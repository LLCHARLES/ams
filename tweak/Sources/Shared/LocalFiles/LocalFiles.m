// LocalFiles.h says what is kept and why the file is not written.
//
// Threading: the edits are read on whatever thread Spotify reads a track's metadata on, so the table is
// swapped whole under a lock; they are written on the main thread.
#import <os/lock.h>
#import <ImageIO/ImageIO.h>
#import "Core/SGCore.h"
#import "Core/SGDataRoot.h"
#import "LocalFiles.h"

static NSString *const kLocalPrefix = @"spotify:local:";
// A cover is kept no larger than this on its longer side; the player draws it at under half that.
static const CGFloat kCoverSide = 1200;

NSNotificationName const SGLocalFileEditsDidChangeNotification = @"spotifyglass.localFiles.editsDidChange";

static NSDictionary<NSString *, NSDictionary *> *sg_edits;
static os_unfair_lock sg_lock = OS_UNFAIR_LOCK_INIT;

BOOL SGLocalFileIs(NSString *uri) {
    return [uri isKindOfClass:NSString.class] && [uri hasPrefix:kLocalPrefix];
}

// nil means unknown/unavailable, not an authoritative empty collection. In particular a locked
// launch must not permanently cache an empty table.
static NSDictionary *readStoredEdits(void) {
    if (!UIApplication.sharedApplication.isProtectedDataAvailable) return nil;
    id stored = [NSUserDefaults.standardUserDefaults objectForKey:SGKeyLocalFileEdits];
    if (![stored isKindOfClass:NSDictionary.class]) return nil;
    for (id edit in [stored allValues]) {
        if (![edit isKindOfClass:NSDictionary.class]) return nil;
        id cover = edit[@"cover"];
        if (cover && (![cover isKindOfClass:NSString.class] || ![cover length] ||
                      ![cover isEqual:[cover lastPathComponent]])) return nil;
    }
    return UIApplication.sharedApplication.isProtectedDataAvailable ? stored : nil;
}

static NSDictionary<NSString *, NSDictionary *> *allEdits(void) {
    os_unfair_lock_lock(&sg_lock);
    NSDictionary *edits = sg_edits;
    os_unfair_lock_unlock(&sg_lock);
    if (edits) return edits;
    NSDictionary *stored = readStoredEdits();
    if (!stored) return @{}; // a temporary read result only; retry after data becomes available
    os_unfair_lock_lock(&sg_lock);
    if (!sg_edits) sg_edits = stored; // do not overwrite a concurrent publication
    edits = sg_edits;
    os_unfair_lock_unlock(&sg_lock);
    return edits;
}

static void storeEdits(NSDictionary<NSString *, NSDictionary *> *edits) {
    os_unfair_lock_lock(&sg_lock);
    sg_edits = [edits copy];
    os_unfair_lock_unlock(&sg_lock);
    if (edits.count) [NSUserDefaults.standardUserDefaults setObject:edits forKey:SGKeyLocalFileEdits];
    else [NSUserDefaults.standardUserDefaults removeObjectForKey:SGKeyLocalFileEdits];
}

NSDictionary<NSString *, id> *SGLocalFileEditFor(NSString *uri) {
    if (!SGLocalFileIs(uri)) return nil;
    id edit = allEdits()[uri];
    return [edit isKindOfClass:NSDictionary.class] ? edit : nil;
}

NSString *SGLocalFileLyricsKey(NSString *uri) {
    if (!SGLocalFileIs(uri)) return nil;
    id number = SGLocalFileEditFor(uri)[@"number"];
    return number ? [NSString stringWithFormat:@"%@#%@", uri, number] : uri;
}

#pragma mark - the URI's own names

// Form encoded: "+" is a space and the rest percent escapes, so a part never holds a raw ":".
static NSString *decoded(NSString *part) {
    NSString *spaced = [part stringByReplacingOccurrencesOfString:@"+" withString:@" "];
    return spaced.stringByRemovingPercentEncoding ?: spaced;
}

