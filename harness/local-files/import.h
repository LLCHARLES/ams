#import "Shared/LocalFiles/LocalLyrics.h"

// Synchronous fixture setup around the asynchronous production import; callbacks still run on main.
static NSString *importLRC(NSURL *url, NSString *uri, NSError **error) {
    __block BOOL done = NO;
    __block NSString *name;
    __block NSError *failure;
    SGImportLRC(url, uri, ^(NSString *imported, NSError *reason) {
        if (!NSThread.isMainThread) { fprintf(stderr, "LRC completion is not on main\n"); exit(1); }
        name = imported; failure = reason; done = YES;
    });
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:60];
    while (!done && deadline.timeIntervalSinceNow > 0)
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.001]];
    if (!done) { fprintf(stderr, "LRC import timed out\n"); exit(1); }
    if (error) *error = failure;
    return name;
}

// The store's own work is on its queue, so a fixture waits for it the same way: on main.
static BOOL deleteLRC(NSString *name) {
    __block BOOL done = NO;
    __block BOOL deleted = NO;
    SGDeleteImportedLRC(name, ^(BOOL answer) {
        if (!NSThread.isMainThread) { fprintf(stderr, "delete completion is not on main\n"); exit(1); }
        deleted = answer; done = YES;
    });
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:60];
    while (!done && deadline.timeIntervalSinceNow > 0)
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.001]];
    if (!done) { fprintf(stderr, "LRC delete timed out\n"); exit(1); }
    return deleted;
}

// The launch's retire step, waited for the same way: the names it removed.
static inline __attribute__((unused)) NSArray<NSString *> *retireLRC(void) {
    __block BOOL done = NO;
    __block NSArray<NSString *> *removed;
    SGRetireImportedLyrics(^(NSArray<NSString *> *names) {
        if (!NSThread.isMainThread) { fprintf(stderr, "retire completion is not on main\n"); exit(1); }
        removed = names; done = YES;
    });
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:60];
    while (!done && deadline.timeIntervalSinceNow > 0)
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.001]];
    if (!done) { fprintf(stderr, "LRC retire timed out\n"); exit(1); }
    return removed ?: @[];
}
