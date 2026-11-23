// Spotify owns the queue. History is a read-only list above the current song; Up Next keeps
// its existing skip-ahead action. Queue editing and History replay are not offered.
// History adapted from the GPL-3 jadetheda and michaelmelita1 forks.
// Threading: main thread only; Spotify delivers fetches on main.
#import "Core/SGCore.h"
#import "Settings/SGPageStyle.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Shared/Player/PlayerState.h"
#import "Shared/AutoMix/AutoMixPreview.h"
#import "PlayerMix.h"
#import "PlayerQueue.h"
#import <objc/message.h>

static const NSUInteger kMaxRows = 50;
static const NSUInteger kHistoryRows = 10;
static const CGFloat kBlendPadding = 8, kBlendGap = 6;
// A row's cover, the Music app's list thumbnail (iOS 26, design/applemusic-gap item 22).
static const CGFloat kCoverSide = 44;

// Verified against Spotify 9.1.90's metadata and live runtime. Every optional surface is gated below.
@protocol SGRQueueSnapshot <NSObject>
@property (nonatomic, readonly) SPTPlayerTrack *track;
@property (nonatomic, readonly) NSArray *prevTracks;
@property (nonatomic, readonly) NSArray *nextTracks;
@end
@protocol SGRQueuePlayer <SPTPlayer>
- (void)fetchQueue:(void (^)(id<SGRQueueSnapshot>))callback on:(dispatch_queue_t)queue;
@end

static id queueValue(id object, NSString *name) {
    SEL selector = NSSelectorFromString(name);
    return [object respondsToSelector:selector] ? ((id (*)(id, SEL))objc_msgSend)(object, selector) : nil;
}

static NSArray *trackIdentity(SPTPlayerTrack *track) {
    if (![track isKindOfClass:NSClassFromString(@"SPTPlayerTrack")]) return nil;
    NSString *uri = SGURIString(track.URI), *uid = queueValue(track, @"UID");
    if (!uri.length || ![uid isKindOfClass:NSString.class] || !uid.length) return nil;
    return @[uri, uid, track.provider ?: @""];
}

static NSArray<SPTPlayerTrack *> *queueTracks(NSArray *tracks, NSUInteger limit, BOOL history) {
    NSMutableArray *songs = [NSMutableArray new];
    if (![tracks isKindOfClass:NSArray.class]) return songs;
    for (SPTPlayerTrack *track in tracks) {
        if (![track isKindOfClass:NSClassFromString(@"SPTPlayerTrack")] || !track.trackTitle.length ||
            !SGURIString(track.URI) || (history && ![SGURIString(track.URI) hasPrefix:@"spotify:track:"])) continue;
        [songs addObject:track];
        if (songs.count == limit) break;
    }
    return songs;
}

// The blend from the playing song into `next`; nil when the facts say nothing about that pair.
static NSString *blendInto(SPTPlayerTrack *next) {
    SGTransitionFacts *facts = SGAutoMixCurrentTransition();
    if (!SGRMixShowsQueue() || !facts || !SGRMixTrackIs(SGPlayerState().track, facts.fromURI, facts.fromUID)
        || !SGRMixTrackIs(next, facts.toURI, facts.toUID)) return nil;
    if (facts.kind == SGTransitionKindSpotifyAutomix) return SGL(@"settings.player.queue.blend.spotify", @"Spotify AutoMix");
    SGTransitionSettings settings;
    if (facts.kind != SGTransitionKindCrossfade || !SGTransitionSettingsRead(&settings)) return nil;
    return [NSString stringWithFormat:SGL(@"settings.player.queue.blend.crossfade", @"Crossfade, %ld s"), lround(settings.milliseconds / 1000.0)];
}

// The line over the first row: the merge glyph and the blend's name, read out as the name.
@interface SGRQueueBlendView : UIView
@property (nonatomic, readonly) UILabel *label;
@end

@implementation SGRQueueBlendView {
    UIImageView *_glyph;
}

- (instancetype)init {
    if (!(self = [super initWithFrame:CGRectZero])) return nil;
    _glyph = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"arrow.triangle.merge"]];
    _glyph.tintColor = SGRSecondary();
    _glyph.contentMode = UIViewContentModeScaleAspectFit;
    _label = [UILabel new];
    _label.textColor = SGRSecondary();
    _label.numberOfLines = 0;
    [self addSubview:_glyph];
    [self addSubview:_label];
    self.isAccessibilityElement = YES;
    self.accessibilityTraits = UIAccessibilityTraitStaticText;
    [self takeFont];
    return self;
}

