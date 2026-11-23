// The lyrics' Sync and Search LRCLIB sheets and the screen kept awake under them (LyricsTools.h).
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Settings/SGPageStyle.h"
#import "Shared/Lyrics/Lyrics.h"
#import "Shared/LyricsSources/LyricsSources.h"
#import "Shared/LocalFiles/LocalFiles.h"
#import "Headers/SPTPlayer.h"
#import "Redesigned/Kit/SGRTokens.h"
#import "LyricsTools.h"

// The steps the buttons move an offset by, and the most a step can reach either way.
static const NSInteger kSmallStep = 10, kLargeStep = 100;
static const CGFloat kSide = 20, kTop = 24, kGap = 16, kCardInset = 16, kCardRadius = 22, kButton = 44;

#pragma mark - the song

// Title, artist and length in seconds of a track the player or the local files know; nil for a track neither does.
static NSDictionary<NSString *, id> *songOf(NSString *track) {
    NSDictionary *local = track ? SGLocalFileInfo(track) : nil;
    if (local) return local;
    SPTPlayerTrack *player = track ? SGKaraokeTrackFor(track) : nil;
    if (!player) return nil;
    NSMutableDictionary *song = [NSMutableDictionary dictionary];
    if ([player.trackTitle isKindOfClass:NSString.class]) song[@"title"] = player.trackTitle;
    if ([player.artistName isKindOfClass:NSString.class]) song[@"artist"] = player.artistName;
    id album = player.metadata[@"album_title"], length = player.metadata[@"duration"];
    if ([album isKindOfClass:NSString.class]) song[@"album"] = album;
    if ([length respondsToSelector:@selector(integerValue)]) song[@"seconds"] = @([length integerValue] / 1000);
    return song;
}

// "+120 ms", "−80 ms" (a minus sign, not a hyphen), "0 ms".
static NSString *offsetText(NSInteger ms) {
    NSString *number = ms > 0 ? [NSString stringWithFormat:@"+%ld", (long)ms]
                     : ms < 0 ? [NSString stringWithFormat:@"\u2212%ld", (long)-ms] : @"0";
    return [NSString stringWithFormat:SGL(@"settings.lyricstools.sync.value.format", @"%@ ms"), number];
}

NSString *SGRLyricsSyncSummary(NSString *trackID) {
    NSInteger song = trackID ? SGLyricsTrackOffsetMs(trackID) : 0, route = SGLyricsRouteOffsetMs();
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    if (song) [parts addObject:[NSString stringWithFormat:SGL(@"settings.lyricstools.sync.summary.song", @"Song %@"), offsetText(song)]];
    NSString *name = SGLyricsRouteName();
    if (route && name) [parts addObject:[NSString stringWithFormat:@"%@ %@", name, offsetText(route)]];
    return parts.count ? [parts componentsJoinedByString:@", "] : nil;
}

#pragma mark - a card

// A rounded panel a step lighter than the sheet, the redesign's card.
static UIView *card(UIView *content) {
    UIView *panel = [UIView new];
    panel.backgroundColor = [UIColor colorWithWhite:1 alpha:0.08];
    panel.layer.cornerRadius = kCardRadius;
    panel.layer.cornerCurve = kCACornerCurveContinuous;
    content.translatesAutoresizingMaskIntoConstraints = NO;
    [panel addSubview:content];
    [NSLayoutConstraint activateConstraints:@[
        [content.topAnchor constraintEqualToAnchor:panel.topAnchor constant:kCardInset],
        [content.bottomAnchor constraintEqualToAnchor:panel.bottomAnchor constant:-kCardInset],
        [content.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor constant:kCardInset],
        [content.trailingAnchor constraintEqualToAnchor:panel.trailingAnchor constant:-kCardInset],
    ]];
    return panel;
}

static UILabel *label(UIFontTextStyle style, UIFontWeight weight, UIColor *color) {
    UILabel *label = [UILabel new];
    label.font = SGCategoryCappedFont(style, weight, UIContentSizeCategoryAccessibilityLarge);
    label.adjustsFontForContentSizeCategory = YES;
    label.textColor = color;
    label.numberOfLines = 0;
    return label;
}

#pragma mark - Sync

// The value of an offset, which VoiceOver adjusts by the small step with a swipe up or down.
@interface SGROffsetValue : UILabel
@property (nonatomic, copy) void (^step)(NSInteger by);
@end

