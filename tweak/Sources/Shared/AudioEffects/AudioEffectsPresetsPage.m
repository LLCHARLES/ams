// The Presets and Headphones pages the Audio effects page's first card opens. Both stay open after a pick,
// so one preset or one headphone after another can be heard before going back.
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import "Core/SGCore.h"
#import "Settings/SGPage.h"
#import "Settings/SGPageStyle.h"
#import "AudioEffectsPage.h"
#import "AudioEffectsPresets.h"

static void tick(UITableViewCell *cell, BOOL on) {
    if (on) {
        UIImageView *tick = SGSymbolView(@"checkmark", 13, UIImageSymbolWeightSemibold, 16);
        tick.tintColor = SGAccentMark();
        cell.accessoryView = tick;
    }
    cell.accessibilityTraits = on ? UIAccessibilityTraitButton | UIAccessibilityTraitSelected : UIAccessibilityTraitButton;
}

#pragma mark - presets

// A pick replaces every effect's settings, so the first pick each time the page opens saves them first,
// as one of the user's presets under this name, kept at the top of theirs: a tap on it puts them back.
// The name is stored with the preset, so it stays the same in every language; only its row is translated.
static NSString *const kBeforePresets = @"Before presets";

static NSString *userPresetTitle(NSString *name) {
    return [name isEqualToString:kBeforePresets] ? SGL(@"settings.audioeffects.presets.beforepresets", @"Before presets") : name;
}

// The user's presets, the settings from before the last round of picks first.
static NSArray<NSString *> *userPresetNames(void) {
    NSMutableArray<NSString *> *names = [SGDSPUserPresetNames() mutableCopy];
    if ([names containsObject:kBeforePresets]) {
        [names removeObject:kBeforePresets];
        [names insertObject:kBeforePresets atIndex:0];
    }
    return names;
}

// A preset to share is written to a folder of its own in tmp, which the share sheet hands on and which is
// deleted when the sheet is done.
static NSURL *sharedFileFor(NSString *name) {
    NSString *fileName = nil;
    NSData *data = SGDSPPresetFileData(name, &fileName);
    if (!data) return nil;
    NSURL *folder = [[NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES] URLByAppendingPathComponent:NSUUID.UUID.UUIDString isDirectory:YES];
    NSURL *url = [folder URLByAppendingPathComponent:fileName];
    if (![NSFileManager.defaultManager createDirectoryAtURL:folder withIntermediateDirectories:YES attributes:nil error:nil]
        || ![data writeToURL:url options:NSDataWritingAtomic error:nil]) {
        [NSFileManager.defaultManager removeItemAtURL:folder error:nil];
        return nil;
    }
    return url;
}

// The rows of the last section: Save, then Import.
enum { kSaveRow, kImportRow, kActionRows };

// The built-in presets, then the user's, then Save and Import. The last one picked is ticked until something else is.
@interface SGDSPPresetList : SGPage <UIDocumentPickerDelegate>
@end

@implementation SGDSPPresetList {
    NSArray<NSString *> *_builtIn, *_mine;
    NSIndexPath *_picked;
    UIView *_footer;
    BOOL _kept;   // the settings from before this page's first pick are saved
}

- (instancetype)init {
    if (!(self = [super initWithStyle:UITableViewStyleInsetGrouped])) return nil;
    self.title = SGL(@"settings.audioeffects.presets.title", @"Presets");
    _builtIn = SGDSPBuiltInPresetNames();
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    _footer = SGNote([NSString stringWithFormat:@"%@\n\n%@", SGL(@"settings.audioeffects.presets.footer", @"Picking a preset turns Audio effects on and replaces the other effects' settings. A built-in "
                      "preset leaves the Graphic EQ, your headphones' correction, as it is; your own presets keep every "
                      "effect, the Graphic EQ too. What you had before the first pick is kept under Yours as Before presets. "
                      "Swipe left on one of yours to delete it."),
                      SGL(@"settings.audioeffects.presets.sharing.footer", @"Swipe left on one of yours to share it as a file, and import a file someone sent you to add it to yours. "
                          "A preset names the impulse response, DDC or Liveprog file it uses without carrying it, so send that file along.")]);
    self.tableView.tableFooterView = _footer;
}

- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    SGFitNote(self.tableView, _footer, 16, 24);
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    SGInsetForBars(self.tableView);
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    _mine = userPresetNames();
    [self.tableView reloadData];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)table {
    return 3;
}

- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return (NSInteger)_builtIn.count;
    if (section == 1) return MAX((NSInteger)_mine.count, 1);
    return kActionRows;
}

