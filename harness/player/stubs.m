#import "substrate.h"
// What the player harness does not compile: the Kit's hooks (SGRAccent.x, SGRRepaint.x), the rest of
// the player's hooks, the lyrics store and the haptics. Everything here answers the way the phone would
// for one track with lyrics, so the redesign's own code is what is being looked at. The player itself
// is a mock the harness drives: SGRHarnessSetTrack reports a track change to every observer.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "Shared/Lyrics/Lyrics.h"
#import "Headers/SPTPlayer.h"
#import "Shared/Player/PlayerState.h"
#import "Shared/Lyrics/PixieLyricsQueue.h"
#import "Shared/Player/SGMusicSpectrum.h"
#import "Shared/Player/SleepTimer.h"

// No Spotify audio unit in the UI mock.
static NSUInteger spectrumReaders;
NSUInteger SGRHarnessSpectrumReaders(void) { return spectrumReaders; }
void SGMusicSpectrumAddReader(void) { spectrumReaders++; }
void SGMusicSpectrumRemoveReader(void) { spectrumReaders--; }
uint64_t SGMusicSpectrumReadings(void) { return 0; }
BOOL SGMusicSpectrumReading(uint64_t index, float levels[3]) { return NO; }

// The queue's menu is linked with the player; the Spotify repeat and sleep
// commands it offers aren't exercised by the UI mock.
id SGPlayerAdvanceRepeat(id<SPTPlayer> player, SPTPlayerOptions *options) { return nil; }
SGSleepTimerMode SGSleepTimerCurrentMode(void) { return SGSleepTimerOff; }
NSDate *SGSleepTimerEnd(void) { return nil; }
void SGSetSleepTimer(SGSleepTimerMode mode, NSTimeInterval seconds) {}

#pragma mark - LyricsSettings.m's lyrics sources and Pixie lyrics queue

// No source is on and no Pixie companion is loaded, so the Lyrics page shows no Pixie lyrics rows.
BOOL SGLyricsEnabled(void) { return NO; }
BOOL SGPixieLyricsAvailable(void) { return NO; }
void SGPixieLyricsSettingsChanged(void) {}
void SGPixieLyricsDownloadMissing(void) {}
void SGPixieLyricsDeleteSaved(void (^done)(unsigned long long)) { if (done) done(0); }
NSDictionary<NSString *, NSNumber *> *SGPixieLyricsCounts(void) { return @{}; }
NSNotificationName const SGPixieLyricsProgress = @"SGPixieLyricsProgress";

#pragma mark - SGRAccent.x, SGRRepaint.x

UIColor *SGRAccentColor(void) { return nil; }
// Spotify's own green is kept, so no color is swapped (PlayerCoverAccent.x asks).
NSInteger SGRAccentRGB(void) { return 0x1ED760; }
BOOL SGRAccentSwap(CGFloat *r, CGFloat *g, CGFloat *b) { return NO; }
__weak UIView *sgr_nowPlayingRoot = nil;
NSHashTable<UIView *> *sgr_nowPlayingPainted = nil;
__weak UIView *sgr_lyricsPageRoot = nil;
__weak UIView *sgr_playlistRoot = nil;
// The accent's provenance (SGRAccent.m), which Follow the cover reads: no color here is the accent's.
@class SGRAccentToken;
NSNotificationName const SGRAccentDidChangeNotification = @"harness.accentDidChange";
BOOL SGRAccentIsToken(UIColor *color) { return NO; }
SGRAccentToken *SGRAccentSource(UIColor *color) { return nil; }
SGRAccentToken *SGRAccentImageSource(UIImage *image) { return nil; }
SGRAccentToken *SGRAccentLayerSource(CAShapeLayer *layer, BOOL stroke) { return nil; }
UIImage *SGRAccentTintedImage(UIImage *image, UIColor *override) { return image; }
void SGRAccentSetLayerOverride(CALayer *layer, UIColor *override) {}
// NowPlayingBar.x: no now playing bar follows the tab bar here.
void SGRNowPlayingBarFollowTabBar(void) {}

#pragma mark - Shared/Player/PlayerEvents.x

