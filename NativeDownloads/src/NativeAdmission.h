#pragma once
#include <stdbool.h>
#include <mach-o/loader.h>

// The host app's own executable: dyld's image 0, or, where a loader such as
// LiveContainer runs first and dlopens the app after it, the image whose file is
// the one _NSGetExecutablePath names (such a loader points it at the app).
bool SAPIsHostExecutableImage(const struct mach_header *header);
// The decision itself: `path` is the image's file, `executable` the process's.
bool SAPImageIsHostExecutable(const struct mach_header *header,const char *path,
                              const struct mach_header *image0,const char *executable);
// Exactly the main header admitted when it loaded (by name, file and UUID), not
// any other image or an address inside it; revoked when that image unloads.
bool SAPIsAdmittedMainImage(const struct mach_header *header);
void SAPObserveProfileImages(void);
#ifdef SAP_TESTING
void SAPTestAdmitMainImage(const struct mach_header *header);
void SAPTestRemoveImage(const struct mach_header *header);
#endif

// A loaded-library entry point is not proof that its host was admitted.
// Lock-free image snapshot published by dyld callbacks; bundle metadata is
// immutable. Rejections are never latched, and image removal revokes admission.
__attribute__((visibility("default"))) bool SAPRuntimeProfileAdmitted(void);
