#import "InboundLinks.h"
#import "LinkURL.h"

static const NSTimeInterval SGLinkResolutionTimeoutSeconds = 5;

@interface SGHTTPSLinkResolution : NSObject <NSURLSessionDataDelegate>
@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, copy) SGLinkResolved completion;
@end

@implementation SGHTTPSLinkResolution
- (void)finish:(NSURL *)url error:(NSError *)error {
    SGLinkResolved completion = self.completion;
    self.completion = nil;
    if (completion) completion(url, error);
    [self.session invalidateAndCancel];
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task
        willPerformHTTPRedirection:(NSHTTPURLResponse *)response newRequest:(NSURLRequest *)request
        completionHandler:(void (^)(NSURLRequest *))completion {
    NSURL *target = SGIsSpotifyHTTPSURL(request.URL) ? SGPublicSpotifyURLFromText(request.URL.absoluteString) : nil;
    if (!target) {
        completion(nil);
        [self finish:nil error:[NSError errorWithDomain:@"RetrineLinks" code:NSURLErrorUnsupportedURL userInfo:nil]];
    } else if (SGSpotifyURLNeedsResolution(target)) {
        NSMutableURLRequest *next = [request mutableCopy];
        next.HTTPMethod = @"HEAD";
        completion(next);
    } else {
        completion(nil);
        [self finish:target error:nil];
    }
}
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task
        didReceiveResponse:(NSURLResponse *)response completionHandler:(void (^)(NSURLSessionResponseDisposition))completion {
    completion(NSURLSessionResponseCancel);
    [self finish:nil error:[NSError errorWithDomain:@"RetrineLinks" code:NSURLErrorBadServerResponse userInfo:nil]];
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    [self finish:nil error:error];
    self.session = nil;
}
@end

id<SGLinkCancellation> SGResolveSpotifyPublicLink(NSURL *url, SGLinkResolved completion) {
    if (!SGSpotifyURLNeedsResolution(url)) {
        completion(nil, [NSError errorWithDomain:@"RetrineLinks" code:NSURLErrorUnsupportedURL userInfo:nil]);
        return nil;
    }
    NSURLSessionConfiguration *config = NSURLSessionConfiguration.ephemeralSessionConfiguration;
    config.timeoutIntervalForRequest = SGLinkResolutionTimeoutSeconds;
    config.timeoutIntervalForResource = SGLinkResolutionTimeoutSeconds;
    config.HTTPCookieStorage = nil;
    config.URLCredentialStorage = nil;
    config.URLCache = nil;
    config.HTTPShouldSetCookies = NO;
    SGHTTPSLinkResolution *resolution = [SGHTTPSLinkResolution new];
    resolution.completion = completion;
    resolution.session = [NSURLSession sessionWithConfiguration:config delegate:resolution delegateQueue:nil];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"HEAD";
    NSURLSessionDataTask *task = [resolution.session dataTaskWithRequest:request];
    [task resume];
    return (id<SGLinkCancellation>)task;
}

@implementation SGInboundLinks {
    SGLinkResolver _resolver;
    BOOL (^_opener)(NSURL *);
    id<SGLinkCancellation> _request;
    NSUInteger _generation;
    NSURL *_pending;
    BOOL _ready;
}
- (instancetype)initWithResolver:(SGLinkResolver)resolver opener:(BOOL (^)(NSURL *))opener {
    if ((self = [super init])) {
        _resolver = [resolver copy];
        _opener = [opener copy];
    }
    return self;
}
- (void)deliver:(NSURL *)url {
    if (!url) return;
    if (!_ready) { _pending = url; return; }
    if (!_opener(url)) NSLog(@"[spotifyglass] links: public navigation unavailable");
}
- (BOOL)acceptURL:(NSURL *)url {
    NSUInteger generation = ++_generation;
    [_request cancel];
    _request = nil;
    _pending = nil;
    NSURL *target = SGPublicSpotifyURLFromText(url.absoluteString);
    if (!target) return NO;
    if (!SGSpotifyURLNeedsResolution(target)) {
        [self deliver:target];
        return YES;
    }
    __weak SGInboundLinks *weakSelf = self;
    _request = _resolver(target, ^(NSURL *resolved, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            SGInboundLinks *owner = weakSelf;
            if (!owner || generation != owner->_generation) return;
            owner->_request = nil;
            NSURL *valid = SGPublicSpotifyURLFromText(resolved.absoluteString);
            if (!valid || SGSpotifyURLNeedsResolution(valid)) {
                NSLog(@"[spotifyglass] links: no public destination (%@/%ld)", error.domain, (long)error.code);
                return;
            }
            [owner deliver:valid];
        });
    });
    return YES;
}
- (void)setReady:(BOOL)ready {
    _ready = ready;
    if (ready && _pending) {
        NSURL *pending = _pending;
        _pending = nil;
        [self deliver:pending];
    }
}
- (void)dealloc {
    [_request cancel];
}
@end

BOOL SGSupportsSpotifyLinkDispatch(Class dispatcherClass, Class reasonClass) {
    if (![dispatcherClass instancesRespondToSelector:NSSelectorFromString(@"setMainUILoaded:")]) return NO;
    return [dispatcherClass instancesRespondToSelector:NSSelectorFromString(@"navigateToURI:options:reason:completionHandler:resultHandler:")] &&
           [reasonClass instancesRespondToSelector:NSSelectorFromString(@"initWithSourceApplication:interactionID:")];
}
