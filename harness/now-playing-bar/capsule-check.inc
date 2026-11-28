@interface HarnessPlatterView : UIView @end
@implementation HarnessPlatterView @end

@interface HarnessBarLayoutView : UIView
@property (nonatomic) NSUInteger passes;
@end
@implementation HarnessBarLayoutView
- (void)layoutSubviews {
    [super layoutSubviews];
    self.passes++;
}
@end

static void checkPlatterInvalidation(void (^done)(void)) {
    UIViewController *container = [UIViewController new];
    HarnessBarLayoutView *view = [[HarnessBarLayoutView alloc] initWithFrame:CGRectMake(0, 0, 500, 76)];
    container.view = view;
    sg_container = container;
    sg_capsule = YES;
    UIView *platter = [[HarnessPlatterView alloc] initWithFrame:CGRectMake(0, 0, 280, 76)];
    [view addSubview:platter];
    [view layoutIfNeeded];
    watchTabGlass(platter);
    NSUInteger settled = view.passes;
    // UIKit assigns platter geometry during layout even when it has not moved.
    platter.frame = platter.frame;
    platter.bounds = platter.bounds;
    platter.center = platter.center;
    dispatch_async(dispatch_get_main_queue(), ^{
        HARNESS_CHECK(view.passes == settled);
        platter.center = CGPointMake(150, 38);
        dispatch_async(dispatch_get_main_queue(), ^{
            HARNESS_CHECK(view.passes > settled);
            watchTabGlass(nil);
            sg_container = nil;
            sg_capsule = NO;
            (void)container; // Keep the weak production owner alive through both deliveries.
            sg_checks++;
            NSLog(@"[harness] unchanged platter geometry leaves layout idle: PASS");
            done();
        });
    });
}

static BOOL whiteTint(UIColor *color) {
    CGFloat r, g, b, a;
    return [color getRed:&r green:&g blue:&b alpha:&a] && r == 1 && g == 1 && b == 1 && a == 1;
}