@implementation SGROffsetValue
- (UIAccessibilityTraits)accessibilityTraits { return UIAccessibilityTraitAdjustable; }
- (void)accessibilityIncrement { if (self.step) self.step(kSmallStep); }
- (void)accessibilityDecrement { if (self.step) self.step(-kSmallStep); }
@end

// One offset: what it is for, its value, the four steps and Reset.
@interface SGROffsetControl : UIStackView
- (instancetype)initWithTitle:(NSString *)title symbol:(NSString *)symbol get:(NSInteger (^)(void))get set:(void (^)(NSInteger ms))set;
- (void)reload;
@end

@implementation SGROffsetControl {
    NSInteger (^_get)(void);
    void (^_set)(NSInteger);
    SGROffsetValue *_value;
    UIButton *_reset;
    UISelectionFeedbackGenerator *_feedback;
}

- (UIButton *)stepButton:(NSInteger)by {
    UIButtonConfiguration *config = [UIButtonConfiguration grayButtonConfiguration];
    config.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
    config.title = by > 0 ? [NSString stringWithFormat:@"+%ld", (long)by] : [NSString stringWithFormat:@"\u2212%ld", (long)-by];
    config.baseForegroundColor = SGRPrimary();
    config.titleTextAttributesTransformer = ^NSDictionary *(NSDictionary *attributes) {
        NSMutableDictionary *out = [attributes mutableCopy];
        out[NSFontAttributeName] = SGMonospacedDigitsFont(SGCategoryCappedFont(UIFontTextStyleSubheadline, UIFontWeightSemibold, UIContentSizeCategoryExtraExtraExtraLarge));
        return out;
    };
    __weak SGROffsetControl *weakSelf = self;
    UIButton *button = [UIButton buttonWithConfiguration:config primaryAction:[UIAction actionWithHandler:^(UIAction *action) {
        [weakSelf stepBy:by];
    }]];
    button.accessibilityLabel = [NSString stringWithFormat:by > 0 ? SGL(@"settings.lyricstools.sync.later.format", @"%ld ms later")
                                                                   : SGL(@"settings.lyricstools.sync.earlier.format", @"%ld ms earlier"), (long)labs(by)];
    [button.heightAnchor constraintGreaterThanOrEqualToConstant:kButton].active = YES;
    return button;
}

