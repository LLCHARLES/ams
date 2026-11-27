// Library redesign: the header of Your Library and of a folder inside it, the way Home and Search have theirs
// (Redesigned/Home/HomeHeader.x, Redesigned/Search/SearchPage.x). A large title at the leading edge, the avatar
// that opens the side drawer at the trailing edge, and the scrim Spotify lays behind the header gone, the soft
// scroll edge (Kit/SGREdgeEffect.x) being what keeps the header clear of the list scrolling under it.
//
// The filter chips under the row stay Spotify's, untouched. They were taken out when the redesign was first
// built and the header closed up by the 49pt they left, and sorting a library turned out to be something the
// page cannot do without (issue #20). Spotify already draws them on the system's own glass
// (Reprise_LiquidGlassKit.LiquidGlass.ChipGlassView, trees/clean/library/03.txt:1210), so they belong here as
// they are; with them back the header keeps the height Spotify gives it and the list keeps Spotify's own inset,
// and there is nothing here to resize or to hold.
//
// Unless Compact library is on (Library.h). Then the root header has a menu button before its trailing controls
// (LibraryMenu.m), and while that menu can stand in for them the chips go and the header closes up by the band
// they leave: the header is shrunk to the bottom of its control row, which hangs off the safe area and so answers
// the same on every pass, and the list's top inset is lowered by the band, taken once from the live frames and
// then held against Spotify setting it again. Both the folded and full insets move by the safe-area delta,
// whether Spotify sets the full height, the already-folded height, or nothing. When the menu can no
// longer stand in -- a filter on with no clear chip, a control it fired gone -- the chips, the header's height and
// the inset come back. A
// filter can change in the chips or the list alone, on passes of their own that reach neither the header nor the
// page, so a change there, and the menu opening, have the page look again at once. A folder keeps its chips and
// its own controls either way.
//
// The row reads from its leading edge, so in a right-to-left language the title is at the right, the avatar at the
// left, and the menu button on the title's side of the controls.
//
// Tree (trees/clean/library/03.txt:1159-1247): YourLibraryView holds YourLibraryContentView, the size of the
// page, and after it -- so over it -- YourLibraryHeaderView 402x159.33: LiquidGlass.GradientView (the scrim), a
// 402x48 row at {0, 62} holding an AutoLayoutStackView {8, 0} 390x48 of
// ListeningActivity_ElementsKit.AdaptiveFaceContainer (the avatar, id=Components.UI.SideDrawerButton),
// id=YourLibraryHeader.title ("Your Library", 21pt), a spacer, a hidden id=YourLibraryHeader.recents,
// id=YourLibraryHeader.search and id=YourLibraryHeader.plus; and under the row
// YourLibraryHeaderContentFiltersView {0, 110} 402x49.33, the chips. Recents is hidden on the account the tree
// is of; the header's model shows it where it says isRecentsAvailable, a clock between the spacer and Search
// (issue #21), and it goes to the trailing edge with the others. A folder (trees/continuous/1.txt:325-344)
// is the same header under YourLibrary_FolderImpl, with id=YourLibraryFolderHeader.back at the leading edge,
// its title, then contextMenu, plus and play or pause, and the chips at {0, 118}. Spotify 9.2.0 puts the root
// header, the same inside, in a plain UIStackView {0, 0} 402x157 that stands where the header stood
// (design/spotify-920/920-library-tree.txt:488-489). There Auto Layout gives the header its height: the row hangs
// off the safe area, the chips under it, and the chips' bottom is the header's (filters.bottom == header.bottom),
// with the stack pinned only at its top and sides so that it follows the header. A frame set on that header is
// undone on the next pass, so Compact library sizes it through that chain instead (pinToRow).
//
// The header neither moves nor shrinks as the list scrolls -- 03.txt, 05.txt and 06.txt hold it at
// {0, 0} 402x159.33 at three scroll positions -- so there is nothing here to follow: the row is laid out once a
// pass and stays where it is put.
//
// Each control moves by a transform rather than by a frame. Spotify's stack lays them out from constraints of
// its own on every pass, and Auto Layout sets a view's center and bounds and leaves its transform alone, so the
// move outlives the pass that made it (Search moves the Browse cells the same way). Nothing leaves the stack:
// an arranged view of Spotify's that hides traps its stack in updateConstraints (Kit/SGRRestyle.h), so what
// goes is alpha, touches and accessibility, and the title Spotify draws goes that way while ours is a subview
// of the header the stack does not arrange.
//
// A move is worked out from where the stack put the control, so it holds only until the stack puts it somewhere
// else, and the stack does that on passes of its own that reach neither the header nor the page: the header's
// model arriving after the page first laid out shows or hides a button, the title gets its text, the avatar
// its size. A button just shown stands where it stood hidden, at the row's leading edge (Recents in 03.txt),
// until the stack's next pass places it. Moves worked out on the page's pass alone were then off by however
// far each control went since -- over the title, off the screen -- until the page laid out again on the way
// back from a playlist (issue #21). So the row the controls stand in is watched too, and every pass of its own
// places them again. In Compact library a header pass can move the whole row without laying the row or page out:
// the controls travel with it, but the frame-placed title and menu need placing on the header's pass (issue #59).

