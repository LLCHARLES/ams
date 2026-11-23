// A stationary playback clock, real menu actions, rows and Core Animation geometry.
#import "Shared/Sing/Sing.h"
@interface SGRKaraokeView (ReaderCheck)
- (UIView *)lineUnder:(CGPoint)point;
- (void)tapped:(UITapGestureRecognizer *)tap;
- (void)held:(UILongPressGestureRecognizer *)hold;
@end
@interface SGHarnessTap : UITapGestureRecognizer
@property (nonatomic) CGPoint point;
@end

@interface SGReaderHold : UILongPressGestureRecognizer
@property (nonatomic) CGPoint point;
@end
@implementation SGReaderHold
- (UIGestureRecognizerState)state { return UIGestureRecognizerStateBegan; }
- (CGPoint)locationInView:(UIView *)view { return [view convertPoint:self.point fromView:nil]; }
@end

static void readerCornerGestures(SGRKaraokeView *view) {
    UIView *box = [view valueForKey:@"extrasBox"];
    CGRect corner = [box convertRect:box.bounds toView:nil];
    __block UIView *line;
    __block CGPoint point;
    BOOL overlaps = extrasWait(^BOOL {
        for (UIView *row in [[view valueForKey:@"shown"] allValues]) {
            CGRect hit = CGRectIntersection(corner, [row convertRect:row.bounds toView:nil]);
            if (CGRectIsEmpty(hit)) continue;
            line = row;
            point = CGPointMake(CGRectGetMidX(hit), CGRectGetMidY(hit));
            return YES;
        }
        return NO;
    });
    check(overlaps, @"a lyric row crosses the options button");
    if (!overlaps) return;
    SGReaderHold *hold = [SGReaderHold new]; hold.point = point;
    SGHarnessTap *tap = [SGHarnessTap new]; tap.point = point;
    NSInteger before = SGKaraokePositionMs(), start = ((SGKaraokeLine *)[line valueForKey:@"line"]).start;
    [view held:hold]; [view tapped:tap];
    check(![view valueForKey:@"heldLine"] && SGKaraokePositionMs() == before && before != start,
          @"shown options keep both gestures away from the verse");
    view.extrasHidden = YES;
    [view held:hold];
    BOOL held = [view valueForKey:@"heldLine"] == line;
    [view tapped:tap];
    check(held && SGKaraokePositionMs() == start, @"hold opens the line menu and tap seeks under tucked options");
    view.extrasHidden = NO;
}

static UIApplicationState readerInactive(id app, SEL cmd) { return UIApplicationStateInactive; }

static void readerInterruptedError(SGRKaraokeView *view) {
    googleHolds();
    sg_held = nil;
    BOOL started = tap(item(view, @"Translate with Google")) && sg_held;
    check(started, @"manual translation starts before interruption");
    if (!started) return;
    UIApplication *app = UIApplication.sharedApplication;
    Method state = class_getInstanceMethod(app.class, @selector(applicationState));
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    [center postNotificationName:UIApplicationWillResignActiveNotification object:app];
    IMP realState = method_setImplementation(state, (IMP)readerInactive);
    sg_alert = nil;
    view.superview.alpha = 0;
    sg_held(nil, @"interrupted request");
    BOOL waited = !sg_alert;
    method_setImplementation(state, realState);
    [center postNotificationName:UIApplicationDidBecomeActiveNotification object:app];
    BOOL stillCovered = !sg_alert;
    view.superview.alpha = 1;
    check(waited && stillCovered && [sg_alert.message containsString:@"interrupted request"],
          @"a same-song error delivered while inactive is presented on return");
    sg_held = nil;
}

