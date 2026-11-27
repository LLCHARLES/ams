// UIKit owns the stack, transition cancellation, appearance callbacks, tab and modal hierarchy.
// No replacement SGAppWindow/SGTopController and no calls into accent refresh/transition APIs.
#import <UIKit/UIKit.h>
#import "Core/SGPrefs.h"
#import "Core/SGTopController.h"
#import "Redesigned/Kit/SGRAccent.h"
#import "Redesigned/Kit/SGRPalette.h"
#import "Redesigned/Kit/SGRBridges.h"
#import "../harness-fail.h"
NSNotificationName const SGRNowPlayingArtworkDidChangeNotification = @"harness.artwork";
NSNotificationName const SGRFieldColorDidChangeNotification = @"harness.field";
BOOL SGRedesignedUI(void) { return YES; }
SPTPlayerState *SGPlayerState(void) { return nil; }
NSString *SGURIString(id uri) { return nil; }
void SGAddPlayerStateObserver(id<SGPlayerStateObserver> observer) {}
UIImage *SGRNowPlayingArtwork(NSString **track,NSString **identity) { return nil; }
@implementation SGRPalette
+ (void)paletteForImage:(UIImage *)image request:(SGRPaletteRequest)request completion:(void (^)(SGRPalette *))completion { HARNESS_FAIL(@"unexpected artwork"); }
+ (void)tintForImage:(UIImage *)image surface:(UIColor *)surface strong:(BOOL)strong completion:(void (^)(UIColor *))completion { HARNESS_FAIL(@"unexpected tint"); }
@end
static NSUInteger checks;
static void expect(BOOL ok,NSString *what) { checks++; if (!ok) HARNESS_FAIL(@"%@",what); }
static void accent(NSInteger want,NSString *what) {
    checks++; if (SGRAccentRGB()!=want) HARNESS_FAIL(@"%@: got #%06lX expected #%06lX",what,(long)SGRAccentRGB(),(long)want);
}
// Checks start only after UIKit delivers the actual appearance. The production base-class hook
// runs through super; its queued refresh precedes the test's continuation.
@interface AppearancePage : UIViewController
@property (nonatomic,copy) void (^appeared)(void);
@end
@implementation AppearancePage
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (self.appeared) dispatch_async(dispatch_get_main_queue(),self.appeared);
}
@end
@interface NavigationScene : UIResponder <UIWindowSceneDelegate,UINavigationControllerDelegate,UIViewControllerAnimatedTransitioning>
@property (nonatomic,strong) UIWindow *window;
@property (nonatomic,strong) UITabBarController *tabs;
@property (nonatomic,strong) UINavigationController *nav;
@property (nonatomic,strong) AppearancePage *a,*b,*other;
@property (nonatomic,strong) UIPercentDrivenInteractiveTransition *interaction;
@end
@implementation NavigationScene
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    [NSUserDefaults.standardUserDefaults setVolatileDomain:@{SGRKeyAccentAuto:@YES,SGRKeyAccent:@0x123456} forName:NSArgumentDomain];
    SGPrefsChanged();
    self.a=[AppearancePage new]; self.b=[AppearancePage new]; self.other=[AppearancePage new];
    SGRAccentPublishPageColor(self.a.view,UIColor.yellowColor);
    SGRAccentPublishPageColor(self.b.view,UIColor.whiteColor);
    SGRAccentPublishPageColor(self.other.view,UIColor.cyanColor);
    self.nav=[[UINavigationController alloc] initWithRootViewController:self.a]; self.nav.delegate=self;
    self.tabs=[UITabBarController new]; self.tabs.viewControllers=@[self.nav,self.other];
    self.window=[[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene]; self.window.rootViewController=self.tabs;
    self.a.appeared=^{
        self.a.appeared=nil;
        accent(0xFFFF00,@"root appearance selects A");
        self.b.appeared=^{
            self.b.appeared=nil;
            accent(0xFFFFFF,@"push lifecycle selects B without color publication");
            self.interaction=[UIPercentDrivenInteractiveTransition new];
            self.b.appeared=^{ [self afterCancel]; };
            [self.nav popViewControllerAnimated:YES];
            [self.interaction updateInteractiveTransition:.4];
            // A's late color during the actual interactive transition must not take ownership.
            SGRAccentPublishPageColor(self.a.view,UIColor.cyanColor);
            accent(0xFFFFFF,@"interactive pop holds committed B");
            [self.interaction cancelInteractiveTransition];
        };
        [self.nav pushViewController:self.b animated:NO];
    };
    [self.window makeKeyAndVisible];
}
- (id<UIViewControllerAnimatedTransitioning>)navigationController:(UINavigationController *)navigationController animationControllerForOperation:(UINavigationControllerOperation)operation fromViewController:(UIViewController *)from toViewController:(UIViewController *)to {
    return operation==UINavigationControllerOperationPop && self.interaction ? self : nil;
}
- (id<UIViewControllerInteractiveTransitioning>)navigationController:(UINavigationController *)nav interactionControllerForAnimationController:(id<UIViewControllerAnimatedTransitioning>)animator { return self.interaction; }
- (NSTimeInterval)transitionDuration:(id<UIViewControllerContextTransitioning>)context { return .2; }
- (void)animateTransition:(id<UIViewControllerContextTransitioning>)context {
    UIView *from=[context viewForKey:UITransitionContextFromViewKey], *to=[context viewForKey:UITransitionContextToViewKey];
    to.frame=context.containerView.bounds; [context.containerView insertSubview:to belowSubview:from];
    [UIView animateWithDuration:[self transitionDuration:context] animations:^{ from.transform=CGAffineTransformMakeTranslation(from.bounds.size.width,0); }
        completion:^(BOOL finished) {
            from.transform=CGAffineTransformIdentity;
            [context completeTransition:!context.transitionWasCancelled];
        }];
}
- (void)afterCancel {
    self.b.appeared=nil; self.interaction=nil;
    expect(self.nav.topViewController==self.b,@"UIKit cancelled the pop");
    expect(SGTopControllerInWindow(self.window,nil,nil)==self.b,@"production traversal sees restored B");
    accent(0xFFFFFF,@"cancel completion keeps B");
    self.other.appeared=^{
        self.other.appeared=nil;
        expect(SGTopControllerInWindow(self.window,nil,nil)==self.other,@"production traversal sees selected tab");
        accent(0x00FFFF,@"tab lifecycle selects other page");
        self.b.appeared=^{
            self.b.appeared=nil;
            accent(0xFFFFFF,@"tab return selects B");
            AppearancePage *player=[AppearancePage new]; player.modalPresentationStyle=UIModalPresentationFullScreen;
            __weak AppearancePage *weakPlayer=player;
            player.appeared=^{
                AppearancePage *shown=weakPlayer; shown.appeared=nil;
                expect(SGTopControllerInWindow(self.window,nil,nil)==shown,@"production traversal sees presented player");
                accent(0x123456,@"player without artwork uses picked fallback, not underlying B");
                self.b.appeared=^{
                    self.b.appeared=nil;
                    accent(0xFFFFFF,@"modal dismissal restores B");
                    printf("accent navigation: %lu checks passed\n",(unsigned long)checks); exit(0);
                };
                [shown dismissViewControllerAnimated:NO completion:nil];
            };
            [self.b presentViewController:player animated:NO completion:nil];
        };
        self.tabs.selectedIndex=0;
    };
    self.tabs.selectedIndex=1;
}
@end
@interface NavigationApp : UIResponder <UIApplicationDelegate> @end
@implementation NavigationApp @end
int main(int argc,char **argv) {
    @autoreleasepool {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,120*NSEC_PER_SEC),dispatch_get_main_queue(),^{HARNESS_FAIL(@"navigation harness timed out");});
        return UIApplicationMain(argc,argv,nil,NSStringFromClass(NavigationApp.class));
    }
}
