// SGRMetalBridge.x
//
// 把 Metal 视觉器挂进播放器的背景平面。Visualizer 那一档在 Metal 可用时由它接管,
// 不可用时原样留给 PlayerVisualiser.m 的 Core Animation 山丘 —— 枚举不动,菜单不动。
//
// 挂在fieldIn() 建好 SGRArtworkField 之后: 同一档位下 Metal 版是 SGRArtworkField 的
// 同级兄弟,铺在同一块平面上,压在field 之上、Spotify 自己的渐变之下。
// Fluid 的四层旋转在这里关掉 —— Metal 版自己就是那层背景,不需要再叠一层。
//
// 频谱: 读 SGRSpectrum(Spotify 自己的输出),不碰音频 tap。歌词页降到 30fps,与
// PlayerVisualiser.m 同节流;暂停、低电量、Reduce Motion 时停链。
//
// Threading: 主线程。
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Redesigned/Kit/SGRBridges.h"
#import "Redesigned/Kit/SGRField.h"
#import "Redesigned/Player/Player.h"
#import "Redesigned/Player/SGRSpectrum.h"
#import "Shared/Player/PlayerState.h"
#import "Redesigned/MetalVisualiser/SGRMetalVisualiser.h"
// 自己也在实现里import:头文件是这些声明的唯一来源,不一致时编译器会当场报冲突,
// 而不是等到调用方的 .o 里才炸。
#import "Redesigned/MetalVisualiser/SGRMetalBridge.h"

static char kMetalKey;
static __weak SGRMetalVisualiser *sg_metal;

// Metal 可用且被选中时才建。
BOOL SGRMetalBridgeWanted(void) {
    return SGRPlayerBackground() == SGRPlayerBackgroundVisualiser && SGRMetalVisualiser.isAvailable;
}

// Past the plane's edges: above for the pull that dismisses the player, below for the bounce at the end
// of the cards. The same insets PlayerField.x gives SGRArtworkField.bleed, so the Metal field bleeds
// where the Core Animation one does — its copies need somewhere to turn that the screen does not show.
static const UIEdgeInsets kBleed = {200, 0, 600, 0};

