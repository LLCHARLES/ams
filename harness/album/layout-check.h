// The album header through the changes an open page lives through (`layout <case>` on the launch line; layout-check.py
// runs them on simulators of its own):
//
//   text-size     (iPhone) the text size changed with the page open, from the size the page opened at to the largest
//                 non-accessibility one: the header's title, artist and details take Title 2 bold, Title 3 and Caption 1
//                 at that size capped at Extra Large, the artist page's name (a second header with largeTitle, below the
//                 screen) Large Title bold capped the same, and that header's content ends SGRHeaderInfoBottom above its
//                 bottom at the new size. The run prints "[harness] READY text-size" for the driver to change the size.
//   resize-card   (iPad, Card cover) the window narrowed with the page open, Spotify's square re-centred in it: the
//                 hero's square lands on Spotify's square again; Spotify's square then shrinking at the new width (the
//                 header collapsing on a scroll) leaves the hero's where it is; a second resize whose square Spotify
//                 centres a pass after the header has its width has the hero's follow it to the centre.
//   beside-scrim  (iPad, Full screen cover) Cover beside turned off with the page open: the hero across the top keeps
//                 the contrast gradient over its top.
//   beside-faces  (iPad, Cover beside, Artist picture) an artist line that fits the text column on one line but not
//                 once the faces stand before it: the name wraps instead of being cut, and the details start under it.
//   measure       (iPhone, Artist picture, the artist's face shown) the header's passes over and over with nothing changed: the info's labels
//                 measured no more after the first; the artist's name changed, measured again once, the line reading it.
//   chrome-card   (iPhone 402pt, Card cover, Spotify's square at {77, 76, 248, 248} as a phone measured it) the pinned
//                 download and ⋯ on one capsule at {298, 62, 88, 44} cover the square's top trailing corner: the square and
//                 its shadow are drawn at {96, 114, 210, 210}, there scrolled 120pt too (moved up with the page); download
//                 gone, ⋯'s circle alone clears it and it is Spotify's square again; download back, the smaller one again.
//   chrome-card-rtl the same laid out right to left, the capsule mirrored onto the left corner.
//   chrome-full   (iPhone 402pt, Full screen cover) the same pair over the cover: the picture is the hero's top square,
//                 {0, 0, 402, 402}, untouched by it.
//
// Each holds a "[harness] SHOT <file>" (the window drawn to Documents) before its checks, then logs PASS and exits 0, or
// logs a FAIL line and exits 1 (../harness-fail.h).

static NSString *layoutCase(void) {
    NSArray<NSString *> *args = NSProcessInfo.processInfo.arguments;
    NSUInteger at = [args indexOfObject:@"layout"];
    return at != NSNotFound && at + 1 < args.count ? args[at + 1] : nil;
}

// Before the page is built: the settings each case opens with.
static void layoutPrepare(void) {
    NSString *name = layoutCase();
    if (!name) return;
    [NSUserDefaults.standardUserDefaults setBool:[name hasPrefix:@"beside"] forKey:SGRKeyCoverBeside];
    [NSUserDefaults.standardUserDefaults setBool:YES forKey:@"spotifyglass.redesign.album.artistPicture"];
}

static void layoutShot(UIWindow *window, NSString *name) {
    [window layoutIfNeeded];
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:window.bounds.size];
    UIImage *image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        HARNESS_CHECK([window drawViewHierarchyInRect:window.bounds afterScreenUpdates:YES]);
    }];
    NSString *file = [[NSHomeDirectory() stringByAppendingPathComponent:@"Documents"]
                      stringByAppendingPathComponent:[NSString stringWithFormat:@"album-%@.png", name]];
    HARNESS_CHECK([UIImagePNGRepresentation(image) writeToFile:file atomically:YES]);
    NSLog(@"[harness] SHOT %@", file);
}

