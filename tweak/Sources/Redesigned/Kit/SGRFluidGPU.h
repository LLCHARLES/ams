// Fluid artwork drawn on the GPU, the Music app's backdrop stage for stage (SGRFluidGPU.m): three turning copies of the
// cover drawn into a quarter-size picture, mixed toward black and saturated, blurred, and shown through a mesh that
// breathes while it flows and is flat and a quarter larger while it is held, mixed toward white and color-graded.
// A new cover comes in over the old one.
//
// Drawn at one pixel a point, at most 30 times a second by a display link that allows 120 Hz UI motion. Only while it
// moves, settles or a new cover comes in, and never in the background or during the player's open/close transition.
// Held, it keeps its last frame and draws nothing. The shaders compile once, off the main thread, from source; until
// they are ready, or if they fail, the layer draws nothing and `drawn` is never called, and SGRFluidLayer keeps its
// Core Animation copies (Light) in its place.
//
// Threading: main thread only.
#import <QuartzCore/QuartzCore.h>

// A Metal device exists (every iPhone the mod runs on; checked so a simulator without one falls back).
BOOL SGRFluidGPUAvailable(void);
// The color table: side^3 RGBA8 texels, red fastest, then green, then blue, each the backdrop's grade of its center
// (SGRFluid.m).
NSData *SGRFluidGradeTable(int side);

@interface SGRFluidGPULayer : CAMetalLayer
// The cover itself, upright, as it is (the shaders treat it). Animated, the new one comes in over the shown one;
// otherwise it replaces it at once. NULL discards the cover and its drawing/analysis demand.
- (void)setCover:(CGImageRef)cover animated:(BOOL)animated;
// The destination itself has been presented, not an older cover or an unfinished crossfade.
@property (nonatomic, readonly) BOOL hasPresentedCover;
// Flowing, or held still where it is. Off to begin with.
@property (nonatomic) BOOL moving;
// Hidden by its owner: nothing is drawn, not even a running transition, until it is NO again.
@property (nonatomic) BOOL held;
// The Speed and Warp settings as factors (1 is standard; Warp 0 leaves a picture turning, nothing flowing).
@property (nonatomic) float rate, warp;
// The Grain setting as a factor: 1 is the standard dither, 0 none, 2 the most.
@property (nonatomic) float grain;
// The Saturation, Brightness and Blur settings as factors of their standards.
@property (nonatomic) float saturation, gain, blur;
// Increase Contrast: the picture's linear luminance is capped low, as SGRFluid.m's Light copies are.
@property (nonatomic) BOOL contrast;
// As SGRFluidLayer's: the part on screen, in this layer's coordinates. The whole layer while empty.
@property (nonatomic) CGRect visibleRect;
// Called in the transaction that presents the destination cover.
@property (nonatomic, copy) void (^drawn)(void);
@end
