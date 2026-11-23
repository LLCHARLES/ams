#import "Settings/SGModPage.h"
#import "Core/SGPrefs.h"
#import "Native/Appearance/Appearance.h"
#import "Redesigned/Kit/SGRAccent.h"
#import "Redesigned/Kit/SGRGlass.h"
#import "Redesigned/Kit/SGRRefinements.h"
#import "../harness-fail.h"

@implementation SGModRow @end
// In-memory settings boundary: row callbacks are real, no shared preferences domain is written.
static NSMutableDictionary *values;
NSInteger SGInt(NSString *key, NSInteger fallback) { return values[key] ? [values[key] integerValue] : fallback; }
BOOL SGFlag(NSString *key, BOOL fallback) { return values[key] ? [values[key] boolValue] : fallback; }
BOOL SGEnabled(NSString *key) { return SGFlag(key, YES); }
BOOL SGHidden(NSString *key) { return SGFlag(key, NO); }
SGModRow *SGSearchIdentified(SGModRow *row, NSString *identifier) { row.searchIdentifier = identifier; return row; }
// What SGRGlass.m draws with; the rows only read and store the choices.
UIVisualEffect *SGGlassEffect(void) { return nil; }
void SGShapeGlass(UIView *glass, CGFloat radius, BOOL capsule) {}
BOOL SGRReduceTransparency(void) { return NO; }
BOOL SGRedesignedUI(void) { return YES; }
UIColor *SGRSolidGlassFill(void) { return UIColor.clearColor; }
void SGSetInt(NSString *key, NSInteger value) { values[key] = @(value); }
void SGSetEnabled(NSString *key, BOOL on) { values[key] = @(on); }
void SGPrefsChanged(void) {}
NSString *SGL(NSString *key, NSString *english) { return english; }
SGModRow *SGMenuRow(NSString *title, NSArray *choices, NSString *(^value)(void), void (^chosen)(NSInteger)) {
    SGModRow *row = [SGModRow new]; row.title = title; row.menu = choices; row.value = value; row.chosen = chosen; return row;
}
SGModRow *SGStatActionRow(NSString *title, NSString *subtitle, NSString *(^value)(void), void (^action)(void)) {
    SGModRow *row = [SGModRow new]; row.title = title; row.value = value; row.action = action; return row;
}
SGModRow *SGSwitchRow(NSString *title, NSString *subtitle, NSString *key) {
    SGModRow *row = [SGModRow new]; row.title = title; row.subtitle = subtitle; row.key = key; row.defaultOn = YES; return row;
}
SGModRow *SGOptionRow(NSString *title, NSString *subtitle, NSString *key) {
    SGModRow *row = [SGModRow new]; row.title = title; row.subtitle = subtitle; row.key = key; return row;
}
SGModRow *SGWithSymbol(SGModRow *row, NSString *symbol) { row.symbol = symbol; return row; }
UIColor *SGColorRGB(NSInteger rgb) { return UIColor.blackColor; }
NSInteger SGAccentRGB(void) { return SGInt(SGKeyAccent, SGSpotifyGreen); }
NSInteger SGRAccentRGB(void) { return 0x00FFFF; } // a temporary automatic color must never enter picked history
NSInteger SGRPickedAccentRGB(void) { return SGInt(SGRKeyAccent, SGRDefaultAccent); }
void SGRAccentPreferencesChanged(void) { SGPrefsChanged(); }
void SGRefreshExplicitBadges(void) {}
void SGRRefreshExplicitBadges(void) {}
void SGPickAccent(NSString *title, NSInteger current, NSArray *recent, void (^chosen)(NSInteger)) {}
void SGRPickAccent(NSString *title, NSInteger current, NSArray *recent, void (^chosen)(NSInteger)) {}

