// Home redesign: a shelf's heading at the Music app's size, the title 3 style in bold (20pt at the default
// text size) over Spotify's 17pt. The title is a label of the Kit's own on the same baseline, drawn over
// Spotify's, which goes transparent: Spotify's label measures the heading, so the shelf keeps its layout,
// and the heading button keeps its accessibility label. Where Spotify offers "Show all", it goes and a chevron
// after the title stands for it, as the Music app's "Recently Played ›": a tap anywhere on the heading fires
// Spotify's concealed "Show all", so it opens the same page. A small line over the title ("For fans of") and the
// artist's picture beside it stay Spotify's.
//
// The label is held on Spotify's by constraints, not by a frame worked out here: a heading with a picture lays
// its labels out in a stack of its own, which is positioned after this hook has run, so a frame taken here put
// the title over the artist's picture at the leading edge, and a cell reused for a plain heading kept the
// place the picture had left (trees/continuous/1.txt:2533 and :2291, 2026-09-17). Spotify's label can also have
// no text yet when the button lays out, which left three of that tree's headings at Spotify's own size, so a
// heading with nothing to draw on is looked at again on the next turn of the run loop, a few times at most.
//
// Tree (trees/continuous/1.txt:2289-2312, 2026-09-17): Element_List.SupplementaryItemView 370x48 >
// ... > UIView id=Components.UI.SectionHeadingHome > AutoLayoutStackView > UIView > NoIntrinsicContentSizeButton
// (a11y "For fans of  Yzomandias"), under which an ImageViewHolder 48x48 and a stack of SPTEncoreLabels:
// "For fans of " 11pt #B3B3B3, "Yzomandias" 17pt #FFFFFF at {0, 19.3} 91x20.7, and a hidden one. A heading
// of a title alone is 20.7 tall (10.txt:2363). "Show all" is Components.UI.NavigationButtonHome, a sibling
// of the button's stack, 0 wide while it is not offered.
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Home.h"

static char kTitleKey, kShowAllKey, kHeldKey, kTriesKey, kAskedKey, kChevronKey, kTapKey;

// How often a heading with no title yet is looked at again.
static const NSUInteger kTries = 3;
// Between the title and its chevron, the Music app's "Recently Played ›".
static const CGFloat kChevronGap = 4;

