// One CPU-rendered still frame per content change, on Spotify's own playback clock.
// Never owns an audio session or player. Lifecycle/text frames are on main; backgrounds prepare off main.
#import "LyricsPiP.h"
#import "LyricsPiPFrame.h"
#import "LyricsPiPText.h"
#import "LyricsPiPBackground.h"
#import "Core/SGCore.h"
#import "Settings/SGPageStyle.h"
#import "Shared/Lyrics/Lyrics.h"
#import "Shared/LyricsTranslation/LyricsTranslation.h"
#import "Shared/Fonts/FontLibrary.h"
#import "Shared/Player/SGLastTrack.h"
#import "Shared/LyricsSources/LyricsSources.h"
#import "Shared/Player/PlayerState.h"
#import "Shared/Player/NowPlayingExtras.h"
#import <AVKit/AVKit.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
#import <CoreText/CoreText.h>
#import <math.h>

NSNotificationName const SGLyricsPiPDidChangeNotification = @"spotifyglass.lyrics.pip.didChange";
static BOOL sg_enabled;
static void *kPossibleContext = &kPossibleContext;

@interface SGLyricsPiPHost : UIView
@end
@implementation SGLyricsPiPHost
+ (Class)layerClass { return AVSampleBufferDisplayLayer.class; }
@end

@interface SGLyricsPiPEngine : NSObject <AVPictureInPictureControllerDelegate,
    AVPictureInPictureSampleBufferPlaybackDelegate, SGPlayerStateObserver> {
    CVPixelBufferPoolRef _pool;
    CMTimebaseRef _timebase;
}
@property (nonatomic, strong) SGLyricsPiPHost *host;
@property (nonatomic, strong) AVPictureInPictureController *pip;
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic, weak) UIWindow *window;
@property (nonatomic, copy) NSString *track;
@property (nonatomic, copy) NSString *artworkTrack;
@property (nonatomic, copy) NSArray<NSString *> *shown;
@property (nonatomic, strong) SGLyricsPiPBackground *background;
@property (nonatomic) NSUInteger shownBackgroundRevision;
@property (nonatomic, strong) SGLyricsPiPStyle *style;
@property (nonatomic, copy) NSArray *shownStyle;
@property (nonatomic) CGSize raster;
@property (nonatomic, strong) NSArray<SGKaraokeLine *> *sourceLines, *preparedLines, *pendingLines;
@property (nonatomic) BOOL linesDirty;
@property (nonatomic, copy) void (^seekCompletion)(void);
@property (nonatomic, copy) NSString *seekTrack;
@property (nonatomic) NSInteger seekTarget;
@property (nonatomic) BOOL seekWasPlaying;
@property (nonatomic) NSUInteger seekToken;
@property (nonatomic) BOOL active, starting, startRequested, stopping, playing, alertPending, restoreCredit, retryPending;
@property (nonatomic) NSUInteger generation, attempt;
@property (nonatomic) double duration, position, speed;
- (void)toggleFrom:(UIView *)from;
- (void)refresh;
@end

static SGLyricsPiPEngine *sg_engine;

BOOL SGLyricsPiPEnabled(void) { return sg_enabled; }
BOOL SGLyricsPiPActive(void) { return sg_engine.active; }
BOOL SGLyricsPiPStarting(void) { return sg_engine.starting; }
NSString *SGLyricsPiPMenuTitle(void) {
    return SGLyricsPiPActive() || SGLyricsPiPStarting()
        ? SGL(@"settings.lyrics.pip.menu.close", @"Close lyrics Picture in Picture")
        : SGL(@"settings.lyrics.pip.menu.open", @"Open lyrics Picture in Picture");
}
void SGLyricsPiPToggle(UIView *from) {
    if (!sg_enabled) {
        UIViewController *presenter = from.window.rootViewController ?: SGTopController();
        while (presenter.presentedViewController) presenter = presenter.presentedViewController;
        if (presenter.transitionCoordinator) {
            [presenter.transitionCoordinator animateAlongsideTransition:nil completion:^(id<UIViewControllerTransitionCoordinatorContext> context) {
                dispatch_async(dispatch_get_main_queue(), ^{ SGLyricsPiPToggle(from); });
            }];
            return;
        }
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:SGL(@"settings.lyrics.pip.title", @"Picture in Picture lyrics")
            message:SGL(@"settings.lyrics.pip.disabled", @"Enable Picture in Picture lyrics in Retrine settings → Lyrics, then restart Spotify.")
            preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:SGL(@"common.ok", @"OK") style:UIAlertActionStyleDefault handler:nil]];
        SGPresentDark(alert);
        [presenter presentViewController:alert animated:YES completion:nil];
        return;
    }
    if (!sg_engine) sg_engine = [SGLyricsPiPEngine new];
    [sg_engine toggleFrom:from];
}

