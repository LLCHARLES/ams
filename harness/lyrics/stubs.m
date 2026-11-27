// What SGRKaraokeView.m links against, answering the way the phone would for one track playing on a
// clock of the harness's own: the lines are whatever main.m keeps, the position runs from the launch
// line's -at at -rate, and holds at -pauseAt for -holdFor seconds before it runs on.
#import <UIKit/UIKit.h>
#import "Shared/Lyrics/Lyrics.h"
#import "Shared/Sing/Sing.h"
#import "Core/SGPrefs.h"

UIColor *SGRAccentColor(void) { return nil; }

NSString *const SGPlayerTransitionNotification = @"spotifyglass.playerTransition";
NSNotificationName const SGPlayerSpeedDidChangeNotification = @"spotifyglass.player.speedChanged";
NSString *const SGPlayerTransitionEndedNotification = @"spotifyglass.playerTransitionEnded";
CFTimeInterval SGPlayerTransitionEnds(void) { return 0; }

void SGRPlayFeedback(NSInteger feedback) {}
void SGPlayFeedback(NSInteger feedback) {}   // the name it has had since Haptics moved to Shared
// The view is the redesign's (Core/SGUIMode.h).
BOOL SGRedesignedUI(void) { return YES; }
#import "../shared/lyrics-pip-disabled.m"
// -credit names the source (Show source is -spotifyglass.lyricsCredit 1); one naming Spicy Lyrics is
// required, so it shows either way, and links to two people, as SpicyLyrics.m's community syncs do.
NSString *SGLyricsCreditFor(NSString *trackID) { return [NSUserDefaults.standardUserDefaults stringForKey:@"credit"] ?: @"the harness"; }
NSNotificationName const SGLyricsSourceChosenNotification = @"spotifyglass.lyricsSourceChosen";
NSString *SGLyricsLeadArtist(NSString *artist) { return artist; }
NSURL *SGLyricsURL(NSString *base, NSDictionary<NSString *, NSString *> *query) {
    NSURLComponents *url = [NSURLComponents componentsWithString:base];
    NSMutableArray<NSURLQueryItem *> *items = [NSMutableArray array];
    [query enumerateKeysAndObjectsUsingBlock:^(NSString *name, NSString *value, BOOL *stop) {
        [items addObject:[NSURLQueryItem queryItemWithName:name value:value]];
    }];
    url.queryItems = items;
    return url.URL;
}
// LyricsSources.h's, declared here: that header's SPTPlayerTrack clashes with the track stub below.
@interface SGLyricsLink : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSURL *url;
@end
@implementation SGLyricsLink
@end
BOOL SGLyricsCreditRequired(NSString *credit) { return [credit hasPrefix:@"Spicy Lyrics"]; }
NSArray<SGLyricsLink *> *SGLyricsCreditLinks(NSString *text) {
    if (![text containsString:@"Spicy Lyrics"]) return nil;
    NSMutableArray<SGLyricsLink *> *links = [NSMutableArray array];
    for (NSString *who in @[@"Uploader", @"Maker"]) {
        SGLyricsLink *link = [SGLyricsLink new];
        link.title = [who stringByAppendingString:@": harness"];
        link.url = [NSURL URLWithString:@"https://example.org/"];
        [links addObject:link];
    }
    return links;
}
void SGLyricsOpenCreditLinks(NSArray<SGLyricsLink *> *links, UIView *from) { NSLog(@"harness: credit opens %lu links", (unsigned long)links.count); }
// -translateTo es: the language the Lyrics page would ask translations for.
NSString *SGLyricsTranslationLanguage(void) { return [NSUserDefaults.standardUserDefaults stringForKey:@"translateTo"]; }

// -gemini 1: a Gemini key is set, and Translate with Gemini answers each line with itself, marked.
BOOL SGGeminiKeySet(void) { return [NSUserDefaults.standardUserDefaults boolForKey:@"gemini"]; }
NSString *SGLyricsGeminiLanguage(void) { return SGLyricsTranslationLanguage() ?: @"en"; }
void SGLyricsTranslateWithGemini(NSString *trackID, NSArray<SGKaraokeLine *> *lines, NSString *languageTag,
                                 void (^done)(NSArray<NSString *> *translations, NSString *error)) {
    NSMutableArray<NSString *> *translations = [NSMutableArray array];
    for (SGKaraokeLine *line in lines) [translations addObject:[@"Gemini: " stringByAppendingString:SGKaraokeLineText(line)]];
    // -geminiDelay S: as late as a whole song through the real API can be.
    double delay = [NSUserDefaults.standardUserDefaults doubleForKey:@"geminiDelay"];
    if (delay <= 0) {
        done(translations, nil);
        return;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ done(translations, nil); });
}

