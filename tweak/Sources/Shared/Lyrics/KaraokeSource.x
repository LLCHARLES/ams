// Where the karaoke page gets its lines and its clock. The color-lyrics body is copied as it passes
// the same URLSession delegates AdBlock/AdNetwork.x reads, untouched, and kept per track, since the
// page may open long after the request finished. Track and clock use PlayerState's shared report,
// like artwork, falling back to the player only before the first report.
// With a source of the mod's on, the color-lyrics body is Shared/LyricsSources' to answer and it
// hands the lines over.
#import "Core/SGCore.h"
#import "Core/SGOptionalWork.h"
#import "Lyrics.h"
#import "LyricsStore.h"
#import "Shared/LocalFiles/LocalFiles.h"
#import "Shared/LocalFiles/LocalLyrics.h"
#import "Shared/LockScreenLyrics/LockScreenLyrics.h"
#import "Shared/AnimatedArtwork/AnimatedArtwork.h"
#import "Shared/LyricsSources/LyricsSources.h"
#import "Shared/Sing/Sing.h"
#import "Shared/Player/PlayerState.h"
#import "Shared/LiveActivity/LiveActivity.h"
#import "Shared/LyricsPiP/LyricsPiP.h"
#import "Headers/SPTPlayer.h"
#import <AVFoundation/AVFoundation.h>
#import <mach-o/dyld.h>
#import <objc/runtime.h>

static const NSUInteger kKeptTracks = 40;
static const NSUInteger kSeenTracks = 200;
static const NSUInteger kCompletedRequests = 200;
// A track whose request was lost may be asked for again after this long, twice as long after each loss
// in a row up to the most: soon enough for the song still playing, not so soon that a busy server is pressed.
static const NSTimeInterval kRetryPause = SGLyricsRetryPause, kRetryPauseMost = SGLyricsRetryPauseMost;
// Only the failed-source/empty-fallback path gets automatic retries: one pass through the backoff.
static const NSUInteger kSourceRetries = SGLyricsRecoveryTries;
// What spclient needs from a request to answer it as the signed-in app.
static NSString *const kSpclientHeaders[] = {@"authorization", @"client-token", @"app-platform", @"spotify-app-version", @"user-agent", @"accept-language"};

static NSMutableDictionary<NSString *, NSArray<SGKaraokeLine *> *> *sg_lyrics;
// Same lifetime as sg_lyrics, not the independently evicted source-order cache. Translation copies
// retain the original sheet's authority; losing its selection record never makes it persistable.
static NSMutableDictionary<NSString *, id> *sg_sheetAuthorities;
// Lives only as long as this track's request or retained sheet.
static NSMutableDictionary<NSString *, NSString *> *sg_sampledLocalPaths;
static NSMutableSet<NSString *> *sg_requested;
// Of those, the ones with a request still out or waiting out its pause. A full cache spares their lines
// and leaves them asked for, so no second request runs beside the first.
static NSMutableSet<NSString *> *sg_asking;
static NSMutableDictionary<NSString *, NSNumber *> *sg_losses;   // requests lost in a row, by track
// kSourceRetries + 1 means stopped until activation, replay or an explicit retry. Main queue.
static NSMutableDictionary<NSString *, NSNumber *> *sg_sourceRetries;
// A new token on each ask lets a forget retire both its reply and its retry pause. Main queue.
static NSMutableDictionary<NSString *, NSObject *> *sg_requests;
// Separate from source requests: a keep or forget retires a disk delivery and
// a deferred write without retiring a source walk that may still improve its answer.
static NSMutableDictionary<NSString *, NSObject *> *sg_storeRequests;
static NSMutableDictionary<NSString *, SGLyricsLease *> *sg_storeWrites;
static NSMutableSet<NSString *> *sg_looking;   // asked of the sources or spclient right now (SGKaraokeLooking)
static NSDictionary<NSString *, NSString *> *sg_spclientHeaders;
static NSString *sg_refusedAuthorization;
static NSMutableArray<void (^)(NSDictionary<NSString *, NSString *> *)> *sg_headersWaiting;   // SGSpclientHeaders
static __weak id sg_player;
// Every track the player has reported, by id, so a source can name a track that is not the one
// playing at the moment it is asked: a lyrics request routinely lands a beat before the player
// moves on to its track. The last object seen is kept by pointer so the check on each call is free,
// and its id behind it, since the player hands out a fresh object with every state it reports.
static NSMutableDictionary<NSString *, SPTPlayerTrack *> *sg_seenTracks;
static __weak SPTPlayerTrack *sg_lastSeen;
static NSString *sg_lastSeenID;   // the player makes a new track object on every state it reports, so the id is what tells a change
static BOOL sg_ownSources;   // a source of the mod's answers the color-lyrics request, not Spotify
static char kBodyKey;

NSNotificationName const SGLyricsOffsetsDidChangeNotification = @"spotifyglass.lyrics.offsetsDidChange";
static NSObject *sg_offsetsLock;
static NSMutableDictionary<NSString *, NSNumber *> *sg_trackOffsets, *sg_routeOffsets;
static NSString *sg_routeUID, *sg_routeName;
static NSInteger sg_delay;

static NSInteger offsetMs(id value) {
    return [value isKindOfClass:NSNumber.class] ? MAX(-5000, MIN(5000, [value integerValue])) : 0;
}

static NSMutableDictionary *offsetsFrom(id stored) {
    NSMutableDictionary *offsets = [NSMutableDictionary dictionary];
    if ([stored isKindOfClass:NSDictionary.class]) {
        for (id key in stored) {
            if ([key isKindOfClass:NSString.class] && [key length] && offsetMs(stored[key])) offsets[key] = @(offsetMs(stored[key]));
        }
    }
    return offsets;
}

static void offsetsChanged(void) {
    void (^post)(void) = ^{
        [NSNotificationCenter.defaultCenter postNotificationName:SGLyricsOffsetsDidChangeNotification object:nil];
    };
    if (NSThread.isMainThread) post();
    else dispatch_async(dispatch_get_main_queue(), post);
}

static void readRoute(void) {
    AVAudioSessionPortDescription *output = AVAudioSession.sharedInstance.currentRoute.outputs.firstObject;
    BOOL external = output && ![output.portType isEqualToString:AVAudioSessionPortBuiltInSpeaker]
                           && ![output.portType isEqualToString:AVAudioSessionPortBuiltInReceiver];
    @synchronized (sg_offsetsLock) {
        sg_routeUID = external && output.UID.length ? [output.UID copy] : nil;
        sg_routeName = sg_routeUID ? [output.portName copy] : nil;
    }
}

static void readOffsets(void) {
    @synchronized (sg_offsetsLock) {
        NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
        sg_trackOffsets = offsetsFrom([defaults objectForKey:SGKeyLyricsTrackOffsets]);
        for (NSString *track in sg_trackOffsets.allKeys) {
            if (sg_trackOffsets.count <= 500) break;
            [sg_trackOffsets removeObjectForKey:track];
        }
        sg_routeOffsets = offsetsFrom([defaults objectForKey:SGKeyLyricsRouteOffsets]);
        sg_delay = MAX(0, MIN(1000, [defaults integerForKey:SGKeyLyricsDelay]));
    }
}