- (UIView *)tableView:(UITableView *)table viewForHeaderInSection:(NSInteger)section {
    return section == 2 ? nil : SGSectionHeader(table, section == 0 ? SGL(@"settings.audioeffects.presets.builtin.header", @"Built in") : SGL(@"settings.audioeffects.presets.yours.header", @"Yours"));
}

- (CGFloat)tableView:(UITableView *)table heightForHeaderInSection:(NSInteger)section {
    return section == 2 ? SGSectionGap : SGSectionHeaderHeight();
}

- (UIView *)tableView:(UITableView *)table viewForFooterInSection:(NSInteger)section {
    return nil;
}

- (CGFloat)tableView:(UITableView *)table heightForFooterInSection:(NSInteger)section {
    return CGFLOAT_MIN;
}

- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell = SGDequeueCell(table, @"preset");
    if (path.section == 2) {
        if (path.row == kImportRow) {
            SGFillCell(cell, SGL(@"settings.audioeffects.presets.import.title", @"Import preset file…"), SGL(@"settings.audioeffects.presets.import.subtitle", @"A preset someone shared, from Files"), nil, @"tray.and.arrow.down");
        } else {
            SGFillCell(cell, SGL(@"settings.audioeffects.presets.savecurrent.title", @"Save current settings…"), SGL(@"settings.audioeffects.presets.savecurrent.subtitle", @"Every effect as it is now, under a name"), nil, @"square.and.arrow.down");
        }
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
        cell.accessibilityTraits = UIAccessibilityTraitButton;
        return cell;
    }
    if (path.section == 1 && !_mine.count) {
        SGFillCell(cell, SGL(@"settings.audioeffects.presets.nonesaved", @"None saved yet"), nil, SGGrey(), nil);
        cell.accessibilityTraits = UIAccessibilityTraitNone;
        return cell;
    }
    BOOL builtIn = path.section == 0;
    SGFillCell(cell, builtIn ? _builtIn[(NSUInteger)path.row] : userPresetTitle(_mine[(NSUInteger)path.row]), builtIn ? SGDSPBuiltInPresetDetail(path.row) : nil, nil, nil);
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    tick(cell, [path isEqual:_picked]);
    return cell;
}

- (BOOL)tableView:(UITableView *)table shouldHighlightRowAtIndexPath:(NSIndexPath *)path {
    return path.section != 1 || _mine.count;
}

- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)path {
    [table deselectRowAtIndexPath:path animated:YES];
    if (path.section == 2) {
        if (path.row == kImportRow) [self pickFile];
        else [self askForName];
        return;
    }
    if (path.section == 1 && !_mine.count) return;
    NSString *name = path.section == 1 ? _mine[(NSUInteger)path.row] : nil;
    // Loading Before presets itself is the way back, so it is never written over by its own pick.
    if (!_kept && ![name isEqualToString:kBeforePresets]) {
        SGDSPSaveUserPreset(kBeforePresets);
        _kept = YES;
        _mine = userPresetNames();
    }
    if (path.section == 0) SGDSPLoadBuiltInPreset(path.row);
    else if (!SGDSPLoadUserPreset(name)) return;
    _picked = name ? [NSIndexPath indexPathForRow:(NSInteger)[_mine indexOfObject:name] inSection:1] : path;
    [table reloadSections:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, 2)] withRowAnimation:UITableViewRowAnimationNone];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)table trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)path {
    if (path.section != 1 || !_mine.count) return nil;
    NSString *name = _mine[(NSUInteger)path.row];
    UIContextualAction *delete = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:SGL(@"common.delete", @"Delete")
        handler:^(UIContextualAction *action, UIView *view, void (^done)(BOOL)) {
            SGDSPDeleteUserPreset(name);
            self->_mine = userPresetNames();
            NSIndexPath *picked = self->_picked;
            if (picked.section == 1 && picked.row == path.row) self->_picked = nil;
            else if (picked.section == 1 && picked.row > path.row) self->_picked = [NSIndexPath indexPathForRow:picked.row - 1 inSection:1];
            // The rows under it close up; the last one gives way to the placeholder instead.
            if (self->_mine.count) [self.tableView deleteRowsAtIndexPaths:@[path] withRowAnimation:UITableViewRowAnimationAutomatic];
            else [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:1] withRowAnimation:UITableViewRowAnimationFade];
            done(YES);
        }];
    delete.image = [UIImage systemImageNamed:@"trash"];
    UIContextualAction *share = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:SGL(@"settings.audioeffects.presets.action.share", @"Share")
        handler:^(UIContextualAction *action, UIView *view, void (^done)(BOOL)) {
            [self share:name from:[self.tableView cellForRowAtIndexPath:path] ?: view];
            done(YES);
        }];
    share.image = [UIImage systemImageNamed:@"square.and.arrow.up"];
    share.backgroundColor = UIColor.systemBlueColor;
    UISwipeActionsConfiguration *configuration = [UISwipeActionsConfiguration configurationWithActions:@[delete, share]];
    configuration.performsFirstActionWithFullSwipe = NO;
    return configuration;
}

