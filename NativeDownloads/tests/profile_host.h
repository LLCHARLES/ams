#import <Foundation/Foundation.h>
#include <mach-o/dyld.h>
#include <mach-o/loader.h>
#include <dlfcn.h>
static NSDictionary *metadata;
static NSString *hostPath=@"Payload/Spotify.app";
@interface FingerprintBundle:NSObject
+ (instancetype)mainBundle;
- (NSDictionary *)infoDictionary;
- (NSString *)bundlePath;
@end
@implementation FingerprintBundle
+ (instancetype)mainBundle {return [self new];}
- (NSDictionary *)infoDictionary {return metadata;}
- (NSString *)bundlePath {return hostPath;}
@end
static struct {struct mach_header_64 header;struct uuid_command uuid;} images[2];
static unsigned imageCount=2;
static const char *image_name(uint32_t i) {return i?"SpotifyShared":"Spotify";}
static const struct mach_header *image_header(uint32_t i) {return (const void *)&images[i];}
static void (*addedImage)(const struct mach_header *,intptr_t);
static void (*removedImage)(const struct mach_header *,intptr_t);
static int image_info(const void *address,Dl_info *info) {
    for(unsigned i=0;i<2;i++)if(address==&images[i]){info->dli_fname=image_name(i);return 1;}
    return 0;
}
static void register_added(void (*callback)(const struct mach_header *,intptr_t)) {
    addedImage=callback;
    for(unsigned i=0;i<imageCount;i++)callback(image_header(i),0);
}
static void register_removed(void (*callback)(const struct mach_header *,intptr_t)) {removedImage=callback;}
static void publishImages(void) {
    for(unsigned i=0;i<2;i++)removedImage(image_header(i),0);
    for(unsigned i=0;i<imageCount;i++)addedImage(image_header(i),0);
}
#define _dyld_get_image_header image_header
#define _dyld_register_func_for_add_image register_added
#define _dyld_register_func_for_remove_image register_removed
#define dladdr image_info
#define NSBundle FingerprintBundle
#include "NativeAdmission.m"
#undef NSBundle
static void uuid(const char *hex,uint8_t *bytes) {
    for(unsigned i=0;i<16;i++){unsigned value;sscanf(hex+2*i,"%2x",&value);bytes[i]=value;}
}
static void exactHost(void) {
    hostPath=@"Payload/Spotify.app";
    metadata=@{@"CFBundleShortVersionString":@"9.1.90",@"CFBundleVersion":@"919002269"};
    imageCount=2;
    for(unsigned i=0;i<2;i++) {
        images[i].header.magic=MH_MAGIC_64;images[i].header.ncmds=1;
        images[i].header.sizeofcmds=sizeof(struct uuid_command);
        images[i].uuid.cmd=LC_UUID;images[i].uuid.cmdsize=sizeof(struct uuid_command);
    }
    uuid("fbce22c17e1b3e0d9be866ff9291943e",images[0].uuid.uuid);
    uuid("2e074234cfc63f0e9255c9881824167a",images[1].uuid.uuid);
    publishImages();
}
