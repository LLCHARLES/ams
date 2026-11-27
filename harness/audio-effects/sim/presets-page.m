// The Presets page's Save dialog (Shared/AudioEffects/AudioEffectsPresetsPage.m, askForName) in the simulator:
// a dialog presented and cancelled, and one saved, must both be freed with the page once it is popped. The page
// is the real SGDSPPresetList behind the real SGPage; the dialog is opened through the row's own method.
//
//     THEOS=$HOME/theos ./build-presets-page.sh
//     xcrun simctl install <udid> build/presets-page/PresetsPageHarness.app
//     xcrun simctl launch --console-pty <udid> com.vojta.presetspageharness
//
// Failures are logged and exit nonzero; "all passed" exits 0.
#import <UIKit/UIKit.h>
#import "Shared/AudioEffects/AudioEffects.h"
#import "Shared/AudioEffects/AudioEffectsPage.h"
#import "Shared/AudioEffects/AudioEffectsPresets.h"
#import "../../harness-wait.h"

@interface UIViewController (PresetsPageHarness)
- (void)askForName;
@end

@interface PresetsPageHarness : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@property (nonatomic, strong) UINavigationController *nav;
@end

@implementation PresetsPageHarness

// Pushes a fresh page and opens the Save dialog on it; after the dialog is up, either cancels it or types `name`
// and taps Save, pops the page, and calls `done` once the run loop has had time to free them. Only weak
// references outlive each step, so what is still alive at the end is held by the objects themselves.
- (void)round:(NSString *)name done:(void (^)(BOOL pageFreed, BOOL alertFreed))done {
    __weak UIViewController *weakPage = nil;
    __block __weak UIAlertController *weakAlert = nil;
    @autoreleasepool {
        UIViewController *presets = SGDSPPresetsPage();
        weakPage = presets;
        [self.nav pushViewController:presets animated:NO];
        [presets loadViewIfNeeded];
        [presets askForName];
    }
    HarnessWhen(@"attached Save dialog", ^BOOL { return weakPage.presentedViewController.view.window != nil; }, ^{
        UIAlertController *dialog = (UIAlertController *)weakPage.presentedViewController;
        HARNESS_CHECK([dialog isKindOfClass:UIAlertController.class]);
        HARNESS_CHECK(dialog.view.window != nil);
        if (name) {
            dialog.textFields.firstObject.text = name;
            void (^handler)(UIAlertAction *) = [dialog.actions.lastObject valueForKey:@"handler"];
            HARNESS_CHECK(handler != nil);
            handler(dialog.actions.lastObject);
        }
        [weakPage dismissViewControllerAnimated:NO completion:^{
            [self.nav popViewControllerAnimated:NO];
            HarnessWhen(@"release of popped presets page and Save dialog", ^BOOL {
                return !weakPage && !weakAlert;
            }, ^{ done(weakPage == nil, weakAlert == nil); });
        }];
        weakAlert = dialog;
    });
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    self.nav = [[UINavigationController alloc] initWithRootViewController:[UIViewController new]];
    self.window.rootViewController = self.nav;
    [self.window makeKeyAndVisible];
    NSUserDefaults *store = NSUserDefaults.standardUserDefaults;
    for (NSString *key in store.dictionaryRepresentation.allKeys) {
        if ([key hasPrefix:@"spotifyglass.dsp"]) [store removeObjectForKey:key];
    }
    HarnessWhen(@"visible presets navigation controller", ^BOOL { return self.nav.view.window != nil; }, ^{ [self run]; });
    return YES;
}

- (void)run {
    [self round:nil done:^(BOOL pageFreed, BOOL alertFreed) {
        HARNESS_CHECK(alertFreed);
        HARNESS_CHECK(pageFreed);
        NSLog(@"[harness] ok   a cancelled Save dialog and its popped page are freed");
        [self round:@"Harness name" done:^(BOOL pageFreed, BOOL alertFreed) {
            HARNESS_CHECK([SGDSPUserPresetNames() containsObject:@"Harness name"]);
            NSLog(@"[harness] ok   Save still stores the typed name");
            HARNESS_CHECK(alertFreed);
            HARNESS_CHECK(pageFreed);
            NSLog(@"[harness] ok   a saved dialog and its popped page are freed");
            NSLog(@"[harness] all passed");
            exit(0);
        }];
    }];
}

@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(PresetsPageHarness.class));
    }
}
