// The add button's glyph: Saved mark (Appearance), Spotify's circled tick on a saved song swapped for a plain
// checkmark or a filled dot in the accent, and Star add button (the Player page), the player's button as a star,
// outlined until the song is saved and filled in the accent once it is. In the player the star wins (SGRAddGlyphFor,
// SGRRefinements.h).
//
// The Add button (id=Components.UI.AddToButton, a UIButton) draws its state with a Lottie animation in a
// StateMicroInteractionView<AddToButtonState> (trees: player 1434-1436, the rows' buttons the same): a plus when the
// song is not saved, an accent circle with a tick when it is. Spotify marks a saved song's button selected ("Added to
// playlist"), so the button's own selected state tells which. Where a glyph of the Kit's stands in, the animation
// goes transparent; elsewhere Spotify's plus or tick shows as it is. The button stays Spotify's: its action, its
// selected state, its size and its accessibility; the glyph takes no touches and is no element. A disabled player's
// button goes back to Spotify's own glyph, which shows it disabled, and gets the star again once enabled.
//
// The player's button is the one inside the information unit's view, which answers to the unit as its next
// responder (PlayerLyrics.x finds the units the same way).
#import <objc/runtime.h>
#import "Core/SGCore.h"
#import "SGRKit.h"
#import "SGRRefinements.h"

static const CGFloat kCheckSize = 19, kDotSize = 10, kStarSize = 22;
static char kGlyphKey, kAnimationKey;

SGRSavedMark SGRSavedMarkChosen(void) {
    static SGRSavedMark mark;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ mark = SGRSavedMarkFrom(SGInt(SGRKeySavedMark, -1), SGHidden(SGRKeyPlainCheck)); });
    return mark;
}

BOOL SGRStarAddOn(void) {
    static BOOL on;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ on = SGHidden(SGRKeyPlayerStarAdd); });
    return on;
}

static BOOL inPlayer(UIView *button) {
    for (UIView *view = button; view; view = view.superview) {
        UIResponder *next = view.nextResponder;
        if ([next isKindOfClass:UIViewController.class] && [NSStringFromClass(next.class) hasSuffix:@"InformationElementsUnit"]) return YES;
    }
    return NO;
}

static UIImage *imageOf(SGRAddGlyph glyph) {
    BOOL check = glyph == SGRAddGlyphPlainCheck, dot = glyph == SGRAddGlyphDot;
    UIImageSymbolConfiguration *configuration = [UIImageSymbolConfiguration configurationWithPointSize:check ? kCheckSize : dot ? kDotSize : kStarSize
                                                                                                 weight:check ? UIImageSymbolWeightBold : UIImageSymbolWeightMedium];
    NSString *name = check ? @"checkmark" : dot ? @"circle.fill" : glyph == SGRAddGlyphStarFilled ? @"star.fill" : @"star";
    return [UIImage systemImageNamed:name withConfiguration:configuration];
}

static UIView *animationIn(UIButton *button) {
    static Class lottie;
    if (!lottie) lottie = NSClassFromString(@"Lottie.LottieAnimationView");
    if (!lottie) return nil;
    return SGFindRemembered(button, &kAnimationKey, ^BOOL(UIView *view) {
        return [view isKindOfClass:lottie] && view.superview.superview == button;
    });
}

static void showState(UIButton *button) {
    UIView *animation = animationIn(button);
    if (!animation) return;
    UIImageView *view = objc_getAssociatedObject(button, &kGlyphKey);
    SGRAddGlyph glyph = SGRAddGlyphFor(button.isSelected, button.isEnabled, SGRStarAddOn() && inPlayer(button), SGRStarAddOn(), SGRSavedMarkChosen());
    BOOL drawn = glyph != SGRAddGlyphSpotify;
    // A button that never had a glyph of the Kit's is left to Spotify.
    if (!drawn && !view) return;
    if (!view) {
        view = [UIImageView new];
        view.contentMode = UIViewContentModeCenter;
        view.userInteractionEnabled = NO;
        view.isAccessibilityElement = NO;
        objc_setAssociatedObject(button, &kGlyphKey, view, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (drawn) {
        view.image = imageOf(glyph);
        // The accent glyphs carry the identifier Follow the cover paints by, and are given the accent as they come in;
        // the star's outline is drawn in the primary color, as Spotify's plus is.
        BOOL accent = glyph != SGRAddGlyphStarOutline;
        BOOL wasAccent = [view.accessibilityIdentifier isEqualToString:SGRPlainCheckIdentifier];
        if (accent && !wasAccent) view.tintColor = SGRAccent();
        if (!accent) view.tintColor = SGRPrimary();
        view.accessibilityIdentifier = accent ? SGRPlainCheckIdentifier : nil;
    }
    if (view && view.superview != button) [button addSubview:view];
    view.frame = button.bounds;
    view.alpha = drawn ? 1 : 0;
    // Alpha, not hidden: Lottie's own state keeps running under it.
    animation.alpha = drawn ? 0 : 1;
}

%hook UIButton
- (void)layoutSubviews {
    %orig;
    if ([self.accessibilityIdentifier isEqualToString:@"Components.UI.AddToButton"]) showState(self);
}

- (void)setSelected:(BOOL)selected {
    %orig;
    if ([self.accessibilityIdentifier isEqualToString:@"Components.UI.AddToButton"]) showState(self);
}

- (void)setEnabled:(BOOL)enabled {
    %orig;
    if ([self.accessibilityIdentifier isEqualToString:@"Components.UI.AddToButton"]) showState(self);
}
%end

%ctor {
    if (!SGRedesignedUI() || !(SGRSavedMarkChosen() != SGRSavedMarkSpotify || SGRStarAddOn())) return;
    %init;
}
