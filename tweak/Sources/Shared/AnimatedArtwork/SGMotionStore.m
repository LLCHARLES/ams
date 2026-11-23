// Remote videos kept as local files in Caches/Retrine/Motion, named by a hash of their address, and the
// videos the mod makes, named by a hash of their key. A video asked for again while it downloads joins the
// download in flight. Trimming keeps the newest clips within both budgets, except those still in use.
#import <AVFoundation/AVFoundation.h>
#import <CommonCrypto/CommonDigest.h>
#import <objc/runtime.h>
#import <stdatomic.h>
#import <stdlib.h>
#import <string.h>
#import "Core/SGCore.h"
#import "Core/SGDataRoot.h"
#import "AnimatedArtwork.h"
#import "SGMotionTicket.h"

static const NSUInteger kFiles = 40;
static const uint64_t kStoreBytes = 300 * 1000 * 1000;
static NSCountedSet<NSString *> *sg_inUse; // store queue only; counts retained handoff URLs
// Bumped by each clear. A file the mod was asked to make before a clear is not made after it.
static _Atomic uint64_t sg_clearGeneration;
static void trim(void);

static NSURL *folder(void) {
    return [SGDataRoot(NSCachesDirectory) URLByAppendingPathComponent:@"Motion" isDirectory:YES];
}

static dispatch_queue_t storeQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ queue = dispatch_queue_create("retrine.motion.store", DISPATCH_QUEUE_SERIAL); });
    return queue;
}

// An existing cache can be over budget even if artwork is never requested this launch.
__attribute__((constructor)) static void scheduleLaunchTrim(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), storeQueue(), ^{ trim(); });
}

// The URL is the consumer's existing ownership handle. Its lease does not retain the
// URL, so dropping the last consumer releases the pin without a second lifecycle API.
@interface SGMotionFileLease : NSObject
@property (nonatomic, copy) NSString *path;
@end
@implementation SGMotionFileLease
- (void)dealloc {
    NSString *path = _path;
    dispatch_async(storeQueue(), ^{
        [sg_inUse removeObject:path];
        trim();
    });
}
@end

