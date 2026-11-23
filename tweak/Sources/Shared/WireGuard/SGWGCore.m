#import "SGWGCore.h"
#import "SGWGBridge.h"
#import "SGWGABI.h"
#import "Shared/LyricsSources/LyricsHosts.h"
#import <Network/Network.h>
#import <Security/Security.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <netinet/in.h>
#import <os/lock.h>
#import <stdatomic.h>
#import <stdlib.h>
#import <sys/socket.h>
#import <sys/utsname.h>
#import <unistd.h>
#import <arpa/inet.h>
#import <mach-o/dyld.h>

NSString *const SGWGVersion = @"1.0";

static NSString *const kDefaultsKey = @"spotifyglass.wireguard";
// Stable Keychain service for existing profiles, including deletion.
static NSString *const kKeychainService = @"Vitrine.WireGuard";
static NSString *const kKeychainAccount = @"profile";
static NSString *const kKeychainProxyAccount = @"proxy-password";

NSString *const SGWGKindWireGuard = @"wireguard";
NSString *const SGWGKindHTTP = @"http";
NSString *const SGWGKindHTTPS = @"https";
NSString *const SGWGKindSOCKS5 = @"socks5";

#pragma mark - State

static atomic_int gState = SGWGStateOff;
static atomic_bool gActive;       // armed before checking any capability
static atomic_bool gReady, gGuardsReady, gEngineReady;
static atomic_bool gEngineRecoverable;
static os_unfair_lock gReadinessLock = OS_UNFAIR_LOCK_INIT;
static uint64_t gReadinessGeneration;
static BOOL gEngineAvailable;    // unvalidated engine event, protected by gReadinessLock
static BOOL gSessionGuards;
static int gPort = -1;            // fixed before session hooks are installed
static int gListenerFD = -1;      // reserved socket handed to Go on start
static char gUser[33], gPass[33]; // per-launch random proxy credentials
static dispatch_queue_t gQueue;

static atomic_uint gConfigsProxied, gSessionsProxied, gBackgroundConfigs, gSharedReplaced;
static atomic_uint gProxyFailures, gBlockedRequests, gHTTP3Cleared, gDataURLFetches;
static atomic_uint gRebinds;

// External proxy mode (HTTP / HTTPS / SOCKS5) for this launch.
static NSString *gKind = @"";
static char gProxyHost[256], gProxyPort[8];
static char *gProxyUser, *gProxyPass; // strdup'ed, NULL when no authentication
static atomic_bool gBlockAll;
static atomic_int gCredentialStatus;

SGWGState SGWGCurrentState(void) { return (SGWGState)atomic_load(&gState); }
BOOL SGWGActiveThisLaunch(void) { return gActive; }
BOOL SGWGReady(void) {
    return atomic_load_explicit(&gReady, memory_order_acquire) && atomic_load(&gEngineReady);
}
BOOL SGWGGuardsInstalled(void) { return atomic_load(&gGuardsReady); }

NSString *SGWGStateDescription(SGWGState state) {
    switch (state) {
        case SGWGStateOff: return @"off";
        case SGWGStateUnsupported: return @"unsupported (iOS 17+ required)";
        case SGWGStateWaitingProfile: return @"waiting for profile (Keychain locked)";
        case SGWGStateStarting: return @"starting";
        case SGWGStateRunning: return @"running";
        case SGWGStateFailed: return @"failed (traffic blocked)";
        case SGWGStateExternalProxy: return @"external proxy applied";
        case SGWGStateBlocked: return @"configuration unusable (traffic blocked)";
    }
    return @"unknown";
}

#pragma mark - Settings

#ifdef SGWG_TESTING
static NSString *TestEnv(NSString *name) { return NSProcessInfo.processInfo.environment[name]; }
#endif

static NSDictionary *SettingsDict(void) {
    NSDictionary *d = [[NSUserDefaults standardUserDefaults] dictionaryForKey:kDefaultsKey];
    return [d isKindOfClass:NSDictionary.class] ? d : @{};
}

static void SetSetting(NSString *key, id value) {
    NSMutableDictionary *d = [SettingsDict() mutableCopy];
    d[key] = value;
    [[NSUserDefaults standardUserDefaults] setObject:d forKey:kDefaultsKey];
}

BOOL SGWGSettingEnabled(void) {
#ifdef SGWG_TESTING
    if (TestEnv(@"SGWG_TEST_ENABLED")) return [TestEnv(@"SGWG_TEST_ENABLED") boolValue];
#endif
    return [SettingsDict()[@"enabled"] boolValue];
}
void SGWGSetSettingEnabled(BOOL enabled) { SetSetting(@"enabled", @(enabled)); }

SGWGLyricsRoute SGWGSettingLyricsRoute(void) {
    NSInteger value = [SettingsDict()[@"lyricsRoute"] integerValue];
    return value == SGWGLyricsBlockedDirect || value == SGWGLyricsAllDirect ? value : SGWGLyricsThroughTunnel;
}
void SGWGSetSettingLyricsRoute(SGWGLyricsRoute route) { SetSetting(@"lyricsRoute", @(route)); }

BOOL SGWGLyricsRequestIsDirect(NSURLRequest *request) {
    if (!gActive || !SGLyricsRequestIsMarked(request)) return NO;
    NSURL *url = request.URL;
    NSSet *hosts;
    switch (SGWGSettingLyricsRoute()) {
        case SGWGLyricsBlockedDirect: hosts = SGLyricsBlockedProviderHosts(); break;
        case SGWGLyricsAllDirect: hosts = SGLyricsProviderHosts(); break;
        default: return NO;
    }
    return url.host && [hosts containsObject:url.host.lowercaseString];
}


NSString *SGWGSettingKind(void) {
#ifdef SGWG_TESTING
    if (TestEnv(@"SGWG_TEST_KIND")) return TestEnv(@"SGWG_TEST_KIND");
#endif
    NSString *kind = SettingsDict()[@"kind"];
    return [@[SGWGKindWireGuard, SGWGKindHTTP, SGWGKindHTTPS, SGWGKindSOCKS5] containsObject:kind ?: @""] ? kind : SGWGKindWireGuard;
}

NSDictionary *SGWGSettingExternalProxy(void) {
#ifdef SGWG_TESTING
    if (TestEnv(@"SGWG_TEST_HOST"))
        return @{@"host": TestEnv(@"SGWG_TEST_HOST"), @"port": TestEnv(@"SGWG_TEST_PORT") ?: @"", @"username": TestEnv(@"SGWG_TEST_USER") ?: @""};
#endif
    NSDictionary *d = SettingsDict();
    NSString *(^str)(NSString *) = ^NSString *(NSString *key) { return [d[key] isKindOfClass:NSString.class] ? d[key] : @""; };
    return @{@"host": str(@"host"), @"port": str(@"port"), @"username": str(@"username")};
}

NSString *SGWGActiveKind(void) { return gActive ? gKind : @""; }


NSString *SGWGAppVersion(void) {
#ifdef SGWG_TESTING
    if (TestEnv(@"SGWG_TEST_APP_VERSION")) return TestEnv(@"SGWG_TEST_APP_VERSION");
#endif
    id v = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    return [v isKindOfClass:NSString.class] ? v : @"?";
}

BOOL SGWGIsSupportedVersion(void) {
    NSString *version = SGWGAppVersion();
#define SGWG_TARGET(number, revision, mainUUID, sharedUUID) if ([version isEqualToString:@number]) return YES;
#include "SGWGTargets.inc"
#undef SGWG_TARGET
    return NO;
}

