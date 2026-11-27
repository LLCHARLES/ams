// Production Objective-C event/admission owner; Go and Spotify import admission are boundaries.
#import <unistd.h>
#import <errno.h>
#import <stdlib.h>
#import <Network/Network.h>
#import <Foundation/Foundation.h>
#import <Security/Security.h>
static BOOL keychainUnlocked;
static NSData *savedItem;
static OSStatus fixtureUpdate(CFDictionaryRef query, CFDictionaryRef attributes) {
    if (!getenv("SGWG_TEST_SAVE_PASSWORD") && !getenv("SGWG_TEST_IMPORT_PROFILE")) return errSecParam;
    savedItem = [(__bridge NSDictionary *)attributes objectForKey:(__bridge id)kSecValueData];
    return errSecSuccess;
}
static OSStatus fixtureItem(CFDictionaryRef query, CFTypeRef *result) {
    if (getenv("SGWG_TEST_SAVE_PASSWORD") || getenv("SGWG_TEST_IMPORT_PROFILE")) {
        NSData *data = savedItem;
        if (!data && getenv("SGWG_TEST_IMPORT_PROFILE")) data = [@"offline" dataUsingEncoding:NSUTF8StringEncoding];
        if (!data) return errSecItemNotFound;
        *result = CFBridgingRetain(data);
        return errSecSuccess;
    }
    if (!getenv("SGWG_TEST_LOCKED_PROXY")) return SecItemCopyMatching(query, result);
    NSDictionary *attributes = (__bridge NSDictionary *)query;
    if (![attributes[(__bridge id)kSecAttrAccount] isEqual:@"proxy-password"]) return errSecItemNotFound;
    if (!keychainUnlocked) return errSecInteractionNotAllowed;
    NSDictionary *entry = @{@"identity": @[@"socks5", @"127.0.0.1", @"1080", @"fixture"], @"password": @"unlock-test"};
    *result = CFBridgingRetain([NSJSONSerialization dataWithJSONObject:entry options:0 error:nil]);
    return errSecSuccess;
}
#define SecItemCopyMatching fixtureItem
#define SecItemUpdate fixtureUpdate
static BOOL clearedService;
static OSStatus fixtureDelete(CFDictionaryRef raw) {
    NSDictionary *query = (__bridge NSDictionary *)raw;
    if (![query[(__bridge id)kSecClass] isEqual:(__bridge id)kSecClassGenericPassword] ||
        ![query[(__bridge id)kSecAttrService] isEqual:@"Vitrine.WireGuard"]) return errSecParam;
    if (!query[(__bridge id)kSecAttrAccount]) clearedService = YES;
    return errSecSuccess;
}
#define SecItemDelete fixtureDelete
static dispatch_source_t recoveryTimer;
static dispatch_queue_t gQueue;
static dispatch_block_t tick;
static dispatch_time_t nextFire = DISPATCH_TIME_FOREVER;
static uint64_t repeat;
static dispatch_source_t fixtureSource(dispatch_source_type_t type, uintptr_t handle, unsigned long mask, dispatch_queue_t queue) {
    dispatch_source_t source = dispatch_source_create(type, handle, mask, queue);
    if (type == DISPATCH_SOURCE_TYPE_TIMER && queue == gQueue) recoveryTimer = source;
    return source;
}
static void fixtureTimer(dispatch_source_t source, dispatch_time_t first, uint64_t interval, uint64_t leeway) {
    if (source != recoveryTimer) {
        dispatch_source_set_timer(source, first, interval, leeway);
        return;
    }
    nextFire = first;
    repeat = interval;
}
// Advance to the next scheduled deadline without waiting for wall time.
static unsigned fireRecovery(void) {
    if (!tick || nextFire == DISPATCH_TIME_FOREVER) return 0;
    if (repeat == DISPATCH_TIME_FOREVER) nextFire = DISPATCH_TIME_FOREVER;
    tick();
    return 1;
}
static void fixtureHandler(dispatch_source_t source, dispatch_block_t handler) {
    if (source == recoveryTimer) tick = [handler copy];
    else dispatch_source_set_event_handler(source, handler);
}
#define dispatch_source_set_timer fixtureTimer
#define dispatch_source_create fixtureSource
#define dispatch_source_set_event_handler fixtureHandler
static int fixtureDup(int fd) {
    static int failed;
    if (getenv("SGWG_TEST_FD_LIMIT") && !failed++) { errno = EMFILE; return -1; }
    return dup(fd);
}
#define dup fixtureDup
// Path delivery is driven by the fixture, never by the Mac's actual Wi-Fi.
#define nw_path_monitor_start(monitor) ((void)(monitor))
#import <mach-o/dyld.h>
#import <stdatomic.h>
static atomic_uint nativeScans;
static unsigned scansAtRegistration;
static void (*registeredAdd)(const struct mach_header *, intptr_t);
static void (*registeredRemove)(const struct mach_header *, intptr_t);
static void registerImages(void (*callback)(const struct mach_header *, intptr_t)) {
    if (getenv("SGWG_TEST_REPLAY")) {
        registeredAdd = callback;
        scansAtRegistration = nativeScans;
        for (int i = 0; i < 600; i++) callback(NULL, 0);
    } else _dyld_register_func_for_add_image(callback);
}
#define _dyld_register_func_for_add_image registerImages
static void registerRemovals(void (*callback)(const struct mach_header *, intptr_t)) {
    if (getenv("SGWG_TEST_REPLAY")) registeredRemove = callback;
    else _dyld_register_func_for_remove_image(callback);
}
#define _dyld_register_func_for_remove_image registerRemovals
#import "Shared/WireGuard/SGWGCore.m"
#undef nw_path_monitor_start
#undef dispatch_source_set_timer
#undef dispatch_source_create
#undef dispatch_source_set_event_handler
#undef dup
#undef SecItemCopyMatching
#undef SecItemUpdate
#undef SecItemDelete