- (instancetype)initWithTitle:(NSString *)title symbol:(NSString *)symbol get:(NSInteger (^)(void))get set:(void (^)(NSInteger ms))set {
    if (!(self = [super initWithFrame:CGRectZero])) return nil;
    _get = [get copy];
    _set = [set copy];
    _feedback = [UISelectionFeedbackGenerator new];
    self.axis = UILayoutConstraintAxisVertical;
    self.spacing = 12;

    UIImageView *glyph = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:symbol]];
    glyph.tintColor = SGRSecondary();
    glyph.preferredSymbolConfiguration = [UIImageSymbolConfiguration configurationWithTextStyle:UIFontTextStyleSubheadline scale:UIImageSymbolScaleMedium];
    [glyph setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    UILabel *name = label(UIFontTextStyleSubheadline, UIFontWeightSemibold, SGRSecondary());
    name.text = title;
    UIButtonConfiguration *resetConfig = [UIButtonConfiguration plainButtonConfiguration];
    resetConfig.title = SGL(@"common.reset", @"Reset");
    resetConfig.baseForegroundColor = SGRAccent();
    resetConfig.contentInsets = NSDirectionalEdgeInsetsMake(0, 8, 0, 0);
    __weak SGROffsetControl *weakSelf = self;
    _reset = [UIButton buttonWithConfiguration:resetConfig primaryAction:[UIAction actionWithHandler:^(UIAction *action) {
        [weakSelf take:0];
    }]];
    [_reset setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [_reset.heightAnchor constraintGreaterThanOrEqualToConstant:kButton].active = YES;
    UIStackView *head = [[UIStackView alloc] initWithArrangedSubviews:@[glyph, name, _reset]];
    head.spacing = 8;
    head.alignment = UIStackViewAlignmentCenter;

    _value = [SGROffsetValue new];
    _value.font = SGMonospacedDigitsFont(SGCategoryCappedFont(UIFontTextStyleLargeTitle, UIFontWeightBold, UIContentSizeCategoryAccessibilityMedium));
    _value.adjustsFontForContentSizeCategory = YES;
    _value.textColor = SGRPrimary();
    _value.textAlignment = NSTextAlignmentCenter;
    _value.isAccessibilityElement = YES;
    _value.accessibilityLabel = title;
    _value.step = ^(NSInteger by) { [weakSelf stepBy:by]; };

    UIStackView *steps = [[UIStackView alloc] initWithArrangedSubviews:@[[self stepButton:-kLargeStep], [self stepButton:-kSmallStep],
                                                                         [self stepButton:kSmallStep], [self stepButton:kLargeStep]]];
    steps.distribution = UIStackViewDistributionFillEqually;
    steps.spacing = 8;
    [self addArrangedSubview:head];
    [self addArrangedSubview:_value];
    [self addArrangedSubview:steps];
    [self reload];
    return self;
}

- (void)stepBy:(NSInteger)by {
    [self take:_get() + by];
}

- (void)take:(NSInteger)ms {
    ms = MAX(-5000, MIN(5000, ms));
    if (ms == _get()) return;
    _set(ms);
    [_feedback selectionChanged];
    [self reload];
}

- (void)reload {
    NSInteger ms = _get();
    _value.text = offsetText(ms);
    _value.accessibilityValue = _value.text;
    _reset.enabled = ms != 0;
    _reset.alpha = ms ? 1 : 0.35;
}
@end

@interface SGRLyricsSyncSheet : UIViewController
@end

@implementation SGRLyricsSyncSheet {
    NSString *_track;
    UIStackView *_stack;
    SGROffsetControl *_song;
    UIView *_routeCard;
    UILabel *_footer;
}

- (instancetype)initWithTrack:(NSString *)track {
    if (!(self = [super initWithNibName:nil bundle:nil])) return nil;
    _track = [track copy];
    self.modalPresentationStyle = UIModalPresentationPageSheet;
    SGPresentDark(self);
    UISheetPresentationController *sheet = self.sheetPresentationController;
    sheet.detents = @[UISheetPresentationControllerDetent.mediumDetent, UISheetPresentationControllerDetent.largeDetent];
    sheet.prefersGrabberVisible = YES;
    sheet.prefersEdgeAttachedInCompactHeight = YES;
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    // From iOS 26 a sheet short of full height is Liquid Glass the system draws; a fill here would cover it.
    if (@available(iOS 26.0, *)) {
    } else {
        self.view.backgroundColor = UIColor.systemBackgroundColor;
    }
    UIScrollView *scroll = [UIScrollView new];
    scroll.alwaysBounceVertical = YES;
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:scroll];
    _stack = [UIStackView new];
    _stack.axis = UILayoutConstraintAxisVertical;
    _stack.spacing = kGap;
    _stack.translatesAutoresizingMaskIntoConstraints = NO;
    [scroll addSubview:_stack];
    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [scroll.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [scroll.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor],
        [_stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:kTop],
        [_stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-kTop],
        [_stack.leadingAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.leadingAnchor constant:kSide],
        [_stack.trailingAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.trailingAnchor constant:-kSide],
    ]];

    UILabel *title = label(UIFontTextStyleTitle2, UIFontWeightBold, SGRPrimary());
    title.text = SGL(@"settings.lyricstools.sync.title", @"Sync");
    title.accessibilityTraits = UIAccessibilityTraitHeader;
    UILabel *song = label(UIFontTextStyleSubheadline, UIFontWeightRegular, SGRSecondary());
    NSDictionary *info = songOf(_track);
    song.text = [info[@"title"] length] ? ([info[@"artist"] length] ? [NSString stringWithFormat:@"%@ · %@", info[@"title"], info[@"artist"]] : info[@"title"]) : nil;
    UIStackView *head = [[UIStackView alloc] initWithArrangedSubviews:@[title, song]];
    head.axis = UILayoutConstraintAxisVertical;
    head.spacing = 2;
    [_stack addArrangedSubview:head];

    NSString *track = _track;
    _song = [[SGROffsetControl alloc] initWithTitle:SGL(@"settings.lyricstools.sync.song.title", @"This song") symbol:@"music.note"
                                                get:^NSInteger { return SGLyricsTrackOffsetMs(track); }
                                                set:^(NSInteger ms) { SGLyricsSetTrackOffsetMs(track, ms); }];
    [_stack addArrangedSubview:card(_song)];
    _footer = label(UIFontTextStyleFootnote, UIFontWeightRegular, SGRTertiary());
    [self showRoute];
    // Headphones connected or taken off while the sheet is open, or an offset changed elsewhere.
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(offsetsChanged) name:SGLyricsOffsetsDidChangeNotification object:nil];
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

