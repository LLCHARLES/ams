// Compact library's menu (Library.h): with the root's filter chips hidden, a button in the header whose menu
// reaches what the chips and the list's sort row offer, through Spotify's own controls. Nothing here keeps a sort
// order, a view or a filter of its own: each item finds Spotify's control as the menu opens and fires it the way a
// tap does, so Spotify's sheet, its list and its chips' model stay the only ones.
//
// The controls, by Spotify's identifiers and class names (Spotify 9.1.x): the sort row's
// sort button YourLibraryContent.sort and its list or grid toggle YourLibraryContent.gridToggle, in the list
// (YourLibraryContent.collectionView), which reuses them away as it scrolls; a grid card is
// Components.UI.CardLibrary; the chips are a collection view, Layout.CollectionView, under
// YourLibraryHeaderContentFiltersView, and while a filter is on its first cell is a clear chip, a cell whose class
// name holds ClearChip, which the chips' delegate clears on selection.
//
// When something the menu needs is missing, the chips stay: SGRLibraryMenuStandsIn answers NO until the page's sort
// and view controls have been seen, while a filter is on with no clear chip to clear it, and for good on a page
// where something the menu fired could not be found.
//
// Nothing the sort row says is kept: Spotify changes it from its own sheet, in a cell the list may have put away, so
// what was read once may no longer be so. The menu names the order only while the row is on screen to read it from.
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Library.h"

static NSString *const kSortID = @"YourLibraryContent.sort";
static NSString *const kViewID = @"YourLibraryContent.gridToggle";
static NSString *const kCardID = @"Components.UI.CardLibrary";
static NSString *const kChipsID = @"Layout.CollectionView";
static NSString *const kClearChipMarker = @"ClearChip";

// On the chips' view: their collection, found last. On the page: that the sort row and the toggle have been seen, and
// a failure.
static char kChipsKey, kSortSeenKey, kViewSeenKey, kFailedKey;
// On the chips' collection: whether a filter of theirs could be cleared at the page's last look. On the list: the
// identifier of the sort row's control to fire once the list is back at its top.
static char kClearableKey, kPendingKey;
// On the header: the menu button.
static char kButtonKey;

BOOL SGRLibraryCompact(void) {
    static BOOL compact;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ compact = SGFlag(SGRKeyLibraryHideChips, NO); });
    return compact;
}

#pragma mark - Spotify's controls

static UIView *filtersOf(UIView *page) {
    return SGRChildNamed(SGRLibraryRootHeaderIn(page), @"YourLibraryHeaderContentFiltersView");
}

static UICollectionView *chipsIn(UIView *filters) {
    UIView *found = filters ? SGRFindByIdentifier(filters, kChipsID, &kChipsKey) : nil;
    return [found isKindOfClass:UICollectionView.class] ? (UICollectionView *)found : nil;
}

static BOOL shown(UIView *view, UIView *root) {
    for (UIView *up = view; up && up != root; up = up.superview) if (up.hidden || up.alpha < 0.01) return NO;
    return YES;
}

// One of the sort row's controls while it is on the page, looked for afresh each time and never under a hidden view:
// a cell the list has put away for reuse stays in it, hidden, its control no longer the row's.
static UIView *liveIn(UIView *root, NSString *identifier) {
    if (root.hidden || root.alpha < 0.01) return nil;
    if ([root.accessibilityIdentifier isEqualToString:identifier]) return root;
    for (UIView *sub in root.subviews) {
        UIView *found = liveIn(sub, identifier);
        if (found) return found;
    }
    return nil;
}

static UICollectionViewCell *clearChipIn(UICollectionView *chips) {
    for (UICollectionViewCell *cell in chips.visibleCells) {
        if ([NSStringFromClass(cell.class) containsString:kClearChipMarker] && shown(cell, chips)) return cell;
    }
    return nil;
}

// A chip drawn as chosen: its cell selected, or a control or element inside it that says so.
static BOOL filterOn(UICollectionView *chips) {
    for (UICollectionViewCell *cell in chips.visibleCells) {
        if ([NSStringFromClass(cell.class) containsString:kClearChipMarker]) return YES;
        __block BOOL chosen = cell.selected;
        SGForEachView(cell, ^(UIView *view) {
            if (chosen) return;
            chosen = (view.accessibilityTraits & UIAccessibilityTraitSelected) || ([view isKindOfClass:UIControl.class] && ((UIControl *)view).selected);
        });
        if (chosen) return YES;
    }
    return NO;
}

