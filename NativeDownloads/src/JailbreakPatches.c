#include "JailbreakPatches.h"
#include "NativeAdmission.h"
#include <NativeRestrictionsPatch.h>
#include <NativeKeyModePatch.h>
#include "NativeKeyPatch.h"
#include <mach-o/loader.h>
#include <mach/machine.h>
#include <string.h>

static bool fail(const char **reason,const char *message) {if(reason)*reason=message;return false;}
static bool zeroes(const uint8_t *bytes,size_t count) {for(size_t i=0;i<count;i++)if(bytes[i])return false;return true;}
bool SAPJBApplyPatches(uint8_t *image,size_t textSize,SAPJBWrite writer,void *context,const char **reason) {
    if(reason)*reason="unsupported_image";
    if(!SAPRuntimeProfileAdmitted())return false;
    if(!image||textSize<sizeof(struct mach_header_64))return false;
    const struct mach_header_64 *header=(const void *)image;
    if(header->magic!=MH_MAGIC_64||header->cputype!=CPU_TYPE_ARM64||header->filetype!=MH_EXECUTE||
       header->ncmds>1024||header->sizeofcmds>1048576||sizeof(*header)+header->sizeofcmds>textSize)return false;
    size_t cursor=sizeof(*header),end=cursor+header->sizeofcmds,firstSection=textSize;
    bool uuidOK=false,textOK=false;
    for(uint32_t i=0;i<header->ncmds;i++) {
        if(cursor>end||end-cursor<sizeof(struct load_command))return false;
        const struct load_command *cmd=(const void *)(image+cursor);
        if(cmd->cmdsize<sizeof(*cmd)||cmd->cmdsize>end-cursor)return false;
        if(cmd->cmd==LC_UUID) {
            if(cmd->cmdsize<sizeof(struct uuid_command))return false;
            uuidOK=!memcmp(((const struct uuid_command *)cmd)->uuid,SAPJBSupportedUUID,16);
        }
        if(cmd->cmd==LC_SEGMENT_64) {
            if(cmd->cmdsize<sizeof(struct segment_command_64))return false;
            const struct segment_command_64 *seg=(const void *)cmd;
            if(!strncmp(seg->segname,"__TEXT",16)) {
                if(seg->nsects>(cmd->cmdsize-sizeof(*seg))/sizeof(struct section_64))return false;
                textOK=seg->vmaddr==UINT64_C(0x100000000)&&seg->fileoff==0&&seg->filesize==textSize&&(seg->initprot&5)==5;
                const struct section_64 *section=(const void *)(seg+1);
                for(uint32_t s=0;s<seg->nsects;s++)if(section[s].offset&&section[s].offset<firstSection)firstSection=section[s].offset;
            }
        }
        cursor+=cmd->cmdsize;
    }
    if(cursor!=end||!uuidOK||!textOK)return false;
    const struct {size_t offset,length;} spans[]={
        {SAPJBSetterOffset,sizeof(SAPJBSetterOriginal)},
        {SAPJBKeyWindowOffset,sizeof(SAPJBKeyOriginal)},
        {SAPJBProviderOffset,sizeof(SAPJBProviderOriginal)},
        {SAPJBMappingOffset,sizeof(SAPJBMappingOriginal)},
        {SAPJBDLSymStubOffset,sizeof(SAPJBDLSymStubOriginal)},
        {SAPKeyModeCaveOffset,sizeof(SAPKeyModeTrampoline)},
        {SAPRestrictionCaveOffset,sizeof(SAPRestrictionTrampoline)}};
    for(size_t i=0;i<sizeof(spans)/sizeof(*spans);i++)
        if(spans[i].offset>textSize||spans[i].length>textSize-spans[i].offset)return false;
    if(SAPRestrictionCaveOffset<end||SAPRestrictionCaveOffset+sizeof(SAPRestrictionTrampoline)>firstSection)return false;
    if(SAPKeyModeCaveOffset<end||SAPKeyModeCaveOffset+sizeof(SAPKeyModeTrampoline)>firstSection||
       SAPKeyModeCaveOffset+sizeof(SAPKeyModeTrampoline)>SAPRestrictionCaveOffset)return false;
    uint8_t *setter=image+SAPJBSetterOffset,*cave=image+SAPRestrictionCaveOffset,*key=image+SAPJBKeyWindowOffset;
    uint8_t *keyCave=image+SAPKeyModeCaveOffset;
    bool guarded=!memcmp(setter,SAPGuardedSetterHead,4)&&
        !memcmp(setter+4,SAPJBSetterOriginal+4,sizeof(SAPJBSetterOriginal)-4)&&
        !memcmp(cave,SAPRestrictionTrampoline,sizeof(SAPRestrictionTrampoline));
    if(!guarded&&(memcmp(setter,SAPJBSetterOriginal,sizeof(SAPJBSetterOriginal))||!zeroes(cave,sizeof(SAPRestrictionTrampoline))))
        return fail(reason,"restriction_guard_mismatch");
    bool keyPatched=!memcmp(key,SAPJBKeyPatched,sizeof(SAPJBKeyPatched));
    bool keyStaticZero=!memcmp(key,SAPJBKeyStaticZero,sizeof(SAPJBKeyStaticZero));
    if((!keyPatched&&!keyStaticZero&&memcmp(key,SAPJBKeyOriginal,sizeof(SAPJBKeyOriginal)))||
       memcmp(image+SAPJBProviderOffset,SAPJBProviderOriginal,sizeof(SAPJBProviderOriginal))||
       memcmp(image+SAPJBMappingOffset,SAPJBMappingOriginal,sizeof(SAPJBMappingOriginal))||
       memcmp(image+SAPJBDLSymStubOffset,SAPJBDLSymStubOriginal,sizeof(SAPJBDLSymStubOriginal))||
       (keyPatched?memcmp(keyCave,SAPKeyModeTrampoline,sizeof(SAPKeyModeTrampoline)):
                    !zeroes(keyCave,sizeof(SAPKeyModeTrampoline))))
        return fail(reason,"key_requester_mismatch");
    if(guarded&&keyPatched){if(reason)*reason="already_applied";return true;}
    if(!writer)return fail(reason,"no_memory_writer");
    uint8_t oldCave[sizeof(SAPRestrictionTrampoline)],oldKeyCave[sizeof(SAPKeyModeTrampoline)],oldHead[4],oldKey[4];
    memcpy(oldCave,cave,sizeof(oldCave));memcpy(oldKeyCave,keyCave,sizeof(oldKeyCave));
    memcpy(oldHead,setter,4);memcpy(oldKey,image+SAPJBKeyCallOffset,4);
    if(!guarded) {
        writer(cave,SAPRestrictionTrampoline,sizeof(SAPRestrictionTrampoline),context);
        if(memcmp(cave,SAPRestrictionTrampoline,sizeof(SAPRestrictionTrampoline)))goto rollback;
    }
    if(!keyPatched) {
        writer(keyCave,SAPKeyModeTrampoline,sizeof(SAPKeyModeTrampoline),context);
        if(memcmp(keyCave,SAPKeyModeTrampoline,sizeof(SAPKeyModeTrampoline)))goto rollback;
        writer(image+SAPJBKeyCallOffset,SAPJBKeyPatched+(SAPJBKeyCallOffset-SAPJBKeyWindowOffset),4,context);
        if(memcmp(key,SAPJBKeyPatched,sizeof(SAPJBKeyPatched)))goto rollback;
    }
    if(!guarded) {
        writer(setter,SAPGuardedSetterHead,4,context);
        if(memcmp(setter,SAPGuardedSetterHead,4))goto rollback;
    }
    if(reason)*reason="applied";
    return true;
rollback:
    writer(setter,oldHead,4,context);
    writer(image+SAPJBKeyCallOffset,oldKey,4,context);
    writer(keyCave,oldKeyCave,sizeof(oldKeyCave),context);
    writer(cave,oldCave,sizeof(oldCave),context);
    return fail(reason,"memory_write_failed");
}
