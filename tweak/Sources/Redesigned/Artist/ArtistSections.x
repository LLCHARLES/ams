// Artist redesign: the Music list without the artist's videos (and, each on its own switch, without the Artist pick,
// the Release Countdown and About), and nothing of it painted over the field.
//
// Tree (trees/clean/artist/05.txt, the Music list top to bottom): Popular, Artist pick, Popular releases and
// its Show all, Featuring, Release Countdown, Music videos, Watch more from…, About, Artist playlists, Fans
// also like, Appears on. Every section is three Element_List cells in a row -- a 16pt spacer, a heading
// (Components.UI.SectionHeadingHome) and what the section holds -- and every kind of content carries an
// identifier of its own, in any language: Components.UI.RetrievalRowElementUI (tracks), PinnedItemUI (the
// pick), HomeCard (a carousel), UpcomingReleaseRow, CreatorBiographyCard (About),
// Components.UI.MusicVideoShelfHeader and WatchFeedCarouselEntryPointElement (videos).
//
// So the rule is by kind, never by the heading's words, which are the app's language: a hidden section's content
// reports no height, and so do the heading and the spacer in the two cells before it. They were sized before it, so
// the list is asked to lay out again once they are known. Every carousel is the same kind whatever it holds,
// so the carousels all stay; merch has a tab of its own, which ArtistField.x takes away. With a section's switch
// off (Artist.h) its content is any other cell and stays. The pick's, the countdown's and About's identifiers are
// strings of the 9.1.78 and 9.1.90 binaries (About's as its two labels', so it matches by prefix).
//
// A dropped cell is 0 tall but what it holds keeps the height it measured at, hidden and cut off by the
// cell: content squeezed to 0 breaks Spotify's required constraints on every pass (Album/AlbumSections.x).
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Artist.h"

static char kSettledKey, kKindsKey, kDroppedKey, kInvalidateKey;

// The "You liked" row's heart sits on a 24pt black disc at the avatar's corner, a ring on any field but black
// (device 2026-10-08). The disc goes; a soft shadow keeps the heart readable on the photo.
static void clearLikedBadge(UIView *cell) {
    SGForEachView(cell, ^(UIView *row) {
        if (![row.accessibilityIdentifier isEqualToString:@"Components.UI.LikedSongs.Row"]) return;
        SGForEachView(row, ^(UIView *disc) {
            CGSize size = disc.bounds.size;
            if (size.width > 30 || size.width != size.height || !SGIsBaseSurface(disc.layer.backgroundColor)) return;
            disc.backgroundColor = UIColor.clearColor;
            disc.clipsToBounds = NO;
            disc.layer.shadowColor = UIColor.blackColor.CGColor;
            disc.layer.shadowOpacity = 0.5;
            disc.layer.shadowRadius = 2;
            disc.layer.shadowOffset = CGSizeZero;
        });
    });
}
typedef NS_ENUM(NSInteger, SGRArtistCell) {
    SGRArtistCellOther,
    SGRArtistCellSpacer,
    SGRArtistCellHeading,
    // The sections with a switch, from here on: dropped with their heading and spacer while it is on.
    SGRArtistCellVideos,
    SGRArtistCellPick,
    SGRArtistCellCountdown,
    SGRArtistCellAbout,
};
static BOOL hidden[SGRArtistCellAbout + 1];   // by kind, read at launch
static __unsafe_unretained NSString *const dropped[] = {nil, nil, nil, @"the videos", @"the Artist pick", @"the Release Countdown", @"About"};

static BOOL listenersInAbout;

BOOL SGRArtistListenersInAbout(void) {
    return listenersInAbout && !hidden[SGRArtistCellAbout];
}

static SGRArtistCell kindOf(UIView *content, CGFloat height) {
    __block SGRArtistCell kind = SGRArtistCellOther;
    SGForEachView(content, ^(UIView *v) {
        NSString *identifier = v.accessibilityIdentifier;
        if (kind != SGRArtistCellOther || !identifier.length) return;
        if ([identifier isEqualToString:@"Components.UI.MusicVideoShelfHeader"] ||
            [identifier isEqualToString:@"Music-Videos.Video-Card-Carousel"] ||
            [identifier isEqualToString:@"WatchFeedCarouselEntryPointElement"]) kind = SGRArtistCellVideos;
        else if ([identifier isEqualToString:@"Components.UI.PinnedItemUI"]) kind = SGRArtistCellPick;
        else if ([identifier isEqualToString:@"Components.UI.UpcomingReleaseRow"]) kind = SGRArtistCellCountdown;
        else if ([identifier hasPrefix:@"Components.UI.CreatorBiographyCard"]) kind = SGRArtistCellAbout;
        else if ([identifier isEqualToString:@"Components.UI.SectionHeadingHome"]) kind = SGRArtistCellHeading;
    });
    if (kind == SGRArtistCellOther && height <= 16.5 && content.subviews.count <= 1) {
        __block BOOL empty = YES;
        SGForEachView(content, ^(UIView *v) { if (v.accessibilityIdentifier.length) empty = NO; });
        if (empty) kind = SGRArtistCellSpacer;
    }
    return kind;
}