NSString *const SGPlayerTransitionNotification = @"spotifyglass.playerTransition";
NSNotificationName const SGPlayerSpeedDidChangeNotification = @"spotifyglass.player.speedChanged";
NSString *const SGPlayerTransitionEndedNotification = @"spotifyglass.playerTransitionEnded";
// No open or close runs, unless the automix scenario says one does until a time (SGRHarnessSetTransitionEnds).
static CFTimeInterval sg_transitionEnds;
CFTimeInterval SGPlayerTransitionEnds(void) { return sg_transitionEnds; }
void SGRHarnessSetTransitionEnds(CFTimeInterval ends) { sg_transitionEnds = ends; }

#pragma mark - Shared/Player/PlayerState.x

NSString *SGURIString(id uri) {
    if ([uri isKindOfClass:NSString.class]) return uri;
    if ([uri isKindOfClass:NSURL.class]) return ((NSURL *)uri).absoluteString;
    return nil;
}

// The harness's player has no queue after the track.
SPTPlayerTrack *SGPlayerUpNextIn(SPTPlayerState *state) { return nil; }

// A player that plays what the harness tells it to, reporting on the main thread the way
// Shared/Player/PlayerState.x moves Spotify's reports onto it.
@implementation SPTPlayerTrack
@end
@implementation SPTPlayerOptions
@end
@implementation SPTPlayerState
@end

static NSHashTable *sg_observers;
static SPTPlayerState *sg_state;

void SGAddPlayerStateObserver(id observer) {
    if (!sg_observers) sg_observers = [NSHashTable weakObjectsHashTable];
    [sg_observers addObject:observer];
}
SPTPlayerState *SGPlayerState(void) { return sg_state; }

// A state the harness made whole, reported as Spotify reports: every report, then the change.
void SGRHarnessReport(SPTPlayerState *state) {
    sg_state = state;
    for (id<SGPlayerStateObserver> observer in sg_observers.allObjects) {
        if ([observer respondsToSelector:@selector(playerStateDidReport:)]) [observer playerStateDidReport:state];
        [observer playerStateDidChange:state];
    }
}

void SGRHarnessClearTrack(void) {
    sg_state = nil;
    for (id<SGPlayerStateObserver> observer in sg_observers.allObjects) [observer playerStateDidChange:nil];
}

// `imageURI` is the xlarge picture as Spotify's metadata has it, spotify:image:<40 hex digits>, or nil for
// a track whose metadata names none.
void SGRHarnessSetTrack(NSString *uri, NSString *imageURI, BOOL paused) {
    SPTPlayerTrack *track = [SPTPlayerTrack new];
    [track setValue:uri forKey:@"URI"];
    NSMutableDictionary *metadata = [@{@"title": uri} mutableCopy];
    BOOL settings = [NSProcessInfo.processInfo.environment[@"HARNESS_SCENARIO"] isEqualToString:@"settings"];
    if (settings && [uri isEqualToString:@"spotify:track:harnessA"]) metadata[@"title"] = @"Loose Canon";
    [track setValue:metadata[@"title"] forKey:@"trackTitle"];
    if (settings) [track setValue:@"Retrine harness" forKey:@"artistName"];
    if (imageURI) {
        // The four sizes share the picture's last 24 digits (out/karaoke-diag.log:174-177 on the phone).
        NSString *hash = [imageURI substringFromIndex:imageURI.length - 24];
        metadata[@"image_xlarge_url"] = imageURI;
        metadata[@"image_large_url"] = imageURI;
        metadata[@"image_url"] = [@"spotify:image:ab67616d00001e02" stringByAppendingString:hash];
        metadata[@"image_small_url"] = [@"spotify:image:ab67616d00004851" stringByAppendingString:hash];
    }
    // HARNESS_ARTIST, HARNESS_ALBUM and HARNESS_CANVAS (a video URL) give Animated artwork something to find.
    NSDictionary<NSString *, NSString *> *env = NSProcessInfo.processInfo.environment;
    if (env[@"HARNESS_ARTIST"]) [track setValue:env[@"HARNESS_ARTIST"] forKey:@"artistName"];
    if (env[@"HARNESS_ALBUM"]) metadata[@"album_title"] = env[@"HARNESS_ALBUM"];
    if (env[@"HARNESS_CANVAS"]) {
        metadata[@"canvas.type"] = @"VIDEO_LOOPING_RANDOM";
        metadata[@"canvas.url"] = env[@"HARNESS_CANVAS"];
    }
    [track setValue:metadata forKey:@"metadata"];
    SPTPlayerState *state = [SPTPlayerState new];
    [state setValue:track forKey:@"track"];
    [state setValue:@(paused) forKey:@"isPaused"];
    [state setValue:@(!paused) forKey:@"isPlaying"];
    if (settings) {
        [state setValue:@75 forKey:@"position"];
        [state setValue:@240 forKey:@"duration"];
    }
    sg_state = state;
    for (id<SGPlayerStateObserver> observer in sg_observers.allObjects) [observer playerStateDidChange:state];
}

