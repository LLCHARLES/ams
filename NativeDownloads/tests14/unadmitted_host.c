#include <stdbool.h>
// A host Pixie does not admit, as under LiveContainer, where Spotify is not
// dyld's image 0: the redirected imports must still reach AudioToolbox.
bool SAPRuntimeProfileAdmitted(void) {return false;}
