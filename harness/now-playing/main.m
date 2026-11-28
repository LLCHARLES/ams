// Checks what reaches the system's now playing through the mod's two hooks of the setter,
// Shared/Player/NowPlayingExtras.x and Shared/LockScreenLyrics/LockScreenLyrics.x, built as the tweak
// builds them. The system's setter and getter are replaced underneath both (this file links first, so its
// constructor runs before their %ctors), and Karaoke is a stub with two lines. Run with LSL=1 for lock
// screen lyrics on, without it for off; it exits non-zero on the first check that fails.
#import <MediaPlayer/MediaPlayer.h>
#import <objc/runtime.h>
#include <stdlib.h>
#import "Shared/Lyrics/Lyrics.h"
#import "Shared/Player/NowPlayingExtras.h"
#import "Headers/SPTPlayer.h"
#import "Shared/LockScreenLyrics/LockScreenLyrics.h"
#import "artwork.h"
#import "Shared/AnimatedArtwork/AnimatedArtwork.h"
#import "Shared/LyricsTranslation/LyricsTranslation.h"
#import "Shared/LiveActivity/LiveActivity.h"
#import "Shared/ArtistBlock/ArtistBlock.h"

#pragma mark - the system, underneath

static NSDictionary *sg_system;   // what the system was last given
static NSUInteger sg_sets;

static void systemSet(id self, SEL _cmd, NSDictionary *info) {
    extern void harnessRecordPublished(NSDictionary *);
    harnessRecordPublished(info);
    sg_system = info;
    sg_sets++;
}

static NSDictionary *systemGet(id self, SEL _cmd) {
    return sg_system;
}

__attribute__((constructor)) static void underneath(void) {
    Class center = MPNowPlayingInfoCenter.class;
    class_replaceMethod(center, @selector(setNowPlayingInfo:), (IMP)systemSet, "v@:@");
    class_replaceMethod(center, @selector(nowPlayingInfo), (IMP)systemGet, "@@:");
}

#pragma mark - stubs

// These preference stubs read live values or fallbacks, so there is no cache to invalidate.
void SGPrefsChanged(void) {}
void SGMigrateKey(NSString *from, NSString *to) {}

BOOL harnessActivityOn;
BOOL SGFlag(NSString *key, BOOL fallback) {
    if ([key isEqual:SGKeyLiveActivity]) return harnessActivityOn;
    if ([key isEqual:SGKeyLockScreenTranslation] || [key isEqual:SGKeyLiveActivityTranslation])
        return [NSUserDefaults.standardUserDefaults boolForKey:key];
    return [key isEqual:SGKeyLockScreenLyrics] ? getenv("LSL") != NULL : fallback;
}
BOOL SGEnabled(NSString *key) { return SGFlag(key, YES); }

@implementation SPTPlayerTrack {
@public
    NSString *_title;
    NSString *_uri;
    NSDictionary *_metadata;
}
- (NSString *)trackTitle { return _title; }
- (id)URI { return _uri; }
- (NSDictionary *)metadata { return _metadata ?: @{}; }
- (NSString *)artistName { return @"Artist"; }
@end

BOOL harnessPlaying;
double harnessRate = 1;
double harnessDuration;
@implementation SPTPlayerState {
@public
    SPTPlayerTrack *_track;
}
- (SPTPlayerTrack *)track { return _track; }
- (BOOL)isPaused { return !harnessPlaying; }
- (BOOL)isPlaying { return harnessPlaying; }
- (SPTPlayerOptions *)options { return nil; }
- (double)position { return SGKaraokePositionMs() / 1000.; }
- (double)positionAsOfTimestamp { return self.position; }
- (NSArray *)future { return nil; }
- (double)playbackSpeed { return harnessRate; }
- (double)duration { return harnessDuration; }
@end

static NSUInteger skipRequests;
@interface SPTEsperantoPlayer : NSObject
@property (nonatomic) SPTPlayerState *state;
@end
@implementation SPTEsperantoPlayer
- (void)skipToNextTrack { skipRequests++; }
@end

