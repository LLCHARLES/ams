// The Lyrics page's parts; App/Pages.m assembles the page.
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Settings/SGPageStyle.h"
#import "Lyrics.h"
#import "LyricsStore.h"
#import "PixieLyricsQueue.h"
#import "Shared/LyricsTranslation/LyricsTranslation.h"
#import "Core/SGGlass.h"
#import "Shared/LocalFiles/LocalLyrics.h"
#import "Shared/LockScreenLyrics/LockScreenLyrics.h"
#import "Shared/LyricsSources/LyricsSources.h"

@interface SGPixieStatusRow : SGModRow
@end
@implementation SGPixieStatusRow
- (void)refresh:(NSNotification *)note {
    NSDictionary *counts = SGPixieLyricsCounts();
    self.subtitle = [NSString stringWithFormat:SGL(@"settings.lyrics.pixie.counts", @"Saved: %@ · Missing: %@ · Deferred: %@"),
        counts[@"saved"], counts[@"missing"], counts[@"deferred"]];
    if ([counts[@"capacity"] boolValue]) self.subtitle = [self.subtitle stringByAppendingFormat:@"\n%@", SGL(@"settings.lyrics.pixie.capacity", @"Lyrics storage is full.")];
    if ([counts[@"failed"] boolValue]) self.subtitle = [self.subtitle stringByAppendingFormat:@"\n%@", SGL(@"settings.lyrics.pixie.unavailable", @"Could not read the download library or queue.")];
    UIViewController *top = SGTopController();
    if (note && [top isKindOfClass:SGModPage.class]) [((SGModPage *)top).tableView reloadData];
}
@end

SGModRow *SGDeleteSavedLyricsRow(dispatch_block_t openOfflineSettings) {
    SGModRow *deleteSaved = SGActionRow(SGL(@"settings.lyrics.offline.delete", @"Delete saved lyrics"),
        SGL(@"settings.lyrics.offline.none", @"None"), nil);
    __weak SGModRow *weakDelete = deleteSaved;
    void (^showSize)(unsigned long long) = ^(unsigned long long bytes) {
        weakDelete.subtitle = bytes ? [NSByteCountFormatter stringFromByteCount:(long long)bytes countStyle:NSByteCountFormatterCountStyleFile]
            : SGL(@"settings.lyrics.offline.none", @"None");
        UIViewController *top = SGTopController();
        if ([top isKindOfClass:SGModPage.class]) [((SGModPage *)top).tableView reloadData];
    };
    SGLyricsStoreSize(showSize);
    deleteSaved.action = openOfflineSettings ?: ^{ SGPixieLyricsDeleteSaved(showSize); };
    deleteSaved.searchIdentifier = @"action.lyrics.deleteSaved";
    return deleteSaved;
}

