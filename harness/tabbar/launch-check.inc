// The selected button is drawn under UIKit's selection bubble. The other
// buttons draw in the ordinary content view. Read their actual image views.
static NSArray<NSNumber *> *launchGlyphs(UITabBar *bar) {
    NSMutableArray<UIView *> *buttons = [NSMutableArray array];
    SGForEachView(bar, ^(UIView *v) {
        if (![v isKindOfClass:UIControl.class] || v == bar) return;
        BOOL lit = NO;
        for (UIView *up = v.superview; up && up != bar; up = up.superview) {
            if ([NSStringFromClass(up.class) containsString:@"SelectedContent"]) lit = YES;
        }
        if (lit == ((UIControl *)v).selected) [buttons addObject:v];
    });
    [buttons sortUsingComparator:^NSComparisonResult(UIView *a, UIView *b) {
        return [@(SGFrameIn(a, bar).origin.x) compare:@(SGFrameIn(b, bar).origin.x)];
    }];
    NSMutableArray *images = [NSMutableArray array];
    for (UIView *button in buttons) {
        __block BOOL found = NO;
        SGForEachView(button, ^(UIView *v) {
            if (![v isKindOfClass:UIImageView.class] || !((UIImageView *)v).image || CGRectIsEmpty(v.bounds)) return;
            for (UIView *up = v; up; up = up.superview) if (up.hidden || up.alpha < .01) return;
            if (v.window) found = YES;
        });
        [images addObject:@(found)];
    }
    return images;
}

static UIStackView *makeLaunchRow(UIViewController *owner) {
    CGRect frame = CGRectMake(0, 420, owner.view.bounds.size.width, 80);
    UIView *stock = [[_TtC23NavigationUI_TabBarImpl10TabBarView alloc] initWithFrame:frame];
    [owner.view addSubview:stock];
    UIStackView *row = [[UIStackView alloc] initWithFrame:stock.bounds];
    row.distribution = UIStackViewDistributionFillEqually;
    [stock addSubview:row];
    NSArray *stockTitles = @[@"Home", @"Search", @"Your Library", @"Create"];
    for (NSUInteger i = 0; i < stockTitles.count; i++) {
        UIImageView *icon = [UIImageView new];
        if (i == 2) icon.image = [UIImage systemImageNamed:@"books.vertical"];
        UIView *source = tab(_TtC23NavigationUI_TabBarImpl21TabBarItemElementView.class, stockTitles[i], icon, i == 0);
        source.frame = CGRectMake(i * 80, 0, 80, 49);
        [row addArrangedSubview:source];
    }
    return row;
}

static void checkReentrantLayout(UIStackView *row, UITabBar *bar) {
    UIView *home = row.arrangedSubviews[0], *oldSearch = row.arrangedSubviews[1];
    oldSearch.subviews.firstObject.layer.backgroundColor = UIColor.whiteColor.CGColor;
    UIView *newSearch = tab(oldSearch.class, @"Search", [UIImageView new], YES);
    UILabel *homeLabel = (id)home.subviews.lastObject;
    SGHarnessGlyphView *glyph = [[NSClassFromString(@"SPTEncoreIconView") alloc]
                                 initWithIcon:[SGHarnessEncoreIcon outlineNamed:@"home" square:NO]];
    glyph.frame = home.subviews.firstObject.frame;
    [home.subviews.firstObject removeFromSuperview];
    [home addSubview:glyph];
    __block NSTimer *innerTimer = nil;
    glyph.onActiveLayout = ^{
        // drawLive temporarily selected Home's glyph and called layoutIfNeeded.
        homeLabel.textColor = UIColor.grayColor;
        [oldSearch removeFromSuperview];
        [row insertArrangedSubview:newSearch atIndex:1];
        [newSearch layoutSubviews];
        innerTimer = [bar valueForKey:@"glyphTimer"];
        HARNESS_CHECK(innerTimer.valid && bar.selectedItem == bar.items[1] && !bar.items[1].image);
    };
    [home layoutSubviews];
    HARNESS_CHECK(innerTimer.valid && [bar valueForKey:@"glyphTimer"] == innerTimer);
    HARNESS_CHECK(bar.selectedItem == bar.items[1]);
    newSearch.subviews.firstObject.layer.backgroundColor = UIColor.whiteColor.CGColor;
    after(.6, ^{
        HARNESS_CHECK(bar.items[1].image && bar.items[1].selectedImage && bar.selectedItem == bar.items[1]);
        HARNESS_CHECK(([launchGlyphs(bar) isEqualToArray:@[@YES, @YES, @YES, @YES]]));
        HARNESS_CHECK(![bar valueForKey:@"glyphTimer"]);
        puts("[harness] PASS Search replaced during glyph drawing keeps its selection and retry");
        exit(0);
    });
}

