#import "Core/SGCore.h"
#import "Core/SGOptionalWork.h"
#import "Shared/AppIcon/AppIcon.h"
#import "Shared/Fonts/Fonts.h"
#import "Shared/LyricsTranslation/LyricsTranslation.h"
#import "Redesigned/Player/Player.h"
#import "Settings/SGModPage.h"
#import "Settings/SGPageStyle.h"
#import "Pages.h"
#import "Shared/ArtistBlock/ArtistBlock.h"
#import "Shared/Gestures/Gestures.h"
#import "Shared/Lyrics/Lyrics.h"
#import "Shared/LyricsMeanings/Meanings.h"
#import "Shared/Player/PlayerSettings.h"
#import "Shared/Player/AudioQuality.h"
#import "Shared/Sing/Sing.h"
#import "Native/Appearance/Appearance.h"
#import "Native/Navbar/Navbar.h"
#import "Native/NowPlayingBar/NowPlayingBar.h"
#import "Native/Player/NowPlaying.h"
#import "Shared/LiveActivity/LiveActivity.h"
#import "Shared/Lossless/SGLossless.h"
#import "Shared/LocalFiles/LocalAudioImport.h"
#import "Redesigned/Lyrics/LyricsText.h"
#import "Redesigned/Lyrics/LyricsLook.h"
#import "Redesigned/Lyrics/LyricsTools.h"
#import "Redesigned/Lyrics/AutoTranslation.h"
#import "Redesigned/Navbar/Navbar.h"
#import "Redesigned/NowPlayingBar/NowPlayingBar.h"
#import "Redesigned/Kit/SGRAccent.h"
#import "Redesigned/Kit/SGRPagePreview.h"
#import "Redesigned/Search/Search.h"
#import "Redesigned/Library/Library.h"
#import "Native/Home/Home.h"
#import "Shared/AdBlock/AdBlock.h"

NSString *SGRedesignedUIInfoText(void) {
    return SGL(@"settings.redesign.info", @"Redesigned uses Retrine's Apple Music-inspired interface. Native keeps Spotify's interface. Appearance settings are separate for each look; shared features work in both. Switching requires a restart.");
}

// Below iOS 26 the redesign also needs SGKeyRedesignUntested (Core/SGUIMode.h): whoever calls this has
// shown the warning. Turning it off takes that back, so turning it on again warns again.
void SGSetRedesignedUI(BOOL on) {
    SGSetEnabled(SGKeyRedesign, on);
    SGSetEnabled(SGKeyRedesignUntested, on && !SGRedesignAvailable());
}

NSString *SGRedesignUntestedWarning(void) {
    return [NSString stringWithFormat:SGL(@"settings.redesign.untested.alert.message", @"The redesign is built on iOS 26's Liquid Glass. iOS %@ draws a blur in its place, and nobody has tested the redesign there: pages can be laid out wrongly, and Spotify can freeze as it starts. If Spotify does not start with it, the next launch goes back to Native."),
            UIDevice.currentDevice.systemVersion];
}

// The whole look changes hands at launch, so the switch asks for the restart straight away rather than
// leaving Spotify half in the old look.
static void offerRestart(BOOL on) {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:SGL(@"settings.redesign.restart.alert.title", @"Restart Spotify")
        message:on ? SGL(@"settings.redesign.restart_on.alert.message", @"The redesign takes over when Spotify starts again. Spotify closes now; open it again to see it.") : SGL(@"settings.redesign.restart_off.alert.message", @"Spotify's own look comes back when Spotify starts again. Spotify closes now; open it again to see it.")
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:SGL(@"common.later", @"Later") style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:SGL(@"settings.redesign.action.restart_now", @"Restart now") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { SGRestartSpotify(); }]];
    SGPresentDark(alert);
    [SGTopController() presentViewController:alert animated:YES completion:nil];
}

