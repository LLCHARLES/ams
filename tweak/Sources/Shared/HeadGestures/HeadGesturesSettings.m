// The AirPods gestures page: the switch, a pull-down of what each gesture does, then fitting them to the
// user: the teaching sheet, the sensitivity, Try it, which listens a few seconds and names what it picked up
// in its own row without doing anything to the song, and Forget.
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Settings/SGPageStyle.h"
#import "HeadGestures.h"

// Long enough to get the AirPods' attention and make a slow double nod.
static const double kTrySeconds = 6;

extern void SGHeadGesturesCancelTry(void (^done)(SGHeadGesture, BOOL));

@interface SGHeadGesturesPage : SGModPage
@property (nonatomic, copy) dispatch_block_t leave;
@property (nonatomic, copy) void (^trying)(SGHeadGesture, BOOL);
@end

@implementation SGHeadGesturesPage
- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    if (_leave) _leave();
}
@end

// SGHeadAction's names, in its order.
static NSArray<NSString *> *actionNames(void) {
    return @[SGL(@"settings.headgestures.action.nothing", @"Nothing"), SGL(@"settings.headgestures.action.back_15", @"Back 15 seconds"), SGL(@"settings.headgestures.action.forward_15", @"Forward 15 seconds"), SGL(@"settings.headgestures.action.play_pause", @"Play or pause"), SGL(@"settings.headgestures.action.next_track", @"Next track"), SGL(@"settings.headgestures.action.previous_track", @"Previous track"),
             SGL(@"settings.headgestures.action.shuffle", @"Shuffle"), SGL(@"settings.headgestures.action.repeat", @"Repeat"), SGL(@"settings.headgestures.action.like", @"Like")];
}

static BOOL headTracking(void) {
    if (SGHeadGesturesAvailable()) return YES;
    SGPresentInformation(SGTopController(), SGL(@"settings.headgestures.alert.no_tracking.title", @"No head tracking"), SGL(@"settings.headgestures.alert.no_tracking.message", @"This iPhone cannot read the motion of headphones."));
    return NO;
}

static NSString *learnedValue(void) {
    BOOL nod = SGInt(SGKeyHeadNod, 0) > 0, shake = SGInt(SGKeyHeadShake, 0) > 0;
    return nod && shake ? SGL(@"settings.headgestures.status.learned", @"Learned") : nod ? SGL(@"settings.headgestures.status.nod_learned", @"Nod learned") : shake ? SGL(@"settings.headgestures.status.shake_learned", @"Shake learned") : @"";
}

static BOOL anythingLearned(void) {
    return SGInt(SGKeyHeadNod, 0) > 0 || SGInt(SGKeyHeadShake, 0) > 0;
}

// Both learned sizes back to the defaults, asked first; `done` runs once they are.
static void forget(void (^done)(void)) {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:SGL(@"settings.headgestures.alert.forget.title", @"Forget your nod and shake?")
        message:SGL(@"settings.headgestures.alert.forget.message", @"Both go back to the default sizes. You can teach them again.") preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:SGL(@"settings.headgestures.action.forget", @"Forget") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        SGSetInt(SGKeyHeadNod, 0);
        SGSetInt(SGKeyHeadShake, 0);
        SGHeadGesturesSettingsChanged();
        done();
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:SGL(@"common.cancel", @"Cancel") style:UIAlertActionStyleCancel handler:nil]];
    SGPresentDark(alert);
    [SGTopController() presentViewController:alert animated:YES completion:nil];
}

static SGModRow *actionRow(NSString *title, SGHeadGesture gesture) {
    return SGMenuRow(title, actionNames(), ^NSString *{ return actionNames()[(NSUInteger)SGHeadGestureAction(gesture)]; },
                     ^(NSInteger index) { SGSetHeadGestureAction(gesture, index); });
}