static SGModRow *named(NSArray *rows, NSString *title) {
    for (SGModRow *row in rows) if ([row.title isEqualToString:title]) return row;
    return nil;
}
static NSUInteger checks;
static void expect(BOOL ok, NSString *name) { checks++; if (!ok) HARNESS_FAIL(@"%@", name); }
static void checkRecents(NSArray<NSNumber *> *(*from)(id),
                         NSArray<NSNumber *> *(*adding)(NSArray<NSNumber *> *, NSInteger, NSInteger),
                         NSInteger own) {
    expect([from(nil) isEqual:@[]], @"no saved colors");
    expect([from(@"#123456") isEqual:@[]], @"non-list history ignored");
    expect([from(@[@0x123456, @"#ABCDEF", @YES, @1.5, @(-1), @0x1000000, @(own), @{}, @0x123456, @0xABCDEF])
            isEqual:@[@0x123456, @0xABCDEF]], @"invalid, default and duplicate colors ignored");
    expect([from(@[@1, @2, @3, @4, @5, @6, @7, @8, @9, @10]) isEqual:@[@1, @2, @3, @4, @5, @6, @7, @8]], @"eight recent colors");
    expect([adding(@[], 0x112233, own) isEqual:@[@0x112233]], @"first color");
    expect([adding(@[@0xA, @0xB], 0xC, 0xA) isEqual:@[@0xC, @0xA, @0xB]], @"new color first");
    expect([adding(@[@0xA, @0xB, @0xC], 0xC, 0xA) isEqual:@[@0xC, @0xA, @0xB]], @"existing color moved first");
    expect([adding(@[@1, @2, @3, @4, @5, @6, @7, @8], 9, 1) isEqual:@[@9, @1, @2, @3, @4, @5, @6, @7]], @"oldest color evicted");
    expect([adding(@[@0xA, @0xB], 0xB, 0xB) isEqual:@[@0xA, @0xB]], @"same color leaves history alone");
    expect([adding(@[@0xA], own, 0xA) isEqual:@[@0xA]], @"default not saved");
    expect([adding(@[@0xA], -1, 0xA) isEqual:@[@0xA]], @"negative color not saved");
    expect([adding(@[@0xA], 0x1000000, 0xA) isEqual:@[@0xA]], @"out of range color not saved");
}
// The glass's three choices: nothing stored is Regular, None and On; a stored value that is none of the choices reads
// as Regular and None, on the rows and in what SGRGlass.m builds the launch's glass from.
static void checkGlassRows(void) {
    values = [NSMutableDictionary dictionary];
    NSArray *rows = SGRAppearanceRows();
    SGModRow *material = named(rows, @"Glass material"), *tint = named(rows, @"Glass tint"), *touch = named(rows, @"Glass touch response");
    expect([material.menu isEqual:@[@"Regular", @"Clear"]] && [tint.menu isEqual:@[@"None", @"Light", @"Dark"]], @"exact glass choices");
    expect([material.value() isEqualToString:@"Regular"] && SGRStoredGlassMaterial() == SGRGlassMaterialRegular, @"unset material is Regular");
    expect([tint.value() isEqualToString:@"None"] && SGRStoredGlassTint() == SGRGlassTintNone, @"unset tint is None");
    expect([touch.key isEqualToString:@"spotifyglass.redesign.glass.interactive"] && touch.defaultOn, @"touch response key, on unless switched off");
    values[@"spotifyglass.redesign.glass.material"] = @7;
    values[@"spotifyglass.redesign.glass.tint"] = @(-3);
    // The readers first: the rows index their names by them.
    expect(SGRStoredGlassMaterial() == SGRGlassMaterialRegular, @"out of range material reads Regular");
    expect(SGRStoredGlassTint() == SGRGlassTintNone, @"out of range tint reads None");
    expect([material.value() isEqualToString:@"Regular"] && [tint.value() isEqualToString:@"None"], @"out of range shown as Regular and None");
    values[@"spotifyglass.redesign.glass.tint"] = @3;
    expect(SGRStoredGlassTint() == SGRGlassTintNone && [tint.value() isEqualToString:@"None"], @"tint past Dark is None");
    material.chosen(1);
    tint.chosen(2);
    expect([values[@"spotifyglass.redesign.glass.material"] isEqual:@1] && [material.value() isEqualToString:@"Clear"]
           && SGRStoredGlassMaterial() == SGRGlassMaterialClear, @"Clear stored and shown");
    expect([values[@"spotifyglass.redesign.glass.tint"] isEqual:@2] && [tint.value() isEqualToString:@"Dark"]
           && SGRStoredGlassTint() == SGRGlassTintDark, @"Dark stored and shown");
    tint.chosen(1);
    expect([tint.value() isEqualToString:@"Light"] && SGRStoredGlassTint() == SGRGlassTintLight, @"Light stored and shown");
    expect([material.searchIdentifier isEqualToString:@"spotifyglass.redesign.glass.material"]
           && [tint.searchIdentifier isEqualToString:@"spotifyglass.redesign.glass.tint"], @"glass menus remembered by their keys");
}

