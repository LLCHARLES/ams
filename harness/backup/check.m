#import <UIKit/UIKit.h>
#import <sys/stat.h>
static NSString *exportDirectory;
static NSUInteger restartCount;
static void recordRestart(void) { restartCount++; }
#define NSTemporaryDirectory() exportDirectory
#define SGRestartSpotify recordRestart
#import "App/About/Backup.m"
#undef SGRestartSpotify
#undef NSTemporaryDirectory
#import "../harness-fail.h"
#import "flag-conversions.inc"
static id oldOverride;
id SGForcedFlagValue(NSString *key) { return oldOverride; }
const SGFlagDef SGFlagTable[] = {{"bad", SGFlagBool, 0, 0, 1}};
const NSUInteger SGFlagCount = 1;

@interface ExportPresenter : UIViewController
@property UIViewController *last;
@end
@implementation ExportPresenter
- (void)presentViewController:(UIViewController *)controller animated:(BOOL)animated completion:(void (^)(void))completion {
    self.last = controller;
}
@end
static ExportPresenter *owner;
UIViewController *SGTopController(void) { return owner; }

// Model UIKit forwarding presentation from a pushed page to its navigation controller.
@interface ImportNavigation : UINavigationController
@property (nonatomic, strong) UIViewController *modal;
@end
@implementation ImportNavigation
- (UIViewController *)presentedViewController { return self.modal; }
@end

@interface ImportPresenter : UIViewController <UIAdaptivePresentationControllerDelegate>
@property (nonatomic) BOOL suppliesPresentationDelegate;
@property (nonatomic) NSUInteger alertPresentations;
@end
@implementation ImportPresenter
- (UIViewController *)presentedViewController { return nil; }
- (void)presentViewController:(UIViewController *)controller animated:(BOOL)animated completion:(void (^)(void))completion {
    if (self.suppliesPresentationDelegate && [controller isKindOfClass:UIDocumentPickerViewController.class]) {
        controller.presentationController.delegate = self;
    }
    if ([controller isKindOfClass:UIAlertController.class]) self.alertPresentations++;
    ((ImportNavigation *)self.navigationController).modal = controller;
    if (completion) completion();
}
@end

@interface DismissingPicker : UIDocumentPickerViewController
@property (nonatomic) BOOL remotelyDismissing;
@property (nonatomic) NSUInteger dismissalCalls;
@property (nonatomic) NSUInteger statusReads;
@end
@implementation DismissingPicker
- (BOOL)isBeingDismissed {
    self.statusReads++;
    return self.remotelyDismissing;
}
- (id<UIViewControllerTransitionCoordinator>)transitionCoordinator { return nil; }
- (void)dismissViewControllerAnimated:(BOOL)animated completion:(void (^)(void))completion {
    self.dismissalCalls++;
}
@end

static void waitForPickerStatusRead(DismissingPicker *picker) {
    NSUInteger reads = picker.statusReads;
    NSTimeInterval deadline = NSProcessInfo.processInfo.systemUptime + 2;
    while (picker.statusReads == reads && NSProcessInfo.processInfo.systemUptime < deadline) {
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.01, false);
    }
    HARNESS_CHECK(picker.statusReads > reads);
}

static UIDocumentPickerViewController *startImport(ImportPresenter *presenter, ImportNavigation *nav) {
    SGImportSettings(presenter);
    HARNESS_CHECK([nav.modal isKindOfClass:UIDocumentPickerViewController.class]);
    UIDocumentPickerViewController *picker = (UIDocumentPickerViewController *)nav.modal;
    HARNESS_CHECK(picker.overrideUserInterfaceStyle == UIUserInterfaceStyleDark);
    HARNESS_CHECK(((SGSettingsPicker *)picker.delegate).pending);
    return picker;
}

