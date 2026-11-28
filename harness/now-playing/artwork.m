// Production Logos control flow and follower; only sources, rendering and the OS boundary are stubs.
#import <MediaPlayer/MediaPlayer.h>
#import <objc/runtime.h>
#import <CommonCrypto/CommonDigest.h>
#import "artwork.h"
#import "Shared/Fonts/Fonts.h"
#import "../sha256-fixture.h"
#import "Shared/AnimatedArtwork/AnimatedArtwork.h"
#import "Shared/AnimatedArtwork/SGFluidClip.h"
#import "Shared/AnimatedArtwork/SGMotionClip.h"
#import "Shared/LockScreenLyrics/LockScreenLyrics.h"
#import "Shared/LockScreenLyrics/SGLyricsClip.h"
#import "Shared/Lyrics/Lyrics.h"
#import "Shared/LyricsTranslation/LyricsTranslation.h"
#import "Shared/Player/PlayerState.h"
#import "Shared/Player/NowPlayingExtras.h"
#import "Shared/Player/SGLastTrack.h"

typedef void (^Preview)(CGSize, void (^)(UIImage *));
typedef void (^Video)(CGSize, void (^)(NSURL *));
static char idKey, previewKey, videoKey;
static NSArray *supported;
static NSURL *cacheRoot;
static BOOL holdLyricsCleanup, cleanupGateTimedOut;
static dispatch_semaphore_t cleanupEntered, cleanupRelease;
static NSUInteger completedLyricsCleanups;
NSNotificationName const SGLyricsAIResultDidChangeNotification = @"spotifyglass.lyricsAIResultDidChange";
static CGSize lastCoverRequest;
static NSUInteger nativeAcquisitions;
static CGRect screenBounds(id self, SEL cmd) { return CGRectMake(0, 0, 32, 48); }

// Exercise the real metadata -> SGShownTrack -> URL loader -> decode boundary, not an
// SGShownTrackArtwork stub. Only the transport is controlled; no network leaves this process.
static NSMutableDictionary<NSString *, NSURLProtocol *> *coverRequests;
static NSUInteger coverLoads;
static NSMutableDictionary<NSString *, NSNumber *> *coverCompletions;
@interface CoverProtocol : NSURLProtocol
@end
@implementation CoverProtocol
+ (BOOL)canInitWithRequest:(NSURLRequest *)request { return [request.URL.host isEqual:@"cover.invalid"]; }
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request { return request; }
- (void)startLoading {
    dispatch_async(dispatch_get_main_queue(), ^{
        coverLoads++;
        coverRequests[self.request.URL.absoluteString] = self;
    });
}
- (void)stopLoading {}
@end

// Keep Apple's real object and initializer, but retain the supplied handlers so tests can act as the OS.
@interface MPMediaItemAnimatedArtwork (Harness)
- (instancetype)initHarnessWithArtworkID:(NSString *)name previewImageRequestHandler:(Preview)preview
        videoAssetFileURLRequestHandler:(Video)video;
@end
@implementation MPMediaItemAnimatedArtwork (Harness)
- (instancetype)initHarnessWithArtworkID:(NSString *)name previewImageRequestHandler:(Preview)preview
        videoAssetFileURLRequestHandler:(Video)video {
    self = [self initHarnessWithArtworkID:name previewImageRequestHandler:preview videoAssetFileURLRequestHandler:video];
    if (self) {
        objc_setAssociatedObject(self, &idKey, name, OBJC_ASSOCIATION_COPY_NONATOMIC);
        objc_setAssociatedObject(self, &previewKey, preview, OBJC_ASSOCIATION_COPY_NONATOMIC);
        objc_setAssociatedObject(self, &videoKey, video, OBJC_ASSOCIATION_COPY_NONATOMIC);
    }
    return self;
}
@end

@interface NSFileManager (Harness)
- (NSArray *)harnessURLsForDirectory:(NSSearchPathDirectory)directory inDomains:(NSSearchPathDomainMask)domains;
- (BOOL)harnessRemoveItemAtURL:(NSURL *)url error:(NSError **)error;
@end
@implementation NSFileManager (Harness)
- (NSArray *)harnessURLsForDirectory:(NSSearchPathDirectory)directory inDomains:(NSSearchPathDomainMask)domains {
    if (directory == NSCachesDirectory) return @[cacheRoot];
    return [self harnessURLsForDirectory:directory inDomains:domains];
}
- (BOOL)harnessRemoveItemAtURL:(NSURL *)url error:(NSError **)error {
    BOOL lyrics = [url.path isEqual:[cacheRoot.path stringByAppendingPathComponent:@"Retrine/Lyrics"]];
    BOOL hold = NO;
    if (lyrics) {
        @synchronized (cacheRoot) {
            hold = holdLyricsCleanup;
            holdLyricsCleanup = NO;
        }
    }
    if (hold) {
        dispatch_semaphore_signal(cleanupEntered);
        BOOL timedOut = dispatch_semaphore_wait(cleanupRelease, dispatch_time(DISPATCH_TIME_NOW, HarnessWaitSeconds * (int64_t)NSEC_PER_SEC)) != 0;
        @synchronized (cacheRoot) { cleanupGateTimedOut = timedOut; }
    }
    BOOL removed = [self harnessRemoveItemAtURL:url error:error];
    if (lyrics) {
        @synchronized (cacheRoot) { completedLyricsCleanups++; }
    }
    return removed;
}
@end

static NSArray *keys(id self, SEL cmd) { return supported ?: @[]; }
static void alreadyPlaying(void);
__attribute__((constructor)) static void artworkBoundary(void) {
    coverRequests = [NSMutableDictionary dictionary];
    [NSURLProtocol registerClass:CoverProtocol.class];
    coverCompletions = [NSMutableDictionary dictionary];
    // NSURLProtocol finishing the transport is not SGShownTrackArtwork finishing
    // decode. Its URLSession completion enqueues the decoded reply on main.
    Method load = class_getInstanceMethod(NSURLSession.sharedSession.class, @selector(dataTaskWithURL:completionHandler:));
    IMP loadIMP = method_getImplementation(load);
    method_setImplementation(load, imp_implementationWithBlock(^NSURLSessionDataTask *(NSURLSession *session, NSURL *url,
            void (^completion)(NSData *, NSURLResponse *, NSError *)) {
        if ([url.host isEqual:@"cover.invalid"]) {
            void (^consume)(NSData *, NSURLResponse *, NSError *) = completion;
            completion = ^(NSData *data, NSURLResponse *response, NSError *error) {
                consume(data, response, error);
                dispatch_async(dispatch_get_main_queue(), ^{
                    coverCompletions[url.absoluteString] = @([coverCompletions[url.absoluteString] unsignedIntegerValue] + 1);
                });
            };
        }
        return ((NSURLSessionDataTask *(*)(id, SEL, NSURL *, id))loadIMP)(session, @selector(dataTaskWithURL:completionHandler:), url, completion);
    }));
    char *path = strdup([[NSTemporaryDirectory() stringByAppendingPathComponent:@"retrine-artwork.XXXXXX"] fileSystemRepresentation]);
    if (!mkdtemp(path)) { perror("mkdtemp artwork cache"); exit(1); }
    cacheRoot = [NSURL fileURLWithPath:@(path) isDirectory:YES];
    free(path);
    method_exchangeImplementations(class_getInstanceMethod(NSFileManager.class, @selector(URLsForDirectory:inDomains:)),
                                   class_getInstanceMethod(NSFileManager.class, @selector(harnessURLsForDirectory:inDomains:)));
    method_exchangeImplementations(class_getInstanceMethod(NSFileManager.class, @selector(removeItemAtURL:error:)),
                                   class_getInstanceMethod(NSFileManager.class, @selector(harnessRemoveItemAtURL:error:)));
    class_replaceMethod(object_getClass(MPNowPlayingInfoCenter.class), @selector(supportedAnimatedArtworkKeys), (IMP)keys, "@@:");
    Method bounds = class_getInstanceMethod(UIScreen.class, @selector(nativeBounds));
    class_replaceMethod(UIScreen.class, @selector(nativeBounds), (IMP)screenBounds, method_getTypeEncoding(bounds));
    method_exchangeImplementations(class_getInstanceMethod(MPMediaItemAnimatedArtwork.class,
                                       @selector(initWithArtworkID:previewImageRequestHandler:videoAssetFileURLRequestHandler:)),
                                   class_getInstanceMethod(MPMediaItemAnimatedArtwork.class,
                                       @selector(initHarnessWithArtworkID:previewImageRequestHandler:videoAssetFileURLRequestHandler:)));
    alreadyPlaying();
}

static SGLockArtwork choice;
static NSHashTable *observers;
static SPTPlayerState *state;
static NSInteger position;
static NSUInteger lookups, posters;
static NSURL *sourceFile;
static NSMutableArray *posterCallbacks;
static UIImage *red, *blue;
static void alreadyPlaying(void) {
    // This boundary constructor runs before LockScreenMotion's, with no observer replay.
    state = harnessState(@"spotify:track:already-playing", @"Song");
    choice = SGLockArtworkMotion;
    sourceFile = [cacheRoot URLByAppendingPathComponent:@"already-playing.mp4"];
}
// Hold one production background worker before it renders, without replacing the renderer or
// changing delivery order on main. Guard the gate and preparation counter across both threads.
static NSString *heldPicture;
static dispatch_semaphore_t renderEntered, renderRelease;
static NSUInteger backgroundPreparations;
static BOOL renderGateTimedOut;

static NSUInteger preparations(void) {
    @synchronized (cacheRoot) { return backgroundPreparations; }
}

