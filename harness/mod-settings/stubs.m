// What Mod Settings' main page links to and reads, stood in for: every page is an empty page of its own
// name, the values beside the chevrons are what a fresh install reads, and the update check does nothing.
#import <UIKit/UIKit.h>
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Shared/LyricsTranslation/LyricsTranslation.h"
#import "Shared/Fonts/Fonts.h"
#import "Shared/Player/PlayerState.h"
#import "Redesigned/Kit/SGRBridges.h"
#import "Redesigned/Kit/SGRField.h"
#import "Redesigned/Kit/SGRHeaderInfo.h"
#import "App/About/About.h"

// The page previews' cards read the player and the artwork the redesign publishes; with no player here, they are
// never told anything, and the preview draws its placeholder instead.
void SGAddPlayerStateObserver(id<SGPlayerStateObserver> observer) {}
SPTPlayerState *SGPlayerState(void) { return nil; }
NSString *SGURIString(id uri) { return nil; }
UIImage *SGPlaceholderArtwork(UIColor *tint) { return nil; }
NSNotificationName const SGRFieldColorDidChangeNotification = @"harness.sgr.fieldcolor";
NSNotificationName const SGRNowPlayingArtworkDidChangeNotification = @"harness.sgr.artwork";
UIImage *SGRNowPlayingArtwork(NSString **trackURI, NSString **identity) { return nil; }
BOOL SGRPageFullCover(NSString *key) { return NO; }

extern BOOL SGHarnessWarning;

static UIViewController *blank(NSString *title) {
    return [[SGModPage alloc] initWithTitle:title intro:nil sections:@[] footer:nil];
}

#define PAGE(name) UIViewController *name(void) { return blank(@#name); }
PAGE(SGAdsSettingsPage) PAGE(SGAutoMixSettingsPage)
UIViewController *SGDSPSettingsPage(void) {
    SGPage *page = [SGPage new];
    page.title = @"Audio effects";
    return page;
}
UIViewController *SGAllFlagsPage(void) {
    SGPage *page = [SGPage new];
    page.title = @"All flags";
    return page;
}
PAGE(SGGesturesSettingsPage) PAGE(SGHeadGesturesSettingsPage) PAGE(SGHomeSettingsPage) PAGE(SGLabsPage)
PAGE(SGListeningStatsPage) PAGE(SGLiveActivitySettingsPage) PAGE(SGLockScreenWidgetPage) PAGE(SGNavbarSettingsPage)
PAGE(SGNowPlayingBarSettingsPage) PAGE(SGQueueSettingsPage) PAGE(SGRAlbumSettingsPage) PAGE(SGRArtistSettingsPage)
PAGE(SGRNavbarSettingsPage)
PAGE(SGLocalFilesSettingsPage)
PAGE(SGAlbumSettingsPage) PAGE(SGArtistSettingsPage) PAGE(SGPlaylistSettingsPage)
PAGE(SGDSPHeadphonesPage) PAGE(SGDSPPresetsPage) PAGE(SGFontLibraryPage)
PAGE(SGRHomeSettingsPage) PAGE(SGRLibrarySettingsPage) PAGE(SGRVisualiserSettingsPage)
PAGE(SGSingSettingsPage) PAGE(SGSpatialVoiceSettingsPage) PAGE(SGVibrationsSettingsPage)
UIViewController *SGRPlayerSettingsPage(NSArray *more) { return blank(@"SGRPlayerSettingsPage"); }
UIViewController *SGRLyricsSettingsPage(NSString *title, NSString *intro, NSArray<SGModSection *> *sections) {
    return [[SGModPage alloc] initWithTitle:title intro:intro sections:sections footer:nil];
}
// Redesigned/Lyrics/LyricsStylesSettings.m, whose cards play the real karaoke view: a blank page here.
PAGE(SGRLyricsStylesSettingsPage)
PAGE(SGLicensesPage) PAGE(SGUpdatePage) PAGE(SGReportListPage)

// AboutSettings.m builds the real Mod rows; their external actions stay offline here.
NSString *SGSpotifyVersion(void) { return @"9.1.90"; }
NSString *SGUpdateStatus(void) { return @"up to date"; }
BOOL SGBuildIsBeta(void) { return NO; }
NSArray<SGUpdateChange *> *SGWhatsNewChanges(void) { return @[]; }
void SGShowOnboarding(void) {}
void SGShowWhatsNew(void) {}
void SGExportSettings(void) {}
void SGImportSettings(UIViewController *presenter) {}
void SGShareDiagnostics(UIViewController *presenter) {}
void SGAutoMixApply(BOOL on) {}
void SGLosslessLowerQuality(BOOL lower) {}
void SGAudioQualitySettingChanged(void) {}
BOOL SGGeminiForgetKey(void) { return YES; }
BOOL SGClaudeForgetKey(void) { return YES; }
NSURL *SGHarnessStorageURI;
BOOL SGOpenSpotifyURI(NSURL *uri) { SGHarnessStorageURI = uri; return YES; }
SGModRow *SGNativeVideoSwitchRow(void) { return SGHideRow(@"Switch to video", nil, @"spotifyglass.hideVideoSwitch"); }
BOOL SGOpenAIForgetKeys(void) { return YES; }
BOOL SGDeepLForgetKey(void) { return YES; }
BOOL SGSpicyLyricsForgetKey(void) { return YES; }
BOOL SGDeezerForgetKey(void) { return YES; }
void SGLyricsTranslationServiceSettingsChanged(void) {}
NSString *SGKaraokePlayingTrack(void) { return nil; }
NSNotificationName const SGLyricsDidReloadNotification = @"harness.lyrics.reload";