// `then` once `ready` holds, looked at every 50 ms for at most 20 s.
static void layoutWhen(NSString *what, BOOL (^ready)(void), dispatch_block_t then) {
    CFTimeInterval deadline = CACurrentMediaTime() + 20;
    [NSTimer scheduledTimerWithTimeInterval:0.05 repeats:YES block:^(NSTimer *timer) {
        if (!ready()) {
            if (CACurrentMediaTime() > deadline) HARNESS_FAIL(@"timed out waiting for %@", what);
            return;
        }
        [timer invalidate];
        then();
    }];
}

static void layoutAfter(NSTimeInterval seconds, dispatch_block_t then) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(seconds * NSEC_PER_SEC)), dispatch_get_main_queue(), then);
}

// The page shown whole: the field's veil faded.
static BOOL layoutRevealed(UIView *page) {
    UIView *veil = besideFind(page, @"SGRFieldVeil");
    return !veil || (veil.layer.presentationLayer ?: veil.layer).opacity < 0.01;
}

static NSArray<UILabel *> *layoutLabels(UIView *info) {
    NSMutableArray<UILabel *> *labels = [NSMutableArray array];
    for (UIView *view in info.subviews) {
        if ([view isKindOfClass:UILabel.class] && !view.hidden) [labels addObject:(UILabel *)view];
    }
    return labels;
}

static UILabel *layoutLabel(UIView *info, NSString *text) {
    for (UILabel *label in layoutLabels(info)) {
        if ([label.text isEqualToString:text]) return label;
    }
    HARNESS_FAIL(@"no label reads \"%@\"", text);
}

// A text style's size at `category`, as the system's type table has it.
static CGFloat layoutSize(UIFontTextStyle style, UIContentSizeCategory category) {
    UITraitCollection *traits = [UITraitCollection traitCollectionWithPreferredContentSizeCategory:category];
    return [UIFont preferredFontForTextStyle:style compatibleWithTraitCollection:traits].pointSize;
}

static void layoutExpectFont(UILabel *label, UIFontTextStyle style, UIContentSizeCategory category) {
    CGFloat size = layoutSize(style, category);
    if (fabs(label.font.pointSize - size) > 0.01)
        HARNESS_FAIL(@"\"%@\" is %.1fpt, expected %@ at %@: %.1fpt", label.text, label.font.pointSize, style, category, size);
}

