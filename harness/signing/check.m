#import "../harness-fail.h"
#import "Core/SGCore.h"
#import "App/About/About.h"
#import "Settings/SGPageStyle.h"

// Launches share only this temporary preferences file, not the observer or the pending sheet.
static NSString *prefsPath;
@interface TestDefaults : NSObject
+ (instancetype)standardUserDefaults;
- (NSString *)stringForKey:(NSString *)key;
- (void)setObject:(id)value forKey:(NSString *)key;
@end
@implementation TestDefaults
+ (instancetype)standardUserDefaults { return [self new]; }
- (NSString *)stringForKey:(NSString *)key { return [NSDictionary dictionaryWithContentsOfFile:prefsPath][key]; }
- (void)setObject:(id)value forKey:(NSString *)key {
    HARNESS_CHECK(([@{key: value} writeToFile:prefsPath atomically:YES]));
}
@end

#define SG_SIGNING_HARNESS 1
#define NSUserDefaults TestDefaults
#define dispatch_after(when, queue, block) (block)()
#import "App/About/Signing.m"

static BOOL tour, presented;
@interface Presenter : UIViewController
@end
@implementation Presenter
- (void)presentViewController:(UIViewController *)vc animated:(BOOL)animated completion:(void (^)(void))completion {
    HARNESS_CHECK([vc isKindOfClass:UIAlertController.class]);
    presented = YES;
    if (completion) completion();
}
@end
UIViewController *SGTopController(void) { return [Presenter new]; }
NSString *SGSigningAppIdentifier(void) { return @"paid.profile.id"; }
BOOL SGOnboardingShowing(void) { return tour; }
NSString *SGL(NSString *key, NSString *english) { return english; }
NSString *const SGRepoURL = nil;
void SGOpenURL(NSString *url) {}
SGModRow *SGWarningRow(NSString *title, NSString *subtitle, void (^action)(void)) { return nil; }
SGModRow *SGStatRow(NSString *title, NSString *(^value)(void)) { return nil; }

int main(int argc, const char **argv) {
    @autoreleasepool {
        HARNESS_CHECK(argc == 3);
        NSString *launch = @(argv[1]);
        prefsPath = @(argv[2]);
        tour = [launch isEqualToString:@"tour"];
        SGCheckSigningOnce();
        [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationDidBecomeActiveNotification object:nil];
        if (presented != [launch isEqualToString:@"after-restart"])
            HARNESS_FAIL(@"%@: signing sheet %@", launch, presented ? @"unexpected" : @"missing");
        // Restart exits without the tour dismissal callback.
    }
    return 0;
}