static SPTEsperantoPlayer *sg_player;
static NSMutableDictionary *blockedSongs;
NSString *const SGArtistURI = @"uri", *const SGArtistName = @"name";
NSString *const SGBlockedSongsDidChangeNotification = @"harness.blockedSongsChanged";
NSDictionary *SGBlockedSongs(void) { return blockedSongs; }
BOOL SGSongBlocked(NSString *uri) { return blockedSongs[uri] != nil; }
BOOL SGArtistBlocked(NSString *uri) { return NO; }
NSArray *SGArtistsOfTrack(id track) { return @[]; }
static NSArray<SGKaraokeLine *> *sg_lines;
static void (^sg_afterTickSnapshot)(void);
static NSUInteger sg_lyricReads;

id SGKaraokePlayer(void) {
    if (NSThread.isMainThread) {
        sg_lyricReads++;
        void (^gate)(void) = sg_afterTickSnapshot;
        sg_afterTickSnapshot = nil;
        if (gate) gate();
    }
    return sg_player;
}
NSString *SGKaraokePlayingTrack(void) { return sg_player.state.track.URI; }
NSArray<SGKaraokeLine *> *SGKaraokeLinesForTrack(NSString *trackID) { return sg_lines; }
void (^harnessLyricsRequested)(NSString *);
void SGSpclientHeaders(void (^use)(NSDictionary *headers)) { use(@{}); }
BOOL harnessLookupFailed;
BOOL SGLyricsLoadFailed(NSString *track) { return harnessLookupFailed; }
void SGKaraokeRequestLyrics(NSString *trackID) {
    if (harnessLyricsRequested) harnessLyricsRequested(trackID);
}
NSNotificationName const SGKaraokeLinesKeptNotification = @"harness.karaokeLinesKept";
NSNotificationName const SGKaraokeLookupReadyNotification = @"harness.karaokeLookupReady";
NSNotificationName const SGLyricsOffsetsDidChangeNotification = @"harness.offsets";
NSInteger harnessTrackOffset;
NSInteger SGKaraokeDelayMs(void) { return harnessTrackOffset + [NSUserDefaults.standardUserDefaults integerForKey:SGKeyLyricsDelay]; }
// Only the translation check selects the translated artist row.
static BOOL sg_showTranslation;
NSInteger SGInt(NSString *key, NSInteger fallback) {
    if ([key isEqual:SGKeyLiveActivityView] || [key isEqual:SGKeyLockScreenLyricsStyle] || [key isEqual:SGKeyLockScreenLyricsSize]) {
        id value = [NSUserDefaults.standardUserDefaults objectForKey:key];
        return value ? [value integerValue] : fallback;
    }
    return [key isEqual:SGKeyLockScreenLyricsLine] && sg_showTranslation ? SGLockScreenLyricsLineTranslation : fallback;
}
NSString *harnessLanguage = @"en";
NSDictionary *harnessTranslations;
BOOL harnessHoldTranslation;
static NSMutableArray<void (^)(void)> *heldTranslations;
NSString *SGLyricsGeminiLanguage(void) { return harnessLanguage; }
void SGLyricsSyncSavedTranslation(NSString *track, NSString *language, NSArray<SGKaraokeLine *> *lines) {}
void SGLyricsLoadTranslation(NSString *track, NSString *language, NSArray<SGKaraokeLine *> *lines,
                             BOOL (^current)(void), void (^done)(void)) {
    NSDictionary *values = harnessTranslations[language];
    void (^deliver)(void) = ^{
        if (!current()) return;
        for (SGKaraokeLine *line in lines) {
            NSString *value = values[SGKaraokeLineText(line)];
            if (line.translationMade || (!line.translation.length && value.length)) {
                line.translation = value;
                line.translationMade = value.length > 0;
            }
        }
        done();
    };
    if (harnessHoldTranslation) {
        if (!heldTranslations) heldTranslations = [NSMutableArray array];
        [heldTranslations addObject:deliver];
    } else dispatch_async(dispatch_get_main_queue(), deliver);
}
void harnessDeliverTranslations(void) {
    NSArray *pending = [heldTranslations copy];
    [heldTranslations removeAllObjects];
    for (void (^deliver)(void) in pending.reverseObjectEnumerator) deliver();
}
NSUInteger harnessAutomaticTranslations;
void SGRAutoTranslateWithoutView(NSString *track, NSArray<SGKaraokeLine *> *lines, BOOL (^mayContinue)(void), void (^loaded)(void)) {
    harnessAutomaticTranslations++;
    SGLyricsLoadTranslation(track, SGLyricsGeminiLanguage(), lines, mayContinue, loaded);
}
// The redesign's choice of pronunciation; off unless a check sets it.
static SGRLyricsReading sg_reading;
static BOOL sg_readingLeads;
SGRLyricsReading SGRLyricsReadingShown(BOOL *leads) {
    if (leads) *leads = sg_readingLeads;
    return sg_reading;
}
void harnessReading(SGRLyricsReading reading, BOOL leads) {
    sg_reading = reading;
    sg_readingLeads = leads;
}
NSString *harnessSongLanguage;
NSString *SGLyricsTrackLanguage(NSString *trackID) { return harnessSongLanguage; }
NSString *SGLyricsDetectedLanguage(NSArray<SGKaraokeLine *> *lines) { return nil; }
NSNotificationName const SGLyricsLanguageDidChangeNotification = @"harness.lyricsLanguageChanged";
NSNotificationName const SGLyricsTranslationSavedNotification = @"spotifyglass.lyricsTranslationSaved";
NSNotificationName const SGLyricsTranslationsDidChangeNotification = @"spotifyglass.lyricsTranslationsDidChange";

