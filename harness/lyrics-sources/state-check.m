// The actual keeper and walk, with Spotify's hooks left out and replies held until the check lets
// them through. This exercises a choice changed while the old request is still out, without a phone.
#import <UIKit/UIKit.h>
#import "Shared/LyricsSources/LyricsSources.h"
#import "Settings/SGSourcesPage.h"
#import <objc/runtime.h>
#import <Security/Security.h>
#import "Shared/Player/PlayerState.h"
#import "Core/SGOptionalWork.h"
#import "Shared/AnimatedArtwork/AnimatedArtwork.h"
#import "../harness-fail.h"
#define CHECK(cond) do { if (!(cond)) { fprintf(stderr, "FAILED line %d: %s\n", __LINE__, #cond); exit(1); } } while (0)

static void (^sg_pinnedReply)(SGLyricsResult *);
static SGLyricsRequestContext *sg_pinnedContext;
static NSNumber *sg_askedPin;
static BOOL sg_observePickPreparation;
static SGLyricsResult *observedRecordResult(NSDictionary *record) {
    if (sg_observePickPreparation) CHECK(!NSThread.isMainThread);
    return SGLrcLibRecordResult(record);
}
void HarnessGetID(NSNumber *identifier, void (^done)(SGLyricsResult *)) { sg_askedPin = identifier; sg_pinnedReply = done; }
void HarnessGetIDIn(SGLyricsRequestContext *context, NSNumber *identifier, void (^done)(SGLyricsResult *)) { sg_pinnedContext = context; HarnessGetID(identifier, done); }
#define SGLrcLibGetID HarnessGetID
#define SGLrcLibGetIDIn HarnessGetIDIn
#define SGLrcLibRecordResult observedRecordResult
#define kKeptTracks kWalkKeptTracks
static NSMutableArray<dispatch_block_t> *sg_recoveryClocks;
static NSMutableArray<dispatch_block_t> *sg_deadlineEvents;
static NSMutableDictionary<NSValue *, NSMutableDictionary *> *sg_virtualTimers;
static NSTimeInterval sg_virtualSeconds;
static NSValue *timerKey(dispatch_source_t source) { return [NSValue valueWithPointer:(__bridge const void *)source]; }
static dispatch_time_t timerTime(dispatch_time_t when, int64_t delta) {
    return sg_virtualTimers ? (dispatch_time_t)((sg_virtualSeconds + (double)delta / NSEC_PER_SEC) * NSEC_PER_SEC)
        : dispatch_time(when, delta);
}
static void timerSchedule(dispatch_source_t source, dispatch_time_t start, uint64_t interval, uint64_t leeway) {
    if (sg_virtualTimers) {
        sg_virtualTimers[timerKey(source)] = [@{@"at": @((double)start / NSEC_PER_SEC)} mutableCopy];
        dispatch_source_set_timer(source, DISPATCH_TIME_FOREVER, DISPATCH_TIME_FOREVER, 0);
    } else dispatch_source_set_timer(source, start, interval, leeway);
}
static void timerCancel(dispatch_source_t source) {
    [sg_virtualTimers removeObjectForKey:timerKey(source)];
    dispatch_source_cancel(source);
}
static void deadlineHandler(dispatch_source_t source, dispatch_block_t block) {
    if (sg_deadlineEvents && block) [sg_deadlineEvents addObject:[block copy]];
    if (sg_virtualTimers) {
        if (block) sg_virtualTimers[timerKey(source)][@"block"] = [block copy];
        else [sg_virtualTimers removeObjectForKey:timerKey(source)];
    }
    dispatch_source_set_event_handler(source, block);
}
static void advanceTimers(NSTimeInterval seconds) {
    while (YES) {
        NSValue *next = nil;
        for (NSValue *key in sg_virtualTimers)
            if ([sg_virtualTimers[key][@"at"] doubleValue] <= seconds &&
                (!next || [sg_virtualTimers[key][@"at"] doubleValue] < [sg_virtualTimers[next][@"at"] doubleValue]))
                next = key;
        if (!next) break;
        sg_virtualSeconds = [sg_virtualTimers[next][@"at"] doubleValue];
        dispatch_block_t block = sg_virtualTimers[next][@"block"];
        [sg_virtualTimers removeObjectForKey:next];
        block();
    }
    sg_virtualSeconds = seconds;
}
static void recoveryAfter(dispatch_time_t when, dispatch_queue_t queue, dispatch_block_t block) {
    if (sg_recoveryClocks) [sg_recoveryClocks addObject:[block copy]];
    else dispatch_after(when, queue, block);
}
#define dispatch_after recoveryAfter
#define dispatch_time timerTime
#define dispatch_source_set_timer timerSchedule
#define dispatch_source_cancel timerCancel
#define dispatch_source_set_event_handler deadlineHandler
#import "Shared/LyricsSources/LyricsSources.m"
#undef dispatch_source_set_event_handler
#undef dispatch_source_cancel
#undef dispatch_source_set_timer
#undef dispatch_time
#undef dispatch_after
#undef kKeptTracks
#undef SGLrcLibGetID
#undef SGLrcLibGetIDIn
#undef SGLrcLibRecordResult
// Existing keeper tests supply prepared fixtures directly; the asynchronous selection contract is
// exercised separately below with the real long Lyricsfile parser.
static BOOL SGLyricsPin(NSString *track, NSDictionary *record) {
    NSDictionary *raw = [record[@"record"] isKindOfClass:NSDictionary.class] ? record[@"record"] : record;
    return pinResult(track, raw, SGLrcLibRecordResult(raw));
}
// Hold only the keeper/watcher clocks during the background-skip check. Other checks use real time.
static NSMutableArray<dispatch_block_t> *sg_heldClocks;
static void holdableAfter(dispatch_time_t when, dispatch_queue_t queue, dispatch_block_t block) {
    if (sg_heldClocks) [sg_heldClocks addObject:[block copy]];
    else dispatch_after(when, queue, block);
}
#define dispatch_after holdableAfter
static BOOL sg_aheadAllowed = YES;
static BOOL sg_expensivePath, sg_backgroundConsumer;
static BOOL optionalForWatcher(BOOL expensive) {
    return sg_aheadAllowed && (!sg_expensivePath || expensive) && SGEnabled(SGKeyLoadAhead);
}
BOOL SGLiveActivityLyricsActive(void) { return sg_backgroundConsumer; }
BOOL SGLyricsPiPActive(void) { return NO; }
BOOL SGLyricsPiPStarting(void) { return NO; }
SGLockArtwork SGLockScreenArtwork(void) { return SGLockArtworkOff; }
static NSMutableArray<NSString *> *sg_prefetched;
static void observedPrefetch(NSString *track) {
    [sg_prefetched addObject:track];
    SGLyricsPrefetch(track);
}
#define SGOptionalWorkMayRun optionalForWatcher
#define SGLyricsPrefetch observedPrefetch
static _Thread_local NSUInteger *headerSubmissions;
static void observedKaraokeDispatch(dispatch_queue_t queue, dispatch_block_t block) {
    if (headerSubmissions && queue == dispatch_get_main_queue()) ++*headerSubmissions;
    dispatch_async(queue, block);
}
#define dispatch_async observedKaraokeDispatch
#define SGBoundedRequestTask(request, timeout, ...) [NSURLSession.sharedSession dataTaskWithRequest:request completionHandler:__VA_ARGS__]
#import "karaoke.inc"
#undef SGBoundedRequestTask
#undef dispatch_async
#undef SGLyricsPrefetch
#undef SGOptionalWorkMayRun
static NSString *sg_missingLyrics;
#import "activity-lines.inc"
// The production watcher, with only its drawing/rest effects replaced. The full player simulator
// harness needs unrelated AI/view services; this check drives the state machine without those.
static BOOL sg_open, sg_alone, sg_wide, sg_queuePage;
static NSTimer *sg_rest;
static NSUInteger sg_closed;
static void setOpen(BOOL open, BOOL animated) { sg_open = open; if (!open) sg_closed++; }
static void setAlone(BOOL alone, BOOL animated) { sg_alone = alone; }
static BOOL singing(void) { return NO; }
static void restartRestAfter(NSTimeInterval wait) {}
static void refreshSide(BOOL animated) {}
// The preview tap waiting for lyrics (PlayerLyrics.x) belongs to the player's view, which this check has none of.
static id sg_pendingPreview;
static void forgetPreview(void) { sg_pendingPreview = nil; }
static void answerPreview(void) {}
BOOL SGRPlayerLyricsAvailable(void) { return SGKaraokeLinesForTrack(SGKaraokePlayingTrack()) != nil; }
void SGRPlayerLyricsChanged(void) {}
void SGRPlayerLandscapeLinesChanged(void) {}
#import "player-lyrics-watcher.inc"
#undef dispatch_after
// Exercise the production hook decisions and completion paths, without installing Logos hooks.
#define completed hookCompleted
#import "lyrics-hook.inc"
#undef completed

// Exercise the real Spicy provider through the real walk, with only transport and Keychain mocked.
static void (^sg_spicyReply)(id, NSHTTPURLResponse *);
static NSString *sg_spicyAuthorization;
static void heldSpicyJSON(SGLyricsRequestContext *context, NSURL *url, NSDictionary *headers, void (^done)(id, NSHTTPURLResponse *)) {
    sg_spicyAuthorization = headers[@"Authorization"];
    sg_spicyReply = ^(id root, NSHTTPURLResponse *response) { [context noteResponse:response error:nil]; done(root, response); };
}
static OSStatus ignoreSpicyDelete(CFDictionaryRef query) { return errSecSuccess; }
static OSStatus emptySpicyKey(CFDictionaryRef query, CFTypeRef *data) { return errSecItemNotFound; }
#define SGLyricsGetJSONReplyIn heldSpicyJSON
#define SecItemDelete ignoreSpicyDelete
#define SecItemCopyMatching emptySpicyKey
#define kKeptTracks kSpicyKeptTracks
static NSMutableArray *spicyLogs;
#pragma push_macro("SGLog")
#undef SGLog
#define SGLog(...) [spicyLogs addObject:[NSString stringWithFormat:__VA_ARGS__]]
#import "Shared/LyricsSources/SpicyLyrics.m"
#pragma pop_macro("SGLog")
#undef kKeptTracks
#define keyQuery deezerKeyQuery
#import "Shared/LyricsSources/Deezer.m"
#undef keyQuery
#undef SecItemCopyMatching
#undef SecItemDelete
#undef SGLyricsGetJSONReplyIn

// The rest of the app has no work in this check. The one enabled provider holds its answer.
static void (^sg_providerReply)(SGLyricsResult *);
static NSString *sg_providerTrack;
static SGLyricsRequestContext *sg_providerContext;
SGLyricsAsk SGMusixmatchAsk = ^(SGLyricsQuery *q, void (^done)(SGLyricsResult *)) { sg_providerReply = done; sg_providerTrack = q.trackID; sg_providerContext = q.requestContext; };
SGLyricsAsk SGBiniLyricsAsk, SGUnisonAsk, SGNetEaseAsk, SGQQMusicAsk, SGKuGouAsk;
SGLyricsAsk SGBugsAsk, SGGenieAsk, SGLyricsPlusAsk, SGImportedLRCAsk, SGGeniusAsk;
SGLyricsAsk SGPetitLyricsAsk;
NSString *const SGImportedLRCKey = @"importedlrc";
@implementation SGSource
+ (instancetype)sourceWithKey:(NSString *)key name:(NSString *)name detail:(NSString *)detail { return [self new]; }
@end
NSString *SGL(NSString *key, NSString *english) { return english; }
// Song matching is covered by lyrics-sources/genius-lyrics; this fixture's artist is always Singer.
NSString *SGLyricsLeadArtist(NSString *artist) { return artist; }
static BOOL sg_testTranslations;
static void (^sg_translationReply)(NSDictionary *);
static NSArray *sg_translatedLines;
static NSString *sg_translationRequestedLanguage;
static NSDictionary *sg_cachedTranslationReply;
void SGMusixmatchTranslations(NSString *track, NSString *language, void (^done)(NSDictionary *)) {
    if (sg_testTranslations) {
        sg_translationRequestedLanguage = language;
        sg_translationReply = done;
        if (sg_cachedTranslationReply) done(sg_cachedTranslationReply);
    }
    else done(nil);
}
NSArray *SGMusixmatchTranslatedLines(NSArray *lines, NSDictionary *byLine) { return sg_translatedLines; }
SGModRow *SGStatActionRow(NSString *title, NSString *subtitle, NSString *(^value)(void), void (^action)(void)) { return nil; }
UIViewController *SGTopController(void) { return nil; }
UIViewController *SGSourcesPageMake(NSString *title, NSString *note, NSArray *all, NSArray *(^order)(void), void (^setOrder)(NSArray *)) { return nil; }
void SGRegisterFlagForcer(BOOL beatsOverride, SGFlagForcer launch, SGFlagForcer locked) {}
BOOL SGRedesignedUI(void) { return sg_testTranslations; }
NSString *SGURIString(id uri) {
    return [uri isKindOfClass:NSURL.class] ? [uri absoluteString] :
        ([uri isKindOfClass:NSString.class] ? uri : nil);
}
#import "player-up-next.inc"
static SPTPlayerState *sg_fixtureState;
SPTPlayerState *SGPlayerState(void) { return sg_fixtureState; }
NSNotificationName const SGLocalFileEditsDidChangeNotification = @"harness.localFileEdits";
static BOOL sg_testLocalFile;
BOOL SGLocalFileIs(NSString *track) { return sg_testLocalFile; }
NSString *SGLocalFileLyricsKey(NSString *track) { return [track hasPrefix:@"spotify:local:"] ? track : nil; }
NSDictionary *SGLocalFileInfo(NSString *track) { return @{@"title": @"Song", @"artist": @"Singer", @"seconds": @200}; }
static NSMutableDictionary<NSString *, void (^)(SGLyricsResult *)> *sg_importedReplies;
static NSString *sg_linkedSong;
static NSString *sg_testReportedPath;
NSString *SGImportedLRCLinkedTo(NSString *track) { return [track isEqual:sg_linkedSong] ? @"listener.lrc" : nil; }
void SGPlaybackLyricsFetch(NSString *track, NSString *path, void (^done)(SGLyricsResult *)) {
    sg_testReportedPath = path;
    if (sg_importedReplies) sg_importedReplies[track] = done;
    else dispatch_async(dispatch_get_main_queue(), ^{ done(nil); });
}
double SGSingHeldLead(void) { return 0; }
double SGSingLeadOf(SPTPlayerState *state) { return 0; }

@interface HarnessPlayer : NSObject
@property (nonatomic) double sought;
@property (nonatomic, strong) id state;
@end
@implementation HarnessPlayer
- (void)seekTo:(double)seconds { self.sought = seconds; }
@end

@interface HarnessLyricsTrack : NSObject
@property (nonatomic, copy) NSString *URI, *trackTitle, *artistName;
@property (nonatomic, copy) NSDictionary *metadata;
@end
@implementation HarnessLyricsTrack
@end
// SGPlayerUpNextIn validates Spotify's concrete class, rather than any URI-bearing object.
@implementation SPTPlayerTrack
@dynamic URI, artistURI, artistName, trackTitle, metadata, provider;
@end
@interface StateUpcomingTrack : SPTPlayerTrack
@property (nonatomic, copy) id URI;
@property (nonatomic, copy) NSString *trackTitle, *artistName;
@property (nonatomic, copy) NSDictionary *metadata;
@end
@implementation StateUpcomingTrack
@synthesize URI, trackTitle, artistName, metadata;
@end
@interface HarnessLyricsState : NSObject
@property (nonatomic, strong) HarnessLyricsTrack *track;
@property (nonatomic) BOOL isPaused;
@property (nonatomic) double position, positionAsOfTimestamp;
@property (nonatomic, copy) NSArray *future;
@end
@implementation HarnessLyricsState
@end
#include "spotify-check.inc"
@interface HarnessApplication : NSObject
@property (nonatomic) UIApplicationState applicationState;
@end
@implementation HarnessApplication
@end
static HarnessApplication *sg_testApplication;
static id fakeApplication(id self, SEL selector) { return sg_testApplication; }

@interface HarnessLyricsTask : NSObject
@property (nonatomic, copy) dispatch_block_t reply;
@end
@implementation HarnessLyricsTask
- (void)resume { self.reply(); }
@end
static NSUInteger sg_spotifyAsks;
static NSString *fixtureTrackID(void) {
    return [[NSUUID.UUID.UUIDString stringByReplacingOccurrencesOfString:@"-" withString:@""] substringToIndex:22];
}
static NSInteger sg_spotifyStatus = 404;
static NSData *sg_spotifyBody;
static NSString *sg_holdSpotifyTrack;
static dispatch_block_t sg_heldSpotifyReply;
static id spotifyMiss(id self, SEL selector, NSURLRequest *request, void (^done)(NSData *, NSURLResponse *, NSError *)) {
    CHECK([request.URL.host isEqual:@"spclient.wg.spotify.com"]);
    sg_spotifyAsks++;
    HarnessLyricsTask *task = [HarnessLyricsTask new];
    task.reply = ^{
        dispatch_block_t reply = ^{
            done(sg_spotifyBody, [[NSHTTPURLResponse alloc] initWithURL:request.URL statusCode:sg_spotifyStatus HTTPVersion:@"HTTP/2" headerFields:nil], nil);
        };
        if ([request.URL.lastPathComponent isEqual:sg_holdSpotifyTrack]) sg_heldSpotifyReply = reply;
        else reply();
    };
    return task;
}

// AVAudioSession itself stays untouched except for its route getter while the check runs.
@interface HarnessPort : NSObject
@property (nonatomic, copy) NSString *UID, *portName, *portType;
@end
@implementation HarnessPort
@end
@interface HarnessRoute : NSObject
@property (nonatomic, copy) NSArray *outputs;
@end
@implementation HarnessRoute
@end
static HarnessRoute *sg_fakeRoute;
static id fakeRoute(id self, SEL selector) { return sg_fakeRoute; }
static void pumpUntilAt(BOOL (^ready)(void), int caller) {
    NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:60];
    while (!ready() && [limit timeIntervalSinceNow] > 0) [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.005]];
    if (!ready()) { fprintf(stderr, "FAILED wait at line %d\n", caller); exit(1); }
}
#define pumpUntil(ready) pumpUntilAt(ready, __LINE__)

@interface HarnessTask : NSObject
@property (nonatomic, strong) NSURLRequest *originalRequest, *currentRequest;
@property (nonatomic) NSURLSessionTaskState state;
@end
@implementation HarnessTask
@end

@interface HarnessDelegate : NSObject
@property (nonatomic) NSUInteger deliveries;
@end
@implementation HarnessDelegate
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveData:(NSData *)data {
    self.deliveries++;
}
@end

static void checkHookPins(void) {
    NSString *track = @"hook-song";
    SGLyricsResult *timed = SGLrcLibRecordResult(@{@"syncedLyrics": @"[00:01]Spotify timed line"});
    NSData *body = pageBody(timed, nil);
    CHECK(SGKaraokeLinesTiming(SGKaraokeLinesFromBody(body)) != SGKaraokeTimingNone);
    NSDictionary *plain = @{@"id": @800, @"plainLyrics": @"My plain choice"};
    NSDictionary *instrumental = @{@"id": @801, @"instrumental": @YES};
    for (NSDictionary *record in @[plain, instrumental]) {
        CHECK(SGLyricsPin(track, record));
        SGLyricsResult *chosen = sg_kept[track];
        NSData *page = decide(track, chosen, body, NO, nil);
        CHECK(page.length && ![page isEqual:body]);
        NSArray *kept = SGKaraokeLinesForTrack(track);
        CHECK(kept && [SGLyricsCreditFor(track) isEqual:@"LRCLIB"]);
        CHECK(!requested(track)); // No Spotify timing request for a pin.
        if (chosen.instrumental) CHECK(!kept.count && !SGKaraokeLinesFromBody(page).count);
        else {
            CHECK([SGKaraokeLineText(kept.firstObject) isEqual:@"My plain choice"]);
            CHECK([SGKaraokeLineText(SGKaraokeLinesFromBody(page).firstObject) isEqual:@"My plain choice"]);
        }
    }

    // The donor's answer was accepted while this choice was current, then the user unpinned it.
    CHECK(SGLyricsPin(track, plain));
    SGLyricsTaskState *state = [SGLyricsTaskState new];
    state.kind = SGLyricsTaskDonor; state.track = track;
    state.chain = sg_kept[track]; state.pinGeneration = SGLyricsPinGeneration(track);
    HarnessDelegate *delegate = [HarnessDelegate new];
    __block NSError *ended;
    SGLyricsUnpin(track);
    CHECK(!currentChoice(state));
    finishDonor(delegate, nil, nil, state, body, nil, ^(NSError *error) { ended = error; });
    CHECK(ended.code == NSURLErrorCancelled && !delegate.deliveries && !SGKaraokeLinesForTrack(track));
    // Even the same record pinned again is a different choice; the old donor cannot write it back.
    CHECK(SGLyricsPin(track, instrumental));
    ended = nil;
    finishDonor(delegate, nil, nil, state, body, nil, ^(NSError *error) { ended = error; });
    CHECK(ended.code == NSURLErrorCancelled && !delegate.deliveries && !SGKaraokeLinesForTrack(track).count);

    // Capture at request creation, not response arrival, including when donor mode is disabled.
    NSURL *url = [NSURL URLWithString:@"https://spclient.wg.spotify.com/color-lyrics/v2/track/hook-song"];
    HarnessTask *task = [HarnessTask new];
    task.originalRequest = lyricsRequestFor([NSURLRequest requestWithURL:url]);
    task.currentRequest = task.originalRequest;
    SGLyricsPinStamp *generation = SGLyricsPinGeneration(track);
    CHECK([[NSURLProtocol propertyForKey:kPinGenerationKey inRequest:task.originalRequest] isEqual:generation]);
    CHECK(!SGLyricsPin(track, @{@"id": @1}) && [SGLyricsPinGeneration(track) isEqual:generation]);
    CHECK(SGLyricsPin(track, plain));
    CHECK([[NSURLProtocol propertyForKey:kPinGenerationKey inRequest:lyricsRequestFor(task.originalRequest)] isEqual:generation]);
    NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:url statusCode:200 HTTPVersion:@"HTTP/2" headerFields:nil];
    state = classify((id)task, response);
    CHECK([state.pinGeneration isEqual:generation] && !currentChoice(state));
    ended = nil;
    finishSpotify(delegate, nil, (id)task, state, body, nil, ^(NSError *error) { ended = error; });
    CHECK(ended.code == NSURLErrorCancelled && !delegate.deliveries);
    __block BOOL cancelled = NO, forwarded = NO;
    state.kind = SGLyricsTaskDonor;
    answerHeld(delegate, nil, (id)task, state, timed, response,
               ^(NSURLSessionResponseDisposition choice) { cancelled = choice == NSURLSessionResponseCancel; },
               ^(NSURLResponse *given, SGDisposition handler) { forwarded = YES; });
    CHECK(cancelled && !forwarded && !delegate.deliveries);

    // Donor rewriting carries the generation of the real track, even before any response exists.
    SGLyricsNoteSpotifyHas(track, NO);
    sg_everyTrack = YES;
    NSURLRequest *donor = lyricsRequestFor([NSURLRequest requestWithURL:url]);
    sg_everyTrack = NO;
    CHECK([donorFor(donor) isEqual:track] && [SGLyricsTrackInURL(donor.URL) isEqual:kDonorTrack]);
    // The one color-lyrics track reader (LyricsSources.h): the segment after the first marker, from the path
    // alone and whatever the host, nil when the path has no marker or that segment is empty.
    CHECK([SGLyricsTrackInURL([NSURL URLWithString:@"https://spclient.wg.spotify.com/color-lyrics/v2/track/abc?format=json"]) isEqual:@"abc"]);
    CHECK([SGLyricsTrackInURL([NSURL URLWithString:@"https://spclient.wg.spotify.com/color-lyrics/v2/track/abc/more"]) isEqual:@"abc"]);
    CHECK(SGLyricsTrackInURL([NSURL URLWithString:@"https://spclient.wg.spotify.com/color-lyrics/v2/track/"]) == nil);
    CHECK([SGLyricsTrackInURL([NSURL URLWithString:@"https://spclient.wg.spotify.com/color-lyrics/v2/track/abc/color-lyrics/v2/track/def"]) isEqual:@"abc"]);
    CHECK([SGLyricsTrackInURL([NSURL URLWithString:@"https://example.com/color-lyrics/v2/track/xyz"]) isEqual:@"xyz"]);
    CHECK(SGLyricsTrackInURL([NSURL URLWithString:@"https://spclient.wg.spotify.com/scrollsita/abc"]) == nil);
    task.originalRequest = task.currentRequest = donor;
    CHECK(SGLyricsPin(track, instrumental));
    SGLyricsTaskState *donorState = classify((id)task, response);
    CHECK(donorState.kind == SGLyricsTaskDonor && !currentChoice(donorState));

    // Also change the pin while finishSpotify is waiting for its source callback.
    state.pinGeneration = SGLyricsPinGeneration(track);
    ended = nil;
    finishSpotify(delegate, nil, (id)task, state, body, nil, ^(NSError *error) { ended = error; });
    CHECK(SGLyricsPin(track, instrumental));
    pumpUntil(^BOOL { return ended != nil; });
    CHECK(ended.code == NSURLErrorCancelled && !delegate.deliveries && !SGKaraokeLinesForTrack(track).count);
    CHECK([SGLyricsCreditFor(track) isEqual:@"LRCLIB"]);
    printf("hook pins: plain/instrumental beat late Spotify timing; stale donor, held and Spotify replies dropped after pin/unpin passed\n");
}

static NSUserDefaults *sg_testDefaults;
static NSString *sg_testSuite;
static NSString *sg_testStore;
static NSUInteger sg_defaultsReads;
static id fakeDefaults(id self, SEL selector) { sg_defaultsReads++; return sg_testDefaults; }
static void removeTestDefaults(void) {
    [sg_testDefaults removePersistentDomainForName:sg_testSuite];
    if (sg_testStore) [NSFileManager.defaultManager removeItemAtPath:sg_testStore error:nil];
}

static void checkLanguageStore(void) {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    BOOL translation = YES, pronunciation = YES;
    CHECK(!SGLyricsLanguageRule(@"ja", &translation, &pronunciation) && translation && pronunciation);
    SGLyricsSetLanguageRule(@"ja-JP", YES, NO);
    CHECK(SGLyricsLanguageRule(@"ja", &translation, &pronunciation) && translation && !pronunciation);
    CHECK(SGLyricsLanguageRule(@"ja", NULL, NULL));
    SGLyricsSetLanguageRule(@"ja", NO, YES);
    CHECK(SGLyricsLanguageRule(@"ja", &translation, &pronunciation) && !translation && pronunciation);
    CHECK([defaults dictionaryForKey:SGKeyLyricsLanguageRules].count == 1);
    SGLyricsSetLanguageRule(@"invalid tag", YES, YES);
    CHECK([defaults dictionaryForKey:SGKeyLyricsLanguageRules].count == 1);
    [defaults setObject:@{@"ko": @"invalid"} forKey:SGKeyLyricsLanguageRules];
    CHECK(!SGLyricsLanguageRule(@"ko", NULL, NULL));
    [defaults removeObjectForKey:SGKeyLyricsLanguageRules];
    CHECK(!SGLyricsLanguageRule(@"ja", NULL, NULL));
    __block NSUInteger notes = 0;
    id observer = [NSNotificationCenter.defaultCenter addObserverForName:SGLyricsLanguageDidChangeNotification object:@"language-song" queue:nil usingBlock:^(NSNotification *note) {
        CHECK(NSThread.isMainThread); notes++;
    }];
    NSArray *japanese = SGKaraokeStaticLines(@[@"明日の空を見上げて歩く"]);
    SGLyricsSetTrackLanguage(@"language-song", @"EN_us");
    CHECK([SGLyricsSongLanguage(@"language-song", japanese) isEqual:@"en-us"] && notes == 1);
    SGLyricsSetTrackLanguage(@"language-song", nil);
    CHECK(!SGLyricsTrackLanguage(@"language-song") && notes == 2);
    CHECK([SGLyricsSongLanguage(@"language-song", japanese) isEqual:@"ja"]);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{ SGLyricsSetTrackLanguage(@"language-song", @"ko"); });
    pumpUntil(^BOOL { return notes == 3; });
    CHECK([SGLyricsTrackLanguage(@"language-song") isEqual:@"ko"]);
    for (NSUInteger i = 0; i < 501; i++) SGLyricsSetTrackLanguage(@(i).stringValue, @"es");
    CHECK([defaults dictionaryForKey:SGKeyLyricsTrackLanguages].count == 500 && [SGLyricsTrackLanguage(@"500") isEqual:@"es"]);
    [NSNotificationCenter.defaultCenter removeObserver:observer];
    printf("language store: rules, nullable outputs, malformed entries, overrides, removal, main notification and 500 tracks passed\n");
}

static SGLyricsResult *madeUpLyrics(NSString *name, SGKaraokeTiming timing) {
    NSArray *lines = timing == SGKaraokeTimingNone ? SGKaraokeStaticLines(@[name]) : SGKaraokeEstimatedLines(@[@1000], @[name]);
    for (SGKaraokeLine *line in lines) line.timing = timing;
    return SGLyricsResultWithLines(lines, name);
}