// Below iOS 26 the switch stores the warning's key, not the look's: it is on only once the warning has
// been accepted, which restarts Spotify at once, so the switch never reads on for a look that is not coming.
static SGModRow *untestedRow(void) {
    SGModRow *row = SGOptionRow(SGL(@"settings.redesign.title", @"Redesigned UI"), [NSString stringWithFormat:SGL(@"settings.redesign.untested.subtitle", @"Untested on iOS %@"), UIDevice.currentDevice.systemVersion], SGKeyRedesignUntested);
    row.glows = YES;
    row.info = SGRedesignedUIInfo;
    row.changed = ^(BOOL on) {
        if (!on) {
            SGSetRedesignedUI(NO);
            offerRestart(NO);
            return;
        }
        SGSetEnabled(SGKeyRedesignUntested, NO);   // the page reloads to off; the warning's button turns it on
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:SGL(@"settings.redesign.confirm.alert.title", @"Turn on the redesign?")
            message:[SGRedesignUntestedWarning() stringByAppendingString:SGL(@"settings.redesign.confirm_restart.alert.message", @"\n\nSpotify restarts to turn it on.")]
            preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:SGL(@"common.cancel", @"Cancel") style:UIAlertActionStyleCancel handler:nil]];
        [alert addAction:[UIAlertAction actionWithTitle:SGL(@"settings.redesign.action.turn_on_and_restart", @"Turn On and Restart") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            SGSetRedesignedUI(YES);
            SGRestartSpotify();
        }]];
        SGPresentDark(alert);
        [SGTopController() presentViewController:alert animated:YES completion:nil];
    };
    return SGWithTile(row, @"sparkles", UIColor.systemIndigoColor);
}

SGModRow *SGRedesignedUIRow(void) {
    if (!SGRedesignAvailable()) return untestedRow();
    SGModRow *redesign = SGOptionRow(SGL(@"settings.redesign.title", @"Redesigned UI"), nil, SGKeyRedesign);
    redesign.glows = YES;
    redesign.info = SGRedesignedUIInfo;
    redesign.changed = ^(BOOL on) {
        SGSetRedesignedUI(on);
        offerRestart(on);
    };
    return SGWithTile(redesign, @"sparkles", UIColor.systemIndigoColor);
}

// The words the search finds these rows by besides their titles (SGModRow.searchKeywords): what the settings are
// called elsewhere, and what people call what they change, in this language.
static void foundBy(NSArray<SGModRow *> *rows, NSString *keywords) {
    for (SGModRow *row in rows) SGSearchKeywords(row, keywords);
}

// The name the search remembers a page row of these pages as when its results lead there (SGModRow.searchIdentifier):
// a page row has no key to be named by, and the name must not be its title, which the language changes. Pages whose
// rows differ by look are under a look-named row already, or say the look here.
static SGModRow *named(SGModRow *row, NSString *name) {
    return SGSearchIdentified(row, [NSString stringWithFormat:@"page.%@", name]);
}

// The stored look's own rows, then the font and the app icon, which work under either look on any iOS.
// Redesigned UI itself leads Mod Settings' main page.
//
// A row is remembered by the search under its own key (SGModRow.searchIdentifier falls back to it), which is already
// the look's: the native look's Accent color rows store under SGKeyAccent and SGKeyAmoled, the redesign's under
// SGRKeyAccent and SGRKeyAccentAuto, so one recent place can never lead into the other look's setting. The rows of
// either look's list that have no key of their own (the accent preset and color rows, whose keys their blocks hold)
// carry a searchIdentifier set where they are built.
UIViewController *SGAppearancePage(void) {
    NSMutableArray<SGModRow *> *everywhere = [NSMutableArray arrayWithArray:SGAppFontRows()];
    SGModRow *icon = SGAppIconRow();
    if (icon) [everywhere addObject:icon];
    NSArray<SGModRow *> *look = SGRedesignedUIStored() ? SGRAppearanceRows() : SGNativeAppearanceRows();
    foundBy(look, SGL(@"settings.search.appearance.look.keywords", @"theme colour color accent typeface amoled black dark"));
    foundBy(everywhere, SGL(@"settings.search.appearance.everywhere.keywords", @"typeface font app icon"));
    return [[SGModPage alloc] initWithTitle:SGL(@"settings.appearance.title", @"Appearance") intro:SGRestartNote sections:@[
        SGSection(nil, look),
        SGSection(nil, everywhere),
    ] footer:nil];
}

