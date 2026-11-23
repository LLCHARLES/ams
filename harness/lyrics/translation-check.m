// -translationCheck 1: the lyrics menu's translations, driven through the real SGRKaraokeView's menu items with two
// views on one song (the player's and the full screen page's), against stubs.m's saved translations and job tokens.
// Prints PASS and FAIL lines and quits with the number of failures. Alerts are caught, never shown.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "Redesigned/Lyrics/SGRKaraokeView.h"
#import "Redesigned/Lyrics/LyricsText.h"
#import "Redesigned/Kit/SGRDownload.h"
#if __has_include("Redesigned/Lyrics/AutoTranslation.h")
#import "Redesigned/Lyrics/AutoTranslation.h"
#define SG_HARNESS_AUTO_TRANSLATION 1
#endif
#import "Shared/LyricsTranslation/LyricsTranslation.h"

extern NSMutableDictionary<NSString *, NSDictionary<NSString *, NSString *> *> *SGHarnessSavedTranslations;
extern void (^SGHarnessGoogle)(NSArray<SGKaraokeLine *> *lines, void (^done)(NSArray<NSString *> *translations, NSString *error));
void SGHarnessDeleteAllTranslations(void);
NSUInteger SGHarnessTranslationJobs(void);
void SGKaraokeKeepLines(NSString *trackID, NSArray<SGKaraokeLine *> *lines);

typedef void (^SGHarnessDone)(NSArray<NSString *> *, NSString *);
static int sg_failed;
static UIAlertController *sg_alert;
static SGHarnessDone sg_held;

static void check(BOOL ok, NSString *what) {
    printf("%s %s\n", ok ? "PASS" : "FAIL", what.UTF8String);
    fflush(stdout);
    if (!ok) sg_failed++;
}

// Spotify's AddToButton owner exposes its Swift enum as one byte.
@interface HarnessAddToButton : NSObject {
@public
    uint8_t currentStatus;
}
- (void)performAction;
@end
@implementation HarnessAddToButton
- (void)performAction {}
@end

static void addToLookupChecks(void) {
    HarnessAddToButton *saved = [HarnessAddToButton new], *unsaved = [HarnessAddToButton new];
    saved->currentStatus = 1;
    UIButton *root = [UIButton new], *nested = [UIButton new], *sibling = [UIButton new];
    UIView *branch = [UIView new];
    [root addTarget:unsaved action:@selector(performAction) forControlEvents:UIControlEventTouchUpInside];
    [nested addTarget:saved action:@selector(performAction) forControlEvents:UIControlEventTouchUpInside];
    [sibling addTarget:unsaved action:@selector(performAction) forControlEvents:UIControlEventTouchUpInside];
    root.accessibilityIdentifier = @"Components.UI.AddToButton";
    nested.accessibilityIdentifier = @"Components.UI.AddToButton.saved";
    sibling.accessibilityIdentifier = @"Components.UI.AddToButton";
    [root addSubview:branch];
    [branch addSubview:nested];
    [root addSubview:sibling];
    BOOL added = YES;
    check(SGRReadAddTo(root, &added) && !added, @"AddTo lookup includes the root before descendants");
    root.accessibilityIdentifier = nil;
    check(SGRReadAddTo(root, &added) && added, @"AddTo lookup takes the first depth-first prefix match");
    [branch removeFromSuperview];
    check(SGRReadAddTo(root, &added) && !added, @"AddTo lookup reads the current tree without a cached match");
    check(!SGRReadAddTo(nil, &added), @"AddTo lookup rejects a missing root");
}

static void caught(UIViewController *self, SEL _cmd, UIViewController *shown, BOOL animated, void (^completion)(void)) {
    if ([shown isKindOfClass:UIAlertController.class]) sg_alert = (UIAlertController *)shown;
}

static SGKaraokeLine *sungLine(NSInteger start, NSString *text) {
    NSMutableArray<SGKaraokeWord *> *words = [NSMutableArray array];
    NSInteger at = start;
    for (NSString *piece in [text componentsSeparatedByString:@" "]) {
        SGKaraokeWord *word = [SGKaraokeWord new];
        word.text = piece;
        word.start = at;
        word.end = at + 450;
        at += 500;
        [words addObject:word];
    }
    SGKaraokeLine *line = [SGKaraokeLine new];
    line.words = words;
    line.start = start;
    line.end = at;
    return line;
}

