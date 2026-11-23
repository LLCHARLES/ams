// Run the real resume hook with task doubles and a real Foundation session whose
// URLProtocol transport is local; no sockets or Spotify account are involved.
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import "AdBlock.h"
#include <stdlib.h>

BOOL SGHidden(NSString *key) {
    const char *value = getenv([key isEqualToString:SGKeyHideAds] ? "HIDE_ADS" : "FAKE_PREMIUM");
    return value && atoi(value);
}
void SGRequireClasses(NSArray<NSString *> *names) {}
static NSUInteger blockedRequests, seenRequests;
void SGAdBlockCountOne(NSString *label) { if ([label isEqual:@"Requests"]) blockedRequests++; }
void SGAdBlockSawOne(NSString *label) { if ([label isEqual:@"Requests"]) seenRequests++; }
NSData *SGPatchCustomize(NSData *data) { return data; }
NSData *SGPatchBootstrap(NSData *data) { return data; }
NSData *SGPatchAccountAttributes(NSData *data) { return data; }
NSData *SGPatchRemoteConfiguration(NSData *data) { return data; }
BOOL SGOfflineCompanionLoaded(void) { return NO; }
NSData *SGPatchOfflineAccountAttributes(NSData *data, BOOL *recognized) { if (recognized) *recognized = NO; return data; }
NSData *SGStripFeed(NSData *data) { return data; }

@interface ProbeTask : NSURLSessionTask
@property NSURLRequest *current;
@property NSURLRequest *original;
@property BOOL sent;
@property BOOL cancelled;
@end
@implementation ProbeTask
- (NSURLRequest *)currentRequest { return self.current; }
- (NSURLRequest *)originalRequest { return self.original; }
- (void)cancel { self.cancelled = YES; }
@end
static void sendTask(ProbeTask *task, SEL selector) { task.sent = YES; }
__attribute__((constructor(101))) static void installTransport(void) {
    if (getenv("REAL_SESSION")) return;
    class_replaceMethod(NSURLSessionTask.class, @selector(resume), (IMP)sendTask, "v@:");
}

@interface DelegateProbe : NSObject <NSURLSessionDataDelegate>
@property NSOperationQueue *queue;
@property NSMutableArray *events;
@property NSMutableData *body;
@property NSInteger status;
@property NSError *error;
@property BOOL correctQueue;
@property BOOL rejectResponse;
@property dispatch_semaphore_t completed;
@property dispatch_semaphore_t invalidated;
@end
@implementation DelegateProbe
- (instancetype)init {
    if ((self = [super init])) {
        _events = [NSMutableArray new];
        _body = [NSMutableData new];
        _correctQueue = YES;
        _completed = dispatch_semaphore_create(0);
        _invalidated = dispatch_semaphore_create(0);
    }
    return self;
}
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveResponse:(NSURLResponse *)response completionHandler:(void (^)(NSURLSessionResponseDisposition))handler {
    self.correctQueue &= NSOperationQueue.currentQueue == self.queue;
    [self.events addObject:@"response"];
    self.status = [(NSHTTPURLResponse *)response statusCode];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
        handler(self.rejectResponse ? NSURLSessionResponseCancel : NSURLSessionResponseAllow);
    });
}
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveData:(NSData *)data {
    self.correctQueue &= NSOperationQueue.currentQueue == self.queue;
    [self.events addObject:@"data"];
    [self.body appendData:data];
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    self.correctQueue &= NSOperationQueue.currentQueue == self.queue;
    [self.events addObject:@"complete"];
    self.error = error;
    dispatch_semaphore_signal(self.completed);
}
- (void)URLSession:(NSURLSession *)session didBecomeInvalidWithError:(NSError *)error {
    dispatch_semaphore_signal(self.invalidated);
}
@end
@interface SPTDataLoaderService : DelegateProbe @end
@implementation SPTDataLoaderService @end
@interface _TtC26Connectivity_HttpClientKit20HttpClientURLSession : DelegateProbe @end
@implementation _TtC26Connectivity_HttpClientKit20HttpClientURLSession @end
@interface SPTCoreURLSessionDataDelegate : DelegateProbe @end
@implementation SPTCoreURLSessionDataDelegate @end

#include "AdNetwork.m"

