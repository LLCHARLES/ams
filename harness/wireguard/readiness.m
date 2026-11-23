// Production Objective-C event/admission owner; Go and Spotify import admission are boundaries.
#import "Shared/WireGuard/SGWGCore.m"

static unsigned notices, rebinds;
static BOOL admitted = YES, patches = YES;
static atomic_bool sharedImageLoaded;
static int sessionPort;
static CreateSocksFn realCreateSocks;
static void *recordSocksEndpoint(void *endpoint) {
    sessionPort = nw_endpoint_get_port((__bridge nw_endpoint_t)endpoint);
    return realCreateSocks(endpoint);
}
static dispatch_semaphore_t admissionEntered, admissionContinue;
#define CHECK(value) do { if (!(value)) { fprintf(stderr, "FAIL readiness:%d %s\n", __LINE__, #value); exit(1); } } while (0)

BOOL SGWGInstallNativePatches(void) { return patches; }
BOOL SGWGCheckAdmission(BOOL *pendingImages) {
    BOOL ready = SGWGAdmissionReady();
    if (pendingImages) *pendingImages = !ready && getenv("SGWG_TEST_DELAY_ADMISSION") != NULL;
    return ready;
}
BOOL SGWGAdmissionReady(void) {
    BOOL result = admitted && (!getenv("SGWG_TEST_DELAY_ADMISSION") || sharedImageLoaded);
    if (admissionEntered) {
        dispatch_semaphore_signal(admissionEntered);
        dispatch_semaphore_wait(admissionContinue, DISPATCH_TIME_FOREVER);
    }
    return result;
}
void SGWGInstallTransportPatches(void) {}
NSArray *SGWGNativeReportLines(void) { return @[]; }
NSArray *SGWGTransportReportLines(void) { return @[]; }
NSArray *SGWGScanTransportClasses(void) { return @[]; }
NSArray *SGWGAdmissionReportLines(void) { return @[]; }
void SGWGNotifyRecovery(void) { notices++; CHECK(!SGWGReady()); }
int SGWGRebind(void) { rebinds++; return 0; }
static void unexpected(void) { fputs("FAIL unexpected profile/Go status access\n", stderr); exit(1); }
char *SGWGInspect(char *text) { unexpected(); return NULL; }
int SGWGStart(char *text, char *user, char *pass, int fd, int port) {
    if (!getenv("SGWG_TEST_DELAY_ADMISSION")) unexpected();
    struct sockaddr_in address;
    socklen_t size = sizeof(address);
    CHECK(getsockname(fd, (struct sockaddr *)&address, &size) == 0);
    CHECK(ntohs(address.sin_port) == port && port == sessionPort);
    close(fd);
    EngineChanged(SGWGEngineAvailable);
    return port;
}
char *SGWGStatus(void) { unexpected(); return NULL; }
char *SGWGLookup(char *host) { unexpected(); return NULL; }
char *SGWGResolve(char *host) { unexpected(); return NULL; }
char *SGWGRedact(char *text) { unexpected(); return NULL; }
void SGWGFree(char *text) { free(text); }
void SGWGSetStateCallback(uintptr_t callback) { if (!getenv("SGWG_TEST_DELAY_ADMISSION")) unexpected(); }

static void drain(void) { dispatch_sync(gQueue, ^{}); }

