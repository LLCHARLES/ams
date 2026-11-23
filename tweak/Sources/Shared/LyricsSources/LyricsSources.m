// The chain: sources asked in order or all at once, with timed lyrics answering promptly.
//
// Stopping at the first answer is what makes the lyrics card under the player appear at all. For a
// track Spotify has no lyrics of its own for, the card is only offered when the answer to Spotify's
// lyrics request arrives within about a second of the player building its list of cards; a walk that
// went on through every source for word timing took three seconds and more, and the card never came.
// Word timing first (the default) answers just as soon, then keeps looking for finer timing,
// keeping source priority for ties. All at once keeps the first word-timed answer to arrive.
#import "Core/SGCore.h"
#import "LyricsSources.h"
#import "LyricsHosts.h"
#import "Shared/Lyrics/Lyrics.h"
#import "Shared/LocalFiles/LocalFiles.h"
#import "Shared/LocalFiles/LocalLyrics.h"
#import "Settings/SGSourcesPage.h"
#import "Settings/SGPageStyle.h"
#import "Headers/SPTPlayer.h"
#import <stdatomic.h>

static const NSTimeInterval kTimeout = SGLyricsRequestTimeoutSeconds;
static const NSUInteger kKeptTracks = 40;

// What the switches were called while Musixmatch was the only source; read once, to carry an
// existing install's settings over to the order.
static NSString *const kLegacyMusixmatch = @"spotifyglass.musixmatchLyrics";
static NSString *const kLegacyAllTracks = @"spotifyglass.musixmatchAllTracks";
static NSString *const kLegacyNetEase = @"spotifyglass.neteaseWordTiming";

@implementation SGLyricsLink
@end

@implementation SGLyricsResult
@end

@implementation SGLyricsQuery
@end

@implementation SGLyricsProvider
@end

SGLyricsRequestContext *SGLyricsInvoke(SGLyricsProvider *provider, SGLyricsQuery *query, BOOL (^current)(void), void (^done)(SGLyricsResult *, BOOL)) {
    SGLyricsQuery *invocation = [SGLyricsQuery new];
    invocation.trackID = query.trackID;
    invocation.title = query.title; invocation.artist = query.artist; invocation.album = query.album;
    invocation.seconds = query.seconds;
    SGLyricsRequestContext *context = invocation.requestContext = [SGLyricsRequestContext new];
    // One deadline covers the entire adapter, including token/ISRC/search/lyrics subrequests.
    // A late provider callback cannot re-enter the walk after it has fallen through.
    __block BOOL completed = NO;
    dispatch_source_t deadline = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    void (^complete)(SGLyricsResult *, BOOL) = ^(SGLyricsResult *result, BOOL failed) {
        if (completed) return;
        completed = YES;
        dispatch_source_cancel(deadline);
        dispatch_source_set_event_handler(deadline, nil);
        [context finishRequests];
        done(result, failed);
    };
    dispatch_source_set_timer(deadline, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kTimeout * NSEC_PER_SEC)),
                              DISPATCH_TIME_FOREVER, 0);
    dispatch_source_set_event_handler(deadline, ^{
        [context cancelRequests];
    });
    [context onCancel:^{
        if (NSThread.isMainThread) complete(nil, YES);
        else dispatch_async(dispatch_get_main_queue(), ^{ complete(nil, YES); });
    }];
    dispatch_resume(deadline);
    provider.ask(invocation, ^(SGLyricsResult *result) {
        void (^deliver)(void) = ^{
            if (completed) return;
            SGLyricsAsk search = context.emptyNameSearch;
            NSString *title = !result && !context.failed && search && (!current || current())
                ? SGLyricsBareTitleWithOptions(invocation.title, YES) : invocation.title;
            if (title.length && ![title isEqualToString:invocation.title]) {
                invocation.title = title;
                context.emptyNameSearch = nil;
                search(invocation, ^(SGLyricsResult *retry) {
                    void (^finish)(void) = ^{ complete(retry, context.failed); };
                    if (NSThread.isMainThread) finish();
                    else dispatch_async(dispatch_get_main_queue(), finish);
                });
            } else complete(result, context.failed);
        };
        if (NSThread.isMainThread) deliver();
        else dispatch_async(dispatch_get_main_queue(), deliver);
    });
    return context;
}

static SGLyricsRequestContext *invokePin(NSNumber *pin, SGLyricsQuery *query, BOOL (^current)(void),
                      void (^done)(SGLyricsResult *, BOOL)) {
    SGLyricsProvider *provider = [SGLyricsProvider new];
    provider.ask = ^(SGLyricsQuery *invocation, void (^answer)(SGLyricsResult *)) {
        SGLrcLibGetIDIn(invocation.requestContext, pin, answer);
    };
    return SGLyricsInvoke(provider, query, current, done);
}

SGLyricsResult *SGLyricsSnapshot(SGLyricsResult *result) {
    if (!result) return nil;
    SGLyricsResult *copy = [SGLyricsResult new];
    copy.provider = result.provider; copy.pageProvider = result.pageProvider;
    copy.creditLinks = result.creditLinks; copy.creditRequired = result.creditRequired;
    copy.synced = result.synced; copy.wordTimed = result.wordTimed;
    copy.starts = result.starts; copy.texts = result.texts; copy.karaokeLines = result.karaokeLines;
    copy.title = result.title; copy.artist = result.artist; copy.album = result.album; copy.seconds = result.seconds;
    copy.instrumental = result.instrumental; copy.picked = result.picked; copy.provisional = result.provisional;
    return copy;
}

static SGLyricsResult *pickedSnapshot(SGLyricsResult *result) {
    result = SGLyricsSnapshot(result);
    if (!result.texts.count && result.karaokeLines.count) {
        NSArray *starts, *texts;
        SGLyricsPageLines(result.karaokeLines, &starts, &texts);
        result.starts = starts; result.texts = texts;
        result.synced = SGKaraokeLinesTiming(result.karaokeLines) != SGKaraokeTimingNone;
    }
    result.picked = YES;
    result.provisional = NO;
    return result;
}

#pragma mark - the requests the sources share

// Aggregate diagnostics only. Selection and recovery use invocation-private contexts.
static _Atomic NSUInteger sg_failures;

void SGLyricsNoteReply(NSURLResponse *response, NSError *error) {
    if (SGLyricsReplyFailed(response, error)) atomic_fetch_add(&sg_failures, 1);
}

NSURL *SGLyricsURL(NSString *base, NSDictionary<NSString *, NSString *> *query) {
    NSURLComponents *url = [NSURLComponents componentsWithString:base];
    NSMutableArray<NSURLQueryItem *> *items = [NSMutableArray array];
    [query enumerateKeysAndObjectsUsingBlock:^(NSString *name, NSString *value, BOOL *stop) {
        [items addObject:[NSURLQueryItem queryItemWithName:name value:value]];
    }];
    url.queryItems = items;
    return url.URL;
}

static NSMutableURLRequest *requestFor(NSURL *url, NSDictionary<NSString *, NSString *> *headers) {
    if (!url) return nil;
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:kTimeout];
    SGLyricsMarkRequest(request);
    [headers enumerateKeysAndObjectsUsingBlock:^(NSString *name, NSString *value, BOOL *stop) {
        [request setValue:value forHTTPHeaderField:name];
    }];
    return request;
}

// Raw transport completion stays off main. The public helpers decode/transform here and only
// deliver the finished value to main, where provider caches and the source walk still live.
static void sendForReply(SGLyricsRequestContext *context, NSURLRequest *request, void (^done)(NSData *body, NSHTTPURLResponse *response)) {
    if (!request) {
        [context noteFailure:YES];
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{ done(nil, nil); });
        return;
    }
    NSURL *url = request.URL;
    NSURLSessionDataTask *task = [NSURLSession.sharedSession dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSHTTPURLResponse *reply = [response isKindOfClass:NSHTTPURLResponse.class] ? (NSHTTPURLResponse *)response : nil;
        SGLyricsNoteReply(response, error);
        [context noteResponse:response error:error];
        if (error || reply.statusCode >= 400) SGLog(@"lyrics: %@ answered %ld, error %@ (%ld)", url.host, (long)reply.statusCode, error.domain, (long)error.code);
        if (!error && reply.statusCode >= 200 && reply.statusCode < 300 && !data.length)
            [context noteFailure:YES];
        done(error ? nil : data, reply);
    }];
    [context trackTask:task];
    [task resume];
}

static void send(SGLyricsRequestContext *context, NSURLRequest *request, void (^done)(NSData *body)) {
    sendForReply(context, request, ^(NSData *body, NSHTTPURLResponse *reply) {
        done(reply.statusCode >= 400 ? nil : body);
    });
}

static id jsonIn(NSData *body) {
    return body.length ? [NSJSONSerialization JSONObjectWithData:body options:0 error:nil] : nil;
}

void SGLyricsGetJSON(NSURL *url, NSDictionary<NSString *, NSString *> *headers, void (^done)(id root)) {
    SGLyricsGetJSONIn(nil, url, headers, done);
}
void SGLyricsGetJSONIn(SGLyricsRequestContext *context, NSURL *url, NSDictionary *headers, void (^done)(id)) {
    SGLyricsGetJSONTransformIn(context, url, headers, nil, done);
}

void SGLyricsGetJSONTransform(NSURL *url, NSDictionary<NSString *, NSString *> *headers,
                              id (^transform)(id), void (^done)(id)) {
    SGLyricsGetJSONTransformIn(nil, url, headers, transform, done);
}
void SGLyricsGetJSONTransformIn(SGLyricsRequestContext *context, NSURL *url, NSDictionary *headers,
                                id (^transform)(id), void (^done)(id)) {
    send(context, requestFor(url, headers), ^(NSData *body) {
        SGLyricsTransform(^id {
            id root = jsonIn(body);
            if (body.length && !root) [context noteFailure:YES];
            return transform ? transform(root) : root;
        }, done);
    });
}

void SGLyricsGetJSONReply(NSURL *url, NSDictionary<NSString *, NSString *> *headers, void (^done)(id root, NSHTTPURLResponse *response)) {
    SGLyricsGetJSONReplyIn(nil, url, headers, done);
}
void SGLyricsGetJSONReplyIn(SGLyricsRequestContext *context, NSURL *url, NSDictionary *headers, void (^done)(id, NSHTTPURLResponse *)) {
    sendForReply(context, requestFor(url, headers), ^(NSData *body, NSHTTPURLResponse *reply) {
        id root = jsonIn(body);
        if (reply.statusCode >= 200 && reply.statusCode < 300 && !root) [context noteFailure:YES];
        dispatch_async(dispatch_get_main_queue(), ^{ done(root, reply); });
    });
}

void SGLyricsGetText(NSURL *url, void (^done)(NSString *text)) {
    SGLyricsGetTextIn(nil, url, done);
}
void SGLyricsGetTextIn(SGLyricsRequestContext *context, NSURL *url, void (^done)(NSString *)) {
    SGLyricsGetTextTransformIn(context, url, nil, done);
}

