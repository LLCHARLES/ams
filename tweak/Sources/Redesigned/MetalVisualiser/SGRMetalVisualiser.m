// SGRMetalVisualiser.m
//
// 见 .h 的说明。
//
// 频谱: 读 SGRSpectrum(24 频段, Spotify 自己的输出经 Accelerate FFT),
// 映射进 256x2 的纹理 —— 行0 是频段、行1 是 dB 级,与二进制里的布局一致。
// 每帧上传一次 2KB,开销可忽略。
//
// 取色: 封面变了就重算三档配色 + 强调色。取的是 SGRPalette 的 flowColors,
// 那是 Kit 已经算好的流动配色,和播放页其他地方一致。
//
// Threading: 主线程。渲染每帧一个 CADisplayLink,与 PlayerVisualiser 同节流:
// 歌词页 30fps,Reduce Motion 15fps,低电量模式停。
#import <dlfcn.h>
#import "SGRMetalVisualiser.h"
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Redesigned/Player/SGRSpectrum.h"
#import "Shared/AudioEffects/AudioEffects.h"

// ============================================================================
// Uniform 桥接 —— 与 .metal 里逐字段对应
// ============================================================================

// The uniform block, laid out to match Frame/Params in the .metal exactly: a pair of floats,
// then four-vectors, then scalars. SIMD types are spelled out as structs rather than
// vector_floatN so the layout does not depend on which Metal headers happen to be in scope.
typedef struct { float x, y; } SGRSimd2;
typedef struct { float x, y, z, w; } SGRSimd4;

typedef struct {
    SGRSimd2 resolution;
    SGRSimd2 focus;
    SGRSimd2 tilt;
    SGRSimd4 textAspect;
    SGRSimd4 color0;
    SGRSimd4 color1;
    SGRSimd4 color2;
    SGRSimd4 accent;
    float flowAmount;
    float audioAmount;
    float edgeSmooth;
    float saturation;
    float brightness;
    float zoom;
    float time;
    uint32_t spectrumBands;
    uint32_t _pad;
    // 构图,与 shader 的 Params 里同名的一组一一对应。四张副本各自旋转、错落分布,
    // 压暗带盖在控制条下面。数值取自 vitrine 的 SGRFluid.m。
    float warp;            // 副本中心离可见区中点的远近,以及上三张的不透明度
    float shadeFrom;       // 压暗带起点(可见区高度的比例)
    float shadeAlpha;      // 压暗带底端的黑度
    float coverScale;      // 副本边长占可见区长边的倍数
    SGRSimd2 visibleTopLeft;
    SGRSimd2 visibleSize;
} SGRMetalUniforms;

// ============================================================================
// 设置
// ============================================================================

// 键与 SGRFluid 的命名一致,便于用户界面复用。
static const struct { __unsafe_unretained NSString *key; SGRMetalLimits limits; } kSettings[] = {
    {@"spotifyglass.metal.flow",       {0,  100, 5, 50}},
    {@"spotifyglass.metal.audio",      {0,  100, 5, 70}},
    {@"spotifyglass.metal.blur",       {0,  100, 5, 62}},
    {@"spotifyglass.metal.saturation", {0,  200, 10, 150}},
    {@"spotifyglass.metal.brightness", {40, 150, 5, 100}},
    // 构图两项。warp 与 coverScale 的默认值就是 SGRFluid.m 的标准值(100% / 1.0),
    // 范围沿用那边的档位,方便读过那边设置的人直接对上。
    {@"spotifyglass.metal.warp",       {0,  100, 5, 100}},
    {@"spotifyglass.metal.coverscale", {50, 200, 5, 100}},
};
enum { kSettingCount = sizeof(kSettings) / sizeof(kSettings[0]) };

NSNotificationName const SGRMetalSettingsDidChangeNotification = @"spotifyglass.metalSettingsDidChange";

SGRMetalLimits SGRMetalLimitsOf(SGRMetalSetting setting) {
    return kSettings[setting].limits;
}

