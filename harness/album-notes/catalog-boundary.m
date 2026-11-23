#import "catalog-boundary.h"
#import "Shared/AnimatedArtwork/AnimatedArtwork.h"
#import "Shared/SpotifyMetadata/SGSpotifyMetadata.h"
#import "../motion/no-recording-lookup.h"

BOOL SGMotionAppleMusicOn(void) { return YES; }
dispatch_block_t SGSpotifyMetadataRequestAllowConstrained(NSString *path, NSData *body, BOOL allow, SGSpotifyMetadataReply done) {
    CHECK(NO); return ^{};
}

NSDictionary *CatalogFixture;
BOOL CatalogLowData;
NSInteger CatalogStatus = 200;
NSUInteger CatalogSearches, CatalogAlbumRequests, CatalogMediaRequests, CatalogDownloads;
NSUInteger CatalogArtistRequests;
NSURL *CatalogRoot;
NSMutableArray<NSString *> *CatalogAssetPaths;
static id priorToken;
static NSData *imageData;

BOOL SGFlag(NSString *key, BOOL fallback) { return [key isEqual:SGKeyMotionLowData] ? CatalogLowData : fallback; }
CGFloat SGMotionPixels(void) { return 720; }
NSURL *SGMotionTestAlbumAnswersFile(void) { return [CatalogRoot URLByAppendingPathComponent:@"answers.plist"]; }
void SGMotionFile(NSURL *remote, void (^done)(NSURL *)) {
    if (remote) CatalogDownloads++;
    done(remote ? [NSURL fileURLWithPath:@"/fixture/clip.mp4"] : nil);
}
// The ticketed download the catalog's own chain asks for; the fixture answers at once, so nothing is left to cancel.
SGMotionTicket *SGMotionRequestFile(NSURL *remote, void (^done)(NSURL *)) {
    SGMotionFile(remote, done);
    return [SGMotionTicket new];
}
// The store's half of the settings page's clear (SGMotionCacheBytes, SGMotionCacheClear); the fixture holds no clips.
void SGMotionStoreBytes(void (^done)(uint64_t bytes)) { done(0); }
void SGMotionStoreClear(void (^done)(BOOL complete)) { done(YES); }

@interface ReplayedCatalog : NSURLProtocol @end
@implementation ReplayedCatalog
+ (BOOL)canInitWithRequest:(NSURLRequest *)request { return YES; }
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request { return request; }
- (void)startLoading {
    dispatch_async(dispatch_get_main_queue(), ^{
        CHECK(self.request.allowsConstrainedNetworkAccess == CatalogLowData);
        NSURL *url = self.request.URL;
        NSURLComponents *components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
        NSMutableDictionary *query = [NSMutableDictionary dictionary];
        for (NSURLQueryItem *item in components.queryItems) query[item.name] = item.value;
        NSData *data;
        NSInteger status = 200;
        if ([url.host isEqual:@"amp-api.music.apple.com"]) {
            status = CatalogStatus;
            if ([url.path hasSuffix:@"/search"]) {
                CatalogSearches++;
                if ([query[@"types"] isEqual:@"artists"])
                    CHECK([query[@"extend"] isEqual:@"editorialArtwork,editorialVideo"]);
                data = [NSJSONSerialization dataWithJSONObject:CatalogFixture options:0 error:nil];
            } else if ([url.path hasSuffix:@"/albums"]) {
                CatalogAlbumRequests++;
                NSString *identifier = url.URLByDeletingLastPathComponent.lastPathComponent;
                NSNumber *override = CatalogFixture[@"artistAlbumStatuses"][identifier];
                if (override) status = override.integerValue;
                if (override && status == 0) {
                    [self.client URLProtocol:self didFailWithError:[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorNotConnectedToInternet userInfo:nil]];
                    return;
                }
                NSDictionary *albums = query[@"offset"] ? CatalogFixture[@"artistAlbumPages"][identifier][query[@"offset"]] : CatalogFixture[@"artistAlbums"][identifier];
                CHECK(albums != nil);
                data = [NSJSONSerialization dataWithJSONObject:albums options:0 error:nil];
            } else {
                CHECK([url.path containsString:@"/artists/"] && [query[@"extend"] isEqual:@"editorialVideo"]);
                CatalogArtistRequests++;
                NSDictionary *resource = CatalogFixture[@"artistResources"][url.lastPathComponent];
                CHECK(resource != nil);
                data = [NSJSONSerialization dataWithJSONObject:resource options:0 error:nil];
            }
        } else {
            CHECK([url.host isEqual:@"fixture.invalid"]);
            CatalogMediaRequests++;
            [CatalogAssetPaths addObject:url.path];
            if ([url.path hasSuffix:@"/master.m3u8"])
                data = [@"#EXTM3U\n#EXT-X-STREAM-INF:RESOLUTION=720x720\nmedia.m3u8" dataUsingEncoding:NSUTF8StringEncoding];
            else if ([url.path hasSuffix:@"/media.m3u8"])
                data = [@"#EXTM3U\nclip.mp4" dataUsingEncoding:NSUTF8StringEncoding];
            else {
                CHECK([url.path hasSuffix:@".png"]);
                data = imageData;
            }
        }
        NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:url statusCode:status HTTPVersion:@"HTTP/1.1" headerFields:nil];
        [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
        [self.client URLProtocol:self didLoadData:data];
        [self.client URLProtocolDidFinishLoading:self];
    });
}
- (void)stopLoading {}
@end