void SGLyricsGetTextTransform(NSURL *url, id (^transform)(NSString *), void (^done)(id)) {
    SGLyricsGetTextTransformIn(nil, url, transform, done);
}
void SGLyricsGetTextTransformIn(SGLyricsRequestContext *context, NSURL *url, id (^transform)(NSString *), void (^done)(id)) {
    send(context, requestFor(url, nil), ^(NSData *body) {
        SGLyricsTransform(^id {
            NSString *text = body.length ? [[NSString alloc] initWithData:body encoding:NSUTF8StringEncoding] : nil;
            if (body.length && !text) [context noteFailure:YES];
            return transform ? transform(text) : text;
        }, done);
    });
}

void SGLyricsPostJSON(NSURL *url, NSDictionary<NSString *, NSString *> *headers, id body, void (^done)(id root)) {
    SGLyricsPostJSONTransform(url, headers, body, nil, done);
}

void SGLyricsPostJSONTransform(NSURL *url, NSDictionary<NSString *, NSString *> *headers, id body,
                               id (^transform)(id), void (^done)(id)) {
    SGLyricsPostJSONTransformIn(nil, url, headers, body, transform, done);
}
void SGLyricsPostJSONTransformIn(SGLyricsRequestContext *context, NSURL *url, NSDictionary *headers, id body,
                                id (^transform)(id), void (^done)(id)) {
    NSData *written = [NSJSONSerialization isValidJSONObject:body]
        ? [NSJSONSerialization dataWithJSONObject:body options:0 error:nil] : nil;
    NSMutableURLRequest *request = written ? requestFor(url, headers) : nil;
    request.HTTPMethod = @"POST";
    request.HTTPBody = written;
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    send(context, request, ^(NSData *answer) {
        SGLyricsTransform(^id {
            id root = jsonIn(answer);
            if (answer.length && !root) [context noteFailure:YES];
            return transform ? transform(root) : root;
        }, done);
    });
}

// A private session keeps a login cookie out of the shared cookie jar and disk cache. Receiving
// chunks lets us stop a broken endpoint before its reply grows into an unbounded allocation.
@interface SGLyricsSourceTransfer : NSObject <NSURLSessionDataDelegate>
@property (nonatomic, strong) NSMutableData *data;
@property (nonatomic, copy) void (^done)(NSData *, NSInteger);
@property (nonatomic) NSInteger status;
@property (nonatomic, strong) SGLyricsRequestContext *context;
@end
@implementation SGLyricsSourceTransfer
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task
 didReceiveResponse:(NSURLResponse *)response completionHandler:(void (^)(NSURLSessionResponseDisposition))completion {
    self.status = [response isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)response).statusCode : 0;
    SGLyricsNoteReply(response, nil);
    [self.context noteResponse:response error:nil];
    completion(response.expectedContentLength > 2 * 1024 * 1024 ? NSURLSessionResponseCancel : NSURLSessionResponseAllow);
}
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveData:(NSData *)data {
    if (data.length > 2 * 1024 * 1024 - self.data.length) { [task cancel]; return; }
    [self.data appendData:data];
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task
 willPerformHTTPRedirection:(NSHTTPURLResponse *)response newRequest:(NSURLRequest *)request
 completionHandler:(void (^)(NSURLRequest *))completion { completion(nil); }
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    if (error) SGLyricsNoteReply(nil, error);
    [self.context noteResponse:nil error:error];
    if (error || self.status >= 400) SGLog(@"lyrics: source request ended with HTTP %ld, error %@ (%ld)", (long)self.status, error.domain, (long)error.code);
    NSData *data = error ? nil : [self.data copy];
    if (!error && self.status >= 200 && self.status < 300 && !data.length) [self.context noteFailure:YES];
    void (^done)(NSData *, NSInteger) = self.done;
    self.done = nil;
    NSInteger status = self.status;
    if (done) dispatch_async(dispatch_get_main_queue(), ^{ done(data, status); });
    [session finishTasksAndInvalidate];
}
@end

void SGLyricsSourceRequest(NSURL *url, NSDictionary<NSString *, NSString *> *headers, NSData *body,
                           void (^done)(NSData *, NSInteger)) {
    SGLyricsSourceRequestIn(nil, url, headers, body, done);
}
void SGLyricsSourceRequestIn(SGLyricsRequestContext *context, NSURL *url, NSDictionary *headers, NSData *body,
                            void (^done)(NSData *, NSInteger)) {
    NSMutableURLRequest *request = requestFor(url, headers);
    if (!request || ![url.scheme isEqualToString:@"https"]) {
        [context noteFailure:YES];
        dispatch_async(dispatch_get_main_queue(), ^{ done(nil, 0); });
        return;
    }
    request.HTTPShouldHandleCookies = NO;
    if (body) { request.HTTPMethod = @"POST"; request.HTTPBody = body; }
    NSURLSessionConfiguration *config = NSURLSessionConfiguration.ephemeralSessionConfiguration;
    config.HTTPCookieStorage = nil;
    config.URLCredentialStorage = nil;
    config.URLCache = nil;
    config.timeoutIntervalForResource = kTimeout;
    SGLyricsSourceTransfer *transfer = [SGLyricsSourceTransfer new];
    transfer.data = [NSMutableData data];
    transfer.done = done;
    transfer.context = context;
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config delegate:transfer delegateQueue:nil];
    NSURLSessionDataTask *task = [session dataTaskWithRequest:request];
    [context trackTask:task];
    [task resume];
}

// A pause this long between two lines gets a ♪, so Spotify's page does not hold the last one.
static const NSInteger kBreakMs = 3000;

void SGLyricsPageLines(NSArray<SGKaraokeLine *> *lines, NSArray<NSNumber *> **starts, NSArray<NSString *> **texts) {
    NSMutableArray<NSNumber *> *at = [NSMutableArray array];
    NSMutableArray<NSString *> *said = [NSMutableArray array];
    SGKaraokeLine *last = nil;
    for (SGKaraokeLine *line in lines) {
        if (last && line.start - last.end >= kBreakMs) {
            [at addObject:@(last.end)];
            [said addObject:@"♪"];
        }
        NSString *text = SGKaraokeLineText(line);
        // The backing vocals read on the same line on Spotify's own page, which has one row a line.
        if (line.backing) text = [text stringByAppendingFormat:@" %@", SGKaraokeLineText(line.backing)];
        [at addObject:@(line.start)];
        [said addObject:text];
        last = line;
    }
    if (last) {
        [at addObject:@(last.end)];
        [said addObject:@""];
    }
    *starts = at;
    *texts = said;
}

#pragma mark - which sources there are, and in what order

NSArray<SGLyricsProvider *> *SGLyricsAllProviders(void) {
    static NSArray<SGLyricsProvider *> *all;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        SGLyricsProvider *(^make)(NSString *, NSString *, NSString *, SGLyricsAsk) =
        ^(NSString *key, NSString *name, NSString *detail, SGLyricsAsk ask) {
            SGLyricsProvider *provider = [SGLyricsProvider new];
            provider.key = key;
            provider.name = name;
            provider.detail = detail;
            // A source that matches by Spotify's own track id has everything it needs from the
            // start; the rest wait for the player to name the track before they can search.
            provider.needsName = ![key isEqualToString:@"musixmatch"] && ![key isEqualToString:SGSpicyLyricsKey];
            provider.untimed = [key isEqualToString:@"genius"];
            provider.ask = ask;
            return provider;
        };
        all = @[
            make(@"binilyrics", @"BiniLyrics", SGL(@"settings.lyricssources.binilyrics.subtitle", @"Apple Music word timing"), SGBiniLyricsAsk),
            make(@"lyricsplus", @"LyricsPlus", SGL(@"settings.lyricssources.lyricsplus.subtitle", @"Word and line timing, multiple catalogs"), SGLyricsPlusAsk),
            make(@"musixmatch", @"Musixmatch", SGL(@"settings.lyricssources.musixmatch.subtitle", @"Spotify's licensed catalog"), SGMusixmatchAsk),
            make(@"unison", @"Unison", SGL(@"settings.lyricssources.unison.subtitle", @"Hand-timed, few tracks"), SGUnisonAsk),
            make(@"netease", @"NetEase", SGL(@"settings.lyricssources.netease.subtitle", @"Word timing, censored"), SGNetEaseAsk),
            make(@"lrclib", @"LRCLIB", SGL(@"settings.lyricssources.lrclib.subtitle", @"Line timing, open fallback"), SGLrcLibAsk),
            make(@"bugs", @"Bugs", SGL(@"settings.lyricssources.bugs.subtitle", @"Line timing, Korean catalog"), SGBugsAsk),
            make(@"genie", @"Genie", SGL(@"settings.lyricssources.genie.subtitle", @"Line timing, Korean catalog"), SGGenieAsk),
            make(@"petitlyrics", @"PetitLyrics", SGL(@"settings.lyricssources.petitlyrics.subtitle", @"Word and line timing, Japanese catalog"), SGPetitLyricsAsk),
            make(SGSpicyLyricsKey, @"Spicy Lyrics", SGL(@"settings.lyricssources.spicylyrics.subtitle", @"Community word syncs, your own key"), SGSpicyLyricsAsk),
            make(@"qqmusic", @"QQ Music", SGL(@"settings.lyricssources.qqmusic.subtitle", @"Line timing, Chinese catalog"), SGQQMusicAsk),
            make(@"kugou", @"KuGou", SGL(@"settings.lyricssources.kugou.subtitle", @"Word timing, Chinese catalog"), SGKuGouAsk),
            make(@"deezer", @"Deezer", SGL(@"settings.lyricssources.deezer.subtitle", @"Word and line timing, your own ARL"), SGDeezerAsk),
            make(SGImportedLRCKey, SGL(@"settings.lyricssources.importedlrc.title", @"Imported lyrics"), SGL(@"settings.lyricssources.importedlrc.subtitle", @"Your own LRC, TTML or text files"), SGImportedLRCAsk),
            make(@"genius", @"Genius", SGL(@"settings.lyricssources.genius.subtitle", @"Untimed, when no other has lyrics"), SGGeniusAsk),
        ];
    });
    return all;
}

SGLyricsProvider *SGLyricsProviderFor(NSString *key) {
    for (SGLyricsProvider *provider in SGLyricsAllProviders()) {
        if ([provider.key isEqualToString:key]) return provider;
    }
    return nil;
}

// An install from before the order existed keeps what it had: the sources it was using, in the only
// order there was. Nothing is switched on for it that it had not already asked for.
static NSArray<NSString *> *fromLegacyKeys(void) {
    if (!SGFlag(kLegacyMusixmatch, NO)) return @[];
    NSMutableArray<NSString *> *order = [NSMutableArray arrayWithObject:@"musixmatch"];
    if (SGFlag(kLegacyNetEase, NO)) [order addObject:@"netease"];
    return order;
}

// With nothing stored and nothing to carry over, every source is on: the user's own files first,
// word timing ahead of line timing, and the two Chinese catalogs after the rest.
// The catalog before known-source tracking is the bootstrap for old saved orders.
// Keep this historical set fixed: missing members were deliberately disabled.
static NSArray<NSString *> *sourcesBeforeCatalogTracking(void) {
    return @[SGImportedLRCKey, SGSpicyLyricsKey, @"binilyrics", @"lyricsplus", @"musixmatch",
             @"unison", @"deezer", @"netease", @"lrclib", @"bugs", @"genie", @"qqmusic", @"kugou", @"genius"];
}

