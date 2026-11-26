#import <UIKit/UIKit.h>
#import <sys/stat.h>
static NSString *exportDirectory;
#define NSTemporaryDirectory() exportDirectory
#import "App/About/Backup.m"
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
        puts("backup: ok");
    }
    exit(0);
}

@interface BackupApp : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end
@implementation BackupApp
- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)options {
    self.window = [UIWindow new];
    self.window.rootViewController = [UIViewController new];
    dispatch_async(dispatch_get_main_queue(), ^{ runChecks(); });
    return YES;
}
@end

int main(int argc, char **argv) {
    @autoreleasepool { return UIApplicationMain(argc, argv, nil, NSStringFromClass(BackupApp.class)); }
}
