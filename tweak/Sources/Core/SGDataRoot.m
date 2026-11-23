#import "SGDataRoot.h"
#import <sys/stat.h>

// ENOENT alone means absent. In particular, don't follow a link and treat its target
// as a host library, or create a new library because the old one could not be inspected.
static BOOL inspect(NSURL *url, struct stat *st) {
    if (lstat(url.fileSystemRepresentation, st) == 0) {
        if (S_ISDIR(st->st_mode)) return YES;
        NSLog(@"[spotifyglass] storage: not a directory: %@", url.path);
    } else if (errno == ENOENT) {
        st->st_mode = 0;
        return YES;
    } else NSLog(@"[spotifyglass] storage: cannot inspect %@: %s", url.path, strerror(errno));
    return NO;
}

static BOOL markRetired(NSURL *marker, NSURL *old) {
    NSError *error = nil;
    if ([NSFileManager.defaultManager createDirectoryAtURL:marker withIntermediateDirectories:YES attributes:nil error:&error]) return YES;
    NSLog(@"[spotifyglass] storage: cannot retire %@: %@", old.path, error);
    return NO;
}

static NSURL *resolve(NSSearchPathDirectory directory) {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSURL *base = [fm URLsForDirectory:directory inDomains:NSUserDomainMask].firstObject;
    if (!base) return nil;
    // Preserve the migration source path for existing installs.
    NSURL *old = [base URLByAppendingPathComponent:@"Vitrine" isDirectory:YES];
    NSURL *new = [base URLByAppendingPathComponent:@"Retrine" isDirectory:YES];
    // The receipt must survive deleting the active root, including purging Caches.
    NSURL *support = [fm URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;
    NSURL *retired = [support URLByAppendingPathComponent:[NSString stringWithFormat:@".retrine-migration/retired-%lu", (unsigned long)directory] isDirectory:YES];
    BOOL raced = NO;
    for (;;) {
        struct stat a, b, marker;
        if (!inspect(old, &a) || !inspect(new, &b)) return nil;
        if (!a.st_mode) return new;
        if (!retired || !inspect(retired, &marker)) return nil;
        if (b.st_mode || marker.st_mode) {
            if (!marker.st_mode && !markRetired(retired, old)) return nil;
            NSLog(@"[spotifyglass] storage: leaving previous library untouched at %@", old.path);
            return new;
        }
        if (raced) return old; // The competing destination disappeared again. Retry next launch.
        if (!renamex_np(old.fileSystemRepresentation, new.fileSystemRepresentation, RENAME_EXCL))
            return markRetired(retired, old) ? new : nil;
        int failure = errno;
        if (failure == EEXIST) { raced = YES; continue; }
        struct stat remaining;
        if (!inspect(old, &remaining) || !remaining.st_mode || a.st_dev != remaining.st_dev || a.st_ino != remaining.st_ino)
            return nil;
        NSLog(@"[spotifyglass] storage: keeping %@ this launch (rename: %s)", old.path, strerror(failure));
        return old;
    }
}

NSURL *SGDataRoot(NSSearchPathDirectory directory) {
    NSUInteger index;
    switch (directory) {
        case NSApplicationSupportDirectory: index = 0; break;
        case NSCachesDirectory: index = 1; break;
        case NSDocumentDirectory: index = 2; break;
        default: return nil;
    }
    static dispatch_once_t once[3];
    static NSURL *roots[3];
    dispatch_once(&once[index], ^{ roots[index] = resolve(directory); });
    return roots[index];
}
