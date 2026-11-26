// What the Updates row opens: where this build stands against GitHub's releases, and the changelog of
// every release newer than it -- a section per release and heading, a row per line, each opening the
// commit it came from. Everything here is read out of what the last check stored (Update.m), so the
// page draws whatever is known the moment it opens, even while a fresh check is in flight.
// A check that lands rebuilds it where it stands, which is what makes Check now worth having: the
// changelog of a release nobody had heard of a second ago fills the page in without leaving it.
#import "Core/SGCore.h"
#import "Settings/SGPage.h"
#import "Settings/SGPageStyle.h"
#import "Settings/SGModPage.h"
#import "Settings/SGSettingsIndex.h"
#import "About.h"

// "2026-09-18T17:25:02Z" written out, and the empty string for a release GitHub never dated. Every
// word of the mod's is English, so the month is too, whatever the phone is set to.
static NSString *dateInWords(NSString *published, NSString *format) {
    static NSISO8601DateFormatter *reader;
    static NSDateFormatter *writer;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        reader = [NSISO8601DateFormatter new];
        writer = [NSDateFormatter new];
        writer.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    });
    NSDate *date = published.length ? [reader dateFromString:published] : nil;
    if (!date) return @"";
    writer.dateFormat = format;
    return [writer stringFromDate:date];
}

static NSString *shortDate(NSString *published) {   // 18 Sep 2026
    return dateInWords(published, @"d MMM yyyy");
}

static NSString *longDate(NSString *published) {    // 18 September 2026
    return dateInWords(published, @"d MMMM yyyy");
}

#pragma mark - the page

@interface SGUpdatePageController : SGPage <SGSettingsSearchPages>
@end

@implementation SGUpdatePageController {
    NSArray<SGModSection *> *_groups;
    UIView *_intro;
}

- (instancetype)init {
    if (!(self = [super initWithStyle:UITableViewStyleInsetGrouped])) return nil;
    self.title = SGL(@"settings.mod.update.title", @"Updates");
    _groups = [self build];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(checkLanded)
                                               name:SGUpdateCheckedNotification object:nil];
    return self;
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

// The releases whose changelog this page shows: everything newer than the build, newest first.
// With nothing newer, show the build's own notes only if the stored version matches it.
static NSArray<SGUpdateRelease *> *releasesToShow(void) {
    NSArray<SGUpdateRelease *> *releases = SGUpdateReleases();
    NSMutableArray<SGUpdateRelease *> *shown = [NSMutableArray array];
    for (SGUpdateRelease *release in releases) {
        if (!SGUpdateIsNewer(release.version)) {
            if (!shown.count && !SGVersionIsNewer(@(SG_VERSION), release.version)) [shown addObject:release];
            break;
        }
        [shown addObject:release];
    }
    return shown;
}

- (NSString *)introText {
    SGUpdateRelease *newest = releasesToShow().firstObject;
    if (!newest) return SGUpdateChecked()
        ? [NSString stringWithFormat:SGL(@"settings.mod.update.intro.up_to_date", @"This build is %s. The last check found no newer release."), SG_VERSION]
        : [NSString stringWithFormat:SGL(@"settings.mod.update.intro.not_checked", @"This build is %s. Nothing has been asked of GitHub yet."), SG_VERSION];
    NSString *date = longDate(newest.date);
    NSString *when = date.length ? [SGL(@"settings.mod.update.came_out_on", @" came out on ") stringByAppendingString:date] : SGL(@"settings.mod.update.status.is_out", @" is out");
    if (SGUpdateIsNewer(newest.version))
        return [NSString stringWithFormat:SGL(@"settings.mod.update.intro.newer_available", @"%@%@, and this build is %s. Everything in between is below."),
                newest.version, when, SG_VERSION];
    return [NSString stringWithFormat:SGL(@"settings.mod.update.intro.is_newest", @"This build, %s, is GitHub's newest release; it%@. What went into it is below."),
            SG_VERSION, when];
}

