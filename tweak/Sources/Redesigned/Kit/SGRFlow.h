// A moving field of the artwork's colors, the Music app's animated background behind its player
// (issue #59): five soft discs of color, one for each quarter of the artwork and one for the whole of
// it, each drifting on a slow loop of its own and breathing in size, over the artwork's main color and
// under a shade that deepens toward the bottom, where the controls are.
//
// Radial gradient layers, moved a step at a time by a timer while it drifts and drawn small, then
// stretched to the screen: the discs are soft and slow, so neither shows. Animations the render server
// played cost the app nothing but drew the whole screen again on every frame (the figures are in
// SGRFlow.m). A timer, not a display link, so it asks nothing of the screen's frame rate; held still it
// has no timer and costs nothing at all.
//
// Stopping holds every disc where it is and starting again carries on from there, so the owner can stop
// it as often as it likes (the player's transition, the app leaving the screen) without a jump.
//
// Threading: main thread only.
#import <UIKit/UIKit.h>

@interface SGRFlowLayer : CALayer
// Five colors, as -[SGRPalette flowColors] gives them: top left, top right, bottom left, bottom right,
// the whole artwork's. Animated, they blend into the new ones where the discs are.
- (void)setColors:(NSArray<UIColor *> *)colors animated:(BOOL)animated;
// The color under the discs, darker than the artwork's main one; nil before any colors are set.
@property (nonatomic, readonly) UIColor *baseColor;
// Drifting, or held still where it is. Off to begin with.
@property (nonatomic) BOOL moving;
@end
