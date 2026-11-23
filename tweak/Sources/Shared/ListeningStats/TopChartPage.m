// The chart a Top heading of Listening stats opens: for the period the page shows, how many different songs,
// artists or albums were played and how many of them for the first time, then the top 50, each with its plays and
// listening time, its move since the period before (or New), and how many periods in a row it has held the top 5.
// SGChartBuild adds it up off main from the log's snapshot; a chart is kept for its kind, period and log state,
// and the page adds it up again when the log changes while it shows.
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Settings/SGPageStyle.h"
#import "ListeningStats.h"
#import "ListeningStatsStyle.h"

// A label drawn inside padding, for the New capsule.
@interface SGChartCapsule : UILabel
@end
@implementation SGChartCapsule
static const UIEdgeInsets kCapsulePadding = {2, 7, 2, 7};
- (CGSize)intrinsicContentSize {
    CGSize size = [super intrinsicContentSize];
    return CGSizeMake(size.width + kCapsulePadding.left + kCapsulePadding.right, size.height + kCapsulePadding.top + kCapsulePadding.bottom);
}
- (void)drawTextInRect:(CGRect)rect {
    [super drawTextInRect:UIEdgeInsetsInsetRect(rect, kCapsulePadding)];
}
- (void)layoutSubviews {
    [super layoutSubviews];
    self.layer.cornerRadius = self.bounds.size.height / 2;
}
@end

static UIColor *risingColor(void) {
    return [UIColor colorWithRed:0x30 / 255.0 green:0xD1 / 255.0 blue:0x58 / 255.0 alpha:1];   // the dark appearance's system green
}

static NSString *periodsText(SGStatsPeriod period, NSUInteger count) {
    NSString *format = period == SGStatsPeriodYear ? SGL(@"settings.stats.chart.run.years", @"%lu years in the top %lu")
                     : period == SGStatsPeriodMonth ? SGL(@"settings.stats.chart.run.months", @"%lu months in the top %lu")
                     : SGL(@"settings.stats.chart.run.weeks", @"%lu weeks in the top %lu");
    return [NSString stringWithFormat:format, (unsigned long)count, (unsigned long)SGChartRunTop];
}