#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Library.h"

// Spotify's own inset for the header's controls: a 48pt button flush against the header's trailing edge has its
// 24pt glyph 20pt from the screen, and the 32pt avatar inside its own 48pt box 16pt from it, which is the
// margin Home gives the avatar.
static const CGFloat kRowInset = 8;
static char kTitleKey, kRowWatchedKey, kListKey, kInsetKey, kHeightKey, kFoldedKey, kHoldKey, kChainKey;
static char kRecentsKey, kSearchKey, kPlusKey, kHeaderTitleKey;
static char kBackKey, kMenuKey, kFolderPlusKey, kPlayKey, kPauseKey, kFolderTitleKey;

UIView *SGRLibraryRootHeaderIn(UIView *page) {
    UIView *header = SGRChildNamed(page, @"YourLibraryHeaderView");
    if (header) return header;
    for (UIView *sub in page.subviews) {
        if (![sub isMemberOfClass:UIStackView.class]) continue;
        header = SGRChildNamed(sub, @"YourLibraryHeaderView");
        if (header) return header;
    }
    return nil;
}

void SGRLibraryClearScrim(UIView *header) {
    SGRVanish(SGRChildNamed(header, @"GradientView"));
}

UIScrollView *SGRLibraryListIn(UIView *page) {
    UIView *found = SGRFindByIdentifier(page, @"YourLibraryContent.collectionView", &kListKey);
    return [found isKindOfClass:UIScrollView.class] ? (UIScrollView *)found : nil;
}

#pragma mark - the controls

// The header's controls, in the order they are to read from the leading edge, leaving out what this build does
// not have, what Spotify has hidden (a folder shows play or pause, never both) and what has not been laid out.
static NSMutableArray<UIView *> *controlsIn(UIView *header, NSArray<NSString *> *identifiers, const void **keys) {
    NSMutableArray<UIView *> *found = [NSMutableArray array];
    for (NSUInteger i = 0; i < identifiers.count; i++) {
        UIView *control = SGRFindByIdentifier(header, identifiers[i], keys[i]);
        if (control && !control.hidden && control.alpha > 0.01 && control.bounds.size.width > 1) [found addObject:control];
    }
    return found;
}

// The header's row reads from its leading edge: the right one in a right-to-left language. Places along the row are
// worked out as distances from that edge and turned into x only as a frame or a move is set.
static BOOL rightToLeft(UIView *header) {
    return header.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;
}

// The x of a span `width` wide starting `fromLeading` from the header's leading edge.
static CGFloat xAt(UIView *header, CGFloat fromLeading, CGFloat width) {
    return rightToLeft(header) ? header.bounds.size.width - fromLeading - width : fromLeading;
}

