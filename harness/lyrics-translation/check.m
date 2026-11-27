// Checks the parts of lyrics translation that need no network: Musixmatch's community translations
// matched onto a song's lines as copies, and each translator's replies, language tags and batches.
// Replies below are made up, with no real lyrics. Exits non-zero on the first wrong answer.
#import <UIKit/UIKit.h>
#import <Security/Security.h>
#import <objc/runtime.h>
#import "Core/SGDataRoot.h"
#import "Shared/Lyrics/Lyrics.h"
#import "Shared/LyricsSources/LyricsSources.h"
#import "Shared/LyricsTranslation/AIServicesInternal.h"
#import "Settings/SGModPage.h"
#import "Redesigned/Lyrics/AutoTranslation.h"

static dispatch_semaphore_t storeEntered, storeRelease;
static BOOL holdStore;
static NSUInteger mainStoreEnumerations;
void SGLyricsTestStoreEnumeration(void) {
    if (NSThread.isMainThread) mainStoreEnumerations++;
}
NSURL *SGLyricsTestCacheRoot(void) {
    if (getenv("SG_TEST_PRELAUNCH")) return SGDataRoot(NSApplicationSupportDirectory);
    if (!NSThread.isMainThread && holdStore) {
        holdStore = NO;
        dispatch_semaphore_signal(storeEntered);
        if (dispatch_semaphore_wait(storeRelease, dispatch_time(DISPATCH_TIME_NOW, 120 * NSEC_PER_SEC))) {
            fprintf(stderr, "FAIL: main blocked behind the translation store queue\n");
            exit(1);
        }
    }
    static NSURL *root;
    if (!root) root = [[NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES] URLByAppendingPathComponent:[@"retrine-lyrics-check-" stringByAppendingString:NSUUID.UUID.UUIDString] isDirectory:YES];
    return root;
}
static BOOL deviceAvailable;
static NSArray *deviceAnswer;
static NSUInteger deviceCalls;
static NSMutableArray *heldDeviceReplies;
static NSTimeInterval titleTestClock = 100;
NSTimeInterval SGLyricsTitleTestTime(void) { return titleTestClock; }
@implementation SGOnDeviceTranslation
+ (BOOL)translationAvailable { return deviceAvailable; }
+ (BOOL)appleIntelligenceAvailable:(NSString *)languageTag { return NO; }
+ (void)translate:(NSArray<NSString *> *)lines to:(NSString *)tag done:(void (^)(NSArray<NSString *> *, NSString *))done {
    deviceCalls++;
    if (heldDeviceReplies) { [heldDeviceReplies addObject:[done copy]]; return; }
    NSArray *answer = deviceAnswer;
    dispatch_async(dispatch_get_main_queue(), ^{ done(answer, answer ? nil : @"Languages not installed"); });
}
+ (void)translateWithAppleIntelligence:(NSArray<NSString *> *)lines to:(NSString *)tag song:(NSString *)song progress:(void (^)(NSArray<NSString *> *))progress done:(void (^)(NSArray<NSString *> *, NSString *))done { done(nil, @"Not exercised"); }
@end
@implementation SGModRow
@end
@implementation SGPage
@end
static NSSet *testKeys;
static NSMutableDictionary<NSString *, NSData *> *openAIKeys;
static OSStatus keyReadFailure, keyWriteFailure, keyDeleteFailure;
static NSUInteger keyReads;
static NSData *lastStoredCredential;
static BOOL preserveTestKeys;
static void resetCredentialCaches(void) {
    preserveTestKeys = YES;
    SGGeminiForgetKey(); SGClaudeForgetKey(); SGDeepLForgetKey(); SGOpenAIForgetKeys();
    preserveTestKeys = NO;
}
// Replacing the fake Keychain represents a new fixture, not an external mutation
// that the running app is expected to detect. Retire its availability caches too.
@interface SGCredentialFixture : NSObject
@property (nonatomic, copy) NSSet *services;
@property (nonatomic, strong) NSMutableDictionary *hosts;
@end
@implementation SGCredentialFixture
- (NSSet *)services { return testKeys; }
- (void)setServices:(NSSet *)value { testKeys = value; resetCredentialCaches(); }
- (NSMutableDictionary *)hosts { return openAIKeys; }
- (void)setHosts:(NSMutableDictionary *)value { openAIKeys = value; resetCredentialCaches(); }
@end
static SGCredentialFixture *credentialFixture(void) {
    static SGCredentialFixture *fixture;
    if (!fixture) fixture = [SGCredentialFixture new];
    return fixture;
}
OSStatus SGLyricsTestKey(CFDictionaryRef query, CFTypeRef *result) {
    keyReads++;
    NSDictionary *item = (__bridge NSDictionary *)query;
    NSString *service = item[(__bridge id)kSecAttrService];
    if (keyReadFailure) return keyReadFailure;
    if (![testKeys containsObject:service]) return errSecItemNotFound;
    NSData *data = [@"offline-test-key" dataUsingEncoding:NSUTF8StringEncoding];
    if ([service isEqual:@"Vitrine.OpenAI"]) {
        if ([item[(__bridge id)kSecReturnAttributes] boolValue]) {
            NSMutableArray *items = [NSMutableArray array];
            for (NSString *account in openAIKeys) [items addObject:@{(__bridge id)kSecAttrAccount:account}];
            if (result) *result = CFBridgingRetain(items);
            return errSecSuccess;
        }
        data = openAIKeys[item[(__bridge id)kSecAttrAccount]];
        if (!data) return errSecItemNotFound;
    }
    if (result) *result = CFBridgingRetain(data);
    return errSecSuccess;
}
OSStatus SGLyricsTestKeyAdd(CFDictionaryRef query, CFTypeRef *result) {
    NSDictionary *item = (__bridge NSDictionary *)query;
    NSString *service = item[(__bridge id)kSecAttrService], *account = item[(__bridge id)kSecAttrAccount];
    if (keyWriteFailure) return keyWriteFailure;
    lastStoredCredential = item[(__bridge id)kSecValueData];
    testKeys = [testKeys ?: [NSSet set] setByAddingObject:service];
    if (![service isEqual:@"Vitrine.OpenAI"]) return errSecSuccess;
    if (openAIKeys[account]) return errSecDuplicateItem;
    openAIKeys[account] = ((__bridge NSDictionary *)query)[(__bridge id)kSecValueData];
    return errSecSuccess;
}
OSStatus SGLyricsTestKeyUpdate(CFDictionaryRef query, CFDictionaryRef attributes) {
    NSString *account = ((__bridge NSDictionary *)query)[(__bridge id)kSecAttrAccount];
    if (keyWriteFailure) return keyWriteFailure;
    NSString *service = ((__bridge NSDictionary *)query)[(__bridge id)kSecAttrService];
    if (![service isEqual:@"Vitrine.OpenAI"]) {
        if (![testKeys containsObject:service]) return errSecItemNotFound;
        lastStoredCredential = ((__bridge NSDictionary *)attributes)[(__bridge id)kSecValueData];
        return errSecSuccess;
    }
    if (!openAIKeys[account]) return errSecItemNotFound;
    NSString *renamed = ((__bridge NSDictionary *)attributes)[(__bridge id)kSecAttrAccount];
    if (renamed) {
        if (openAIKeys[renamed]) return errSecDuplicateItem;
        openAIKeys[renamed] = openAIKeys[account];
        [openAIKeys removeObjectForKey:account];
        return errSecSuccess;
    }
    openAIKeys[account] = ((__bridge NSDictionary *)attributes)[(__bridge id)kSecValueData];
    return errSecSuccess;
}
OSStatus SGLyricsTestKeyDelete(CFDictionaryRef query) {
    if (preserveTestKeys) return errSecSuccess;
    NSDictionary *item = (__bridge NSDictionary *)query;
    NSString *service = item[(__bridge id)kSecAttrService], *account = item[(__bridge id)kSecAttrAccount];
    if (keyDeleteFailure) return keyDeleteFailure;
    if (![service isEqual:@"Vitrine.OpenAI"]) {
        NSMutableSet *kept = [testKeys mutableCopy];
        [kept removeObject:service]; testKeys = kept;
        return errSecSuccess;
    }
    if (!account) { [openAIKeys removeAllObjects]; return errSecSuccess; }
    if (!openAIKeys[account]) return errSecItemNotFound;
    [openAIKeys removeObjectForKey:account];
    return errSecSuccess;
}
#define testKeys credentialFixture().services
#define openAIKeys credentialFixture().hosts
SGModRow *SGMenuRow(NSString *t, NSArray *c, NSString *(^v)(void), void (^chosen)(NSInteger)) { SGModRow *r = [SGModRow new]; r.title = t; r.menu = c; r.value = v; r.chosen = chosen; return r; }
SGModRow *SGChoiceRow(NSString *t, NSString *s, NSString *k, NSArray *c, NSInteger f) { return nil; }
SGModRow *SGPageRow(NSString *t, UIViewController *(^page)(void)) { SGModRow *r = [SGModRow new]; r.title = t; r.page = page; return r; }
// What the files reach outside what is checked here; none of it is called.
@implementation SGLyricsResult
@end
void SGLyricsNoteReply(NSURLResponse *response, NSError *error) {}
SGLyricsResult *SGLyricsPlainResult(NSArray<NSString *> *rows) { return nil; }
static NSString *testLanguage;
NSString *SGLyricsTranslationLanguage(void) { return testLanguage; }
SGModRow *SGStatActionRow(NSString *t, NSString *s, NSString *(^v)(void), void (^a)(void)) { SGModRow *r = [SGModRow new]; r.title = t; r.subtitle = s; r.value = v; r.action = a; return r; }
SGModRow *SGOptionRow(NSString *t, NSString *s, NSString *k) { return nil; }
SGModRow *SGSwitchRow(NSString *t, NSString *s, NSString *k) { SGModRow *r = [SGModRow new]; r.title = t; r.subtitle = s; r.key = k; return r; }
id SGKaraokeTrackFor(NSString *trackID) { return nil; }
static BOOL bingEnabled, googleEnabled, titlesEnabled, autoRetryEnabled;
NSString *SGKaraokePlayingTrack(void) { return nil; }
NSInteger SGInt(NSString *key, NSInteger fallback) { return fallback; }
BOOL SGFlag(NSString *key, BOOL fallback) { return [key isEqual:SGRKeyLyricsAutoTranslation] ? autoRetryEnabled : [key isEqual:SGKeyLyricsBingTranslate] ? bingEnabled : [key isEqual:SGKeyLyricsGoogleTranslate] ? googleEnabled : [key isEqual:SGKeyLyricsTranslateTitles] ? titlesEnabled : fallback; }
BOOL SGHidden(NSString *key) { return SGFlag(key, NO); }
static UIAlertController *keyPrompt;
@interface SGKeyPresenter : UIViewController
@end
@implementation SGKeyPresenter
- (void)presentViewController:(UIViewController *)controller animated:(BOOL)animated completion:(void (^)(void))done {
    keyPrompt = (UIAlertController *)controller;
    if (done) done();
}
@end
static UIViewController *testPresenter;
UIViewController *SGTopController(void) { return testPresenter; }
UIViewController *SGSavedTranslationsPage(void) {
    UIViewController *library = [UIViewController new]; library.title = @"Saved library fixture"; return library;
}
void SGShowPage(UIViewController *owner, UIViewController *page) {}

