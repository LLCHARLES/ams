// SGRMinimizeStep on the Mac: cc -I../../tweak/Sources/Redesigned/Navbar minimize-check.c -o build/minimize-check && build/minimize-check
#include <assert.h>
#include <stdio.h>
#include "MinimizeStep.h"

// A page from -100 (its top, under a 100 pt header inset) to 2000.
static bool step(SGRMinimizeTrack *t, CGFloat offset) { return SGRMinimizeStep(t, offset, -100, 2000); }

int main(void) {
    SGRMinimizeTrack t = {-100, false};
    assert(!step(&t, -90));          // a little way down: a finger resting
    assert(!step(&t, -77));
    assert(step(&t, -76));           // 24 down from the top: minimized
    assert(step(&t, 600));           // further down
    assert(step(&t, 590));           // a jitter back up
    assert(step(&t, 200));           // back up part way, mid-list: still minimized, as the Music app's
    assert(step(&t, 584));           // down again
    assert(!step(&t, 2000));         // the foot expands
    assert(!step(&t, 2080));         // pulled past it
    assert(!step(&t, 1990));         // springing back and up a little
    assert(!step(&t, 1500));         // up from the foot, expanded
    assert(step(&t, 1524));          // 24 down from where it turned: minimized
    assert(!step(&t, -100));         // the top always expands
    assert(!step(&t, -140));         // pulled past the top

    SGRMinimizeTrack s = {0, false}; // a page with almost nothing to scroll
    assert(!SGRMinimizeStep(&s, 80, 0, 100));
    s.minimized = true;              // and one that cannot scroll leaves a minimized bar minimized
    assert(SGRMinimizeStep(&s, 0, 0, 100));
    puts("minimize-check: ok");
    return 0;
}
