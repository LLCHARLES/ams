#import <UIKit/UIKit.h>
#import "../reduce-motion-fixture.h"
#import <objc/runtime.h>
#import "Redesigned/Navigation/PageZoom.h"
#import "../harness-fail.h"

BOOL SGRedesignedUI(void) { return YES; }
BOOL SGFlag(NSString *key, BOOL fallback) {
    id value = [NSUserDefaults.standardUserDefaults objectForKey:key];
    return value ? [value boolValue] : fallback;
}
void SGRequireClasses(NSArray *names) {
    for (NSString *name in names) HARNESS_CHECK(NSClassFromString(name));
}

@interface EdgeGesture : UIScreenEdgePanGestureRecognizer
@property (nonatomic) UIGestureRecognizerState reportedState;
@end
@implementation EdgeGesture
- (UIGestureRecognizerState)state { return self.reportedState; }
@end

@interface SPNavigationController : UINavigationController <UINavigationControllerDelegate>
@property (nonatomic, strong) EdgeGesture *testEdge;
@end
@implementation SPNavigationController
- (UIGestureRecognizer *)interactivePopGestureRecognizer { return self.testEdge ?: [super interactivePopGestureRecognizer]; }
- (NSInteger)pageProbe { return 73; }
- (id<UIViewControllerAnimatedTransitioning>)navigationController:(UINavigationController *)nav
        animationControllerForOperation:(UINavigationControllerOperation)operation
        fromViewController:(UIViewController *)from toViewController:(UIViewController *)to { return nil; }
@end

@interface LayoutOnlyView : UIView
@end
@implementation LayoutOnlyView
+ (Class)layerClass { return CATransformLayer.class; }
@end

@interface ContentList : UICollectionView <UICollectionViewDataSource>
@end
@implementation ContentList
- (instancetype)init {
    UICollectionViewFlowLayout *layout = [UICollectionViewFlowLayout new];
    layout.itemSize = CGSizeMake(100, 50);
    self = [super initWithFrame:CGRectMake(0, 0, 300, 500) collectionViewLayout:layout];
    if (self) {
        self.dataSource = self;
        [self registerClass:UICollectionViewCell.class forCellWithReuseIdentifier:@"row"];
    }
    return self;
}
- (NSInteger)collectionView:(UICollectionView *)view numberOfItemsInSection:(NSInteger)section { return 1; }
- (UICollectionViewCell *)collectionView:(UICollectionView *)view cellForItemAtIndexPath:(NSIndexPath *)path {
    return [view dequeueReusableCellWithReuseIdentifier:@"row" forIndexPath:path];
}
@end

@interface AlbumPage : UIViewController
@property (nonatomic, copy) void (^appeared)(void);
@end
@implementation AlbumPage
- (NSURL *)URI { return [NSURL URLWithString:@"spotify:album:example"]; }
- (NSURL *)spt_pageURI { return nil; }
- (void)loadView {
    self.view = [LayoutOnlyView new];
    UIView *content = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 300, 500)];
    content.backgroundColor = UIColor.blueColor;
    [self.view addSubview:content];
}
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (self.appeared) self.appeared();
}
@end

@interface PopContext : NSObject <UIViewControllerContextTransitioning>
@property (nonatomic, strong) UIView *containerView;
@property (nonatomic, strong) UIViewController *from;
@property (nonatomic, strong) UIViewController *to;
@property (nonatomic) BOOL cancelled;
@property (nonatomic, copy) void (^completed)(void);
@end
@implementation PopContext
- (BOOL)isAnimated { return YES; }
- (BOOL)isInteractive { return NO; }
- (BOOL)transitionWasCancelled { return self.cancelled; }
- (UIModalPresentationStyle)presentationStyle { return UIModalPresentationNone; }
- (CGAffineTransform)targetTransform { return CGAffineTransformIdentity; }
- (UIViewController *)viewControllerForKey:(UITransitionContextViewControllerKey)key {
    return [key isEqualToString:UITransitionContextFromViewControllerKey] ? self.from : self.to;
}
- (UIView *)viewForKey:(UITransitionContextViewKey)key {
    return [key isEqualToString:UITransitionContextFromViewKey] ? self.from.view : self.to.view;
}
- (CGRect)initialFrameForViewController:(UIViewController *)vc { return self.containerView.bounds; }
- (CGRect)finalFrameForViewController:(UIViewController *)vc { return self.containerView.bounds; }
- (void)updateInteractiveTransition:(CGFloat)percentComplete {}
- (void)finishInteractiveTransition {}
- (void)cancelInteractiveTransition {}
- (void)pauseInteractiveTransition {}
- (void)completeTransition:(BOOL)complete {
    HARNESS_CHECK(complete == !self.cancelled);
    HARNESS_CHECK(self.from.view.superview == self.containerView);
    HARNESS_CHECK(CGRectEqualToRect(self.from.view.frame, self.containerView.bounds));
    self.completed();
}
@end

