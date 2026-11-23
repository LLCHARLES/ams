#pragma once
#import <Foundation/Foundation.h>
#include <mach-o/dyld.h>
#include <mach-o/loader.h>
#include <string.h>
#include <Generated/TargetProfile.h>
#include "NativeAdmission.h"

static inline BOOL SAPProfileUUIDMatches(const struct mach_header_64 *h,const uint8_t expected[16]) {
    if(!h||h->magic!=MH_MAGIC_64||h->ncmds>1024||h->sizeofcmds>1048576)return NO;
    const uint8_t *cursor=(const void *)(h+1),*end=cursor+h->sizeofcmds;
    for(unsigned i=0;i<h->ncmds;i++) {
        if((size_t)(end-cursor)<sizeof(struct load_command))return NO;
        const struct load_command *c=(const void *)cursor;
        if(c->cmdsize<sizeof(*c)||c->cmdsize>(size_t)(end-cursor))return NO;
        if(c->cmd==LC_UUID)return c->cmdsize>=sizeof(struct uuid_command)&&
            !memcmp(((const struct uuid_command *)c)->uuid,expected,16);
        cursor+=c->cmdsize;
    }
    return NO;
}

static inline BOOL SAPProfileMetadataMatches(void) {
    if(!SAPProfileEnabled||!SAPProfileReservationCountersVerified||!SAPProfileRuntimeLayoutVerified)return NO;
    NSDictionary *info=NSBundle.mainBundle.infoDictionary;
    if(info[@"NSExtension"]||[NSBundle.mainBundle.bundlePath.pathExtension.lowercaseString isEqual:@"appex"])return NO;
    if(![info[@"CFBundleShortVersionString"] isEqual:@SAPProfileVersion]||
       ![info[@"CFBundleVersion"] isEqual:@SAPProfileBuild])return NO;
    return YES;
}

static inline BOOL SAPProfileMatchesImage(uintptr_t image) {
    return SAPIsAdmittedMainImage((const struct mach_header *)image)&&SAPRuntimeProfileAdmitted();
}
