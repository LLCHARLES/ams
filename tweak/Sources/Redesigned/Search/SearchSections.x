// Search redesign: of the cells the Browse page lists, only the category cards stay. Every other cell reports no
// height, so the list closes up around it: the watch feed carousels (Playlists you can watch, Explore episodes for
// you), and the promos, showcases and ad cards the page can also carry (BrowseStructure's other cases in the binary,
// swift-fields.txt 2026-09-17), and any kind the server adds later. An allow list, as for Home's sections
// (Redesigned/Home/HomeSections.x): the page is the server's, and a new kind should not turn up on a redesigned Search.
// The carousels and the rest each have a switch (Search.h); a kind switched off stays at Spotify's height.
//
// Tree (trees/clean/search/01.txt): a cell of the list (id=BrowsePage.ContentScrollView) is an
// Element_List.CollectionViewCell whose content view is an ElementContentView over Browse_BrowsePageImpl.BrowseStructure,
// then an ElementView<BrowseStructure>, then the cell's own root:
//   Control<Box> id=Components.UI.CategoryCardBrowse   a category card 177x108 (:332)
//   UIView > UIView > UIStackView > ... WatchFeedCarouselEntryPointElement   a carousel 402x224 under its heading (:26-30)
//
// A collapsed cell keeps its content at the height it measured, hidden and cut off by the cell, the way Home's do: content
// squeezed to 0 with the cell breaks its constraints on every layout pass (Home.h, home perf 2026-09-17).
//
// The carousels are the page's first two sections, and the list keeps its spacing between sections whatever their
// height: collapsed, they still leave 16pt after the first and 24pt after the second (01.txt:30-31, :325), 40pt of black
// between the search field and the cards. So every cell of the list moves up by the spacing the collapsed cells above the
// first card leave, measured from the list's own layout attributes. The move is the cell's transform, set after UIKit
// applies the cell's attributes and on the cell's layout passes, so it holds through scrolling, reuse and reloads (a
// compositional list with the same shape on the iOS 27 simulator, 2026-09-17), and touches follow it. The list's content
// size loses the same gap at its end, so the last row ends as far above it as Spotify's layout has it. Spotify's content
// inset, which its collapsing header is worked out from, stays its own.
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Search.h"

NSString *const SGRSearchListIdentifier = @"BrowsePage.ContentScrollView";

typedef NS_ENUM(NSInteger, SGRSearchKind) {
    SGRSearchKindPending,   // the cell's root is not in yet: left as it is
    SGRSearchKindKeep,
    SGRSearchKindDrop,
};

// The items looked at from the top of the list for the first card before the gap is taken as none.
static const NSInteger kGapItems = 24;

static char kCollapsedKey;

static CGFloat sg_gap;
// Collapses and expansions so far, so a layout pass of the page measures again after one.
static NSUInteger sg_changes;
static __weak UICollectionView *sg_list;
// sg_list's content height as its layout last set it, before the gap was taken off.
static CGFloat sg_layoutHeight;
static BOOL sg_measureQueued;

static NSMutableSet<NSString *> *sg_loggedMessages;
#define kLogFormat @"redesign search: %@"

static BOOL isBrowseCell(UIView *content) {
    return SGClassNamed(object_getClass(content), @"Browse_BrowsePageImpl15BrowseStructure");
}

// What collapses, read at launch: the watch feed carousels (SGRKeySearchHideWatchFeeds) and every other kind but the
// cards (SGRKeySearchHideOther).
static BOOL sg_hideWatchFeeds, sg_hideOther;

// A carousel's cell holds its heading and WatchFeedCarouselEntryPointElement (01.txt:26-30, as on the artist page).
static BOOL isWatchFeed(UIView *root) {
    __block BOOL found = NO;
    SGForEachView(root, ^(UIView *v) {
        if (!found && [v.accessibilityIdentifier isEqualToString:@"WatchFeedCarouselEntryPointElement"]) found = YES;
    });
    return found;
}

static SGRSearchKind kindOf(UIView *root) {
    if (!root) return SGRSearchKindPending;
    if ([root.accessibilityIdentifier isEqualToString:@"Components.UI.CategoryCardBrowse"]) return SGRSearchKindKeep;
    // Both on, the default: no walk of the cell is needed to drop it.
    if (sg_hideWatchFeeds == sg_hideOther) return sg_hideOther ? SGRSearchKindDrop : SGRSearchKindKeep;
    return (isWatchFeed(root) ? sg_hideWatchFeeds : sg_hideOther) ? SGRSearchKindDrop : SGRSearchKindKeep;
}

// What a dropped cell holds, for the log: the first identifier in it, else its root's class.
static NSString *describe(UIView *root) {
    __block NSString *identifier = nil;
    SGForEachView(root, ^(UIView *v) {
        if (!identifier && v.accessibilityIdentifier.length) identifier = v.accessibilityIdentifier;
    });
    return identifier ?: NSStringFromClass(root.class);
}

static void shift(UICollectionViewCell *cell) {
    CGAffineTransform moved = CGAffineTransformMakeTranslation(0, -sg_gap);
    if (!CGAffineTransformEqualToTransform(cell.transform, moved)) cell.transform = moved;
}