static void checkLyricsRouting(void) {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    id saved = [defaults objectForKey:@"spotifyglass.wireguard"];
    NSArray *genius = @[@"https://genius.com/api/search/song?q=test", @"https://genius.com/songs/123/embed.js"];
    NSArray *other = @[@"https://lrclib.net/api/get", @"https://pipe.deezer.com/api",
        @"https://lrc.red/s/test.ttml", @"https://m.bugs.co.kr/api/getSearchList",
        @"https://lyrics-api.binimum.org/", @"https://music.bugs.co.kr/player/lyrics/T/123",
        @"https://auth.deezer.com/login/arl", @"https://api.deezer.com/search",
        @"https://www.genie.co.kr/search/searchMain", @"https://dn.genie.co.kr/app/purchase/get_msl.asp",
        @"https://krcs.kugou.com/search", @"https://lyrics.kugou.com/download",
        @"https://lyricsplus.binimum.org/v2/lyrics/get", @"https://lyricsplus.prjktla.my.id/v2/lyrics/get",
        @"https://apic-appmobile.musixmatch.com/ws/1.1/", @"https://music.163.com/api/",
        @"https://p1.petitlyrics.com/api/GetPetitLyricsData.php", @"https://u.y.qq.com/cgi-bin/musicu.fcg",
        @"https://api.spicylyrics.org/v1/lyrics/", @"https://unison.boidu.dev/lyrics"];
    NSArray *protected = @[@"https://spclient.wg.spotify.com/color-lyrics/v2/track/123",
        @"https://api.spotify.com/", @"https://example.com/", @"https://genius.com.evil.tld/",
        @"https://xgenius.com/", @"https://www.genius.com/", @"https://genius.com./",
        @"http://genius.com/api/search/song", @"https://127.0.0.1/", @"https://localhost/",
        @"https://developers.spicylyrics.org/dashboard", @"https://y.qq.com/",
        @"https://unknown-lyrics-files.example/song.ttml", @"https://user:pass@genius.com/",
        @"https://genius.com:444/"];
    Class direct = NSClassFromString(@"SGWGLyricsDirectProtocol");
    for (NSInteger mode = 0; mode <= 2; mode++) {
        [defaults setObject:@{@"lyricsRoute": @(mode)} forKey:@"spotifyglass.wireguard"];
        for (NSNumber *ready in @[@NO, @YES]) {
            gReady = ready.boolValue; gEngineReady = ready.boolValue;
            for (NSString *url in [genius arrayByAddingObjectsFromArray:[other arrayByAddingObjectsFromArray:protected]]) {
                NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]];
                CHECK(![direct canInitWithRequest:request]);
                CHECK([SGWGUnavailableProtocol canInitWithRequest:request] == !ready.boolValue);
                SGLyricsMarkRequest(request);
                BOOL expected = (mode == 1 && [genius containsObject:url]) ||
                                (mode == 2 && ![protected containsObject:url]);
                CHECK([direct canInitWithRequest:request] == expected);
                CHECK([SGWGUnavailableProtocol canInitWithRequest:request] == (!ready.boolValue && !expected));
                CHECK([SGWGBlockedURLProtocol canInitWithRequest:request] == !expected);
            }
        }
    }
    CHECK(SGLyricsBiniFileURLAllowed([NSURL URLWithString:@"https://lrc.red/s/test.ttml"]));
    CHECK(!SGLyricsBiniFileURLAllowed([NSURL URLWithString:@"https://api.deezer.com/test.ttml"]));
    CHECK(!SGLyricsBiniFileURLAllowed([NSURL URLWithString:@"https://lrc.red.evil.tld/test.ttml"]));
    NSMutableURLRequest *changed = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"https://genius.com/api/search/song"]];
    SGLyricsMarkRequest(changed);
    changed.URL = [NSURL URLWithString:@"https://api.deezer.com/search"];
    CHECK(![direct canInitWithRequest:changed]);
    if (saved) [defaults setObject:saved forKey:@"spotifyglass.wireguard"];
    else [defaults removeObjectForKey:@"spotifyglass.wireguard"];
    puts("PASS lyrics modes, exact HTTPS hosts, lookalikes, Spotify isolation and unavailable guards");
}