static void layoutTextSize(UIWindow *window, UIView *page) {
    // The artist page's header, laid out where nothing covers the album's.
    CGFloat width = window.bounds.size.width;
    SGRHeaderInfo *artist = [[SGRHeaderInfo alloc] initWithFrame:CGRectMake(0, window.bounds.size.height + 20, width, 300)];
    artist.largeTitle = YES;
    [artist showTitle:@"Artist Name" creator:nil length:@"1,234,567 monthly listeners" about:nil];
    [window.rootViewController.view addSubview:artist];
    UIContentSizeCategory opened = UIApplication.sharedApplication.preferredContentSizeCategory;
    __block BOOL changed = NO;
    [NSNotificationCenter.defaultCenter addObserverForName:UIContentSizeCategoryDidChangeNotification object:nil queue:nil
                                                usingBlock:^(NSNotification *note) { changed = YES; }];
    layoutWhen(@"the page revealed", ^BOOL { return layoutRevealed(page) && besideFind(page, @"SGRHeaderInfo"); }, ^{
        NSLog(@"[harness] READY text-size, opened at %@", opened);
        layoutWhen(@"the text size changed", ^BOOL { return changed; }, ^{
            layoutAfter(1, ^{
                UIContentSizeCategory now = UIApplication.sharedApplication.preferredContentSizeCategory;
                HARNESS_CHECK(![now isEqualToString:opened]);
                // The header's sizes stop growing at Extra Large.
                UIContentSizeCategory capped = UIContentSizeCategoryCompareToCategory(now, UIContentSizeCategoryExtraLarge) == NSOrderedDescending
                    ? UIContentSizeCategoryExtraLarge : now;
                HARNESS_CHECK(![capped isEqualToString:opened]);
                layoutShot(window, @"text-size");
                UIView *info = besideFind(page, @"SGRHeaderInfo");
                layoutExpectFont(layoutLabel(info, @"Hurry Up Tomorrow"), UIFontTextStyleTitle2, capped);
                layoutExpectFont(layoutLabel(info, @"The Weeknd"), UIFontTextStyleTitle3, capped);
                layoutExpectFont(layoutLabel(info, @"Album • 31. 1. 2025"), UIFontTextStyleCaption1, capped);
                layoutExpectFont(layoutLabel(artist, @"Artist Name"), UIFontTextStyleLargeTitle, capped);
                layoutExpectFont(layoutLabel(artist, @"1,234,567 monthly listeners"), UIFontTextStyleCaption1, capped);
                // Measured again at the new size: the content still ends on the header's bottom edge, Play its last line.
                [artist layoutIfNeeded];
                UIView *play = besideFind(artist, @"SGRPlayCapsule");
                CGFloat bottom = artist.bounds.size.height - SGRHeaderInfoBottom;
                if (fabs(CGRectGetMaxY(play.frame) - bottom) > 0.5)
                    HARNESS_FAIL(@"the artist header's content ends at %.1f, its bottom edge less %.0f is %.1f", CGRectGetMaxY(play.frame),
                                 SGRHeaderInfoBottom, bottom);
                for (UILabel *label in [layoutLabels(info) arrayByAddingObjectsFromArray:layoutLabels(artist)]) {
                    CGFloat needed = ceil([label sizeThatFits:CGSizeMake(label.bounds.size.width, CGFLOAT_MAX)].height);
                    if (label.bounds.size.height < needed - 0.5) HARNESS_FAIL(@"\"%@\" is %.1fpt high, its text %.1fpt", label.text, label.bounds.size.height, needed);
                }
                NSLog(@"[harness] PASS album text size: %@ to %@, the headers' fonts at %@ and measured again", opened, now, capped);
                exit(0);
            });
        });
    });
}

// The hero's square picture (iOS 26's extension view around it, or the picture itself), in the page.
static CGRect layoutSquare(UIView *hero, UIView *page) {
    UIView *holder = [hero valueForKey:@"_extension"] ?: [hero valueForKey:@"picture"];
    return [holder convertRect:holder.bounds toView:page];
}

static void layoutExpectRect(NSString *what, CGRect actual, CGRect expected) {
    if (fabs(CGRectGetMinX(actual) - CGRectGetMinX(expected)) > 0.5 || fabs(CGRectGetMinY(actual) - CGRectGetMinY(expected)) > 0.5 ||
        fabs(actual.size.width - expected.size.width) > 0.5 || fabs(actual.size.height - expected.size.height) > 0.5)
        HARNESS_FAIL(@"%@: %@, expected %@", what, NSStringFromCGRect(actual), NSStringFromCGRect(expected));
}