// One entry: its rank, its name over its artist, its plays and time and its run, and its move at the trailing
// edge. Read as one element.
@interface SGChartEntryView : UIView
- (void)showEntry:(SGChartEntry *)entry period:(SGStatsPeriod)period;
@end
@implementation SGChartEntryView {
    UILabel *_rank, *_name, *_detail, *_counts, *_run, *_move;
    SGChartCapsule *_new;
    UIStackView *_line, *_texts, *_trailing;
    NSLayoutConstraint *_rankWidth;
}
- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    _rank = SGStatsLabel(UIColor.whiteColor);
    _rank.numberOfLines = 1;
    _rankWidth = [_rank.widthAnchor constraintGreaterThanOrEqualToConstant:0];
    _rankWidth.active = YES;
    _name = SGStatsLabel(UIColor.whiteColor);
    _detail = SGStatsLabel(SGGrey());
    _counts = SGStatsLabel(SGGrey());
    _run = SGStatsLabel(SGAccentMark());
    _move = SGStatsLabel(SGGrey());
    _move.numberOfLines = 1;
    _new = [SGChartCapsule new];
    _new.text = SGL(@"settings.stats.chart.new", @"NEW");
    _new.textColor = SGOnAccent();
    _new.backgroundColor = SGGreen();
    _new.clipsToBounds = YES;
    _texts = [[UIStackView alloc] initWithArrangedSubviews:@[_name, _detail, _counts, _run]];
    _texts.axis = UILayoutConstraintAxisVertical;
    _texts.spacing = 2;
    [_texts setCustomSpacing:4 afterView:_detail];
    _trailing = [[UIStackView alloc] initWithArrangedSubviews:@[_move, _new]];
    _trailing.alignment = UIStackViewAlignmentCenter;
    for (UIView *view in @[_rank, _trailing, _move, _new]) {
        [view setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        [view setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    }
    _line = [[UIStackView alloc] initWithArrangedSubviews:@[_rank, _texts, _trailing]];
    _line.spacing = 12;
    _line.layoutMarginsRelativeArrangement = YES;
    _line.directionalLayoutMargins = NSDirectionalEdgeInsetsMake(11, 0, 11, 0);
    _line.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_line];
    [NSLayoutConstraint activateConstraints:@[
        [_line.leadingAnchor constraintEqualToAnchor:self.leadingAnchor], [_line.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [_line.topAnchor constraintEqualToAnchor:self.topAnchor], [_line.bottomAnchor constraintEqualToAnchor:self.bottomAnchor]]];
    self.isAccessibilityElement = YES;
    return self;
}
- (void)showEntry:(SGChartEntry *)entry period:(SGStatsPeriod)period {
    BOOL stacked = SGAccessibilityTextSize();
    _line.axis = stacked ? UILayoutConstraintAxisVertical : UILayoutConstraintAxisHorizontal;
    _line.alignment = stacked ? UIStackViewAlignmentLeading : UIStackViewAlignmentCenter;
    _rank.textAlignment = stacked ? NSTextAlignmentNatural : NSTextAlignmentCenter;
    _rank.font = SGMonospacedDigitsFont(SGStatsStrongFont(17, 34));
    _name.font = SGTitleFont();
    for (UILabel *label in @[_detail, _counts, _run]) label.font = SGSubtitleFont();
    _new.font = SGCappedFont(SGStatsStrongFont(10, 20), 20);
    _rank.text = SGStatsCount(entry.rank);
    // As wide as the chart's last rank in this font, so every name starts at the same place.
    _rankWidth.constant = ceil([SGStatsCount(SGChartLength) sizeWithAttributes:@{NSFontAttributeName: _rank.font}].width);

    _name.text = entry.name;
    _detail.text = entry.detail;
    _detail.hidden = !entry.detail.length;
    NSString *plays = SGStatsPlays(entry.plays), *time = SGStatsDuration(entry.ms);
    _counts.text = [NSString stringWithFormat:SGL(@"settings.stats.chart.counts", @"%@ · %@"), plays, time];
    NSString *run = entry.run >= SGChartRunShown ? periodsText(period, entry.run) : nil;
    if (run) {
        NSTextAttachment *flame = [NSTextAttachment textAttachmentWithImage:[[UIImage systemImageNamed:@"flame.fill"
            withConfiguration:[UIImageSymbolConfiguration configurationWithFont:_run.font scale:UIImageSymbolScaleSmall]]
            imageWithTintColor:SGAccentMark() renderingMode:UIImageRenderingModeAlwaysOriginal]];
        NSMutableAttributedString *text = [[NSAttributedString attributedStringWithAttachment:flame] mutableCopy];
        [text appendAttributedString:[[NSAttributedString alloc] initWithString:[@" " stringByAppendingString:run]
            attributes:@{NSFontAttributeName: _run.font, NSForegroundColorAttributeName: SGAccentMark()}]];
        _run.attributedText = text;
    }
    _run.hidden = !run;

    NSString *spokenMove;
    _new.hidden = entry.previousRank != 0;
    _move.hidden = entry.previousRank == 0;
    if (!entry.previousRank) {
        spokenMove = SGL(@"settings.stats.chart.a11y.new", @"New");
    } else {
        NSInteger change = (NSInteger)entry.previousRank - (NSInteger)entry.rank;
        NSString *symbol = change > 0 ? @"arrowtriangle.up.fill" : change < 0 ? @"arrowtriangle.down.fill" : @"minus";
        UIColor *color = change > 0 ? risingColor() : change < 0 ? SGRed() : SGGrey();
        UIFont *font = SGMonospacedDigitsFont(SGCappedFont(SGStatsStrongFont(12, 22), 22));
        NSTextAttachment *arrow = [NSTextAttachment textAttachmentWithImage:[[UIImage systemImageNamed:symbol
            withConfiguration:[UIImageSymbolConfiguration configurationWithFont:font scale:UIImageSymbolScaleSmall]]
            imageWithTintColor:color renderingMode:UIImageRenderingModeAlwaysOriginal]];
        NSMutableAttributedString *text = [[NSAttributedString attributedStringWithAttachment:arrow] mutableCopy];
        if (change) [text appendAttributedString:[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@" %@", SGStatsCount((NSUInteger)labs(change))]
            attributes:@{NSFontAttributeName: font, NSForegroundColorAttributeName: color}]];
        _move.attributedText = text;
        spokenMove = change > 0 ? [NSString stringWithFormat:SGL(@"settings.stats.chart.a11y.up", @"Up %lu"), (unsigned long)change]
                   : change < 0 ? [NSString stringWithFormat:SGL(@"settings.stats.chart.a11y.down", @"Down %lu"), (unsigned long)-change]
                   : SGL(@"settings.stats.chart.a11y.same", @"No change");
    }

    NSMutableArray<NSString *> *label = [NSMutableArray arrayWithObject:[NSString stringWithFormat:SGL(@"settings.stats.chart.a11y.rank", @"Number %lu"), (unsigned long)entry.rank]];
    [label addObject:entry.name ?: @""];
    if (entry.detail.length) [label addObject:entry.detail];
    self.accessibilityLabel = [label componentsJoinedByString:@", "];
    NSMutableArray<NSString *> *value = [NSMutableArray arrayWithObjects:spokenMove, plays, time, nil];
    if (run) [value addObject:run];
    self.accessibilityValue = [value componentsJoinedByString:@", "];
}
@end