static void setUpOffsets(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        sg_offsetsLock = [NSObject new];
        readOffsets();
        readRoute();
        // These notifications may arrive from the audio or preferences thread. Never make that
        // thread wait for main: at launch main may itself be waiting for Spotify's CoreThread.
        [NSNotificationCenter.defaultCenter addObserverForName:AVAudioSessionRouteChangeNotification object:nil queue:nil
                                                    usingBlock:^(NSNotification *note) {
            dispatch_async(dispatch_get_main_queue(), ^{ readRoute(); offsetsChanged(); });
        }];
        [NSNotificationCenter.defaultCenter addObserverForName:NSUserDefaultsDidChangeNotification object:nil queue:nil
                                                    usingBlock:^(NSNotification *note) {
            readOffsets();
        }];
    });
}

NSInteger SGLyricsTrackOffsetMs(NSString *trackID) {
    setUpOffsets();
    @synchronized (sg_offsetsLock) { return trackID ? sg_trackOffsets[trackID].integerValue : 0; }
}

void SGLyricsSetTrackOffsetMs(NSString *trackID, NSInteger ms) {
    if (!trackID.length) return;
    setUpOffsets();
    @synchronized (sg_offsetsLock) {
        ms = MAX(-5000, MIN(5000, ms));
        if (ms) sg_trackOffsets[trackID] = @(ms);
        else [sg_trackOffsets removeObjectForKey:trackID];
        for (NSString *other in sg_trackOffsets.allKeys) {
            if (sg_trackOffsets.count <= 500) break;
            if (![other isEqualToString:trackID]) [sg_trackOffsets removeObjectForKey:other];
        }
        [NSUserDefaults.standardUserDefaults setObject:[sg_trackOffsets copy] forKey:SGKeyLyricsTrackOffsets];
    }
    offsetsChanged();
}

NSString *SGLyricsRouteName(void) {
    setUpOffsets();
    @synchronized (sg_offsetsLock) { return sg_routeName; }
}

NSInteger SGLyricsRouteOffsetMs(void) {
    setUpOffsets();
    @synchronized (sg_offsetsLock) { return sg_routeUID ? sg_routeOffsets[sg_routeUID].integerValue : 0; }
}

void SGLyricsSetRouteOffsetMs(NSInteger ms) {
    setUpOffsets();
    @synchronized (sg_offsetsLock) {
        if (!sg_routeUID) return;
        ms = MAX(-5000, MIN(5000, ms));
        if (ms) sg_routeOffsets[sg_routeUID] = @(ms);
        else [sg_routeOffsets removeObjectForKey:sg_routeUID];
        [NSUserDefaults.standardUserDefaults setObject:[sg_routeOffsets copy] forKey:SGKeyLyricsRouteOffsets];
    }
    offsetsChanged();
}

// spclient's global name, or the regional one Spotify talks to instead on some accounts
// ("guc3-spclient.spotify.com" on a 9.2.0 phone, which never asked the global name at all).
static BOOL isSpclientHost(NSString *host) {
    host = host.lowercaseString;
    if ([host isEqualToString:@"spclient.wg.spotify.com"]) return YES;
    NSString *suffix = @"-spclient.spotify.com";
    if (![host hasSuffix:suffix] || host.length == suffix.length) return NO;
    NSString *region = [host substringToIndex:host.length - suffix.length];
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyz0123456789"];
    return [region rangeOfCharacterFromSet:allowed.invertedSet].location == NSNotFound;
}

static void rememberHeaders(NSURLSession *session, NSURLRequest *request) {
    if (![request.URL.scheme.lowercaseString isEqualToString:@"https"] || !isSpclientHost(request.URL.host)) return;
    NSMutableDictionary<NSString *, NSString *> *all = [NSMutableDictionary dictionary];
    [session.configuration.HTTPAdditionalHeaders enumerateKeysAndObjectsUsingBlock:^(id key, id value, BOOL *stop) {
        if ([key isKindOfClass:NSString.class] && [value isKindOfClass:NSString.class]) all[[key lowercaseString]] = value;
    }];
    [request.allHTTPHeaderFields enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *value, BOOL *stop) {
        all[key.lowercaseString] = value;
    }];
    if (!all[@"authorization"]) return;
    NSMutableDictionary<NSString *, NSString *> *headers = [NSMutableDictionary dictionary];
    for (NSUInteger i = 0; i < sizeof(kSpclientHeaders) / sizeof(*kSpclientHeaders); i++) {
        NSString *name = kSpclientHeaders[i];
        if (all[name]) headers[name] = all[name];
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        sg_spclientHeaders = headers;
        NSArray *waiting = sg_headersWaiting;
        sg_headersWaiting = nil;
        for (void (^waiter)(NSDictionary<NSString *, NSString *> *) in waiting) waiter(headers);
    });
}

void SGSpclientHeaders(void (^use)(NSDictionary<NSString *, NSString *> *headers)) {
    if (sg_spclientHeaders) {
        use(sg_spclientHeaders);
        return;
    }
    if (!sg_headersWaiting) sg_headersWaiting = [NSMutableArray array];
    [sg_headersWaiting addObject:[use copy]];
}

static SPTPlayerState *playerState(void);
static NSString *idOf(SPTPlayerTrack *track);
static void keep(NSString *track, NSArray<SGKaraokeLine *> *lines, BOOL fromStore);
// Pending or displaying an automatic local sheet. Never translate it online or write it over
// the ordinary offline sheet. An explicit choice supersedes even a lookup still in flight.
static NSString *const fileAuthority = @"Retrine.fileLyrics";
static BOOL hasChoice(NSString *track) {
    return SGLyricsPinnedID(track) != nil || SGLyricsChosenSource(track) != nil;
}

// Lines with no translation of their own take Musixmatch's community ones in the Lyrics page's language,
// whichever source they came from, Spotify's own included, matched by their text. Only the redesign shows
// translations, so the native look asks for none. The translated lines are copies kept in place of the
// lines: the lyrics view measures lines off the main thread, and a new array is what tells it to look.
// Musixmatch answers at once once it has answered, so lines kept again take the translations straight away.
static void translate(NSString *track) {
    NSString *language = SGRedesignedUI() ? SGLyricsTranslationLanguage() : nil;
    if (!language || SGLyricsHasTranslations(sg_lyrics[track])) return;
    NSUInteger generation = SGLyricsPinGeneration(track);
    SGMusixmatchTranslations(track, language, ^(NSDictionary<NSString *, NSString *> *byLine) {
        if (generation != SGLyricsPinGeneration(track) || sg_sheetAuthorities[track] == fileAuthority) return;
        // Whatever is kept by now, which may be Spotify's timed lines in place of the plain ones asked for.
        NSArray<SGKaraokeLine *> *kept = sg_lyrics[track];
        if (!byLine || !kept.count || ![language isEqualToString:SGLyricsTranslationLanguage()]
            || SGLyricsHasTranslations(kept)) return;
        NSArray<SGKaraokeLine *> *translated = SGMusixmatchTranslatedLines(kept, byLine);
        for (NSUInteger i = 0; i < translated.count; i++) {
            SGKaraokeLine *line = translated[i];
            if (line != kept[i]) line.translationLanguage = language;
        }
        if (translated) keep(track, translated, NO);
    });
}

NSNotificationName const SGKaraokeLinesKeptNotification = @"spotifyglass.karaoke.linesKept";

