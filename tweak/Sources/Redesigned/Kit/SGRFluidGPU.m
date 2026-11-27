#import <Metal/Metal.h>
#import <UIKit/UIKit.h>
#import <simd/simd.h>
#import "Core/SGCore.h"
#import "SGRFluid.h"
#import "SGRFluidGPU.h"
#import "SGRTokens.h"
#import "SGRBridges.h"
#import "Shared/Player/SGMusicSpectrum.h"

// Retrine's backdrop, made to look like the Music app's player behind a cover, in stages:
//   1. Three copies of the cover, drawn opaque one over the other into a picture a quarter of the drawable's size. Each
//      is mixed toward black (0.5, and 0.0075 more per copy), its contrast and saturation raised about middle gray and
//      Rec. 709 luma by the music (kContrastPerBass, kCopySaturation), on the cover's encoded values. The unit is half the visible
//      rect's longer side (its aspect matrix scales x by height / width on a phone); the copies are 1.4, 0.7 and 0.7
//      units across, at (0, 0), (-0.25, 0.15) and (0.7, 0.7) (y up), each turning clockwise about its own center once
//      in 120, 70 and 90 s, the third also carried about the middle by the first's turn, which turns it as well.
//   2. That picture blurred, a Gaussian of kBlurPoints standard deviation on screen.
//   3. Shown through a mesh: held still, flat and a quarter larger; flowing, bent by one of two 6 x 6 grids and
//      breathing from the one to the other once in 2 pi * 3.5 s of its clock; going from held to flowing eased in and
//      out (kSettleClock).
//      Each pixel is mixed toward white by 0.1 and passed through a 32 x 32 x 32 color table (Retrine's own grade, SGRFluidGradeTable).
// The grids are Retrine's own, made at random per layer, 6 x 6 points: the inner points well off the even grid,
// the edge points sliding along their side, the corners in place, and the second grid the first with two to eight
// inner points moved, so the breathing stirs a few places only. They never fold (makeMesh).
static const float kCopyScrim = 0.5f, kCopyScrimStep = 0.0075f, kWhite = 0.1f;
static const float kCopySaturation = 2.4f;
static const float kBlurPoints = 160;
// The music, heard as the Music app's backdrop seems to (SGMusicSpectrum.h): the bands' levels, averaged over the last four
// readings by these weights (oldest first), held at their peak and let down by these shares of themselves each of its
// frames, followed half way each frame, and eased (smootherstep). Bass raises the copies' contrast about middle gray,
// treble their saturation, and a mix of bass and middle grows the whole picture about the middle by 0.33 m^2.
static const float kHistoryWeight[4] = {0.1f, 0.2f, 0.3f, 0.4f};
static const float kPeakFall[3] = {1.0f / 50, 1.0f / 100, 1.0f / 1000};
static const float kContrastPerBass = 0.076f, kSaturationPerTreble = 0.166f, kGrowth = 0.33f, kGrowthMiddle = 0.1f;
static const double kSettleClock = 0.8;
static const float kHeldZoom = 1.25f;
static const double kBreathPeriod = 3.5;
static const CFTimeInterval kRunIn = 1.4;
// Held still, a new cover crossfades in over the Music app's backdrop crossfade (0.8 s).
static const CFTimeInterval kBackdropCrossfade = 0.8;
static const double kDrawFramesPerSecond = 30;
// The blur works on a picture small enough that its Gaussian spans about this many texels: the Music app blurs 160 pt,
// which leaves nothing finer than tens of points, so a picture of 16 pt texels holds all of it. Drawn a quarter of the
// drawable as before, a 160 pt blur took 241 taps a texel each way, every frame; here it takes about 51.
static const float kBlurTexels = 10;
static const NSUInteger kLeastDivisor = 4, kMostDivisor = 16;
enum { kLUTSide = 32, kMeshCells = 24 };
static const struct { float side, x, y, turn, orbit; } kCopy[3] = {
    {1.4f, 0, 0, 120, 0},
    {0.7f, -0.25f, 0.15f, 70, 0},
    {0.7f, 0.7f, 0.7f, 90, 120},
};

// In the shaders' order and layout.
typedef struct {
    simd_float2 center;    // the copy's center, in clip space
    simd_float2 scale;     // clip space per unit, x and y
    float half;            // half the copy's side, in units
    float angle;           // its turn, radians, clockwise
    float scrim;           // how far toward black
    float saturation;
    float contrast;
    float progress;        // how far the new cover has come in, 0 to 1
} CopyUniforms;

typedef struct {
    simd_float2 step;      // one texel along the pass's axis
    float sigma;           // in texels
    int radius;            // taps either side
} BlurUniforms;

typedef struct {
    simd_float4 visible;   // the visible rect as shares of the layer: x, y, width, height
    float playing;         // 0 held still, 1 flowing (eased)
    float breath;          // 0 to 1
    float warp;            // the Warp setting as a factor
    float white;
    float gain;            // the Brightness setting, on linear light
    float cap;             // the most linear luminance (Increase Contrast), 0 for none
    float grain;           // the noise's spread in eight-bit steps
    float zoom;
} ShowUniforms;

// Two grids' shifts off the even 6 x 6 grid, row by row from the visible rect's top left, in shares of its size.
enum { kGridSide = 6, kGridPoints = kGridSide * kGridSide };
typedef struct {
    simd_float2 first[kGridPoints];
    simd_float2 second[kGridPoints];
} MeshUniforms;

static float between(float least, float most) {
    return least + (most - least) * (float)arc4random_uniform(1u << 24) / (float)(1u << 24);
}

