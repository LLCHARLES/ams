// What the Logos files hold for the page: the accent colors as Accent.x and SGRAccent.x read them, and the
// font choice as Fonts.x reads it. And the two tokens the glass rows' SGRGlass.m links against, as SGRTokens.m has them.
#import "Core/SGCore.h"
#import "Native/Appearance/Appearance.h"
#import "Redesigned/Kit/SGRAccent.h"
#import "Redesigned/Kit/SGRTokens.h"
#import "Shared/Fonts/Fonts.h"

BOOL SGRReduceTransparency(void) { return UIAccessibilityIsReduceTransparencyEnabled(); }
UIColor *SGRSolidGlassFill(void) { return [UIColor colorWithWhite:1 alpha:0.16]; }

static NSInteger valid(NSInteger rgb) {
    return rgb >= 0 && rgb <= 0xFFFFFF ? rgb : -1;
}

NSInteger SGAccentRGB(void) { NSInteger rgb = valid(SGInt(SGKeyAccent, -1)); return rgb < 0 ? SGSpotifyGreen : rgb; }
UIColor *SGRAccentColor(void) { return valid(SGInt(SGRKeyAccent, SGRDefaultAccent)) < 0 ? nil : UIColor.redColor; }
NSInteger SGRAccentRGB(void) { NSInteger rgb = valid(SGInt(SGRKeyAccent, SGRDefaultAccent)); return rgb < 0 ? SGSpotifyGreen : rgb; }
NSInteger SGRPickedAccentRGB(void) { return SGRAccentRGB(); }
void SGRAccentPreferencesChanged(void) {}
void SGRefreshExplicitBadges(void) {}
void SGRRefreshExplicitBadges(void) {}

SGAppFont SGAppFontChosen(void) {
    NSInteger font = SGInt(SGKeyAppFont, SGAppFontSpotify);
    return font >= SGAppFontSpotify && font <= SGAppFontLibrary ? font : SGAppFontSpotify;
}

NSArray<NSString *> *SGAppFontNames(void) {
    return @[@"Default", @"San Francisco", @"SF Rounded", @"New York", @"SF Mono"];
}

NSArray<NSString *> *SGAppFontFamilies(void) {
    return @[@"Avenir Next", @"Georgia"];
}
