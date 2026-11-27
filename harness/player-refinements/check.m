// The player refinements of Redesigned/Kit/SGRRefinements.h, as a Mac Catalyst app; no simulator.
//
// Rolling time digits: the rules (SGRRefinements.m) and the real roll (SGRRollingDigits.m over SGRRestyle.m's monospaced
// label) on a label in a window: which characters roll, a change within 150 ms of the last shown at once, a label that
// moved into a window shown at once, the first value counted as a change, a right-to-left or mixed text shown at once,
// Reduce Motion a crossfade with no travel, the label's text and accessibility Spotify's. Star add button and Plain
// checkmark: the mapping and SGRPlainCheck.x through Logos on a player's and a row's add button, enabled and disabled.
//
// The launch arguments are the settings, read at launch as on the phone: `both` has Plain checkmark's old switch and
// Star add button on, `plain` the old switch alone (Saved mark unset, so it carries the switch's Plain checkmark),
// `dot` Saved mark's Dot stored beside the old switch, on. Reduce Motion and the accent are test
// doubles (the system's setting cannot be set from here); everything else is the tweak's own code.
#import <objc/runtime.h>
#import <CoreText/CoreText.h>
#import <CoreText/SFNTLayoutTypes.h>
#import <UIKit/UIKit.h>
#import "Redesigned/Kit/SGRRefinements.h"
#import "Redesigned/Kit/SGRAccent.h"
#import "Redesigned/Kit/SGRRestyle.h"
#import "Redesigned/Kit/SGRTokens.h"
#import "../harness-wait.h"

static NSUInteger sg_checks;
static BOOL sg_reduceMotion;
static NSString *sg_mode;

#define CHECK(condition, ...) do { sg_checks++; if (!(condition)) HARNESS_FAIL(__VA_ARGS__); } while (0)

#pragma mark - test doubles for the Kit around the code under test

BOOL SGRedesignedUI(void) { return YES; }
BOOL SGRReduceMotion(void) { return sg_reduceMotion; }
void SGRAnimate(SGRMotion motion, void (^animations)(void), void (^completion)(BOOL finished)) {
    [UIView animateWithDuration:SGRCrossfade animations:animations completion:completion];
}
const NSTimeInterval SGRCrossfade = 0.35;
const CGFloat SGRRadiusArtwork = 12;
UIColor *SGRPrimary(void) { return UIColor.whiteColor; }
UIColor *SGRSecondary(void) { return [UIColor colorWithWhite:1 alpha:0.65]; }
// The redesign's own green, in place of Spotify's.
UIColor *SGRAccent(void) { return [UIColor colorWithRed:0x37 / 255.0 green:0xF2 / 255.0 blue:0 alpha:1]; }
UIFont *SGMonospacedDigitsFont(UIFont *font) { return [UIFont monospacedDigitSystemFontOfSize:font.pointSize weight:UIFontWeightRegular]; }

#pragma mark - mocks of Spotify's classes

@interface _TtC20NowPlaying_ModesImpl23InformationElementsUnit : UIViewController @end
@implementation _TtC20NowPlaying_ModesImpl23InformationElementsUnit @end

static CFTimeInterval digitTime = 1000;
CFTimeInterval SGHarnessDigitsTime(void) { return digitTime; }
static void advanceDigits(NSTimeInterval seconds) { digitTime += seconds; }

#pragma mark - rolling time digits: the rules