static void layoutResizeCard(UIWindow *window, UIView *page, UIView *cover, dispatch_block_t relayout) {
    __block UIView *hero = nil;
    layoutWhen(@"the card cover", ^BOOL {
        hero = besideFind(page, @"SGRAlbumHero");
        return hero && layoutRevealed(page) && layoutSquare(hero, page).size.width > 0;
    }, ^{
        layoutExpectRect(@"the square as the page opened", layoutSquare(hero, page), [cover convertRect:cover.bounds toView:page]);
        // A narrower window (Split View): the full-width views follow it and Spotify centres its square in it again.
        CGFloat from = page.bounds.size.width, to = round(from * 0.68);
        besideResizable(page, from);
        cover.superview.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
        CGRect frame = page.frame;
        frame.size.width = to;
        page.frame = frame;
        relayout();
        layoutAfter(0.5, ^{
            relayout();
            layoutShot(window, @"resize-card");
            CGRect spotify = [cover convertRect:cover.bounds toView:page];
            HARNESS_CHECK(fabs(CGRectGetMidX(spotify) - to / 2) < 0.5);
            layoutExpectRect([NSString stringWithFormat:@"the square after the window went from %.0f to %.0fpt", from, to],
                             layoutSquare(hero, page), spotify);
            // Spotify's square shrinking at that width, as the header collapses on a scroll: the hero's stays put.
            CGRect rest = layoutSquare(hero, page);
            CGRect full = cover.frame;
            cover.frame = CGRectInset(full, 24, 24);
            relayout();
            layoutExpectRect(@"the square while Spotify's shrinks at the same width", layoutSquare(hero, page), rest);
            cover.frame = full;
            relayout();
            // A second resize where Spotify centres its square on a pass after the one that gave the header its
            // width: the hero's follows it there.
            UIView *holder = cover.superview;
            holder.autoresizingMask = UIViewAutoresizingNone;
            CGFloat again = round(from * 0.84);
            CGRect wider = page.frame;
            wider.size.width = again;
            page.frame = wider;
            relayout();
            HARNESS_CHECK(fabs(CGRectGetMidX([cover convertRect:cover.bounds toView:page]) - again / 2) > 0.5);
            holder.center = CGPointMake(holder.center.x + again / 2 - CGRectGetMidX([cover convertRect:cover.bounds toView:page]),
                                        holder.center.y);
            relayout();
            CGRect centred = [cover convertRect:cover.bounds toView:page];
            HARNESS_CHECK(fabs(CGRectGetMidX(centred) - again / 2) < 0.5);
            layoutExpectRect([NSString stringWithFormat:@"the square centred a pass after the window went to %.0fpt", again],
                             layoutSquare(hero, page), centred);
            NSLog(@"[harness] PASS album card resize: the square re-centred at %.0fpt, held while Spotify's shrank, and followed to "
                  "the centre Spotify gave it a pass late at %.0fpt", to, again);
            exit(0);
        });
    });
}

static void layoutBesideScrim(UIWindow *window, UIView *page) {
    __block SGRHeaderInfo *info = nil;
    layoutWhen(@"the cover beside", ^BOOL {
        info = (SGRHeaderInfo *)besideFind(page, @"SGRHeaderInfo");
        return info.sgr_coverBeside && layoutRevealed(page);
    }, ^{
        [NSUserDefaults.standardUserDefaults setBool:NO forKey:SGRKeyCoverBeside];
        layoutWhen(@"the stacked header", ^BOOL { return !info.sgr_coverBeside; }, ^{
            layoutAfter(0.5, ^{
                layoutShot(window, @"beside-scrim");
                UIView *hero = besideFind(page, @"SGRAlbumHero");
                CAGradientLayer *scrim = [hero valueForKey:@"scrim"];
                HARNESS_CHECK(scrim.superlayer == hero.layer && scrim.bounds.size.height > 0);
                if (scrim.hidden) HARNESS_FAIL(@"the full screen cover has no contrast gradient after Cover beside went off");
                NSLog(@"[harness] PASS album beside to full screen: the contrast gradient is back, %@", NSStringFromCGRect(scrim.frame));
                exit(0);
            });
        });
    });
}

// The faces drawn before the artist line: the info's plain view of circles, shown.
static UIView *layoutFaces(UIView *info) {
    for (UIView *view in info.subviews) {
        if ([view isMemberOfClass:UIView.class] && !view.hidden && view.subviews.count) return view;
    }
    return nil;
}

