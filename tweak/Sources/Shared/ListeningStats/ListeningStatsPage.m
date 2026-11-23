// Shared local history pages. The log is main-owned; parsing, export and aggregation use snapshots.
//
// The page: a streak card; a calendar week, month or year stepped through (its chart, listening time, plays,
// hours and tops); all time; the Record plays switch; import, export and erase. The cards are cells of the
// page's own, one instance each, so a step or a reload never takes VoiceOver's focus off a control, and
// every row count stays fixed while data changes (the See all rows come and go with the page's ticker),
// so a step never scrolls the page.
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <QuartzCore/QuartzCore.h>
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Settings/SGPageStyle.h"
#import "ListeningStats.h"
#import "ListeningStatsStyle.h"
#import "SGPlayLog.h"
#import "SGTopCharts.h"
#import "SGRecap.h"

static BOOL sg_importing, sg_exporting, sg_picking;

@class SGPeriodCell, SGChartCell, SGTopListCell;

@interface SGListeningPage : SGModPage
@property (nonatomic, copy) void (^refreshHistory)(void);
@property (nonatomic) NSUInteger generation, periodGeneration;
@property (nonatomic) BOOL loading;
@property (nonatomic) BOOL observing;
// The rows drawn by the cards below; they have no title, so Settings search passes them by.
@property (nonatomic, strong) SGModRow *streakRow, *periodRow, *chartRow, *tracksRow, *artistsRow, *albumsRow;
@property (nonatomic, strong) SGStatsPairCell *streakCell;   // the current streak, then the best
@property (nonatomic, strong) SGPeriodCell *periodCell;
@property (nonatomic, strong) SGChartCell *chartCell;
@property (nonatomic, strong) SGTopListCell *tracksCell, *artistsCell, *albumsCell;
// What the rows' value blocks read.
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *values;
// The log as last loaded (nil until then or after a load error), its first play and the calendar it is read in.
@property (nonatomic, copy) NSArray<SGPlay *> *snapshot;
@property (nonatomic) int64_t earliest;
@property (nonatomic, copy) NSCalendar *calendar;
@property (nonatomic) SGStatsPeriod kind;
@property (nonatomic, strong) NSDateInterval *shown;
@property (nonatomic, strong) SGStats *stats;   // the shown period's, top 25 of each
@property (nonatomic, copy) NSString *statsTitle;   // the title of the period `stats` and `hours` add up
@property (nonatomic) SGStatsPeriod statsKind;      // and that period, which a Top heading's chart is for
@property (nonatomic, strong) NSDateInterval *statsShown;
// Top tracks, artists and albums, in SGChartKind order: their headings open the chart while the period has plays.
@property (nonatomic, copy) NSArray<SGModSection *> *topSections;
@property (nonatomic, strong) SGModRow *recapRow;
@property (nonatomic, copy) NSArray<SGStatEntry *> *hours;
@property (nonatomic, strong) SGListeningStreaks *streaks;
- (void)showPeriod;
- (void)showStreaks;
- (void)updateNavigator;
- (void)showSummaryError;
@end

NSString *SGStatsDuration(int64_t ms) {
    if (ms > 0 && ms < 60000) return SGL(@"settings.stats.time.less_than_minute", @"<1 min");
    int64_t minutes = ms / 60000;
    if (minutes < 60) return [NSString stringWithFormat:SGL(@"settings.stats.time.minutes", @"%lld min"), minutes];
    return [NSString stringWithFormat:SGL(@"settings.stats.time.hours_minutes", @"%lld h %lld min"), minutes / 60, minutes % 60];
}
NSString *SGStatsPlays(NSUInteger plays) {
    return [NSString stringWithFormat:plays == 1 ? SGL(@"settings.stats.plays.singular", @"%lu play") : SGL(@"settings.stats.plays.plural", @"%lu plays"), (unsigned long)plays];
}
NSString *SGStatsDays(NSUInteger days) {
    return [NSString stringWithFormat:days == 1 ? SGL(@"settings.stats.days.singular", @"%lu day") : SGL(@"settings.stats.days.plural", @"%lu days"), (unsigned long)days];
}
static void present(UIViewController *controller) {
    SGPresentDark(controller);
    [SGTopController() presentViewController:controller animated:YES completion:nil];
}
static void showAlert(NSString *title, NSString *message) {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:SGL(@"common.ok", @"OK") style:UIAlertActionStyleCancel handler:nil]];
    present(alert);
}
static SGModSection *topSection(NSString *title, NSArray<SGStatEntry *> *entries) {
    NSMutableArray<SGModRow *> *rows = [NSMutableArray array];
    [entries enumerateObjectsUsingBlock:^(SGStatEntry *entry, NSUInteger i, BOOL *stop) {
        NSString *plays = SGStatsPlays(entry.plays);
        SGModRow *row = SGStatRow([NSString stringWithFormat:SGL(@"settings.stats.rank_format", @"%lu. %@"), (unsigned long)i + 1, entry.name], ^NSString *{ return plays; });
        row.subtitle = entry.detail;
        [rows addObject:row];
    }];
    if (!rows.count) [rows addObject:SGStatRow(SGL(@"settings.stats.empty", @"Nothing yet"), nil)];
    return SGSection(title, rows);
}
static UIViewController *hoursPage(NSArray<SGStatEntry *> *hours) {
    NSMutableArray *rows = [NSMutableArray array];
    NSDateFormatter *formatter = [NSDateFormatter new];
    formatter.locale = NSLocale.currentLocale;
    // A non-DST day in UTC supplies every wall-clock hour; locale selects 12/24 h.
    formatter.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
    [formatter setLocalizedDateFormatFromTemplate:@"j"];
    for (NSUInteger hour = 0; hour < 24; hour++) {
        NSString *label = [formatter stringFromDate:[NSDate dateWithTimeIntervalSince1970:hour * 3600]];
        SGStatEntry *entry = hours[hour];
        NSString *time = SGStatsDuration(entry.ms);
        SGModRow *row = SGStatRow(label, ^NSString *{ return time; });
        row.subtitle = SGStatsPlays(entry.plays);
        [rows addObject:row];
    }
    return [[SGModPage alloc] initWithTitle:SGL(@"settings.stats.hours.title", @"By hour of day")
        intro:SGL(@"settings.stats.hours.intro", @"Each play and its listening time count in the local hour when it ended. Repeated daylight-saving hours are combined.")
        sections:@[SGSection(nil, rows)] footer:nil];
}
static UIViewController *periodPage(NSString *title, int64_t since) {
    SGModSection *summary = SGSection(nil, @[SGStatRow(SGL(@"settings.stats.status.loading", @"Loading…"), nil)]);
    SGModSection *tracks = SGSection(SGL(@"settings.stats.section.top_tracks", @"Top tracks"), @[]), *artists = SGSection(SGL(@"settings.stats.section.top_artists", @"Top artists"), @[]), *albums = SGSection(SGL(@"settings.stats.section.top_albums", @"Top albums"), @[]);
    SGModPage *page = [[SGModPage alloc] initWithTitle:title intro:nil sections:@[summary, tracks, artists, albums] footer:nil];
    __weak SGModPage *weakPage = page;
    [SGListeningLog() loadWithCompletion:^{
        if (SGListeningLog().loadError) {
            SGModRow *error = SGStatRow(SGL(@"settings.stats.error.load", @"Could not load history"), nil);
            error.subtitle = SGListeningLog().loadError.localizedDescription;
            summary.rows = @[error];
            [weakPage refreshVisibility];
            UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, error.title);
            return;
        }
        NSArray *snapshot = [SGListeningLog().plays copy];
        NSCalendar *calendar = [NSCalendar.currentCalendar copy];
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            SGStats *stats = SGStatsSince(snapshot, since, 25);
            NSArray *hours = SGHourlyStats(snapshot, since, calendar);
            dispatch_async(dispatch_get_main_queue(), ^{
                SGModPage *page = weakPage;
                if (!page) return;
                NSString *time = SGStatsDuration(stats.ms), *plays = SGStatsPlays(stats.plays);
                summary.rows = @[
                    SGStatRow(SGL(@"settings.stats.row.listening_time", @"Listening time"), ^NSString *{ return time; }),
                    SGStatRow(SGL(@"settings.stats.row.plays", @"Plays"), ^NSString *{ return plays; }),
                    SGPageRow(SGL(@"settings.stats.row.by_hour", @"By hour of day"), ^UIViewController *{ return hoursPage(hours); })];
                tracks.rows = topSection(SGL(@"settings.stats.section.top_tracks", @"Top tracks"), stats.tracks).rows;
                artists.rows = topSection(SGL(@"settings.stats.section.top_artists", @"Top artists"), stats.artists).rows;
                albums.rows = topSection(SGL(@"settings.stats.section.top_albums", @"Top albums"), stats.albums).rows;
                [page refreshVisibility];
                [page.tableView reloadData];
                UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, stats.plays ? SGL(@"settings.stats.a11y.loaded", @"History loaded") : SGL(@"settings.stats.a11y.no_plays", @"No plays in this period"));
            });
        });
    }];
    return page;
}

