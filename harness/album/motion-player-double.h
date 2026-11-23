// PlayerField.x isn't linked into the page harnesses.
#import <UIKit/UIKit.h>
__weak UIView *harnessSettledPlayerField;
CGRect SGRSettledPlayerRect(UIWindow *window) {
    UIView *field = harnessSettledPlayerField;
    return field && field.window == window ? [field convertRect:field.bounds toView:window] : CGRectNull;
}
NSNotificationName const SGRPlayerVisibilityDidChangeNotification = @"SGRPlayerVisibilityDidChangeNotification";