static void layoutBesideFaces(UIWindow *window, UIView *page, UILabel *artistName, dispatch_block_t relayout) {
    __block SGRHeaderInfo *info = nil;
    layoutWhen(@"the cover beside with the artist's face", ^BOOL {
        info = (SGRHeaderInfo *)besideFind(page, @"SGRHeaderInfo");
        return info.sgr_coverBeside && layoutRevealed(page) && layoutFaces(info);
    }, ^{
        UILabel *creator = layoutLabel(info, artistName.text);
        CGFloat column = info.bounds.size.width, lead = layoutFaces(info).bounds.size.width + 8;
        // The longest line of names one line holds across the column, short of 2pt.
        NSArray<NSString *> *words = @[@"Academy", @"of", @"St", @"Martin", @"in", @"the", @"Fields", @"&", @"London", @"Symphony", @"Orchestra"];
        UILabel *probe = [UILabel new];
        probe.font = creator.font;
        CGFloat (^wide)(NSString *) = ^CGFloat(NSString *text) {
            probe.text = text;
            return [probe sizeThatFits:CGSizeMake(CGFLOAT_MAX, CGFLOAT_MAX)].width;
        };
        NSString *names = @"Joshua Bell,";
        for (NSString *word in words) {
            NSString *longer = [names stringByAppendingFormat:@" %@", word];
            if (wide(longer) > column - 2) break;
            names = longer;
        }
        // Then initials, shorter than the faces, up to the column.
        for (NSString *longer = [names stringByAppendingString:@" A."]; wide(longer) <= column - 2;
             longer = [longer stringByAppendingString:@" A."]) names = longer;
        if (wide(names) <= column - lead) HARNESS_FAIL(@"fixture: \"%@\" is %.1fpt, not past the %.1fpt after the faces", names, wide(names), column - lead);
        artistName.text = names;
        artistName.superview.superview.accessibilityLabel = names;
        relayout();
        layoutWhen(@"the faces before the long names", ^BOOL { return layoutFaces(info) && [creator.text isEqualToString:names] && info.sgr_coverBeside; }, ^{
            layoutAfter(0.6, ^{
                relayout();
                layoutShot(window, @"beside-faces");
                CGFloat needed = ceil([creator sizeThatFits:CGSizeMake(creator.bounds.size.width, CGFLOAT_MAX)].height);
                if (creator.bounds.size.height < needed - 0.5)
                    HARNESS_FAIL(@"the artist line is %.1fpt high at %.1fpt across, its names need %.1fpt", creator.bounds.size.height,
                                 creator.bounds.size.width, needed);
                UILabel *details = layoutLabel(info, @"Album • 31. 1. 2025");
                if (CGRectGetMinY(details.frame) < CGRectGetMaxY(creator.frame) - 0.5)
                    HARNESS_FAIL(@"the details at %.1f start inside the artist line, which ends at %.1f", CGRectGetMinY(details.frame),
                                 CGRectGetMaxY(creator.frame));
                HARNESS_CHECK(!CGRectIntersectsRect(layoutFaces(info).frame, creator.frame));
                for (UIView *view in info.subviews) {
                    if (!view.hidden && view.alpha > 0) HARNESS_CHECK(CGRectContainsRect(CGRectInset(info.bounds, -1, -1), view.frame));
                }
                NSLog(@"[harness] PASS album faces beside: the names wrap to %.0fpt across %.0fpt after the faces", creator.bounds.size.height,
                      creator.bounds.size.width);
                exit(0);
            });
        });
    });
}

// sizeThatFits: on SGRHeaderInfo's own labels, counted from layoutCountMeasures on.
static NSUInteger layoutMeasured;

static void layoutCountMeasures(void) {
    Method method = class_getInstanceMethod(UILabel.class, @selector(sizeThatFits:));
    CGSize (*original)(id, SEL, CGSize) = (CGSize (*)(id, SEL, CGSize))method_getImplementation(method);
    Class info = NSClassFromString(@"SGRHeaderInfo");
    method_setImplementation(method, imp_implementationWithBlock(^CGSize(UILabel *label, CGSize size) {
        if ([label.superview isKindOfClass:info]) layoutMeasured++;
        return original(label, @selector(sizeThatFits:), size);
    }));
}

// The header's pass and the info's own, `count` times, nothing changed between them; the measurements they made.
static NSUInteger layoutPasses(UIView *info, dispatch_block_t relayout, NSUInteger count) {
    NSUInteger before = layoutMeasured;
    for (NSUInteger i = 0; i < count; i++) {
        relayout();
        [info setNeedsLayout];
        [info layoutIfNeeded];
    }
    return layoutMeasured - before;
}

