// Real ConnectionTestSettings.m, SGPage, UIKit and UIAlertController; fake backend/presentation boundary.
#import <UIKit/UIKit.h>
#import "Settings/SGModPage.h"
#import "Settings/SGPageStyle.h"
#import "Shared/LyricsTranslation/ConnectionTest.h"
#import "Shared/LyricsTranslation/LyricsTranslation.h"

static int checks, failures;
static NSUInteger starts, cancellations, presentations;
static BOOL hasKey = YES, refuseHandle, synchronousReply;
static NSString *target = @"ko";
static UIViewController *topController;
static UIAlertController *lastAlert;
static UIWindow *window;
static void check(BOOL ok, NSString *label) {
    printf("%s %s\n", ok ? "PASS" : "FAIL", label.UTF8String);
    checks++; if (!ok) failures++;
}
@implementation SGModRow
@end
// The report is a plain value object; its parser/default lives in ConnectionTest.m, which belongs to the
// transport harness (lyrics-translation/build.sh --connection-only). This UI check only moves reports around.
@implementation SGTranslationConnectionReport
@end
SGModRow *SGStatActionRow(NSString *title, NSString *subtitle, NSString *(^value)(void), void (^action)(void)) {
    SGModRow *row = [SGModRow new]; row.title = title; row.subtitle = subtitle;
    row.value = value; row.action = action; return row;
}
BOOL SGOpenAIKeySet(void) { return hasKey; }
NSString *SGLyricsGeminiLanguage(void) { return target; }
UIViewController *SGTopController(void) { return topController; }
UIColor *SGPageBackground(void) { return UIColor.blackColor; }
void SGPresentDark(UIViewController *controller) { controller.overrideUserInterfaceStyle = UIUserInterfaceStyleDark; }
NSNotificationName const SGLyricsTranslationsDidChangeNotification = @"FixtureTranslationsChanged";
NSNotificationName const SGLyricsTranslationServiceSettingsDidChangeNotification = @"FixtureServiceSettingsChanged";

