// A podcast's speed button (PlayerSpeedLabel.m) in a controls row shaped as Spotify 9.2.0's (sim920 treed3, 2026-11-20):
// a 378 pt row 12 pt in, equal spacing, the 48 pt speed slot, the 56 pt 15 s skips, the 64 pt play and the 48 pt timer;
// in the speed button a 40 x 36 view holding a stack of the value and "×", centered on it, which Spotify turns to a
// column when the value is long and sets in a smaller size (1배속 in 21 pt, 1.25배속 in 15 pt). Every speed from 0.5 to
// 3.5, as Spotify writes it in Korean, at the default text size and a larger one, left to right and right to left, on
// a phone's row and on the narrower row of an iPad's side panel: the words on one line, all of them inside the button,
// where a tap on any of them reaches it and its accessibility frame holds them, short of the 15 s skip's slot, at
// Spotify's size where they fit.
#import <UIKit/UIKit.h>
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Redesigned/Player/Player.h"
#import "../harness-fail.h"

static int checked, failed;

BOOL SGRedesignedUI(void) { return YES; }
BOOL SGFlag(NSString *key, BOOL fallback) { return fallback; }
NSInteger SGInt(NSString *key, NSInteger fallback) { return fallback; }
void SGPresentDark(UIViewController *controller) {}
UIColor *SGRAccentColor(void) { return nil; }

static void check(BOOL ok, NSString *what) {
    checked++;
    if (!ok) failed++;
    printf("%s %s\n", ok ? "PASS" : "FAIL", what.UTF8String);
    fflush(stdout);
}

typedef struct {
    UIView *host, *skip, *button;
    UIStackView *row, *labels;
    UILabel *value, *times;
} Controls;

static UIView *slot(CGFloat width) {
    UIView *view = [UIView new];
    [view.widthAnchor constraintEqualToConstant:width].active = YES;
    [view.heightAnchor constraintEqualToConstant:width].active = YES;
    return view;
}

// Spotify's arrangement for `text`: a line when it is short, a column when long, in the size it picks for each.
static void spotifySets(Controls c, NSString *text, CGFloat larger) {
    BOOL longValue = text.length > 3;
    UIFont *font = [UIFont systemFontOfSize:(longValue ? 15 : 21) * larger weight:UIFontWeightBold];
    c.value.text = text;
    c.value.font = c.times.font = font;
    c.labels.axis = longValue ? UILayoutConstraintAxisVertical : UILayoutConstraintAxisHorizontal;
    c.labels.spacing = longValue ? -4 : -1;
    [c.labels setNeedsLayout];
    [c.host layoutIfNeeded];
}

static Controls build(UIWindow *window, CGFloat hostWidth, BOOL rtl) {
    Controls c = {0};
    c.host = [[UIView alloc] initWithFrame:CGRectMake(0, 300, hostWidth, 96)];
    c.row = [[UIStackView alloc] initWithFrame:CGRectMake(12, 16, hostWidth - 24, 64)];
    c.row.distribution = UIStackViewDistributionEqualSpacing;
    c.row.alignment = UIStackViewAlignmentCenter;
    UIView *speedSlot = slot(48);
    c.skip = slot(56);
    for (UIView *view in @[speedSlot, c.skip, slot(64), slot(56), slot(48)]) [c.row addArrangedSubview:view];
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    button.accessibilityIdentifier = @"Components.UI.SpeedControlButtonNowPlaying";
    button.frame = CGRectMake(0, 0, 48, 48);
    button.accessibilityLabel = @"속도 제어";
    [speedSlot addSubview:button];
    c.button = button;
    UIView *speedLabel = [[UIView alloc] initWithFrame:CGRectMake(4, 6, 40, 36)];
    [button addSubview:speedLabel];
    c.value = [UILabel new];
    c.times = [UILabel new];
    c.times.text = @"×";
    c.labels = [[UIStackView alloc] initWithArrangedSubviews:@[c.value, c.times]];
    c.labels.alignment = UIStackViewAlignmentCenter;
    c.labels.translatesAutoresizingMaskIntoConstraints = NO;
    [speedLabel addSubview:c.labels];
    [NSLayoutConstraint activateConstraints:@[
        [c.labels.centerXAnchor constraintEqualToAnchor:speedLabel.centerXAnchor],
        [c.labels.centerYAnchor constraintEqualToAnchor:speedLabel.centerYAnchor],
    ]];
    [c.host addSubview:c.row];
    [window addSubview:c.host];
    if (rtl) {
        NSMutableArray<UIView *> *views = [NSMutableArray arrayWithObject:c.host];
        for (NSUInteger i = 0; i < views.count; i++) {
            views[i].semanticContentAttribute = UISemanticContentAttributeForceRightToLeft;
            [views addObjectsFromArray:views[i].subviews];
        }
    }
    spotifySets(c, @"1배속", 1);
    SGRPlayerFitSpeedLabel(c.host);
    return c;
}

static CGRect inRow(Controls c, UIView *view) {
    return [view.superview convertRect:view.frame toView:c.row];
}

// Whether a tap at `point` in the row reaches the speed button: the view hit is the button or one inside it.
static BOOL tapsButton(Controls c, CGPoint point) {
    UIWindow *window = c.host.window;
    UIView *hit = [window hitTest:[c.row convertPoint:point toView:window] withEvent:nil];
    return [hit isDescendantOfView:c.button];
}