static void checkSpicyCancellation(void) {
    SGLyricsQuery *absent = SGLyricsQuery.new; absent.trackID = @"00000000000000000000AA";
    spicyLogs=NSMutableArray.array;
    absent.requestContext = SGLyricsRequestContext.new;
    SGSpicyLyricsAskWith(@"sl_pk_fixture",absent,^(SGLyricsResult *result){ CHECK(!result); });
    sg_spicyReply(nil,[[NSHTTPURLResponse alloc] initWithURL:[NSURL URLWithString:@"https://fixture.invalid"] statusCode:404 HTTPVersion:nil headerFields:nil]);
    sg_spicyReply=nil; absent.requestContext=SGLyricsRequestContext.new;
    SGSpicyLyricsAskWith(@"sl_pk_fixture",absent,^(SGLyricsResult *result){ CHECK(!result); });
    CHECK(!sg_spicyReply && absent.requestContext.definiteMiss);
    CHECK(spicyLogs.count && ![[spicyLogs componentsJoinedByString:@" "]containsString:absent.trackID]);spicyLogs=nil;
    SGLyricsProvider *spicy = SGLyricsProviderFor(SGSpicyLyricsKey), *other = SGLyricsProviderFor(@"musixmatch");
    SGLyricsAsk savedSpicy = spicy.ask, savedOther = other.ask;
    __block NSString *key;
    spicy.ask = ^(SGLyricsQuery *query, void (^done)(SGLyricsResult *)) { SGSpicyLyricsAskWith(key, query, done); };
    other.ask = ^(SGLyricsQuery *query, void (^done)(SGLyricsResult *)) { done(nil); };
    for (NSInteger mode = 0; mode <= 2; mode++) {
        SGSpicyLyricsForgetKey();
        SGSetInt(SGKeyLyricsAskMode, mode);
        SGLyricsSetOrder(@[SGSpicyLyricsKey, @"musixmatch"]);
        NSString *track = [NSString stringWithFormat:@"0123456789abcdefghijk%ld", (long)mode];
        key = @"sl_pk_old_harness";
        __block NSUInteger completed = 0;
        SGLyricsFetch(track, ^(SGLyricsResult *result) { CHECK(!result); completed++; });
        pumpUntil(^BOOL { return sg_spicyReply != nil; });
        SGSpicyLyricsForgetKey();
        key = @"sl_pk_new_harness";
        NSHTTPURLResponse *refused = [[NSHTTPURLResponse alloc] initWithURL:[NSURL URLWithString:@"https://api.spicylyrics.org/"]
            statusCode:401 HTTPVersion:@"HTTP/1.1" headerFields:nil];
        void (^old)(id, NSHTTPURLResponse *) = sg_spicyReply; sg_spicyReply = nil;
        old(@{@"error": @"key_revoked"}, refused);
        pumpUntil(^BOOL { return completed != 0; });
        CHECK(completed == 1 && SGLyricsMayHave(track));
        // A stale completion must leave the walk retryable, not a cached authoritative miss.
        __block BOOL retried = NO;
        __block SGLyricsResult *answer;
        SGLyricsFetch(track, ^(SGLyricsResult *result) { answer = result; retried = YES; });
        pumpUntil(^BOOL { return sg_spicyReply != nil || retried; });
        CHECK(sg_spicyReply && [sg_spicyAuthorization isEqual:@"Bearer sl_pk_new_harness"]);
        NSHTTPURLResponse *ok = [[NSHTTPURLResponse alloc] initWithURL:refused.URL statusCode:200 HTTPVersion:@"HTTP/1.1" headerFields:nil];
        void (^fresh)(id, NSHTTPURLResponse *) = sg_spicyReply; sg_spicyReply = nil;
        fresh(@{@"Body": @{@"Type": @"Line", @"Content": @[@{@"Text": @"New key", @"StartTime": @1, @"EndTime": @2}]}}, ok);
        pumpUntil(^BOOL { return retried; });
        CHECK([SGKaraokeLineText(answer.karaokeLines.firstObject) isEqual:@"New key"]);
    }
    spicy.ask = savedSpicy; other.ask = savedOther;
    SGLyricsSetOrder(@[@"musixmatch"]);
    SGSetInt(SGKeyLyricsAskMode, 0);
    puts("Spicy cancellation: all three walk modes retry the new credential after stale completion");
}

static void checkCompletedBounds(void) {
    id oldPlayer = sg_player;
    NSString *oldSeen = sg_lastSeenID;
    HarnessPlayer *player = [HarnessPlayer new]; sg_player = player;
    HarnessLyricsState *state = [HarnessLyricsState new]; player.state = state;
    HarnessLyricsTrack *playing = [HarnessLyricsTrack new]; state.track = playing;
    NSString *current = fixtureTrackID(), *active = fixtureTrackID();
    playing.URI = [@"spotify:track:" stringByAppendingString:current];
    sg_lastSeenID = current;
    SGLyricsProvider *provider = SGLyricsProviderFor(@"musixmatch");
    SGLyricsAsk saved = provider.ask;
    provider.ask = ^(SGLyricsQuery *q, void (^done)(SGLyricsResult *)) { done(nil); };
    void (^miss)(NSString *) = ^(NSString *track) {
        __block BOOL ended = NO;
        SGLyricsFetch(track, ^(SGLyricsResult *result) { CHECK(!result); ended = YES; });
        pumpUntil(^BOOL { return ended; });
    };
    miss(current); miss(active);
    for (NSUInteger i = 0; i < 45; i++) miss([NSString stringWithFormat:@"warm-miss-%lu", (unsigned long)i]);
    __block void (^held)(SGLyricsResult *);
    provider.ask = ^(SGLyricsQuery *q, void (^done)(SGLyricsResult *)) {
        if ([q.trackID isEqual:active]) held = done;
        else done(nil);
    };
    __block BOOL activeEnded = NO;
    // Cache pressure, not elapsed time, owns this scenario; slow CI must not expire the held invocation.
    NSMutableDictionary *previousTimers = sg_virtualTimers;
    NSTimeInterval previousSeconds = sg_virtualSeconds;
    sg_virtualTimers = [NSMutableDictionary dictionary];
    sg_virtualSeconds = 0;
    SGLyricsFetch(active, ^(SGLyricsResult *result) { activeEnded = YES; });
    pumpUntil(^BOOL { return held != nil; });
    NSMutableArray<NSString *> *tracks = [NSMutableArray array];
    for (NSUInteger i = 0; i < 250; i++) {
        NSString *track = [NSString stringWithFormat:@"source-miss-%lu", (unsigned long)i];
        [tracks addObject:track]; miss(track);
    }
    CHECK(sg_missing.count <= 201 && !activeEnded);
    CHECK(!SGLyricsMayHave(current) && !SGLyricsMayHave(active));
    NSString *evicted;
    for (NSString *track in tracks) if (SGLyricsMayHave(track)) { evicted = track; break; }
    CHECK(evicted);
    provider.ask = ^(SGLyricsQuery *q, void (^done)(SGLyricsResult *)) { done(madeUpLyrics(@"Asked again", SGKaraokeTimingLine)); };
    __block SGLyricsResult *answer;
    SGLyricsFetch(evicted, ^(SGLyricsResult *result) { answer = result; });
    pumpUntil(^BOOL { return answer != nil; });
    CHECK([answer.provider isEqual:@"Asked again"]);
    held(nil); CHECK(activeEnded);
    sg_virtualTimers = previousTimers;
    sg_virtualSeconds = previousSeconds;
    provider.ask = saved;

    BOOL oldOwn = sg_ownSources; sg_ownSources = NO;
    NSDictionary *oldHeaders = sg_spclientHeaders; sg_spclientHeaders = @{};
    NSUInteger oldAsks = sg_spotifyAsks;
    Method method = class_getInstanceMethod(NSURLSession.class, @selector(dataTaskWithRequest:completionHandler:));
    IMP oldTask = method_setImplementation(method, (IMP)spotifyMiss);
    for (NSString *invalid in @[@"", @"123456789012345678901", @"123456789012345678901?", @"123456789012345678901é"]) {
        CHECK(!requestFromSpotify(invalid) && !sg_requests[invalid] && sg_spotifyAsks == oldAsks);
    }
    SGKaraokeRequestLyrics(current);
    pumpUntil(^BOOL { return !SGKaraokeLooking(current); });
    sg_holdSpotifyTrack = active;
    SGKaraokeRequestLyrics(active);
    CHECK(sg_heldSpotifyReply && SGKaraokeLooking(active));
    [tracks removeAllObjects];
    for (NSUInteger i = 0; i < 250; i++) {
        NSString *track = fixtureTrackID();
        [tracks addObject:track]; SGKaraokeRequestLyrics(track);
        pumpUntil(^BOOL { return !SGKaraokeLooking(track); });
    }
    CHECK(sg_requestMarks.count <= 201);
    CHECK(requested(current) && requested(active) && SGKaraokeLooking(active));
    evicted = nil;
    for (NSString *track in tracks) if (!requested(track)) { evicted = track; break; }
    CHECK(evicted);
    NSUInteger before = sg_spotifyAsks;
    BOOL noLyrics = YES;
    CHECK(!SGKaraokeLookupEnded(evicted));
    CHECK(!timedLinesForCard(evicted, SGKaraokeLinesForTrack(evicted), &noLyrics) && !noLyrics);
    pumpUntil(^BOOL { return !SGKaraokeLooking(evicted); });
    CHECK(!timedLinesForCard(evicted, SGKaraokeLinesForTrack(evicted), &noLyrics) && noLyrics);
    CHECK(sg_spotifyAsks == before + 1);
    sg_holdSpotifyTrack = nil;
    sg_heldSpotifyReply(); sg_heldSpotifyReply = nil;
    pumpUntil(^BOOL { return !SGKaraokeLooking(active); });
    method_setImplementation(method, oldTask);
    sg_spotifyAsks = oldAsks; sg_spclientHeaders = oldHeaders; sg_ownSources = oldOwn;
    sg_player = oldPlayer; sg_lastSeenID = oldSeen;
    puts("completed records: 200-record budgets, active/current protection and evicted misses re-requested");
}

static void checkImportedDelivery(void) {
    sg_testLocalFile = YES;
    sg_importedReplies = [NSMutableDictionary dictionary];
    NSString *a = @"local-import-a", *b = @"local-import-b";
    SGKaraokeRequestLyrics(a);
    CHECK(SGKaraokeLooking(a) && !SGKaraokeLinesForTrack(a));
    void (^stale)(SGLyricsResult *) = sg_importedReplies[a];
    SGKaraokeRequestLyrics(b);
    sg_importedReplies[b](madeUpLyrics(@"Track B", SGKaraokeTimingLine));
    CHECK([SGKaraokeLineText(SGKaraokeLinesForTrack(b).firstObject) isEqual:@"Track B"]);
    SGKaraokeForgetLyrics(a);
    SGKaraokeRequestLyrics(a);
    stale(madeUpLyrics(@"Retired import", SGKaraokeTimingLine));
    CHECK(SGKaraokeLooking(a) && !SGKaraokeLinesForTrack(a));
    sg_importedReplies[a](madeUpLyrics(@"Current import", SGKaraokeTimingLine));
    CHECK([SGKaraokeLineText(SGKaraokeLinesForTrack(a).firstObject) isEqual:@"Current import"]);
    CHECK([SGKaraokeLineText(SGKaraokeLinesForTrack(b).firstObject) isEqual:@"Track B"]);
    SGKaraokeForgetLyrics(a); SGKaraokeForgetLyrics(b);
    sg_importedReplies = nil;
    sg_testLocalFile = NO;
    puts("imported delivery: nonblocking lookup, track isolation and retired-token rejection passed");
}

static void checkSongImport(void) {
    NSString *song = @"7aQAZv5XfpQF63U7lgN6w5";
    NSArray *uris = @[[@"spotify:track:" stringByAppendingString:song]];
    [sg_testDefaults setBool:YES forKey:SGKeyLyricsOffline];
    SGLyricsResult *ordinary = SGLrcLibRecordResult(@{@"syncedLyrics":@"[00:02]Ordinary words"});
    SGLyricsStoreSave(song,ordinary.karaokeLines,@"Ordinary");
    sg_linkedSong = song;
    NSUInteger asks = sg_spotifyAsks;
    sg_providerReply = nil;
    sg_importedReplies = [NSMutableDictionary dictionary];
    SGKaraokeRequestLyrics(song);
    void (^deliver)(SGLyricsResult *) = sg_importedReplies[song];
    HARNESS_CHECK(deliver && !SGKaraokeLinesForTrack(song));
    deliver(SGLyricsPlainTextResult(@"My words", @"Imported LRC"));
    SGKaraokeKeepSpotifyLines(song,ordinary.karaokeLines); // even an unsolicited Spotify answer loses
    HARNESS_CHECK([SGKaraokeLineText(SGKaraokeLinesForTrack(song).firstObject) isEqual:@"My words"]);
    HARNESS_CHECK(!sg_providerReply && sg_spotifyAsks == asks);
    sg_linkedSong = nil;
    importsChanged(uris);
    SGKaraokeRequestLyrics(song);
    pumpUntil(^BOOL { return SGKaraokeLinesForTrack(song).count > 0; });
    HARNESS_CHECK([SGKaraokeLineText(SGKaraokeLinesForTrack(song).firstObject) isEqual:@"Ordinary words"]);
    HARNESS_CHECK(SGLyricsPin(song, (@{@"id":@719, @"syncedLyrics":@"[00:01]Pinned words"})));
    sg_linkedSong = song;
    importsChanged(uris);
    SGKaraokeRequestLyrics(song);
    HARNESS_CHECK([SGKaraokeLineText(SGKaraokeLinesForTrack(song).firstObject) isEqual:@"Pinned words"]);
    sg_linkedSong = nil; sg_importedReplies = nil;
    [sg_pins removeObjectForKey:song];
    SGKaraokeForgetLyrics(song);
    [sg_testDefaults setBool:NO forKey:SGKeyLyricsOffline];
    puts("catalogue song: import above offline, Spotify and sources; ordinary offline words restored; pin preserved");
}

static void checkFileDeliveryReview(void) {
    NSString *song = @"71QAZv5XfpQF63U7lgN6w5";
    SGLyricsResult *ordinary = madeUpLyrics(@"Ordinary offline", SGKaraokeTimingLine);
    SGLyricsResult *file = madeUpLyrics(@"Imported provider", SGKaraokeTimingLine);
    for (SGKaraokeLine *line in file.karaokeLines) line.fileOwned = YES;
    SGLyricsStoreSave(song, ordinary.karaokeLines, @"Ordinary");
    // The source walk writes directly with a lease, independently of the keeper's authority.
    SGLyricsStoreSaveWithLease(song, [[NSArray alloc] initWithArray:file.karaokeLines copyItems:YES],
                               @"Provider", [SGLyricsLease new]);
    __block NSString *saved;
    SGLyricsStoreLoad(song, ^(NSArray *lines, NSString *credit, SGLyricsResult *metadata) {
        saved = SGKaraokeLineText(lines.firstObject) ?: @"";
    });
    pumpUntil(^BOOL { return saved != nil; });
    SGLyricsStoreDelete(song);

    sg_testLocalFile = YES;
    HarnessLyricsState *state = [HarnessLyricsState new];
    state.track = [HarnessLyricsTrack new]; state.track.URI = @"spotify:local:A:B:C:120";
    sg_fixtureState = (id)state;
    sg_importedReplies = [NSMutableDictionary dictionary];
    NSString *key = state.track.URI;
    SGKaraokeTrackWatcher *watcher = [SGKaraokeTrackWatcher new];
    SGKaraokeRequestLyrics(key);
    sg_importedReplies[key](madeUpLyrics(@"Name match",SGKaraokeTimingLine));
    state.track.metadata = @{@"local_file_path":@"/fixture/c.mp3"};
    if ([watcher respondsToSelector:@selector(playerStateDidReport:)]) [watcher playerStateDidReport:(id)state];
    if ([sg_testReportedPath isEqual:@"/fixture/c.mp3"]) sg_importedReplies[key](madeUpLyrics(@"Embedded",SGKaraokeTimingLine));
    NSString *shown = SGKaraokeLineText(SGKaraokeLinesForTrack(key).firstObject);
    sg_fixtureState = nil; sg_testLocalFile = NO; sg_importedReplies = nil;
    SGKaraokeForgetLyrics(key);
    if (![saved isEqual:@"Ordinary offline"] || ![shown isEqual:@"Embedded"])
        HARNESS_FAIL(@"offline=%@, after path report=%@", saved, shown);
    puts("file delivery review: offline copy survives file provider; late local path replaces name match");
}

static void checkDirectInstrumentalFallback(void) {
    BOOL oldOwn = sg_ownSources, oldLocal = sg_testLocalFile;
    sg_ownSources = NO;
    sg_testLocalFile = YES;
    SGLyricsProvider *provider = SGLyricsProviderFor(@"lrclib");
    SGLyricsAsk saved = provider.ask;
    __block void (^reply)(SGLyricsResult *);
    provider.ask = ^(SGLyricsQuery *query, void (^done)(SGLyricsResult *)) { reply = done; };
    NSString *track = NSUUID.UUID.UUIDString;
    __block BOOL deliveredEmptySheet = NO;
    id observer = [NSNotificationCenter.defaultCenter addObserverForName:SGKaraokeLinesKeptNotification
        object:track queue:nil usingBlock:^(NSNotification *note) {
            NSArray *lines = SGKaraokeLinesForTrack(track);
            deliveredEmptySheet = lines != nil && lines.count == 0 && !SGKaraokeLooking(track);
        }];
    SGKaraokeRequestLyrics(track);
    pumpUntil(^BOOL { return reply != nil; });
    reply(SGLrcLibRecordResult(@{@"instrumental": @YES}));
    CHECK(deliveredEmptySheet);
    CHECK([SGLyricsCreditFor(track) isEqual:@"LRCLIB"]);
    [NSNotificationCenter.defaultCenter removeObserver:observer];
    SGKaraokeForgetLyrics(track);
    provider.ask = saved;
    sg_ownSources = oldOwn;
    sg_testLocalFile = oldLocal;
    puts("direct instrumental fallback: sources disabled, local empty sheet and completion notification passed");
}

static void checkMissingRecovery(void) {
    for (NSNumber *early in @[@NO, @YES]) {
        NSString *track = NSUUID.UUID.UUIDString;
        SGLyricsProvider *provider = SGLyricsProviderFor(@"musixmatch");
        SGLyricsAsk saved = provider.ask;
        SGLyricsSetOrder(@[@"musixmatch"]);
        SGSetInt(SGKeyLyricsAskMode, early.boolValue ? 1 : 0);
        provider.ask = ^(SGLyricsQuery *q, void (^done)(SGLyricsResult *)) { done(nil); };
        __block BOOL completed = NO;
        SGLyricsFetch(track, ^(SGLyricsResult *result) { CHECK(!result); completed = YES; });
        pumpUntil(^BOOL { return completed; });
        CHECK(!SGLyricsMayHave(track));
        // Evict through normal requests, not by clearing the negative marker under test.
        for (NSUInteger i = 0; i < 41; i++) {
            completed = NO;
            SGLyricsFetch(NSUUID.UUID.UUIDString, ^(SGLyricsResult *result) { completed = YES; });
            pumpUntil(^BOOL { return completed; });
        }
        provider.ask = ^(SGLyricsQuery *q, void (^done)(SGLyricsResult *)) { done(madeUpLyrics(@"Recovered", SGKaraokeTimingLine)); };
        SGLyricsAsk tail = SGLyricsProviderFor(@"netease").ask;
        void (^__block later)(SGLyricsResult *);
        if (early.boolValue) {
            SGLyricsSetOrder(@[@"musixmatch", @"netease"]);
            SGLyricsProviderFor(@"netease").ask = ^(SGLyricsQuery *q, void (^done)(SGLyricsResult *)) { later = done; };
        }
        completed = NO;
        SGLyricsFetch(track, ^(SGLyricsResult *result) {
            CHECK([result.provider isEqual:@"Recovered"]);
            CHECK(SGLyricsMayHave(track));
            completed = YES;
        });
        pumpUntil(^BOOL { return completed; });
        if (early.boolValue) { pumpUntil(^BOOL { return later != nil; }); later(nil); }
        provider.ask = saved;
        SGLyricsProviderFor(@"netease").ask = tail;
    }
    SGLyricsSetOrder(@[@"musixmatch"]);
    SGSetInt(SGKeyLyricsAskMode, 0);
    puts("missing recovery: final and early positive deliveries clear negative marks");
}

static void checkWalkTypes(void) {
    NSArray *keys = @[@"musixmatch", @"netease", @"unison"];
    NSMutableArray *saved = [NSMutableArray array], *asked = [NSMutableArray array];
    NSMutableDictionary *replies = [NSMutableDictionary dictionary];
    for (NSString *key in [keys arrayByAddingObject:SGImportedLRCKey]) {
        SGLyricsProvider *provider = SGLyricsProviderFor(key);
        [saved addObject:(id)provider.ask ?: NSNull.null];
        provider.ask = ^(SGLyricsQuery *query, void (^done)(SGLyricsResult *)) {
            [asked addObject:key]; done(replies[key]);
        };
    }
    void (^run)(BOOL, SGLyricsTypes, SGKaraokeTiming, SGKaraokeTiming, NSArray *, NSString *) =
    ^(BOOL typeFirst, SGLyricsTypes allowed, SGKaraokeTiming first, SGKaraokeTiming second, NSArray *expected, NSString *winner) {
        [asked removeAllObjects];
        SGLyricsSetOrder(keys);
        SGSetInt(SGKeyLyricsAskMode, typeFirst ? 1 : 0);
        SGLyricsSetSourceTypes(keys[0], allowed);
        replies[keys[0]] = madeUpLyrics(keys[0], first);
        replies[keys[1]] = madeUpLyrics(keys[1], second);
        replies[keys[2]] = madeUpLyrics(keys[2], SGKaraokeTimingLine);
        __block SGLyricsResult *answer;
        NSString *track = NSUUID.UUID.UUIDString;
        SGLyricsFetch(track, ^(SGLyricsResult *result) { answer = result; });
        pumpUntil(^BOOL { return answer != nil; });
        CHECK([asked isEqual:expected]);
        answer = SGLyricsKeptAnswer(track);
        CHECK([answer.provider isEqual:winner] && [answer.pageProvider isEqual:winner]);
    };
    run(NO, SGLyricsTypesAny, SGKaraokeTimingLine, SGKaraokeTimingWords, @[keys[0]], keys[0]);
    run(YES, SGLyricsTypesAny, SGKaraokeTimingLine, SGKaraokeTimingWords, @[keys[0], keys[1]], keys[1]);
    run(YES, SGLyricsTypesAny, SGKaraokeTimingLine, SGKaraokeTimingLine, keys, keys[0]);
    run(YES, SGLyricsTypesAny, SGKaraokeTimingWords, SGKaraokeTimingWords, @[keys[0]], keys[0]);
    run(NO, SGLyricsTypesSynced, SGKaraokeTimingNone, SGKaraokeTimingLine, @[keys[0], keys[1]], keys[1]);
    run(NO, SGLyricsTypesWords, SGKaraokeTimingLine, SGKaraokeTimingWords, @[keys[0], keys[1]], keys[1]);
    run(NO, SGLyricsTypesSynced, SGKaraokeTimingLine, SGKaraokeTimingWords, @[keys[0]], keys[0]);
    run(NO, SGLyricsTypesWords, SGKaraokeTimingWords, SGKaraokeTimingWords, @[keys[0]], keys[0]);
    run(YES, SGLyricsTypesAny, SGKaraokeTimingNone, SGKaraokeTimingLine, keys, keys[1]);
    [asked removeAllObjects];
    SGLyricsSetOrder(@[SGImportedLRCKey]);
    [NSUserDefaults.standardUserDefaults setObject:@{SGImportedLRCKey: @(SGLyricsTypesWords)} forKey:SGKeyLyricsSourceTypes];
    replies[SGImportedLRCKey] = madeUpLyrics(@"Imported", SGKaraokeTimingNone);
    __block SGLyricsResult *answer;
    SGLyricsFetch(NSUUID.UUID.UUIDString, ^(SGLyricsResult *result) { answer = result; });
    pumpUntil(^BOOL { return answer != nil; });
    CHECK([answer.provider isEqual:@"Imported"] && SGLyricsSourceTypes(SGImportedLRCKey) == SGLyricsTypesAny);
    // The first source needed the name that the second source discovers. It still wins a tie.
    [asked removeAllObjects];
    SGLyricsSetOrder(@[keys[1], keys[0], keys[2]]);
    replies[keys[0]] = madeUpLyrics(keys[0], SGKaraokeTimingWords);
    replies[keys[1]] = madeUpLyrics(keys[1], SGKaraokeTimingWords);
    ((SGLyricsResult *)replies[keys[0]]).title = @"Named later";
    ((SGLyricsResult *)replies[keys[0]]).artist = @"Singer";
    SGLyricsQuery *unnamed = [SGLyricsQuery new]; unnamed.trackID = NSUUID.UUID.UUIDString;
    answer = nil;
    sg_waiting[unnamed.trackID] = [NSMutableArray arrayWithObject:[^(SGLyricsResult *result) { answer = result; } copy]];
    startWalk(unnamed.trackID, unnamed);
    CHECK([asked isEqual:(@[keys[0], keys[1]])] && [answer.provider isEqual:keys[0]]);
    SGLyricsResult *settled = SGLyricsKeptAnswer(unnamed.trackID);
    CHECK([settled.provider isEqual:keys[1]] && [settled.pageProvider isEqual:keys[1]]);
    NSUInteger index = 0;
    for (NSString *key in [keys arrayByAddingObject:SGImportedLRCKey]) {
        id original = saved[index++]; SGLyricsProviderFor(key).ask = original == NSNull.null ? nil : original;
    }
    [NSUserDefaults.standardUserDefaults removeObjectForKey:SGKeyLyricsSourceTypes];
    SGSetInt(SGKeyLyricsAskMode, 0);
    SGLyricsSetOrder(@[@"musixmatch"]);
    printf("walk types: default early stop, type-first upgrade and ties including late naming, any/synced/words filtering and imported bypass passed\n");
}

