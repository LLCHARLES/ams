#import "AdBlock.h"
#import "OfflineCompanion.h"
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <pthread.h>

typedef NSData *(*SGOfflineTransform)(NSData *);
typedef NSData *(*SGOfflineStatusTransform)(NSData *, SAPOfflineAttributesStatus *);
typedef struct { bool (*admitted)(void); SGOfflineTransform legacy; SGOfflineStatusTransform status; } SGOfflineAPI;

static SGOfflineAPI offlineAPI(void) {
    static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
    static SGOfflineAPI api;
    pthread_mutex_lock(&lock);
    if (!api.admitted) {
        for (uint32_t i = 0; i < _dyld_image_count(); i++) {
            const char *path = _dyld_get_image_name(i);
            if (!path || strcmp(strrchr(path, '/') ? strrchr(path, '/') + 1 : path, SGOfflineCompanionImageName)) continue;
            const void *image = _dyld_get_image_header(i);
            void *handle = dlopen(path, RTLD_LAZY | RTLD_NOLOAD);
            if (!handle) continue;
            void *admitted = dlsym(handle, "SAPRuntimeProfileAdmitted");
            void *legacy = dlsym(handle, "SAPRewriteOfflineAccountAttributes");
            void *status = dlsym(handle, "SAPRewriteOfflineAccountAttributesWithStatus");
            Dl_info info;
            if (admitted && (!dladdr(admitted, &info) || info.dli_fbase != image)) admitted = NULL;
            if (legacy && (!dladdr(legacy, &info) || info.dli_fbase != image)) legacy = NULL;
            if (status && (!dladdr(status, &info) || info.dli_fbase != image)) status = NULL;
            // Pin only a verified provider; cached function pointers must survive a caller's dlclose.
            if (admitted && (legacy || status)) { api = (SGOfflineAPI){admitted,legacy,status}; break; }
            dlclose(handle);
        }
    }
    SGOfflineAPI result = api;
    pthread_mutex_unlock(&lock);
    return result;
}

BOOL SGOfflineCompanionLoaded(void) {
    SGOfflineAPI api = offlineAPI();
    return api.admitted && api.admitted();
}

NSData *SGPatchOfflineAccountAttributes(NSData *body, BOOL *recognized) {
    SGOfflineAPI api = offlineAPI();
    SAPOfflineAttributesStatus status = {NO, NO};
    NSData *result = api.status ? api.status(body, &status) : api.admitted && api.admitted() ? api.legacy(body) : body;
    if (recognized) *recognized = status.admitted && status.recognized;
    return result;
}
