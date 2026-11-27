// Where lyrics come from. Every source answers the same question — what are this track's lines, and
// how finely are they timed — and the chain asks them in order or all at once,
// keeping the best answer rather than the first: a source with only plain text does not shut out a
// later one that times every word.
//
// SGTTML.m reads the TTML that Apple Music's own lyrics are written in, which is what BiniLyrics and
// Unison serve. It carries a second voice and the (oh, aye) sung under a line, as LyricsPlus can too.
#import <UIKit/UIKit.h>
#import <math.h>
#import "Shared/Lyrics/Lyrics.h"

// The sources in priority order, as their keys. Unset uses the current default order;
// saved orders gain newly introduced sources once; disabled known sources and empty orders stay off.
#define SGKeyLyricsProviders @"spotifyglass.lyricsProviders"
#define SGKeyLyricsKnownProviders @"spotifyglass.lyrics.knownProviders"
// Offers the lyrics card on tracks Spotify itself has no lyrics for.
#define SGKeyLyricsAllTracks @"spotifyglass.lyricsAllTracks"
// The walk goes on past a line-timed answer to the first source with words timed; read by every walk.
#define SGKeyLyricsPreferWordTiming @"spotifyglass.lyricsPreferWordTiming"
// Names the source the shown lines came from, on the full screen page.
#define SGKeyLyricsCredit @"spotifyglass.lyricsCredit"
// The language a line's translation is asked for in, as an index into SGLyricsTranslationLanguages;
// unset or 0 takes whatever translation the source has.
#define SGKeyLyricsTranslationLanguage @"spotifyglass.lyricsTranslationLanguage"

// Each source may answer with any lyrics, timed lines or only timed words. Imported files are
// always accepted. Word timing first keeps asking past line timing until a source times the words.
#define SGKeyLyricsSourceTypes @"spotifyglass.lyrics.sourceTypes"
typedef NS_ENUM(NSInteger, SGLyricsTypes) { SGLyricsTypesAny = 0, SGLyricsTypesSynced, SGLyricsTypesWords };
SGLyricsTypes SGLyricsSourceTypes(NSString *key);
void SGLyricsSetSourceTypes(NSString *key, SGLyricsTypes types);
#define SGKeyLyricsTypeFirst @"spotifyglass.lyrics.typeFirst"
// 0: in order; 1 (default): word timing first; 2: all at once, first word timing wins.
#define SGKeyLyricsAskMode @"spotifyglass.lyrics.askMode"
UIViewController *SGLyricsTypesPage(void);
SGModRow *SGLyricsTypesRow(void);

@class SGLyricsResult, SGLyricsQuery;
// Main queue: background consumers that need timed lines now, not a hidden lyric view.
BOOL SGLyricsBackgroundNeeded(void);
void SGLyricsCancelPrefetch(NSString *trackID);
void SGLyricsResumeDeferred(void);
// Calls back on the main queue, nil when the source has nothing for the track.
typedef void (^SGLyricsAsk)(SGLyricsQuery *query, void (^done)(SGLyricsResult *result));
// One invocation, never a provider-wide or track-wide counter. Subrequests OR their outcomes.
@interface SGLyricsRequestContext : NSObject
@property (atomic, readonly) BOOL failed;
@property (atomic, readonly) BOOL cancelled;
@property (atomic) BOOL definiteMiss, credentialRejected;
@property (nonatomic) BOOL bulk;
@property (atomic) NSTimeInterval rateLimitUntil;
// Set only for a successful, genuinely empty name search, before matching or fetching lyrics.
// The continuation must search by name only, never repeat an ID or ISRC lookup.
@property (atomic, copy) SGLyricsAsk emptyNameSearch;
- (void)noteFailure:(BOOL)failed;
- (void)noteResponse:(NSURLResponse *)response error:(NSError *)error;
- (void)trackTask:(NSURLSessionTask *)task;
- (void)cancelRequests;
- (void)onCancel:(dispatch_block_t)action;
- (void)finishRequests;
@end

