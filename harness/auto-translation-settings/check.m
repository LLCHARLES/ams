// Production AutoTranslationSettings.m + SGPage.m run under real Catalyst UIKit.
#import <UIKit/UIKit.h>
#import "Settings/SGModPage.h"
#import "Settings/SGPageStyle.h"
#import "Redesigned/Lyrics/AutoTranslation.h"
#import "Redesigned/Lyrics/LyricsText.h"

static NSArray<NSNumber *> *savedOrder;
static SGRAutoTranslationState states[SGRAutoTranslatorCount];
static NSMutableArray<NSString *> *events;
static NSUInteger saves, languageReads;
static BOOL translationShown;
static int checks, failures;
static void check(BOOL ok, NSString *label) {
    printf("%s %s\n", ok ? "PASS" : "FAIL", label.UTF8String);
    checks++; if (!ok) failures++;
}

// Minimal row constructors: retain the actual production callback blocks unchanged.
@implementation SGModRow
@end
SGModRow *SGOptionRow(NSString *title, NSString *subtitle, NSString *key) {
    SGModRow *row = [SGModRow new]; row.title = title; row.subtitle = subtitle; row.key = key; return row;
}
SGModRow *SGPageRow(NSString *title, UIViewController *(^page)(void)) {
    SGModRow *row = [SGModRow new]; row.title = title; row.page = page; return row;
}
// Deterministic provider boundary; no requests, keychain or production preferences.
NSArray<NSNumber *> *SGRAutoTranslationOrder(void) { return savedOrder; }
void SGRSetAutoTranslationOrder(NSArray<NSNumber *> *order) { saves++; savedOrder = [order copy]; }
NSString *SGLyricsGeminiLanguage(void) { return @"ko"; }
SGRAutoTranslationState SGRAutoTranslationStateOf(SGRAutoTranslator provider, NSString *language) {
    check([language isEqual:@"ko"], @"provider receives selected translation language");
    languageReads++; return states[provider];
}
BOOL SGRAutoTranslationAvailable(SGRAutoTranslator provider, NSString *language) {
    return SGRAutoTranslationStateOf(provider, language) == SGRAutoTranslationReady;
}
void SGRAutoTranslationSettingsChanged(void) { [events addObject:@"settings"]; }
void SGRSetLyricsTextShown(SGRLyricsText text, BOOL shown) {
    check(text == SGRLyricsTextTranslation, @"switch targets translation text only");
    [events addObject:shown ? @"show" : @"hide"]; translationShown = shown;
}
// Style substitutes use real UIKit cells/labels; no product row ordering or status logic here.
UIColor *SGGrey(void) { return UIColor.grayColor; }
UIColor *SGPageBackground(void) { return UIColor.blackColor; }
void SGPresentDark(UIViewController *controller) { controller.overrideUserInterfaceStyle = UIUserInterfaceStyleDark; }
UIView *SGNote(NSString *text) { UILabel *label = [UILabel new]; label.text = text; label.numberOfLines = 0; return label; }
void SGFitNote(UITableView *table, UIView *note, CGFloat top, CGFloat bottom) {
    note.frame = CGRectMake(0, 0, table.bounds.size.width, top + bottom + 80);
}
void SGInsetForBars(UITableView *table) {}
CGFloat SGSectionHeaderHeight(void) { return 32; }
UIView *SGSectionHeader(UITableView *table, NSString *text) { return SGNote(text); }
UITableViewCell *SGDequeueCell(UITableView *table, NSString *identifier) {
    return [table dequeueReusableCellWithIdentifier:identifier] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:identifier];
}
void SGFillCell(UITableViewCell *cell, NSString *title, NSString *subtitle, UIColor *color, NSString *symbol) {
    cell.textLabel.text = title; cell.detailTextLabel.text = subtitle;
    cell.textLabel.textColor = color ?: UIColor.whiteColor;
    cell.imageView.image = [UIImage systemImageNamed:symbol];
}

