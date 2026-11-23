// The year's recap (SGRecap.h) told as a story of full-screen cards: Listening stats > Recap lists the years with
// plays, and a year with enough active days opens its story. Tap the right of a card for the next and the left for
// the one before, hold to pause, swipe down or close to leave; a card moves on by itself after kRecapCardSeconds
// unless VoiceOver runs. Reduce Motion cross-fades the cards. Share draws the card shown, alone, at 9:16.
//
// From 1 January, for SGRecapAnnouncementDays days, the year just ended is announced once if it has a recap: by
// the Recap row (In Retrine Settings, the default) or by one prompt after launch (When Spotify opens).
// Recaps are added up off main from the log's snapshot and kept for their year and the log's state.
#import <QuartzCore/QuartzCore.h>
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Settings/SGPageStyle.h"
#import "ListeningStats.h"
#import "ListeningStatsStyle.h"
#import "SGRecap.h"

static const NSTimeInterval kRecapCardSeconds = 6;
// The share image's shape, and the drag down that closes the story.
static const CGFloat kShareAspect = 16.0 / 9.0, kDismissDistance = 120, kDismissVelocity = 800;

static dispatch_queue_t recapQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ queue = dispatch_queue_create("retrine.stats.recap", dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_USER_INITIATED, 0)); });
    return queue;
}

// On screen with nothing over it and not on its way out: where a request started can still be answered.
static BOOL canPresentFrom(UIViewController *controller) {
    return controller.viewIfLoaded.window && !controller.isBeingDismissed && !controller.presentedViewController;
}

static void removeShareDirectory(NSURL *directory) {
    if (directory) dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{ [NSFileManager.defaultManager removeItemAtURL:directory error:nil]; });
}

#pragma mark - announcement state

static SGRecapAnnouncement announcement(void) {
    return SGRecapAnnouncementFrom(SGInt(SGKeyRecapAnnouncement, SGRecapAnnounceInSettings));
}

static NSInteger announcedYear(void) {
    return SGInt(SGKeyRecapAnnouncedYear, 0);
}

static void markAnnounced(NSDateInterval *year, NSCalendar *calendar) {
    SGSetInt(SGKeyRecapAnnouncedYear, MAX(announcedYear(), SGRecapYearNumber(year, calendar)));
}

SGRecapYear *SGRecapDueYear(NSArray<SGRecapYear *> *years, NSDate *now, NSCalendar *calendar) {
    NSDateInterval *ended = SGRecapUnannouncedYear(now, calendar, announcement(), announcedYear());
    if (!ended) return nil;
    for (SGRecapYear *year in years) if ([year.interval isEqualToDateInterval:ended]) return year.eligible ? year : nil;
    return nil;
}

#pragma mark - building

// Recaps already added up, by year and the log's state.
static NSCache<NSString *, SGRecap *> *recapCache(void) {
    static NSCache *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cache = [NSCache new]; cache.countLimit = 8; });
    return cache;
}

// The recap of the year holding `date`, from the loaded log; nil after a load error. Main queue in and out.
static void buildRecap(NSDate *date, void (^done)(SGRecap *recap, NSError *error)) {
    SGPlayLog *log = SGListeningLog();
    [log loadWithCompletion:^{
        if (log.loadError) { done(nil, log.loadError); return; }
        NSArray<SGPlay *> *snapshot = log.plays;
        NSCalendar *calendar = [NSCalendar.currentCalendar copy];
        NSString *key = SGStatsCacheKey(SGPeriodInterval(SGStatsPeriodYear, date, calendar), calendar, log.playsGeneration, snapshot.count);
        SGRecap *cached = [recapCache() objectForKey:key];
        if (cached) { done(cached, nil); return; }
        NSDate *now = NSDate.date;
        dispatch_async(recapQueue(), ^{
            SGRecap *recap = SGRecapBuild(snapshot, date, now, calendar);
            if (recap) [recapCache() setObject:recap forKey:key];
            dispatch_async(dispatch_get_main_queue(), ^{ done(recap, nil); });
        });
    }];
}

#pragma mark - a card

// Spotify's typeface, bold or regular, at `size` for the default text size; grown with Dynamic Type up to
// `largest`, or held at `size` for the share image, which is a picture rather than text.
static UIFont *cardFont(CGFloat size, CGFloat largest, BOOL bold, BOOL fixed) {
    if (bold && !fixed) return SGStatsStrongFont(size, largest);
    UIFont *title = SGTitleFont();
    UIFont *font = [title fontWithSize:fixed ? size : MIN(largest, title.pointSize * size / 13)];
    UIFontDescriptor *heavy = bold ? [font.fontDescriptor fontDescriptorWithSymbolicTraits:UIFontDescriptorTraitBold] : nil;
    return heavy ? [UIFont fontWithDescriptor:heavy size:font.pointSize] : bold ? [UIFont systemFontOfSize:font.pointSize weight:UIFontWeightBold] : font;
}

static UIColor *cardTint(NSUInteger index) {
    CGFloat hue = 0, saturation = 0, brightness = 0, alpha = 1;
    [SGGreen() getHue:&hue saturation:&saturation brightness:&brightness alpha:&alpha];
    // Each card a step around the color wheel from the accent, dark enough for white text.
    hue = fmod(hue + 0.07 * index, 1);
    return [UIColor colorWithHue:hue saturation:MIN(saturation, 0.8) brightness:MIN(brightness, 0.62) alpha:1];
}

// One card of a recap: a gradient from a tint of the accent, a large faint symbol, and its words over the lower
// part. In the story it sits under the progress and buttons (its top margin); for sharing, alone at 9:16.
@interface SGRecapCardView : UIView
- (instancetype)initWithRecap:(SGRecap *)recap card:(SGRecapCard)card index:(NSUInteger)index forImage:(BOOL)forImage;
@property (nonatomic, readonly) UIScrollView *scroll;
@property (nonatomic, readonly) UIView *firstElement;
- (void)arrive:(BOOL)animated;
@end