static void checkWalkEarlyAnswer(void) {
    NSArray *keys = @[@"musixmatch", @"netease", @"unison"];
    NSMutableArray *saved = [NSMutableArray array], *asked = [NSMutableArray array];
    NSMutableDictionary *pending = [NSMutableDictionary dictionary];
    for (NSString *key in keys) {
        SGLyricsProvider *provider = SGLyricsProviderFor(key);
        [saved addObject:(id)provider.ask ?: NSNull.null];
        provider.ask = ^(SGLyricsQuery *query, void (^done)(SGLyricsResult *)) {
            [asked addObject:key]; pending[key] = [done copy];
        };
    }
    SGSetInt(SGKeyLyricsAskMode, 1);
    SGLyricsSetOrder(keys);
    for (NSString *action in @[@"upgrade", @"pin", @"reload", @"filter"]) {
        NSString *track = [@"early-" stringByAppendingString:action];
        [asked removeAllObjects]; [pending removeAllObjects];
        SGLyricsResult *line = madeUpLyrics(@"First lines", SGKaraokeTimingLine);
        SGLyricsResult *words = madeUpLyrics(@"Later words", SGKaraokeTimingWords);
        __block NSUInteger deliveries = 0, hookEnds = 0;
        for (NSUInteger i = 0; i < 2; i++) SGLyricsFetch(track, ^(SGLyricsResult *result) {
            CHECK(SGKaraokeLinesTiming(result.karaokeLines) == SGKaraokeTimingLine);
            CHECK([result.provider isEqual:line.provider]);
            deliveries++;
        });
        SGKaraokeRequestLyrics(track);
        // The color-lyrics completion is a waiter too; it must deliver before the second source.
        HarnessDelegate *delegate = [HarnessDelegate new];
        SGLyricsTaskState *state = [SGLyricsTaskState new];
        state.track = track; state.pinGeneration = SGLyricsPinGeneration(track);
        finishSpotify(delegate, nil, nil, state, pageBody(line, nil), nil, ^(NSError *error) {
            CHECK(!error); hookEnds++;
        });
        pumpUntil(^BOOL { return pending[keys[0]] && sg_waiting[track].count == 4; });
        CHECK(!deliveries && !hookEnds && !pending[keys[1]]);
        void (^first)(SGLyricsResult *) = pending[keys[0]];
        first(line);
        CHECK(deliveries == 2 && hookEnds == 1 && delegate.deliveries == 1);
        CHECK(sg_waiting[track] && !sg_waiting[track].count && pending[keys[1]]);
        CHECK(SGKaraokeLinesTiming(SGKaraokeLinesForTrack(track)) == SGKaraokeTimingLine);
        CHECK([SGLyricsCreditFor(track) isEqual:line.provider]);
        __block SGLyricsResult *cached;
        SGLyricsFetch(track, ^(SGLyricsResult *result) { cached = result; });
        pumpUntil(^BOOL { return cached != nil; });
        CHECK(cached == sg_kept[track] && [cached.provider isEqual:line.provider]);
        CHECK([asked isEqual:(@[keys[0], keys[1]])]);
        void (^late)(SGLyricsResult *) = pending[keys[1]];

        if ([action isEqual:@"pin"]) {
            CHECK(SGLyricsPin(track, @{@"id": @901, @"syncedLyrics": @"[00:01]Pinned lines"}));
            SGLyricsResult *pinned = sg_kept[track];
            NSArray *pinnedLines = SGKaraokeLinesForTrack(track);
            late(words);
            CHECK(sg_kept[track] == pinned && SGKaraokeLinesForTrack(track) == pinnedLines);
            CHECK([SGLyricsCreditFor(track) isEqual:@"LRCLIB"] && !sg_waiting[track]);
            // Even after cache eviction, a successful pinned answer never continues the order.
            [sg_kept removeObjectForKey:track]; sg_pinnedReply = nil;
            __block SGLyricsResult *pinAnswer;
            SGLyricsFetch(track, ^(SGLyricsResult *result) { pinAnswer = result; });
            pumpUntil(^BOOL { return sg_pinnedReply != nil; });
            sg_pinnedReply(pinned);
            CHECK([pinAnswer.karaokeLines isEqual:pinned.karaokeLines] && !sg_waiting[track] && asked.count == 2);
        } else if ([action isEqual:@"reload"]) {
            SGLyricsPinStamp *generation = SGLyricsPinGeneration(track);
            SGLyricsReload(track);
            CHECK(![SGLyricsPinGeneration(track) isEqual:generation]);
            CHECK(!sg_kept[track] && !SGKaraokeLinesForTrack(track) && !SGLyricsCreditFor(track));
            late(words);
            CHECK(!sg_kept[track] && !SGKaraokeLinesForTrack(track) && !SGLyricsCreditFor(track));
            pumpUntil(^BOOL { return sg_waiting[track].count == 1; });
            CHECK(asked.count == 3 && [asked.lastObject isEqual:keys[0]]);
            void (^reloaded)(SGLyricsResult *) = pending[keys[0]];
            reloaded(madeUpLyrics(@"Reloaded words", SGKaraokeTimingWords));
            SGLyricsResult *kept = sg_kept[track];
            NSArray *keptLines = SGKaraokeLinesForTrack(track);
            late(words);
            CHECK(sg_kept[track] == kept && SGKaraokeLinesForTrack(track) == keptLines);
            CHECK([SGLyricsCreditFor(track) isEqual:@"Reloaded words"] && !sg_waiting[track]);
        } else {
            if ([action isEqual:@"filter"]) {
                SGLyricsSetSourceTypes(keys[1], SGLyricsTypesWords);
                NSArray *before = SGKaraokeLinesForTrack(track);
                late(madeUpLyrics(@"Rejected lines", SGKaraokeTimingLine));
                CHECK(SGKaraokeLinesForTrack(track) == before && [SGLyricsCreditFor(track) isEqual:line.provider]);
                CHECK(pending[keys[2]] && sg_waiting[track]);
                late = pending[keys[2]];
            }
            late(words);
            SGLyricsResult *kept = sg_kept[track];
            CHECK(SGKaraokeLinesTiming(kept.karaokeLines) == SGKaraokeTimingWords);
            CHECK([kept.provider isEqual:words.provider] && [kept.pageProvider isEqual:words.provider]);
            CHECK(SGKaraokeLinesTiming(SGKaraokeLinesForTrack(track)) == SGKaraokeTimingWords);
            CHECK([SGKaraokeLineText(SGKaraokeLinesForTrack(track).firstObject) isEqual:words.provider]);
            CHECK([SGLyricsCreditFor(track) isEqual:words.provider] && !sg_waiting[track]);
        }
        CHECK(deliveries == 2 && hookEnds == 1 && delegate.deliveries == 1);
        SGLyricsSetSourceTypes(keys[1], SGLyricsTypesAny);
    }
    NSUInteger index = 0;
    for (NSString *key in keys) {
        id original = saved[index++]; SGLyricsProviderFor(key).ask = original == NSNull.null ? nil : original;
    }
    SGSetInt(SGKeyLyricsAskMode, 0);
    SGLyricsSetOrder(@[@"musixmatch"]);
    printf("type-first early answer: waiters and color-lyrics released before later source; cached answer, word upgrade, credit, filters, pin and reload rejection passed\n");
}

// A sentinel behind queued provider replies also lets checks prove that a late reply did nothing.
static void drainReplies(void) {
    __block BOOL drained = NO;
    dispatch_async(dispatch_get_main_queue(), ^{ drained = YES; });
    pumpUntil(^BOOL { return drained; });
}

// Provider callbacks and the recovery clock are the only doubles: cache, playback publication,
// translations and disk reads/writes below use their production owners.
@interface RecoveryFixture : NSObject
@property (nonatomic, strong) NSMutableDictionary *held, *saved;
- (void)reply:(NSString *)key track:(NSString *)track result:(SGLyricsResult *)result failed:(BOOL)failed;
- (void)advance;
- (void)restore;
@end
@implementation RecoveryFixture
- (instancetype)init {
    if (!(self = [super init])) return nil;
    self.held = [NSMutableDictionary dictionary]; self.saved = [NSMutableDictionary dictionary];
    __weak RecoveryFixture *weak = self;
    for (NSString *key in @[@"musixmatch", @"netease", @"unison", @"genius", SGSpicyLyricsKey]) {
        SGLyricsProvider *provider = SGLyricsProviderFor(key);
        self.saved[key] = (id)provider.ask ?: NSNull.null;
        provider.ask = ^(SGLyricsQuery *query, void (^done)(SGLyricsResult *)) {
            weak.held[[query.trackID stringByAppendingString:key]] = ^(SGLyricsResult *result, BOOL failed) {
                [query.requestContext noteFailure:failed];
                done(result);
            };
        };
    }
    sg_recoveryClocks = [NSMutableArray array];
    SGSetEnabled(SGKeyLyricsOffline, YES);
    return self;
}
- (void)reply:(NSString *)key track:(NSString *)track result:(SGLyricsResult *)result failed:(BOOL)failed {
    NSString *identity = [track stringByAppendingString:key];
    void (^done)(SGLyricsResult *, BOOL) = self.held[identity];
    CHECK(done);
    [self.held removeObjectForKey:identity];
    done(result, failed);
    drainReplies();
}
- (void)advance {
    CHECK(sg_recoveryClocks.count == 1);
    dispatch_block_t next = sg_recoveryClocks.firstObject;
    [sg_recoveryClocks removeAllObjects];
    next();
    drainReplies();
}
- (void)restore {
    for (NSString *key in self.saved) {
        id saved = self.saved[key];
        SGLyricsProviderFor(key).ask = saved == NSNull.null ? nil : saved;
    }
    sg_recoveryClocks = nil;
    SGSetEnabled(SGKeyLyricsOffline, NO);
    SGSetEnabled(SGKeyLyricsPreferWordTiming, NO);
    SGSetInt(SGKeyLyricsAskMode, 0);
    SGLyricsSetOrder(@[@"musixmatch"]);
    SGLyricsPlaybackChanged(nil);
}
@end

static NSDictionary *recoveryDisk(NSString *track) {
    drainReplies();
    __block BOOL loaded = NO;
    __block NSDictionary *value;
    SGLyricsStoreLoad(track, ^(NSArray *lines, NSString *credit, SGLyricsResult *metadata) {
        if (lines.count) value = @{@"text": SGKaraokeLineText(lines.firstObject), @"credit": credit ?: @"",
                                  @"required": @(metadata.creditRequired)};
        loaded = YES;
    });
    pumpUntil(^BOOL { return loaded; });
    return value;
}

static void checkCredentialFallback(void) {
    RecoveryFixture *fixture = [RecoveryFixture new];
    SGLyricsProvider *spicy = SGLyricsProviderFor(SGSpicyLyricsKey);
    SGLyricsSetOrder(@[SGSpicyLyricsKey, @"deezer", @"musixmatch"]);
    for (NSUInteger rejected = 0; rejected <= 1; rejected++) {
        NSString *track = rejected ? @"0123456789abcdefghijkR" : @"0123456789abcdefghijkU";
        spicy.ask = SGSpicyLyricsAsk;
        if (rejected) spicy.ask = ^(SGLyricsQuery *q, void (^done)(SGLyricsResult *)) {
            SGSpicyLyricsAskWith(@"sl_pk_fixture", q, done);
        };
        SGLyricsPlaybackChanged(track);
        SGKaraokeRequestLyrics(track);
        if (rejected) {
            pumpUntil(^BOOL { return sg_spicyReply != nil; });
            sg_spicyReply(nil, [[NSHTTPURLResponse alloc] initWithURL:[NSURL URLWithString:@"https://fixture.invalid"]
                statusCode:401 HTTPVersion:nil headerFields:nil]);
            sg_spicyReply = nil;
        }
        pumpUntil(^BOOL { return fixture.held[[track stringByAppendingString:@"musixmatch"]] != nil; });
        [fixture reply:@"musixmatch" track:track result:madeUpLyrics(@"Fallback", SGKaraokeTimingLine) failed:NO];
        CHECK([SGKaraokeLineText(SGKaraokeLinesForTrack(track).firstObject) isEqual:@"Fallback"]);
        SGLyricsResult *answer = SGLyricsKeptAnswer(track);
        CHECK(answer && answer.provisional == rejected);
        CHECK(rejected ? !recoveryDisk(track) : [recoveryDisk(track)[@"text"] isEqual:@"Fallback"]);
    }
    SGSpicyLyricsForgetKey();
    [fixture restore];
}

static void checkSoundtrackRetry(void) {
    // One invocation contract: only a genuine empty name search can remove its film annotation.
    for (NSString *title in @[@"Song (From \"Film\")", @"Song (From the Motion Picture Film)",
                              @"Song OST", @"Song - Original Soundtrack", @"Song From “Film”",
                              @"Song - Original Soundtrack - Live", @"Song (From \"Howl's Moving Castle\")",
                              @"Song - Live (From \"Film\")", @"Song - Live", @"From Home", @" Song "]) {
        BOOL annotated = ![title isEqual:@"Song - Live"] && ![title isEqual:@"From Home"] && ![title isEqual:@" Song "];
        NSString *clean = [title isEqual:@"Song - Live (From \"Film\")"] || [title isEqual:@"Song - Original Soundtrack - Live"] ? @"Song - Live" : @"Song";
        for (NSString *outcome in @[@"empty", @"empty-again", @"rejected", @"timeout", @"refused", @"id", @"found", @"retired"]) {
            SGLyricsQuery *query = [SGLyricsQuery new];
            query.trackID = @"1234567890123456789012"; query.title = title;
            query.artist = @"Singer"; query.album = @"Album"; query.seconds = 200;
            SGLyricsProvider *provider = [SGLyricsProvider new];
            provider.needsName = NO; // Like Musixmatch: the lookup, not the provider, can be by name.
            SGLyricsWalk *walk = nil;
            if ([outcome isEqual:@"retired"]) {
                query.trackID = @"retired-soundtrack";
                walk = [SGLyricsWalk new];
                walk.query = query;
                walk.generation = SGLyricsPinGeneration(query.trackID);
                sg_walks[query.trackID] = walk;
            }
            SGLyricsResult *expected = SGLrcLibRecordResult(@{@"plainLyrics": @"Own song"});
            __block BOOL retried = NO, finished = NO;
            __block void (^pending)(SGLyricsResult *);
            provider.ask = ^(SGLyricsQuery *first, void (^done)(SGLyricsResult *)) {
                if (![outcome isEqual:@"rejected"] && ![outcome isEqual:@"id"]) first.requestContext.emptyNameSearch = ^(SGLyricsQuery *again, void (^answer)(SGLyricsResult *)) {
                    CHECK(!retried && NSThread.isMainThread);
                    retried = YES;
                    CHECK([again.title isEqual:clean] && [again.artist isEqual:@"Singer"]);
                    CHECK([again.album isEqual:@"Album"] && again.seconds == 200 && [again.trackID isEqual:query.trackID]);
                    // A second empty result must finish, not start another attempt.
                    again.requestContext.emptyNameSearch = ^(SGLyricsQuery *unused, void (^unexpected)(SGLyricsResult *)) { CHECK(NO); };
                    answer([outcome isEqual:@"empty"] ? expected : nil);
                };
                if ([outcome isEqual:@"timeout"])
                    [first.requestContext noteResponse:nil error:[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorTimedOut userInfo:nil]];
                if ([outcome isEqual:@"refused"])
                    [first.requestContext noteResponse:[[NSHTTPURLResponse alloc] initWithURL:[NSURL URLWithString:@"https://fixture.invalid"]
                        statusCode:403 HTTPVersion:nil headerFields:nil] error:nil];
                if (walk) pending = [done copy];
                else done([outcome isEqual:@"found"] ? expected : nil);
            };
            SGLyricsInvoke(provider, query, ^BOOL { return !walk || currentWalk(walk); }, ^(SGLyricsResult *result, BOOL failed) {
                CHECK(!finished && NSThread.isMainThread);
                CHECK(result == (([outcome isEqual:@"found"] || (annotated && [outcome isEqual:@"empty"])) ? expected : nil));
                CHECK(failed == ([outcome isEqual:@"timeout"] || [outcome isEqual:@"refused"]));
                finished = YES;
            });
            if (walk) {
                CHECK(!finished && pending);
                SGLyricsRetire(query.trackID);
                pending(nil);
            }
            CHECK(finished && retried == (annotated && ([outcome isEqual:@"empty"] || [outcome isEqual:@"empty-again"])));
            CHECK([query.title isEqual:title]);
        }
    }
    puts("soundtrack retry: genuine empty only, once, annotations, versions, failures and ID exclusion passed");
}

static void checkInvocationIsolation(void) {
    SGLyricsProvider *provider = [SGLyricsProvider new];
    NSMutableArray *contexts = [NSMutableArray array], *replies = [NSMutableArray array];
    provider.ask = ^(SGLyricsQuery *query, void (^done)(SGLyricsResult *)) {
        [contexts addObject:query.requestContext]; [replies addObject:[done copy]];
    };
    SGLyricsQuery *query = [SGLyricsQuery new]; query.trackID = @"same-track";
    __block NSUInteger completions = 0;
    SGLyricsInvoke(provider, query, nil, ^(SGLyricsResult *result, BOOL failed) { CHECK(!result && failed); completions++; });
    SGLyricsInvoke(provider, query, nil, ^(SGLyricsResult *result, BOOL failed) { CHECK(!result && !failed); completions++; });
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        [contexts[0] noteResponse:nil error:[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorTimedOut userInfo:nil]];
        // A later successful/missing subrequest must not erase the failed search.
        [contexts[0] noteFailure:NO];
        SGLyricsNoteReply(nil, [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorNetworkConnectionLost userInfo:nil]);
        ((void (^)(SGLyricsResult *))replies[1])(nil);
        ((void (^)(SGLyricsResult *))replies[0])(nil);
    });
    pumpUntil(^BOOL { return completions == 2; });
}

static void checkRecoveryNextPlayback(void) {
    RecoveryFixture *fixture = [RecoveryFixture new];
    for (NSUInteger policy = 0; policy < 4; policy++) {
        SGSetInt(SGKeyLyricsAskMode, policy == 3 ? 0 : policy);
        SGSetEnabled(SGKeyLyricsPreferWordTiming, policy == 3);
        SGLyricsSetOrder(@[@"musixmatch", @"netease", @"unison"]);
        NSString *track = NSUUID.UUID.UUIDString;
        SGLyricsPlaybackChanged(track);
        SGKaraokeRequestLyrics(track);
        pumpUntil(^BOOL { return fixture.held[[track stringByAppendingString:@"musixmatch"]] != nil; });
        [fixture reply:@"musixmatch" track:track result:nil failed:YES];
        [fixture reply:@"netease" track:track result:madeUpLyrics(@"Fallback", SGKaraokeTimingLine) failed:NO];
        CHECK([SGKaraokeLineText(SGKaraokeLinesForTrack(track).firstObject) isEqual:@"Fallback"]);
        CHECK(!recoveryDisk(track));
        __block SGLyricsResult *early;
        SGLyricsFetch(track, ^(SGLyricsResult *result) { early = result; });
        pumpUntil(^BOOL { return early != nil; });
        if (policy != 0) [fixture reply:@"unison" track:track result:nil failed:NO];
        [fixture advance];
        SGLyricsResult *recovered = madeUpLyrics(@"Recovered", SGKaraokeTimingLine);
        recovered.creditRequired = YES;
        [fixture reply:@"musixmatch" track:track result:recovered failed:NO];
        CHECK([SGKaraokeLineText(SGKaraokeLinesForTrack(track).firstObject) isEqual:@"Fallback"]);
        CHECK([SGLyricsCreditFor(track) isEqual:@"Fallback"]);
        CHECK([early.provider isEqual:@"Fallback"] && [early.texts containsObject:@"Fallback"]);
        __block SGLyricsResult *current;
        SGLyricsFetch(track, ^(SGLyricsResult *result) { current = result; });
        pumpUntil(^BOOL { return current != nil; });
        CHECK([current.texts containsObject:@"Fallback"]);
        CHECK([recoveryDisk(track) isEqual:(@{@"text": @"Recovered", @"credit": @"Recovered", @"required": @YES})]);
        // A language refresh republishes the displayed sheet, but cannot replace the pending disk winner.
        keep(track, SGKaraokeLinesForTrack(track), NO);
        CHECK([recoveryDisk(track)[@"text"] isEqual:@"Recovered"]);
        SGLyricsPlaybackChanged(@"other-track");
        SGLyricsPlaybackChanged(track);
        SGKaraokeRequestLyrics(track);
        CHECK([SGKaraokeLineText(SGKaraokeLinesForTrack(track).firstObject) isEqual:@"Recovered"]);
        CHECK([SGLyricsCreditFor(track) isEqual:@"Recovered"]);
        SGLyricsPlaybackChanged(nil);
        // Eviction is memory-only; a new keeper request must load the finalized answer from disk.
        for (NSUInteger i = 0; i < 41; i++) SGKaraokeKeepLines(NSUUID.UUID.UUIDString, @[]);
        SGKaraokeRequestLyrics(track);
        pumpUntil(^BOOL { return SGKaraokeLinesForTrack(track) != nil; });
        CHECK([SGKaraokeLineText(SGKaraokeLinesForTrack(track).firstObject) isEqual:@"Recovered"]);
        SGKaraokeForgetLyrics(track);
    }
    [fixture restore];
}

static void checkFailureFallback(void) {
    RecoveryFixture *fixture = [RecoveryFixture new];
    for (NSInteger mode = 0; mode < 3; mode++) {
        SGSetInt(SGKeyLyricsAskMode, mode);
        SGLyricsSetOrder(@[@"musixmatch", @"genius"]);
        NSString *track = NSUUID.UUID.UUIDString;
        HarnessLyricsTrack *metadata = [HarnessLyricsTrack new];
        metadata.trackTitle = @"A song"; metadata.artistName = @"A singer";
        metadata.URI = [@"spotify:track:" stringByAppendingString:track];
        SGKaraokeRememberTrack((id)metadata, track);
        SGLyricsNoteSpotifyHas(track, YES);
        __block BOOL finished = NO;
        __block SGLyricsResult *answer;
        SGLyricsFetch(track, ^(SGLyricsResult *result) { answer = result; finished = YES; });
        pumpUntil(^BOOL { return fixture.held[[track stringByAppendingString:@"musixmatch"]] != nil; });
        [fixture reply:@"musixmatch" track:track result:nil failed:YES];
        // Spotify metadata promises lyrics, but only an actual sheet can suppress the fallback.
        CHECK(fixture.held[[track stringByAppendingString:@"genius"]] != nil);
        [fixture reply:@"genius" track:track result:SGLyricsPlainTextResult(@"Available words", @"Genius") failed:NO];
        pumpUntil(^BOOL { return finished; });
        CHECK([SGKaraokeLineText(answer.karaokeLines.firstObject) isEqual:@"Available words"]);
        CHECK(!SGLyricsLoadFailed(track));
        [fixture advance];
        [fixture reply:@"musixmatch" track:track result:nil failed:YES];
        __block SGLyricsResult *cached;
        SGLyricsFetch(track, ^(SGLyricsResult *result) { cached = result; });
        pumpUntil(^BOOL { return cached != nil; });
        CHECK([SGKaraokeLineText(cached.karaokeLines.firstObject) isEqual:@"Available words"]);
        SGKaraokeForgetLyrics(track);
        [sg_recoveryClocks removeAllObjects];
    }
    for (NSNumber *failure in @[@NO, @YES]) {
        SGLyricsSetOrder(@[@"musixmatch"]);
        NSString *track = NSUUID.UUID.UUIDString;
        __block BOOL finished = NO;
        SGLyricsFetch(track, ^(SGLyricsResult *result) { CHECK(!result); finished = YES; });
        pumpUntil(^BOOL { return fixture.held[[track stringByAppendingString:@"musixmatch"]] != nil; });
        [fixture reply:@"musixmatch" track:track result:nil failed:failure.boolValue];
        pumpUntil(^BOOL { return finished; });
        CHECK(SGLyricsLoadFailed(track) == failure.boolValue);
        CHECK(SGLyricsMayHave(track) == failure.boolValue);
        SGKaraokeForgetLyrics(track);
    }
    [fixture restore];
    puts("failure fallback: all policies, Spotify metadata, good cache and failure versus absence passed");
}

static void checkInvocationDeadline(void) {
    SGLyricsProvider *provider = SGLyricsProviderFor(@"musixmatch");
    SGLyricsProvider *fallback = SGLyricsProviderFor(@"netease");
    SGLyricsAsk saved = provider.ask, savedFallback = fallback.ask;
    BOOL needsName = fallback.needsName;
    fallback.needsName = NO;
    SGLyricsSetOrder(@[@"musixmatch", @"netease"]);
    SGSetInt(SGKeyLyricsAskMode, 0);
    sg_deadlineEvents = [NSMutableArray array];
    __block void (^late)(SGLyricsResult *);
    provider.ask = ^(SGLyricsQuery *query, void (^done)(SGLyricsResult *)) { late = done; };
    fallback.ask = ^(SGLyricsQuery *query, void (^done)(SGLyricsResult *)) {
        done(SGLyricsPlainTextResult(@"Timely fallback", @"Fallback"));
    };
    __block NSUInteger completions = 0;
    NSString *track = NSUUID.UUID.UUIDString;
    SGLyricsFetch(track, ^(SGLyricsResult *result) {
        CHECK([SGKaraokeLineText(result.karaokeLines.firstObject) isEqual:@"Timely fallback"]);
        completions++;
    });
    pumpUntil(^BOOL { return late != nil; });
    CHECK(!completions);
    dispatch_block_t expire = sg_deadlineEvents.lastObject;
    CHECK(expire);
    expire();
    CHECK(completions == 1);
    late(SGLyricsPlainTextResult(@"Too late", @"Delayed"));
    CHECK(completions == 1);
    __block SGLyricsResult *cached;
    SGLyricsFetch(track, ^(SGLyricsResult *result) { cached = result; });
    pumpUntil(^BOOL { return cached != nil; });
    CHECK([SGKaraokeLineText(cached.karaokeLines.firstObject) isEqual:@"Timely fallback"]);
    SGKaraokeForgetLyrics(track);
    sg_deadlineEvents = nil;
    provider.ask = saved; fallback.ask = savedFallback; fallback.needsName = needsName;
    SGLyricsSetOrder(@[@"musixmatch"]);
    puts("invocation deadline: stalled source falls through and a late sheet cannot replace the cache");
}

static void checkHedgedWalk(void) {
    for (NSInteger mode = 0; mode < 2; mode++) {
        RecoveryFixture *fixture = [RecoveryFixture new];
        SGSetInt(SGKeyLyricsAskMode, mode);
        SGLyricsSetOrder(@[@"musixmatch", @"netease"]);
        sg_virtualSeconds = 0;
        sg_virtualTimers = [NSMutableDictionary dictionary];
        NSString *track = NSUUID.UUID.UUIDString;
        HarnessLyricsTrack *metadata = [HarnessLyricsTrack new];
        metadata.trackTitle = @"Hedged song"; metadata.artistName = @"Singer";
        metadata.URI = [@"spotify:track:" stringByAppendingString:track];
        SGKaraokeRememberTrack((id)metadata, track);
        SGLyricsPlaybackChanged(track);
        __block SGLyricsResult *answer;
        SGLyricsFetch(track, ^(SGLyricsResult *result) { answer = result; });
        pumpUntil(^BOOL { return fixture.held[[track stringByAppendingString:@"musixmatch"]] != nil; });
        advanceTimers(1.99);
        CHECK(!answer);
        advanceTimers(2);
        CHECK(fixture.held[[track stringByAppendingString:@"netease"]] != nil);
        [fixture reply:@"netease" track:track result:madeUpLyrics(@"Fast second", SGKaraokeTimingWords) failed:NO];
        CHECK([answer.provider isEqual:@"Fast second"]);
        advanceTimers(3);
        [fixture reply:@"musixmatch" track:track result:madeUpLyrics(@"Slow first", SGKaraokeTimingWords) failed:NO];
        CHECK([[SGLyricsKeptAnswer(track) provider] isEqual:@"Slow first"]);
        SGKaraokeForgetLyrics(track);
        sg_virtualTimers = nil;
        [fixture restore];
    }
    puts("hedged walk: fallback at two seconds and higher priority before deadline wins in both sequential modes");
}

@interface CancellationTask : NSObject
@property (nonatomic) BOOL cancelled;
@end
@implementation CancellationTask
- (void)cancel { self.cancelled = YES; }
@end
static void checkRetiredCancellation(void) {
    SGLyricsProvider *provider = SGLyricsProviderFor(@"musixmatch");
    SGLyricsAsk saved = provider.ask;
    SGLyricsSetOrder(@[@"musixmatch"]);
    __block CancellationTask *task;
    provider.ask = ^(SGLyricsQuery *query, void (^done)(SGLyricsResult *)) {
        task = [CancellationTask new];
        [query.requestContext trackTask:(id)task];
    };
    NSString *track = NSUUID.UUID.UUIDString;
    SGLyricsFetch(track, ^(SGLyricsResult *result) {});
    pumpUntil(^BOOL { return task != nil; });
    SGKaraokeForgetLyrics(track);
    CHECK(task.cancelled);
    provider.ask = saved;
    puts("retirement cancels the outstanding provider task");
}

static void checkWalkBudget(void) {
    for (NSNumber *cached in @[@NO, @YES]) {
    RecoveryFixture *fixture = [RecoveryFixture new];
    SGSetInt(SGKeyLyricsAskMode, 1);
    SGLyricsSetOrder(@[@"musixmatch", @"netease", @"unison", SGSpicyLyricsKey, @"genius"]);
    sg_virtualSeconds = 0;
    sg_virtualTimers = [NSMutableDictionary dictionary];
    NSString *track = NSUUID.UUID.UUIDString;
    HarnessLyricsTrack *metadata = [HarnessLyricsTrack new];
    metadata.trackTitle = @"Slow song"; metadata.artistName = @"Singer";
    metadata.URI = [@"spotify:track:" stringByAppendingString:track];
    SGKaraokeRememberTrack((id)metadata, track);
    __block BOOL completed = NO;
    SGLyricsFetch(track, ^(SGLyricsResult *result) {
        if (cached.boolValue) CHECK([result.provider isEqual:@"Spotify"]);
        else CHECK(!result);
        completed = YES;
    });
    pumpUntil(^BOOL { return fixture.held[[track stringByAppendingString:@"musixmatch"]] != nil; });
    if (cached.boolValue) SGKaraokeKeepSpotifyLines(track, madeUpLyrics(@"Cached", SGKaraokeTimingWords).karaokeLines);
    advanceTimers(7.99);
    CHECK(!completed);
    advanceTimers(8);
    CHECK(completed && SGLyricsLoadFailed(track) == !cached.boolValue && SGLyricsMayHave(track));
    __block NSUInteger secondCompletions = 0;
    __block BOOL secondUpdated = NO;
    id observer = [NSNotificationCenter.defaultCenter addObserverForName:SGKaraokeLinesKeptNotification object:track queue:nil
        usingBlock:^(NSNotification *note) {
            secondUpdated = [SGKaraokeLineText(SGKaraokeLinesForTrack(track).firstObject) isEqual:@"Higher priority late"];
        }];
    SGLyricsFetch(track, ^(SGLyricsResult *result) {
        secondCompletions++;
        if (cached.boolValue) CHECK([result.provider isEqual:@"Spotify"]);
        else CHECK(!result && SGLyricsLoadFailed(track));
    });
    drainReplies();
    CHECK(secondCompletions == 1);
    [fixture reply:SGSpicyLyricsKey track:track result:SGLyricsPlainTextResult(@"Late", @"Late") failed:NO];
    if (cached.boolValue) CHECK([[SGLyricsKeptAnswer(track) provider] isEqual:@"Spotify"]);
    else CHECK([[SGLyricsKeptAnswer(track) provider] isEqual:@"Late"] && !SGLyricsLoadFailed(track));
    advanceTimers(8.5);
    [fixture reply:@"unison" track:track result:madeUpLyrics(@"Higher priority late", SGKaraokeTimingWords) failed:NO];
    CHECK([[SGLyricsKeptAnswer(track) provider] isEqual:@"Higher priority late"]);
    CHECK([SGKaraokeLineText(SGKaraokeLinesForTrack(track).firstObject) isEqual:@"Higher priority late"]);
    CHECK(secondCompletions == 1);
    CHECK(secondUpdated);
    [NSNotificationCenter.defaultCenter removeObserver:observer];
    SGKaraokeForgetLyrics(track);
    sg_virtualTimers = nil;
    [fixture restore];
    }
    puts("walk budget: visible by eight seconds, in-flight recovery and late higher priority retained");
}

