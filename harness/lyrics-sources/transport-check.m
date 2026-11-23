// Real JSON transport and NetEase provider; only NSURLSession and the external keeper are doubles.
#import "Core/SGCore.h"
#import "Shared/LyricsSources/LyricsSources.h"
#import "Shared/LyricsSources/LyricsHosts.h"
#import <stdatomic.h>
#import <objc/runtime.h>
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAILED line %d: %s\n", __LINE__, #c); exit(1); } } while (0)
static NSData *(^reply)(NSURLRequest *);
static NSInteger replyStatus = 200;
static NSError *replyError;
static _Atomic NSUInteger decoded;
static IMP originalJSON, originalLineStart, originalXML, originalMatches;
static BOOL watchModels;
static void checkedLineStart(id line, SEL selector, NSInteger start) {
    if (watchModels) CHECK(!NSThread.isMainThread);
    ((void (*)(id, SEL, NSInteger))originalLineStart)(line, selector, start);
}
static BOOL checkedXML(id object, SEL selector) {
    CHECK(!NSThread.isMainThread);
    return ((BOOL (*)(id, SEL))originalXML)(object, selector);
}
static id checkedMatches(NSRegularExpression *regex, SEL selector, NSString *text, NSMatchingOptions options, NSRange range) {
    if ([regex.pattern hasPrefix:@"<tr"]) CHECK(!NSThread.isMainThread);
    return ((id (*)(id, SEL, NSString *, NSMatchingOptions, NSRange))originalMatches)(regex, selector, text, options, range);
}

static NSMutableArray *heldTokenTasks;
static BOOL holdMacro;
@interface TransportTask : NSObject
@property (nonatomic, copy) dispatch_block_t work;
@property (nonatomic) BOOL cancelled, hold;
- (void)resume;
- (void)cancel;
@end
@implementation TransportTask
- (void)resume {
    if (self.hold) [heldTokenTasks addObject:self];
    else dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), self.work);
}
- (void)cancel { self.cancelled = YES; }
@end
@interface TransportSession : NSObject
@property (nonatomic, strong) id<NSURLSessionDataDelegate> delegate;
@property (nonatomic, strong) NSOperationQueue *queue;
+ (instancetype)sharedSession;
+ (instancetype)sessionWithConfiguration:(NSURLSessionConfiguration *)configuration delegate:(id)delegate delegateQueue:(NSOperationQueue *)queue;
- (TransportTask *)dataTaskWithRequest:(NSURLRequest *)request;
- (void)finishTasksAndInvalidate;
- (TransportTask *)dataTaskWithRequest:(NSURLRequest *)request
                    completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))done;
