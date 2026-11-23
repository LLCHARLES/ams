#import <NaturalLanguage/NaturalLanguage.h>
#import "Core/SGCore.h"
#import "Shared/Lyrics/Lyrics.h"
#import "Shared/Lyrics/LyricsLanguage.h"
#import "Shared/LyricsTranslation/LyricsTranslation.h"
#import "Shared/LockScreenLyrics/LockScreenLyrics.h"
#import "AutoTranslation.h"

// Every reader and manual menu shares the SavedTranslations token for a song and language.
static NSMutableDictionary<NSString *, NSNumber *> *sgr_jobs;
static NSString *jobKey(NSString *track, NSString *language) { return [NSString stringWithFormat:@"%@|%@", track, language]; }
BOOL SGRTranslationJobRunning(NSString *track, NSString *language) {
    NSNumber *token = track.length && language.length ? sgr_jobs[jobKey(track, language)] : nil;
    return token && SGLyricsTranslationIsCurrent(track, language, token.unsignedIntegerValue);
}
void SGRForgetTranslationJob(NSString *track, NSString *language) {
    [sgr_jobs removeObjectForKey:jobKey(track, language)];
}
// Posted on main when a job starts/ends, saves or is removed. Views may hold different copies of the lines.
NSNotificationName const SGRTranslationNotification = @"spotifyglass.redesign.lyricsTranslationDidChange";
NSString *const kTranslationLines = @"lines", *const kTranslationRemoved = @"removed", *const kTranslationLanguage = @"language";
void SGRTranslationChanged(NSString *track, NSString *language, NSString *what) {
    NSMutableDictionary *info = [NSMutableDictionary dictionaryWithObject:language forKey:kTranslationLanguage];
    if (what) info[what] = @YES;
    [NSNotificationCenter.defaultCenter postNotificationName:SGRTranslationNotification object:track userInfo:info];
}

// A line with words to translate: not an empty one, nor a ♪ holding a break.
BOOL SGRLyricsHasWords(SGKaraokeLine *line) {
    for (SGKaraokeWord *word in line.words) {
        if ([word.text rangeOfCharacterFromSet:NSCharacterSet.letterCharacterSet].location != NSNotFound) return YES;
    }
    return NO;
}

// Letters outside the target's script, read from the characters: past Latin for a Latin-script language, Latin for
// any other. A short Korean line or one mixed with English, which the recognizer is not sure of, still counts.
static NSUInteger otherScriptLetters(NSString *text, BOOL latinTarget) {
    __block NSUInteger count = 0;
    [text enumerateSubstringsInRange:NSMakeRange(0, text.length) options:NSStringEnumerationByComposedCharacterSequences
                          usingBlock:^(NSString *character, NSRange range, NSRange enclosing, BOOL *stop) {
        UTF32Char c = 0;
        if (![character getBytes:&c maxLength:sizeof(c) usedLength:NULL encoding:NSUTF32LittleEndianStringEncoding options:0
                           range:NSMakeRange(0, character.length) remainingRange:NULL]) return;
        if (![NSCharacterSet.letterCharacterSet longCharacterIsMember:c]) return;
        BOOL latin = c < 0x250 || (c >= 0x1E00 && c < 0x1F00);
        if (latin != latinTarget) count++;
    }];
    return count;
}

// Words spelled the way Korean is in Latin letters, with "eo" or "eu" (neol, geureon, eotteoke). Spicy Lyrics'
// community syncs give some K-pop this way. Of twenty English songs checked, no line had two such words.
static NSUInteger romanizedKoreanWords(NSString *text) {
    NSUInteger count = 0;
    for (NSString *word in [text componentsSeparatedByCharactersInSet:NSCharacterSet.letterCharacterSet.invertedSet]) {
        if ([word containsString:@"eo"] || [word containsString:@"eu"]) count++;
    }
    return count;
}

