#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#define SGLog(...) ((void)0)
static BOOL SGRedesignedUI(void) { return YES; }
static void SGRequireClasses(NSArray *names) {}
static id provider;
static id stateProvider(id self, SEL cmd) { return provider; }
static id subscription(id self, SEL cmd, id url, id completion) { return @"subscription"; }
static id contextSubscription(id self, SEL cmd, id url, id context, id completion) { return @"subscription"; }
static id platformInit(id self, SEL cmd, id loader, BOOL gated) { return self; }
static const char *cup = "_TtC21Curation_PlatformImpl30CUPStateProviderImplementation";
static const char *modern = "_TtC23Collection_PlatformImpl22CollectionPlatformImpl";
static const char *legacy = "SPTCollectionPlatformImplementation";
static const char *migration = "_TtC23Collection_PlatformImpl27CollectionPlatformMigration";

__attribute__((constructor(101))) static void fixtures(void) {
    BOOL newer = getenv("SPOTIFY_920") != NULL;
    const char *platforms[] = {legacy, migration, modern, "_TtC26AlignedCuration_CommonImpl21ACUCollectionPlatform"};
    for (unsigned i = 0; i < 4; i++) {
        if (newer && i < 2) continue;
        Class cls = objc_allocateClassPair(NSObject.class, platforms[i], 0);
        class_addMethod(cls, @selector(stateProvider), (IMP)stateProvider, "@@:");
        if (i == 0) class_addMethod(cls, @selector(initWithCosmosDataLoader:isGatedEntityRelationsEnabled:), (IMP)platformInit, "@@:@B");
        objc_registerClassPair(cls);
    }
    const char *providers[] = {"_TtC23Collection_PlatformImpl35CollectionPlatformStateProviderImpl", "_TtC26AlignedCuration_CommonImpl25ACUEsperantoStateProvider"};
    for (unsigned i = 0; i < 2; i++) {
        Class cls = objc_allocateClassPair(NSObject.class, providers[i], 0);
        class_addMethod(cls, @selector(subscribeCollectionStateForURL:completion:), (IMP)subscription, "@@:@@");
        class_addMethod(cls, @selector(subscribeCollectionStateForURLs:completion:), (IMP)subscription, "@@:@@");
        class_addMethod(cls, @selector(subscribeCollectionStateForURL:inContextURL:completion:), (IMP)contextSubscription, "@@:@@@");
        class_addMethod(cls, @selector(subscribeCollectionStateForURLs:inContextURL:completion:), (IMP)contextSubscription, "@@:@@@");
        objc_registerClassPair(cls);
    }
    Class cls = objc_allocateClassPair(NSObject.class, cup, 0);
    class_addIvar(cls, "collectionPlatformStateProvider", sizeof(id), 3, "@");
    if (!newer) class_addMethod(cls, @selector(subscribeCollectionStateForURL:inContext:completion:), (IMP)contextSubscription, "@@:@@@");
    objc_registerClassPair(cls);
}

#include "capture.m"

int main(void) {
    @autoreleasepool {
        provider = [objc_getClass("_TtC23Collection_PlatformImpl35CollectionPlatformStateProviderImpl") new];
        BOOL newer = getenv("SPOTIFY_920") != NULL;
        SEL selector = @selector(subscribeCollectionStateForURL:inContext:completion:);
        if (newer) {
            if (class_getInstanceMethod(objc_getClass(cup), selector)) {
                NSLog(@"FAIL installed missing CUP selector"); return 1;
            }
        } else {
            id wrapper = [objc_getClass(cup) new];
            object_setIvar(wrapper, class_getInstanceVariable([wrapper class], "collectionPlatformStateProvider"), provider);
            ((id (*)(id, SEL, id, id, id))objc_msgSend)(wrapper, selector, nil, nil, nil);
            if (currentProvider() != provider) { NSLog(@"FAIL CUP capture"); return 1; }
        }
        const char *platforms[] = {legacy, migration, modern};
        for (unsigned i = newer ? 2 : 0; i < 3; i++) {
            sg_provider = nil;
            id platform = [objc_getClass(platforms[i]) new];
            ((id (*)(id, SEL))objc_msgSend)(platform, @selector(stateProvider));
            if (currentProvider() != provider) { NSLog(@"FAIL platform capture"); return 1; }
        }
        sg_provider = nil;
        [(id<SGRCollectionStateProvider>)provider subscribeCollectionStateForURL:nil completion:nil];
        if (currentProvider() != provider) { NSLog(@"FAIL subscription capture"); return 1; }
        printf("PASS Follow capture %s\n", newer ? "9.2.0" : "9.1.90");
    }
    return 0;
}
