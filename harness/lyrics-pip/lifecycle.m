// Compile the real engine, replacing only its system PiP transport. No real PiP/audio session starts.
#import "tests.h"
#import <objc/runtime.h>
#import "../../tweak/Sources/Shared/LyricsPiP/LyricsPiP.m"

static BOOL paused = YES, loading;
static BOOL loadFailed;
static NSString *retriedTrack;
BOOL SGLyricsLoadFailed(NSString *track) { return loadFailed; }
void SGLyricsRetry(NSString *track) { retriedTrack = track; }
static NSInteger requestedSeek;
static NSArray<SGKaraokeLine *> *testLines;
static NSUInteger translationReads, pronunciationReads;
static NSMutableArray<void (^)(void)> *heldTranslationLoads;
static BOOL rulePresent, ruleTranslation, rulePronunciation;
@implementation SPTPlayerTrack
- (id)URI { return SGTestTrackURI(); }
@end
@implementation SPTPlayerState
- (SPTPlayerTrack *)track { return [SPTPlayerTrack new]; }
- (BOOL)isPlaying { return !paused && !loading; }
- (BOOL)isPaused { return paused; }
- (BOOL)isLoading { return loading; }
- (double)duration { return 180; }
- (double)playbackSpeed { return 1; }
@end
@interface TestPlayer : NSObject
@property (nonatomic) NSUInteger pauses, resumes;
@end
@implementation TestPlayer
- (SPTPlayerState *)state { return [SPTPlayerState new]; }
- (id)pause:(id)options { _pauses++; paused = YES; return nil; }
- (id)resume:(id)options { _resumes++; paused = NO; return nil; }
@end
static TestPlayer *player;
static NSInteger position = 1500;
static NSString *credit = @"Spicy Lyrics · Maker · Uploader https://example.org/credit";
NSString *SGURIString(id uri) { return [uri isKindOfClass:NSURL.class] ? [uri absoluteString] : uri; }
SPTPlayerState *SGPlayerState(void) { return [SPTPlayerState new]; }
void SGAddPlayerStateObserver(id observer) {}
NSString *SGKaraokePlayingTrack(void) {
    return [SGTestTrackURI() hasPrefix:@"spotify:track:"] ? [SGTestTrackURI() substringFromIndex:14] : SGTestTrackURI();
}
id SGKaraokePlayer(void) { return player; }
NSInteger SGKaraokePositionMs(void) { return position; }
NSInteger SGKaraokeDelayMs(void) { return 0; }
void SGKaraokeSeek(NSInteger ms) { requestedSeek = ms; loading = YES; }
NSArray *SGKaraokeLinesForTrack(NSString *track) { return testLines; }
void SGKaraokeRequestLyrics(NSString *track) {}
NSString *SGLyricsGeminiLanguage(void) { return @"en"; }
void SGLyricsSyncSavedTranslation(NSString *track, NSString *language, NSArray<SGKaraokeLine *> *lines) {
    translationReads++;
    for (SGKaraokeLine *line in lines) if (!line.translation.length) line.translation = @"Saved translation";
}
void SGLyricsLoadTranslation(NSString *track, NSString *language, NSArray<SGKaraokeLine *> *lines,
                             BOOL (^current)(void), void (^done)(void)) {
    void (^load)(void) = ^{
        if (!current()) return;
        SGLyricsSyncSavedTranslation(track, language, lines);
        done();
    };
    if (heldTranslationLoads) [heldTranslationLoads addObject:[load copy]];
    else dispatch_async(dispatch_get_main_queue(), load);
}
NSDictionary *SGLyricsAIValues(NSString *kind, NSString *track, NSString *notation) {
    pronunciationReads++;
    return @{@"Original": @"Saved pronunciation"};
}
NSString *SGLyricsSongLanguage(NSString *track, NSArray *lines) { return @"ko"; }
BOOL SGLyricsLanguageRule(NSString *language, BOOL *translation, BOOL *pronunciation) {
    if (!rulePresent) return NO;
    *translation = ruleTranslation; *pronunciation = rulePronunciation; return YES;
}
NSNotificationName const SGLyricsTranslationSavedNotification = @"test.translation.saved";
NSNotificationName const SGLyricsTranslationsDidChangeNotification = @"test.translation.changed";
NSNotificationName const SGLyricsAIResultDidChangeNotification = @"test.ai.saved";
NSNotificationName const SGLyricsLanguageDidChangeNotification = @"test.language";
NSString *SGLyricsCreditFor(NSString *track) { return credit; }
NSArray *SGLyricsCreditLinks(NSString *text) { return @[]; }
void SGLyricsOpenCreditLinks(NSArray *links, UIView *from) {}
NSNotificationName const SGKaraokeLinesKeptNotification = @"test.lines";
NSNotificationName const SGLyricsOffsetsDidChangeNotification = @"test.offset";
NSNotificationName const SGLyricsDidReloadNotification = @"test.reload";
NSNotificationName const SGNowPlayingInfoDidChangeNotification = @"test.artwork";
NSString *SGL(NSString *key, NSString *english) { return english; }
BOOL SGFlag(NSString *key, BOOL fallback) {
    id value = [NSUserDefaults.standardUserDefaults objectForKey:key]; return value ? [value boolValue] : fallback;
}
void SGPresentDark(UIViewController *controller) {}
// SGPageStyle's accent preferences are not part of the PiP transport fixture.
NSInteger SGInt(NSString *key, NSInteger fallback) { return fallback; }
BOOL SGRedesignedUI(void) { return NO; }

