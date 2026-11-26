#import <CoreImage/CoreImage.h>
#import "Core/SGCore.h"
#import "SGRFluid.h"
#import "SGRFluidGPU.h"
#import "SGRTokens.h"
#import "SGRBackdropInk.h"

// The copies, laid out as the Music app's player lays its own: the unit is half the visible rect's longer side (its
// height on a phone), measured from its middle with y up. Each copy is a square of the cover `side` units across,
// centered `x`, `y` units from the middle, turning clockwise about its own center once in `turn` seconds; a copy with
// an `orbit` is also carried clockwise about the middle once in that many seconds (the third rides the first's turn).
// Each soft copy is composited over the one before.
static const struct { CGFloat side, x, y; CFTimeInterval turn, orbit; } kCopy[] = {
    {1.4, 0, 0, 120, 0},
    {0.7, -0.25, 0.15, 70, 0},
    {0.7, 0.7, 0.7, 90, 120},
};
enum { kCopies = sizeof(kCopy) / sizeof(kCopy[0]) };
// A new cover crossfades in over this, the Music app's backdrop crossfade (0.8 s, as
// its player shows it). It was the Kit's 0.35, so a dark cover gave way to a light one, and the player's ink with it, in a
// quick jump.
static const CFTimeInterval kBackdropCrossfade = 0.8;
// Held still (paused), the Music app shows its backdrop flat and this much larger, going there and back over kSettle.
static const CGFloat kHeldZoom = 1.25;
static const CGFloat kGPUHeightStepPoints = 256;
static const CFTimeInterval kSettle = 0.8;
// Its blur's standard deviation, in points on screen. Core Image's radius is the standard deviation itself (measured on
// a macOS runner: 1.00 at 4 to 64 px). Fitted to a few screenshots, 1.8 times it looked nearer,
// but against a simulation of the Music app's backdrop as Retrine draws it (the copies, blur and color table) over
// three covers at many moments of the turn, its own 160 pt came nearest, and 1.8 times washed out the red a mostly
// black cover's banner gives the top of the screen.
// Fitted with the rest below (kBackdropTuned): 262 pt.
static const CGFloat kBackdropSigma = 262;
// The blurred cover is small: it is drawn larger than the screen, so detail is lost anyway. The Blur setting scales
// kBackdropSigma (the standard 24 is the Music app's), worked out as a radius on this cover in setArtwork:. Core
// Image works here on encoded values,
// which matched the Music app's look (in linear light even -0.08 turned every channel under about 30% to black, issue #100).
static const CGFloat kBlurSide = 128;
// The shade over the bottom of the visible rect, where the controls are. It was flat and light, because the ceiling
// below kept the whole cover dark (and 0.55 left the lower half of a dark cover black, issue #100). The Music app's
// player instead keeps the cover's own colors and brightness down to the title and the bar and goes dark only toward
// its foot (measured over the Mr. Blue Sky cover: ochre at the title, olive at the controls, near black at the foot),
// so the ceiling is higher and the shade does the darkening: none down to kShadeFrom of the visible rect, then along
// x^kShadeEase (x the way from there to the bottom) to its peak. The peak follows how light the lower part of the
// blurred cover is: kShadeLeast over a dark cover (nothing to hold back), kShadeMost over one at the ceiling, so the
// text's contrast holds whatever the cover (4.5:1 at the title and the times, more below). The peak over a light cover
// was 0.62; beside the Music app over Fuel's orange its foot stood at 45, 27, 17 where 0.62 took Retrine's to 28, 18,
// 16, so it is 0.48 (the player's ink brightens over a light backdrop, SGRBackdropInk.h).
// Fitted (kBackdropTuned): the shade starts near the top and is 0.52 to 0.47 at the foot.
static const CGFloat kShadeFrom = 0.02, kShadeEase = 1.9, kShadeLeast = 0.52, kShadeMost = 0.47;
enum { kShadeSteps = 6 };
// The share of the blurred cover (from its top) that counts as its lower part, for the shade's peak.
static const CGFloat kLowerFrom = 0.5;
// With Increase Contrast each blurred pixel's linear luminance is capped at kCeilingContrast, which keeps the player's
// white text at about 8.8:1 on the brightest. kCeiling is only the scale of the shade's peak (lowerLight): a lower part
// at this linear luminance takes kShadeMost.
static const CGFloat kCeiling = 0.17, kCeilingContrast = 0.04;
// Chosen to match the Music app's player behind a still cover, on encoded sRGB values: the cover is mixed toward black
// by kBackdropBlack, its saturation is scaled by kBackdropSaturation about its Rec. 709 luma, the result is
// blurred, mixed toward white by kBackdropWhite and passed through a color grade (backdropGrade),
// which leaves grays nearly as they are and pulls strong reds and blues in. The Saturation slider scales kBackdropSaturation against
// its standard; the Brightness slider scales the result's linear light.
// kBackdropTuned: these, the blur (kBackdropSigma), the shade (kShade*), kBackdropDepth and kBackdropLoudness were
// fitted together to the Music app's player: Retrine's Light backdrop simulated over four covers (a mostly black, an
// orange, a teal and a red and yellow one) at the moments of its turn that matched each best, by a downhill search
// over all ten at once. 6.1 of 255 off on average before, 5.1 after, checked on moments the fit had not seen; the
// simulation matches Retrine's own screenshots to 2 to 4, so closer than that cannot be told apart.
static const CGFloat kBackdropBlack = 0.526, kBackdropSaturation = 2.52, kBackdropWhite = 0.112;
// The Music app also raises the contrast about middle gray (1 + 0.076 a) and the saturation (+ 0.166 a) by how loud the
// music is (a, 0 to 1). Retrine does not listen to it here and takes this steady level for music playing: measured
// against its player over three covers, Retrine's darkest channel stood 8 to 10 of 255 higher without it.
// Beside the Music app's player, at the moments of the turn that matched it best over four covers, the brightest
// channel stood where its does and the lowest higher: an orange's blue 5 to 17 of 255 over (Fuel, November Rain), a
// teal's red 7 over. Taking the lowest down by this share of the spread brought the four from 6.4 of 255 off on
// average to 5.3 (simulated), matching its look rather than any stage of it.
static const CGFloat kBackdropDepth = 0.20;
static const CGFloat kBackdropLoudness = 0.06, kBackdropContrastPerLoudness = 0.076, kBackdropSaturationPerLoudness = 0.166;