static void checkDigitRules(void) {
    struct { NSString *before, *after; NSArray<NSNumber *> *rolled; } cases[] = {
        {@"1:09", @"1:10", @[@2, @3]},
        {@"1:10", @"1:11", @[@3]},
        {@"0:59", @"1:00", @[@0, @2, @3]},
        {@"9:59", @"10:00", @[@0, @1, @2, @3, @4]},
        {@"-3:21", @"-3:20", @[@4]},
        {@"-10:00", @"-9:59", @[@0, @1, @2, @3, @4]},
        {@"2:00", @"2:00", @[]},
    };
    for (size_t i = 0; i < sizeof cases / sizeof *cases; i++) {
        NSMutableArray<NSNumber *> *got = [NSMutableArray array];
        [SGRDigitsRolled(cases[i].before, cases[i].after) enumerateIndexesUsingBlock:^(NSUInteger index, BOOL *stop) { [got addObject:@(index)]; }];
        CHECK([got isEqualToArray:cases[i].rolled], @"%@ -> %@ rolls %@, want %@", cases[i].before, cases[i].after, got, cases[i].rolled);
    }

    struct { NSString *before, *after; BOOL attached; NSTimeInterval since; BOOL reduce; SGRDigitsChange want; NSString *what; } rules[] = {
        {@"1:09", @"1:09", YES, 1, NO, SGRDigitsChangeNone, @"unchanged"},
        {@"", @"0:00", YES, -1, NO, SGRDigitsChangeJump, @"first value"},
        {@"1:09", @"1:10", NO, 1, NO, SGRDigitsChangeJump, @"just attached"},
        {@"1:09", @"2:45", YES, 0.016, NO, SGRDigitsChangeJump, @"a scrub's frame"},
        {@"1:09", @"1:10", YES, 0.149, NO, SGRDigitsChangeJump, @"149 ms after the last"},
        {@"1:09", @"1:10", YES, 0.15, NO, SGRDigitsChangeRoll, @"150 ms after the last"},
        {@"1:09", @"1:10", YES, 1, NO, SGRDigitsChangeRoll, @"a second's tick"},
        {@"1:09", @"1:10", YES, -1, NO, SGRDigitsChangeRoll, @"no change before"},
        {@"1:09", @"1:10", YES, 1, YES, SGRDigitsChangeFade, @"Reduce Motion"},
        {@"1:09", @"1:10", YES, 0.05, YES, SGRDigitsChangeJump, @"Reduce Motion, a scrub"},
    };
    for (size_t i = 0; i < sizeof rules / sizeof *rules; i++) {
        SGRDigitsChange got = SGRDigitsChangeFor(rules[i].before, rules[i].after, rules[i].attached, rules[i].since, rules[i].reduce);
        CHECK(got == rules[i].want, @"rule %@: got %ld, want %ld", rules[i].what, (long)got, (long)rules[i].want);
    }
}

#pragma mark - rolling time digits: the label

// The overlay SGRRollingDigits.m lays over the label, nil when none.
static UIView *overlayOver(UILabel *label) {
    NSArray<UIView *> *siblings = label.superview.subviews;
    NSUInteger index = [siblings indexOfObject:label];
    return index + 1 < siblings.count ? siblings[index + 1] : nil;
}

// The characters coming in (those ending visible) and going out.
static void glyphsOf(UIView *overlay, NSMutableString *incoming, NSMutableString *outgoing) {
    for (UIView *glyph in overlay.subviews) [(glyph.alpha > 0.5 ? incoming : outgoing) appendString:glyph.accessibilityLabel];
}

// Compare a warmed column to the original UILabel drawing at Core Text's actual
// advance, not to another copy of the cached image.
static void checkDigitPixels(UILabel *label, UIImage *cached) {
    NSAttributedString *text = label.attributedText;
    CTLineRef line = CTLineCreateWithAttributedString((__bridge CFAttributedStringRef)text);
    NSUInteger index = text.length - 1;
    CGFloat width = CTLineGetOffsetForStringIndex(line, index + 1, NULL) - CTLineGetOffsetForStringIndex(line, index, NULL);
    CFRelease(line);
    UILabel *reference = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, width + 2, label.bounds.size.height)];
    reference.font = label.font;
    reference.textColor = label.textColor;
    reference.attributedText = [text attributedSubstringFromRange:NSMakeRange(index, 1)];
    reference.textAlignment = NSTextAlignmentLeft;
    reference.lineBreakMode = NSLineBreakByClipping;
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat preferredFormat];
    format.scale = label.window.screen.scale;
    reference.contentScaleFactor = format.scale;
    UIImage *want = [[[UIGraphicsImageRenderer alloc] initWithSize:reference.bounds.size format:format]
        imageWithActions:^(UIGraphicsImageRendererContext *ctx) { [reference.layer renderInContext:ctx.CGContext]; }];
    CHECK(cached && [UIImagePNGRepresentation(cached) isEqual:UIImagePNGRepresentation(want)], @"digit pixels differ from UILabel");
}