static void run(UIWindow *window) {
    // Keep the labels through a button replacement. Their layout callback must neither
    // hold the old button alive nor keep fitting to it once the labels have moved.
    UIStackView *reused;
    __weak UIView *old;
    @autoreleasepool {
        Controls c = build(window, 402, NO);
        old = c.button;
        reused = c.labels;
        [reused removeFromSuperview];
        [c.host removeFromSuperview];
    }
    check(!old, @"reused labels release the old button");
    UIView *replacement = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 48, 48)];
    replacement.accessibilityIdentifier = @"Components.UI.SpeedControlButtonNowPlaying";
    UIView *host = [UIView new];
    [host addSubview:replacement];
    [replacement addSubview:reused];
    SGRPlayerFitSpeedLabel(host);
    reused.axis = UILayoutConstraintAxisVertical;
    [reused layoutSubviews];
    check(reused.axis == UILayoutConstraintAxisHorizontal, @"reused labels still refit after a layout");
    NSArray<NSString *> *speeds = @[@"0.5", @"0.75", @"1", @"1.25", @"1.5", @"1.75", @"2", @"2.5", @"3", @"3.5"];
    for (NSNumber *hostWidth in @[@402, @375]) {
        for (int direction = 0; direction < 2; direction++) {
            BOOL rtl = direction == 1;
            Controls c = build(window, hostWidth.doubleValue, rtl);
            for (NSNumber *larger in @[@1, @1.35]) {
                for (NSString *speed in speeds) {
                    NSString *text = [speed stringByAppendingString:@"배속"];
                    spotifySets(c, text, larger.doubleValue);
                    [window layoutIfNeeded];
                    CGRect value = inRow(c, c.value), times = inRow(c, c.times), stack = inRow(c, c.labels), skip = inRow(c, c.skip);
                    CGRect button = inRow(c, c.button);
                    // "×" follows the value on its line, as near as the stack's spacing (Spotify's -1 on a line) puts it.
                    CGFloat overlap = MAX(0, -c.labels.spacing) * c.labels.transform.a + 0.5;
                    BOOL line = fabs(CGRectGetMidY(value) - CGRectGetMidY(times)) < 0.5
                        && (rtl ? CGRectGetMaxX(times) <= CGRectGetMinX(value) + overlap : CGRectGetMinX(times) >= CGRectGetMaxX(value) - overlap);
                    BOOL inside = CGRectContainsRect(CGRectInset(button, -0.5, -0.5), stack);
                    BOOL clear = rtl ? CGRectGetMinX(stack) >= CGRectGetMaxX(skip) - 0.5 : CGRectGetMaxX(stack) <= CGRectGetMinX(skip) + 0.5;
                    // Taps on the two words and on the line's two ends, half a point in, reach the button.
                    BOOL taps = YES;
                    for (NSValue *point in @[[NSValue valueWithCGPoint:CGPointMake(CGRectGetMidX(value), CGRectGetMidY(value))],
                                             [NSValue valueWithCGPoint:CGPointMake(CGRectGetMidX(times), CGRectGetMidY(times))],
                                             [NSValue valueWithCGPoint:CGPointMake(CGRectGetMinX(stack) + 0.5, CGRectGetMidY(stack))],
                                             [NSValue valueWithCGPoint:CGPointMake(CGRectGetMaxX(stack) - 0.5, CGRectGetMidY(stack))]]) {
                        taps &= tapsButton(c, point.CGPointValue);
                    }
                    CGRect onScreen = [c.labels convertRect:c.labels.bounds toCoordinateSpace:window.screen.coordinateSpace];
                    BOOL framed = CGRectContainsRect(CGRectInset(c.button.accessibilityFrame, -0.5, -0.5), onScreen);
                    // The room the line has about its middle in the button, Spotify's size kept where the line fits it.
                    CGFloat line_ = c.labels.bounds.size.width, middle = CGRectGetMidX(stack) - CGRectGetMinX(button);
                    CGFloat room = 2 * MIN(middle, button.size.width - middle);
                    BOOL size = line_ <= room ? c.labels.transform.a == 1 : fabs(stack.size.width - room) < 0.5;
                    NSString *where = [NSString stringWithFormat:@"%@ pt host, %@, text x%@", hostWidth, rtl ? @"right to left" : @"left to right", larger];
                    check(line && inside && clear && size && taps && framed,
                          [NSString stringWithFormat:@"%@× (%@) on one line inside the button, every word tapped and framed for VoiceOver "
                           "as the button, short of the 15 s skip, Spotify's size where it fits (value %@, × %@, stack %@, button %@, "
                           "skip at %.1f, scale %.2f, taps %d, framed %d)", text, where, NSStringFromCGRect(value), NSStringFromCGRect(times),
                           NSStringFromCGRect(stack), NSStringFromCGRect(button), rtl ? CGRectGetMaxX(skip) : CGRectGetMinX(skip),
                           c.labels.transform.a, taps, framed]);
                }
            }
            [c.host removeFromSuperview];
        }
    }
    printf("speed label checks: %d of %d right -- %s\n", checked - failed, checked, failed ? "FAIL" : "PASS");
    fflush(stdout);
    exit(failed ? 1 : 0);
}

@interface SpeedLabelApp : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end
@implementation SpeedLabelApp
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController = [UIViewController new];
    [self.window makeKeyAndVisible];
    [NSTimer scheduledTimerWithTimeInterval:0 repeats:NO block:^(NSTimer *timer) { run(self.window); }];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 45 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        HARNESS_FAIL(@"speed label checks did not finish");
    });
    return YES;
}
@end
int main(int argc, char **argv) {
    @autoreleasepool { return UIApplicationMain(argc, argv, nil, NSStringFromClass(SpeedLabelApp.class)); }
}