#pragma mark - iOS 17 proxy API (resolved at runtime; the repo builds with the iOS 16.5 SDK)

typedef void *(*CreateSocksFn)(void *endpoint);
typedef void *(*CreateHTTPConnectFn)(void *endpoint, void *tlsOptions);
static CreateHTTPConnectFn pCreateHTTPConnect;
typedef void (*SetUserPassFn)(void *config, const char *user, const char *pass);
typedef void (*SetFailoverFn)(void *config, bool allowed);
typedef bool (*GetFailoverFn)(void *config);
static CreateSocksFn pCreateSocks;
static SetUserPassFn pSetUserPass;
static SetFailoverFn pSetFailover;
static GetFailoverFn pGetFailover;
static SEL sSetProxyConfigurations, sProxyConfigurations;

BOOL SGWGIsSupportedOS(void) {
    static BOOL supported;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
#if TARGET_OS_OSX
        NSOperatingSystemVersion minimum = {14, 0, 0};
#else
        NSOperatingSystemVersion minimum = {17, 0, 0};
#endif
        // NSProcessInfo instead of @available: no compiler-rt dependency.
        if ([NSProcessInfo.processInfo isOperatingSystemAtLeastVersion:minimum]) {
            dlopen("/System/Library/Frameworks/Network.framework/Network", RTLD_LAZY);
            pCreateSocks = (CreateSocksFn)dlsym(RTLD_DEFAULT, "nw_proxy_config_create_socksv5");
            pCreateHTTPConnect = (CreateHTTPConnectFn)dlsym(RTLD_DEFAULT, "nw_proxy_config_create_http_connect");
            pSetUserPass = (SetUserPassFn)dlsym(RTLD_DEFAULT, "nw_proxy_config_set_username_and_password");
            pSetFailover = (SetFailoverFn)dlsym(RTLD_DEFAULT, "nw_proxy_config_set_failover_allowed");
            pGetFailover = (GetFailoverFn)dlsym(RTLD_DEFAULT, "nw_proxy_config_get_failover_allowed");
            sSetProxyConfigurations = NSSelectorFromString(@"setProxyConfigurations:");
            sProxyConfigurations = NSSelectorFromString(@"proxyConfigurations");
            supported = pCreateSocks && pCreateHTTPConnect && pSetUserPass && pSetFailover && pGetFailover &&
                [NSURLSessionConfiguration instancesRespondToSelector:sSetProxyConfigurations] &&
                [NSURLSessionConfiguration instancesRespondToSelector:sProxyConfigurations];
        }
    });
    return supported;
}

#pragma mark - Fail-closed protocol

// Used only if a configuration cannot be given the tunnel proxy. Non-exempt
// web requests fail instead of being sent directly.
@interface SGWGBlockedURLProtocol : NSURLProtocol
@end
@implementation SGWGBlockedURLProtocol
+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    NSString *scheme = request.URL.scheme.lowercaseString;
    return !SGWGLyricsRequestIsDirect(request) && [@[@"http", @"https", @"ws", @"wss"] containsObject:scheme ?: @""];
}
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request { return request; }
- (void)startLoading {
    atomic_fetch_add(&gBlockedRequests, 1);
    [self.client URLProtocol:self didFailWithError:[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorNotConnectedToInternet userInfo:nil]];
}
- (void)stopLoading {}
@end

// CFNetwork can exempt local IP literals from a session proxy. Refuse literal
// addresses and local hostnames instead of silently allowing those exemptions.
@interface SGWGLocalAddressProtocol : SGWGBlockedURLProtocol
@end
@implementation SGWGLocalAddressProtocol
+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    NSString *host = request.URL.host.lowercaseString;
    if (!host || ![super canInitWithRequest:request]) return NO;
    NSString *address = [host stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"[]"]];
    struct in_addr v4; struct in6_addr v6;
    return [host isEqualToString:@"localhost"] || [host hasSuffix:@".localhost"] || [host hasSuffix:@".local"] ||
        inet_pton(AF_INET, address.UTF8String, &v4) == 1 || inet_pton(AF_INET6, address.UTF8String, &v6) == 1;
}
@end

