// The listener's glass and Saved mark's dot in an iOS simulator: Redesigned/Kit/SGRGlass.m and SGRPlainCheck.x (through
// Logos) as they are, over Spotify's add button and a few controls of the harness's own. The settings are launch
// arguments, read at launch as on the phone; what each scene expects is a launch argument too, a literal check.sh
// gives, never read back from the code under test. Each scene prints `SHOT <name>` and holds still for
// kShotHold seconds so check.sh can take the simulator's screenshot, and ends with `PASS <scene>`; a failed check
// exits nonzero through harness-fail.h.
//
//     glass   a row of glass circles and two capsules (one prominent) over a coloured field: the effect is UIGlassEffect in
//             the material and tint expected (-harness.wantMaterial regular|clear, -harness.wantTint none|light|dark)
//             and interactive as expected (-harness.wantInteractive YES|NO), the same after the glass is hidden and
//             shown again (SGRShowGlass); under -harness.reduceTransparency YES every shape is the solid fill instead.
//             With -harness.changeAfterLaunch YES as well, the first shape is the solid fill, then every choice is
//             stored changed and Reduce Transparency goes off: the glass made after is still the launch's choices.
//     touch   one glass button held for kHoldSeconds by a finger made the way UIKit's own arrive (../tabbar/touch.m),
//             screenshots at rest and held; the button tracks the finger and its action runs once either way. Then
//             the button disabled and held again: no action, and a screenshot check.sh compares with the rest one.
//             -harness.arrangement inside puts the glass in the button; sibling puts it in a holder of its own beneath
//             the button, as Home's pill, told the button it backs (SGRGlassBacks).
//     rows    a list of Spotify's add buttons, every third song saved (-spotifyglass.redesign.savedMark 2, Dot): saved
//             rows show the accent dot and nothing of Spotify's tick, unsaved ones Spotify's own plus; again after the
//             list is scrolled so its cells are reused for songs of the other state, after a saved song is unsaved
//             by a tap on its button (Spotify's action, here the mock's), and after it is saved again. The buttons
//             keep their action, selected state, size and accessibility label.
#import <objc/runtime.h>
#import <UIKit/UIKit.h>
#import "Core/SGPrefs.h"
#import "Redesigned/Kit/SGRGlass.h"
#import "Redesigned/Kit/SGRAccent.h"
#import "Redesigned/Kit/SGRRefinements.h"
#import "Redesigned/Kit/SGRTokens.h"
#import "../harness-fail.h"

void SGHarnessHold(UIWindow *window, CGPoint point, NSTimeInterval seconds);
void SGHarnessTap(UIWindow *window, CGPoint point);

static const NSTimeInterval kShotHold = 2.0, kHoldSeconds = 3.0;
static NSUInteger sg_checks;
#define CHECK(condition, ...) do { sg_checks++; if (!(condition)) HARNESS_FAIL(__VA_ARGS__); } while (0)

#pragma mark - test doubles for the Kit around the code under test

BOOL SGRedesignedUI(void) { return YES; }
// The system's setting cannot be switched from inside the app; the launch argument stands in for it at launch, and a
// scene may switch it off as the listener would.
static BOOL sg_reduceTransparency;
BOOL SGRReduceTransparency(void) { return sg_reduceTransparency; }
UIColor *SGRSolidGlassFill(void) { return [UIColor colorWithWhite:1 alpha:0.16]; }
UIColor *SGRPrimary(void) { return UIColor.whiteColor; }
// The redesign's own green.
UIColor *SGRAccent(void) { return [UIColor colorWithRed:0x37 / 255.0 green:0xF2 / 255.0 blue:0 alpha:1]; }

#pragma mark - steps

// Runs the steps one after another on the main queue, each after the last one's wait.
typedef NSTimeInterval (^Step)(void);
static void runSteps(NSArray<Step> *steps, NSUInteger index) {
    if (index >= steps.count) return;
    NSTimeInterval wait = steps[index]();
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(wait * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ runSteps(steps, index + 1); });
}

static NSTimeInterval shot(NSString *name) {
    printf("SHOT %s\n", name.UTF8String);
    fflush(stdout);
    return kShotHold;
}