@implementation SGLyricsPiPEngine

- (instancetype)init {
    if (!(self = [super init])) return nil;
    SGAddPlayerStateObserver(self);
    _background = [SGLyricsPiPBackground new];
    __weak SGLyricsPiPEngine *weakSelf = self;
    _background.changed = ^{ [weakSelf refresh]; };
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    // No queued notification observer: a posting Spotify thread must never wait for main.
    [center addObserver:self selector:@selector(lyricsChanged:) name:SGKaraokeLinesKeptNotification object:nil];
    [center addObserver:self selector:@selector(lyricsChanged:) name:SGLyricsOffsetsDidChangeNotification object:nil];
    [center addObserver:self selector:@selector(lyricsChanged:) name:SGLyricsDidReloadNotification object:nil];
    for (NSString *name in @[SGLyricsTranslationSavedNotification, SGLyricsTranslationsDidChangeNotification,
        SGLyricsAIResultDidChangeNotification, SGLyricsLanguageDidChangeNotification])
        [center addObserver:self selector:@selector(lyricsChanged:) name:name object:nil];
    [center addObserver:self selector:@selector(foreground:) name:UIApplicationDidBecomeActiveNotification object:nil];
    [center addObserver:self selector:@selector(background:) name:UIApplicationDidEnterBackgroundNotification object:nil];
    [center addObserver:self selector:@selector(backgroundChanged:) name:NSUserDefaultsDidChangeNotification object:nil];
    [center addObserver:self selector:@selector(backgroundChanged:) name:SGFontLibraryChangedNotification object:nil];
    [center addObserver:self selector:@selector(backgroundChanged:) name:SGNowPlayingInfoDidChangeNotification object:nil];
    return self;
}

- (AVSampleBufferDisplayLayer *)displayLayer { return (AVSampleBufferDisplayLayer *)self.host.layer; }

- (void)announce {
    [NSNotificationCenter.defaultCenter postNotificationName:SGLyricsPiPDidChangeNotification object:nil];
}

- (void)showFailure {
    if (!_alertPending || UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return;
    UIViewController *presenter = _window.rootViewController;
    while (presenter.presentedViewController) presenter = presenter.presentedViewController;
    if (!presenter || presenter.isBeingDismissed) return;
    _alertPending = NO;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:SGL(@"settings.lyrics.pip.title", @"Picture in Picture lyrics")
        message:SGL(@"settings.lyrics.pip.failed", @"Picture in Picture could not start. This device or Spotify's current playback session may not support it. Keep Spotify in front and try again.")
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:SGL(@"common.ok", @"OK") style:UIAlertActionStyleDefault handler:nil]];
    SGPresentDark(alert);
    [presenter presentViewController:alert animated:YES completion:nil];
}

- (void)fail:(NSString *)reason {
    SGLog(@"lyrics PiP: %@", reason);
    _stopping = YES;
    [_pip stopPictureInPicture];
    [self finish];
    _alertPending = YES;
    [self showFailure];
}

- (void)finish {
    [self completeSeek];
    _attempt++;
    _generation++;
    _retryPending = NO;
    _starting = NO;
    _startRequested = NO;
    _stopping = NO;
    _active = NO;
    [_timer invalidate];
    _timer = nil;
    [self.displayLayer flushAndRemoveImage];
    if (_timebase) CMTimebaseSetRate(_timebase, 0);
    [_host removeFromSuperview];
    _shown = nil;
    _shownStyle = nil;
    _sourceLines = nil;
    _preparedLines = nil;
    _pendingLines = nil;
    _track = nil;
    _artworkTrack = nil;
    [_background invalidate];
    // A cancelled start may still deliver callbacks. Give the next attempt its own controller
    // identity so an old didStart/didStop can never start or tear down the new session.
    [_pip removeObserver:self forKeyPath:@"pictureInPicturePossible" context:kPossibleContext];
    _pip.contentSource = nil;
    _pip = nil;
    if (_pool) { CVPixelBufferPoolRelease(_pool); _pool = NULL; }
    [self announce];
}

