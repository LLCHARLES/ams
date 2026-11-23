#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import "AdBlock.h"
#import "Protobuf.h"
#include <stdbool.h>
#include <stdatomic.h>

BOOL SGHidden(NSString *key) { return [key isEqual:SGKeyFakePremium] && atoi(getenv("FAKE_PREMIUM") ?: "0"); }
void SGRequireClasses(NSArray<NSString *> *names) {}
void SGAdBlockCountOne(NSString *label) {}
void SGAdBlockSawOne(NSString *label) {}
NSData *SGStripFeed(NSData *data) { return data; }

@interface AttributeTask : NSURLSessionTask
@property NSURLRequest *request;
@property NSURLResponse *reply;
@end
@implementation AttributeTask
- (NSURLRequest *)currentRequest { return self.request; }
- (NSURLRequest *)originalRequest { return self.request; }
- (NSURLResponse *)response { return self.reply; }
@end

@interface AttributeDelegate : NSObject <NSURLSessionDataDelegate>
@property NSMutableData *body;
@property NSInteger status;
@property NSUInteger completions;
@property NSError *error;
@property NSHTTPURLResponse *response;
@property BOOL deferResponse, dataOnDelegateQueue;
@property void (^decision)(NSURLSessionResponseDisposition);
@end
@implementation AttributeDelegate
- (instancetype)init { if ((self = [super init])) _body = [NSMutableData new]; return self; }
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveResponse:(NSURLResponse *)response completionHandler:(void (^)(NSURLSessionResponseDisposition))handler {
    self.status = [(NSHTTPURLResponse *)response statusCode];
    self.response = (NSHTTPURLResponse *)response;
    if (self.deferResponse) self.decision = handler;
    else handler(NSURLSessionResponseAllow);
}
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveData:(NSData *)data {
    self.dataOnDelegateQueue = NSOperationQueue.currentQueue == session.delegateQueue;
    [self.body appendData:data];
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error { self.completions++; self.error = error; }
@end
@interface SPTDataLoaderService : AttributeDelegate @end
@implementation SPTDataLoaderService @end
@interface _TtC26Connectivity_HttpClientKit20HttpClientURLSession : AttributeDelegate @end
@implementation _TtC26Connectivity_HttpClientKit20HttpClientURLSession @end
@interface SPTCoreURLSessionDataDelegate : AttributeDelegate @end
@implementation SPTCoreURLSessionDataDelegate @end
#include "AdNetwork.m"

static atomic_uint failures, checks;
static void check(BOOL condition, NSString *name) {
    checks++;
    if (!condition) { failures++; NSLog(@"FAIL %@", name); }
}
static NSData *hex(const char *text) {
    NSMutableData *data = [NSMutableData new];
    while (*text) {
        unsigned byte;
        if (sscanf(text, "%2x", &byte) != 1) exit(2);
        uint8_t value = byte;
        [data appendBytes:&value length:1];
        text += 2;
    }
    return data;
}
static NSData *join(NSData *a, NSData *b) { NSMutableData *out = [a mutableCopy]; [out appendData:b]; return out; }
static NSData *entry(NSString *key, NSData *value) {
    return SGPBSerialize(@[SGPBBytes(1, SGPBSerialize(@[SGPBString(1, key), SGPBBytes(2, value)]))]);
}
static NSData *account(BOOL existing) {
    NSData *data = join(entry(@"type", hex("220466726565")), hex("98067b"));
    if (!existing) return data;
    data = join(data, entry(@"offline", hex("100098067b")));
    data = join(data, entry(@"can-use-offline", hex("220130")));
    data = join(data, entry(@"max-offline-tracks", hex("180a")));
    return join(data, entry(@"max-offline-downloads-per-device", hex("22023130")));
}
static NSData *envelope(NSData *attributes, NSUInteger shape) {
    if (shape == 2) return attributes;
    NSData *identifier = SGPBSerialize(@[SGPBString(1, @"core-playback-setup"), SGPBString(2, @"crossfade_enabled")]);
    NSData *configuration = SGPBSerialize(@[SGPBBytes(3, SGPBSerialize(@[SGPBBytes(1, identifier), SGPBBytes(3, NSData.data)]))]);
    NSData *ucs = SGPBSerialize(@[SGPBBytes(1, SGPBSerialize(@[SGPBBytes(1, configuration)])),
                                 SGPBBytes(3, attributes), SGPBBytes(99, hex("deadbeef"))]);
    NSData *customize = SGPBSerialize(@[SGPBBytes(1, ucs)]);
    return shape == 0 ? customize : SGPBSerialize(@[SGPBBytes(2, SGPBSerialize(@[SGPBBytes(1, SGPBSerialize(@[SGPBBytes(1, customize)]))]))]);
}
static NSData *unwrap(NSData *data, NSUInteger shape) {
    NSArray *path = shape == 0 ? @[@1, @3] : shape == 1 ? @[@2, @1, @1, @1, @3] : @[];
    for (NSNumber *number in path) data = SGPBFirst(SGPBParse(data), number.unsignedIntValue).payload;
    return data;
}
static NSData *value(NSData *attributes, NSString *key) {
    for (SGPBField *field in SGPBParse(attributes)) {
        if (field.number != 1 || field.wire != 2) continue;
        NSArray *map = SGPBParse(field.payload);
        if ([SGPBText(SGPBFirst(map, 1)) isEqual:key]) return SGPBFirst(map, 2).payload;
    }
    return nil;
}
static NSURL *urlFor(NSUInteger shape) {
    return [NSURL URLWithString:@[@"https://spclient.wg.spotify.com/user-customization-service/v1/customize",
                                  @"https://spclient.wg.spotify.com/bootstrap/v1/bootstrap",
                                  @"https://spclient.wg.spotify.com/nebula/v1/configuration/attributes"][shape]];
}
static AttributeDelegate *receiveTask(Class cls, NSURLSession *session, NSURLSessionDataTask *task, NSInteger status,
                                     NSDictionary *headers, NSArray<NSData *> *chunks, NSError *error) {
    AttributeDelegate *delegate = [cls new];
    NSURLResponse *reply = [[NSHTTPURLResponse alloc] initWithURL:task.currentRequest.URL statusCode:status HTTPVersion:@"HTTP/2" headerFields:headers];
    dispatch_semaphore_t answered = dispatch_semaphore_create(0);
    [delegate URLSession:session dataTask:task didReceiveResponse:reply completionHandler:^(NSURLSessionResponseDisposition disposition) {
        dispatch_semaphore_signal(answered);
    }];
    check(dispatch_semaphore_wait(answered, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)) == 0,
          @"response decision completed");
    for (NSData *chunk in chunks) [delegate URLSession:session dataTask:(id)task didReceiveData:chunk];
    [delegate URLSession:session task:task didCompleteWithError:error];
    check(delegate.completions == 1 && delegate.error == error, @"single completion/error preserved");
    [task cancel];
    return delegate;
}
static AttributeDelegate *receiveChunks(Class cls, NSURLSession *session, NSURLRequest *request, NSInteger status,
                                        NSDictionary *headers, NSArray<NSData *> *chunks, NSError *error) {
    return receiveTask(cls, session, [session dataTaskWithRequest:request], status, headers, chunks, error);
}
static AttributeDelegate *receive(Class cls, NSURL *url, NSInteger status, NSData *body, NSError *error) {
    NSUInteger split = body.length / 2;
    NSArray *chunks = body.length ? @[[body subdataWithRange:NSMakeRange(0, split)],
                                     [body subdataWithRange:NSMakeRange(split, body.length - split)]] : @[];
    return receiveChunks(cls, NSURLSession.sharedSession, [NSURLRequest requestWithURL:url], status, @{}, chunks, error);
}
static void attributesMatch(NSData *data, NSUInteger shape, BOOL admitted, BOOL spoof, BOOL existing) {
    NSData *attrs = unwrap(data, shape);
    if (shape != 2) {
        NSData *ucs = data;
        for (NSNumber *number in (shape == 0 ? @[@1] : @[@2, @1, @1, @1]))
            ucs = SGPBFirst(SGPBParse(ucs), number.unsignedIntValue).payload;
        check([SGPBFirst(SGPBParse(ucs), 99).payload isEqual:hex("deadbeef")], @"unknown UCS payload preserved");
        NSData *configuration = SGPBFirst(SGPBParse(SGPBFirst(SGPBParse(ucs), 1).payload), 1).payload;
        NSData *assigned = SGPBFirst(SGPBParse(configuration), 3).payload;
        check([SGPBFirst(SGPBParse(assigned), 3).payload isEqual:hex(spoof ? "0801" : "")], @"remote configuration follows Premium only");
    }
    check([value(attrs, @"type") isEqual:hex(spoof ? "22077072656d69756d" : "220466726565")], @"Premium setting isolation");
    if (admitted) {
        check([value(attrs, @"offline") isEqual:hex(existing ? "98067b1001" : "1001")], @"offline bool and unknown value field");
        check([value(attrs, @"can-use-offline") isEqual:hex(existing ? "220131" : "1001")], @"offline flag preserves string/default bool type");
        check([value(attrs, @"max-offline-tracks") isEqual:hex("18c0843d")], @"track limit integer is 1000000, not bool");
        check([value(attrs, @"max-offline-downloads-per-device") isEqual:hex(existing ? "220731303030303030" : "18c0843d")], @"device limit preserves string/default integer type");
    } else {
        for (NSString *key in @[@"offline", @"can-use-offline", @"max-offline-tracks", @"max-offline-downloads-per-device"]) {
            NSData *expected = value(account(existing), key), *actual = value(attrs, key);
            check((!expected && !actual) || [actual isEqual:expected], @"absent/rejected companion must not grant offline");
        }
    }
    check(SGPBFirst(SGPBParse(attrs), 99).varint == 123, @"unrelated account field");
}
static void protocolCases(BOOL loaded, BOOL admitted) {
    for (Class cls in @[SPTDataLoaderService.class, _TtC26Connectivity_HttpClientKit20HttpClientURLSession.class, SPTCoreURLSessionDataDelegate.class]) {
        BOOL core = cls == SPTCoreURLSessionDataDelegate.class;
        for (NSUInteger shape = 0; shape < 3; shape++) {
            BOOL spoof = premium && !core && shape != 2;
            for (NSNumber *existing in @[@NO, @YES]) {
                NSData *input = envelope(account(existing.boolValue), shape);
                AttributeDelegate *live = receive(cls, urlFor(shape), 200, input, nil);
                attributesMatch(live.body, shape, admitted && shape == 2, spoof, existing.boolValue);
                if (!(admitted && shape == 2) && !spoof) check([live.body isEqual:input], @"no-op preserves full response");
                if ((loaded && shape == 2) || (spoof && shape == 0)) {
                    AttributeDelegate *replay = receive(cls, urlFor(shape), 304, nil, nil);
                    check(replay.status == 200 && [replay.body isEqual:live.body], @"304 replays consistent transformed response");
                }
            }
            NSArray *malformedBodies = shape == 2 ? @[hex("0aff"), hex("00"), hex("0a00"),
                entry(@"offline", hex("1002")), entry(@"offline", hex("10001801"))] : @[hex("0aff"), hex("00")];
            for (NSData *malformed in malformedBodies) {
                AttributeDelegate *bad = receive(cls, urlFor(shape), 200, malformed, nil);
                check([bad.body isEqual:malformed], @"malformed response passes unchanged");
            }
        }
    }
}

