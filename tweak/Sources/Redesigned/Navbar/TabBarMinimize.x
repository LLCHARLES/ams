// What minimizes the glass bar and what brings it back (TabBar.x draws it): a page scrolled down by a
// finger or the fling after it, and scrolled back up or to its top (MinimizeStep.h). After the bar changes some
// other way (a tap on its circle, a tab, the player), only a new touch minimizes it again: the fling still
// running would otherwise undo the tap at once; another tab (TabBar.x);
// and the full screen player opening or closing, which takes Spotify's pictures of the bars to move with it
// and would have moved the card from the tab bar's row back up to its place above the bar.
//
// Only a page's own scroll views count: those inside Spotify's tab bar container. The player and the now
// playing bar are outside it, and a shelf scrolling sideways has nothing to scroll down.
#import "Core/SGCore.h"
#import "Navbar.h"
#import "MinimizeStep.h"
#import "Shared/Player/PlayerEvents.h"

static Class sg_containerClass;
static __weak UIScrollView *sg_page;
static char kInContainer;
static NSUInteger sg_hierarchy = 2;
static SGRMinimizeTrack sg_track;
static BOOL sg_waitForTouch;

static BOOL inContainer(UIView *view) {
    for (UIResponder *r = view.nextResponder; r; r = r.nextResponder) if ([r isKindOfClass:sg_containerClass]) return YES;
    return NO;
}

static void scrolled(UIScrollView *scrollView) {
    if (!scrollView.isTracking && !scrollView.isDecelerating) return;
    CGFloat offset = scrollView.contentOffset.y;
    if (scrollView != sg_page) {
        sg_page = scrollView;
        sg_track = (SGRMinimizeTrack){offset, SGRTabBarMinimized()};
    }
    // The bar changed some other way (a tab, the player): the scroll counts from here.
    if (sg_track.minimized != SGRTabBarMinimized()) {
        sg_track = (SGRMinimizeTrack){offset, SGRTabBarMinimized()};
        sg_waitForTouch = YES;
    }
    if (scrollView.isTracking) sg_waitForTouch = NO;
    UIEdgeInsets inset = scrollView.adjustedContentInset;
    CGFloat top = -inset.top, bottom = scrollView.contentSize.height + inset.bottom - scrollView.bounds.size.height;
    BOOL minimized = SGRMinimizeStep(&sg_track, offset, top, bottom);
    if (minimized == SGRTabBarMinimized() || (minimized && !SGEnabled(SGRKeyNavbarMinimize))) return;
    if (minimized && sg_waitForTouch) return;
    SGRSetTabBarMinimized(minimized, YES);
}

// Moving a wrapper mid-fling does not send didMoveToSuperview to its scroll view.
%hook UIView
- (void)didMoveToSuperview {
    sg_hierarchy += 2;
    %orig;
}
%end

%hook UIScrollView
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)recognizer {
    BOOL begin = %orig;
    // A wrapper may have changed page without changing our window or superview.
    if (begin && recognizer == self.panGestureRecognizer)
        objc_setAssociatedObject(self, &kInContainer, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return begin;
}
- (void)didMoveToWindow {
    %orig;
    objc_setAssociatedObject(self, &kInContainer, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
- (void)setContentOffset:(CGPoint)offset {
    %orig;
    NSNumber *inside = objc_getAssociatedObject(self, &kInContainer);
    // Low bit: a page. Remaining bits: the hierarchy in which it was classified.
    NSUInteger cached = inside.unsignedIntegerValue;
    if ((cached & ~(NSUInteger)1) != sg_hierarchy) {
        cached = sg_hierarchy | inContainer(self);
        inside = @(cached);
        objc_setAssociatedObject(self, &kInContainer, inside, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (cached & 1) scrolled(self);
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    sg_containerClass = NSClassFromString(@"_TtC23NavigationUI_TabBarImpl19TabBarContainerImpl");
    if (!sg_containerClass) return;
    %init;
    [NSNotificationCenter.defaultCenter addObserverForName:SGPlayerTransitionNotification object:nil queue:nil
                                                usingBlock:^(NSNotification *note) { SGRSetTabBarMinimized(NO, NO); }];
}