@end
@implementation TransportSession
+ (instancetype)sharedSession { return [self new]; }
+ (instancetype)sessionWithConfiguration:(NSURLSessionConfiguration *)configuration delegate:(id)delegate delegateQueue:(NSOperationQueue *)queue {
    CHECK(configuration.HTTPCookieStorage == nil && configuration.URLCache == nil);
    TransportSession *session = [self new];
    session.delegate = delegate;
    session.queue = queue ?: [NSOperationQueue new];
    session.queue.maxConcurrentOperationCount = 1;
    return session;
}
- (void)finishTasksAndInvalidate { self.delegate = nil; }
- (TransportTask *)dataTaskWithRequest:(NSURLRequest *)request {
    if (SGLyricsProviderURLAllowed(request.URL)) CHECK(SGLyricsRequestIsMarked(request));
    TransportTask *task = [TransportTask new];
    __weak TransportTask *weakTask = task;
    task.work = ^{
        TransportTask *activeTask = weakTask;
        NSData *data = reply(request);
        NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:request.URL statusCode:replyStatus HTTPVersion:@"HTTP/1.1" headerFields:nil];
        [self.queue addOperationWithBlock:^{
            CHECK(!NSThread.isMainThread);
            [self.delegate URLSession:(id)self dataTask:(id)activeTask didReceiveResponse:response completionHandler:^(NSURLSessionResponseDisposition disposition) {
                CHECK(disposition == NSURLSessionResponseAllow);
                if (data) [self.delegate URLSession:(id)self dataTask:(id)activeTask didReceiveData:data];
                [self.delegate URLSession:(id)self task:(id)activeTask didCompleteWithError:replyError];
            }];
        }];
    };
    return task;
}
- (TransportTask *)dataTaskWithRequest:(NSURLRequest *)request
                    completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))done {
    if (SGLyricsProviderURLAllowed(request.URL)) CHECK(SGLyricsRequestIsMarked(request));
    TransportTask *task = [TransportTask new];
    task.hold = heldTokenTasks && [request.URL.path hasSuffix:holdMacro ? @"macro.subtitles.get" : @"token.get"];
    task.work = ^{
        NSData *body = reply(request);
        done(body, [[NSHTTPURLResponse alloc] initWithURL:request.URL statusCode:replyStatus HTTPVersion:@"HTTP/1.1"
            headerFields:@{@"Retry-After": @"7"}], replyError);
    };
    return task;
}
@end
@interface TransportJSON : NSObject
+ (id)JSONObjectWithData:(NSData *)data options:(NSJSONReadingOptions)options error:(NSError **)error;
+ (BOOL)isValidJSONObject:(id)value;
+ (NSData *)dataWithJSONObject:(id)value options:(NSJSONWritingOptions)options error:(NSError **)error;
@end
@implementation TransportJSON
+ (id)JSONObjectWithData:(NSData *)data options:(NSJSONReadingOptions)options error:(NSError **)error {
    CHECK(!NSThread.isMainThread);
    atomic_fetch_add(&decoded, 1);
    return ((id (*)(id, SEL, NSData *, NSJSONReadingOptions, NSError **))originalJSON)(NSJSONSerialization.class, _cmd, data, options, error);
}
+ (BOOL)isValidJSONObject:(id)value { return [NSJSONSerialization isValidJSONObject:value]; }
+ (NSData *)dataWithJSONObject:(id)value options:(NSJSONWritingOptions)options error:(NSError **)error {
    return [NSJSONSerialization dataWithJSONObject:value options:options error:error];
}
@end
static const NSTimeInterval kTimeout = SGLyricsRequestTimeoutSeconds;
static NSUserDefaults *probeDefaults;
static NSString *probeSuite;
static void clearProbeDefaults(void) { [probeDefaults removePersistentDomainForName:probeSuite]; }
@interface ProbeDefaults : NSObject
+ (NSUserDefaults *)standardUserDefaults;
@end
@implementation ProbeDefaults
+ (NSUserDefaults *)standardUserDefaults { return probeDefaults; }
@end
#define NSURLSession TransportSession
#import "transport.inc"
// NetEase has its own 3-second request policy.
#define kTimeout kNetEaseTimeout
#import "Shared/LyricsSources/NetEase.m"
#undef kTimeout
#define kTimeout kMusixmatchTimeout
#define kBreakMs kMusixmatchBreakMs
#define requestFor musixmatchRequestFor
#define NSUserDefaults ProbeDefaults
#import "Shared/LyricsSources/Musixmatch.m"
#undef NSUserDefaults
#undef requestFor
#undef kBreakMs
#undef kTimeout
#undef NSURLSession
BOOL SGLocalFileIs(NSString *uri) { return NO; }
NSDictionary *SGLocalFileInfo(NSString *uri) { return nil; }
@implementation SGLyricsResult
@end
@implementation SGLyricsQuery
@end
void SGLyricsPageLines(NSArray *lines, NSArray **starts, NSArray **texts) {
    NSMutableArray *at = [NSMutableArray array], *words = [NSMutableArray array];
    for (SGKaraokeLine *line in lines) { [at addObject:@(line.start)]; [words addObject:SGKaraokeLineText(line)]; }
    *starts = at; *texts = words;
}
static NSString *fixtureISRC;
static BOOL holdISRC, cancelledISRC;
void SGSpotifyISRC(NSString *uri, NSUInteger tries, void (^done)(NSString *)) { done(fixtureISRC); }
dispatch_block_t SGSpotifyISRCWithOutcome(NSString *uri, NSUInteger tries, void (^done)(NSString *, BOOL)) {
    if (!holdISRC) done(fixtureISRC, NO);
    return ^{ cancelledISRC = YES; };
}
NSString *SGLyricsTranslationLanguage(void) { return nil; }
static void waitFor(BOOL *finished) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5];
    while (!*finished && deadline.timeIntervalSinceNow > 0)
        [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
    CHECK(*finished);
}
static NSData *json(id value) { return [NSJSONSerialization dataWithJSONObject:value options:0 error:nil]; }
static void checkUpstream404(void) {
    for (NSString *upstream in @[@"RTO", @"BAD", @"NOT_FOUND"]) {
        replyStatus = 404;
        reply = ^NSData *(NSURLRequest *request) {
            return json(@{@"error": @{@"status": @404, @"message": @"Lyrics not found in sources: qapple, qq, deezer"},
                          @"processingTime": @{@"sourcesStatus": @{@"qq": @{@"status": upstream}}}});
        };
        SGLyricsQuery *query = [SGLyricsQuery new];
        query.title = @"Fixture"; query.artist = @"Singer"; query.seconds = 200;
        query.requestContext = [SGLyricsRequestContext new];
        __block BOOL finished = NO;
        SGLyricsPlusAsk(query, ^(SGLyricsResult *result) { CHECK(!result); finished = YES; });
        waitFor(&finished);
        CHECK(query.requestContext.failed == ![upstream isEqual:@"NOT_FOUND"]);
        CHECK((query.requestContext.emptyNameSearch != nil) == [upstream isEqual:@"NOT_FOUND"]);
    }
    replyStatus = 200;
    puts("LyricsPlus probe: upstream RTO/BAD in 404 is failure; healthy 404 stays searchable");
}