// The label says what Spotify set, and accessibility reads it as from a label of UIKit's own given the same text.
static void expectSpotifysText(UILabel *label, NSString *text, NSString *what) {
    UILabel *reference = [UILabel new];
    reference.text = text;
    BOOL same = [label.text isEqualToString:text]
        && (label.accessibilityLabel == reference.accessibilityLabel || [label.accessibilityLabel isEqualToString:reference.accessibilityLabel])
        && (label.accessibilityValue == reference.accessibilityValue || [label.accessibilityValue isEqualToString:reference.accessibilityValue])
        && label.isAccessibilityElement == reference.isAccessibilityElement;
    CHECK(same, @"%@: the label says \"%@\", accessibility \"%@\" / \"%@\", want \"%@\"", what, label.text, label.accessibilityLabel,
          label.accessibilityValue, text);
}

static void expectRoll(UILabel *label, NSString *text, NSString *wantIn, NSString *wantOut, BOOL travels, NSString *what) {
    label.text = text;
    UIView *overlay = overlayOver(label);
    CHECK(overlay != nil, @"%@: nothing rolls", what);
    CHECK(label.layer.mask != nil, @"%@: the label's changed columns are not masked", what);
    CHECK(overlay.accessibilityElementsHidden && !overlay.isAccessibilityElement && !overlay.userInteractionEnabled,
          @"%@: the overlay is reachable", what);
    NSMutableString *incoming = [NSMutableString string], *outgoing = [NSMutableString string];
    glyphsOf(overlay, incoming, outgoing);
    CHECK([incoming isEqualToString:wantIn], @"%@: rolls in \"%@\", want \"%@\"", what, incoming, wantIn);
    CHECK([outgoing isEqualToString:wantOut], @"%@: rolls out \"%@\", want \"%@\"", what, outgoing, wantOut);
    for (UIView *glyph in overlay.subviews) {
        BOOL moving = [glyph.layer animationForKey:@"transform"] != nil;
        CHECK(moving == travels, @"%@: \"%@\" %@", what, glyph.accessibilityLabel, travels ? @"does not travel" : @"travels under Reduce Motion");
        CHECK([glyph.layer animationForKey:@"opacity"] != nil, @"%@: \"%@\" does not fade", what, glyph.accessibilityLabel);
    }
    expectSpotifysText(label, text, what);
}

static void expectJump(UILabel *label, NSString *text, NSString *what) {
    label.text = text;
    CHECK(overlayOver(label) == nil, @"%@: rolled", what);
    CHECK(label.layer.mask == nil, @"%@: the label is still masked", what);
    expectSpotifysText(label, text, what);
}

@interface TimeLabel : UILabel
@property (nonatomic) NSUInteger writes;
@property (nonatomic) NSUInteger attributedReads;
- (void)replaceBehindSetter;
- (void)recolorBehindSetter;
@end
@implementation TimeLabel
- (NSAttributedString *)attributedText { self.attributedReads++; return super.attributedText; }
- (void)setText:(NSString *)text { self.writes++; [super setText:text]; }
- (void)setAttributedText:(NSAttributedString *)text { self.writes++; [super setAttributedText:text]; }
- (void)replaceBehindSetter { [super setAttributedText:[[NSAttributedString alloc] initWithString:@"changed"]]; }
- (void)recolorBehindSetter {
    [super setAttributedText:[[NSAttributedString alloc] initWithString:self.text attributes:@{NSForegroundColorAttributeName:UIColor.orangeColor}]];
}
@end