// A manual LRCLIB choice, kept by track id across launches. At most 500 pins.
#define SGKeyLyricsPins @"spotifyglass.lyrics.pins"
// Main queue, object the track id, after the pinned lines are kept or the pin is removed.
extern NSNotificationName const SGLyricsPinDidChangeNotification;
// Each record has id (NSNumber), title, artist, album (NSString, maybe empty), seconds (NSNumber),
// synced and instrumental (NSNumber BOOL), and record (the raw LRCLIB dictionary). At most 20,
// synced first then closest length when seconds > 0. Main queue; an empty array on failure, never nil.
void SGLrcLibSearch(NSString *title, NSString *artist, NSInteger seconds, void (^done)(NSArray<NSDictionary *> *records));
NSNumber *SGLyricsPinnedID(NSString *trackID);
// Safe from any thread. Keep the stamp with the request until delivery; compare by value.
typedef NSArray<NSString *> SGLyricsPinStamp;
SGLyricsPinStamp *SGLyricsPinGeneration(NSString *trackID);
// Main queue: a menu source pick or Automatic also invalidates in-flight hook deliveries.
void SGLyricsInvalidateDelivery(NSString *trackID);
// Prepare off main, then keep on main only while this selection and the track's pin generation
// remain current. A newer pick supersedes this one. done(NO) also covers an unusable/cancelled pick.
// current and done run on main; current may be nil for a choice without a presenting controller.
void SGLyricsPickRecord(NSString *trackID, NSDictionary *record, BOOL (^current)(void), void (^done)(BOOL pinned));
// Drops the pin, the walk's answer and missing mark, and KaraokeSource's lines, requests and losses;
// announces it and asks for the track again. Main queue.
void SGLyricsUnpin(NSString *trackID);
// LrcLib.m: the same conversion for a search choice and a pin read back by its id.
SGLyricsResult *SGLrcLibRecordResult(NSDictionary *record);
void SGLrcLibGetID(NSNumber *recordID, void (^done)(SGLyricsResult *result));
void SGLrcLibGetIDIn(SGLyricsRequestContext *context, NSNumber *recordID, void (^done)(SGLyricsResult *result));

// A page a credit names someone on: "Uploader: name" and the address it opens.
@interface SGLyricsLink : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSURL *url;
@end

// What a source answers with, and what the chain merges several of into one.
@interface SGLyricsResult : NSObject
// What the credit names: the source's name, unless it gave a fuller credit of its own.
@property (nonatomic, copy) NSString *provider;
// Who made the lines, linked from the credit; and whether the source's terms ask for the credit to
// show wherever its lines do, Show source or not.
@property (nonatomic, copy) NSArray<SGLyricsLink *> *creditLinks;
@property (nonatomic) BOOL creditRequired;
// The source of the text Spotify's own page shows, when it is not the one the lines came from.
@property (nonatomic, copy) NSString *pageProvider;
@property (nonatomic) BOOL synced;                // the lines have starts of their own
@property (nonatomic) BOOL wordTimed;             // the words inside them are timed, not estimated
// Every line as Spotify's lyrics page takes it: ♪ over a break and an empty last line where the
// singing ends. Starts are in milliseconds, all 0 when not synced. nil when a source times words
// but has no text for Spotify's own page.
@property (nonatomic, copy) NSArray<NSNumber *> *starts;
@property (nonatomic, copy) NSArray<NSString *> *texts;
@property (nonatomic, copy) NSArray<SGKaraokeLine *> *karaokeLines;
// What the source learned about the track on the way, for the sources asked after it: one that
// matched the track by Spotify's id knows the title and artist the ones searching by name need.
@property (nonatomic, copy) NSString *title, *artist, *album;
@property (nonatomic) NSInteger seconds;
@property (nonatomic) BOOL instrumental;
// The source picked for the track from the player's ⋯ answered with this (SGLyricsKeepChosen), so it stands
// over Spotify's own lines however either is timed. The walk's own answer never is, a pick standing or not.
@property (nonatomic) BOOL picked;
@property (nonatomic) BOOL provisional;
@end

SGLyricsResult *SGLyricsSnapshot(SGLyricsResult *result);

// What is known about the track when a source is asked. Only trackID is always there; the rest is
// filled in by the player, and by whichever source answered before.
@interface SGLyricsQuery : NSObject
@property (nonatomic, copy) NSString *trackID;   // Spotify's base62 id
@property (nonatomic, copy) NSString *title, *artist, *album;
@property (nonatomic) NSInteger seconds;
// Set only on the private query copy made by SGLyricsInvoke, never on the walk's shared query.
@property (nonatomic, strong) SGLyricsRequestContext *requestContext;
@end

// The lines as Spotify's own page takes them, ♪ over a break and an empty line at the end.
void SGLyricsPageLines(NSArray<SGKaraokeLine *> *lines, NSArray<NSNumber *> **starts, NSArray<NSString *> **texts);