static NSArray<NSString *> *defaultOrder(void) {
    NSMutableArray *order = [sourcesBeforeCatalogTracking() mutableCopy];
    [order insertObject:@"petitlyrics" atIndex:[order indexOfObject:@"lrclib"]];
    return order;
}

NSArray<NSString *> *SGLyricsOrder(void) {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSArray *stored = [defaults arrayForKey:SGKeyLyricsProviders];
    if (stored) {
        NSArray *known = [defaults arrayForKey:SGKeyLyricsKnownProviders] ?: sourcesBeforeCatalogTracking();
        NSArray *catalog = defaultOrder();
        NSMutableArray *updated = [stored mutableCopy];
        NSMutableOrderedSet *seen = [NSMutableOrderedSet orderedSetWithArray:known];
        for (NSUInteger i = 0; i < catalog.count; i++) {
            NSString *key = catalog[i];
            if ([seen containsObject:key]) continue;
            [seen addObject:key];
            if (!stored.count || [updated containsObject:key]) continue;
            NSUInteger insertion = updated.count;
            for (NSUInteger j = i + 1; j < catalog.count; j++) {
                NSUInteger next = [updated indexOfObject:catalog[j]];
                if (next != NSNotFound) { insertion = next; break; }
            }
            [updated insertObject:key atIndex:insertion];
        }
        if (![updated isEqual:stored]) [defaults setObject:updated forKey:SGKeyLyricsProviders];
        if (![[defaults arrayForKey:SGKeyLyricsKnownProviders] isEqual:seen.array])
            [defaults setObject:seen.array forKey:SGKeyLyricsKnownProviders];
        stored = updated;
    }
    // A reset leaves sources off until the user saves an order, including an explicitly empty one.
    if (!stored && SGHidden(SGKeyStock)) return @[];
    NSArray *legacy = fromLegacyKeys();
    NSArray *keys = [stored isKindOfClass:NSArray.class] ? stored : legacy.count ? legacy : defaultOrder();
    NSMutableArray<NSString *> *order = [NSMutableArray array];
    for (id key in keys) {
        if ([key isKindOfClass:NSString.class] && SGLyricsProviderFor(key) && ![order containsObject:key]) [order addObject:key];
    }
    return order;
}

void SGLyricsSetOrder(NSArray<NSString *> *keys) {
    [NSUserDefaults.standardUserDefaults setObject:keys ?: @[] forKey:SGKeyLyricsProviders];
    [NSUserDefaults.standardUserDefaults setObject:defaultOrder() forKey:SGKeyLyricsKnownProviders];
}

// With EeveeSpotify injected, its own lyrics answer Spotify's requests and the mod's stand aside: two
// tweaks holding and answering the same request froze Spotify after launch.
BOOL SGLyricsEnabled(void) {
    return SGLyricsOrder().count > 0 && !SGLyricsStandAsideForEevee();
}

#pragma mark - what is known about the track

// The player knows every track it has played by name, which is what every source but Musixmatch
// searches by. The track is looked up by id rather than compared with the one playing now: a lyrics
// request often lands a beat before the player moves on to its track, and comparing then left the
// query nameless. A track the player has not reported starts with nothing, and the first source
// that matches by id fills the rest in.
SGLyricsQuery *SGLyricsQueryFor(NSString *trackID) {
    SGLyricsQuery *query = [SGLyricsQuery new];
    query.trackID = trackID;
    // A local file is named by its own key: its tags, and the names the user gave it over them.
    NSDictionary *local = SGLocalFileInfo(trackID);
    if (local) {
        query.title = local[@"title"];
        query.artist = local[@"artist"];
        query.album = local[@"album"];
        query.seconds = [local[@"seconds"] integerValue];
        return query;
    }
    SPTPlayerTrack *track = SGKaraokeTrackFor(trackID);
    if (!track) return query;
    query.title = track.trackTitle;
    query.artist = track.artistName;
    NSDictionary<NSString *, NSString *> *metadata = track.metadata;
    // With "every track" on, the metadata hook has just noted Spotify's own verdict and forced has_lyrics on;
    // off, nothing notes it and has_lyrics is Spotify's own.
    id has = metadata[@"has_lyrics"];
    if (has && SGLyricsSpotifyHas(trackID) < 0) SGLyricsNoteSpotifyHas(trackID, [@"true" isEqual:has]);
    id album = metadata[@"album_title"];
    id length = metadata[@"duration"];
    if ([album isKindOfClass:NSString.class]) query.album = album;
    if ([length respondsToSelector:@selector(integerValue)]) query.seconds = [length integerValue] / 1000;
    return query;
}

static void learnFrom(SGLyricsQuery *query, SGLyricsResult *result) {
    if (!query.title.length && result.title.length) query.title = result.title;
    if (!query.artist.length && result.artist.length) query.artist = result.artist;
    if (!query.album.length && result.album.length) query.album = result.album;
    if (query.seconds <= 0 && result.seconds > 0) query.seconds = result.seconds;
}

#pragma mark - the walk

// Main queue only, except sg_missing and sg_credits.
static NSMutableDictionary<NSString *, id> *sg_kept;
static NSMutableDictionary<NSString *, NSMutableArray *> *sg_waiting;
@class SGLyricsWalk;
static NSMutableDictionary<NSString *, SGLyricsWalk *> *sg_walks;
static NSMutableSet<NSString *> *sg_advance;
static NSString *sg_playing;
static void trimKept(NSString *track);
static NSMutableSet<NSString *> *sg_missing;
static NSMutableSet<NSString *> *sg_failed;
static NSMutableSet<NSString *> *sg_spotifyFailed;
static NSMutableDictionary<NSString *, NSNumber *> *sg_pins;
// Guarded by sg_pins; generations survive unpinning and source picks to reject old hook deliveries.
static NSMutableDictionary<NSString *, NSNumber *> *sg_pinGenerations;
// Main-owned, only outstanding preparations. Tokens distinguish overlapping choices for one track.
static NSMutableDictionary<NSString *, NSObject *> *sg_pinSelections;
NSNotificationName const SGLyricsPinDidChangeNotification = @"spotifyglass.lyrics.pinDidChange";
NSNotificationName const SGLyricsDidReloadNotification = @"spotifyglass.lyrics.didReload";
static NSMutableDictionary<NSString *, NSString *> *sg_credits;
// Spotify's own has_lyrics per track, as its metadata said. The player's metadata is read many
// times a second while a list scrolls, so a value already noted costs one lookup and no write.
static NSMutableDictionary<NSString *, NSNumber *> *sg_spotifyHas;
static const NSUInteger kNotedTracks = 200;
static const NSUInteger kMissingTracks = 200;

// Main queue; missing marks outlive the answer cache, but not an unlimited number of completed tracks.
static void pruneMissing(NSString *newest) {
    NSString *playing = SGKaraokePlayingTrack();
    @synchronized (sg_missing) {
        NSMutableSet<NSString *> *completed = [sg_missing mutableCopy];
        [completed minusSet:[NSSet setWithArray:sg_waiting.allKeys]];
        NSUInteger count = completed.count;
        for (NSString *track in completed) {
            if (count <= kMissingTracks) break;
            if ([track isEqualToString:playing] || [track isEqualToString:newest]) continue;
            [sg_missing removeObject:track];
            if (sg_kept[track] == NSNull.null) [sg_kept removeObjectForKey:track];
            count--;
        }
    }
}

static void setUp(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        sg_kept = [NSMutableDictionary dictionary];
        sg_waiting = [NSMutableDictionary dictionary];
        sg_walks = [NSMutableDictionary dictionary];
        sg_advance = [NSMutableSet set];
        sg_missing = [NSMutableSet set];
        sg_failed = [NSMutableSet set];
        sg_spotifyFailed = [NSMutableSet set];
        sg_credits = [NSMutableDictionary dictionary];
        sg_spotifyHas = [NSMutableDictionary dictionary];
        sg_pins = [NSMutableDictionary dictionary];
        sg_pinGenerations = [NSMutableDictionary dictionary];
        sg_pinSelections = [NSMutableDictionary dictionary];
        id stored = [NSUserDefaults.standardUserDefaults objectForKey:SGKeyLyricsPins];
        if ([stored isKindOfClass:NSDictionary.class]) {
            for (id track in stored) {
                id identifier = stored[track];
                if (sg_pins.count >= 500) break;
                if ([track isKindOfClass:NSString.class] && [track length] && [identifier isKindOfClass:NSNumber.class]
                    && SGLyricsDecimalID(identifier).length && [identifier longLongValue] > 0) sg_pins[track] = identifier;
            }
        }
    });
}

NSNumber *SGLyricsPinnedID(NSString *trackID) {
    setUp();
    @synchronized (sg_pins) { return trackID ? sg_pins[trackID] : nil; }
}

NSUInteger SGLyricsPinGeneration(NSString *trackID) {
    setUp();
    @synchronized (sg_pins) { return trackID ? sg_pinGenerations[trackID].unsignedIntegerValue : 0; }
}

void SGLyricsInvalidateDelivery(NSString *trackID) {
    if (!trackID.length) return;
    setUp();
    SGLyricsRetire(trackID);
    @synchronized (sg_pins) {
        sg_pinGenerations[trackID] = @(sg_pinGenerations[trackID].unsignedIntegerValue + 1);
    }
}

static void whenNamed(NSString *trackID, NSTimeInterval waited, NSMutableArray *waiting);

static BOOL pinResult(NSString *trackID, NSDictionary *record, SGLyricsResult *result) {
    if (!trackID.length || ![record isKindOfClass:NSDictionary.class]) return NO;
    // The menu may hand back its shaped entry or the raw record it carries.
    if ([record[@"record"] isKindOfClass:NSDictionary.class]) record = record[@"record"];
    id identifier = record[@"id"];
    if (![identifier isKindOfClass:NSNumber.class] || !SGLyricsDecimalID(identifier).length || [identifier longLongValue] <= 0) return NO;
    if (!result.instrumental && !result.karaokeLines.count) return NO;
    setUp();
    SGLyricsRetire(trackID);
    SGLyricsDropChoice(trackID, SGLyricsChosenSource(trackID));
    @synchronized (sg_pins) {
        sg_pins[trackID] = identifier;
        for (NSString *other in sg_pins.allKeys) {
            if (sg_pins.count <= 500) break;
            if (![other isEqualToString:trackID]) [sg_pins removeObjectForKey:other];
        }
        [NSUserDefaults.standardUserDefaults setObject:[sg_pins copy] forKey:SGKeyLyricsPins];
    }
    NSArray *waiting = sg_waiting[trackID];
    [sg_waiting removeObjectForKey:trackID];
    SGKaraokeForgetLyrics(trackID);
    trimKept(trackID);
    sg_kept[trackID] = result;
    @synchronized (sg_missing) { [sg_missing removeObject:trackID]; }
    SGKaraokeKeepSourceLines(trackID, result.karaokeLines ?: @[], result);
    [NSNotificationCenter.defaultCenter postNotificationName:SGLyricsPinDidChangeNotification object:trackID];
    for (void (^done)(SGLyricsResult *) in waiting) done(result);
    return YES;
}

