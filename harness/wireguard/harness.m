// macOS integration of the production Foundation hooks with a real WireGuard
// provider. Spotify admission/import slots are test doubles, not device evidence.
#import <Foundation/Foundation.h>
#import <Network/Network.h>
#import <arpa/inet.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <fcntl.h>
#import <sys/socket.h>
#import "../../tweak/Sources/Shared/WireGuard/SGWGCore.h"

int SGWGNativeTestConnect(int, const struct sockaddr *, socklen_t);
ssize_t SGWGNativeTestSendto(int, const void *, size_t, int, const struct sockaddr *, socklen_t);
nw_connection_t SGWGNativeTestNWCreate(nw_endpoint_t, nw_parameters_t);

#define CHECK(cond, ...) do { if (!(cond)) { \
    fprintf(stderr, "FAIL %s:%d: ", __FILE__, __LINE__); \
    fprintf(stderr, __VA_ARGS__); fprintf(stderr, "\n"); exit(1); \
} } while (0)

static NSString *Env(NSString *name) { return NSProcessInfo.processInfo.environment[name]; }
void SGWGNotifyRecovery(void) {}

@interface SPTCoreURLSessionDataDelegate : NSObject
@property NSUInteger calls, bytes;
- (void)URLSession:(id)session task:(id)task didCompleteWithError:(id)error;
- (void)URLSession:(id)session dataTask:(id)task didReceiveData:(NSData *)data;
@end
@implementation SPTCoreURLSessionDataDelegate
- (void)URLSession:(id)session task:(id)task didCompleteWithError:(id)error { self.calls++; }
- (void)URLSession:(id)session dataTask:(id)task didReceiveData:(NSData *)data { self.bytes += data.length; }
@end

// Deliberately incompatible: observer installation must preserve this method.
@interface SPTDataLoaderService : NSObject
@property NSUInteger calls;
- (NSInteger)URLSession:(id)session task:(id)task didCompleteWithError:(id)error;
@end
@implementation SPTDataLoaderService
- (NSInteger)URLSession:(id)session task:(id)task didCompleteWithError:(id)error { self.calls++; return 73; }
@end

@interface FixtureTask : NSURLSessionDataTask
@property NSHTTPURLResponse *fixtureResponse;
@property NSURLRequest *fixtureRequest;
@end
@implementation FixtureTask
- (NSURLResponse *)response { return self.fixtureResponse; }
- (NSURLRequest *)currentRequest { return self.fixtureRequest; }
- (NSURLRequest *)originalRequest { return self.fixtureRequest; }
@end

// Only the local external-proxy fixture uses a pinned test certificate.
@interface FixtureTrust : NSObject <NSURLSessionDelegate>
@end
@implementation FixtureTrust
- (void)URLSession:(NSURLSession *)session didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge
 completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition, NSURLCredential *))completion {
    NSData *der = Env(@"SGWG_TEST_CERT") ? [NSData dataWithContentsOfFile:Env(@"SGWG_TEST_CERT")] : nil;
    if (der && [challenge.protectionSpace.host isEqualToString:@"fixture.invalid"] &&
        [challenge.protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust]) {
        SecTrustRef trust = challenge.protectionSpace.serverTrust;
        SecCertificateRef cert = SecCertificateCreateWithData(NULL, (__bridge CFDataRef)der);
        SecTrustSetAnchorCertificates(trust, (__bridge CFArrayRef)@[(__bridge id)cert]);
        SecTrustSetAnchorCertificatesOnly(trust, true);
        CFRelease(cert);
        if (SecTrustEvaluateWithError(trust, NULL)) {
            completion(NSURLSessionAuthChallengeUseCredential, [NSURLCredential credentialForTrust:trust]);
            return;
        }
    }
    completion(NSURLSessionAuthChallengePerformDefaultHandling, nil);
}
@end

typedef struct { NSInteger status; NSString *body; NSError *error; NSDictionary *headers; } Result;