static void pass(NSString *scene) {
    printf("PASS %s: %lu checks\n", scene.UTF8String, (unsigned long)sg_checks);
    fflush(stdout);
    exit(0);
}

static NSString *argument(NSString *name) {
    NSString *value = [NSUserDefaults.standardUserDefaults stringForKey:name];
    if (!value.length) HARNESS_FAIL(@"-%@ is missing", name);
    return value;
}

#pragma mark - the field behind the glass

// Stripes of colour and a line of text, so the material and the tint show in a screenshot.
static UIView *field(CGRect frame) {
    UIView *view = [[UIView alloc] initWithFrame:frame];
    view.backgroundColor = UIColor.blackColor;
    NSArray<UIColor *> *colours = @[UIColor.systemPinkColor, UIColor.systemOrangeColor, UIColor.systemYellowColor,
                                    UIColor.systemGreenColor, UIColor.systemTealColor, UIColor.systemBlueColor,
                                    UIColor.systemPurpleColor, UIColor.whiteColor, UIColor.blackColor];
    CGFloat width = frame.size.width / colours.count;
    for (NSUInteger i = 0; i < colours.count; i++) {
        UIView *stripe = [[UIView alloc] initWithFrame:CGRectMake(i * width, 0, ceil(width), frame.size.height)];
        stripe.backgroundColor = colours[i];
        [view addSubview:stripe];
    }
    for (NSUInteger line = 0; line < 12; line++) {
        UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(8, 120 + line * 56, frame.size.width - 16, 40)];
        label.text = @"Retrine glass Retrine glass Retrine glass";
        label.font = [UIFont boldSystemFontOfSize:28];
        label.textColor = line % 2 ? UIColor.blackColor : UIColor.whiteColor;
        [view addSubview:label];
    }
    return view;
}