void SGLyricsPickRecord(NSString *trackID, NSDictionary *record, BOOL (^current)(void), void (^done)(BOOL)) {
    if (!trackID.length || ![record isKindOfClass:NSDictionary.class]) { done(NO); return; }
    setUp();
    trackID = [trackID copy];
    record = [record[@"record"] isKindOfClass:NSDictionary.class] ? record[@"record"] : record;
    record = [record copy];
    NSObject *selection = [NSObject new];
    sg_pinSelections[trackID] = selection;
    NSUInteger generation = SGLyricsPinGeneration(trackID);
    SGLyricsTransform(^id { return SGLrcLibRecordResult(record); }, ^(SGLyricsResult *result) {
        BOOL latest = sg_pinSelections[trackID] == selection;
        if (latest) [sg_pinSelections removeObjectForKey:trackID];
        BOOL valid = latest && generation == SGLyricsPinGeneration(trackID) && (!current || current());
        done(valid && pinResult(trackID, record, result));
    });
}

static void reloadTrack(NSString *trackID, BOOL unpin) {
    if (!trackID.length) return;
    setUp();
    SGLyricsRetire(trackID);
    @synchronized (sg_pins) {
        if (unpin) {
            [sg_pins removeObjectForKey:trackID];
            [NSUserDefaults.standardUserDefaults setObject:[sg_pins copy] forKey:SGKeyLyricsPins];
        }
    }
    [sg_kept removeObjectForKey:trackID];
    @synchronized (sg_missing) { [sg_missing removeObject:trackID]; }
    @synchronized (sg_credits) { [sg_credits removeObjectForKey:trackID]; }
    // A new waiter array retires the old walk while keeping everyone who still needs its answer.
    NSMutableArray *waiting = [sg_waiting[trackID] mutableCopy];
    [sg_waiting removeObjectForKey:trackID];
    SGKaraokeForgetLyrics(trackID);
    [NSNotificationCenter.defaultCenter postNotificationName:unpin ? SGLyricsPinDidChangeNotification : SGLyricsDidReloadNotification object:trackID];
    if (waiting) {
        sg_waiting[trackID] = waiting;
        whenNamed(trackID, 0, waiting);
    }
    SGKaraokeRequestLyrics(trackID);
}

void SGLyricsUnpin(NSString *trackID) { reloadTrack(trackID, YES); }
void SGLyricsReload(NSString *trackID) { reloadTrack(trackID, NO); }

// Whether the source's lines are better than what the walk already has: any lines beat none, and
// finer timing beats coarser — words timed beat a line's start, which beats plain text. Read off the
// lines themselves, which say how they were really timed, rather than off what the source claimed.
static BOOL betterLines(SGLyricsResult *merged, SGLyricsResult *fresh) {
    if (!fresh.karaokeLines.count) return NO;
    return !merged.karaokeLines.count || SGKaraokeLinesTiming(fresh.karaokeLines) < SGKaraokeLinesTiming(merged.karaokeLines);
}

// The same for the text Spotify's own page shows: any text beats none, timed beats untimed.
static BOOL betterTexts(SGLyricsResult *merged, SGLyricsResult *fresh) {
    if (!fresh.texts.count) return NO;
    return !merged.texts.count || (fresh.synced && !merged.synced);
}

// How long a lyrics request waits for the player to name its track before the walk starts without a
// name. The request routinely lands a few hundred milliseconds before the player reports the track
// it belongs to, and a walk started in that gap passes over every source that searches by name.
static const NSTimeInterval kNameWait = 1.5, kNamePoll = 0.1;

static BOOL named(SGLyricsQuery *query) {
    return query.title.length && query.artist.length;
}

// The credits that carry links or must show, by their text, as their sources answered. Main queue.
static NSMutableDictionary<NSString *, SGLyricsResult *> *sg_noted;
static const NSUInteger kNotedCredits = 100;

void SGLyricsNoteCredit(SGLyricsResult *result) {
    if (!result.provider.length || !(result.creditRequired || result.creditLinks.count)) return;
    if (!sg_noted) sg_noted = [NSMutableDictionary dictionary];
    if (sg_noted.count >= kNotedCredits) [sg_noted removeAllObjects];
    sg_noted[result.provider] = result;
}

BOOL SGLyricsCreditRequired(NSString *credit) {
    return credit && sg_noted[credit].creditRequired;
}

NSArray<SGLyricsLink *> *SGLyricsCreditLinks(NSString *text) {
    if (!text.length) return nil;
    SGLyricsResult *exact = sg_noted[text];
    if (exact) return exact.creditLinks;
    // The longest credit the text holds, so "Spicy Lyrics, synced by a" is not read as a shorter one.
    SGLyricsResult *found = nil;
    for (NSString *credit in sg_noted) {
        if ([text containsString:credit] && credit.length > found.provider.length) found = sg_noted[credit];
    }
    return found.creditLinks;
}