@implementation SGRecapCardView {
    CAGradientLayer *_wash, *_glow;
    UIImageView *_mark;
    UIStackView *_stack;
    UILabel *_kicker, *_headline;
    BOOL _forImage;
}

- (UILabel *)label:(UIFont *)font color:(UIColor *)color lines:(NSInteger)lines {
    UILabel *label = [UILabel new];
    label.font = font;
    label.textColor = color;
    label.numberOfLines = lines;
    return label;
}

- (instancetype)initWithRecap:(SGRecap *)recap card:(SGRecapCard)card index:(NSUInteger)index forImage:(BOOL)forImage {
    if (!(self = [super initWithFrame:CGRectZero])) return nil;
    _forImage = forImage;
    self.backgroundColor = UIColor.blackColor;
    self.clipsToBounds = YES;
    UIColor *tint = cardTint(index);
    _wash = [CAGradientLayer layer];
    _wash.colors = @[(id)tint.CGColor, (id)[tint colorWithAlphaComponent:0.35].CGColor, (id)[UIColor colorWithWhite:0.04 alpha:1].CGColor];
    _wash.locations = @[@0, @0.45, @1];
    _wash.startPoint = CGPointMake(0.2, 0);
    _wash.endPoint = CGPointMake(0.8, 1);
    [self.layer addSublayer:_wash];
    _glow = [CAGradientLayer layer];
    _glow.type = kCAGradientLayerRadial;
    _glow.colors = @[(id)[cardTint(index + 3) colorWithAlphaComponent:0.7].CGColor, (id)[cardTint(index + 3) colorWithAlphaComponent:0].CGColor];
    _glow.startPoint = CGPointMake(0.5, 0.5);
    _glow.endPoint = CGPointMake(1, 1);
    [self.layer addSublayer:_glow];

    NSArray<NSString *> *symbols = @[@"clock.fill", @"music.mic", @"music.note", @"square.stack.fill", @"sparkles", @"calendar", @"sun.max.fill"];
    _mark = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:symbols[(NSUInteger)card]
        withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:240 weight:UIImageSymbolWeightBold]]];
    _mark.tintColor = [UIColor colorWithWhite:1 alpha:0.09];
    _mark.contentMode = UIViewContentModeScaleAspectFit;
    _mark.isAccessibilityElement = NO;
    [self addSubview:_mark];

    _scroll = [UIScrollView new];
    _scroll.showsVerticalScrollIndicator = NO;
    _scroll.alwaysBounceVertical = NO;
    _scroll.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    [self addSubview:_scroll];
    _stack = [UIStackView new];
    _stack.axis = UILayoutConstraintAxisVertical;
    _stack.alignment = UIStackViewAlignmentFill;
    _stack.spacing = 8;
    [_scroll addSubview:_stack];
    [self fill:recap card:card];
    _firstElement = _kicker;
    return self;
}

- (void)fill:(SGRecap *)recap card:(SGRecapCard)card {
    BOOL fixed = _forImage;
    UIColor *soft = [UIColor colorWithWhite:1 alpha:0.75];
    NSCalendar *calendar = NSCalendar.currentCalendar;
    NSString *year = SGRecapYearTitle(recap.year, calendar);
    NSArray<NSString *> *kickers = @[SGL(@"settings.stats.recap.card.total", @"Listening time"), SGL(@"settings.stats.recap.card.artist", @"Top artist"),
                                     SGL(@"settings.stats.recap.card.song", @"Top song"), SGL(@"settings.stats.recap.card.album", @"Top album"),
                                     SGL(@"settings.stats.recap.card.discoveries", @"Discoveries"), SGL(@"settings.stats.recap.card.days", @"Active days"),
                                     SGL(@"settings.stats.recap.card.peak", @"Peak listening")];
    _kicker = [self label:cardFont(12, 22, YES, fixed) color:soft lines:0];
    _kicker.attributedText = [[NSAttributedString alloc] initWithString:[NSString stringWithFormat:SGL(@"settings.stats.recap.kicker", @"%@ · %@"), year, kickers[(NSUInteger)card]].uppercaseString
        attributes:@{NSKernAttributeName: @1.2}];
    _kicker.accessibilityTraits = UIAccessibilityTraitHeader;
    _headline = [self label:cardFont(44, 76, YES, fixed) color:UIColor.whiteColor lines:3];
    _headline.adjustsFontSizeToFitWidth = YES;
    _headline.minimumScaleFactor = 0.45;
    UILabel *line = [self label:cardFont(19, 34, NO, fixed) color:UIColor.whiteColor lines:0];
    UILabel *note = [self label:cardFont(15, 28, NO, fixed) color:soft lines:0];
    NSArray<SGChartEntry *> *list;

    switch (card) {
        case SGRecapCardTotal:
            _headline.text = SGStatsDuration(recap.ms);
            line.text = [NSString stringWithFormat:SGL(@"settings.stats.recap.total.line", @"of music, over %@"), SGStatsPlays(recap.plays)];
            note.text = [NSString stringWithFormat:SGL(@"settings.stats.recap.total.note", @"About %@ on each day you listened."),
                         SGStatsDuration(recap.ms / (int64_t)MAX((NSUInteger)1, recap.activeDays))];
            break;
        case SGRecapCardArtists:
        case SGRecapCardSongs:
        case SGRecapCardAlbums: {
            list = card == SGRecapCardArtists ? recap.artists : card == SGRecapCardSongs ? recap.songs : recap.albums;
            SGChartEntry *top = list.firstObject;
            _headline.text = top.name;
            line.text = top.detail.length ? [NSString stringWithFormat:SGL(@"settings.stats.recap.top.line_by", @"%@ · %@"), top.detail, SGStatsPlays(top.plays)]
                                          : [NSString stringWithFormat:SGL(@"settings.stats.recap.top.line", @"%@ · %@"), SGStatsPlays(top.plays), SGStatsDuration(top.ms)];
            break;
        }
        case SGRecapCardDiscoveries:
            _headline.text = [NSString stringWithFormat:recap.newArtists == 1 ? SGL(@"settings.stats.recap.discoveries.artists.singular", @"%@ new artist")
                                                                              : SGL(@"settings.stats.recap.discoveries.artists.plural", @"%@ new artists"), SGStatsCount(recap.newArtists)];
            line.text = [NSString stringWithFormat:recap.newSongs == 1 ? SGL(@"settings.stats.recap.discoveries.songs.singular", @"and %@ new song, first played this year")
                                                                       : SGL(@"settings.stats.recap.discoveries.songs.plural", @"and %@ new songs, first played this year"), SGStatsCount(recap.newSongs)];
            if (recap.topNewArtist) note.text = [NSString stringWithFormat:SGL(@"settings.stats.recap.discoveries.top", @"Your top discovery: %@, with %@."),
                                                 recap.topNewArtist.name, SGStatsPlays(recap.topNewArtist.plays)];
            break;
        case SGRecapCardDays: {
            _headline.text = SGStatsDays(recap.activeDays);
            line.text = SGL(@"settings.stats.recap.days.line", @"with music in them");
            if (recap.longestStreak > 1) {
                NSDateIntervalFormatter *range = [NSDateIntervalFormatter new];
                range.calendar = calendar;
                range.timeZone = calendar.timeZone;
                range.dateTemplate = @"MMMMd";
                note.text = [NSString stringWithFormat:SGL(@"settings.stats.recap.days.streak", @"Longest streak: %@ in a row, %@."),
                             SGStatsDays(recap.longestStreak), [range stringFromDate:recap.streakStart toDate:recap.streakEnd]];
            }
            break;
        }
        case SGRecapCardPeak: {
            NSDateFormatter *hour = [NSDateFormatter new];
            hour.locale = NSLocale.currentLocale;
            // A non-DST day in UTC supplies every wall-clock hour; the locale picks 12 or 24 h.
            hour.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
            [hour setLocalizedDateFormatFromTemplate:@"j"];
            _headline.text = [hour stringFromDate:[NSDate dateWithTimeIntervalSince1970:recap.peakHour * 3600]];
            line.text = SGL(@"settings.stats.recap.peak.line", @"was your hour for music");
            note.text = [NSString stringWithFormat:SGL(@"settings.stats.recap.peak.month", @"%@ was your month, with %@."),
                         [SGStatsDateFormatter(calendar, @"MMMM") stringFromDate:recap.peakMonth], SGStatsDuration(recap.peakMonthMs)];
            break;
        }
    }
    [_stack addArrangedSubview:_kicker];
    [_stack addArrangedSubview:_headline];
    [_stack setCustomSpacing:4 afterView:_headline];
    [_stack addArrangedSubview:line];
    if (note.text.length) {
        [_stack setCustomSpacing:14 afterView:line];
        [_stack addArrangedSubview:note];
    }
    if (list.count > 1) {
        [_stack setCustomSpacing:22 afterView:_stack.arrangedSubviews.lastObject];
        [_stack addArrangedSubview:[self listOf:list fixed:fixed]];
    }
}

