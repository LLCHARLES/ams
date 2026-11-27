// Home redesign: of the sections the feed sends, only the music ones stay: the grid of shortcuts, the
// DJ and the shelves of cards (Recents, Jump back in, Your playlists, New releases, the mixes, For fans
// of...). Every other section reports no height, so the list closes up around it: the medium density
// previews (a video or an episode playing muted under Unmute and Watch full episode, or a playlist to
// Preview), a heading over one of those (Fitness for you, Videos from your top artists), the episode
// cards, and any kind the server adds later.
//
// An allow list, as for the cards under the player (Redesigned/Player/PlayerCards.x): the feed is the
// server's, and a new kind should not turn up on a redesigned Home.
//
// Tree (trees/clean/home/10.txt): a section is an Element_List.CollectionViewCell of the page's list whose
// first subview is an ElementContentView over Home_EvoPageImpl.HomeStructure, then an
// ElementView<HomeStructure>, then the section's own root, which names its kind:
//   Home_CarouselKit.TouchCancellingCollectionView     a shelf of SimpleCards under a heading (:2274)
//   UICollectionView with no identifier                 the shortcuts grid, Home_AnchorsAndShortcutsKit cells (01.txt:33)
//   UICollectionView id=ActionCardCarouselElement        episode cards (:696)
//   UIStackView                                         a heading over the DJ card's LazyElementView (01.txt:460),
//                                                       or over a medium density card (:973, :1443)
//   Discovery_MediumDensityCardKit.MediumCardAnimatingLayout   a preview card (:1300, :1746, :1882)
//
// The DJ stays without its heading ("Your own personal DJ" over a card that says DJ): the stack is a plain
// UIStackView, so the heading's LazyElementView is hidden before the cell is measured and the stack closes up.
//
// A dropped section must also stop being estimated in the compositional layout. Returning zero only from the
// cell leaves UIKit recreating and self-sizing that cell at its original estimate on subsequent layout passes.
// Keep the snapshot's indices, but give dropped sections an empty, absolute-height layout.
#import <objc/runtime.h>
#import <objc/message.h>
#import "Core/SGCore.h"
#import "Shared/WireGuard/SGWGABI.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Home.h"

typedef NS_ENUM(NSInteger, SGRHomeKind) {
    SGRHomeKindPending,   // the section's root is not in the cell yet: left as it is
    SGRHomeKindKeep,
    SGRHomeKindDrop,
};

static char kCollapsedKey, kDroppedKey, kModelKey;

@interface SGRHomeFeed : NSObject
+ (NSArray *)sectionsOf:(id)page;
+ (NSArray *)sectionsOf:(id)page items:(NSArray *)identifiers generation:(id)generation;
@end
@interface __UIDiffableDataSource : NSObject
@end

static BOOL modelDrops(UICollectionViewCompositionalLayout *layout, NSInteger section);

// UIKit's private diffable internals differ between iOS releases; a missing one leaves the model unavailable
// (cells then classify themselves) instead of an unrecognized selector in every diffable list of the app.
static id sendIfAnswered(id object, NSString *name) {
    SEL selector = NSSelectorFromString(name);
    Method method = class_getInstanceMethod(object_getClass(object), selector);
    return SGWGMethodMatches(method, "@", @[]) ? ((id (*)(id, SEL))objc_msgSend)(object, selector) : nil;
}

static UICollectionView *homeListOf(id source) {
    id list = sendIfAnswered(source, @"_collectionView");
    if (![list isKindOfClass:UICollectionView.class]) return nil;
    return SGClassNamed(object_getClass(((UICollectionView *)list).delegate), @"Home_EvoPageImpl") ? list : nil;
}