static unsigned notices, rebinds;
static BOOL presenterAvailable;
static dispatch_block_t presentedNotice;
static BOOL admitted = YES, patches = YES;
static atomic_bool sharedImageLoaded;
static atomic_uint starts, stops, transports, admissions;
static dispatch_semaphore_t handoff, releaseHandoff;
static dispatch_semaphore_t oldProfileRead, finishOldAttempt;
static int sessionPort;
static CreateSocksFn realCreateSocks;
static void *recordSocksEndpoint(void *endpoint) {
    sessionPort = nw_endpoint_get_port((__bridge nw_endpoint_t)endpoint);
    return realCreateSocks(endpoint);
}
static dispatch_semaphore_t admissionEntered, admissionContinue;
#define CHECK(value) do { if (!(value)) { fprintf(stderr, "FAIL readiness:%d %s\n", __LINE__, #value); exit(1); } } while (0)

BOOL SGWGInstallNativePatches(void) { ++nativeScans; return patches; }
BOOL SGWGCheckAdmission(BOOL *pendingImages) {
    ++admissions;
    BOOL ready = SGWGAdmissionReady();
    if (pendingImages) *pendingImages = !ready && !sharedImageLoaded && getenv("SGWG_TEST_DELAY_ADMISSION") != NULL;
    return ready;
}
BOOL SGWGAdmissionReady(void) {
    BOOL result = admitted && !getenv("SGWG_TEST_REFUSED") && (!getenv("SGWG_TEST_DELAY_ADMISSION") || sharedImageLoaded);
    if (admissionEntered) {
        dispatch_semaphore_signal(admissionEntered);
        dispatch_semaphore_wait(admissionContinue, DISPATCH_TIME_FOREVER);
    }
    return result;
}
void SGWGInstallTransportPatches(void) { ++transports; }
NSArray *SGWGNativeReportLines(void) { return @[]; }
NSArray *SGWGTransportReportLines(void) { return @[]; }
NSArray *SGWGScanTransportClasses(void) { return @[]; }
NSArray *SGWGAdmissionReportLines(void) { return @[]; }
void SGWGNotifyRecovery(void) {
    notices++;
    CHECK(!SGWGReady());
    if (presenterAvailable) {
        presentedNotice = SGWGRecoveryPresentationCompletion();
        CHECK(presentedNotice);
        presentedNotice();
    }
}
int SGWGRebind(void) { rebinds++; return 0; }
static void unexpected(void) { fputs("FAIL unexpected profile/Go status access\n", stderr); exit(1); }
char *SGWGInspect(char *text) {
    if (getenv("SGWG_TEST_IMPORT_PROFILE") && !strcmp(text, "working")) return strdup("{\"ok\":true}");
    unexpected(); return NULL;
}
enum SGWGStartResult SGWGStart(char *text, char *user, char *pass, int fd) {
    if (!getenv("SGWG_TEST_DELAY_ADMISSION")) unexpected();
    struct sockaddr_in address;
    socklen_t size = sizeof(address);
    CHECK(getsockname(fd, (struct sockaddr *)&address, &size) == 0);
    CHECK(ntohs(address.sin_port) == sessionPort && fd != gListenerFD);
    unsigned attempt = ++starts;
    if (getenv("SGWG_TEST_IMPORT_PROFILE"))
        CHECK(!strcmp(text, attempt == 1 ? "offline" : "working"));
    CHECK(!ProxyAdmitted());
    if (attempt == 1 && oldProfileRead) {
        dispatch_semaphore_signal(oldProfileRead);
        dispatch_semaphore_wait(finishOldAttempt, DISPATCH_TIME_FOREVER);
    }
    if ((attempt == 1 && !getenv("SGWG_TEST_FD_LIMIT") && !getenv("SGWG_TEST_OLD_SUCCEEDS")) || getenv("SGWG_TEST_INVALID")) {
        close(fd);
        return getenv("SGWG_TEST_INVALID") ? SGWGStartRefused : SGWGStartNetworkUnavailable;
    }
    CHECK(listen(fd, 1) == 0);
    close(fd);
    EngineChanged(SGWGEngineAvailable);
    dispatch_semaphore_signal(handoff);
    dispatch_semaphore_wait(releaseHandoff, DISPATCH_TIME_FOREVER);
    return SGWGStarted;
}
void SGWGStop(void) { ++stops; }
char *SGWGStatus(void) { unexpected(); return NULL; }
char *SGWGLookup(char *host) { unexpected(); return NULL; }
char *SGWGResolve(char *host) { unexpected(); return NULL; }
char *SGWGRedact(char *text) { unexpected(); return NULL; }
void SGWGFree(char *text) { free(text); }
void SGWGSetStateCallback(uintptr_t callback, uintptr_t gate) { if (!getenv("SGWG_TEST_DELAY_ADMISSION") || !gate) unexpected(); }

