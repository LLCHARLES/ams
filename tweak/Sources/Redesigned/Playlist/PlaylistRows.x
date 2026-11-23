// Playlist redesign: the track rows on the field, the way the Music app has them -- no surface of their own,
// artwork with rounded corners, and a hairline from the text's edge between one row and the next.
//
// Tree (trees/clean/playlist/02.txt:164-247): a cell id=Playlist.ItemCell holds an Encore.ListRow painted the
// base surface, and in it Encore.ImageView 48x48 (the artwork), Track.Row.Content.Title,
// Track.Row.Content.Subtitle and, at the trailing edge, Components.UI.ContextMenuButton. The row's own paint
// is cleared here rather than left to the Kit's repaint hook, which only hears about a color when Spotify
// sets it and not when a reused cell already carries one.
//
// Spotify's type and its spacing are left alone: the row is 64pt for a title of 18pt, and a larger font of
// the Kit's would be cut off by the box the element framework measured for it.
//
// The pills over the first row (own-playlist/01.txt:33) are a cell of the list: Add, Mix, Notes, Video,
// Edit, Sort and Name & details. Unless switched off (SGRKeyPlaylistHideCuration), the row is closed up -- ListUXPlatform_LayoutKit.ListLayout gives every
// item its height, so the cell can only close up where the layout asks it how tall it wants to be -- and
// Sort and Mix are put on the ⋯ sheet instead (PlaylistMenu.x), where the rest of the row already is. The
// cell is handed over as it lays out, so the sheet has Spotify's own buttons to fire.
//
// Not every cell of the list is a track row. Under the tracks Spotify puts the extender -- Recommended
// songs, its rows and Refresh (ListUXPlatformConsumers_PlaylistExtenderImpl) -- and its heading and its
// Refresh cell paint the base surface over the field, where the black made bands of them (device,
// trees/continuous/2.txt 2026-09-20). So the paint comes off every cell of the page, the Kit's way, and
// only the row below is a row.
// The optional recommendation switch collapses that component instead. Spotify 9.1.90 mounts
// ListExtenderHeaderElement, ListExtenderTrackElement and ListExtenderRefreshElement in the
// cell's ElementContentView; ordinary playlist tracks belong to a different module.
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Redesigned/Kit/SGRPress.h"
#import "Playlist.h"

// Under the text rather than the whole row, as the Music app draws it; the trailing end clears the page margin.
static const CGFloat kHairline = 0.5, kHairlineGap = 12;

static char kRowKey, kTrackRowKey, kArtKey, kArtHolderKey, kSubtitleKey, kLineKey, kToolbarKey;

// Whether the curation pills close up (SGRKeyPlaylistHideCuration), read at launch.
static BOOL sg_hideCuration;
// Refreshed when a playlist opens, before its cells lay out; reopening also clears cached heights.
static BOOL sg_hideRecommendations;

static char kRecommendationHeightKey, kRecommendationStateKey, kRecommendationPreferenceKey;

@interface SGRPlaylistRecommendationState : NSObject
@property (nonatomic, weak) UIView *content;
@property (nonatomic) UIViewAutoresizing autoresizing;
@property (nonatomic) CGFloat height;
@property (nonatomic) BOOL hidden, clipped, accessibilityHidden, interactive;
@end
@implementation SGRPlaylistRecommendationState
@end

static BOOL isRecommendation(UICollectionViewCell *cell) {
    return SGClassNamed(object_getClass(cell.contentView), @"44ListUXPlatformConsumers_PlaylistExtenderImpl");
}