// The chevron after the title, in the heading (so a tap on it is the heading's), sized from the title's font.
static UIImageView *chevronIn(UIView *heading, UIFont *font) {
    UIImageView *chevron = objc_getAssociatedObject(heading, &kChevronKey);
    if (!chevron) {
        chevron = [UIImageView new];
        chevron.translatesAutoresizingMaskIntoConstraints = NO;
        chevron.userInteractionEnabled = NO;
        chevron.isAccessibilityElement = NO;
        chevron.tintColor = SGRSecondary();
        chevron.contentMode = UIViewContentModeCenter;
        objc_setAssociatedObject(heading, &kChevronKey, chevron, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (chevron.superview != heading) [heading addSubview:chevron];
    UIImageSymbolConfiguration *size = [UIImageSymbolConfiguration configurationWithFont:font scale:UIImageSymbolScaleSmall];
    if (![chevron.preferredSymbolConfiguration isEqual:size]) {
        chevron.preferredSymbolConfiguration = size;
        chevron.image = [UIImage systemImageNamed:@"chevron.forward"];
    }
    return chevron;
}

// The heading's tap fires Spotify's own "Show all", concealed in the heading, so it opens what that opens; the
// title button's own touch is cancelled as the tap is recognized.
@interface SGRHeadingTapTarget : NSObject
@end

@implementation SGRHeadingTapTarget
+ (void)showAllTapped:(UITapGestureRecognizer *)tap {
    UIView *heading = tap.view;
    UIView *showAll = SGRFindByIdentifier(heading, @"Components.UI.NavigationButtonHome", &kShowAllKey);
    if (showAll && SGShownUnder(showAll, heading)) SGRActivate(showAll);
}
@end

static UITapGestureRecognizer *headingTap(UIView *heading) {
    UITapGestureRecognizer *tap = objc_getAssociatedObject(heading, &kTapKey);
    if (tap) return tap;
    tap = [[UITapGestureRecognizer alloc] initWithTarget:SGRHeadingTapTarget.class action:@selector(showAllTapped:)];
    [heading addGestureRecognizer:tap];
    objc_setAssociatedObject(heading, &kTapKey, tap, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return tap;
}

// What the title is held on, so the constraints are made again only when it changes.
@interface SGRHeadingHold : NSObject
@property (nonatomic, weak) UILabel *label;
@property (nonatomic, weak) UIView *limit;
@property (nonatomic, copy) NSArray<NSLayoutConstraint *> *constraints;
@end

@implementation SGRHeadingHold
@end

static UIView *headingAround(UIView *button) {
    NSUInteger depth = 0;
    for (UIView *v = button.superview; v && depth < 4; v = v.superview, depth++) {
        if ([v.accessibilityIdentifier isEqualToString:@"Components.UI.SectionHeadingHome"]) return v;
    }
    return nil;
}

// The label that is the title: the largest text showing under the button, its own label aside. A label the stack
// has not sized yet counts, since the constraints take its place from the layout rather than from its bounds.
static UILabel *titleLabelIn(UIView *button, UILabel *mine) {
    __block UILabel *title = nil;
    SGForEachView(button, ^(UIView *v) {
        if (v == mine || ![v isKindOfClass:UILabel.class]) return;
        UILabel *label = (UILabel *)v;
        if (!label.text.length || !SGShownUnder(label, button)) return;
        if (!title || label.font.pointSize > title.font.pointSize) title = label;
    });
    return title;
}

static void restyle(UIView *button) {
    UIView *heading = headingAround(button);
    if (!heading) return;
    // The heading names the shelf (HomeShelves.m). The page's list may have sized the shelf before the heading
    // was in; one switched off, or the one Top picks is to draw, is then measured again now that it is known. The
    // large shelf's heading goes with the band above its cards, unless Show Top picks heading is on (HomeTopPicks.x).
    UIView *shelf = heading.superview;
    while (shelf && ![shelf isKindOfClass:UICollectionView.class]) shelf = shelf.superview;
    NSString *identity = SGRHomeShelfIdentity(shelf);
    if (identity && ![objc_getAssociatedObject(shelf, &kAskedKey) isEqualToString:identity]) {
        objc_setAssociatedObject(shelf, &kAskedKey, identity, OBJC_ASSOCIATION_COPY_NONATOMIC);
        SGRHomeNoteShelf(identity);
        BOOL wanted = !SGRHomeInTopPicks(heading) && SGEnabled(SGRKeyHomeTopPicks) && [identity isEqualToString:SGRHomeTopPicksFrom()];
        if (SGRHomeShelfHidden(identity) || wanted) SGRHomeMeasureAgain(heading);
    }
    UILabel *mine = objc_getAssociatedObject(button, &kTitleKey);
    UILabel *theirs = titleLabelIn(button, mine);
    SGRHeadingHold *held = objc_getAssociatedObject(button, &kHeldKey);
    if (!theirs) {
        // A heading between two shelves: nothing to hold the title on until its label has text again.
        mine.hidden = YES;
        ((UIView *)objc_getAssociatedObject(heading, &kChevronKey)).hidden = YES;
        ((UIGestureRecognizer *)objc_getAssociatedObject(heading, &kTapKey)).enabled = NO;
        if (held.constraints) [NSLayoutConstraint deactivateConstraints:held.constraints];
        objc_setAssociatedObject(button, &kHeldKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }
    if (!mine) {
        mine = [UILabel new];
        mine.userInteractionEnabled = NO;
        mine.accessibilityElementsHidden = YES;
        mine.lineBreakMode = NSLineBreakByTruncatingTail;
        mine.translatesAutoresizingMaskIntoConstraints = NO;
        objc_setAssociatedObject(button, &kTitleKey, mine, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    BOOL added = mine.superview != button;
    if (added) [button addSubview:mine];
    mine.hidden = NO;

    UIFont *font = SGCategoryCappedFont(UIFontTextStyleTitle3, UIFontWeightBold, UIContentSizeCategoryLarge);
    if (![mine.font isEqual:font]) mine.font = font;
    if (![mine.text isEqualToString:theirs.text]) mine.text = theirs.text;
    if (![mine.textColor isEqual:theirs.textColor]) mine.textColor = theirs.textColor;
    if (theirs.alpha != 0) theirs.alpha = 0;

    // Whether "Show all" is offered is read off the hidden flags, not off its width: it has none to go by until
    // the layout resolves. Offered, it goes and a chevron after the title stands for it, the whole heading opening
    // what it opens by firing it (showAllTapped), so the destination stays Spotify's own.
    UIView *showAll = SGRFindByIdentifier(heading, @"Components.UI.NavigationButtonHome", &kShowAllKey);
    BOOL offered = showAll && SGShownUnder(showAll, heading);
    UIImageView *chevron = chevronIn(heading, font);
    chevron.hidden = !offered;
    if (offered) SGRSuppress(showAll);
    headingTap(heading).enabled = offered;
    // VoiceOver keeps "Show all" as an action of the heading, under Spotify's own name for it.
    NSString *showAllName = offered ? showAll.accessibilityLabel : nil;
    if (![button.accessibilityCustomActions.firstObject.name ?: @"" isEqualToString:showAllName ?: @""]) {
        __weak UIView *weakHeading = heading;
        button.accessibilityCustomActions = showAllName.length ? @[[[UIAccessibilityCustomAction alloc] initWithName:showAllName
            actionHandler:^BOOL(UIAccessibilityCustomAction *action) {
                UIView *source = SGRFindByIdentifier(weakHeading, @"Components.UI.NavigationButtonHome", &kShowAllKey);
                return source && SGRActivate(source);
            }]] : nil;
    }

    // The leading edge and the baseline are Spotify's label's; the title ends before the chevron, or before the
    // heading's trailing edge while there is none, and truncates rather than push anything.
    UIView *limit = offered ? chevron : heading;
    if (added || held.label != theirs || held.limit != limit) {
        if (held.constraints) [NSLayoutConstraint deactivateConstraints:held.constraints];
        NSMutableArray<NSLayoutConstraint *> *constraints = [NSMutableArray arrayWithArray:@[
            [mine.leadingAnchor constraintEqualToAnchor:theirs.leadingAnchor],
            [mine.firstBaselineAnchor constraintEqualToAnchor:theirs.firstBaselineAnchor],
            [mine.trailingAnchor constraintLessThanOrEqualToAnchor:heading.trailingAnchor],
        ]];
        if (offered) [constraints addObjectsFromArray:@[
            [chevron.leadingAnchor constraintEqualToAnchor:mine.trailingAnchor constant:kChevronGap],
            [chevron.centerYAnchor constraintEqualToAnchor:mine.centerYAnchor],
            [chevron.trailingAnchor constraintLessThanOrEqualToAnchor:heading.trailingAnchor],
        ]];
        [NSLayoutConstraint activateConstraints:constraints];
        held = [SGRHeadingHold new];
        held.label = theirs;
        held.limit = limit;
        held.constraints = constraints;
        objc_setAssociatedObject(button, &kHeldKey, held, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(button, &kTriesKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        static dispatch_once_t once;
        dispatch_once(&once, ^{ SGLog(@"redesign home: heading \"%@\" %.0fpt drawn at %.0fpt, held on Spotify's label", theirs.text, theirs.font.pointSize, font.pointSize); });
    }
}

// Looks again once the layout has settled, while the heading has no label with text to hold the title on.
static void restyleWhenReady(UIView *button) {
    if (objc_getAssociatedObject(button, &kHeldKey)) return;
    NSUInteger tries = [objc_getAssociatedObject(button, &kTriesKey) unsignedIntegerValue];
    if (tries >= kTries) return;
    objc_setAssociatedObject(button, &kTriesKey, @(tries + 1), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    dispatch_async(dispatch_get_main_queue(), ^{
        if (button.window) restyle(button);
    });
}

%hook _TtCOOOE11Home_ECMKitO19LegacyUI_ECMCoreKit10Components18SectionHeadingHome2UI7Private28NoIntrinsicContentSizeButton
- (void)layoutSubviews {
    %orig;
    CFTimeInterval began = SGRHomeProbeBegin();
    restyle((UIView *)self);
    restyleWhenReady((UIView *)self);
    SGRHomeProbeEnd(SGRHomeProbeHeadings, began);
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
    SGRequireClasses(@[@"_TtCOOOE11Home_ECMKitO19LegacyUI_ECMCoreKit10Components18SectionHeadingHome2UI7Private28NoIntrinsicContentSizeButton"]);
}