static void checkRollingLabel(UIWindow *window) {
    UIView *host = [[UIView alloc] initWithFrame:CGRectMake(20, 100, 200, 40)];
    [window addSubview:host];
    TimeLabel *label = [[TimeLabel alloc] initWithFrame:CGRectMake(0, 10, 80, 20)];
    label.font = [UIFont systemFontOfSize:12];
    label.accessibilityIdentifier = @"now-playing-time-take-label-internal";
    [host addSubview:label];
    SGRRollDigits(label);
    CHECK(SGRRollingDigitsWatched(label), @"the label is not watched");

    expectJump(label, @"1:30", @"the first value");
    expectJump(label, @"0:00", @"a scrub right after the first value");
    advanceDigits(0.2);
    expectRoll(label, @"0:01", @"1", @"0", YES, @"0:00 -> 0:01");
    advanceDigits(0.020);
    expectJump(label, @"1:45", @"a seek 20 ms later");
    expectJump(label, @"1:46", @"the scrub's next frame");
    advanceDigits(0.2);
    expectRoll(label, @"1:47", @"7", @"6", YES, @"1:46 -> 1:47");
    UIView *first = overlayOver(label).subviews.firstObject;
    UIImage *seven = [first isKindOfClass:UIImageView.class] ? [(UIImageView *)first image] : nil;
    if (seven) checkDigitPixels(label, seven);
    advanceDigits(0.2);
    extern NSUInteger harnessShapedLines;
    NSUInteger shaped = harnessShapedLines;
    expectRoll(label, @"1:50", @"50", @"47", YES, @"1:47 -> 1:50");
    CHECK(shaped == harnessShapedLines, @"unchanged tabular columns shaped again");
    CHECK(seven && seven == [(UIImageView *)overlayOver(label).subviews.lastObject image], @"7 was rasterized twice");
    advanceDigits(0.2);
    // The roll before is still running: it is finished first, and this one stands alone.
    expectRoll(label, @"1:59", @"9", @"0", YES, @"1:50 -> 1:59");
    advanceDigits(0.2);
    expectRoll(label, @"2:00", @"200", @"159", YES, @"1:59 -> 2:00");
    advanceDigits(0.2);
    expectRoll(label, @"10:00", @"10:00", @"2:00", YES, @"2:00 -> 10:00 (length changes)");
    // The same text again, while that roll runs: nothing new, and the roll goes on.
    UIView *running = overlayOver(label);
    NSUInteger writes = label.writes;
    label.attributedReads = 0;
    for (NSUInteger i = 0; i < 24; i++) label.text = @"10:00";
    CHECK(!label.attributedReads, @"repeat read synthesized attributed text");
    CHECK(writes == label.writes, @"repeat reached the plain text setter");
    CHECK(running && overlayOver(label) == running && label.layer.mask, @"the same text again cut the running roll short");

    // Out of the window and back: the next value shows at once, the one after rolls.
    [label removeFromSuperview];
    CHECK(label.layer.mask == nil && overlayOver(label) == nil, @"leaving the window kept the roll");
    [host addSubview:label];
    advanceDigits(0.2);
    expectJump(label, @"10:01", @"the first change after attaching");
    advanceDigits(0.2);
    expectRoll(label, @"10:02", @"2", @"1", YES, @"10:01 -> 10:02 after attaching");

    // Off any window, nothing rolls.
    [label removeFromSuperview];
    UIView *loose = [UIView new];
    [loose addSubview:label];
    advanceDigits(0.2);
    expectJump(label, @"10:03", @"a label in no window");
    [label removeFromSuperview];
    [host addSubview:label];
    advanceDigits(0.2);
    expectJump(label, @"10:04", @"back in the window");

    sg_reduceMotion = YES;
    advanceDigits(0.2);
    expectRoll(label, @"10:05", @"5", @"4", NO, @"Reduce Motion crossfades");
    sg_reduceMotion = NO;

    // Right to left (a right-to-left mark before Arabic digits) and mixed (a Hebrew letter after the time): shown at
    // once, going in, between two such texts, and going out; a plain time rolls again after.
    advanceDigits(0.2);
    expectJump(label, @"\u200F-\u0663:\u0662\u0661", @"to a right-to-left text");
    advanceDigits(0.2);
    expectJump(label, @"\u200F-\u0663:\u0662\u0660", @"a right-to-left text's change");
    advanceDigits(0.2);
    expectJump(label, @"-3:21 \u05D0", @"to a mixed text");
    advanceDigits(0.2);
    expectJump(label, @"-3:20 \u05D0", @"a mixed text's change");
    advanceDigits(0.2);
    expectJump(label, @"-3:19", @"from a mixed text");
    advanceDigits(0.2);
    expectRoll(label, @"-3:18", @"8", @"9", YES, @"-3:19 -> -3:18 after them");

    // A label not marked keeps its digits one width and never rolls.
    UILabel *plain = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 80, 20)];
    [host addSubview:plain];
    plain.text = @"0:01";
    SGRMonospacedDigits(plain);
    advanceDigits(0.2);
    expectJump(plain, @"0:02", @"an unmarked label");
    NSAttributedString *given = [[NSAttributedString alloc] initWithString:@"1:23" attributes:@{NSFontAttributeName: [UIFont systemFontOfSize:13]}];
    label.attributedText = given;
    writes = label.writes;
    label.attributedText = given;
    CHECK(writes == label.writes, @"repeat reached the attributed setter");
    [label replaceBehindSetter];
    label.attributedText = given;
    CHECK([label.text isEqualToString:@"1:23"], @"repeat failed to repair an external edit");
    [label recolorBehindSetter];
    label.attributedText = given;
    CHECK(![[label.attributedText attribute:NSForegroundColorAttributeName atIndex:0 effectiveRange:NULL] isEqual:UIColor.orangeColor],
          @"external same-text attribute edit was not repaired");
    label.font = [UIFont systemFontOfSize:18];
    label.overrideUserInterfaceStyle = UIUserInterfaceStyleLight;
    advanceDigits(.3);
    expectRoll(label, @"1:27", @"7", @"3", YES, @"font and appearance changed");
    UIImage *resized = [(UIImageView *)overlayOver(label).subviews.firstObject image];
    CHECK(resized != seven, @"old style's bitmap reused");
    checkDigitPixels(label, resized);
    // The request survives in the descriptor even though this face has no equal-width figures.
    UIFont *face = [UIFont fontWithName:@"KohinoorDevanagari-Regular" size:22];
    CHECK(face != nil, @"missing proportional-digit fixture");
    UIFont *requested = [UIFont fontWithDescriptor:[face.fontDescriptor fontDescriptorByAddingAttributes:@{
        UIFontDescriptorFeatureSettingsAttribute:@[@{UIFontFeatureTypeIdentifierKey:@(kNumberSpacingType),
                                                      UIFontFeatureSelectorIdentifierKey:@(kMonospacedNumbersSelector)}]}] size:22];
    NSDictionary *style = @{NSFontAttributeName:requested};
    CHECK([@"8" sizeWithAttributes:style].width > [@"1" sizeWithAttributes:style].width, @"fixture digits are not proportional");
    for (NSString *time in @[@"0:11", @"1:11", @"1:18"]) {
        advanceDigits(.3);
        label.attributedText = [[NSAttributedString alloc] initWithString:time attributes:style];
    }
    UIImageView *eight = (UIImageView *)overlayOver(label).subviews.firstObject;
    NSDictionary *installed = [label.attributedText attributesAtIndex:3 effectiveRange:NULL];
    CHECK([@"8" sizeWithAttributes:installed].width > [@"1" sizeWithAttributes:installed].width,
          @"label lost the fixture's proportional digits: %@", installed);
    CHECK([eight.accessibilityLabel isEqual:@"8"], @"proportional 8 did not roll");
    checkDigitPixels(label, eight.image);
    [host removeFromSuperview];
}