static Result Get(NSURLSession *session, NSString *url, NSString *range) {
    __block Result result = {0};
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]];
    request.timeoutInterval = 12;
    if (range) [request setValue:range forHTTPHeaderField:@"Range"];
    NSURLSessionDataTask *task = [session dataTaskWithRequest:request completionHandler:
        ^(NSData *data, NSURLResponse *response, NSError *error) {
            result.status = [response isKindOfClass:NSHTTPURLResponse.class] ? [(NSHTTPURLResponse *)response statusCode] : 0;
            result.headers = [response isKindOfClass:NSHTTPURLResponse.class] ? [(NSHTTPURLResponse *)response allHeaderFields] : nil;
            result.body = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
            result.error = error;
            dispatch_semaphore_signal(done);
        }];
    [task resume];
    if (dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC))) {
        [task cancel];
        CHECK(NO, "request did not complete within harness deadline");
    }
    return result;
}

static void WaitForEngine(void) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:10];
    while (!SGWGReady() && deadline.timeIntervalSinceNow > 0) usleep(10000);
    CHECK(SGWGReady(), "guards/engine unavailable: %s", SGWGStateDescription(SGWGCurrentState()).UTF8String);
}

static void NativeDenialChecks(void) {
    struct sockaddr_in remote = {.sin_len = sizeof(remote), .sin_family = AF_INET, .sin_port = htons(443)};
    inet_pton(AF_INET, "1.1.1.1", &remote.sin_addr);
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    CHECK(fd >= 0 && fcntl(fd, F_SETFL, O_NONBLOCK) == 0, "socket setup");
    CHECK(SGWGNativeTestConnect(fd, (const void *)&remote, sizeof(remote)) == -1 && errno == ENETUNREACH,
          "remote BSD TCP not denied");
    CHECK(fcntl(fd, F_GETFL) & O_NONBLOCK, "caller nonblocking mode changed");
    CHECK(SGWGNativeTestConnect(fd, (const void *)&remote, 1) == -1 && errno == EINVAL,
          "short sockaddr not rejected");
    close(fd);
    fd = socket(AF_INET, SOCK_DGRAM, 0);
    remote.sin_port = htons(53);
    CHECK(fd >= 0 && SGWGNativeTestSendto(fd, "x", 1, 0, (const void *)&remote, sizeof(remote)) == -1 &&
          errno == ENETUNREACH, "remote DNS UDP not denied");
    close(fd);
    puts("PASS remote BSD TCP and DNS UDP denied; short sockaddr rejected; O_NONBLOCK preserved");
}

static BOOL GoImageMapped(void) {
    for (uint32_t i = 0; i < _dyld_image_count(); i++)
        if ([@(_dyld_get_image_name(i)).lastPathComponent isEqualToString:@"libsgwg.dylib"]) return YES;
    return NO;
}

static void LoaderFailureChecks(void) {
    NSString *expected = Env(@"SGWG_TEST_LOADER_ERROR");
    NSString *reason;
    CHECK(!SGWGInspectProfile(@"private input", &reason) && [reason isEqualToString:expected], "profile admission");
    CHECK([SGWGRedactText(@"private input") isEqualToString:expected], "unsafe redaction fallback");
    CHECK([SGWGDiagnosticsReport(@{@"country": @"private input"}) isEqualToString:expected], "unsafe report fallback");
    CHECK(!SGWGReady() && SGWGGuardsInstalled() && [SGWGEngineStatus()[@"error"] isEqualToString:expected],
          "engine not guarded on loader failure");
    if (getenv("SGWG_EXPECT_UNMAPPED")) CHECK(!GoImageMapped(), "loaded despite override");
}

