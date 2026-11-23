#import "../timer-lifecycle.h"
#import "Shared/Player/PlayerState.h"
#import "Core/SGRebind.h"
#import <dns_sd.h>

static NSUInteger searches, stops;
BOOL SGRebindImport(const char *name, void *replacement, void **original) { return NO; }
#import "Connect.m"

@protocol LocationObserver <NSObject>
- (void)aggregator:(id)aggregator didUpdateAggregatorState:(id)state;
@end
@interface _TtC22Connect_AggregatorImpl24ConnectAggregatorManager : NSObject
@property (nonatomic, getter=isPlayingLocally) BOOL local;
@property (nonatomic, strong) NSMutableArray *observers;
- (void)addStateObserver:(id)observer;
- (void)report;
@end
@implementation _TtC22Connect_AggregatorImpl24ConnectAggregatorManager
- (void)addStateObserver:(id)observer {
    if (!_observers) _observers = [NSMutableArray array];
    [_observers addObject:observer];
}
- (void)report {
    for (id<LocationObserver> observer in _observers)
        if ([observer respondsToSelector:@selector(aggregator:didUpdateAggregatorState:)])
            [observer aggregator:self didUpdateAggregatorState:nil];
}
@end

static void drainLocation(void) {
    // Manager attachment queues its initial location report on the next main-queue turn.
    dispatch_async(dispatch_get_main_queue(), ^{
        dispatch_async(dispatch_get_main_queue(), ^{ CFRunLoopStop(CFRunLoopGetMain()); });
    });
    CFRunLoopRun();
}

int main(void) {
    @autoreleasepool {
        SGHarnessBeginTimerCapture();
        Method search = class_getInstanceMethod(NSNetServiceBrowser.class, @selector(searchForServicesOfType:inDomain:));
        Method stop = class_getInstanceMethod(NSNetServiceBrowser.class, @selector(stop));
        IMP oldSearch = method_setImplementation(search, imp_implementationWithBlock(^(id object, NSString *type, NSString *domain) { searches++; }));
        IMP oldStop = method_setImplementation(stop, imp_implementationWithBlock(^(id object) { stops++; }));
        SGConnectBrowser *browser = [SGConnectBrowser new];
        [browser start];
        HARNESS_CHECK(searches == 1);
        [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationDidEnterBackgroundNotification object:nil];
        HARNESS_CHECK(stops == 1 && SGHarnessLiveTimers() == 0);
        NSObject *first = [NSObject new], *second = [NSObject new];
        pickerVisible(first, YES);
        pickerVisible(second, YES);
        HARNESS_CHECK(searches == 2);
        pickerVisible(first, NO);
        HARNESS_CHECK(stops == 1);
        pickerVisible(second, NO);
        HARNESS_CHECK(stops == 2);
        __block NSUInteger notices = 0;
        id token = [NSNotificationCenter.defaultCenter addObserverForName:SGPlayerPlaybackLocationDidChangeNotification
            object:nil queue:nil usingBlock:^(NSNotification *note) {
                HARNESS_CHECK(NSThread.isMainThread);
                notices++;
            }];
        HARNESS_CHECK(!SGPlayerPlaybackIsLocal() && !SGPlayerPlaybackIsRemote());
        _TtC22Connect_AggregatorImpl24ConnectAggregatorManager *manager =
            [_TtC22Connect_AggregatorImpl24ConnectAggregatorManager new];
        dispatch_sync(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
            [manager addStateObserver:[NSObject new]];
        });
        drainLocation();
        HARNESS_CHECK(searches == 3 && notices == 1 && SGPlayerPlaybackIsRemote() && !SGPlayerPlaybackIsLocal());
        [manager report];
        drainLocation();
        HARNESS_CHECK(notices == 1);
        manager.local = YES;
        [manager report];
        drainLocation();
        HARNESS_CHECK(notices == 2 && stops == 3 && SGPlayerPlaybackIsLocal() && !SGPlayerPlaybackIsRemote());
        manager.local = NO;
        dispatch_sync(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{ [manager report]; });
        drainLocation();
        HARNESS_CHECK(notices == 3 && searches == 4 && SGPlayerPlaybackIsRemote());
        NSNetServiceBrowser *service = [browser valueForKey:@"browser"];
        [browser netServiceBrowser:service didNotSearch:@{NSNetServicesErrorCode: @(kDNSServiceErr_PolicyDenied)}];
        [browser update];
        HARNESS_CHECK(searches == 4 && SGHarnessLiveTimers() == 0);
        [browser foreground];
        HARNESS_CHECK(searches == 5);
        manager.local = YES;
        [manager report];
        drainLocation();
        [browser background];
        [browser foreground];
        HARNESS_CHECK(searches == 6);
        [browser background];
        method_setImplementation(search, oldSearch);
        method_setImplementation(stop, oldStop);
        [NSNotificationCenter.defaultCenter removeObserver:token];
        SGHarnessEndTimerCapture();
        puts("PASS Connect background, initial remote attachment, deduplicated main-thread location changes, picker and denial lifecycle");
    }
}
