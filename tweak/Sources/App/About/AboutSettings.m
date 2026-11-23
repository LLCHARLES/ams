#import "Core/SGCore.h"
#import "Settings/SGPageStyle.h"
#import "About.h"
#import "App/Onboarding/Onboarding.h"
#import "Shared/AutoMix/AutoMix.h"
#import "Shared/Lossless/LosslessQuality.h"
#import "Shared/LyricsSources/LyricsSources.h"
#import "Shared/LyricsTranslation/LyricsTranslation.h"

// Every key of the mod's is under one prefix, so a reset is a sweep of the defaults with the stock
// marker of SGPrefs.h left behind; the hooks read them at launch, so it ends in a restart.
static void resetAll(void) {
    // Spotify's own settings that AutoMix and Lossless changed go back first, while the keys that hold them are there.
    SGAutoMixApply(NO);
    SGLosslessLowerQuality(NO);
    NSUserDefaults *store = NSUserDefaults.standardUserDefaults;
    NSUInteger removed = 0;
    for (NSString *key in [store persistentDomainForName:NSBundle.mainBundle.bundleIdentifier].allKeys) {
        if (![key hasPrefix:@"spotifyglass."]) continue;
        [store removeObjectForKey:key];
        removed++;
    }
    [store setBool:YES forKey:SGKeyStock];
    SGLog(@"reset: removed %lu keys", (unsigned long)removed);
    SGRestartSpotify();
}

static void confirmReset(void) {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:SGL(@"settings.mod.reset.alert.title", @"Reset all settings?")
                                                                  message:SGL(@"ui.every.switch.goes.off.5f7e53", @"Every switch goes off, flag overrides and the tab bar layout are cleared, and Spotify restarts as it came, with the mod doing nothing until asked. Spotify's own settings are untouched.")
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:SGL(@"settings.mod.reset.action.reset_and_restart", @"Reset and restart") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) { resetAll(); }]];
    [alert addAction:[UIAlertAction actionWithTitle:SGL(@"common.cancel", @"Cancel") style:UIAlertActionStyleCancel handler:nil]];
    [SGTopController() presentViewController:alert animated:YES completion:nil];
}

// Reset all leaves the Keychain alone, so a key outlives a reset; this takes every item Vitrine keeps there.
static void confirmClearKeychain(void) {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:SGL(@"settings.mod.keychain.alert.title", @"Clear Keychain?")
                                                                  message:SGL(@"ui.the.gemini.openai.compatible.df899d", @"The Gemini, OpenAI-compatible and Anthropic API keys, the OpenAI-compatible server and the Spicy Lyrics key are removed from this iPhone. Settings stay as they are.")
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:SGL(@"settings.mod.keychain.title", @"Clear Keychain") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        SGAIForgetKeys();
        SGSpicyLyricsForgetKey();
        SGLog(@"reset: keychain cleared");
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:SGL(@"common.cancel", @"Cancel") style:UIAlertActionStyleCancel handler:nil]];
    [SGTopController() presentViewController:alert animated:YES completion:nil];
}

static SGModRow *withSymbol(SGModRow *row, NSString *symbol) {
    row.symbol = symbol;
    return row;
}