// A grid's least cell area over the mesh the show pass draws (24 x 24, the shifts read between the grid's points),
// as a share of an even cell's: below 0 the sheet folds over itself there.
static float leastArea(const simd_float2 *shift) {
    enum { n = 24 };
    simd_float2 p[n + 1][n + 1];
    for (int r = 0; r <= n; r++) {
        for (int c = 0; c <= n; c++) {
            simd_float2 q = simd_make_float2((float)c / n, (float)r / n), s = q * (kGridSide - 1);
            int ix = MIN((int)s.x, kGridSide - 2), iy = MIN((int)s.y, kGridSide - 2);
            simd_float2 f = s - simd_make_float2(ix, iy);
            int k = iy * kGridSide + ix;
            simd_float2 top = shift[k] + (shift[k + 1] - shift[k]) * f.x;
            simd_float2 bottom = shift[k + kGridSide] + (shift[k + kGridSide + 1] - shift[k + kGridSide]) * f.x;
            p[r][c] = q + top + (bottom - top) * f.y;
        }
    }
    float least = INFINITY;
    for (int r = 0; r < n; r++) {
        for (int c = 0; c < n; c++) {
            simd_float2 a = p[r][c], b = p[r][c + 1], d = p[r + 1][c + 1], e = p[r + 1][c];
            float one = (b.x - a.x) * (d.y - a.y) - (b.y - a.y) * (d.x - a.x);
            float two = (d.x - a.x) * (e.y - a.y) - (d.y - a.y) * (e.x - a.x);
            least = MIN(least, MIN(one, two) * n * n);
        }
    }
    return least;
}

// Retrine's own grids (the header's last paragraph): a smooth field of three slow waves whose push across each side
// eases to nothing at it (so the edges slide along their sides and the corners stay), scaled to an inner reach picked
// at random, then a few inner points moved for the second. Unlike the Music app's, the sheet never folds over itself:
// a fold here left a hard crease across the blurred picture, so the reach is taken down until every cell of both
// grids, and of the breath between them, keeps a quarter of its area.
static void makeMesh(MeshUniforms *mesh) {
    float f[3][4], phase[3][2], amp[3];
    for (int w = 0; w < 3; w++) {
        for (int k = 0; k < 4; k++) f[w][k] = between(1.0f, 2.6f);
        phase[w][0] = between(0, 2 * (float)M_PI);
        phase[w][1] = between(0, 2 * (float)M_PI);
        amp[w] = between(0.5f, 1.0f);
    }
    float innerSum = 0;
    for (int r = 0; r < kGridSide; r++) {
        for (int c = 0; c < kGridSide; c++) {
            float x = (float)c / (kGridSide - 1), y = (float)r / (kGridSide - 1);
            simd_float2 d = 0;
            for (int w = 0; w < 3; w++) {
                d.x += amp[w] * sinf(f[w][0] * x + f[w][1] * y + phase[w][0]);
                d.y += amp[w] * sinf(f[w][2] * x + f[w][3] * y + phase[w][1]);
            }
            d.x *= sinf((float)M_PI * x);
            d.y *= sinf((float)M_PI * y);
            mesh->first[r * kGridSide + c] = d;
            if (r > 0 && r < kGridSide - 1 && c > 0 && c < kGridSide - 1) innerSum += simd_length(d);
        }
    }
    float reach = between(0.13f, 0.21f) / MAX(1e-6f, innerSum / ((kGridSide - 2) * (kGridSide - 2)));
    for (int i = 0; i < kGridPoints; i++) mesh->second[i] = mesh->first[i] = mesh->first[i] * reach;
    int moved = 2 + (int)arc4random_uniform(7), innerPoints = (kGridSide - 2) * (kGridSide - 2);
    BOOL taken[(kGridSide - 2) * (kGridSide - 2)] = {NO};
    for (int m = 0; m < moved; m++) {
        int pick;
        do pick = (int)arc4random_uniform((uint32_t)innerPoints); while (taken[pick]);
        taken[pick] = YES;
        int i = (pick / (kGridSide - 2) + 1) * kGridSide + pick % (kGridSide - 2) + 1;
        float angle = between(0, 2 * (float)M_PI), length = between(0.04f, 0.12f);
        mesh->second[i] += length * simd_make_float2(cosf(angle), sinf(angle));
    }
    for (int tries = 0; tries < 60; tries++) {
        simd_float2 middle[kGridPoints];
        for (int i = 0; i < kGridPoints; i++) middle[i] = (mesh->first[i] + mesh->second[i]) * 0.5f;
        if (MIN(leastArea(mesh->first), MIN(leastArea(mesh->second), leastArea(middle))) >= 0.25f) break;
        for (int i = 0; i < kGridPoints; i++) {
            mesh->first[i] *= 0.95f;
            mesh->second[i] *= 0.95f;
        }
    }
}

// At its standard the Grain setting adds no noise, as the Music app's backdrop has none; above it, up to 24 steps.
static const float kGrainStandardSteps = 0, kGrainMostSteps = 24;

static float grainSteps(float factor) {
    SGRFluidLimits limits = SGRFluidLimitsOf(SGRFluidGrain);
    float most = (float)limits.most / (float)limits.standard;
    if (factor <= 1) return factor * kGrainStandardSteps;
    return kGrainStandardSteps + (MIN(factor, most) - 1) / (most - 1) * (kGrainMostSteps - kGrainStandardSteps);
}

