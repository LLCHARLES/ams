// The production resolver and the two controls built on it (Core/SGTopController.m) against real UIKit controller
// trees, plus the readings the phone driver's `state` command prints from the same chain (controllers, presented,
// top). Each tree is the shape the app was checked to have on a phone (Spotify 9.1.90):
//   app      RootViewController → containers → the tab bar's own container → a navigation stack → a hosting page → a
//            page;
//   player   presented NowPlayingOverlayContainer, whose shown child is a full-screen background controller, the close
//            button in a sibling collection view of the overlay's own view;
//   search   the Search tab's Browse page, whose bar's press pushes SearchUIContainerViewController, whose field is a
//            custom text view id SearchBarSearch.TextField.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "Core/SGTopController.h"

static int checks, failures;

static void check(BOOL ok, NSString *label) {
    printf("%s %s\n", ok ? "PASS" : "FAIL", label.UTF8String ?: "");
    checks++;
    if (!ok) failures++;
}

// Turns the main run loop until `done` says so, at most 5 s: UIKit finishes a presentation or a dismissal some turns
// later, and how many depends on the machine, so a fixed wait passes on one Mac and not on another.
static BOOL waitUntil(BOOL (^done)(void)) {
    NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:60];
    while (!done() && limit.timeIntervalSinceNow > 0) [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
    return done();
}

static NSString *named(UIViewController *controller) {
    return controller ? [NSString stringWithFormat:@"%@ %@", NSStringFromClass(controller.class), controller.title ?: @""] : @"nil";
}

// Over the full screen, as the app presents its player and its sheets on a phone (a Mac Catalyst sheet is a
// presentation of another kind). Waits for the presentation to be over, read from the page and its transition rather
// than from the completion, which a window the harness launched from a shell does not always get; UIKit refuses to
// present over a page still being presented.
static void present(UIViewController *presenter, UIViewController *page) {
    page.modalPresentationStyle = UIModalPresentationOverFullScreen;
    [presenter presentViewController:page animated:NO completion:nil];
    if (!waitUntil(^{ return (BOOL)(page.presentingViewController != nil && !page.isBeingPresented && !page.transitionCoordinator); }))
        printf("     %s was not presented over %s\n", named(page).UTF8String, named(presenter).UTF8String);
}

static void dismissAll(UIViewController *presenter) {
    if (!presenter.presentedViewController) return;
    [presenter dismissViewControllerAnimated:NO completion:nil];
    if (!waitUntil(^{ return (BOOL)(presenter.presentedViewController == nil); }))
        printf("     what %s presented was not dismissed\n", named(presenter).UTF8String);
}

// A container of the app's kind: shows one child by size, holds the rest behind it. Not a UITabBarController, which
// is what Spotify's tab bar container is not either.
@interface HarnessContainer : UIViewController
@end

@implementation HarnessContainer
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.blackColor;
}
@end

@interface HarnessPage : UIViewController
@end

// A page UIKit is taking away: once `leaving` is set it reports itself as being dismissed, which is what the resolver
// has to skip so the screen coming back is the top again before the animation ends. Set only once it is up: UIKit asks
// a page it is presenting the same question, and does not present one that says yes.
@interface HarnessDismissingPage : HarnessPage
@property (nonatomic) BOOL leaving;
@end

@implementation HarnessDismissingPage
- (BOOL)isBeingDismissed { return self.leaving || super.isBeingDismissed; }
@end

@implementation HarnessPage
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.blackColor;
}
@end

// The first view under `root` (itself included) with that identifier, shown.
static UIView *findShown(UIView *root, NSString *identifier) {
    if ([root.accessibilityIdentifier isEqualToString:identifier] && SGViewShown(root)) return root;
    for (UIView *sub in root.subviews) {
        UIView *found = findShown(sub, identifier);
        if (found) return found;
    }
    return nil;
}

static HarnessPage *page(NSString *name) {
    HarnessPage *page = [HarnessPage new];
    page.title = name;
    page.view.accessibilityIdentifier = name;
    return page;
}

