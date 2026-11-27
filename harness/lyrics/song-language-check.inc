#import "Redesigned/Lyrics/SongLanguage.h"

static void songLanguageChecks(void) {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSArray *keys = @[SGKeyLyricsTrackLanguages, SGKeyLyricsLanguageRules,
                      SGRKeyLyricsTranslation, SGRKeyLyricsPronunciation];
    NSMutableDictionary *saved = [NSMutableDictionary dictionary];
    for (NSString *key in keys) saved[key] = [defaults objectForKey:key] ?: NSNull.null;
    NSString *previousTrack = SGHarnessPlayingTrack;
    NSString *track = @"language-menu-first";
    NSArray *lines = @[sungLine(0, @"こんにちは 世界")];
    SGLyricsSetTrackLanguage(track, @"en");
    SGLyricsSetLanguageRule(@"ja", YES, YES);
    SGLyricsSetLanguageRule(@"en", YES, YES);
    SGHarnessPlayingTrack = track;
    __block BOOL analysed = NO;
    __block NSString *detectedLanguage = nil;
    SGRAnalyzeLyricsLanguage(lines, @"en", ^(BOOL foreign, NSString *detected) { analysed = YES; detectedLanguage = detected; });
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:60];
    while (!analysed && deadline.timeIntervalSinceNow > 0)
        [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.001]];
    check(analysed, @"song language is available before constructing its settled menu");
    __block BOOL applied = NO;
    UIMenu *menu = SGRSongLanguageMenu(track, detectedLanguage, ^{ applied = YES; });
    UIMenuElement *pick = itemIn(menu, SGRLanguageName(@"ja"));
    UIMenuElement *automatic = itemIn(menu, @"Automatic");
    UIMenuElement *keep = itemIn(menu, [NSString stringWithFormat:@"Keep for %@ Songs", SGRLanguageName(@"en")]);
    SGHarnessPlayingTrack = @"language-menu-next";
    SGRSetLyricsTextShown(SGRLyricsTextTranslation, NO);
    SGRSetLyricsTextShown(SGRLyricsTextPronunciation, NO);
    BOOL tapped = tap(pick);
    check(tapped && [SGLyricsTrackLanguage(track) isEqual:@"en"] && !shown() &&
          ![defaults boolForKey:SGRKeyLyricsPronunciation] && !applied,
          @"a stale language pick changes neither song metadata nor the current song's switches");

    SGLyricsSetTrackLanguage(track, @"en");
    SGRSetLyricsTextShown(SGRLyricsTextTranslation, NO);
    SGRSetLyricsTextShown(SGRLyricsTextPronunciation, NO);
    applied = NO;
    tapped = tap(automatic);
    check(tapped && [SGLyricsTrackLanguage(track) isEqual:@"en"] && !shown() &&
          ![defaults boolForKey:SGRKeyLyricsPronunciation] && !applied,
          @"a stale Automatic action does not clear the old song's language or apply its detected rule");

    SGRSetLyricsTextShown(SGRLyricsTextTranslation, NO);
    SGRSetLyricsTextShown(SGRLyricsTextPronunciation, NO);
    applied = NO;
    tapped = tap(keep);
    BOOL translation = NO, pronunciation = NO;
    BOOL ruled = SGLyricsLanguageRule(@"en", &translation, &pronunciation);
    check(tapped && ruled && translation && pronunciation && !applied,
          @"a stale Keep action does not save the new song's switches under the old language");

    SGHarnessPlayingTrack = track;
    applied = NO;
    tapped = tap(pick);
    check(tapped && [SGLyricsTrackLanguage(track) isEqual:@"ja"] && shown() &&
          [defaults boolForKey:SGRKeyLyricsPronunciation] && applied,
          @"a current language pick still changes the language and follows its rule");
    applied = NO;
    tapped = tap(automatic);
    check(tapped && !SGLyricsTrackLanguage(track) && shown() &&
          [defaults boolForKey:SGRKeyLyricsPronunciation] && applied,
          @"a current Automatic action still clears the override and follows the detected language");

    SGLyricsSetTrackLanguage(track, @"en");
    SGRSetLyricsTextShown(SGRLyricsTextTranslation, YES);
    SGRSetLyricsTextShown(SGRLyricsTextPronunciation, NO);
    menu = SGRSongLanguageMenu(track, detectedLanguage, ^{ applied = YES; });
    applied = NO;
    tapped = tap(itemIn(menu, [NSString stringWithFormat:@"Keep for %@ Songs", SGRLanguageName(@"en")]));
    ruled = SGLyricsLanguageRule(@"en", &translation, &pronunciation);
    check(tapped && ruled && translation && !pronunciation && applied,
          @"a current Keep action still stores the selected display switches");

    for (NSString *key in keys) {
        if (saved[key] == NSNull.null) [defaults removeObjectForKey:key];
        else [defaults setObject:saved[key] forKey:key];
    }
    SGHarnessPlayingTrack = previousTrack;
}