static void restoreRecommendation(UICollectionViewCell *cell) {
    SGRPlaylistRecommendationState *state = objc_getAssociatedObject(cell, &kRecommendationStateKey);
    if (!state) return;
    CGRect frame = cell.frame;
    frame.size.height = state.height;
    cell.frame = frame;
    if (cell.contentView == state.content) SGRRestoreCell(cell, &kRecommendationHeightKey);
    else objc_setAssociatedObject(cell, &kRecommendationHeightKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    state.content.hidden = state.hidden;
    state.content.autoresizingMask = state.autoresizing;
    cell.clipsToBounds = state.clipped;
    cell.accessibilityElementsHidden = state.accessibilityHidden;
    cell.userInteractionEnabled = state.interactive;
    objc_setAssociatedObject(cell, &kRecommendationStateKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void collapseRecommendation(UICollectionViewCell *cell, CGFloat naturalHeight) {
    SGRPlaylistRecommendationState *state = objc_getAssociatedObject(cell, &kRecommendationStateKey);
    if (state && state.content != cell.contentView) {
        restoreRecommendation(cell);
        state = nil;
    }
    if (!state) {
        state = [SGRPlaylistRecommendationState new];
        state.content = cell.contentView;
        state.hidden = cell.contentView.hidden;
        state.autoresizing = cell.contentView.autoresizingMask;
        state.height = cell.bounds.size.height;
        state.clipped = cell.clipsToBounds;
        state.accessibilityHidden = cell.accessibilityElementsHidden;
        state.interactive = cell.userInteractionEnabled;
        objc_setAssociatedObject(cell, &kRecommendationStateKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    SGRCollapseCell(cell, naturalHeight, &kRecommendationHeightKey);
    cell.userInteractionEnabled = NO;
    // ListLayout leaves a zero-sized, hidden prefetched cell at its old frame even after fitting.
    // Keep the cell itself collapsed as well as its layout attributes; its content keeps its natural height.
    CGRect frame = cell.frame;
    if (frame.size.height != 0) {
        frame.size.height = 0;
        cell.frame = frame;
    }
}

static void clearSurface(UIView *view) {
    UIColor *color = view.backgroundColor;
    if (color && SGIsBaseSurface(color.CGColor)) view.backgroundColor = UIColor.clearColor;
}

// `leading`: how far in from the row's leading edge the line starts; it ends SGRSideMargin short of the trailing edge,
// both mirrored right to left.
static void applyHairline(UIView *row, CGFloat leading, BOOL rtl) {
    CALayer *line = objc_getAssociatedObject(row, &kLineKey);
    if (!line) {
        line = [CALayer layer];
        line.backgroundColor = [UIColor colorWithWhite:1 alpha:0.12].CGColor;
        line.zPosition = 1;
        objc_setAssociatedObject(row, &kLineKey, line, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (line.superlayer != row.layer) [row.layer addSublayer:line];
    CGRect bounds = row.bounds;
    CGFloat width = MAX(0, bounds.size.width - leading - SGRSideMargin);
    CGRect frame = CGRectMake(rtl ? SGRSideMargin : leading, bounds.size.height - kHairline, width, kHairline);
    if (CGRectEqualToRect(line.frame, frame)) return;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    line.frame = frame;
    [CATransaction commit];
}

// Where the artwork has no Encore.ImageView of its own (Track.Row): the holder the picture is drawn in, a private
// class of the row kit that is told by its name. Kept on the row, as the lookups by identifier are.
static UIView *artHolderIn(UIView *row) {
    return SGFindRemembered(row, &kArtHolderKey, ^BOOL(UIView *view) {
        return [NSStringFromClass(view.class) hasSuffix:@"ImageViewHolder"];
    });
}

// A playlist's row is an Encore.ListRow; the songs liked by one artist have a Track.Row of the same kit.
static UIView *rowIn(UIView *cell) {
    return SGRFindByIdentifier(cell, @"Encore.ListRow", &kRowKey) ?: SGRFindByIdentifier(cell, @"Track.Row", &kTrackRowKey);
}

// YES when the cell holds a track row.
static BOOL applyRow(UIView *cell) {
    clearSurface(cell);
    UIView *row = rowIn(cell);
    // The Music app's highlight under the finger (SGRPress.h), on the rows only: not the pills or a heading.
    SGRPressRow(cell, row != nil);
    if (!row) return NO;
    clearSurface(row);

    // From the leading edge: right to left the artwork is on the right and the text ends at its left edge.
    BOOL rtl = row.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;
    CGFloat leading = SGRSideMargin + 48 + kHairlineGap;
    UIView *art = SGRFindByIdentifier(row, @"Encore.ImageView", &kArtKey) ?: artHolderIn(row);
    if (art) {
        if (art.layer.cornerRadius != SGRRadiusThumb) {
            art.layer.cornerRadius = SGRRadiusThumb;
            art.layer.cornerCurve = kCACornerCurveContinuous;
            art.clipsToBounds = YES;
        }
        CGRect frame = [row convertRect:art.bounds fromView:art];
        if (frame.size.width > 0) leading = (rtl ? row.bounds.size.width - CGRectGetMinX(frame) : CGRectGetMaxX(frame)) + kHairlineGap;
    }

    UIView *subtitle = SGRFindByIdentifier(row, @"Track.Row.Content.Subtitle", &kSubtitleKey);
    SGForEachView(subtitle, ^(UIView *v) {
        if (![v isKindOfClass:UILabel.class]) return;
        UILabel *label = (UILabel *)v;
        if (![label.textColor isEqual:SGRSecondary()]) label.textColor = SGRSecondary();
    });

    applyHairline(row, leading, rtl);
    return YES;
}

%hook _TtC35ListUXPlatform_FreeTierPlaylistImpl25ElementCollectionViewCell
- (void)layoutSubviews {
    %orig;
    UICollectionViewCell *cell = (UICollectionViewCell *)self;
    if (sg_hideRecommendations && isRecommendation(cell)) {
        NSNumber *natural = objc_getAssociatedObject(cell, &kRecommendationHeightKey);
        collapseRecommendation(cell, natural ? natural.doubleValue : cell.contentView.bounds.size.height);
    } else if (objc_getAssociatedObject(cell, &kRecommendationStateKey)) {
        restoreRecommendation(cell);
    }
    if (!SGRPlaylistHeaderOf(cell)) return;
    SGRClearCellPaint(cell);
    // A track row is not the curation row, so only the other cells are searched for its toolbar.
    if (!applyRow(cell)) SGRPlaylistTakeCuration(cell);
}

- (UICollectionViewLayoutAttributes *)preferredLayoutAttributesFittingAttributes:(UICollectionViewLayoutAttributes *)attributes {
    UICollectionViewCell *cell = (UICollectionViewCell *)self;
    BOOL hideRecommendation = sg_hideRecommendations && isRecommendation(cell);
    if (!hideRecommendation && objc_getAssociatedObject(cell, &kRecommendationStateKey)) restoreRecommendation(cell);
    UICollectionViewLayoutAttributes *result = %orig;
    if (hideRecommendation) {
        collapseRecommendation(cell, result.size.height);
        result.size = CGSizeMake(result.size.width, 0);
        return result;
    }
    if (!sg_hideCuration || !SGRFindByIdentifier((UIView *)self, SGRPlaylistCurationIdentifier, &kToolbarKey)) return result;
    result.size = CGSizeMake(result.size.width, 0);
    ((UIView *)self).clipsToBounds = YES;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ SGLog(@"redesign playlist: curation pills asked for a height, answered 0"); });
    return result;
}

- (void)prepareForReuse {
    restoreRecommendation((UICollectionViewCell *)self);
    %orig;
}
%end

%hook _TtC35ListUXPlatform_FreeTierPlaylistImpl17FTPViewController
- (void)viewWillAppear:(BOOL)animated {
    BOOL hidden = SGFlag(SGRKeyPlaylistHideRecommendations, NO);
    sg_hideRecommendations = hidden;
    %orig;
    UIView *page = ((UIViewController *)self).viewIfLoaded;
    NSNumber *previous = objc_getAssociatedObject(self, &kRecommendationPreferenceKey);
    objc_setAssociatedObject(self, &kRecommendationPreferenceKey, @(hidden), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (previous && previous.boolValue != hidden) {
        // ListLayout caches self-sizing heights; reopening must discard the collapsed measurements too.
        UICollectionView *list = (UICollectionView *)SGRFindByIdentifier(page, SGRPlaylistListIdentifier, NULL);
        [list reloadData];
    }
}
%end

#pragma mark - Spotify's chip row

// Spotify 9.2.0 gives the playlists it makes itself (the mixes, the charts) a row of chips over the first track --
// Video, Duplicate, Sort, Select (ListUXPlatformConsumers_DefaultToolbarImpl's DefaultToolbarElement: a view of the
// page's beside the list, placed by its frame, not a cell of the list) -- and holds it under the navigation bar once
// the list has scrolled past it. The redesign has no bar there, so the held row stood over the rows going by under
// it, across their names, with nothing behind it. It goes with the list instead: held, it fades over the first
// kChipFade of scroll past where it was held and takes no touch, and comes back as the list brings its place back.
// Duplicate and Select are nowhere else, so the row itself stays whatever Hide the curation pills says.
static const CGFloat kChipFade = 24;
static char kChipYKey, kChipPlaceKey, kChipFadedKey;

static void followChipRow(UIScrollView *list) {
    UIView *row = nil;
    for (UIView *sibling in list.superview.subviews) {
        if (SGClassNamed(sibling.class, @"DefaultToolbarElement")) { row = sibling; break; }
    }
    if (!row) return;
    // Where the row is in the list's content. While it moves with the list that stays the same, and is its place;
    // held, the row stands still and the difference is how far the list has gone on.
    CGFloat y = CGRectGetMinY(row.frame), place = y + list.contentOffset.y;
    NSNumber *lastY = objc_getAssociatedObject(list, &kChipYKey), *rest = objc_getAssociatedObject(list, &kChipPlaceKey);
    if (!rest || !lastY || fabs(lastY.doubleValue - y) > 0.01) {
        objc_setAssociatedObject(list, &kChipPlaceKey, rest = @(place), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (!lastY || lastY.doubleValue != y) objc_setAssociatedObject(list, &kChipYKey, @(y), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    CGFloat past = place - rest.doubleValue;
    CGFloat alpha = past <= 0 ? 1 : MAX(0, 1 - past / kChipFade);
    // Spotify's own alpha is left alone until the row has been faded here.
    BOOL faded = objc_getAssociatedObject(row, &kChipFadedKey) != nil;
    if (alpha >= 1 && !faded) return;
    if (fabs(row.alpha - alpha) > 0.001) row.alpha = alpha;
    row.userInteractionEnabled = alpha >= 1;
    row.accessibilityElementsHidden = alpha <= 0;
    if (faded != (alpha < 1)) objc_setAssociatedObject(row, &kChipFadedKey, alpha < 1 ? @YES : nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

// The playlist's own list class, so no other scroll view pays for this.
%hook _TtC35ListUXPlatform_FreeTierPlaylistImpl32FTPTouchCancellingCollectionView
- (void)setContentOffset:(CGPoint)offset {
    %orig;
    followChipRow((UIScrollView *)self);
}
%end

// The rows of the songs liked by one artist are another cell (a UITableView's, Track.Row painted the base surface)
// with the same row kit in it, so they get the playlist's row: no paint, rounded artwork, the hairline.
%hook SPTEncoreSwipeableTableViewCell
- (void)layoutSubviews {
    %orig;
    UIView *cell = (UIView *)self;
    if (!sgr_playlistRoot || !SGIsInside(cell, sgr_playlistRoot)) return;
    SGRClearCellPaint(cell);
    applyRow(cell);
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    sg_hideCuration = SGEnabled(SGRKeyPlaylistHideCuration);
    sg_hideRecommendations = SGFlag(SGRKeyPlaylistHideRecommendations, NO);
    %init;
    SGRequireClasses(@[@"_TtC35ListUXPlatform_FreeTierPlaylistImpl25ElementCollectionViewCell", @"SPTEncoreSwipeableTableViewCell"]);
}