static NSUInteger alerts;
static UIAlertAction *lyricsRetry;
static UIAlertController *retryAlert;
@interface TestPresenter : UIViewController
@end
@implementation TestPresenter
- (void)presentViewController:(UIViewController *)controller animated:(BOOL)animated completion:(void (^)(void))completion {
    if ([controller isKindOfClass:UIAlertController.class]) {
        UIAlertController *alert = (id)controller;
        if ([alert.title isEqual:@"Couldn't load lyrics · Retry"]) {
            retryAlert = alert;
            lyricsRetry = alert.actions.firstObject;
            return;
        }
        SGTestAssert([alert.message isEqual:@"Enable Picture in Picture lyrics in Retrine settings → Lyrics, then restart Spotify."],
            @"disabled tap gives exact activation and restart guidance");
        alerts++;
    }
    if (completion) completion();
}
@end
static TestPresenter *presenter;
UIViewController *SGTopController(void) { return presenter; }
// The engine needs only window identity and a presenter; creating a real UIWindow would require
// NSApplication/UIApplicationMain and turn this host-only lifecycle check into an application run.
@interface TestWindow : NSObject
@end
@implementation TestWindow
- (UIViewController *)rootViewController { return presenter; }
@end
static TestWindow *window;
@interface TestSource : UIView
@end
@implementation TestSource
- (UIWindow *)window { return (id)window; }
@end
UIView *SGTestSourceView(void) { return [TestSource new]; }
NSUInteger SGTestDisabledAlerts(void) { return alerts; }

@interface TestPiP : NSObject
@property (nonatomic, getter=isPictureInPicturePossible) BOOL pictureInPicturePossible;
@property (nonatomic, strong) id contentSource;
@property (nonatomic) NSUInteger starts, stops, invalidations;
@end
@implementation TestPiP
- (void)startPictureInPicture { _starts++; }
- (void)stopPictureInPicture { _stops++; }
- (void)invalidatePlaybackState { _invalidations++; }
@end

