// The pages a file effect's row and the Graphic EQ's row push: a library of files with the chosen one
// ticked, and the GraphicEQ text to paste or edit. Each shows the effect's error, if its last change did
// not take, in a red card at the top, looked at again once a second while the page is open.
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import "Core/SGCore.h"
#import "Settings/SGPage.h"
#import "Settings/SGPageStyle.h"
#import "AudioEffectsPage.h"
#import "AudioEffectsApply.h"
#import "AudioEffectsPresets.h"

static NSString *const kAutoEqURL = @"https://github.com/jaakkopasanen/AutoEq";
// Main-thread requests, shared across page instances for the same library.
static NSUInteger sg_libraryRequest[SGDSPFileLiveprog + 1];

NSString *SGDSPChosenFile(SGDSPFileKind kind) {
    NSString *name = SGDSPString(SGDSPFileKey(kind));
    return name.length ? name : SGL(@"settings.audioeffects.library.none", @"None");
}

// ".eel", ".vdc", ".wav, .flac or .irs".
static NSString *extensionList(SGDSPFileKind kind) {
    NSMutableArray<NSString *> *dotted = [NSMutableArray array];
    for (NSString *extension in SGDSPFileExtensions(kind)) [dotted addObject:[@"." stringByAppendingString:extension]];
    if (dotted.count < 2) return dotted.firstObject ?: @"";
    NSString *last = dotted.lastObject;
    [dotted removeLastObject];
    return [NSString stringWithFormat:SGL(@"settings.audioeffects.library.extensions.format", @"%@ or %@"), [dotted componentsJoinedByString:@", "], last];
}

UITableViewCell *SGDSPErrorCell(UITableView *table, NSString *text) {
    UITableViewCell *cell = SGDequeueCell(table, @"error");
    SGFillCell(cell, SGL(@"settings.audioeffects.status.notapplied", @"Not applied"), text, SGRed(), @"exclamationmark.triangle.fill");
    UIListContentConfiguration *content = (UIListContentConfiguration *)cell.contentConfiguration;
    content.secondaryTextProperties.color = SGRed();
    cell.contentConfiguration = content;
    return cell;
}

static UITableViewCell *tiledCell(UITableView *table, NSString *title, NSString *subtitle, NSString *symbol, UIColor *color) {
    UITableViewCell *cell = SGDequeueCell(table, @"action");
    SGFillCell(cell, title, subtitle, color, nil);
    UIListContentConfiguration *content = (UIListContentConfiguration *)cell.contentConfiguration;
    content.image = SGTileImage(symbol);
    content.imageToTextPadding = 14;
    cell.contentConfiguration = content;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    cell.separatorInset = UIEdgeInsetsMake(0, 58, 0, 0);
    return cell;
}

#pragma mark - the error card

// A page of this file whose section 0 is the effect's error: one red row while there is one, nothing
// otherwise, the row coming and going without the page reloading.
@interface SGDSPErrorPage : SGPage
@property (nonatomic, copy) NSString *errorKey;
@end

@implementation SGDSPErrorPage {
    NSString *_error;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    SGInsetForBars(self.tableView);
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    _error = SGDSPError(self.errorKey);
    [self.tableView reloadData];
    self.refreshSelector = @selector(showError);
}

- (void)showError {
    NSString *now = SGDSPError(self.errorKey);
    if (now == _error || [now isEqualToString:_error]) return;
    NSString *shown = _error;
    NSIndexPath *path = [NSIndexPath indexPathForRow:0 inSection:0];
    [self.tableView performBatchUpdates:^{
        self->_error = now;
        if (shown && now) [self.tableView reloadRowsAtIndexPaths:@[path] withRowAnimation:UITableViewRowAnimationFade];
        else if (now) [self.tableView insertRowsAtIndexPaths:@[path] withRowAnimation:UITableViewRowAnimationFade];
        else [self.tableView deleteRowsAtIndexPaths:@[path] withRowAnimation:UITableViewRowAnimationFade];
    } completion:nil];
}

- (NSInteger)errorRows {
    return _error ? 1 : 0;
}

- (UITableViewCell *)errorCellIn:(UITableView *)table {
    return SGDSPErrorCell(table, _error);
}

- (UIView *)tableView:(UITableView *)table viewForHeaderInSection:(NSInteger)section {
    return nil;
}

- (CGFloat)tableView:(UITableView *)table heightForHeaderInSection:(NSInteger)section {
    return section == 0 && !_error ? CGFLOAT_MIN : SGSectionGap;
}

- (UIView *)tableView:(UITableView *)table viewForFooterInSection:(NSInteger)section {
    return nil;
}

- (CGFloat)tableView:(UITableView *)table heightForFooterInSection:(NSInteger)section {
    return CGFLOAT_MIN;
}

