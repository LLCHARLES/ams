#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <OSLog/OSLog.h>
#import <sys/utsname.h>
#import "Core/SGCore.h"
#import "Core/SGDataRoot.h"
#import "Shared/AdBlock/AdBlock.h"
#import "Shared/SponsorBlock/SponsorBlock.h"
#import "Shared/Lyrics/Lyrics.h"
#import "Shared/Flags/Flags.h"
#import "Settings/SGPageStyle.h"
#import "About.h"
#import "SGDiagnosticRedaction.h"
#import "Redesigned/Player/Player.h"

// Install-local state must survive replacement as well as stay out of the exported document.
static BOOL isSetting(NSString *key) {
    if (![key hasPrefix:@"spotifyglass."]) return NO;
    if (SGPrivatePreferenceKey(key) || [key isEqual:SGKeySponsorBlockServer] || [key isEqual:SGKeyLyricsOpenAIBaseURL] ||
        [key isEqual:@"spotifyglass.wireguard"] || [key isEqual:SGKeyRedesignUntested] ||
        ([key hasPrefix:@"spotifyglass.dsp."] && [key hasSuffix:@".file"])) return NO;
    for (NSString *local in @[@"spotifyglass.adblock.counts", @"spotifyglass.privacy.counts", @"spotifyglass.update.",
                              @"spotifyglass.signing.", @"spotifyglass.onboarding.", @"spotifyglass.navbar.stock",
                              @"spotifyglass.redesign.navbar.stock", @"spotifyglass.automix.saved",
                              @"spotifyglass.lossless.savedQuality", @"spotifyglass.liveActivity.startedAt",
                              @"spotifyglass.font.file", @"spotifyglass.font.name", @"spotifyglass.localFiles.",
                              @"spotifyglass.localfiles.imported", @"spotifyglass.audioPresets"]) {
        if ([key hasPrefix:local]) return NO;
    }
    return YES;
}

static NSDictionary *storedDefaults(void) {
    return [NSUserDefaults.standardUserDefaults persistentDomainForName:NSBundle.mainBundle.bundleIdentifier] ?: @{};
}

static UIAlertController *showAlert(UIViewController *presenter, NSString *title, NSString *message, UIAlertAction *confirm, void (^cancelled)(void)) {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    SGPresentDark(alert);
    if (confirm) [alert addAction:confirm];
    [alert addAction:[UIAlertAction actionWithTitle:confirm ? SGL(@"common.cancel", @"Cancel") : SGL(@"common.ok", @"OK") style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
        if (cancelled) cancelled();
    }]];
    [presenter presentViewController:alert animated:YES completion:nil];
    return alert;
}

static BOOL importable(NSString *key, id value, NSDictionary *registered);

static NSDictionary *exportSettings(NSDictionary *stored) {
    NSDictionary *registered = [NSUserDefaults.standardUserDefaults volatileDomainForName:NSRegistrationDomain];
    NSMutableDictionary *settings = [NSMutableDictionary dictionary];
    [stored enumerateKeysAndObjectsUsingBlock:^(NSString *key, id value, BOOL *stop) {
        if (importable(key, value, registered) && [NSJSONSerialization isValidJSONObject:@[value]]) settings[key] = value;
    }];
    return settings;
}

void SGExportSettings(void) {
    NSDictionary *file = @{
        @"mod": @(SG_VERSION),
        @"spotify": [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"unknown",
        @"settings": exportSettings(storedDefaults()),
    };
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:file options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:&error];
    NSURL *url = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:@"spotifyglass-settings.json"]];
    UIViewController *top = SGTopController();
    if (!data || ![data writeToURL:url options:NSDataWritingAtomic error:&error]) {
        showAlert(top, SGL(@"settings.mod.export_settings.title", @"Export settings"), error.localizedDescription, nil, nil);
        return;
    }
    UIActivityViewController *sheet = [[UIActivityViewController alloc] initWithActivityItems:@[url] applicationActivities:nil];
    sheet.popoverPresentationController.sourceView = top.view;
    SGPresentDark(sheet);
    [top presentViewController:sheet animated:YES completion:nil];
}