- (void)takeFont {
    _label.font = SGCategoryCappedFont(UIFontTextStyleFootnote, UIFontWeightRegular, UIContentSizeCategoryAccessibilityMedium);
    _glyph.preferredSymbolConfiguration = [UIImageSymbolConfiguration configurationWithFont:_label.font];
}

- (void)setText:(NSString *)text {
    _label.text = text;
    self.accessibilityLabel = text;
    [self setNeedsLayout];
}

- (CGFloat)glyphWidth {
    return ceil(_glyph.intrinsicContentSize.width);
}

- (CGFloat)heightForWidth:(CGFloat)width {
    CGFloat text = width - self.layoutMargins.left - self.layoutMargins.right - [self glyphWidth] - kBlendGap;
    return ceil([_label sizeThatFits:CGSizeMake(text, CGFLOAT_MAX)].height) + 2 * kBlendPadding;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat x = self.layoutMargins.left, glyph = [self glyphWidth];
    CGFloat width = self.bounds.size.width - x - self.layoutMargins.right - glyph - kBlendGap;
    CGFloat height = ceil([_label sizeThatFits:CGSizeMake(width, CGFLOAT_MAX)].height);
    _glyph.frame = CGRectMake(x, kBlendPadding, glyph, _label.font.lineHeight);
    _label.frame = CGRectMake(x + glyph + kBlendGap, kBlendPadding, width, height);
}

- (void)traitCollectionDidChange:(UITraitCollection *)previous {
    [super traitCollectionDidChange:previous];
    [self takeFont];
}

@end

// The Up Next heading and, under it, the blend into the first song. A header view of the table's own kind, so the
// table gives it the margins it gives its own headers (History, Now Playing): the heading and the blend stand where
// their headings do, over the rows' covers.
@interface SGRQueueUpNextHeader : UITableViewHeaderFooterView
@property (nonatomic, readonly) UILabel *title;
@property (nonatomic, readonly) SGRQueueBlendView *blend;
@end

@implementation SGRQueueUpNextHeader

- (instancetype)initWithReuseIdentifier:(NSString *)identifier {
    if (!(self = [super initWithReuseIdentifier:identifier])) return nil;
    _title = [UILabel new];
    _title.text = SGL(@"settings.player.queue.up_next", @"Up Next");
    _title.textColor = SGRSecondary();
    _blend = [SGRQueueBlendView new];
    [self.contentView addSubview:_title];
    [self.contentView addSubview:_blend];
    return self;
}

- (CGFloat)headingHeight {
    return ceil(_title.font.lineHeight) + 2 * kBlendPadding;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    UIView *content = self.contentView;
    UIEdgeInsets margins = content.layoutMargins;
    CGFloat width = content.bounds.size.width;
    _title.frame = CGRectMake(margins.left, kBlendPadding, MAX(0, width - margins.left - margins.right), ceil(_title.font.lineHeight));
    _blend.layoutMargins = UIEdgeInsetsMake(0, margins.left, 0, margins.right);
    _blend.frame = CGRectMake(0, [self headingHeight], width, _blend.hidden ? 0 : [_blend heightForWidth:width]);
}

@end

// What a row shows, so a report that changed nothing in the list leaves it alone.
static NSArray<NSString *> *signatureOf(NSArray<SPTPlayerTrack *> *tracks) {
    NSMutableArray<NSString *> *signature = [NSMutableArray arrayWithCapacity:tracks.count];
    for (SPTPlayerTrack *track in tracks) {
        [signature addObject:[NSString stringWithFormat:@"%@\t%@\t%@\t%@", trackIdentity(track), SGURIString(track.URI), track.trackTitle, track.artistName ?: @""]];
    }
    return signature;
}

#ifndef __IPHONE_17_0
// UIKit calls it from iOS 13 on (back-deployed); the iOS 16.5 SDK the tweak builds with does not declare it.
@interface UIViewController (SGRIsAppearing)
- (void)viewIsAppearing:(BOOL)animated;
@end
#endif

@interface SGRPlayerQueueController : UITableViewController <SGPlayerStateObserver>
// In the two column player's side column rather than a sheet: nothing to close.
@property (nonatomic) BOOL embedded;
@end

