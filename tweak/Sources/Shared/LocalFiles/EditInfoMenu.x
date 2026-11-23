// Edit info, in the player's ⋯ menu while a local file plays, under either look: a row that opens an
// editor for the file's title, artist, album and cover, stored by the mod (LocalFiles.h).
//
// The menu is Spotify's context menu sheet, ContextMenu_InternalImpl.ContextMenuViewController, whose
// rows come from Swift item factories with no way in (Shared/Player/SpeedPitchMenu.x says more). So the
// row is the table's footer, as Speed and pitch is its header, and the sheet is the player's by
// Speed and pitch's own test. Speed and pitch takes the footer when Spotify has a header of its own in
// the table, so then the footer is left to it and Edit info is left out.
//
// The menu says nothing of the track it is for, so the row is only offered on the player's own menu,
// which is for the track playing.
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <objc/runtime.h>
#import "Core/SGCore.h"
#import "Settings/SGPageStyle.h"
#import "Shared/Player/PlayerState.h"
#import "Shared/Player/SpeedPitch.h"
#import "LocalFiles.h"
#import "LocalInfoLookup.h"
#import "LocalInfoReview.h"

// The sheet's own measures, as Speed and pitch has them.
static const CGFloat kRowHeight = 56, kSideMargin = 16, kIconSide = 24;

static char kRowKey, kDecidedKey;

#pragma mark - the editor

// A form sheet over the player: the three names, the cover with a menu to change it, and a row that puts
// the file's own info back. Nothing is stored until Save, so Cancel undoes everything, a cover picked
// or removed and a restore too; a swipe down with changes asks first.

typedef NS_ENUM(NSInteger, SGCoverChange) { SGCoverKept, SGCoverPicked, SGCoverRemoved };

static NSArray<NSString *> *fieldKeys(void) {
    return @[@"title", @"artist", @"album"];
}

static NSArray<NSString *> *fieldLabels(void) {
    return @[SGL(@"settings.edit_info.field.title", @"Title"),
             SGL(@"settings.edit_info.field.artist", @"Artist"),
             SGL(@"settings.edit_info.field.album", @"Album")];
}

