// Tab bar: Spotify's own bar stays where it is but goes invisible, and a system UITabBar sits on top
// of it. On iOS 26+ with UIDesignRequiresCompatibility off, UIKit draws that bar as real Liquid Glass
// (selection bubble, lensing, light/dark adaptation) with no glass API of ours. Spotify's bar keeps
// its frame, so the page insets and the now playing bar stay where Spotify puts them; where the system
// bar is taller than Spotify's, Spotify is made to leave it the room (see "room for the glass bar").
//
// A tab picked on the system bar is passed on as a tap on the hidden Spotify item it mirrors, and the
// system bar's selection follows whichever Spotify label is painted white, or the tab of the mod's own whose
// page is up (SGRNavbarLitTab), which Spotify does not know of. Navbar.x composes the
// hidden row, so its order, hidden tabs and tabs of the mod's own carry over. Always on in the redesign.
//
// Tree (trees/home.txt): NavigationUI_TabBarImpl.TabBarView > TabBarCompactView > UIStackView of
//   ElementContentView<TabBarItemElement>, each with an SPTEncoreIconView and an SPTEncoreLabel.
#import "Core/SGCore.h"
#import "Navbar.h"
#import "Redesigned/Kit/SGRTokens.h"
#import "Redesigned/NowPlayingBar/NowPlayingBar.h"
#import "Settings/SGPage.h"
#import "Headers/SPTEncoreIconView.h"
#import "Shared/Navigation/TabIcons.h"
#import <objc/message.h>

static char kBarKey, kTrailBarKey, kHostKey, kFadeKey;
static __weak UIView *sg_stockBar;
static CGFloat sg_room, sg_glassHeight;   // see "room for the glass bar"
// See "minimized".
static BOOL sg_minimized;
// The trailing circle sliding back into the row as the bar grows, kept on screen until it has.
static BOOL sg_trailLeaving;
static BOOL sg_fingerOnBar;
// A circle tapped, lit at once rather than when Spotify repaints its tab a moment later (its owner, 2026-10-27).
static __weak UIView *sg_pendingActive;
static CFTimeInterval sg_pendingUntil;

@interface SGRSystemTabBar : UITabBar <UITabBarDelegate, UIGestureRecognizerDelegate>
@property (nonatomic, weak) UIView *stockBar;
@property (nonatomic, copy) NSArray<UIView *> *sources;
@property (nonatomic, weak) UILongPressGestureRecognizer *hold;
@property (nonatomic) BOOL holding;
// The other bar, the minimized bar's trailing circle and its leading one: a tab picked on one clears the other's.
@property (nonatomic, weak) SGRSystemTabBar *partner;
// The item last shown selected, so a tap on it can be told from a tap that changes the tab.
@property (nonatomic, weak) UITabBarItem *shown;
@end

static void syncBar(UIView *stockBar);

#pragma mark - reading Spotify's items

// The items the bar shows, left to right as Navbar/Navbar.x placed them.
static NSArray<UIView *> *tabItems(UIView *tabBar) {
    NSMutableArray<UIView *> *items = [NSMutableArray array];
    for (UIView *item in SGRowIn(tabBar).arrangedSubviews) {
        if (!item.hidden && item.bounds.size.width >= 20) [items addObject:item];
    }
    return [items sortedArrayUsingComparator:^NSComparisonResult(UIView *a, UIView *b) {
        return [@(SGFrameIn(a, tabBar).origin.x) compare:@(SGFrameIn(b, tabBar).origin.x)];
    }];
}

// The first tab the bar shows, whichever the tab editor put there: the one held for Mod Settings.
static BOOL isFirstTab(UIView *item, UIView *tabBar) {
    return item && item == tabItems(tabBar).firstObject;
}

static UILabel *labelIn(UIView *item) {
    __block UILabel *label = nil;
    SGForEachView(item, ^(UIView *v) {
        if (!label && [v isKindOfClass:UILabel.class] && ((UILabel *)v).text.length) label = (UILabel *)v;
    });
    return label;
}

static UIView *iconIn(UIView *item) {
    __block UIView *icon = nil;
    SGForEachView(item, ^(UIView *v) {
        if (icon || v.bounds.size.width < 2) return;
        if ([v isKindOfClass:UIImageView.class] || [NSStringFromClass(v.class) containsString:@"IconView"]) icon = v;
    });
    return icon;
}

// Spotify paints the selected tab's label white and the rest #B3B3B3.
static BOOL isActive(UIView *item) {
    UIColor *color = labelIn(item).textColor;
    CGFloat white = 0, alpha = 0, r, g, b;
    if (![color getWhite:&white alpha:&alpha] && [color getRed:&r green:&g blue:&b alpha:&alpha]) white = MIN(r, MIN(g, b));
    return white > 0.95;
}

static BOOL hasInk(UIImage *image) {
    CGImageRef cg = image.CGImage;
    size_t width = CGImageGetWidth(cg), height = CGImageGetHeight(cg);
    if (!width || !height) return NO;
    NSMutableData *pixels = [NSMutableData dataWithLength:width * height];
    CGContextRef context = CGBitmapContextCreate(pixels.mutableBytes, width, height, 8, width, NULL, (CGBitmapInfo)kCGImageAlphaOnly);
    CGContextDrawImage(context, CGRectMake(0, 0, width, height), cg);
    CGContextRelease(context);
    const uint8_t *alpha = pixels.bytes;
    for (size_t i = 0; i < pixels.length; i++) if (alpha[i] > 16) return YES;
    return NO;
}

static UIImage *renderLayer(CALayer *layer, CGSize size) {
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:size];
    UIImage *image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [layer renderInContext:context.CGContext];
    }];
    return hasInk(image) ? [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate] : nil;
}

// The SPTEncoreIcon an icon view was built with. Encore keeps it in a Swift ivar with no getter.
static id encoreIconOf(UIView *view) {
    Ivar ivar = class_getInstanceVariable(view.class, "icon");
    const char *type = ivar ? ivar_getTypeEncoding(ivar) : NULL;
    return type && type[0] == '@' ? object_getIvar(view, ivar) : nil;
}

// Encore draws a tab's icon from one SPTEncoreIcon in two states: isActive picks its filled variant.
// Both are drawn on an icon view of our own, off screen, so the images do not wait for Spotify's
// views to lay out and paint, and UITabBar swaps image and selectedImage itself.
static UIImage *glyphOf(UIView *item, BOOL active) {
    UIView *live = iconIn(item);
    if (!live) return nil;
    CGSize size = live.bounds.size;
    id icon = encoreIconOf(live);
    Class viewClass = NSClassFromString(@"SPTEncoreIconView");
    if (icon && viewClass) {
        static NSCache<NSString *, UIImage *> *cache;
        if (!cache) cache = [NSCache new];
        NSString *key = [NSString stringWithFormat:@"%@ %d %@", [icon respondsToSelector:@selector(name)] ? [icon name] : icon, active, NSStringFromCGSize(size)];
        UIImage *cached = [cache objectForKey:key];
        if (cached) return cached;
        SPTEncoreIconView *view = [[viewClass alloc] initWithIcon:icon];
        view.frame = (CGRect){CGPointZero, size};
        [view setForegroundColor:UIColor.whiteColor];
        if ([view respondsToSelector:@selector(setActiveForegroundColor:)]) [view setActiveForegroundColor:UIColor.whiteColor];
        if ([view respondsToSelector:@selector(setIsActive:)]) [view setIsActive:active];
        [view layoutIfNeeded];
        UIImage *image = renderLayer(view.layer, size);
        if (image) {
            [cache setObject:image forKey:key];
            return image;
        }
    }
    // Tabs of the mod's own draw a UIImageView, or an icon Encore would not draw off screen. On 9.1.90 Spotify's own
    // icon views name no icon, so its tab is pictured off the live view, which shows its filled icon only while its tab
    // is the one Spotify is on: a tab picked kept the hollow picture it was made with (its owner, 2026-10-26). So the
    // live view is drawn in the state asked for, its state set for the drawing and given back at once, without
    // animation, and both pictures are kept per tab: UIKit then shows the filled one in the lens's lit copy as the lens
    // passes over it, as YouTube's glass bar does (its owner's recording).
    if (size.width < 2) return nil;
    BOOL toggles = [live isKindOfClass:viewClass] && [live respondsToSelector:@selector(setIsActive:)] && [live respondsToSelector:@selector(isActive)];
    if (!toggles) return renderLayer(live.layer, size);
    static NSCache<NSString *, UIImage *> *pictures;
    if (!pictures) pictures = [NSCache new];
    NSString *key = [NSString stringWithFormat:@"%@ %d %@", labelIn(item).text ?: @"", active, NSStringFromCGSize(size)];
    UIImage *kept = [pictures objectForKey:key];
    if (kept) return kept;
    SPTEncoreIconView *spotify = (SPTEncoreIconView *)live;
    BOOL was = [spotify isActive];
    __block UIImage *image = nil;
    [UIView performWithoutAnimation:^{
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        if (was != active) {
            [spotify setIsActive:active];
            [spotify layoutIfNeeded];
        }
        image = renderLayer(spotify.layer, size);
        if (was != active) {
            [spotify setIsActive:was];
            [spotify layoutIfNeeded];
        }
        [CATransaction commit];
    }];
    if (image) [pictures setObject:image forKey:key];
    return image;
}

// For the Tab bar page's list and preview: a tab of Spotify's drawn from its item on the bar, hidden or not,
// found by the label its entry is named after; a tab of the mod's own drawn from its entry, as Navbar.x
// draws it on the bar. Nil while Spotify's item has not been built.
UIImage *SGRNavbarGlyph(NSDictionary *entry, BOOL active) {
    if (entry[SGRNavbarURI]) {
        UIView *holder = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 24, 24)];
        UIView *icon = SGTabIconView(entry[SGRNavbarIcon], [entry[SGRNavbarIconSet] isEqual:SGTabIconSetSymbols], UIColor.whiteColor);
        icon.translatesAutoresizingMaskIntoConstraints = YES;
        icon.frame = holder.bounds;
        if ([icon isKindOfClass:UIImageView.class]) icon.contentMode = UIViewContentModeScaleAspectFit;
        [holder addSubview:icon];
        [holder layoutIfNeeded];
        return glyphOf(holder, active);
    }
    for (UIView *item in SGRowIn(sg_stockBar).arrangedSubviews) {
        if ([NSStringFromClass(item.class) isEqualToString:@"SGRTabItemView"]) continue;
        if ([labelIn(item).text isEqualToString:entry[SGRNavbarID]]) return glyphOf(item, active);
    }
    return nil;
}

#pragma mark - passing a tap on