@implementation SGRPlayerQueueController {
    NSArray<SPTPlayerTrack *> *_tracks;
    NSArray *_signature;
    NSArray<SPTPlayerTrack *> *_history;
    SPTPlayerTrack *_current;
    NSArray *_reportedKey;
    BOOL _fetching;
    UILabel *_empty;
    SGRQueueUpNextHeader *_upNext;
    // Each row's cover by the track's URI once it has landed (a failed or missing one is asked for again when its row
    // next comes on screen), and the ones on their way.
    NSCache<NSString *, UIImage *> *_covers;
    NSMutableDictionary<NSString *, NSProgress *> *_coming;
}

- (void)dealloc {
    [self stopCoversExcept:nil];
}

- (instancetype)init {
    if (!(self = [super initWithStyle:UITableViewStyleInsetGrouped])) return nil;
    self.title = SGL(@"settings.player.queue.title", @"Playing Next");
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    if (!self.embedded) {
        self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemClose
                                                                                             target:self action:@selector(close)];
    }
    // From iOS 26 a sheet short of full height is Liquid Glass the system draws; a fill here would cover it. In the
    // player's column the player's background shows through.
    if (self.embedded) self.tableView.backgroundColor = UIColor.clearColor;
    else if (@available(iOS 26.0, *)) self.tableView.backgroundColor = UIColor.clearColor;
    _empty = [UILabel new];
    _empty.text = SGL(@"settings.player.queue.empty", @"Nothing is playing next.");
    _empty.font = SGCategoryCappedFont(UIFontTextStyleBody, UIFontWeightRegular, UIContentSizeCategoryAccessibilityMedium);
    _empty.textColor = SGRSecondary();
    _empty.textAlignment = NSTextAlignmentCenter;
    _empty.numberOfLines = 0;
    _upNext = [[SGRQueueUpNextHeader alloc] initWithReuseIdentifier:nil];
    _covers = [NSCache new];
    _coming = [NSMutableDictionary dictionary];
    self.tableView.accessibilityIdentifier = @"retrine.queue";
    [self takeState:SGPlayerState()];
    SGAddPlayerStateObserver(self);
    // Both are posted on the main thread.
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    [center addObserver:self selector:@selector(showBlend) name:SGAutoMixTransitionDidChangeNotification object:nil];
    [center addObserver:self selector:@selector(showBlend) name:SGAutoMixPlayerOptionsDidChangeNotification object:nil];
}

// Only the upcoming section owns the transition from current to next, never History.
- (void)showBlend {
    NSString *text = blendInto(_tracks.firstObject);
    SGRQueueBlendView *blend = _upNext.blend;
    if (blend.label.text == text || [blend.label.text isEqualToString:text]) return;
    [blend setText:text];
    [_upNext setNeedsLayout];
    [self.tableView beginUpdates];
    [self.tableView endUpdates];
}

// The Up Next header's height for the table's width: the heading, and the blend when there is one, measured at the
// margins the header was last given (the table's own until it has been laid out once).
- (CGFloat)upNextHeight {
    UITableView *table = self.tableView;
    SGRQueueBlendView *blend = _upNext.blend;
    _upNext.title.font = SGCategoryCappedFont(UIFontTextStyleHeadline, UIFontWeightSemibold, UIContentSizeCategoryAccessibilityMedium);
    BOOL showsBlend = blend.label.text.length > 0;
    blend.hidden = !showsBlend;
    if (UIEdgeInsetsEqualToEdgeInsets(blend.layoutMargins, UIEdgeInsetsZero)) blend.layoutMargins = table.layoutMargins;
    return [_upNext headingHeight] + (showsBlend ? [blend heightForWidth:table.bounds.size.width] : 0);
}

- (void)close {
    [self dismissViewControllerAnimated:YES completion:nil];
}

// Coming on screen, first or again with its rows kept, in a window already (viewWillAppear: is too early for one): each
// row shown asks for its cover, one set up off screen or cancelled when the list went away included (coverOf: asks
// nothing for a cover in or on its way), and takes it as it lands.
- (void)viewIsAppearing:(BOOL)animated {
    [super viewIsAppearing:animated];
    for (NSIndexPath *path in self.tableView.indexPathsForVisibleRows) [self coverOf:[self trackAt:path]];
}

