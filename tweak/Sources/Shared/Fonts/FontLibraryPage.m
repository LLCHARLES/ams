// The free fonts page (FontLibrary.h): the catalog's families, Korean ones first. A family not on this iPhone
// downloads on a tap and becomes the app's font; one that is here is picked on a tap, as on the Font page. The row
// says how far a download has come, and a tap on it then offers to stop it. A swipe deletes a family or opens its
// license.
#import "Core/SGCore.h"
#import "Settings/SGPage.h"
#import "Settings/SGPageStyle.h"
#import "Shared/Fonts/FontLibrary.h"
#import "Shared/Fonts/Fonts.h"

static NSString *sizeText(long long bytes) {
    return [NSByteCountFormatter stringFromByteCount:bytes countStyle:NSByteCountFormatterCountStyleFile];
}

static NSString *stylesText(NSUInteger styles) {
    return [NSString stringWithFormat:styles == 1 ? SGL(@"settings.font.library.styles.singular", @"%lu style")
                                                  : SGL(@"settings.font.library.styles.plural", @"%lu styles"), (unsigned long)styles];
}

static BOOL chosen(SGLibraryFont *font) {
    return SGAppFontChosen() == SGAppFontLibrary
        && [[NSUserDefaults.standardUserDefaults stringForKey:SGKeyAppFontLibrary] isEqualToString:font.identifier];
}

static void choose(SGLibraryFont *font) {
    [NSUserDefaults.standardUserDefaults setObject:font.identifier forKey:SGKeyAppFontLibrary];
    SGSetInt(SGKeyAppFont, SGAppFontLibrary);
}

@interface SGFontLibraryList : SGPage
@end

@implementation SGFontLibraryList {
    NSArray<NSArray<SGLibraryFont *> *> *_sections;   // Korean, then the others
    UIView *_header;
    id _observer;
}

- (instancetype)init {
    if (!(self = [super initWithStyle:UITableViewStyleInsetGrouped])) return nil;
    self.title = SGL(@"settings.font.library.title", @"Free fonts");
    NSArray<SGLibraryFont *> *all = SGFontLibrary();
    _sections = @[[all filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"korean == YES"]],
                  [all filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"korean == NO"]]];
    return self;
}

- (void)dealloc {
    if (_observer) [NSNotificationCenter.defaultCenter removeObserver:_observer];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    _header = SGNote(SGL(@"settings.font.library.intro", @"Families under the SIL Open Font License, free to use, from Google Fonts. "
                         "Each file is checked before it is kept, and stays on this iPhone. A family you download becomes the app's font "
                         "when Spotify starts again. Swipe left on one to delete it or read its license."));
    self.tableView.tableHeaderView = _header;
    __weak SGFontLibraryList *page = self;
    // Posted on the main thread only (FontLibrary.m).
    _observer = [NSNotificationCenter.defaultCenter addObserverForName:SGFontLibraryChangedNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
        [page refreshFamily:note.userInfo[@"identifier"]];
    }];
    // So a family already here can be drawn in itself, whichever font the app uses: registered off main,
    // and each row is refreshed by the notification above once its family is known.
    SGFontLibraryRegisterInstalled();
}

- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    SGFitNote(self.tableView, _header, 8, 8);
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    SGInsetForBars(self.tableView);
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.tableView reloadData];
}

- (NSIndexPath *)pathOf:(NSString *)identifier {
    for (NSUInteger section = 0; section < _sections.count; section++) {
        NSUInteger row = [_sections[section] indexOfObjectPassingTest:^BOOL(SGLibraryFont *font, NSUInteger i, BOOL *stop) {
            return [font.identifier isEqualToString:identifier];
        }];
        if (row != NSNotFound) return [NSIndexPath indexPathForRow:(NSInteger)row inSection:(NSInteger)section];
    }
    return nil;
}

// Only the row that changed, so a download's progress does not redraw the whole list ten times a second.
- (void)refreshFamily:(NSString *)identifier {
    if (!self.isViewLoaded) return;
    NSIndexPath *path = identifier ? [self pathOf:identifier] : nil;
    UITableViewCell *cell = path ? [self.tableView cellForRowAtIndexPath:path] : nil;
    if (cell) [self fill:cell font:_sections[(NSUInteger)path.section][(NSUInteger)path.row]];
    else [self.tableView reloadData];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)table {
    return (NSInteger)_sections.count;
}

- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)_sections[(NSUInteger)section].count;
}

- (UIView *)tableView:(UITableView *)table viewForHeaderInSection:(NSInteger)section {
    return SGSectionHeader(table, section == 0 ? SGL(@"settings.font.library.korean.header", @"Korean") : SGL(@"settings.font.library.latin.header", @"Latin"));
}

- (CGFloat)tableView:(UITableView *)table heightForHeaderInSection:(NSInteger)section {
    return SGSectionHeaderHeight();
}

- (UIView *)tableView:(UITableView *)table viewForFooterInSection:(NSInteger)section {
    return nil;
}

- (CGFloat)tableView:(UITableView *)table heightForFooterInSection:(NSInteger)section {
    return CGFLOAT_MIN;
}

- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell = SGDequeueCell(table, @"library-font");
    [self fill:cell font:_sections[(NSUInteger)path.section][(NSUInteger)path.row]];
    return cell;
}

- (void)fill:(UITableViewCell *)cell font:(SGLibraryFont *)font {
    BOOL downloading = [SGFontLibraryDownloading() isEqualToString:font.identifier];
    BOOL here = SGFontLibraryInstalled(font.identifier);
    BOOL inUse = here && chosen(font);
    NSString *details = [NSString stringWithFormat:@"%@ · %@", stylesText(font.styles), sizeText(font.bytes)];
    NSString *subtitle = details;
    if (downloading) {
        subtitle = [NSString stringWithFormat:SGL(@"settings.font.library.downloading.format", @"Downloading… %.0f%%"), SGFontLibraryProgress() * 100];
    } else if (inUse) {
        subtitle = [NSString stringWithFormat:SGL(@"settings.font.library.in_use.format", @"In use · %@"), details];
    } else if (here) {
        subtitle = [NSString stringWithFormat:SGL(@"settings.font.library.downloaded.format", @"Downloaded · %@"), details];
    }
    SGFillCell(cell, font.name, subtitle, nil, nil);
    // A family that is here is drawn in its regular face once FontLibrary.m has registered it and published
    // its name; until then the row keeps the list's font.
    NSString *family = here ? SGFontLibraryRegisteredFamily(font.identifier) : nil;
    UIFont *face = family ? [UIFont fontWithDescriptor:[UIFontDescriptor fontDescriptorWithFontAttributes:@{
        UIFontDescriptorFamilyAttribute: family,
        UIFontDescriptorTraitsAttribute: @{UIFontWeightTrait: @(UIFontWeightRegular), UIFontSlantTrait: @0},
    }] size:SGTitleFont().pointSize] : nil;
    if (face) {
        UIListContentConfiguration *content = (UIListContentConfiguration *)cell.contentConfiguration;
        content.textProperties.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleBody] scaledFontForFont:face maximumPointSize:20];
        cell.contentConfiguration = content;
    }
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    if (downloading) {
        UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
        spinner.color = SGGrey();
        [spinner startAnimating];
        cell.accessoryView = spinner;
    } else if (inUse) {
        UIImageView *tick = SGSymbolView(@"checkmark", 13, UIImageSymbolWeightSemibold, 16);
        tick.tintColor = SGAccentMark();
        cell.accessoryView = tick;
    } else if (!here) {
        UIImageView *get = SGSymbolView(@"arrow.down.circle", 17, UIImageSymbolWeightRegular, 22);
        get.tintColor = SGAccentMark();
        cell.accessoryView = get;
    }
    cell.accessibilityLabel = font.name;
    cell.accessibilityValue = subtitle;
    cell.accessibilityHint = downloading ? SGL(@"settings.font.library.a11y.stop_hint", @"Stops the download")
                           : here ? nil : SGL(@"settings.font.library.a11y.download_hint", @"Downloads the font and makes it the app's font");
    cell.accessibilityTraits = inUse ? UIAccessibilityTraitButton | UIAccessibilityTraitSelected : UIAccessibilityTraitButton;
}

- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)path {
    [table deselectRowAtIndexPath:path animated:YES];
    SGLibraryFont *font = _sections[(NSUInteger)path.section][(NSUInteger)path.row];
    if ([SGFontLibraryDownloading() isEqualToString:font.identifier]) {
        [self offerToStop:font];
    } else if (SGFontLibraryInstalled(font.identifier)) {
        if (chosen(font)) return;
        choose(font);
        [table reloadData];
        [self offerRestart:font];
    } else {
        [self download:font];
    }
}

- (void)download:(SGLibraryFont *)font {
    NSArray *selection = SGFontSelectionSnapshot();
    __weak SGFontLibraryList *page = self;
    UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, [NSString stringWithFormat:SGL(@"settings.font.library.a11y.downloading", @"Downloading %@"), font.name]);
    SGFontLibraryDownload(font.identifier, ^(NSString *error) {
        if (error.length) {
            [page tell:SGL(@"settings.font.library.failed.alert.title", @"Font not downloaded") message:error];
            return;
        }
        if (error) return;   // stopped
        // Keep the download available even if a newer choice or pending restart prevents selection. The
        // registration runs off main and the page goes on when it lands.
        SGFontLibraryRegisterAsync(font.identifier, ^(NSString *family) {
            SGFontLibraryList *strong = page;
            if (!family) {
                [strong tell:SGL(@"settings.font.library.failed.alert.title", @"Font not downloaded") message:SGL(@"settings.font.library.error.unreadable", @"iOS could not read the downloaded font.")];
                return;
            }
            BOOL select = SGFontSelectionUnchanged(selection);
            if (select) choose(font);
            [strong.tableView reloadData];
            if (select) [strong offerRestart:font];
        });
    });
}

- (void)offerToStop:(SGLibraryFont *)font {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:SGL(@"settings.font.library.stop.alert.title", @"Stop downloading %@?"), font.name]
        message:nil preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:SGL(@"settings.font.library.action.keep", @"Keep downloading") style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:SGL(@"settings.font.library.action.stop", @"Stop") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        SGFontLibraryCancel();
    }]];
    SGPresentDark(alert);
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)offerRestart:(SGLibraryFont *)font {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:SGL(@"settings.font.library.ready.alert.title", @"Font ready")
        message:[NSString stringWithFormat:SGL(@"settings.font.imported.alert.message", @"%@ becomes the app's font when Spotify starts again."), font.name]
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:SGL(@"common.later", @"Later") style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:SGL(@"settings.font.action.restart_now", @"Restart now") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { SGRestartSpotify(); }]];
    SGPresentDark(alert);
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)tell:(NSString *)title message:(NSString *)message {
    if (!self.viewIfLoaded.window) return;
    SGPresentInformation(self, title, message);
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)table trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)path {
    SGLibraryFont *font = _sections[(NSUInteger)path.section][(NSUInteger)path.row];
    NSMutableArray<UIContextualAction *> *actions = [NSMutableArray array];
    if (SGFontLibraryInstalled(font.identifier) && ![SGFontLibraryDownloading() isEqualToString:font.identifier]) {
        UIContextualAction *delete = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:SGL(@"common.delete", @"Delete")
            handler:^(UIContextualAction *action, UIView *view, void (^done)(BOOL)) {
                SGFontLibraryRemove(font.identifier);
                done(YES);
            }];
        delete.image = [UIImage systemImageNamed:@"trash"];
        [actions addObject:delete];
    }
    UIContextualAction *license = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:SGL(@"settings.font.library.action.license", @"License")
        handler:^(UIContextualAction *action, UIView *view, void (^done)(BOOL)) {
            SGOpenURL(font.licenseURL.absoluteString);
            done(YES);
        }];
    license.image = [UIImage systemImageNamed:@"doc.text"];
    license.backgroundColor = UIColor.systemGrayColor;
    [actions addObject:license];
    UISwipeActionsConfiguration *configuration = [UISwipeActionsConfiguration configurationWithActions:actions];
    configuration.performsFirstActionWithFullSwipe = NO;
    return configuration;
}

@end

UIViewController *SGFontLibraryPage(void) {
    return [SGFontLibraryList new];
}
