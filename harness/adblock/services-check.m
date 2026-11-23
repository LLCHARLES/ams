// Real service installer with Objective-C runtime doubles at Spotify's boundary.
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "AdBlock.h"
#include <stdlib.h>

BOOL SGHidden(NSString *key) {
    const char *value = getenv([key isEqualToString:SGKeyHideAds] ? "HIDE_ADS" : "HIDE_UPSELLS");
    return value && atoi(value);
}
void SGAdBlockCountOne(NSString *label) {}
@implementation UIView
- (void)removeFromSuperview { self.superview = nil; }
- (void)didMoveToSuperview {}
@end
static int deliveries;
static void deliver(id self, SEL selector) { deliveries++; }
static void registerProvider(id self, SEL selector, id registry) { deliveries++; }
static int wrongReturn(id self, SEL selector) { deliveries++; return 7; }
static const char *baseService(void) {
    return getenv("SPOTIFY_920")
        ? "_TtC23AdsPlatform_AdsBaseImpl18AdsBaseServiceImpl"
        : "_TtC28AdsPlatform_AdsBaseSwiftImpl23AdsBaseSwiftServiceImpl";
}
static BOOL absentBase(const char *name) {
    return (strcmp(name, "_TtC23AdsPlatform_AdsBaseImpl18AdsBaseServiceImpl") == 0 ||
            strcmp(name, "_TtC28AdsPlatform_AdsBaseSwiftImpl23AdsBaseSwiftServiceImpl") == 0) &&
        strcmp(name, baseService()) != 0;
}

#include "AdServices.m"

@interface ServiceParent : NSObject
- (void)load;
@end
@implementation ServiceParent
- (void)load { deliveries++; }
@end

// Fixtures include an absent class, an absent selector, wrong ABI and inherited load.
__attribute__((constructor(101))) static void installSpotifyDoubles(void) {
    Class base = objc_allocateClassPair(NSObject.class, baseService(), 0);
    class_addMethod(base, @selector(load), (IMP)deliver, "v16@0:8");
    objc_registerClassPair(base);
    for (size_t i = 0; i < sizeof(serviceTargets) / sizeof(serviceTargets[0]); i++) {
        if (i == 0) continue;
        const SGServiceTarget *target = &serviceTargets[i];
        if (absentBase(target->className)) continue;
        if (strcmp(target->className, baseService()) == 0) continue;
        Class cls = objc_allocateClassPair(i == 4 ? ServiceParent.class : NSObject.class, target->className, 0);
        if (i != 1 && i != 4) {
            BOOL scroll = strcmp(target->selector, "registerScrollProviderIn:") == 0;
            IMP imp = i == 2 ? (IMP)wrongReturn : (scroll ? (IMP)registerProvider : (IMP)deliver);
            class_addMethod(cls, sel_registerName(target->selector), imp, i == 2 ? "i@:" : (scroll ? "v@:@" : "v@:"));
        }
        objc_registerClassPair(cls);
    }
}

int main(void) {
    @autoreleasepool {
        int failures = 0;
        Class base = objc_getClass(baseService());
        if (!base) {
            NSLog(@"FAIL missing base ad service fixture");
            return EXIT_FAILURE;
        }
        int baseBefore = deliveries;
        ((void (*)(id, SEL))objc_msgSend)([base new], @selector(load));
        if (deliveries - baseBefore != (SGHidden(SGKeyHideAds) ? 0 : 1)) {
            NSLog(@"FAIL base ad service did not obey Hide ads");
            failures++;
        }
        // This fixture is a public switch contract, not generated from serviceTargets.
        NSData *gateData = [NSData dataWithContentsOfFile:@"service-gates.json"];
        NSDictionary *expectedGates = gateData ? [NSJSONSerialization JSONObjectWithData:gateData options:0 error:nil] : nil;
        if (![expectedGates isKindOfClass:NSDictionary.class]) {
            NSLog(@"FAIL missing independent service gate expectations");
            return EXIT_FAILURE;
        }
        for (size_t i = 0; i < sizeof(serviceTargets) / sizeof(serviceTargets[0]); i++) {
            const SGServiceTarget *target = &serviceTargets[i];
            if (absentBase(target->className)) continue;
            Class cls = objc_getClass(target->className);
            SEL selector = sel_registerName(target->selector);
            if (i == 0 || i == 1) {
                if (cls && class_getInstanceMethod(cls, selector)) failures++;
                continue;
            }
            id service = [cls new];
            int before = deliveries;
            if (i == 2) {
                if (((int (*)(id, SEL))objc_msgSend)(service, selector) != 7) failures++;
            } else if (selector == @selector(registerScrollProviderIn:)) {
                ((void (*)(id, SEL, id))objc_msgSend)(service, selector, [NSObject new]);
            } else {
                ((void (*)(id, SEL))objc_msgSend)(service, selector);
            }
            NSString *gate = expectedGates[@(target->className)];
            if (![gate isEqualToString:@"ads"] && ![gate isEqualToString:@"upsells"]) {
                NSLog(@"FAIL missing gate expectation for %s", target->className);
                failures++;
                continue;
            }
            BOOL blocked = i != 2 && SGHidden([gate isEqualToString:@"upsells"] ? SGKeyHideUpsells : SGKeyHideAds);
            if (deliveries - before != (blocked ? 0 : 1)) {
                NSLog(@"FAIL service %s did not obey its gate", target->className);
                failures++;
            }
        }
        int before = deliveries;
        [[ServiceParent new] load];
        if (deliveries != before + 1) failures++;
        printf("services: Hide ads=%d Hide upsells=%d failures=%d\n",
               SGHidden(SGKeyHideAds), SGHidden(SGKeyHideUpsells), failures);
        return failures ? EXIT_FAILURE : EXIT_SUCCESS;
    }
}
