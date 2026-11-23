// Player redesign: the header the way the Music app's full screen player has it, only a grabber at the top. The
// ordinary player's down arrow and ⋯ are put away, and its ⋯ is the mod's own beside the title (PlayerMenu.m); the
// AI DJ's header keeps both buttons, each on a glass circle, as its ⋯ opens the DJ's own menu.
//
// The ordinary player's two buttons stay Spotify's and in Spotify's row: each goes by alpha, out of VoiceOver's reach
// (Encore's stacks crash on a hidden subview, so never hidden), and its action is still run from code. The ⋯'s brings
// up Spotify's sheet for the menu's rows (PlayerMenu.m, ContextMenu.x); the arrow's closes the player, from the
// grabber. The player still closes with a swipe down, Spotify's own.
//
// The arrow goes only once the grabber has a way to close by: the arrow a control with a tap's action (a primary
// action or a touch up inside, SGRControlActionEvents). Until then, or where it never has one, the arrow stays as
// Spotify's, on glass while Header glass is on, and the grabber is only drawn, as the header was before.
//
// The grabber is a button of the mod's: a tap on it, VoiceOver's activation of it (it reads as the arrow's own words,
// a button) and VoiceOver's escape on it close the player through the arrow's action. It stands in the player's own
// view, just above the header row's branch of it, so the row decides neither where it is drawn nor where it takes a
// touch: the pill is pinned where the Music app has it and the whole touch area is centered on the pill, wherever
// Spotify then moves the row. Spotify 9.2.0 places the row by its top constraint, and a move of it lays the header out
// again only across the safe area's edge; a pill inside the row rode along to 115pt on the phone, one row height
// low, and one pinned there alone would sit outside the row's touches.
// It takes the row's look: the row and each view between it and the player are watched for their alpha and hidden,
// which every fade of the row sets (the lyrics on their own, PlayerLyrics.x, the AI DJ's row with them; Spotify's
// own), inside its animation, so the grabber goes and comes back with the row in the same animation, Reduce
// Motion's included. The row holds it, and it leaves the player when the row does, out of the window or within it.
// The window's top inset is followed as it changes, apart from any layout of the row; with no inset, the touch area
// keeps its 44pt inside the player and the pill stays 7pt under the top.
//
// The AI DJ's circles: glass is the control layer floating over the field, so it goes behind the round buttons only.
// Each circle is a subview of the button it sits behind (SGRGlassInside), below what the button draws and taking no
// touches, so the buttons stay Spotify's, with their actions, state and accessibility, and the circle follows the
// button wherever Spotify's row puts it. Circles placed from the unit's layout pass instead (a backing across the
// unit's view) were read before the row had laid the buttons out and sat 24pt up and to the side until a tap laid
// the unit out again (trees/continuous/1.txt, 2026-09-17). They can be switched off on the Player page
// (SGRKeyPlayerHeaderGlass), which the open player follows at once: only the circles go, and each button draws as
// Spotify's own again. The circle presses in itself (scale, the Kit's press spring) from the button's own touches:
// Spotify draws a button's pressed look under its subviews, where the circle covers it (phone, 2026-10-06).
//
// Tree (trees/clean/player/01.txt): HeaderElementsUnit's view is a 402x48 row holding
// id=now-playing-minimize-button 48x48 (:103) and id=Context menu 48x48 (:122), the playlist name between them.
// 9.1.78 also carries mobile-nowplaying-close-button (strings in the binary), so the down arrow is looked for under
// either name; which view each button was found as is logged once, so a phone where one is missing says why.
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Redesigned/ContextMenu/ContextMenu.h"
#import "Player.h"

static char kGlassKey, kCloseKey, kMoreKey, kPressKey, kGrabberKey;
static char kContextKey, kContextStateKey;
static const CGFloat kPressScale = 0.92;
static NSString *const kMoreID = @"Context menu";

static NSArray<NSString *> *closeIDs(void) {
    return @[@"now-playing-minimize-button", @"mobile-nowplaying-close-button"];
}

