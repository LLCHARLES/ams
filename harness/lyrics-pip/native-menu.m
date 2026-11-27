#import "tests.h"
#import <objc/message.h>
#import "../dispatch-clock.h"
static CFTimeInterval menuTime(void) {
    return harnessTimers ? 100 + harnessNow / (double)NSEC_PER_SEC : CACurrentMediaTime();
}
// Logos transforms the real production hooks, including their existing player-sheet gate.
#define CACurrentMediaTime menuTime
#define dispatch_time HarnessTime
#define dispatch_after HarnessAfter
#import "SpeedPitchMenu.m"
#undef dispatch_after
#undef dispatch_time
#undef CACurrentMediaTime

void SGRequireClasses(NSArray *classes) {}
void SGPlayFeedback(SGFeedback feedback) {}
void SGPrepareFeedback(SGFeedback feedback) {}
static double testSpeed = 1;
static SGSpeedPitchSongs *menuSongOwner;
double SGPlayerSpeed(void) { return testSpeed; }
BOOL SGPlayerSpeedAllowed(void) { return YES; }
void SGSetPlayerSpeed(double speed) { testSpeed = speed; [menuSongOwner valuesChanged:@"speed"]; }
float SGPlayerPitch(void) { return 0; }
void SGSetPlayerPitch(float pitch) {}
BOOL SGPlayerPitchAvailable(void) { return YES; }
BOOL SGPlayerPitchFollowsSpeed(void) { return YES; }
void SGSetPlayerPitchFollowsSpeed(BOOL follows) {}
BOOL SGPlayerMenuOffersAnimatedArtwork(void) { return YES; }
BOOL SGPlayerMenuAnimatedArtwork(void) { return NO; }
void SGPlayerMenuSetAnimatedArtwork(BOOL on) {}
BOOL SGPlayerMenuReplaced(UIViewController *menu) { return NO; }
// The settings setters/readers are production; only preferences' switch access and the DSP engine
// transport are stood in for. No audio device is started by this headless host.
BOOL SGHidden(NSString *key) { return [NSUserDefaults.standardUserDefaults boolForKey:key]; }
void SGSetEnabled(NSString *key, BOOL on) { [NSUserDefaults.standardUserDefaults setBool:on forKey:key]; }
void SGDSPApply(NSString *effect) {}

static UIViewController *sheet(BOOL header) {
    UIViewController *menu = [UIViewController new];
    UITableView *table = [[UITableView alloc] initWithFrame:CGRectMake(0, 0, 390, 600)];
    if (header) table.tableHeaderView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 390, 80)];
    menu.view = table;
    return menu;
}
static UIButton *pipButton(SGSpeedPitchView *block) {
    for (UIView *view in block.subviews)
        if ([view isKindOfClass:UIButton.class] && [((UIButton *)view).currentTitle containsString:@"Picture in Picture"]) return (id)view;
    return nil;
}
static void tap(UIButton *button, SGSpeedPitchView *block) {
    // Selector-based UIControl dispatch goes through UIApplication, absent in this headless host.
    // Deliver its registered touch-up actions directly; UIAction-based dispatch needs no application.
    NSArray<NSString *> *actions = [button actionsForTarget:block forControlEvent:UIControlEventTouchUpInside];
    SGTestAssert(actions.count == 1, @"native PiP button has one touch-up action");
    for (NSString *action in actions) ((void (*)(id, SEL))objc_msgSend)(block, NSSelectorFromString(action));
}

static UISlider *speedSlider(UIView *view) {
    if ([view isKindOfClass:UISlider.class] && [view.accessibilityLabel isEqual:@"Speed"]) return (id)view;
    for (UIView *child in view.subviews) {
        UISlider *slider = speedSlider(child);
        if (slider) return slider;
    }
    return nil;
}

static void sliderEvent(UISlider *slider, SGSpeedPitchView *block, UIControlEvents event) {
    for (NSString *action in [slider actionsForTarget:block forControlEvent:event])
        ((void (*)(id, SEL, id))objc_msgSend)(block, NSSelectorFromString(action), slider);
}

static void playSong(NSString *uri) {
    SGTestSetTrack(uri, nil);
    [menuSongOwner playerStateDidReport:SGPlayerState()];
}

