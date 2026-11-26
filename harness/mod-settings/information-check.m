// Real settings actions, with only UIKit presentation and icon-changing replaced.
#import <objc/runtime.h>
#import "Core/SGPrefs.h"
#import "Settings/SGModPage.h"
#import "Settings/SGPageStyle.h"
#import "Shared/AppIcon/AppIcon.h"
#import "Shared/ArtistBlock/ArtistBlock.h"
#import "Shared/AnimatedArtwork/AnimatedArtwork.h"
#import "../harness-fail.h"

static UIAlertController *shown;
static UIViewController *expectedPresenter;

static void checkAlert(NSString *title, NSString *message) {
    if (![shown.title isEqualToString:title]) HARNESS_FAIL(@"alert title: expected %@, got %@", title, shown.title);
    HARNESS_CHECK([shown.message isEqualToString:message]);
    HARNESS_CHECK(shown.preferredStyle == UIAlertControllerStyleAlert);
    HARNESS_CHECK(shown.actions.count == 1 && [shown.actions.firstObject.title isEqualToString:@"OK"] &&
                  shown.actions.firstObject.style == UIAlertActionStyleCancel);
    shown = nil;
}

void SGCheckInformationAlerts(void) {
    Method presentation = class_getInstanceMethod(UIViewController.class, @selector(presentViewController:animated:completion:));
    IMP originalPresentation = method_setImplementation(presentation, imp_implementationWithBlock(
        ^(UIViewController *presenter, UIViewController *controller, BOOL animated, void (^completion)(void)) {
            HARNESS_CHECK(NSThread.isMainThread && presenter == expectedPresenter && animated && !completion);
            HARNESS_CHECK([controller isKindOfClass:UIAlertController.class]);
            shown = (UIAlertController *)controller;
        }));

    UITableViewController *artists = (UITableViewController *)SGArtistBlockSettingsPage();
    expectedPresenter = artists;
    NSIndexPath *add = [NSIndexPath indexPathForRow:0 inSection:2];
    SGSetEnabled(SGKeyArtistBlock, NO);
    [artists tableView:artists.tableView didSelectRowAtIndexPath:add];
    HARNESS_CHECK(!shown && ![artists tableView:artists.tableView cellForRowAtIndexPath:add].userInteractionEnabled);
    SGSetEnabled(SGKeyArtistBlock, YES);
    [artists tableView:artists.tableView didSelectRowAtIndexPath:add];
    checkAlert(@"Nothing playing", @"Play a track by the artist first, then come back here.");

    expectedPresenter = SGTopController();
    SGLockScreenArtworkNeedsRow().action();
    checkAlert(@"Needs iOS 26", [NSString stringWithFormat:
        @"This iPhone has iOS %@. The lock screen takes moving artwork from apps from iOS 26 on, so the Canvas and Apple Music's animated covers can show there once the iPhone is updated.",
        UIDevice.currentDevice.systemVersion]);

    Method supports = class_getInstanceMethod(UIApplication.class, @selector(supportsAlternateIcons));
    IMP originalSupports = method_setImplementation(supports, imp_implementationWithBlock(^BOOL(id application) { return YES; }));
    Method change = class_getInstanceMethod(UIApplication.class, @selector(setAlternateIconName:completionHandler:));
    IMP originalChange = method_getImplementation(change);
    method_setImplementation(change, imp_implementationWithBlock(^(id application, NSString *name, void (^completion)(NSError *)) {
        HARNESS_CHECK([name isEqualToString:@"Fixture"]);
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
            completion([NSError errorWithDomain:@"Harness" code:1 userInfo:@{NSLocalizedDescriptionKey: @"Icon change refused"}]);
            // The product queues presentation on main before this assertion is queued.
            dispatch_async(dispatch_get_main_queue(), ^{
                checkAlert(@"The icon did not change", @"Icon change refused");
                method_setImplementation(change, originalChange);
                method_setImplementation(supports, originalSupports);
                method_setImplementation(presentation, originalPresentation);
                NSLog(@"[harness] information alerts PASS");
                exit(0);
            });
        });
    }));
    SGModRow *row = SGAppIconRow();
    HARNESS_CHECK(row.page != nil);
    UITableViewController *icons = (UITableViewController *)row.page();
    [icons tableView:icons.tableView didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:1 inSection:0]];
}
