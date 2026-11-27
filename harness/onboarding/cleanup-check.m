#import "App/Onboarding/Onboarding.h"
#import "Settings/SGModPage.h"
#import "../harness-fail.h"

// Hold only the environment scans' deliveries, so an older row and tap can finish last.
static NSMutableArray<dispatch_block_t> *deliveries;
static void scheduleCleanup(dispatch_queue_t queue, dispatch_block_t block) {
    if (!deliveries) dispatch_async(queue, block);
    else if (queue == dispatch_get_main_queue()) [deliveries addObject:[block copy]];
    else block();
}
#define dispatch_async scheduleCleanup
#import "App/Onboarding/Environment.m"
#undef dispatch_async

@interface CleanupPage : SGModPage
@property NSString *expectedSubtitle;
@property SGModRow *cleanup;
@property NSUInteger alerts;
@end
@implementation CleanupPage
- (void)presentViewController:(UIViewController *)controller animated:(BOOL)animated completion:(dispatch_block_t)completion {
    HARNESS_CHECK([controller isKindOfClass:UIAlertController.class]);
    HARNESS_CHECK(controller.overrideUserInterfaceStyle == UIUserInterfaceStyleDark);
    self.alerts++;
    if (self.alerts == 2) {
        HARNESS_CHECK([[(UIAlertController *)controller actions].lastObject.title isEqual:@"Keep"]);
        puts("PASS kept cleanup size, delete action and dark environment alerts");
        exit(0);
    }
}
- (void)tableView:(UITableView *)table willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)path {
    UIListContentConfiguration *content = (id)cell.contentConfiguration;
    if (![content.text isEqual:self.cleanup.title]) return;
    HARNESS_CHECK([content.secondaryText isEqual:self.expectedSubtitle]);
    HARNESS_CHECK([SGEnvironmentWarningRows().lastObject.subtitle isEqual:self.expectedSubtitle]);
    dispatch_async(dispatch_get_main_queue(), ^{
        // An upgrade can drop support without changing Spotify or its plist. The previous build
        // had already checked this exact install; the new warning must appear once, not twice.
        [NSUserDefaults.standardUserDefaults setObject:@"eevee 0, spotify 1.0, app changes 0" forKey:@"spotifyglass.environment.told"];
        tellProblems();
        HARNESS_CHECK(self.alerts == 1);
        tellProblems();
        HARNESS_CHECK(self.alerts == 1);
        self.cleanup.action();
    });
}
@end

void CheckKeptCleanup(UIWindow *window) {
    // The persisted result of Keep, in a fresh process that has never shown the offer.
    [NSUserDefaults.standardUserDefaults setBool:YES forKey:@"spotifyglass.environment.chromaCleanupOffered"];
    NSFileManager *files = NSFileManager.defaultManager;
    NSURL *support = [files URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;
    NSURL *dir = [support URLByAppendingPathComponent:@"spoti.pw/Sing"];
    HARNESS_CHECK([files createDirectoryAtURL:dir withIntermediateDirectories:YES attributes:nil error:nil]);
    NSURL *file = [dir URLByAppendingPathComponent:@"fixture"];
    HARNESS_CHECK([[NSMutableData dataWithLength:4096] writeToURL:file atomically:YES]);
    deliveries = [NSMutableArray array];
    SGEnvironmentWarningRows().lastObject.action();
    HARNESS_CHECK([[NSMutableData dataWithLength:65536] writeToURL:file atomically:YES]);
    NSNumber *bytes;
    HARNESS_CHECK([file getResourceValue:&bytes forKey:NSURLTotalFileAllocatedSizeKey error:nil]);
    NSArray *rows = SGEnvironmentWarningRows();
    offerCleanup(YES); // supersedes the open row's scan; Keep is already persisted
    NSArray<dispatch_block_t> *pending = deliveries;
    deliveries = nil;
    HARNESS_CHECK(pending.count == 4);
    HARNESS_CHECK(rows.count >= 2);
    CleanupPage *page = [[CleanupPage alloc] initWithTitle:@"Settings" intro:nil sections:@[SGSection(nil, rows)] footer:nil];
    page.cleanup = rows.lastObject;
    HARNESS_CHECK([page.cleanup.title isEqual:@"Chroma left files behind"]);
    page.expectedSubtitle = [NSString stringWithFormat:@"%@ Retrine never uses. Tap to delete",
        [NSByteCountFormatter stringFromByteCount:bytes.longLongValue countStyle:NSByteCountFormatterCountStyleFile]];
    window.overrideUserInterfaceStyle = UIUserInterfaceStyleLight;
    window.rootViewController = page;
    dispatch_async(dispatch_get_main_queue(), ^{
        pending[3]();
        HARNESS_CHECK(page.cleanup.visible() && [page.cleanup.subtitle isEqual:page.expectedSubtitle]);
        pending[2]();
        pending[0]();
        HARNESS_CHECK([SGEnvironmentWarningRows().lastObject.subtitle isEqual:page.expectedSubtitle]);
        pending[1]();
        HARNESS_CHECK([SGEnvironmentWarningRows().lastObject.subtitle isEqual:page.expectedSubtitle]);
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 120 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        HARNESS_FAIL(@"cleanup row did not refresh or present its alerts");
    });
}
