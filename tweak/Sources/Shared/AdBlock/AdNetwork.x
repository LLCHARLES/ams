// Spotify's responses on their way in, through the URLSession delegates it reads them by:
// SPTDataLoaderService and HttpClientURLSession for the app's own requests, and
// SPTCoreURLSessionDataDelegate for the C++ core's, which fetch the ad config (ads/v2/config and
// ad-logic/state/config, device 2026-10-10). A request for an ad is answered
// empty. With Spoof Premium on, the bootstrap and customize bodies are rewritten by Premium.m
// before the client sees them (on 9.2, which has no customize, its account attributes and remote
// config, which come on their own), the endpoints the server would use to log the account out are
// answered as if they succeeded, and past the first thirty seconds the re-fetches that could bring
// the real state back are canceled before they leave. Feeds go through Feeds.m. Everything here is
// EeveeSpotify's, less its Ably hooks, which it does not turn on for 9.1 either.
#import "Core/SGCore.h"
#import "AdBlock.h"
#import "OfflineCompanion.h"
#import <mach-o/dyld.h>
#import <mach-o/loader.h>

static BOOL ads, premium;
// Spoof Premium on Spotify 9.2 or later. 9.1.x still gets both parts inside customize, and keeps the
// path it was tested on.
static BOOL premiumSplit;
static NSDate *started;
static NSObject *cacheLock;
static NSData *cachedCustomize;   // the last rewritten customize body, for a 304 and the re-fetches
static const NSUInteger offlineBodyLimitBytes = 4 * 1024 * 1024;
@interface SGOfflineInput : NSObject
@property NSURL *url;
@property NSData *body;
@end
@implementation SGOfflineInput @end
// Only standalone nebula bytes belong here; Pixie owns bootstrap/customize interception.
static NSMutableDictionary<NSNumber *, SGOfflineInput *> *offlineInputs;
static __weak NSURLSession *offlineSession;
static NSString *offlineAuthorization;
static uint64_t offlineGeneration;
static dispatch_queue_t offlineInstallQueue;
@interface SGOfflineResponse : NSObject
@property BOOL enabled, bypass;
@property uint64_t generation;
@property NSURL *url;
@property NSMutableData *buffer;
@end
@implementation SGOfflineResponse @end
static char kBufferKey, kServedKey, kPassKey, kKindKey, kOfflineKey, kGenerationKey, kOfflineReplayKey, kAdResponseKey, kAdDispositionKey, kAdCompleteKey;

typedef NS_ENUM(NSInteger, SGNet) { SGNetPass, SGNetBlock, SGNetPatch };

static NSTimeInterval elapsed(void) {
    return -started.timeIntervalSinceNow;
}

static BOOL has(NSString *text, NSString *needle) {
    return [text containsString:needle];
}

static BOOL isBootstrap(NSString *path) { return has(path, @"v1/bootstrap"); }
static BOOL isCustomize(NSString *path) { return has(path, @"v1/customize"); }
static BOOL isAttributes(NSString *path) { return [path isEqualToString:@"/nebula/v1/configuration/attributes"]; }
// The signed-in configuration only; v3/unauth/configuration is the logged-out one.
static BOOL isRemoteConfig(NSString *path) { return has(path, @"/remote-config-resolver/v3/configuration"); }
static BOOL isSplitConfig(NSString *path) { return isAttributes(path) || isRemoteConfig(path); }

static NSUInteger offlineEndpoint(NSURL *url) {
    NSString *host = url.host.lowercaseString;
    if (![url.scheme.lowercaseString isEqual:@"https"]
        || !([host isEqual:@"spotify.com"] || [host hasSuffix:@".spotify.com"])) return 0;
    return isAttributes(url.path) ? 3 : 0;
}

static BOOL isOfflineConfig(NSURL *url) {
    return offlineEndpoint(url) != 0;
}

// The feeds Home, Search and the page under the player are built from. casita/v1/feeds is the flat
// list of tab chips, not sections.
static BOOL isFeed(NSString *path) {
    if (has(path, @"/casita/v1/feeds")) return NO;
    return has(path, @"/browsita/") || has(path, @"/casita/") || has(path, @"/scrollsita/");
}

static BOOL isLogout(NSString *path) {
    return has(path, @"logout") || has(path, @"sign-out") || has(path, @"session/purge") || has(path, @"token/revoke")
        || has(path, @"auth/expire") || (has(path, @"melody") && has(path, @"check")) || has(path, @"product-state")
        || (has(path, @"license") && has(path, @"check")) || has(path, @"deletetoken");
}

