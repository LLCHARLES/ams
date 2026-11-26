// Fluid artwork: the cover itself, blurred and slowly turning behind the player, drawn as the Music app draws its
// backdrop: on the GPU (SGRFluidGPU.h), three turning copies of the cover in a quarter-size picture, mixed toward
// black and saturated, blurred, and shown through a breathing mesh, mixed toward white and color-graded. Where Metal
// cannot draw (or until its first frame) Core Animation copies stand in (Light), with a shade over the bottom.
//
// The Player page tunes it with six sliders (Redesigned/Player/PlayerSettings.m), stored as whole numbers under
// spotifyglass.redesign.fluid.<speed|warp|blur|saturation|brightness|grain>. Every layer follows a change at once.
// spotifyglass.redesign.fluid.renderer chooses the Smooth GPU pipeline (default) or preblurred Light copies.
//
// Threading: main thread only; the cover's preparation runs off it.
#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, SGRFluidSetting) {
    SGRFluidSpeed,        // percent of the turns' speed
    SGRFluidWarp,         // percent of how far apart the copies turn and how much the upper three show
    SGRFluidBlur,         // the on-screen Gaussian radius, relative to the standard setting
    SGRFluidSaturation,   // percent
    SGRFluidBrightness,   // percent, on linear light
    SGRFluidGrain,        // percent of the Smooth renderer's grain (SGRFluidGPU.h); 100 is its standard dither
    SGRFluidSettingCount,
};
typedef struct { NSInteger least, most, step, standard; } SGRFluidLimits;
SGRFluidLimits SGRFluidLimitsOf(SGRFluidSetting setting);
NSInteger SGRFluidValue(SGRFluidSetting setting);   // held to its limits
// Stores the value and posts SGRFluidSettingsDidChangeNotification on the main thread.
void SGRSetFluidValue(SGRFluidSetting setting, NSInteger value);
void SGRResetFluidSettings(void);   // all six back to their standard values, one notification
extern NSNotificationName const SGRFluidSettingsDidChangeNotification;

typedef NS_ENUM(NSInteger, SGRFluidRenderer) {
    SGRFluidRendererLight,    // Core Animation's turning copies, a little less battery; shown wherever Metal is missing
    SGRFluidRendererSmooth,   // the GPU's flow (SGRFluidGPU.h): the standard
};
SGRFluidRenderer SGRFluidRendererChosen(void);
// Stores the choice and posts SGRFluidSettingsDidChangeNotification on the main thread. Reset leaves it.
void SGRSetFluidRenderer(SGRFluidRenderer renderer);
NSArray<NSString *> *SGRFluidRendererNames(void);   // in SGRFluidRenderer's order

@interface SGRFluidLayer : CALayer
// The cover, blurred off the main thread and crossfaded in. The same image again is a no-op.
- (void)setArtwork:(UIImage *)image animated:(BOOL)animated;
// Turning, or held still where it is. Off to begin with.
@property (nonatomic) BOOL moving;
// The part of the layer on screen, in its own coordinates: the copies turn about points in it and the
// shade darkens its bottom, whatever the layer bleeds past it. The whole layer while empty.
@property (nonatomic) CGRect visibleRect;
@end