NSArray<SGModSection *> *SGLyricsSourcesSections(BOOL namingSource) {
    SGModRow *offline = SGSwitchRow(SGL(@"settings.lyrics.offline.title", @"Keep lyrics for offline listening"),
        SGL(@"settings.lyrics.offline.subtitle", @"Saved lyrics play without a connection."), SGKeyLyricsOffline);
    SGModRow *sources = SGPageRow(SGL(@"settings.lyrics.sources.row.title", @"Sources"), ^UIViewController *{ return SGLyricsSourcesPage(); });
    sources.value = ^NSString *{
        // The first one asked and how many follow it, short enough to sit beside the title.
        NSArray<NSString *> *order = SGLyricsOrder();
        if (!order.count) return SGL(@"common.off", @"Off");
        NSString *first = SGLyricsProviderFor(order.firstObject).name;
        return order.count == 1 ? first : [NSString stringWithFormat:SGL(@"settings.lyrics.sources.summary.format", @"%@ +%lu"), first, (unsigned long)order.count - 1];
    };
    SGModRow *imported = SGPageRow(SGL(@"settings.lyrics.imported_lrc.title", @"Imported lyrics files"), ^UIViewController *{ return SGImportedLRCPage(); });
    imported.searchIdentifier = @"page.lyrics.imported";
    sources.searchIdentifier = @"page.lyrics.sources";
    imported.value = ^NSString *{
        NSUInteger count = SGImportedLRCFiles().count;
        return count ? @(count).stringValue : SGL(@"settings.lyrics.imported_lrc.value.none", @"None");
    };
    SGModRow *words = SGOptionRow(SGL(@"settings.lyrics.prefer_words.title", @"Prefer word-by-word timing"), SGL(@"settings.lyrics.prefer_words.subtitle", @"In In order mode, keep looking past line-timed lyrics"), SGKeyLyricsPreferWordTiming);
    NSMutableArray *files = [NSMutableArray arrayWithObjects:imported, offline, SGDeleteSavedLyricsRow(nil), nil];
    NSMutableArray<SGModRow *> *rows = [NSMutableArray arrayWithObjects:sources, SGLyricsTypesRow(), words,
        SGSwitchRow(SGL(@"settings.lyrics.all_tracks.title", @"Lyrics for every track"), SGL(@"settings.lyrics.all_tracks.subtitle", @"Even where Spotify has none"), SGKeyLyricsAllTracks), nil];
    // Spicy Lyrics' terms ask for its credit wherever its lines show (Shared/LyricsSources/SpicyLyrics.m), so the switch
    // says so, or its credit under the lyrics reads as the switch not working (issue #20).
    if (SGPixieLyricsAvailable() && SGLyricsEnabled()) {
        SGModRow *bulk = SGOptionRow(SGL(@"settings.lyrics.pixie.title", @"Save lyrics for Pixie downloads"),
            SGL(@"settings.lyrics.pixie.hint", @"Ask your enabled lyrics sources about downloaded songs. Turning this off cancels the queue, not the saved lyrics."), SGKeyPixieLyrics);
        bulk.waitsOn = SGKeyLyricsOffline;
        bulk.changed = offline.changed = ^(BOOL on){ SGPixieLyricsSettingsChanged(); };
        SGModRow *pause = SGOptionRow(SGL(@"settings.lyrics.pixie.pause", @"Pause lyrics downloads"),nil,SGKeyPixieLyricsPaused);
        pause.changed = bulk.changed;
        SGPixieStatusRow *status = SGPixieStatusRow.new;
        status.title = SGL(@"settings.lyrics.pixie.missing", @"Download missing lyrics");
        status.action = ^{ SGPixieLyricsDownloadMissing(); };
        pause.visible = status.visible = ^BOOL { return SGFlag(SGKeyPixieLyrics,NO) && SGFlag(SGKeyLyricsOffline,YES); };
        [NSNotificationCenter.defaultCenter addObserver:status selector:@selector(refresh:) name:SGPixieLyricsProgress object:nil];
        [status refresh:nil];
        [files addObjectsFromArray:@[bulk,pause,status]];
    }
    if (namingSource) [rows addObject:SGOptionRow(SGL(@"settings.lyrics.show_source.title", @"Show source"), SGL(@"settings.lyrics.show_source.subtitle", @"Spicy Lyrics is always credited after the last line: its terms ask for it"), SGKeyLyricsCredit)];
    NSString *note = nil;
    if (SGEeveeLyricsOn()) {
        [rows addObject:SGOptionRow(SGL(@"settings.lyrics.use_beside_eevee.title", @"Use these sources anyway"), SGL(@"settings.lyrics.use_beside_eevee.subtitle", @"Only if EeveeSpotify's lyrics are really off"), SGKeyLyricsBesideEevee)];
        note = SGL(@"settings.lyrics.sources.eevee_conflict.footer", @"EeveeSpotify's lyrics are on, so it answers Spotify's lyrics and these sources stay "
                                                @"off: both answering froze Spotify after launch. Turn its lyrics off in its own "
                                                @"settings to use these.");
    }
    return @[SGNotedSection(SGL(@"settings.lyrics.sources.header", @"Sources"), rows, note),
             SGSection(SGL(@"settings.lyrics.accounts.header", @"Source accounts"), @[SGSpicyLyricsKeyRow(), SGDeezerARLRow()]),
             SGSection(SGL(@"settings.lyrics.files.header", @"Offline & imported lyrics"), files)];
}

SGModRow *SGLockScreenLyricsRow(void) {
    return SGOptionRow(SGL(@"settings.lyrics.lockscreen_lyrics.title", @"Lock screen lyrics"), SGL(@"settings.lyrics.lockscreen_lyrics.subtitle", @"Current line in place of the artist"), SGKeyLockScreenLyrics);
}

SGModRow *SGLyricsTranslationLanguageRow(void) {
    SGModRow *row = SGChoiceRow(SGL(@"settings.lyrics.translation_language.title", @"Translation language"), nil, SGKeyLyricsTranslationLanguage, SGLyricsTranslationLanguageNames(), 0);
    row.chosen = ^(NSInteger index) {
        SGLyricsTitleSettingsChanged();
        [NSNotificationCenter.defaultCenter postNotificationName:SGLyricsTranslationsDidChangeNotification object:nil];
    };
    row.choiceFooter = SGL(@"settings.lyrics.translation_language.footer", @"A language brings Musixmatch's community translations to lyrics that have none, "
                       @"which sends Musixmatch each song's ID. Any shows the first translation the lyrics come with. "
                       @"It is also the language the lyrics' translate menu translates into, offered only for songs in another one; "
                       @"with Any, the iPhone's own language.");
    return row;
}