// The Search page of the app: a BrowsePageViewController whose own view holds the Search bar button and the header
// label. The bar is an Encore tertiary button, not a text field, which is what the keyboard's ⌘F presses.
static HarnessPage *searchPage(NSString *name) {
    HarnessPage *search = page(name);
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(16, 8, 370, 108)];
    header.accessibilityIdentifier = @"SearchHeaderFind.Header";
    UIButton *bar = [UIButton buttonWithType:UIButtonTypeSystem];
    bar.frame = CGRectMake(0, 60, 358, 48);
    bar.accessibilityIdentifier = @"SearchHeaderFind.SearchBar";
    [bar setTitle:@"Search" forState:UIControlStateNormal];
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(40, 0, 278, 48)];
    title.accessibilityIdentifier = @"SearchHeaderFind.HeaderLabel";
    title.text = @"Search";
    [header addSubview:title];
    [header addSubview:bar];
    [search.view addSubview:header];
    return search;
}

// Puts `child` on `parent` at a frame, the way a container lays its children out and UIKit adds their views. The
// frame is kept on the child and applied again by applyFrames once the whole chain is in the window: a view whose
// parent is not on screen yet has no bounds to sit in, and UIKit sizes the wrapper as it attaches.
static char kFrameKey;

static void host(UIViewController *parent, UIViewController *child, CGRect frame) {
    objc_setAssociatedObject(child, &kFrameKey, [NSValue valueWithCGRect:frame], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [parent addChildViewController:child];
    [parent.view addSubview:child.view];
    [child didMoveToParentViewController:parent];
}

// Every hosted child back to its frame, top down, once the chain is in a window.
static void applyFrames(UIViewController *parent) {
    parent.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    for (UIViewController *child in parent.childViewControllers) {
        NSValue *frame = objc_getAssociatedObject(child, &kFrameKey);
        if (frame) child.view.frame = frame.CGRectValue;
        applyFrames(child);
    }
    [parent.view layoutIfNeeded];
}

// The harness's one window, the one the scene put on screen: only a window in a connected scene has its hierarchy
// laid out, and a resolver reads frames.
static UIWindow *appWindowRef;

static UIWindow *windowWith(UIViewController *root) {
    UIWindow *window = appWindowRef;
    // A fresh root each time, so a chain from the test before cannot linger as a child or as a presentation.
    dismissAll(window.rootViewController);
    window.rootViewController = nil;
    window.rootViewController = root;
    [window makeKeyAndVisible];
    [window layoutIfNeeded];
    applyFrames(root);
    [window layoutIfNeeded];
    return window;
}

// The app's chain, as the phone showed it, down to the page on the selected tab.
static UIWindow *appWindow(UIViewController *selectedTabPage, UIViewController *otherTabPage) {
    UIViewController *root = [HarnessContainer new];
    UIViewController *chrome = [HarnessContainer new];
    UIViewController *primary = [HarnessContainer new];
    UIViewController *inner = [HarnessContainer new];
    UIViewController *main = [HarnessContainer new];
    UIViewController *tabBar = [HarnessContainer new];   // NavigationUI_TabBarImpl.TabBarContainerImpl
    UINavigationController *stack = [[UINavigationController alloc] init];   // SPNavigationController
    UIViewController *hosting = [HarnessContainer new];  // MusicAppPageHostingViewController
    host(root, chrome, CGRectMake(0, 0, 402, 874));
    host(chrome, primary, CGRectMake(0, 0, 402, 874));
    host(primary, inner, CGRectMake(0, 0, 402, 874));
    host(inner, main, CGRectMake(0, 0, 402, 874));
    host(main, tabBar, CGRectMake(0, 0, 402, 874));
    // The tab bar's container holds the selected tab's stack full size and the other tab behind it, hidden.
    host(tabBar, stack, CGRectMake(0, 0, 402, 874));
    if (otherTabPage) {
        host(tabBar, otherTabPage, CGRectMake(0, 0, 402, 874));
        otherTabPage.view.hidden = YES;
    }
    [stack setViewControllers:@[hosting] animated:NO];
    host(hosting, selectedTabPage, CGRectMake(0, 0, 402, 874));
    return windowWith(root);
}

// What Driver.m's `state` prints, from the same resolver: the class of every controller down the chain, the classes
// of what was presented, and the top.
static NSDictionary *driverState(UIWindow *window) {
    NSMutableArray<NSString *> *path = [NSMutableArray array], *presented = [NSMutableArray array];
    UIViewController *top = SGTopControllerInWindow(window, path, presented);
    return @{@"top" : top ? NSStringFromClass(top.class) : [NSNull null],
             @"controllers" : path,
             @"presented" : presented};
}

static void expectTop(UIWindow *window, UIViewController *page, NSString *label) {
    UIViewController *top = SGTopControllerInWindow(window, nil, nil);
    if (top != page) printf("     top %s at %s, wanted %s\n", named(top).UTF8String,
                            NSStringFromCGRect(top.viewIfLoaded ? SGViewScreenFrame(top.view) : CGRectZero).UTF8String, named(page).UTF8String);
    check(top == page, label);
}

static void expectState(UIWindow *window, NSString *topClass, NSArray<NSString *> *controllers, NSArray<NSString *> *presented, NSString *label) {
    NSDictionary *state = driverState(window);
    BOOL ok = [state[@"top"] isEqual:topClass] && [state[@"controllers"] isEqual:controllers] && [state[@"presented"] isEqual:presented];
    if (!ok) printf("     driver state: top %s, controllers %s, presented %s\n",
                    [state[@"top"] description].UTF8String, [state[@"controllers"] description].UTF8String, [state[@"presented"] description].UTF8String);
    check(ok, label);
}

static void runChecks(UIWindow *sceneWindow) {
    appWindowRef = sceneWindow;
    // 1. The app's own chain: containers of Spotify's kind, not UITabBarController or UINavigationController at the
    //    top, and the published page is found through them rather than stopping at the root.
    HarnessPage *home = page(@"Home");
    HarnessPage *search = searchPage(@"Search");
    UIWindow *window = appWindow(home, search);
    expectTop(window, home, @"the resolver reaches the page on the selected tab through Spotify's containers");

    // 2. Search on the other tab is built and holds its bar, but is hidden: it is never the top.
    check(search.viewIfLoaded != nil && !SGViewShown(search.view), @"the sibling Search page is built and not shown");
    expectTop(window, home, @"a hidden sibling Search page is never the resolved top");

    // 3. Selected tab switched to Search: now it is the top, and its bar is inside the top's own hierarchy.
    // A Search page of its own: the first tree's copy is its hidden other tab, and a controller has one parent.
    HarnessPage *searchTab = searchPage(@"SearchTab");
    HarnessPage *home2 = page(@"Home2");
    UIWindow *onSearch = appWindow(searchTab, home2);
    expectTop(onSearch, searchTab, @"the Search page is the resolved top when its tab is the one shown");
    UIView *bar = findShown(searchTab.view, @"SearchHeaderFind.SearchBar");
    check(bar != nil && [bar isDescendantOfView:searchTab.view], @"the Search bar is a shown view inside the top's own hierarchy");

    // 4. The player presented over the app: the overlay is the top, and it was presented by the page in front, which
    //    is the shape the phone reported (presented NowPlayingOverlayContainer inside, the player's own content top).
    HarnessPage *overlay = page(@"NowPlaying_OverlayContainer");
    present(SGTopControllerInWindow(window, nil, nil), overlay);
    expectTop(window, overlay, @"a presented player overlay is the resolved top");

    // 5. Something presented over the player: the resolver reaches that, so Esc must not act on the overlay behind it.
    HarnessPage *sheet = page(@"PlayerSheet");
    present(overlay, sheet);
    expectTop(window, sheet, @"what is presented over the player is the resolved top, not the player");

    // 6. Driver equivalence: the same chain read the way `state` reads it — the root that UIKit presents from (a
    //    plain container does not forward a presentation the way Spotify's own do), then the overlay and the sheet.
    //    The driver prints these same three lists, so they have to be the same walk.
    NSArray<NSString *> *controllers = @[@"HarnessContainer", @"HarnessPage", @"HarnessPage"];
    expectState(window, @"HarnessPage", controllers, (@[@"HarnessPage", @"HarnessPage"]),
                @"driver state: the chain walked, what was presented, and the top agree with the resolver");

    // 6b. A presented page UIKit is dismissing is skipped: the screen it was over is the top again. It goes over
    //     the sheet, which is the front page (a controller shows one presentation at a time).
    HarnessDismissingPage *dismissing = [HarnessDismissingPage new];
    dismissing.title = @"Dismissing";
    present(sheet, dismissing);
    dismissing.leaving = YES;
    check(sheet.presentedViewController == dismissing, @"the dismissing page is the one presented");
    expectTop(window, sheet, @"a presented page that is being dismissed is skipped, the one under it is the top");
    // Back to an ordinary page, so the chain can be dismissed before the next tree.
    dismissing.leaving = NO;

    // 5b. The player's real shape: an overlay presenting a container whose shown child is a full-screen background
    //     page the controls are not inside, the close button in a sibling collection view of the overlay's view. The
    //     resolver reaches the background page, so the control must come from the overlay's own tree — and its press
    //     must be the one that closes the player.
    //     (Built as its own tree: a window's root cannot be presented over again once a presentation is up.)
    {
        HarnessPage *pgHome = page(@"Home");
        HarnessPage *pgSearch = searchPage(@"Search");
        UIWindow *pgWindow = appWindow(pgHome, pgSearch);

        HarnessPage *overlayPage = page(@"NowPlaying_OverlayContainer");
        HarnessPage *container = page(@"SPTNowPlayingViewContainerViewController");
        HarnessPage *background = page(@"NPVBackgroundViewController");
        host(overlayPage, container, CGRectMake(0, 0, 402, 874));
        host(container, background, CGRectMake(0, 0, 402, 874));
        UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
        close.frame = CGRectMake(12, 0, 48, 48);
        close.accessibilityIdentifier = @"now-playing-minimize-button";
        [close setTitle:@"Close" forState:UIControlStateNormal];
        [overlayPage.view addSubview:close];   // a sibling of the container's view, as the phone has it
        present(SGTopControllerInWindow(pgWindow, nil, nil), overlayPage);
        // The container and the background page full size in the overlay, as the player lays them out: hosted
        // frames are applied once a chain is in a window, and a view left at its loaded size depends on the screen.
        applyFrames(overlayPage);

        expectTop(pgWindow, background, @"the player resolves to its background plane, not to the overlay");
        NSArray<UIViewController *> *presentedChain = SGPresentedControllersInWindow(pgWindow);
        check(presentedChain.count == 1 && presentedChain.lastObject == overlayPage,
              @"the player overlay is the last presented controller");
        UIView *found = SGPlayerCloseControlInWindow(pgWindow, @[@"now-playing-minimize-button", @"mobile-nowplaying-close-button"]);
        check(found == close, @"the close control is found in the overlay's view, though not in the resolved top's");
        check(![close isDescendantOfView:background.view], @"the close control is not in the resolved top's hierarchy");

        // A sheet over the player: the last presented is no longer the overlay, so Esc/⌘W find nothing.
        HarnessPage *overlaySheet = page(@"PlayerSheet2");
        present(overlayPage, overlaySheet);
        check(SGPresentedControllersInWindow(pgWindow).lastObject == overlaySheet,
              @"a sheet over the player becomes the last presented controller");
        check(SGPlayerCloseControlInWindow(pgWindow, @[@"now-playing-minimize-button"]) == nil,
              @"no close control while a sheet is over the player");
    }

    // 5c. The search push: the Browse page's bar press pushes SearchUIContainerViewController on the Search tab's own
    //     stack, the field being a custom text view, not a UITextField — and a sheet presented from that page is not
    //     the page, so no field is answered then.
    {
        // The Browse page on the Search tab, carried by a hosting controller on that tab's own navigation stack
        // (SPNavigationController → MusicAppPageHostingViewController → BrowsePageViewController, as on the phone).
        HarnessPage *browse = searchPage(@"Browse");
        HarnessContainer *browseHost = [HarnessContainer new];
        host(browseHost, browse, CGRectMake(0, 0, 402, 874));
        UINavigationController *stack = [[UINavigationController alloc] initWithRootViewController:browseHost];
        UIWindow *searchWindow = windowWith(stack);
        expectTop(searchWindow, browse, @"the Browse page is the top on the Search tab's stack");

        // Pressing the bar pushes the input page: a container whose shown child is the SERP page.
        HarnessPage *input = page(@"SearchUIContainerViewController");
        input.view.accessibilityIdentifier = @"SearchUIContainerViewController.view";
        HarnessPage *recents = page(@"RecentsSERPViewController");
        host(input, recents, CGRectMake(0, 0, 402, 874));
        UIView *barContainer = [[UIView alloc] initWithFrame:CGRectMake(16, 60, 370, 48)];
        barContainer.accessibilityIdentifier = @"SearchBarSearch";
        // A decoy input beside it, with no identifier of its own: the field is the identified one, not merely the
        // first responder-capable view of the page.
        UITextView *decoy = [[UITextView alloc] initWithFrame:CGRectMake(0, 300, 320, 48)];
        [input.view addSubview:decoy];
        UITextView *field = [[UITextView alloc] initWithFrame:CGRectMake(0, 0, 320, 48)];
        field.accessibilityIdentifier = @"SearchBarSearch.TextField";
        [barContainer addSubview:field];
        [input.view addSubview:barContainer];
        [stack pushViewController:input animated:NO];
        [searchWindow layoutIfNeeded];
        applyFrames(stack);

        check(SGTopControllerInWindow(searchWindow, nil, nil) == recents, @"the pushed input page's SERP page is the top");
        UIResponder *pushed = SGSearchInputFieldInPushedPage(searchWindow, browse, @"SearchUIContainerViewController", @"SearchBarSearch.TextField");
        check(pushed == field, @"the input page's custom text field is found by its identifier");
        check(![pushed isKindOfClass:UITextField.class], @"the field is not a UITextField");

        // A sheet over the input page descends from it but is not it: nothing is answered.
        HarnessPage *popup = page(@"SearchPopup");
        present(recents, popup);
        check(SGSearchInputFieldInPushedPage(searchWindow, browse, @"SearchUIContainerViewController", @"SearchBarSearch.TextField") == nil,
              @"no field is answered while a sheet is over the input page");

        // The page's field is taken when it is not the cursor's, and left alone when it is.
        dismissAll(recents);
        // UIKit may lay the pages out again as the sheet goes; the containers here have no layout of their own.
        applyFrames(stack);
        UIResponder *again = SGSearchInputFieldInPushedPage(searchWindow, browse, @"SearchUIContainerViewController", @"SearchBarSearch.TextField");
        check(again == field, @"the field is found again once the sheet is gone");

        // A Browse page that is not on the input page's stack is not what it was pushed from: nothing is answered —
        // neither a page outside any stack, nor one in a stack of its own.
        HarnessPage *stranger = page(@"Stranger");
        check(SGSearchInputFieldInPushedPage(searchWindow, stranger, @"SearchUIContainerViewController", @"SearchBarSearch.TextField") == nil,
              @"a Browse page outside the input page's stack is refused");
        UINavigationController *otherStack = [[UINavigationController alloc] initWithRootViewController:page(@"OtherBrowse")];
        check(SGSearchInputFieldInPushedPage(searchWindow, otherStack.viewControllers.firstObject, @"SearchUIContainerViewController", @"SearchBarSearch.TextField") == nil,
              @"a Browse page in another navigation stack is refused");
    }

    // 7. A container whose visible child is under half its own view shows that child nowhere: the container is the
    //    top, which is what the resolver's own half-of-the-view rule says.
    HarnessContainer *small = [HarnessContainer new];
    HarnessPage *strip = page(@"Bar");
    host(small, strip, CGRectMake(0, 800, 402, 49));
    UIWindow *smallWindow = windowWith(small);
    expectTop(smallWindow, small, @"a child under half the container's view is not the shown child");

    // 8. No window, no answer: nil rather than a guess.
    check(SGTopControllerInWindow(nil, nil, nil) == nil, @"no window resolves no controller");

    printf("retrine-keyboard-top-controller-check: %d/%d passed\n", checks - failures, checks);
    fflush(stdout);
    exit(failures ? 1 : 0);
}

@interface CheckApp : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation CheckApp
- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)options {
    self.window = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, 402, 874)];
    [self.window makeKeyAndVisible];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 180 * NSEC_PER_SEC), dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
        fputs("FAIL UIKit smoke timed out\n", stderr);
        exit(1);
    });
    // The trees are built once the scene the window moved into is active, from a run loop timer and not from a block
    // on the main queue: UIKit finishes a presentation in a block of its own on that queue, which cannot run while
    // the checks wait inside one (the completion never comes and the presented view keeps no size).
    __block id observer = [NSNotificationCenter.defaultCenter addObserverForName:UISceneDidActivateNotification object:nil
        queue:nil usingBlock:^(NSNotification *note) {
        [NSNotificationCenter.defaultCenter removeObserver:observer];
        [NSTimer scheduledTimerWithTimeInterval:0 repeats:NO block:^(NSTimer *timer) { runChecks(self.window); }];
    }];
    return YES;
}
@end

int main(int argc, char **argv) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(CheckApp.class));
    }
}
