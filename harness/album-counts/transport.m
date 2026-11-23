#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import "Shared/SpotifyMetadata/SGSpotifyMetadata.h"

static void check(BOOL ok, NSString *reason) {
    if (!ok) { fprintf(stderr, "FAIL transport: %s\n", reason.UTF8String); exit(1); }
}
typedef NS_ENUM(NSUInteger, FixtureMode) { Good, WrongHost, CrossRedirect, SameRedirect, TooLongHeader, TooLongStream, AtLimit };
static FixtureMode mode;
static NSUInteger headersRead;
static BOOL allowConstrained = YES;
void SGSpclientHeaders(void (^use)(NSDictionary *headers)) {
    headersRead++;
    use(@{@"Authorization": @"fixture-only"});
}

@interface MetadataProtocol : NSURLProtocol @end
@implementation MetadataProtocol
+ (BOOL)canInitWithRequest:(NSURLRequest *)request { return YES; }
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request { return request; }
- (void)startLoading {
    NSURL *url = self.request.URL;
    check(self.request.allowsConstrainedNetworkAccess == allowConstrained, @"respects caller's Low Data Mode policy");
    check([url.scheme isEqual:@"https"] && [url.host isEqual:@"spclient.wg.spotify.com"], @"request must have the fixed Spotify origin");
    check([self.request valueForHTTPHeaderField:@"Authorization"] != nil, @"fixture headers delivered only to Spotify");
    if (mode == CrossRedirect || mode == SameRedirect) {
        NSURL *destination = [NSURL URLWithString:mode == CrossRedirect ? @"https://attacker.invalid/collect" : @"https://spclient.wg.spotify.com/other"];
        NSHTTPURLResponse *redirect = [[NSHTTPURLResponse alloc] initWithURL:url statusCode:302 HTTPVersion:@"HTTP/1.1"
            headerFields:@{@"Location": destination.absoluteString}];
        [self.client URLProtocol:self wasRedirectedToRequest:[NSURLRequest requestWithURL:destination] redirectResponse:redirect];
        return;
    }
    NSURL *responseURL = mode == WrongHost ? [NSURL URLWithString:@"https://spclient.wg.spotify.com.attacker.invalid/metadata"] : url;
    NSDictionary *fields = mode == TooLongHeader ? @{@"Content-Length": @"2097153"} : @{};
    NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:responseURL statusCode:200 HTTPVersion:@"HTTP/1.1" headerFields:fields];
    [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    if (mode == TooLongHeader) return; // The delegate must cancel without waiting for a body or EOF.
    if (mode == TooLongStream || mode == AtLimit) {
        NSData *chunk = [NSMutableData dataWithLength:65536];
        NSUInteger chunks = mode == AtLimit ? 32 : 33;
        for (NSUInteger i = 0; i < chunks; i++) [self.client URLProtocol:self didLoadData:chunk];
        if (mode == TooLongStream) return; // Cancellation is required before EOF.
    } else [self.client URLProtocol:self didLoadData:[@"{}" dataUsingEncoding:NSUTF8StringEncoding]];
    [self.client URLProtocolDidFinishLoading:self];
}
- (void)stopLoading {}
@end

// NSURLProtocol on this host withholds a header-only synthetic response until EOF. Exercise
// incremental cancellation at NSURLSession's delegate boundary instead, without inventing an EOF.
@interface StreamingSession : NSObject
@property (nonatomic, strong) id<NSURLSessionDataDelegate> delegate;
@property (nonatomic) BOOL cancelled;
- (id)dataTaskWithRequest:(NSURLRequest *)request;
- (void)invalidateAndCancel;
@end
@interface StreamingTask : NSObject
@property (nonatomic, strong) StreamingSession *session;
@property (nonatomic, strong) NSURLRequest *request;
- (void)resume;
@end
@implementation StreamingSession
- (id)dataTaskWithRequest:(NSURLRequest *)request {
    StreamingTask *task = [StreamingTask new];
    task.session = self;
    task.request = request;
    return task;
}
- (void)invalidateAndCancel {
    self.cancelled = YES;
    self.delegate = nil;
}
@end
@implementation StreamingTask
- (void)resume {
    dispatch_async(dispatch_get_main_queue(), ^{
        StreamingSession *session = self.session;
        id<NSURLSessionDataDelegate> delegate = session.delegate;
        NSDictionary *headers = mode == TooLongHeader ? @{@"Content-Length": @"2097153"} : @{};
        NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:self.request.URL statusCode:200 HTTPVersion:@"HTTP/1.1" headerFields:headers];
        [delegate URLSession:(id)session dataTask:(id)self didReceiveResponse:response completionHandler:^(NSURLSessionResponseDisposition disposition) {
            if (mode == TooLongHeader) check(disposition == NSURLSessionResponseCancel, @"oversized declared length is refused before body delivery");
        }];
        if (mode == TooLongStream) {
            NSData *chunk = [NSMutableData dataWithLength:65536];
            for (NSUInteger i = 0; i < 33 && !session.cancelled; i++)
                [delegate URLSession:(id)session dataTask:(id)self didReceiveData:chunk];
        }
        check(session.cancelled, @"oversized stream must cancel the session before EOF");
        // No didCompleteWithError or EOF: failure must already have been delivered by the size guard.
    });
}
@end