static NSMutableDictionary<NSIndexPath *, NSNumber *> *kindsOf(UICollectionView *list) {
    NSMutableDictionary *kinds = objc_getAssociatedObject(list, &kKindsKey);
    if (!kinds) {
        kinds = [NSMutableDictionary dictionary];
        objc_setAssociatedObject(list, &kKindsKey, kinds, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return kinds;
}

static NSMutableSet<NSIndexPath *> *droppedOf(UICollectionView *list) {
    NSMutableSet *dropped = objc_getAssociatedObject(list, &kDroppedKey);
    if (!dropped) {
        dropped = [NSMutableSet set];
        objc_setAssociatedObject(list, &kDroppedKey, dropped, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return dropped;
}

static UICollectionView *listOf(UIView *cell) {
    for (UIView *v = cell.superview; v; v = v.superview) {
        if ([v isKindOfClass:UICollectionView.class]) return (UICollectionView *)v;
    }
    return nil;
}

static char kPageListKey;

// Bumped each time a different page is found. A cell measured before Spotify names its page keeps a NO only until then.
static NSInteger pagesFound;
static __weak UIView *lastPage;

// Whether the cell is a row of the page's own list: a card inside a carousel is a cell of the same class, and its row
// decides. Worked out once the cell is in a window and kept on it, since a cell never leaves its list nor the list its
// page; every cell of the class asks on every pass, Home's and Search's included. Kept as -1 for YES, or as
// pagesFound when it said NO.
static BOOL onPageList(UICollectionViewCell *cell) {
    NSNumber *known = objc_getAssociatedObject(cell, &kPageListKey);
    if (known.integerValue == -1) return YES;
    if (known && known.integerValue == pagesFound) return NO;
    UICollectionView *list = listOf(cell);
    UIView *page = list && ![listOf(list) isKindOfClass:UICollectionView.class] ? SGRArtistPageOf(cell) : nil;
    if (page && page != lastPage) {
        lastPage = page;
        pagesFound++;
    }
    if (cell.window) objc_setAssociatedObject(cell, &kPageListKey, @(page ? -1 : pagesFound), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return page != nil;
}

// The cell `back` items before `path` in the list, across the end of a section if it has to.
static NSIndexPath *before(UICollectionView *list, NSIndexPath *path, NSInteger back) {
    NSInteger section = path.section, item = path.item - back;
    while (item < 0 && section > 0) {
        section--;
        item += [list numberOfItemsInSection:section];
    }
    return item >= 0 ? [NSIndexPath indexPathForItem:item inSection:section] : nil;
}

// Derive suppression from the current kinds, not from index paths that used to hold hidden content.
// A heading can be measured before or after its content; either order reaches the same answer.
static void recordKind(UICollectionView *list, NSIndexPath *path, SGRArtistCell kind) {
    NSMutableDictionary *kinds = kindsOf(list);
    if (kinds[path] && [kinds[path] integerValue] == kind) return;
    kinds[path] = @(kind);
    NSMutableSet *dropped = [NSMutableSet set];
    for (NSIndexPath *content in kinds) {
        if ([kinds[content] integerValue] < SGRArtistCellVideos) continue;
        [dropped addObject:content];
        NSIndexPath *heading = before(list, content, 1);
        if (!heading || [kinds[heading] integerValue] != SGRArtistCellHeading) continue;
        [dropped addObject:heading];
        NSIndexPath *spacer = before(list, content, 2);
        if (spacer && [kinds[spacer] integerValue] == SGRArtistCellSpacer) [dropped addObject:spacer];
    }
    if ([dropped isEqualToSet:droppedOf(list)]) return;
    objc_setAssociatedObject(list, &kDroppedKey, dropped, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (objc_getAssociatedObject(list, &kInvalidateKey)) return;
    objc_setAssociatedObject(list, &kInvalidateKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    __weak UICollectionView *weakList = list;
    dispatch_async(dispatch_get_main_queue(), ^{
        UICollectionView *current = weakList;
        objc_setAssociatedObject(current, &kInvalidateKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [current.collectionViewLayout invalidateLayout];
    });
}

// Reloads and insert/delete/move/reload transactions change what every index path means. The layout
// callback covers both ordinary updates and diffable-data-source transactions.
static void forgetKinds(UICollectionView *list) {
    if (!objc_getAssociatedObject(list, &kKindsKey)) return;
    objc_setAssociatedObject(list, &kKindsKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(list, &kDroppedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

%hook UICollectionView
- (void)reloadData {
    forgetKinds((UICollectionView *)self);
    %orig;
}
%end

%hook UICollectionViewLayout
- (void)prepareForCollectionViewUpdates:(NSArray<UICollectionViewUpdateItem *> *)updates {
    UICollectionView *list = ((UICollectionViewLayout *)self).collectionView;
    forgetKinds(list);
    %orig;
}
%end

static NSMutableSet<NSString *> *sg_loggedMessages;
#define kLogFormat @"redesign artist: %@"

%hook _TtC12Element_List18CollectionViewCell
- (UICollectionViewLayoutAttributes *)preferredLayoutAttributesFittingAttributes:(UICollectionViewLayoutAttributes *)attributes {
    UICollectionViewCell *cell = (UICollectionViewCell *)self;
    // Only the page's own list: a card inside a carousel is a cell of the same class, and its row decides.
    BOOL page = onPageList(cell) && attributes.indexPath;
    UICollectionView *list = page ? listOf(cell) : nil;
    if (!page) {
        if (objc_getAssociatedObject(cell, &kSettledKey)) SGRRestoreCell(cell, &kSettledKey);
        return %orig;
    }
    UICollectionViewLayoutAttributes *result = %orig;
    NSIndexPath *path = attributes.indexPath;
    UIView *content = cell.contentView.subviews.firstObject ?: cell.contentView;
    SGRArtistCell kind = kindOf(content, result.size.height);
    BOOL hide = kind >= SGRArtistCellVideos && hidden[kind];
    if (kind >= SGRArtistCellVideos && !hide) kind = SGRArtistCellOther;
    recordKind(list, path, kind);

    if (hide) {
        SGLogOnce(&sg_loggedMessages, [dropped[kind] stringByAppendingString:@" dropped from the Music list"], kLogFormat);
    }
    if (!hide && ![droppedOf(list) containsObject:path]) {
        if (objc_getAssociatedObject(cell, &kSettledKey)) SGRRestoreCell(cell, &kSettledKey);
        return result;
    }
    SGRCollapseCell(cell, MAX(1, result.size.height), &kSettledKey);
    result.size = CGSizeMake(result.size.width, 0);
    return result;
}

// The cell's own passes size the content to the cell again.
- (void)layoutSubviews {
    %orig;
    UICollectionViewCell *cell = (UICollectionViewCell *)self;
    NSNumber *settled = objc_getAssociatedObject(self, &kSettledKey);
    if (settled) SGRCollapseCell(cell, settled.doubleValue, &kSettledKey);
    if (onPageList(cell)) {
        // What the cell paints over the field -- the "You liked" row, every carousel's collection and the
        // fade Popular's "See more" draws over its last track (device, trees/continuous/3.txt 2026-09-18).
        SGRClearCellPaint(cell);
        clearLikedBadge(cell);
    }
}

- (void)prepareForReuse {
    %orig;
    if (objc_getAssociatedObject(self, &kSettledKey)) SGRRestoreCell((UICollectionViewCell *)self, &kSettledKey);
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    hidden[SGRArtistCellVideos] = SGEnabled(SGRKeyArtistHideVideos);
    hidden[SGRArtistCellPick] = SGHidden(SGRKeyArtistHidePick);
    hidden[SGRArtistCellCountdown] = SGHidden(SGRKeyArtistHideCountdown);
    hidden[SGRArtistCellAbout] = SGHidden(SGRKeyArtistHideAbout);
    listenersInAbout = SGFlag(SGRKeyArtistListenersInAbout, NO);
    %init;
    SGRequireClasses(@[@"_TtC12Element_List18CollectionViewCell"]);
}