- (BOOL)prepareIn:(UIWindow *)window {
    if (!_host) {
        _host = [[SGLyricsPiPHost alloc] initWithFrame:CGRectZero];
        _host.userInteractionEnabled = NO;
        _host.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
        _host.translatesAutoresizingMaskIntoConstraints = NO;
        [NSLayoutConstraint activateConstraints:@[
            [_host.widthAnchor constraintEqualToConstant:160], [_host.heightAnchor constraintEqualToConstant:90]
        ]];
        self.displayLayer.videoGravity = AVLayerVideoGravityResizeAspect;
        OSStatus status = CMTimebaseCreateWithSourceClock(kCFAllocatorDefault, CMClockGetHostTimeClock(), &_timebase);
        if (status != noErr) return NO;
        self.displayLayer.controlTimebase = _timebase;
    }
    if (!_timebase) return NO;
    if (!_pip) {
        AVPictureInPictureControllerContentSource *source = [[AVPictureInPictureControllerContentSource alloc]
            initWithSampleBufferDisplayLayer:self.displayLayer playbackDelegate:self];
        _pip = [[AVPictureInPictureController alloc] initWithContentSource:source];
        _pip.delegate = self;
        _pip.canStartPictureInPictureAutomaticallyFromInline = NO;
        [_pip addObserver:self forKeyPath:@"pictureInPicturePossible" options:NSKeyValueObservingOptionNew context:kPossibleContext];
    }
    if (!_pip) return NO;
    if (![self preparePool:SGLyricsPiPReadStyle().raster]) return NO;
    _host.alpha = 1;
    [window addSubview:_host];
    [NSLayoutConstraint activateConstraints:@[
        [_host.leadingAnchor constraintEqualToAnchor:window.safeAreaLayoutGuide.leadingAnchor constant:12],
        [_host.bottomAnchor constraintEqualToAnchor:window.safeAreaLayoutGuide.bottomAnchor constant:-64]
    ]];
    [window layoutIfNeeded];
    return YES;
}

- (BOOL)preparePool:(CGSize)size {
    if (_pool && CGSizeEqualToSize(size, _raster)) return YES;
    [self resetFrames];
    if (_pool) { CVPixelBufferPoolRelease(_pool); _pool = NULL; }
    _raster = size;
    for (NSLayoutConstraint *constraint in _host.constraints) {
        if (constraint.firstAttribute == NSLayoutAttributeWidth) constraint.constant = 160;
        if (constraint.firstAttribute == NSLayoutAttributeHeight) constraint.constant = 160 * size.height / size.width;
    }
    {
        NSDictionary *attributes = @{(__bridge NSString *)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA),
            (__bridge NSString *)kCVPixelBufferWidthKey: @(size.width),
            (__bridge NSString *)kCVPixelBufferHeightKey: @(size.height),
            (__bridge NSString *)kCVPixelBufferCGImageCompatibilityKey: @YES,
            (__bridge NSString *)kCVPixelBufferCGBitmapContextCompatibilityKey: @YES,
            (__bridge NSString *)kCVPixelBufferIOSurfacePropertiesKey: @{}};
        if (CVPixelBufferPoolCreate(kCFAllocatorDefault, NULL, (__bridge CFDictionaryRef)attributes, &_pool) != kCVReturnSuccess) return NO;
    }
    return YES;
}

- (void)toggleFrom:(UIView *)from {
    if (_active) { _stopping = YES; [_pip stopPictureInPicture]; return; }
    if (_starting) { _stopping = YES; [_pip stopPictureInPicture]; [self finish]; return; }
    _window = from.window;
    if (![AVPictureInPictureController isPictureInPictureSupported]) {
        [self fail:@"PiP is not supported on this device"];
        return;
    }
    if (!_window) {
        [self fail:@"no source window"];
        return;
    }
    if (UIApplication.sharedApplication.applicationState != UIApplicationStateActive) {
        [self fail:@"Spotify is not in the foreground"];
        return;
    }
    if (![self prepareIn:_window]) { [self fail:@"could not prepare the display layer or pixel buffer pool"]; return; }
    _starting = YES;
    _startRequested = NO;
    _alertPending = NO;
    _restoreCredit = NO;
    NSUInteger attempt = ++_attempt;
    [self announce];
    [self refresh]; // enqueue a real first image before asking whether PiP is possible
    [self startIfPossible];
    __weak SGLyricsPiPEngine *weakSelf = self;
    // A bounded readiness/start deadline, not a repeating render timer.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 8 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        SGLyricsPiPEngine *engine = weakSelf;
        if (engine.starting && engine.attempt == attempt) [engine fail:@"timed out waiting for PiP under Spotify's audio session"];
    });
}

