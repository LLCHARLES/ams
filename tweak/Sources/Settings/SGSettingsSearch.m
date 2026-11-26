// The field over Mod Settings and the results under it: a field with words typed shows the rows the pages read so
// far hold (SGSettingsIndex), and one left empty shows the settings the results led to before. A row picked opens the
// page it sits on, scrolled to it and lit for a moment, or the page it opens. The pages are built by their rows'
// blocks as they are opened, so nothing lists every row ahead of time: opening the field reads the searched page
// itself, and the pages under it follow one per pass of the main run loop.
#import "SGSettingsSearch.h"
#import "SGSettingsIndex.h"
#import "SGPageStyle.h"
#import "Core/SGCore.h"

static char kSearchKey;

@interface SGSettingsResults : SGPage <UISearchResultsUpdating, UISearchControllerDelegate>
@property (nonatomic, weak) SGModPage *owner;
@property (nonatomic, weak) UISearchBar *bar;
// The field this table is the results of: its `showsSearchResultsController` is held on, off the field's own rule,
// so the table (and the recents on it) shows for an empty field too, which that rule hides.
@property (nonatomic, weak) UISearchController *search;
@end

// The field's own box sits 8pt inside the bar, so the bar is set out by the table's margin less that: the field
// lines up with the cards under it.
@interface SGSettingsSearchHeader : UIView
@property (nonatomic, weak) UITableView *table;
@property (nonatomic, weak) UISearchBar *bar;
@end

@implementation SGSettingsSearchHeader
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat inset = MAX(0, self.table.layoutMargins.left - 8);
    self.bar.frame = CGRectMake(inset, 0, MAX(0, self.bounds.size.width - 2 * inset), self.bounds.size.height);
}
@end

@implementation SGSettingsResults {
    SGSettingsIndex *_index;
    NSString *_query;                   // the field's text, folded; nil until the field is first asked
    NSString *_shownQuery;              // the query the table was last scrolled to the top for
    NSArray<SGSettingsHit *> *_hits;
    NSArray<SGSettingsHit *> *_recents;   // the recent places the rows read so far hold
    UILabel *_none;
    id _defaultsObserver;
    UIViewController *_destination;
}

- (instancetype)init {
    if (!(self = [super initWithStyle:UITableViewStyleInsetGrouped])) return nil;
    __weak typeof(self) weakSelf = self;
    _defaultsObserver = [NSNotificationCenter.defaultCenter addObserverForName:NSUserDefaultsDidChangeNotification object:nil queue:nil
        usingBlock:^(NSNotification *note) {
            dispatch_async(dispatch_get_main_queue(), ^{
                // A switch flipped outside the results can hide or show a row, so the pages are read again. The recents
                // are one of the things written this way and need no re-read, but they come
                // with the same write, and a results table that is not up needs no index at all.
                if (!weakSelf.keysUp) return;
                [weakSelf readPages];
            });
        }];
    return self;
}

- (void)dealloc {
    [_index stop];
    [NSNotificationCenter.defaultCenter removeObserver:_defaultsObserver];
}

// The field is closed or its page is off screen: nothing more is built, and opening it again reads the pages afresh,
// since a switch flipped meanwhile may have moved a row.
- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    [_index stop];
    _index = nil;
    _shownQuery = nil;
}

// The field is showing its results, over its page.
- (BOOL)keysUp {
    return _index != nil && self.view.window != nil;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    // The results show over the page from its top, the field still on it: they start under the field, not under
    // the safe area the page's own rows start under.
    self.tableView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    _none = [UILabel new];
    _none.text = SGL(@"settings.search.none", @"No Results");
    _none.textColor = SGGrey();
    _none.textAlignment = NSTextAlignmentCenter;
}