// Request marks without a retained sheet need their own budget. Active asks/backoffs are never evicted.
static void pruneRequested(NSString *newest) {
    NSMutableSet<NSString *> *completed = [sg_requested mutableCopy];
    [completed minusSet:sg_asking];
    [completed minusSet:sg_looking];
    NSString *playing;
    @synchronized (sg_seenTracks) { playing = sg_lastSeenID; }
    NSUInteger count = completed.count;
    for (NSString *track in completed) {
        if (count <= kCompletedRequests) break;
        if ([track isEqualToString:playing] || [track isEqualToString:newest]) continue;
        [sg_requested removeObject:track];
        if (!sg_lyrics[track]) [sg_sampledLocalPaths removeObjectForKey:track];
        [sg_losses removeObjectForKey:track];
        [sg_sourceRetries removeObjectForKey:track];
        count--;
    }
}

// Main queue only.
static void announce(NSString *track) {
    pruneRequested(track);
    [NSNotificationCenter.defaultCenter postNotificationName:SGKaraokeLinesKeptNotification object:track];
}

BOOL SGKaraokeLooking(NSString *trackID) {
    return trackID && [sg_looking containsObject:trackID];
}

// Main queue only. A full cache is emptied but for the track playing, the one up next and those still
// being asked for; what goes can be asked for again.
static void keep(NSString *track, NSArray<SGKaraokeLine *> *lines, BOOL fromStore) {
    if (lines.firstObject.fileOwned) {
        if (!sg_sheetAuthorities) sg_sheetAuthorities = [NSMutableDictionary dictionary];
        sg_sheetAuthorities[track] = fileAuthority;
    } else if (!sg_sheetAuthorities[track]) {
        id authority = SGLyricsPersistenceAuthority(track);
        if (authority) {
            if (!sg_sheetAuthorities) sg_sheetAuthorities = [NSMutableDictionary dictionary];
            sg_sheetAuthorities[track] = NSNull.null;
        }
    }
    // Provider decoding can finish after a target change. Never mutate a source's cached
    // result or the old snapshot a layout worker is still measuring.
    lines = SGLyricsProviderTranslationsForLanguage(lines, SGLyricsTranslationLanguage());
    [sg_sourceRetries removeObjectForKey:track];
    if (sg_storeRequests[track]) {
        [sg_storeRequests removeObjectForKey:track];
        [sg_asking removeObject:track];
    }
    SGKaraokeCancelStoreWrite(track);
    if (sg_lyrics.count >= kKeptTracks && !sg_lyrics[track]) {
        NSMutableSet<NSString *> *spared = [sg_asking mutableCopy];
        SPTPlayerState *state = playerState();
        NSString *playing = idOf(state.track), *next = idOf(SGPlayerUpNextIn(state));
        if (playing) [spared addObject:playing];
        if (next) [spared addObject:next];
        for (NSString *kept in sg_lyrics.allKeys) {
            if ([spared containsObject:kept]) continue;
            [sg_lyrics removeObjectForKey:kept];
            [sg_sheetAuthorities removeObjectForKey:kept];
            [sg_sampledLocalPaths removeObjectForKey:kept];
            [sg_requested removeObject:kept];
            [sg_requests removeObjectForKey:kept];
            SGLyricsForgetAnswer(kept);
        }
    }
    sg_lyrics[track] = SGKaraokeInTimeOrder(lines);
    id authority = sg_sheetAuthorities[track];
    if (!fromStore && authority != fileAuthority && lines.count && !SGLocalFileIs(track) && SGFlag(SGKeyLyricsOffline, YES) && SGLyricsMayPersist(track, authority)) {
        if (!sg_storeWrites) sg_storeWrites = [NSMutableDictionary dictionary];
        SGLyricsLease *token = [SGLyricsLease new];
        sg_storeWrites[track] = token;
        NSUInteger generation = SGLyricsPinGeneration(track);
        // Most callers set the provider immediately after keep; pins set it before.
        // End-of-turn capture supports both without changing every producer's API.
        dispatch_async(dispatch_get_main_queue(), ^{
            if (sg_storeWrites[track] != token) return;
            if (generation != SGLyricsPinGeneration(track) || !SGLyricsMayPersist(track, authority)) return;
            if (SGFlag(SGKeyLyricsOffline, YES)) SGLyricsStoreSaveWithLease(track, lines, SGLyricsCreditFor(track), token);
        });
    }
    // Saved lines take their translations as fresh ones do: offline, the ask simply goes unanswered.
    if (lines.count && authority != fileAuthority) translate(track);
    announce(track);
}

void SGKaraokeKeepLines(NSString *track, NSArray<SGKaraokeLine *> *lines) {
    if (!track.length) return;
    void (^save)(void) = ^{
        if (!sg_lyrics) sg_lyrics = [NSMutableDictionary dictionary];
        id authority = SGLyricsPersistenceAuthority(track);
        if (authority) {
            if (!sg_sheetAuthorities) sg_sheetAuthorities = [NSMutableDictionary dictionary];
            sg_sheetAuthorities[track] = NSNull.null;
        }
        keep(track, lines, NO);
    };
    if (NSThread.isMainThread) save();
    else dispatch_async(dispatch_get_main_queue(), save);
}

BOOL SGKaraokeKeepSourceLines(NSString *track, NSArray<SGKaraokeLine *> *lines, SGLyricsResult *answer) {
    if (sg_sheetAuthorities[track] == fileAuthority && !hasChoice(track)) return NO;
    id current = SGLyricsKeptAnswer(track);
    if (![current isKindOfClass:SGLyricsResult.class] || !SGLyricsSameSheet(answer, current)) return NO;
    if (!sg_lyrics) sg_lyrics = [NSMutableDictionary dictionary];
    if (!sg_sheetAuthorities) sg_sheetAuthorities = [NSMutableDictionary dictionary];
    sg_sheetAuthorities[track] = answer;
    SGLyricsSetCredit(track, answer.provider);
    keep(track, lines, NO);
    return YES;
}

NSArray<SGKaraokeLine *> *SGKaraokeSpotifyLines(NSString *track) {
    return [SGLyricsCreditFor(track) isEqualToString:@"Spotify"] ? sg_lyrics[track] : nil;
}

void SGKaraokeKeepSpotifyLines(NSString *track, NSArray<SGKaraokeLine *> *lines) {
    if (sg_sheetAuthorities[track] == fileAuthority && !hasChoice(track)) return;
    SGLyricsResult *answer = SGLyricsAcceptSpotify(track, lines, sg_sheetAuthorities[track]);
    SGKaraokeKeepSourceLines(track, lines, answer);
}

void SGKaraokeDeferPersistence(NSString *track) {
    if (!sg_lyrics[track] || sg_sheetAuthorities[track] == fileAuthority) return;
    if (!sg_sheetAuthorities) sg_sheetAuthorities = [NSMutableDictionary dictionary];
    sg_sheetAuthorities[track] = NSNull.null;
    SGKaraokeCancelStoreWrite(track);
}

static void forgetKeeper(NSString *trackID) {
    if (!trackID.length) return;
    [sg_sampledLocalPaths removeObjectForKey:trackID];
    [sg_storeRequests removeObjectForKey:trackID];
    SGKaraokeCancelStoreWrite(trackID);
    [sg_lyrics removeObjectForKey:trackID];
    [sg_sheetAuthorities removeObjectForKey:trackID];
    [sg_requested removeObject:trackID];
    [sg_asking removeObject:trackID];
    [sg_looking removeObject:trackID];
    [sg_losses removeObjectForKey:trackID];
    [sg_sourceRetries removeObjectForKey:trackID];
    [sg_requests removeObjectForKey:trackID];
}