static NSString *const adPaths[] = {
    @"/ads/", @"/ad-logic/", @"/dac/view/v1/", @"/ad-slot/", @"/ad-inventory/", @"/ad-on-app-open", @"/sponsored/",
    @"/promoted/", @"/upsell/", @"/premium-upsell", @"/upsell-banner", @"/upsell-card", @"/referrals/upsell",
    @"/campaign/", @"/billboard/", @"/banner/", @"/interstitial/", @"/overlay/", @"/popup/", @"/pop-up/",
    @"/search-ad/", @"/home-ad/", @"/marquee/", @"/leavebehind", @"/leave-behind", @"/display-ad/", @"/fullbleed/",
    @"/leaderboard/", @"/ad-card/", @"/sponsored-content/", @"/sponsored-ad/", @"/native-ad/", @"/sponsored-shelf/",
    @"/sponsored-row/", @"/ad-shelf/", @"/ad-row/", @"/sponsored-item/", @"/ad-item/", @"/merchandising/",
    @"/upgrade-component/", @"/marketing/", @"/home-ads/", @"/search-ads/",
};

// Esperanto service names use dot/underscore-separated identifiers as well as URL
// path segments. A word-boundary regex alone would not split underscores. Match
// whole ad/slot tokens after /esperanto/, never the "ad" inside load or metadata.
static BOOL isEsperantoAd(NSString *path) {
    NSRange marker = [path rangeOfString:@"/esperanto/"];
    if (marker.location == NSNotFound) return NO;
    static NSRegularExpression *tokens;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        tokens = [NSRegularExpression regularExpressionWithPattern:@"(?:^|[/._-])(?:ads?|slots?)(?=$|[/._-])"
                                                          options:0 error:NULL];
    });
    NSString *route = [path substringFromIndex:NSMaxRange(marker)];
    return [tokens firstMatchInString:route options:0 range:NSMakeRange(0, route.length)] != nil;
}

static BOOL isAd(NSURL *url, NSString *path) {
    // EeveeSpotifyReincarnated 43b9ca3: spclient also uses a terminal /ads.
    if ([path hasSuffix:@"/ads"]) return YES;
    for (size_t i = 0; i < sizeof(adPaths) / sizeof(adPaths[0]); i++) {
        if (has(path, adPaths[i])) return YES;
    }
    if (isEsperantoAd(path)) return YES;
    NSString *host = url.host.lowercaseString ?: @"";
    return has(host, @"doubleclick") || has(host, @"googlesyndication") || [host hasPrefix:@"aet."]
        || [host isEqualToString:@"ad.spotify.com"] || [host isEqualToString:@"ads.spotify.com"]
        || [host isEqualToString:@"aet.spotify.com"];
}

// The first thirty seconds are a fresh login's: signup/public and customize are part of it, and
// answering them broke first launch.
static BOOL isRefetch(NSString *path) {
    return has(path, @"signup/public") || has(path, @"select-ondemand-set") || has(path, @"trials-facade/start-trial")
        || has(path, @"premium-marketing/upselloffer") || (has(path, @"pendragon") && has(path, @"fetchmessagelist"))
        || has(path, @"pushka-tokens") || has(path, @"apresolve") || has(path, @"pses/screenconfig") || isCustomize(path);
}

// What a request's URL makes it, worked out once per task: its data comes in many chunks.
enum { kBlocked = 1, kRefetch = 2, kPatched = 4, kAd = 8 };

static unsigned kindOf(NSURL *url) {
    NSString *path = url.path.lowercaseString ?: @"";
    return (ads && isAd(url, path) ? kAd : 0)
         | (premium && isLogout(path) ? kBlocked : 0)
         | (premium && isRefetch(path) ? kRefetch : 0)
         | ((premium && (isBootstrap(path) || isCustomize(path))) || (premiumSplit && isSplitConfig(path))
            || (ads && isFeed(path)) ? kPatched : 0);
}

// The thirty seconds are read at each call, as the task's data and its end arrive.
// The kind is worked out once per URL the task is on: a redirect moves it to another, which is classified again.
static unsigned taskKind(NSURLSessionTask *task, NSURL *url) {
    id key = url ?: (id)NSNull.null;
    NSArray *stored = objc_getAssociatedObject(task, &kKindKey);   // @[url, kind]
    if (!stored || (stored[0] != key && ![stored[0] isEqual:key])) {
        stored = @[key, @(kindOf(url))];
        // resume and the delegate queue can both read the cached classification.
        objc_setAssociatedObject(task, &kKindKey, stored, OBJC_ASSOCIATION_RETAIN);
    }
    return [stored[1] unsignedIntValue];
}

static SGNet classify(NSURLSessionTask *task) {
    unsigned kind = taskKind(task, task.currentRequest.URL);
    if ((kind & (kBlocked | kAd)) || ((kind & kRefetch) && elapsed() > 30)) return SGNetBlock;
    return kind & kPatched ? SGNetPatch : SGNetPass;
}

static NSData *cached(void) {
    @synchronized (cacheLock) { return cachedCustomize; }
}

static uint64_t offlineContext(NSURLSession *session, NSURLRequest *request) {
    NSString *authorization = [request valueForHTTPHeaderField:@"Authorization"];
    @synchronized (cacheLock) {
        if (offlineSession != session || !((!authorization && !offlineAuthorization) || [authorization isEqual:offlineAuthorization])) {
            [offlineInputs removeAllObjects];
            offlineSession = session;
            offlineAuthorization = [authorization copy];
            offlineGeneration++;
        }
        return offlineGeneration;
    }
}