#pragma mark - dates

NSDateFormatter *SGStatsDateFormatter(NSCalendar *calendar, NSString *template) {
    NSDateFormatter *formatter = [NSDateFormatter new];
    formatter.locale = NSLocale.currentLocale;
    formatter.calendar = calendar;
    formatter.timeZone = calendar.timeZone;
    [formatter setLocalizedDateFormatFromTemplate:template];
    return formatter;
}

NSString *SGStatsCacheKey(NSDateInterval *interval, NSCalendar *calendar, NSUInteger playsGeneration, NSUInteger plays) {
    return [NSString stringWithFormat:@"%.0f %.0f %@ %@ %lu %lu %lu", interval.startDate.timeIntervalSince1970, interval.endDate.timeIntervalSince1970,
            calendar.calendarIdentifier, calendar.timeZone.name, (unsigned long)calendar.firstWeekday, (unsigned long)playsGeneration, (unsigned long)plays];
}

// Local days from `first` through `last`, the year written only when either is outside the current one.
static NSString *dayRange(NSDate *first, NSDate *last, NSCalendar *calendar) {
    NSInteger year = [calendar component:NSCalendarUnitYear fromDate:NSDate.date];
    BOOL thisYear = [calendar component:NSCalendarUnitYear fromDate:first] == year && [calendar component:NSCalendarUnitYear fromDate:last] == year;
    NSDateIntervalFormatter *formatter = [NSDateIntervalFormatter new];
    formatter.locale = NSLocale.currentLocale;
    formatter.calendar = calendar;
    formatter.timeZone = calendar.timeZone;
    formatter.dateTemplate = thisYear ? @"MMMd" : @"yMMMd";
    return [formatter stringFromDate:first toDate:last];
}

// [start, end): NSDateInterval's own test counts the end in.
static BOOL holds(NSDateInterval *interval, NSDate *date) {
    return [interval.startDate compare:date] != NSOrderedDescending && [date compare:interval.endDate] == NSOrderedAscending;
}

static NSString *periodTitle(SGStatsPeriod kind, NSDateInterval *shown, NSCalendar *calendar) {
    NSDate *now = NSDate.date;
    if (kind == SGStatsPeriodWeek) {
        if (holds(shown, now)) return SGL(@"settings.stats.period.this_week", @"This week");
        if ([shown.endDate isEqualToDate:SGPeriodInterval(kind, now, calendar).startDate]) return SGL(@"settings.stats.period.last_week", @"Last week");
        return dayRange(shown.startDate, [shown.endDate dateByAddingTimeInterval:-1], calendar);
    }
    return [SGStatsDateFormatter(calendar, kind == SGStatsPeriodMonth ? @"MMMMy" : @"y") stringFromDate:shown.startDate];
}

NSString *SGStatsCount(NSUInteger count) {
    return [NSNumberFormatter localizedStringFromNumber:@(count) numberStyle:NSNumberFormatterDecimalStyle];
}

#pragma mark - cards

UIFont *SGStatsStrongFont(CGFloat size, CGFloat largest) {
    UIFont *base = SGTitleFont();
    CGFloat scaled = MIN(largest, base.pointSize * size / 13);
    UIFontDescriptor *bold = [base.fontDescriptor fontDescriptorWithSymbolicTraits:UIFontDescriptorTraitBold];
    return bold ? [UIFont fontWithDescriptor:bold size:scaled] : [UIFont systemFontOfSize:scaled weight:UIFontWeightBold];
}

UILabel *SGStatsLabel(UIColor *color) {
    UILabel *label = [UILabel new];
    label.textColor = color;
    label.numberOfLines = 0;
    return label;
}

void SGStatsPinToCard(UIView *view, UITableViewCell *cell, CGFloat vertical) {
    UIView *content = cell.contentView;
    view.translatesAutoresizingMaskIntoConstraints = NO;
    [content addSubview:view];
    // One point under required, so the cell's first, estimated height does not break it before sizing.
    NSLayoutConstraint *bottom = [view.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-vertical];
    bottom.priority = UILayoutPriorityRequired - 1;
    [NSLayoutConstraint activateConstraints:@[
        [view.leadingAnchor constraintEqualToAnchor:content.layoutMarginsGuide.leadingAnchor],
        [view.trailingAnchor constraintEqualToAnchor:content.layoutMarginsGuide.trailingAnchor],
        [view.topAnchor constraintEqualToAnchor:content.topAnchor constant:vertical], bottom]];
}

void SGStatsPrepareCard(UITableViewCell *cell) {
    cell.backgroundColor = SGCardBackground();
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.isAccessibilityElement = NO;
}