// Only construction of this protocol's private one-hop session skips the
// configuration hooks. No app configuration/request property can opt out.
static char kLyricsDirectConfiguration;
static NSURLSessionConfiguration *CopyRoutingConfiguration(NSURLSessionConfiguration *configuration) {
    NSURLSessionConfiguration *copy = [configuration copy];
    if (objc_getAssociatedObject(configuration, &kLyricsDirectConfiguration))
        objc_setAssociatedObject(copy, &kLyricsDirectConfiguration, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return copy;
}

@interface SGWGLyricsDirectProtocol : NSURLProtocol <NSURLSessionDataDelegate>
@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, strong) NSURLSessionDataTask *task;
@property (nonatomic) BOOL stopped;
@end
@implementation SGWGLyricsDirectProtocol
+ (BOOL)canInitWithRequest:(NSURLRequest *)request { return SGWGLyricsRequestIsDirect(request); }
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request { return request; }
- (void)startLoading {
    @synchronized (self) {
        if (self.stopped) return;
        // A preference change between selection and start may revoke permission.
        if (!SGWGLyricsRequestIsDirect(self.request)) {
            [self.client URLProtocol:self didFailWithError:[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCancelled userInfo:nil]];
            return;
        }
            NSURLSessionConfiguration *config = [NSURLSessionConfiguration ephemeralSessionConfiguration];
            objc_setAssociatedObject(config, &kLyricsDirectConfiguration, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            config.connectionProxyDictionary = @{};
            config.HTTPCookieStorage = nil;
            config.URLCredentialStorage = nil;
            config.URLCache = nil;
            config.HTTPShouldSetCookies = NO;
            config.timeoutIntervalForRequest = self.request.timeoutInterval;
            config.timeoutIntervalForResource = self.request.timeoutInterval;
            if (sSetProxyConfigurations)
                ((void (*)(id, SEL, id))objc_msgSend)(config, sSetProxyConfigurations, @[]);
            config.protocolClasses = @[];
            self.session = [NSURLSession sessionWithConfiguration:config delegate:self delegateQueue:nil];
        self.task = [self.session dataTaskWithRequest:self.request];
        [self.task resume];
    }
}
- (void)stopLoading {
    @synchronized (self) {
        self.stopped = YES;
        [self.task cancel];
        [self.session invalidateAndCancel];
        self.task = nil;
        self.session = nil;
    }
}
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task
 didReceiveResponse:(NSURLResponse *)response completionHandler:(void (^)(NSURLSessionResponseDisposition))completion {
    @synchronized (self) {
        if (!self.stopped) [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
        completion(self.stopped ? NSURLSessionResponseCancel : NSURLSessionResponseAllow);
    }
}
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveData:(NSData *)data {
    @synchronized (self) {
        if (!self.stopped) [self.client URLProtocol:self didLoadData:data];
    }
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task
 willPerformHTTPRedirection:(NSHTTPURLResponse *)response newRequest:(NSURLRequest *)request
 completionHandler:(void (^)(NSURLRequest *))completion {
    @synchronized (self) {
        // Never follow a redirect in the direct session: the original session
        // and its delegate must decide, then guards classify the new URL again.
        completion(nil);
        NSMutableURLRequest *redirect = [request mutableCopy];
        SGLyricsMarkRequest(redirect);
        if (!self.stopped) [self.client URLProtocol:self wasRedirectedToRequest:redirect redirectResponse:response];
        [self stopLoading];
    }
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    @synchronized (self) {
        if (!self.stopped) {
            if (error) [self.client URLProtocol:self didFailWithError:error];
            else [self.client URLProtocolDidFinishLoading:self];
        }
        [self stopLoading];
    }
}
@end

static void BlockConfiguration(NSURLSessionConfiguration *config) {
    atomic_fetch_add(&gProxyFailures, 1);
    NSArray *classes = config.protocolClasses ?: @[];
    if (![classes containsObject:SGWGBlockedURLProtocol.class])
        config.protocolClasses = [@[SGWGBlockedURLProtocol.class] arrayByAddingObjectsFromArray:classes];
}

// One nw_proxy_config for the mode of this launch. NULL means "block".
static id CreateProxyConfig(void) {
    if (!SGWGIsSupportedOS()) return nil;
    // WebSocket tasks do not use NSURLProtocol. Give an invalid configuration
    // a real, fail-closed proxy too, so those tasks cannot use a direct route.
    if (gBlockAll || (![gKind isEqualToString:SGWGKindWireGuard] && !atomic_load(&gEngineReady))) {
        nw_endpoint_t endpoint = nw_endpoint_create_host("127.0.0.1", "1");
        return endpoint ? (__bridge_transfer id)pCreateSocks((__bridge void *)endpoint) : nil;
    }
    if ([gKind isEqualToString:SGWGKindWireGuard]) {
        char port[8];
        snprintf(port, sizeof(port), "%d", gPort);
        nw_endpoint_t endpoint = nw_endpoint_create_host("127.0.0.1", port);
        id proxy = endpoint ? (__bridge_transfer id)pCreateSocks((__bridge void *)endpoint) : nil;
        if (proxy) pSetUserPass((__bridge void *)proxy, gUser, gPass);
        return proxy;
    }
    nw_endpoint_t endpoint = nw_endpoint_create_host(gProxyHost, gProxyPort);
    if (!endpoint) return nil;
    id proxy = nil;
    if ([gKind isEqualToString:SGWGKindSOCKS5]) {
        proxy = (__bridge_transfer id)pCreateSocks((__bridge void *)endpoint);
    } else {
        // HTTPS: TLS to the proxy itself, validated against the system trust store.
        nw_protocol_options_t tls = [gKind isEqualToString:SGWGKindHTTPS] ? nw_tls_create_options() : nil;
        proxy = (__bridge_transfer id)pCreateHTTPConnect((__bridge void *)endpoint, (__bridge void *)tls);
    }
    if (proxy && gProxyUser) pSetUserPass((__bridge void *)proxy, gProxyUser, gProxyPass);
    return proxy;
}

id SGWGCreateNativeProxyConfig(void) {
    id proxy = SGWGReady() ? CreateProxyConfig() : nil;
    if (proxy) pSetFailover((__bridge void *)proxy, false);
    return proxy;
}

@interface SGWGUnavailableProtocol : SGWGBlockedURLProtocol
@end
@implementation SGWGUnavailableProtocol
+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    return !SGWGReady() && [super canInitWithRequest:request];
}
@end

static void ApplyProxy(NSURLSessionConfiguration *config) {
    if (objc_getAssociatedObject(config, &kLyricsDirectConfiguration) || !gActive || ![config isKindOfClass:NSURLSessionConfiguration.class]) return;
    NSArray *classes = config.protocolClasses ?: @[];
    if (![classes containsObject:SGWGLyricsDirectProtocol.class])
        classes = [@[SGWGLyricsDirectProtocol.class] arrayByAddingObjectsFromArray:classes];
    if (![classes containsObject:SGWGUnavailableProtocol.class])
        classes = [@[SGWGUnavailableProtocol.class] arrayByAddingObjectsFromArray:classes];
    config.protocolClasses = classes;
    if (![classes containsObject:SGWGLocalAddressProtocol.class])
        config.protocolClasses = [@[SGWGLocalAddressProtocol.class] arrayByAddingObjectsFromArray:classes];
    @try {
        id proxy = CreateProxyConfig();
        if (!proxy) {
            BlockConfiguration(config);
            return;
        }
        pSetFailover((__bridge void *)proxy, false);
        config.connectionProxyDictionary = nil;
        ((void (*)(id, SEL, id))objc_msgSend)(config, sSetProxyConfigurations, @[proxy]);
        atomic_fetch_add(&gConfigsProxied, 1);
    } @catch (NSException *exception) {
        BlockConfiguration(config);
    }
}

#pragma mark - Hooks

static IMP ReplaceMethod(Class cls, SEL sel, IMP replacement, const char *result, NSArray<NSString *> *arguments) {
    Method method = class_getInstanceMethod(cls, sel);
    if (!SGWGMethodMatches(method, result, arguments)) return NULL;
    IMP original = method_getImplementation(method);
    // class_addMethod first so an inherited implementation is not modified for
    // unrelated superclasses.
    if (!class_addMethod(cls, sel, replacement, method_getTypeEncoding(method)))
        original = method_setImplementation(class_getInstanceMethod(cls, sel), replacement);
    return original;
}

static id (*origDefault)(id, SEL);
static id (*origEphemeral)(id, SEL);
static id (*origBackground)(id, SEL, id);
static id (*origSession)(id, SEL, id);
static id (*origSessionDelegate)(id, SEL, id, id, id);
static id (*origShared)(id, SEL);
static void (*origSetHTTP3)(id, SEL, BOOL);
static BOOL (*origGetHTTP3)(id, SEL);
static id (*origDataURL)(id, SEL, id);
static id (*origDataURLOptions)(id, SEL, id, NSUInteger, NSError **);

static id HookDefault(id self, SEL _cmd) {
    NSURLSessionConfiguration *c = origDefault(self, _cmd);
    ApplyProxy(c);
    return c;
}
static id HookEphemeral(id self, SEL _cmd) {
    NSURLSessionConfiguration *c = origEphemeral(self, _cmd);
    ApplyProxy(c);
    return c;
}
static id HookBackground(id self, SEL _cmd, id identifier) {
    NSURLSessionConfiguration *c = origBackground(self, _cmd, identifier);
    atomic_fetch_add(&gBackgroundConfigs, 1);
    ApplyProxy(c);
    return c;
}
// The session constructors re-apply the proxy to a copy, so later changes to a
// configuration object by the app cannot remove it.
static id HookSession(id self, SEL _cmd, NSURLSessionConfiguration *config) {
    NSURLSessionConfiguration *copy = CopyRoutingConfiguration(config);
    ApplyProxy(copy);
    atomic_fetch_add(&gSessionsProxied, 1);
    return origSession(self, _cmd, copy);
}
static id HookSessionDelegate(id self, SEL _cmd, NSURLSessionConfiguration *config, id delegate, id queue) {
    NSURLSessionConfiguration *copy = CopyRoutingConfiguration(config);
    ApplyProxy(copy);
    atomic_fetch_add(&gSessionsProxied, 1);
    return origSessionDelegate(self, _cmd, copy, delegate, queue);
}
static id HookShared(id self, SEL _cmd) {
    static NSURLSession *session;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        session = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]];
        atomic_fetch_add(&gSharedReplaced, 1);
    });
    return session;
}
// The local SOCKS5 proxy carries TCP only; never ask URLSession to assume QUIC.
static void HookSetHTTP3(id self, SEL _cmd, BOOL value) {
    if (value) atomic_fetch_add(&gHTTP3Cleared, 1);
    origSetHTTP3(self, _cmd, NO);
}
static BOOL HookGetHTTP3(id self, SEL _cmd) { return NO; }