static void checkFastFailureTiming(void) {
    NSArray *responses = @[@403, @451, @429, @(NSURLErrorCannotFindHost), @(NSURLErrorCannotConnectToHost),
                          @(NSURLErrorSecureConnectionFailed)];
    for (NSNumber *code in responses) {
        RecoveryFixture *fixture = [RecoveryFixture new];
        SGSetInt(SGKeyLyricsAskMode, 1);
        SGLyricsSetOrder(@[@"musixmatch", @"unison"]);
        sg_virtualSeconds = 0;
        sg_virtualTimers = [NSMutableDictionary dictionary];
        NSString *track = NSUUID.UUID.UUIDString;
        HarnessLyricsTrack *metadata = [HarnessLyricsTrack new];
        metadata.trackTitle = @"Fast failure"; metadata.artistName = @"Singer";
        metadata.URI = [@"spotify:track:" stringByAppendingString:track];
        SGKaraokeRememberTrack((id)metadata, track);
        __block SGLyricsResult *answer;
        SGLyricsFetch(track, ^(SGLyricsResult *result) { answer = result; });
        pumpUntil(^BOOL { return fixture.held[[track stringByAppendingString:@"musixmatch"]] != nil; });
        NSURLResponse *response = code.integerValue > 0 ? [[NSHTTPURLResponse alloc]
            initWithURL:[NSURL URLWithString:@"https://example.test/lyrics"] statusCode:code.integerValue
            HTTPVersion:@"HTTP/1.1" headerFields:nil] : nil;
        NSError *error = code.integerValue < 0 ? [NSError errorWithDomain:NSURLErrorDomain code:code.integerValue userInfo:nil] : nil;
        [fixture reply:@"musixmatch" track:track result:nil failed:SGLyricsReplyFailed(response, error)];
        CHECK(fixture.held[[track stringByAppendingString:@"unison"]] != nil);
        [fixture reply:@"unison" track:track result:madeUpLyrics(@"Immediate fallback", SGKaraokeTimingWords) failed:NO];
        CHECK([answer.provider isEqual:@"Immediate fallback"] && sg_virtualSeconds == 0);
        SGKaraokeForgetLyrics(track);
        sg_virtualTimers = nil;
        [fixture restore];
    }
    puts("fast failures: HTTP 403/451/429, DNS, refused connection and TLS fall through without a hedge wait");
}

static void checkSpotifyAuthPause(void) {
    RecoveryFixture *fixture = [RecoveryFixture new];
    SGLyricsSetOrder(@[]);
    BOOL own = sg_ownSources; sg_ownSources = NO;
    NSDictionary *headers = sg_spclientHeaders;
    NSString *refused = sg_refusedAuthorization;
    NSInteger status = sg_spotifyStatus;
    NSUInteger asks = sg_spotifyAsks;
    sg_spotifyStatus = 401;
    sg_spclientHeaders = nil;
    Method method = class_getInstanceMethod(NSURLSession.class, @selector(dataTaskWithRequest:completionHandler:));
    IMP original = method_setImplementation(method, (IMP)spotifyMiss);
    NSString *track = fixtureTrackID();
    SPTPlayerState *oldState = sg_fixtureState;
    HarnessLyricsState *playing = [HarnessLyricsState new];
    playing.track = [HarnessLyricsTrack new];
    playing.track.URI = [@"spotify:track:" stringByAppendingString:track];
    sg_fixtureState = (id)playing;
    __block NSUInteger readyCount = 0;
    id reader = [NSNotificationCenter.defaultCenter addObserverForName:@"spotifyglass.karaoke.lookupReady" object:nil queue:nil
        usingBlock:^(NSNotification *note) {
            if ([note.object isEqual:track]) { readyCount++; SGKaraokeRequestLyrics(note.object); }
        }];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"https://spclient.wg.spotify.com/"]];
    SGKaraokeRequestLyrics(track);
    drainReplies();
    CHECK(sg_spotifyAsks == asks);
    [request setValue:@"fixture-old" forHTTPHeaderField:@"Authorization"];
    captureHeaders(nil, request);
    pumpUntil(^BOOL { return SGLyricsLoadFailed(track); });
    CHECK(sg_spotifyAsks == asks + 1);
    SGKaraokeAskSpotifyForTiming(track);
    drainReplies();
    CHECK(sg_spotifyAsks == asks + 1 && SGLyricsLoadFailed(track));
    NSString *skippedTo = fixtureTrackID();
    __block BOOL refusedAtDelivery = NO;
    id completion = SGKaraokeObserveLinesKept(^(NSNotification *note) {
        if ([note.object isEqual:skippedTo]) refusedAtDelivery = SGKaraokeLookupEnded(skippedTo);
    });
    SGKaraokeRequestLyrics(skippedTo);
    pumpUntil(^BOOL { return SGLyricsLoadFailed(skippedTo); }); // Offline lookup precedes the refused-header path.
    [NSNotificationCenter.defaultCenter removeObserver:completion];
    CHECK(refusedAtDelivery && !requested(skippedTo) && sg_spotifyAsks == asks + 1);
    NSUInteger before = readyCount;
    [request setValue:@"updated-client" forHTTPHeaderField:@"Client-Token"];
    captureHeaders(nil, request);
    drainReplies();
    SGSpclientHeaders(^(NSDictionary *headers) {
        CHECK([headers[@"client-token"] isEqual:@"updated-client"]);
    });
    CHECK(readyCount == before);
    sg_spotifyStatus = 404;
    [request setValue:@"fixture-new" forHTTPHeaderField:@"Authorization"];
    captureHeaders(nil, request);
    pumpUntil(^BOOL { return sg_spotifyAsks == asks + 2; });
    drainReplies();
    CHECK(!SGLyricsLoadFailed(track));
    SGLyricsNoteLoadFailure(track, YES);
    sg_spclientHeaders = @{@"authorization": @"fixture-another"};
    setRequested(track, NO);
    SGKaraokeAskSpotifyForTiming(track);
    pumpUntil(^BOOL { return sg_spotifyAsks == asks + 3; });
    drainReplies();
    CHECK(SGLyricsLoadFailed(track));
    SGKaraokeForgetLyrics(track);
    [NSNotificationCenter.defaultCenter removeObserver:reader];
    sg_fixtureState = oldState;
    method_setImplementation(method, original);
    sg_spclientHeaders = headers; sg_refusedAuthorization = refused;
    sg_spotifyStatus = status; sg_spotifyAsks = asks; sg_ownSources = own;
    [fixture restore];
    puts("Spotify auth: 401 pauses the refused authorization, new captured authorization can retry");
}

static void checkRecoveryUpgradeAndMiss(void) {
    RecoveryFixture *fixture = [RecoveryFixture new];
    SGSetInt(SGKeyLyricsAskMode, 1);
    SGLyricsSetOrder(@[@"musixmatch", @"netease", @"unison"]);
    NSString *track = NSUUID.UUID.UUIDString;
    SGLyricsPlaybackChanged(track);
    SGKaraokeRequestLyrics(track);
    pumpUntil(^BOOL { return fixture.held[[track stringByAppendingString:@"musixmatch"]] != nil; });
    [fixture reply:@"musixmatch" track:track result:madeUpLyrics(@"Early", SGKaraokeTimingLine) failed:NO];
    CHECK(!recoveryDisk(track)); // Outstanding work is non-persistable even before it fails.
    [fixture reply:@"netease" track:track result:nil failed:YES];
    [fixture reply:@"unison" track:track result:nil failed:YES];
    [fixture advance];
    [fixture reply:@"unison" track:track result:madeUpLyrics(@"Word upgrade", SGKaraokeTimingWords) failed:NO];
    CHECK([SGKaraokeLineText(SGKaraokeLinesForTrack(track).firstObject) isEqual:@"Word upgrade"]);
    CHECK(!recoveryDisk(track));
    [fixture reply:@"netease" track:track result:nil failed:YES];
    CHECK([SGKaraokeLineText(SGKaraokeLinesForTrack(track).firstObject) isEqual:@"Word upgrade"]);
    CHECK(!recoveryDisk(track));
    [fixture advance];
    [fixture reply:@"netease" track:track result:nil failed:NO];
    CHECK([recoveryDisk(track)[@"text"] isEqual:@"Word upgrade"]);
    CHECK(!SGLyricsRecovering(track));
    SGKaraokeForgetLyrics(track);
    [fixture restore];
}

static void checkRecoveryFinalAndExhausted(void) {
    RecoveryFixture *fixture = [RecoveryFixture new];
    for (NSUInteger scenario = 0; scenario < 3; scenario++) {
        BOOL wordWins = scenario == 1;
        SGSetInt(SGKeyLyricsAskMode, wordWins ? 2 : 1);
        SGLyricsSetOrder(@[@"musixmatch", @"netease"]);
        NSString *track = NSUUID.UUID.UUIDString;
        SGLyricsPlaybackChanged(track);
        SGKaraokeRequestLyrics(track);
        pumpUntil(^BOOL { return fixture.held[[track stringByAppendingString:@"musixmatch"]] != nil; });
        [fixture reply:@"musixmatch" track:track result:nil failed:YES];
        [fixture reply:@"netease" track:track result:madeUpLyrics(@"Winner", wordWins ? SGKaraokeTimingWords : SGKaraokeTimingLine) failed:NO];
        if (wordWins) {
            CHECK([recoveryDisk(track)[@"text"] isEqual:@"Winner"] && !sg_recoveryClocks.count);
        } else if (scenario == 2) {
            [fixture advance];
            [fixture reply:@"musixmatch" track:track result:nil failed:NO];
            CHECK([recoveryDisk(track)[@"text"] isEqual:@"Winner"] && !SGLyricsRecovering(track));
        } else {
            for (NSUInteger attempt = 0; attempt < 4; attempt++) {
                [fixture advance];
                [fixture reply:@"musixmatch" track:track result:nil failed:YES];
            }
            CHECK(!sg_recoveryClocks.count && !recoveryDisk(track));
            keep(track, SGKaraokeLinesForTrack(track), NO);
            CHECK(!recoveryDisk(track));
        }
        SGKaraokeForgetLyrics(track);
    }
    [fixture restore];
}

static void checkConcurrentRecoveryWinner(void) {
    RecoveryFixture *fixture = [RecoveryFixture new];
    SGSetInt(SGKeyLyricsAskMode, 2);
    SGLyricsSetOrder(@[@"musixmatch", @"netease", @"unison"]);
    NSString *track = NSUUID.UUID.UUIDString;
    SGLyricsPlaybackChanged(track);
    SGKaraokeRequestLyrics(track);
    pumpUntil(^BOOL { return fixture.held[[track stringByAppendingString:@"unison"]] != nil; });
    [fixture reply:@"musixmatch" track:track result:madeUpLyrics(@"Lines", SGKaraokeTimingLine) failed:NO];
    [fixture reply:@"netease" track:track result:nil failed:YES];
    [fixture reply:@"unison" track:track result:nil failed:YES];
    [fixture advance];
    [fixture reply:@"unison" track:track result:madeUpLyrics(@"First recovery words", SGKaraokeTimingWords) failed:NO];
    CHECK([recoveryDisk(track)[@"text"] isEqual:@"First recovery words"]);
    [fixture reply:@"netease" track:track result:madeUpLyrics(@"Later priority words", SGKaraokeTimingWords) failed:NO];
    CHECK([SGKaraokeLineText(SGKaraokeLinesForTrack(track).firstObject) isEqual:@"First recovery words"]);
    CHECK([recoveryDisk(track)[@"text"] isEqual:@"First recovery words"]);
    SGKaraokeForgetLyrics(track);
    [fixture restore];
}

static void checkFailedPinRecovery(void) {
    RecoveryFixture *fixture = [RecoveryFixture new];
    SGSetInt(SGKeyLyricsAskMode, 0);
    SGLyricsSetOrder(@[@"musixmatch"]);
    NSString *track = NSUUID.UUID.UUIDString;
    SGLyricsPlaybackChanged(track);
    CHECK(SGLyricsPin(track, @{@"id": @449, @"syncedLyrics": @"[00:01]Pin"}));
    sg_pinnedReply = nil;
    SGLyricsReload(track);
    pumpUntil(^BOOL { return sg_pinnedReply != nil; });
    [sg_pinnedContext noteFailure:YES];
    sg_pinnedReply(nil);
    [fixture reply:@"musixmatch" track:track result:madeUpLyrics(@"Pin fallback", SGKaraokeTimingLine) failed:NO];
    CHECK(!recoveryDisk(track));
    [fixture advance];
    sg_pinnedReply(SGLrcLibRecordResult(@{@"syncedLyrics": @"[00:01]Pin recovered"}));
    CHECK([SGKaraokeLineText(SGKaraokeLinesForTrack(track).firstObject) isEqual:@"Pin fallback"]);
    CHECK([recoveryDisk(track)[@"text"] isEqual:@"Pin recovered"]);
    SGLyricsPlaybackChanged(nil);
    CHECK([SGKaraokeLineText(SGKaraokeLinesForTrack(track).firstObject) isEqual:@"Pin recovered"]);
    SGKaraokeForgetLyrics(track);
    [fixture restore];
}

static void checkFailedUntimedPick(void) {
    RecoveryFixture *fixture = [RecoveryFixture new];
    SGSetInt(SGKeyLyricsAskMode, 0);
    SGLyricsSetOrder(@[@"musixmatch", @"genius"]);
    NSString *track = NSUUID.UUID.UUIDString;
    SGLyricsPlaybackChanged(track);
    SGLyricsAskOffers(track);
    [fixture reply:@"musixmatch" track:track result:madeUpLyrics(@"Offer", SGKaraokeTimingWords) failed:NO];
    [fixture reply:@"genius" track:track result:madeUpLyrics(@"Chosen plain", SGKaraokeTimingNone) failed:NO];
    SGLyricsChooseSource(track, @"genius");
    SGKaraokeForgetLyrics(track);
    SGKaraokeRequestLyrics(track);
    pumpUntil(^BOOL { return fixture.held[[track stringByAppendingString:@"genius"]] != nil; });
    [fixture reply:@"genius" track:track result:nil failed:YES];
    [fixture reply:@"musixmatch" track:track result:madeUpLyrics(@"Word fallback", SGKaraokeTimingWords) failed:NO];
    CHECK(!recoveryDisk(track));
    [fixture advance];
    [fixture reply:@"genius" track:track result:madeUpLyrics(@"Recovered pick", SGKaraokeTimingNone) failed:NO];
    CHECK([SGKaraokeLineText(SGKaraokeLinesForTrack(track).firstObject) isEqual:@"Word fallback"]);
    CHECK([recoveryDisk(track)[@"text"] isEqual:@"Recovered pick"]);
    SGLyricsPlaybackChanged(nil);
    CHECK([(SGLyricsResult *)SGLyricsKeptAnswer(track) picked]);
    CHECK([SGKaraokeLineText(SGKaraokeLinesForTrack(track).firstObject) isEqual:@"Recovered pick"]);
    SGKaraokeForgetLyrics(track);
    [fixture restore];
}

static void checkRecoveryReentrantRetirement(void) {
    RecoveryFixture *fixture = [RecoveryFixture new];
    SGSetInt(SGKeyLyricsAskMode, 0);
    SGLyricsSetOrder(@[@"musixmatch", @"netease"]);
    NSString *track = NSUUID.UUID.UUIDString;
    SGLyricsPlaybackChanged(track);
    SGKaraokeRequestLyrics(track);
    pumpUntil(^BOOL { return fixture.held[[track stringByAppendingString:@"musixmatch"]] != nil; });
    [fixture reply:@"musixmatch" track:track result:nil failed:YES];
    [fixture reply:@"netease" track:track result:madeUpLyrics(@"Before", SGKaraokeTimingLine) failed:NO];
    [fixture advance];
    __block BOOL reloaded = NO;
    id observer = [NSNotificationCenter.defaultCenter addObserverForName:SGKaraokeLinesKeptNotification object:track queue:nil usingBlock:^(NSNotification *note) {
        if (!reloaded && [SGLyricsCreditFor(track) isEqual:@"Retired"]) {
            reloaded = YES;
            SGLyricsReload(track);
        }
    }];
    [fixture reply:@"musixmatch" track:track result:madeUpLyrics(@"Retired", SGKaraokeTimingWords) failed:NO];
    CHECK(reloaded && !SGKaraokeLinesForTrack(track) && !recoveryDisk(track));
    [NSNotificationCenter.defaultCenter removeObserver:observer];
    SGKaraokeForgetLyrics(track);
    [fixture restore];
}

static void checkRecoveryRetirement(void) {
    RecoveryFixture *fixture = [RecoveryFixture new];
    SGSetInt(SGKeyLyricsAskMode, 0);
    SGLyricsSetOrder(@[@"musixmatch", @"netease"]);
    for (NSString *action in @[@"pin", @"unpin", @"reload", @"forget", @"evict", @"pick", @"automatic", @"newer"]) {
        NSString *track = NSUUID.UUID.UUIDString;
        SGLyricsPlaybackChanged(track);
        SGKaraokeRequestLyrics(track);
        pumpUntil(^BOOL { return fixture.held[[track stringByAppendingString:@"musixmatch"]] != nil; });
        [fixture reply:@"musixmatch" track:track result:nil failed:YES];
        [fixture reply:@"netease" track:track result:madeUpLyrics(@"Before", SGKaraokeTimingLine) failed:NO];
        [fixture advance];
        void (^late)(SGLyricsResult *, BOOL) = fixture.held[[track stringByAppendingString:@"musixmatch"]];
        CHECK(late);
        [fixture.held removeObjectForKey:[track stringByAppendingString:@"musixmatch"]];
        if ([action isEqual:@"pin"] || [action isEqual:@"unpin"]) {
            CHECK(SGLyricsPin(track, @{@"id": @443, @"syncedLyrics": @"[00:01]Pinned"}));
            if ([action isEqual:@"unpin"]) SGLyricsUnpin(track);
        } else if ([action isEqual:@"reload"]) SGLyricsReload(track);
        else if ([action isEqual:@"forget"]) SGKaraokeForgetLyrics(track);
        else if ([action isEqual:@"evict"]) {
            for (NSUInteger i = 0; i < 41; i++) SGKaraokeKeepLines(NSUUID.UUID.UUIDString, @[]);
        } else if ([action isEqual:@"newer"]) {
            SGLyricsRestoreKept(track, nil);
            SGKaraokeRequestLyrics(track);
        } else {
            SGLyricsAskOffers(track);
            [fixture reply:@"musixmatch" track:track result:madeUpLyrics(@"Offer", SGKaraokeTimingLine) failed:NO];
            [fixture reply:@"netease" track:track result:madeUpLyrics(@"Chosen", SGKaraokeTimingLine) failed:NO];
            SGLyricsChooseSource(track, @"netease");
            if ([action isEqual:@"automatic"]) SGLyricsChooseAutomatic(track);
        }
        NSArray *before = SGKaraokeLinesForTrack(track);
        NSString *credit = SGLyricsCreditFor(track);
        late(madeUpLyrics(@"Stale recovery", SGKaraokeTimingWords), NO);
        drainReplies();
        if ([action isEqual:@"evict"]) {
            // Capacity eviction is not retirement: the better provider still wins and persists.
            CHECK([SGKaraokeLineText(SGKaraokeLinesForTrack(track).firstObject) isEqual:@"Stale recovery"]);
            CHECK([recoveryDisk(track)[@"text"] isEqual:@"Stale recovery"]);
        } else {
            CHECK(SGKaraokeLinesForTrack(track) == before);
            CHECK(SGLyricsCreditFor(track) == credit || [SGLyricsCreditFor(track) isEqual:credit]);
            CHECK(![recoveryDisk(track)[@"text"] isEqual:@"Stale recovery"]);
        }
        SGKaraokeForgetLyrics(track);
        [fixture.held removeAllObjects];
        [sg_recoveryClocks removeAllObjects];
    }
    [fixture restore];
}

static void checkRecoveryWithSpotify(void) {
    RecoveryFixture *fixture = [RecoveryFixture new];
    NSUInteger oldAsks = sg_spotifyAsks;
    NSDictionary *headers = sg_spclientHeaders; sg_spclientHeaders = @{};
    NSInteger oldStatus = sg_spotifyStatus; sg_spotifyStatus = 200;
    Method method = class_getInstanceMethod(NSURLSession.class, @selector(dataTaskWithRequest:completionHandler:));
    IMP original = method_setImplementation(method, (IMP)spotifyMiss);
    SGSetInt(SGKeyLyricsAskMode, 0);
    SGLyricsSetOrder(@[@"musixmatch", @"netease"]);
    for (NSNumber *tier in @[@(SGKaraokeTimingLine), @(SGKaraokeTimingWords)]) {
        NSString *track = fixtureTrackID();
        SGLyricsPlaybackChanged(track);
        sg_spotifyBody = pageBody(madeUpLyrics(@"Spotify sheet", SGKaraokeTimingLine), nil);
        SGKaraokeRequestLyrics(track);
        pumpUntil(^BOOL { return fixture.held[[track stringByAppendingString:@"musixmatch"]] != nil; });
        [fixture reply:@"musixmatch" track:track result:nil failed:YES];
        [fixture reply:@"netease" track:track result:madeUpLyrics(@"Plain fallback", SGKaraokeTimingNone) failed:NO];
        pumpUntil(^BOOL { return [SGLyricsCreditFor(track) isEqual:@"Spotify"]; });
        CHECK(!recoveryDisk(track) && SGLyricsRecovering(track));
        [fixture advance];
        [fixture reply:@"musixmatch" track:track result:madeUpLyrics(@"Recovered source", tier.integerValue) failed:NO];
        NSString *shown = tier.integerValue == SGKaraokeTimingWords ? @"Recovered source" : @"Spotify sheet";
        CHECK([SGKaraokeLineText(SGKaraokeLinesForTrack(track).firstObject) isEqual:shown]);
        CHECK([recoveryDisk(track)[@"text"] isEqual:@"Recovered source"]);
        SGKaraokeForgetLyrics(track);
    }
    method_setImplementation(method, original);
    sg_spclientHeaders = headers; sg_spotifyStatus = oldStatus; sg_spotifyBody = nil; sg_spotifyAsks = oldAsks;
    [fixture restore];
}

static void checkWordWinnerRecovery(void) {
    RecoveryFixture *fixture = [RecoveryFixture new];
    SGLyricsSetOrder(@[@"musixmatch", @"netease"]);
    for (NSUInteger policy = 0; policy < 3; policy++) {
        SGSetInt(SGKeyLyricsAskMode, policy == 2 ? 0 : policy);
        SGSetEnabled(SGKeyLyricsPreferWordTiming, policy == 2);
        NSString *track = NSUUID.UUID.UUIDString;
        SGLyricsPlaybackChanged(track);
        SGKaraokeRequestLyrics(track);
        pumpUntil(^BOOL { return fixture.held[[track stringByAppendingString:@"musixmatch"]] != nil; });
        [fixture reply:@"musixmatch" track:track result:nil failed:YES];
        [fixture reply:@"netease" track:track result:madeUpLyrics(@"First words", SGKaraokeTimingWords) failed:NO];
        CHECK(!recoveryDisk(track));
        [fixture advance];
        [fixture reply:@"musixmatch" track:track result:madeUpLyrics(@"Priority words", SGKaraokeTimingWords) failed:NO];
        CHECK([SGKaraokeLineText(SGKaraokeLinesForTrack(track).firstObject) isEqual:@"First words"]);
        CHECK([recoveryDisk(track)[@"text"] isEqual:@"Priority words"]);
        // A late community translation of the old display must not overwrite the pending winner.
        sg_testTranslations = YES;
        SGSetInt(SGKeyLyricsTranslationLanguage, 18);
        translate(track);
        CHECK(sg_translationReply);
        SGKaraokeLine *translated = [SGKaraokeLinesForTrack(track).firstObject copy];
        translated.translation = @"이전 가사";
        sg_translatedLines = @[translated];
        sg_translationReply(@{@"First words": @"이전 가사"});
        CHECK([SGKaraokeLinesForTrack(track).firstObject.translation isEqual:@"이전 가사"]);
        CHECK([recoveryDisk(track)[@"text"] isEqual:@"Priority words"]);
        sg_testTranslations = NO; sg_translatedLines = nil; sg_translationReply = nil;
        SGSetInt(SGKeyLyricsTranslationLanguage, 0);
        SGKaraokeForgetLyrics(track);
    }
    [fixture restore];
}

static void checkLateDonorSheetIdentity(void) {
    RecoveryFixture *fixture = [RecoveryFixture new];
    SGSetInt(SGKeyLyricsAskMode, 1);
    SGLyricsSetOrder(@[@"musixmatch", @"netease"]);
    NSString *track = NSUUID.UUID.UUIDString;
    SGLyricsPlaybackChanged(track);
    SGKaraokeRequestLyrics(track);
    pumpUntil(^BOOL { return fixture.held[[track stringByAppendingString:@"musixmatch"]] != nil; });
    [fixture reply:@"musixmatch" track:track result:nil failed:YES];
    [fixture reply:@"netease" track:track result:madeUpLyrics(@"Early donor", SGKaraokeTimingLine) failed:NO];
    __block SGLyricsResult *early;
    SGLyricsFetch(track, ^(SGLyricsResult *result) { early = result; });
    pumpUntil(^BOOL { return early != nil; });
    SGLyricsTaskState *donor = [SGLyricsTaskState new];
    donor.kind = SGLyricsTaskDonor; donor.track = track; donor.chain = early;
    donor.pinGeneration = SGLyricsPinGeneration(track);
    [fixture advance];
    [fixture reply:@"musixmatch" track:track result:madeUpLyrics(@"Recovered words", SGKaraokeTimingWords) failed:NO];
    CHECK([recoveryDisk(track)[@"text"] isEqual:@"Recovered words"]);
    HarnessDelegate *delegate = [HarnessDelegate new];
    __block BOOL ended = NO;
    finishDonor(delegate, nil, nil, donor, nil, nil, ^(NSError *error) { ended = YES; });
    CHECK(ended);
    NSDictionary *afterDonor = recoveryDisk(track);
    CHECK([afterDonor[@"text"] isEqual:@"Recovered words"]);
    CHECK([SGKaraokeLineText(SGKaraokeLinesForTrack(track).firstObject) isEqual:@"Recovered words"]);
    CHECK([SGLyricsCreditFor(track) isEqual:@"Recovered words"]);
    SGKaraokeForgetLyrics(track);
    [fixture restore];
}

static void checkEvictedSheetAuthority(void) {
    RecoveryFixture *fixture = [RecoveryFixture new];
    SGSetInt(SGKeyLyricsAskMode, 0);
    SGLyricsSetOrder(@[@"musixmatch", @"netease"]);
    NSInteger language = SGInt(SGKeyLyricsTranslationLanguage, 0);
    for (NSNumber *pending in @[@NO, @YES]) {
        NSString *track = NSUUID.UUID.UUIDString;
        SGLyricsPlaybackChanged(track);
        SGKaraokeRequestLyrics(track);
        pumpUntil(^BOOL { return fixture.held[[track stringByAppendingString:@"musixmatch"]] != nil; });
        [fixture reply:@"musixmatch" track:track result:nil failed:YES];
        [fixture reply:@"netease" track:track result:madeUpLyrics(@"Retained display", SGKaraokeTimingLine) failed:NO];
        if (pending.boolValue) {
            [fixture advance];
            [fixture reply:@"musixmatch" track:track result:madeUpLyrics(@"Pending disk winner", SGKaraokeTimingLine) failed:NO];
            CHECK([recoveryDisk(track)[@"text"] isEqual:@"Pending disk winner"]);
        }
        for (NSUInteger i = 0; i < 41; i++)
            SGLyricsKeepChosen(NSUUID.UUID.UUIDString, madeUpLyrics(@"Other track", SGKaraokeTimingLine));
        CHECK(!SGLyricsKeptAnswer(track) && SGKaraokeLinesForTrack(track).count);
        SGKaraokeTrackWatcher *watcher = [SGKaraokeTrackWatcher new];
        SGSetInt(SGKeyLyricsTranslationLanguage, language == 7 ? 18 : 7);
        [watcher defaultsChanged:nil];
        drainReplies();
        NSDictionary *disk = recoveryDisk(track);
        BOOL preservedSelection = pending.boolValue ? [disk[@"text"] isEqual:@"Pending disk winner"] : disk == nil;
        CHECK(preservedSelection);
        [NSNotificationCenter.defaultCenter removeObserver:watcher];
        SGSetInt(SGKeyLyricsTranslationLanguage, language);
        SGKaraokeForgetLyrics(track);
        [sg_recoveryClocks removeAllObjects];
    }
    [fixture restore];
}

static void checkRecoveryNamesDeferredSources(void) {
    RecoveryFixture *fixture = [RecoveryFixture new];
    for (NSNumber *mode in @[@1, @2]) {
        SGSetInt(SGKeyLyricsAskMode, mode.integerValue);
        SGLyricsSetOrder(@[SGSpicyLyricsKey, @"musixmatch", @"netease", @"unison"]);
        NSString *track = NSUUID.UUID.UUIDString;
        SGLyricsPlaybackChanged(track);
        SGLyricsQuery *query = [SGLyricsQuery new]; query.trackID = track;
        sg_waiting[track] = [NSMutableArray arrayWithObject:[^(SGLyricsResult *answer) {
            CHECK(SGKaraokeKeepSourceLines(track, answer.karaokeLines, answer));
        } copy]];
        startWalk(track, query);
        [fixture reply:SGSpicyLyricsKey track:track result:madeUpLyrics(@"Nameless fallback", SGKaraokeTimingLine) failed:NO];
        [fixture reply:@"musixmatch" track:track result:nil failed:YES];
        [fixture advance];
        SGLyricsResult *name = [SGLyricsResult new]; name.title = @"Recovered title"; name.artist = @"Recovered artist";
        [fixture reply:@"musixmatch" track:track result:name failed:NO];
        BOOL newlyEligible = fixture.held[[track stringByAppendingString:@"netease"]] != nil;
        CHECK(newlyEligible);
        if (getenv("RETRINE_PRESSURE_ONLY"))
            for (NSUInteger i = 0; i <= kKeptTracks; i++) SGKaraokeKeepLines(NSUUID.UUID.UUIDString, @[]);
        CHECK(!recoveryDisk(track));
        [fixture reply:@"netease" track:track result:madeUpLyrics(@"Named word winner", SGKaraokeTimingWords) failed:NO];
        CHECK([recoveryDisk(track)[@"text"] isEqual:@"Named word winner"]);
        CHECK([SGKaraokeLineText(SGKaraokeLinesForTrack(track).firstObject) isEqual:@"Named word winner"]);
        SGKaraokeForgetLyrics(track);
        [fixture.held removeAllObjects];
        [sg_recoveryClocks removeAllObjects];
    }
    [fixture restore];
}