@interface NSURLSession (StreamingFixture)
+ (NSURLSession *)fixture_sessionWithConfiguration:(NSURLSessionConfiguration *)configuration
                                         delegate:(id<NSURLSessionDelegate>)delegate delegateQueue:(NSOperationQueue *)queue;
@end
@implementation NSURLSession (StreamingFixture)
+ (NSURLSession *)fixture_sessionWithConfiguration:(NSURLSessionConfiguration *)configuration
                                         delegate:(id<NSURLSessionDelegate>)delegate delegateQueue:(NSOperationQueue *)queue {
    if (mode == TooLongHeader || mode == TooLongStream) {
        StreamingSession *session = [StreamingSession new];
        session.delegate = (id)delegate;
        return (id)session;
    }
    return [self fixture_sessionWithConfiguration:configuration delegate:delegate delegateQueue:queue];
}
@end

@interface NSURLSessionConfiguration (Fixture)
+ (instancetype)fixture_ephemeralSessionConfiguration;
@end
@implementation NSURLSessionConfiguration (Fixture)
+ (instancetype)fixture_ephemeralSessionConfiguration {
    NSURLSessionConfiguration *configuration = [self fixture_ephemeralSessionConfiguration];
    configuration.protocolClasses = @[MetadataProtocol.class];
    return configuration;
}
@end

static NSData *ask(NSString *path, NSData *body, NSInteger expectedError) {
    __block BOOL finished = NO;
    __block NSData *result;
    SGSpotifyMetadataReply reply = ^(NSData *data, NSInteger status, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            check(error.code == expectedError, [NSString stringWithFormat:@"expected error %ld, got %@", (long)expectedError, error]);
            check(expectedError ? data == nil : status == 200, @"failed transfers expose no body; success carries HTTP 200");
            result = data;
            finished = YES;
        });
    };
    if (allowConstrained) SGSpotifyMetadataRequest(path, body, reply);
    else SGSpotifyMetadataRequestAllowConstrained(path, body, NO, reply);
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5];
    while (!finished && deadline.timeIntervalSinceNow > 0)
        [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.001]];
    check(finished, [NSString stringWithFormat:@"transfer must finish, including cancellation before EOF (mode=%lu, path=%@)",
                    (unsigned long)mode, path]);
    return result;
}
int main(void) {
    @autoreleasepool {
        method_exchangeImplementations(class_getClassMethod(NSURLSessionConfiguration.class, @selector(ephemeralSessionConfiguration)),
                                       class_getClassMethod(NSURLSessionConfiguration.class, @selector(fixture_ephemeralSessionConfiguration)));
        method_exchangeImplementations(class_getClassMethod(NSURLSession.class, @selector(sessionWithConfiguration:delegate:delegateQueue:)),
                                       class_getClassMethod(NSURLSession.class, @selector(fixture_sessionWithConfiguration:delegate:delegateQueue:)));
        NSString *get = @"/metadata/4/album/00000000000000000000000000000001?market=from_token";
        for (NSString *bad in @[@"@attacker.invalid/", @"//attacker.invalid/", @"/other",
             [get stringByAppendingString:@"\n"], [get stringByAppendingString:@"&host=attacker.invalid"],
             @"/metadata/4/album/%2e%2e?market=from_token"]) ask(bad, nil, 1);
        ask(get, [NSData data], 1);
        ask(SGSpotifyExtendedMetadataPath, nil, 1);
        check(headersRead == 0, @"rejected paths cannot request captured credentials");
        allowConstrained = NO;
        check([ask(get, nil, 0) isEqual:[@"{}" dataUsingEncoding:NSUTF8StringEncoding]], @"allowed album endpoint returns body");
        allowConstrained = YES;
        check(ask(SGSpotifyExtendedMetadataPath, [NSData data], 0).length == 2, @"allowed extension endpoint returns body");
        mode = WrongHost; ask(get, nil, 3);
        mode = CrossRedirect; ask(get, nil, 2);
        mode = SameRedirect; ask(get, nil, 2);
        mode = TooLongHeader; ask(get, nil, 4);
        mode = TooLongStream; ask(get, nil, 4);
        mode = AtLimit; check(ask(get, nil, 0).length == 2097152, @"exactly 2 MiB remains accepted");
        mode = Good;
        __block BOOL cancelled = NO;
        dispatch_block_t cancel = SGSpotifyMetadataRequest(get, nil, ^(NSData *data, NSInteger status, NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                check(!data && error.code == NSURLErrorCancelled, @"cancelled metadata exposes cancellation, not a missing record");
                cancelled = YES;
            });
        });
        cancel();
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5];
        while (!cancelled && deadline.timeIntervalSinceNow > 0)
            [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.001]];
        check(cancelled, @"metadata cancellation reaches the active transfer");
        puts("metadata transport: endpoint, response origin, redirects and streaming bounds passed");
    }
    return 0;
}
