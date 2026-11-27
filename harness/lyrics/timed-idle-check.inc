// Drive the real display link, timer and renderer. Only Spotify's reports/position are scripted.
#import "Shared/Player/SpeedPitch.h"
@interface SGRKaraokeView (TimedIdleCheck)
- (void)tick;
- (void)playerStateDidReport:(id)state;
@end
@interface SGTimedIdleView : SGRKaraokeView
@property (nonatomic) NSUInteger ticks;
@property (nonatomic) double collapseClock;
@end
@implementation SGTimedIdleView
- (void)tick {
    self.ticks++;
    BOOL open = [[self valueForKey:@"openBreak"] integerValue] == 1;
    [super tick];
    if (open && [[self valueForKey:@"openBreak"] integerValue] < 0)
        self.collapseClock = [[self valueForKey:@"clock"] doubleValue];
}
@end

static void timedIdleChecks(UIWindow *window) {
    extern id SGPlayerState(void);
    extern void SGHarnessPause(BOOL);
    SGHarnessPlayingTrack = @"timed-idle";
    SGKaraokeLine *line = sungLine(0, @"whole line");
    line.timing = SGKaraokeTimingLine;
    line.end = 20000;
    SGKaraokeLine *words = sungLine(30000, @"moving word");
    words.timing = SGKaraokeTimingWords;
    words.words.lastObject.end = words.end = 35000;
    SGKaraokeKeepLines(SGHarnessPlayingTrack, @[line, words]);
    SGHarnessStartClock(12000, 1, -1, 0);
    UIViewController *root = [UIViewController new];
    window.rootViewController = root;
    [window makeKeyAndVisible];
    SGTimedIdleView *view = [[SGTimedIdleView alloc] initWithFrame:CGRectMake(0, 0, 360, 540)];
    [root.view addSubview:view];
    autoTick(view);
    // Connecting the scene can replace the link installed when the view entered its window.
    BOOL settled = extrasWait(^BOOL { return !view.hidden && ((CADisplayLink *)[view valueForKey:@"link"]).paused; });
    CADisplayLink *link = [view valueForKey:@"link"];
    check(settled, [NSString stringWithFormat:@"advancing whole line parks after settlement (link %@, %lu ticks, clock %@, visible %d)",
                    link ? @"installed" : @"absent", (unsigned long)view.ticks, [view valueForKey:@"clock"], !view.hidden]);
    if (!settled) { [view removeFromSuperview]; return; }
    NSUInteger ticks = view.ticks;
    for (int i = 0; i < 4; i++) {
        [view playerStateDidReport:SGPlayerState()];
        extern void LyricsAfterDisplayFrames(dispatch_block_t);
        __block BOOL frames = NO;
        LyricsAfterDisplayFrames(^{ frames = YES; });
        check(extrasWait(^BOOL { return frames; }), @"display opportunities arrived while the lyrics were parked");
    }
    check(view.ticks == ticks, @"zero display callbacks across four advancing reports inside the same static line");

    // Land on the settled line, then switch speed as a cover hold does, without a report.
    SGHarnessStartClock(16500, 1, -1, 0);
    [view playerStateDidReport:SGPlayerState()];
    check(extrasWait(^BOOL { return link.paused && [[view valueForKey:@"clock"] doubleValue] >= 16500; }),
          @"1x deadline armed before the cover hold");
    SGHarnessStartClock(SGKaraokePositionMs(), 2, -1, 0);
    [NSNotificationCenter.defaultCenter postNotificationName:SGPlayerSpeedDidChangeNotification object:nil];
    check(extrasWait(^BOOL { return [[view valueForKey:@"openBreak"] integerValue] == 1; }),
          @"2x cover hold shows the break before the old 1x deadline");

    // Sing can retain lead even with its switch off. The output flush below changes only the
    // position read from the same state: its six seconds of held audio are no longer subtracted.
    extern double SGHarnessHeldLead;
    SGHarnessHeldLead = 6;
    SGHarnessStartClock(21000, 1, -1, 0);
    [view playerStateDidReport:SGPlayerState()];
    check(extrasWait(^BOOL { return SGKaraokePositionMs() >= 17200 && [[view valueForKey:@"openBreak"] integerValue] < 0; }),
          @"held audio leaves the line lit before the flush");
    SGHarnessHeldLead = 0;
    check(extrasWait(^BOOL { return [[view valueForKey:@"openBreak"] integerValue] == 1; }) && SGKaraokePositionMs() < 26000,
          @"Sing flush shows the break without a report, before the held clock would reach it");

    // External scrub into the instrumental. No more reports: CA runs the dots, the page must
    // wake itself for their half-second collapse and then start the next line's word sweep.
    SGHarnessStartClock(27000, 1, -1, 0);
    [view playerStateDidReport:SGPlayerState()];
    check(extrasWait(^BOOL { return [[view valueForKey:@"openBreak"] integerValue] == 1 && link.paused; }),
          @"seek into the break installs the dots and parks the link");
    view.collapseClock = -1;
    check(extrasWait(^BOOL { return view.collapseClock >= 0; }),
          @"break collapses before the next line without another player report");
    double clock = view.collapseClock;
    check(clock >= 29500 && clock < 30000, @"break collapse is on its own displayed timestamp");
    UIView *(^row)(void) = ^UIView *{ return [view valueForKey:@"shown"][@1]; };
    check(extrasWait(^BOOL { return (row().accessibilityTraits & UIAccessibilityTraitSelected) != 0; }),
          @"word line selected at the end of the break");
    ticks = view.ticks;
    check(extrasWait(^BOOL { return view.ticks >= ticks + 4; }) && !link.paused && link.preferredFrameRateRange.maximum == 120,
          @"word sweep receives successive frames at the full-rate preference");
    SGHarnessPause(YES);
    check(extrasWait(^BOOL { return link.paused; }), @"stationary word sweep calms down on pause");
    UIScrollView *scroll = [view valueForKey:@"scroll"];
    [scroll.delegate scrollViewWillBeginDragging:scroll];
    check(!link.paused, @"dragging wakes the lyrics link");
    [view removeFromSuperview];
    SGHarnessPause(NO);
}
