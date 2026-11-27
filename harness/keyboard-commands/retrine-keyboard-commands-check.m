// What Shared/Keyboard promises with no app running: SGKeyboardVolumeAfterStep's grid, the command table in
// KeyboardCommands.m, and the reading of a described window list the Esc/⌘W gate is built on. Expected values are the
// spec's (16 steps, 6.25 percentage points, 0–100%), the keyboard's own keys, never read back out of the table. The
// front screen itself is Core's SGTopController and is checked against real UIKit controller trees by
// harness/keyboard-top-controller.
#import <UIKit/UIKit.h>
#import <math.h>
#import <stdio.h>
#import "Shared/Keyboard/Keyboard.h"
#import "../dispatch-clock.h"
#define dispatch_time HarnessTime
#define dispatch_after HarnessAfter
#import "Shared/Keyboard/KeyboardCommands.m"
#undef dispatch_after
#undef dispatch_time

static int failures;

static void expectValue(const char *what, double got, double want) {
    if (fabs(got - want) < 1e-9) return;
    printf("FAIL %s: got %.6f, want %.6f\n", what, got, want);
    failures++;
}

static void expectText(const char *what, NSString *got, NSString *want) {
    if (got == want || [got isEqualToString:want]) return;
    printf("FAIL %s: got %s, want %s\n", what, got.UTF8String ?: "(nil)", want.UTF8String ?: "(nil)");
    failures++;
}

static void expectFlag(const char *what, BOOL got, BOOL want) {
    if (got == want) return;
    printf("FAIL %s: got %s, want %s\n", what, got ? "YES" : "NO", want ? "YES" : "NO");
    failures++;
}

// The grid: a press moves one 6.25 point step, the volume snaps onto a point, and both ends hold.
static void checkVolumeGrid(void) {
    expectValue("up from 0", SGKeyboardVolumeAfterStep(0, YES), 0.0625);
    expectValue("down from 0 holds", SGKeyboardVolumeAfterStep(0, NO), 0);
    expectValue("up from 0.0625", SGKeyboardVolumeAfterStep(0.0625, YES), 0.125);
    expectValue("down from 0.0625", SGKeyboardVolumeAfterStep(0.0625, NO), 0);
    expectValue("down from 0.9375", SGKeyboardVolumeAfterStep(0.9375, NO), 0.875);
    expectValue("up from 0.9375", SGKeyboardVolumeAfterStep(0.9375, YES), 1);
    expectValue("up from 1 holds", SGKeyboardVolumeAfterStep(1, YES), 1);
    expectValue("down from 1", SGKeyboardVolumeAfterStep(1, NO), 0.9375);
    // Between points the volume snaps the way it is pressed: up to the next point, down to the previous one. These
    // are off the grid (16 steps put its points 0.0625 apart), so a press moves less than a step.
    expectValue("up from 0.53", SGKeyboardVolumeAfterStep(0.53, YES), 0.5625);
    expectValue("down from 0.53", SGKeyboardVolumeAfterStep(0.53, NO), 0.5);
    expectValue("up from 0.97", SGKeyboardVolumeAfterStep(0.97, YES), 1);
    expectValue("down from 0.97", SGKeyboardVolumeAfterStep(0.97, NO), 0.9375);
    expectValue("up from 0.01", SGKeyboardVolumeAfterStep(0.01, YES), 0.0625);
    expectValue("down from 0.01", SGKeyboardVolumeAfterStep(0.01, NO), 0);
    expectValue("up from 0.5 (on the grid)", SGKeyboardVolumeAfterStep(0.5, YES), 0.5625);
    expectValue("down from 0.5 (on the grid)", SGKeyboardVolumeAfterStep(0.5, NO), 0.4375);
    // The system reports a float, so a point can arrive a hair off; it is still that point.
    expectValue("up from 0.6875 off by a float", SGKeyboardVolumeAfterStep(0.6874999999, YES), 0.75);
    expectValue("down from 0.6875 off by a float", SGKeyboardVolumeAfterStep(0.6875000001, NO), 0.625);
    // Whatever the system says, the grid is 0–100%.
    expectValue("down from -1", SGKeyboardVolumeAfterStep(-1, NO), 0);
    expectValue("up from 2", SGKeyboardVolumeAfterStep(2, YES), 1);
    expectValue("up from NaN", SGKeyboardVolumeAfterStep(NAN, YES), 0.0625);
}