static void clearOfflineSession(NSURLSession *session) {
    @synchronized (cacheLock) {
        if (!session || offlineSession == session) {
            [offlineInputs removeAllObjects];
            offlineSession = nil;
            offlineAuthorization = nil;
            offlineGeneration++;
        }
    }
}

static void observeAccountRequest(NSURLRequest *request) {
    NSString *host = request.URL.host.lowercaseString;
    if (([host isEqual:@"spotify.com"] || [host hasSuffix:@".spotify.com"])
        && (isLogout(request.URL.path.lowercaseString) || [host isEqual:@"login5.spotify.com"]))
        clearOfflineSession(nil);
}

// Pixie's offline values, then on 9.2 Spoof Premium's attributes: the two set different keys. Pixie's hooks
// take the body before the Premium ones see it, so both are applied here.
static NSData *offlineAttributes(NSData *raw, BOOL *recognized) {
    NSData *result = SGPatchOfflineAccountAttributes(raw, recognized);
    return premiumSplit ? SGPatchAccountAttributes(result) ?: result : result;
}

static NSData *cachedOffline(NSURL *url, uint64_t generation) {
    NSData *input;
    @synchronized (cacheLock) {
        SGOfflineInput *entry = offlineInputs[@(offlineEndpoint(url))];
        if (generation == offlineGeneration && [entry.url isEqual:url]) input = entry.body;
    }
    if (!input) return nil;
    BOOL recognized = NO;
    // Replay is read-only, including when another delegate completes a newer response here.
    NSData *result = offlineAttributes(input, &recognized);
    @synchronized (cacheLock) { return generation == offlineGeneration ? result : nil; }
}

static void storeOffline(NSURL *url, uint64_t generation, NSData *body) {
    SGOfflineInput *entry = [SGOfflineInput new];
    entry.url = url;
    entry.body = [body copy];
    @synchronized (cacheLock) {
        if (generation == offlineGeneration) offlineInputs[@(offlineEndpoint(url))] = entry;
    }
}

static NSHTTPURLResponse *rewrittenResponse(NSHTTPURLResponse *response, NSInteger status) {
    NSMutableDictionary *headers = [response.allHeaderFields mutableCopy];
    for (NSString *key in headers.allKeys) {
        if ([@[@"content-length", @"etag", @"last-modified", @"content-md5", @"digest", @"content-encoding"] containsObject:key.lowercaseString])
            [headers removeObjectForKey:key];
    }
    return [[NSHTTPURLResponse alloc] initWithURL:response.URL statusCode:status HTTPVersion:@"HTTP/2.0" headerFields:headers];
}

static BOOL fullResponse(NSHTTPURLResponse *response, NSURLRequest *request) {
    return response.statusCode == 200 && ![response valueForHTTPHeaderField:@"Content-Range"]
        && ![request valueForHTTPHeaderField:@"Range"];
}

static NSData *json(NSString *text) {
    return [text dataUsingEncoding:NSUTF8StringEncoding];
}

// The body a blocked request is answered with: what its reader parses for, so that nothing is
// retried and no logout path taken.
static NSData *blockedReply(NSString *path) {
    if (has(path, @"signup/public")) return json(@"{\"status\":1,\"country\":\"US\",\"is_country_launched\":true}");
    if (has(path, @"trials-facade")) return json(@"{\"result\":\"NOT_ELIGIBLE\"}");
    if (has(path, @"premium-marketing") || has(path, @"pses/screenconfig")) return json(@"{}");
    if (isLogout(path) || has(path, @"apresolve")) return json(@"{\"status\":\"OK\"}");
    if (isCustomize(path) && cached()) return cached();
    return [NSData data];
}

static NSData *patched(NSURL *url, NSData *body) {
    NSString *path = url.path.lowercaseString ?: @"";
    if (isFeed(path)) return SGStripFeed(body);
    SGAdBlockSawOne(@"Config rewrites");
    NSData *result = isAttributes(path) ? SGPatchAccountAttributes(body)
        : isRemoteConfig(path) ? SGPatchRemoteConfiguration(body)
        : isBootstrap(path) ? SGPatchBootstrap(body) : SGPatchCustomize(body);
    if (!result) {
        SGLog(@"could not rewrite %@, passed through", path);
        return nil;
    }
    if (isCustomize(path)) {
        @synchronized (cacheLock) { cachedCustomize = result; }
    }
    SGAdBlockCountOne(@"Config rewrites");
    SGLog(@"rewrote %@, %lu -> %lu bytes", path, (unsigned long)body.length, (unsigned long)result.length);
    return result;
}

#pragma mark - the delegate's three calls