static void checkSpotifySurvivesRecoveryMiss(void) {
    RecoveryFixture *fixture = [RecoveryFixture new];
    NSDictionary *headers = sg_spclientHeaders; sg_spclientHeaders = @{};
    NSUInteger asks = sg_spotifyAsks;
    NSInteger status = sg_spotifyStatus; sg_spotifyStatus = 200;
    Method method = class_getInstanceMethod(NSURLSession.class, @selector(dataTaskWithRequest:completionHandler:));
    IMP original = method_setImplementation(method, (IMP)spotifyMiss);
    SGSetInt(SGKeyLyricsAskMode, 0);
    SGLyricsSetOrder(@[@"musixmatch", @"netease"]);
    NSString *track = fixtureTrackID();
    SGLyricsPlaybackChanged(track);
    sg_spotifyBody = pageBody(madeUpLyrics(@"Spotify timed winner", SGKaraokeTimingLine), nil);
    SGKaraokeRequestLyrics(track);
    pumpUntil(^BOOL { return fixture.held[[track stringByAppendingString:@"musixmatch"]] != nil; });
    [fixture reply:@"musixmatch" track:track result:nil failed:YES];
    [fixture reply:@"netease" track:track result:madeUpLyrics(@"Plain fallback", SGKaraokeTimingNone) failed:NO];
    pumpUntil(^BOOL { return [SGLyricsCreditFor(track) isEqual:@"Spotify"]; });
    CHECK(!recoveryDisk(track));
    [fixture advance];
    [fixture reply:@"musixmatch" track:track result:nil failed:NO];
    NSDictionary *afterMiss = recoveryDisk(track);
    CHECK([afterMiss[@"text"] isEqual:@"Spotify timed winner"]);
    SGLyricsPlaybackChanged(nil);
    SGLyricsPlaybackChanged(track);
    CHECK([SGKaraokeLineText(SGKaraokeLinesForTrack(track).firstObject) isEqual:@"Spotify timed winner"]);
    CHECK([SGLyricsCreditFor(track) isEqual:@"Spotify"]);
    CHECK([recoveryDisk(track)[@"credit"] isEqual:@"Spotify"]);
    SGKaraokeForgetLyrics(track);
    method_setImplementation(method, original);
    sg_spclientHeaders = headers; sg_spotifyStatus = status; sg_spotifyAsks = asks; sg_spotifyBody = nil;
    [fixture restore];
}

static void checkUntimedFailureSuppliesPage(void) {
    RecoveryFixture *fixture = [RecoveryFixture new];
    SGSetInt(SGKeyLyricsAskMode, 0);
    SGLyricsSetOrder(@[@"genius", @"netease"]);
    NSString *track = NSUUID.UUID.UUIDString;
    SGLyricsPlaybackChanged(track);
    SGKaraokeRequestLyrics(track);
    pumpUntil(^BOOL { return fixture.held[[track stringByAppendingString:@"genius"]] != nil; });
    [fixture reply:@"genius" track:track result:nil failed:YES];
    SGLyricsResult *words = madeUpLyrics(@"Words without page", SGKaraokeTimingWords);
    words.texts = nil; words.starts = nil;
    [fixture reply:@"netease" track:track result:words failed:NO];
    NSDictionary *pageFailureDisk = recoveryDisk(track);
    CHECK(!pageFailureDisk);
    [fixture advance];
    [fixture reply:@"genius" track:track result:madeUpLyrics(@"Recovered page", SGKaraokeTimingNone) failed:NO];
    CHECK([recoveryDisk(track)[@"text"] isEqual:@"Words without page"]);
    SGLyricsPlaybackChanged(nil);
    __block SGLyricsResult *final;
    SGLyricsFetch(track, ^(SGLyricsResult *answer) { final = answer; });
    pumpUntil(^BOOL { return final != nil; });
    CHECK([final.provider isEqual:@"Words without page"] && [final.pageProvider isEqual:@"Recovered page"]);
    CHECK([final.texts containsObject:@"Recovered page"]);
    SGKaraokeForgetLyrics(track);
    [fixture restore];
}

static void checkAskModeMigration(void) {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSArray *expected = @[SGImportedLRCKey, SGSpicyLyricsKey, @"binilyrics", @"lyricsplus",
        @"musixmatch", @"unison", @"deezer", @"netease", @"petitlyrics", @"lrclib", @"bugs", @"genie", @"qqmusic", @"kugou", @"genius"];
    CHECK([SGLyricsOrder() isEqual:expected]);
    // Simulate a saved order from before catalog tracking, without restoring disabled sources.
    [defaults setObject:@[@"musixmatch", @"lrclib", @"genius"] forKey:SGKeyLyricsProviders];
    [defaults removeObjectForKey:SGKeyLyricsKnownProviders];
    NSArray *migrated = @[@"musixmatch", @"petitlyrics", @"lrclib", @"genius"];
    CHECK([SGLyricsOrder() isEqual:migrated]);
    CHECK([[defaults arrayForKey:SGKeyLyricsProviders] isEqual:migrated]);
    CHECK([SGLyricsOrder() isEqual:migrated]);
    SGLyricsSetOrder(@[@"musixmatch", @"lrclib", @"genius"]);
    CHECK([SGLyricsOrder() isEqual:(@[@"musixmatch", @"lrclib", @"genius"])]);
    [defaults setObject:@[] forKey:SGKeyLyricsProviders];
    [defaults removeObjectForKey:SGKeyLyricsKnownProviders];
    CHECK(SGLyricsOrder().count == 0);
    CHECK([[defaults arrayForKey:SGKeyLyricsKnownProviders] containsObject:@"petitlyrics"]);
    // Exercise both early returns in the migration, and a pre-existing new preference.
    for (NSArray *stored in @[@[], @[@"unison"]]) {
        SGLyricsSetOrder(stored);
        for (id old in @[@NO, @YES, NSNull.null]) {
            [defaults removeObjectForKey:SGKeyLyricsAskMode];
            [defaults removeObjectForKey:SGKeyLyricsTypeFirst];
            if (old != NSNull.null) [defaults setObject:old forKey:SGKeyLyricsTypeFirst];
            SGLyricsMigrateLegacyKeys();
            CHECK(SGInt(SGKeyLyricsAskMode, 1) == (old == NSNull.null ? 1 : [old integerValue]));
            CHECK([SGLyricsOrder() isEqual:stored]);
            SGSetInt(SGKeyLyricsAskMode, 2);
            [defaults setObject:@NO forKey:SGKeyLyricsTypeFirst];
            SGLyricsMigrateLegacyKeys();
            CHECK(SGInt(SGKeyLyricsAskMode, 1) == 2);
        }
    }
    [defaults removeObjectForKey:SGKeyLyricsProviders];
    [defaults removeObjectForKey:SGKeyLyricsAskMode];
    [defaults setObject:@YES forKey:SGKeyLyricsTypeFirst];
    SGLyricsMigrateLegacyKeys();
    CHECK(SGInt(SGKeyLyricsAskMode, 1) == 1 && [SGLyricsOrder() isEqual:expected]);
    [defaults removeObjectForKey:SGKeyLyricsAskMode];
    [defaults removeObjectForKey:SGKeyLyricsTypeFirst];
    [defaults setObject:@YES forKey:kLegacyMusixmatch];
    [defaults setObject:@YES forKey:kLegacyNetEase];
    SGLyricsMigrateLegacyKeys();
    CHECK([SGLyricsOrder() isEqual:(@[@"musixmatch", @"netease"])]);
    CHECK(SGInt(SGKeyLyricsAskMode, 1) == 1);
    [defaults removeObjectForKey:kLegacyMusixmatch];
    [defaults removeObjectForKey:kLegacyNetEase];
    [defaults removeObjectForKey:SGKeyLyricsProviders];
    SGSetInt(SGKeyLyricsAskMode, 0);
    printf("ask mode: old NO/YES/unset, existing new value, stored and legacy orders, default priority passed\n");
}

static void checkConcurrentWalk(void) {
    NSArray<NSString *> *keys = @[@"musixmatch", @"netease", @"unison"];
    NSArray<NSString *> *all = [keys arrayByAddingObject:SGImportedLRCKey];
    NSMutableArray *saved = [NSMutableArray array], *asked = [NSMutableArray array];
    NSMutableDictionary *pending = [NSMutableDictionary dictionary], *sync = [NSMutableDictionary dictionary];
    NSMutableDictionary *contexts = [NSMutableDictionary dictionary];
    for (NSString *key in all) {
        SGLyricsProvider *provider = SGLyricsProviderFor(key);
        [saved addObject:(id)provider.ask ?: NSNull.null];
        provider.ask = ^(SGLyricsQuery *query, void (^done)(SGLyricsResult *)) {
            contexts[key] = query.requestContext;
            [asked addObject:key];
            id reply = sync[key];
            if (reply) done(reply == NSNull.null ? nil : reply);
            else pending[key] = [done copy];
        };
    }
    SGSetInt(SGKeyLyricsAskMode, 2);
    void (^reset)(void) = ^{
        [asked removeAllObjects]; [pending removeAllObjects]; [sync removeAllObjects];
        [NSUserDefaults.standardUserDefaults removeObjectForKey:SGKeyLyricsSourceTypes];
        SGLyricsSetOrder(keys);
    };
    void (^reply)(NSString *, SGLyricsResult *) = ^(NSString *key, SGLyricsResult *result) {
        void (^done)(SGLyricsResult *) = pending[key];
        CHECK(done != nil);
        [pending removeObjectForKey:key];
        done(result);
        drainReplies();
    };

    // Prefetch, foreground fetches, the keeper and color-lyrics share one set of asks.
    reset();
    NSString *track = NSUUID.UUID.UUIDString;
    __block NSUInteger deliveries = 0, hookEnds = 0;
    SGLyricsPrefetch(track);
    for (NSUInteger i = 0; i < 2; i++) SGLyricsFetch(track, ^(SGLyricsResult *result) {
        CHECK([result.provider isEqual:@"First lines"]); deliveries++;
    });
    SGKaraokeRequestLyrics(track);
    HarnessDelegate *delegate = [HarnessDelegate new];
    SGLyricsTaskState *state = [SGLyricsTaskState new];
    state.track = track; state.pinGeneration = SGLyricsPinGeneration(track);
    SGLyricsResult *line = madeUpLyrics(@"First lines", SGKaraokeTimingLine);
    finishSpotify(delegate, nil, nil, state, pageBody(line, nil), nil, ^(NSError *error) {
        CHECK(!error); hookEnds++;
    });
    pumpUntil(^BOOL { return pending.count == keys.count && sg_waiting[track].count == 5; });
    CHECK([asked isEqual:keys] && !deliveries && !hookEnds);
    reply(keys[0], line);
    CHECK(deliveries == 2 && hookEnds == 1 && delegate.deliveries == 1);
    CHECK(sg_waiting[track] && !sg_waiting[track].count);
    CHECK(SGKaraokeLinesTiming(SGKaraokeLinesForTrack(track)) == SGKaraokeTimingLine);
    CHECK([SGLyricsCreditFor(track) isEqual:@"First lines"]);
    SGLyricsResult *words = madeUpLyrics(@"Low-ranked words", SGKaraokeTimingWords);
    words.wordTimed = NO; // Timing comes from the lines, not the provider's flag.
    reply(keys[2], words);
    CHECK(!sg_waiting[track] && [((SGLyricsResult *)sg_kept[track]).provider isEqual:words.provider]);
    CHECK([SGKaraokeLinesForTrack(track) isEqual:words.karaokeLines] && [SGLyricsCreditFor(track) isEqual:words.provider]);
    reply(keys[1], madeUpLyrics(@"Higher-ranked late words", SGKaraokeTimingWords));
    CHECK([SGKaraokeLinesForTrack(track) isEqual:words.karaokeLines] && [SGLyricsCreditFor(track) isEqual:words.provider]);
    CHECK(deliveries == 2 && hookEnds == 1 && delegate.deliveries == 1);

    // Synchronous callbacks still cannot settle the walk before every eligible ask starts.
    reset();
    sync[keys[0]] = madeUpLyrics(@"Synchronous words", SGKaraokeTimingWords);
    sync[keys[1]] = NSNull.null; sync[keys[2]] = NSNull.null;
    track = NSUUID.UUID.UUIDString;
    __block SGLyricsResult *answer;
    SGLyricsFetch(track, ^(SGLyricsResult *result) {
        CHECK([asked isEqual:keys]); answer = result;
    });
    pumpUntil(^BOOL { return answer != nil; });
    CHECK([answer.provider isEqual:@"Synchronous words"] && !sg_waiting[track]);
    drainReplies();

    // Equal-quality lines and plain text keep priority, not arrival order, for both outputs.
    for (NSNumber *quality in @[@(SGKaraokeTimingLine), @(SGKaraokeTimingNone)]) {
        reset(); track = NSUUID.UUID.UUIDString; answer = nil; deliveries = 0;
        SGLyricsFetch(track, ^(SGLyricsResult *result) { answer = result; deliveries++; });
        pumpUntil(^BOOL { return pending.count == keys.count; });
        SGKaraokeTiming timing = quality.integerValue;
        reply(keys[2], madeUpLyrics(@"Third", timing));
        reply(keys[1], madeUpLyrics(@"Second", timing));
        reply(keys[0], madeUpLyrics(@"First", timing));
        CHECK(deliveries == 1);
        NSString *firstDelivery = timing == SGKaraokeTimingLine ? @"Third" : @"First";
        CHECK([answer.provider isEqual:firstDelivery] && [answer.pageProvider isEqual:firstDelivery]);
        SGLyricsResult *selected = SGLyricsKeptAnswer(track);
        CHECK([SGKaraokeLineText(selected.karaokeLines.firstObject) isEqual:@"First"] && [selected.texts.firstObject isEqual:@"First"]);
        CHECK(!sg_waiting[track]);
    }

    // A word-only answer locks the lines, but remains open for another source's page text.
    reset(); track = NSUUID.UUID.UUIDString; answer = nil;
    SGLyricsFetch(track, ^(SGLyricsResult *result) { answer = result; });
    pumpUntil(^BOOL { return pending.count == keys.count; });
    words = madeUpLyrics(@"Word-only winner", SGKaraokeTimingWords);
    words.texts = nil; words.starts = nil;
    reply(keys[2], words);
    CHECK(!answer && sg_waiting[track]);
    SGLyricsResult *higherWords = madeUpLyrics(@"Higher word-only", SGKaraokeTimingWords);
    higherWords.texts = nil; higherWords.starts = nil;
    reply(keys[0], higherWords);
    CHECK(!answer && sg_waiting[track]);
    reply(keys[1], madeUpLyrics(@"Page lines", SGKaraokeTimingLine));
    CHECK(answer.karaokeLines == words.karaokeLines && [answer.provider isEqual:words.provider]);
    CHECK([answer.pageProvider isEqual:@"Page lines"] && answer.synced && !sg_waiting[track]);

    // Line and page decisions must both be computed before replacing either half.
    reset(); track = NSUUID.UUID.UUIDString; answer = nil;
    SGLyricsFetch(track, ^(SGLyricsResult *result) { answer = result; });
    pumpUntil(^BOOL { return pending.count == keys.count; });
    SGLyricsResult *onlyLines = madeUpLyrics(@"Best lines", SGKaraokeTimingLine);
    onlyLines.texts = nil; onlyLines.starts = nil;
    reply(keys[0], onlyLines);
    reply(keys[2], madeUpLyrics(@"Low page", SGKaraokeTimingLine));
    reply(keys[1], madeUpLyrics(@"Better page", SGKaraokeTimingLine));
    CHECK([answer.provider isEqual:@"Best lines"] && [answer.pageProvider isEqual:@"Low page"]);
    CHECK([[(SGLyricsResult *)SGLyricsKeptAnswer(track) pageProvider] isEqual:@"Better page"]);

    // Learn even from a filtered answer, then launch each deferred source exactly once.
    reset(); SGLyricsSetOrder(@[keys[1], keys[0], keys[2]]);
    SGLyricsSetSourceTypes(keys[0], SGLyricsTypesWords);
    SGLyricsQuery *query = [SGLyricsQuery new]; query.trackID = NSUUID.UUID.UUIDString;
    track = query.trackID; answer = nil;
    sg_waiting[track] = [NSMutableArray arrayWithObject:[^(SGLyricsResult *result) { answer = result; } copy]];
    startWalk(track, query);
    CHECK([asked isEqual:(@[keys[0]])]);
    SGLyricsResult *filtered = madeUpLyrics(@"Rejected naming reply", SGKaraokeTimingLine);
    filtered.title = @"Song"; filtered.artist = @"Singer";
    reply(keys[0], filtered);
    CHECK([asked isEqual:(@[keys[0], keys[1], keys[2]])] && !answer);
    reply(keys[2], madeUpLyrics(@"Deferred lines", SGKaraokeTimingLine));
    reply(keys[1], nil);
    CHECK([answer.provider isEqual:@"Deferred lines"] && asked.count == 3 && !sg_waiting[track]);

    // Exhaustion without a name, or during a failed request, must be retryable.
    for (NSNumber *failure in @[@NO, @YES]) {
        reset(); answer = nil; deliveries = 0;
        query = [SGLyricsQuery new]; query.trackID = NSUUID.UUID.UUIDString;
        if (failure.boolValue) { query.title = @"Song"; query.artist = @"Singer"; }
        track = query.trackID;
        sg_waiting[track] = [NSMutableArray arrayWithObject:[^(SGLyricsResult *result) {
            CHECK(!result); deliveries++;
        } copy]];
        startWalk(track, query);
        if (failure.boolValue) {
            [contexts[keys[0]] noteFailure:YES];
            reply(keys[1], nil); reply(keys[2], nil);
        }
        reply(keys[0], nil);
        CHECK(deliveries == 1 && !sg_waiting[track] && !sg_kept[track] && SGLyricsMayHave(track));
    }

    // Instrumental never wins over lyrics, regardless of arrival order; alone it waits for exhaustion.
    for (NSString *scenario in @[@"before", @"after", @"alone", @"miss", @"word-only"]) {
        reset(); track = NSUUID.UUID.UUIDString; answer = nil; deliveries = 0;
        SGLyricsFetch(track, ^(SGLyricsResult *result) { answer = result; deliveries++; });
        pumpUntil(^BOOL { return pending.count == keys.count; });
        SGLyricsResult *instrumental = [SGLyricsResult new]; instrumental.instrumental = YES;
        BOOL before = [scenario isEqual:@"before"], after = [scenario isEqual:@"after"];
        if (after) reply(keys[1], madeUpLyrics(@"Lyrics beat instrumental", SGKaraokeTimingLine));
        reply(keys[0], [scenario isEqual:@"miss"] || [scenario isEqual:@"word-only"] ? nil : instrumental);
        if (!after) CHECK(!deliveries && sg_waiting[track]);
        if (before) reply(keys[1], madeUpLyrics(@"Lyrics beat instrumental", SGKaraokeTimingLine));
        else if (!after) {
            SGLyricsResult *partial = nil;
            if ([scenario isEqual:@"word-only"]) {
                partial = madeUpLyrics(@"Words without a page", SGKaraokeTimingWords);
                partial.texts = nil; partial.starts = nil;
            }
            reply(keys[1], partial);
        }
        CHECK(sg_waiting[track]);
        reply(keys[2], nil);
        CHECK(deliveries == 1 && !sg_waiting[track]);
        if (before || after) CHECK(answer.karaokeLines.count && !answer.instrumental);
        else if ([scenario isEqual:@"alone"]) CHECK(answer.instrumental && !answer.karaokeLines.count);
        else if ([scenario isEqual:@"word-only"]) CHECK(answer.karaokeLines.count && !answer.texts.count);
        else CHECK(!answer && sg_kept[track] == NSNull.null && !SGLyricsMayHave(track));
    }

    // Imported LRC bypasses a stored type restriction, including a synchronous plain reply.
    reset(); SGLyricsSetOrder(@[SGImportedLRCKey]);
    [NSUserDefaults.standardUserDefaults setObject:@{SGImportedLRCKey: @(SGLyricsTypesWords)} forKey:SGKeyLyricsSourceTypes];
    sync[SGImportedLRCKey] = madeUpLyrics(@"Imported plain", SGKaraokeTimingNone);
    track = NSUUID.UUID.UUIDString; answer = nil;
    SGLyricsFetch(track, ^(SGLyricsResult *result) { answer = result; });
    pumpUntil(^BOOL { return answer != nil; });
    CHECK([answer.provider isEqual:@"Imported plain"] && asked.count == 1);

    // A resolved pin launches no providers. A missing pin enters the concurrent scheduler.
    for (NSNumber *success in @[@YES, @NO]) {
        reset(); track = NSUUID.UUID.UUIDString; answer = nil; sg_pinnedReply = nil;
        CHECK(SGLyricsPin(track, @{@"id": @902, @"syncedLyrics": @"[00:01]Pinned"}));
        SGLyricsResult *pinned = sg_kept[track];
        [sg_kept removeObjectForKey:track];
        SGLyricsFetch(track, ^(SGLyricsResult *result) { answer = result; });
        pumpUntil(^BOOL { return sg_pinnedReply != nil; });
        CHECK(!asked.count);
        sg_pinnedReply(success.boolValue ? pinned : nil);
        if (success.boolValue) CHECK([answer.karaokeLines isEqual:pinned.karaokeLines] && !asked.count && !sg_waiting[track]);
        else {
            CHECK([asked isEqual:keys] && !answer);
            reply(keys[2], madeUpLyrics(@"Pin fallback", SGKaraokeTimingWords));
            CHECK([answer.provider isEqual:@"Pin fallback"]);
            reply(keys[0], nil); reply(keys[1], nil);
        }
    }

    // Reload retires every outstanding reply; a waiter that pins also retires the scheduler,
    // even when the first reply already has word timing and would otherwise finish immediately.
    for (NSString *action in @[@"reload", @"pin-in-waiter", @"words-in-waiter"]) {
        reset(); track = NSUUID.UUID.UUIDString; deliveries = 0;
        NSString *retiringTrack = track;
        SGLyricsFetch(track, ^(SGLyricsResult *result) {
            deliveries++;
            if (![action isEqual:@"reload"]) {
                CHECK(SGLyricsPin(retiringTrack, @{@"id": @903, @"syncedLyrics": @"[00:01]Waiter pin"}));
            }
        });
        SGKaraokeRequestLyrics(track);
        pumpUntil(^BOOL { return pending.count == keys.count && sg_waiting[track].count == 2; });
        void (^late)(SGLyricsResult *) = pending[keys[2]];
        if ([action isEqual:@"reload"]) {
            NSMutableArray *oldWaiting = sg_waiting[track];
            SGLyricsReload(track);
            CHECK(sg_waiting[track] != oldWaiting);
            pumpUntil(^BOOL { return asked.count == 2 * keys.count; });
            late(madeUpLyrics(@"Retired words", SGKaraokeTimingWords)); drainReplies();
            CHECK(!sg_kept[track] && !SGKaraokeLinesForTrack(track) && !deliveries);
            reply(keys[1], madeUpLyrics(@"Reloaded winner", SGKaraokeTimingWords));
            CHECK(deliveries == 1 && [SGLyricsCreditFor(track) isEqual:@"Reloaded winner"]);
        } else {
            reply(keys[0], madeUpLyrics(@"Early answer",
                [action isEqual:@"words-in-waiter"] ? SGKaraokeTimingWords : SGKaraokeTimingLine));
            CHECK(deliveries == 1 && [SGLyricsCreditFor(track) isEqual:@"LRCLIB"]);
        }
        NSArray *kept = SGKaraokeLinesForTrack(track);
        late(madeUpLyrics(@"Late words", SGKaraokeTimingWords)); drainReplies();
        CHECK(SGKaraokeLinesForTrack(track) == kept && deliveries == 1 && !sg_waiting[track]);
    }

    // Upgrade publication can synchronously pin the track through a keeper observer.
    reset(); track = NSUUID.UUID.UUIDString; deliveries = 0;
    SGLyricsFetch(track, ^(SGLyricsResult *result) { deliveries++; });
    SGKaraokeRequestLyrics(track);
    pumpUntil(^BOOL { return pending.count == keys.count && sg_waiting[track].count == 2; });
    reply(keys[0], madeUpLyrics(@"Before observer", SGKaraokeTimingLine));
    CHECK(deliveries == 1);
    __block BOOL pinnedOnUpgrade = NO;
    NSString *observedTrack = track;
    id observer = [NSNotificationCenter.defaultCenter addObserverForName:SGKaraokeLinesKeptNotification
        object:track queue:nil usingBlock:^(NSNotification *note) {
        if (pinnedOnUpgrade) return;
        pinnedOnUpgrade = YES;
        CHECK(SGLyricsPin(observedTrack, @{@"id": @904, @"syncedLyrics": @"[00:01]Observer pin"}));
    }];
    reply(keys[2], madeUpLyrics(@"Upgrade that triggers pin", SGKaraokeTimingWords));
    [NSNotificationCenter.defaultCenter removeObserver:observer];
    reply(keys[1], madeUpLyrics(@"Retired observer reply", SGKaraokeTimingWords));
    CHECK(pinnedOnUpgrade && deliveries == 1 && !sg_waiting[track]);
    CHECK([SGLyricsCreditFor(track) isEqual:@"LRCLIB"]);
    CHECK([SGKaraokeLineText(SGKaraokeLinesForTrack(track).firstObject) isEqual:@"Observer pin"]);

    reset();
    NSUInteger index = 0;
    for (NSString *key in all) {
        id original = saved[index++]; SGLyricsProviderFor(key).ask = original == NSNull.null ? nil : original;
    }
    SGSetInt(SGKeyLyricsAskMode, 0);
    SGLyricsSetOrder(@[@"musixmatch"]);
    printf("all-at-once: launch, synchronous replies, coalescing, early delivery, ranked merges, first words, deferred naming, filters, exhaustion, pins and retirement passed\n");
}

static void checkWalkSelection(void) {
    NSArray *keys = @[@"musixmatch", @"netease", SGImportedLRCKey];
    NSMutableArray *saved = [NSMutableArray array], *asked = [NSMutableArray array];
    __block NSInteger pickedReply = 0; // 0: lyrics, 1: failed transport, 2: successful empty reply
    for (NSString *key in keys) {
        SGLyricsProvider *provider = SGLyricsProviderFor(key);
        [saved addObject:(id)provider.ask ?: NSNull.null];
        provider.ask = ^(SGLyricsQuery *query, void (^done)(SGLyricsResult *)) {
            [asked addObject:key];
            if ([key isEqual:@"netease"] && pickedReply) {
                if (pickedReply == 1) [query.requestContext noteFailure:YES];
                done(nil);
            } else done(madeUpLyrics(key, SGKaraokeTimingLine));
        };
    }
    SGLyricsSetOrder(@[@"musixmatch", @"netease"]);
    SGSetInt(SGKeyLyricsAskMode, 0);
    SGSetEnabled(SGKeyLyricsPreferWordTiming, NO);
    SGLyricsResult *(^fetch)(NSString *) = ^SGLyricsResult *(NSString *track) {
        __block BOOL finished = NO;
        __block SGLyricsResult *answer;
        SGLyricsFetch(track, ^(SGLyricsResult *result) { answer = result; finished = YES; });
        pumpUntil(^BOOL { return finished; });
        return answer;
    };
    void (^evictWalk)(void) = ^{
        for (NSUInteger i = 0; i < 40; i++) fetch(NSUUID.UUID.UUIDString);
        [asked removeAllObjects];
    };
    NSString *track = NSUUID.UUID.UUIDString;
    SGLyricsResult *answer = fetch(track);
    CHECK([answer.provider isEqual:@"musixmatch"] && !answer.picked);
    SGLyricsAskOffers(track);
    SGLyricsChooseSource(track, @"netease");
    CHECK([SGLyricsCreditFor(track) isEqual:@"netease"]);
    evictWalk();
    answer = fetch(track);
    CHECK([asked isEqual:@[@"netease"]] && answer.picked);
    evictWalk();
    pickedReply = 1;
    answer = fetch(track);
    CHECK([asked isEqual:(@[@"netease", @"musixmatch"])]);
    CHECK([answer.provider isEqual:@"musixmatch"] && !answer.picked);
    CHECK([SGLyricsChosenSource(track) isEqual:@"netease"] && fetch(track) == answer);
    pickedReply = 0;
    evictWalk();
    CHECK(fetch(track).picked);
    evictWalk();
    pickedReply = 2;
    answer = fetch(track);
    CHECK([answer.provider isEqual:@"musixmatch"] && !answer.picked && !SGLyricsChosenSource(track));
    pickedReply = 0;

    // Automatic restores the real keeper's Spotify sheet, not a test-owned lines dictionary.
    track = NSUUID.UUID.UUIDString;
    NSArray *spotify = SGKaraokeStaticLines(@[@"Spotify original"]);
    SGKaraokeKeepSpotifyLines(track, spotify);
    SGLyricsAskOffers(track);
    SGLyricsChooseSource(track, @"netease");
    SGLyricsChooseAutomatic(track);
    CHECK(!SGLyricsChosenSource(track) && [SGLyricsCreditFor(track) isEqual:@"Spotify"]);
    CHECK([SGKaraokeLineText(SGKaraokeLinesForTrack(track).firstObject) isEqual:@"Spotify original"]);
    evictWalk();
    CHECK([fetch(track).provider isEqual:@"musixmatch"] && [asked isEqual:@[@"musixmatch"]]);

    SGSetEnabled(SGKeyLyricsPreferWordTiming, YES);
    SGLyricsSetOrder(@[SGImportedLRCKey, @"musixmatch", @"netease"]);
    [asked removeAllObjects];
    CHECK([fetch(NSUUID.UUID.UUIDString).provider isEqual:SGImportedLRCKey]);
    CHECK([asked isEqual:@[SGImportedLRCKey]]);
    SGLyricsSetOrder(@[@"musixmatch", SGImportedLRCKey, @"netease"]);
    [asked removeAllObjects];
    CHECK([fetch(NSUUID.UUID.UUIDString).provider isEqual:@"musixmatch"]);
    CHECK([asked isEqual:(@[@"musixmatch", SGImportedLRCKey, @"netease"])]);
    for (NSUInteger i = 0; i < keys.count; i++)
        SGLyricsProviderFor(keys[i]).ask = saved[i] == NSNull.null ? nil : saved[i];
    SGSetEnabled(SGKeyLyricsPreferWordTiming, NO);
    SGLyricsSetOrder(@[@"musixmatch"]);
    puts("walk selection: 40-track eviction, failed/empty picks, Spotify restoration and imported timing passed");
}

