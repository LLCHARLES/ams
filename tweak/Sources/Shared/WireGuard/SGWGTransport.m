// Spotify transport observations. No Google flags, enum guesses or binary patches.
// The session core applies the proxy; these delegates measure what Spotify actually receives.
#import "SGWGCore.h"
#import <objc/runtime.h>
#import <os/lock.h>
#import <stdatomic.h>

static os_unfair_lock lock = OS_UNFAIR_LOCK_INIT;
static NSMutableDictionary<NSString *, NSNumber *> *completions, *statuses, *errors;
static NSMutableArray<NSString *> *installed, *skipped;
static atomic_uint_fast64_t mediaBytes, apiBytes;

static NSArray<NSString *> *Delegates(void) {
    return @[@"SPTCoreURLSessionDataDelegate",
             @"_TtC26Connectivity_HttpClientKit20HttpClientURLSession", @"SPTDataLoaderService"];
}

// Verify the ABI, including every argument, before touching the implementation.
static BOOL Matches(Method method) {
    if (!method || method_getNumberOfArguments(method) != 5) return NO;
    char *type = method_copyReturnType(method);
    BOOL valid = type && !strcmp(type, "v");
    free(type);
    for (unsigned i = 2; valid && i < 5; i++) {
        type = method_copyArgumentType(method, i);
        valid = type && !strcmp(type, "@");
        free(type);
    }
    return valid;
}

static void Increment(NSMutableDictionary *map, NSString *key) {
    map[key] = @([map[key] unsignedLongLongValue] + 1);
}

static void ObserveCompletion(NSString *name, NSURLSessionTask *task, NSError *error) {
    NSInteger status = [task.response isKindOfClass:NSHTTPURLResponse.class] ? [(NSHTTPURLResponse *)task.response statusCode] : 0;
    // Never retain URLs, payloads, headers, or an arbitrary error domain supplied by a server.
    NSString *domain = [@[@"NSURLErrorDomain", @"NSPOSIXErrorDomain", @"kCFErrorDomainCFNetwork"] containsObject:error.domain] ? error.domain : @"other";
    os_unfair_lock_lock(&lock);
    Increment(completions, name);
    if (status) Increment(statuses, [NSString stringWithFormat:@"%ld", (long)status]);
    if (error) Increment(errors, [NSString stringWithFormat:@"%@ %ld", domain, (long)error.code]);
    os_unfair_lock_unlock(&lock);
}

typedef enum { Other, Media, API, MissingHost } HostKind;

// Don't pin even the last song URL on a long-lived delegate thread. When a
// classified URL dies, invalidate address comparisons before it can be reused.
static atomic_uint_fast64_t urlGeneration;
@interface SGWGHostKind : NSObject {
@public HostKind kind;
}
@end
@implementation SGWGHostKind
- (void)dealloc { atomic_fetch_add_explicit(&urlGeneration, 1, memory_order_release); }
@end

