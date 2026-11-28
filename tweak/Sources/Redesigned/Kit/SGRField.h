// The artwork field: one continuous color taken from the artwork (SGRPalette.h) behind a whole
// redesigned page, with no card and no seam anywhere. The player's field also carries the
// artwork itself at the top, blurred and dimmed and dissolving into the color (showsBackdrop).
//
// Nothing is blurred live and nothing is masked: the view draws a solid color layer, a black gradient
// layer (the redesign is AMOLED throughout, fading the color to black down the page) and at most one
// bitmap layer rendered off the main thread, so it costs a few composited layers while the page moves. A new color or bitmap crossfades over
// SGRCrossfade; the same image again is a no-op.
//
// Ownership: the screen that installs a field owns it (usually retained by its superview and an
// associated object). The field retains its last image and palette only.
// Threading: main thread only; the palette work it starts runs off it.
#import <UIKit/UIKit.h>

// Standalone artwork harnesses have no UIApplication.
#ifdef SGR_ARTWORK_PREPARE_PROBE
BOOL SGRArtworkAppIsActive(void);
#else
static inline BOOL SGRArtworkAppIsActive(void) {
    UIApplication *app = UIApplication.sharedApplication;
    return !app || app.applicationState == UIApplicationStateActive;
}
#endif

// Posted on the main thread by a field whose color changed, with the field as the object and the
// new color under "color".
extern NSNotificationName const SGRFieldColorDidChangeNotification;
// Posted on the main thread by a field that has read its artwork's palette (-paletteColor), with the field as the object.
extern NSNotificationName const SGRFieldPaletteDidChangeNotification;

@interface SGRArtworkField : UIView
// Set by SGRPageFieldIn, not by the player. Only an actually resolved color is published.
@property (nonatomic, weak) UIView *accentPage;
// Where the color, the fade to black and the backdrop reach past the bounds (overscroll, a plane
// that does not clip): positive values draw outside. The field never clips.
@property (nonatomic) UIEdgeInsets bleed;
@property (nonatomic) BOOL showsBackdrop;
// The player's moving field instead of the still backdrop (SGRFlow.h): the artwork's colors drifting
// over the whole of the bounds, with no fade to black. It moves only while the field is in a window,
// the app is in front, the player is not opening or closing, Reduce Motion and Low Power Mode are off
// and nothing holds it (motionHeld); otherwise it stays still where it was. Changing this mode rereads
// the retained artwork for the new palette and discards pending results from the previous mode.
@property (nonatomic) BOOL flows;
// Fluid artwork instead (SGRFluid.h): the cover itself blurred and slowly turning over the whole of the
// bounds, under the same conditions for moving as `flows`. Setting one turns the other off.
@property (nonatomic) BOOL fluid;
// Held still by the owner (the player while playback is paused, or while an Animated artwork clip covers
// the field).
@property (nonatomic) BOOL motionHeld;
// Covered by something opaque the owner lays over the whole of the bounds (the player's Animated artwork
// clip): the Fluid copies are hidden rather than composited under it for nothing, and come back where they
// were when uncovered. Set the clip hold once it is opaque and release it before it fades.
// Reading covered includes the independent Black or Photo backdrop hold.
@property (nonatomic) BOOL covered;
// Black and Photo have their own opaque view. A clip going away cannot uncover it.
@property (nonatomic) BOOL backdropCovered;
// The player can leave the screen while its background view is still in a window.
@property (nonatomic) BOOL offscreen;
// The backdrop's height in points from the top of the bounds; 0 is the window's height.
@property (nonatomic) CGFloat backdropHeight;
// The color the field paints: the one asked for (SGRNeutralField until a color arrives) as the redesign shows it
// (SGRFieldShownColor), so what is drawn to meet the page ends in the page's own color.
// SGRFieldColorDidChangeNotification's "color" is the one asked for.
@property (nonatomic, readonly) UIColor *fieldColor;

// The color from the artwork's main color rather than its bottom edge (SGRPaletteRequest's mainColor): a
// playlist, album or artist page, whose cover dissolves into the field. The player keeps the edge, where its
// backdrop meets the color. Set before the first artwork.
@property (nonatomic) BOOL mainColor;

// A color Spotify already has for the page (the player's background color, the album's wash), made fit
// to be a field and shown until the first artwork has been read; ignored after that.
- (void)setProvisionalColor:(UIColor *)color;
// A color the page's owner read itself (the album's picture-aware cover, Album/AlbumHeader.x): shown as given, not
// made fit as the palette's is, instead of the palette's while it is set, and a page held for its artwork is shown
// with it. nil goes back to the palette's color.
@property (nonatomic, copy) UIColor *overrideColor;
// The palette's color for the artwork last given, whether or not overrideColor is shown over it; nil until that artwork
// has been read. SGRFieldPaletteDidChangeNotification is posted, with the field as the object, each time one is read.
@property (nonatomic, readonly) UIColor *paletteColor;
// Reads the artwork off the main thread and crossfades the result in (without animation when
// `animated` is NO or the field is not in a window). The same image, or the same non-nil identity,
// as the last call is a no-op, and a result that lands after a newer call is dropped. nil keeps
// what the field shows.
- (void)setArtwork:(UIImage *)image identity:(NSString *)identity animated:(BOOL)animated;

// A page that comes in whole rather than a piece at a time: until the field has read its first artwork, a veil
// of the neutral field lies over everything `page` holds but its pinned ⋯ (SGRPinnedMore), and then fades away
// at once, with the cover, the color and the text that arrived under it. The back button is the navigation
// bar's, outside the page, and stays. A page whose artwork never comes is shown after SGRFieldHoldLimit, and
// one that knows it has none releases itself (-showPage). Called from the page's own pass, which keeps the
// veil on top; nothing once the page has been shown, so a page coming back is never held again.
- (void)holdPage:(UIView *)page;
- (void)showPage;
@end

// How long a page waits for its artwork before it is shown anyway. The Music app shows something at once
// (HIG, Loading: "Show something as soon as possible"), so the wait is short; a page then loads as it used to.
extern const NSTimeInterval SGRFieldHoldLimit;

// The color a field asked to paint `color` shows (its -fieldColor then): the redesign paints Spotify's base greys
// black (SGRAmoled.x), and this is that rule's answer, read off a layer. nil for nil. Main thread.
UIColor *SGRFieldShownColor(UIColor *color);

// Album, artist and playlist fields: page-sized, behind its contents, bleeding 600pt above and below,
// using the artwork's main color. Keys remain page-specific; pageName is the existing diagnostic name.
SGRArtworkField *SGRPageFieldIn(UIView *page, const void *key, NSString *pageName);
// The nearest ancestor (view included) carrying this page's field.
SGRArtworkField *SGRPageFieldOn(UIView *view, const void *key);