NSInteger SGRMetalValue(SGRMetalSetting setting) {
    SGRMetalLimits l = kSettings[setting].limits;
    return MIN(l.most, MAX(l.least, SGInt(kSettings[setting].key, l.standard)));
}

void SGRSetMetalValue(SGRMetalSetting setting, NSInteger value) {
    SGRMetalLimits l = kSettings[setting].limits;
    SGSetInt(kSettings[setting].key, MIN(l.most, MAX(l.least, value)));
    dispatch_async(dispatch_get_main_queue(), ^{
        [NSNotificationCenter.defaultCenter postNotificationName:SGRMetalSettingsDidChangeNotification object:nil];
    });
}

void SGRResetMetalSettings(void) {
    for (int i = 0; i < kSettingCount; i++) {
        SGRMetalLimits l = kSettings[i].limits;
        SGSetInt(kSettings[i].key, l.standard);
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        [NSNotificationCenter.defaultCenter postNotificationName:SGRMetalSettingsDidChangeNotification object:nil];
    });
}

// ============================================================================
// 常量
// ============================================================================

// 频谱纹理: 256 x 2,与二进制一致。
static const NSUInteger kSpectrumWidth = 256, kSpectrumHeight = 2;
// 4 字节每像素,RGBA。命名而非在数组长度处展开:一个 static 数组按常量表达式定长时,
// clang 会把长度折进数组类型并按 GNU 扩展告警,而 -Werror 让它变成错误。
enum { kSpectrumBytes = kSpectrumWidth * kSpectrumHeight * 4 };
// 行0 的频段数;行1 的dB 级数。
static const float kBandsRow = 127.0f, kLevelsRow = 255.0f;
// Kawase ping-pong 的尺寸。半分辨率足够 —— 背景本来就是模糊的。
static const NSUInteger kBlurSide = 512;
// 没有分析结果时的电平(SGRSpectrumFloor)。
static const float kFloorDB = SGRSpectrumFloor;
// 归一化的最小跨度。顶端对齐由sg_peak 自适应完成 —— 见 +levelAt,所以安静的曲子
// 和响的曲子动得一样多。
static const float kRangeDB = 30.0f;
// 起落速度(秒)。快起慢落,与 PlayerVisualiser 的 kFrontUp/kFrontDown 同思路。
static const float kRise = 0.12f, kFall = 0.5f;
// 焦点缓动。0.14 是每帧的插值系数。
static const float kFocusEase = 0.14f;

#pragma mark - 频谱

// 平滑后的 24 个频段,映射到 0..1。
static float sg_levels[SGRSpectrumBands];
static float sg_peak = kFloorDB;

static void readSpectrum(void) {
    float db[SGRSpectrumBands];
    uint64_t stamp = SGRSpectrumRead(db);

    // 还没有分析(暂停,或 tap 没跑),让已有的电平自己落回底。
    static uint64_t last;
    if (stamp == last) {
        for (int i = 0; i < SGRSpectrumBands; i++) sg_levels[i] = MAX(kFloorDB, sg_levels[i] - 4.0f);
        return;
    }
    last = stamp;

    // 顶端缓慢回落,静音时保持平坦。
    float loudest = kFloorDB;
    for (int i = 0; i < SGRSpectrumBands; i++) loudest = MAX(loudest, db[i]);
    sg_peak = (loudest > sg_peak) ? loudest : MAX(loudest, sg_peak - 4.0f);

    // 起落:快起慢落
    float dt = 1.0f / 60.0f;
    for (int i = 0; i < SGRSpectrumBands; i++) {
        float target = db[i];
        float current = sg_levels[i];
        float rate = (target > current) ? kRise : kFall;
        sg_levels[i] = current + (target - current) * MIN(1.0f, dt / rate);
    }
}

// 24 个频段 -> 0..1 的归一化电平。
static float levelAt(float index) {
    int i = (int)(index * (SGRSpectrumBands - 1));
    i = MAX(0, MIN(SGRSpectrumBands - 1, i));
    float span = MAX(kRangeDB, sg_peak - kFloorDB);
    return MAX(0.0f, MIN(1.0f, (sg_levels[i] - (sg_peak - span)) / span));
}