static void checkCommands(void) {
    NSUInteger count = SGKeyboardCommandCount();
    const SGKeyboardCommand *table = SGKeyboardCommands();
    NSMutableSet *bindings = [NSMutableSet set];
    NSString *escapeAction = nil, *commandWAction = nil;
    for (NSUInteger i = 0; i < count; i++) {
        NSString *input = SGKeyboardCommandInput(&table[i]);
        NSArray *binding = @[input, @(table[i].modifiers)];
        expectFlag("input and modifier pair does not collide", [bindings containsObject:binding], NO);
        [bindings addObject:binding];
        expectFlag("only bare space yields to focused controls", table[i].needsSpace,
                   [input isEqual:@" "] && table[i].modifiers == 0);
        if ([input isEqual:UIKeyInputEscape] && !table[i].modifiers) escapeAction = table[i].actionName;
        if ([input isEqual:@"w"] && table[i].modifiers == UIKeyModifierCommand) commandWAction = table[i].actionName;
    }
    expectFlag("Esc and command-W are available", escapeAction.length && commandWAction.length, YES);
    expectText("Esc and command-W close through the same action", escapeAction, commandWAction);
}

// Whether a window of its own covers the app window: same scene, above it, visible, opaque, overlapping — and not
// one of the system's keyboard or text-effects windows, which are always up beside a keyboard.
static void checkWindowCover(void) {
    const CGRect screen = {{0, 0}, {402, 874}};
    SGKeyboardWindow keyboard = {UIWindowLevelNormal + 1000, NO, 1, YES, screen, @"UIRemoteKeyboardWindow"};
    expectFlag("the keyboard window alone covers nothing", SGKeyboardWindowCovers(&keyboard, 1, UIWindowLevelNormal, screen), NO);
    SGKeyboardWindow effects = {UIWindowLevelNormal + 1000, NO, 1, YES, screen, @"UITextEffectsWindow"};
    expectFlag("the text effects window alone covers nothing", SGKeyboardWindowCovers(&effects, 1, UIWindowLevelNormal, screen), NO);
    SGKeyboardWindow menu = {UIWindowLevelNormal + 1, NO, 1, YES, screen, @"_UIContextMenuContainerView"};
    expectFlag("a context menu window covers", SGKeyboardWindowCovers(&menu, 1, UIWindowLevelNormal, screen), YES);
    expectFlag("a menu with the keyboard up covers", SGKeyboardWindowCovers((SGKeyboardWindow[]){menu, keyboard}, 2, UIWindowLevelNormal, screen), YES);
    // Above the app, but not covering what it shows.
    SGKeyboardWindow below = {UIWindowLevelNormal - 1, NO, 1, YES, screen, @"UIWindow"};
    expectFlag("a window below the app covers nothing", SGKeyboardWindowCovers(&below, 1, UIWindowLevelNormal, screen), NO);
    SGKeyboardWindow elsewhere = {UIWindowLevelNormal + 1, NO, 1, YES, CGRectMake(1000, 0, 402, 874), @"UIWindow"};
    expectFlag("a window on another display covers nothing", SGKeyboardWindowCovers(&elsewhere, 1, UIWindowLevelNormal, screen), NO);
    SGKeyboardWindow otherScene = {UIWindowLevelNormal + 1, NO, 1, NO, screen, @"UIWindow"};
    expectFlag("a window in another scene covers nothing", SGKeyboardWindowCovers(&otherScene, 1, UIWindowLevelNormal, screen), NO);
    SGKeyboardWindow hidden = {UIWindowLevelNormal + 1, YES, 1, YES, screen, @"UIWindow"};
    expectFlag("a hidden window covers nothing", SGKeyboardWindowCovers(&hidden, 1, UIWindowLevelNormal, screen), NO);
    SGKeyboardWindow invisible = {UIWindowLevelNormal + 1, NO, 0, YES, screen, @"UIWindow"};
    expectFlag("a transparent window covers nothing", SGKeyboardWindowCovers(&invisible, 1, UIWindowLevelNormal, screen), NO);
    expectFlag("no windows cover nothing", SGKeyboardWindowCovers(NULL, 0, UIWindowLevelNormal, screen), NO);
}