// The field shows its table for as long as it is up, and UIKit takes the table down with the field, so nothing here
// has to put it back: this only keeps the table up when the field's own rule would take it away, which is when the
// text is empty or is cleared (SGSettingsSearchAttach sets it once, off that rule for good).
- (void)updateSearchResultsForSearchController:(UISearchController *)search {
    search.showsSearchResultsController = YES;
    NSString *query = [SGSearchFold(search.searchBar.text) stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    _query = [query copy];
    // A field nobody typed in reads the pages only when it has stored places to find among them; a typed query
    // matches the pages read before it as they are, and the pages still to be read join them.
    if (!_index && (query.length || SGSearchRecents().count)) [self readPages];
    else [self showResults];
}

#pragma mark - the table

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    // Measured in the results' container, which does not scroll: in the table's own space the field would move
    // with every offset the table is given, and each pass would ask for another.
    UISearchBar *bar = self.bar;
    UIView *container = self.view.superview;
    CGFloat top = bar.window && container ? round(MAX(0, CGRectGetMaxY([container convertRect:bar.bounds fromView:bar]) - CGRectGetMinY(self.view.frame)))
                                          : self.view.safeAreaInsets.top;
    UITableView *table = self.tableView;
    if (fabs(table.contentInset.top - top) > 0.5) {
        UIEdgeInsets inset = table.contentInset;
        inset.top = top;
        table.contentInset = inset;
        table.verticalScrollIndicatorInsets = inset;
        table.contentOffset = CGPointMake(0, -top);
    }
    SGInsetForBars(table);
    _none.font = SGTitleFont();
}

#pragma mark - reading the pages

// The pages are read again from the page itself, which is what a changed setting needs: a row whose switch was
// flipped elsewhere comes or goes. What is read stays shown while it is read again.
- (void)readPages {
    [_index stop];
    _index = [SGSettingsIndex new];
    __weak typeof(self) weakSelf = self;
    _index.grew = ^{ [weakSelf showResults]; };
    [_index startWithRoot:self.owner];
    [self showResults];
    [_index scheduleStep];
}

// What the pages read so far hold, shown at once, and again as each pass adds to it. A field with nothing typed
// shows the recent places alone, and says nothing when there are none.
- (void)showResults {
    BOOL newQuery = ![(_shownQuery ?: @"") isEqualToString:_query ?: @""];
    _shownQuery = [_query copy];
    if (_query.length) {
        _hits = [_index hitsForQuery:_query];
        _recents = @[];
    } else {
        _hits = @[];
        _recents = [_index recentHits];
    }
    // "No Results" only once every page has been read: before that, the rows a later pass brings are still coming.
    self.tableView.backgroundView = _query.length && !_hits.count && !_index.running ? _none : nil;
    [self.tableView reloadData];
    // A new query reads from its best match down; a pass that adds to the same one leaves the page where it is.
    if (newQuery && _hits.count) self.tableView.contentOffset = CGPointMake(0, -self.tableView.contentInset.top);
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)table {
    return 2;
}

- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)(section == 0 ? _recents.count : _hits.count);
}

// The recents' heading sits over their card; the results have none, only the gap a section with no heading keeps.
- (CGFloat)tableView:(UITableView *)table heightForHeaderInSection:(NSInteger)section {
    if (section == 0) return _recents.count ? SGSectionHeaderHeight() : CGFLOAT_MIN;
    return SGSectionGap;
}

// No note under either card: the two sections are one list to the eye.
- (CGFloat)tableView:(UITableView *)table heightForFooterInSection:(NSInteger)section {
    return CGFLOAT_MIN;
}

// The recents' heading, with the way to forget them beside it; the results need none.
- (UIView *)tableView:(UITableView *)table viewForHeaderInSection:(NSInteger)section {
    if (section != 0 || !_recents.count) return nil;
    UIView *header = SGSectionHeader(table, SGL(@"settings.search.recent.header", @"Recently Opened"));
    UIButton *clear = [UIButton buttonWithType:UIButtonTypeSystem];
    [clear setTitle:SGL(@"settings.search.recent.clear", @"Clear") forState:UIControlStateNormal];
    clear.titleLabel.font = SGSubtitleFont();
    clear.tintColor = SGGreen();
    [clear sizeToFit];
    clear.frame = CGRectMake(header.bounds.size.width - 16 - clear.bounds.size.width, header.bounds.size.height - 7 - clear.bounds.size.height,
                             clear.bounds.size.width, clear.bounds.size.height);
    clear.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleTopMargin;
    [clear addTarget:self action:@selector(clearRecents) forControlEvents:UIControlEventTouchUpInside];
    [header addSubview:clear];
    return header;
}