#pragma mark - 视图

// accent's backing store is _coverAccent, not an auto-synthesised _accent: the setter is
// written by hand so it can push the colour into the uniform block and redraw, and the
// synthesised ivar would then sit unreferenced. @synthesize goes after the ivar block —
// a block declares ivars only.
@implementation SGRMetalVisualiser {
    id<MTLDevice> _device;
    id<MTLCommandQueue> _queue;

    id<MTLRenderPipelineState> _present;
    id<MTLRenderPipelineState> _down;
    id<MTLRenderPipelineState> _up;
    id<MTLRenderPipelineState> _composite;

    id<MTLSamplerState> _sampler;

    __strong id<MTLTexture> _cover;
    __strong id<MTLTexture> _previous;
    __strong id<MTLTexture> _spectrum;
    __strong id<MTLTexture> _text;
    __strong id<MTLTexture> _blurA;
    __strong id<MTLTexture> _blurB;

    SGRMetalUniforms _u;
    CGPoint _focus;      // 目标,0..1
    CGPoint _focusNow;   // 缓动后
    CGPoint _tilt;       // 0..1
    CFTimeInterval _start;
    CFTimeInterval _lastTick;
    NSInteger _frames;

    UIImage *_artwork;
    NSString *_artworkIdentity;
    NSArray<NSString *> *_lyrics;
    NSUInteger _textWanted;
    UIColor *_coverAccent;
    // 图层坐标里的可见区。CGRectZero 表示整块图层。
    CGRect _visibleRect;

    CADisplayLink *_link;
}

@synthesize accent = _coverAccent;

// 可见区变了要重画:副本的位置和压暗带都跟着它走。
- (void)setVisibleRect:(CGRect)rect {
    if (CGRectEqualToRect(rect, _visibleRect)) return;
    _visibleRect = rect;
    [self drawOnce];
}

+ (BOOL)isAvailable {
    static BOOL available;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        available = MTLCreateSystemDefaultDevice() != nil;
        if (!available) SGLog(@"metal visualiser: no Metal device, staying on the Core Animation field");
    });
    return available;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!SGRMetalVisualiser.isAvailable) return nil;

    _device = MTLCreateSystemDefaultDevice();
    if (!_device) return nil;
    _queue = [_device newCommandQueue];

    self = [super initWithFrame:frame device:_device];
    if (!self) return nil;

    [self configure];
    if (![self buildPipelines]) return nil;
    [self buildTextures];

    _start = CACurrentMediaTime();
    _focusNow = CGPointZero;

    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(settingsChanged)
                                               name:SGRMetalSettingsDidChangeNotification
                                             object:nil];
    return self;
}

- (void)dealloc {
    [_link invalidate];
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)settingsChanged {
    // 每帧读 NSUserDefaults 也不贵,但记下来便于日后加动画。
}

#pragma mark - 配置

- (void)configure {
    self.colorPixelFormat = MTLPixelFormatBGRA8Unorm;
    self.framebufferOnly = NO;
    self.clearColor = MTLClearColorMake(0, 0, 0, 1);
    self.opaque = YES;
    self.backgroundColor = UIColor.blackColor;
    self.paused = YES;
    self.enableSetNeedsDisplay = NO;
    self.preferredFramesPerSecond = 60;
    self.userInteractionEnabled = NO;
    self.opaque = YES;
}