#pragma mark - Shared/Haptics

void SGPlayFeedback(NSInteger feedback) {}
void SGPrepareFeedback(NSInteger feedback) {}
void SGInstallVolumeFeedback(UISlider *slider) {}

#pragma mark - Redesigned/Player/PlayerConnectVolume.x

NSNotificationName const SGRConnectVolumeChangedNotification = @"harness.connectVolumeChanged";
// The volume row shows its Connect slider while a scenario sets this (main.m's volumebar), and the device takes what
// the slider sends it; it starts at half.
BOOL SGRHarnessConnectVolume;
double SGRHarnessConnectLevel = 0.5;
BOOL SGRConnectReadVolume(double *value) {
    if (SGRHarnessConnectVolume && value) *value = SGRHarnessConnectLevel;
    return SGRHarnessConnectVolume;
}
BOOL SGRConnectSetVolume(double value) {
    if (SGRHarnessConnectVolume) SGRHarnessConnectLevel = value;
    return SGRHarnessConnectVolume;
}

#pragma mark - Shared/LyricsSources

NSString *SGLyricsCreditFor(NSString *trackID) { return @"the harness"; }
BOOL SGLyricsCreditRequired(NSString *credit) { return NO; }
NSArray *SGLyricsCreditLinks(NSString *text) { return nil; }
void SGLyricsOpenCreditLinks(NSArray *links, UIView *from) {}

#pragma mark - Shared/Lyrics/KaraokeSource.x

static NSArray<SGKaraokeLine *> *sg_lines;
static NSString *sg_track = @"harness";
static NSInteger sg_position;
static CFTimeInterval sg_started;

// The player's commands (Headers/SPTPlayer.h) counted, for the settings scenario: the Player page's card must never
// send one. Every selector of the protocol is answered with nil.
@interface SGRHarnessPlayerRecorder : NSObject
@end
static NSUInteger sg_playerCommands;
NSUInteger SGRHarnessPlayerCommands(void) { return sg_playerCommands; }
@implementation SGRHarnessPlayerRecorder
static struct objc_method_description playerMethod(SEL selector) {
    struct objc_method_description method = protocol_getMethodDescription(@protocol(SPTPlayer), selector, YES, YES);
    return method.name ? method : protocol_getMethodDescription(@protocol(SPTPlayer), selector, NO, YES);
}
- (BOOL)respondsToSelector:(SEL)selector {
    return playerMethod(selector).name != NULL || [super respondsToSelector:selector];
}
- (NSMethodSignature *)methodSignatureForSelector:(SEL)selector {
    struct objc_method_description method = playerMethod(selector);
    return method.name ? [NSMethodSignature signatureWithObjCTypes:method.types] : [super methodSignatureForSelector:selector];
}
- (void)forwardInvocation:(NSInvocation *)invocation {
    sg_playerCommands++;
    NSLog(@"[harness] player command %@", NSStringFromSelector(invocation.selector));
    if (invocation.methodSignature.methodReturnLength == sizeof(id) && invocation.methodSignature.methodReturnType[0] == '@') {
        id none = nil;
        [invocation setReturnValue:&none];
    }
}
@end
static id playerRecorder(void) {
    static SGRHarnessPlayerRecorder *recorder;
    if (!recorder) recorder = [SGRHarnessPlayerRecorder new];
    return recorder;
}
id SGPlayer(void) { return playerRecorder(); }
id SGPlayerInstance(void) { return playerRecorder(); }