- (void)startIfPossible {
    if (!_starting || _startRequested || !_shown || !_pip.isPictureInPicturePossible ||
        UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return;
    _startRequested = YES;
    [_pip startPictureInPicture];
}

- (void)observeValueForKeyPath:(NSString *)path ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if (context != kPossibleContext) { [super observeValueForKeyPath:path ofObject:object change:change context:context]; return; }
    dispatch_async(dispatch_get_main_queue(), ^{ [self startIfPossible]; });
}

- (void)lyricsChanged:(NSNotification *)note {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!note.object || [note.object isEqual:self.track]) {
            self.linesDirty = YES;
            self.pendingLines = nil;
            [self refresh];
        }
    });
}

- (void)foreground:(NSNotification *)note {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self showFailure];
        [self showRestoredCredit];
        [self refresh];
    });
}

- (void)backgroundChanged:(NSNotification *)note {
    // Settings and late artwork must update a paused frame without a polling render timer.
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([note.name isEqual:NSUserDefaultsDidChangeNotification]) {
            self.linesDirty = YES;
            self.pendingLines = nil;
        }
        [self refresh];
    });
}

- (void)background:(NSNotification *)note {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.starting && !self.startRequested) [self fail:@"left the foreground before PiP was ready"];
    });
}

- (void)playerStateDidChange:(SPTPlayerState *)state { [self scheduleRefresh]; }
- (void)playerStateDidReport:(SPTPlayerState *)state { [self scheduleRefresh]; }

- (void)scheduleRefresh {
    if (!_active && !_starting) return;
    NSUInteger generation = _generation;
    // Karaoke's observer may run after ours; read its track/clock after all observers have seen the report.
    dispatch_async(dispatch_get_main_queue(), ^{
        if (generation == self.generation) [self refresh];
    });
}

- (void)resetFrames {
    _generation++;
    _shown = nil;
    [self.displayLayer flushAndRemoveImage];
}

