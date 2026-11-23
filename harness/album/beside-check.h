#import "Redesigned/Album/SGRCoverBeside.h"
#import "Core/SGViewTree.h"
#import "../harness-fail.h"

static UIView *besideFind(UIView *root, NSString *className) {
    if ([NSStringFromClass(root.class) isEqualToString:className]) return root;
    for (UIView *child in root.subviews) {
        UIView *found = besideFind(child, className);
        if (found) return found;
    }
    return nil;
}

// The fixture has Spotify's measured frames rather than its layout engine. Give its full-width
// containers UIKit's resize behavior, so an actual scene rotation reaches the hooked header.
static void besideResizable(UIView *root, CGFloat width) {
    for (UIView *child in root.subviews) {
        if (fabs(child.bounds.size.width - width) <= 40)
            child.autoresizingMask |= UIViewAutoresizingFlexibleWidth;
        besideResizable(child, width);
    }
}

@interface SGRBesideCheck : NSObject
@property UIWindow *window;
@property UIViewController *controller;
@property UIView *page;
@property NSString *kind;
@property (copy) dispatch_block_t relayout;
@property (copy) void (^title)(NSString *);
@property CADisplayLink *link;
@property CFTimeInterval deadline;
@property NSInteger stage;
@property CGFloat initialFont;
@property NSArray<UIView *> *actions;
@property NSArray<NSValue *> *actionSizes;
@property BOOL portraitRequested;
@property UIView *cardCover;
@property CALayer *cardMask;
@property BOOL cardHidden;
@property BOOL cardInteractive;
@property BOOL cardAccessibilityHidden;
@end

