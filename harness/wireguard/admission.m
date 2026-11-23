#import <Foundation/Foundation.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import "../../tweak/Sources/Shared/WireGuard/SGWGCore.h"

static NSString *version, *build;
static struct {
    struct mach_header_64 header;
    struct uuid_command uuid;
} images[2];

@interface AdmissionBundle : NSObject
+ (instancetype)mainBundle;
- (id)objectForInfoDictionaryKey:(NSString *)key;
@end
@implementation AdmissionBundle
+ (instancetype)mainBundle { return [self new]; }
- (id)objectForInfoDictionaryKey:(NSString *)key {
    return @{@"CFBundleVersion": build, @"CFBundleExecutable": @"Spotify"}[key];
}
@end

NSString *SGWGAppVersion(void) { return version; }
static uint32_t imageCount(void) { return 2; }
static const char *imageName(uint32_t index) { return index ? "SpotifyShared" : "Spotify"; }
static const struct mach_header *imageHeader(uint32_t index) { return (void *)&images[index]; }

// Exercise production admission, not its SGWG_TESTING shortcut; only bundle/dyld inputs are fixtures.
#define NSBundle AdmissionBundle
#define _dyld_image_count imageCount
#define _dyld_get_image_name imageName
#define _dyld_get_image_header imageHeader
#include "../../tweak/Sources/Shared/WireGuard/SGWGAdmission.m"
#undef NSBundle
#undef _dyld_image_count
#undef _dyld_get_image_name
#undef _dyld_get_image_header

static void imageUUID(NSUInteger index, NSString *uuid) {
    images[index].header = (struct mach_header_64){
        .magic = MH_MAGIC_64, .ncmds = 1, .sizeofcmds = sizeof(struct uuid_command)
    };
    images[index].uuid.cmd = LC_UUID;
    images[index].uuid.cmdsize = sizeof(struct uuid_command);
    [[[NSUUID alloc] initWithUUIDString:uuid] getUUIDBytes:images[index].uuid.uuid];
}

static BOOL expect(BOOL admitted, NSString *label) {
    if (SGWGAdmissionReady() == admitted) return YES;
    fprintf(stderr, "FAIL: %s should be %s\n", label.UTF8String, admitted ? "admitted" : "rejected");
    return NO;
}

int main(void) {
    @autoreleasepool {
        BOOL passed = YES;
        for (NSArray<NSString *> *target in @[
            @[@"9.1.90", @"919002269", @"FBCE22C1-7E1B-3E0D-9BE8-66FF9291943E", @"2E074234-CFC6-3F0E-9255-C9881824167A"],
            @[@"9.2.0", @"920002054", @"B49E7578-1D86-35D3-8BB5-7DAF68FED8A8", @"30BAC55F-8361-373A-AD60-7F0535395641"]
        ]) {
            version = target[0]; build = target[1];
            imageUUID(0, target[2]); imageUUID(1, target[3]);
            passed &= expect(YES, version);
            build = [target[1] stringByAppendingString:@"0"];
            passed &= expect(NO, [version stringByAppendingString:@" wrong build"]);
            build = target[1];
            images[0].uuid.uuid[0] ^= 1;
            passed &= expect(NO, [version stringByAppendingString:@" wrong main UUID"]);
            images[0].uuid.uuid[0] ^= 1;
            images[1].uuid.uuid[0] ^= 1;
            passed &= expect(NO, [version stringByAppendingString:@" wrong shared UUID"]);
        }
        if (!passed) return 1;
        puts("PASS: exact 9.1.90/9.2.0 admission and wrong-build/main/shared UUID rejection");
        return 0;
    }
}