// A long press on one of yours offers the same, for anyone who does not swipe.
- (UIContextMenuConfiguration *)tableView:(UITableView *)table contextMenuConfigurationForRowAtIndexPath:(NSIndexPath *)path point:(CGPoint)point {
    if (path.section != 1 || !_mine.count) return nil;
    NSString *name = _mine[(NSUInteger)path.row];
    __weak SGDSPPresetList *page = self;
    return [UIContextMenuConfiguration configurationWithIdentifier:nil previewProvider:nil actionProvider:^UIMenu *(NSArray<UIMenuElement *> *suggested) {
        UIAction *share = [UIAction actionWithTitle:SGL(@"settings.audioeffects.presets.action.share", @"Share") image:[UIImage systemImageNamed:@"square.and.arrow.up"] identifier:nil
            handler:^(UIAction *action) { [page share:name from:[page.tableView cellForRowAtIndexPath:path]]; }];
        return [UIMenu menuWithChildren:@[share]];
    }];
}

- (void)share:(NSString *)name from:(UIView *)source {
    NSURL *url = sharedFileFor(name);
    if (!url) {
        SGPresentInformation(self, SGL(@"settings.audioeffects.presets.share_failed.alert.title", @"Could not share the preset"), SGL(@"settings.stats.error.try_again", @"Please try again."));
        return;
    }
    UIActivityViewController *sheet = [[UIActivityViewController alloc] initWithActivityItems:@[url] applicationActivities:nil];
    NSURL *folder = url.URLByDeletingLastPathComponent;
    sheet.completionWithItemsHandler = ^(UIActivityType type, BOOL completed, NSArray *items, NSError *error) {
        [NSFileManager.defaultManager removeItemAtURL:folder error:nil];
    };
    sheet.popoverPresentationController.sourceView = source ?: self.view;
    sheet.popoverPresentationController.sourceRect = (source ?: self.view).bounds;
    SGPresentDark(sheet);
    [self presentViewController:sheet animated:YES completion:nil];
}

#pragma mark - importing a file

- (void)pickFile {
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeJSON, UTTypeData] asCopy:YES];
    picker.delegate = self;
    picker.allowsMultipleSelection = NO;
    SGPresentDark(picker);
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)picker didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url = urls.firstObject;
    if (!url) return;
    NSString *fallback = url.lastPathComponent;
    // Old exports use the previous suffix; strip it too when deriving a name.
    for (NSString *suffix in @[@".retrine-preset.json", @".vitrine-preset.json", @".json"]) {
        if ([fallback.lowercaseString hasSuffix:suffix]) { fallback = [fallback substringToIndex:fallback.length - suffix.length]; break; }
    }
    __weak SGDSPPresetList *page = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        // A copy in the app's own inbox, so no security scope is needed. A file over the limit is not read at all.
        NSDictionary *attributes = [NSFileManager.defaultManager attributesOfItemAtPath:url.path error:nil];
        BOOL tooLarge = [attributes fileSize] > 256 * 1024;
        NSData *data = tooLarge ? nil : [NSData dataWithContentsOfURL:url options:NSDataReadingMappedIfSafe error:nil];
        NSString *name = nil, *error = nil;
        NSDictionary<NSString *, id> *values = tooLarge ? nil : SGDSPReadPresetFile(data, fallback, &name, &error);
        if (tooLarge) error = SGL(@"settings.audioeffects.presetfile.error.toolarge", @"This preset file is too large.");
        dispatch_async(dispatch_get_main_queue(), ^{
            SGDSPPresetList *strong = page;
            if (!strong) return;
            if (!values) {
                SGPresentInformation(strong, SGL(@"settings.audioeffects.presets.import_failed.alert.title", @"Preset not imported"), error);
                return;
            }
            if (SGDSPUserPresetExists(name)) [strong ask:name values:values];
            else [strong keep:values as:name];
        });
    });
}