// The chart's entries on one card, a hairline between them, or what stands for them: loading, an empty period or a
// load error. One row whatever it shows, so the page's rows never change under the reader.
@interface SGChartListCell : UITableViewCell
- (void)showEntries:(NSArray<SGChartEntry *> *)entries period:(SGStatsPeriod)period;
- (void)showMessage:(NSString *)title detail:(NSString *)detail;
@end
@implementation SGChartListCell {
    UIStackView *_stack;
    NSMutableArray<SGChartEntryView *> *_views;
}
- (instancetype)init {
    if (!(self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil])) return nil;
    SGStatsPrepareCard(self);
    _stack = [UIStackView new];
    _stack.axis = UILayoutConstraintAxisVertical;
    SGStatsPinToCard(_stack, self, 0);
    _views = [NSMutableArray array];
    return self;
}
- (void)clear {
    for (UIView *view in _stack.arrangedSubviews) {
        [_stack removeArrangedSubview:view];
        [view removeFromSuperview];
    }
}
- (void)showEntries:(NSArray<SGChartEntry *> *)entries period:(SGStatsPeriod)period {
    [self clear];
    while (_views.count < entries.count) [_views addObject:[SGChartEntryView new]];
    [entries enumerateObjectsUsingBlock:^(SGChartEntry *entry, NSUInteger i, BOOL *stop) {
        if (i) {
            UIView *hairline = [UIView new];
            hairline.backgroundColor = [UIColor colorWithWhite:1 alpha:0.1];
            [hairline.heightAnchor constraintEqualToConstant:1 / MAX(1, self.traitCollection.displayScale)].active = YES;
            [self->_stack addArrangedSubview:hairline];
        }
        SGChartEntryView *view = self->_views[i];
        [view showEntry:entry period:period];
        [self->_stack addArrangedSubview:view];
    }];
}
- (void)showMessage:(NSString *)title detail:(NSString *)detail {
    [self clear];
    UILabel *name = SGStatsLabel(UIColor.whiteColor), *under = SGStatsLabel(SGGrey());
    name.font = SGTitleFont();
    name.text = title;
    under.font = SGSubtitleFont();
    under.text = detail;
    under.hidden = !detail.length;
    UIStackView *texts = [[UIStackView alloc] initWithArrangedSubviews:@[name, under]];
    texts.axis = UILayoutConstraintAxisVertical;
    texts.spacing = 2;
    texts.layoutMarginsRelativeArrangement = YES;
    texts.directionalLayoutMargins = NSDirectionalEdgeInsetsMake(11, 0, 11, 0);
    texts.isAccessibilityElement = YES;
    texts.accessibilityLabel = title;
    texts.accessibilityValue = detail;
    [_stack addArrangedSubview:texts];
}
@end

