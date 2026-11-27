// The real LiveActivity.x timer and reader, with only ActivityKit/player services replaced.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "artwork.h"
#import "Shared/LiveActivity/LiveActivity.h"
#import "Shared/Lyrics/Lyrics.h"
#import "Shared/LyricsTranslation/LyricsTranslation.h"
#import "Shared/Player/PlayerState.h"
#import "Shared/Player/SleepTimer.h"
#define HARNESS_ACTIVITY_CLOCK_IMPLEMENTATION
#import "activity-clock.h"

int64_t harnessActivityDelay;
uint64_t harnessActivityRepeat;
static BOOL virtualClock, showing = YES, allowStart = YES, pip;
static NSTimeInterval now, due;
static NSTimeInterval bridgeCost, singLead;
extern NSInteger harnessTrackOffset;
extern double harnessDuration;
static dispatch_block_t timerFire;
static NSUInteger fires, sends, ends;
static NSDate *started;
static NSDate *sentStart, *sleepEnd, *sentSleepEnd;
@implementation NSDate (ActivityClock)
+ (NSDate *)activityDate { return virtualClock ? [NSDate dateWithTimeIntervalSince1970:now] : NSDate.date; }
+ (NSDate *)activityDateWithTimeIntervalSinceNow:(NSTimeInterval)interval { return [self.activityDate dateByAddingTimeInterval:interval]; }
- (NSTimeInterval)activityTimeIntervalSinceNow { return [self timeIntervalSinceDate:NSDate.activityDate]; }
@end
// A command-line Catalyst harness has no UIApplicationMain or shared application.
@interface HarnessActivityApp : NSObject
@property UIApplicationState applicationState;
@end
@implementation HarnessActivityApp
@end
static HarnessActivityApp *app;
@implementation UIApplication (ActivityClock)
+ (UIApplication *)activityApplication { return app ? (id)app : self.sharedApplication; }
@end
void HarnessActivityHandler(dispatch_source_t timer, dispatch_block_t block) {
    if (virtualClock) timerFire = block;
    dispatch_source_set_event_handler(timer, block);
}
dispatch_time_t HarnessActivityTime(dispatch_time_t when, int64_t delta) {
    harnessActivityDelay = delta;
    if (virtualClock) return (when == DISPATCH_TIME_NOW ? (dispatch_time_t)llround(now * NSEC_PER_SEC) : when) + delta;
    return dispatch_time(when, delta);
}
void HarnessActivitySetTimer(dispatch_source_t timer, dispatch_time_t start, uint64_t interval, uint64_t leeway) {
    harnessActivityRepeat = interval;
    if (virtualClock) {
        due = start == DISPATCH_TIME_FOREVER ? INFINITY : start / (double)NSEC_PER_SEC;
        if (start != DISPATCH_TIME_FOREVER) harnessActivityDelay = (int64_t)start - llround(now * NSEC_PER_SEC);
        start = DISPATCH_TIME_FOREVER;
    }
    dispatch_source_set_timer(timer, start, interval, leeway);
}

static NSString *sentTranslation, *sentLine;
static NSArray *sentTitles, *upcoming;
static NSInteger sentTab;
@interface SGLiveActivityBridge : NSObject
@end
@implementation SGLiveActivityBridge
+ (BOOL)isShowing { return showing; }
+ (NSDate *)startedAt { return started ?: NSDate.activityDate; }
+ (BOOL)canStart { return YES; }
+ (void)end { if (virtualClock) { ends++; showing = NO; } }
+ (void)endBeforeExit {}
+ (BOOL)showWithView:(NSInteger)view paused:(BOOL)paused line:(NSString *)line nextLine:(NSString *)nextLine
              titles:(NSArray *)titles artists:(NSArray *)artists uris:(NSArray *)uris
                 tab:(NSInteger)tab title:(NSString *)title artist:(NSString *)artist shuffle:(BOOL)shuffle repeatMode:(NSInteger)repeatMode
            timerEnd:(NSDate *)timerEnd timerEndOfTrack:(BOOL)timerEndOfTrack timerEndOfAlbum:(BOOL)timerEndOfAlbum
                tint:(NSString *)tint trackStart:(NSDate *)trackStart trackEnd:(NSDate *)trackEnd pausedAt:(NSNumber *)pausedAt
         translation:(NSString *)translation cover:(NSData *)cover textSize:(NSInteger)textSize
           alignment:(NSInteger)alignment noLyrics:(BOOL)noLyrics withoutLyrics:(NSInteger)withoutLyrics
             colors:(NSInteger)colors accent:(NSString *)accent progressBar:(BOOL)progressBar {
    sentLine = line;
    sentTranslation = translation;
    sentTitles = titles;
    sentTab = tab;
    sentStart = trackStart;
    sentSleepEnd = timerEnd;
    now += bridgeCost;
    sends++;
    if (allowStart) showing = YES;
    return showing;
}
@end