// The output's own card while headphones, a car or a speaker of their own play the song, else a note saying so.
- (void)showRoute {
    [_routeCard removeFromSuperview];
    [_footer removeFromSuperview];
    NSString *name = SGLyricsRouteName();
    if (name) {
        SGROffsetControl *route = [[SGROffsetControl alloc] initWithTitle:name symbol:@"headphones"
                                                                      get:^NSInteger { return SGLyricsRouteOffsetMs(); }
                                                                      set:^(NSInteger ms) { SGLyricsSetRouteOffsetMs(ms); }];
        _routeCard = card(route);
    } else {
        UILabel *note = label(UIFontTextStyleFootnote, UIFontWeightRegular, SGRSecondary());
        note.text = SGL(@"settings.lyricstools.sync.route.none", @"Playing on this iPhone. Connect headphones or a speaker to give them an offset of their own, kept for every song.");
        _routeCard = card(note);
    }
    [_stack addArrangedSubview:_routeCard];
    _footer.text = [NSString stringWithFormat:SGL(@"settings.lyricstools.sync.footer.format",
        @"A positive offset shows the lines later. Both add to the Delay on the Lyrics page, now %@."), offsetText(SGInt(SGKeyLyricsDelay, 0))];
    [_stack addArrangedSubview:_footer];
}

- (void)offsetsChanged {
    [_song reload];
    [self showRoute];
}
@end

void SGRShowLyricsSync(NSString *trackID) {
    if (!trackID.length) return;
    UIViewController *top = SGTopController();
    if (!top || [top isKindOfClass:SGRLyricsSyncSheet.class]) return;
    [top presentViewController:[[SGRLyricsSyncSheet alloc] initWithTrack:trackID] animated:YES completion:nil];
}

#pragma mark - Search LRCLIB

typedef NS_ENUM(NSInteger, SGRSearchState) {
    SGRSearchIdle,
    SGRSearchLoading,
    SGRSearchDone,
};

@interface SGRLyricsSearchController : UITableViewController <UITextFieldDelegate>
@end

@implementation SGRLyricsSearchController {
    NSString *_track;
    NSInteger _seconds;
    UITextField *_title, *_artist;
    NSArray<NSDictionary *> *_records;
    SGRSearchState _state;
    NSUInteger _asked;   // counts the searches, so a late answer to an earlier one is dropped
}

- (instancetype)initWithTrack:(NSString *)track {
    if (!(self = [super initWithStyle:UITableViewStyleInsetGrouped])) return nil;
    _track = [track copy];
    NSDictionary *song = songOf(track);
    _seconds = [song[@"seconds"] integerValue];
    _title = [self field:SGL(@"settings.lyricstools.search.field.title", @"Title") text:song[@"title"]];
    _artist = [self field:SGL(@"settings.lyricstools.search.field.artist", @"Artist") text:song[@"artist"]];
    _artist.returnKeyType = UIReturnKeySearch;
    _title.returnKeyType = UIReturnKeyNext;
    self.title = SGL(@"settings.lyricstools.search.title", @"Search LRCLIB");
    return self;
}

- (UITextField *)field:(NSString *)placeholder text:(NSString *)text {
    UITextField *field = [UITextField new];
    field.placeholder = placeholder;
    field.text = [text isKindOfClass:NSString.class] ? text : nil;
    field.accessibilityLabel = placeholder;
    field.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    field.adjustsFontForContentSizeCategory = YES;
    field.textColor = SGRPrimary();
    field.clearButtonMode = UITextFieldViewModeWhileEditing;
    field.autocorrectionType = UITextAutocorrectionTypeNo;
    field.delegate = self;
    return field;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemClose
                                                                                         target:self action:@selector(close)];
    if (@available(iOS 26.0, *)) self.tableView.backgroundColor = UIColor.clearColor;
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    [self search];
}

