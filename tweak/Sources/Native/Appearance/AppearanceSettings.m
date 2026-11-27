#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Settings/SGPageStyle.h"
#import "Appearance.h"

// The preset is read off the color stored, so the hooks keep the one key they read and a color set before
// presets existed stays in effect: Apple Music's red reads as Apple Music, any other color as Custom, none
// as Spotify. The custom color is put aside while a preset is in place, so Custom brings it back.
static NSArray<NSString *> *presets(void) {
    return @[@"Spotify", @"Apple Music", SGL(@"settings.appearance.accent_preset.choice.custom", @"Custom")];
}

static NSInteger preset(void) {
    NSInteger rgb = SGInt(SGKeyAccent, -1);
    if (rgb < 0 || rgb > 0xFFFFFF) return 0;
    return rgb == SGAppleMusicRed ? 1 : 2;
}

static void choosePreset(NSInteger index) {
    if (preset() == 2) SGSetInt(SGKeyAccentCustom, SGInt(SGKeyAccent, -1));
    NSInteger custom = SGInt(SGKeyAccentCustom, SGSpotifyGreen);
    if (custom < 0 || custom > 0xFFFFFF) custom = SGSpotifyGreen;
    SGSetInt(SGKeyAccent, index == 0 ? -1 : index == 1 ? SGAppleMusicRed : custom);
}

// A color from the sheet, a swatch's or the picker's: Custom, and first among the recent colors when it is another.
static void chooseColor(NSInteger rgb) {
    NSUserDefaults *store = NSUserDefaults.standardUserDefaults;
    NSArray<NSNumber *> *recent = SGAccentRecentFrom([store objectForKey:SGKeyAccentRecent]);
    [store setObject:SGAccentRecentAdding(recent, rgb, SGAccentRGB()) forKey:SGKeyAccentRecent];
    SGSetInt(SGKeyAccent, rgb);
    SGSetInt(SGKeyAccentCustom, rgb);
}

// The native look's rows of the Appearance page (App/Pages.m): the preset from a menu, then the color in
// effect, which opens the sheet of recent colors and the picker; a color stored from there is Custom.
NSArray<SGModSection *> *SGNativeAppearanceSections(void) {
    SGModRow *explicit = SGOptionRow(SGL(@"settings.appearance.hide_explicit.title", @"Hide explicit badge"),
        SGL(@"settings.appearance.hide_explicit.subtitle", @"Hide the E mark, without changing content restrictions or VoiceOver"), SGKeyHideExplicit);
    explicit.changed = ^(BOOL on) { SGRefreshExplicitBadges(); };
    SGModRow *menu = SGMenuRow(SGL(@"settings.appearance.accent_preset.title", @"Accent color preset"), presets(), ^NSString *{ return presets()[(NSUInteger)preset()]; },
                               ^(NSInteger index) { choosePreset(index); });
    SGModRow *colour = SGStatActionRow(SGL(@"settings.appearance.accent_color.title", @"Accent color"), nil, ^NSString *{ return [NSString stringWithFormat:@"#%06lX", (long)SGAccentRGB()]; }, ^{
        SGPickAccent(SGL(@"settings.appearance.accent_color.title", @"Accent color"), SGAccentRGB(),
                     SGAccentRecentFrom([NSUserDefaults.standardUserDefaults objectForKey:SGKeyAccentRecent]), ^(NSInteger rgb) { chooseColor(rgb); });
    });
    colour.swatch = ^UIColor *{ return SGColorRGB(SGAccentRGB()); };
    return @[
        SGSection(SGL(@"settings.appearance.theme.header", @"Theme"), @[
            SGWithSymbol(SGOptionRow(SGL(@"settings.appearance.amoled_background.title", @"AMOLED background"), nil, SGKeyAmoled), @"moon")]),
        SGSection(SGL(@"settings.appearance.accent.header", @"Accent"), @[
            SGWithSymbol(SGSearchIdentified(menu, @"menu.native.accentPreset"), @"paintpalette"),
            SGWithSymbol(SGSearchIdentified(colour, SGKeyAccent), @"eyedropper")]),
        SGSection(SGL(@"settings.appearance.pages.header", @"Pages & badges"), @[SGWithSymbol(explicit, @"e.square")]),
    ];
}
