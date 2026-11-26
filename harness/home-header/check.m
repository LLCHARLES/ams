// The Home header's pill and avatar, and the page's tint behind them, through a turn of the iPad and a resize of its
// window. HomeHeader.x's Logos output is included and run from a page laid out in Spotify's order (trees/clean/home/10.txt):
// the page's controller passes first (FunkisViewController's viewDidLayoutSubviews, where HomeHeader.x places the row),
// then the header's element sizes the header, then the header sizes its stack, which holds the avatar and the pills the
// redesign hides. The page view (HomePageView, which holds the feed and the tint) is the view of the feed's controller
// (EvoLoadableResourceViewController, whose pass lays the tint out) and is sized by its container after the page's pass,
// as on the device (still 1016pt wide in that pass after a turn to 1360); at launch the feed can arrive after the page's
// last pass, and Spotify can replace it with another. Every place is measured once layout has settled, with nothing
// after it, as on a device that has stopped turning.
#import <UIKit/UIKit.h>
#import "harness-fail.h"
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Home.h"
#include "HomeHeader.gen.m"

static NSUInteger sg_checks;

static void waitFor(NSString *stage, BOOL (^ready)(void)) {
    CFTimeInterval deadline = CACurrentMediaTime() + 30;
    while (!ready()) {
        if (CACurrentMediaTime() >= deadline) HARNESS_FAIL(@"timed out waiting for %@", stage);
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.05, true);
    }
}

// Spotify's header, as recorded: the element at {0, 62} 50pt tall, the stack at {0, 8} 34pt tall across it, the avatar
// 32pt wide at its leading margin of 16pt (right to left once the redesign turns the stack).
static const CGFloat kElementTop = 62, kElementHeight = 50, kStackTop = 8, kStackHeight = 34, kAvatarWidth = 32, kStackMargin = 16;
// The row as the redesign means it: the filter button 6pt before the avatar, the pill 6pt past the avatar's trailing edge,
// so 16 - 6 from the header's, and the large title ending one 8pt grid step before the pill.
static const CGFloat kExpectedGap = 6, kExpectedTrailingInset = 10, kExpectedTitleGap = 8;
// The avatar with friends listening beside it, wider than alone.
static const CGFloat kWideAvatarWidth = 56;

// The feed's controller, under the name HomeHeader.x hooks; its view is the page view.
@interface _TtC16Home_EvoPageImpl33EvoLoadableResourceViewController : UIViewController
@end
@implementation _TtC16Home_EvoPageImpl33EvoLoadableResourceViewController
- (void)loadView {
    self.view = [UIView new];
    self.view.accessibilityIdentifier = [@"HomePageView-" stringByAppendingString:NSUUID.UUID.UUIDString];
}
@end

// What holds the page view and gives it its size in its own pass.
@interface HarnessHomeContent : UIView
@property (nonatomic, strong) UIView *pageView;
@end
@implementation HarnessHomeContent
- (void)layoutSubviews {
    [super layoutSubviews];
    self.pageView.frame = self.bounds;
}
@end

@interface HarnessHomeHeaderView : UIView
@property (nonatomic, strong) UIStackView *stack;
@property BOOL recentersAfterStackPass;
@end
@implementation HarnessHomeHeaderView
- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect frame = CGRectMake(0, kStackTop, self.bounds.size.width, kStackHeight);
    if (!self.recentersAfterStackPass) {
        self.stack.frame = frame;
        return;
    }
    // The stack takes its new width about its old center and lays its avatar out, then the header moves it by its layer,
    // which lays nothing out (UIKit's setCenter: would mark the stack's arranged views for another pass).
    self.stack.bounds = (CGRect){self.stack.bounds.origin, frame.size};
    [self.stack layoutIfNeeded];
    self.stack.layer.position = CGPointMake(CGRectGetMidX(frame), CGRectGetMidY(frame));
}
@end

@interface HarnessHomeHeaderElement : UIView
@property (nonatomic, strong) HarnessHomeHeaderView *header;
@end
@implementation HarnessHomeHeaderElement
- (void)layoutSubviews {
    [super layoutSubviews];
    self.header.frame = self.bounds;
}
@end

