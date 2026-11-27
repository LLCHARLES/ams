// Regression for Spotify 9.1.90's unchecked local-image URI parser. Exercise the
// actual fallback resolver with unrelated URLs, malformed URIs and valid covers.
#import <UIKit/UIKit.h>
#import <MediaPlayer/MediaPlayer.h>
#import <objc/runtime.h>
#import "Headers/SPTPlayer.h"
#import "Shared/LocalFiles/LocalFiles.h"
#import "Shared/Player/PlayerState.h"
#import "Native/LocalFiles/LocalCoverFill.h"
#import "Shared/Player/NowPlayingExtras.h"

NSNotificationName const SGNowPlayingInfoDidChangeNotification = @"spotifyglass.nowPlayingInfoDidChange";

#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAILED line %d: %s\n", __LINE__, #c); exit(1); } } while (0)

static NSUInteger legacyCalls, sequence;
@interface NSURL (SGCrashFixture)
- (NSString *)spt_localFileImagePath;
@end
@implementation NSURL (SGCrashFixture)
- (NSString *)spt_localFileImagePath {
    legacyCalls++;
    NSArray *parts = [self.absoluteString componentsSeparatedByString:@":"];
    return [parts[2] stringByRemovingPercentEncoding];
}
@end

@interface SGTestLocalTrack : NSObject
@property(nonatomic, strong) NSURL *URI;
@property(nonatomic, copy) NSDictionary *metadata;
@property(nonatomic, copy) NSString *trackTitle, *artistName;
@end
@implementation SGTestLocalTrack @end
@interface SGTestNowPlaying : NSObject
@property(nonatomic, copy) NSDictionary *nowPlayingInfo;
@end
@implementation SGTestNowPlaying @end
@interface SGTestLocalState : NSObject
@property(nonatomic, strong) SGTestLocalTrack *track;
@end
@implementation SGTestLocalState @end

static SGTestLocalState *state;
static id<SGPlayerStateObserver> observer;
SPTPlayerState *SGPlayerState(void) { return (SPTPlayerState *)state; }
void SGAddPlayerStateObserver(id<SGPlayerStateObserver> value) { observer = value; }
static void play(SGTestLocalTrack *track) {
    state = [SGTestLocalState new];
    state.track = track;
    [observer playerStateDidChange:SGPlayerState()];
}
static void pumpUntil(BOOL (^done)(void)) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:60];
    while (!done() && deadline.timeIntervalSinceNow > 0)
        [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.005]];
    CHECK(done());
}