static NSString *const kShader = @"#include <metal_stdlib>\n"
"using namespace metal;\n"
"struct CopyU { float2 center; float2 scale; float halfSide; float angle; float scrim; float saturation; float contrast; float progress; };\n"
"struct BlurU { float2 step; float sigma; int radius; };\n"
"struct ShowU { float4 visible; float playing; float breath; float warp; float white; float gain; float cap; float grain; float zoom; };\n"
"struct CV { float4 position [[position]]; float2 uv; uint copy [[flat]]; };\n"
"struct V { float4 position [[position]]; float2 uv; };\n"
// A copy: a square turned about its own center, clockwise (y up), placed and scaled into clip space.
"vertex CV copyVertex(uint vid [[vertex_id]], uint iid [[instance_id]], constant CopyU *u [[buffer(0)]]) {\n"
"    CopyU c = u[iid];\n"
"    float2 corner = float2((vid & 1) ? 1.0 : -1.0, (vid & 2) ? 1.0 : -1.0);\n"
"    float2 l = corner * c.halfSide;\n"
"    float co = cos(c.angle), si = sin(c.angle);\n"
"    float2 w = float2(co * l.x + si * l.y, -si * l.x + co * l.y);\n"
"    CV v;\n"
"    v.position = float4(c.center + w * c.scale, 0.0, 1.0);\n"
"    v.uv = float2(corner.x * 0.5 + 0.5, 0.5 - corner.y * 0.5);\n"
"    v.copy = iid;\n"
"    return v;\n"
"}\n"
"static float4 gradeCopy(float3 rgb, CopyU c) {\n"
"    rgb = mix(rgb, float3(0.0), c.scrim);\n"
"    rgb = (rgb - 0.5) * c.contrast + 0.5;\n"
"    float l = dot(rgb, float3(0.2126, 0.7152, 0.0722));\n"
"    return float4(l + c.saturation * (rgb - l), 1.0);\n"
"}\n"
"fragment float4 copyFragment(CV in [[stage_in]], constant CopyU *u [[buffer(0)]],\n"
"                             texture2d<float> to [[texture(1)]], sampler s [[sampler(0)]]) {\n"
"    return gradeCopy(to.sample(s, in.uv).rgb, u[in.copy]);\n"
"}\n"
"fragment float4 fadeFragment(CV in [[stage_in]], constant CopyU *u [[buffer(0)]],\n"
"                             texture2d<float> from [[texture(0)]], texture2d<float> to [[texture(1)]], sampler s [[sampler(0)]]) {\n"
"    CopyU c = u[in.copy];\n"
"    return gradeCopy(mix(from.sample(s, in.uv).rgb, to.sample(s, in.uv).rgb, c.progress), c);\n"
"}\n"
// One triangle past the corners covers the target; uv runs 0 to 1 down and across it.
"vertex V fullVertex(uint id [[vertex_id]]) {\n"
"    float2 p = float2((id << 1) & 2, id & 2);\n"
"    V v;\n"
"    v.position = float4(p * 2.0 - 1.0, 0.0, 1.0);\n"
"    v.uv = float2(p.x, 1.0 - p.y);\n"
"    return v;\n"
"}\n"
// One axis of a Gaussian.
"fragment float4 blurFragment(V in [[stage_in]], constant BlurU &u [[buffer(0)]], texture2d<float> t [[texture(0)]], sampler s [[sampler(0)]]) {\n"
"    float3 sum = float3(0.0); float weights = 0.0;\n"
"    for (int i = -u.radius; i <= u.radius; i++) {\n"
"        float w = exp(-float(i * i) / (2.0 * u.sigma * u.sigma));\n"
"        sum += w * t.sample(s, in.uv + u.step * float(i)).rgb;\n"
"        weights += w;\n"
"    }\n"
"    return float4(sum / weights, 1.0);\n"
"}\n"
"struct MeshU { float2 first[36]; float2 second[36]; };\n"
// A grid's shift at q (0 to 1 over the visible rect), between its points; beyond the rect, its edge's.
"static float2 shiftAt(constant float2 *grid, float2 q) {\n"
"    float2 s = clamp(q, 0.0, 1.0) * 5.0;\n"
"    int2 i = min(int2(s), int2(4));\n"
"    float2 f = s - float2(i);\n"
"    int k = i.y * 6 + i.x;\n"
"    return mix(mix(grid[k], grid[k + 1], f.x), mix(grid[k + 6], grid[k + 7], f.x), f.y);\n"
"}\n"
// The mesh: each point of the picture (uv) drawn where the held zoom or the breathing grids put it.
"vertex V showVertex(uint vid [[vertex_id]], constant ShowU &u [[buffer(0)]], constant MeshU &m [[buffer(1)]]) {\n"
"    const uint n = 24u;\n"
"    uint cell = vid / 6u, k = vid % 6u;\n"
"    uint cx = cell % n, cy = cell / n;\n"
"    uint ox = (k == 1u || k == 3u || k == 4u) ? 1u : 0u;\n"
"    uint oy = (k == 2u || k == 4u || k == 5u) ? 1u : 0u;\n"
"    float2 uv = float2(float(cx + ox), float(cy + oy)) / float(n);\n"
"    float2 middle = u.visible.xy + u.visible.zw * 0.5;\n"
"    float2 held = middle + (uv - middle) * u.zoom;\n"
"    float2 q = (uv - u.visible.xy) / u.visible.zw;\n"
"    float2 bent = uv + u.warp * mix(shiftAt(m.first, q), shiftAt(m.second, q), u.breath) * u.visible.zw;\n"
"    float2 p = mix(held, bent, u.playing);\n"
"    V v;\n"
"    v.position = float4(p.x * 2.0 - 1.0, 1.0 - p.y * 2.0, 0.0, 1.0);\n"
// Upside down: the Music app's display mesh gives each point the picture's texel at the same grid place, with the grid's
// y running up the screen and the picture's down, so its backdrop shows the cover's foot at the top.
"    v.uv = float2(uv.x, 2.0 * middle.y - uv.y);\n"
"    return v;\n"
"}\n"
"static float3 decodeSRGB(float3 c) { return select(pow((c + 0.055) / 1.055, 2.4), c / 12.92, c <= 0.04045); }\n"
"static float3 encodeSRGB(float3 c) { return select(1.055 * pow(c, 1.0 / 2.4) - 0.055, c * 12.92, c <= 0.0031308); }\n"
"fragment float4 showFragment(V in [[stage_in]], constant ShowU &u [[buffer(0)]], texture2d<float> picture [[texture(0)]],\n"
"                             texture3d<float> table [[texture(1)]], sampler s [[sampler(0)]]) {\n"
"    float3 c = picture.sample(s, in.uv).rgb;\n"
"    c = mix(c, float3(1.0), u.white);\n"
"    c = table.sample(s, saturate(c)).rgb;\n"