static UIAlertController *waitForImportAlert(ImportNavigation *nav, NSString *title) {
    NSTimeInterval deadline = NSProcessInfo.processInfo.systemUptime + 4;
    while (![nav.modal isKindOfClass:UIAlertController.class] && NSProcessInfo.processInfo.systemUptime < deadline) {
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.01, false);
    }
    HARNESS_CHECK([nav.modal isKindOfClass:UIAlertController.class]);
    UIAlertController *alert = (UIAlertController *)nav.modal;
    HARNESS_CHECK(alert.overrideUserInterfaceStyle == UIUserInterfaceStyleDark);
    HARNESS_CHECK([alert.title isEqualToString:title]);
    return alert;
}

static void chooseAlertAction(UIAlertAction *action) {
    HARNESS_CHECK(action != nil);
    void (^handler)(UIAlertAction *) = [action valueForKey:@"handler"];
    HARNESS_CHECK(handler != nil);
    handler(action);
}

static void checkImport(void) {
    ImportPresenter *presenter = [ImportPresenter new];
    ImportNavigation *nav = [[ImportNavigation alloc] initWithRootViewController:presenter];
    __attribute__((objc_precise_lifetime)) UIWindow *window = [UIWindow new];
    [window addSubview:nav.view];
    [nav.view addSubview:presenter.view];
    HARNESS_CHECK(presenter.view.window == window && presenter.parentViewController == nav);

    NSString *directory = exportDirectory;
    NSURL *valid = [NSURL fileURLWithPath:[directory stringByAppendingPathComponent:@"import.json"]];
    NSURL *invalid = [NSURL fileURLWithPath:[directory stringByAppendingPathComponent:@"invalid.json"]];
    HARNESS_CHECK([@"{\"settings\":{\"spotifyglass.sponsorblock.enabled\":true}}" writeToURL:valid
        atomically:YES encoding:NSUTF8StringEncoding error:nil]);
    HARNESS_CHECK([@"{invalid" writeToURL:invalid atomically:YES encoding:NSUTF8StringEncoding error:nil]);
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSString *domain = NSBundle.mainBundle.bundleIdentifier;
    NSDictionary *saved = [defaults persistentDomainForName:domain];
    [defaults setPersistentDomain:@{SGKeySponsorBlock: @NO} forName:domain];

    presenter.suppliesPresentationDelegate = YES;
    UIDocumentPickerViewController *picker = startImport(presenter, nav);
    HARNESS_CHECK(picker.presentationController.delegate == presenter);
    presenter.suppliesPresentationDelegate = NO;
    SGSettingsPicker *delegate = (SGSettingsPicker *)picker.delegate;
    HARNESS_CHECK(!presenter.presentedViewController && nav.presentedViewController == picker);
    [delegate documentPicker:picker didPickDocumentsAtURLs:@[valid]];
    nav.modal = nil;
    UIAlertController *alert = waitForImportAlert(nav, SGL(@"settings.mod.backup.import_confirm.alert.title", @"Import settings?"));
    HARNESS_CHECK(![defaults boolForKey:SGKeySponsorBlock]);
    chooseAlertAction(alert.actions.firstObject);
    HARNESS_CHECK([defaults boolForKey:SGKeySponsorBlock] && restartCount == 1 && !delegate.pending);
    nav.modal = nil;
    if (saved) [defaults setPersistentDomain:saved forName:domain];
    else [defaults removePersistentDomainForName:domain];

    picker = startImport(presenter, nav);
    DismissingPicker *dismissing = [[DismissingPicker alloc] initForOpeningContentTypes:@[UTTypeJSON] asCopy:YES];
    dismissing.remotelyDismissing = YES;
    nav.modal = dismissing;
    delegate.picker = dismissing;
    NSUInteger previousAlerts = presenter.alertPresentations;
    [presenter.view removeFromSuperview];
    HARNESS_CHECK(!presenter.view.window);
    [delegate documentPicker:dismissing didPickDocumentsAtURLs:@[valid]];
    SGImportSettings(presenter);
    waitForPickerStatusRead(dismissing);
    HARNESS_CHECK(delegate.reading && nav.modal == dismissing && dismissing.dismissalCalls == 0);
    dismissing.remotelyDismissing = NO;
    waitForPickerStatusRead(dismissing);
    HARNESS_CHECK(nav.modal == dismissing && dismissing.dismissalCalls == 0);
    nav.modal = nil;
    waitForPickerStatusRead(dismissing);
    HARNESS_CHECK(delegate.reading && !nav.modal && !presenter.view.window &&
                  presenter.alertPresentations == previousAlerts);
    [nav.view addSubview:presenter.view];
    alert = waitForImportAlert(nav, SGL(@"settings.mod.backup.import_confirm.alert.title", @"Import settings?"));
    HARNESS_CHECK(presenter.alertPresentations == previousAlerts + 1 && dismissing.dismissalCalls == 0);
    chooseAlertAction(alert.actions.lastObject);
    HARNESS_CHECK(!delegate.pending);
    nav.modal = nil;

    picker = startImport(presenter, nav);
    [delegate documentPicker:picker didPickDocumentsAtURLs:@[invalid]];
    nav.modal = nil;
    alert = waitForImportAlert(nav, SGL(@"settings.mod.backup.invalid_file.alert.title", @"Not a settings file"));
    chooseAlertAction(alert.actions.lastObject);
    HARNESS_CHECK(!delegate.pending && restartCount == 1);
    nav.modal = nil;

    @autoreleasepool {
        startImport(presenter, nav);
        nav.modal = nil;
    }
    HARNESS_CHECK(!delegate.picker && delegate.pending);
    picker = startImport(presenter, nav);
    UIDocumentPickerViewController *detachedPicker = picker;
    nav.modal = nil;
    HARNESS_CHECK(delegate.picker == detachedPicker && delegate.pending);
    picker = startImport(presenter, nav);
    HARNESS_CHECK(picker != detachedPicker && delegate.picker == picker);
    [delegate documentPickerWasCancelled:picker];
    HARNESS_CHECK(!delegate.pending);
    nav.modal = nil;
    picker = startImport(presenter, nav);
    [delegate presentationControllerDidDismiss:picker.presentationController];
    HARNESS_CHECK(!delegate.pending);
    puts("backup import: ok");
}

