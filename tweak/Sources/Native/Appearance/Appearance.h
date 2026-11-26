// The native look's appearance: the AMOLED background (Amoled.x), the accent color in place of
// Spotify's green (Accent.x), the soft top edge (EdgeEffect.x) and Repaint.x, which keeps what the
// native tweaks stripped transparent when Spotify repaints it. The switches are off until asked for.
#import <UIKit/UIKit.h>

#define SGKeyAmoled @"spotifyglass.amoled"
#define SGKeyAccent @"spotifyglass.accent"   // 0xRRGGBB; unset or negative keeps Spotify's own green
// The last color picked, kept while a preset is in place so Custom brings it back.
#define SGKeyAccentCustom @"spotifyglass.accent.custom"
#define SGKeyHideExplicit @"spotifyglass.hideExplicit"
void SGRefreshExplicitBadges(void);

NSInteger SGAccentRGB(void);    // the color in effect, 0xRRGGBB, Spotify's green included

// The colors chosen before, newest first, as 0xRRGGBB numbers (AccentHistory.m), shown as swatches over the
// picker (AccentSheet.m). Spotify's green, the native look's own, is never kept.
#define SGKeyAccentRecent @"spotifyglass.accent.recent"
#define SGAccentRecentLimit 8
// The stored list as it is shown: whole numbers in 0...0xFFFFFF, first of each only, Spotify's green and any other
// entry left out, at most SGAccentRecentLimit.
NSArray<NSNumber *> *SGAccentRecentFrom(id stored);
// `recent` after `rgb` was chosen with `current` in effect: unchanged when they are the same color or `rgb` is not
// kept, else `rgb` first, taken out of where it was, and the oldest past the limit dropped.
NSArray<NSNumber *> *SGAccentRecentAdding(NSArray<NSNumber *> *recent, NSInteger rgb, NSInteger current);
// The accent color's sheet: `recent` as swatches over the system color picker, `current` marked. A swatch hands its
// color to `chosen` at once; the picker's color goes when its checkmark is tapped, never while it is dragged; closing
// the sheet chooses nothing.
void SGPickAccent(NSString *title, NSInteger current, NSArray<NSNumber *> *recent, void (^chosen)(NSInteger rgb));

@class SGModRow;
@class SGModSection;
NSArray<SGModSection *> *SGNativeAppearanceSections(void);