#define CHECK(cond) do { if (!(cond)) { fprintf(stderr, "FAILED line %d: %s\n", __LINE__, #cond); exit(1); } } while (0)

// Offline jobs use scripted replies; only --bing-live permits a network request.
static BOOL bingLive;
static NSMutableArray *aiReplies;
static NSUInteger aiRequests;
static NSURLRequest *lastAIRequest;
static BOOL duplicateAIReply;
static void (^beforeAIReply)(void);
static BOOL aiBusyFirst;
// Model lists go through the one-shot transport, which has no reply script of its own. An error here is
// handed to the production job as its NSError, which is what the app receives from a refused request.
static NSError *modelListFailure;
// The connection check scripts the same one-shot transport through this block; nil keeps the error-only fake.
static NSURLSessionDataTask * (^connectionModelTransport)(NSURLRequest *, NSUInteger, void (^)(NSData *, NSInteger, NSError *));
// A scripted, manually answered transport for the multi-page model list, which holds each page's completion
// and its task so a test decides the order and can cancel between pages.
@interface SGModelListFakeTask : NSObject
@property BOOL cancelled;
@end
@implementation SGModelListFakeTask
- (void)cancel { self.cancelled = YES; }
@end
static BOOL modelPageScripted;
static NSMutableArray<NSURLRequest *> *modelPageRequests;
static NSMutableArray *modelPageCompletions;
static NSMutableArray<SGModelListFakeTask *> *modelPageTasks;
static void modelPageDeliverData(NSUInteger index, NSData *data, NSInteger status, NSError *error) {
    CHECK(index < modelPageCompletions.count);
    void (^done)(NSData *, NSInteger, NSError *) = modelPageCompletions[index];
    modelPageCompletions[index] = [^{} copy];
    done(data, status, error);
}
static void modelPageDeliver(NSUInteger index, id root, NSInteger status, NSError *error) {
    NSData *data = root ? [NSJSONSerialization dataWithJSONObject:root options:0 error:nil] : nil;
    modelPageDeliverData(index, data, status, error);
}
NSURLSessionDataTask *SGLyricsTranslationSendOnceUpTo(NSURLRequest *request, NSUInteger limit,
                                                      void (^done)(NSData *, NSInteger, NSError *)) {
    CHECK(NSThread.isMainThread && limit == 8 * 1024 * 1024);
    if (modelPageScripted) {
        SGModelListFakeTask *task = [SGModelListFakeTask new];
        [modelPageRequests addObject:request];
        [modelPageCompletions addObject:[done copy]];
        [modelPageTasks addObject:task];
        return (id)task;
    }
    if (connectionModelTransport) return connectionModelTransport(request, limit, done);
    NSError *failure = modelListFailure;
    dispatch_async(dispatch_get_main_queue(), ^{ done(nil, 0, failure); });
    return nil;
}
static NSUInteger bingGets, bingPosts;
static NSMutableArray *bingReplies;
static BOOL disableOnReply;
static NSString *const bingHTML = @"<div data-iid=\"translator.1\"></div><script>IG: \"abc&def\"; params_AbusePreventionHelper = [1234567890123,\"token&+=%\",3600000];</script>";