static NSArray<UIMenuElement *> *everyItem(UIMenu *menu) {
    NSMutableArray<UIMenuElement *> *all = [NSMutableArray array];
    for (UIMenuElement *child in menu.children) {
        [all addObject:child];
        if ([child isKindOfClass:UIMenu.class]) [all addObjectsFromArray:everyItem((UIMenu *)child)];
    }
    return all;
}
static UIMenu *menuOf(SGRKaraokeView *view) { return ((UIButton *)[view valueForKey:@"extras"]).menu; }
static UIMenuElement *itemIn(UIMenu *menu, NSString *title) {
    for (UIMenuElement *item in everyItem(menu)) if ([item.title isEqualToString:title]) return item;
    return nil;
}
static UIMenuElement *item(SGRKaraokeView *view, NSString *title) { return itemIn(menuOf(view), title); }
// The translators offered at the menu's own level, outside Translate Again.
static BOOL offeredFlat(SGRKaraokeView *view, NSString *title) {
    for (UIMenuElement *group in menuOf(view).children) {
        if (![group isKindOfClass:UIMenu.class]) continue;
        for (UIMenuElement *child in ((UIMenu *)group).children) if ([child.title isEqualToString:title] && [child isKindOfClass:UIAction.class]) return YES;
    }
    return NO;
}
static BOOL tap(UIMenuElement *element) {
    if (![element isKindOfClass:UIAction.class]) return NO;
    UIAction *action = (UIAction *)element;
    void (^handler)(UIAction *) = [action valueForKey:@"handler"];
    if (!handler) return NO;
    handler(action);
    return YES;
}
static BOOL again(SGRKaraokeView *view, NSString *translator) {
    UIMenuElement *menu = item(view, @"Translate Again");
    return [menu isKindOfClass:UIMenu.class] && tap(itemIn((UIMenu *)menu, translator));
}
static BOOL spinning(SGRKaraokeView *view) { return ((UIButton *)[view valueForKey:@"extras"]).configuration.showsActivityIndicator; }
static BOOL shown(void) { return [NSUserDefaults.standardUserDefaults boolForKey:SGRKeyLyricsTranslation]; }
static NSString *translations(NSArray<SGKaraokeLine *> *lines) {
    NSMutableArray<NSString *> *out = [NSMutableArray array];
    for (SGKaraokeLine *line in lines) [out addObject:[NSString stringWithFormat:@"%@%@", line.translation ?: @"-", line.translationMade ? @"*" : @""]];
    return [out componentsJoinedByString:@" | "];
}
static NSArray<NSString *> *markAll(NSArray<SGKaraokeLine *> *lines, NSString *mark) {
    NSMutableArray<NSString *> *out = [NSMutableArray array];
    for (SGKaraokeLine *line in lines) [out addObject:[mark stringByAppendingString:SGKaraokeLineText(line)]];
    return out;
}
static void googleAnswers(NSString *mark) {
    SGHarnessGoogle = ^(NSArray<SGKaraokeLine *> *lines, SGHarnessDone done) { done(markAll(lines, mark), nil); };
}
static void googleHolds(void) {
    SGHarnessGoogle = ^(NSArray<SGKaraokeLine *> *lines, SGHarnessDone done) { sg_held = done; };
}

#ifdef SG_HARNESS_AUTO_TRANSLATION
#include "auto-check.inc"
#endif
#include "review-check.inc"
#include "wrap-check.inc"
#include "round-one-check.inc"
#include "model-budget-check.inc"
#include "reader-check.inc"

