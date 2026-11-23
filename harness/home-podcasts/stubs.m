// What HomeHeader.x links against and the podcasts choice does not use: the look, the glass, the title's
// font, the edge effect, Top picks' Show all and the digits Kit/SGRRestyle.m rolls.
#import <UIKit/UIKit.h>
#import "Core/SGUIMode.h"
#import "Settings/SGPageStyle.h"
#import "Redesigned/Kit/SGRGlass.h"
#import "Redesigned/Kit/SGRRestyle.h"
#import "Home.h"

// The hooks install: this is the redesign.
BOOL SGRedesignedUI(void) { return YES; }
BOOL SGRedesignAvailable(void) { return YES; }
BOOL SGRHomeLook(void) { return NO; }
UIFont *SGCategoryCappedFont(UIFontTextStyle style, UIFontWeight weight, UIContentSizeCategory largest) { return [UIFont systemFontOfSize:17 weight:weight]; }
UIView *SGRGlassCapsuleInside(UIView *control, const void *key, CGSize size, BOOL prominent) { return nil; }
void SGRShowGlass(UIView *shape, BOOL shown) {}
void SGRGlassBacks(UIView *shape, UIControl *control) {}
void SGRHardTopEdge(UIScrollView *scrollView) {}
UIControl *SGRHomeTopPicksShowAll(NSString **title) { return nil; }
CFTimeInterval SGRHomeProbeBegin(void) { return 0; }
void SGRHomeProbeEnd(SGRHomeProbe probe, CFTimeInterval began) {}
UIFont *SGMonospacedDigitsFont(UIFont *font) { return font; }
void SGRRollingDigitsMovedToWindow(UIView *view) {}
void SGRRollingDigitsTextChanged(UIView *view) {}
BOOL SGRRollingDigitsWatched(UIView *view) { return NO; }
UIColor *SGRAccentColor(void) { return UIColor.whiteColor; }