// Spotify 9.2 has no customize: Spoof Premium rewrites the account attributes and the remote config on their
// own and strips their validators; 9.1.x leaves both as they were.
static void splitCases(BOOL loaded) {
    NSURL *config = [NSURL URLWithString:@"https://spclient.wg.spotify.com/remote-config-resolver/v3/configuration"];
    NSData *identifier = SGPBSerialize(@[SGPBString(1, @"core-playback-setup"), SGPBString(2, @"crossfade_enabled")]);
    NSData *assignedValue = SGPBSerialize(@[SGPBBytes(1, identifier), SGPBBytes(3, NSData.data)]);
    NSData *resolve = SGPBSerialize(@[SGPBBytes(1, SGPBSerialize(@[SGPBBytes(3, assignedValue)]))]);
    for (NSNumber *split in @[@NO, @YES]) {
        premiumSplit = premium && split.boolValue;
        for (NSURL *url in @[config, urlFor(2)]) {
            // Pixie strips the attributes' validators itself.
            if (loaded && url != config) continue;
            NSMutableURLRequest *conditional = [NSMutableURLRequest requestWithURL:url];
            [conditional setValue:@"etag" forHTTPHeaderField:@"If-None-Match"];
            NSURLSessionDataTask *task = [NSURLSession.sharedSession dataTaskWithRequest:conditional];
            BOOL kept = [task.currentRequest valueForHTTPHeaderField:@"If-None-Match"] != nil;
            check(kept != premiumSplit,
                  @"9.2 config requests lose their validators only under 9.2 Premium");
            [task cancel];
        }
        for (Class cls in @[SPTDataLoaderService.class, _TtC26Connectivity_HttpClientKit20HttpClientURLSession.class]) {
            AttributeDelegate *live = receive(cls, urlFor(2), 200, account(NO), nil);
            attributesMatch(live.body, 2, loaded, premiumSplit, NO);
            AttributeDelegate *replay = receive(cls, urlFor(2), 304, nil, nil);
            if (loaded) check(replay.status == 200 && [replay.body isEqual:live.body], @"9.2 replay carries Pixie's and Premium's values");
            else check(replay.status == 304 && !replay.body.length, @"bodiless attributes 304 reaches Spotify as sent");
            AttributeDelegate *remote = receive(cls, config, 200, resolve, nil);
            NSData *first = SGPBFirst(SGPBParse(SGPBFirst(SGPBParse(remote.body), 1).payload), 3).payload;
            check([SGPBFirst(SGPBParse(first), 3).payload isEqual:hex(premiumSplit ? "0801" : "")],
                  @"9.2 remote config follows Premium's flag rules");
            if (!premiumSplit) check([remote.body isEqual:resolve], @"remote config untouched off 9.2 Premium");
        }
    }
    premiumSplit = NO;
}

