#import "App/About/About.h"
#import "Core/SGPrefs.h"
#import "../harness-fail.h"

static void stored(NSArray *releases, BOOL betas) {
    [NSUserDefaults.standardUserDefaults setVolatileDomain:@{
        @"spotifyglass.update.releases": releases,
        @"spotifyglass.update.checked": @1,
        SGKeyUpdateBetas: @(betas),
    } forName:NSArgumentDomain];
    SGPrefsChanged();
}

int main(void) {
    @autoreleasepool {
        NSArray *releases = @[
            @"not a release",
            @{},
            @{@"version": @"3.0.0", @"prerelease": @YES, @"notes": @"### Features\n* Preview"},
            @{@"version": @"2.5.0-beta.1", @"notes": @"### Features\n* Unmarked beta"},
            @{@"version": @"2.0.0", @"prerelease": @NO, @"notes": @"### Fixes\n* Stable"},
        ];
        stored(releases, NO);
        HARNESS_CHECK([SGUpdateVersion() isEqualToString:@"2.0.0"]);
        stored(releases, YES);
        HARNESS_CHECK([SGUpdateVersion() isEqualToString:@"3.0.0"]);
        stored(@[@{@"version": @"0.9.0", @"notes": @"### Fixes\n* Old"}], YES);
        HARNESS_CHECK(SGUpdateVersion() == nil);
        stored(@[], NO);
        HARNESS_CHECK(SGUpdateVersion() == nil);
        stored(@[@{@"version":@"2", @"url":@"https://github.com.example/test",
                   @"notes":@"* Bad ([abcdef](tel:123))\n* Good ([123abc](https://github.com/owner/repo/commit/123abc))"}], NO);
        SGUpdateRelease *release = SGUpdateNewestRelease();
        HARNESS_CHECK(!release.url && !release.changes.firstObject.url);
        HARNESS_CHECK([release.changes.lastObject.url isEqual:@"https://github.com/owner/repo/commit/123abc"]);
        NSData *tags = [@"[{\"tag_name\":\"v1.0\"},{\"tag_name\":\"v2\"},{\"tag_name\":\"v1.0.0\"}]" dataUsingEncoding:NSUTF8StringEncoding];
        NSArray *versions = [SGUpdateReleasesFrom(tags) valueForKey:@"version"];
        HARNESS_CHECK(([versions isEqual:@[@"2", @"1.0", @"1.0.0"]]));
        NSLog(@"[harness] offline update selection PASS");
    }
    return 0;
}
