#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import "Shared/LocalFiles/LocalInfoLookup.h"

#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); exit(1); } } while (0)

static NSData *json(id object) { return [NSJSONSerialization dataWithJSONObject:object options:0 error:nil]; }
static NSDictionary *song(NSString *title, NSString *artist, double ms) {
    return @{@"trackName": title, @"artistName": artist, @"trackTimeMillis": @(ms)};
}
static NSArray *rank(NSArray *rows, NSString *title, NSString *artist, double seconds) {
    return SGLocalInfoRank(SGLocalInfoParse(json(@{@"results": rows})), title, artist, seconds);
}

static NSData *reply;
static BOOL stalled;
static NSUInteger starts;
static NSDictionary<NSString *, NSString *> *redirects;
static NSInteger status = 200;
@interface FixtureProtocol : NSURLProtocol @end
@implementation FixtureProtocol
+ (BOOL)canInitWithRequest:(NSURLRequest *)request { return YES; }
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request { return request; }
- (void)startLoading {
    ++starts;
    if (stalled) return;
    NSString *target = redirects[self.request.URL.absoluteString];
    if (target) {
        NSHTTPURLResponse *redirect = [[NSHTTPURLResponse alloc] initWithURL:self.request.URL statusCode:302
            HTTPVersion:@"HTTP/1.1" headerFields:@{@"Location": target}];
        [self.client URLProtocol:self wasRedirectedToRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:target]]
            redirectResponse:redirect];
        return;
    }
    NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:self.request.URL statusCode:status
        HTTPVersion:@"HTTP/1.1" headerFields:@{}];
    [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    [self.client URLProtocol:self didLoadData:reply];
    [self.client URLProtocolDidFinishLoading:self];
}
- (void)stopLoading {}
@end

static void pump(BOOL (^done)(void)) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:60];
    while (!done() && deadline.timeIntervalSinceNow > 0)
        [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    CHECK(done());
}

static void search(NSString *term, NSString *country, BOOL succeeds) {
    // A fresh screen/owner must still reuse the app-lifetime cache.
    SGLocalInfoLookup *lookup = [SGLocalInfoLookup new];
    __block BOOL done = NO;
    [lookup search:SGLocalInfoSearchURL(term, country) completion:^(NSArray *songs, NSError *error) {
        CHECK(succeeds ? (songs != nil && !error) : (songs == nil && error != nil));
        done = YES;
    }];
    pump(^BOOL { return done; });
}

static void cover(NSString *url, BOOL succeeds) {
    SGLocalInfoLookup *lookup = [SGLocalInfoLookup new];
    __block BOOL done = NO;
    [lookup cover:[NSURL URLWithString:url] completion:^(NSData *data, NSError *error) {
        CHECK(succeeds ? (data != nil && !error) : (data == nil && error != nil));
        done = YES;
    }];
    pump(^BOOL { return done; });
}