"    if (u.gain != 1.0 || u.cap > 0.0) {\n"
"        float3 lin = decodeSRGB(c) * u.gain;\n"
"        float light = dot(lin, float3(0.2126, 0.7152, 0.0722));\n"
"        if (u.cap > 0.0 && light > u.cap) lin *= u.cap / light;\n"
"        c = encodeSRGB(saturate(lin));\n"
"    }\n"
"    uint2 ip = uint2(in.position.xy);\n"
"    uint h = ip.x * 1973u + ip.y * 9277u;\n"
"    h = (h ^ (h >> 13)) * 1274126177u;\n"
"    h ^= h >> 16;\n"
"    float noise = float(h & 0xffffu) / 65535.0 - 0.5;\n"
"    return float4(c + min(noise * u.grain, 0.5) / 255.0, 1.0);\n"
"}\n";

BOOL SGRFluidGPUAvailable(void) {
    static BOOL available;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ available = MTLCreateSystemDefaultDevice() != nil; });
    return available;
}

// What every layer shares, made once on the main thread; the shaders compile off it.
static id<MTLDevice> sDevice;
static id<MTLCommandQueue> sQueue;
static id<MTLRenderPipelineState> sCopy, sFade, sBlur, sShow;
static id<MTLSamplerState> sLinear;
static id<MTLTexture> sTable;
static BOOL sFailed;
static NSMutableArray<void (^)(void)> *sWaiting;

static void finish(NSError *error) {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSArray<void (^)(void)> *waiting = sWaiting;
        sWaiting = nil;
        if (!sCopy || !sFade || !sBlur || !sShow) {
            sFailed = YES;
            SGLog(@"redesign kit: the Fluid shader failed, Light stays: %@", error.localizedDescription ?: @"no reason");
            return;
        }
        for (void (^ready)(void) in waiting) ready();
    });
}

// The pictures between the copies and the screen are half floats: what the saturation pushes below 0 or above 1 is kept through the blur, which
// leaves a strong color deeper than an 8-bit picture, clamped first, would.
static const MTLPixelFormat kPictureFormat = MTLPixelFormatRGBA16Float;

static id<MTLRenderPipelineState> pipeline(id<MTLLibrary> library, NSString *vertex, NSString *fragment, MTLPixelFormat format, NSError **error) {
    MTLRenderPipelineDescriptor *described = [MTLRenderPipelineDescriptor new];
    described.vertexFunction = [library newFunctionWithName:vertex];
    described.fragmentFunction = [library newFunctionWithName:fragment];
    described.colorAttachments[0].pixelFormat = format;
    return [sDevice newRenderPipelineStateWithDescriptor:described error:error];
}

// The color table: each texel the grade of its own center, so a linear read at a color is the grade of that color.
static id<MTLTexture> makeTable(void) {
    NSData *data = SGRFluidGradeTable(kLUTSide);
    if (data.length != (NSUInteger)kLUTSide * kLUTSide * kLUTSide * 4) return nil;
    MTLTextureDescriptor *described = [MTLTextureDescriptor new];
    described.textureType = MTLTextureType3D;
    described.pixelFormat = MTLPixelFormatRGBA8Unorm;
    described.width = described.height = described.depth = kLUTSide;
    described.usage = MTLTextureUsageShaderRead;
    id<MTLTexture> texture = [sDevice newTextureWithDescriptor:described];
    [texture replaceRegion:MTLRegionMake3D(0, 0, 0, kLUTSide, kLUTSide, kLUTSide) mipmapLevel:0 slice:0
                 withBytes:data.bytes bytesPerRow:kLUTSide * 4 bytesPerImage:kLUTSide * kLUTSide * 4];
    return texture;
}

// Runs the block on the main thread once the pipelines exist: at once if they do, never if they failed.
static void whenReady(void (^ready)(void)) {
    if (sShow) { ready(); return; }
    if (sFailed) return;
    if (sWaiting) { [sWaiting addObject:ready]; return; }
    sWaiting = [NSMutableArray arrayWithObject:ready];
    sDevice = MTLCreateSystemDefaultDevice();
    sQueue = [sDevice newCommandQueue];
    if (!sDevice || !sQueue) { finish(nil); return; }
    MTLSamplerDescriptor *linear = [MTLSamplerDescriptor new];
    linear.minFilter = MTLSamplerMinMagFilterLinear;
    linear.magFilter = MTLSamplerMinMagFilterLinear;
    linear.sAddressMode = MTLSamplerAddressModeClampToEdge;
    linear.tAddressMode = MTLSamplerAddressModeClampToEdge;
    linear.rAddressMode = MTLSamplerAddressModeClampToEdge;
    // The cover is read from its mipmaps when the picture is far smaller than it, so the small picture does not shimmer.
    linear.mipFilter = MTLSamplerMipFilterLinear;
    sLinear = [sDevice newSamplerStateWithDescriptor:linear];
    sTable = makeTable();
    if (!sTable) { finish(nil); return; }
    id<MTLDevice> device = sDevice;
    [device newLibraryWithSource:kShader options:nil completionHandler:^(id<MTLLibrary> library, NSError *error) {
        if (!library) { finish(error); return; }
        NSError *failure = nil;
        id<MTLRenderPipelineState> copy = pipeline(library, @"copyVertex", @"copyFragment", kPictureFormat, &failure);
        id<MTLRenderPipelineState> fade = copy ? pipeline(library, @"copyVertex", @"fadeFragment", kPictureFormat, &failure) : nil;
        id<MTLRenderPipelineState> blur = fade ? pipeline(library, @"fullVertex", @"blurFragment", kPictureFormat, &failure) : nil;
        id<MTLRenderPipelineState> show = blur ? pipeline(library, @"showVertex", @"showFragment", MTLPixelFormatBGRA8Unorm, &failure) : nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            sCopy = copy; sFade = fade; sBlur = blur; sShow = show;
            finish(failure);
        });
    }];
}