// The top five as numbered lines, the first already named above.
- (UIView *)listOf:(NSArray<SGChartEntry *> *)entries fixed:(BOOL)fixed {
    UIStackView *list = [UIStackView new];
    list.axis = UILayoutConstraintAxisVertical;
    list.spacing = 10;
    BOOL stacked = !fixed && SGAccessibilityTextSize();
    UIFont *rankFont = SGMonospacedDigitsFont(cardFont(15, 28, YES, fixed));
    CGFloat rankWidth = ceil([SGStatsCount(SGRecapTopLength) sizeWithAttributes:@{NSFontAttributeName: rankFont}].width) + 4;
    for (SGChartEntry *entry in entries) {
        UILabel *rank = [self label:rankFont color:[UIColor colorWithWhite:1 alpha:0.6] lines:1];
        rank.text = SGStatsCount(entry.rank);
        [rank.widthAnchor constraintEqualToConstant:rankWidth].active = YES;
        UILabel *name = [self label:cardFont(15, 28, YES, fixed) color:UIColor.whiteColor lines:2];
        name.text = entry.name;
        UILabel *detail = [self label:cardFont(13, 24, NO, fixed) color:[UIColor colorWithWhite:1 alpha:0.7] lines:1];
        detail.text = entry.detail.length ? [NSString stringWithFormat:SGL(@"settings.stats.recap.top.line_by", @"%@ · %@"), entry.detail, SGStatsPlays(entry.plays)]
                                          : SGStatsPlays(entry.plays);
        UIStackView *texts = [[UIStackView alloc] initWithArrangedSubviews:@[name, detail]];
        texts.axis = UILayoutConstraintAxisVertical;
        texts.spacing = 1;
        UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[rank, texts]];
        row.spacing = 10;
        row.alignment = stacked ? UIStackViewAlignmentTop : UIStackViewAlignmentCenter;
        row.isAccessibilityElement = YES;
        row.accessibilityLabel = [NSString stringWithFormat:SGL(@"settings.stats.chart.a11y.rank", @"Number %lu"), (unsigned long)entry.rank];
        row.accessibilityValue = [@[entry.name ?: @"", detail.text] componentsJoinedByString:@", "];
        [list addArrangedSubview:row];
    }
    return list;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect bounds = self.bounds;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _wash.frame = bounds;
    CGFloat glow = bounds.size.width * 1.3;
    _glow.frame = CGRectMake(bounds.size.width - glow * 0.6, -glow * 0.35, glow, glow);
    [CATransaction commit];
    CGFloat side = bounds.size.width * 0.62;
    _mark.frame = CGRectMake(bounds.size.width - side * 0.82, bounds.size.height * 0.16, side, side);
    UIEdgeInsets margins = self.layoutMargins;
    _scroll.frame = UIEdgeInsetsInsetRect(bounds, UIEdgeInsetsMake(margins.top, 0, 0, 0));
    CGFloat width = bounds.size.width - margins.left - margins.right;
    CGSize size = [_stack systemLayoutSizeFittingSize:CGSizeMake(width, UILayoutFittingCompressedSize.height)
                        withHorizontalFittingPriority:UILayoutPriorityRequired verticalFittingPriority:UILayoutPriorityFittingSizeLevel];
    CGFloat available = _scroll.bounds.size.height - margins.bottom;
    // The words sit on the card's lower part, and scroll from the top when the text size makes them longer.
    CGFloat top = MAX(0, available - size.height);
    _stack.frame = CGRectMake(margins.left, top, width, size.height);
    _scroll.contentSize = CGSizeMake(bounds.size.width, top + size.height + margins.bottom);
    _scroll.scrollEnabled = size.height > available;
}

