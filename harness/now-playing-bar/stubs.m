// What NowPlayingBar.x links against and the text split does not use: the glass, the press watcher, the tab bar's
// slot and the accent, none of which a placed page's text touches.
#import <UIKit/UIKit.h>
#import "Core/SGGlass.h"
#import "Core/SGUIMode.h"
#import "Settings/SGPageStyle.h"
#import "Redesigned/Kit/SGRAccent.h"
#import "Redesigned/Kit/SGRGlass.h"
#import "Redesigned/Kit/SGRPress.h"
#import "Redesigned/Kit/SGRRepaint.h"
#import "Redesigned/Navbar/Navbar.h"
#import "Shared/Player/PlayerState.h"

__weak UIView *sgr_nowPlayingRoot;
NSHashTable<UIView *> *sgr_nowPlayingPainted;

BOOL SGRedesignedUI(void) { return NO; }
NSString *SGL(NSString *key, NSString *english) { return english; }
UIColor *SGRAccentColor(void) { return nil; }
NSInteger SGRAccentRGB(void) { return 0x1ed760; }
NSString *const SGRAccentDidChangeNotification = @"harness.accent";
UIColor *SGColorRGB(NSInteger rgb) {
    return [UIColor colorWithRed:((rgb >> 16) & 255) / 255.0 green:((rgb >> 8) & 255) / 255.0 blue:(rgb & 255) / 255.0 alpha:1];
}
void SGAddPlayerStateObserver(id<SGPlayerStateObserver> observer) {}
BOOL sg_harnessLyricsOpened, sg_harnessQueueOpened;
NSString *const SGRPlayerVisibilityDidChangeNotification = @"harness.visibility";
CGRect SGRSettledPlayerRect(UIWindow *window) { return CGRectNull; }
BOOL SGRPlayerLandscapeCovers(UIWindow *window) { return NO; }
void SGRObserveVisibility(UIView *view, dispatch_block_t changed) {}
void SGRPlayerShowLyricsOnOpen(void) { sg_harnessLyricsOpened = YES; }
void SGRPlayerShowQueue(UIView *from) { sg_harnessQueueOpened = YES; }
BOOL SGOpenSpotifyURI(NSURL *uri) { return [uri.absoluteString isEqualToString:@"spotify:now-playing"]; }
UIView *SGRFindByIdentifier(UIView *root, NSString *identifier, const void *key) {
    if ([root.accessibilityIdentifier isEqualToString:identifier]) return root;
    for (UIView *child in root.subviews) {
        UIView *found = SGRFindByIdentifier(child, identifier, key);
        if (found) return found;
    }
    return nil;
}
// The app's text size, which the harness changes; production reads UIApplication.preferredContentSizeCategory.
// Catalyst's Mac idiom does not scale text, so the sizes are the phone's: the bar's two styles at Large, a point less
// below it, and capped at `largest` like SGCategoryCappedFont.
UIContentSizeCategory sg_harnessTextSize;
UIFont *SGCategoryCappedFont(UIFontTextStyle style, UIFontWeight weight, UIContentSizeCategory largest) {
    UIContentSizeCategory category = sg_harnessTextSize ?: UIContentSizeCategoryLarge;
    if (UIContentSizeCategoryCompareToCategory(category, largest) == NSOrderedDescending) category = largest;
    CGFloat atLarge = [style isEqual:UIFontTextStyleSubheadline] ? 15 : 13;
    BOOL below = UIContentSizeCategoryCompareToCategory(category, UIContentSizeCategoryLarge) == NSOrderedAscending;
    return [UIFont systemFontOfSize:atLarge - (below ? 1 : 0) weight:weight];
}
void SGRShowGlass(UIView *shape, BOOL shown) {}
UIVisualEffect *SGRGlassEffect(void) { return SGGlassEffect(); }
void SGRPressWatch(UIView *view, SGRPressKind kind, BOOL (^begins)(UITouch *touch), void (^changed)(BOOL pressed, BOOL tapped)) {}
BOOL SGRPressOnSmallControl(UITouch *touch, UIView *container) { return NO; }
void SGRPressAnimateLayer(CALayer *layer, NSString *keyPath, id value, BOOL animated) {}
CGRect SGRTabBarInlineSlot(UIView *host, CGFloat height) { return CGRectNull; }
CGRect SGRTabBarGlassRow(UIView *view) { return CGRectNull; }