void SGKaraokeForgetLyrics(NSString *trackID) {
    if (!trackID.length) return;
    forgetKeeper(trackID);
    SGLyricsForgetAnswer(trackID);
    SGLyricsStoreDelete(trackID);
}

void SGKaraokeCancelStoreWrite(NSString *track) {
    if (!track.length) return;
    [sg_storeWrites[track] invalidate];
    [sg_storeWrites removeObjectForKey:track];
}

static void received(NSURLSession *session, NSURLSessionTask *task, NSData *data) {
    rememberHeaders(session, task.currentRequest);
    if (sg_ownSources || !SGLyricsTrackInURL(task.currentRequest.URL)) return;
    NSMutableData *body = objc_getAssociatedObject(task, &kBodyKey);
    if (!body) objc_setAssociatedObject(task, &kBodyKey, (body = [NSMutableData data]), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [body appendData:data];
}

static void completed(NSURLSessionTask *task, NSError *error) {
    NSMutableData *body = objc_getAssociatedObject(task, &kBodyKey);
    if (!body) {
        NSString *path = task.currentRequest.URL.path;
        if (!sg_ownSources && [path.lowercaseString containsString:@"lyrics"]) SGLog(@"karaoke: lyrics request not read: %@ (error %@)", path, error);
        return;
    }
    objc_setAssociatedObject(task, &kBodyKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    NSString *track = SGLyricsTrackInURL(task.currentRequest.URL);
    if (error || !track) return;
    NSArray<SGKaraokeLine *> *lines = SGKaraokeLinesFromBody(body);
    SGLog(@"karaoke: lyrics for %@, %lu bytes, %lu synced lines", track, (unsigned long)body.length, (unsigned long)lines.count);
    if (lines) dispatch_async(dispatch_get_main_queue(), ^{
        if (!SGLyricsPinnedID(track)) SGKaraokeKeepSpotifyLines(track, lines);
    });
}

NSArray<SGKaraokeLine *> *SGKaraokeLinesForTrack(NSString *trackID) {
    return trackID ? sg_lyrics[trackID] : nil;
}

// Main queue only. The track stays asked for through the pause, so the readers asking on every tick
// send nothing until it is over.
static void askAgainLater(NSString *trackID, BOOL automatic) {
    NSObject *request = sg_requests[trackID];
    NSUInteger losses = sg_losses[trackID].unsignedIntegerValue;
    if (losses >= kSourceRetries) {
        [sg_asking removeObject:trackID];
        [sg_requests removeObjectForKey:trackID];
        return;
    }
    sg_losses[trackID] = @(losses + 1);
    NSTimeInterval pause = MIN(kRetryPause * pow(2, losses), kRetryPauseMost);
    SGLog(@"karaoke: lyrics for %@ not answered, may ask again in %.0fs", trackID, pause);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(pause * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (sg_requests[trackID] != request) return;
        [sg_asking removeObject:trackID];
        [sg_requested removeObject:trackID];
        if (!sg_lyrics[trackID]) [sg_sampledLocalPaths removeObjectForKey:trackID];
        [sg_requests removeObjectForKey:trackID];
        // Returning before the pause ended must not leave the playing track waiting for a reader's tick.
        if (automatic && UIApplication.sharedApplication.applicationState == UIApplicationStateActive
            && [trackID isEqualToString:SGKaraokePlayingTrack()]) SGKaraokeRequestLyrics(trackID);
    });
}

static void retrySourcesLater(NSString *trackID) {
    if (SGLyricsRecovering(trackID)) {
        [sg_asking removeObject:trackID];
        [sg_requests removeObjectForKey:trackID];
        return;
    }
    if (!sg_sourceRetries) sg_sourceRetries = [NSMutableDictionary dictionary];
    NSUInteger retries = sg_sourceRetries[trackID].unsignedIntegerValue;
    sg_sourceRetries[trackID] = @(MIN(retries + 1, kSourceRetries + 1));
    if (retries >= kSourceRetries) {
        [sg_asking removeObject:trackID];
        [sg_requests removeObjectForKey:trackID];
        return; // Keep the requested mark: display-link readers are not a recovery signal.
    }
    askAgainLater(trackID, YES);
}

// Recovery releases only an exhausted source retry budget, never an ask or a backoff still in flight.
static BOOL resumeSourceRetries(NSString *trackID) {
    if (!trackID || sg_sourceRetries[trackID].unsignedIntegerValue <= kSourceRetries) return NO;
    [sg_sourceRetries removeObjectForKey:trackID];
    [sg_losses removeObjectForKey:trackID];
    [sg_requested removeObject:trackID];
    return YES;
}

// Whether a loaded image has this file name; EeveeSpotify's Reincarnated fork also loads EeveeSwiftProtobuf.
static BOOL imageLoaded(NSString *wanted) {
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const char *image = _dyld_get_image_name(i);
        if (image && [@(image).lastPathComponent caseInsensitiveCompare:wanted] == NSOrderedSame) return YES;
    }
    return NO;
}

// Only loaded code counts, never a file's name: an IPA can keep EeveeSpotify's icons
// (EeveeSpotifyAnime@2x.png) after its dylib is gone. EeveeSpotify ships as EeveeSpotify.dylib, but an
// IPA builder can rename it (EeveeSpotify-6.6.dylib) or wrap it as EeveeSpotify.framework, so its Swift
// settings page, which every fork keeps under the module EeveeSpotify, counts as well. It may load after
// the mod, so a NO is asked again, though only once more images have loaded, and a YES is kept.
BOOL SGEeveeSpotifyInjected(void) {
    static BOOL found;
    static uint32_t looked;
    uint32_t images = _dyld_image_count();
    if (found || images == looked) return found;
    looked = images;
    if (imageLoaded(@"EeveeSpotify.dylib") || objc_getClass("_TtC12EeveeSpotify27EeveeSettingsViewController")) {
        found = YES;
        SGLog(@"lyrics: EeveeSpotify is injected");
    }
    return found;
}

// Whether EeveeSpotify answers Spotify's lyrics, read from its own settings in the standard defaults.
// It decides at launch and asks for a restart to change, so the first answer is kept. Anything not
// known to turn its lyrics off counts as on, a missing key and an unknown version included.
static BOOL eeveeLyricsOn(void) {
    static BOOL on;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
        id source = [defaults objectForKey:@"lyricsSource"];      // 4 is "Do not replace lyrics"
        id patch = [defaults objectForKey:@"patchType"];          // Reincarnated: 0 not set, 1 off, 2 on
        BOOL sourceOff = [source isKindOfClass:NSNumber.class] && [source integerValue] == 4;
        BOOL unpatched = imageLoaded(@"EeveeSwiftProtobuf") && [patch isKindOfClass:NSNumber.class]
                      && ([patch integerValue] == 0 || [patch integerValue] == 1);
        on = !(getenv("EEVEE_DISABLE_ALL") || sourceOff || unpatched);
        SGLog(@"lyrics: EeveeSpotify's lyrics are %@ (lyricsSource %@, patchType %@)", on ? @"on" : @"off", source, patch);
    });
    return on;
}

BOOL SGLyricsStandAsideForEevee(void) {
    return SGEeveeSpotifyInjected() && eeveeLyricsOn() && !SGHidden(SGKeyLyricsBesideEevee);
}