// The words rise into place as the card arrives, unless Reduce Motion is on.
- (void)arrive:(BOOL)animated {
    if (!animated || UIAccessibilityIsReduceMotionEnabled()) return;
    _stack.alpha = 0;
    _stack.transform = CGAffineTransformMakeTranslation(0, 24);
    [UIView animateWithDuration:0.55 delay:0.05 usingSpringWithDamping:0.9 initialSpringVelocity:0 options:UIViewAnimationOptionAllowUserInteraction animations:^{
        self->_stack.alpha = 1;
        self->_stack.transform = CGAffineTransformIdentity;
    } completion:nil];
}

@end

#pragma mark - the story

// One bar of the progress strip, filled to its card's share of the time.
@interface SGStorySegment : UIView
@property (nonatomic) CGFloat progress;
@end
@implementation SGStorySegment {
    UIView *_fill;
}
- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.backgroundColor = [UIColor colorWithWhite:1 alpha:0.3];
    self.layer.cornerRadius = 1.5;
    self.clipsToBounds = YES;
    _fill = [UIView new];
    _fill.backgroundColor = UIColor.whiteColor;
    [self addSubview:_fill];
    return self;
}
- (void)setProgress:(CGFloat)progress {
    if (progress == _progress) return;
    _progress = progress;
    [self setNeedsLayout];
}
- (void)layoutSubviews {
    [super layoutSubviews];
    _fill.frame = CGRectMake(0, 0, round(self.bounds.size.width * _progress * self.traitCollection.displayScale) / MAX(1, self.traitCollection.displayScale), self.bounds.size.height);
}
@end

@class SGRecapStoryController;
// The strip of bars, which VoiceOver reads as the card's place and moves through by swiping up and down.
@interface SGStoryProgress : UIStackView
@property (nonatomic, weak) SGRecapStoryController *story;
@end

@interface SGRecapStoryController : UIViewController <UIGestureRecognizerDelegate>
- (instancetype)initWithRecap:(SGRecap *)recap;
- (void)step:(NSInteger)delta;
- (void)tick:(CADisplayLink *)link;
@property (nonatomic, readonly) NSUInteger index, count;
@end

@implementation SGStoryProgress
- (BOOL)isAccessibilityElement { return YES; }
- (UIAccessibilityTraits)accessibilityTraits { return UIAccessibilityTraitAdjustable; }
- (NSString *)accessibilityLabel { return SGL(@"settings.stats.recap.a11y.card", @"Recap card"); }
- (NSString *)accessibilityValue {
    return [NSString stringWithFormat:SGL(@"settings.stats.recap.a11y.position", @"%lu of %lu"), (unsigned long)self.story.index + 1, (unsigned long)self.story.count];
}
- (void)accessibilityIncrement { [self.story step:1]; }
- (void)accessibilityDecrement { [self.story step:-1]; }
@end

// Holds the story weakly for its display link, which retains its target.
@interface SGStoryTicker : NSObject
@property (nonatomic, weak) SGRecapStoryController *story;
@end

@implementation SGRecapStoryController {
    SGRecap *_recap;
    NSArray<NSNumber *> *_cards;
    UIView *_host;
    SGRecapCardView *_card;
    SGStoryProgress *_strip;
    NSArray<SGStorySegment *> *_segments;
    UILabel *_title;
    UIButton *_close, *_share;
    UIPanGestureRecognizer *_dismissPan;
    CADisplayLink *_link;
    CFTimeInterval _last;
    NSTimeInterval _elapsed;
    BOOL _holding, _dragging, _sharing, _visible, _inactive;
    NSURL *_shareDirectory;   // the picture the share sheet holds, removed when the sheet or the story goes
}

- (instancetype)initWithRecap:(SGRecap *)recap {
    if (!(self = [super initWithNibName:nil bundle:nil])) return nil;
    _recap = recap;
    _cards = recap.cards;
    self.modalPresentationStyle = UIModalPresentationOverFullScreen;
    self.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
    self.modalPresentationCapturesStatusBarAppearance = YES;
    return self;
}

- (NSUInteger)count { return _cards.count; }
- (BOOL)prefersStatusBarHidden { return YES; }