- (void)refresh {
    if (!_active && !_starting) return;
    _style = SGLyricsPiPReadStyle();
    if (![self preparePool:_style.raster]) { [self fail:@"could not resize pixel buffer pool"]; return; }
    if (self.displayLayer.status == AVQueuedSampleBufferRenderingStatusFailed) {
        [self fail:[NSString stringWithFormat:@"display layer failed: %@", self.displayLayer.error]];
        return;
    }
    NSString *track = SGKaraokePlayingTrack();
    SPTPlayerState *state = [(id<SPTPlayer>)SGKaraokePlayer() state];
    NSString *artworkTrack = SGURIString(state.track.URI);
    double position = MAX(0, SGKaraokePositionMs()) / 1000.0;
    BOOL changedTrack = ![_track isEqualToString:track] && (_track || track);
    changedTrack |= ![_artworkTrack isEqualToString:artworkTrack] && (_artworkTrack || artworkTrack);
    if (_seekCompletion && ![_seekTrack isEqual:artworkTrack]) [self completeSeek];
    BOOL seekArrived = _seekCompletion && !state.isLoading && fabs(position - _seekTarget / 1000.0) <= .75;
    // Spotify reports loading/not-playing while an asynchronous seek is in flight. That is not
    // a user pause. Keep the pre-seek clock rate until a report lands or a real play/pause arrives.
    BOOL seeking = _seekCompletion != nil;
    if (seeking && !seekArrived) position = _position;
    double clock = CMTimeGetSeconds(CMTimebaseGetTime(_timebase));
    // Position-only reports include scrubs. A discontinuity retires the previous track/seek's image.
    BOOL jumped = !isfinite(clock) || fabs(clock - position) > 0.25;
    if (changedTrack || jumped) [self resetFrames];
    BOOL playing = seeking ? _seekWasPlaying : state && state.isPlaying && !state.isPaused && !state.isLoading;
    double duration = isfinite(state.duration) && state.duration > 0 ? state.duration : 0;
    double speed = isfinite(state.playbackSpeed) && state.playbackSpeed > 0 ? state.playbackSpeed : 1;
    BOOL playbackChanged = changedTrack || jumped || playing != _playing || duration != _duration || speed != _speed;
    _track = [track copy];
    _artworkTrack = [artworkTrack copy];
    [_background refreshForTrack:artworkTrack];
    _position = position;
    _duration = duration;
    _playing = playing;
    _speed = speed;
    CMTimebaseSetTime(_timebase, CMTimeMakeWithSeconds(position, 1000));
    CMTimebaseSetRate(_timebase, _playing ? _speed : 0);
    if (seekArrived) [self completeSeek];
    if (playbackChanged || !_duration) [_pip invalidatePlaybackState];
    if (_active && _playing && !_timer) {
        __weak SGLyricsPiPEngine *weakSelf = self;
        _timer = [NSTimer timerWithTimeInterval:0.25 repeats:YES block:^(NSTimer *timer) { [weakSelf refresh]; }];
        [NSRunLoop.mainRunLoop addTimer:_timer forMode:NSRunLoopCommonModes];
    } else if (!_active || !_playing) {
        [_timer invalidate];
        _timer = nil;
    }
    if (track.length && !SGKaraokeLinesForTrack(track)) SGKaraokeRequestLyrics(track);
    NSArray<SGKaraokeLine *> *lines = track.length ? SGKaraokeLinesForTrack(track) : nil;
    if (changedTrack || _linesDirty || _sourceLines != lines) {
        _linesDirty = NO;
        _sourceLines = lines;
        if (changedTrack) _preparedLines = nil;
        NSMutableArray *copies = [NSMutableArray arrayWithCapacity:lines.count];
        for (SGKaraokeLine *line in lines) [copies addObject:[line copy]];
        _pendingLines = copies;
        if (track.length && copies.count) {
            NSString *language = SGLyricsGeminiLanguage();
            __weak SGLyricsPiPEngine *weakSelf = self;
            SGLyricsLoadTranslation(track, language, copies, ^BOOL {
                SGLyricsPiPEngine *engine = weakSelf;
                return engine && (engine.active || engine.starting) && [engine.track isEqual:track]
                    && engine.sourceLines == lines && engine.pendingLines == copies
                    && [language isEqual:SGLyricsGeminiLanguage()];
            }, ^{
                SGLyricsPiPEngine *engine = weakSelf;
                engine.preparedLines = copies;
                engine.pendingLines = nil;
                [engine refresh];
            });
        }
        NSString *notation = [NSString stringWithFormat:@"%ld", (long)[NSUserDefaults.standardUserDefaults integerForKey:SGKeyLyricsPronunciationNotation]];
        NSDictionary *saved = track.length && copies.count ? SGLyricsAIValues(@"pronunciation", track, notation) : nil;
        for (SGKaraokeLine *line in copies) {
            if (line.pronunciation && !line.pronunciationMade) continue;
            NSString *text = saved[SGKaraokeLineText(line)];
            SGKaraokeLine *spoken = nil;
            if (text.length) {
                SGKaraokeWord *word = [SGKaraokeWord new]; word.text = text;
                spoken = [SGKaraokeLine new]; spoken.words = @[word];
            }
            line.pronunciation = spoken;
        }
        if (!track.length || !copies.count) {
            _preparedLines = lines ? copies : nil;
            _pendingLines = nil;
        }
    }
    // A refresh never exposes the unfinished copies. Same-track frames keep their
    // prepared supplements; a new track waits for its first ordered store read.
    if (_pendingLines && !_preparedLines) return;
    // The lyrics views apply language defaults once per song to these shared switches.
    // They are also the current manual choice: reapplying a rule here on open/reopen would
    // undo that choice. Read the effective switches, including a queued next-song update,
    // without owning a second rule ledger or changing preferences.
    BOOL showTranslation = SGFlag(@"spotifyglass.redesign.lyricsTranslation", NO);
    BOOL showPronunciation = SGFlag(@"spotifyglass.redesign.lyricsPronunciation", NO);
    lines = _preparedLines;
    NSString *current = nil, *next = nil;
    SGLyricsPiPTextKind kind = SGLyricsPiPTextFor(lines, SGKaraokePositionMs() - SGKaraokeDelayMs(), &current, &next);
    if (kind == SGLyricsPiPTextNoLyrics) {
        BOOL failed = SGLyricsLoadFailed(track);
        current = failed ? SGL(@"settings.lyrics.load_failed", @"Couldn't load lyrics · Retry")
            : SGL(@"settings.lyrics.pip.no_lyrics", @"No lyrics available");
        if (failed) next = SGL(@"settings.lyrics.pip.open_retry", @"Open Spotify to retry");
    } else if (kind == SGLyricsPiPTextInstrumental) {
        current = SGL(@"settings.lyrics.pip.instrumental", @"Instrumental");
    } else if (kind == SGLyricsPiPTextUntimed) {
        next = SGL(@"settings.lyrics.pip.untimed", @"These lyrics are not synced");
    }
    NSString *credit = track.length ? SGLyricsCreditFor(track) : nil;
    // Always credit every provider, a stronger rule than SGLyricsCreditRequired: full Spicy
    // maker/uploader attribution even with Show source off. Linked again on return from PiP.
    SGKaraokeLine *selected = SGLyricsPiPSelectedLine(lines, SGKaraokePositionMs() - SGKaraokeDelayMs());
    SGShownTrack *metadata = SGShownTrackNow();
    BOOL currentMetadata = metadata.current && [metadata.uri isEqual:artworkTrack];
    NSArray<NSString *> *content = @[current ?: @"", next ?: @"", credit ?: @"",
        showPronunciation ? SGKaraokeLineText(selected.pronunciation) ?: @"" : @"",
        showTranslation ? SGLyricsShownTranslation(selected) ?: @"" : @"",
        currentMetadata ? metadata.title ?: @"" : @"", currentMetadata ? metadata.artist ?: @"" : @""];
    if (_background.image && (![_shown isEqualToArray:content] || _shownBackgroundRevision != _background.revision ||
        ![_shownStyle isEqual:_style.identity]))
        [self enqueue:content generation:_generation];
    [self startIfPossible];
}