static void handOff(NSURL *file) {
    [NSFileManager.defaultManager setAttributes:@{NSFileModificationDate: NSDate.date} ofItemAtPath:file.path error:nil];
    [file removeCachedResourceValueForKey:NSURLContentModificationDateKey];
    static char leaseKey;
    if (objc_getAssociatedObject(file, &leaseKey)) return;
    if (!sg_inUse) sg_inUse = [NSCountedSet set];
    SGMotionFileLease *lease = [SGMotionFileLease new];
    // Directory enumeration resolves aliases (for example /tmp to /private/tmp).
    // Use the same physical identity for both handoffs and trimming.
    lease.path = file.URLByResolvingSymlinksInPath.path;
    [sg_inUse addObject:lease.path];
    objc_setAssociatedObject(file, &leaseKey, lease, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
static NSURL *localFor(NSString *key) {
    NSData *address = [key dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char digest[CC_SHA1_DIGEST_LENGTH];
    CC_SHA1(address.bytes, (CC_LONG)address.length, digest);
    NSMutableString *name = [NSMutableString string];
    for (int i = 0; i < CC_SHA1_DIGEST_LENGTH; i++) [name appendFormat:@"%02x", digest[i]];
    return [folder() URLByAppendingPathComponent:[name stringByAppendingPathExtension:@"mp4"]];
}

CGFloat SGMotionPixels(void) {
    return round(UIScreen.mainScreen.nativeBounds.size.width * 0.75);
}

NSURL *SGMotionMadeFile(NSString *key) {
    return localFor([@"made\n" stringByAppendingString:key]);
}

void SGMotionMakeFile(NSURL *file, BOOL (^write)(void), void (^done)(BOOL)) {
    uint64_t generation = atomic_load(&sg_clearGeneration);
    dispatch_async(storeQueue(), ^{
        if (!file || generation != atomic_load(&sg_clearGeneration)) { done(NO); return; }
        BOOL ok = [NSFileManager.defaultManager fileExistsAtPath:file.path];
        if (!ok) {
            ok = [NSFileManager.defaultManager createDirectoryAtURL:folder() withIntermediateDirectories:YES attributes:nil error:nil];
            if (ok) { trim(); ok = write(); }
        }
        if (ok) { handOff(file); trim(); }
        done(ok);
    });
}

// Decimal MB, shared by every remote clip consumer. Reject advertised oversize
// bodies at the headers, and enforce the same ceiling for chunked/lying servers.
static const uint64_t kMaximumClipBytes = 30 * 1000 * 1000;
static const int64_t kFinishWithoutConsumerDivisor = 2;

@interface SGMotionWaiter : SGMotionTicket
@property (nonatomic, copy) void (^done)(NSURL *);
@end
@implementation SGMotionWaiter
- (void)cancel {
    self.done = nil;
    [super cancel];
}
@end

@interface SGMotionDownload : NSObject <NSURLSessionDataDelegate>
@property (nonatomic, strong) NSURL *remote, *local, *temporary;
@property (nonatomic, strong) NSFileHandle *output;
@property (nonatomic) NSUInteger retries;
@property (nonatomic) uint64_t received;
@property (nonatomic) NSInteger status;
@property (nonatomic) BOOL rejected;
@property (atomic) BOOL cancelled;
@property (nonatomic, strong) NSURLSessionDataTask *task;
@property (nonatomic, strong) NSMutableArray<SGMotionWaiter *> *waiters;
@end

static NSMutableDictionary<NSURL *, SGMotionDownload *> *sg_downloads; // main queue
static void download(SGMotionDownload *owner);

static BOOL transientFailure(NSError *error, NSInteger status) {
    if (!error) return status == 0 || status == 408 || status == 429 || (status >= 500 && status < 600);
    if (![error.domain isEqual:NSURLErrorDomain]) return NO;
    switch (error.code) {
        case NSURLErrorTimedOut:
        case NSURLErrorCannotFindHost:
        case NSURLErrorCannotConnectToHost:
        case NSURLErrorNetworkConnectionLost:
        case NSURLErrorDNSLookupFailed:
        case NSURLErrorNotConnectedToInternet:
            return YES;
        default: return NO;
    }
}

@implementation SGMotionDownload
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task
    didReceiveResponse:(NSURLResponse *)response completionHandler:(void (^)(NSURLSessionResponseDisposition))completion {
    self.status = [response isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)response).statusCode : 0;
    if (response.expectedContentLength > (int64_t)kMaximumClipBytes) {
        self.rejected = YES;
        completion(NSURLSessionResponseCancel);
        return;
    }
    if (self.status != 200) { completion(NSURLSessionResponseAllow); return; }
    // A unique partial outside the cache: trimming cannot remove an active write.
    NSString *pattern = [NSTemporaryDirectory() stringByAppendingPathComponent:@"retrine-motion-XXXXXX"];
    char *path = strdup(pattern.fileSystemRepresentation);
    int descriptor = mkstemp(path);
    if (descriptor >= 0) {
        self.temporary = [NSURL fileURLWithPath:@(path)];
        self.output = [[NSFileHandle alloc] initWithFileDescriptor:descriptor closeOnDealloc:YES];
    }
    free(path);
    if (!self.output) self.rejected = YES;
    completion(self.rejected ? NSURLSessionResponseCancel : NSURLSessionResponseAllow);
}
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveData:(NSData *)data {
    if (self.rejected) return;
    if (data.length > kMaximumClipBytes - self.received) {
        self.rejected = YES;
        [task cancel];
        return;
    }
    self.received += data.length;
    if (self.status != 200) return;
    NSError *error = nil;
    if (![self.output writeData:data error:&error]) {
        SGLog(@"motion: cannot write clip: %@", error.localizedDescription);
        self.rejected = YES;
        [task cancel];
    }
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    NSError *closeError = nil;
    BOOL closed = self.output && [self.output closeAndReturnError:&closeError];
    self.output = nil;
    __block BOOL kept = NO;
    if (!self.rejected && !error && closed && self.status == 200 && self.received > 0) dispatch_sync(storeQueue(), ^{
        if (self.cancelled) return;
        if (![NSFileManager.defaultManager createDirectoryAtURL:folder() withIntermediateDirectories:YES attributes:nil error:nil]) return;
        kept = [NSFileManager.defaultManager moveItemAtURL:self.temporary toURL:self.local error:nil];
        if (kept) { handOff(self.local); trim(); }
    });
    if (!kept && self.temporary) {
        NSError *cleanup = nil;
        if (![NSFileManager.defaultManager removeItemAtURL:self.temporary error:&cleanup])
            SGLog(@"motion: cannot remove partial clip: %@", cleanup.localizedDescription);
    }
    BOOL cancelled = [error.domain isEqual:NSURLErrorDomain] && error.code == NSURLErrorCancelled;
    BOOL again = !kept && !self.rejected && !cancelled && !self.cancelled && self.retries > 0 &&
        transientFailure(error, self.status);
    SGLog(@"motion: %@ %@ (%llu bytes, HTTP %ld)%@", self.remote.lastPathComponent, kept ? @"kept" : @"failed",
          (unsigned long long)self.received, (long)self.status, self.rejected ? @", size or write rejected" : @"");
    [session finishTasksAndInvalidate];
    dispatch_async(dispatch_get_main_queue(), ^{
        if (sg_downloads[self.remote] != self) return;
        if (again && !self.cancelled && self.waiters.count) {
            self.retries--;
            download(self);
            return;
        }
        NSArray *waiting = [self.waiters copy];
        [self.waiters removeAllObjects];
        [sg_downloads removeObjectForKey:self.remote];
        for (SGMotionWaiter *waiter in waiting) {
            waiter.onCancel = nil;
            void (^done)(NSURL *) = waiter.done;
            waiter.done = nil;
            if (done) done(kept ? self.local : nil);
        }
    });
}
@end

static void download(SGMotionDownload *owner) {
    owner.received = 0;
    owner.status = 0;
    owner.rejected = NO;
    owner.temporary = nil;
    NSOperationQueue *queue = [NSOperationQueue new];
    queue.maxConcurrentOperationCount = 1;
    NSURLSession *session = [NSURLSession sessionWithConfiguration:NSURLSessionConfiguration.defaultSessionConfiguration
                                                        delegate:owner delegateQueue:queue];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:owner.remote];
    request.allowsConstrainedNetworkAccess = SGFlag(SGKeyMotionLowData, NO);
    owner.task = [session dataTaskWithRequest:request];
    [owner.task resume];
}

SGMotionTicket *SGMotionRequestFile(NSURL *remote, void (^done)(NSURL *file)) {
    SGMotionWaiter *ticket = [SGMotionWaiter new];
    if (!remote) {
        dispatch_async(dispatch_get_main_queue(), ^{ if (!ticket.cancelled) done(nil); });
        return ticket;
    }
    if (!sg_downloads) sg_downloads = [NSMutableDictionary dictionary];
    SGMotionDownload *owner = sg_downloads[remote];
    BOOL joined = owner != nil;
    if (!owner) {
        owner = [SGMotionDownload new];
        owner.remote = remote;
        owner.retries = 1;
        owner.waiters = [NSMutableArray array];
        sg_downloads[remote] = owner;
    }
    ticket.done = done;
    [owner.waiters addObject:ticket];
    __weak SGMotionWaiter *weakTicket = ticket;
    __weak SGMotionDownload *weakOwner = owner;
    ticket.onCancel = ^{
        SGMotionDownload *active = weakOwner;
        [active.waiters removeObjectIdenticalTo:weakTicket];
        if (!active || active.waiters.count || sg_downloads[remote] != active) return;
        int64_t expected = active.task.countOfBytesExpectedToReceive;
        int64_t received = active.task.countOfBytesReceived;
        if (expected > 0 && received > expected / kFinishWithoutConsumerDivisor) return;
        active.cancelled = YES;
        [sg_downloads removeObjectForKey:remote];
        [active.task cancel];
    };
    if (joined) return ticket;
    dispatch_async(storeQueue(), ^{
        NSURL *local = localFor(remote.absoluteString);
        BOOL exists = [NSFileManager.defaultManager fileExistsAtPath:local.path];
        if (exists) handOff(local);
        dispatch_async(dispatch_get_main_queue(), ^{
            if (sg_downloads[remote] != owner) return;
            owner.local = local;
            if (local && !exists) { download(owner); return; }
            NSArray *waiting = [owner.waiters copy];
            [owner.waiters removeAllObjects];
            [sg_downloads removeObjectForKey:remote];
            for (SGMotionWaiter *waiter in waiting) {
                waiter.onCancel = nil;
                void (^completion)(NSURL *) = waiter.done;
                waiter.done = nil;
                if (completion) completion(local);
            }
        });
    });
    return ticket;
}

void SGMotionFile(NSURL *remote, void (^done)(NSURL *file)) {
    SGMotionRequestFile(remote, done);
}

#pragma mark - clearing

// The clips this store makes and nothing else in the folder: the hash of an address or key, then .mp4.
static BOOL ownedClip(NSURL *file) {
    NSString *name = file.lastPathComponent.stringByDeletingPathExtension;
    NSCharacterSet *notHex = [NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdef"].invertedSet;
    return [file.pathExtension isEqualToString:@"mp4"] && name.length == CC_SHA1_DIGEST_LENGTH * 2 &&
        [name rangeOfCharacterFromSet:notHex].location == NSNotFound;
}

// Store queue. *error is set when a folder that exists could not be read; one not made yet has no clips.
static NSArray<NSURL *> *ownedClips(NSError **error) {
    NSError *listing = nil;
    NSArray *keys = @[NSURLFileSizeKey, NSURLIsRegularFileKey, NSURLContentModificationDateKey];
    NSArray<NSURL *> *files = [NSFileManager.defaultManager contentsOfDirectoryAtURL:folder() includingPropertiesForKeys:keys
                                                                             options:NSDirectoryEnumerationSkipsHiddenFiles error:&listing];
    if (!files) {
        if (![NSFileManager.defaultManager fileExistsAtPath:folder().path]) return @[];
        if (error) *error = listing;
        return @[];
    }
    NSMutableArray<NSURL *> *owned = [NSMutableArray array];
    for (NSURL *file in files) {
        NSNumber *regular = nil;
        if (ownedClip(file) && [file getResourceValue:&regular forKey:NSURLIsRegularFileKey error:nil] && regular.boolValue)
            [owned addObject:file];
    }
    return owned;
}

static uint64_t clipBytes(NSURL *file) {
    NSNumber *size = nil;
    [file getResourceValue:&size forKey:NSURLFileSizeKey error:nil];
    return size.unsignedLongLongValue;
}

static void trim(void) {
    NSArray<NSURL *> *files = ownedClips(NULL);
    NSUInteger count = files.count;
    uint64_t bytes = 0;
    for (NSURL *file in files) bytes += clipBytes(file);
    if (count <= kFiles && bytes <= kStoreBytes) return;
    NSArray *oldestFirst = [files sortedArrayUsingComparator:^NSComparisonResult(NSURL *a, NSURL *b) {
        NSDate *left = nil, *right = nil;
        [a getResourceValue:&left forKey:NSURLContentModificationDateKey error:nil];
        [b getResourceValue:&right forKey:NSURLContentModificationDateKey error:nil];
        return [left compare:right];
    }];
    for (NSURL *file in oldestFirst) {
        if ([sg_inUse containsObject:file.URLByResolvingSymlinksInPath.path]) continue;
        uint64_t size = clipBytes(file);
        if (![NSFileManager.defaultManager removeItemAtURL:file error:nil]) continue;
        count--;
        bytes -= size;
        if (count <= kFiles && bytes <= kStoreBytes) break;
    }
}

void SGMotionStoreBytes(void (^done)(uint64_t bytes)) {
    dispatch_async(storeQueue(), ^{
        uint64_t total = 0;
        for (NSURL *file in ownedClips(NULL)) total += clipBytes(file);
        dispatch_async(dispatch_get_main_queue(), ^{ done(total); });
    });
}

void SGMotionStoreClear(void (^done)(BOOL complete)) {
    atomic_fetch_add(&sg_clearGeneration, 1);
    // A download from before the clear may not land afterwards, nor may a request after it join one:
    // its consumers get nothing and the next request fetches again.
    NSArray<SGMotionDownload *> *stale = sg_downloads.allValues;
    [sg_downloads removeAllObjects];
    for (SGMotionDownload *owner in stale) {
        owner.cancelled = YES;
        [owner.task cancel];
        NSArray *waiting = [owner.waiters copy];
        [owner.waiters removeAllObjects];
        for (SGMotionWaiter *waiter in waiting) {
            waiter.onCancel = nil;
            void (^completion)(NSURL *) = waiter.done;
            waiter.done = nil;
            if (completion) completion(nil);
        }
    }
    dispatch_async(storeQueue(), ^{
        NSError *listing = nil;
        BOOL complete = YES;
        for (NSURL *file in ownedClips(&listing)) {
            // A clip a consumer holds stays; it goes with the next trim once released.
            if ([sg_inUse containsObject:file.URLByResolvingSymlinksInPath.path]) continue;
            NSError *error = nil;
            if (![NSFileManager.defaultManager removeItemAtURL:file error:&error] && [NSFileManager.defaultManager fileExistsAtPath:file.path]) {
                SGLog(@"motion: cannot remove clip: %@", error.localizedDescription);
                complete = NO;
            }
        }
        if (listing) {
            SGLog(@"motion: cannot list clips: %@", listing.localizedDescription);
            complete = NO;
        }
        dispatch_async(dispatch_get_main_queue(), ^{ done(complete); });
    });
}

void SGMotionPoster(NSURL *file, void (^done)(UIImage *poster)) {
    AVAssetImageGenerator *generator = [AVAssetImageGenerator assetImageGeneratorWithAsset:[AVURLAsset assetWithURL:file]];
    generator.appliesPreferredTrackTransform = YES;
    [generator generateCGImageAsynchronouslyForTime:kCMTimeZero completionHandler:^(CGImageRef image, CMTime actual, NSError *error) {
        UIImage *poster = image ? [UIImage imageWithCGImage:image] : nil;
        dispatch_async(dispatch_get_main_queue(), ^{ done(poster); });
    }];
}
