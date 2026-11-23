#import <UIKit/UIKit.h>
#import "../harness-fail.h"

@interface _TtC19NowPlaying_ViewImpl24NowPlayingViewController : UIViewController @end
@implementation _TtC19NowPlaying_ViewImpl24NowPlayingViewController @end
@interface _TtC25Lyrics_NPVElementsKitImpl24LyricsElementWrapperView : UIView @end
@implementation _TtC25Lyrics_NPVElementsKitImpl24LyricsElementWrapperView @end
@interface _TtC22Lyrics_NPVContainerKit19LyricsContainerView : UIView @end
@implementation _TtC22Lyrics_NPVContainerKit19LyricsContainerView @end

static void check(UIView *host, Class cls, BOOL rtl, CGFloat x, CGFloat width, CGFloat inset) {
    UIView *column = [[UIView alloc] initWithFrame:CGRectMake(x, 100, width, 60)];
    column.semanticContentAttribute = rtl ? UISemanticContentAttributeForceRightToLeft
                                          : UISemanticContentAttributeForceLeftToRight;
    [host addSubview:column];
    UIView *preview = [cls new];
    preview.translatesAutoresizingMaskIntoConstraints = NO;
    [column addSubview:preview];
    [NSLayoutConstraint activateConstraints:@[
        [preview.leadingAnchor constraintEqualToAnchor:column.leadingAnchor],
        [preview.trailingAnchor constraintEqualToAnchor:column.trailingAnchor],
        [preview.topAnchor constraintEqualToAnchor:column.topAnchor],
        [preview.bottomAnchor constraintEqualToAnchor:column.bottomAnchor],
    ]];
    [column layoutIfNeeded];
    [preview layoutSubviews];
    [column layoutIfNeeded];
    CGRect frame = preview.frame;
    CGRect inHost = [host convertRect:preview.bounds fromView:preview];
    if (CGRectGetMinX(frame) != inset || CGRectGetWidth(frame) != width - 2 * inset ||
        CGRectGetMinX(inHost) != x + inset)
        HARNESS_FAIL(@"%@ (%@), column x %g width %g: preview x %g width %g, expected x %g width %g",
                     cls, rtl ? @"RTL" : @"LTR", x, width, frame.origin.x, frame.size.width, inset, width - 2 * inset);
    [column removeFromSuperview];
}

@interface MarginApp : UIResponder <UIApplicationDelegate> @end
@implementation MarginApp
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
        UIWindow *window = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, 402, 800)];
        UIViewController *player = [_TtC19NowPlaying_ViewImpl24NowPlayingViewController new];
        player.view.frame = window.bounds;
        [window addSubview:player.view];
        HARNESS_CHECK(player.view.window == window && player.view.bounds.size.width == 402);
        [player viewDidLayoutSubviews];
        UIView *outside = [[UIView alloc] initWithFrame:player.view.bounds];
        [window addSubview:outside];
        for (Class cls in @[_TtC25Lyrics_NPVElementsKitImpl24LyricsElementWrapperView.class,
                            _TtC22Lyrics_NPVContainerKit19LyricsContainerView.class]) {
            check(player.view, cls, NO, 24, 354, 8);
            check(player.view, cls, YES, 24, 354, 8);
            check(player.view, cls, NO, 60, 200, 0);
            check(player.view, cls, NO, 24, 346, 0); // opposite gap exactly 32
            check(outside, cls, NO, 24, 354, 0);
        }
        puts("Player lyric preview margin: passed");
        exit(0);
}
@end

int main(int argc, char **argv) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(MarginApp.class));
    }
}