// Data handed to the delegate by the mod goes through its hooked didReceiveData like Spotify's own,
// with the pass mark on the task so the hook lets it by.
static void deliver(id<NSURLSessionDataDelegate> delegate, NSURLSession *session, NSURLSessionTask *task, NSData *data) {
    objc_setAssociatedObject(task, &kPassKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [delegate URLSession:session dataTask:(NSURLSessionDataTask *)task didReceiveData:data];
    objc_setAssociatedObject(task, &kPassKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static BOOL blockedAdTask(NSURLSessionTask *task) {
    NSURL *url = task.currentRequest.URL ?: task.originalRequest.URL;
    return ads && (taskKind(task, url) & kAd);
}

static NSHTTPURLResponse *emptyAdResponse(NSURLSessionTask *task) {
    return [[NSHTTPURLResponse alloc] initWithURL:task.currentRequest.URL ?: task.originalRequest.URL
                                     statusCode:200 HTTPVersion:@"HTTP/2.0"
                                   headerFields:@{@"Content-Length": @"0"}];
}

// All three Spotify delegates consume response -> data -> completion, even when resume canceled
// before Foundation produced headers. Reuse an already delivered response rather than send two.
typedef void (^SGResponseHandler)(NSURLSessionResponseDisposition);
static BOOL receiveAdResponse(NSURLSessionTask *task, SGResponseHandler handler,
                              void (^receive)(NSHTTPURLResponse *, SGResponseHandler)) {
    if (!blockedAdTask(task)) return NO;
    if (objc_getAssociatedObject(task, &kAdResponseKey)) {
        handler(NSURLSessionResponseCancel);
        return YES;
    }
    objc_setAssociatedObject(task, &kAdResponseKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    receive(emptyAdResponse(task), ^(NSURLSessionResponseDisposition disposition) {
        objc_setAssociatedObject(task, &kAdDispositionKey, @(disposition), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        handler(disposition);
    });
    return YES;
}

static char kRequestCounted;
static void countRequest(NSURLSessionTask *task, BOOL blocked) {
    @synchronized (task) {
        if (objc_getAssociatedObject(task, &kRequestCounted)) return;
        objc_setAssociatedObject(task, &kRequestCounted, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    SGAdBlockSawOne(@"Requests");
    if (blocked) SGAdBlockCountOne(@"Requests");
}

static BOOL completeAd(id<NSURLSessionDataDelegate> delegate, NSURLSession *session, NSURLSessionTask *task,
                       void (^finish)(NSError *)) {
    if (!blockedAdTask(task)) return NO;
    if (objc_getAssociatedObject(task, &kAdCompleteKey)) return YES;
    objc_setAssociatedObject(task, &kAdCompleteKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    void (^accepted)(NSURLSessionResponseDisposition) = ^(NSURLSessionResponseDisposition disposition) {
        void (^end)(void) = ^{
            if (disposition != NSURLSessionResponseAllow) {
                finish([NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCancelled userInfo:nil]);
                return;
            }
            countRequest(task, YES);
            deliver(delegate, session, task, [NSData data]);
            finish(nil);
        };
        // A delegate may answer the response handler asynchronously on another queue.
        // Data and the original completion still belong to Foundation's delegate queue.
        [session.delegateQueue addOperationWithBlock:end];
    };
    // Foundation waits for the response decision before issuing its completion.
    if (objc_getAssociatedObject(task, &kAdResponseKey))
        accepted([objc_getAssociatedObject(task, &kAdDispositionKey) integerValue]);
    else [delegate URLSession:session dataTask:(NSURLSessionDataTask *)task
           didReceiveResponse:emptyAdResponse(task) completionHandler:accepted];
    return YES;
}

// A conditional nebula reply uses server bytes captured under the task's original session.
static NSURLResponse *responseFor(NSURLSessionTask *task, NSURLResponse *response) {
    NSURL *url = task.currentRequest.URL;
    if (!isOfflineConfig(url)) {
        // A later response on the same task must supersede any earlier offline buffer.
        if (objc_getAssociatedObject(task, &kOfflineKey))
            objc_setAssociatedObject(task, &kOfflineKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return response;
    }
    SGOfflineResponse *state = [SGOfflineResponse new];
    state.enabled = SGOfflineCompanionLoaded();
    state.url = url;
    objc_setAssociatedObject(task, &kOfflineKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (state.enabled) {
        NSNumber *generation = objc_getAssociatedObject(task, &kGenerationKey);
        // Tasks predating hook installation can be transformed, but cannot seed or replay a cache.
        state.generation = generation ? generation.unsignedLongLongValue : UINT64_MAX;
        state.bypass = ![response isKindOfClass:NSHTTPURLResponse.class]
            || !fullResponse((NSHTTPURLResponse *)response, task.currentRequest)
            || response.expectedContentLength > (int64_t)offlineBodyLimitBytes;
        if ([response isKindOfClass:NSHTTPURLResponse.class] && ((NSHTTPURLResponse *)response).statusCode == 304
            && ![task.currentRequest valueForHTTPHeaderField:@"Range"]
            && ![(NSHTTPURLResponse *)response valueForHTTPHeaderField:@"Content-Range"]) {
            NSData *body = cachedOffline(url, state.generation);
            if (body) {
                objc_setAssociatedObject(task, &kOfflineReplayKey, body, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                return rewrittenResponse((NSHTTPURLResponse *)response, 200);
            }
        }
        // Length is unknown until transformation; omit it and validators before streaming starts.
        return state.bypass ? response : rewrittenResponse((NSHTTPURLResponse *)response, 200);
    }
    return response;
}

static BOOL holdsOffline(id<NSURLSessionDataDelegate> delegate, NSURLSession *session, NSURLSessionTask *task, NSData *data) {
    if (objc_getAssociatedObject(task, &kPassKey)) return NO;
    if (objc_getAssociatedObject(task, &kOfflineReplayKey)) return YES;
    SGOfflineResponse *state = objc_getAssociatedObject(task, &kOfflineKey);
    if (state.enabled) {
        if (state.bypass) return NO;
        if (data.length > offlineBodyLimitBytes - state.buffer.length) {
            state.bypass = YES;
            NSData *prefix = state.buffer;
            state.buffer = nil;
            if (prefix.length) deliver(delegate, session, task, prefix);
            return NO;
        }
        if (!state.buffer) state.buffer = [NSMutableData new];
        [state.buffer appendData:data];
        return YES;
    }
    return NO;
}

static void completeOffline(id<NSURLSessionDataDelegate> delegate, NSURLSession *session, NSURLSessionTask *task, NSError *error) {
    SGOfflineResponse *state = objc_getAssociatedObject(task, &kOfflineKey);
    NSData *raw = state.buffer;
    state.buffer = nil;
    if (state.enabled && !state.bypass && raw) {
        BOOL recognized = NO;
        NSData *result = error ? raw : offlineAttributes(raw, &recognized);
        if (recognized) storeOffline(state.url, state.generation, raw);
        deliver(delegate, session, task, result);
    }
}

static SGResponseHandler replayBody(id<NSURLSessionDataDelegate> delegate, NSURLSession *session,
                                       NSURLSessionTask *task, NSData *body, SGResponseHandler handler) {
    if (!body) return handler;
    return ^(NSURLSessionResponseDisposition disposition) {
        void (^accepted)(void) = ^{
            if (disposition == NSURLSessionResponseAllow) deliver(delegate, session, task, body);
            // Foundation may issue completion as soon as this is called.
            handler(disposition);
        };
        [session.delegateQueue addOperationWithBlock:accepted];
    };
}

static SGResponseHandler replayDecision(id<NSURLSessionDataDelegate> delegate, NSURLSession *session,
                                       NSURLSessionTask *task, SGResponseHandler handler) {
    return replayBody(delegate, session, task, objc_getAssociatedObject(task, &kOfflineReplayKey), handler);
}

// A customize the server says has not changed, answered with the rewritten one from last time.
static NSHTTPURLResponse *replayFor(NSURLSessionTask *task, NSURLResponse *response) {
    if (!premium || ![response isKindOfClass:NSHTTPURLResponse.class] || ((NSHTTPURLResponse *)response).statusCode != 304) return nil;
    NSURL *url = task.currentRequest.URL;
    if (!isCustomize(url.path.lowercaseString ?: @"")) return nil;
    NSData *body = cached();
    if (!body) return nil;
    objc_setAssociatedObject(task, &kServedKey, body, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return [[NSHTTPURLResponse alloc] initWithURL:url statusCode:200 HTTPVersion:@"HTTP/2.0" headerFields:@{}];
}

// YES when the data is not the delegate's to see yet: dropped for a blocked request, kept back for
// one whose reply is rewritten when it finishes.
static BOOL holds(NSURLSessionTask *task, NSData *data) {
    if (objc_getAssociatedObject(task, &kPassKey)) return NO;
    switch (classify(task)) {
        case SGNetBlock:
            return YES;
        case SGNetPatch: {
            NSMutableData *buffer = objc_getAssociatedObject(task, &kBufferKey);
            if (!buffer) objc_setAssociatedObject(task, &kBufferKey, (buffer = [NSMutableData data]), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            [buffer appendData:data];
            return YES;
        }
        default:
            return NO;
    }
}

static void complete(id<NSURLSessionDataDelegate> delegate, NSURLSession *session, NSURLSessionTask *task, NSError *error, void (^finish)(NSError *)) {
    if (completeAd(delegate, session, task, finish)) return;
    NSURL *url = task.currentRequest.URL;
    NSString *path = url.path.lowercaseString ?: @"";
    NSMutableData *buffer = objc_getAssociatedObject(task, &kBufferKey);
    objc_setAssociatedObject(task, &kBufferKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (objc_getAssociatedObject(task, &kServedKey)) {
        countRequest(task, NO);
        finish(error);
        return;
    }
    SGNet kind = classify(task);
    countRequest(task, kind == SGNetBlock);
    switch (kind) {
        case SGNetBlock:
            SGLog(@"answered %@ empty", path);
            deliver(delegate, session, task, blockedReply(path));
            finish(nil);
            return;
        case SGNetPatch:
            if (error) {
                finish(error);
                return;
            }
            // Nothing to rewrite: a 304, or a body of no bytes. The delegate is told of a body either
            // way, since a completion with none hangs some readers. 9.2's two are left as the server sent
            // them: an empty body there would clear the account's state instead of keeping the cached one.
            if (!buffer) {
                if (!isSplitConfig(path)) deliver(delegate, session, task, (isCustomize(path) ? cached() : nil) ?: [NSData data]);
                finish(nil);
                return;
            }
            deliver(delegate, session, task, patched(url, buffer) ?: buffer);
            finish(nil);
            return;
        default:
            finish(error);
    }
}

%hook SPTDataLoaderService
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveResponse:(NSURLResponse *)response completionHandler:(void (^)(NSURLSessionResponseDisposition))handler {
    BOOL consumed = receiveAdResponse(task, handler, ^(NSHTTPURLResponse *empty, SGResponseHandler decision) { %orig(session, task, empty, decision); });
    if (consumed) return;
    NSHTTPURLResponse *replay = replayFor(task, response);
    %orig(session, task, replay ?: response, replay ? replayBody((id)self, session, task, objc_getAssociatedObject(task, &kServedKey), handler) : handler);
}
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveData:(NSData *)data {
    if (!holds(task, data)) %orig;
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    complete((id)self, session, task, error, ^(NSError *passed) { %orig(session, task, passed); });
}
%end

%hook _TtC26Connectivity_HttpClientKit20HttpClientURLSession
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveResponse:(NSURLResponse *)response completionHandler:(void (^)(NSURLSessionResponseDisposition))handler {
    BOOL consumed = receiveAdResponse(task, handler, ^(NSHTTPURLResponse *empty, SGResponseHandler decision) { %orig(session, task, empty, decision); });
    if (consumed) return;
    NSHTTPURLResponse *replay = replayFor(task, response);
    %orig(session, task, replay ?: response, replay ? replayBody((id)self, session, task, objc_getAssociatedObject(task, &kServedKey), handler) : handler);
}
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveData:(NSData *)data {
    if (!holds(task, data)) %orig;
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    complete((id)self, session, task, error, ^(NSError *passed) { %orig(session, task, passed); });
}
%end

// The C++ core's requests: most of Spotify's traffic, the access point lookup among it. Only its ad
// requests are touched. Each gets an empty 200 of the mod's own in place of the server's headers and
// body, including pre-send cancellation. Spoof Premium's rules stay off this path;
// non-ad failures keep their errors.
%hook SPTCoreURLSessionDataDelegate
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveResponse:(NSURLResponse *)response completionHandler:(void (^)(NSURLSessionResponseDisposition))handler {
    BOOL consumed = receiveAdResponse(task, handler, ^(NSHTTPURLResponse *empty, SGResponseHandler decision) { %orig(session, task, empty, decision); });
    if (consumed) return;
    %orig(session, task, response, handler);
}
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveData:(NSData *)data {
    if (!blockedAdTask(task) || objc_getAssociatedObject(task, &kPassKey)) %orig;
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    BOOL consumed = completeAd((id)self, session, task, ^(NSError *passed) { %orig(session, task, passed); });
    if (consumed) return;
    %orig;
}
%end

// This group owns only standalone nebula. Pixie's own hooks own both UCS envelopes.
%group OfflineDelegates
%hook SPTDataLoaderService
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveResponse:(NSURLResponse *)response completionHandler:(void (^)(NSURLSessionResponseDisposition))handler {
    NSURLResponse *forward = responseFor(task, response);
    %orig(session, task, forward, replayDecision((id)self, session, task, handler));
}
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveData:(NSData *)data {
    if (!holdsOffline((id)self, session, task, data)) %orig;
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    completeOffline((id)self, session, task, error);
    %orig;
}
%end
%hook _TtC26Connectivity_HttpClientKit20HttpClientURLSession
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveResponse:(NSURLResponse *)response completionHandler:(void (^)(NSURLSessionResponseDisposition))handler {
    NSURLResponse *forward = responseFor(task, response);
    %orig(session, task, forward, replayDecision((id)self, session, task, handler));
}
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveData:(NSData *)data {
    if (!holdsOffline((id)self, session, task, data)) %orig;
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    completeOffline((id)self, session, task, error);
    %orig;
}
%end
%hook SPTCoreURLSessionDataDelegate
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveResponse:(NSURLResponse *)response completionHandler:(void (^)(NSURLSessionResponseDisposition))handler {
    NSURLResponse *forward = responseFor(task, response);
    %orig(session, task, forward, replayDecision((id)self, session, task, handler));
}
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveData:(NSData *)data {
    if (!holdsOffline((id)self, session, task, data)) %orig;
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    completeOffline((id)self, session, task, error);
    %orig;
}
%end
%end

#pragma mark - before a request leaves

// Ad tasks are canceled immediately under Hide ads, including sessions the delegates do not see.
// Premium's re-fetches retain their startup window. login5 and the Google token stay:
// blocking those was a crash loop.
%group TaskRequests
%hook NSURLSessionTask
- (void)resume {
    NSURL *url = self.currentRequest.URL ?: self.originalRequest.URL;
    NSString *host = url.host.lowercaseString ?: @"", *path = url.path.lowercaseString ?: @"";
    BOOL spotify = has(host, @"spotify") || has(host, @"spclient");
    // EeveeSpotifyReincarnated 350aa15, with Hide ads independent of Spoof Premium.
    if ((ads && (taskKind(self, url) & kAd)) ||
        (premium && spotify && elapsed() > 30 &&
         (has(path, @"deletetoken") || has(path, @"signup/public") || has(path, @"pses/screenconfig")
          || isCustomize(path) || has(host, @"apresolve")))) {
        countRequest(self, YES);
        SGLog(@"canceled %@%@ before it left", host, path);
        [self cancel];
        return;
    }
    %orig;
}
%end
%end

// The config comes back 304 with no body when the app holds a copy of it and asks whether that is still
// current, and a copy taken while Spoof Premium was off is the server's own: the mod then has nothing to
// rewrite, and the account stays free until the server changes the config (device 2026-09-21). So the two
// go out without the question, and the server always answers in full; on 9.2 the attributes and remote
// config that replaced customize do too.
static NSURLRequest *unconditional(NSURLRequest *request) {
    NSString *host = request.URL.host.lowercaseString ?: @"", *path = request.URL.path.lowercaseString ?: @"";
    if (!(has(host, @"spotify") || has(host, @"spclient"))
        || !(isBootstrap(path) || isCustomize(path) || (premiumSplit && isSplitConfig(path)))) return nil;
    if (![request valueForHTTPHeaderField:@"If-None-Match"] && ![request valueForHTTPHeaderField:@"If-Modified-Since"]) return nil;
    NSMutableURLRequest *plain = [request mutableCopy];
    [plain setValue:nil forHTTPHeaderField:@"If-None-Match"];
    [plain setValue:nil forHTTPHeaderField:@"If-Modified-Since"];
    plain.cachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    SGLog(@"premium: %@ sent without its validators", path);
    return plain;
}

typedef void (^SGDataCompletion)(NSData *, NSURLResponse *, NSError *);
static NSURLRequest *offlineRequest(NSURLRequest *request) {
    if (!isOfflineConfig(request.URL) || !SGOfflineCompanionLoaded()) return request;
    NSMutableURLRequest *plain = [request mutableCopy];
    [plain setValue:nil forHTTPHeaderField:@"If-None-Match"];
    [plain setValue:nil forHTTPHeaderField:@"If-Modified-Since"];
    plain.cachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    return plain;
}

static NSNumber *taskGeneration(NSURLSession *session, NSURLRequest *request) {
    return isOfflineConfig(request.URL) && SGOfflineCompanionLoaded() ? @(offlineContext(session, request)) : nil;
}

static SGDataCompletion offlineCompletion(NSURLSession *session, NSURLRequest *request, SGDataCompletion handler) {
    if (!handler || !isOfflineConfig(request.URL) || !SGOfflineCompanionLoaded()) return handler;
    uint64_t generation = offlineContext(session, request);
    return ^(NSData *data, NSURLResponse *response, NSError *error) {
        NSURL *url = response.URL ?: request.URL;
        if (!error && isOfflineConfig(url) && [response isKindOfClass:NSHTTPURLResponse.class] && data.length <= offlineBodyLimitBytes) {
            if (((NSHTTPURLResponse *)response).statusCode == 304 && ![request valueForHTTPHeaderField:@"Range"]
                && ![(NSHTTPURLResponse *)response valueForHTTPHeaderField:@"Content-Range"]) {
                NSData *replay = cachedOffline(url, generation);
                if (replay) {
                    handler(replay, rewrittenResponse((NSHTTPURLResponse *)response, 200), nil);
                    return;
                }
            } else if (data.length && fullResponse((NSHTTPURLResponse *)response, request)) {
                BOOL recognized = NO;
                NSData *result = offlineAttributes(data, &recognized);
                if (recognized) storeOffline(url, generation, data);
                if (result && ![result isEqual:data]) response = rewrittenResponse((NSHTTPURLResponse *)response, 200);
                data = result ?: data;
            }
        }
        handler(data, response, error);
    };
}

%group PremiumRequests
%hook NSURLSession
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request {
    return %orig(unconditional(request) ?: request);
}
%end
%end

%group OfflineCompletionRequests
%hook NSURLSession
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request {
    observeAccountRequest(request);
    NSNumber *generation = taskGeneration(self, request);
    NSURLSessionDataTask *task = %orig(offlineRequest(request));
    if (generation)
        objc_setAssociatedObject(task, &kGenerationKey, generation, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return task;
}
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))handler {
    observeAccountRequest(request);
    return %orig(offlineRequest(request), offlineCompletion(self, request, handler));
}
- (void)invalidateAndCancel {
    clearOfflineSession(self);
    %orig;
}
- (void)finishTasksAndInvalidate {
    clearOfflineSession(self);
    %orig;
}
%end
%end

// The sessions Spotify makes are __NSURLSessionLocal; hooked as well only when that class answers
// dataTaskWithRequest: itself, since a hook on an inherited method would sit on NSURLSession's twice.
%group PremiumLocalRequests
%hook __NSURLSessionLocal
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request {
    return %orig(unconditional(request) ?: request);
}
%end
%end

%group OfflineLocalRequests
%hook __NSURLSessionLocal
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request {
    observeAccountRequest(request);
    NSNumber *generation = taskGeneration((id)self, request);
    NSURLSessionDataTask *task = %orig(offlineRequest(request));
    if (generation)
        objc_setAssociatedObject(task, &kGenerationKey, generation, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return task;
}
%end
%end

%group OfflineLocalCompletionRequests
%hook __NSURLSessionLocal
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))handler {
    observeAccountRequest(request);
    return %orig(offlineRequest(request), offlineCompletion((id)self, request, handler));
}
%end
%end

static void installDelegates(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        %init;
        SGRequireClasses(@[@"SPTDataLoaderService", @"_TtC26Connectivity_HttpClientKit20HttpClientURLSession",
                           @"SPTCoreURLSessionDataDelegate"]);
    });
}

static void installRequestFactories(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        %init(PremiumRequests);
        SEL selector = @selector(dataTaskWithRequest:);
        Class local = objc_getClass("__NSURLSessionLocal");
        Method own = local ? class_getInstanceMethod(local, selector) : NULL;
        if (own && own != class_getInstanceMethod(NSURLSession.class, selector)) %init(PremiumLocalRequests);
    });
}

static BOOL installOfflineHooks(void) {
    if (!SGOfflineCompanionLoaded()) return NO;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        // The store is initialized under cacheLock before any delegate hook is published.
        @synchronized (cacheLock) {
            if (!offlineInputs) offlineInputs = [NSMutableDictionary new];
        }
        %init(OfflineCompletionRequests);
        Class local = objc_getClass("__NSURLSessionLocal");
        SEL selector = @selector(dataTaskWithRequest:);
        Method plain = local ? class_getInstanceMethod(local, selector) : NULL;
        if (plain && plain != class_getInstanceMethod(NSURLSession.class, selector)) %init(OfflineLocalRequests);
        selector = @selector(dataTaskWithRequest:completionHandler:);
        Method own = local ? class_getInstanceMethod(local, selector) : NULL;
        if (own && own != class_getInstanceMethod(NSURLSession.class, selector)) %init(OfflineLocalCompletionRequests);
        %init(OfflineDelegates);
    });
    return YES;
}

static void offlineImageAdded(const struct mach_header *image, intptr_t slide) {
    if (image->magic != MH_MAGIC_64) return;
    const struct load_command *command = (const void *)((const struct mach_header_64 *)image + 1);
    for (uint32_t i = 0; i < image->ncmds; i++, command = (const void *)((const char *)command + command->cmdsize)) {
        if (command->cmd != LC_ID_DYLIB) continue;
        const struct dylib_command *dylib = (const void *)command;
        const char *path = (const char *)command + dylib->dylib.name.offset;
        const char *name = strrchr(path, '/');
        if (!strcmp(name ? name + 1 : path, SGOfflineCompanionImageName)) {
            // Loader APIs and Objective-C hook installation must run outside dyld's callback lock.
            dispatch_async(offlineInstallQueue, ^{ installOfflineHooks(); });
        }
    }
}

%ctor {
    ads = SGHidden(SGKeyHideAds);
    premium = SGHidden(SGKeyFakePremium);
    NSString *version = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    premiumSplit = premium && version && [version compare:@"9.2" options:NSNumericSearch] != NSOrderedAscending;
    started = NSDate.date;
    cacheLock = [NSObject new];
    if (ads || premium) {
        installDelegates();
        %init(TaskRequests);
        if (premium) installRequestFactories();
    }
    // A verified provider is pinned. Only a miss needs replay and future add-image notifications.
    if (!installOfflineHooks()) {
        offlineInstallQueue = dispatch_queue_create("com.retrine.offline-loader", DISPATCH_QUEUE_SERIAL);
        [NSNotificationCenter.defaultCenter addObserverForName:@"SAPOfflineProfileReady" object:nil queue:nil usingBlock:^(NSNotification *note){
            dispatch_async(offlineInstallQueue, ^{ installOfflineHooks(); });
        }];
        _dyld_register_func_for_add_image(offlineImageAdded);
    }
}
