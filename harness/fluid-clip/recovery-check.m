// The player clip's failure recovery, compiled from PlayerMotion.x by build.sh: an item or looper that fails
// after the clip has drawn a frame is played again from the same file, a bounded number of times, and a clip
// that may not play, or that is being replaced, is not rebuilt. The second half drives the production
// `beginTrack` with doubles, so the handover a skip starts is the real one. Exits 1 on any failure.
#import <Foundation/Foundation.h>

#include "player-motion-recovery.inc"

static int failures;

static void check(BOOL ok, NSString *what) {
    printf("  %s %s\n", ok ? "ok  " : "FAIL", what.UTF8String);
    if (!ok) failures++;
}

// What the view does with the policy: `saw` is the layer's readiness as it reads it, latched per clip; the
// failure is read on the pass after it is reported, and answered with the clip as it is then.
static void saw(SGRPlayerMotionRecovery *recovery, BOOL readyNow) {
    SGRPlayerMotionRecoverySaw(recovery, readyNow);
}

static SGRPlayerMotionRecoveryStep answer(SGRPlayerMotionRecovery *recovery, BOOL mayPlay) {
    return SGRPlayerMotionRecoveryRuns(recovery, mayPlay);
}

// The clip as `beginTrack` sees it: the one on screen is told to hand over, and that is what the policy does.
@class UIView;

@interface SGRPlayerMotionView : NSObject {
@public
    SGRPlayerMotionRecovery recovery;
}
- (void)handover;
@end

@implementation SGRPlayerMotionView
- (void)handover {
    SGRPlayerMotionRecoveryTrack(&recovery, NO);
}
@end

// The surface `beginTrack` reads, as the player is on screen with Animated chosen.
typedef NS_ENUM(NSInteger, SGRPlayerBackgroundKind) { SGRPlayerBackgroundFluid, SGRPlayerBackgroundAnimated };
static SGRPlayerBackgroundKind background = SGRPlayerBackgroundAnimated;
static SGRPlayerBackgroundKind SGRPlayerBackground(void) { return background; }
static BOOL videoShowing(void) { return NO; }
static BOOL motionAllowed(void) { return YES; }
static BOOL consumerOnScreen = YES;
static BOOL consumerVisible(void) { return consumerOnScreen; }
static BOOL seen(UIView *view) { return YES; }
static void clear(BOOL animated) {}
// As PlayerMotion.x reads them: what a clip is shown under, and the Visualizer that stands in for a missing clip.
static BOOL clipWanted(void) {
    return SGRPlayerBackground() == SGRPlayerBackgroundAnimated && !videoShowing() && motionAllowed();
}
static void SGRPlayerVisualiserUpdate(void) {}
static void SGRPlayerHoldField(void) {}

static NSString *sg_track, *sg_shown, *sg_noClip;
static NSUInteger sg_begun;
static SGRPlayerMotionView *sg_motion, *sg_coverClip;

#include "player-motion-handover.inc"

