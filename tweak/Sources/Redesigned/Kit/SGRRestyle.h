// Keeping Spotify's views the way a redesigned screen set them: Spotify re-applies its own look on
// reuse, on state changes and on every layout pass, so each helper here either survives that or is
// cheap enough to run again on every pass. Nothing here uses `hidden` on a view Spotify arranges in a
// stack: OverflowStackView and some Encore stacks trap in updateConstraints when an arranged view
// hides, so a view goes away by alpha, touches and accessibility instead.
//
// Ownership: what a helper creates belongs to the view it was made for (associated objects), and a
// helper keeps only weak references to Spotify's views.
// Threading: main thread only.
#import <UIKit/UIKit.h>

#pragma mark - views

// The first immediate child whose class name contains marker; no recursive search or cache.
UIView *SGRChildNamed(UIView *host, NSString *marker);
// First nonempty UILabel text, trimmed of whitespace and newlines, depth first including root and hidden labels.
// nil when no label has text.
NSString *SGRFirstLabelText(UIView *root);
// First image-bearing image view at least 80pt wide, depth first; otherwise the first empty one that wide.
UIImageView *SGRHeaderArtworkIn(UIView *root);
// A page's large-title label, retained under key and reattached when needed. Text and layout stay local.
UILabel *SGRLargeTitleIn(UIView *host, const void *key);
// Empty-mask suppression, without changing UIView.hidden or Spotify's layout. Conceal additionally hides
// the layer; blank keeps collection views laying out and creating their cells.
void SGRBlankView(UIView *view);
void SGRConcealView(UIView *view);

// Alpha 0, no touches, hidden from accessibility, and kept so: the instance becomes a runtime subclass
// of its own class (the way KVO does it, `class` still answers the original) whose setAlpha: and
// setUserInteractionEnabled: hold those values. For plain UIKit views (a UIImageView, a UILabel). One of
// Spotify's Swift classes, or an instance KVO observes, keeps its alpha (only its alpha: touches and
// accessibility are set again on each call) through an override on its class that holds only the instances
// suppressed; where neither takes, the values are set once instead, re-applied
// on the next call, and a log line says so once.
void SGRSuppress(UIView *view);

// Alpha 1 whatever Spotify sets, for one of Spotify's own classes, through the same override on its class that
// SGRSuppress uses (only the instances asked for are held); elsewhere it is only set on each call and a log line says so.
// For a header the redesign keeps solid where Spotify fades it as the page scrolls (Album/AlbumHeader.x).
void SGRKeepOpaque(UIView *view);

// Alpha 0, no touches, hidden from accessibility, set again on every call: for Spotify's Swift views,
// which SGRSuppress cannot keep.
void SGRVanish(UIView *view);

// Digits of one width in the label, kept through Spotify's own setText:, setAttributedText: and
// setFont: by a runtime subclass of the instance, like SGRSuppress. Idempotent.
void SGRMonospacedDigits(UILabel *label);

// SGRMonospacedDigits, in the Music app's type for the player's times: the system font, semibold, caption-sized
// (12 pt, it follows the text size), a dim translucent white as the Music app's times are, with a real minus sign in
// place of the hyphen before the time left. Kept through Spotify's own setters as the digits are. Idempotent.
void SGRTimeLabelStyle(UILabel *label);
// While `lit` is YES the label's ink is left to the caller (a scrub turns the times white); NO takes it back at the
// next pass of Spotify's setters. Only for a label SGRTimeLabelStyle was given.
void SGRTimeLabelLit(UILabel *label, BOOL lit);

// `changed` after every setImage: on the image view, Spotify's included, for as long as the view lives: by a
// runtime subclass of the instance like SGRSuppress, or, for one of Spotify's own classes (Encore's image
// views, which no instance of can be subclassed), by an override on that class, which only ever reports the
// instances that asked. A second call replaces the block. NO when neither took, which a log line says once:
// the caller then only sees what its own passes read.
//
// This is how a picture that lands after a screen has been laid out reaches it: setting an image lays no
// ancestor out, so nothing else tells the screen it is there.
BOOL SGRObserveImage(UIImageView *view, void (^changed)(UIImageView *view));

// `changed` after every setText: and setAttributedText: on a plain UILabel, Spotify's included, for as long as the
// label lives, by a runtime subclass of the instance like SGRSuppress. A second call replaces the block. NO when the
// label cannot be subclassed. For a label of the redesign's drawn over one of Spotify's: a cell reused for another
// item is given its new text without any layout pass that would tell.
BOOL SGRObserveText(UILabel *label, void (^changed)(UILabel *label));

// `laidOut` after every layoutSubviews of the view, Spotify's included, for as long as the view lives, by
// a runtime subclass of the instance like SGRSuppress. A second call replaces the block, and a pass started
// from inside the block is not reported again. NO when the view cannot be subclassed (one of Spotify's Swift
// classes, a KVO-observed instance): the caller then has only the passes it hooks itself to work from.
//
// For a screen that arranges Spotify's controls its own way: a parent lays its children out after the
// hook that placed them has returned, so frames set from an ancestor's pass are the ones overwritten.
BOOL SGRObserveLayout(UIView *view, void (^laidOut)(UIView *view));

// Hidden, alpha, window and superview changes of this view or any ancestor, including an ancestor
// reparented within the same window. One callback per target; nil removes it. Main thread only.
void SGRObserveVisibility(UIView *view, dispatch_block_t changed);