@interface SGLyricsProvider : NSObject
@property (nonatomic, copy) NSString *key;      // stored in the order, never shown
@property (nonatomic, copy) NSString *name;     // "BiniLyrics", what the credit reads
@property (nonatomic, copy) NSString *detail;   // one line under the name on the Lyrics page
// Searches by title and artist, so it has nothing to ask with until someone has named the track.
// Musixmatch and AMLL match by Spotify's id and can go without, though AMLL falls back to a name search.
@property (nonatomic) BOOL needsName;
// Has only untimed lines, which never replace lines already found, so it is asked only while there are none
// and Spotify has none of its own.
@property (nonatomic) BOOL untimed;
@property (nonatomic, copy) SGLyricsAsk ask;
@end

SGLyricsRequestContext *SGLyricsInvoke(SGLyricsProvider *provider, SGLyricsQuery *query,
                    BOOL (^current)(void),
                    void (^done)(SGLyricsResult *result, BOOL failed));

typedef NS_ENUM(NSInteger, SGBulkReply) {
    SGBulkFound, SGBulkMiss, SGBulkTemporary, SGBulkRateLimited, SGBulkCredentialRejected, SGBulkFiltered
};
SGLyricsRequestContext *SGLyricsAskDownloaded(NSString *key, SGLyricsQuery *query,
    void (^done)(SGBulkReply, SGLyricsResult *, NSTimeInterval retryAt));
BOOL SGLyricsPlaybackRequestsActive(void);

// Shared backoff for empty-source retries and provisional-answer recovery.
static const NSTimeInterval SGLyricsHedgeDelaySeconds = 2;
static const NSTimeInterval SGLyricsRequestTimeoutSeconds = 5;
static const NSTimeInterval SGLyricsWalkBudgetSeconds = 8;
static const NSTimeInterval SGLyricsCredentialPauseSeconds = 600;
static const NSTimeInterval SGLyricsRetryPause = 10, SGLyricsRetryPauseMost = 60;
static const NSUInteger SGLyricsRecoveryTries = 4;
// Retirement and the store's final publication decision share only an in-memory flag.
@interface SGLyricsLease : NSObject
- (BOOL)isCurrent;
- (void)invalidate;
@end
void SGLyricsStoreSaveWithLease(NSString *track, NSArray<SGKaraokeLine *> *lines, NSString *credit, SGLyricsLease *lease);
// A keeper retains this authority with its sheet, even after the selection cache is evicted.
// NSNull means a walk is outstanding but has not published a sheet yet.
id SGLyricsPersistenceAuthority(NSString *track);
BOOL SGLyricsMayPersist(NSString *track, id authority);
BOOL SGLyricsSameSheet(SGLyricsResult *a, SGLyricsResult *b);
BOOL SGLyricsUseSpotify(NSArray<SGKaraokeLine *> *source, NSArray<SGKaraokeLine *> *spotify, BOOL protected);
BOOL SGKaraokeKeepSourceLines(NSString *track, NSArray<SGKaraokeLine *> *lines, SGLyricsResult *answer);
void SGKaraokeKeepSpotifyLines(NSString *track, NSArray<SGKaraokeLine *> *lines);
SGLyricsResult *SGLyricsAcceptSpotify(NSString *track, NSArray<SGKaraokeLine *> *lines, id previousAuthority);
NSArray<SGKaraokeLine *> *SGKaraokeSpotifyLines(NSString *track);
void SGKaraokeDeferPersistence(NSString *track);
BOOL SGLyricsRecovering(NSString *track);
void SGLyricsRetire(NSString *track);
void SGLyricsForgetAnswer(NSString *track);
// Import edits retire the old walk and complete its consumers with nil. Disk is untouched.
void SGLyricsForgetAnswerForImportChange(NSString *track);
// Main queue, only authoritative player reports, not state getters or seeks.
void SGLyricsPlaybackChanged(NSString *track);
void SGKaraokeCancelStoreWrite(NSString *track);

// Every source there is, in the order a fresh install asks them.
NSArray<SGLyricsProvider *> *SGLyricsAllProviders(void);
SGLyricsProvider *SGLyricsProviderFor(NSString *key);
// The keys in the user's order, the ones switched off left out. An empty list means the mod leaves
// Spotify's own lyrics alone.
NSArray<NSString *> *SGLyricsOrder(void);
void SGLyricsSetOrder(NSArray<NSString *> *keys);
BOOL SGLyricsEnabled(void);   // any source at all is on

