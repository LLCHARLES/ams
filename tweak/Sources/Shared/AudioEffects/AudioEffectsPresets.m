// The presets: built-in ones over a reset, and the user's own as a copy of every dsp key. Everything goes back
// in through AudioEffects.h's setters, so it is clamped and applied the way the page's own changes are.
#import "Core/SGLocalize.h"
#import "AudioEffects.h"
#import "AudioEffectsApply.h"
#import "AudioEffectsPresets.h"
#import <CommonCrypto/CommonDigest.h>
#import <math.h>

static NSString *const kPrefix = @"spotifyglass.dsp.";

static NSUserDefaults *store(void) {
    return NSUserDefaults.standardUserDefaults;
}

// A value back through its setter: a switch (the key naming its own effect), a number, the gains as a
// list, or text. Anything else is left out, a preset from a later build naming a key this one lacks too.
static void setValue(NSString *key, id value) {
    if (![key hasPrefix:kPrefix]) return;
    if ([value isKindOfClass:NSArray.class]) SGDSPSetGains(key, value);
    else if ([value isKindOfClass:NSString.class]) SGDSPSetString(key, value);
    else if (![value isKindOfClass:NSNumber.class]) return;
    else if ([SGDSPEffectOf(key) isEqualToString:key]) SGDSPSetSwitch(key, [value boolValue]);
    else SGDSPSetNumber(key, [value doubleValue]);
}

// A pick is meant to be heard: the master switch, off until asked for, comes on with it.
static void turnOn(void) {
    if (!SGDSPSwitch(SGKeyDSP)) SGDSPSetSwitch(SGKeyDSP, YES);
}

static NSDictionary<NSString *, id> *currentValues(void) {
    NSDictionary<NSString *, id> *all = store().dictionaryRepresentation;
    NSMutableDictionary<NSString *, id> *values = [NSMutableDictionary dictionary];
    for (NSString *key in all) {
        if ([key hasPrefix:kPrefix]) values[key] = all[key];
    }
    return values;
}

#pragma mark - built in

// Each built-in preset's name and what it does, in the order builtInValues reads them. Shown only, so they
// are read in the person's language; a pick goes by its index.
static NSArray<NSArray<NSString *> *> *builtIn(void) {
    return @[
        @[SGL(@"settings.audioeffects.preset.bass_boost", @"Bass boost"), SGL(@"settings.audioeffects.preset.bass_boost.subtitle", @"Bass boost at 8 dB")],
        @[SGL(@"settings.audioeffects.preset.vocal_clarity", @"Vocal clarity"), SGL(@"settings.audioeffects.preset.vocal_clarity.subtitle", @"Equalizer on voices, a light compander")],
        @[SGL(@"settings.audioeffects.preset.late_night", @"Late night"), SGL(@"settings.audioeffects.preset.late_night.subtitle", @"Quiet and loud evened out, less bass")],
        @[SGL(@"settings.audioeffects.preset.concert_hall", @"Concert hall"), SGL(@"settings.audioeffects.preset.concert_hall.subtitle", @"A large hall's reverb, a wider stage")],
        @[SGL(@"settings.audioeffects.preset.warm_analog", @"Warm analog"), SGL(@"settings.audioeffects.preset.warm_analog.subtitle", @"Tube warmth, a warm equalizer")],
        @[SGL(@"settings.audioeffects.preset.headphone_comfort", @"Headphone comfort"), SGL(@"settings.audioeffects.preset.headphone_comfort.subtitle", @"Crossfeed, a softer top")],
        @[SGL(@"settings.audioeffects.preset.wide_stereo", @"Wide stereo"), SGL(@"settings.audioeffects.preset.wide_stereo.subtitle", @"Stereo widening")],
    ];
}

// The equalizer presets by their place in SGDSPEqualizerPresetNames, whose names are translated.
enum { kEqualizerVocal = 4, kEqualizerWarm = 5 };