// -onDevice 1 / -intelligence 1: Translate on iPhone and Apple Intelligence are offered, each answering every
// line with itself, marked.
@interface SGOnDeviceTranslation : NSObject
@end
void (^SGHarnessOnDevice)(NSArray<NSString *> *, void (^)(NSArray<NSString *> *, NSString *));
@implementation SGOnDeviceTranslation
+ (BOOL)translationAvailable { return [NSUserDefaults.standardUserDefaults boolForKey:@"onDevice"]; }
+ (BOOL)appleIntelligenceAvailable:(NSString *)languageTag { return [NSUserDefaults.standardUserDefaults boolForKey:@"intelligence"]; }
+ (void)answer:(NSArray<NSString *> *)lines as:(NSString *)mark done:(void (^)(NSArray<NSString *> *, NSString *))done {
    NSMutableArray<NSString *> *out = [NSMutableArray array];
    for (NSString *line in lines) [out addObject:line.length ? [mark stringByAppendingString:line] : @""];
    dispatch_async(dispatch_get_main_queue(), ^{ done(out, nil); });
}
+ (void)translate:(NSArray<NSString *> *)lines to:(NSString *)languageTag done:(void (^)(NSArray<NSString *> *, NSString *))done {
    if (SGHarnessOnDevice) { SGHarnessOnDevice(lines, done); return; }
    [self answer:lines as:@"iPhone: " done:done];
}
+ (void)translate:(NSArray<NSString *> *)lines to:(NSString *)languageTag from:(UIView *)view done:(void (^)(NSArray<NSString *> *, NSString *))done {
    [self translate:lines to:languageTag done:done];
}
+ (void)openTranslateSettings {}
// A batch at a time, as the model works: the first half shows a second before the rest.
+ (void)translateWithAppleIntelligence:(NSArray<NSString *> *)lines to:(NSString *)languageTag song:(NSString *)song progress:(void (^)(NSArray<NSString *> *))progress
                                  done:(void (^)(NSArray<NSString *> *, NSString *))done {
    NSMutableArray<NSString *> *half = [NSMutableArray array];
    [lines enumerateObjectsUsingBlock:^(NSString *line, NSUInteger i, BOOL *stop) {
        [half addObject:i < lines.count / 2 && line.length ? [@"Intelligence: " stringByAppendingString:line] : @""];
    }];
    dispatch_async(dispatch_get_main_queue(), ^{ progress(half); });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{ [self answer:lines as:@"Intelligence: " done:done]; });
}
@end
// Shared/LyricsTranslation/TextTranslation.m, for the meaning sheet's Translate action: the menus here have no
// translator for an explanation, so the action is not offered (harness/meaning-translate covers it).
BOOL SGLyricsTranslateTextsAvailable(void) { return NO; }
void SGLyricsTranslateTexts(NSArray<NSString *> *texts, NSString *languageTag, UIView *presentingView,
                            void (^done)(NSArray<NSString *> *translations, NSString *error)) {
    done(nil, @"no translator in this harness");
}
// Saved translations and their jobs, kept in memory for the run as SavedTranslations.m keeps them: the lines made
// here by their text, for a song and language, and one token a song and language that a newer job or a delete ends.
NSNotificationName const SGLyricsTranslationsDidChangeNotification = @"spotifyglass.lyricsTranslationsDidChange";
NSNotificationName const SGLyricsTranslationSavedNotification = @"spotifyglass.lyricsTranslationSaved";
NSMutableDictionary<NSString *, NSDictionary<NSString *, NSString *> *> *SGHarnessSavedTranslations;
static NSMutableDictionary<NSString *, NSNumber *> *sg_jobTokens;
static NSUInteger sg_lastToken;
static NSString *pairKey(NSString *track, NSString *language) { return [NSString stringWithFormat:@"%@|%@", track, language]; }
void SGLyricsSyncSavedTranslation(NSString *track, NSString *language, NSArray<SGKaraokeLine *> *lines) {
    NSDictionary<NSString *, NSString *> *saved = SGHarnessSavedTranslations[pairKey(track, language)];
    for (SGKaraokeLine *line in lines) {
        NSString *translation = saved[SGKaraokeLineText(line) ?: @""];
        if (translation.length && (!line.translation.length || line.translationMade)) {
            line.translation = translation;
            line.translationMade = YES;
        } else if (!translation.length && line.translationMade) {
            line.translation = nil;
            line.translationMade = NO;
        }
    }
}
void SGLyricsLoadTranslation(NSString *track, NSString *language, NSArray<SGKaraokeLine *> *lines,
                             BOOL (^current)(void), void (^done)(void)) {
    // This menu fixture has an in-memory store. Queue ordering and stale async reads are
    // exercised against SavedTranslations.m in lyrics-translation, not this boundary double.
    if (!current()) return;
    SGLyricsSyncSavedTranslation(track, language, lines);
    done();
}
void SGLyricsSaveTranslation(NSString *track, NSString *language, NSArray<SGKaraokeLine *> *lines) {
    NSMutableDictionary<NSString *, NSString *> *saved = [NSMutableDictionary dictionary];
    for (SGKaraokeLine *line in lines) {
        NSString *text = SGKaraokeLineText(line);
        if (text.length && line.translationMade && line.translation.length) saved[text] = line.translation;
    }
    if (!SGHarnessSavedTranslations) SGHarnessSavedTranslations = [NSMutableDictionary dictionary];
    SGHarnessSavedTranslations[pairKey(track, language)] = saved;
}
NSUInteger SGLyricsBeginTranslation(NSString *track, NSString *language) {
    if (!sg_jobTokens) sg_jobTokens = [NSMutableDictionary dictionary];
    sg_jobTokens[pairKey(track, language)] = @(++sg_lastToken);
    return sg_lastToken;
}
BOOL SGLyricsTranslationIsCurrent(NSString *track, NSString *language, NSUInteger token) {
    return token && [sg_jobTokens[pairKey(track, language)] unsignedIntegerValue] == token;
}
void SGLyricsEndTranslation(NSString *track, NSString *language, NSUInteger token) {
    if (SGLyricsTranslationIsCurrent(track, language, token)) [sg_jobTokens removeObjectForKey:pairKey(track, language)];
}
void SGLyricsDeleteTranslation(NSString *track, NSString *language) {
    [SGHarnessSavedTranslations removeObjectForKey:pairKey(track, language)];
    [sg_jobTokens removeObjectForKey:pairKey(track, language)];
}
void SGLyricsDeleteTranslationWithCompletion(NSString *track, NSString *language, void (^done)(NSError *)) {
    SGLyricsDeleteTranslation(track, language);
    dispatch_async(dispatch_get_main_queue(), ^{ if (done) done(nil); });
}
// The Lyrics page's Saved translations row: every one deleted, every job ended.
void SGHarnessDeleteAllTranslations(void) {
    [SGHarnessSavedTranslations removeAllObjects];
    [sg_jobTokens removeAllObjects];
    [NSNotificationCenter.defaultCenter postNotificationName:@"harness.lyricsAIResultDidChange" object:nil];
    [NSNotificationCenter.defaultCenter postNotificationName:SGLyricsTranslationsDidChangeNotification object:nil];
}
NSUInteger SGHarnessTranslationJobs(void) { return sg_jobTokens.count; }