static BOOL checkFileAfterPick(BOOL replace) {
    NSString *track = NSUUID.UUID.UUIDString;
    SGLyricsProvider *provider = SGLyricsProviderFor(@"musixmatch");
    SGLyricsAsk saved = provider.ask;
    provider.ask = ^(SGLyricsQuery *query, void (^done)(SGLyricsResult *)) {
        done(madeUpLyrics(@"Explicit words", SGKaraokeTimingLine));
    };
    sg_linkedSong = track;
    sg_importedReplies = [NSMutableDictionary dictionary];
    SGKaraokeRequestLyrics(track);
    SGLyricsResult *original = madeUpLyrics(@"Original file", SGKaraokeTimingLine);
    for (SGKaraokeLine *line in original.karaokeLines) line.fileOwned = YES;
    sg_importedReplies[track](original);
    [sg_importedReplies removeAllObjects];
    SGLyricsAskOffers(track);
    SGLyricsChooseSource(track, @"musixmatch");
    if (replace) importsChanged(@[[@"spotify:track:" stringByAppendingString:track]]);
    HARNESS_CHECK([SGLyricsChosenSource(track) isEqual:@"musixmatch"]);
    HARNESS_CHECK([SGKaraokeLineText(SGKaraokeLinesForTrack(track).firstObject) isEqual:@"Explicit words"]);
    NSString *wanted = replace ? @"Replacement file" : @"Original file";
    if (!replace) {
        sg_testTranslations = YES; sg_translationRequestedLanguage = nil;
        [sg_testDefaults setInteger:7 forKey:SGKeyLyricsTranslationLanguage];
    }
    SGLyricsChooseAutomatic(track);
    if (replace) {
        SGKaraokeRequestLyrics(track);
        if (sg_importedReplies[track]) sg_importedReplies[track](madeUpLyrics(wanted, SGKaraokeTimingLine));
    } else {
        SGKaraokeKeepSpotifyLines(track, madeUpLyrics(@"Late Spotify", SGKaraokeTimingWords).karaokeLines);
        sg_testTranslations = NO; sg_translationReply = nil;
        [sg_testDefaults removeObjectForKey:SGKeyLyricsTranslationLanguage];
    }
    BOOL current = [SGKaraokeLineText(SGKaraokeLinesForTrack(track).firstObject) isEqual:wanted]
        && (replace || !sg_translationRequestedLanguage);
    sg_linkedSong = nil; sg_importedReplies = nil; provider.ask = saved;
    SGKaraokeForgetLyrics(track);
    return current;
}

static BOOL checkLocalRevisit(void) {
    HarnessLyricsState *state = [HarnessLyricsState new];
    HarnessLyricsTrack *a = [HarnessLyricsTrack new], *b = [HarnessLyricsTrack new];
    a.URI = @"spotify:local:A::Song:120"; a.metadata = @{@"local_file_path":@"/fixture/a.mp3"};
    b.URI = @"spotify:local:B::Song:120"; b.metadata = @{@"local_file_path":@"/fixture/b.mp3"};
    sg_testLocalFile = YES; sg_fixtureState = (id)state;
    sg_importedReplies = [NSMutableDictionary dictionary];
    SGKaraokeTrackWatcher *watcher = [SGKaraokeTrackWatcher new];
    for (HarnessLyricsTrack *song in @[a,b]) {
        state.track = song;
        SGKaraokeRequestLyrics(song.URI);
        sg_importedReplies[song.URI](madeUpLyrics(@"File words",SGKaraokeTimingLine));
        [sg_importedReplies removeAllObjects];
    }
    state.track = a;
    [watcher playerStateDidReport:(id)state];
    BOOL reused = !sg_importedReplies[a.URI] && SGKaraokeLinesForTrack(a.URI).count;
    if (!reused && sg_importedReplies[a.URI]) {
        sg_importedReplies[a.URI](madeUpLyrics(@"File words",SGKaraokeTimingLine));
        [sg_importedReplies removeAllObjects];
    }
    sg_testApplication.applicationState = UIApplicationStateBackground;
    a.metadata = @{@"local_file_path":@"/fixture/new-a.mp3"};
    [watcher playerStateDidReport:(id)state];
    BOOL deferred = !sg_importedReplies[a.URI] && SGKaraokeLinesForTrack(a.URI).count;
    sg_testApplication.applicationState = UIApplicationStateActive;
    [watcher becameActive:nil];
    BOOL resumed = sg_importedReplies[a.URI] && [sg_testReportedPath isEqual:@"/fixture/new-a.mp3"];
    sg_fixtureState = nil; sg_testLocalFile = NO; sg_importedReplies = nil;
    SGKaraokeForgetLyrics(a.URI); SGKaraokeForgetLyrics(b.URI);
    return reused && deferred && resumed;
}

static BOOL checkHeldPagesOnImportChange(void) {
    NSString *track = NSUUID.UUID.UUIDString;
    NSURL *url = [NSURL URLWithString:[@"https://example.test/color-lyrics/v2/track/" stringByAppendingString:track]];
    NSHTTPURLResponse *missing = [[NSHTTPURLResponse alloc] initWithURL:url statusCode:404 HTTPVersion:@"HTTP/2" headerFields:nil];
    SGLyricsStoreSave(track, madeUpLyrics(@"Offline copy", SGKaraokeTimingLine).karaokeLines, @"Ordinary");
    NSMutableArray *cancelled = [@[@0,@0] mutableCopy];
    sg_providerReply = nil;
    for (NSUInteger i = 0; i < 2; i++) {
        HarnessTask *task = [HarnessTask new];
        task.originalRequest = task.currentRequest = [NSURLRequest requestWithURL:url];
        receivedResponse(nil,nil,(id)task,missing,^(NSURLSessionResponseDisposition disposition) {
            HARNESS_CHECK(disposition == NSURLSessionResponseCancel);
            cancelled[i] = @([cancelled[i] unsignedIntegerValue]+1);
        }, ^(NSURLResponse *response, SGDisposition handler) { HARNESS_FAIL(@"retired response forwarded"); });
    }
    pumpUntil(^BOOL { return sg_providerReply != nil; });
    importsChanged(@[[@"spotify:track:" stringByAppendingString:track]]);
    sg_providerReply(madeUpLyrics(@"Late source", SGKaraokeTimingLine)); sg_providerReply = nil;
    drainReplies();
    __block BOOL loaded = NO;
    SGLyricsStoreLoad(track, ^(NSArray *lines, NSString *credit, SGLyricsResult *metadata) {
        HARNESS_CHECK([SGKaraokeLineText(lines.firstObject) isEqual:@"Offline copy"]);
        loaded = YES;
    });
    pumpUntil(^BOOL { return loaded; });
    SGKaraokeForgetLyrics(track);
    return [cancelled isEqual:@[@1,@1]];
}

static void checkReload(void) {
    NSString *track = @"reload-song";
    NSDictionary *record = @{@"id": @456, @"syncedLyrics": @"[00:01]Before reload"};
    CHECK(SGLyricsPin(track, record));
    SGLyricsPinStamp *generation = SGLyricsPinGeneration(track);
    __block NSUInteger notes = 0;
    id observer = [NSNotificationCenter.defaultCenter addObserverForName:SGLyricsDidReloadNotification object:track queue:nil usingBlock:^(NSNotification *note) {
        CHECK(NSThread.isMainThread && !sg_kept[track] && !SGKaraokeLinesForTrack(track) && !SGLyricsCreditFor(track));
        CHECK(!requested(track) && ![sg_asking containsObject:track] && !sg_losses[track] && !sg_requests[track]);
        CHECK(SGLyricsMayHave(track)); notes++;
    }];
    [sg_missing addObject:track]; sg_losses[track] = @3;
    sg_pinnedReply = nil;
    SGLyricsReload(track);
    CHECK(notes == 1 && [SGLyricsPinnedID(track) isEqual:@456] && ![SGLyricsPinGeneration(track) isEqual:generation]);
    pumpUntil(^BOOL { return sg_pinnedReply != nil; });
    void (^old)(SGLyricsResult *) = sg_pinnedReply;
    sg_pinnedReply = nil;
    SGLyricsReload(track);
    old(SGLrcLibRecordResult(record));
    CHECK(!SGKaraokeLinesForTrack(track) && !sg_kept[track]);
    pumpUntil(^BOOL { return sg_pinnedReply != nil; });
    sg_pinnedReply(SGLrcLibRecordResult(@{@"syncedLyrics": @"[00:02]After reload"}));
    pumpUntil(^BOOL { return SGKaraokeLinesForTrack(track) != nil; });
    CHECK([SGKaraokeLineText(SGKaraokeLinesForTrack(track).firstObject) isEqual:@"After reload"]);
    CHECK([sg_askedPin isEqual:@456] && [SGLyricsCreditFor(track) isEqual:@"LRCLIB"]);
    [NSNotificationCenter.defaultCenter removeObserver:observer];
    printf("reload: cleared caches, request generations, notification order, kept pin and stale reply rejection passed\n");
}

// Both providers are real walk/menu entries; only their network callbacks are controlled here.
// Run one race in isolation with RETRINE_PICK_RACE=1, 2 or 3 to check it against pre-fix sources.
static void checkPickRaces(NSUInteger only) {
    NSArray *keys = @[@"musixmatch", @"netease"];
    NSMutableArray *saved = [NSMutableArray array];
    NSMutableDictionary *pending = [NSMutableDictionary dictionary];
    __block BOOL hold = NO;
    for (NSString *key in keys) {
        SGLyricsProvider *provider = SGLyricsProviderFor(key);
        [saved addObject:(id)provider.ask ?: NSNull.null];
        provider.ask = ^(SGLyricsQuery *query, void (^done)(SGLyricsResult *)) {
            if (hold) pending[key] = [done copy];
            else done(madeUpLyrics(key, SGKaraokeTimingWords));
        };
    }
    SGLyricsSetOrder(keys);
    SGSetInt(SGKeyLyricsAskMode, 0);
    [NSUserDefaults.standardUserDefaults setBool:NO forKey:SGKeyLyricsPreferWordTiming];
    [NSUserDefaults.standardUserDefaults setBool:NO forKey:SGKeyLyricsOffline];
    void (^prepare)(NSString *) = ^(NSString *track) {
        SGKaraokeRequestLyrics(track);
        pumpUntil(^BOOL { return SGKaraokeLinesForTrack(track) != nil; });
        CHECK([SGLyricsCreditFor(track) isEqual:keys[0]]);
        SGLyricsAskOffers(track);
    };
    void (^evictAutomatic)(void) = ^{
        // Exercise the real 40-song snapshot bound, not a test-only cache deletion.
        for (NSUInteger i = 0; i < 40; i++) {
            NSString *other = NSUUID.UUID.UUIDString;
            SGLyricsAskOffers(other);
            SGLyricsChooseSource(other, keys[1]);
        }
    };
    if (!only || only == 1) {
        for (NSNumber *pendingWrite in @[@NO, @YES]) {
            NSString *track = NSUUID.UUID.UUIDString;
            prepare(track);
            SGLyricsChooseSource(track, keys[1]);
            evictAutomatic();
            [NSUserDefaults.standardUserDefaults setBool:YES forKey:SGKeyLyricsOffline];
            // Re-open after menu eviction, and save the pick with no Automatic snapshot left.
            SGLyricsAskOffers(track);
            SGLyricsChooseSource(track, keys[1]);
            if (!pendingWrite.boolValue) {
                if (getenv("RETRINE_PRESSURE_ONLY"))
                    for (NSUInteger i = 0; i <= kKeptTracks; i++) SGKaraokeKeepLines(NSUUID.UUID.UUIDString, @[]);
                drainReplies();
                __block BOOL loaded = NO;
                SGLyricsStoreLoad(track, ^(NSArray *lines, NSString *credit, SGLyricsResult *metadata) {
                    CHECK(lines.count && [credit isEqual:keys[1]]); loaded = YES;
                });
                pumpUntil(^BOOL { return loaded; });
            } else {
                BOOL pending = NO;
                for (SGKaraokeWrite *write in sg_storeWrites) if ([write.track isEqual:track]) pending = YES;
                CHECK(pending);
            }
            SGLyricsChooseAutomatic(track);
            SGKaraokeRequestLyrics(track);
            pumpUntil(^BOOL { return SGKaraokeLinesForTrack(track) != nil; });
            CHECK([SGKaraokeLineText(SGKaraokeLinesForTrack(track).firstObject) isEqual:keys[0]]);
            CHECK([SGLyricsCreditFor(track) isEqual:keys[0]] && !SGLyricsChosenSource(track));
            drainReplies();
            __block BOOL loaded = NO;
            SGLyricsStoreLoad(track, ^(NSArray *lines, NSString *credit, SGLyricsResult *metadata) {
                CHECK([SGKaraokeLineText(lines.firstObject) isEqual:keys[0]] && [credit isEqual:keys[0]]);
                loaded = YES;
            });
            pumpUntil(^BOOL { return loaded; });
            [NSUserDefaults.standardUserDefaults setBool:NO forKey:SGKeyLyricsOffline];
        }
        printf("pick race 1: evicted Automatic snapshot rejects persisted pick and pending offline write passed\n");
    }
    if (!only || only == 2) {
        NSString *track = NSUUID.UUID.UUIDString;
        prepare(track);
        for (id choice in @[keys[1], keys[0], NSNull.null]) {
            SGLyricsTaskState *state = [SGLyricsTaskState new];
            state.kind = SGLyricsTaskDonor; state.track = track;
            state.pinGeneration = SGLyricsPinGeneration(track);
            __block BOOL forwarded = NO;
            answerDonor(nil, state, sg_kept[track], nil, nil, ^(NSURLResponse *response, SGDisposition handler) { forwarded = YES; });
            CHECK(forwarded && state.chain.texts.count);
            if (choice == NSNull.null) SGLyricsChooseAutomatic(track);
            else SGLyricsChooseSource(track, choice);
            NSArray *lines = SGKaraokeLinesForTrack(track);
            NSString *credit = SGLyricsCreditFor(track);
            HarnessDelegate *delegate = [HarnessDelegate new];
            __block NSError *ended;
            finishDonor(delegate, nil, nil, state, nil, nil, ^(NSError *error) { ended = error; });
            CHECK(ended.code == NSURLErrorCancelled && !delegate.deliveries);
            CHECK(SGKaraokeLinesForTrack(track) == lines && [SGLyricsCreditFor(track) isEqual:credit]);
        }
        printf("pick race 2: donor body held across source pick, another pick and Automatic is cancelled without changing lines/credit passed\n");
    }
    if (!only || only == 3) {
        for (NSNumber *mode in @[@0, @1, @2]) {
            SGSetInt(SGKeyLyricsAskMode, mode.integerValue);
            NSString *track = NSUUID.UUID.UUIDString;
            prepare(track);
            SGLyricsChooseSource(track, keys[1]);
            // Replay after the walk/line caches have been evicted, with its original snapshot intact.
            [sg_kept removeObjectForKey:track];
            [sg_lyrics removeObjectForKey:track];
            setRequested(track, NO);
            [pending removeAllObjects]; hold = YES;
            __block NSUInteger deliveries = 0;
            for (NSUInteger i = 0; i < 2; i++) SGLyricsFetch(track, ^(SGLyricsResult *result) {
                CHECK([result.provider isEqual:keys[0]]); deliveries++;
            });
            SGKaraokeRequestLyrics(track);
            pumpUntil(^BOOL { return pending[keys[1]] && sg_waiting[track].count == 3; });
            CHECK(!pending[keys[0]]);
            void (^old)(SGLyricsResult *) = pending[keys[1]];
            SGLyricsChooseAutomatic(track);
            CHECK([SGLyricsCreditFor(track) isEqual:keys[0]]);
            old(madeUpLyrics(@"stale promoted provider", SGKaraokeTimingWords));
            drainReplies();
            CHECK(!deliveries && [SGLyricsCreditFor(track) isEqual:keys[0]]);
            CHECK([SGKaraokeLineText(SGKaraokeLinesForTrack(track).firstObject) isEqual:keys[0]]);
            CHECK(pending[keys[0]] != nil);
            void (^first)(SGLyricsResult *) = pending[keys[0]];
            first(madeUpLyrics(keys[0], SGKaraokeTimingWords));
            pumpUntil(^BOOL { return deliveries == 2; });
            CHECK(!sg_waiting[track] && [((SGLyricsResult *)sg_kept[track]).provider isEqual:keys[0]]);
            old(madeUpLyrics(@"stale again", SGKaraokeTimingWords));
            CHECK(deliveries == 2 && [SGLyricsCreditFor(track) isEqual:keys[0]]);
            hold = NO;
        }
        printf("pick race 3: Automatic retires promoted walk in all three modes, restarts configured order and serves both waiters once passed\n");
    }
    for (NSUInteger i = 0; i < keys.count; i++)
        SGLyricsProviderFor(keys[i]).ask = saved[i] == NSNull.null ? nil : saved[i];
    SGSetInt(SGKeyLyricsAskMode, 0);
    SGLyricsSetOrder(@[@"musixmatch"]);
}

static void checkBackgroundSkip(void) {
    sg_backgroundConsumer = YES;
    id oldPlayer = sg_player;
    NSDictionary *oldHeaders = sg_spclientHeaders;
    Method appMethod = class_getClassMethod(UIApplication.class, @selector(sharedApplication));
    IMP oldApp = method_setImplementation(appMethod, (IMP)fakeApplication);
    Method taskMethod = class_getInstanceMethod(NSURLSession.class, @selector(dataTaskWithRequest:completionHandler:));
    IMP oldTask = method_setImplementation(taskMethod, (IMP)spotifyMiss);
    sg_testApplication = [HarnessApplication new];
    sg_testApplication.applicationState = UIApplicationStateBackground;
    sg_heldClocks = [NSMutableArray array];
    sg_spclientHeaders = @{};
    HarnessPlayer *player = [HarnessPlayer new]; sg_player = player;
    HarnessLyricsState *state = [HarnessLyricsState new]; player.state = state;
    HarnessLyricsTrack *track = [HarnessLyricsTrack new]; state.track = track;
    NSString *key = fixtureTrackID();
    track.URI = [@"spotify:track:" stringByAppendingString:key];
    track.trackTitle = @"Song"; track.artistName = @"Singer"; track.metadata = @{};
    SGKaraokeRememberTrack((id)track, key);
    SGKaraokeTrackWatcher *sourceWatcher = [SGKaraokeTrackWatcher new];
    sg_open = YES; sg_closed = 0;
    sg_watcher = [SGRPlayerLyricsWatcher new];
    [sg_watcher playerStateDidChange:(id)state];
    CHECK(!SGRPlayerLyricsNone() && sg_open && !sg_heldClocks.count);

    // The background source walk fails, then Spotify really has no lyrics (404). The walk already
    // refuses to cache this miss; the keeper must not turn it into a permanent requested mark.
    sg_providerReply = nil;
    SGKaraokeRequestLyrics(key);
    pumpUntil(^BOOL { return sg_providerReply != nil; });
    [sg_providerContext noteFailure:YES];
    sg_providerReply(nil);
    pumpUntil(^BOOL { return sg_losses[key].unsignedIntegerValue == 1; });
    CHECK(!SGLyricsKeptAnswer(key) && !SGKaraokeLinesForTrack(key) && !SGKaraokeLooking(key));
    CHECK(sg_open && !sg_closed && !SGRPlayerLyricsNone() && sg_heldClocks.count == 1);
    NSObject *request = sg_requests[key];
    sg_providerReply = nil;
    for (NSUInteger i = 0; i < 100; i++) SGKaraokeRequestLyrics(key);
    drainReplies();
    CHECK(!sg_providerReply && sg_requests[key] == request && sg_spotifyAsks == 1);
    dispatch_block_t retry = sg_heldClocks.firstObject;
    [sg_heldClocks removeAllObjects];

    // Foreground before the pause expires: re-asking respects the pause, and the pause itself
    // starts a fresh walk when it expires, without waiting for a lyric view's display-link tick.
    sg_testApplication.applicationState = UIApplicationStateActive;
    [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationDidBecomeActiveNotification object:nil];
    CHECK(!SGRPlayerLyricsNone() && sg_heldClocks.count == 1 && sg_requests[key] == request);
    dispatch_block_t grace = sg_heldClocks.firstObject;
    [sg_heldClocks removeAllObjects];
    grace(); // The 3-second grace expires before the existing 10-second retry pause.
    CHECK(!sg_open && sg_closed == 1 && SGRPlayerLyricsNone() && [sg_asking containsObject:key]);
    retry();
    pumpUntil(^BOOL { return sg_providerReply != nil; });
    CHECK(SGKaraokeLooking(key));
    sg_providerReply(SGLrcLibRecordResult(@{@"syncedLyrics": @"[00:01]Back in front"}));
    pumpUntil(^BOOL { return SGKaraokeLinesForTrack(key) != nil; });
    grace();
    CHECK(!sg_open && sg_closed == 1 && SGRPlayerLyricsAvailable() && !SGRPlayerLyricsNone());
    CHECK(!sg_losses[key] && ![sg_asking containsObject:key] && sg_spotifyAsks == 1);

    // A stale same-track timer cannot consume a fresh foreground grace. Inactive is not active,
    // either; and the unchanged active path still closes after a genuine, fully answered miss.
    SGKaraokeForgetLyrics(key);
    sg_open = YES; sg_closed = 0;
    sg_testApplication.applicationState = UIApplicationStateInactive;
    [sg_watcher closeIfNone];
    CHECK(sg_open && !SGRPlayerLyricsNone());
    sg_testApplication.applicationState = UIApplicationStateActive;
    [sg_watcher restartChecks];
    dispatch_block_t stale = sg_heldClocks.lastObject;
    [sg_watcher restartChecks];
    dispatch_block_t current = sg_heldClocks.lastObject;
    stale();
    CHECK(sg_open && !SGRPlayerLyricsNone());
    current();
    CHECK(!sg_open && sg_closed == 1 && SGRPlayerLyricsNone());

    // A fully answered no-lyrics walk remains cached, unlike a failed walk.
    SGLyricsRestoreKept(key, nil);
    sg_providerReply = nil;
    SGKaraokeRequestLyrics(key);
    pumpUntil(^BOOL { return sg_providerReply != nil; });
    sg_providerReply(nil);
    pumpUntil(^BOOL { return !SGKaraokeLooking(key); });
    CHECK(SGLyricsKeptAnswer(key) == NSNull.null && !sg_losses[key]);
    CHECK(requested(key) && ![sg_asking containsObject:key]);

    // No captured Spotify headers yet: the same failed walk waits, rather than being re-walked
    // every tick. A pause expiring in the background only clears the mark; activation asks again.
    sg_spclientHeaders = nil; sg_testApplication.applicationState = UIApplicationStateBackground;
    [sg_heldClocks removeAllObjects];
    track = [HarnessLyricsTrack new]; state.track = track; key = fixtureTrackID();
    track.URI = [@"spotify:track:" stringByAppendingString:key];
    track.trackTitle = @"Next song"; track.artistName = @"Singer"; track.metadata = @{};
    SGKaraokeRememberTrack((id)track, key);
    sg_open = YES;
    [sg_watcher playerStateDidChange:(id)state];
    sg_providerReply = nil;
    SGKaraokeRequestLyrics(key);
    pumpUntil(^BOOL { return sg_providerReply != nil; });
    [sg_providerContext noteFailure:YES];
    sg_providerReply(nil);
    pumpUntil(^BOOL { return sg_losses[key].unsignedIntegerValue == 1; });
    CHECK(sg_heldClocks.count == 1 && requested(key) && sg_open);
    retry = sg_heldClocks.firstObject; [sg_heldClocks removeAllObjects]; sg_providerReply = nil;
    retry();
    drainReplies();
    CHECK(!sg_providerReply && !requested(key) && !SGRPlayerLyricsNone());
    sg_testApplication.applicationState = UIApplicationStateActive;
    [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationDidBecomeActiveNotification object:nil];
    pumpUntil(^BOOL { return sg_providerReply != nil; });
    sg_providerReply(SGLrcLibRecordResult(@{@"syncedLyrics": @"[00:01]Next track recovered"}));
    pumpUntil(^BOOL { return SGKaraokeLinesForTrack(key) != nil; });
    CHECK(sg_open && !SGRPlayerLyricsNone() && !sg_losses[key]);
    // Exhaust the new path while playing and paused, with and without Spotify headers.
    // A same-track state update or a reader's tick is not a recovery signal.
    for (NSString *signal in @[@"activation", @"replay", @"explicit"]) {
        [sg_heldClocks removeAllObjects];
        sg_spclientHeaders = [signal isEqual:@"explicit"] ? nil : @{};
        state.isPaused = ![signal isEqual:@"activation"];
        track = [HarnessLyricsTrack new]; state.track = track; key = fixtureTrackID();
        track.URI = [@"spotify:track:" stringByAppendingString:key];
        track.trackTitle = @"Outage"; track.artistName = @"Singer"; track.metadata = @{};
        SGKaraokeRememberTrack((id)track, key);
        sg_lastSeen = (id)track; sg_lastSeenID = key;
        sg_providerReply = nil;
        SGKaraokeRequestLyrics(key);
        NSUInteger asks = sg_spotifyAsks;
        dispatch_block_t lastRetry;
        // Initial ask plus four automatic retries: 10/20/40/60, then no more.
        for (NSUInteger attempt = 0; attempt <= 4; attempt++) {
            pumpUntil(^BOOL { return sg_providerReply != nil; });
            void (^answer)(SGLyricsResult *) = sg_providerReply; sg_providerReply = nil;
            [sg_providerContext noteFailure:YES];
            answer(nil);
            pumpUntil(^BOOL { return !SGKaraokeLooking(key); });
            CHECK(!SGKaraokeLinesForTrack(key) && !SGLyricsKeptAnswer(key));
            if (attempt < 4) {
                CHECK(sg_heldClocks.count == 1);
                lastRetry = sg_heldClocks.firstObject; [sg_heldClocks removeAllObjects];
                lastRetry();
            } else {
                CHECK(!sg_heldClocks.count && ![sg_asking containsObject:key] && !sg_requests[key]);
                CHECK(requested(key));
            }
        }
        CHECK(sg_spotifyAsks == asks + (sg_spclientHeaders ? 5 : 0));
        asks = sg_spotifyAsks;
        for (NSUInteger i = 0; i < 100; i++) {
            SGKaraokeRequestLyrics(key);
            [sourceWatcher playerStateDidChange:(id)state];
            lastRetry(); // Even a stale backoff callback cannot restart the exhausted walk.
        }
        drainReplies();
        CHECK(!sg_providerReply && !sg_heldClocks.count && sg_spotifyAsks == asks);
        if ([signal isEqual:@"activation"]) {
            sg_testApplication.applicationState = UIApplicationStateBackground;
            sg_testApplication.applicationState = UIApplicationStateActive;
            [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationDidBecomeActiveNotification object:nil];
        } else if ([signal isEqual:@"replay"]) {
            state.track = nil; [sourceWatcher playerStateDidChange:(id)state];
            state.track = track; [sourceWatcher playerStateDidChange:(id)state];
        } else SGKaraokeAskAgain(key);
        pumpUntil(^BOOL { return sg_providerReply != nil && SGKaraokeLooking(key); });
        CHECK(!sg_sourceRetries[key]);
        sg_providerReply(SGLrcLibRecordResult(@{@"syncedLyrics": @"[00:01]Recovery signal worked"}));
        pumpUntil(^BOOL { return SGKaraokeLinesForTrack(key) != nil; });
        CHECK(!sg_losses[key]);
    }

    // Existing Spotify network-loss behavior: expiry releases the mark for readers, but does not
    // automatically ask, and does not consume the new failed-source retry budget.
    SGKaraokeForgetLyrics(key); SGLyricsRestoreKept(key, nil); [sg_heldClocks removeAllObjects];
    sg_spclientHeaders = @{}; sg_spotifyStatus = 503; sg_providerReply = nil;
    SGKaraokeRequestLyrics(key);
    pumpUntil(^BOOL { return sg_providerReply != nil; });
    sg_providerReply(nil); sg_providerReply = nil;
    pumpUntil(^BOOL { return sg_losses[key] != nil; });
    CHECK(!sg_sourceRetries[key] && sg_heldClocks.count == 1);
    NSUInteger asks = sg_spotifyAsks;
    retry = sg_heldClocks.firstObject; [sg_heldClocks removeAllObjects]; retry();
    drainReplies();
    CHECK(!sg_providerReply && sg_spotifyAsks == asks && !requested(key));
    SGKaraokeRequestLyrics(key);
    pumpUntil(^BOOL { return sg_losses[key].unsignedIntegerValue == 2; });
    CHECK(!sg_sourceRetries[key]); // The cached genuine source miss still follows the old lost path.
    sg_spotifyStatus = 404;

    // A local-file foreground miss still returns the cover after grace, not after its retry budget.
    SGKaraokeForgetLyrics(key); SGLyricsRestoreKept(key, nil); [sg_heldClocks removeAllObjects];
    sg_testLocalFile = YES; sg_open = YES; sg_providerReply = nil;
    [sg_watcher restartChecks];
    grace = sg_heldClocks.firstObject;
    SGKaraokeRequestLyrics(key);
    pumpUntil(^BOOL { return sg_providerReply != nil; });
    sg_providerReply(nil);
    pumpUntil(^BOOL { return sg_losses[key] != nil; });
    CHECK(!SGKaraokeLooking(key) && [sg_asking containsObject:key]);
    grace();
    CHECK(!sg_open && SGRPlayerLyricsNone() && [sg_asking containsObject:key]);
    SGKaraokeForgetLyrics(key); sg_testLocalFile = NO;
    [NSNotificationCenter.defaultCenter removeObserver:sourceWatcher];
    [NSNotificationCenter.defaultCenter removeObserver:sg_watcher]; sg_watcher = nil;
    sg_heldClocks = nil; sg_player = oldPlayer; sg_spclientHeaders = oldHeaders;
    method_setImplementation(appMethod, oldApp);
    method_setImplementation(taskMethod, oldTask);
    printf("background skip: inactive guards, foreground grace including local retry pauses, bounded source retries, activation/replay/explicit recovery and unchanged Spotify-loss retries passed\n");
}

