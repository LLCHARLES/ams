// Production Canvas lookup/cache and protobuf codec, with controlled HTTP and file boundaries.
#import <UIKit/UIKit.h>
#import "Shared/AnimatedArtwork/AnimatedArtwork.h"
#import "Shared/AnimatedArtwork/SGMotionTicket.h"
#import "Shared/LyricsSources/SGBoundedRequest.h"
#import "Shared/AdBlock/Protobuf.h"
#import "Settings/SGModPage.h"
#import "Settings/SGSourcesPage.h"
#import <objc/runtime.h>

#define CHECK(value) do { if (!(value)) { fprintf(stderr, "FAIL %d: %s\n", __LINE__, #value); exit(1); } } while (0)

BOOL SGFlag(NSString *key, BOOL fallback) { return fallback; }
NSString *SGL(NSString *key, NSString *english) { return english; }
static NSMutableArray *headerWaiters;
void SGSpclientHeaders(void (^use)(NSDictionary *)) {
    if (headerWaiters) [headerWaiters addObject:[use copy]];
    else use(@{@"Authorization": @"fixture"});
}
static BOOL holdFile;
static SGMotionTicket *fileTicket;
static NSUInteger fileRequests;
static BOOL allowAlbum;
SGMotionTicket *SGMotionRequestFile(NSURL *remote, void (^done)(NSURL *)) {
    fileRequests++;
    SGMotionTicket *ticket = [SGMotionTicket new];
    fileTicket = ticket;
    if (!holdFile) dispatch_async(dispatch_get_main_queue(), ^{ if (!ticket.cancelled) done(remote); });
    return ticket;
}
SGMotionTicket *SGMotionRequestSongCover(NSString *artist, NSString *album, NSString *song, NSString *albumURI, NSString *trackURI, CGFloat pixels, void (^done)(NSURL *)) {
    CHECK(allowAlbum);
    SGMotionTicket *ticket = [SGMotionTicket new];
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!ticket.cancelled) done([NSURL URLWithString:@"https://fixture.invalid/album.mp4"]);
    });
    return ticket;
}
// Settings-page linkage is not exercised by these source-walk checks.
@implementation SGSource
+ (instancetype)sourceWithKey:(NSString *)key name:(NSString *)name detail:(NSString *)detail { return nil; }
@end
SGModRow *SGPageRow(NSString *title, UIViewController *(^page)(void)) { return nil; }
SGModRow *SGWithSymbol(SGModRow *row, NSString *symbol) { return row; }
UIViewController *SGSourcesPageMake(NSString *title, NSString *note, NSArray *all,
                                   NSArray *(^order)(void), void (^setOrder)(NSArray *)) { return nil; }

static BOOL revised;
static NSUInteger heldRequests;
@interface CanvasProtocol : NSURLProtocol
@property (nonatomic, copy) NSString *uri;
- (void)finish;
@end
@implementation CanvasProtocol
+ (BOOL)canInitWithRequest:(NSURLRequest *)request { return YES; }
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request { return request; }
- (void)startLoading {
    CHECK([[self.request valueForHTTPHeaderField:@"Authorization"] isEqual:@"fixture"]);
    CHECK(!self.request.allowsConstrainedNetworkAccess);
    NSMutableData *body = [self.request.HTTPBody mutableCopy];
    if (!body) {
        body = [NSMutableData data];
        NSInputStream *stream = self.request.HTTPBodyStream;
        CHECK(stream);
        [stream open];
        uint8_t bytes[1024];
        NSInteger length;
        while ((length = [stream read:bytes maxLength:sizeof(bytes)]) > 0) [body appendBytes:bytes length:length];
        CHECK(length == 0);
        [stream close];
    }
    self.uri = SGPBText(SGPBFirst(SGPBParse(SGPBFirst(SGPBParse(body), 1).payload), 1));
    CHECK([self.uri hasPrefix:@"spotify:track:"]);
    CHECK(![self.uri hasPrefix:@"spotify:track:offline-"]);
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([self.uri isEqual:@"spotify:track:held"]) heldRequests++;
        [self finish];
    });
}
- (void)finish {
    NSData *data = [NSData data];
    if (revised || ![self.uri isEqual:@"spotify:track:negative"]) {
        NSString *url = revised ? @"https://fixture.invalid/second.mp4" : @"https://fixture.invalid/first.mp4";
        data = SGPBSerialize(@[SGPBBytes(1, SGPBSerialize(@[SGPBString(2, url), SGPBVarint(4, 1)]))]);
    }
    NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:self.request.URL statusCode:200
        HTTPVersion:@"HTTP/1.1" headerFields:nil];
    [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    [self.client URLProtocol:self didLoadData:data];
    [self.client URLProtocolDidFinishLoading:self];
}
- (void)stopLoading {}
@end

