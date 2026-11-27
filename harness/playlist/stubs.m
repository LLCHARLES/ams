#import "../shared/redesigned-page-stubs.m"
#import "../shared/no-music-spectrum.h"
#import "../album/motion-player-double.h"

// Shared/AlbumQueue/AlbumQueueMenu.x: the ⋯ menu's album queue is a part of a native menu, not of the page.
void SGAlbumQueueMarkSource(UIView *view) {}

// SGPageStyle.m: the cover viewer is presented over whatever is on top of the harness's window.
UIViewController *SGTopController(void) {
    UIWindowScene *scene = (UIWindowScene *)UIApplication.sharedApplication.connectedScenes.anyObject;
    UIViewController *top = scene.windows.firstObject.rootViewController;
    while (top.presentedViewController) top = top.presentedViewController;
    return top;
}