@interface HarnessHomePage : UIViewController
@property (nonatomic, strong) HarnessHomeHeaderElement *element;
@property (nonatomic, strong) HarnessHomeContent *content;
@property (nonatomic, strong) UIViewController *feed;
@property (nonatomic, strong) UIView *avatar;
@property (nonatomic, strong) NSLayoutConstraint *avatarWidth;
@property CGRect avatarAtHeaderLayout;
@property NSUInteger pagePasses;
@end
@implementation HarnessHomePage
// The feed in its page view, in place of the one before it, with no pass of the page after.
- (void)arriveFeed {
    UIViewController *old = self.feed;
    [old willMoveToParentViewController:nil];
    [old.view removeFromSuperview];
    [old removeFromParentViewController];
    self.feed = [_TtC16Home_EvoPageImpl33EvoLoadableResourceViewController new];
    [self addChildViewController:self.feed];
    self.content.pageView = self.feed.view;
    [self.content addSubview:self.feed.view];
    [self.feed didMoveToParentViewController:self];
    [self.content setNeedsLayout];
}
- (void)loadView {
    self.view = [UIView new];
    self.content = [HarnessHomeContent new];
    [self.view addSubview:self.content];
    self.avatar = [UIView new];
    self.avatar.accessibilityIdentifier = @"Components.UI.SideDrawerButton";
    self.avatarWidth = [self.avatar.widthAnchor constraintEqualToConstant:kAvatarWidth];
    self.avatarWidth.active = YES;
    UIView *pills = [UIView new];
    [pills setContentHuggingPriority:UILayoutPriorityDefaultLow - 1 forAxis:UILayoutConstraintAxisHorizontal];
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[self.avatar, pills]];
    stack.layoutMarginsRelativeArrangement = YES;
    stack.directionalLayoutMargins = NSDirectionalEdgeInsetsMake(0, kStackMargin, 0, 0);
    HarnessHomeHeaderView *header = [HarnessHomeHeaderView new];
    header.stack = stack;
    [header addSubview:stack];
    self.element = [HarnessHomeHeaderElement new];
    self.element.header = header;
    [self.element addSubview:header];
    [self.view addSubview:self.element];
}
- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    self.content.frame = self.view.bounds;
    self.element.frame = CGRectMake(0, kElementTop, self.view.bounds.size.width, kElementHeight);
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    layoutHeader(self);
    self.avatarAtHeaderLayout = self.avatar.frame;
    self.pagePasses++;
}
@end

static UIViewController *host(void) {
    return [(id)UIApplication.sharedApplication.delegate window].rootViewController;
}

// Wait for the fixture's size to reach the render tree, not for the mod's
// filter/pill/tint to match expectations. Never induce a second page pass.
static void waitForSize(HarnessHomePage *page, CGSize size) {
    waitFor([NSString stringWithFormat:@"header and feed to display at %@", NSStringFromCGSize(size)], ^BOOL {
        for (UIView *view in @[page.element.header.stack, page.content.pageView ?: page.content]) {
            CALayer *display = view.layer.presentationLayer;
            if (!display || CGRectGetWidth(display.bounds) != size.width) return NO;
        }
        return YES;
    });
}

static NSString *rowError(HarnessHomePage *page);

// A page opened at this size: Home as Spotify shows it when the app launches in that orientation or window, its feed
// there from the start or arriving after the page's passes (arriveFeed).
static HarnessHomePage *openPage(CGSize size, BOOL feedFirst) {
    HarnessHomePage *page = [HarnessHomePage new];
    [page loadViewIfNeeded];
    if (feedFirst) [page arriveFeed];
    [host() addChildViewController:page];
    page.view.frame = (CGRect){CGPointZero, size};
    [host().view addSubview:page.view];
    [page didMoveToParentViewController:host()];
    [page.view layoutIfNeeded];
    waitForSize(page, size);
    // A header first discovered at zero size schedules its own first layout.
    // Let that launch finish before starting any turns. Resizes below never
    // wait for the pill's position, or request another pass to correct it.
    waitFor(@"the newly opened header to place its row", ^BOOL { return rowError(page) == nil; });
    return page;
}

static void closePage(HarnessHomePage *page) {
    [page willMoveToParentViewController:nil];
    [page.view removeFromSuperview];
    [page removeFromParentViewController];
}

// Each page goes with its pool and the run loop's turn after it, so the next page's tint is its own (HomeHeader.x
// keeps the last one weakly).
static void withPage(void (^check)(void)) {
    @autoreleasepool { check(); }
    waitFor(@"the closed page to release its tint", ^BOOL { return !sg_tintView; });
}

// The page given its new size in one pass, as a turn or a resize does, and left to settle.
static void resize(HarnessHomePage *page, CGSize size) {
    page.view.frame = (CGRect){CGPointZero, size};
    [page.view layoutIfNeeded];
    waitForSize(page, size);
}

static CGRect inPage(UIView *view, HarnessHomePage *page) {
    return [view convertRect:view.bounds toView:page.view];
}