static NSMutableString *diagnosticMetadata(void) {
    NSMutableString *text = [NSMutableString string];
    struct utsname machine;
    uname(&machine);
    [text appendFormat:@"Retrine %s, Spotify %@, iOS %@, %s\n", SG_VERSION,
        [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"unknown",
        UIDevice.currentDevice.systemVersion, machine.machine];
    [text appendFormat:@"look %@, hide ads %d, hide upsells %d, spoof premium %d, EeveeSpotify %d\n\n",
        SGRedesignedUIStored() ? @"redesign" : @"native", SGHidden(SGKeyHideAds), SGHidden(SGKeyHideUpsells),
        SGHidden(SGKeyFakePremium), SGEeveeSpotifyInjected()];
    [text appendString:@"== ads blocked (stopped of checked)\n"];
    for (NSString *label in SGAdBlockLabels()) {
        NSUInteger checked = SGAdBlockChecked(label);
        [text appendFormat:@"%@: %lu%@\n", label, (unsigned long)SGAdBlockCount(label),
            checked == NSNotFound ? @"" : [NSString stringWithFormat:@" of %lu", (unsigned long)checked]];
    }
    return text;
}

static dispatch_queue_t diagnosticWriter(void) {
    static dispatch_queue_t writer;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ writer = dispatch_queue_create("spotifyglass.diagnostics.export", DISPATCH_QUEUE_SERIAL); });
    return writer;
}

static NSString *const diagnosticLogPrefix = @"[spotifyglass] ";
static NSPredicate *diagnosticLogPredicate(void) {
    return [NSPredicate predicateWithFormat:@"composedMessage BEGINSWITH %@ AND NOT composedMessage BEGINSWITH %@",
            diagnosticLogPrefix, [diagnosticLogPrefix stringByAppendingString:@"screen dump"]];
}

// Only the writer queue reads the system log and writes diagnostic files.
static NSError *writeDiagnostics(NSMutableString *text, NSURL *url) {
        // Release builds keep no log of their own. Retain only the newest matching lines, even
        // when a whole day's launch holds tens of thousands.
        [text appendString:@"\n== log, this launch\n"];
        NSError *error = nil;
        OSLogStore *store = [OSLogStore storeWithScope:OSLogStoreCurrentProcessIdentifier error:&error];
        NSPredicate *ours = diagnosticLogPredicate();
        const NSUInteger limit = 1500;
        NSMutableArray<NSString *> *lines = [NSMutableArray arrayWithCapacity:limit];
        NSUInteger oldest = 0;
        for (OSLogEntry *entry in [store entriesEnumeratorWithOptions:0 position:nil predicate:ours error:&error]) {
            @autoreleasepool {
                NSString *line = [NSString stringWithFormat:@"%@ %@", entry.date, [entry.composedMessage substringFromIndex:diagnosticLogPrefix.length]];
                if (lines.count < limit) [lines addObject:line];
                else {
                    lines[oldest] = line;
                    oldest = (oldest + 1) % limit;
                }
            }
        }
        for (NSUInteger i = 0; i < lines.count; i++)
            [text appendFormat:@"%@%@", i ? @"\n" : @"", lines[(oldest + i) % lines.count]];
        if (!lines.count) [text appendFormat:@"(none: %@)", error.localizedDescription ?: @"the log is empty"];
        NSURL *caches = SGDataRoot(NSCachesDirectory);
        NSString *config = [NSString stringWithContentsOfURL:[caches URLByAppendingPathComponent:@"live-config.txt"]
                                                    encoding:NSUTF8StringEncoding error:nil];
        [text appendFormat:@"\n\n== config Spotify's server last sent\n%@", config ?: @"(none yet: Spoof Premium is off, or no fetch so far)\n"];
        NSError *writeError = nil;
        NSString *safe = SGRedactDiagnostics(text, NSUserDefaults.standardUserDefaults.dictionaryRepresentation);
        [safe writeToURL:url atomically:YES encoding:NSUTF8StringEncoding error:&writeError];
        if (writeError) SGLog(@"diagnostics export failed: %@", writeError.localizedDescription);
        return writeError;
}

