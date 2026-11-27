#import "clock.h"
#define UIApplicationDidBecomeActiveNotification @"UIApplicationDidBecomeActiveNotification"
#define UIApplicationSignificantTimeChangeNotification @"UIApplicationSignificantTimeChangeNotification"
#define dispatch_time HarnessClockTime
#define dispatch_after HarnessClockAfter
#import "Shared/Player/SpotifySleepTimer.m"