// Retrine's grade for the backdrop, on an encoded color `e` (0 to 1), made to look like the Music app's. What its color
// table does, read off its output: greens, yellows, cyans and magentas pass nearly untouched, while a color whose red
// (or blue) stands out above both other channels is pulled toward a neutral point, by up to 36% (33% for blue) as that
// channel stands further out; the other channels rise a little, and a slight contrast curve runs over everything (16
// of 255 goes to 12, 239 to 243). Here that is a dozen numbers: the pull per standing-out channel (kGradeRed,
// kGradeBlue: strength, then where the ease starts and ends, as the share of the channel above the next highest), the
// neutral point (a mix of luma, the lowest channel and the mean, raised with the pull), and the curve (gain, offset).
// Fitted to the look by least squares; it lands within 0.8 of 255 on average and 6.6 at worst (a pure red).
static const CGFloat kGradeRed[3] = {0.3633, 0.1641, 0.8199}, kGradeBlue[3] = {0.3336, 0.1497, 0.8128};
static const CGFloat kGradeLuma = 0.0821, kGradeFloor = 0.5891, kGradeRaise = 0.1736, kGradeLift = -0.0603;
static const CGFloat kGradeGain = 1.0292, kGradeOffset = -0.0152;

static CGFloat gradeEase(CGFloat from, CGFloat to, CGFloat v) {
    CGFloat t = MIN(1, MAX(0, (v - from) / (to - from)));
    return t * t * (3 - 2 * t);
}

static void backdropGrade(CGFloat e[3]) {
    CGFloat lo = MIN(e[0], MIN(e[1], e[2])), hi = MAX(e[0], MAX(e[1], e[2]));
    CGFloat c[3] = {e[0] - lo, e[1] - lo, e[2] - lo};
    CGFloat pull = 0;
    const CGFloat *curve[2] = {kGradeRed, kGradeBlue};
    const int channel[2] = {0, 2};
    for (int i = 0; i < 2; i++) {
        int ch = channel[i];
        CGFloat own = c[ch], other = MAX(c[(ch + 1) % 3], c[(ch + 2) % 3]);
        if (own > 1e-9) pull += curve[i][0] * gradeEase(curve[i][1], curve[i][2], (own - other) / own);
    }
    CGFloat luma = 0.2126 * e[0] + 0.7152 * e[1] + 0.0722 * e[2], mean = (e[0] + e[1] + e[2]) / 3;
    CGFloat neutral = kGradeLuma * luma + kGradeFloor * lo + (1 - kGradeLuma - kGradeFloor) * mean + kGradeRaise * pull * hi;
    for (int k = 0; k < 3; k++) {
        CGFloat y = neutral + (1 - pull) * (e[k] - neutral) + kGradeLift * pull * hi;
        e[k] = MIN(1, MAX(0, kGradeGain * y + kGradeOffset));
    }
}

