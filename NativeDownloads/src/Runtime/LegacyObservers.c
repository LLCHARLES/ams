#include <stdint.h>

// Retain the companion ABI without collecting key material. Neither supported
// target installs these three research observers.
__attribute__((visibility("default")))
void SpotifyAudioProbeObserveOfflineKey(const void *functionStorage, const void *result) {}
__attribute__((visibility("default")))
void SAPObserveAesBlock(const uint64_t *registers, uintptr_t image) {}
__attribute__((visibility("default")))
void SAPObserveAesCtr(const uint64_t *registers, uintptr_t image) {}
