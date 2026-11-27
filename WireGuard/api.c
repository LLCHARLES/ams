#include "../tweak/Sources/Shared/WireGuard/SGWGBridge.h"

const struct SGWGAPI SGWGEngineV2 = {
    .version = SGWGEngineABIVersion, .size = sizeof(struct SGWGAPI),
    .inspect = SGWGInspect, .start = SGWGStart, .setCallback = SGWGSetStateCallback,
    .status = SGWGStatus, .rebind = SGWGRebind, .lookup = SGWGLookup,
    .stop = SGWGStop, .redact = SGWGRedact, .freeString = SGWGFree,
};