// The three rows at the top, then a section per release and heading: "0.19.0 · Features".
- (NSArray<SGModSection *> *)build {
    NSMutableArray<SGModSection *> *groups = [NSMutableArray array];
    SGModRow *check = [SGModRow new];
    check.title = SGL(@"settings.mod.update.check_now.title", @"Check now");
    check.symbol = @"arrow.clockwise";
    check.value = ^NSString *{ return SGUpdateStatus(); };
    check.action = ^{ SGCheckForUpdate(YES); };
    NSMutableArray<SGModRow *> *top = [NSMutableArray arrayWithObject:check];
    SGUpdateRelease *newest = SGUpdateNewestRelease();
    if (SGUpdateVersion() && newest.url.length)
        [top addObject:SGWithSymbol(SGLinkRow([SGL(@"settings.mod.update.get_version.title_prefix", @"Get ") stringByAppendingString:newest.version],
                                              newest.prerelease ? SGL(@"settings.mod.update.beta.subtitle", @"A beta, on GitHub with its .deb") : SGL(@"settings.mod.update.release.subtitle", @"The release on GitHub, where its .deb is"),
                                              newest.url), @"arrow.down.circle")];
    if (SGRepoURL) [top addObject:SGWithSymbol(SGLinkRow(SGL(@"settings.mod.update.all_releases.title", @"All releases"), SGL(@"settings.mod.update.all_releases.subtitle", @"Every version, this one and the ones before it"),
                                                         [SGRepoURL stringByAppendingString:@"/releases"]), @"clock.arrow.circlepath")];
    [groups addObject:SGSection(nil, top)];

    [groups addObject:SGSection(nil, self.sg_searchPageRows)];

    for (SGUpdateRelease *release in releasesToShow()) {
        NSMutableArray<NSString *> *kinds = [NSMutableArray array];
        NSMutableDictionary<NSString *, NSMutableArray<SGModRow *> *> *byKind = [NSMutableDictionary dictionary];
        for (SGUpdateChange *change in release.changes) {
            NSMutableArray<SGModRow *> *rows = byKind[change.kind];
            if (!rows) {
                rows = [NSMutableArray array];
                byKind[change.kind] = rows;
                [kinds addObject:change.kind];
            }
            SGModRow *row = [SGModRow new];
            row.title = change.text;
            if (change.url.length) row.action = ^{ SGOpenURL(change.url); };
            [rows addObject:row];
        }
        NSString *date = shortDate(release.date);
        if (!kinds.count) {
            SGModRow *empty = [SGModRow new];
            empty.title = SGL(@"settings.mod.update.empty.title", @"Nothing written down");
            empty.subtitle = release.url.length ? SGL(@"settings.mod.update.empty.subtitle", @"Tap to read the release on GitHub") : nil;
            if (release.url.length) empty.action = ^{ SGOpenURL(release.url); };
            [groups addObject:SGSection([NSString stringWithFormat:@"%@%@", release.version,
                                         date.length ? [@" · " stringByAppendingString:date] : @""], @[empty])];
            continue;
        }
        [kinds enumerateObjectsUsingBlock:^(NSString *kind, NSUInteger i, BOOL *stop) {
            // The date goes on the first heading of a release, so several releases read as dated blocks.
            NSString *title = [NSString stringWithFormat:@"%@ · %@%@", release.version, kind,
                               i == 0 && date.length ? [@" · " stringByAppendingString:date] : @""];
            [groups addObject:SGSection(title, byKind[kind])];
        }];
    }
    return groups;
}

- (NSArray<SGModRow *> *)sg_searchPageRows {
    SGModRow *notice = SGWithSymbol(SGSwitchRow(SGL(@"settings.mod.update.auto_check.title", @"Auto check updates"), nil, SGKeyUpdateNotice), @"bell");
    SGModRow *betas = SGSwitchRow(SGL(@"settings.mod.include_betas.title", @"Include betas"), SGL(@"settings.mod.include_betas.subtitle", @"Offer test builds ahead of each release"), SGKeyUpdateBetas);
    betas.defaultOn = SGBuildIsBeta();
    betas.changed = ^(BOOL on) { SGCheckForUpdate(YES); };
    return @[notice, betas];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    _intro = SGNote([self introText]);
    self.tableView.tableHeaderView = _intro;
}

- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    SGFitNote(self.tableView, _intro, 24, 0);
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    SGInsetForBars(self.tableView);
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.tableView reloadData];
    // Only the status reads out on the right, and only it moves on its own while the page is open;
    // it is written into the cell so that a reload never lands under a tap.
    self.refreshSelector = @selector(readStatus);
}