static inline CGRect SGRVisibleRectInWindow(UIView *view) {
    UIWindow *window = view.window;
    if (!window) return CGRectNull;
    CGRect remaining = CGRectIntersection(window.bounds, [view convertRect:view.bounds toView:window]);
    for (UIView *v = view; v; v = v.superview) {
        if (v.hidden || v.alpha <= 0 || CGRectIsEmpty(remaining)) return CGRectNull;
        if (v != view && v != window && v.clipsToBounds)
            remaining = CGRectIntersection(remaining, [v convertRect:v.bounds toView:window]);
    }
    return remaining;
}

static inline BOOL SGRViewInViewport(UIView *view, CGRect covered) {
    CGRect visible = SGRVisibleRectInWindow(view);
    return !CGRectIsEmpty(visible) && !CGRectContainsRect(covered, visible);
}

// Observe only scroll views above a live clip. Weak membership does not keep a former page alive.
static inline void SGRBindViewportScrolls(UIView *view, NSHashTable *bound, id observer, void *context) {
    for (UIView *scroll in bound.allObjects) {
        if (view.window && [view isDescendantOfView:scroll]) continue;
        [scroll removeObserver:observer forKeyPath:@"contentOffset" context:context];
        [bound removeObject:scroll];
    }
    for (UIView *v = view.window ? view.superview : nil; v; v = v.superview) {
        if (![v isKindOfClass:UIScrollView.class] || [bound containsObject:v]) continue;
        [bound addObject:v];
        [v addObserver:observer forKeyPath:@"contentOffset" options:0 context:context];
    }
}

// The first view under `root` (itself included) with the accessibility identifier, depth first. The
// answer is kept weakly on `root` under `cacheKey` and searched for again only when it is gone, has
// left `root` or changed its identifier. nil when there is none; a miss is not cached.
UIView *SGRFindByIdentifier(UIView *root, NSString *identifier, const void *cacheKey);

// Whether `view` is the profile avatar that opens the side drawer, in the Home, Search and Library headers. Known by
// its identifier, which every version gives it: 9.1.88 draws it in an AdaptiveFaceContainer, 9.1.90 in an Encore
// button around a listening-activity pulse, which a check by class alone took for something else.
BOOL SGRIsAvatar(UIView *view);

// A view that draws only a shadow, for a view whose own layer clips (rounded artwork): made once per
// host under `key`, inserted at the bottom of `host`. The caller gives it its frame and transform; its
// shadowPath follows its bounds and cornerRadius.
@interface SGRShadowPlate : UIView
@property (nonatomic) CGFloat cornerRadius;   // SGRRadiusArtwork unless set
@end
SGRShadowPlate *SGRShadowPlateIn(UIView *host, const void *key);

#pragma mark - Spotify's controls and pages

// Element_List's retrieval content, identified once per runtime class (nil is not track content).
BOOL SGRIsTrackContent(UIView *content);
// A dropped cell keeps its content's natural height, hidden and clipped, rather than squeezing Spotify's
// constraints to zero. Each page keeps its own key, including across layout and reuse.
void SGRCollapseCell(UICollectionViewCell *cell, CGFloat natural, const void *key);
// Also restores Album's settled cells, whose value under key includes its measured lead and text size.
void SGRRestoreCell(UICollectionViewCell *cell, const void *key);

// The base surface a list cell paints over a page's field, cleared: the #121212 the redesign's AMOLED
// black has already turned black, on the cell and on everything under it nearly as wide as the cell, and
// the full-width fade a "see more" draws over its last row, which the black makes a dark band. The Kit's
// repaint hook misses all of it -- it only hears about a color when Spotify sets it, and a cell is painted
// before it is inside the page and brings its old paint with it when it is reused -- so this runs from the
// cell's own layout pass, and is cheap enough to.
//
// Only what is nearly as wide as the cell: a badge's black disc, a card's gray and an image's placeholder
// are their own. A cell nested inside the cell and narrower than that (a card in a carousel) is not walked
// into: its own row decides for it.
void SGRClearCellPaint(UIView *cell);

// Fires one of Spotify's own buttons the way a tap on it would: the first control under `source`, through
// SGRFire, and through -accessibilityActivate when that control answers its touches some other way. For a
// control the redesign conceals and draws itself (the action row's buttons, a header's creator line).
// A source Spotify has disabled is not fired at all, by either route: NO, and nothing was dispatched.
BOOL SGRActivate(UIView *source);

// Whether Spotify's button is enabled: its first control is enabled and neither it nor `source` carries the
// not-enabled accessibility trait. NO for nil. What a mirror of the button copies and SGRActivate checks.
BOOL SGRSourceEnabled(UIView *source);

// Fires a control's action the way a tap would: the actions registered for primary action triggered,
// else those for touch up inside. NO when the control has neither (an Encore control that reads its
// touches through a gesture recognizer); what was found is logged once per class.
BOOL SGRFire(UIControl *control);

// Gives a scroll view the hard top edge effect, a dark band, and keeps the soft one SGREdgeEffect.x sets on every
// other scroll view off it: for text that stays over a page scrolling under it (Home's kept title, HomeHeader.x).
// iOS 26 on; nothing before.
void SGRHardTopEdge(UIScrollView *scrollView);