// How far from the header's leading edge `frame` ends.
static CGFloat endFromLeading(UIView *header, CGRect frame) {
    return rightToLeft(header) ? header.bounds.size.width - CGRectGetMinX(frame) : CGRectGetMaxX(frame);
}

// Puts the controls at the header's trailing edge, the last of them flush against it and each keeping the width
// it has, and answers how far from the leading edge the first of them starts.
static CGFloat placeTrailing(UIView *header, NSArray<UIView *> *controls) {
    CGFloat end = header.bounds.size.width - kRowInset;
    for (UIView *control in controls.reverseObjectEnumerator) {
        CGFloat width = control.bounds.size.width;
        // The center is where Auto Layout put the control, whatever transform is on it; its frame is not.
        CGFloat natural = [control.superview convertPoint:CGPointZero toView:header].x + control.center.x - width / 2;
        CGAffineTransform move = CGAffineTransformMakeTranslation(xAt(header, end - width, width) - natural, 0);
        if (!CGAffineTransformEqualToTransform(control.transform, move)) control.transform = move;
        end -= width;
    }
    return end;
}

// `place` again after every pass of the row the controls stand in (see the top of the file), for as long as it
// is in the header. The row is the stack's container, a plain UIView the Kit can watch; what `place` does not
// touch -- the header's height, the list under it -- stays the page's pass's.
static void watchRow(UIView *row, UIView *header, NSArray<UIView *> *(*place)(UIView *header)) {
    if (!row || objc_getAssociatedObject(row, &kRowWatchedKey)) return;
    objc_setAssociatedObject(row, &kRowWatchedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    __weak UIView *weakHeader = header;
    SGRObserveLayout(row, ^(UIView *view) {
        UIView *owner = weakHeader;
        if (!owner || ![view isDescendantOfView:owner]) return;
        // Once, the first time the row's pass finds a control away from where the page's pass left it.
        static BOOL logged;
        NSMutableArray<NSNumber *> *before = logged ? nil : [NSMutableArray array];
        for (UIView *sub in before ? view.subviews : @[]) [before addObject:@(sub.transform.tx)];
        NSArray<UIView *> *placed = place(owner);
        if (!before || !owner.window) return;
        for (NSUInteger i = 0; i < before.count && i < view.subviews.count; i++) {
            if (fabs(view.subviews[i].transform.tx - before[i].doubleValue) < 0.5) continue;
            logged = YES;
            SGLog(@"redesign library: the header's row laid out on its own after the page, its %lu controls placed again",
                  (unsigned long)placed.count);
            break;
        }
    });
}

#pragma mark - the title

static NSString *textIn(UIView *label) {
    __block NSString *text = nil;
    SGForEachView(label, ^(UIView *view) {
        if (!text && [view isKindOfClass:UILabel.class] && ((UILabel *)view).text.length) text = ((UILabel *)view).text;
    });
    return text;
}

// The title Spotify's own says, so it follows the app's language, in the Music app's size on the row's middle,
// from `leading` to `trailing`, both measured from the header's leading edge.
static void layoutTitle(UIView *header, UIView *spotifyTitle, CGFloat leading, CGFloat trailing, CGFloat middle) {
    UILabel *title = SGRLargeTitleIn(header, &kTitleKey);
    NSString *text = textIn(spotifyTitle);
    if (text.length && ![title.text isEqualToString:text]) {
        title.text = text;
        title.accessibilityLabel = text;
    }
    UIFont *font = SGCategoryCappedFont(UIFontTextStyleLargeTitle, UIFontWeightBold, UIContentSizeCategoryLarge);
    if (![title.font isEqual:font]) title.font = font;

    CGFloat height = ceil(font.lineHeight);
    CGFloat width = MAX(0, trailing - SGRGrid - leading);
    CGRect frame = CGRectMake(xAt(header, leading, width), round(middle - height / 2), width, height);
    if (!CGRectEqualToRect(title.frame, frame)) title.frame = frame;
}

#pragma mark - the two headers

// The root header's controls at its trailing edge, the avatar last, and the title before them. Answers what it
// placed in the order it reads, nothing while the header has no control laid out.
static NSArray<UIView *> *placeRoot(UIView *header) {
    UIView *spotifyTitle = SGRFindByIdentifier(header, @"YourLibraryHeader.title", &kHeaderTitleKey);
    SGRVanish(spotifyTitle);
    static const void *keys[] = {&kRecentsKey, &kSearchKey, &kPlusKey};
    NSMutableArray<UIView *> *trailing = controlsIn(header, @[
        @"YourLibraryHeader.recents", @"YourLibraryHeader.search", @"YourLibraryHeader.plus",
    ], keys);
    __block UIView *face = nil;
    SGForEachView(header, ^(UIView *view) {
        if (!face && SGRIsAvatar(view) && view.bounds.size.width > 1) face = view;
    });
    if (face) [trailing addObject:face];
    if (!trailing.count) return trailing;

    CGFloat leading = placeTrailing(header, trailing);
    CGRect row = SGFrameIn(trailing.firstObject, header);
    // Compact library's menu, as tall and as wide as the row's controls, before the first of them.
    if (SGRLibraryCompact() && header.superview) {
        UIButton *menu = SGRLibraryMenuButton(header);
        CGFloat side = row.size.height;
        CGRect frame = CGRectMake(xAt(header, leading - side, side), CGRectGetMidY(row) - side / 2, side, side);
        if (!CGRectEqualToRect(menu.frame, frame)) menu.frame = frame;
        leading -= side;
    }
    layoutTitle(header, spotifyTitle, SGRSideMargin, leading, CGRectGetMidY(row));
    for (UIView *control in trailing) watchRow(control.superview, header, placeRoot);
    return trailing;
}

// The folder header's controls at its trailing edge and the title between them and the back button, which stays
// where Spotify has it. Answers what it placed in the order it reads, the back button first.
static NSArray<UIView *> *placeFolder(UIView *header) {
    UIView *spotifyTitle = SGRFindByIdentifier(header, @"YourLibraryFolderHeader.title", &kFolderTitleKey);
    SGRVanish(spotifyTitle);
    UIView *back = SGRFindByIdentifier(header, @"YourLibraryFolderHeader.back", &kBackKey);
    static const void *keys[] = {&kMenuKey, &kFolderPlusKey, &kPlayKey, &kPauseKey};
    NSMutableArray<UIView *> *placed = controlsIn(header, @[
        @"YourLibraryFolderHeader.contextMenu", @"YourLibraryFolderHeader.plus",
        @"YourLibraryFolderHeader.play", @"YourLibraryFolderHeader.pause",
    ], keys);
    if (!placed.count && !back) return placed;

    CGFloat trailingEdge = placed.count ? placeTrailing(header, placed) : header.bounds.size.width - kRowInset;
    if (back) [placed insertObject:back atIndex:0];
    CGRect rowFrame = SGFrameIn(placed.firstObject, header);
    CGFloat leading = back ? endFromLeading(header, rowFrame) + SGRGrid : SGRSideMargin;
    layoutTitle(header, spotifyTitle, leading, trailingEdge, CGRectGetMidY(rowFrame));
    for (UIView *control in placed) watchRow(control.superview, header, placeFolder);
    return placed;
}

#pragma mark - Compact library

// Whether Auto Layout sizes the header: 9.2.0's, arranged in a stack (see the top of the file).
static BOOL stacked(UIView *header) {
    return [header.superview isMemberOfClass:UIStackView.class];
}

// Spotify's link from the chips' bottom to the stacked header's, while it is active.
static NSLayoutConstraint *chipsToBottom(UIView *header, UIView *filters) {
    for (NSLayoutConstraint *link in header.constraints) {
        if (!link.active || link.relation != NSLayoutRelationEqual) continue;
        if (link.firstAttribute != NSLayoutAttributeBottom || link.secondAttribute != NSLayoutAttributeBottom) continue;
        if ((link.firstItem == filters && link.secondItem == header) || (link.firstItem == header && link.secondItem == filters)) {
            return link;
        }
    }
    return nil;
}

// End the stacked header at the row instead of the chips so a safe-area change moves both bottoms in
// the same layout pass. Keep Spotify's link for unfoldChips, including any replacement it installs.
static void pinToRow(UIView *header, UIView *filters, UIView *control) {
    UIView *row = control;
    while (row && row.superview != header) row = row.superview;
    if (!row) return;
    NSLayoutConstraint *hold = objc_getAssociatedObject(header, &kHoldKey);
    NSLayoutConstraint *chain = chipsToBottom(header, filters);
    if (chain) {
        chain.active = NO;
        objc_setAssociatedObject(header, &kChainKey, chain, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (hold.secondItem != row) {
        hold.active = NO;
        hold = [header.bottomAnchor constraintEqualToAnchor:row.bottomAnchor];
        objc_setAssociatedObject(header, &kHoldKey, hold, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    hold.active = YES;
}

// The top of the safe area of the page `list` is in, which the header's row hangs off. The page's own: the list's is
// worked out after the page's pass, where Spotify sets the list's inset from the page's.
static CGFloat safeTop(UIView *list) {
    return SGRLibraryPageAbove(list).safeAreaInsets.top;
}

// Once folded, a top Spotify writes can include the chips or already exclude them. Only the movement
// of the safe area changes our two saved tops; a bottom-only write need not be distinguished.
static NSArray<NSNumber *> *heldInset(UIScrollView *list) {
    NSArray<NSNumber *> *held = objc_getAssociatedObject(list, &kInsetKey);   // folded, full, safe top
    if (!held) return nil;
    UIView *page = SGRLibraryPageAbove(list);
    // A detached tab can report zero even though its list will return to the same safe area.
    if (!page.window) return held;
    CGFloat safe = page.safeAreaInsets.top, delta = safe - held[2].doubleValue;
    if (delta != 0) {
        held = @[@(held[0].doubleValue + delta), @(held[1].doubleValue + delta), @(safe)];
        objc_setAssociatedObject(list, &kInsetKey, held, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return held;
}

// The chips gone and the page closed up by the band they leave (see the top of the file). `control` is any of the
// header's controls: they fill its row, so the bottom of one is the bottom of the row. What Spotify had -- the
// chips' alpha, the header's height and the band, the list's inset -- is kept for unfoldChips.
static void foldChips(UIView *header, UIView *control, UIView *filters, UIScrollView *list) {
    if (stacked(header) && !objc_getAssociatedObject(header, &kHoldKey) && !chipsToBottom(header, filters)) {
        static BOOL logged;
        if (!logged) SGLog(@"redesign library: compact, the stacked header has no link from its chips to its bottom, chips kept");
        logged = YES;
        return;
    }
    if (!objc_getAssociatedObject(filters, &kFoldedKey)) {
        objc_setAssociatedObject(filters, &kFoldedKey, @(filters.alpha), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    SGRVanish(filters);

    CGFloat wanted = CGRectGetMaxY(SGFrameIn(control, header));
    NSArray<NSNumber *> *spotify = objc_getAssociatedObject(header, &kHeightKey);   // its height, the band
    if (!spotify) {
        // Taken once, from a header laid out with its chips under its row.
        CGRect chips = SGFrameIn(filters, header);
        CGFloat height = header.bounds.size.height, band = CGRectGetMaxY(chips) - wanted;
        if (CGRectGetMinY(chips) < wanted - 0.5 || height < wanted + band - 0.5 || band < 1) return;
        spotify = @[@(height), @(band)];
        objc_setAssociatedObject(header, &kHeightKey, spotify, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (stacked(header)) {
        pinToRow(header, filters, control);
    } else {
        CGRect frame = header.frame;
        if (fabs(frame.size.height - wanted) > 0.5) {
            frame.size.height = wanted;
            header.frame = frame;
        }
    }

    // The list rests under the header by an inset of its own, which counts the whole header Spotify made. It is
    // lowered by the band once and then held (the setter hook below), so Spotify setting it again from its own pass
    // does not undo it pass after pass.
    if (!list) return;
    NSArray<NSNumber *> *held = heldInset(list);
    CGFloat top = list.contentInset.top, band = spotify[1].doubleValue;
    CGFloat folded;
    if (held) {
        folded = held[0].doubleValue;
        if (top == folded) return;
    } else {
        if (top < spotify[0].doubleValue - 0.5) return;
        folded = top - band;
        objc_setAssociatedObject(list, &kInsetKey, @[@(folded), @(top), @(safeTop(list))], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        SGLog(@"redesign library: compact, the chips' %.0fpt taken off the header, the list rests at %.0f", band, folded);
    }
    BOOL atTop = list.contentOffset.y <= -top + 0.5;
    UIEdgeInsets inset = list.contentInset;
    inset.top = folded;
    list.contentInset = inset;
    // A list resting at its top rests that much higher; one scrolled into its rows does not move at all.
    if (atTop) list.contentOffset = CGPointMake(list.contentOffset.x, -inset.top);
}

// The chips, the header's height and the list's inset as Spotify had them, once the menu cannot stand in for them.
static void unfoldChips(UIView *header, UIView *filters, UIScrollView *list) {
    NSNumber *alpha = objc_getAssociatedObject(filters, &kFoldedKey);
    if (alpha) {
        objc_setAssociatedObject(filters, &kFoldedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        filters.alpha = alpha.doubleValue;
        filters.userInteractionEnabled = YES;
        filters.accessibilityElementsHidden = NO;
    }
    NSArray<NSNumber *> *spotify = objc_getAssociatedObject(header, &kHeightKey);
    NSLayoutConstraint *hold = objc_getAssociatedObject(header, &kHoldKey);
    if (hold) {
        objc_setAssociatedObject(header, &kHoldKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        hold.active = NO;
        ((NSLayoutConstraint *)objc_getAssociatedObject(header, &kChainKey)).active = YES;
        objc_setAssociatedObject(header, &kChainKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(header, &kHeightKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    } else if (spotify) {
        objc_setAssociatedObject(header, &kHeightKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        CGRect frame = header.frame;
        frame.size.height = spotify[0].doubleValue;
        header.frame = frame;
    }
    NSArray<NSNumber *> *held = heldInset(list);
    if (!held) return;
    objc_setAssociatedObject(list, &kInsetKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    BOOL atTop = list.contentOffset.y <= -list.contentInset.top + 0.5;
    UIEdgeInsets inset = list.contentInset;
    inset.top = held[1].doubleValue;
    list.contentInset = inset;
    if (atTop) list.contentOffset = CGPointMake(list.contentOffset.x, -inset.top);
    SGLog(@"redesign library: compact, the chips back, the list rests at %.0f", inset.top);
}

static void layoutRoot(UIView *page) {
    UIView *header = SGRLibraryRootHeaderIn(page);
    if (!header) return;
    // 9.2.0's stack sizes the header on a pass of its own, after the page's, so it is laid out first here: the
    // controls are placed against the header's width.
    [(header.superview == page ? header : header.superview) layoutIfNeeded];
    SGRLibraryClearScrim(header);

    NSArray<UIView *> *trailing = placeRoot(header);
    if (!trailing.count) return;

    UIView *filters = SGRChildNamed(header, @"YourLibraryHeaderContentFiltersView");
    if (SGRLibraryCompact() && filters) {
        UIScrollView *list = SGRLibraryListIn(page);
        if (SGRLibraryMenuStandsIn(page, filters)) foldChips(header, trailing.firstObject, filters, list);
        else unfoldChips(header, filters, list);
    }

    // The first pass that laid the header out, not the first pass at all: a page appearing lays out before
    // its controls have a size, and a line off that pass would say the header was left as Spotify's.
    UIView *face = SGRIsAvatar(trailing.lastObject) ? trailing.lastObject : nil;
    static BOOL logged;
    if (!logged && header.window && face) {
        logged = YES;
        SGLog(@"redesign library: header %@, %lu controls at the trailing edge, avatar %@, chips %@",
              NSStringFromCGRect(header.frame), (unsigned long)trailing.count, face ? @"found" : @"not found",
              !filters ? @"not found" : objc_getAssociatedObject(filters, &kFoldedKey) ? @"folded" : @"Spotify's");
    }
}

static void layoutFolder(UIView *page) {
    UIView *header = SGRChildNamed(page, @"FolderHeaderView");
    if (!header) return;
    [header layoutIfNeeded];
    SGRLibraryClearScrim(header);

    NSArray<UIView *> *placed = placeFolder(header);
    if (!placed.count) return;

    UIView *back = SGRFindByIdentifier(header, @"YourLibraryFolderHeader.back", &kBackKey);
    NSUInteger trailing = placed.count - (back ? 1 : 0);
    static BOOL logged;
    if (!logged && header.window && trailing) {
        logged = YES;
        SGLog(@"redesign library: folder header %@, back %@, %lu controls at the trailing edge, chips %@",
              NSStringFromCGRect(header.frame), back ? @"found" : @"not found", (unsigned long)trailing,
              SGRChildNamed(header, @"YourLibraryHeaderContentFiltersView") ? @"Spotify's" : @"not found");
    }
}

%hook _TtC28YourLibrary_YourLibraryXImpl15YourLibraryView
- (void)layoutSubviews {
    %orig;
    layoutRoot((UIView *)self);
}
%end

%hook _TtC22YourLibrary_FolderImpl10FolderView
- (void)layoutSubviews {
    %orig;
    layoutFolder((UIView *)self);
}
%end

%group CompactLibrary
%hook _TtC28YourLibrary_YourLibraryXImpl21YourLibraryHeaderView
- (void)layoutSubviews {
    %orig;
    UIView *header = (UIView *)self;
    if (SGRLibraryPageAbove(header)) placeRoot(header);
}
%end

%hook _TtC21YourLibrary_CommonKit25YourLibraryCollectionView
- (void)setContentInset:(UIEdgeInsets)inset {
    NSArray<NSNumber *> *held = heldInset((UIScrollView *)self);
    if (held) inset.top = held[0].doubleValue;
    %orig(inset);
}

// The list's rows, and its sort row with them, come in after the page first laid out, on passes of the list's own,
// and a filter changes them the same way. A list whose content changed has the page look again.
- (void)setContentSize:(CGSize)size {
    BOOL changed = !CGSizeEqualToSize(size, ((UIScrollView *)self).contentSize);
    %orig;
    if (changed) [SGRLibraryPageAbove((UIView *)self) setNeedsLayout];
}
%end

// The chips' collection and the list, after each pass of their own (LibraryMenu.m tells them from every other).
%hook UICollectionView
- (void)layoutSubviews {
    %orig;
    SGRLibraryCollectionLaidOut((UICollectionView *)self);
}
%end
%end

UIView *SGRLibraryPageAbove(UIView *view) {
    Class pageClass = objc_getClass("_TtC28YourLibrary_YourLibraryXImpl15YourLibraryView");
    for (UIView *up = view.superview; up; up = up.superview) {
        if ([up isKindOfClass:pageClass]) return up;
    }
    return nil;
}

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
    if (SGRLibraryCompact()) %init(CompactLibrary);
    SGRequireClasses(@[
        @"_TtC28YourLibrary_YourLibraryXImpl15YourLibraryView",
        @"_TtC22YourLibrary_FolderImpl10FolderView",
        @"_TtC21YourLibrary_CommonKit25YourLibraryCollectionView",
        @"_TtC21YourLibrary_CommonKit35YourLibraryHeaderContentFiltersView",
        @"_TtC29ListeningActivity_ElementsKit21AdaptiveFaceContainer",
    ]);
}
