// The page fixtures render artwork without Spotify audio output.
#if __has_include("Shared/Player/SGMusicSpectrum.h")
#import "Shared/Player/SGMusicSpectrum.h"
void SGMusicSpectrumAddReader(void) {}
void SGMusicSpectrumRemoveReader(void) {}
uint64_t SGMusicSpectrumReadings(void) { return 0; }
BOOL SGMusicSpectrumReading(uint64_t index, float levels[3]) { return NO; }
#endif