static void layoutMeasure(UIWindow *window, UIView *page, UILabel *artistName, dispatch_block_t relayout) {
    __block UIView *info = nil;
    layoutWhen(@"the header with the artist's face", ^BOOL {
        info = besideFind(page, @"SGRHeaderInfo");
        return info && layoutRevealed(page) && ([[info valueForKey:@"picture"] image] || layoutFaces(info));
    }, ^{
        layoutAfter(0.6, ^{
            layoutCountMeasures();
            layoutPasses(info, relayout, 1);
            NSUInteger again = layoutPasses(info, relayout, 10);
            if (again) HARNESS_FAIL(@"10 passes with nothing changed measured the info's labels %lu times", (unsigned long)again);
            NSString *names = @"The Weeknd & Justice";
            artistName.text = names;
            artistName.superview.superview.accessibilityLabel = names;
            NSUInteger changed = layoutPasses(info, relayout, 1);
            UILabel *creator = layoutLabel(info, names);
            CGFloat needed = [creator sizeThatFits:CGSizeMake(creator.bounds.size.width, CGFLOAT_MAX)].width;
            if (!changed || creator.bounds.size.width < ceil(needed) - 0.5)
                HARNESS_FAIL(@"the new artist line: measured %lu times, %.1fpt across for %.1fpt of names", (unsigned long)changed,
                             creator.bounds.size.width, needed);
            NSUInteger after = layoutPasses(info, relayout, 10);
            if (after) HARNESS_FAIL(@"10 passes after the new artist line measured the info's labels %lu times", (unsigned long)after);
            NSLog(@"[harness] PASS album measure: no text measured over 10 passes with nothing changed, %lu measurements once the "
                  "artist's name changed, none over 10 passes after", (unsigned long)changed);
            exit(0);
        });
    });
}

// The pinned pair on `page`: download by its identifier, ⋯ the other mirror button pinned there.
static void layoutPinned(UIView *page, SGRMirrorButton **download, SGRMirrorButton **more) {
    *download = nil;
    *more = nil;
    for (UIView *view in page.subviews) {
        if (![view isKindOfClass:SGRMirrorButton.class]) continue;
        if ([view.accessibilityIdentifier isEqualToString:@"Retrine.Album.Download"]) *download = (SGRMirrorButton *)view;
        else *more = (SGRMirrorButton *)view;
    }
}

// The square as the hero draws it, and its shadow, both at `expected` in the page.
static void layoutExpectCard(NSString *what, UIView *hero, UIView *page, CGRect expected) {
    [hero layoutIfNeeded];
    layoutExpectRect([what stringByAppendingString:@", the square"], layoutSquare(hero, page), expected);
    CALayer *shadow = object_getIvar(hero, class_getInstanceVariable(hero.class, "_shadow"));
    layoutExpectRect([what stringByAppendingString:@", its shadow"], [hero.layer convertRect:shadow.frame toLayer:page.layer], expected);
    CGRect path = CGPathGetBoundingBox(shadow.shadowPath);
    layoutExpectRect([what stringByAppendingString:@", its shadow's path"], path, (CGRect){CGPointZero, expected.size});
}

// The phone's geometry (iOS 26, 402pt across, Spotify's square 76pt down the header) and the pair's frames there.
static const CGFloat kLayoutPhoneWidth = 402;
static const CGRect kLayoutDownload = {{298, 62}, {44, 44}}, kLayoutMore = {{342, 62}, {44, 44}};

static CGRect layoutMirrored(CGRect frame, BOOL rtl) {
    if (rtl) frame.origin.x = kLayoutPhoneWidth - CGRectGetMaxX(frame);
    return frame;
}