@interface TestLayer : AVSampleBufferDisplayLayer
@property (nonatomic) NSUInteger frames, flushes;
@property (nonatomic) CGSize raster;
@property (nonatomic, copy) NSData *pixels;
@property (nonatomic) BOOL blocked;
@end
@implementation TestLayer
- (BOOL)isReadyForMoreMediaData { return !_blocked; }
- (AVQueuedSampleBufferRenderingStatus)status { return AVQueuedSampleBufferRenderingStatusRendering; }
- (void)enqueueSampleBuffer:(CMSampleBufferRef)sample {
    SGTestAssert(CMSampleBufferGetImageBuffer(sample) != NULL, @"real engine enqueues a rendered pixel buffer");
    CVPixelBufferRef pixel = CMSampleBufferGetImageBuffer(sample);
    _raster = CGSizeMake(CVPixelBufferGetWidth(pixel), CVPixelBufferGetHeight(pixel));
    CVPixelBufferLockBaseAddress(pixel, kCVPixelBufferLock_ReadOnly);
    _pixels = [NSData dataWithBytes:CVPixelBufferGetBaseAddress(pixel) length:CVPixelBufferGetBytesPerRow(pixel) * CVPixelBufferGetHeight(pixel)];
    CVPixelBufferUnlockBaseAddress(pixel, kCVPixelBufferLock_ReadOnly);
    _frames++;
}
- (void)flushAndRemoveImage { _flushes++; }
@end

@interface TestEngine : SGLyricsPiPEngine
@property (nonatomic, strong) TestLayer *testLayer;
@property (nonatomic, readonly) CMTimebaseRef clock;
@end
@implementation TestEngine
- (CMTimebaseRef)clock { return _timebase; }
- (AVSampleBufferDisplayLayer *)displayLayer { return self.testLayer; }
- (BOOL)prepareIn:(UIWindow *)source {
    self.testLayer = [TestLayer new];
    if (!_timebase) CMTimebaseCreateWithSourceClock(kCFAllocatorDefault, CMClockGetHostTimeClock(), &_timebase);
    [self preparePool:SGLyricsPiPReadStyle().raster];
    TestPiP *pip = [TestPiP new];
    pip.pictureInPicturePossible = YES;
    [pip addObserver:self forKeyPath:@"pictureInPicturePossible" options:0 context:kPossibleContext];
    self.pip = (id)pip;
    return _pool && _timebase;
}
@end

void SGTestPiPState(BOOL enabled, BOOL active, BOOL starting) {
    [sg_engine finish];
    sg_engine = [TestEngine new];
    [sg_engine prepareIn:(id)window];
    sg_enabled = enabled;
    sg_engine.active = active;
    sg_engine.starting = starting;
}

static void prepareLifecycle(void) {
    player = [TestPlayer new];
    presenter = [TestPresenter new];
    window = [TestWindow new];
    // Report supported without constructing or starting a real system PiP controller.
    Method supported = class_getClassMethod(AVPictureInPictureController.class, @selector(isPictureInPictureSupported));
    method_setImplementation(supported, imp_implementationWithBlock(^BOOL(id object) { return YES; }));
}