// A layer that is not ready, or a full pool, would otherwise drop the frame with nothing left to
// show it: a start waits on _shown, and a paused engine has no repeating refresh.
- (void)scheduleRetry {
    if (_retryPending || (!_active && !_starting)) return;
    _retryPending = YES;
    NSUInteger attempt = _attempt;
    __weak SGLyricsPiPEngine *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        SGLyricsPiPEngine *engine = weakSelf;
        if (engine.attempt != attempt) return; // a stale block must not clear the new attempt's flag
        engine.retryPending = NO;
        [engine refresh];
    });
}

- (void)enqueue:(NSArray<NSString *> *)content generation:(NSUInteger)generation {
    AVSampleBufferDisplayLayer *layer = self.displayLayer;
    if (!layer.readyForMoreMediaData) { [self scheduleRetry]; return; }
    CVPixelBufferRef pixel = NULL;
    // The allocation threshold is a hard bound even if the system retains enqueued frames.
    NSDictionary *aux = @{(__bridge NSString *)kCVPixelBufferPoolAllocationThresholdKey: @3};
    CVReturn result = CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(kCFAllocatorDefault, _pool,
                                                                          (__bridge CFDictionaryRef)aux, &pixel);
    if (result == kCVReturnWouldExceedAllocationThreshold) { [self scheduleRetry]; return; }
    if (result != kCVReturnSuccess) { [self fail:@"pixel buffer allocation failed"]; return; }
    if (CVPixelBufferLockBaseAddress(pixel, 0) != kCVReturnSuccess) {
        CVPixelBufferRelease(pixel);
        [self fail:@"pixel buffer lock failed"];
        return;
    }
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(CVPixelBufferGetBaseAddress(pixel), _raster.width,
        _raster.height, 8, CVPixelBufferGetBytesPerRow(pixel), space,
        kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);
    CGColorSpaceRelease(space);
    if (context) {
        SGLyricsPiPDrawStyledFrame(context, content, _style, _background.image.CGImage, _background.cover.CGImage);
        CGContextRelease(context);
    }
    CVPixelBufferUnlockBaseAddress(pixel, 0);
    if (!context) { CVPixelBufferRelease(pixel); [self fail:@"bitmap context creation failed"]; return; }
    CMVideoFormatDescriptionRef format = NULL;
    CMSampleBufferRef sample = NULL;
    OSStatus status = CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault, pixel, &format);
    CMSampleTimingInfo timing = {kCMTimeInvalid, CMTimeMakeWithSeconds(_position, 1000), kCMTimeInvalid};
    if (status == noErr) status = CMSampleBufferCreateReadyWithImageBuffer(kCFAllocatorDefault, pixel, format, &timing, &sample);
    CVPixelBufferRelease(pixel);
    if (format) CFRelease(format);
    if (status != noErr || !sample) { [self fail:@"sample buffer creation failed"]; return; }
    CFArrayRef attachments = CMSampleBufferGetSampleAttachmentsArray(sample, true);
    CFMutableDictionaryRef attachment = (CFMutableDictionaryRef)CFArrayGetValueAtIndex(attachments, 0);
    CFDictionarySetValue(attachment, kCMSampleAttachmentKey_DisplayImmediately, kCFBooleanTrue);
    if (generation == _generation && (_active || _starting)) {
        [layer enqueueSampleBuffer:sample];
        _shown = content;
        _shownStyle = _style.identity;
        _shownBackgroundRevision = _background.revision;
    }
    CFRelease(sample);
}

