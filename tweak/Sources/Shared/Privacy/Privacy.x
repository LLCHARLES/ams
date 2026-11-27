// Telemetry blocking: an NSURLProtocol that answers the analytics endpoints itself instead of
// letting them out, and keeps a count of what it stopped for the Privacy page.
//
// The SDKs Spotify ships each send somewhere of their own: Firebase to app-measurement.com, Facebook
// to graph.facebook.com/<id>/activities, then Branch, Comscore, Segment. None of it carries playback,
// search, sign-in or deep links, so a whole host is named where it does nothing else and a path where
// it does. Spotify's own events, sent to spclient's
// /gabo-receiver-service/, are left alone: Recents is built from the plays reported among them.
//
// A protocol handed to +registerClass: is only consulted by NSURLConnection and the shared
// session, so both session configurations are given it as well: that is what the SDKs build their
// sessions from. What the core sends over its own sockets is out of reach either way.
#import "Core/SGCore.h"
#import "Core/SGCounterStore.h"
#import "Privacy.h"

typedef struct { const char *host, *path, *label; } SGBlockRule;

// host matched on the domain and its subdomains, path as a substring; no path means the whole host.
static const SGBlockRule kRules[] = {
    {"app-measurement.com",               NULL,                      "Firebase"},
    {"crashlytics.com",                   NULL,                      "Crashlytics"},
    {"facebook.com",                      "/activities",             "Facebook"},
    {"ep1.facebook.com",                  NULL,                      "Facebook"},
    {"ep2.facebook.com",                  NULL,                      "Facebook"},
    {"branch.io",                         "/v1/event",               "Branch"},
    {"scorecardresearch.com",             NULL,                      "Comscore"},
    {"segment.io",                        NULL,                      "Segment"},
    {"zqtk.net",                          NULL,                      "Segment"},
    {"google-analytics.com",              NULL,                      "Google"},
    {"googleadservices.com",              NULL,                      "Google"},
    {"doubleclick.net",                   NULL,                      "Google"},
};
static const size_t kRuleCount = sizeof(kRules) / sizeof(kRules[0]);

static NSString *const kCounts = @"spotifyglass.privacy.counts";
@interface SGBlockProtocol : NSURLProtocol
@end

static SGCounterStore *counter(void) {
    static SGCounterStore *store;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        store = [[SGCounterStore alloc] initWithKey:kCounts prepare:^BOOL(NSMutableDictionary *counts) {
            // Drop obsolete labels in memory so the total adds up to the rows the page shows.
            NSSet<NSString *> *current = [NSSet setWithArray:SGBlockedLabels()];
            for (NSString *label in counts.allKeys) {
                if (![current containsObject:label]) counts[label] = nil;
            }
            return NO;
        }];
    });
    return store;
}

static NSString *labelFor(NSURL *url) {
    NSString *host = url.host.lowercaseString;
    if (!host) return nil;
    NSString *path = url.path ?: @"";
    // Both protocol admission and loading run this matcher for every request.
    // The rules never change; convert their C strings and build suffixes only once.
    static NSArray<NSArray<NSString *> *> *rules;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableArray *built = [NSMutableArray arrayWithCapacity:kRuleCount];
        for (size_t i = 0; i < kRuleCount; i++) {
            NSString *domain = @(kRules[i].host);
            [built addObject:@[domain, [@"." stringByAppendingString:domain],
                               kRules[i].path ? @(kRules[i].path) : @"", @(kRules[i].label)]];
        }
        rules = [built copy];
    });
    for (NSArray<NSString *> *rule in rules) {
        if (![host isEqualToString:rule[0]] && ![host hasSuffix:rule[1]]) continue;
        if ([rule[2] length] && ![path containsString:rule[2]]) continue;
        return rule[3];
    }
    return nil;
}

NSArray<NSString *> *SGBlockedLabels(void) {
    NSMutableArray<NSString *> *labels = [NSMutableArray array];
    for (size_t i = 0; i < kRuleCount; i++) {
        NSString *label = @(kRules[i].label);
        if (![labels containsObject:label]) [labels addObject:label];
    }
    return labels;
}

NSUInteger SGBlockedCount(NSString *label) {
    NSDictionary<NSString *, NSNumber *> *counts = counter().counts;
    if (label) return counts[label].unsignedIntegerValue;
    NSUInteger total = 0;
    for (NSNumber *count in counts.allValues) total += count.unsignedIntegerValue;
    return total;
}

void SGResetBlocked(void) {
    [counter() reset];
}

@implementation SGBlockProtocol

+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    return labelFor(request.URL) != nil;
}

+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request {
    return request;
}

- (void)startLoading {
    NSString *label = labelFor(self.request.URL);
    if (label) [counter() increment:label];
    // 204 rather than an error: the sender takes it for delivered and queues no retry behind it.
    NSHTTPURLResponse *answer = [[NSHTTPURLResponse alloc] initWithURL:self.request.URL statusCode:204 HTTPVersion:@"HTTP/1.1" headerFields:@{}];
    [self.client URLProtocol:self didReceiveResponse:answer cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    [self.client URLProtocolDidFinishLoading:self];
}

- (void)stopLoading {
}

@end

static NSURLSessionConfiguration *carryingProtocol(NSURLSessionConfiguration *configuration) {
    if (!configuration || [configuration.protocolClasses containsObject:SGBlockProtocol.class]) return configuration;
    NSMutableArray *classes = [configuration.protocolClasses mutableCopy] ?: [NSMutableArray array];
    [classes insertObject:SGBlockProtocol.class atIndex:0];
    configuration.protocolClasses = classes;
    return configuration;
}

%hook NSURLSessionConfiguration

+ (NSURLSessionConfiguration *)defaultSessionConfiguration {
    NSURLSessionConfiguration *configuration = %orig;
    return carryingProtocol(configuration);
}

+ (NSURLSessionConfiguration *)ephemeralSessionConfiguration {
    NSURLSessionConfiguration *configuration = %orig;
    return carryingProtocol(configuration);
}

%end

%ctor {
    for (NSNotificationName name in @[UIApplicationWillResignActiveNotification, UIApplicationWillTerminateNotification])
        [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:nil usingBlock:^(NSNotification *note) {
            [counter() flush];
        }];
    if (SGEnabled(SGKeyBlockTelemetry)) {
        [NSURLProtocol registerClass:SGBlockProtocol.class];
        %init;
    }
}