// A preset of the same name is replaced only when asked; the other choice keeps both under a new name.
- (void)ask:(NSString *)name values:(NSDictionary<NSString *, id> *)values {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:SGL(@"settings.audioeffects.presets.import_exists.alert.title", @"You already have “%@”"), userPresetTitle(name)]
        message:SGL(@"settings.audioeffects.presets.import_exists.alert.message", @"Replace it with the file's preset, or keep both.") preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:SGL(@"common.cancel", @"Cancel") style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:SGL(@"settings.audioeffects.presets.action.keep_both", @"Keep both") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self keep:values as:SGDSPUniquePresetName(name)];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:SGL(@"settings.audioeffects.presets.action.replace", @"Replace") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        [self keep:values as:name];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

// Saved under Yours, not applied: a tap on it is how it is heard, as with any preset of the user's.
- (void)keep:(NSDictionary<NSString *, id> *)values as:(NSString *)name {
    SGDSPSaveUserPresetValues(name, values);
    _mine = userPresetNames();
    NSIndexPath *picked = _picked;
    if (picked.section == 1) _picked = nil;   // the rows under Yours may have moved
    [self.tableView reloadSections:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, 2)] withRowAnimation:UITableViewRowAnimationFade];
    NSArray<NSString *> *missing = SGDSPPresetMissingFiles(values);
    NSString *message = missing.count
        ? [NSString stringWithFormat:SGL(@"settings.audioeffects.presets.imported.missing.alert.message", @"“%@” is under Yours. It uses files this iPhone does not have: %@. Import them on the Audio effects page, or the effects that need them stay silent."),
           userPresetTitle(name), [missing componentsJoinedByString:@", "]]
        : [NSString stringWithFormat:SGL(@"settings.audioeffects.presets.imported.alert.message", @"“%@” is under Yours. Tap it to hear it."), userPresetTitle(name)];
    SGPresentInformation(self, SGL(@"settings.audioeffects.presets.imported.alert.title", @"Preset imported"), message);
}

