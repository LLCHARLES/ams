#import <Foundation/Foundation.h>
#import <mach-o/dyld.h>
#import <dlfcn.h>
#import "../harness-fail.h"
#import "Shared/ListeningStats/SGTopCharts.h"

static const char *symbol;
static int imageInfo(void *address, Dl_info *info) {
    *info = (Dl_info){"/Lib/Test", (void *)0x10000, symbol, symbol ? (void *)0x10100 : NULL};
    return 1;
}
#define dladdr imageInfo
#import "describe.inc"
#undef dladdr

// Fail just the scratch allocations in the three owners, not Foundation's.
#define malloc(n) NULL
#define calloc(n, size) NULL
#import "Shared/ListeningStats/SGTopCharts.m"
#import "feed.inc"
static NSArray *systemSymbolNames(void) { return @[@"star", @"heart"]; }
static BOOL scriptVariant(NSString *name) { return NO; }
static BOOL symbolImage(NSString *name) { return YES; }
static NSArray *SGCommonTabSymbols(void) { return @[@"heart"]; }
#define SGLog(...) do {} while (0)
#import "tabs.inc"
#undef malloc
#undef calloc

// Return from the scan to a different screen. Neither the old owner nor a
// newly presented controller should be handed the deletion alert.
#define UIViewController NSObject
static NSObject *top;
static NSObject *SGTopController(void) { HARNESS_CHECK(NSThread.isMainThread); return top; }
static NSString *sg_leftoverSize;
static NSString *const kCleanupOffered = @"harness.offered";
enum { kTries = 1 };
static BOOL rechecked, presented;
static NSArray *chromaLeftovers(void) {
    HARNESS_CHECK(!NSThread.isMainThread);
    return @[[NSURL fileURLWithPath:@"/fixture"]];
}
static NSString *sizeOf(NSArray *urls) {
    HARNESS_CHECK(!NSThread.isMainThread);
    dispatch_async(dispatch_get_main_queue(), ^{ top = [NSObject new]; });
    return @"1 GB";
}
static void whenClear(NSInteger tries, dispatch_block_t then) {
    HARNESS_CHECK(NSThread.isMainThread);
    then();
    rechecked = YES;
}
static void showCleanup(NSArray *urls, NSString *size) { presented = YES; }
#import "cleanup.inc"

int main(void) { @autoreleasepool {
    HARNESS_CHECK([describe(0x10123) isEqual:@"Test +0x123"]);
    symbol = "<redacted>";
    HARNESS_CHECK([describe(0x10123) isEqual:@"Test +0x123"]);
    symbol = "named";
    HARNESS_CHECK([describe(0x10123) isEqual:@"Test named+35"]);
    HARNESS_CHECK(!adSection([@"sponsored" dataUsingEncoding:NSUTF8StringEncoding]));
    HARNESS_CHECK(![[SGChartLog alloc] initWithPlays:@[[SGPlay new]] kind:SGChartKindSongs before:100]);
    __block BOOL delivered = NO;
    SGLoadSymbolNames(^(NSArray *names) {
        HARNESS_CHECK(NSThread.isMainThread && [names isEqual:@[@"heart"]]);
        delivered = YES;
    });
    top = [NSObject new];
    offerCleanup(NO);
    while (!(delivered && rechecked))
        [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:1]];
    HARNESS_CHECK(!presented);
    puts("image offsets, allocation failures and cleanup eligibility: ok");
}}