void SGExportDiagnosticsToURL(NSURL *url, void (^completion)(NSError *error)) {
    NSMutableString *text = diagnosticMetadata();
    dispatch_async(diagnosticWriter(), ^{
        NSError *error = writeDiagnostics(text, url);
        if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(error); });
    });
}

// NativeDownloads resolves this exact signature with dlsym from its report queue.
NSURL *SGWriteDiagnosticsFile(void) {
    __block NSMutableString *text;
    dispatch_sync(dispatch_get_main_queue(), ^{ text = diagnosticMetadata(); });
    NSURL *url = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:@"retrine-diagnostics.txt"]];
    __block NSError *error;
    dispatch_sync(diagnosticWriter(), ^{ error = writeDiagnostics(text, url); });
    return error ? nil : url;
}

BOOL SGDiagnosticsCanPresentFrom(UIViewController *presenter) {
    if (!presenter.viewIfLoaded.window) return NO;
    for (UIViewController *page = presenter; page; page = page.parentViewController) {
        if (page.presentedViewController || page.isBeingPresented || page.isBeingDismissed || page.transitionCoordinator) return NO;
    }
    return YES;
}

void SGShareDiagnostics(UIViewController *presenter) {
    static BOOL exporting;   // main thread, from the settings action and the export's completion
    if (exporting || !SGDiagnosticsCanPresentFrom(presenter)) return;
    exporting = YES;
    __weak UIViewController *weakPresenter = presenter;
    NSURL *url = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:@"retrine-diagnostics.txt"]];
    SGExportDiagnosticsToURL(url, ^(NSError *error) {
        exporting = NO;
        UIViewController *owner = weakPresenter;
        if (!SGDiagnosticsCanPresentFrom(owner)) return;
        if (error) {
            showAlert(owner, SGL(@"settings.mod.share_diagnostics.title", @"Share diagnostics"), error.localizedDescription, nil, nil);
            return;
        }
        UIActivityViewController *sheet = [[UIActivityViewController alloc] initWithActivityItems:@[url] applicationActivities:nil];
        sheet.popoverPresentationController.sourceView = owner.view;
        SGPresentDark(sheet);
        [owner presentViewController:sheet animated:YES completion:nil];
    });
}

static Class kindOf(id value) {
    for (Class kind in @[NSNumber.class, NSString.class, NSArray.class, NSDictionary.class]) {
        if ([value isKindOfClass:kind]) return kind;
    }
    return Nil;
}

