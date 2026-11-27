// Included by check.m; scripted service replies, then production one-shot transport via NSURLProtocol.
#import "Shared/LyricsTranslation/ConnectionTest.h"
#import <objc/runtime.h>
NSURLSessionDataTask *SGLyricsTranslationRealSendOnce(NSURLRequest *, void (^)(NSData *, NSInteger, NSError *));
@interface SGConnectionFakeTask : NSObject
@property BOOL cancelled;
@end
@implementation SGConnectionFakeTask
- (void)cancel { self.cancelled = YES; }
@end
static NSUInteger connectionSends, connectionModelSends;
static NSURLRequest *connectionRequest, *connectionModelRequest;
static SGConnectionFakeTask *connectionTask, *connectionModelTask;
static void (^connectionReply)(NSData *, NSInteger, NSError *);
static void (^connectionModelReply)(NSData *, NSInteger, NSError *);
NSURLSessionDataTask *SGLyricsTranslationSendOnce(NSURLRequest *request, void (^done)(NSData *, NSInteger, NSError *)) {
    connectionSends++; connectionRequest = request; connectionReply = [done copy];
    connectionTask = [SGConnectionFakeTask new];
    return (id)connectionTask;
}
static NSData *connectionData(NSString *text) {
    return [NSJSONSerialization dataWithJSONObject:chatReply([@"L0001\t" stringByAppendingString:text]) options:0 error:nil];
}
static NSData *connectionModels(NSArray *ids) {
    NSMutableArray *data = [NSMutableArray array];
    for (NSString *identifier in ids) [data addObject:@{@"id": identifier}];
    return [NSJSONSerialization dataWithJSONObject:@{@"data": data} options:0 error:nil];
}
static void connectionDrain(void) {
    __block BOOL drained = NO;
    dispatch_async(dispatch_get_main_queue(), ^{ drained = YES; });
    waitFor(^BOOL { return drained; });
}
static void connectionConfigure(void) {
    [NSUserDefaults.standardUserDefaults setObject:@"http://100.97.8.81:10100/v1" forKey:SGKeyLyricsOpenAIBaseURL];
    [NSUserDefaults.standardUserDefaults setObject:@"offline-model" forKey:SGKeyLyricsOpenAIModel];
    testKeys = [NSSet setWithObject:@"Vitrine.OpenAI"];
    openAIKeys = [@{@"http://100.97.8.81:10100": [@"connection-fixture-key" dataUsingEncoding:NSUTF8StringEncoding],
                    @"other.invalid": [@"other-fixture-key" dataUsingEncoding:NSUTF8StringEncoding]} mutableCopy];
    keyReadFailure = keyWriteFailure = keyDeleteFailure = 0;
    testLanguage = @"ko";
}
// A copied diagnostic may name the stage, HTTP status, error domain/code and model, but never the key,
// Authorization, address, port, query, request/response body or a lyric.
static void connectionSafe(NSString *text) {
    if (!text.length) return;
    for (NSString *secret in @[@"connection-fixture-key", @"other-fixture-key", @"Bearer", @"100.97.8.81", @"10100",
                               @"/chat/completions", @"/models", @"offline-model", @"The sky is blue", @"upstream detail"]) {
        CHECK([text rangeOfString:secret].location == NSNotFound);
    }
}
// One explicit check: exactly one transport call of its kind, exactly one main-thread completion, and no
// generation request for the free model check.
static SGTranslationConnectionReport *connectionResult(SGConnectionTestKind kind, NSData *data, NSInteger status, NSError *error, BOOL success) {
    __block NSUInteger calls = 0;
    __block SGTranslationConnectionReport *out;
    NSUInteger before = connectionSends, beforeModels = connectionModelSends;
    SGTranslationConnectionTest *test = SGTestOpenAIConnection(kind, ^(SGTranslationConnectionReport *report) {
        CHECK(NSThread.isMainThread && ++calls == 1 && report);
        CHECK(success ? !report.problem.length : report.problem.length > 0);
        if (kind == SGConnectionTestTranslation) CHECK(success ? report.translated == SGConnectionFactYes
                                                              : report.translated != SGConnectionFactYes);
        CHECK(![report respondsToSelector:NSSelectorFromString(@"translation")]);
        connectionSafe(report.problem);
        connectionSafe(report.diagnostic);
        out = report;
    });
    CHECK(test);
    if (kind == SGConnectionTestModels) {
        CHECK(connectionModelSends == beforeModels + 1 && connectionSends == before);
        connectionModelReply(data, status, error);
        connectionModelReply(data, status, error); // Deliberately hostile duplicate transport callback.
    } else {
        CHECK(connectionSends == before + 1 && connectionModelSends == beforeModels);
        connectionReply(data, status, error);
        connectionReply(data, status, error);
    }
    connectionDrain(); CHECK(calls == 1);
    connectionReply = nil;
    connectionModelReply = nil;
    return out;
}
static void checkConnectionModels(void) {
    connectionModelTransport = ^NSURLSessionDataTask *(NSURLRequest *request, NSUInteger limit, void (^done)(NSData *, NSInteger, NSError *)) {
        CHECK(limit == 8 * 1024 * 1024 && NSThread.isMainThread);
        connectionModelSends++; connectionModelRequest = request; connectionModelReply = [done copy];
        connectionModelTask = [SGConnectionFakeTask new];
        return (id)connectionModelTask;
    };
    connectionConfigure();
    SGTranslationConnectionReport *report = connectionResult(SGConnectionTestModels, connectionModels(@[@"offline-model", @"other"]), 200, nil, YES);
    CHECK([connectionModelRequest.HTTPMethod isEqual:@"GET"] && [connectionModelRequest.HTTPBody length] == 0);
    CHECK([connectionModelRequest.URL.absoluteString isEqual:@"http://100.97.8.81:10100/v1/models"]);
    CHECK([[connectionModelRequest valueForHTTPHeaderField:@"Authorization"] isEqual:@"Bearer connection-fixture-key"]);
    CHECK(report.stage == SGConnectionCheckModels && report.reachable == SGConnectionFactYes &&
          report.authenticated == SGConnectionFactUnknown && report.models == SGConnectionFactYes);
    CHECK([report.diagnostic containsString:@"stage=models"] && [report.diagnostic containsString:@"http=200"] &&
          ![report.diagnostic containsString:@"model="] && [report.diagnostic containsString:@"sent=yes"] &&
          [report.diagnostic containsString:@"reachable=yes authenticated=unknown models=yes translated=unknown"]);

    // A 401 proves the transport works while the key fails; the two facts stay separate.
    report = connectionResult(SGConnectionTestModels, connectionData(@"connection-fixture-key upstream detail"), 401, nil, NO);
    CHECK(report.stage == SGConnectionCheckAuthentication && report.reachable == SGConnectionFactYes &&
          report.authenticated == SGConnectionFactNo && report.models == SGConnectionFactUnknown);
    CHECK([report.diagnostic containsString:@"http=401"]);
    // A 404 model list is not proof that chat fails; the model fact stays unknown.
    report = connectionResult(SGConnectionTestModels, connectionData(@"upstream detail"), 404, nil, NO);
    CHECK(report.stage == SGConnectionCheckModels && report.reachable == SGConnectionFactYes &&
          report.models == SGConnectionFactUnknown && [report.problem containsString:@"Test translation"]);
    report = connectionResult(SGConnectionTestModels, connectionData(@"upstream detail"), 405, nil, NO);
    CHECK(report.models == SGConnectionFactUnknown);
    // A public model list, readable or not, says nothing about whether a key was checked.
    report = connectionResult(SGConnectionTestModels, [@"invalid JSON" dataUsingEncoding:NSUTF8StringEncoding], 200, nil, NO);
    CHECK(report.reachable == SGConnectionFactYes && report.authenticated == SGConnectionFactUnknown &&
          report.models == SGConnectionFactUnknown);
    report = connectionResult(SGConnectionTestModels, connectionData(@"upstream detail"), 500, nil, NO);
    CHECK(report.stage == SGConnectionCheckModels && report.reachable == SGConnectionFactYes);
    report = connectionResult(SGConnectionTestModels, connectionData(@"connection-fixture-key"), 418, nil, NO);
    CHECK(report.models == SGConnectionFactNo && [report.problem containsString:@"418"]);
    // Network failures are the connection's, with the NSError's domain and code, never its description.
    report = connectionResult(SGConnectionTestModels, nil, 0, [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCannotConnectToHost
        userInfo:@{NSLocalizedDescriptionKey: @"connection-fixture-key http://100.97.8.81:10100 upstream detail"}], NO);
    CHECK(report.stage == SGConnectionCheckConnection && report.reachable == SGConnectionFactNo &&
          report.authenticated == SGConnectionFactUnknown);
    CHECK([report.diagnostic containsString:@"error=NSURLErrorDomain/-1004"] &&
          ![report.diagnostic containsString:@"NSLocalizedDescription"]);
    for (NSNumber *code in @[@(NSURLErrorAppTransportSecurityRequiresSecureConnection), @(NSURLErrorTimedOut), @(NSURLErrorCannotFindHost), @(NSURLErrorNotConnectedToInternet)]) {
        report = connectionResult(SGConnectionTestModels, nil, 0, [NSError errorWithDomain:NSURLErrorDomain code:code.integerValue userInfo:nil], NO);
        CHECK(report.stage == SGConnectionCheckConnection && report.problem.length);
    }
    report = connectionResult(SGConnectionTestModels, connectionModels(@[@"offline-model"]), 200,
        [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorDataLengthExceedsMaximum userInfo:nil], NO);
    CHECK(report.stage == SGConnectionCheckModels && report.reachable == SGConnectionFactYes &&
          report.authenticated == SGConnectionFactUnknown && report.models == SGConnectionFactUnknown);
    CHECK([report.problem containsString:@"could not be read"] && [report.diagnostic containsString:@"http=200"]);
    connectionModelTransport = nil;
}