// Exercise Gemini's real job/cache without allowing its NSURLSession to reach the network.
static NSMutableArray *geminiTitleReplies;
static NSUInteger geminiTitleRequests;
static NSURLRequest *lastGeminiRequest;
static NSInteger geminiTitleStatus;   // 0: 200
static void (^beforeGeminiReply)(void);
@interface SGGeminiTitleProtocol : NSURLProtocol
@end
@implementation SGGeminiTitleProtocol
+ (BOOL)canInitWithRequest:(NSURLRequest *)request { return [request.URL.host isEqual:@"generativelanguage.googleapis.com"]; }
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request { return request; }
- (void)startLoading {
    dispatch_async(dispatch_get_main_queue(), ^{
        CHECK(geminiTitleReplies.count > 0);
        geminiTitleRequests++;
        NSMutableURLRequest *captured = [self.request mutableCopy];
        if (!captured.HTTPBody) {
            NSInputStream *stream = self.request.HTTPBodyStream;
            CHECK(stream);
            NSMutableData *body = [NSMutableData data];
            [stream open];
            uint8_t buffer[4096];
            NSInteger length;
            while ((length = [stream read:buffer maxLength:sizeof(buffer)]) > 0) [body appendBytes:buffer length:(NSUInteger)length];
            CHECK(length == 0 && !stream.streamError);
            [stream close];
            captured.HTTPBody = body;
        }
        lastGeminiRequest = captured;
        id reply = geminiTitleReplies.firstObject;
        [geminiTitleReplies removeObjectAtIndex:0];
        if ([reply isKindOfClass:NSError.class]) {
            [self.client URLProtocol:self didFailWithError:reply];
            return;
        }
        id root = [reply isKindOfClass:NSString.class] ? @{@"candidates": @[@{@"content": @{@"parts": @[@{@"text": reply}]}, @"finishReason": @"STOP"}]} : reply;
        NSData *data = [NSJSONSerialization dataWithJSONObject:root options:0 error:nil];
        if (beforeGeminiReply) beforeGeminiReply();
        NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:self.request.URL statusCode:geminiTitleStatus ?: 200 HTTPVersion:@"HTTP/1.1" headerFields:@{@"Content-Type": @"application/json"}];
        [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
        [self.client URLProtocol:self didLoadData:data];
        [self.client URLProtocolDidFinishLoading:self];
    });
}
- (void)stopLoading {}
@end

// DeepL.m keeps its own transport (the build renames only the symbol the other translators share), so its jobs
// are routed into this protocol by giving every ephemeral session configuration it creates the protocol.
static NSMutableArray<NSNumber *> *deepLStatuses;   // one per request; 200 answers one translated line
static NSUInteger deepLRequests;
static void (^beforeDeepLReply)(void);
@interface SGDeepLProtocol : NSURLProtocol
@end
@implementation SGDeepLProtocol
+ (BOOL)canInitWithRequest:(NSURLRequest *)request { return [request.URL.host hasSuffix:@"deepl.com"]; }
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request { return request; }
- (void)startLoading {
    dispatch_async(dispatch_get_main_queue(), ^{
        CHECK(deepLStatuses.count > 0);
        deepLRequests++;
        NSInteger status = deepLStatuses.firstObject.integerValue;
        [deepLStatuses removeObjectAtIndex:0];
        if (beforeDeepLReply) beforeDeepLReply();
        NSData *data = [NSJSONSerialization dataWithJSONObject:@{@"translations": @[@{@"text": @"로봇"}]} options:0 error:nil];
        NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:self.request.URL statusCode:status HTTPVersion:@"HTTP/1.1" headerFields:@{@"Content-Type": @"application/json"}];
        [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
        [self.client URLProtocol:self didLoadData:data];
        [self.client URLProtocolDidFinishLoading:self];
    });
}
- (void)stopLoading {}
@end
static IMP realEphemeralConfiguration;
static void routeEphemeralSessionsToDeepL(BOOL on) {
    Method method = class_getClassMethod(NSURLSessionConfiguration.class, @selector(ephemeralSessionConfiguration));
    if (!on) { method_setImplementation(method, realEphemeralConfiguration); return; }
    realEphemeralConfiguration = method_getImplementation(method);
    IMP routed = imp_implementationWithBlock(^NSURLSessionConfiguration *(id receiver) {
        NSURLSessionConfiguration *config = ((NSURLSessionConfiguration *(*)(id, SEL))realEphemeralConfiguration)(receiver, @selector(ephemeralSessionConfiguration));
        config.protocolClasses = @[SGDeepLProtocol.class, SGGeminiTitleProtocol.class];
        return config;
    });
    method_setImplementation(method, routed);
}