static NSData *transportBody;
static NSInteger transportStatus;
static BOOL transportUnconditional;
@interface AttributesProtocol : NSURLProtocol @end
@implementation AttributesProtocol
+ (BOOL)canInitWithRequest:(NSURLRequest *)request { return YES; }
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request { return request; }
- (void)startLoading {
    transportUnconditional = ![self.request valueForHTTPHeaderField:@"If-None-Match"]
        && ![self.request valueForHTTPHeaderField:@"If-Modified-Since"]
        && self.request.cachePolicy == NSURLRequestReloadIgnoringLocalCacheData;
    NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:self.request.URL statusCode:transportStatus HTTPVersion:@"HTTP/2"
                                                       headerFields:@{@"ETag": @"\"wire\"", @"Content-Length": @(transportBody.length).stringValue}];
    [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    if (transportBody) [self.client URLProtocol:self didLoadData:transportBody];
    [self.client URLProtocolDidFinishLoading:self];
}
- (void)stopLoading {}
@end

static void completionCases(void) {
    NSURLSessionConfiguration *config = NSURLSessionConfiguration.ephemeralSessionConfiguration;
    config.protocolClasses = @[AttributesProtocol.class];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config];
    for (NSUInteger shape = 2; shape < 3; shape++) {
        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:urlFor(shape)];
        [request setValue:@"etag" forHTTPHeaderField:@"If-None-Match"];
        [request setValue:@"date" forHTTPHeaderField:@"If-Modified-Since"];
        NSData *live;
        for (NSNumber *statusCode in @[@200, @304]) {
            transportStatus = statusCode.integerValue;
            transportBody = transportStatus == 200 ? envelope(account(NO), shape) : nil;
            transportUnconditional = NO;
            dispatch_semaphore_t completed = dispatch_semaphore_create(0);
            __block NSData *result;
            __block NSInteger status;
            __block NSError *failure;
            __block NSHTTPURLResponse *reply;
            [[session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
                result = data; status = [(NSHTTPURLResponse *)response statusCode]; failure = error;
                reply = (NSHTTPURLResponse *)response;
                dispatch_semaphore_signal(completed);
            }] resume];
            if (dispatch_semaphore_wait(completed, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC))) {
                check(NO, @"completion-handler transport timed out");
                [session invalidateAndCancel];
                return;
            }
            check(!failure && transportUnconditional, @"actual task factory bypasses cold cache");
            check(![reply valueForHTTPHeaderField:@"ETag"] && ![reply valueForHTTPHeaderField:@"Content-Length"],
                  @"completion handler receives rewritten response metadata");
            if (transportStatus == 200) {
                attributesMatch(result, shape, YES, premium && shape != 2, NO);
                live = result;
            } else check(status == 200 && [result isEqual:live], @"actual completion-handler 304 replay");
        }
    }
    [session finishTasksAndInvalidate];
}