- (void)close {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (BOOL)textFieldShouldReturn:(UITextField *)field {
    if (field == _title) [_artist becomeFirstResponder];
    else [self search];
    return NO;
}

- (void)search {
    [self.view endEditing:YES];
    NSString *title = [_title.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *artist = [_artist.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    // Every search, an empty one too, retires the answer still on its way to an earlier one.
    NSUInteger asked = ++_asked;
    if (!title.length) {
        _state = SGRSearchIdle;
        _records = nil;
        [self.tableView reloadData];
        return;
    }
    _state = SGRSearchLoading;
    [self.tableView reloadData];
    UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, SGL(@"settings.lyricstools.search.searching", @"Searching"));
    __weak SGRLyricsSearchController *weakSelf = self;
    SGLrcLibSearch(title, artist, _seconds, ^(NSArray<NSDictionary *> *records) {
        SGRLyricsSearchController *me = weakSelf;
        if (!me || asked != me->_asked) return;
        me->_records = records ?: @[];
        me->_state = SGRSearchDone;
        [me.tableView reloadData];
        UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification,
            me->_records.count ? [NSString stringWithFormat:SGL(@"settings.lyricstools.search.found.format", @"%lu results"), (unsigned long)me->_records.count]
                               : SGL(@"settings.lyricstools.search.empty", @"No lyrics found"));
    });
}

// The fields and Search; Automatic while a pick is pinned; then the results, or what stands for them.
enum { kFieldsSection, kPinSection, kResultsSection };

- (NSInteger)numberOfSectionsInTableView:(UITableView *)table { return 3; }

- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section {
    if (section == kFieldsSection) return 3;
    if (section == kPinSection) return SGLyricsPinnedID(_track) ? 1 : 0;
    if (_state == SGRSearchLoading) return 1;
    return _state == SGRSearchDone ? MAX(1, (NSInteger)_records.count) : 0;
}

- (NSString *)tableView:(UITableView *)table titleForHeaderInSection:(NSInteger)section {
    return section == kResultsSection && _state == SGRSearchDone && _records.count ? SGL(@"settings.lyricstools.search.results.header", @"Results") : nil;
}

- (NSString *)tableView:(UITableView *)table titleForFooterInSection:(NSInteger)section {
    if (section == kFieldsSection) return SGL(@"settings.lyricstools.search.footer", @"LRCLIB is an open library of lyrics. The lyrics you pick stay with this song until you choose Automatic.");
    if (section == kPinSection && SGLyricsPinnedID(_track)) return SGL(@"settings.lyricstools.search.automatic.footer", @"The sources on the Lyrics page choose again.");
    return nil;
}

static NSString *lengthText(NSInteger seconds) {
    return seconds > 0 ? [NSString stringWithFormat:@"%ld:%02ld", (long)seconds / 60, (long)seconds % 60] : nil;
}

- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.backgroundColor = [UIColor colorWithWhite:1 alpha:0.08];
    UIListContentConfiguration *content = [UIListContentConfiguration subtitleCellConfiguration];
    content.textProperties.color = SGRPrimary();
    content.secondaryTextProperties.color = SGRSecondary();
    if (path.section == kFieldsSection && path.row < 2) {
        UITextField *field = path.row == 0 ? _title : _artist;
        field.translatesAutoresizingMaskIntoConstraints = NO;
        [cell.contentView addSubview:field];
        UILayoutGuide *margins = cell.contentView.layoutMarginsGuide;
        [NSLayoutConstraint activateConstraints:@[
            [field.leadingAnchor constraintEqualToAnchor:margins.leadingAnchor],
            [field.trailingAnchor constraintEqualToAnchor:margins.trailingAnchor],
            [field.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor],
            [field.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor],
            [field.heightAnchor constraintGreaterThanOrEqualToConstant:kButton],
        ]];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }
    if (path.section == kFieldsSection) {
        content = [UIListContentConfiguration cellConfiguration];
        content.text = SGL(@"settings.lyricstools.search.action", @"Search");
        content.textProperties.color = SGRAccent();
        content.textProperties.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
        content.textProperties.alignment = UIListContentTextAlignmentCenter;
        cell.contentConfiguration = content;
        cell.accessibilityTraits = UIAccessibilityTraitButton;
        return cell;
    }
    if (path.section == kPinSection) {
        content.text = SGL(@"settings.lyricstools.search.automatic.title", @"Automatic");
        content.image = [UIImage systemImageNamed:@"arrow.uturn.backward"];
        content.imageProperties.tintColor = SGRAccent();
        cell.contentConfiguration = content;
        cell.accessibilityTraits = UIAccessibilityTraitButton;
        return cell;
    }
    if (_state == SGRSearchLoading) {
        UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithFrame:CGRectZero];
        [spinner startAnimating];
        cell.accessoryView = spinner;
        content = [UIListContentConfiguration cellConfiguration];
        content.text = SGL(@"settings.lyricstools.search.searching", @"Searching");
        content.textProperties.color = SGRSecondary();
        cell.contentConfiguration = content;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }
    if (!_records.count) {
        content.text = SGL(@"settings.lyricstools.search.empty", @"No lyrics found");
        content.secondaryText = SGL(@"settings.lyricstools.search.empty.hint", @"Try a shorter title, or the artist without anyone featured.");
        cell.contentConfiguration = content;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }
    NSDictionary *record = _records[path.row];
    NSString *kind = [record[@"instrumental"] boolValue] ? SGL(@"settings.lyricstools.search.kind.instrumental", @"Instrumental")
                   : [record[@"synced"] boolValue] ? SGL(@"settings.lyricstools.search.kind.synced", @"Synced")
                   : SGL(@"settings.lyricstools.search.kind.plain", @"Plain");
    NSMutableArray<NSString *> *detail = [NSMutableArray array];
    for (NSString *part in @[record[@"artist"] ?: @"", record[@"album"] ?: @"", lengthText([record[@"seconds"] integerValue]) ?: @"", kind]) {
        if ([part isKindOfClass:NSString.class] && part.length) [detail addObject:part];
    }
    content.text = [record[@"title"] isKindOfClass:NSString.class] ? record[@"title"] : @"";
    content.secondaryText = [detail componentsJoinedByString:@" · "];
    content.textProperties.numberOfLines = 2;
    cell.contentConfiguration = content;
    BOOL pinned = [record[@"id"] isEqual:SGLyricsPinnedID(_track)];
    cell.accessoryType = pinned ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    cell.tintColor = SGRAccent();
    if (pinned) cell.accessibilityTraits |= UIAccessibilityTraitSelected;
    return cell;
}