- (void)askForName {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:SGL(@"settings.audioeffects.presets.save.alert.title", @"Save preset")
        message:SGL(@"settings.audioeffects.presets.save.alert.message", @"A preset of the same name is replaced.") preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = SGL(@"settings.audioeffects.presets.name.placeholder", @"Name");
        field.autocapitalizationType = UITextAutocapitalizationTypeSentences;
        field.keyboardAppearance = UIKeyboardAppearanceDark;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:SGL(@"common.cancel", @"Cancel") style:UIAlertActionStyleCancel handler:nil]];
    // The alert holds its actions and their handlers, so the handler must not hold the alert back.
    __weak UIAlertController *weakAlert = alert;
    [alert addAction:[UIAlertAction actionWithTitle:SGL(@"common.save", @"Save") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *name = [weakAlert.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (!name.length) return;
        SGDSPSaveUserPreset(name);
        self->_mine = userPresetNames();
        self->_picked = [NSIndexPath indexPathForRow:(NSInteger)[self->_mine indexOfObject:name] inSection:1];
        [self.tableView reloadSections:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, 2)] withRowAnimation:UITableViewRowAnimationFade];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end

UIViewController *SGDSPPresetsPage(void) {
    return [SGDSPPresetList new];
}

#pragma mark - headphones

// AutoEq's headphones under a search field, the one in use ticked, with None above them. A tap downloads its
// GraphicEQ and turns the Graphic EQ on with it; None turns it off again. Pulling down fetches the list again.
// Above the field, Use for <the output playing now> remembers the pick for that output (AutoEq.m), and the
// outputs remembered so far are listed with their corrections, a swipe removing one. The field sits right over
// the list it searches, and while it is in use only the list stays under it, the way Settings' search does.
@interface SGDSPHeadphoneList : SGPage <UISearchBarDelegate>
@end

static const CGFloat kSearchTop = 8;   // the field's gap from the card over it
static const CGFloat kFormGap = 4;     // between the field and the form filter under it
static const CGFloat kFormHeight = 32;

typedef NS_ENUM(NSInteger, SGDSPHeadphoneSection) {
    SGDSPHeadphoneOutput,       // Use for <output>, while an output is known and no search is on
    SGDSPHeadphoneRemembered,   // the remembered outputs, while there are any and no search is on
    SGDSPHeadphoneSearch,       // no rows: the search field is its header
    SGDSPHeadphoneNone,         // while no search is on
    SGDSPHeadphoneMessage,      // loading, or why the list did not come
    SGDSPHeadphoneAll,
    SGDSPHeadphoneSections,
};

// The Output section's rows: Use for <output>, then its Preset.
enum { kUseRow, kPresetRow, kOutputRows };

@implementation SGDSPHeadphoneList {
    NSArray<SGAutoEqHeadphone *> *_all, *_shown;
    NSString *_message;          // loading, or why the list did not come
    BOOL _failed;
    NSString *_applying;         // the path being downloaded
    NSArray<NSDictionary<NSString *, NSString *> *> *_remembered;
    UISearchBar *_search;
    UISegmentedControl *_formControl;
    SGAutoEqForm _form;          // All each time the page opens: it is not kept
    UIView *_searchHeader, *_header, *_footer;
    BOOL _searching;             // the field in use, so only the list shows under it
}

- (instancetype)init {
    if (!(self = [super initWithStyle:UITableViewStyleInsetGrouped])) return nil;
    self.title = SGL(@"settings.audioeffects.headphones.title", @"Headphones");
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    UITableView *table = self.tableView;
    table.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    _search = [UISearchBar new];
    _search.placeholder = SGL(@"settings.audioeffects.headphones.search.placeholder", @"Search headphones");
    _search.searchBarStyle = UISearchBarStyleMinimal;
    _search.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    _search.keyboardAppearance = UIKeyboardAppearanceDark;
    _search.delegate = self;
    // The table insets the header to the cards' width; the bar reaches past them by the room it keeps
    // around its field, so the field lines up with the cards.
    _searchHeader = [UIView new];
    _search.translatesAutoresizingMaskIntoConstraints = NO;
    [_searchHeader addSubview:_search];
    // The form filter, in the order of SGAutoEqForm.
    _formControl = [[UISegmentedControl alloc] initWithItems:@[
        SGL(@"settings.audioeffects.headphones.form.all", @"All"), SGL(@"settings.audioeffects.headphones.form.inear", @"In-ear"),
        SGL(@"settings.audioeffects.headphones.form.overear", @"Over-ear"), SGL(@"settings.audioeffects.headphones.form.earbuds", @"Earbuds")]];
    _formControl.selectedSegmentIndex = _form;
    _formControl.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    _formControl.translatesAutoresizingMaskIntoConstraints = NO;
    [_formControl addTarget:self action:@selector(formChanged) forControlEvents:UIControlEventValueChanged];
    [_searchHeader addSubview:_formControl];
    [NSLayoutConstraint activateConstraints:@[
        [_search.leadingAnchor constraintEqualToAnchor:_searchHeader.leadingAnchor constant:-8],
        [_search.trailingAnchor constraintEqualToAnchor:_searchHeader.trailingAnchor constant:8],
        [_search.topAnchor constraintEqualToAnchor:_searchHeader.topAnchor constant:kSearchTop],
        [_search.heightAnchor constraintEqualToConstant:44],
        [_formControl.leadingAnchor constraintEqualToAnchor:_searchHeader.leadingAnchor],
        [_formControl.trailingAnchor constraintEqualToAnchor:_searchHeader.trailingAnchor],
        [_formControl.topAnchor constraintEqualToAnchor:_search.bottomAnchor constant:kFormGap],
        [_formControl.heightAnchor constraintEqualToConstant:kFormHeight],
    ]];
    _header = SGNote(SGL(@"settings.audioeffects.headphones.header", @"Corrections that make your headphones sound neutral, measured by AutoEq. Picking one turns Audio effects and the Graphic EQ on with it."));
    table.tableHeaderView = _header;
    _footer = SGNote(SGL(@"settings.audioeffects.headphones.footer", @"From AutoEq by Jaakko Pasanen, MIT License. Pull down to fetch the list again."));
    table.tableFooterView = _footer;
    self.refreshControl = [UIRefreshControl new];
    [self.refreshControl addTarget:self action:@selector(refresh) forControlEvents:UIControlEventValueChanged];
    _remembered = SGAutoEqRememberedOutputs();
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(outputsChanged) name:SGAutoEqOutputsChangedNotification object:nil];
    [self load:NO];
}

// Another output connected, or a pick changed what one remembers.
- (void)outputsChanged {
    _remembered = SGAutoEqRememberedOutputs();
    [self reload:UITableViewRowAnimationNone];
}

// Every section but the field's: reloading the header the field is in would take the keyboard away mid-word.
- (void)reload:(UITableViewRowAnimation)animation {
    NSMutableIndexSet *sections = [NSMutableIndexSet indexSetWithIndexesInRange:NSMakeRange(0, SGDSPHeadphoneSections)];
    [sections removeIndex:SGDSPHeadphoneSearch];
    [self.tableView reloadSections:sections withRowAnimation:animation];
}

- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    SGFitNote(self.tableView, _header, 4, 8);
    SGFitNote(self.tableView, _footer, 16, 24);
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    SGInsetForBars(self.tableView);
}