static UIButton *storyButton(NSString *symbol, NSString *label) {
    UIButtonConfiguration *look = [UIButtonConfiguration filledButtonConfiguration];
    look.image = [UIImage systemImageNamed:symbol withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:15 weight:UIImageSymbolWeightSemibold]];
    look.baseBackgroundColor = [UIColor colorWithWhite:0 alpha:0.3];
    look.baseForegroundColor = UIColor.whiteColor;
    look.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
    UIButton *button = [UIButton buttonWithConfiguration:look primaryAction:nil];
    button.accessibilityLabel = label;
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[[button.widthAnchor constraintEqualToConstant:40], [button.heightAnchor constraintEqualToConstant:40]]];
    return button;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    UIView *view = self.view;
    view.backgroundColor = UIColor.blackColor;
    view.accessibilityViewIsModal = YES;
    _host = [[UIView alloc] initWithFrame:view.bounds];
    _host.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [view addSubview:_host];

    NSMutableArray<SGStorySegment *> *segments = [NSMutableArray array];
    for (NSUInteger i = 0; i < _cards.count; i++) {
        SGStorySegment *segment = [SGStorySegment new];
        [segment.heightAnchor constraintEqualToConstant:3].active = YES;
        [segments addObject:segment];
    }
    _segments = segments;
    _strip = [[SGStoryProgress alloc] initWithArrangedSubviews:segments];
    _strip.story = self;
    _strip.spacing = 4;
    _strip.distribution = UIStackViewDistributionFillEqually;
    _strip.translatesAutoresizingMaskIntoConstraints = NO;
    [view addSubview:_strip];

    _title = [UILabel new];
    _title.textColor = UIColor.whiteColor;
    _title.text = [NSString stringWithFormat:SGL(@"settings.stats.recap.story.title", @"Your %@ Recap"), SGRecapYearTitle(_recap.year, NSCalendar.currentCalendar)];
    _title.accessibilityTraits = UIAccessibilityTraitHeader;
    _title.translatesAutoresizingMaskIntoConstraints = NO;
    _title.adjustsFontSizeToFitWidth = YES;
    _title.minimumScaleFactor = 0.6;
    [view addSubview:_title];
    _share = storyButton(@"square.and.arrow.up", SGL(@"settings.stats.recap.a11y.share", @"Share card"));
    [_share addTarget:self action:@selector(shareCard) forControlEvents:UIControlEventTouchUpInside];
    _close = storyButton(@"xmark", SGL(@"settings.stats.recap.a11y.close", @"Close"));
    [_close addTarget:self action:@selector(close) forControlEvents:UIControlEventTouchUpInside];
    [view addSubview:_share];
    [view addSubview:_close];
    UILayoutGuide *safe = view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [_strip.topAnchor constraintEqualToAnchor:safe.topAnchor constant:8],
        [_strip.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:12],
        [_strip.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-12],
        [_close.topAnchor constraintEqualToAnchor:_strip.bottomAnchor constant:10],
        [_close.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-12],
        [_share.centerYAnchor constraintEqualToAnchor:_close.centerYAnchor],
        [_share.trailingAnchor constraintEqualToAnchor:_close.leadingAnchor constant:-10],
        [_title.centerYAnchor constraintEqualToAnchor:_close.centerYAnchor],
        [_title.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:16],
        [_title.trailingAnchor constraintLessThanOrEqualToAnchor:_share.leadingAnchor constant:-10]]];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapped:)];
    tap.delegate = self;
    UILongPressGestureRecognizer *hold = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(held:)];
    hold.minimumPressDuration = 0.2;
    hold.delegate = self;
    _dismissPan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragged:)];
    _dismissPan.delegate = self;
    for (UIGestureRecognizer *recognizer in @[tap, hold, _dismissPan]) [_host addGestureRecognizer:recognizer];

    [self showCard:0 direction:0];
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    [center addObserver:self selector:@selector(resetClock) name:UIAccessibilityVoiceOverStatusDidChangeNotification object:nil];
    [center addObserver:self selector:@selector(resignActive) name:UIApplicationWillResignActiveNotification object:nil];
    [center addObserver:self selector:@selector(becomeActive) name:UIApplicationDidBecomeActiveNotification object:nil];
}

- (void)dealloc {
    [_link invalidate];
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    _title.font = cardFont(15, 22, YES, NO);
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    // The card's words start under the strip and the buttons, and keep clear of the screen's edges.
    UIEdgeInsets safe = self.view.safeAreaInsets;
    UIEdgeInsets margins = UIEdgeInsetsMake(CGRectGetMaxY(_close.frame) + 16, safe.left + 24, MAX(32, safe.bottom + 24), safe.right + 24);
    if (!UIEdgeInsetsEqualToEdgeInsets(_card.layoutMargins, margins)) _card.layoutMargins = margins;
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    _visible = YES;
    if (!_link) {
        SGStoryTicker *ticker = [SGStoryTicker new];
        ticker.story = self;
        _link = [CADisplayLink displayLinkWithTarget:ticker selector:@selector(tick:)];
        [_link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    }
    [self resetClock];
    UIAccessibilityPostNotification(UIAccessibilityScreenChangedNotification, _card.firstElement);
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    _visible = NO;
    [self resetClock];
    if (self.isBeingDismissed) {
        [_link invalidate];
        _link = nil;
        removeShareDirectory(_shareDirectory);
        _shareDirectory = nil;
    }
}

#pragma mark clock

// The card's time runs only while it can be watched: not held, dragged, shared over, in the background or under VoiceOver.
- (BOOL)running {
    return !_holding && !_dragging && !_sharing && !self.presentedViewController && !UIAccessibilityIsVoiceOverRunning()
        && UIApplication.sharedApplication.applicationState == UIApplicationStateActive;
}

- (void)resetClock {
    _last = 0;
    _link.paused = !_visible || _inactive || UIApplication.sharedApplication.applicationState != UIApplicationStateActive;
}

- (void)resignActive {
    _inactive = YES;
    [self resetClock];
}

- (void)becomeActive {
    _inactive = NO;
    [self resetClock];
}

- (void)tick:(CADisplayLink *)link {
    if (![self running]) { _last = 0; return; }
    if (_last) _elapsed += link.timestamp - _last;
    _last = link.timestamp;
    if (_elapsed >= kRecapCardSeconds && _index + 1 < _cards.count) { [self step:1]; return; }
    _segments[_index].progress = (CGFloat)MIN(1, _elapsed / kRecapCardSeconds);
}

#pragma mark cards

- (void)showCard:(NSUInteger)index direction:(NSInteger)direction {
    _index = index;
    _elapsed = 0;
    _last = 0;
    for (NSUInteger i = 0; i < _segments.count; i++) _segments[i].progress = i < index ? 1 : 0;
    SGRecapCardView *old = _card;
    SGRecapCardView *card = [[SGRecapCardView alloc] initWithRecap:_recap card:(SGRecapCard)_cards[index].integerValue index:index forImage:NO];
    card.frame = _host.bounds;
    card.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    card.insetsLayoutMarginsFromSafeArea = NO;   // the story sets them, the safe area included
    // Long words scroll only once a drag down has proven not to be the dismissal.
    [card.scroll.panGestureRecognizer requireGestureRecognizerToFail:_dismissPan];
    _card = card;
    [_host addSubview:card];
    [self.view setNeedsLayout];
    [self.view layoutIfNeeded];
    self.view.accessibilityElements = @[_title, _strip, card, _share, _close];
    if (!old) return;
    BOOL still = UIAccessibilityIsReduceMotionEnabled();
    if (!still && direction) card.transform = CGAffineTransformMakeTranslation(direction * _host.bounds.size.width * 0.25, 0);
    card.alpha = 0;
    [card arrive:YES];
    [UIView animateWithDuration:still ? 0.3 : 0.4 delay:0 usingSpringWithDamping:1 initialSpringVelocity:0 options:UIViewAnimationOptionAllowUserInteraction animations:^{
        card.alpha = 1;
        card.transform = CGAffineTransformIdentity;
        if (!still && direction) old.transform = CGAffineTransformMakeTranslation(-direction * self->_host.bounds.size.width * 0.12, 0);
        old.alpha = 0;
    } completion:^(BOOL finished) {
        [old removeFromSuperview];
    }];
    UIAccessibilityPostNotification(UIAccessibilityScreenChangedNotification, card.firstElement);
}

- (void)step:(NSInteger)delta {
    NSInteger next = (NSInteger)_index + delta;
    if (next < 0) {
        // Back from the first card starts it again.
        _elapsed = 0;
        _segments[0].progress = 0;
        return;
    }
    if (next >= (NSInteger)_cards.count) {
        _segments[_index].progress = 1;
        return;
    }
    [self showCard:(NSUInteger)next direction:delta];
}

- (BOOL)accessibilityScroll:(UIAccessibilityScrollDirection)direction {
    if (direction != UIAccessibilityScrollDirectionLeft && direction != UIAccessibilityScrollDirectionRight) return NO;
    [self step:direction == UIAccessibilityScrollDirectionLeft ? 1 : -1];
    UIAccessibilityPostNotification(UIAccessibilityPageScrolledNotification, _strip.accessibilityValue);
    return YES;
}

- (BOOL)accessibilityPerformEscape {
    [self close];
    return YES;
}

#pragma mark gestures

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)recognizer {
    if (recognizer != _dismissPan) return YES;
    CGPoint velocity = [_dismissPan velocityInView:self.view];
    return velocity.y > fabs(velocity.x) && _card.scroll.contentOffset.y <= 0;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)recognizer shouldReceiveTouch:(UITouch *)touch {
    return ![touch.view isKindOfClass:UIControl.class];
}