#pragma mark - the add button

static void checkAddMapping(void) {
    const SGRSavedMark spotify = SGRSavedMarkSpotify, plain = SGRSavedMarkPlainCheck, dot = SGRSavedMarkDot;
    struct { BOOL saved, enabled, player, star; SGRSavedMark mark; SGRAddGlyph want; NSString *what; } cases[] = {
        {NO, YES, YES, YES, spotify, SGRAddGlyphStarOutline, @"player, unsaved, star"},
        {YES, YES, YES, YES, spotify, SGRAddGlyphStarFilled, @"player, saved, star"},
        {YES, YES, YES, YES, plain, SGRAddGlyphStarFilled, @"player, saved, star and plain check: star wins"},
        {NO, YES, YES, YES, plain, SGRAddGlyphStarOutline, @"player, unsaved, star and plain check: star wins"},
        {YES, YES, YES, YES, dot, SGRAddGlyphStarFilled, @"player, saved, star and dot: star wins"},
        {NO, NO, YES, YES, spotify, SGRAddGlyphSpotify, @"player, unsaved, star, disabled"},
        {YES, NO, YES, YES, plain, SGRAddGlyphSpotify, @"player, saved, star and plain check, disabled"},
        {YES, YES, NO, YES, plain, SGRAddGlyphPlainCheck, @"row, saved, both: plain check keeps the rows"},
        {YES, YES, NO, YES, dot, SGRAddGlyphDot, @"row, saved, star and dot: the dot keeps the rows"},
        {NO, YES, NO, YES, plain, SGRAddGlyphSpotify, @"row, unsaved, both"},
        {YES, YES, NO, YES, spotify, SGRAddGlyphSpotify, @"row, saved, star only"},
        {YES, YES, YES, NO, plain, SGRAddGlyphPlainCheck, @"player, saved, plain check only"},
        {NO, YES, YES, NO, plain, SGRAddGlyphSpotify, @"player, unsaved, plain check only"},
        {YES, YES, YES, NO, dot, SGRAddGlyphDot, @"player, saved, dot only"},
        {NO, YES, NO, NO, dot, SGRAddGlyphSpotify, @"row, unsaved, dot: Spotify's plus"},
        {YES, YES, YES, NO, spotify, SGRAddGlyphSpotify, @"player, saved, neither"},
    };
    for (size_t i = 0; i < sizeof cases / sizeof *cases; i++) {
        SGRAddGlyph got = SGRAddGlyphFor(cases[i].saved, cases[i].enabled, cases[i].player, cases[i].star, cases[i].mark);
        CHECK(got == cases[i].want, @"add glyph %@: got %ld, want %ld", cases[i].what, (long)got, (long)cases[i].want);
    }
}