BOOL SGEeveeLyricsOn(void) {
    return SGEeveeSpotifyInjected() && eeveeLyricsOn();
}

// Main queue only. NO, asking nothing, before any request of Spotify's has shown the headers, and with
// EeveeSpotify injected, whose lyrics answer the request: a second asker beside it froze Spotify after launch.
static BOOL requestFromSpotify(NSString *trackID) {
    NSDictionary<NSString *, NSString *> *headers = sg_spclientHeaders;
    if (!headers || SGLyricsStandAsideForEevee()) return NO;
    if ([headers[@"authorization"] isEqual:sg_refusedAuthorization]) {
        SGLyricsNoteSpotifyLoadFailure(trackID, YES);
        return NO;
    }
    if (!sg_requests) sg_requests = [NSMutableDictionary dictionary];
    NSObject *token = [NSObject new];
    sg_requests[trackID] = token;
    [sg_requested addObject:trackID];
    [sg_asking addObject:trackID];
    [sg_looking addObject:trackID];
    NSString *address = [NSString stringWithFormat:@"https://spclient.wg.spotify.com/color-lyrics/v2/track/%@?format=json&vocalRemoval=false&market=from_token", trackID];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:address]];
    request.timeoutInterval = SGLyricsRequestTimeoutSeconds;
    [headers enumerateKeysAndObjectsUsingBlock:^(NSString *name, NSString *value, BOOL *stop) {
        [request setValue:value forHTTPHeaderField:name];
    }];
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    // The mod's own, so LyricsHook's request hook does not send it to the donor.
    [NSURLProtocol setProperty:@YES forKey:SGLyricsOwnRequestKey inRequest:request];
    [[NSURLSession.sharedSession dataTaskWithRequest:request completionHandler:^(NSData *body, NSURLResponse *response, NSError *error) {
        NSArray<SGKaraokeLine *> *lines = SGKaraokeLinesFromBody(body);
        NSInteger status = [response isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)response).statusCode : 0;
        SGLog(@"karaoke: fetched lyrics for %@: status %ld, %lu lines (%@), error %@", trackID,
              (long)status, (unsigned long)lines.count,
              SGKaraokeLinesTiming(lines) == SGKaraokeTimingNone ? @"untimed" : @"line timed", error);
        // A refused authorization is lost too: the captured one may have expired, and Spotify's next
        // spclient request brings a fresh one.
        BOOL lost = SGLyricsReplyFailed(response, error) || status == 401 || status == 403;
        lost = lost || (status == 200 && !lines);
        dispatch_async(dispatch_get_main_queue(), ^{
            if (sg_requests[trackID] != token) return;
            [sg_looking removeObject:trackID];
            SGLyricsNoteSpotifyLoadFailure(trackID, lost);
            // The walk deliberately did not keep a failed/unfinished empty answer. Spotify's own
            // absence must not turn that into a permanent requested mark either.
            BOOL retrySources = !lines && (sg_ownSources || SGLyricsPinnedID(trackID)) && !SGLyricsKeptAnswer(trackID);
            if (status == 401) {
                sg_refusedAuthorization = headers[@"authorization"];
                [sg_requests removeObjectForKey:trackID];
                [sg_requested removeObject:trackID];
                [sg_asking removeObject:trackID];
            } else if (lost) {
                askAgainLater(trackID, NO);
            } else if (retrySources) {
                retrySourcesLater(trackID);
            } else {
                [sg_requests removeObjectForKey:trackID];
                [sg_asking removeObject:trackID];
                [sg_losses removeObjectForKey:trackID];
                [sg_sourceRetries removeObjectForKey:trackID];
                // Asked after the chain found plain text only: Spotify's replace it only when they are timed,
                // and never a source picked for the track from the player's ⋯ that answered.
                NSArray<SGKaraokeLine *> *kept = sg_lyrics[trackID];
                id answer = SGLyricsKeptAnswer(trackID);
                BOOL picked = [answer isKindOfClass:SGLyricsResult.class] && [(SGLyricsResult *)answer picked];
                if (SGLyricsUseSpotify(kept, lines, picked)) {
                    SGKaraokeKeepSpotifyLines(trackID, lines);
                    return;
                }
            }
            announce(trackID);
        });
    }] resume];
    return YES;
}

// Main queue only. The track's lines are forgotten, but for a look still out, and the track playing is asked
// for again as on a first play.
void SGKaraokeAskAgain(NSString *trackID) {
    if (!trackID || [sg_looking containsObject:trackID]) return;
    [sg_sampledLocalPaths removeObjectForKey:trackID];
    [sg_lyrics removeObjectForKey:trackID];
    [sg_sheetAuthorities removeObjectForKey:trackID];
    [sg_requested removeObject:trackID];
    [sg_asking removeObject:trackID];
    [sg_losses removeObjectForKey:trackID];
    [sg_sourceRetries removeObjectForKey:trackID];
    if ([trackID isEqualToString:SGKaraokePlayingTrack()]) SGKaraokeRequestLyrics(trackID);
    announce(trackID);
}

void SGKaraokeAskSpotifyForTiming(NSString *trackID) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!trackID || [sg_requested containsObject:trackID] || SGLyricsPinnedID(trackID)) return;
        requestFromSpotify(trackID);
    });
}

// A local file the sources had nothing for is asked again this many times, on askAgainLater's pauses:
// nothing may mean a request was lost, and LRCLIB asked alone cannot say which it was, so a song it has
// nothing for is not asked for every minute while it plays. ponytail: an outage longer than the pauses
// (about two minutes) leaves the file without lyrics until its names are edited or Spotify restarts; a
// source answer that tells "lost" from "none" would lift that.
static const NSUInteger kLocalTries = 4;

// With no source of the mod's switched on, a local file still gets LRCLIB, the open and keyless floor of
// the order, by the names it goes by: spclient has nothing for it, and without this the redesign's
// lyrics, the lock screen and the Live Activity would have nothing to show. Answers NO, asking nothing,
// when the file has no title and artist to search with.
static BOOL askLrcLib(NSString *trackID, void (^done)(SGLyricsResult *lyrics)) {
    NSDictionary *info = SGLocalFileInfo(trackID);
    SGLyricsProvider *lrclib = SGLyricsProviderFor(@"lrclib");
    if (!lrclib.ask || ![info[@"title"] length] || ![info[@"artist"] length]) return NO;
    SGLyricsQuery *query = [SGLyricsQuery new];
    query.trackID = trackID;
    query.title = info[@"title"];
    query.artist = info[@"artist"];
    query.album = info[@"album"];
    query.seconds = [info[@"seconds"] integerValue];
    SGLog(@"karaoke: no source is on, asking LRCLIB for the local file \"%@\" by \"%@\"", query.title, query.artist);
    lrclib.ask(query, ^(SGLyricsResult *lyrics) {
        if (lyrics.karaokeLines && !lyrics.provider) lyrics.provider = lrclib.name;
        done(lyrics);
    });
    return YES;
}