UIViewController *SGNavbarPage(void) {
    return SGRedesignedUIStored() ? SGRNavbarSettingsPage() : SGNavbarSettingsPage();
}

UIViewController *SGSearchLibrarySettingsPage(void) {
    NSString *title = SGL(@"settings.main.search_library.title", @"Search & Library");
    NSString *search = SGL(@"settings.search_tab.title", @"Search");
    if (SGRedesignedUIStored()) {
        SGModSection *library = SGRLibrarySection();
        return SGRPairedPreviewPage(title, SGRSearchPreview(), SGRLibraryPreview(), @[search, library.title], SGRestartNote,
                                    [SGRSearchSections() arrayByAddingObject:library]);
    }
    return [[SGModPage alloc] initWithTitle:title intro:SGRestartNote sections:@[
        SGSection(search, @[SGOptionRow(SGL(@"settings.privacy.hide_search_carousel.title", @"Hide the video carousel in Search"), nil, SGKeyHideSearchVideos)]),
        SGNativeLibrarySection(),
    ] footer:nil];
}

static UIViewController *translationPage(void) {
    // The on-device translators lead the services: they need no key or account.
    NSArray<SGModRow *> *services = [SGOnDeviceTranslatorRows() arrayByAddingObjectsFromArray:
        @[SGLyricsAIServiceRow(SGLyricsAIGemini), SGLyricsAIServiceRow(SGLyricsAIClaude), SGLyricsAIServiceRow(SGLyricsAIOpenAI),
          SGLyricsTranslationPromptRow(), SGDeepLKeyRow(), SGBingTranslateRow(), SGGoogleTranslateRow(), SGLyricsPronunciationNotationRow(), SGLyricsCulturalNotesRow()]];
    return [[SGModPage alloc] initWithTitle:SGL(@"settings.lyrics.translation_ai.title", @"Translation & AI") intro:nil sections:@[
        SGSection(SGL(@"settings.lyrics.translation_ai.automatic.header", @"Automatic translation"),
                  @[SGLyricsTranslationLanguageRow(), SGRAutoTranslationRow(), SGRAutoTranslationOrderRow(),
                    SGTranslateEverySongRow(), SGLyricsLanguageRulesRow(), SGTranslateTitlesRow()]),
        SGNotedSection(SGL(@"settings.lyrics.translation_ai.services.header", @"Services"), services,
                       SGL(@"settings.lyrics.ai.footer", @"Write Pronunciation and Explain References in the lyrics' menu use Gemini, Claude or your AI service, on your own key. What they write is kept for the song.")),
        SGSection(SGL(@"settings.lyrics.translation_ai.saved.header", @"Saved translations"), @[SGSavedTranslationsRow()]),
    ] footer:nil];
}