NSDictionary<NSString *, id> *SGLocalFileTags(NSString *uri) {
    if (!SGLocalFileIs(uri)) return nil;
    NSArray<NSString *> *parts = [[uri substringFromIndex:kLocalPrefix.length] componentsSeparatedByString:@":"];
    if (parts.count != 4) return nil;
    NSMutableDictionary<NSString *, id> *tags = [NSMutableDictionary dictionary];
    NSString *artist = decoded(parts[0]), *album = decoded(parts[1]), *title = decoded(parts[2]);
    if (title.length) tags[@"title"] = title;
    if (artist.length) tags[@"artist"] = artist;
    if (album.length) tags[@"album"] = album;
    // A lyrics key carries "#<number>" after the seconds, which integerValue stops at.
    tags[@"seconds"] = @(MAX(parts[3].integerValue, 0));
    return tags;
}

NSDictionary<NSString *, id> *SGLocalFileInfo(NSString *uri) {
    NSDictionary *tags = SGLocalFileTags(uri);
    if (!tags) return nil;
    NSRange mark = [uri rangeOfString:@"#" options:NSBackwardsSearch];
    NSDictionary *edit = SGLocalFileEditFor(mark.location == NSNotFound ? uri : [uri substringToIndex:mark.location]);
    if (!edit) return tags;
    NSMutableDictionary<NSString *, id> *info = [tags mutableCopy];
    for (NSString *field in @[@"title", @"artist", @"album"]) {
        if ([edit[field] length]) info[field] = edit[field];
    }
    return info;
}

#pragma mark - storing an edit

NSString *SGLocalFileCoversDirectory(void) {
    return [SGDataRoot(NSApplicationSupportDirectory).path stringByAppendingPathComponent:@"Local file covers"];
}

NSString *SGLocalFileCoverPath(NSDictionary<NSString *, id> *edit) {
    NSString *name = edit[@"cover"];
    return [name isKindOfClass:NSString.class] && name.length ? [SGLocalFileCoversDirectory() stringByAppendingPathComponent:name] : nil;
}

static NSString *const kImagePrefix = @"spotify:localfileimage:";

NSString *SGLocalFileCoverURL(NSString *path) {
    static NSCharacterSet *allowed;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableCharacterSet *set = [NSCharacterSet.URLPathAllowedCharacterSet mutableCopy];
        // -[NSURL spotifyURIComponents] splits the address on ":"; "/" goes too, so the path is one plain part.
        [set removeCharactersInString:@":/"];
        allowed = set;
    });
    NSString *escaped = [path stringByAddingPercentEncodingWithAllowedCharacters:allowed];
    return escaped ? [kImagePrefix stringByAppendingString:escaped] : nil;
}

NSString *SGLocalFileCoverInURL(NSString *url) {
    if (![url isKindOfClass:NSString.class] || ![url hasPrefix:kImagePrefix]) return nil;
    NSString *path = [url substringFromIndex:kImagePrefix.length].stringByRemovingPercentEncoding;
    NSString *directory = [SGLocalFileCoversDirectory() stringByAppendingString:@"/"];
    // Only a file of the covers' own, by its name alone, so no address reaches anything else.
    if (!directory || ![path hasPrefix:directory] || [path substringFromIndex:directory.length].pathComponents.count != 1) return nil;
    return path;
}

static UIImage *readCoverSource(CGImageSourceRef source) {
        if (!source) return nil;
        CGImageRef thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, (__bridge CFDictionaryRef)@{
            (id)kCGImageSourceCreateThumbnailFromImageAlways: @YES,
            (id)kCGImageSourceCreateThumbnailWithTransform: @YES,
            (id)kCGImageSourceThumbnailMaxPixelSize: @(kCoverSide),
            (id)kCGImageSourceShouldCacheImmediately: @YES,
        });
        CFRelease(source);
        if (!thumbnail) return nil;
        UIImage *image = [UIImage imageWithCGImage:thumbnail];
        CGImageRelease(thumbnail);
        return image;
}

UIImage *SGLocalFileReadCoverData(NSData *data) {
    if (!data.length) return nil;
    return readCoverSource(CGImageSourceCreateWithData((__bridge CFDataRef)data,
        (__bridge CFDictionaryRef)@{(id)kCGImageSourceShouldCache: @NO}));
}

UIImage *SGLocalFileReadCover(NSURL *url) {
    if (!url) return nil;
    BOOL scoped = [url startAccessingSecurityScopedResource];
    @try {
        return readCoverSource(CGImageSourceCreateWithURL((__bridge CFURLRef)url,
            (__bridge CFDictionaryRef)@{(id)kCGImageSourceShouldCache: @NO}));
    } @finally {
        if (scoped) [url stopAccessingSecurityScopedResource];
    }
}