NSNotificationName const SGRFluidSettingsDidChangeNotification = @"spotifyglass.redesign.fluidSettingsDidChange";

// In SGRFluidSetting's order.
static const struct { __unsafe_unretained NSString *key; SGRFluidLimits limits; } kSetting[] = {
    {@"spotifyglass.redesign.fluid.speed", {25, 300, 25, 100}},
    {@"spotifyglass.redesign.fluid.warp", {0, 100, 5, 100}},
    {@"spotifyglass.redesign.fluid.blur", {2, 32, 1, 24}},
    {@"spotifyglass.redesign.fluid.saturation", {0, 250, 10, 110}},
    {@"spotifyglass.redesign.fluid.brightness", {40, 150, 5, 100}},
    {@"spotifyglass.redesign.fluid.grain", {0, 200, 10, 100}},
};

SGRFluidLimits SGRFluidLimitsOf(SGRFluidSetting setting) {
    return kSetting[setting].limits;
}

NSInteger SGRFluidValue(SGRFluidSetting setting) {
    SGRFluidLimits l = kSetting[setting].limits;
    return MIN(l.most, MAX(l.least, SGInt(kSetting[setting].key, l.standard)));
}

void SGRSetFluidValue(SGRFluidSetting setting, NSInteger value) {
    SGSetInt(kSetting[setting].key, value);
    [NSNotificationCenter.defaultCenter postNotificationName:SGRFluidSettingsDidChangeNotification object:nil];
}

void SGRResetFluidSettings(void) {
    for (NSInteger i = 0; i < SGRFluidSettingCount; i++) [NSUserDefaults.standardUserDefaults removeObjectForKey:kSetting[i].key];
    [NSNotificationCenter.defaultCenter postNotificationName:SGRFluidSettingsDidChangeNotification object:nil];
}

static NSString *const kRendererKey = @"spotifyglass.redesign.fluid.renderer";

SGRFluidRenderer SGRFluidRendererChosen(void) {
    return SGInt(kRendererKey, SGRFluidRendererLight) == SGRFluidRendererSmooth ? SGRFluidRendererSmooth : SGRFluidRendererLight;
}

void SGRSetFluidRenderer(SGRFluidRenderer renderer) {
    SGSetInt(kRendererKey, renderer);
    [NSNotificationCenter.defaultCenter postNotificationName:SGRFluidSettingsDidChangeNotification object:nil];
}

NSArray<NSString *> *SGRFluidRendererNames(void) {
    return @[SGL(@"settings.player.fluid.renderer.light", @"Light"), SGL(@"settings.player.fluid.renderer.smooth", @"Smooth")];
}