// A control with a glyph, as Spotify's and the Kit's are: the glyph does not change when the control is held, so a
// screenshot shows only what the glass does.
static UIButton *glyphButton(CGRect frame, NSString *symbol, id target, SEL action) {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    button.frame = frame;
    button.adjustsImageWhenHighlighted = NO;
    button.adjustsImageWhenDisabled = NO;
    UIImageSymbolConfiguration *configuration = [UIImageSymbolConfiguration configurationWithPointSize:22 weight:UIImageSymbolWeightSemibold];
    [button setImage:[UIImage systemImageNamed:symbol withConfiguration:configuration] forState:UIControlStateNormal];
    button.tintColor = UIColor.whiteColor;
    button.accessibilityLabel = symbol;
    if (action) [button addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}

#pragma mark - glass

static char kCircleKeys[3], kCapsuleKey, kProminentKey;

// The material is checked where the Kit asks UIKit for it: an effect view hands back a glass rebuilt without its style
// (iOS 26.5 answers Regular for a Clear one, while the screen shows Clear), so the styles asked of
// +[UIGlassEffect effectWithStyle:] are recorded on their way to UIKit's own.
static NSMutableArray<NSNumber *> *sg_stylesAsked;
static IMP sg_effectWithStyle;

static UIGlassEffect *recordStyle(id self, SEL _cmd, UIGlassEffectStyle style) {
    [sg_stylesAsked addObject:@(style)];
    return ((UIGlassEffect *(*)(id, SEL, UIGlassEffectStyle))sg_effectWithStyle)(self, _cmd, style);
}

static void recordStyles(void) {
    sg_stylesAsked = [NSMutableArray array];
    Method method = class_getClassMethod(UIGlassEffect.class, @selector(effectWithStyle:));
    sg_effectWithStyle = method_setImplementation(method, (IMP)recordStyle);
}

static void expectStyles(NSUInteger count, NSString *when) {
    if (sg_reduceTransparency) count = 0;
    CHECK(sg_stylesAsked.count == count, @"%@: %lu glass effects asked for, want %lu", when, (unsigned long)sg_stylesAsked.count,
          (unsigned long)count);
    if (!count) return;
    NSString *want = argument(@"harness.wantMaterial");
    for (NSNumber *style in sg_stylesAsked) {
        NSString *material = style.integerValue == UIGlassEffectStyleClear ? @"clear" : style.integerValue == UIGlassEffectStyleRegular ? @"regular" : @"?";
        CHECK([material isEqualToString:want], @"%@: material %@ (style %@), want %@", when, material, style, want);
    }
}

static void expectShape(UIView *shape, NSString *what) {
    if (sg_reduceTransparency) {
        // The prominent capsule's fill is the same white, stronger.
        CGFloat white = -1, alpha = 0, solidWhite = -2, solidAlpha = 0;
        [shape.backgroundColor getWhite:&white alpha:&alpha];
        [SGRSolidGlassFill() getWhite:&solidWhite alpha:&solidAlpha];
        CHECK(![shape isKindOfClass:UIVisualEffectView.class] && white == solidWhite && alpha >= solidAlpha && alpha < 1,
              @"%@: Reduce Transparency gives %@ filled %@, not the solid fill", what, shape.class, shape.backgroundColor);
        return;
    }
    CHECK([shape isKindOfClass:UIVisualEffectView.class], @"%@: %@ is no effect view", what, shape.class);
    UIVisualEffect *effect = ((UIVisualEffectView *)shape).effect;
    CHECK([effect isKindOfClass:UIGlassEffect.class], @"%@: the effect is %@, not glass", what, effect.class);
    UIGlassEffect *glass = (UIGlassEffect *)effect;
    CGFloat white = -1, alpha = -1;
    NSString *tint = !glass.tintColor ? @"none" : ![glass.tintColor getWhite:&white alpha:&alpha] ? @"?"
                   : alpha <= 0 || alpha >= 1 ? @"opaque or clear" : white >= 0.99 ? @"light" : white <= 0.01 ? @"dark" : @"?";
    CHECK([tint isEqualToString:argument(@"harness.wantTint")], @"%@: tint %@ (%@), want %@", what, tint, glass.tintColor,
          argument(@"harness.wantTint"));
    BOOL wantInteractive = [argument(@"harness.wantInteractive") boolValue];
    CHECK(glass.isInteractive == wantInteractive, @"%@: interactive %d, want %d", what, glass.isInteractive, wantInteractive);
    CHECK(!shape.userInteractionEnabled, @"%@: the shape takes touches from its control", what);
}

static void glassScene(UIWindow *window) {
    UIView *root = window.rootViewController.view;
    [root addSubview:field(root.bounds)];
    NSMutableArray<UIButton *> *buttons = [NSMutableArray array];
    NSArray *symbols = @[@"ellipsis", @"heart.fill", @"arrow.down"];
    for (NSUInteger i = 0; i < 3; i++) [buttons addObject:glyphButton(CGRectMake(70 + i * 96, 200, 64, 64), symbols[i], nil, NULL)];
    [buttons addObject:glyphButton(CGRectMake(60, 320, 280, 56), @"shuffle", nil, NULL)];
    [buttons addObject:glyphButton(CGRectMake(60, 420, 280, 56), @"play.fill", nil, NULL)];
    for (UIButton *button in buttons) [root addSubview:button];
    // The buttons lay their glyphs out first, as the controls the redesign puts glass in have theirs.
    [root layoutIfNeeded];
    BOOL changeAfterLaunch = [NSUserDefaults.standardUserDefaults boolForKey:@"harness.changeAfterLaunch"];
    if (changeAfterLaunch) {
        // Launched under Reduce Transparency: the first shape is the solid fill and no glass is made. Then every choice
        // is changed and Reduce Transparency switched off; the glass made now is still the launch's.
        CHECK(sg_reduceTransparency, @"-harness.changeAfterLaunch needs -harness.reduceTransparency YES");
        expectShape(SGRGlassInside(buttons[0], &kCircleKeys[0], 56), @"at launch, under Reduce Transparency");
        SGSetInt(SGRKeyGlassMaterial, SGRGlassMaterialClear);
        SGSetInt(SGRKeyGlassTint, SGRGlassTintDark);
        SGSetEnabled(SGRKeyGlassInteractive, NO);
        CHECK(SGRStoredGlassMaterial() == SGRGlassMaterialClear && SGRStoredGlassTint() == SGRGlassTintDark,
              @"the changed choices were not stored");
        sg_reduceTransparency = NO;
    }
    [sg_stylesAsked removeAllObjects];
    NSMutableArray<UIView *> *shapes = [NSMutableArray array];
    for (NSUInteger i = 0; i < 3; i++) [shapes addObject:SGRGlassInside(buttons[i], &kCircleKeys[i], 56)];
    [shapes addObject:SGRGlassCapsuleInside(buttons[3], &kCapsuleKey, buttons[3].bounds.size, NO)];
    [shapes addObject:SGRGlassCapsuleInside(buttons[4], &kProminentKey, buttons[4].bounds.size, YES)];
    for (NSUInteger i = 0; i < shapes.count; i++) expectShape(shapes[i], [NSString stringWithFormat:@"shape %lu", (unsigned long)i]);
    expectStyles(shapes.count, @"made");
    NSString *name = [NSString stringWithFormat:@"glass-%@", argument(@"harness.shot")];
    runSteps(@[
        ^NSTimeInterval { return shot(name); },
        ^NSTimeInterval {
            // Hidden and shown again by its effect, as the player and the lyrics do: the same glass comes back.
            for (UIView *shape in shapes) SGRShowGlass(shape, NO);
            for (UIView *shape in shapes) SGRShowGlass(shape, YES);
            for (NSUInteger i = 0; i < shapes.count; i++) expectShape(shapes[i], [NSString stringWithFormat:@"shape %lu shown again", (unsigned long)i]);
            expectStyles(2 * shapes.count, @"shown again");
            if (changeAfterLaunch) {
                // The changes are this scene's own; later launches in the simulator start from nothing stored.
                for (NSString *key in @[SGRKeyGlassMaterial, SGRKeyGlassTint, SGRKeyGlassInteractive]) [NSUserDefaults.standardUserDefaults removeObjectForKey:key];
                [NSUserDefaults.standardUserDefaults synchronize];
            }
            pass(@"glass");
            return 0;
        },
    ], 0);
}

#pragma mark - touch

@interface TouchTarget : NSObject
@property (nonatomic) NSUInteger actions;
@end
@implementation TouchTarget
- (void)act { self.actions++; }
@end

static char kTouchGlassKey;

static void touchScene(UIWindow *window) {
    UIView *root = window.rootViewController.view;
    [root addSubview:field(root.bounds)];
    static TouchTarget *target;
    target = [TouchTarget new];
    CGRect frame = CGRectMake(141, 300, 120, 120);
    UIButton *button = glyphButton(frame, @"heart.fill", target, @selector(act));
    NSString *arrangement = argument(@"harness.arrangement");
    if ([arrangement isEqualToString:@"inside"]) {
        [root addSubview:button];
        [root layoutIfNeeded];
        SGRGlassInside(button, &kTouchGlassKey, 104);
    } else if ([arrangement isEqualToString:@"sibling"]) {
        // As Home's pill: the glass in a holder of its own that takes no touch, the button beside it on top, and the
        // glass told the button it backs.
        UIView *holder = [[UIView alloc] initWithFrame:frame];
        holder.userInteractionEnabled = NO;
        [root addSubview:holder];
        [root addSubview:button];
        [root layoutIfNeeded];
        SGRGlassBacks(SGRGlassInside(holder, &kTouchGlassKey, 104), button);
    } else {
        HARNESS_FAIL(@"unknown arrangement %@", arrangement);
    }
    CGPoint middle = [root convertPoint:CGPointMake(CGRectGetMidX(button.frame), CGRectGetMidY(button.frame)) toView:window];
    NSString *mode = argument(@"harness.shot");
    runSteps(@[
        ^NSTimeInterval { return shot([NSString stringWithFormat:@"touch-%@-rest", mode]); },
        ^NSTimeInterval { SGHarnessHold(window, middle, kHoldSeconds); return 1.2; },
        ^NSTimeInterval {
            CHECK(button.isTracking && button.isHighlighted, @"held: the button is not tracking the finger");
            return shot([NSString stringWithFormat:@"touch-%@-held", mode]);
        },
        ^NSTimeInterval { return kHoldSeconds; },
        ^NSTimeInterval {
            CHECK(target.actions == 1, @"after the hold: the button's action ran %lu times, want 1", (unsigned long)target.actions);
            CHECK(button.isEnabled && button.userInteractionEnabled, @"after the hold: the button was disabled");
            button.enabled = NO;
            SGHarnessHold(window, middle, kHoldSeconds);
            return 1.2;
        },
        ^NSTimeInterval { return shot([NSString stringWithFormat:@"touch-%@-disabled-held", mode]); },
        ^NSTimeInterval { return kHoldSeconds; },
        ^NSTimeInterval {
            CHECK(target.actions == 1, @"a disabled button's action ran");
            pass(@"touch");
            return 0;
        },
    ], 0);
}

#pragma mark - rows

static Class lottieClass(void) {
    static Class lottie;
    if (!lottie) {
        lottie = objc_allocateClassPair(UIView.class, "Lottie.LottieAnimationView", 0);
        objc_registerClassPair(lottie);
    }
    return lottie;
}

static NSString *const kAddLabel = @"Add to Liked Songs", *const kSavedLabel = @"Remove from Liked Songs";

// A song's row with Spotify's add button: a UIButton whose Lottie animation (a mock under its class name) draws
// Spotify's plus or its circled tick, and whose selected state and label say whether the song is saved.
@interface SongCell : UITableViewCell
@property (nonatomic, strong) UIButton *add;
@property (nonatomic, strong) UIView *animation;
@property (nonatomic, strong) UIImageView *spotifyGlyph;
@property (nonatomic) NSInteger song;
@end

@implementation SongCell
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier {
    if (!(self = [super initWithStyle:style reuseIdentifier:identifier])) return nil;
    self.backgroundColor = UIColor.blackColor;
    self.textLabel.textColor = UIColor.whiteColor;
    _add = [UIButton buttonWithType:UIButtonTypeCustom];
    _add.accessibilityIdentifier = @"Components.UI.AddToButton";
    UIView *state = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 48, 48)];
    state.userInteractionEnabled = NO;
    _animation = [[lottieClass() alloc] initWithFrame:state.bounds];
    _spotifyGlyph = [[UIImageView alloc] initWithFrame:_animation.bounds];
    _spotifyGlyph.contentMode = UIViewContentModeCenter;
    [_animation addSubview:_spotifyGlyph];
    [state addSubview:_animation];
    [_add addSubview:state];
    [self.contentView addSubview:_add];
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.add.frame = CGRectMake(self.contentView.bounds.size.width - 64, (self.contentView.bounds.size.height - 48) / 2, 48, 48);
}

