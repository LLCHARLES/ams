// What the lock screen fills the screen with, the lyrics' style and whether the downloads run in Low Data
// Mode. iOS 26 and up only.
#import "Core/SGCore.h"
#import "Core/SGOptionalWork.h"
#import "Settings/SGModPage.h"
#import "Settings/SGPageStyle.h"
#import "AnimatedArtwork.h"
#import "Shared/LockScreenLyrics/SGLyricsClip.h"
#import "Shared/LyricsBackground/LyricsBackgroundSettings.h"

SGModRow *SGLoadAheadRow(void) {
    return SGSwitchRow(SGL(@"settings.load_ahead.title", @"Load ahead"),
                      SGL(@"settings.load_ahead.subtitle", @"Prepare the next track's artwork and lyrics. Turning this off does not affect the current track."),
                      SGKeyLoadAhead);
}

SGLockArtwork SGLockScreenArtwork(void) {
    if (@available(iOS 26.0, *)) {
        // The old switch's YES and NO read as Moving artwork and Off, the enum's first two.
        static dispatch_once_t once;
        dispatch_once(&once, ^{ SGMigrateKey(SGKeyLockScreenMotion, SGKeyLockScreenArtwork); });
        return (SGLockArtwork)SGInt(SGKeyLockScreenArtwork, SGLockArtworkOff);
    }
    return SGLockArtworkOff;
}

NSArray *SGLockScreenMotionRows(void) {
    if (@available(iOS 26.0, *)) {
        SGLockScreenArtwork();   // moves the old switch over before the row reads the new key
        SGModRow *style = SGChoiceRow(SGL(@"settings.lockscreen.lyrics_style.title", @"Lyrics style"), SGL(@"settings.lockscreen.lyrics_style.subtitle", @"Still draws each line once; Animated gently moves the selected background. Applies when moving artwork is unavailable."),
                                      SGKeyLockScreenLyricsStyle, @[SGL(@"settings.lockscreen.lyrics_style.choice.still", @"Still"), SGL(@"settings.lockscreen.lyrics_style.choice.animated", @"Animated")], 0);
        style.visible = ^BOOL { return SGLockArtworkShowsLyrics(SGLockScreenArtwork()); };
        SGModRow *layout = SGChoiceRow(SGL(@"settings.lockscreen.lyrics_layout.title", @"Layout"), SGL(@"settings.lockscreen.lyrics_layout.subtitle", @"Where the lyrics sit. Poster shows the line alone, larger."),
                                       SGKeyLockScreenLyricsLayout, @[SGL(@"settings.lockscreen.lyrics_layout.choice.left", @"Left"), SGL(@"settings.lockscreen.lyrics_layout.choice.centered", @"Centered"), SGL(@"settings.lockscreen.lyrics_layout.choice.poster", @"Poster"), SGL(@"settings.lockscreen.lyrics_layout.choice.messages", @"Messages"), SGL(@"settings.lockscreen.lyrics_layout.choice.vinyl", @"Vinyl"), SGL(@"settings.lockscreen.lyrics_layout.choice.over_artwork", @"Over the artwork")], 0);
        layout.visible = style.visible;
        SGModRow *dim = SGOptionRow(SGL(@"settings.lockscreen.dim_artwork.title", @"Dim the whole artwork"), SGL(@"settings.lockscreen.dim_artwork.subtitle", @"Blurs and darkens the whole artwork, moving artwork included, and floats the lyrics over it instead of shading only around them."), SGKeyLockScreenDimArtwork);
        dim.visible = ^BOOL {
            return SGLockArtworkShowsLyrics(SGLockScreenArtwork()) && SGInt(SGKeyLockScreenLyricsLayout, SGLyricsClipLeft) == SGLyricsClipOverArtwork;
        };
        SGModRow *translation = SGOptionRow(SGL(@"settings.lockscreen.translations.title", @"Translations"), SGL(@"settings.lockscreen.translations.subtitle", @"Under the line, when the lyrics have one or automatic translation makes one"), SGKeyLockScreenTranslation);
        translation.visible = style.visible;
        SGModRow *lowData = SGOptionRow(SGL(@"settings.lockscreen.low_data.title", @"Download in Low Data Mode"), SGL(@"settings.lockscreen.low_data.subtitle", @"Moving artwork, up to about 7 MB a song. Applies to animated artwork throughout Retrine."), SGKeyMotionLowData);
        lowData.visible = ^BOOL {
            SGLockArtwork artwork = SGLockScreenArtwork();
            return artwork == SGLockArtworkMotion || artwork == SGLockArtworkEverySong || artwork == SGLockArtworkMotionLyrics;
        };
        SGModRow *sources = SGMotionSourcesRow();
        sources.visible = lowData.visible;
        SGModRow *star = SGOptionRow(SGL(@"settings.lockscreen.star_switch.title", @"Switch with the star"), SGL(@"settings.lockscreen.star_switch.subtitle", @"The lock screen widget's star swaps the moving artwork for the lyrics "
                                                             @"and back. It takes the place of Spotify's like and dislike buttons"),
                                     SGKeyLockScreenStar);
        star.visible = ^BOOL { return SGLockScreenArtwork() != SGLockArtworkOff; };
        SGModRow *artwork = SGChoiceRow(SGL(@"settings.lockscreen.artwork.title", @"Full-screen artwork"), nil,
                        SGKeyLockScreenArtwork, @[SGL(@"common.off", @"Off"), SGL(@"settings.lockscreen.artwork.choice.moving", @"Moving artwork"), SGL(@"settings.lockscreen.artwork.choice.lyrics", @"Lyrics"), SGL(@"settings.lockscreen.artwork.choice.every_song", @"Every song"), SGL(@"settings.lockscreen.artwork.choice.moving_with_lyrics", @"Moving artwork with lyrics")],
                        SGLockArtworkOff);
        artwork.choiceNotes = @[
            SGL(@"settings.lockscreen.artwork.note.off", @"Leaves Spotify's artwork unchanged."),
            SGL(@"settings.lockscreen.artwork.note.moving", @"The Canvas or Apple Music's animated cover."),
            SGL(@"settings.lockscreen.artwork.note.lyrics", @"Lyrics, a line at a time."),
            SGL(@"settings.lockscreen.artwork.note.every_song", @"Uses moving artwork when available; otherwise uses your selected background."),
            SGL(@"settings.lockscreen.artwork.subtitle", @"Puts the lyrics over the Canvas or animated cover."),
        ];
        NSMutableArray *rows = [@[
            artwork,
            style,
            layout,
            dim,
            translation,
            star,
            sources,
            lowData,
        ] mutableCopy];
        NSArray<SGModRow *> *background = SGLyricsBackgroundRows(@"spotifyglass.lockscreen.background");
        background.firstObject.subtitle = SGL(@"settings.background.mode.subtitle", @"Used when moving artwork is unavailable.");
        for (SGModRow *row in background) {
            BOOL (^visible)(void) = row.visible;
            row.visible = ^BOOL {
                SGLockArtwork picked = SGLockScreenArtwork();
                return (picked == SGLockArtworkEverySong || SGLockArtworkShowsLyrics(picked)) && (!visible || visible());
            };
        }
        [rows insertObjects:background atIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(3, background.count)]];
        [rows addObject:SGArtworkCacheRow()];
        return rows;
    }
    return @[SGLockScreenArtworkNeedsRow(), SGArtworkCacheRow()];
}

