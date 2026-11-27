// Run the production installer against dyld and hooker boundaries, without patching host code.
#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <mach-o/getsect.h>
#import <mach-o/loader.h>
#import "Core/SGAudioInline.h"
#import "../harness-fail.h"

static const char *hookerPath;
static int refused;
static SGInlineHook *activeHooks, *enteringHook;
static NSString *bundlePath;
static void targetStop(void) {}
static void targetDispose(void) {}
static void targetStart(void) {}
static OSStatus replacement(void) {
    typedef OSStatus (*Original)(void);
    SG_AUDIO_INLINE_ORIGINAL(original, enteringHook, Original);
    return original();
}
static OSStatus trampoline(void) { return 73; }
static void *targets[] = {(void *)targetStop, (void *)targetDispose, (void *)targetStart};
static struct {
    struct mach_header_64 header;
    struct segment_command_64 text;
} spotify = {
    .header = {.magic = MH_MAGIC_64, .ncmds = 1},
    .text = {.cmd = LC_SEGMENT_64, .cmdsize = sizeof(struct segment_command_64), .segname = SEG_TEXT},
}, container = {
    .header = {.magic = MH_MAGIC_64, .ncmds = 1},
    .text = {.cmd = LC_SEGMENT_64, .cmdsize = sizeof(struct segment_command_64), .segname = SEG_TEXT},
};

static void fakeHook(void *function, void *replace, void **original) {
    for (int i = 0; i < 3; i++) {
        if (function != targets[i] || refused == i) continue;
        enteringHook = &activeHooks[i];
        // A framework thread reaches patched code before ElleKit publishes its out parameter.
        dispatch_semaphore_t finished = dispatch_semaphore_create(0);
        dispatch_async(dispatch_get_global_queue(0, 0), ^{
            HARNESS_CHECK(((OSStatus (*)(void))replace)() == kAudioUnitErr_CannotDoInCurrentContext);
            dispatch_semaphore_signal(finished);
        });
        HARNESS_CHECK(dispatch_semaphore_wait(finished, dispatch_time(DISPATCH_TIME_NOW, 60 * NSEC_PER_SEC)) == 0);
        *original = (void *)trampoline;
        // Even the hooker's private write is not a publication to callers until installation returns.
        HARNESS_CHECK(((OSStatus (*)(void))replace)() == kAudioUnitErr_CannotDoInCurrentContext);
    }
}
static void *fakeOpen(const char *path, int flags) { return NULL; }
static void *fakeSymbol(void *handle, const char *name) {
    return hookerPath ? (void *)fakeHook : NULL;
}
static int fakeAddress(const void *address, Dl_info *info) {
    info->dli_fname = hookerPath;
    return 1;
}
static uint32_t fakeCount(void) { return 2; }
static const char *fakeName(uint32_t index) {
    return index == 0 ? "/Applications/LiveContainer" : "/var/mobile/Containers/Spotify";
}
static const struct mach_header *fakeHeader(uint32_t index) {
    return (const struct mach_header *)(index == 0 ? &container.header : &spotify.header);
}
static uint8_t *fakeSegment(const struct mach_header_64 *header, const char *name, unsigned long *size) {
    *size = 0x100;
    return (uint8_t *)(uintptr_t)(header == &spotify.header ? 0x2000 : 0x1000);
}
@interface RebindBundle : NSObject
+ (instancetype)mainBundle;
@property(nonatomic, readonly) NSString *bundlePath;
@property(nonatomic, readonly) NSDictionary *infoDictionary;
@end
@implementation RebindBundle
+ (instancetype)mainBundle { static RebindBundle *bundle; if (!bundle) bundle = [self new]; return bundle; }
- (NSString *)bundlePath { return bundlePath ?: NSBundle.mainBundle.bundlePath; }
- (NSDictionary *)infoDictionary { return NSBundle.mainBundle.infoDictionary; }
@end
#define NSBundle RebindBundle
#define dlopen fakeOpen
#define dlsym fakeSymbol
#define dladdr fakeAddress
#define _dyld_image_count fakeCount
#define _dyld_get_image_name fakeName
#define _dyld_get_image_header fakeHeader
#define getsegmentdata fakeSegment
#import "../../tweak/Sources/Core/SGRebind.m"

int main(int argc, char **argv) {
    @autoreleasepool {
        HARNESS_CHECK(argc == 3);
        NSString *kind = @(argv[1]);
        refused = atoi(argv[2]);
        BOOL alias = [kind isEqualToString:@"bundle-alias"];
        if (alias) bundlePath = @"/private/var/containers/Bundle/Application/app/Spotify.app";
        NSString *path = [kind isEqualToString:@"bundle"]
            ? [NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"Frameworks/CydiaSubstrate.framework/CydiaSubstrate"]
            : alias ? @"/var/containers/Bundle/Application/app/Spotify.app/Frameworks/CydiaSubstrate.framework/CydiaSubstrate"
            : [kind isEqualToString:@"container"] ? @"/private/var/mobile/Containers/Data/Application/app/libsubstrate.dylib"
            : [kind isEqualToString:@"roothide"] ? @"/var/containers/Bundle/Application/.jbroot-test/usr/lib/libellekit.dylib"
            : @"/var/jb/usr/lib/libellekit.dylib";
        hookerPath = [kind isEqualToString:@"none"] ? NULL : path.UTF8String;
        BOOL jailbroken = [kind isEqualToString:@"jailbreak"] || [kind isEqualToString:@"roothide"];
        HARNESS_CHECK(SGJailbroken() == jailbroken);
        void *originals[3] = {NULL, NULL, NULL};
        SGInlineHook hooks[] = {
            {.function = targets[0], .replacement = (void *)replacement, .original = &originals[0]},
            {.function = targets[1], .replacement = (void *)replacement, .original = &originals[1]},
            {.function = targets[2], .replacement = (void *)replacement, .original = &originals[2]},
        };
        activeHooks = hooks;
        BOOL installed = SGHookFunctionsInline(hooks, 3);
        HARNESS_CHECK(installed == (jailbroken && refused == -1));
        if (installed) {
            HARNESS_CHECK(replacement() == 73);
            HARNESS_CHECK(originals[0] && originals[1] && originals[2]);
            HARNESS_CHECK(SGCalledFromMainExecutable((void *)0x2000));
            HARNESS_CHECK(SGCalledFromMainExecutable((void *)0x20ff));
            HARNESS_CHECK(!SGCalledFromMainExecutable((void *)0x2100));
            HARNESS_CHECK(!SGCalledFromMainExecutable((void *)0x1000));
        } else if (!jailbroken) {
            HARNESS_CHECK(!originals[0] && !originals[1] && !originals[2]);
        } else {
            // No later lifecycle entry can be installed after one was refused.
            for (int i = refused; i < 3; i++) HARNESS_CHECK(!originals[i]);
        }
        puts("inline hook selection: ok");
    }
    return 0;
}