// The top of the first item with a height, when every item above it has none; 0 when the list starts with one.
static CGFloat measure(UICollectionView *list) {
    BOOL collapsedAbove = NO;
    NSInteger seen = 0;
    NSInteger sections = list.numberOfSections;
    for (NSInteger section = 0; section < sections; section++) {
        NSInteger items = [list numberOfItemsInSection:section];
        for (NSInteger item = 0; item < items; item++) {
            if (++seen > kGapItems) return 0;
            UICollectionViewLayoutAttributes *attributes = [list layoutAttributesForItemAtIndexPath:[NSIndexPath indexPathForItem:item inSection:section]];
            if (!attributes) return 0;
            if (attributes.frame.size.height < 1) {
                collapsedAbove = YES;
                continue;
            }
            return collapsedAbove ? MAX(0, CGRectGetMinY(attributes.frame)) : 0;
        }
    }
    return 0;
}

void SGRSearchCloseGap(UICollectionView *list) {
    if (!list) return;
    static CGSize lastSize;
    static NSUInteger lastChanges = NSUIntegerMax;
    CGSize size = list.contentSize;
    if (list == sg_list && sg_changes == lastChanges && CGSizeEqualToSize(size, lastSize)) return;
    // A list not seen before has the height its layout gave it, none of the gap taken off yet.
    BOOL seen = list == sg_list;
    if (!seen) sg_layoutHeight = size.height;
    sg_list = list;
    lastChanges = sg_changes;

    CGFloat gap = measure(list);
    BOOL moved = gap != sg_gap;
    if (moved) {
        sg_gap = gap;
        SGLog(@"redesign search: cards moved up %.0fpt, the spacing the collapsed sections above them leave", gap);
        for (UIView *sub in list.subviews) {
            if ([sub isKindOfClass:UICollectionViewCell.class] && isBrowseCell(((UICollectionViewCell *)sub).contentView)) {
                shift((UICollectionViewCell *)sub);
            }
        }
    }
    // The content's end moves up with the cards (setContentSize: below takes the gap off).
    if (moved || !seen) list.contentSize = CGSizeMake(size.width, sg_layoutHeight);
    lastSize = list.contentSize;
}

// After the pass that sized the cell: the list's attributes take the new height when that pass ends.
static void measureSoon(void) {
    if (sg_measureQueued) return;
    sg_measureQueued = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        sg_measureQueued = NO;
        SGRSearchCloseGap(sg_list);
    });
}

%hook _TtC12Element_List18CollectionViewCell
- (UICollectionViewLayoutAttributes *)preferredLayoutAttributesFittingAttributes:(UICollectionViewLayoutAttributes *)attributes {
    UICollectionViewCell *cell = (UICollectionViewCell *)self;
    UIView *content = cell.contentView;
    if (!isBrowseCell(content)) return %orig;
    UICollectionViewLayoutAttributes *result = %orig;

    UIView *root = content.subviews.firstObject.subviews.firstObject;
    SGRSearchKind kind = kindOf(root);
    BOOL collapsed = objc_getAssociatedObject(cell, &kCollapsedKey) != nil;
    if (kind == SGRSearchKindDrop) {
        SGRCollapseCell(cell, MAX(1, result.size.height), &kCollapsedKey);
        result.size = CGSizeMake(result.size.width, 0);
        if (!collapsed) {
            sg_changes++;
            measureSoon();
        }
        SGLogOnce(&sg_loggedMessages, [@"dropped " stringByAppendingString:describe(root)], kLogFormat);
    } else if (kind == SGRSearchKindKeep && collapsed) {
        // Cells are reused across kinds: one collapsed before holds a card now.
        SGRRestoreCell(cell, &kCollapsedKey);
        sg_changes++;
        measureSoon();
    }
    return result;
}

- (void)applyLayoutAttributes:(UICollectionViewLayoutAttributes *)attributes {
    %orig;
    UICollectionViewCell *cell = (UICollectionViewCell *)self;
    if (isBrowseCell(cell.contentView)) shift(cell);
}

// The cell's own passes may size the content to the cell again, and a cell laid out before the gap was known takes it here.
- (void)layoutSubviews {
    %orig;
    UICollectionViewCell *cell = (UICollectionViewCell *)self;
    NSNumber *natural = objc_getAssociatedObject(cell, &kCollapsedKey);
    if (natural) SGRCollapseCell(cell, natural.doubleValue, &kCollapsedKey);
    if (sg_gap > 0 && isBrowseCell(cell.contentView)) shift(cell);
}

- (void)prepareForReuse {
    %orig;
    if (objc_getAssociatedObject(self, &kCollapsedKey)) SGRRestoreCell((UICollectionViewCell *)self, &kCollapsedKey);
}
%end

// The list's content ends the gap earlier than its layout has it, so it scrolls as far as the moved-up last row and no
// further. Every other collection view's size goes through untouched.
%hook UICollectionView
- (void)setContentSize:(CGSize)size {
    if ((UICollectionView *)self == sg_list) {
        sg_layoutHeight = size.height;
        size.height = MAX(0, size.height - sg_gap);
    }
    %orig(size);
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    sg_hideWatchFeeds = SGEnabled(SGRKeySearchHideWatchFeeds);
    sg_hideOther = SGEnabled(SGRKeySearchHideOther);
    // Both off, every cell is Spotify's to size.
    if (!sg_hideWatchFeeds && !sg_hideOther) return;
    %init;
    SGRequireClasses(@[@"_TtC12Element_List18CollectionViewCell"]);
}