// The tweak is a dylib injected into Spotify rather than a bundle with a .metallib beside it, so
// -newDefaultLibrary has nothing to find: it looks in the main bundle's resources. The shaders are
// linked into this image instead (see tweak/Makefile's -sectcreate), so the library is read out of
// this dylib. -newLibraryWithURL: on the image path is that; if the sect ever went missing it
// returns nil here and the caller falls back rather than crashing.
- (id<MTLLibrary>)loadShaderLibrary {
    id<MTLLibrary> library = [_device newDefaultLibrary];
    if (library) return library;

    Dl_info info;
    if (dladdr((__bridge const void *)self, &info) && info.dli_fname) {
        NSString *path = [NSString stringWithUTF8String:info.dli_fname];
        NSURL *url = [NSURL fileURLWithPath:path];
        NSError *err = nil;
        library = [_device newLibraryWithURL:url error:&err];
        if (library) return library;
        SGLog(@"metal visualiser: newLibraryWithURL failed: %@", err.localizedDescription);
    } else {
        SGLog(@"metal visualiser: dladdr found no path for the dylib");
    }
    return nil;
}

- (BOOL)buildPipelines {
    NSError *error = nil;
    id<MTLLibrary> library = [self loadShaderLibrary];
    if (!library) {
        SGLog(@"metal visualiser: no shader library — the .metallib did not link into the dylib");
        return NO;
    }

    NSArray<NSString *> *names = @[@"chromaPresentFragment", @"kawaseDownFragment", @"kawaseUpFragment", @"compositeFragment"];
    NSMutableArray *pipes = [NSMutableArray arrayWithCapacity:4];
    for (NSString *frag in names) {
        id<MTLFunction> vertex = [library newFunctionWithName:@"blitVertex"];
        if (![frag isEqualToString:@"chromaPresentFragment"]) {
            vertex = [library newFunctionWithName:@"blitVertex"];
        } else {
            vertex = [library newFunctionWithName:@"chromaPresentVertex"];
        }
        id<MTLFunction> fragment = [library newFunctionWithName:frag];
        if (!fragment) {
            SGLog(@"metal visualiser: missing %@", frag);
            return NO;
        }
        MTLRenderPipelineDescriptor *desc = [MTLRenderPipelineDescriptor new];
        desc.vertexFunction = vertex;
        desc.fragmentFunction = fragment;
        desc.colorAttachments[0].pixelFormat = self.colorPixelFormat;
        id<MTLRenderPipelineState> pipe = [_device newRenderPipelineStateWithDescriptor:desc error:&error];
        if (!pipe) {
            SGLog(@"metal visualiser: %@: %@", frag, error.localizedDescription);
            return NO;
        }
        [pipes addObject:pipe];
    }
    _present = pipes[0];
    _down = pipes[1];
    _up = pipes[2];
    _composite = pipes[3];

    MTLSamplerDescriptor *sd = [MTLSamplerDescriptor new];
    sd.minFilter = MTLSamplerMinMagFilterLinear;
    sd.magFilter = MTLSamplerMinMagFilterLinear;
    sd.mipFilter = MTLSamplerMipFilterLinear;
    sd.maxAnisotropy = 8;
    sd.sAddressMode = MTLSamplerAddressModeClampToEdge;
    sd.tAddressMode = MTLSamplerAddressModeClampToEdge;
    _sampler = [_device newSamplerStateWithDescriptor:sd];
    return _sampler != nil;
}

- (void)buildTextures {
    _spectrum = [self newTextureOfWidth:kSpectrumWidth height:kSpectrumHeight usage:MTLTextureUsageShaderRead];
    _text = [self newTextureOfWidth:512 height:512 usage:MTLTextureUsageShaderRead];
    _blurA = [self newTextureOfWidth:kBlurSide height:kBlurSide usage:MTLTextureUsageShaderRead | MTLTextureUsageRenderTarget];
    _blurB = [self newTextureOfWidth:kBlurSide height:kBlurSide usage:MTLTextureUsageShaderRead | MTLTextureUsageRenderTarget];
}

- (id<MTLTexture>)newTextureOfWidth:(NSUInteger)width
                              height:(NSUInteger)height
                              usage:(MTLTextureUsage)usage {
    MTLTextureDescriptor *desc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
                                                                                 width:width
                                                                                height:height
                                                                             mipmapped:NO];
    desc.usage = usage;
    desc.storageMode = MTLStorageModePrivate;
    return [_device newTextureWithDescriptor:desc];
}