// Most settings use fallback arguments, not NSRegistrationDomain. Describe those portable
// settings here; never let the document itself decide the type of an unset preference.
static Class settingClass(NSString *key, NSDictionary *registered) {
    Class kind = kindOf(registered[key]);
    if (kind) return kind;
    if (![key hasPrefix:@"spotifyglass."]) return Nil;
    NSString *name = [key substringFromIndex:@"spotifyglass.".length];
    static NSSet *numbers, *strings, *stringLists, *numberLists;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        numbers = [NSSet setWithArray:[@"accent accent.custom adblock.ads adblock.premium adblock.searchVideos adblock.upsells aiBadges albumBackdrop amoled "
            "artistBlock artistBlock.featured artistPhotoFade automix automix.artwork automix.show-progress automix.show-queue automix.style blockTelemetry cleanSharedLinks "
            "font gestures gestures.hold gestures.hold.speed gestures.split gestures.step haptics.controls haptics.controls.strength haptics.music haptics.music.strength "
            "haptics.music.background haptics.music.follows haptics.music.mode headgestures headgestures.chime headgestures.nod headgestures.sensitivity headgestures.shake "
            "homeGradientTint homeGradientStrength homeGradientHeight redesign.fluid.speed redesign.fluid.warp redesign.fluid.blur redesign.fluid.saturation "
            "redesign.fluid.brightness redesign.fluid.grain redesign.fluid.renderer redesign.haptics.controls redesign.haptics.controls.strength "
            "redesign.haptics.music redesign.haptics.music.strength redesign.haptics.music.follows redesign.liveActivity redesign.liveActivity.view "
            "lockscreen.motion lyrics.typeFirst hideExplicit homeGradient language likelyAIBadges liveActivity liveActivity.alignment liveActivity.artwork liveActivity.colors liveActivity.progressBar "
            "liveActivity.textSize liveActivity.translation liveActivity.view liveActivity.withoutLyrics loadAhead lockScreenLyrics lockScreenLyrics.line lockscreen.artwork "
            "lockscreen.dimArtwork lockscreen.lyricsLayout lockscreen.lyricsStyle lockscreen.star lockscreen.star.back lockscreen.translation lossless lyrics.appleIntelligence "
            "lyrics.askMode lyrics.besideEevee lyrics.bingTranslate lyrics.culturalNotes lyrics.googleTranslate lyrics.offline lyrics.pip lyrics.pip.alignment lyrics.pip.info "
            "lyrics.pip.layout lyrics.pronunciationNotation lyrics.translateEverySong lyrics.translateOnDevice lyrics.translateTitles lyricsAllTracks lyricsCard lyricsCredit "
            "lyricsDelay lyricsFurigana lyricsJapaneseKana lyricsMeanings lyricsPreferWordTiming lyricsPronunciationHangul lyricsRomanised lyricsSimulateWords lyricsTranslationLanguage "
            "motion.lowdata navbar player player.audioQuality playerBackdrop playlistBackdrop redesign redesign.accent redesign.accent.auto redesign.accent.custom redesign.accentPlay "
            "redesign.album.adaptiveCover redesign.album.artistPicture redesign.album.fullCover redesign.album.motion redesign.album.notesPlace redesign.album.playCounts "
            "redesign.album.playCounts.place redesign.album.playCounts.source redesign.album.trackNumbers redesign.artist.adaptivePhoto redesign.artist.applePhoto "
            "redesign.artist.cutOutPlay redesign.artist.listenersInAbout redesign.artist.logo redesign.artist.motion redesign.artist.roundPlay redesign.glass.interactive "
            "redesign.glass.material redesign.glass.tint redesign.hero.scrollVeil redesign.hideExplicit redesign.home.hidePodcasts redesign.home.keepTitle redesign.home.look "
            "redesign.home.previews redesign.home.shortcutGlass redesign.home.songSuggestions redesign.home.topPicks redesign.home.topPicksColour redesign.home.topPicksHeading "
            "redesign.inlinePlayer.artist redesign.library.hideChips redesign.lyrics.autoHide redesign.lyrics.autoTranslation redesign.lyrics.breakLabels redesign.lyrics.fullRate "
            "redesign.lyrics.keepAwake redesign.lyrics.landscape redesign.lyricsPronunciation redesign.lyricsTranslation redesign.navbar redesign.navbar.fade redesign.navbar.hideLabels "
            "redesign.navbar.minimize redesign.navbar.symbols redesign.nowPlayingBar.artworkShape redesign.nowPlayingBar.inlineConnect redesign.nowPlayingBar.nextButton "
            "redesign.pageTitleWhenScrolled redesign.pageZoom redesign.pages.coverBeside redesign.plainCheck redesign.playInPageColour redesign.player.animatedStill "
            "redesign.player.animatedVisualizer redesign.player.holdNoClip redesign.player.background redesign.player.background.artwork redesign.player.followsCover redesign.player.headerGlass "
            "redesign.player.hideContext redesign.player.hideRepeat redesign.player.hideShuffle redesign.player.landscape redesign.player.lyricLine redesign.player.movingBackground "
            "redesign.player.musicIcons redesign.player.rollingDigits redesign.player.starAdd redesign.player.volume redesign.playlist.coverViewer redesign.playlist.creatorLine "
            "redesign.playlist.creatorPicture redesign.playlist.description redesign.playlist.menuSortMix redesign.savedMark redesign.search.glassCards showCacheLimit simplifyTitles "
            "sing sing.button sing.ignoreHeat sing.ignoreMemory sing.prepareAhead sing.runsOn sing.spatial sleepTimer.fade speed.pitchFollows sponsorblock.enabled sponsorblock.haptics "
            "sponsorblock.minDuration sponsorblock.overlay sponsorblock.respectManualSeek stats.recap.announce stats.record stock visualizer.ignoreHeat visualizer.shuffle "
            "dsp dsp.bass dsp.bass.gain dsp.compander dsp.compander.time dsp.convolver dsp.convolver.mode dsp.crossfeed dsp.crossfeed.mode dsp.ddc dsp.eq dsp.geq dsp.limiterRelease "
            "dsp.limiterThreshold dsp.liveprog dsp.postGain dsp.reverb dsp.reverb.amount dsp.reverb.preset dsp.tube dsp.tube.drive dsp.wide dsp.wide.level "
            "headgestures.nodaction headgestures.shakeaction sing.model sing.level sing.spatial.distance sing.spatial.room sing.spatial.front sing.spatial.width lyrics.ai.timeout" componentsSeparatedByString:@" "]];
        strings = [NSSet setWithArray:[@"font.family font.library lyrics.pip.font lyrics.openai.model lyrics.claude.model lyrics.gemini.model lyrics.gemini.thinking lyrics.translationPrompt redesign.home.topPicksFrom dsp.eq.gains dsp.compander.gains dsp.geq.nodes" componentsSeparatedByString:@" "]];
        stringLists = [NSSet setWithArray:@[@"motion.sources", @"lyricsProviders", @"lyrics.knownProviders", @"redesign.lyricsTextOrder", @"navbar.split", @"redesign.navbar.split"]];
        numberLists = [NSSet setWithArray:@[@"accent.recent", @"redesign.accent.recent"]];
    });
    if ([strings containsObject:name]) return NSString.class;
    if ([numberLists containsObject:name] || [stringLists containsObject:name] ||
        [@[@"artistBlock.list", @"navbar.layout", @"redesign.navbar.layout", @"redesign.navbar.apart"] containsObject:name]) return NSArray.class;
    if ([@[@"lyrics.sourceTypes", @"lyrics.trackLanguages", @"lyrics.trackOffsets", @"lyrics.routeOffsets",
           @"gestures.zones", @"blockedSongs", @"lyrics.languageRules"] containsObject:name]) return NSDictionary.class;
    if ([numbers containsObject:name] || [name hasPrefix:@"hide."] || [name hasPrefix:@"sponsorblock.behavior."] ||
        [name hasPrefix:@"sponsorblock.category."] || ([name hasPrefix:@"redesign."] && [name containsString:@".hide."])) return NSNumber.class;
    return Nil;
}

