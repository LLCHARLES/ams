#import "tests.h"
#import "Shared/LyricsPiP/LyricsPiPBackground.h"
#import "Shared/LyricsBackground/LyricsBackground.h"
#import "Shared/Player/SGLastTrack.h"
#import "Shared/LyricsPiP/LyricsPiPStyle.h"

// Only the external player/artwork transport is mocked. The coordinator and renderer are production.
@interface SGShownTrack ()
@property (nonatomic, copy, readwrite) NSString *uri, *title, *artist, *album;
@property (nonatomic, readwrite) NSURL *artworkURL, *canvasURL;
@property (nonatomic, readwrite) BOOL current;
@end
@implementation SGShownTrack
@end

static SGShownTrack *shown;
static NSString *currentURI;
static NSMutableArray *requests;
NSUInteger SGTestArtworkRequests(void) { return requests.count; }
SGShownTrack *SGShownTrackNow(void) { return shown; }
void SGShownTrackArtwork(SGShownTrack *track, void (^done)(UIImage *)) {
    if (!requests) requests = [NSMutableArray array];
    [requests addObject:[done copy]];
}
void SGTestSetTrack(NSString *uri, NSString *url) {
    currentURI = [uri copy];
    // SGShownTrackNow intentionally excludes ads; playback still has their exact URI.
    if (!uri || [uri hasPrefix:@"spotify:ad:"]) { shown = nil; return; }
    shown = [SGShownTrack new];
    shown.uri = uri;
    shown.current = uri != nil;
    shown.artworkURL = url ? [NSURL URLWithString:url] : nil;
}
NSString *SGTestTrackURI(void) { return currentURI; }
void (^SGTestTakeArtwork(void))(UIImage *) {
    void (^done)(UIImage *) = requests.firstObject;
    if (done) [requests removeObjectAtIndex:0];
    SGTestAssert(done != nil, @"artwork requested from proven player interface");
    return done ?: ^(UIImage *image) {};
}
void SGTestSetting(NSString *key, id value) {
    NSMutableDictionary *domain = [[NSUserDefaults.standardUserDefaults volatileDomainForName:NSArgumentDomain] mutableCopy];
    domain[key] = value;
    [NSUserDefaults.standardUserDefaults setVolatileDomain:domain forName:NSArgumentDomain];
}
BOOL SGTestPump(BOOL (^ready)(void)) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:60];
    while (!ready() && deadline.timeIntervalSinceNow > 0)
        [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.005]];
    return ready();
}
UIImage *SGTestCover(void) {
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(NULL, 64, 64, 8, 256, space, kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(space);
    CGContextSetRGBFillColor(context, 1, 0, 0, 1);
    CGContextFillRect(context, CGRectMake(0, 0, 64, 64));
    CGContextSetRGBFillColor(context, 0, 0, 1, 1);
    CGContextFillRect(context, CGRectMake(32, 0, 32, 32));
    CGContextSetRGBFillColor(context, 0, 1, 0, 1);
    CGContextFillRect(context, CGRectMake(0, 32, 32, 32));
    CGImageRef image = CGBitmapContextCreateImage(context);
    UIImage *result = [UIImage imageWithCGImage:image];
    CGImageRelease(image);
    CGContextRelease(context);
    return result;
}

static NSData *pixels(CGImageRef image) {
    return image ? CFBridgingRelease(CGDataProviderCopyData(CGImageGetDataProvider(image))) : nil;
}

static void drainBackground(NSOperationQueue *queue) {
    [queue waitUntilAllOperationsAreFinished];
    __block BOOL drained = NO;
    dispatch_async(dispatch_get_main_queue(), ^{ drained = YES; });
    SGTestAssert(SGTestPump(^BOOL { return drained; }), @"queued background publication drained");
}

void SGTestBackground(void) {
    NSString *prefix = SGKeyLyricsPiPBackground, *lock = @"spotifyglass.lockscreen.background";
    for (NSString *p in @[prefix, lock]) {
        for (NSString *field in @[@"mode", @"darkness", @"blur", @"color"])
            SGTestSetting([p stringByAppendingFormat:@".%@", field], nil);
    }
    SGLyricsBackgroundStyle defaults = SGLyricsBackgroundRead(prefix);
    SGTestAssert(defaults.mode == SGLyricsBackgroundCover && fabs(defaults.darkness - .45) < .001
        && defaults.blur == 20 && defaults.color == 0x18181B, @"PiP background defaults match contract");
    SGTestSetting([lock stringByAppendingString:@".mode"], @4);
    SGTestSetting([lock stringByAppendingString:@".darkness"], @80);
    SGTestSetting([prefix stringByAppendingString:@".darkness"], @0);
    SGTestAssert(SGLyricsBackgroundRead(prefix).mode == 0 && SGLyricsBackgroundRead(lock).mode == 4
        && SGLyricsBackgroundRead(prefix).darkness == 0 && SGLyricsBackgroundRead(lock).darkness == .8,
        @"lockscreen and PiP settings remain isolated");

    UIImage *cover = SGTestCover();
    NSMutableSet *modes = [NSMutableSet set];
    for (NSInteger mode = 0; mode < 5; mode++) {
        SGLyricsBackgroundStyle style = {mode, 0, 20, 0x123456};
        CGImageRef image = SGLyricsBackgroundCreate(cover.CGImage, CGSizeMake(640, 360), style);
        SGTestAssert(image && CGImageGetWidth(image) == 640 && CGImageGetHeight(image) == 360, @"each mode renders fixed PiP raster");
        if (image) [modes addObject:pixels(image)];
        if (mode == SGLyricsBackgroundMonochrome && image) {
            NSData *data = pixels(image);
            const uint8_t *p = data.bytes;
            BOOL gray = YES;
            for (NSUInteger i = 0; i < data.length; i += 4) gray &= p[i] == p[i + 1] && p[i + 1] == p[i + 2];
            SGTestAssert(gray, @"monochrome has equal RGB channels");
        }
        if (mode == SGLyricsBackgroundSolid && image) {
            NSData *data = pixels(image);
            const uint8_t *p = data.bytes;
            SGTestAssert(p[0] == 0x12 && p[1] == 0x34 && p[2] == 0x56, @"solid uses chosen 24-bit color");
        }
        CGImageRelease(image);
    }
    SGTestAssert(modes.count == 5, @"five visually distinct modes for a multicolor cover");

    SGLyricsPiPBackground *background = [SGLyricsPiPBackground new];
    SGTestSetTrack(@"spotify:track:A", nil);
    [background refreshForTrack:SGTestTrackURI()];
    SGTestAssert(SGTestPump(^BOOL { return background.image != nil; }), @"no cover publishes shared fallback");
    NSData *fallback = pixels(background.image.CGImage);
    NSUInteger revision = background.revision;
    for (NSUInteger i = 0; i < 20; i++) [background refreshForTrack:SGTestTrackURI()];
    SGTestAssert(background.revision == revision && background.image != nil, @"unchanged tick does not enqueue another render");

    SGTestSetTrack(@"spotify:track:A", @"https://i.scdn.co/image/A");
    [background refreshForTrack:SGTestTrackURI()];
    void (^late)(UIImage *) = SGTestTakeArtwork();
    late(cover);
    SGTestAssert(SGTestPump(^BOOL { return background.image != nil; }), @"late same-track artwork is prepared");
    SGTestAssert(![pixels(background.image.CGImage) isEqual:fallback], @"late cover replaces fallback");
    revision = background.revision;
    SGTestSetting([prefix stringByAppendingString:@".darkness"], @70);
    [background refreshForTrack:SGTestTrackURI()];
    SGTestAssert(SGTestPump(^BOOL { return background.revision > revision; }), @"paused settings change renders without a timer");

    SGTestSetTrack(@"spotify:track:B", @"https://i.scdn.co/image/B");
    [background refreshForTrack:SGTestTrackURI()];
    void (^old)(UIImage *) = SGTestTakeArtwork();
    NSOperationQueue *queue = [background valueForKey:@"queue"];
    [queue waitUntilAllOperationsAreFinished]; // old render complete; its main-thread publication is pending
    SGTestSetTrack(@"spotify:track:C", @"https://i.scdn.co/image/C");
    [background refreshForTrack:SGTestTrackURI()];
    SGTestAssert(background.image == nil, @"track switch immediately retires previous cover");
    old(cover);
    void (^failed)(UIImage *) = SGTestTakeArtwork();
    failed(nil);
    // Approved bounded recovery: the first failure asks once more for the same source.
    void (^retry)(UIImage *) = SGTestTakeArtwork();
    SGTestAssert(retry != nil, @"a failed cover load retries exactly once");
    SGTestAssert(SGTestPump(^BOOL { return background.image != nil; }), @"failed image retains shared fallback");
    CGImageRef expected = SGLyricsBackgroundCreate(NULL, SGLyricsPiPReadStyle().raster, SGLyricsBackgroundRead(prefix));
    SGTestAssert([pixels(background.image.CGImage) isEqual:pixels(expected)], @"old fetch and render cannot replace new track fallback");
    revision = background.revision;
    retry(nil); // the one retry fails too: the budget is exhausted
    [background refreshForTrack:SGTestTrackURI()];
    SGTestAssert(background.revision == revision && requests.count == 0,
                 @"an exhausted retry keeps the solid fallback without another request");

    // A transient nil is recovered by the one retry, and its cover is prepared.
    SGTestSetTrack(@"spotify:track:transient", @"https://i.scdn.co/image/transient");
    [background refreshForTrack:SGTestTrackURI()];
    SGTestTakeArtwork()(nil);
    void (^recover)(UIImage *) = SGTestTakeArtwork();
    SGTestAssert(recover != nil, @"a transient failure retries immediately");
    SGTestAssert(SGTestPump(^BOOL { return background.image != nil; }), @"the solid fallback shows during the retry");
    revision = background.revision;
    recover(cover);
    SGTestAssert(SGTestPump(^BOOL { return background.revision > revision; }), @"a successful retry prepares a new frame");
    SGTestAssert(![pixels(background.image.CGImage) isEqual:fallback], @"the recovered retry cover replaces the solid fallback");
    CGImageRelease(expected);
    expected = SGLyricsBackgroundCreate(NULL, SGLyricsPiPReadStyle().raster, SGLyricsBackgroundRead(prefix));

    // A source URL change retires the old retry; its late cover cannot paint over the new source.
    SGTestSetTrack(@"spotify:track:retry-a", @"https://i.scdn.co/image/retry-a");
    [background refreshForTrack:SGTestTrackURI()];
    SGTestTakeArtwork()(nil);
    void (^retryA)(UIImage *) = SGTestTakeArtwork();
    SGTestSetTrack(@"spotify:track:retry-b", @"https://i.scdn.co/image/retry-b");
    [background refreshForTrack:SGTestTrackURI()];
    SGTestTakeArtwork()(nil);
    void (^retryB)(UIImage *) = SGTestTakeArtwork();
    retryA(cover);
    drainBackground(queue);
    CGImageRef fallbackB = SGLyricsBackgroundCreate(NULL, SGLyricsPiPReadStyle().raster, SGLyricsBackgroundRead(prefix));
    SGTestAssert([pixels(background.image.CGImage) isEqual:pixels(fallbackB)],
                 @"a retired source's retry cannot publish its cover");
    CGImageRelease(fallbackB);
    retryB(cover);
    SGTestAssert(SGTestPump(^BOOL { return ![pixels(background.image.CGImage) isEqual:pixels(expected)]; }),
                 @"the current source's retry still recovers its own cover");
    CGImageRelease(expected);

    // Disposal retires a retry in flight.
    SGTestSetTrack(@"spotify:track:retry-stop", @"https://i.scdn.co/image/retry-stop");
    [background refreshForTrack:SGTestTrackURI()];
    SGTestTakeArtwork()(nil);
    void (^retryStop)(UIImage *) = SGTestTakeArtwork();
    revision = background.revision;
    [background invalidate];
    retryStop(cover);
    drainBackground(queue);
    SGTestAssert(background.image == nil && background.revision == revision,
                 @"disposal cancels a retry before it can publish");
    [background refreshForTrack:SGTestTrackURI()];
    SGTestAssert(requests.count == 1, @"after disposal a current source starts a fresh load");
    SGTestTakeArtwork()(nil);
    SGTestTakeArtwork()(cover);
    SGTestSetting([prefix stringByAppendingString:@".mode"], @3);
    [background refreshForTrack:SGTestTrackURI()];
    [queue waitUntilAllOperationsAreFinished];
    revision = background.revision;
    [background invalidate];
    drainBackground(queue);
    SGTestAssert(background.image == nil && background.revision == revision, @"stop cancels queued publication");
    SGTestSetting([prefix stringByAppendingString:@".mode"], @0);
    SGTestSetting([prefix stringByAppendingString:@".darkness"], @45);

    SGTestSetTrack(@"spotify:ad:current", @"https://i.scdn.co/image/excluded");
    [background refreshForTrack:SGTestTrackURI()];
    SGTestAssert(SGTestPump(^BOOL { return background.image != nil; }), @"current ad publishes fallback despite artwork exclusion");
    SGTestAssert(requests.count == 0, @"excluded ad never requests network artwork");
    revision = background.revision;
    for (NSUInteger i = 0; i < 20; i++) [background refreshForTrack:SGTestTrackURI()];
    drainBackground(queue);
    SGTestAssert(background.revision == revision, @"stable ad fallback does not redraw");

    SGTestSetTrack(@"spotify:track:no-cover", nil);
    shown = nil; // artwork description can be absent independently of current playback
    [background refreshForTrack:SGTestTrackURI()];
    SGTestAssert(SGTestPump(^BOOL { return background.image != nil; }), @"current URI without artwork description publishes fallback");

    SGTestSetTrack(@"spotify:track:ordered", nil);
    [background refreshForTrack:SGTestTrackURI()];
    [queue waitUntilAllOperationsAreFinished];
    currentURI = @"spotify:track:other"; // player changes before the queued publication
    revision = background.revision;
    drainBackground(queue);
    SGTestAssert(background.image == nil && background.revision == revision, @"stale completed render cannot publish for another current URI");
    SGTestAssert(queue.operationCount == 0, @"rejected publication waits for an external refresh without spinning");
    currentURI = @"spotify:track:ordered";
    [background refreshForTrack:SGTestTrackURI()];
    SGTestAssert(SGTestPump(^BOOL { return background.image != nil; }), @"same source retries after player state ordering catches up");
    revision = background.revision;
    for (NSUInteger i = 0; i < 20; i++) [background refreshForTrack:SGTestTrackURI()];
    drainBackground(queue);
    SGTestAssert(background.revision == revision, @"successful ordered fallback is cached without repeated rendering");

    SGTestSetTrack(@"spotify:track:fetch-order", @"https://i.scdn.co/image/order");
    [background refreshForTrack:SGTestTrackURI()];
    void (^outOfOrder)(UIImage *) = SGTestTakeArtwork();
    currentURI = @"spotify:track:other";
    outOfOrder(cover);
    drainBackground(queue);
    SGTestAssert(background.image == nil, @"out-of-order artwork callback cannot publish a previous track");
    currentURI = @"spotify:track:fetch-order";
    [background refreshForTrack:SGTestTrackURI()];
    SGTestTakeArtwork()(cover);
    SGTestAssert(SGTestPump(^BOOL { return background.image != nil; }), @"rejected artwork source can refresh once current state catches up");
    [background invalidate];
    SGTestSetTrack(nil, nil);
}
