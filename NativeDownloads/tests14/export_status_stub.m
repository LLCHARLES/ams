#import "TrackExport.h"

// These fixtures double the exporter; its status token must not be display copy.
NSString *const SAPAudioExportBusyIdentifier = @"fixture.export.busy";
BOOL SAPAudioExportIsBusy(NSString *error) {
    return [error isEqual:SAPAudioExportBusyIdentifier];
}
NSString *SAPAudioExportErrorText(NSString *error) {
    return SAPAudioExportIsBusy(error) ? @"Another export is already running." : error;
}
