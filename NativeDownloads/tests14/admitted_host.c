#include <stdbool.h>
// Upstream algorithm fixtures supply an admitted host; runtime_effects.py and
// profile_runtime.py separately execute production fingerprint rejection.
bool SAPRuntimeProfileAdmitted(void) {return true;}