static void UnitChecks(void) {
    BOOL enabled = [Env(@"SGWG_EXPECT_ACTIVE") boolValue];
    CHECK(SGWGActiveThisLaunch() == enabled, "armed state");
    if (!enabled) {
        CHECK(!GoImageMapped(), "disabled launch mapped the Go runtime");
        CHECK([[NSURLSessionConfiguration.ephemeralSessionConfiguration valueForKey:@"proxyConfigurations"] count] == 0,
              "proxy applied while disabled");
        puts("PASS disabled: no proxy");
        return;
    }
    WaitForEngine();
    NativeDenialChecks();
    NSURLSessionConfiguration *config = NSURLSessionConfiguration.ephemeralSessionConfiguration;
    [config setValue:@[] forKey:@"proxyConfigurations"];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config];
    NSArray *proxies = [session.configuration valueForKey:@"proxyConfigurations"];
    bool (*getFailover)(void *) = dlsym(RTLD_DEFAULT, "nw_proxy_config_get_failover_allowed");
    CHECK(proxies.count == 1 && getFailover && !getFailover((__bridge void *)proxies.firstObject),
          "session failed to restore proxy without failover");
    [session invalidateAndCancel];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"https://example.com"]];
    if ([request respondsToSelector:NSSelectorFromString(@"setAssumesHTTP3Capable:")]) {
        [request setValue:@YES forKey:@"assumesHTTP3Capable"];
        CHECK(![[request valueForKey:@"assumesHTTP3Capable"] boolValue], "HTTP3 still enabled");
    }
    NSError *error = nil;
    NSData *data = [[NSMutableData alloc] initWithContentsOfURL:request.URL options:0 error:&error];
    CHECK(data == nil && error != nil, "main-thread NSData initializer must fail immediately");
    FixtureTask *task = [FixtureTask new];
    task.fixtureRequest = [NSURLRequest requestWithURL:[NSURL URLWithString:@"https://audio-fa.scdn.co/audio/secret?sig=SECRETSIG"]];
    task.fixtureResponse = [[NSHTTPURLResponse alloc] initWithURL:task.fixtureRequest.URL statusCode:403 HTTPVersion:@"HTTP/1.1" headerFields:nil];
    SPTCoreURLSessionDataDelegate *events = [SPTCoreURLSessionDataDelegate new];
    [events URLSession:nil dataTask:task didReceiveData:[NSMutableData dataWithLength:12]];
    [events URLSession:nil dataTask:task didReceiveData:[NSMutableData dataWithLength:13]];
    task.fixtureRequest = [NSURLRequest requestWithURL:[NSURL URLWithString:@"https://api.spotify.com/test"]];
    [events URLSession:nil dataTask:task didReceiveData:[NSMutableData dataWithLength:7]];
    CHECK([SGWGTransportReportLines() containsObject:@"spotify.received-bytes: media 25 api 7"], "in-flight byte accounting");
    [events URLSession:nil task:task didCompleteWithError:[NSError errorWithDomain:NSURLErrorDomain code:-1005 userInfo:nil]];
    CHECK(events.calls == 1 && events.bytes == 32, "delegate forwarding");
    SPTDataLoaderService *wrong = [SPTDataLoaderService new];
    CHECK([wrong URLSession:nil task:task didCompleteWithError:nil] == 73 && wrong.calls == 1, "wrong observer ABI changed");
    NSString *report = SGWGDiagnosticsReport(@{});
    CHECK([report containsString:@"spotify.http-status: 403 x1"], "observer counter absent");
    CHECK(![report containsString:@"SECRETSIG"] && ![report containsString:@"scdn.co"], "diagnostics leaked URL");
    puts("PASS session enforcement, HTTP3, NSData initializer denial, observer forwarding and redaction");
}

static void FailClosedChecks(void) {
    CHECK(SGWGActiveThisLaunch(), "saved opt-in must remain armed");
    if ([Env(@"SGWG_EXPECT_BLOCKED") boolValue])
        CHECK(SGWGCurrentState() == SGWGStateBlocked, "version/build mismatch not blocked");
    else WaitForEngine();
    NativeDenialChecks();
    NSURLSession *session = [NSURLSession sessionWithConfiguration:NSURLSessionConfiguration.ephemeralSessionConfiguration];
    Result result = Get(session, @"https://www.cloudflare.com/cdn-cgi/trace", nil);
    CHECK(result.error != nil, "public HTTPS succeeded with unavailable tunnel");
    result = Get(session, Env(@"SGWG_TEST_DIRECT_URL"), nil);
    CHECK(result.error != nil, "direct sentinel request succeeded");
    [session invalidateAndCancel];
    puts("PASS unavailable tunnel/admission: covered requests fail");
}