SGKaraokeLine *lineOf(NSString *text, NSInteger start, NSInteger end) {
    SGKaraokeWord *word = [SGKaraokeWord new];
    word.text = text;
    word.start = start;
    word.end = end;
    SGKaraokeLine *line = [SGKaraokeLine new];
    line.words = @[word];
    line.start = start;
    line.end = end;
    line.timing = SGKaraokeTimingWords;
    return line;
}

#pragma mark - checks

static int failures;

void check(BOOL ok, NSString *what) {
    printf("%s %s\n", ok ? "ok  " : "FAIL", what.UTF8String);
    if (!ok) failures++;
}

void runFor(NSTimeInterval seconds) {
    [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:seconds]];
}

SPTPlayerState *harnessState(NSString *uri, NSString *title) {
    SPTPlayerTrack *track = [SPTPlayerTrack new];
    track->_uri = uri;
    track->_title = title;
    SPTPlayerState *state = [SPTPlayerState new];
    state->_track = track;
    sg_player.state = state;
    return state;
}
void harnessLines(NSArray *lines) { sg_lines = lines; }
void harnessMetadata(NSDictionary *metadata) { sg_player.state.track->_metadata = metadata; }
NSDictionary *harnessSystem(void) { return sg_system; }
NSUInteger harnessSets(void) { return sg_sets; }

static NSDictionary *spotifyInfo(NSString *title, double elapsed, double rate) {
    return @{MPMediaItemPropertyTitle: title, MPMediaItemPropertyArtist: @"Artist",
             MPNowPlayingInfoPropertyElapsedPlaybackTime: @(elapsed), MPNowPlayingInfoPropertyPlaybackRate: @(rate)};
}

static double systemElapsed(void) {
    return [sg_system[MPNowPlayingInfoPropertyElapsedPlaybackTime] doubleValue];
}