static NSString *trimmed(NSString *text) {
    return [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
}

@interface SGLocalFileEditor : UITableViewController <UITextFieldDelegate, UIAdaptivePresentationControllerDelegate,
                                                      UIImagePickerControllerDelegate, UINavigationControllerDelegate, UIDocumentPickerDelegate>
- (instancetype)initWithURI:(NSString *)uri;
@end

@implementation SGLocalFileEditor {
    NSString *_uri;
    NSDictionary<NSString *, id> *_tags, *_shown;   // the file's own names, and the ones it goes by now
    NSArray<UITextField *> *_fields;
    NSArray<UILabel *> *_labels;
    NSArray<UIStackView *> *_stacks;
    NSArray<NSLayoutConstraint *> *_labelWidths;
    UITableViewCell *_coverCell, *_restoreCell;
    UIButton *_coverButton;
    UIImage *_cover;            // the cover the row shows: the stored one, or the one just picked
    SGCoverChange _coverChange;
    BOOL _hasStoredCover;
    BOOL _coverLoading;
    NSUInteger _coverRequest;
    SGLocalInfoLookup *_infoLookup;
    BOOL _findingInfo;
    NSUInteger _infoRequest;
    UIBarButtonItem *_findInfoButton;
}

- (instancetype)initWithURI:(NSString *)uri {
    if (!(self = [super initWithStyle:UITableViewStyleInsetGrouped])) return nil;
    _uri = [uri copy];
    _tags = SGLocalFileTags(uri) ?: @{};
    _shown = SGLocalFileInfo(uri) ?: @{};
    NSString *path = SGLocalFileCoverPath(SGLocalFileEditFor(uri));
    _hasStoredCover = path != nil;

    NSMutableArray *fields = [NSMutableArray array], *labels = [NSMutableArray array], *stacks = [NSMutableArray array], *widths = [NSMutableArray array];
    for (NSUInteger i = 0; i < fieldKeys().count; i++) {
        NSString *key = fieldKeys()[i];
        UILabel *label = [UILabel new];
        label.text = fieldLabels()[i];
        label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
        label.adjustsFontForContentSizeCategory = YES;
        label.isAccessibilityElement = NO;   // the field reads its own label
        UITextField *field = [UITextField new];
        field.text = _shown[key];
        field.placeholder = _tags[key] ?: fieldLabels()[i];
        field.accessibilityLabel = fieldLabels()[i];
        field.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
        field.adjustsFontForContentSizeCategory = YES;
        field.clearButtonMode = UITextFieldViewModeWhileEditing;
        field.autocapitalizationType = UITextAutocapitalizationTypeWords;
        field.returnKeyType = i + 1 < fieldKeys().count ? UIReturnKeyNext : UIReturnKeyDone;
        field.delegate = self;
        [field addTarget:self action:@selector(changed) forControlEvents:UIControlEventEditingChanged];
        [field setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
        UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[label, field]];
        stack.spacing = 12;
        stack.translatesAutoresizingMaskIntoConstraints = NO;
        [fields addObject:field];
        [labels addObject:label];
        [stacks addObject:stack];
        [widths addObject:[label.widthAnchor constraintEqualToConstant:0]];
    }
    _fields = fields;
    _labels = labels;
    _stacks = stacks;
    _labelWidths = widths;

    self.title = SGL(@"settings.edit_info.title", @"Edit info");
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(cancel)];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemSave target:self action:@selector(save)];
    id suggest = [NSUserDefaults.standardUserDefaults objectForKey:SGKeyLocalFileSuggest];
    if (!suggest || [suggest boolValue]) {
        _infoLookup = [SGLocalInfoLookup new];
        _findInfoButton = [[UIBarButtonItem alloc] initWithTitle:SGL(@"settings.edit_info.suggest.title", @"Find Info")
            style:UIBarButtonItemStylePlain target:self action:@selector(findInfo)];
        self.toolbarItems = @[[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil],
                             _findInfoButton,
                             [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil]];
    }
    return self;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.navigationController setToolbarHidden:!_findInfoButton animated:NO];
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    // Presenting the review/picker is not leaving the editor.
    if (self.isBeingDismissed || self.navigationController.isBeingDismissed || self.isMovingFromParentViewController) {
        ++_infoRequest;
        [_infoLookup cancel];
        _findingInfo = NO;
    }
}

- (void)viewDidLoad {
    [super viewDidLoad];
    _coverCell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    _coverCell.selectionStyle = UITableViewCellSelectionStyleNone;
    UIButtonConfiguration *change = [UIButtonConfiguration plainButtonConfiguration];
    change.title = SGL(@"settings.edit_info.cover.change", @"Change");
    _coverButton = [UIButton buttonWithConfiguration:change primaryAction:nil];
    _coverButton.showsMenuAsPrimaryAction = YES;
    _coverButton.accessibilityLabel = SGL(@"settings.edit_info.cover.change_a11y", @"Change cover");
    _coverCell.accessoryView = _coverButton;
    _restoreCell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    [self fitLabels];
    [self showCover];
    [self changed];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(fitLabels) name:UIContentSizeCategoryDidChangeNotification object:nil];
    if (_hasStoredCover) {
        NSUInteger request = ++_coverRequest;
        _coverLoading = YES;
        [self changed];
        __weak SGLocalFileEditor *weakSelf = self;
        SGLocalFileLoadCover(_uri, ^(UIImage *image) {
            SGLocalFileEditor *editor = weakSelf;
            if (!editor || request != editor->_coverRequest) return;
            editor->_coverLoading = NO;
            editor->_cover = image;
            [editor showCover];
            [editor changed];
        });
    }
}