static void securityCases(void) {
    NSData *body = account(NO);
    NSURLRequest *request = [NSURLRequest requestWithURL:urlFor(2)];
    NSDictionary *headers = @{@"Content-Length": @(body.length).stringValue, @"ETag": @"\"original\"",
                               @"Last-Modified": @"date", @"X-Keep": @"kept"};
    AttributeDelegate *changed = receiveChunks(SPTCoreURLSessionDataDelegate.class, NSURLSession.sharedSession, request, 200, headers, @[body], nil);
    check(![changed.response valueForHTTPHeaderField:@"Content-Length"]
          && ![changed.response valueForHTTPHeaderField:@"ETag"] && ![changed.response valueForHTTPHeaderField:@"Last-Modified"]
          && [[changed.response valueForHTTPHeaderField:@"X-Keep"] isEqual:@"kept"], @"rewritten metadata omits stale length and validators");
    AttributeDelegate *partial = receiveChunks(SPTDataLoaderService.class, NSURLSession.sharedSession, request, 206, headers, @[body], nil);
    check([partial.body isEqual:body] && partial.status == 206
          && [[partial.response valueForHTTPHeaderField:@"ETag"] isEqual:@"\"original\""], @"206 passes body and headers untouched");
    NSError *error = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorTimedOut userInfo:nil];
    for (Class cls in @[SPTDataLoaderService.class, SPTCoreURLSessionDataDelegate.class]) {
        check([receive(cls, urlFor(2), 200, body, error).body isEqual:body], @"Pixie-only partial data survives errors regardless of Premium");
        NSData *config = envelope(body, 0);
        NSData *expected = premium && cls == SPTDataLoaderService.class ? NSData.data : config;
        check([receive(cls, urlFor(0), 200, config, error).body isEqual:expected], @"legacy buffering retains its original error contract");
    }
    for (NSString *address in @[@"http://spclient.wg.spotify.com/nebula/v1/configuration/attributes",
                               @"https://spclient.wg.spotify.com/Nebula/v1/configuration/attributes",
                               @"https://spclient.wg.spotify.com/prefix/bootstrap/v1/bootstrap/suffix",
                               @"https://spclient.wg.spotify.com/user-customization-service/v1/customize-extra"]) {
        check([receive(SPTCoreURLSessionDataDelegate.class, [NSURL URLWithString:address], 200, body, nil).body isEqual:body],
              @"offline routing requires HTTPS and exact case-sensitive paths");
    }
    NSURLSession *session = [NSURLSession sessionWithConfiguration:NSURLSessionConfiguration.ephemeralSessionConfiguration];
    NSData *large = SGPBSerialize(@[SGPBBytes(100, [NSMutableData dataWithLength:4 * 1024 * 1024])]);
    AttributeDelegate *oversize = receiveChunks(SPTCoreURLSessionDataDelegate.class, session, request, 200, @{}, @[body, large], nil);
    check([oversize.body isEqual:join(body, large)], @"oversize body flushes original prefix and suffix without rewriting");
    check(receiveChunks(SPTCoreURLSessionDataDelegate.class, session, request, 304, @{}, @[], nil).status == 304,
          @"oversize body is never retained for replay");
    receiveChunks(SPTCoreURLSessionDataDelegate.class, session, request, 200, @{}, @[body], nil);
    NSURLSession *other = [NSURLSession sessionWithConfiguration:NSURLSessionConfiguration.ephemeralSessionConfiguration];
    check(receiveChunks(SPTCoreURLSessionDataDelegate.class, other, request, 304, @{}, @[], nil).status == 304,
          @"session change discards prior account cache");
    NSMutableURLRequest *authorized = [request mutableCopy];
    [authorized setValue:@"fixture-account-A" forHTTPHeaderField:@"Authorization"];
    receiveChunks(SPTCoreURLSessionDataDelegate.class, session, authorized, 200, @{}, @[body], nil);
    [authorized setValue:@"fixture-account-B" forHTTPHeaderField:@"Authorization"];
    check(receiveChunks(SPTCoreURLSessionDataDelegate.class, session, authorized, 304, @{}, @[], nil).status == 304,
          @"authorization change discards prior account cache");
    for (NSUInteger index = 0; index < 4; index++) {
        NSURL *url = [NSURL URLWithString:[urlFor(2).absoluteString stringByAppendingFormat:@"?variant=%lu", (unsigned long)index]];
        receiveChunks(SPTCoreURLSessionDataDelegate.class, session, [NSURLRequest requestWithURL:url], 200, @{}, @[body], nil);
    }
    NSURL *first = [NSURL URLWithString:[urlFor(2).absoluteString stringByAppendingString:@"?variant=0"]];
    check(receiveChunks(SPTCoreURLSessionDataDelegate.class, session, [NSURLRequest requestWithURL:first], 304, @{}, @[], nil).status == 304,
          @"raw cache keeps only one URL per fixed endpoint");
    NSURL *invalid = [NSURL URLWithString:[urlFor(2).absoluteString stringByAppendingString:@"?invalid=1"]];
    receiveChunks(SPTCoreURLSessionDataDelegate.class, session, [NSURLRequest requestWithURL:invalid], 200, @{}, @[hex("0a00")], nil);
    check(receiveChunks(SPTCoreURLSessionDataDelegate.class, session, [NSURLRequest requestWithURL:invalid], 304, @{}, @[], nil).status == 304,
          @"unrecognized 200 is never cached");
    receiveChunks(SPTCoreURLSessionDataDelegate.class, session, request, 200, @{}, @[body], nil);
    NSURLSessionDataTask *logout = [session dataTaskWithRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"https://spclient.wg.spotify.com/logout"]]];
    [logout cancel];
    check(receiveChunks(SPTCoreURLSessionDataDelegate.class, session, request, 304, @{}, @[], nil).status == 304,
          @"logout request clears raw account cache");
    receiveChunks(SPTCoreURLSessionDataDelegate.class, session, request, 200, @{}, @[body], nil);
    NSURLSessionDataTask *pending = [session dataTaskWithRequest:request];
    [session invalidateAndCancel];
    check(receiveTask(SPTCoreURLSessionDataDelegate.class, session, pending, 304, @{}, @[], nil).status == 304,
          @"session invalidation clears raw cache");
    [other invalidateAndCancel];
    check(SGPBParse(hex("808080801000")) == nil && SGPBParse(hex("88808080800100")) == nil,
          @"protobuf rejects field numbers above 29 bits before narrowing");
}