// A delayed run that a later press cancels: the stale run's delay and steps must do nothing at all — not even look at
// what is in front. This is ⌘F pressed twice within its 450 ms, where the first press's callback would otherwise press
// the Search bar too. Two things are observed by their own effect, not inferred: presses through a counting control,
// and the cursor through a real UIKit window — the run engine's press and focus steps are the ones under test.
typedef struct {
    int probes;
} RunTally;

// A target whose press is counted.
@interface HarnessPress : NSObject
@property (nonatomic, copy) void (^count)(void);
- (void)pressed;
@end

@implementation HarnessPress
- (void)pressed { if (self.count) self.count(); }
@end

// The responder the run's focus step is given. This check is a command-line tool with no application or window scene
// (a UIWindow cannot be made there), so real first-responder state cannot be observed: the responder records the call
// the engine makes instead, and reports whether it was already first responder. That is the engine's own contract on a
// Take answer — "make it first responder unless it already is" — observed at the responder, not inferred from a probe
// count.
@interface HarnessResponder : UIResponder
@property (nonatomic) BOOL alreadyFirstResponder;
@property (nonatomic) int becomeCalls;
@end

@implementation HarnessResponder
- (BOOL)canBecomeFirstResponder { return YES; }
- (BOOL)isFirstResponder { return self.alreadyFirstResponder; }
- (BOOL)becomeFirstResponder { self.becomeCalls++; self.alreadyFirstResponder = YES; return YES; }
@end

