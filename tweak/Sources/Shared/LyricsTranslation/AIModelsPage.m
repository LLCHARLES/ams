// The AI services' pages under Lyrics › Translation (LyricsTranslation.h): each holds the service's key and model,
// and the OpenAI-compatible one its preset, address and connection test. The model is picked from the list the
// service gives for the saved key, filtered as it is typed, or typed in by hand when there is no list.
#import "Core/SGCore.h"
#import "Core/SGGlass.h"
#import "Settings/SGModPage.h"
#import "Settings/SGPageStyle.h"
#import "AIServicesInternal.h"
#import "ConnectionTest.h"

typedef NS_ENUM(NSInteger, SGModelListState) { SGModelListLoading, SGModelListDone, SGModelListFailed };

// A search field over the list once it is longer than this.
static const NSUInteger kSearchFrom = 8;

@interface SGAIModelPage : SGPage <UISearchBarDelegate>
- (instancetype)initWithService:(SGLyricsAI)service;
@end

@implementation SGAIModelPage {
    SGLyricsAI _service;
    NSArray<NSDictionary<NSString *, NSString *> *> *_models, *_shown;
    NSString *_problem;
    SGModelListState _state;
    SGLyricsAIModelLoad *_task;
    NSUInteger _asked;   // counts the loads, so a late answer to an earlier one is dropped
    UISearchBar *_search;
}

enum { kManualSection, kListSection };

- (instancetype)initWithService:(SGLyricsAI)service {
    if (!(self = [super initWithStyle:UITableViewStyleInsetGrouped])) return nil;
    _service = service;
    self.title = SGL(@"settings.translation.openaikey.model", @"Model");
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    _search = [UISearchBar new];
    _search.searchBarStyle = UISearchBarStyleMinimal;
    _search.placeholder = SGL(@"settings.translation.models.search", @"Search models");
    _search.autocapitalizationType = UITextAutocapitalizationTypeNone;
    _search.autocorrectionType = UITextAutocorrectionTypeNo;
    _search.delegate = self;
    [_search sizeToFit];
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    UIRefreshControl *refresh = [UIRefreshControl new];
    refresh.tintColor = SGGrey();
    [refresh addTarget:self action:@selector(reload) forControlEvents:UIControlEventValueChanged];
    self.refreshControl = refresh;
    [self load:NO];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    SGInsetForBars(self.tableView);
}

// Once the page is really gone: a back swipe given up halfway leaves the load running.
- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    if (!self.isMovingFromParentViewController) return;
    _asked++;
    [_task cancel];
    _task = nil;
}

- (void)reload {
    [self load:YES];
}

- (void)load:(BOOL)fresh {
    [_task cancel];
    _task = nil;
    NSUInteger asked = ++_asked;
    _state = SGModelListLoading;
    [self.tableView reloadData];
    __weak SGAIModelPage *weakSelf = self;
    SGLyricsAIModelLoad *task = SGLyricsAIFetchModels(_service, fresh, ^(NSArray<NSDictionary<NSString *, NSString *> *> *models, NSString *error) {
        SGAIModelPage *me = weakSelf;
        if (!me || asked != me->_asked) return;
        me->_task = nil;
        me->_models = models;
        me->_problem = error;
        me->_state = models ? SGModelListDone : SGModelListFailed;
        [me.refreshControl endRefreshing];
        [me filter];
    });
    // A kept list answers before this returns.
    if (asked == _asked && _state == SGModelListLoading) _task = task;
}

- (void)filter {
    NSString *query = [_search.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!query.length) _shown = _models;
    else _shown = [_models objectsAtIndexes:[_models indexesOfObjectsPassingTest:^BOOL(NSDictionary<NSString *, NSString *> *model, NSUInteger index, BOOL *stop) {
        return [model[@"id"] localizedCaseInsensitiveContainsString:query] || [model[@"name"] localizedCaseInsensitiveContainsString:query];
    }]];
    // Set only when it changes: setting it again takes the keyboard from the field being typed in.
    UIView *header = _models.count > kSearchFrom ? _search : nil;
    if (self.tableView.tableHeaderView != header) self.tableView.tableHeaderView = header;
    [self.tableView reloadData];
}

- (void)searchBar:(UISearchBar *)bar textDidChange:(NSString *)text {
    [self filter];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)bar {
    [bar resignFirstResponder];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)table {
    return 2;
}

- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section {
    if (section == kManualSection) return 1;
    return _state == SGModelListDone ? MAX(1, (NSInteger)_shown.count) : 1;
}