void SGTestLifecycle(void) {
    prepareLifecycle();
    SGTestSetTrack(@"spotify:track:A", nil);
    testLines = @[];
    SGTestPiPState(NO, NO, NO);
    SGLyricsPiPToggle(SGTestSourceView());
    SGTestAssert(alerts == 1 && !SGLyricsPiPStarting(), @"disabled action never force-enables or starts");
    SGTestPiPState(YES, NO, NO);
    TestEngine *engine = (id)sg_engine;
    [engine refresh];
    SGTestAssert(engine.testLayer.frames == 0 && engine.background.image == nil, @"inactive refresh creates no frame or artwork");
    SGLyricsPiPToggle(SGTestSourceView());
    SGTestAssert(SGTestPump(^BOOL { return engine.shown != nil; }), @"user open prepares first production frame");
    TestPiP *pip = (id)engine.pip;
    SGTestAssert(pip.starts == 1 && engine.starting && !engine.active, @"readiness starts only once after first frame");
    SGTestAssert([SGLyricsPiPMenuTitle() isEqual:@"Close lyrics Picture in Picture"], @"starting action is cancel/close");
    SGTestAssert([engine.shown[2] isEqual:credit], @"provider maker/uploader credit is never filtered");
    testLines = nil;
    loadFailed = YES;
    [engine refresh];
    SGTestAssert(SGTestPump(^BOOL { return [engine.shown[0] isEqual:@"Couldn't load lyrics · Retry"]; }),
        @"PiP renders failure distinctly from healthy absence");
    engine.window = (id)window;
    engine.restoreCredit = YES;
    [engine showRestoredCredit];
    SGTestAssert(lyricsRetry != nil, @"restoring failed PiP offers retry");
    void (^retry)(UIAlertAction *) = [lyricsRetry valueForKey:@"handler"];
    SGTestAssert(retry != nil, @"retry action exposes a runnable handler");
    if (retry) retry(lyricsRetry);
    SGTestAssert([retriedTrack isEqual:@"A"], @"PiP retry uses the shared keeper for the displayed track");
    lyricsRetry = nil;
    retryAlert = nil;
    loadFailed = NO;
    [engine refresh];
    SGTestAssert(SGTestPump(^BOOL { return [engine.shown[0] isEqual:@"No lyrics available"]; }),
        @"PiP returns to genuine absence after a healthy miss");
    NSUInteger frames = engine.testLayer.frames;
    for (int i = 0; i < 20; i++) [engine refresh];
    SGTestAssert(engine.testLayer.frames == frames, @"unchanged content and background do not repeat frames");
    [engine pictureInPictureControllerDidStartPictureInPicture:(id)pip];
    SGTestAssert(engine.active && !engine.starting && engine.timer == nil, @"paused active session has no render timer");
    SGTestSetting(@"spotifyglass.lyrics.pip.background.darkness", @60);
    [NSNotificationCenter.defaultCenter postNotificationName:NSUserDefaultsDidChangeNotification object:nil];
    SGTestAssert(SGTestPump(^BOOL { return engine.testLayer.frames > frames; }), @"paused defaults notification refreshes actual engine");
    frames = engine.testLayer.frames;
    SGTestSetTrack(@"spotify:track:A", @"https://i.scdn.co/image/late");
    [NSNotificationCenter.defaultCenter postNotificationName:SGNowPlayingInfoDidChangeNotification object:nil];
    SGTestAssert(SGTestPump(^BOOL { return SGTestArtworkRequests() > 0; }), @"late artwork notification refreshes paused source");
    SGTestTakeArtwork()(SGTestCover());
    SGTestAssert(SGTestPump(^BOOL { return engine.testLayer.frames > frames; }), @"late cover refreshes actual paused frame");
    for (NSNumber *layout in @[@1, @2, @0]) {
        frames = engine.testLayer.frames;
        SGTestSetting(SGKeyPiPLayout, layout);
        [NSNotificationCenter.defaultCenter postNotificationName:NSUserDefaultsDidChangeNotification object:nil];
        SGTestAssert(SGTestPump(^BOOL { return engine.testLayer.frames > frames; }), @"paused aspect change enqueues a new frame");
        SGTestAssert(CGSizeEqualToSize(engine.testLayer.raster, SGLyricsPiPReadStyle().raster) &&
            CGImageGetWidth(engine.background.image.CGImage) == engine.testLayer.raster.width &&
            CGImageGetHeight(engine.background.image.CGImage) == engine.testLayer.raster.height,
            @"pool, background and enqueued pixel dimensions change together");
    }
    SGTestSetting(SGKeyPiPLayout, nil);
    frames = engine.testLayer.frames;
    NSData *oldPixels = engine.testLayer.pixels;
    SGTestSetting(SGKeyPiPFont, @"Georgia");
    [NSNotificationCenter.defaultCenter postNotificationName:NSUserDefaultsDidChangeNotification object:nil];
    SGTestAssert(SGTestPump(^BOOL { return engine.testLayer.frames > frames; }) &&
        ![oldPixels isEqual:engine.testLayer.pixels], @"paused font change invalidates style cache and changes real pixels");
    frames = engine.testLayer.frames;
    for (NSUInteger i = 0; i < 10; i++) [engine refresh];
    SGTestAssert(engine.testLayer.frames == frames, @"new style identity is cached after one frame");
    SGTestSetting(SGKeyPiPFont, nil);

    SGKaraokeWord *word = [SGKaraokeWord new]; word.text = @"Original";
    SGKaraokeLine *line = [SGKaraokeLine new]; line.words = @[word]; line.start = 1000; line.end = 4000;
    line.timing = SGKaraokeTimingLine; testLines = @[line];
    SGTestSetting(@"spotifyglass.redesign.lyricsTranslation", @YES);
    SGTestSetting(@"spotifyglass.redesign.lyricsPronunciation", @YES);
    [engine refresh];
    SGTestAssert(SGTestPump(^BOOL { return [engine.shown[4] isEqual:@"Saved translation"]; }) &&
        [engine.shown[3] isEqual:@"Saved pronunciation"] &&
        !line.translation && !line.pronunciation, @"saved supplements appear without modifying shared source lines");
    NSUInteger reads = translationReads + pronunciationReads;
    for (NSUInteger i = 0; i < 10; i++) [engine refresh];
    SGTestAssert(translationReads + pronunciationReads == reads, @"saved supplements are not reread from storage on each tick");
    heldTranslationLoads = [NSMutableArray array];
    frames = engine.testLayer.frames;
    NSData *translatedPixels = engine.testLayer.pixels;
    [engine backgroundChanged:[NSNotification notificationWithName:NSUserDefaultsDidChangeNotification object:nil]];
    SGTestAssert(SGTestPump(^BOOL { return heldTranslationLoads.count == 1; }), @"defaults refresh reaches the held saved-translation read");
    SGTestAssert([engine.shown[4] isEqual:@"Saved translation"] && [engine.testLayer.pixels isEqual:translatedPixels]
        && engine.testLayer.frames == frames, @"a pending defaults read never removes the translated presentation");
    void (^releaseTranslation)(void) = heldTranslationLoads.firstObject;
    heldTranslationLoads = nil;
    if (releaseTranslation) releaseTranslation();
    SGTestAssert(engine.testLayer.frames == frames && [engine.shown[4] isEqual:@"Saved translation"],
        @"an unchanged prepared result does not publish a duplicate frame");
    rulePresent = YES; ruleTranslation = NO; rulePronunciation = YES;
    // followLanguageRule in the lyrics view owns applying defaults to the effective switches.
    SGTestSetting(@"spotifyglass.redesign.lyricsTranslation", @NO);
    [engine lyricsChanged:[NSNotification notificationWithName:SGLyricsLanguageDidChangeNotification object:nil]];
    SGTestAssert(SGTestPump(^BOOL { return ![engine.shown[4] length]; }) && [engine.shown[3] length],
        @"effective language-rule switches independently hide translation");
    SGTestSetting(@"spotifyglass.redesign.lyricsPronunciation", @NO);
    [engine backgroundChanged:[NSNotification notificationWithName:NSUserDefaultsDidChangeNotification object:nil]];
    SGTestAssert(SGTestPump(^BOOL { return ![engine.shown[3] length]; }), @"manual display change wins after the song language default");
    rulePresent = NO;
    SGTestSetting(@"spotifyglass.redesign.lyricsTranslation", nil);
    SGTestSetting(@"spotifyglass.redesign.lyricsPronunciation", nil);
    testLines = nil;
    [engine lyricsChanged:[NSNotification notificationWithName:SGKaraokeLinesKeptNotification object:nil]];
    SGTestAssert(SGTestPump(^BOOL { return [engine.shown[0] isEqual:@"No lyrics available"]; }) &&
        ![engine.shown[3] length] && ![engine.shown[4] length], @"nil lyrics clear stale supplements and use honest no-lyrics state");

    // Invoke real delegate interactions. Only Spotify's asynchronous transport is simulated.
    paused = NO; loading = NO; position = 30000; [engine refresh];
    __block NSUInteger completions = 0;
    [engine pictureInPictureController:(id)pip skipByInterval:CMTimeMake(-10, 1) completionHandler:^{ completions++; }];
    SGTestAssert(requestedSeek == 20000 && completions == 0, @"backward skip waits for Spotify acknowledgement, not request dispatch");
    [engine refresh]; // loading report still contains the old position
    SGTestAssert(![engine pictureInPictureControllerIsPlaybackPaused:(id)pip] &&
        CMTimebaseGetRate(engine.clock) == 1 && completions == 0, @"seek-loading report preserves pre-seek playing rate");
    position = requestedSeek; loading = NO; [engine playerStateDidReport:SGPlayerState()];
    SGTestAssert(SGTestPump(^BOOL { return completions == 1; }) && !paused && player.resumes == 0 &&
        CMTimeGetSeconds(CMTimebaseGetTime(engine.clock)) >= 20, @"backward seek completes after landing without blind resume");
    paused = YES; position = 175000; [engine refresh];
    [engine pictureInPictureController:(id)pip skipByInterval:CMTimeMake(10, 1) completionHandler:^{ completions++; }];
    SGTestAssert(requestedSeek == 180000 && completions == 1, @"forward skip clamps to duration and remains pending");
    position = requestedSeek; loading = NO; [engine refresh];
    SGTestAssert(completions == 2 && paused && CMTimebaseGetRate(engine.clock) == 0 && player.resumes == 0,
        @"paused forward seek stays paused when completion runs");
    position = 2000; [engine refresh];
    [engine pictureInPictureController:(id)pip skipByInterval:CMTimeMake(-10, 1) completionHandler:^{ completions++; }];
    SGTestAssert(requestedSeek == 0, @"backward skip clamps at zero");
    position = 0; loading = NO; [engine refresh];
    SGTestAssert(completions == 3, @"zero-bound seek completes");
    paused = NO; position = 50000; [engine refresh];
    [engine pictureInPictureController:(id)pip skipByInterval:CMTimeMake(10, 1) completionHandler:^{ completions++; }];
    [engine pictureInPictureController:(id)pip setPlaying:NO];
    position = requestedSeek; loading = NO; [engine refresh];
    SGTestAssert(completions == 4 && paused && player.pauses == 1 && player.resumes == 0,
        @"a user pause after skip is never overwritten by its completion");
    [engine pictureInPictureController:(id)pip skipByInterval:CMTimeMake(10, 1) completionHandler:^{ completions++; }];
    SGTestSetTrack(@"spotify:track:seek-switch", nil); loading = NO; position = 0; [engine refresh];
    SGTestAssert(completions == 5 && paused && player.resumes == 0, @"track switch releases stale completion without resuming another song");
    NSInteger lastSeek = requestedSeek;
    [engine pictureInPictureController:(id)[TestPiP new] skipByInterval:CMTimeMake(10, 1) completionHandler:^{ completions++; }];
    SGTestAssert(completions == 6 && requestedSeek == lastSeek, @"stale controller acknowledges without seeking");
    [engine pictureInPictureController:(id)pip skipByInterval:kCMTimeInvalid completionHandler:^{ completions++; }];
    SGTestAssert(completions == 7 && requestedSeek == lastSeek, @"invalid interval acknowledges without seeking");
    __block NSUInteger replaced = 0;
    [engine pictureInPictureController:(id)pip skipByInterval:CMTimeMake(10, 1) completionHandler:^{ replaced++; }];
    [engine pictureInPictureController:(id)pip skipByInterval:CMTimeMake(10, 1) completionHandler:^{ replaced++; }];
    SGTestAssert(requestedSeek == 20000 && replaced == 1, @"rapid skips accumulate the target and acknowledge superseded requests once");
    position = requestedSeek; loading = NO; [engine refresh];
    SGTestAssert(replaced == 2 && paused && player.resumes == 0, @"newest rapid skip completes at its own target");
    [engine pictureInPictureController:(id)pip skipByInterval:CMTimeMake(10, 1) completionHandler:^{ completions++; }];
    SGTestAssert(SGTestPump(^BOOL { return completions == 8; }) && player.resumes == 0,
        @"unacknowledged seek times out once without starting audio");
    loading = NO; [engine refresh];
    NSUInteger pausesBeforeClose = player.pauses;
    SGLyricsPiPToggle(SGTestSourceView());
    SGTestAssert(pip.stops == 1 && player.pauses == pausesBeforeClose, @"close stops PiP without pausing Spotify");
    [engine pictureInPictureControllerDidStopPictureInPicture:(id)pip];
    SGTestAssert(!engine.active && engine.background.image == nil, @"stop clears pending background ownership");
    SGTestSetTrack(@"spotify:track:B", nil);
    SGLyricsPiPToggle(SGTestSourceView());
    TestPiP *cancelled = (id)engine.pip;
    SGLyricsPiPToggle(SGTestSourceView());
    SGTestAssert(!engine.starting && !engine.active && cancelled.stops == 1, @"second tap cancels pending start");
    SGLyricsPiPToggle(SGTestSourceView());
    TestPiP *newAttempt = (id)engine.pip;
    [engine pictureInPictureControllerDidStartPictureInPicture:(id)cancelled];
    [engine pictureInPictureControllerDidStopPictureInPicture:(id)cancelled];
    SGTestAssert(engine.pip == (id)newAttempt && engine.starting && !engine.active, @"stale delegate cannot start or tear down next attempt");
    [engine finish];
    SGTestPiPState(NO, NO, NO);
    SGTestSetTrack(@"spotify:track:menus", nil);
}