@end

#pragma mark - a library

// The files of one kind, the chosen one ticked: a tap chooses a file and uses it straight away, and the
// page stays, so one after another can be heard. A swipe deletes one; Import file… copies one in from Files.
@interface SGDSPFilesPage : SGDSPErrorPage <UIDocumentPickerDelegate>
- (instancetype)initWithKind:(SGDSPFileKind)kind;
@end

@implementation SGDSPFilesPage {
    SGDSPFileKind _kind;
    NSArray<NSString *> *_files;
    UIView *_footer;
}

- (instancetype)initWithKind:(SGDSPFileKind)kind {
    if (!(self = [super initWithStyle:UITableViewStyleInsetGrouped])) return nil;
    _kind = kind;
    ++sg_libraryRequest[kind];
    self.errorKey = SGDSPEffectOf(SGDSPFileKey(kind));
    self.title = kind == SGDSPFileImpulseResponse ? SGL(@"settings.audioeffects.library.impulseresponses.title", @"Impulse responses") : kind == SGDSPFileDDC ? SGL(@"settings.audioeffects.library.ddcfiles.title", @"DDC files") : SGL(@"settings.audioeffects.library.scripts.title", @"Scripts");
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    _footer = SGNote(SGL(@"settings.audioeffects.library.footer", @"Choosing a file uses it straight away. Swipe left on one to delete it."));
    self.tableView.tableFooterView = _footer;
}

- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    SGFitNote(self.tableView, _footer, 16, 24);
}

- (void)viewWillAppear:(BOOL)animated {
    _files = SGDSPLibraryFiles(_kind);
    [super viewWillAppear:animated];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)table {
    return 3;
}

- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return [self errorRows];
    if (section == 1) return MAX((NSInteger)_files.count, 1);
    return 1;
}

- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    if (path.section == 0) return [self errorCellIn:table];
    if (path.section == 2) {
        NSString *subtitle = [NSString stringWithFormat:SGL(@"settings.audioeffects.library.import.subtitle", @"A %@ file from Files"), extensionList(_kind)];
        return tiledCell(table, SGL(@"settings.audioeffects.library.import.title", @"Import file…"), subtitle, @"square.and.arrow.down", nil);
    }
    UITableViewCell *cell = SGDequeueCell(table, @"file");
    if (!_files.count) {
        SGFillCell(cell, SGL(@"settings.audioeffects.library.nofiles", @"No files yet"), nil, SGGrey(), nil);
        cell.accessibilityTraits = UIAccessibilityTraitNone;
        return cell;
    }
    NSString *name = _files[(NSUInteger)path.row];
    BOOL chosen = [name isEqualToString:SGDSPString(SGDSPFileKey(_kind))];
    SGFillCell(cell, name, nil, nil, nil);
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    if (chosen) {
        UIImageView *tick = SGSymbolView(@"checkmark", 13, UIImageSymbolWeightSemibold, 16);
        tick.tintColor = SGGreen();
        cell.accessoryView = tick;
    }
    cell.accessibilityTraits = chosen ? UIAccessibilityTraitButton | UIAccessibilityTraitSelected : UIAccessibilityTraitButton;
    return cell;
}

- (BOOL)tableView:(UITableView *)table shouldHighlightRowAtIndexPath:(NSIndexPath *)path {
    return path.section == 2 || (path.section == 1 && _files.count);
}

- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)path {
    [table deselectRowAtIndexPath:path animated:YES];
    if (path.section == 2) {
        [self pickFile];
        return;
    }
    if (path.section != 1 || !_files.count) return;
    ++sg_libraryRequest[_kind];
    SGDSPSetString(SGDSPFileKey(_kind), _files[(NSUInteger)path.row]);
    [table reloadSections:[NSIndexSet indexSetWithIndex:1] withRowAnimation:UITableViewRowAnimationNone];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)table trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)path {
    if (path.section != 1 || !_files.count) return nil;
    NSString *name = _files[(NSUInteger)path.row];
    UIContextualAction *delete = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:SGL(@"common.delete", @"Delete")
        handler:^(UIContextualAction *action, UIView *view, void (^done)(BOOL)) {
            [self deleteFile:name at:path];
            done(YES);
        }];
    delete.image = [UIImage systemImageNamed:@"trash"];
    return [UISwipeActionsConfiguration configurationWithActions:@[delete]];
}

