// Player services outside the artwork and tap-routing regressions.
#import "Shared/Gestures/Gestures.h"
#import "Shared/Haptics/Haptics.h"
#import "Shared/Player/SpeedPitch.h"

__weak UIView *sg_npvBackdropRoot;
#import "Headers/SPTNowPlayingPlaybackController.h"
@implementation SPTNowPlayingPlaybackControllerImplementation
- (id)initWithPlayer:(id)player testManager:(id)manager inStreamClient:(id)client { return [super init]; }
- (BOOL)seekingAllowed { return YES; }
- (BOOL)isPaused { return NO; }
- (BOOL)isShuffling { return NO; }
- (BOOL)canSkipNext { return YES; }
- (BOOL)disallowPausing { return NO; }
- (BOOL)disallowResuming { return NO; }
- (void)seekForwardBySeconds:(double)s {}
- (void)seekBackwardBySeconds:(double)s {}
- (void)skipToNextWhileDragging:(BOOL)b {}
- (void)skipToPreviousWhileDragging:(BOOL)b {}
- (void)setPaused:(BOOL)b {}
- (void)setGlobalShuffleMode:(BOOL)b {}
- (void)toggleRepeatMode {}
@end
id harnessPlaybackController(void) {
    return [[SPTNowPlayingPlaybackControllerImplementation alloc] initWithPlayer:nil testManager:nil inStreamClient:nil];
}
BOOL SGPlayerSpeedAllowed(void) { return NO; }
double SGPlayerSpeed(void) { return 1; }
void SGSetPlayerSpeed(double speed) {}
void SGPlayFeedback(SGFeedback feedback) {}
// The audio quality badge (Shared/Player/AudioQuality.x), off until switched on: off, Player.x's time unit places none.
void SGAudioQualityPlaceBadge(UIView *unitView) {}