NSString *SGKaraokePlayingTrack(void) { return sg_track; }
NSArray<SGKaraokeLine *> *SGKaraokeLinesForTrack(NSString *trackID) { return sg_lines; }
void SGKaraokeKeepLines(NSString *trackID, NSArray<SGKaraokeLine *> *lines) { sg_lines = lines; }
void SGKaraokeRequestLyrics(NSString *trackID) {}
NSNotificationName const SGKaraokeLinesKeptNotification = @"harness.karaokeLinesKept";
BOOL SGKaraokeLooking(NSString *trackID) { return NO; }
// No player, but for the settings and automix scenarios, whose recorder counts the commands sent to it.
id SGKaraokePlayer(void) {
    const char *scenario = getenv("HARNESS_SCENARIO");
    return scenario && (!strcmp(scenario, "settings") || !strcmp(scenario, "automix")) ? playerRecorder() : nil;
}
SPTPlayerTrack *SGKaraokeTrackFor(NSString *trackID) { return nil; }
void SGKaraokeRememberTrack(SPTPlayerTrack *track, NSString *trackID) {}

// The song runs on from the moment the harness started it, so the sweep is alive in a screenshot.
NSInteger SGKaraokeDelayMs(void) { return [NSUserDefaults.standardUserDefaults integerForKey:SGKeyLyricsDelay]; }

NSInteger (^SGRHarnessPositionDuringPlacement)(void);
NSInteger SGKaraokePositionMs(void) {
    if (SGRHarnessPositionDuringPlacement) return SGRHarnessPositionDuringPlacement();
    if (!sg_started) return sg_position;
    return sg_position + (NSInteger)((CACurrentMediaTime() - sg_started) * 1000);
}
void SGKaraokeSeek(NSInteger ms) {
    sg_position = ms;
    sg_started = CACurrentMediaTime();
}
void SGRHarnessPlayFrom(NSInteger ms) { SGKaraokeSeek(ms); }

// Line meanings: Genius is not asked in the harness. The sheet itself is the real one (MeaningSheet.m).
#import "Shared/LyricsMeanings/Meanings.h"
@implementation SGLyricsMeaning
@end
void SGLyricsMeaningsFor(NSString *trackID, NSArray<SGKaraokeLine *> *lines,
                         void (^done)(NSDictionary<NSNumber *, NSArray<SGLyricsMeaning *> *> *byLine)) {}

// Apple's on-device translation (OnDeviceTranslation.swift, not built here) and the settings framework's
// top controller: not part of the harness. The Gemini provider and saved translations are real files now.
#import "Shared/LyricsTranslation/LyricsTranslation.h"
// The saved-library management screen is outside the player harness.
UIViewController *SGSavedTranslationsPage(void) { return nil; }
@implementation SGOnDeviceTranslation
+ (BOOL)translationAvailable { return NO; }
+ (BOOL)appleIntelligenceAvailable:(NSString *)language { return NO; }
+ (void)translate:(NSArray<NSString *> *)texts to:(NSString *)language
             done:(void (^)(NSArray<NSString *> *, NSString *))done { done(nil, @"harness"); }
+ (void)translateWithAppleIntelligence:(NSArray<NSString *> *)texts to:(NSString *)language song:(NSString *)song
                              progress:(void (^)(NSArray<NSString *> *))progress
                                  done:(void (^)(NSArray<NSString *> *, NSString *))done { done(nil, @"harness"); }
@end
// Upstream's AI API is not linked by this fork; keep its harness-only stubs as well.
BOOL SGAITranslatorReady(void) { return NO; }
NSString *SGLyricsTranslationTarget(void) { return @"en"; }
void SGLyricsTranslateWithAI(NSString *trackID, NSArray<SGKaraokeLine *> *lines, NSString *languageTag,
                             void (^done)(NSArray<NSString *> *translations, NSString *error)) { done(nil, @"harness"); }
NSString *SGAITranslatorName(void) { return @"Gemini"; }
BOOL SGLyricsTranslateTextsAvailable(void) { return NO; }
void SGLyricsTranslateTexts(NSArray<NSString *> *texts, NSString *languageTag, UIView *presentingView,
                            void (^done)(NSArray<NSString *> *translations, NSString *error)) { done(nil, @"harness"); }