// Pause the defaults poster after it sampled Off, or after its work was handed to main.
static _Thread_local BOOL stalePoster;
static BOOL readOnPoster;
static dispatch_semaphore_t sampledMode, resumePoster;
SGLockArtwork SGLockScreenArtwork(void) {
    if (stalePoster) {
        if (!readOnPoster) {
            readOnPoster = YES;
            dispatch_semaphore_signal(sampledMode);
            dispatch_semaphore_wait(resumePoster, DISPATCH_TIME_FOREVER);
        }
        return SGLockArtworkOff; // this writer's sample before the main-queue enable
    }
    return choice;
}
CGFloat SGMotionPixels(void) { return 32; }
NSString *SGURIString(id uri) { return [uri isKindOfClass:NSString.class] ? uri : [uri absoluteString]; }
SPTPlayerState *SGPlayerState(void) { return state; }
NSInteger SGKaraokePositionMs(void) { return position; }
void harnessPosition(NSInteger value) { position = value; }
void SGAddPlayerStateObserver(id<SGPlayerStateObserver> observer) {
    if (!observers) observers = [NSHashTable weakObjectsHashTable];
    [observers addObject:observer];
}
extern BOOL harnessMotionSourcesOff;
NSArray *SGMotionSourceOrder(void) { return harnessMotionSourcesOff ? @[] : @[@"canvas"]; }
NSURL *SGMotionCanvasIn(NSDictionary *metadata) { return nil; }
NSString *SGLocalFileCoverInURL(NSString *url) { return nil; }
BOOL SGMotionCanvasOutranks(NSArray *order, NSString *source) { return YES; }
void SGMotionClipFor(NSString *uri, NSURL *canvas, NSString *artist, NSString *album,
                     CGFloat pixels, void (^done)(NSURL *, NSString *)) {
    lookups++;
    done(sourceFile, sourceFile ? @"canvas" : nil);
}
// The follower's ticketed lookup: the stub source answers at once, so the ticket has nothing to cancel.
SGMotionTicket *SGMotionRequestSongClip(NSString *uri, NSURL *canvas, NSString *artist, NSString *album, NSString *song,
                                   CGFloat pixels, void (^done)(NSURL *, NSString *)) {
    SGMotionClipFor(uri, canvas, artist, album, pixels, done);
    return [SGMotionTicket new];
}
SGMotionTicket *SGMotionRequestAlbumSongClip(NSString *uri, NSURL *canvas, NSString *artist, NSString *album, NSString *song,
                                           NSString *albumURI, CGFloat pixels, void (^done)(NSURL *, NSString *)) {
    return SGMotionRequestSongClip(uri, canvas, artist, album, song, pixels, done);
}
// Shared/Player/PlayerState.x's first future track, other than the one playing.
SPTPlayerTrack *SGPlayerUpNextIn(SPTPlayerState *state) {
    id future = [state respondsToSelector:@selector(future)] ? state.future : nil;
    id next = [future isKindOfClass:NSArray.class] ? [future firstObject] : nil;
    if (![next isKindOfClass:objc_getClass("SPTPlayerTrack")]) return nil;
    NSString *uri = SGURIString([next URI]);
    return uri.length && ![uri isEqualToString:SGURIString(state.track.URI)] ? next : nil;
}
void SGMotionPoster(NSURL *file, void (^done)(UIImage *)) {
    posters++;
    if (!posterCallbacks) posterCallbacks = [NSMutableArray array];
    [posterCallbacks addObject:[done copy]];
}
NSURL *SGMotionMadeFile(NSString *key) {
    dispatch_semaphore_t entered = nil, release = nil;
    @synchronized (cacheRoot) {
        if ([key hasPrefix:@"background\n"]) backgroundPreparations++;
        if (heldPicture && [key hasPrefix:[NSString stringWithFormat:@"background\n%@\n", heldPicture]]) {
            entered = renderEntered;
            release = renderRelease;
            heldPicture = nil;
        }
    }
    if (entered) {
        dispatch_semaphore_signal(entered);
        BOOL timedOut = dispatch_semaphore_wait(release, dispatch_time(DISPATCH_TIME_NOW, HarnessWaitSeconds * (int64_t)NSEC_PER_SEC)) != 0;
        @synchronized (cacheRoot) { renderGateTimedOut = timedOut; }
    }
    NSData *data = [key dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char hash[CC_SHA1_DIGEST_LENGTH];
    CC_SHA1(data.bytes, (CC_LONG)data.length, hash);
    NSMutableString *name = [NSMutableString string];
    for (NSUInteger i = 0; i < sizeof(hash); i++) [name appendFormat:@"%02x", hash[i]];
    return [cacheRoot URLByAppendingPathComponent:[name stringByAppendingPathExtension:@"mp4"]];
}

static UIImage *image(UIColor *color) {
    return [[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(24, 32)] imageWithActions:^(UIGraphicsImageRendererContext *c) {
        [color setFill];
        UIRectFill(CGRectMake(0, 0, 24, 32));
    }];
}
void SGMotionMakeFile(NSURL *file, BOOL (^write)(void), void (^done)(BOOL)) {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        done([NSFileManager.defaultManager fileExistsAtPath:file.path] || write());
    });
}
SGAppFont SGAppFontDrawn(void) { return SGAppFontSystem; }
NSString *SGAppFontFamilyDrawn(void) { return nil; }
NSString *SGAppFontImportRevisionDrawn(void) { return nil; }
CGSize SGLyricsClipSize(CGFloat pixels) { return CGSizeMake(24, 32); }
CGImageRef SGLyricsClipBackdrop(CGImageRef cover, CGSize size) {
    return CGImageRetain(cover ?: blue.CGImage);
}
CGImageRef harnessPublicationFrame(NSString *, CGImageRef);
CGImageRef SGLyricsClipFrameWithFont(CGImageRef backdrop, CGImageRef cover, NSString *previous, NSString *line,
                                       NSString *translation, NSString *next, CGSize size, SGLyricsClipLayout layout, SGLyricsClipTextSize textSize, SGLyricsClipFont face) {
    return harnessPublicationFrame(line, backdrop);
}
CGImageRef SGLyricsClipDimmedArtwork(CGImageRef cover, CGSize size) {
    return CGImageRetain(cover ?: blue.CGImage);
}
NSString *SGLyricsClipLookWithFont(NSURL *motion, SGLyricsClipStyle style, SGLyricsClipLayout layout, BOOL dimmed, SGLyricsClipTextSize textSize, SGLyricsClipFont face) {
    return [NSString stringWithFormat:@"style%ldl%ldz%ld%@%@", (long)style, (long)layout, (long)textSize, dimmed ? @"d" : @"", motion ? motion.lastPathComponent : @""];
}
static BOOL writeFrame(NSURL *file, CGImageRef frame) {
    NSData *data = UIImagePNGRepresentation([UIImage imageWithCGImage:frame]);
    return [data writeToURL:file atomically:YES];
}
static NSMutableArray<NSString *> *encodedLines, *stoppedLines;
static NSMutableDictionary<NSString *, NSString *> *encodedTranslations;
static NSString *heldClip;
static dispatch_semaphore_t clipEntered, clipRelease;
static BOOL clipGateTimedOut;
// NO, as the real writers return, when `current` says no more once the clip is under way: they ask it each frame.
static BOOL recordClip(NSURL *file, NSString *line, NSString *translation, BOOL (^current)(void)) {
    BOOL hold;
    @synchronized (cacheRoot) {
        if (!encodedLines) encodedLines = [NSMutableArray array];
        if (!encodedTranslations) encodedTranslations = [NSMutableDictionary dictionary];
        [encodedLines addObject:line ?: @""];
        encodedTranslations[file.path] = translation ?: @"";
        hold = [line isEqual:heldClip];
        if (hold) heldClip = nil;
    }
    if (hold) {
        dispatch_semaphore_signal(clipEntered);
        clipGateTimedOut = dispatch_semaphore_wait(clipRelease, dispatch_time(DISPATCH_TIME_NOW, HarnessWaitSeconds * (int64_t)NSEC_PER_SEC)) != 0;
    }
    if (current && !current()) {
        @synchronized (cacheRoot) {
            if (!stoppedLines) stoppedLines = [NSMutableArray array];
            [stoppedLines addObject:line ?: @""];
        }
        return NO;
    }
    return YES;
}
BOOL SGLyricsClipWriteWithFont(NSURL *file, CGImageRef backdrop, CGImageRef cover, NSString *previous, NSString *line,
                                 NSString *translation, NSString *next, CGSize size, SGLyricsClipStyle style,
                                 SGLyricsClipLayout layout, SGLyricsClipTextSize textSize, SGLyricsClipFont face, BOOL (^current)(void)) {
    return recordClip(file, line, translation, current) && writeFrame(file, backdrop);
}
BOOL SGLyricsClipWriteOverMotionWithFont(NSURL *file, NSURL *motion, NSString *previous, NSString *line, NSString *translation,
                                 NSString *next, double from, double seconds, SGLyricsClipLayout layout, SGLyricsClipTextSize textSize, SGLyricsClipFont face, BOOL (^current)(void)) {
    return recordClip(file, line, translation, current) && writeFrame(file, blue.CGImage);
}
CGImageRef SGLyricsClipMotionFrameWithFont(NSURL *motion, NSString *previous, NSString *line, NSString *translation,
                                   NSString *next, double from, double seconds, SGLyricsClipLayout layout, SGLyricsClipTextSize textSize, SGLyricsClipFont face) { return CGImageRetain(blue.CGImage); }
BOOL SGMotionClipShape(NSURL *file, CGFloat ratio, NSURL *out) { return writeFrame(out, blue.CGImage); }
CGImageRef SGFluidClipFrame(CGImageRef cover, CGSize size) { return CGImageRetain(cover); }
BOOL SGFluidClipWrite(NSURL *file, CGImageRef cover, CGSize size) { return writeFrame(file, cover); }