// Count matcher entries without adding instrumentation to the production chunk path.
static _Thread_local NSUInteger adMatches;
__attribute__((no_instrument_function)) void __cyg_profile_func_enter(void *fn, void *caller) {
    if (fn == (void *)isAd) adMatches++;
}
__attribute__((no_instrument_function)) void __cyg_profile_func_exit(void *fn, void *caller) {}

static NSUInteger offlineAllocations;
@implementation SGOfflineResponse (AllocationProbe)
+ (instancetype)allocWithZone:(NSZone *)zone {
    offlineAllocations++;
    return [super allocWithZone:zone];
}
@end

static int chunkCosts(void) {
    ProbeTask *task = class_createInstance(ProbeTask.class, 0);
    task.current = [NSURLRequest requestWithURL:[NSURL URLWithString:@"https://audio.example/track"]];
    SPTCoreURLSessionDataDelegate *delegate = [SPTCoreURLSessionDataDelegate new];
    NSURLResponse *reply = [[NSHTTPURLResponse alloc] initWithURL:task.current.URL statusCode:200
                                                     HTTPVersion:@"HTTP/2" headerFields:nil];
    adMatches = 0;
    offlineAllocations = 0;
    [task resume];
    NSURLSession *session = NSURLSession.sharedSession;
    // This suite has no offline companion; exercise its response hook's decision explicitly.
    [delegate URLSession:session dataTask:(id)task didReceiveResponse:responseFor(task, reply)
       completionHandler:^(NSURLSessionResponseDisposition d) {}];
    NSData *chunk = [@"x" dataUsingEncoding:NSUTF8StringEncoding];
    for (int i = 0; i < 32; i++) [delegate URLSession:session dataTask:(id)task didReceiveData:chunk];
    NSUInteger matches = adMatches, allocations = offlineAllocations;
    if (matches != 1 || allocations || delegate.body.length != 32) {
        NSLog(@"FAIL 32 audio chunks: %lu matches, %lu offline allocations, %lu bytes",
              matches, allocations, delegate.body.length);
        return 1;
    }
    // Redirecting the same task must invalidate the negative result.
    task.current = [NSURLRequest requestWithURL:[NSURL URLWithString:@"https://ads.spotify.com/fetch"]];
    [delegate URLSession:session dataTask:(id)task didReceiveData:chunk];
    if (adMatches != 2 || delegate.body.length != 32) {
        NSLog(@"FAIL redirected audio task: %lu matches, %lu bytes", adMatches, delegate.body.length);
        return 1;
    }
    return 0;
}

// A real Foundation session, with its final network boundary handled locally.
@interface LocalProtocol : NSURLProtocol
@end
@implementation LocalProtocol
+ (BOOL)canInitWithRequest:(NSURLRequest *)request { return YES; }
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request { return request; }
- (void)startLoading {
    NSURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:self.request.URL statusCode:200
                                                      HTTPVersion:@"HTTP/1.1" headerFields:@{}];
    [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    [self.client URLProtocol:self didLoadData:[@"ok" dataUsingEncoding:NSUTF8StringEncoding]];
    [self.client URLProtocolDidFinishLoading:self];
}
- (void)stopLoading {}
@end