- (void)dealloc {
    [_infoLookup cancel];
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

// The names' labels share one width so the fields line up; at the accessibility sizes each label goes
// above its field instead.
- (void)fitLabels {
    BOOL stacked = UIContentSizeCategoryIsAccessibilityCategory(self.traitCollection.preferredContentSizeCategory);
    UIFont *font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody compatibleWithTraitCollection:self.traitCollection];
    CGFloat widest = 0;
    for (NSString *text in fieldLabels()) widest = MAX(widest, ceil([text sizeWithAttributes:@{NSFontAttributeName: font}].width));
    for (NSUInteger i = 0; i < _stacks.count; i++) {
        _stacks[i].axis = stacked ? UILayoutConstraintAxisVertical : UILayoutConstraintAxisHorizontal;
        _stacks[i].alignment = stacked ? UIStackViewAlignmentFill : UIStackViewAlignmentFirstBaseline;
        _labelWidths[i].constant = widest;
        _labelWidths[i].active = !stacked;
    }
}

#pragma mark - state

- (NSDictionary<NSString *, NSString *> *)names {
    NSMutableDictionary<NSString *, NSString *> *names = [NSMutableDictionary dictionary];
    for (NSUInteger i = 0; i < _fields.count; i++) names[fieldKeys()[i]] = _fields[i].text ?: @"";
    return names;
}

// A name the way it would be stored: an empty field is the file's own.
- (NSString *)effectiveName:(NSUInteger)i {
    NSString *typed = trimmed(_fields[i].text);
    return typed.length ? typed : _tags[fieldKeys()[i]] ?: @"";
}

- (BOOL)isDirty {
    if (_coverChange != SGCoverKept) return YES;
    for (NSUInteger i = 0; i < _fields.count; i++) {
        if (![[self effectiveName:i] isEqualToString:_shown[fieldKeys()[i]] ?: @""]) return YES;
    }
    return NO;
}

- (BOOL)differsFromFile {
    if (_cover) return YES;
    for (NSUInteger i = 0; i < _fields.count; i++) {
        if (![[self effectiveName:i] isEqualToString:_tags[fieldKeys()[i]] ?: @""]) return YES;
    }
    return NO;
}

- (void)changed {
    BOOL dirty = self.isDirty;
    self.navigationItem.rightBarButtonItem.enabled = dirty && !_coverLoading;
    _coverButton.enabled = !_coverLoading;
    // A swipe down then asks before the changes go (presentationControllerDidAttemptToDismiss:).
    self.modalInPresentation = dirty || _coverLoading;
    BOOL restorable = self.differsFromFile;
    UIListContentConfiguration *content = [UIListContentConfiguration cellConfiguration];
    content.text = SGL(@"settings.edit_info.restore.title", @"Restore file's info");
    content.textProperties.color = restorable ? UIColor.systemRedColor : UIColor.tertiaryLabelColor;
    _restoreCell.contentConfiguration = content;
    _restoreCell.userInteractionEnabled = restorable;
    _restoreCell.accessibilityTraits = UIAccessibilityTraitButton | (restorable ? 0 : UIAccessibilityTraitNotEnabled);
}