BOOL SGLyricsPiPActive(void) { return pip; }
NSNotificationName const SGLyricsPiPDidChangeNotification = @"harness.pip";
// The card runs as on an IPA build with its extension; the settings page that checks the bundle is not built here.
BOOL SGLiveActivityAllowedByInstall(void) { return YES; }
// No string tables here: English, as SGL gives without one.
NSString *SGL(NSString *key, NSString *english) { return english; }
BOOL SGKaraokeLookupEnded(NSString *track) { return SGKaraokeLinesForTrack(track) != nil; }
id SGKaraokeObserveLinesKept(void (^changed)(NSNotification *)) {
    return [NSNotificationCenter.defaultCenter addObserverForName:SGKaraokeLinesKeptNotification object:nil queue:nil usingBlock:changed];
}
static NSUInteger queueLimit;
NSArray *SGPlayerUpcomingTracks(SPTPlayerState *state, NSUInteger limit) { queueLimit = limit; return upcoming ?: @[]; }
id SGPlayerAdvanceRepeat(id player, id options) { return nil; }
SGSleepTimerMode SGSleepTimerCurrentMode(void) { return sleepEnd ? SGSleepTimerAtTime : SGSleepTimerOff; }
NSDate *SGSleepTimerEnd(void) { return sleepEnd; }
void SGSetSleepTimer(SGSleepTimerMode mode, NSTimeInterval seconds) {}
void SGSleepTimerAdd(NSTimeInterval seconds) {}
BOOL SGSingOn(void) { return NO; }
double SGSingLeadOf(SPTPlayerState *state) { return singLead; }
NSString *SGSingMissing(void) { return nil; }
void SGSetSingOn(BOOL on) {}
BOOL SGLikePlayingTrack(void) { return NO; }

static void refresh(void) {
    // The card's normal action notification asks its timer owner to publish now.
    [NSNotificationCenter.defaultCenter postNotificationName:@"SGLiveActivityAction" object:@"tab:0"];
    drainMain();
}

static void lockedLyrics(void) {
    // Model a locked process still executing main-queue work but deferring run-loop timers.
    Method timerMethod = class_getClassMethod(NSTimer.class, @selector(timerWithTimeInterval:repeats:block:));
    IMP originalTimer = method_getImplementation(timerMethod);
    IMP deferredTimer = imp_implementationWithBlock(^NSTimer *(id cls, NSTimeInterval interval, BOOL repeats, void (^block)(NSTimer *)) {
        NSTimer *timer = ((id (*)(id, SEL, NSTimeInterval, BOOL, id))originalTimer)(
            cls, @selector(timerWithTimeInterval:repeats:block:), interval, repeats, block);
        timer.fireDate = NSDate.distantFuture;
        return timer;
    });
    method_setImplementation(timerMethod, deferredTimer);
    app = [HarnessActivityApp new];
    app.applicationState = UIApplicationStateBackground;

    harnessReport(@"activity-locked", @"Locked song");
    harnessLines(nil);
    sentLine = nil;
    extern void (^harnessLyricsRequested)(NSString *);
    harnessLyricsRequested = ^(NSString *track) {
        if (![track isEqual:@"activity-locked"]) return;
        harnessLyricsRequested = nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            harnessLines(@[lineOf(@"Locked lyric", 0, 1000000)]);
            [NSNotificationCenter.defaultCenter postNotificationName:SGKaraokeLinesKeptNotification object:track];
        });
    };
    SGSetLiveActivityEnabled(YES);
    HARNESS_AWAIT([sentLine isEqual:@"Locked lyric"]);
    check([sentLine isEqual:@"Locked lyric"], @"Live Activity requests and publishes lyrics while locked without now-playing or UI events");
    SGSetLiveActivityEnabled(NO);
    harnessLyricsRequested = nil;
    method_setImplementation(timerMethod, originalTimer);
    app = nil;
    imp_removeBlock(deferredTimer);
}