// Saved mark in Plain checkmark's place: with nothing stored it reads the old switch, and a pick writes only its own key.
static void checkSavedMark(void) {
    NSString *const oldKey = @"spotifyglass.redesign.plainCheck", *const newKey = @"spotifyglass.redesign.savedMark";
    // The decoder first: the row indexes its names by it.
    expect(SGRSavedMarkFrom(-1, NO) == SGRSavedMarkSpotify && SGRSavedMarkFrom(-1, YES) == SGRSavedMarkPlainCheck
           && SGRSavedMarkFrom(2, NO) == SGRSavedMarkDot && SGRSavedMarkFrom(1, NO) == SGRSavedMarkPlainCheck
           && SGRSavedMarkFrom(0, YES) == SGRSavedMarkSpotify && SGRSavedMarkFrom(3, YES) == SGRSavedMarkPlainCheck
           && SGRSavedMarkFrom(9, YES) == SGRSavedMarkPlainCheck && SGRSavedMarkFrom(9, NO) == SGRSavedMarkSpotify,
           @"what the launch reads (SGRSavedMarkFrom)");
    values = [NSMutableDictionary dictionary];
    NSArray *rows = SGRAppearanceRows();
    expect(named(rows, @"Plain checkmark") == nil, @"no Plain checkmark switch beside Saved mark");
    SGModRow *mark = named(rows, @"Saved mark");
    expect([mark.menu isEqual:@[@"Spotify's", @"Plain checkmark", @"Dot"]], @"exact saved mark choices");
    expect([mark.value() isEqualToString:@"Spotify's"], @"nothing stored is Spotify's");
    values[oldKey] = @YES;
    expect([mark.value() isEqualToString:@"Plain checkmark"], @"Plain checkmark switched on carries over");
    values[newKey] = @9;
    expect([mark.value() isEqualToString:@"Plain checkmark"], @"an unknown mark keeps the old switch's choice");
    mark.chosen(2);
    expect([values[newKey] isEqual:@2] && [mark.value() isEqualToString:@"Dot"], @"Dot stored and shown");
    expect([values[oldKey] isEqual:@YES], @"the old switch is left as it was");
    mark.chosen(0);
    expect([mark.value() isEqualToString:@"Spotify's"], @"Spotify's chosen wins over the old switch");
    [values removeObjectForKey:oldKey];
    values[newKey] = @(-1);
    expect([mark.value() isEqualToString:@"Spotify's"], @"an unknown mark with the old switch off is Spotify's");
    expect([mark.searchIdentifier isEqualToString:newKey], @"saved mark remembered by its key");
}

int main(void) {
    @autoreleasepool {
        checkRecents(SGAccentRecentFrom, SGAccentRecentAdding, 0x1ED760);
        checkRecents(SGRAccentRecentFrom, SGRAccentRecentAdding, 0x37F200);
        expect([SGRAccentRecentFrom(@[@0x1ED760, @0x37F200, @0xFA2D48]) isEqual:@[@0xFA2D48]], @"redesign omits both preset greens");
        expect([SGRAccentRecentAdding(@[], 0x1ED760, 0x37F200) isEqual:@[]], @"Spotify preset not saved");
        expect([SGAccentRecentAdding(@[], 0x37F200, 0x1ED760) isEqual:@[@0x37F200]], @"native history owns its colors");
        values = [@{SGRKeyAccent: @0x123456} mutableCopy];
        NSArray *native = SGNativeAppearanceRows(), *redesign = SGRAppearanceRows();
        SGModRow *mode = named(redesign, @"Accent source");
        expect([mode.menu isEqual:@[@"Picked", @"Automatic"]], @"exact automatic choices");
        expect([mode.value() isEqualToString:@"Picked"], @"Picked is the default");
        mode.chosen(1);
        expect(SGFlag(SGRKeyAccentAuto, NO), @"Automatic writes its redesign-only key");
        expect([named(redesign, @"Accent color").value() isEqualToString:@"#123456"], @"color row shows saved pick, not automatic tint");
        named(redesign, @"Accent color preset").chosen(1);
        expect(SGInt(SGRKeyAccentCustom, -1) == 0x123456, @"preset change keeps saved custom color, not automatic tint");
        mode.chosen(0);
        expect(!SGFlag(SGRKeyAccentAuto, YES), @"Picked disables automatic");
        expect(named(native, @"Accent source") == nil, @"Native has no automatic row");
        SGModRow *nativeBadge = named(native, @"Hide explicit badge"), *redesignBadge = named(redesign, @"Hide explicit badge");
        expect([nativeBadge.key isEqualToString:@"spotifyglass.hideExplicit"] && !nativeBadge.defaultOn, @"Native badge key and off default");
        expect([redesignBadge.key isEqualToString:@"spotifyglass.redesign.hideExplicit"] && !redesignBadge.defaultOn, @"redesign badge key and off default");
        checkGlassRows();
        checkSavedMark();
        printf("appearance rows: %lu checks passed\n", (unsigned long)checks);
    }
    return 0;
}