- (BOOL)tableView:(UITableView *)table shouldHighlightRowAtIndexPath:(NSIndexPath *)path {
    if (path.section == kFieldsSection) return path.row == 2;
    if (path.section == kResultsSection) return _state == SGRSearchDone && _records.count;
    return YES;
}

- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)path {
    [table deselectRowAtIndexPath:path animated:YES];
    if (path.section == kFieldsSection) {
        if (path.row == 2) [self search];
        return;
    }
    if (path.section == kPinSection) {
        SGLyricsUnpin(_track);
        [[UINotificationFeedbackGenerator new] notificationOccurred:UINotificationFeedbackTypeSuccess];
        [self close];
        return;
    }
    if (_state != SGRSearchDone || path.row >= (NSInteger)_records.count) return;
    NSUInteger asked = ++_asked;
    __weak SGRLyricsSearchController *weakSelf = self;
    BOOL (^current)(void) = ^BOOL {
        SGRLyricsSearchController *me = weakSelf;
        return me && me->_asked == asked && me.view.window && !me.isBeingDismissed && !me.navigationController.isBeingDismissed;
    };
    SGLyricsPickRecord(_track, _records[path.row], current, ^(BOOL pinned) {
    SGRLyricsSearchController *me = weakSelf;
    if (!current()) return;
    if (!pinned) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:SGL(@"settings.lyricstools.search.unusable.title", @"No lines to show")
            message:SGL(@"settings.lyricstools.search.unusable.message", @"These lyrics are empty. Pick another result.") preferredStyle:UIAlertControllerStyleAlert];
        alert.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
        [alert addAction:[UIAlertAction actionWithTitle:SGL(@"common.ok", @"OK") style:UIAlertActionStyleCancel handler:nil]];
        [me presentViewController:alert animated:YES completion:nil];
        return;
    }
    [[UINotificationFeedbackGenerator new] notificationOccurred:UINotificationFeedbackTypeSuccess];
    [me close];
    });
}
@end