static void advance(double seconds);
static void lyricDeadlines(void) {
    extern BOOL harnessPlaying;
    virtualClock = harnessPlaying = YES;
    now = 10000;
    due = INFINITY;
    harnessReport(@"activity-deadlines", @"Deadline song");
    harnessLines(@[lineOf(@"First", 0, 9000), lineOf(@"Second", 10000, 19000)]);
    harnessPosition(0);
    SGSetLiveActivityEnabled(YES);
    refresh();
    check([sentLine isEqual:@"First"] && harnessActivityDelay > NSEC_PER_SEC,
          @"an unchanged playing lyric card sleeps until a lyric deadline");
    harnessPosition(9000);
    bridgeCost = .12;
    harnessLines(@[lineOf(@"Landing", 0, 9000), lineOf(@"Second", 10000, 19000)]);
    harnessReport(@"activity-deadlines", @"Deadline song");
    HARNESS_AWAIT([sentLine isEqual:@"Landing"]);
    bridgeCost = 0;
    check([sentLine isEqual:@"Landing"] && harnessActivityDelay == 80 * NSEC_PER_MSEC
          && harnessActivityRepeat == DISPATCH_TIME_FOREVER,
          @"120 ms spent publishing leaves 80 ms of the 200 ms lead-adjusted lyric deadline");
    harnessPosition(9200);
    advance(.08);
    check([sentLine isEqual:@"Second"], @"the deadline alone delivers the lead-adjusted lyric");
    SGKaraokeLine *prefetched = lineOf(@"Prefetched lead", 0, 9000);
    harnessLines(@[prefetched, lineOf(@"Next lead", 10000, 19000)]);
    harnessReport(@"prefetched", @"Prefetched song");
    harnessTrackOffset = 500; // Karaoke's DidChange follows the activity's DidReport.
    HARNESS_AWAIT([sentLine isEqual:@"Prefetched lead"]);
    check([sentLine isEqual:@"Prefetched lead"] && harnessActivityDelay == 500 * NSEC_PER_MSEC,
          @"skip uses the prefetched track's own offset for the line and next wake");
    harnessPlaying = NO;
    harnessPosition(0);
    harnessTrackOffset = 0;
    harnessReading(SGRLyricsReadingSource, YES);
    harnessReport(@"prefetched", @"Prefetched song");
    drainMain();
    [NSNotificationCenter.defaultCenter postNotificationName:SGLyricsAIResultDidChangeNotification object:@"prefetched"];
    prefetched.pronunciation = lineOf(@"New reading", 0, 9000); // applied later in the same notification turn
    HARNESS_AWAIT([sentLine isEqual:@"New reading"]);
    check([sentLine isEqual:@"New reading"], @"paused card rereads the saved pronunciation after in-place application");
    harnessReading(SGRLyricsReadingNone, NO);
    SGSetLiveActivityEnabled(NO);
    virtualClock = harnessPlaying = NO;
    showing = YES; timerFire = nil;
    harnessPosition(0);
}

static void advance(double seconds) {
    NSTimeInterval end = now + seconds;
    for (NSUInteger n = 0; due <= end && n < 100; n++) {
        now = due;
        due = INFINITY;
        fires++;
        timerFire();
    }
    now = end;
}