@implementation SGRBesideCheck
- (SGRHeaderInfo *)info { return (id)besideFind(self.page, @"SGRHeaderInfo"); }
- (UIView *)hero { return besideFind(self.page, [@"SGR" stringByAppendingFormat:@"%@Hero", self.kind]); }
- (NSArray<NSValue *> *)frames {
    NSMutableArray *frames = [NSMutableArray arrayWithObjects:
        [NSValue valueWithCGRect:[self.info convertRect:self.info.bounds toView:self.page]],
        [NSValue valueWithCGRect:[self.hero convertRect:self.hero.bounds toView:self.page]], nil];
    for (UIView *view in self.info.subviews) {
        if (!view.hidden) [frames addObject:[NSValue valueWithCGRect:view.frame]];
    }
    return frames;
}
- (BOOL)settled {
    NSArray<UIView *> *views = [self.info.subviews arrayByAddingObject:self.hero];
    for (UIView *view in views) {
        if (view.hidden) continue;
        CALayer *shown = view.layer.presentationLayer;
        if (shown && (fabs(shown.position.x - view.layer.position.x) > 0.5 ||
            fabs(shown.position.y - view.layer.position.y) > 0.5 ||
            fabs(shown.bounds.size.width - view.bounds.size.width) > 0.5 ||
            fabs(shown.bounds.size.height - view.bounds.size.height) > 0.5)) return NO;
    }
    return YES;
}
- (void)shot:(NSString *)name {
    [self.window layoutIfNeeded];
    CGRect cover = [self.hero convertRect:self.hero.bounds toView:self.window];
    CGRect text = [self.info convertRect:self.info.bounds toView:self.window];
    CGSize size = CGSizeMake(self.window.bounds.size.width, MAX(CGRectGetMaxY(cover), CGRectGetMaxY(text)) + 20);
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:size];
    UIImage *image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        HARNESS_CHECK([self.window drawViewHierarchyInRect:self.window.bounds afterScreenUpdates:YES]);
    }];
    NSString *folder = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents"];
    NSString *file = [folder stringByAppendingPathComponent:[NSString stringWithFormat:@"%@-%@.png", self.kind.lowercaseString, name]];
    HARNESS_CHECK([UIImagePNGRepresentation(image) writeToFile:file atomically:YES]);
    NSLog(@"[harness] SHOT %@", file);
}
- (void)side {
    SGRHeaderInfo *info = self.info;
    UIView *hero = self.hero;
    HARNESS_CHECK(info.sgr_coverBeside);
    CGRect cover = [hero convertRect:hero.bounds toView:self.page];
    CGRect text = [info convertRect:info.bounds toView:self.page];
    HARNESS_CHECK(fabs(cover.size.width - cover.size.height) < 1);
    HARNESS_CHECK(cover.size.width <= 320 && cover.size.width > 200);
    HARNESS_CHECK(!CGRectIntersectsRect(cover, text));
    HARNESS_CHECK(fabs(CGRectGetMidY(cover) - CGRectGetMidY(text)) < 1);
    BOOL rtl = self.page.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;
    HARNESS_CHECK(rtl ? CGRectGetMaxX(text) < CGRectGetMinX(cover) : CGRectGetMaxX(cover) < CGRectGetMinX(text));
    CGFloat gap = rtl ? CGRectGetMinX(cover) - CGRectGetMaxX(text) : CGRectGetMinX(text) - CGRectGetMaxX(cover);
    HARNESS_CHECK(fabs(gap - 28) < 0.5);
    NSMutableArray<UIView *> *buttons = [NSMutableArray array];
    CGRect content = CGRectNull;
    for (UIView *view in info.subviews) {
        if (view.hidden || view.alpha == 0) continue;
        HARNESS_CHECK(CGRectContainsRect(CGRectInset(info.bounds, -1, -1), view.frame));
        if ([view isKindOfClass:UIControl.class]) [buttons addObject:view];
        if ([view isKindOfClass:UIControl.class] || [view isKindOfClass:UILabel.class]) content = CGRectUnion(content, view.frame);
        if ([view isKindOfClass:UILabel.class]) {
            UILabel *label = (UILabel *)view;
            HARNESS_CHECK(label.textAlignment == (rtl ? NSTextAlignmentRight : NSTextAlignmentLeft));
            HARNESS_CHECK([label sizeThatFits:CGSizeMake(label.bounds.size.width, CGFLOAT_MAX)].height <= label.bounds.size.height + 1);
            // The creator's face, when present, leads its name; the other text starts on the column's edge.
            if (label != info.accessibilityElements[1])
                HARNESS_CHECK(fabs(rtl ? CGRectGetMaxX(label.frame) - info.bounds.size.width : label.frame.origin.x) < 0.5);
        }
    }
    HARNESS_CHECK(buttons.count >= 4);
    CGFloat actionLeading = rtl ? info.bounds.size.width - CGRectGetMaxX(buttons.firstObject.frame) : buttons.firstObject.frame.origin.x;
    HARNESS_CHECK(fabs(actionLeading) < 0.5);
    HARNESS_CHECK(fabs(CGRectGetMidY(content) - CGRectGetMidY(info.bounds)) < 1);
    if (!self.actions) {
        self.actions = buttons;
        NSMutableArray *sizes = [NSMutableArray array];
        for (UIView *button in buttons) [sizes addObject:[NSValue valueWithCGSize:button.bounds.size]];
        self.actionSizes = sizes;
    } else {
        for (NSUInteger i = 0; i < self.actions.count; i++)
            HARNESS_CHECK(CGSizeEqualToSize(self.actions[i].bounds.size, self.actionSizes[i].CGSizeValue));
    }
    if ([self.kind isEqualToString:@"Playlist"]) {
        UILabel *description = info.accessibilityElements.lastObject;
        HARNESS_CHECK([description isKindOfClass:UILabel.class]);
        for (UIView *button in buttons) HARNESS_CHECK(CGRectGetMinY(description.frame) > CGRectGetMaxY(button.frame));
        if (self.stage == 0) HARNESS_CHECK(description.bounds.size.height > description.font.lineHeight * 1.5);
    }
    for (NSUInteger i = 0; i < buttons.count; i++)
        for (NSUInteger j = i + 1; j < buttons.count; j++)
            HARNESS_CHECK(!CGRectIntersectsRect(buttons[i].frame, buttons[j].frame));
    HARNESS_CHECK(info.superview.accessibilityElements.firstObject == hero);
    HARNESS_CHECK([info.accessibilityElements.firstObject isKindOfClass:UILabel.class]);
}
- (void)next {
    self.stage++;
    self.deadline = CACurrentMediaTime() + 20;
}
- (void)checkCardRestored {
    HARNESS_CHECK(self.cardCover.layer.hidden == self.cardHidden);
    HARNESS_CHECK(self.cardCover.layer.mask == self.cardMask);
    HARNESS_CHECK(self.cardCover.userInteractionEnabled == self.cardInteractive);
    HARNESS_CHECK(self.cardCover.accessibilityElementsHidden == self.cardAccessibilityHidden);
}
- (void)checkPhoneFrames {
    // Independent pre-beside captures, not the current implementation with its setting off.
    // The README records the source commit and fixture environment.
    static const CGRect album[][8] = {
        {{0,0,430,486.67}, {0,0,430,412}, {20,342,390,27}, {160,371,111,24},
         {20,399,390,15}, {77,430,48,48}, {141,430,148,48}, {305,430,48,48}},
        {{0,0,390,486.67}, {0,0,390,412}, {20,342,350,27}, {140,371,111,24},
         {20,399,350,15}, {57,430,48,48}, {121,430,148,48}, {285,430,48,48}},
        {{0,0,320,486.67}, {0,0,320,412}, {20,342,280,27}, {105,371,111,24},
         {20,399,280,15}, {22,430,48,48}, {86,430,148,48}, {250,430,48,48}}
    };
    static const CGRect playlist[][9] = {
        {{0,266.67,430,178.33}, {0,0,430,305}, {20,-18,390,27}, {160,11,111,24},
         {20,39,390,15}, {20,132,390,32}, {77,70,48,48}, {141,70,148,48}, {305,70,48,48}},
        {{0,266.67,390,178.33}, {0,0,390,305}, {20,-18,350,27}, {140,11,111,24},
         {20,39,350,15}, {20,132,350,32}, {57,70,48,48}, {121,70,148,48}, {285,70,48,48}},
        {{0,266.67,320,178.33}, {0,0,320,305}, {20,-18,280,27}, {105,11,111,24},
         {20,39,280,15}, {20,132,280,32}, {22,70,48,48}, {86,70,148,48}, {250,70,48,48}}
    };
    CGFloat width = self.info.bounds.size.width;
    HARNESS_CHECK(width == 430 || width == 390 || width == 320);
    NSUInteger variant = width == 430 ? 0 : (width == 390 ? 1 : 2);
    BOOL isAlbum = [self.kind isEqualToString:@"Album"];
    const CGRect *expected = isAlbum ? album[variant] : playlist[variant];
    NSArray<NSValue *> *actual = self.frames;
    HARNESS_CHECK(actual.count == (isAlbum ? 8 : 9));
    for (NSUInteger i = 0; i < actual.count; i++) {
        CGRect a = actual[i].CGRectValue, e = expected[i];
        if (fabs(a.origin.x-e.origin.x) >= 0.01 || fabs(a.origin.y-e.origin.y) >= 0.01 ||
            fabs(a.size.width-e.size.width) >= 0.01 || fabs(a.size.height-e.size.height) >= 0.01)
            HARNESS_FAIL(@"%@ %.0fpt frame %lu: %@, committed %@", self.kind, width,
                         (unsigned long)i, NSStringFromCGRect(a), NSStringFromCGRect(e));
    }
}
- (void)cardTick {
    if (self.stage == 0) {
        SGForEachView(self.page, ^(UIView *view) {
            if ([view.accessibilityIdentifier isEqualToString:@"Components.Header.UI.ArtworkImage"])
                self.cardCover = view;
        });
        HARNESS_CHECK(self.cardCover && !self.cardCover.layer.hidden && !self.cardCover.layer.mask);
        self.cardHidden = self.cardCover.layer.hidden;
        self.cardInteractive = self.cardCover.userInteractionEnabled;
        self.cardAccessibilityHidden = self.cardCover.accessibilityElementsHidden;
        [NSUserDefaults.standardUserDefaults setBool:YES forKey:SGRKeyCoverBeside];
    } else if (self.stage == 1 || self.stage == 3 || self.stage == 5) {
        if (!self.info.sgr_coverBeside) return;
        HARNESS_CHECK(self.cardCover.layer.hidden);
        if (self.stage == 1) {
            [NSUserDefaults.standardUserDefaults setBool:NO forKey:SGRKeyCoverBeside];
        } else if (self.stage == 3) {
            self.controller.traitOverrides.horizontalSizeClass = UIUserInterfaceSizeClassCompact;
            self.relayout();
        } else {
            UIView *old = self.cardCover;
            UIView *replacement = [[UIView alloc] initWithFrame:old.frame];
            replacement.accessibilityIdentifier = old.accessibilityIdentifier;
            [old.superview addSubview:replacement];
            [old removeFromSuperview];
            self.relayout();
            [self checkCardRestored];
            self.cardCover = replacement;
            self.cardMask = nil;
            HARNESS_CHECK(replacement.layer.hidden);
            [NSUserDefaults.standardUserDefaults setBool:NO forKey:SGRKeyCoverBeside];
        }
    } else {
        if (self.info.sgr_coverBeside) return;
        [self checkCardRestored];
        if (self.stage == 2) {
            self.cardMask = [CALayer layer];
            self.cardMask.frame = self.cardCover.bounds;
            self.cardMask.backgroundColor = UIColor.blackColor.CGColor;
            self.cardCover.layer.mask = self.cardMask;
            [NSUserDefaults.standardUserDefaults setBool:YES forKey:SGRKeyCoverBeside];
        } else if (self.stage == 4) {
            self.controller.traitOverrides.horizontalSizeClass = UIUserInterfaceSizeClassRegular;
            self.relayout();
        } else {
            NSLog(@"[harness] PASS Playlist Card cover restored after setting off, compact width and cover reuse");
            [self.link invalidate];
            self.link = nil;
            return;
        }
    }
    [self next];
}
- (void)tick {
    HARNESS_CHECK(CACurrentMediaTime() < self.deadline);
    if (!self.window.windowScene || !self.info || !self.hero) return;
    [self.window layoutIfNeeded];
    if (self.stage < 4 && !self.settled) return;
    if ([NSProcessInfo.processInfo.arguments containsObject:@"card-cover"]) {
        [self cardTick];
        return;
    }
    if (self.stage == 0) {
        UIView *veil = besideFind(self.page, @"SGRFieldVeil");
        if (veil && (veil.layer.presentationLayer ?: veil.layer).opacity > 0.01) return;
        self.relayout();
        [self.window layoutIfNeeded];
        if (self.window.traitCollection.userInterfaceIdiom != UIUserInterfaceIdiomPad) {
            HARNESS_CHECK(!self.info.sgr_coverBeside);
            [self checkPhoneFrames];
            [NSUserDefaults.standardUserDefaults setBool:NO forKey:SGRKeyCoverBeside];
            self.stage = 20;
            return;
        }
        if (self.window.bounds.size.width > self.window.bounds.size.height) {
            if (!self.portraitRequested) {
                self.portraitRequested = YES;
                [self.window.windowScene requestGeometryUpdateWithPreferences:
                    [[UIWindowSceneGeometryPreferencesIOS alloc] initWithInterfaceOrientations:UIInterfaceOrientationMaskPortrait]
                    errorHandler:^(NSError *error) { HARNESS_FAIL(@"portrait: %@", error); }];
            }
            return;
        }
        [self side];
        self.initialFont = ((UILabel *)self.info.accessibilityElements.firstObject).font.pointSize;
        [self shot:@"portrait"];
        besideResizable(self.page, self.page.bounds.size.width);
        self.page.autoresizingMask |= UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self next];
        [self.window.windowScene requestGeometryUpdateWithPreferences:
            [[UIWindowSceneGeometryPreferencesIOS alloc] initWithInterfaceOrientations:UIInterfaceOrientationMaskLandscapeRight]
            errorHandler:^(NSError *error) { HARNESS_FAIL(@"rotation: %@", error); }];
    } else if (self.stage == 1) {
        if (self.window.bounds.size.width < self.window.bounds.size.height) return;
        if (self.controller.transitionCoordinator) return;
        self.relayout();
        [self.window layoutIfNeeded];
        [self side];
        [self shot:@"landscape"];
        self.title(@"A Long Evening of Music from Somewhere Beyond the Sea");
        self.controller.traitOverrides.preferredContentSizeCategory = UIContentSizeCategoryExtraExtraExtraLarge;
        self.relayout();
        [self next];
    } else if (self.stage == 2) {
        [self side];
        HARNESS_CHECK(((UILabel *)self.info.accessibilityElements.firstObject).font.pointSize > self.initialFont);
        [self shot:@"large-text"];
        self.page.semanticContentAttribute = UISemanticContentAttributeForceRightToLeft;
        self.relayout();
        [self next];
    } else if (self.stage == 3) {
        [self side];
        [self shot:@"rtl"];
        [NSUserDefaults.standardUserDefaults setBool:NO forKey:SGRKeyCoverBeside];
        [self next];
    } else if (self.stage == 4) {
        if (self.info.sgr_coverBeside) return;
        HARNESS_CHECK(self.info.bounds.size.width > self.hero.bounds.size.width - 1);
        for (NSUInteger i = 0; i < self.actions.count; i++)
            HARNESS_CHECK(CGSizeEqualToSize(self.actions[i].bounds.size, self.actionSizes[i].CGSizeValue));
        [NSUserDefaults.standardUserDefaults setBool:YES forKey:SGRKeyCoverBeside];
        [self next];
    } else if (self.stage == 5) {
        if (!self.info.sgr_coverBeside) return;
        [self side];
        self.title([@"A very long title with many words " stringByPaddingToLength:800 withString:@"and more music " startingAtIndex:0]);
        self.controller.traitOverrides.preferredContentSizeCategory = UIContentSizeCategoryAccessibilityExtraExtraExtraLarge;
        self.relayout();
        [self next];
    } else if (self.stage == 6) {
        HARNESS_CHECK(!self.info.sgr_coverBeside);
        for (UIView *view in self.info.subviews)
            if (!view.hidden && [view isKindOfClass:UILabel.class])
                HARNESS_CHECK(CGRectGetMinY([view convertRect:view.bounds toView:self.page]) >= 0);
        self.title(@"Music");
        self.controller.traitOverrides.preferredContentSizeCategory = UIContentSizeCategoryLarge;
        self.controller.traitOverrides.horizontalSizeClass = UIUserInterfaceSizeClassCompact;
        self.relayout();
        [self next];
    } else if (self.stage == 7) {
        HARNESS_CHECK(!self.info.sgr_coverBeside);
        self.controller.traitOverrides.horizontalSizeClass = UIUserInterfaceSizeClassRegular;
        self.relayout();
        [self next];
    } else if (self.stage == 8) {
        [self side];
        NSLog(@"[harness] PASS %@ cover beside: portrait landscape large-text RTL live-setting fallback compact", self.kind);
        [self.link invalidate];
        self.link = nil;
    } else if (self.stage == 20) {
        HARNESS_CHECK(!self.info.sgr_coverBeside);
        [self checkPhoneFrames];
        NSLog(@"[harness] PASS %@ iPhone unchanged %.0fpt", self.kind, self.info.bounds.size.width);
        [self.link invalidate];
        self.link = nil;
    }
}
@end

static void besideRun(UIWindow *window, UIViewController *controller, UIView *page, NSString *kind,
                      dispatch_block_t relayout, void (^title)(NSString *)) {
    SGRBesideCheck *check = [SGRBesideCheck new];
    check.window = window;
    check.controller = controller;
    check.page = page;
    check.kind = kind;
    check.relayout = relayout;
    check.title = title;
    check.deadline = CACurrentMediaTime() + 20;
    check.link = [CADisplayLink displayLinkWithTarget:check selector:@selector(tick)];
    [check.link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
}