int main(void) {
    @autoreleasepool {
        check(kRebuildsMost == 3, @"the bound is three rebuilds per clip");

        // A clip that drew a frame, then had its item fail: played again from the same file.
        SGRPlayerMotionRecovery recovery = {0};
        SGRPlayerMotionRecoveryBegin(&recovery);
        saw(&recovery, YES);
        check(answer(&recovery, YES) == SGRPlayerMotionRecoveryRebuild && recovery.rebuilds == 1,
              @"ready-then-failed item recovers");

        // The looper swaps in a later item that fails before decoding its own first frame. The layer's readiness
        // reads NO by then (it belongs to the item the player has), but this clip drew one earlier: it recovers,
        // and readiness seen NO does not take the latch back.
        recovery = (SGRPlayerMotionRecovery){0};
        SGRPlayerMotionRecoveryBegin(&recovery);
        saw(&recovery, YES);   // the first item drew
        saw(&recovery, NO);   // the swap took the layer's readiness back
        check(answer(&recovery, YES) == SGRPlayerMotionRecoveryRebuild && recovery.rebuilds == 1,
              @"a later item failing before its first frame recovers");
        // And the latch still holds after a rebuild, whose first frame has not decoded yet.
        check(answer(&recovery, YES) == SGRPlayerMotionRecoveryRebuild && recovery.rebuilds == 2,
              @"the latch holds over a rebuild");

        // The song paused before the answer: nothing is built, and the pass that resumes it rebuilds then.
        recovery = (SGRPlayerMotionRecovery){0};
        SGRPlayerMotionRecoveryBegin(&recovery);
        saw(&recovery, YES);
        check(answer(&recovery, NO) == SGRPlayerMotionRecoveryNothing && recovery.rebuilds == 0,
              @"paused: the failure is not rebuilt");
        check(answer(&recovery, YES) == SGRPlayerMotionRecoveryRebuild && recovery.rebuilds == 1,
              @"paused: the clip is rebuilt once it plays again");

        // Detached: same gate, and the clip that comes back into a window is rebuilt once, not twice.
        recovery = (SGRPlayerMotionRecovery){0};
        SGRPlayerMotionRecoveryBegin(&recovery);
        saw(&recovery, YES);
        check(answer(&recovery, NO) == SGRPlayerMotionRecoveryNothing && recovery.rebuilds == 0,
              @"detached: the failure is not rebuilt");
        check(answer(&recovery, YES) == SGRPlayerMotionRecoveryRebuild && recovery.rebuilds == 1,
              @"detached: the clip is rebuilt once it is on screen again");

        // The track is replaced while the answer is on its way: the clip that left is told to stop, and the pass
        // finds nothing to play again. The clip that replaces it has its own count.
        recovery = (SGRPlayerMotionRecovery){0};
        SGRPlayerMotionRecoveryBegin(&recovery);
        saw(&recovery, YES);
        SGRPlayerMotionRecoveryCancel(&recovery);
        check(answer(&recovery, YES) == SGRPlayerMotionRecoveryNothing && recovery.rebuilds == 0,
              @"replacement during recovery: no rebuild for the clip that left");
        SGRPlayerMotionRecoveryBegin(&recovery);
        saw(&recovery, YES);
        check(answer(&recovery, YES) == SGRPlayerMotionRecoveryRebuild && recovery.rebuilds == 1,
              @"replacement during recovery: the next clip recovers from its own first failure");

        // A skip on screen: the outgoing clip waits kHandOver, so the next clip crosses over it. `beginTrack`
        // stops its recovery at once, so a failure during that wait is not rebuilt, though the clip drew and its
        // count is untouched.
        SGRPlayerMotionView *outgoing = [SGRPlayerMotionView new];
        SGRPlayerMotionRecoveryBegin(&outgoing->recovery);
        saw(&outgoing->recovery, YES);
        sg_track = @"spotify:track:outgoing";
        sg_shown = sg_track;
        sg_motion = outgoing;
        background = SGRPlayerBackgroundAnimated;
        check(beginTrack(@"spotify:track:next"), @"a skip on screen keeps the last clip for the handover");
        check(sg_motion == outgoing, @"the outgoing clip is still the one on screen");
        check(answer(&outgoing->recovery, YES) == SGRPlayerMotionRecoveryNothing && outgoing->recovery.rebuilds == 0,
              @"a failure during the 0.4 s handover is not rebuilt");

        // The same track walked again (its Canvas came late) keeps the clip on screen and its recovery.
        SGRPlayerMotionView *same = [SGRPlayerMotionView new];
        SGRPlayerMotionRecoveryBegin(&same->recovery);
        saw(&same->recovery, YES);
        sg_motion = same;
        sg_shown = @"spotify:track:canvas";
        check(beginTrack(@"spotify:track:canvas"), @"the same track is walked again");
        check(answer(&same->recovery, YES) == SGRPlayerMotionRecoveryRebuild && same->recovery.rebuilds == 1,
              @"the same track walked again keeps its recovery");

        consumerOnScreen = NO;
        check(!beginTrack(@"spotify:track:hidden"), @"a hidden consumer does not start a clip lookup");
        consumerOnScreen = YES;

        // A file that keeps failing: three rebuilds, then given up, so the poster or Fluid takes over.
        recovery = (SGRPlayerMotionRecovery){0};
        SGRPlayerMotionRecoveryBegin(&recovery);
        saw(&recovery, YES);
        BOOL rebuilt = YES;
        for (NSUInteger i = 0; i < kRebuildsMost; i++) rebuilt = rebuilt && answer(&recovery, YES) == SGRPlayerMotionRecoveryRebuild;
        check(rebuilt && recovery.rebuilds == kRebuildsMost, @"each failure up to the bound rebuilds");
        check(answer(&recovery, YES) == SGRPlayerMotionRecoveryGiveUp, @"the failure past the bound gives up");
        check(answer(&recovery, YES) == SGRPlayerMotionRecoveryNothing, @"a given-up clip is not rebuilt again");

        // A clip that never drew a frame is the give-up count's, not the recovery's.
        recovery = (SGRPlayerMotionRecovery){0};
        SGRPlayerMotionRecoveryBegin(&recovery);
        saw(&recovery, NO);
        check(answer(&recovery, YES) == SGRPlayerMotionRecoveryNothing && recovery.rebuilds == 0,
              @"a clip that never drew is not rebuilt");

        printf("%s\n", failures ? "FAILED" : "all passed");
        return failures ? 1 : 0;
    }
}
