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
dispatch_time_t HarnessActivityTime(dispatch_time_t when, int64_t delta) {
    harnessActivityDelay = delta;
    return dispatch_time(when, delta);
}
void HarnessActivitySetTimer(dispatch_source_t timer, dispatch_time_t start, uint64_t interval, uint64_t leeway) {
    harnessActivityRepeat = interval;
    dispatch_source_set_timer(timer, start, interval, leeway);
}

static NSString *sentTranslation, *sentLine;
@interface SGLiveActivityBridge : NSObject
@end
@implementation SGLiveActivityBridge
+ (BOOL)isShowing { return YES; }
+ (NSDate *)startedAt { return [NSDate date]; }
+ (BOOL)canStart { return YES; }
+ (void)end {}
+ (void)endBeforeExit {}
+ (void)showWithView:(NSInteger)view paused:(BOOL)paused line:(NSString *)line nextLine:(NSString *)nextLine
              titles:(NSArray *)titles artists:(NSArray *)artists uris:(NSArray *)uris
                 tab:(NSInteger)tab title:(NSString *)title artist:(NSString *)artist shuffle:(BOOL)shuffle repeatMode:(NSInteger)repeatMode
            timerEnd:(NSDate *)timerEnd timerEndOfTrack:(BOOL)timerEndOfTrack timerEndOfAlbum:(BOOL)timerEndOfAlbum
                tint:(NSString *)tint trackStart:(NSDate *)trackStart trackEnd:(NSDate *)trackEnd pausedAt:(NSNumber *)pausedAt
         translation:(NSString *)translation cover:(NSData *)cover textSize:(NSInteger)textSize
           alignment:(NSInteger)alignment noLyrics:(BOOL)noLyrics withoutLyrics:(NSInteger)withoutLyrics
             colors:(NSInteger)colors accent:(NSString *)accent progressBar:(BOOL)progressBar {
    sentLine = line;
    sentTranslation = translation;
}
@end

BOOL SGLyricsPiPActive(void) { return NO; }
NSNotificationName const SGLyricsPiPDidChangeNotification = @"harness.pip";
// The card runs as on an IPA build with its extension; the settings page that checks the bundle is not built here.
BOOL SGLiveActivityAllowedByInstall(void) { return YES; }
// No string tables here: English, as SGL gives without one.
NSString *SGL(NSString *key, NSString *english) { return english; }
BOOL SGKaraokeLooking(NSString *track) { return NO; }
static NSUInteger queueLimit;
NSArray *SGPlayerUpcomingTracks(SPTPlayerState *state, NSUInteger limit) { queueLimit = limit; return @[]; }
id SGPlayerAdvanceRepeat(id player, id options) { return nil; }
SGSleepTimerMode SGSleepTimerCurrentMode(void) { return SGSleepTimerOff; }
NSDate *SGSleepTimerEnd(void) { return nil; }
void SGSetSleepTimer(SGSleepTimerMode mode, NSTimeInterval seconds) {}
void SGSleepTimerAdd(NSTimeInterval seconds) {}
BOOL SGSingOn(void) { return NO; }
NSString *SGSingMissing(void) { return nil; }
void SGSetSingOn(BOOL on) {}
BOOL SGLikePlayingTrack(void) { return NO; }

static void refresh(void) {
    // The card's normal action notification asks its timer owner to publish now.
    [NSNotificationCenter.defaultCenter postNotificationName:@"SGLiveActivityAction" object:@"tab:0"];
    runFor(.05);
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
    Method stateMethod = class_getInstanceMethod(UIApplication.class, @selector(applicationState));
    IMP originalState = method_getImplementation(stateMethod);
    IMP backgroundState = imp_implementationWithBlock(^UIApplicationState(id app) { return UIApplicationStateBackground; });
    method_setImplementation(timerMethod, deferredTimer);
    method_setImplementation(stateMethod, backgroundState);

    harnessState(@"activity-locked", @"Locked song");
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
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:3];
    while (![sentLine isEqual:@"Locked lyric"] && deadline.timeIntervalSinceNow > 0) runFor(.01);
    check([sentLine isEqual:@"Locked lyric"], @"Live Activity requests and publishes lyrics while locked without now-playing or UI events");
    SGSetLiveActivityEnabled(NO);
    harnessLyricsRequested = nil;
    method_setImplementation(timerMethod, originalTimer);
    method_setImplementation(stateMethod, originalState);
    imp_removeBlock(deferredTimer);
    imp_removeBlock(backgroundState);
}

