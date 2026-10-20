// When a page's scroll minimizes the glass bar and when it brings it back (TabBarMinimize.x), apart from
// UIKit so harness/tabbar/minimize-check.c runs it on the Mac.
//
// A scroll down of kSGRMinimizeTravel from where the page last turned minimizes the bar, and only reaching the top or
// the foot of the list brings it back (or a tap on its circle, TabBar.x): the Music app's bar stays minimized while a
// list is scrolled back up part way (its owner's recordings), where Vitrine's used to expand at a scroll up of as much
// anywhere. Less than kSGRMinimizeTravel down is a finger resting on the glass, not a scroll. Pulling past either end is
// that end, and a page with less than kSGRMinimizeRange to scroll leaves the bar as it is.
#include <CoreGraphics/CGBase.h>
#include <math.h>
#include <stdbool.h>

static const CGFloat kSGRMinimizeTravel = 24;
static const CGFloat kSGRMinimizeRange = 120;

typedef struct {
    CGFloat turn;     // where the scroll last turned while expanded: its lowest offset
    bool minimized;
} SGRMinimizeTrack;

// One step of a scroll: `offset` the content offset, `top` and `bottom` the least and most it rests at.
static inline bool SGRMinimizeStep(SGRMinimizeTrack *track, CGFloat offset, CGFloat top, CGFloat bottom) {
    if (bottom - top < kSGRMinimizeRange) return track->minimized;
    offset = fmin(fmax(offset, top), bottom);
    if (offset <= top + 1 || offset >= bottom - 1) {
        track->minimized = false;
        track->turn = offset;
    } else if (track->minimized || offset < track->turn) {
        track->turn = offset;
    } else if (offset - track->turn >= kSGRMinimizeTravel) {
        track->minimized = true;
        track->turn = offset;
    }
    return track->minimized;
}