@interface SGTopChartController : SGModPage
@property (nonatomic) SGChartKind kind;
@property (nonatomic) SGStatsPeriod period;
@property (nonatomic, strong) NSDate *start;
@property (nonatomic, strong) SGModRow *summaryRow, *listRow;
@property (nonatomic, strong) SGStatsPairCell *summaryCell;
@property (nonatomic, strong) SGChartListCell *listCell;
@property (nonatomic, copy) NSString *messageTitle, *messageDetail;   // what the list card says without entries
@property (nonatomic, strong) SGChart *chart;           // nil while loading or after a load error
@property (nonatomic, copy) NSString *summaryState;     // what the summary reads without a chart
@property (nonatomic) NSUInteger generation;
@property (nonatomic) BOOL observing;
@end

// Charts already added up, by their kind, period and the log's state; a change to the log misses them.
static NSCache<NSString *, SGChart *> *chartCache(void) {
    static NSCache *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cache = [NSCache new]; cache.countLimit = 24; });
    return cache;
}

static dispatch_queue_t chartQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ queue = dispatch_queue_create("retrine.stats.charts", dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_USER_INITIATED, 0)); });
    return queue;
}

@implementation SGTopChartController

- (void)viewDidLoad {
    [super viewDidLoad];
    NSArray<NSString *> *symbols = @[@"music.note", @"music.mic", @"square.stack"];
    NSArray<NSString *> *captions = @[SGL(@"settings.stats.chart.played.songs", @"Songs played"), SGL(@"settings.stats.chart.played.artists", @"Artists played"),
                                      SGL(@"settings.stats.chart.played.albums", @"Albums played")];
    self.summaryCell = [[SGStatsPairCell alloc] initWithFirst:[[SGStatsColumn alloc] initWithSymbol:symbols[(NSUInteger)self.kind] caption:captions[(NSUInteger)self.kind]]
                                                       second:[[SGStatsColumn alloc] initWithSymbol:@"sparkles" caption:SGL(@"settings.stats.chart.discovered", @"Discovered")]];
    self.summaryState = SGL(@"settings.stats.status.loading", @"Loading…");
    self.listCell = [SGChartListCell new];
    self.messageTitle = self.summaryState;
    [self showSummary];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (!self.observing) {
        self.observing = YES;
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(reload) name:SGPlayLogDidChangeNotification object:SGListeningLog()];
    }
    [self reload];
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    if (self.observing) {
        [NSNotificationCenter.defaultCenter removeObserver:self name:SGPlayLogDidChangeNotification object:SGListeningLog()];
        self.observing = NO;
    }
}

- (NSString *)firstTimeNote {
    return self.period == SGStatsPeriodYear ? SGL(@"settings.stats.chart.discovered.year", @"First played this year")
         : self.period == SGStatsPeriodMonth ? SGL(@"settings.stats.chart.discovered.month", @"First played this month")
         : SGL(@"settings.stats.chart.discovered.week", @"First played this week");
}

- (void)showSummary {
    SGChart *chart = self.chart;
    [self.summaryCell.first showValue:chart ? SGStatsCount(chart.played) : self.summaryState note:nil];
    [self.summaryCell.second showValue:chart ? SGStatsCount(chart.discovered) : self.summaryState note:self.firstTimeNote];
}

// The list card drawn again, entries or message, in the fonts of the text size now.
- (void)showList {
    if (self.chart.entries.count) [self.listCell showEntries:self.chart.entries period:self.period];
    else [self.listCell showMessage:self.messageTitle detail:self.messageDetail];
}

- (void)showMessage:(NSString *)title detail:(NSString *)detail {
    self.messageTitle = title;
    self.messageDetail = detail;
    [self.tableView reloadData];
    UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, title);
}