static void readerChecks(UIWindow *window) {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    [defaults setBool:NO forKey:SGRKeyLyricsAutoTranslation];
    [defaults setBool:YES forKey:SGKeyLyricsTranslateEverySong];
    [defaults setBool:YES forKey:SGKeyLyricsGoogleTranslate];
    [defaults setBool:YES forKey:SGKeyLyricsRomanised];
    [defaults setBool:YES forKey:SGRKeyLyricsPronunciation];
    [defaults setBool:YES forKey:SGRKeyLyricsTranslation];
    [defaults setBool:YES forKey:SGKeySingButton];
    [defaults setObject:@"en" forKey:@"translateTo"];
    SGHarnessPlayingTrack = @"reader-a";
    SGHarnessStartClock(100, 0, -1, 0);
    NSMutableArray<SGKaraokeLine *> *lines = [NSMutableArray array];
    for (NSInteger i = 0; i < 64; ++i)
        [lines addObject:sungLine(i * 2000, [NSString stringWithFormat:@"verse%ld", (long)i])];
    lines[0].pronunciation = sungLine(0, @"provider");
    SGKaraokeKeepLines(SGHarnessPlayingTrack, lines);
    UIViewController *root = [UIViewController new];
    window.rootViewController = root;
    [window makeKeyAndVisible];
    SGRKaraokeView *view = [[SGRKaraokeView alloc] initWithFrame:CGRectMake(0, 0, 560, 320)];
    [root.view addSubview:view];
    autoTick(view);
    UIScrollView *scroll = [view valueForKey:@"scroll"];
    UIView *(^row)(NSInteger) = ^UIView *(NSInteger i) { return [view valueForKey:@"shown"][@(i)]; };
    BOOL ready = extrasWait(^BOOL { return !view.hidden && extrasLabel(view, @"provider") && row(3); });
    check(ready, @"reader fixture displays the provider's pronunciation");
    if (!ready) return;

    UIAction *hide = (id)item(view, @"Hide Pronunciation");
    if (hide) {
        UIView *old = row(0);
        tap(hide);
        extrasWait(^BOOL { return row(0) && old != row(0); });
    }
    check(extrasLabel(view, @"provider") && !hide && !item(view, @"Show Pronunciation"),
          @"always-on readings show the provider row without a no-op Show/Hide action");

    CAGradientLayer *mask = (id)scroll.layer.mask;
    NSNumber *withControls = mask.locations[3];
    view.extrasHidden = YES;
    [view layoutIfNeeded];
    check(withControls.doubleValue < 1 && [mask.locations[3] doubleValue] == 1,
          @"tucking both landscape controls frees their transparent strip");
    view.keepsSing = YES;
    view.extrasHidden = YES;
    [view layoutIfNeeded];
    check([mask.locations[3] isEqual:withControls], @"a mic that stays shown keeps its clearance");
    view.extrasHidden = NO;
    [view layoutIfNeeded];

    // Hold a spring at its starting position, with the two model rows already at their destinations.
    extrasWait(^BOOL { return row(2) && row(3); });
    UIView *moving = row(2), *neighbour = row(3);
    for (UIView *line in @[moving ?: view, neighbour ?: view]) {
        CASpringAnimation *spring = [CASpringAnimation animationWithKeyPath:@"position"];
        spring.fromValue = [NSValue valueWithCGPoint:(line == moving ? neighbour : moving).center];
        spring.toValue = [NSValue valueWithCGPoint:line.center];
        spring.duration = spring.settlingDuration;
        spring.speed = 0;
        [line.layer addAnimation:spring forKey:@"readerCheck"];
    }
    [CATransaction flush];
    __block CGPoint touch;
    BOOL crossing = extrasWait(^BOOL {
        CALayer *shown = moving.layer.presentationLayer;
        if (!shown || !row(3)) return NO;
        touch = CGPointMake(CGRectGetMidX(shown.frame), CGRectGetMidY(shown.frame));
        return CGRectContainsPoint(row(3).frame, touch);
    });
    check(crossing, @"a displayed row occupies its neighbour's model frame mid-spring");
    if (crossing) {
        BOOL hold = [view lineUnder:touch] == moving;
        SGHarnessTap *tapAt = [SGHarnessTap new];
        tapAt.point = [scroll convertPoint:touch toView:nil];
        [view tapped:tapAt];
        check(hold && SGKaraokePositionMs() == lines[2].start,
              @"hold and tap target the displayed verse, not its neighbour's destination");
    }
    [moving.layer removeAnimationForKey:@"readerCheck"];
    [neighbour.layer removeAnimationForKey:@"readerCheck"];

    [scroll.delegate scrollViewWillBeginDragging:scroll];
    scroll.contentOffset = CGPointMake(0, 1000);
    __block NSInteger index = NSNotFound;
    __block CGFloat y;
    BOOL browsed = extrasWait(^BOOL {
        for (NSInteger i = 1; i < (NSInteger)lines.count; ++i) {
            UIView *prior = row(i-1), *candidate = row(i);
            if (!prior || !candidate) continue;
            CGRect previous = [prior convertRect:prior.bounds toView:view];
            CGRect current = [candidate convertRect:candidate.bounds toView:view];
            if (CGRectGetMinY(previous) < 0 && CGRectGetMinY(current) >= 0 &&
                CGRectGetMaxY(current) <= view.bounds.size.height) {
                index = i; y = CGRectGetMinY(current); return YES;
            }
        }
        return NO;
    });
    check(browsed, @"hand browsing reaches a first fully visible original row");
    if (browsed) {
        NSMutableArray *batch = [NSMutableArray array];
        for (NSInteger i = 0; i < (NSInteger)lines.count; ++i) {
            SGKaraokeLine *copy = [lines[i] copy];
            if (i < index) copy.translation = @"Translated verse";
            [batch addObject:copy];
        }
        UIView *before = row(index);
        SGKaraokeKeepLines(SGHarnessPlayingTrack, batch);
        autoTick(view);
        BOOL replaced = extrasWait(^BOOL { return row(index) && row(index) != before; });
        CGFloat after = CGRectGetMinY([row(index) convertRect:row(index).bounds toView:view]);
        check(replaced && fabs(after - y) < 1,
              [NSString stringWithFormat:@"translation batch preserves verse %ld at viewport Y %.1f (now %.1f)", (long)index, y, after]);
    }

    readerCornerGestures(view);
    readerInterruptedError(view);
    googleHolds();
    sg_held = nil;
    BOOL asked = tap(item(view, @"Translate with Google")) && sg_held;
    check(asked, @"manual translation of A is pending");
    if (asked) {
        SGHarnessPlayingTrack = @"reader-b";
        SGKaraokeKeepLines(SGHarnessPlayingTrack, @[sungLine(0, @"another")]);
        autoTick(view);
        sg_alert = nil;
        NSMutableArray *partial = [NSMutableArray array];
        for (NSUInteger i = 0; i < lines.count; ++i) [partial addObject:i == lines.count-1 ? @"saved" : @""];
        sg_held(partial, @"partial failure");
        check(!sg_alert && [SGHarnessSavedTranslations[@"reader-a|en"][@"verse63"] isEqual:@"saved"],
              @"A's late partial error saves its result without alerting over B");
        sg_held = nil;
    }
    [view removeFromSuperview];
}