// Whether a song is in a language other than `language`, line by line: one distinct line in five that the recognizer
// is at least 80% sure is another language, or two lines in another script (Hangul, kana, Han among English, for
// K-pop with only a verse in Korean). A line with two letters of another script counts however unsure the
// recognizer is: NewJeans' "New Jeans" has six such lines, all short or mixed with English. So does a line of Korean
// in Latin letters (romanizedKoreanWords). A chorus sung eight
// times weighs as one line. The whole song's guess is not asked: short lines sway it (it reads Havana, all "ooh
// na-na", as Dutch), and an unsure line counts neither way. A song with no line it is sure of counts as foreign,
// too little to tell.
BOOL SGRLyricsInAnotherLanguage(NSArray<SGKaraokeLine *> *lines, NSString *language) {
    NSString *(^code)(NSString *) = ^NSString *(NSString *tag) {
        return [tag componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"-_"]].firstObject.lowercaseString;
    };
    NSString *target = code(language);
    NSString *targetScript = [NSOrthography defaultOrthographyForLanguage:language].dominantScript;
    NSUInteger distinct = 0, sure = 0, foreign = 0, otherScript = 0;
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    NLLanguageRecognizer *recognizer = [NLLanguageRecognizer new];
    for (SGKaraokeLine *line in lines) {
        NSString *text = SGRLyricsHasWords(line) ? SGKaraokeLineText(line).lowercaseString : nil;
        if (!text.length || [seen containsObject:text]) continue;
        [seen addObject:text];
        distinct++;
        BOOL lettersOther = otherScriptLetters(text, [targetScript isEqualToString:@"Latn"]) >= 2;
        if (lettersOther) otherScript++;
        [recognizer reset];
        [recognizer processString:text];
        NSDictionary<NLLanguage, NSNumber *> *guess = [recognizer languageHypothesesWithMaximum:1];
        NLLanguage found = guess.allKeys.firstObject;
        BOOL confident = found && guess[found].doubleValue >= 0.8, inTarget = confident && [code(found) isEqualToString:target];
        // A line sure to be in the target language does not count as romanized Korean, so French "peu" and "heure" stay.
        if (!lettersOther && !inTarget && romanizedKoreanWords(text) >= 2) otherScript++;
        if (!confident) continue;
        sure++;
        if (inTarget) continue;
        foreign++;
        if (!lettersOther && ![[NSOrthography defaultOrthographyForLanguage:found].dominantScript isEqualToString:targetScript]) otherScript++;
    }
    return !sure || foreign * 5 >= MAX(distinct, 5) || otherScript >= 2;
}
BOOL SGRLyricsShouldTranslate(BOOL foreign) {
    return foreign || SGHidden(SGKeyLyricsTranslateEverySong);
}
void SGRAnalyzeLyricsLanguage(NSArray<SGKaraokeLine *> *lines, NSString *language,
                             void (^done)(BOOL foreign, NSString *detected)) {
    static NSCache *answers;
    static dispatch_queue_t worker;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        answers = [NSCache new]; answers.countLimit = SGLyricsLanguageCacheSongLimit;
        worker = dispatch_queue_create("com.retrine.lyrics.language", DISPATCH_QUEUE_SERIAL);
    });
    NSArray *snapshot = SGLyricsLanguageSnapshot(lines);
    NSMutableArray *texts = [NSMutableArray arrayWithCapacity:snapshot.count];
    for (SGKaraokeLine *line in snapshot) [texts addObject:SGKaraokeLineText(line) ?: @""];
    NSArray *key = @[[texts copy], [language copy] ?: @""];
    NSArray *cached = [answers objectForKey:key];
    if (cached) { done([cached[0] boolValue], [cached[1] length] ? cached[1] : nil); return; }
    dispatch_async(worker, ^{
        NSArray *answer = [answers objectForKey:key];
        if (!answer) {
            answer = @[@(SGRLyricsInAnotherLanguage(snapshot, key[1])), SGLyricsDetectedLanguage(snapshot) ?: @""];
            [answers setObject:answer forKey:key];
        }
        dispatch_async(dispatch_get_main_queue(), ^{ done([answer[0] boolValue], [answer[1] length] ? answer[1] : nil); });
    });
}
BOOL SGRLyricsTranslationAllowed(NSString *track, NSString *detectedLanguage) {
    BOOL translation = YES, pronunciation = NO;
    NSString *source = SGLyricsTrackLanguage(track) ?: detectedLanguage;
    return !(source && SGLyricsLanguageRule(source, &translation, &pronunciation) && !translation);
}

