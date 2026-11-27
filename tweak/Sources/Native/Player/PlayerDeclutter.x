// Player declutter: hides parts of the full screen player, one switch each on the Player page. Cards
// under the player are Element_List cells; a hidden one reports zero height when the list sizes it,
// so the list closes up around it (the 24pt gap between cards stays). Player buttons go invisible but
// keep their place, so their row stays centered. A hidden lyric preview gives its room to the cover.
//
// Trees (trees/now-playing*.txt): every card is a CollectionViewCell whose content view names the
// page (NowPlaying_ScrollAPI) and whose subtree names the card. Player rows are the UIStackView of each NowPlaying_ModesImpl unit: playback controls
// hold shuffle, previous, play, next, repeat; the footer holds connect, a hidden button, share
// and the queue; track info ends with the add-to button.
#import "Core/SGCore.h"
#import "Shared/AdBlock/AdBlock.h"
#import "NowPlaying.h"
#import "Native/Declutter/Declutter.h"

// Like the other switches, the inline preview setting takes effect at launch.
static BOOL sg_hideLyricsInline;

#pragma mark - cards and sections

static const SGNativeMarkerRule cards[] = {
    {@"Lyrics_CardElementImpl", SGHideLyricsCard},
    {@"CreatorBiography", SGHideAboutArtist},
    {@"ArtistAbout", SGHideAboutArtist},
    {@"VideoRecommendations", SGHideRelatedVideos},
    {@"SongDNA_", SGHideSongDNA},
    {@"LiveEvents_", SGHideLiveEvents},
    {@"WatchFeed_", SGHideExploreArtist},
    {@"Creator_Credits", SGHideCredits},
    {@"CreatorElements_Credits", SGHideCredits}, // Spotify 9.2.2's module name
    {@"Merch_", SGHideMerch},
    {@"RelatedContentRecommendations", SGHideRecommendations},
};

enum { kCards = sizeof(cards) / sizeof(cards[0]) };

static BOOL hasPlayerControls(UIView *view) {
    static char key;
    return SGFindRemembered(view, &key, ^BOOL(UIView *v) {
        return [v isKindOfClass:UISlider.class] || SGClassNamed(v.class, @"SliderNowPlaying")
            || SGClassNamed(v.class, @"PlaybackControlsGridView");
    }) != nil;
}

// Whether the cell is one of the player's cards: its own first subview or its content view's names the page.
// Spotify's cell has held the name in both places (Redesigned/Player/PlayerCards.x, and the trees above).
static BOOL onPlayer(UICollectionViewCell *cell) {
    return SGClassNamed(cell.subviews.firstObject.class, @"NowPlaying_ScrollAPI")
        || SGClassNamed(cell.contentView.subviews.firstObject.class, @"NowPlaying_ScrollAPI");
}

// An ad among the cards (a sponsored playlist's "Advertisement" card, 9.1.78): built of Encore's own views, it is
// told apart only by its identifiers, Components.UI.Ads.FullbleedDisplayAd and the like. Hide ads drops it.
static BOOL holdsAd(UIView *cell) {
    __block BOOL found = NO;
    SGForEachView(cell, ^(UIView *v) {
        if (!found && [v.accessibilityIdentifier hasPrefix:@"Components.UI.Ads."]) found = YES;
    });
    return found;
}

static NSString *hiddenKeyFor(UICollectionViewCell *cell) {
    // Only the player's cards are looked into: they name the page, which every other list's cells do not.
    BOOL hideAds = SGHidden(SGKeyHideAds), anyCard = SGNativeAnyMarkerHidden(cards, kCards);
    if (!(hideAds || anyCard) || !onPlayer(cell)) return nil;
    // A cell inside another card's list: the outer card decides.
    for (UIView *v = cell.superview; v; v = v.superview) {
        if ([v isKindOfClass:cell.class]) return nil;
    }
    // The ad card has been seen only with the name on its content view, so only that shape is searched for ads.
    if (hideAds && SGClassNamed(cell.contentView.subviews.firstObject.class, @"NowPlaying_ScrollAPI") && holdsAd(cell)) return SGKeyHideAds;
    return anyCard ? SGNativeHiddenMarkerIn(cell, cards, kCards) : nil;
}

