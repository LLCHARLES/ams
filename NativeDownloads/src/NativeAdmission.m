#import "TargetAdmission.h"
#import "NativeAdmission.h"
#include <dlfcn.h>
#include <limits.h>
#include <stdatomic.h>
#include <sys/stat.h>

enum { SAPMainImage=1, SAPSharedImage=2, SAPRequiredImages=SAPMainImage|SAPSharedImage };
static atomic_uint admittedImages;

// The same file, not the same spelling: dyld and the loader may name it differently.
static bool sameFile(const char *a,const char *b) {
    struct stat x,y;
    return a&&b&&!stat(a,&x)&&!stat(b,&y)&&x.st_dev==y.st_dev&&x.st_ino==y.st_ino;
}

bool SAPImageIsHostExecutable(const struct mach_header *header,const char *path,
                              const struct mach_header *image0,const char *executable) {
    if(!header)return false;
    return header==image0||sameFile(path,executable);
}

static bool hostExecutable(const struct mach_header *header,const char *path) {
    char executable[PATH_MAX];uint32_t size=sizeof(executable);
    return SAPImageIsHostExecutable(header,path,_dyld_get_image_header(0),
                                    _NSGetExecutablePath(executable,&size)==0?executable:NULL);
}

bool SAPIsHostExecutableImage(const struct mach_header *header) {
    Dl_info info;
    return hostExecutable(header,header&&dladdr(header,&info)?info.dli_fname:NULL);
}

static unsigned profileImageKind(const struct mach_header *header) {
    Dl_info info;
    if(!dladdr(header,&info)||!info.dli_fname)return 0;
    const char *name=strrchr(info.dli_fname,'/');
    name=name?name+1:info.dli_fname;
    if(!strcmp(name,"Spotify")&&hostExecutable(header,info.dli_fname))return SAPMainImage;
    if(!strcmp(name,"SpotifyShared"))return SAPSharedImage;
    return 0;
}

// The exact main header admitted at load. Callers compare against it and its
// removal revokes it by pointer, never by looking the file up again.
static _Atomic(uintptr_t) admittedMain;

static void admitMain(const struct mach_header *header) {
    atomic_store_explicit(&admittedMain,(uintptr_t)header,memory_order_release);
    atomic_fetch_or_explicit(&admittedImages,SAPMainImage,memory_order_release);
}

static void profileImageAdded(const struct mach_header *header,intptr_t slide) {
    unsigned kind=profileImageKind(header);
    if(!kind)return;
    const uint8_t *uuid=kind==SAPMainImage?SAPProfileMainUUID:SAPProfileSharedUUID;
    if(!SAPProfileUUIDMatches((const void *)header,uuid))return;
    if(kind==SAPMainImage)admitMain(header);
    else atomic_fetch_or_explicit(&admittedImages,kind,memory_order_release);
}

static void profileImageRemoved(const struct mach_header *header,intptr_t slide) {
    uintptr_t expected=(uintptr_t)header;
    if(header&&atomic_compare_exchange_strong_explicit(&admittedMain,&expected,0,memory_order_acq_rel,memory_order_acquire))
        atomic_fetch_and_explicit(&admittedImages,~(unsigned)SAPMainImage,memory_order_release);
    Dl_info info;
    if(!dladdr(header,&info)||!info.dli_fname)return;
    const char *name=strrchr(info.dli_fname,'/');
    if(!strcmp(name?name+1:info.dli_fname,"SpotifyShared"))
        atomic_fetch_and_explicit(&admittedImages,~(unsigned)SAPSharedImage,memory_order_release);
}

bool SAPIsAdmittedMainImage(const struct mach_header *header) {
    return header&&(uintptr_t)header==atomic_load_explicit(&admittedMain,memory_order_acquire);
}

#ifdef SAP_TESTING
void SAPTestAdmitMainImage(const struct mach_header *header) {admitMain(header);}
void SAPTestRemoveImage(const struct mach_header *header) {profileImageRemoved(header,0);}
#endif

// Dyld owns image lifetimes during callbacks; readers never walk an unloadable
// header or an indexed image list. Registration replays already-loaded images.
__attribute__((constructor)) static void observeProfileImages(void) {
    _dyld_register_func_for_remove_image(profileImageRemoved);
    _dyld_register_func_for_add_image(profileImageAdded);
}

bool SAPRuntimeProfileAdmitted(void) {
    return SAPProfileMetadataMatches()&&
        atomic_load_explicit(&admittedImages,memory_order_acquire)==SAPRequiredImages;
}