static void LiveChecks(void) {
    WaitForEngine();
    NativeDenialChecks();
    NSURLSession *session = [NSURLSession sessionWithConfiguration:NSURLSessionConfiguration.ephemeralSessionConfiguration];
    Result result = Get(session, @"https://www.cloudflare.com/cdn-cgi/trace", nil);
    NSString *ip = nil, *country = nil;
    for (NSString *line in [result.body componentsSeparatedByString:@"\n"]) {
        if ([line hasPrefix:@"ip="]) ip = [line substringFromIndex:3];
        if ([line hasPrefix:@"loc="]) country = [line substringFromIndex:4];
    }
    CHECK(result.status == 200 && ip.length, "tunnel HTTPS trace failed: HTTP %ld error %ld",
          (long)result.status, (long)result.error.code);
    CHECK([country isEqualToString:Env(@"SGWG_EXPECT_COUNTRY")], "unexpected tunnel exit country");
    CHECK(![ip isEqualToString:Env(@"SGWG_DIRECT_IP")], "tunnel exit equals direct Mac exit");
    printf("PASS live exit country %s; exit differs from direct Mac IP\n", country.UTF8String);
    result = Get(NSURLSession.sharedSession, @"https://www.google.com/generate_204", nil);
    CHECK(result.status == 204, "shared-session HTTPS: HTTP %ld error %ld", (long)result.status, (long)result.error.code);
    result = Get(session, @"https://www.gstatic.com/images/branding/googlelogo/2x/googlelogo_color_272x92dp.png", @"bytes=0-1023");
    CHECK(result.status == 206 && [result.headers[@"Content-Range"] hasPrefix:@"bytes 0-1023/"],
          "HTTPS range response: HTTP %ld", (long)result.status);
    result = Get(session, Env(@"SGWG_TEST_DIRECT_URL"), nil);
    CHECK(result.error != nil, "direct sentinel was reachable");

    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    __block BOOL fetched = NO;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSError *error = nil;
        NSMutableData *data = [[NSMutableData alloc] initWithContentsOfURL:
            [NSURL URLWithString:@"https://www.cloudflare.com/cdn-cgi/trace"] options:0 error:&error];
        fetched = !error && data.length && [data isKindOfClass:NSMutableData.class];
        if (fetched) [data appendBytes:"x" length:1];
        dispatch_semaphore_signal(done);
    });
    CHECK(dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 15 * NSEC_PER_SEC)) == 0 && fetched,
          "background mutable NSData initializer failed");
    NSDictionary *status = SGWGEngineStatus();
    CHECK(status[@"handshakeAgeSec"] && [status[@"handshakeAgeSec"] longLongValue] >= 0, "no WireGuard handshake");
    [session invalidateAndCancel];
    puts("PASS live Proton: handshake, HTTPS/206, shared session and mutable NSData; direct sentinel blocked");
    printf("%s\n", SGWGDiagnosticsReport(@{@"country": country, @"exitDiffers": @"yes"}).UTF8String);
}

