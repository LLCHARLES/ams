// Podcasts and audiobooks on Home. HomeHeader.x's Logos output is included, so the filter menu and the way back from a hidden
// filter are driven over Spotify's chips as recorded on a device (Home_PillUIKit pills with the identifiers
// home-feed-default, home-feed-music-chip, home-feed-podcasts-chip). Also the pill's Friday ring, by the weekday.
#import <UIKit/UIKit.h>
#import "harness-fail.h"
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Redesigned/Kit/SGRMotionBudget.h"
#import "Home.h"

#import "../reduce-motion-fixture.h"
// Drive the application state read alongside the lifecycle notifications we send.
static UIApplicationState fixtureState = UIApplicationStateActive;
@interface UIApplication (FridayCheck)
- (UIApplicationState)fridayFixtureState;
@end
@implementation UIApplication (FridayCheck)
- (UIApplicationState)fridayFixtureState { return fixtureState; }
@end
#define applicationState fridayFixtureState
static BOOL lowPower;
static NSProcessInfoThermalState heat;
#define SGRMotionHeldForPowerOrHeat() SGRMotionHeldFor(lowPower, heat)
#include "HomeHeader.gen.m"
#undef SGRMotionHeldForPowerOrHeat
#undef applicationState

#pragma mark - helpers

static NSUInteger sg_checks;
#define CHECK(condition) do { sg_checks++; HARNESS_CHECK(condition); } while (0)

static NSUserDefaults *defaults(void) { return NSUserDefaults.standardUserDefaults; }

static void until(NSString *what, BOOL (^ready)(void)) {
    double deadline = NSProcessInfo.processInfo.systemUptime + 45;
    while (!ready()) {
        if (NSProcessInfo.processInfo.systemUptime >= deadline) HARNESS_FAIL(@"waiting for %@", what);
        [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
    }
}

static void drainChips(void) {
    __block BOOL done = NO;
    dispatch_async(dispatch_get_main_queue(), ^{ done = YES; });
    until(@"previous chip actions delivered", ^BOOL { return done; });
}

static void setHidePodcasts(BOOL hidden) {
    [defaults() setBool:hidden forKey:SGRKeyHomeHidePodcasts];
    SGPrefsChanged();
    drainChips();
}

#pragma mark - Home

static UIControl *makeChip(NSString *identifier, NSString *label, NSUInteger *fired) {
    UIControl *chip = [UIControl new];
    chip.accessibilityIdentifier = identifier;
    chip.accessibilityLabel = label;
    if (fired) [chip addAction:[UIAction actionWithHandler:^(UIAction *action) { (*fired)++; }] forControlEvents:UIControlEventPrimaryActionTriggered];
    return chip;
}

static NSArray<NSString *> *menuTitles(void) {
    NSMutableArray<NSString *> *titles = [NSMutableArray array];
    UIMenu *filters = (UIMenu *)menuElements().firstObject;
    for (UIAction *action in filters.children) [titles addObject:action.title];
    return titles;
}

// The page holds its stack weakly (sg_stack).
static UIStackView *sg_heldStack;
static NSUInteger sg_defaultFired, sg_musicFired, sg_podcastsFired, sg_audiobooksFired;

// Spotify's chips in their order: All, Music, Podcasts, and an Audiobooks one where the region has it.
static UIStackView *chipStack(void) {
    sg_defaultFired = sg_musicFired = sg_podcastsFired = sg_audiobooksFired = 0;
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[
        makeChip(@"home-feed-default", @"전체", &sg_defaultFired),
        makeChip(@"home-feed-music-chip", @"음악", &sg_musicFired),
        makeChip(@"home-feed-podcasts-chip", @"팟캐스트", &sg_podcastsFired),
        makeChip(@"home-feed-audiobooks-chip", @"오디오북", &sg_audiobooksFired),
    ]];
    stack.distribution = UIStackViewDistributionFillEqually;
    stack.frame = CGRectMake(0, 0, 400, 34);
    [stack layoutIfNeeded];
    sg_stack = sg_heldStack = stack;
    return stack;
}

static void checkMenu(void) {
    chipStack();
    setHidePodcasts(NO);
    NSArray<NSString *> *all = @[@"전체", @"음악", @"팟캐스트", @"오디오북"];
    CHECK([menuTitles() isEqualToArray:all]);
    setHidePodcasts(YES);
    CHECK([menuTitles() isEqualToArray:(@[@"전체", @"음악"])]);
    setHidePodcasts(NO);
    CHECK([menuTitles() isEqualToArray:all]);
}