static void requestLyrics(NSString *trackID, BOOL tryStore, BOOL tryImported) {
    if (!trackID || sg_lyrics[trackID] || [sg_requested containsObject:trackID]
        || sg_sourceRetries[trackID].unsignedIntegerValue > kSourceRetries) return;
    // spclient has nothing for a local file, which only the sources can name. A file of the user's own,
    // linked to it or matching its names, comes before every source.
    BOOL local = SGLocalFileIs(trackID);
    BOOL pinned = hasChoice(trackID);
    if (tryImported && !pinned && (local || SGImportedLRCLinkedTo(trackID))) {
        if (!sg_sheetAuthorities) sg_sheetAuthorities = [NSMutableDictionary dictionary];
        sg_sheetAuthorities[trackID] = fileAuthority;
        if (!sg_requests) sg_requests = [NSMutableDictionary dictionary];
        NSObject *token = [NSObject new];
        sg_requests[trackID] = token;
        [sg_requested addObject:trackID];
        [sg_asking addObject:trackID];
        [sg_looking addObject:trackID];
        SPTPlayerTrack *track = local ? SGKaraokeTrackFor(trackID) : nil;
        NSString *path = nil;
        if (local) {
            SPTPlayerTrack *playing = playerState().track;
            if ([idOf(playing) isEqual:trackID]) track = playing;
            id raw = track.metadata[@"local_file_path"];
            if ([raw isKindOfClass:NSString.class]) path = [raw copy];
            if (!sg_sampledLocalPaths) sg_sampledLocalPaths = [NSMutableDictionary dictionary];
            sg_sampledLocalPaths[trackID] = path;
        }
        SGPlaybackLyricsFetch(trackID, path, ^(SGLyricsResult *imported) {
            if (sg_requests[trackID] != token) return;
            [sg_requests removeObjectForKey:trackID];
            [sg_asking removeObject:trackID];
            [sg_looking removeObject:trackID];
            if (hasChoice(trackID)) return;
            if (imported) {
                SGLyricsSetCredit(trackID, imported.provider);
                keep(trackID, imported.karaokeLines, NO);
                return;
            }
            [sg_sheetAuthorities removeObjectForKey:trackID];
            [sg_requested removeObject:trackID];
            requestLyrics(trackID, tryStore, NO);
        });
        return;
    }
    if (tryStore && !local && SGFlag(SGKeyLyricsOffline, YES)) {
        if (!sg_requested) sg_requested = [NSMutableSet set];
        if (!sg_asking) sg_asking = [NSMutableSet set];
        if (!sg_storeRequests) sg_storeRequests = [NSMutableDictionary dictionary];
        NSObject *token = [NSObject new];
        sg_storeRequests[trackID] = token;
        [sg_requested addObject:trackID];
        [sg_asking addObject:trackID];
        SGLyricsStoreLoad(trackID, ^(NSArray<SGKaraokeLine *> *lines, NSString *credit, SGLyricsResult *metadata) {
            if (sg_storeRequests[trackID] != token) return;
            [sg_storeRequests removeObjectForKey:trackID];
            [sg_asking removeObject:trackID];
            if (sg_lyrics[trackID]) return;
            if (lines.count && SGFlag(SGKeyLyricsOffline, YES)) {
                if (!sg_lyrics) sg_lyrics = [NSMutableDictionary dictionary];
                if (metadata) SGLyricsNoteCredit(metadata);
                keep(trackID, lines, YES);
                SGLyricsSetCredit(trackID, credit);
                // Plain text was saved: Spotify is asked whether it has the song timed, as when the sources found it.
                if (SGKaraokeLinesTiming(lines) == SGKaraokeTimingNone) {
                    [sg_requested removeObject:trackID];
                    SGKaraokeAskSpotifyForTiming(trackID);
                }
                return;
            }
            [sg_requested removeObject:trackID];
            requestLyrics(trackID, NO, NO); // A miss continues exactly once, without another disk look.
        });
        return;
    }
    if (!sg_ownSources && !local && !pinned) {
        requestFromSpotify(trackID);
        return;
    }
    [sg_requested addObject:trackID];
    [sg_asking addObject:trackID];
    [sg_looking addObject:trackID];
    if (!sg_requests) sg_requests = [NSMutableDictionary dictionary];
    NSObject *token = [NSObject new];
    sg_requests[trackID] = token;
    void (^answered)(SGLyricsResult *) = ^(SGLyricsResult *lyrics) {
        if (sg_requests[trackID] != token) return;
        [sg_looking removeObject:trackID];
        if (lyrics.instrumental) {
            [sg_requests removeObjectForKey:trackID];
            [sg_asking removeObject:trackID];
            [sg_losses removeObjectForKey:trackID];
            if (sg_ownSources || pinned) {
                SGKaraokeKeepSourceLines(trackID, @[], lyrics);
            } else {
                keep(trackID, @[], NO);
                SGLyricsSetCredit(trackID, lyrics.provider);
            }
            return;
        }
        if (lyrics.karaokeLines) {
            [sg_asking removeObject:trackID];
            [sg_losses removeObjectForKey:trackID];
            if (sg_ownSources || pinned) {
                if (!SGKaraokeKeepSourceLines(trackID, lyrics.karaokeLines, lyrics)) return;
            } else {
                keep(trackID, lyrics.karaokeLines, NO);
                SGLyricsSetCredit(trackID, lyrics.provider);
            }
            // Plain text is shown while Spotify is asked whether it has the song timed; it has no local file.
            if (local || pinned || SGKaraokeLinesTiming(lyrics.karaokeLines) != SGKaraokeTimingNone) {
                [sg_requests removeObjectForKey:trackID];
                return;
            }
        } else if (local) {
            // Asked again after a pause; a miss the sources keep answers at once then. An instrumental, or
            // a file out of tries, is left asked for: the readers ask on every tick, and an edit of its
            // names gives it a new key.
            if (!lyrics.instrumental && sg_losses[trackID].unsignedIntegerValue < kLocalTries) askAgainLater(trackID, NO);
            else {
                [sg_asking removeObject:trackID];
                [sg_requests removeObjectForKey:trackID];
            }
            announce(trackID);
            return;
        }
        [sg_asking removeObject:trackID];
        [sg_requested removeObject:trackID];
        // Spotify is asked next, so the look goes on; with nothing to ask it with, it is over.
        if (!requestFromSpotify(trackID)) {
            if (!lyrics && !SGLyricsKeptAnswer(trackID)) {
                [sg_requested addObject:trackID];
                [sg_asking addObject:trackID];
                retrySourcesLater(trackID);
            } else [sg_requests removeObjectForKey:trackID];
            announce(trackID);
        }
    };
    if (sg_ownSources || pinned) {
        SGLyricsFetch(trackID, answered);
    } else if (!askLrcLib(trackID, answered)) {
        [sg_requests removeObjectForKey:trackID];
        [sg_asking removeObject:trackID];
        [sg_looking removeObject:trackID];
        announce(trackID);
    }
}

id SGKaraokePlayer(void) {
    return sg_player;
}

static SPTPlayerState *playerState(void) {
    SPTPlayerState *reported = SGPlayerState();
    if (reported) return reported;
    id player = sg_player;
    return [player respondsToSelector:@selector(state)] ? [(id<SPTPlayer>)player state] : nil;
}

NSString *SGKaraokePlayingTrack(void) {
    return idOf(playerState().track);
}

NSInteger SGKaraokePositionMs(void) {
    SPTPlayerState *state = playerState();
    if (!state) return -1;
    return (NSInteger)((state.isPaused ? state.positionAsOfTimestamp : state.position) * 1000);
}