static NSDictionary<NSString *, id> *builtInValues(NSInteger index) {
    switch (index) {
        case 0: return @{SGKeyDSPBass: @YES, SGKeyDSPBassGain: @8};
        case 1: return @{SGKeyDSPEqualizer: @YES, SGKeyDSPEqualizerGains: SGDSPEqualizerPreset(kEqualizerVocal),
                         SGKeyDSPCompander: @YES, SGKeyDSPCompanderGains: @[@0, @0.2, @0.3, @0.3, @0.3, @0.2, @0]};
        // The compander over 0 lifts the quiet parts and holds the loud ones; the gain brings the level back.
        case 2: return @{SGKeyDSPCompander: @YES, SGKeyDSPCompanderGains: @[@0.6, @0.7, @0.8, @0.8, @0.8, @0.7, @0.6],
                         SGKeyDSPCompanderTime: @0.3, SGKeyDSPEqualizer: @YES,
                         SGKeyDSPEqualizerGains: @[@-6, @-5, @-4, @-2, @-1, @0, @0, @0, @0, @0, @0, @0, @-1, @-2, @-2],
                         SGKeyDSPPostGain: @3, SGKeyDSPLimiterThreshold: @-3};
        case 3: return @{SGKeyDSPReverb: @YES, SGKeyDSPReverbPreset: @7, SGKeyDSPReverbAmount: @40,
                         SGKeyDSPStereoWide: @YES, SGKeyDSPStereoWideLevel: @65};
        case 4: return @{SGKeyDSPTube: @YES, SGKeyDSPTubeDrive: @6, SGKeyDSPEqualizer: @YES, SGKeyDSPEqualizerGains: SGDSPEqualizerPreset(kEqualizerWarm)};
        case 5: return @{SGKeyDSPCrossfeed: @YES, SGKeyDSPCrossfeedMode: @2, SGKeyDSPEqualizer: @YES,
                         SGKeyDSPEqualizerGains: @[@0, @0, @0, @0, @0, @0, @0, @0, @0, @0, @-1, @-2, @-2, @-3, @-3]};
        case 6: return @{SGKeyDSPStereoWide: @YES, SGKeyDSPStereoWideLevel: @75};
    }
    return nil;
}

NSArray<NSString *> *SGDSPBuiltInPresetNames(void) {
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (NSArray<NSString *> *preset in builtIn()) [names addObject:preset[0]];
    return names;
}

NSString *SGDSPBuiltInPresetDetail(NSInteger index) {
    NSArray<NSArray<NSString *> *> *all = builtIn();
    return index >= 0 && index < (NSInteger)all.count ? all[(NSUInteger)index][1] : nil;
}

void SGDSPLoadBuiltInPreset(NSInteger index) {
    NSDictionary<NSString *, id> *values = builtInValues(index);
    if (!values) return;
    NSMutableDictionary<NSString *, id> *kept = [NSMutableDictionary dictionary];
    NSDictionary<NSString *, id> *now = currentValues();
    for (NSString *key in now) {
        if ([SGDSPEffectOf(key) isEqualToString:SGKeyDSPGraphicEq]) kept[key] = now[key];
    }
    SGDSPResetAll();
    for (NSString *key in kept) setValue(key, kept[key]);
    for (NSString *key in values) setValue(key, values[key]);
    turnOn();
}

#pragma mark - the user's

static NSDictionary<NSString *, NSDictionary *> *userPresets(void) {
    id presets = [store() objectForKey:SGKeyDSPUserPresets];
    return [presets isKindOfClass:NSDictionary.class] ? presets : @{};
}

NSArray<NSString *> *SGDSPUserPresetNames(void) {
    return [userPresets().allKeys sortedArrayUsingSelector:@selector(localizedStandardCompare:)];
}

void SGDSPSaveUserPreset(NSString *name) {
    if (!name.length) return;
    SGDSPSaveUserPresetValues(name, currentValues());
}

NSDictionary<NSString *, id> *SGDSPUserPresetValues(NSString *name) {
    NSDictionary *values = name ? userPresets()[name] : nil;
    return [values isKindOfClass:NSDictionary.class] ? values : nil;
}

NSDictionary<NSString *, id> *SGDSPCurrentValues(void) {
    return currentValues();
}

// The settings are written in one main-thread burst, which SGDSPApply hands the engine as one reconfiguration.
void SGDSPApplyValues(NSDictionary<NSString *, id> *values) {
    SGDSPResetAll();
    for (NSString *key in values) setValue(key, values[key]);
}

NSString *SGDSPValuesDigest(NSDictionary<NSString *, id> *values) {
    NSMutableString *text = [NSMutableString string];
    NSDictionary<NSString *, id> *effective = SGDSPEffectiveValues(values);
    for (NSString *key in [effective.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
        id value = effective[key];
        if ([value isKindOfClass:NSString.class]) [text appendFormat:@"%@=s%@\n", key, value];
        else if ([SGDSPEffectOf(key) isEqualToString:key]) [text appendFormat:@"%@=b%d\n", key, [value boolValue]];
        else [text appendFormat:@"%@=n%.9g\n", key, [value doubleValue]];
    }
    unsigned char hash[CC_SHA256_DIGEST_LENGTH];
    NSData *bytes = [text dataUsingEncoding:NSUTF8StringEncoding];
    CC_SHA256(bytes.bytes, (CC_LONG)bytes.length, hash);
    NSMutableString *hex = [NSMutableString stringWithCapacity:2 * CC_SHA256_DIGEST_LENGTH];
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) [hex appendFormat:@"%02x", hash[i]];
    return hex;
}