void SGLyricsOpenCreditLinks(NSArray<SGLyricsLink *> *links, UIView *from) {
    if (!links.count) return;
    if (links.count == 1) {
        [UIApplication.sharedApplication openURL:links.firstObject.url options:@{} completionHandler:nil];
        return;
    }
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:nil message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    for (SGLyricsLink *link in links) {
        NSURL *url = link.url;
        [sheet addAction:[UIAlertAction actionWithTitle:link.title style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            [UIApplication.sharedApplication openURL:url options:@{} completionHandler:nil];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:SGL(@"common.cancel", @"Cancel") style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = from;
    sheet.popoverPresentationController.sourceRect = from.bounds;
    [SGTopController() presentViewController:sheet animated:YES completion:nil];
}

// One walk down the order for one track.
@interface SGLyricsWalk : NSObject
@property (nonatomic, copy) NSArray<NSString *> *order;
@property (nonatomic) NSUInteger index;
@property (nonatomic) BOOL typeFirst;
@property (nonatomic) BOOL concurrent, finished, instrumental;
@property (nonatomic) BOOL budgetReached;
@property (nonatomic) BOOL deferred, advance;
@property (nonatomic, strong) NSMutableSet<NSString *> *started, *inFlight;
@property (nonatomic, strong) dispatch_source_t hedgeTimer, budgetTimer;
@property (nonatomic, strong) NSMutableSet<SGLyricsRequestContext *> *invocations;
@property (nonatomic) BOOL answered;
@property (nonatomic, copy) NSArray<NSString *> *originalOrder;
@property (nonatomic) NSUInteger lineRank, pageRank;
@property (nonatomic) SGKaraokeTiming pageTiming;
@property (nonatomic, strong) SGLyricsQuery *query;
@property (nonatomic, strong) SGLyricsResult *merged;
// Released once; sg_walks and the delivery generation remain the identity after they are drained.
@property (nonatomic, strong) NSMutableArray *waiting;
// Sources that needed a name the query did not have when their turn came.
@property (nonatomic, strong) NSMutableArray<NSString *> *passedOver;
@property (nonatomic) NSUInteger generation, retries;
@property (nonatomic, strong) SGLyricsLease *lease;
@property (nonatomic, strong) NSMutableSet<NSString *> *failures;
@property (nonatomic, strong) NSMutableDictionary<NSString *, SGLyricsResult *> *answers;
@property (nonatomic, strong) NSMutableArray<NSString *> *sequence;
@property (nonatomic, strong) SGLyricsResult *pending;
@property (nonatomic, strong) NSNumber *pin;
@property (nonatomic) BOOL pinnedAnswered, replaying, terminal, settled, retryScheduled;
// The source picked for the track when the walk started, asked first.
@property (nonatomic, copy) NSString *picked;
// The picked source answered with lines, which are the walk's answer however they are timed.
@property (nonatomic) BOOL pickedAnswered;
@end

@implementation SGLyricsWalk
@end

static void cancelTimer(dispatch_source_t timer) {
    if (!timer) return;
    dispatch_source_cancel(timer);
    dispatch_source_set_event_handler(timer, nil);
}

static dispatch_source_t afterSeconds(NSTimeInterval seconds, dispatch_block_t block) {
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(seconds * NSEC_PER_SEC)),
                              DISPATCH_TIME_FOREVER, 0);
    dispatch_source_set_event_handler(timer, ^{
        cancelTimer(timer);
        block();
    });
    dispatch_resume(timer);
    return timer;
}

static BOOL ownsWalk(SGLyricsWalk *walk) {
    return sg_walks[walk.query.trackID] == walk && walk.generation == SGLyricsPinGeneration(walk.query.trackID);
}

void SGLyricsRetire(NSString *track) {
    if (!track.length) return;
    SGLyricsWalk *walk = sg_walks[track];
    cancelTimer(walk.hedgeTimer);
    cancelTimer(walk.budgetTimer);
    [walk.lease invalidate];
    if (walk && !walk.waiting.count && sg_waiting[track] == walk.waiting)
        [sg_waiting removeObjectForKey:track];
    [sg_walks removeObjectForKey:track];
    for (SGLyricsRequestContext *context in [walk.invocations copy]) [context cancelRequests];
    [walk.invocations removeAllObjects];
    [sg_advance removeObject:track];
    SGKaraokeCancelStoreWrite(track);
}

void SGLyricsForgetAnswer(NSString *track) {
    if (!track.length) return;
    SGLyricsInvalidateDelivery(track);
    [sg_kept removeObjectForKey:track];
    [sg_waiting removeObjectForKey:track];
    [sg_failed removeObject:track];
    [sg_spotifyFailed removeObject:track];
    @synchronized (sg_missing) { [sg_missing removeObject:track]; }
}

void SGLyricsForgetAnswerForImportChange(NSString *track) {
    // Detach the old consumers before retiring the walk. Their held responses see the
    // invalidated generation; a reentrant fetch belongs to the new one.
    NSMutableArray *pending = sg_waiting[track];
    NSArray *waiting = [pending copy];
    [pending removeAllObjects];
    SGLyricsForgetAnswer(track);
    for (void (^done)(SGLyricsResult *) in waiting) done(nil);
}

static void trimKept(NSString *track) {
    if (sg_kept.count < kKeptTracks || sg_kept[track]) return;
    for (NSString *other in sg_kept.allKeys) if (![other isEqualToString:track]) SGLyricsRetire(other);
    [sg_kept removeAllObjects];
}

id SGLyricsPersistenceAuthority(NSString *track) {
    id kept = sg_kept[track];
    if ([kept isKindOfClass:SGLyricsResult.class]) return kept;
    return sg_walks[track] ? NSNull.null : nil;
}

BOOL SGLyricsMayPersist(NSString *track, id authority) {
    SGLyricsWalk *walk = sg_walks[track];
    id current = SGLyricsPersistenceAuthority(track);
    if (!current) return !authority;
    return [authority isKindOfClass:SGLyricsResult.class] && [current isKindOfClass:SGLyricsResult.class]
        && SGLyricsSameSheet(authority, current) && ![current provisional]
        && (!walk || (walk.settled && !walk.pending));
}

BOOL SGLyricsRecovering(NSString *track) {
    SGLyricsWalk *walk = sg_walks[track];
    return walk && !walk.settled && (walk.merged.karaokeLines.count || walk.merged.texts.count);
}

BOOL SGLyricsSameSheet(SGLyricsResult *a, SGLyricsResult *b) {
    return a && b && a.karaokeLines == b.karaokeLines && (a.texts == b.texts || [a.texts isEqual:b.texts])
        && (a.starts == b.starts || [a.starts isEqual:b.starts])
        && a.synced == b.synced && a.picked == b.picked && a.instrumental == b.instrumental
        && (a.provider == b.provider || [a.provider isEqual:b.provider])
        && (a.pageProvider == b.pageProvider || [a.pageProvider isEqual:b.pageProvider])
        && a.creditRequired == b.creditRequired
        && (a.creditLinks == b.creditLinks || [a.creditLinks isEqual:b.creditLinks]);
}

BOOL SGLyricsUseSpotify(NSArray<SGKaraokeLine *> *source, NSArray<SGKaraokeLine *> *spotify, BOOL protected) {
    return !protected && spotify.count && (!source.count
        || SGKaraokeLinesTiming(spotify) < SGKaraokeLinesTiming(source));
}

SGLyricsResult *SGLyricsAcceptSpotify(NSString *track, NSArray<SGKaraokeLine *> *lines, id previousAuthority) {
    setUp();
    SGLyricsWalk *walk = sg_walks[track];
    SGLyricsResult *answer = SGLyricsResultWithLines(lines, @"Spotify");
    if (walk.pending && SGLyricsUseSpotify(walk.pending.karaokeLines, lines,
        walk.pinnedAnswered || walk.pending.picked || walk.pending.instrumental)) walk.pending = nil;
    answer.provisional = walk ? !walk.settled || walk.pending != nil
        : previousAuthority && !SGLyricsMayPersist(track, previousAuthority);
    trimKept(track);
    sg_kept[track] = answer;
    @synchronized (sg_missing) { [sg_missing removeObject:track]; }
    return answer;
}

// Only sources that were actually eligible and asked can be blockers. Keep the separate page
// requirement: a word-only answer can still need a timed page from a later provider.
static BOOL failureMatters(SGLyricsWalk *walk, NSString *key) {
    if (walk.pickedAnswered || walk.pinnedAnswered) return NO;
    SGLyricsResult *answer = walk.merged;
    SGKaraokeTiming timing = SGKaraokeLinesTiming(answer.karaokeLines);
    if ([key isEqualToString:@"@pin"]) return YES;
    if ([key isEqualToString:walk.picked] && [walk.picked isEqualToString:SGLyricsChosenSource(walk.query.trackID)]) return YES;
    if (walk.concurrent && answer.karaokeLines.count && timing == SGKaraokeTimingWords) return NO;
    SGLyricsProvider *provider = SGLyricsProviderFor(key);
    NSUInteger rank = [walk.originalOrder indexOfObject:key];
    BOOL earlier = rank <= walk.lineRank;
    if (provider.untimed) {
        if (SGLyricsSourceTypes(key) != SGLyricsTypesAny) return NO;
        BOOL page = !answer.texts.count;
        if (!page && walk.typeFirst) page = walk.pageTiming == SGKaraokeTimingNone && rank < walk.pageRank;
        if (!page && !walk.typeFirst && !answer.synced && walk.pageRank != NSNotFound)
            page = [walk.sequence indexOfObject:key] < [walk.sequence indexOfObject:walk.originalOrder[walk.pageRank]];
        BOOL lines = !answer.karaokeLines.count || (timing == SGKaraokeTimingNone &&
            (walk.typeFirst ? earlier :
             [walk.sequence indexOfObject:key] < [walk.sequence indexOfObject:walk.originalOrder[walk.lineRank]]));
        return page || lines;
    }
    // A timed imported file ends a sequential walk even when it has only line timing.
    if (!walk.concurrent && walk.terminal && walk.lineRank != NSNotFound
        && [walk.originalOrder[walk.lineRank] isEqualToString:SGImportedLRCKey]
        && timing != SGKaraokeTimingWords) return YES;
    if (!answer.karaokeLines.count || timing == SGKaraokeTimingNone) return YES;
    if (walk.typeFirst) {
        if (timing != SGKaraokeTimingWords || earlier) return YES;
        return !answer.texts.count || !answer.synced || rank <= walk.pageRank;
    }
    // In-order stops at the first complete timed answer, including a deferred-by-name source.
    if (!answer.synced || !answer.texts.count) return YES;
    NSString *winner = walk.lineRank == NSNotFound ? nil : walk.originalOrder[walk.lineRank];
    NSString *page = walk.pageRank == NSNotFound ? nil : walk.originalOrder[walk.pageRank];
    NSUInteger stop = MAX(winner ? [walk.sequence indexOfObject:winner] : 0,
                          page ? [walk.sequence indexOfObject:page] : 0);
    return [walk.sequence indexOfObject:key] <= stop;
}

static NSArray<NSString *> *blockers(SGLyricsWalk *walk) {
    NSMutableArray *keys = [NSMutableArray array];
    for (NSString *key in walk.failures) if (failureMatters(walk, key)) [keys addObject:key];
    return keys;
}

static SGLyricsResult *playbackAnswer(SGLyricsWalk *walk, SGLyricsResult *source) {
    NSArray *spotify = SGKaraokeSpotifyLines(walk.query.trackID);
    BOOL protected = walk.pinnedAnswered || source.picked || source.instrumental;
    return SGLyricsUseSpotify(source.karaokeLines, spotify, protected)
        ? SGLyricsResultWithLines(spotify, @"Spotify") : SGLyricsSnapshot(source);
}

static void publishAnswer(SGLyricsWalk *walk, BOOL settled) {
    if (!ownsWalk(walk)) return;
    NSString *track = walk.query.trackID;
    SGLyricsResult *answer = playbackAnswer(walk, walk.merged);
    if (!answer.karaokeLines.count && !answer.texts.count && !answer.instrumental) return;
    answer.provisional = !settled;
    SGLyricsResult *displayed = [sg_kept[track] isKindOfClass:SGLyricsResult.class] ? sg_kept[track] : nil;
    NSArray *keeperLines = SGKaraokeLinesForTrack(track);
    NSArray *shown = keeperLines ?: displayed.karaokeLines;
    BOOL playing = [track isEqualToString:sg_playing ?: SGKaraokePlayingTrack()];
    BOOL upgrade = answer.karaokeLines.count && (!shown.count
        || SGKaraokeLinesTiming(answer.karaokeLines) < SGKaraokeLinesTiming(shown));
    BOOL same = SGLyricsSameSheet(displayed, answer) && (!keeperLines.count
        || (SGKaraokeLinesTiming(shown) == SGKaraokeLinesTiming(answer.karaokeLines)
            && [SGLyricsCreditFor(track) isEqual:answer.provider]));
    // Hedged answers are provisional: priority can still change during the initial walk.
    // Recovery after a finished walk retains the existing next-playback replacement rule.
    BOOL selecting = !walk.concurrent && !walk.finished;
    BOOL defer = playing && shown.count && !upgrade && !same && !selecting;
    if (settled) {
        walk.settled = YES;
        walk.pending = defer ? answer : nil;
        SGKaraokeCancelStoreWrite(track);
        if (!SGLocalFileIs(track) && SGFlag(SGKeyLyricsOffline, YES)) {
            SGLyricsNoteCredit(answer);
            SGLyricsStoreSaveWithLease(track, answer.karaokeLines, answer.provider, walk.lease);
        }
    }
    if (defer) return;
    // Before settlement, even changes to the page projection alone must not mutate a delivered sheet.
    if (!settled && displayed && shown.count && !upgrade && !selecting) return;
    trimKept(track);
    sg_kept[track] = answer;
    @synchronized (sg_missing) { [sg_missing removeObject:track]; }
    if (walk.answered && (!same || upgrade || !shown)) {
        SGKaraokeKeepSourceLines(track, answer.karaokeLines ?: @[], answer);
    }
}

void SGLyricsPlaybackChanged(NSString *track) {
    if (sg_playing == track || [sg_playing isEqualToString:track]) return;
    NSString *left = sg_playing;
    sg_playing = [track copy];
    SGLyricsWalk *walk = left ? sg_walks[left] : nil;
    if (!walk.pending || !ownsWalk(walk)) return;
    SGLyricsResult *answer = playbackAnswer(walk, walk.pending);
    if (!SGLyricsSameSheet(answer, walk.pending) && !SGLocalFileIs(left) && SGFlag(SGKeyLyricsOffline, YES))
        SGLyricsStoreSaveWithLease(left, answer.karaokeLines, answer.provider, walk.lease);
    walk.pending = nil;
    trimKept(left);
    sg_kept[left] = answer;
    SGKaraokeKeepSourceLines(left, answer.karaokeLines ?: @[], answer);
}

static void recoverLater(SGLyricsWalk *walk);

// Musixmatch's community translations are not waited for here: the lines take them as they are kept
// for the lyrics view (Shared/Lyrics/KaraokeSource.x), whichever source won, Spotify included.
static void finish(SGLyricsWalk *walk) {
    if (walk.finished || !ownsWalk(walk)) return;
    cancelTimer(walk.hedgeTimer);
    cancelTimer(walk.budgetTimer);
    walk.finished = YES;
    NSString *trackID = walk.query.trackID;
    BOOL hasAnswer = walk.merged.karaokeLines.count || walk.merged.texts.count || walk.merged.instrumental;
    SGLyricsNoteLoadFailure(trackID, !hasAnswer && (walk.failures.count || walk.passedOver.count));
    if (!ownsWalk(walk)) return;
    NSArray *waiting = [walk.waiting copy];
    [walk.waiting removeAllObjects];
    [sg_waiting removeObjectForKey:trackID];
    if (hasAnswer) {
        publishAnswer(walk, blockers(walk).count == 0);
        if (!ownsWalk(walk)) return;
    } else if (!walk.passedOver.count && !walk.failures.count) {
        trimKept(trackID);
        if (![sg_kept[trackID] isKindOfClass:SGLyricsResult.class]) {
            sg_kept[trackID] = NSNull.null;
            @synchronized (sg_missing) { [sg_missing addObject:trackID]; }
        }
    }
    pruneMissing(trackID);
    for (void (^done)(SGLyricsResult *) in waiting) {
        if (!ownsWalk(walk)) return;
        id answer = sg_kept[trackID];
        done(answer == NSNull.null ? nil : answer);
    }
    walk.answered = hasAnswer;
    if (!ownsWalk(walk)) return;
    if (hasAnswer && !walk.settled) recoverLater(walk);
    else if (!hasAnswer) SGLyricsRetire(trackID);
}

// Both schedulers share delivery, filtering, ranking and upgrade publication.
static BOOL currentWalk(SGLyricsWalk *walk) {
    return ownsWalk(walk) && (!walk.finished || walk.replaying);
}

static BOOL releaseAnswer(SGLyricsWalk *walk) {
    SGLyricsQuery *query = walk.query;
    SGLyricsResult *merged = walk.merged;
    BOOL ready = merged.synced && merged.texts.count && merged.karaokeLines.count;
    BOOL hedged = !walk.concurrent && walk.inFlight.count && merged.karaokeLines.count;
    if (!walk.answered && ((walk.typeFirst && ready) || hedged)) {
        publishAnswer(walk, NO);
        walk.answered = YES;
        while (walk.waiting.count && currentWalk(walk)) {
            void (^done)(SGLyricsResult *) = walk.waiting.firstObject;
            [walk.waiting removeObjectAtIndex:0];
            id current = sg_kept[query.trackID];
            done(current);
        }
        // A waiter may itself have pinned or reloaded the track.
        if (!currentWalk(walk)) return NO;
    }
    return currentWalk(walk);
}

static BOOL mergeReply(SGLyricsWalk *walk, SGLyricsProvider *provider, SGLyricsResult *fresh) {
    if (!currentWalk(walk)) return NO;
    SGLyricsQuery *query = walk.query;
    SGLyricsResult *merged = walk.merged;
    // Even a filtered reply can name the track for a deferred source.
    learnFrom(query, fresh);
    BOOL pick = [provider.key isEqualToString:walk.picked]
        && [walk.picked isEqualToString:SGLyricsChosenSource(query.trackID)];
    // Sequential walks prefer words from providers, not over the user's own timed file.
    // An equally timed source already above the file still wins; All at once keeps its race.
    BOOL imported = !walk.concurrent && fresh.synced
        && [provider.key isEqualToString:SGImportedLRCKey] && betterLines(merged, fresh);
    if (fresh.karaokeLines.count && (pick || imported)) {
        fresh = pick ? pickedSnapshot(fresh) : SGLyricsSnapshot(fresh);
        if (!fresh.provider) fresh.provider = provider.name;
        SGLyricsNoteCredit(fresh);
        walk.merged = fresh;
        walk.pickedAnswered = pick;
        walk.merged.picked = pick;
        walk.lineRank = walk.pageRank = [walk.originalOrder indexOfObject:provider.key];
        walk.terminal = YES;
        return NO;
    }
    SGLyricsTypes allowed = SGLyricsSourceTypes(provider.key);
    SGKaraokeTiming timing = fresh.karaokeLines.count ? SGKaraokeLinesTiming(fresh.karaokeLines)
        : fresh.synced ? SGKaraokeTimingLine : SGKaraokeTimingNone;
    if (![provider.key isEqualToString:SGImportedLRCKey] &&
        ((allowed == SGLyricsTypesSynced && timing == SGKaraokeTimingNone) ||
         (allowed == SGLyricsTypesWords && timing != SGKaraokeTimingWords))) return YES;
    SGLyricsNoteCredit(fresh);
    if (fresh.instrumental) {
        if (walk.concurrent) {
            walk.instrumental = YES;
            return YES;
        }
        if (walk.typeFirst && (merged.karaokeLines.count || merged.texts.count)) return YES;
        SGLog(@"lyrics: %@ is instrumental, by %@", query.trackID, provider.key);
        merged.instrumental = YES;
        walk.terminal = YES;
        return NO;
    }
    NSUInteger rank = [walk.originalOrder indexOfObject:provider.key];
    BOOL finer = betterLines(merged, fresh) || (walk.typeFirst && fresh.karaokeLines.count &&
        timing == SGKaraokeLinesTiming(merged.karaokeLines) && rank < walk.lineRank);
    // In concurrent mode the first actual word timing wins, regardless of source priority.
    if (walk.concurrent && merged.karaokeLines.count &&
        SGKaraokeLinesTiming(merged.karaokeLines) == SGKaraokeTimingWords) finer = NO;
    // Decide both replacements against the old merged answer, not the newly selected lines.
    BOOL replaceText = walk.typeFirst ? fresh.texts.count && (!merged.texts.count || timing < walk.pageTiming ||
        (timing == walk.pageTiming && rank < walk.pageRank)) : betterTexts(merged, fresh);
    if (finer) {
        walk.lineRank = rank;
        merged.karaokeLines = fresh.karaokeLines;
        merged.wordTimed = timing == SGKaraokeTimingWords;
        merged.provider = fresh.provider ?: provider.name;
        merged.creditLinks = fresh.creditLinks;
        merged.creditRequired = fresh.creditRequired;
        if (walk.typeFirst && !walk.concurrent && timing == SGKaraokeTimingLine && walk.index < walk.order.count) {
            SGLog(@"lyrics: %@ line timed by %@, asking on for words timed", query.trackID, merged.provider);
        }
    }
    if (replaceText) {
        walk.pageRank = rank;
        walk.pageTiming = timing;
        merged.starts = fresh.starts;
        merged.texts = fresh.texts;
        merged.synced = fresh.synced;
        if (!merged.provider) merged.provider = fresh.provider ?: provider.name;
        merged.pageProvider = fresh.provider ?: provider.name;
    }
    return currentWalk(walk);
}

static void reselect(SGLyricsWalk *walk) {
    walk.replaying = YES;
    walk.merged = [SGLyricsResult new];
    walk.lineRank = walk.pageRank = NSNotFound;
    walk.pageTiming = SGKaraokeTimingNone;
    walk.terminal = walk.instrumental = walk.pickedAnswered = NO;
    for (NSString *key in walk.sequence) {
        if (!mergeReply(walk, SGLyricsProviderFor(key), walk.answers[key])) break;
        if (!walk.typeFirst && walk.merged.synced && walk.merged.texts.count && walk.merged.karaokeLines.count) break;
    }
    if (walk.concurrent && !walk.merged.karaokeLines.count && !walk.merged.texts.count)
        walk.merged.instrumental = walk.instrumental;
    walk.replaying = NO;
}

static BOOL acceptReply(SGLyricsWalk *walk, SGLyricsProvider *provider, SGLyricsResult *fresh) {
    if (!currentWalk(walk)) return NO;
    if (walk.concurrent || ![walk.sequence containsObject:provider.key]) [walk.sequence addObject:provider.key];
    if (fresh) walk.answers[provider.key] = SGLyricsSnapshot(fresh);
    reselect(walk);
    if (walk.terminal && (walk.concurrent || !walk.inFlight.count)) {
        if (!walk.concurrent && walk.answered) publishAnswer(walk, NO);
        finish(walk);
        return NO;
    }
    if (walk.answered) publishAnswer(walk, NO);
    return currentWalk(walk);
}

static void scheduleWalk(SGLyricsWalk *walk);

static void recovered(SGLyricsWalk *walk, BOOL roundFinished) {
    if (!ownsWalk(walk)) return;
    if (!walk.pinnedAnswered) reselect(walk);
    BOOL deferred = !walk.pinnedAnswered && !walk.pickedAnswered && named(walk.query) && walk.passedOver.count;
    BOOL settled = blockers(walk).count == 0 && !deferred;
    publishAnswer(walk, settled);
    if (!ownsWalk(walk)) return;
    if (deferred && roundFinished) {
        walk.order = [walk.passedOver copy];
        [walk.passedOver removeAllObjects];
        walk.index = 0;
        walk.finished = NO;
        scheduleWalk(walk);
        return;
    }
    if (ownsWalk(walk) && !settled && roundFinished) recoverLater(walk);
}

static void recoverLater(SGLyricsWalk *walk) {
    if (!ownsWalk(walk) || walk.settled || walk.retryScheduled || walk.retries >= SGLyricsRecoveryTries) return;
    NSArray *keys = blockers(walk);
    if (!keys.count) { recovered(walk, YES); return; }
    NSTimeInterval pause = MIN(SGLyricsRetryPause * pow(2, walk.retries), SGLyricsRetryPauseMost);
    walk.retryScheduled = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(pause * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (!ownsWalk(walk)) return;
        walk.retryScheduled = NO;
        if (UIApplication.sharedApplication.applicationState != UIApplicationStateActive && !SGLyricsBackgroundNeeded()) {
            walk.deferred = YES;
            return;
        }
        walk.retries++;
        __block NSUInteger remaining = keys.count;
        for (NSString *key in keys) {
            void (^done)(SGLyricsResult *, BOOL) = ^(SGLyricsResult *fresh, BOOL failed) {
                if (!ownsWalk(walk) || walk.settled) return;
                if (!failed) [walk.failures removeObject:key];
                if ([key isEqualToString:@"@pin"]) {
                    if (fresh.karaokeLines.count || fresh.instrumental) {
                        walk.pinnedAnswered = YES;
                        walk.merged = SGLyricsSnapshot(fresh);
                    }
                } else {
                    if (fresh) walk.answers[key] = SGLyricsSnapshot(fresh);
                    // A concurrent recovery enters the arrival race now, not in its original failure slot.
                    if (walk.concurrent && fresh) {
                        [walk.sequence removeObject:key];
                        [walk.sequence addObject:key];
                    }
                }
                recovered(walk, --remaining == 0);
            };
            if ([key isEqualToString:@"@pin"]) {
                [walk.invocations addObject:invokePin(walk.pin, walk.query, ^BOOL { return ownsWalk(walk) && !walk.settled; }, done)];
            } else [walk.invocations addObject:SGLyricsInvoke(SGLyricsProviderFor(key), walk.query, ^BOOL { return ownsWalk(walk) && !walk.settled; }, done)];
            if (!ownsWalk(walk) || walk.settled) return;
        }
    });
}