// Stand-in for LyricsSources.m's transport, whose unrelated provider registry is not linked here.
// The optional live check retains its 2 MiB bound, ephemeral storage and redirect refusal.
@interface BingPageRequest : NSObject <NSURLSessionDataDelegate>
@property (nonatomic, strong) NSMutableData *data;
@property (nonatomic) NSInteger status;
@property (nonatomic, copy) void (^done)(NSData *, NSInteger);
@end
@implementation BingPageRequest
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveResponse:(NSURLResponse *)response completionHandler:(void (^)(NSURLSessionResponseDisposition))completion {
    self.status = [(NSHTTPURLResponse *)response statusCode];
    completion(response.expectedContentLength > 2 * 1024 * 1024 ? NSURLSessionResponseCancel : NSURLSessionResponseAllow);
}
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveData:(NSData *)data {
    if (data.length > 2 * 1024 * 1024 - self.data.length) { [task cancel]; return; }
    [self.data appendData:data];
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task willPerformHTTPRedirection:(NSHTTPURLResponse *)response newRequest:(NSURLRequest *)request completionHandler:(void (^)(NSURLRequest *))completion { completion(nil); }
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    void (^done)(NSData *, NSInteger) = self.done;
    self.done = nil;
    [session finishTasksAndInvalidate];
    if (done) done(error ? nil : self.data, self.status);
}
@end
void SGLyricsSourceRequest(NSURL *url, NSDictionary<NSString *, NSString *> *headers, NSData *body, void (^done)(NSData *, NSInteger)) {
    CHECK(NSThread.isMainThread && bingEnabled && !body);
    CHECK([url.absoluteString isEqual:@"https://www.bing.com/translator"]);
    CHECK([headers[@"Accept"] isEqual:@"text/html"]);
    bingGets++;
    if (!bingLive) {
        dispatch_async(dispatch_get_main_queue(), ^{ done([bingHTML dataUsingEncoding:NSUTF8StringEncoding], 200); });
        return;
    }
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.allHTTPHeaderFields = headers;
    request.HTTPShouldHandleCookies = NO;
    request.timeoutInterval = 60;
    NSURLSessionConfiguration *config = NSURLSessionConfiguration.ephemeralSessionConfiguration;
    config.HTTPCookieStorage = nil; config.URLCredentialStorage = nil; config.URLCache = nil;
    config.timeoutIntervalForResource = 60;
    BingPageRequest *receiver = [BingPageRequest new];
    receiver.data = [NSMutableData data]; receiver.done = done;
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config delegate:receiver delegateQueue:NSOperationQueue.mainQueue];
    [[session dataTaskWithRequest:request] resume];
}
// DeepL.m is compiled with just this transport symbol renamed so the production implementation
// stays available for the explicit live run, while offline Bing jobs can receive scripted replies.
void SGLyricsTranslationRealSendRequest(NSURLRequest *, BOOL, BOOL (^)(void), void (^)(NSData *, NSInteger, NSError *));
static NSMutableArray *googleForms, *googleReplies;
void SGLyricsTranslationSendRequest(NSURLRequest *request, BOOL retry, BOOL (^allowed)(void), void (^done)(NSData *, NSInteger, NSError *)) {
    if ([request.URL.host isEqual:@"translate.googleapis.com"]) {
        CHECK(NSThread.isMainThread && retry && allowed && allowed() && googleReplies.count);
        [googleForms addObject:[[NSString alloc] initWithData:request.HTTPBody encoding:NSUTF8StringEncoding]];
        id reply = googleReplies.firstObject;
        [googleReplies removeObjectAtIndex:0];
        dispatch_async(dispatch_get_main_queue(), ^{ done([NSJSONSerialization dataWithJSONObject:reply options:0 error:nil], 200, nil); });
        return;
    }
    if (![request.URL.host isEqual:@"www.bing.com"]) {
        CHECK(NSThread.isMainThread && retry && allowed && allowed() && aiReplies.count);
        CHECK([request.HTTPMethod isEqual:@"POST"] && request.HTTPBody.length <= 1024 * 1024);
        lastAIRequest = request; aiRequests++;
        id reply = aiReplies.firstObject;
        [aiReplies removeObjectAtIndex:0];
        dispatch_async(dispatch_get_main_queue(), ^{
            NSData *data = [NSJSONSerialization dataWithJSONObject:reply options:0 error:nil];
            if (beforeAIReply) beforeAIReply();
            if (aiBusyFirst) {
                // The transport's 429 path: the service is asked again after a delay, and `allowed` decides whether it is.
                aiBusyFirst = NO;
                if (!allowed()) { done(nil, 0, [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCancelled userInfo:nil]); return; }
                aiRequests++;
            }
            done(data, 200, nil);
            if (duplicateAIReply) done(data, 200, nil);
        });
        return;
    }
    CHECK(NSThread.isMainThread && allowed && allowed() && retry);
    CHECK([request.HTTPMethod isEqual:@"POST"]);
    CHECK([request.URL.host isEqual:@"www.bing.com"]);
    CHECK([request valueForHTTPHeaderField:@"Origin"] && [request valueForHTTPHeaderField:@"Referer"]);
    bingPosts++;
    if (bingLive) { SGLyricsTranslationRealSendRequest(request, retry, allowed, done); return; }
    CHECK([request.URL.absoluteString containsString:@"IG=abc%26def&IID=translator.1"]);
    CHECK(([request.URL.absoluteString containsString:[NSString stringWithFormat:@"&SFX=%lu&", (unsigned long)bingPosts]]));
    NSString *body = [[NSString alloc] initWithData:request.HTTPBody encoding:NSUTF8StringEncoding];
    CHECK([body containsString:@"&token=token%26%2B%3D%25&key=1234567890123&to=ko&"]);
    if (bingPosts <= 3) CHECK([body containsString:@"text=A%20%26%2B%3D%25%20%ED%95%9C%F0%9F%98%80"]);
    CHECK(![body containsString:@"[Chorus]"] && ![body containsString:@"%E2%99%AA"]);
    CHECK(bingReplies.count);
    id reply = bingReplies.firstObject;
    [bingReplies removeObjectAtIndex:0];
    dispatch_async(dispatch_get_main_queue(), ^{
        if (disableOnReply) bingEnabled = NO;
        done([NSJSONSerialization dataWithJSONObject:reply options:0 error:nil], 200, nil);
    });
}
static id bingReply(NSString *text) { return @[@{@"translations": @[@{@"text": text}]}]; }
static NSArray *bingAsk(NSString *track, NSArray *texts, NSString **problem) {
    __block BOOL finished = NO;
    __block NSUInteger calls = 0;
    __block NSArray *result;
    __block NSString *error;
    NSMutableArray *lines = [NSMutableArray array];
    for (NSString *text in texts) {
        SGKaraokeWord *word = [SGKaraokeWord new]; word.text = text;
        SGKaraokeLine *line = [SGKaraokeLine new]; line.words = @[word];
        [lines addObject:line];
    }
    SGLyricsTranslateWithBing(track, lines, @"ko-KR", ^(NSArray *translated, NSString *message) {
        CHECK(NSThread.isMainThread && ++calls == 1);
        result = translated; error = message; finished = YES;
    });
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:90];
    while (!finished && deadline.timeIntervalSinceNow > 0) [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    CHECK(finished);
    *problem = error;
    return result;
}
static void checkBing(void) {
    CHECK([SGBingTargetLanguage(@"zh-Hans-CN") isEqual:@"zh-Hans"]);
    CHECK([SGBingTargetLanguage(@"zh-CN") isEqual:@"zh-Hans"]);
    CHECK([SGBingTargetLanguage(@"zh_Hant_TW") isEqual:@"zh-Hant"]);
    CHECK([SGBingTargetLanguage(@"zh-TW") isEqual:@"zh-Hant"]);
    CHECK([SGBingTargetLanguage(@"PT-PT") isEqual:@"pt-PT"]);
    CHECK([SGBingTargetLanguage(@"pt-BR") isEqual:@"pt"]);
    CHECK([SGBingTargetLanguage(@"HE-IL") isEqual:@"he"]);
    CHECK([SGBingTargetLanguage(@"nb-NO") isEqual:@"nb"]);
    CHECK([SGBingTargetLanguage(@"ko_KR") isEqual:@"ko"]);
    for (id bad in @[@"", @"en--US", @"en&to=ko", @" 한 ", @42, NSNull.null, [@"a" stringByPaddingToLength:65 withString:@"a" startingAtIndex:0]]) CHECK(!SGBingTargetLanguage(bad));
    CHECK(!SGBingTargetLanguage(nil));
    NSDictionary *configuration = SGBingConfigurationIn(bingHTML);
    CHECK([configuration[@"ig"] isEqual:@"abc&def"] && [configuration[@"iid"] isEqual:@"translator.1"]);
    CHECK([configuration[@"key"] longLongValue] == 1234567890123 && [configuration[@"seconds"] doubleValue] == 3600);
    CHECK([configuration[@"token"] isEqual:@"token&+=%"]);
    for (NSString *marker in @[@"IG:", @"data-iid", @"params_AbusePreventionHelper"]) CHECK(!SGBingConfigurationIn([bingHTML stringByReplacingOccurrencesOfString:marker withString:@"missing"]));
    for (NSString *tuple in @[@"[]", @"[1]", @"[true,\"x\"]", @"[1.5,\"x\"]", @"[-1,\"x\"]", @"[9223372036854775808,\"x\"]", @"[\"123\",\"x\"]", @"[1,42]", @"[1,\"\"]", @"[1,null]", @"[1,\"x\",\"600\"]", @"[1,\"x\",true]", @"[1,\"x\",-1]", @"[1,\"x\",null]", @"[1,\"x\",600,7]"]) {
        CHECK(!SGBingConfigurationIn([NSString stringWithFormat:@"IG:\"x\" data-iid=\"y\" params_AbusePreventionHelper = %@;", tuple]));
    }
    CHECK([SGBingConfigurationIn(@"IG:\"x\" data-iid=\"y\" params_AbusePreventionHelper=[1,\"x\"]")[@"seconds"] doubleValue] == 600);
    CHECK([SGBingConfigurationIn(@"IG:\"x\" data-iid=\"y\" params_AbusePreventionHelper=[1,\"x\",1000]")[@"seconds"] doubleValue] == 60);
    CHECK([SGBingConfigurationIn(@"IG:\"x\" data-iid=\"y\" params_AbusePreventionHelper=[9223372036854775807,\"x\"]")[@"key"] longLongValue] == LLONG_MAX);
    CHECK(!SGBingConfigurationIn((id)@42));
    NSString *text = SGBingTranslationTextIn(bingReply(@"  밤에 달려가  \r\n고마워\t \r♪  "));
    CHECK(([[text componentsSeparatedByString:@"\n"] isEqual:@[@"  밤에 달려가", @"고마워", @"♪"]]));
    CHECK([SGBingTranslationTextIn(bingReply(@"A\nB\n")) hasSuffix:@"\n"]);
    CHECK([SGBingTranslationTextIn(bingReply(@"")) isEqual:@""]);
    CHECK(!SGBingTranslationTextIn(bingReply([@"x" stringByPaddingToLength:128001 withString:@"x" startingAtIndex:0])));
    for (id bad in @[NSNull.null, @{}, @[], @[NSNull.null], @[@{}], @[@{@"translations": @[]}], @[@{@"translations": @[NSNull.null]}], @[@{@"translations": @[@{@"text": @7}]}]]) CHECK(!SGBingTranslationTextIn(bad));
    CHECK(SGBingTokenRefused(@{@"statusCode": @205, @"errorMessage": @""}));
    CHECK(!SGBingTokenRefused(@{}) && !SGBingTokenRefused(bingReply(@"A")) && !SGBingTokenRefused(NSNull.null));
    NSMutableArray *many = [NSMutableArray array];
    for (NSUInteger i = 0; i < 41; i++) [many addObject:@"A"];
    NSArray *batches = SGLyricsTranslationBatches(many, 40, 2800);
    CHECK(batches.count == 2 && [batches[0] count] == 40 && [batches[1] count] == 1);
    NSString *full = [@"A" stringByPaddingToLength:2800 withString:@"A" startingAtIndex:0];
    CHECK(([SGLyricsTranslationBatches(@[full, @"B"], 40, 2800) isEqual:@[@[@0], @[@1]]]));
    CHECK(!SGLyricsTranslationBatches(@[[full stringByAppendingString:@"A"]], 40, 2800));
    // A refused token is refreshed once; a merged reply then falls back to individual source lines.
    bingEnabled = YES;
    bingReplies = [@[@{@"statusCode": @205}, bingReply(@"merged"), bingReply(@"하나  "), bingReply(@"둘\t ")] mutableCopy];
    NSString *problem;
    NSArray *source = @[@"A &+=% 한😀", @" ♪ ", @" [Chorus] ", @"B"];
    NSArray *got = bingAsk(@"offline-fallback", source, &problem);
    CHECK(!problem && ([got isEqual:@[@"하나", @" ♪ ", @" [Chorus] ", @"둘"]]));
    CHECK(bingGets == 2 && bingPosts == 4 && !bingReplies.count);
    CHECK([bingAsk(@"offline-fallback", source, &problem) isEqual:got] && bingPosts == 4 && bingGets == 2);
    bingReplies = [@[bingReply(@"새로  \n둘  ")] mutableCopy];
    CHECK(bingAsk(@"offline-fallback", @[@"changed", @"B"], &problem) && !problem && bingPosts == 5 && bingGets == 2);
    bingReplies = [@[bingReply(@"안\n녕  "), bingReply(@"둘 ")] mutableCopy];
    CHECK(([bingAsk(nil, @[@"A\nB", @"C"], &problem) isEqual:@[@"안\n녕", @"둘"]]) && !problem);
    bingReplies = [@[@{@"statusCode": @205}, @{@"statusCode": @205}] mutableCopy];
    NSUInteger before = bingPosts;
    CHECK(!bingAsk(nil, @[@"A"], &problem) && [problem containsString:@"token"] && bingPosts == before + 2);
    disableOnReply = YES;
    bingReplies = [@[bingReply(@"ignored")] mutableCopy];
    CHECK(!bingAsk(nil, @[@"A"], &problem) && [problem containsString:@"Turn on"]);
    disableOnReply = NO;
    before = bingPosts;
    CHECK(!bingAsk(nil, @[@"A"], &problem) && [problem containsString:@"Turn on"] && bingPosts == before);
    puts("Bing: language, configuration, bounds, padded lines, token retry, fallback, opt-in, memo and main completion checks passed");
}

