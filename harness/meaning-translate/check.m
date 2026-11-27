// The meaning sheet's Translate action (Redesigned/Lyrics/MeaningSheet.m) and the shared operation it uses for text
// that is not a song's lyrics (Shared/LyricsTranslation/TextTranslation.m), as a Mac Catalyst app; no simulator.
//
// The translation services are doubles: each records what was sent and answers when the check says so, so a request
// in flight can be overtaken, dismissed or repeated. Everything else is the tweak's own code, including the sheet's
// layout and its sheet-local cache.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "Shared/LyricsMeanings/Meanings.h"
#import "Shared/LyricsTranslation/LyricsTranslation.h"
#import "Shared/Lyrics/Lyrics.h"
#import "Shared/LyricsTranslation/AIServicesInternal.h"
#import "../harness-fail.h"

static NSUInteger sg_checks;
#define CHECK(condition, ...) do { sg_checks++; if (!(condition)) HARNESS_FAIL(__VA_ARGS__); } while (0)

@implementation SGLyricsMeaning
@end

#pragma mark - the services, as doubles

// The text the sheet sent, in the order it sent it, and the answers still to give.
static NSMutableArray<NSArray<NSString *> *> *sg_sent;
static NSMutableArray<void (^)(NSArray<NSString *> *, NSString *)> *sg_pending;
static NSString *sg_language = @"ko";
static BOOL sg_gemini, sg_deepl, sg_google, sg_bing, sg_claude, sg_openai, sg_onDevice;
static BOOL sg_shouldFail, sg_hold;
static NSUInteger sg_savedTranslations;
static NSString *sg_service, *sg_sentLanguage;
static NSURL *sg_openedURL;

@interface UIApplication (MeaningTranslateCheck)
- (void)meaningCheckOpenURL:(NSURL *)url options:(NSDictionary *)options completionHandler:(void (^)(BOOL))completion;
@end
@implementation UIApplication (MeaningTranslateCheck)
- (void)meaningCheckOpenURL:(NSURL *)url options:(NSDictionary *)options completionHandler:(void (^)(BOOL))completion {
    sg_openedURL = url;
    if (completion) completion(YES);
}
@end

// `sg_hold` keeps the answer for the check to give, so an answer can arrive while another annotation is shown.
static void answer(NSArray<NSString *> *texts, void (^done)(NSArray<NSString *> *, NSString *)) {
    [sg_sent addObject:texts];
    if (sg_hold) { [sg_pending addObject:[done copy]]; return; }
    if (sg_shouldFail) { dispatch_async(dispatch_get_main_queue(), ^{ done(nil, @"offline"); }); return; }
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *text in texts) [out addObject:[@"번역: " stringByAppendingString:text]];
    dispatch_async(dispatch_get_main_queue(), ^{ done(out, nil); });
}

// Hands the first held answer over, as the service would.
static void releaseHeld(BOOL failing) {
    void (^done)(NSArray<NSString *> *, NSString *) = sg_pending.firstObject;
    NSArray<NSString *> *texts = sg_sent[sg_sent.count - sg_pending.count];
    if (done) [sg_pending removeObjectAtIndex:0];
    if (!done) return;
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *text in texts) [out addObject:[@"번역: " stringByAppendingString:text]];
    dispatch_async(dispatch_get_main_queue(), ^{ done(failing ? nil : out, failing ? @"offline" : nil); });
}

// The switches the shared operation reads: the two web services are off until switched on, the on-device translator
// is on unless switched off, as on the phone.
BOOL SGFlag(NSString *key, BOOL fallback) {
    if ([key isEqualToString:SGKeyLyricsGoogleTranslate]) return sg_google;
    if ([key isEqualToString:SGKeyLyricsBingTranslate]) return sg_bing;
    if ([key isEqualToString:SGKeyLyricsTranslateOnDevice]) return fallback;
    return fallback;
}
NSString *SGL(NSString *key, NSString *english) { return english; }
void SGLogLong(NSString *tag, NSString *text) {}