static HostKind KindForURL(NSURL * __attribute__((objc_precise_lifetime)) url) {
    if (!url) return MissingHost;
    static __thread struct { uintptr_t address; uint64_t generation; HostKind kind; } last;
    uintptr_t address = (uintptr_t)(__bridge void *)url;
    uint64_t generation = atomic_load_explicit(&urlGeneration, memory_order_acquire);
    if (last.address == address && last.generation == generation) return last.kind;
    SGWGHostKind *tag = objc_getAssociatedObject(url, &urlGeneration);
    if (!tag) {
        @synchronized (url) {
            tag = objc_getAssociatedObject(url, &urlGeneration);
            if (!tag) {
                NSString *host = url.host;
                NSString *category = SGWGHostCategory(host);
                tag = [SGWGHostKind new];
                tag->kind = !host ? MissingHost : [category isEqual:@"media"] ? Media : [category isEqual:@"api"] ? API : Other;
                objc_setAssociatedObject(url, &urlGeneration, tag, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
        }
    }
    last = (typeof(last)){address, generation, tag->kind};
    return tag->kind;
}

static void ObserveData(NSURLSessionTask *task, NSData *data) {
    HostKind kind = KindForURL(task.currentRequest.URL);
    if (kind == MissingHost) kind = KindForURL(task.originalRequest.URL);
    if (kind == Media) atomic_fetch_add_explicit(&mediaBytes, data.length, memory_order_relaxed);
    if (kind == API) atomic_fetch_add_explicit(&apiBytes, data.length, memory_order_relaxed);
}

static void Hook(NSString *name, BOOL data) {
    Class cls = NSClassFromString(name);
    SEL selector = NSSelectorFromString(data ? @"URLSession:dataTask:didReceiveData:" : @"URLSession:task:didCompleteWithError:");
    Method method = class_getInstanceMethod(cls, selector);
    NSString *label = [NSString stringWithFormat:@"%@ %@", name, NSStringFromSelector(selector)];
    if (!Matches(method)) { [skipped addObject:label]; return; }
    void (*original)(id, SEL, id, id, id) = (void *)method_getImplementation(method);
    IMP replacement;
    if (data) {
        replacement = imp_implementationWithBlock(^(id self, NSURLSession *session, NSURLSessionDataTask *task, NSData *bytes) {
            ObserveData(task, bytes);
            original(self, selector, session, task, bytes);
        });
    } else {
        replacement = imp_implementationWithBlock(^(id self, NSURLSession *session, NSURLSessionTask *task, NSError *error) {
            ObserveCompletion(name, task, error);
            original(self, selector, session, task, error);
        });
    }
    if (!class_addMethod(cls, selector, replacement, method_getTypeEncoding(method)))
        method_setImplementation(class_getInstanceMethod(cls, selector), replacement);
    [installed addObject:label];
}

void SGWGInstallTransportPatches(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        completions = [NSMutableDictionary dictionary];
        statuses = [NSMutableDictionary dictionary];
        errors = [NSMutableDictionary dictionary];
        installed = [NSMutableArray array];
        skipped = [NSMutableArray array];
        for (NSString *name in Delegates()) { Hook(name, NO); Hook(name, YES); }
    });
}

static NSString *Summary(NSDictionary *values) {
    NSMutableArray *parts = [NSMutableArray array];
    for (NSString *key in [values.allKeys sortedArrayUsingSelector:@selector(compare:)])
        [parts addObject:[NSString stringWithFormat:@"%@ x%@", key, values[key]]];
    return parts.count ? [parts componentsJoinedByString:@", "] : @"none";
}

NSArray<NSString *> *SGWGTransportReportLines(void) {
    os_unfair_lock_lock(&lock);
    NSArray *lines = @[
        [NSString stringWithFormat:@"spotify.completions: %@", Summary(completions)],
        [NSString stringWithFormat:@"spotify.http-status: %@", Summary(statuses)],
        [NSString stringWithFormat:@"spotify.errors: %@", Summary(errors)],
        [NSString stringWithFormat:@"spotify.received-bytes: media %llu api %llu",
            (unsigned long long)atomic_load_explicit(&mediaBytes, memory_order_relaxed),
            (unsigned long long)atomic_load_explicit(&apiBytes, memory_order_relaxed)],
        [NSString stringWithFormat:@"spotify.hooks: %lu installed | skipped: %@", (unsigned long)installed.count, [skipped componentsJoinedByString:@"; "] ?: @"none"],
        @"coverage: URLSession and Spotify main-image native TCP imports; remote UDP is blocked. Background services, remote Connect devices and playback are not device-verified.",
        [NSString stringWithFormat:@"input: Spotify %@; class/selector presence is static evidence, not proof of playback. Destination counters count connection attempts.", SGWGAppVersion()]
    ];
    os_unfair_lock_unlock(&lock);
    return lines;
}

NSArray<NSString *> *SGWGScanTransportClasses(void) {
    NSMutableArray *lines = [NSMutableArray array];
    for (NSString *name in Delegates()) {
        Class cls = NSClassFromString(name);
        [lines addObject:[NSString stringWithFormat:@"%@: %@", name, cls ? @"present" : @"missing"]];
        for (NSString *selector in @[@"URLSession:task:didCompleteWithError:", @"URLSession:dataTask:didReceiveData:"]) {
            Method method = class_getInstanceMethod(cls, NSSelectorFromString(selector));
            [lines addObject:[NSString stringWithFormat:@"  %@: %@", selector, Matches(method) ? @"compatible" : @"missing or incompatible"]];
        }
    }
    return lines;
}