// Pronunciation, romanized lines, translation, word sweeping and line meanings exist only in the redesign's lyrics view.
static UIViewController *lyricsPage(void) {
    BOOL redesigned = SGRedesignedUIStored();
    NSMutableArray<SGModRow *> *more = [NSMutableArray arrayWithObject:SGLockScreenLyricsRow()];
    if (!redesigned) [more insertObject:SGGlassLyricsRow() atIndex:0];
    SGModRow *sing = SGPageRow(SGL(@"settings.lyrics.sing.title", @"Karaoke"), ^UIViewController *{ return SGSingSettingsPage(); });
    sing.value = ^NSString *{ return SGSingSummary(); };
    // The main page's own Karaoke row is page.sing; this one is the Lyrics page's.
    named(sing, @"lyrics.sing");
    NSMutableArray<SGModSection *> *sections = [NSMutableArray arrayWithObjects:SGSection(nil, @[SGWithTile(sing, @"music.mic", UIColor.systemRedColor)]),
                                                SGLyricsSourcesSection(redesigned), nil];
    SGModSection *timing = SGNotedSection(SGL(@"settings.lyrics.timing.header", @"Timing"), @[SGLyricsDelayRow()],
        redesigned ? SGL(@"settings.lyrics.timing.footer.redesigned", @"Every line shows this much later than the song, for Bluetooth headphones that play a little behind the lyrics. "
                         @"Sync in the lyrics' corner menu adds an offset for one song, and one for the headphones it plays through. Applies at once.")
                   : SGL(@"settings.lyrics.timing.footer", @"Every line shows this much later than the song, for Bluetooth headphones that play a little behind the lyrics. Applies at once."));
    if (redesigned) {
        SGModRow *translation = SGPageRow(SGL(@"settings.lyrics.translation_ai.title", @"Translation & AI"), ^UIViewController *{ return translationPage(); });
        // Reuse the language row's value reader, including its fallback for an unset selection.
        translation.value = SGLyricsTranslationLanguageRow().value;
        named(translation, @"lyrics.translation");
        [sections addObjectsFromArray:@[
            SGSection(SGL(@"settings.lyrics.display.header", @"Display"), @[
                SGWithNew(named(SGPageRow(SGL(@"settings.lyricsstyle.title", @"Lyrics styles"), ^UIViewController *{ return SGRLyricsStylesSettingsPage(); }), @"lyricsstyles"), @"lyricsStyles"),
                SGRLyricsTextSizesRow(), SGLyricsWordTimingRow(), SGLyricsRomanisedRow(),
                SGLyricsJapaneseReadingRow(), SGLyricsFuriganaRow(), SGRLyricsKeepAwakeRow(), SGRLyricsFullRateRow(),
                SGOptionRow(SGL(@"settings.lyrics.break_labels.title", @"Name the breaks"), SGL(@"settings.lyrics.break_labels.subtitle", @"Intro, Interlude or Outro beside the dots"), SGRKeyLyricsBreakLabels),
                SGSimplifyTitlesRow(),
                SGRLyricsHideRow(),
                SGRLyricsKeepMicRow(),
                SGSwitchRow(SGL(@"settings.lyrics.landscape.title", @"Landscape lyrics"), SGL(@"settings.lyrics.landscape.subtitle", @"Turn the phone with the lyrics open"), SGRKeyLyricsLandscape)]),
            timing,
            SGSection(nil, @[translation]),
            SGSection(nil, @[SGLyricsMeaningsRow()]),
        ]];
    } else {
        [sections addObject:timing];
    }
    [sections addObject:SGSection(nil, more)];
    // The redesign's page leads with its lyrics playing in the look the page sets, and that look's presets.
    if (redesigned) return SGRLyricsSettingsPage(SGL(@"settings.lyrics.title", @"Lyrics"), SGL(@"settings.lyrics.intro", @"The look, romanization, furigana, estimated word timing, delay and automatic translation apply without restarting. Other changes may need a Spotify restart."), sections);
    return [[SGModPage alloc] initWithTitle:SGL(@"settings.lyrics.title", @"Lyrics") intro:SGRestartNote sections:sections footer:nil];
}

// Lyrics has its own row on Mod Settings' main page, beside Sing.
UIViewController *SGLyricsSettingsPage(void) {
    return lyricsPage();
}

UIViewController *SGPlaybackSettingsPage(void) {
    SGModRow *blocked = named(SGPageRow(SGL(@"settings.player.blocked_artists.title", @"Blocked artists"), ^UIViewController *{ return SGArtistBlockSettingsPage(); }), @"player.blockedartists");
    blocked.value = ^NSString *{
        return SGFlag(SGKeyArtistBlock, NO) ? @(SGBlockedArtists().count).stringValue : SGL(@"common.off", @"Off");
    };
    SGModRow *songs = named(SGPageRow(SGL(@"settings.songblock.title", @"Blocked Songs"), ^UIViewController *{ return SGSongBlockSettingsPage(); }), @"player.blockedsongs");
    songs.value = ^NSString *{ return @(SGBlockedSongs().count).stringValue; };

    SGModRow *local = named(SGPageRow(SGL(@"settings.localfiles.title", @"Local files"), ^UIViewController *{ return SGLocalFilesSettingsPage(); }), @"player.localfiles");
    local.value = ^NSString *{ return @([NSUserDefaults.standardUserDefaults arrayForKey:SGKeyLocalAudioImported].count).stringValue; };
    return [[SGModPage alloc] initWithTitle:SGL(@"settings.playback.title", @"Playback & local files") intro:nil sections:@[
        SGPlaybackRulesSection(blocked, songs),
        SGNotedSection(SGL(@"settings.playback.local", @"Local audio & lossless"), @[
            SGOptionRow(SGL(@"settings.lossless.files.title", @"Lossless files"), SGL(@"settings.lossless.files.subtitle", @"Your own FLACs in place of Spotify's stream"), SGKeyLossless),
            local,
        ], SGL(@"settings.lossless.footer", @"Put FLAC or ALAC files in Files › Spotify › Lossless. A file plays when its title and length match the song "
           @"and its sound matches what Spotify plays, from about 4 s after the song starts or you seek. Spotify still "
           @"streams its own copy, at its lowest quality while the next song has a file. Karaoke and speeds other than "
           @"1x keep Spotify's sound. Applies after you restart Spotify.")),
        SGSection(SGL(@"settings.playback.data", @"Data & prefetch"), @[SGLoadAheadRow()]),
    ] footer:nil];
}

