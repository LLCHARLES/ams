// The ink of the player's small text (the artist, the times, the audio quality badge) over a backdrop that is not
// always dark. Each is white ADDED to what is behind it (plusL), which brightens a dark backdrop and goes nowhere on
// a light one (a white cover's gray lower half: the words vanish). Two things are read to fix that:
//
//  - how light the backdrop is behind each of them: the field is drawn small now and then (a few times a second,
//    only while the player shows) and the rows the text stands on are averaged, so the reading follows a moving
//    field, a new cover and the lower shade (SGRFluid.m) without knowing which of them is drawing; and
//  - whether plusL can see that backdrop at all: a layer under an ancestor that is masked, rasterized or filtered
//    is drawn into a group of its own, where plusL adds to nothing and the ink is a plain translucent white.
//
// Over a dark backdrop nothing changes (the legacy alpha, plusL). Over a light one the alpha rises toward the
// ceiling given, and where plusL cannot see the backdrop the same result is drawn as a normal white of the alpha
// that lands on the same value over the measured backdrop.
//
// Threading: main thread only.
#import <UIKit/UIKit.h>

// Posted on the main thread when a reading changed enough to matter.
extern NSNotificationName const SGRBackdropInkDidChangeNotification;

// The view whose pixels are behind the player's text, nil when the player goes. Starts and stops the readings.
void SGRBackdropInkSetSource(UIView *source);
// 0 (black) to 1 (white), encoded luma of the backdrop behind `view`; -1 while there is no reading.
CGFloat SGRBackdropLightnessBehind(UIView *view);
// Whether plusL on `view` composites against nothing: a mask, a rasterized layer or a filter above it.
BOOL SGRInkIsolated(UIView *view);
// The ink for `view`: plain white that lands where `alpha` of white added to the backdrop behind it would
// (alpha / (1 - its lightness)). `lightAlpha` is not used. `plusL` is set to NO: the color is the plain one.
UIColor *SGRInkFor(UIView *view, CGFloat alpha, CGFloat lightAlpha, BOOL *plusL);
// For things drawn as plain translucent white that the Music app draws as white ADDED to the backdrop (its bars, its
// glyphs): the plain alpha that lands on the same value as `add` of white added over the measured backdrop,
// add / (1 - light), never under `floorAlpha` (the alpha that is the same thing over a dark backdrop), in steps of
// 0.05 so a drifting field does not redraw an image at every reading. `floorAlpha` where there is no reading or
// under Increase Contrast.
CGFloat SGRInkPlainAlpha(UIView *view, CGFloat floorAlpha, CGFloat add);
// The backdrop starts a change of `duration` seconds (a new cover crossfading in): the readings follow it at the
// display's pace until it ends, rather than every quarter second.
void SGRBackdropInkFollow(CFTimeInterval duration);
// Calls `changed` after each change of reading for as long as `view` lives; a second call replaces the block.
void SGRBackdropInkObserve(UIView *view, void (^changed)(void));