static void step(SGLyricsWalk *walk) {
    if (!currentWalk(walk)) return;
    if (UIApplication.sharedApplication.applicationState != UIApplicationStateActive && !SGLyricsBackgroundNeeded()) {
        walk.deferred = YES;
        return;
    }
    SGLyricsQuery *query = walk.query;
    SGLyricsResult *merged = walk.merged;
    // A source that learned the name lets earlier sources search before type first settles a tie.
    if (walk.typeFirst && walk.passedOver.count && named(query)) {
        walk.order = [walk.passedOver arrayByAddingObjectsFromArray:
            [walk.order subarrayWithRange:NSMakeRange(walk.index, walk.order.count - walk.index)]];
        walk.index = 0;
        walk.passedOver = [NSMutableArray array];
    }
    BOOL earlierPending = walk.index < walk.order.count &&
        [walk.originalOrder indexOfObject:walk.order[walk.index]] < walk.lineRank;
    if (walk.terminal || (merged.synced && merged.texts.count && merged.karaokeLines.count &&
        (!walk.typeFirst || (SGKaraokeLinesTiming(merged.karaokeLines) == SGKaraokeTimingWords && !earlierPending)))) {
        if (walk.inFlight.count) releaseAnswer(walk);
        else finish(walk);
        return;
    }
    if (!releaseAnswer(walk)) return;
    if (walk.budgetReached) {
        if (!walk.inFlight.count) finish(walk);
        return;
    }
    if (walk.answered && merged.synced && merged.karaokeLines.count &&
        UIApplication.sharedApplication.applicationState != UIApplicationStateActive) {
        walk.deferred = YES;
        return;
    }
    if (walk.index >= walk.order.count) {
        // A source that matches by id named the track partway down: the ones passed over ask now,
        // in the order they came in. Once, since they cannot be passed over again with a name.
        if (walk.passedOver.count && named(query)) {
            SGLog(@"lyrics: %@ named partway as \"%@\" by \"%@\", asking %@ after all", query.trackID,
                  query.title, query.artist, [walk.passedOver componentsJoinedByString:@", "]);
            walk.order = walk.passedOver;
            walk.index = 0;
            walk.passedOver = [NSMutableArray array];
            step(walk);
            return;
        }
        if (!walk.inFlight.count) finish(walk);
        return;
    }
    SGLyricsProvider *provider = SGLyricsProviderFor(walk.order[walk.index++]);
    // Not yet known asks: wrongly passing Genius over would keep "no lyrics" for a track Spotify has none for.
    // The source picked for the track is asked whatever Spotify has: the pick stands timed or not.
    if (provider.untimed && ![provider.key isEqualToString:walk.picked]
        && (merged.karaokeLines.count || merged.texts.count || SGKaraokeSpotifyLines(query.trackID).count)) {
        step(walk);
        return;
    }
    if (provider.needsName && !named(query)) {
        [walk.passedOver addObject:provider.key];
        step(walk);
        return;
    }
    [walk.started addObject:provider.key];
    [walk.inFlight addObject:provider.key];
    [walk.sequence addObject:provider.key];
    cancelTimer(walk.hedgeTimer);
    __weak SGLyricsWalk *weakWalk = walk;
    NSUInteger nextIndex = walk.index;
    walk.hedgeTimer = afterSeconds(SGLyricsHedgeDelaySeconds, ^{
        SGLyricsWalk *active = weakWalk;
        if (active && currentWalk(active) && active.index == nextIndex &&
            [active.inFlight containsObject:provider.key]) step(active);
    });
    [walk.invocations addObject:SGLyricsInvoke(provider, query, ^BOOL { return currentWalk(walk); }, ^(SGLyricsResult *fresh, BOOL failed) {
        if (!currentWalk(walk)) return;
        [walk.inFlight removeObject:provider.key];
        if (failed) [walk.failures addObject:provider.key];
        // Instrumental counts as no lines here; a failed request does not, as the server may only be busy.
        if ([provider.key isEqualToString:walk.picked] && !fresh.karaokeLines.count && !failed) {
            SGLyricsDropChoice(query.trackID, walk.picked);
        }
        if (acceptReply(walk, provider, fresh)) step(walk);
    })];
}