// Source translations stay; only empty/generated ones take a new answer.
static BOOL takeTranslations(NSArray<NSString *> *translations, NSArray<SGKaraokeLine *> *lines) {
    __block BOOL took = NO;
    [lines enumerateObjectsUsingBlock:^(SGKaraokeLine *line, NSUInteger i, BOOL *stop) {
        NSString *translation = i < translations.count ? translations[i] : nil;
        if (![translation isKindOfClass:NSString.class] ||
            ![translation stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length ||
            [line.translation isEqualToString:translation]) return;
        if (line.translation.length && !line.translationMade) return;
        line.translation = translation;
        line.translationMade = YES;
        took = YES;
    }];
    return took;
}

void SGRTranslateLyrics(NSArray<SGKaraokeLine *> *lines, NSString *track, NSString *language,
                        NSUInteger automaticRevision, SGRTranslator translator, dispatch_block_t started, SGRAutoTranslated done) {
    if (!lines.count || !track.length || !language.length || SGRTranslationJobRunning(track, language)) return;
    NSUInteger token = SGLyricsBeginTranslation(track, language);
    if (!token) return;
    if (automaticRevision) SGRAutoTranslationRegister(track, language, token);
    NSString *key = jobKey(track, language);
    if (!sgr_jobs) sgr_jobs = [NSMutableDictionary dictionary];
    sgr_jobs[key] = @(token);
    BOOL (^current)(void) = ^BOOL {
        return (!automaticRevision || SGRAutoTranslationRevision() == automaticRevision) &&
            SGLyricsTranslationIsCurrent(track, language, token) && [SGLyricsGeminiLanguage() isEqualToString:language];
    };
    // Keep each batch too, so closing Spotify preserves the work already done.
    void (^take)(NSArray<NSString *> *) = ^(NSArray<NSString *> *translations) {
        if (!takeTranslations(translations, lines)) return;
        SGLyricsSaveTranslation(track, language, lines);
        SGRTranslationChanged(track, language, kTranslationLines);
    };
    SGRTranslationChanged(track, language, nil);
    if (started) started();
    translator(lines, track, language, ^(NSArray<NSString *> *soFar, NSString *error) {
        if (current()) take(soFar);
    }, ^(NSArray<NSString *> *translations, NSString *error) {
        BOOL live = current();
        if (live && translations) take(translations);
        SGLyricsEndTranslation(track, language, token);
        if (automaticRevision) SGRAutoTranslationFinish(track, language, token);
        if ([sgr_jobs[key] isEqualToNumber:@(token)]) [sgr_jobs removeObjectForKey:key];
        SGRTranslationChanged(track, language, nil);
        if (live && done) done(translations, error);
    });
}

void SGRAutoTranslateWithoutView(NSString *track, NSArray<SGKaraokeLine *> *lines, BOOL (^mayContinue)(void), void (^loaded)(void)) {
    NSString *language = SGLyricsGeminiLanguage();
    if (!track.length || !lines.count || !language.length) return;
    SGLyricsLoadTranslation(track, language, lines, ^BOOL {
        return mayContinue() && [language isEqual:SGLyricsGeminiLanguage()];
    }, ^{
    loaded();
    if (!SGRAutoTranslationEnabled()) return;
    SGRAnalyzeLyricsLanguage(lines, language, ^(BOOL foreign, NSString *detected) {
    if (!mayContinue() || ![language isEqual:SGLyricsGeminiLanguage()] ||
        !SGRAutoTranslationEnabled() || !SGRLyricsShouldTranslate(foreign) ||
        !SGRLyricsTranslationAllowed(track, detected)) return;
    BOOL untranslated = NO;
    for (SGKaraokeLine *line in lines) {
        if (!line.translation.length && SGRLyricsHasWords(line)) { untranslated = YES; break; }
    }
    if (!untranslated || SGRTranslationJobRunning(track, language)) return;
    BOOL available = NO;
    for (NSNumber *provider in SGRAutoTranslationOrder()) available = available || SGRAutoTranslationAvailable(provider.integerValue, language);
    if (!available) { SGRAutoTranslationUnavailable(track, language); return; }
    NSUInteger revision = SGRAutoTranslationClaim(track, language);
    if (!revision) return;
    SGRTranslateLyrics(lines, track, language, revision,
        ^(NSArray *sent, NSString *song, NSString *to, SGRAutoTranslated progress, SGRAutoTranslated done) {
            SGRAutoTranslateInOrder(sent, song, to, revision, mayContinue, progress, done);
        }, nil, nil);
    });
    });
}

NSNotificationName const SGRAutoTranslationDidChangeNotification = @"spotifyglass.redesign.autoTranslationDidChange";
BOOL SGRAutoTranslationEnabled(void) { return SGFlag(SGRKeyLyricsAutoTranslation, NO); }
static NSArray *defaultOrder(void) {
    return @[@(SGRAutoTranslatorOnDevice), @(SGRAutoTranslatorBing), @(SGRAutoTranslatorGoogle),
        @(SGRAutoTranslatorDeepL), @(SGRAutoTranslatorGemini), @(SGRAutoTranslatorClaude),
        @(SGRAutoTranslatorOpenAI), @(SGRAutoTranslatorAppleIntelligence)];
}
static NSArray *validatedOrder(id raw) {
    NSMutableArray *order = [NSMutableArray array];
    if ([raw isKindOfClass:NSArray.class]) for (id value in raw) {
        if ([value isKindOfClass:NSNumber.class] && [defaultOrder() containsObject:value] && ![order containsObject:value]) [order addObject:value];
    }
    for (NSNumber *value in defaultOrder()) if (![order containsObject:value]) [order addObject:value];
    return order;
}
NSArray<NSNumber *> *SGRAutoTranslationOrder(void) {
    return validatedOrder([NSUserDefaults.standardUserDefaults objectForKey:SGRKeyLyricsAutoTranslationOrder]);
}
void SGRSetAutoTranslationOrder(NSArray<NSNumber *> *order) {
    [NSUserDefaults.standardUserDefaults setObject:validatedOrder(order) forKey:SGRKeyLyricsAutoTranslationOrder];
    SGRAutoTranslationSettingsChanged();
}
SGRAutoTranslationState SGRAutoTranslationStateOf(SGRAutoTranslator provider, NSString *language) {
    switch (provider) {
        case SGRAutoTranslatorOnDevice:
            if (!SGFlag(SGKeyLyricsTranslateOnDevice, YES)) return SGRAutoTranslationNeedsSwitch;
            return SGOnDeviceTranslation.translationAvailable ? SGRAutoTranslationReady : SGRAutoTranslationUnavailableDevice;
        case SGRAutoTranslatorAppleIntelligence:
            if (!SGFlag(SGKeyLyricsAppleIntelligence, YES)) return SGRAutoTranslationNeedsSwitch;
            return [SGOnDeviceTranslation appleIntelligenceAvailable:language] ? SGRAutoTranslationReady : SGRAutoTranslationUnavailableDevice;
        case SGRAutoTranslatorGoogle:
            if (!SGFlag(SGKeyLyricsGoogleTranslate, NO)) return SGRAutoTranslationNeedsSwitch;
            return SGGoogleTargetLanguage(language) ? SGRAutoTranslationReady : SGRAutoTranslationUnsupportedLanguage;
        case SGRAutoTranslatorBing:
            if (!SGFlag(SGKeyLyricsBingTranslate, NO)) return SGRAutoTranslationNeedsSwitch;
            return SGBingTargetLanguage(language) ? SGRAutoTranslationReady : SGRAutoTranslationUnsupportedLanguage;
        case SGRAutoTranslatorDeepL:
            if (!SGDeepLKeySet()) return SGRAutoTranslationNeedsKey;
            return SGDeepLTargetLanguage(language) ? SGRAutoTranslationReady : SGRAutoTranslationUnsupportedLanguage;
        case SGRAutoTranslatorGemini: return SGGeminiKeySet() ? SGRAutoTranslationReady : SGRAutoTranslationNeedsKey;
        case SGRAutoTranslatorClaude: return SGClaudeKeySet() ? SGRAutoTranslationReady : SGRAutoTranslationNeedsKey;
        case SGRAutoTranslatorOpenAI: {
            NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
            NSString *base = [defaults stringForKey:SGKeyLyricsOpenAIBaseURL] ?: @"https://api.openai.com/v1";
            NSString *model = [defaults stringForKey:SGKeyLyricsOpenAIModel] ?: @"gpt-4o-mini";
            if (!SGOpenAICompletionURL(base) || ![model stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length)
                return SGRAutoTranslationNeedsSettings;
            return SGOpenAIKeySet() ? SGRAutoTranslationReady : SGRAutoTranslationNeedsKey;
        }
        default: return SGRAutoTranslationUnavailableDevice;
    }
}
BOOL SGRAutoTranslationAvailable(SGRAutoTranslator provider, NSString *language) {
    return language.length && SGRAutoTranslationStateOf(provider, language) == SGRAutoTranslationReady;
}

// All bookkeeping is on main. Automatic work shares the manual translator's tokens, so removing a
// translation or starting a manual replacement makes an older automatic answer harmless.
static NSUInteger revision = 1;
static NSArray *configuration;
static NSMutableOrderedSet<NSArray *> *attempted, *suppressed, *freshRetries;
static NSMutableDictionary<NSArray *, NSNumber *> *active;
@interface SGRAutoTranslationProgress ()
@property (nonatomic) SGRAutoTranslationPhase phase;
@property (nonatomic) SGRAutoTranslator provider;
@property (nonatomic) SGRAutoTranslationFailure failure;
@property (nonatomic) NSUInteger completed, total, attempt;
@end
@implementation SGRAutoTranslationProgress
@end
NSNotificationName const SGRAutoTranslationProgressDidChangeNotification = @"spotifyglass.redesign.autoTranslationProgressDidChange";
static NSMutableDictionary<NSArray *, SGRAutoTranslationProgress *> *statuses;
static NSMutableOrderedSet<NSArray *> *statusOrder;
static void statusChanged(NSArray *pair) {
    [NSNotificationCenter.defaultCenter postNotificationName:SGRAutoTranslationProgressDidChangeNotification
        object:pair.firstObject userInfo:pair ? @{@"language": pair[1]} : nil];
}
static void clearStatus(NSArray *pair) {
    if (!statuses[pair]) return;
    [statuses removeObjectForKey:pair]; [statusOrder removeObject:pair]; statusChanged(pair);
}
static void publishStatus(NSArray *pair, SGRAutoTranslationPhase phase, SGRAutoTranslator provider,
                          SGRAutoTranslationFailure failure, NSUInteger completed, NSUInteger total, NSUInteger attempt) {
    SGRAutoTranslationProgress *old = statuses[pair];
    if (old && old.phase == phase && old.provider == provider && old.failure == failure &&
        old.completed == completed && old.total == total && old.attempt == attempt) return;
    SGRAutoTranslationProgress *snapshot = [SGRAutoTranslationProgress new];
    snapshot.phase = phase; snapshot.provider = provider; snapshot.failure = failure;
    snapshot.completed = completed; snapshot.total = total; snapshot.attempt = attempt;
    if (!old && statusOrder.count >= 200) { [statuses removeObjectForKey:statusOrder.firstObject]; [statusOrder removeObjectAtIndex:0]; }
    statuses[pair] = snapshot; [statusOrder removeObject:pair]; [statusOrder addObject:pair]; statusChanged(pair);
}
// Match only known local messages. Untrusted server bodies are never exposed as status text.
static SGRAutoTranslationFailure failureOf(NSString *problem) {
    NSArray *connection = @[
        SGL(@"settings.translation.openai.error.unreachable", @"The translation service could not be reached."),
        SGL(@"settings.translation.error.unreachable", @"Gemini could not be reached."),
        SGL(@"settings.translation.deepl.error.unreachable", @"DeepL could not be reached."),
        SGL(@"settings.translation.google.error.unreachable", @"Google Translate could not be reached."),
        SGL(@"settings.translation.bing.error.unreachable", @"Bing Translator could not be reached."),
        SGL(@"settings.translation.claude.error.unreachable", @"Claude could not be reached.")];
    if (problem && [connection containsObject:problem]) return SGRAutoTranslationFailureConnection;
    NSArray *authentication = @[
        SGL(@"settings.translation.openai.error.keyinvalid", @"The translation service turned the key down. Check it on the Lyrics page."),
        SGL(@"settings.translation.error.keyinvalid", @"Gemini turned the key down. Check it on the Lyrics page."),
        SGL(@"settings.translation.deepl.error.keyinvalid", @"DeepL turned the key down. Check it on the Lyrics page."),
        SGL(@"settings.translation.claude.error.keyinvalid", @"Claude turned the key down. Check it on the Lyrics page.")];
    if (problem && [authentication containsObject:problem]) return SGRAutoTranslationFailureAuthentication;
    NSArray *busy = @[
        SGL(@"settings.translation.openai.error.busy", @"The translation service is busy right now. Try again in a minute."),
        SGL(@"settings.translation.error.busy", @"Gemini is busy right now. Try again in a minute."),
        SGL(@"settings.translation.error.ratelimit", @"Gemini's limit for this key is reached for now."),
        SGL(@"settings.translation.deepl.error.busy", @"DeepL is busy right now. Try again in a minute."),
        SGL(@"settings.translation.deepl.error.quota", @"This DeepL key's translation quota is used up."),
        SGL(@"settings.translation.google.error.busy", @"Google Translate is busy right now. Try again in a minute."),
        SGL(@"settings.translation.bing.error.busy", @"Bing Translator is busy right now. Try again in a minute."),
        SGL(@"settings.translation.claude.error.busy", @"Claude is busy right now. Try again in a minute.")];
    return problem && [busy containsObject:problem] ? SGRAutoTranslationFailureBusy : SGRAutoTranslationFailureResponse;
}
static NSArray *currentConfiguration(void) {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSString *language = SGLyricsGeminiLanguage();
    NSMutableArray *states = [NSMutableArray array];
    for (NSNumber *provider in SGRAutoTranslationOrder()) [states addObject:@(SGRAutoTranslationStateOf(provider.integerValue, language))];
    return @[@(SGRAutoTranslationEnabled()), SGRAutoTranslationOrder(), language ?: @"", states,
        @(SGFlag(SGKeyLyricsTranslateEverySong, NO)),
        [defaults stringForKey:SGKeyLyricsOpenAIBaseURL] ?: @"", [defaults stringForKey:SGKeyLyricsOpenAIModel] ?: @"",
        [defaults stringForKey:SGKeyLyricsClaudeModel] ?: @""];

}
static void remember(NSMutableOrderedSet *set, NSArray *pair) {
    if ([set containsObject:pair]) return;
    if (set.count >= 2000) [set removeObjectAtIndex:0];
    [set addObject:pair];
}
static void invalidate(BOOL explicitSelection) {
    for (NSArray *pair in active) SGLyricsEndTranslation(pair[0], pair[1], active[pair].unsignedIntegerValue);
    [active removeAllObjects];
    [attempted removeAllObjects]; [freshRetries removeAllObjects];
    [statuses removeAllObjects]; [statusOrder removeAllObjects]; statusChanged(nil);
    if (explicitSelection) [suppressed removeAllObjects];
    revision++;
    configuration = currentConfiguration();
    [NSNotificationCenter.defaultCenter postNotificationName:SGRAutoTranslationDidChangeNotification object:nil];
}
static void prepare(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        attempted = [NSMutableOrderedSet orderedSet]; suppressed = [NSMutableOrderedSet orderedSet]; active = [NSMutableDictionary dictionary];
        freshRetries = [NSMutableOrderedSet orderedSet];
        statuses = [NSMutableDictionary dictionary]; statusOrder = [NSMutableOrderedSet orderedSet];
        configuration = currentConfiguration();
        for (NSNotificationName name in @[SGLyricsTranslationsDidChangeNotification, SGLyricsTranslationServiceSettingsDidChangeNotification]) {
            [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:nil usingBlock:^(NSNotification *note) {
                // Generic redraws include cultural-note visibility. Only changed translation configuration
                // or an explicit credential/provider update may restart a failed or in-flight chain.
                void (^changed)(void) = ^{
                    if ([note.name isEqual:SGLyricsTranslationServiceSettingsDidChangeNotification] ||
                        ![configuration isEqual:currentConfiguration()]) invalidate(NO);
                };
                if (NSThread.isMainThread) changed(); else dispatch_async(dispatch_get_main_queue(), changed);
            }];
        }
        [NSNotificationCenter.defaultCenter addObserverForName:SGLyricsAIResultDidChangeNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
            if (note.object) return; // A nil object means the combined saved-results store was cleared.
            void (^clear)(void) = ^{
                for (NSArray *pair in active) remember(suppressed, pair);
                NSString *track = SGKaraokePlayingTrack(), *language = SGLyricsGeminiLanguage();
                if (track.length && language.length) remember(suppressed, @[track, language]);
                invalidate(NO);
            };
            if (NSThread.isMainThread) clear(); else dispatch_async(dispatch_get_main_queue(), clear);
        }];
    });
}
NSUInteger SGRAutoTranslationRevision(void) {
    prepare();
    if (![configuration isEqual:currentConfiguration()]) invalidate(NO);
    return revision;
}
void SGRAutoTranslationSettingsChanged(void) { prepare(); invalidate(YES); }
NSUInteger SGRAutoTranslationClaim(NSString *track, NSString *language) {
    NSUInteger current = SGRAutoTranslationRevision();
    if (!track.length || !language.length) return 0;
    NSArray *pair = @[track, language];
    if ([attempted containsObject:pair] || [suppressed containsObject:pair]) return 0;
    remember(attempted, pair);
    return current;
}
void SGRAutoTranslationSuppress(NSString *track, NSString *language) {
    prepare();
    if (!track.length || !language.length) return;
    NSArray *pair = @[track, language];
    remember(suppressed, pair);
    [freshRetries removeObject:pair];
    clearStatus(pair);
    SGLyricsEndTranslation(track, language, active[pair].unsignedIntegerValue);
    [active removeObjectForKey:pair];
}
void SGRAutoTranslationRegister(NSString *track, NSString *language, NSUInteger token) {
    if (token) active[@[track, language]] = @(token);
}
void SGRAutoTranslationFinish(NSString *track, NSString *language, NSUInteger token) {
    NSArray *pair = @[track, language];
    if ([active[pair] isEqual:@(token)]) [active removeObjectForKey:pair];
}
SGRAutoTranslationProgress *SGRAutoTranslationProgressFor(NSString *track, NSString *language) {
    if (!track.length || !language.length) return nil;
    prepare();
    return statuses[@[track, language]];
}
BOOL SGRAutoTranslationRetry(NSString *track, NSString *language) {
    if (!track.length || !language.length) return NO;
    prepare();
    NSArray *pair = @[track, language];
    SGRAutoTranslationProgress *status = statuses[pair];
    if (!status || status.phase == SGRAutoTranslationPhaseRunning || status.phase == SGRAutoTranslationPhaseComplete || active[pair]) return NO;
    [attempted removeObject:pair]; [suppressed removeObject:pair]; remember(freshRetries, pair); clearStatus(pair);
    return YES;
}
void SGRAutoTranslationUnavailable(NSString *track, NSString *language) {
    if (!track.length || !language.length) return;
    prepare();
    NSArray *pair = @[track, language];
    if ([suppressed containsObject:pair] || active[pair]) return;
    publishStatus(pair, SGRAutoTranslationPhaseUnavailable, SGRAutoTranslatorOff, SGRAutoTranslationFailureNone, 0, 0, 0);
}
static void translateUsing(SGRAutoTranslator provider, NSArray<SGKaraokeLine *> *lines, NSString *track,
                      NSString *language, BOOL fresh, SGRAutoTranslated progress, SGRAutoTranslated done) {
    if (!SGRAutoTranslationAvailable(provider, language)) { done(nil, nil); return; }
    NSMutableArray *texts = [NSMutableArray arrayWithCapacity:lines.count];
    for (SGKaraokeLine *line in lines) [texts addObject:SGKaraokeLineText(line) ?: @""];
    // A nil cache identity is already supported by every remote translator. Explicit Retry must not
    // replay a cached partial answer; ordinary automatic attempts keep using their normal memo.
    NSString *cacheTrack = fresh ? nil : track;
    switch (provider) {
        case SGRAutoTranslatorOnDevice: [SGOnDeviceTranslation translate:texts to:language done:done]; break;
        case SGRAutoTranslatorAppleIntelligence: {
            [SGOnDeviceTranslation translateWithAppleIntelligence:texts to:language song:SGLyricsSongName(track)
                progress:^(NSArray *answer) { progress(answer, nil); } done:done]; break;
        }
        case SGRAutoTranslatorGoogle: SGLyricsTranslateWithGoogle(cacheTrack, lines, language, done); break;
        case SGRAutoTranslatorBing: SGLyricsTranslateWithBing(cacheTrack, lines, language, done); break;
        case SGRAutoTranslatorDeepL: SGLyricsTranslateWithDeepL(cacheTrack, lines, language, done); break;
        case SGRAutoTranslatorGemini: SGLyricsTranslateWithGemini(cacheTrack, lines, language, done); break;
        case SGRAutoTranslatorClaude: SGLyricsTranslateWithClaude(cacheTrack, lines, language, done); break;
        case SGRAutoTranslatorOpenAI: SGLyricsTranslateWithOpenAI(cacheTrack, lines, language, done); break;
        default: done(nil, nil); break;
    }
}


