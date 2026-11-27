#import <Foundation/Foundation.h>
#import "Core/SGCounterStore.h"
#import "Core/SGFileHash.h"
#import "../harness-fail.h"
#import "../sha256-fixture.h"
#import "../harness-wait.h"

// Capture the actual scheduled save and its requested offset at the GCD
// boundary. Other stores in this process have independent pending saves.
static NSMutableArray<dispatch_block_t> *saves;
static void scheduleSave(int64_t offset, dispatch_queue_t queue, dispatch_block_t save) {
    HARNESS_CHECK(queue == dispatch_get_main_queue() && offset == 30 * NSEC_PER_SEC);
    [saves addObject:[save copy]];
}
#define dispatch_time(base, delta) (delta)
#define dispatch_after scheduleSave
#import "Core/SGCounterStore.m"
#undef dispatch_after
#undef dispatch_time

static NSString *checkKey;
static void cleanDefaults(void) {
    [NSUserDefaults.standardUserDefaults removeObjectForKey:checkKey];
}

static SGCounterStore *plain(NSString *key) {
    return [[SGCounterStore alloc] initWithKey:key prepare:^BOOL(NSMutableDictionary *counts) { return NO; }];
}

static void checkHash(void) {
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    NSURL *url = [NSURL fileURLWithPath:path];
    HARNESS_CHECK(SGFileSHA256(url) == nil);
    HARNESS_CHECK([[NSData data] writeToURL:url atomically:YES]);
    HARNESS_CHECK([SGFileSHA256(url) isEqualToString:@"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"]);
    HARNESS_CHECK([[@"abc" dataUsingEncoding:NSUTF8StringEncoding] writeToURL:url atomically:YES]);
    HARNESS_CHECK([SGFileSHA256(url) isEqualToString:@"ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"]);
    // Independently calculated with Python hashlib; the file crosses a one-MiB chunk boundary.
    NSMutableData *large = [NSMutableData dataWithLength:1048579];
    memset(large.mutableBytes, 'a', large.length);
    HARNESS_CHECK([large writeToURL:url atomically:YES]);
    HARNESS_CHECK([SGFileSHA256(url) isEqualToString:@"f5e25b6b994188fdb721357d459785dc479934edfd40f95658a45ab2ce2d8027"]);
    HARNESS_CHECK([NSFileManager.defaultManager removeItemAtURL:url error:nil]);
}

static void checkDataHash(void) {
    NSArray<NSData *> *inputs = @[[NSData data], [@"abc" dataUsingEncoding:NSUTF8StringEncoding],
        [@"한글 😀/../" dataUsingEncoding:NSUTF8StringEncoding], [NSData dataWithBytes:"\0\xff\x80\x01" length:4]];
    for (NSData *data in inputs)
        HARNESS_CHECK([SGDataSHA256(data) isEqualToString:HarnessLegacySHA256(data)]);
    HARNESS_CHECK([SGDataSHA256(inputs[0]) isEqualToString:@"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"]);
    HARNESS_CHECK([SGDataSHA256(inputs[1]) isEqualToString:@"ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"]);
    HARNESS_CHECK([SGDataSHA256(nil) isEqualToString:HarnessLegacySHA256(nil)]);
}

int main(void) {
    @autoreleasepool {
        checkDataHash();
        checkHash();
        NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
        NSString *key = [@"retrine.counter-check." stringByAppendingString:NSUUID.UUID.UUIDString];
        checkKey = key;
        atexit(cleanDefaults);

        // Reset must neither load nor migrate the old dictionary, and must remove its disk value.
        [defaults setObject:@{@"old": @4} forKey:key];
        __block BOOL prepared = NO;
        SGCounterStore *reset = [[SGCounterStore alloc] initWithKey:key prepare:^BOOL(NSMutableDictionary *counts) {
            prepared = YES;
            return NO;
        }];
        [reset reset];
        HARNESS_CHECK(!prepared && ![defaults objectForKey:key] && !reset.counts.count);

        // A load-time migration can request persistence; its normalized snapshot is isolated.
        [defaults setObject:@{@"old": @4} forKey:key];
        SGCounterStore *migrated = [[SGCounterStore alloc] initWithKey:key prepare:^BOOL(NSMutableDictionary *counts) {
            [counts removeAllObjects];
            counts[@"checked"] = @0;
            return YES;
        }];
        NSDictionary *snapshot = migrated.counts;
        HARNESS_CHECK([snapshot isEqual:@{@"checked": @0}]);
        [migrated increment:@"checked"];
        HARNESS_CHECK([snapshot isEqual:@{@"checked": @0}]);
        [migrated flush];
        HARNESS_CHECK([[defaults dictionaryForKey:key] isEqual:@{@"checked": @1}]);
        [migrated reset];

        // Filtering alone does not dirty a loaded dictionary.
        [defaults setObject:@{@"keep": @2, @"obsolete": @9} forKey:key];
        SGCounterStore *filtered = [[SGCounterStore alloc] initWithKey:key prepare:^BOOL(NSMutableDictionary *counts) {
            [counts removeObjectForKey:@"obsolete"];
            return NO;
        }];
        HARNESS_CHECK([filtered.counts isEqual:@{@"keep": @2}]);
        [filtered flush];
        HARNESS_CHECK([[defaults dictionaryForKey:key][@"obsolete"] isEqual:@9]);
        [filtered reset];

        // Off-main flush cannot wait on main, and must snapshot at execution, not enqueue time.
        SGCounterStore *queued = plain(key);
        [queued increment:@"before"];
        dispatch_semaphore_t enqueued = dispatch_semaphore_create(0);
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
            [queued flush];
            dispatch_semaphore_signal(enqueued);
        });
        HARNESS_CHECK(dispatch_semaphore_wait(enqueued, dispatch_time(DISPATCH_TIME_NOW, HarnessWaitSeconds * NSEC_PER_SEC)) == 0);
        HARNESS_CHECK(![defaults objectForKey:key]);
        [queued reset];
        [queued increment:@"after"];
        HARNESS_AWAIT([defaults dictionaryForKey:key] != nil);
        HARNESS_CHECK([[defaults dictionaryForKey:key] isEqual:@{@"after": @1}]);

        // Flush remains visible to settings/export without broadcasting a preference change.
        __block NSUInteger notifications = 0;
        id observer = [NSNotificationCenter.defaultCenter addObserverForName:NSUserDefaultsDidChangeNotification
            object:nil queue:nil usingBlock:^(NSNotification *note) { notifications++; }];
        [queued increment:@"after"];
        [queued flush];
        HARNESS_CHECK(notifications == 0);
        HARNESS_CHECK([[defaults dictionaryRepresentation][key] isEqual:@{@"after": @2}]);
        [queued reset];
        HARNESS_CHECK(notifications == 0);
        [NSNotificationCenter.defaultCenter removeObserver:observer];
        HARNESS_AWAIT([defaults objectForKey:key] == nil);

        // First increment opens a 30-second window. Reset/flush inside it must not cancel or
        // postpone that timer, and the timer must save the new counts, not the original snapshot.
        SGCounterStore *timed = plain(key);
        saves = [NSMutableArray array];
        [timed increment:@"old"];
        HARNESS_CHECK(saves.count == 1 && ![defaults objectForKey:key]);
        [timed reset];
        [timed increment:@"new"];
        HARNESS_CHECK(saves.count == 1 && ![defaults objectForKey:key]);
        saves.firstObject();
        HARNESS_CHECK([[defaults dictionaryForKey:key] isEqual:@{@"new": @1}]);
        [timed reset];
        puts("counter store and file hash: ok");
    }
    return 0;
}