// AIServices.m's prose helpers, which the translators linked here reach: no prose is translated in the harness.
NSString *SGLyricsProseTooLong(void) { return @"harness"; }
void SGLyricsTranslateSegments(NSArray<NSString *> *texts, NSUInteger maxSize, NSInteger unit,
                               void (^send)(NSArray<NSString *> *, void (^)(NSArray<NSString *> *, NSString *)),
                               void (^done)(NSArray<NSString *> *, NSString *)) { done(nil, @"harness"); }
NSString *SGAITranslatorRecipient(void) { return @"Google"; }
@interface SGTranslationSource : NSObject
@property (nonatomic, copy, readonly) NSString *by, *model;
@property (nonatomic, readonly) NSDate *made;
+ (instancetype)by:(NSString *)by model:(NSString *)model made:(NSDate *)made;
@property (nonatomic, readonly) NSString *name;
@property (nonatomic, readonly) BOOL deletable;
@end
@implementation SGTranslationSource
+ (instancetype)by:(NSString *)by model:(NSString *)model made:(NSDate *)made { return [self new]; }
- (NSString *)name { return @"Unknown"; }
- (BOOL)deletable { return NO; }
@end
SGTranslationSource *SGAITranslatorSource(void) { return [SGTranslationSource by:@"gemini" model:nil made:nil]; }
void SGLyricsDeleteSavedTranslation(NSString *track, NSString *language) {}

// Local files: no edits in the harness, so the name is all PlayerLyrics.x needs to watch for one.
#import "Shared/LocalFiles/LocalFiles.h"
NSNotificationName const SGLocalFileEditsDidChangeNotification = @"harness.localFileEditsDidChange";
NSString *SGLocalFileCoverInURL(NSString *url) { return nil; }
UIImage *SGLocalFileFallbackCover(SPTPlayerTrack *track, BOOL *isMetadata) {
    if (isMetadata) *isMetadata = NO;
    return nil;
}

// The lyrics source chain and its settings page (LyricsSources.m): no provider is asked here, the
// harness feeds SGRKaraokeView its lines itself.
#import "Shared/LyricsSources/LyricsSources.h"
NSNotificationName const SGLyricsSourceChosenNotification = @"spotifyglass.lyricsSourceChosen";
NSNotificationName const SGLyricsDidReloadNotification = @"harness.lyricsDidReload";
NSNotificationName const SGLyricsOffsetsDidChangeNotification = @"harness.lyricsOffsetsDidChange";
NSNotificationName const SGLyricsPinDidChangeNotification = @"harness.lyricsPinDidChange";
NSArray<SGLyricsProvider *> *SGLyricsAllProviders(void) { return @[]; }
SGLyricsProvider *SGLyricsProviderFor(NSString *key) { return nil; }
NSArray<NSString *> *SGLyricsOrder(void) { return @[]; }
SGLyricsTypes SGLyricsSourceTypes(NSString *key) { return SGLyricsTypesAny; }
void SGLyricsSetSourceTypes(NSString *key, SGLyricsTypes types) {}
NSArray<NSString *> *SGLyricsTranslationLanguageNames(void) { return @[]; }
NSString *SGLyricsTranslationLanguage(void) { return @""; }
void SGLyricsSourceRequest(NSURL *url, NSDictionary<NSString *, NSString *> *headers, NSData *body,
                           void (^done)(NSData *data, NSInteger status)) {
    if (done) done(nil, 0);
}
BOOL SGLyricsPin(NSString *trackID, NSDictionary *record) { return NO; }
void SGLyricsUnpin(NSString *trackID) {}
NSNumber *SGLyricsPinnedID(NSString *trackID) { return nil; }
void SGLyricsPickRecord(NSString *trackID, NSDictionary *record, BOOL (^current)(void), void (^done)(BOOL pinned)) {
    if (done) done(NO);
}
UIViewController *SGLyricsSourcesPage(void) { return nil; }
SGModRow *SGDeezerARLRow(void) { return nil; }
SGModRow *SGSpicyLyricsKeyRow(void) { return nil; }
void SGLrcLibSearch(NSString *title, NSString *artist, NSInteger seconds, void (^done)(NSArray<NSDictionary *> *records)) {
    if (done) done(nil);
}