// Spotify's add button: a UIButton whose Lottie animation sits in a child view.
static UIButton *addButton(UIView *host, UIView **animation) {
    static Class lottie;
    if (!lottie) {
        lottie = objc_allocateClassPair(UIView.class, "Lottie.LottieAnimationView", 0);
        objc_registerClassPair(lottie);
    }
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    button.frame = CGRectMake(0, 0, 48, 48);
    button.accessibilityIdentifier = @"Components.UI.AddToButton";
    button.accessibilityLabel = @"Add to Liked Songs";
    UIView *state = [[UIView alloc] initWithFrame:button.bounds];
    state.userInteractionEnabled = NO;
    *animation = [[lottie alloc] initWithFrame:state.bounds];
    [state addSubview:*animation];
    [button addSubview:state];
    [host addSubview:button];
    return button;
}

// The button has no image of its own, so its one image view is the Kit's glyph.
static UIImageView *glyphIn(UIButton *button) {
    for (UIView *view in button.subviews) {
        if ([view isKindOfClass:UIImageView.class]) return (UIImageView *)view;
    }
    return nil;
}

// What the button shows as it is, with no layout pass: "spotify" (the animation), or the symbol of the Kit's glyph,
// with its tint's name.
static NSString *shownNow(UIButton *button, UIView *animation) {
    UIImageView *glyph = glyphIn(button);
    BOOL drawn = glyph && glyph.alpha > 0.5;
    if (drawn == (animation.alpha > 0.5)) HARNESS_FAIL(@"the glyph and Spotify's animation both %@", drawn ? @"show" : @"hide");
    if (!drawn) return @"spotify";
    if (glyph.userInteractionEnabled || glyph.isAccessibilityElement) HARNESS_FAIL(@"the glyph takes touches or is an element");
    NSString *name = [glyph.image.description containsString:@"star.fill"] ? @"star.fill"
                   : [glyph.image.description containsString:@"star"] ? @"star"
                   : [glyph.image.description containsString:@"checkmark"] ? @"checkmark"
                   : [glyph.image.description containsString:@"circle.fill"] ? @"dot" : glyph.image.description;
    BOOL accent = [glyph.tintColor isEqual:SGRAccent()] && [glyph.accessibilityIdentifier isEqualToString:SGRPlainCheckIdentifier];
    // UIKit can expose the symbol's identifier when the view's own identifier is unset.
    UIImageView *reference = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"star"]];
    reference.accessibilityIdentifier = nil;
    BOOL unmarked = glyph.accessibilityIdentifier == reference.accessibilityIdentifier
        || [glyph.accessibilityIdentifier isEqualToString:reference.accessibilityIdentifier];
    BOOL primary = [glyph.tintColor isEqual:SGRPrimary()] && unmarked;
    return [name stringByAppendingString:accent ? @" accent" : primary ? @" primary" : @" ?"];
}