// What Spotify does when it binds a row to a song or the song's saved state changes.
- (void)showSaved:(BOOL)saved {
    UIImageSymbolConfiguration *configuration = [UIImageSymbolConfiguration configurationWithPointSize:24 weight:UIImageSymbolWeightRegular];
    self.spotifyGlyph.image = [UIImage systemImageNamed:saved ? @"checkmark.circle.fill" : @"plus.circle" withConfiguration:configuration];
    self.spotifyGlyph.tintColor = saved ? [UIColor colorWithRed:0.12 green:0.84 blue:0.38 alpha:1] : UIColor.lightGrayColor;
    self.add.accessibilityLabel = saved ? kSavedLabel : kAddLabel;
    self.add.selected = saved;
}
@end

@interface RowsController : UITableViewController
@property (nonatomic, strong) NSMutableSet<NSNumber *> *saved;
@property (nonatomic) NSUInteger actions;
@end

static const NSInteger kSongs = 40;

@implementation RowsController
- (instancetype)init {
    if (!(self = [super initWithStyle:UITableViewStylePlain])) return nil;
    _saved = [NSMutableSet set];
    for (NSInteger song = 0; song < kSongs; song++) if (song % 3 == 1) [_saved addObject:@(song)];
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.backgroundColor = UIColor.blackColor;
    self.tableView.rowHeight = 64;
    [self.tableView registerClass:SongCell.class forCellReuseIdentifier:@"song"];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return kSongs; }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    SongCell *cell = [tableView dequeueReusableCellWithIdentifier:@"song" forIndexPath:path];
    cell.song = path.row;
    cell.textLabel.text = [NSString stringWithFormat:@"Song %ld", (long)path.row];
    [cell.add removeTarget:nil action:NULL forControlEvents:UIControlEventAllEvents];
    [cell.add addTarget:self action:@selector(toggle:) forControlEvents:UIControlEventTouchUpInside];
    [cell showSaved:[self.saved containsObject:@(path.row)]];
    return cell;
}