// 平面就位后调用。返回挂上的视图,没挂返回 nil。
UIView *SGRMetalBridgeAttach(UIView *plane) {
    if (!plane || plane.bounds.size.height < 200) return nil;

    SGRMetalVisualiser *existing = objc_getAssociatedObject(plane, &kMetalKey);
    if (existing) return existing;
    if (!SGRMetalBridgeWanted()) return nil;

    CGRect bounds = plane.bounds;
    CGRect painted = CGRectMake(-kBleed.left, -kBleed.top,
                                bounds.size.width + kBleed.left + kBleed.right,
                                bounds.size.height + kBleed.top + kBleed.bottom);
    SGRMetalVisualiser *metal = [[SGRMetalVisualiser alloc] initWithFrame:painted];
    if (!metal) {
        SGLog(@"metal bridge: no device, the Core Animation visualiser keeps the background");
        return nil;
    }

    metal.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    metal.userInteractionEnabled = NO;
    metal.clipsToBounds = NO;
    [plane addSubview:metal];

    objc_setAssociatedObject(plane, &kMetalKey, metal, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    sg_metal = metal;

    // 可见区:屏幕上真正看到的那一块。图层比它大,副本要绕着屏幕内的点转、压暗带要在屏幕
    // 底边收住 —— 都以这块为准,和 SGRField.m 给 SGRFluidLayer.visibleRect 的做法一致。
    // 少了这一层,副本就只能按整块画布算,构图比例会错(看起来像被裁)。
    SGRMetalBridgeSetVisibleRect(CGRectMake(kBleed.left, kBleed.top, bounds.size.width, bounds.size.height));

    // 第一张封面现在就给,免得开屏几帧是黑的。
    UIImage *cover = SGRNowPlayingArtwork(NULL, NULL);
    if (cover) [metal setArtwork:cover];

    // Fluid 的四层旋转让位:Metal 版自己就是背景。
    SGRArtworkField *field = SGRPlayerField();
    field.fluid = NO;
    field.flows = NO;

    SGLog(@"metal bridge: visualiser on %.0fx%.0f bleeding to %.0fx%.0f, artwork %@",
          painted.size.width, painted.size.height, bounds.size.width, bounds.size.height,
          cover ? @"ready" : @"not read yet");
    return metal;
}

// 切歌 / 封面更新。走SGRPlayerField 的同一个钩子(PlayerField.x 的 publishCover)。
void SGRMetalBridgeSetArtwork(UIImage *artwork) {
    [sg_metal setArtwork:artwork];
}

// 可见区。图层比屏幕大,这一块是屏幕上真正看到的部分;副本的边长基准、旋转中心和压暗带
// 终点都以它为准。plane 的高度随播放器滚动变化,所以每次 Update 都重算一遍。
void SGRMetalBridgeSetVisibleRect(CGRect rect) {
    [sg_metal setVisibleRect:rect];
}

// 图层随plane 走:bleed 后仍比plane大一圈,可见区跟着 plane 的尺寸。
static void trackPlane(SGRMetalVisualiser *metal) {
    UIView *plane = metal.superview;
    if (!plane) return;
    CGRect bounds = plane.bounds;
    CGRect painted = CGRectMake(-kBleed.left, -kBleed.top,
                                bounds.size.width + kBleed.left + kBleed.right,
                                bounds.size.height + kBleed.top + kBleed.bottom);
    if (!CGRectEqualToRect(metal.frame, painted)) metal.frame = painted;
    SGRMetalBridgeSetVisibleRect(CGRectMake(kBleed.left, kBleed.top, bounds.size.width, bounds.size.height));
}

// 歌词。歌词页开着时降帧 —— 山丘那条链也是这么做的。
void SGRMetalBridgeSetLyrics(NSArray<NSString *> *lines) {
    SGRMetalVisualiser *metal = sg_metal;
    if (!metal) return;
    [metal setLyrics:lines];
    // 歌词页的链有它自己的一条,山丘那条降到 30fps;这里跟着。
    metal.preferredFPS = lines.count > 0 ? 30 : 60;
}

// 播放状态。暂停、低电量、Reduce Motion 都停下来;同 PlayerVisualiser.m 的条件。
void SGRMetalBridgeUpdate(void) {
    SGRMetalVisualiser *metal = sg_metal;
    if (!metal) return;

    if (!SGRMetalBridgeWanted()) {
        metal.hidden = YES;
        metal.moving = NO;
        return;
    }
    metal.hidden = NO;
    trackPlane(metal);

    BOOL inWindow = metal.window != nil;
    BOOL playing = !SGPlayerState().isPaused;
    BOOL lowPower = NSProcessInfo.processInfo.isLowPowerModeEnabled;
    BOOL reduceMotion = UIAccessibilityIsReduceMotionEnabled();

    metal.moving = inWindow && playing && !lowPower && !reduceMotion;
    // Reduce Motion 15fps,与 PlayerVisualiser.m 的节流一致。
    metal.preferredFPS = reduceMotion ? 15 : 60;

    if (metal.moving) {
        UIImage *cover = SGRNowPlayingArtwork(NULL, NULL);
        if (cover) [metal setArtwork:cover];
    }
}

// 播放器的触摸手势转发成焦点:按住封面拖动,背景跟着流。
void SGRMetalBridgeFocusAt(CGPoint point, CGRect bounds) {
    [sg_metal setFocusX:bounds.size.width > 0 ? point.x / bounds.size.width : 0
                      y:bounds.size.height > 0 ? point.y / bounds.size.height : 0];
}

void SGRMetalBridgeResetFocus(void) {
    [sg_metal resetFocus];
}

// 陀螺仪 / 头动的倾斜。CoreMotion 由Kit 统一管,这里只收归一化后的值。
void SGRMetalBridgeTilt(CGFloat x, CGFloat y) {
    [sg_metal setTiltX:x y:y];
}