// NavigationUI_TabBarImpl's TabBarItemElementUI answers a tap recognizer (-handleTap), so the tap is
// replayed through the recognizer's own target-action pairs, the same call a real touch ends in.
static BOOL fireTapRecognizers(UIView *view) {
    Ivar targetsIvar = class_getInstanceVariable(UIGestureRecognizer.class, "_targets");
    if (!targetsIvar) return NO;
    BOOL fired = NO;
    for (UIGestureRecognizer *recognizer in view.gestureRecognizers) {
        if (![recognizer isKindOfClass:UITapGestureRecognizer.class] || !recognizer.enabled) continue;
        for (id pair in object_getIvar(recognizer, targetsIvar)) {
            Ivar targetIvar = class_getInstanceVariable([pair class], "_target");
            Ivar actionIvar = class_getInstanceVariable([pair class], "_action");
            if (!targetIvar || !actionIvar) continue;
            id target = object_getIvar(pair, targetIvar);
            SEL action = *(SEL *)((char *)(__bridge void *)pair + ivar_getOffset(actionIvar));
            if (!target || !action || ![target respondsToSelector:action]) continue;
            SGLog(@"tab bar: tap -> %@ %@", NSStringFromClass([target class]), NSStringFromSelector(action));
            ((void (*)(id, SEL, id))objc_msgSend)(target, action, recognizer);
            fired = YES;
        }
    }
    return fired;
}

static void forwardTap(UIView *item) {
    __block BOOL sent = NO;
    SGForEachView(item, ^(UIView *v) {
        if (!sent) sent = fireTapRecognizers(v);
    });
    SGForEachView(item, ^(UIView *v) {
        if (sent || ![v isKindOfClass:UIControl.class]) return;
        SGLog(@"tab bar: tap -> control %@", NSStringFromClass(v.class));
        [(UIControl *)v sendActionsForControlEvents:UIControlEventTouchUpInside];
        sent = YES;
    });
    if (!sent) {
        NSMutableString *out = [NSMutableString stringWithFormat:@"tab bar: nothing to tap in %@", NSStringFromClass(item.class)];
        SGForEachView(item, ^(UIView *v) {
            for (UIGestureRecognizer *r in v.gestureRecognizers) [out appendFormat:@"\n  %@ on %@", r, NSStringFromClass(v.class)];
        });
        SGLogLong(@"navbar", out);
    }
}

#pragma mark - holding the first tab

// Holding the first tab (Home, unless the tab editor moved another there; its owner asked for the first, 2026-10-25)
// opens Mod Settings as a press and hold, as YTGlass's hold on YouTube's Home does: a little longer than
// iOS's own press for a menu (some 0.5 s) and a firm tap when it opens, so the hold is felt and a slow tap is not taken
// for one. Letting go before then is an ordinary tap.
static const NSTimeInterval kFirstTabHold = 0.8;

static void firstTabHeld(UIView *source) {
    UIImpactFeedbackGenerator *tap = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    [tap impactOccurred];
    SGOpenModSettings(source);
}

#pragma mark - the system bar

// A name too long for its tab (one of the user's own) shrinks a little before UIKit cuts
// it short, to 8 pt from 10.
void SGRShrinkTabTitles(UIView *bar) {
    SGForEachView(bar, ^(UIView *v) {
        if (![v isKindOfClass:UILabel.class] || ((UILabel *)v).adjustsFontSizeToFitWidth) return;
        ((UILabel *)v).adjustsFontSizeToFitWidth = YES;
        ((UILabel *)v).minimumScaleFactor = 0.8;
    });
}

static void widenPlatter(UITabBar *bar);
static void pressCircle(UIView *bar, BOOL down);
static BOOL isTabButton(UIView *view);
static UIImageView *glyphView(UIView *button);

@implementation SGRSystemTabBar

// UIKit makes the labels as it lays the items out, so they are shrunk after each pass, and the row's platter is
// widened to the bar after it.
- (void)layoutSubviews {
    [super layoutSubviews];
    widenPlatter(self);
    SGRShrinkTabTitles(self);
}

- (void)tabBar:(UITabBar *)tabBar didSelectItem:(UITabBarItem *)item {
    NSUInteger index = [self.items indexOfObject:item];
    if (index == NSNotFound || index >= self.sources.count) return;
    self.shown = item;
    // A minimized circle is its tab, as a tab of the full bar is: a tap on the one the page is on takes Spotify's stack
    // back to its root, and the bar stays minimized (its owner asked for this over the Music app's, whose circle brings
    // the bar back, 2026-10-27).
    // One of Spotify's own takes the light back from a tab of the mod's own.
    UIView *source = self.sources[index];
    if (![NSStringFromClass(source.class) isEqualToString:@"SGRTabItemView"]) SGRNavbarForgetTab();
    // Home tapped while on Home pops Spotify's stack, which would take Mod Settings straight off it.
    if (!self.holding) forwardTap(source);
    if (sg_minimized && !self.holding && self.stockBar) {
        sg_pendingActive = source;
        sg_pendingUntil = CACurrentMediaTime() + 0.6;
        syncBar(self.stockBar);
    }
    self.partner.selectedItem = nil;
    self.partner.shown = nil;
    // Spotify repaints its labels a moment later; a tap it did not take snaps the selection back.
    UIView *stockBar = self.stockBar;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (stockBar) syncBar(stockBar);
    });
}

// UIKit's item views are private, so the item under a touch is the one whose title label or glyph is
// nearest. With the labels hidden only the glyph is left; UIKit shows the item's own image instance.
- (UITabBarItem *)itemAt:(CGPoint)point {
    __block UITabBarItem *nearest = nil;
    __block CGFloat best = CGFLOAT_MAX;
    SGForEachView(self, ^(UIView *v) {
        BOOL label = [v isKindOfClass:UILabel.class], glyph = [v isKindOfClass:UIImageView.class];
        if ((!label && !glyph) || v.bounds.size.width < 1) return;
        CGFloat distance = fabs([v convertPoint:CGPointMake(CGRectGetMidX(v.bounds), 0) toView:self].x - point.x);
        if (distance >= best) return;
        for (UITabBarItem *item in self.items) {
            UIImage *image = glyph ? ((UIImageView *)v).image : nil;
            if (label ? ![((UILabel *)v).text isEqualToString:item.title] : !image || (image != item.image && image != item.selectedImage)) continue;
            best = distance;
            nearest = item;
            break;
        }
    });
    return nearest;
}

// UIView asks itself this for its own recognizers too, so only the hold is answered here.
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)recognizer {
    if (recognizer != self.hold) return [super gestureRecognizerShouldBegin:recognizer];
    NSUInteger index = [self.items indexOfObject:[self itemAt:[recognizer locationInView:self]]];
    return index < self.sources.count && isFirstTab(self.sources[index], self.stockBar);
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)recognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other {
    return YES;
}

- (void)fingerMoved:(UILongPressGestureRecognizer *)finger {
    UIGestureRecognizerState state = finger.state;
    sg_fingerOnBar = state == UIGestureRecognizerStateBegan || state == UIGestureRecognizerStateChanged;
}

- (void)held:(UILongPressGestureRecognizer *)hold {
    if (hold.state == UIGestureRecognizerStateBegan) {
        self.holding = YES;
        firstTabHeld(self);
    } else if (hold.state != UIGestureRecognizerStateChanged) {
        // The bar may still pick the tab as the finger lifts, after this.
        __weak typeof(self) weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            weakSelf.holding = NO;
        });
    }
}

@end

// The system bar's own view in Spotify's bar. UIKit measures the system bar and lays it out by the safe
// area of the view it stands in, and the room made under Spotify's bar is not the phone's: on a phone
// with a home button it went under the platter as well, squeezing it to 49 pt. So this view hands the
// bar the safe area without the room.
@interface SGRTabBarHost : UIView
@end

@implementation SGRTabBarHost
- (UIEdgeInsets)safeAreaInsets {
    UIEdgeInsets insets = [super safeAreaInsets];
    insets.bottom = MAX(0, insets.bottom - sg_room);
    return insets;
}
@end

@interface SGRFirstTabHold : UILongPressGestureRecognizer
@end

@implementation SGRFirstTabHold
+ (void)held:(SGRFirstTabHold *)hold {
    if (hold.state == UIGestureRecognizerStateBegan) firstTabHeld(hold.view);
}
@end

// On Spotify's own bar a hold that begins fails the item's tap recognizer, so the tab is not tapped too. It moves with
// the first tab when the tab editor changes which that is.
static void holdFirstTab(UIView *stockBar) {
    UIView *first = tabItems(stockBar).firstObject;
    BOOL held = NO;
    for (UIView *item in SGRowIn(stockBar).arrangedSubviews) {
        for (UIGestureRecognizer *recognizer in item.gestureRecognizers.copy) {
            if (![recognizer isKindOfClass:SGRFirstTabHold.class]) continue;
            if (item == first) held = YES;
            else [item removeGestureRecognizer:recognizer];
        }
    }
    if (!first || held) return;
    SGRFirstTabHold *hold = [[SGRFirstTabHold alloc] initWithTarget:SGRFirstTabHold.class action:@selector(held:)];
    hold.minimumPressDuration = kFirstTabHold;
    [first addGestureRecognizer:hold];
}

static void logBarOnce(UITabBar *bar) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            SGLogLong(@"navbar", [NSString stringWithFormat:@"system tab bar %@\n%@", NSStringFromCGRect(bar.superview.frame), [bar recursiveDescription]]);
        });
    });
}

#pragma mark - the fade under the bars

// The pages darken toward the bottom of the screen under the glass bar and the now playing bar, from clear
// a little above the now playing card to half black at the screen's foot, so a row going under the glass
// reads as passing behind it. Never darker than half: the glass still has the page to lens. The fade is the
// stock bar's own subview, behind the glass, so it slides away with the bar when a page hides it; Spotify's
// bar does not clip, or the glass bar would not have stood over the now playing bar before the room was made.
@interface SGRBarFade : UIView
@end

@implementation SGRBarFade
+ (Class)layerClass {
    return CAGradientLayer.class;
}
@end

// The now playing card (56), its gap over the bar (8) and 24 more, whether a song is playing or not; in a
// Jam the strip's height on top while the card is above the bar. In the minimized row the strip rides just
// above the card, which these 88 already reach.
static const CGFloat kFadeAbove = 88;