// Spotify's action: the song saved or unsaved, and the row's button told.
- (void)toggle:(UIButton *)button {
    self.actions++;
    SongCell *cell = (SongCell *)button.superview.superview;
    while (cell && ![cell isKindOfClass:SongCell.class]) cell = (SongCell *)cell.superview;
    NSNumber *song = @(cell.song);
    if ([self.saved containsObject:song]) [self.saved removeObject:song];
    else [self.saved addObject:song];
    [cell showSaved:[self.saved containsObject:song]];
}
@end

// The Kit's glyph is the button's one image view of its own (the mock's glyph sits inside the animation).
static UIImageView *kitGlyph(UIButton *button) {
    for (UIView *view in button.subviews) if ([view isKindOfClass:UIImageView.class]) return (UIImageView *)view;
    return nil;
}

static void expectRow(SongCell *cell, BOOL saved, NSString *when) {
    UIImageView *glyph = kitGlyph(cell.add);
    BOOL dotShown = glyph && glyph.alpha > 0.5 && [glyph.image.description containsString:@"circle.fill"];
    BOOL spotifyShown = cell.animation.alpha > 0.5;
    NSString *what = [NSString stringWithFormat:@"%@, song %ld (%@)", when, (long)cell.song, saved ? @"saved" : @"unsaved"];
    if (saved) {
        CHECK(dotShown && !spotifyShown, @"%@: dot %d, Spotify's tick %d", what, dotShown, spotifyShown);
        CHECK([glyph.tintColor isEqual:SGRAccent()] && [glyph.accessibilityIdentifier isEqualToString:SGRPlainCheckIdentifier],
              @"%@: the dot is not in the accent (%@)", what, glyph.tintColor);
        CHECK(!glyph.userInteractionEnabled && !glyph.isAccessibilityElement, @"%@: the dot takes touches or is an element", what);
        CHECK(CGRectEqualToRect(glyph.frame, cell.add.bounds), @"%@: the dot is not where the tick is", what);
    } else {
        CHECK(!dotShown && spotifyShown, @"%@: dot %d, Spotify's plus %d", what, dotShown, spotifyShown);
    }
    CHECK(cell.add.isSelected == saved && [cell.add.accessibilityLabel isEqualToString:saved ? kSavedLabel : kAddLabel]
          && cell.add.isEnabled && cell.add.userInteractionEnabled && CGSizeEqualToSize(cell.add.bounds.size, CGSizeMake(48, 48)),
          @"%@: the button is no longer Spotify's", what);
}

