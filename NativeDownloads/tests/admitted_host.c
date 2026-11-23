// Unit fixtures explicitly supply an admitted host; production links NativeAdmission.m.
#include "../src/NativeAdmission.h"
static bool admitted=true;
bool SAPRuntimeProfileAdmitted(void) { return admitted; }
void SAPTestSetHostAdmitted(bool value) { admitted=value; }