NSString *SGLyricsGeminiLanguage(void) { return sg_language; }
NSNotificationName const SGLyricsTranslationsDidChangeNotification = @"harness.translationsDidChange";
NSNotificationName const SGLyricsTranslationServiceSettingsDidChangeNotification = @"harness.serviceSettingsDidChange";
UIViewController *SGTopController(void) { return nil; }
void SGPresentDark(UIViewController *controller) {
    controller.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
}
UIColor *SGRPrimary(void) { return UIColor.whiteColor; }
UIColor *SGRTertiary(void) { return UIColor.grayColor; }
UIColor *SGRAccent(void) { return UIColor.systemGreenColor; }
UIColor *SGRAccentColor(void) { return nil; }

// A lyric translation is saved for a song and a language; an explanation must never be one.
void SGLyricsSaveTranslation(NSString *track, NSString *language, NSArray<SGKaraokeLine *> *lines) { sg_savedTranslations++; }

NSString *SGLyricsAILanguageName(NSString *tag) {
    if (![tag isKindOfClass:NSString.class] || !tag.length || tag.length > 64) return nil;
    return [[NSLocale localeWithLocaleIdentifier:@"en"] localizedStringForLocaleIdentifier:tag] ?: tag;
}
NSUInteger SGLyricsAIProseOutputTokens(SGLyricsAI service) { return 8192; }

BOOL SGGeminiKeySet(void) { return sg_gemini; }
BOOL SGClaudeKeySet(void) { return sg_claude; }
BOOL SGOpenAIKeySet(void) { return sg_openai; }
BOOL SGDeepLKeySet(void) { return sg_deepl; }
NSString *SGBingTargetLanguage(NSString *tag) { return sg_bing ? tag : nil; }
NSString *SGGoogleTargetLanguage(NSString *tag) { return sg_google ? tag : nil; }
NSString *SGDeepLTargetLanguage(NSString *tag) { return sg_deepl ? tag : nil; }