static void contextVisibility(UIView *header) {
    // The recorded title container carries the accessibility label as well as the nested marquee.
    // Alpha preserves its stack slot; hidden would change Spotify's stack layout.
    UIView *context = SGRFindByIdentifier(header, @"now-playing-navigation-unit-title-label", &kContextKey);
    if (!context) return;
    NSArray<NSNumber *> *saved = objc_getAssociatedObject(context, &kContextStateKey);
    if (SGEnabled(SGRKeyPlayerHideContext)) {
        if (!saved) {
            saved = @[@(context.alpha), @(context.isAccessibilityElement), @(context.accessibilityElementsHidden)];
            objc_setAssociatedObject(context, &kContextStateKey, saved, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        context.alpha = 0;
        context.isAccessibilityElement = NO;
        context.accessibilityElementsHidden = YES;
    } else if (saved) {
        context.alpha = saved[0].doubleValue;
        context.isAccessibilityElement = saved[1].boolValue;
        context.accessibilityElementsHidden = saved[2].boolValue;
        objc_setAssociatedObject(context, &kContextStateKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

// The first of `identifiers` found in `host`, logged once by its first name when none is there.
static UIView *buttonIn(UIView *host, NSArray<NSString *> *identifiers, const void *findKey) {
    UIView *button = nil;
    for (NSString *identifier in identifiers) {
        if ((button = SGRFindByIdentifier(host, identifier, findKey))) break;
    }
    static NSMutableSet<NSString *> *said;
    if (!said) said = [NSMutableSet set];
    NSString *name = identifiers.firstObject;
    if (!button && ![said containsObject:name]) {
        [said addObject:name];
        SGLog(@"redesign player: %@ not found in %@, left as Spotify's", [identifiers componentsJoinedByString:@" or "], NSStringFromClass(host.class));
    }
    return button;
}

#pragma mark - the AI DJ's glass

// It listens for a touch up inside, so it says it is a watcher (SGRControlWatcher): the grabber's route to close by is
// the arrow's own action, never this.
@interface SGRHeaderPress : NSObject <SGRControlWatcher>
@end
@implementation SGRHeaderPress
- (void)down:(UIControl *)control {
    UIView *circle = objc_getAssociatedObject(control, &kGlassKey);
    SGRAnimate(SGRMotionPress, ^{ circle.transform = CGAffineTransformMakeScale(kPressScale, kPressScale); }, nil);
}
- (void)up:(UIControl *)control {
    UIView *circle = objc_getAssociatedObject(control, &kGlassKey);
    SGRAnimate(SGRMotionPress, ^{ circle.transform = CGAffineTransformIdentity; }, nil);
}
@end

static void pressFrom(UIControl *control) {
    if (![control isKindOfClass:UIControl.class] || objc_getAssociatedObject(control, &kPressKey)) return;
    objc_setAssociatedObject(control, &kPressKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    static SGRHeaderPress *press;
    if (!press) press = [SGRHeaderPress new];
    [control addTarget:press action:@selector(down:) forControlEvents:UIControlEventTouchDown | UIControlEventTouchDragEnter];
    [control addTarget:press action:@selector(up:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside
                                                                    | UIControlEventTouchDragExit | UIControlEventTouchCancel];
}

// The button's circle, taken out while the header glass is switched off (SGRKeyPlayerHeaderGlass); the next pass with
// it on makes a new one. Only the circle goes: the button and its press watcher stay.
static void dropCircle(UIView *button) {
    UIView *circle = objc_getAssociatedObject(button, &kGlassKey);
    if (!circle) return;
    [circle removeFromSuperview];
    objc_setAssociatedObject(button, &kGlassKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

// A circle behind `button` while the header glass is on, none while it is off.
static void glassBehind(UIView *button) {
    BOOL glass = SGEnabled(SGRKeyPlayerHeaderGlass);
    UIView *circle = glass ? SGRGlassInside(button, &kGlassKey, SGRGlassCircleSize) : nil;
    if (!glass) dropCircle(button);
    static NSMutableSet<NSString *> *said;
    if (!said) said = [NSMutableSet set];
    NSString *name = button.accessibilityIdentifier ?: NSStringFromClass(button.class);
    if (![said containsObject:name] && button.bounds.size.width > 0) {
        [said addObject:name];
        SGLog(@"redesign player: %@ in %@ (id %@, %.0fx%.0f)", circle ? [NSString stringWithFormat:@"a %.0fpt glass circle", circle.bounds.size.width] : @"no glass circle, switched off",
              NSStringFromClass(button.class), button.accessibilityIdentifier, button.bounds.size.width, button.bounds.size.height);
    }
    pressFrom((UIControl *)button);
}

static void glassInside(UIViewController *unit) {
    UIView *host = unit.viewIfLoaded;
    if (!host) return;
    NSUInteger found = 0;
    static const void *keys[] = {&kCloseKey, &kMoreKey};
    NSArray<NSArray<NSString *> *> *identifiers = @[closeIDs(), @[kMoreID]];
    for (NSUInteger i = 0; i < identifiers.count; i++) {
        UIView *button = buttonIn(host, identifiers[i], keys[i]);
        if (!button) continue;
        glassBehind(button);
        found++;
    }
    static BOOL logged;
    if (!logged) {
        logged = YES;
        SGLog(@"redesign player: glass inside %lu of %lu buttons in %@", (unsigned long)found, (unsigned long)identifiers.count, NSStringFromClass(unit.class));
    }
}

#pragma mark - the ordinary player's buttons put away

// Spotify's ElementView holding a header button (trees of 9.2.0: each button alone in one). Spotify gives the ⋯ its
// alpha back as playback starts, with no layout of the header (9.2.0 simulator, 2026-11-18), and leaves the holder's.
static NSString *const kElementHolderPrefix = @"_TtGC13Element_UIKit11ElementView";

static void putAway(UIView *button) {
    if (!button) return;
    UIView *holder = button.superview;
    BOOL held = [NSStringFromClass(holder.class) hasPrefix:kElementHolderPrefix];
    for (UIView *view in held ? @[button, holder] : @[button]) {
        if (view.alpha != 0) view.alpha = 0;
        if (!view.accessibilityElementsHidden) view.accessibilityElementsHidden = YES;
    }
    if (button.isAccessibilityElement) button.isAccessibilityElement = NO;
}

// The events a tap on the down arrow fires, which the grabber closes the player by.
static const UIControlEvents kCloseEvents = UIControlEventPrimaryActionTriggered | UIControlEventTouchUpInside;

// The arrow, when it is a control with a tap's action to close the player by; else nil.
static UIControl *closeRoute(UIView *close) {
    if (![close isKindOfClass:UIControl.class]) return nil;
    return SGRControlActionEvents((UIControl *)close) & kCloseEvents ? (UIControl *)close : nil;
}

// The ⋯ always (the mod's own beside the title stands in); the arrow only with a route to close by, else it stays
// Spotify's, on glass as the setting has it.
static void putButtonsAway(UIView *header, UIView *close, UIControl *route) {
    UIView *more = buttonIn(header, @[kMoreID], &kMoreKey);
    if (route) putAway(close);
    else if (close) glassBehind(close);
    putAway(more);
    if (more) SGRPlayerMenuWatch(more);
    static BOOL logged;
    if (!logged && (close || more)) {
        logged = YES;
        SGLog(@"redesign player: the header's %@ and %@ put away for the grabber", !close ? @"(no down arrow)" : route ? @"down arrow" : @"(down arrow kept, no action to close by)",
              more ? @"⋯" : @"(no ⋯)");
    }
}

#pragma mark - the grabber

// The Music app's grabber over its full screen player (measured on its screenshot: a 60 x 4 pill, 7pt under the safe
// area's top), centered in a touch area of at least 44pt.
static const CGSize kGrabberSize = {60, 4};
static const CGFloat kGrabberTop = 7, kGrabberTouch = 44;
static char kRowLookContext;

@interface SGRPlayerGrabber : UIControl
@property (nonatomic, weak) UIControl *close;
@property (nonatomic, readonly) UIView *pill;
// The header row it stands for, whose look it takes.
@property (nonatomic, weak, readonly) UIView *row;
// The row's hold on it (SGRGrabberHold), a view in the row, through which the touch area takes its height.
@property (nonatomic, weak) UIView *hold;
- (void)follow:(UIView *)row in:(UIView *)player;
- (void)detach;
- (void)updateTopInset;
@end

// A full-window view receives inset changes even while the header is stationary or the player is sliding.
@interface SGRGrabberInsetObserver : UIView
@property (nonatomic, weak) SGRPlayerGrabber *grabber;
@end
@implementation SGRGrabberInsetObserver
- (void)safeAreaInsetsDidChange {
    [super safeAreaInsetsDidChange];
    [self.grabber updateTopInset];
}
@end

// The row's hold on its grabber: the row keeps it, and the grabber leaves the player once the row has gone.
@interface SGRGrabberHold : UIView
@property (nonatomic, readonly) SGRPlayerGrabber *grabber;
@end

@implementation SGRPlayerGrabber {
    NSHashTable<UIView *> *_watched;   // the row and each view between it and the player
    NSLayoutConstraint *_pin, *_middle, *_edge, *_tie;
    SGRGrabberInsetObserver *_insets;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    _pill = [UIView new];
    _pill.userInteractionEnabled = NO;
    _pill.layer.cornerRadius = kGrabberSize.height / 2;
    _pill.layer.cornerCurve = kCACornerCurveContinuous;
    [self addSubview:_pill];
    self.translatesAutoresizingMaskIntoConstraints = NO;
    _pill.translatesAutoresizingMaskIntoConstraints = NO;
    NSLayoutConstraint *center = [self.centerYAnchor constraintEqualToAnchor:_pill.centerYAnchor];
    center.priority = UILayoutPriorityRequired - 1; // Keep all 44pt reachable when the window has no top inset.
    // The height the touch area falls to once the row's tie (follow:) is gone.
    NSLayoutConstraint *collapsed = [self.heightAnchor constraintEqualToConstant:0];
    collapsed.priority = UILayoutPriorityFittingSizeLevel;
    [NSLayoutConstraint activateConstraints:@[
        [self.widthAnchor constraintEqualToConstant:kGrabberSize.width + kGrabberTouch], collapsed,
        center, [_pill.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [_pill.widthAnchor constraintEqualToConstant:kGrabberSize.width], [_pill.heightAnchor constraintEqualToConstant:kGrabberSize.height],
    ]];
    _watched = [NSHashTable weakObjectsHashTable];
    self.isAccessibilityElement = YES;
    self.accessibilityTraits = UIAccessibilityTraitButton;
    [self addTarget:self action:@selector(sgr_close) forControlEvents:UIControlEventTouchUpInside];
    return self;
}

- (void)dealloc {
    [self unwatch];
    [_insets removeFromSuperview];
}

- (void)unwatch {
    for (UIView *view in _watched) {
        [view removeObserver:self forKeyPath:@"alpha" context:&kRowLookContext];
        [view removeObserver:self forKeyPath:@"hidden" context:&kRowLookContext];
    }
    [_watched removeAllObjects];
}

- (void)detach {
    [self unwatch];
    _close = nil;
    _row = nil;
    _pin.active = NO;
    _edge.active = NO;
    _middle.active = NO;
    _tie.active = NO;
    [_insets removeFromSuperview];
    [self removeFromSuperview];
}

// The row, or a view it is in, has left the player, staying in the window (a move with no window change, which
// neither the hold's window nor the header's layout hears of): UIKit takes out every constraint tying the moved
// views to the rest (removeFromSuperview's contract), the tie with them, so the touch area falls to no height and is
// laid out here. A row moved within the player is laid out to be followed again; one gone from it takes the grabber
// out with it, after this pass.
- (void)layoutSubviews {
    [super layoutSubviews];
    UIView *player = self.superview, *row = _row;
    if (!player || _tie.active) return;
    if ([row isDescendantOfView:player]) {
        [row setNeedsLayout];
        return;
    }
    self.hidden = YES;
    __weak SGRPlayerGrabber *weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        SGRPlayerGrabber *grabber = weakSelf;
        if (grabber.superview && ![grabber.row isDescendantOfView:grabber.superview]) [grabber detach];
    });
}

- (void)updateTopInset {
    UIWindow *window = _insets.window;
    CGFloat top = window.safeAreaInsets.top + kGrabberTop;
    if (window && _pin.constant != top) _pin.constant = top;
}

// In the player just above the row's branch of it, the pill pinned under the player's top at the window's safe area
// and centered over the row, the touch area tied to the row's hold, and the row and each view between it and the
// player watched for their look. Taking the row out of the player takes the constraints to it across with it; a row
// put in again gets them anew.
- (void)follow:(UIView *)row in:(UIView *)player {
    _row = row;
    NSMutableArray<UIView *> *chain = [NSMutableArray array];
    for (UIView *view = row; view.superview != player; view = view.superview) [chain addObject:view.superview];
    UIView *branch = chain.lastObject ?: row;
    [chain insertObject:row atIndex:0];
    if (self.superview != player || [player.subviews indexOfObject:self] < [player.subviews indexOfObject:branch]) [player insertSubview:self aboveSubview:branch];
    UIWindow *window = player.window;
    if (!_insets) {
        _insets = [SGRGrabberInsetObserver new];
        _insets.grabber = self;
        _insets.userInteractionEnabled = NO;
        _insets.accessibilityElementsHidden = YES;
        _insets.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    }
    if (_insets.superview != window) {
        _insets.frame = window.bounds;
        [window insertSubview:_insets atIndex:0];
    }
    if (!_pin.active || _edge.secondItem != player) {
        _pin.active = NO;
        _edge.active = NO;
        _pin = [_pill.topAnchor constraintEqualToAnchor:player.topAnchor constant:window.safeAreaInsets.top + kGrabberTop];
        _edge = [self.topAnchor constraintGreaterThanOrEqualToAnchor:player.topAnchor];
        [NSLayoutConstraint activateConstraints:@[_pin, _edge]];
    }
    [self updateTopInset];
    if (!_middle.active || _middle.secondItem != row) {
        _middle = [self.centerXAnchor constraintEqualToAnchor:row.centerXAnchor];
        _middle.active = YES;
    }
    UIView *hold = self.hold;
    if (!_tie.active || _tie.secondItem != hold) {
        _tie = [self.heightAnchor constraintEqualToAnchor:hold.heightAnchor constant:kGrabberTouch];
        _tie.active = YES;
    }
    BOOL same = chain.count == _watched.count;
    for (UIView *view in chain) same = same && [_watched containsObject:view];
    if (!same) {
        [self unwatch];
        for (UIView *view in chain) {
            [view addObserver:self forKeyPath:@"alpha" options:0 context:&kRowLookContext];
            [view addObserver:self forKeyPath:@"hidden" options:0 context:&kRowLookContext];
            [_watched addObject:view];
        }
    }
    [self takeRowsLook];
}

// The row's alpha and hidden as the player draws it. A fade sets them inside its animation, where the observer is
// told at once, so the grabber's are set in the same animation. Its end is the product of the chain's alphas; while
// two of them animate at once the grabber goes straight to that product, drawn apart from the row's mid-fade. Only
// the row itself fades in Spotify 9.2.0 (its stack never: lyrics alone and woken, Reduce Motion on, track change,
// swipe-down and grabber close, reopen, iPhone, iPad side panel and two-column; simulator, 2026-11-20).
- (void)takeRowsLook {
    UIView *row = _row;
    CGFloat alpha = 1;
    BOOL hidden = !row || !self.superview || ![row isDescendantOfView:self.superview];
    for (UIView *view in _watched) {
        alpha *= view.alpha;
        hidden = hidden || view.hidden;
    }
    if (self.alpha != alpha) self.alpha = alpha;
    if (self.hidden != hidden) self.hidden = hidden;
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if (context != &kRowLookContext) {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
        return;
    }
    [self takeRowsLook];
}

// YES once the arrow's action has been sent: the arrow still has one to send.
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    return _row && self.superview && [_row isDescendantOfView:self.superview] && [super pointInside:point withEvent:event];
}

- (BOOL)sgr_close {
    if (!_row || !self.superview || ![_row isDescendantOfView:self.superview]) return NO;
    UIControl *close = self.close;
    BOOL routed = close && (SGRControlActionEvents(close) & kCloseEvents);
    NSString *how = routed ? SGRFireControl(close) : @"nothing: the down arrow has no action to close by";
    static int logged;
    if (logged++ < 3) SGLog(@"redesign player: the grabber closes the player by %@", how);
    return routed;
}

- (BOOL)accessibilityActivate {
    return [self sgr_close];
}

- (BOOL)accessibilityPerformEscape {
    return [self sgr_close];
}

@end

@implementation SGRGrabberHold
- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.userInteractionEnabled = NO;
    self.accessibilityElementsHidden = YES;
    _grabber = [SGRPlayerGrabber new];
    _grabber.hold = self;
    return self;
}
- (void)didMoveToWindow {
    [super didMoveToWindow];
    UIView *row = self.superview;
    if (!self.window || (_grabber.superview && ![row isDescendantOfView:_grabber.superview])) [_grabber detach];
    if (self.window) [row setNeedsLayout];
}
@end

// The player's own full screen view (SPTNowPlayingView) holding `view`, or nil.
static UIView *playerHolding(UIView *view) {
    for (UIView *v = view.superview; v; v = v.superview) {
        if ([v.nextResponder isKindOfClass:%c(_TtC19NowPlaying_ViewImpl24NowPlayingViewController)]) return v;
    }
    return nil;
}

// `route`: the arrow to close by, or nil, when the grabber is only drawn; `close`: the arrow, whose words it reads.
// `player`: the player's own view holding the header (playerHolding), whose top is the screen's once the player is up,
// under the window's safe area: the player's own safe area and the window's coordinates both take in the player's open
// as it slides up (9.2.0, 2026-11-18: the grabber 500pt over the screen).
static void placeGrabber(UIView *header, UIView *close, UIControl *route, UIView *player) {
    UIWindow *window = header.window;
    if (!window) return;
    SGRGrabberHold *hold = objc_getAssociatedObject(header, &kGrabberKey);
    if (!player) {
        [hold.grabber detach];
        return;
    }
    if (!hold) {
        hold = [[SGRGrabberHold alloc] initWithFrame:CGRectZero];
        objc_setAssociatedObject(header, &kGrabberKey, hold, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [header addSubview:hold];
    }
    SGRPlayerGrabber *grabber = hold.grabber;
    grabber.close = route;
    grabber.userInteractionEnabled = route != nil;
    grabber.isAccessibilityElement = route != nil;
    grabber.accessibilityElementsHidden = !route;
    // Spotify's words for its arrow, which the grabber stands in for.
    NSString *label = close.accessibilityLabel.length ? close.accessibilityLabel : SGL(@"player.grabber.close", @"Close Player");
    if (![grabber.accessibilityLabel isEqualToString:label]) grabber.accessibilityLabel = label;
    grabber.pill.backgroundColor = [UIColor colorWithWhite:1 alpha:SGRIncreaseContrast() ? 0.5 : 0.3];
    // Constraints, not a place worked out here: Spotify moves the row by its top constraint with no layout of the
    // header (9.2.0 simulator, 2026-11-19: the row one row lower carried a pill placed in it to 114pt, where the phone
    // had it), and the engine keeps the grabber where it is pinned.
    [grabber follow:header in:player];

    static dispatch_once_t once;
    dispatch_once(&once, ^{
        SGLog(@"redesign player: grabber pinned at %.0f in %@ (safe top %.0f, header row at %.0f), %@", window.safeAreaInsets.top + kGrabberTop, NSStringFromClass(player.class),
              window.safeAreaInsets.top, [header convertPoint:CGPointZero toView:player].y,
              route ? @"closing by the down arrow" : close ? @"drawn only, the down arrow has no action to close by" : @"drawn only, no down arrow");
    });
}

#pragma mark - touches through the put-away row

// The ordinary header put away: its buttons gone for the grabber, which closes by its arrow, and where it plays from
// hidden, nothing in its row is left to take a touch. The row keeps its touches while it shows where it plays from,
// which is a button, or the arrow, which stays Spotify's and live with no action to close by; the AI DJ's keeps its
// buttons. Read from the row and the setting as they are, never kept.
static BOOL rowPutAway(UIView *row) {
    return SGEnabled(SGRKeyPlayerHideContext) && closeRoute(buttonIn(row, closeIDs(), &kCloseKey)) != nil;
}

// Whether a touch landing on `view` itself goes on to what is under it in the player, the lifted cover (PlayerArtwork.x):
// `view` is a put-away ordinary header row, or holds nothing but such rows, down views holding nothing else. Spotify
// 9.2.0 keeps the unit's view alone in a stack of the row's own size, which took the touch the row let go
// (phone-sized simulator, 2026-11-20: a tap at y 100 landed on that stack). Never a view holding anything else, nor a
// view controller's own, the player's included. Decided from the views as they are at the touch, with nothing set on
// Spotify's: a row taken out of its stack, released, moved or replaced there by another header (the AI DJ's, whose
// buttons are live) leaves nothing behind. A put-away row lets go of a touch on the drawn cover anywhere in it but on
// a control (the hit-test hook below): its own stack's elements take one between what they draw (9.2.0 simulator,
// 2026-11-20: a tap at y 100 on the stack inside the row). Off the drawn cover every touch stays Spotify's (onDrawnCover).
static BOOL passesTouches(UIView *view) {
    UIResponder *owner = view.nextResponder;
    if ([owner isKindOfClass:%c(_TtC20NowPlaying_ModesImpl18HeaderElementsUnit)]) return rowPutAway(view);
    NSArray<UIView *> *held = view.subviews;
    if (!held.count || [owner isKindOfClass:UIViewController.class]) return NO;
    for (UIView *sub in held) {
        if (!passesTouches(sub)) return NO;
    }
    return YES;
}

// A touch in a put-away row that landed on a control of Spotify's still drawn there, or inside one: the buttons put
// away go by alpha, which hit testing passes over, so this is one Spotify shows beside them (an iPad side panel's
// button to widen the player) and keeps.
static BOOL onControl(UIView *hit, UIView *row) {
    for (UIView *view = hit; view && view != row; view = view.superview) {
        if ([view isKindOfClass:UIControl.class]) return YES;
    }
    return NO;
}

// A touch at `point` in `view` lands on the cover as drawn, lifted under the row. Elsewhere the row keeps it as Spotify's
// does: the cover's cell under it opens the cover's viewer on a tap anywhere in it, 40 pt over the picture in an iPad's
// side panel (9.2.0 simulator, 2026-11-20).
static BOOL onDrawnCover(UIView *view, CGPoint point) {
    return CGRectContainsPoint(SGRPlayerCoverFrameIn(view), point);
}

%hook UIView
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = %orig;
    if (!hit) return nil;
    if ([self.nextResponder isKindOfClass:%c(_TtC20NowPlaying_ModesImpl18HeaderElementsUnit)])
        return rowPutAway(self) && !onControl(hit, self) && onDrawnCover(self, point) ? nil : hit;
    return hit == self && passesTouches(self) && onDrawnCover(self, point) ? nil : hit;
}
%end

// `ordinary`: the ordinary player's header, its buttons put away; else the AI DJ's, its buttons on glass.
static void layOutHeader(UIViewController *unit, BOOL ordinary) {
    UIView *header = unit.viewIfLoaded;
    if (!header) return;
    UIView *close = buttonIn(header, closeIDs(), &kCloseKey);
    UIControl *route = closeRoute(close);
    if (ordinary) putButtonsAway(header, close, route);
    else glassInside(unit);
    UIView *player = playerHolding(header);
    // A touch in the put-away row's band falls through to the lifted cover under it (passesTouches); a live row keeps
    // its touches, and the cover stays under it.
    SGRPlayerCoverUnderRow(header, !ordinary || !rowPutAway(header), player);
    contextVisibility(header);
    placeGrabber(header, close, route, player);
    SGRPlayerWatchLook(header);
}

%hook _TtC20NowPlaying_ModesImpl18HeaderElementsUnit
- (void)viewDidLayoutSubviews {
    %orig;
    layOutHeader((UIViewController *)self, YES);
}
%end

// The AI DJ's player has a header unit of its own with the same two buttons. Its ⋯ opens the DJ's own menu
// (feedback, language, voice), not the player's, so both stay, on glass.
%group SGRDJHeaderHooks
%hook SGRDJHeaderUnit
- (void)viewDidLayoutSubviews {
    %orig;
    layOutHeader((UIViewController *)self, NO);
}
%end
%end

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
    Class djHeader = SGRDJClass(@"DJMHeaderElementsUnitViewController");
    if (djHeader) { %init(SGRDJHeaderHooks, SGRDJHeaderUnit = djHeader); }
    SGRequireClasses(@[@"_TtC20NowPlaying_ModesImpl18HeaderElementsUnit"]);
}