// Only the redesign's lyrics view draws it, and every one there is redrawn as the switch flips.
SGModRow *SGLyricsRomanisedRow(void) {
    SGModRow *row = SGOptionRow(SGL(@"settings.lyrics.romanized.title", @"Pronunciation"), SGL(@"settings.lyrics.pronunciation.subtitle", @"Shows readings in your chosen alphabet."), SGKeyLyricsRomanised);
    row.changed = ^(BOOL on) {
        [NSNotificationCenter.defaultCenter postNotificationName:SGLyricsRomanisedDidChangeNotification object:nil];
    };
    return row;
}

SGModRow *SGLyricsAlphabetRow(void) {
    NSString *title = SGL(@"settings.lyrics.pronunciation.alphabet", @"Pronunciation alphabet");
    NSArray<NSString *> *alphabets = @[SGL(@"settings.lyrics.pronunciation.latin", @"Latin"),
                                      SGL(@"settings.lyrics.pronunciation.hangul", @"Hangul")];
    SGModRow *alphabet = SGMenuRow(title, alphabets,
            ^NSString *{ return alphabets[SGFlag(SGKeyLyricsPronunciationHangul, NO) ? 1 : 0]; }, ^(NSInteger index) {
                SGSetEnabled(SGKeyLyricsPronunciationHangul, index == 1);
                [NSNotificationCenter.defaultCenter postNotificationName:SGLyricsRomanisedDidChangeNotification object:nil];
            });
    alphabet.waitsOn = SGKeyLyricsRomanised;
    alphabet.searchIdentifier = SGKeyLyricsPronunciationHangul;
    return alphabet;
}

SGModRow *SGLyricsJapaneseReadingRow(void) {
    NSArray<NSString *> *choices = @[SGL(@"settings.lyrics.japanese_reading.romaji", @"Romaji"),
                                        SGL(@"settings.lyrics.japanese_reading.hiragana", @"Hiragana")];
    SGModRow *japanese = SGMenuRow(SGL(@"settings.lyrics.japanese_reading.title", @"Japanese reading"), choices,
            ^NSString *{ return choices[SGFlag(SGKeyLyricsJapaneseKana, NO) ? 1 : 0]; }, ^(NSInteger index) {
                SGSetEnabled(SGKeyLyricsJapaneseKana, index == 1);
                [NSNotificationCenter.defaultCenter postNotificationName:SGLyricsRomanisedDidChangeNotification object:nil];
            });
    japanese.searchIdentifier = SGKeyLyricsJapaneseKana;
    japanese.visible = ^BOOL { return SGFlag(SGKeyLyricsRomanised, NO) && !SGFlag(SGKeyLyricsPronunciationHangul, NO); };
    return japanese;
}

// Only the redesign's lyrics view sweeps words, and it restyles as the switch flips.
NSNotificationName const SGLyricsWordTimingDidChangeNotification = @"spotifyglass.lyricsWordTimingDidChange";
SGModRow *SGLyricsWordTimingRow(void) {
    SGModRow *row = SGOptionRow(SGL(@"settings.lyrics.simulate_word_timing.title", @"Simulate word timing"),
                               SGL(@"settings.lyrics.simulate_word_timing.subtitle", @"Sweeps lines timed only by the line on estimated words. Applies at once"),
                               SGKeyLyricsSimulateWords);
    row.changed = ^(BOOL on) {
        [NSNotificationCenter.defaultCenter postNotificationName:SGLyricsWordTimingDidChangeNotification object:nil];
    };
    return row;
}

// Read wherever lines are timed, so it applies as the thumb moves.
SGModRow *SGLyricsDelayRow(void) {
    return SGSliderRow(SGL(@"settings.lyrics.delay.title", @"Delay"), nil, 0, 1000, 25, ^double { return SGInt(SGKeyLyricsDelay, 0); },
                       ^(double value) { SGSetInt(SGKeyLyricsDelay, lround(value)); },
                       ^NSString *(double value) { return [NSString stringWithFormat:SGL(@"settings.lyrics.delay.format", @"%ld ms"), lround(value)]; });
}

SGModRow *SGLyricsFuriganaRow(void) {
    SGModRow *row = SGOptionRow(SGL(@"settings.lyrics.furigana.title", @"Furigana"),
                               SGL(@"settings.lyrics.furigana.subtitle", @"Readings over the kanji of Japanese songs"), SGKeyLyricsFurigana);
    row.changed = ^(BOOL on) {
        [NSNotificationCenter.defaultCenter postNotificationName:SGLyricsRomanisedDidChangeNotification object:nil];
    };
    return row;
}