- (void)tapped:(UITapGestureRecognizer *)tap {
    BOOL back = [tap locationInView:_host].x < _host.bounds.size.width / 3;
    if (self.view.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft) back = !back;
    [self step:back ? -1 : 1];
}

- (void)held:(UILongPressGestureRecognizer *)hold {
    _holding = hold.state == UIGestureRecognizerStateBegan || hold.state == UIGestureRecognizerStateChanged;
    [UIView animateWithDuration:0.2 animations:^{
        CGFloat alpha = self->_holding ? 0 : 1;
        for (UIView *chrome in @[self->_strip, self->_title, self->_share, self->_close]) chrome.alpha = alpha;
    }];
}

- (void)dragged:(UIPanGestureRecognizer *)pan {
    UIView *view = self.view;
    CGFloat down = MAX(0, [pan translationInView:view].y);
    switch (pan.state) {
        case UIGestureRecognizerStateBegan:
            _dragging = YES;
            break;
        case UIGestureRecognizerStateChanged: {
            CGFloat scale = 1 - MIN(0.12, down / view.bounds.size.height * 0.3);
            _host.transform = CGAffineTransformScale(CGAffineTransformMakeTranslation(0, down), scale, scale);
            _host.layer.cornerRadius = MIN(32, down / 3);
            _host.clipsToBounds = YES;
            view.backgroundColor = [UIColor colorWithWhite:0 alpha:1 - MIN(0.6, down / view.bounds.size.height)];
            break;
        }
        default: {
            _dragging = NO;
            if (pan.state == UIGestureRecognizerStateEnded && (down > kDismissDistance || [pan velocityInView:view].y > kDismissVelocity)) {
                [self close];
                return;
            }
            [UIView animateWithDuration:0.35 delay:0 usingSpringWithDamping:0.85 initialSpringVelocity:0 options:0 animations:^{
                self->_host.transform = CGAffineTransformIdentity;
                self->_host.layer.cornerRadius = 0;
                view.backgroundColor = UIColor.blackColor;
            } completion:nil];
        }
    }
}

- (void)close {
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark sharing

// The card shown, drawn alone at 9:16 and the screen's scale. UIKit draws views on main only; the PNG is encoded
// and written off main.
- (void)shareCard {
    if (_sharing) return;
    _sharing = YES;
    CGFloat width = self.view.bounds.size.width;
    CGSize size = CGSizeMake(width, round(width * kShareAspect));
    NSUInteger index = _index;
    SGRecapCardView *card = [[SGRecapCardView alloc] initWithRecap:_recap card:(SGRecapCard)_cards[index].integerValue index:index forImage:YES];
    card.frame = (CGRect){CGPointZero, size};
    card.insetsLayoutMarginsFromSafeArea = NO;
    card.layoutMargins = UIEdgeInsetsMake(size.height * 0.12, 28, 64, 28);
    UILabel *mark = [UILabel new];
    mark.text = [NSString stringWithFormat:SGL(@"settings.stats.recap.share.mark", @"Retrine · %@ Recap"), SGRecapYearTitle(_recap.year, NSCalendar.currentCalendar)];
    mark.font = cardFont(12, 12, YES, YES);
    mark.textColor = [UIColor colorWithWhite:1 alpha:0.7];
    [mark sizeToFit];
    mark.frame = (CGRect){CGPointMake(28, size.height - 28 - mark.bounds.size.height), mark.bounds.size};
    [card addSubview:mark];
    [card layoutIfNeeded];
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat preferredFormat];   // the screen's scale
    format.opaque = YES;
    UIImage *image = [[[UIGraphicsImageRenderer alloc] initWithSize:size format:format] imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [card.layer renderInContext:context.CGContext];
    }];
    NSString *name = [NSString stringWithFormat:@"Retrine-Recap-%@-%lu.png", SGRecapYearTitle(_recap.year, NSCalendar.currentCalendar), (unsigned long)index + 1];
    __weak SGRecapStoryController *weakSelf = self;
    dispatch_async(recapQueue(), ^{
        NSURL *directory = [[NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES] URLByAppendingPathComponent:NSUUID.UUID.UUIDString isDirectory:YES];
        NSURL *url = [directory URLByAppendingPathComponent:name];
        NSError *error;
        BOOL saved = [NSFileManager.defaultManager createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:nil error:&error]
                  && [UIImagePNGRepresentation(image) writeToURL:url options:NSDataWritingAtomic error:&error];
        dispatch_async(dispatch_get_main_queue(), ^{
            SGRecapStoryController *story = weakSelf;
            // Closed, or covered, while the picture was written: the request is dropped with its file.
            BOOL present = canPresentFrom(story);
            if (saved && present) {
                [story presentShareSheet:url directory:directory];
                return;
            }
            removeShareDirectory(directory);
            if (!story) return;
            story->_sharing = NO;
            if (present) SGPresentInformation(story, SGL(@"settings.stats.recap.share.failed", @"Could not share the card"), error.localizedDescription);
        });
    });
}