// Line meanings: -title and -artist name the track Genius is searched for, and the setting's key
// (-spotifyglass.lyricsMeanings 3) turns them on.
@interface SGHarnessTrack : NSObject
@property (nonatomic, copy) NSString *trackTitle, *artistName;
@end
@implementation SGHarnessTrack
@end
id SGKaraokeTrackFor(NSString *trackID) {
    SGHarnessTrack *track = [SGHarnessTrack new];
    track.trackTitle = [NSUserDefaults.standardUserDefaults stringForKey:@"title"];
    track.artistName = [NSUserDefaults.standardUserDefaults stringForKey:@"artist"];
    return track;
}
// lyrics-page links the real Settings/ framework, which has both.
#ifndef SG_HARNESS_SETTINGS
id SGChoiceRow(NSString *title, NSString *subtitle, NSString *key, NSArray *choices, NSInteger fallback) { return nil; }
UIViewController *SGTopController(void) {
    // The harness owns this window; Catalyst may put an auxiliary window first in the scene.
    UIViewController *top = UIApplication.sharedApplication.delegate.window.rootViewController;
    while (top.presentedViewController) top = top.presentedViewController;
    return top;
}
#endif

static NSArray<SGKaraokeLine *> *sg_lines;
static double sg_from = -1, sg_rate = 1, sg_pauseAt = -1, sg_holdFor = 0;
static CFTimeInterval sg_since, sg_heldAt;

