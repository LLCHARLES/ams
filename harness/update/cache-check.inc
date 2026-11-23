// A deterministic GitHub reply through the real update session, without a network connection.
#import <objc/runtime.h>

@interface CacheReply : NSURLProtocol
@end
@implementation CacheReply
+ (BOOL)canInitWithRequest:(NSURLRequest *)request { return YES; }
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request { return request; }
- (void)startLoading {
    HARNESS_CHECK([self.request.URL.absoluteString isEqualToString:SGUpdateURL]);
    NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:self.request.URL statusCode:200
                                                            HTTPVersion:nil headerFields:nil];
    [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    [self.client URLProtocol:self didLoadData:[@"[{\"tag_name\":\"v1.0.0-beta.34\"}]" dataUsingEncoding:NSUTF8StringEncoding]];
    [self.client URLProtocolDidFinishLoading:self];
}
- (void)stopLoading {}
@end

static NSDictionary *entry(NSString *version, NSString *note) {
    return @{@"version": version, @"notes": [@"* " stringByAppendingString:note], @"date": @"2026-09-18T12:00:00Z"};
}

static void checkPage(NSArray *entries, NSString *intro, NSArray *notes) {
    [NSUserDefaults.standardUserDefaults setObject:entries forKey:@"spotifyglass.update.releases"];
    // The data source is weak; keep its controller alive through the assertions.
    __attribute__((objc_precise_lifetime)) UITableViewController *page = (UITableViewController *)SGUpdatePage();
    UITableView *table = page.tableView;
    UILabel *label = table.tableHeaderView.subviews.firstObject;
    HARNESS_CHECK([label.text isEqualToString:intro]);
    HARNESS_CHECK([table.dataSource numberOfSectionsInTableView:table] == 2 + (NSInteger)notes.count);
    for (NSUInteger i = 0; i < notes.count; ++i) {
        UITableViewCell *cell = [table.dataSource tableView:table cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:i + 2]];
        HARNESS_CHECK([((UIListContentConfiguration *)cell.contentConfiguration).text isEqualToString:notes[i]]);
    }
}

static void checkCache(BOOL legacy) {
    NSURLSessionConfiguration *config = NSURLSessionConfiguration.ephemeralSessionConfiguration;
    config.protocolClasses = @[CacheReply.class];
    method_setImplementation(class_getClassMethod(NSURLSessionConfiguration.class, @selector(ephemeralSessionConfiguration)),
                             imp_implementationWithBlock(^id(id receiver) { return config; }));
    [NSTimeZone setDefaultTimeZone:[NSTimeZone timeZoneForSecondsFromGMT:0]];
    NSUserDefaults *store = NSUserDefaults.standardUserDefaults;
    [store setDouble:NSDate.date.timeIntervalSince1970 forKey:@"spotifyglass.update.checked"];
    [store setBool:YES forKey:SGKeyUpdateBetas];
    if (legacy) [store removeObjectForKey:@"spotifyglass.update.checkedBuild"];
    else [store setObject:@"1.0.0-beta.34" forKey:@"spotifyglass.update.checkedBuild"];
    NSDictionary *old = entry(@"1.0.0-beta.34", @"Old fix");
    __block NSUInteger landed = 0;
    [NSNotificationCenter.defaultCenter addObserverForName:SGUpdateCheckedNotification object:nil queue:nil
                                                usingBlock:^(NSNotification *note) { landed++; }];
    checkPage(@[old], @"This build is 1.0.0-beta.35. The last check found no newer release.", @[]);
    HARNESS_CHECK([SGUpdateStatus() isEqualToString:@"checking…"]);
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5];
    while (!landed && deadline.timeIntervalSinceNow > 0)
        [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:deadline];
    HARNESS_CHECK(landed == 1 && [SGUpdateStatus() isEqualToString:@"up to date"]);
    SGCheckForUpdate(NO);
    HARNESS_CHECK([SGUpdateStatus() isEqualToString:@"up to date"]);
    NSDictionary *equal = entry(@"1.0-beta.35", @"Build fix");
    checkPage(@[equal, old], @"This build, 1.0.0-beta.35, is GitHub's newest release; it came out on 18 September 2026. What went into it is below.", @[@"Build fix"]);
    checkPage(@[entry(@"1.0.0-beta.36", @"New fix"), equal, old],
              @"1.0.0-beta.36 came out on 18 September 2026, and this build is 1.0.0-beta.35. Everything in between is below.", @[@"New fix"]);
    puts("PASS cached page and one build-change request");
}