@implementation SGStatsColumn {
    UIImageView *_icon;
    UILabel *_caption, *_value, *_note;
}
- (instancetype)initWithSymbol:(NSString *)symbol caption:(NSString *)caption {
    if (!(self = [super initWithFrame:CGRectZero])) return nil;
    self.axis = UILayoutConstraintAxisVertical;
    self.alignment = UIStackViewAlignmentLeading;
    self.spacing = 3;
    _icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:symbol]];
    _icon.contentMode = UIViewContentModeScaleAspectFit;
    _caption = SGStatsLabel(SGGrey());
    _caption.text = caption;
    UIStackView *top = [[UIStackView alloc] initWithArrangedSubviews:@[_icon, _caption]];
    top.spacing = 5;
    top.alignment = UIStackViewAlignmentCenter;
    _value = SGStatsLabel(UIColor.whiteColor);
    _note = SGStatsLabel(SGGrey());
    [self addArrangedSubview:top];
    [self addArrangedSubview:_value];
    [self addArrangedSubview:_note];
    [self setCustomSpacing:6 afterView:top];
    self.isAccessibilityElement = YES;
    return self;
}
- (void)showValue:(NSString *)value note:(NSString *)note {
    _caption.font = SGSubtitleFont();
    _note.font = SGSubtitleFont();
    _value.font = SGStatsStrongFont(24, 40);
    _icon.preferredSymbolConfiguration = [UIImageSymbolConfiguration configurationWithFont:SGCappedFont(SGSubtitleFont(), 22)];
    _icon.tintColor = SGAccentMark();
    _value.text = value;
    _note.text = note;
    _note.hidden = !note.length;
    self.accessibilityLabel = _caption.text;
    self.accessibilityValue = note.length ? [@[value, note] componentsJoinedByString:@", "] : value;
}
@end

@implementation SGStatsPairCell {
    UIStackView *_columns;
}
- (instancetype)initWithFirst:(SGStatsColumn *)first second:(SGStatsColumn *)second {
    if (!(self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil])) return nil;
    SGStatsPrepareCard(self);
    _first = first;
    _second = second;
    _columns = [[UIStackView alloc] initWithArrangedSubviews:@[first, second]];
    _columns.distribution = UIStackViewDistributionFillEqually;
    _columns.alignment = UIStackViewAlignmentTop;
    _columns.spacing = 16;
    SGStatsPinToCard(_columns, self, 14);
    return self;
}
- (void)render {
    _columns.axis = SGAccessibilityTextSize() ? UILayoutConstraintAxisVertical : UILayoutConstraintAxisHorizontal;
}
@end

// The period's kind over the step back, its title and the step forward.
@interface SGPeriodCell : UITableViewCell
@property (nonatomic, readonly) UISegmentedControl *kinds;
@property (nonatomic, readonly) UIButton *previous, *next;
@property (nonatomic, readonly) UILabel *title;
- (void)render;
@end
static UIButton *stepButton(NSString *symbol) {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setImage:[UIImage systemImageNamed:symbol] forState:UIControlStateNormal];
    button.tintColor = UIColor.whiteColor;
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[[button.widthAnchor constraintEqualToConstant:44], [button.heightAnchor constraintEqualToConstant:44]]];
    return button;
}
@implementation SGPeriodCell
- (instancetype)init {
    if (!(self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil])) return nil;
    SGStatsPrepareCard(self);
    _kinds = [[UISegmentedControl alloc] initWithItems:@[SGL(@"settings.stats.kind.week", @"Week"), SGL(@"settings.stats.kind.month", @"Month"),
                                                         SGL(@"settings.stats.kind.year", @"Year")]];
    _kinds.accessibilityLabel = SGL(@"settings.stats.a11y.period", @"Period");
    _previous = stepButton(@"chevron.left");
    _next = stepButton(@"chevron.right");
    _title = SGStatsLabel(UIColor.whiteColor);
    _title.textAlignment = NSTextAlignmentCenter;
    _title.accessibilityTraits = UIAccessibilityTraitHeader;
    [_title setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    [_title setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[_previous, _title, _next]];
    row.alignment = UIStackViewAlignmentCenter;
    row.spacing = 4;
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[_kinds, row]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 8;
    SGStatsPinToCard(stack, self, 12);
    return self;
}
- (void)render {
    [_kinds setTitleTextAttributes:@{NSFontAttributeName: SGCappedFont(SGTitleFont(), 22)} forState:UIControlStateNormal];
    _title.font = SGStatsStrongFont(17, 34);
    UIImageSymbolConfiguration *arrow = [UIImageSymbolConfiguration configurationWithPointSize:17 weight:UIImageSymbolWeightSemibold];
    [_previous setPreferredSymbolConfiguration:arrow forImageInState:UIControlStateNormal];
    [_next setPreferredSymbolConfiguration:arrow forImageInState:UIControlStateNormal];
}
@end

// Bars of listening time drawn on plain layers, one per day or month, a label under some, and one VoiceOver
// element per bar.
@interface SGStatsChart : UIView
- (void)showBuckets:(NSArray<SGStatBucket *> *)buckets labels:(NSArray<NSString *> *)labels spokenLabels:(NSArray<NSString *> *)spokenLabels
       spokenValues:(NSArray<NSString *> *)spokenValues highlighted:(NSInteger)highlighted;