void SGHarnessStartClock(double at, double rate, double pauseAt, double holdFor) {
    sg_from = at;
    sg_rate = rate;
    sg_pauseAt = pauseAt;
    sg_holdFor = holdFor;
    sg_since = CACurrentMediaTime();
    sg_heldAt = 0;
}

NSString *SGHarnessPlayingTrack;
NSString *SGKaraokePlayingTrack(void) { return SGHarnessPlayingTrack ?: @"harness"; }
NSArray<SGKaraokeLine *> *SGKaraokeLinesForTrack(NSString *trackID) { return sg_lines; }
void SGKaraokeKeepLines(NSString *trackID, NSArray<SGKaraokeLine *> *lines) { sg_lines = lines; }
BOOL SGHarnessLoadFailed;
void (^SGHarnessRetryLyrics)(NSString *);
BOOL SGLyricsLoadFailed(NSString *trackID) { return SGHarnessLoadFailed; }
BOOL SGKaraokeLooking(NSString *trackID) { return NO; }
void SGLyricsRetry(NSString *trackID) { if (SGHarnessRetryLyrics) SGHarnessRetryLyrics(trackID); }

NSNotificationName const SGKaraokeLinesKeptNotification = @"harness.kept";
@interface SGHarnessPlayback : NSObject
@property(nonatomic) BOOL isPaused;
@property(nonatomic) double positionAsOfTimestamp;
@end
@implementation SGHarnessPlayback
- (double)position { return SGKaraokePositionMs() / 1000.; }
- (BOOL)isPlaying { return !self.isPaused; }
- (double)playbackSpeed { return sg_rate; }
@end
static __weak id sg_listener;
static SGHarnessPlayback *sg_playback;
id SGKaraokePlayer(void) { return nil; }
void SGAddPlayerStateObserver(id observer) { sg_listener = observer; }
id SGPlayerState(void) {
    if (!sg_playback) sg_playback = [SGHarnessPlayback new];
    return sg_playback;
}
void SGHarnessPause(BOOL paused) {
    double at = SGKaraokePositionMs();
    SGHarnessStartClock(at, paused ? 0 : 1, -1, 0);
    SGHarnessPlayback *state = SGPlayerState();
    state.positionAsOfTimestamp = at / 1000.;
    state.isPaused = paused;
    [sg_listener performSelector:@selector(playerStateDidChange:) withObject:state];
}
void SGHarnessStall(BOOL stalled) {
    double at = SGKaraokePositionMs();
    SGHarnessStartClock(at, stalled ? 0 : 1, -1, 0);
    SGHarnessPlayback *state = SGPlayerState();
    state.positionAsOfTimestamp = at / 1000.;
    [sg_listener performSelector:@selector(playerStateDidReport:) withObject:state];
}
NSInteger SGKaraokeDelayMs(void) { return [NSUserDefaults.standardUserDefaults integerForKey:SGKeyLyricsDelay]; }

double SGHarnessHeldLead;
double SGSingHeldLead(void) { return SGHarnessHeldLead; }

