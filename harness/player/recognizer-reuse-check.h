#pragma once
#import <UIKit/UIKit.h>
#import "../harness-fail.h"

static inline UIGestureRecognizer *onlyRecognizer(UIView *host, Class cls) {
    UIGestureRecognizer *found = nil;
    for (UIGestureRecognizer *gesture in host.gestureRecognizers)
        if ([gesture isKindOfClass:cls]) {
            HARNESS_CHECK(!found);
            found = gesture;
        }
    HARNESS_CHECK(found != nil);
    return found;
}

static inline void checkRecognizerReuse(UIView *host, UIView *other, NSString *name,
                                        void (^layout)(void), void (^layoutOther)(void)) {
    Class cls = NSClassFromString(name);
    UIGestureRecognizer *old = onlyRecognizer(host, cls);
    [host removeGestureRecognizer:old];
    [other addGestureRecognizer:old];
    layoutOther();
    __weak UIGestureRecognizer *detached;
    @autoreleasepool {
        layout();
        UIGestureRecognizer *replacement = onlyRecognizer(host, cls);
        detached = replacement;
        [host removeGestureRecognizer:replacement];
    }
    // No view, local strong reference or autorelease pool owns the new recognizer.
    HARNESS_CHECK(detached != nil);
    layout();
    layoutOther();
    layout();
    HARNESS_CHECK(onlyRecognizer(other, cls) == old);
    HARNESS_CHECK(onlyRecognizer(host, cls) != old);
}