// Uploads through a blit encoder. -contents is not declared on MTLTexture for iOS, so writing
// the bytes by hand is not an option here the way it is on macOS.
- (void)uploadBytes:(const uint8_t *)bytes
             length:(NSUInteger)length
          bytesPerRow:(NSUInteger)bytesPerRow
                width:(NSUInteger)width
               height:(NSUInteger)height
             toTexture:(id<MTLTexture>)texture {
    if (!bytes || !texture) return;
    id<MTLBuffer> staging = [_device newBufferWithBytes:bytes
                                                 length:length
                                                options:MTLResourceStorageModeShared];
    if (!staging) return;
    id<MTLCommandBuffer> cmd = [_queue commandBuffer];
    id<MTLBlitCommandEncoder> blit = [cmd blitCommandEncoder];
    [blit copyFromBuffer:staging
            sourceOffset:0
       sourceBytesPerRow:bytesPerRow
     sourceBytesPerImage:length
              sourceSize:MTLSizeMake(width, height, 1)
              toTexture:texture
        destinationSlice:0
         destinationLevel:0
        destinationOrigin:MTLOriginMake(0, 0, 0)];
    [blit endEncoding];
    [cmd commit];
}

// Clears the lyrics atlas. MTLBlitCommandEncoder has no fillRegion:...withBytes: on iOS, but it
// does have fillBuffer:range:value:, and a private texture is reached the same way as any other
// upload: copy a zeroed staging buffer into it.
- (void)fillTexture:(id<MTLTexture>)texture with:(uint32_t)pixel {
    if (!texture) return;
    uint8_t zero = (uint8_t)(pixel & 0xff);
    NSUInteger length = texture.width * texture.height * 4;
    uint8_t *bytes = calloc(1, length);
    if (!bytes) return;
    if (pixel) memset(bytes, zero, length);
    [self uploadBytes:bytes length:length bytesPerRow:texture.width * 4
                width:texture.width height:texture.height toTexture:texture];
    free(bytes);
}

#pragma mark - 封面

- (void)setArtwork:(UIImage *)image {
    if (image == _artwork) return;
    _artwork = image;

    if (!image) {
        _cover = nil;
        [self drawOnce];
        return;
    }

    // 缩到较小再上传:背景本就要模糊,省显存也省带宽。
    CGImageRef source = image.CGImage;
    if (!source) { [self drawOnce]; return; }

    NSUInteger side = MIN(MAX((NSUInteger)CGImageGetWidth(source), (NSUInteger)CGImageGetHeight(source)), 1024);
    id<MTLTexture> texture = [self newTextureOfWidth:side height:side usage:MTLTextureUsageShaderRead | MTLTextureUsageRenderTarget];
    if (!texture) { [self drawOnce]; return; }

    // 用 CoreGraphics 画到 4 字节像素,再 blit 上传。
    NSUInteger stride = side * 4;
    uint8_t *bytes = calloc(side * stride, 1);
    if (!bytes) { [self drawOnce]; return; }

    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(bytes, side, side, 8, stride, space,
                                             kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Host);
    if (ctx) {
        CGContextDrawImage(ctx, CGRectMake(0, 0, side, side), source);
        CGContextRelease(ctx);
    }
    CGColorSpaceRelease(space);

    [self uploadBytes:bytes length:side * stride bytesPerRow:stride
                width:side height:side toTexture:texture];
    free(bytes);

    _cover = texture;
    _previous = texture;

    // 配色: 用 Kit 已有的 flowColors,和播放页其他地方一致。
    [SGRPalette paletteForImage:image request:(SGRPaletteRequest){ .flow = YES } completion:^(SGRPalette *palette) {
        NSArray<UIColor *> *colors = palette.flowColors;
        for (NSUInteger i = 0; i < 3 && i < colors.count; i++) {
            CGFloat r, g, b, a;
            [colors[i] getRed:&r green:&g blue:&b alpha:&a];
            SGRSimd4 v = { r, g, b, 1.0f };
            if (i == 0) _u.color0 = v;
            else if (i == 1) _u.color1 = v;
            else _u.color2 = v;
        }
        // 强调色取最饱和的那个(PlayerField.x 的 followCover 同样判断)。
        UIColor *best = nil;
        CGFloat bestSat = -1;
        for (UIColor *color in colors) {
            CGFloat h, s, v2, a;
            if ([color getHue:&h saturation:&s brightness:&v2 alpha:&a] && s > bestSat) {
                best = color;
                bestSat = s;
            }
        }
        if (best) self.accent = best;
    }];

    [self drawOnce];
}

