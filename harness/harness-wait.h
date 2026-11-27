#pragma once
#import "harness-fail.h"

// Deadlines bound a missing event; they never signal success.
enum { HarnessWaitSeconds = 60 };

static inline BOOL HarnessRunUntil(BOOL (^ready)(void)) {
    NSTimeInterval end = NSProcessInfo.processInfo.systemUptime + HarnessWaitSeconds;
    while (!ready()) {
        if (NSProcessInfo.processInfo.systemUptime >= end) return NO;
        [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode
                               beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    }
    return YES;
}

#define HARNESS_AWAIT(...) do { \
    if (!HarnessRunUntil(^BOOL { return (__VA_ARGS__); })) \
        HARNESS_FAIL(@"still waiting for %s", #__VA_ARGS__); \
} while (0)

// Leave the main queue between observations: a nested run loop inside a
// main-queue callback cannot deliver another callback from that queue.
static inline void HarnessWhen(NSString *what, BOOL (^ready)(void), dispatch_block_t then) {
    NSTimeInterval end = NSProcessInfo.processInfo.systemUptime + HarnessWaitSeconds;
    [NSTimer scheduledTimerWithTimeInterval:0.025 repeats:YES block:^(NSTimer *timer) {
        if (ready()) {
            [timer invalidate];
            then();
        } else if (NSProcessInfo.processInfo.systemUptime >= end) {
            HARNESS_FAIL(@"still waiting for %@", what);
        }
    }];
}