// No filter on, or one the clear chip clears.
static BOOL clearable(UICollectionView *chips) {
    return !filterOn(chips) || clearChipIn(chips) != nil;
}

// What VoiceOver reads for a chip: the first name it or a view inside it gives.
static NSString *readOut(UIView *chip) {
    __block NSString *name = nil;
    SGForEachView(chip, ^(UIView *view) {
        if (!name.length) name = view.accessibilityLabel;
    });
    return name;
}

// The first text a label shows under `root`, a hidden one not counting.
static NSString *shownText(UIView *root) {
    if (root.hidden || root.alpha < 0.01) return nil;
    if ([root isKindOfClass:UILabel.class]) {
        NSString *text = [((UILabel *)root).text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (text.length) return text;
    }
    for (UIView *sub in root.subviews) {
        NSString *text = shownText(sub);
        if (text) return text;
    }
    return nil;
}

// What the sort row says its order is: the text it shows, else what it reads out.
static NSString *sortName(UIView *sort) {
    NSString *name = shownText(sort);
    if (!name.length) name = sort.accessibilityValue.length ? sort.accessibilityValue : sort.accessibilityLabel;
    return name ?: @"";
}

static void noteSeen(UIView *page, UIView *sort, UIView *toggle) {
    if (sort) objc_setAssociatedObject(page, &kSortSeenKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (toggle) objc_setAssociatedObject(page, &kViewSeenKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static BOOL seen(UIView *page, const void *key) {
    return objc_getAssociatedObject(page, key) != nil;
}

typedef NS_ENUM(NSInteger, SGRLibraryView) {
    SGRLibraryViewUnknown,
    SGRLibraryViewList,
    SGRLibraryViewGrid,
};

// Grid while a card of Spotify's grid is on screen, list while an item that is no card is; unknown with no item
// (an empty library, a list still loading), the sort row's own cell not counting as one.
static SGRLibraryView currentView(UIView *page, UIView *sort) {
    UIScrollView *list = SGRLibraryListIn(page);
    if (![list isKindOfClass:UICollectionView.class]) return SGRLibraryViewUnknown;
    BOOL item = NO;
    for (UICollectionViewCell *cell in ((UICollectionView *)list).visibleCells) {
        if (sort && [sort isDescendantOfView:cell]) continue;
        __block BOOL card = NO;
        SGForEachView(cell, ^(UIView *view) {
            if (!card && [view.accessibilityIdentifier isEqualToString:kCardID]) card = YES;
        });
        if (card) return SGRLibraryViewGrid;
        item = YES;
    }
    return item ? SGRLibraryViewList : SGRLibraryViewUnknown;
}

// The page's chips come back, for good on this page.
static void giveUp(UIView *page, NSString *what) {
    SGLog(@"redesign library: %@ not found, the chips stay", what);
    objc_setAssociatedObject(page, &kFailedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [page setNeedsLayout];
}

static BOOL atTop(UIScrollView *list) {
    return list.contentOffset.y <= -list.adjustedContentInset.top + 0.5;
}

// Fires the sort row's control `identifier`: in place while the row is on screen. The list reuses the row away once
// it scrolls out of sight, so a row not on screen is brought back the way the user would bring it back: the list
// scrolls to its top, in sight, and stays there, and the control fires once it is (SGRLibraryCollectionLaidOut), so
// Spotify's sheet or its new view opens over the row it came from.
static void fireRow(UIView *page, NSString *identifier) {
    UIView *control = liveIn(page, identifier);
    if (control) {
        SGRActivate(control);
        return;
    }
    UIScrollView *list = SGRLibraryListIn(page);
    if (!list || atTop(list)) {
        giveUp(page, identifier);
        return;
    }
    objc_setAssociatedObject(list, &kPendingKey, identifier, OBJC_ASSOCIATION_COPY_NONATOMIC);
    [list setContentOffset:CGPointMake(list.contentOffset.x, -list.adjustedContentInset.top) animated:!SGRReduceMotion()];
    [list layoutIfNeeded];
}

// What fireRow left for the list, once it is back at its top. A finger on the list before then takes it over, and
// the control is not fired.
static void firePending(UICollectionView *list) {
    NSString *identifier = objc_getAssociatedObject(list, &kPendingKey);
    if (!identifier) return;
    if (list.isTracking) {
        objc_setAssociatedObject(list, &kPendingKey, nil, OBJC_ASSOCIATION_COPY_NONATOMIC);
        return;
    }
    if (!atTop(list)) return;
    objc_setAssociatedObject(list, &kPendingKey, nil, OBJC_ASSOCIATION_COPY_NONATOMIC);
    UIView *page = SGRLibraryPageAbove(list);
    UIView *control = page ? liveIn(page, identifier) : nil;
    if (!control) {
        if (page) giveUp(page, identifier);
        return;
    }
    // Out of the list's pass: what the control does (a sheet, the list reloaded in its other view) is not done in
    // the middle of laying the list out.
    dispatch_async(dispatch_get_main_queue(), ^{ SGRActivate(control); });
}

void SGRLibraryCollectionLaidOut(UICollectionView *view) {
    firePending(view);
    NSNumber *was = objc_getAssociatedObject(view, &kClearableKey);
    if (!was) return;
    BOOL now = clearable(view);
    if (now == was.boolValue) return;
    objc_setAssociatedObject(view, &kClearableKey, @(now), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [SGRLibraryPageAbove(view) setNeedsLayout];
}

// Clears the filter the way a tap on Spotify's clear chip does: the chips' delegate told the chip was selected.
static void clearFilter(UIView *page) {
    UICollectionView *chips = chipsIn(filtersOf(page));
    UICollectionViewCell *chip = clearChipIn(chips);
    NSIndexPath *path = chip ? [chips indexPathForCell:chip] : nil;
    id<UICollectionViewDelegate> delegate = chips.delegate;
    if (!path || ![delegate respondsToSelector:@selector(collectionView:didSelectItemAtIndexPath:)]) {
        giveUp(page, @"the clear chip");
        return;
    }
    [delegate collectionView:chips didSelectItemAtIndexPath:path];
}

#pragma mark - the menu

static UIImage *symbol(NSString *name) {
    return [UIImage systemImageNamed:name];
}

static UIMenu *section(NSArray<UIMenuElement *> *children) {
    return [UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:children];
}

NSArray<UIMenuElement *> *SGRLibraryMenuElements(UIView *page) {
    // The page looks again first: a filter the chips or the list took on since its last pass may be one the menu
    // cannot clear, and then the chips are back by the time the menu is.
    [page setNeedsLayout];
    [page layoutIfNeeded];

    NSMutableArray<UIMenuElement *> *elements = [NSMutableArray array];
    __weak UIView *weakPage = page;
    UIView *sort = liveIn(page, kSortID);
    UIView *toggle = liveIn(page, kViewID);
    noteSeen(page, sort, toggle);

    if (seen(page, &kSortSeenKey)) {
        UIAction *action = [UIAction actionWithTitle:SGL(@"settings.library.menu.sort", @"Sort") image:symbol(@"arrow.up.arrow.down")
                                          identifier:nil handler:^(UIAction *a) {
            UIView *owner = weakPage;
            if (owner) fireRow(owner, kSortID);
        }];
        NSString *order = sort ? sortName(sort) : nil;
        if (order.length) action.subtitle = order;
        [elements addObject:section(@[action])];
    }

    if (seen(page, &kViewSeenKey)) {
        void (^flip)(UIAction *) = ^(UIAction *a) {
            UIView *owner = weakPage;
            if (owner) fireRow(owner, kViewID);
        };
        SGRLibraryView view = currentView(page, sort);
        if (view == SGRLibraryViewUnknown) {
            NSString *toggleName = toggle.accessibilityLabel;
            NSString *title = toggleName.length ? toggleName : SGL(@"settings.library.menu.change_view", @"Change view");
            [elements addObject:section(@[[UIAction actionWithTitle:title image:symbol(@"square.grid.2x2") identifier:nil handler:flip]])];
        } else {
            NSMutableArray<UIAction *> *views = [NSMutableArray array];
            for (SGRLibraryView option = SGRLibraryViewList; option <= SGRLibraryViewGrid; option++) {
                BOOL grid = option == SGRLibraryViewGrid, current = option == view;
                UIAction *action = [UIAction actionWithTitle:grid ? SGL(@"settings.library.menu.grid", @"Grid") : SGL(@"settings.library.menu.list", @"List")
                                                       image:symbol(grid ? @"square.grid.2x2" : @"list.bullet") identifier:nil
                                                     handler:current ? ^(UIAction *a) {} : flip];
                action.state = current ? UIMenuElementStateOn : UIMenuElementStateOff;
                [views addObject:action];
            }
            [elements addObject:section(views)];
        }
    }

    UICollectionViewCell *chip = clearChipIn(chipsIn(filtersOf(page)));
    if (chip) {
        NSString *spoken = readOut(chip);
        NSString *title = spoken.length ? spoken : SGL(@"settings.library.menu.clear_filter", @"Clear filter");
        UIAction *clear = [UIAction actionWithTitle:title image:symbol(@"xmark") identifier:nil handler:^(UIAction *a) {
            UIView *owner = weakPage;
            if (owner) clearFilter(owner);
        }];
        [elements addObject:section(@[clear])];
    }
    return elements;
}

BOOL SGRLibraryMenuStandsIn(UIView *page, UIView *filters) {
    if (objc_getAssociatedObject(page, &kFailedKey)) return NO;
    UICollectionView *chips = chipsIn(filters);
    if (!chips) return NO;
    // Watched from here on (SGRLibraryCollectionLaidOut), with what it says now.
    BOOL canClear = clearable(chips);
    objc_setAssociatedObject(chips, &kClearableKey, @(canClear), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    // Looked for until both have been seen; after that the menu looks as it opens.
    if (!seen(page, &kSortSeenKey) || !seen(page, &kViewSeenKey)) {
        noteSeen(page, liveIn(page, kSortID), liveIn(page, kViewID));
        if (!seen(page, &kSortSeenKey) || !seen(page, &kViewSeenKey)) return NO;
    }
    return canClear;
}

UIButton *SGRLibraryMenuButton(UIView *header) {
    UIButton *button = objc_getAssociatedObject(header, &kButtonKey);
    if (!button) {
        button = [UIButton buttonWithType:UIButtonTypeSystem];
        // Spotify's header glyphs are 24pt in their 48pt buttons; a symbol at 20pt draws that size.
        UIImageSymbolConfiguration *size = [UIImageSymbolConfiguration configurationWithPointSize:20 weight:UIImageSymbolWeightRegular];
        UIImage *image = [UIImage systemImageNamed:@"line.3.horizontal.decrease" withConfiguration:size];
        [button setImage:image forState:UIControlStateNormal];
        button.tintColor = SGRPrimary();
        // The menu takes the appearance of its button; Spotify's pages are dark whatever the system is.
        button.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
        button.accessibilityLabel = SGL(@"settings.library.menu.a11y", @"Sort and view");
        button.accessibilityHint = SGL(@"settings.library.menu.hint", @"Sorts the library, changes its view or clears its filter");
        // A glyph that keeps its size at every text size shows larger on a long press, as a bar's buttons do.
        button.showsLargeContentViewer = YES;
        button.largeContentTitle = button.accessibilityLabel;
        button.largeContentImage = image;
        [button addInteraction:[UILargeContentViewerInteraction new]];
        __weak UIView *weakHeader = header;
        button.menu = [UIMenu menuWithChildren:@[[UIDeferredMenuElement elementWithUncachedProvider:^(void (^completion)(NSArray<UIMenuElement *> *)) {
            UIView *page = SGRLibraryPageAbove(weakHeader);
            completion(page ? SGRLibraryMenuElements(page) : @[]);
        }]]];
        button.showsMenuAsPrimaryAction = YES;
        objc_setAssociatedObject(header, &kButtonKey, button, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (button.superview != header) [header addSubview:button];
    return button;
}