SGModRow *SGSimplifyTitlesRow(void) {
    SGModRow *row = SGOptionRow(SGL(@"settings.lyrics.simplify_titles.title", @"Simplify song titles"),
                               SGL(@"settings.lyrics.simplify_titles.subtitle", @"Without (feat. …), Remastered and the like"), SGKeyLyricsSimplifyTitles);
    row.changed = ^(BOOL on) {
        [NSNotificationCenter.defaultCenter postNotificationName:SGSimplifyTitlesDidChangeNotification object:nil];
    };
    return row;
}

SGModRow *SGLyricsLanguageRulesRow(void) {
    return SGStatActionRow(SGL(@"settings.lyrics.language_rules.title", @"Clear language rules…"),
                          SGL(@"settings.lyrics.language_rules.subtitle", @"Rules are made from the lyrics menu."), ^NSString *{
        NSUInteger count = [NSUserDefaults.standardUserDefaults dictionaryForKey:SGKeyLyricsLanguageRules].count;
        return count ? @(count).stringValue : SGL(@"settings.lyrics.language_rules.none", @"None saved");
    }, ^{
        if (![NSUserDefaults.standardUserDefaults dictionaryForKey:SGKeyLyricsLanguageRules].count) return;
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:SGL(@"settings.lyrics.language_rules.clear.title", @"Clear language rules?")
            message:SGL(@"settings.lyrics.language_rules.clear.message", @"Translation and pronunciation will use your usual settings for every song.") preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:SGL(@"common.delete", @"Delete") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
            [NSUserDefaults.standardUserDefaults removeObjectForKey:SGKeyLyricsLanguageRules];
            [NSNotificationCenter.defaultCenter postNotificationName:SGLyricsLanguageDidChangeNotification object:nil];
        }]];
        [alert addAction:[UIAlertAction actionWithTitle:SGL(@"common.cancel", @"Cancel") style:UIAlertActionStyleCancel handler:nil]];
        SGPresentDark(alert);
        [SGTopController() presentViewController:alert animated:YES completion:nil];
    });
}

static NSArray<NSString *> *askModeNames(void) {
    return @[SGL(@"settings.lyrics.ask_mode.order", @"In order"),
             SGL(@"settings.lyrics.ask_mode.words", @"Word timing first"),
             SGL(@"settings.lyrics.ask_mode.all", @"All at once")];
}

UIViewController *SGLyricsTypesPage(void) {
    NSArray *choices = @[SGL(@"settings.lyrics.types.any", @"Any"), SGL(@"settings.lyrics.types.synced", @"Synced only"),
                         SGL(@"settings.lyrics.types.words", @"Word synced only")];
    NSMutableArray *rows = [NSMutableArray array];
    for (SGLyricsProvider *provider in SGLyricsAllProviders()) {
        // Imported LRC is accepted in every format, so it has no restriction to set.
        if ([provider.key isEqualToString:SGImportedLRCKey]) continue;
        [rows addObject:SGMenuRow(provider.name, choices, ^NSString *{ return choices[SGLyricsSourceTypes(provider.key)]; },
                                 ^(NSInteger index) { SGLyricsSetSourceTypes(provider.key, index); })];
    }
    NSArray<NSString *> *notes = @[
        SGL(@"settings.lyrics.ask_mode.order.subtitle", @"Asks in order and stops at the first timed answer."),
        SGL(@"settings.lyrics.ask_mode.words.subtitle", @"Asks in order, showing timed lines while looking for word timing."),
        SGL(@"settings.lyrics.ask_mode.all.subtitle", @"Asks every source at once; the first word timing wins. Sends more requests.")];
    NSInteger mode = SGInt(SGKeyLyricsAskMode, 1);
    SGModRow *first = SGChoiceRow(SGL(@"settings.lyrics.ask_mode.title", @"Request mode"),
        notes[mode >= 0 && mode < (NSInteger)notes.count ? mode : 1], SGKeyLyricsAskMode, askModeNames(), 1);
    first.choiceNotes = notes;
    __weak SGModRow *weakFirst = first;
    first.chosen = ^(NSInteger index) { weakFirst.subtitle = notes[index]; };
    return [[SGModPage alloc] initWithTitle:SGL(@"settings.lyrics.types.title", @"Request mode & lyric types") intro:nil
        sections:@[SGSection(nil, @[first]), SGSection(SGL(@"settings.lyrics.sources.header", @"Sources"), rows)] footer:nil];
}

SGModRow *SGLyricsTypesRow(void) {
    SGModRow *row = SGPageRow(SGL(@"settings.lyrics.types.title", @"Request mode & lyric types"), ^UIViewController *{ return SGLyricsTypesPage(); });
    row.value = ^NSString *{
        NSInteger mode = SGInt(SGKeyLyricsAskMode, 1);
        NSArray<NSString *> *names = askModeNames();
        return names[mode >= 0 && mode < (NSInteger)names.count ? mode : 1];
    };
    return row;
}
