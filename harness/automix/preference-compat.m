// Real capture and quality guards. Register each Spotify-shaped owner before Logos runs.
#import "../harness-fail.h"
#import "Shared/SpotifyPrefs/SpotifyPrefs.h"
#import "Shared/Lossless/LosslessQuality.h"
#import <objc/runtime.h>

static NSInteger cellular = 3, wifi = 4;
static BOOL mode(const char *name) { return !strcmp(getenv("PREFS_CASE"), name); }
BOOL SGHidden(NSString *key) { return NO; }
void SGAutoMixReconcile(void) {}
void SGRequireClasses(NSArray *names) {}

@interface FixtureInstaller : NSObject
@end
@implementation FixtureInstaller
+ (void)load {
    Class cls = objc_allocateClassPair(NSObject.class, "_TtC31Preferences_CorePreferencesImpl28SPTPreferencesImplementation", 0);
    class_addMethod(cls, @selector(initWithScheduler:), imp_implementationWithBlock(^id(id obj, id scheduler) { return obj; }), "@@:@");
    if (!mode("missing-speed"))
        class_addMethod(cls, @selector(playbackSpeed), imp_implementationWithBlock(^NSInteger(id obj) { return 100; }), "q@:");
    class_addMethod(cls, @selector(audioPlayBitrate), imp_implementationWithBlock(^NSInteger(id obj) { return cellular; }), "q@:");
    class_addMethod(cls, @selector(audioPlayBitrateNonMetered), imp_implementationWithBlock(^NSInteger(id obj) { return wifi; }), "q@:");
    class_addMethod(cls, @selector(setAudioPlayBitrate:), imp_implementationWithBlock(^(id obj, NSInteger level) { cellular = level; }), "v@:q");
    if (mode("wrong-setter"))
        class_addMethod(cls, @selector(setAudioPlayBitrateNonMetered:), imp_implementationWithBlock(^(id obj, double level) { wifi = 0; }), "v@:d");
    else
        class_addMethod(cls, @selector(setAudioPlayBitrateNonMetered:), imp_implementationWithBlock(^(id obj, NSInteger level) { wifi = level; }), "v@:q");
    objc_registerClassPair(cls);
}
@end

@interface NSObject (Fixture)
- (instancetype)initWithScheduler:(id)scheduler;
@end

int main(void) {
    @autoreleasepool {
        id __attribute__((objc_precise_lifetime)) prefs =
            [[NSClassFromString(@"_TtC31Preferences_CorePreferencesImpl28SPTPreferencesImplementation") alloc] initWithScheduler:nil];
        HARNESS_CHECK(SGSpotifyPreferences() == (mode("missing-speed") ? nil : prefs));
        NSInteger a = -1, b = -1;
        BOOL ok = mode("supported");
        HARNESS_CHECK(SGStreamQuality(&a, &b) == ok);
        HARNESS_CHECK(a == (ok ? 3 : -1) && b == (ok ? 4 : -1));
        HARNESS_CHECK(SGSetStreamQuality(1, 2) == ok);
        HARNESS_CHECK(cellular == (ok ? 1 : 3) && wifi == (ok ? 2 : 4));
        if (ok) {
            // A later capture overrides only the second setter, with an incompatible ABI.
            Class later = objc_allocateClassPair(object_getClass(prefs), "LaterPreferences", 0);
            class_addMethod(later, @selector(setAudioPlayBitrateNonMetered:),
                            imp_implementationWithBlock(^(id obj, double level) { wifi = 0; }), "v@:d");
            objc_registerClassPair(later);
            id __attribute__((objc_precise_lifetime)) replacement = [[later alloc] initWithScheduler:nil];
            HARNESS_CHECK(SGSpotifyPreferences() == replacement);
            HARNESS_CHECK(!SGSetStreamQuality(7, 8) && cellular == 1 && wifi == 2);
        }
        printf("[harness] PASS %s\n", getenv("PREFS_CASE"));
    }
    return 0;
}