static void checkReplacedBar(UIViewController *owner, UIView *stock, UITabBar *bar) {
    UIView *home = SGRowIn(stock).arrangedSubviews.firstObject;
    NSNumber *attempts = [bar valueForKey:@"glyphRetries"];
    [stock removeFromSuperview];
    [[bar valueForKey:@"glyphTimer"] fire];
    HARNESS_CHECK(![bar valueForKey:@"glyphTimer"] && [[bar valueForKey:@"glyphRetries"] isEqual:attempts]);

    [owner.view addSubview:stock];
    [home layoutSubviews];
    NSTimer *pending = [bar valueForKey:@"glyphTimer"];
    HARNESS_CHECK(pending.valid);
    [stock removeFromSuperview];
    UIStackView *replacement = makeLaunchRow(owner);
    [replacement.arrangedSubviews.firstObject layoutSubviews];
    HARNESS_CHECK(!pending.valid && ![bar valueForKey:@"glyphTimer"]);
    after(.6, ^{
        HARNESS_CHECK(stock && !stock.window && replacement.window);
        HARNESS_CHECK(!CGRectIsNull(SGRTabBarGlassRow(replacement.window)));
        puts("[harness] PASS detached and replaced stock bars leave the visible bar active");
        exit(0);
    });
}

// Launch as itemDidLayOut sees it, before the stack has placed Queue. UIKit owns
// the glass bar, its item views and every layout after the initial burst.
static void runLaunch(UIWindow *window) {
    SGSetEnabled(SGRKeyNavbar, YES);
    SGSetEnabled(SGRKeyNavbarSymbols, YES);
    SGSetEnabled(SGRKeyNavbarHideLabels, NO);
    NSArray *titles = @[@"Home", @"Search", @"Your Library", @"Queue"];
    SGRSetNavbarSplit(@[]);
    SGRSetNavbarLayout(@[@{SGRNavbarID: @"Home"}, @{SGRNavbarID: @"Search"}, @{SGRNavbarID: @"Your Library"},
                         @{SGRNavbarID: @"Create", SGRNavbarHidden: @YES},
                         @{SGRNavbarID: @"queue", SGRNavbarTitle: @"Queue", SGRNavbarURI: @"spotify:queue",
                           SGRNavbarIconSet: SGTabIconSetSymbols, SGRNavbarIcon: @"list.bullet"}]);

    UIViewController *owner = [UIViewController new];
    window.rootViewController = owner;
    [window makeKeyAndVisible];
    UIStackView *row = makeLaunchRow(owner);
    UIView *stock = row.superview;
    NSArray *args = NSProcessInfo.processInfo.arguments;
    BOOL unlabeled = [args containsObject:@"unlabeled"];
    UIView *search = row.arrangedSubviews[1];
    if (unlabeled) {
        SGRSetNavbarStock(@[]);
        ((UILabel *)row.arrangedSubviews[0].subviews.lastObject).text = @"";
        ((UILabel *)search.subviews.lastObject).text = @"";
    }
    UIView *home = row.arrangedSubviews.firstObject;
    SGRComposeTabBar(stock);
    CGFloat initialWidth = row.arrangedSubviews.lastObject.bounds.size.width;
    [home layoutSubviews];
    UITabBar *bar = (id)viewsNamed(stock, @"SGRSystemTabBar").firstObject;
    if (unlabeled) {
        NSArray *order = SGRComposedTabItems(stock);
        HARNESS_CHECK(order.count == 4 && [order containsObject:home] && [order containsObject:search]);
        HARNESS_CHECK([order isEqualToArray:[bar valueForKey:@"sources"]] && bar.items.count == 4);
        HARNESS_CHECK(![SGRNavbarStock() containsObject:NSStringFromClass(home.class)]);
        ((UILabel *)home.subviews.lastObject).text = @"Home";
        ((UILabel *)search.subviews.lastObject).text = @"Search";
        [home layoutSubviews];
        HARNESS_CHECK(([SGRNavbarStock() isEqualToArray:@[@"Home", @"Search", @"Your Library", @"Create"]]));
        puts("[harness] PASS both unlabeled stock tabs kept until named");
    }
    NSArray *first = [bar.items valueForKey:@"title"];
    NSLog(@"[harness] first pass: Queue width %.0f, glass items %@", initialWidth, first);
    HARNESS_CHECK(initialWidth == 0);
    HARNESS_CHECK([first isEqualToArray:titles] && bar.selectedItem == bar.items.firstObject);
    HARNESS_CHECK(!bar.items[0].image && !bar.items[1].image && bar.items[2].image && bar.items[3].image);
    NSTimer *pending = [bar valueForKey:@"glyphTimer"];
    HARNESS_CHECK(pending.valid);
    for (NSUInteger i = 0; i < 60; i++) {
        [home layoutSubviews];
        HARNESS_CHECK([bar valueForKey:@"glyphTimer"] == pending);
    }
    HARNESS_CHECK([[bar valueForKey:@"glyphRetries"] unsignedIntegerValue] == 0);
    after(.40, ^{
        NSArray *initial = launchGlyphs(bar);
        HARNESS_CHECK(([initial isEqualToArray:@[@NO, @NO, @YES, @YES]]));
        HARNESS_CHECK([[bar valueForKey:@"glyphRetries"] unsignedIntegerValue] > 0);
        NSLog(@"[harness] PASS Queue at zero width, Home selected, one pending retry for 60 layouts");
        if ([args containsObject:@"reentrant"]) {
            checkReentrantLayout(row, bar);
            return;
        }
        if ([args containsObject:@"replace-bar"]) {
            checkReplacedBar(owner, stock, bar);
            return;
        }
        if ([args containsObject:@"replace-search"]) {
            NSTimer *oldTimer = [bar valueForKey:@"glyphTimer"];
            UIView *replacement = tab(_TtC23NavigationUI_TabBarImpl21TabBarItemElementView.class, @"Search", [UIImageView new], NO);
            [row.arrangedSubviews[1] removeFromSuperview];
            [row insertArrangedSubview:replacement atIndex:1];
            [replacement layoutSubviews];
            HARNESS_CHECK(!oldTimer.valid && [[bar valueForKey:@"glyphTimer"] isValid]);
            HARNESS_CHECK([[bar valueForKey:@"glyphRetries"] unsignedIntegerValue] == 0);
        }
        if ([args containsObject:@"late-ink"]) {
            for (UIView *source in @[home, row.arrangedSubviews[1]]) {
                source.subviews.firstObject.layer.backgroundColor = UIColor.whiteColor.CGColor;
            }
        } else SGRSetNavbarStockURIs(@{@"Home": @"spotify:home", @"Search": @"spotify:find", @"Your Library": @"spotify:collection"});
        after(.6, ^{
            HARNESS_CHECK(([launchGlyphs(bar) isEqualToArray:@[@YES, @YES, @YES, @YES]]));
            HARNESS_CHECK(![bar valueForKey:@"glyphTimer"] && [[bar valueForKey:@"glyphRetries"] unsignedIntegerValue] == 0);
            HARNESS_CHECK([[bar.items valueForKey:@"title"] isEqualToArray:titles] && bar.selectedItem == bar.items.firstObject);
            for (UITabBarItem *item in bar.items) HARNESS_CHECK(item.image && item.selectedImage);
            puts("[harness] PASS launch with four visible glyphs");
            exit(0);
        });
    });
}