void SGBingTranslateTexts(NSArray<NSString *> *texts, NSString *languageTag, void (^done)(NSArray<NSString *> *, NSString *)) {
    sg_service = @"bing"; sg_sentLanguage = languageTag;
    answer(texts, done);
}
void SGGoogleTranslateTexts(NSArray<NSString *> *texts, NSString *languageTag, void (^done)(NSArray<NSString *> *, NSString *)) {
    sg_service = @"google"; sg_sentLanguage = languageTag;
    answer(texts, done);
}
void SGDeepLTranslateTexts(NSArray<NSString *> *texts, NSString *languageTag, void (^done)(NSArray<NSString *> *, NSString *)) {
    sg_service = @"deepl"; sg_sentLanguage = languageTag;
    answer(texts, done);
}
// An AI service is asked with a prose instruction and a prompt, and answers JSON strings.
static NSString *sg_prompt, *sg_system;
void SGLyricsAIAskWithFormat(SGLyricsAI service, NSString *system, NSString *prompt, NSUInteger count, SGLyricsReplyFormat format,
                             void (^done)(NSArray<NSString *> *, NSString *)) {
    sg_system = system;
    sg_prompt = prompt;
    sg_service = service == SGLyricsAIGemini ? @"gemini" : service == SGLyricsAIClaude ? @"claude" : @"openai";
    CHECK(format == SGLyricsReplyProse && count == 1, @"prose did not ask for one strict JSON segment");
    NSMutableArray *texts = [NSMutableArray array];
    NSRange start = [prompt rangeOfString:@"\n\n"];
    if (start.location != NSNotFound) {
        NSString *json = [prompt substringFromIndex:NSMaxRange(start)];
        NSArray *parsed = [NSJSONSerialization JSONObjectWithData:[json dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
        if ([parsed isKindOfClass:NSArray.class]) texts = [parsed mutableCopy];
    }
    answer(texts, done);
}

@implementation SGOnDeviceTranslation
+ (BOOL)translationAvailable { return sg_onDevice; }
+ (BOOL)appleIntelligenceAvailable:(NSString *)languageTag { return NO; }
+ (void)translate:(NSArray<NSString *> *)lines to:(NSString *)languageTag done:(void (^)(NSArray<NSString *> *, NSString *))done {
    sg_service = @"apple"; sg_sentLanguage = languageTag;
    answer(lines, done);
}
+ (void)translate:(NSArray<NSString *> *)lines to:(NSString *)languageTag from:(UIView *)view done:(void (^)(NSArray<NSString *> *, NSString *))done {
    CHECK(view != nil, @"explicit Apple translation cannot prepare missing languages without its view");
    sg_service = @"apple"; sg_sentLanguage = languageTag;
    answer(lines, done);
}
+ (void)translateWithAppleIntelligence:(NSArray<NSString *> *)lines to:(NSString *)languageTag song:(NSString *)song
                              progress:(void (^)(NSArray<NSString *> *))progress done:(void (^)(NSArray<NSString *> *, NSString *))done {
    answer(lines, done);
}
+ (void)openTranslateSettings {}
@end

// The sheet, as the lyrics view makes it.
@interface SGRMeaningSheet : UIViewController
- (instancetype)initWithLine:(NSString *)lineText meanings:(NSArray<SGLyricsMeaning *> *)meanings;
@end

#pragma mark - reading the sheet

static UIWindow *sg_window;

static SGRMeaningSheet *sheetFor(NSUInteger count, NSString *line) {
    NSMutableArray<SGLyricsMeaning *> *meanings = [NSMutableArray array];
    for (NSUInteger i = 0; i < count; i++) {
        SGLyricsMeaning *meaning = [SGLyricsMeaning new];
        meaning.fragment = [NSString stringWithFormat:@"word %lu", (unsigned long)i];
        meaning.body = [NSString stringWithFormat:@"Explanation %lu long enough to read.", (unsigned long)i];
        meaning.author = i == 1 ? SGLyricsMeaningByEditors : SGLyricsMeaningByArtist;
        meaning.url = [NSString stringWithFormat:@"https://genius.com/annotations/%lu", (unsigned long)i];
        [meanings addObject:meaning];
    }
    SGRMeaningSheet *sheet = [[SGRMeaningSheet alloc] initWithLine:line meanings:meanings];
    UIViewController *root = [UIViewController new];
    sg_window.rootViewController = root;
    [root addChildViewController:sheet];
    sheet.view.frame = CGRectMake(0, 0, 390, 500);
    [root.view addSubview:sheet.view];
    [sheet didMoveToParentViewController:root];
    [sheet.view layoutIfNeeded];
    return sheet;
}

static UIButton *button(UIViewController *sheet, NSString *ivar) { return [sheet valueForKey:ivar]; }
static UIButton *translateButton(UIViewController *sheet) { return button(sheet, @"translate"); }
static UILabel *label(UIViewController *sheet, NSString *ivar) { return [sheet valueForKey:ivar]; }
static UITextView *body(UIViewController *sheet) { return [sheet valueForKey:@"body"]; }
static NSString *bodyText(UIViewController *sheet) { return body(sheet).attributedText.string; }
static void tap(UIViewController *sheet, NSString *ivar) {
    [[sheet valueForKey:ivar] sendActionsForControlEvents:UIControlEventTouchUpInside];
}

// A run loop turn, so a double's answer on the main queue runs.
// Runs the run loop until `done` says so, or the wait runs out (a check then fails on what it expected).
static void waitUntil(BOOL (^done)(void)) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:60];
    while (!done() && deadline.timeIntervalSinceNow > 0) [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    [sg_window.rootViewController.view layoutIfNeeded];
}

// Every queued block has run: a block queued now runs after those already queued, and the run loop is pumped until
// it has. The sheet sends on the main queue and a double answers on it too, so two hops are enough.
static void settle(void) {
    __block BOOL drained = NO;
    // Queued from a block on the main queue, the marker runs after anything that block's turn queued too.
    dispatch_async(dispatch_get_main_queue(), ^{
        dispatch_async(dispatch_get_main_queue(), ^{ drained = YES; });
    });
    waitUntil(^BOOL { return drained; });
    [sg_window.rootViewController.view layoutIfNeeded];
}

static void reset(void) {
    sg_sent = [NSMutableArray array];
    sg_pending = [NSMutableArray array];
    sg_shouldFail = sg_hold = NO;
    sg_gemini = sg_deepl = sg_google = sg_bing = sg_claude = sg_openai = sg_onDevice = NO;
    sg_language = @"ko";
    sg_prompt = sg_system = nil;
    sg_savedTranslations = 0;
    sg_service = sg_sentLanguage = nil;
    sg_openedURL = nil;
}

#pragma mark - the checks

// Nothing is offered without a service the user set up, and everything Genius said stays as it was.
static void checkOffered(void) {
    reset();
    SGRMeaningSheet *sheet = sheetFor(2, @"the line");
    UIButton *translate = translateButton(sheet);
    CHECK(translate.isHidden, @"Translate is offered with no service set up");
    CHECK([label(sheet, @"status").text length] == 0, @"a status line is shown with nothing translated");
    CHECK([bodyText(sheet) isEqualToString:@"Explanation 0 long enough to read."], @"the explanation is Genius's own: %@", bodyText(sheet));
    CHECK([button(sheet, @"author").configuration.title isEqualToString:@"From the artist"], @"the author badge is Genius's own");
    CHECK([label(sheet, @"count").text isEqualToString:@"Genius · 1 of 2"], @"the count is unchanged");
    CHECK(!button(sheet, @"open").isHidden, @"View on Genius is offered for an annotation with a link");
    CHECK([sg_sent count] == 0, @"opening the sheet asked a service for the explanation");
    tap(sheet, @"translate");
    settle();
    CHECK(sg_sent.count == 0, @"a stale action sent text without a service");

    // A service that takes the target language offers it; one that is switched off does not.
    sg_google = YES;
    sheet = sheetFor(1, @"the line");
    settle();
    CHECK(sg_sent.count == 0, @"opening an enabled sheet sent the explanation without a tap");
    CHECK(!translateButton(sheet).isHidden, @"Translate is not offered although Google Translate is on");
    CHECK(!button(sheet, @"next").isHidden == NO, @"Next is offered for a single annotation");
    CHECK([label(sheet, @"count").text isEqualToString:@"Genius"], @"one annotation says Genius alone");
}

// The explanation and the line it quotes go once, on the tap alone; the answer shows under them as a translation.
static void checkTranslate(void) {
    reset();
    sg_google = YES;
    SGRMeaningSheet *sheet = sheetFor(2, @"the line");
    UIButton *translate = translateButton(sheet);
    CHECK([[translate.configuration.title copy] isEqualToString:@"Translate"], @"the action does not say Translate");
    tap(sheet, @"translate");
    settle();
    settle();
    CHECK([sg_sent count] == 1, @"the tap sent %lu requests", (unsigned long)sg_sent.count);
    CHECK(([sg_sent[0] isEqualToArray:@[@"Explanation 0 long enough to read.", @"the line"]]),
          @"the request carried %@, not the explanation and its quoted line", sg_sent[0]);
    settle();
    CHECK([bodyText(sheet) isEqualToString:@"번역: Explanation 0 long enough to read."], @"the translation is not shown: %@", bodyText(sheet));
    CHECK([label(sheet, @"quote").text isEqualToString:@"“번역: the line”"], @"the quoted line is not translated");
    CHECK([[translate.configuration.title copy] isEqualToString:@"Show Original"], @"the action does not offer Show Original");
    CHECK([[label(sheet, @"status").text copy] isEqualToString:@"Translated"], @"the sheet does not say the words are translated");
    CHECK([button(sheet, @"author").configuration.title isEqualToString:@"From the artist"], @"the author badge changed with the translation");
    CHECK([label(sheet, @"count").text isEqualToString:@"Genius · 1 of 2"], @"the Genius attribution changed with the translation");
    CHECK(!button(sheet, @"open").isHidden, @"View on Genius went with the translation");
    tap(sheet, @"open");
    CHECK([sg_openedURL.absoluteString isEqual:@"https://genius.com/annotations/0"], @"translation changed the Genius URL");
    CHECK(sg_savedTranslations == 0, @"an explanation was stored as a lyric translation");

    // Show Original brings Genius's own words back, and Translate again shows the kept translation: no second ask.
    tap(sheet, @"translate");
    CHECK([bodyText(sheet) isEqualToString:@"Explanation 0 long enough to read."], @"Show Original did not restore the explanation");
    CHECK([label(sheet, @"quote").text isEqualToString:@"“the line”"], @"Show Original did not restore the quoted line");
    CHECK([[translate.configuration.title copy] isEqualToString:@"Translate"], @"the action does not say Translate again");
    CHECK([label(sheet, @"status").text length] == 0, @"the sheet still calls the original translated");
    tap(sheet, @"translate");
    CHECK([sg_sent count] == 1, @"showing the kept translation asked again");
    CHECK([bodyText(sheet) isEqualToString:@"번역: Explanation 0 long enough to read."], @"the kept translation did not come back");
    CHECK(sg_savedTranslations == 0, @"showing the translation again saved a lyric translation");
}

// A second tap while the answer is on its way sends nothing; the answer shows when it comes.
static void checkDuplicateTaps(void) {
    reset();
    sg_gemini = YES;
    sg_hold = YES;
    SGRMeaningSheet *sheet = sheetFor(1, @"the line");
    tap(sheet, @"translate");
    tap(sheet, @"translate");
    tap(sheet, @"translate");
    settle();
    CHECK(sg_sent.count == 1, @"repeated taps sent %lu requests", (unsigned long)sg_sent.count);
    CHECK([sg_prompt containsString:@"explains a song"], @"the AI service was asked with a lyric instruction: %@", sg_prompt);
    releaseHeld(NO);
    settle();
    CHECK([bodyText(sheet) isEqual:@"Explanation 0 long enough to read."], @"a partial AI explanation was shown");
    releaseHeld(NO);
    settle();
    CHECK([bodyText(sheet) hasPrefix:@"번역: "], @"the answer did not show");
}

// A failure says so where the reader tapped, and the action stays for another try.
static void checkFailureAndRetry(void) {
    reset();
    sg_google = YES;
    sg_shouldFail = YES;
    SGRMeaningSheet *sheet = sheetFor(1, @"the line");
    tap(sheet, @"translate");
    settle();
    CHECK([[label(sheet, @"status").text copy] isEqualToString:@"Couldn't translate"], @"a failure is not reported: %@", label(sheet, @"status").text);
    CHECK([bodyText(sheet) isEqualToString:@"Explanation 0 long enough to read."], @"a failure replaced Genius's words");
    CHECK([[translateButton(sheet).configuration.title copy] isEqualToString:@"Translate"], @"a failure took the action away");
    sg_shouldFail = NO;
    tap(sheet, @"translate");
    settle();
    CHECK([sg_sent count] == 2, @"the retry did not ask again");
    CHECK([bodyText(sheet) hasPrefix:@"번역: "], @"the retry's answer did not show");
    CHECK([[label(sheet, @"status").text copy] isEqualToString:@"Translated"], @"the retry did not clear the failure: %@", label(sheet, @"status").text);
    CHECK(sg_savedTranslations == 0, @"a retried explanation was stored as a lyric translation");
}

// An answer that arrives while another annotation is shown redraws nothing; that annotation keeps its own words. The
// answer is still kept for the annotation it belongs to, so going back shows it without a second request.
static void checkSwitchedDuringRequest(void) {
    reset();
    sg_google = YES;
    sg_hold = YES;
    SGRMeaningSheet *sheet = sheetFor(2, @"the line");
    tap(sheet, @"translate");
    settle();
    CHECK(sg_sent.count == 1 && [sg_sent[0] count] == 2, @"the first request did not carry the explanation and its line");
    CHECK([label(sheet, @"count").text isEqualToString:@"Genius · 1 of 2"], @"Next moved before the answer came");
    tap(sheet, @"next");
    CHECK([label(sheet, @"count").text isEqualToString:@"Genius · 2 of 2"], @"Next did not move to the second annotation");
    UIScrollView *scroll = [sheet valueForKey:@"scroll"];
    [scroll setContentOffset:CGPointMake(0, 37) animated:NO];
    releaseHeld(NO);
    settle();
    CHECK(scroll.contentOffset.y == 37, @"a late answer reset the other annotation's reading position");
    CHECK([bodyText(sheet) isEqualToString:@"Explanation 1 long enough to read."],
          @"the first annotation's late answer was drawn under the second: %@", bodyText(sheet));
    CHECK([[translateButton(sheet).configuration.title copy] isEqualToString:@"Translate"], @"the second annotation says it was translated");
    CHECK([button(sheet, @"author").configuration.title isEqualToString:@"Genius editors"], @"the second annotation's badge is not its own");
    CHECK(!button(sheet, @"open").isHidden, @"View on Genius went with the previous annotation's answer");
    tap(sheet, @"open");
    CHECK([sg_openedURL.absoluteString isEqual:@"https://genius.com/annotations/1"], @"Next did not preserve the selected Genius URL");
    // Back to the first: its answer was kept, and nothing more was sent.
    tap(sheet, @"next");
    settle();
    CHECK([label(sheet, @"count").text isEqualToString:@"Genius · 1 of 2"], @"Next did not come back to the first annotation");
    CHECK([bodyText(sheet) hasPrefix:@"번역: Explanation 0"], @"the first annotation's kept translation did not show: %@", bodyText(sheet));
    CHECK(sg_sent.count == 1, @"going back to the answered annotation asked again");
}

// A target language of its own is a different answer: the kept one is not reused, and the service is asked for the new
// language.
static void checkLanguageChange(void) {
    reset();
    sg_google = YES;
    SGRMeaningSheet *sheet = sheetFor(1, @"the line");
    tap(sheet, @"translate");
    settle();
    CHECK([bodyText(sheet) hasPrefix:@"번역: "], @"the Korean answer did not show");
    tap(sheet, @"translate");
    CHECK([bodyText(sheet) isEqual:@"Explanation 0 long enough to read."], @"Show Original before language change failed");
    sg_language = @"fr";
    // The sheet reads the target language per call, as the lyrics view does: the Korean answer is not this one's.
    [NSNotificationCenter.defaultCenter postNotificationName:SGLyricsTranslationsDidChangeNotification object:nil];
    CHECK([bodyText(sheet) isEqualToString:@"Explanation 0 long enough to read."], @"another language kept the first language's answer");
    CHECK([[translateButton(sheet).configuration.title copy] isEqualToString:@"Translate"], @"another language still offers Show Original");
    NSUInteger before = sg_sent.count;
    tap(sheet, @"translate");
    settle();
    CHECK(sg_sent.count == before + 1, @"another target language reused the first answer");
    CHECK([sg_sentLanguage isEqual:@"fr"], @"the request did not use the new target language");
    CHECK([bodyText(sheet) hasPrefix:@"번역: "], @"the French answer did not show");
}

// Many annotations do not keep every answer forever; recent answers remain usable without another request.
static void checkCacheBounded(void) {
    reset();
    sg_google = YES;
    SGRMeaningSheet *sheet = sheetFor(100, @"the line");
    for (NSUInteger i = 0; i < 100; i++) {
        tap(sheet, @"translate");
        settle();
        if (i < 99) tap(sheet, @"next");
    }
    NSUInteger before = sg_sent.count;
    // The most recent answer stays cached through Show Original / Translate.
    tap(sheet, @"translate");
    tap(sheet, @"translate");
    CHECK(sg_sent.count == before, @"the latest answer was not retained");
    tap(sheet, @"next");
    CHECK([translateButton(sheet).configuration.title isEqual:@"Translate"], @"unbounded retention kept the oldest answer");
    tap(sheet, @"translate");
    settle();
    CHECK(sg_sent.count == before + 1, @"the evicted translation was not asked for again");
    CHECK(sg_savedTranslations == 0, @"a kept explanation was stored as a lyric translation");
}

// A sheet taken away while its answer is on its way shows nothing more and keeps nothing for the next one; the answer
// that comes late changes no other sheet.
static void checkDismissed(void) {
    reset();
    sg_google = YES;
    sg_hold = YES;
    SGRMeaningSheet *sheet = sheetFor(1, @"the line");
    tap(sheet, @"translate");
    settle();
    CHECK(sg_sent.count == 1, @"the tapped sheet sent nothing");
    [sheet willMoveToParentViewController:nil];
    [sheet.view removeFromSuperview];
    [sheet removeFromParentViewController];
    SGRMeaningSheet *fresh = sheetFor(1, @"the line");
    releaseHeld(NO);
    settle();
    CHECK([bodyText(fresh) isEqualToString:@"Explanation 0 long enough to read."], @"a late answer was drawn on another sheet: %@", bodyText(fresh));
    CHECK([bodyText(sheet) isEqualToString:@"Explanation 0 long enough to read."], @"a dismissed sheet drew its late answer");
    CHECK(sg_savedTranslations == 0, @"an explanation was stored as a lyric translation");

    // Isolate request ownership from UIKit's appearance-transition/autorelease lifetime.
    __weak SGRMeaningSheet *weakSheet;
    @autoreleasepool {
        SGLyricsMeaning *meaning = [SGLyricsMeaning new];
        meaning.body = @"A separately owned explanation.";
        SGRMeaningSheet *unowned = [[SGRMeaningSheet alloc] initWithLine:@"the line" meanings:@[meaning]];
        [unowned loadViewIfNeeded];
        weakSheet = unowned;
        tap(unowned, @"translate");
        settle();
    }
    CHECK(weakSheet == nil, @"the pending translation retained a dismissed sheet");
    releaseHeld(NO);
    settle();
}

static void checkLanguageDuringRequest(void) {
    reset(); sg_google = YES; sg_hold = YES;
    SGRMeaningSheet *sheet = sheetFor(1, @"the line");
    tap(sheet, @"translate"); settle();
    sg_language = @"fr";
    [NSNotificationCenter.defaultCenter postNotificationName:SGLyricsTranslationsDidChangeNotification object:nil];
    UIScrollView *scroll = [sheet valueForKey:@"scroll"];
    [scroll setContentOffset:CGPointMake(0, 37) animated:NO];
    releaseHeld(NO); settle();
    CHECK([bodyText(sheet) isEqual:@"Explanation 0 long enough to read."], @"late Korean answer replaced French original");
    CHECK(scroll.contentOffset.y == 37, @"late Korean answer redrew the French sheet");
    tap(sheet, @"translate"); settle();
    CHECK([sg_sentLanguage isEqual:@"fr"] && sg_sent.count == 2, @"French request not independent");
    releaseHeld(NO); settle();
}

static void checkContentIdentity(void) {
    reset(); sg_google = YES;
    SGRMeaningSheet *sheet = sheetFor(1, @"the line");
    tap(sheet, @"translate"); settle();
    SGLyricsMeaning *meaning = [[sheet valueForKey:@"meanings"] firstObject];
    meaning.body = @"An edited explanation.";
    [NSNotificationCenter.defaultCenter postNotificationName:SGLyricsTranslationsDidChangeNotification object:nil];
    CHECK([bodyText(sheet) isEqual:@"An edited explanation."], @"an edited annotation reused the old content");
    tap(sheet, @"translate"); settle();
    CHECK([bodyText(sheet) isEqual:@"번역: An edited explanation."], @"edited content not translated");
}

static void checkPartialReply(void) {
    reset(); sg_google = YES; sg_hold = YES;
    SGRMeaningSheet *sheet = sheetFor(1, @"the line");
    tap(sheet, @"translate"); settle();
    void (^done)(NSArray *, NSString *) = sg_pending.firstObject;
    [sg_pending removeObjectAtIndex:0];
    done(@[@"Only the body"], nil); settle();
    CHECK([label(sheet, @"status").text isEqual:@"Couldn't translate"], @"partial answer accepted");
    CHECK([bodyText(sheet) isEqual:@"Explanation 0 long enough to read."], @"partial answer replaced original");
    tap(sheet, @"translate"); settle();
    releaseHeld(NO); settle();
    CHECK([bodyText(sheet) isEqual:@"번역: Explanation 0 long enough to read."], @"partial reply prevented retry");
}

static void checkProviders(void) {
    for (NSString *provider in @[@"apple", @"bing", @"google", @"deepl", @"gemini", @"claude", @"openai"]) {
        reset();
        sg_onDevice = [provider isEqual:@"apple"];
        sg_bing = [provider isEqual:@"bing"];
        sg_google = [provider isEqual:@"google"];
        sg_deepl = [provider isEqual:@"deepl"];
        sg_gemini = [provider isEqual:@"gemini"];
        sg_claude = [provider isEqual:@"claude"];
        sg_openai = [provider isEqual:@"openai"];
        SGRMeaningSheet *sheet = sheetFor(1, @"the line");
        CHECK(!translateButton(sheet).hidden, @"%@ not offered", provider);
        tap(sheet, @"translate"); settle();
        CHECK([sg_service isEqual:provider], @"%@ routed to %@", provider, sg_service);
        CHECK([bodyText(sheet) isEqual:@"번역: Explanation 0 long enough to read."], @"%@ did not translate", provider);
    }
}

static void checkDynamicType(void) {
    reset(); sg_google = YES;
    SGRMeaningSheet *sheet = sheetFor(1, @"the line");
    [sheet.parentViewController setOverrideTraitCollection:
        [UITraitCollection traitCollectionWithPreferredContentSizeCategory:UIContentSizeCategoryLarge]
        forChildViewController:sheet];
    [translateButton(sheet) setNeedsUpdateConfiguration];
    settle();
    CGFloat ordinary = [translateButton(sheet).titleLabel sizeThatFits:CGSizeMake(CGFLOAT_MAX, CGFLOAT_MAX)].height;
    [sheet.parentViewController setOverrideTraitCollection:
        [UITraitCollection traitCollectionWithPreferredContentSizeCategory:UIContentSizeCategoryAccessibilityExtraExtraExtraLarge]
        forChildViewController:sheet];
    [translateButton(sheet) setNeedsUpdateConfiguration];
    settle();
    CGFloat enlarged = [translateButton(sheet).titleLabel sizeThatFits:CGSizeMake(CGFLOAT_MAX, CGFLOAT_MAX)].height;
    CHECK(enlarged > ordinary, @"Translate ignores Dynamic Type: height %.1f -> %.1f, category %@",
          ordinary, enlarged, sheet.traitCollection.preferredContentSizeCategory);
}

static void run(void) {
    // UIKit's Mac typography keeps the same point size across these categories. Test iOS typography
    // on an actual iOS Simulator instead of pretending the Catalyst font metrics prove that behavior.
    if ([NSProcessInfo.processInfo.arguments containsObject:@"--dynamic-type"]) {
        checkDynamicType();
        puts("[harness] meaning Dynamic Type passed");
        exit(0);
    }
    method_exchangeImplementations(class_getInstanceMethod(UIApplication.class, @selector(openURL:options:completionHandler:)),
                                   class_getInstanceMethod(UIApplication.class, @selector(meaningCheckOpenURL:options:completionHandler:)));
    checkOffered();
    checkTranslate();
    checkDuplicateTaps();
    checkFailureAndRetry();
    checkSwitchedDuringRequest();
    checkLanguageChange();
    checkCacheBounded();
    checkDismissed();
    checkLanguageDuringRequest();
    checkContentIdentity();
    checkPartialReply();
    checkProviders();
    printf("[harness] meaning-translate: %lu checks passed\n", (unsigned long)sg_checks);
    fflush(stdout);
    exit(0);
}

@interface MeaningTranslateApp : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation MeaningTranslateApp
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    sg_window = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, 390, 844)];
    self.window = sg_window;
    sg_window.rootViewController = [UIViewController new];
    [sg_window makeKeyAndVisible];
    // A timer, not a queued block: the checks pump the run loop for a double's answer, and the main queue is not
    // drained reentrantly from a block still running on it.
    // Wait for scene attachment, not a fixed number of launch turns.
    CFTimeInterval started = CACurrentMediaTime();
    [NSTimer scheduledTimerWithTimeInterval:0.1 repeats:YES block:^(NSTimer *timer) {
        if (!self.window.windowScene && CACurrentMediaTime() - started < 60) return;
        [timer invalidate];
        if (!self.window.windowScene) HARNESS_FAIL(@"the window never joined a scene");
        run();
    }];
    return YES;
}
@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(MeaningTranslateApp.class));
    }
}