static void songControlTests(void) {
    NSUserDefaults *globals = NSUserDefaults.standardUserDefaults;
    NSArray *keys = @[SGKeyDSP, SGKeyDSPReverb, SGKeyDSPReverbAmount];
    NSMutableDictionary *saved = [NSMutableDictionary dictionary];
    for (NSString *key in keys) {
        saved[key] = [globals objectForKey:key] ?: NSNull.null;
        [globals removeObjectForKey:key];
    }
    NSString *priorTrack = SGTestTrackURI();
    NSString *suite = [@"dev.retrine.pip-song-controls." stringByAppendingString:NSUUID.UUID.UUIDString];
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:suite];
    menuSongOwner = [[SGSpeedPitchSongs alloc] initWithDefaults:defaults];
    playSong(@"spotify:track:gesture-a");
    [menuSongOwner setKept:YES];
    SGSetPlayerSpeed(1.25);
    SGPlayerSetReverb(20);
    playSong(@"spotify:track:gesture-b");
    [menuSongOwner setKept:YES];
    SGSetPlayerSpeed(0.75);
    SGPlayerSetReverb(30);
    playSong(@"spotify:track:gesture-a");

    SGSpeedPitchView *block = [SGSpeedPitchView new];
    UISlider *slider = speedSlider(block);
    SGTestAssert(slider != nil, @"speed slider is accessible to gesture tests");
    HarnessStartClock();
    sliderEvent(slider, block, UIControlEventTouchDown);
    slider.value = 1.5;
    sliderEvent(slider, block, UIControlEventValueChanged);
    SGTestAssert(SGPlayerSpeed() == 1.5, @"speed drag changes the current song");
    slider.value = 1.8;
    sliderEvent(slider, block, UIControlEventValueChanged); // coalesced slider send is still pending
    SGTestAssert(harnessTimers.count == 1, @"second drag queued a coalesced send");

    dispatch_async(dispatch_get_main_queue(), ^{ playSong(@"spotify:track:gesture-b"); });
    SGDSPSetNumber(SGKeyDSPReverbAmount, 65); // Settings edits A before the already-queued B report.
    SGTestAssert(SGTestPump(^BOOL{ return SGPlayerSpeed() == 0.75; }), @"queued track B is applied");
    slider.value = 1.9;
    sliderEvent(slider, block, UIControlEventValueChanged);
    sliderEvent(slider, block, UIControlEventTouchUpInside);
    SGTestAssert(SGPlayerSpeed() == 0.75, @"old drag and release cannot overwrite the new song");
    HarnessAdvanceClock(100 * NSEC_PER_MSEC);
    HarnessStopClock();
    SGTestAssert(SGPlayerSpeed() == 0.75,
        @"old coalesced slider send cannot change the new song");
    [menuSongOwner flush];
    NSDictionary *records = [defaults dictionaryForKey:@"spotifyglass.speedPitch.songs"];
    SGTestAssert([records[@"spotify:track:gesture-b"][@"speed"] doubleValue] == 0.75,
        @"new song record survives callbacks from the previous gesture");
    SGTestAssert([records[@"spotify:track:gesture-a"][@"reverb"] floatValue] == 65
        && [records[@"spotify:track:gesture-b"][@"reverb"] floatValue] == 30,
        @"Settings reverb edit belongs to A even when B's report was already queued");

    // A new gesture remains usable after the invalidated gesture has ended.
    sliderEvent(slider, block, UIControlEventTouchDown);
    slider.value = 1.5;
    sliderEvent(slider, block, UIControlEventValueChanged);
    sliderEvent(slider, block, UIControlEventTouchUpInside);
    SGTestAssert(SGPlayerSpeed() == 1.5, @"a fresh drag can change the new song");

    playSong(@"spotify:track:gesture-a");
    dispatch_async(dispatch_get_main_queue(), ^{ playSong(@"spotify:track:gesture-b"); });
    SGDSPSetSwitch(SGKeyDSPReverb, NO);
    SGTestAssert(SGTestPump(^BOOL{ return [SGTestTrackURI() isEqual:@"spotify:track:gesture-b"]; }), @"queued B follows reverb switch edit");
    playSong(@"spotify:track:gesture-a");
    SGTestAssert(SGPlayerReverb() == 0, @"Settings reverb switch-off stays with the edited song");
    SGPlayerSetReverb(50);
    dispatch_async(dispatch_get_main_queue(), ^{ playSong(@"spotify:track:gesture-b"); });
    SGDSPSetSwitch(SGKeyDSP, NO);
    SGTestAssert(SGTestPump(^BOOL{ return [SGTestTrackURI() isEqual:@"spotify:track:gesture-b"]; }), @"queued B follows master switch edit");
    playSong(@"spotify:track:gesture-a");
    SGTestAssert(SGPlayerReverb() == 0, @"Settings master switch-off records the edited song's effective reverb");

    SGPlayerSetReverb(50);
    [menuSongOwner flush];
    // dispatch_sync may execute on its calling thread; async plus a group guarantees a worker.
    dispatch_group_t backgroundWrites = dispatch_group_create();
    __block BOOL wroteOffMain = NO;
    dispatch_group_async(backgroundWrites, dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
        wroteOffMain = !NSThread.isMainThread;
        SGDSPSetNumber(SGKeyDSPReverbAmount, 75);
        SGDSPSetSwitch(SGKeyDSPReverb, NO);
        SGDSPSetSwitch(SGKeyDSP, NO);
    });
    dispatch_group_wait(backgroundWrites, DISPATCH_TIME_FOREVER);
    SGTestAssert(wroteOffMain, @"background settings fixture executes on a worker thread");
    __block BOOL backgroundWritesDrained = NO;
    dispatch_async(dispatch_get_main_queue(), ^{ backgroundWritesDrained = YES; });
    SGTestAssert(SGTestPump(^BOOL{ return backgroundWritesDrained; }), @"main queue drains after background settings writes");
    [menuSongOwner flush];
    SGTestAssert([[defaults dictionaryForKey:@"spotifyglass.speedPitch.songs"][@"spotify:track:gesture-a"][@"reverb"] floatValue] == 50,
        @"background settings writes neither update song records off-main nor dispatch a delayed update");
    SGTestAssert(SGDSPNumber(SGKeyDSPReverbAmount) == 75 && !SGDSPSwitch(SGKeyDSPReverb) && !SGDSPSwitch(SGKeyDSP),
        @"background settings writes retain their existing preference behavior");

    playSong(nil);
    menuSongOwner = nil;
    [defaults removePersistentDomainForName:suite];
    for (NSString *key in keys) {
        if (saved[key] == NSNull.null) [globals removeObjectForKey:key];
        else [globals setObject:saved[key] forKey:key];
    }
    SGTestSetTrack(priorTrack, nil);
    testSpeed = 1;
}

