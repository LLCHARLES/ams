#import <NaturalLanguage/NaturalLanguage.h>
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Shared/Lyrics/Lyrics.h"
#import "AIServicesInternal.h"

NSNotificationName const SGTranslatedTitleDidChangeNotification = @"spotifyglass.translatedTitleDidChange";
NSNotificationName const SGTitleTranslationSettingsDidChangeNotification = @"spotifyglass.titleTranslationSettingsDidChange";

static NSRegularExpression *expression(NSString *scripts) {
    static NSDictionary *expressions;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableDictionary *compiled = [NSMutableDictionary dictionary];
        for (NSString *name in @[@"L", @"Latin", @"Hangul", @"Hiragana|Katakana|Han", @"Hiragana|Katakana",
                                 @"Han", @"Cyrillic", @"Greek", @"Arabic", @"Hebrew", @"Thai", @"Devanagari"]) {
            NSString *parts = [name stringByReplacingOccurrencesOfString:@"|" withString:@"}|\\p{"];
            compiled[name] = [NSRegularExpression regularExpressionWithPattern:[NSString stringWithFormat:@"\\p{%@}", parts]
                                                                        options:0 error:nil];
        }
        expressions = [compiled copy];
    });
    return expressions[scripts];
}
static BOOL contains(NSString *text, NSString *scripts) {
    return [expression(scripts) rangeOfFirstMatchInString:text options:0 range:NSMakeRange(0, text.length)].location != NSNotFound;
}
BOOL SGLyricsTitleLatinArtist(NSString *artist) {
    if (![artist isKindOfClass:NSString.class] || artist.length > 64000 || !contains(artist, @"Latin")) return NO;
    NSString *other = [expression(@"Latin") stringByReplacingMatchesInString:artist options:0 range:NSMakeRange(0, artist.length) withTemplate:@""];
    return !contains(other, @"L");
}
BOOL SGLyricsTitleNeedsTranslation(NSString *title, NSString *languageTag) {
    if (![title isKindOfClass:NSString.class] || !title.length || title.length > 64000 || !SGGoogleTargetLanguage(languageTag) || !contains(title, @"L")) return NO;
    NSString *target = [[[languageTag stringByReplacingOccurrencesOfString:@"_" withString:@"-"] componentsSeparatedByString:@"-"] firstObject].lowercaseString;
    if ([target isEqual:@"iw"]) target = @"he";
    // Short titles give uncertain language guesses. A different writing system still supplies evidence;
    // shared Han characters alone do not distinguish Chinese from Japanese.
    NSDictionary *scripts = @{@"ko": @"Hangul", @"ja": @"Hiragana|Katakana|Han", @"zh": @"Han", @"yue": @"Han",
        @"ru": @"Cyrillic", @"uk": @"Cyrillic", @"bg": @"Cyrillic", @"el": @"Greek", @"ar": @"Arabic", @"fa": @"Arabic", @"he": @"Hebrew",
        @"th": @"Thai", @"hi": @"Devanagari"};
    NSString *script = scripts[target];
    if (!script && [@[@"en", @"fr", @"de", @"es", @"it", @"pt", @"nl", @"sv", @"da", @"no", @"nb", @"fi", @"pl", @"cs", @"vi", @"id", @"tr", @"ro"] containsObject:target]) script = @"Latin";
    if (script && !contains(title, script)) return YES;
    NSMutableDictionary *thread = NSThread.currentThread.threadDictionary;
    NSString *key = @"spotifyglass.titleLanguageRecognizer";
    NLLanguageRecognizer *recognizer = thread[key];
    if (!recognizer) thread[key] = recognizer = [NLLanguageRecognizer new];
    [recognizer reset];
    [recognizer processString:title];
    NSDictionary *hypotheses = [recognizer languageHypothesesWithMaximum:1];
    NSString *found = hypotheses.allKeys.firstObject;
    if (!found || [found isEqual:@"und"] || [hypotheses[found] doubleValue] < 0.8) return NO;
    NSString *source = [[found componentsSeparatedByString:@"-"] firstObject];
    if ([target isEqual:@"ja"] && [source isEqual:@"zh"] && !contains(title, @"Hiragana|Katakana")) return NO;
    return ![source isEqual:target];
}