NSString *SGURIString(id uri) {
    return [uri isKindOfClass:NSURL.class] ? [uri absoluteString] : uri;
}
static SGTestLocalTrack *track(NSDictionary *metadata) {
    SGTestLocalTrack *t = [SGTestLocalTrack new];
    t.URI = [NSURL URLWithString:[NSString stringWithFormat:@"spotify:local:Fixture:Album:Track%lu:60", (unsigned long)++sequence]];
    t.metadata = metadata; t.trackTitle = @"Cover fixture"; t.artistName = @"Fixture artist";
    return t;
}
static UIImage *resolve(SGTestLocalTrack *t) {
    if (state.track != t) play(t);
    return SGLocalFileFallbackCover((SPTPlayerTrack *)t, NULL);
}
static UIImage *awaitCover(SGTestLocalTrack *t) {
    __block UIImage *image;
    pumpUntil(^BOOL { image = resolve(t); return image != nil; });
    return image;
}
int main(void) { @autoreleasepool {
    [NSUserDefaults.standardUserDefaults removeObjectForKey:SGKeyLocalFileEdits];
    SGTestNowPlaying *center = [SGTestNowPlaying new];
    Method getter = class_getClassMethod(MPNowPlayingInfoCenter.class, @selector(defaultCenter));
    IMP replacement = imp_implementationWithBlock(^id(id self) { return center; });
    IMP original = method_setImplementation(getter, replacement);
    // Intercept the production thumbnail reader at its file-URL boundary, retaining real ImageIO
    // decoding. Every read, including a failed read, must enter this boundary off main.
    NSObject *readLock = [NSObject new];
    __block NSString *blockedPath;
    dispatch_semaphore_t entered = dispatch_semaphore_create(0), release = dispatch_semaphore_create(0);
    Method access = class_getInstanceMethod(NSURL.class, @selector(startAccessingSecurityScopedResource));
    IMP accessOriginal = method_getImplementation(access);
    IMP accessReplacement = imp_implementationWithBlock(^BOOL(NSURL *url) {
        CHECK(!NSThread.isMainThread);
        BOOL block;
        @synchronized (readLock) {
            block = [url.path isEqual:blockedPath];
        }
        if (block) {
            dispatch_semaphore_signal(entered);
            CHECK(dispatch_semaphore_wait(release, dispatch_time(DISPATCH_TIME_NOW, 120 * NSEC_PER_SEC)) == 0);
        }
        return ((BOOL (*)(id, SEL))accessOriginal)(url, @selector(startAccessingSecurityScopedResource));
    });
    method_setImplementation(access, accessReplacement);
    // Catch the former synchronous UIImage path too, not just the ImageIO implementation.
    Method contents = class_getClassMethod(UIImage.class, @selector(imageWithContentsOfFile:));
    IMP contentsOriginal = method_getImplementation(contents);
    IMP contentsReplacement = imp_implementationWithBlock(^UIImage *(id self, NSString *path) {
        CHECK(!NSThread.isMainThread);
        return ((id (*)(id, SEL, id))contentsOriginal)(self, @selector(imageWithContentsOfFile:), path);
    });
    method_setImplementation(contents, contentsReplacement);
    @try {
        for (id address in @[@"cover.jpg", @"https://example.invalid/cover.jpg",
                [NSURL URLWithString:@"https://example.invalid/cover.jpg"],
                @"spotify:image:abc", @"spotify:localfileimage", @"spotify:localfileimage:",
                @"spotify:localfileimage:relative.jpg", @"spotify:localfileimage:/tmp/a:b.jpg",
                @42, NSNull.null]) {
            CHECK(!resolve(track(@{@"image_xlarge_url": address})));
        }
        UIImage *image = [[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(4, 4)]
            imageWithActions:^(UIGraphicsImageRendererContext *context) {
                [UIColor.redColor setFill]; UIRectFill(CGRectMake(0, 0, 4, 4));
            }];
        NSString *file = [NSProcessInfo.processInfo.environment[@"CFFIXED_USER_HOME"]
            stringByAppendingPathComponent:[NSUUID.UUID.UUIDString stringByAppendingString:@" local cover: artwork.png"]];
        CHECK([UIImagePNGRepresentation(image) writeToFile:file atomically:YES]);
        for (id address in @[file, [NSURL fileURLWithPath:file], SGLocalFileCoverURL(file),
                [NSURL URLWithString:SGLocalFileCoverURL(file)], image]) {
            CHECK(awaitCover(track(@{@"image_xlarge_url": address})).CGImage);
        }
        CHECK(awaitCover(track(@{@"image_xlarge_url": @"cover.jpg", @"image_small_url": file})).CGImage);
        SGTestLocalTrack *cached = track(@{@"image_url": file});
        UIImage *cachedImage = awaitCover(cached);
        // Removing the backing file must not disturb subsequent layouts of this playing track.
        CHECK([NSFileManager.defaultManager removeItemAtPath:file error:nil]);
        CHECK(resolve(cached) == cachedImage);
        SGTestLocalTrack *failed = track(@{@"image_url": file});
        CHECK(!resolve(failed));
        // A FIFO worker request on another path confirms the failed read has completed.
        NSString *barrierFile = [file stringByAppendingString:@".barrier.png"];
        CHECK([UIImagePNGRepresentation(image) writeToFile:barrierFile atomically:YES]);
        failed.metadata = @{@"image_url": file, @"image_small_url": barrierFile};
        CHECK(awaitCover(failed).CGImage);
        CHECK([UIImagePNGRepresentation(image) writeToFile:file atomically:YES]);
        failed.metadata = @{@"image_url": file};
        // Exercise later layouts beyond the old one-second retry window.
        [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1.1]];
        CHECK(!resolve(failed));
        NSString *retryBarrier = [file stringByAppendingString:@".retry.png"];
        CHECK([UIImagePNGRepresentation(image) writeToFile:retryBarrier atomically:YES]);
        failed.metadata = @{@"image_url": file, @"image_small_url": retryBarrier};
        CHECK(awaitCover(failed).CGImage);
        failed.metadata = @{@"image_url": file};
        CHECK(!resolve(failed));
        [NSFileManager.defaultManager removeItemAtPath:retryBarrier error:nil];
        SGTestLocalTrack *revisited = track(@{@"image_url": file});
        CHECK(awaitCover(revisited).CGImage);
        // A pending read from A must not publish after A -> B -> A, even without intervening layouts.
        @synchronized (readLock) { blockedPath = file; }
        SGTestLocalTrack *pending = track(@{@"image_url": file});
        CHECK(!resolve(pending));
        CHECK(dispatch_semaphore_wait(entered, dispatch_time(DISPATCH_TIME_NOW, 60 * NSEC_PER_SEC)) == 0);
        play(track(@{}));
        play(pending);
        __block NSUInteger publications = 0;
        id token = [NSNotificationCenter.defaultCenter addObserverForName:SGLocalFileFallbackCoverDidChangeNotification
            object:nil queue:nil usingBlock:^(NSNotification *note) {
                CHECK(NSThread.isMainThread);
                if ([note.object isEqual:pending.URI.absoluteString]) publications++;
            }];
        @synchronized (readLock) { blockedPath = nil; }
        dispatch_semaphore_signal(release);
        // A new-path request completes behind the old one; do not request the old path again yet.
        pending.metadata = @{@"image_url": barrierFile};
        CHECK(awaitCover(pending).CGImage);
        // Only the new request's notification is legitimate.
        CHECK(publications == 1);
        [NSNotificationCenter.defaultCenter removeObserver:token];
        // Check stale publication independently with the old path removed: a stale cache would return it.
        CHECK([NSFileManager.defaultManager removeItemAtPath:file error:nil]);
        pending.metadata = @{@"image_url": file};
        CHECK(!resolve(pending));
        CHECK(awaitCover(track(@{@"image_url": barrierFile})).CGImage);
        [NSFileManager.defaultManager removeItemAtPath:barrierFile error:nil];
        SGTestLocalTrack *fallback = track(@{@"image_url": @"cover.jpg"});
        center.nowPlayingInfo = @{MPMediaItemPropertyTitle: fallback.trackTitle,
            MPMediaItemPropertyArtist: fallback.artistName,
            MPMediaItemPropertyArtwork: [[MPMediaItemArtwork alloc] initWithBoundsSize:image.size
                requestHandler:^UIImage *(CGSize size) { return image; }]};
        CHECK(resolve(fallback).CGImage);
        // Native publication must upgrade provisional red system artwork to the blue metadata
        // thumbnail, while leaving an image Spotify installed over our placeholder untouched.
        UIImage *blue = [[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(4, 4)]
            imageWithActions:^(UIGraphicsImageRendererContext *context) {
                [UIColor.blueColor setFill]; UIRectFill(CGRectMake(0, 0, 4, 4));
            }];
        CHECK([UIImagePNGRepresentation(blue) writeToFile:file atomically:YES]);
        @synchronized (readLock) { blockedPath = file; }
        SGTestLocalTrack *upgrade = track(@{@"image_url": file});
        play(upgrade);
        UIImageView *provisional = [UIImageView new], *spotify = [UIImageView new];
        SGLocalCoverFill(provisional);
        SGLocalCoverFill(spotify);
        CHECK(provisional.image == image);
        spotify.image = blue; // Spotify takes ownership while the metadata read is still pending.
        CHECK(dispatch_semaphore_wait(entered, dispatch_time(DISPATCH_TIME_NOW, 60 * NSEC_PER_SEC)) == 0);
        __block BOOL refreshed = NO;
        id refresh = [NSNotificationCenter.defaultCenter addObserverForName:SGLocalFileFallbackCoverDidChangeNotification
            object:nil queue:nil usingBlock:^(NSNotification *note) {
                if (![note.object isEqual:upgrade.URI.absoluteString]) return;
                SGLocalCoverFill(provisional);
                SGLocalCoverFill(spotify);
                refreshed = YES;
            }];
        @synchronized (readLock) { blockedPath = nil; }
        dispatch_semaphore_signal(release);
        pumpUntil(^BOOL { return refreshed; });
        [NSNotificationCenter.defaultCenter removeObserver:refresh];
        uint8_t pixel[4] = {0};
        CGColorSpaceRef rgb = CGColorSpaceCreateDeviceRGB();
        CGContextRef bitmap = CGBitmapContextCreate(pixel, 1, 1, 8, 4, rgb,
            kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
        CGContextDrawImage(bitmap, CGRectMake(0, 0, 1, 1), provisional.image.CGImage);
        CGContextRelease(bitmap);
        CGColorSpaceRelease(rgb);
        CHECK(pixel[0] == 0 && pixel[1] == 0 && pixel[2] == 255 && pixel[3] == 255);
        CHECK(spotify.image == blue);
        // System artwork is provisional: the previous track's artwork agrees by title and artist and is
        // taken, then replaced when the now playing info holds the new track's own artwork. Info that
        // stops agreeing with the track gives nothing.
        MPMediaItemArtwork *previousArtwork = [[MPMediaItemArtwork alloc] initWithBoundsSize:image.size
            requestHandler:^UIImage *(CGSize size) { return image; }];
        MPMediaItemArtwork *nextArtwork = [[MPMediaItemArtwork alloc] initWithBoundsSize:blue.size
            requestHandler:^UIImage *(CGSize size) { return blue; }];
        SGTestLocalTrack *albumOne = track(@{}), *albumTwo = track(@{});
        center.nowPlayingInfo = @{MPMediaItemPropertyTitle: albumOne.trackTitle,
            MPMediaItemPropertyArtist: albumOne.artistName, MPMediaItemPropertyArtwork: previousArtwork};
        CHECK(resolve(albumOne) == image);
        CHECK(resolve(albumTwo) == image);
        center.nowPlayingInfo = @{MPMediaItemPropertyTitle: albumTwo.trackTitle,
            MPMediaItemPropertyArtist: albumTwo.artistName, MPMediaItemPropertyArtwork: nextArtwork};
        CHECK(resolve(albumTwo) == blue);
        center.nowPlayingInfo = @{MPMediaItemPropertyTitle: @"Another song",
            MPMediaItemPropertyArtist: albumTwo.artistName, MPMediaItemPropertyArtwork: nextArtwork};
        CHECK(!resolve(albumTwo));
        center.nowPlayingInfo = nil;
        SGTestLocalTrack *edited = track(@{@"image_url": @"cover.jpg"});
        SGLocalFileSaveEdit(edited.URI.absoluteString, @{}, image, YES);
        CHECK(!resolve(edited));
        SGLocalFileSaveEdit(edited.URI.absoluteString, @{}, nil, NO);
        SGTestLocalTrack *remote = track(@{@"image_url": @"cover.jpg"});
        remote.URI = [NSURL URLWithString:@"spotify:track:4uLU6hMCjMI75M1A2tKUQC"];
        CHECK(!resolve(remote));
        CHECK(legacyCalls == 0);
        [NSFileManager.defaultManager removeItemAtPath:file error:nil];
        puts("PASS: local covers; worker-only bounded reads, cached layouts, remembered failures, stale A/B/A replies, safe URL parsing and system/edited cover fallback");
    } @catch (NSException *exception) {
        fprintf(stderr, "FAIL: local cover resolver raised %s: %s\n", exception.name.UTF8String, exception.reason.UTF8String);
        return 1;
    } @finally {
        method_setImplementation(getter, original);
        imp_removeBlock(replacement);
        method_setImplementation(access, accessOriginal);
        imp_removeBlock(accessReplacement);
        method_setImplementation(contents, contentsOriginal);
        imp_removeBlock(contentsReplacement);
    }
    return 0;
} }