static void cardDeadlines(void) {
    extern BOOL harnessPlaying, harnessActivityOn;
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    app = [HarnessActivityApp new];
    app.applicationState = UIApplicationStateActive;
    virtualClock = harnessPlaying = harnessActivityOn = YES;
    now = 100000;
    fires = 0;
    due = INFINITY;
    [NSUserDefaults.standardUserDefaults setVolatileDomain:@{SGKeyLiveActivityView:@(SGLiveActivityPanel)} forName:NSArgumentDomain];
    harnessReport(nil, nil);
    SGSetLiveActivityEnabled(YES);
    advance(25);
    check(!fires, @"empty player leaves the activity clock disarmed");
    harnessDuration = 180;
    harnessReport(@"panel", @"Panel");
    drainMain();
    NSUInteger at = fires, sent = sends;
    advance(19);
    check(fires == at && sends == sent, @"stable playing panel has no idle fires or sends");
    advance(1);
    check(fires == at + 1 && sends == sent + 1, @"visible unchanged panel refreshes at 20 seconds");
    upcoming = @[harnessState(@"next", @"Queued").track];
    harnessReport(@"panel", @"Panel");
    HARNESS_AWAIT([sentTitles isEqual:@[@"Queued"]]);
    check([sentTitles isEqual:@[@"Queued"]], @"queue-only report updates the panel");
    [center postNotificationName:@"SGLiveActivityAction" object:@"tab:1"]; HARNESS_AWAIT(sentTab == 1);
    check(sentTab == 1, @"card intent changes tab without a timer");
    singLead = 5;
    harnessReport(@"sing-hold", @"Following track");
    drainMain();
    advance(1.5);
    check(sentStart.timeIntervalSince1970 == now, @"running progress reanchors while Sing holds the new track at zero");
    singLead = 0;
    harnessPosition(1500);
    advance(1.5);
    at = fires;
    advance(10);
    check(fires == at, @"running progress returns to refresh-only scheduling after the hold");
    harnessPlaying = NO;
    sleepEnd = [NSDate.activityDate dateByAddingTimeInterval:3];
    harnessReport(@"panel", @"Panel");
    HARNESS_AWAIT([sentSleepEnd isEqual:sleepEnd]);
    check([sentSleepEnd isEqual:sleepEnd], @"paused panel offers its active sleep timer");
    advance(3);
    check(!sentSleepEnd, @"sleep expiry removes Add/Cancel even before the owner's main-queue callback");
    sleepEnd = nil;
    at = fires;
    advance(19);
    check(fires == at, @"paused panel waits for refresh");
    // No card is left to feed. Only recheck at the background hold deadline.
    app.applicationState = UIApplicationStateBackground; showing = NO;
    [center postNotificationName:UIApplicationDidEnterBackgroundNotification object:nil];
    at = fires; sent = sends;
    advance(19);
    check(fires == at && sends == sent, @"closed background card has no idle fires or sends");
    advance(1);
    check(fires == at + 1 && sends == sent, @"closed background card rechecks only at its hold deadline");
    app.applicationState = UIApplicationStateActive; allowStart = NO;
    [center postNotificationName:UIApplicationDidBecomeActiveNotification object:nil];
    sent = sends; allowStart = YES;
    advance(10);
    check(showing && sends == sent + 1, @"refused foreground start retries at its deadline");
    started = [NSDate.activityDate dateByAddingTimeInterval:-(3600 - 2)];
    [center postNotificationName:UIApplicationDidBecomeActiveNotification object:nil];
    at = ends;
    advance(2);
    check(ends == at + 1 && showing, @"foreground age deadline renews before refresh");
    started = [NSDate.activityDate dateByAddingTimeInterval:-(8 * 3600 - 300 - 2)];
    app.applicationState = UIApplicationStateBackground;
    [center postNotificationName:UIApplicationDidEnterBackgroundNotification object:nil];
    advance(2);
    check(ends == at + 2 && !showing, @"background expiry ends the card before refresh");
    started = nil;
    app.applicationState = UIApplicationStateActive;
    pip = YES;
    [center postNotificationName:SGLyricsPiPDidChangeNotification object:nil]; drainMain();
    pip = NO;
    [center postNotificationName:SGLyricsPiPDidChangeNotification object:nil]; drainMain();
    sent = sends;
    advance(5);
    check(!showing && sends == sent, @"return from PiP waits while paused");
    harnessPlaying = YES; harnessReport(@"panel", @"Panel");
    HARNESS_AWAIT(showing);
    check(showing && sends == sent + 1, @"playback report restores the card after PiP");
    SGSetLiveActivityEnabled(NO);
    virtualClock = harnessPlaying = harnessActivityOn = NO;
    harnessDuration = 0;
    upcoming = nil; timerFire = nil; showing = YES;
    [NSUserDefaults.standardUserDefaults setVolatileDomain:@{} forName:NSArgumentDomain];
    app = nil;
}