- (void)readStatus {
    for (UITableViewCell *cell in self.tableView.visibleCells) {
        SGModRow *row = [self rowAt:[self.tableView indexPathForCell:cell]];
        UILabel *label = (UILabel *)cell.accessoryView;
        if (!row.value || ![label isKindOfClass:UILabel.class]) continue;
        label.text = row.value();
        [label sizeToFit];
        [cell setNeedsLayout];
    }
}

// A check that lands may have brought a release nobody had heard of: the whole page is built again,
// intro and all, and faded in where it stands.
- (void)checkLanded {
    _groups = [self build];
    UILabel *note = (UILabel *)_intro.subviews.firstObject;
    note.text = [self introText];
    [self.view setNeedsLayout];
    [UIView transitionWithView:self.tableView duration:0.25 options:UIViewAnimationOptionTransitionCrossDissolve
                    animations:^{ [self.tableView reloadData]; } completion:nil];
}

- (SGModRow *)rowAt:(NSIndexPath *)path {
    if (!path) return nil;
    return _groups[(NSUInteger)path.section].rows[(NSUInteger)path.row];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)table {
    return (NSInteger)_groups.count;
}

- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)_groups[(NSUInteger)section].rows.count;
}

- (UIView *)tableView:(UITableView *)table viewForHeaderInSection:(NSInteger)section {
    NSString *title = _groups[(NSUInteger)section].title;
    return title ? SGSectionHeader(table, title) : nil;
}

- (CGFloat)tableView:(UITableView *)table heightForHeaderInSection:(NSInteger)section {
    return _groups[(NSUInteger)section].title ? SGSectionHeaderHeight() : SGSectionGap;
}

- (UIView *)tableView:(UITableView *)table viewForFooterInSection:(NSInteger)section {
    return nil;
}

- (CGFloat)tableView:(UITableView *)table heightForFooterInSection:(NSInteger)section {
    return CGFLOAT_MIN;
}

- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    SGModRow *row = [self rowAt:path];
    UITableViewCell *cell = SGDequeueCell(table, row.symbol ? @"tiled" : @"line");
    SGFillCell(cell, row.title, row.subtitle, nil, nil);
    if (row.symbol) {
        UIListContentConfiguration *content = (UIListContentConfiguration *)cell.contentConfiguration;
        content.image = SGTileImage(row.symbol);
        content.imageToTextPadding = 14;
        cell.contentConfiguration = content;
    }
    cell.separatorInset = UIEdgeInsetsMake(0, row.symbol ? 58 : 16, 0, 0);
    if (row.key) {
        UISwitch *toggle = [UISwitch new];
        toggle.onTintColor = SGGreen();
        toggle.on = SGFlag(row.key, row.defaultOn);
        toggle.accessibilityLabel = row.title;
        [toggle addTarget:self action:@selector(toggled:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = toggle;
    } else if (row.value) {
        UILabel *label = [UILabel new];
        label.font = SGCappedFont(SGTitleFont(), 18);   // beside the title, which keeps its room
        label.textColor = SGGrey();
        label.text = row.value();
        [label sizeToFit];
        cell.accessoryView = label;
    }
    cell.selectionStyle = row.action ? UITableViewCellSelectionStyleDefault : UITableViewCellSelectionStyleNone;
    cell.accessibilityTraits = row.action ? UIAccessibilityTraitButton : UIAccessibilityTraitStaticText;
    return cell;
}

// The switch is read by the cell it sits in, since a rebuilt page moves the rows under it.
- (void)toggled:(UISwitch *)toggle {
    UIView *view = toggle;
    while (view && ![view isKindOfClass:UITableViewCell.class]) view = view.superview;
    SGModRow *row = [self rowAt:[self.tableView indexPathForCell:(UITableViewCell *)view]];
    if (row.key) {
        SGSetEnabled(row.key, toggle.on);
        if (row.changed) row.changed(toggle.on);
    }
}

- (BOOL)tableView:(UITableView *)table shouldHighlightRowAtIndexPath:(NSIndexPath *)path {
    return [self rowAt:path].action != nil;
}

- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)path {
    [table deselectRowAtIndexPath:path animated:YES];
    SGModRow *row = [self rowAt:path];
    if (row.action) row.action();
    // Check now goes gray to "checking…" the moment it is tapped rather than on the next tick.
    if (row.value) [self readStatus];
}

@end

UIViewController *SGUpdatePage(void) {
    // Opening the page respects this build's cached check; Check now bypasses it.
    SGCheckForUpdate(NO);
    return [SGUpdatePageController new];
}