// The cover as a texture, in its encoded numbers as they are (the Music app loads it without sRGB decoding).
static id<MTLTexture> textureOf(id picture) {
    CGImageRef image = (__bridge CGImageRef)picture;
    size_t width = CGImageGetWidth(image), height = CGImageGetHeight(image);
    if (!sDevice || width == 0 || height == 0) return nil;
    CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGContextRef bitmap = CGBitmapContextCreate(NULL, width, height, 8, width * 4, space,
                                                kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(space);
    if (!bitmap) return nil;
    CGContextDrawImage(bitmap, CGRectMake(0, 0, width, height), image);
    MTLTextureDescriptor *described = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
                                                                                         width:width height:height mipmapped:YES];
    described.usage = MTLTextureUsageShaderRead;
    id<MTLTexture> texture = [sDevice newTextureWithDescriptor:described];
    if (!texture) { CGContextRelease(bitmap); return nil; }
    [texture replaceRegion:MTLRegionMake2D(0, 0, width, height) mipmapLevel:0
                 withBytes:CGBitmapContextGetData(bitmap) bytesPerRow:width * 4];
    CGContextRelease(bitmap);
    // Its mipmaps, made on the queue every frame is drawn on, so they are there before the first frame reads them.
    id<MTLCommandBuffer> buffer = [sQueue commandBuffer];
    id<MTLBlitCommandEncoder> blit = [buffer blitCommandEncoder];
    [blit generateMipmapsForTexture:texture];
    [blit endEncoding];
    [buffer commit];
    return texture;
}

static id<MTLTexture> target(NSUInteger width, NSUInteger height) {
    MTLTextureDescriptor *described = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:kPictureFormat
                                                                                         width:MAX(1u, width) height:MAX(1u, height) mipmapped:NO];
    described.usage = MTLTextureUsageShaderRead | MTLTextureUsageRenderTarget;
    described.storageMode = MTLStorageModePrivate;
    return [sDevice newTextureWithDescriptor:described];
}

@interface SGRFluidGPULayer ()
- (void)tick:(CADisplayLink *)link;
@end

// The display link's target, so the link (which retains it) does not keep the layer.
@interface SGRFluidTicker : NSObject
@property (nonatomic, weak) SGRFluidGPULayer *layer;
@end

@implementation SGRFluidTicker
- (void)tick:(CADisplayLink *)link {
    [self.layer tick:link];
}
@end

@implementation SGRFluidGPULayer {
    id _fromPicture, _toPicture;   // CGImages of the cover
    id<MTLTexture> _from, _to;
    id<MTLTexture> _copies, _across, _blurred;   // the small picture, its blur's first pass, and the blurred one
    float _progress;
    CFTimeInterval _length, _last;
    double _time;
    float _settle;
    float _history[4][3];   // the last four readings of the bands, oldest first
    float _peak[3], _follow[3];
    uint64_t _reading;      // the last reading of the music taken in
    MeshUniforms _mesh;
    CADisplayLink *_link;
    BOOL _ready, _dirty, _firstPending;
    BOOL _acquiring;
    BOOL _spectrumWanted;
    CGSize _wantedSize;
    NSUInteger _pictureRevision, _presentedRevision, _misses;
    BOOL _resigning;
    int _firstFailures;
}

- (instancetype)init {
    if (!(self = [super init])) return nil;
    _rate = 1;
    _warp = 1;
    _grain = 1;
    _saturation = 1;
    _gain = 1;
    _blur = 1;
    _progress = 1;
    makeMesh(&_mesh);
    self.pixelFormat = MTLPixelFormatBGRA8Unorm;
    self.framebufferOnly = YES;
    self.maximumDrawableCount = 2;
    self.opaque = YES;
    self.contentsScale = 1;
    CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    self.colorspace = space;
    CGColorSpaceRelease(space);
    NSNull *off = NSNull.null;
    self.actions = @{@"bounds": off, @"position": off, @"frame": off, @"contents": off, @"hidden": off};
    __weak SGRFluidGPULayer *weakSelf = self;
    whenReady(^{
        SGRFluidGPULayer *layer = weakSelf;
        if (!layer) return;
        layer.device = sDevice;
        layer->_ready = YES;
        [layer update];
    });
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(becameActive)
        name:UIApplicationDidBecomeActiveNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(resigning)
        name:UIApplicationWillResignActiveNotification object:nil];
    // Hold the work while the player opens or closes, and resume its clock only after the transition has finished.
    SGRObservePlayerTransition(self, ^(id owner) { [owner update]; });
    return self;
}