// PlayerState.publish sends this callback on every accepted report, even when
// its URI/context/playback key is unchanged and it suppresses DidChange.
static void reportOnly(void) {
    for (id<SGPlayerStateObserver> observer in observers.allObjects) {
        if ([observer respondsToSelector:@selector(playerStateDidReport:)]) [observer playerStateDidReport:state];
    }
}
void harnessReport(NSString *uri, NSString *title) {
    state = harnessState(uri, title);
    reportOnly();
}
// Other lifecycle cases explicitly force a change (including simulated lyric seeks).
static void report(void) {
    reportOnly();
    for (id<SGPlayerStateObserver> observer in observers.allObjects) [observer playerStateDidChange:state];
}
static void choose(SGLockArtwork value) {
    choice = value;
    [NSNotificationCenter.defaultCenter postNotificationName:NSUserDefaultsDidChangeNotification object:nil];
    drainMain();
}
static void track(NSString *uri, SGLockArtwork mode, NSURL *file, NSArray *lines) {
    choose(SGLockArtworkOff);
    sourceFile = file;
    state = harnessState(uri, @"Song");
    position = 0;
    harnessLines(lines);
    report();
    choose(mode);
}
static void nativeArtworkInfo(MPMediaItemArtwork *cover) {
    NSMutableDictionary *info = [@{MPMediaItemPropertyTitle: @"Song", MPMediaItemPropertyArtist: @"Artist",
        MPNowPlayingInfoPropertyElapsedPlaybackTime: @0, MPNowPlayingInfoPropertyPlaybackRate: @0} mutableCopy];
    if (cover) info[MPMediaItemPropertyArtwork] = cover;
    MPNowPlayingInfoCenter.defaultCenter.nowPlayingInfo = info;
}
static void nativeInfo(UIImage *cover) {
    // MediaPlayer clamps requests to these bounds; model a full-resolution source.
    nativeArtworkInfo(cover ? [[MPMediaItemArtwork alloc] initWithBoundsSize:CGSizeMake(2048, 2048)
        requestHandler:^UIImage *(CGSize size) { nativeAcquisitions++; lastCoverRequest = size; return cover; }] : nil);
}
static id artwork(void) { return harnessSystem()[MPNowPlayingInfoProperty3x4AnimatedArtwork]; }
static NSString *name(id art) { return objc_getAssociatedObject(art, &idKey); }
static void finishPoster(void) {
    check(posterCallbacks.count > 0, @"a controlled poster callback is pending");
    if (!posterCallbacks.count) return;
    void (^done)(UIImage *) = posterCallbacks.firstObject;
    [posterCallbacks removeObjectAtIndex:0];
    done(blue);
}
#define await HarnessRunUntil
static NSString *coverURL(NSString *key) {
    return [@"https://cover.invalid/" stringByAppendingString:key];
}
static void coverMetadata(NSString *key) {
    harnessMetadata(key ? @{@"image_xlarge_url": coverURL(key)} : @{});
    // Only metadata changed: production does not deliver DidChange, and there
    // need not be a native now-playing notification to wake the paused lyrics.
    reportOnly();
}
static void finishCover(NSString *key, UIImage *image) {
    NSString *url = coverURL(key);
    check(await(^BOOL { return coverRequests[url] != nil; }), @"metadata artwork reaches the real URL loader");
    NSURLProtocol *request = coverRequests[url];
    if (!request) return;
    NSUInteger before = [coverCompletions[url] unsignedIntegerValue];
    [coverRequests removeObjectForKey:url];
    NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:request.request.URL
        statusCode:image ? 200 : 404 HTTPVersion:@"HTTP/1.1" headerFields:nil];
    [request.client URLProtocol:request didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    if (image) [request.client URLProtocol:request didLoadData:UIImagePNGRepresentation(image)];
    [request.client URLProtocolDidFinishLoading:request];
    if (!await(^BOOL { return [coverCompletions[url] unsignedIntegerValue] > before; }))
        HARNESS_FAIL(@"URLSession did not finish delivering cover %@", key);
}
static UIImage *preview(id art) {
    Preview block = objc_getAssociatedObject(art, &previewKey);
    __block UIImage *result;
    __block BOOL done = NO;
    if (block) block(CGSizeMake(24, 32), ^(UIImage *value) {
        dispatch_async(dispatch_get_main_queue(), ^{ result = value; done = YES; });
    });
    check(await(^BOOL { return done; }), @"preview request completes");
    return result;
}
static NSURL *video(id art) {
    Video block = objc_getAssociatedObject(art, &videoKey);
    __block NSURL *result;
    __block BOOL done = NO;
    if (block) block(CGSizeMake(24, 32), ^(NSURL *value) {
        dispatch_async(dispatch_get_main_queue(), ^{ result = value; done = YES; });
    });
    check(await(^BOOL { return done; }), @"video request completes");
    return result;
}
// PNG encoders can attach different scale/color metadata to the same pixels. The stand-ins are solid
// colors, so compare their decoded center in one fixed RGB space, not their container bytes.
static uint32_t pixel(UIImage *image) {
    uint32_t value = 0;
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(&value, 1, 1, 8, 4, space,
                                                 kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGContextDrawImage(context, CGRectMake(0, 0, 1, 1), image.CGImage);
    CGContextRelease(context);
    CGColorSpaceRelease(space);
    return value;
}
static BOOL sameImage(UIImage *a, UIImage *b) { return a.CGImage && b.CGImage && pixel(a) == pixel(b); }

static void background(NSDictionary *values) {
    NSMutableDictionary *domain = [NSMutableDictionary dictionary];
    for (NSString *key in values) domain[[@"spotifyglass.lockscreen.background." stringByAppendingString:key]] = values[key];
    [NSUserDefaults.standardUserDefaults setVolatileDomain:domain forName:NSArgumentDomain];
    [NSNotificationCenter.defaultCenter postNotificationName:NSUserDefaultsDidChangeNotification object:nil];
}

#include "publication-check.inc"

NSNotificationName const SGPlayerSpeedDidChangeNotification = @"spotifyglass.player.speedChanged";
int64_t harnessArtDelay;
int64_t harnessArtDue;
__weak dispatch_source_t harnessArmedArt;
CFAbsoluteTime harnessExtrasNow;
static _Thread_local BOOL countingPoster;
static NSUInteger posterHandoffs;
void HarnessArtDispatch(dispatch_queue_t queue, dispatch_block_t block) {
    if (countingPoster && queue == dispatch_get_main_queue()) posterHandoffs++;
    dispatch_async(queue, block);
}
extern void harnessAfterClipRequests(dispatch_block_t marker);
extern int64_t harnessRowDelay;
extern BOOL harnessPlaying;
extern double harnessRate;
NSUInteger harnessRowFires, harnessArtFires;
extern BOOL HarnessRowArmed(void);
static void failedLookup(void) {
    extern BOOL harnessLookupFailed;
    extern void (^harnessLyricsRequested)(NSString *);
    extern NSNotificationName const SGKaraokeLookupReadyNotification;
    // Model the keeper's admitted network starts separately from its callers.
    __block BOOL eligible = NO;
    __block NSUInteger starts = 0;
    harnessLyricsRequested = ^(NSString *trackID) {
        if (eligible && [trackID isEqual:@"lookup"]) { starts++; eligible = NO; }
    };
    harnessPlaying = YES;
    harnessLookupFailed = YES;
    track(@"lookup", SGLockArtworkLyrics, nil, nil);
    MPNowPlayingInfoCenter.defaultCenter.nowPlayingInfo = @{MPMediaItemPropertyTitle:@"Song",
        MPMediaItemPropertyArtist:@"Artist", MPNowPlayingInfoPropertyElapsedPlaybackTime:@0, MPNowPlayingInfoPropertyPlaybackRate:@1};
    drainMain();
    NSUInteger row = harnessRowFires, art = harnessArtFires, sets = harnessSets();
    check(!HarnessRowArmed() && (!harnessArmedArt || dispatch_source_testcancel(harnessArmedArt)) &&
          harnessRowFires == row && harnessArtFires == art, @"failed lookup: neither reader fires again");
    check(starts == 0 && harnessSets() == sets, @"failed lookup: no network starts or metadata setters");
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    eligible = YES;
    [center postNotificationName:SGKaraokeLookupReadyNotification object:@"lookup"];
    check(starts == 1, @"headers arriving wake a reader and admit one lookup");
    [center postNotificationName:SGKaraokeLinesKeptNotification object:@"lookup"]; // still no sheet; budget spent
    harnessPlaying = NO; reportOnly();
    harnessPlaying = YES; reportOnly();
    sets = harnessSets();
    drainMain();
    check(!HarnessRowArmed() && (!harnessArmedArt || dispatch_source_testcancel(harnessArmedArt)) &&
          harnessRowFires == row && harnessArtFires == art && starts == 1 && harnessSets() == sets,
          @"pause/resume with exhausted retries does not restart a display clock, request or setter");
    eligible = YES;
    [center postNotificationName:SGKaraokeLookupReadyNotification object:@"lookup"];
    harnessLookupFailed = NO;
    harnessLines(@[lineOf(@"Recovered", 0, 20000)]);
    [center postNotificationName:SGKaraokeLinesKeptNotification object:@"lookup"];
    check(starts == 2 && artwork() && (!getenv("LSL") || [harnessSystem()[MPMediaItemPropertyArtist] isEqual:@"Recovered"]),
          @"renewal and lookup completion publish the current line and artwork without waiting for a timer");
    harnessLyricsRequested = nil;
    harnessPlaying = NO;
    choose(SGLockArtworkOff);
}
static void playerDeadlines(void) {
    harnessPlaying = YES;
    // Artwork also wakes at the current line's sung end and 4 s before the next.
    track(@"clock-report", SGLockArtworkLyrics, nil, @[lineOf(@"first", 0, 24000), lineOf(@"second", 24000, 40000)]);
    harnessExtrasNow = 1000;
    MPNowPlayingInfoCenter.defaultCenter.nowPlayingInfo = @{MPMediaItemPropertyTitle:@"Song",
        MPMediaItemPropertyArtist:@"Artist", MPNowPlayingInfoPropertyElapsedPlaybackTime:@0, MPNowPlayingInfoPropertyPlaybackRate:@1};
    harnessRate = 2;
    [NSNotificationCenter.defaultCenter postNotificationName:SGPlayerSpeedDidChangeNotification object:nil];
    if (getenv("LSL")) check(harnessRowDelay == (int64_t)(12.0005 * NSEC_PER_SEC), @"speed alone halves the row deadline");
    check(harnessArtDelay == (int64_t)(10.0005 * NSEC_PER_SEC), @"speed alone halves the artwork deadline");
    harnessExtrasNow += 2;
    position = 4000;
    SGNowPlayingSetExtras(@"late-cover", @{@"late": @YES}, @"Song");
    NSDictionary *resent = harnessSystem();
    check([resent[@"late"] boolValue] && [resent[MPNowPlayingInfoPropertyPlaybackRate] doubleValue] == 2 &&
          [resent[MPNowPlayingInfoPropertyElapsedPlaybackTime] doubleValue] == 4,
          @"metadata resend after two seconds at 2x publishes position four and rate two");
    if (getenv("LSL")) check(harnessRowDelay == (int64_t)(10.0005 * NSEC_PER_SEC),
                              @"resent metadata preserves the row deadline at wall second twelve");
    check(harnessArmedArt && !dispatch_source_testcancel(harnessArmedArt) &&
          harnessArtDue - (int64_t)(harnessExtrasNow * NSEC_PER_SEC) == (int64_t)(8.0005 * NSEC_PER_SEC),
          @"the artwork's armed 2x one-shot has eight seconds left after the resend");
    SGNowPlayingSetExtras(@"late-cover", nil, nil);
    harnessExtrasNow = 0;
    position = 0;
    reportOnly(); // settle the rate, so the next report changes only position
    position = 250; // position-only report; smaller than the old artwork drift threshold
    reportOnly();
    if (getenv("LSL")) check(harnessRowDelay == (int64_t)(11.8755 * NSEC_PER_SEC), @"player-first seek advances the row deadline");
    check(harnessArtDelay == (int64_t)(9.8755 * NSEC_PER_SEC), @"player-first seek advances the artwork deadline");
    position = 25000;
    reportOnly();
    if (getenv("LSL")) check([harnessSystem()[MPMediaItemPropertyArtist] isEqual:@"second"], @"seek publishes the new row before MediaPlayer reports it");
    harnessRate = 1;
    harnessPlaying = NO;
    position = 0;
    choose(SGLockArtworkOff);
}

static void interleavedMode(void) {
    track(@"interleaved", SGLockArtworkOff, nil, @[lineOf(@"first", 0, 20000)]);
    nativeInfo(nil);
    sampledMode = dispatch_semaphore_create(0);
    resumePoster = dispatch_semaphore_create(0);
    dispatch_group_t posted = dispatch_group_create();
    dispatch_group_async(posted, dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
        stalePoster = YES;
        [NSNotificationCenter.defaultCenter postNotificationName:NSUserDefaultsDidChangeNotification object:nil];
        stalePoster = NO;
        dispatch_semaphore_signal(sampledMode);
    });
    check(dispatch_semaphore_wait(sampledMode, dispatch_time(DISPATCH_TIME_NOW, HarnessWaitSeconds * (int64_t)NSEC_PER_SEC)) == 0, @"background defaults poster reached the handoff");
    choose(SGLockArtworkLyrics);
    check(artwork() != nil, @"main applied the new artwork while the old defaults notification was pending");
    dispatch_semaphore_signal(resumePoster);
    dispatch_group_wait(posted, DISPATCH_TIME_FOREVER);
    check(readOnPoster, @"the background writer sampled Off before main enabled artwork");
    drainMain();
    choose(SGLockArtworkOff);
    check(artwork() == nil, @"final Off clears the applied artwork despite an interleaved background write");
}