static void songBlockOccurrence(void) {
    SPTPlayerState *saved = sg_player.state;
    blockedSongs = [@{@"other": @YES} mutableCopy];
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    [center postNotificationName:SGBlockedSongsDidChangeNotification object:@"other"];
    harnessState(@"newly-blocked", @"Song");
    MPNowPlayingInfoCenter.defaultCenter.nowPlayingInfo = spotifyInfo(@"Song", 0, 0);
    drainMain();
    // The queued now-playing check sees the new block before its list-change handler.
    blockedSongs[@"newly-blocked"] = @YES;
    MPNowPlayingInfoCenter.defaultCenter.nowPlayingInfo = spotifyInfo(@"Song", 0, 0);
    [center postNotificationName:SGBlockedSongsDidChangeNotification object:@"newly-blocked"];
    drainMain();
    check(skipRequests == 1, @"a newly blocked examined occurrence requests one skip");
    harnessState(@"already-blocked", @"Song");
    blockedSongs[@"already-blocked"] = @YES;
    MPNowPlayingInfoCenter.defaultCenter.nowPlayingInfo = spotifyInfo(@"Song", 0, 0);
    [center postNotificationName:SGBlockedSongsDidChangeNotification object:@"already-blocked"];
    drainMain();
    check(skipRequests == 2, @"a queued skip and its block notification cannot skip twice for one occurrence");
    harnessState(@"allowed", @"Song");
    MPNowPlayingInfoCenter.defaultCenter.nowPlayingInfo = spotifyInfo(@"Song", 0, 0);
    drainMain();
    check(skipRequests == 2, @"the next allowed song is left playing");
    [blockedSongs removeAllObjects];
    [center postNotificationName:SGBlockedSongsDidChangeNotification object:nil];
    sg_player.state = saved;
}

// Lock screen lyrics: once the line is let go, the artist comes back with the clock moved on, and the
// extras' clock, which records what passes, is not pulled back by it either.
extern BOOL harnessManualRow;
extern CFAbsoluteTime harnessExtrasNow;
extern int64_t harnessRowDelay;
BOOL HarnessFireRow(void);
BOOL HarnessRowArmed(void);
static void progressBar(void) {
    MPNowPlayingInfoCenter *center = MPNowPlayingInfoCenter.defaultCenter;
    // Rate 4, so the 4 s break after the line's end comes in about a second of wall time.
    const double rate = 4;
    harnessManualRow = YES;
    CFAbsoluteTime setAt = harnessExtrasNow = 1000;
    center.nowPlayingInfo = spotifyInfo(@"Song", 0, rate);
    check([sg_system[MPMediaItemPropertyArtist] isEqual:@"Hello"], @"the line sung shows in place of the artist");
    check(harnessRowDelay > 0 && harnessRowDelay < 1.6 * NSEC_PER_SEC, @"row armed for the line break");
    harnessExtrasNow += 1.6;
    check(HarnessFireRow(), @"armed row timer delivers the break");
    double expected = rate * (harnessExtrasNow - setAt);
    check([sg_system[MPMediaItemPropertyArtist] isEqual:@"Artist"], @"the artist comes back in the break");
    // The line is let go 4 s past its end at 0.1 s, so the info that lets it go is from 4.1 s on.
    check(systemElapsed() > 4.1 && systemElapsed() <= expected,
          [NSString stringWithFormat:@"the break's info is at %.2f s, not Spotify's 0", systemElapsed()]);
    harnessExtrasNow += 0.25;
    SGNowPlayingSetExtras(@"haptics", @{MPNowPlayingInfoPropertyInternationalStandardRecordingCode: @"ISRC"}, @"Song");
    expected = rate * (harnessExtrasNow - setAt);
    check(fabs(systemElapsed() - expected) < 1.5,
          [NSString stringWithFormat:@"an extra's resend is at %.2f s (expected about %.2f)", systemElapsed(), expected]);
    SGNowPlayingSetExtras(@"haptics", nil, nil);
    center.nowPlayingInfo = spotifyInfo(@"Song", 0, 0);
    harnessManualRow = NO;
    harnessExtrasNow = 0;
}