#pragma mark - downloaded covers and artist photos

// Main queue. The size shown is measured off main when the row is built and again after each clear; a measurement
// or clear that began before the epoch last changed no longer owns the row.
static NSString *sg_cacheSize;
static BOOL sg_cacheMeasuring, sg_cacheClearing;
static NSUInteger sg_cacheEpoch;

static NSString *cacheDetail(void) {
    if (sg_cacheClearing) return SGL(@"settings.artwork_clear.clearing", @"Clearing…");
    if (sg_cacheSize) return sg_cacheSize;
    if (!sg_cacheMeasuring) {
        sg_cacheMeasuring = YES;
        NSUInteger epoch = sg_cacheEpoch;
        SGMotionCacheBytes(^(uint64_t bytes) {
            if (epoch != sg_cacheEpoch) return;
            sg_cacheMeasuring = NO;
            sg_cacheSize = [NSByteCountFormatter stringFromByteCount:(long long)bytes countStyle:NSByteCountFormatterCountStyleFile];
        });
    }
    return SGL(@"settings.artwork_clear.calculating", @"Calculating…");
}

static void clearCache(void) {
    if (sg_cacheClearing) return;
    sg_cacheClearing = YES;
    sg_cacheEpoch++;
    sg_cacheMeasuring = NO;
    sg_cacheSize = nil;
    SGMotionCacheClear(^(BOOL complete) {
        sg_cacheClearing = NO;
        sg_cacheEpoch++;
        if (!complete)
            SGPresentInformation(SGTopController(), SGL(@"settings.artwork_clear.title", @"Clear Downloaded Covers and Artist Photos"),
                                 SGL(@"settings.artwork_clear.failed", @"Some files couldn't be removed."));
    });
}

static void confirmClearCache(void) {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:SGL(@"settings.artwork_clear.alert.title", @"Clear Downloaded Covers and Artist Photos?")
                                                                  message:SGL(@"settings.artwork_clear.alert.message", @"Animated covers and artist photos are fetched again when needed. Your songs are not touched.")
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:SGL(@"common.cancel", @"Cancel") style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:SGL(@"settings.artwork_clear.alert.action", @"Clear") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) { clearCache(); }]];
    [SGTopController() presentViewController:alert animated:YES completion:nil];
}

SGModRow *SGArtworkCacheRow(void) {
    if (!sg_cacheClearing) {   // a page opened again measures again
        sg_cacheEpoch++;
        sg_cacheMeasuring = NO;
        sg_cacheSize = nil;
    }
    return SGStatActionRow(SGL(@"settings.artwork_clear.title", @"Clear Downloaded Covers and Artist Photos"), nil, ^NSString *{ return cacheDetail(); }, ^{ confirmClearCache(); });
}

// Below iOS 26 the section stays, with one row that says why there is nothing to pick.
SGModRow *SGLockScreenArtworkNeedsRow(void) {
    return SGStatActionRow(SGL(@"settings.lockscreen.artwork.row.title", @"Full-screen artwork"), nil, ^NSString *{ return SGL(@"settings.lockscreen.needs_ios26.status", @"Needs iOS 26"); }, ^{
        NSString *message = [NSString stringWithFormat:SGL(@"settings.lockscreen.needs_ios26.alert.message", @"This iPhone has iOS %@. The lock screen takes moving artwork "
                                                       @"from apps from iOS 26 on, so the Canvas and Apple Music's animated "
                                                       @"covers can show there once the iPhone is updated."), UIDevice.currentDevice.systemVersion];
        SGPresentInformation(SGTopController(), SGL(@"settings.lockscreen.needs_ios26.alert.title", @"Needs iOS 26"), message);
    });
}