static BOOL listOf(id value, Class kind) {
    if (![value isKindOfClass:NSArray.class]) return NO;
    for (id item in value) if (![item isKindOfClass:kind]) return NO;
    return YES;
}

static int compareFlag(const void *key, const void *definition) {
    return strcmp(key, ((const SGFlagDef *)definition)->key);
}

static BOOL importable(NSString *key, id value, NSDictionary *registered) {
    if (!isSetting(key)) return NO;
    NSString *pip = @"spotifyglass.lyrics.pip.";
    if ([key hasPrefix:pip]) {
        NSArray *parts = [[key substringFromIndex:pip.length] componentsSeparatedByString:@"."];
        if (parts.count == 2 && [@[@"original", @"pronunciation", @"translation"] containsObject:parts[0]]) {
            if (![value isKindOfClass:NSNumber.class] || CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID()) return NO;
            double n = [value doubleValue];
            if (n != floor(n)) return NO;
            if ([parts[1] isEqual:@"weight"]) return n >= 0 && n <= 3;
            if (![parts[1] isEqual:@"size"]) return NO;
            return [parts[0] isEqual:@"original"] ? n >= 24 && n <= 64 : n >= 16 && n <= 48;
        }
    }
    if ([key hasPrefix:SGFlagOverridePrefix]) {
        NSString *flag = [key substringFromIndex:SGFlagOverridePrefix.length];
        if (!flag.length || [flag containsString:@"\0"]) return NO;
        const SGFlagDef *def = bsearch(flag.UTF8String, SGFlagTable, SGFlagCount, sizeof *SGFlagTable, compareFlag);
        if (!def) return NO;
        if (def->type == SGFlagBool) return [value isEqual:@0] || [value isEqual:@1];
        return def->type == SGFlagEnum ? [value isKindOfClass:NSString.class] :
            [value isKindOfClass:NSNumber.class] || (def->type == SGFlagUnknown && [value isKindOfClass:NSString.class]);
    }
    Class kind = settingClass(key, registered);
    if (!kind || ![value isKindOfClass:kind]) return NO;
    if ([key isEqual:@"spotifyglass.artistBlock.list"]) {
        for (id artist in value)
            if (![artist isKindOfClass:NSDictionary.class] || ![artist[@"uri"] isKindOfClass:NSString.class] ||
                ![artist[@"name"] isKindOfClass:NSString.class]) return NO;
    } else if ([key hasSuffix:@".navbar.layout"] || [key isEqual:@"spotifyglass.redesign.navbar.apart"]) {
        if (!listOf(value, NSDictionary.class)) return NO;
        for (NSDictionary *tab in value) {
            if (![tab[@"id"] isKindOfClass:NSString.class]) return NO;
            for (NSString *field in @[@"title", @"uri", @"icon", @"iconSet"])
                if (tab[field] && ![tab[field] isKindOfClass:NSString.class]) return NO;
            if (tab[@"hidden"] && ![tab[@"hidden"] isKindOfClass:NSNumber.class]) return NO;
        }
    } else if (kind == NSArray.class && !registered[key]) {
        if (!listOf(value, [key hasSuffix:@".recent"] ? NSNumber.class : NSString.class)) return NO;
    } else if (kind == NSDictionary.class && !registered[key]) {
        for (id entry in [value allValues]) {
            if ([key isEqual:@"spotifyglass.gestures.zones"]) {
                if (!listOf(entry, NSNumber.class)) return NO;
            } else if ([key isEqual:@"spotifyglass.blockedSongs"]) {
                if (!listOf(entry, NSString.class) || [entry count] != 2) return NO;
            } else if ([key isEqual:@"spotifyglass.lyrics.languageRules"]) {
                if (![entry isKindOfClass:NSDictionary.class] || ![entry[@"translation"] isKindOfClass:NSNumber.class] ||
                    ![entry[@"pronunciation"] isKindOfClass:NSNumber.class]) return NO;
            } else if (![entry isKindOfClass:[key isEqual:@"spotifyglass.lyrics.trackLanguages"] ? NSString.class : NSNumber.class]) return NO;
        }
    }
    return [NSPropertyListSerialization propertyList:value isValidForFormat:NSPropertyListBinaryFormat_v1_0];
}

