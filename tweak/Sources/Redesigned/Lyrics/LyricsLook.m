// The lyrics' look as stored, its presets and the preview's lines. The page is LyricsLookSettings.m.
#import "Core/SGLocalize.h"
#import "LyricsLook.h"

NSNotificationName const SGRLyricsLookDidChangeNotification = @"spotifyglass.redesign.lyricsLookDidChange";

// The sliders' ranges, which a stored look is held to as well.
static const SGRLyricsLook kLeast = {22, 12, 0, 0, 0}, kMost = {40, 40, 2, 2, 2};

static SGRLyricsLook presets[] = {
    {34, 24, 1, 1, 1},          // Apple Music: its 34 pt lines (iOS 26, design/applemusic-gap item 5), 24 pt apart
    {36, 28, 1, 1, 1},          // Large
    {25, 16, 1, 1, 1},          // Compact
    {30, 24, 0, 0, 0},          // Calm: every line sharp, and nothing held glows or waves
    {32, 26, 1.4, 1.6, 1.8},    // Vivid
};

NSArray<NSString *> *SGRLyricsLookPresetNames(void) {
    return @[SGL(@"settings.lyricslook.choice.apple_music", @"Apple Music"), SGL(@"settings.lyricslook.choice.large", @"Large"), SGL(@"settings.lyricslook.choice.compact", @"Compact"), SGL(@"settings.lyricslook.choice.calm", @"Calm"), SGL(@"settings.lyricslook.choice.vivid", @"Vivid")];
}

SGRLyricsLook SGRLyricsLookPreset(NSUInteger index) {
    return presets[MIN(index, sizeof(presets) / sizeof(*presets) - 1)];
}

static CGFloat held(CGFloat value, CGFloat least, CGFloat most) {
    return isfinite(value) ? MAX(least, MIN(most, value)) : least;
}

static CGFloat stored(NSDictionary *look, NSString *name, CGFloat fallback, CGFloat least, CGFloat most) {
    id value = look[name];
    return [value isKindOfClass:NSNumber.class] ? held([value doubleValue], least, most) : fallback;
}

SGRLyricsLook SGRLyricsLookNow(void) {
    SGRLyricsLook look = presets[0];
    NSDictionary *saved = [NSUserDefaults.standardUserDefaults dictionaryForKey:SGRKeyLyricsLook];
    if (!saved) return look;
    look.size = stored(saved, @"size", look.size, kLeast.size, kMost.size);
    look.spacing = stored(saved, @"spacing", look.spacing, kLeast.spacing, kMost.spacing);
    look.blur = stored(saved, @"blur", look.blur, kLeast.blur, kMost.blur);
    look.glow = stored(saved, @"glow", look.glow, kLeast.glow, kMost.glow);
    look.wave = stored(saved, @"wave", look.wave, kLeast.wave, kMost.wave);
    return look;
}

void SGRSetLyricsLook(SGRLyricsLook look, id changer) {
    [NSUserDefaults.standardUserDefaults setObject:@{
        @"size": @(held(look.size, kLeast.size, kMost.size)),
        @"spacing": @(held(look.spacing, kLeast.spacing, kMost.spacing)),
        @"blur": @(held(look.blur, kLeast.blur, kMost.blur)),
        @"glow": @(held(look.glow, kLeast.glow, kMost.glow)),
        @"wave": @(held(look.wave, kLeast.wave, kMost.wave)),
    } forKey:SGRKeyLyricsLook];
    [NSNotificationCenter.defaultCenter postNotificationName:SGRLyricsLookDidChangeNotification object:changer];
}

// Equal to the slider's step, so a look slid back onto a preset's values reads as that preset again.
static BOOL same(CGFloat a, CGFloat b) {
    return fabs(a - b) < 0.01;
}

NSInteger SGRLyricsLookPresetIndex(SGRLyricsLook look) {
    for (NSUInteger i = 0; i < sizeof(presets) / sizeof(*presets); i++) {
        SGRLyricsLook preset = presets[i];
        if (same(look.size, preset.size) && same(look.spacing, preset.spacing) && same(look.blur, preset.blur)
            && same(look.glow, preset.glow) && same(look.wave, preset.wave)) return (NSInteger)i;
    }
    return -1;
}

#pragma mark - the preview's song

// Each word as [text, start, end] in ms; a line runs from its first word's start to its last word's end.
static SGKaraokeLine *sampleLine(NSArray<NSArray *> *timed) {
    NSMutableArray<SGKaraokeWord *> *words = [NSMutableArray array];
    for (NSArray *piece in timed) {
        SGKaraokeWord *word = [SGKaraokeWord new];
        word.text = piece[0];
        word.start = [piece[1] integerValue];
        word.end = [piece[2] integerValue];
        [words addObject:word];
    }
    SGKaraokeLine *line = [SGKaraokeLine new];
    line.words = words;
    line.start = words.firstObject.start;
    line.end = words.lastObject.end;
    line.timing = SGKaraokeTimingWords;
    return line;
}