static int reviewRegressions(const char *libraryPath) {
    SEL dataSelector = @selector(URLSession:dataTask:didReceiveData:);
    if (!premium)
        check(class_getMethodImplementation(SPTDataLoaderService.class, dataSelector)
              == class_getMethodImplementation(AttributeDelegate.class, dataSelector),
              @"R1 no delegate interception without settings or companion");
    AttributeDelegate *stream = [SPTCoreURLSessionDataDelegate new];
    AttributeTask *task = class_createInstance(AttributeTask.class, 0);
    task.request = [NSURLRequest requestWithURL:urlFor(2)];
    task.reply = [[NSHTTPURLResponse alloc] initWithURL:urlFor(2) statusCode:200 HTTPVersion:nil headerFields:nil];
    NSURLSession *session = NSURLSession.sharedSession;
    NSData *prefix = entry(@"type", hex("220466726565")), *suffix = entry(@"offline", hex("1000"));
    [stream URLSession:session dataTask:(id)task didReceiveResponse:task.reply completionHandler:^(NSURLSessionResponseDisposition d) {}];
    [stream URLSession:session dataTask:(id)task didReceiveData:prefix];
    void *library = dlopen(libraryPath, RTLD_NOW | RTLD_GLOBAL);
    if (!library) { NSLog(@"FAIL dlopen: %s", dlerror()); return 1; }
    dispatch_sync(offlineInstallQueue, ^{});
    void (*admit)(bool) = dlsym(library, "SGTestSetAdmitted");
    void (*observe)(dispatch_block_t) = dlsym(library, "SGTestSetAdmissionObserver");
    admit(true);
    [stream URLSession:session dataTask:(id)task didReceiveData:suffix];
    [stream URLSession:session task:task didCompleteWithError:nil];
    check([stream.body isEqual:join(prefix, suffix)], @"R3 late loading cannot rewrite a partial stream");
    receive(SPTDataLoaderService.class, urlFor(2), 200, account(YES), nil);
    admit(false);
    NSURL *missing = [NSURL URLWithString:[urlFor(2).absoluteString stringByAppendingString:@"?other-account=1"]];
    AttributeDelegate *revoked = receive(SPTDataLoaderService.class, missing, 304, nil, nil);
    check(revoked.status == 304 && !revoked.body.length, @"R2 missing raw URL cannot replay prior grants");
    admit(true);
    NSData *old = join(account(NO), entry(@"revision", hex("22036f6c64")));
    NSData *new = join(account(NO), entry(@"revision", hex("22036e6577")));
    receive(SPTCoreURLSessionDataDelegate.class, urlFor(2), 200, old, nil);
    dispatch_semaphore_t entered = dispatch_semaphore_create(0), release = dispatch_semaphore_create(0), finished = dispatch_semaphore_create(0);
    observe(^{
        dispatch_semaphore_signal(entered);
        dispatch_semaphore_wait(release, DISPATCH_TIME_FOREVER);
    });
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
        receive(SPTCoreURLSessionDataDelegate.class, urlFor(2), 304, nil, nil);
        dispatch_semaphore_signal(finished);
    });
    if (dispatch_semaphore_wait(entered, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC))) {
        check(NO, @"R5 replay did not reach transformer");
        dispatch_semaphore_signal(release);
        return 1;
    }
    receive(SPTCoreURLSessionDataDelegate.class, urlFor(2), 200, new, nil);
    dispatch_semaphore_signal(release);
    if (dispatch_semaphore_wait(finished, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC))) {
        check(NO, @"R5 replay did not finish"); return 1;
    }
    AttributeDelegate *latest = receive(SPTCoreURLSessionDataDelegate.class, urlFor(2), 304, nil, nil);
    check([value(latest.body, @"revision") isEqual:hex("22036e6577")], @"R5 replay must not overwrite newer raw input");
    NSURL *errorURL = [NSURL URLWithString:[urlFor(2).absoluteString stringByAppendingString:@"?error=1"]];
    receive(SPTCoreURLSessionDataDelegate.class, errorURL, 500, account(NO), nil);
    AttributeDelegate *errorReplay = receive(SPTCoreURLSessionDataDelegate.class, errorURL, 304, nil, nil);
    check(errorReplay.status == 304 && !errorReplay.body.length, @"R9 error body cannot become a cached 200");
    printf("review regressions: premium=%d failures=%u\n", premium, failures);
    return failures ? 1 : 0;
}