// Lock screen translation: a translation longer than the row is cut by its own
// length, not the line's, and its pieces follow the line's clock.
static void translation(void) {
    sg_showTranslation = YES;
    MPNowPlayingInfoCenter *center = MPNowPlayingInfoCenter.defaultCenter;
    NSArray<SGKaraokeLine *> *was = sg_lines;
    SGKaraokeLine *line = lineOf(@"Hola", 0, 4000);
    line.translation = @"This translation runs well past what the lock screen's artist row holds";
    sg_lines = @[line];
    center.nowPlayingInfo = spotifyInfo(@"Song", 0, 0);
    NSString *first = sg_system[MPMediaItemPropertyArtist];
    check(first.length > 0 && first.length <= 30 && [line.translation hasPrefix:first],
          [NSString stringWithFormat:@"the translation's first piece shows: \"%@\"", first]);
    center.nowPlayingInfo = spotifyInfo(@"Song", 3.9, 0);
    NSString *last = sg_system[MPMediaItemPropertyArtist];
    check(last.length > 0 && last.length <= 30 && [line.translation hasSuffix:last],
          [NSString stringWithFormat:@"its last piece shows by the line's end: \"%@\"", last]);
    sg_lines = was;
    sg_showTranslation = NO;
}

// Exercise the production setter's actual dispatch deadline at exact Now Playing
// positions; no wall-clock wait or simulated audio is needed.
int64_t harnessRowDelay;
static void rowDeadlines(void) {
    NSArray *was = sg_lines;
    SGKaraokeLine *line = lineOf(@"two", 0, 20000);
    line.words = @[line.words.firstObject, lineOf(@"words", 2000, 20000).words.firstObject];
    sg_lines = @[line, lineOf(@"later", 30000, 31000)];
    MPNowPlayingInfoCenter *center = MPNowPlayingInfoCenter.defaultCenter;
    center.nowPlayingInfo = spotifyInfo(@"Song", 0, 1);
    check([sg_system[MPMediaItemPropertyArtist] isEqual:@"two words"] && harnessRowDelay == 24002 * NSEC_PER_MSEC,
          @"one displayed piece sleeps past interior words until the long break");
    center.nowPlayingInfo = spotifyInfo(@"Song", 25, 1);
    check([sg_system[MPMediaItemPropertyArtist] isEqual:@"Artist"] && harnessRowDelay == (int64_t)(1.001 * NSEC_PER_SEC),
          @"seek into a rest arms its exit, four seconds before the next lead");
    line.words = @[lineOf(@"one sufficiently long phrase", 0, 2000).words.firstObject,
                   lineOf(@"and another phrase", 2000, 20000).words.firstObject];
    center.nowPlayingInfo = spotifyInfo(@"Song", 0, 1);
    check([sg_system[MPMediaItemPropertyArtist] isEqual:@"one sufficiently long phrase"] &&
          harnessRowDelay == (int64_t)(2.001 * NSEC_PER_SEC), @"a second displayed piece keeps its own word-start deadline");
    center.nowPlayingInfo = spotifyInfo(@"Song", 2, 0);
    check([sg_system[MPMediaItemPropertyArtist] isEqual:@"and another phrase"], @"paused seek selects the new piece");
    sg_lines = nil;
    harnessRowDelay = -1;
    center.nowPlayingInfo = spotifyInfo(@"Song", 0, 1);
    check(harnessRowDelay == -1, @"an outstanding lyric lookup needs no periodic clock");
    sg_lines = @[line];
    [NSNotificationCenter.defaultCenter postNotificationName:SGKaraokeLinesKeptNotification object:nil];
    check([sg_system[MPMediaItemPropertyArtist] isEqual:@"one sufficiently long phrase"], @"arriving lyrics replace the artist immediately");
    sg_lines = was;
    center.nowPlayingInfo = spotifyInfo(@"Song", 0, 0);
}