static SGLyricsResult *probeAnswer(SGLyricsAsk ask, SGLyricsRequestContext *context) {
    SGLyricsQuery *query = [SGLyricsQuery new];
    query.trackID = NSUUID.UUID.UUIDString;
    query.title = @"Fixture"; query.artist = @"Singer"; query.seconds = 200;
    query.requestContext = context;
    __block BOOL finished = NO;
    __block SGLyricsResult *answer;
    ask(query, ^(SGLyricsResult *result) { answer = result; finished = YES; });
    waitFor(&finished);
    return answer;
}

static void checkTokenCancellation(void) {
    holdISRC = YES; cancelledISRC = NO;
    SGLyricsQuery *bini = [SGLyricsQuery new];
    bini.trackID = @"0000000000000000000001";
    bini.requestContext = [SGLyricsRequestContext new];
    SGBiniLyricsAsk(bini, ^(SGLyricsResult *result) { CHECK(NO); });
    [bini.requestContext cancelRequests];
    CHECK(cancelledISRC);
    holdISRC = NO;
    [probeDefaults removeObjectForKey:@"spotifyglass.musixmatch.token"];
    heldTokenTasks = [NSMutableArray array];
    NSMutableArray<SGLyricsQuery *> *queries = [NSMutableArray array];
    for (NSUInteger i = 0; i < 2; i++) {
        SGLyricsQuery *query = [SGLyricsQuery new];
        query.trackID = NSUUID.UUID.UUIDString;
        query.requestContext = [SGLyricsRequestContext new];
        [queries addObject:query];
        SGMusixmatchAsk(query, ^(SGLyricsResult *result) { CHECK(!result); });
    }
    TransportTask *task = heldTokenTasks.firstObject;
    CHECK(task);
    [queries[0].requestContext cancelRequests];
    CHECK(!task.cancelled);
    [queries[1].requestContext cancelRequests];
    CHECK(task.cancelled);
    heldTokenTasks = nil;
    puts("shared token: cancelling one subscriber preserves the other; last subscriber cancels transport");
}