// `saturation` is the Saturation setting as a factor (1.1 its standard), `gain` the Brightness setting's on linear light.
static UIImage *blurred(UIImage *image, BOOL contrast, CGFloat relativeSigma, CGFloat saturation, CGFloat gain,
                        CGFloat *lowerLight, CGFloat *expansion) {
    CGImageRef source = image.CGImage;
    if (!source) return nil;
    CIImage *input = [CIImage imageWithCGImage:source];
    // Leave three standard deviations of transparent halo on each side. Reduce the
    // cover resolution rather than clipping the halo for a small copy or a strong blur.
    CGFloat side = MAX(1, MIN(kBlurSide, floor(510 / (1 + 6 * relativeSigma))));
    CGFloat radius = side * relativeSigma, pad = ceil(3 * radius);
    CGFloat scale = side / MIN(input.extent.size.width, input.extent.size.height);
    input = [input imageByApplyingTransform:CGAffineTransformMakeScale(scale, scale)];
    input = [input imageByApplyingTransform:CGAffineTransformMakeTranslation(side/2 - CGRectGetMidX(input.extent),
                                                                             side/2 - CGRectGetMidY(input.extent))];
    CGRect coverRect = CGRectMake(0, 0, side, side);
    CGRect extent = CGRectInset(coverRect, -pad, -pad);
    *expansion = extent.size.width / side;
    // The Music app's copy treatment before its blur: toward black, contrast about middle gray, then saturation about
    // the luma, clamped as its 8-bit texture holds it. One matrix and a bias: each output channel is
    // spread * keep * (s * own + (1 - s) * luma) + (1 - spread) / 2, spread the contrast (the saturation leaves a gray
    // as it is).
    CGFloat s = (kBackdropSaturation + kBackdropSaturationPerLoudness * kBackdropLoudness) * saturation
              / (SGRFluidLimitsOf(SGRFluidSaturation).standard / 100.0);
    CGFloat spread = 1 + kBackdropContrastPerLoudness * kBackdropLoudness;
    CGFloat keep = 1 - kBackdropBlack, luma[3] = {0.2126, 0.7152, 0.0722}, bias = (1 - spread) / 2;
    CIVector *rows[3];
    for (int c = 0; c < 3; c++) {
        CGFloat m[3];
        for (int k = 0; k < 3; k++) m[k] = spread * keep * ((1 - s) * luma[k] + (c == k ? s : 0));
        rows[c] = [CIVector vectorWithX:m[0] Y:m[1] Z:m[2] W:0];
    }
    CIImage *output = [[[[input imageByApplyingFilter:@"CIColorMatrix" withInputParameters:@{
            @"inputRVector": rows[0], @"inputGVector": rows[1], @"inputBVector": rows[2],
            @"inputBiasVector": [CIVector vectorWithX:bias Y:bias Z:bias W:0]}]
        imageByApplyingFilter:@"CIColorClamp" withInputParameters:@{}] imageByCroppingToRect:coverRect]
        imageByApplyingFilter:@"CIGaussianBlur" withInputParameters:@{kCIInputRadiusKey: @(radius)}];
    static CIContext *context;
    static dispatch_once_t once;
    // Covers are prepared even offscreen; leave GPU submission to the visible renderer.
    dispatch_once(&once, ^{
        CGColorSpaceRef encoded = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
        context = [CIContext contextWithOptions:@{kCIContextWorkingColorSpace: (__bridge id)encoded,
                                                  kCIContextUseSoftwareRenderer: @YES}];
        CGColorSpaceRelease(encoded);
    });
    CGImageRef cg = [context createCGImage:[output imageByCroppingToRect:extent] fromRect:extent];
    if (!cg) return nil;
    size_t width = CGImageGetWidth(cg), height = CGImageGetHeight(cg);
    CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGContextRef bitmap = CGBitmapContextCreate(NULL, width, height, 8, width * 4, space,
                                                kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(space);
    if (!bitmap) { CGImageRelease(cg); return nil; }
    CGContextDrawImage(bitmap, CGRectMake(0, 0, width, height), cg);
    CGImageRelease(cg);
    unsigned char *pixels = CGBitmapContextGetData(bitmap);
    CGFloat lowerSum = 0;
    size_t lowerCount = 0, lowerRow = pad + floor(side * kLowerFrom);
    for (size_t i = 0; i < width * height; i++) {
        unsigned char *p = pixels + i * 4;
        if (!p[3]) continue;
        // After the blur: toward white, then the grade.
        CGFloat e[3];
        for (int c = 0; c < 3; c++) e[c] = (CGFloat)p[c] / p[3] * (1 - kBackdropWhite) + kBackdropWhite;
        backdropGrade(e);
        // The lowest channel taken further down by kBackdropDepth of the spread (an orange's blue, a teal's red).
        CGFloat lo = MIN(e[0], MIN(e[1], e[2])), hi = MAX(e[0], MAX(e[1], e[2]));
        for (int c = 0; c < 3; c++) if (e[c] == lo) e[c] = MAX(0, lo - kBackdropDepth * (hi - lo));
        // The Brightness setting on linear light, and with Increase Contrast the cap.
        CGFloat rgb[3];
        for (int c = 0; c < 3; c++) {
            CGFloat v = e[c];
            rgb[c] = (v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)) * gain;
        }
        CGFloat light = 0.2126 * rgb[0] + 0.7152 * rgb[1] + 0.0722 * rgb[2];
        CGFloat cap = contrast && light > kCeilingContrast ? kCeilingContrast / light : 1;
        if (lowerLight && i / width >= lowerRow && i / width < pad + side &&
            i % width >= pad && i % width < pad + side) { lowerSum += light * cap; lowerCount++; }
        for (int c = 0; c < 3; c++) {
            CGFloat v = MIN(1, rgb[c] * cap);
            p[c] = lround(p[3] * (v <= 0.0031308 ? v * 12.92 : 1.055 * pow(v, 1 / 2.4) - 0.055));
        }
    }
    // 0 for a black lower part, 1 for one at kCeiling or lighter.
    if (lowerLight) *lowerLight = lowerCount ? MIN(1, lowerSum / lowerCount / kCeiling) : 0;
    cg = CGBitmapContextCreateImage(bitmap);
    UIImage *result = cg ? [UIImage imageWithCGImage:cg] : nil;
    if (cg) CGImageRelease(cg);
    CGContextRelease(bitmap);
    return result;
}