// Asks the sources in order and merges what they give, on the main queue. nil when none had lyrics.
void SGLyricsFetch(NSString *trackID, void (^done)(SGLyricsResult *result));
// Main queue. A failed lookup is not a catalog miss; good kept lines always take precedence.
BOOL SGLyricsLoadFailed(NSString *trackID);
void SGLyricsNoteLoadFailure(NSString *trackID, BOOL failed);
void SGLyricsNoteSpotifyLoadFailure(NSString *trackID, BOOL failed);
void SGLyricsRetry(NSString *trackID);
// NO once every source has said it has nothing for the track; safe from any thread.
BOOL SGLyricsMayHave(NSString *trackID);
// Starts the walk for a track before anyone has asked, so the answer is in when Spotify's request
// comes; a walk already run or running is left alone. Safe from any thread.
void SGLyricsPrefetch(NSString *trackID);
// What Spotify's own metadata says of a track: 1 has lyrics, 0 has none, -1 not seen yet. The
// player-track hook notes it, and the walk when it names a track; the request hook reads it to send a
// track Spotify has none for to the donor, and the walk to pass Genius over. Safe from any thread.
NSInteger SGLyricsSpotifyHas(NSString *trackID);
void SGLyricsNoteSpotifyHas(NSString *trackID, BOOL has);
// The remote-config values the lyrics feature forces while a source is on, nil for any other flag:
// the player gives its cards this long to load before it shows the list without the slow ones, and
// a source of the mod's can take longer than Spotify's default to answer.
id SGLyricsForcedFlag(NSString *key);
// Set on the requests the mod sends to spclient itself, so the request hook leaves them alone.
extern NSString *const SGLyricsOwnRequestKey;
// The name of the source the lines shown for the track came from, nil until they arrive.
NSString *SGLyricsCreditFor(NSString *trackID);
void SGLyricsSetCredit(NSString *trackID, NSString *name);
// What the walk learned of a credit, by its text: whether it must show, and the links it carries.
// SGLyricsCreditLinks takes the credit or any text holding it, as Spotify's "Lyrics provided by ..."
// does. Main queue.
BOOL SGLyricsCreditRequired(NSString *credit);
NSArray<SGLyricsLink *> *SGLyricsCreditLinks(NSString *text);
// Register provider or restored offline credit metadata without selecting or keeping lyrics. Main queue.
void SGLyricsNoteCredit(SGLyricsResult *result);
// Opens one link at once; two or more as an action sheet held to `from`.
void SGLyricsOpenCreditLinks(NSArray<SGLyricsLink *> *links, UIView *from);
// Turns an install's old Musixmatch switches into an order. Called once, before anything reads one.
void SGLyricsMigrateLegacyKeys(void);

// The requests the sources share; each calls back on the main queue, with nil when it failed.
NSURL *SGLyricsURL(NSString *base, NSDictionary<NSString *, NSString *> *query);
void SGLyricsGetJSON(NSURL *url, NSDictionary<NSString *, NSString *> *headers, void (^done)(id root));
// The same with the reply's status and headers, and the body read whatever the status: an error's
// body says why. response is nil when the request never got an answer.
void SGLyricsGetJSONReply(NSURL *url, NSDictionary<NSString *, NSString *> *headers, void (^done)(id root, NSHTTPURLResponse *response));
void SGLyricsGetText(NSURL *url, void (^done)(NSString *text));
// For the one source that is asked a question rather than sent to an address. body is anything
// NSJSONSerialization writes; nothing is sent at all when it is not.
void SGLyricsPostJSON(NSURL *url, NSDictionary<NSString *, NSString *> *headers, id body, void (^done)(id root));
// Pure transforms run with JSON decoding on the transport worker, before delivery on main.
// Capture immutable inputs only; query/cache state remains owned by the main queue.
void SGLyricsGetJSONTransform(NSURL *url, NSDictionary<NSString *, NSString *> *headers,
                              id (^transform)(id root), void (^done)(id result));
void SGLyricsPostJSONTransform(NSURL *url, NSDictionary<NSString *, NSString *> *headers, id body,
                               id (^transform)(id root), void (^done)(id result));