// What the button shows after its next layout pass.
static NSString *shown(UIButton *button, UIView *animation) {
    [button setNeedsLayout];
    [button layoutIfNeeded];
    return shownNow(button, animation);
}

static void expectShown(UIButton *button, UIView *animation, BOOL saved, NSString *want, NSString *what) {
    CGRect frame = button.frame;
    button.selected = saved;
    NSString *got = shown(button, animation);
    CHECK([got isEqualToString:want], @"%@: shows %@, want %@ (tint %@, primary %@, identifier %@)", what, got, want,
          glyphIn(button).tintColor, SGRPrimary(), glyphIn(button).accessibilityIdentifier);
    CHECK(button.isSelected == saved && CGRectEqualToRect(button.frame, frame) && [button.accessibilityLabel isEqualToString:@"Add to Liked Songs"]
          && button.userInteractionEnabled, @"%@: the button is no longer Spotify's", what);
}

static void checkAddButtons(UIWindow *window) {
    _TtC20NowPlaying_ModesImpl23InformationElementsUnit *unit = [_TtC20NowPlaying_ModesImpl23InformationElementsUnit new];
    unit.view.frame = CGRectMake(0, 200, 300, 60);
    [window addSubview:unit.view];
    UIView *titleRow = [[UIView alloc] initWithFrame:unit.view.bounds];
    [unit.view addSubview:titleRow];
    UIView *playerAnimation, *rowAnimation;
    UIButton *player = addButton(titleRow, &playerAnimation);
    UIView *row = [[UIView alloc] initWithFrame:CGRectMake(0, 300, 300, 60)];
    [window addSubview:row];
    UIButton *rowButton = addButton(row, &rowAnimation);

    BOOL star = [sg_mode isEqualToString:@"both"];
    // `dot` stores Saved mark's Dot beside Plain checkmark's old switch, on: the stored mark wins.
    NSString *mark = [sg_mode isEqualToString:@"dot"] ? @"dot accent" : @"checkmark accent";
    expectShown(player, playerAnimation, NO, star ? @"star primary" : @"spotify", @"the player's button, unsaved");
    expectShown(player, playerAnimation, YES, star ? @"star.fill accent" : mark, @"the player's button, saved");
    expectShown(player, playerAnimation, NO, star ? @"star primary" : @"spotify", @"the player's button, unsaved again");
    // Disabled: Spotify's own glyph, which shows it disabled, in place of the star, at once (no layout pass); the
    // star again once enabled.
    player.enabled = NO;
    NSString *got = shownNow(player, playerAnimation);
    CHECK([got isEqualToString:@"spotify"], @"the player's button, disabled: shows %@", got);
    player.selected = YES;
    NSString *want = star ? @"spotify" : mark;
    got = shownNow(player, playerAnimation);
    CHECK([got isEqualToString:want], @"the player's button, saved and disabled: shows %@, want %@", got, want);
    CHECK([shown(player, playerAnimation) isEqualToString:want], @"the player's button, saved and disabled, laid out: changed");
    player.enabled = YES;
    want = star ? @"star.fill accent" : mark;
    got = shownNow(player, playerAnimation);
    CHECK([got isEqualToString:want], @"the player's button, enabled again: shows %@, want %@", got, want);
    expectShown(rowButton, rowAnimation, YES, mark, @"a row's button, saved");
    expectShown(rowButton, rowAnimation, NO, @"spotify", @"a row's button, unsaved");
    // A song saved again after it was unsaved gets the mark back.
    expectShown(rowButton, rowAnimation, YES, mark, @"a row's button, saved again");
    // Reuse can replace the whole state view while the old animation still has a superview.
    UIView *oldState = rowAnimation.superview;
    [oldState removeFromSuperview];
    UIView *replacement = [[rowAnimation.class alloc] initWithFrame:rowButton.bounds];
    UIView *newState = [[UIView alloc] initWithFrame:rowButton.bounds];
    [newState addSubview:replacement];
    [rowButton addSubview:newState];
    expectShown(rowButton, replacement, YES, mark, @"a reused row with a new state view");
    CHECK(rowAnimation.superview == oldState, @"reuse fixture lost the detached state view");
    [unit.view removeFromSuperview];
    [row removeFromSuperview];
}