static void DeferredGuardChecks(void) {
    // Capture the session while it refers to the reservation. The proxy will
    // subsequently accept connections, but must not resolve or dial for them.
    NSURLSession *session = NSURLSession.sharedSession;
    NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:10];
    while (![SGWGEngineStatus()[@"running"] boolValue] && limit.timeIntervalSinceNow > 0) usleep(10000);
    CHECK([SGWGEngineStatus()[@"running"] boolValue] && !SGWGReady(), "expected running but unadmitted engine");
    NativeDenialChecks();
    NSString *url = Env(@"SGWG_TEST_DIRECT_URL");
    NSURLComponents *parts = [NSURLComponents componentsWithString:url];
    CHECK(!SGWGNativeTestNWCreate(nw_endpoint_create_host(parts.host.UTF8String, parts.port.stringValue.UTF8String),
          nw_parameters_create_secure_tcp(NW_PARAMETERS_DISABLE_PROTOCOL, NW_PARAMETERS_DEFAULT_CONFIGURATION)),
          "native TCP connection created while blocked");
    CHECK(Get(session, url, nil).error, "covered HTTP not blocked");
    parts.scheme = @"ws";
    NSURLSessionWebSocketTask *task = [session webSocketTaskWithURL:parts.URL];
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    __block BOOL failed = NO;
    [task resume];
    [task receiveMessageWithCompletionHandler:^(NSURLSessionWebSocketMessage *message, NSError *error) {
        failed = error != nil;
        dispatch_semaphore_signal(done);
    }];
    CHECK(!dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 15*NSEC_PER_SEC)) && failed,
          "blocked WebSocket did not fail");
    NSDictionary *connections = SGWGEngineStatus()[@"connections"];
    CHECK([connections[@"total"] isEqual:@0], "unadmitted engine attempted a destination");
    puts("PASS running but unadmitted: HTTP, WebSocket and native TCP blocked");
}

static void OfflineBootstrapChecks(void) {
    NSURLSession *early = NSURLSession.sharedSession;
    NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:15];
    while (SGWGCurrentState() != SGWGStateFailed && limit.timeIntervalSinceNow > 0) usleep(10000);
    CHECK(SGWGCurrentState() == SGWGStateFailed && !SGWGReady() &&
          ![SGWGEngineStatus()[@"running"] boolValue], "bootstrap failure not retriable");
    // Substitute reachable bootstrap data in the private copy, not the user's
    // profile or the system resolver. Use the real path-trigger entry point.
    NSData *restored = [NSData dataWithContentsOfFile:Env(@"SGWG_TEST_RESTORED_PROFILE")];
    CHECK([restored writeToFile:Env(@"SGWG_TEST_PROFILE") atomically:YES], "fixture restore failed");
    SGWGRequestRebind(@"path");
    WaitForEngine();
    CHECK(Get(early, @"https://www.google.com/generate_204", nil).status == 204,
          "early session failed after bootstrap recovery");
    puts("PASS hostname bootstrap failure followed by recovery on early session");
}

static void ExternalChecks(void) {
    WaitForEngine();
    NSString *kind = Env(@"SGWG_TEST_KIND");
    CHECK([SGWGActiveKind() isEqualToString:kind], "external kind");
    NSURLSession *session = [NSURLSession sessionWithConfiguration:NSURLSessionConfiguration.ephemeralSessionConfiguration
        delegate:[FixtureTrust new] delegateQueue:nil];
    Result result = Get(session, Env(@"SGWG_TEST_ORIGIN_URL"), @"bytes=0-9");
    if ([Env(@"SGWG_EXPECT_OK") boolValue])
        CHECK(result.status == 206 && result.body.length == 10, "external proxy range: HTTP %ld error %ld",
              (long)result.status, (long)result.error.code);
    else CHECK(result.error != nil, "unavailable external proxy succeeded");
    NSString *password = Env(@"SGWG_TEST_PASS");
    CHECK(!password.length || ![SGWGDiagnosticsReport(@{}) containsString:password], "proxy password in report");
    [session invalidateAndCancel];
    printf("PASS external %s\n", kind.UTF8String);
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSString *mode = argc > 1 ? @(argv[1]) : @"unit";
        if ([mode isEqualToString:@"unit"]) UnitChecks();
        else if ([mode isEqualToString:@"loader-failure"]) LoaderFailureChecks();
        else if ([mode isEqualToString:@"live"]) LiveChecks();
        else if ([mode isEqualToString:@"deferred"]) DeferredGuardChecks();
        else if ([mode isEqualToString:@"offline"]) OfflineBootstrapChecks();
        else if ([mode isEqualToString:@"failclosed"]) FailClosedChecks();
        else if ([mode isEqualToString:@"external"]) ExternalChecks();
        else CHECK(NO, "unknown harness mode");
    }
    return 0;
}