// Lock screen pronunciation: the artist row has room for one line, the larger of the lyrics' two, so the source's
// pronunciation shows only where the order leads with it; a choice made while paused shows at once, and the
// translation chosen for the row keeps its place.
static void pronunciation(void) {
    NSArray<SGKaraokeLine *> *was = sg_lines;
    SGKaraokeLine *line = lineOf(@"안녕", 0, 10000);
    line.pronunciation = lineOf(@"annyeong", 0, 10000);
    sg_lines = @[line];
    sg_reading = SGRLyricsReadingSource;
    MPNowPlayingInfoCenter.defaultCenter.nowPlayingInfo = spotifyInfo(@"Song", 0, 0);
    check([sg_system[MPMediaItemPropertyArtist] isEqual:@"안녕"], @"the words lead the artist row by the default order");
    sg_readingLeads = YES;
    [NSNotificationCenter.defaultCenter postNotificationName:NSUserDefaultsDidChangeNotification object:nil];
    HARNESS_AWAIT([sg_system[MPMediaItemPropertyArtist] isEqual:@"annyeong"]);
    check([sg_system[MPMediaItemPropertyArtist] isEqual:@"annyeong"], @"paused, the pronunciation takes the row once the order leads with it");
    sg_showTranslation = YES;
    line.translation = @"Hello";
    MPNowPlayingInfoCenter.defaultCenter.nowPlayingInfo = spotifyInfo(@"Song", 0, 0);
    check([sg_system[MPMediaItemPropertyArtist] isEqual:@"Hello"], @"the row's translation keeps its place over the pronunciation");
    sg_showTranslation = NO;
    line.pronunciation = nil;
    sg_reading = SGRLyricsReadingRomanised;
    MPNowPlayingInfoCenter.defaultCenter.nowPlayingInfo = spotifyInfo(@"Song", 0, 0);
    check([sg_system[MPMediaItemPropertyArtist] isEqual:@"안녕"], @"uncached reading leaves the original visible until its worker completes");
    HARNESS_AWAIT([sg_system[MPMediaItemPropertyArtist] isEqual:@"annyeong"]);
    check([sg_system[MPMediaItemPropertyArtist] isEqual:@"annyeong"], @"completed offline reading refreshes the paused artist row");
    sg_reading = SGRLyricsReadingNone;
    sg_readingLeads = NO;
    sg_lines = was;
}

static void pausedTrackDuringTick(void) {
    MPNowPlayingInfoCenter *center = MPNowPlayingInfoCenter.defaultCenter;
    NSArray *saved = sg_lines;
    sg_lines = @[lineOf(@"A before", 0, 1000)];
    center.nowPlayingInfo = spotifyInfo(@"Song", 0, 1);
    sg_lines = @[lineOf(@"A after", 0, 1000)];
    __block BOOL gated = NO;
    sg_afterTickSnapshot = ^{
        gated = YES;
        dispatch_semaphore_t published = dispatch_semaphore_create(0);
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            center.nowPlayingInfo = spotifyInfo(@"Paused B", 7, 0);
            dispatch_semaphore_signal(published);
        });
        check(dispatch_semaphore_wait(published, dispatch_time(DISPATCH_TIME_NOW, HarnessWaitSeconds * (int64_t)NSEC_PER_SEC)) == 0,
              @"paused B publishes off-main while A's tick is held after its snapshot");
    };
    [NSNotificationCenter.defaultCenter postNotificationName:SGKaraokeLinesKeptNotification object:nil];
    check(gated, @"the production lyric tick reaches the snapshot gate");
    HARNESS_AWAIT([sg_system[MPMediaItemPropertyTitle] isEqual:@"Paused B"]);
    check([sg_system[MPMediaItemPropertyTitle] isEqual:@"Paused B"] && systemElapsed() == 7
          && [sg_system[MPNowPlayingInfoPropertyPlaybackRate] doubleValue] == 0,
          @"draining main restores paused B after A's stale resend");
    NSUInteger reads = sg_lyricReads;
    drainMain();
    check(!HarnessRowArmed() && sg_lyricReads == reads, @"paused B leaves no timer polling the lyric player");
    sg_lines = saved;
}

static void deletedTranslation(void) {
    sg_showTranslation = YES;
    harnessTranslations = @{@"en": @{@"Hola": @"Hello saved"}};
    sg_lines = @[lineOf(@"Hola", 0, 10000)];
    MPNowPlayingInfoCenter.defaultCenter.nowPlayingInfo = spotifyInfo(@"Song", 0, 0);
    HARNESS_AWAIT([sg_system[MPMediaItemPropertyArtist] isEqual:@"Hello saved"]);
    check([sg_system[MPMediaItemPropertyArtist] isEqual:@"Hello saved"], @"paused artist row restores saved translation without a view");
    harnessTranslations = nil;
    [NSNotificationCenter.defaultCenter postNotificationName:SGLyricsTranslationsDidChangeNotification object:nil];
    HARNESS_AWAIT([sg_system[MPMediaItemPropertyArtist] isEqual:@"Hola"]);
    check([sg_system[MPMediaItemPropertyArtist] isEqual:@"Hola"], @"paused artist row removes deleted translation without a view");
    sg_showTranslation = NO;
}