// Settings exported by Chroma (spoti.pw 0.50) under its own names, in ours. Its player background knows only
// Fluid (0) and Animated (1); its artwork sources call Spotify's clips "spotify". Its menu row cache and
// one-time notices have no counterpart and are left out.
static NSDictionary *fromChroma(NSDictionary *settings) {
    NSDictionary<NSString *, NSString *> *renamed = @{
        @"spotifyglass.redesign.sing": @"spotifyglass.sing",
        @"spotifyglass.redesign.sing.ignoreHeat": @"spotifyglass.sing.ignoreHeat",
        @"spotifyglass.redesign.spatialVoice": @"spotifyglass.sing.spatial",
        @"spotifyglass.redesign.player.hideVideoSwitch": @"spotifyglass.hide.videoSwitch",
        @"spotifyglass.gestures.head": @"spotifyglass.headgestures",
        @"spotifyglass.redesign.inlinePlayer": @"spotifyglass.redesign.navbar.minimize",
    };
    NSSet<NSString *> *dropped = [NSSet setWithArray:@[@"spotifyglass.redesign.menuNumbers", @"spotifyglass.eevee.warned",
                                                       @"spotifyglass.spotifyversion.warned", @"spotifyglass.lockscreen.lyricsartwork"]];
    NSMutableDictionary *ours = [NSMutableDictionary dictionary];
    for (NSString *key in settings) {
        id value = settings[key];
        if ([dropped containsObject:key]) continue;
        if ([key isEqualToString:@"spotifyglass.redesign.player.backdrop"]) {
            NSString *target = @"spotifyglass.redesign.player.background";
            if (settings[target]) continue;
            // A present but invalid legacy value is not a missing choice in a replacement backup.
            ours[target] = [value isEqual:@0] || [value isEqual:@"0"] ? @(SGRPlayerBackgroundFluid) :
                [value isEqual:@1] || [value isEqual:@"1"] ? @(SGRPlayerBackgroundAnimated) : NSNull.null;
        } else if ([key isEqualToString:@"spotifyglass.redesign.player.artworksources"] && [value isKindOfClass:NSArray.class]) {
            NSMutableArray *sources = [NSMutableArray array];
            for (NSString *source in value) [sources addObject:[source isEqual:@"spotify"] ? @"canvas" : source];
            ours[@"spotifyglass.motion.sources"] = sources;
        } else {
            ours[renamed[key] ?: key] = value;
        }
    }
    return ours;
}