@interface SGTranslationConnectionTest ()
@property (nonatomic, copy) void (^reply)(SGTranslationConnectionReport *);
@property NSUInteger cancelCalls;
@end
@implementation SGTranslationConnectionTest
- (void)cancel { self.cancelCalls++; cancellations++; }
@end
static SGTranslationConnectionTest *lastTest;
static SGConnectionTestKind lastKind;
static SGTranslationConnectionReport *passingReport(SGConnectionTestKind kind);
static SGTranslationConnectionReport *failingReport(void);
SGTranslationConnectionTest *SGTestOpenAIConnection(SGConnectionTestKind kind, void (^done)(SGTranslationConnectionReport *)) {
    check(NSThread.isMainThread, @"backend starts on main"); starts++; lastKind = kind;
    if (refuseHandle) return nil;
    lastTest = [SGTranslationConnectionTest new]; lastTest.reply = done;
    if (synchronousReply) done(passingReport(kind));
    return lastTest;
}
// Safe diagnostic lines as the backend builds them: a stage, an HTTP status and whether anything was sent.
// Model names and free-form error domains are deliberately absent, as are keys, addresses and bodies.
static NSString *const kModelsPassDiagnostic = @"stage=models http=200 sent=yes";
static NSString *const kTranslationPassDiagnostic = @"stage=translation http=200 sent=yes";
static NSString *const kFailureDiagnostic = @"stage=authentication http=401 sent=yes";
static SGTranslationConnectionReport *failingReport(void) {
    SGTranslationConnectionReport *r = [SGTranslationConnectionReport new];
    r.stage = SGConnectionCheckAuthentication;
    r.reachable = SGConnectionFactYes;
    r.authenticated = SGConnectionFactNo;
    r.problem = @"The service turned the key down.";
    r.diagnostic = kFailureDiagnostic;
    return r;
}
// Success reports carry the evidenced fact for their kind and no problem. They deliberately hold no sample text:
// the report has no such field, and the UI must show the fixed sentence instead of any returned content.
static SGTranslationConnectionReport *passingReport(SGConnectionTestKind kind) {
    SGTranslationConnectionReport *r = [SGTranslationConnectionReport new];
    r.reachable = r.authenticated = SGConnectionFactYes;
    if (kind == SGConnectionTestTranslation) {
        r.stage = SGConnectionCheckTranslation;
        r.translated = SGConnectionFactYes;
        r.diagnostic = kTranslationPassDiagnostic;
    } else {
        r.stage = SGConnectionCheckModels;
        r.models = SGConnectionFactYes;
        r.diagnostic = kModelsPassDiagnostic;
    }
    return r;
}
// An arbitrary report with no problem but no evidenced fact must not count as success.
static SGTranslationConnectionReport *unprovenReport(SGConnectionTestKind kind) {
    SGTranslationConnectionReport *r = [SGTranslationConnectionReport new];
    r.stage = kind == SGConnectionTestTranslation ? SGConnectionCheckTranslation : SGConnectionCheckModels;
    r.reachable = SGConnectionFactUnknown;
    r.authenticated = SGConnectionFactUnknown;
    r.models = SGConnectionFactUnknown;
    r.translated = SGConnectionFactUnknown;
    r.diagnostic = @"stage=unknown http=none sent=yes";
    return r;
}
// Count actual presentation requests and inspect the real UIAlertController, without animation timing.
@interface CheckPage : SGPage
@property (nonatomic, strong) UIViewController *cover;
@end
@implementation CheckPage
- (void)presentViewController:(UIViewController *)controller animated:(BOOL)animated completion:(void (^)(void))completion {
    check([controller isKindOfClass:UIAlertController.class], @"production presents a real UIAlertController");
    presentations++; lastAlert = (UIAlertController *)controller;
    if (completion) completion();
}
- (UIViewController *)presentedViewController { return self.cover; }
@end
static void post(NSNotificationName name) { [NSNotificationCenter.defaultCenter postNotificationName:name object:nil]; }
static void reset(void) { post(SGLyricsTranslationServiceSettingsDidChangeNotification); lastAlert = nil; }
static CheckPage *visiblePage(void) {
    CheckPage *page = [[CheckPage alloc] initWithStyle:UITableViewStyleInsetGrouped];
    window.rootViewController = page;
    [page loadViewIfNeeded]; [window makeKeyAndVisible];
    [page.view layoutIfNeeded]; topController = page;
    return page;
}
static void runChecks(void) {
    window = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, 600, 800)];
    CheckPage *page = visiblePage();
    check(NSThread.isMainThread && page.view.window == window && page.overrideUserInterfaceStyle == UIUserInterfaceStyleDark,
          @"real SGPage is attached to a UIKit window with dark appearance");
    SGModRow *modelsRow = SGOpenAIConnectionTestRow();
    SGModRow *translationRow = SGOpenAITranslationTestRow();
    check(modelsRow.action && modelsRow.value && !modelsRow.page && translationRow.action && translationRow.value && !translationRow.page,
          @"production returns two explicit action rows");
    check(modelsRow != translationRow && ![modelsRow.title isEqual:translationRow.title], @"the checks are separate rows");
    check([modelsRow.value() isEqual:@"Not tested"] && [translationRow.value() isEqual:@"Not tested"] && starts == 0,
          @"creating/reading rows starts no request");
    check([modelsRow.subtitle containsString:@"model list"] && [modelsRow.subtitle containsString:@"without sending a translation request"] &&
          [translationRow.subtitle containsString:@"short sentence"] && [translationRow.subtitle containsString:@"charge"],
          @"rows explain what each sends and the possible charge, and the model row makes no cost claim");
    for (int i = 0; i < 5; i++) { SGOpenAIConnectionTestRow().value(); SGOpenAITranslationTestRow().value(); }
    check(starts == 0, @"recreating and redrawing settings never auto-tests");
    hasKey = NO;
    check([modelsRow.value() isEqual:@"API key required"] && [translationRow.value() isEqual:@"API key required"],
          @"missing key is visible on both rows instead of hiding them");
    modelsRow.action(); translationRow.action();
    check(starts == 2, @"a tap without a key still asks the backend, which reports a configuration failure");
    hasKey = YES;
    reset();
    modelsRow.action(); SGTranslationConnectionTest *models = lastTest;
    check(starts == 3 && lastKind == SGConnectionTestModels && [modelsRow.value() isEqual:@"Testing… · Cancel"],
          @"explicit tap starts the model check once and exposes Cancel");
    check([translationRow.value() isEqual:@"Not tested"], @"the other row is unaffected");
    modelsRow.value(); modelsRow.action();
    check(starts == 3 && models.cancelCalls == 1 && [modelsRow.value() isEqual:@"Not tested"],
          @"second tap cancels exactly once without a duplicate start");
    NSUInteger shown = presentations;
    models.reply(passingReport(SGConnectionTestModels));
    check([modelsRow.value() isEqual:@"Not tested"] && presentations == shown, @"cancelled late callback stays silent");

    modelsRow.action(); lastTest.reply(passingReport(SGConnectionTestModels));
    check([modelsRow.value() isEqual:@"✓ Works"] && presentations == shown + 1, @"model check success shows checkmark and one alert");
    check([lastAlert.title isEqual:@"Connection and model list work"] &&
          [lastAlert.message containsString:@"does not verify the key"] &&
          [lastAlert.message containsString:@"does not verify the key or prove every model can translate"] &&
          ![lastAlert.message containsString:@"accepted the key"],
          @"model success says a readable list, not a verified key");
    check(lastAlert.overrideUserInterfaceStyle == UIUserInterfaceStyleDark && lastAlert.actions.count == 3 &&
          [lastAlert.actions[0].title isEqual:@"Copy details"] && [lastAlert.actions[1].title isEqual:@"Test Again"] &&
          [lastAlert.actions[2].title isEqual:@"OK"], @"result alert is dark with Copy details/Test Again/OK");
    check([lastAlert.message containsString:@"stage=models"] && [lastAlert.message containsString:@"http=200"],
          @"the alert shows the safe stage/status details it would copy");
    // The copied text is the report's diagnostic line, which the transport harness checks for secrets.
    NSString *copied = kModelsPassDiagnostic;
    check([copied isEqual:@"stage=models http=200 sent=yes"], @"copied details are the safe stage/status line");
    for (NSString *secret in @[@"Bearer", @"fixture-key", @"100.97.8.81", @"/models", @"Hello", @"Lyrics", @"offline-model",
                               @"NSURLErrorDomain", @"NSOSStatusErrorDomain"]) {
        check([copied rangeOfString:secret].location == NSNotFound, [@"copied details exclude " stringByAppendingString:secret]);
    }
    shown = presentations;
    modelsRow.action(); check(presentations == shown + 1, @"tapping cached result opens it without a request");

    reset(); translationRow.action(); SGTranslationConnectionTest *sample = lastTest;
    check(lastKind == SGConnectionTestTranslation && [translationRow.value() isEqual:@"Testing… · Cancel"] && [modelsRow.value() isEqual:@"Not tested"],
          @"translation check is a separate explicit tap");
    sample.reply(passingReport(SGConnectionTestTranslation));
    check([translationRow.value() isEqual:@"✓ Works"] && [lastAlert.title isEqual:@"Translation works"] &&
          [lastAlert.message containsString:@"correctly formatted response to the test translation request"],
          @"translation success is the fixed sentence, not returned content");
    check(![lastAlert.message containsString:target] && ![lastAlert.message containsString:@"The sky is blue"] &&
          ![lastAlert.message containsString:@"offline-model"] && ![lastAlert.message containsString:@"100.97.8.81"],
          @"translation success alert shows no returned sample text, model or address");
    // A report with no problem but also no evidenced fact is a failure, never a success.
    reset(); translationRow.action(); lastTest.reply(unprovenReport(SGConnectionTestTranslation));
    check([translationRow.value() isEqual:@"✕ Failed"] && [lastAlert.message containsString:@"did not translate"] &&
          ![lastAlert.message containsString:@"correctly formatted"],
          @"unproven translation report cannot claim a formatted answer");
    reset(); modelsRow.action(); lastTest.reply(unprovenReport(SGConnectionTestModels));
    check([modelsRow.value() isEqual:@"✕ Failed"] && ![lastAlert.message containsString:@"readable model list"],
          @"unproven model report cannot claim a readable model list");

    reset(); modelsRow.action(); lastTest.reply(failingReport());
    check([modelsRow.value() isEqual:@"✕ Failed"] && [lastAlert.title isEqual:@"Connection check failed"] &&
          [lastAlert.message containsString:@"The service turned the key down."], @"failure uses the safe backend message");
    check([lastAlert.message containsString:@"stage=authentication"], @"the alert carries safe stage/status details");
    reset(); translationRow.action(); lastTest.reply(failingReport());
    check([translationRow.value() isEqual:@"✕ Failed"] && [modelsRow.value() isEqual:@"Not tested"],
          @"a failed translation check leaves the model result alone");

    for (NSNumber *languageChange in @[@NO, @YES]) {
        reset(); modelsRow.action(); SGTranslationConnectionTest *old = lastTest;
        if (languageChange.boolValue) target = [target isEqual:@"ko"] ? @"ja" : @"ko";
        post(languageChange.boolValue ? SGLyricsTranslationsDidChangeNotification : SGLyricsTranslationServiceSettingsDidChangeNotification);
        check(old.cancelCalls == 1 && [modelsRow.value() isEqual:@"Not tested"], @"service/target change cancels pending request and clears status");
        modelsRow.action(); SGTranslationConnectionTest *current = lastTest;
        shown = presentations; old.reply(passingReport(SGConnectionTestModels));
        check([modelsRow.value() isEqual:@"Testing… · Cancel"] && presentations == shown && current.cancelCalls == 0,
              @"old callback cannot overwrite or cancel replacement test");
        post(SGLyricsTranslationsDidChangeNotification);
        check([modelsRow.value() isEqual:@"Testing… · Cancel"] && current.cancelCalls == 0, @"unrelated notification leaves pending test alive");
        current.reply(passingReport(SGConnectionTestModels));
        check([modelsRow.value() isEqual:@"✓ Works"] && [lastAlert.title isEqual:@"Connection and model list work"], @"replacement test still completes normally");
        if (languageChange.boolValue) target = [target isEqual:@"ko"] ? @"ja" : @"ko";
        post(languageChange.boolValue ? SGLyricsTranslationsDidChangeNotification : SGLyricsTranslationServiceSettingsDidChangeNotification);
        check([modelsRow.value() isEqual:@"Not tested"], @"service/target change also invalidates cached result");
    }
    // Closing a global-state row does not cancel the bounded backend; only popup presentation is suppressed.
    reset(); modelsRow.action(); SGTranslationConnectionTest *closed = lastTest; shown = presentations;
    window.rootViewController = [UIViewController new]; topController = window.rootViewController;
    check(page.view.window == nil, @"closed page is genuinely detached from window");
    closed.reply(passingReport(SGConnectionTestModels));
    check(closed.cancelCalls == 0 && presentations == shown && [modelsRow.value() isEqual:@"✓ Works"], @"closed page completes into cache without popping an alert");
    page = visiblePage(); NSUInteger before = starts; modelsRow.action();
    check(starts == before && [lastAlert.message containsString:@"does not verify the key"], @"returning to settings can inspect cached result without resending");
    reset(); modelsRow.action(); shown = presentations; topController = [UIViewController new];
    lastTest.reply(passingReport(SGConnectionTestModels));
    check(presentations == shown && [modelsRow.value() isEqual:@"✓ Works"], @"attached page that is not top receives no popup");
    topController = page; reset(); page.cover = [UIViewController new]; modelsRow.action(); shown = presentations;
    lastTest.reply(passingReport(SGConnectionTestModels));
    check(presentations == shown && [modelsRow.value() isEqual:@"✓ Works"], @"existing modal suppresses automatic popup"); page.cover = nil;
    reset(); refuseHandle = YES; modelsRow.action(); refuseHandle = NO;
    check([modelsRow.value() isEqual:@"Not tested"], @"nil backend handle does not leave UI stuck testing");
    synchronousReply = YES; modelsRow.action(); synchronousReply = NO;
    check([modelsRow.value() isEqual:@"✓ Works"], @"synchronous backend completion does not leave a running state");
    SGTranslationConnectionTest *finished = lastTest; reset();
    check(finished.cancelCalls == 0, @"synchronous completion does not retain a finished handle for cancellation");
    printf("connection test settings: %d/%d passed; %lu starts, %lu cancels\n", checks - failures, checks,
           (unsigned long)starts, (unsigned long)cancellations); fflush(stdout); exit(failures ? 1 : 0);
}
@interface CheckApp : UIResponder <UIApplicationDelegate>
@end
@implementation CheckApp
- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)options {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 120 * NSEC_PER_SEC), dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
        fputs("FAIL UIKit check timed out\n", stderr); exit(1);
    });
    dispatch_async(dispatch_get_main_queue(), ^{ runChecks(); }); return YES;
}
@end
@interface CheckScene : UIResponder <UIWindowSceneDelegate>
@end
@implementation CheckScene
@end
int main(int argc, char **argv) {
    @autoreleasepool { return UIApplicationMain(argc, argv, nil, NSStringFromClass(CheckApp.class)); }
}