// Main owns each request and cache. Successful identities remain remembered after result eviction,
// so repeated label updates do not spend another call (200 results; 2000 successful identities).
static NSMutableSet *sg_succeeded;
static NSMutableDictionary *sg_titles, *sg_pending, *sg_attempts;
static NSMutableArray *sg_order, *sg_successOrder;
static NSTimeInterval titleNow(void) {
#ifdef SG_LYRICS_TEST_STORE
    extern NSTimeInterval SGLyricsTitleTestTime(void);
    return SGLyricsTitleTestTime();
#else
    return NSProcessInfo.processInfo.systemUptime;
#endif
}
void SGLyricsTitleSettingsChanged(void) {
    if (!NSThread.isMainThread) { dispatch_async(dispatch_get_main_queue(), ^{ SGLyricsTitleSettingsChanged(); }); return; }
    [sg_attempts removeAllObjects];
    [sg_pending removeAllObjects];
    // Invalidate synchronously, but refresh labels later so a settings write never re-enters setText:.
    dispatch_async(dispatch_get_main_queue(), ^{
        [NSNotificationCenter.defaultCenter postNotificationName:SGTitleTranslationSettingsDidChangeNotification object:nil];
    });
}
NSNotificationName const SGLyricsTranslationServiceSettingsDidChangeNotification = @"spotifyglass.translationServiceSettingsDidChange";
void SGLyricsTranslationServiceSettingsChanged(void) {
    if (!NSThread.isMainThread) { dispatch_async(dispatch_get_main_queue(), ^{ SGLyricsTranslationServiceSettingsChanged(); }); return; }
    SGLyricsTitleSettingsChanged();
    [NSNotificationCenter.defaultCenter postNotificationName:SGLyricsTranslationServiceSettingsDidChangeNotification object:nil];
}

static NSArray *titleConfiguration(void) {
    BOOL local = SGFlag(SGKeyLyricsTranslateOnDevice, YES) && SGOnDeviceTranslation.translationAvailable;
    NSString *online = nil, *base = @"", *model = @"";
    if (SGFlag(SGKeyLyricsBingTranslate, NO)) online = @"bing";
    else if (SGFlag(SGKeyLyricsGoogleTranslate, NO)) online = @"google";
    else if (SGDeepLKeySet()) online = @"deepl";
    else if (SGGeminiKeySet()) { online = @"gemini"; model = SGGeminiModel(); }
    else if (SGClaudeKeySet()) { online = @"claude"; model = [NSUserDefaults.standardUserDefaults stringForKey:SGKeyLyricsClaudeModel] ?: @""; }
    else if (SGOpenAIKeySet()) {
        online = @"openai";
        base = [NSUserDefaults.standardUserDefaults stringForKey:SGKeyLyricsOpenAIBaseURL] ?: @"";
        model = [NSUserDefaults.standardUserDefaults stringForKey:SGKeyLyricsOpenAIModel] ?: @"";
    }
    return local || online ? @[@(local), online ?: @"", base, model] : nil;
}