- (void)reload {
    NSUInteger generation = ++self.generation;
    __weak SGTopChartController *weakSelf = self;
    SGPlayLog *log = SGListeningLog();
    [log loadWithCompletion:^{
        SGTopChartController *page = weakSelf;
        if (!page || page.generation != generation) return;
        if (log.loadError) {
            page.chart = nil;
            page.summaryState = SGL(@"settings.stats.status.unavailable", @"Unavailable");
            [page showSummary];
            [page showMessage:SGL(@"settings.stats.error.load", @"Could not load history") detail:log.loadError.localizedDescription];
            return;
        }
        NSArray<SGPlay *> *snapshot = log.plays;
        NSCalendar *calendar = [NSCalendar.currentCalendar copy];
        SGChartKind kind = page.kind;
        SGStatsPeriod period = page.period;
        NSDate *start = page.start;
        NSString *key = [NSString stringWithFormat:@"%ld %ld %@", (long)kind, (long)period,
                         SGStatsCacheKey(SGPeriodInterval(period, start, calendar), calendar, log.playsGeneration, snapshot.count)];
        SGChart *cached = [chartCache() objectForKey:key];
        if (cached) { [page showChart:cached]; return; }
        dispatch_async(chartQueue(), ^{
            SGChart *chart = SGChartBuild(snapshot, kind, period, start, calendar) ?: [SGChart new];
            [chartCache() setObject:chart forKey:key];
            dispatch_async(dispatch_get_main_queue(), ^{
                SGTopChartController *page = weakSelf;
                if (page && page.generation == generation) [page showChart:chart];
            });
        });
    }];
}

- (void)showChart:(SGChart *)chart {
    self.chart = chart;
    [self showSummary];
    if (!chart.entries.count) {
        NSArray<NSString *> *titles = @[SGL(@"settings.stats.chart.empty.songs", @"No songs played"), SGL(@"settings.stats.chart.empty.artists", @"No artists played"),
                                        SGL(@"settings.stats.chart.empty.albums", @"No albums played")];
        [self showMessage:titles[(NSUInteger)self.kind]
                   detail:SGL(@"settings.stats.chart.empty.detail", @"Nothing was played in this period. Plays recorded or imported for it are ranked here.")];
        return;
    }
    [self.tableView reloadData];
    UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, SGL(@"settings.stats.a11y.loaded", @"History loaded"));
}

// Both rows are cards of the page's own; their fonts are set again on every pass, for a text size changed
// while the page is open.
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    NSArray<SGModRow *> *rows = self.sections[(NSUInteger)path.section].rows;
    SGModRow *row = (NSUInteger)path.row < rows.count ? rows[(NSUInteger)path.row] : nil;
    if (row == self.summaryRow) {
        [self.summaryCell render];
        [self showSummary];
        return self.summaryCell;
    }
    if (row == self.listRow) {
        [self showList];
        return self.listCell;
    }
    return [super tableView:table cellForRowAtIndexPath:path];
}

- (BOOL)tableView:(UITableView *)table shouldHighlightRowAtIndexPath:(NSIndexPath *)path {
    return NO;
}

@end

UIViewController *SGTopChartPage(SGChartKind kind, SGStatsPeriod period, NSDate *start, NSString *periodTitle) {
    NSArray<NSString *> *titles = @[SGL(@"settings.stats.section.top_tracks", @"Top tracks"), SGL(@"settings.stats.section.top_artists", @"Top artists"),
                                    SGL(@"settings.stats.section.top_albums", @"Top albums")];
    NSString *compared = period == SGStatsPeriodYear ? SGL(@"settings.stats.chart.footer.year", @"Arrows compare each rank with the year before. New: not in that year's top %lu.")
                       : period == SGStatsPeriodMonth ? SGL(@"settings.stats.chart.footer.month", @"Arrows compare each rank with the month before. New: not in that month's top %lu.")
                       : SGL(@"settings.stats.chart.footer.week", @"Arrows compare each rank with the week before. New: not in that week's top %lu.");
    // The rows drawn by the cards have no title, so Settings search passes them by.
    SGModRow *summary = [SGModRow new], *list = [SGModRow new];
    SGTopChartController *page = [[SGTopChartController alloc] initWithTitle:titles[(NSUInteger)kind] intro:nil sections:@[
        SGSection(nil, @[summary]),
        SGNotedSection(periodTitle, @[list], [NSString stringWithFormat:compared, (unsigned long)SGChartLength])] footer:nil];
    page.kind = kind;
    page.period = period;
    page.start = start;
    page.summaryRow = summary;
    page.listRow = list;
    return page;
}