- (void)showCover {
    UIListContentConfiguration *content = [UIListContentConfiguration subtitleCellConfiguration];
    content.text = SGL(@"settings.album.cover.header", @"Cover");
    content.secondaryText = !_cover ? SGL(@"settings.edit_info.cover.file_own", @"The file's own") : _coverChange == SGCoverPicked ? SGL(@"settings.edit_info.cover.new_picture", @"New picture") : SGL(@"settings.edit_info.cover.your_picture", @"Your picture");
    content.secondaryTextProperties.color = UIColor.secondaryLabelColor;
    content.image = _cover ?: [UIImage systemImageNamed:@"music.note"];
    content.imageProperties.preferredSymbolConfiguration = [UIImageSymbolConfiguration configurationWithTextStyle:UIFontTextStyleTitle2];
    content.imageProperties.tintColor = UIColor.secondaryLabelColor;
    content.imageProperties.maximumSize = CGSizeMake(56, 56);
    content.imageProperties.reservedLayoutSize = CGSizeMake(56, 56);
    content.imageProperties.cornerRadius = 8;
    content.imageProperties.accessibilityIgnoresInvertColors = YES;
    _coverCell.contentConfiguration = content;

    __weak typeof(self) weakSelf = self;
    NSMutableArray<UIMenuElement *> *items = [NSMutableArray arrayWithArray:@[
        [UIAction actionWithTitle:SGL(@"settings.edit_info.cover.choose_photos", @"Choose from Photos") image:[UIImage systemImageNamed:@"photo.on.rectangle"] identifier:nil handler:^(UIAction *action) {
            [weakSelf pickCoverFromFiles:NO];
        }],
        [UIAction actionWithTitle:SGL(@"settings.edit_info.cover.choose_files", @"Choose from Files") image:[UIImage systemImageNamed:@"folder"] identifier:nil handler:^(UIAction *action) {
            [weakSelf pickCoverFromFiles:YES];
        }],
    ]];
    if (_cover) {
        UIAction *remove = [UIAction actionWithTitle:SGL(@"settings.edit_info.cover.remove", @"Remove cover") image:[UIImage systemImageNamed:@"trash"] identifier:nil handler:^(UIAction *action) {
            [weakSelf useCover:nil];
        }];
        remove.attributes = UIMenuElementAttributesDestructive;
        [items addObject:remove];
    }
    _coverButton.menu = [UIMenu menuWithChildren:items];
    [_coverButton sizeToFit];
}

// nil removes the cover: the stored one goes on Save, a picked one goes at once.
- (void)useCover:(UIImage *)image {
    _coverRequest++;
    _coverLoading = NO;
    _cover = image;
    _coverChange = image ? SGCoverPicked : _hasStoredCover ? SGCoverRemoved : SGCoverKept;
    [self showCover];
    [self changed];
}

#pragma mark - the actions

- (void)acceptInfo:(NSDictionary<NSString *, NSString *> *)names cover:(UIImage *)cover {
    for (NSUInteger i = 0; i < _fields.count; i++)
        if (names[fieldKeys()[i]]) _fields[i].text = names[fieldKeys()[i]];
    if (cover) [self useCover:cover];
    else [self changed];
}

- (void)findInfo {
    if (_findingInfo || !_infoLookup || _coverLoading) return;
    [self.view endEditing:YES];
    NSString *title = _fields[0].text ?: @"", *artist = _fields[1].text ?: @"";
    NSString *query = SGLocalInfoQuery(title, artist, _tags[@"title"]);
    NSTimeInterval seconds = [_tags[@"seconds"] doubleValue];
    NSUInteger request = ++_infoRequest;
    _findingInfo = YES;
    _findInfoButton.enabled = NO;
    __weak typeof(self) weakSelf = self;
    [_infoLookup search:SGLocalInfoSearchURL(query, NSLocale.currentLocale.countryCode)
        completion:^(NSArray<NSDictionary *> *parsed, NSError *error) {
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            NSArray *songs = parsed ? SGLocalInfoRank(parsed, title.length ? title : query, artist, seconds) : nil;
            dispatch_async(dispatch_get_main_queue(), ^{
                SGLocalFileEditor *editor = weakSelf;
                if (!editor || request != editor->_infoRequest) return;
                editor->_findingInfo = NO;
                editor->_findInfoButton.enabled = YES;
                if (!editor.view.window || editor.presentedViewController ||
                    editor.navigationController.topViewController != editor ||
                    editor.isBeingDismissed || editor.navigationController.isBeingDismissed) return;
                if (songs.count) {
                    SGLocalInfoReview *review = [[SGLocalInfoReview alloc] initWithSongs:songs current:editor.names
                        cover:editor->_cover durationUnknown:seconds == 0 accept:^(NSDictionary *names, UIImage *cover) {
                            [weakSelf acceptInfo:names cover:cover];
                        }];
                    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:review];
                    SGPresentDark(nav);
                    [editor presentViewController:nav animated:YES completion:nil];
                    return;
                }
                NSString *message = parsed ?
                    SGL(@"settings.edit_info.suggest.empty", @"Apple Music has no song with this name within three seconds of this file's length.") :
                    [error.userInfo[NSURLErrorNetworkUnavailableReasonKey] integerValue] == NSURLErrorNetworkUnavailableReasonConstrained ?
                    SGL(@"settings.edit_info.suggest.low_data", @"Find Info is unavailable in Low Data Mode.") :
                    SGL(@"settings.edit_info.suggest.error", @"iTunes did not answer. Try again.");
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:nil message:message preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:SGL(@"common.ok", @"OK") style:UIAlertActionStyleDefault handler:nil]];
                SGPresentDark(alert);
                [editor presentViewController:alert animated:YES completion:nil];
            });
        });
    }];
}

