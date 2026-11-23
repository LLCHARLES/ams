#import "SGSpotifyMetadata.h"
#import "Shared/Lyrics/Lyrics.h"

static NSString *const kMetadataHost = @"spclient.wg.spotify.com";

static NSError *metadataError(NSInteger code, NSString *reason) {
    return [NSError errorWithDomain:@"Retrine.SpotifyMetadata" code:code userInfo:@{NSLocalizedDescriptionKey: reason}];
}

static NSURL *metadataURL(NSString *path, BOOL post) {
    NSURLComponents *url = [NSURLComponents new];
    url.scheme = @"https";
    url.host = kMetadataHost;
    if (post && [path isEqual:SGSpotifyExtendedMetadataPath]) {
        url.path = SGSpotifyExtendedMetadataPath;
    } else if (!post && [path isKindOfClass:NSString.class] &&
               [path rangeOfString:@"^/metadata/4/album/[0-9a-f]{32}\\?market=from_token\\z"
                           options:NSRegularExpressionSearch].location != NSNotFound) {
        url.path = [path componentsSeparatedByString:@"?"].firstObject;
        url.queryItems = @[[NSURLQueryItem queryItemWithName:@"market" value:@"from_token"]];
    } else return nil;
    return url.URL;
}

@interface SGSpotifyMetadataTransfer : NSObject <NSURLSessionDataDelegate>
@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, strong) NSMutableData *bytes;
@property (nonatomic, copy) SGSpotifyMetadataReply done;
@property (nonatomic) NSInteger status;
- (void)finish:(NSError *)error;
@end

@implementation SGSpotifyMetadataTransfer
- (void)finish:(NSError *)error {
    SGSpotifyMetadataReply done = self.done;
    if (!done) return;
    self.done = nil;
    NSData *bytes = error ? nil : [self.bytes copy];
    self.bytes = nil;
    [self.session invalidateAndCancel];
    self.session = nil;
    done(bytes, self.status, error);
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task
 willPerformHTTPRedirection:(NSHTTPURLResponse *)response newRequest:(NSURLRequest *)request
 completionHandler:(void (^)(NSURLRequest *))completionHandler {
    completionHandler(nil);
    [self finish:metadataError(2, @"Spotify metadata redirects are not allowed.")];
}
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task
 didReceiveResponse:(NSURLResponse *)response completionHandler:(void (^)(NSURLSessionResponseDisposition))completionHandler {
    NSURL *url = response.URL;
    if (![response isKindOfClass:NSHTTPURLResponse.class] || ![url.scheme isEqual:@"https"] ||
        ![url.host isEqual:kMetadataHost] || (url.port && url.port.integerValue != 443)) {
        completionHandler(NSURLSessionResponseCancel);
        [self finish:metadataError(3, @"Spotify metadata response origin did not match.")];
        return;
    }
    self.status = ((NSHTTPURLResponse *)response).statusCode;
    if (response.expectedContentLength > (int64_t)SGSpotifyMetadataMaxResponseBytes) {
        completionHandler(NSURLSessionResponseCancel);
        [self finish:metadataError(4, @"Spotify metadata response exceeds 2 MiB.")];
        return;
    }
    self.bytes = [NSMutableData data];
    completionHandler(NSURLSessionResponseAllow);
}
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveData:(NSData *)data {
    if (!self.done) return;
    if (data.length > SGSpotifyMetadataMaxResponseBytes - self.bytes.length) {
        [self finish:metadataError(4, @"Spotify metadata response exceeds 2 MiB.")];
        return;
    }
    [self.bytes appendData:data];
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    [self finish:error];
}
@end

dispatch_block_t SGSpotifyMetadataRequest(NSString *path, NSData *body, SGSpotifyMetadataReply done) {
    return SGSpotifyMetadataRequestAllowConstrained(path, body, YES, done);
}

dispatch_block_t SGSpotifyMetadataRequestAllowConstrained(NSString *path, NSData *body, BOOL allowConstrained,
                                                          SGSpotifyMetadataReply done) {
    __block BOOL cancelled = NO;
    __block NSURLSessionDataTask *task;
    void (^start)(void) = ^{
    if (cancelled) return;
    NSURL *url = metadataURL(path, body != nil);
    if (!url) {
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            done(nil, 0, metadataError(1, @"Unsupported Spotify metadata endpoint."));
        });
        return;
    }
    SGSpclientHeaders(^(NSDictionary<NSString *, NSString *> *headers) {
        if (cancelled) return;
        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
        request.allowsConstrainedNetworkAccess = allowConstrained;
        request.allHTTPHeaderFields = headers;
        if (body) {
            request.HTTPMethod = @"POST";
            request.HTTPBody = body;
            [request setValue:@"application/x-protobuf" forHTTPHeaderField:@"Content-Type"];
        }
        [request setValue:body ? @"application/x-protobuf" : @"application/json" forHTTPHeaderField:@"Accept"];
        NSURLSessionConfiguration *configuration = NSURLSessionConfiguration.ephemeralSessionConfiguration;
        configuration.URLCache = nil;
        configuration.HTTPCookieStorage = nil;
        configuration.URLCredentialStorage = nil;
        SGSpotifyMetadataTransfer *transfer = [SGSpotifyMetadataTransfer new];
        transfer.done = done;
        transfer.session = [NSURLSession sessionWithConfiguration:configuration delegate:transfer delegateQueue:nil];
        task = [transfer.session dataTaskWithRequest:request];
        [task resume];
    });
    };
    if (NSThread.isMainThread) start();
    else dispatch_async(dispatch_get_main_queue(), start);
    return ^{
        void (^cancel)(void) = ^{
            cancelled = YES;
            [task cancel];
            task = nil;
        };
        if (NSThread.isMainThread) cancel();
        else dispatch_async(dispatch_get_main_queue(), cancel);
    };
}