static int delegateSessions(void) {
    int failed = 0;
    for (Class cls in @[SPTDataLoaderService.class, _TtC26Connectivity_HttpClientKit20HttpClientURLSession.class,
                        SPTCoreURLSessionDataDelegate.class]) {
        DelegateProbe *delegate = [cls new];
        delegate.queue = [NSOperationQueue new];
        delegate.queue.maxConcurrentOperationCount = 1;
        NSURLSessionConfiguration *configuration = NSURLSessionConfiguration.ephemeralSessionConfiguration;
        configuration.protocolClasses = @[LocalProtocol.class];
        NSURLSession *session = [NSURLSession sessionWithConfiguration:configuration delegate:delegate delegateQueue:delegate.queue];
        NSURLSessionDataTask *task = [session dataTaskWithURL:[NSURL URLWithString:@"https://spclient.wg.spotify.com/ads"]];
        NSUInteger blocked = blockedRequests, seen = seenRequests;
        [task resume];
        BOOL completed = dispatch_semaphore_wait(delegate.completed, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)) == 0;
        [session finishTasksAndInvalidate];
        BOOL invalidated = dispatch_semaphore_wait(delegate.invalidated, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)) == 0;
        NSData *expected = SGHidden(SGKeyHideAds) ? [NSData data] : [@"ok" dataUsingEncoding:NSUTF8StringEncoding];
        BOOL passed = completed && invalidated && delegate.correctQueue && delegate.status == 200 && !delegate.error &&
            [delegate.body isEqual:expected] && [delegate.events isEqual:@[@"response", @"data", @"complete"]];
        if (SGHidden(SGKeyHideAds))
            passed &= blockedRequests - blocked == 1 && seenRequests - seen == 1;
        if (!passed) {
            NSLog(@"FAIL delegate %@: status=%ld events=%@ data=%@ error=%@ queue=%d completed=%d invalidated=%d",
                  cls, (long)delegate.status, delegate.events, delegate.body, delegate.error,
                  delegate.correctQueue, completed, invalidated);
            failed++;
        }
        printf("delegate %s Hide ads=%d: %s\n", class_getName(cls), SGHidden(SGKeyHideAds), passed ? "PASS" : "FAIL");
    }
    return failed ? EXIT_FAILURE : EXIT_SUCCESS;
}

// A response may already have arrived (for example, before a resumed task was canceled).
// Exercise the hooked callbacks on Foundation's delegate queue, including a refused response.
static int delegateFallbacks(void) {
    if (!SGHidden(SGKeyHideAds)) return 0;
    int failed = 0;
    for (Class cls in @[SPTDataLoaderService.class, _TtC26Connectivity_HttpClientKit20HttpClientURLSession.class,
                        SPTCoreURLSessionDataDelegate.class]) {
        for (NSNumber *reject in @[@NO, @YES]) {
            DelegateProbe *delegate = [cls new];
            delegate.rejectResponse = reject.boolValue;
            delegate.queue = [NSOperationQueue new];
            delegate.queue.maxConcurrentOperationCount = 1;
            NSURLSession *session = [NSURLSession sessionWithConfiguration:NSURLSessionConfiguration.ephemeralSessionConfiguration
                                                                 delegate:delegate delegateQueue:delegate.queue];
            ProbeTask *task = class_createInstance(ProbeTask.class, 0);
            task.current = [NSURLRequest requestWithURL:[NSURL URLWithString:@"https://spclient.wg.spotify.com/ads"]];
            [delegate.queue addOperationWithBlock:^{
                NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:task.current.URL statusCode:503
                                                                       HTTPVersion:@"HTTP/1.1" headerFields:@{}];
                [delegate URLSession:session dataTask:(id)task didReceiveResponse:response completionHandler:^(NSURLSessionResponseDisposition disposition) {
                    [delegate.queue addOperationWithBlock:^{
                        if (disposition == NSURLSessionResponseAllow)
                            [delegate URLSession:session dataTask:(id)task didReceiveData:[@"ad" dataUsingEncoding:NSUTF8StringEncoding]];
                        NSError *cancelled = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCancelled userInfo:nil];
                        [delegate URLSession:session task:task didCompleteWithError:cancelled];
                        [delegate URLSession:session task:task didCompleteWithError:cancelled];
                    }];
                }];
            }];
            BOOL completed = dispatch_semaphore_wait(delegate.completed, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)) == 0;
            [session finishTasksAndInvalidate];
            BOOL invalidated = dispatch_semaphore_wait(delegate.invalidated, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)) == 0;
            NSArray *expected = reject.boolValue ? @[@"response", @"complete"] : @[@"response", @"data", @"complete"];
            BOOL cancelled = [delegate.error.domain isEqualToString:NSURLErrorDomain] && delegate.error.code == NSURLErrorCancelled;
            BOOL passed = completed && invalidated && delegate.correctQueue && delegate.status == 200 && !delegate.body.length &&
                [delegate.events isEqual:expected] && (reject.boolValue ? cancelled : delegate.error == nil);
            if (!passed) {
                NSLog(@"FAIL fallback %@ reject=%@: status=%ld events=%@ error=%@ queue=%d",
                      cls, reject, (long)delegate.status, delegate.events, delegate.error, delegate.correctQueue);
                failed++;
            }
            printf("delegate fallback %s reject=%d: %s\n", class_getName(cls), reject.boolValue, passed ? "PASS" : "FAIL");
        }
    }
    return failed ? EXIT_FAILURE : EXIT_SUCCESS;
}