// Imported LRC files (LocalLyrics.m): none in the harness.
#import "Shared/LocalFiles/LocalLyrics.h"
NSString *const SGImportedLRCKey = @"importedLRC";
NSArray<NSString *> *SGImportedLRCFiles(void) { return @[]; }
UIViewController *SGImportedLRCPage(void) { return nil; }
SGLyricsAsk SGImportedLRCAsk = ^(SGLyricsQuery *query, void (^done)(SGLyricsResult *result)) { if (done) done(nil); };
NSDictionary<NSString *, id> *SGLocalFileInfo(NSString *uri) { return nil; }

#import "../shared/lyrics-pip-disabled.m"

// The lyrics store (LyricsStore.m): empty.
#import "Shared/Lyrics/LyricsStore.h"
void SGLyricsStoreSize(void (^done)(unsigned long long bytes)) { if (done) done(0); }
void SGLyricsStoreDeleteAll(void (^done)(unsigned long long remainingBytes)) { if (done) done(0); }

// KaraokeSource.x's settings the harness does not build: no Eevee, one offset of none.
BOOL SGEeveeLyricsOn(void) { return NO; }
NSInteger SGLyricsTrackOffsetMs(NSString *trackID) { return 0; }
void SGLyricsSetTrackOffsetMs(NSString *trackID, NSInteger ms) {}
NSString *SGLyricsRouteName(void) { return nil; }
NSInteger SGLyricsRouteOffsetMs(void) { return 0; }
void SGLyricsSetRouteOffsetMs(NSInteger ms) {}
void SGLyricsReload(NSString *trackID) {
    [NSNotificationCenter.defaultCenter postNotificationName:SGLyricsDidReloadNotification object:nil userInfo:trackID ? @{@"track": trackID} : nil];
}
BOOL SGLyricsLoadFailed(NSString *trackID) { return NO; }
void SGLyricsRetry(NSString *trackID) { SGLyricsReload(trackID); }

// PlayerTitle.x's engine: the title as the metadata has it.
#import "Redesigned/Player/Player.h"
NSString *SGRShownTitle(NSString *trackID, NSString *title, NSString *artist, NSString **shownArtist) {
    if (shownArtist) *shownArtist = artist;
    return title;
}
void SGRShownTitleWatch(UIView *unit) {}
void SGRShownTitleRestyle(void) {}
void SGRShownTitleSlide(CGFloat slide) {}

// Speed and pitch: a number the harness keeps, with no audio behind it.
static double sg_speed = 1;
double SGPlayerSpeed(void) { return sg_speed; }
BOOL SGPlayerSpeedAllowed(void) { return YES; }
void SGSetPlayerSpeed(double speed) { sg_speed = speed; NSLog(@"[harness] speed %.2f", speed); }

// The audio effects' reader (AudioEffects.x): a song of the harness's own, 120 beats a minute at 48 kHz, a kick on
// every beat, hats between, a bass line, a chord and a tune, handed to the reader in buffers of 1024 on a queue of
// its own, as the render thread would, for as long as one is set.
#import <stdatomic.h>
#import "Shared/AudioEffects/AudioEffects.h"

static _Atomic(SGAudioOutputReader) sg_reader;
static dispatch_source_t sg_audio;

BOOL SGRHarnessReading(void) { return atomic_load(&sg_reader) != NULL; }

static void synthesize(float *out, uint64_t start, int count, double rate) {
    static const double bass[] = {55, 73.42, 65.41, 49}, tune[] = {440, 523.25, 587.33, 659.25, 783.99, 659.25, 587.33, 523.25};
    for (int i = 0; i < count; i++) {
        double t = (start + i) / rate, beat = fmod(t, 0.5), half = fmod(t + 0.25, 0.5);
        int bar = (int)(t / 2) % 4, note = (int)(t / 0.5) % 8;
        double kick = 0.55 * sin(2 * M_PI * 52 * beat) * exp(-9 * beat);
        double hat = 0.12 * (2.0 * arc4random_uniform(1 << 16) / (1 << 16) - 1) * exp(-50 * half);
        double low = 0.22 * sin(2 * M_PI * bass[bar] * t);
        double chord = 0.05 * (0.6 + 0.4 * sin(2 * M_PI * 0.25 * t)) * (sin(2 * M_PI * 220 * t) + sin(2 * M_PI * 277.18 * t) + sin(2 * M_PI * 329.63 * t));
        double lead = 0.08 * sin(2 * M_PI * tune[note] * t) * (1 - exp(-20 * beat));
        out[i] = (float)(kick + hat + low + chord + lead);
    }
}