static void askAll(SGLyricsWalk *walk) {
    if (!currentWalk(walk)) return;
    if (!releaseAnswer(walk)) return;
    if (walk.budgetReached) {
        if (!walk.inFlight.count) finish(walk);
        return;
    }
    if (UIApplication.sharedApplication.applicationState != UIApplicationStateActive &&
        (!SGLyricsBackgroundNeeded() || (walk.answered && walk.merged.synced && walk.merged.karaokeLines.count))) {
        walk.deferred = YES;
        return;
    }
    for (NSString *key in walk.originalOrder) {
        if ([walk.started containsObject:key]) continue;
        SGLyricsProvider *provider = SGLyricsProviderFor(key);
        if (provider.needsName && !named(walk.query)) continue;
        // Genius is a fallback even in concurrent mode, not another speculative request.
        if (provider.untimed && ![key isEqualToString:walk.picked]) {
            if (walk.merged.karaokeLines.count || walk.merged.texts.count || SGKaraokeSpotifyLines(walk.query.trackID).count) {
                [walk.started addObject:key];
                continue;
            }
            BOOL pending = walk.inFlight.count != 0;
            for (NSString *other in walk.originalOrder) {
                SGLyricsProvider *candidate = SGLyricsProviderFor(other);
                if (!candidate.untimed && ![walk.started containsObject:other] &&
                    (!candidate.needsName || named(walk.query))) pending = YES;
            }
            if (pending) continue;
        }
        [walk.started addObject:key];
        [walk.inFlight addObject:key];
        [walk.invocations addObject:SGLyricsInvoke(provider, walk.query, ^BOOL { return currentWalk(walk) && [walk.inFlight containsObject:key]; }, ^(SGLyricsResult *fresh, BOOL failed) {
            // Imported files, missing keys and cached replies may answer synchronously. Every
            // initial eligible ask must start before any reply can merge or exhaust the walk.
            dispatch_async(dispatch_get_main_queue(), ^{
                if (!currentWalk(walk) || ![walk.inFlight containsObject:key]) return;
                [walk.inFlight removeObject:key];
                if (failed) [walk.failures addObject:key];
                if (acceptReply(walk, provider, fresh)) askAll(walk);
            });
        })];
        if (!currentWalk(walk)) return;
    }
    SGLyricsResult *merged = walk.merged;
    if (!releaseAnswer(walk)) return;
    if (merged.karaokeLines.count && SGKaraokeLinesTiming(merged.karaokeLines) == SGKaraokeTimingWords &&
        merged.synced && merged.texts.count) {
        finish(walk);
        return;
    }
    if (walk.inFlight.count) return;
    // All eligible sources have started. Still-unnamed sources are not a cached miss.
    for (NSString *key in walk.originalOrder) {
        if (![walk.started containsObject:key]) [walk.passedOver addObject:key];
    }
    if (!merged.karaokeLines.count && !merged.texts.count) merged.instrumental = walk.instrumental;
    finish(walk);
}

static void scheduleWalk(SGLyricsWalk *walk) {
    if (walk.concurrent) askAll(walk);
    else step(walk);
}

static void startWalk(NSString *trackID, SGLyricsQuery *query) {
    NSMutableArray<NSString *> *order = [SGLyricsOrder() mutableCopy];
    NSString *chosen = SGLyricsChosenSource(trackID);
    if (chosen && [order containsObject:chosen]) {
        [order removeObject:chosen];
        [order insertObject:chosen atIndex:0];
    } else if (chosen) {
        SGLyricsDropChoice(trackID, chosen);
        chosen = nil;
    }
    SGLog(@"lyrics: asking %@ for %@ as \"%@\" by \"%@\", album \"%@\", %lds",
          [order componentsJoinedByString:@", "], trackID, query.title, query.artist, query.album, (long)query.seconds);
    SGLyricsWalk *walk = [SGLyricsWalk new];
    walk.order = order;
    NSInteger mode = SGInt(SGKeyLyricsAskMode, 1);
    walk.typeFirst = mode != 0 || SGFlag(SGKeyLyricsPreferWordTiming, NO);
    walk.concurrent = mode == 2 && !chosen && UIApplication.sharedApplication.applicationState == UIApplicationStateActive;
    walk.started = [NSMutableSet set];
    walk.inFlight = [NSMutableSet set];
    walk.invocations = [NSMutableSet set];
    walk.originalOrder = walk.order;
    walk.lineRank = walk.pageRank = NSNotFound;
    walk.pageTiming = SGKaraokeTimingNone;
    walk.picked = chosen;
    walk.query = query;
    walk.waiting = sg_waiting[trackID];
    walk.merged = [SGLyricsResult new];
    walk.passedOver = [NSMutableArray array];
    walk.failures = [NSMutableSet set];
    walk.answers = [NSMutableDictionary dictionary];
    walk.sequence = [NSMutableArray array];
    walk.generation = SGLyricsPinGeneration(trackID);
    walk.lease = [SGLyricsLease new];
    walk.advance = [sg_advance containsObject:trackID];
    SGLyricsRetire(trackID);
    sg_walks[trackID] = walk;
    SGKaraokeDeferPersistence(trackID);
    __weak SGLyricsWalk *weakWalk = walk;
    walk.budgetTimer = afterSeconds(SGLyricsWalkBudgetSeconds, ^{
        SGLyricsWalk *active = weakWalk;
        if (!active || !currentWalk(active)) return;
        active.budgetReached = YES;
        cancelTimer(active.hedgeTimer);
        for (NSString *key in active.originalOrder) {
            if ([active.started containsObject:key]) continue;
            [active.failures addObject:key];
            // Recovery replays sequential answers in this order, including asks the budget cut off.
            if (!active.concurrent) [active.sequence addObject:key];
        }
        if (!active.inFlight.count) { finish(active); return; }
        publishAnswer(active, NO);
        if (!currentWalk(active)) return;
        BOOL usable = [sg_kept[trackID] isKindOfClass:SGLyricsResult.class];
        SGLyricsNoteLoadFailure(trackID, !usable);
        NSArray *waiting = [active.waiting copy];
        [active.waiting removeAllObjects];
        [sg_waiting removeObjectForKey:trackID];
        active.answered = YES;
        for (void (^done)(SGLyricsResult *) in waiting) {
            if (!currentWalk(active)) return;
            done(usable ? sg_kept[trackID] : nil);
        }
    });
    NSNumber *pin = chosen ? nil : SGLyricsPinnedID(trackID);
    walk.pin = pin;
    if (pin) {
        [walk.invocations addObject:invokePin(pin, query, ^BOOL { return currentWalk(walk); }, ^(SGLyricsResult *result, BOOL failed) {
            if (!currentWalk(walk)) return;
            if (result.karaokeLines.count || result.instrumental) {
                walk.merged = SGLyricsSnapshot(result);
                walk.pinnedAnswered = YES;
                finish(walk);
            } else {
                if (failed) [walk.failures addObject:@"@pin"];
                scheduleWalk(walk);
            }
        })];
    } else scheduleWalk(walk);
}

// Starts the walk as soon as the player has named the track, or once it has waited long enough
// that it is not going to: a track opened for something other than what is playing is never named.
static void whenNamed(NSString *trackID, NSTimeInterval waited, NSMutableArray *waiting) {
    if (sg_waiting[trackID] != waiting || sg_walks[trackID]) return;
    if (UIApplication.sharedApplication.applicationState != UIApplicationStateActive && !SGLyricsBackgroundNeeded()) return;
    SGLyricsQuery *query = SGLyricsQueryFor(trackID);
    if (named(query) || waited >= kNameWait) {
        if (!named(query)) SGLog(@"lyrics: the player never named %@ in %.1fs", trackID, waited);
        startWalk(trackID, query);
        return;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kNamePoll * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        whenNamed(trackID, waited + kNamePoll, waiting);
    });
}

static void fetchLyrics(NSString *trackID, BOOL advance, void (^done)(SGLyricsResult *result)) {
    setUp();
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!trackID.length) {
            done(nil);
            return;
        }
        SGLyricsWalk *walk = sg_walks[trackID];
        if (!advance) {
            [sg_advance removeObject:trackID];
            walk.advance = NO;
        }
        if (walk.deferred && UIApplication.sharedApplication.applicationState == UIApplicationStateActive) {
            walk.deferred = NO;
            if (walk.finished) recoverLater(walk);
            else scheduleWalk(walk);
        }
        id kept = sg_kept[trackID];
        if (kept || (walk.budgetReached && walk.answered && currentWalk(walk))) {
            done(kept == NSNull.null ? nil : kept);
            return;
        }
        NSMutableArray *waiting = sg_waiting[trackID];
        if (waiting) {
            [waiting addObject:[done copy]];
            return;
        }
        sg_waiting[trackID] = [NSMutableArray arrayWithObject:[done copy]];
        if (advance) [sg_advance addObject:trackID];
        whenNamed(trackID, 0, sg_waiting[trackID]);
    });
}

void SGLyricsFetch(NSString *trackID, void (^done)(SGLyricsResult *result)) {
    fetchLyrics(trackID, NO, done);
}

BOOL SGLyricsLoadFailed(NSString *trackID) {
    setUp();
    if (!trackID.length || SGKaraokeLinesForTrack(trackID).count) return NO;
    SGLyricsResult *kept = [sg_kept[trackID] isKindOfClass:SGLyricsResult.class] ? sg_kept[trackID] : nil;
    return !kept.karaokeLines.count && !kept.texts.count && !kept.instrumental &&
        ([sg_failed containsObject:trackID] || [sg_spotifyFailed containsObject:trackID]);
}