- (void)restore {
    for (NSUInteger i = 0; i < _fields.count; i++) _fields[i].text = _tags[fieldKeys()[i]];
    [self.view endEditing:YES];
    [self useCover:nil];
}

- (void)save {
    if (_coverLoading) return;
    ++_infoRequest;
    [_infoLookup cancel];
    _coverRequest++;
    [self.view endEditing:YES];
    SGLocalFileSaveEdit(_uri, self.names, _coverChange == SGCoverPicked ? _cover : nil, _coverChange != SGCoverRemoved);
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)cancel {
    if (self.isDirty) [self confirmDiscard];
    else {
        ++_infoRequest;
        [_infoLookup cancel];
        _coverRequest++;
        [self dismissViewControllerAnimated:YES completion:nil];
    }
}

- (void)confirmDiscard {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:nil message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:SGL(@"settings.edit_info.discard_changes", @"Discard changes") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        ++self->_infoRequest;
        [self->_infoLookup cancel];
        self->_coverRequest++;
        [self dismissViewControllerAnimated:YES completion:nil];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:SGL(@"settings.edit_info.keep_editing", @"Keep editing") style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.barButtonItem = self.navigationItem.leftBarButtonItem;
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)presentationControllerDidAttemptToDismiss:(UIPresentationController *)presentationController {
    [self confirmDiscard];
}

- (void)pickCoverFromFiles:(BOOL)files {
    ++_infoRequest;
    [_infoLookup cancel];
    _findingInfo = NO;
    _findInfoButton.enabled = YES;
    [self.view endEditing:YES];
    UIViewController *picker;
    if (files) {
        // A copy, so it is the app's own to read.
        UIDocumentPickerViewController *documents = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeImage] asCopy:YES];
        documents.delegate = self;
        picker = documents;
    } else {
        // Runs out of the app's process, so no Photos permission is asked.
        UIImagePickerController *photos = [UIImagePickerController new];
        photos.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
        photos.delegate = self;
        picker = photos;
    }
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary<UIImagePickerControllerInfoKey, id> *)info {
    NSURL *url = info[UIImagePickerControllerImageURL];
    [self loadCoverFromURL:url image:url ? nil : info[UIImagePickerControllerOriginalImage]];
    [picker dismissViewControllerAnimated:YES completion:nil];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    [picker dismissViewControllerAnimated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    [self loadCoverFromURL:urls.firstObject image:nil];
}

- (void)loadCoverFromURL:(NSURL *)url image:(UIImage *)original {
    NSUInteger request = ++_coverRequest;
    _coverLoading = YES;
    [self changed];
    __weak SGLocalFileEditor *weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        UIImage *image = url ? SGLocalFileReadCover(url) : SGLocalFileThumbnail(original);
        dispatch_async(dispatch_get_main_queue(), ^{
            SGLocalFileEditor *editor = weakSelf;
            if (!editor || request != editor->_coverRequest) return;
            editor->_coverLoading = NO;
            if (image) {
                [editor useCover:image];
                return;
            }
            [editor changed];
            SGLog(@"local files: %@ is not an image", url.lastPathComponent);
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:SGL(@"settings.edit_info.not_an_image.title", @"Not an image") message:SGL(@"settings.edit_info.not_an_image.message", @"Pick a JPEG, PNG or HEIC file.")
                                                                    preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:SGL(@"common.ok", @"OK") style:UIAlertActionStyleDefault handler:nil]];
            [editor presentViewController:alert animated:YES completion:nil];
        });
    });
}