void SGAudioSetOutputReader(SGAudioOutputReader reader) {
    atomic_store(&sg_reader, reader);
    NSLog(@"[harness] output reader %@", reader ? @"on" : @"off");
    if (sg_audio) return;
    __block uint64_t played = 0;
    sg_audio = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_queue_create("harness.audio", DISPATCH_QUEUE_SERIAL));
    dispatch_source_set_timer(sg_audio, DISPATCH_TIME_NOW, (uint64_t)(1024 / 48000.0 * NSEC_PER_SEC), NSEC_PER_MSEC);
    dispatch_source_set_event_handler(sg_audio, ^{
        static float buffer[1024];
        synthesize(buffer, played, 1024, 48000);
        played += 1024;
        SGAudioOutputReader now = atomic_load(&sg_reader);
        if (now) now(buffer, 1024, 48000);
    });
    dispatch_resume(sg_audio);
}

// Sing (the mic on the lyrics, SGRSingButton.m): never available, as on a phone that cannot run it.
#import "Shared/Sing/Sing.h"
#import "Core/SGPrefs.h"
NSString *const SGSingChangedNotification = @"harness.singChanged";
NSString *const SGSingButtonDidChangeNotification = @"harness.singButtonDidChange";
BOOL SGSingButtonShown(void) { return SGFlag(SGKeySingButton, NO); }
SGSingState SGSingCurrentState(void) { return SGSingStateUnavailable; }
NSString *SGSingStatusText(void) { return @"Unavailable"; }
NSString *SGSingStatusDetail(void) { return nil; }
NSString *SGSingMissing(void) { return @"the harness"; }
BOOL SGSingOn(void) { return NO; }
double SGSingHeldLead(void) { return 0; }
void SGSetSingOn(BOOL on) {}
float SGSingLevel(void) { return 0; }
void SGSetSingLevel(float level) {}
NSString *SGSingLevelText(double level) { return @""; }
double SGSingModelProgress(void) { return 0; }
BOOL SGSingModelWaitingForNetwork(void) { return NO; }
NSString *SGSingModelError(void) { return nil; }
NSString *SGSingModelSizeText(void) { return @""; }
void SGSingDownloadModel(void) {}
void SGSingCancelModelDownload(void) {}

// MotionSources.m: the default order, Canvas then Apple Music, over the catalog the harness builds. No
// Canvas service: a track whose metadata names no Canvas goes to Apple Music.
#import "Shared/AnimatedArtwork/AnimatedArtwork.h"
NSArray<NSString *> *SGMotionSourceOrder(void) { return @[@"canvas", @"applemusic"]; }
NSURL *SGMotionCanvasIn(NSDictionary *metadata) {
    // PlayerField.x moves the keys under SGMotionHiddenCanvas, as on the phone.
    id type = metadata[@"canvas.type"] ?: metadata[SGMotionHiddenCanvas @"canvas.type"];
    id address = metadata[@"canvas.url"] ?: metadata[SGMotionHiddenCanvas @"canvas.url"];
    return [type hasPrefix:@"VIDEO"] && [address isKindOfClass:NSString.class] ? [NSURL URLWithString:address] : nil;
}
// A walk asked for while this is set answers that many seconds late, so a check can look at the player while the
// lookup is out.
static NSTimeInterval sg_lookupDelay;
void SGRHarnessSetLookupDelay(NSTimeInterval seconds) { sg_lookupDelay = seconds; }
static NSMutableDictionary<NSString *, NSMutableArray<dispatch_block_t> *> *sg_heldLookups;
void SGRHarnessHoldLookups(NSString *uri) {
    if (!sg_heldLookups) sg_heldLookups = [NSMutableDictionary dictionary];
    sg_heldLookups[uri] = [NSMutableArray array];
}
BOOL SGRHarnessLookupReady(NSString *uri) { return sg_heldLookups[uri].count > 0; }
void SGRHarnessDeliverLookups(NSString *uri) {
    NSArray<dispatch_block_t> *answers = [sg_heldLookups[uri] copy];
    [sg_heldLookups removeObjectForKey:uri];
    for (dispatch_block_t answer in answers) answer();
}