- (NSString *)headerFor:(NSInteger)section {
    if (section != kListSection || _state != SGModelListDone || !_models.count) return nil;
    return [NSString stringWithFormat:SGL(@"settings.translation.models.header", @"%lu models"), (unsigned long)_models.count];
}

- (NSString *)footerFor:(NSInteger)section {
    if (section == kManualSection) return SGL(@"settings.translation.models.manual.footer", @"For a model the list leaves out, or a service with no list.");
    if (_state == SGModelListFailed) return _problem;
    return _service == SGLyricsAIOpenAI
        ? SGL(@"settings.translation.models.openai.footer", @"This is the provider's whole model list. Not every model can translate.")
        : nil;
}

- (CGFloat)tableView:(UITableView *)table heightForHeaderInSection:(NSInteger)section {
    return [self headerFor:section] ? SGSectionHeaderHeight() : section == kManualSection ? CGFLOAT_MIN : SGSectionGap;
}

- (UIView *)tableView:(UITableView *)table viewForHeaderInSection:(NSInteger)section {
    NSString *title = [self headerFor:section];
    return title ? SGSectionHeader(table, title) : nil;
}

- (CGFloat)tableView:(UITableView *)table heightForFooterInSection:(NSInteger)section {
    NSString *text = [self footerFor:section];
    return text.length ? SGSectionFooterHeight(table, text) : CGFLOAT_MIN;
}

- (UIView *)tableView:(UITableView *)table viewForFooterInSection:(NSInteger)section {
    NSString *text = [self footerFor:section];
    return text.length ? SGSectionFooter(table, text) : nil;
}

- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell = SGDequeueCell(table, @"model");
    cell.accessibilityTraits = UIAccessibilityTraitNone;   // SGFillCell leaves a reused model row's traits
    NSString *current = SGLyricsAIModel(_service);
    if (path.section == kManualSection) {
        SGFillCell(cell, SGL(@"settings.translation.models.manual.title", @"Enter a model"),
                   [NSString stringWithFormat:SGL(@"settings.translation.models.current", @"Selected: %@"), current ?: @""], nil, @"keyboard");
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
        cell.accessibilityTraits = UIAccessibilityTraitButton;
        return cell;
    }
    if (_state == SGModelListLoading) {
        SGFillCell(cell, SGL(@"settings.translation.models.loading", @"Loading models…"), nil, SGGrey(), nil);
        UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
        [spinner startAnimating];
        cell.accessoryView = spinner;
        return cell;
    }
    if (_state == SGModelListFailed) {
        SGFillCell(cell, SGL(@"settings.translation.models.retry", @"Try Again"), nil, nil, @"arrow.clockwise");
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
        cell.accessibilityTraits = UIAccessibilityTraitButton;
        return cell;
    }
    if (!_shown.count) {
        SGFillCell(cell, _models.count ? SGL(@"settings.translation.models.nomatch", @"No models match")
                                       : SGL(@"settings.translation.models.empty", @"The service lists no models"), nil, SGGrey(), nil);
        return cell;
    }
    NSDictionary<NSString *, NSString *> *model = _shown[(NSUInteger)path.row];
    SGFillCell(cell, model[@"name"] ?: model[@"id"], model[@"name"] ? model[@"id"] : nil, nil, nil);
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    cell.accessibilityTraits = UIAccessibilityTraitButton;
    if ([model[@"id"] isEqualToString:current]) {
        UIImageView *tick = SGSymbolView(@"checkmark", 13, UIImageSymbolWeightSemibold, 16);
        tick.tintColor = SGGreen();
        cell.accessoryView = tick;
        cell.accessibilityTraits |= UIAccessibilityTraitSelected;
    }
    return cell;
}

- (BOOL)tableView:(UITableView *)table shouldHighlightRowAtIndexPath:(NSIndexPath *)path {
    if (path.section == kManualSection) return YES;
    return _state == SGModelListFailed || (_state == SGModelListDone && _shown.count);
}

- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)path {
    [table deselectRowAtIndexPath:path animated:YES];
    if (path.section == kManualSection) { [self askForModel]; return; }
    if (_state == SGModelListFailed) { [self load:YES]; return; }
    if (_state != SGModelListDone || path.row >= (NSInteger)_shown.count) return;
    if (!SGLyricsAISetModel(_service, _shown[(NSUInteger)path.row][@"id"])) return;
    [[UISelectionFeedbackGenerator new] selectionChanged];
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)askForModel {
    SGLyricsAI service = _service;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:SGL(@"settings.translation.models.manual.title", @"Enter a model")
        message:SGL(@"settings.translation.models.manual.message", @"The model's ID, as the service writes it.") preferredStyle:UIAlertControllerStyleAlert];
    __weak UIAlertController *weakAlert = alert;
    __weak SGAIModelPage *weakSelf = self;
    UIAlertAction *save = [UIAlertAction actionWithTitle:SGL(@"common.save", @"Save") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        if (!SGLyricsAISetModel(service, weakAlert.textFields.firstObject.text)) return;
        [weakSelf.navigationController popViewControllerAnimated:YES];
    }];
    __weak UIAlertAction *weakSave = save;
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.autocorrectionType = UITextAutocorrectionTypeNo;
        field.autocapitalizationType = UITextAutocapitalizationTypeNone;
        field.clearButtonMode = UITextFieldViewModeWhileEditing;
        field.placeholder = SGL(@"settings.translation.openaikey.model", @"Model");
        field.text = SGLyricsAIModel(service);
        [field addAction:[UIAction actionWithHandler:^(UIAction *action) {
            weakSave.enabled = SGLyricsAICleanModel(weakAlert.textFields.firstObject.text) != nil;
        }] forControlEvents:UIControlEventEditingChanged];
    }];
    save.enabled = SGLyricsAICleanModel(SGLyricsAIModel(service)) != nil;
    [alert addAction:save];
    [alert addAction:[UIAlertAction actionWithTitle:SGL(@"common.cancel", @"Cancel") style:UIAlertActionStyleCancel handler:nil]];
    SGPresentDark(alert);
    [self presentViewController:alert animated:YES completion:nil];
}

@end

static NSString *serviceTitle(SGLyricsAI service) {
    switch (service) {
        case SGLyricsAIGemini: return SGL(@"settings.translation.ai.gemini.title", @"Gemini");
        case SGLyricsAIClaude: return SGL(@"settings.translation.ai.claude.title", @"Claude");
        case SGLyricsAIOpenAI: return SGL(@"settings.translation.ai.openai.title", @"OpenAI-compatible");
    }
    return nil;
}

static SGModRow *modelRow(SGLyricsAI service) {
    SGModRow *row = SGPageRow(SGL(@"settings.translation.openaikey.model", @"Model"), ^UIViewController *{
        return [[SGAIModelPage alloc] initWithService:service];
    });
    row.value = ^NSString *{ return SGLyricsAIModel(service); };
    return row;
}

static UIViewController *servicePage(SGLyricsAI service) {
    NSArray<SGModSection *> *sections = nil;
    switch (service) {
        case SGLyricsAIGemini:
            sections = @[SGNotedSection(nil, [@[SGGeminiKeyRow(), modelRow(service)] arrayByAddingObjectsFromArray:SGGeminiTuningRows()],
                SGL(@"settings.translation.ai.gemini.footer", @"Translations, pronunciations and notes send the song's lyrics to Google, on your own key from Google AI Studio. The key stays on this iPhone."))];
            break;
        case SGLyricsAIClaude:
            sections = @[SGNotedSection(nil, @[SGClaudeKeyRow(), modelRow(service)],
                SGL(@"settings.translation.ai.claude.footer", @"Translations, pronunciations and notes send the song's lyrics to Anthropic, on your own key from the Claude Console. The key stays on this iPhone."))];
            break;
        case SGLyricsAIOpenAI:
            sections = @[SGNotedSection(nil, @[SGOpenAIPresetRow(), SGOpenAIBaseURLRow(), SGOpenAIKeyRow(), modelRow(service)],
                             SGL(@"settings.translation.ai.openai.footer", @"Translations, pronunciations and notes send the song's lyrics to the service at this address, on your own key. A service sets the address and a model; each host keeps its own key on this iPhone.")),
                         SGSection(nil, @[SGOpenAIConnectionTestRow(), SGOpenAITranslationTestRow()])];
            break;
    }
    return [[SGModPage alloc] initWithTitle:serviceTitle(service) intro:nil sections:sections footer:nil];
}

SGModRow *SGLyricsAIServiceRow(SGLyricsAI service) {
    SGModRow *row = SGPageRow(serviceTitle(service), ^UIViewController *{ return servicePage(service); });
    row.searchIdentifier = @[@"page.lyrics.gemini", @"page.lyrics.claude", @"page.lyrics.openai"][service];
    row.value = ^NSString *{
        return [SGLyricsAIAvailable() containsObject:@(service)] ? SGLyricsAIModel(service) : SGL(@"settings.translation.ai.key_required", @"API key required");
    };
    return row;
}