void checkNetEaseURLs(void);

@interface HarnessMethodParent : NSObject
- (NSInteger)inheritedOnly;
@end
@implementation HarnessMethodParent
- (NSInteger)inheritedOnly { return 1; }
@end
@interface HarnessMethodChild : HarnessMethodParent
@end
@implementation HarnessMethodChild
- (NSInteger)duplicate { return 2; }
@end
@interface HarnessMethodChild (Duplicate)
- (NSInteger)duplicate;
@end
@implementation HarnessMethodChild (Duplicate)
- (NSInteger)duplicate { return 3; }
@end

static void checkOwnMethod(void) {
    CHECK(SGOwnMethod(HarnessMethodChild.class, @selector(inheritedOnly)) == NULL);
    // A category and its class deliberately supply different entries for the same selector.
    // Runtime enumeration order, not the helper's output, defines the expected first entry.
    unsigned int count = 0;
    Method *methods = class_copyMethodList(HarnessMethodChild.class, &count);
    Method first = NULL, last = NULL;
    for (unsigned int i = 0; i < count; i++) {
        if (method_getName(methods[i]) != @selector(duplicate)) continue;
        if (!first) first = methods[i];
        last = methods[i];
    }
    free(methods);
    CHECK(first && last && method_getImplementation(first) != method_getImplementation(last));
    CHECK(SGOwnMethod(HarnessMethodChild.class, @selector(duplicate)) == first);
    puts("own method: inherited methods excluded, duplicate selector selects first entry");
}

static void checkTranslationPresence(void) {
    CHECK(!SGLyricsHasTranslations(nil));
    CHECK(!SGLyricsHasTranslations(@[]));
    SGKaraokeLine *line = SGKaraokeStaticLines(@[@"Original"]).firstObject;
    line.translation = @"";
    CHECK(!SGLyricsHasTranslations(@[line]));
    line.translation = @" \n";
    CHECK(SGLyricsHasTranslations(@[line]));
    line.translation = @"Original";
    CHECK(SGLyricsHasTranslations(@[line]));
    SGKaraokeLine *untranslated = SGKaraokeStaticLines(@[@"Other"]).firstObject;
    untranslated.backing = line;
    CHECK(!SGLyricsHasTranslations(@[untranslated]));
    CHECK(SGLyricsHasTranslations(@[untranslated, line]));
    puts("translation presence: stored text, whitespace, repeated originals and top-level lines");
}

static void checkTranslationDelivery(void) {
    [sg_testDefaults setInteger:7 forKey:SGKeyLyricsTranslationLanguage]; // English in the persisted index.
    sg_testTranslations = YES;
    NSArray *lines = SGKaraokeStaticLines(@[@"Original"]);
    SGKaraokeKeepLines(@"translation-delivery", lines);
    CHECK(sg_translationReply != nil);
    SGKaraokeLine *translated = [lines.firstObject copy];
    translated.translation = @"Translated";
    sg_translatedLines = @[translated];
    sg_translationReply(@{@"Original": @"Translated"});
    CHECK([SGKaraokeLinesForTrack(@"translation-delivery").firstObject.translation isEqual:@"Translated"]);
    sg_translationReply = nil;
    SGKaraokeKeepLines(@"translation-delivery", sg_translatedLines);
    CHECK(sg_translationReply == nil);
    sg_testTranslations = NO;
    sg_translatedLines = nil;
    [sg_testDefaults removeObjectForKey:SGKeyLyricsTranslationLanguage];
    SGKaraokeForgetLyrics(@"translation-delivery");
    puts("translation delivery: late provider reply kept, existing translation suppresses another request");
}

static void checkTTMLTranslationProvenance(void) {
    NSString *xml = @"<tt><head><metadata><iTunesMetadata><translations>"
        "<translation xml:lang=\"en-US\"><text for=\"L1\">Hello</text></translation>"
        "<translation xml:lang=\"ko-KR\"><text for=\"L1\">안녕</text></translation>"
        "</translations></iTunesMetadata></metadata></head><body><div>"
        "<p key=\"L1\" begin=\"1s\" end=\"2s\">Bonjour</p></div></body></tt>";
    // The stored field is the requested filter (en), not the matched document tag (en-US).
    for (NSArray *fixture in @[@[@7, @"Hello", @"en"], @[@18, @"안녕", @"ko"],
                              @[@0, @"Hello", NSNull.null], @[@10, NSNull.null, NSNull.null]]) {
        SGSetInt(SGKeyLyricsTranslationLanguage, [fixture[0] integerValue]);
        __block BOOL finished = NO;
        SGLyricsTransform(^id {
            CHECK(!NSThread.isMainThread);
            return SGTTMLResult(xml, NO);
        }, ^(SGLyricsResult *result) {
            CHECK(NSThread.isMainThread);
            SGKaraokeLine *line = result.karaokeLines.firstObject;
            CHECK(line && [(line.translation ?: NSNull.null) isEqual:fixture[1]]);
            CHECK([(line.translationLanguage ?: NSNull.null) isEqual:fixture[2]]);
            if ([fixture[0] isEqual:@7]) {
                SGSetInt(SGKeyLyricsTranslationLanguage, 18);
                SGKaraokeLine *copy = [line copy];
                CHECK([copy.translationLanguage isEqual:@"en"]);
            }
            finished = YES;
        });
        pumpUntil(^BOOL { return finished; });
    }
    [sg_testDefaults removeObjectForKey:SGKeyLyricsTranslationLanguage];
    SGPrefsChanged();
    puts("TTML provenance: worker reads, regional filter tags, Any/unknown and copied origin passed");
}

static void checkCommunityTranslationProvenance(void) {
    SGSetInt(SGKeyLyricsTranslationLanguage, 7);
    sg_testTranslations = YES;
    NSArray<SGKaraokeLine *> *lines = SGKaraokeStaticLines(@[@"Original", @"Unmatched"]);
    sg_translationReply = nil;
    SGKaraokeKeepLines(@"community-provenance", lines);
    CHECK(sg_translationReply != nil);
    SGKaraokeLine *translated = [lines.firstObject copy]; translated.translation = @"Translated";
    sg_translatedLines = @[translated, lines[1]];
    sg_translationReply(@{@"Original": @"Translated"});
    NSArray<SGKaraokeLine *> *communityLines = SGKaraokeLinesForTrack(@"community-provenance");
    CHECK([communityLines.firstObject.translationLanguage isEqual:@"en"]);
    CHECK(!lines.firstObject.translationLanguage && !communityLines[1].translationLanguage);
    sg_testTranslations = NO; sg_translationReply = nil; sg_translatedLines = nil;
    SGKaraokeForgetLyrics(@"community-provenance");
    [sg_testDefaults removeObjectForKey:SGKeyLyricsTranslationLanguage];
    SGPrefsChanged();
    puts("Musixmatch provenance: new copies keep the requested language without changing originals");
}

static void checkLiveTranslationTarget(NSString *scenario) {
    SGSetInt(SGKeyLyricsTranslationLanguage, 7);
    sg_testTranslations = YES;
    SGKaraokeTrackWatcher *watcher = [SGKaraokeTrackWatcher new];
    NSString *track = NSUUID.UUID.UUIDString;
    NSString *xml = @"<tt><head><metadata><iTunesMetadata><translations>"
        "<translation xml:lang=\"en\"><text for=\"L1\">Hello</text></translation>"
        "</translations></iTunesMetadata></metadata></head><body><div>"
        "<p key=\"L1\" begin=\"1s\" end=\"2s\">Bonjour</p></div></body></tt>";
    __block BOOL clearedNotification = NO;
    id observer = [NSNotificationCenter.defaultCenter addObserverForName:SGKaraokeLinesKeptNotification
        object:track queue:nil usingBlock:^(NSNotification *note) {
        CHECK(NSThread.isMainThread);
        if ([SGLyricsTranslationLanguage() isEqual:@"ko"]
            && !SGKaraokeLinesForTrack(track).firstObject.translation) clearedNotification = YES;
    }];
    if ([scenario isEqual:@"community-stale"]) {
        NSArray<SGKaraokeLine *> *lines = SGKaraokeStaticLines(@[@"Bonjour"]);
        SGKaraokeKeepLines(track, lines);
        void (^englishReply)(NSDictionary *) = sg_translationReply;
        CHECK(englishReply && [sg_translationRequestedLanguage isEqual:@"en"]);
        SGKaraokeLine *english = [lines.firstObject copy]; english.translation = @"Hello";
        sg_translatedLines = @[english];
        SGSetInt(SGKeyLyricsTranslationLanguage, 18);
        englishReply(@{@"Bonjour": @"Hello"});
        CHECK(!SGKaraokeLinesForTrack(track).firstObject.translation); // stale community
    } else if ([scenario isEqual:@"ttml-stale"]) {
        __block SGLyricsResult *held;
        SGLyricsTransform(^id {
            CHECK(!NSThread.isMainThread);
            return SGTTMLResult(xml, NO);
        }, ^(SGLyricsResult *result) { held = result; });
        pumpUntil(^BOOL { return held != nil; });
        CHECK([held.karaokeLines.firstObject.translation isEqual:@"Hello"]);
        SGSetInt(SGKeyLyricsTranslationLanguage, 18);
        SGKaraokeKeepLines(track, held.karaokeLines);
        CHECK(!SGKaraokeLinesForTrack(track).firstObject.translation); // stale TTML
        CHECK([held.karaokeLines.firstObject.translation isEqual:@"Hello"]); // source snapshot unchanged
    } else {
        NSArray<SGKaraokeLine *> *lines = SGTTMLLines(xml);
        SGKaraokeLine *line = lines.firstObject;
        line.backing = SGKaraokeStaticLines(@[@"Backing"]).firstObject;
        line.backing.translation = @"Unknown language";
        line.pronunciation = SGKaraokeStaticLines(@[@"Reading"]).firstObject;
        line.pronunciation.translation = @"Matching language";
        line.pronunciation.translationLanguage = @"KO";
        SGKaraokeKeepLines(track, lines);
        SGLyricsSetCredit(track, @"Provider credit");
        // Any retains known and unknown translations, including nested ones.
        SGSetInt(SGKeyLyricsTranslationLanguage, 0);
        SGKaraokeKeepLines(track, lines);
        [NSNotificationCenter.defaultCenter postNotificationName:NSUserDefaultsDidChangeNotification object:sg_testDefaults];
        drainReplies();
        CHECK([SGKaraokeLinesForTrack(track).firstObject.translation isEqual:@"Hello"]);
        CHECK([SGKaraokeLinesForTrack(track).firstObject.backing.translation isEqual:@"Unknown language"]);
        SGSetInt(SGKeyLyricsTranslationLanguage, 18);
        // Exercise a notification posted away from main without making its thread wait for main.
        __block BOOL posted = NO;
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
            [NSNotificationCenter.defaultCenter postNotificationName:NSUserDefaultsDidChangeNotification object:sg_testDefaults];
            dispatch_async(dispatch_get_main_queue(), ^{ posted = YES; });
        });
        pumpUntil(^BOOL { return posted; });
        CHECK(!SGKaraokeLinesForTrack(track).firstObject.translation); // received English
        CHECK(!SGKaraokeLinesForTrack(track).firstObject.backing.translation);
        CHECK([SGKaraokeLinesForTrack(track).firstObject.pronunciation.translation isEqual:@"Matching language"]);
        CHECK([line.translation isEqual:@"Hello"] && [line.backing.translation isEqual:@"Unknown language"]);
        CHECK([SGLyricsCreditFor(track) isEqual:@"Provider credit"]);
        CHECK(SGKaraokeLinesForTrack(track).firstObject.start == 1000 && SGKaraokeLinesForTrack(track).firstObject.end == 2000);
    }
    [NSNotificationCenter.defaultCenter postNotificationName:NSUserDefaultsDidChangeNotification object:sg_testDefaults];
    drainReplies();
    CHECK(clearedNotification);
    CHECK([SGKaraokeLineText(SGKaraokeLinesForTrack(track).firstObject) isEqual:@"Bonjour"]);
    CHECK([sg_translationRequestedLanguage isEqual:@"ko"] && sg_translationReply);
    SGKaraokeLine *korean = [SGKaraokeLinesForTrack(track).firstObject copy]; korean.translation = @"안녕";
    sg_translatedLines = @[korean];
    sg_translationReply(@{@"Bonjour": @"안녕"});
    CHECK([SGKaraokeLinesForTrack(track).firstObject.translation isEqual:@"안녕"]);
    CHECK([SGKaraokeLinesForTrack(track).firstObject.translationLanguage isEqual:@"ko"]);
    [NSNotificationCenter.defaultCenter removeObserver:observer];
    [NSNotificationCenter.defaultCenter removeObserver:watcher];
    SGKaraokeForgetLyrics(track);
    sg_testTranslations = NO; sg_translationReply = nil; sg_translatedLines = nil;
    printf("live translation target: %s passed\n", scenario.UTF8String);
}

static void checkCommunityPersistence(BOOL cached) {
    SGSetInt(SGKeyLyricsTranslationLanguage, 7);
    SGSetEnabled(SGKeyLyricsOffline, YES);
    sg_testTranslations = YES;
    NSString *track = NSUUID.UUID.UUIDString;
    NSArray<SGKaraokeLine *> *lines = SGLrcLibRecordResult(@{@"syncedLyrics": @"[00:01]Original\n[00:02]"}).karaokeLines;
    SGKaraokeLine *translated = [lines.firstObject copy]; translated.translation = @"Hello";
    sg_translatedLines = @[translated];
    NSDictionary *reply = @{@"Original": @"Hello"};
    __block BOOL translatedNotification = NO;
    id observer = [NSNotificationCenter.defaultCenter addObserverForName:SGKaraokeLinesKeptNotification
        object:track queue:nil usingBlock:^(NSNotification *note) {
        CHECK(NSThread.isMainThread);
        SGKaraokeLine *line = SGKaraokeLinesForTrack(track).firstObject;
        if ([line.translation isEqual:@"Hello"] && [line.translationLanguage isEqual:@"en"]) translatedNotification = YES;
    }];
    sg_cachedTranslationReply = cached ? reply : nil;
    SGKaraokeKeepLines(track, lines);
    SGLyricsSetCredit(track, @"Community fixture");
    if (!cached) {
        drainReplies(); // The original, untranslated write may already have started.
        translatedNotification = NO;
        sg_translationReply(reply);
    }
    CHECK(translatedNotification); // community kept notification
    drainReplies(); // Submit the keeper's end-of-turn write before the I/O fence.
    __block BOOL writesDrained = NO;
    SGLyricsStoreSize(^(unsigned long long bytes) { CHECK(bytes > 0); writesDrained = YES; });
    pumpUntil(^BOOL { return writesDrained; });
    // Fresh offline session: no memory answer, no community transport, only the real disk store.
    sg_testTranslations = NO; sg_cachedTranslationReply = nil; sg_translationReply = nil; sg_translatedLines = nil;
    [sg_lyrics removeAllObjects]; [sg_requestMarks removeAllObjects]; [sg_asking removeAllObjects];
    [sg_requests removeAllObjects]; [sg_storeRequests removeAllObjects]; [sg_storeWrites removeAllObjects];
    SGLyricsForgetAnswer(track);
    SGKaraokeRequestLyrics(track);
    pumpUntil(^BOOL { return SGKaraokeLinesForTrack(track) != nil; });
    SGKaraokeLine *restored = SGKaraokeLinesForTrack(track).firstObject;
    CHECK([SGKaraokeLineText(restored) isEqual:@"Original"]);
    CHECK([restored.translation isEqual:@"Hello"]); // community offline translation
    CHECK([restored.translationLanguage isEqual:@"en"]); // community offline provenance
    CHECK(restored.start == 1000);
    CHECK([SGLyricsCreditFor(track) isEqual:@"Community fixture"]);
    [NSNotificationCenter.defaultCenter removeObserver:observer];
    SGKaraokeForgetLyrics(track);
    SGSetEnabled(SGKeyLyricsOffline, NO);
    printf("community translation: %s reply announced and restored offline passed\n", cached ? "cached" : "delayed");
}

static void checkLiveTranslations(void) {
    NSString *only = getenv("RETRINE_TRANSLATION_CASE") ? @(getenv("RETRINE_TRANSLATION_CASE")) : nil;
    for (NSString *scenario in @[@"community-stale", @"ttml-stale", @"received"]) {
        if (!only || [only isEqual:scenario]) checkLiveTranslationTarget(scenario);
    }
    if (!only || [only isEqual:@"delayed"]) checkCommunityPersistence(NO);
    if (!only || [only isEqual:@"cached"]) checkCommunityPersistence(YES);
    [sg_testDefaults removeObjectForKey:SGKeyLyricsTranslationLanguage];
    SGPrefsChanged();
}

static void checkStoredTranslationLanguage(void) {
    checkCommunityTranslationProvenance();
    checkTTMLTranslationProvenance();
    NSString *xml = @"<tt><head><metadata><iTunesMetadata><translations>"
        "<translation xml:lang=\"en-US\"><text for=\"L1\">Hello</text></translation>"
        "<translation xml:lang=\"ko-KR\"><text for=\"L1\">안녕</text></translation>"
        "</translations></iTunesMetadata></metadata></head><body><div>"
        "<p key=\"L1\" begin=\"1s\" end=\"2s\">Bonjour</p></div></body></tt>";
    [sg_testDefaults setBool:YES forKey:SGKeyLyricsOffline];
    sg_testTranslations = YES;
    for (NSNumber *selection in @[@7, @18]) { // persisted English and Korean selections
        [sg_testDefaults setInteger:7 forKey:SGKeyLyricsTranslationLanguage];
        NSArray<SGKaraokeLine *> *lines = SGTTMLLines(xml);
        CHECK([lines.firstObject.translation isEqual:@"Hello"]);
        NSString *track = NSUUID.UUID.UUIDString;
        // Cached English lines may be reused under Korean before the store ever sees them.
        SGSetInt(SGKeyLyricsTranslationLanguage, selection.integerValue);
        SGLyricsStoreSave(track, lines, @"TTML fixture");
        sg_translationReply = nil; sg_translationRequestedLanguage = nil;
        SGKaraokeRequestLyrics(track);
        pumpUntil(^BOOL { return SGKaraokeLinesForTrack(track) != nil; });
        SGKaraokeLine *kept = SGKaraokeLinesForTrack(track).firstObject;
        CHECK([SGKaraokeLineText(kept) isEqual:@"Bonjour"] && kept.start == 1000 && kept.end == 2000);
        if (selection.integerValue == 7) {
            CHECK([kept.translation isEqual:@"Hello"] && !sg_translationReply);
        } else {
            CHECK(!kept.translation && [sg_translationRequestedLanguage isEqual:@"ko"] && sg_translationReply);
            CHECK([SGTTMLLines(xml).firstObject.translation isEqual:@"안녕"]);
            SGKaraokeLine *translated = [kept copy]; translated.translation = @"안녕";
            sg_translatedLines = @[translated];
            sg_translationReply(@{@"Bonjour": @"안녕"});
            CHECK([SGKaraokeLinesForTrack(track).firstObject.translation isEqual:@"안녕"]);
            CHECK([SGKaraokeLinesForTrack(track).firstObject.translationLanguage isEqual:@"ko"]);
        }
        SGKaraokeForgetLyrics(track);
        SGLyricsStoreDelete(track);
    }
    sg_testTranslations = NO; sg_translationReply = nil; sg_translatedLines = nil;
    sg_translationRequestedLanguage = nil;
    [sg_testDefaults removeObjectForKey:SGKeyLyricsTranslationLanguage];
    [sg_testDefaults setBool:NO forKey:SGKeyLyricsOffline];
    puts("stored translation language: TTML regional tags, matching cache and Korean community lookup passed");
}

static void checkTTMLResult(void) {
    NSString *xml = @"<tt><body><div>"
        "<p begin=\"5s\" end=\"6s\"><span begin=\"5s\" end=\"6s\">Later</span></p>"
        "<p begin=\"1s\" end=\"2s\"><span begin=\"1s\" end=\"2s\">Earlier</span></p>"
        "</div></body></tt>";
    SGLyricsResult *result = SGTTMLResult(xml, NO);
    CHECK(result.synced && !result.wordTimed);
    CHECK(([[result.karaokeLines valueForKey:@"start"] isEqual:@[@5000, @1000]]));
    CHECK(([result.starts isEqual:@[@5000, @1000, @2000]]));
    CHECK(([result.texts isEqual:@[@"Later", @"Earlier", @""]]));
    CHECK(SGTTMLResult(@"<tt><body><p begin=\"1s\" end=\"2s\">Line only</p></body></tt>", YES).wordTimed);
    CHECK(!SGTTMLResult(nil, YES));
    CHECK(!SGTTMLResult(@"<tt/>", NO));
    CHECK(!SGTTMLResult(@"<tt><body><p begin=\"1s\" end=\"2s\">Unclosed", YES));
    puts("TTML result: supplied timing, parser order, page projection and nil answers passed");
}

static void checkLRCProjection(SGLyricsResult *result, NSArray *lineStarts, NSArray *starts, NSArray *texts, BOOL wordTimed) {
    CHECK(result && result.synced && result.wordTimed == wordTimed);
    CHECK([[result.karaokeLines valueForKey:@"start"] isEqual:lineStarts]);
    CHECK([result.starts isEqual:starts]);
    CHECK([result.texts isEqual:texts]);
}

static void checkLRCProjectionPaths(void) {
    checkLRCProjection(SGLyricsLRCResult(@"[00:05]B\n[00:01]A\n[00:01.5]\n[00:05.5]\n"),
        @[@1000, @5000], @[@1000, @1425, @5000, @5425], @[@"A", @"♪", @"B", @""], NO);
    // Enhanced-LRC word tags remain literal text, not word timing.
    checkLRCProjection(SGLyricsLRCResult(@"[00:01]<00:01.00>A <00:01.50>B\n[00:02]\n"),
        @[@1000], @[@1000, @2000], @[@"<00:01.00>A <00:01.50>B", @""], NO);
    NSString *file = @"version: '1.0'\nlines:\n"
        "- text: B\n  start_ms: 5000\n  end_ms: 6000\n  words:\n"
        "  - text: B\n    start_ms: 5000\n    end_ms: 6000\n"
        "- text: A\n  start_ms: 1000\n  end_ms: 1500\n";
    checkLRCProjection(SGLrcLibRecordResult(@{@"hasWordSync": @YES, @"lyricsfile": file}),
        @[@1000, @5000], @[@1000, @1425, @5000, @6000], @[@"A", @"♪", @"B", @""], YES);
    CHECK(!SGLyricsLRCResult(nil));
    for (NSString *empty in @[@"", @" \n", @"[00:01]\n[00:02]♪"]) CHECK(!SGLyricsLRCResult(empty));
    CHECK(!SGLrcLibRecordResult(nil));
    CHECK(!SGLrcLibRecordResult(@{@"hasWordSync": @YES}));
    for (NSString *empty in @[@"", @"version: '1.0'\nlines: []\n"]) {
        CHECK(!SGLrcLibRecordResult(@{@"hasWordSync": @YES, @"lyricsfile": empty}));
    }
    puts("LRCLIB projection: line timing, literal word tags, mixed Lyricsfile timing and empty inputs passed");
}

static void checkAsyncLRCLIBPick(void) {
    NSMutableString *file = [NSMutableString stringWithString:@"version: '1.0'\nlines:\n"];
    for (NSUInteger i = 0; i < 1500; i++) {
        [file appendFormat:@"- text: Word\n  start_ms: %lu\n  end_ms: %lu\n  words:\n  - text: Word\n    start_ms: %lu\n    end_ms: %lu\n",
            i * 1000, i * 1000 + 500, i * 1000, i * 1000 + 500];
    }
    NSDictionary *longRecord = @{@"id": @8801, @"hasWordSync": @YES, @"lyricsfile": [file copy]};
    NSString *track = @"async-lrclib-pick";
    sg_observePickPreparation = YES;
    __block NSUInteger replies = 0, notifications = 0;
    id observer = [NSNotificationCenter.defaultCenter addObserverForName:SGLyricsPinDidChangeNotification object:track queue:nil usingBlock:^(NSNotification *note) {
        CHECK(NSThread.isMainThread);
        notifications++;
    }];
    SGLyricsPickRecord(track, longRecord, nil, ^(BOOL pinned) {
        CHECK(NSThread.isMainThread && pinned);
        NSArray<SGKaraokeLine *> *lines = SGKaraokeLinesForTrack(track);
        CHECK(lines.count == 1500 && lines.firstObject.timing == SGKaraokeTimingWords);
        CHECK(lines.lastObject.words.firstObject.start == 1499000);
        CHECK([SGKaraokeLineText(lines.firstObject) isEqual:@"Word"]);
        replies++;
    });
    CHECK(!SGLyricsPinnedID(track));
    pumpUntil(^BOOL { return replies == 1; });
    CHECK(notifications == 1);
    // Both requests start before main can receive either completion; only the second may pin.
    SGLyricsPickRecord(track, longRecord, nil, ^(BOOL pinned) {
        CHECK(NSThread.isMainThread && !pinned);
        replies++;
    });
    SGLyricsPickRecord(track, @{@"id": @8802, @"syncedLyrics": @"[00:01]Newest"}, nil, ^(BOOL pinned) {
        CHECK(NSThread.isMainThread && pinned);
        replies++;
    });
    pumpUntil(^BOOL { return replies == 3; });
    CHECK(notifications == 2 && [SGLyricsPinnedID(track) isEqual:@8802]);
    CHECK([SGKaraokeLineText(SGKaraokeLinesForTrack(track).firstObject) isEqual:@"Newest"]);
    // Dismissing/searching away from the picker must also reject a still-latest selection.
    SGLyricsPickRecord(track, longRecord, ^BOOL { CHECK(NSThread.isMainThread); return NO; }, ^(BOOL pinned) {
        CHECK(NSThread.isMainThread && !pinned);
        replies++;
    });
    pumpUntil(^BOOL { return replies == 4; });
    CHECK(notifications == 2 && [SGLyricsPinnedID(track) isEqual:@8802]);
    sg_observePickPreparation = NO;
    [NSNotificationCenter.defaultCenter removeObserver:observer];
    // Remove only this fixture, without starting a fresh source walk through Unpin.
    SGKaraokeForgetLyrics(track);
    [sg_kept removeObjectForKey:track];
    @synchronized (sg_pins) { [sg_pins removeObjectForKey:track]; }
    puts("LRCLIB picks: long worker preparation, main delivery, superseded and dismissed selections passed");
}

