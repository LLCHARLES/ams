#import <UIKit/UIKit.h>

// Main-thread playback owner. The hero owns placement, appearance and visibility.
@interface SGRHeaderClip : NSObject
- (instancetype)initWithFile:(NSURL *)file appearance:(void (^)(BOOL shown, BOOL entrance))appearance;
@property (nonatomic, readonly) NSURL *file;
@property (nonatomic, readonly) CALayer *layer;
- (void)setFrame:(CGRect)frame;
- (void)invalidate;
- (void)updateVisible:(BOOL)visible active:(BOOL)active mayPlay:(BOOL)mayPlay;
@end

// UIKit's completed appearance, including that of a containing controller. A
// view can still have a window and a perfectly visible rect underneath a push.
@interface SGRHeaderPage : NSObject
- (instancetype)initWithRefresh:(dispatch_block_t)refresh;
- (void)bindHeader:(UIView *)header;
- (BOOL)visibleInViewport:(BOOL)inViewport;
@end
void SGRHeaderPageDidAppear(UIViewController *owner, BOOL appeared);
void SGRHeaderPageWillDisappear(UIViewController *owner);