UIViewController *SGHeadGesturesSettingsPage(void) {
    SGModRow *toggle = SGOptionRow(SGL(@"settings.headgestures.toggle.title", @"Head gestures"), SGL(@"settings.headgestures.toggle.subtitle", @"Nod twice or shake your head to control the music"), SGKeyHeadGestures);
    toggle.changed = ^(BOOL on) { SGHeadGesturesSettingsChanged(); };

    SGModRow *nodAction = SGWithSymbol(actionRow(SGL(@"settings.headgestures.nod.title", @"Nod twice"), SGHeadGestureDoubleNod), @"arrow.up.and.down");
    SGModRow *shakeAction = SGWithSymbol(actionRow(SGL(@"settings.headgestures.shake.title", @"Shake your head"), SGHeadGestureShake), @"arrow.left.and.right");
    SGModRow *chime = SGWithSymbol(SGSwitchRow(SGL(@"settings.headgestures.chime.title", @"Chime on activation"), nil, SGKeyHeadChime), @"bell");

    __block __weak SGHeadGesturesPage *page;
    __block NSString *tried = @"";
    SGModRow *teach = SGStatActionRow(SGL(@"settings.headgestures.teach.title", @"Teach your gestures"), SGL(@"settings.headgestures.teach.subtitle", @"Five of each, then 20 seconds of ordinary movement"), ^NSString *{ return learnedValue(); }, ^{
        if (!headTracking()) return;
        SGHeadGesturesCancelTry(page.trying);
        page.trying = nil;
        tried = @"";
        SGPresentHeadGesturesTeaching(page, ^{ [page refreshVisibility]; });
    });

    SGModRow *sensitivity = SGSliderRow(SGL(@"settings.headgestures.sensitivity.title", @"Sensitivity"), SGL(@"settings.headgestures.sensitivity.subtitle", @"Higher counts a smaller move"),
        SGHeadSensitivityMin, SGHeadSensitivityMax, SGHeadSensitivityStep,
        ^double { return MAX(SGHeadSensitivityMin, MIN(SGHeadSensitivityMax, SGInt(SGKeyHeadSensitivity, 100))); },
        ^(double value) {
            SGSetInt(SGKeyHeadSensitivity, lround(value));
            SGHeadGesturesSettingsChanged();
        },
        ^NSString *(double value) { return [NSString stringWithFormat:SGL(@"settings.headgestures.sensitivity.format", @"%ld%%"), lround(value)]; });

    // What the last try picked up, read out on its row until the next; a new page starts blank.
    SGModRow *tryRow = SGStatActionRow(SGL(@"settings.headgestures.try.title", @"Try it"), SGL(@"settings.headgestures.try.subtitle", @"Listens after the tone and says what it picked up"), ^NSString *{ return tried; }, ^{
        if (page.trying || !headTracking()) return;
        tried = SGL(@"settings.headgestures.try.listening", @"Listening…");
        [page.tableView reloadData];
        SGHeadGesturesCue(SGHeadCueReady);
        page.trying = ^(SGHeadGesture gesture, BOOL heard) {
            page.trying = nil;
            tried = gesture == SGHeadGestureDoubleNod ? SGL(@"settings.headgestures.try.nod", @"Nod twice") : gesture == SGHeadGestureShake ? SGL(@"settings.headgestures.try.shake", @"Head shake") : heard ? SGL(@"settings.headgestures.try.nothing", @"Nothing") : SGL(@"settings.headgestures.try.no_motion", @"No motion");
            SGHeadGesturesCue(gesture != SGHeadGestureNone ? SGHeadCueWorked : SGHeadCueFailed);
            NSString *spoken = gesture != SGHeadGestureNone ? [SGL(@"settings.headgestures.try.picked_up_lead", @"Picked up: ") stringByAppendingString:tried]
                             : heard ? SGL(@"settings.headgestures.try.picked_up_nothing", @"Picked up nothing. Try a bigger move, or raise Sensitivity.")
                                     : SGL(@"settings.headgestures.try.no_motion_hint", @"No motion came. Put in AirPods that track head motion.");
            UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, spoken);
            [page.tableView reloadData];
        };
        SGHeadGesturesTry(kTrySeconds, page.trying);
    });

    SGModRow *forgetRow = SGActionRow(SGL(@"settings.headgestures.forget.title", @"Forget what it learned"), nil, ^{ forget(^{ [page refreshVisibility]; }); });
    forgetRow.color = SGRed();
    forgetRow.visible = ^BOOL { return anythingLearned(); };
    for (SGModRow *row in @[nodAction, shakeAction, chime, teach, sensitivity, tryRow, forgetRow]) row.waitsOn = SGKeyHeadGestures;

    SGHeadGesturesPage *shown = [[SGHeadGesturesPage alloc] initWithTitle:SGL(@"settings.headgestures.page.title", @"AirPods gestures") intro:nil sections:@[
        SGSection(nil, @[SGWithSymbol(toggle, @"airpods.pro")]),
        SGNotedSection(SGL(@"settings.headgestures.section.gestures", @"Gestures"), @[nodAction, shakeAction, chime],
            SGL(@"settings.headgestures.section.gestures.footer", @"They work while Spotify plays through headphones that track head motion: AirPods Pro, AirPods (3rd "
            "generation and later), AirPods Max and some Beats. Set to Play or pause, they listen with a song paused too. With the chime on, a "
            "tone in the music confirms each, a rising pair when it worked and a low one when it did not, with the "
            "iPhone on silent too. iOS asks once for Motion & Fitness access, which is how Spotify reads the movement.")),
        SGNotedSection(SGL(@"settings.headgestures.section.fit.header", @"Fit to you"), @[teach, sensitivity, tryRow, forgetRow],
            SGL(@"settings.headgestures.section.fit.footer", @"Teaching sets how big a move counts from five of your own, checked against 20 seconds of ordinary movement. Sensitivity scales that for both. Try it does "
            "nothing to the music, so you can tune it while a song plays.")),
    ] footer:nil];
    page = shown;
    shown.leave = ^{
        if (!page.trying) return;
        SGHeadGesturesCancelTry(page.trying);
        page.trying = nil;
        tried = @"";
    };
    return shown;
}