static int realSession(void) {
    NSURLSessionConfiguration *configuration = NSURLSessionConfiguration.ephemeralSessionConfiguration;
    configuration.protocolClasses = @[LocalProtocol.class];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:configuration];
    int failed = 0;
    for (NSString *path in @[@"/ads", @"/esperanto/metadata/load"]) {
        dispatch_semaphore_t done = dispatch_semaphore_create(0);
        __block NSData *received;
        __block NSError *failure;
        NSURL *url = [NSURL URLWithString:[@"https://spclient.wg.spotify.com" stringByAppendingString:path]];
        NSURLSessionDataTask *task = [session dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            received = data;
            failure = error;
            dispatch_semaphore_signal(done);
        }];
        [task resume];
        if (dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC))) {
            NSLog(@"FAIL real session completion timed out: %@", path);
            failed++;
            break;
        }
        BOOL blocked = SGHidden(SGKeyHideAds) && [path isEqualToString:@"/ads"];
        BOOL cancelled = [failure.domain isEqualToString:NSURLErrorDomain] && failure.code == NSURLErrorCancelled;
        if (blocked ? (!cancelled || received.length) :
            (failure != nil || ![received isEqual:[@"ok" dataUsingEncoding:NSUTF8StringEncoding]])) {
            NSLog(@"FAIL real session %@ blocked=%d data=%@ error=%@", path, blocked, received, failure);
            failed++;
        }
    }
    [session invalidateAndCancel];
    printf("real session: Hide ads=%d failures=%d\n", SGHidden(SGKeyHideAds), failed);
    return failed ? EXIT_FAILURE : EXIT_SUCCESS;
}

static int failures;
static void request(NSString *address, BOOL fallback, BOOL blocked) {
    ProbeTask *task = class_createInstance(ProbeTask.class, 0);
    NSURLRequest *req = [NSURLRequest requestWithURL:[NSURL URLWithString:address]];
    if (fallback) task.original = req;
    else task.current = req;
    [task resume];
    if (task.sent != !blocked || task.cancelled != blocked) {
        NSLog(@"FAIL %@ fallback=%d sent=%d cancelled=%d expected block=%d",
              address, fallback, task.sent, task.cancelled, blocked);
        failures++;
    }
}
int main(void) {
    @autoreleasepool {
        if (getenv("REAL_SESSION")) {
            int result = realSession();
            int delegates = delegateSessions();
            int fallbacks = delegateFallbacks();
            return result || delegates || fallbacks;
        }
        BOOL hideAds = SGHidden(SGKeyHideAds), spoof = SGHidden(SGKeyFakePremium);
        if (hideAds) failures += chunkCosts();
        for (NSString *path in @[@"/ads", @"/v3/ads?slot=1", @"/ADS", @"/ads/v2/config",
                                @"/esperanto/com.spotify.ads.v1/Get", @"/esperanto/ad_slot/get"]) {
            for (NSNumber *fallback in @[@NO, @YES])
                request([@"https://spclient.wg.spotify.com" stringByAppendingString:path],
                        fallback.boolValue, hideAds);
        }
        request(@"https://ads.spotify.com/fetch", NO, hideAds);
        for (NSString *path in @[@"/downloads", @"/roads", @"/ads-extra",
                                @"/esperanto/metadata/load", @"/esperanto/download/get",
                                @"/login5", @"/bootstrap/v1/bootstrap"]) {
            request([@"https://spclient.wg.spotify.com" stringByAppendingString:path], NO, NO);
        }
        request(@"https://spclient.wg.spotify.com/v1/customize", NO, NO);
        started = [NSDate dateWithTimeIntervalSinceNow:-31];
        request(@"https://spclient.wg.spotify.com/v1/customize", NO, spoof);
        request(@"https://spclient.wg.spotify.com/ads", NO, hideAds);
        printf("network: Hide ads=%d Spoof Premium=%d failures=%d\n", hideAds, spoof, failures);
    }
    return failures ? EXIT_FAILURE : EXIT_SUCCESS;
}