- (CGFloat)labelHeight;
@end
@implementation SGStatsChart {
    NSArray<SGStatBucket *> *_buckets;
    NSMutableArray<CALayer *> *_bars;
    NSMutableArray<UILabel *> *_labels;
    BOOL _placeAtOnce;
}
- (UIFont *)labelFont {
    return SGCappedFont(SGSubtitleFont(), 14);
}
- (CGFloat)labelHeight {
    return ceil(self.labelFont.lineHeight) + 4;
}
- (void)showBuckets:(NSArray<SGStatBucket *> *)buckets labels:(NSArray<NSString *> *)labels spokenLabels:(NSArray<NSString *> *)spokenLabels
       spokenValues:(NSArray<NSString *> *)spokenValues highlighted:(NSInteger)highlighted {
    NSUInteger n = buckets.count;
    if (n != _bars.count) {
        for (CALayer *bar in _bars) [bar removeFromSuperlayer];
        for (UILabel *label in _labels) [label removeFromSuperview];
        _bars = [NSMutableArray arrayWithCapacity:n];
        _labels = [NSMutableArray arrayWithCapacity:n];
        for (NSUInteger i = 0; i < n; i++) {
            CALayer *bar = [CALayer layer];
            [self.layer addSublayer:bar];
            [_bars addObject:bar];
            UILabel *label = [UILabel new];
            label.textAlignment = NSTextAlignmentCenter;
            label.adjustsFontSizeToFitWidth = YES;
            label.minimumScaleFactor = 0.5;
            [self addSubview:label];
            [_labels addObject:label];
        }
        _placeAtOnce = YES;   // new bars appear where they belong; the same bars grow and shrink
    }
    _buckets = [buckets copy];
    NSMutableArray<UIAccessibilityElement *> *elements = [NSMutableArray arrayWithCapacity:n];
    for (NSUInteger i = 0; i < n; i++) {
        UILabel *label = _labels[i];
        label.text = labels[i];
        label.font = self.labelFont;
        label.textColor = (NSInteger)i == highlighted ? UIColor.whiteColor : SGGrey();
        UIAccessibilityElement *element = [[UIAccessibilityElement alloc] initWithAccessibilityContainer:self];
        element.accessibilityLabel = spokenLabels[i];
        element.accessibilityValue = spokenValues[i];
        element.accessibilityTraits = UIAccessibilityTraitStaticText;
        [elements addObject:element];
    }
    self.accessibilityElements = elements;
    [self setNeedsLayout];
}
- (void)layoutSubviews {
    [super layoutSubviews];
    NSUInteger n = _buckets.count;
    if (!n) return;
    CGFloat labelHeight = self.labelHeight, width = self.bounds.size.width;
    CGFloat area = MAX(0, self.bounds.size.height - labelHeight), slot = width / n;
    CGFloat barWidth = MIN(22, MAX(2, floor(slot * 0.6)));
    int64_t most = 1;
    for (SGStatBucket *bucket in _buckets) most = MAX(most, bucket.ms);
    [CATransaction begin];
    [CATransaction setDisableActions:_placeAtOnce || UIAccessibilityIsReduceMotionEnabled()];
    _placeAtOnce = NO;
    for (NSUInteger i = 0; i < n; i++) {
        SGStatBucket *bucket = _buckets[i];
        CGFloat height = bucket.ms > 0 ? MAX(3, round(area * (double)bucket.ms / (double)most)) : 2;
        CALayer *bar = _bars[i];
        bar.frame = CGRectMake(round(slot * i + (slot - barWidth) / 2), area - height, barWidth, height);
        bar.cornerRadius = MIN(barWidth / 2, 3);
        bar.backgroundColor = (bucket.ms > 0 ? SGAccentMark() : [UIColor colorWithWhite:1 alpha:0.14]).CGColor;
        // Wider than its slot so a month's day numbers fit; only every seventh has one.
        CGFloat labelWidth = MAX(slot, 24);
        _labels[i].frame = CGRectMake(slot * i + (slot - labelWidth) / 2, area + 4, labelWidth, labelHeight - 4);
        ((UIAccessibilityElement *)self.accessibilityElements[i]).accessibilityFrameInContainerSpace = CGRectMake(slot * i, 0, slot, self.bounds.size.height);
    }
    [CATransaction commit];
}
@end

@interface SGChartCell : UITableViewCell
@property (nonatomic, readonly) UILabel *caption;
@property (nonatomic, readonly) SGStatsChart *chart;
- (void)render;
@end
@implementation SGChartCell {
    NSLayoutConstraint *_height;
}
- (instancetype)init {
    if (!(self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil])) return nil;
    SGStatsPrepareCard(self);
    _caption = SGStatsLabel(SGGrey());
    _chart = [SGStatsChart new];
    _height = [_chart.heightAnchor constraintEqualToConstant:100];
    _height.active = YES;
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[_caption, _chart]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 10;
    SGStatsPinToCard(stack, self, 12);
    return self;
}
- (void)render {
    _caption.font = SGSubtitleFont();
    _height.constant = 88 + _chart.labelHeight;
}
@end