// One worker/main boundary for pure provider work, including preparation of a manual choice.
// Transport workers may execute immediately; callers on main always enqueue the work.
static inline void SGLyricsTransform(id (^work)(void), void (^done)(id)) {
    dispatch_block_t run = ^{
        id result = work();
        dispatch_async(dispatch_get_main_queue(), ^{ done(result); });
    };
    if (NSThread.isMainThread) dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), run);
    else run();
}
void SGLyricsGetTextTransform(NSURL *url, id (^transform)(NSString *), void (^done)(id));
void SGLyricsGetJSONIn(SGLyricsRequestContext *context, NSURL *url, NSDictionary *headers, void (^done)(id));
void SGLyricsGetJSONTransformIn(SGLyricsRequestContext *context, NSURL *url, NSDictionary *headers, id (^transform)(id), void (^done)(id));
void SGLyricsGetJSONReplyIn(SGLyricsRequestContext *context, NSURL *url, NSDictionary *headers, void (^done)(id, NSHTTPURLResponse *));
void SGLyricsGetTextIn(SGLyricsRequestContext *context, NSURL *url, void (^done)(NSString *));
void SGLyricsGetTextTransformIn(SGLyricsRequestContext *context, NSURL *url, id (^transform)(NSString *), void (^done)(id));
void SGLyricsPostJSONTransformIn(SGLyricsRequestContext *context, NSURL *url, NSDictionary *headers, id body, id (^transform)(id), void (^done)(id));
void SGLyricsSourceRequestIn(SGLyricsRequestContext *context, NSURL *url, NSDictionary *headers, NSData *body, void (^done)(NSData *, NSInteger));
// QQ's crypt=0 lyric field: base64 UTF-8 or zlib-compressed QRC, then ordinary LRC.
SGLyricsResult *SGQQMusicResult(id payload);
// Aggregate diagnostic count only; transports also record the outcome on their invocation context.
void SGLyricsNoteReply(NSURLResponse *response, NSError *error);
// A network error or non-success HTTP status, except a catalog's explicit 404 miss.
BOOL SGLyricsReplyFailed(NSURLResponse *response, NSError *error);

// SGTTML.m. Apple Music's TTML as timed lines, the voices already turned into alignments and each
// line's translation and pronunciation added where the head has them; nil when the document holds no
// line the page could show.
NSArray<SGKaraokeLine *> *SGTTMLLines(NSString *xml);
// Provider timing metadata is kept verbatim; page lines retain the parser's order.
SGLyricsResult *SGTTMLResult(NSString *xml, BOOL wordTimed);
// SGLyricsBareText and SGLyricsShownTranslation are declared in Lyrics.h, beside the lines they read.
// A line's pronunciation: timed `words` where the source has them, else `plain` estimated across the
// line's own time; nil when it has neither or reads the same as `of`.
SGKaraokeLine *SGLyricsPronunciation(NSArray<SGKaraokeWord *> *words, NSString *plain, SGKaraokeLine *of);

// The languages a translation can be asked for in, as language tags ("en", "es"), the first one ""
// for whatever the source has; SGKeyLyricsTranslationLanguage indexes it, so it only ever grows at
// the end. Their names, in English, for the Lyrics page.
NSArray<NSString *> *SGLyricsTranslationLanguages(void);
NSArray<NSString *> *SGLyricsTranslationLanguageNames(void);
// The tag of the language asked for, nil for whatever the source has.
NSString *SGLyricsTranslationLanguage(void);


// The sources themselves, each in its own file.
extern SGLyricsAsk SGBiniLyricsAsk;
extern SGLyricsAsk SGAMLLAsk;
extern SGLyricsAsk SGMusixmatchAsk;
// Musixmatch's community translations of a track into `language`, by SGMusixmatchLineKey of each original
// line, or nil when there are none. Main queue, and at once when the answer is in. Asked once per
// track and language a launch, again only after an answer cut short.
void SGMusixmatchTranslations(NSString *trackID, NSString *language, void (^done)(NSDictionary<NSString *, NSString *> *byLine));
NSString *SGMusixmatchLineKey(NSString *text);
// Copies of the lines with the translations matched in, in a new array; nil when none matched.
NSArray<SGKaraokeLine *> *SGMusixmatchTranslatedLines(NSArray<SGKaraokeLine *> *lines, NSDictionary<NSString *, NSString *> *byLine);
// A richsync body, the JSON array its richsync_body holds, as word timed lines; nil when it has none.
SGLyricsResult *SGMusixmatchRichsyncResult(id body);
extern SGLyricsAsk SGUnisonAsk;
extern SGLyricsAsk SGNetEaseAsk;
extern SGLyricsAsk SGLrcLibAsk;
extern SGLyricsAsk SGSpicyLyricsAsk;
extern SGLyricsAsk SGQQMusicAsk;
extern SGLyricsAsk SGLuoyueAsk;
extern SGLyricsAsk SGKuGouAsk;
extern SGLyricsAsk SGBugsAsk;
extern SGLyricsAsk SGGenieAsk;
extern SGLyricsAsk SGPetitLyricsAsk;
extern SGLyricsAsk SGLyricsPlusAsk;
extern SGLyricsAsk SGDeezerAsk;

// The newer endpoints return untrusted text as well as JSON. Requests stop at 2 MiB, never follow
// redirects with credentials, and answer once on main. A nil body is GET; any data body is POST.
void SGLyricsSourceRequest(NSURL *url, NSDictionary<NSString *, NSString *> *headers, NSData *body,
                           void (^done)(NSData *data, NSInteger status));