%hook _TtC12Element_List18CollectionViewCell
- (UICollectionViewLayoutAttributes *)preferredLayoutAttributesFittingAttributes:(UICollectionViewLayoutAttributes *)attributes {
    UICollectionViewLayoutAttributes *result = %orig;
    NSString *key = hiddenKeyFor((UICollectionViewCell *)self);
    if (!key || hasPlayerControls((UIView *)self)) return result;
    result.size = CGSizeMake(result.size.width, 0);
    ((UIView *)self).clipsToBounds = YES;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ SGLog(@"collapsed the first card, %@", key); });
    return result;
}
%end

static NSString *const kPlayerListID = @"scrolling_npv_collection_view_accessibility_identifier";

static BOOL inPlayerScroll(UIView *view) {
    for (UIView *v = view.superview; v; v = v.superview) {
        if (SGClassNamed(v.class, @"NowPlaying_Scroll") || SGClassNamed(v.class, @"NPVScroll")) return YES;
        if (![v isKindOfClass:UICollectionView.class]) continue;
        UICollectionView *list = (UICollectionView *)v;
        if ([list.accessibilityIdentifier isEqualToString:kPlayerListID] ||
            SGClassNamed([list.dataSource class], @"NowPlaying_Scroll") ||
            SGClassNamed([list.delegate class], @"NowPlaying_Scroll")) return YES;
    }
    return NO;
}

static BOOL hidePlayerHeader(UIView *view) {
    return inPlayerScroll(view) && !hasPlayerControls(view);
}