// The cover upright at 256 px a side, its colors as they are: what the GPU renderer's copies are drawn from.
static UIImage *upright(UIImage *image) {
    if (!image) return nil;
#ifdef SGR_FLUID_FRAME_PROBE
    extern BOOL SGRProbeFailUprightCover(UIImage *);
    if (SGRProbeFailUprightCover(image)) return nil;
#endif
    enum { kSide = 256 };
    CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGContextRef bitmap = CGBitmapContextCreate(NULL, kSide, kSide, 8, kSide * 4, space,
                                                kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(space);
    if (!bitmap) return nil;
    UIGraphicsPushContext(bitmap);
    CGContextTranslateCTM(bitmap, 0, kSide);
    CGContextScaleCTM(bitmap, 1, -1);
    [image drawInRect:CGRectMake(0, 0, kSide, kSide)];
    UIGraphicsPopContext();
    CGImageRef cg = CGBitmapContextCreateImage(bitmap);
    CGContextRelease(bitmap);
    UIImage *result = cg ? [UIImage imageWithCGImage:cg] : nil;
    if (cg) CGImageRelease(cg);
    return result;
}

NSData *SGRFluidGradeTable(int side) {
    if (side < 2) return nil;
    NSMutableData *data = [NSMutableData dataWithLength:(NSUInteger)side * side * side * 4];
    unsigned char *p = data.mutableBytes;
    for (int b = 0; b < side; b++) {
        for (int g = 0; g < side; g++) {
            for (int r = 0; r < side; r++) {
                CGFloat e[3] = {(r + 0.5) / side, (g + 0.5) / side, (b + 0.5) / side};
                backdropGrade(e);
                for (int c = 0; c < 3; c++) *p++ = (unsigned char)lround(255 * e[c]);
                *p++ = 255;
            }
        }
    }
    return data;
}

@implementation SGRFluidLayer {
    CALayer *_canvas;   // the copies, shown a quarter larger while held still (kHeldZoom)
    CALayer *_orbits[kCopies];   // each copy's journey about the middle, for those with an orbit
    CALayer *_copies[kCopies];
    CGFloat _expansion[2];   // padded bitmap / original square, large and small
    CAGradientLayer *_shade;
    CGFloat _lowerLight;   // how light the shown cover's lower part is, 0 to 1 (blurred())
    UIImage *_source;
    UIImage *_cover;       // the cover as the GPU renderer takes it (upright, 256 px)
    NSUInteger _generation;
    BOOL _moving;
    BOOL _turning;   // the copies' turns are running (moving, and Smooth is not showing)
    CFTimeInterval _since, _elapsed;   // _elapsed in turns at the standard speed
    CGFloat _rate, _warp;              // Speed and Warp as factors, read when the copies are laid out or started
    CGRect _laidOutFor;
    SGRFluidGPULayer *_gpu;   // Smooth, under the copies; nil while Light is chosen
    BOOL _gpuShown;           // its first frame is on screen and the copies are hidden
    BOOL _requestedHidden, _preparing, _awaitingCoveredBlur;
}

- (instancetype)init {
    if (!(self = [super init])) return nil;
    self.masksToBounds = YES;
    self.backgroundColor = UIColor.blackColor.CGColor;
    _canvas = [CALayer layer];
    _canvas.transform = CATransform3DMakeScale(kHeldZoom, kHeldZoom, 1);
    _canvas.backgroundColor = UIColor.blackColor.CGColor;
    [self addSublayer:_canvas];
    for (int i = 0; i < kCopies; i++) {
        _orbits[i] = [CALayer layer];
        _copies[i] = [CALayer layer];
        _copies[i].contentsGravity = kCAGravityResizeAspectFill;
        [_orbits[i] addSublayer:_copies[i]];
        [_canvas addSublayer:_orbits[i]];
    }
    [self applyWarp];
    _shade = [CAGradientLayer layer];
    [self updateShadeColors];
    [self addSublayer:_shade];
    [self applyRenderer];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(contrastChanged)
        name:UIAccessibilityDarkerSystemColorsStatusDidChangeNotification object:nil];
    // Posted on the main thread by the Player page's sliders, so the change applies at once.
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(settingsChanged)
        name:SGRFluidSettingsDidChangeNotification object:nil];
    return self;
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)contrastChanged {
    dispatch_async(dispatch_get_main_queue(), ^{
        self->_gpu.contrast = SGRIncreaseContrast();
        [self reblur];
    });
}

// The same cover blurred again, for a new Blur, Saturation, Brightness or contrast.
- (void)reblur {
    UIImage *source = _source;
    _source = nil;
    [self setArtwork:source animated:NO];
}

// Warp is how far from the middle the smaller copies sit, and how much they show (opaque at the standard 100 %): at
// none, the large copy turns alone, a still picture turning, with nothing to flow through it.
- (void)applyWarp {
    _warp = SGRFluidValue(SGRFluidWarp) / 100.0;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    for (int i = 1; i < kCopies; i++) _copies[i].opacity = (float)_warp;
    [CATransaction commit];
}