- (void)dealloc {
    if (_spectrumWanted) SGMusicSpectrumRemoveReader();
    [_link invalidate];
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

#pragma mark - what it shows

- (void)resigning {
    _resigning = YES;
    [self update];
}

- (void)becameActive {
    _resigning = NO;
    [self update];
}

- (BOOL)mayDraw {
    return !_held && !_resigning && UIApplication.sharedApplication.applicationState == UIApplicationStateActive
        && !SGRPlayerIsTransitioning();
}

- (BOOL)hasPresentedCover {
    return _toPicture && _pictureRevision == _presentedRevision;
}

- (void)setCover:(CGImageRef)cover animated:(BOOL)animated {
    BOOL fade = cover && animated && _toPicture && (_progress < 1 || self.hasPresentedCover) && [self mayDraw];
    _pictureRevision++;
    _firstPending = NO;
    _firstFailures = 0;
    if (fade) {
        // One still coming in is cut short: the new one comes in over the one it was bringing.
        _fromPicture = _toPicture;
        _from = _to;
        _length = _moving && !SGRReduceMotion() ? kRunIn : kBackdropCrossfade;
        _progress = 0;
    } else {
        _fromPicture = nil;
        _from = nil;
        _progress = 1;
    }
    _toPicture = (__bridge id)cover;
    _to = nil;
    _dirty = YES;
    [self update];
}

- (void)setMoving:(BOOL)moving {
    if (moving == _moving) return;
    _moving = moving;
    // Stopping, the Music app's analyzer sends one empty report and then none.
    if (!moving) {
        static const float silence[3] = {0, 0, 0};
        [self take:silence];
    }
    [self update];
}

- (void)setHeld:(BOOL)held {
    if (held == _held) return;
    _held = held;
    [self update];
}

- (void)setWarp:(float)warp {
    if (warp == _warp) return;
    _warp = warp;
    _dirty = YES;
    [self update];
}

- (void)setGrain:(float)grain {
    if (grain == _grain) return;
    _grain = grain;
    _dirty = YES;
    [self update];
}

- (void)setSaturation:(float)saturation {
    if (saturation == _saturation) return;
    _saturation = saturation;
    _dirty = YES;
    [self update];
}

- (void)setGain:(float)gain {
    if (gain == _gain) return;
    _gain = gain;
    _dirty = YES;
    [self update];
}

- (void)setBlur:(float)blur {
    if (blur == _blur) return;
    _blur = blur;
    _dirty = YES;
    [self update];
}

- (void)setContrast:(BOOL)contrast {
    if (contrast == _contrast) return;
    _contrast = contrast;
    _dirty = YES;
    [self update];
}

- (void)setVisibleRect:(CGRect)rect {
    if (CGRectEqualToRect(rect, _visibleRect)) return;
    _visibleRect = rect;
    _dirty = YES;
    [self update];
}

- (void)setBounds:(CGRect)bounds {
    [super setBounds:bounds];
    [self fit];
}

- (void)setFrame:(CGRect)frame {
    [super setFrame:frame];
    [self fit];
}

- (void)layoutSublayers {
    [super layoutSublayers];
    [self fit];
}

- (void)fit {
    CGSize bounds = self.bounds.size;
    CGSize size = CGSizeMake(MAX(1, round(bounds.width * self.contentsScale)), MAX(1, round(bounds.height * self.contentsScale)));
    if (CGSizeEqualToSize(size, _wantedSize)) return;
    _wantedSize = size;
    if (!_acquiring) self.drawableSize = size;
    _dirty = YES;
    [self update];
}

#pragma mark - drawing

// The Music app's ease for settling, a cubic Bezier through (0.42, 0) and (0.58, 1), solved for its x.
static float easeInOut(float x) {
    if (x <= 0) return 0;
    if (x >= 1) return 1;
    float t = x;
    for (int i = 0; i < 8; i++) {
        float u = 1 - t;
        float bx = 3 * u * u * t * 0.42f + 3 * u * t * t * 0.58f + t * t * t;
        float dx = 3 * u * u * 0.42f + 6 * u * t * (0.58f - 0.42f) + 3 * t * t * (1 - 0.58f);
        if (fabsf(dx) < 1e-5f) break;
        t = MIN(1.0f, MAX(0.0f, t - (bx - x) / dx));
    }
    float u = 1 - t;
    return 3 * u * t * t + t * t * t;
}

// A reading into the last four, the oldest let go.
- (void)take:(const float *)levels {
    memmove(_history[0], _history[1], sizeof(float) * 3 * 3);
    memcpy(_history[3], levels, sizeof(float) * 3);
}

// Each new reading of the music into the last four, in order (each taken once, as the Music app's main queue takes
// each report), then one of its frames of the peak and the follow: the peak let down by its share of itself, held up
// to the average of the last four, and followed half way. Paused, no readings come: the average of the last four
// holds, and so does what the music had grown, as the Music app's does.
- (void)hear {
    uint64_t readings = SGMusicSpectrumReadings();
    if (!_moving || _reading > readings) _reading = readings;
    for (; _reading < readings; _reading++) {
        float levels[3];
        if (SGMusicSpectrumReading(_reading, levels)) [self take:levels];
    }
    for (int b = 0; b < 3; b++) {
        float average = 0;
        for (int k = 0; k < 4; k++) average += kHistoryWeight[k] * _history[k][b];
        _peak[b] = MAX(_peak[b] - _peak[b] * kPeakFall[b], average);
        _follow[b] += 0.5f * (_peak[b] - _follow[b]);
    }
}

// The field owns playback, accessibility and power holds. Only the finite settle/fade
// or a dirty still can keep the link after motion stops.
- (void)update {
    if ((_held || _resigning) && _progress < 1) {
        _fromPicture = nil;
        _from = nil;
        _progress = 1;
        _dirty = YES;
    }
    BOOL eligible = _ready && _toPicture && [self mayDraw] && _firstFailures < 3;
    BOOL wants = eligible && self.bounds.size.width >= 1 && self.bounds.size.height >= 1 &&
                 (_moving || _settle > 0 || _progress < 1 || _dirty);
    BOOL spectrum = wants && _moving;
    if (spectrum != _spectrumWanted) {
        _spectrumWanted = spectrum;
        if (spectrum) {
            _reading = SGMusicSpectrumReadings();
            SGMusicSpectrumAddReader();
        } else SGMusicSpectrumRemoveReader();
    }
    if (wants && !_link) {
        SGRFluidTicker *ticker = [SGRFluidTicker new];
        ticker.layer = self;
        _link = [CADisplayLink displayLinkWithTarget:ticker selector:@selector(tick:)];
        _link.preferredFrameRateRange = CAFrameRateRangeMake(15, 120, kDrawFramesPerSecond);
        _last = 0;
        [_link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    } else if (!wants && _link) {
        [_link invalidate];
        _link = nil;
    }
}

- (void)tick:(CADisplayLink *)link {
    if (![self mayDraw]) {
        [self update];
        return;
    }
    CFTimeInterval now = link.timestamp;
    if (_acquiring || _firstPending || (_last > 0 && now - _last + 1e-6 < 1.0 / kDrawFramesPerSecond)) return;
    CFTimeInterval step = _last > 0 ? MIN(0.1, now - _last) : 0;
    _last = now;
    if (_moving) _time += step * _rate;
    _settle = (float)MAX(0.0, MIN(1.0, _settle + (_moving ? step : -step) / kSettleClock));
    [self hear];
    if (_progress < 1) {
        _progress = (float)MIN(1.0, _progress + step / MAX(0.05, _length));
        if (_progress >= 1) {
            _fromPicture = nil;
            _from = nil;
        }
    }
    _dirty = YES;
    [self acquireFrame];
}

- (void)acquireFrame {
    if (_acquiring || _firstPending) return;
    _acquiring = YES;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INTERACTIVE, 0), ^{
        id<CAMetalDrawable> output = [self nextDrawable];
        dispatch_async(dispatch_get_main_queue(), ^{
            self->_acquiring = NO;
            if (!CGSizeEqualToSize(self.drawableSize, self->_wantedSize)) {
                self.drawableSize = self->_wantedSize;
                if (self->_link && [self mayDraw]) [self acquireFrame];
                return;
            }
            if (!self->_link || ![self mayDraw]) return;
            CGSize size = self.drawableSize;
            if (output && output.texture.width == (NSUInteger)size.width && output.texture.height == (NSUInteger)size.height
                && [self draw:output]) self->_misses = 0;
            else if (!self->_moving && self->_progress >= 1 && ++self->_misses >= 30) {
                self->_dirty = NO;
                self->_misses = 0;
            }
            [self update];
        });
    });
}

