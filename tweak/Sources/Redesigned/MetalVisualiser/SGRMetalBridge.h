// SGRMetalBridge.h
//
// 桥接层对外只暴露 C 函数,所以声明单独放在这里 —— Logos 的 .x 不能被 import,
// PlayerField.x 要用它就得有这么一个头。

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// Metal 版是否应当接管背景:Metal 可用,且背景档位正是 Visualizer。
BOOL SGRMetalBridgeWanted(void);

// 把视觉器挂进播放器背景平面,并让它跟随该平面的尺寸。返回挂上去的视图,
// 未接管时为 nil。
UIView *_Nullable SGRMetalBridgeAttach(UIView *plane);

// The part of the layer on screen: the copies are placed and the shade ends against it, while the
// layer itself bleeds past the bounds. SGRField.m's layoutSubviews sets SGRFluidLayer.visibleRect
// the same way — a layer the size of the screen has no room to bleed into.
void SGRMetalBridgeSetVisibleRect(CGRect rect);

// 每帧更新:读播放状态、频谱与歌词,决定要不要走链路。
void SGRMetalBridgeUpdate(void);

// 当前曲目封面变化时交给视觉器。
void SGRMetalBridgeSetArtwork(UIImage *_Nullable artwork);

// 歌词行变化。空数组表示没有歌词。
void SGRMetalBridgeSetLyrics(NSArray<NSString *> *_Nullable lines);

// 焦点:拖动封面时画面跟着流动。bounds 是平面尺寸,用来把触点换算成 uv。
void SGRMetalBridgeFocusAt(CGPoint point, CGRect bounds);
void SGRMetalBridgeResetFocus(void);

// 陀螺仪倾斜。
void SGRMetalBridgeTilt(CGFloat x, CGFloat y);

NS_ASSUME_NONNULL_END