static void lyricDeadlines(void) {
    Method paused = class_getInstanceMethod(SPTPlayerState.class, @selector(isPaused));
    IMP original = method_getImplementation(paused);
    IMP playing = imp_implementationWithBlock(^BOOL(id state) { return NO; });
    method_setImplementation(paused, playing);
    harnessState(@"activity-deadlines", @"Deadline song");
    harnessLines(@[lineOf(@"First", 0, 9000), lineOf(@"Second", 10000, 19000)]);
    harnessPosition(0);
    SGSetLiveActivityEnabled(YES);
    refresh();
    check([sentLine isEqual:@"First"] && harnessActivityDelay == NSEC_PER_SEC,
          @"an unchanged playing lyric card waits a second instead of polling at 4 Hz");
    harnessPosition(9000);
    refresh();
    check([sentLine isEqual:@"First"] && harnessActivityDelay == 200 * NSEC_PER_MSEC
          && harnessActivityRepeat == DISPATCH_TIME_FOREVER,
          @"the next lyric boundary arms a one-shot 200 ms deadline, including rendering lead");
    harnessPosition(9200);
    refresh();
    check([sentLine isEqual:@"Second"], @"the line changes exactly at the lead-adjusted lyric boundary");
    SGSetLiveActivityEnabled(NO);
    method_setImplementation(paused, original);
    imp_removeBlock(playing);
    harnessPosition(0);
}

void activityChecks(void) {
    [NSUserDefaults.standardUserDefaults setVolatileDomain:@{SGKeyLiveActivityTranslation: @YES} forName:NSArgumentDomain];
    harnessLanguage = @"en";
    harnessTranslations = @{@"en": @{@"Hola": @"Hello restored"}, @"ko": @{@"Hola": @"안녕"}};
    harnessState(@"activity-restore", @"Song");
    harnessLines(@[lineOf(@"Hola", 0, 10000)]);
    NSUInteger automaticBefore = harnessAutomaticTranslations;
    SGSetLiveActivityEnabled(YES);
    refresh();
    check([sentLine isEqual:@"Hola"] && [sentTranslation isEqual:@"Hello restored"],
          @"Live Activity restores saved generated translation without opening lyrics");

    harnessLanguage = @"ko";
    refresh();
    check([sentTranslation isEqual:@"안녕"], @"Live Activity reloads saved translation after language change");
    harnessTranslations = nil;
    [NSNotificationCenter.defaultCenter postNotificationName:SGLyricsTranslationsDidChangeNotification object:nil];
    runFor(.05);
    check(!sentTranslation.length, @"paused Live Activity clears deleted translation without a view");

    harnessTranslations = @{@"ko": @{@"Hola": @"다시"}};
    [NSNotificationCenter.defaultCenter postNotificationName:SGLyricsTranslationSavedNotification
        object:@"activity-restore" userInfo:@{@"language": @"ko"}];
    runFor(.05);
    check([sentTranslation isEqual:@"다시"], @"paused Live Activity refreshes a saved translation");

    harnessHoldTranslation = YES;
    harnessLanguage = @"en";
    harnessTranslations = @{@"en": @{@"Hola": @"Stale English"}, @"ko": @{@"Hola": @"새 소스"}};
    refresh();
    harnessLanguage = @"ko";
    refresh();
    harnessHoldTranslation = NO;
    harnessDeliverTranslations();
    runFor(.05);
    check([sentTranslation isEqual:@"새 소스"], @"late retired-language load cannot overwrite the current activity");
    harnessTranslations = @{@"ko": @{@"Hola": @"다른 소스"}};
    harnessLines(@[lineOf(@"Hola", 0, 10000)]);
    refresh();
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
    [NSUserDefaults.standardUserDefaults setVolatileDomain:@{} forName:NSArgumentDomain];
}