static void realTransformerCases(void *library, void (*admit)(bool), BOOL legacy) {
    NSData *(*withStatus)(NSData *, SAPOfflineAttributesStatus *) = dlsym(library, "SAPRewriteOfflineAccountAttributesWithStatus");
    check(legacy ? withStatus == NULL : withStatus != NULL, @"real companion has the requested exported ABI");
    for (NSNumber *allowed in @[@NO, @YES]) {
        admit(allowed.boolValue);
        for (NSNumber *valid in @[@NO, @YES]) {
            NSData *input = valid.boolValue ? account(NO) : hex("0a00");
            if (withStatus) {
                SAPOfflineAttributesStatus status = {NO, NO};
                NSData *output = withStatus(input, &status);
                check(status.recognized == valid.boolValue && status.admitted == allowed.boolValue,
                      @"real status separates recognition from admission");
                if (!valid.boolValue || !allowed.boolValue)
                    check(output == input, @"real rejected or unrecognized transform returns the input object");
            }
            BOOL recognized = NO;
            NSData *host = SGPatchOfflineAccountAttributes(input, &recognized);
            check(recognized == (!legacy && valid.boolValue), @"host consumes real recognition, including rejected hosts");
            if (valid.boolValue && allowed.boolValue)
                attributesMatch(host, 2, YES, NO, NO);
            else check(host == input, @"host preserves the real transformer's no-op object");
            NSURL *url = [NSURL URLWithString:[urlFor(2).absoluteString stringByAppendingFormat:@"?real-schema=%d&admission=%d",
                                               valid.boolValue, allowed.boolValue]];
            AttributeDelegate *live = receive(SPTCoreURLSessionDataDelegate.class, url, 200, input, nil);
            check([live.body isEqual:host], @"delegate uses real companion output");
            AttributeDelegate *replay = receive(SPTCoreURLSessionDataDelegate.class, url, 304, nil, nil);
            if (!legacy && valid.boolValue)
                check(replay.status == 200 && [replay.body isEqual:host], @"recognized real input is replayable independently of admission");
            else check(replay.status == 304 && !replay.body.length, @"unrecognized or old-symbol-only input cannot seed replay");
        }
    }
    admit(false);
    printf("real transformer integration: ABI=%s recognition/admission matrix complete\n", legacy ? "old-only" : "status");
}

