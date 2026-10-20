// What minimizes the glass bar and what brings it back (TabBar.x draws it): a page scrolled down by a
// finger or the fling after it, and scrolled back up or to its top (MinimizeStep.h). After the bar changes some
// other way (a tap on its circle, a tab, the player), only a new touch minimizes it again: the fling still
// running would otherwise undo the tap at once; another tab (TabBar.x);
// and the full screen player opening, which takes Spotify's pictures of the bars to move with it and would have
// moved the card from the tab bar's row back up to its place above the bar. A player opened from the minimized bar
// closes back into it.
//
// Only a page's own scroll views count: those inside Spotify's tab bar container. The player and the now
// playing bar are outside it, and a shelf scrolling sideways has nothing to scroll down.
#import "Core/SGCore.h"
#import "Navbar.h"
#import "MinimizeStep.h"
#import "Shared/Player/PlayerEvents.h"

static Class sg_containerClass;
static __weak UIScrollView *sg_page, *sg_other;
static SGRMinimizeTrack sg_track;
static BOOL sg_waitForTouch;

static BOOL inContainer(UIView *view) {
    for (UIResponder *r = view.nextResponder; r; r = r.nextResponder) if ([r isKindOfClass:sg_containerClass]) return YES;
    return NO;
}

static void scrolled(UIScrollView *scrollView) {
    if ((!scrollView.isTracking && !scrollView.isDecelerating) || scrollView == sg_other) return;
    CGFloat offset = scrollView.contentOffset.y;
    if (scrollView != sg_page) {
        if (!inContainer(scrollView)) {
            sg_other = scrollView;
            return;
        }
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

%hook UIScrollView
- (void)setContentOffset:(CGPoint)offset {
    %orig;
    scrolled(self);
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    sg_containerClass = NSClassFromString(@"_TtC23NavigationUI_TabBarImpl19TabBarContainerImpl");
    if (!sg_containerClass) return;
    %init;
    // The player opens over the whole bar, so the bar is expanded first (its pictures move with the player); a player
    // opened from the minimized bar closes back into it, minimized again before the close takes the bar's pictures, as
    // the Music app's does (its owner asked). The appearance callbacks that announce a close come before its animator.
    [NSNotificationCenter.defaultCenter addObserverForName:SGPlayerTransitionNotification object:nil queue:nil
                                                usingBlock:^(NSNotification *note) {
        static BOOL openedMinimized;
        if (SGPlayerTransitionOpens()) {
            openedMinimized = SGRTabBarMinimized();
            SGRSetTabBarMinimized(NO, NO);
        } else if (openedMinimized) {
            SGRSetTabBarMinimized(YES, NO);
        }
    }];
}