static NSArray<SGKaraokeLine *> *titleLines(NSString *title, NSString *artist) {
    NSMutableArray *lines = [NSMutableArray array];
    for (NSString *text in @[title, artist]) {
        SGKaraokeWord *word = [SGKaraokeWord new]; word.text = text;
        SGKaraokeLine *line = [SGKaraokeLine new]; line.words = @[word];
        [lines addObject:line];
    }
    return lines;
}
static void translateTitle(NSString *track, NSArray<SGKaraokeLine *> *lines, NSString *language, void (^done)(NSArray *, NSString *)) {
    // A distinct memo name keeps this pair away from a two-line song's lyrics.
    NSString *memo = [@"title:" stringByAppendingString:track];
    if (SGFlag(SGKeyLyricsBingTranslate, NO)) SGLyricsTranslateWithBing(memo, lines, language, done);
    else if (SGFlag(SGKeyLyricsGoogleTranslate, NO)) SGLyricsTranslateWithGoogle(memo, lines, language, done);
    else if (SGDeepLKeySet()) SGLyricsTranslateWithDeepL(memo, lines, language, done);
    else if (SGGeminiKeySet()) SGLyricsTranslateWithGeminiFormat(memo, lines, language, SGLyricsReplyJSON, done);
    else if (SGClaudeKeySet()) SGLyricsTranslateWithClaudeFormat(memo, lines, language, SGLyricsReplyJSON, done);
    else if (SGOpenAIKeySet()) SGLyricsTranslateWithOpenAIFormat(memo, lines, language, SGLyricsReplyJSON, done);
    else done(nil, nil);
}
NSString *SGLyricsTranslatedTitle(NSString *trackID, NSString *title, NSString *artist, NSString **artistOut) {
    if (artistOut) *artistOut = nil;
    if (!NSThread.isMainThread || !SGFlag(SGKeyLyricsTranslateTitles, NO) || ![trackID isKindOfClass:NSString.class] || !trackID.length || trackID.length > 1024 ||
        ![title isKindOfClass:NSString.class] || !title.length || title.length > 64000 || (artist && ![artist isKindOfClass:NSString.class]) || artist.length > 64000) return nil;
    artist = artist ?: @"";
    NSString *language = SGLyricsGeminiLanguage();
    NSArray *identity = @[trackID, title, artist, language];
    NSDictionary *saved = sg_titles[identity];
    if (saved) {
        [sg_order removeObject:identity]; [sg_order addObject:identity];
        if (artistOut) *artistOut = saved[@"translatedArtist"];
        return saved[@"translatedTitle"];
    }
    if ([sg_succeeded containsObject:identity] || sg_pending[identity] || !SGLyricsTitleNeedsTranslation(title, language)) return nil;
    NSArray *configuration = titleConfiguration();
    if (!configuration) return nil;   // Enabling the first service must be able to try this same song.
    if (!sg_titles) {
        sg_titles = [NSMutableDictionary dictionary]; sg_pending = [NSMutableDictionary dictionary]; sg_attempts = [NSMutableDictionary dictionary];
        sg_order = [NSMutableArray array]; sg_succeeded = [NSMutableSet set]; sg_successOrder = [NSMutableArray array];
    }
    NSDictionary *previous = sg_attempts[identity];
    NSUInteger attempts = [previous[@"configuration"] isEqual:configuration] ? [previous[@"count"] unsignedIntegerValue] : 0;
    if (attempts && (attempts >= 2 || titleNow() < [previous[@"retryAfter"] doubleValue])) return nil;
    // Bound failure bookkeeping too. There is no retry timer; label updates may retry once after 30s.
    if (!previous && sg_attempts.count >= 2000) [sg_attempts removeObjectForKey:sg_attempts.allKeys.firstObject];
    sg_attempts[identity] = @{@"configuration": configuration, @"count": @(attempts + 1), @"retryAfter": @(titleNow() + 30)};
    NSObject *ticket = [NSObject new];
    sg_pending[identity] = ticket;
    NSArray *lines = titleLines(title, artist);
    BOOL keepArtist = SGLyricsTitleLatinArtist(artist);
    __block BOOL finished = NO;
    void (^done)(NSArray *, NSString *) = ^(NSArray *answer, NSString *problem) {
        if (finished) return;
        finished = YES;
        if (sg_pending[identity] != ticket) return;
        [sg_pending removeObjectForKey:identity];
        if (!SGFlag(SGKeyLyricsTranslateTitles, NO) || ![SGLyricsGeminiLanguage() isEqual:language]) {
            [sg_attempts removeObjectForKey:identity];
            return;
        }
        if (!sg_attempts[identity] && sg_attempts.count >= 2000) [sg_attempts removeObjectForKey:sg_attempts.allKeys.firstObject];
        sg_attempts[identity] = @{@"configuration": configuration, @"count": @(attempts + 1), @"retryAfter": @(titleNow() + 30)};
        // A switch or language change while the request was running must not put the old title on screen.
        if (![answer isKindOfClass:NSArray.class] || answer.count != 2 ||
            ![answer[0] isKindOfClass:NSString.class] || ![answer[1] isKindOfClass:NSString.class] || ![answer[0] length] || [answer[0] length] > 64000 || [answer[1] length] > 64000) return;
        if (sg_order.count >= 200) { [sg_titles removeObjectForKey:sg_order.firstObject]; [sg_order removeObjectAtIndex:0]; }
        sg_titles[identity] = @{@"translatedTitle": answer[0],
            @"translatedArtist": keepArtist || ![answer[1] length] ? artist : answer[1]};
        [sg_order removeObject:identity]; [sg_order addObject:identity];
        [sg_attempts removeObjectForKey:identity];
        if (sg_successOrder.count >= 2000) { [sg_succeeded removeObject:sg_successOrder.firstObject]; [sg_successOrder removeObjectAtIndex:0]; }
        [sg_succeeded addObject:identity]; [sg_successOrder addObject:identity];
        [NSNotificationCenter.defaultCenter postNotificationName:SGTranslatedTitleDidChangeNotification object:trackID];
    };
    dispatch_async(dispatch_get_main_queue(), ^{
        if (sg_pending[identity] != ticket || !SGFlag(SGKeyLyricsTranslateTitles, NO) || ![SGLyricsGeminiLanguage() isEqual:language]) { done(nil, nil); return; }
        if (SGFlag(SGKeyLyricsTranslateOnDevice, YES) && SGOnDeviceTranslation.translationAvailable) {
            [SGOnDeviceTranslation translate:@[title, artist] to:language done:^(NSArray *answer, NSString *problem) {
                if (sg_pending[identity] != ticket || !SGFlag(SGKeyLyricsTranslateTitles, NO) || ![SGLyricsGeminiLanguage() isEqual:language]) { done(nil, nil); return; }
                if (answer.count == 2 && [answer[0] length]) done(answer, problem);
                else if (SGFlag(SGKeyLyricsTranslateTitles, NO)) translateTitle(trackID, lines, language, done);
                else done(nil, problem);
            }];
        } else translateTitle(trackID, lines, language, done);
    });
    return nil;
}
SGModRow *SGTranslateTitlesRow(void) {
    SGModRow *row = SGOptionRow(SGL(@"settings.translation.titles.title", @"Translate song titles"),
        SGL(@"settings.translation.titles.subtitle", @"The title and artist go to the first translator that is on"), SGKeyLyricsTranslateTitles);
    row.changed = ^(BOOL on) { SGLyricsTitleSettingsChanged(); };
    return row;
}
