#import "Flags.h"
#import "Core/SGFlagForce.h"
#import "Core/SGPrefs.h"

static NSString *const cacheLimitItem = @"ios-settings-connectivitypageplugin-impl.show_cache_limit_item";

__attribute__((constructor)) static void registerCacheLimit(void) {
    SGRegisterFlagForcer(YES, ^id(NSString *key) {
        static BOOL on;
        static dispatch_once_t once;
        dispatch_once(&once, ^{ on = SGEnabled(SGKeyShowCacheLimit); });
        return on && [key isEqualToString:cacheLimitItem] ? @YES : nil;
    }, ^id(NSString *key) {
        return [key isEqualToString:cacheLimitItem] && SGEnabled(SGKeyShowCacheLimit) ? @YES : nil;
    });
}
