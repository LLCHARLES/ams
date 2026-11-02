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
// edge by itself). The row is the stack the title rides in, not the add button's superview: Spotify can give
// each element of the row a view of its own. The add button stays where Spotify put it and wears the Music
// app's star over the same glass circle: hollow until the song is saved, filled and accented once it is. Its
// Lottie plus/tick stays under the star, transparent, so the button's own action and selected state are
// untouched, and the saved star carries the plain checkmark's identifier for Follow the cover. The other add
// buttons (the list rows', the mini bar's) keep Spotify's look, and so does the AI DJ's player: its units are
// other classes. Both discs are 30pt (the Music app's 28.5pt, measured below): the header's own pass puts a
// 44pt circle behind the ⋯ for the one pass it is still there, and placeRowButtons re-asserts the pair's
// size every time, so no other glass circle changes.
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
static char kStarKey, kStarStateKey, kEllipsisKey, kSizedKey, kMoreRowKey, kLikeKey, kTitleKey, kFrameKey;
static char kTreeKey, kTreeAfterKey;
static const CGFloat kPressScale = 0.92;
// The Music app's two round buttons on the title row, measured off its player screenshot (706 x 1536px for the
// 402 x 874pt screen, 1.756px to a point): the discs are 50px across, 28.5pt, 11.5pt apart with their middles
// 40pt apart. Spotify's add button keeps its own 48pt slot; the ⋯'s slot is 36pt and both discs 30pt (28.5
// rounded up so the 17pt glyph keeps its rim), so the add button's 9pt inset and the ⋯'s 3pt leave 12pt
// between the discs and 42pt between their middles.
static const CGFloat kTitleDiscSize = 30;
static const CGFloat kMoreSide = 36;
static const CGFloat kRowButtonGap = 0;
static const CGFloat kStarSize = 17;
static const CGFloat kEllipsisSize = 20;

static __weak UIStackView *sg_row;   // the ordinary player's title row
static __weak UIButton *sg_like;     // its add button, star-drawn
static __weak UIView *sg_more;       // the header's ⋯, moved to the row's end

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
    SGRGlassInside(button, &kGlassKey, kTitleDiscSize);
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

// The ⋯'s own glyph in the button, hidden under ours, is the small one. Spotify's ⋯ is a view whose class the
// phones disagree on (PlayerHeader.x's move found a non-UIButton), and what it draws is not always its own
// image view nor a child of the button: a reused header came back with a small ellipsis drawn a level or two
// inside (the phone's report, two glyphs over each other). Everything that is not ours is hidden, however deep
// it sits; the button itself is never hidden, and neither are the ⋯'s own control, the menu's front, nor the
// glass circle, so the menu, its action and its press stay untouched.
static void hideGlyphs(UIView *root, UIView *keepDots, UIView *keepGlass, UIView *keepFront) {
    for (UIView *sub in root.subviews) {
        if (sub == keepDots || sub == keepGlass || sub == keepFront) continue;
        // A control is the menu's front or Spotify's own button: it is not hidden (that would take its touches
        // away), but what it draws inside it may be the glyph and is looked at.
        if ([sub isKindOfClass:UIControl.class]) {
            hideGlyphs(sub, keepDots, keepGlass, keepFront);
            continue;
        }
        sub.hidden = YES;
        hideGlyphs(sub, keepDots, keepGlass, keepFront);
    }
}

static void appendTree(UIView *view, NSUInteger depth, NSMutableString *text) {
    NSString *indent = [@"" stringByPaddingToLength:depth * 2 withString:@" " startingAtIndex:0];
    [text appendFormat:@"\n%@%@ %@%@ hidden=%d alpha=%.2f", indent, NSStringFromClass(view.class), NSStringFromCGRect(view.frame),
     [view isKindOfClass:UIControl.class] ? @" (control)" : @"", view.hidden, view.alpha];
    if ([view isKindOfClass:UIImageView.class]) [text appendFormat:@" image=%@", ((UIImageView *)view).image ? @"yes" : @"no"];
    if ([view isKindOfClass:UILabel.class]) [text appendFormat:@" text=%@", ((UILabel *)view).text];
    for (UIView *sub in view.subviews) appendTree(sub, depth + 1, text);
}

