// Real player consumers and label setters; only application state, scheduling and clip I/O are faked.
#import <UIKit/UIKit.h>
#import "Redesigned/Player/Player.h"
#import "Redesigned/Kit/SGRRefinements.h"
#import "Shared/AnimatedArtwork/AnimatedArtwork.h"
#import "Shared/AnimatedArtwork/SGMotionTicket.h"
#import "Shared/AutoMix/AutoMix.h"
#import "Shared/AutoMix/AutoMixPreview.h"
#import "Shared/Player/PlayerState.h"
#import "../background-work.h"

void SGRHarnessSetTrack(NSString *, NSString *, BOOL);
NSArray<SGMotionTicket *> *SGRHarnessMotionTickets(void);
void SGRHarnessSetTransition(SGTransitionFacts *);
@interface SGTransitionFacts (BackgroundCheck)
+ (instancetype)sgr_harnessFrom:(NSString *)fromURI to:(NSString *)toURI kind:(SGTransitionKind)kind known:(BOOL)known
                       outStart:(double)outStart outEnd:(double)outEnd inStart:(double)inStart inEnd:(double)inEnd;
@end

static NSUInteger failures, checks;
static void check(BOOL ok, NSString *message) {
    checks++;
    failures += !ok;
    NSLog(@"[background] %@ %@", ok ? @"PASS" : @"FAIL", message);
}
static UILabel *digits(UIView *host) {
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(10, 10, 150, 30)];
    label.text = @"1:00";
    [host addSubview:label];
    SGRRollDigits(label);
    label.text = @"1:01";
    return label;
}