static void checkStockPreferences(void) {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSArray *order = [defaults arrayForKey:SGKeyLyricsProviders];
    [defaults removeObjectForKey:SGKeyLyricsProviders];
    for (NSArray *fixture in @[@[@YES, @NO], @[@NO, @YES], @[@"1", @NO], @[@"0", @YES], @[@[], @YES], @[@{}, @YES]]) {
        [defaults setObject:fixture[0] forKey:SGKeyStock];
        [defaults removeObjectForKey:SGKeyLoadAhead];
        SGPrefsChanged();
        CHECK((SGLyricsOrder().count > 0) == [fixture[1] boolValue]);
        CHECK(optionalForWatcher(NO) == [fixture[1] boolValue]);
    }
    [defaults removeObjectForKey:SGKeyStock];
    [defaults setObject:@[] forKey:SGKeyLoadAhead];
    SGPrefsChanged();
    CHECK(optionalForWatcher(NO));
    [defaults removeObjectForKey:SGKeyLoadAhead];
    if (order) [defaults setObject:order forKey:SGKeyLyricsProviders];
    SGPrefsChanged();
    puts("source defaults: stock marker and Load ahead share typed preference accessors");
}

@interface HeaderSession : NSObject
@property NSUInteger merges;
@end
@implementation HeaderSession
- (NSURLSessionConfiguration *)configuration {
    self.merges++;
    NSURLSessionConfiguration *config = NSURLSessionConfiguration.ephemeralSessionConfiguration;
    config.HTTPAdditionalHeaders = @{@"Client-Token": @"session-token", @"Cookie": @"not forwarded"};
    return config;
}
@end

static void checkHeaderOrigin(void) {
    NSDictionary *previousHeaders = sg_spclientHeaders;
    NSMutableArray *previousWaiting = sg_headersWaiting;
    sg_spclientHeaders = nil;
    sg_headersWaiting = nil;
    // The third column is what public header consumers must see after each request.
    NSArray *cases = @[
        @[@"https://spclient.wg.spotify.com/color-lyrics/v2/track/check", @"trusted", @"trusted"],
        @[@"https://spclient.evil.example/color-lyrics/v2/track/check", @"untrusted-host", @"trusted"],
        @[@"https://evilspclient.wg.spotify.com.example/color-lyrics/v2/track/check", @"untrusted-suffix", @"trusted"],
        @[@"https://guc3-spclient.spotify.com.evil.com/", @"untrusted-regional-suffix", @"trusted"],
        @[@"https://spclient.spotify.com.x/", @"untrusted-domain", @"trusted"],
        @[@"https://evil-spclient.spotify.co/", @"untrusted-tld", @"trusted"],
        @[@"http://spclient.wg.spotify.com/color-lyrics/v2/track/check", @"insecure", @"trusted"],
        @[@"HTTPS://SPCLIENT.WG.SPOTIFY.COM/color-lyrics/v2/track/check", @"case-insensitive", @"case-insensitive"],
        // The regional name some accounts use instead of the global one (9.2.0 phone).
        @[@"https://guc3-spclient.spotify.com/remote-config-resolver/v3/configuration", @"regional", @"regional"],
        @[@"https://-spclient.spotify.com/", @"untrusted-empty-region", @"regional"],
        @[@"https://a.b-spclient.spotify.com/", @"untrusted-dotted-region", @"regional"],
        @[@"https://guc3_x-spclient.spotify.com/", @"untrusted-region-character", @"regional"],
        @[@"https://GUC3-SPCLIENT.SPOTIFY.COM/", @"regional-case", @"regional-case"],
    ];
    HarnessTask *task = [HarnessTask new];
    HeaderSession *session = [HeaderSession new];
    __block NSUInteger first = 0;
    SGSpclientHeaders(^(NSDictionary *headers) {
        CHECK([headers[@"authorization"] isEqual:@"trusted"]);
        first++;
    });
    for (NSArray<NSString *> *row in cases) {
        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:row[0]]];
        [request setValue:row[1] forHTTPHeaderField:@"Authorization"];
        task.currentRequest = [request copy];
        NSUInteger submissions = 0, before = session.merges;
        headerSubmissions = &submissions;
        for (NSUInteger i = 0; i < 32; i++) rememberHeaders((id)session, (id)task);
        headerSubmissions = NULL;
        NSUInteger accepted = [row[1] isEqual:row[2]] ? 1 : 0;
        CHECK(submissions == accepted && session.merges - before == accepted);
        __block BOOL checked = NO;
        // Capture queues its update on main. This fence observes that update (or rejection)
        // before querying the public API, without timing assumptions or network access.
        dispatch_async(dispatch_get_main_queue(), ^{
            SGSpclientHeaders(^(NSDictionary *headers) {
                CHECK([headers[@"authorization"] isEqualToString:row[2]]);
                CHECK([headers[@"client-token"] isEqual:@"session-token"] && !headers[@"cookie"]);
                checked = YES;
            });
        });
        pumpUntil(^BOOL { return checked; });
    }
    CHECK(first == 1);
    NSMutableURLRequest *revision = [task.currentRequest mutableCopy];
    [revision setValue:@"ko" forHTTPHeaderField:@"Accept-Language"];
    task.currentRequest = revision;
    rememberHeaders((id)session, (id)task);
    __block BOOL delivered = NO;
    dispatch_async(dispatch_get_main_queue(), ^{
        SGSpclientHeaders(^(NSDictionary *headers) {
            CHECK([headers[@"accept-language"] isEqual:@"ko"] && [headers[@"authorization"] isEqual:@"regional-case"]);
            delivered = YES;
        });
    });
    pumpUntil(^BOOL { return delivered; });
    NSString *previousRefusal = sg_refusedAuthorization;
    sg_refusedAuthorization = @"regional-case"; // 401 while another request using that token is in flight.
    HarnessTask *late = [HarnessTask new];
    late.currentRequest = [revision copy];
    HarnessTask *fresh = [HarnessTask new];
    [revision setValue:@"renewed" forHTTPHeaderField:@"Authorization"];
    fresh.currentRequest = [revision copy];
    rememberHeaders((id)session, (id)fresh);
    rememberHeaders((id)session, (id)late);
    rememberHeaders((id)session, (id)fresh);
    delivered = NO;
    dispatch_async(dispatch_get_main_queue(), ^{
        SGSpclientHeaders(^(NSDictionary *headers) {
            CHECK([headers[@"authorization"] isEqual:@"renewed"]);
            delivered = YES;
        });
    });
    pumpUntil(^BOOL { return delivered; });
    sg_refusedAuthorization = previousRefusal;
    sg_spclientHeaders = previousHeaders;
    sg_headersWaiting = previousWaiting;
    puts("header origin: exact HTTPS global or regional host, case-insensitivity, malicious hosts and HTTP rejection passed");
}

static void checkBackgroundTimedDelivery(void) {
    NSArray *keys = @[@"musixmatch", @"netease"];
    SGLyricsProvider *first = SGLyricsProviderFor(keys[0]), *second = SGLyricsProviderFor(keys[1]);
    SGLyricsAsk firstAsk = first.ask, secondAsk = second.ask;
    BOOL firstNeedsName = first.needsName, secondNeedsName = second.needsName;
    first.needsName = NO; second.needsName = YES;
    NSArray *order = SGLyricsOrder();
    NSInteger mode = SGInt(SGKeyLyricsAskMode, 1);
    for (NSNumber *choice in @[@1, @2]) {
        SGSetInt(SGKeyLyricsAskMode, choice.integerValue);
        SGLyricsSetOrder(keys);
        __block void (^plainReply)(SGLyricsResult *), (^timedReply)(SGLyricsResult *);
        first.ask = ^(SGLyricsQuery *query, void (^done)(SGLyricsResult *)) { plainReply = done; };
        second.ask = ^(SGLyricsQuery *query, void (^done)(SGLyricsResult *)) { timedReply = done; };
        NSString *track = [@"background-timed-" stringByAppendingString:choice.stringValue];
        __block SGLyricsResult *delivered;
        sg_waiting[track] = [NSMutableArray arrayWithObject:[^(SGLyricsResult *result) { delivered = result; } copy]];
        SGLyricsQuery *query = [SGLyricsQuery new]; query.trackID = track;
        sg_backgroundConsumer = YES;
        // The concurrent walk learns the name only after it has moved to the background.
        sg_testApplication.applicationState = choice.integerValue == 2 ? UIApplicationStateActive : UIApplicationStateBackground;
        startWalk(track, query);
        CHECK(plainReply && !timedReply);
        sg_testApplication.applicationState = UIApplicationStateBackground;
        SGLyricsResult *plain = madeUpLyrics(@"Plain only", SGKaraokeTimingNone);
        plain.title = @"Song"; plain.artist = @"Singer";
        plainReply(plain);
        drainReplies();
        CHECK(timedReply && !delivered);
        timedReply(madeUpLyrics(@"Timed background line", SGKaraokeTimingLine));
        drainReplies();
        CHECK(delivered.synced && [delivered.texts.firstObject isEqual:@"Timed background line"]);
        SGLyricsRetire(track);
        [sg_waiting removeObjectForKey:track];
    }
    sg_backgroundConsumer = NO;
    sg_testApplication.applicationState = UIApplicationStateActive;
    first.ask = firstAsk; second.ask = secondAsk;
    first.needsName = firstNeedsName; second.needsName = secondNeedsName;
    SGLyricsSetOrder(order);
    SGSetInt(SGKeyLyricsAskMode, mode);
    puts("background delivery: plain replies do not prevent later timed providers in either scheduler");
}

static void checkUpNext(void) {
    NSString *previousID = sg_lastSeenID;
    SPTPlayerTrack *previousTrack = sg_lastSeen;
    sg_prefetched = [NSMutableArray array];
    SGKaraokeTrackWatcher *watcher = [SGKaraokeTrackWatcher new];
    HarnessLyricsState *state = [HarnessLyricsState new];
    StateUpcomingTrack *(^track)(NSString *) = ^(NSString *identifier) {
        StateUpcomingTrack *value = [StateUpcomingTrack new];
        value.URI = [@"spotify:track:" stringByAppendingString:identifier];
        value.trackTitle = identifier; value.artistName = @"Singer"; value.metadata = @{};
        return value;
    };
    StateUpcomingTrack *a = track(@"ahead-current"), *b = track(@"ahead-old"), *c = track(@"ahead-new");
    state.track = (id)a; state.future = @[b];
    sg_fixtureState = (id)state;
    SGSetEnabled(SGKeyLoadAhead, NO);
    [watcher playerStateDidChange:(id)state];
    drainReplies();
    CHECK(([sg_prefetched isEqual:@[@"ahead-current"]]));
    SGSetEnabled(SGKeyLoadAhead, YES);
    [watcher playerUpNextDidChange:(id)state];
    CHECK(([sg_prefetched isEqual:@[@"ahead-current", @"ahead-old"]]));
    state.future = @[c];
    [watcher playerUpNextDidChange:(id)state];
    [watcher playerStateDidChange:(id)state];
    CHECK(([sg_prefetched isEqual:@[@"ahead-current", @"ahead-old", @"ahead-new"]]));
    state.future = @[]; [watcher playerUpNextDidChange:(id)state];
    CHECK(!watcher.ahead);
    state.future = @[@"invalid"]; [watcher playerUpNextDidChange:(id)state];
    CHECK(sg_prefetched.count == 3);
    sg_aheadAllowed = NO; state.future = @[b];
    [watcher playerUpNextDidChange:(id)state];
    CHECK(sg_prefetched.count == 3);
    sg_aheadAllowed = YES; [watcher playerStateDidChange:(id)state];
    CHECK([sg_prefetched.lastObject isEqual:@"ahead-old"]);
    // Cancelled advance requests cannot advance to another provider or publish a late answer.
    NSMutableDictionary *replies = [NSMutableDictionary dictionary];
    SGLyricsProvider *provider = SGLyricsProviderFor(@"musixmatch");
    SGLyricsAsk saved = provider.ask;
    provider.ask = ^(SGLyricsQuery *q, void (^done)(SGLyricsResult *)) { replies[q.trackID] = [done copy]; };
    pumpUntil(^BOOL { return replies[@"ahead-old"] != nil; });
    SGLyricsResult *old = madeUpLyrics(@"old", SGKaraokeTimingWords);
    CHECK(!SGLyricsKeptAnswer(@"ahead-new"));
    Method appMethod = class_getClassMethod(UIApplication.class, @selector(sharedApplication));
    IMP oldApp = method_setImplementation(appMethod, (IMP)fakeApplication);
    sg_testApplication = [HarnessApplication new];
    sg_testApplication.applicationState = UIApplicationStateBackground;
    sg_expensivePath = YES;
    [watcher background:nil];
    drainReplies();
    CHECK(!watcher.ahead);
    ((void (^)(SGLyricsResult *))replies[@"ahead-old"])(old);
    CHECK(!SGLyricsKeptAnswer(@"ahead-old"));
    sg_backgroundConsumer = NO;
    NSUInteger before = sg_prefetched.count;
    prefetch(@"background-unused");
    drainReplies();
    CHECK(sg_prefetched.count == before);
    sg_backgroundConsumer = YES;
    prefetch(@"background-needed");
    CHECK([sg_prefetched.lastObject isEqual:@"background-needed"]);
    sg_testApplication.applicationState = UIApplicationStateActive;
    sg_expensivePath = NO; sg_backgroundConsumer = NO;
    method_setImplementation(appMethod, oldApp);
    provider.ask = saved;
    sg_prefetched = nil;
    sg_fixtureState = nil;
    sg_lastSeenID = previousID;
    sg_lastSeen = previousTrack;
}

#import "pixie-check.inc"
int main(void) {
    @autoreleasepool {
        NSString *line = @"<p begin=\"0\" end=\"1\"><span begin=\"0\">verse</span></p>";
        NSString *rows = [@"" stringByPaddingToLength:line.length * 4096 withString:line startingAtIndex:0];
        CHECK(SGTTMLLines([NSString stringWithFormat:@"<tt>%@</tt>", rows]).count == 4096);
        NSString *many = [@"" stringByPaddingToLength:4 * 65536 withString:@"<x/>" startingAtIndex:0];
        CHECK(!SGTTMLLines([NSString stringWithFormat:@"<tt>%@%@</tt>", line, many]));
        NSString *open = [@"" stringByPaddingToLength:3 * 80 withString:@"<x>" startingAtIndex:0];
        NSString *close = [@"" stringByPaddingToLength:4 * 80 withString:@"</x>" startingAtIndex:0];
        CHECK(!SGTTMLLines([NSString stringWithFormat:@"<tt>%@%@%@</tt>", line, open, close]));
        CHECK(!SGTTMLLines([NSString stringWithFormat:@"<!DOCTYPE tt><tt>%@</tt>", line]));
        NSString *padding = [@"" stringByPaddingToLength:1500000 withString:@"界" startingAtIndex:0];
        CHECK(!SGTTMLLines([NSString stringWithFormat:@"<tt>%@<!--%@--></tt>", line, padding]));
        checkSpotifySyllables();
        checkSpotifyPublishedClock();
        checkHeaderOrigin();
        BOOL aheadOnly = getenv("RETRINE_UP_NEXT_ONLY") != NULL;
        if (!aheadOnly) {
        checkOwnMethod();
        checkTranslationPresence();
        checkLRCProjectionPaths();
        checkTTMLResult();
        checkNetEaseURLs();
        }
        // A separate suite makes the default writes real without touching the app's or the user's.
        sg_testSuite = [@"com.retrine.lyrics-state-check." stringByAppendingString:NSUUID.UUID.UUIDString];
        sg_testDefaults = [[NSUserDefaults alloc] initWithSuiteName:sg_testSuite];
        // A previous harness run's offline answer must not bypass this run's held providers.
        // Pin/reload invalidation also stays out of the user's real lyrics directory.
        char store[] = "/tmp/retrine-lyrics-state.XXXXXX";
        CHECK(mkdtemp(store));
        sg_testStore = @(store);
        SGLyricsStoreConfigureForTests([NSURL fileURLWithPath:sg_testStore], 1000, 30 * 1024 * 1024);
        [sg_testDefaults setBool:NO forKey:SGKeyLyricsOffline];
        atexit(removeTestDefaults);
        Method defaultsMethod = class_getClassMethod(NSUserDefaults.class, @selector(standardUserDefaults));
        method_setImplementation(defaultsMethod, (IMP)fakeDefaults);
        sg_testApplication = [HarnessApplication new];
        sg_testApplication.applicationState = UIApplicationStateActive;
        method_setImplementation(class_getClassMethod(UIApplication.class, @selector(sharedApplication)), (IMP)fakeApplication);
        NSUserDefaults *defaults = sg_testDefaults;
        if (getenv("RETRINE_PIXIE_ONLY")) { checkPixieQueue(); return 0; }
        if (getenv("RETRINE_PIXIE_COLD")) { checkColdQueue(@(getenv("RETRINE_PIXIE_COLD"))); return 0; }
        if (!aheadOnly) {
            checkLanguageStore();
            checkAskModeMigration();
            checkStockPreferences();
        }
        [defaults setObject:@[@"musixmatch"] forKey:SGKeyLyricsProviders];
        [defaults setInteger:250 forKey:SGKeyLyricsDelay];
        sg_seenTracks = [NSMutableDictionary dictionary];
        sg_lyrics = [NSMutableDictionary dictionary];
        sg_requestMarks = [NSMutableDictionary dictionary]; sg_asking = [NSMutableSet set]; sg_looking = [NSMutableSet set];
        sg_losses = [NSMutableDictionary dictionary]; sg_ownSources = YES;
        sg_lastSeenID = @"song";
        if (getenv("RETRINE_RESILIENCE_ONLY")) {
            checkHedgedWalk();
            checkWalkBudget();
            checkFastFailureTiming();
            checkSpotifyAuthPause();
            checkFailureFallback();
            checkInvocationDeadline();
            return 0;
        }
        if (getenv("RETRINE_AUTH_ONLY")) { checkSpotifyAuthPause(); return 0; }
        if (getenv("RETRINE_CANCEL_ONLY")) { checkRetiredCancellation(); return 0; }
        if (getenv("RETRINE_TRANSLATION_CASE")) { checkLiveTranslations(); return 0; }
        if (getenv("RETRINE_STORE_ONLY")) { checkStoredTranslationLanguage(); return 0; }
        checkAsyncLRCLIBPick();
        checkBackgroundTimedDelivery();
        checkUpNext();
        if (aheadOnly) { puts("lyrics up-next: replacement, coalescing, stale result and foreground gate passed"); return 0; }
        checkTranslationDelivery();
        checkStoredTranslationLanguage();
        checkLiveTranslations();
        checkMissingRecovery();
        checkSpicyCancellation();
        checkCredentialFallback();
        checkCompletedBounds();
        checkImportedDelivery();
        checkSongImport();
        checkFileDeliveryReview();
        BOOL currentImport = checkFileAfterPick(YES), releasedPages = checkHeldPagesOnImportChange();
        if (!currentImport || !releasedPages) HARNESS_FAIL(@"current Automatic import=%d; both held pages cancelled exactly once=%d",
                                                           currentImport,releasedPages);
        puts("import invalidation: explicit pick retained, Automatic uses replacement; both held pages cancelled once, ordinary offline copy retained");
        BOOL restored = checkFileAfterPick(NO), revisit = checkLocalRevisit();
        if (!restored || !revisit) HARNESS_FAIL(@"restored file protected=%d; local revisit and gated path change=%d",restored,revisit);
        puts("file authority and path sampling: Automatic protected; local revisit reused; background change deferred until activation");
        checkDirectInstrumentalFallback();
        const char *race = getenv("RETRINE_PICK_RACE");
        if (getenv("RETRINE_PRESSURE_ONLY")) {
            checkRecoveryNamesDeferredSources(); checkPickRaces(1);
            return 0;
        }
        if (race) { checkPickRaces((NSUInteger)atoi(race)); return 0; }
        HarnessPort *port = [HarnessPort new]; port.UID = @"headphones-one"; port.portName = @"Headphones"; port.portType = AVAudioSessionPortBluetoothA2DP;
        sg_fakeRoute = [HarnessRoute new]; sg_fakeRoute.outputs = @[port];
        Method routeMethod = class_getInstanceMethod(AVAudioSession.class, @selector(currentRoute));
        IMP originalRoute = method_setImplementation(routeMethod, (IMP)fakeRoute);
        CHECK(SGKaraokeDelayMs() == 250);
        NSUInteger reads = sg_defaultsReads;
        dispatch_apply(1000, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^(size_t i) { CHECK(SGKaraokeDelayMs() == 250); });
        CHECK(sg_defaultsReads == reads);
        __block NSMutableArray *delays = [NSMutableArray array];
        id delayObserver = [NSNotificationCenter.defaultCenter addObserverForName:SGLyricsOffsetsDidChangeNotification
            object:nil queue:nil usingBlock:^(NSNotification *note) {
                CHECK(NSThread.isMainThread);
                [delays addObject:@(SGKaraokeDelayMs())];
            }];
        SGSetInt(SGKeyLyricsDelay, 500);
        SGSetInt(SGKeyLyricsDelay, 1100);
        SGSetInt(SGKeyLyricsDelay, 1200); // same effective 1000 ms
        [NSNotificationCenter.defaultCenter postNotificationName:NSUserDefaultsDidChangeNotification object:defaults];
        [NSNotificationCenter.defaultCenter removeObserver:delayObserver];
        CHECK(([delays isEqual:@[@500, @1000]]));
        SGSetInt(SGKeyLyricsDelay, 250);
        SGLyricsSetTrackOffsetMs(@"song", -6000);
        SGLyricsSetRouteOffsetMs(6000);
        CHECK(SGLyricsTrackOffsetMs(@"song") == -5000 && SGLyricsRouteOffsetMs() == 5000 && SGKaraokeDelayMs() == 250);
        SGLyricsSetRouteOffsetMs(-300);
        CHECK(SGKaraokeDelayMs() == -5050 && [SGLyricsRouteName() isEqual:@"Headphones"]);
        SGLyricsSetTrackOffsetMs(@"song", 0);
        CHECK(SGKaraokeDelayMs() == -50 && ![defaults dictionaryForKey:SGKeyLyricsTrackOffsets][@"song"]);
        for (NSUInteger i = 0; i < 501; i++) SGLyricsSetTrackOffsetMs([@(i) stringValue], 12);
        CHECK([defaults dictionaryForKey:SGKeyLyricsTrackOffsets].count == 500 && SGLyricsTrackOffsetMs(@"500") == 12);
        __block NSUInteger routeNotes = 0;
        id observer = [NSNotificationCenter.defaultCenter addObserverForName:SGLyricsOffsetsDidChangeNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
            CHECK(NSThread.isMainThread); routeNotes++;
        }];
        port.portType = AVAudioSessionPortBuiltInSpeaker;
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            [NSNotificationCenter.defaultCenter postNotificationName:AVAudioSessionRouteChangeNotification object:nil];
        });
        pumpUntil(^BOOL { return routeNotes > 0; });
        CHECK(!SGLyricsRouteName() && !SGLyricsRouteOffsetMs() && SGKaraokeDelayMs() == 250);
        SGLyricsSetRouteOffsetMs(1000);
        CHECK(!SGLyricsRouteOffsetMs());
        port.portType = AVAudioSessionPortBluetoothA2DP;
        [NSNotificationCenter.defaultCenter postNotificationName:AVAudioSessionRouteChangeNotification object:nil];
        pumpUntil(^BOOL { return routeNotes > 1; });
        CHECK(SGLyricsRouteOffsetMs() == -300);
        [NSNotificationCenter.defaultCenter removeObserver:observer];
        HarnessPlayer *player = [HarnessPlayer new]; sg_player = player;
        SGKaraokeSeek(-500); CHECK(player.sought == 0);
        method_setImplementation(routeMethod, originalRoute);
        printf("offsets: clamp, zero removal, 500 tracks, negative total, cached clock, route notification and seek passed\n");

        NSDictionary *record = @{@"id": @123, @"syncedLyrics": @"[00:01]Chosen line"};
        sg_testApplication.applicationState = UIApplicationStateActive;
        sg_providerReply = nil;
        __block NSUInteger pinNotes = 0;
        observer = [NSNotificationCenter.defaultCenter addObserverForName:SGLyricsPinDidChangeNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
            CHECK(NSThread.isMainThread);
            if (SGLyricsPinnedID(note.object)) CHECK(SGKaraokeLinesForTrack(note.object) != nil);
            pinNotes++;
        }];
        __block SGLyricsResult *answer;
        SGLyricsFetch(@"song", ^(SGLyricsResult *result) { answer = result; });
        pumpUntil(^BOOL { return sg_providerReply != nil; });
        void (^oldReply)(SGLyricsResult *) = sg_providerReply;
        CHECK(SGLyricsPin(@"song", record));
        CHECK([SGLyricsPinnedID(@"song") isEqual:@123] && answer.karaokeLines.count == 1 && pinNotes == 1);
        CHECK([SGLyricsCreditFor(@"song") isEqual:@"LRCLIB"]);
        SGLyricsResult *chosen = answer;
        oldReply(SGLyricsPlainTextResult(@"Late wrong words", @"Old provider"));
        CHECK(sg_kept[@"song"] == chosen && [SGKaraokeLineText(SGKaraokeLinesForTrack(@"song").firstObject) isEqual:@"Chosen line"]);
        CHECK(!SGLyricsPin(@"song", @{@"id": @456}) && [SGLyricsPinnedID(@"song") isEqual:@123] && pinNotes == 1);
        SGLyricsUnpin(@"song");
        CHECK(!SGLyricsPinnedID(@"song") && !SGKaraokeLinesForTrack(@"song") && SGLyricsMayHave(@"song") && pinNotes == 2);
        sg_providerReply = nil;
        pumpUntil(^BOOL { return sg_providerReply != nil; });
        sg_providerReply(SGLrcLibRecordResult(@{@"syncedLyrics": @"[00:02]Normal again"}));
        CHECK([SGKaraokeLineText(SGKaraokeLinesForTrack(@"song").firstObject) isEqual:@"Normal again"]);
        CHECK(SGLyricsPin(@"song", record));
        [sg_kept removeObjectForKey:@"song"]; // The walk cache was evicted, so the persistent id must be asked first.
        answer = nil;
        SGLyricsFetch(@"song", ^(SGLyricsResult *result) { answer = result; });
        pumpUntil(^BOOL { return sg_pinnedReply != nil; });
        CHECK([sg_askedPin isEqual:@123]);
        void (^oldPinReply)(SGLyricsResult *) = sg_pinnedReply;
        SGLyricsUnpin(@"song");
        oldPinReply(chosen);
        CHECK(!answer && !sg_kept[@"song"]);
        sg_providerReply(SGLrcLibRecordResult(@{@"syncedLyrics": @"[00:03]After unpin"}));
        CHECK([SGKaraokeLineText(answer.karaokeLines.firstObject) isEqual:@"After unpin"]);
        CHECK(SGLyricsPin(@"fallback", record));
        [sg_kept removeObjectForKey:@"fallback"];
        sg_pinnedReply = nil; sg_providerReply = nil; sg_providerTrack = nil; answer = nil;
        SGLyricsFetch(@"fallback", ^(SGLyricsResult *result) { answer = result; });
        pumpUntil(^BOOL { return sg_pinnedReply != nil; });
        // A slow run lets "song"'s later work reach the provider meanwhile; only this track must wait for its stored id.
        CHECK(![sg_providerTrack isEqualToString:@"fallback"]);
        sg_pinnedReply(nil);
        CHECK(sg_providerReply != nil && [sg_providerTrack isEqualToString:@"fallback"]);
        sg_providerReply(SGLrcLibRecordResult(@{@"plainLyrics": @"Fallback words"}));
        CHECK([SGKaraokeLineText(answer.karaokeLines.firstObject) isEqual:@"Fallback words"]);
        CHECK(SGLyricsPin(@"instrumental", @{@"id": @9, @"instrumental": @YES}));
        CHECK(SGKaraokeLinesForTrack(@"instrumental") && !SGKaraokeLinesForTrack(@"instrumental").count);
        checkHookPins();
        checkWalkTypes();
        checkWalkEarlyAnswer();
        checkConcurrentWalk();
        checkSoundtrackRetry();
        checkInvocationIsolation();
        checkHedgedWalk();
        checkRetiredCancellation();
        checkWalkBudget();
        checkFastFailureTiming();
        checkSpotifyAuthPause();
        checkFailureFallback();
        checkInvocationDeadline();
        checkRecoveryNextPlayback();
        checkRecoveryUpgradeAndMiss();
        checkRecoveryFinalAndExhausted();
        checkConcurrentRecoveryWinner();
        checkFailedPinRecovery();
        checkFailedUntimedPick();
        checkRecoveryReentrantRetirement();
        checkRecoveryRetirement();
        checkRecoveryWithSpotify();
        checkWordWinnerRecovery();
        checkLateDonorSheetIdentity();
        checkEvictedSheetAuthority();
        checkRecoveryNamesDeferredSources();
        checkSpotifySurvivesRecoveryMiss();
        checkUntimedFailureSuppliesPage();
        puts("recovery: invocation isolation, all policies, provisional disk exclusion, stable snapshots, next playback, upgrades, misses, exhaustion, Spotify, translations and retirement passed");
        checkReload();
        checkPickRaces(0);
        checkWalkSelection();
        checkBackgroundSkip();
        for (NSUInteger i = 0; i < 501; i++) CHECK(SGLyricsPin([@(i) stringValue], record));
        CHECK([defaults dictionaryForKey:SGKeyLyricsPins].count == 500 && [SGLyricsPinnedID(@"500") isEqual:@123]);
        [NSNotificationCenter.defaultCenter removeObserver:observer];
        printf("pins: immediate keep, invalid choice, stale walk, unpin, stored-id lookup, failed-pin fallback, instrumental and 500 pins passed\n");
    }
    return 0;
}