- (void)setAccent:(UIColor *)color {
    _coverAccent = color;
    if (color) {
        CGFloat r, g, b, a;
        [color getRed:&r green:&g blue:&b alpha:&a];
        _u.accent = (SGRSimd4){ r, g, b, 1.0f };
    }
    [self drawOnce];
}

#pragma mark - 歌词

- (void)setLyrics:(NSArray<NSString *> *)lines {
    _lyrics = lines;
    [self drawLyricsInto:_text];
    [self drawOnce];
}

// 歌词画进纹理: 白字 + alpha,composite 那一步按频段给它上光。
- (void)drawLyricsInto:(id<MTLTexture>)texture {
    if (!texture) return;

    NSUInteger w = texture.width, h = texture.height;
    NSUInteger stride = w * 4;
    uint8_t *bytes = calloc(h * stride, 1);
    if (!bytes) return;

    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(bytes, w, h, 8, stride, space,
                                             kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Host);
    if (ctx) {
        UIGraphicsPushContext(ctx);
        // 上面的坐标系原点在左下,而纹理采样时 y 翻转,所以这里从底部往上排。
        CGFloat size = 34.0;
        UIFont *font = [UIFont boldSystemFontOfSize:size];
        NSDictionary *attrs = @{
            NSFontAttributeName: font,
            NSForegroundColorAttributeName: UIColor.whiteColor,
        };
        CGFloat line = size * 1.6;
        CGFloat y = size;
        for (NSString *text in _lyrics) {
            [text drawAtPoint:CGPointMake(40, y) withAttributes:attrs];
            y += line;
            if (y > h) break;
        }
        UIGraphicsPopContext();
        CGContextRelease(ctx);
    }
    CGColorSpaceRelease(space);

    [self uploadBytes:bytes length:h * stride bytesPerRow:stride width:w height:h toTexture:texture];
    free(bytes);
}

#pragma mark - 交互

- (void)setFocusX:(CGFloat)x y:(CGFloat)y {
    _focus = CGPointMake(MIN(1, MAX(0, x)), MIN(1, MAX(0, y)));
}

- (void)resetFocus {
    _focus = CGPointZero;
}

- (void)setTiltX:(CGFloat)x y:(CGFloat)y {
    _tilt = CGPointMake(MIN(1, MAX(0, x)), MIN(1, MAX(0, y)));
}

- (void)setMoving:(BOOL)moving {
    if (_moving == moving) return;
    _moving = moving;
    if (moving) [self startLink];
    else [self stopLink];
}

- (void)setPreferredFPS:(NSInteger)fps {
    _preferredFPS = fps;
    _link.preferredFramesPerSecond = MIN(60, MAX(15, fps));
}

#pragma mark - 渲染循环

- (void)startLink {
    if (_link) {
        _link.paused = NO;
        return;
    }
    _link = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick:)];
    _link.preferredFramesPerSecond = MIN(60, MAX(15, _preferredFPS));
    [_link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    [_link setPaused:NO];
}

- (void)stopLink {
    _link.paused = YES;
}

- (void)tick:(CADisplayLink *)link {
    if (!self.window) return;
    [self drawOnce];
}

- (void)drawOnce {
    [self draw:self.bounds];
}