// A top list's first five, each read as one element; the See all row under it opens the rest.
@interface SGTopListCell : UITableViewCell
@property (nonatomic, copy) NSArray<SGStatEntry *> *entries;   // nil while loading
- (void)render;
@end
@implementation SGTopListCell {
    UIStackView *_stack;
}
- (instancetype)init {
    if (!(self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil])) return nil;
    SGStatsPrepareCard(self);
    _stack = [UIStackView new];
    _stack.axis = UILayoutConstraintAxisVertical;
    SGStatsPinToCard(_stack, self, 0);
    return self;
}
- (UIView *)lineWithTitle:(NSString *)title detail:(NSString *)detail trailing:(NSString *)trailing {
    UILabel *name = SGStatsLabel(UIColor.whiteColor), *under = SGStatsLabel(SGGrey()), *count = SGStatsLabel(SGGrey());
    name.font = SGTitleFont();
    name.text = title;
    under.font = SGSubtitleFont();
    under.text = detail;
    under.hidden = !detail.length;
    count.font = SGTitleFont();
    count.text = trailing;
    count.hidden = !trailing.length;
    [count setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [count setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    UIStackView *texts = [[UIStackView alloc] initWithArrangedSubviews:@[name, under]];
    texts.axis = UILayoutConstraintAxisVertical;
    texts.spacing = 2;
    UIStackView *line = [[UIStackView alloc] initWithArrangedSubviews:@[texts, count]];
    line.spacing = 12;
    line.alignment = UIStackViewAlignmentCenter;
    if (SGAccessibilityTextSize()) {
        line.axis = UILayoutConstraintAxisVertical;
        line.alignment = UIStackViewAlignmentLeading;
        line.spacing = 2;
    }
    line.layoutMarginsRelativeArrangement = YES;
    line.directionalLayoutMargins = NSDirectionalEdgeInsetsMake(11, 0, 11, 0);
    line.isAccessibilityElement = YES;
    line.accessibilityLabel = detail.length ? [@[title, detail] componentsJoinedByString:@", "] : title;
    line.accessibilityValue = trailing;
    return line;
}
- (void)render {
    for (UIView *view in _stack.arrangedSubviews) {
        [_stack removeArrangedSubview:view];
        [view removeFromSuperview];
    }
    if (!self.entries.count) {
        NSString *text = self.entries ? SGL(@"settings.stats.empty", @"Nothing yet") : SGL(@"settings.stats.status.loading", @"Loading…");
        [_stack addArrangedSubview:[self lineWithTitle:text detail:nil trailing:nil]];
        return;
    }
    NSUInteger shown = MIN(self.entries.count, 5);
    for (NSUInteger i = 0; i < shown; i++) {
        SGStatEntry *entry = self.entries[i];
        if (i) {
            UIView *hairline = [UIView new];
            hairline.backgroundColor = [UIColor colorWithWhite:1 alpha:0.1];
            [hairline.heightAnchor constraintEqualToConstant:1 / MAX(1, self.traitCollection.displayScale)].active = YES;
            [_stack addArrangedSubview:hairline];
        }
        NSString *title = [NSString stringWithFormat:SGL(@"settings.stats.rank_format", @"%lu. %@"), (unsigned long)i + 1, entry.name];
        [_stack addArrangedSubview:[self lineWithTitle:title detail:entry.detail trailing:SGStatsPlays(entry.plays)]];
    }
}
@end

#pragma mark - the page

@implementation SGListeningPage

- (void)viewDidLoad {
    [super viewDidLoad];
    self.streakCell = [[SGStatsPairCell alloc]
        initWithFirst:[[SGStatsColumn alloc] initWithSymbol:@"flame.fill" caption:SGL(@"settings.stats.row.current_streak", @"Current streak")]
               second:[[SGStatsColumn alloc] initWithSymbol:@"trophy.fill" caption:SGL(@"settings.stats.row.best_streak", @"Best streak")]];
    self.periodCell = [SGPeriodCell new];
    self.chartCell = [SGChartCell new];
    self.tracksCell = [SGTopListCell new];
    self.artistsCell = [SGTopListCell new];
    self.albumsCell = [SGTopListCell new];
    SGPeriodCell *period = self.periodCell;
    [period.kinds addTarget:self action:@selector(kindPicked) forControlEvents:UIControlEventValueChanged];
    [period.previous addTarget:self action:@selector(stepBack) forControlEvents:UIControlEventTouchUpInside];
    [period.next addTarget:self action:@selector(stepForward) forControlEvents:UIControlEventTouchUpInside];
    [self showStreaks];
    [self updateNavigator];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (!self.observing) {
        self.observing = YES;
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(historyChanged)
            name:SGPlayLogDidChangeNotification object:SGListeningLog()];
    }
    if (self.refreshHistory) self.refreshHistory();
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    if (self.observing) {
        [NSNotificationCenter.defaultCenter removeObserver:self name:SGPlayLogDidChangeNotification object:SGListeningLog()];
        self.observing = NO;
    }
}

- (void)historyChanged {
    if (self.refreshHistory) self.refreshHistory();
}

// The card at `path`, or nil for an ordinary row. Card rows sit in sections whose rows never change, so the
// section's own list names them.
- (UITableViewCell *)cardAt:(NSIndexPath *)path {
    NSArray<SGModRow *> *rows = self.sections[(NSUInteger)path.section].rows;
    SGModRow *row = (NSUInteger)path.row < rows.count ? rows[(NSUInteger)path.row] : nil;
    if (!row) return nil;
    if (row == self.streakRow) return self.streakCell;
    if (row == self.periodRow) return self.periodCell;
    if (row == self.chartRow) return self.chartCell;
    if (row == self.tracksRow) return self.tracksCell;
    if (row == self.artistsRow) return self.artistsCell;
    if (row == self.albumsRow) return self.albumsCell;
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *card = [self cardAt:path];
    if (!card) return [super tableView:table cellForRowAtIndexPath:path];
    // Fonts again on every pass, for a text size changed while the page was open.
    [(id)card render];
    if (card == self.streakCell) [self showStreaks];
    return card;
}

- (BOOL)tableView:(UITableView *)table shouldHighlightRowAtIndexPath:(NSIndexPath *)path {
    return ![self cardAt:path];
}

// A Top heading with a chevron after it, which opens that list's chart for the period added up; the plain
// heading while the period has no plays.
- (UIView *)tableView:(UITableView *)table viewForHeaderInSection:(NSInteger)section {
    NSUInteger kind = [self.topSections indexOfObject:self.sections[(NSUInteger)section]];
    if (kind == NSNotFound || !self.stats.plays) return [super tableView:table viewForHeaderInSection:section];
    NSString *title = self.topSections[kind].title;
    UIButtonConfiguration *look = [UIButtonConfiguration plainButtonConfiguration];
    look.attributedTitle = [[NSAttributedString alloc] initWithString:title.uppercaseString attributes:@{NSFontAttributeName: SGSubtitleFont()}];
    look.image = [UIImage systemImageNamed:@"chevron.right" withConfiguration:[UIImageSymbolConfiguration configurationWithFont:SGSubtitleFont() scale:UIImageSymbolScaleSmall]];
    look.imagePlacement = NSDirectionalRectEdgeTrailing;
    look.imagePadding = 4;
    look.baseForegroundColor = SGGrey();
    // Where SGSectionHeader puts its words: 16 pt in, 7 pt over the card.
    look.contentInsets = NSDirectionalEdgeInsetsMake(0, 16, 7, 16);
    __weak SGListeningPage *weakSelf = self;
    UIButton *heading = [UIButton buttonWithConfiguration:look primaryAction:[UIAction actionWithHandler:^(UIAction *action) {
        SGListeningPage *page = weakSelf;
        if (!page.statsShown) return;
        [page.navigationController pushViewController:SGTopChartPage((SGChartKind)kind, page.statsKind, page.statsShown.startDate, page.statsTitle) animated:YES];
    }]];
    heading.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeading;
    heading.contentVerticalAlignment = UIControlContentVerticalAlignmentBottom;
    heading.frame = CGRectMake(0, 0, table.bounds.size.width, SGSectionHeaderHeight());
    heading.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    heading.accessibilityLabel = title;
    heading.accessibilityHint = SGL(@"settings.stats.a11y.open_chart", @"Opens the chart for this period");
    heading.accessibilityTraits = UIAccessibilityTraitButton | UIAccessibilityTraitHeader;
    return heading;
}

#pragma mark stepping

- (BOOL)canStepBack {
    return self.snapshot && self.earliest < (int64_t)floor(self.shown.startDate.timeIntervalSince1970);
}

- (BOOL)canStepForward {
    return [self.shown.endDate compare:NSDate.date] != NSOrderedDescending;
}

- (void)updateNavigator {
    SGPeriodCell *cell = self.periodCell;
    if (!cell) return;
    cell.kinds.selectedSegmentIndex = self.kind;
    cell.title.text = periodTitle(self.kind, self.shown, self.calendar);
    BOOL back = [self canStepBack], forward = [self canStepForward];
    cell.previous.enabled = back;
    cell.next.enabled = forward;
    cell.previous.alpha = back ? 1 : 0.3;
    cell.next.alpha = forward ? 1 : 0.3;
    NSArray<NSString *> *previous = @[SGL(@"settings.stats.a11y.previous_week", @"Previous week"), SGL(@"settings.stats.a11y.previous_month", @"Previous month"),
                                      SGL(@"settings.stats.a11y.previous_year", @"Previous year")];
    NSArray<NSString *> *next = @[SGL(@"settings.stats.a11y.next_week", @"Next week"), SGL(@"settings.stats.a11y.next_month", @"Next month"),
                                  SGL(@"settings.stats.a11y.next_year", @"Next year")];
    cell.previous.accessibilityLabel = previous[(NSUInteger)self.kind];
    cell.next.accessibilityLabel = next[(NSUInteger)self.kind];
    self.chartCell.caption.text = self.kind == SGStatsPeriodYear ? SGL(@"settings.stats.chart.by_month", @"Listening time by month")
                                                                : SGL(@"settings.stats.chart.by_day", @"Listening time by day");
}

- (void)step:(NSInteger)delta {
    if (delta < 0 ? ![self canStepBack] : ![self canStepForward]) return;
    NSDateInterval *shown = SGPeriodStep(self.kind, self.shown.startDate, delta, self.calendar);
    if (!shown) return;
    self.shown = shown;
    [self showPeriod];
    UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, self.periodCell.title.text);
}

- (void)stepBack { [self step:-1]; }
- (void)stepForward { [self step:1]; }

// The new kind's period around the middle of the one shown, or now when that is later.
- (void)kindPicked {
    NSInteger index = self.periodCell.kinds.selectedSegmentIndex;
    if (index < SGStatsPeriodWeek || index > SGStatsPeriodYear || index == self.kind) return;
    NSDate *middle = [self.shown.startDate dateByAddingTimeInterval:self.shown.duration / 2], *now = NSDate.date;
    NSDateInterval *shown = SGPeriodInterval((SGStatsPeriod)index, [middle compare:now] == NSOrderedDescending ? now : middle, self.calendar);
    if (!shown) { [self updateNavigator]; return; }
    self.kind = (SGStatsPeriod)index;
    self.shown = shown;
    [self showPeriod];
}