- (void)pictureInPictureControllerDidStartPictureInPicture:(AVPictureInPictureController *)controller {
    if (controller != _pip || !_starting) { [controller stopPictureInPicture]; return; }
    _starting = NO;
    _active = YES;
    _host.alpha = 0; // the real layer stays attached; only its inline preview goes away
    [self announce];
    [self refresh];
}

- (void)pictureInPictureController:(AVPictureInPictureController *)controller failedToStartPictureInPictureWithError:(NSError *)error {
    if (controller == _pip && _starting) [self fail:[NSString stringWithFormat:@"start failed under Spotify's audio session: %@", error]];
}

- (void)pictureInPictureControllerDidStopPictureInPicture:(AVPictureInPictureController *)controller {
    if (controller != _pip) return;
    [self finish]; // closing the window never sends a player command
    [self showRestoredCredit];
}

- (void)pictureInPictureControllerWillStopPictureInPicture:(AVPictureInPictureController *)controller {
    if (controller == _pip) _stopping = YES;
}

- (BOOL)pictureInPictureControllerShouldProhibitBackgroundAudioPlayback:(AVPictureInPictureController *)controller {
    return NO; // Spotify's audio must survive closing the PiP window.
}

- (void)showRestoredCredit {
    if (!_restoreCredit || UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return;
    UIViewController *presenter = _window.rootViewController;
    while (presenter.presentedViewController) presenter = presenter.presentedViewController;
    if (!presenter || presenter.isBeingDismissed) return;
    NSString *track = SGKaraokePlayingTrack();
    NSString *credit = track.length ? SGLyricsCreditFor(track) : nil;
    NSArray<SGLyricsLink *> *links = SGLyricsCreditLinks(credit);
    _restoreCredit = NO;
    if (SGLyricsLoadFailed(track)) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:
            SGL(@"settings.lyrics.load_failed", @"Couldn't load lyrics · Retry") message:nil preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:SGL(@"settings.lyrics.retry", @"Retry")
            style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { SGLyricsRetry(track); }]];
        [alert addAction:[UIAlertAction actionWithTitle:SGL(@"common.cancel", @"Cancel") style:UIAlertActionStyleCancel handler:nil]];
        SGPresentDark(alert);
        [presenter presentViewController:alert animated:YES completion:nil];
        return;
    }
    if (!links.count) return;
    // Return to Spotify first; never launch an uploader's URL merely because PiP was restored.
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:credit message:nil preferredStyle:UIAlertControllerStyleAlert];
    __weak UIWindow *window = _window;
    [alert addAction:[UIAlertAction actionWithTitle:SGL(@"settings.lyrics.pip.credit_links", @"View source credits")
        style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            if (window) SGLyricsOpenCreditLinks(links, window);
        }]];
    [alert addAction:[UIAlertAction actionWithTitle:SGL(@"common.cancel", @"Cancel") style:UIAlertActionStyleCancel handler:nil]];
    SGPresentDark(alert);
    [presenter presentViewController:alert animated:YES completion:nil];
}

- (void)pictureInPictureController:(AVPictureInPictureController *)controller
    restoreUserInterfaceForPictureInPictureStopWithCompletionHandler:(void (^)(BOOL restored))completionHandler {
    // The owning Spotify window never depended on a lyrics page remaining alive.
    if (controller == _pip) _restoreCredit = YES;
    completionHandler(YES);
}

- (void)pictureInPictureController:(AVPictureInPictureController *)controller setPlaying:(BOOL)playing {
    if (controller != _pip || _stopping) return;
    // An explicit later request wins over the seek's captured intent. Never resume in a seek
    // completion: doing so would unpause a user-paused song or a newly switched track.
    if (_seekCompletion) _seekWasPlaying = playing;
    id<SPTPlayer> player = SGKaraokePlayer();
    SPTPlayerState *state = player.state;
    if (!state) return;
    if (playing && state.isPaused) [player resume:nil];
    else if (!playing && !state.isPaused) [player pause:nil];
    [self scheduleRefresh];
}