static void drain(void) { dispatch_sync(gQueue, ^{}); }

static void imageBurst(void) {
    for (int i = 0; i < 100; ++i) {
        registeredRemove(NULL, 0);
        registeredAdd(NULL, 0);
    }
}

static void checkImageBursts(void) {
    drain();
    CHECK(registeredAdd && registeredRemove && scansAtRegistration > 0);
    CHECK(!SGWGReady() && gAdmissionPending && !gBlockAll);
    sharedImageLoaded = true;
    registeredAdd(NULL, 0);
    dispatch_sync(gQueue, ^{
        CHECK(!SGWGReady() && !gAdmissionPending && !gBlockAll);
        CHECK(fireRecovery() == 1 && SGWGReady()); // start still pending, even without a rescan
    });

    unsigned before = nativeScans;
    dispatch_sync(gQueue, ^{
        registeredRemove(NULL, 0);
        CHECK(!SGWGReady());
        SGWGRefreshReadiness(); // independent refresh with an image worker already queued
        CHECK(SGWGReady());
        registeredAdd(NULL, 0);
        CHECK(!SGWGReady());
        imageBurst();
    });
    drain();
    CHECK(nativeScans == before + 2 && SGWGReady()); // one direct pass, one image pass

    before = nativeScans;
    admissionEntered = dispatch_semaphore_create(0);
    admissionContinue = dispatch_semaphore_create(0);
    dispatch_sync(gQueue, ^{ imageBurst(); CHECK(!SGWGReady()); });
    CHECK(!dispatch_semaphore_wait(admissionEntered, dispatch_time(DISPATCH_TIME_NOW, 3*NSEC_PER_SEC)));
    // Queue this observation ahead of any successor. Admission has already
    // sampled "present", but its generation is about to become stale.
    dispatch_async(gQueue, ^{
        CHECK(!SGWGReady() && nativeScans == before + 1);
        admissionEntered = admissionContinue = nil;
    });
    sharedImageLoaded = false;
    imageBurst();
    registeredRemove(NULL, 0);
    dispatch_semaphore_signal(admissionContinue);
    drain();
    CHECK(nativeScans == before + 2 && !SGWGReady() && gAdmissionPending && !gBlockAll);
    sharedImageLoaded = true;
    registeredAdd(NULL, 0);
    drain();
    CHECK(SGWGReady());
    admitted = NO;
    registeredAdd(NULL, 0);
    drain();
    CHECK(!SGWGReady() && gBlockAll && !gAdmissionPending);
    puts("PASS image bursts coalesce, stale pass cannot publish, missing target recovers, mismatch refuses");
}
static void checkPublishedSink(void) {
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    struct sockaddr_in addr = {.sin_len = sizeof(addr), .sin_family = AF_INET,
        .sin_port = htons(sessionPort), .sin_addr.s_addr = htonl(INADDR_LOOPBACK)};
    CHECK(fd >= 0 && bind(fd, (struct sockaddr *)&addr, sizeof(addr)) < 0 && errno == EADDRINUSE);
    struct timeval timeout = {.tv_sec = 2};
    CHECK(!setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout)));
    CHECK(!connect(fd, (struct sockaddr *)&addr, sizeof(addr)));
    char b;
    CHECK(read(fd, &b, 1) == 0);
    close(fd);
}
static void waitFor(BOOL (^predicate)(void)) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:3];
    while (deadline.timeIntervalSinceNow > 0) {
        __block BOOL ok;
        dispatch_sync(gQueue, ^{ ok = predicate(); });
        if (ok) return;
        usleep(1000);
    }
    CHECK(NO);
}

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
static unsigned directSessions;
static id fixtureSession(id receiver, SEL selector, NSURLSessionConfiguration *config, id delegate, id queue) {
    if (objc_getAssociatedObject(config, &kLyricsDirectConfiguration)) {
        directSessions++;
        CHECK(!config.URLCache && !config.HTTPCookieStorage && !config.URLCredentialStorage && !config.HTTPShouldSetCookies);
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
    CHECK(directSessions == 1);
    origSessionDelegate = fixtureSessionPredecessor;
    if (saved) [defaults setObject:saved forKey:@"spotifyglass.wireguard"];
    else [defaults removeObjectForKey:@"spotifyglass.wireguard"];
    puts("PASS existing session switches routes live; unavailable direct forwarding; redirected Spotify remains blocked");
}

static void checkStaleRefresh(void) {
    for (NSNumber *event in @[@1, @2, @0]) {
        patches = YES;
        gHandedOff = true;
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
        gHandedOff = true;
        EngineChanged(1);
        drain();
        CHECK(SGWGReady());
    }
    puts("PASS in-flight guard validation cannot restore readiness across recovery, unavailable or stopped events");
}

int main(int argc, char **argv) {
    @autoreleasepool {
        CHECK(SGWGIsSupportedOS());
        if (argc == 2 && !strcmp(argv[1], "--image-bursts")) {
            checkImageBursts();
            return 0;
        }
        if (argc == 2 && !strcmp(argv[1], "--clear-credentials")) {
            NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
            id previous = [defaults objectForKey:kDefaultsKey];
            [defaults setObject:@{@"enabled":@YES, @"kind":@"socks5", @"host":@"example.test"} forKey:kDefaultsKey];
            BOOL reset = SGWGSettingEnabled() && SGWGForgetAllCredentials() && clearedService && ![defaults objectForKey:kDefaultsKey] &&
                [SGWGSettingKind() isEqual:SGWGKindWireGuard] && !SGWGSettingEnabled();
            if (previous) [defaults setObject:previous forKey:kDefaultsKey];
            else [defaults removeObjectForKey:kDefaultsKey];
            CHECK(reset);
            puts("PASS service-wide credential deletion and unconfigured defaults");
            return 0;
        }
        if (argc == 2 && !strcmp(argv[1], "--delayed-admission")) {
            CHECK(!SGWGAdmissionReady() && !SGWGReady());
            realCreateSocks = pCreateSocks;
            pCreateSocks = recordSocksEndpoint;
            NSURLSession *early = NSURLSession.sharedSession;
            CHECK([[early.configuration valueForKey:@"proxyConfigurations"] count] == 1);
            CHECK(sessionPort > 1);
            handoff = dispatch_semaphore_create(0);
            releaseHandoff = dispatch_semaphore_create(0);
            if (getenv("SGWG_TEST_INFLIGHT_IMPORT")) {
                oldProfileRead = dispatch_semaphore_create(0);
                finishOldAttempt = dispatch_semaphore_create(0);
            }
            sharedImageLoaded = true;
            dispatch_async(gQueue, ^{
                PathUpdated(@"wifi", YES);
                // This attempt parks on failure: no backoff timer can satisfy
                // either the foreground-only or same-signature path check.
                gStartRetries = MaxStartRetries;
                StartEngine();
            });
            if (oldProfileRead) {
                CHECK(!dispatch_semaphore_wait(oldProfileRead, dispatch_time(DISPATCH_TIME_NOW, 2*NSEC_PER_SEC)));
                CHECK(SGWGCurrentState() == SGWGStateStarting && SGWGImportProfile(@"working", nil));
                drain();
                CHECK(gStarting && starts == 1);
                dispatch_semaphore_signal(finishOldAttempt);
            } else waitFor(^BOOL{ return !gStarting; });
            if (getenv("SGWG_TEST_INVALID")) {
                SGWGRequestRebind(@"fixture path");
                drain();
                CHECK(starts == 1 && gBlockAll && !SGWGReady());
                checkPublishedSink();
                puts("PASS invalid profile refuses existing configurations and never retries");
                return 0;
            }
            if (!oldProfileRead) {
                CHECK(gRetryStart && !SGWGReady() && gListenerFD >= 0);
                if (getenv("SGWG_TEST_IMPORT_PROFILE")) {
                    CHECK(SGWGCurrentState() == SGWGStateFailed);
                    CHECK(SGWGImportProfile(@"working", nil));
                } else if (getenv("SGWG_TEST_SAME_PATH")) {
                    dispatch_async(gQueue, ^{ PathUpdated(@"wifi", YES); });
                } else {
                    [NSNotificationCenter.defaultCenter postNotificationName:@"UIApplicationWillEnterForegroundNotification" object:nil];
                }
            }
            CHECK(!dispatch_semaphore_wait(handoff, dispatch_time(DISPATCH_TIME_NOW, 2*NSEC_PER_SEC)));
            drain();
            CHECK(!SGWGReady());
            if (getenv("SGWG_TEST_REFUSE_HANDOFF")) {
                admitted = NO;
                ImageChanged(NULL, 0);
                drain();
                CHECK(gBlockAll);
                checkPublishedSink();
            }
            dispatch_semaphore_signal(releaseHandoff);
            waitFor(^BOOL{ return !gStarting && (!gBlockAll || stops != 0); });
            CHECK(starts == ((getenv("SGWG_TEST_FD_LIMIT") || getenv("SGWG_TEST_OLD_SUCCEEDS")) ? 1 : 2) && NSURLSession.sharedSession == early);
            CHECK(SGWGReady() == admitted);
            if (admitted) {
                dispatch_sync(gQueue, ^{ CHECK(fireRecovery() == 0); });
                EngineChanged(SGWGEngineUnavailable);
                dispatch_sync(gQueue, ^{ CHECK(!SGWGReady() && fireRecovery() == 1); });
                EngineChanged(SGWGEngineAvailable);
                dispatch_sync(gQueue, ^{ CHECK(SGWGReady() && fireRecovery() == 0); });
                dispatch_sync(gQueue, ^{ RefuseListener(); });
                waitFor(^BOOL{ return stops != 0; });
            }
            checkPublishedSink();
            puts("PASS offline retry and delayed handoff respect current admission");
            return 0;
        }
        if (argc == 2 && !strcmp(argv[1], "--external-proxy")) {
            CHECK([gKind isEqualToString:SGWGKindSOCKS5]);
            NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
            id previousSettings = [defaults objectForKey:kDefaultsKey];
            if (getenv("SGWG_TEST_DELAY_ADMISSION")) {
                CHECK(!SGWGReady() && !transports);
                if (getenv("SGWG_TEST_LOCKED_PROXY") || getenv("SGWG_TEST_SAVE_PASSWORD")) {
                    [NSUserDefaults.standardUserDefaults setVolatileDomain:@{kDefaultsKey:
                        @{@"host": @"127.0.0.1", @"port": @"1080", @"username": @"fixture"}} forName:NSArgumentDomain];
                }
                sharedImageLoaded = true;
                dispatch_sync(gQueue, ^{ CHECK(fireRecovery() == 1); });
            }
            if (getenv("SGWG_TEST_REFUSED")) {
                drain();
                if (getenv("SGWG_TEST_REPLAY") && !getenv("SGWG_TEST_DELAY_ADMISSION")) {
                    CHECK(registeredAdd && scansAtRegistration > 0);
                    CHECK(nativeScans == scansAtRegistration + 1);
                }
                CHECK(SGWGActiveThisLaunch() && SGWGGuardsInstalled() && !SGWGReady());
                unsigned scans = nativeScans, checks = admissions;
                dispatch_sync(gQueue, ^{ fireRecovery(); });
                CHECK(nativeScans == scans && admissions == checks && !transports);
                CHECK(SGWGCurrentState() == SGWGStateBlocked);
                puts("PASS refused proxy stays guarded without periodic image scans");
                return 0;
            }
            if (getenv("SGWG_TEST_SAVE_PASSWORD")) {
                CHECK(SGWGCurrentState() == SGWGStateBlocked && !gBlockAll && gCredentialStatus == errSecItemNotFound);
                CHECK(!SGWGSaveConnection(gKind, @"127.0.0.1", @"1080", @"fixture", @"not\nvalid", nil));
                CHECK(!SGWGSaveConnection(gKind, @"127.0.0.1", @"1080", @"fixture",
                      [@"" stringByPaddingToLength:100 withString:@"한" startingAtIndex:0], nil));
                CHECK(SGWGSaveConnection(gKind, @"127.0.0.1", @"1080", @"fixture", @"replacement", nil));
                drain();
                if (previousSettings) [defaults setObject:previousSettings forKey:kDefaultsKey];
                else [defaults removeObjectForKey:kDefaultsKey];
                CHECK(SGWGReady() && gCredentialStatus == errSecSuccess && gProxyPass && !strcmp(gProxyPass, "replacement"));
            } else if (getenv("SGWG_TEST_LOCKED_PROXY")) {
                CHECK(SGWGCurrentState() == SGWGStateWaitingProfile && !SGWGReady() && !gProxyPass);
                CHECK(gCredentialStatus == errSecInteractionNotAllowed);
                keychainUnlocked = YES;
                if (getenv("SGWG_TEST_TIMER_UNLOCK"))
                    dispatch_sync(gQueue, ^{ CHECK(fireRecovery() == 1); });
                else
                    [NSNotificationCenter.defaultCenter postNotificationName:@"UIApplicationProtectedDataDidBecomeAvailable" object:nil];
                drain();
                CHECK(gCredentialStatus == errSecSuccess && gProxyUser && !strcmp(gProxyUser, "fixture"));
                CHECK(gProxyPass && !strcmp(gProxyPass, "unlock-test"));
            }
            CHECK(gListenerFD == -1 && SGWGReady() && SGWGCurrentState() == SGWGStateExternalProxy && transports == 1);
            if (getenv("SGWG_TEST_REPLAY")) {
                CHECK(registeredAdd && scansAtRegistration > 0);
                dispatch_sync(gQueue, ^{
                    registeredAdd(NULL, 0);
                    CHECK(!SGWGReady()); // refresh is queued behind this block
                });
                drain();
                CHECK(SGWGReady());
            }
            if (getenv("SGWG_TEST_ACTIVE_NOTICE")) {
                patches = NO;
                ImageChanged(NULL, 0);
                dispatch_sync(gQueue, ^{ for (unsigned i = 0; i < 4; i++) CHECK(fireRecovery()); });
                [NSNotificationCenter.defaultCenter postNotificationName:@"UIApplicationDidBecomeActiveNotification" object:nil];
                dispatch_sync(gQueue, ^{
                    for (unsigned i = 0; i < 2; i++) {
                        presenterAvailable = i == 1;
                        unsigned before = notices;
                        CHECK(nextFire <= dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC));
                        CHECK(fireRecovery() && notices == before + 1);
                    }
                    CHECK(presentedNotice);
                    unsigned shown = notices;
                    for (unsigned i = 0; i < 2; i++) {
                        CHECK(nextFire > dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC));
                        CHECK(fireRecovery() && notices == shown); // repair only
                    }
                    patches = YES;
                    SGWGRefreshReadiness();
                    CHECK(SGWGReady() && !fireRecovery());
                    patches = NO;
                    SGWGRefreshReadiness();
                    presentedNotice(); // late completion from the previous outage
                    CHECK(nextFire <= dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC));
                    CHECK(fireRecovery() && notices == shown + 1);
                    patches = YES;
                    SGWGRefreshReadiness();
                });
                puts("PASS presentation failure retries, shown outage has no notice wakes, new outage re-arms");
            }
            dispatch_sync(gQueue, ^{
                CHECK(fireRecovery() == 0);
                // A Foundation ABI mismatch cannot be repaired by native slot scans.
                gSessionGuards = NO;
                patches = NO;
                SGWGRefreshReadiness();
                patches = YES;
                unsigned scans = nativeScans;
                CHECK(fireRecovery() == 1);
                CHECK(nativeScans > scans && !SGWGGuardsInstalled());
                scans = nativeScans;
                fireRecovery();
                CHECK(nativeScans == scans && !SGWGReady());
            });
            puts("PASS external proxy start; periodic scans limited to incomplete native slots");
            return 0;
        }
        gActive = YES;
        CHECK(ReserveListener());
        RefuseListener();
        CHECK(gListenerFD < 0);
        gBlockAll = NO;
        gKind = SGWGKindWireGuard;
        gSessionGuards = YES;
        gHandedOff = true;
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