static void noteLoadFailure(NSString *trackID, BOOL failed, NSMutableSet *source) {
    if (!trackID.length) return;
    BOOL previous = [sg_failed containsObject:trackID] || [sg_spotifyFailed containsObject:trackID];
    if (failed) {
        if (source.count >= kMissingTracks && ![source containsObject:trackID])
            [source removeObject:source.anyObject];
        [source addObject:trackID];
    } else [source removeObject:trackID];
    BOOL changed = previous != ([sg_failed containsObject:trackID] || [sg_spotifyFailed containsObject:trackID]);
    if (changed) [NSNotificationCenter.defaultCenter postNotificationName:SGKaraokeLinesKeptNotification object:trackID];
}

void SGLyricsNoteLoadFailure(NSString *trackID, BOOL failed) {
    setUp();
    noteLoadFailure(trackID, failed, sg_failed);
}

void SGLyricsNoteSpotifyLoadFailure(NSString *trackID, BOOL failed) {
    setUp();
    noteLoadFailure(trackID, failed, sg_spotifyFailed);
}

void SGLyricsRetry(NSString *trackID) {
    if (!trackID.length) return;
    if (SGKaraokeLinesForTrack(trackID).count) return;
    if ([SGLyricsKeptAnswer(trackID) isKindOfClass:SGLyricsResult.class]) {
        SGKaraokeAskAgain(trackID);
        return;
    }
    SGLyricsReload(trackID);
}

void SGLyricsResumeDeferred(void) {
    for (SGLyricsWalk *walk in sg_walks.allValues) {
        if (!walk.deferred || ![walk.query.trackID isEqual:SGKaraokePlayingTrack()]) continue;
        walk.deferred = NO;
        if (walk.finished) recoverLater(walk);
        else scheduleWalk(walk);
    }
    for (NSString *track in sg_waiting.allKeys) {
        if (!sg_walks[track]) whenNamed(track, 0, sg_waiting[track]);
    }
}

void SGLyricsCancelPrefetch(NSString *trackID) {
    if (!trackID.length) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (![sg_advance containsObject:trackID] && !sg_walks[trackID].advance) return;
        [sg_advance removeObject:trackID];
        SGLyricsRetire(trackID);
        [sg_waiting removeObjectForKey:trackID];
    });
}

BOOL SGLyricsMayHave(NSString *trackID) {
    setUp();
    @synchronized (sg_missing) { return ![sg_missing containsObject:trackID]; }
}

void SGLyricsPrefetch(NSString *trackID) {
    if (!trackID.length) return;
    fetchLyrics(trackID, YES, ^(SGLyricsResult *result) {});
}

NSInteger SGLyricsSpotifyHas(NSString *trackID) {
    setUp();
    if (!trackID) return -1;
    @synchronized (sg_spotifyHas) {
        NSNumber *has = sg_spotifyHas[trackID];
        return has ? has.integerValue : -1;
    }
}

void SGLyricsNoteSpotifyHas(NSString *trackID, BOOL has) {
    setUp();
    if (!trackID.length) return;
    @synchronized (sg_spotifyHas) {
        NSNumber *noted = sg_spotifyHas[trackID];
        if (noted && noted.boolValue == has) return;
        if (sg_spotifyHas.count >= kNotedTracks) [sg_spotifyHas removeAllObjects];
        sg_spotifyHas[trackID] = @(has);
    }
}

NSString *const SGLyricsOwnRequestKey = @"spotifyglass.ownRequest";

// The cards under the player load together, and the list is shown without any card still loading
// once this many milliseconds have passed (NowPlaying_ScrollImpl's scrollCardsAsyncLoadingTimeoutMs,
// 2 s unless the server says otherwise, 1 s at the least). The lyrics card is one of them and waits
// for the color-lyrics reply, which with a source of the mod's on comes after the chain has answered;
// so the wait is set to the most the flag allows.
id SGLyricsForcedFlag(NSString *key) {
    static BOOL on;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ on = SGLyricsEnabled(); });
    if (!on) return nil;
    if ([key isEqualToString:@"ios-nowplaying-scroll-impl.scroll_cards_async_loading_timeout_ms"]) return @5000;
    return nil;
}

// After an override; no row shows the timeout, so nothing is locked.
__attribute__((constructor)) static void registerForcer(void) {
    SGRegisterFlagForcer(NO, ^id(NSString *key) { return SGLyricsForcedFlag(key); }, nil);
}

#pragma mark - the language of translations

NSArray<NSString *> *SGLyricsTranslationLanguages(void) {
    return @[@"", @"ar", @"zh-Hans", @"zh-Hant", @"cs", @"da", @"nl", @"en", @"fi", @"fr", @"de", @"el", @"he",
             @"hi", @"hu", @"id", @"it", @"ja", @"ko", @"nb", @"pl", @"pt", @"ro", @"ru", @"sk", @"es", @"sv",
             @"th", @"tr", @"uk", @"vi"];
}

NSArray<NSString *> *SGLyricsTranslationLanguageNames(void) {
    NSLocale *english = [NSLocale localeWithLocaleIdentifier:@"en"];
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (NSString *tag in SGLyricsTranslationLanguages()) {
        [names addObject:tag.length ? [english localizedStringForLocaleIdentifier:tag] ?: tag : SGL(@"settings.lyricssources.translationlanguage.choice.any", @"Any · iPhone's language")];
    }
    return names;
}

NSString *SGLyricsTranslationLanguage(void) {
    NSArray<NSString *> *tags = SGLyricsTranslationLanguages();
    NSInteger index = SGInt(SGKeyLyricsTranslationLanguage, 0);
    return index > 0 && index < (NSInteger)tags.count ? tags[(NSUInteger)index] : nil;
}

NSString *SGLyricsCreditFor(NSString *trackID) {
    setUp();
    @synchronized (sg_credits) { return trackID ? sg_credits[trackID] : nil; }
}

void SGLyricsSetCredit(NSString *trackID, NSString *name) {
    setUp();
    if (!trackID.length) return;
    @synchronized (sg_credits) {
        if (sg_credits.count >= kKeptTracks) [sg_credits removeAllObjects];
        sg_credits[trackID] = name ?: @"Spotify";
    }
}

// Once, at launch: the keys Musixmatch owned alone become an order, so the Lyrics page opens on what
// the install was already doing rather than on nothing.
void SGLyricsMigrateLegacyKeys(void) {
    SGMigrateKey(SGKeyLyricsTypeFirst, SGKeyLyricsAskMode);
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    if ([defaults objectForKey:SGKeyLyricsProviders]) return;
    NSArray<NSString *> *order = fromLegacyKeys();
    if (!order.count) return;
    SGLyricsSetOrder(order);
    SGSetEnabled(SGKeyLyricsAllTracks, SGFlag(kLegacyAllTracks, NO));
    SGLog(@"lyrics: carried the Musixmatch switches over as %@", [order componentsJoinedByString:@", "]);
}

UIViewController *SGLyricsSourcesPage(void) {
    NSMutableArray<SGSource *> *all = [NSMutableArray array];
    for (SGLyricsProvider *provider in SGLyricsAllProviders()) {
        // The page is made on every open, so a key refused since the last one says so here.
        NSString *detail = [provider.key isEqualToString:SGSpicyLyricsKey] ? SGSpicyLyricsStatus() ?: provider.detail : provider.detail;
        [all addObject:[SGSource sourceWithKey:provider.key name:provider.name detail:detail]];
    }
    return SGSourcesPageMake(SGL(@"settings.lyricssources.title", @"Lyrics sources"), SGL(@"settings.lyricssources.intro", @"Drag to set source priority. Choose how sources are asked in Request mode & lyric types. In All at once mode, the first word-timed answer wins regardless of order. Deezer uses your own login cookie when you add it."),
                             all, ^NSArray<NSString *> * { return SGLyricsOrder(); }, ^(NSArray<NSString *> *keys) { SGLyricsSetOrder(keys); });
}

SGLyricsTypes SGLyricsSourceTypes(NSString *key) {
    if (!key.length || [key isEqualToString:SGImportedLRCKey]) return SGLyricsTypesAny;
    id stored = [NSUserDefaults.standardUserDefaults dictionaryForKey:SGKeyLyricsSourceTypes][key];
    if (![stored isKindOfClass:NSNumber.class]) return SGLyricsTypesAny;
    NSInteger value = [stored integerValue];
    return value >= SGLyricsTypesAny && value <= SGLyricsTypesWords ? value : SGLyricsTypesAny;
}

void SGLyricsSetSourceTypes(NSString *key, SGLyricsTypes types) {
    if (!key.length || [key isEqualToString:SGImportedLRCKey] || types < SGLyricsTypesAny || types > SGLyricsTypesWords) return;
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSMutableDictionary *stored = [[defaults dictionaryForKey:SGKeyLyricsSourceTypes] mutableCopy] ?: [NSMutableDictionary dictionary];
    if (types == SGLyricsTypesAny) [stored removeObjectForKey:key];
    else stored[key] = @(types);
    [defaults setObject:stored forKey:SGKeyLyricsSourceTypes];
}

#pragma mark - a source picked for a track (LyricsPick.m)

NSUInteger SGLyricsFailures(void) {
    return atomic_load(&sg_failures);
}

// The picked answer stands in for the walk's, so a later request for the track, Spotify's own page's included,
// gets the same lines. A source that times words but has no page text gets the page lines made from its own.
void SGLyricsKeepChosen(NSString *trackID, SGLyricsResult *result) {
    setUp();
    SGLyricsRetire(trackID);
    result = pickedSnapshot(result);
    SGLyricsNoteCredit(result);
    trimKept(trackID);
    sg_kept[trackID] = result;
    @synchronized (sg_missing) { [sg_missing removeObject:trackID]; }
    NSArray *waiting = [sg_waiting[trackID] copy];
    [sg_waiting removeObjectForKey:trackID];
    NSUInteger generation = SGLyricsPinGeneration(trackID);
    for (void (^done)(SGLyricsResult *) in waiting) {
        if (generation != SGLyricsPinGeneration(trackID)) break;
        done(result);
    }
}

id SGLyricsKeptAnswer(NSString *trackID) {
    setUp();
    return sg_kept[trackID];
}

void SGLyricsRestoreKept(NSString *trackID, id kept) {
    setUp();
    SGLyricsRetire(trackID);
    // Automatic changes the order, even when a saved answer can be shown immediately.
    // Retire the promoted-source walk, preserving its consumers for a fresh configured-order walk.
    NSMutableArray *waiting = [sg_waiting[trackID] mutableCopy];
    [sg_waiting removeObjectForKey:trackID];
    // Preserve the old consumers before the keeper retires the picked sheet and its disk entry.
    SGKaraokeForgetLyrics(trackID);
    if ([kept isKindOfClass:SGLyricsResult.class]) kept = SGLyricsSnapshot(kept);
    if (kept) sg_kept[trackID] = kept;
    else [sg_kept removeObjectForKey:trackID];
    @synchronized (sg_missing) {
        if (kept == NSNull.null) [sg_missing addObject:trackID];
        else [sg_missing removeObject:trackID];
    }
    BOOL provisional = [kept isKindOfClass:SGLyricsResult.class] && [kept provisional];
    if (waiting || provisional) {
        if (!waiting) waiting = [NSMutableArray array];
        sg_waiting[trackID] = waiting;
        whenNamed(trackID, 0, waiting);
    }
    pruneMissing(trackID);
}