int main(void) {
    @autoreleasepool {
        CHECK([SGLocalInfoQuery(@"012 - Café (Live [HQ]) [clip] OFFICIAL video Audio lyrics lyric HD hq 4K visualizer explicit Remastered remaster",
                               @"Artist", @"unused.mp3") isEqual:@"Café Artist"]);
        CHECK([SGLocalInfoQuery(@"Officially Videohead", @"", @"") isEqual:@"Officially Videohead"]);
        CHECK([SGLocalInfoQuery(@"", @"", @"003. Song Name.flac") isEqual:@"Song Name"]);
        CHECK([SGLocalInfoQuery(@"1000 Ways", @"", @"") isEqual:@"1000 Ways"]);
        NSURLComponents *url = [NSURLComponents componentsWithURL:SGLocalInfoSearchURL(@"A & B + C", @"KR") resolvingAgainstBaseURL:NO];
        NSMutableDictionary *query = [NSMutableDictionary dictionary];
        for (NSURLQueryItem *item in url.queryItems) query[item.name] = item.value;
        CHECK([url.host isEqual:@"itunes.apple.com"] && [url.path isEqual:@"/search"]);
        CHECK(([query isEqual:@{@"term": @"A & B + C", @"media": @"music", @"entity": @"song", @"limit": @"10", @"country": @"kr"}]));
        CHECK([NSURLComponents componentsWithURL:SGLocalInfoSearchURL(@"a", nil) resolvingAgainstBaseURL:NO].queryItems.count == 4);

        NSArray *boundary = @[song(@"lower", @"", 97000), song(@"upper", @"", 103000),
            song(@"below", @"", 96999), song(@"above", @"", 103001), song(@"zero", @"", 0)];
        NSArray *bounded = rank(boundary, @"", @"", 100);
        CHECK(bounded.count == 2 && [bounded[0][@"title"] isEqual:@"lower"] && [bounded[1][@"title"] isEqual:@"upper"]);
        CHECK(rank(boundary, @"", @"", 0).count == 4);
        NSArray *ambiguous = rank(@[song(@"Home (Live)", @"Right", 100000), song(@"Home", @"Wrong", 100000),
            song(@"Home", @"Right", 102000), song(@"Home", @"Right", 100000)], @"Home", @"Right", 100);
        CHECK([ambiguous[0][@"artist"] isEqual:@"Right"] && [ambiguous[0][@"milliseconds"] intValue] == 100000);
        CHECK([ambiguous[1][@"milliseconds"] intValue] == 102000);
        CHECK([ambiguous[2][@"artist"] isEqual:@"Wrong"]);
        CHECK([ambiguous[3][@"title"] isEqual:@"Home (Live)"]);
        NSArray *featured = rank(@[song(@"Deja Vu", @"Beyonce feat. Guest", 100000),
            song(@"Déjà-Vu", @"BEYONCÉ", 100000), song(@"Déjà Vu Remaster", @"Beyoncé", 100000)], @"DÉJÀ vu", @"Beyonce", 100);
        CHECK([featured[0][@"title"] isEqual:@"Déjà-Vu"]);
        CHECK([featured[1][@"artist"] isEqual:@"Beyonce feat. Guest"]);

        NSArray *parsed = SGLocalInfoParse(json(@{@"results": @[
            NSNull.null, @7, @{}, @{@"trackName": @"bad", @"trackTimeMillis": @"100"},
            @{@"trackName": @"bad", @"trackTimeMillis": @YES}, @{@"trackName": @7, @"trackTimeMillis": @100},
            @{@"trackName": @"Valid", @"trackTimeMillis": @100, @"artistName": NSNull.null,
              @"collectionName": @[], @"releaseDate": @2020, @"artworkUrl100": @7},
            @{@"trackName": @"Dated", @"trackTimeMillis": @100, @"releaseDate": @"2024-01-01T00:00:00Z"}
        ]}));
        CHECK(parsed.count == 2 && [parsed[0][@"artist"] isEqual:@""] && [parsed[0][@"album"] isEqual:@""] &&
              [parsed[0][@"cover"] isEqual:@""] && [parsed[0][@"year"] isEqual:@""] && [parsed[1][@"year"] isEqual:@"2024"]);
        CHECK(!SGLocalInfoParse(json(@[])) && !SGLocalInfoParse(json(@{@"results": @4})) &&
              !SGLocalInfoParse([@"{" dataUsingEncoding:NSUTF8StringEncoding]));
        NSMutableData *full = [json(@{@"results": @[]}) mutableCopy];
        while (full.length < 2 * 1024 * 1024) [full appendBytes:" " length:1];
        CHECK(SGLocalInfoParse(full) != nil);
        [full appendBytes:" " length:1];
        CHECK(SGLocalInfoParse(full) == nil);
        CHECK([SGLocalInfoArtworkURL(@"https://is1-ssl.mzstatic.com/100x100bb.jpg") isEqual:@"https://is1-ssl.mzstatic.com/600x600bb.jpg"]);
        CHECK(SGLocalInfoArtworkURL(@"https://mzstatic.com/x") && SGLocalInfoArtworkURL(@"https://IS2-SSL.MZSTATIC.COM/x"));
        for (NSString *bad in @[@"file:///tmp/x", @"http://is1-ssl.mzstatic.com/x",
             @"https://example.com/x", @"https://evilmzstatic.com/x", @"https://mzstatic.com.evil.example/x",
             @"https://itunes.apple.com/x", @"https://user@is1-ssl.mzstatic.com/x"])
            CHECK(!SGLocalInfoArtworkURL(bad));

        Method method = class_getClassMethod(NSURLSessionConfiguration.class, @selector(ephemeralSessionConfiguration));
        IMP original = method_getImplementation(method);
        method_setImplementation(method, imp_implementationWithBlock(^id(id cls) {
            NSURLSessionConfiguration *config = ((id (*)(id, SEL))original)(cls, @selector(ephemeralSessionConfiguration));
            config.protocolClasses = @[FixtureProtocol.class];
            return config;
        }));
        // Observe the actual configuration supplied to the session, not defaults before fetch configures it.
        Method factory = class_getClassMethod(NSURLSession.class, @selector(sessionWithConfiguration:delegate:delegateQueue:));
        IMP makeSession = method_getImplementation(factory);
        method_setImplementation(factory, imp_implementationWithBlock(^id(id cls, NSURLSessionConfiguration *config, id delegate, NSOperationQueue *queue) {
            CHECK(config.timeoutIntervalForRequest == 15 && config.timeoutIntervalForResource == 15);
            CHECK(!config.HTTPShouldSetCookies && !config.HTTPCookieStorage && !config.URLCache);
            CHECK(!config.allowsConstrainedNetworkAccess);
            return ((id (*)(id, SEL, id, id, id))makeSession)(cls, @selector(sessionWithConfiguration:delegate:delegateQueue:), config, delegate, queue);
        }));
        SGLocalInfoLookup *lookup = [SGLocalInfoLookup new];
        reply = [NSMutableData dataWithLength:4 * 1024 * 1024 + 1];
        __block BOOL done = NO;
        [lookup cover:[NSURL URLWithString:@"https://is1-ssl.mzstatic.com/fixture"] completion:^(NSData *data, NSError *error) {
            CHECK(!data && error.code == NSURLErrorDataLengthExceedsMaximum);
            done = YES;
        }];
        pump(^BOOL { return done; });
        stalled = YES;
        NSUInteger before = starts;
        [lookup search:SGLocalInfoSearchURL(@"cancel", nil) completion:^(NSArray *songs, NSError *error) { CHECK(NO); }];
        [lookup search:SGLocalInfoSearchURL(@"duplicate", nil) completion:^(NSArray *songs, NSError *error) { CHECK(NO); }];
        pump(^BOOL { return starts > before; });
        CHECK(starts == before + 1 && lookup.busy);
        [lookup cancel];
        CHECK(!lookup.busy);
        stalled = NO;
        reply = json(@{@"results": @[]});
        before = starts;
        cover(@"https://example.com/art.jpg", NO);
        CHECK(starts == before);
        redirects = @{@"https://is1-ssl.mzstatic.com/redirect": @"https://evil.example/art.jpg"};
        cover(@"https://is1-ssl.mzstatic.com/redirect", NO);
        CHECK(starts == before + 1); // denied destination must never receive a request
        redirects = @{@"https://is1-ssl.mzstatic.com/redirect": @"https://is2-ssl.mzstatic.com/next",
                      @"https://is2-ssl.mzstatic.com/next": @"https://evilmzstatic.com/art.jpg"};
        before = starts;
        cover(@"https://is1-ssl.mzstatic.com/redirect", NO);
        CHECK(starts == before + 2); // revalidate every redirect, not only the first hop
        redirects = @{@"https://is1-ssl.mzstatic.com/redirect": @"https://mzstatic.com/ok"};
        cover(@"https://is1-ssl.mzstatic.com/redirect", YES);
        NSString *searchURL = SGLocalInfoSearchURL(@"redirect", nil).absoluteString;
        redirects = @{searchURL: @"https://is1-ssl.mzstatic.com/not-search"};
        before = starts;
        search(@"redirect", nil, NO);
        CHECK(starts == before + 1);
        redirects = @{searchURL: @"https://itunes.apple.com/search?term=redirected"};
        search(@"redirect", nil, YES);
        redirects = nil;

        before = starts;
        search(@"country", @"us", YES);
        search(@"country", @"gb", YES);
        CHECK(starts == before + 2);
        search(@"country", @"us", YES);
        CHECK(starts == before + 2);
        for (NSUInteger i = 0; i < 32; ++i) search([NSString stringWithFormat:@"cache-%lu", (unsigned long)i], @"kr", YES);
        before = starts;
        search(@"cache-0", @"kr", YES);
        CHECK(starts == before);
        search(@"cache-32", @"kr", YES);
        CHECK(starts == before + 1);
        search(@"cache-1", @"kr", YES);
        CHECK(starts == before + 1);
        search(@"cache-0", @"kr", YES);
        CHECK(starts == before + 2);
        reply = [@"{" dataUsingEncoding:NSUTF8StringEncoding];
        before = starts;
        search(@"malformed", nil, NO);
        search(@"malformed", nil, NO);
        CHECK(starts == before + 2);
        reply = json(@{@"results": @[]});
        status = 500;
        before = starts;
        search(@"server-failure", nil, NO);
        status = 200;
        search(@"server-failure", nil, YES);
        CHECK(starts == before + 2);
        puts("PASS query, request, duration, ranking, parsing/caps, trusted hosts/redirects, FIFO cache, transport/cancel (no network)");
    }
    return 0;
}
