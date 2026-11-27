// Settings/SGPageStyle.m's SGInsetForBars against a window with a large view tree: how often a layout walks the
// window, and whether the inset follows a bar that is resized, hidden, removed or added.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "Settings/SGPageStyle.h"
#import "harness-fail.h"

static NSUInteger walks;
static NSUInteger classScans;
static Class *countedClassList(unsigned int *count) {
    classScans++;
    return objc_copyClassList(count);
}
#define objc_copyClassList countedClassList
static dispatch_block_t retry;
#define dispatch_after(deadline, queue, block) (retry = [block copy])
#import "Settings/SGPageStyle.m"
#undef objc_copyClassList
#undef dispatch_after
#import "audit.inc"

@interface TransitionPresenter : UIViewController
@property BOOL transition;
@property UIViewController *presented;
@end
@implementation TransitionPresenter
- (BOOL)isBeingPresented { return self.transition; }
- (void)presentViewController:(UIViewController *)controller animated:(BOOL)animated completion:(dispatch_block_t)done {
    self.presented = controller;
}
@end

// SGForEachView reads the window's subviews once per walk, so counting that counts the walks.
@interface CountingWindow : UIWindow
@end

@implementation CountingWindow
- (NSArray<__kindof UIView *> *)subviews {
    walks++;
    return [super subviews];
}
@end

static Class barClass(const char *name) {
    Class cls = objc_getClass(name);
    if (cls) return cls;
    cls = objc_allocateClassPair(UIView.class, name, 0);
    objc_registerClassPair(cls);
    return cls;
}

static UIView *addBar(UIView *host, const char *className, CGRect frame) {
    UIView *bar = [[barClass(className) alloc] initWithFrame:frame];
    [host addSubview:bar];
    return bar;
}

static const char *kTabBar = "_TtC23NavigationUI_TabBarImpl10TabBarView";
static const char *kNowPlaying = "NowPlaying_BarPageImpl";

static UITableView *addTable(UIWindow *window) {
    UITableView *table = [[UITableView alloc] initWithFrame:CGRectMake(0, 0, 400, 800)];
    [window addSubview:table];
    return table;
}

static CGFloat inset(UITableView *table) {
    SGInsetForBars(table);
    return table.contentInset.bottom;
}

#define EXPECT_INSET(table, expected, what) do { \
    CGFloat got = inset(table); \
    if (got != (expected)) HARNESS_FAIL(@"%s: inset %g, expected %g", what, got, (CGFloat)(expected)); \
} while (0)

// The walks since the last time this was checked.
#define EXPECT_WALKS(expected, what) do { \
    NSUInteger since = walks; \
    walks = 0; \
    if (since != (expected)) HARNESS_FAIL(@"%s: %lu walks, expected %lu", what, (unsigned long)since, (unsigned long)(expected)); \
} while (0)