BOOL SGDSPLoadUserPreset(NSString *name) {
    NSDictionary *values = SGDSPUserPresetValues(name);
    if (!values) return NO;
    SGDSPApplyValues(values);
    turnOn();
    return YES;
}

void SGDSPDeleteUserPreset(NSString *name) {
    NSMutableDictionary *presets = [userPresets() mutableCopy];
    [presets removeObjectForKey:name];
    [store() setObject:presets forKey:SGKeyDSPUserPresets];
    SGAutoEqPresetDeleted(name);
}

#pragma mark - preset files

enum { kPresetSwitch, kPresetNumber, kPresetString };

// The keys and types this build can exchange, without the master switch.
static NSDictionary<NSString *, NSNumber *> *presetTypes(void) {
    static NSDictionary<NSString *, NSNumber *> *types;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableDictionary<NSString *, NSNumber *> *all = [@{
            SGKeyDSPPostGain: @(kPresetNumber), SGKeyDSPLimiterThreshold: @(kPresetNumber),
            SGKeyDSPLimiterRelease: @(kPresetNumber), SGKeyDSPCompanderTime: @(kPresetNumber),
            SGKeyDSPBassGain: @(kPresetNumber), SGKeyDSPConvolverMode: @(kPresetNumber),
            SGKeyDSPReverbPreset: @(kPresetNumber), SGKeyDSPReverbAmount: @(kPresetNumber),
            SGKeyDSPStereoWideLevel: @(kPresetNumber), SGKeyDSPCrossfeedMode: @(kPresetNumber),
            SGKeyDSPTubeDrive: @(kPresetNumber),
            SGKeyDSPCompanderGains: @(kPresetString), SGKeyDSPEqualizerGains: @(kPresetString),
            SGKeyDSPGraphicEqNodes: @(kPresetString), SGKeyDSPGraphicEqHeadphone: @(kPresetString),
            SGKeyDSPConvolverFile: @(kPresetString), SGKeyDSPDDCFile: @(kPresetString),
            SGKeyDSPLiveprogFile: @(kPresetString),
        } mutableCopy];
        for (NSString *effect in SGDSPEffectSwitches()) all[effect] = @(kPresetSwitch);
        types = [all copy];
    });
    return types;
}

// Keep whole composed characters when shortening a name.
static NSString *presetShortName(NSString *name, NSUInteger limit) {
    NSUInteger end = 0;
    for (NSUInteger count = 0; count < limit && end < name.length; count++) {
        end = NSMaxRange([name rangeOfComposedCharacterSequencesForRange:NSMakeRange(end, 1)]);
    }
    return [name substringToIndex:end];
}

// Imported strings have size and file-name limits as well as their declared type.
static NSDictionary<NSString *, id> *presetFileValues(NSDictionary *values, BOOL importing) {
    NSMutableDictionary<NSString *, id> *kept = [NSMutableDictionary dictionary];
    NSDictionary<NSString *, NSNumber *> *types = presetTypes();
    for (NSString *key in types) {
        id value = values[key];
        NSInteger type = types[key].integerValue;
        if (type == kPresetString) {
            if (![value isKindOfClass:NSString.class]) continue;
            NSString *text = value;
            if (importing) {
                if ([text lengthOfBytesUsingEncoding:NSUTF8StringEncoding] > 64 * 1024) continue;
                BOOL file = [key isEqualToString:SGKeyDSPConvolverFile] || [key isEqualToString:SGKeyDSPDDCFile]
                            || [key isEqualToString:SGKeyDSPLiveprogFile];
                if (file && text.length && (![text isEqualToString:text.lastPathComponent]
                    || [text containsString:@"/"] || [text containsString:@"\\"] || [text hasPrefix:@"."])) continue;
            }
            kept[key] = text;
        } else {
            if (![value isKindOfClass:NSNumber.class]) continue;
            if (type == kPresetSwitch) kept[key] = @([value boolValue]);
            else {
                double number = [value doubleValue];
                if (!isnan(number) && !isinf(number)) kept[key] = value;
            }
        }
    }
    return [kept copy];
}