// The chosen file going leaves the effect with none, rather than naming a file that is not there.
- (void)deleteFile:(NSString *)name at:(NSIndexPath *)path {
    ++sg_libraryRequest[_kind];
    if (!SGDSPDeleteFile(_kind, name)) {
        SGPresentInformation(self, SGL(@"settings.audioeffects.library.deleteerror.title", @"Could not delete the file"), nil);
        return;
    }
    if ([name isEqualToString:SGDSPString(SGDSPFileKey(_kind))]) SGDSPSetString(SGDSPFileKey(_kind), @"");
    _files = SGDSPLibraryFiles(_kind);
    if (_files.count) [self.tableView deleteRowsAtIndexPaths:@[path] withRowAnimation:UITableViewRowAnimationAutomatic];
    else [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:1] withRowAnimation:UITableViewRowAnimationFade];
}

// .eel, .vdc and .irs are nobody's registered types, so the picker offers any file and the name is
// checked after.
- (void)pickFile {
    ++sg_libraryRequest[_kind];
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeData] asCopy:YES];
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)picker didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url = urls.firstObject;
    if (!url) return;
    if (![SGDSPFileExtensions(_kind) containsObject:url.pathExtension.lowercaseString]) {
        SGPresentInformation(self, SGL(@"settings.audioeffects.library.invalidfile.title", @"Not a file this effect takes"), [NSString stringWithFormat:SGL(@"settings.audioeffects.library.invalidfile.message", @"Pick a %@ file."), extensionList(_kind)]);
        return;
    }
    static dispatch_queue_t imports;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ imports = dispatch_queue_create("spotifyglass.dsp.import", DISPATCH_QUEUE_SERIAL); });
    SGDSPFileKind kind = _kind;
    NSUInteger request = ++sg_libraryRequest[kind];
    NSString *selection = SGDSPString(SGDSPFileKey(kind));
    dispatch_async(imports, ^{
        NSError *error = nil;
        NSString *name = SGDSPImportFile(kind, url, &error);
        NSArray<NSString *> *files = name ? SGDSPLibraryFiles(kind) : nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            BOOL current = request == sg_libraryRequest[kind]
                && [selection isEqualToString:SGDSPString(SGDSPFileKey(kind))];
            if (!name) {
                if (current) SGPresentInformation(self, SGL(@"settings.audioeffects.library.importerror.title", @"Could not import the file"), error.localizedDescription);
                return;
            }
            // A stale request may not choose a file, but replacing the current
            // file still invalidates the engine's loaded contents.
            if (current || [name isEqualToString:SGDSPString(SGDSPFileKey(kind))])
                SGDSPSetString(SGDSPFileKey(kind), name);
            self->_files = files;
            [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:1] withRowAnimation:UITableViewRowAnimationFade];
        });
    });
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    if (self.isMovingFromParentViewController || self.isBeingDismissed || self.navigationController.isBeingDismissed)
        ++sg_libraryRequest[_kind];
}

@end

UIViewController *SGDSPLibraryPage(SGDSPFileKind kind) {
    return [[SGDSPFilesPage alloc] initWithKind:kind];
}

#pragma mark - the GraphicEQ text

// What the Graphic EQ holds until something is pasted: flat.
static NSString *const kFlatGraphicEq = @"GraphicEQ: 0.0 0.0;";

typedef NS_ENUM(NSInteger, SGGraphicEqRow) {
    SGGraphicEqSave,
    SGGraphicEqPaste,
    SGGraphicEqReset,
    SGGraphicEqRowCount,
};

@interface SGDSPGraphicEqEditor : SGDSPErrorPage <UITextViewDelegate>
@end

@implementation SGDSPGraphicEqEditor {
    UITextView *_text;
    UIView *_intro;
}

- (instancetype)init {
    if (!(self = [super initWithStyle:UITableViewStyleInsetGrouped])) return nil;
    self.title = SGL(@"settings.audioeffects.graphiceq.title", @"Graphic EQ");
    self.errorKey = SGKeyDSPGraphicEq;
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    _intro = SGNote(SGL(@"settings.audioeffects.graphiceq.intro", @"AutoEq's GraphicEQ format: \"GraphicEQ:\", then a frequency and a gain in dB per point, "
                     "separated by semicolons. Paste the GraphicEQ file for your headphones, or edit the text and save."));
    self.tableView.tableHeaderView = _intro;
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;

    _text = [UITextView new];
    _text.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
    _text.textColor = UIColor.whiteColor;
    _text.backgroundColor = UIColor.clearColor;
    _text.textContainerInset = UIEdgeInsetsMake(12, 16, 12, 16);
    _text.textContainer.lineFragmentPadding = 0;
    _text.keyboardAppearance = UIKeyboardAppearanceDark;
    _text.autocorrectionType = UITextAutocorrectionTypeNo;
    _text.autocapitalizationType = UITextAutocapitalizationTypeNone;
    _text.spellCheckingType = UITextSpellCheckingTypeNo;
    _text.smartQuotesType = UITextSmartQuotesTypeNo;
    _text.smartDashesType = UITextSmartDashesTypeNo;
    _text.smartInsertDeleteType = UITextSmartInsertDeleteTypeNo;
    _text.accessibilityLabel = SGL(@"settings.audioeffects.graphiceq.text.a11y", @"GraphicEQ");
    _text.delegate = self;
    _text.text = SGDSPString(SGKeyDSPGraphicEqNodes);
}

- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    SGFitNote(self.tableView, _intro, 24, 0);
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)table {
    return 4;
}

- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return [self errorRows];
    return section == 2 ? SGGraphicEqRowCount : 1;
}

- (CGFloat)tableView:(UITableView *)table heightForRowAtIndexPath:(NSIndexPath *)path {
    return path.section == 1 ? 188 : UITableViewAutomaticDimension;
}

- (BOOL)edited {
    return ![SGDSPGraphicEqLine(_text.text) ?: _text.text isEqualToString:SGDSPString(SGKeyDSPGraphicEqNodes)];
}

- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    if (path.section == 0) return [self errorCellIn:table];
    if (path.section == 1) {
        UITableViewCell *cell = SGDequeueCell(table, @"text");
        cell.backgroundColor = SGCardBackground();
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        _text.frame = cell.contentView.bounds;
        _text.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [cell.contentView addSubview:_text];
        return cell;
    }
    if (path.section == 3) return tiledCell(table, @"AutoEq", SGL(@"settings.audioeffects.graphiceq.autoeq.subtitle", @"GraphicEQ files for thousands of headphones"), @"safari", nil);
    switch (path.row) {
        case SGGraphicEqSave: {
            BOOL edited = [self edited];
            UITableViewCell *cell = tiledCell(table, SGL(@"common.save", @"Save"), edited ? SGL(@"settings.audioeffects.graphiceq.save.edited", @"Use the text above") : SGL(@"settings.audioeffects.graphiceq.save.unchanged", @"Nothing changed"), @"checkmark", edited ? nil : SGGrey());
            cell.accessibilityTraits = edited ? UIAccessibilityTraitButton : UIAccessibilityTraitButton | UIAccessibilityTraitNotEnabled;
            return cell;
        }
        case SGGraphicEqPaste:
            return tiledCell(table, SGL(@"settings.audioeffects.graphiceq.paste.title", @"Paste"), SGL(@"settings.audioeffects.graphiceq.paste.subtitle", @"Replace the text with what you copied, and use it"), @"doc.on.clipboard", nil);
        default:
            return tiledCell(table, SGL(@"common.reset", @"Reset"), SGL(@"settings.audioeffects.graphiceq.reset.subtitle", @"Back to flat"), @"arrow.counterclockwise", nil);
    }
}

- (BOOL)tableView:(UITableView *)table shouldHighlightRowAtIndexPath:(NSIndexPath *)path {
    return path.section == 3 || (path.section == 2 && (path.row != SGGraphicEqSave || [self edited]));
}

- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)path {
    [table deselectRowAtIndexPath:path animated:YES];
    if (path.section == 3) {
        SGOpenURL(kAutoEqURL);
        return;
    }
    if (path.section != 2) return;
    if (path.row == SGGraphicEqSave) [self save:_text.text];
    else if (path.row == SGGraphicEqPaste) [self save:UIPasteboard.generalPasteboard.string];
    else [self save:kFlatGraphicEq];
}

- (void)save:(NSString *)text {
    NSString *line = SGDSPGraphicEqLine(text);
    if (!line) {
        SGPresentInformation(self, text.length ? SGL(@"settings.audioeffects.graphiceq.invalidline.title", @"Not a GraphicEQ line") : SGL(@"settings.audioeffects.graphiceq.nothingtopaste.title", @"Nothing to paste"),
                  SGL(@"settings.audioeffects.graphiceq.invalidline.message", @"It starts with \"GraphicEQ:\", then pairs of a frequency and a gain: GraphicEQ: 20 -1.2; 21 -1.1; …"));
        return;
    }
    [_text resignFirstResponder];
    // Text of one's own is no longer the headphone's correction the Headphones row names.
    if (![line isEqualToString:SGDSPString(SGKeyDSPGraphicEqNodes)]) SGDSPSetString(SGKeyDSPGraphicEqHeadphone, @"");
    SGDSPSetString(SGKeyDSPGraphicEqNodes, line);
    _text.text = line;
    [self.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:SGGraphicEqSave inSection:2]] withRowAnimation:UITableViewRowAnimationNone];
}

- (void)textViewDidChange:(UITextView *)textView {
    [self.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:SGGraphicEqSave inSection:2]] withRowAnimation:UITableViewRowAnimationNone];
}

@end

UIViewController *SGDSPGraphicEqPage(void) {
    return [SGDSPGraphicEqEditor new];
}