// Two tracks with one title: what the first had must not stay on the second's info once it is cleared.
static void sameTitle(void) {
    MPNowPlayingInfoCenter *center = MPNowPlayingInfoCenter.defaultCenter;
    NSString *key = MPNowPlayingInfoPropertyInternationalStandardRecordingCode;
    center.nowPlayingInfo = spotifyInfo(@"Intro", 50, 0);
    SGNowPlayingSetExtras(@"lyrics", @{key: @"first"}, @"Intro");
    check([sg_system[key] isEqual:@"first"], @"the extra rides on its title's info");
    center.nowPlayingInfo = spotifyInfo(@"Intro", 0, 0);   // the next track, also called Intro
    check([sg_system[key] isEqual:@"first"], @"it rides on the next track of that title until cleared");
    SGNowPlayingSetExtras(@"lyrics", nil, nil);
    check(sg_system && !sg_system[key], @"cleared, it is taken off the info at once");
    check(fabs(systemElapsed()) < 0.01, @"the paused clock is kept");

    // Spotify building its next info from the one it reads back, so the extra comes along under a new title.
    SGNowPlayingSetExtras(@"lyrics", @{key: @"second"}, @"Intro");
    NSMutableDictionary *copied = [center.nowPlayingInfo mutableCopy];
    copied[MPMediaItemPropertyTitle] = @"Outro";
    center.nowPlayingInfo = copied;
    check([sg_system[key] isEqual:@"second"], @"copied, it rides on another title's info");
    SGNowPlayingSetExtras(@"lyrics", nil, nil);
    check(!sg_system[key], @"cleared, it comes off an info it was copied onto");

    // Nothing to take off: nothing is sent.
    SGNowPlayingSetExtras(@"lyrics", @{key: @"third"}, @"Intro");
    NSUInteger sets = sg_sets;
    SGNowPlayingSetExtras(@"lyrics", nil, nil);
    check(sg_sets == sets, @"cleared for another title, the info is not sent again");

    // Another owner's extra for the same title stays.
    center.nowPlayingInfo = spotifyInfo(@"Intro", 0, 0);
    SGNowPlayingSetExtras(@"haptics", @{@"other": @"kept"}, @"Intro");
    SGNowPlayingSetExtras(@"lyrics", @{key: @"fourth"}, @"Intro");
    SGNowPlayingSetExtras(@"lyrics", nil, nil);
    check(!sg_system[key] && [sg_system[@"other"] isEqual:@"kept"], @"another owner's extra stays on");
    SGNowPlayingSetExtras(@"haptics", nil, nil);
}

int main(void) {
    @autoreleasepool {
        SPTPlayerTrack *track = [SPTPlayerTrack new];
        track->_title = @"Song";
        track->_uri = @"track";
        SPTPlayerState *state = [SPTPlayerState new];
        state->_track = track;
        sg_player = [SPTEsperantoPlayer new];
        sg_player.state = state;
        sg_lines = @[lineOf(@"Hello", 0, 100), lineOf(@"Later", 60000, 61000)];
        BOOL lyrics = getenv("LSL") != NULL;
        printf("lock screen lyrics %s\n", lyrics ? "on" : "off");
        songBlockOccurrence();
        if (lyrics) progressBar();
        if (lyrics) translation();
        if (lyrics) rowDeadlines();
        if (lyrics) pronunciation();
        if (lyrics) pausedTrackDuringTick();
        if (lyrics) deletedTranslation();
        sameTitle();
        artworkChecks();
        activityChecks();
        publicationChecks();
        printf(failures ? "%d failed\n" : "all passed\n", failures);
        return failures ? 1 : 0;
    }
}