UIViewController *SGPlayerSettingsPage(void) {
    BOOL native = !SGRedesignedUIStored();
    // AirPods gestures, the lock screen widget and Vibrations have rows of their own on Mod Settings' main page.
    NSMutableArray<SGModSection *> *sections = [NSMutableArray arrayWithObject:SGSection(nil, @[
        SGWithTile(named(SGPageRow(SGL(@"settings.player.gestures.title", @"Gestures"), ^UIViewController *{ return SGGesturesSettingsPage(); }), @"player.gestures"), @"hand.tap", UIColor.systemBlueColor),
    ])];
    if (native) {
        [sections addObject:SGSection(nil, @[
            SGWithTile(named(SGPageRow(SGL(@"settings.player.now_playing_bar.title", @"Now playing bar"), ^UIViewController *{ return SGNowPlayingBarSettingsPage(); }), @"player.nowplayingbar"), @"rectangle.bottomthird.inset.filled", UIColor.systemPinkColor),
            SGWithTile(named(SGPageRow(SGL(@"settings.player.queue_devices.title", @"Queue & devices"), ^UIViewController *{ return SGQueueSettingsPage(); }), @"player.queue"), @"text.line.first.and.arrowtriangle.forward", UIColor.systemIndigoColor),
        ])];
        [sections addObjectsFromArray:SGNativePlayerScreenSections()];
    }
    // Switch to video is the same chip of Spotify's player under either look: a row here, and in the redesign one of the
    // Buttons chips with its Shuffle and Repeat (the native look's are in its Hide on the player section, with their own keys).
    if (native) {
        [sections addObject:SGSection(nil, @[SGNativeVideoSwitchRow()])];
    } else [sections addObject:SGRPlayerButtonsSection()];
    // Spotify's full screen cover a tap on the player's cover opens, under either look.
    [sections addObject:SGSection(nil, @[
        SGShownRow(SGL(@"settings.player.full_screen_cover.title", @"Full screen cover on tap"),
                   SGL(@"settings.player.full_screen_cover.subtitle", @"A tap on the cover shows it alone. Off while Gestures is on."),
                   SGKeyHideFullScreenCover),
    ])];
    // The audio quality badge under the progress bar, under either look and at once (Shared/Player/AudioQuality.h).
    SGModRow *quality = SGOptionRow(SGL(@"settings.player.audio_quality.title", @"Audio quality"),
                                    SGL(@"settings.player.audio_quality.subtitle", @"The quality Spotify plays the song in, under the progress bar"),
                                    SGKeyPlayerAudioQuality);
    quality.changed = ^(BOOL on) { SGAudioQualitySettingChanged(); };
    [sections addObject:SGNotedSection(nil, @[quality],
        SGL(@"settings.player.audio_quality.footer", @"Applies at once. Tap the badge for the sample rate and where the song comes from. "
            @"With Lossless files on, it still shows what Spotify streams, not your file."))];

    // The redesign's page leads with a card of its player and the background's control, the background's
    // rows and the Mini player section under it.
    if (!native) return SGRPlayerSettingsPage(sections);
    return [[SGModPage alloc] initWithTitle:SGL(@"settings.player.title", @"Player") intro:SGRestartNote sections:sections footer:nil];
}
