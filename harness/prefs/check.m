// Host check for Core/SGPrefs.m's memo: a write applies to the next read, through the accessors or straight
// to NSUserDefaults, from this thread or another, and an unset key reads as its fallback.
#import <Foundation/Foundation.h>
#import "Core/SGPrefs.h"

#define CHECK(cond) do { if (!(cond)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #cond); exit(1); } } while (0)

int main(void) {
    @autoreleasepool {
        NSUserDefaults *store = NSUserDefaults.standardUserDefaults;
        NSString *flag = @"spotifyglass.test.flag", *choice = @"spotifyglass.test.int";
        for (NSString *key in @[flag, choice, SGKeyStock]) [store removeObjectForKey:key];

        CHECK(SGEnabled(flag) && !SGHidden(flag));
        CHECK(SGInt(choice, 7) == 7);
        SGSetEnabled(flag, NO);
        CHECK(!SGEnabled(flag));
        SGSetInt(choice, 3);
        CHECK(SGInt(choice, 7) == 3);

        [store setBool:YES forKey:flag];
        CHECK(SGHidden(flag));
        [store removeObjectForKey:flag];
        CHECK(SGEnabled(flag));
        [store setBool:YES forKey:SGKeyStock];
        CHECK(!SGEnabled(flag) && !SGFlag(flag, YES));
        [store removeObjectForKey:SGKeyStock];
        CHECK(SGEnabled(flag));

        dispatch_sync(dispatch_get_global_queue(0, 0), ^{ [store setInteger:9 forKey:choice]; });
        CHECK(SGInt(choice, 7) == 9);
        [store removeObjectForKey:choice];
        CHECK(SGInt(choice, 7) == 7);

        for (NSString *key in @[flag, choice]) [store removeObjectForKey:key];
        puts("prefs: ok");
    }
    return 0;
}