static void checkProbeShapes(void) {
    // Reduced, redacted response shapes from design/lyrics-proton; lyric text is synthetic.
    for (NSNumber *status in @[@403, @500, @502]) {
        replyStatus = status.integerValue;
        reply = ^NSData *(NSURLRequest *request) {
            if ([status isEqual:@500]) return json(@{@"status": @500, @"error": @"Internal Server Error",
                @"exception": @"java.lang.NullPointerException", @"message": @"No message available", @"path": @"/api/getSearchList"});
            if ([status isEqual:@502]) return [@"error code: 502" dataUsingEncoding:NSUTF8StringEncoding];
            return [@"<!DOCTYPE html><html><title>Just a moment...</title><body>Enable JavaScript and cookies to continue</body></html>"
                dataUsingEncoding:NSUTF8StringEncoding];
        };
        SGLyricsRequestContext *context = [SGLyricsRequestContext new];
        CHECK(!probeAnswer(SGGeniusAsk, context) && context.failed && !context.emptyNameSearch);
    }
    replyStatus = 200;
    for (NSNumber *code in @[@(NSURLErrorNetworkConnectionLost), @(NSURLErrorTimedOut)]) {
        replyError = [NSError errorWithDomain:NSURLErrorDomain code:code.integerValue userInfo:nil];
        reply = ^NSData *(NSURLRequest *request) { return nil; };
        SGLyricsRequestContext *context = [SGLyricsRequestContext new];
        __block BOOL finished = NO;
        SGLyricsGetJSONIn(context, [NSURL URLWithString:@"https://pipe.deezer.com/api"], nil,
            ^(id root) { CHECK(!root && context.failed); finished = YES; });
        waitFor(&finished);
    }
    replyError = nil;
    reply = ^NSData *(NSURLRequest *request) {
        return json(@{@"code": @0, @"req": @{@"code": @2001, @"data": @{@"body": @{@"song": @{@"list": @[]}}}}});
    };
    SGLyricsRequestContext *context = [SGLyricsRequestContext new];
    CHECK(!probeAnswer(SGQQMusicAsk, context) && context.failed);
    replyStatus = 404;
    reply = ^NSData *(NSURLRequest *request) {
        return json(@{@"success": @NO, @"error": @"Lyrics not found", @"code": @"NOT_FOUND"});
    };
    context = [SGLyricsRequestContext new];
    CHECK(!probeAnswer(SGUnisonAsk, context) && !context.failed);
    replyStatus = 200;
    reply = ^NSData *(NSURLRequest *request) {
        if ([request.URL.host isEqual:@"www.genie.co.kr"])
            return [@"<tr class='list' songid='7'><a class='title' title='Fixture'>Fixture</a><a class='artist'>Singer</a></tr>"
                dataUsingEncoding:NSUTF8StringEncoding];
        return [@"NOT FOUND LYRICS" dataUsingEncoding:NSUTF8StringEncoding];
    };
    context = [SGLyricsRequestContext new];
    CHECK(!probeAnswer(SGGenieAsk, context) && !context.failed);
    reply = ^NSData *(NSURLRequest *request) {
        if ([request.URL.path containsString:@"search"]) return json(@{@"code": @200, @"result": @{@"songs": @[
            @{@"id": @4, @"name": @"Fixture", @"duration": @200000, @"artists": @[@{@"name": @"Singer"}]}]}});
        return json(@{@"code": @200, @"lrc": @{@"lyric": @"[00:01]Only line timing"}});
    };
    context = [SGLyricsRequestContext new];
    CHECK(!probeAnswer(SGNetEaseAsk, context) && !context.failed);
    fixtureISRC = @"FIXTUREISRC";
    reply = ^NSData *(NSURLRequest *request) {
        if ([request.URL.path isEqual:@"/s/FIXTUREISRC.ttml"]) { replyStatus = 404; return nil; }
        replyStatus = 200;
        if ([request.URL.host isEqual:@"lyrics-api.binimum.org"]) return json(@{@"results": @[
            @{@"lyricsUrl": @"https://lrc.red/s/name-fallback.ttml", @"timing_type": @"word", @"duration": @200}]});
        return [@"<tt timing=\"Word\"><body><div><p begin=\"1s\" end=\"2s\"><span begin=\"1s\" end=\"2s\">Name fallback</span></p></div></body></tt>"
            dataUsingEncoding:NSUTF8StringEncoding];
    };
    context = [SGLyricsRequestContext new];
    SGLyricsResult *named = probeAnswer(^(SGLyricsQuery *query, void (^done)(SGLyricsResult *)) {
        query.trackID = @"1234567890123456789012";
        SGBiniLyricsAsk(query, done);
    }, context);
    CHECK(!context.failed && [SGKaraokeLineText(named.karaokeLines.firstObject) isEqual:@"Name fallback"]);
    fixtureISRC = nil;
    for (NSNumber *matcherCode in @[@400, @200]) {
        reply = ^NSData *(NSURLRequest *request) {
            if ([request.URL.path hasSuffix:@"token.get"])
                return json(@{@"message": @{@"header": @{@"status_code": @200}, @"body": @{@"user_token": @"fixture-token"}}});
            id calls = @{
                @"matcher.track.get": @{@"message": @{@"header": @{@"status_code": matcherCode}, @"body": @""}},
                @"track.richsync.get": @{@"message": @{@"header": @{@"status_code": @404}, @"body": @""}},
                @"track.subtitles.get": @{@"message": @{@"header": @{@"status_code": matcherCode},
                    @"body": [matcherCode isEqual:@400] ? @"" : @{@"subtitle_list": @[@{@"subtitle": @{@"subtitle_body":
                        @"[{\"text\":\"Available subtitles\",\"time\":{\"total\":1}},{\"text\":\"\",\"time\":{\"total\":2}}]"}}]}}}
            };
            return json(@{@"message": @{@"header": @{@"status_code": @200}, @"body": @{@"macro_calls": calls}}});
        };
        context = [SGLyricsRequestContext new];
        SGLyricsResult *answer = probeAnswer(SGMusixmatchAsk, context);
        CHECK(context.failed == [matcherCode isEqual:@400]);
        if ([matcherCode isEqual:@400]) CHECK(!answer);
        if ([matcherCode isEqual:@200]) CHECK([SGKaraokeLineText(answer.karaokeLines.firstObject) isEqual:@"Available subtitles"]);
    }
    puts("probe shapes: challenges, upstream errors, resets/timeouts, QQ 2001, healthy misses and missing timing capability passed");
}
static void checkSameTrackCancellation(void) {
    for (NSNumber *macro in @[@NO, @YES]) for (NSUInteger cancelledIndex = 0; cancelledIndex < 2; cancelledIndex++) {
        holdMacro = macro.boolValue;
        heldTokenTasks = [NSMutableArray array];
        if (holdMacro) [probeDefaults setObject:@"fixture-token" forKey:@"spotifyglass.musixmatch.token"];
        else [probeDefaults removeObjectForKey:@"spotifyglass.musixmatch.token"];
        replyStatus = 200;
        reply = ^NSData *(NSURLRequest *request) {
            if ([request.URL.path hasSuffix:@"token.get"])
                return json(@{@"message": @{@"header": @{@"status_code": @200}, @"body": @{@"user_token": @"fixture-token"}}});
            return json(@{@"message": @{@"header": @{@"status_code": @200}, @"body": @{@"macro_calls": @{
                @"track.lyrics.get": @{@"message": @{@"header": @{@"status_code": @200},
                    @"body": @{@"lyrics": @{@"lyrics_body": @"Surviving subscriber"}}}}
            }}}});
        };
        NSString *track = NSUUID.UUID.UUIDString;
        NSMutableArray *contexts = [NSMutableArray array];
        __block BOOL received = NO;
        for (NSUInteger index = 0; index < 2; index++) {
            SGLyricsQuery *query = [SGLyricsQuery new];
            query.trackID = track;
            query.requestContext = [SGLyricsRequestContext new];
            [contexts addObject:query.requestContext];
            SGMusixmatchAsk(query, ^(SGLyricsResult *result) {
                CHECK(index != cancelledIndex);
                CHECK([SGKaraokeLineText(result.karaokeLines.firstObject) isEqual:@"Surviving subscriber"]);
                CHECK(!query.requestContext.failed);
                received = YES;
            });
        }
        TransportTask *task = heldTokenTasks.firstObject;
        CHECK(task != nil);
        [contexts[cancelledIndex] cancelRequests];
        CHECK(!task.cancelled);
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), task.work);
        waitFor(&received);
        heldTokenTasks = nil;
    }
    holdMacro = NO;
    puts("same-track subscribers: either subscriber detaches during token or macro without cancelling the survivor");
}
int main(void) {
    @autoreleasepool {
        NSString *suite = [@"retrine.lyrics.probe." stringByAppendingString:NSUUID.UUID.UUIDString];
        probeSuite = suite;
        probeDefaults = [[NSUserDefaults alloc] initWithSuiteName:suite];
        atexit(clearProbeDefaults);
        checkTokenCancellation();
        checkSameTrackCancellation();
        // Classification covers legacy adapters too; worker-thread checks below belong to shared transforms.
        checkUpstream404();
        checkProbeShapes();
        atomic_store(&sg_failures, 0);
        Method jsonMethod = class_getClassMethod(NSJSONSerialization.class, @selector(JSONObjectWithData:options:error:));
        originalJSON = method_setImplementation(jsonMethod, class_getMethodImplementation(object_getClass(TransportJSON.class), @selector(JSONObjectWithData:options:error:)));
        originalLineStart = method_setImplementation(class_getInstanceMethod(SGKaraokeLine.class, @selector(setStart:)), (IMP)checkedLineStart);
        originalXML = method_setImplementation(class_getInstanceMethod(NSXMLParser.class, @selector(parse)), (IMP)checkedXML);
        originalMatches = method_setImplementation(class_getInstanceMethod(NSRegularExpression.class, @selector(matchesInString:options:range:)), (IMP)checkedMatches);
        NSURL *url = [NSURL URLWithString:@"https://fixture.invalid/lyrics"];
        NSString *large = [@"a" stringByPaddingToLength:500000 withString:@"a" startingAtIndex:0];
        reply = ^NSData *(NSURLRequest *request) { return json(@{@"text": large, @"candidate": @17}); };
        __block BOOL finished = NO;
        SGLyricsGetJSONTransform(url, nil, ^id(id root) {
            CHECK(!NSThread.isMainThread);
            CHECK([root[@"text"] length] == 500000);
            return root[@"candidate"];
        }, ^(id value) { CHECK(NSThread.isMainThread && [value isEqual:@17]); finished = YES; });
        waitFor(&finished);
        CHECK(atomic_load(&decoded) == 1);
        finished = NO;
        SGLyricsPostJSON(url, nil, @{@"ask": @YES}, ^(id root) {
            CHECK(NSThread.isMainThread && [root[@"candidate"] isEqual:@17]); finished = YES;
        });
        waitFor(&finished);
        replyStatus = 429;
        finished = NO;
        SGLyricsGetJSONReply(url, nil, ^(id root, NSHTTPURLResponse *response) {
            CHECK(NSThread.isMainThread && response.statusCode == 429);
            CHECK([response.allHeaderFields[@"Retry-After"] isEqual:@"7"] && [root[@"candidate"] isEqual:@17]);
            finished = YES;
        });
        waitFor(&finished);
        CHECK(atomic_load(&sg_failures) == 1);
        // A provider's refusal is not evidence that the recording has no lyrics.
        replyStatus = 403;
        SGLyricsRequestContext *blocked = [SGLyricsRequestContext new];
        finished = NO;
        SGLyricsGetJSONIn(blocked, url, nil, ^(id root) {
            CHECK(!root && blocked.failed);
            finished = YES;
        });
        waitFor(&finished);
        replyStatus = 200;
        reply = ^NSData *(NSURLRequest *request) { return [@"{broken" dataUsingEncoding:NSUTF8StringEncoding]; };
        SGLyricsRequestContext *malformed = [SGLyricsRequestContext new];
        finished = NO;
        SGLyricsGetJSONIn(malformed, url, nil, ^(id root) {
            CHECK(!root && malformed.failed);
            finished = YES;
        });
        waitFor(&finished);
        finished = NO;
        SGLyricsGetJSON(url, nil, ^(id root) { CHECK(NSThread.isMainThread && !root); finished = YES; });
        waitFor(&finished);
        finished = NO;
        SGLyricsPostJSON(url, nil, [NSObject new], ^(id root) { CHECK(NSThread.isMainThread && !root); finished = YES; });
        waitFor(&finished);
        finished = NO;
        SGLyricsGetText(url, ^(NSString *text) { CHECK(NSThread.isMainThread && [text isEqual:@"{broken"]); finished = YES; });
        waitFor(&finished);
        reply = ^NSData *(NSURLRequest *request) {
            CHECK(request.timeoutInterval == 3);
            if ([request.URL.path isEqual:@"/api/search/get"]) return json(@{@"result": @{@"songs": @[
                @{@"id": @1, @"name": @"Different", @"duration": @200000, @"artists": @[@{@"name": @"Singer"}]},
                @{@"id": @2, @"name": @"Fixture (Live)", @"duration": @200000, @"artists": @[@{@"name": @"Singer"}]},
                @{@"id": @3, @"name": @42, @"duration": @200000, @"artists": @[@{@"name": @"Singer"}]},
                @{@"id": @4, @"name": @" Fixture! ", @"duration": @200000, @"artists": @[@{@"name": @"Singer"}]}
            ]}});
            CHECK([request.URL.query containsString:@"id=4"]);
            return json(@{@"yrc": @{@"lyric": @"[1234,1000](1234,200,0)Hello"}});
        };
        SGLyricsQuery *query = [SGLyricsQuery new];
        query.title = @"Fixture"; query.artist = @"Singer"; query.seconds = 200;
        finished = NO;
        SGNetEaseAsk(query, ^(SGLyricsResult *result) {
            CHECK(NSThread.isMainThread && result.wordTimed);
            CHECK(result.karaokeLines[0].words[0].start == 1234 && result.karaokeLines[0].words[0].end == 1434);
            finished = YES;
        });
        waitFor(&finished);
        watchModels = YES;
        // Each real adapter sees the same captured query even if the source walk learns new names.
        for (NSUInteger provider = 0; provider < 6; provider++) {
            query.title = @"Fixture"; query.artist = @"Singer"; query.seconds = 200;
            query.trackID = provider == 5 ? @"1234567890123456789012" : @"fixture";
            fixtureISRC = provider == 5 ? @"ISRC123" : nil;
            reply = ^NSData *(NSURLRequest *request) {
                NSString *host = request.URL.host, *path = request.URL.path;
                if ([host isEqual:@"lrclib.net"]) {
                    NSDictionary *record = @{@"id": @7, @"trackName": @"Fixture", @"artistName": @"Singer", @"duration": @200, @"syncedLyrics": @"[00:01]Hello\n[00:02]"};
                    return json(provider == 1 ? @[record] : record);
                }
                if ([host hasPrefix:@"lyricsplus."]) return json(@{@"type": @"Word", @"lyrics": @[
                    @{@"text": @"Hello", @"time": @1000, @"duration": @1000, @"syllabus": @[
                        @{@"text": @"Hello", @"time": @1000, @"duration": @1000}]}]});
                if ([host isEqual:@"www.genie.co.kr"]) return [@"<tr class='list' songid='7'><a class='title' title='Fixture'>Fixture</a><a class='artist'>Singer</a></tr>" dataUsingEncoding:NSUTF8StringEncoding];
                if ([host isEqual:@"dn.genie.co.kr"]) return [@"callback({\"1000\":\"Hello\",\"2000\":\"\"})" dataUsingEncoding:NSUTF8StringEncoding];
                if ([host isEqual:@"lyrics-api.binimum.org"]) return json(@{@"results": @[
                    @{@"lyricsUrl": @"https://lrc.red/s/unknown.ttml", @"timing_type": @"word", @"duration": NSNull.null},
                    @{@"lyricsUrl": @"https://lrc.red/s/lyrics.ttml", @"timing_type": @"word", @"duration": @202}]});
                CHECK([path hasSuffix:@".ttml"]);
                if ([path isEqual:@"/unknown.ttml"])
                    return [@"<tt timing=\"Word\"><body><div><p begin=\"1s\" end=\"2s\"><span begin=\"1s\" end=\"2s\">Unknown</span></p></div></body></tt>" dataUsingEncoding:NSUTF8StringEncoding];
                return [@"<tt timing=\"Word\"><body><div><p begin=\"1s\" end=\"2s\"><span begin=\"1s\" end=\"2s\">Hello</span></p></div></body></tt>" dataUsingEncoding:NSUTF8StringEncoding];
            };
            finished = NO;
            void (^receive)(SGLyricsResult *) = ^(SGLyricsResult *result) {
                CHECK(NSThread.isMainThread && result.karaokeLines.count == 1);
                CHECK(result.karaokeLines.firstObject.start == 1000);
                CHECK([SGKaraokeLineText(result.karaokeLines.firstObject) isEqual:@"Hello"]);
                if (provider == 2 || provider >= 4) CHECK(result.wordTimed);
                finished = YES;
            };
            if (provider == 0) SGLrcLibAsk(query, receive);
            else if (provider == 1) {
                query.seconds = 0;
                SGLrcLibAsk(query, receive);
            } else if (provider == 2) SGLyricsPlusAsk(query, receive);
            else if (provider == 3) SGGenieAsk(query, receive);
            else SGBiniLyricsAsk(query, receive);
            query.title = @"Changed"; query.artist = @"Other"; query.seconds = 900;
            waitFor(&finished);
        }
        [probeDefaults removePersistentDomainForName:suite];
        puts("Shared transport: worker decoding/models, main delivery, LRCLIB/LyricsPlus/Genie/BiniLyrics and NetEase passed");
    }
    return 0;
}