static void layoutChrome(UIWindow *window, UIView *page, UIView *cover, UIScrollView *scroll, NSString *name,
                         dispatch_block_t relayout) {
    BOOL rtl = [name hasSuffix:@"-rtl"], card = [name hasPrefix:@"chrome-card"];
    __block UIView *hero = nil;
    __block SGRMirrorButton *download = nil, *more = nil;
    layoutWhen(@"the cover under the pinned pair", ^BOOL {
        hero = besideFind(page, @"SGRAlbumHero");
        layoutPinned(page, &download, &more);
        // No veil at all: main.m's pinned hold puts one over the page again once the first has gone.
        return hero && !besideFind(page, @"SGRFieldVeil") && download && !download.hidden && more && !more.hidden;
    }, ^{
        relayout();
        HARNESS_CHECK(fabs(page.bounds.size.width - kLayoutPhoneWidth) < 0.5);
        HARNESS_CHECK((page.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft) == rtl);
        layoutExpectRect(@"the pinned download", download.frame, layoutMirrored(kLayoutDownload, rtl));
        layoutExpectRect(@"the pinned ⋯", more.frame, layoutMirrored(kLayoutMore, rtl));
        CGRect spotify = CGRectMake(77, 76, 248, 248);
        layoutExpectRect(@"Spotify's square", [cover convertRect:cover.bounds toView:page], spotify);
        layoutShot(window, name);
        if (!card) {
            UIView *picture = [hero valueForKey:@"picture"];
            layoutExpectRect(@"the full screen cover under the pair", [picture convertRect:picture.bounds toView:page],
                             CGRectMake(0, 0, kLayoutPhoneWidth, kLayoutPhoneWidth));
            NSLog(@"[harness] PASS album chrome full: the full screen cover is the hero's top square under the pinned pair");
            exit(0);
        }
        CGRect smaller = CGRectMake(96, 114, 210, 210);
        layoutExpectCard(@"under the two-button capsule", hero, page, smaller);
        scroll.contentOffset = CGPointMake(0, 120);
        relayout();
        layoutExpectCard(@"scrolled 120pt", hero, page, CGRectOffset(smaller, 0, -120));
        scroll.contentOffset = CGPointZero;
        relayout();
        UIView *source = download.source, *row = source.superview;
        NSUInteger slot = [row.subviews indexOfObject:source];
        [source removeFromSuperview];
        relayout();
        HARNESS_CHECK(download.hidden && !more.hidden);
        layoutExpectCard(@"under ⋯ alone", hero, page, spotify);
        if ([row isKindOfClass:UIStackView.class]) [(UIStackView *)row insertArrangedSubview:source atIndex:slot];
        else [row insertSubview:source atIndex:slot];
        relayout();
        HARNESS_CHECK(!download.hidden);
        layoutExpectCard(@"with download back", hero, page, smaller);
        NSLog(@"[harness] PASS album chrome card%@: %@ under the capsule, scrolled with the page, %@ under ⋯ alone",
              rtl ? @" rtl" : @"", NSStringFromCGRect(smaller), NSStringFromCGRect(spotify));
        exit(0);
    });
}

static void layoutRun(UIWindow *window, UIView *page, UIView *cover, UIScrollView *scroll, UILabel *artistName,
                      dispatch_block_t relayout) {
    NSString *name = layoutCase();
    if ([name isEqualToString:@"text-size"]) layoutTextSize(window, page);
    else if ([name isEqualToString:@"resize-card"]) layoutResizeCard(window, page, cover, relayout);
    else if ([name isEqualToString:@"beside-scrim"]) layoutBesideScrim(window, page);
    else if ([name isEqualToString:@"beside-faces"]) layoutBesideFaces(window, page, artistName, relayout);
    else if ([name isEqualToString:@"measure"]) layoutMeasure(window, page, artistName, relayout);
    else if ([@[@"chrome-card", @"chrome-card-rtl", @"chrome-full"] containsObject:name]) layoutChrome(window, page, cover, scroll, name, relayout);
    else HARNESS_FAIL(@"no layout case %@", name);
}