void SGTestIntent(void) {
    prepareLifecycle();
    paused = YES; loading = NO; position = 1500;
    SGKaraokeWord *word = [SGKaraokeWord new]; word.text = @"Original";
    SGKaraokeLine *line = [SGKaraokeLine new]; line.words = @[word];
    line.start = 1000; line.end = 4000; line.timing = SGKaraokeTimingLine;
    testLines = @[line];
    rulePresent = YES;
    for (NSNumber *manual in @[@NO, @YES]) {
        ruleTranslation = !manual.boolValue;
        rulePronunciation = !manual.boolValue;
        SGTestSetTrack(manual.boolValue ? @"spotify:track:manual-show" : @"spotify:track:manual-hide", nil);
        SGTestSetting(@"spotifyglass.redesign.lyricsTranslation", manual);
        SGTestSetting(@"spotifyglass.redesign.lyricsPronunciation", manual);
        SGTestPiPState(YES, NO, NO);
        TestEngine *engine = (id)sg_engine;
        NSDictionary *preferences = NSUserDefaults.standardUserDefaults.dictionaryRepresentation;
        for (NSUInteger opening = 0; opening < 2; opening++) {
            SGLyricsPiPToggle(SGTestSourceView());
            SGTestAssert(SGTestPump(^BOOL { return engine.shown != nil; }), @"manual-choice open/reopen renders");
            SGTestAssert(([engine.shown[4] length] > 0) == manual.boolValue &&
                ([engine.shown[3] length] > 0) == manual.boolValue,
                @"open/reopen preserves manual hide/show despite the opposite language default");
            SGTestAssert([preferences isEqual:NSUserDefaults.standardUserDefaults.dictionaryRepresentation],
                @"opening PiP never writes global display preferences");
            if (!opening) [engine finish];
        }
        SGTestSetTrack(manual.boolValue ? @"spotify:track:next-hide" : @"spotify:track:next-show", nil);
        [engine refresh];
        // Model the existing rule owner's queued switch update after track arrival, not a
        // second implementation of its per-song ledger. PiP must consume it even with cached lines.
        SGTestSetting(@"spotifyglass.redesign.lyricsTranslation", @(ruleTranslation));
        SGTestSetting(@"spotifyglass.redesign.lyricsPronunciation", @(rulePronunciation));
        preferences = NSUserDefaults.standardUserDefaults.dictionaryRepresentation;
        [engine refresh];
        SGTestAssert(SGTestPump(^BOOL {
            return engine.shown != nil && ([engine.shown[4] length] > 0) == ruleTranslation &&
                ([engine.shown[3] length] > 0) == rulePronunciation;
        }),
            @"next-song effective language defaults replace the previous song's manual choice");
        SGTestAssert([preferences isEqual:NSUserDefaults.standardUserDefaults.dictionaryRepresentation],
            @"next-song refresh only reads the rule owner's preferences");
        [engine finish];
    }
    rulePresent = NO;
    SGTestSetting(@"spotifyglass.redesign.lyricsTranslation", nil);
    SGTestSetting(@"spotifyglass.redesign.lyricsPronunciation", nil);
    testLines = @[];
    for (NSNumber *delta in @[@10, @-10]) {
        SGTestSetTrack(@"spotify:track:old-seek", nil);
        position = 100000; paused = YES; loading = NO;
        SGTestPiPState(YES, NO, NO);
        TestEngine *engine = (id)sg_engine;
        SGLyricsPiPToggle(SGTestSourceView());
        SGTestAssert(SGTestPump(^BOOL { return engine.shown != nil; }), @"queued-track seek fixture opens");
        TestPiP *pip = (id)engine.pip;
        __block NSUInteger oldDone = 0, newDone = 0;
        [engine pictureInPictureController:(id)pip skipByInterval:CMTimeMake(10, 1) completionHandler:^{ oldDone++; }];
        SGTestAssert(requestedSeek == 110000 && oldDone == 0, @"old track has an unacknowledged seek target");
        SGTestSetTrack(@"spotify:track:new-seek", nil);
        position = 3000; paused = YES; loading = NO;
        [engine playerStateDidReport:SGPlayerState()]; // refresh queued, deliberately not pumped yet
        [engine pictureInPictureController:(id)pip skipByInterval:CMTimeMake(delta.intValue, 1) completionHandler:^{ newDone++; }];
        NSInteger expected = delta.intValue > 0 ? 13000 : 0;
        SGTestAssert(requestedSeek == expected && oldDone == 1 && newDone == 0,
            @"second skip before queued refresh bases forward/backward bounds on actual new-track position");
        SGTestAssert(paused && player.resumes == 0 && player.pauses == 0 && CMTimebaseGetRate(engine.clock) == 0,
            @"retiring old seek does not change the new song's paused playback");
        position = requestedSeek; loading = NO;
        SGTestAssert(SGTestPump(^BOOL { return newDone == 1; }) && oldDone == 1,
            @"queued refresh acknowledges only the new track's settled target");
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:2.1];
        SGTestPump(^BOOL { return deadline.timeIntervalSinceNow <= 0; });
        SGTestAssert(oldDone == 1 && newDone == 1 && paused && player.resumes == 0 && player.pauses == 0,
            @"stale seek timeout callbacks cannot repeat completion or change playback");
        [engine finish];
    }
    testLines = nil;
    // finish closes the session, not the launch-time enable gate. Restore the fixture too.
    SGTestPiPState(NO, NO, NO);
    SGTestAssert(!SGLyricsPiPEnabled() && !SGLyricsPiPActive() && !SGLyricsPiPStarting(),
        @"intent fixture restores disabled idle state before menu tests");
}