// One chain per shared token. Later providers fill only gaps, never overwrite a saved/source/earlier result.
@interface SGRAutoTranslationJob : NSObject
@property (nonatomic, copy) NSString *track, *language;
@property (nonatomic, copy) NSArray<SGKaraokeLine *> *lines;
@property (nonatomic, copy) NSArray<NSNumber *> *order;
@property (nonatomic, strong) NSMutableArray<NSString *> *answer;
@property (nonatomic, strong) NSMutableIndexSet *missing;
@property (nonatomic) NSUInteger revision, next, step, total, token;
@property (nonatomic) SGRAutoTranslator provider;
@property (nonatomic) SGRAutoTranslationFailure failure;
@property (nonatomic) BOOL interrupted, fresh;
@property (nonatomic) BOOL finished;
@property (nonatomic, copy) SGRAutoTranslated progress, done;
@property (nonatomic, copy) BOOL (^mayContinue)(void);
@end
@implementation SGRAutoTranslationJob
- (BOOL)current {
    if (self.finished || SGRAutoTranslationRevision() != self.revision) return NO;
    NSNumber *token = active[@[self.track, self.language]];
    return token && SGLyricsTranslationIsCurrent(self.track, self.language, token.unsignedIntegerValue);
}
- (void)finish:(BOOL)cancelled {
    if (self.finished) return;
    self.finished = YES;
    NSArray *pair = @[self.track, self.language];
    // The old chain may finish after a replacement; it must never clear or overwrite the new status.
    if ([active[pair] isEqual:@(self.token)] && revision == self.revision) {
        if (cancelled) clearStatus(pair);
        else {
            SGRAutoTranslationPhase phase = !self.missing.count ? SGRAutoTranslationPhaseComplete : self.interrupted ? SGRAutoTranslationPhasePaused :
                self.missing.count < self.total ? SGRAutoTranslationPhasePartial : SGRAutoTranslationPhaseFailed;
            publishStatus(pair, phase, self.provider, self.failure, self.total - self.missing.count, self.total, self.step);
        }
    }
    BOOL any = NO;
    for (NSString *text in self.answer) any = any || text.length;
    SGRAutoTranslated done = self.done;
    self.done = nil; self.progress = nil;
    done(!cancelled && any ? [self.answer copy] : nil, nil);
}
- (void)take:(NSArray *)values indexes:(NSArray<NSNumber *> *)indexes {
    if (![values isKindOfClass:NSArray.class] || values.count != indexes.count) return;
    NSMutableIndexSet *filled = [NSMutableIndexSet indexSet];
    [indexes enumerateObjectsUsingBlock:^(NSNumber *index, NSUInteger sent, BOOL *stop) {
        NSUInteger i = index.unsignedIntegerValue;
        if (![self.missing containsIndex:i]) return;
        id text = values[sent];
        if ([text isKindOfClass:NSString.class] && [text length] <= 64000 &&
            [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length) {
            self.answer[i] = text;
            [filled addIndex:i];
        }
    }];
    [self.missing removeIndexes:filled];
    if (filled.count) {
        publishStatus(@[self.track, self.language], SGRAutoTranslationPhaseRunning, self.provider,
            SGRAutoTranslationFailureNone, self.total - self.missing.count, self.total, self.step);
        self.progress([self.answer copy], nil);
    }
}
- (void)runNext {
    if (![self current]) { [self finish:YES]; return; }
    if (!self.missing.count) { [self finish:NO]; return; }
    if (!self.mayContinue()) { self.interrupted = YES; [self finish:NO]; return; }
    SGRAutoTranslator provider = SGRAutoTranslatorOff;
    while (self.next < self.order.count) {
        SGRAutoTranslator candidate = self.order[self.next++].integerValue;
        if (SGRAutoTranslationAvailable(candidate, self.language)) { provider = candidate; break; }
    }
    if (provider == SGRAutoTranslatorOff) { [self finish:NO]; return; }
    NSUInteger step = ++self.step;
    self.provider = provider;
    publishStatus(@[self.track, self.language], SGRAutoTranslationPhaseRunning, provider, SGRAutoTranslationFailureNone,
        self.total - self.missing.count, self.total, step);
    if (![self current]) { [self finish:YES]; return; }
    if (!self.mayContinue()) { self.interrupted = YES; [self finish:NO]; return; }
    BOOL contextual = provider == SGRAutoTranslatorAppleIntelligence || provider == SGRAutoTranslatorGemini ||
        provider == SGRAutoTranslatorClaude || provider == SGRAutoTranslatorOpenAI;
    NSMutableArray *sent = [NSMutableArray array], *indexes = [NSMutableArray array];
    [self.lines enumerateObjectsUsingBlock:^(SGKaraokeLine *line, NSUInteger i, BOOL *stop) {
        if (contextual || [self.missing containsIndex:i]) {
            [sent addObject:line];
            [indexes addObject:@(i)];
        }
    }];
    __block BOOL answered = NO;
    translateUsing(provider, sent, self.track, self.language, self.fresh, ^(NSArray *values, NSString *error) {
        if (!answered && self.step == step && [self current]) [self take:values indexes:indexes];
    }, ^(NSArray *values, NSString *error) {
        if (answered || self.step != step || self.finished) return;
        answered = YES;
        if (![self current]) { [self finish:YES]; return; }
        [self take:values indexes:indexes];
        if (self.missing.count) self.failure = failureOf(error);
        dispatch_async(dispatch_get_main_queue(), ^{ [self runNext]; });
    });
}
@end
void SGRAutoTranslateInOrder(NSArray<SGKaraokeLine *> *lines, NSString *track, NSString *language,
                             NSUInteger revision, BOOL (^mayContinue)(void), SGRAutoTranslated progress, SGRAutoTranslated done) {
    SGRAutoTranslationJob *job = [SGRAutoTranslationJob new];
    job.track = track; job.language = language; job.revision = revision; job.token = active[@[track, language]].unsignedIntegerValue;
    NSArray *pair = @[track, language];
    job.fresh = [freshRetries containsObject:pair]; [freshRetries removeObject:pair];
    job.order = SGRAutoTranslationOrder(); job.progress = progress; job.done = done; job.mayContinue = mayContinue;
    job.answer = [NSMutableArray array]; job.missing = [NSMutableIndexSet indexSet];
    NSMutableArray *copies = [NSMutableArray array];
    [lines enumerateObjectsUsingBlock:^(SGKaraokeLine *line, NSUInteger i, BOOL *stop) {
        [copies addObject:[line copy]];
        [job.answer addObject:@""];
        if (!line.translation.length && [SGKaraokeLineText(line) rangeOfCharacterFromSet:NSCharacterSet.letterCharacterSet].location != NSNotFound)
            [job.missing addIndex:i];
    }];
    job.lines = copies; job.total = job.missing.count;
    [job runNext];
}
