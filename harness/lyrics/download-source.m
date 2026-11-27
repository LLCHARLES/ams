#import "../dispatch-clock.h"
void HarnessBeginGlyphClose(void) { HarnessStartClock(); }
void HarnessFinishGlyphClose(void) {
    HARNESS_CHECK(harnessTimers.count == 1);
    HarnessAdvanceClock(220 * NSEC_PER_MSEC);
    HarnessStopClock();
}
#define dispatch_time HarnessTime
#define dispatch_after HarnessAfter
#import "Redesigned/Kit/SGRDownload.m"
