#import <objc/runtime.h>
#import "Redesigned/Kit/SGRHeaderInfo.h"
#import "Redesigned/Artist/ArtistShuffleHold.h"
#import "../harness-fail.h"

static NSUInteger impacts;
void SGPlayFeedback(SGFeedback feedback) { impacts++; }
BOOL SGRSourceEnabled(UIView *source) { return YES; }
BOOL SGRActivate(UIView *source) { HARNESS_FAIL(@"cancelled hold activated a control"); }

@interface HoldFixture : SGRArtistHold
@property(nonatomic) UIGestureRecognizerState phase;
@property(nonatomic) CGPoint point;
@end
@implementation HoldFixture
- (UIGestureRecognizerState)state { return self.phase; }
- (CGPoint)locationInView:(UIView *)view { return self.point; }
- (BOOL)readShuffleOn:(BOOL *)on playing:(BOOL *)playing {
    *on = YES;
    *playing = YES;
    return YES;
}
@end

int main(void) {
    @autoreleasepool {
        UIView *button = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 100, 48)];
        HoldFixture *hold = [HoldFixture new];
        [button addGestureRecognizer:hold];
        hold.artist = @"artist";
        hold.point = CGPointMake(50, 24);
        hold.phase = UIGestureRecognizerStateBegan;
        [hold trackHold];
        hold.point = CGPointMake(120, 24);
        hold.phase = UIGestureRecognizerStateChanged;
        [hold trackHold];
        hold.phase = UIGestureRecognizerStateEnded;
        [hold trackHold];
        if (impacts) HARNESS_FAIL(@"cancelled shuffle-on hold: expected 0 haptics, got %lu", (unsigned long)impacts);
        NSLog(@"PASS cancelled shuffle-on hold: 0 haptics");
    }
}