@interface LyricsOriginFixture : NSURLProtocol
@end
@implementation LyricsOriginFixture
+ (BOOL)canInitWithRequest:(NSURLRequest *)request { return YES; }
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request { return request; }
- (void)startLoading {
    if ([self.request.URL.path isEqualToString:@"/redirect"]) {
        NSURLRequest *next = [NSURLRequest requestWithURL:[NSURL URLWithString:@"https://api.spotify.com/redirect-target"]];
        NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:self.request.URL statusCode:302 HTTPVersion:@"HTTP/1.1" headerFields:@{@"Location": next.URL.absoluteString}];
        [self.client URLProtocol:self wasRedirectedToRequest:next redirectResponse:response];
    } else {
        NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:self.request.URL statusCode:200 HTTPVersion:@"HTTP/1.1" headerFields:@{}];
        [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
        [self.client URLProtocol:self didLoadData:[@"direct origin" dataUsingEncoding:NSUTF8StringEncoding]];
        [self.client URLProtocolDidFinishLoading:self];
    }
}
- (void)stopLoading {}
@end

static id (*fixtureSessionPredecessor)(id, SEL, id, id, id);
static id fixtureSession(id receiver, SEL selector, NSURLSessionConfiguration *config, id delegate, id queue) {
    if (objc_getAssociatedObject(config, &kLyricsDirectConfiguration)) {
        CHECK(config.connectionProxyDictionary.count == 0);
        CHECK([((id (*)(id, SEL))objc_msgSend)(config, sProxyConfigurations) count] == 0);
        config.protocolClasses = @[LyricsOriginFixture.class];
    }
    return fixtureSessionPredecessor(receiver, selector, config, delegate, queue);
}

static void checkLyricsSessions(void) {
    CHECK(InstallSessionHooks());
    fixtureSessionPredecessor = origSessionDelegate;
    origSessionDelegate = fixtureSession;
    gBlockAll = YES; gReady = NO; gEngineReady = NO;
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    id saved = [defaults objectForKey:@"spotifyglass.wireguard"];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:NSURLSessionConfiguration.ephemeralSessionConfiguration];
    // One existing session, changed preferences: test selection and forwarding,
    // not just the matcher. Only the external origin is replaced.
    for (NSArray *example in @[
        @[@0, @"https://genius.com/api/search/song", @NO],
        @[@1, @"https://genius.com/api/search/song", @YES],
        @[@1, @"https://genius.com/songs/123/embed.js", @YES],
        @[@1, @"https://lrclib.net/api/get", @NO],
        @[@2, @"https://lrclib.net/api/get", @YES],
        @[@2, @"https://api.spotify.com/", @NO],
        @[@2, @"https://genius.com.evil.tld/", @NO],
        @[@1, @"https://genius.com/redirect", @NO],
        @[@0, @"https://genius.com/api/search/song", @NO],
    ]) {
        SGWGSetSettingLyricsRoute([example[0] integerValue]);
        dispatch_semaphore_t done = dispatch_semaphore_create(0);
        __block NSData *body; __block NSError *failure;
        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:example[1]] cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:5];
        SGLyricsMarkRequest(request);
        [[session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            body = data; failure = error; dispatch_semaphore_signal(done);
        }] resume];
        CHECK(dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)) == 0);
        if ([example[2] boolValue]) {
            CHECK(!failure && [[[NSString alloc] initWithData:body encoding:NSUTF8StringEncoding] isEqualToString:@"direct origin"]);
        } else {
            CHECK(failure.code == NSURLErrorNotConnectedToInternet && body.length == 0);
        }
    }
    [session invalidateAndCancel];
    origSessionDelegate = fixtureSessionPredecessor;
    if (saved) [defaults setObject:saved forKey:@"spotifyglass.wireguard"];
    else [defaults removeObjectForKey:@"spotifyglass.wireguard"];
    puts("PASS existing session switches routes live; unavailable direct forwarding; redirected Spotify remains blocked");
}