static NSInteger connectionHTTPStatus;
static NSData *connectionHTTPData;
static BOOL connectionHTTPHold;
static NSUInteger connectionHTTPStarts;
static NSTimeInterval connectionRequestTimeout, connectionResourceTimeout;
static BOOL connectionRequestCookies;
// Kept alive so its resource timeout can be read after production has finished setting policies.
static NSURLSessionConfiguration *connectionFixtureConfiguration;
@interface SGConnectionProtocol : NSURLProtocol
@end
@implementation SGConnectionProtocol
+ (BOOL)canInitWithRequest:(NSURLRequest *)request { return [request.URL.host isEqual:@"127.0.0.1"] && request.URL.port.integerValue == 1; }
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request { return request; }
- (void)startLoading {
    dispatch_async(dispatch_get_main_queue(), ^{
    connectionHTTPStarts++; connectionRequestTimeout = self.request.timeoutInterval;
    connectionRequestCookies = self.request.HTTPShouldHandleCookies;
    connectionResourceTimeout = connectionFixtureConfiguration.timeoutIntervalForResource;
    if (connectionHTTPHold) return;
    NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:self.request.URL statusCode:connectionHTTPStatus HTTPVersion:@"HTTP/1.1" headerFields:@{}];
    [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    [self.client URLProtocol:self didLoadData:connectionHTTPData];
    [self.client URLProtocolDidFinishLoading:self];
    });
}
- (void)stopLoading {}
@end
// Ephemeral sessions do not inherit globally registered protocols on every OS.
// Inject only the protocol list; production owns every transport policy and delegate.
@interface NSURLSessionConfiguration (SGConnectionFixture)
+ (NSURLSessionConfiguration *)sg_connectionEphemeral;
@end
@implementation NSURLSessionConfiguration (SGConnectionFixture)
+ (NSURLSessionConfiguration *)sg_connectionEphemeral {
    NSURLSessionConfiguration *config = [self sg_connectionEphemeral];
    connectionFixtureConfiguration = config;
    config.protocolClasses = @[SGConnectionProtocol.class];
    return config;
}
@end
// Test the exact production redirect delegate separately: NSURLProtocol redirects are not portable.
@interface SGLyricsTranslationRequest : NSObject <NSURLSessionDataDelegate>
@end
static void checkConnectionTransport(void) {
    Method original = class_getClassMethod(NSURLSessionConfiguration.class, @selector(ephemeralSessionConfiguration));
    Method fixture = class_getClassMethod(NSURLSessionConfiguration.class, @selector(sg_connectionEphemeral));
    method_exchangeImplementations(original, fixture);
    NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:@"http://127.0.0.1:1/connection-fixture"]];
    for (NSNumber *code in @[@200, @429, @503]) {
        connectionHTTPStatus = code.integerValue; connectionHTTPData = [@"fixture" dataUsingEncoding:NSUTF8StringEncoding];
        NSUInteger before = connectionHTTPStarts;
        __block NSUInteger calls = 0;
        SGLyricsTranslationRealSendOnce(request, ^(NSData *data, NSInteger status, NSError *error) {
            CHECK(NSThread.isMainThread && ++calls == 1 && !error && status == code.integerValue);
            CHECK([data isEqual:connectionHTTPData]);
        });
        waitFor(^BOOL { return calls > 0; });
        CHECK(connectionHTTPStarts == before + 1 && connectionRequestTimeout == 20 && !connectionRequestCookies);
    }
    // Unknown-length payloads exercise accumulation bounds, not merely Content-Length rejection.
    for (NSNumber *size in @[@(512 * 1024), @(512 * 1024 + 1)]) {
        connectionHTTPStatus = 200; connectionHTTPData = [NSMutableData dataWithLength:size.unsignedIntegerValue];
        __block NSUInteger calls = 0;
        SGLyricsTranslationRealSendOnce(request, ^(NSData *data, NSInteger status, NSError *error) {
            CHECK(NSThread.isMainThread && ++calls == 1);
            CHECK(size.unsignedIntegerValue == 512 * 1024 ? (!error && data.length == 512 * 1024) : (error && !data));
        });
        waitFor(^BOOL { return calls > 0; });
    }
    connectionHTTPHold = YES;
    NSUInteger before = connectionHTTPStarts;
    __block NSUInteger calls = 0;
    NSURLSessionDataTask *task = SGLyricsTranslationRealSendOnce(request, ^(NSData *data, NSInteger status, NSError *error) {
        CHECK(NSThread.isMainThread && ++calls == 1 && !data && error.code == NSURLErrorCancelled);
    });
    waitFor(^BOOL { return connectionHTTPStarts > before; });
    [task cancel]; waitFor(^BOOL { return calls == 1; });
    connectionHTTPHold = NO;
    // A Gemini job's chosen timeout (30–300 s) bounds the whole job; every 60 s caller keeps the old resource cap.
    for (NSNumber *seconds in @[@30, @60, @120, @300]) {
        NSMutableURLRequest *job = [request mutableCopy];
        job.timeoutInterval = seconds.doubleValue;
        connectionHTTPStatus = 200; connectionHTTPData = [@"fixture" dataUsingEncoding:NSUTF8StringEncoding];
        __block NSUInteger calls = 0;
        SGLyricsTranslationRealSendRequest(job, YES, nil, ^(NSData *data, NSInteger status, NSError *error) {
            CHECK(NSThread.isMainThread && ++calls == 1 && !error);
        });
        waitFor(^BOOL { return calls > 0; });
        CHECK(connectionRequestTimeout == seconds.doubleValue && connectionResourceTimeout == MAX(60, seconds.doubleValue));
    }
    SGLyricsTranslationRequest *receiver = [SGLyricsTranslationRequest new];
    __block BOOL refused = NO;
    [receiver URLSession:NSURLSession.sharedSession task:task willPerformHTTPRedirection:[[NSHTTPURLResponse alloc] initWithURL:request.URL statusCode:302 HTTPVersion:@"HTTP/1.1" headerFields:@{@"Location": @"https://other.invalid/"}] newRequest:request completionHandler:^(NSURLRequest *redirect) { CHECK(!redirect); refused = YES; }];
    CHECK(refused);
    method_exchangeImplementations(original, fixture);
    puts("Connection transport: real SendOnce, 20s request, 429/503 no retry, cancel, 512 KiB boundary, Gemini job resource timeout; direct redirect delegate passed");
}
static void checkConnection(void) {
    NSArray *settings = @[SGKeyLyricsOpenAIBaseURL, SGKeyLyricsOpenAIModel];
    NSMutableDictionary *saved = [NSMutableDictionary dictionary];
    for (NSString *key in settings) saved[key] = [NSUserDefaults.standardUserDefaults objectForKey:key] ?: NSNull.null;
    NSSet *savedKeys = testKeys; NSMutableDictionary *savedOpenAIKeys = openAIKeys;
    NSString *savedLanguage = testLanguage;
    connectionConfigure();
    checkConnectionModels();

    // No key: an actionable configuration report, and nothing sent for either check. Reading a row can never
    // trigger generation; only an explicit SGTestOpenAIConnection call sends.
    [openAIKeys removeAllObjects];
    for (NSNumber *kind in @[@(SGConnectionTestModels), @(SGConnectionTestTranslation)]) {
        NSUInteger before = connectionSends, beforeModels = connectionModelSends;
        __block NSUInteger calls = 0;
        __block SGTranslationConnectionReport *report;
        SGTranslationConnectionTest *test = SGTestOpenAIConnection(kind.integerValue, ^(SGTranslationConnectionReport *r) { CHECK(NSThread.isMainThread && ++calls == 1); report = r; });
        connectionDrain();
        CHECK(test && calls == 1 && report.stage == SGConnectionCheckConfiguration && report.problem.length);
        CHECK([report.problem containsString:@"key"] && report.reachable == SGConnectionFactUnknown);
        CHECK([report.diagnostic containsString:@"sent=no"]);
        connectionSafe(report.diagnostic);
        CHECK(connectionSends == before && connectionModelSends == beforeModels);
    }
    // An address no request can be built from is configuration too, and sends nothing.
    connectionConfigure();
    [NSUserDefaults.standardUserDefaults setObject:@"http://openrouter.ai/v1" forKey:SGKeyLyricsOpenAIBaseURL];
    openAIKeys = [@{@"https://openrouter.ai:443": [@"other-fixture-key" dataUsingEncoding:NSUTF8StringEncoding]} mutableCopy];
    for (NSNumber *kind in @[@(SGConnectionTestModels), @(SGConnectionTestTranslation)]) {
        NSUInteger before = connectionSends, beforeModels = connectionModelSends;
        __block SGTranslationConnectionReport *report;
        SGTestOpenAIConnection(kind.integerValue, ^(SGTranslationConnectionReport *r) { report = r; });
        connectionDrain();
        CHECK(report.stage == SGConnectionCheckConfiguration && connectionSends == before && connectionModelSends == beforeModels);
    }
    connectionConfigure();

    // The paid sample: one request only when asked, exact host/model/auth/fixed prompt, safe reply.
    SGTranslationConnectionReport *report = connectionResult(SGConnectionTestTranslation, connectionData(@"하늘은 파랗다."), 200, nil, YES);
    CHECK(report.translated == SGConnectionFactYes && report.authenticated == SGConnectionFactUnknown);
    CHECK([connectionRequest.URL.absoluteString isEqual:@"http://100.97.8.81:10100/v1/chat/completions"]);
    CHECK([[connectionRequest valueForHTTPHeaderField:@"Authorization"] isEqual:@"Bearer connection-fixture-key"]);
    CHECK([connectionRequest.HTTPMethod isEqual:@"POST"]);
    NSDictionary *body = [NSJSONSerialization JSONObjectWithData:connectionRequest.HTTPBody options:0 error:nil];
    CHECK([body[@"model"] isEqual:@"offline-model"] && [body[@"messages"] count] == 2);
    CHECK([body[@"messages"][0][@"content"] isEqual:SGLyricsTranslationInstruction()]);
    CHECK([body[@"messages"][1][@"content"] isEqual:SGLyricsTranslationPrompt(@[@"The sky is blue."], @"ko")]);
    CHECK([report.diagnostic containsString:@"stage=translation"] && [report.diagnostic containsString:@"http=200"]);

    // Translation failure categories stay distinct, and a 401 is authentication rather than connection.
    report = connectionResult(SGConnectionTestTranslation, connectionData(@"connection-fixture-key upstream detail"), 401, nil, NO);
    CHECK(report.stage == SGConnectionCheckAuthentication && report.reachable == SGConnectionFactYes &&
          report.authenticated == SGConnectionFactNo && report.translated == SGConnectionFactUnknown);
    report = connectionResult(SGConnectionTestTranslation, connectionData(@"upstream detail"), 403, nil, NO);
    CHECK(report.stage == SGConnectionCheckAuthentication);
    report = connectionResult(SGConnectionTestTranslation, connectionData(@"upstream detail"), 400, nil, NO);
    CHECK(report.stage == SGConnectionCheckTranslation && report.translated == SGConnectionFactNo && report.models == SGConnectionFactNo);
    report = connectionResult(SGConnectionTestTranslation, connectionData(@"upstream detail"), 404, nil, NO);
    CHECK(report.translated == SGConnectionFactNo && report.models == SGConnectionFactNo);
    report = connectionResult(SGConnectionTestTranslation, connectionData(@"upstream detail"), 429, nil, NO);
    CHECK(report.stage == SGConnectionCheckTranslation && report.reachable == SGConnectionFactYes);
    report = connectionResult(SGConnectionTestTranslation, connectionData(@"upstream detail"), 503, nil, NO);
    CHECK(report.stage == SGConnectionCheckTranslation);
    report = connectionResult(SGConnectionTestTranslation, connectionData(@"upstream detail"), 418, nil, NO);
    CHECK(report.translated == SGConnectionFactNo && [report.problem containsString:@"418"] && report.authenticated == SGConnectionFactUnknown);
    report = connectionResult(SGConnectionTestTranslation, nil, 0, [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorTimedOut
        userInfo:@{NSLocalizedDescriptionKey: @"connection-fixture-key"}], NO);
    CHECK(report.stage == SGConnectionCheckConnection && report.reachable == SGConnectionFactNo && [report.diagnostic containsString:@"-1001"]);
    report = connectionResult(SGConnectionTestTranslation, nil, 0, nil, NO);
    CHECK(report.reachable == SGConnectionFactUnknown && report.authenticated == SGConnectionFactUnknown);
    for (NSNumber *code in @[@(NSURLErrorDataLengthExceedsMaximum), @(NSURLErrorCannotDecodeContentData), @(NSURLErrorNetworkConnectionLost)]) {
        report = connectionResult(SGConnectionTestTranslation, connectionData(@"하늘은 파랗다."), 200,
            [NSError errorWithDomain:NSURLErrorDomain code:code.integerValue userInfo:@{NSLocalizedDescriptionKey: @"connection-fixture-key"}], NO);
        CHECK(report.reachable == SGConnectionFactYes && report.authenticated == SGConnectionFactUnknown &&
              report.translated == SGConnectionFactNo && report.stage == SGConnectionCheckTranslation);
        CHECK([report.problem containsString:@"could not be read"] &&
              [report.diagnostic containsString:@"http=200"] && [report.diagnostic containsString:@"reachable=yes"]);
    }
    // User-controlled model names and arbitrary error domains must never enter diagnostic copy.
    [NSUserDefaults.standardUserDefaults setObject:@"https://connection-fixture-key@100.97.8.81:10100/models" forKey:SGKeyLyricsOpenAIModel];
    report = connectionResult(SGConnectionTestTranslation, nil, 0,
        [NSError errorWithDomain:@"connection-fixture-key http://100.97.8.81:10100 upstream detail" code:17 userInfo:nil], NO);
    CHECK([report.diagnostic containsString:@"error=other/17"] && ![report.diagnostic containsString:@"model="]);
    connectionConfigure();
    for (id root in @[chatReply(@"[\"하늘은 파랗다.\"]"), chatReply(@"L0002\t하늘은 파랗다."),
                      chatReply(@"L0001\t하늘\nL0001\t파랗다."),
                      @{@"choices": @[@{@"message": @{@"content": @"L0001\t하늘은 파랗다."}, @"finish_reason": @"length"}]},
                      @{@"choices": @[@{@"message": @{@"content": @"L0001\t하늘은 파랗다.", @"refusal": @"No"}, @"finish_reason": @"stop"}]}]) {
        report = connectionResult(SGConnectionTestTranslation, [NSJSONSerialization dataWithJSONObject:root options:0 error:nil], 200, nil, NO);
        CHECK(report.translated == SGConnectionFactNo && report.reachable == SGConnectionFactYes && report.authenticated == SGConnectionFactUnknown);
    }

    // Valid-shaped echoes may pass the shape check, but no response text is returned in the report.
    for (NSString *echo in @[@"100.97.8.81", @"http://100.97.8.81:10100/v1", @"offline-model",
                            @"connection-fixture-key", @"http://100.97.8.81:10100/v1/chat/completions?key=connection-fixture-key"]) {
        report = connectionResult(SGConnectionTestTranslation, connectionData(echo), 200, nil, YES);
        CHECK(!report.problem && [report.diagnostic rangeOfString:echo].location == NSNotFound);
    }
    // Malformed/empty/oversized replies still fail without exposing any upstream content.
    for (NSData *data in @[[NSData data], [@"invalid JSON" dataUsingEncoding:NSUTF8StringEncoding], connectionData(@""),
                           connectionData(@" \n "),
                           connectionData([@"x" stringByPaddingToLength:513 withString:@"x" startingAtIndex:0]),
                           [NSMutableData dataWithLength:512 * 1024 + 1]]) {
        report = connectionResult(SGConnectionTestTranslation, data, 200, nil, NO);
        CHECK(report.translated == SGConnectionFactNo);
    }
    report = connectionResult(SGConnectionTestTranslation, connectionData([@"x" stringByPaddingToLength:512 withString:@"x" startingAtIndex:0]), 200, nil, YES);

    // Explicit cancel, each changed setting with/without notification, and unchanged generic redraw.
    for (NSNumber *notify in @[@0, @1, @2]) for (NSString *change in @[@"cancel", @"base", @"model", @"key", @"target", @"redraw"]) {
        connectionConfigure(); __block NSUInteger calls = 0;
        SGTranslationConnectionTest *test = SGTestOpenAIConnection(SGConnectionTestTranslation, ^(SGTranslationConnectionReport *r) { CHECK(NSThread.isMainThread); calls++; });
        if ([change isEqual:@"cancel"]) [test cancel];
        else if ([change isEqual:@"base"]) [NSUserDefaults.standardUserDefaults setObject:@"http://100.97.8.81:10101/v2" forKey:SGKeyLyricsOpenAIBaseURL];
        else if ([change isEqual:@"model"]) [NSUserDefaults.standardUserDefaults setObject:@"different-model" forKey:SGKeyLyricsOpenAIModel];
        else if ([change isEqual:@"key"]) openAIKeys[@"http://100.97.8.81:10100"] = [@"replacement-fixture-key" dataUsingEncoding:NSUTF8StringEncoding];
        else if ([change isEqual:@"target"]) testLanguage = @"ja";
        if (notify.boolValue || [change isEqual:@"redraw"]) {
            NSNotificationName name = notify.integerValue == 1 ? SGLyricsTranslationServiceSettingsDidChangeNotification : SGLyricsTranslationsDidChangeNotification;
            [NSNotificationCenter.defaultCenter postNotificationName:name object:nil];
        }
        BOOL redraw = [change isEqual:@"redraw"];
        if (notify.boolValue && !redraw) CHECK(connectionTask.cancelled);
        connectionReply(connectionData(@"하늘은 파랗다."), 200, nil);
        connectionDrain(); CHECK(calls == (redraw ? 1 : 0));
        if (!redraw) CHECK(connectionTask.cancelled);
        connectionReply = nil;
    }
    for (NSString *key in settings) { if (saved[key] == NSNull.null) [NSUserDefaults.standardUserDefaults removeObjectForKey:key]; else [NSUserDefaults.standardUserDefaults setObject:saved[key] forKey:key]; }
    testKeys = savedKeys; openAIKeys = savedOpenAIKeys; testLanguage = savedLanguage;
    puts("Connection checks: configuration/no-key without a send, free GET /models with separate reachability/auth/model facts, paid sample only when asked, error categories, hostile reply redaction, single completion, cancellation and stale configuration passed");
    checkConnectionTransport();
}