static BOOL IsWebURL(id url) {
    if (![url isKindOfClass:NSURL.class]) return NO;
    NSString *scheme = [url scheme].lowercaseString;
    return [scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"];
}

// -[NSData dataWithContentsOfURL:] loads web URLs on a private Foundation path.
// Some callers use it for manifests and cover art, so route it through
// a tunnelled session instead.
static NSData *TunnelFetch(NSURL *url, NSError **outError) {
    // Synchronous Foundation I/O must never turn a UI caller into a tunnel
    // startup wait. Background callers have one eight-second terminal deadline.
    if (!SGWGReady() || NSThread.isMainThread) {
        if (outError) *outError = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorNotConnectedToInternet userInfo:nil];
        return nil;
    }
    static const NSTimeInterval timeoutSeconds = 8;
    static NSURLSession *session;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSURLSessionConfiguration *c = [NSURLSessionConfiguration defaultSessionConfiguration];
        c.timeoutIntervalForRequest = timeoutSeconds;
        c.timeoutIntervalForResource = timeoutSeconds;
        NSOperationQueue *queue = [NSOperationQueue new];
        queue.maxConcurrentOperationCount = 4;
        session = [NSURLSession sessionWithConfiguration:c delegate:nil delegateQueue:queue];
    });
    atomic_fetch_add(&gDataURLFetches, 1);
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    __block NSData *result;
    __block NSError *failure;
    __block BOOL terminal = NO;
    NSObject *lock = [NSObject new];
    NSURLSessionDataTask *task = [session dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        @synchronized (lock) {
            if (terminal) return;
            terminal = YES;
            NSInteger status = [response isKindOfClass:NSHTTPURLResponse.class] ? [(NSHTTPURLResponse *)response statusCode] : 0;
            if (!error && status >= 200 && status < 300) result = data ?: [NSData data];
            else failure = error ?: [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorBadServerResponse userInfo:nil];
        }
        dispatch_semaphore_signal(done);
    }];
    [task resume];
    if (dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeoutSeconds * NSEC_PER_SEC)))) {
        @synchronized (lock) {
            if (!terminal) {
                terminal = YES;
                failure = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorTimedOut userInfo:nil];
            }
        }
        [task cancel];
    }
    @synchronized (lock) {
        if (!result && outError) *outError = failure;
        return result;
    }
}

static id MutableIfNeeded(id cls, NSData *data) {
    if (!data) return nil;
    return [cls isSubclassOfClass:NSMutableData.class] ? [data mutableCopy] : data;
}
static id HookDataURL(id self, SEL _cmd, id url) {
    if (!IsWebURL(url)) return origDataURL(self, _cmd, url);
    return MutableIfNeeded(self, TunnelFetch(url, NULL));
}
static id HookDataURLOptions(id self, SEL _cmd, id url, NSUInteger options, NSError **error) {
    if (!IsWebURL(url)) return origDataURLOptions(self, _cmd, url, options, error);
    return MutableIfNeeded(self, TunnelFetch(url, error));
}

static BOOL InstallInitializers(void) {
    BOOL valid = YES;
    SEL sessionInit = NSSelectorFromString(@"initWithConfiguration:delegate:delegateQueue:delegateDispatchQueue:");
    for (NSString *name in @[@"NSURLSession", @"__NSURLSessionLocal"]) {
        Class cls = NSClassFromString(name);
        Method method = class_getInstanceMethod(cls, sessionInit);
        if (!SGWGMethodMatches(method, "@", @[@"@", @"@", @"@", @"@"])) { valid = NO; continue; }
        void *(*original)(void *, SEL, id, id, id, id) = (void *)method_getImplementation(method);
        IMP replacement = imp_implementationWithBlock(^void *(void *receiver, NSURLSessionConfiguration *configuration,
                                                             id delegate, id queue, id dispatchQueue) {
            NSURLSessionConfiguration *copy = CopyRoutingConfiguration(configuration);
            ApplyProxy(copy);
            return original(receiver, sessionInit, copy, delegate, queue, dispatchQueue);
        });
        if (!ReplaceMethod(cls, sessionInit, replacement, "@", @[@"@", @"@", @"@", @"@"])) valid = NO;
    }
    const uint8_t byte = 0;
    NSArray *instances = @[[NSData alloc], [NSMutableData alloc], [NSData data],
        [NSData dataWithBytes:&byte length:1], [NSMutableData data]];
    NSMutableSet *classes = [NSMutableSet setWithObjects:NSData.class, NSMutableData.class, nil];
    for (id instance in instances) [classes addObject:object_getClass(instance)];
    for (Class cls in classes) {
        for (NSNumber *options in @[@NO, @YES]) {
            SEL selector = options.boolValue ? @selector(initWithContentsOfURL:options:error:) : @selector(initWithContentsOfURL:);
            NSArray *arguments = options.boolValue ? @[@"@", @(@encode(NSUInteger)), @"^@"] : @[@"@"];
            Method method = class_getInstanceMethod(cls, selector);
            if (!SGWGMethodMatches(method, "@", arguments)) { valid = NO; continue; }
            IMP original = method_getImplementation(method), replacement;
            if (options.boolValue) {
                replacement = imp_implementationWithBlock(^void *(void *receiver, NSURL *url, NSUInteger flags, NSError **error) {
                    if (!IsWebURL(url)) return ((void *(*)(void *, SEL, id, NSUInteger, NSError **))original)(receiver, selector, url, flags, error);
                    id consumed = CFBridgingRelease(receiver);
                    NSData *data = TunnelFetch(url, error);
                    id result = [consumed isKindOfClass:NSMutableData.class] ? [data mutableCopy] : data;
                    return (void *)CFBridgingRetain(result);
                });
            } else {
                replacement = imp_implementationWithBlock(^void *(void *receiver, NSURL *url) {
                    if (!IsWebURL(url)) return ((void *(*)(void *, SEL, id))original)(receiver, selector, url);
                    id consumed = CFBridgingRelease(receiver);
                    NSData *data = TunnelFetch(url, NULL);
                    id result = [consumed isKindOfClass:NSMutableData.class] ? [data mutableCopy] : data;
                    return (void *)CFBridgingRetain(result);
                });
            }
            if (!ReplaceMethod(cls, selector, replacement, "@", arguments)) valid = NO;
        }
    }
    return valid;
}

static BOOL InstallSessionHooks(void) {
    Class configMeta = object_getClass(NSURLSessionConfiguration.class);
    Class sessionMeta = object_getClass(NSURLSession.class);
    origDefault = (void *)ReplaceMethod(configMeta, @selector(defaultSessionConfiguration), (IMP)HookDefault, "@", @[]);
    origEphemeral = (void *)ReplaceMethod(configMeta, @selector(ephemeralSessionConfiguration), (IMP)HookEphemeral, "@", @[]);
    origBackground = (void *)ReplaceMethod(configMeta, @selector(backgroundSessionConfigurationWithIdentifier:), (IMP)HookBackground, "@", @[@"@"]);
    origSession = (void *)ReplaceMethod(sessionMeta, @selector(sessionWithConfiguration:), (IMP)HookSession, "@", @[@"@"]);
    origSessionDelegate = (void *)ReplaceMethod(sessionMeta, @selector(sessionWithConfiguration:delegate:delegateQueue:), (IMP)HookSessionDelegate, "@", @[@"@", @"@", @"@"]);
    origShared = (void *)ReplaceMethod(sessionMeta, @selector(sharedSession), (IMP)HookShared, "@", @[]);

    SEL setHTTP3 = NSSelectorFromString(@"setAssumesHTTP3Capable:");
    SEL getHTTP3 = NSSelectorFromString(@"assumesHTTP3Capable");
    Method m = class_getInstanceMethod(NSMutableURLRequest.class, setHTTP3);
    BOOL http3Valid = !m || SGWGMethodMatches(m, "v", @[@(@encode(BOOL))]);
    if (m && http3Valid)
        origSetHTTP3 = (void *)ReplaceMethod(NSMutableURLRequest.class, setHTTP3, (IMP)HookSetHTTP3, "v", @[@(@encode(BOOL))]);
    m = class_getInstanceMethod(NSURLRequest.class, getHTTP3);
    http3Valid &= !m || SGWGMethodMatches(m, @encode(BOOL), @[]);
    if (m && http3Valid)
        origGetHTTP3 = (void *)ReplaceMethod(NSURLRequest.class, getHTTP3, (IMP)HookGetHTTP3, @encode(BOOL), @[]);

    Class dataMeta = object_getClass(NSData.class);
    origDataURL = (void *)ReplaceMethod(dataMeta, @selector(dataWithContentsOfURL:), (IMP)HookDataURL, "@", @[@"@"]);
    origDataURLOptions = (void *)ReplaceMethod(dataMeta, @selector(dataWithContentsOfURL:options:error:), (IMP)HookDataURLOptions, "@", @[@"@", @(@encode(NSUInteger)), @"^@"]);
    BOOL initializers = InstallInitializers();
    return origDefault && origEphemeral && origBackground && origSession && origSessionDelegate && origShared &&
        origDataURL && origDataURLOptions && http3Valid && initializers;
}

