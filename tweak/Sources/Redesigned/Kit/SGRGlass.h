// Glass for the redesign's control layer, and only for it: never behind rows, cards or text. On iOS 26 a
// UIGlassEffect in the listener's material, tint and touch response (below). Under Reduce Transparency a
// shape is a solid SGRSolidGlassFill, on any OS; before iOS 26 without it, a dark thin material blur. Nothing
// touches a glass class on an OS without them. A shape is dark whatever the system appearance: glass
// takes the one it inherits, which outside the navigation stacks Spotify makes dark (the player) is the
// system's, light on a phone in light mode.
//
// Ownership: a shape belongs to the control it is made in (associated with it under the caller's key).
// Threading: main thread only.
#import <UIKit/UIKit.h>

#pragma mark - the listener's glass (the Appearance page), read once at launch

// The iOS 26 glass's material, UIGlassEffect's two styles. Below 26 the blur has none to choose.
#define SGRKeyGlassMaterial @"spotifyglass.redesign.glass.material"
typedef NS_ENUM(NSInteger, SGRGlassMaterial) {
    SGRGlassMaterialRegular,
    SGRGlassMaterialClear,
};
// A shade laid in the iOS 26 glass. Below 26 the blur stays as it is.
#define SGRKeyGlassTint @"spotifyglass.redesign.glass.tint"
typedef NS_ENUM(NSInteger, SGRGlassTint) {
    SGRGlassTintNone,
    SGRGlassTintLight,
    SGRGlassTintDark,
};
// Touch response, on until switched off: the glass gives under a finger on the control it sits in (interactive
// glass). The control takes the touch either way; off, the glass simply stays still.
#define SGRKeyGlassInteractive @"spotifyglass.redesign.glass.interactive"
// What is stored now, for the settings rows: nothing stored, or a value that is none of the enum's, is Regular and None.
SGRGlassMaterial SGRStoredGlassMaterial(void);
SGRGlassTint SGRStoredGlassTint(void);

// The listener's glass as the launch read it, a new effect on each call: on iOS 26 a UIGlassEffect in their material,
// tint and touch response, below it Core's SGGlassEffect(). Every glass pane the redesign makes takes its effect from
// here (the shapes below, the now playing card and its strip, the bars' stand-ins), never from SGGlassEffect() or
// UIGlassEffect directly; Search's category cards keep their own Clear glass in the category's color. Reduce
// Transparency is the caller's: a shape of the Kit's is solid under it, a pane keeps UIKit's own treatment.
UIVisualEffect *SGRGlassEffect(void);

// Gives a glass UIKit draws as a view's own background (the tab bars' platters) the listener's glass, when they chose
// other than UIKit's Regular, untinted, interactive glass; for a pass that may follow UIKit making the view anew.
// Nothing below iOS 26 or on a view without a glass background.
void SGRGlassRestyle(UIView *view);

// A glass circle inside someone else's round control, `side` across, behind everything the control
// draws (first in its subviews, re-asserted on every call, since glass takes what is above it in the
// tree into its backdrop however the depths are set) and kept at its middle by the autoresizing mask.
// Being the control's own
// subview it goes wherever the control goes: a frame worked out from outside goes stale when Spotify
// lays a row out after the unit that holds it (the player's header circles sat 24pt off until a tap
// laid the unit out again, trees/continuous/1.txt 2026-09-17). Takes no touches; made once per control
// under `key`, and made again when Reduce Transparency changes the kind of shape.
UIView *SGRGlassInside(UIView *control, const void *key, CGFloat side);

// The same, in a capsule `size` across rather than a circle: for the one control of an action row that
// leads (the playlist header's Play). `prominent` lays a white film inside the shape, so that control
// reads a step brighter than the circles beside it without leaving the same material.
UIView *SGRGlassCapsuleInside(UIView *control, const void *key, CGSize size, BOOL prominent);

// The control a shape backs when the shape is not that control's own subview but sits behind it in a holder of its own
// (Home's pill: the glass in a holder, the Filter button beside it): touch response follows that control's touches
// rather than the holder's. Held weakly; only an iOS 26 glass shape takes it, any other shape ignores it. Callers pass
// it on every pass they make the shape on, since the shape is made again when Reduce Transparency changes.
void SGRGlassBacks(UIView *shape, UIControl *control);

// Shows or hides a shape of the Kit's by its effect, never by an alpha on it or on a view above it
// (Redesigned/Player/PlayerMotion.x): UIKit draws the material wrongly or not at all under a fading alpha.
// The solid shape Reduce Transparency puts in its place has no effect and fades by its own alpha. Animates
// in the caller's animation.
void SGRShowGlass(UIView *shape, BOOL shown);

// Gives a shown glass shape its effect again, at once, for one that was on screen while a view above it faded by its
// alpha: UIKit then leaves the material undrawn after the fade though the effect is still set, and SGRShowGlass, which
// sets the effect only when it changes, never puts it back. Nothing for a hidden shape or a solid one.
void SGRRefreshGlass(UIView *shape);