// Hold delivery to the source walk, not the HTTP connection: 200 cache fills can
// outlast the fixture's one-second request timeout. Keep the real transport and reply bytes.
extern __typeof__(SGBoundedRequestTask) fixtureHTTPTask;
static BOOL holdNextReply;
static dispatch_block_t releaseReply;
NSURLSessionDataTask *SGBoundedRequestTask(NSURLRequest *request, NSTimeInterval timeout,
    void (^done)(NSData *, NSURLResponse *, NSError *)) {
    if (!holdNextReply) return fixtureHTTPTask(request, timeout, done);
    holdNextReply = NO;
    return fixtureHTTPTask(request, timeout, ^(NSData *data, NSURLResponse *response, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            releaseReply = ^{ done(data, response, error); };
        });
    });
}

static NSURLSession *fixtureSession;
@interface NSURLSession (CanvasCheck)
+ (NSURLSession *)canvasSession;
@end
@implementation NSURLSession (CanvasCheck)
+ (NSURLSession *)canvasSession { return fixtureSession; }
@end

static void waitFor(BOOL (^ready)(void)) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:45];
    while (!ready() && deadline.timeIntervalSinceNow > 0)
        [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.001]];
    CHECK(ready());
}
static void ask(NSString *uri, void (^done)(NSURL *)) {
    SGMotionClipFor(uri, nil, @"Artist", @"Album", 720, ^(NSURL *file, NSString *source) {
        CHECK(file ? [source isEqual:@"canvas"] : source == nil);
        done(file);
    });
}
static NSURL *lookup(NSString *uri) {
    __block BOOL finished = NO;
    __block NSURL *answer;
    ask(uri, ^(NSURL *file) { CHECK(!finished); answer = file; finished = YES; });
    waitFor(^BOOL { return finished; });
    return answer;
}
int main(void) {
    @autoreleasepool {
        [NSUserDefaults.standardUserDefaults setVolatileDomain:@{SGKeyMotionSources: @[@"canvas"]} forName:NSArgumentDomain];
        CHECK([NSURLProtocol registerClass:CanvasProtocol.class]);
        NSURLSessionConfiguration *configuration = NSURLSessionConfiguration.ephemeralSessionConfiguration;
        configuration.protocolClasses = @[CanvasProtocol.class];
        configuration.timeoutIntervalForRequest = 1;
        Method ephemeral = class_getClassMethod(NSURLSessionConfiguration.class, @selector(ephemeralSessionConfiguration));
        method_setImplementation(ephemeral, imp_implementationWithBlock(^id(id cls) { return [configuration copy]; }));
        fixtureSession = [NSURLSession sessionWithConfiguration:configuration];
        Method shared = class_getClassMethod(NSURLSession.class, @selector(sharedSession));
        Method fixture = class_getClassMethod(NSURLSession.class, @selector(canvasSession));
        method_exchangeImplementations(shared, fixture);
        headerWaiters = [NSMutableArray array];
        [NSUserDefaults.standardUserDefaults setVolatileDomain:@{SGKeyMotionSources: @[@"canvas", @"applemusic"]} forName:NSArgumentDomain];
        allowAlbum = YES;
        __block NSUInteger fallbackDelivered = 0;
        SGMotionRequestClip(@"spotify:track:no-headers", nil, nil, nil, 720, ^(NSURL *file, NSString *source) {
            CHECK([source isEqual:@"applemusic"]);
            CHECK([file.absoluteString isEqual:@"https://fixture.invalid/album.mp4"]);
            fallbackDelivered++;
        });
        waitFor(^BOOL { return fallbackDelivered == 1; });
        allowAlbum = NO;
        [NSUserDefaults.standardUserDefaults setVolatileDomain:@{SGKeyMotionSources: @[@"canvas"]} forName:NSArgumentDomain];
        NSHashTable *cancelled = NSHashTable.weakObjectsHashTable;
        for (NSUInteger i = 0; i < 250; i++) {
            @autoreleasepool {
                SGMotionTicket *ticket = SGMotionRequestClip([NSString stringWithFormat:@"spotify:track:offline-%lu", (unsigned long)i],
                    nil, nil, nil, 720, ^(NSURL *file, NSString *source) { CHECK(NO); });
                [cancelled addObject:ticket];
                [ticket cancel];
            }
        }
        CHECK(cancelled.allObjects.count == 0);
        CHECK(headerWaiters.count == 1); // The uncancellable provider must not accumulate per-track closures.
        __block NSUInteger asyncDelivered = 0;
        SGMotionTicket *stale = SGMotionRequestClip(@"spotify:track:async-current", nil, nil, nil, 720,
            ^(NSURL *file, NSString *source) { CHECK(NO); });
        void (^asyncAnswer)(NSURL *) = ^(NSURL *file) {
            CHECK([file.absoluteString isEqual:@"https://fixture.invalid/first.mp4"]);
            asyncDelivered++;
        };
        ask(@"spotify:track:async-current", asyncAnswer);
        ask(@"spotify:track:async-current", asyncAnswer);
        [stale cancel]; // Removing one consumer must leave the shared live consumers registered.
        CHECK(asyncDelivered == 0 && fileRequests == 0);
        NSArray *waiting = headerWaiters;
        headerWaiters = nil;
        for (void (^deliver)(NSDictionary *) in waiting) deliver(@{@"Authorization": @"fixture"});
        waitFor(^BOOL { return asyncDelivered == 2; });
        // A late provider reply cannot revive the expired walk or cache its failure as "no Canvas".
        CHECK(lookup(@"spotify:track:no-headers") != nil);
        CHECK(fallbackDelivered == 1);
        CHECK(fileRequests == 3);
        CHECK([lookup(@"spotify:track:positive").absoluteString isEqual:@"https://fixture.invalid/first.mp4"]);
        CHECK(lookup(@"spotify:track:negative") == nil);
        revised = YES;
        CHECK([lookup(@"spotify:track:positive").absoluteString isEqual:@"https://fixture.invalid/first.mp4"]);
        CHECK(lookup(@"spotify:track:negative") == nil);

        __block NSUInteger delivered = 0;
        void (^waiter)(NSURL *) = ^(NSURL *file) {
            CHECK([file.absoluteString isEqual:@"https://fixture.invalid/second.mp4"]);
            delivered++;
        };
        holdNextReply = YES;
        ask(@"spotify:track:held", waiter);
        ask(@"spotify:track:held", waiter);
        waitFor(^BOOL { return releaseReply != nil; });
        revised = NO;
        for (NSUInteger i = 0; i < 200; i++)
            CHECK(lookup([NSString stringWithFormat:@"spotify:track:fill-%lu", (unsigned long)i]) != nil);
        revised = YES;
        CHECK([lookup(@"spotify:track:fill-199").absoluteString isEqual:@"https://fixture.invalid/first.mp4"]);
        CHECK([lookup(@"spotify:track:positive").absoluteString isEqual:@"https://fixture.invalid/second.mp4"]);
        CHECK([lookup(@"spotify:track:negative").absoluteString isEqual:@"https://fixture.invalid/second.mp4"]);
        ask(@"spotify:track:held", waiter);
        CHECK(heldRequests == 1 && delivered == 0);
        releaseReply();
        releaseReply = nil;
        waitFor(^BOOL { return delivered == 3; });
        CHECK([lookup(@"spotify:track:held").absoluteString isEqual:@"https://fixture.invalid/second.mp4"]);
        CHECK(delivered == 3 && heldRequests == 1);
        holdFile = YES;
        SGMotionTicket *walk = SGMotionRequestClip(@"spotify:track:cancel", [NSURL URLWithString:@"https://fixture.invalid/held.mp4"],
            nil, nil, 720, ^(NSURL *file, NSString *source) { CHECK(NO); });
        [walk cancel];
        CHECK(fileTicket.cancelled);
        holdFile = NO;
        // A cancelled metadata lookup must not start a file download when its reply arrives.
        NSUInteger before = fileRequests;
        walk = SGMotionRequestClip(@"spotify:track:cancel-metadata", nil, nil, nil, 720,
            ^(NSURL *file, NSString *source) { CHECK(NO); });
        [walk cancel];
        lookup(@"spotify:track:barrier");
        CHECK(fileRequests == before + 1);
        method_exchangeImplementations(shared, fixture);
        [fixtureSession invalidateAndCancel];
        [NSURLProtocol unregisterClass:CanvasProtocol.class];
        puts("motion sources: unavailable/late headers, released cancelled waiters, fallback and bounded cache passed");
        return 0;
    }
}