static void checkLeaving(void) {
    UIStackView *stack = chipStack();
    UIControl *defaultChip = stack.arrangedSubviews[0], *music = stack.arrangedSubviews[1], *podcasts = stack.arrangedSubviews[2];
    setHidePodcasts(NO);
    // Shown: a chosen Podcasts chip is left alone.
    defaultChip.selected = NO;
    podcasts.selected = YES;
    syncPodcastChips(stack);
    drainChips();
    CHECK(sg_defaultFired == 0);

    // Hidden, and chosen: back to the default chip on the next turn, not this one, and once.
    [defaults() setBool:YES forKey:SGRKeyHomeHidePodcasts];
    SGPrefsChanged();
    syncPodcastChips(stack);
    CHECK(sg_defaultFired == 0);
    until(@"default chip action", ^BOOL { return sg_defaultFired > 0; });
    CHECK(sg_defaultFired == 1);
    syncPodcastChips(stack);
    drainChips();
    CHECK(sg_defaultFired == 1);
    CHECK(sg_musicFired == 0 && sg_podcastsFired == 0);

    // Home followed: another chip chosen is left alone.
    podcasts.selected = NO;
    defaultChip.selected = NO;
    music.selected = YES;
    syncPodcastChips(stack);
    drainChips();
    CHECK(sg_defaultFired == 1);

    // Chosen again later, the way back is asked again.
    music.selected = NO;
    podcasts.selected = YES;
    syncPodcastChips(stack);
    until(@"default chip reselected", ^BOOL { return sg_defaultFired >= 2; });
    CHECK(sg_defaultFired == 2);
    podcasts.selected = NO;
    setHidePodcasts(NO);
}

// The switch flipped on while Home is on Podcasts: the observer takes Home off it, with no layout pass of the page.
static void checkLive(void) {
    UIStackView *stack = chipStack();
    setHidePodcasts(NO);
    ((UIControl *)stack.arrangedSubviews[2]).selected = YES;
    drainChips();
    CHECK(sg_defaultFired == 0);
    setHidePodcasts(YES);
    until(@"live preference returned to All", ^BOOL { return sg_defaultFired != 0; });
    CHECK(sg_defaultFired == 1);
    ((UIControl *)stack.arrangedSubviews[2]).selected = NO;
    setHidePodcasts(NO);
}

#pragma mark - Friday

// The device's calendar answers the weekday a check asks for (Sunday 1); 0 leaves it the calendar's own.
static NSInteger sg_weekday;
static IMP sg_component;
static NSInteger answerComponent(NSCalendar *self, SEL _cmd, NSCalendarUnit unit, NSDate *date) {
    if (unit == NSCalendarUnitWeekday && sg_weekday) return sg_weekday;
    return ((NSInteger (*)(NSCalendar *, SEL, NSCalendarUnit, NSDate *))sg_component)(self, _cmd, unit, date);
}

static void answerWeekday(NSInteger weekday) {
    if (!sg_component) {
        Method method = class_getInstanceMethod(NSCalendar.currentCalendar.class, @selector(component:fromDate:));
        sg_component = method_setImplementation(method, (IMP)answerComponent);
    }
    sg_weekday = weekday;
}

static CAAnimation *ringTurn(CALayer *ring) {
    return [ring.sublayers.firstObject animationForKey:@"turn"];
}

static void switchReduceMotion(BOOL on) {
    harnessMotion = on ? reduceMotion : allowMotion;
    [NSNotificationCenter.defaultCenter postNotificationName:UIAccessibilityReduceMotionStatusDidChangeNotification object:nil];
}

static void scrollPillAwayAndBack(UIView *glass) {
    riseGlass(glass, CGAffineTransformMakeTranslation(0, -40), 0);
    until(@"pill material faded", ^BOOL { return !glass.layer.animationKeys.count; });
    riseGlass(glass, CGAffineTransformIdentity, 1);
}

