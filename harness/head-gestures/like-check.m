#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#define SGLog(...) ((void)0)
static void SGRequireClasses(NSArray *names) {
    for (NSString *name in names) {
        if (!NSClassFromString(name)) { NSLog(@"FAIL required absent optional class"); exit(1); }
    }
}
@interface Track : NSObject
@property NSURL *URI;
@end
@implementation Track
@end
@interface State : NSObject
@property Track *track;
@end
@implementation State
@end
static State *state;
static State *SGPlayerState(void) { return state; }
static NSString *SGURIString(NSURL *url) { return url.absoluteString; }
enum { UIApplicationStateActive = 0 };
@interface UIApplication : NSObject
+ (instancetype)sharedApplication;
@property NSInteger applicationState;
@end
@implementation UIApplication
+ (instancetype)sharedApplication { static id app; if (!app) app = [self new]; return app; }
@end
static NSMutableSet *liked;
static id stateProvider(id self, SEL cmd) { return nil; }
static void add(id self, SEL cmd, NSURL *url, BOOL show, id completion) {
    [liked addObject:url.absoluteString];
}
static void toggle(id self, SEL cmd, id completion, id identifier) {
    [liked removeAllObjects];
}
static const char *platforms[] = {
    "SPTCollectionPlatformImplementation",
    "_TtC23Collection_PlatformImpl27CollectionPlatformMigration",
    "_TtC23Collection_PlatformImpl22CollectionPlatformImpl",
    "_TtC26AlignedCuration_CommonImpl21ACUCollectionPlatform"
};
__attribute__((constructor(101))) static void fixtures(void) {
    for (unsigned i = getenv("SPOTIFY_920") ? 2 : 0; i < 4; i++) {
        Class cls = objc_allocateClassPair(NSObject.class, platforms[i], 0);
        class_addMethod(cls, @selector(stateProvider), (IMP)stateProvider, "@@:");
        class_addMethod(cls, @selector(addURL:showUIConfirmation:completion:), (IMP)add, "v@:@B@?");
        class_addMethod(cls, @selector(likeButtonPressedWithCompletion:identifier:), (IMP)toggle, "v@:@@");
        objc_registerClassPair(cls);
    }
}
#include "capture.m"
int main(void) {
    @autoreleasepool {
        state = [State new];
        state.track = [Track new];
        state.track.URI = [NSURL URLWithString:@"spotify:track:example"];
        liked = [NSMutableSet set];
        for (unsigned i = getenv("SPOTIFY_920") ? 2 : 0; i < 4; i++) {
            [liked removeAllObjects];
            sg_platform = nil;
            id platform = [objc_getClass(platforms[i]) new];
            ((id (*)(id, SEL))objc_msgSend)(platform, @selector(stateProvider));
            if (!SGLikePlayingTrack() || !SGLikePlayingTrack() ||
                ![liked isEqualToSet:[NSSet setWithObject:@"spotify:track:example"]]) {
                NSLog(@"FAIL repeated Like must keep the track saved"); return 1;
            }
        }
        printf("PASS repeated Like %s\n", getenv("SPOTIFY_920") ? "9.2.0" : "9.1.90");
    }
    return 0;
}