// Closed, or the side column gone: no row waits for a cover, and viewIsAppearing: asks again for the rows shown.
- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    [self stopCoversExcept:nil];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previous {
    [super traitCollectionDidChange:previous];
    _empty.font = SGCategoryCappedFont(UIFontTextStyleBody, UIFontWeightRegular, UIContentSizeCategoryAccessibilityMedium);
}

#pragma mark - the player

- (void)takeState:(SPTPlayerState *)state {
    if (!queueValue(state, @"queueRevision") || ![SGPlayerInstance() respondsToSelector:@selector(fetchQueue:on:)]) {
        [self showTracks:SGPlayerUpcomingTracks(state, kMaxRows)
                   past:[state.reverse isKindOfClass:NSArray.class] ? state.reverse.reverseObjectEnumerator.allObjects : @[]
                current:state.track];
        return;
    }
    NSArray *key = @[queueValue(state, @"playbackId") ?: NSNull.null,
                     queueValue(state, @"queueRevision") ?: NSNull.null,
                     trackIdentity(state.track) ?: SGURIString(state.track.URI) ?: @""];
    if ([_reportedKey isEqual:key]) return;
    if (_fetching) return;
    _reportedKey = key;
    [self refreshQueue];
}

- (void)showTracks:(NSArray *)next past:(NSArray *)past current:(SPTPlayerTrack *)current {
    _tracks = queueTracks(next, kMaxRows, NO);
    NSArray *history = queueTracks(past, NSUIntegerMax, YES);
    _history = history.count > kHistoryRows ? [history subarrayWithRange:NSMakeRange(history.count - kHistoryRows, kHistoryRows)] : history;
    _current = current;
    NSArray *signature = @[signatureOf(_history), signatureOf(current ? @[current] : @[]), signatureOf(_tracks)];
    if (![_signature isEqual:signature]) {
        _signature = signature;
        NSMutableSet<NSString *> *listed = [NSMutableSet set];
        for (SPTPlayerTrack *track in [[_history arrayByAddingObjectsFromArray:current ? @[current] : @[]] arrayByAddingObjectsFromArray:_tracks]) {
            NSString *uri = SGURIString(track.URI);
            if (uri) [listed addObject:uri];
        }
        [self stopCoversExcept:listed];
        self.tableView.backgroundView = _tracks.count || _history.count || current ? nil : _empty;
        [self.tableView reloadData];
    }
    [self showBlend];
}

- (void)refreshQueue {
    id<SGRQueuePlayer> player = SGPlayerInstance();
    SPTPlayerState *state = SGPlayerState();
    [self showTracks:SGPlayerUpcomingTracks(state, kMaxRows)
               past:[state.reverse isKindOfClass:NSArray.class] ? state.reverse.reverseObjectEnumerator.allObjects : @[]
            current:state.track];
    if (![player respondsToSelector:@selector(fetchQueue:on:)]) return;
    _fetching = YES;
    NSArray *reported = _reportedKey;
    __weak typeof(self) weakSelf = self;
    [player fetchQueue:^(id<SGRQueueSnapshot> queue) {
        typeof(self) self = weakSelf;
        if (!self) return;
        self->_fetching = NO;
        if (![queue respondsToSelector:@selector(nextTracks)] || ![queue respondsToSelector:@selector(prevTracks)] ||
            ![queue respondsToSelector:@selector(track)] ||
            (queue.nextTracks && ![queue.nextTracks isKindOfClass:NSArray.class]) ||
            (queue.prevTracks && ![queue.prevTracks isKindOfClass:NSArray.class])) return;
        [self showTracks:queue.nextTracks past:queue.prevTracks current:queue.track];
        // A report received while fetching must not be lost.
        if ([self->_reportedKey isEqual:reported]) [self takeState:SGPlayerState()];
    } on:dispatch_get_main_queue()];
}

- (void)playerStateDidReport:(SPTPlayerState *)state {
    if (self.isViewLoaded) [self takeState:state];
}

- (void)playerStateDidChange:(SPTPlayerState *)state {
    if (self.isViewLoaded) [self takeState:state];
}

#pragma mark - the covers

// What a row shows until its cover is in, or for a track without one: the shape the cover takes, faintly.
static UIImage *coverPlaceholder(void) {
    static UIImage *placeholder;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        CGSize size = CGSizeMake(kCoverSide, kCoverSide);
        placeholder = [[[UIGraphicsImageRenderer alloc] initWithSize:size] imageWithActions:^(UIGraphicsImageRendererContext *context) {
            [[UIColor colorWithWhite:1 alpha:0.12] setFill];
            UIRectFill((CGRect){CGPointZero, size});
        }];
    });
    return placeholder;
}