- (void)settingsChanged {
    // Restarted at the new speed from the angle each copy is at, and laid out again for the new warp.
    if (_turning) [self stop];
    [self applyWarp];
    _laidOutFor = CGRectNull;
    [self setNeedsLayout];
    [self applyRenderer];
    [self updateCopies];
    [self reblur];
}

#pragma mark - the renderer

// Smooth stays beneath the prepared Light copies until its current cover is presented.
- (void)applyRenderer {
    BOOL smooth = SGRFluidRendererChosen() == SGRFluidRendererSmooth && SGRFluidGPUAvailable();
    if (smooth && !_gpu) {
        _gpu = [SGRFluidGPULayer layer];
        [self insertSublayer:_gpu atIndex:0];
        __weak SGRFluidLayer *weakSelf = self;
        __weak SGRFluidGPULayer *weakGPU = _gpu;
        _gpu.drawn = ^{ [weakSelf gpuDrew:weakGPU]; };
        _gpu.held = self.hidden;
        _gpu.moving = _moving;
        [self setNeedsLayout];
        if (_cover) [_gpu setCover:_cover.CGImage animated:NO];
    } else if (!smooth && _gpu) {
        _gpu.held = YES;
        [_gpu removeFromSuperlayer];
        _gpu = nil;
        _gpuShown = NO;
        [self showCopies];
    }
    _gpu.rate = (float)(SGRFluidValue(SGRFluidSpeed) / 100.0);
    _gpu.warp = (float)_warp;
    _gpu.grain = (float)(SGRFluidValue(SGRFluidGrain) / 100.0);
    _gpu.saturation = (float)(SGRFluidValue(SGRFluidSaturation) / (CGFloat)SGRFluidLimitsOf(SGRFluidSaturation).standard);
    _gpu.gain = (float)(SGRFluidValue(SGRFluidBrightness) / 100.0);
    _gpu.blur = (float)(SGRFluidValue(SGRFluidBlur) / (CGFloat)SGRFluidLimitsOf(SGRFluidBlur).standard);
    _gpu.contrast = SGRIncreaseContrast();
}

- (void)gpuDrew:(SGRFluidGPULayer *)gpu {
    if (!gpu || gpu != _gpu || _gpuShown) return;
    _gpuShown = YES;
    [self showCopies];
}

// The copies shown and turning while Smooth is not on screen, hidden and still while it is.
- (void)showCopies {
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _canvas.hidden = _gpuShown;
    // The Music app has no shade over its backdrop; the GPU renderer is drawn as its is.
    _shade.hidden = _gpuShown;
    [CATransaction commit];
    [self updateCopies];
}

- (void)updateCopies {
    BOOL turn = _moving && !_gpuShown;
    if (turn && !_turning) [self start];
    else if (!turn && _turning) [self stop];
}

- (void)setHidden:(BOOL)hidden {
    _requestedHidden = hidden;
    if (hidden && _preparing) _awaitingCoveredBlur = YES;
    if (hidden && _gpu && !_gpu.hasPresentedCover) {
        // Preparation may already have finished while the old drawable is still showing.
        // On uncover show the prepared destination, not a fading copy or an old surface.
        for (int i = 0; i < kCopies; i++) [_copies[i] removeAnimationForKey:@"contents"];
        if (_gpuShown) {
            _gpuShown = NO;
            [self showCopies];
        }
    }
    [super setHidden:hidden || _awaitingCoveredBlur];
    _gpu.held = self.hidden;
}

- (BOOL)moving {
    return _moving;
}

- (void)setVisibleRect:(CGRect)rect {
    if (CGRectEqualToRect(rect, _visibleRect)) return;
    _visibleRect = rect;
    [self setNeedsLayout];
}

// The shade's stops: nothing at the top, then x^kShadeEase of the peak down to the bottom, the peak following how light
// the cover's lower part is.
- (void)updateShadeColors {
    CGFloat peak = kShadeLeast + (kShadeMost - kShadeLeast) * MAX(0, MIN(1, _lowerLight));
    NSMutableArray *colors = [NSMutableArray arrayWithCapacity:kShadeSteps + 1];
    for (int i = 0; i <= kShadeSteps; i++) {
        [colors addObject:(__bridge id)[UIColor colorWithWhite:0 alpha:peak * pow((CGFloat)i / kShadeSteps, kShadeEase)].CGColor];
    }
    _shade.colors = colors;
}