#define ROW(name) SGModRow *name(void) { return SGPageRow(@#name, ^UIViewController *{ return nil; }); }
ROW(SGGeminiKeyRow) ROW(SGGlassLyricsRow) ROW(SGLockScreenLyricsRow) ROW(SGLyricsMeaningsRow)
ROW(SGLyricsTranslationLanguageRow) ROW(SGLyricsWordTimingRow) ROW(SGRLyricsTextSizesRow) ROW(SGLyricsDelayRow)
ROW(SGBingTranslateRow) ROW(SGDeepLKeyRow) ROW(SGGoogleTranslateRow) ROW(SGLyricsCulturalNotesRow)
ROW(SGLyricsFuriganaRow) ROW(SGLyricsJapaneseReadingRow) ROW(SGLyricsLanguageRulesRow) ROW(SGLyricsPiPRow)
ROW(SGLyricsPronunciationNotationRow) ROW(SGRAutoTranslationOrderRow) ROW(SGRAutoTranslationRow)
ROW(SGRLyricsKeepAwakeRow) ROW(SGRLyricsFullRateRow) ROW(SGSavedTranslationsRow) ROW(SGSimplifyTitlesRow) ROW(SGTranslateEverySongRow)
ROW(SGRLyricsHideRow)
ROW(SGTranslateTitlesRow)
NSString *SGLyricsAIName(SGLyricsAI service) { return @[@"Gemini", @"Claude", @"OpenAI"][service]; }
SGModRow *SGLyricsAIServiceRow(SGLyricsAI service) { return SGPageRow(SGLyricsAIName(service), ^UIViewController *{ return nil; }); }
// Shared/LyricsTranslation/LyricsTranslation.m: its two switches, as a fresh install has them.
NSArray<SGModRow *> *SGOnDeviceTranslatorRows(void) {
    NSArray *rows = @[SGSwitchRow(@"Translate on iPhone", @"Apple's Translate in the lyrics' translate menu and automatic translation",
                                  SGKeyLyricsTranslateOnDevice),
                      SGSwitchRow(@"Apple Intelligence", @"Apple Intelligence in the lyrics' translate menu and automatic translation",
                                  SGKeyLyricsAppleIntelligence)];
    for (SGModRow *row in rows) row.changed = ^(BOOL on) {};
    return rows;
}
SGModSection *SGSleepTimerSettingsSection(void) { return SGSection(nil, @[]); }
SGModSection *SGSponsorBlockSettingsSection(void) { return SGSection(nil, @[]); }
SGModSection *SGRPlayerButtonsSection(void) { return SGSection(nil, @[]); }
void SGMotionCacheBytes(void (^done)(uint64_t bytes)) { done(0); }
void SGMotionCacheClear(void (^done)(BOOL complete)) { done(YES); }
SGAppFont SGAppFontChosen(void) { return SGAppFontSpotify; }
NSArray<SGModRow *> *SGAppFontRows(void) { return @[]; }
NSArray<SGModRow *> *SGNativeAppearanceRows(void) { return @[]; }
NSArray<SGModRow *> *SGRAppearanceRows(void) { return @[]; }
SGModSection *SGLyricsSourcesSection(BOOL namingSource) { return SGSection(nil, @[]); }
NSArray<SGModSection *> *SGNativePlayerScreenSections(void) { return @[]; }
NSArray<NSDictionary *> *SGBlockedArtists(void) { return @[]; }
NSArray<NSDictionary *> *SGPlayingArtists(void) { return @[]; }
NSString *const SGArtistURI = @"uri", *const SGArtistName = @"name";
BOOL SGArtistBlocked(NSString *uri) { return NO; }
void SGBlockArtist(NSDictionary *artist) {}
void SGUnblockArtist(NSString *uri) {}
NSDictionary<NSString *, NSArray<NSString *> *> *SGBlockedSongs(void) { return @{}; }
void SGSetSongBlocked(NSString *uri, NSString *title, NSString *artist, BOOL blocked) {}

NSString *SGDSPSummary(void) { return @"Off"; }
NSString *SGAutoMixSummary(void) { return @"Off"; }
NSString *SGSingSummary(void) { return @"Off"; }
// An iPhone that reads headphone motion, with Spatial voice off.
BOOL SGSingSpatialAvailable(void) { return YES; }
BOOL SGSingSpatial(void) { return NO; }

void SGCheckForUpdate(BOOL force) {}
void SGWatchForUpdates(void) {}
// Signing.m is the real one: its row stays away while the harness's own signature is sound, and its
// "Signed until" row shows once the .app holds an embedded.mobileprovision (README).
BOOL SGOnboardingShowing(void) { return NO; }
// Environment.m's red row, as a phone with EeveeSpotify injected too shows it.
NSArray<SGModRow *> *SGEnvironmentWarningRows(void) {
    if (!SGHarnessWarning) return @[];
    return @[SGWarningRow(@"EeveeSpotify is injected too", @"Tap to see what that changes", ^{})];
}
// The Lyrics page's Romanized lyrics row (Shared/Lyrics/Romanise.m).
SGModRow *SGLyricsRomanisedRow(void) { return SGOptionRow(@"Romanized lyrics", nil, @"spotifyglass.harness.romanised"); }
// The lock screen's source order row (MotionSources.m), for AnimatedArtworkSettings.m.
SGModRow *SGMotionSourcesRow(void) { return SGStatRow(@"Sources", ^NSString *{ return @"Canvas, Apple Music"; }); }
// The lock screen's background rows (LyricsBackgroundSettings.m), empty here.
NSArray<SGModRow *> *SGLyricsBackgroundRows(NSString *prefix) { return @[]; }