static void checkCapsule(void) {
    UIWindow *window = [(id)UIApplication.sharedApplication.delegate window];
    UIViewController *root = window.rootViewController;
    root.view.backgroundColor = [UIColor colorWithRed:0.06 green:0.09 blue:0.14 alpha:1];
    BOOL pad = window.traitCollection.userInterfaceIdiom == UIUserInterfaceIdiomPad;
    if (getenv("HARNESS_COMPACT")) window.traitOverrides.horizontalSizeClass = UIUserInterfaceSizeClassCompact;
    BOOL wide = pad && !getenv("HARNESS_COMPACT");
    BOOL rtl = getenv("HARNESS_RTL") != NULL;
    CGFloat width = root.view.bounds.size.width, height = wide ? 76 : 56;
    UIView *tabs = [[UIView alloc] initWithFrame:CGRectMake(rtl ? width - 304 : 24, root.view.bounds.size.height - 110, 280, height)];
    tabs.accessibilityIdentifier = @"elements-tabs-view-identifier";
    UIView *platter = [[HarnessPlatterView alloc] initWithFrame:tabs.bounds];
    platter.backgroundColor = [UIColor colorWithWhite:1 alpha:0.12];
    platter.layer.cornerRadius = height / 2;
    [tabs addSubview:platter];
    [root.view addSubview:tabs];
    UIViewController *container = [UIViewController new], *bar = [UIViewController new];
    [root addChildViewController:container];
    [root.view addSubview:container.view];
    container.view.frame = CGRectMake(wide ? (rtl ? 8 : width - 376) : 16, root.view.bounds.size.height - 110, wide ? 368 : width - 32, height);
    [container addChildViewController:bar];
    [container.view addSubview:bar.view];
    bar.view.frame = CGRectMake(8, 0, container.view.bounds.size.width - 16, height);
    UIView *card = [[UIView alloc] initWithFrame:bar.view.bounds];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.backgroundColor = UIColor.darkGrayColor;
    [bar.view addSubview:card];
    [NSLayoutConstraint activateConstraints:@[
        [card.leadingAnchor constraintEqualToAnchor:bar.view.leadingAnchor],
        [card.trailingAnchor constraintEqualToAnchor:bar.view.trailingAnchor],
        [card.topAnchor constraintEqualToAnchor:bar.view.topAnchor],
        [card.bottomAnchor constraintEqualToAnchor:bar.view.bottomAnchor]
    ]];
    CGFloat artSide = height - 16;
    UIImageView *cover = [[UIImageView alloc] initWithFrame:CGRectMake(rtl ? card.bounds.size.width - artSide - 8 : 8, 8, artSide, artSide)];
    if (rtl) cover.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    cover.image = [UIImage systemImageNamed:@"music.note"];
    cover.backgroundColor = UIColor.systemIndigoColor;
    cover.tintColor = UIColor.whiteColor;
    cover.layer.cornerRadius = 4;
    [card addSubview:cover];
    UILabel *title = [UILabel new];
    title.text = @"We Are The People";
    title.textColor = UIColor.whiteColor;
    title.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
    title.adjustsFontForContentSizeCategory = YES;
    UIStackView *buttons = [UIStackView new];
    UIButton *play = [UIButton buttonWithType:UIButtonTypeSystem];
    play.accessibilityIdentifier = kPlayId;
    play.accessibilityLabel = @"Play";
    if (!wide) play.tintColor = UIColor.whiteColor;
    [play setImage:[UIImage systemImageNamed:@"play.fill"] forState:UIControlStateNormal];
    [play.widthAnchor constraintEqualToConstant:44].active = YES;
    [buttons addArrangedSubview:play];
    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[title, buttons]];
    row.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:row];
    [NSLayoutConstraint activateConstraints:@[
        [row.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:height - 8],
        [row.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16],
        [row.centerYAnchor constraintEqualToAnchor:card.centerYAnchor],
        [row.heightAnchor constraintEqualToConstant:44]
    ]];
    sg_state = [SPTPlayerState new];
    sg_state.track = makeTrack(@"We Are The People", @"Canon");
    sg_state.options = [SPTPlayerOptions new];
    sg_player = [SGHarnessPlayer new];
    // A trait override alone leaves UIKit's semantic layout LTR on an English/Korean simulator.
    // Mirror the fixture's Spotify views together, as a right-to-left app locale does.
    if (rtl) SGForEachView(root.view, ^(UIView *view) {
        view.semanticContentAttribute = UISemanticContentAttributeForceRightToLeft;
    });
    HARNESS_CHECK(bar.view.effectiveUserInterfaceLayoutDirection ==
                  (rtl ? UIUserInterfaceLayoutDirectionRightToLeft : UIUserInterfaceLayoutDirectionLeftToRight));
    [root.view layoutIfNeeded];
    styleNowPlayingBar(container);
    [root.view layoutIfNeeded];
    styleNowPlayingBar(container);
    [root.view layoutIfNeeded];
    NSArray *extras = objc_getAssociatedObject(bar.view, &kCapsuleKey);
    HARNESS_CHECK(wide ? extras.count == 4 : extras.count == 0);
    if (wide) {
        CGFloat radius = 0;
        CGRect capsule = SGRNowPlayingCardFrameIn(root.view, &radius);
        HARNESS_CHECK(fabs(radius - height / 2) < 1);
        HARNESS_CHECK(rtl ? CGRectGetMaxX(capsule) <= CGRectGetMinX(tabs.frame) - 16 :
                           CGRectGetMinX(capsule) >= CGRectGetMaxX(tabs.frame) + 16);
        HARNESS_CHECK(whiteTint(play.tintColor));
        HARNESS_CHECK(whiteTint(sg_shuffle.tintColor) && whiteTint(sg_repeat.tintColor));
        CGRect previous = [play convertRect:play.bounds toView:root.view];
        CGRect artwork = [cover convertRect:cover.bounds toView:root.view];
        for (UIButton *button in extras) {
            CGRect frame = [button convertRect:button.bounds toView:root.view];
            HARNESS_CHECK(button.accessibilityLabel.length && frame.size.width >= 44 && frame.size.height >= 44);
            HARNESS_CHECK(CGRectContainsRect(capsule, frame));
            HARNESS_CHECK(!CGRectIntersectsRect(artwork, frame));
            if (!(rtl ? CGRectGetMaxX(frame) <= CGRectGetMinX(previous) :
                        CGRectGetMinX(frame) >= CGRectGetMaxX(previous))) {
                HARNESS_FAIL(@"capsule order %@ [%.17g, %.17g] after [%.17g, %.17g]; bar direction %ld, row direction %ld, semantic %ld",
                    button.accessibilityIdentifier, CGRectGetMinX(frame), CGRectGetMaxX(frame),
                    CGRectGetMinX(previous), CGRectGetMaxX(previous), (long)bar.view.effectiveUserInterfaceLayoutDirection,
                    (long)row.effectiveUserInterfaceLayoutDirection, (long)row.semanticContentAttribute);
            }
            previous = frame;
            CGPoint center = CGPointMake(CGRectGetMidX(button.bounds), CGRectGetMidY(button.bounds));
            HARNESS_CHECK([bar.view hitTest:[button convertPoint:center toView:bar.view] withEvent:nil] == button);
            [button sendActionsForControlEvents:UIControlEventTouchUpInside];
        }
        extern BOOL sg_harnessLyricsOpened, sg_harnessQueueOpened;
        HARNESS_CHECK(sg_state.options.shufflingContext && sg_state.options.repeatingContext);
        HARNESS_CHECK(sg_harnessLyricsOpened && sg_harnessQueueOpened);
        showPlayerOptions();
        HARNESS_CHECK([sg_shuffle.accessibilityValue isEqual:@"On"]);
        HARNESS_CHECK([sg_repeat.accessibilityValue isEqual:@"All"]);
        CGFloat r, g, b, a;
        for (UIButton *button in @[sg_shuffle, sg_repeat]) {
            HARNESS_CHECK([button.tintColor getRed:&r green:&g blue:&b alpha:&a] && g > r && g > b);
        }
        // A repeat-only report must wait while inactive, then update on activation and on the next active report.
        UIApplication *app = UIApplication.sharedApplication;
        Method method = class_getInstanceMethod(app.class, @selector(applicationState));
        __block UIApplicationState appState = UIApplicationStateInactive;
        IMP replacement = imp_implementationWithBlock(^UIApplicationState(id owner) { return appState; });
        IMP original = method_setImplementation(method, replacement);
        sg_state.options.repeatingContext = NO;
        sg_state.options.repeatingTrack = YES;
        [sg_optionsWatcher playerStateDidReport:sg_state];
        HARNESS_CHECK([sg_repeat.accessibilityValue isEqual:@"All"]);
        appState = UIApplicationStateActive;
        [sg_optionsWatcher appDidBecomeActive];
        HARNESS_CHECK([sg_repeat.accessibilityValue isEqual:@"One"]);
        method_setImplementation(method, original);
        imp_removeBlock(replacement);
        sg_state.options.repeatingTrack = NO;
        sg_state.options.repeatingContext = YES;
        [sg_optionsWatcher playerStateDidReport:sg_state];
        HARNESS_CHECK([sg_repeat.accessibilityValue isEqual:@"All"]);
        if (!getenv("HARNESS_OPTIONS_ACTIVE")) {
            [sg_shuffle sendActionsForControlEvents:UIControlEventTouchUpInside];
            [sg_repeat sendActionsForControlEvents:UIControlEventTouchUpInside];
            [sg_repeat sendActionsForControlEvents:UIControlEventTouchUpInside];
            showPlayerOptions();
            HARNESS_CHECK(!sg_state.options.shufflingContext && !sg_state.options.repeatingContext && !sg_state.options.repeatingTrack);
            HARNESS_CHECK(whiteTint(sg_shuffle.tintColor) && whiteTint(sg_repeat.tintColor));
        }
        NSLog(@"[harness] capsule options: shuffle %@, repeat %@", sg_shuffle.accessibilityValue, sg_repeat.accessibilityValue);
    }
    NSLog(@"[harness] capsule checks: PASS");
    fflush(stdout);
}