// The ⋯'s glyph, Spotify's dots swapped for the SF Symbol. The glass, the menu front and the press are
// the button's own subviews and targets and stay untouched. The ⋯ is Spotify's control whatever its class:
// its glyph is hidden only when it has one (a UIButton's image view), and anything else the button draws
// that is not ours (hideGlyphs).
static void showEllipsis(UIView *button) {
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
    // The tree as Spotify's ⋯ came, once, and after the pass that hid what it drew: the phone's log then says
    // which view drew the second ellipsis (kTreeKey is the before, kTreeAfterKey the after).
    if (!objc_getAssociatedObject(button, &kTreeKey)) {
        NSMutableString *text = [NSMutableString string];
        appendTree(button, 0, text);
        objc_setAssociatedObject(button, &kTreeKey, [text copy], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        SGLog(@"redesign player: the ⋯ %@ came as:%@", NSStringFromClass(button.class), text);
    }
    if ([button isKindOfClass:UIButton.class]) ((UIButton *)button).imageView.hidden = YES;
    hideGlyphs(button, dots, objc_getAssociatedObject(button, &kGlassKey), SGRSystemMenuFront(button));
    if (dots.superview != button) [button addSubview:dots];
    dots.frame = button.bounds;
    NSMutableString *after = [NSMutableString string];
    appendTree(button, 0, after);
    if (![after isEqualToString:objc_getAssociatedObject(button, &kTreeAfterKey)]) {
        objc_setAssociatedObject(button, &kTreeAfterKey, [after copy], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        SGLog(@"redesign player: the ⋯ %@ is now:%@", NSStringFromClass(button.class), after);
    }
}

// Both sides found (the header's ⋯, the stack holding the star), the move is made once and kept asserted:
// a rebuilt row takes the ⋯ back out and this puts it again. The ⋯ goes right after the add button, or after
// the view the add button is arranged in (Spotify may wrap each element of the row), and last when it is not
// arranged at all. Its slot is kMoreSide square (the add button keeps Spotify's own), and its glass is
// re-asserted here so the header's own pass, which puts a 44pt circle behind it, does not keep the size.
static void placeRowButtons(void) {
    UIStackView *row = sg_row;
    UIView *like = sg_like, *more = sg_more;
    if (!row || !like || !more) return;
    // The view of the row the add button belongs to, which the ⋯ goes after.
    UIView *item = like;
    while (item && item.superview != row) item = item.superview;
    BOOL placed = NO;
    if (more.superview == row) {
        NSUInteger at = [row.arrangedSubviews indexOfObject:more];
        NSUInteger before = item ? [row.arrangedSubviews indexOfObject:item] : NSNotFound;
        placed = at != NSNotFound && (before == NSNotFound ? at == row.arrangedSubviews.count - 1 : at == before + 1);
    }
    if (!placed) {
        UIView *old = more.superview;
        if ([old isKindOfClass:UIStackView.class] && [((UIStackView *)old).arrangedSubviews containsObject:more]) {
            [(UIStackView *)old removeArrangedSubview:more];
        }
        [more removeFromSuperview];
        more.translatesAutoresizingMaskIntoConstraints = NO;
        // The index is read again once the ⋯ is out: its old place, before the add button, would have
        // shifted the one wanted under it, and an index past the stack's count is an exception.
        NSUInteger next = item ? [row.arrangedSubviews indexOfObject:item] : NSNotFound;
        next = next == NSNotFound ? row.arrangedSubviews.count : next + 1;
        next = MIN(next, row.arrangedSubviews.count);
        [row insertArrangedSubview:more atIndex:next];
        if (!objc_getAssociatedObject(more, &kSizedKey)) {
            objc_setAssociatedObject(more, &kSizedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            [more.widthAnchor constraintEqualToConstant:kMoreSide].active = YES;
            // The height yields to the row: a fill alignment gives the ⋯ the row's height, and the circle is
            // centered in whatever bounds the button ends with, so a required height would only be broken.
            NSLayoutConstraint *height = [more.heightAnchor constraintEqualToConstant:kMoreSide];
            height.priority = 999;
            height.active = YES;
        }
        // The circle is centered from the button's bounds, which are still the header's or nothing until the
        // stack lays this pass' new view out: its place is given here, so the first frame is right too.
        more.bounds = (CGRect){CGPointZero, CGSizeMake(kMoreSide, kMoreSide)};
        SGLog(@"redesign player: the ⋯ (%@) moved from %@ to the title row %@ at index %lu, after %@",
              NSStringFromClass(more.class), old ? NSStringFromClass(old.class) : @"nothing",
              NSStringFromClass(row.class), (unsigned long)next, item ? NSStringFromClass(item.class) : @"nothing");
    }
    if (item) [row setCustomSpacing:kRowButtonGap afterView:item];
    SGRGlassInside(more, &kGlassKey, kTitleDiscSize);
    showEllipsis(more);
}

// The ordinary player's information unit holds the title row the buttons move into. The row is the stack
// the title is arranged in (the unit's own view is a plain view above it): the add button can be given as a
// plain view of that stack, or inside a view of it, so its own superview is not the row to trust. The stack
// the title rides in is the row; the add button's stack and SGRowIn are the fallbacks. The DJ's unit is
// another class, so its row keeps Spotify's buttons.
static void rowUnitLaidOut(UIViewController *unit) {
    UIView *host = unit.viewIfLoaded;
    if (!host) return;
    UIButton *like = (UIButton *)SGRFindByIdentifier(host, @"Components.UI.AddToButton", &kLikeKey);
    if (![like isKindOfClass:UIButton.class]) return;
    sg_like = like;
    UIView *title = SGRFindByIdentifier(host, @"now-playing-title-label", &kTitleKey);
    UIStackView *row = nil;
    for (UIView *v = title; v && v != host; v = v.superview) {
        if ([v.superview isKindOfClass:UIStackView.class]) { row = (UIStackView *)v.superview; break; }
    }
    if (!row && [like.superview isKindOfClass:UIStackView.class]) row = (UIStackView *)like.superview;
    if (!row) row = SGRowIn(host);
    sg_row = row;
    showStar(like);
    placeRowButtons();
    // The trees this ran against: the row, the add button and the ⋯ as found, so a phone says which stack
    // the row is and where the pair stands. Logged when it changes, not on every pass.
    NSString *seen = [NSString stringWithFormat:@"%@ %@ %@ %@", row ? NSStringFromClass(row.class) : @"nothing",
                      like.superview ? NSStringFromClass(like.superview.class) : @"nothing",
                      sg_more ? NSStringFromClass(sg_more.class) : @"nothing",
                      title ? NSStringFromClass(title.class) : @"nothing"];
    if (![seen isEqualToString:objc_getAssociatedObject(host, &kFrameKey)]) {
        objc_setAssociatedObject(host, &kFrameKey, seen, OBJC_ASSOCIATION_COPY_NONATOMIC);
        SGLog(@"redesign player: the title row is %@ %@; the add button rides in %@, the title on %@; the ⋯ %@",
              row ? NSStringFromClass(row.class) : @"nothing",
              row ? NSStringFromCGRect(SGFrameIn(row, host)) : @"(none)",
              like.superview ? NSStringFromClass(like.superview.class) : @"nothing",
              title ? NSStringFromClass(title.class) : @"nothing",
              sg_more ? NSStringFromClass(sg_more.class) : @"nothing");
    }
}

%hook _TtC20NowPlaying_ModesImpl18HeaderElementsUnit
- (void)viewDidLayoutSubviews {
    %orig;
    glassHeader((UIViewController *)self, YES);
    // Once the ⋯ is in the title row it has left this view and the walk is skipped. A header that was
    // rebuilt keeps a fresh ⋯ of its own: that one is taken and the moved one, wherever it stands, goes, so
    // the row never shows two. The identifier's view is taken whatever its class, since the phone that stayed
    // broken was one where it is not a UIButton; that view is also what the menu front, the press and the
    // popover anchor were put on (PlayerHeader's own pass), so the move takes all of them along.
    UIStackView *row = sg_row;
    if (!sg_more || !(row && sg_more.superview == row)) {
        UIView *found = SGRFindByIdentifier(((UIViewController *)self).viewIfLoaded, @"Context menu", &kMoreRowKey);
        if (found && found != sg_more) {
            UIView *old = sg_more;
            if (old && old.superview) {
                if ([old.superview isKindOfClass:UIStackView.class]
                    && [((UIStackView *)old.superview).arrangedSubviews containsObject:old]) {
                    [(UIStackView *)old.superview removeArrangedSubview:old];
                }
                [old removeFromSuperview];
            }
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