// The cover the metadata names for `track` once it is in; until then nil, and it is asked for once, only while the list
// is on screen (a row set up as it goes away would start a download nothing cancels). Rows showing the track take it as
// it lands.
- (UIImage *)coverOf:(SPTPlayerTrack *)track {
    NSString *uri = SGURIString(track.URI);
    if (!uri) return nil;
    UIImage *cover = [_covers objectForKey:uri];
    if (cover) return cover;
    if (_coming[uri] || !self.viewIfLoaded.window) return nil;
    __weak typeof(self) weakSelf = self;
    NSProgress *coming = SGRPlayerTrackCover(track, YES, ^(UIImage *image) {
        typeof(self) self = weakSelf;
        if (!self) return;
        [self->_coming removeObjectForKey:uri];
        if (!image) return;
        [self->_covers setObject:image forKey:uri];
        if (self.isViewLoaded) [self showCoverOf:uri];
    });
    // Nil when there was nothing to fetch, `done` having run already.
    if (coming) _coming[uri] = coming;
    return nil;
}

// Cancels the covers on their way for every track but those in `kept` (all of them for nil).
- (void)stopCoversExcept:(NSSet<NSString *> *)kept {
    for (NSString *uri in _coming.allKeys) {
        if ([kept containsObject:uri]) continue;
        [_coming[uri] cancel];
        [_coming removeObjectForKey:uri];
    }
}

- (void)showCoverOf:(NSString *)uri {
    NSMutableArray<NSIndexPath *> *rows = [NSMutableArray array];
    for (NSIndexPath *path in self.tableView.indexPathsForVisibleRows) {
        SPTPlayerTrack *track = [self trackAt:path];
        if ([SGURIString(track.URI) isEqualToString:uri]) [rows addObject:path];
    }
    if (rows.count) [self.tableView reconfigureRowsAtIndexPaths:rows];
}

- (SPTPlayerTrack *)trackAt:(NSIndexPath *)path {
    NSArray<SPTPlayerTrack *> *tracks = path.section == 0 ? _history : path.section == 1 ? (_current ? @[_current] : @[]) : _tracks;
    return path.row >= 0 && path.row < (NSInteger)tracks.count ? tracks[(NSUInteger)path.row] : nil;
}

#pragma mark - the list

- (NSInteger)numberOfSectionsInTableView:(UITableView *)table { return 3; }

- (UIView *)tableView:(UITableView *)table viewForHeaderInSection:(NSInteger)section {
    return section == 2 && _tracks.count ? _upNext : nil;
}

- (CGFloat)tableView:(UITableView *)table heightForHeaderInSection:(NSInteger)section {
    return section == 2 && _tracks.count ? [self upNextHeight] : UITableViewAutomaticDimension;
}

- (NSString *)tableView:(UITableView *)table titleForHeaderInSection:(NSInteger)section {
    if (section == 0) return _history.count ? SGL(@"settings.player.queue.history", @"History") : nil;
    if (section == 1) return _current ? SGL(@"settings.player.queue.now", @"Now Playing") : nil;
    return nil;
}

- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section {
    return section == 0 ? (NSInteger)_history.count : section == 1 ? (_current ? 1 : 0) : (NSInteger)_tracks.count;
}

- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell = [table dequeueReusableCellWithIdentifier:@"track"]
        ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"track"];
    cell.backgroundColor = [UIColor colorWithWhite:1 alpha:0.08];
    SPTPlayerTrack *track = [self trackAt:path];
    NSString *title = track.trackTitle, *artist = track.artistName.length ? track.artistName : nil;
    UIListContentConfiguration *content = [UIListContentConfiguration subtitleCellConfiguration];
    content.text = title;
    content.secondaryText = artist;
    content.textProperties.color = SGRPrimary();
    content.textProperties.font = SGCategoryCappedFont(UIFontTextStyleBody, UIFontWeightRegular, UIContentSizeCategoryAccessibilityMedium);
    content.textProperties.numberOfLines = 1;
    content.secondaryTextProperties.color = SGRSecondary();
    content.secondaryTextProperties.font = SGCategoryCappedFont(UIFontTextStyleSubheadline, UIFontWeightRegular, UIContentSizeCategoryAccessibilityMedium);
    content.secondaryTextProperties.numberOfLines = 1;
    content.image = [self coverOf:track] ?: coverPlaceholder();
    content.imageProperties.reservedLayoutSize = CGSizeMake(kCoverSide, kCoverSide);
    content.imageProperties.maximumSize = CGSizeMake(kCoverSide, kCoverSide);
    content.imageProperties.cornerRadius = SGRRadiusThumb;
    cell.contentConfiguration = content;
    cell.isAccessibilityElement = YES;
    cell.accessibilityLabel = artist ? [NSString stringWithFormat:@"%@, %@", title, artist] : title;
    BOOL playable = path.section == 2;
    cell.accessibilityTraits = playable ? UIAccessibilityTraitButton : UIAccessibilityTraitStaticText;
    cell.selectionStyle = playable ? UITableViewCellSelectionStyleDefault : UITableViewCellSelectionStyleNone;
    return cell;
}