NSInteger SGKaraokeDelayMs(void) {
    setUpOffsets();
    NSString *track;
    @synchronized (sg_seenTracks) { track = sg_lastSeenID; }
    @synchronized (sg_offsetsLock) {
        return sg_delay + (track ? sg_trackOffsets[track].integerValue : 0)
                        + (sg_routeUID ? sg_routeOffsets[sg_routeUID].integerValue : 0);
    }
}

void SGKaraokeSeek(NSInteger ms) {
    ms = MAX(0, ms);
    id player = sg_player;
    if (![player respondsToSelector:@selector(seekTo:)]) {
        SGLog(@"seek: to %ld ms, but no player to seek", (long)ms);
        return;
    }
    // Where it was and where it is half a second on, with Karaoke's lead and the correction it takes off, so the log
    // says whether a seek lands where it was sent.
    SPTPlayerState *state = playerState();
    NSInteger before = SGKaraokePositionMs();
    NSString *lead = [NSString stringWithFormat:@"Karaoke holds %.2f s, takes %.2f s off", SGSingHeldLead(), state ? SGSingLeadOf(state) : 0];
    [(id<SPTPlayer>)player seekTo:ms / 1000.0];
    SGLog(@"seek: to %ld ms (sent %.3f s to %@) from %ld ms; %@", (long)ms, ms / 1000.0, [player class], (long)before, lead);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        SPTPlayerState *now = playerState();
        SGLog(@"seek: half a second after the seek to %ld ms the position reads %ld ms (%ld ms off); Karaoke holds %.2f s, takes %.2f s off", (long)ms,
              (long)SGKaraokePositionMs(), (long)(SGKaraokePositionMs() - ms - 500), SGSingHeldLead(), now ? SGSingLeadOf(now) : 0);
    });
}

// A Spotify track by its base62 id, a local file by its URI (Shared/LocalFiles/LocalFiles.h).
// The id is kept on the track, which the page asks for on every frame; a local file's key is not,
// as a rename changes it.
static char sg_trackIDKey;
static NSString *idOf(SPTPlayerTrack *track) {
    NSString *kept = track ? objc_getAssociatedObject(track, &sg_trackIDKey) : nil;
    if (kept) return kept;
    id uri = track.URI;
    NSString *text = [uri isKindOfClass:NSURL.class] ? ((NSURL *)uri).absoluteString : [uri description];
    if (![text hasPrefix:@"spotify:track:"]) return SGLocalFileLyricsKey(text);
    NSString *trackID = [text substringFromIndex:@"spotify:track:".length];
    objc_setAssociatedObject(track, &sg_trackIDKey, trackID, OBJC_ASSOCIATION_RETAIN);
    return trackID;
}

// Tracks come in from the player and from every list that reads their metadata, so when the table
// is full it is emptied, all but the track playing, whose name the next lyrics request needs.
void SGKaraokeRequestLyrics(NSString *trackID) {
    requestLyrics(trackID, YES, YES);
}

static void importsChanged(NSArray<NSString *> *uris) {
    NSString *playing = SGKaraokePlayingTrack();
    NSMutableSet *affected = [NSMutableSet set];
    for (NSString *uri in uris) {
        if ([uri hasPrefix:@"spotify:track:"]) [affected addObject:[uri substringFromIndex:@"spotify:track:".length]];
        else if (SGLocalFileIs(uri)) [affected addObject:SGLocalFileLyricsKey(uri)];
    }
    for (NSString *key in [sg_requested setByAddingObjectsFromArray:sg_lyrics.allKeys])
        if (SGLocalFileIs(key)) [affected addObject:key];
    if (SGLocalFileIs(playing)) [affected addObject:playing];
    for (NSString *key in affected) {
        SGLyricsForgetAutomaticFallback(key);
        if (SGLyricsPinnedID(key)) continue;
        NSString *choice = SGLyricsChosenSource(key);
        if (choice && ![choice isEqual:SGImportedLRCKey]) continue;
        if (choice) {
            if (!SGImportedLRCLinkedTo(key)) SGLyricsDropChoice(key, choice);
        }
        forgetKeeper(key);
        SGLyricsForgetAnswerForImportChange(key);
        if ([key isEqual:playing]) SGKaraokeRequestLyrics(key);
        announce(key);
    }
}

static void remember(SPTPlayerTrack *track, NSString *trackID) {
    @synchronized (sg_seenTracks) {
        if (sg_seenTracks.count >= kSeenTracks) {
            [sg_seenTracks removeAllObjects];
            SPTPlayerTrack *playing = sg_lastSeen;
            NSString *playingID = playing ? idOf(playing) : nil;
            if (playingID) sg_seenTracks[playingID] = playing;
        }
        sg_seenTracks[trackID] = track;
    }
}

SPTPlayerTrack *SGKaraokeTrackFor(NSString *trackID) {
    if (!trackID) return nil;
    @synchronized (sg_seenTracks) { return sg_seenTracks[trackID]; }
}

void SGKaraokeRememberTrack(SPTPlayerTrack *track, NSString *trackID) {
    if (sg_seenTracks && trackID) remember(track, trackID);
}

// With a source of the mod's on, the walk for a track starts the moment the player moves to it and,
// for the track after it, while this one still plays: Spotify asks for a track's lyrics within a
// beat of starting it and gives its card list about a second to load, so an answer that is already
// in is what puts the card there. The track is named here, so no walk waits for a name.
BOOL SGLyricsBackgroundNeeded(void) {
    return SGFlag(SGKeyLockScreenLyrics, NO) || SGLockArtworkShowsLyrics(SGLockScreenArtwork())
        || SGLiveActivityLyricsActive() || SGLyricsPiPActive() || SGLyricsPiPStarting();
}

static BOOL mayPrefetchLyrics(void) {
    return UIApplication.sharedApplication.applicationState == UIApplicationStateActive || SGLyricsBackgroundNeeded();
}

static void prefetch(NSString *trackID) {
    if (!mayPrefetchLyrics()) return;
    // Spotify never asks for a local file's lyrics, so they are asked for and kept here, a source of the
    // mod's on or not (SGKaraokeRequestLyrics). The state is read on any thread, and the kept lines are
    // the main queue's.
    BOOL local = SGLocalFileIs(trackID);
    if (local || (SGImportedLRCLinkedTo(trackID) && !hasChoice(trackID))) {
        SGKaraokeRequestLyrics(trackID);
        return;
    }
    if (!sg_ownSources) return;
    if (!local) SGLyricsPrefetch(trackID);
}

// A state the player reported or was asked for: a new track is remembered and its walk begun. From the
// -state hook on any thread, and from the player's own reports on the main one.
static void seen(SPTPlayerState *state) {
    SPTPlayerTrack *track = state.track;
    if (!track) {
        @synchronized (sg_seenTracks) { sg_lastSeen = nil; sg_lastSeenID = nil; }
        return;
    }
    NSString *trackID = nil;
    @synchronized (sg_seenTracks) {
        if (track == sg_lastSeen) return;
        sg_lastSeen = track;
        trackID = idOf(track);
        if (!trackID || [trackID isEqualToString:sg_lastSeenID]) return;
        sg_lastSeenID = trackID;
    }
    remember(track, trackID);
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([trackID isEqualToString:SGKaraokePlayingTrack()] && resumeSourceRetries(trackID))
            SGKaraokeRequestLyrics(trackID);
    });
    dispatch_async(dispatch_get_main_queue(), ^{ prefetch(trackID); });
}