void SGHarnessRunTranslationCheck(UIWindow *window) {
    modelBudgetChecks();
    if (getenv("SG_LYRICS_MODEL_BUDGET_ONLY")) {
        exit(sg_failed ? 1 : 0);
    }
    if (getenv("SG_LYRICS_ROUND_ONE_ONLY")) {
        [NSTimer scheduledTimerWithTimeInterval:0.1 repeats:NO block:^(NSTimer *timer) {
            roundOneChecks(window);
            printf("%d failed\n", sg_failed);
            fflush(stdout);
            exit(sg_failed);
        }];
        return;
    }
    if (getenv("SG_LYRICS_WRAP_ONLY")) {
        wrapChecks();
        printf("%d failed\n", sg_failed);
        fflush(stdout);
        exit(sg_failed);
    }
    addToLookupChecks();
    if (getenv("SG_LYRICS_REVIEW_ONLY")) {
        [NSTimer scheduledTimerWithTimeInterval:0.1 repeats:NO block:^(NSTimer *timer) {
            reviewChecks(window);
            printf("%d failed\n", sg_failed);
            fflush(stdout);
            exit(sg_failed);
        }];
        return;
    }
    NSUserDefaults *args = NSUserDefaults.standardUserDefaults;
    for (NSString *key in @[@"translateTo", SGRKeyLyricsTranslation]) [args removeObjectForKey:key];
#ifdef SG_HARNESS_AUTO_TRANSLATION
    [args removeObjectForKey:SGRKeyLyricsAutoTranslation];
    [args removeObjectForKey:SGRKeyLyricsAutoTranslationOrder];
#endif
    [args setBool:YES forKey:@"gemini"];
    [args setDouble:0 forKey:@"geminiDelay"];
    [args setBool:YES forKey:SGKeyLyricsGoogleTranslate];
    [args setBool:YES forKey:SGKeyLyricsTranslateEverySong];
    method_setImplementation(class_getInstanceMethod(UIViewController.class, @selector(presentViewController:animated:completion:)), (IMP)caught);

    SGKaraokeLine *source = sungLine(1000, @"uno dos");
    source.translation = @"one two";
    NSArray<SGKaraokeLine *> *lines = @[source, sungLine(4000, @"tres cuatro"), sungLine(7000, @"cinco seis"), sungLine(10000, @"siete ocho")];
    SGKaraokeKeepLines(@"harness", lines);

    UIViewController *root = [UIViewController new];
    window.rootViewController = root;
    [window makeKeyAndVisible];
    CGRect bounds = root.view.bounds;
    SGRKaraokeView *player = [[SGRKaraokeView alloc] initWithFrame:CGRectMake(0, 0, bounds.size.width, bounds.size.height / 2)];
    SGRKaraokeView *page = [[SGRKaraokeView alloc] initWithFrame:CGRectMake(0, bounds.size.height / 2, bounds.size.width, bounds.size.height / 2)];
    for (SGRKaraokeView *view in @[player, page]) {
        // Each real lyrics host owns its siblings' opacity. Let both views reach their on-screen state.
        UIView *host = [[UIView alloc] initWithFrame:view.frame];
        [root.view addSubview:host];
        view.frame = host.bounds;
        [host addSubview:view];
        autoTick(view);
    }
    check(extrasWait(^BOOL { return !player.hidden && !page.hidden; }), @"both manual translation menus are on screen");
    NSArray<SGRKaraokeView *> *views = @[player, page];
    BOOL (^both)(BOOL (^)(SGRKaraokeView *)) = ^BOOL(BOOL (^test)(SGRKaraokeView *)) { return test(player) && test(page); };
    NSDictionary *(^saved)(void) = ^NSDictionary * { return SGHarnessSavedTranslations[@"harness|en"]; };
    // The full screen page holds other copies of the song's lines, as a source's refined lines come in as copies.
    NSMutableArray<SGKaraokeLine *> *copies = [NSMutableArray array];
    for (SGKaraokeLine *line in lines) [copies addObject:[line copy]];
    [page setValue:copies forKey:@"lines"];
    ((void (*)(id, SEL))objc_msgSend)(page, NSSelectorFromString(@"timeLines"));

    // Before any translation: the translators at the top, nothing to replace or remove.
    check(offeredFlat(player, @"Translate with Google") && !item(player, @"Translate Again") && !item(player, @"Remove Translation"),
          @"untranslated: the translators are offered, nothing to replace or remove");
    check([item(player, @"Show Translation").subtitle isEqualToString:@"For all songs"], @"Show Translation says it is for all songs");

    // Google: the lines without one take it, the source's line keeps its own, and only made lines are saved.
    googleAnswers(@"G: ");
    check(tap(item(player, @"Translate with Google")), @"Translate with Google is tapped");
    check([translations(lines) isEqualToString:@"one two | G: tres cuatro* | G: cinco seis* | G: siete ocho*"], translations(lines));
    check([translations(copies) isEqualToString:translations(lines)], @"the other view's own copies take it from what is saved");
    check(saved().count == 3 && !saved()[@"uno dos"], @"the three made lines are saved, the source's is not");
    check(shown(), @"the translation is switched on");
    check(both(^BOOL(SGRKaraokeView *v) { return [[v valueForKey:@"madeTranslation"] boolValue] && !spinning(v); }), @"both views know of it, neither spins");
    check(!offeredFlat(player, @"Translate with Google") && !offeredFlat(page, @"Translate with Gemini"), @"the translators leave the top level");
    UIMenuElement *gemini = itemIn((UIMenu *)item(page, @"Translate Again"), @"Translate with Gemini");
    check([gemini.subtitle isEqualToString:@"Sends the lyrics to Google"], @"Translate Again offers Gemini, saying where the lyrics go");
    UIMenuElement *remove = item(page, @"Remove Translation");
    check([remove.subtitle isEqualToString:@"This song only"] && (((UIAction *)remove).attributes & UIMenuElementAttributesDestructive), @"Remove Translation is offered, for this song only");
    check([item(page, @"Hide Translation").subtitle isEqualToString:@"For all songs"], @"Hide Translation says it is for all songs");

    // Another service replaces what was made, never the source's line.
    check(again(page, @"Translate with Gemini"), @"Translate Again with Gemini is tapped in the other view");
    check([translations(lines) isEqualToString:@"one two | Gemini: tres cuatro* | Gemini: cinco seis* | Gemini: siete ocho*"], translations(lines));
    check([translations(copies) isEqualToString:translations(lines)], @"and the view that asked has it in its own copies");
    check([saved()[@"cinco seis"] isEqualToString:@"Gemini: cinco seis"], @"the replacement is saved");

    // A failed replacement keeps every line and says so.
    NSString *before = translations(lines);
    NSDictionary *savedBefore = saved();
    SGHarnessGoogle = ^(NSArray<SGKaraokeLine *> *sent, SGHarnessDone done) { done(nil, @"boom"); };
    sg_alert = nil;
    check(again(player, @"Translate with Google"), @"Translate Again with Google is tapped");
    check([translations(lines) isEqualToString:before] && [saved() isEqualToDictionary:savedBefore], @"a failure changes no line and nothing saved");
    check([sg_alert.title isEqualToString:@"No translation"] && [sg_alert.message containsString:@"keep their previous translation"], @"its alert says the lines keep their translation");
    check(SGHarnessTranslationJobs() == 0 && !spinning(player) && !spinning(page), @"the job ended and nothing spins");

    // A partial answer replaces only the lines it has.
    SGHarnessGoogle = ^(NSArray<SGKaraokeLine *> *sent, SGHarnessDone done) { done(@[@"", @"G2: tres cuatro", @"", @""], @"part"); };
    sg_alert = nil;
    again(player, @"Translate with Google");
    check([translations(lines) isEqualToString:@"one two | G2: tres cuatro* | Gemini: cinco seis* | Gemini: siete ocho*"], translations(lines));
    check([sg_alert.title isEqualToString:@"Partly translated"] && [sg_alert.message containsString:@"keep their previous translation"], @"its alert says it is partly translated");

    // While a job works: both spin, no translator is offered, Remove is; hiding it then stands through the answer.
    googleHolds();
    again(player, @"Translate with Google");
    check(both(^BOOL(SGRKaraokeView *v) { return spinning(v) && !item(v, @"Translate Again") && item(v, @"Remove Translation"); }),
          @"working: both views spin, offer no translator, and offer Remove");
    tap(item(page, @"Hide Translation"));
    check(!shown(), @"hidden while it works");
    SGHarnessDone held = sg_held;
    held(markAll(lines, @"G3: "), nil);
    check([translations(lines) isEqualToString:@"one two | G3: tres cuatro* | G3: cinco seis* | G3: siete ocho*"], translations(lines));
    check(!shown(), @"the answer leaves the translation hidden");
    // A second answer to an ended job changes nothing.
    sg_alert = nil;
    held(markAll(lines, @"late: "), @"late");
    check([translations(lines) hasPrefix:@"one two | G3: "] && [saved()[@"tres cuatro"] isEqualToString:@"G3: tres cuatro"] && !sg_alert, @"a late second answer changes nothing");

    // Asking switches the translation on; Remove while it works stops it, and its answer is dropped.
    again(player, @"Translate with Google");
    check(shown(), @"asking switches the translation back on");
    tap(item(page, @"Remove Translation"));
    check([translations(lines) isEqualToString:@"one two | - | - | -"], translations(lines));
    check([translations(copies) isEqualToString:translations(lines)], @"in both views' lines");
    check(!saved() && SGHarnessTranslationJobs() == 0, @"its saved translation and its job are gone");
    check(both(^BOOL(SGRKaraokeView *v) { return !spinning(v) && !item(v, @"Remove Translation") && offeredFlat(v, @"Translate with Google"); }),
          @"both views stop, Remove goes and the translators are back");
    sg_alert = nil;
    sg_held(markAll(lines, @"stale: "), @"stale");
    check([translations(lines) isEqualToString:@"one two | - | - | -"] && !saved() && !sg_alert, @"the removed job's answer changes nothing");

    // Another language overtakes a job: its answer is dropped and its token ended.
    googleAnswers(@"G4: ");
    tap(item(player, @"Translate with Google"));
    googleHolds();
    again(player, @"Translate with Google");
    [args setObject:@"fr" forKey:@"translateTo"];
    for (SGRKaraokeView *view in views) ((void (*)(id, SEL))objc_msgSend)(view, NSSelectorFromString(@"translationsChanged"));
    check(!spinning(player) && !spinning(page), @"in another language nothing spins");
    sg_held(markAll(lines, @"stale: "), nil);
    check(SGHarnessTranslationJobs() == 0 && !SGHarnessSavedTranslations[@"harness|fr"], @"its answer is dropped and its job ended");
    [args removeObjectForKey:@"translateTo"];
    for (SGRKaraokeView *view in views) ((void (*)(id, SEL))objc_msgSend)(view, NSSelectorFromString(@"translationsChanged"));
    check([translations(lines) isEqualToString:@"one two | G4: tres cuatro* | G4: cinco seis* | G4: siete ocho*"], translations(lines));

    // Deleting every saved translation ends the job too.
    again(page, @"Translate with Google");
    SGHarnessDeleteAllTranslations();
    check(!spinning(player) && !spinning(page), @"deleting them all stops the spinner");
    sg_held(markAll(lines, @"stale: "), nil);
    check([translations(lines) isEqualToString:@"one two | - | - | -"] && !saved(), @"and the job's answer is dropped");

    // AI completion must reach views sharing the objects as well as a view holding its own copies.
    [args setBool:YES forKey:@"ai"];
    [args setBool:YES forKey:@"aiCheck"];
    [args setBool:YES forKey:SGKeyLyricsCulturalNotes];
    SGRKaraokeView *shared = [[SGRKaraokeView alloc] initWithFrame:CGRectZero];
    [shared setValue:@"harness" forKey:@"track"];
    [shared setValue:lines forKey:@"lines"];
    NSArray *aiViews = @[player, page, shared];
    for (SGRKaraokeView *view in aiViews) ((void (*)(id, SEL))objc_msgSend)(view, NSSelectorFromString(@"timeLines"));
    check(tap(itemIn((UIMenu *)item(player, @"Write Pronunciation"), @"Gemini")), @"AI pronunciation requested");
    check([[page valueForKey:@"hasSpoken"] boolValue] && [[shared valueForKey:@"hasSpoken"] boolValue], @"AI pronunciation flags update in copied and shared views");
    check(lines[1].pronunciation && [SGKaraokeLineText(lines[1].pronunciation) isEqualToString:SGKaraokeLineText(((SGKaraokeLine *)copies[1]).pronunciation)], @"AI pronunciation reaches the other array");
    check(tap(itemIn((UIMenu *)item(player, @"Explain References"), @"Gemini")), @"AI notes requested");
    check([[page valueForKey:@"hasNotes"] boolValue] && [[shared valueForKey:@"hasNotes"] boolValue], @"AI note flags update in copied and shared views");
    check(lines[1].note.length && [lines[1].note isEqualToString:((SGKaraokeLine *)copies[1]).note], @"AI notes reach the other array");
    [args setBool:NO forKey:@"ai"];

    // A menu kept from before the view moved to another song acts on the song it was offered for, or not at all.
    googleAnswers(@"G5: ");
    tap(item(player, @"Translate with Google"));
    UIMenuElement *oldRemove = item(player, @"Remove Translation");
    UIMenuElement *oldAgain = itemIn((UIMenu *)item(player, @"Translate Again"), @"Translate with Google");
    SGHarnessSavedTranslations[@"other|en"] = @{@"x": @"y"};
    [player setValue:@"other" forKey:@"track"];
    __block BOOL sent = NO;
    SGHarnessGoogle = ^(NSArray<SGKaraokeLine *> *sentLines, SGHarnessDone done) { sent = YES; };
    check(tap(oldAgain) && !sent && SGHarnessTranslationJobs() == 0, @"an old Translate Again sends nothing for the new song");
    check(tap(oldRemove) && !saved() && [SGHarnessSavedTranslations[@"other|en"] isEqualToDictionary:@{@"x": @"y"}],
          @"an old Remove deletes the song it was offered for, not the new one");
    check([translations(copies) isEqualToString:@"one two | - | - | -"], @"and the view still on that song goes back to its lyrics");

    // A timer leaves the dispatch-main callback before the automatic tests pump their nested run loop.
    // Otherwise queued translator completions cannot run while this main-queue block is still executing.
    [NSTimer scheduledTimerWithTimeInterval:0.1 repeats:NO block:^(NSTimer *timer) {
        wrapChecks();
        reviewChecks(window);
#ifdef SG_HARNESS_AUTO_TRANSLATION
        autoCheck(window);
#endif
        roundOneChecks(window);
        readerChecks(window);
        printf("%d failed\n", sg_failed);
        fflush(stdout);
        exit(sg_failed);
    }];
}
