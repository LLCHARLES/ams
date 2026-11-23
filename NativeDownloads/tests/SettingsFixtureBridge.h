#import "../src/Public/AudioProbeUI.h"
#import "../src/Public/Diagnostics.h"
#import "../../harness/harness-fail.h"
static inline void SAPFixtureFail(NSString *message) { HARNESS_FAIL(@"%@",message); }
BOOL SAPFixtureAutoLikeEnabled(void);
NSInteger SAPFixtureActionCount(void);
void SAPFixtureSetDownloadActive(BOOL active);
