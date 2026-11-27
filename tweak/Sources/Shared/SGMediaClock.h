#pragma once
#import <QuartzCore/QuartzCore.h>

// A harness can supply a clock function when compiling its copy of a reader.
// Release readers call Core Animation directly, with no runtime override.
#ifdef SG_MEDIA_CLOCK
extern CFTimeInterval SG_MEDIA_CLOCK(void);
#else
#define SG_MEDIA_CLOCK CACurrentMediaTime
#endif