// The shown period added up off main from the snapshot; a newer step or reload wins.
- (void)showPeriod {
    [self updateNavigator];
    NSArray<SGPlay *> *snapshot = self.snapshot;
    if (!snapshot) return;
    NSUInteger generation = ++self.periodGeneration;
    SGStatsPeriod kind = self.kind;
    NSDateInterval *shown = self.shown;
    NSCalendar *calendar = [self.calendar copy];
    __weak SGListeningPage *weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        int64_t start = (int64_t)floor(shown.startDate.timeIntervalSince1970), end = (int64_t)floor(shown.endDate.timeIntervalSince1970);
        SGStats *stats = SGStatsBetween(snapshot, start, end, 25);
        NSArray<SGStatEntry *> *hours = SGHourlyStatsBetween(snapshot, start, end, calendar);
        NSArray<SGStatBucket *> *buckets = SGPeriodBuckets(snapshot, kind, shown.startDate, calendar);
        dispatch_async(dispatch_get_main_queue(), ^{
            SGListeningPage *page = weakSelf;
            if (!page || page.periodGeneration != generation) return;
            [page showStats:stats hours:hours buckets:buckets kind:kind shown:shown];
        });
    });
}

- (void)showStats:(SGStats *)stats hours:(NSArray<SGStatEntry *> *)hours buckets:(NSArray<SGStatBucket *> *)buckets
             kind:(SGStatsPeriod)kind shown:(NSDateInterval *)shown {
    self.stats = stats;
    self.statsTitle = periodTitle(kind, shown, self.calendar);
    self.statsKind = kind;
    self.statsShown = shown;
    self.hours = hours;
    self.values[@"periodTime"] = SGStatsDuration(stats.ms);
    self.values[@"periodPlays"] = SGStatsCount(stats.plays);
    self.tracksCell.entries = stats.tracks;
    self.artistsCell.entries = stats.artists;
    self.albumsCell.entries = stats.albums;
    NSCalendar *calendar = self.calendar;
    NSDateFormatter *mark = SGStatsDateFormatter(calendar, kind == SGStatsPeriodYear ? @"MMMMM" : kind == SGStatsPeriodMonth ? @"d" : @"EEEEE");
    NSDateFormatter *spoken = SGStatsDateFormatter(calendar, kind == SGStatsPeriodYear ? @"MMMMy" : @"EEEEMMMMd");
    NSMutableArray<NSString *> *labels = [NSMutableArray array], *spokenLabels = [NSMutableArray array], *spokenValues = [NSMutableArray array];
    NSInteger highlighted = -1;
    int64_t now = (int64_t)time(NULL);
    for (NSUInteger i = 0; i < buckets.count; i++) {
        SGStatBucket *bucket = buckets[i];
        NSDate *day = [NSDate dateWithTimeIntervalSince1970:bucket.start];
        [labels addObject:kind != SGStatsPeriodMonth || i % 7 == 0 ? [mark stringFromDate:day] : @""];
        [spokenLabels addObject:[spoken stringFromDate:day]];
        [spokenValues addObject:[@[SGStatsDuration(bucket.ms), SGStatsPlays(bucket.plays)] componentsJoinedByString:@", "]];
        if (bucket.start <= now && now < bucket.end) highlighted = (NSInteger)i;
    }
    [self.chartCell.chart showBuckets:buckets labels:labels spokenLabels:spokenLabels spokenValues:spokenValues highlighted:highlighted];
    [self.tableView reloadData];
}

- (void)showStreaks {
    SGListeningStreaks *streaks = self.streaks;
    SGStatsPairCell *cell = self.streakCell;
    if (!cell) return;
    if (!streaks) {
        NSString *text = self.loading ? SGL(@"settings.stats.status.loading", @"Loading…") : SGL(@"settings.stats.status.unavailable", @"Unavailable");
        [cell.first showValue:text note:nil];
        [cell.second showValue:text note:nil];
        return;
    }
    NSCalendar *calendar = self.calendar;
    NSString *currentNote;
    if (!streaks.current) currentNote = SGL(@"settings.stats.streak.start", @"Listen today to start one");
    else if (![streaks.currentEnd isEqualToDate:[calendar startOfDayForDate:NSDate.date]]) currentNote = SGL(@"settings.stats.streak.keep_going", @"Listen today to keep it going");
    else currentNote = dayRange(streaks.currentStart, streaks.currentEnd, calendar);
    [cell.first showValue:SGStatsDays(streaks.current) note:currentNote];
    [cell.second showValue:SGStatsDays(streaks.best) note:streaks.best ? dayRange(streaks.bestStart, streaks.bestEnd, calendar) : nil];
}

- (void)showSummaryError {
    self.snapshot = nil;
    self.streaks = nil;
    self.stats = nil;
    self.statsShown = nil;
    self.hours = nil;
    self.periodGeneration++;
    NSString *unavailable = SGL(@"settings.stats.status.unavailable", @"Unavailable");
    for (NSString *key in @[@"plays", @"allTime", @"periodTime", @"periodPlays"]) self.values[key] = unavailable;
    self.tracksCell.entries = @[];
    self.artistsCell.entries = @[];
    self.albumsCell.entries = @[];
    [self.chartCell.chart showBuckets:@[] labels:@[] spokenLabels:@[] spokenValues:@[] highlighted:-1];
    [self showStreaks];
    [self updateNavigator];
}

@end

#pragma mark - document picker