- (void)draw:(CGRect)rect {
    MTLRenderPassDescriptor *drawableRPD = self.currentRenderPassDescriptor;
    id<CAMetalDrawable> drawable = self.currentDrawable;
    if (!drawableRPD || !drawable) return;

    CGSize size = self.drawableSize;

    // 尺寸
    _u.resolution = (SGRSimd2){ (float)size.width, (float)size.height };

    // 可见区。图层比屏幕大(bleed),这一块是屏幕上真正看到的部分;副本绕它里面的点转、
    // 边长以它的长边为基准、压暗带在它下边收住。shader 用的是 uv,所以把 rect 除以图层尺寸。
    // 早先这里写死 (0,0,1,1),等于把整块画布当可见区 —— 于是"副本比屏幕大"这个前提消失了,
    // 构图比例全错,看着像被裁。
    CGRect visible = _visibleRect;
    if (CGRectIsEmpty(visible) || self.bounds.size.width < 1 || self.bounds.size.height < 1) {
        visible = self.bounds;
    }
    _u.visibleTopLeft = (SGRSimd2){ (float)(visible.origin.x / MAX(self.bounds.size.width, 1.0)),
                                    (float)(visible.origin.y / MAX(self.bounds.size.height, 1.0)) };
    _u.visibleSize    = (SGRSimd2){ (float)(visible.size.width  / MAX(self.bounds.size.width, 1.0)),
                                    (float)(visible.size.height / MAX(self.bounds.size.height, 1.0)) };

    // 焦点缓动
    _focusNow.x += (_focus.x - _focusNow.x) * kFocusEase;
    _focusNow.y += (_focus.y - _focusNow.y) * kFocusEase;
    _u.focus = (SGRSimd2){ _focusNow.x, _focusNow.y };
    _u.tilt = (SGRSimd2){ _tilt.x, _tilt.y };

    // 时间与帧数
    CFTimeInterval now = CACurrentMediaTime();
    if (_lastTick == 0) _lastTick = now;
    _lastTick = now;
    _u.time = (float)(now - _start);
    _frames++;

    // 设置项
    _u.flowAmount = SGRMetalValue(SGRMetalSettingFlow) / 100.0f;
    _u.audioAmount = SGRMetalValue(SGRMetalSettingAudio) / 100.0f;
    _u.edgeSmooth = SGRMetalValue(SGRMetalSettingBlur) / 100.0f * 0.5f;
    _u.saturation = SGRMetalValue(SGRMetalSettingSaturation) / 100.0f;
    _u.brightness = SGRMetalValue(SGRMetalSettingBrightness) / 100.0f;
    // zoom 已经不是构图的手段了 —— 副本的边长由 coverScale 定,这里是留给后续微调的余量,
    // 与 SGRFluid.m 一样默认 1。
    _u.zoom = 1.0f;
    _u.warp = SGRMetalValue(SGRMetalSettingWarp) / 100.0f;
    _u.coverScale = SGRMetalValue(SGRMetalSettingCoverScale) / 100.0f;
    // 压暗带:SGRFluid.m 的 kShadeFrom / kShadeAlpha。
    _u.shadeFrom = 0.45f;
    _u.shadeAlpha = 0.55f;
    _u.spectrumBands = SGRSpectrumBands;

    // 频谱上传
    readSpectrum();
    [self uploadSpectrum];

    id<MTLCommandBuffer> cmd = [_queue commandBuffer];

    // Pass 1 — 主渲染进 _blurA。不能直接写 drawable: Pass 3 还要往同一张
    // drawable 上合成歌词, 先写了就被后面那遍覆盖掉。
    if (_blurA) {
        MTLRenderPassDescriptor *desc = [MTLRenderPassDescriptor renderPassDescriptor];
        desc.colorAttachments[0].texture = _blurA;
        desc.colorAttachments[0].loadAction = MTLLoadActionClear;
        desc.colorAttachments[0].storeAction = MTLStoreActionStore;
        desc.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1);

        id<MTLRenderCommandEncoder> enc = [cmd renderCommandEncoderWithDescriptor:desc];
        [enc setRenderPipelineState:_present];
        [enc setFragmentTexture:_cover atIndex:0];
        [enc setFragmentTexture:_previous atIndex:1];
        [enc setFragmentTexture:_spectrum atIndex:2];
        [enc setFragmentBytes:&_u length:sizeof(_u) atIndex:0];
        // The shaders take the sampler as [[sampler(0)]]; a constexpr sampler cannot carry
        // max_anisotropy, so the host's MTLSamplerState is bound here instead.
        [enc setFragmentSamplerState:_sampler atIndex:0];
        [enc drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
        [enc endEncoding];
    }

    // Pass 2 — Kawase: _blurA -> _blurB(降) -> _blurA(升)
    if (_blurA && _blurB) {
        for (NSUInteger pass = 0; pass < 2; pass++) {
            id<MTLTexture> src = pass == 0 ? _blurA : _blurB;
            id<MTLTexture> dst = pass == 0 ? _blurB : _blurA;
            id<MTLRenderPipelineState> pipe = pass == 0 ? _down : _up;

            MTLRenderPassDescriptor *desc = [MTLRenderPassDescriptor renderPassDescriptor];
            desc.colorAttachments[0].texture = dst;
            desc.colorAttachments[0].loadAction = MTLLoadActionClear;
            desc.colorAttachments[0].storeAction = MTLStoreActionStore;
            desc.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1);

            id<MTLRenderCommandEncoder> enc = [cmd renderCommandEncoderWithDescriptor:desc];
            [enc setRenderPipelineState:pipe];
            [enc setFragmentTexture:src atIndex:0];
            SGRSimd2 srcSize = { (float)src.width, (float)src.height };
            [enc setFragmentBytes:&srcSize length:sizeof(srcSize) atIndex:0];
            [enc setFragmentSamplerState:_sampler atIndex:0];
            [enc drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
            [enc endEncoding];
        }
    }

    // Pass 3 — 模糊结果 + 歌词 -> 屏幕
    {
        id<MTLRenderCommandEncoder> enc = [cmd renderCommandEncoderWithDescriptor:drawableRPD];
        [enc setRenderPipelineState:_composite];
        [enc setFragmentTexture:_blurA atIndex:0];
        [enc setFragmentTexture:_text atIndex:1];
        [enc setFragmentTexture:_spectrum atIndex:2];
        [enc setFragmentBytes:&_u length:sizeof(_u) atIndex:0];
        [enc setFragmentSamplerState:_sampler atIndex:0];
        [enc drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
        [enc endEncoding];
    }

    [cmd presentDrawable:drawable];
    [cmd commit];

    _lastTick = now;
}

#pragma mark - 频谱纹理

// 256 x 2:行0 是 24 个频段映射到 127 档,行1 是 dB 级映射到 255 档。
- (void)uploadSpectrum {
    if (!_spectrum) return;

    static uint8_t bytes[kSpectrumBytes];
    memset(bytes, 0, sizeof(bytes));

    for (NSUInteger x = 0; x < 128; x++) {
        float t = (float)x / (float)(kBandsRow);
        float value = levelAt(t);
        uint8_t v = (uint8_t)(MAX(0.0f, MIN(1.0f, value)) * 255.0f);
        bytes[x * 4 + 0] = v;
        bytes[x * 4 + 1] = v;
        bytes[x * 4 + 2] = v;
        bytes[x * 4 + 3] = 255;
    }

    for (NSUInteger x = 0; x < kSpectrumWidth; x++) {
        float t = (float)x / (float)(kLevelsRow);
        // 行1 是一条缓升的曲线,给 shader 一个整体响度的参考。
        float shaped = powf(MAX(0.0f, MIN(1.0f, t)), 1.0f / 2.2f) * levelAt(0.5f);
        uint8_t v = (uint8_t)(shaped * 255.0f);
        NSUInteger off = kSpectrumWidth * 4 + x * 4;
        bytes[off + 0] = v;
        bytes[off + 1] = v;
        bytes[off + 2] = v;
        bytes[off + 3] = 255;
    }

    [self uploadBytes:bytes length:sizeof(bytes) bytesPerRow:kSpectrumWidth * 4
                width:kSpectrumWidth height:kSpectrumHeight toTexture:_spectrum];
}

@end
