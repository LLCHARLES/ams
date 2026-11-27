// C ABI of the separately loaded Go engine in WireGuard/bridge.go.
// Every returned string is malloc'ed by Go and must be freed with SGWGFree.
#ifndef SGWG_BRIDGE_H
#define SGWG_BRIDGE_H
#include <stdint.h>

// Shared with cgo: readiness is structural, never a verdict about one destination.
enum SGWGEngineEvent {
    SGWGEngineStopped = 0,
    SGWGEngineAvailable = 1,
    SGWGEngineUnavailable = 2,
    SGWGEngineDestinationFailed = 3,
};

#ifdef __cplusplus
extern "C" {
#endif

enum SGWGStartResult {
    SGWGStarted, SGWGStartNetworkUnavailable, SGWGStartRefused
};
char *SGWGInspect(char *text);
// Consumes a duplicate of the reserved, bound socket on every outcome.
enum SGWGStartResult SGWGStart(char *text, char *user, char *pass, int listenerFD);
void SGWGStop(void);
char *SGWGStatus(void);
void SGWGSetStateCallback(uintptr_t callback, uintptr_t admitted);
int SGWGRebind(void);
char *SGWGLookup(char *host);
char *SGWGResolve(char *host);
char *SGWGRedact(char *text);
void SGWGFree(char *p);

// The versioned table is the sole exported symbol of the engine dylib.
// Derive its types from the declarations shared with cgo.
enum { SGWGEngineABIVersion = 2 };
struct SGWGAPI {
    uint32_t version;
    uint32_t size;
    __typeof__(&SGWGInspect) inspect;
    __typeof__(&SGWGStart) start;
    __typeof__(&SGWGSetStateCallback) setCallback;
    __typeof__(&SGWGStatus) status;
    __typeof__(&SGWGRebind) rebind;
    __typeof__(&SGWGLookup) lookup;
    __typeof__(&SGWGStop) stop;
    __typeof__(&SGWGRedact) redact;
    __typeof__(&SGWGFree) freeString;
};
extern const struct SGWGAPI SGWGEngineV2;

#ifdef __cplusplus
}
#endif

#endif