// The -state hook runs only when something asks the player, which nothing may do with the app in the
// background and nothing on screen. The player's own reports come there too, so the next track's walk
// begins as it starts and its lines are in for the lock screen.
@interface SGKaraokeTrackWatcher : NSObject <SGPlayerStateObserver>
@property (nonatomic, copy) NSString *ahead;
@property (nonatomic, copy) NSString *translationLanguage;
@end

@implementation SGKaraokeTrackWatcher
- (instancetype)init {
    if (!(self = [super init])) return nil;
    self.translationLanguage = SGLyricsTranslationLanguage();
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(becameActive:) name:UIApplicationDidBecomeActiveNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(background:) name:UIApplicationDidEnterBackgroundNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(defaultsChanged:) name:NSUserDefaultsDidChangeNotification object:nil];
    return self;
}
- (void)becameActive:(NSNotification *)note {
    SGLyricsResumeDeferred();
    [self playerStateDidReport:SGPlayerState()];
    NSString *playing = SGKaraokePlayingTrack();
    resumeSourceRetries(playing);
    if (playing && !sg_lyrics[playing] && !SGKaraokeLooking(playing)) SGKaraokeRequestLyrics(playing);
    [self playerUpNextDidChange:SGPlayerState()];
}
- (void)background:(NSNotification *)note {
    [self playerUpNextDidChange:SGPlayerState()];
}
- (void)playerStateDidChange:(SPTPlayerState *)state {
    SGLyricsPlaybackChanged(idOf(state.track));
    seen(state);
    [self playerUpNextDidChange:state];
}
- (void)playerStateDidReport:(SPTPlayerState *)state {
    NSString *key = idOf(state.track);
    if (!SGLocalFileIs(key)) return;
    id path = state.track.metadata[@"local_file_path"];
    if (![path isKindOfClass:NSString.class] || ![path length] ||
        [path isEqual:sg_sampledLocalPaths[key]] || !mayPrefetchLyrics() ||
        hasChoice(key) || SGImportedLRCLinkedTo(key)) return;
    // Supersede the old local lookup, not the source walk or its page waiters.
    forgetKeeper(key);
    SGKaraokeRequestLyrics(key);
}
- (void)playerUpNextDidChange:(SPTPlayerState *)state {
    SPTPlayerTrack *next = SGPlayerUpNextIn(state);
    NSString *nextID = idOf(next);
    BOOL foreground = UIApplication.sharedApplication.applicationState == UIApplicationStateActive;
    if (!sg_ownSources || !nextID || !SGOptionalWorkMayRun(foreground)) {
        if (![self.ahead isEqualToString:idOf(state.track)]) SGLyricsCancelPrefetch(self.ahead);
        self.ahead = nil;
        return;
    }
    if ([nextID isEqualToString:self.ahead]) return;
    if (![self.ahead isEqualToString:idOf(state.track)]) SGLyricsCancelPrefetch(self.ahead);
    self.ahead = nextID;
    remember(next, nextID);
    // The existing lyric owner coalesces by track ID and keeps late replies under that ID.
    if (!SGImportedLRCLinkedTo(nextID) && !SGLocalFileIs(nextID)) SGLyricsPrefetch(nextID);
}
- (void)defaultsChanged:(NSNotification *)note {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *language = SGLyricsTranslationLanguage();
        if (self.translationLanguage != language && ![self.translationLanguage isEqualToString:language]) {
            self.translationLanguage = language;
            // Republish through the owner: refresh paused consumers, supersede deferred writes,
            // and let untranslated tracks ask for the newly selected community language.
            for (NSString *track in sg_lyrics.allKeys) keep(track, sg_lyrics[track], NO);
        }
        [self playerUpNextDidChange:SGPlayerState()];
    });
}
- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}
@end

static SGKaraokeTrackWatcher *sg_trackWatcher;

%hook SPTEsperantoPlayer
- (id)state {
    if (!sg_player) sg_player = self;
    SPTPlayerState *state = %orig;
    seen(state);
    return state;
}
%end

%hook SPTDataLoaderService
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveData:(NSData *)data {
    received(session, task, data);
    %orig;
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    completed(task, error);
    %orig;
}
%end

%hook _TtC26Connectivity_HttpClientKit20HttpClientURLSession
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveData:(NSData *)data {
    received(session, task, data);
    %orig;
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    completed(task, error);
    %orig;
}
%end

// With nothing of the karaoke's on, the headers are still read for SGSpclientHeaders' other askers
// (Native iOS Music Haptics, which can be picked at any moment).
%group SGSpclientHeadersOnly
%hook SPTDataLoaderService
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveData:(NSData *)data {
    rememberHeaders(session, task.currentRequest);
    %orig;
}
%end

%hook _TtC26Connectivity_HttpClientKit20HttpClientURLSession
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveData:(NSData *)data {
    rememberHeaders(session, task.currentRequest);
    %orig;
}
%end
%end

%ctor {
    // The sources that search by name learn the name from the player, so the player is caught
    // whenever one is on, not only for the redesign's lyrics and the lock screen.
    if (!SGRedesignedUI() && !SGFlag(SGKeyLockScreenLyrics, NO) && !SGLyricsEnabled()
        && !SGLockArtworkShowsLyrics(SGLockScreenArtwork())) {
        %init(SGSpclientHeadersOnly);
        return;
    }
    sg_seenTracks = [NSMutableDictionary dictionary];
    sg_lyrics = [NSMutableDictionary dictionary];
    sg_requested = [NSMutableSet set];
    sg_asking = [NSMutableSet set];
    sg_losses = [NSMutableDictionary dictionary];
    sg_looking = [NSMutableSet set];
    sg_ownSources = SGLyricsEnabled();
    // A rename gives the file playing a new lyrics key at once, with no new state from the player to
    // bring it here, so the new key is asked for now; the redesign's lyrics view shows what comes in.
    // Posted on the main thread.
    [NSNotificationCenter.defaultCenter addObserverForName:SGLocalFileEditsDidChangeNotification object:nil queue:nil
                                                usingBlock:^(NSNotification *note) {
        NSString *key = SGLocalFileLyricsKey(note.object);
        if (key && [key isEqualToString:SGKaraokePlayingTrack()]) {
            @synchronized (sg_seenTracks) { sg_lastSeenID = key; }
            SGKaraokeRequestLyrics(key);
        }
    }];
    // An imported or deleted LRC file can change any local file's lyrics, found or missed: they are
    // forgotten, but for a look still out, and the file playing is asked for again.
    [NSNotificationCenter.defaultCenter addObserverForName:SGImportedLRCDidChangeNotification object:nil queue:nil
                                                usingBlock:^(NSNotification *note) {
        importsChanged(note.object);
    }];
    // Spotify asks for a track's lyrics only while a page of its own shows them, so a track the player
    // moved on to in the background came back to the app with none, and the redesign's lyrics, which
    // ask for nothing themselves, stayed empty. They are asked for here as the app becomes active again,
    // which also follows Control Center, a call or Siri without the background.
    sg_trackWatcher = [SGKaraokeTrackWatcher new];
    SGAddPlayerStateObserver(sg_trackWatcher);
    %init;
    SGLog(@"karaoke: on");
    SGRequireClasses(@[
        @"SPTEsperantoPlayer", @"SPTPlayerState",
        @"SPTDataLoaderService", @"_TtC26Connectivity_HttpClientKit20HttpClientURLSession",
    ]);
}