// Words of the mod's own. The second line holds its last word for three seconds, so the glow and the wave
// show on every round.
NSArray<SGKaraokeLine *> *SGRLyricsSampleLines(void) {
    static NSArray<SGKaraokeLine *> *lines;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        lines = @[
            sampleLine(@[@[@"Light", @600, @1000], @[@"comes", @1000, @1400], @[@"over", @1400, @1800], @[@"the", @1800, @2000], @[@"water", @2000, @2900]]),
            sampleLine(@[@[@"hold", @3100, @3500], @[@"on", @3500, @3800], @[@"to", @3800, @4000], @[@"the", @4000, @4200], @[@"night", @4200, @7200]]),
            sampleLine(@[@[@"we", @7500, @7800], @[@"sing", @7800, @8300], @[@"it", @8300, @8500], @[@"louder", @8500, @9500]]),
            sampleLine(@[@[@"all", @9800, @10100], @[@"the", @10100, @10300], @[@"way", @10300, @10700], @[@"home", @10700, @12000]]),
        ];
    });
    return lines;
}

// Korean lines of the mod's own with a pronunciation timed to their words and an English translation, for the
// Text sizes page, which shows all three whatever the lyrics menu has switched on. Timed as the lines above.
NSArray<SGKaraokeLine *> *SGRLyricsSampleLinesWithExtras(void) {
    static NSArray<SGKaraokeLine *> *lines;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSArray<NSArray *> *song = @[
            @[@[@[@"별빛을", @600, @1400], @[@"따라", @1400, @2000], @[@"걸어요", @2000, @2900]],
              @[@[@"byeolbicheul", @600, @1400], @[@"ttara", @1400, @2000], @[@"georeoyo", @2000, @2900]], @"We walk along the starlight"],
            @[@[@[@"새벽이", @3100, @3800], @[@"오고", @3800, @4300], @[@"있어", @4300, @7200]],
              @[@[@"saebyeogi", @3100, @3800], @[@"ogo", @3800, @4300], @[@"isseo", @4300, @7200]], @"A new dawn is on its way"],
            @[@[@[@"함께", @7500, @8300], @[@"노래해요", @8300, @9500]],
              @[@[@"hamkke", @7500, @8300], @[@"noraehaeyo", @8300, @9500]], @"Let's sing it together"],
            @[@[@[@"집으로", @9800, @10700], @[@"가는", @10700, @11200], @[@"길", @11200, @12000]],
              @[@[@"jibeuro", @9800, @10700], @[@"ganeun", @10700, @11200], @[@"gil", @11200, @12000]], @"All the way home"],
        ];
        NSMutableArray<SGKaraokeLine *> *made = [NSMutableArray array];
        for (NSArray *verse in song) {
            SGKaraokeLine *line = sampleLine(verse[0]);
            line.pronunciation = sampleLine(verse[1]);
            line.translation = verse[2];
            [made addObject:line];
        }
        lines = made;
    });
    return lines;
}

NSInteger SGRLyricsSampleLength(void) {
    return 13500;   // a pause after the last line, then the first again
}

#pragma mark - the size in each place

// The place's own size first, then smaller and larger shares of it.
static const CGFloat kPlaceShares[] = {1, 0.75, 0.85, 1.15, 1.3};
static const NSInteger kPlaceShareCount = sizeof(kPlaceShares) / sizeof(*kPlaceShares);

static NSString *placeKey(SGRLyricsPlace place) {
    switch (place) {
        case SGRLyricsPlacePlayer: return SGRKeyLyricsSizePlayer;
        case SGRLyricsPlaceFullScreen: return SGRKeyLyricsSizeFullScreen;
        case SGRLyricsPlaceNone: return nil;
    }
    return nil;
}

NSInteger SGRLyricsSizeChoice(SGRLyricsPlace place) {
    NSString *key = placeKey(place);
    NSInteger choice = key ? [NSUserDefaults.standardUserDefaults integerForKey:key] : 0;
    return choice >= 0 && choice < kPlaceShareCount ? choice : 0;
}

CGFloat SGRLyricsSizeShare(SGRLyricsPlace place) {
    return kPlaceShares[SGRLyricsSizeChoice(place)];
}

void SGRSetLyricsSizeChoice(SGRLyricsPlace place, NSInteger choice) {
    NSString *key = placeKey(place);
    if (!key) return;
    // The place's own size is stored as no choice at all.
    if (choice > 0 && choice < kPlaceShareCount) [NSUserDefaults.standardUserDefaults setInteger:choice forKey:key];
    else [NSUserDefaults.standardUserDefaults removeObjectForKey:key];
    [NSNotificationCenter.defaultCenter postNotificationName:SGRLyricsLookDidChangeNotification object:nil];
}

NSArray<NSString *> *SGRLyricsSizeNames(void) {
    NSMutableArray<NSString *> *names = [NSMutableArray arrayWithObject:SGL(@"settings.lyricslook.place.default", @"Default")];
    for (NSInteger i = 1; i < kPlaceShareCount; i++)
        [names addObject:[NSString stringWithFormat:SGL(@"settings.lyricslook.format.percent", @"%.0f%%"), kPlaceShares[i] * 100]];
    return names;
}
