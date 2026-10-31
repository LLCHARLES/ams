// Player redesign: glass circles behind the header's close and more buttons.
//
// Glass is the control layer floating over the field, so it goes behind the round buttons only: the
// playlist name between them stays a label, and the row of playback controls stays bare glyphs
// (PlayerControls.x). Each circle is a subview of the button it sits behind (SGRGlassInside), below
// what the button draws and taking no touches, so the buttons stay Spotify's, with their actions, state
// and accessibility, and the circle follows the button wherever Spotify's row puts it. Circles placed
// from the unit's layout pass instead (a backing across the unit's view) were read before the row had
// laid the buttons out and sat 24pt up and to the side until a tap laid the unit out again
// (trees/continuous/1.txt, 2026-09-17: shapes at {-10, -22} and {320, -22}; the close button is at {12, 0}
// in the unit's view, so its circle belonged at {14, 2}).
//
// The ⋯ leaves the header for the title row's trailing end, right of the add button, where the Music app
// keeps the pair (reparented as an arranged view: the glass, the menu front, the press and the popover
// anchor are the button's own and ride the move; PlayerLyrics.x's title fade reads the row's new trailing
// edge by itself). The add button stays where Spotify put it and wears the Music app's star over the same
// glass circle: hollow until the song is saved, filled and accented once it is. Its Lottie plus/tick stays
// under the star, transparent, so the button's own action and selected state are untouched, and the saved
// star carries the plain checkmark's identifier for Follow the cover. The other add buttons (the list rows',
// the mini bar's) keep Spotify's look, and so does the AI DJ's player: its units are other classes.
//
// Tree (trees/clean/player/01.txt): HeaderElementsUnit's view is a 402x48 row holding
// id=now-playing-minimize-button 48x48 (:103) and id=Context menu 48x48 (:122), the playlist name
// between them. The down arrow keeps its circle in the header; the ⋯'s circle moves to the row with it.
// 9.1.78 also carries mobile-nowplaying-close-button (strings in the binary), so the down arrow is looked for
// under either name; which view each circle went into is logged once, so a phone where the arrow has none
// says why.
//
// The circle presses in itself (scale, the Kit's press spring), from the control that takes the touches: the
// arrow's own, and for the ⋯ the mod's button over it (ContextMenu.x). Spotify draws a button's pressed look
// under its subviews, where the circle covers it (phone, 2026-10-06: the arrow closed the player but showed
// no ripple), and the ⋯'s touches no longer reach Spotify's button at all.
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Redesigned/ContextMenu/ContextMenu.h"
#import "Player.h"

static char kGlassKey, kCloseKey, kMoreKey, kPressKey;
static char kStarKey, kStarStateKey, kEllipsisKey, kSizedKey, kMoreRowKey, kLikeKey;
static const CGFloat kPressScale = 0.92;
static const CGFloat kRowButtonGap = 10;   // between the star and the ⋯ in the title row
static const CGFloat kStarSize = 17;
static const CGFloat kEllipsisSize = 20;

static __weak UIStackView *sg_row;   // the ordinary player's title row
static __weak UIButton *sg_like;     // its add button, star-drawn
static __weak UIButton *sg_more;     // the header's ⋯, moved to the row's end

@interface SGRHeaderPress : NSObject
@end
@implementation SGRHeaderPress
// The circle of the control pressed, or of the button under it (the ⋯'s front).
static UIView *circleOf(UIControl *control) {
    return objc_getAssociatedObject(control, &kGlassKey) ?: objc_getAssociatedObject(control.superview, &kGlassKey);
}
- (void)down:(UIControl *)control {
    UIView *circle = circleOf(control);
    SGRAnimate(SGRMotionPress, ^{ circle.transform = CGAffineTransformMakeScale(kPressScale, kPressScale); }, nil);
}
- (void)up:(UIControl *)control {
    UIView *circle = circleOf(control);
    SGRAnimate(SGRMotionPress, ^{ circle.transform = CGAffineTransformIdentity; }, nil);
}
@end