- (void)clearRecents {
    SGSearchForgetRecents();
    [self showResults];
}

// The row as it reads on its page, its trail where its subtitle would be, under the tile of the page it is in.
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    NSArray<SGSettingsHit *> *hits = path.section == 0 ? _recents : _hits;
    SGSettingsHit *hit = hits[(NSUInteger)path.row];
    UITableViewCell *cell = SGDequeueCell(table, @"hit");
    NSString *where = hit.trail.count ? [hit.trail componentsJoinedByString:@" › "] : hit.subtitle;
    SGFillCell(cell, hit.title, where, nil, nil);
    UIListContentConfiguration *content = (UIListContentConfiguration *)cell.contentConfiguration;
    content.image = hit.symbol ? (hit.tint ? SGTileImageTinted(hit.symbol, hit.tint) : SGTileImage(hit.symbol)) : nil;
    cell.contentConfiguration = content;
    cell.separatorInset = UIEdgeInsetsMake(0, hit.symbol ? SGTileRowInset : 16, 0, 0);
    cell.accessoryView = nil;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    return cell;
}

// Where the results led is remembered before the page it opens is built, so a row opened again moves to the front.
- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)path {
    [table deselectRowAtIndexPath:path animated:YES];
    SGSettingsHit *hit = (path.section == 0 ? _recents : _hits)[(NSUInteger)path.row];
    SGModPage *owner = self.owner;
    // A row whose place says nothing (its page or the row has no name) opens all the same, it is just not remembered.
    [_index rememberPlace:hit.place];
    UIViewController *page = hit.open ? hit.open() : nil;
    if (!page) {
        // A row of the searched page itself: the results go, and the row is shown where it is.
        UISearchController *search = objc_getAssociatedObject(owner, &kSearchKey);
        search.active = NO;
        [owner revealRowTitled:hit.title];
        return;
    }
    if (!hit.opens && [page isKindOfClass:SGModPage.class]) [(SGModPage *)page revealRowTitled:hit.title];
    // Deactivation starts a dismissal even without animation. Pushing during it is rejected by the navigation
    // controller, so every destination waits for UIKit to finish taking the search off the stack.
    _destination = page;
    UISearchController *search = self.search;
    [UIView performWithoutAnimation:^{ search.active = NO; }];
}

- (void)didDismissSearchController:(UISearchController *)search {
    UIViewController *page = _destination;
    _destination = nil;
    if (page) SGShowPage(self.owner,page);
}

@end

UISearchController *SGSettingsSearchField(SGModPage *page) {
    return objc_getAssociatedObject(page, &kSearchKey);
}

void SGSettingsSearchAttach(SGModPage *page) {
    SGSettingsResults *results = [SGSettingsResults new];
    results.owner = page;
    UISearchController *search = [[UISearchController alloc] initWithSearchResultsController:results];
    results.bar = search.searchBar;
    results.search = search;
    search.delegate = results;
    search.searchResultsUpdater = results;
    // The field is not left to its own rule, which shows the table only while something is typed and takes it away
    // again the moment the text is cleared: the table is where the recently opened settings are, on an empty field
    // too. So the table is what the field shows from the start, and UIKit still takes it down with the field when the
    // field closes.
    search.showsSearchResultsController = YES;
    search.hidesNavigationBarDuringPresentation = NO;
    search.obscuresBackgroundDuringPresentation = NO;
    search.searchBar.placeholder = SGL(@"settings.search.placeholder", @"Search");
    search.searchBar.searchBarStyle = UISearchBarStyleMinimal;
    search.searchBar.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    [search.searchBar sizeToFit];
    // In the table's header rather than the navigation item: the page sits on Spotify's own stack, whose bar
    // is not the system's. The results show over this page only.
    SGSettingsSearchHeader *header = [[SGSettingsSearchHeader alloc] initWithFrame:CGRectMake(0, 0, page.tableView.bounds.size.width, search.searchBar.bounds.size.height)];
    header.table = page.tableView;
    header.bar = search.searchBar;
    [header addSubview:search.searchBar];
    page.tableView.tableHeaderView = header;
    page.definesPresentationContext = YES;
    objc_setAssociatedObject(page, &kSearchKey, search, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