static void checkRunOwnership(void) {
    HarnessStartClock();
    HarnessResponder *field = [HarnessResponder new];
    __block RunTally stale = {0}, live = {0};
    // A control whose press is counted, so "pressed nothing" is observed rather than inferred.
    __block int controlPresses = 0;
    HarnessPress *press = [HarnessPress new];
    press.count = ^{ controlPresses++; };
    UIControl *control = [[UIControl alloc] initWithFrame:CGRectMake(0, 0, 44, 44)];
    [control addTarget:press action:@selector(pressed) forControlEvents:UIControlEventPrimaryActionTriggered];
    void (^pressControl)(UIControl *) = ^(UIControl *pressed) {
        [pressed sendActionsForControlEvents:UIControlEventPrimaryActionTriggered];
    };

    NSUInteger staleToken = SGKeyboardRunBegin(^SGKeyboardRunStep(UIControl **outControl, UIResponder **outField) {
        stale.probes++;
        *outControl = control;
        *outField = field;
        return SGKeyboardRunPress;   // would press, again and again, had it kept the work
    }, pressControl, 0.05, 0.02, 4);

    // A second press replaces it before the first one's delay is up: the live run waits a step, then takes the field.
    NSUInteger liveToken = SGKeyboardRunBegin(^SGKeyboardRunStep(UIControl **outControl, UIResponder **outField) {
        live.probes++;
        *outControl = nil;
        if (live.probes == 1) return SGKeyboardRunWait;
        *outField = field;
        return SGKeyboardRunTake;
    }, pressControl, 0.05, 0.02, 4);

    expectFlag("the later run owns the work", SGKeyboardRunOwns(liveToken), YES);
    expectFlag("the earlier run no longer owns it", SGKeyboardRunOwns(staleToken), NO);
    expectFlag("two runs get different tokens", staleToken != liveToken, YES);

    expectFlag("the field has no cursor before the run reaches it", field.isFirstResponder, NO);
    HarnessAdvanceClock(NSEC_PER_SEC);

    expectValue("the replaced run's callback never runs its probe", stale.probes, 0);
    expectValue("the replaced run pressed nothing", controlPresses, 0);
    expectValue("the live run probed exactly its two steps", live.probes, 2);
    // The run's focus step really asked the field it reported to take the cursor, once.
    expectValue("the live run asked its field to become first responder", field.becomeCalls, 1);
    expectFlag("that field now reports itself first responder", field.isFirstResponder, YES);

    // A field that already has the cursor is left alone: one more run, one Take, no second ask.
    HarnessResponder *alreadyFocused = [HarnessResponder new];
    alreadyFocused.alreadyFirstResponder = YES;
    SGKeyboardRunBegin(^SGKeyboardRunStep(UIControl **outControl, UIResponder **outField) {
        *outField = alreadyFocused;
        return SGKeyboardRunTake;
    }, pressControl, 0, 0.02, 3);
    HarnessAdvanceClock(NSEC_PER_SEC);
    expectValue("a field that already has the cursor is not asked again", alreadyFocused.becomeCalls, 0);

    // One ordered run whose first step is the activation: as ⌘F is one run now, the press cannot happen after the
    // focus steps have run out, and the focus cannot be taken before the press. An event log says which came first.
    {
        NSMutableArray<NSString *> *log = [NSMutableArray array];
        HarnessResponder *inputField = [HarnessResponder new];
        __block BOOL pressed = NO;
        __block int orderedPresses = 0;
        SGKeyboardRunBegin(^SGKeyboardRunStep(UIControl **outControl, UIResponder **outField) {
            if (!pressed) {
                *outControl = control;
                return SGKeyboardRunPress;
            }
            *outField = inputField;
            return SGKeyboardRunTake;
        }, ^(UIControl *pressedControl) {
            pressed = YES;
            orderedPresses++;
            [log addObject:@"press"];
            [pressedControl sendActionsForControlEvents:UIControlEventPrimaryActionTriggered];
        }, 0, 0.02, 4);
        HarnessAdvanceClock(NSEC_PER_SEC);
        [log addObject:inputField.becomeCalls ? @"focus" : @"no-focus"];
        expectFlag("one run presses first and then takes the field", [log isEqual:@[@"press", @"focus"]], YES);
        expectValue("the one run's press went through the caller's press block", orderedPresses, 1);
    }

    // Budget: a run that always waits probes exactly as many times as it was given steps, and no more.
    __block int waits = 0;
    NSUInteger budgetToken = SGKeyboardRunBegin(^SGKeyboardRunStep(UIControl **outControl, UIResponder **outField) {
        waits++;
        return SGKeyboardRunWait;
    }, pressControl, 0, 0.02, 10);
    HarnessAdvanceClock(NSEC_PER_SEC);
    HarnessStopClock();
    expectValue("ten attempts probe exactly ten times", waits, 10);
    expectFlag("the budgeted run still owns the work when it runs out", SGKeyboardRunOwns(budgetToken), YES);

    // A stale token given to the engine answers no, whatever the newest run's state.
    expectFlag("a token from before the newest run is not owned", SGKeyboardRunOwns(budgetToken - 1), NO);
}

int main(void) {
    @autoreleasepool {
        checkVolumeGrid();
        checkCommands();
        checkWindowCover();
        checkRunOwnership();
    }
    if (failures) {
        printf("retrine-keyboard-commands-check: %d failure(s)\n", failures);
        return 1;
    }
    printf("retrine-keyboard-commands-check: ok\n");
    return 0;
}