void SGTestNativeMenu(void) {
    songControlTests();
    // The disabled-guidance case must not inherit the preceding suite's enable gate.
    SGTestPiPState(NO, NO, NO);
    UIViewController *nonplayer = sheet(NO);
    install(nonplayer);
    SGTestAssert(((UITableView *)nonplayer.view).tableHeaderView == nil, @"album/track context without existing player marker has no row");
    for (NSNumber *footer in @[@NO, @YES]) {
        SGPlayerMenuMarkPlayers();
        UIViewController *menu = sheet(footer.boolValue);
        install(menu);
        UITableView *table = (id)menu.view;
        SGSpeedPitchView *block = (id)(footer.boolValue ? table.tableFooterView : table.tableHeaderView);
        install(menu);
        SGTestAssert(block == (footer.boolValue ? table.tableFooterView : table.tableHeaderView), @"native repeat layout does not duplicate block");
        [block layoutIfNeeded];
        UIButton *pip = pipButton(block);
        SGTestAssert(pip != nil && !pip.hidden && CGRectGetMaxY(pip.frame) <= block.bounds.size.height,
            @"native disabled PiP row visible outside collapsed speed panel");
        NSUInteger alerts = SGTestDisabledAlerts();
        tap(pip, block);
        SGTestAssert(SGTestDisabledAlerts() == alerts + 1, @"native row invokes shared disabled guidance");
        [block toggle];
        [block layoutSubviews];
        SGTestAssert(CGRectGetMaxY(pip.frame) <= block.bounds.size.height && !pip.hidden,
            @"native PiP stays outside expanded speed controls and artwork switch");
        [block toggle];
        SGTestPiPState(YES, NO, YES);
        [block refresh];
        SGTestAssert([pip.currentTitle isEqual:@"Close lyrics Picture in Picture"], @"native pending start label closes");
        tap(pip, block);
        SGTestAssert(!SGLyricsPiPStarting(), @"native PiP row cancels pending start");
        SGTestPiPState(NO, NO, NO);
        UIViewController *second = sheet(NO);
        install(second);
        SGTestAssert(((UITableView *)second.view).tableHeaderView == nil, @"consumed player marker cannot leak into nested menu");
    }
    SGSpeedPitchPanel *panel = [SGSpeedPitchPanel new];
    SGSpeedPitchView *block = (id)panel.view;
    SGTestAssert(pipButton(block).hidden, @"panel-only speed popup never shows PiP entry");

    SGPlayerMenuMarkPlayers();
    UIViewController *occupied = sheet(YES);
    UITableView *table = (id)occupied.view;
    UIView *header = table.tableHeaderView;
    UIView *footer = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 390, 73)];
    footer.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    UIButton *nativeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    nativeButton.frame = CGRectMake(8, 8, 120, 40);
    [footer addSubview:nativeButton];
    NSArray *nativeSubviews = footer.subviews;
    table.tableFooterView = footer;
    install(occupied);
    UIView *composed = table.tableFooterView;
    block = objc_getAssociatedObject(occupied, &kBlockKey);
    [block layoutIfNeeded];
    SGTestAssert(block && pipButton(block) && !pipButton(block).hidden, @"both occupied slots still expose native PiP entry");
    SGTestAssert(table.tableHeaderView == header && footer.superview == composed
        && [footer.subviews isEqual:nativeSubviews] && nativeButton.superview == footer,
        @"composition preserves exact native header/footer and footer subview ownership");
    SGTestAssert(footer.bounds.size.height == 73 && footer.autoresizingMask == (UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight)
        && composed.bounds.size.height == 73 + block.bounds.size.height && block.frame.origin.y == 73,
        @"composition adds block height without stretching native footer");
    NSUInteger alerts = SGTestDisabledAlerts();
    tap(pipButton(block), block);
    SGTestAssert(SGTestDisabledAlerts() == alerts + 1, @"composed PiP entry invokes shared disabled guidance");
    CGFloat closed = composed.bounds.size.height;
    [block toggle];
    [composed layoutIfNeeded];
    SGTestAssert(table.tableFooterView == composed && composed.bounds.size.height > closed
        && composed.bounds.size.height == footer.bounds.size.height + block.bounds.size.height
        && footer.bounds.size.height == 73 && CGRectEqualToRect(nativeButton.frame, CGRectMake(8, 8, 120, 40)),
        @"opening speed resizes composed footer without changing native content");
    [block toggle];
    [composed layoutIfNeeded];
    SGTestAssert(composed.bounds.size.height == closed && footer.bounds.size.height == 73,
        @"closing speed restores composed footer height");
    for (NSUInteger i = 0; i < 10; i++) install(occupied);
    SGTestAssert(table.tableFooterView == composed && composed.subviews.count == 2
        && [footer.subviews isEqual:nativeSubviews] && block.superview == composed,
        @"repeated installation never nests wrappers or duplicates native/footer controls");
    footer.frame = CGRectMake(0, 0, 390, 101);
    table.frame = CGRectMake(0, 0, 430, 600);
    install(occupied);
    SGTestAssert(footer.bounds.size.height == 101 && footer.bounds.size.width == 430
        && composed.bounds.size.height == 101 + block.bounds.size.height && block.frame.origin.y == 101,
        @"subsequent native footer height and table width updates propagate to composition");
    UIView *replacement = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 430, 61)];
    table.tableFooterView = replacement;
    install(occupied);
    UIView *recomposed = table.tableFooterView;
    install(occupied);
    SGTestAssert(recomposed != composed && table.tableFooterView == recomposed && replacement.superview == recomposed
        && block.superview == recomposed && recomposed.subviews.count == 2
        && nativeButton.superview == footer && table.tableHeaderView == header,
        @"native footer replacement preserves new content and moves exactly one existing PiP block");
    CGRect currentBlockFrame = block.frame;
    [composed setNeedsLayout];
    [composed layoutIfNeeded];
    SGTestAssert(CGRectEqualToRect(block.frame, currentBlockFrame) && block.superview == recomposed,
        @"stale wrapper layout cannot reposition block owned by replacement footer");
}