- (BOOL)textFieldShouldReturn:(UITextField *)field {
    NSUInteger i = [_fields indexOfObject:field];
    if (i != NSNotFound && i + 1 < _fields.count) [_fields[i + 1] becomeFirstResponder];
    else [field resignFirstResponder];
    return NO;
}

#pragma mark - the table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 3;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return section == 0 ? (NSInteger)_fields.count : 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 2 && _findInfoButton) return SGL(@"settings.edit_info.suggest.privacy", @"The song's name is sent to Apple's iTunes Search.");
    return section == 0 ? SGL(@"settings.edit_info.footer", @"Kept by Retrine for this file. The file itself is not changed.") : nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 1) return _coverCell;
    if (indexPath.section == 2) return _restoreCell;
    // One cell per name, made once: the field keeps what was typed while the table scrolls.
    UIStackView *stack = _stacks[(NSUInteger)indexPath.row];
    if (stack.superview) return (UITableViewCell *)stack.superview.superview;
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    [cell.contentView addSubview:stack];
    UILayoutGuide *margins = cell.contentView.layoutMarginsGuide;
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:margins.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:margins.trailingAnchor],
        [stack.topAnchor constraintEqualToAnchor:margins.topAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:margins.bottomAnchor],
    ]];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 0) [_fields[(NSUInteger)indexPath.row] becomeFirstResponder];
    if (indexPath.section == 2) [self restore];
}

@end

static UIViewController *topOf(UIViewController *presenter) {
    UIViewController *top = presenter;
    while (top.presentedViewController && !top.presentedViewController.isBeingDismissed) top = top.presentedViewController;
    return top;
}

void SGLocalFilePresentEditor(UIViewController *presenter, NSString *uri) {
    if (!presenter || !SGLocalFileIs(uri)) return;
    SGLocalFileEditor *editor = [[SGLocalFileEditor alloc] initWithURI:uri];
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:editor];
    navigation.modalPresentationStyle = UIModalPresentationFormSheet;
    // Outside Spotify's navigation stacks a sheet takes the system's appearance, light in light mode.
    SGPresentDark(navigation);
    navigation.presentationController.delegate = editor;
    UISheetPresentationController *sheet = navigation.sheetPresentationController;
    sheet.detents = @[UISheetPresentationControllerDetent.mediumDetent, UISheetPresentationControllerDetent.largeDetent];
    sheet.prefersGrabberVisible = YES;
    [topOf(presenter) presentViewController:navigation animated:YES completion:nil];
}

#pragma mark - the row

@interface SGEditInfoRow : UIControl
@property (nonatomic, copy) NSString *uri;
@property (nonatomic, weak) UIViewController *menu;
@end

@implementation SGEditInfoRow {
    UIImageView *_icon;
    UILabel *_title;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    UIColor *secondary = [UIColor colorWithWhite:1 alpha:UIAccessibilityDarkerSystemColorsEnabled() ? 0.80 : 0.65];
    UIImage *glyph = [UIImage systemImageNamed:@"pencil" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:20 weight:UIImageSymbolWeightRegular]];
    // Colors drawn in, so nothing passes through the sheet's tint.
    _icon = [[UIImageView alloc] initWithImage:[glyph imageWithTintColor:secondary renderingMode:UIImageRenderingModeAlwaysOriginal]];
    _icon.contentMode = UIViewContentModeCenter;
    _title = [UILabel new];
    _title.font = SGCategoryCappedFont(UIFontTextStyleBody, UIFontWeightRegular, UIContentSizeCategoryExtraLarge);
    _title.textColor = UIColor.whiteColor;
    _title.text = SGL(@"settings.edit_info.title", @"Edit info");
    for (UIView *view in @[_icon, _title]) {
        view.userInteractionEnabled = NO;
        [self addSubview:view];
    }
    self.isAccessibilityElement = YES;
    self.accessibilityTraits = UIAccessibilityTraitButton;
    self.accessibilityLabel = SGL(@"settings.edit_info.title", @"Edit info");
    [self addTarget:self action:@selector(open) forControlEvents:UIControlEventTouchUpInside];
    [self addTarget:self action:@selector(highlight) forControlEvents:UIControlEventTouchDown | UIControlEventTouchDragEnter];
    [self addTarget:self action:@selector(unhighlight) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel | UIControlEventTouchDragExit];
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.bounds.size.width;
    _icon.frame = CGRectMake(kSideMargin, (kRowHeight - kIconSide) / 2, kIconSide, kIconSide);
    CGFloat titleX = kSideMargin + kIconSide + kSideMargin;
    _title.frame = CGRectMake(titleX, 0, MAX(0, width - titleX - kSideMargin), kRowHeight);
}

