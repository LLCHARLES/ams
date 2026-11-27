#import "art-dispatch.h"
#include "LockScreenMotion.m"

BOOL harnessCoverRevisions(UIImage *a, UIImage *b) {
    __block BOOL reused;
    dispatch_sync(sg_queue, ^{
        NSString *first = coverSource(a.CGImage, NSUIntegerMax);
        NSString *again = coverSource(a.CGImage, NSUIntegerMax);
        NSString *second = coverSource(b.CGImage, NSUIntegerMax - 1);
        reused = first && second && first == again && ![first isEqual:second]
            && [first isEqual:coverSource(a.CGImage, NSUIntegerMax - 2)];
    });
    return reused;
}
