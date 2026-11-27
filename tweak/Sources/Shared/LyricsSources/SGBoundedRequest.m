#import "SGBoundedRequest.h"

static const NSUInteger kMaxReplyBytes = 2 * 1024 * 1024;

static NSNumber *effectivePort(NSURL *url) {
    return url.port ?: ([url.scheme.lowercaseString isEqual:@"https"] ? @443 : @80);
}

@interface SGLyricsSourceTransfer : NSObject <NSURLSessionDataDelegate>
@property (nonatomic, strong) NSMutableData *data;
@property (nonatomic, strong) NSURLResponse *response;
@property (nonatomic, copy) void (^done)(NSData *, NSURLResponse *, NSError *);
@property (nonatomic) BOOL oversized;
@end
@implementation SGLyricsSourceTransfer
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task
 didReceiveResponse:(NSURLResponse *)response completionHandler:(void (^)(NSURLSessionResponseDisposition))completion {
    self.response = response;
    self.oversized = response.expectedContentLength > (int64_t)kMaxReplyBytes;
    completion(self.oversized ? NSURLSessionResponseCancel : NSURLSessionResponseAllow);
}
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveData:(NSData *)data {
    if (self.oversized) return;
    if (data.length > kMaxReplyBytes - self.data.length) { self.oversized = YES; [task cancel]; return; }
    [self.data appendData:data];
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task
 willPerformHTTPRedirection:(NSHTTPURLResponse *)response newRequest:(NSURLRequest *)request
 completionHandler:(void (^)(NSURLRequest *))completion {
    NSURLRequest *original = task.originalRequest;
    NSURL *from = original.URL, *to = request.URL;
    if (![from.scheme.lowercaseString isEqual:to.scheme.lowercaseString] ||
        ![from.host.lowercaseString isEqual:to.host.lowercaseString] ||
        ![effectivePort(from) isEqual:effectivePort(to)]) {
        completion(nil);
        return;
    }
    NSMutableURLRequest *next = [request mutableCopy];
    [original.allHTTPHeaderFields enumerateKeysAndObjectsUsingBlock:^(NSString *name, NSString *value, BOOL *stop) {
        // Keep URLSession's method/body rewrite on a POST-to-GET redirect.
        if (![original.HTTPMethod isEqual:next.HTTPMethod] &&
            ([name.lowercaseString hasPrefix:@"content-"] || [name.lowercaseString isEqual:@"transfer-encoding"])) return;
        if (![next valueForHTTPHeaderField:name]) [next setValue:value forHTTPHeaderField:name];
    }];
    completion(next);
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    if (self.oversized) error = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorDataLengthExceedsMaximum userInfo:nil];
    self.done(error ? nil : [self.data copy], self.response, error);
    self.done = nil;
    [session finishTasksAndInvalidate];
}
@end

NSURLSessionDataTask *SGBoundedRequestTask(NSURLRequest *request, NSTimeInterval resourceTimeout,
    void (^done)(NSData *, NSURLResponse *, NSError *)) {
    NSURLSessionConfiguration *config = NSURLSessionConfiguration.ephemeralSessionConfiguration;
    config.HTTPCookieStorage = nil;
    config.HTTPShouldSetCookies = NO;
    config.URLCredentialStorage = nil;
    config.URLCache = nil;
    if (resourceTimeout) config.timeoutIntervalForResource = resourceTimeout;
    SGLyricsSourceTransfer *transfer = [SGLyricsSourceTransfer new];
    transfer.data = [NSMutableData data];
    transfer.done = done;
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config delegate:transfer delegateQueue:nil];
    return [session dataTaskWithRequest:request];
}