// Share the saved values with a name safe for Files.
NSData *SGDSPPresetFileData(NSString *name, NSString **fileName) {
    if (fileName) *fileName = nil;
    NSDictionary *values = name ? userPresets()[name] : nil;
    if (![values isKindOfClass:NSDictionary.class]) return nil;
    NSDictionary *file = @{@"format": @"retrine.audio-preset", @"version": @1,
                           @"name": name, @"values": presetFileValues(values, NO)};
    NSData *data = [NSJSONSerialization dataWithJSONObject:file
                         options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:nil];
    if (!data) return nil;
    NSMutableCharacterSet *unsafe = [NSCharacterSet.controlCharacterSet mutableCopy];
    [unsafe addCharactersInString:@"/\\:"];
    NSString *safe = [[name componentsSeparatedByCharactersInSet:unsafe] componentsJoinedByString:@"-"];
    safe = [safe stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    safe = presetShortName(safe, 60);
    if (fileName) *fileName = [(safe.length ? safe : @"Preset") stringByAppendingString:@".retrine-preset.json"];
    return data;
}

// Check a file without touching preferences or applying any effect.
NSDictionary<NSString *, id> *SGDSPReadPresetFile(NSData *data, NSString *fallbackName, NSString **name, NSString **error) {
    if (name) *name = nil;
    if (error) *error = nil;
    if (data.length > 256 * 1024) {
        if (error) *error = SGL(@"settings.audioeffects.presetfile.error.toolarge", @"This preset file is too large.");
        return nil;
    }
    id file = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    // Files already shared under the old name are the same v1 format.
    if (![file isKindOfClass:NSDictionary.class] ||
        (![file[@"format"] isEqual:@"retrine.audio-preset"] && ![file[@"format"] isEqual:@"vitrine.audio-preset"])) {
        if (error) *error = SGL(@"settings.audioeffects.presetfile.error.format", @"This file is not a Retrine audio preset.");
        return nil;
    }
    id version = file[@"version"];
    if (![version isKindOfClass:NSNumber.class] || CFGetTypeID((__bridge CFTypeRef)version) == CFBooleanGetTypeID()
        || !isfinite([version doubleValue]) || floor([version doubleValue]) != [version doubleValue]
        || [version doubleValue] < 1) {
        if (error) *error = SGL(@"settings.audioeffects.presetfile.error.version", @"This preset file has an invalid version.");
        return nil;
    }
    if ([version doubleValue] > 1) {
        if (error) *error = SGL(@"settings.audioeffects.presetfile.error.newer", @"This preset was made by a newer Retrine. Update Retrine to import it.");
        return nil;
    }
    if (![file[@"values"] isKindOfClass:NSDictionary.class]) {
        if (error) *error = SGL(@"settings.audioeffects.presetfile.error.values", @"This preset file has invalid settings.");
        return nil;
    }
    NSDictionary<NSString *, id> *values = presetFileValues(file[@"values"], YES);
    if (!values.count) {
        if (error) *error = SGL(@"settings.audioeffects.presetfile.error.empty", @"This preset has no settings this version of Retrine can use.");
        return nil;
    }
    NSString *title = [file[@"name"] isKindOfClass:NSString.class] ? file[@"name"] : @"";
    title = [title stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!title.length) title = [fallbackName stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!title.length) title = @"Preset";
    if (name) *name = presetShortName(title, 80);
    return values;
}

// Save imported values under the chosen name.
void SGDSPSaveUserPresetValues(NSString *name, NSDictionary<NSString *, id> *values) {
    if (!name.length) return;
    NSMutableDictionary *presets = [userPresets() mutableCopy];
    presets[name] = values;
    [store() setObject:presets forKey:SGKeyDSPUserPresets];
}

// A stored entry reserves its name, even when its values cannot be loaded.
BOOL SGDSPUserPresetExists(NSString *name) {
    return name && userPresets()[name] != nil;
}

// Keep the requested name when free, or take its first unused numbered variant.
NSString *SGDSPUniquePresetName(NSString *name) {
    NSDictionary *presets = userPresets();
    if (!presets[name]) return name;
    for (NSUInteger suffix = 2; ; suffix++) {
        NSString *candidate = [NSString stringWithFormat:@"%@ %lu", name, (unsigned long)suffix];
        if (!presets[candidate]) return candidate;
    }
}

// List missing library files in effect order, with each name only once.
NSArray<NSString *> *SGDSPPresetMissingFiles(NSDictionary<NSString *, id> *values) {
    const SGDSPFileKind kinds[] = {SGDSPFileImpulseResponse, SGDSPFileDDC, SGDSPFileLiveprog};
    NSMutableArray<NSString *> *missing = [NSMutableArray array];
    for (NSUInteger i = 0; i < sizeof kinds / sizeof *kinds; i++) {
        id value = values[SGDSPFileKey(kinds[i])];
        if (![value isKindOfClass:NSString.class] || ![value length]) continue;
        if (![SGDSPLibraryFiles(kinds[i]) containsObject:value] && ![missing containsObject:value]) [missing addObject:value];
    }
    return [missing copy];
}

#pragma mark - GraphicEQ text

// One line: AutoEq's files end in a newline, and a copy out of a web page often has more.
NSString *SGDSPGraphicEqLine(NSString *text) {
    NSArray<NSString *> *words = [text ?: @"" componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    words = [words filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"length > 0"]];
    NSString *line = [words componentsJoinedByString:@" "];
    return [line.lowercaseString hasPrefix:@"graphiceq:"] ? line : nil;
}