// Small checks shared by these parsers. A time must be finite and within a day; accepting a numeric
// prefix of an error message would silently put the wrong words at the start of a song.
static inline id SGLyricsField(id object, NSString *key) {
    return [object isKindOfClass:NSDictionary.class] ? object[key] : nil;
}
static inline NSString *SGLyricsString(id value, NSUInteger limit) {
    return [value isKindOfClass:NSString.class] && [value length] <= limit ? value : nil;
}
static inline BOOL SGLyricsNumber(id value, double *number) {
    if ([value isKindOfClass:NSNumber.class] && CFGetTypeID((__bridge CFTypeRef)value) != CFBooleanGetTypeID()) {
        *number = [value doubleValue];
    } else if ([value isKindOfClass:NSString.class] && [value length] && [value length] <= 32) {
        NSScanner *scanner = [NSScanner scannerWithString:value];
        scanner.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        scanner.charactersToBeSkipped = nil;
        if (![scanner scanDouble:number] || !scanner.isAtEnd) return NO;
    } else return NO;
    return isfinite(*number) && *number >= 0 && *number <= SGKaraokeMaxTimeMs;
}
static inline NSInteger SGLyricsSecondsToMs(id value) {
    double seconds;
    return SGLyricsNumber(value, &seconds) && seconds <= SGKaraokeMaxTimeMs / 1000.0 ? llround(seconds * 1000) : -1;
}
static inline NSString *SGLyricsDecimalID(id value) {
    NSString *text = [value isKindOfClass:NSNumber.class] && CFGetTypeID((__bridge CFTypeRef)value) != CFBooleanGetTypeID()
        ? [value stringValue] : SGLyricsString(value, 20);
    return text.length && text.length <= 20 &&
        [text rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"0123456789"].invertedSet].location == NSNotFound ? text : nil;
}
static inline SGLyricsResult *SGLyricsResultWithLines(NSArray<SGKaraokeLine *> *lines, NSString *provider) {
    if (!lines.count) return nil;
    SGLyricsResult *result = [SGLyricsResult new];
    result.provider = provider;
    result.karaokeLines = SGKaraokeInTimeOrder(lines);
    result.synced = SGKaraokeLinesTiming(lines) != SGKaraokeTimingNone;
    result.wordTimed = SGKaraokeLinesTiming(lines) == SGKaraokeTimingWords;
    NSArray *starts, *texts;
    SGLyricsPageLines(result.karaokeLines, &starts, &texts);
    result.starts = starts;
    result.texts = texts;
    return result;
}
static inline SGLyricsResult *SGLyricsPlainTextResult(id text, NSString *provider) {
    NSString *plain = SGLyricsString(text, 262144);
    if (!plain.length) return nil;
    NSArray *rows = [plain componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet];
    if (rows.count > 4000) return nil;
    NSMutableArray *texts = [NSMutableArray array], *starts = [NSMutableArray array];
    for (NSString *row in rows) {
        NSString *line = [row stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if (line.length > 4096) return nil;
        if (line.length) { [texts addObject:line]; [starts addObject:@0]; }
    }
    SGLyricsResult *result = SGLyricsResultWithLines(SGKaraokeStaticLines(texts), provider);
    result.starts = starts;
    result.texts = texts;
    return result;
}

// The one LRC timestamp, read by LrcLib.m's records and LocalFiles/LocalLyrics.m's imported files:
// [mm:ss] with a fraction of tenths, hundredths or thousandths, minutes of one to three digits and a
// ":" before the fraction as some editors write it. A line carries a stamp per time it is sung.
static inline NSRegularExpression *SGLyricsLRCStamp(void) {
    static NSRegularExpression *stamp;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        stamp = [NSRegularExpression regularExpressionWithPattern:@"\\[(\\d{1,3}):(\\d{1,2})(?:[.:](\\d{1,3}))?\\]" options:0 error:nil];
    });
    return stamp;
}
// The milliseconds a stamp of `row` names: its minutes and seconds in ms, plus its fraction as
// thousandths, a one or two digit fraction counting tenths or hundredths.
static inline NSInteger SGLyricsLRCStampMs(NSString *row, NSTextCheckingResult *match) {
    NSInteger minutes = [[row substringWithRange:[match rangeAtIndex:1]] integerValue];
    NSInteger seconds = [[row substringWithRange:[match rangeAtIndex:2]] integerValue];
    NSInteger fraction = 0;
    NSRange part = [match rangeAtIndex:3];
    if (part.location != NSNotFound) {
        NSString *digits = [row substringWithRange:part];
        fraction = digits.integerValue * (digits.length == 1 ? 100 : digits.length == 2 ? 10 : 1);
    }
    return (minutes * 60 + seconds) * 1000 + fraction;
}