// The filter button 6pt before the avatar, the pill 10pt from the page's trailing edge and level with the avatar, the
// title ending 8pt before the pill.
static NSString *rowError(HarnessHomePage *page) {
    UIView *header = page.element.header;
    SGRHomePillButtons *buttons = objc_getAssociatedObject(header, &kButtonsKey);
    UIView *glass = objc_getAssociatedObject(header, &kGlassKey);
    UILabel *title = objc_getAssociatedObject(header, &kTitleKey);
    if (!buttons || !glass || !title) return [NSString stringWithFormat:@"row not placed (buttons %@, pill %@, title %@)", buttons, glass, title];
    CGRect filter = inPage(buttons.filter, page), avatar = inPage(page.avatar, page), pill = inPage(glass, page), text = inPage(title, page);
    CGFloat gap = CGRectGetMinX(avatar) - CGRectGetMaxX(filter);
    CGFloat inset = CGRectGetWidth(page.view.bounds) - CGRectGetMaxX(pill);
    CGFloat titleGap = CGRectGetMinX(pill) - CGRectGetMaxX(text);
    if (fabs(gap - kExpectedGap) > 0.5 || fabs(inset - kExpectedTrailingInset) > 0.5 || fabs(CGRectGetMidY(pill) - CGRectGetMidY(avatar)) > 0.5 ||
        fabs(titleGap - kExpectedTitleGap) > 0.5) {
        return [NSString stringWithFormat:@"filter %@, avatar %@, pill %@, title %@ (gap %.1f, trailing inset %.1f, title gap %.1f); avatar in stack at last page pass %@, now %@",
                NSStringFromCGRect(filter), NSStringFromCGRect(avatar), NSStringFromCGRect(pill), NSStringFromCGRect(text), gap, inset, titleGap,
                NSStringFromCGRect(page.avatarAtHeaderLayout), NSStringFromCGRect(page.avatar.frame)];
    }
    return nil;
}

static void checkRow(HarnessHomePage *page, NSString *when) {
    NSString *error = rowError(page);
    if (error) HARNESS_FAIL(@"%@: %@", when, error);
    sg_checks++;
}

// One tint on the page, at the back of its page view, from its leading edge across its whole width.
static void checkTint(HarnessHomePage *page, NSString *when) {
    UIView *pageView = page.content.pageView;
    UIView *tint = objc_getAssociatedObject(pageView, &kTintKey);
    __block NSUInteger tints = 0;
    SGForEachView(page.view, ^(UIView *view) { if ([view isKindOfClass:SGRHomeTintView.class]) tints++; });
    CGFloat width = CGRectGetWidth(page.view.bounds);
    CGRect frame = tint.frame;
    if (tints != 1 || tint.superview != pageView || !CGPointEqualToPoint(frame.origin, CGPointZero) || frame.size.width != width || frame.size.height <= 0) {
        HARNESS_FAIL(@"%@: tint %@ in a page %@ wide, not from its top leading corner across %@ (%lu tints on the page)", when,
                     tint ? NSStringFromCGRect(frame) : @"missing", @(CGRectGetWidth(pageView.bounds)), @(width), (unsigned long)tints);
    }
    sg_checks++;
}

static void checkPage(HarnessHomePage *page, NSString *when) {
    checkRow(page, when);
    checkTint(page, when);
}

// The reporter's iPad (11-inch, 2nd generation) turned both ways and back again, and windows of Stage Manager's sizes.
static const CGSize kPortrait = {834, 1194}, kLandscape = {1194, 834};
static const CGSize kWindows[] = {{694, 834}, {1194, 834}, {507, 834}, {980, 700}, {834, 1194}};

static void checkTurns(CGSize launch, CGSize turned) {
    HarnessHomePage *page = openPage(launch, YES);
    checkPage(page, [NSString stringWithFormat:@"opened at %@", NSStringFromCGSize(launch)]);
    for (NSUInteger turn = 1; turn <= 4; turn++) {
        CGSize size = turn % 2 ? turned : launch;
        resize(page, size);
        checkPage(page, [NSString stringWithFormat:@"opened at %@, turn %lu to %@", NSStringFromCGSize(launch), (unsigned long)turn,
                        NSStringFromCGSize(size)]);
    }
    closePage(page);
}

static void checkWindows(void) {
    HarnessHomePage *page = openPage(kPortrait, YES);
    for (NSUInteger i = 0; i < sizeof kWindows / sizeof kWindows[0]; i++) {
        resize(page, kWindows[i]);
        checkPage(page, [NSString stringWithFormat:@"window resized to %@", NSStringFromCGSize(kWindows[i])]);
    }
    closePage(page);
}