static NSArray<SongCell *> *visibleCells(RowsController *rows) {
    [rows.tableView layoutIfNeeded];
    NSMutableArray *cells = [NSMutableArray array];
    for (UITableViewCell *cell in rows.tableView.visibleCells) {
        // A row half under the screen's edges is left out of the checks: it is laid out but not seen.
        CGRect frame = [rows.tableView convertRect:cell.frame toView:nil];
        if (CGRectGetMinY(frame) >= 0 && CGRectGetMaxY(frame) <= rows.view.window.bounds.size.height) [cells addObject:cell];
    }
    return cells;
}

static void expectRows(RowsController *rows, NSString *when) {
    NSArray<SongCell *> *cells = visibleCells(rows);
    CHECK(cells.count >= 8, @"%@: only %lu rows on screen", when, (unsigned long)cells.count);
    for (SongCell *cell in cells) expectRow(cell, [rows.saved containsObject:@(cell.song)], when);
}

static void rowsScene(UIWindow *window) {
    static RowsController *rows;
    rows = [RowsController new];
    window.rootViewController = rows;
    [window layoutIfNeeded];
    static NSMapTable<SongCell *, NSNumber *> *before;
    static SongCell *chosen;
    runSteps(@[
        ^NSTimeInterval { expectRows(rows, @"at first"); return 0.1; },
        ^NSTimeInterval { return shot(@"rows-dot"); },
        ^NSTimeInterval {
            before = [NSMapTable weakToStrongObjectsMapTable];
            for (SongCell *cell in visibleCells(rows)) [before setObject:@([rows.saved containsObject:@(cell.song)]) forKey:cell];
            // Down by 13 rows a row at a time, laid out after each as a scroll is: the cells that go off the top come
            // back at the bottom for later songs, saved where the songs they showed were not and the other way round.
            for (NSInteger row = 1; row <= 13; row++) {
                rows.tableView.contentOffset = CGPointMake(0, row * rows.tableView.rowHeight - rows.tableView.adjustedContentInset.top);
                [rows.tableView layoutIfNeeded];
            }
            return 0.3;
        },
        ^NSTimeInterval {
            NSUInteger toSaved = 0, toUnsaved = 0;
            for (SongCell *cell in visibleCells(rows)) {
                NSNumber *was = [before objectForKey:cell];
                BOOL now = [rows.saved containsObject:@(cell.song)];
                if (was && !was.boolValue && now) toSaved++;
                if (was && was.boolValue && !now) toUnsaved++;
            }
            CHECK(toSaved && toUnsaved, @"scrolled: no cell was reused for a song of the other state (%lu to saved, %lu to unsaved)",
                  (unsigned long)toSaved, (unsigned long)toUnsaved);
            expectRows(rows, @"scrolled, cells reused");
            return 0.1;
        },
        ^NSTimeInterval { return shot(@"rows-dot-scrolled"); },
        ^NSTimeInterval {
            for (SongCell *cell in visibleCells(rows)) if ([rows.saved containsObject:@(cell.song)] && cell.song > 14) { chosen = cell; break; }
            CHECK(chosen != nil, @"no saved song on screen to unsave");
            CGPoint middle = [chosen.add convertPoint:CGPointMake(24, 24) toView:nil];
            SGHarnessTap(window, middle);
            return 0.6;
        },
        ^NSTimeInterval {
            CHECK(rows.actions == 1, @"unsave: Spotify's action ran %lu times, want 1", (unsigned long)rows.actions);
            CHECK(![rows.saved containsObject:@(chosen.song)], @"unsave: song %ld is still saved", (long)chosen.song);
            expectRows(rows, @"after unsaving");
            return 0.1;
        },
        ^NSTimeInterval { printf("UNSAVED song %ld\n", (long)chosen.song); return shot(@"rows-dot-unsaved"); },
        ^NSTimeInterval {
            SGHarnessTap(window, [chosen.add convertPoint:CGPointMake(24, 24) toView:nil]);
            return 0.6;
        },
        ^NSTimeInterval {
            CHECK(rows.actions == 2 && [rows.saved containsObject:@(chosen.song)], @"save again: the song was not saved");
            expectRows(rows, @"saved again");
            pass(@"rows");
            return 0;
        },
    ], 0);
}

#pragma mark - the app

@interface GlassChoicesApp : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation GlassChoicesApp
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    UIViewController *root = [UIViewController new];
    root.view.backgroundColor = UIColor.blackColor;
    self.window.rootViewController = root;
    NSString *scene = argument(@"harness.scene");
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (!self.window.windowScene) HARNESS_FAIL(@"the window never joined a scene");
        if ([scene isEqualToString:@"glass"]) glassScene(self.window);
        else if ([scene isEqualToString:@"touch"]) touchScene(self.window);
        else if ([scene isEqualToString:@"rows"]) rowsScene(self.window);
        else HARNESS_FAIL(@"unknown scene %@", scene);
    });
    return YES;
}
@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        recordStyles();
        sg_reduceTransparency = [NSUserDefaults.standardUserDefaults boolForKey:@"harness.reduceTransparency"];
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(GlassChoicesApp.class));
    }
}