void CatalogWait(BOOL (^ready)(void)) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5];
    while (!ready() && deadline.timeIntervalSinceNow > 0)
        [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.001]];
    CHECK(ready());
}
void CatalogStart(NSString *path) {
    NSData *data = [NSData dataWithContentsOfFile:path];
    CHECK(data != nil);
    CatalogFixture = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    CHECK([CatalogFixture isKindOfClass:NSDictionary.class]);
    CatalogAssetPaths = [NSMutableArray array];
    NSString *workspace = NSProcessInfo.processInfo.environment[@"RETRINE_TEST_ROOT"];
    CHECK(workspace.length > 0);
    CatalogRoot = [NSURL fileURLWithPath:workspace isDirectory:YES];
    CHECK([NSFileManager.defaultManager createDirectoryAtURL:CatalogRoot withIntermediateDirectories:YES attributes:nil error:nil]);
    priorToken = [NSUserDefaults.standardUserDefaults objectForKey:@"spotifyglass.motion.token"];
    NSData *claims = [NSJSONSerialization dataWithJSONObject:@{@"exp": @4102444800} options:0 error:nil];
    [NSUserDefaults.standardUserDefaults setObject:[NSString stringWithFormat:@"e30.%@.test", [claims base64EncodedStringWithOptions:0]]
                                          forKey:@"spotifyglass.motion.token"];
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat];
    format.scale = 1;
    imageData = [[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(1, 1) format:format]
        PNGDataWithActions:^(UIGraphicsImageRendererContext *context) { [UIColor.redColor setFill]; UIRectFill(CGRectMake(0, 0, 1, 1)); }];
    CHECK([NSURLProtocol registerClass:ReplayedCatalog.class]);
}
void CatalogFinish(void) {
    [NSURLProtocol unregisterClass:ReplayedCatalog.class];
    if (priorToken) [NSUserDefaults.standardUserDefaults setObject:priorToken forKey:@"spotifyglass.motion.token"];
    else [NSUserDefaults.standardUserDefaults removeObjectForKey:@"spotifyglass.motion.token"];
    // Catalog disk writes are serial but intentionally asynchronous; the caller
    // waits for the expected persisted answer before removing its own workspace.
    CHECK([NSFileManager.defaultManager removeItemAtURL:CatalogRoot error:nil]);
}