UIAction *SGRLyricsSearchAction(NSString *trackID) {
    if (!trackID.length) return nil;
    NSString *track = [trackID copy];
    UIAction *action = [UIAction actionWithTitle:SGL(@"settings.lyricstools.player.search", @"Search Lyrics") image:[UIImage systemImageNamed:@"text.magnifyingglass"]
                                      identifier:nil handler:^(UIAction *action) { SGRShowLyricsSearch(track); }];
    action.subtitle = SGLyricsPinnedID(track) ? SGL(@"settings.lyricstools.menu.search.pinned", @"Picked by hand")
                    : !SGKaraokeLinesForTrack(track) ? SGL(@"settings.lyricstools.player.search.none", @"None found yet, from LRCLIB") : nil;
    return action;
}

void SGRShowLyricsSearch(NSString *trackID) {
    if (!trackID.length) return;
    UIViewController *top = SGTopController();
    if (!top || [top.presentedViewController isKindOfClass:UINavigationController.class]) return;
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:[[SGRLyricsSearchController alloc] initWithTrack:trackID]];
    navigation.modalPresentationStyle = UIModalPresentationPageSheet;
    SGPresentDark(navigation);
    UISheetPresentationController *sheet = navigation.sheetPresentationController;
    sheet.detents = @[UISheetPresentationControllerDetent.mediumDetent, UISheetPresentationControllerDetent.largeDetent];
    sheet.prefersGrabberVisible = YES;
    sheet.prefersEdgeAttachedInCompactHeight = YES;
    [top presentViewController:navigation animated:YES completion:nil];
}

#pragma mark - Keep screen on

static BOOL sgr_keepAwake;
static NSHashTable *sgr_holders;
static BOOL sgr_holding;   // whether the lyrics hold the screen awake
static BOOL sgr_wasOff;    // the idle timer was off already when they took it, by someone else (the phone driver)

BOOL SGRLyricsKeepAwakeOn(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{ sgr_keepAwake = SGEnabled(SGRKeyLyricsKeepAwake); });
    return sgr_keepAwake;
}

void SGRLyricsHoldAwake(id holder, BOOL hold) {
    if (!holder) return;
    if (!sgr_holders) sgr_holders = [NSHashTable weakObjectsHashTable];
    // Asked again every time, not only on a change: a view going away from dealloc is already out of the
    // weak table, and the screen must still be let go.
    if (hold) [sgr_holders addObject:holder];
    else [sgr_holders removeObject:holder];
    // Only what this set is undone: an idle timer someone else had off when the lyrics took it stays off.
    BOOL awake = sgr_holders.allObjects.count > 0;
    if (awake == sgr_holding) return;
    sgr_holding = awake;
    UIApplication *app = UIApplication.sharedApplication;
    if (awake) {
        sgr_wasOff = app.idleTimerDisabled;
        app.idleTimerDisabled = YES;
    } else if (!sgr_wasOff) {
        app.idleTimerDisabled = NO;
    }
    SGLog(@"lyrics: the screen %@", awake ? @"is kept on" : @"may lock again");
}

SGModRow *SGRLyricsKeepAwakeRow(void) {
    // On until switched off: the Music app keeps the screen on while its lyrics are open.
    SGModRow *row = SGSwitchRow(SGL(@"settings.lyrics.keep_awake.title", @"Keep screen on"),
                                SGL(@"settings.lyrics.keep_awake.subtitle", @"While lyrics are shown and the song plays"), SGRKeyLyricsKeepAwake);
    row.changed = ^(BOOL on) {
        SGRLyricsKeepAwakeOn();
        sgr_keepAwake = on;
        [NSNotificationCenter.defaultCenter postNotificationName:SGRKeyLyricsKeepAwake object:nil];
    };
    return row;
}

SGModRow *SGRLyricsFullRateRow(void) {
    SGModRow *row = SGSwitchRow(SGL(@"settings.lyrics.full_rate.title", @"Smooth lyrics (120 Hz)"),
                                SGL(@"settings.lyrics.full_rate.subtitle", @"Off draws the lyrics at up to 60 Hz to use less battery. Only ProMotion displays show a difference."), SGRKeyLyricsFullRate);
    row.changed = ^(BOOL on) {
        [NSNotificationCenter.defaultCenter postNotificationName:SGRKeyLyricsFullRate object:nil];
    };
    return row;
}