- (void)highlight {
    self.backgroundColor = [UIColor colorWithWhite:1 alpha:0.08];
}

- (void)unhighlight {
    [UIView animateWithDuration:0.2 animations:^{ self.backgroundColor = UIColor.clearColor; }];
}

// One sheet at a time: Spotify's menu goes before the editor comes up over what presented it.
- (void)open {
    UIViewController *menu = self.menu, *host = menu.presentingViewController;
    NSString *uri = self.uri;
    if (!host) {
        SGLocalFilePresentEditor(menu, uri);
        return;
    }
    [menu dismissViewControllerAnimated:YES completion:^{ SGLocalFilePresentEditor(host, uri); }];
}

@end

#pragma mark - the menu

static BOOL freeSlot(UIView *view) {
    return !view || view.bounds.size.height < 1;
}

static void decide(UIViewController *menu, BOOL offered) {
    objc_setAssociatedObject(menu, &kDecidedKey, @(offered), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void install(UIViewController *menu) {
    UIView *root = menu.viewIfLoaded;
    if (!root || [objc_getAssociatedObject(menu, &kDecidedKey) isEqual:@NO]) return;
    UITableView *table = SGTableIn(root, 5);
    CGFloat width = table.bounds.size.width;
    if (width <= 0) return;
    SGEditInfoRow *row = objc_getAssociatedObject(menu, &kRowKey);
    if (!row) {
        NSString *uri = SGURIString(SGPlayerState().track.URI);
        if (!SGLocalFileIs(uri) || !SGPlayerMenuIsPlayers(menu)) {
            decide(menu, NO);
            return;
        }
        // A header of Spotify's own sends Speed and pitch to the footer.
        UIView *header = table.tableHeaderView;
        BOOL headerOurs = freeSlot(header) || [NSStringFromClass(header.class) hasPrefix:@"SG"];
        if (!headerOurs || !freeSlot(table.tableFooterView)) {
            SGLog(@"local files: the menu's table has %@ and %@, Edit info left out",
                  header ? NSStringFromClass(header.class) : @"no header", table.tableFooterView ? NSStringFromClass(table.tableFooterView.class) : @"no footer");
            decide(menu, NO);
            return;
        }
        decide(menu, YES);
        row = [[SGEditInfoRow alloc] initWithFrame:CGRectMake(0, 0, width, kRowHeight)];
        row.uri = uri;
        row.menu = menu;
        objc_setAssociatedObject(menu, &kRowKey, row, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        table.tableFooterView = row;
        [table invalidateIntrinsicContentSize];
        SGLog(@"local files: Edit info offered for %@", uri);
        return;
    }
    // Spotify replaced the footer, or the table changed width: put it back at the table's width.
    if (table.tableFooterView != row || fabs(row.frame.size.width - width) > 0.5) {
        row.frame = CGRectMake(0, row.frame.origin.y, width, kRowHeight);
        table.tableFooterView = row;
        [table invalidateIntrinsicContentSize];
    }
}

%hook _TtC24ContextMenu_InternalImpl25ContextMenuViewController
- (void)viewDidLayoutSubviews {
    %orig;
    install((UIViewController *)self);
}
%end

%ctor {
    %init;
    SGRequireClasses(@[@"_TtC24ContextMenu_InternalImpl25ContextMenuViewController"]);
}