static void captureModel(UICollectionView *list, id source, id generation) {
    SEL itemSelector = @selector(itemIdentifierForIndexPath:);
    NSArray *model = nil;
    if (generation && [source respondsToSelector:@selector(numberOfSectionsInCollectionView:)]
        && [source respondsToSelector:itemSelector]) {
        NSMutableArray *identifiers = [NSMutableArray array];
        NSInteger count = [(id<UICollectionViewDataSource>)source numberOfSectionsInCollectionView:list];
        for (NSInteger section = 0; section < count; section++) {
            id identifier = ((id (*)(id, SEL, NSIndexPath *))objc_msgSend)(source, itemSelector,
                [NSIndexPath indexPathForItem:0 inSection:section]);
            [identifiers addObject:identifier ?: NSNull.null];
        }
        model = [SGRHomeFeed sectionsOf:list.delegate items:identifiers generation:generation];
    }
    objc_setAssociatedObject(list.collectionViewLayout, &kModelKey, model ?: NSNull.null, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

#pragma mark - the dropped sections' layout

// `layout` gives the layout once it is made. Hidden content has no estimated items to recreate.
static UICollectionViewCompositionalLayoutSectionProvider withoutDroppedSections(UICollectionViewCompositionalLayoutSectionProvider inner,
                                                                               UICollectionViewCompositionalLayout *(^layout)(void)) {
    return ^NSCollectionLayoutSection *(NSInteger section, id<NSCollectionLayoutEnvironment> environment) {
        UICollectionViewCompositionalLayout *owner = layout();
        NSIndexSet *dropped = owner ? objc_getAssociatedObject(owner, &kDroppedKey) : nil;
        if ([dropped containsIndex:(NSUInteger)section] || modelDrops(owner, section)) {
            NSCollectionLayoutSize *size = [NSCollectionLayoutSize
                sizeWithWidthDimension:[NSCollectionLayoutDimension fractionalWidthDimension:1]
                heightDimension:[NSCollectionLayoutDimension absoluteDimension:0]];
            return [NSCollectionLayoutSection sectionWithGroup:
                [NSCollectionLayoutGroup customGroupWithLayoutSize:size itemProvider:
                    ^NSArray<NSCollectionLayoutGroupCustomItem *> *(id<NSCollectionLayoutEnvironment> env) { return @[]; }]];
        }
        return inner(section, environment);
    };
}

%hook UICollectionViewCompositionalLayout
- (instancetype)initWithSectionProvider:(UICollectionViewCompositionalLayoutSectionProvider)provider
                          configuration:(UICollectionViewCompositionalLayoutConfiguration *)configuration {
    if (!provider) return %orig;
    __block __weak UICollectionViewCompositionalLayout *made = nil;
    UICollectionViewCompositionalLayout *layout = %orig(withoutDroppedSections(provider, ^{ return made; }), configuration);
    made = layout;
    return layout;
}
- (instancetype)initWithSectionProvider:(UICollectionViewCompositionalLayoutSectionProvider)provider {
    if (!provider) return %orig;
    __block __weak UICollectionViewCompositionalLayout *made = nil;
    UICollectionViewCompositionalLayout *layout = %orig(withoutDroppedSections(provider, ^{ return made; }));
    made = layout;
    return layout;
}
%end

// UIKit's transaction identifies the input generation even when committing advances the state ID.
// Resolve that generation once on main; layouts must not retry an unavailable model.
%hook __UIDiffableDataSource
- (void)_storeState:(id)state {
    %orig;
    if (!NSThread.isMainThread) {
        // A commit off main cannot be matched to its model here; the previous model must not classify it.
        __weak id source = self;
        dispatch_async(dispatch_get_main_queue(), ^{
            UICollectionView *list = homeListOf(source);
            if (!list) return;
            objc_setAssociatedObject(list.collectionViewLayout, &kDroppedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            captureModel(list, source, nil);
            [list.collectionViewLayout invalidateLayout];
        });
        return;
    }
    UICollectionView *list = homeListOf(self);
    if (!list) return;
    objc_setAssociatedObject(list.collectionViewLayout, &kDroppedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    id snapshotState = sendIfAnswered(sendIfAnswered(sendIfAnswered(sendIfAnswered(self, @"currentTransaction"),
        @"finalSnapshot"), @"impl"), @"state");
    captureModel(list, self, sendIfAnswered(snapshotState, @"generationID"));
    [list.collectionViewLayout invalidateLayout];
}
%end

// Marks or clears the list section `index` as dropped, and has the layout ask for it again when that changes.
static void markDropped(UICollectionViewCell *cell, NSInteger index, BOOL dropped) {
    UIView *v = cell.superview;
    while (v && ![v isKindOfClass:UICollectionView.class]) v = v.superview;
    UICollectionViewLayout *layout = ((UICollectionView *)v).collectionViewLayout;
    if (!layout || index < 0) return;
    NSMutableIndexSet *set = objc_getAssociatedObject(layout, &kDroppedKey);
    if ([set containsIndex:(NSUInteger)index] == dropped) return;
    if (!set) {
        set = [NSMutableIndexSet indexSet];
        objc_setAssociatedObject(layout, &kDroppedKey, set, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (dropped) [set addIndex:(NSUInteger)index];
    else [set removeIndex:(NSUInteger)index];
    // Not from inside the list's own sizing pass.
    __weak UICollectionViewLayout *weakLayout = layout;
    dispatch_async(dispatch_get_main_queue(), ^{ [weakLayout invalidateLayout]; });
}

static BOOL contentNames(UIView *content, NSString *marker) {
    return SGClassNamed(object_getClass(content), marker);
}

static BOOL isSection(UIView *content) {
    return contentNames(content, @"Home_EvoPageImpl13HomeStructure");
}

static NSMutableSet<NSString *> *sg_loggedMessages;
#define kLogFormat @"redesign home: %@"

// The shortcuts grid names no identifier; episode cards and whatever else comes as a bare list do.
static SGRHomeKind gridKind(UICollectionView *grid) {
    if (grid.accessibilityIdentifier.length) return SGRHomeKindDrop;
    UIView *cell = grid.visibleCells.firstObject;
    // A grid the list sized before it laid its own cells out: nothing but the shortcuts has come as one.
    if (cell && !contentNames(cell.subviews.firstObject, @"Home_AnchorsAndShortcutsKit")) return SGRHomeKindDrop;
    return SGHidden(SGRKeyHomeHideShortcuts) ? SGRHomeKindDrop : SGRHomeKindKeep;
}

// The previews (a video or a playlist playing as Home scrolls) are medium density cards, on their own or under a
// heading; the song suggestions are Spotify's content evaluation carousel. Each stays only when asked for.
static SGRHomeKind optionalKind(NSString *name) {
    if ([name containsString:@"MediumDensityCard"] || [name containsString:@"Discovery_Preview"]) {
        return SGHidden(SGRKeyHomePreviews) ? SGRHomeKindKeep : SGRHomeKindDrop;
    }
    if ([name containsString:@"ContentEvaluationList"]) return SGHidden(SGRKeyHomeSongSuggestions) ? SGRHomeKindKeep : SGRHomeKindDrop;
    return SGRHomeKindDrop;
}

// Decide before constructing cells where the model names the kind. In particular, a hidden music preview
// must never be materialized merely because collapsing shelves brought it into the viewport: Spotify's
// DataElement can ask for its not-yet-ready data while creating the cell, before self-sizing can hide it.
static BOOL modelDrops(UICollectionViewCompositionalLayout *layout, NSInteger section) {
    UICollectionView *list = layout.collectionView;
    if (!SGClassNamed(object_getClass(list.delegate), @"Home_EvoPageImpl")) return NO;
    id cached = objc_getAssociatedObject(layout, &kModelKey);
    if (![cached isKindOfClass:NSArray.class]) return NO;
    NSArray *model = cached;
    if (section < 0 || (NSUInteger)section >= model.count) return NO;
    id entry = model[section];
    if (![entry isKindOfClass:NSArray.class]) return NO;
    NSString *kind = entry[0];
    if ([kind isEqualToString:@"musicPreview"]) return optionalKind(@"MediumDensityCard") == SGRHomeKindDrop;
    if ([kind isEqualToString:@"shortcuts"]) return SGHidden(SGRKeyHomeHideShortcuts);
    if ([kind isEqualToString:@"shelf"] || [kind isEqualToString:@"recents"]) {
        NSArray *heading = entry[1];
        if (heading.count != 2) return NO;
        NSString *identity = SGRHomeShelfIdentityFrom(heading[0], heading[1]);
        SGRHomeNoteShelf(identity);
        return SGRHomeShelfHidden(identity);
    }
    return NO;
}

// A LazyElementView names the element it will hold before it holds it.
static SGRHomeKind stackKind(UIStackView *stack) {
    for (UIView *part in stack.arrangedSubviews) {
        NSString *name = NSStringFromClass(part.class);
        if ([name containsString:@"Discovery_DJElementKit"]) return SGHidden(SGRKeyHomeHideDJ) ? SGRHomeKindDrop : SGRHomeKindKeep;
        SGRHomeKind optional = optionalKind(name);
        if (optional == SGRHomeKindKeep) return optional;
    }
    return stack.arrangedSubviews.count >= 2 ? SGRHomeKindDrop : SGRHomeKindPending;
}

// A shelf stays unless its heading names one that is switched off; one with no heading to read yet stays, and
// HomeHeadings.x asks the cell to measure again once there is one.
static SGRHomeKind shelfKind(UIView *shelf) {
    NSString *identity = SGRHomeShelfIdentity(shelf);
    if (!identity) return SGRHomeKindKeep;
    SGRHomeNoteShelf(identity);
    return SGRHomeShelfHidden(identity) ? SGRHomeKindDrop : SGRHomeKindKeep;
}

// Before the cell is measured, so the height it reports is without the heading.
static void dropDJHeading(UIView *content) {
    UIStackView *stack = (UIStackView *)content.subviews.firstObject.subviews.firstObject;
    if (![stack isKindOfClass:UIStackView.class] || stackKind(stack) != SGRHomeKindKeep) return;
    for (UIView *part in stack.arrangedSubviews) {
        if (part.hidden || ![NSStringFromClass(part.class) containsString:@"Home_HeadingElementKit"]) continue;
        part.hidden = YES;
        SGLogOnce(&sg_loggedMessages, @"DJ heading hidden", kLogFormat);
    }
}

static SGRHomeKind kindOf(UIView *content, NSString **rootName) {
    UIView *root = content.subviews.firstObject.subviews.firstObject;
    if (!root) return SGRHomeKindPending;
    *rootName = NSStringFromClass(root.class);
    static Class shelf;
    if (!shelf) shelf = NSClassFromString(@"_TtC16Home_CarouselKit29TouchCancellingCollectionView");
    if (shelf && [root isKindOfClass:shelf]) return shelfKind(root);
    if ([root isKindOfClass:UICollectionView.class]) return gridKind((UICollectionView *)root);
    if ([root isKindOfClass:UIStackView.class]) return stackKind((UIStackView *)root);
    return optionalKind(*rootName);
}

void SGRHomeMeasureAgain(UIView *view) {
    UIView *cell = view;
    while (cell && ![cell isKindOfClass:UICollectionViewCell.class]) cell = cell.superview;
    // A cell of a shelf's own list: the page's cell is the one around that.
    for (UIView *v = cell.superview; v; v = v.superview) {
        if ([v isKindOfClass:UICollectionViewCell.class]) cell = v;
    }
    if (!cell || !isSection(((UICollectionViewCell *)cell).contentView)) return;
    // The list asks a self-sizing cell for its size again once the cell's item is invalidated in the layout and the
    // cell lays out; the cell's intrinsic size alone was not enough for a cell already sized.
    dispatch_async(dispatch_get_main_queue(), ^{
        UIView *v = cell.superview;
        while (v && ![v isKindOfClass:UICollectionView.class]) v = v.superview;
        UICollectionView *list = (UICollectionView *)v;
        NSIndexPath *path = list ? [list indexPathForCell:(UICollectionViewCell *)cell] : nil;
        [cell invalidateIntrinsicContentSize];
        [cell setNeedsLayout];
        if (!path) return;
        UICollectionViewLayoutInvalidationContext *context = [[[list.collectionViewLayout class] invalidationContextClass] new];
        [context invalidateItemsAtIndexPaths:@[path]];
        [list.collectionViewLayout invalidateLayoutWithContext:context];
    });
}

// A dropped section's cell is 0 tall, but what it holds keeps the height it measured at, hidden and cut off
// by the cell. Spotify's content squeezed to 0 with the cell (trees/continuous/1.txt:375-381, every stack,
// heading and card at {402, 0}) breaks its required constraints on every layout pass of the cell, which
// held the main thread for up to 1.5 s at a time where dropped sections scrolled in (home perf, 2026-09-17).
%hook _TtC12Element_List18CollectionViewCell
- (UICollectionViewLayoutAttributes *)preferredLayoutAttributesFittingAttributes:(UICollectionViewLayoutAttributes *)attributes {
    UICollectionViewCell *cell = (UICollectionViewCell *)self;
    UIView *content = cell.contentView;
    if (!isSection(content)) return %orig;
    CFTimeInterval began = SGRHomeProbeBegin();
    dropDJHeading(content);
    UICollectionViewLayoutAttributes *result = %orig;

    NSString *rootName = nil;
    SGRHomeKind kind = kindOf(content, &rootName);
    BOOL collapsed = objc_getAssociatedObject(cell, &kCollapsedKey) != nil;
    if (kind == SGRHomeKindDrop) {
        SGRCollapseCell(cell, MAX(1, result.size.height), &kCollapsedKey);
        result.size = CGSizeMake(result.size.width, 0);
        markDropped(cell, attributes.indexPath.section, YES);
        SGLogOnce(&sg_loggedMessages, [@"dropped a section of " stringByAppendingString:rootName], kLogFormat);
    } else if (kind == SGRHomeKindKeep) {
        // Cells are reused across kinds: one collapsed before holds a section to keep now.
        if (collapsed) SGRRestoreCell(cell, &kCollapsedKey);
        // The page's color (HomeHeader.x) shows through a kept section; Spotify paints a shelf black on each configure.
        UIView *root = content.subviews.firstObject.subviews.firstObject;
        if (SGRHomeLook() && [root isKindOfClass:UICollectionView.class] && ![root.backgroundColor isEqual:UIColor.clearColor]) root.backgroundColor = UIColor.clearColor;
        markDropped(cell, attributes.indexPath.section, NO);
        SGLogOnce(&sg_loggedMessages, [@"kept a section of " stringByAppendingString:rootName], kLogFormat);
    } else {
        SGLogOnce(&sg_loggedMessages, [@"sized a section before its root was in, left as it is: " stringByAppendingString:rootName ?: @"no root"], kLogFormat);
    }
    SGRHomeProbeEnd(SGRHomeProbeSections, began);
    return result;
}

// The cell's own passes may size the content to the cell again.
- (void)layoutSubviews {
    %orig;
    NSNumber *natural = objc_getAssociatedObject(self, &kCollapsedKey);
    if (natural) SGRCollapseCell((UICollectionViewCell *)self, natural.doubleValue, &kCollapsedKey);
}

- (void)prepareForReuse {
    %orig;
    if (objc_getAssociatedObject(self, &kCollapsedKey)) SGRRestoreCell((UICollectionViewCell *)self, &kCollapsedKey);
}
%end

BOOL SGRHomeSectionCollapsed(UIView *cell) {
    return objc_getAssociatedObject(cell, &kCollapsedKey) != nil;
}

%ctor {
    // Registered whatever the switch says: the flag rows elsewhere lock to these while it is on.
    SGRedesignForceFlags(@"home", @{
        // The badge on the DJ card.
        @"ios-home-evopage-impl.dj_mdc_beta_badge_enabled": @NO,
        // The prompt field for Spotify's AI on Home.
        @"ios-home-evopage-impl.interactive_entrypoint_enabled": @NO,
    });
    if (!SGRedesignedUI()) return;
    %init;
    SGRequireClasses(@[
        @"_TtC12Element_List18CollectionViewCell",
        @"_TtC16Home_CarouselKit29TouchCancellingCollectionView",
    ]);
}
