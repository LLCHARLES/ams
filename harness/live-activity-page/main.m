// Real page callbacks and conditional rows; preview cycling belongs to the activity, not this check.
#import <UIKit/UIKit.h>
#import "../harness-fail.h"
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Shared/LiveActivity/LiveActivity.h"
#import "Shared/LiveActivity/SGLiveActivityPreview.h"
#import "../timer-lifecycle.h"
#import "../reduce-motion-fixture.h"

extern BOOL HarnessActivityEnabled;

static void previewBackgroundChecks(UIWindow *window) {
    harnessMotion = allowMotion;
    SGHarnessBeginTimerCapture();
    SGLiveActivityPreview *preview = [SGLiveActivityPreview new];
    [window addSubview:preview];
    preview.running = YES;
    HARNESS_CHECK(SGHarnessLiveTimers() == 1);
    [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationWillResignActiveNotification object:nil];
    HARNESS_CHECK(SGHarnessLiveTimers() == 0);
    sg_testAppState = UIApplicationStateBackground;
    [preview reload];
    HARNESS_CHECK(SGHarnessLiveTimers() == 0);
    sg_testAppState = UIApplicationStateActive;
    [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationDidBecomeActiveNotification object:nil];
    HARNESS_CHECK(SGHarnessLiveTimers() == 1);
    [preview removeFromSuperview];
    HARNESS_CHECK(SGHarnessLiveTimers() == 0);
    [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationDidBecomeActiveNotification object:nil];
    HARNESS_CHECK(SGHarnessLiveTimers() == 0);
    preview.running = NO;
    SGHarnessEndTimerCapture();
    puts("PASS activity preview stops in background and off-window");
}

static SGModRow *row(SGModPage *page, NSString *title) {
    for (SGModSection *section in page.sections)
        for (SGModRow *item in section.rows)
            if ([item.title isEqualToString:title]) return item;
    HARNESS_FAIL(@"Missing row %@", title);
}

@interface AppDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation AppDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    if ([NSProcessInfo.processInfo.arguments containsObject:@"background-check"]) {
        self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
        self.window.rootViewController = [UIViewController new];
        [self.window makeKeyAndVisible];
        dispatch_async(dispatch_get_main_queue(), ^{
            previewBackgroundChecks(self.window);
            exit(0);
        });
        return YES;
    }
    NSUserDefaults *store = NSUserDefaults.standardUserDefaults;
    for (NSString *key in store.dictionaryRepresentation)
        if ([key hasPrefix:@"spotifyglass.liveActivity"]) [store removeObjectForKey:key];
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    SGModPage *page = (SGModPage *)SGLiveActivitySettingsPage();
    self.window.rootViewController = [[UINavigationController alloc] initWithRootViewController:page];
    [self.window makeKeyAndVisible];
    dispatch_async(dispatch_get_main_queue(), ^{
        [page loadViewIfNeeded];
        [page viewWillAppear:NO];
        // The install warning and enable switch are mutually exclusive. This
        // standalone harness has no bundled widget and exercises the warning path.
        HARNESS_CHECK(row(page, @"Missing from this install").visible());
        HARNESS_CHECK(!row(page, @"Live Activity").visible());
        HARNESS_CHECK([page.tableView numberOfRowsInSection:0] == 6);
        row(page, @"Live Activity").changed(YES);
        HARNESS_CHECK(HarnessActivityEnabled);
        row(page, @"Live Activity").changed(NO);
        HARNESS_CHECK(!HarnessActivityEnabled);
        row(page, @"Without lyrics").chosen(1);
        HARNESS_CHECK([row(page, @"Without lyrics").value() isEqualToString:@"Track"]);
        row(page, @"Alignment").chosen(0);
        HARNESS_CHECK([row(page, @"Alignment").value() isEqualToString:@"Left"]);
        row(page, @"Colors").chosen(2);
        HARNESS_CHECK([row(page, @"Colors").value() isEqualToString:@"Plain"]);

        UITableViewController *choices = (UITableViewController *)row(page, @"Shows").page();
        [choices loadViewIfNeeded];
        [choices tableView:choices.tableView didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:1 inSection:0]];
        [page viewWillAppear:NO];
        HARNESS_CHECK([row(page, @"Shows").value() isEqualToString:@"Queue"]);
        HARNESS_CHECK([page.tableView numberOfRowsInSection:0] == 2);
        HARNESS_CHECK([page.tableView numberOfRowsInSection:1] == 3);
        [choices tableView:choices.tableView didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:2 inSection:0]];
        [page viewWillAppear:NO];
        HARNESS_CHECK([row(page, @"Shows").value() isEqualToString:@"Control menu"]);
        HARNESS_CHECK([page.tableView numberOfRowsInSection:0] == 2);
        [choices tableView:choices.tableView didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];
        [page viewWillAppear:NO];
        HARNESS_CHECK([page.tableView numberOfRowsInSection:0] == 6);
        HARNESS_CHECK([row(page, @"Without lyrics").value() isEqualToString:@"Track"]);
        puts("PASS Live Activity callbacks and conditional rows");
        fflush(stdout);
        exit(0);
    });
    return YES;
}
@end

int main(int argc, char *argv[]) {
    @autoreleasepool { return UIApplicationMain(argc, argv, nil, NSStringFromClass(AppDelegate.class)); }
}