static void runChecks(void) {
    @autoreleasepool {
        NSArray *messages = @[@{@"composedMessage": @"[spotifyglass]"},
                              @{@"composedMessage": @"[spotifyglass] settings opened"},
                              @{@"composedMessage": @"[spotifyglass] screen dump 1"}];
        NSArray *exportable = [messages filteredArrayUsingPredicate:diagnosticLogPredicate()];
        HARNESS_CHECK([exportable isEqual:@[messages[1]]]);
        for (oldOverride in @[@[], @{}]) {
            @try {
                HARNESS_CHECK(boolFor(@"bad", YES) && intFor(@"bad", 0, 10, 7) == 7);
            } @catch (NSException *exception) {
                HARNESS_FAIL(@"an invalid stored flag raised an exception");
            }
        }
        NSString *suite = [@"retrine.backup.check." stringByAppendingString:NSUUID.UUID.UUIDString];
        NSUserDefaults *store = [[NSUserDefaults alloc] initWithSuiteName:suite];
        NSString *wg = @"spotifyglass.wireguard", *server = SGKeySponsorBlockServer;
        NSString *ordinary = SGKeySponsorBlock;
        NSDictionary *local = @{wg: @{@"host": @"local.example"}, server: @"https://local.example", ordinary: @NO};
        [store setPersistentDomain:local forName:suite];
        NSDictionary *exported = exportSettings(local);
        importSettings(@{wg: @{@"host": @"import.example"}, server: @"https://import.example", ordinary: @YES}, store, local);
        NSDictionary *after = [store persistentDomainForName:suite];
        [store removePersistentDomainForName:suite];
        BOOL exportOK = [exported isEqual:@{ordinary: @NO}];
        BOOL importOK = [after isEqual:@{wg: local[wg], server: local[server], ordinary: @YES}];
        if (!exportOK || !importOK) HARNESS_FAIL(@"private settings: export %d, import %d", exportOK, importOK);
        NSString *base = @"spotifyglass.lyrics.openai.baseURL";
        NSDictionary *historyDefaults = @{SGKeySearchRecents:@[], SGKeySeenNew:@{}};
        [NSUserDefaults.standardUserDefaults registerDefaults:historyDefaults];
        [store registerDefaults:historyDefaults];
        NSDictionary *install = @{base:@"https://local.example", @"spotifyglass.font.files":@[@"old.ttf"],
                                  SGKeySearchRecents:@[@[@"page.mod"]], SGKeySeenNew:@{@"reportProblem":@YES},
                                  @"spotifyglass.localFiles.lrcLinks":@{@"track":@"kept.lrc"}};
        [store setPersistentDomain:install forName:suite];
        [store registerDefaults:@{@"spotifyglass.registered":@1}];
        NSData *json = [@"{\"settings\":{\"spotifyglass.flag.bad\":[],\"spotifyglass.amoled\":{},"
            "\"spotifyglass.unrecognized\":12,\"spotifyglass.registered\":\"no\","
            "\"spotifyglass.lyrics.openai.baseURL\":\"https://other.example\","
            "\"spotifyglass.settings.seenNew\":{},"
            "\"spotifyglass.font.files\":[\"other.ttf\"],\"spotifyglass.localFiles.lrcLinks\":{},"
            "\"spotifyglass.dsp.convolver.file\":\"other.wav\",\"spotifyglass.redesign.untested\":true,"
            "\"spotifyglass.sponsorblock.enabled\":true}}" dataUsingEncoding:NSUTF8StringEncoding];
        importSettings([NSJSONSerialization JSONObjectWithData:json options:0 error:nil][@"settings"], store, install);
        NSMutableDictionary *expected = [install mutableCopy];
        expected[ordinary] = @YES;
        BOOL safe = [[store persistentDomainForName:suite] isEqual:expected] && !exportSettings(install).count;
        [store removePersistentDomainForName:suite];
        HARNESS_CHECK(safe);
        importSettings(@{@"spotifyglass.registered":@2, @"spotifyglass.flag.bad":@YES,
                         @"spotifyglass.artistBlock.list":@[@{@"name":@"Artist",@"uri":@"spotify:artist:test"}],
                         @"spotifyglass.motion.sources":@[@"canvas",@{}]}, store, @{});
        NSDictionary *portable = [store persistentDomainForName:suite];
        [store removePersistentDomainForName:suite];
        HARNESS_CHECK([portable[@"spotifyglass.registered"] isEqual:@2] && [portable[@"spotifyglass.flag.bad"] isEqual:@YES] &&
            [portable[@"spotifyglass.artistBlock.list"] count] == 1 && !portable[@"spotifyglass.motion.sources"]);
        NSDictionary *choices = @{@"spotifyglass.homeGradientTint":@3, @"spotifyglass.homeGradientStrength":@2,
            @"spotifyglass.lockscreen.lyricsSize":@2,
            @"spotifyglass.homeGradientHeight":@1, @"spotifyglass.navbar.layout":@[@{@"id":@"home", @"hidden":@NO}],
            @"spotifyglass.navbar.split":@[@"home"], @"spotifyglass.redesign.fluid.speed":@125,
            @"spotifyglass.lyrics.pip.original.size":@64, @"spotifyglass.lyrics.pip.original.weight":@2,
            @"spotifyglass.lyrics.pip.pronunciation.size":@16, @"spotifyglass.lyrics.pip.pronunciation.weight":@0,
            @"spotifyglass.lyrics.pip.translation.size":@48, @"spotifyglass.lyrics.pip.translation.weight":@3,
            @"spotifyglass.redesign.fluid.renderer":@1, @"spotifyglass.redesign.haptics.controls.strength":@2,
            SGRKeyPlayerHoldNoClip:@YES, @"spotifyglass.redesign.liveActivity":@YES, @"spotifyglass.flag.bad":@NO};
        NSMutableDictionary *snapshot = [choices mutableCopy];
        [snapshot addEntriesFromDictionary:install];
        snapshot[@"spotifyglass.unknown.unschematized"] = @[];
        NSDictionary *full = exportSettings(snapshot);
        NSData *document = [NSJSONSerialization dataWithJSONObject:full options:0 error:nil];
        importSettings([NSJSONSerialization JSONObjectWithData:document options:0 error:nil], store, @{});
        HARNESS_CHECK([full isEqual:choices] && [[store persistentDomainForName:suite] isEqual:choices]);
        NSDictionary *boolWeights = [NSJSONSerialization JSONObjectWithData:
            [@"{\"spotifyglass.lyrics.pip.original.weight\":true,\"spotifyglass.lyrics.pip.translation.weight\":false}"
             dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
        NSMutableDictionary *changedWeights = [choices mutableCopy];
        [changedWeights addEntriesFromDictionary:boolWeights];
        importSettings(changedWeights, store, choices);
        for (NSString *key in boolWeights) HARNESS_CHECK([[store objectForKey:key] isEqual:choices[key]]);
        NSDictionary *invalidRoles = @{@"spotifyglass.lyrics.pip.original.size":@23, @"spotifyglass.lyrics.pip.translation.size":@49,
            @"spotifyglass.lyrics.pip.pronunciation.size":@22.5, @"spotifyglass.lyrics.pip.translation.weight":@4,
            @"spotifyglass.lyrics.pip.original.weight":@"2"};
        importSettings(invalidRoles, store, choices);
        for (NSString *key in invalidRoles) HARNESS_CHECK([[store objectForKey:key] isEqual:choices[key]]);
        NSString *flag = @"spotifyglass.flag.bad", *background = @"spotifyglass.redesign.player.background";
        [store setObject:@NO forKey:flag];
        importSettings(@{flag:@2}, store, @{flag:@NO});
        HARNESS_CHECK([[store objectForKey:flag] isEqual:@NO]);
        for (id invalid in @[@"not numeric", @[], @2]) {
            [store setObject:@(SGRPlayerBackgroundAnimated) forKey:background];
            importSettings(@{@"spotifyglass.redesign.player.backdrop":invalid}, store, @{background:@(SGRPlayerBackgroundAnimated)});
            HARNESS_CHECK([store integerForKey:background] == SGRPlayerBackgroundAnimated);
        }
        [store removePersistentDomainForName:suite];
        owner = [ExportPresenter new];
        exportDirectory = NSProcessInfo.processInfo.environment[@"EXPORT_DIR"];
        NSString *path = [exportDirectory stringByAppendingPathComponent:@"spotifyglass-settings.json"];
        HARNESS_CHECK([@"stale" writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil]);
        HARNESS_CHECK(chmod(exportDirectory.fileSystemRepresentation, 0500) == 0);
        SGExportSettings();
        HARNESS_CHECK(chmod(exportDirectory.fileSystemRepresentation, 0700) == 0);
        HARNESS_CHECK([owner.last isKindOfClass:UIAlertController.class]);
        HARNESS_CHECK(owner.last.overrideUserInterfaceStyle == UIUserInterfaceStyleDark);
        HARNESS_CHECK([[(UIAlertController *)owner.last message] length] > 0);
        HARNESS_CHECK([[NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil] isEqual:@"stale"]);
        checkImport();
        puts("backup: ok");
    }
    exit(0);
}

@interface BackupApp : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end
@implementation BackupApp
- (void)runChecks { runChecks(); }
- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)options {
    self.window = [UIWindow new];
    self.window.rootViewController = [UIViewController new];
    [self performSelector:@selector(runChecks) withObject:nil afterDelay:0];
    return YES;
}
@end

int main(int argc, char **argv) {
    @autoreleasepool { return UIApplicationMain(argc, argv, nil, NSStringFromClass(BackupApp.class)); }
}