// The feed arriving after the page's last pass, as it does at launch on an iPad, then replaced by another page view, then
// the page turned: the tint comes with each page view, without a pass of the page.
static void checkFeedLate(CGSize launch, CGSize turned) {
    HarnessHomePage *page = openPage(launch, NO);
    [page arriveFeed];
    waitForSize(page, launch);
    checkPage(page, [NSString stringWithFormat:@"opened at %@, the feed after", NSStringFromCGSize(launch)]);
    [page arriveFeed];
    waitForSize(page, launch);
    checkPage(page, [NSString stringWithFormat:@"opened at %@, the page view replaced", NSStringFromCGSize(launch)]);
    resize(page, turned);
    checkPage(page, [NSString stringWithFormat:@"opened at %@, the feed after, turned to %@", NSStringFromCGSize(launch), NSStringFromCGSize(turned)]);
    closePage(page);
}

// Two Homes open at once: the first page's stack lays its avatar out again (friends listening widen it) right after the
// second page's pass, with no pass of its own page. Checked straight after the stack's pass, with no turn of the run loop
// in which a header's own retry (layoutHeaderOnceSized) could lay its page's row out again.
static void checkTwoPages(void) {
    HarnessHomePage *first = openPage(kPortrait, YES);
    HarnessHomePage *second = openPage(kLandscape, YES);
    NSUInteger passes = first.pagePasses, secondPasses = second.pagePasses;
    [second.view setNeedsLayout];
    [second.view layoutIfNeeded];
    if (second.pagePasses == secondPasses) HARNESS_FAIL(@"the second page did not lay out");
    first.avatarWidth.constant = kWideAvatarWidth;
    UIStackView *stack = first.element.header.stack;
    [stack setNeedsLayout];
    [stack layoutIfNeeded];
    if (first.pagePasses != passes) HARNESS_FAIL(@"the first page laid out again (%lu passes after %lu), so its stack's own pass is not what is checked",
                                                 (unsigned long)first.pagePasses, (unsigned long)passes);
    if (CGRectGetWidth(first.avatar.frame) != kWideAvatarWidth) HARNESS_FAIL(@"the first page's avatar not widened: %@", NSStringFromCGRect(first.avatar.frame));
    checkRow(first, @"the first of two pages, its avatar widened after the second page's pass");
    checkRow(second, @"the second of two pages, after the first one's avatar widened");
    closePage(second);
    closePage(first);
}

// A header that recenters its stack after the stack's own pass at the new width, which lays nothing out, through turns.
static void checkRecenter(CGSize launch, CGSize turned) {
    HarnessHomePage *page = openPage(launch, YES);
    page.element.header.recentersAfterStackPass = YES;
    for (NSUInteger turn = 1; turn <= 2; turn++) {
        CGSize size = turn % 2 ? turned : launch;
        resize(page, size);
        checkRow(page, [NSString stringWithFormat:@"opened at %@, the stack recentered after its pass, turn %lu to %@", NSStringFromCGSize(launch),
                        (unsigned long)turn, NSStringFromCGSize(size)]);
    }
    closePage(page);
}

static void run(void) {
    withPage(^{ checkTwoPages(); });
    withPage(^{ checkRecenter(kPortrait, kLandscape); });
    withPage(^{ checkRecenter(kLandscape, kPortrait); });
    withPage(^{ checkTurns(kPortrait, kLandscape); });
    withPage(^{ checkTurns(kLandscape, kPortrait); });
    withPage(^{ checkWindows(); });
    withPage(^{ checkFeedLate(kPortrait, kLandscape); });
    withPage(^{ checkFeedLate(kLandscape, kPortrait); });
    printf("[harness] home-header: %lu checks passed\n", (unsigned long)sg_checks);
    fflush(stdout);
    exit(0);
}

@interface HomeHeaderApp : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end
@implementation HomeHeaderApp
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    self.window = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, 390, 844)];
    self.window.rootViewController = [UIViewController new];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(sceneActivated:) name:UISceneDidActivateNotification object:nil];
    return YES;
}
- (void)sceneActivated:(NSNotification *)note {
    [NSNotificationCenter.defaultCenter removeObserver:self name:UISceneDidActivateNotification object:nil];
    // Outside the launch transaction and main queue: layout waits service the run loop.
    [NSTimer scheduledTimerWithTimeInterval:0 repeats:NO block:^(NSTimer *timer) { run(); }];
}
@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(HomeHeaderApp.class));
    }
}
