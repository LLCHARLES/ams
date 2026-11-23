#import "LyricRetirement.h"
#import <sys/stat.h>
#import <unistd.h>

static NSDictionary *identity(NSURL *url, struct stat st) {
    return @{@"name":url.lastPathComponent, @"device":@(st.st_dev), @"inode":@(st.st_ino),
        @"birth":@(st.st_birthtimespec.tv_sec), @"birthNS":@(st.st_birthtimespec.tv_nsec),
        @"modified":@(st.st_mtimespec.tv_sec), @"modifiedNS":@(st.st_mtimespec.tv_nsec), @"size":@(st.st_size)};
}

BOOL SGWriteImportedLyric(NSString *text, NSURL *url, NSDictionary **receipt, NSError **error) {
    __block BOOL written = NO;
    __block NSError *failure = nil;
    __block NSDictionary *proof = nil;
    [[NSFileCoordinator new] coordinateWritingItemAtURL:url options:0 error:error byAccessor:^(NSURL *target) {
        struct stat st;
        if (!lstat(target.fileSystemRepresentation, &st) || errno != ENOENT) {
            failure = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileWriteFileExistsError userInfo:nil];
            return;
        }
        written = [text writeToURL:target atomically:YES encoding:NSUTF8StringEncoding error:&failure];
        if (written && !lstat(target.fileSystemRepresentation, &st) && S_ISREG(st.st_mode)) proof = identity(target, st);
    }];
    if (failure && error) *error = failure;
    *receipt = proof;
    return written;
}

BOOL SGRemoveRetiredLyric(NSURL *folder, id receipt, BOOL *removed) {
    *removed = NO;
    // Old name-only retirements cannot authorize deletion, even if that name exists today.
    NSString *name = [receipt isKindOfClass:NSDictionary.class] ? receipt[@"name"] : nil;
    if (![name isKindOfClass:NSString.class] || !name.length || ![name isEqual:name.lastPathComponent] ||
        [name isEqual:@"."] || [name isEqual:@".."] || [name isEqual:@"/"]) return YES;
    NSURL *url = [folder URLByAppendingPathComponent:name];
    __block BOOL done = NO, deleted = NO;
    // Claim an ordinary write: until identity is checked inside the accessor this
    // may be somebody else's document. Do not tell its presenter to close it.
    [[NSFileCoordinator new] coordinateWritingItemAtURL:url options:0 error:nil byAccessor:^(NSURL *target) {
        struct stat st;
        if (lstat(target.fileSystemRepresentation, &st)) { done = errno == ENOENT; return; }
        if (!S_ISREG(st.st_mode) || ![receipt isEqual:identity(target, st)]) { done = YES; return; }
        done = deleted = unlink(target.fileSystemRepresentation) == 0;
    }];
    *removed = deleted;
    return done;
}