NSInteger SGKaraokePositionMs(void) {
    if (sg_from < 0) return -1;
    CFTimeInterval now = CACurrentMediaTime();
    double at = sg_from + (now - sg_since) * 1000 * sg_rate;
    if (sg_pauseAt >= 0 && at >= sg_pauseAt) {
        // Held where it was asked to stop, then on from there as if never stopped.
        if (!sg_heldAt) sg_heldAt = now;
        if (sg_holdFor <= 0 || now - sg_heldAt < sg_holdFor) return (NSInteger)sg_pauseAt;
        SGHarnessStartClock(sg_pauseAt, sg_rate, -1, 0);
        return (NSInteger)sg_pauseAt;
    }
    return (NSInteger)(at - 1000 * SGHarnessHeldLead);
}

// -seekLag S: the player reports a seek S seconds after it is asked for, as Spotify's takes a few frames.
static BOOL sg_holdSeek;
static NSInteger sg_pendingSeek;
void SGHarnessHoldSeek(void) {
    sg_pendingSeek = -1;
    sg_holdSeek = YES;
}
NSInteger SGHarnessReleaseSeek(void) {
    sg_holdSeek = NO;
    if (sg_pendingSeek >= 0) SGHarnessStartClock(sg_pendingSeek, sg_rate, -1, 0);
    return sg_pendingSeek;
}
void SGKaraokeSeek(NSInteger ms) {
    if (sg_holdSeek) { sg_pendingSeek = ms; return; }
    double lag = [NSUserDefaults.standardUserDefaults doubleForKey:@"seekLag"];
    if (lag <= 0) {
        SGHarnessStartClock(ms, sg_rate, -1, 0);
        return;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(lag * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        SGHarnessStartClock(ms, sg_rate, -1, 0);
    });
}
// "“Title” by Artist" the translators are told.
NSString *SGLyricsSongName(NSString *trackID) { return @"“Sample” by Harness"; }
// Karaoke's settings tell the lyrics to show or hide the mic.
NSNotificationName const SGSingButtonDidChangeNotification = @"SGSingButtonDidChangeNotification";
BOOL SGSingButtonShown(void) {
    if (@available(iOS 18.0, *)) return SGFlag(SGKeySingButton, YES);
    return SGFlag(SGKeySingButton, NO);
}

// The other translators and the lyrics' tools (LyricsTools.m): off in the harness, so the menu offers what it
// did before, with Sync and Search LRCLIB under it.
BOOL SGDeepLKeySet(void) { return [NSUserDefaults.standardUserDefaults boolForKey:@"deepl"]; }
BOOL SGOpenAIKeySet(void) { return [NSUserDefaults.standardUserDefaults boolForKey:@"openai"]; }
void (^SGHarnessDeepL)(NSArray<SGKaraokeLine *> *, void (^)(NSArray<NSString *> *, NSString *));
void SGLyricsTranslateWithDeepL(NSString *trackID, NSArray<SGKaraokeLine *> *lines, NSString *languageTag,
                               void (^done)(NSArray<NSString *> *translations, NSString *error)) { if (SGHarnessDeepL) SGHarnessDeepL(lines, done); else done(nil, @"harness"); }
// Google answers as a check sets it to (translation-check.m), else turns the song down.
void (^SGHarnessGoogle)(NSArray<SGKaraokeLine *> *lines, void (^done)(NSArray<NSString *> *translations, NSString *error));
void SGLyricsTranslateWithGoogle(NSString *trackID, NSArray<SGKaraokeLine *> *lines, NSString *languageTag,
                                void (^done)(NSArray<NSString *> *translations, NSString *error)) {
    if (SGHarnessGoogle) SGHarnessGoogle(lines, done);
    else done(nil, @"harness");
}
void (^SGHarnessBing)(NSArray<SGKaraokeLine *> *, void (^)(NSArray<NSString *> *, NSString *));
void SGLyricsTranslateWithBing(NSString *trackID, NSArray<SGKaraokeLine *> *lines, NSString *languageTag,
                              void (^done)(NSArray<NSString *> *translations, NSString *error)) { if (SGHarnessBing) SGHarnessBing(lines, done); else done(nil, @"harness"); }
void (^SGHarnessOpenAI)(NSArray<SGKaraokeLine *> *, void (^)(NSArray<NSString *> *, NSString *));
void SGLyricsTranslateWithOpenAI(NSString *trackID, NSArray<SGKaraokeLine *> *lines, NSString *languageTag,
                                void (^done)(NSArray<NSString *> *translations, NSString *error)) { if (SGHarnessOpenAI) SGHarnessOpenAI(lines, done); else done(nil, @"harness"); }