static void runChecks(void) {
    @autoreleasepool {
        CountingWindow *window = [[CountingWindow alloc] initWithFrame:CGRectMake(0, 0, 400, 800)];
        for (NSString *category in @[UIContentSizeCategoryLarge, UIContentSizeCategoryAccessibilityExtraLarge]) {
            UITraitCollection *traits = [UITraitCollection traitCollectionWithPreferredContentSizeCategory:category];
            [traits performAsCurrentTraitCollection:^{
                UILabel *body = label(@"Notes", UIFontTextStyleBody, UIFontWeightRegular, UIColor.whiteColor);
                CGFloat expected = [UIFont preferredFontForTextStyle:UIFontTextStyleBody compatibleWithTraitCollection:traits].pointSize;
                HARNESS_CHECK(body.font.pointSize == expected);
            }];
        }
        UIView *a = [UIView new], *b = [UIView new], *c = [UIView new];
        a.frame = c.frame = CGRectMake(50, 0, 20, 20);
        NSMutableArray *stacked = [@[a, b, c] mutableCopy];
        sortButtons(stacked);
        HARNESS_CHECK(([stacked isEqual:@[b, a, c]]));
        // Spotify's tree under the bars: thousands of views that a walk has to pass.
        UIView *content = [[UIView alloc] initWithFrame:window.bounds];
        [window addSubview:content];
        for (int i = 0; i < 300; i++) {
            UIView *group = [UIView new];
            [content addSubview:group];
            for (int j = 0; j < 20; j++) [group addSubview:[UIView new]];
        }
        UIView *bars = [[UIView alloc] initWithFrame:window.bounds];
        [window addSubview:bars];
        UITableView *table = addTable(window);
        HARNESS_CHECK(table.window == window);

        // The bar classes exist before any bar does, as Spotify's do.
        barClass(kTabBar);
        barClass(kNowPlaying);

        UIView *tabBar = addBar(bars, kTabBar, CGRectMake(0, 740, 400, 60));
        walks = 0;
        HARNESS_CHECK(SGHasClass(window, @"CountingWindow") && !walks);
        HARNESS_CHECK(SGHasClass(window, @"TabBarView"));
        HARNESS_CHECK(!SGHasClass(window, @"NeverInThisTree") && !SGHasClass(nil, @"UIView"));
        walks = 0;
        EXPECT_INSET(table, 60, "first layout");
        EXPECT_WALKS(1, "first layout");

        // Scrolling lays the table out on every frame.
        for (int i = 0; i < 500; i++) {
            table.contentOffset = CGPointMake(0, i);
            EXPECT_INSET(table, 60, "scroll");
        }
        EXPECT_WALKS(0, "500 layouts of an unchanged window");

        tabBar.frame = CGRectMake(0, 700, 400, 100);
        EXPECT_INSET(table, 100, "tab bar resized");
        tabBar.alpha = 0;
        EXPECT_INSET(table, 0, "tab bar transparent");
        tabBar.alpha = 1;
        tabBar.hidden = YES;
        EXPECT_INSET(table, 0, "tab bar hidden");
        tabBar.hidden = NO;
        EXPECT_INSET(table, 100, "tab bar shown");
        EXPECT_WALKS(0, "a bar resized, hidden and shown");

        // A bar attached mid-page, beside the one remembered, is measured by the next layout.
        UIView *playing = addBar(bars, kNowPlaying, CGRectMake(0, 640, 400, 60));
        EXPECT_INSET(table, 160, "bar attached mid-page");
        EXPECT_WALKS(1, "a bar attached mid-page");
        EXPECT_INSET(table, 160, "mid-page bar again");
        EXPECT_WALKS(0, "layouts after the attach");

        ReportLayout *report = [ReportLayout new];
        report.tableView.frame = table.frame;
        [window addSubview:report.tableView];
        [report viewDidLayoutSubviews];
        HARNESS_CHECK(report.tableView.contentInset.bottom == 160);
        [report.tableView removeFromSuperview];
        walks = 0;

        // A table of a new page finds both.
        NSUInteger scansBeforeNextPage = classScans;
        UITableView *next = addTable(window);
        EXPECT_INSET(next, 160, "next page");
        EXPECT_INSET(next, 160, "next page again");
        HARNESS_CHECK(classScans == scansBeforeNextPage);
        EXPECT_WALKS(0, "a second table");
        playing.frame = CGRectMake(0, 600, 400, 60);
        EXPECT_INSET(next, 200, "now playing bar moved");
        EXPECT_WALKS(0, "a bar moved");

        UIView *late = addBar(bars, "Late_NowPlaying_BarPageImpl", CGRectMake(0, 540, 400, 60));
        UITableView *latePage = addTable(window);
        EXPECT_INSET(latePage, 260, "bar class registered after first layout");
        EXPECT_WALKS(1, "newly discovered bar");
        [late removeFromSuperview];
        EXPECT_INSET(latePage, 200, "late bar removed");
        EXPECT_WALKS(1, "late bar removal");

        // A bar taken out of the window is not measured, by any table that had it.
        [playing removeFromSuperview];
        EXPECT_INSET(next, 100, "bar removed");
        EXPECT_INSET(table, 100, "bar removed, first page");
        EXPECT_WALKS(1, "a bar removed");
        EXPECT_INSET(next, 100, "after the removal");
        EXPECT_WALKS(0, "layouts after the removal");

        // A bar released while a table remembers it.
        __weak UIView *weakTemporary;
        UITableView *third = addTable(window);
        @autoreleasepool {
            UIView *temporary = addBar(bars, kNowPlaying, CGRectMake(0, 600, 400, 60));
            weakTemporary = temporary;
            EXPECT_INSET(third, 200, "temporary bar");
            EXPECT_WALKS(1, "a third table");
            [temporary removeFromSuperview];
        }
        HARNESS_CHECK(weakTemporary == nil);
        EXPECT_INSET(third, 100, "temporary bar released");
        EXPECT_WALKS(1, "a bar released");
        EXPECT_INSET(third, 100, "after the release");
        EXPECT_WALKS(0, "layouts after the release");

        CountingWindow *other = [[CountingWindow alloc] initWithFrame:CGRectMake(0, 0, 400, 800)];
        addBar(other, kTabBar, CGRectMake(0, 720, 400, 80));
        walks = 0;

        // No bar at all: layouts walk nothing more, and a bar attached later is found.
        [tabBar removeFromSuperview];
        EXPECT_INSET(next, 0, "no bars");
        EXPECT_WALKS(1, "the last bar removed");
        EXPECT_INSET(next, 0, "no bars again");
        EXPECT_WALKS(0, "layouts with no bar");
        addBar(bars, kNowPlaying, CGRectMake(0, 700, 400, 100));
        EXPECT_INSET(next, 100, "bar attached after none");
        EXPECT_WALKS(1, "a bar attached after none");

        // A table moved to another window measures that window's bars, though no bar came or went since.
        [other addSubview:next];
        walks = 0;
        EXPECT_INSET(next, 80, "table in another window");
        EXPECT_WALKS(1, "a table in another window");

        // A table in no window insets nothing.
        UITableView *loose = [[UITableView alloc] initWithFrame:CGRectMake(0, 0, 400, 800)];
        EXPECT_INSET(loose, 0, "no window");
    }
    TransitionPresenter *top = (id)SGTopController();
    SGPresentInformation(top, @"Information", @"Details");
    HARNESS_CHECK(top.presented.overrideUserInterfaceStyle == UIUserInterfaceStyleDark);
    top.presented = nil;
    UIView *anchor = [UIView new];
    [top.view addSubview:anchor];
    top.transition = YES;
    SGPresentPopover([UIViewController new], anchor);
    dispatch_async(dispatch_get_main_queue(), ^{
        HARNESS_CHECK(retry != nil && !top.presented);
        [anchor removeFromSuperview];
        top.transition = NO;
        retry();
        retry = nil;
        HARNESS_CHECK(!top.presented);
        fprintf(stderr, "[settings-bars] ok\n");
        exit(0);
    });
}

@interface CheckApp : UIResponder <UIApplicationDelegate>
@end

@interface SGRHarnessScene : UIResponder <UIWindowSceneDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation SGRHarnessScene
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    self.window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    self.window.rootViewController = [TransitionPresenter new];
    [self.window makeKeyAndVisible];
}
- (void)sceneDidBecomeActive:(UIScene *)scene {
    static BOOL started;
    if (started) return;
    started = YES;
    dispatch_async(dispatch_get_main_queue(), ^{ runChecks(); });
}
@end

@implementation CheckApp
@end

int main(int argc, char **argv) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 120 * NSEC_PER_SEC), dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
        HARNESS_FAIL(@"timed out waiting for scene activation or inset checks");
    });
    @autoreleasepool { return UIApplicationMain(argc, argv, nil, NSStringFromClass(CheckApp.class)); }
}
