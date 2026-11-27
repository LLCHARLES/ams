#ifndef SGWG_LOADER_POLICY_H
#define SGWG_LOADER_POLICY_H
#include <TargetConditionals.h>
#include <mach-o/loader.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>

#ifndef SGWG_LOADER_KEYS
#define SGWG_LOADER_KEYS "SGWGLoaderKeys.inc"
#endif
static const struct { const char *key; bool processOverride; } SGWGLoaderKeys[] = {
#include SGWG_LOADER_KEYS
};

static inline bool SGWGProcessOverrides(void) {
    for (size_t i = 0; i < sizeof(SGWGLoaderKeys)/sizeof(SGWGLoaderKeys[0]); ++i)
        if (SGWGLoaderKeys[i].processOverride && getenv(SGWGLoaderKeys[i].key)) return true;
    return false;
}

static inline bool SGWGEmbeddedOverride(const char *entry) {
    size_t n = strcspn(entry, "=");
    if (!n || entry[n] != '=') return true; // malformed assignment
    for (size_t i = 0; i < sizeof(SGWGLoaderKeys)/sizeof(SGWGLoaderKeys[0]); ++i)
        if (strlen(SGWGLoaderKeys[i].key) == n && !memcmp(entry, SGWGLoaderKeys[i].key, n)) return true;
    // dyld's embedded search directives use the DYLD_*_PATH namespace.
    return n >= 10 && !memcmp(entry, "DYLD_", 5) && !memcmp(entry + n - 5, "_PATH", 5);
}

// dyld supplies the mapped executable header and its load-command region.
static inline bool SGWGHostOverrides(const struct mach_header_64 *host) {
    if (!host || host->magic != MH_MAGIC_64 || host->filetype != MH_EXECUTE) return true;
    const uint8_t *p = (const uint8_t *)(host + 1);
    size_t remaining = host->sizeofcmds;
    for (uint32_t i = 0; i < host->ncmds; ++i) {
        if (remaining < sizeof(struct load_command)) return true;
        const struct load_command *lc = (const void *)p;
        size_t size = lc->cmdsize;
        if (size < sizeof(*lc) || size % 8 || size > remaining) return true;
        if (lc->cmd == LC_DYLD_ENVIRONMENT) {
            const struct dylinker_command *env = (const void *)p;
            if (size < sizeof(*env)) return true;
            size_t offset = env->name.offset;
            if (offset < sizeof(*env) || offset >= size || !memchr(p + offset, 0, size - offset)
                || SGWGEmbeddedOverride((const char *)p + offset)) return true;
        }
        p += size;
        remaining -= size;
    }
    return remaining != 0;
}
#endif