static void placeFade(UIView *stockBar, CGRect glass, BOOL minimized) {
    SGRBarFade *fade = objc_getAssociatedObject(stockBar, &kFadeKey);
    if (!fade) {
        fade = [SGRBarFade new];
        fade.userInteractionEnabled = NO;
        CAGradientLayer *layer = (CAGradientLayer *)fade.layer;
        // Eased rather than straight, so the fade has no edge where it starts.
        layer.colors = @[(id)[UIColor colorWithWhite:0 alpha:0].CGColor, (id)[UIColor colorWithWhite:0 alpha:0.3].CGColor,
                         (id)[UIColor colorWithWhite:0 alpha:0.5].CGColor];
        layer.locations = @[@0, @0.5, @1];
        objc_setAssociatedObject(stockBar, &kFadeKey, fade, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    CGFloat top = CGRectGetMinY(glass) - kFadeAbove - (minimized ? 0 : SGRNowPlayingStripHeight());
    CGRect frame = CGRectMake(0, top, stockBar.bounds.size.width, CGRectGetMaxY(glass) - top);
    if (!CGRectEqualToRect(fade.frame, frame)) fade.frame = frame;
    if (fade.superview != stockBar || stockBar.subviews.firstObject != fade) [stockBar insertSubview:fade atIndex:0];
}

#pragma mark - room for the glass bar

// UIKit's glass bar asks for 83 pt, the platter the top 62 of it, over no more safe area than a Face ID
// phone's 34 (simulator, iOS 26.5 and 27). Spotify's bar is its 49 pt row over the bottom safe area of
// TabBarContainerImpl's view: a guide from 49 pt above the safe area's bottom to the view's bottom sets
// its height (its viewDidLoad, 0x100840a2c), the now playing bar stands on that guide's top
// (MainUIContainer's chrome bottom anchor, 0x100ae0178), the bar slides away by the inset plus 49 when
// Spotify hides it (0x1037169a4) and the pages get 49 on top of the inset (0x10707bde4). A Face ID
// phone gives the view 34 and the two bars match. A phone with a home button gives it none, and so does
// Spotify's message bar (LimitedExperienceIndicatorBar: Offline, Private Session) coming in under the
// tab bar, which takes the home indicator's inset for itself: the glass bar stood 34 pt above
// Spotify's, over the now playing bar. So the view gets the rest of the glass bar's height as safe
// area, and Spotify lays its bar, the now playing bar, the pages and the hide out for the glass bar
// itself, and moves them all with the message bar.
static const CGFloat kStockRow = 49;

// UIKit asks for 62 + max(21, inset) on a phone with a home button, max(83, 49 + inset) on a Face ID
// phone, by the safe area of the view the bar stands in. SGRTabBarHost keeps the room out of that; if
// it ever reached the bar again, the bar would ask for more room every pass, so what it asks for with
// no room made is what is kept.
static CGFloat glassHeight(UITabBar *bar, UIView *stockBar) {
    if (sg_room < 0.5 || sg_glassHeight <= 0) sg_glassHeight = [bar sizeThatFits:CGSizeMake(stockBar.bounds.size.width, kStockRow)].height;
    return sg_glassHeight;
}

static UIViewController *containerOf(UIView *stockBar) {
    Class containerClass = NSClassFromString(@"_TtC23NavigationUI_TabBarImpl19TabBarContainerImpl");
    for (UIResponder *r = stockBar.nextResponder; r; r = r.nextResponder) {
        if ([r isKindOfClass:containerClass]) return (UIViewController *)r;
    }
    return nil;
}

static void makeRoom(UIViewController *container) {
    UIView *stockBar = sg_stockBar;
    UITabBar *bar = stockBar ? objc_getAssociatedObject(stockBar, &kBarKey) : nil;
    if (!bar.window || !container.isViewLoaded || ![stockBar isDescendantOfView:container.view]) return;
    UIEdgeInsets extra = container.additionalSafeAreaInsets;
    CGFloat inset = container.view.safeAreaInsets.bottom - extra.bottom;
    CGFloat height = glassHeight(bar, stockBar);
    // Spotify's regular width bar is a fixed 76 pt that ignores the inset.
    BOOL compact = container.traitCollection.horizontalSizeClass == UIUserInterfaceSizeClassCompact;
    CGFloat room = compact ? MAX(0, ceil(height - kStockRow - inset)) : 0;
    if (fabs(extra.bottom - room) < 0.5) return;
    sg_room = extra.bottom = room;
    container.additionalSafeAreaInsets = extra;
    SGLog(@"tab bar: %.0f pt of room made under Spotify's bar for the glass bar's %.0f, over an inset of %.0f", room, height, inset);
}

static SGRSystemTabBar *makeBar(UIView *stockBar) {
    SGRSystemTabBar *bar = [[SGRSystemTabBar alloc] initWithFrame:stockBar.bounds];
    // UIKit draws the glass in the appearance the bar inherits, and the bar is outside the navigation
    // stacks Spotify makes dark itself (-[SPNavigationController viewDidLoad] while +[SPTLiquidGlass
    // isEnabled]), so a phone in light mode had it light over Spotify's black. Spotify is dark whatever
    // the system is, and so is the bar.
    bar.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    bar.delegate = bar;
    bar.stockBar = stockBar;
    UILongPressGestureRecognizer *hold = [[UILongPressGestureRecognizer alloc] initWithTarget:bar action:@selector(held:)];
    hold.minimumPressDuration = kFirstTabHold;
    hold.delegate = bar;
    [bar addGestureRecognizer:hold];
    bar.hold = hold;
    // Whether a finger is on the row, which the lens follows rather than a tab while it is (placedCenter).
    UILongPressGestureRecognizer *finger = [[UILongPressGestureRecognizer alloc] initWithTarget:bar action:@selector(fingerMoved:)];
    finger.minimumPressDuration = 0;
    finger.allowableMovement = CGFLOAT_MAX;
    finger.cancelsTouchesInView = NO;
    finger.delaysTouchesBegan = NO;
    finger.delaysTouchesEnded = NO;
    finger.delegate = bar;
    [bar addGestureRecognizer:finger];
    return bar;
}

// One bar's share of the tabs: its items, their glyphs and titles. YES while a glyph is still missing.
static BOOL fillBar(SGRSystemTabBar *bar, NSArray<UIView *> *sources, BOOL hideLabels, BOOL lit) {
    bar.tintColor = SGRAccent();
    if (![sources isEqualToArray:bar.sources]) {
        NSMutableArray<UITabBarItem *> *items = [NSMutableArray array];
        for (UIView *source in sources) [items addObject:[[UITabBarItem alloc] initWithTitle:hideLabels ? nil : labelIn(source).text image:nil tag:items.count]];
        bar.sources = sources;
        [bar setItems:items animated:NO];
        // Logged the first few times only: built and written on every minimize and expand, it was part of their stall.
        static NSUInteger logged;
        if (logged++ < 4) {
            NSMutableString *out = [NSMutableString stringWithString:@"tab bar icons"];
            for (UIView *source in sources) {
                UIView *live = iconIn(source);
                id icon = live ? encoreIconOf(live) : nil;
                id variant = [icon respondsToSelector:NSSelectorFromString(@"active")] ? ((id (*)(id, SEL))objc_msgSend)(icon, NSSelectorFromString(@"active")) : nil;
                [out appendFormat:@"\n  %@: %@ icon %@ active-variant %@ live-isActive %d label-white %d", labelIn(source).text, NSStringFromClass(live.class),
                     [icon respondsToSelector:@selector(name)] ? [icon name] : icon, [variant respondsToSelector:@selector(name)] ? [variant name] : variant,
                     [live respondsToSelector:@selector(isActive)] ? [(SPTEncoreIconView *)live isActive] : -1, isActive(source)];
            }
            SGLogLong(@"navbar", out);
        }
    }

    BOOL missing = NO;
    for (NSUInteger i = 0; i < sources.count; i++) {
        UITabBarItem *item = bar.items[i];
        // Drawn again when it goes lit or unlit: the trailing circle keeps its item, lit while its tab is the page's. The
        // hollow and filled pictures are each tab's own (glyphOf), so a tab change sets nothing: set mid slide, they had
        // the lens stutter (its owner, 2026-10-26).
        static char kLitKey;
        if (!item.image || [objc_getAssociatedObject(item, &kLitKey) boolValue] != lit) {
            UIImage *image = lit ? [glyphOf(sources[i], YES) imageWithTintColor:SGRAccent() renderingMode:UIImageRenderingModeAlwaysOriginal]
                                 : glyphOf(sources[i], NO);
            if (image) {
                item.image = image;
                objc_setAssociatedObject(item, &kLitKey, @(lit), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
        }
        if (!item.selectedImage || item.selectedImage == item.image) item.selectedImage = glyphOf(sources[i], YES);
        missing |= !item.image || !item.selectedImage;
        item.accessibilityLabel = labelIn(sources[i]).text;
        item.largeContentSizeImage = item.image;
        NSString *title = hideLabels ? nil : labelIn(sources[i]).text;
        if (hideLabels ? item.title != nil : title.length && ![title isEqualToString:item.title]) item.title = title;
    }
    return missing;
}

// The bar holding the tab Spotify paints as selected selects it, and the other one lets go. With no tab
// painted (a tab of the mod's own, a repaint still to come) both keep what they have.
static void selectActive(SGRSystemTabBar *bar, UIView *active) {
    NSUInteger index = active ? [bar.sources indexOfObject:active] : NSNotFound;
    UITabBarItem *item = index == NSNotFound ? nil : bar.items[index];
    if (active && bar.selectedItem != item) bar.selectedItem = item;
    if (active && item) bar.shown = item;
}

// The item a bar holds for the tab the page is on, as shown without selecting it; none when the page is on another
// bar's tab, and left as it is when Spotify paints no tab.
static void noteShown(SGRSystemTabBar *bar, UIView *active) {
    if (!active) return;
    NSUInteger index = [bar.sources indexOfObject:active];
    UITabBarItem *item = index == NSNotFound || index >= bar.items.count ? nil : bar.items[index];
    if (bar.shown != item) bar.shown = item;
}

// The tab a bar shows selected, when Spotify paints none: a tab of the mod's own.
static UIView *selectedSource(SGRSystemTabBar *bar) {
    NSUInteger index = bar.selectedItem ? [bar.items indexOfObject:bar.selectedItem] : NSNotFound;
    return index < bar.sources.count ? bar.sources[index] : nil;
}

// Minimized, the row's last tab stands on a glass circle of its own at the trailing end, the way the Music app keeps
// Search. A standalone UITabBar has no way to set an item apart (iOS 27 SDK: only UITabBarController's UISearchTab
// does), so it is a second bar. UIKit draws each bar's platter 21 pt in from its sides (harness/tabbar, iPhone 17 Pro,
// iOS 27: a 72 pt bar got a 30 pt platter at x 21), so a circle's bar is a 62 pt platter, as tall as the bar's, plus
// those insets, and the card keeps 12 pt of glassless gap from each circle.
static const CGFloat kPlatterInset = 21, kCircleWidth = 62, kPlatterGap = 12;

static UIView *platterOf(UIView *bar) {
    __block UIView *platter = nil;
    SGForEachView(bar, ^(UIView *v) {
        if (!platter && [NSStringFromClass(v.class) hasSuffix:@"PlatterView"]) platter = v;
    });
    return platter;
}

// UIKit gives a standalone bar's items a width of their own, some 100 pt at most, and centers the platter round
// them: with three tabs the platter was 293 pt of a 440 pt bar (the phone's log), where the Music app's runs the
// width of the screen, 21 pt in from each side, as the card above it does (SGRTabBarFullSlot). Neither Fill nor
// Centered with a wider itemWidth widens it (Centered at 130 pt made it 227 pt), so after UIKit's own pass the
// platter is given the bar's width. UIKit keeps laying the tabs and the selection's lens out on its own narrower
// platter, in passes of the platter's rows that a tab change runs without this one: set here once, the tabs went back
// to UIKit's places, bunched at the leading end, on the next tab picked (screen recordings, 2026-10-26). So every place
// UIKit gives a tab button or the lens in a widened platter is stretched from its platter's width to the bar's, the
// same mapping for both, so the lens still lands on its tab and slides between them as UIKit moves it. Minimized, a
// circle keeps UIKit's own width.
static const CGFloat kTabInset = 4;
static char kNaturalKey;

// How far a frame UIKit gives a view of a widened platter is stretched, from the platter UIKit laid out to the one it
// has; 1 for any other view. `platterOut` is the platter.
// Whether any bar has had its platter widened: until one has, the hooks below have nothing to do. They run for every
// tab button and lens in the app, and iOS 26 lenses a slider's thumb too, so a volume drag ran them every frame.
static BOOL sg_anyWidened;

static CGFloat stretchFor(UIView *view, UIView **platterOut) {
    if (sg_minimized || !sg_anyWidened) return 1;
    UIView *platter = nil;
    SGRSystemTabBar *bar = nil;
    NSUInteger depth = 0;
    for (UIView *up = view.superview; up && depth < 6; up = up.superview, depth++) {
        if (!platter && [NSStringFromClass(up.class) hasSuffix:@"PlatterView"]) platter = up;
        if ([up isKindOfClass:SGRSystemTabBar.class]) {
            bar = (SGRSystemTabBar *)up;
            break;
        }
    }
    if (!bar || !platter || bar.items.count < 2) return 1;
    CGFloat natural = [objc_getAssociatedObject(bar, &kNaturalKey) doubleValue];
    CGFloat room = bar.bounds.size.width - 2 * kPlatterInset;
    if (natural <= 2 * kTabInset + 1 || room <= natural) return 1;
    if (platterOut) *platterOut = platter;
    return (room - 2 * kTabInset) / (natural - 2 * kTabInset);
}

// The center to set on a tab button or the lens for the one UIKit asks for: stretched, unless it is one this file has
// already stretched for the same bar. UIKit sets a center again from one it reads back, and puts the lens on the center
// it reads off the selected tab, which is a stretched one: stretched again, the lens stood a tab's width past its tab
// (105 pt for Home's 73, the phone's log, 2026-10-26). The lens is kept on the row whatever it is given.
static char kPlacedKey, kPlacedWidthKey;

// Whether `value` is one this file set for the platter under `key`; if not, it is noted as set once stretched.
static NSMutableArray<NSNumber *> *placedList(UIView *platter, const void *key) {
    NSMutableArray<NSNumber *> *placed = objc_getAssociatedObject(platter, key);
    if (!placed) {
        placed = [NSMutableArray array];
        objc_setAssociatedObject(platter, key, placed, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return placed;
}

static char kSlotsKey;

static CGPoint placedCenter(UIView *view, CGPoint center) {
    UIView *platter = nil;
    CGFloat stretch = stretchFor(view, &platter);
    if (stretch == 1) return center;
    NSMutableArray<NSNumber *> *placed = placedList(platter, &kPlacedKey);
    for (NSNumber *x in placed) if (fabs(x.doubleValue - center.x) < 0.5) return center;
    // UIKit's own slots are the centers it gives the tabs. UIKit moves the lens between them a frame at a time on its own
    // narrow row, so those steps are stretched too: left alone the lens jumped back towards UIKit's places mid-slide (a
    // screen recording, 2026-10-26). Under a finger it is where the finger is, which is on the widened row already, so
    // then only a tab's own slot is stretched: stretched again it ran ahead of the finger (211 set as 287, the log).
    NSMutableArray<NSNumber *> *slots = placedList(platter, &kSlotsKey);
    if ([view isKindOfClass:%c(_UITabButton)]) {
        BOOL known = NO;
        for (NSNumber *x in slots) if (fabs(x.doubleValue - center.x) < 0.5) known = YES;
        if (!known) {
            [slots addObject:@(center.x)];
            if (slots.count > 12) [slots removeObjectAtIndex:0];
        }
    } else {
        BOOL slot = NO;
        for (NSNumber *x in slots) if (fabs(x.doubleValue - center.x) < 0.5) slot = YES;
        if (!slot && sg_fingerOnBar) return center;
    }
    center.x = kTabInset + (center.x - kTabInset) * stretch;
    CGFloat half = view.bounds.size.width / 2;
    CGFloat width = platter.bounds.size.width;
    if (half > 0 && width > 2 * (kTabInset + half)) center.x = MIN(MAX(center.x, kTabInset + half), width - kTabInset - half);
    [placed addObject:@(center.x)];
    if (placed.count > 24) [placed removeObjectAtIndex:0];
    return center;
}

// The width to give a tab button or the lens: stretched once, as their centers are, so the lens fills its tab's share of
// the row as the Music app's does (138 pt of a three tab row, its owner's recording, 2026-10-26), and a tab takes its
// whole share for touches. A width this file set, read back and set again, is left as it is.
static char kSlotWidthKey, kSlotHeightKey;
// How much of UIKit's growth of the lens on the move is kept, across and up (see placedBounds).
// Measured against the Music app's side by side (2026-10-26): at rest 134 pt to our 137, pressed 156 to our 162, sliding
// 165 to our 177 with 0.63 kept; so 3 pt off at rest and half the growth.
static const CGFloat kLensGrowth = 0.5, kLensRise = 0.57, kLensTrim = 3;

static CGRect placedBounds(UIView *view, CGRect bounds) {
    UIView *platter = nil;
    CGFloat stretch = stretchFor(view, &platter);
    if (stretch == 1) return bounds;
    NSMutableArray<NSNumber *> *placed = placedList(platter, &kPlacedWidthKey);
    for (NSNumber *w in placed) if (fabs(w.doubleValue - bounds.size.width) < 0.5) return bounds;
    CGFloat width = bounds.size.width;
    if ([view isKindOfClass:%c(_UITabButton)]) {
        objc_setAssociatedObject(platter, &kSlotWidthKey, @(width), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(platter, &kSlotHeightKey, @(bounds.size.height), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        width *= stretch;
    } else {
        // The lens grows past a tab's size while it slides and under a finger, by half its width and a quarter of its
        // height on UIKit's narrow row, where the Music app's grows by under a quarter: 134 by 54 pt at rest to 165 by 62
        // on the move (its owner's recordings at 60 fps, 2026-10-26), ours to 186 by 68. The slot's stretch is added to
        // it, not multiplied in (multiplied, it ran over two tabs), and its growth is kept to the Music app's share.
        CGFloat slot = [objc_getAssociatedObject(platter, &kSlotWidthKey) doubleValue] ?: width;
        CGFloat slotHeight = [objc_getAssociatedObject(platter, &kSlotHeightKey) doubleValue];
        width = slot * stretch - kLensTrim + MAX(0, width - slot) * kLensGrowth;
        if (slotHeight > 0 && bounds.size.height > slotHeight) bounds.size.height = slotHeight + (bounds.size.height - slotHeight) * kLensRise;
    }
    bounds.size.width = MIN(width, platter.bounds.size.width - 2 * kTabInset);
    [placed addObject:@(bounds.size.width)];
    if (placed.count > 24) [placed removeObjectAtIndex:0];
    return bounds;
}

static void widenPlatter(UITabBar *bar) {
    NSUInteger count = bar.items.count;
    // The lens shows only on the full row: on a minimized circle, where nothing is selected, it stood as a dark blob at
    // the circle's edge, left where the stretched row had it (a screen recording, 2026-10-26).
    for (UIView *pane in platterOf(bar).subviews) {
        if (![NSStringFromClass(pane.class) containsString:@"LiquidLens"]) continue;
        CGFloat shown = sg_minimized ? 0 : 1;
        if (pane.alpha != shown) pane.alpha = shown;
        // Held hidden on the circles (the lens's hooks), it is shown again with the full row.
        if (!sg_minimized && pane.hidden) pane.hidden = NO;
    }
    UIView *platter = count >= 2 ? platterOf(bar) : nil;
    CGFloat room = bar.bounds.size.width - 2 * kPlatterInset;
    if (!platter || room < 100 || sg_minimized) return;
    CGRect frame = platter.frame;
    if (fabs(frame.size.width - room) <= 0.5 && fabs(frame.origin.x - kPlatterInset) <= 0.5) return;
    // The width UIKit just gave it, which its rows are laid out to.
    objc_setAssociatedObject(bar, &kNaturalKey, @(frame.size.width), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    sg_anyWidened = YES;
    objc_setAssociatedObject(platter, &kPlacedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(platter, &kPlacedWidthKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(platter, &kSlotsKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(platter, &kSlotWidthKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    frame.origin.x = kPlatterInset;
    frame.size.width = room;
    platter.frame = frame;
    // UIKit's rows and lens laid out again now, through the stretch in their hooks.
    for (UIView *pane in platter.subviews) [pane setNeedsLayout];
    [platter setNeedsLayout];
    [platter layoutIfNeeded];
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableString *panes = [NSMutableString string];
        for (UIView *pane in platter.subviews) {
            [panes appendFormat:@"\n  %@ %@:", NSStringFromClass(pane.class), NSStringFromCGRect(pane.frame)];
            for (UIView *v in pane.subviews) if (isTabButton(v)) [panes appendFormat:@" %@", NSStringFromCGRect(v.frame)];
        }
        SGLogLong(@"navbar", [NSString stringWithFormat:@"tab bar: platter widened from %.0f to %.0f pt for %lu tabs%@",
                              [objc_getAssociatedObject(bar, &kNaturalKey) doubleValue], room, (unsigned long)count, panes]);
    });
}

// UIKit's own item widths throughout: the platter is widened after its pass instead (widenPlatter).
static void fillPlatter(SGRSystemTabBar *bar, BOOL circle) {
    if (bar.itemPositioning != UITabBarItemPositioningAutomatic) bar.itemPositioning = UITabBarItemPositioningAutomatic;
    if (bar.itemWidth != 0) bar.itemWidth = 0;
}

// The minimized bar's circles are as tall as its card, 48 pt, as the Music app's are, where UIKit draws a bar's
// platter 62 pt high whatever is in it. Each bar draws its contents smaller round the circle's center, which stays
// put, by a transform on its sublayers: its own frame, which the moves and the card's slot read, is untouched.
static const CGFloat kRowCircle = 48;

// A circle under a finger, drawn a little larger: UIKit's own press lifts its lens outside the circle's shrink, a second
// disc of the bar's full 62 pt off the 48 pt circle (its owner's recordings, 2026-10-27), so the lens stays hidden on the
// circles and the press is drawn on the circle itself, once and at its size.
static char kPressedKey;
static const CGFloat kCirclePress = 1.12;

static CATransform3D circleTransform(UIView *bar, BOOL circle) {
    if (!circle) return CATransform3DIdentity;
    CGPoint center = CGPointMake(kPlatterInset + kCircleWidth / 2, kCircleWidth / 2);
    CGPoint off = CGPointMake(center.x - CGRectGetMidX(bar.bounds), center.y - CGRectGetMidY(bar.bounds));
    CGFloat scale = kRowCircle / kCircleWidth * ([objc_getAssociatedObject(bar, &kPressedKey) boolValue] ? kCirclePress : 1);
    CATransform3D transform = CATransform3DMakeTranslation(off.x, off.y, 0);
    transform = CATransform3DScale(transform, scale, scale, 1);
    return CATransform3DTranslate(transform, -off.x, -off.y, 0);
}

static void shrinkCircle(UIView *bar, BOOL circle) {
    if (!bar) return;
    CATransform3D transform = circleTransform(bar, circle);
    if (CATransform3DEqualToTransform(bar.layer.sublayerTransform, transform)) return;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    bar.layer.sublayerTransform = transform;
    [CATransaction commit];
}

static char kPressTokenKey;

static void pressCircle(UIView *bar, BOOL down) {
    if (!bar || [objc_getAssociatedObject(bar, &kPressedKey) boolValue] == down) return;
    objc_setAssociatedObject(bar, &kPressedKey, down ? @YES : nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    // UIKit lowers a lens it was let lift, and this one never lifted, so it does not always ask again on the finger's way
    // up: the circle stayed at its pressed size after the tap (its owner's recording, 2026-10-27). It settles back on its
    // own, once the finger has had time to lift, if nothing has lowered it first.
    if (down) {
        id token = [NSObject new];
        objc_setAssociatedObject(bar, &kPressTokenKey, token, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        __weak UIView *weakBar = bar;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.45 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            UIView *strongBar = weakBar;
            if (strongBar && objc_getAssociatedObject(strongBar, &kPressTokenKey) == token) pressCircle(strongBar, NO);
        });
    }
    // Let go after the bar grew back: the row keeps its own transform.
    if (!sg_minimized) return;
    CALayer *layer = bar.layer;
    CATransform3D from = (layer.presentationLayer ?: layer).sublayerTransform, to = circleTransform(bar, YES);
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    layer.sublayerTransform = to;
    [CATransaction commit];
    if (SGRReduceMotion()) return;
    if (@available(iOS 17.0, *)) {
        CASpringAnimation *spring = [[CASpringAnimation alloc] initWithPerceptualDuration:0.3 bounce:down ? 0.25 : 0.35];
        spring.keyPath = @"sublayerTransform";
        spring.fromValue = [NSValue valueWithCATransform3D:from];
        spring.duration = spring.settlingDuration;
        [layer addAnimation:spring forKey:@"sgr.press"];
    }
}

static void syncBar(UIView *stockBar) {
    sg_stockBar = stockBar;

    SGRSystemTabBar *bar = objc_getAssociatedObject(stockBar, &kBarKey);
    if (!bar) {
        bar = makeBar(stockBar);
        objc_setAssociatedObject(stockBar, &kBarKey, bar, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        SGRTabBarHost *host = [SGRTabBarHost new];
        [host addSubview:bar];
        objc_setAssociatedObject(stockBar, &kHostKey, host, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    UIView *host = objc_getAssociatedObject(stockBar, &kHostKey);

    for (UIView *sub in stockBar.subviews) {
        if (sub == host || [sub isKindOfClass:SGRBarFade.class]) continue;
        sub.alpha = 0;
        sub.userInteractionEnabled = NO;
    }
    stockBar.superview.layer.backgroundColor = NULL;

    NSArray<UIView *> *sources = tabItems(stockBar);
    if (!sources.count) return;
    // An item with no title is drawn by UIKit as its glyph alone, centered, on a bar of the same height.
    BOOL hideLabels = SGHidden(SGRKeyNavbarHideLabels);
    SGRSystemTabBar *trailBar = objc_getAssociatedObject(stockBar, &kTrailBarKey);
    UIView *active = SGRNavbarLitTab();
    if (![sources containsObject:active]) active = nil;
    for (UIView *source in sources) if (!active && isActive(source)) active = source;
    active = active ?: selectedSource(bar) ?: selectedSource(trailBar);
    UIView *pending = sg_pendingActive;
    if (pending && CACurrentMediaTime() < sg_pendingUntil && [sources containsObject:pending]) active = pending;

    // Minimized, the bar keeps the tab it is on, glyph only, on a circle at the leading end, and the row's last tab on
    // one at the trailing end, the way the Music app keeps Search, sliding out of the row to it as the card comes down
    // between the two (its owner asked for the last tab, 2026-10-25). On the last tab, the leading circle has the first.
    BOOL minimized = sg_minimized && sources.count >= 2;

    // Spotify lays its bar out far more often than anything on it changes, and each pass re-laid and re-filled both glass
    // bars. What the pass below reads is kept, and when none of it changed since a pass that drew everything, only the
    // glass is kept in front and the room under it made.
    static NSArray<UIView *> *lastSources;
    static __weak UIView *lastActive;
    static __weak id lastItems, lastSelected, lastTrailItems;
    static NSString *lastLabels;
    static UIColor *lastAccent;
    static CGRect lastBounds;
    static CGFloat lastSafe, lastRoom;
    static BOOL lastMinimized, lastHide, lastLeaving, lastInWindow, lastMissing = YES;
    NSMutableString *labels = [NSMutableString string];
    for (UIView *source in sources) [labels appendFormat:@"%@\n", labelIn(source).text ?: @""];
    UIColor *accent = SGRAccent();
    BOOL same = !lastMissing && [sources isEqualToArray:lastSources] && active == lastActive && minimized == lastMinimized
        && hideLabels == lastHide && sg_trailLeaving == lastLeaving && (stockBar.window != nil) == lastInWindow
        && CGRectEqualToRect(stockBar.bounds, lastBounds) && stockBar.safeAreaInsets.bottom == lastSafe && sg_room == lastRoom
        && bar.sources == lastItems && bar.selectedItem == lastSelected && trailBar.sources == lastTrailItems
        && [labels isEqualToString:lastLabels] && [accent isEqual:lastAccent];
    static NSUInteger runs, skips;
    runs++;
    if (same) {
        skips++;
        if (runs % 200 == 0 && runs <= 2000) SGLog(@"tab bar: %lu of %lu passes found nothing changed", (unsigned long)skips, (unsigned long)runs);
        if (host.superview != stockBar) [stockBar addSubview:host];
        else if (stockBar.subviews.lastObject != host) [stockBar bringSubviewToFront:host];
        makeRoom(containerOf(stockBar));
        return;
    }
    NSArray<UIView *> *main = sources, *trail = @[];
    if (minimized) {
        UIView *last = sources.lastObject;
        main = @[active && active != last ? active : sources.firstObject];
        trail = @[last];
        hideLabels = YES;
    }
    if (trail.count && !trailBar) {
        trailBar = makeBar(stockBar);
        objc_setAssociatedObject(stockBar, &kTrailBarKey, trailBar, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        trailBar.partner = bar;
        bar.partner = trailBar;
        [host addSubview:trailBar];
    }
    // The circle keeps its item while hidden: made again each time it came, its glyph was missing for the circle's
    // first frames, an empty disc beside the row (a recording at 30 fps, 2026-10-24).
    trailBar.hidden = !trail.count && !sg_trailLeaving;

    CGRect bounds = stockBar.bounds;
    CGFloat width = bounds.size.width;
    CGFloat height = MAX(bounds.size.height, glassHeight(bar, stockBar));
    CGRect frame = CGRectMake(0, CGRectGetMaxY(bounds) - height, width, height);
    if (!CGRectEqualToRect(host.frame, frame)) host.frame = frame;
    placeFade(stockBar, frame, minimized);
    CGRect mainFrame = host.bounds;
    if (minimized) {
        CGFloat side = kCircleWidth + 2 * kPlatterInset;
        mainFrame.size.width = side;
        CGRect trailFrame = CGRectMake(width - side, 0, side, height);
        if (!CGRectEqualToRect(trailBar.frame, trailFrame)) trailBar.frame = trailFrame;
    }
    if (!CGRectEqualToRect(bar.frame, mainFrame)) bar.frame = mainFrame;

    // The items go in once the bars are laid out at their frames. UIKit sizes an item's title by the platter it
    // is made in and never again when the bar grows, so items made while a bar was still a circle kept "…" for
    // their names at full width (harness/tabbar, `names`).
    [host layoutIfNeeded];
    // Minimized, each circle is lit when it holds the tab the page is on.
    BOOL missing = fillBar(bar, main, hideLabels, minimized && (!active || main.firstObject == active));
    fillPlatter(bar, minimized);
    if (trail.count) missing |= fillBar(trailBar, trail, hideLabels, active && trail.firstObject == active);
    // The minimized bar's circles hold their tabs, the one it is on lit, with no bubble round it: the Music app's
    // circle is its glass and the glyph. Selected, UIKit drew its bubble inside the circle, a dark disc in a ring.
    // Each still keeps the item it is on as shown, so a tap on a lit circle is told from one that changes the tab.
    if (minimized) {
        if (bar.selectedItem) bar.selectedItem = nil;
        if (trailBar.selectedItem) trailBar.selectedItem = nil;
        noteShown(bar, active);
        noteShown(trailBar, active);
    } else {
        selectActive(bar, active);
    }
    shrinkCircle(bar, minimized);
    // The trailing bar is only ever a circle: grown back to a bar's platter, it swelled to a ringed disc beside the
    // row as it went back in (a recording at 30 fps, 2026-10-24).
    shrinkCircle(trailBar, YES);
    lastSources = sources;
    lastActive = active;
    lastMinimized = minimized;
    lastHide = SGHidden(SGRKeyNavbarHideLabels);
    lastLeaving = sg_trailLeaving;
    lastInWindow = stockBar.window != nil;
    lastBounds = stockBar.bounds;
    lastSafe = stockBar.safeAreaInsets.bottom;
    lastRoom = sg_room;
    lastItems = bar.sources;
    lastSelected = bar.selectedItem;
    lastTrailItems = trailBar.sources;
    lastLabels = labels;
    lastAccent = accent;
    lastMissing = missing;
    // An icon view Spotify has not built yet is looked for again shortly, not on the next touch.
    static NSUInteger retries;
    if (missing && retries++ < 40) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            syncBar(stockBar);
        });
    }
    if (host.superview != stockBar) [stockBar addSubview:host];
    else if (stockBar.subviews.lastObject != host) [stockBar bringSubviewToFront:host];
    logBarOnce(bar);
    makeRoom(containerOf(stockBar));
}

#pragma mark - minimized

// A page scrolled down minimizes the bar (TabBarMinimize.x), the way the Music app's does. Spotify's tab bar
// container is a UIViewController of its own, not a UITabBarController (the binary's ObjC metadata), so
// UIKit's tabBarMinimizeBehavior and bottomAccessory have nothing to act on. The minimized bar is built
// from the two bars this file already has: the main bar narrowed to one circle at the leading end, the
// second bar to one at the trailing end, and the now playing card between them (NowPlayingBar.x). The
// bars get their new items and are laid out where they are going at once; then every view of theirs goes back
// to where it was and moves on one spring with the card (see "one move"); nothing fades a bar's glass.
BOOL SGRTabBarMinimized(void) {
    return sg_minimized;
}

static void setMinimized(BOOL minimized, BOOL animated);

// The scroll asks from inside -[UIScrollView setContentOffset:], which Spotify can call inside an animation of
// its own: a block, whose length the spring then took, or a property animator held part way, which kept the bar's
// and the card's moves at its fraction for good, the circle stopped half way along the row and the card half way
// down to it (harness/tabbar, `nested`). So an animated change asked for inside an animation is made on the main
// queue's next turn, outside it, and only if nothing was asked for since; one asked for outside any is made at
// once. A change with no animation stays at once too: the player's transition takes its pictures of the bars
// right after asking.
static NSUInteger sg_request;

void SGRSetTabBarMinimized(BOOL minimized, BOOL animated) {
    NSUInteger request = ++sg_request;
    if (!animated) {
        [UIView performWithoutAnimation:^{ setMinimized(minimized, NO); }];
        return;
    }
    if (UIView.areAnimationsEnabled && UIView.inheritedAnimationDuration <= 0) {
        setMinimized(minimized, YES);
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        if (request == sg_request) setMinimized(minimized, YES);
    });
}

#pragma mark - one move

// The bars, the circles and the card move as one: on one spring (SGRMotionBar), from what is on screen. UIKit
// lays a bar's items out by its width, so a bar laid out where it was with its new items put them where they
// never were: minimizing, the circle's tab stood in the middle of the old full bar and slid to the leading end
// from there (harness/tabbar, `motion`: 124 pt in one frame). So each bar is laid out where it is going, and
// every view of the bars that was already there goes back to its frame from before, under its animations still
// running, and moves to its new one in the spring. UIView's animations add up, so a change that turns one back
// carries on from where the screen is, at the speed it had. UIKit takes the animations off its platters when it
// lays new items out, though, and a platter turned back half way then started from the old move's end, 62 pt from
// where it was shown (`motion`, four quick turns); one whose move was taken off starts from what was shown. The
// selected tab's new button starts with its glyph where the old one's was; the other new buttons fade in, and the
// buttons that went fade out from where they were.
typedef struct {
    NSMapTable<UIView *, NSArray<NSValue *> *> *frames; // every view of the host: its frame, the frame shown, moving
    NSMutableDictionary<NSString *, NSValue *> *glyphs; // each tab's glyph center in the host, by its keys (tabKeys)
    NSMapTable<UIView *, UIView *> *buttons;            // each tab button, a picture of it
    NSMapTable<UIView *, NSArray<NSString *> *> *keys;  // each tab button, its keys
} SGRBarState;

// How the tabs follow the glass's edge (moveFrom): the longest wait before a tab fades, for the one furthest
// from the leading end, and how long the fade takes. The platter covers most of its way in some 0.15 s.
static const NSTimeInterval kArriveSweep = 0.15, kArriveFade = 0.15, kLeaveSweep = 0.08, kLeaveFade = 0.1;
// How far the card trails the bars into a minimize, and the bars trail the card out of it (setMinimized).
// The Music app's card sets off some 0.09 s after its bar on a minimize (a recording at 50 fps, 2026-10-26); 0.07 by its
// owner's pick.
static const NSTimeInterval kCardLag = 0.07, kBarLag = 0.03;
// When the trailing circle fades into the growing row, and over how long.
static const NSTimeInterval kMergeDelay = 0.03, kMergeFade = 0.12;

// UIKit draws every tab twice, the second time in the accent under the selection's bubble only.
static BOOL isLitCopy(UIView *view, UIView *host) {
    for (UIView *up = view.superview; up && up != host; up = up.superview) {
        if ([NSStringFromClass(up.class) containsString:@"SelectedContent"]) return YES;
    }
    return NO;
}

static BOOL isMoving(UIView *view) {
    for (NSString *key in view.layer.animationKeys) if ([key hasPrefix:@"position"] || [key hasPrefix:@"bounds"]) return YES;
    return NO;
}

static UIImageView *glyphView(UIView *button) {
    __block UIImageView *glyph = nil;
    SGForEachView(button, ^(UIView *v) {
        if (!glyph && [v isKindOfClass:UIImageView.class] && !v.hidden && ((UIImageView *)v).image) glyph = (UIImageView *)v;
    });
    return glyph;
}

static BOOL isTabButton(UIView *view) {
    return [view isKindOfClass:UIControl.class] && glyphView(view) != nil;
}

// A glyph's shape: its alpha on a 16 pt grid, the same for the same icon whatever its color or UIImage copy.
static NSString *glyphShape(UIView *button) {
    // Kept per picture: UIKit hands the same image to a tab's buttons from one move to the next while its items stay,
    // and each was drawn at 16 by 16 at every move.
    static NSMapTable<id, NSString *> *shapes;
    if (!shapes) shapes = [NSMapTable mapTableWithKeyOptions:NSPointerFunctionsWeakMemory | NSPointerFunctionsObjectPointerPersonality valueOptions:NSPointerFunctionsStrongMemory];
    UIImage *picture = glyphView(button).image;
    NSString *known = picture ? [shapes objectForKey:picture] : nil;
    if (known) return known;
    CGImageRef image = picture.CGImage;
    if (!image) return nil;
    enum { kSide = 16 };
    uint8_t alpha[kSide * kSide] = {0};
    CGContextRef context = CGBitmapContextCreate(alpha, kSide, kSide, 8, kSide, NULL, (CGBitmapInfo)kCGImageAlphaOnly);
    CGContextDrawImage(context, CGRectMake(0, 0, kSide, kSide), image);
    CGContextRelease(context);
    uint64_t hash = 1469598103934665603ULL;
    for (int i = 0; i < kSide * kSide; i++) hash = (hash ^ (alpha[i] > 127)) * 1099511628211ULL;
    NSString *shape = [NSString stringWithFormat:@"%llx", hash];
    [shapes setObject:shape forKey:picture];
    return shape;
}

// Which old button a new one takes over from, in each of the two copies. A tab that stays slides from where its
// glyph was, the way the Music app's Library tab slides into the circle, and only a tab that comes or goes fades.
// UIKit draws its glyphs anew with each set of items (each copy a UIImage of its own) and its buttons carry no
// name, so a tab is told by its glyph's shape (the minimized circle's glyph is the selected tab's, lit, the same
// shape). Matched by selection or by name, the tabs on the phone faded out and back in at every move (screen
// recordings at 60 fps): two Home icons at once, and Home and Search blank for a fifth of a second.
static NSArray<NSString *> *tabKeys(UIView *button, UIView *host) {
    if (!isTabButton(button)) return @[];
    NSString *copy = isLitCopy(button, host) ? @"lit" : @"plain";
    NSMutableArray<NSString *> *keys = [NSMutableArray array];
    NSString *shape = glyphShape(button);
    if (shape) [keys addObject:[copy stringByAppendingFormat:@" %@", shape]];
    if (((UIControl *)button).selected) [keys addObject:copy];
    return keys;
}

// A picture of a tab button to fade out once UIKit has taken the button away. A snapshot of a view inside the
// glass came back empty on the phone (a screen recording at 60 fps: the leaving tabs went in one frame), so the
// button's own layers are drawn; their glyph and title need no glass to show.
static UIView *pictureOf(UIView *button) {
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:button.bounds.size];
    UIImage *image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [button.layer renderInContext:context.CGContext];
    }];
    return hasInk(image) ? [[UIImageView alloc] initWithImage:image] : [button snapshotViewAfterScreenUpdates:NO];
}

static CGRect shownIn(UIView *view, UIView *host) {
    CALayer *layer = view.layer.presentationLayer ?: view.layer, *top = host.layer.presentationLayer ?: host.layer;
    return [layer convertRect:layer.bounds toLayer:top];
}

static SGRBarState barState(UIView *host, BOOL pictured) {
    SGRBarState state = {
        [NSMapTable mapTableWithKeyOptions:NSPointerFunctionsWeakMemory | NSPointerFunctionsObjectPointerPersonality valueOptions:NSPointerFunctionsStrongMemory],
        [NSMutableDictionary dictionary],
        [NSMapTable mapTableWithKeyOptions:NSPointerFunctionsWeakMemory | NSPointerFunctionsObjectPointerPersonality valueOptions:NSPointerFunctionsStrongMemory],
        [NSMapTable mapTableWithKeyOptions:NSPointerFunctionsWeakMemory | NSPointerFunctionsObjectPointerPersonality valueOptions:NSPointerFunctionsStrongMemory],
    };
    SGForEachView(host, ^(UIView *v) {
        CALayer *shownLayer = v.layer.presentationLayer;
        [state.frames setObject:@[[NSValue valueWithCGRect:v.frame], [NSValue valueWithCGRect:shownLayer ? shownLayer.frame : v.frame], @(isMoving(v))] forKey:v];
        if (!v.window || v == host || !isTabButton(v)) return;
        CGRect shown = shownIn(v, host), glyph = shownIn(glyphView(v), host);
        NSArray<NSString *> *keys = tabKeys(v, host);
        for (NSString *key in keys) state.glyphs[key] = [NSValue valueWithCGPoint:CGPointMake(CGRectGetMidX(glyph), CGRectGetMidY(glyph))];
        [state.keys setObject:keys forKey:v];
        // The lit copy is left out, or its picture would show the tab lit outside the bubble. Pictured now, while it is
        // whole: pictured once it went, UIKit had already squeezed it into the circle, a gray block fading out (a screen
        // recording, 2026-10-26). Only a minimize has tabs that go, so an expand pictures none.
        if (!pictured || isLitCopy(v, host)) return;
        UIView *picture = pictureOf(v);
        if (picture) {
            picture.frame = shown;
            [state.buttons setObject:picture forKey:v];
        }
    });
    return state;
}

// Moves the host's views from `before` to where they are now, with `along` (the card) on the same spring. The card
// sets off `alongDelay` after the bars, or the bars `barDelay` after the card (see setMinimized).
static void moveFrom(UIView *host, SGRBarState before, void (^along)(void), NSTimeInterval alongDelay, NSTimeInterval barDelay,
                     void (^completion)(BOOL)) {
    NSMutableArray<UIView *> *moved = [NSMutableArray array], *faded = [NSMutableArray array];
    NSMutableArray<NSValue *> *starts = [NSMutableArray array], *targets = [NSMutableArray array];
    NSMutableSet<NSString *> *taken = [NSMutableSet set];
    SGForEachView(host, ^(UIView *v) {
        if (v == host) return;
        NSArray<NSValue *> *old = [before.frames objectForKey:v];
        if (old) {
            BOOL stopped = [(NSNumber *)old[2] boolValue] && !isMoving(v);
            CGRect start = stopped ? old[1].CGRectValue : old[0].CGRectValue;
            if (!stopped && CGRectEqualToRect(start, v.frame)) return;
            [moved addObject:v];
            [starts addObject:[NSValue valueWithCGRect:start]];
            [targets addObject:[NSValue valueWithCGRect:v.frame]];
            return;
        }
        // A view made for the new items, whose superview was there before. A tab that was on the bar starts where
        // its old glyph was, a new one fades in where it is going; the rest (the selection's bubble) are there
        // at once, or the selected tab's glyph, drawn under the bubble, went with it.
        if (![before.frames objectForKey:v.superview] || [v isKindOfClass:UITabBar.class]) return;
        NSString *key = nil;
        for (NSString *candidate in tabKeys(v, host)) if (!key && before.glyphs[candidate] && ![taken containsObject:candidate]) key = candidate;
        if (key) {
            [moved addObject:v];
            [starts addObject:before.glyphs[key]];   // a center in the host, placed once the views above it are back
            [targets addObject:[NSValue valueWithCGRect:v.frame]];
            [taken addObject:key];
        } else if (isTabButton(v) && v.alpha > 0.01) {
            [faded addObject:v];
        }
    });
    NSMutableArray<UIView *> *gone = [NSMutableArray array];
    for (UIView *button in before.buttons) {
        BOOL replaced = NO;
        for (NSString *key in [before.keys objectForKey:button]) replaced |= [taken containsObject:key];
        if (!button.window && !replaced) [gone addObject:[before.buttons objectForKey:button]];
    }

    [UIView performWithoutAnimation:^{
        // Top down, so a button's center is placed in its platter where the platter starts.
        for (NSUInteger i = 0; i < moved.count; i++) {
            UIView *v = moved[i];
            if (strcmp(starts[i].objCType, @encode(CGPoint)) != 0) {
                v.frame = starts[i].CGRectValue;
                continue;
            }
            // Its glyph where the old one's was: the button moved by as much as its glyph is off its center.
            UIImageView *glyph = glyphView(v);
            CGPoint inButton = [v convertPoint:glyph.center fromView:glyph.superview], to = [host convertPoint:starts[i].CGPointValue toView:v.superview];
            v.center = CGPointMake(to.x - (inButton.x - CGRectGetMidX(v.bounds)), to.y - (inButton.y - CGRectGetMidY(v.bounds)));
        }
        for (UIView *v in faded) v.alpha = 0;
        for (UIView *picture in gone) [host addSubview:picture];
    }];
    SGRAnimateBarAfter(barDelay, ^{
        for (NSUInteger i = 0; i < moved.count; i++) moved[i].frame = targets[i].CGRectValue;
    }, completion);
    if (along) SGRAnimateBarAfter(alongDelay, along, nil);
    // The glass's trailing edge sweeps over the tabs, as the Music app's does: a tab that went fades as the
    // shrinking platter passes it, the one furthest out first, and one that came fades in as the growing
    // platter reaches it. Faded all at once, the new tabs stood outside the glass before it got to them.
    CGFloat width = MAX(host.bounds.size.width, 1);
    BOOL still = SGRReduceMotion();
    for (UIView *picture in gone) {
        CGFloat at = CGRectGetMidX(picture.frame) / width;
        [UIView animateWithDuration:kLeaveFade delay:still ? 0 : barDelay + kLeaveSweep * MAX(0, 1 - at)
                            options:UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionCurveEaseOut
                         animations:^{ picture.alpha = 0; }
                         completion:^(BOOL finished) { [picture removeFromSuperview]; }];
    }
    for (UIView *v in faded) {
        CGFloat at = CGRectGetMidX([v convertRect:v.bounds toView:host]) / width;
        [UIView animateWithDuration:kArriveFade delay:still ? 0 : barDelay + kArriveSweep * MIN(1, MAX(0, at))
                            options:UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseOut
                         animations:^{ v.alpha = 1; }
                         completion:nil];
    }
    SGLog(@"tab bar: %lu tabs fade out, %lu fade in", (unsigned long)gone.count, (unsigned long)faded.count);
}

// The middle, in the host, of the trailing tab the row shows, where it is laid out: the row's last, which the
// minimized bar's trailing circle holds.
static BOOL trailingTabCenter(UIView *bar, UIView *host, CGPoint *center) {
    __block CGFloat best = -CGFLOAT_MAX;
    SGForEachView(bar, ^(UIView *v) {
        if (!v.window || !isTabButton(v) || isLitCopy(v, host)) return;
        CGRect frame = [v convertRect:v.bounds toView:host];
        if (CGRectGetMidX(frame) <= best) return;
        best = CGRectGetMidX(frame);
        *center = CGPointMake(CGRectGetMidX(frame), CGRectGetMidY(frame));
    });
    return best > -CGFLOAT_MAX;
}

static void setMinimized(BOOL minimized, BOOL animated) {
    UIView *stockBar = sg_stockBar;
    if (minimized == sg_minimized) return;
    // Spotify's regular width bar is not the glass one's row of tabs; it stays as it is.
    if (minimized && (!stockBar.window || stockBar.traitCollection.horizontalSizeClass != UIUserInterfaceSizeClassCompact)) return;
    sg_minimized = minimized;
    SGLog(@"tab bar: %@", minimized ? @"minimized" : @"expanded");
    if (!stockBar) return;
    UIView *host = objc_getAssociatedObject(stockBar, &kHostKey);
    void (^settle)(BOOL) = ^(BOOL finished) {
        if (sg_minimized != minimized) return;
        syncBar(stockBar);
    };
    animated &= host.window != nil;
    SGRBarState before = animated ? barState(host, minimized) : (SGRBarState){0};
    UIView *mainBar = objc_getAssociatedObject(stockBar, &kBarKey), *trailBar = objc_getAssociatedObject(stockBar, &kTrailBarKey);
    // Minimizing, the trailing circle sets off from where the last tab stands in the row; growing, it heads back there
    // and goes into the row: kept, it stood beside the grown row as a second copy until the spring ended, where the
    // Music app's slides into the row (a screen recording beside the Music app's, 2026-10-24).
    CGPoint lastInRow = CGPointZero;
    BOOL fromRow = animated && minimized && trailingTabCenter(mainBar, host, &lastInRow);
    BOOL leaving = animated && !minimized && trailBar && !trailBar.hidden;
    if (leaving) sg_trailLeaving = YES;
    CALayer *mainShown = mainBar.layer.presentationLayer ?: mainBar.layer;
    NSValue *mainWas = [NSValue valueWithCATransform3D:mainShown.sublayerTransform];
    // The items are made where the bars are going, before anything moves. UIKit sizes a tab's name by the platter
    // its item is made in, and the first pass made the expanding row's items while the bar still held the circle's one
    // item, its platter a circle: "Your Library" stayed cut. They were made a second time for that, which was a third of
    // the expand's stall; now each name is set again once the row is laid out, which measures it anew (its owner asked
    // for the stall cut, 2026-10-26). Checked on the phone: every name its full width over six expands.
    [UIView performWithoutAnimation:^{
        syncBar(stockBar);
        [host layoutIfNeeded];
        if (!minimized) {
            SGRSystemTabBar *row = objc_getAssociatedObject(stockBar, &kBarKey);
            for (UITabBarItem *item in row.items) {
                NSString *title = item.title;
                if (!title.length) continue;
                item.title = nil;
                item.title = title;
            }
            [host layoutIfNeeded];
            SGRShrinkTabTitles(row);
        }
        if (!animated) SGRNowPlayingBarFollowTabBar();
    }];
    if (!animated) {
        settle(YES);
        return;
    }
    // The Music app's bar leads a minimize, drawing in before the card comes down into its row, and the card leads
    // an expand, lifting off before the bar grows under it. Set off together, the two glasses lay over each other
    // half the way (a screen recording at 60 fps).
    CGFloat side = kCircleWidth + 2 * kPlatterInset;
    if (fromRow && trailBar && !trailBar.hidden) {
        CGRect to = trailBar.frame, from = CGRectMake(lastInRow.x - side / 2, to.origin.y, to.size.width, to.size.height);
        [before.frames removeObjectForKey:trailBar];
        [UIView performWithoutAnimation:^{ trailBar.frame = from; }];
        SGRAnimateBarAfter(0, ^{ trailBar.frame = to; }, nil);
    }
    if (leaving) {
        CGPoint target = CGPointZero;
        if (trailingTabCenter(mainBar, host, &target)) {
            CGRect to = CGRectMake(target.x - side / 2, trailBar.frame.origin.y, trailBar.frame.size.width, trailBar.frame.size.height);
            [before.frames removeObjectForKey:trailBar];
            SGRAnimateBarAfter(kBarLag, ^{ trailBar.frame = to; }, nil);
        }
        // Gone as the row's edge reaches it, the Music app's two merging in a couple of frames, where after the sweep it
        // stood beside the row's own copy a while.
        [UIView animateWithDuration:kMergeFade delay:kBarLag + kMergeDelay options:UIViewAnimationOptionBeginFromCurrentState
                         animations:^{ trailBar.alpha = 0; }
                         completion:^(BOOL finished) {
            sg_trailLeaving = NO;
            trailBar.alpha = 1;
            if (!sg_minimized) syncBar(stockBar);
        }];
    }
    // A Jam's strip lays out again only once the move is over (NowPlayingBar.x).
    SGRNowPlayingBarMoving(YES);
    moveFrom(host, before, ^{ SGRNowPlayingBarFollowTabBar(); }, minimized ? kCardLag : 0, minimized ? 0 : kBarLag, ^(BOOL finished) {
        SGRNowPlayingBarMoving(NO);
        settle(finished);
    });
    // The leading circle grows and shrinks on the bars' spring; the trailing one is always a circle.
    if (mainBar && !CATransform3DEqualToTransform(mainWas.CATransform3DValue, mainBar.layer.sublayerTransform)) {
        CASpringAnimation *spring = SGRBarSpringAnimation(@"sublayerTransform", mainWas, minimized ? 0 : kBarLag);
        if (spring) [mainBar.layer addAnimation:spring forKey:@"sgr.circle"];
    }
}

CGRect SGRTabBarInlineSlot(UIView *host, CGFloat height) {
    UIView *stockBar = sg_stockBar;
    UIView *bar = stockBar ? objc_getAssociatedObject(stockBar, &kBarKey) : nil;
    UIView *trailBar = stockBar ? objc_getAssociatedObject(stockBar, &kTrailBarKey) : nil;
    if (!sg_minimized || !host || !bar.window || stockBar.hidden || stockBar.alpha < 0.01) return CGRectNull;
    // The frames the bars are going to, not what is on screen mid-spring. Without the trailing circle the card
    // runs to where its glass would end.
    CGRect lead = [bar.superview convertRect:bar.frame toView:host];
    // The circles are kRowCircle across round the centers of UIKit's 62 pt platters, the card kPlatterGap from each.
    CGFloat shrunk = (kCircleWidth - kRowCircle) / 2;
    CGFloat left = CGRectGetMinX(lead) + kPlatterInset + kCircleWidth - shrunk + kPlatterGap;
    CGFloat right;
    if (trailBar && !trailBar.hidden) {
        CGRect trail = [trailBar.superview convertRect:trailBar.frame toView:host];
        right = CGRectGetMaxX(trail) - kPlatterInset - kCircleWidth + shrunk - kPlatterGap;
    } else {
        CGRect whole = [stockBar convertRect:stockBar.bounds toView:host];
        right = CGRectGetMaxX(whole) - kPlatterInset - shrunk;
    }
    CGFloat middle = CGRectGetMinY(lead) + kCircleWidth / 2;
    CGRect slot = CGRectMake(left, middle - height / 2, right - left, height);
    // A bar Spotify has slid away for a page takes the slot off the screen with it.
    CGRect inWindow = [host convertRect:slot toView:nil];
    if (slot.size.width < 100 || CGRectGetMaxY(inWindow) > CGRectGetMaxY(bar.window.bounds)) return CGRectNull;
    return slot;
}

CGRect SGRTabBarFullSlot(UIView *host) {
    UIView *stockBar = sg_stockBar;
    UIView *bar = stockBar ? objc_getAssociatedObject(stockBar, &kBarKey) : nil;
    if (sg_minimized || !host || !bar.window || stockBar.hidden || stockBar.alpha < 0.01) return CGRectNull;
    if (stockBar.traitCollection.horizontalSizeClass != UIUserInterfaceSizeClassCompact) return CGRectNull;
    CGRect whole = [stockBar convertRect:stockBar.bounds toView:host];
    return CGRectInset(whole, kPlatterInset, 0);
}

#pragma mark - hooks

static UIView *tabBarOf(UIView *item) {
    Class barClass = NSClassFromString(@"_TtC23NavigationUI_TabBarImpl10TabBarView");
    for (UIView *v = item.superview; v; v = v.superview) if ([v isKindOfClass:barClass]) return v;
    return nil;
}

// The bar in its own pass, and whether one of its items laid out during it.
static __weak UIView *sg_passBar;
static BOOL sg_itemsLaidOut;

%hook _TtC23NavigationUI_TabBarImpl10TabBarView
- (void)layoutSubviews {
    // A pass nested in another (an item's layoutIfNeeded) hands both back, so the outer one still composes.
    UIView *bar = (UIView *)self, *outer = sg_passBar;
    BOOL outerLaidOut = sg_itemsLaidOut;
    sg_passBar = bar;
    %orig;
    SGRComposeTabBar(bar);
    sg_itemsLaidOut = NO;
    for (UIView *sub in bar.subviews) {
        if (![sub isKindOfClass:SGRTabBarHost.class] && ![sub isKindOfClass:SGRBarFade.class]) [sub layoutIfNeeded];
    }
    // Items the row's pass laid out are composed once, all together, rather than once each.
    if (sg_itemsLaidOut) SGRComposeTabBar(bar);
    sg_passBar = outer;
    sg_itemsLaidOut = outerLaidOut;
    holdFirstTab(bar);
    syncBar(bar);
    SGRLogTabBarRow(bar);
}
%end

// The bar's own pass runs before Spotify has filled the row; the items lay out as they arrive. Inside the bar's
// pass, the pass composes once after them; outside it, the item composes at once, so no frame shows Spotify's row.
static void itemDidLayOut(UIView *item) {
    UIView *bar = tabBarOf(item);
    if (!bar) return;
    if (bar == sg_passBar) {
        sg_itemsLaidOut = YES;
        return;
    }
    SGRComposeTabBar(bar);
    holdFirstTab(bar);
    syncBar(bar);
    SGRLogTabBarRow(bar);
}

%hook _TtC23NavigationUI_TabBarImpl21TabBarItemElementView
- (void)layoutSubviews {
    %orig;
    itemDidLayOut((UIView *)self);
}
%end

%hook _TtC25CreateMenu_TabBarItemImpl24CreateMenuTabBarItemView
- (void)layoutSubviews {
    %orig;
    itemDidLayOut((UIView *)self);
}
%end

// A tab changed from elsewhere (a link, the side drawer) repaints the labels without a layout pass.
%hook _TtC23NavigationUI_TabBarImpl19TabBarContainerImpl
- (void)setSelectedViewController:(UIViewController *)controller {
    %orig;
    dispatch_async(dispatch_get_main_queue(), ^{
        // Another tab brings the minimized bar back (HIG, Tab bars).
        SGRSetTabBarMinimized(NO, YES);
        UIView *bar = sg_stockBar;
        if (bar) syncBar(bar);
    });
}
// The message bar coming or going changes the view's safe area before Spotify lays the bar out for it,
// so the room follows in that same pass, and inside the message bar's animation.
- (void)viewSafeAreaInsetsDidChange {
    %orig;
    makeRoom((UIViewController *)self);
}
%end

// Spotify's own fade under its bar, 219 pt down to black from 9.1.90 (TabBarGradientView), stacked with SGRBarFade
// into a band near black over the page's foot. SGRBarFade is the redesign's, so Spotify's stays clear.
%group SpotifyBarFade
%hook _TtC23NavigationUI_TabBarImpl18TabBarGradientView
- (void)didMoveToWindow {
    %orig;
    ((UIView *)self).alpha = 0;
}
- (void)setAlpha:(CGFloat)alpha {
    %orig(0);
}
%end
%end

// The tab buttons and the selection's lens UIKit lays out in a widened platter, stretched to it (widenPlatter). UIKit
// places them by bounds and center, never by frame (the phone's log, 2026-10-26: 94 pt bounds and centers 51, 137 and
// 223 in a 274 pt platter, the lens on the selected one's center); their centers are spread over the bar.
%hook _UITabButton
- (void)setCenter:(CGPoint)center {
    %orig(placedCenter((UIView *)self, center));
}
- (void)setBounds:(CGRect)bounds {
    %orig(placedBounds((UIView *)self, bounds));
}
%end

// Whether a lens is one of the glass bar's own.
static BOOL inGlassBar(UIView *view) {
    NSUInteger depth = 0;
    for (UIView *up = view.superview; up && depth < 4; up = up.superview, depth++) if ([up isKindOfClass:SGRSystemTabBar.class]) return YES;
    return NO;
}

%hook _UILiquidLensView
// No lens on a minimized circle (see pressCircle): UIKit shows it by its alpha and hidden, so those stay off.
- (void)setAlpha:(CGFloat)alpha {
    %orig(sg_minimized && alpha > 0 && inGlassBar((UIView *)self) ? 0 : alpha);
}
- (void)setHidden:(BOOL)hidden {
    %orig(hidden || (sg_minimized && inGlassBar((UIView *)self)));
}
// UIKit's press is the lens being lifted, and the lifted lens is drawn apart from the lens view, so neither its alpha nor
// its hidden kept it off a circle: two bubbles stacked at every tap (its owner, 2026-10-27; the buttons' highlight never
// changed, the log showed). On a minimized circle the lift is refused and stands for the press instead (pressCircle).
- (void)setLifted:(BOOL)lifted animated:(BOOL)animated alongsideAnimations:(id)alongside completion:(id)completion {
    UIView *lens = (UIView *)self;
    if (sg_minimized && inGlassBar(lens)) {
        for (UIView *up = lens.superview; up; up = up.superview) {
            if ([up isKindOfClass:SGRSystemTabBar.class]) {
                pressCircle(up, lifted);
                break;
            }
        }
        %orig(NO, animated, alongside, completion);
        return;
    }
    %orig;
}
- (void)setCenter:(CGPoint)center {
    %orig(placedCenter((UIView *)self, center));
}
- (void)setBounds:(CGRect)bounds {
    %orig(placedBounds((UIView *)self, bounds));
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
    if (objc_getClass("_TtC23NavigationUI_TabBarImpl18TabBarGradientView")) %init(SpotifyBarFade);
    SGRequireClasses(@[
        @"_TtC23NavigationUI_TabBarImpl10TabBarView",
        @"_TtC23NavigationUI_TabBarImpl21TabBarItemElementView",
        @"_TtC25CreateMenu_TabBarItemImpl24CreateMenuTabBarItemView",
        @"_TtC23NavigationUI_TabBarImpl19TabBarContainerImpl",
    ]);
}