- (void)layoutSublayers {
    [super layoutSublayers];
    CGRect bounds = self.bounds;
    CGRect visible = CGRectIsEmpty(_visibleRect) ? bounds : _visibleRect;
    CGFloat total = MAX(1, bounds.size.height);
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _shade.frame = bounds;
    CGFloat shadeTop = MIN(1, (CGRectGetMinY(visible) + visible.size.height * kShadeFrom) / total), shadeBottom = MIN(1, CGRectGetMaxY(visible) / total);
    NSMutableArray *at = [NSMutableArray arrayWithCapacity:kShadeSteps + 1];
    for (int i = 0; i <= kShadeSteps; i++) [at addObject:@(shadeTop + (shadeBottom - shadeTop) * i / kShadeSteps)];
    _shade.locations = at;
    _gpu.frame = CGRectMake(bounds.origin.x, bounds.origin.y, bounds.size.width,
                            ceil(bounds.size.height / kGPUHeightStepPoints) * kGPUHeightStepPoints);
    if (_gpu) _gpu.visibleRect = [self convertRect:visible toLayer:_gpu];
    // Grown about the visible rect's middle.
    if (bounds.size.width >= 1 && bounds.size.height >= 1) {
        _canvas.bounds = bounds;
        _canvas.anchorPoint = CGPointMake((CGRectGetMidX(visible) - bounds.origin.x) / bounds.size.width,
                                          (CGRectGetMidY(visible) - bounds.origin.y) / bounds.size.height);
        _canvas.position = CGPointMake(CGRectGetMidX(visible), CGRectGetMidY(visible));
    }
    if (!CGRectEqualToRect(visible, _laidOutFor) && visible.size.width >= 1) {
        _laidOutFor = visible;
        if (_turning) [self stop];
        CGFloat half = MAX(visible.size.width, visible.size.height) / 2;
        for (int i = 0; i < kCopies; i++) {
            _orbits[i].bounds = CGRectMake(0, 0, 2 * half, 2 * half);
            _orbits[i].position = CGPointMake(CGRectGetMidX(visible), CGRectGetMidY(visible));
            _copies[i].position = CGPointMake(half * (1 + kCopy[i].x * _warp), half * (1 - kCopy[i].y * _warp));
        }
        [self updateCopies];
    }
    [self sizeCopies];
    [CATransaction commit];
}

- (void)sizeCopies {
    CGFloat longer = MAX(_laidOutFor.size.width, _laidOutFor.size.height);
    for (int i = 0; i < kCopies; i++) {
        CGFloat side = round(longer * kCopy[i].side) * _expansion[i != 0];
        _copies[i].bounds = CGRectMake(0, 0, side, side);
    }
}

- (void)setArtwork:(UIImage *)image animated:(BOOL)animated {
    if (!image || image == _source) return;
    _source = image;
    _preparing = YES;
    if (self.hidden) _awaitingCoveredBlur = YES;
    BOOL needsCover = _gpu != nil;
    NSUInteger generation = ++_generation;
    BOOL contrast = SGRIncreaseContrast();
    // The blur in points on screen, as the Music app's (kBackdropSigma at the standard Blur), as a radius on the large
    // copy's cover: it is kCopy[0].side units across, a unit half the visible rect's longer side.
    CGRect visible = CGRectIsEmpty(_visibleRect) ? self.bounds : _visibleRect;
    CGFloat longer = MAX(visible.size.width, visible.size.height);
    if (longer < 1) longer = MAX(UIScreen.mainScreen.bounds.size.width, UIScreen.mainScreen.bounds.size.height);
    CGFloat points = kBackdropSigma * SGRFluidValue(SGRFluidBlur) / SGRFluidLimitsOf(SGRFluidBlur).standard;
    CGFloat saturation = SGRFluidValue(SGRFluidSaturation) / 100.0;
    CGFloat gain = SGRFluidValue(SGRFluidBrightness) / 100.0;
    __weak SGRFluidLayer *weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        CGFloat lowerLight = 0, largeScale = 0, smallScale = 0;
        UIImage *blur = blurred(image, contrast, points / (kCopy[0].side * longer), saturation, gain, &lowerLight, &largeScale);
        // The smaller copies are half the large one's size, so their cover is blurred twice as far for the same blur
        // on screen, as the Music app blurs the whole square at once.
        UIImage *small = blurred(image, contrast, points / (kCopy[1].side * longer), saturation, gain, NULL, &smallScale);
        UIImage *cover = needsCover ? upright(image) : nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            SGRFluidLayer *layer = weakSelf;
            if (!layer || generation != layer->_generation) return;
            layer->_preparing = NO;
            BOOL fade = animated && !layer->_awaitingCoveredBlur && !layer->_gpu.held;
            if (layer->_awaitingCoveredBlur || !cover) {
                layer->_gpuShown = NO;
                [layer showCopies];
            }
            layer->_cover = cover;
            [layer->_gpu setCover:cover.CGImage animated:fade];
            // A picture the blur cannot read (no CGImage) keeps the copies showing the last cover, not black.
            if (blur) {
                layer->_expansion[0] = largeScale;
                layer->_expansion[1] = small ? smallScale : largeScale;
                [layer show:blur small:small ?: blur lowerLight:lowerLight animated:fade];
            }
            layer->_awaitingCoveredBlur = NO;
            [layer setHidden:layer->_requestedHidden];
        });
    });
}