UIImage *SGLocalFileThumbnail(UIImage *image) {
    if (!image || image.size.width <= 0 || image.size.height <= 0) return nil;
    CGFloat scale = MIN(1, kCoverSide / MAX(image.size.width, image.size.height));
    CGSize size = CGSizeMake(round(image.size.width * scale), round(image.size.height * scale));
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat preferredFormat];
    format.scale = 1;
    format.opaque = YES;
    return [[[UIGraphicsImageRenderer alloc] initWithSize:size format:format] imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [image drawInRect:(CGRect){CGPointZero, size}];
    }];
}

static dispatch_queue_t coverQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        queue = dispatch_queue_create("spotifyglass.localFiles.covers", DISPATCH_QUEUE_SERIAL);
    });
    return queue;
}

void SGLocalFileLoadCover(NSString *uri, void (^completion)(UIImage *)) {
    NSString *path = SGLocalFileCoverPath(SGLocalFileEditFor(uri));
    dispatch_async(coverQueue(), ^{
        UIImage *image = path ? SGLocalFileReadCover([NSURL fileURLWithPath:path]) : nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            NSString *current = SGLocalFileCoverPath(SGLocalFileEditFor(uri));
            completion([path isEqualToString:current] ? image : nil);
        });
    });
}

static NSString *writeCover(UIImage *image) {
    NSData *data = UIImageJPEGRepresentation(SGLocalFileThumbnail(image), 0.9);
    NSString *name = [NSUUID.UUID.UUIDString stringByAppendingPathExtension:@"jpg"];
    NSError *error = nil;
    [NSFileManager.defaultManager createDirectoryAtPath:SGLocalFileCoversDirectory() withIntermediateDirectories:YES attributes:nil error:&error];
    if (!data || ![data writeToFile:[SGLocalFileCoversDirectory() stringByAppendingPathComponent:name] options:NSDataWritingAtomic error:&error]) {
        SGLog(@"local files: the cover was not written: %@", error);
        return nil;
    }
    return name;
}

static void changed(NSString *uri) {
    [NSNotificationCenter.defaultCenter postNotificationName:SGLocalFileEditsDidChangeNotification object:uri];
}

void SGLocalFileSaveEdit(NSString *uri, NSDictionary<NSString *, NSString *> *names, UIImage *cover, BOOL keepCover) {
    if (!SGLocalFileIs(uri) || !SGLocalFileCoversDirectory()) return;
    NSDictionary *tags = SGLocalFileTags(uri), *old = SGLocalFileEditFor(uri);
    NSMutableDictionary<NSString *, id> *edit = [NSMutableDictionary dictionary];
    for (NSString *field in @[@"title", @"artist", @"album"]) {
        NSString *name = [names[field] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (name.length && ![name isEqualToString:tags[field]]) edit[field] = name;
    }
    NSString *oldCover = SGLocalFileCoverPath(old);
    NSString *newCover = cover ? writeCover(cover) : nil;
    if (newCover) edit[@"cover"] = newCover;
    else if (keepCover && oldCover) edit[@"cover"] = old[@"cover"];

    // The lyrics key changes with the names only: a cover alone leaves the lyrics where they are, and the
    // file's own names go back to the bare URI, whose lyrics may still be kept.
    BOOL named = NO, renamed = NO;
    for (NSString *field in @[@"title", @"artist", @"album"]) {
        named = named || edit[field];
        renamed = renamed || !(edit[field] == old[field] || [edit[field] isEqual:old[field]]);
    }
    // Milliseconds, so no two renames of a track share a lyrics key, a reset in between or not.
    if (named) edit[@"number"] = renamed || !old[@"number"] ? @((long long)(NSDate.date.timeIntervalSince1970 * 1000)) : old[@"number"];

    NSMutableDictionary *edits = [allEdits() mutableCopy];
    if (edit.count) {
        edits[uri] = edit;
    } else {
        [edits removeObjectForKey:uri];
    }
    storeEdits(edits);
    if (oldCover && ![edit[@"cover"] isEqual:old[@"cover"]]) [NSFileManager.defaultManager removeItemAtPath:oldCover error:nil];
    SGLog(@"local files: %@ %@", uri, edit.count ? [NSString stringWithFormat:@"edited: %@", edit] : @"back to its own tags");
    changed(uri);
}