static void completeCreatedTask(NSURLSession *session, NSURLSessionDataTask *task, NSData *body) {
    AttributeDelegate *delegate = [SPTDataLoaderService new];
    NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:task.currentRequest.URL
        statusCode:200 HTTPVersion:nil headerFields:nil];
    [delegate URLSession:session dataTask:task didReceiveResponse:response completionHandler:^(NSURLSessionResponseDisposition d) {}];
    [delegate URLSession:session dataTask:task didReceiveData:body];
    [delegate URLSession:session task:task didCompleteWithError:nil];
}

static int recheckRegressions(const char *libraryPath) {
    for (NSUInteger shape = 0; shape < 2; shape++) {
        NSData *ucs = SGPBSerialize(@[SGPBBytes(1, NSData.data), SGPBBytes(3, account(YES))]);
        NSData *input = SGPBSerialize(@[SGPBBytes(1, ucs)]);
        if (shape == 1) input = SGPBSerialize(@[SGPBBytes(2, SGPBSerialize(@[SGPBBytes(1,
            SGPBSerialize(@[SGPBBytes(1, input)]))]))]);
        AttributeDelegate *output = receive(SPTDataLoaderService.class, urlFor(shape), 200, input, nil);
        check([value(unwrap(output.body, shape), @"type") isEqual:hex(premium ? "22077072656d69756d" : "220466726565")],
              @"empty optional ResolveResponse retains legacy Premium attribute rewrite");
        check([value(unwrap(output.body, shape), @"offline") isEqual:hex("100098067b")],
              @"legacy Premium preserves offline fields without a companion");
    }
    // Hold installation after dyld publishes the image: legacy hooks can already receive bodies.
    dispatch_suspend(offlineInstallQueue);
    void *library = dlopen(libraryPath, RTLD_NOW | RTLD_GLOBAL);
    if (!library) { dispatch_resume(offlineInstallQueue); NSLog(@"FAIL dlopen: %s", dlerror()); return 1; }
    void (*admit)(bool) = dlsym(library, "SGTestSetAdmitted");
    admit(true);
    NSURLSession *session = [NSURLSession sessionWithConfiguration:NSURLSessionConfiguration.ephemeralSessionConfiguration];
    NSURLRequest *request = [NSURLRequest requestWithURL:urlFor(2)];
    NSURLSessionDataTask *beforeInstall = [session dataTaskWithRequest:request];
    dispatch_resume(offlineInstallQueue);
    dispatch_sync(offlineInstallQueue, ^{});
    completeCreatedTask(session, beforeInstall, account(NO));
    check(receiveChunks(SPTDataLoaderService.class, session, request, 304, @{}, @[], nil).status == 304,
          @"task predating offline hook publication cannot seed raw cache");
    completeCreatedTask(session, [session dataTaskWithRequest:request], account(NO));
    dispatch_sync(offlineInstallQueue, ^{ installOfflineHooks(); });
    check(receiveChunks(SPTDataLoaderService.class, session, request, 304, @{}, @[], nil).status == 200,
          @"published hooks retain recognized bytes across repeated installation");

    for (NSNumber *invalidate in @[@NO, @YES]) {
        NSURLSessionDataTask *old = [session dataTaskWithRequest:request];
        NSURLSessionDataTask *probe;
        if (invalidate.boolValue) probe = [session dataTaskWithRequest:request];
        if (invalidate.boolValue) [session finishTasksAndInvalidate];
        else [[session dataTaskWithRequest:[NSURLRequest requestWithURL:
            [NSURL URLWithString:@"https://spclient.wg.spotify.com/logout"]]] cancel];
        if (!invalidate.boolValue) probe = [session dataTaskWithRequest:request];
        completeCreatedTask(session, old, account(NO));
        check(receiveTask(SPTDataLoaderService.class, session, probe, 304, @{}, @[], nil).status == 304,
              @"task created before account/session invalidation cannot repopulate raw cache");
    }
    session = [NSURLSession sessionWithConfiguration:NSURLSessionConfiguration.ephemeralSessionConfiguration];
    for (Class cls in @[SPTDataLoaderService.class, _TtC26Connectivity_HttpClientKit20HttpClientURLSession.class, SPTCoreURLSessionDataDelegate.class]) {
        for (NSNumber *allow in @[@NO, @YES]) {
            completeCreatedTask(session, [session dataTaskWithRequest:request], account(NO));
            NSURLSessionDataTask *task = [session dataTaskWithRequest:request];
            AttributeDelegate *delegate = [cls new];
            delegate.deferResponse = YES;
            NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:urlFor(2) statusCode:304 HTTPVersion:nil headerFields:nil];
            dispatch_semaphore_t answered = dispatch_semaphore_create(0);
            [delegate URLSession:session dataTask:task didReceiveResponse:response completionHandler:^(NSURLSessionResponseDisposition d) {
                dispatch_semaphore_signal(answered);
            }];
            check(delegate.body.length == 0, @"cached bytes wait for response disposition");
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
                delegate.decision(allow.boolValue ? NSURLSessionResponseAllow : NSURLSessionResponseCancel);
            });
            check(dispatch_semaphore_wait(answered, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)) == 0,
                  @"asynchronous response disposition completed");
            check(allow.boolValue ? delegate.body.length > 0 && delegate.dataOnDelegateQueue : delegate.body.length == 0,
                  @"replay only follows Allow on the delegate queue");
            [task cancel];
        }
    }
    [session invalidateAndCancel];
    printf("recheck regressions: premium=%d failures=%u\n", premium, failures);
    return failures ? 1 : 0;
}

