// Hooks a C function Spotify's binary imports, by pointing the binary's own import slot for it
// (its __got, or __la_symbol_ptr in an older build) at a replacement. Only calls Spotify's own code
// makes go through the new function; the system's frameworks keep calling the original. This is the
// fishhook technique, kept to Spotify's binary, for the few places no Objective-C method stands
// between Spotify and a system call (the audio output unit Music Haptics listens to). The binary is
// the image named Spotify (or named as the bundle's executable): the main executable, or under
// LiveContainer a dylib it dlopens. There it is expected to be loaded and bound before any %ctor runs
// (not yet confirmed by a LiveContainer log); if it is not, the log says so and nothing is rebound.
//
// Threading: call from a %ctor, before Spotify has run; the slots are written without a lock.
#import <Foundation/Foundation.h>

// Returns YES when at least one slot named `symbol` (without the leading underscore) was repointed.
// `original` receives what the first slot held, which is what the replacement calls on.
BOOL SGRebindImport(const char *symbol, void *replacement, void **original);