void SGRHarnessRunBackground(UIWindow *window, UIViewController *background, UIView *tilt) {
    SGHarnessBeginBackgroundWork();
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    [center postNotificationName:UIApplicationDidBecomeActiveNotification object:nil];
    [background viewWillAppear:NO];
    [background viewDidAppear:NO];
    SGRSetPlayerBackground(SGRPlayerBackgroundAnimated);
    SGRPlayerBackgroundDidChange();
    SGRHarnessSetTrack(@"spotify:track:foreground", nil, NO);
    SGMotionTicket *foreground = SGRHarnessMotionTickets().lastObject;
    check(foreground && !foreground.cancelled, @"visible player starts current lookup");
    [background viewDidDisappear:NO];
    check(foreground.cancelled, @"disappearing player cancels its lookup");
    NSUInteger requests = SGRHarnessMotionTickets().count;
    SGRHarnessSetTrack(@"spotify:track:hidden", nil, NO);
    check(SGRHarnessMotionTickets().count == requests, @"hidden player starts no lookup");
    [background viewWillAppear:NO];
    [background viewDidAppear:NO];
    check(SGRHarnessMotionTickets().count == requests + 1, @"visibility resumes the current track");
    SGMotionTicket *resumed = SGRHarnessMotionTickets().lastObject;
    requests = SGRHarnessMotionTickets().count;
    background.view.hidden = YES;
    check(resumed.cancelled, @"hiding an ancestor cancels current artwork without a layout callback");
    background.view.hidden = NO;
    check(SGRHarnessMotionTickets().count == requests + 1, @"unhiding an ancestor resumes the current track without layout");
    resumed = SGRHarnessMotionTickets().lastObject;
    requests = SGRHarnessMotionTickets().count;
    background.view.alpha = 0;
    check(resumed.cancelled, @"fading an ancestor cancels current artwork");
    background.view.alpha = 1;
    check(SGRHarnessMotionTickets().count == requests + 1, @"unfading an ancestor resumes the current track");
    resumed = SGRHarnessMotionTickets().lastObject;
    __attribute__((objc_precise_lifetime)) SGMotionFollower *lockScreen = [[SGMotionFollower alloc]
        initWithBegin:^BOOL(NSString *uri, SPTPlayerState *state) { return YES; }
        found:^(NSString *uri, NSURL *file) {}];
    [lockScreen restart];
    SGMotionTicket *lockTicket = SGRHarnessMotionTickets().lastObject;

    UIView *host = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 200, 80)];
    [window addSubview:host];
    UILabel *rolling = digits(host);
    check(rolling.layer.mask != nil, @"visible digits still animate");
    [center postNotificationName:UIApplicationWillResignActiveNotification object:nil];
    check(resumed.cancelled, @"resign-active cancels current player lookup before app state changes");
    check(!lockTicket.cancelled, @"separate lock-screen consumer keeps its lookup");
    check(rolling.layer.mask == nil && host.subviews.count == 1, @"resign-active removes digits overlays");
    sg_testAppState = UIApplicationStateBackground;
    requests = SGRHarnessMotionTickets().count;
    SGRHarnessSetTrack(@"spotify:track:background", nil, NO);
    check(SGRHarnessMotionTickets().count == requests + 1, @"only lock-screen consumer fetches in background");
    UILabel *inactive = digits(host);
    check(inactive.layer.mask == nil && [inactive.text isEqual:@"1:01"], @"inactive digits update directly");
    sg_testAppState = UIApplicationStateActive;
    [center postNotificationName:UIApplicationDidBecomeActiveNotification object:nil];
    host.hidden = YES;
    UILabel *hidden = digits(host);
    check(hidden.layer.mask == nil, @"digits under hidden ancestor update directly");
    host.hidden = NO;
    host.frame = CGRectMake(-1000, 0, 200, 80);
    UILabel *offscreen = digits(host);
    check(offscreen.layer.mask == nil, @"offscreen digits update directly");
    [host removeFromSuperview];

    // No artwork ready: inside the outgoing window AutoMix must wait, but not while inactive.
    SGRSetPlayerBackground(SGRPlayerBackgroundFluid);
    SGRPlayerBackgroundDidChange();
    [NSUserDefaults.standardUserDefaults setBool:YES forKey:SGKeyAutoMixArtwork];
    [center postNotificationName:SGAutoMixPlayerOptionsDidChangeNotification object:nil];
    SGRHarnessSetTrack(@"spotify:track:mix-from", nil, NO);
    SPTPlayerState *state = SGPlayerState();
    [state setValue:@0 forKey:@"positionAsOfTimestamp"];
    [state setValue:@1 forKey:@"playbackSpeed"];
    [state setValue:@YES forKey:@"isPlaying"];
    SGTransitionFacts *facts = [SGTransitionFacts sgr_harnessFrom:@"spotify:track:mix-from" to:@"spotify:track:mix-to"
        kind:SGTransitionKindCrossfade known:YES outStart:0 outEnd:100000 inStart:0 inEnd:10];
    for (NSTimer *timer in sg_testTimers) [timer invalidate];
    [SGRHarnessMotionTickets() enumerateObjectsUsingBlock:^(SGMotionTicket *ticket, NSUInteger i, BOOL *stop) { [ticket cancel]; }];
    SGRHarnessSetTransition(facts);
    check(SGHarnessLiveTimers() > 0, @"eligible AutoMix arms while artwork is pending");
    [center postNotificationName:UIApplicationWillResignActiveNotification object:nil];
    check(SGHarnessLiveTimers() == 0, @"resign-active disarms AutoMix retries");
    sg_testAppState = UIApplicationStateBackground;
    [center postNotificationName:SGAutoMixPlayerOptionsDidChangeNotification object:nil];
    check(SGHarnessLiveTimers() == 0, @"background readiness cannot rearm AutoMix");
    sg_testAppState = UIApplicationStateActive;
    [center postNotificationName:UIApplicationDidBecomeActiveNotification object:nil];
    check(SGHarnessLiveTimers() > 0, @"foreground resumes AutoMix readiness");
    tilt.hidden = YES;
    [center postNotificationName:SGAutoMixPlayerOptionsDidChangeNotification object:nil];
    check(SGHarnessLiveTimers() == 0 && SGRPlayerIsVisible(), @"visible field waits without polling for an absent cover");
    tilt.hidden = NO;
    [tilt layoutSubviews];
    check(SGHarnessLiveTimers() > 0, @"cover layout resumes AutoMix without another player report");
    SGHarnessEndBackgroundWork();
    NSLog(@"background checks: %lu of %lu right -- %@", (unsigned long)(checks - failures), (unsigned long)checks, failures ? @"FAIL" : @"PASS");
    exit(failures ? 1 : 0);
}
