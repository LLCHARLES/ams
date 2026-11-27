#import "SGCounterStore.h"

static const int64_t kCounterSaveDelayNs = 30 * NSEC_PER_SEC;

@implementation SGCounterStore {
    NSString *_key;
    BOOL (^_prepare)(NSMutableDictionary<NSString *, NSNumber *> *);
    NSMutableDictionary<NSString *, NSNumber *> *_counts;
    BOOL _unsaved, _saveScheduled;
}

- (instancetype)initWithKey:(NSString *)key prepare:(BOOL (^)(NSMutableDictionary<NSString *, NSNumber *> *))prepare {
    if ((self = [super init])) {
        _key = [key copy];
        _prepare = [prepare copy];
    }
    return self;
}

- (void)saveOnMain {
    NSDictionary *snapshot;
    @synchronized (self) {
        if (!_unsaved) return;
        snapshot = [_counts copy];
        _unsaved = NO;
    }
    // Same app-domain keys for settings and backup, without NSUserDefaults' change broadcast.
    CFPreferencesSetAppValue((__bridge CFStringRef)_key, snapshot.count ? (__bridge CFDictionaryRef)snapshot : NULL,
                             kCFPreferencesCurrentApplication);
}

// Called under the lock. One timer covers all increments in this window, including after a reset.
- (void)scheduleSaveLocked {
    _unsaved = YES;
    if (_saveScheduled) return;
    _saveScheduled = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, kCounterSaveDelayNs), dispatch_get_main_queue(), ^{
        @synchronized (self) { self->_saveScheduled = NO; }
        [self saveOnMain];
    });
}

- (NSMutableDictionary<NSString *, NSNumber *> *)countsLocked {
    if (!_counts) {
        _counts = [[NSUserDefaults.standardUserDefaults dictionaryForKey:_key] mutableCopy] ?: [NSMutableDictionary dictionary];
        if (_prepare(_counts)) [self scheduleSaveLocked];
    }
    return _counts;
}

- (NSDictionary<NSString *, NSNumber *> *)counts {
    @synchronized (self) { return [[self countsLocked] copy]; }
}

- (void)increment:(NSString *)label {
    @synchronized (self) {
        NSMutableDictionary *counts = [self countsLocked];
        counts[label] = @([counts[label] unsignedIntegerValue] + 1);
        [self scheduleSaveLocked];
    }
}

- (void)flush {
    if (NSThread.isMainThread) [self saveOnMain];
    else dispatch_async(dispatch_get_main_queue(), ^{ [self saveOnMain]; });
}

- (void)reset {
    @synchronized (self) {
        _counts = [NSMutableDictionary dictionary];
        _unsaved = YES;
    }
    // An off-main reset queues its flush behind an in-flight main-queue write.
    [self flush];
}
@end
