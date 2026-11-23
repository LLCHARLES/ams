// The device button of the now playing bar, hidden unless switched back on, as the Music app's mini player has none,
// and shown in the minimized tab bar's row when that row keeps it (SGRKeyBarInlineConnect, SGRBarRowKeepsConnect).
// The redesign keeps Spotify's own buttons
// on its glass card, so the button and the way to hide it are the native look's, copied over.
//
// Tree (trees/test6.txt): the button row is a UIStackView holding Connect_EntryPointsImpl.ConnectStateView
// (the connected device) and .ConnectButtonView, each wrapped; hiding the wrapper closes the gap.
// The ConnectStateView under the title ("playing on ...") sits in InformationContainer and stays.
#import "Core/SGCore.h"
#import "NowPlayingBar.h"

static BOOL insideClass(UIView *view, NSString *marker) {
    for (UIView *v = view; v; v = v.superview) if ([NSStringFromClass(v.class) containsString:marker]) return YES;
    return NO;
}

// What this hid, so only that is shown again when the minimized row keeps the button or the switch goes off.
static NSHashTable<UIView *> *sg_hidden;

void SGRBarPlaceConnect(UIView *bar) {
    if (!sg_hidden) sg_hidden = [NSHashTable weakObjectsHashTable];
    if (!SGEnabled(SGRHideBarConnect) || SGRBarRowKeepsConnect()) {
        NSArray<UIView *> *items = sg_hidden.allObjects;
        [sg_hidden removeAllObjects];
        for (UIView *item in items) item.hidden = NO;
        return;
    }
    if (SGRBarInSheet(bar)) return;
    SGForEachView(bar, ^(UIView *v) {
        NSString *name = NSStringFromClass(v.class);
        if (![name containsString:@"ConnectButtonView"] && ![name containsString:@"ConnectStateView"]) return;
        if (insideClass(v, @"InformationContainer")) return;
        UIView *item = v;
        while (item.superview && ![item.superview isKindOfClass:UIStackView.class]) item = item.superview;
        if (!item.superview || item.hidden) return;
        item.hidden = YES;
        [sg_hidden addObject:item];
    });
}

%hook _TtC18NowPlaying_BarImpl27NowPlayingBarViewController
- (void)viewDidLayoutSubviews {
    %orig;
    SGRBarPlaceConnect(((UIViewController *)self).view);
}
%end

%ctor {
    if (!SGRedesignedUI() || !SGEnabled(SGRHideBarConnect)) return;
    %init;
    SGRequireClasses(@[@"_TtC18NowPlaying_BarImpl27NowPlayingBarViewController"]);
}