// Spotify can deliver the bar's layout callback before its row has adopted the new width.
// The capsule must keep the same edges through those callbacks, not widen then restore in a cycle.
static void checkStaleCapsuleRow(void) {
    dispatch_source_t watchdog = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0,
                                                       dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0));
    dispatch_source_set_timer(watchdog, dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC), DISPATCH_TIME_FOREVER, 0);
    dispatch_source_set_event_handler(watchdog, ^{
        HARNESS_FAIL(@"stale capsule row: layout did not complete within 30 seconds");
    });
    dispatch_resume(watchdog);
    UIViewController *root = [(id)UIApplication.sharedApplication.delegate window].rootViewController;
    for (NSNumber *mirrored in @[@NO, @YES]) {
        BOOL rtl = mirrored.boolValue;
        UIView *host = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 1376, 1032)];
        [root.view addSubview:host];
        UIView *tabs = [[UIView alloc] initWithFrame:CGRectMake(rtl ? 1072 : 24, 900, 280, 76)];
        tabs.accessibilityIdentifier = @"elements-tabs-view-identifier";
        [tabs addSubview:[[HarnessPlatterView alloc] initWithFrame:tabs.bounds]];
        [host addSubview:tabs];
        UIViewController *container = [UIViewController new], *bar = [UIViewController new];
        [root addChildViewController:container];
        [host addSubview:container.view];
        container.view.frame = CGRectMake(rtl ? 8 : 910, 900, 458, 76);
        [container addChildViewController:bar];
        [container.view addSubview:bar.view];
        bar.view.translatesAutoresizingMaskIntoConstraints = NO;
        NSLayoutConstraint *leading = [bar.view.leadingAnchor constraintEqualToAnchor:container.view.leadingAnchor constant:8];
        NSLayoutConstraint *trailing = [bar.view.trailingAnchor constraintEqualToAnchor:container.view.trailingAnchor constant:-8];
        [NSLayoutConstraint activateConstraints:@[
            leading, trailing,
            [bar.view.topAnchor constraintEqualToAnchor:container.view.topAnchor],
            [bar.view.bottomAnchor constraintEqualToAnchor:container.view.bottomAnchor]
        ]];
        UIButton *play = [UIButton buttonWithType:UIButtonTypeSystem];
        play.accessibilityIdentifier = kPlayId;
        [play.widthAnchor constraintEqualToConstant:44].active = YES;
        UIStackView *buttons = [[UIStackView alloc] initWithArrangedSubviews:@[play]];
        UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[[UIView new], buttons]];
        row.spacing = 4;
        row.translatesAutoresizingMaskIntoConstraints = NO;
        [bar.view addSubview:row];
        [NSLayoutConstraint activateConstraints:@[
            [row.leadingAnchor constraintEqualToAnchor:bar.view.leadingAnchor constant:68],
            [row.trailingAnchor constraintEqualToAnchor:bar.view.trailingAnchor constant:-8],
            [row.topAnchor constraintEqualToAnchor:bar.view.topAnchor constant:16],
            [row.heightAnchor constraintEqualToConstant:44]
        ]];
        SGForEachView(host, ^(UIView *view) {
            view.semanticContentAttribute = rtl ? UISemanticContentAttributeForceRightToLeft : UISemanticContentAttributeForceLeftToRight;
        });
        sg_capsule = YES;
        placeCapsuleButtons(bar.view, YES);
        CGRect previousRow = CGRectZero;
        NSUInteger changes = 0;
        for (NSUInteger pass = 0; pass < 12; pass++) {
            [container.view layoutIfNeeded];
            CGRect settledRow = row.frame;
            if (pass) row.frame = previousRow;
            CGFloat oldLeading = leading.constant, oldTrailing = trailing.constant;
            placeInline(container);
            if (leading.constant != oldLeading || trailing.constant != oldTrailing) changes++;
            if (changes > 1) HARNESS_FAIL(@"stale capsule row %@: %lu edge changes by pass %lu",
                                         rtl ? @"RTL" : @"LTR", (unsigned long)changes, (unsigned long)pass);
            previousRow = settledRow;
        }
        [container.view layoutIfNeeded];
        // 68pt artwork/inset + 8pt trailing inset + five 44pt buttons with 4pt gaps + 200pt title.
        HARNESS_CHECK(fabs(bar.view.bounds.size.width - 516) < 0.01);
        [tabs removeFromSuperview];
        placeInline(container);
        HARNESS_CHECK(leading.constant == 8 && trailing.constant == -8);
        [container willMoveToParentViewController:nil];
        [container.view removeFromSuperview];
        [container removeFromParentViewController];
        [host removeFromSuperview];
    }
    sg_capsule = NO;
    dispatch_source_cancel(watchdog);
    sg_checks++;
    NSLog(@"[harness] stale capsule row: PASS");
}

