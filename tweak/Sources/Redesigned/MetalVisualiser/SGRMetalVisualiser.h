// SGRMetalVisualiser.h
//
// Metal 视觉器:一个 MTKView,绘制流体扭曲 + Kawase 模糊的封面背景。
//
// 移植自 spoti.pw 0.51.0-beta.1 的二进制规格 —— 4 条 pipeline(kawase/blend/warp/tint)、
// Frame uniform(resolution/focus/tilt/color0_1_2_/accent)、256x2 频谱纹理、
// 流体径向扭曲数学。着色器在 SGRMetalShaders.metal。
//
// 与 Redesigned/Player/PlayerVisualiser.m(Core Animation 的山丘)并列,
// 由 PlayerField.x 在背景种类选到 Visualizer 时挂上。频谱走 SGRSpectrum ——
// 那是 Spotify 自己的输出,不用外部音频 tap。
//
// Threading: 主线程。
#import <UIKit/UIKit.h>
#import <MetalKit/MetalKit.h>
// MetalKit pulls in the view and the pipeline state, but not the command buffer, blit encoder or
// render command encoder protocols — their selectors (setFragmentTexture:index:,
// copyFromBuffer:…, fillRegion:…) live in these headers, so without them every call below reads
// as an unknown selector on a bare id.
#import <Metal/Metal.h>

NS_ASSUME_NONNULL_BEGIN

/// 设置项。与 SGRFluid 的五项对齐,外加音频反应度。
typedef NS_ENUM(NSInteger, SGRMetalSetting) {
    SGRMetalSettingFlow,          ///< 径向流动强度,百分比
    SGRMetalSettingAudio,         ///< 音频驱动强度,百分比
    SGRMetalSettingBlur,          ///< Kawase 迭代深度换算出的强度,百分比
    SGRMetalSettingSaturation,    ///< 饱和度,百分比
    SGRMetalSettingBrightness,    ///< 亮度,百分比
    SGRMetalSettingWarp,          ///< 副本分布的张开程度,百分比(SGRFluid.m 的 Warp)
    SGRMetalSettingCoverScale,    ///< 副本边长占可见区长边的倍数,百分比(SGRFluid.m 的 Warp 也管这个的一半)
    SGRMetalSettingCount
};

typedef struct { NSInteger least, most, step, standard; } SGRMetalLimits;

SGRMetalLimits SGRMetalLimitsOf(SGRMetalSetting setting);
NSInteger SGRMetalValue(SGRMetalSetting setting);
/// 存下并通知;变更会立刻作用到所有层。
void SGRSetMetalValue(SGRMetalSetting setting, NSInteger value);
void SGRResetMetalSettings(void);

extern NSNotificationName const SGRMetalSettingsDidChangeNotification;

/// 视觉器视图。铺满播放器背景平面即可。
@interface SGRMetalVisualiser : MTKView

/// 封面。同一张图重复设置是空操作。
- (void)setArtwork:(nullable UIImage *)image;

/// 歌词,直接渲染进 Metal 管线(不是 UILabel),所以能随节拍发光。
- (void)setLyrics:(nullable NSArray<NSString *> *)lines;

/// 焦点。播放器手势转发过来;触摸位置转 [0,1]。
- (void)setFocusX:(CGFloat)x y:(CGFloat)y;
- (void)resetFocus;

/// 倾斜,来自陀螺仪或头动,各 [0,1]。无输入时留 0.5(中位)。
- (void)setTiltX:(CGFloat)x y:(CGFloat)y;

/// 播放中转动,暂停时停住(与 SGRFluid 的 moving 同义)。
@property (nonatomic, assign) BOOL moving;

/// 强调色。取自封面;nil 时用封面的平均色。
@property (nonatomic, strong, nullable) UIColor *accent;

/// 帧率。歌词页降到 30,与PlayerVisualiser 的做法一致。
@property (nonatomic, assign) NSInteger preferredFPS;

/// 屏幕上真正可见的那一块,图层自己的坐标。图层比屏幕大(bleed),副本要绕这块里的点转、
/// 压暗带在这块的下边收住,所以副本的边长也以这块的长边为基准 —— 与 SGRFluidLayer 的
/// visibleRect 同义。默认整块图层。
@property (nonatomic, assign) CGRect visibleRect;

/// Metal 设备不可用时为 NO,调用方回退到 Core Animation 的实现。
@property (class, nonatomic, readonly) BOOL isAvailable;

@end

NS_ASSUME_NONNULL_END