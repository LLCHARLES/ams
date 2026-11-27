// Exercise the real page's asynchronous completion and selection handlers.
// The file-copy boundary is paused; style and the DSP consumer are test doubles.
#import <UIKit/UIKit.h>
#import "AudioEffectsLibraryPage.m"
#import "AudioEffectsApply.h"

@implementation SGPage
@end
UIColor *SGGrey(void) { return UIColor.grayColor; }
UIColor *SGGreen(void) { return UIColor.greenColor; }
UIColor *SGRed(void) { return UIColor.redColor; }
UIColor *SGCardBackground(void) { return UIColor.blackColor; }
const CGFloat SGSectionGap = 12;
UIImage *SGTileImage(NSString *symbol) { return nil; }
UIImageView *SGSymbolView(NSString *name, CGFloat size, UIImageSymbolWeight weight, CGFloat box) { return nil; }
UIView *SGNote(NSString *text) { return [UIView new]; }
void SGFitNote(UITableView *table, UIView *wrapper, CGFloat top, CGFloat bottom) {}
void SGInsetForBars(UITableView *table) {}
void SGFillCell(UITableViewCell *cell, NSString *title, NSString *subtitle, UIColor *color, NSString *symbol) {}
UITableViewCell *SGDequeueCell(UITableView *table, NSString *identifier) { return [UITableViewCell new]; }
void SGOpenURL(NSString *url) {}
NSString *SGDSPError(NSString *key) { return nil; }
NSString *SGDSPGraphicEqLine(NSString *text) { return text; }
// This paused-copy fixture models only the Liveprog library.
NSString *SGDSPFileKey(SGDSPFileKind kind) { return SGKeyDSPLiveprogFile; }
NSArray<NSString *> *SGDSPFileExtensions(SGDSPFileKind kind) { return @[@"eel"]; }
NSArray<NSString *> *SGDSPLibraryFiles(SGDSPFileKind kind) { return @[@"A.eel", @"B.eel"]; }
BOOL SGDSPDeleteFile(SGDSPFileKind kind, NSString *name) { return NO; }

static dispatch_semaphore_t allowCopy;
static NSString *contentsA, *loadedContents;
static int failures;
static void (^completed)(void);

void SGDSPApply(NSString *effect) {
    if ([effect isEqualToString:SGKeyDSPLiveprog])
        loadedContents = [SGDSPString(SGKeyDSPLiveprogFile) isEqualToString:@"A.eel"] ? contentsA : @"B";
}
NSString *SGDSPImportFile(SGDSPFileKind kind, NSURL *url, NSError **error) {
    dispatch_semaphore_wait(allowCopy, DISPATCH_TIME_FOREVER);
    contentsA = @"replacement A";
    return @"A.eel";
}

@interface ImportTable : UITableView
@end
@implementation ImportTable
- (void)reloadSections:(NSIndexSet *)sections withRowAnimation:(UITableViewRowAnimation)animation {
    if (completed) {
        void (^done)(void) = completed;
        completed = nil;
        dispatch_async(dispatch_get_main_queue(), done);
    }
}
@end
@interface ImportPage : SGDSPFilesPage
@property(nonatomic) BOOL leaving;
@end
@implementation ImportPage
- (void)loadView { self.tableView = [ImportTable new]; }
- (BOOL)isMovingFromParentViewController { return self.leaving; }
@end

static void expect(BOOL ok, const char *name) {
    printf("%s %s\n", ok ? "ok" : "FAIL", name);
    failures += !ok;
}

static void runCase(unsigned scenario) {
    if (scenario == 3) {
        printf("RESULT failures=%d\n", failures);
        fflush(stdout);
        exit(failures ? 1 : 0);
    }
    contentsA = @"original A";
    SGDSPSetString(SGKeyDSPLiveprogFile, @"A.eel");
    ImportPage *page = [[ImportPage alloc] initWithKind:SGDSPFileLiveprog];
    [page viewWillAppear:NO];
    [page documentPicker:nil didPickDocumentsAtURLs:@[[NSURL fileURLWithPath:@"/fixture/A.eel"]]];
    if (scenario == 0) {
        page.leaving = YES;
        [page viewDidDisappear:NO];
    } else {
        [page tableView:page.tableView didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:1 inSection:1]];
        if (scenario == 1)
            [page tableView:page.tableView didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:1]];
    }
    completed = ^{
        if (scenario < 2) {
            expect([SGDSPString(SGKeyDSPLiveprogFile) isEqualToString:@"A.eel"] && [loadedContents isEqualToString:@"replacement A"],
                   scenario == 0 ? "dismissed import refreshes the replaced current file" : "A-B-A selection refreshes the replaced current file");
        } else {
            expect([SGDSPString(SGKeyDSPLiveprogFile) isEqualToString:@"B.eel"] && [loadedContents isEqualToString:@"B"],
                   "stale import neither selects A nor reloads it over current B");
        }
        [page viewDidDisappear:NO];
        runCase(scenario + 1);
    };
    dispatch_semaphore_signal(allowCopy);
}
@interface ImportHarness : UIResponder <UIApplicationDelegate>
@property(nonatomic,strong) UIWindow *window;
@end
@implementation ImportHarness
- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)options {
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController = [UIViewController new];
    [self.window makeKeyAndVisible];
    allowCopy = dispatch_semaphore_create(0);
    dispatch_async(dispatch_get_main_queue(), ^{ runCase(0); });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 120 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        fprintf(stderr, "FAIL import completion watchdog\n");
        exit(1);
    });
    return YES;
}
@end
int main(int argc, char **argv) {
    @autoreleasepool { return UIApplicationMain(argc, argv, nil, @"ImportHarness"); }
}