void activityChecks(void) {
    [NSUserDefaults.standardUserDefaults setVolatileDomain:@{SGKeyLiveActivityTranslation: @YES} forName:NSArgumentDomain];
    harnessLanguage = @"en";
    harnessTranslations = @{@"en": @{@"Hola": @"Hello restored"}, @"ko": @{@"Hola": @"안녕"}};
    harnessReport(@"activity-restore", @"Song");
    harnessLines(@[lineOf(@"Hola", 0, 10000)]);
    NSUInteger automaticBefore = harnessAutomaticTranslations;
    SGSetLiveActivityEnabled(YES);
    refresh();
    check([sentLine isEqual:@"Hola"] && [sentTranslation isEqual:@"Hello restored"],
          @"Live Activity restores saved generated translation without opening lyrics");

    harnessLanguage = @"ko";
    refresh();
    HARNESS_AWAIT([sentTranslation isEqual:@"안녕"]);
    check([sentTranslation isEqual:@"안녕"], @"Live Activity reloads saved translation after language change");
    harnessTranslations = nil;
    [NSNotificationCenter.defaultCenter postNotificationName:SGLyricsTranslationsDidChangeNotification object:nil];
    HARNESS_AWAIT(!sentTranslation.length);
    check(!sentTranslation.length, @"paused Live Activity clears deleted translation without a view");

    harnessTranslations = @{@"ko": @{@"Hola": @"다시"}};
    [NSNotificationCenter.defaultCenter postNotificationName:SGLyricsTranslationSavedNotification
        object:@"activity-restore" userInfo:@{@"language": @"ko"}];
    HARNESS_AWAIT([sentTranslation isEqual:@"다시"]);
    check([sentTranslation isEqual:@"다시"], @"paused Live Activity refreshes a saved translation");

    harnessHoldTranslation = YES;
    harnessLanguage = @"en";
    harnessTranslations = @{@"en": @{@"Hola": @"Stale English"}, @"ko": @{@"Hola": @"새 소스"}};
    refresh();
    harnessLanguage = @"ko";
    refresh();
    harnessHoldTranslation = NO;
    harnessDeliverTranslations();
    HARNESS_AWAIT([sentTranslation isEqual:@"새 소스"]);
    check([sentTranslation isEqual:@"새 소스"], @"late retired-language load cannot overwrite the current activity");
    harnessTranslations = @{@"ko": @{@"Hola": @"다른 소스"}};
    harnessLines(@[lineOf(@"Hola", 0, 10000)]);
    refresh();
    HARNESS_AWAIT([sentTranslation isEqual:@"다른 소스"]);
    check([sentTranslation isEqual:@"다른 소스"], @"Live Activity restores translations onto replacement source lines");
    check(harnessAutomaticTranslations == automaticBefore, @"Live Activity never starts automatic translation");
    SGSetLiveActivityEnabled(NO);
    harnessTranslations = nil;
    harnessLanguage = @"en";
    [NSUserDefaults.standardUserDefaults setVolatileDomain:@{} forName:NSArgumentDomain];
    lockedLyrics();
    lyricDeadlines();
    [NSUserDefaults.standardUserDefaults setVolatileDomain:@{SGKeyLiveActivityView: @(SGLiveActivityQueue)} forName:NSArgumentDomain];
    SGSetLiveActivityEnabled(YES);
    refresh();
    check(queueLimit == 3, @"queue view requests only the three qualifying tracks it displays");
    SGSetLiveActivityEnabled(NO);
    cardDeadlines();
}
