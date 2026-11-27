// The real provider and shared URL builder, replacing only the session boundary.
#import <UIKit/UIKit.h>
#import "Shared/LyricsSources/LyricsSources.h"

#define CHECK(cond) do { if (!(cond)) { fprintf(stderr, "FAILED line %d: %s\n", __LINE__, #cond); exit(1); } } while (0)
static id (^replyForRequest)(NSURLRequest *);

@interface NetEaseCheckTask : NSObject
@property (nonatomic, copy) dispatch_block_t work;
- (void)resume;
@end
@implementation NetEaseCheckTask
- (void)resume { dispatch_async(dispatch_get_main_queue(), self.work); }
@end

@interface NetEaseCheckSession : NSObject
+ (instancetype)sharedSession;
- (NetEaseCheckTask *)dataTaskWithRequest:(NSURLRequest *)request
                      completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))done;
@end
@implementation NetEaseCheckSession
+ (instancetype)sharedSession { return [self new]; }
- (NetEaseCheckTask *)dataTaskWithRequest:(NSURLRequest *)request
                      completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))done {
    NetEaseCheckTask *task = [NetEaseCheckTask new];
    task.work = ^{
        NSData *data = [NSJSONSerialization dataWithJSONObject:replyForRequest(request) options:0 error:nil];
        done(data, [[NSHTTPURLResponse alloc] initWithURL:request.URL statusCode:200 HTTPVersion:@"HTTP/1.1" headerFields:nil], nil);
    };
    return task;
}
@end

// Keep the walk's held-provider fixtures independent from this real provider.
#define NSURLSession NetEaseCheckSession
#define SGBoundedRequestTask(request, timeout, ...) [NetEaseCheckSession.sharedSession dataTaskWithRequest:request completionHandler:__VA_ARGS__]
#define SGNetEaseAsk NetEaseCheckAsk
#import "Shared/LyricsSources/NetEase.m"
#undef SGNetEaseAsk
#undef NSURLSession
#undef SGBoundedRequestTask

void checkNetEaseURLs(void) {
    replyForRequest = ^id(NSURLRequest *request) {
        CHECK([request.URL.scheme isEqual:@"https"] && [request.URL.host isEqual:@"music.163.com"]);
        CHECK(request.timeoutInterval == 3 && request.cachePolicy == NSURLRequestReloadIgnoringLocalCacheData);
        CHECK([[request valueForHTTPHeaderField:@"Referer"] isEqual:@"https://music.163.com"]);
        NSMutableDictionary *query = [NSMutableDictionary dictionary];
        for (NSURLQueryItem *item in [NSURLComponents componentsWithURL:request.URL resolvingAgainstBaseURL:NO].queryItems)
            query[item.name] = item.value;
        if ([request.URL.path isEqual:@"/api/search/get"]) {
            CHECK(([query isEqual:@{@"s": @"A & B? #한글 singer+one", @"type": @"1", @"limit": @"10"}]));
            return @{@"result": @{@"songs": @[@{@"id": @42, @"name": @"A & B? #한글", @"duration": @200000,
                                               @"artists": @[@{@"name": @"Singer+One"}]}]}};
        }
        CHECK([request.URL.path isEqual:@"/api/song/lyric/v1"]);
        CHECK(([query isEqual:@{@"id": @"42", @"lv": @"1", @"yv": @"1", @"tv": @"-1"}]));
        return @{@"yrc": @{@"lyric": @"[1000,1000](1000,1000,0)Hello"}};
    };
    SGLyricsQuery *query = [SGLyricsQuery new];
    query.title = @"A & B? #한글";
    query.artist = @"Singer+One feat Guest";
    query.seconds = 200;
    __block BOOL finished = NO;
    NetEaseCheckAsk(query, ^(SGLyricsResult *result) {
        CHECK(NSThread.isMainThread);
        CHECK([SGKaraokeLineText(result.karaokeLines.firstObject) isEqual:@"Hello"]);
        finished = YES;
    });
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:60];
    while (!finished && deadline.timeIntervalSinceNow > 0)
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
    CHECK(finished);
    replyForRequest = nil;
    puts("NetEase: escaped search and lyric URLs, request policy and main-queue answer passed");
}
