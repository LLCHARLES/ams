// Run the compact transition against UIKit, with the card and player supplied by the harness.
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import "../harness-fail.h"

static __weak UIView *sg_card, *sg_barArt, *sg_cover;

CGRect SGRNowPlayingCardFrameIn(UIView *host, CGFloat *radius) {
    if (!sg_card.window) return CGRectNull;
    if (radius) *radius = 24;
    return [host convertRect:sg_card.bounds fromView:sg_card];
}
CGRect SGRNowPlayingArtworkFrameIn(UIView *host, CGFloat *radius) {
    if (!sg_barArt.window) return CGRectNull;
    if (radius) *radius = sg_barArt.layer.cornerRadius;
    return [host convertRect:sg_barArt.bounds fromView:sg_barArt];
}
CGRect SGRPlayerCoverFrameIn(UIView *host) {
    return sg_cover.window ? [host convertRect:sg_cover.bounds fromView:sg_cover] : CGRectNull;
}
void SGRPlayerSetCoverHidden(BOOL hidden) { sg_cover.alpha = hidden ? 0 : 1; }
CGFloat SGRPlayerCoverScale(void) { return 1; }
BOOL SGRPlayerMotionShowing(void) { return NO; }
BOOL SGRPlayerCoverHidden(void) { return NO; }
id SGRPlayerField(void) { return nil; }
BOOL SGRPlayerBackdropShowing(void) { return NO; }
UIImage *SGRNowPlayingArtwork(NSString **uri, NSString **identity) { return nil; }
const CGFloat SGRRadiusArtwork = 12;
BOOL SGRReduceMotion(void) { return NO; }
BOOL SGRedesignedUI(void) { return YES; }
BOOL SGHidden(NSString *key) { return getenv("MORPH_MUSIC") && strcmp(getenv("MORPH_MUSIC"), "1") == 0; }

#import "compact.inc"

@interface AppDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end
@implementation AppDelegate
- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)options {
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController = [UIViewController new];
    [self.window makeKeyAndVisible];
    runCompactChecks(self.window);
    return YES;
}
@end

int main(int argc, char **argv) {
    @autoreleasepool { return UIApplicationMain(argc, argv, nil, NSStringFromClass(AppDelegate.class)); }
}