- (void)presentShareSheet:(NSURL *)url directory:(NSURL *)directory {
    UIActivityViewController *sheet = [[UIActivityViewController alloc] initWithActivityItems:@[url] applicationActivities:nil];
    sheet.popoverPresentationController.sourceView = _share;
    _shareDirectory = directory;
    __weak SGRecapStoryController *weakSelf = self;
    // Shared, cancelled or failed alike.
    sheet.completionWithItemsHandler = ^(UIActivityType type, BOOL completed, NSArray *items, NSError *error) {
        removeShareDirectory(directory);
        SGRecapStoryController *story = weakSelf;
        if (!story) return;
        story->_sharing = NO;
        story->_shareDirectory = nil;
    };
    SGPresentDark(sheet);
    [self presentViewController:sheet animated:YES completion:nil];
}

@end

@implementation SGStoryTicker
- (void)tick:(CADisplayLink *)link {
    [self.story tick:link];
}
@end

// The story of `recap` over `presenter`, the controller that asked for it; dropped once that one has been left.
static void presentStory(SGRecap *recap, UIViewController *presenter) {
    if (!canPresentFrom(presenter)) return;
    SGRecapStoryController *story = [[SGRecapStoryController alloc] initWithRecap:recap];
    SGPresentDark(story);
    [presenter presentViewController:story animated:YES completion:nil];
}

#pragma mark - the years

static NSString *notEnoughMessage(SGRecapYear *year, NSCalendar *calendar) {
    return [NSString stringWithFormat:SGL(@"settings.stats.recap.not_ready.message", @"%@ has %@ with plays. A recap needs %lu. Keep listening, or import your Spotify history to fill in the days this phone did not record."),
            SGRecapYearTitle(year.interval, calendar), SGStatsDays(year.activeDays), (unsigned long)SGRecapActiveDaysNeeded];
}

@interface SGRecapYearsController : SGModPage
@property (nonatomic, strong) SGModSection *years;
@property (nonatomic, copy) void (^importHistory)(void);
@property (nonatomic) NSUInteger generation;
@property (nonatomic) BOOL opening, observing;
@end

@implementation SGRecapYearsController

// While shown, a play recorded or imported can give a year its 30th day: the years are added up again.
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

- (void)showRows:(NSArray<SGModRow *> *)rows {
    self.years.rows = rows;
    [self refreshVisibility];
    [self.tableView reloadData];
}

- (void)reload {
    NSUInteger generation = ++self.generation;
    __weak SGRecapYearsController *weakSelf = self;
    SGPlayLog *log = SGListeningLog();
    [log loadWithCompletion:^{
        SGRecapYearsController *page = weakSelf;
        if (!page || page.generation != generation) return;
        if (log.loadError) {
            SGModRow *row = SGStatRow(SGL(@"settings.stats.error.load", @"Could not load history"), nil);
            row.subtitle = log.loadError.localizedDescription;
            [page showRows:@[row]];
            return;
        }
        NSArray<SGPlay *> *snapshot = log.plays;
        NSCalendar *calendar = [NSCalendar.currentCalendar copy];
        dispatch_async(recapQueue(), ^{
            NSArray<SGRecapYear *> *years = SGRecapYears(snapshot, calendar);
            dispatch_async(dispatch_get_main_queue(), ^{
                SGRecapYearsController *page = weakSelf;
                if (page && page.generation == generation) [page showYears:years calendar:calendar];
            });
        });
    }];
}

- (void)showYears:(NSArray<SGRecapYear *> *)years calendar:(NSCalendar *)calendar {
    if (!years.count) {
        SGModRow *row = SGStatRow(SGL(@"settings.stats.status.no_plays", @"No plays yet"), nil);
        row.subtitle = SGL(@"settings.stats.recap.empty", @"Years you listen in appear here.");
        [self showRows:@[row]];
        return;
    }
    // The year just ended, shown here with its recap, is announced: no prompt or New mark for it after this.
    SGRecapYear *due = SGRecapDueYear(years, NSDate.date, calendar);
    if (due) markAnnounced(due.interval, calendar);
    __weak SGRecapYearsController *weakSelf = self;
    NSMutableArray<SGModRow *> *rows = [NSMutableArray array];
    for (SGRecapYear *year in years) {
        NSString *title = SGRecapYearTitle(year.interval, calendar);
        NSString *days = [NSString stringWithFormat:SGL(@"settings.stats.recap.year.days", @"%@ with plays"), SGStatsDays(year.activeDays)];
        SGModRow *row = SGActionRow(title, days, ^{ [weakSelf open:year calendar:calendar]; });
        row.value = ^NSString *{
            return year.eligible ? SGL(@"settings.stats.recap.year.play", @"Play") : SGL(@"settings.stats.recap.year.not_ready", @"Not enough yet");
        };
        [rows addObject:year.eligible ? SGWithTile(row, @"play.fill", SGGreen()) : SGWithSymbol(row, @"hourglass")];
    }
    [self showRows:rows];
}