void SGMotionClipFor(NSString *uri, NSURL *canvas, NSString *artist, NSString *album, CGFloat pixels,
                     void (^done)(NSURL *file, NSString *source)) {
    if (sg_heldLookups[uri]) {
        void (^answer)(NSURL *, NSString *) = [done copy];
        NSMutableArray *held = sg_heldLookups[uri];
        done = ^(NSURL *file, NSString *source) {
            // A second consumer can finish after the first answer opened the gate.
            // Don't enqueue its answer on an array that will never be drained again.
            if (sg_heldLookups[uri] == held) [held addObject:^{ answer(file, source); }];
            else answer(file, source);
        };
    } else if (sg_lookupDelay > 0) {
        void (^answer)(NSURL *, NSString *) = [done copy];
        NSTimeInterval delay = sg_lookupDelay;
        done = ^(NSURL *file, NSString *source) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ answer(file, source); });
        };
    }
    void (^apple)(void) = ^{ SGMotionAlbumCover(artist, album, pixels, ^(NSURL *file) { done(file, file ? @"applemusic" : nil); }); };
    if (!canvas && [uri isEqual:@"spotify:track:noClip"]) {
        // The settings scenario supplies a known catalog miss, not a live Apple Music search.
        dispatch_async(dispatch_get_main_queue(), ^{ done(nil, nil); });
        return;
    }
    if (!canvas) { apple(); return; }
    SGMotionFile(canvas, ^(NSURL *file) { if (file) done(file, @"canvas"); else apple(); });
}
// The Artwork sources row as a link to nowhere, so the Player page's rows under the card can be counted.
#import "Settings/SGModPage.h"
SGModRow *SGMotionSourcesRow(void) { return SGPageRow(@"Artwork sources", ^UIViewController *{ return nil; }); }
BOOL SGMotionAppleMusicOn(void) { return YES; }

// TabBar.x: the Mini player section's Apple Music style switch lays the tab bar out again; there is none here.
void SGRSetTabBarMinimized(BOOL minimized, BOOL animated) {}
void SGRRefreshTabBar(void) {}

// Spotify's link dispatcher, which the AI DJ's Queue glyph opens the queue through (DJPlayer.x): none here. The last URI
// asked for is kept for the options scenario.
NSURL *SGRHarnessLastOpened;
BOOL SGOpenSpotifyURI(NSURL *uri) {
    NSLog(@"[harness] open %@", uri);
    SGRHarnessLastOpened = uri;
    return NO;
}

// PlayerMorph.x's Music-like close switch, which the Player page lists.
NSString *const SGRKeyPlayerMusicClose = @"spotifyglass.redesign.player.musicClose";

// The ⋯'s system menu (PlayerMenu.m, ContextMenu.x), which this harness does not build (harness/system-menu does):
// the Spotify ⋯ PlayerHeader.x hands over is kept for the header scenario, and the title row is left as it is.
__weak UIView *SGRHarnessWatchedMore;
void SGRPlayerMenuWatch(UIView *button) { SGRHarnessWatchedMore = button; }
void SGRPlayerMenuInTitleRow(UIView *title) {}

// PlayerState.x's playback location: this device plays. The audio quality badge (Shared/Player/AudioQuality.x) is built
// here, and reads Spotify's report of the file it plays from the state's playbackQuality, which the harness sets.
NSNotificationName const SGPlayerPlaybackLocationDidChangeNotification = @"harness.playbackLocation";
BOOL SGPlayerPlaybackIsLocal(void) { return YES; }
static char kQualityKey;
@implementation SPTPlayerState (HarnessQuality)
- (id)playbackQuality { return objc_getAssociatedObject(self, &kQualityKey); }
- (void)setPlaybackQuality:(id)quality { objc_setAssociatedObject(self, &kQualityKey, quality, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
@end

// Cydia Substrate's hook (substrate.h here), as the runtime does it: the class gets its own copy of an inherited
// method, so its superclass is left alone.
void MSHookMessageEx(Class _class, SEL message, IMP hook, IMP *old) {
    Method method = class_getInstanceMethod(_class, message);
    if (!method) return;
    if (old) *old = method_getImplementation(method);
    if (!class_addMethod(_class, message, hook, method_getTypeEncoding(method))) method_setImplementation(method, hook);
}