@interface SGHistoryPicker : NSObject <UIDocumentPickerDelegate>
@property (nonatomic, weak) SGListeningPage *page;
@property (nonatomic, strong) NSURL *temporaryDirectory;
@end
@implementation SGHistoryPicker
- (void)finishExport {
    NSURL *directory = self.temporaryDirectory;
    self.temporaryDirectory = nil;
    sg_exporting = NO;
    [self.page.tableView reloadData];
    if (directory) dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        [NSFileManager.defaultManager removeItemAtURL:directory error:nil];
    });
}
- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
    sg_picking = NO;
    if (self.temporaryDirectory) {
        [self finishExport];
        UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, SGL(@"common.cancel", @"Cancel"));
    }
}
- (void)documentPicker:(UIDocumentPickerViewController *)picker didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    sg_picking = NO;
    if (self.temporaryDirectory) {
        [self finishExport];
        UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, SGL(@"settings.stats.a11y.exported", @"History exported"));
        return;
    }
    SGListeningPage *page = self.page;
    sg_importing = YES;
    [page.tableView reloadData];
    UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, SGL(@"settings.stats.a11y.importing", @"Importing"));
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        SGHistoryImport *result = SGReadHistoryURLs(urls);
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!result.files) {
                sg_importing = NO;
                [page.tableView reloadData];
                showAlert(SGL(@"settings.stats.alert.no_history_found.title", @"No listening history found"), SGL(@"settings.stats.alert.no_history_found.message", @"Choose a Retrine history export, Spotify StreamingHistory_music or Streaming_History_Audio JSON files, their ZIP, or a folder containing JSON files. Unreadable, unsupported or oversized files are skipped."));
                return;
            }
            [SGListeningLog() merge:result.plays completion:^(NSUInteger added, NSError *error) {
                sg_importing = NO;
                [page.tableView reloadData];
                if (error) {
                    showAlert(SGL(@"settings.stats.error.load", @"Could not load history"), error.localizedDescription);
                    return;
                }
                showAlert(SGL(@"settings.stats.alert.imported.title", @"Imported"), [NSString stringWithFormat:SGL(@"settings.stats.alert.imported.message", @"%@ added from %lu files. %lu duplicate plays and %lu unreadable, unsupported or over-limit items skipped."),
                    SGStatsPlays(added), (unsigned long)result.files, (unsigned long)(result.plays.count - added), (unsigned long)result.skipped]);
            }];
        });
    });
}
@end
static SGHistoryPicker *historyPicker(void) {
    static SGHistoryPicker *delegate;
    if (!delegate) delegate = [SGHistoryPicker new];
    return delegate;
}
static BOOL busy(SGListeningPage *page) {
    return !page || sg_importing || sg_exporting || sg_picking || page.loading || !SGListeningLog() || SGListeningLog().loadError;
}
static void pickExport(SGListeningPage *page, BOOL folder) {
    if (busy(page)) return;
    sg_picking = YES;
    SGHistoryPicker *delegate = historyPicker();
    delegate.page = page;
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc]
        initForOpeningContentTypes:folder ? @[UTTypeFolder] : @[UTTypeJSON, UTTypeZIP] asCopy:NO];
    picker.allowsMultipleSelection = YES;
    picker.delegate = delegate;
    present(picker);
}
static void exportHistory(SGListeningPage *page) {
    if (busy(page)) return;
    NSArray *snapshot = [SGListeningLog().plays copy];
    if (!snapshot.count) { showAlert(SGL(@"settings.stats.alert.no_history_export.title", @"No history to export"), SGL(@"settings.stats.alert.no_history_export.message", @"Record or import some plays first.")); return; }
    sg_exporting = YES;
    [page.tableView reloadData];
    UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, SGL(@"settings.stats.a11y.preparing_export", @"Preparing export"));
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSError *error;
        NSData *data = SGHistoryJSON(snapshot, &error);
        NSURL *directory = [[NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES] URLByAppendingPathComponent:NSUUID.UUID.UUIDString isDirectory:YES];
        NSURL *url = [directory URLByAppendingPathComponent:@"Retrine-listening-history.json"];
        BOOL saved = data && [NSFileManager.defaultManager createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:nil error:&error]
                          && [data writeToURL:url options:NSDataWritingAtomic error:&error];
        if (!saved) [NSFileManager.defaultManager removeItemAtURL:directory error:nil];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!saved) {
                sg_exporting = NO;
                [page.tableView reloadData];
                showAlert(SGL(@"settings.stats.alert.export_failed.title", @"Could not export history"), error.localizedDescription ?: SGL(@"settings.stats.error.try_again", @"Please try again."));
                return;
            }
            SGHistoryPicker *delegate = historyPicker();
            delegate.page = page;
            delegate.temporaryDirectory = directory;
            UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForExportingURLs:@[url] asCopy:YES];
            picker.delegate = delegate;
            present(picker);
        });
    });
}
static void confirmErase(SGListeningPage *page) {
    // Erase is also the recovery path for a damaged log, so loading and load errors must not disable it.
    if (!page || sg_importing || sg_exporting || sg_picking) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:SGL(@"settings.stats.alert.erase.title", @"Erase listening history?")
        message:SGL(@"settings.stats.alert.erase.message", @"Every play recorded on this phone and every one imported is deleted. Spotify's own history is untouched.")
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:SGL(@"settings.stats.alert.erase.action", @"Erase") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        [SGListeningLog() erase];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:SGL(@"common.cancel", @"Cancel") style:UIAlertActionStyleCancel handler:nil]];
    present(alert);
}

#pragma mark - summary