NSNotificationName const SGLyricsOffsetsDidChangeNotification = @"spotifyglass.lyricsOffsetsDidChange";
NSNotificationName const SGLyricsPinDidChangeNotification = @"spotifyglass.lyricsPinDidChange";
NSNumber *SGLyricsPinnedID(NSString *trackID) { return nil; }
void SGRShowLyricsSync(NSString *trackID) { NSLog(@"harness: Sync for %@", trackID); }
void SGRShowLyricsSearch(NSString *trackID) { NSLog(@"harness: Search LRCLIB for %@", trackID); }
NSString *SGRLyricsSyncSummary(NSString *trackID) { return nil; }
BOOL SGHarnessAwake;
NSUInteger SGHarnessAwakeWrites;
#if __has_include("awake-row-under-check.inc")
#import "Core/SGLog.h"
#import "Redesigned/Lyrics/LyricsTools.h"
#import "Settings/SGModPage.h"
@implementation SGModRow
@end
#define SGSwitchRow(title, subtitle, key) [SGModRow new]
#define SGEnabled(key) [NSUserDefaults.standardUserDefaults boolForKey:@"plainIdle"]
#define SGRLyricsHoldAwake registryHold
#include "awake-row-under-check.inc"
#undef SGRLyricsHoldAwake
#undef SGEnabled
#undef SGSwitchRow
void SGRLyricsHoldAwake(id holder, BOOL hold) {
    SGHarnessAwakeWrites++;
    registryHold(holder, hold);
    SGHarnessAwake = UIApplication.sharedApplication.idleTimerDisabled;
}
#else
BOOL SGRLyricsKeepAwakeOn(void) { return [NSUserDefaults.standardUserDefaults boolForKey:@"plainIdle"]; }
void SGRLyricsHoldAwake(id holder, BOOL hold) { SGHarnessAwakeWrites++; SGHarnessAwake = hold; }
#endif

// The AI services, Claude and a reload are off in the harness; the song's language is the real one (LyricsLanguage.m).
BOOL SGClaudeKeySet(void) { return NO; }
void SGLyricsTranslateWithClaude(NSString *trackID, NSArray<SGKaraokeLine *> *lines, NSString *languageTag,
                                 void (^done)(NSArray<NSString *> *translations, NSString *error)) { done(nil, @"harness"); }