static void checkStaleRefresh(void) {
    for (NSNumber *event in @[@1, @2, @0]) {
        patches = YES;
        EngineChanged(1);
        drain();
        CHECK(SGWGReady());
        admissionEntered = dispatch_semaphore_create(0);
        admissionContinue = dispatch_semaphore_create(0);
        dispatch_semaphore_t refreshed = dispatch_semaphore_create(0);
        dispatch_semaphore_t finish = dispatch_semaphore_create(0);
        dispatch_async(gQueue, ^{
            SGWGRefreshReadiness();
            dispatch_semaphore_signal(refreshed);
            // Inspect the old publication before any queued recovery can overwrite it.
            dispatch_semaphore_wait(finish, DISPATCH_TIME_FOREVER);
        });
        dispatch_semaphore_wait(admissionEntered, DISPATCH_TIME_FOREVER);
        EngineChanged(2);
        patches = NO;
        ImageChanged(NULL, 0);
        if (event.intValue != 2) EngineChanged(event.intValue);
        CHECK(!SGWGReady());
        dispatch_semaphore_signal(admissionContinue);
        dispatch_semaphore_wait(refreshed, DISPATCH_TIME_FOREVER);
        CHECK(!SGWGReady());
        admissionEntered = admissionContinue = nil;
        dispatch_semaphore_signal(finish);
        drain();
        CHECK(!SGWGReady());
        patches = YES;
        ImageChanged(NULL, 0);
        EngineChanged(1);
        drain();
        CHECK(SGWGReady());
    }
    puts("PASS in-flight guard validation cannot restore readiness across recovery, unavailable or stopped events");
}

int main(int argc, char **argv) {
    @autoreleasepool {
        CHECK(SGWGIsSupportedOS());
        if (argc == 2 && !strcmp(argv[1], "--delayed-admission")) {
            CHECK(!SGWGAdmissionReady() && !SGWGReady());
            realCreateSocks = pCreateSocks;
            pCreateSocks = recordSocksEndpoint;
            NSURLSession *early = NSURLSession.sharedSession;
            CHECK([[early.configuration valueForKey:@"proxyConfigurations"] count] == 1);
            CHECK(sessionPort > 1);
            sharedImageLoaded = true;
            StartEngine();
            drain();
            CHECK(SGWGReady() && NSURLSession.sharedSession == early);
            puts("PASS early shared session targets the same reserved port handed to the admitted engine");
            return 0;
        }
        if (argc == 2 && !strcmp(argv[1], "--external-proxy")) {
            CHECK([gKind isEqualToString:SGWGKindSOCKS5]);
            CHECK(gListenerFD == -1 && !gBlockAll && SGWGCurrentState() == SGWGStateExternalProxy);
            puts("PASS external proxy starts without reserving a loopback listener");
            return 0;
        }
        gActive = YES;
        gKind = SGWGKindWireGuard;
        gSessionGuards = YES;
        EngineChanged(1);
        drain();
        CHECK(SGWGReady() && SGWGCurrentState() == SGWGStateRunning);
        EngineChanged(3);
        drain();
        CHECK(SGWGReady() && notices == 0);

        // A blocked Go rebind must not delay revocation or the failure notice behind gQueue.
        dispatch_suspend(gQueue);
        EngineChanged(2);
        CHECK(!SGWGReady() && SGWGCurrentState() == SGWGStateFailed && notices == 1);
        dispatch_resume(gQueue);
        drain();
        SGWGRequestRebind(@"fixture recovery");
        drain();
        CHECK(rebinds == 1);
        EngineChanged(3);
        drain();
        CHECK(!SGWGReady() && notices == 1);
        EngineChanged(1);
        drain();
        CHECK(SGWGReady() && SGWGCurrentState() == SGWGStateRunning);
        patches = NO;
        EngineChanged(1);
        drain();
        CHECK(!SGWGReady());
        EngineChanged(0);
        drain();
        SGWGRequestRebind(@"stopped is not recoverable");
        drain();
        CHECK(!SGWGReady() && rebinds == 1);
        checkStaleRefresh();
        checkLyricsRouting();
        checkLyricsSessions();
        puts("PASS structural failure revokes readiness immediately, recovery restores guards, destination failure is informational");
    }
}
