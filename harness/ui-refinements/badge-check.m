#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "Core/SGPrefs.h"
#import "Native/Appearance/Appearance.h"
#import "Redesigned/Kit/SGRAccent.h"
#import "../harness-fail.h"
#include <stdlib.h>
#include <string.h>

BOOL SGRedesignedUI(void) { const char *look = getenv("LOOK"); return look && strcmp(look, "redesign") == 0; }
BOOL SGNativeUI(void) { return !SGRedesignedUI(); }
static NSUInteger checks;
static void expect(BOOL ok, NSString *name) { checks++; if (!ok) HARNESS_FAIL(@"%@", name); }
static void refresh(void) { SGPrefsChanged(); SGNativeUI() ? SGRefreshExplicitBadges() : SGRRefreshExplicitBadges(); }
static void stored(BOOL native, BOOL redesign) {
    [NSUserDefaults.standardUserDefaults setVolatileDomain:@{SGKeyHideExplicit: @(native), SGRKeyHideExplicit: @(redesign)}
                                                 forName:NSArgumentDomain];
    refresh();
}
static void layout(UIView *view) { [view setNeedsLayout]; [view layoutIfNeeded]; }
static UIImage *drawing(UIView *view) {
    return [[[UIGraphicsImageRenderer alloc] initWithSize:view.bounds.size] imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [view.layer renderInContext:context.CGContext];
    }];
}
static BOOL paints(UIView *view) {
    UIImage *image = drawing(view);
    uint8_t pixel[4] = {0};
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(pixel, 1, 1, 8, 4, space, (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
    CGContextDrawImage(context, CGRectMake(0,0,1,1), image.CGImage);
    CGContextRelease(context); CGColorSpaceRelease(space);
    return pixel[3] != 0;
}
static UIView *badge(Class cls, NSString *identifier) {
    UIView *view = [[cls alloc] initWithFrame:CGRectMake(0, 0, 16, 16)];
    view.accessibilityIdentifier = identifier;
    view.accessibilityLabel = @"Explicit";
    view.isAccessibilityElement = YES;
    view.backgroundColor = UIColor.whiteColor;
    layout(view);
    return view;
}

@interface OrdinaryView : UIView
@property (nonatomic) NSUInteger reads;
@end
@implementation OrdinaryView
- (NSString *)accessibilityIdentifier { self.reads++; return super.accessibilityIdentifier; }
@end

static void check(UIWindow *window) {
    @autoreleasepool {
        [NSUserDefaults.standardUserDefaults setVolatileDomain:@{} forName:NSArgumentDomain];
        refresh();
        Class retrieval = objc_allocateClassPair(UIView.class, "_TtCCC36CreativeWorkPlatform_RetrievalRowKit21RetrievalRowElementUI10BadgesViewP33_9D5FF3EB21C9757CC8B47C2445B48C7B13ExplicitBadge", 0);
        objc_registerClassPair(retrieval);
        UIView *component = badge(UIView.class, @"Components.UI.ExplicitIcon");
        UIView *row = badge(retrieval, @"CreativeWorkPlatform_RetrievalRowKit.ExplicitBadge");
        [window addSubview:component];
        [window addSubview:row];
        UIView *page = [UIView new];
        UIView *returning = badge(UIView.class, @"Components.UI.ExplicitIcon");
        [page addSubview:returning];
        [window addSubview:page];
        [page removeFromSuperview];
        OrdinaryView *ordinary = [OrdinaryView new];
        ordinary.accessibilityIdentifier = @"ordinary";
        [ordinary layoutSubviews];
        expect(ordinary.reads == 0, @"disabled hooks must not classify an ordinary view");
        UIView *download = badge(UIView.class, @"Components.UI.DownloadBadge");
        UIView *podcast = badge(UIView.class, @"Podcast.Row.MarkAsPlayed.ExplicitIcon");
        UILabel *letter = [[UILabel alloc] initWithFrame:CGRectMake(0,0,16,16)]; letter.text = @"E";
        for (UIView *view in @[component, row]) expect(paints(view), @"default off draws explicit badge");
        stored(!SGNativeUI(), !SGRedesignedUI());
        expect(paints(component), @"inactive look's setting cannot hide a badge");
        stored(SGNativeUI(), SGRedesignedUI());
        [window addSubview:page];
        expect(returning.layer.mask != nil, @"badge detached at enable is masked on unchanged reattachment");
        for (UIView *view in @[component, row]) {
            expect(!paints(view), @"verified badge paints no pixels");
            expect(CGRectEqualToRect(view.frame, CGRectMake(0,0,16,16)), @"row geometry remains unchanged");
            expect(!view.hidden && view.alpha == 1 && view.isAccessibilityElement && !view.accessibilityElementsHidden &&
                   [view.accessibilityLabel isEqualToString:@"Explicit"], @"VoiceOver description and participation retained");
        }
        expect(paints(download), @"download badge is not explicit");
        expect(paints(podcast), @"unverified podcast action icon is not hidden");
        layout(letter);
        expect(letter.layer.mask == nil && [letter.text isEqualToString:@"E"], @"arbitrary E label left alone");
        component.accessibilityIdentifier = @"clean-track";
        expect(paints(component), @"reuse for clean track restores pixels immediately");
        component.accessibilityIdentifier = @"Components.UI.ExplicitIcon";
        expect(!paints(component), @"reuse for explicit track hides badge again");
        CALayer *spotifyMask = [CALayer layer];
        spotifyMask.frame = row.bounds; spotifyMask.backgroundColor = UIColor.whiteColor.CGColor;
        row.layer.mask = spotifyMask;
        expect(!paints(row), @"Spotify mask updates cannot reveal hidden badge");
        [row removeFromSuperview];
        stored(NO, NO);
        expect(row.layer.mask == spotifyMask && paints(row), @"turning off restores latest Spotify drawing mask");
        expect(paints(component), @"turning off restores component without layout/restart");
        printf("explicit badges (%s): %lu checks passed\n", SGNativeUI() ? "native" : "redesign", (unsigned long)checks);
    }
    exit(0);
}
@interface BadgeScene : UIResponder <UIWindowSceneDelegate>
@end
@implementation BadgeScene
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    UIWindow *window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    window.rootViewController = [UIViewController new];
    [window makeKeyAndVisible];
    dispatch_async(dispatch_get_main_queue(), ^{ check(window); });
}
@end
int main(int argc, char **argv) {
    @autoreleasepool { return UIApplicationMain(argc, argv, nil, nil); }
}
