#pragma once
#import <UIKit/UIKit.h>
#import "SpotifyPageContract.h"

// A stack we created for fallback is UIKit's, not Spotify's. Mark it with a
// process-wide selector so pages from either dylib can navigate back normally.
static inline UINavigationController *SAPFallbackPageStack(UIViewController *page) {
    UINavigationController *nav=[[UINavigationController alloc]initWithRootViewController:page];
    objc_setAssociatedObject(nav,sel_registerName("sap_fallbackPageStack"),@YES,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    nav.overrideUserInterfaceStyle=UIUserInterfaceStyleDark;
    return nav;
}

static inline BOOL SAPCanPushPage(UINavigationController *nav,UIViewController *page) {
    return nav && (objc_getAssociatedObject(nav,sel_registerName("sap_fallbackPageStack")) || SAPSpotifyPageContract(page.class,NO));
}

static inline void SAPShowPixiePage(UIViewController *owner,UIViewController *page) {
    if(SAPCanPushPage(owner.navigationController,page))
        [owner.navigationController pushViewController:page animated:YES];
    else {
        UINavigationController *nav=SAPFallbackPageStack(page);
        [owner presentViewController:nav animated:YES completion:nil];
    }
}
