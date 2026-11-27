#pragma once
#import <Foundation/Foundation.h>
void SAPNativeErrorLogSetActive(BOOL active);
// Independent of diagnostics. Posts SAPOfflineTrackDownloaded with the verified URI as object.
__attribute__((visibility("default"))) void SAPNativeDownloadCompletionSetActive(BOOL active);
NSDictionary *SAPNativeErrorLogReport(void);
#ifdef SAP_TESTING
void SAPNativeErrorLogParseForTesting(NSString *line);
#endif