// Every color-lyrics request carries this before the track it asks for.
#define SGLyricsColorLyricsPath @"/color-lyrics/v2/track/"
// The track a color-lyrics URL asks for, out of its path alone: the segment after the first
// SGLyricsColorLyricsPath, nil when the path has none or that segment is empty.
static inline NSString *SGLyricsTrackInURL(NSURL *url) {
    NSString *path = url.path;
    NSRange marker = [path rangeOfString:SGLyricsColorLyricsPath];
    if (marker.location == NSNotFound) return nil;
    NSString *track = [[path substringFromIndex:NSMaxRange(marker)] componentsSeparatedByString:@"/"].firstObject;
    return track.length ? track : nil;
}

SGLyricsResult *SGBugsResult(id root, BOOL timed);
SGLyricsResult *SGGenieResult(NSString *jsonp);
SGLyricsResult *SGLyricsPlusResult(id root);
SGLyricsResult *SGDeezerResult(id root);
@class SGModRow;
SGModRow *SGDeezerARLRow(void);
BOOL SGDeezerARLSet(void);
// Removes the ARL from the Keychain and the login it signed in with (Mod > Clear Keychain); the order stays.
// NO when the Keychain refused the delete, so the ARL is still stored.
BOOL SGDeezerForgetKey(void);
extern SGLyricsAsk SGGeniusAsk;
// Genius.m. The rows of the lyrics in Genius's embed script, "" between stanzas and the [Chorus]
// headings left out; nil when the script is not the shape it reads or holds no line.
NSArray<NSString *> *SGGeniusEmbedRows(NSString *js);

// LrcLib.m. Timed LRC as a synced result, nil when no line in it is timed.
SGLyricsResult *SGLyricsLRCResult(NSString *lrc);
// Lyricsfile.m. LRCLIB's Lyricsfile YAML as word timed lines; nil when it times no word, or is not
// a Lyricsfile 1.0 this reads.
NSArray<SGKaraokeLine *> *SGLyricsfileLines(NSString *yaml);
// Untimed rows as a result: every start 0, a ♪ for each empty row.
SGLyricsResult *SGLyricsPlainResult(NSArray<NSString *> *rows);
// NetEase.m. Word timed lines from NetEase's yrc, or with krc from KuGou's KRC text; nil for none.
NSArray<SGKaraokeLine *> *SGLyricsPieceLines(NSString *body, BOOL krc);
// QQMusic.m, for it and KuGou. A title as the two are matched by: lowercased, without spaces,
// punctuation or symbols, ideographic and full width ones included. The artist without whoever is
// featured ("A feat. B" is A). Whether a credited name and the track's artist name the same one: the
// key of either holds the other's, the featured artists left out.
NSString *SGLyricsMatchKey(NSString *text);
NSString *SGLyricsLeadArtist(NSString *artist);
BOOL SGLyricsSameArtist(NSString *credited, NSString *artist);
// What the two catalogs are asked as: a browser.
#define SGLyricsBrowserAgent @"Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"
// KuGou.m. A download's base64 content as lines, nil when it is not KRC or holds no timed line.
NSArray<SGKaraokeLine *> *SGKuGouLines(NSString *content);

// SongMatch.m, for the searches that answer with whole songs (Genius, LRCLIB). Text as the two are
// matched by: letters and digits only, lowercase, accents gone and apostrophes closed up, so "Don’t"
// and "dont" read alike across sources. A title with a version in brackets or after " - " set aside
// ("Song (feat. X) - Remastered 2011" is "Song"), and the version words of the track's title, its
// guests left out ("Old Town Road (feat. Billy Ray Cyrus) - Remix" is {remix}). How closely a song
// a catalog names by title and artists is the track: 0 when it is not (another title, or none of its
// artists is the track's lead), 1 for another version of it, 2 for the plain song, 3 for the same version.
NSString *SGLyricsFoldedText(NSString *text);
NSString *SGLyricsBareTitle(NSString *title);
NSString *SGLyricsBareTitleWithOptions(NSString *title, BOOL soundtrackOnly);
NSSet<NSString *> *SGLyricsTitleVersion(NSString *title);
NSInteger SGLyricsSongRank(NSString *title, NSString *artist, NSString *songTitle, NSArray<NSString *> *songArtists);
// Genius's search, which the lyrics source (Genius.m) and the line meanings (LyricsMeanings/Meanings.m)
// both ask: its address, what it is asked for a track, and the song in its reply that is the track, as
// SGLyricsSongRank tells: of several, the same version wins, then the plain song. nil when none is, or
// the track is an instrumental or karaoke version, since Genius files the words under the song.
#define SGGeniusSearchURL @"https://genius.com/api/search/song"
NSDictionary<NSString *, NSString *> *SGGeniusSearchQuery(NSString *title, NSString *artist);
NSNumber *SGGeniusSongIn(NSDictionary *response, NSString *title, NSString *artist);

