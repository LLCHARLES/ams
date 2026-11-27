#import "Shared/LocalFiles/LocalFiles.h"

// Wait for worker reads while allowing main-thread publication to run.
static UIImage *loadCoverAndWait(NSString *uri) {
    __block BOOL done = NO;
    __block UIImage *cover;
    SGLocalFileLoadCover(uri, ^(UIImage *image) {
        if (!NSThread.isMainThread) { fprintf(stderr, "cover completion not on main\n"); exit(1); }
        cover = image; done = YES;
    });
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:60];
    while (!done && deadline.timeIntervalSinceNow > 0)
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.001]];
    if (!done) { fprintf(stderr, "cover load timed out\n"); exit(1); }
    return cover;
}