- (void)refresh {
    [self load:YES];
}

- (void)load:(BOOL)refresh {
    if (!_all) _message = SGL(@"settings.audioeffects.headphones.loading", @"Loading AutoEq's list…");
    _failed = NO;
    // From viewDidLoad the table has not asked for its rows yet, and will.
    if (self.tableView.window) [self reload:UITableViewRowAnimationNone];
    SGAutoEqLoadIndex(refresh, ^(NSArray<SGAutoEqHeadphone *> *headphones, NSString *error) {
        [self.refreshControl endRefreshing];
        if (headphones) self->_all = headphones;
        self->_failed = error != nil;
        self->_message = error ? [NSString stringWithFormat:SGL(@"settings.audioeffects.headphones.retry.format", @"%@. Tap to try again."), error] : nil;
        [self filter];
    });
}

- (void)formChanged {
    _form = (SGAutoEqForm)_formControl.selectedSegmentIndex;
    [self filter];
}

- (void)filter {
    _shown = SGAutoEqFilterByForm(SGAutoEqSearch(_all ?: @[], _search.text), _form);
    BOOL searching = _search.isFirstResponder || _search.text.length > 0;
    BOOL changed = searching != _searching;
    _searching = searching;
    // No fade: one over thousands of rows leaves the cards half drawn while the field moves up.
    [self reload:UITableViewRowAnimationNone];
    // What went from over the field could have taken it off the screen.
    if (changed && searching) {
        [self.tableView scrollRectToVisible:[self.tableView rectForHeaderInSection:SGDSPHeadphoneSearch] animated:YES];
    }
}

- (void)searchBar:(UISearchBar *)bar textDidChange:(NSString *)text {
    [self filter];
}

- (void)searchBarTextDidBeginEditing:(UISearchBar *)bar {
    [self filter];
}

- (void)searchBarTextDidEndEditing:(UISearchBar *)bar {
    [self filter];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)bar {
    [bar resignFirstResponder];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)table {
    return SGDSPHeadphoneSections;
}

- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case SGDSPHeadphoneMessage: return _message ? 1 : 0;
        case SGDSPHeadphoneOutput: return SGAutoEqOutputUID() && !_searching ? kOutputRows : 0;
        case SGDSPHeadphoneRemembered: return _searching ? 0 : (NSInteger)_remembered.count;
        case SGDSPHeadphoneSearch: return 0;
        case SGDSPHeadphoneNone: return _searching ? 0 : 1;
        default: return _all && !_shown.count ? 1 : (NSInteger)_shown.count;
    }
}

- (UIView *)tableView:(UITableView *)table viewForHeaderInSection:(NSInteger)section {
    if (section == SGDSPHeadphoneSearch) return _searchHeader;
    return section == SGDSPHeadphoneRemembered && [self tableView:table numberOfRowsInSection:section] ? SGSectionHeader(table, SGL(@"settings.audioeffects.headphones.remembered.header", @"Remembered outputs")) : nil;
}

- (CGFloat)tableView:(UITableView *)table heightForHeaderInSection:(NSInteger)section {
    if (section == SGDSPHeadphoneSearch) return kSearchTop + 44 + kFormGap + kFormHeight + 4;
    if ([self tableView:table numberOfRowsInSection:section] == 0) return CGFLOAT_MIN;
    return section == SGDSPHeadphoneRemembered ? SGSectionHeaderHeight() : SGSectionGap;
}

- (NSString *)outputFooter {
    NSString *name = SGAutoEqOutputName();
    return [NSString stringWithFormat:SGL(@"settings.audioeffects.headphones.output.footer", @"With this on, the correction you pick is kept for %@. It comes back each time audio plays through "
            "%@, and goes off on outputs with none remembered."), name, name];
}

- (UIView *)tableView:(UITableView *)table viewForFooterInSection:(NSInteger)section {
    return section == SGDSPHeadphoneOutput && [self tableView:table numberOfRowsInSection:section] ? SGSectionFooter(table, [self outputFooter]) : nil;
}

- (CGFloat)tableView:(UITableView *)table heightForFooterInSection:(NSInteger)section {
    return section == SGDSPHeadphoneOutput && [self tableView:table numberOfRowsInSection:section] ? SGSectionFooterHeight(table, [self outputFooter]) : CGFLOAT_MIN;
}

// A remembered output's correction, by name.
static NSString *correctionName(NSString *path) {
    return path.length ? SGAutoEqNameOf(path) : SGL(@"settings.audioeffects.headphones.none", @"None");
}