// SpicyLyrics.m. Its key in the order; whether the user's own API key is in the Keychain; what keeps
// it from answering, for its row on the sources page ("Needs a key", why the key was refused), nil
// while nothing does; the Lyrics page's row that sets or removes the key; and an API response as
// lines, nil when it has none.
extern NSString *const SGSpicyLyricsKey;
BOOL SGSpicyLyricsKeySet(void);
// Removes the key from the Keychain and forgets a refusal (Mod > Clear Keychain); the order stays.
// NO when the Keychain refused the delete, so the key is still stored.
BOOL SGSpicyLyricsForgetKey(void);
NSString *SGSpicyLyricsStatus(void);
@class SGModRow;
SGModRow *SGSpicyLyricsKeyRow(void);
SGLyricsResult *SGSpicyLyricsResult(id root);

UIViewController *SGLyricsSourcesPage(void);   // the ordered list on the Lyrics page

// LyricsPick.m. The source picked for a track from the redesigned player's ⋯, which may be lower in the order
// than the one that answered (issue #67). The pick is a track's id against a source's key, kept until Spotify
// quits; a track's walk asks its picked source first, the rest of the order after it. Main queue.
NSString *SGLyricsChosenSource(NSString *trackID);
// Every source in the order is asked for the track at once, with no answer awaited, and the answers are
// kept for the last few tracks; SGLyricsOffersDidChangeNotification is posted as each one answers.
void SGLyricsAskOffers(NSString *trackID);
// What they have answered, asking nothing: the sources with lines so far, and in `asking` the keys still out.
NSDictionary<NSString *, SGLyricsResult *> *SGLyricsOffersSoFar(NSString *trackID, NSArray<NSString *> **asking);
// Posted on the main queue (object the track's id) each time one of those sources answers.
extern NSNotificationName const SGLyricsOffersDidChangeNotification;
// Makes the offer of `key` the track's lyrics now, everywhere they show, and posts
// SGLyricsSourceChosenNotification (object the track's id) once its lines are kept.
void SGLyricsChooseSource(NSString *trackID, NSString *key);
// Drops the track's pick and puts back what the order had chosen, shown before the first pick, the same way.
void SGLyricsChooseAutomatic(NSString *trackID);
// A walk under way at the track's first pick has ended with `lyrics`: that is what Automatic puts back.
void SGLyricsNoteOrderChoice(NSString *trackID, SGLyricsResult *lyrics);
// The next switch to Automatic must resolve again, without changing the current pick.
void SGLyricsForgetAutomaticFallback(NSString *trackID);
// A walk found the track's pick `key` answering no lines, or switched off: the pick goes, so the menu shows
// Automatic over the order's answer the walk goes on to. Nothing when the track's pick is another by now.
void SGLyricsDropChoice(NSString *trackID, NSString *key);
extern NSNotificationName const SGLyricsSourceChosenNotification;
// LyricsSources.m, for LyricsPick.m: the query a walk would start with, and a picked answer kept as the walk's.
SGLyricsQuery *SGLyricsQueryFor(NSString *trackID);
// How many source requests have failed since launch; any thread.
NSUInteger SGLyricsFailures(void);
void SGLyricsKeepChosen(NSString *trackID, SGLyricsResult *result);
// The walk's kept answer: a result (possibly provisional), NSNull for none, nil when not kept.
id SGLyricsKeptAnswer(NSString *trackID);
// Automatic: retires the picked sheet and disk entry, preserving waiters for the configured order.
void SGLyricsRestoreKept(NSString *trackID, id kept);
#import "SGBoundedRequest.h"

static inline BOOL SGLyricsIsSpotifyTrackID(NSString *trackID) {
    if (![trackID isKindOfClass:NSString.class] || trackID.length != 22) return NO;
    NSCharacterSet *base62 = [NSCharacterSet characterSetWithCharactersInString:
        @"0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"];
    return [trackID rangeOfCharacterFromSet:base62.invertedSet].location == NSNotFound;
}
