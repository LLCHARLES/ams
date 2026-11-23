// The redesign's accent token (SGRAccent.x), apart from the native look's. The saved pick defaults
// to #37F200; negative picks Spotify's green. Automatic temporarily uses the page/playing cover.
#import <UIKit/UIKit.h>

#define SGRKeyAccent @"spotifyglass.redesign.accent"   // 0xRRGGBB
// The last color picked, kept while a preset is in place so Custom brings it back.
#define SGRKeyAccentCustom @"spotifyglass.redesign.accent.custom"
#define SGRKeyAccentAuto @"spotifyglass.redesign.accent.auto"
#define SGRKeyHideExplicit @"spotifyglass.redesign.hideExplicit"
// The redesign's own green until another is picked; Spotify's is a pick of its own, stored as -1.
#define SGRDefaultAccent 0x37F200

// Follow the cover (Player/PlayerCoverAccent.x), read at launch. It paints only what carries provenance, so a launch
// with it on installs the provenance hooks even under Spotify's green.
#define SGRKeyPlayerFollowsCover @"spotifyglass.redesign.player.followsCover"

UIColor *SGRAccentColor(void);   // nil for Picked/Spotify, as before; otherwise a live token
// A Picked/Spotify launch needs relaunch to enable an accent (Follow the cover alone installs the hooks, not the
// substitution); accent launches can toggle live.
BOOL SGRAccentSubstitutionEnabled(void);
NSInteger SGRAccentRGB(void);    // the color in effect, 0xRRGGBB, Spotify's green included
NSInteger SGRPickedAccentRGB(void); // saved pick, never the temporary page/cover color
extern NSNotificationName const SGRAccentDidChangeNotification;
// Main-thread ownership. A registered page with nil color uses the playing cover, then the pick.
// Publication never promotes a page: only the settled foreground controller can do that.
void SGRAccentPublishPageColor(UIView *page, UIColor *color);
void SGRAccentRefreshContext(void);
void SGRAccentTrackTransition(id<UIViewControllerTransitionCoordinator> transition);
void SGRAccentNavigationWillChange(void);
void SGRAccentNavigationDidChange(id<UIViewControllerTransitionCoordinator> transition);
void SGRAccentPreferencesChanged(void);
// Token colors retain their identity across automatic changes; the drawing hooks refresh assigned tokens.
UIColor *SGRAccentTokenColor(CGFloat alpha, CGFloat shade);
BOOL SGRAccentIsToken(UIColor *color);
// Semantic provenance survives rendering and CAAnimation's copy-on-add. A matching hue/RGB alone
// is never ownership. Tokens retain alpha/shade and original brand RGB for restoring Picked/Spotify,
// never an earlier resolved page color.
@class CAShapeLayer, CAAnimation;
@interface SGRAccentToken : NSObject
@property (nonatomic, readonly) CGFloat alpha, shade;
@property (nonatomic, readonly) NSInteger originalRGB;
- (instancetype)initWithAlpha:(CGFloat)alpha shade:(CGFloat)shade originalRGB:(NSInteger)originalRGB;
- (CGColorRef)copyCGColorForRGB:(NSInteger)rgb CF_RETURNS_RETAINED;
- (CGColorRef)copyGlobalCGColor CF_RETURNS_RETAINED;
- (UIColor *)color;
@end
SGRAccentToken *SGRAccentSource(UIColor *color);
SGRAccentToken *SGRAccentMarkedCGSource(CGColorRef color);
SGRAccentToken *SGRAccentCGSource(CGColorRef color);
SGRAccentToken *SGRAccentImageSource(UIImage *image);
UIImage *SGRAccentTintedImage(UIImage *image, UIColor *override);
SGRAccentToken *SGRAccentLayerSource(CAShapeLayer *layer, BOOL stroke);
// Only newly submitted animations use this override. Installed animations are never replaced.
void SGRAccentSetLayerOverride(CALayer *layer, UIColor *override);
void SGRAccentStart(void);
void SGRRefreshExplicitBadges(void);
// What a UIColor made from these components comes out as: one of Spotify's greens turns into the accent while it is
// swapped. NO, and the components untouched, for any other color.
BOOL SGRAccentSwap(CGFloat *r, CGFloat *g, CGFloat *b);

// The colors chosen before, newest first, as 0xRRGGBB numbers (SGRAccentHistory.m), shown as swatches over the
// picker (SGRAccentSheet.m), apart from the native look's. The redesign's own green and Spotify's are never kept.
#define SGRKeyAccentRecent @"spotifyglass.redesign.accent.recent"
#define SGRAccentRecentLimit 8
// The stored list as it is shown: whole numbers in 0...0xFFFFFF, first of each only, the two greens and any other
// entry left out, at most SGRAccentRecentLimit.
NSArray<NSNumber *> *SGRAccentRecentFrom(id stored);
// `recent` after `rgb` was chosen with `current` in effect: unchanged when they are the same color or `rgb` is not
// kept, else `rgb` first, taken out of where it was, and the oldest past the limit dropped.
NSArray<NSNumber *> *SGRAccentRecentAdding(NSArray<NSNumber *> *recent, NSInteger rgb, NSInteger current);
// The accent color's sheet: `recent` as swatches over the system color picker, `current` marked. A swatch hands its
// color to `chosen` at once; the picker's color goes when its checkmark is tapped, never while it is dragged; closing
// the sheet chooses nothing.
void SGRPickAccent(NSString *title, NSInteger current, NSArray<NSNumber *> *recent, void (^chosen)(NSInteger rgb));

// Plain checkmark's switch, from before Saved mark (SGRKeySavedMark, SGRRefinements.h) took its place: read only, to
// give Saved mark its value while that has none, and never written or removed, so a downgrade finds it as it was.
#define SGRKeyPlainCheck @"spotifyglass.redesign.plainCheck"
// The accent mark's view (the plain checkmark, the dot, the filled star), a template image: Follow the cover
// (Player/PlayerCoverAccent.x) sets its tint.
#define SGRPlainCheckIdentifier @"spotifyglass.plainCheck"

@class SGModRow;
NSArray<SGModRow *> *SGRAppearanceRows(void);   // the accent color, for the Appearance page