void artworkChecks(void) {
    red = image(UIColor.redColor);
    blue = image(UIColor.blueColor);
    extern BOOL harnessCoverRevisions(UIImage *, UIImage *);
    check(harnessCoverRevisions(red, blue), @"stable cover reuses its digest; the pixels identify it across revisions");
    check(lookups == 1, @"lock-screen startup looks up the already-playing track");
    report();
    check(lookups == 1, @"the first ordinary report does not repeat the startup lookup");
    supported = @[MPNowPlayingInfoProperty3x4AnimatedArtwork];
    nativeInfo(nil);
    check(await(^BOOL { return posterCallbacks.count > 0; }), @"startup clip reaches presentation when capabilities arrive");
    finishPoster();
    check([video(artwork()) isEqual:sourceFile], @"the already-playing track supplies the lock-screen video");
    choose(SGLockArtworkOff);
    // A defaults write while both presenters remain off must not enumerate preferences.
    Method dictionary = class_getInstanceMethod(NSUserDefaults.standardUserDefaults.class, @selector(dictionaryRepresentation));
    IMP original = method_getImplementation(dictionary);
    __block NSUInteger snapshots = 0;
    IMP counted = imp_implementationWithBlock(^NSDictionary *(id store) {
        snapshots++;
        return ((id (*)(id, SEL))original)(store, @selector(dictionaryRepresentation));
    });
    method_setImplementation(dictionary, counted);
    dispatch_group_t idleWrite = dispatch_group_create();
    dispatch_group_async(idleWrite, dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
        countingPoster = YES;
        [NSNotificationCenter.defaultCenter postNotificationName:NSUserDefaultsDidChangeNotification object:nil];
        countingPoster = NO;
    });
    dispatch_group_wait(idleWrite, DISPATCH_TIME_FOREVER);
    check(posterHandoffs == 0, @"Off-to-Off background write queues no artwork work on main");
    drainMain();
    method_setImplementation(dictionary, original);
    imp_removeBlock(counted);
    check(!snapshots, @"unrelated defaults change with artwork Off reads no defaults dictionary");
    UIImage *safe = image([UIColor colorWithRed:24 / 255. green:24 / 255. blue:27 / 255. alpha:1]);
    background(@{@"darkness": @0});
    runFor(.2);
    NSURL *file = [cacheRoot URLByAppendingPathComponent:@"source.mp4"];
    NSArray *lines = @[lineOf(@"First", 0, 10000), lineOf(@"Second", 12000, 20000)];
    supported = @[MPNowPlayingInfoProperty3x4AnimatedArtwork];
    nativeInfo(nil);
    drainMain();

    // A whole burst on a posting thread must return without waiting for main, and emit just once.
    __block NSUInteger notifications = 0;
    id token = [NSNotificationCenter.defaultCenter addObserverForName:SGNowPlayingInfoDidChangeNotification object:nil queue:nil
        usingBlock:^(NSNotification *note) {
            check(NSThread.isMainThread, @"now-playing notification is delivered on main");
            notifications++;
        }];
    dispatch_semaphore_t posted = dispatch_semaphore_create(0);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
        for (NSUInteger i = 0; i < 20; i++) nativeInfo(nil);
        dispatch_semaphore_signal(posted);
    });
    check(dispatch_semaphore_wait(posted, dispatch_time(DISPATCH_TIME_NOW, HarnessWaitSeconds * (int64_t)NSEC_PER_SEC)) == 0,
          @"background now-playing setters never wait for main");
    HARNESS_AWAIT(notifications != 0);
    check(notifications == 1, @"native now-playing notification burst is coalesced");
    SGNowPlayingSetExtras(@"test", @{@"test": @YES}, @"Song");
    SGNowPlayingSetExtras(@"test", nil, nil);
    drainMain();
    check(notifications == 1, @"extras resends do not generate notifications");
    [NSNotificationCenter.defaultCenter removeObserver:token];

    track(@"poster-race", SGLockArtworkMotionLyrics, file, @[]);
    SGLockMotionShowPlain(YES);
    harnessLines(lines);
    report();
    id lyric = artwork();
    check(lyric != nil, @"lyrics take ownership while the plain poster is pending");
    finishPoster();
    check(artwork() == lyric, @"late plain poster cannot replace lyric artwork");
    SGNowPlayingSetExtras(@"lyrics", nil, nil);
    check(!artwork(), @"late plain poster did not leave a hidden competing motion owner");

    track(@"poster-toggle", SGLockArtworkMotionLyrics, file, @[]);
    SGLockMotionShowPlain(YES);
    SGLockMotionShowPlain(NO);
    SGLockMotionShowPlain(YES);
    finishPoster();
    check(!artwork(), @"plain-to-lyrics-to-plain rejects the first poster generation");
    finishPoster();
    check(artwork() != nil, @"plain-to-lyrics-to-plain accepts the current poster");

    track(@"poster-old-track", SGLockArtworkMotion, file, @[]);
    choose(SGLockArtworkOff);
    finishPoster();
    check(!artwork(), @"a choice change invalidates an in-flight poster");
    track(@"poster-track-a", SGLockArtworkMotion, file, @[]);
    state = harnessState(@"poster-track-b", @"Song");
    report();
    finishPoster();
    check(!artwork(), @"a same-title track change invalidates the old poster");
    finishPoster();
    check(artwork() != nil, @"the new track's poster still publishes");

    supported = @[];
    track(@"late-capability", SGLockArtworkMotion, file, @[]);
    NSUInteger fetched = lookups, decoded = posters, sets = harnessSets();
    for (NSUInteger i = 0; i < 5; i++) { nativeInfo(nil); drainMain(); }
    check(lookups == fetched && posters == decoded && !artwork(),
          @"unsupported capability does not refetch, decode or publish on repeated updates");
    runFor(0.1);
    check(harnessSets() == sets + 5, @"unsupported capability creates no polling/resend loop");
    supported = @[MPNowPlayingInfoProperty3x4AnimatedArtwork];
    nativeInfo(nil);
    HARNESS_AWAIT(posterCallbacks.count);
    finishPoster();
    check(artwork() && lookups == fetched, @"late capability publishes the same track without downloading again");
    sets = harnessSets();
    runFor(0.1);
    check(harnessSets() == sets, @"recovered publication does not recursively resend");

    supported = @[];
    track(@"cancel-pending", SGLockArtworkMotion, file, @[]);
    decoded = posters;
    choose(SGLockArtworkOff);
    supported = @[MPNowPlayingInfoProperty3x4AnimatedArtwork];
    nativeInfo(nil);
    drainMain();
    check(!artwork() && posters == decoded, @"disabled artwork cannot revive a capability-waiting offer");

    supported = @[];
    track(@"plain-capability", SGLockArtworkMotionLyrics, file, @[]);
    SGLockMotionShowPlain(YES);
    decoded = posters;
    harnessLines(lines);
    report();
    lyric = artwork();
    supported = @[MPNowPlayingInfoProperty3x4AnimatedArtwork];
    nativeInfo(nil);
    drainMain();
    check(artwork() == lyric && posters == decoded, @"lyrics ownership cancels a capability-waiting plain offer");

    supported = @[];
    track(@"plain-late-capability", SGLockArtworkMotionLyrics, file, @[]);
    SGLockMotionShowPlain(YES);
    fetched = lookups;
    supported = @[MPNowPlayingInfoProperty3x4AnimatedArtwork];
    nativeInfo(nil);
    HARNESS_AWAIT(posterCallbacks.count);
    finishPoster();
    check(artwork() && lookups == fetched, @"plain motion recovers late capability without a new lookup");

    nativeInfo(nil);
    drainMain();
    NSUInteger prepared = preparations();
    dispatch_semaphore_t entered = dispatch_semaphore_create(0), release = dispatch_semaphore_create(0);
    @synchronized (cacheRoot) {
        heldPicture = @"cover-during-render";
        renderEntered = entered;
        renderRelease = release;
        renderGateTimedOut = NO;
    }
    track(@"cover-during-render", SGLockArtworkEverySong, nil, @[]);
    check(dispatch_semaphore_wait(entered, dispatch_time(DISPATCH_TIME_NOW, HarnessWaitSeconds * (int64_t)NSEC_PER_SEC)) == 0,
          @"coverless background worker is held before rendering");
    fetched = lookups;
    __block BOOL coverInfoDelivered = NO;
    id coverInfoToken = [NSNotificationCenter.defaultCenter addObserverForName:SGNowPlayingInfoDidChangeNotification object:nil queue:nil
        usingBlock:^(NSNotification *note) { coverInfoDelivered = YES; }];
    // While the authoritative URL is loading, even a new native object is only a fallback.
    coverMetadata(@"cover-during-render");
    nativeInfo(blue);
    check(await(^BOOL { return coverInfoDelivered; }), @"late-cover info is delivered while the worker is held");
    [NSNotificationCenter.defaultCenter removeObserver:coverInfoToken];
    finishCover(@"cover-during-render", red);
    sets = harnessSets();
    dispatch_semaphore_signal(release);
    // Either cancelling the safe render or publishing it before recovery is valid.
    check(await(^BOOL { return artwork() && sameImage(preview(artwork()), red); }),
          @"cover arriving during rendering recovers the paused track without another native event");
    check(sameImage(preview(artwork()), red), @"recovered in-flight cover is the real album image");
    check(sameImage([UIImage imageWithContentsOfFile:video(artwork()).path], red),
          @"in-flight correction reaches the lazy video without another event");
    runFor(.1);
    check(preparations() <= prepared + 2 && harnessSets() <= sets + 2 && lookups == fetched,
          [NSString stringWithFormat:@"in-flight recovery stays bounded with no source re-download (renders +%lu, sets +%lu, lookups +%lu)",
              (unsigned long)(preparations() - prepared), (unsigned long)(harnessSets() - sets), (unsigned long)(lookups - fetched)]);
    @synchronized (cacheRoot) { check(!renderGateTimedOut, @"held render was explicitly released, not timed out"); }

    nativeInfo(nil);
    drainMain();
    prepared = preparations();
    track(@"cover-never-arrives", SGLockArtworkEverySong, nil, @[]);
    check(await(^BOOL { return artwork() != nil; }), @"permanently coverless track publishes its safe fallback");
    fetched = lookups;
    sets = harnessSets();
    for (NSUInteger i = 0; i < 5; i++) nativeInfo(nil);
    runFor(.1);
    check(preparations() == prepared + 1 && harnessSets() == sets + 5 && lookups == fetched,
          @"a cover that never arrives stays bounded across completion and later native updates");

    nativeInfo(red);
    track(@"native-first", SGLockArtworkEverySong, nil, @[]);
    check(await(^BOOL { return artwork() != nil; }), @"native-first track publishes without another event");
    check(sameImage(preview(artwork()), red), @"cover installed before the player observer is accepted");
    state = harnessState(@"player-first-same-title", @"Song");
    report();
    check(await(^BOOL { return artwork() != nil; }), @"same-title player-first switch offers provisional pixels");
    check(sameImage(preview(artwork()), red), @"predecessor pixels may be provisional until a corrective signal");
    id provisional = artwork();
    lastCoverRequest = CGSizeZero;
    nativeInfo(blue);
    check(await(^BOOL { return artwork() && sameImage(preview(artwork()), blue); }),
          @"paused same-title track replaces predecessor pixels on a new native object");
    check(lastCoverRequest.width == 32 && lastCoverRequest.height == 32,
          @"native fallback requests the full cover raster");
    check(sameImage([UIImage imageWithContentsOfFile:video(artwork()).path], blue),
          @"native-only current cover reaches the lazy video");
    check(preview(provisional) == nil && video(provisional) == nil,
          @"native replacement retires stale preview and lazy video work");

    MPMediaItemArtwork *sameNative = MPNowPlayingInfoCenter.defaultCenter.nowPlayingInfo[MPMediaItemPropertyArtwork];
    id sameOffer = artwork();
    NSUInteger acquired = nativeAcquisitions, loaded = coverLoads;
    prepared = preparations(); sets = harnessSets(); fetched = lookups;
    for (NSUInteger i = 0; i < 5; i++) { nativeArtworkInfo(sameNative); drainMain(); }
    check(nativeAcquisitions == acquired && preparations() == prepared && harnessSets() == sets + 5
          && lookups == fetched && coverLoads == loaded,
          @"same-object elapsed updates do not reacquire, render, publish or download");
    for (NSUInteger i = 0; i < 5; i++) nativeInfo(blue);
    runFor(.1);
    check(artwork() == sameOffer && sameImage(preview(sameOffer), blue) && preparations() <= prepared + 2
          && lookups == fetched && coverLoads == loaded,
          @"identical-pixel wrappers coalesce without republishing or retiring lazy work");

    supported = @[];
    nativeInfo(red);
    drainMain();
    prepared = preparations(); acquired = nativeAcquisitions;
    for (NSUInteger i = 0; i < 5; i++) { reportOnly(); drainMain(); }
    check(preparations() == prepared && nativeAcquisitions == acquired,
          @"lost cover capability does not acquire or prepare repeatedly");
    supported = @[MPNowPlayingInfoProperty3x4AnimatedArtwork];
    reportOnly();
    check(await(^BOOL { return artwork() && sameImage(preview(artwork()), red); }),
          @"restored cover capability consumes the latest native object");

    track(@"spotify:local:Artist:Album:Native-only:123", SGLockArtworkEverySong, nil, @[]);
    harnessMetadata(@{@"image_url": @"spotify:localfileimage:%2Fvar%2Fmobile%2FMedia%2Foriginal-album.jpg"});
    reportOnly();
    nativeInfo(blue);
    check(await(^BOOL { return artwork() && sameImage(preview(artwork()), blue); }),
          @"original local asset URI metadata keeps the native cover");

    nativeInfo(red);
    track(@"offline-native-cover", SGLockArtworkEverySong, nil, @[]);
    coverMetadata(@"offline-unavailable");
    nativeInfo(blue);
    check(await(^BOOL { return artwork() && sameImage(preview(artwork()), blue); }),
          @"native cover publishes while the URL request is deliberately unresolved");
    finishCover(@"offline-unavailable", nil);
    finishCover(@"offline-unavailable", nil);
    check(await(^BOOL { return artwork() && sameImage(preview(artwork()), blue); }),
          @"exhausted offline URL load preserves the available native cover");
    nativeInfo(red);
    check(await(^BOOL { return artwork() && sameImage(preview(artwork()), red); }),
          @"new native artwork still replaces the cover after URL failure");
    choose(SGLockArtworkOff);
    choose(SGLockArtworkEverySong);
    finishCover(@"offline-unavailable", nil);
    finishCover(@"offline-unavailable", nil);
    check(await(^BOOL { return artwork() && sameImage(preview(artwork()), red); }),
          @"same-track restart reacquires available native cover");

    coverMetadata(@"stale-native-track");
    check(await(^BOOL { return coverRequests[coverURL(@"stale-native-track")] != nil; }),
          @"prior-track URL request is held");
    track(@"current-native-track", SGLockArtworkEverySong, nil, @[]);
    nativeInfo(blue);
    check(await(^BOOL { return artwork() && sameImage(preview(artwork()), blue); }),
          @"new track publishes native pixels without waiting for the prior request");
    finishCover(@"stale-native-track", red);
    check(sameImage(preview(artwork()), blue), @"stale prior-track URL completion cannot replace current native pixels");
    coverMetadata(@"disabled-native-track");
    check(await(^BOOL { return coverRequests[coverURL(@"disabled-native-track")] != nil; }),
          @"current URL request starts before disabling");
    choose(SGLockArtworkOff);
    prepared = preparations(); loaded = coverLoads;
    finishCover(@"disabled-native-track", red);
    for (NSUInteger i = 0; i < 5; i++) nativeArtworkInfo(sameNative);
    drainMain();
    check(!artwork() && preparations() == prepared && coverLoads == loaded,
          @"disabled fallback cannot acquire, prepare or revive from late native or URL events");

    nativeInfo(blue);
    track(@"revised-url-native-fallback", SGLockArtworkEverySong, nil, @[]);
    check(await(^BOOL { return artwork() != nil; }), @"native B publishes before URL A completes");
    id nativeB = artwork();
    check(sameImage(preview(nativeB), blue), @"the provisional native B cover has blue pixels");
    coverMetadata(@"revised-url-A");
    finishCover(@"revised-url-A", red);
    check(await(^BOOL { return artwork() && ![name(artwork()) isEqual:name(nativeB)]; }),
          @"URL A replaces provisional native B");
    check(sameImage(preview(artwork()), red), @"successful URL A supplies red pixels");
    // No new native object or notification: changing only the URI source must make the
    // still-available B object eligible again, even after it was superseded by URL A.
    coverMetadata(@"revised-url-B");
    finishCover(@"revised-url-B", nil);
    finishCover(@"revised-url-B", nil);
    check(await(^BOOL { return [name(artwork()) isEqual:name(nativeB)]; }),
          @"failed revised URL B restores the unchanged native B object");
    check(sameImage(preview(artwork()), blue), @"revised-source failure keeps native B in the preview");
    check(sameImage([UIImage imageWithContentsOfFile:video(artwork()).path], blue),
          @"revised-source failure keeps native B in the lazy video");

    supported = @[];
    nativeInfo(nil);
    track(@"fluid-late", SGLockArtworkEverySong, nil, @[]);
    fetched = lookups;
    supported = @[MPNowPlayingInfoProperty3x4AnimatedArtwork];
    nativeInfo(nil);
    HARNESS_AWAIT(artwork() != nil);
    id safeFallback = artwork();
    check(safeFallback != nil, @"Every song offers a safe selected fallback before the cover arrives");
    lastCoverRequest = CGSizeZero;
    coverMetadata(@"fluid-late");
    nativeInfo(blue); // the URL load remains primary even when a new native object is available
    finishCover(@"fluid-late", red);
    check(await(^BOOL { return artwork() && sameImage(preview(artwork()), red); }),
          @"paused metadata cover changes Every song's identity without another native event");
    id fluid = artwork();
    check(fluid && lookups == fetched, @"paused late cover recovers Every song without a new lookup");
    check(![name(fluid) isEqual:name(safeFallback)], @"late cover does not reuse the no-cover fallback's disk identity");
    // Native is immediate, but the completed URI result owns the final pixels.
    UIImage *fluidPreview = preview(fluid);
    Preview fluidRequest = objc_getAssociatedObject(fluid, &previewKey);
    __block UIImage *unalignedPreview;
    fluidRequest(CGSizeMake(25, 33), ^(UIImage *value) { unalignedPreview = value; });
    check(unalignedPreview && sameImage(unalignedPreview, fluidPreview)
          && CGImageGetWidth(unalignedPreview.CGImage) * 4 == CGImageGetHeight(unalignedPreview.CGImage) * 3,
          @"Every song returns its ready exact-ratio raster even for an unaligned request");
    check(CGSizeEqualToSize(lastCoverRequest, CGSizeMake(32, 32))
          && CGImageGetWidth(fluidPreview.CGImage) == 24 && CGImageGetHeight(fluidPreview.CGImage) == 32,
          @"native acquisition and authoritative rendering use the intended full raster");
    nativeInfo(blue);
    drainMain();
    check(artwork() == fluid, @"later native notifications cannot downgrade a successful URI cover");
    check(sameImage(preview(fluid), red), @"lazy fluid preview retains the offered cover");
    NSURL *fluidFile = video(fluid);
    check(sameImage(red, [UIImage imageWithContentsOfFile:fluidFile.path]),
          @"lazy fluid video uses the offered cover");

    fetched = lookups;
    entered = dispatch_semaphore_create(0);
    release = dispatch_semaphore_create(0);
    @synchronized (cacheRoot) {
        heldPicture = @"fluid-late";
        renderEntered = entered;
        renderRelease = release;
        renderGateTimedOut = NO;
    }
    background(@{@"mode": @4, @"darkness": @0, @"color": @0x0000FF});
    // Defaults delivery hops to main, debounces, then renders on the worker.
    // Clearing the old offer is observable before the replacement is ready.
    check(await(^BOOL { @synchronized (cacheRoot) { return heldPicture == nil; } }),
          @"paused Every song settings render reaches the controlled worker gate");
    check(!artwork(), @"settings change clears the old offer while its replacement is still rendering");
    dispatch_semaphore_signal(release);
    check(await(^BOOL { return artwork() && ![name(artwork()) isEqual:name(fluid)]; }),
          @"paused Every song publishes the replacement after the settings render completes");
    id solid = artwork();
    check(solid && ![name(solid) isEqual:name(fluid)] && lookups == fetched,
          @"paused Every song background changes identity without a source lookup");
    @synchronized (cacheRoot) { check(!renderGateTimedOut, @"settings render was explicitly released, not timed out"); }
    check(sameImage(preview(solid), blue), @"Every song uses the selected solid color");
    check(preview(fluid) == nil, @"old fallback request cannot return a stale preview after settings change");
    background(@{@"darkness": @0});
    check(await(^BOOL { return artwork() && ![name(artwork()) isEqual:name(solid)]; }),
          @"Every song restores the cover background before the next case");

    nativeInfo(nil);
    track(@"lyrics-late-cover", SGLockArtworkLyrics, nil, lines);
    id empty = artwork();
    check(sameImage(preview(empty), safe), @"coverless lyric preview uses the shared safe backdrop");
    NSURL *emptyFile = video(empty);
    check(emptyFile != nil, @"coverless lyric video is cached on disk");
    NSData *legacyRows = [NSJSONSerialization dataWithJSONObject:@[@[@"First", @0, @10000, @10000],
        @[@"Second", @12000, @20000, @20000]] options:0 error:nil];
    check([name(empty) containsString:[NSString stringWithFormat:@"-%@-", HarnessLegacySHA256(legacyRows)]],
          @"lyric timing fingerprint preserves its original SHA-256 identity");
    NSString *legacyClip = [HarnessLegacySHA256([name(empty) dataUsingEncoding:NSUTF8StringEncoding]) stringByAppendingPathExtension:@"mp4"];
    check([emptyFile.lastPathComponent isEqual:legacyClip], @"lyric clip filename preserves its original SHA-256 identity");
    // A fresh report draws the next line ahead while requests are recent.
    position = 12000;
    report();
    position = 0;
    report();
    nativeInfo(red);
    coverMetadata(@"lyrics-late-cover");
    finishCover(@"lyrics-late-cover", red);
    HARNESS_AWAIT(artwork() && ![name(artwork()) isEqual:name(empty)]);
    id covered = artwork();
    check(covered && ![name(covered) isEqual:name(empty)], @"paused late cover changes the current render identity");
    check(sameImage(preview(covered), red), @"late cover replaces the cached current preview");
    NSURL *coveredFile = video(covered);
    check(coveredFile && ![coveredFile isEqual:emptyFile]
          && [NSFileManager.defaultManager fileExistsAtPath:emptyFile.path],
          @"late cover uses a distinct disk file while the coverless file still exists");
    check(sameImage(red, [UIImage imageWithContentsOfFile:coveredFile.path]),
          @"the new disk file contains the real cover");
    MPMediaItemArtwork *nativeCoverObject = MPNowPlayingInfoCenter.defaultCenter.nowPlayingInfo[MPMediaItemPropertyArtwork];
    check(nativeCoverObject && nativeCoverObject != harnessSystem()[MPMediaItemPropertyArtwork], @"lyrics supply the ordinary artwork by default");
    NSUserDefaults *prefs = NSUserDefaults.standardUserDefaults;
    NSDictionary *originalDomain = [prefs volatileDomainForName:NSArgumentDomain];
    NSMutableDictionary *keepDomain = [originalDomain mutableCopy];
    keepDomain[SGKeyLockScreenKeepWidgetCover] = @YES;
    [prefs setVolatileDomain:keepDomain forName:NSArgumentDomain];
    [NSNotificationCenter.defaultCenter postNotificationName:NSUserDefaultsDidChangeNotification object:nil];
    HARNESS_AWAIT(harnessSystem()[MPMediaItemPropertyArtwork] == nativeCoverObject);
    check([name(artwork()) isEqual:name(covered)] && [video(artwork()) isEqual:coveredFile],
          @"keeping the widget cover preserves the paused line's animated offer and video");
    [prefs setVolatileDomain:originalDomain forName:NSArgumentDomain];
    [NSNotificationCenter.defaultCenter postNotificationName:NSUserDefaultsDidChangeNotification object:nil];
    HARNESS_AWAIT(harnessSystem()[MPMediaItemPropertyArtwork] != nativeCoverObject && harnessSystem()[MPMediaItemPropertyArtwork]);
    check([name(artwork()) isEqual:name(covered)] && MPNowPlayingInfoCenter.defaultCenter.nowPlayingInfo[MPMediaItemPropertyArtwork] == nativeCoverObject,
          @"switching back restores the lyric still and retains the native source cover");
    position = 12000;
    report();
    id next = artwork();
    check(sameImage(preview(next), red), @"prefetched next preview uses the real-cover identity");
    NSURL *nextFile = video(next);
    check(sameImage(red, [UIImage imageWithContentsOfFile:nextFile.path]),
          @"prefetched next disk clip uses the real-cover identity");
    sets = harnessSets();
    nativeInfo(red);
    drainMain();
    check(harnessSets() == sets + 1, @"unchanged cover/line does not republish or loop");
    position = 0;
    report();
    id previousStyle = artwork();
    sets = harnessSets();
    fetched = lookups;
    for (NSUInteger i = 0; i < 20; i++) background(@{@"mode": @4, @"darkness": @0, @"color": @(0x0000FF + i)});
    HARNESS_AWAIT(artwork() && ![name(artwork()) isEqual:name(previousStyle)]);
    id changedStyle = artwork();
    check(changedStyle && ![name(changedStyle) isEqual:name(previousStyle)] && lookups == fetched,
          @"paused lyric background changes current render identity without downloading");
    check(harnessSets() <= sets + 2, @"slider burst coalesces to one clear and one publication");
    check(preview(previousStyle) == nil && video(previousStyle) == nil, @"stale lyric requests are cancelled after a style change");
    NSURL *styleFile = video(changedStyle);
    check(styleFile && ![styleFile isEqual:coveredFile], @"style change creates a distinct current disk clip");
    position = 12000;
    report();
    NSURL *styleNext = video(artwork());
    check(styleNext && ![styleNext isEqual:nextFile], @"style change creates a distinct prefetched disk clip");
    id beforeResize = artwork();
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSDictionary *savedDomain = [defaults volatileDomainForName:NSArgumentDomain];
    NSMutableDictionary *resized = [savedDomain mutableCopy];
    resized[SGKeyLockScreenLyricsSize] = @(SGLyricsClipTextLarge);
    [defaults setVolatileDomain:resized forName:NSArgumentDomain];
    [NSNotificationCenter.defaultCenter postNotificationName:NSUserDefaultsDidChangeNotification object:nil];
    HARNESS_AWAIT(artwork() && [name(artwork()) containsString:@"z2"]);
    NSURL *largerFile = video(artwork());
    check(state.isPaused && largerFile && ![largerFile isEqual:styleNext] && !preview(beforeResize),
          @"changing text size while paused replaces the current clip and retires its old preview");
    choose(SGLockArtworkOff);
    [defaults setVolatileDomain:savedDomain forName:NSArgumentDomain];
    nativeInfo(nil);
    drainMain();
    check(!artwork(), @"late now-playing info cannot revive disabled lyrics");

    SGKaraokeLine *spoken = lineOf(@"原文", 0, 10000);
    spoken.pronunciation = lineOf(@"first reading", 0, 10000);
    harnessReading(SGRLyricsReadingSource, YES);
    track(@"reading-revision", SGLockArtworkLyrics, nil, @[spoken]);
    id firstReading = artwork();
    video(firstReading);
    extern NSUInteger harnessArtworkHashes;
    NSUInteger hashes = harnessArtworkHashes;
    for (NSUInteger i = 0; i < 10; i++) report();
    check(harnessArtworkHashes == hashes, @"position reports reuse the unchanged song reading digest");
    // The view's observer may apply the saved reading after the artwork observer is called.
    [NSNotificationCenter.defaultCenter postNotificationName:SGLyricsAIResultDidChangeNotification object:@"reading-revision"];
    spoken.pronunciation = lineOf(@"replacement reading", 0, 10000);
    check(await(^BOOL { return artwork() != firstReading; }), @"AI pronunciation edit refreshes the paused artwork");
    id replacementReading = artwork();
    video(replacementReading);
    check([encodedLines containsObject:@"replacement reading"] && video(firstReading) == nil,
          @"source pronunciation replacement renders new words and cancels the old clip");
    harnessSongLanguage = @"ja";
    [NSNotificationCenter.defaultCenter postNotificationName:SGLyricsLanguageDidChangeNotification object:@"reading-revision"];
    check(video(replacementReading) == nil && video(artwork()) != nil,
          @"song language change retires pending pronunciation clips while paused");
    harnessSongLanguage = nil;
    harnessReading(SGRLyricsReadingNone, NO);
    choose(SGLockArtworkOff);

    background(@{@"darkness": @0});
    runFor(.2);
    // A non-nil native placeholder is not a missing image. The old test supplied nil,
    // so it never exposed the first-image-wins latch or the title-only identity.
    UIImage *placeholder = [[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(24, 32)]
        imageWithActions:^(UIGraphicsImageRendererContext *context) {
            [UIColor.blackColor setFill];
            UIRectFill(CGRectMake(0, 0, 24, 32));
            [[[UIImage systemImageNamed:@"photo"] imageWithTintColor:UIColor.grayColor
                renderingMode:UIImageRenderingModeAlwaysOriginal] drawInRect:CGRectMake(0, 4, 24, 24)];
        }];
    nativeInfo(placeholder);
    track(@"source-placeholder", SGLockArtworkLyrics, nil, lines);
    check(state.isPaused, @"metadata-only artwork regression runs with the lyric timer stopped");
    coverMetadata(@"source-real");
    check(await(^BOOL { return coverRequests[coverURL(@"source-real")] != nil; }),
          @"paused report-only late metadata starts a cover load without a native info update");
    HARNESS_AWAIT(artwork() != nil);
    id pending = artwork();
    check(sameImage(preview(pending), safe), @"native placeholder never enters the lyric preview while metadata cover loads");
    NSURL *pendingFile = video(pending);
    check(sameImage([UIImage imageWithContentsOfFile:pendingFile.path], safe),
          @"native placeholder never enters the lyric disk clip");
    finishCover(@"source-real", red);
    HARNESS_AWAIT(artwork() && ![name(artwork()) isEqual:name(pending)]);
    id resolved = artwork();
    check(![name(resolved) isEqual:name(pending)] && sameImage(preview(resolved), red),
          @"metadata real cover replaces fallback even while native artwork remains a placeholder");
    check(sameImage([UIImage imageWithContentsOfFile:video(resolved).path], red),
          @"metadata real cover reaches the disk clip");
    position = 12000;
    report();
    check(sameImage(preview(artwork()), red), @"metadata real cover reaches the prefetched next line");

    nativeInfo(red); // Previous track's real cover, same title as the next track.
    track(@"source-old", SGLockArtworkLyrics, nil, lines);
    coverMetadata(@"source-old");
    check(await(^BOOL { return coverRequests[coverURL(@"source-old")] != nil; }), @"old track cover request is held");
    state = harnessState(@"source-new", @"Song");
    report();
    coverMetadata(@"source-new");
    check(sameImage(preview(artwork()), safe), @"same-title track never inherits native artwork from the previous URI");
    finishCover(@"source-new", blue);
    HARNESS_AWAIT(artwork() && sameImage(preview(artwork()), blue));
    finishCover(@"source-old", red);
    check(sameImage(preview(artwork()), blue), @"late old-URI completion cannot replace the current cover");

    coverMetadata(@"source-revised-old");
    check(await(^BOOL { return coverRequests[coverURL(@"source-revised-old")] != nil; }),
          @"paused report-only revised metadata starts a cover load without a native info update");
    coverMetadata(@"source-revised-new");
    finishCover(@"source-revised-new", red);
    HARNESS_AWAIT(artwork() && sameImage(preview(artwork()), red));
    finishCover(@"source-revised-old", blue);
    check(sameImage(preview(artwork()), red), @"late old-URL completion cannot replace revised metadata for the same URI");
    coverMetadata(@"source-unavailable");
    finishCover(@"source-unavailable", nil);
    check(sameImage(preview(artwork()), safe), @"failed authoritative artwork uses dark fallback, not native placeholder or stale cover");
    // The approved retry contract: that first failure asks once more for the same source.
    check(await(^BOOL { return coverRequests[coverURL(@"source-unavailable")] != nil; }),
          @"a failed authoritative load makes exactly one retry");
    check(sameImage(preview(artwork()), safe), @"the solid fallback stays while the retry loads");
    finishCover(@"source-unavailable", nil);
    NSUInteger loads = coverLoads;
    for (NSUInteger i = 0; i < 5; i++) { report(); nativeInfo(placeholder); }
    runFor(.2);
    check(coverLoads == loads && coverRequests.count == 0,
          @"an exhausted retry budget keeps the solid fallback without further requests");

    // A transient failure recovers on the retry, while the player is paused.
    coverMetadata(@"source-transient");
    finishCover(@"source-transient", nil);
    check(await(^BOOL { return coverRequests[coverURL(@"source-transient")] != nil; }),
          @"a paused transient cover failure is retried once");
    id transientFallback = artwork();
    check(sameImage(preview(transientFallback), safe), @"the paused line keeps the solid fallback during the retry");
    finishCover(@"source-transient", red);
    // The recovered cover is decoded and republished off the main queue; a slow runner can take past
    // finishCover's short settle, so wait for the new artwork rather than a fixed delay.
    check(await(^BOOL { return ![name(artwork()) isEqual:name(transientFallback)]; }) && sameImage(preview(artwork()), red),
          @"a paused line recovers its cover when the retry succeeds");
    check(sameImage([UIImage imageWithContentsOfFile:video(artwork()).path], red),
          @"the recovered retry cover reaches the paused disk clip");

    // A new source URL during the old retry retires that retry, which cannot paint over the new cover.
    coverMetadata(@"source-retry-old");
    finishCover(@"source-retry-old", nil);
    check(await(^BOOL { return coverRequests[coverURL(@"source-retry-old")] != nil; }),
          @"the old source's retry is in flight");
    coverMetadata(@"source-retry-new");
    finishCover(@"source-retry-new", blue);
    HARNESS_AWAIT(artwork() && sameImage(preview(artwork()), blue));
    check(sameImage(preview(artwork()), blue), @"the revised source URL shows its own cover while the old retry is pending");
    finishCover(@"source-retry-old", red);
    check(sameImage(preview(artwork()), blue), @"a late old-URL retry cannot replace the new source's cover");

    // Disabling during a retry retires it.
    coverMetadata(@"source-retry-disabled");
    finishCover(@"source-retry-disabled", nil);
    check(await(^BOOL { return coverRequests[coverURL(@"source-retry-disabled")] != nil; }),
          @"a retry is in flight before disabling");
    choose(SGLockArtworkOff);
    finishCover(@"source-retry-disabled", red);
    check(!artwork(), @"a retry completing after disabling cannot revive lyrics");
    choose(SGLockArtworkLyrics);
    coverMetadata(@"source-retry-restored");
    finishCover(@"source-retry-restored", red);
    HARNESS_AWAIT(artwork() && sameImage(preview(artwork()), red));
    check(sameImage(preview(artwork()), red), @"re-enabling starts a fresh source rather than reusing the retired retry");
    coverMetadata(@"source-disabled");
    check(await(^BOOL { return coverRequests[coverURL(@"source-disabled")] != nil; }), @"cover request starts before disabling");
    choose(SGLockArtworkOff);
    finishCover(@"source-disabled", red);
    check(!artwork(), @"late metadata cover cannot revive disabled lyrics");

    [NSUserDefaults.standardUserDefaults setVolatileDomain:@{SGKeyLockScreenTranslation: @YES} forName:NSArgumentDomain];
    harnessTranslations = @{@"en": @{@"Hola": @"Hello saved"}};
    SGKaraokeLine *hola = lineOf(@"Hola", 0, 10000);
    track(@"translation-delete", SGLockArtworkLyrics, nil, @[hola]);
    HARNESS_AWAIT([hola.translation isEqual:@"Hello saved"] && artwork());
    drainMain();
    id translatedArt = artwork();
    NSURL *translatedFile = video(artwork());
    check([encodedTranslations[translatedFile.path] isEqual:@"Hello saved"],
          @"paused artwork restores saved translation without a lyrics view");
    harnessTranslations = nil;
    [NSNotificationCenter.defaultCenter postNotificationName:SGLyricsTranslationsDidChangeNotification object:nil];
    HARNESS_AWAIT(!hola.translation.length && artwork() && artwork() != translatedArt);
    NSURL *deletedFile = video(artwork());
    check([encodedTranslations[deletedFile.path] isEqual:@""],
          @"paused artwork removes deleted translation without a lyrics view");
    [NSUserDefaults.standardUserDefaults setVolatileDomain:@{} forName:NSArgumentDomain];

    // Low Power Mode coming on while paused puts the paused line Still under a new ID, and its going off brings
    // the chosen style back, with no player report in between.
    [NSUserDefaults.standardUserDefaults setVolatileDomain:@{SGKeyLockScreenLyricsStyle: @(SGLyricsClipAnimated)} forName:NSArgumentDomain];
    track(@"power-paused", SGLockArtworkLyrics, nil, @[lineOf(@"Breath", 0, 10000)]);
    NSString *animatedLook = [NSString stringWithFormat:@"style%ldl", (long)SGLyricsClipAnimated];
    NSString *stillLook = [NSString stringWithFormat:@"style%ldl", (long)SGLyricsClipStill];
    HARNESS_AWAIT([name(artwork()) containsString:animatedLook]);
    check(state.isPaused && [name(artwork()) containsString:animatedLook], @"a paused line shows the chosen breathing style");
    // On the process info's own class, under both names, as harness/player swaps it.
    __block BOOL lowPowerOn = YES;
    Class processClass = object_getClass(NSProcessInfo.processInfo);
    NSMutableArray<NSValue *> *swapped = [NSMutableArray array];
    for (NSString *selector in @[@"isLowPowerModeEnabled", @"lowPowerModeEnabled"]) {
        Method method = class_getInstanceMethod(processClass, NSSelectorFromString(selector));
        if (!method) continue;
        [swapped addObject:[NSValue valueWithPointer:method]];
        [swapped addObject:[NSValue valueWithPointer:method_getImplementation(method)]];
        method_setImplementation(method, imp_implementationWithBlock(^BOOL(id process) { return lowPowerOn; }));
    }
    [NSNotificationCenter.defaultCenter postNotificationName:NSProcessInfoPowerStateDidChangeNotification object:nil];
    HARNESS_AWAIT([name(artwork()) containsString:stillLook]);
    check([name(artwork()) containsString:stillLook], @"Low Power Mode while paused puts the line Still");
    lowPowerOn = NO;
    for (NSUInteger i = 0; i + 1 < swapped.count; i += 2)
        method_setImplementation((Method)swapped[i].pointerValue, (IMP)swapped[i + 1].pointerValue);
    [NSNotificationCenter.defaultCenter postNotificationName:NSProcessInfoPowerStateDidChangeNotification object:nil];
    HARNESS_AWAIT([name(artwork()) containsString:animatedLook]);
    check([name(artwork()) containsString:animatedLook], @"Low Power Mode going off while paused brings the chosen style back");
    [NSUserDefaults.standardUserDefaults setVolatileDomain:@{} forName:NSArgumentDomain];

    track(@"late-motion", SGLockArtworkMotionLyrics, file,
          @[lineOf(@"Late", 0, 900), lineOf(@"Now", 1000, 1900)]);
    SGLyricsArtworkSetMotion(SGURIString(state.track.URI), file);
    HARNESS_AWAIT([name(artwork()) containsString:file.lastPathComponent]);
    id late = artwork();
    clipEntered = dispatch_semaphore_create(0);
    clipRelease = dispatch_semaphore_create(0);
    @synchronized (cacheRoot) { heldClip = @"Late"; }
    __block NSUInteger deliveries = 0, expiredURLs = 0;
    Video lateVideo = objc_getAssociatedObject(late, &videoKey);
    void (^delivered)(NSURL *) = ^(NSURL *url) {
        dispatch_async(dispatch_get_main_queue(), ^{ deliveries++; if (url) expiredURLs++; });
    };
    lateVideo(CGSizeMake(24, 32), delivered);
    check(dispatch_semaphore_wait(clipEntered, dispatch_time(DISPATCH_TIME_NOW, HarnessWaitSeconds * (int64_t)NSEC_PER_SEC)) == 0,
          @"on-demand moving artwork is encoding the first line");
    lateVideo(CGSizeMake(24, 32), delivered);
    dispatch_semaphore_t drained = dispatch_semaphore_create(0);
    harnessAfterClipRequests(^{ dispatch_semaphore_signal(drained); });
    position = 1100; // No report or timer callback while the encode was running.
    dispatch_semaphore_signal(clipRelease);
    check(dispatch_semaphore_wait(drained, dispatch_time(DISPATCH_TIME_NOW, HarnessWaitSeconds * (int64_t)NSEC_PER_SEC)) == 0,
          @"both clip requests finished their serial work before main could refresh the clock");
    HARNESS_AWAIT(deliveries == 2);
    check(!expiredURLs && ![name(artwork()) isEqual:name(late)] && video(artwork()) != nil,
          @"overlapping encode and cache-hit requests both discard the expired motion URL");

    NSArray *seekLines = @[lineOf(@"Held", 0, 900), lineOf(@"Passed", 1000, 1900),
        lineOf(@"Obsolete", 2000, 2900), lineOf(@"Demand", 3000, 3900), lineOf(@"Wanted", 4000, 4900)];
    track(@"prefetch-seek", SGLockArtworkLyrics, nil, seekLines);
    clipEntered = dispatch_semaphore_create(0);
    clipRelease = dispatch_semaphore_create(0);
    @synchronized (cacheRoot) { heldClip = @"Held"; }
    Video heldVideo = objc_getAssociatedObject(artwork(), &videoKey);
    __block BOOL heldDone = NO, demandDone = NO;
    heldVideo(CGSizeMake(24, 32), ^(NSURL *url) {
        dispatch_async(dispatch_get_main_queue(), ^{ heldDone = YES; });
    });
    check(dispatch_semaphore_wait(clipEntered, dispatch_time(DISPATCH_TIME_NOW, HarnessWaitSeconds * (int64_t)NSEC_PER_SEC)) == 0,
          @"current clip holds the real serial artwork worker");
    @synchronized (cacheRoot) { [encodedLines removeAllObjects]; }
    position = 1000; report(); // queues Obsolete
    position = 3000; report(); // replaces it with Wanted
    Video demandVideo = objc_getAssociatedObject(artwork(), &videoKey);
    demandVideo(CGSizeMake(24, 32), ^(NSURL *url) {
        dispatch_async(dispatch_get_main_queue(), ^{ demandDone = url != nil; });
    });
    dispatch_semaphore_signal(clipRelease);
    check(await(^BOOL {
        @synchronized (cacheRoot) { return heldDone && demandDone && [encodedLines containsObject:@"Wanted"]; }
    }), @"current and latest next-line clips finish after releasing worker");
    @synchronized (cacheRoot) {
        check([encodedLines isEqual:@[@"Demand", @"Wanted"]],
              @"same-track seeks drop superseded prefetches before encoding and current demand goes first");
        check([stoppedLines containsObject:@"Held"], @"a clip whose line was seeked past stops encoding instead of finishing for nobody");
    }
    check(!clipGateTimedOut, @"held clip is released without a timeout");

    check(video(artwork()) != nil, @"the system is requesting clips before the cleanup interleaving");
    cleanupEntered = dispatch_semaphore_create(0);
    cleanupRelease = dispatch_semaphore_create(0);
    NSUInteger cleaned;
    @synchronized (cacheRoot) {
        cleaned = completedLyricsCleanups;
        holdLyricsCleanup = YES;
        cleanupGateTimedOut = NO;
    }
    // Hold A's filesystem cleanup while its next-line worker is queued. B's cleanup
    // and video request then arrive before that queued worker gets to select a job.
    track(@"cleanup-held", SGLockArtworkLyrics, nil,
          @[lineOf(@"Old", 0, 900), lineOf(@"Old next", 1000, 1900)]);
    check(dispatch_semaphore_wait(cleanupEntered, dispatch_time(DISPATCH_TIME_NOW, HarnessWaitSeconds * (int64_t)NSEC_PER_SEC)) == 0,
          @"old-track cache cleanup holds the serial worker");
    state = harnessState(@"cleanup-new", @"Song");
    harnessLines(@[lineOf(@"New current", 0, 10000)]);
    report();
    Video newTrackVideo = objc_getAssociatedObject(artwork(), &videoKey);
    __block NSURL *newTrackFile;
    __block BOOL newTrackDone = NO;
    newTrackVideo(CGSizeMake(24, 32), ^(NSURL *url) {
        dispatch_async(dispatch_get_main_queue(), ^{ newTrackFile = url; newTrackDone = YES; });
    });
    dispatch_semaphore_signal(cleanupRelease);
    check(await(^BOOL {
        @synchronized (cacheRoot) { return newTrackDone && completedLyricsCleanups >= cleaned + 2; }
    }), @"new-track delivery and both queued cache cleanups finish");
    check(newTrackFile && [NSData dataWithContentsOfURL:newTrackFile].length > 0,
          @"new-track clip URL remains readable after queued cache cleanup");
    @synchronized (cacheRoot) {
        check(!cleanupGateTimedOut, @"held cleanup is explicitly released without a timeout");
    }
    choose(SGLockArtworkOff);
    interleavedMode();
    playerDeadlines();
    failedLookup();
}