static void importSettings(NSDictionary *settings, NSUserDefaults *store, NSDictionary *stored) {
    settings = fromChroma(settings);
    NSDictionary *registered = [store volatileDomainForName:NSRegistrationDomain];
    for (NSString *key in stored)
        if (!settings[key] && importable(key, stored[key], registered)) [store removeObjectForKey:key];
    NSUInteger skipped = 0;
    for (NSString *key in settings) {
        id value = settings[key];
        BOOL fits = importable(key, value, registered);
        if (fits) [store setObject:value forKey:key];
        else skipped++;
    }
    SGLog(@"import: set %lu keys, skipped %lu", (unsigned long)(settings.count - skipped), (unsigned long)skipped);
}

@interface SGSettingsPicker : NSObject <UIDocumentPickerDelegate>
@property (nonatomic, weak) UIViewController *presenter;
@property (nonatomic, weak) UIDocumentPickerViewController *picker;
@property (nonatomic) BOOL pending, reading;
- (void)finish;
@end

static const NSUInteger kSettingsImportLimitBytes = 5 * 1024 * 1024;

// The picker gives us a local copy. Reject a large file before reading it, and bound the stream too
// so a file that grows after the size check cannot make the import allocate without a limit.
static NSDictionary *readSettingsFile(NSURL *url) {
    NSNumber *size = nil;
    if (![url getResourceValue:&size forKey:NSURLFileSizeKey error:nil] || size.unsignedLongLongValue > kSettingsImportLimitBytes) return nil;
    NSInputStream *stream = [NSInputStream inputStreamWithURL:url];
    [stream open];
    NSMutableData *data = [NSMutableData data];
    uint8_t buffer[16384];
    NSInteger count = 0;
    while (data.length <= kSettingsImportLimitBytes
           && (count = [stream read:buffer maxLength:MIN(sizeof(buffer), kSettingsImportLimitBytes + 1 - data.length)]) > 0) {
        [data appendBytes:buffer length:(NSUInteger)count];
    }
    [stream close];
    if (count < 0 || data.length > kSettingsImportLimitBytes) return nil;
    id file = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    return [file isKindOfClass:NSDictionary.class] && [file[@"settings"] isKindOfClass:NSDictionary.class] ? file : nil;
}

