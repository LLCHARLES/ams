// The welcome tour and the What's new sheet on the simulator, over a plain screen standing in for Home:
// Tour.m and WhatsNew.m as the tweak builds them, the notes being a CHANGELOG.md section build.sh wrote.
//
//   tour        the tour, as on a first launch (the default)
//   old         the tour as below iOS 26: the redesign card untested, Legacy picked
//   whatsnew    the What's new sheet
//   pick        taps the other look's card once it appears, to see the note change
//   environment loads a stand-in EeveeSpotify.dylib and runs the install check (the harness's own
//               version, 1.0, is not Spotify's either), whose alert follows about 5 s in
#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import "App/Onboarding/Onboarding.h"
#import "Shared/Lyrics/Lyrics.h"
#import "Core/SGPrefs.h"
#import "Core/SGLocalize.h"
#import "Settings/SGModPage.h"
#import "Shared/SponsorBlock/SponsorBlock.h"
#import <objc/runtime.h>
#import "../harness-wait.h"

static BOOL sg_old;
static NSDictionary *sg_installInfo;
void CheckSponsorBlockScreens(UIWindow *window);
void CheckKeptCleanup(UIWindow *window);

@interface NSBundle (SGInstallFixture)
- (id)sg_installObjectForInfoDictionaryKey:(NSString *)key;
@end
@implementation NSBundle (SGInstallFixture)
- (id)sg_installObjectForInfoDictionaryKey:(NSString *)key {
    return sg_installInfo ? sg_installInfo[key] : [self sg_installObjectForInfoDictionaryKey:key];
}
@end

// Core/SGUIMode.m, with the OS the tour believes it runs on taken from the arguments.
BOOL SGRedesignAvailable(void) { return !sg_old; }
BOOL SGRedesignFellBack(void) { return NO; }
BOOL SGRedesignedUIStored(void) { return NO; }
BOOL SGRedesignedUI(void) { return NO; }
BOOL SGNativeUI(void) { return YES; }

// App/Pages.m and App/About/Signing.m, which bring the rest of the tweak with them.
void SGSetRedesignedUI(BOOL on) { NSLog(@"harness: redesign %@", on ? @"on" : @"off"); }
NSString *SGRedesignUntestedWarning(void) {
    return [NSString stringWithFormat:@"The redesign is built on iOS 26's Liquid Glass. iOS %@ draws a blur in its place, and nobody has tested the redesign there: pages can be laid out wrongly, and Spotify can freeze as it starts. If Spotify does not start with it, the next launch goes back to Legacy.", @"17.5"];
}
void SGShowSigningFixIfPending(void) {}
// The environment check's install questions are answered from this app's fixture below.
#import "Shared/LiveActivity/LiveActivity.h"
#import "Shared/Haptics/Haptics.h"
// Shared/Lyrics/KaraokeSource.x's look for EeveeSpotify, by the loaded image's name alone.
BOOL SGEeveeSpotifyInjected(void) {
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const char *image = _dyld_get_image_name(i);
        if (image && [@(image).lastPathComponent caseInsensitiveCompare:@"EeveeSpotify.dylib"] == NSOrderedSame) return YES;
    }
    return NO;
}
// LiveActivitySettings.m and HapticsSettings.m: what the install's Info.plist says.
BOOL SGLiveActivityAllowedByInstall(void) {
    return !sg_installInfo && [[NSBundle.mainBundle objectForInfoDictionaryKey:@"NSSupportsLiveActivities"] boolValue];
}
BOOL SGMusicHapticsListedByInstall(void) { return [[NSBundle.mainBundle objectForInfoDictionaryKey:@"MusicHapticsSupported"] boolValue]; }

// A released IPA stripped of extensions still has its plist changes; a hand-injected .deb does not.
static int checkInstallWarnings(void) {
    Method original = class_getInstanceMethod(NSBundle.class, @selector(objectForInfoDictionaryKey:));
    Method fixture = class_getInstanceMethod(NSBundle.class, @selector(sg_installObjectForInfoDictionaryKey:));
    method_exchangeImplementations(original, fixture);
    NSArray<NSDictionary *> *installs = @[
        @{@"CFBundleShortVersionString": @"9.1.90", @"NSSupportsLiveActivities": @YES, @"MusicHapticsSupported": @YES},
        @{@"CFBundleShortVersionString": @"9.1.90"}
    ];
    NSArray<NSNumber *> *expectedWarnings = @[@NO, @YES];
    int result = 0;
    for (NSUInteger i = 0; i < installs.count; i++) {
        sg_installInfo = installs[i];
        NSArray *titles = [SGEnvironmentWarningRows() valueForKey:@"title"];
        BOOL warned = [titles containsObject:SGL(@"settings.environment.without_app_changes.title", @"Installed without the app changes")];
        if (warned != expectedWarnings[i].boolValue) {
            NSLog(@"FAIL: %@ must %@show the app-changes warning; actual rows %@",
                  i == 0 ? @"IPA with extension removed" : @"Hand-injected .deb", i == 0 ? @"not " : @"", titles);
            result = 1;
            break;
        }
    }
    for (NSString *version in @[@"9.1.90", @"9.2.0", @"9.2.2", @"9.1.78", @"9.1.88", @"1.0"]) {
        sg_installInfo = @{@"CFBundleShortVersionString": version, @"NSSupportsLiveActivities": @YES, @"MusicHapticsSupported": @YES};
        BOOL supported = [@[@"9.1.90", @"9.2.0", @"9.2.2"] containsObject:version];
        NSArray *expected = supported ? @[] : @[[NSString stringWithFormat:
            SGL(@"settings.environment.supported_versions.title", @"Supported Spotify versions: %@"), @"9.1.90, 9.2.0, 9.2.2"]];
        NSArray *titles = [SGEnvironmentWarningRows() valueForKey:@"title"];
        if (![titles isEqual:expected]) {
            NSLog(@"FAIL Spotify %@: expected %@, got %@", version, expected, titles);
            result = 1;
        }
    }
    sg_installInfo = nil;
    method_exchangeImplementations(original, fixture);
    if (!result) NSLog(@"PASS: stripped IPA is quiet; hand-injected .deb gets the app-changes warning");
    return result;
}

