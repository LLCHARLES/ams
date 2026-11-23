// Drive the production controller through notifications, observing its labels and controls.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "../harness-fail.h"
#import "title-notification-stubs.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Redesigned/Player/Player.h"
#import "Shared/Lyrics/Lyrics.h"
#import "Shared/LyricsTranslation/LyricsTranslation.h"

@interface SGRLandscapeLyricsController : UIViewController
- (void)setControlsShown:(BOOL)shown;
@end

static int failed, checked;
static SGRLandscapeLyricsController *screen;

static void check(BOOL ok, NSString *what) {
    printf("%s %s\n", ok ? "PASS" : "FAIL", what.UTF8String);
    fflush(stdout);
    checked++;
    if (!ok) failed++;
}
// KVC "title" resolves UIViewController.title rather than the displayed label.
static id field(NSString *name) {
    Ivar ivar = class_getInstanceVariable(SGRLandscapeLyricsController.class,
                                        [@"_" stringByAppendingString:name].UTF8String);
    if (!ivar) {
        fprintf(stderr, "FAIL missing display field %s\n", name.UTF8String);
        exit(1);
    }
    return object_getIvar(screen, ivar);
}
static void controlsShown(BOOL shown) {
    check(((UIView *)field(@"controls")).alpha == (shown ? 1 : 0),
          shown ? @"title delivery leaves controls visible" : @"title delivery does not reveal hidden controls");
}
static void textIs(NSString *title, NSString *artist, NSString *context) {
    SGMarqueeLabel *titleLabel = field(@"title"), *artistLabel = field(@"artist");
    check([titleLabel.text isEqual:title] && [artistLabel.text isEqual:artist], context);
    check([titleLabel.accessibilityLabel isEqual:title] && [artistLabel.accessibilityLabel isEqual:artist],
          [context stringByAppendingString:@" (accessibility)"]);
}
static void post(NSNotificationName name, id object) {
    [NSNotificationCenter.defaultCenter postNotificationName:name object:object];
}
static void asyncTitle(NSString *track, dispatch_block_t continuation) {
    dispatch_async(dispatch_get_main_queue(), ^{
        post(SGTranslatedTitleDidChangeNotification, track);
        continuation();
    });
}
static void finish(void) {
    [screen setControlsShown:YES];
    __weak id weakScreen = screen, weakTitle = field(@"title");
    NSTimer *timer = field(@"rest");
    check(timer.valid, @"deallocation fixture has an active rest timer");
    screen = nil;
    dispatch_async(dispatch_get_main_queue(), ^{
        check(weakScreen == nil && weakTitle == nil, @"observers do not retain controller or displayed label");
        check(!timer.valid, @"deallocation invalidates the rest timer");
        check(SGTitleHarnessObserverCount() == 0, @"player-state weak observer released");
        post(SGTranslatedTitleDidChangeNotification, @"B");
        post(SGTitleTranslationSettingsDidChangeNotification, nil);
        printf("landscape title notifications: %d/%d passed\n", checked - failed, checked);
        fflush(stdout);
        exit(failed ? 1 : 0);
    });
}
static void edgeCases(void) {
    for (id uri in @[@"spotify:local:artist:album:song:123", @"spotify:episode:E", @42, NSNull.null]) {
        SGTitleHarnessState(uri == NSNull.null ? nil : uri, @"Local title", @"Local artist", NO);
        post(SGTranslatedTitleDidChangeNotification, @"B");
        post(SGTranslatedTitleDidChangeNotification, nil);
        textIs(@"Local title", @"Local artist", @"non-track metadata survives unrelated completions");
        post(SGTitleTranslationSettingsDidChangeNotification, nil);
        textIs(@"Local title", @"Local artist", @"settings preserve non-track metadata");
    }
    SGTitleHarnessClearState();
    post(SGTranslatedTitleDidChangeNotification, @"B");
    post(SGTitleTranslationSettingsDidChangeNotification, nil);
    textIs(@"Local title", @"Local artist", @"no player state leaves displayed metadata intact");
    SGTitleHarnessState(@"spotify:track:B", @"Song B", @"Artist B", NO);
    finish();
}
static void settingsAndPause(void) {
    SGTitleHarnessUseTranslations(NO);
    post(SGTitleTranslationSettingsDidChangeNotification, nil);
    textIs(@"Song B", @"Artist B", @"settings disable restores original metadata");
    controlsShown(NO);
    SGTitleHarnessUseTranslations(YES);
    post(SGTitleTranslationSettingsDidChangeNotification, nil);
    textIs(@"번역 B", @"가수 B", @"settings re-enable restores cached translation");
    controlsShown(NO);
    SGTitleHarnessState(@"spotify:track:B", @"Song B", @"Artist B", YES);
    SGTitleHarnessAnswer(@"B", @"Paused translation", @"Paused artist");
    post(SGTranslatedTitleDidChangeNotification, @"B");
    textIs(@"Paused translation", @"Paused artist", @"paused track receives translated metadata");
    post(SGTitleTranslationSettingsDidChangeNotification, nil);
    textIs(@"Paused translation", @"Paused artist", @"paused settings retain translated metadata");
    edgeCases();
}
static void afterVisibleCompletion(void) {
    textIs(@"번역 A", @"가수 A", @"asynchronous translation updates displayed metadata");
    controlsShown(YES);
    post(SGTranslatedTitleDidChangeNotification, @"unrelated");
    post(SGTranslatedTitleDidChangeNotification, nil);
    post(SGTranslatedTitleDidChangeNotification, @17);
    textIs(@"번역 A", @"가수 A", @"irrelevant event objects leave metadata intact");
    [screen setControlsShown:NO];
    SGTitleHarnessState([NSURL URLWithString:@"spotify:track:B"], @"Song B", @"Artist B", NO);
    textIs(@"Song B", @"Artist B", @"player-state observer changes to track B");
    SGTitleHarnessAnswer(@"A", @"Stale A", @"Stale artist A");
    asyncTitle(@"A", ^{
        textIs(@"Song B", @"Artist B", @"late previous-track completion cannot replace B");
        controlsShown(NO);
        SGTitleHarnessAnswer(@"B", @"번역 B", @"가수 B");
        asyncTitle(@"B", ^{
            textIs(@"번역 B", @"가수 B", @"current NSURL track receives asynchronous metadata");
            controlsShown(NO);
            settingsAndPause();
        });
    });
}
static void runChecks(void) {
    SGTitleHarnessState(@"spotify:track:A", @"Song A", @"Artist A", NO);
    screen = [SGRLandscapeLyricsController new];
    [screen loadViewIfNeeded];
    screen.view.frame = CGRectMake(0, 0, 844, 390);
    [screen.view layoutIfNeeded];
    textIs(@"Song A", @"Artist A", @"viewDidLoad displays original metadata");
    SGTitleHarnessAnswer(@"A", @"번역 A", @"가수 A");
    textIs(@"Song A", @"Artist A", @"provider answer alone cannot update labels before notification");
    asyncTitle(@"A", ^{ afterVisibleCompletion(); });
}
static void coldPlayerTitle(void) {
    SGTitleHarnessState(@"spotify:track:cold", @"Song - Live", @"Band", NO);
    UILabel *title = [UILabel new];
    title.accessibilityIdentifier = @"now-playing-title-label";
    title.text = @"Song - Live";
    UIView *unit = [UIView new];
    [unit addSubview:title];
    SGRShownTitleWatch(unit);
    HARNESS_CHECK([title.text isEqual:@"Song - Live"]);
    SGTitleHarnessSimplify(YES);
    post(SGSimplifyTitlesDidChangeNotification, nil);
    dispatch_async(dispatch_get_main_queue(), ^{
        if (![title.text isEqual:@"Song"]) HARNESS_FAIL(@"Enabling simplification did not refresh the player's title");
        SGTitleHarnessSimplify(NO);
        post(SGSimplifyTitlesDidChangeNotification, nil);
        dispatch_async(dispatch_get_main_queue(), ^{
            HARNESS_CHECK([title.text isEqual:@"Song - Live"]);
            SGTitleHarnessAnswer(@"cold", @"Translated song", @"Band");
            SGTitleHarnessUseTranslations(YES);
            post(SGTitleTranslationSettingsDidChangeNotification, nil);
            dispatch_async(dispatch_get_main_queue(), ^{
                HARNESS_CHECK([title.text isEqual:@"Translated song"]);
                runChecks();
            });
        });
    });
}
@interface SGTitleCheckApp : UIResponder <UIApplicationDelegate>
@end
@implementation SGTitleCheckApp
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 15 * NSEC_PER_SEC), dispatch_get_global_queue(0, 0), ^{
        fputs("FAIL landscape title checks timed out\n", stderr);
        exit(1);
    });
    dispatch_async(dispatch_get_main_queue(), ^{ coldPlayerTitle(); });
    return YES;
}
@end
@interface SGTitleCheckScene : UIResponder <UIWindowSceneDelegate>
@end
@implementation SGTitleCheckScene
@end
int main(int argc, char **argv) {
    @autoreleasepool { return UIApplicationMain(argc, argv, nil, NSStringFromClass(SGTitleCheckApp.class)); }
}
