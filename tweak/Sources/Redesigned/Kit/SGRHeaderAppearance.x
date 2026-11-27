#import "Core/SGUIMode.h"
#import "SGRHeaderClip.h"

%hook UIViewController
- (void)viewWillDisappear:(BOOL)animated {
    SGRHeaderPageWillDisappear(self);
    %orig;
}
- (void)viewDidDisappear:(BOOL)animated {
    %orig;
    SGRHeaderPageDidAppear(self, NO);
}
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    SGRHeaderPageDidAppear(self, YES);
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
}