static SGPage *loadPage(SGModRow *row) {
    SGPage *page = (SGPage *)row.page();
    [page loadViewIfNeeded];
    page.view.frame = CGRectMake(0, 0, 600, 800);
    [page.view setNeedsLayout]; [page.view layoutIfNeeded];
    [page.tableView reloadData];
    return page;
}
static UITableViewCell *cellAt(SGPage *page, NSInteger index) {
    return [page.tableView.dataSource tableView:page.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:index inSection:0]];
}
static void runChecks(void) {
    check(NSThread.isMainThread, @"checks execute on UIKit main thread");
    check(SGRAutoTranslatorName(SGRAutoTranslatorOff) == nil && SGRAutoTranslatorName(SGRAutoTranslatorCount) == nil
          && SGRAutoTranslatorName((SGRAutoTranslator)-1) == nil, @"off and unknown translators have no display name");
    savedOrder = @[@1,@2,@3,@4,@5,@6,@7,@8]; events = [NSMutableArray array];
    SGModRow *toggle = SGRAutoTranslationRow();
    check([toggle.key isEqual:SGRKeyLyricsAutoTranslation] && toggle.changed != nil && !toggle.defaultOn,
          @"automatic translation switch is wired to its key and defaults off");
    translationShown = NO; toggle.changed(YES);
    check([events isEqual:@[@"settings", @"show"]] && translationShown,
          @"On invalidates settings BEFORE enabling Show Translation");
    [events removeAllObjects]; toggle.changed(NO);
    check([events isEqual:@[@"settings"]] && translationShown, @"Off invalidates settings without hiding translations");
    translationShown = NO; [events removeAllObjects]; toggle.changed(NO);
    check([events isEqual:@[@"settings"]] && !translationShown, @"Off also preserves already-hidden translations");

    SGModRow *orderRow = SGRAutoTranslationOrderRow();
    check([orderRow.waitsOn isEqual:toggle.key], @"order row waits on automatic translation switch");
    check([orderRow.value() isEqual:@"Apple Translate"], @"summary names first ready service");
    states[1] = SGRAutoTranslationUnavailableDevice; states[2] = SGRAutoTranslationUnavailableDevice;
    states[4] = SGRAutoTranslationNeedsSwitch; states[5] = SGRAutoTranslationNeedsKey;
    states[6] = SGRAutoTranslationUnsupportedLanguage; states[7] = SGRAutoTranslationNeedsKey;
    states[8] = SGRAutoTranslationNeedsSettings;
    check([orderRow.value() isEqual:@"Google Translate"], @"summary skips unavailable services");
    SGPage *page = loadPage(orderRow); UITableView *table = page.tableView;
    // Catalyst may wrap the controller in a UIKit data-source/delegate proxy.
    check([page isKindOfClass:SGPage.class] && [table isKindOfClass:UITableView.class] &&
          [table.dataSource tableView:table numberOfRowsInSection:0] == 8 &&
          [table.delegate tableView:table heightForHeaderInSection:0] == SGSectionHeaderHeight(),
          @"real UITableView data source/delegate dispatch reaches production page methods");
    check(page.overrideUserInterfaceStyle == UIUserInterfaceStyleDark && [table.backgroundColor isEqual:UIColor.blackColor],
          @"production SGPage applies dark appearance");
    check(table.editing && [table numberOfRowsInSection:0] == 8, @"editing table keeps all eight services including unavailable ones");
    check(table.tableFooterView != nil && table.tableFooterView.bounds.size.height > 0, @"real lifecycle installs and sizes footer");
    check([page tableView:table viewForHeaderInSection:0] != nil && [page tableView:table heightForHeaderInSection:0] > 0,
          @"table header methods return a view and positive height");
    NSArray *names = @[@"Apple Translate", @"Apple Intelligence", @"Google Translate", @"Bing Translator", @"DeepL", @"Gemini", @"Claude", @"Your AI service"];
    NSArray *notes = @[@"not available on this iPhone", @"needs Apple Intelligence", @"Sends the lyrics to Google Translate", @"switched off", @"no API key", @"can't translate into", @"no API key", @"base URL and model"];
    for (NSInteger i = 0; i < 8; i++) {
        NSIndexPath *path = [NSIndexPath indexPathForRow:i inSection:0];
        UITableViewCell *cell = cellAt(page, i);
        BOOL ready = i == 2;
        check([cell.textLabel.text isEqual:names[i]] && [cell.detailTextLabel.text containsString:notes[i]] &&
              ([cell.detailTextLabel.text containsString:@"Skipped:"] != ready) &&
              [cell.textLabel.textColor isEqual:ready ? UIColor.whiteColor : SGGrey()],
              [NSString stringWithFormat:@"row %ld: stable identity, destination/readiness note and ready/unavailable color", (long)i]);
        check([page tableView:table canMoveRowAtIndexPath:path] && [page tableView:table canEditRowAtIndexPath:path] &&
              [page tableView:table editingStyleForRowAtIndexPath:path] == UITableViewCellEditingStyleNone &&
              ![page tableView:table shouldIndentWhileEditingRowAtIndexPath:path] && cell.selectionStyle == UITableViewCellSelectionStyleNone,
              [NSString stringWithFormat:@"row %ld: reorderable without delete, indent or selection", (long)i]);
    }
    states[8] = SGRAutoTranslationReady;
    [page tableView:table moveRowAtIndexPath:[NSIndexPath indexPathForRow:7 inSection:0] toIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];
    check(saves == 1 && [savedOrder isEqual:@[@8,@1,@2,@3,@4,@5,@6,@7]], @"drag callback forwards exact new order once to SGRSetAutoTranslationOrder");
    check([cellAt(page, 0).textLabel.text isEqual:@"Your AI service"] && [table numberOfRowsInSection:0] == 8,
          @"same page reads reordered model and preserves eight rows");
    check([orderRow.value() isEqual:@"Your AI service"], @"summary follows newly first available service after reorder");
    SGPage *reopened = loadPage(orderRow);
    check([cellAt(reopened, 0).textLabel.text isEqual:@"Your AI service"], @"reopened production page reads order saved by setter boundary");
    [reopened tableView:reopened.tableView moveRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0] toIndexPath:[NSIndexPath indexPathForRow:7 inSection:0]];
    check(saves == 2 && [savedOrder isEqual:@[@1,@2,@3,@4,@5,@6,@7,@8]], @"reverse drag preserves all services and saves exact order");
    for (NSInteger p = 1; p < SGRAutoTranslatorCount; p++) states[p] = SGRAutoTranslationNeedsKey;
    check([orderRow.value() isEqual:@"None ready"], @"summary reports none ready when every service is unavailable");
    check([reopened tableView:reopened.tableView numberOfRowsInSection:0] == 8 && languageReads > 0,
          @"availability changes never remove rows");
    printf("auto translation settings: %d/%d passed\n", checks - failures, checks); fflush(stdout);
    exit(failures ? 1 : 0);
}
@interface CheckApp : UIResponder <UIApplicationDelegate>
@end
@implementation CheckApp
- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)options {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 120 * NSEC_PER_SEC), dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
        fputs("FAIL UIKit smoke timed out\n", stderr); exit(1);
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
