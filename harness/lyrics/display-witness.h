#pragma once
#import <QuartzCore/QuartzCore.h>
#import "../harness-wait.h"

// A parked view cannot provide a callback to wait on. Use an independent
// display link to prove the compositor had a chance to call the view.
@interface LyricsFrameWitness : NSObject
@property(nonatomic) NSUInteger frames;
- (void)frame:(CADisplayLink *)link;
@end
@implementation LyricsFrameWitness
- (void)frame:(CADisplayLink *)link { self.frames++; }
@end
void LyricsAfterDisplayFrames(dispatch_block_t next) {
    LyricsFrameWitness *witness = [LyricsFrameWitness new];
    CADisplayLink *link = [CADisplayLink displayLinkWithTarget:witness selector:@selector(frame:)];
    [link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    HarnessWhen(@"two compositor frames", ^BOOL { return witness.frames >= 2; }, ^{
        [link invalidate];
        next();
    });
}