- (void)open:(SGRecapYear *)year calendar:(NSCalendar *)calendar {
    if (!year.eligible) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:SGL(@"settings.stats.recap.not_ready.title", @"Not enough listening yet")
            message:notEnoughMessage(year, calendar) preferredStyle:UIAlertControllerStyleAlert];
        void (^importHistory)(void) = self.importHistory;
        [alert addAction:[UIAlertAction actionWithTitle:SGL(@"settings.stats.action.import", @"Import history") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            if (importHistory) importHistory();
        }]];
        [alert addAction:[UIAlertAction actionWithTitle:SGL(@"common.ok", @"OK") style:UIAlertActionStyleCancel handler:nil]];
        SGPresentDark(alert);
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    if (self.opening) return;
    self.opening = YES;
    __weak SGRecapYearsController *weakSelf = self;
    buildRecap(year.interval.startDate, ^(SGRecap *recap, NSError *error) {
        SGRecapYearsController *page = weakSelf;
        if (!page) return;
        page.opening = NO;
        // Left while the recap was added up: nothing shows over whatever is in front now.
        if (!canPresentFrom(page)) return;
        if (!recap) {
            SGPresentInformation(page, SGL(@"settings.stats.error.load", @"Could not load history"), error.localizedDescription);
            return;
        }
        presentStory(recap, page);
    });
}

@end

UIViewController *SGRecapYearsPage(void (^importHistory)(void)) {
    SGModSection *years = SGNotedSection(nil, @[SGStatRow(SGL(@"settings.stats.status.loading", @"Loading…"), nil)],
        [NSString stringWithFormat:SGL(@"settings.stats.recap.years.footer", @"A year has a recap once it has %lu days with plays. Recaps are made on this phone from your listening history; sharing a card shares only that picture."),
         (unsigned long)SGRecapActiveDaysNeeded]);
    NSArray<NSString *> *choices = @[SGL(@"settings.stats.recap.announce.launch", @"When Spotify opens"), SGL(@"settings.stats.recap.announce.settings", @"In Retrine Settings"),
                                     SGL(@"settings.stats.recap.announce.off", @"Off")];
    SGModRow *announce = SGMenuRow(SGL(@"settings.stats.recap.announce.title", @"Announce new recaps"), choices,
        ^NSString *{ return choices[(NSUInteger)announcement()]; },
        ^(NSInteger index) { SGSetInt(SGKeyRecapAnnouncement, index); });
    SGModSection *settings = SGNotedSection(nil, @[announce],
        [NSString stringWithFormat:SGL(@"settings.stats.recap.announce.footer", @"For %lu days from 1 January, the year just ended is pointed out once it has a recap: by the Recap row in Listening stats, or by a prompt after Spotify opens."),
         (unsigned long)SGRecapAnnouncementDays]);
    SGRecapYearsController *page = [[SGRecapYearsController alloc] initWithTitle:SGL(@"settings.stats.recap.title", @"Recap") intro:nil sections:@[years, settings] footer:nil];
    page.years = years;
    page.importHistory = importHistory;
    page.tiles = YES;
    return page;
}

#pragma mark - the Recap row and the prompt

// The prompt waits for the app to be in front with nothing presented, a few times, and gives up for this launch.
static const NSInteger kPromptTries = 20;
static const NSTimeInterval kPromptRetrySeconds = 3, kPromptSettleSeconds = 4;

static void promptWhenClear(SGRecap *recap, NSInteger tries) {
    NSCalendar *calendar = [NSCalendar.currentCalendar copy];
    // While it waited the preference may have changed, the days passed, or the Recap page announced the year.
    if (!SGRecapPromptDue(recap.year, NSDate.date, calendar, announcement(), announcedYear())) return;
    UIViewController *top = SGTopController();
    BOOL clear = top && !top.presentingViewController && UIApplication.sharedApplication.applicationState == UIApplicationStateActive;
    if (!clear) {
        if (tries > 0) dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kPromptRetrySeconds * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            promptWhenClear(recap, tries - 1);
        });
        return;
    }
    NSString *year = SGRecapYearTitle(recap.year, calendar);
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:SGL(@"settings.stats.recap.prompt.title", @"Your %@ Recap is ready"), year]
        message:[NSString stringWithFormat:SGL(@"settings.stats.recap.prompt.message", @"%@ of music on %@. Play it now, or later from Listening stats in Retrine Settings."),
                 SGStatsDuration(recap.ms), SGStatsDays(recap.activeDays)]
        preferredStyle:UIAlertControllerStyleAlert];
    // Either answer announces the year.
    [alert addAction:[UIAlertAction actionWithTitle:SGL(@"settings.stats.recap.prompt.play", @"Play") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        markAnnounced(recap.year, calendar);
        presentStory(recap, top);
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:SGL(@"settings.stats.recap.prompt.later", @"Not now") style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
        markAnnounced(recap.year, calendar);
    }]];
    SGPresentDark(alert);
    [top presentViewController:alert animated:YES completion:nil];
}

static void announceIfDue(void) {
    NSCalendar *calendar = [NSCalendar.currentCalendar copy];
    NSDate *now = NSDate.date;
    NSDateInterval *ended = SGRecapAnnouncedYear(now, calendar);
    if (!ended || !SGRecapPromptDue(ended, now, calendar, announcement(), announcedYear())) return;
    buildRecap(ended.startDate, ^(SGRecap *recap, NSError *error) {
        if (recap.eligible) promptWhenClear(recap, kPromptTries);
    });
}

__attribute__((constructor)) static void sg_recapAnnouncement(void) {
    __block id token = [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:nil
                                                                    usingBlock:^(NSNotification *note) {
        [NSNotificationCenter.defaultCenter removeObserver:token];
        token = nil;
        // Spotify posts it on main; the settle leaves the first seconds to its own launch.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kPromptSettleSeconds * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ announceIfDue(); });
    }];
}
