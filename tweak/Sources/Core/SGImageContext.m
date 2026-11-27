#import "SGImageContext.h"
#import <UIKit/UIKit.h>

CIContext *SGOneOffImageContext(void) {
    static CIContext *context;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        context = [CIContext contextWithOptions:@{kCIContextCacheIntermediates: @NO}];
        [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidReceiveMemoryWarningNotification
            object:nil queue:nil usingBlock:^(NSNotification *note) { [context clearCaches]; }];
    });
    return context;
}
