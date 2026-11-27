// The now playing bar and the tab bar keep their glass while the player opens and closes.
//
// Spotify does not move the real bars with the player: it hides them and moves stand-ins, made once at
// the start. CompactOverlayTransition holds them in npbSnapshotView and tabBarSnapshotView.
// renderInContext: cannot draw glass (UIVisualEffectView, UIKit's tab bar platters), so every close
// showed the bar's artwork and title and the tab bar's glyphs floating on nothing, and the glass
// popped back in when the real bars returned. Checked in the simulator: a snapshot view keeps the glass,
// a rendered image loses all of it.
//
// A stand-in that is an image gets live glass behind it, copied pane by pane from the view it was
// taken of, with the image moved into a child on top, so it moves and fades with Spotify's own frame
// and alpha changes. Live glass at half alpha still renders (simulator). The tab bar's selection bubble
// is not copied.
#import "Core/SGCore.h"
#import "Shared/WireGuard/SGWGABI.h"
#import "Redesigned/Kit/SGRGlass.h"

// The panes to copy: glass views and UIKit's tab bar platters, whose glass is not a UIVisualEffectView.
// The source itself may be hidden: Spotify renders the closed bar and hides it again before handing
// the image over.
static void collectPanes(UIView *view, NSMutableArray<UIView *> *panes) {
    for (UIView *sub in view.subviews) {
        if (sub.hidden || sub.alpha < 0.01) continue;
        if ([sub isKindOfClass:UIVisualEffectView.class] || [NSStringFromClass(sub.class) hasSuffix:@"PlatterView"]) {
            [panes addObject:sub];
            continue;
        }
        collectPanes(sub, panes);
    }
}

static UIVisualEffectView *copyPane(UIView *pane) {
    BOOL platter = ![pane isKindOfClass:UIVisualEffectView.class];
    UIVisualEffect *effect = platter ? SGRGlassEffect() : ((UIVisualEffectView *)pane).effect;
    UIVisualEffectView *glass = [[UIVisualEffectView alloc] initWithEffect:effect];
    glass.userInteractionEnabled = NO;
    // The effect does not carry the appearance the pane was drawn in, dark for both bars, and the stand-in
    // would give the copy the system's.
    glass.overrideUserInterfaceStyle = pane.traitCollection.userInterfaceStyle;
    if (platter) {
        SGShapeGlass(glass, pane.bounds.size.height / 2, YES);
    } else if ([pane respondsToSelector:@selector(cornerConfiguration)] && [glass respondsToSelector:@selector(setCornerConfiguration:)]) {
        [glass setCornerConfiguration:[(id)pane cornerConfiguration]];
    }
    glass.layer.cornerRadius = pane.layer.cornerRadius;
    glass.layer.cornerCurve = pane.layer.cornerCurve;
    glass.clipsToBounds = pane.clipsToBounds;
    return glass;
}

static void backWithGlass(UIView *snapshot, UIView *source, NSString *what) {
    if (![snapshot isKindOfClass:UIImageView.class] || ![source isKindOfClass:UIView.class]) return;
    UIImageView *image = (UIImageView *)snapshot;
    if (!image.image || image.subviews.count) return;
    NSMutableArray<UIView *> *panes = [NSMutableArray array];
    collectPanes(source, panes);
    if (!panes.count) return;

    CGSize from = source.bounds.size, to = image.bounds.size;
    CGFloat sx = from.width > 0 ? to.width / from.width : 1, sy = from.height > 0 ? to.height / from.height : 1;
    for (UIView *pane in panes) {
        CGRect frame = [pane.superview convertRect:pane.frame toView:source];
        UIVisualEffectView *glass = copyPane(pane);
        glass.frame = CGRectMake(frame.origin.x * sx, frame.origin.y * sy, frame.size.width * sx, frame.size.height * sy);
        glass.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleWidth
            | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin | UIViewAutoresizingFlexibleHeight;
        [image addSubview:glass];
    }
    UIImageView *content = [[UIImageView alloc] initWithImage:image.image];
    content.frame = image.bounds;
    content.contentMode = image.contentMode;
    content.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    image.image = nil;
    [image addSubview:content];

    static NSUInteger logged;
    if (logged++ < 4) SGLog(@"player transition: %@ stand-in got %lu glass panes", what, (unsigned long)panes.count);
}

@interface SGStoredField : NSObject
+ (id)field:(NSString *)name on:(id)object ofClass:(Class)cls;
@end

static UIView *ivarNamed(id object, const char *name) {
    return [SGStoredField field:@(name) on:object ofClass:UIView.class];
}

%group SGRCompactBarSnapshots
%hook _TtC19MainUI_TabBarUIImpl24CompactOverlayTransition
- (void)animateTransition:(id)context {
    %orig;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ SGLog(@"player transition: CompactOverlayTransition animates, snapshots %@ / %@",
                                  [ivarNamed(self, "npbSnapshotView") class], [ivarNamed(self, "tabBarSnapshotView") class]); });
    backWithGlass(ivarNamed(self, "npbSnapshotView"), ivarNamed(self, "npbView"), @"bar");
    backWithGlass(ivarNamed(self, "tabBarSnapshotView"), ivarNamed(self, "tabBarView"), @"tab bar");
}
%end
%end

%ctor {
    if (!SGRedesignedUI()) return;
    Class compact = NSClassFromString(@"_TtC19MainUI_TabBarUIImpl24CompactOverlayTransition");
    if (SGWGMethodMatches(class_getInstanceMethod(compact, @selector(animateTransition:)), "v", @[@"@"])) {
        %init(SGRCompactBarSnapshots);
    }
    SGRequireClasses(@[
        @"_TtC19MainUI_TabBarUIImpl24CompactOverlayTransition",
    ]);
}