// The pill's ring: only on a Friday, one turn in 6 s at no more than 30 frames a second, going and coming back with the
// pill's material as the title row scrolls, still while gone, and stopped and resumed by Reduce Motion as it is switched.
static void checkFriday(void) {
    UIWindow *window = [(id)UIApplication.sharedApplication.delegate window];
    UIView *glass = [[SGRHomeGlassHolder alloc] initWithFrame:CGRectMake(200, 100, 100, 44)];
    [window addSubview:glass];
    // riseGlass fades a material; SGRGlassCapsuleInside, a test double here, makes none.
    objc_setAssociatedObject(glass, &kPillGlassKey, [UIView new], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    CGSize size = glass.bounds.size;

    answerWeekday(5);
    layoutFriday(glass, size);
    CHECK(objc_getAssociatedObject(glass, &kFridayKey) == nil);

    answerWeekday(6);
    harnessMotion = reduceMotion;
    layoutFriday(glass, size);
    CALayer *ring = objc_getAssociatedObject(glass, &kFridayKey);
    CHECK(ring && !ring.hidden && ring.superlayer == glass.layer && ring.opacity == 1);
    CHECK(CGRectEqualToRect(ring.frame, CGRectMake(0, 0, 100, 44)));
    NSLog(@"[harness] Friday ring: host Reduce Motion %d, fixture %d, turn %@",
          hostReducesMotion(), SGRReduceMotion(), ringTurn(ring) ? @"on" : @"off");
    CHECK(SGRReduceMotion() && !ringTurn(ring));
    switchReduceMotion(NO);
    CABasicAnimation *turn = (CABasicAnimation *)ringTurn(ring);
    NSLog(@"[harness] Friday ring: host/app state %ld/%ld, host/fixture Reduce Motion %d/%d, window %d, resigning %d, glass %d, power %d, heat %ld, turn %@, duration %.1f max FPS %.0f",
          (long)UIApplication.sharedApplication.applicationState, (long)fixtureState, hostReducesMotion(), SGRReduceMotion(),
          glass.window != nil, ((SGRHomeGlassHolder *)glass).resigning, sg_glassShown, lowPower, (long)heat,
          turn ? @"on" : @"off", turn.duration, turn.preferredFrameRateRange.maximum);
    CHECK(turn.duration == 6 && turn.preferredFrameRateRange.maximum == 30);

    extern __weak UIView *harnessSettledPlayerField;
    UIView *cover = [[UIView alloc] initWithFrame:glass.frame];
    [window addSubview:cover];
    harnessSettledPlayerField = cover;
    [NSNotificationCenter.defaultCenter postNotificationName:SGRPlayerVisibilityDidChangeNotification object:nil];
    CHECK(!ringTurn(ring));
    harnessSettledPlayerField = nil;
    [cover removeFromSuperview];
    [NSNotificationCenter.defaultCenter postNotificationName:SGRPlayerVisibilityDidChangeNotification object:nil];
    CHECK(ringTurn(ring));
    [glass removeFromSuperview];
    CHECK(!ringTurn(ring));
    [window addSubview:glass];
    CHECK(ringTurn(ring));
    [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationWillResignActiveNotification object:nil];
    CHECK(!ringTurn(ring));
    fixtureState = UIApplicationStateInactive;
    layoutFriday(glass, size);
    CHECK(!ringTurn(ring));
    fixtureState = UIApplicationStateActive;
    [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationDidBecomeActiveNotification object:nil];
    CHECK(ringTurn(ring));
    lowPower = YES;
    [NSNotificationCenter.defaultCenter postNotificationName:NSProcessInfoPowerStateDidChangeNotification object:nil];
    CHECK(!ringTurn(ring));
    heat = NSProcessInfoThermalStateSerious;
    lowPower = NO;
    [NSNotificationCenter.defaultCenter postNotificationName:NSProcessInfoPowerStateDidChangeNotification object:nil];
    CHECK(!ringTurn(ring));
    heat = NSProcessInfoThermalStateFair;
    [NSNotificationCenter.defaultCenter postNotificationName:NSProcessInfoThermalStateDidChangeNotification object:nil];
    CHECK(ringTurn(ring));

    riseGlass(glass, CGAffineTransformMakeTranslation(0, -40), 0);
    CHECK(ring.opacity == 0);
    until(@"hidden Friday ring stopped", ^BOOL { return !ringTurn(ring); });
    CHECK(ringTurn(ring) == nil);
    riseGlass(glass, CGAffineTransformIdentity, 1);
    CHECK(ring.opacity == 1);
    CHECK(ringTurn(ring) != nil);

    // Reduce Motion switched with no layout after it.
    switchReduceMotion(YES);
    CHECK(ringTurn(ring) == nil);
    switchReduceMotion(NO);
    CHECK(ringTurn(ring) != nil);

    // Saturday's layout hides the ring, and the pill scrolled away and back leaves it still.
    answerWeekday(7);
    layoutFriday(glass, size);
    CHECK(ring.hidden && ringTurn(ring) == nil);
    scrollPillAwayAndBack(glass);
    CHECK(ringTurn(ring) == nil);
    answerWeekday(0);
    [glass removeFromSuperview];
    harnessMotion = useHostMotion;
}

static void run(void) {
    checkMenu();
    checkLeaving();
    checkLive();
    checkFriday();
    [defaults() removeObjectForKey:SGRKeyHomeHidePodcasts];
    printf("[harness] home-podcasts: %lu checks passed\n", (unsigned long)sg_checks);
    fflush(stdout);
    exit(0);
}

@interface HomePodcastsApp : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end
@implementation HomePodcastsApp
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    self.window = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, 390, 844)];
    self.window.rootViewController = [UIViewController new];
    // A timer, not a block of the main queue: the checks run the run loop, which would not run the main queue's other blocks from inside one.
    [NSTimer scheduledTimerWithTimeInterval:0 repeats:NO block:^(NSTimer *timer) { run(); }];
    return YES;
}
@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(HomePodcastsApp.class));
    }
}