@interface Delegate : UIResponder <UIApplicationDelegate>
@end
@implementation Delegate
@end

@interface Scene : UIResponder <UIWindowSceneDelegate>
@property (nonatomic, strong) UIWindow *window;
@property BOOL checkStarted;
@end

@implementation Scene

- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    NSArray<NSString *> *arguments = NSProcessInfo.processInfo.arguments;
    sg_old = [arguments containsObject:@"old"];
    [NSUserDefaults.standardUserDefaults removeObjectForKey:SGKeyOnboardingSeen];

    UIViewController *home = [UIViewController new];
    home.view.backgroundColor = [UIColor colorWithRed:0.12 green:0.2 blue:0.16 alpha:1];
    UILabel *label = [UILabel new];
    label.text = @"Home";
    label.textColor = UIColor.whiteColor;
    label.font = [UIFont systemFontOfSize:34 weight:UIFontWeightBold];
    label.frame = CGRectMake(20, 120, 300, 44);
    [home.view addSubview:label];
    self.window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    self.window.rootViewController = home;
    [self.window makeKeyAndVisible];
    if ([arguments containsObject:@"kept-cleanup"] || [arguments containsObject:@"sponsorblock-check"]) return;

    if ([arguments containsObject:@"environment"]) {
        [NSUserDefaults.standardUserDefaults removeObjectForKey:@"spotifyglass.environment.told"];
        NSString *eevee = [NSBundle.mainBundle pathForResource:@"EeveeSpotify" ofType:@"dylib"];
        NSLog(@"harness: EeveeSpotify.dylib %@", dlopen(eevee.UTF8String, RTLD_NOW) ? @"loaded" : @"not loaded");
        NSLog(@"harness: injected %d, Spotify %@", SGEeveeSpotifyInjected(), SGSpotifyVersion());
        SGCheckEnvironmentOnce();
        [NSUserDefaults.standardUserDefaults setBool:YES forKey:SGKeyOnboardingSeen];
        return;
    }
    BOOL whatsNew = [arguments containsObject:@"whatsnew"];
    HarnessWhen(@"active tour host", ^BOOL { return scene.activationState == UISceneActivationStateForegroundActive; }, ^{
        NSLog(@"harness: %lu changes in the notes", (unsigned long)SGWhatsNewChanges().count);
        if (whatsNew) SGShowWhatsNew();
        else SGShowOnboarding();
    });
    if ([arguments containsObject:@"pick"]) {
        __block UIControl *other;
        HarnessWhen(@"unselected look card in the presented tour", ^BOOL {
            UIView *tour = home.presentedViewController.viewIfLoaded;
            if (!tour.window) return NO;
            NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:tour];
            while (queue.count) {
                UIView *view = queue.firstObject;
                [queue removeObjectAtIndex:0];
                if ([NSStringFromClass(view.class) isEqualToString:@"SGLookCard"] && !((UIControl *)view).selected) {
                    other = (UIControl *)view;
                    return YES;
                }
                [queue addObjectsFromArray:view.subviews];
            }
            return NO;
        }, ^{ [other sendActionsForControlEvents:UIControlEventTouchUpInside]; });
    }
}

- (void)sceneDidBecomeActive:(UIScene *)scene {
    if (self.checkStarted) return;
    self.checkStarted = YES;
    NSArray *arguments = NSProcessInfo.processInfo.arguments;
    if ([arguments containsObject:@"kept-cleanup"]) {
        dispatch_async(dispatch_get_main_queue(), ^{ CheckKeptCleanup(self.window); });
    } else if ([arguments containsObject:@"sponsorblock-check"]) {
        dispatch_async(dispatch_get_main_queue(), ^{ CheckSponsorBlockScreens(self.window); });
    }
}

@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        if ([NSProcessInfo.processInfo.arguments containsObject:@"environment-check"])
            return checkInstallWarnings();
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(Delegate.class));
    }
}