- (void)show:(UIImage *)blur small:(UIImage *)small lowerLight:(CGFloat)lowerLight animated:(BOOL)animated {
    _lowerLight = lowerLight;
    // The player's ink follows the backdrop through the change: the crossfade, or Smooth's longer run-in while playing
    // (SGRFluidGPU.m's 1.4 s).
    if (animated) SGRBackdropInkFollow(_gpu ? 1.4 : kBackdropCrossfade);
    // The shade's peak follows the new cover's lower part, crossfading with the cover.
    [CATransaction begin];
    [CATransaction setDisableActions:!animated];
    [CATransaction setAnimationDuration:kBackdropCrossfade];
    [self updateShadeColors];
    [CATransaction commit];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    [self sizeCopies];
    for (int i = 0; i < kCopies; i++) {
        if (animated) {
            CATransition *fade = [CATransition animation];
            fade.type = kCATransitionFade;
            fade.duration = kBackdropCrossfade;
            [_copies[i] addAnimation:fade forKey:@"contents"];
        }
        else [_copies[i] removeAnimationForKey:@"contents"];
        _copies[i].contents = (__bridge id)(i ? small : blur).CGImage;
    }
    [CATransaction commit];
}

#pragma mark - moving

- (void)setMoving:(BOOL)moving {
    if (moving == _moving) return;
    _moving = moving;
    _gpu.moving = moving;
    [self updateCopies];
    // Flowing at its own size, held a quarter larger, eased over kSettle as the Music app's backdrop goes.
    CGFloat zoom = moving ? 1 : kHeldZoom;
    [CATransaction begin];
    [CATransaction setAnimationDuration:kSettle];
    [CATransaction setAnimationTimingFunction:[CAMediaTimingFunction functionWithControlPoints:0.42 :0 :0.58 :1]];
    _canvas.transform = CATransform3DMakeScale(zoom, zoom, 1);
    [CATransaction commit];
}

- (void)start {
    if (self.bounds.size.width < 1) return;
    _turning = YES;
    _since = CACurrentMediaTime();
    _rate = SGRFluidValue(SGRFluidSpeed) / 100.0;
    CAFrameRateRange rate = CAFrameRateRangeMake(15, 60, 30);
    for (int i = 0; i < kCopies; i++) {
        CALayer *layers[2] = {_copies[i], _orbits[i]};
        CFTimeInterval lengths[2] = {kCopy[i].turn, kCopy[i].orbit};
        for (int k = 0; k < 2; k++) {
            if (lengths[k] <= 0) continue;
            // The turn's offset carries the angle it stopped at, so the resting angle goes back to none.
            [CATransaction begin];
            [CATransaction setDisableActions:YES];
            layers[k].transform = CATransform3DIdentity;
            [CATransaction commit];
            // Clockwise on screen, where y runs down.
            CABasicAnimation *turn = [CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];
            turn.byValue = @(2 * M_PI);
            turn.duration = lengths[k] / _rate;
            turn.repeatCount = HUGE_VALF;
            turn.additive = YES;
            turn.timeOffset = fmod(_elapsed, lengths[k]) / _rate;
            turn.preferredFrameRateRange = rate;
            [layers[k] addAnimation:turn forKey:@"turn"];
        }
    }
}

// Every copy held at the angle it is drawn at now.
- (void)stop {
    if (!_turning) return;
    _turning = NO;
    if (_since > 0) _elapsed += (CACurrentMediaTime() - _since) * _rate;
    _since = 0;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    for (int i = 0; i < kCopies; i++) {
        CALayer *layers[2] = {_copies[i], _orbits[i]};
        CFTimeInterval lengths[2] = {kCopy[i].turn, kCopy[i].orbit};
        for (int k = 0; k < 2; k++) {
            if (lengths[k] <= 0) continue;
            CGFloat angle = 2 * M_PI * fmod(_elapsed, lengths[k]) / lengths[k];
            [layers[k] removeAnimationForKey:@"turn"];
            layers[k].transform = CATransform3DMakeRotation(angle, 0, 0, 1);
        }
    }
    [CATransaction commit];
}

@end
