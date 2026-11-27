// Production motion store. Filesystem boundaries reject main-thread work; no network is used.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <CommonCrypto/CommonDigest.h>
#import <unistd.h>
#import "Shared/AnimatedArtwork/AnimatedArtwork.h"
#import "Shared/AnimatedArtwork/SGMotionTicket.h"

#define CHECK(value) do { if (!(value)) { fprintf(stderr, "FAIL %d: %s\n", __LINE__, #value); exit(1); } } while (0)
static NSURL *root;
static dispatch_semaphore_t missingRootTrim;
static BOOL watch;
BOOL SGFlag(NSString *key, BOOL fallback) { return fallback; }
static void offMain(NSString *path) {
    if (watch && [path hasPrefix:root.path] && NSThread.isMainThread) {
        fprintf(stderr, "main-thread filesystem access: %s\n%s\n", path.UTF8String,
                [NSThread.callStackSymbols componentsJoinedByString:@"\n"].UTF8String);
        CHECK(NO);
    }
}

@interface NSFileManager (StoreCheck)
- (NSArray *)testURLsForDirectory:(NSSearchPathDirectory)directory inDomains:(NSSearchPathDomainMask)domains;
- (BOOL)testExists:(NSString *)path;
- (BOOL)testCreate:(NSURL *)url withIntermediateDirectories:(BOOL)parents attributes:(NSDictionary *)attributes error:(NSError **)error;
- (NSArray *)testContents:(NSURL *)url includingPropertiesForKeys:(NSArray *)keys options:(NSDirectoryEnumerationOptions)options error:(NSError **)error;
@end
@implementation NSFileManager (StoreCheck)
- (NSArray *)testURLsForDirectory:(NSSearchPathDirectory)directory inDomains:(NSSearchPathDomainMask)domains {
    if (directory == NSCachesDirectory && missingRootTrim) {
        // The launch trim is resolving its folder. Queue a completion behind it.
        SGMotionMakeFile(nil, ^BOOL { CHECK(NO); return NO; }, ^(BOOL ok) {
            CHECK(!ok);
            dispatch_semaphore_signal(missingRootTrim);
        });
        return @[];
    }
    return directory == NSCachesDirectory ? @[root] : [self testURLsForDirectory:directory inDomains:domains];
}
- (BOOL)testExists:(NSString *)path { offMain(path); return [self testExists:path]; }
- (BOOL)testCreate:(NSURL *)url withIntermediateDirectories:(BOOL)parents attributes:(NSDictionary *)attributes error:(NSError **)error {
    offMain(url.path); return [self testCreate:url withIntermediateDirectories:parents attributes:attributes error:error];
}
- (NSArray *)testContents:(NSURL *)url includingPropertiesForKeys:(NSArray *)keys options:(NSDirectoryEnumerationOptions)options error:(NSError **)error {
    CHECK(url != nil);
    offMain(url.path); return [self testContents:url includingPropertiesForKeys:keys options:options error:error];
}
@end
static void exchange(SEL original, SEL replacement) {
    method_exchangeImplementations(class_getInstanceMethod(NSFileManager.class, original),
                                   class_getInstanceMethod(NSFileManager.class, replacement));
}
static void waitFor(BOOL (^ready)(void)) {
    NSDate *until = [NSDate dateWithTimeIntervalSinceNow:45];
    while (!ready() && until.timeIntervalSinceNow > 0)
        [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.001]];
    CHECK(ready());
}
static void writeFile(NSURL *file) {
    __block BOOL done = NO;
    SGMotionMakeFile(file, ^BOOL {
        CHECK(!NSThread.isMainThread);
        return [@"clip" writeToURL:file atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }, ^(BOOL ok) { CHECK(ok); dispatch_async(dispatch_get_main_queue(), ^{ done = YES; }); });
    waitFor(^BOOL { return done; });
}

static void checkByteTrim(NSURL *pinned) {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSMutableArray<NSURL *> *clips = [NSMutableArray arrayWithObject:pinned];
    for (NSUInteger i = 1; i < 12; i++)
        [clips addObject:SGMotionMadeFile([NSString stringWithFormat:@"byte-%lu", (unsigned long)i])];
    NSURL *foreign = [pinned.URLByDeletingLastPathComponent URLByAppendingPathComponent:@"other.mp4"];
    [clips addObject:foreign];
    for (NSUInteger i = 0; i < clips.count; i++) {
        NSURL *clip = clips[i];
        if (i) CHECK([fm createFileAtPath:clip.path contents:nil attributes:nil]);
        NSFileHandle *handle = [NSFileHandle fileHandleForWritingToURL:clip error:nil];
        CHECK([handle truncateAtOffset:30000000 error:nil] && [handle closeAndReturnError:nil]);
        CHECK([fm setAttributes:@{NSFileModificationDate:[NSDate dateWithTimeIntervalSince1970:i+1]}
                   ofItemAtPath:clip.path error:nil]);
    }
    // Handoff of an existing (newest) clip triggers trim without adding any bytes.
    writeFile(clips[11]);
    watch = NO;
    CHECK(![fm fileExistsAtPath:clips[1].path] && ![fm fileExistsAtPath:clips[2].path]);
    CHECK([fm fileExistsAtPath:pinned.path]);
    for (NSUInteger i = 3; i < clips.count; i++) CHECK([fm fileExistsAtPath:clips[i].path]);
    for (NSURL *clip in [clips subarrayWithRange:NSMakeRange(3, clips.count - 3)]) CHECK([fm removeItemAtURL:clip error:nil]);
    watch = YES;
}

// Seed a previous launch's cache directly. Nothing asks the store for a clip or releases a lease.
static void checkIdleLaunchTrim(NSURL *folder) {
    NSFileManager *fm = NSFileManager.defaultManager;
    CHECK([fm createDirectoryAtURL:folder withIntermediateDirectories:YES attributes:nil error:nil]);
    NSURL *abandoned = [SGMotionMadeFile(@"interrupted") URLByAppendingPathExtension:@"partial"];
    NSURL *foreign = [folder URLByAppendingPathComponent:@"foreign.mp4.partial"];
    CHECK([fm createFileAtPath:abandoned.path contents:nil attributes:nil]);
    CHECK([fm createFileAtPath:foreign.path contents:nil attributes:nil]);
    NSMutableArray<NSURL *> *clips = [NSMutableArray array];
    for (unsigned i = 0; i < 11; i++) {
        NSURL *clip = [folder URLByAppendingPathComponent:[NSString stringWithFormat:@"%040x.mp4", i]];
        [clips addObject:clip];
        CHECK([fm createFileAtPath:clip.path contents:nil attributes:nil]);
        NSFileHandle *handle = [NSFileHandle fileHandleForWritingToURL:clip error:nil];
        CHECK([handle truncateAtOffset:30000000 error:nil] && [handle closeAndReturnError:nil]);
        CHECK([fm setAttributes:@{NSFileModificationDate:[NSDate dateWithTimeIntervalSince1970:i+1]}
                   ofItemAtPath:clip.path error:nil]);
    }
    watch = YES;
    waitFor(^BOOL { return access(clips.firstObject.fileSystemRepresentation, F_OK) == -1 && errno == ENOENT; });
    watch = NO;
    CHECK(![fm fileExistsAtPath:abandoned.path] && [fm fileExistsAtPath:foreign.path]);
    CHECK([fm removeItemAtURL:foreign error:nil]);
    for (NSUInteger i = 1; i < clips.count; i++) CHECK([fm removeItemAtURL:clips[i] error:nil]);
}

// Controlled NSURLSession boundary: progress, cancellation, stale completion and retry.
@interface StoreTask : NSObject
@property (nonatomic) int64_t countOfBytesExpectedToReceive, countOfBytesReceived;
@property (nonatomic) BOOL cancelled;
- (void)resume;
- (void)cancel;
@end
@implementation StoreTask
- (void)resume {}
- (void)cancel { self.cancelled = YES; }
@end
@interface StoreSession : NSObject
@property (nonatomic, strong) id<NSURLSessionDataDelegate> delegate;
@property (nonatomic, strong) StoreTask *task;
@property (nonatomic, strong) NSURL *url;
- (id)dataTaskWithRequest:(NSURLRequest *)request;
- (void)finishTasksAndInvalidate;
- (void)receive:(NSUInteger)bytes expected:(int64_t)expected;
- (void)finish:(NSError *)error;
@end
static NSMutableArray<StoreSession *> *sessions;
@implementation StoreSession
- (id)dataTaskWithRequest:(NSURLRequest *)request {
    self.url = request.URL;
    self.task = [StoreTask new];
    self.task.countOfBytesExpectedToReceive = -1;
    return self.task;
}
- (void)finishTasksAndInvalidate {}
- (void)receive:(NSUInteger)bytes expected:(int64_t)expected {
    self.task.countOfBytesExpectedToReceive = expected;
    NSDictionary *headers = expected >= 0 ? @{@"Content-Length": [@(expected) stringValue]} : @{};
    NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:self.url statusCode:200 HTTPVersion:@"HTTP/1.1" headerFields:headers];
    [self.delegate URLSession:(id)self dataTask:(id)self.task didReceiveResponse:response
        completionHandler:^(NSURLSessionResponseDisposition disposition) {}];
    if (bytes) [self.delegate URLSession:(id)self dataTask:(id)self.task didReceiveData:[NSMutableData dataWithLength:bytes]];
    self.task.countOfBytesReceived = bytes;
}
- (void)finish:(NSError *)error {
    // NSURLSession invokes delegates off-main; dispatch_sync to the store may run inline
    // on its caller, so a main-thread fake would violate the real transport contract.
    // Drain its main-queue delivery before returning: tests choose the completion order,
    // including stale-before-replacement, rather than racing independent background tasks.
    __block BOOL finished = NO;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
        [self.delegate URLSession:(id)self task:(id)self.task didCompleteWithError:error];
        dispatch_async(dispatch_get_main_queue(), ^{ finished = YES; });
    });
    waitFor(^BOOL { return finished; });
}
@end
static id sessionFactory(id self, SEL cmd, id configuration, id delegate, id queue) {
    StoreSession *session = [StoreSession new];
    session.delegate = delegate;
    [sessions addObject:session];
    return session;
}
static NSError *cancelError(void) {
    return [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCancelled userInfo:nil];
}
static StoreSession *latestAfter(NSUInteger count) {
    waitFor(^BOOL { return sessions.count > count; });
    return sessions.lastObject;
}
static void checkCancellation(void) {
    sessions = [NSMutableArray array];
    __block BOOL delivered = NO;
    Method method = class_getClassMethod(NSURLSession.class, @selector(sessionWithConfiguration:delegate:delegateQueue:));
    IMP original = method_setImplementation(method, (IMP)sessionFactory);
    NSURL *url = [NSURL URLWithString:@"https://fixture.invalid/shared.mp4"];
    __block NSURL *retainedFile;
    SGMotionTicket *first = SGMotionRequestFile(url, ^(NSURL *file) { CHECK(NO); });
    SGMotionRequestFile(url, ^(NSURL *file) { retainedFile = file; });
    StoreSession *shared = latestAfter(0);
    [shared receive:49 expected:100];
    [first cancel];
    CHECK(!shared.task.cancelled);
    [shared finish:nil];
    waitFor(^BOOL { return retainedFile != nil; });
    // The remaining consumer's lease survives pressure after the cancelled peer is gone.
    for (NSUInteger i = 0; i < 41; i++)
        @autoreleasepool { writeFile(SGMotionMadeFile([NSString stringWithFormat:@"lease-%lu", (unsigned long)i])); }
    watch = NO;
    CHECK([NSFileManager.defaultManager fileExistsAtPath:retainedFile.path]);
    watch = YES;

    // Both waiters have already been captured for delivery when the first callback cancels
    // the second. Removing it from the transfer's original array alone cannot suppress it.
    NSUInteger deliveryCount = sessions.count;
    __block BOOL firstDelivered = NO, secondDelivered = NO;
    __block SGMotionTicket *second;
    NSURL *deliveryURL = [NSURL URLWithString:@"https://fixture.invalid/cancel-during-delivery.mp4"];
    SGMotionRequestFile(deliveryURL, ^(NSURL *file) {
        CHECK(file);
        [second cancel];
        firstDelivered = YES;
    });
    second = SGMotionRequestFile(deliveryURL, ^(NSURL *file) { secondDelivered = YES; });
    StoreSession *delivery = latestAfter(deliveryCount);
    [delivery receive:100 expected:100];
    [delivery finish:nil];
    CHECK(firstDelivered && !secondDelivered);

    for (NSNumber *progress in @[@49, @50, @51, @(-1), @0]) {
        NSString *address = [NSString stringWithFormat:@"https://fixture.invalid/progress-%@.mp4", progress];
        NSURL *remote = [NSURL URLWithString:address];
        NSUInteger count = sessions.count;
        SGMotionTicket *ticket = SGMotionRequestFile(remote, ^(NSURL *file) { CHECK(NO); });
        StoreSession *old = latestAfter(count);
        [old receive:progress.intValue <= 0 ? 0 : progress.unsignedIntegerValue expected:progress.intValue <= 0 ? progress.intValue : 100];
        [ticket cancel];
        CHECK(old.task.cancelled == (progress.intValue != 51));
        __block NSURL *replacementFile;
        SGMotionRequestFile(remote, ^(NSURL *file) { CHECK(file); replacementFile = file; });
        if (progress.intValue == 51) {
            CHECK(sessions.count == count + 1);
            [old finish:nil];
        } else {
            StoreSession *replacement = latestAfter(count + 1);
            // Intentionally cancelled requests must not retry, even if a timeout races cancel.
            [old finish:[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorTimedOut userInfo:nil]];
            CHECK(replacementFile == nil);
            [replacement receive:100 expected:100];
            [replacement finish:nil];
        }
        CHECK(replacementFile != nil);
        CHECK(sessions.count == count + (progress.intValue == 51 ? 1 : 2));
    }
    // A stale completion must leave the replacement joinable. Without that ownership
    // guard, each orphaned transfer can still deliver its own waiters, hiding the defect
    // until a later consumer asks for the same remote.
    NSUInteger staleCount = sessions.count;
    NSURL *staleURL = [NSURL URLWithString:@"https://fixture.invalid/stale-before-join.mp4"];
    SGMotionTicket *staleTicket = SGMotionRequestFile(staleURL, ^(NSURL *file) { CHECK(NO); });
    StoreSession *stale = latestAfter(staleCount);
    [staleTicket cancel];
    __block BOOL replacementDelivered = NO, joinedDelivered = NO;
    SGMotionRequestFile(staleURL, ^(NSURL *file) { CHECK(!file); replacementDelivered = YES; });
    StoreSession *replacement = latestAfter(staleCount + 1);
    [stale finish:cancelError()];
    SGMotionRequestFile(staleURL, ^(NSURL *file) { CHECK(!file); joinedDelivered = YES; });
    // An error leaves no cache file that could accidentally satisfy an orphaned joiner.
    [replacement finish:cancelError()];
    CHECK(replacementDelivered && joinedDelivered);
    CHECK(sessions.count == staleCount + 2);

    // An abandoned >half transfer finishes into cache without any completion.
    NSUInteger count = sessions.count;
    NSURL *cacheURL = [NSURL URLWithString:@"https://fixture.invalid/finish-to-cache.mp4"];
    SGMotionTicket *ticket = SGMotionRequestFile(cacheURL, ^(NSURL *file) { CHECK(NO); });
    StoreSession *cacheSession = latestAfter(count);
    [cacheSession receive:51 expected:100]; [ticket cancel]; [cacheSession finish:nil];
    __block NSURL *cached;
    dispatch_async(dispatch_get_main_queue(), ^{ SGMotionFile(cacheURL, ^(NSURL *file) { cached = file; }); });
    waitFor(^BOOL { return cached != nil; });
    CHECK(sessions.count == count + 1);
    count = sessions.count; delivered = NO;
    SGMotionRequestFile([NSURL URLWithString:@"https://fixture.invalid/certificate.mp4"], ^(NSURL *file) { CHECK(!file); delivered = YES; });
    StoreSession *permanent = latestAfter(count);
    [permanent finish:[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorServerCertificateUntrusted userInfo:nil]];
    waitFor(^BOOL { return delivered; });
    CHECK(sessions.count == count + 1);
    // Two transient failures terminate the request; there must be no third transfer.
    count = sessions.count; delivered = NO;
    SGMotionRequestFile([NSURL URLWithString:@"https://fixture.invalid/retry.mp4"], ^(NSURL *file) {
        CHECK(!file && !delivered);
        delivered = YES;
    });
    StoreSession *attempt = latestAfter(count);
    [attempt finish:[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorTimedOut userInfo:nil]];
    StoreSession *retry = latestAfter(count + 1);
    [retry finish:[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorTimedOut userInfo:nil]];
    CHECK(sessions.count == count + 2);
    CHECK(delivered);
    // The header ceiling still applies after introducing consumer tickets.
    count = sessions.count; delivered = NO;
    SGMotionRequestFile([NSURL URLWithString:@"https://fixture.invalid/oversize.mp4"], ^(NSURL *file) { CHECK(!file); delivered = YES; });
    StoreSession *oversize = latestAfter(count);
    [oversize receive:0 expected:30000001]; [oversize finish:cancelError()];
    waitFor(^BOOL { return delivered; });
    CHECK(sessions.count == count + 1);
    method_setImplementation(method, original);
    sessions = nil;
}
int main(int argc, const char **argv) {
    @autoreleasepool {
        CHECK(argc == 2);
        root = [NSURL fileURLWithPath:@(argv[1]) isDirectory:YES];
        exchange(@selector(URLsForDirectory:inDomains:), @selector(testURLsForDirectory:inDomains:));
        exchange(@selector(fileExistsAtPath:), @selector(testExists:));
        exchange(@selector(createDirectoryAtURL:withIntermediateDirectories:attributes:error:), @selector(testCreate:withIntermediateDirectories:attributes:error:));
        exchange(@selector(contentsOfDirectoryAtURL:includingPropertiesForKeys:options:error:), @selector(testContents:includingPropertiesForKeys:options:error:));
        if (strcmp(argv[1], "missing-root") == 0) {
            missingRootTrim = dispatch_semaphore_create(0);
            CHECK(!dispatch_semaphore_wait(missingRootTrim, dispatch_time(DISPATCH_TIME_NOW, 45 * NSEC_PER_SEC)));
            return 0;
        }
        watch = YES;
        NSURL *made = SGMotionMadeFile(@"a generated clip");
        CHECK(made.lastPathComponent.length == 44);
        watch = NO;
        CHECK(![NSFileManager.defaultManager fileExistsAtPath:root.path]);
        checkIdleLaunchTrim(made.URLByDeletingLastPathComponent);
        watch = YES;
        writeFile(made);
        @autoreleasepool { checkByteTrim(made); }
        for (NSUInteger i = 0; i < 41; i++) {
            @autoreleasepool { writeFile(SGMotionMadeFile([NSString stringWithFormat:@"clip-%lu", (unsigned long)i])); }
        }
        watch = NO;
        CHECK([NSFileManager.defaultManager contentsOfDirectoryAtURL:made.URLByDeletingLastPathComponent
            includingPropertiesForKeys:nil options:0 error:nil].count == 40);
        // Seed the documented address-hashed cache, then ask through the public remote entrypoint.
        NSURL *remote = [NSURL URLWithString:@"https://fixture.invalid/clip.mp4"];
        NSData *address = [remote.absoluteString dataUsingEncoding:NSUTF8StringEncoding];
        unsigned char digest[CC_SHA1_DIGEST_LENGTH]; CC_SHA1(address.bytes, (CC_LONG)address.length, digest);
        NSMutableString *name = [NSMutableString string];
        for (NSUInteger i = 0; i < sizeof(digest); i++) [name appendFormat:@"%02x", digest[i]];
        NSURL *cached = [made.URLByDeletingLastPathComponent URLByAppendingPathComponent:[name stringByAppendingPathExtension:@"mp4"]];
        CHECK([@"clip" writeToURL:cached atomically:YES encoding:NSUTF8StringEncoding error:nil]);
        CHECK([NSFileManager.defaultManager setAttributes:@{NSFileModificationDate: [NSDate dateWithTimeIntervalSince1970:1]}
            ofItemAtPath:cached.path error:nil]);
        watch = YES;
        __block NSUInteger replies = 0;
        for (NSUInteger i = 0; i < 2; i++) SGMotionFile(remote, ^(NSURL *file) {
            CHECK(NSThread.isMainThread && [file isEqual:cached]);
            CHECK([[NSString stringWithContentsOfURL:file encoding:NSUTF8StringEncoding error:nil] isEqual:@"clip"]);
            NSDate *modified = [NSFileManager.defaultManager attributesOfItemAtPath:file.path error:nil][NSFileModificationDate];
            CHECK([modified timeIntervalSince1970] > 1);
            replies++;
        });
        // Main stays held: the hit has queued its delivery, then more than one cache's
        // worth of writes trims before the consumer can even receive the handoff.
        dispatch_semaphore_t written = dispatch_semaphore_create(0);
        for (NSUInteger i = 0; i < 41; i++) {
            @autoreleasepool {
                NSURL *next = SGMotionMadeFile([NSString stringWithFormat:@"after-hit-%lu", (unsigned long)i]);
                SGMotionMakeFile(next, ^BOOL {
                    return [@"later" writeToURL:next atomically:YES encoding:NSUTF8StringEncoding error:nil];
                }, ^(BOOL ok) { CHECK(ok); if (i == 40) dispatch_semaphore_signal(written); });
            }
        }
        CHECK(dispatch_semaphore_wait(written, dispatch_time(DISPATCH_TIME_NOW, 45 * NSEC_PER_SEC)) == 0);
        waitFor(^BOOL { return replies == 2; });
        checkCancellation();
        watch = NO;
        CHECK([NSFileManager.defaultManager removeItemAtURL:root error:nil]);
        puts("motion store: pure names, background creation/trim and asynchronous cached lookup passed");
        return 0;
    }
}
