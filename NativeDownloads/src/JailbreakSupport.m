// Loaded as Retrine's dependency, before Retrine installs its own audio hooks.
// DEB only: the IPA continues to use its existing on-disk patches/imports.
#import <Foundation/Foundation.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <CydiaSubstrate/CydiaSubstrate.h>
#import "JailbreakPatches.h"
#import "NativeAdmission.h"
#import "JailbreakSupport.h"
#include <string.h>
extern bool SAPInstallJailbreakAudioImports(void);
static const char *startupReason="not_initialized";
NSDictionary *SAPJailbreakSupportReport(void) {
    return @{@"native_patches_ready":@(startupReason==NULL),
             @"reason":@(startupReason?:"ready"),
             @"detected_spotify_version":NSBundle.mainBundle.infoDictionary[@"CFBundleShortVersionString"]?:@""};
}
static void writeCode(void *target,const void *bytes,size_t length,void *context) {
    MSHookMemory(target,bytes,length);
}
bool SAPInstallJailbreakSupport(void) {
    startupReason="unsupported_image";
    if(!SAPRuntimeProfileAdmitted())return false;
    startupReason="invalid_macho";
    const struct mach_header_64 *header=(const void *)_dyld_get_image_header(0);
    if(!header||header->magic!=MH_MAGIC_64||header->sizeofcmds>1048576||header->ncmds>1024)return false;
    const uint8_t *cursor=(const void *)(header+1),*end=cursor+header->sizeofcmds;
    size_t textSize=0;
    for(uint32_t i=0;i<header->ncmds;i++) {
        if(cursor>end||(size_t)(end-cursor)<sizeof(struct load_command))return false;
        const struct load_command *command=(const void *)cursor;
        if(command->cmdsize<sizeof(*command)||command->cmdsize>(size_t)(end-cursor))return false;
        if(command->cmd==LC_SEGMENT_64&&command->cmdsize>=sizeof(struct segment_command_64)) {
            const struct segment_command_64 *segment=(const void *)command;
            if(!strncmp(segment->segname,"__TEXT",16))textSize=segment->filesize;
        }
        cursor+=command->cmdsize;
    }
    const char *reason=NULL;
    if(!SAPJBApplyPatches((void *)header,textSize,writeCode,NULL,&reason)) {
        startupReason=reason?:"invalid_macho";
        NSLog(@"[Pixie] DEB initialization refused: %s",reason?:"invalid Mach-O");return false;
    }
    if(!SAPInstallJailbreakAudioImports()) {
        startupReason="audio_imports_unavailable";
        NSLog(@"[Pixie] Could not install Spotify's audio imports");return false;
    }
    startupReason=NULL;
    return true;
}