int main(int argc, const char **argv) {
    @autoreleasepool {
        check(argc == 2, @"companion fixture path");
        if (getenv("RECHECK_REGRESSIONS")) return recheckRegressions(argv[1]);
        if (getenv("REVIEW_REGRESSIONS")) return reviewRegressions(argv[1]);
        protocolCases(NO, NO);
        splitCases(NO);
        void *library = dlopen(argv[1], RTLD_NOW | RTLD_GLOBAL);
        if (!library) { NSLog(@"FAIL dlopen: %s", dlerror()); return 1; }
        dispatch_sync(offlineInstallQueue, ^{});
        void (*admit)(bool) = dlsym(library, "SGTestSetAdmitted");
        if (!admit) { NSLog(@"FAIL admission fixture export"); return 1; }
        if (getenv("FOREIGN_COMPANION")) {
            check(!SGOfflineCompanionLoaded(), @"unrelated image cannot supply Pixie's transformer");
            return failures ? 1 : 0;
        }
        realTransformerCases(library, admit, getenv("OLD_COMPANION") != NULL);
        if (getenv("OLD_COMPANION")) {
            admit(true);
            for (NSUInteger shape = 0; shape < 3; shape++) {
                AttributeDelegate *live = receive(SPTCoreURLSessionDataDelegate.class, urlFor(shape), 200, envelope(account(NO), shape), nil);
                attributesMatch(live.body, shape, shape == 2, NO, NO);
                check(receive(SPTCoreURLSessionDataDelegate.class, urlFor(shape), 304, nil, nil).status == 304,
                      @"old companion cannot certify cache recognition");
            }
            return failures ? 1 : 0;
        }
        protocolCases(YES, NO);
        // The rejected server bytes are cached; admission must be checked again at replay.
        admit(true);
        for (NSUInteger shape = 2; shape < 3; shape++) {
            // Seed a valid rejected response after the malformed-body cases.
            admit(false);
            receive(SPTDataLoaderService.class, urlFor(shape), 200, envelope(account(YES), shape), nil);
            admit(true);
            AttributeDelegate *replay = receive(SPTDataLoaderService.class, urlFor(shape), 304, nil, nil);
            attributesMatch(replay.body, shape, YES, premium && shape != 2, YES);
        }
        protocolCases(YES, YES);
        splitCases(YES);
        completionCases();
        securityCases();
        NSURL *foreign = [NSURL URLWithString:@"https://example.com/nebula/v1/configuration/attributes"];
        NSData *input = account(NO);
        check([receive(SPTDataLoaderService.class, foreign, 200, input, nil).body isEqual:input], @"non-Spotify request isolation");
        [offlineInputs removeAllObjects];
        AttributeDelegate *empty = receive(SPTCoreURLSessionDataDelegate.class, urlFor(2), 304, nil, nil);
        check(empty.status == 304 && !empty.body.length, @"uncached 304 never fabricates attributes");
        NSError *error = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorTimedOut userInfo:nil];
        check([receive(SPTCoreURLSessionDataDelegate.class, urlFor(2), 200, input, error).body isEqual:input], @"failed core request preserves raw body");
        printf("offline attributes: Spoof Premium=%d checks=%u failures=%u\n", premium, checks, failures);
        return failures ? 1 : 0;
    }
}
