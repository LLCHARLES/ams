// Production streaming downloader, with recorded HTTP boundaries and no network.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "../album-notes/catalog-boundary.h"
#import "Shared/AnimatedArtwork/AnimatedArtwork.h"
static NSURL *root;
static BOOL lowData;
static NSMutableDictionary<NSString *, NSNumber *> *attempts;
BOOL SGFlag(NSString *key, BOOL fallback) { return lowData; }

@interface ClipProtocol : NSURLProtocol
@property (atomic) BOOL stopped;
@property (nonatomic) NSUInteger sent;
- (void)sendChunk;
@end
@implementation ClipProtocol
+ (BOOL)canInitWithRequest:(NSURLRequest *)request { return YES; }
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request { return request; }
- (void)startLoading {
    dispatch_async(dispatch_get_main_queue(), ^{
        CHECK(self.request.allowsConstrainedNetworkAccess == lowData);
        NSString *name = self.request.URL.lastPathComponent;
        attempts[name] = @([attempts[name] unsignedIntegerValue] + 1);
        if ([name isEqual:@"cancel"]) {
            [self.client URLProtocol:self didFailWithError:[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCancelled userInfo:nil]];
            return;
        }
        NSDictionary *headers = [name isEqual:@"header"] ? @{@"Content-Length": @"30000001"}
            : [name isEqual:@"exact"] ? @{@"Content-Length": @"30000000"} : @{};
        NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:self.request.URL statusCode:200
            HTTPVersion:@"HTTP/1.1" headerFields:headers];
        [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
        // NSURLProtocol completes the transport transaction before Foundation
        // delivers its response to the data delegate. Queue a complete body;
        // the delegate must reject its headers before consuming those chunks.
        [self sendChunk];
    });
}
- (void)sendChunk {
    if (self.stopped) return;
    NSUInteger length = [self.request.URL.lastPathComponent isEqual:@"exact"] ? 30000000 : 30000001;
    NSUInteger chunk = MIN((NSUInteger)1000000, length - self.sent);
    [self.client URLProtocol:self didLoadData:[NSMutableData dataWithLength:chunk]];
    self.sent += chunk;
    if (self.sent == length) [self.client URLProtocolDidFinishLoading:self];
    else dispatch_async(dispatch_get_main_queue(), ^{ [self sendChunk]; });
}
- (void)stopLoading { self.stopped = YES; }
@end

@interface NSURLSessionConfiguration (ClipBoundary)
+ (NSURLSessionConfiguration *)fixtureConfiguration;
@end
@implementation NSURLSessionConfiguration (ClipBoundary)
+ (NSURLSessionConfiguration *)fixtureConfiguration {
    NSURLSessionConfiguration *configuration = [self fixtureConfiguration];
    configuration.protocolClasses = @[ClipProtocol.class];
    return configuration;
}
@end

@interface NSFileManager (DownloadRoot)
- (NSArray *)fixtureURLs:(NSSearchPathDirectory)directory inDomains:(NSSearchPathDomainMask)domains;
@end
@implementation NSFileManager (DownloadRoot)
- (NSArray *)fixtureURLs:(NSSearchPathDirectory)directory inDomains:(NSSearchPathDomainMask)domains {
    return directory == NSCachesDirectory ? @[root] : [self fixtureURLs:directory inDomains:domains];
}
@end

int main(void) {
    @autoreleasepool {
        NSString *path = NSProcessInfo.processInfo.environment[@"RETRINE_TEST_ROOT"];
        CHECK(path.length > 0);
        root = [NSURL fileURLWithPath:path isDirectory:YES];
        attempts = [NSMutableDictionary dictionary];
        method_exchangeImplementations(class_getClassMethod(NSURLSessionConfiguration.class, @selector(defaultSessionConfiguration)),
                                       class_getClassMethod(NSURLSessionConfiguration.class, @selector(fixtureConfiguration)));
        method_exchangeImplementations(class_getInstanceMethod(NSFileManager.class, @selector(URLsForDirectory:inDomains:)),
                                       class_getInstanceMethod(NSFileManager.class, @selector(fixtureURLs:inDomains:)));
        CHECK([NSURLProtocol registerClass:ClipProtocol.class]);
        for (NSString *name in @[@"header", @"chunked", @"exact", @"cancel"]) {
            lowData = [name isEqual:@"exact"];
            __block BOOL done = NO;
            SGMotionFile([NSURL URLWithString:[@"https://fixture.invalid/" stringByAppendingString:name]], ^(NSURL *file) {
                if ([name isEqual:@"exact"]) {
                    CHECK(file != nil);
                    NSDictionary *attributes = [NSFileManager.defaultManager attributesOfItemAtPath:file.path error:nil];
                    CHECK([attributes[NSFileSize] unsignedLongLongValue] == 30000000);
                } else CHECK(file == nil);
                done = YES;
            });
            NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:10];
            while (!done && deadline.timeIntervalSinceNow > 0)
                [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.001]];
            if (!done || [attempts[name] unsignedIntegerValue] != 1)
                fprintf(stderr, "download %s: completed=%d, attempts=%lu\n", name.UTF8String, done, (unsigned long)[attempts[name] unsignedIntegerValue]);
            CHECK(done && [attempts[name] unsignedIntegerValue] == 1);
        }
        [NSURLProtocol unregisterClass:ClipProtocol.class];
        CHECK([NSFileManager.defaultManager removeItemAtURL:root error:nil]);
        puts("artist artwork: 30 MB accepted; oversized headers/chunked bodies and cancellation fail without retry; Low Data policy preserved");
    }
    return 0;
}