// Which build this is, whether GitHub has a newer release, and where to reach the mod: without these
// rows a build that is already installed has no way of telling its user that anything moved on.
UIViewController *SGAboutPage(void) {
    SGModRow *reset = withSymbol(SGActionRow(SGL(@"settings.mod.reset.title", @"Reset all settings"), nil, ^{ confirmReset(); }), @"trash");
    reset.color = SGRed();
    SGModRow *clearKeys = withSymbol(SGActionRow(SGL(@"settings.mod.keychain.title", @"Clear Keychain"), nil, ^{ confirmClearKeychain(); }), @"key");
    clearKeys.color = SGRed();
    NSString *spotify = SGSpotifyVersion();
    if ([SGSpotifyLikelyWorksVersions containsObject:spotify]) spotify = [spotify stringByAppendingString:@", likely works"];
    else if (![SGSpotifySupportedVersions containsObject:spotify]) spotify = [NSString stringWithFormat:@"%@, made for %@", spotify, SGSpotifyMadeFor];
    // The row reads out where the build stands and opens the changelog of everything newer than it.
    SGModRow *updates = SGPageRow(SGL(@"settings.mod.update.title", @"Updates"), ^UIViewController *{ return SGUpdatePage(); });
    updates.value = ^NSString *{ return SGUpdateStatus(); };
    // A release build can opt into betas; a beta build starts opted in. Either way a check follows at
    // once, since the stored list only holds what counted at the last one.
    SGModRow *betas = SGSwitchRow(SGL(@"settings.mod.include_betas.title", @"Include betas"), SGL(@"settings.mod.include_betas.subtitle", @"Offer test builds ahead of each release"), SGKeyUpdateBetas);
    betas.defaultOn = SGBuildIsBeta();
    betas.changed = ^(BOOL on) { SGCheckForUpdate(YES); };
    NSMutableArray<SGModRow *> *links = [NSMutableArray array];
    if (SGRepoURL) [links addObject:withSymbol(SGLinkRow(SGL(@"ui.github.5442e2", @"GitHub"), nil, SGRepoURL), @"chevron.left.forwardslash.chevron.right")];
    [links addObjectsFromArray:@[
        withSymbol(SGPageRow(SGL(@"settings.mod.licenses.title", @"Licenses"), ^UIViewController *{ return SGLicensesPage(); }), @"doc.text"),
        withSymbol(SGActionRow(SGL(@"settings.mod.tour.title", @"Welcome tour"), nil, ^{ SGShowOnboarding(); }), @"map"),
    ]];
    if (SGWhatsNewChanges().count) [links insertObject:withSymbol(SGActionRow(SGL(@"settings.mod.whats_new.title", @"What's New"), nil, ^{ SGShowWhatsNew(); }), @"sparkles") atIndex:links.count - 1];
    // Language of the mod's own screens. System follows Spotify's language; the other three are explicit.
    SGModRow *language = SGChoiceRow(SGL(@"settings.mod.language.title", @"Language"), nil, SGKeyLanguage,
        @[ SGL(@"settings.mod.language.system", @"System"),
           SGL(@"settings.mod.language.english", @"English"),
           SGL(@"settings.mod.language.korean", @"한국어"),
           SGL(@"settings.mod.language.chinese", @"简体中文") ], 0);
    language.choiceFooter = SGL(@"settings.mod.language.footer", @"Applies after you restart Spotify.");
    NSMutableArray<SGModRow *> *build = [NSMutableArray arrayWithObjects:updates, betas, language,
        SGStatRow(SGL(@"settings.mod.version.title", @"Version"), ^NSString *{ return SGVersionWithBuild(); }),
        SGStatRow(SGL(@"settings.liveactivity.colors.choice.spotify", @"Spotify"), ^NSString *{ return spotify; }), nil];
    SGModRow *signedUntil = SGSigningExpiryRow();
    if (signedUntil) [build addObject:signedUntil];
    return [[SGModPage alloc] initWithTitle:SGL(@"settings.mod.title", @"Mod") intro:nil sections:@[
        SGSection(nil, build),
        SGSection(nil, links),
        SGSection(nil, @[
            withSymbol(SGActionRow(SGL(@"settings.mod.export_settings.title", @"Export settings"), nil, ^{ SGExportSettings(); }), @"square.and.arrow.up"),
            withSymbol(SGActionRow(SGL(@"settings.mod.import_settings.title", @"Import settings"), nil, ^{ SGImportSettings(); }), @"square.and.arrow.down"),
            withSymbol(SGActionRow(SGL(@"settings.mod.share_diagnostics.title", @"Share diagnostics"), SGL(@"settings.mod.share_diagnostics.subtitle", @"For a bug report: versions, ad counts, this launch's log and Spotify's config. Song names can show."),
                                   ^{ SGShareDiagnostics(); }), @"stethoscope"),
        ]),
        SGSection(nil, @[clearKeys, reset]),
    ] footer:nil];
}

NSString *SGVersionWithBuild(void) {
    const char *stamp = SGBuildStamp();
    return stamp[0] ? [NSString stringWithFormat:@"%s (%s)", SG_VERSION, stamp] : @(SG_VERSION);
}