@interface SourcePage : UIViewController
@property (nonatomic, strong) AlbumPage *destination;
@property (nonatomic, strong) UICollectionViewCell *cell;
@property (nonatomic, strong) UIImageView *artwork;
@property (nonatomic, strong) UINavigationController *testedNavigation;
@property (nonatomic, strong) UIView *testContainer;
@property (nonatomic) BOOL started;
@end
@implementation SourcePage
- (void)open:(id)sender {
    [self.navigationController pushViewController:self.destination animated:YES];
}
- (void)checkPush:(NSUInteger)stage {
    NSLog(@"[harness] page zoom push %lu", (unsigned long)stage);
    if (stage == 3) { [self checkPop:0]; return; }
    for (UIView *view in self.destination.view.subviews.copy) [view removeFromSuperview];
    UIButton *action = [UIButton buttonWithType:UIButtonTypeSystem];
    action.frame = CGRectMake(0, 0, 44, 44);
    [action setTitle:@"More" forState:UIControlStateNormal];
    self.destination.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:action];
    [self.testedNavigation.view layoutIfNeeded];
    [self.testedNavigation.navigationBar layoutIfNeeded];
    UIView *chrome = action;
    while (chrome && ![NSStringFromClass(chrome.class) isEqualToString:@"_UINavigationBarPlatterView"]) chrome = chrome.superview;
    HARNESS_CHECK(chrome);
    chrome.alpha = 0.75;
    BOOL chromeHidden = chrome.hidden;
    UIView *sourceChrome = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 20, 20)];
    sourceChrome.alpha = 0.5;
    [self.view addSubview:sourceChrome];
    PopContext *context = [PopContext new];
    context.cancelled = stage == 2;
    context.containerView = self.testContainer;
    context.from = self;
    context.to = self.destination;
    context.from.view.frame = context.containerView.bounds;
    [context.containerView addSubview:context.from.view];
    CFTimeInterval start = CACurrentMediaTime();
    context.completed = ^{
        HARNESS_CHECK(self.destination.view.alpha == 1);
        HARNESS_CHECK(self.destination.view.superview == (stage == 2 ? nil : self.testContainer));
        HARNESS_CHECK(chrome.alpha == 0.75 && chrome.hidden == chromeHidden);
        HARNESS_CHECK(sourceChrome.alpha == 0.5);
        [sourceChrome removeFromSuperview];
        if (stage == 1) HARNESS_CHECK(CACurrentMediaTime() - start >= 0.6);
        dispatch_async(dispatch_get_main_queue(), ^{ [self checkPush:stage + 1]; });
    };
    id<UIViewControllerAnimatedTransitioning> animator = [self.testedNavigation.delegate
        navigationController:self.testedNavigation animationControllerForOperation:UINavigationControllerOperationPush
        fromViewController:self toViewController:self.destination];
    [animator animateTransition:context];
    CADisplayLink *readiness = [(NSObject *)animator valueForKey:@"readinessLink"];
    HARNESS_CHECK(readiness && readiness.preferredFramesPerSecond == 0);
    HARNESS_CHECK(CAFrameRateRangeIsEqualToRange(readiness.preferredFrameRateRange, CAFrameRateRangeDefault));
    HARNESS_CHECK(chrome.alpha == 0 && chrome.hidden == chromeHidden);
    HARNESS_CHECK(sourceChrome.alpha == 0.5);
    HARNESS_CHECK(self.destination.view.alpha == 0);
    UIImageView *cover = nil;
    for (UIView *view in self.destination.view.superview.subviews) {
        if ([view isKindOfClass:UIImageView.class] && ((UIImageView *)view).image == self.artwork.image) cover = (id)view;
    }
    HARNESS_CHECK(cover && cover.alpha == 1 && cover.contentMode == UIViewContentModeScaleAspectFill);
    CGFloat width = self.testContainer.bounds.size.width;
    HARNESS_CHECK(CGRectEqualToRect(cover.frame, CGRectMake(0, 0, width, width)));
    HARNESS_CHECK(CGColorEqualToColor(cover.superview.backgroundColor.CGColor, UIColor.blackColor.CGColor));
    if (stage != 1) {
        ContentList *list = [ContentList new];
        [self.destination.view addSubview:list];
        [list layoutIfNeeded];
        HARNESS_CHECK(list.visibleCells.count == 1);
    }
}
- (void)checkPop:(NSUInteger)stage {
    NSLog(@"[harness] page zoom pop %lu", (unsigned long)stage);
    if (stage == 3) {
        fprintf(stderr, "PASS page zoom on: uncapped readiness, destination chrome reveal/restoration/cancel, artwork push, content/cap reveal, interactive fallback, delegate forwarding, source frame, removal and reuse\n");
        fflush(stderr);
        exit(0);
    }
    if (stage == 1) [self.cell removeFromSuperview];
    if (stage == 2) {
        [self.view addSubview:self.cell];
        [self.cell prepareForReuse];
    }
    PopContext *context = [PopContext new];
    context.containerView = self.testContainer;
    context.from = self.destination;
    context.to = self;
    context.from.view.frame = context.containerView.bounds;
    [context.containerView addSubview:context.from.view];
    context.completed = ^{ dispatch_async(dispatch_get_main_queue(), ^{ [self checkPop:stage + 1]; }); };
    id<UIViewControllerAnimatedTransitioning> animator = [self.testedNavigation.delegate
        navigationController:self.testedNavigation animationControllerForOperation:UINavigationControllerOperationPop
        fromViewController:self.destination toViewController:self];
    HARNESS_CHECK(animator);
    [animator animateTransition:context];
    // Inspect the rendered page's animated carrier, not a copied geometry calculation.
    UIView *carrier = self.destination.view.superview;
    if (stage == 0) {
        HARNESS_CHECK(CGRectEqualToRect(carrier.frame, CGRectMake(20, 150, 100, 100)));
        HARNESS_CHECK(carrier.alpha == 1);
    } else {
        HARNESS_CHECK(CGRectEqualToRect(carrier.frame, self.testContainer.bounds));
        HARNESS_CHECK(carrier.alpha == 0);
    }
}
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (self.started) return;
    NSLog(@"[harness] page zoom source appeared");
    self.started = YES;
    self.testedNavigation = self.navigationController;
    self.testedNavigation.delegate = (id)self.testedNavigation;
    UICollectionViewCell *cell = [[UICollectionViewCell alloc] initWithFrame:CGRectMake(20, 150, 100, 100)];
    self.cell = cell;
    [self.view addSubview:cell];
    UIButton *button = [[UIButton alloc] initWithFrame:cell.bounds];
    [cell.contentView addSubview:button];
    UIView *holder = [[UIView alloc] initWithFrame:button.bounds];
    holder.accessibilityIdentifier = @"Encore.ImageView";
    holder.layer.cornerRadius = 12;
    holder.clipsToBounds = YES;
    [button addSubview:holder];
    UIImageView *artwork = [[UIImageView alloc] initWithFrame:holder.bounds];
    self.artwork = artwork;
    artwork.image = [[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(400, 400)] imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [UIColor.redColor setFill];
        UIRectFill(CGRectMake(0, 0, 400, 400));
    }];
    [holder addSubview:artwork];
    [button addTarget:self action:@selector(open:) forControlEvents:UIControlEventTouchUpInside];
    self.destination = [AlbumPage new];
    BOOL enabled = SGFlag(SGRKeyPageZoom, NO);
    UIViewControllerTransition *existing = [UIViewControllerTransition crossDissolveTransition];
    if (!enabled) self.destination.preferredTransition = existing;
    __weak SourcePage *weakSelf = self;
    self.destination.appeared = ^{
        SourcePage *source = weakSelf;
        if (!enabled) {
            HARNESS_CHECK(source.destination.preferredTransition == existing);
            HARNESS_CHECK(source.testedNavigation.delegate == (id)source.testedNavigation);
            fprintf(stderr, "PASS page zoom off: existing transition and delegate untouched\n");
            fflush(stderr);
            exit(0);
        }
        id delegate = source.testedNavigation.delegate;
        HARNESS_CHECK([delegate pageProbe] == 73);
        SPNavigationController *nav = (id)source.testedNavigation;
        nav.testEdge = [EdgeGesture new];
        nav.testEdge.reportedState = UIGestureRecognizerStateBegan;
        HARNESS_CHECK([delegate navigationController:nav
            animationControllerForOperation:UINavigationControllerOperationPop
            fromViewController:source.destination toViewController:source] == nil);
        nav.testEdge = nil;
        HARNESS_CHECK([delegate navigationController:source.testedNavigation
            animationControllerForOperation:UINavigationControllerOperationPush
            fromViewController:source.destination toViewController:[UIViewController new]] == nil);
        // Delegate reassignment must retain Spotify's new owner, not replace the proxy.
        SPNavigationController *replacement = [SPNavigationController new];
        source.testedNavigation.delegate = replacement;
        HARNESS_CHECK([(id)source.testedNavigation.delegate pageProbe] == 73);
        source.testedNavigation.delegate = (id)source.testedNavigation;
        source.testContainer = [[UIView alloc] initWithFrame:source.destination.view.window.bounds];
        [source.destination.view.window addSubview:source.testContainer];
        [source checkPush:0];
    };
    // Real UIControl activation also covers the path used without a finger by accessibility.
    [button sendActionsForControlEvents:UIControlEventTouchUpInside];
    HARNESS_CHECK(self.navigationController.topViewController == self.destination);
}
@end

@interface App : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end
@implementation App
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    harnessMotion = allowMotion;
    NSLog(@"[harness] page zoom launched");
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController = [[SPNavigationController alloc] initWithRootViewController:[SourcePage new]];
    return YES;
}
@end

int main(int argc, char **argv) {
    @autoreleasepool { return UIApplicationMain(argc, argv, nil, NSStringFromClass(App.class)); }
}