- (void)tableView:(UITableView *)table willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)path {
    // A prepared cell can return without another cellForRow: (even after its download failed).
    UIImage *image = [self coverOf:[self trackAt:path]];
    UIListContentConfiguration *content = (id)cell.contentConfiguration;
    if (image && image != content.image) {
        content.image = image;
        cell.contentConfiguration = content;
    }
}

- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)path {
    [table deselectRowAtIndexPath:path animated:YES];
    if (path.section != 2 || path.row < 0 || path.row >= (NSInteger)_tracks.count) return;
    id<SPTPlayer> player = SGPlayerInstance();
    if (![player respondsToSelector:@selector(skipToNextTrackWithOptions:track:)]) return;
    [player skipToNextTrackWithOptions:nil track:_tracks[(NSUInteger)path.row]];
    if (!self.embedded) [self close];
}

@end

#pragma mark - opening it

NSNotificationName const SGRQueueSheetPlacedNotification = @"SGRQueueSheetPlaced";

@interface SGRQueueSheet : UINavigationController
@end
@implementation SGRQueueSheet
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    if (!self.isBeingDismissed)
        [NSNotificationCenter.defaultCenter postNotificationName:SGRQueueSheetPlacedNotification object:self.view];
}
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [NSNotificationCenter.defaultCenter postNotificationName:SGRQueueSheetPlacedNotification object:self.view];
}
- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [NSNotificationCenter.defaultCenter postNotificationName:SGRQueueSheetPlacedNotification object:nil];
}
@end

// The controller on top in `from`'s window, through whatever is presented over it; the key window's without one.
static UIViewController *topIn(UIView *from) {
    UIViewController *top = from.window.rootViewController;
    if (!top) return SGTopController();
    while (top.presentedViewController && !top.presentedViewController.isBeingDismissed) top = top.presentedViewController;
    return top;
}

UIViewController *SGRPlayerQueueList(void) {
    SGRPlayerQueueController *list = [SGRPlayerQueueController new];
    list.embedded = YES;
    return list;
}

void SGRPlayerShowQueue(UIView *from) {
    UINavigationController *navigation = [[SGRQueueSheet alloc] initWithRootViewController:[SGRPlayerQueueController new]];
    navigation.modalPresentationStyle = UIModalPresentationPageSheet;
    SGPresentDark(navigation);
    UISheetPresentationController *sheet = navigation.sheetPresentationController;
    sheet.detents = @[UISheetPresentationControllerDetent.mediumDetent, UISheetPresentationControllerDetent.largeDetent];
    sheet.prefersGrabberVisible = YES;
    sheet.prefersEdgeAttachedInCompactHeight = YES;
    sheet.prefersScrollingExpandsWhenScrolledToEdge = YES;
    // Picked from the system menu, which is still going away: the sheet waits for it, as the sound panel does.
    __weak UIView *weakFrom = from;
    __block int tries = 0;
    __block void (^present)(void);
    present = ^{
        UIViewController *top = topIn(weakFrom);
        if ((top.isBeingDismissed || top.isBeingPresented || top.transitionCoordinator) && ++tries < 20) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), present);
            return;
        }
        present = nil;
        if (!top) return;
        if ([top isKindOfClass:UINavigationController.class]
            && [((UINavigationController *)top).viewControllers.firstObject isKindOfClass:SGRPlayerQueueController.class]) return;
        [top presentViewController:navigation animated:YES completion:nil];
    };
    dispatch_async(dispatch_get_main_queue(), present);
}