@implementation SGSettingsPicker

- (void)finish {
    self.pending = NO;
    self.reading = NO;
    self.presenter = nil;
    self.picker = nil;
}

- (void)presentFile:(NSDictionary *)file {
    UIViewController *owner = self.presenter;
    if (!SGDiagnosticsCanPresentFrom(owner)) {
        [self finish];
        return;
    }
    NSString *title, *message;
    UIAlertAction *confirm = nil;
    if (file) {
        NSString *mod = [file[@"mod"] isKindOfClass:NSString.class] ? file[@"mod"] : @"unknown";
        title = SGL(@"settings.mod.backup.import_confirm.alert.title", @"Import settings?");
        message = [NSString stringWithFormat:SGL(@"settings.mod.backup.import_confirm.alert.message", @"Your settings are replaced by the file's, exported from version %@. Anything it does not have goes back to its default, and Spotify restarts."), mod];
        confirm = [UIAlertAction actionWithTitle:SGL(@"settings.mod.backup.action.import_and_restart", @"Import and restart") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
            [self finish];
            importSettings(file[@"settings"], NSUserDefaults.standardUserDefaults, storedDefaults());
            SGRestartSpotify();
        }];
    } else {
        title = SGL(@"settings.mod.backup.invalid_file.alert.title", @"Not a settings file");
        message = SGL(@"settings.mod.backup.invalid_file.alert.message", @"Pick a file made by Export settings.");
    }
    UIAlertController *alert = showAlert(owner, title, message, confirm, ^{ [self finish]; });
    if (owner.presentedViewController != alert) [self finish];
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)picker {
    if (self.picker == picker) [self finish];
}

- (void)documentPicker:(UIDocumentPickerViewController *)picker didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    if (!self.pending || self.reading || self.picker != picker) return;
    self.reading = YES;
    NSURL *url = urls.firstObject;
    // Finish the picker's own dismissal before reading, so even a tiny file cannot race it.
    void (^read)(void) = ^{
        if (self.picker != picker) return;
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            NSDictionary *file = readSettingsFile(url);
            dispatch_async(dispatch_get_main_queue(), ^{
                if (self.picker == picker) [self presentFile:file];
            });
        });
    };
    if (picker.isBeingDismissed && picker.transitionCoordinator) {
        [picker.transitionCoordinator animateAlongsideTransition:nil completion:^(id<UIViewControllerTransitionCoordinatorContext> context) { read(); }];
    } else if (picker.presentingViewController) {
        [picker dismissViewControllerAnimated:YES completion:read];
    } else {
        read();
    }
}

@end

void SGImportSettings(UIViewController *presenter) {
    static SGSettingsPicker *delegate;
    if (!delegate) delegate = [SGSettingsPicker new];
    if (delegate.pending || !SGDiagnosticsCanPresentFrom(presenter)) return;
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeJSON] asCopy:YES];
    delegate.pending = YES;
    delegate.presenter = presenter;
    delegate.picker = picker;
    picker.delegate = delegate;
    SGPresentDark(picker);
    [presenter presentViewController:picker animated:YES completion:nil];
    if (presenter.presentedViewController != picker) [delegate finish];
}