#pragma mark - the app

static void run(UIWindow *window) {
    checkDigitRules();
    // Hold the concrete weak-table method only for this check. After detachment
    // alpha/hidden must not even snapshot an empty subscriber list.
    UIView *branch = [UIView new], *child = [UIView new];
    [branch addSubview:child];
    __block NSUInteger calls = 0;
    SGRObserveVisibility(child, ^{ calls++; });
    NSHashTable *sample = [NSHashTable weakObjectsHashTable];
    Method snapshot = class_getInstanceMethod(object_getClass(sample), @selector(allObjects));
    IMP old = method_getImplementation(snapshot);
    __block NSUInteger snapshots = 0;
    method_setImplementation(snapshot, imp_implementationWithBlock(^NSArray *(id table) {
        snapshots++;
        return ((id (*)(id, SEL))old)(table, @selector(allObjects));
    }));
    branch.alpha = .9;
    CHECK(calls && snapshots, @"observed ancestor not reported");
    SGRObserveVisibility(child, nil);
    snapshots = 0;
    for (NSUInteger i = 0; i < 24; i++) branch.hidden = i % 2;
    method_setImplementation(snapshot, old);
    CHECK(!snapshots, @"detached branch enumerated weak tables");
    checkAddMapping();
    if ([sg_mode isEqualToString:@"both"]) checkRollingLabel(window);
    checkAddButtons(window);
    printf("[harness] player-refinements %s: %lu checks passed\n", sg_mode.UTF8String, (unsigned long)sg_checks);
    fflush(stdout);
    exit(0);
}

@interface PlayerRefinementsApp : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation PlayerRefinementsApp
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    self.window = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, 390, 844)];
    self.window.rootViewController = [UIViewController new];
    HarnessWhen(@"player refinements window joined its scene", ^BOOL { return self.window.windowScene != nil; }, ^{
        run(self.window);
    });
    return YES;
}
@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        sg_mode = [NSUserDefaults.standardUserDefaults stringForKey:@"harness.mode"];
        if (![@[@"both", @"plain", @"dot"] containsObject:sg_mode ?: @""]) {
            fprintf(stderr, "usage: -harness.mode both|plain|dot with the settings as launch arguments\n");
            return 2;
        }
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(PlayerRefinementsApp.class));
    }
}
