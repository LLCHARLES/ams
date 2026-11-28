// The field reports in window coordinates. The morph owns that transform and can change it
// without a layout, just as the display-link follower does after UIKit completes the open.
#import <UIKit/UIKit.h>
#import "Redesigned/Kit/SGRRestyle.h"
#import "Redesigned/Kit/SGRBackdropInk.h"
#import "harness-fail.h"

void SGRBackdropInkSetSource(UIView *source) {}

static BOOL landscapeCovers;
static BOOL SGRPlayerLandscapeCovers(UIWindow *window) { return landscapeCovers; }

static UIView *screen;
static CGRect drawn;
@interface SGRArtworkField : UIView
@property (nonatomic) BOOL offscreen;
@end
@implementation SGRArtworkField
- (UIWindow *)window { return (UIWindow *)screen; }
- (CGRect)convertRect:(CGRect)rect toView:(UIView *)view { return drawn; }
@end

@interface SGRPlayerMorph : NSObject
- (void)follow;
- (void)tearDown;
@end
@implementation SGRPlayerMorph
- (void)follow { drawn = CGRectMake(21, 0, 360, 782.687); }
- (void)tearDown { drawn = screen.bounds; }
@end

// Replaced by progress-check.sh with the production cache and its Logos hooks.
FIELD_GEOMETRY

int main(void) { @autoreleasepool {
    FIELD_INIT
    screen = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 402, 874)];
    SGRArtworkField *field = [[SGRArtworkField alloc] initWithFrame:screen.bounds];
    sg_field = field;
    CGRect mini = CGRectMake(27, 781, 348, 2);
    __block BOOL covered = NO;
    [NSNotificationCenter.defaultCenter addObserverForName:SGRPlayerVisibilityDidChangeNotification object:nil queue:nil
                                               usingBlock:^(NSNotification *note) {
        covered = CGRectContainsRect(SGRSettledPlayerRect((UIWindow *)screen), mini);
    }];
    SGRPlayerMorph *morph = [SGRPlayerMorph new];
    [morph follow];
    sg_appeared = YES;
    visibilityChanged(); // didAppear; the coordinator finishes while the follower is still running
    HARNESS_CHECK(!covered);
    [morph tearDown];
    HARNESS_CHECK(covered); // no later layout or touch, and no second run-loop turn
    landscapeCovers = YES;
    visibilityChanged();
    HARNESS_CHECK(field.offscreen);
    landscapeCovers = NO;
    visibilityChanged();
    HARNESS_CHECK(!field.offscreen);
    puts("settled field: covered mini notified after the late opening morph");
    return 0;
} }