NSArray<NSNumber *> *SGLyricsAIAvailable(void) { return [NSUserDefaults.standardUserDefaults boolForKey:@"ai"] ? @[@0] : @[]; }
NSString *SGLyricsAIName(NSInteger service) { return @"Gemini"; }
// -ai 1 offers the AI items, and answers them at once: a sound for each line, a note for every third. Each answer
// is kept for the song as AIServices.m keeps it, so the view reads it back the way it does on the phone.
void SGLyricsSaveAI(NSString *kind, NSString *track, NSString *variant, NSDictionary<NSString *, NSString *> *byLine);
NSDictionary<NSString *, NSString *> *SGLyricsSavedAI(NSString *kind, NSString *track, NSString *variant);
void (^SGHarnessAIRequested)(NSString *kind, NSString *track);
extern NSNotificationName const SGLyricsAIResultDidChangeNotification;
static void keepAnswer(NSString *kind, NSString *track, NSString *variant, NSArray<SGKaraokeLine *> *lines, NSArray<NSString *> *answer) {
    NSMutableDictionary *byLine = [NSMutableDictionary dictionary];
    [lines enumerateObjectsUsingBlock:^(SGKaraokeLine *line, NSUInteger i, BOOL *stop) {
        NSString *text = SGKaraokeLineText(line);
        if (text.length) byLine[text] = answer[i];
    }];
    SGLyricsSaveAI(kind, track, variant, byLine);
    [NSNotificationCenter.defaultCenter postNotificationName:SGLyricsAIResultDidChangeNotification object:track];
}
void SGLyricsAIPronounce(NSInteger service, NSString *trackID, NSArray<SGKaraokeLine *> *lines,
                        void (^done)(NSArray<NSString *> *spoken, NSString *error)) {
    if (SGHarnessAIRequested) SGHarnessAIRequested(@"pronunciation", trackID);
    NSMutableArray *out = [NSMutableArray array];
    // A sound unlike the line, as a service's would be: a pronunciation that reads the same as its line is dropped.
    for (SGKaraokeLine *line in lines) [out addObject:SGLyricsRomanised(SGKaraokeLineText(line), YES) ?: ([NSUserDefaults.standardUserDefaults boolForKey:@"aiCheck"] ? @"ha ha" : @"")];
    keepAnswer(@"pronunciation", trackID, [NSString stringWithFormat:@"%ld", (long)[NSUserDefaults.standardUserDefaults integerForKey:@"spotifyglass.lyrics.pronunciationNotation"]], lines, out);
    done(out, nil);
}
void SGLyricsAINotes(NSInteger service, NSString *trackID, NSArray<SGKaraokeLine *> *lines, NSString *languageTag,
                    void (^done)(NSArray<NSString *> *notes, NSString *error)) {
    if (SGHarnessAIRequested) SGHarnessAIRequested(@"notes", trackID);
    NSMutableArray *out = [NSMutableArray array];
    [lines enumerateObjectsUsingBlock:^(SGKaraokeLine *line, NSUInteger i, BOOL *stop) {
        [out addObject:i % 3 == 1 && SGKaraokeLineText(line).length ? @"A made-up note on what this line refers to, for the harness." : @""];
    }];
    keepAnswer(@"notes", trackID, languageTag, lines, out);
    done(out, nil);
}
static NSMutableDictionary *sg_savedAI;
NSNotificationName const SGLyricsAIResultDidChangeNotification = @"harness.lyricsAIResultDidChange";
NSDictionary<NSString *, NSString *> *SGLyricsAIValues(NSString *kind, NSString *track, NSString *variant) {
    return SGLyricsSavedAI(kind, track, variant);
}

NSDictionary<NSString *, NSString *> *SGLyricsSavedAI(NSString *kind, NSString *track, NSString *variant) {
    return sg_savedAI[[NSString stringWithFormat:@"%@|%@|%@", kind, track, variant]];
}
void SGLyricsSaveAI(NSString *kind, NSString *track, NSString *variant, NSDictionary<NSString *, NSString *> *byLine) {
    if (!sg_savedAI) sg_savedAI = [NSMutableDictionary dictionary];
    sg_savedAI[[NSString stringWithFormat:@"%@|%@|%@", kind, track, variant]] = byLine;
}
NSNotificationName const SGLyricsDidReloadNotification = @"spotifyglass.lyricsDidReload";
void SGLyricsReload(NSString *trackID) { NSLog(@"harness: Reload for %@", trackID); }

// Automatic translation capability checks remain offline; real provider validators have their own suite.
NSString *SGGoogleTargetLanguage(NSString *language) { return [language isEqual:@"invalid"] ? nil : language; }
NSString *SGBingTargetLanguage(NSString *language) { return SGGoogleTargetLanguage(language); }
NSString *SGDeepLTargetLanguage(NSString *language) { return SGGoogleTargetLanguage(language); }
NSURL *SGOpenAICompletionURL(NSString *base) { return [NSURL URLWithString:base]; }
NSNotificationName const SGTitleTranslationSettingsDidChangeNotification = @"spotifyglass.titleTranslationSettingsDidChange";

NSNotificationName const SGLyricsTranslationServiceSettingsDidChangeNotification = @"spotifyglass.translationServiceSettingsDidChange";

NSNotificationName const SGLyricsWordTimingDidChangeNotification = @"spotifyglass.lyricsWordTimingDidChange";

// LyricCardPicker.m and ShareCards.m are not built: a lyric card's picker and image are checked on the phone.
#import "Redesigned/Lyrics/LyricCardPicker.h"
@implementation SGRLyricCardLine
@end
void (^SGHarnessLyricCardPresented)(NSArray<SGRLyricCardLine *> *, NSUInteger);
void SGRPresentLyricCardPicker(NSArray<SGRLyricCardLine *> *lines, NSUInteger picked, BOOL pronunciation, NSString *trackID) {
    if (SGHarnessLyricCardPresented) SGHarnessLyricCardPresented(lines, picked);
}