NSDictionary *SGWGProxyCounters(void) {
    return @{
        @"configs": @(atomic_load(&gConfigsProxied)),
        @"sessions": @(atomic_load(&gSessionsProxied)),
        @"backgroundConfigs": @(atomic_load(&gBackgroundConfigs)),
        @"sharedReplaced": @(atomic_load(&gSharedReplaced)),
        @"proxyFailures": @(atomic_load(&gProxyFailures)),
        @"blockedRequests": @(atomic_load(&gBlockedRequests)),
        @"http3Cleared": @(atomic_load(&gHTTP3Cleared)),
        @"dataURLFetches": @(atomic_load(&gDataURLFetches)),
        @"rebinds": @(atomic_load(&gRebinds)),
    };
}

#pragma mark - Keychain

static NSMutableDictionary *KeychainQueryFor(NSString *account) {
    return [@{(__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
              (__bridge id)kSecAttrService: kKeychainService,
              (__bridge id)kSecAttrAccount: account} mutableCopy];
}
static NSMutableDictionary *KeychainQuery(void) { return KeychainQueryFor(kKeychainAccount); }

static OSStatus KeychainWrite(NSString *account, NSData *data) {
    NSMutableDictionary *query = KeychainQueryFor(account);
    NSDictionary *attributes = @{(__bridge id)kSecValueData: data,
                                 (__bridge id)kSecAttrAccessible: (__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly};
    OSStatus status = SecItemUpdate((__bridge CFDictionaryRef)query, (__bridge CFDictionaryRef)attributes);
    if (status == errSecItemNotFound) {
        [query addEntriesFromDictionary:attributes];
        status = SecItemAdd((__bridge CFDictionaryRef)query, NULL);
    }
    return status;
}

static NSArray *ProxyIdentity(NSString *kind, NSString *host, NSString *port, NSString *user) {
    return @[kind ?: @"", host.lowercaseString ?: @"", @(port.integerValue).stringValue, user ?: @""];
}

static NSString *ReadProxyPassword(OSStatus *outStatus) {
#ifdef SGWG_TESTING
    if (TestEnv(@"SGWG_TEST_HOST")) {
        if (outStatus) *outStatus = errSecSuccess;
        return TestEnv(@"SGWG_TEST_PASS") ?: @"";
    }
#endif
    NSMutableDictionary *query = KeychainQueryFor(kKeychainProxyAccount);
    query[(__bridge id)kSecReturnData] = @YES;
    query[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitOne;
    CFTypeRef result = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
    if (outStatus) *outStatus = status;
    if (status != errSecSuccess || !result) return nil;
    NSData *data = CFBridgingRelease(result);
    id value = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    NSDictionary *settings = SGWGSettingExternalProxy();
    NSArray *identity = ProxyIdentity(SGWGSettingKind(), settings[@"host"], settings[@"port"], settings[@"username"]);
    if (![value isKindOfClass:NSDictionary.class] || ![value[@"identity"] isEqual:identity] ||
        ![value[@"password"] isKindOfClass:NSString.class] || ![value[@"password"] length]) {
        if (outStatus) *outStatus = errSecDecode;
        return nil;
    }
    return value[@"password"];
}

BOOL SGWGHasStoredProxyPassword(void) { return ReadProxyPassword(NULL).length > 0; }

static BOOL ValidateExternal(NSString *kind, NSString *host, NSString *port, NSString *username, NSString **reason) {
    NSString *failure = nil;
    NSCharacterSet *hostChars = [NSCharacterSet characterSetWithCharactersInString:
        @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-:"];
    if (![@[SGWGKindHTTP, SGWGKindHTTPS, SGWGKindSOCKS5] containsObject:kind ?: @""])
        failure = @"unknown proxy kind";
    else if (![host isKindOfClass:NSString.class] || !host.length || host.length > 253 ||
             [host rangeOfCharacterFromSet:hostChars.invertedSet].location != NSNotFound)
        failure = @"server must be a host name or IP address only (no scheme, path or spaces)";
    else if (![port isKindOfClass:NSString.class] || !port.length || port.length > 5 ||
             [port rangeOfCharacterFromSet:NSCharacterSet.decimalDigitCharacterSet.invertedSet].location != NSNotFound ||
             port.integerValue < 1 || port.integerValue > 65535)
        failure = @"port must be a number from 1 to 65535";
    else if (username.length > 255 || [username rangeOfCharacterFromSet:NSCharacterSet.newlineCharacterSet].location != NSNotFound)
        failure = @"invalid user name";
    if (reason) *reason = failure;
    return failure == nil;
}

BOOL SGWGSaveConnection(NSString *kind, NSString *host, NSString *port, NSString *username, NSString *password, NSString **reason) {
    if ([kind isEqualToString:SGWGKindWireGuard]) {
        if (!SGWGHasProfile()) {
            if (reason) *reason = @"import a WireGuard .conf first";
            return NO;
        }
        if (![SGWGSettingKind() isEqualToString:kind]) {
            OSStatus status = SecItemDelete((__bridge CFDictionaryRef)KeychainQueryFor(kKeychainProxyAccount));
            if (status != errSecSuccess && status != errSecItemNotFound) {
                if (reason) *reason = @"could not clear previous proxy credentials";
                return NO;
            }
        }
        SetSetting(@"kind", kind);
        return YES;
    }
    host = [host stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
    port = [port stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
    username = username ?: @"";
    if (!ValidateExternal(kind, host, port, username, reason)) return NO;
    NSDictionary *previous = SGWGSettingExternalProxy();
    NSArray *identity = ProxyIdentity(kind, host, port, username);
    if (![identity isEqual:ProxyIdentity(SGWGSettingKind(), previous[@"host"], previous[@"port"], previous[@"username"])]) {
        OSStatus status = SecItemDelete((__bridge CFDictionaryRef)KeychainQueryFor(kKeychainProxyAccount));
        if (status != errSecSuccess && status != errSecItemNotFound) {
            if (reason) *reason = @"could not clear previous proxy credentials";
            return NO;
        }
    }
    if (password) {
        OSStatus status = password.length
            ? KeychainWrite(kKeychainProxyAccount, [NSJSONSerialization dataWithJSONObject:
                @{@"identity": identity, @"password": password} options:0 error:nil])
            : SecItemDelete((__bridge CFDictionaryRef)KeychainQueryFor(kKeychainProxyAccount));
        if (status != errSecSuccess && status != errSecItemNotFound) {
            if (reason) *reason = [NSString stringWithFormat:@"Keychain error %d", (int)status];
            return NO;
        }
    }
    NSMutableDictionary *d = [SettingsDict() mutableCopy];
    [d addEntriesFromDictionary:@{@"kind": kind, @"host": host, @"port": port, @"username": username}];
    [[NSUserDefaults standardUserDefaults] setObject:d forKey:kDefaultsKey];
    return YES;
}

static NSString *ReadProfile(OSStatus *outStatus) {
#ifdef SGWG_TESTING
    NSString *path = TestEnv(@"SGWG_TEST_PROFILE");
    if (path) return [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL];
#endif
    NSMutableDictionary *query = KeychainQuery();
    query[(__bridge id)kSecReturnData] = @YES;
    query[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitOne;
    CFTypeRef result = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
    if (outStatus) *outStatus = status;
    if (status != errSecSuccess || !result) return nil;
    NSData *data = CFBridgingRelease(result);
    NSString *profile = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (!profile.length && outStatus) *outStatus = errSecDecode;
    return profile;
}

BOOL SGWGHasProfile(void) { return ReadProfile(NULL).length > 0; }

static NSDictionary *JSONFromGo(char *raw) {
    if (!raw) return nil;
    NSData *data = [NSData dataWithBytes:raw length:strlen(raw)];
    SGWGFree(raw);
    id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    return [obj isKindOfClass:NSDictionary.class] ? obj : nil;
}

NSDictionary *SGWGInspectProfile(NSString *text, NSString **reason) {
    NSDictionary *summary = JSONFromGo(SGWGInspect((char *)text.UTF8String));
    if (![summary[@"ok"] boolValue]) {
        if (reason) *reason = [summary[@"error"] isKindOfClass:NSString.class] ? summary[@"error"] : @"invalid profile";
        return nil;
    }
    return summary;
}

NSDictionary *SGWGStoredProfileSummary(void) {
    NSString *text = ReadProfile(NULL);
    return text ? SGWGInspectProfile(text, NULL) : nil;
}

BOOL SGWGImportProfile(NSString *text, NSString **reason) {
    if (!SGWGInspectProfile(text, reason)) return NO;
    OSStatus status = KeychainWrite(kKeychainAccount, [text dataUsingEncoding:NSUTF8StringEncoding]);
    if (status != errSecSuccess) {
        if (reason) *reason = [NSString stringWithFormat:@"Keychain error %d", (int)status];
        return NO;
    }
    return YES;
}

BOOL SGWGDeleteProfile(NSString **reason) {
    OSStatus status = SecItemDelete((__bridge CFDictionaryRef)KeychainQuery());
    if (status != errSecSuccess && status != errSecItemNotFound) {
        if (reason) *reason = [NSString stringWithFormat:@"Keychain error %d", (int)status];
        return NO;
    }
    if ([SGWGSettingKind() isEqualToString:SGWGKindWireGuard]) SGWGSetSettingEnabled(NO);
    return YES;
}

#pragma mark - Engine

NSDictionary *SGWGEngineStatus(void) {
    if (!gActive || ![gKind isEqualToString:SGWGKindWireGuard]) return @{@"running": @NO};
    return JSONFromGo(SGWGStatus()) ?: @{@"running": @NO};
}

static void EngineChanged(int state) {
    if (state == SGWGEngineDestinationFailed) return;
    BOOL available = state == SGWGEngineAvailable;
    os_unfair_lock_lock(&gReadinessLock);
    gReadinessGeneration++;
    gEngineAvailable = available;
    atomic_store(&gEngineRecoverable, state == SGWGEngineUnavailable || available);
    atomic_store(&gEngineReady, false);
    atomic_store_explicit(&gReady, false, memory_order_release);
    atomic_store(&gState, available ? SGWGStateRunning : SGWGStateFailed);
    os_unfair_lock_unlock(&gReadinessLock);
    // Rebind may still occupy gQueue. Revoke admission before returning to Go, not behind that work.
    if (!available) SGWGNotifyRecovery();
    dispatch_async(gQueue, ^{ SGWGRefreshReadiness(); });
}

static void RefuseListener(void) {
    gBlockAll = YES;
    if (gListenerFD >= 0) {
        close(gListenerFD);
        gListenerFD = -1;
    }
}
static void StartEngine(void) {
    dispatch_async(gQueue, ^{
        SGWGState state = SGWGCurrentState();
        if (atomic_load(&gEngineReady) || state == SGWGStateFailed || gBlockAll) return;
        OSStatus status = errSecSuccess;
        NSString *profile = ReadProfile(&status);
        if (!profile.length) {
            atomic_store(&gCredentialStatus, status);
            BOOL retryable = status == errSecInteractionNotAllowed || status == errSecNotAvailable;
            if (!retryable) RefuseListener();
            atomic_store(&gState, retryable ? SGWGStateWaitingProfile : SGWGStateBlocked);
            return;
        }
        atomic_store(&gCredentialStatus, errSecSuccess);
        if (gListenerFD < 0) return; // already handed to Go or definitively refused
        atomic_store(&gState, SGWGStateStarting);
        int fd = gListenerFD;
        gListenerFD = -1; // ownership moves to Go
        SGWGSetStateCallback((uintptr_t)EngineChanged);
        int port = SGWGStart((char *)profile.UTF8String, gUser, gPass, fd, gPort);
        if (port != gPort) EngineChanged(SGWGEngineStopped);
        SGWGRefreshReadiness();
    });
}

void SGWGRequestRebind(NSString *reason) {
    if (!gActive) return;
    dispatch_async(gQueue, ^{
        SGWGState state = SGWGCurrentState();
        if (state == SGWGStateWaitingProfile) {
            StartEngine();
        } else if (state == SGWGStateRunning || (state == SGWGStateFailed && atomic_load(&gEngineRecoverable))) {
            SGWGRebind();
            atomic_fetch_add(&gRebinds, 1);
        }
    });
}

void SGWGLookupInTunnel(NSString *host, void (^completion)(NSDictionary *)) {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSDictionary *result = gActive && [gKind isEqualToString:SGWGKindWireGuard] ? JSONFromGo(SGWGLookup((char *)host.UTF8String)) : nil;
        dispatch_async(dispatch_get_main_queue(), ^{ completion(result ?: @{@"ok": @NO, @"error": @"tunnel not active"}); });
    });
}

NSURLSession *SGWGTunnelSession(id<NSURLSessionDelegate> delegate) {
    if (!gActive) return nil;
    NSURLSessionConfiguration *c = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    c.timeoutIntervalForRequest = 15;
    c.timeoutIntervalForResource = 25;
    c.URLCache = nil;
    c.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    ApplyProxy(c); // explicit, independent of the class-method hooks
    return [NSURLSession sessionWithConfiguration:c delegate:delegate delegateQueue:nil];
}

static BOOL ReserveListener(void) {
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) return NO;
    int one = 1;
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(one));
    struct sockaddr_in addr = {0};
    addr.sin_len = sizeof(addr);
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    socklen_t len = sizeof(addr);
    if (bind(fd, (struct sockaddr *)&addr, sizeof(addr)) || listen(fd, 256) ||
        getsockname(fd, (struct sockaddr *)&addr, &len)) {
        close(fd);
        return NO;
    }
    gListenerFD = fd;
    gPort = ntohs(addr.sin_port);
    return YES;
}

static void RandomHex(char out[33]) {
    uint8_t bytes[16];
    if (SecRandomCopyBytes(kSecRandomDefault, sizeof(bytes), bytes) != errSecSuccess) arc4random_buf(bytes, sizeof(bytes));
    for (int i = 0; i < 16; i++) snprintf(out + i * 2, 3, "%02x", bytes[i]);
}

static void ObserveLifecycle(void) {
    // UIKit notification names as strings: this file is Foundation-only so the
    // same core also runs in the macOS test harness.
    // Rebind only after real backgrounding (iOS may have defuncted the sockets),
    // not after Control Center or a notification banner, to avoid needless
    // interruptions of a playing stream.
    static CFAbsoluteTime backgroundSince;
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    [center addObserverForName:@"UIApplicationDidEnterBackgroundNotification" object:nil queue:nil usingBlock:^(NSNotification *note) {
        backgroundSince = CFAbsoluteTimeGetCurrent();
    }];
    [center addObserverForName:@"UIApplicationWillEnterForegroundNotification" object:nil queue:nil usingBlock:^(NSNotification *note) {
        if (backgroundSince > 0 && CFAbsoluteTimeGetCurrent() - backgroundSince > 15) SGWGRequestRebind(@"foreground");
        backgroundSince = 0;
    }];
    for (NSString *name in @[@"UIApplicationDidBecomeActiveNotification", @"UIApplicationProtectedDataDidBecomeAvailable"]) {
        [center addObserverForName:name object:nil queue:nil usingBlock:^(NSNotification *note) {
            // Starts the engine if the Keychain was locked at launch; no rebind.
            if (SGWGCurrentState() == SGWGStateWaitingProfile) SGWGRequestRebind(name);
        }];
    }
    static nw_path_monitor_t monitor;
    static NSString *lastSignature;
    monitor = nw_path_monitor_create();
    nw_path_monitor_set_queue(monitor, gQueue);
    nw_path_monitor_set_update_handler(monitor, ^(nw_path_t path) {
        NSString *signature = [NSString stringWithFormat:@"%d%d%d%d", (int)nw_path_get_status(path),
            nw_path_uses_interface_type(path, nw_interface_type_wifi), nw_path_uses_interface_type(path, nw_interface_type_cellular),
            nw_path_uses_interface_type(path, nw_interface_type_wired)];
        // Wi-Fi <-> cellular: reopen the WireGuard UDP socket on the new path.
        if (lastSignature && ![signature isEqualToString:lastSignature] && nw_path_get_status(path) == nw_path_status_satisfied)
            SGWGRequestRebind(@"path");
        lastSignature = signature;
    });
    nw_path_monitor_start(monitor);
}


// HTTP / HTTPS / SOCKS5 server chosen by the user. No local engine runs; the
// same URLSession hooks apply an nw_proxy_config with failover disabled.
static void StartExternalProxy(void) {
    gActive = YES;
    NSDictionary *cfg = SGWGSettingExternalProxy();
    NSString *host = cfg[@"host"], *port = cfg[@"port"], *user = cfg[@"username"], *pass = nil;
    if (!ValidateExternal(gKind, host, port, user, NULL)) gBlockAll = YES;
    if (!gBlockAll && user.length) {
        OSStatus status = errSecSuccess;
        pass = ReadProxyPassword(&status);
        atomic_store(&gCredentialStatus, status);
        if (status != errSecSuccess || !pass.length) {
            atomic_store(&gState, (status == errSecInteractionNotAllowed || status == errSecNotAvailable)
                ? SGWGStateWaitingProfile : SGWGStateBlocked);
            return;
        }
    }
    if (!gBlockAll) {
        strlcpy(gProxyHost, host.UTF8String, sizeof(gProxyHost));
        strlcpy(gProxyPort, port.UTF8String, sizeof(gProxyPort));
        if (user.length) {
            gProxyUser = strdup(user.UTF8String);
            gProxyPass = strdup(pass.UTF8String);
        }
    }
    atomic_store(&gState, gBlockAll ? SGWGStateBlocked : SGWGStateExternalProxy);
    os_unfair_lock_lock(&gReadinessLock);
    gReadinessGeneration++;
    gEngineAvailable = !gBlockAll;
    atomic_store(&gEngineReady, false);
    atomic_store_explicit(&gReady, false, memory_order_release);
    os_unfair_lock_unlock(&gReadinessLock);
    SGWGRefreshReadiness();
}

void SGWGRefreshReadiness(void) {
    os_unfair_lock_lock(&gReadinessLock);
    uint64_t generation = gReadinessGeneration;
    BOOL available = gEngineAvailable;
    os_unfair_lock_unlock(&gReadinessLock);
    // Patching can itself load an image. Validate outside the lock, then commit only that generation.
    BOOL native = SGWGInstallNativePatches();
    BOOL guards = gSessionGuards && native;
    BOOL ready = guards && SGWGIsSupportedOS() && SGWGAdmissionReady() && available && !gBlockAll;
    os_unfair_lock_lock(&gReadinessLock);
    if (generation == gReadinessGeneration) {
        atomic_store(&gGuardsReady, guards);
        atomic_store(&gEngineReady, available);
        atomic_store_explicit(&gReady, ready, memory_order_release);
    }
    os_unfair_lock_unlock(&gReadinessLock);
}

static void ImageChanged(const struct mach_header *header, intptr_t slide) {
    if (!gActive) return;
    os_unfair_lock_lock(&gReadinessLock);
    gReadinessGeneration++;
    atomic_store_explicit(&gReady, false, memory_order_release);
    os_unfair_lock_unlock(&gReadinessLock);
    dispatch_async(gQueue, ^{ SGWGRefreshReadiness(); });
}

__attribute__((constructor)) static void SGWGInit(void) {
    @autoreleasepool {
        gQueue = dispatch_queue_create("retrine.wireguard", DISPATCH_QUEUE_SERIAL);
        if (!SGWGSettingEnabled()) return;
        atomic_store(&gActive, true);
        gKind = SGWGSettingKind();
        RandomHex(gUser);
        RandomHex(gPass);
        BOOL supported = SGWGIsSupportedOS();
        BOOL tunnel = [gKind isEqualToString:SGWGKindWireGuard];
        // A session created while SpotifyShared is still loading keeps its proxy for life.
        if (supported && tunnel && !ReserveListener()) gBlockAll = YES;
        BOOL pending = NO;
        BOOL admitted = supported && SGWGCheckAdmission(&pending);
        if (tunnel && !admitted && !pending) RefuseListener();
        gSessionGuards = InstallSessionHooks();
        SGWGRefreshReadiness();
        _dyld_register_func_for_add_image(ImageChanged);
        _dyld_register_func_for_remove_image(ImageChanged);
        static dispatch_source_t recovery;
        recovery = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, gQueue);
        dispatch_source_set_timer(recovery, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), 5 * NSEC_PER_SEC, NSEC_PER_SEC);
        dispatch_source_set_event_handler(recovery, ^{
            if (!SGWGReady()) SGWGRefreshReadiness();
            if (SGWGCurrentState() == SGWGStateWaitingProfile) {
                if ([gKind isEqualToString:SGWGKindWireGuard]) StartEngine();
                else StartExternalProxy();
            } else if (SGWGCurrentState() == SGWGStateBlocked && !gBlockAll &&
                       !atomic_load(&gEngineReady) && !atomic_load(&gCredentialStatus) &&
                       SGWGIsSupportedOS()) {
                BOOL stillPending = NO;
                if (SGWGCheckAdmission(&stillPending)) {
                    if (tunnel) StartEngine();
                    else StartExternalProxy();
                } else if (tunnel && !stillPending) RefuseListener();
            } else if (SGWGCurrentState() == SGWGStateFailed && atomic_load(&gEngineRecoverable)) {
                SGWGRequestRebind(@"engine unavailable");
            }
#ifndef SGWG_TESTING
            if (!SGWGReady()) SGWGNotifyRecovery();
#endif
        });
        dispatch_resume(recovery);
        if (!supported) {
            atomic_store(&gState, SGWGStateUnsupported);
            return;
        }
        // A saved opt-in may survive an app update. Do not start a tunnel or
        // touch Spotify's delegates on an uninspected version. The stable Apple
        // entry points still block their covered traffic, not the whole app.
        if (!admitted) {
            atomic_store(&gState, SGWGStateBlocked);
            return;
        }
        SGWGInstallTransportPatches();
        if (![gKind isEqualToString:SGWGKindWireGuard]) {
            StartExternalProxy();
            return;
        }
        atomic_store(&gState, gBlockAll ? SGWGStateBlocked : SGWGStateStarting);
        ObserveLifecycle();
        StartEngine();
    }
}

#pragma mark - Diagnostics

NSString *SGWGHostCategory(NSString *host) {
    NSString *h = host.lowercaseString ?: @"";
    BOOL (^is)(NSString *) = ^BOOL(NSString *domain) { return [h isEqualToString:domain] || [h hasSuffix:[@"." stringByAppendingString:domain]]; };
    if ([h hasPrefix:@"audio"] && (is(@"scdn.co") || is(@"spotifycdn.com") || is(@"akamaized.net"))) return @"media";
    if (is(@"spotify.com") || is(@"spotify.net")) return @"api";
    return @"other";
}

NSString *SGWGRedactText(NSString *text) {
    char *raw = SGWGRedact((char *)(text ?: @"").UTF8String);
    if (!raw) return @"";
    NSString *out = [NSString stringWithUTF8String:raw] ?: @"";
    SGWGFree(raw);
    return out;
}

static NSString *DeviceModel(void) {
    struct utsname u;
    uname(&u);
    return [NSString stringWithUTF8String:u.machine] ?: @"?";
}

static NSString *N(id v) { return v ? [NSString stringWithFormat:@"%@", v] : @"-"; }

NSString *SGWGDiagnosticsReport(NSDictionary<NSString *, NSString *> *checks) {
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    NSProcessInfo *info = NSProcessInfo.processInfo;
    [lines addObject:[NSString stringWithFormat:@"Retrine app-local WireGuard diagnostics v%@", SGWGVersion]];
    [lines addObject:[NSString stringWithFormat:@"app: Spotify %@ | OS %@ | %@", SGWGAppVersion(), info.operatingSystemVersionString, DeviceModel()]];
    [lines addObject:[NSString stringWithFormat:@"setting.enabled: %@ | active this launch: %@ | supported OS: %@",
        SGWGSettingEnabled() ? @"yes" : @"no", gActive ? @"yes" : @"no", SGWGIsSupportedOS() ? @"yes" : @"no"]];
    [lines addObject:[NSString stringWithFormat:@"state: %@", SGWGStateDescription(SGWGCurrentState())]];
    [lines addObject:[NSString stringWithFormat:@"guards: %@; ready: %@; credential-status: %d",
        SGWGGuardsInstalled() ? @"installed" : @"incomplete", SGWGReady() ? @"yes" : @"no", atomic_load(&gCredentialStatus)]];
    [lines addObject:SGWGIsSupportedVersion() ? @"transport.version: inspected version; IPA UUID preflight required" :
        @"transport.version: uninspected; covered traffic blocked when enabled on a supported OS"];
    // The external proxy host is intentionally not included.
    NSString *mode = gActive ? gKind : SGWGSettingKind();
    [lines addObject:[NSString stringWithFormat:@"mode: %@%@", mode,
        [mode isEqualToString:SGWGKindWireGuard] ? @" (in-app tunnel)" :
        [NSString stringWithFormat:@" (external proxy, auth %@)", gProxyUser ? @"yes" : @"no"]]];

    NSDictionary *st = SGWGEngineStatus();
    if ([st[@"running"] boolValue]) {
        long long age = [st[@"handshakeAgeSec"] longLongValue];
        [lines addObject:[NSString stringWithFormat:@"wireguard.handshake: %@ | wg rx %@ B tx %@ B | uptime %@ s",
            age < 0 ? @"none yet" : [NSString stringWithFormat:@"%lld s ago", age], N(st[@"wgRxBytes"]), N(st[@"wgTxBytes"]), N(st[@"uptimeSec"])]];
        NSDictionary *c = st[@"connections"], *cat = st[@"categories"], *b = st[@"proxyBytes"], *bind = st[@"bind"];
        [lines addObject:[NSString stringWithFormat:@"tunnel.connections: total %@ (hostname %@, ip %@) active %@ failed %@ dnsFailed %@",
            N(c[@"total"]), N(c[@"domainTargets"]), N(c[@"ipTargets"]), N(c[@"active"]), N(c[@"failed"]), N(c[@"dnsFailed"])]];
        [lines addObject:[NSString stringWithFormat:@"tunnel.by-protocol: socks5 %@ | http-connect %@ | auth rejected %@ | bad requests %@",
            N(c[@"socks"]), N(c[@"httpConnect"]), N(c[@"authRejected"]), N(c[@"badRequests"])]];
        [lines addObject:[NSString stringWithFormat:@"tunnel.destinations: media-cdn %@ | spotify-api %@ | other %@",
            N(cat[@"media"]), N(cat[@"api"]), N(cat[@"other"])]];
        [lines addObject:[NSString stringWithFormat:@"tunnel.bytes: up %@ down %@ | bind updates %@ failures %@ relistens %@ | endpoint resolved by device DNS: %@",
            N(b[@"up"]), N(b[@"down"]), N(bind[@"updates"]), N(bind[@"failures"]), N(bind[@"relistens"]), [st[@"endpointResolvedLocally"] boolValue] ? @"yes" : @"no"]];
    } else if (gActive && ![gKind isEqualToString:SGWGKindWireGuard]) {
        [lines addObject:@"engine: not used (external proxy; host names are resolved by the proxy server)"];
    } else {
        [lines addObject:[NSString stringWithFormat:@"engine: not running %@", N(st[@"error"])]];
    }
    NSDictionary *p = SGWGProxyCounters();
    [lines addObject:[NSString stringWithFormat:@"proxy.applied: configs %@ sessions %@ background %@ sharedSession %@ | failures %@ blocked %@",
        p[@"configs"], p[@"sessions"], p[@"backgroundConfigs"], p[@"sharedReplaced"], p[@"proxyFailures"], p[@"blockedRequests"]]];
    [lines addObject:[NSString stringWithFormat:@"proxy.other: http3 requests cleared %@ | NSData URL loads tunnelled %@ | rebinds %@",
        p[@"http3Cleared"], p[@"dataURLFetches"], p[@"rebinds"]]];
    [lines addObjectsFromArray:SGWGTransportReportLines()];
    [lines addObjectsFromArray:SGWGNativeReportLines()];
    for (NSString *key in [checks.allKeys sortedArrayUsingSelector:@selector(compare:)])
        [lines addObject:[NSString stringWithFormat:@"check.%@: %@", key, checks[key]]];
    [lines addObject:@"note: a country/HTTPS check passing does not prove music playback; verify play, next track and lock-screen playback."];
    return SGWGRedactText([lines componentsJoinedByString:@"\n"]);
}