UIViewController *SGListeningStatsPage(void) {
    NSMutableDictionary<NSString *, NSString *> *values = [NSMutableDictionary dictionary];
    __block __weak SGListeningPage *weakPage;
    NSString *(^read)(NSString *) = ^NSString *(NSString *key) {
        return values[key] ?: SGL(@"settings.stats.status.loading", @"Loading…");
    };

    // The shown period: its card, chart, totals and hours.
    SGModRow *streak = [SGModRow new], *period = [SGModRow new], *chart = [SGModRow new];
    SGModRow *periodTime = SGStatRow(SGL(@"settings.stats.row.listening_time", @"Listening time"), ^NSString *{ return read(@"periodTime"); });
    SGModRow *periodPlays = SGStatRow(SGL(@"settings.stats.row.plays", @"Plays"), ^NSString *{ return read(@"periodPlays"); });
    SGModRow *byHour = SGPageRow(SGL(@"settings.stats.row.by_hour", @"By hour of day"), ^UIViewController *{
        return hoursPage(weakPage.hours ?: SGHourlyStats(@[], 0, NSCalendar.currentCalendar));
    });

    // Its tops: five on a card, then See all for the rest of the 25.
    NSArray<NSString *> *topTitles = @[SGL(@"settings.stats.section.top_tracks", @"Top tracks"), SGL(@"settings.stats.section.top_artists", @"Top artists"),
                                       SGL(@"settings.stats.section.top_albums", @"Top albums")];
    NSMutableArray<SGModRow *> *lists = [NSMutableArray array];
    NSMutableArray<SGModSection *> *tops = [NSMutableArray array];
    for (NSUInteger i = 0; i < topTitles.count; i++) {
        NSString *title = topTitles[i];
        NSArray<SGStatEntry *> *(^entries)(void) = ^NSArray<SGStatEntry *> *{
            SGStats *stats = weakPage.stats;
            return i == 0 ? stats.tracks : i == 1 ? stats.artists : stats.albums;
        };
        SGModRow *list = [SGModRow new];
        SGModRow *all = SGPageRow(SGL(@"settings.stats.see_all", @"See all"), ^UIViewController *{
            return [[SGModPage alloc] initWithTitle:title intro:nil sections:@[topSection(weakPage.statsTitle, entries() ?: @[])] footer:nil];
        });
        all.visible = ^BOOL { return entries().count > 5; };
        [lists addObject:list];
        [tops addObject:SGSection(title, @[list, all])];
    }

    NSString *recapSubtitle = SGL(@"settings.stats.recap.subtitle", @"A year of listening, card by card");
    SGModRow *recap = SGPageRow(SGL(@"settings.stats.recap.title", @"Recap"), nil);
    recap.page = ^UIViewController *{ return SGRecapYearsPage(^{ pickExport(weakPage, NO); }); };
    recap.subtitle = recapSubtitle;

    NSString *allTimeTitle = SGL(@"settings.stats.period.all_time", @"All time");
    SGModRow *allTime = SGPageRow(allTimeTitle, ^UIViewController *{ return periodPage(allTimeTitle, 0); });
    allTime.value = ^NSString *{ return read(@"allTime"); };
    SGModRow *import = SGWithSymbol(SGStatActionRow(SGL(@"settings.stats.action.import", @"Import history"), SGL(@"settings.stats.action.import.subtitle", @"Retrine JSON or Spotify JSON/ZIP"),
        ^NSString *{ return sg_importing ? SGL(@"settings.stats.status.importing", @"Importing…") : nil; }, nil), @"square.and.arrow.down");
    SGModRow *folder = SGActionRow(SGL(@"settings.stats.action.import_folder", @"Import a folder"), SGL(@"settings.stats.action.import_folder.subtitle", @"JSON files in the selected folder and its subfolders"), nil);
    SGModRow *export = SGWithSymbol(SGStatActionRow(SGL(@"settings.stats.action.export", @"Export history"), SGL(@"settings.stats.action.export.subtitle", @"Retrine JSON, ready to import again"),
        ^NSString *{ return sg_exporting ? SGL(@"settings.stats.status.exporting", @"Exporting…") : nil; }, nil), @"square.and.arrow.up");
    SGModRow *erase = SGWithSymbol(SGActionRow(SGL(@"settings.stats.action.erase", @"Erase listening history"), nil, nil), @"trash");
    erase.color = SGRed();
    SGListeningPage *page = [[SGListeningPage alloc] initWithTitle:SGL(@"settings.stats.page.title", @"Listening stats") intro:nil sections:@[
        SGSection(nil, @[streak]),
        SGSection(nil, @[period, chart, periodTime, periodPlays, byHour]),
        tops[0], tops[1], tops[2],
        SGSection(nil, @[recap]),
        SGNotedSection(nil, @[
            allTime,
            SGStatRow(SGL(@"settings.stats.row.plays", @"Plays"), ^NSString *{ return read(@"plays"); }),
            SGStatRow(SGL(@"settings.stats.row.history", @"History"), ^NSString *{ return read(@"status"); }),
        ], SGL(@"settings.stats.section.history.footer", @"Streaks use local calendar days when plays ended. A current streak can end yesterday until you listen today. Import Spotify's account or extended streaming history, or Retrine's own versioned history export. Duplicate plays are skipped. Large selections may need to be imported in smaller batches.")),
        SGNotedSection(nil, @[SGSwitchRow(SGL(@"settings.stats.record.title", @"Record plays"), nil, SGKeyListeningStats)],
            SGL(@"settings.stats.record.footer", @"A play counts once it has run 30 seconds, or half of a shorter track. History stays on this phone unless you export it.")),
        SGSection(nil, @[import, folder, export]),
        SGSection(nil, @[erase]),
    ] footer:nil];
    weakPage = page;
    page.values = values;
    page.streakRow = streak;
    page.periodRow = period;
    page.chartRow = chart;
    page.tracksRow = lists[0];
    page.artistsRow = lists[1];
    page.albumsRow = lists[2];
    page.topSections = tops;
    page.recapRow = recap;
    page.earliest = INT64_MAX;
    page.calendar = NSCalendar.currentCalendar;
    page.kind = SGStatsPeriodWeek;
    page.shown = SGPeriodInterval(SGStatsPeriodWeek, NSDate.date, page.calendar);
    page.loading = YES;
    page.refreshHistory = ^{
        SGListeningPage *page = weakPage;
        if (!page) return;
        NSUInteger generation = ++page.generation;
        page.loading = YES;
        values[@"status"] = SGL(@"settings.stats.status.loading", @"Loading…");
        if (!SGListeningLog()) {
            page.loading = NO;
            [page showSummaryError];
            values[@"status"] = SGL(@"settings.stats.status.error_retry", @"Could not load history. Reopen to retry.");
            [page.tableView reloadData];
            return;
        }
        [SGListeningLog() loadWithCompletion:^{
            SGListeningPage *page = weakPage;
            if (!page || page.generation != generation) return;
            if (SGListeningLog().loadError) {
                page.loading = NO;
                [page showSummaryError];
                values[@"status"] = SGL(@"settings.stats.status.error_retry", @"Could not load history. Reopen to retry.");
                [page.tableView reloadData];
                UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, values[@"status"]);
                return;
            }
            NSArray *snapshot = [SGListeningLog().plays copy];
            NSDate *now = NSDate.date;
            NSCalendar *calendar = [NSCalendar.currentCalendar copy];
            // The time zone or first weekday may have changed since the period was picked: the same period
            // again, read in the calendar as it is now.
            NSDate *middle = [page.shown.startDate dateByAddingTimeInterval:page.shown.duration / 2];
            page.calendar = calendar;
            page.shown = SGPeriodInterval(page.kind, middle && [middle compare:now] == NSOrderedAscending ? middle : now, calendar);
            page.snapshot = snapshot;
            [page showPeriod];
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
                SGListeningStreaks *streaks = SGStreaks(snapshot, now, calendar);
                int64_t ms = 0, earliest = INT64_MAX;
                for (SGPlay *play in snapshot) {
                    ms += play.ms;
                    // As in SGStreaks, a damaged row's time outside NSDate's years is not a period to step to.
                    if (play.end >= -62135596800LL && play.end <= 253402300799LL) earliest = MIN(earliest, play.end);
                }
                NSDictionary *summary = @{@"allTime": SGStatsDuration(ms), @"plays": SGStatsCount(snapshot.count),
                    @"status": snapshot.count ? SGL(@"settings.stats.status.on_phone", @"On this phone") : SGL(@"settings.stats.status.no_plays", @"No plays yet")};
                NSArray<SGRecapYear *> *years = SGRecapYears(snapshot, calendar);
                dispatch_async(dispatch_get_main_queue(), ^{
                    SGListeningPage *page = weakPage;
                    if (!page || page.generation != generation) return;
                    [values addEntriesFromDictionary:summary];
                    // The year just ended, pointed out with the New mark until the row is opened.
                    SGRecapYear *due = SGRecapDueYear(years, now, calendar);
                    NSString *dueTitle = due ? SGRecapYearTitle(due.interval, calendar) : nil;
                    page.recapRow.subtitle = due ? [NSString stringWithFormat:SGL(@"settings.stats.recap.ready", @"Your %@ Recap is ready"), dueTitle] : recapSubtitle;
                    page.recapRow.markedNewAs = due ? [@"stats.recap." stringByAppendingString:dueTitle] : nil;
                    page.streaks = streaks;
                    page.earliest = earliest;
                    page.loading = NO;
                    [page showStreaks];
                    [page updateNavigator];
                    [page.tableView reloadData];
                });
            });
        }];
    };
    import.action = ^{ pickExport(weakPage, NO); };
    folder.action = ^{ pickExport(weakPage, YES); };
    export.action = ^{ exportHistory(weakPage); };
    erase.action = ^{ confirmErase(weakPage); };
    return page;
}
