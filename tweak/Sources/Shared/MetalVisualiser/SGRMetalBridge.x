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
#import "Shared/MetalVisualiser/SGRMetalVisualiser.h"

static char kMetalKey;
static __weak SGRMetalVisualiser *sg_metal;

// Metal 可用且被选中时才建。
BOOL SGRMetalBridgeWanted(void) {
    return SGRPlayerBackground() == SGRPlayerBackgroundVisualiser && SGRMetalVisualiser.isAvailable;
}

// 平面就位后调用。返回挂上的视图,没挂返回 nil。
UIView *SGRMetalBridgeAttach(UIView *plane) {
    if (!plane || plane.bounds.size.height < 200) return nil;

    SGRMetalVisualiser *existing = objc_getAssociatedObject(plane, &kMetalKey);
    if (existing) return existing;
    if (!SGRMetalBridgeWanted()) return nil;

    SGRMetalVisualiser *metal = [[SGRMetalVisualiser alloc] initWithFrame:plane.bounds];
    if (!metal) {
        SGLog(@"metal bridge: no device, the Core Animation visualiser keeps the background");
        return nil;
    }

    metal.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    metal.userInteractionEnabled = NO;
    [plane addSubview:metal];

    objc_setAssociatedObject(plane, &kMetalKey, metal, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    sg_metal = metal;

    // 第一张封面现在就给,免得开屏几帧是黑的。
    UIImage *cover = SGRNowPlayingArtwork(NULL, NULL);
    if (cover) [metal setArtwork:cover];

    // Fluid 的四层旋转让位:Metal 版自己就是背景。
    SGRArtworkField *field = SGRPlayerField();
    field.fluid = NO;
    field.flows = NO;

    SGLog(@"metal bridge: visualiser in on the player plane %.0fx%.0f, artwork %@",
          plane.bounds.size.width, plane.bounds.size.height, cover ? @"ready" : @"not read yet");
    return metal;
}

// 切歌 / 封面更新。走SGRPlayerField 的同一个钩子(PlayerField.x 的 publishCover)。
void SGRMetalBridgeSetArtwork(UIImage *artwork) {
    [sg_metal setArtwork:artwork];
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