static void trimCardSpacing(UICollectionView *list) {
    if (![list.accessibilityIdentifier isEqualToString:kPlayerListID] || list.dragging || list.decelerating) return;
    // Query the whole layout, not the cells on screen: a later card or footer must stay reachable.
    CGSize size = list.contentSize;
    CGFloat end = 0;
    for (UICollectionViewLayoutAttributes *a in [list.collectionViewLayout layoutAttributesForElementsInRect:(CGRect){CGPointZero, size}]) {
        if (a.hidden || a.alpha == 0 || a.size.height <= 0) continue;
        UIView *view;
        if (a.representedElementCategory == UICollectionElementCategoryCell) view = [list cellForItemAtIndexPath:a.indexPath];
        else if (a.representedElementCategory == UICollectionElementCategorySupplementaryView)
            view = [list supplementaryViewForElementKind:a.representedElementKind atIndexPath:a.indexPath];
        else continue;
        if (!view || (!view.hidden && view.alpha != 0)) end = MAX(end, CGRectGetMaxY(a.frame));
    }
    // Keep Spotify's inset separate from our deduction; it may have supplied a new one since layout.
    static char key;
    NSValue *previous = objc_getAssociatedObject(list, &key);
    CGPoint insets = previous.CGPointValue; // original, applied
    UIEdgeInsets inset = list.contentInset;
    CGFloat original = previous && inset.bottom == insets.y ? insets.x : inset.bottom;
    CGFloat blank = end > 0 ? MAX(0, size.height - end) : 0;
    // The scroll limit includes the adjusted inset too. Leaving its 34 pt on the phone
    // still lets the full-height controls page scroll past its bottom.
    CGFloat automatic = list.adjustedContentInset.bottom - inset.bottom;
    CGFloat bottom = blank > 0 ? -blank - automatic : original;
    if (inset.bottom == bottom) return;
    objc_setAssociatedObject(list, &key, blank ? [NSValue valueWithCGPoint:CGPointMake(original, bottom)] : nil,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    inset.bottom = bottom;
    list.contentInset = inset;
}

%group SGHiddenPlayerHeaders
%hook UICollectionView
- (void)layoutSubviews {
    %orig;
    trimCardSpacing(self);
}
%end

%hook _TtC12Element_List21SupplementaryItemView
- (UICollectionViewLayoutAttributes *)preferredLayoutAttributesFittingAttributes:(UICollectionViewLayoutAttributes *)attributes {
    UICollectionViewLayoutAttributes *result = %orig;
    if (!hidePlayerHeader((UIView *)self)) return result;
    // Don't change the list's proposed attributes: it can fit this header again after reuse.
    UICollectionViewLayoutAttributes *collapsed = [result copy];
    collapsed.size = CGSizeMake(result.size.width, 0);
    return collapsed;
}
- (void)layoutSubviews {
    %orig;
    UIView *view = (UIView *)self;
    static char key;
    NSNumber *priorAlpha = objc_getAssociatedObject(view, &key);
    if (hidePlayerHeader(view)) {
        if (view.alpha != 0) {
            objc_setAssociatedObject(view, &key, @(view.alpha), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            view.alpha = 0;
        }
    } else if (priorAlpha) {
        // A reused header (or one now holding controls) is Spotify's again.
        if (view.alpha == 0) view.alpha = priorAlpha.doubleValue;
        objc_setAssociatedObject(view, &key, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}
%end
%end

#pragma mark - player buttons, lyrics under the artwork

static BOOL vanish(UIView *view) {
    if (!view || view.alpha == 0) return NO;
    view.alpha = 0;
    view.userInteractionEnabled = NO;
    return YES;
}

// Re-layout once something went invisible, so the glass panes of Player.x follow.
static void finish(UIViewController *unit, BOOL changed) {
    if (changed) [unit.viewIfLoaded setNeedsLayout];
}

%hook _TtC20NowPlaying_ModesImpl28PlaybackControlsElementsUnit
- (void)viewDidLayoutSubviews {
    %orig;
    BOOL hideShuffle = SGHidden(SGHideShuffle), hideRepeat = SGHidden(SGHideRepeat);
    if (!hideShuffle && !hideRepeat) return;
    NSArray<UIView *> *items = SGRowIn(((UIViewController *)self).viewIfLoaded).arrangedSubviews;
    if (items.count != 5 || !SGHasClass(items[2], @"PlayButton")) return;
    BOOL changed = NO;
    if (hideShuffle) changed |= vanish(items[0]);
    if (hideRepeat) changed |= vanish(items[4]);
    finish((UIViewController *)self, changed);
}
%end

%hook _TtC20NowPlaying_ModesImpl18FooterElementsUnit
- (void)viewDidLayoutSubviews {
    %orig;
    BOOL hideConnect = SGHidden(SGHideConnect), hideQueue = SGHidden(SGHideQueue), hideShare = SGHidden(SGHideShare);
    if (!hideConnect && !hideQueue && !hideShare) return;
    BOOL changed = NO;
    for (UIView *item in SGRowIn(((UIViewController *)self).viewIfLoaded).arrangedSubviews) {
        if (item.hidden || item.bounds.size.width < 20) continue;
        if (SGHasClass(item, @"Connect")) {
            if (hideConnect) changed |= vanish(item);
        } else if (SGHasClass(item, @"QueueButton")) {
            if (hideQueue) changed |= vanish(item);
        } else if (item.bounds.size.width <= 48 && SGHasClass(item, @"EncoreButton")) {
            if (hideShare) changed |= vanish(item);
        }
    }
    finish((UIViewController *)self, changed);
}
%end

%hook _TtC20NowPlaying_ModesImpl23InformationElementsUnit
- (void)viewDidLayoutSubviews {
    %orig;
    if (!SGHidden(SGHideAddTo)) return;
    BOOL changed = NO;
    for (UIView *item in SGRowIn(((UIViewController *)self).viewIfLoaded).arrangedSubviews) {
        if (SGHasClass(item, @"AddToButton")) changed |= vanish(item);
    }
    finish((UIViewController *)self, changed);
}
%end

// Hidden, the preview takes no room either, whatever size it is asked for or given: Spotify's cell kept
// room under the cover for it, so a track with lyrics had a smaller cover pushed up over a blank band
// (issue #77). With the switch off the preview shows and its room is its own.
%hook _TtC22Lyrics_NPVContainerKit19LyricsContainerView
- (void)setHidden:(BOOL)hidden {
    %orig(sg_hideLyricsInline ? YES : hidden);
}
- (void)didMoveToWindow {
    %orig;
    if (sg_hideLyricsInline) ((UIView *)self).hidden = YES;
}
- (CGSize)intrinsicContentSize {
    return sg_hideLyricsInline ? CGSizeZero : %orig;
}
- (CGSize)sizeThatFits:(CGSize)size {
    return sg_hideLyricsInline ? CGSizeZero : %orig;
}
- (void)setFrame:(CGRect)frame {
    if (sg_hideLyricsInline) frame.size = CGSizeZero;
    %orig(frame);
}
%end

#pragma mark - the cover in the preview's room

// The bar's cover has a tilt view of its own, 40pt; the player's is about 354.
static const CGFloat kCoverMinWidth = 200;

// The tilt view takes the largest square of the plain view it sits in with the preview, centered on whole
// points, the way the Music app's cover fills its square. Bounds and a center, not a frame, since the tilt
// view carries Spotify's tilt while the cover is inspected. A square under kCoverMinWidth is left alone.
static void fillRoom(UIView *tilt) {
    CGRect room = tilt.superview.bounds;
    CGFloat side = MIN(room.size.width, room.size.height);
    if (side < kCoverMinWidth) return;
    CGPoint middle = CGPointMake(round(CGRectGetMinX(room) + (room.size.width - side) / 2) + side / 2,
                                 round(CGRectGetMinY(room) + (room.size.height - side) / 2) + side / 2);
    CGRect bounds = (CGRect){tilt.bounds.origin, CGSizeMake(side, side)};
    if (CGRectEqualToRect(tilt.bounds, bounds) && CGPointEqualToPoint(tilt.center, middle)) return;
    tilt.bounds = bounds;
    tilt.center = middle;
    [tilt setNeedsLayout];
    static dispatch_once_t once;
    dispatch_once(&once, ^{ SGLog(@"native player: the cover fills its room, %.0fpt in %@", side, NSStringFromCGRect(room)); });
}

static Class tiltClass(void) {
    static Class tilt;
    if (!tilt) tilt = NSClassFromString(@"_TtC35CreativeWorkCommons_CoverArtTiltKit16CoverArtTiltView");
    return tilt;
}

// Only the player's own cover cell; the legacy and listening party cells are left as Spotify lays them out.
static BOOL inCoverCell(UIView *tilt) {
    static Class cell;
    if (!cell) cell = NSClassFromString(@"_TtC28NowPlaying_ContentLayersImpl16CoverArtCellImpl");
    for (UIView *v = tilt.superview; v; v = v.superview) {
        if ([v isKindOfClass:cell]) return YES;
    }
    return NO;
}

%hook _TtC28NowPlaying_ContentLayersImpl16CoverArtCellImpl
- (void)layoutSubviews {
    %orig;
    if (!sg_hideLyricsInline) return;
    SGForEachView((UIView *)self, ^(UIView *view) {
        if ([view isKindOfClass:tiltClass()]) fillRoom(view);
    });
}
%end

// Again before the tilt view lays out, for a pass of Spotify's that sizes it without the cell laying out.
// Before %orig, so the cover inside follows, and Player.x's corners and shadow and PlayerGestures.x's hold,
// which hook the same method and work after it, see the new size.
%hook _TtC35CreativeWorkCommons_CoverArtTiltKit16CoverArtTiltView
- (void)layoutSubviews {
    UIView *tilt = (UIView *)self;
    if (sg_hideLyricsInline && inCoverCell(tilt)) fillRoom(tilt);
    %orig;
}
%end

%ctor {
    if (!SGNativeUI()) return;
    sg_hideLyricsInline = SGHidden(SGHideLyricsInline);
    %init;
    // Unmarked section headers cannot be attributed to one card switch. Only hide
    // them when every card is switched off on the native Player page.
    BOOL allHidden = YES;
    for (size_t i = 0; i < kCards; i++) allHidden &= SGHidden(cards[i].key);
    if (allHidden) {
        %init(SGHiddenPlayerHeaders);
    }
    SGRequireClasses(@[
        @"_TtC12Element_List18CollectionViewCell",
        @"_TtC20NowPlaying_ModesImpl28PlaybackControlsElementsUnit",
        @"_TtC20NowPlaying_ModesImpl18FooterElementsUnit",
        @"_TtC20NowPlaying_ModesImpl23InformationElementsUnit",
        @"_TtC22Lyrics_NPVContainerKit19LyricsContainerView",
        @"_TtC28NowPlaying_ContentLayersImpl16CoverArtCellImpl",
        @"_TtC35CreativeWorkCommons_CoverArtTiltKit16CoverArtTiltView",
    ]);
}