static NSArray<NSString *> *readReply(NSString *json, NSInteger status, NSUInteger count, NSString **problem) {
    *problem = nil;
    id root = [NSJSONSerialization JSONObjectWithData:[json dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
    return SGGeminiTranslationsIn(root, status, nil, count, problem);
}

static id json(NSString *text) {
    return [NSJSONSerialization JSONObjectWithData:[text dataUsingEncoding:NSUTF8StringEncoding] options:NSJSONReadingFragmentsAllowed error:nil];
}
static id chatReply(NSString *content) {
    return @{@"choices": @[@{@"message": @{@"content": content}, @"finish_reason": @"stop"}]};
}
static void checkProviders(void) {
    CHECK([SGDeepLTargetLanguage(@"zh-Hans-CN") isEqual:@"ZH-HANS"]);
    CHECK([SGDeepLTargetLanguage(@"zh-Hant") isEqual:@"ZH-HANT"]);
    CHECK([SGDeepLTargetLanguage(@"pt") isEqual:@"PT-BR"]);
    CHECK([SGDeepLTargetLanguage(@"pt-PT") isEqual:@"PT-PT"]);
    CHECK([SGDeepLTargetLanguage(@"en") isEqual:@"EN-US"]);
    CHECK([SGDeepLTargetLanguage(@"en-GB") isEqual:@"EN-GB"]);
    CHECK([SGDeepLTargetLanguage(@"nb-NO") isEqual:@"NB"]);
    CHECK([SGDeepLTargetLanguage(@"ko_KR") isEqual:@"KO"]);
    CHECK(!SGDeepLTargetLanguage(@"xx") && !SGDeepLTargetLanguage(@"en--US") && !SGDeepLTargetLanguage(nil));
    CHECK(!SGDeepLTargetLanguage((id)@42));
    CHECK(( [SGDeepLTranslationsIn(json(@"{\"translations\":[{\"text\":\"sample A\"},{\"text\":\"sample B\"}]}"), 2) isEqual:@[@"sample A", @"sample B"]] ));
    for (NSString *bad in @[@"null", @"[]", @"{}", @"{\"translations\":null}", @"{\"translations\":[null]}", @"{\"translations\":[{\"text\":7}]}", @"{\"translations\":[{\"text\":null}]}" ]) {
        CHECK(!SGDeepLTranslationsIn(json(bad), 1));
    }
    CHECK(!SGDeepLTranslationsIn(json(@"{\"translations\":[{\"text\":\"sample\"}]}"), 2));

    // The 51st nonblank line starts a new DeepL request without shifting any original indices.
    NSMutableArray *many = [NSMutableArray arrayWithObject:@""];
    for (NSUInteger i = 0; i < 51; i++) [many addObject:[NSString stringWithFormat:@"sample %lu", (unsigned long)i]];
    NSArray *batches = SGLyricsTranslationBatches(many, 50, 16000);
    CHECK(batches.count == 2 && [batches[0] count] == 50 && [batches[1] count] == 1);
    CHECK(( [batches[0][0] isEqual:@1] && [batches[1][0] isEqual:@51] ));
    CHECK(( [SGLyricsTranslationBatches(@[@"A", @" ", @"B", @"C"], 50, 3) isEqual:@[@[@0, @2], @[@3]]] ));
    CHECK(( [SGLyricsTranslationBatches(@[@"", @" ", @"\n"], 50, 3500) count] == 0 ));
    CHECK(!SGLyricsTranslationBatches(@[@"A"], 0, 3500));
    CHECK(!SGLyricsTranslationBatches(@[@"A"], 50, 0));
    CHECK(!SGLyricsTranslationBatches((id)@[@42], 50, 3500));
    NSString *full = [@"A" stringByPaddingToLength:3500 withString:@"A" startingAtIndex:0];
    CHECK(( [SGLyricsTranslationBatches(@[full, @"B"], 2000, 3500) isEqual:@[@[@0], @[@1]]] ));
    CHECK(!SGLyricsTranslationBatches(@[[full stringByAppendingString:@"A"]], 2000, 3500));
    CHECK(( [SGLyricsTranslationBatches(@[@"😀", @"界"], 2000, 4) isEqual:@[@[@0, @1]]] ));
    NSMutableArray *tooMany = [NSMutableArray array];
    for (NSUInteger i = 0; i < 2001; i++) [tooMany addObject:@""];
    CHECK(!SGLyricsTranslationBatches(tooMany, 50, 3500));
    NSMutableArray *tooLong = [NSMutableArray array];
    for (NSUInteger i = 0; i < 40; i++) [tooLong addObject:full];
    CHECK(!SGLyricsTranslationBatches(tooLong, 50, 3500));

    CHECK([SGGoogleTargetLanguage(@"zh-Hans") isEqual:@"zh-CN"]);
    CHECK([SGGoogleTargetLanguage(@"zh-Hant-TW") isEqual:@"zh-TW"]);
    CHECK([SGGoogleTargetLanguage(@"he-IL") isEqual:@"iw"]);
    CHECK([SGGoogleTargetLanguage(@"nb") isEqual:@"no"]);
    CHECK([SGGoogleTargetLanguage(@"pt-BR") isEqual:@"pt-BR"]);
    CHECK(!SGGoogleTargetLanguage(@"en&tl=xx") && !SGGoogleTargetLanguage(@"en--US"));
    CHECK(SGGoogleKeepsLine(@"♪") && SGGoogleKeepsLine(@" ♪ ♪ ") && SGGoogleKeepsLine(@" [Chorus] "));
    CHECK(!SGGoogleKeepsLine(@"♪ sample") && !SGGoogleKeepsLine(@"[sample] words") && !SGGoogleKeepsLine(@"[A] [B]"));
    CHECK(!SGGoogleKeepsLine(@"[]") && !SGGoogleKeepsLine(@" "));
    id google = json(@"[[[\"sample A\\n\",\"source\",null],[\"sample B\",\"source\"]],null,\"en\"]");
    CHECK(( [SGGoogleTranslationLinesIn(google, 2) isEqual:@[@"sample A", @"sample B"]] ));
    CHECK(!SGGoogleTranslationLinesIn(google, 3));
    CHECK(( [SGGoogleTranslationLinesIn(@[@[@[@"A\r\nB"]]], 2) isEqual:@[@"A", @"B"]] ));
    CHECK(!SGGoogleTranslationLinesIn(@[@[@[@"A\nB\n"]]], 2));
    CHECK([SGGoogleTranslationTextIn(@[@[@[@"A\nB"]]]) isEqual:@"A\nB"]); // a single source line can contain newlines
    for (NSString *bad in @[@"null", @"{}", @"[]", @"[null]", @"[[]]", @"[[null]]", @"[[[]]]", @"[[[null]]]", @"[[[42]]]", @"[[[\"A\"],null]]"]) {
        CHECK(!SGGoogleTranslationTextIn(json(bad)));
    }
    NSString *oversized = [@"A" stringByPaddingToLength:128001 withString:@"A" startingAtIndex:0];
    CHECK(!SGGoogleTranslationTextIn(@[@[@[oversized]]]));
    CHECK(!SGDeepLTranslationsIn(@{@"translations": @[@{@"text": oversized}]}, 1));
    NSString *form = [[NSString alloc] initWithData:SGGoogleTranslationForm(@"A &+=%\n한😀", @"he") encoding:NSUTF8StringEncoding];
    CHECK([form isEqual:@"client=gtx&sl=auto&tl=iw&dt=t&q=A%20%26%2B%3D%25%0A%ED%95%9C%F0%9F%98%80"]);
    CHECK(!SGGoogleTranslationForm([full stringByAppendingString:@"A"], @"en"));

    CHECK([SGOpenAICompletionURL(@"https://api.openai.com/v1/").absoluteString isEqual:@"https://api.openai.com/v1/chat/completions"]);
    CHECK(SGOpenAICompletionURL(@"https://openrouter.ai/api/v1"));
    CHECK(SGOpenAICompletionURL(@"http://localhost:8080/v1"));
    CHECK(SGOpenAICompletionURL(@"http://127.0.0.1:8080"));
    CHECK(SGOpenAICompletionURL(@"http://server.local/v1"));
    CHECK([SGOpenAICompletionURL(@"http://100.97.8.81:10100/v1").absoluteString isEqual:@"http://100.97.8.81:10100/v1/chat/completions"]);
    CHECK(SGOpenAICompletionURL(@"http://100.64.0.0/v1") && SGOpenAICompletionURL(@"http://100.127.255.255:65535/v1/"));
    for (NSString *bad in @[@"http://100.63.255.255/v1", @"http://100.128.0.0/v1", @"http://101.97.8.81/v1",
        @"http://100.97.8.256/v1", @"http://100.97.8/v1", @"http://100.97.8.81.example.com/v1",
        @"http://100.97.8.81:0/v1", @"http://100.97.8.81:65536/v1", @"http://user:key@100.97.8.81/v1",
        @"http://100.97.8.81/v1?key=value", @"http://100.97.8.81/v1#x", @"ftp://100.97.8.81/v1"]) CHECK(!SGOpenAICompletionURL(bad));
    for (NSString *bad in @[@"", @"http://example.com/v1", @"http://localhost.evil/v1", @"http://server.local.evil/v1", @"ftp://localhost/v1", @"https://user:secret@example.com/v1", @"https://example.com/v1?q=x", @"https://example.com/v1#x", @"https://example.com:65536/v1", @"https://exa mple.com", @"/v1"]) {
        CHECK(!SGOpenAICompletionURL(bad));
    }
    CHECK(( [SGOpenAITranslationsIn(chatReply(@"[\"A\",\"\"]"), 2) isEqual:@[@"A", @""]] ));
    CHECK(( [SGOpenAITranslationsIn(chatReply(@"```json\n[\"A\",\"B\"]\n```"), 2) isEqual:@[@"A", @"B"]] ));
    CHECK(( [SGOpenAITranslationsIn(chatReply(@" ```JSON\r\n{\"lines\":[\"A\",\"B\"]}\r\n``` "), 2) isEqual:@[@"A", @"B"]] ));
    CHECK(( [SGOpenAITranslationsIn(chatReply(@"```\n[\"A\"]\n```"), 1) isEqual:@[@"A"]] ));
    for (NSString *bad in @[@"null", @"[7]", @"[null]", @"[{}]", @"[\"A\",\"B\"]", @"{\"a\":[\"A\"],\"b\":[\"B\"]}", @"```json", @"```json\n[\"A\"]", @"```xml\n[\"A\"]\n```", @"Here: [\"A\"]"]) {
        CHECK(!SGOpenAITranslationsIn(chatReply(bad), 1));
    }
    for (NSString *bad in @[@"null", @"{}", @"{\"choices\":null}", @"{\"choices\":[null]}", @"{\"choices\":[{\"message\":null}]}", @"{\"choices\":[{\"message\":{\"content\":[]}}]}"]) {
        CHECK(!SGOpenAITranslationsIn(json(bad), 1));
    }
    CHECK(!SGOpenAITranslationsIn(chatReply([@"A" stringByPaddingToLength:256001 withString:@"A" startingAtIndex:0]), 1));
    puts("DeepL / Google / OpenAI: mapping, malformed replies, line counts, bounds, form encoding and URL checks passed");
}

#include "check-ai.m"
#include "check-storage.m"
#include "check-connection.m"
#include "check-auto-retry.m"
#include "check-kept.m"
#include "check-bing-completion.m"
#include "check-ai-gaps.m"
#include "check-prompt.m"
#include "check-gemini-guidance.m"

int main(int argc, const char **argv) {
    @autoreleasepool {
        Method ephemeral = class_getClassMethod(NSURLSessionConfiguration.class, @selector(ephemeralSessionConfiguration));
        IMP configuration = method_getImplementation(ephemeral);
        method_setImplementation(ephemeral, imp_implementationWithBlock(^NSURLSessionConfiguration *(id cls) {
            NSURLSessionConfiguration *config = ((id (*)(id, SEL))configuration)(cls, @selector(ephemeralSessionConfiguration));
            config.protocolClasses = [@[SGGeminiTitleProtocol.class] arrayByAddingObjectsFromArray:config.protocolClasses];
            return config;
        }));
        if (argc > 1 && strcmp(argv[1], "--bing-live") == 0) {
            bingLive = bingEnabled = YES;
            NSString *problem;
            NSArray *got = bingAsk(nil, @[@"The blue robot waves hello.", @"Thank you.", @" ♪ "], &problem);
            if (problem) fprintf(stderr, "Bing live: %s\n", problem.UTF8String);
            CHECK(got.count == 3 && !problem && [got[2] isEqual:@" ♪ "]);
            CHECK([got[0] rangeOfCharacterFromSet:[NSCharacterSet characterSetWithRange:NSMakeRange(0xAC00, 11172)]].location != NSNotFound);
            printf("Bing live: %lu page GET, %lu translation POST, main completion, %s\n", (unsigned long)bingGets, (unsigned long)bingPosts, [[got componentsJoinedByString:@" | "] UTF8String]);
            return 0;
        }
        if (argc > 1 && strcmp(argv[1], "--auto-retry-only") == 0) { checkAutoRetry(); return 0; }
        if (argc > 1 && strcmp(argv[1], "--ai-gaps-only") == 0) { checkAIGaps(); return 0; }
        if (argc > 1 && strcmp(argv[1], "--prompt-only") == 0) { checkTranslationPrompt(); return 0; }
        if (argc > 1 && strcmp(argv[1], "--bing-completion-only") == 0) { checkBing(); checkBingCompletion(); return 0; }
        if (argc > 1 && strcmp(argv[1], "--kept-only") == 0) { checkKeptTranslation(); return 0; }
        if (argc > 1 && strcmp(argv[1], "--storage-only") == 0) { checkDurableStorage(); return 0; }
        if (argc > 1 && strcmp(argv[1], "--startup-reclaim-only") == 0) { checkStartupReclaimRetry(); return 0; }
        if (argc > 1 && strcmp(argv[1], "--first-read-only") == 0) { checkColdDeletedAlias(); checkFirstRecordRead(); return 0; }
        if (argc > 1 && strcmp(argv[1], "--first-read-failure-only") == 0) { checkColdReadFailure(); return 0; }
        if (argc > 1 && strcmp(argv[1], "--startup-unlock-only") == 0) { checkStartupUnlock(); return 0; }
        if (argc > 1 && strcmp(argv[1], "--connection-only") == 0) { checkConnection(); return 0; }
        if (argc > 1 && strcmp(argv[1], "--gemini-memo-only") == 0) { checkGeminiMemoBound(); return 0; }
        if (argc > 1 && strcmp(argv[1], "--gemini-guidance-only") == 0) { checkGeminiGuidance(); return 0; }
        checkGeminiGuidance();
        // Musixmatch's translations go on copies of the lines they match, by the folded text.
        NSArray<SGKaraokeLine *> *lines = SGKaraokeEstimatedLines(@[@0, @2000, @4000, @6000],
                                                                  @[@"Où est l'amour ?", @"Yeah", @"Rien", @""]);
        CHECK(lines.count >= 3);
        lines[2].translation = @"Nothing";
        NSDictionary *byLine = @{SGMusixmatchLineKey(@"ou est L'AMOUR"): @"Where is love?", SGMusixmatchLineKey(@"rien"): @"None"};
        NSArray<SGKaraokeLine *> *translated = SGMusixmatchTranslatedLines(lines, byLine);
        CHECK(translated && translated != lines && translated.count == lines.count);
        CHECK([translated[0].translation isEqualToString:@"Where is love?"] && translated[0] != lines[0]);
        CHECK(!lines[0].translation);                                  // the lines kept before are left as they were
        CHECK(translated[0].start == lines[0].start && translated[0].end == lines[0].end
              && translated[0].words == lines[0].words && translated[0].timing == lines[0].timing);
        CHECK(translated[1] == lines[1] && !translated[1].translation);  // no match: the same line
        CHECK([translated[2].translation isEqualToString:@"Nothing"]);   // a translation of its own stays
        CHECK(!SGMusixmatchTranslatedLines(lines, @{@"nothing here": @"x"}));

        // Gemini's language by the whole tag, so the script survives.
        NSLocale *english = [NSLocale localeWithLocaleIdentifier:@"en"];
        CHECK(![[english localizedStringForLocaleIdentifier:@"zh-Hant"] isEqualToString:[english localizedStringForLocaleIdentifier:@"zh-Hans"]]);

        // Gemini's reply: lines, or why there are none.
        NSString *problem;
        NSArray<NSString *> *got = readReply(@"{\"candidates\":[{\"content\":{\"parts\":[{\"text\":\"[\\\"a\\\",\\\"\\\"]\"}]},\"finishReason\":\"STOP\"}]}", 200, 2, &problem);
        CHECK([got isEqualToArray:(@[@"a", @""])] && !problem);
        CHECK(!readReply(@"{\"promptFeedback\":{\"blockReason\":\"PROHIBITED_CONTENT\"}}", 200, 2, &problem) && [problem containsString:@"filters"]);
        CHECK(!readReply(@"{\"candidates\":[{\"finishReason\":\"RECITATION\"}]}", 200, 2, &problem) && [problem containsString:@"repeated"]);
        CHECK(!readReply(@"{\"candidates\":[{\"finishReason\":\"SAFETY\"}]}", 200, 2, &problem) && [problem containsString:@"filters"]);
        CHECK(!readReply(@"{\"candidates\":[{\"content\":{\"parts\":[{\"text\":\"[\\\"a\\\"]\"}]},\"finishReason\":\"STOP\"}]}", 200, 2, &problem)
              && [problem containsString:@"1 lines for the song's 2"]);
        CHECK(!readReply(@"{\"error\":{}}", 403, 2, &problem) && [problem containsString:@"key"]);
        CHECK(!readReply(@"{\"error\":{\"message\":\"API key not valid. Please pass a valid API key.\"}}", 400, 2, &problem) && [problem containsString:@"key"]);
        CHECK(!readReply(@"{\"error\":{\"message\":\"Invalid JSON payload\"}}", 400, 2, &problem) && [problem containsString:@"Invalid JSON payload"]);
        CHECK(!readReply(@"{\"error\":{}}", 503, 2, &problem) && [problem containsString:@"busy"]);
        CHECK(!readReply(@"{\"error\":{\"status\":\"UNAUTHENTICATED\"}}", 401, 2, &problem) && [problem containsString:@"key"]);
        CHECK(!readReply(@"{\"error\":{}}", 429, 2, &problem) && [problem containsString:@"limit"]);
        CHECK(!readReply(@"{}", 200, 2, &problem) && [problem containsString:@"could not be read"]);
        checkProviders();
        checkBing();
        checkNewAI();
        checkDurableStorage();
        checkModelNetworkProblems();
        checkModelFetchErrors();
        checkModelPagination();
        checkConnection();
        checkAutoRetry();
        checkBingCompletion();
        checkAIGaps();
        checkTranslationPrompt();
        puts("lyrics translation: all checks passed");
    }
    return 0;
}