// The name of the user's preset an output plays; empty for None, which a preset since deleted is too.
static NSString *outputPresetName(NSString *uid) {
    NSString *name = SGAutoEqOutputPreset(uid);
    return SGDSPUserPresetExists(name) ? name : @"";
}

// The Preset row's choice: None and the user's presets in a menu, the one in use ticked.
- (UIButton *)presetButton {
    NSString *current = outputPresetName(SGAutoEqOutputUID());
    NSMutableArray<UIMenuElement *> *items = [NSMutableArray array];
    UIAction *none = [UIAction actionWithTitle:SGL(@"settings.audioeffects.headphones.none", @"None") image:nil identifier:nil
        handler:^(UIAction *action) { SGAutoEqSetOutputPreset(nil); }];
    none.state = current.length ? UIMenuElementStateOff : UIMenuElementStateOn;
    [items addObject:none];
    for (NSString *name in userPresetNames()) {
        UIAction *item = [UIAction actionWithTitle:userPresetTitle(name) image:nil identifier:nil
            handler:^(UIAction *action) { SGAutoEqSetOutputPreset(name); }];
        item.state = [name isEqualToString:current] ? UIMenuElementStateOn : UIMenuElementStateOff;
        [items addObject:item];
    }
    UIButtonConfiguration *configuration = [UIButtonConfiguration plainButtonConfiguration];
    configuration.title = current.length ? userPresetTitle(current) : SGL(@"settings.audioeffects.headphones.none", @"None");
    configuration.baseForegroundColor = SGGrey();
    configuration.image = [UIImage systemImageNamed:@"chevron.up.chevron.down"];
    configuration.imagePlacement = NSDirectionalRectEdgeTrailing;
    configuration.imagePadding = 6;
    UIButton *button = [UIButton buttonWithConfiguration:configuration primaryAction:nil];
    button.menu = [UIMenu menuWithChildren:items];
    button.showsMenuAsPrimaryAction = YES;
    button.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    [button sizeToFit];
    return button;
}

- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell = SGDequeueCell(table, @"headphone");
    cell.accessoryView = nil;
    if (path.section == SGDSPHeadphoneOutput && path.row == kPresetRow) {
        SGFillCell(cell, SGL(@"settings.audioeffects.preset.title", @"Preset"),
                   [NSString stringWithFormat:SGL(@"settings.audioeffects.headphones.preset.subtitle.format", @"Applied while %@ plays"), SGAutoEqOutputName()], nil, nil);
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.accessoryView = [self presetButton];
        cell.accessibilityTraits = UIAccessibilityTraitNone;
        return cell;
    }
    if (path.section == SGDSPHeadphoneOutput) {
        NSString *uid = SGAutoEqOutputUID();
        BOOL remembered = SGAutoEqOutputRemembered(uid);
        NSString *current = correctionName(SGAutoEqCorrectionInUse() ? SGDSPString(SGKeyDSPGraphicEqHeadphone) : nil);
        SGFillCell(cell, [NSString stringWithFormat:SGL(@"settings.audioeffects.headphones.usefor.format", @"Use for %@"), SGAutoEqOutputName()],
                   remembered ? [NSString stringWithFormat:SGL(@"settings.audioeffects.headphones.whileplays.format", @"%@ while it plays"), current] : [NSString stringWithFormat:SGL(@"settings.audioeffects.headphones.rememberfor.format", @"Remember %@ for this output"), current], nil, nil);
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        UISwitch *toggle = [UISwitch new];
        toggle.onTintColor = SGGreen();
        toggle.on = remembered;
        [toggle addTarget:self action:@selector(useToggled:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = toggle;
        cell.accessibilityTraits = UIAccessibilityTraitNone;
        return cell;
    }
    if (path.section == SGDSPHeadphoneRemembered) {
        NSDictionary<NSString *, NSString *> *output = _remembered[(NSUInteger)path.row];
        BOOL now = [output[@"uid"] isEqualToString:SGAutoEqOutputUID()];
        NSString *detail = correctionName(output[@"path"]), *preset = outputPresetName(output[@"uid"]);
        if (preset.length) detail = [NSString stringWithFormat:SGL(@"settings.audioeffects.headphones.withpreset.format", @"%@ · preset %@"), detail, userPresetTitle(preset)];
        SGFillCell(cell, output[@"name"], now ? [NSString stringWithFormat:SGL(@"settings.audioeffects.headphones.playingnow.format", @"%@ · playing now"), detail] : detail, nil, nil);
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.accessibilityTraits = UIAccessibilityTraitNone;
        cell.accessibilityHint = SGL(@"settings.audioeffects.headphones.swipehint", @"Swipe left to remove");
        return cell;
    }
    cell.accessibilityHint = nil;
    if (path.section == SGDSPHeadphoneMessage) {
        SGFillCell(cell, _message, nil, _failed ? SGRed() : SGGrey(), _failed ? @"exclamationmark.triangle.fill" : nil);
        cell.selectionStyle = _failed ? UITableViewCellSelectionStyleDefault : UITableViewCellSelectionStyleNone;
        return cell;
    }
    cell.accessibilityValue = nil;
    if (path.section == SGDSPHeadphoneNone) {
        SGFillCell(cell, SGL(@"settings.audioeffects.headphones.none", @"None"), nil, nil, nil);
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
        tick(cell, !SGAutoEqCorrectionInUse());
        return cell;
    }
    if (!_shown.count) {
        SGFillCell(cell, SGL(@"settings.audioeffects.headphones.nomatch", @"No headphones match"), nil, SGGrey(), nil);
        cell.accessibilityTraits = UIAccessibilityTraitNone;
        return cell;
    }
    SGAutoEqHeadphone *headphone = _shown[(NSUInteger)path.row];
    SGFillCell(cell, headphone.name, headphone.source, nil, nil);
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    if ([headphone.path isEqualToString:_applying]) {
        UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
        spinner.color = SGGrey();
        spinner.accessibilityLabel = SGL(@"settings.audioeffects.headphones.applying.a11y", @"Applying");
        [spinner startAnimating];
        cell.accessoryView = spinner;
        // The cell is what VoiceOver reads, not the spinner in it.
        cell.accessibilityValue = SGL(@"settings.audioeffects.headphones.applying.value", @"Applying");
        return cell;
    }
    tick(cell, SGAutoEqCorrectionInUse() && [headphone.path isEqualToString:SGDSPString(SGKeyDSPGraphicEqHeadphone)]);
    return cell;
}

- (BOOL)tableView:(UITableView *)table shouldHighlightRowAtIndexPath:(NSIndexPath *)path {
    if (path.section == SGDSPHeadphoneMessage) return _failed;
    if (path.section == SGDSPHeadphoneOutput || path.section == SGDSPHeadphoneRemembered) return NO;
    return (path.section == SGDSPHeadphoneNone || _shown.count > 0) && !_applying;
}

- (void)useToggled:(UISwitch *)toggle {
    SGAutoEqRememberOutput(toggle.on);
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)table trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)path {
    if (path.section != SGDSPHeadphoneRemembered) return nil;
    NSString *uid = _remembered[(NSUInteger)path.row][@"uid"];
    UIContextualAction *remove = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:SGL(@"common.remove", @"Remove")
        handler:^(UIContextualAction *action, UIView *view, void (^done)(BOOL)) {
            SGAutoEqForgetOutput(uid);
            done(YES);
        }];
    remove.image = [UIImage systemImageNamed:@"trash"];
    return [UISwipeActionsConfiguration configurationWithActions:@[remove]];
}

- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)path {
    [table deselectRowAtIndexPath:path animated:YES];
    if (path.section == SGDSPHeadphoneMessage) {
        if (_failed) [self load:YES];
        return;
    }
    if (_applying || path.section == SGDSPHeadphoneOutput || path.section == SGDSPHeadphoneRemembered) return;
    if (path.section == SGDSPHeadphoneNone) {
        // Only a headphone's correction is taken off: a curve of the user's own, with no headphone, stays.
        SGAutoEqTakeOff();
        [self reload:UITableViewRowAnimationNone];
        return;
    }
    if (!_shown.count) return;
    SGAutoEqHeadphone *headphone = _shown[(NSUInteger)path.row];
    _applying = headphone.path;
    [self reload:UITableViewRowAnimationNone];
    SGAutoEqApply(headphone, ^(NSString *error) {
        self->_applying = nil;
        [self reload:UITableViewRowAnimationNone];
        if (error) SGPresentInformation(self, [NSString stringWithFormat:SGL(@"settings.audioeffects.headphones.applyerror.title", @"Could not apply %@"), headphone.name], error);
    });
}

@end

UIViewController *SGDSPHeadphonesPage(void) {
    return [SGDSPHeadphoneList new];
}

NSString *SGDSPHeadphoneSummary(void) {
    NSString *path = SGDSPString(SGKeyDSPGraphicEqHeadphone);
    return path.length && SGDSPSwitch(SGKeyDSPGraphicEq) ? SGAutoEqNameOf(path) : SGL(@"settings.audioeffects.headphones.none", @"None");
}
