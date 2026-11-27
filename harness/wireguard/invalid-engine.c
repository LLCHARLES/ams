// A real engine table with one ABI defect, exported from a disposable dylib.
#include "../../tweak/Sources/Shared/WireGuard/SGWGBridge.h"
#include <stddef.h>

#define FIELD(member, value) .member = offsetof(struct SGWGAPI, member) == \
    offsetof(struct SGWGAPI, INVALIDATE_FIELD) ? 0 : (value)
const struct SGWGAPI SGWGEngineV2 = {
    FIELD(version, SGWGEngineABIVersion), FIELD(size, sizeof(struct SGWGAPI)),
    FIELD(inspect, SGWGInspect), FIELD(start, SGWGStart), FIELD(setCallback, SGWGSetStateCallback),
    FIELD(status, SGWGStatus), FIELD(rebind, SGWGRebind), FIELD(lookup, SGWGLookup),
    FIELD(stop, SGWGStop), FIELD(redact, SGWGRedact), FIELD(freeString, SGWGFree),
};