- (BOOL)pictureInPictureControllerIsPlaybackPaused:(AVPictureInPictureController *)controller {
    return controller != _pip || !_playing;
}

- (CMTimeRange)pictureInPictureControllerTimeRangeForPlayback:(AVPictureInPictureController *)controller {
    // Finite, track-relative and always contains the layer's running time, even without a duration.
    double clock = _timebase ? CMTimeGetSeconds(CMTimebaseGetTime(_timebase)) : 0;
    double end = MAX(_duration, MAX(_position, isfinite(clock) ? clock : 0) + 1);
    return CMTimeRangeMake(kCMTimeZero, CMTimeMakeWithSeconds(end, 1000));
}

- (void)pictureInPictureController:(AVPictureInPictureController *)controller
    skipByInterval:(CMTime)interval completionHandler:(void (^)(void))completionHandler {
    double delta = CMTimeGetSeconds(interval);
    SPTPlayerState *state = [(id<SPTPlayer>)SGKaraokePlayer() state];
    NSString *track = SGURIString(state.track.URI);
    double duration = state.duration;
    if (controller == _pip && !_stopping && _timebase && isfinite(delta) && isfinite(duration) && duration > 0) {
        BOOL sameSeekTrack = _seekCompletion && track.length && [_seekTrack isEqual:track];
        double origin = sameSeekTrack ? _seekTarget / 1000.0 : SGKaraokePositionMs() / 1000.0;
        [self completeSeek];
        double target = MIN(duration, MAX(0, origin + delta));
        NSInteger targetMs = (NSInteger)llround(target * 1000);
        _seekCompletion = [completionHandler copy];
        _seekTrack = track;
        _seekTarget = targetMs;
        _seekWasPlaying = !state.isPaused;
        NSUInteger token = ++_seekToken;
        [self resetFrames];
        SGKaraokeSeek(targetMs);
        // Completion is an acknowledgement, not "request sent". The next settled Spotify
        // position must agree before AVKit reads the clock and playback rate.
        _position = targetMs / 1000.0;
        CMTimebaseSetTime(_timebase, CMTimeMake(targetMs, 1000));
        CMTimebaseSetRate(_timebase, _seekWasPlaying ? _speed : 0);
        [_pip invalidatePlaybackState];
        __weak SGLyricsPiPEngine *weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            SGLyricsPiPEngine *self = weakSelf;
            if (!self || self.seekToken != token || !self.seekCompletion) return;
            // Rejected seeks must also release AVKit's controls, but never start audio.
            [self completeSeek];
            [self refresh];
        });
        return;
    }
    completionHandler();
}

- (void)completeSeek {
    void (^completion)(void) = _seekCompletion;
    _seekCompletion = nil;
    _seekTrack = nil;
    ++_seekToken;
    if (completion) {
        // Success, timeout, replacement, stop and track switch all acknowledge with the actual
        // player clock/rate, never the optimistic target or a stale loading state.
        SPTPlayerState *state = [(id<SPTPlayer>)SGKaraokePlayer() state];
        _position = MAX(0, SGKaraokePositionMs()) / 1000.0;
        _playing = state && state.isPlaying && !state.isPaused && !state.isLoading;
        if (_timebase) {
            CMTimebaseSetTime(_timebase, CMTimeMakeWithSeconds(_position, 1000));
            CMTimebaseSetRate(_timebase, _playing ? _speed : 0);
        }
        completion();
    }
}

- (void)pictureInPictureController:(AVPictureInPictureController *)controller
    didTransitionToRenderSize:(CMVideoDimensions)newRenderSize {
    // The chosen aspect, not the floating window's transient size, bounds our CPU raster.
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
    [_pip removeObserver:self forKeyPath:@"pictureInPicturePossible" context:kPossibleContext];
    [_timer invalidate];
    if (_pool) CVPixelBufferPoolRelease(_pool);
    if (_timebase) CFRelease(_timebase);
}
@end

__attribute__((constructor)) static void lyricsPiPLaunch(void) {
    @autoreleasepool { sg_enabled = SGFlag(SGKeyLyricsPiP, NO); }
}
