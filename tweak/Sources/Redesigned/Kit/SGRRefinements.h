// Two small refinements of how Spotify's own player controls draw in the redesign, each one switch, read at launch:
//
//     the player's time labels roll only the characters that changed (SGRRollingDigits.m, over SGRRestyle.m's
//     monospaced labels; PlayerControls.x marks the two labels),
//     the player's add button as a star (SGRPlainCheck.x, which owns the add button's glyph, Saved mark's too).
//
// The decisions are plain functions (SGRRefinements.m, Foundation only) so harness/player-refinements runs them as
// they are; the views follow them.
//
// Threading: main thread only, but for the plain functions, which are pure.
#import <UIKit/UIKit.h>

#pragma mark - rolling time digits

// On until switched off (the Player page).
#define SGRKeyPlayerRollingDigits @"spotifyglass.redesign.player.rollingDigits"
// Two changes closer than this are a seek or a scrub, and the second shows at once.
extern const NSTimeInterval SGRDigitsSettleInterval;   // 0.15 s

typedef NS_ENUM(NSInteger, SGRDigitsChange) {
    SGRDigitsChangeNone,   // the same text again: nothing to draw
    SGRDigitsChangeJump,   // shown at once: the first value, a label just attached or detached, a seek or a scrub
    SGRDigitsChangeRoll,   // the changed characters roll up
    SGRDigitsChangeFade,   // the changed characters crossfade in place (Reduce Motion)
};
// How the label goes from `before` to `after`. `attached`: the label is in a window and was in the same one at the
// last change. `sinceLast`: seconds since the label's last change, a negative number when it had none.
SGRDigitsChange SGRDigitsChangeFor(NSString *before, NSString *after, BOOL attached, NSTimeInterval sinceLast, BOOL reduceMotion);
// The indexes of `after` that roll: the characters that differ from `before` at the same index, or every one of them
// when the lengths differ (the digits all move then).
NSIndexSet *SGRDigitsRolled(NSString *before, NSString *after);

// Makes the label's digits one width (SGRMonospacedDigits) and has every later change of its text that Spotify makes
// shown by SGRDigitsChangeFor. Idempotent. The text, the accessibility and the label's own drawing stay Spotify's: the
// rolling characters are drawn over it for the animation's length, in a view no accessibility sees. A text laid out
// right to left, wholly or in part (a directional mark, Arabic or Hebrew), never rolls: its change shows at once.
void SGRRollDigits(UILabel *label);
// Called by SGRRestyle.m's monospaced label after each of its text setters, with the text it had before (nil when it
// had none: the first value counts as a change too), and after it moved to a window or out of one: its next change
// then shows at once.
void SGRRollingDigitsTextChanged(UILabel *label, NSAttributedString *before);
void SGRRollingDigitsMovedToWindow(UILabel *label);
// Whether SGRRollDigits marked the label.
BOOL SGRRollingDigitsWatched(UILabel *label);

#pragma mark - the add button's glyph

// Off until switched on (the Player page). Wins over Saved mark in the player; Saved mark keeps the rest.
#define SGRKeyPlayerStarAdd @"spotifyglass.redesign.player.starAdd"
BOOL SGRStarAddOn(void);

// Saved mark (Appearance): what a saved song's add button shows, stored as the index. The unsaved plus stays Spotify's.
#define SGRKeySavedMark @"spotifyglass.redesign.savedMark"
typedef NS_ENUM(NSInteger, SGRSavedMark) {
    SGRSavedMarkSpotify,       // Spotify's circled tick
    SGRSavedMarkPlainCheck,    // a plain checkmark in the accent
    SGRSavedMarkDot,           // a filled dot in the accent
};
// The mark from what is stored under SGRKeySavedMark (`stored`, -1 when nothing is) and Plain checkmark's switch of
// before (SGRKeyPlainCheck, read and never written): a stored mark wins, and nothing stored or a value that is none of
// the marks keeps the old switch's choice, a plain checkmark when it was on and Spotify's when it was not.
SGRSavedMark SGRSavedMarkFrom(NSInteger stored, BOOL plainCheckOn);
// The mark the launch started with (SGRPlainCheck.x).
SGRSavedMark SGRSavedMarkChosen(void);

typedef NS_ENUM(NSInteger, SGRAddGlyph) {
    SGRAddGlyphSpotify,       // Spotify's own plus or circled tick
    SGRAddGlyphPlainCheck,    // a plain checkmark in the accent
    SGRAddGlyphDot,           // a filled dot in the accent
    SGRAddGlyphStarOutline,   // a star outline in the primary color
    SGRAddGlyphStarFilled,    // a filled star in the accent
};
// The glyph of an add button: `saved` is the button's own selected state, `enabled` its enabled state, `inPlayer`
// whether it is the player's. A disabled button the star would take is left to Spotify, whose own glyph shows it
// disabled.
SGRAddGlyph SGRAddGlyphFor(BOOL saved, BOOL enabled, BOOL inPlayer, BOOL starOn, SGRSavedMark savedMark);