// With a split tab in a regular width the tab bar has two platters on the capsule's row (TabBar.x): the main bar's and,
// nearer the capsule, the split tab's 62 pt circle. The capsule grows toward the tab bar until kCapsuleTabGap from the
// nearer one, however much wider the other is. The stale row's fixture, whose capsule wants 516 pt, beside a tab bar
// whose circle ends 34 pt short of Spotify's capsule: the main platter would let it grow to 516, the circle to 18 pt more.
// Third, the split bar that has lost its last tab: hidden by TabBar.x, its circle left where it stood, nearer than the
// main platter. Unseen, it limits nothing, and the capsule grows to its full 516 pt.
static void checkCapsuleBesideSplitTab(void) {
    // The gap the design keeps from the tab bar's glass, written here rather than read from NowPlayingBar.x.
    const CGFloat expectedGap = 16, expectedFullWidth = 516;
    UIViewController *root = [(id)UIApplication.sharedApplication.delegate window].rootViewController;
    for (NSUInteger pass = 0; pass < 3; pass++) {
        BOOL rtl = pass == 1, splitHidden = pass == 2;
        CGFloat width = 1376, tabsWidth = 860, mainWidth = 600, circleSide = 62;
        UIView *host = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, 1032)];
        host.backgroundColor = [UIColor colorWithRed:0.06 green:0.09 blue:0.14 alpha:1];
        [root.view addSubview:host];
        UIView *tabs = [[UIView alloc] initWithFrame:CGRectMake(rtl ? width - 24 - tabsWidth : 24, 900, tabsWidth, 76)];
        tabs.accessibilityIdentifier = @"elements-tabs-view-identifier";
        UIView *main = [[HarnessPlatterView alloc] initWithFrame:CGRectMake(rtl ? tabsWidth - mainWidth : 0, 0, mainWidth, 76)];
        CGRect circleFrame = CGRectMake(rtl ? 0 : tabsWidth - circleSide, 0, circleSide, 76);
        UIView *splitBar = [[UIView alloc] initWithFrame:circleFrame];
        splitBar.hidden = splitHidden;
        [tabs addSubview:splitBar];
        UIView *circle = [[HarnessPlatterView alloc] initWithFrame:splitBar.bounds];
        for (UIView *platter in @[main, circle]) {
            platter.backgroundColor = [UIColor colorWithWhite:1 alpha:0.25];
            platter.layer.cornerRadius = 38;
        }
        [tabs addSubview:main];
        [splitBar addSubview:circle];
        [host addSubview:tabs];
        UIViewController *container = [UIViewController new], *bar = [UIViewController new];
        [root addChildViewController:container];
        [host addSubview:container.view];
        container.view.frame = CGRectMake(rtl ? 8 : 910, 900, 458, 76);
        [container addChildViewController:bar];
        [container.view addSubview:bar.view];
        bar.view.backgroundColor = UIColor.darkGrayColor;
        bar.view.layer.cornerRadius = 38;
        bar.view.translatesAutoresizingMaskIntoConstraints = NO;
        [NSLayoutConstraint activateConstraints:@[
            [bar.view.leadingAnchor constraintEqualToAnchor:container.view.leadingAnchor constant:8],
            [bar.view.trailingAnchor constraintEqualToAnchor:container.view.trailingAnchor constant:-8],
            [bar.view.topAnchor constraintEqualToAnchor:container.view.topAnchor],
            [bar.view.bottomAnchor constraintEqualToAnchor:container.view.bottomAnchor]
        ]];
        UIButton *play = [UIButton buttonWithType:UIButtonTypeSystem];
        play.accessibilityIdentifier = kPlayId;
        [play.widthAnchor constraintEqualToConstant:44].active = YES;
        UIStackView *buttons = [[UIStackView alloc] initWithArrangedSubviews:@[play]];
        UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[[UIView new], buttons]];
        row.spacing = 4;
        row.translatesAutoresizingMaskIntoConstraints = NO;
        [bar.view addSubview:row];
        [NSLayoutConstraint activateConstraints:@[
            [row.leadingAnchor constraintEqualToAnchor:bar.view.leadingAnchor constant:68],
            [row.trailingAnchor constraintEqualToAnchor:bar.view.trailingAnchor constant:-8],
            [row.topAnchor constraintEqualToAnchor:bar.view.topAnchor constant:16],
            [row.heightAnchor constraintEqualToConstant:44]
        ]];
        SGForEachView(host, ^(UIView *view) {
            view.semanticContentAttribute = rtl ? UISemanticContentAttributeForceRightToLeft : UISemanticContentAttributeForceLeftToRight;
        });
        sg_capsule = YES;
        placeCapsuleButtons(bar.view, YES);
        [container.view layoutIfNeeded];
        placeInline(container);
        [container.view layoutIfNeeded];
        CGRect capsule = [bar.view convertRect:bar.view.bounds toView:host];
        CGRect nearest = [circle convertRect:circle.bounds toView:host];
        shoot(host, CGRectMake(0, 880, width, 116), splitHidden ? @"capsule-split-hidden" : rtl ? @"capsule-split-rtl" : @"capsule-split");
        if (splitHidden) {
            if (fabs(capsule.size.width - expectedFullWidth) > 0.5) {
                HARNESS_FAIL(@"capsule beside a hidden split bar: %.1f pt wide, wanted %.0f; stopped at the unseen circle (%@)?",
                             capsule.size.width, expectedFullWidth, NSStringFromCGRect(nearest));
            }
        } else {
            CGFloat edge = rtl ? CGRectGetMaxX(capsule) : CGRectGetMinX(capsule);
            CGFloat wanted = rtl ? CGRectGetMinX(nearest) - expectedGap : CGRectGetMaxX(nearest) + expectedGap;
            if (fabs(edge - wanted) > 0.5) {
                HARNESS_FAIL(@"capsule beside a split tab %@: its side toward the tab bar at x %.1f, wanted %.0f pt from the split tab's circle (%@)",
                             rtl ? @"RTL" : @"LTR", edge, expectedGap, NSStringFromCGRect(nearest));
            }
        }
        [container willMoveToParentViewController:nil];
        [container.view removeFromSuperview];
        [container removeFromParentViewController];
        [host removeFromSuperview];
    }
    sg_capsule = NO;
    sg_checks++;
    NSLog(@"[harness] capsule beside a split tab: PASS");
}