- (BOOL)draw:(id<CAMetalDrawable>)output {
    CGRect bounds = self.bounds;
    if (bounds.size.width < 1 || bounds.size.height < 1) return NO;
    if (!_to) _to = textureOf(_toPicture);
    if (_fromPicture && !_from) _from = textureOf(_fromPicture);
    if (!_to) return NO;
    CGSize drawable = self.drawableSize;
    // The picture's size: as small as keeps the blur about kBlurTexels across, never under a sixteenth of the drawable.
    float sigmaDrawable = kBlurPoints * _blur * (float)self.contentsScale;
    NSUInteger divisor = MIN(kMostDivisor, MAX(kLeastDivisor, (NSUInteger)floorf(sigmaDrawable / kBlurTexels)));
    NSUInteger qw = MAX((NSUInteger)4, (NSUInteger)drawable.width / divisor), qh = MAX((NSUInteger)4, (NSUInteger)drawable.height / divisor);
    if (!_copies || _copies.width != qw || _copies.height != qh) {
        id<MTLTexture> copies = target(qw, qh), across = target(qw, qh), blurred = target(qw, qh);
        if (!copies || !across || !blurred) return NO;
        _copies = copies;
        _across = across;
        _blurred = blurred;
    }

    // Where the copies go: the unit is half the visible rect's longer side, about its middle, in the layer's clip space.
    CGRect visible = CGRectIsEmpty(_visibleRect) ? bounds : _visibleRect;
    CGFloat unit = MAX(visible.size.width, visible.size.height) / 2;
    simd_float2 middle = simd_make_float2((float)((CGRectGetMidX(visible) - bounds.origin.x) / bounds.size.width * 2 - 1),
                                          (float)(1 - (CGRectGetMidY(visible) - bounds.origin.y) / bounds.size.height * 2));
    simd_float2 scale = simd_make_float2((float)(unit / (bounds.size.width / 2)), (float)(unit / (bounds.size.height / 2)));
    // The music: eased, then bass to contrast, treble to saturation, bass and middle to the growth.
    float heard[3];
    for (int b = 0; b < 3; b++) {
        float x = MIN(1.0f, MAX(0.0f, _follow[b]));
        heard[b] = x * x * x * (x * (x * 6 - 15) + 10);
    }
    float m = heard[0] + (heard[1] - heard[0]) * kGrowthMiddle;
    float growth = 1 + kGrowth * m * m;
    scale *= growth;
    float orbit = (float)(2 * M_PI * fmod(_time, kCopy[2].orbit) / kCopy[2].orbit);
    CopyUniforms copies[3];
    NSUInteger drawn = _warp > 0.01f ? 3 : 1;
    for (int i = 0; i < 3; i++) {
        float x = kCopy[i].x * _warp, y = kCopy[i].y * _warp;
        if (kCopy[i].orbit > 0) {
            float c = cosf(orbit), s = sinf(orbit);
            float rx = c * x + s * y, ry = -s * x + c * y;   // clockwise, y up
            x = rx;
            y = ry;
        }
        copies[i] = (CopyUniforms){
            .center = middle + simd_make_float2(x, y) * scale,
            .scale = scale,
            .half = kCopy[i].side,
            // A carried copy is turned by its carrier too: the Music app turns its whole model, not only its place.
            .angle = (float)(2 * M_PI * fmod(_time, kCopy[i].turn) / kCopy[i].turn) + (kCopy[i].orbit > 0 ? orbit : 0),
            .scrim = kCopyScrim + kCopyScrimStep * i,
            .saturation = (kCopySaturation + kSaturationPerTreble * heard[2]) * _saturation,
            .contrast = 1 + kContrastPerBass * heard[0],
            .progress = _from ? _progress : 1,
        };
    }
    id<MTLCommandBuffer> buffer = [sQueue commandBuffer];

    MTLRenderPassDescriptor *pass = [MTLRenderPassDescriptor renderPassDescriptor];
    pass.colorAttachments[0].texture = _copies;
    pass.colorAttachments[0].loadAction = MTLLoadActionClear;
    pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1);
    pass.colorAttachments[0].storeAction = MTLStoreActionStore;
    id<MTLRenderCommandEncoder> encoder = [buffer renderCommandEncoderWithDescriptor:pass];
    [encoder setRenderPipelineState:_from ? sFade : sCopy];
    [encoder setVertexBytes:copies length:sizeof(copies) atIndex:0];
    [encoder setFragmentBytes:copies length:sizeof(copies) atIndex:0];
    if (_from) [encoder setFragmentTexture:_from atIndex:0];
    [encoder setFragmentTexture:_to atIndex:1];
    [encoder setFragmentSamplerState:sLinear atIndex:0];
    [encoder drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4 instanceCount:drawn];
    [encoder endEncoding];

    // The blur: kBlurPoints on screen, in the picture's texels (it is 1 / divisor of the drawable), out to 2.5 sigma
    // (what is left past it weighs under 2% of the kernel).
    float sigma = MAX(0.5f, sigmaDrawable / (float)(drawable.width / qw));
    int radius = MIN(64, (int)ceilf(sigma * 2.5f));
    BlurUniforms blurs[2] = {
        {simd_make_float2(1.0f / qw, 0), sigma, radius},
        {simd_make_float2(0, 1.0f / qh), sigma, radius},
    };
    id<MTLTexture> sources[2] = {_copies, _across}, targets[2] = {_across, _blurred};
    for (int k = 0; k < 2; k++) {
        MTLRenderPassDescriptor *blurPass = [MTLRenderPassDescriptor renderPassDescriptor];
        blurPass.colorAttachments[0].texture = targets[k];
        blurPass.colorAttachments[0].loadAction = MTLLoadActionDontCare;
        blurPass.colorAttachments[0].storeAction = MTLStoreActionStore;
        id<MTLRenderCommandEncoder> blur = [buffer renderCommandEncoderWithDescriptor:blurPass];
        [blur setRenderPipelineState:sBlur];
        [blur setFragmentBytes:&blurs[k] length:sizeof(BlurUniforms) atIndex:0];
        [blur setFragmentTexture:sources[k] atIndex:0];
        [blur setFragmentSamplerState:sLinear atIndex:0];
        [blur drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
        [blur endEncoding];
    }

    float eased = easeInOut(_settle);
    ShowUniforms show = {
        .visible = simd_make_float4((float)((visible.origin.x - bounds.origin.x) / bounds.size.width),
                                    (float)((visible.origin.y - bounds.origin.y) / bounds.size.height),
                                    (float)(MAX(1, visible.size.width) / bounds.size.width),
                                    (float)(MAX(1, visible.size.height) / bounds.size.height)),
        .playing = eased,
        .breath = (float)(0.5 + 0.5 * sin(_time / kBreathPeriod)),
        .warp = _warp,
        .white = kWhite,
        .gain = _gain,
        .cap = _contrast ? 0.04f : 0,
        .grain = grainSteps(_grain),
        .zoom = kHeldZoom,
    };
    MTLRenderPassDescriptor *showPass = [MTLRenderPassDescriptor renderPassDescriptor];
    showPass.colorAttachments[0].texture = output.texture;
    showPass.colorAttachments[0].loadAction = MTLLoadActionClear;
    showPass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1);
    showPass.colorAttachments[0].storeAction = MTLStoreActionStore;
    id<MTLRenderCommandEncoder> shown = [buffer renderCommandEncoderWithDescriptor:showPass];
    [shown setRenderPipelineState:sShow];
    [shown setVertexBytes:&show length:sizeof(show) atIndex:0];
    [shown setVertexBytes:&_mesh length:sizeof(_mesh) atIndex:1];
    [shown setFragmentBytes:&show length:sizeof(show) atIndex:0];
    [shown setFragmentTexture:_blurred atIndex:0];
    [shown setFragmentTexture:sTable atIndex:1];
    [shown setFragmentSamplerState:sLinear atIndex:0];
    [shown drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:kMeshCells * kMeshCells * 6];
    [shown endEncoding];

    BOOL presentsDestination = !self.hasPresentedCover && _progress >= 1;
    self.presentsWithTransaction = presentsDestination;
    if (presentsDestination) {
        _firstPending = YES;
        // Uncover this revision in the transaction presenting it, never an old completion.
        NSUInteger revision = _pictureRevision;
        __weak SGRFluidGPULayer *weakSelf = self;
        [buffer addCompletedHandler:^(id<MTLCommandBuffer> done) {
            BOOL completed = done.status == MTLCommandBufferStatusCompleted;
            dispatch_async(dispatch_get_main_queue(), ^{
                SGRFluidGPULayer *layer = weakSelf;
                if (!layer || revision != layer->_pictureRevision) return;
                layer->_firstPending = NO;
                if (![layer mayDraw] || !CGSizeEqualToSize(drawable, layer->_wantedSize)) {
                    layer->_dirty = YES;
                    [layer update];
                    return;
                }
                [CATransaction begin];
                if (completed) [output present];
                [layer firstFrameCompleted:completed];
                [CATransaction commit];
            });
        }];
    } else [buffer presentDrawable:output];
#ifdef SGR_FLUID_FRAME_PROBE
    extern void SGRProbeFluidFrame(CAMetalLayer *, id<CAMetalDrawable>, id<MTLCommandBuffer>);
    SGRProbeFluidFrame(self, output, buffer);
#endif
    [buffer commit];
    _dirty = NO;
    return YES;
}

- (void)firstFrameCompleted:(BOOL)completed {
    if (!completed) {
        SGLog(@"redesign kit: Fluid's first frame failed on the GPU (%d), Light stays", ++_firstFailures);
        _dirty = YES;
        [self update];
        return;
    }
    _presentedRevision = _pictureRevision;
    void (^drawn)(void) = _drawn;
    if (drawn) drawn();
}

@end