// `throughMenu`: the mod's ⋯, whose touch UIKit cancels as the menu comes up on it; the press holds until the
// menu ends, which the button reports as a touch up outside (ContextMenu.x), so its cancel is not listened to.
static void pressFrom(UIControl *control, BOOL throughMenu) {
    if (![control isKindOfClass:UIControl.class] || objc_getAssociatedObject(control, &kPressKey)) return;
    objc_setAssociatedObject(control, &kPressKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    static SGRHeaderPress *press;
    if (!press) press = [SGRHeaderPress new];
    [control addTarget:press action:@selector(down:) forControlEvents:UIControlEventTouchDown | UIControlEventTouchDragEnter];
    UIControlEvents up = UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchDragExit;
    [control addTarget:press action:@selector(up:) forControlEvents:throughMenu ? up : up | UIControlEventTouchCancel];
}

// `identifiers` holds, for each button, the identifiers it may carry, the first found winning. `watchMenu`: the ⋯ is
// handed to PlayerMenu.m, which takes it for the ordinary player's; the AI DJ's ⋯ keeps Spotify's own menu.
static void glassInside(UIViewController *unit, NSArray<NSArray<NSString *> *> *identifiers, const void **findKeys, BOOL watchMenu) {
    UIView *host = unit.viewIfLoaded;
    if (!host) return;
    NSUInteger found = 0;
    for (NSUInteger i = 0; i < identifiers.count; i++) {
        UIView *button = nil;
        for (NSString *identifier in identifiers[i]) {
            if ((button = SGRFindByIdentifier(host, identifier, findKeys[i]))) break;
        }
        NSString *name = identifiers[i].firstObject;
        static NSMutableSet<NSString *> *said;
        if (!said) said = [NSMutableSet set];
        if (!button) {
            if (![said containsObject:name]) {
                [said addObject:name];
                SGLog(@"redesign player: %@ not found in %@, left as Spotify's", [identifiers[i] componentsJoinedByString:@" or "], NSStringFromClass(host.class));
            }
            continue;
        }
        UIView *circle = SGRGlassInside(button, &kGlassKey, SGRGlassCircleSize);
        if (![said containsObject:name] && button.bounds.size.width > 0) {
            [said addObject:name];
            SGLog(@"redesign player: a %.0fpt glass circle in %@ (id %@, %.0fx%.0f, %@)", circle.bounds.size.width, NSStringFromClass(button.class),
                  button.accessibilityIdentifier, button.bounds.size.width, button.bounds.size.height,
                  button.hidden || button.alpha < 0.01 ? @"hidden" : @"shown");
        }
        if (watchMenu && [name isEqualToString:@"Context menu"]) {
            SGRPlayerMenuWatch(button);
        }
        UIControl *front = SGRSystemMenuFront(button);
        pressFrom(front ?: (UIControl *)button, front != nil);
        found++;
    }

    static NSMutableSet<NSString *> *logged;
    if (!logged) logged = [NSMutableSet set];
    NSString *unitName = NSStringFromClass(unit.class);
    if (![logged containsObject:unitName]) {
        [logged addObject:unitName];
        SGLog(@"redesign player: glass inside %lu of %lu buttons in %@", (unsigned long)found, (unsigned long)identifiers.count, unitName);
    }
}

static void glassHeader(UIViewController *unit, BOOL watchMenu) {
    static const void *keys[] = {&kCloseKey, &kMoreKey};
    glassInside(unit, @[@[@"now-playing-minimize-button", @"mobile-nowplaying-close-button"], @[@"Context menu"]], keys, watchMenu);
}

// The title row's add button (the one sg_like names) wears the Music app's star over the same glass
// circle the ⋯ wears: hollow until the song is saved, filled and accented once it is. The image only
// changes with the selected state; the Lottie stays transparent under it. The marker keeps the plain
// checkmark off this button and says which button the star's later passes are looking at.
static void showStar(UIButton *button) {
    if (!button) return;
    if (button != sg_like && !objc_getAssociatedObject(button, &SGRTitleAddButtonKey)) return;
    objc_setAssociatedObject(button, &SGRTitleAddButtonKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    SGRGlassInside(button, &kGlassKey, SGRGlassCircleSize);
    pressFrom(button, NO);
    UIImageView *star = objc_getAssociatedObject(button, &kStarKey);
    if (!star) {
        star = [[UIImageView alloc] initWithImage:nil];
        star.contentMode = UIViewContentModeCenter;
        star.userInteractionEnabled = NO;
        star.isAccessibilityElement = NO;
        objc_setAssociatedObject(button, &kStarKey, star, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (star.superview != button) [button addSubview:star];
    star.frame = button.bounds;
    BOOL saved = button.isSelected;
    NSNumber *was = objc_getAssociatedObject(button, &kStarStateKey);
    if (!was || was.boolValue != saved) {
        objc_setAssociatedObject(button, &kStarStateKey, @(saved), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        UIImageSymbolConfiguration *configuration = [UIImageSymbolConfiguration configurationWithPointSize:kStarSize weight:UIImageSymbolWeightSemibold];
        star.image = [UIImage systemImageNamed:saved ? @"star.fill" : @"star" withConfiguration:configuration];
        star.tintColor = saved ? SGRAccent() : UIColor.whiteColor;
        star.accessibilityIdentifier = saved ? SGRPlainCheckIdentifier : nil;
    }
    SGRAddButtonAnimation(button).alpha = 0;
}

// The ⋯'s glyph, Spotify's dots swapped for the SF Symbol. The glass, the menu front and the press are
// the button's own subviews and targets and stay untouched.
static void showEllipsis(UIButton *button) {
    UIImageView *dots = objc_getAssociatedObject(button, &kEllipsisKey);
    if (!dots) {
        UIImageSymbolConfiguration *configuration = [UIImageSymbolConfiguration configurationWithPointSize:kEllipsisSize weight:UIImageSymbolWeightBold];
        dots = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"ellipsis" withConfiguration:configuration]];
        dots.tintColor = UIColor.whiteColor;
        dots.contentMode = UIViewContentModeCenter;
        dots.userInteractionEnabled = NO;
        dots.isAccessibilityElement = NO;
        objc_setAssociatedObject(button, &kEllipsisKey, dots, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    for (UIView *sub in button.subviews) {
        if (sub != dots && [sub isKindOfClass:UIImageView.class]) sub.hidden = YES;
    }
    button.imageView.hidden = YES;
    if (dots.superview != button) [button addSubview:dots];
    dots.frame = button.bounds;
}

// Both sides found (the header's ⋯, the stack holding the star), the move is made once and kept asserted:
// a rebuilt row takes the ⋯ back out and this puts it again.
static void placeRowButtons(void) {
    UIStackView *row = sg_row;
    UIButton *like = sg_like, *more = sg_more;
    if (!row || !like || !more) return;
    NSUInteger afterLike = [row.arrangedSubviews indexOfObject:like];
    // Spotify keeps the add button among the stack's arranged views; if a build gives it as a plain
    // subview instead, the ⋯ still goes last, where the pair belongs.
    afterLike = afterLike == NSNotFound ? row.arrangedSubviews.count : afterLike + 1;
    if (more.superview != row || [row.arrangedSubviews indexOfObject:more] != afterLike) {
        [more removeFromSuperview];
        more.translatesAutoresizingMaskIntoConstraints = NO;
        [row insertArrangedSubview:more atIndex:afterLike];
        if (!objc_getAssociatedObject(more, &kSizedKey)) {
            objc_setAssociatedObject(more, &kSizedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            [more.widthAnchor constraintEqualToConstant:SGRGlassCircleSize].active = YES;
            [more.heightAnchor constraintEqualToConstant:SGRGlassCircleSize].active = YES;
        }
        SGLog(@"redesign player: the ⋯ moved to the title row, after the star");
    }
    [row setCustomSpacing:kRowButtonGap afterView:like];
    showEllipsis(more);
}

// The ordinary player's information unit holds the title row the buttons move into. The row is the stack
// the add button itself sits in (Spotify keeps the title and the button in an inner stack, not the outer
// one SGRowIn finds): that is the stack the ⋯ joins. The DJ's unit is another class, so its row keeps
// Spotify's buttons.
static void rowUnitLaidOut(UIViewController *unit) {
    UIView *host = unit.viewIfLoaded;
    if (!host) return;
    UIButton *like = (UIButton *)SGRFindByIdentifier(host, @"Components.UI.AddToButton", &kLikeKey);
    if (![like isKindOfClass:UIButton.class]) return;
    sg_like = like;
    if ([like.superview isKindOfClass:UIStackView.class]) sg_row = (UIStackView *)like.superview;
    showStar(like);
    placeRowButtons();
}

%hook _TtC20NowPlaying_ModesImpl18HeaderElementsUnit
- (void)viewDidLayoutSubviews {
    %orig;
    glassHeader((UIViewController *)self, YES);
    // Once the ⋯ is in the title row it has left this view and the walk is skipped. A header that was
    // rebuilt keeps a fresh ⋯ of its own: that one is taken and the moved one, if it is still in the row,
    // goes, so the row never shows two.
    UIStackView *row = sg_row;
    if (!sg_more || !(row && sg_more.superview == row)) {
        UIButton *found = (UIButton *)SGRFindByIdentifier(((UIViewController *)self).viewIfLoaded, @"Context menu", &kMoreRowKey);
        if ([found isKindOfClass:UIButton.class] && found != sg_more) {
            if (row && [row.arrangedSubviews containsObject:sg_more]) [sg_more removeFromSuperview];
            sg_more = found;
        }
    }
    placeRowButtons();
}
%end

%hook _TtC20NowPlaying_ModesImpl23InformationElementsUnit
- (void)viewDidLayoutSubviews {
    %orig;
    rowUnitLaidOut((UIViewController *)self);
}
%end

// The star follows the add button's state: Spotify marks a saved song's button selected, and the same
// button in the list rows and the mini bar is left to Spotify (or to the plain checkmark, when that is on).
%hook UIButton
- (void)layoutSubviews {
    %orig;
    if ([self.accessibilityIdentifier isEqualToString:@"Components.UI.AddToButton"]) showStar(self);
}

- (void)setSelected:(BOOL)selected {
    %orig;
    if ([self.accessibilityIdentifier isEqualToString:@"Components.UI.AddToButton"]) showStar(self);
}
%end

// The AI DJ's player has a header unit of its own with the same two buttons, which the circles never reached.
// Its ⋯ gets the glass but is not watched: the menu it opens (feedback, language, voice) is not the player's.
%group SGRDJHeaderHooks
%hook SGRDJHeaderUnit
- (void)viewDidLayoutSubviews {
    %orig;
    glassHeader((UIViewController *)self, NO);
}
%end
%end

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
    Class djHeader = SGRDJClass(@"DJMHeaderElementsUnitViewController");
    if (djHeader) { %init(SGRDJHeaderHooks, SGRDJHeaderUnit = djHeader); }
    SGRequireClasses(@[@"_TtC20NowPlaying_ModesImpl18HeaderElementsUnit", @"_TtC20NowPlaying_ModesImpl23InformationElementsUnit"]);
}
