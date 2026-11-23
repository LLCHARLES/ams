// Rendered role order and stale-publication checks against the shipping lyrics view.
static UILabel *extrasLabel(UIView *view, NSString *text) {
    if ([view isKindOfClass:UILabel.class] && [((UILabel *)view).text isEqual:text]) return (id)view;
    for (UIView *child in view.subviews) {
        UILabel *label = extrasLabel(child, text);
        if (label) return label;
    }
    return nil;
}

static BOOL extrasWait(BOOL (^ready)(void)) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:3];
    while (!ready() && deadline.timeIntervalSinceNow > 0)
        [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.001]];
    return ready();
}

static SGKaraokeLine *extrasFixture(void) {
    SGKaraokeLine *line = sungLine(100, @"君 の 名前");
    for (NSUInteger i = 1; i < line.words.count; i++) line.words[i].joined = YES;
    line.translation = @"Your name";
    line.backing = sungLine(300, @"あ");
    return line;
}

static atomic_bool extrasRubyOnMain;
static IMP extrasOriginalRubyInit;
static id extrasRubyInit(id self, SEL selector) {
    if (NSThread.isMainThread) atomic_store(&extrasRubyOnMain, true);
    return ((id (*)(id, SEL))extrasOriginalRubyInit)(self, selector);
}

// Delay one already-prepared style outside the shared preparation lock. No production test hook.
static atomic_bool extrasHoldNext, extrasHeld, extrasRetired, extrasHoldTimedOut;
static dispatch_semaphore_t extrasRelease;
static __weak id extrasHeldStyle;
static IMP extrasOriginalSetExtras;
static char extrasLifetimeKey;
@interface SGExtrasPreparationLifetime : NSObject
@end
@implementation SGExtrasPreparationLifetime
- (void)dealloc { atomic_store(&extrasRetired, true); }
@end
static void extrasSetPrepared(id self, SEL selector, id value) {
    ((void (*)(id, SEL, id))extrasOriginalSetExtras)(self, selector, value);
    if (!NSThread.isMainThread && atomic_exchange(&extrasHoldNext, false)) {
        objc_setAssociatedObject(self, &extrasLifetimeKey, [SGExtrasPreparationLifetime new], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        extrasHeldStyle = self;
        atomic_store(&extrasHeld, true);
        if (dispatch_semaphore_wait(extrasRelease, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC)))
            atomic_store(&extrasHoldTimedOut, true);
    }
}

static void extrasChecks(UIWindow *window) {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSArray *keys = @[SGKeyLyricsRomanised, SGKeyLyricsPronunciationHangul, SGKeyLyricsJapaneseKana,
        SGKeyLyricsFurigana, SGKeyLyricsSimulateWords, SGRKeyLyricsPronunciation, SGRKeyLyricsTranslation,
        SGRKeyLyricsTextOrder];
    NSMutableDictionary *saved = [NSMutableDictionary dictionary];
    for (NSString *key in keys) saved[key] = [defaults objectForKey:key] ?: NSNull.null;
    [defaults setBool:YES forKey:SGKeyLyricsRomanised];
    [defaults setBool:NO forKey:SGKeyLyricsPronunciationHangul];
    [defaults setBool:NO forKey:SGKeyLyricsJapaneseKana];
    [defaults setBool:YES forKey:SGKeyLyricsFurigana];
    [defaults setBool:NO forKey:SGKeyLyricsSimulateWords];
    [defaults setBool:NO forKey:SGRKeyLyricsPronunciation];
    [defaults setBool:YES forKey:SGRKeyLyricsTranslation];
    SGHarnessPlayingTrack = @"extras-roles";
    SGHarnessStartClock(300, 0, -1, 0);
    SGKaraokeLine *line = extrasFixture();
    SGKaraokeKeepLines(SGHarnessPlayingTrack, @[line]);
    UIViewController *root = [UIViewController new];
    window.rootViewController = root;
    [window makeKeyAndVisible];
    // Override only this model's inherited initializer, never NSObject's.
    class_addMethod(SGLyricsRuby.class, @selector(init), (IMP)extrasRubyInit, "@@:");
    extrasOriginalRubyInit = class_getMethodImplementation(NSObject.class, @selector(init));
    atomic_store(&extrasRubyOnMain, false);
    SGRKaraokeView *(^makeView)(void) = ^SGRKaraokeView * {
        SGRKaraokeView *view = [[SGRKaraokeView alloc] initWithFrame:CGRectMake(0, 0, 500, 700)];
        [root.view addSubview:view];
        ((void (*)(id, SEL))objc_msgSend)(view, NSSelectorFromString(@"tick"));
        [view layoutSubviews];
        return view;
    };
    SGRKaraokeView *player = makeView(), *page = makeView();
    check(extrasWait(^BOOL { return extrasLabel(player, @"kimi") && extrasLabel(page, @"kimi"); }),
          @"two lyric views show generated timed pronunciation with the source-pronunciation switch off");
    check(extrasLabel(page, @"a") != nil, @"generated pronunciation includes backing vocals");
    check(extrasLabel(page, @"なまえ") != nil && !atomic_load(&extrasRubyOnMain),
          @"cold contextual ruby is prepared off main before view construction");
    for (NSArray *order in @[@[@0,@1,@2], @[@0,@2,@1], @[@1,@0,@2],
                            @[@1,@2,@0], @[@2,@0,@1], @[@2,@1,@0]]) {
        SGRSetLyricsTextOrder(order);
        BOOL ordered = extrasWait(^BOOL {
            NSArray *labels = @[extrasLabel(page, @"君") ?: NSNull.null, extrasLabel(page, @"kimi") ?: NSNull.null,
                                extrasLabel(page, @"Your name") ?: NSNull.null];
            if ([labels containsObject:NSNull.null]) return NO;
            CGFloat prior = -CGFLOAT_MAX;
            for (NSNumber *role in order) {
                UILabel *label = labels[role.unsignedIntegerValue];
                CGFloat y = [label convertPoint:CGPointZero toView:page].y;
                if (y <= prior) return NO;
                prior = y;
            }
            return YES;
        });
        check(ordered, [NSString stringWithFormat:@"generated reading occupies pronunciation role in order %@", order]);
    }
    SGRSetLyricsTextShown(SGRLyricsTextTranslation, NO);
    check(extrasWait(^BOOL { return !extrasLabel(page, @"Your name") && extrasLabel(page, @"kimi") &&
        !extrasLabel(player, @"Your name") && extrasLabel(player, @"kimi"); }),
          @"hidden translation leaves generated pronunciation in the role layout");
    Method setter = class_getInstanceMethod(NSClassFromString(@"SGRKaraokeStyle"), NSSelectorFromString(@"setExtras:"));
    extrasOriginalSetExtras = method_setImplementation(setter, (IMP)extrasSetPrepared);
    extrasRelease = dispatch_semaphore_create(0);
    atomic_store(&extrasHoldNext, true);
    atomic_store(&extrasHeld, false);
    atomic_store(&extrasRetired, false);
    atomic_store(&extrasHoldTimedOut, false);
    ((void (*)(id, SEL))objc_msgSend)(page, NSSelectorFromString(@"restyle"));
    check(extrasWait(^BOOL { return atomic_load(&extrasHeld); }), @"old preparation is held before publication");
    // Publish a different source/alphabet while the old job is still held.
    SGHarnessPlayingTrack = @"extras-replaced";
    SGKaraokeLine *replacement = sungLine(100, @"あ");
    SGKaraokeKeepLines(SGHarnessPlayingTrack, @[replacement]);
    for (SGRKaraokeView *view in @[player, page]) {
        ((void (*)(id, SEL))objc_msgSend)(view, NSSelectorFromString(@"tick"));
        [view layoutSubviews];
    }
    [defaults setBool:YES forKey:SGKeyLyricsPronunciationHangul];
    [NSNotificationCenter.defaultCenter postNotificationName:SGLyricsRomanisedDidChangeNotification object:nil];
    check(extrasWait(^BOOL { return extrasLabel(player, @"아") && extrasLabel(page, @"아"); }) &&
          !extrasLabel(page, @"kimi") && !extrasLabel(page, @"a"),
          @"track/source/alphabet revisions discard an in-flight reading and its old layout");
    dispatch_semaphore_signal(extrasRelease);
    // A rejected job releases its style; with rejection removed it becomes the displayed style.
    // Both outcomes are completion boundaries, not a timer guessed to be longer than preparation.
    BOOL oldFinished = extrasWait(^BOOL {
        return atomic_load(&extrasRetired) || (extrasHeldStyle && [page valueForKey:@"style"] == extrasHeldStyle);
    });
    check(oldFinished && !atomic_load(&extrasHoldTimedOut) && extrasLabel(page, @"아") &&
          !extrasLabel(page, @"kimi") && !extrasLabel(page, @"a"),
          @"releasing the old preparation after replacement cannot change the displayed replacement");
    method_setImplementation(setter, extrasOriginalSetExtras);
    replacement.pronunciation = sungLine(100, @"PROVIDER");
    [NSNotificationCenter.defaultCenter postNotificationName:SGLyricsRomanisedDidChangeNotification object:nil];
    check(extrasWait(^BOOL { return extrasLabel(page, @"PROVIDER") && !extrasLabel(page, @"아"); }),
          @"provider pronunciation is authoritative even when generation is enabled");
    replacement.pronunciation = nil;
    [defaults setBool:NO forKey:SGKeyLyricsRomanised];
    [NSNotificationCenter.defaultCenter postNotificationName:SGLyricsRomanisedDidChangeNotification object:nil];
    check(extrasWait(^BOOL { return extrasLabel(page, @"あ") && !extrasLabel(page, @"아") && !extrasLabel(page, @"PROVIDER"); }),
          @"missing pronunciation role leaves original lyrics when generation is disabled");
    [defaults setBool:YES forKey:SGKeyLyricsRomanised];
    [defaults setBool:NO forKey:SGKeyLyricsPronunciationHangul];
    for (NSNumber *timing in @[@(SGKaraokeTimingLine), @(SGKaraokeTimingNone)]) {
        SGHarnessPlayingTrack = [NSString stringWithFormat:@"extras-timing-%@", timing];
        SGKaraokeLine *estimated = extrasFixture();
        estimated.timing = timing.unsignedIntegerValue;
        estimated.backing = nil;
        if (estimated.timing == SGKaraokeTimingNone) {
            estimated.start = estimated.end = 0;
            for (SGKaraokeWord *word in estimated.words) word.start = word.end = 0;
        }
        SGKaraokeKeepLines(SGHarnessPlayingTrack, @[estimated]);
        ((void (*)(id, SEL))objc_msgSend)(page, NSSelectorFromString(@"tick"));
        [page layoutSubviews];
        BOOL ready = extrasWait(^BOOL { return extrasLabel(page, @"kimi") != nil; });
        check(ready, @"line-timed and untimed readings remain visible");
        if (!ready) continue;
        UILabel *label = extrasLabel(page, @"kimi");
        UIView *word = label.superview, *row = word.superview;
        UIView *filled = nil;
        for (UIView *child in word.subviews) if (child.layer.mask) filled = child;
        ((void (*)(id, SEL, double))objc_msgSend)(row, NSSelectorFromString(@"showTime:"), 100);
        CGRect startMask = filled.layer.mask.frame;
        ((void (*)(id, SEL, double))objc_msgSend)(row, NSSelectorFromString(@"showTime:"), 1000);
        check(filled && CGRectEqualToRect(startMask, filled.layer.mask.frame) &&
              CGRectGetMaxX(startMask) >= filled.bounds.size.width,
              @"simulated timing off: estimated/untimed pronunciation lights whole, never sweeps");
    }
    [defaults setBool:NO forKey:SGKeyLyricsFurigana];
    NSArray *originals = @[@"あ", @"い", @"う", @"え", @"お", @"か", @"き", @"く", @"け", @"こ", @"さ", @"し"];
    NSArray *readings = @[@"a", @"i", @"u", @"e", @"o", @"ka", @"ki", @"ku", @"ke", @"ko", @"sa", @"shi"];
    for (NSArray *order in @[@[@0,@1,@2], @[@1,@0,@2]]) {
        SGHarnessPlayingTrack = [NSString stringWithFormat:@"extras-wrapped-%@", order[0]];
        SGKaraokeLine *wrapped = sungLine(0, [originals componentsJoinedByString:@" "]);
        wrapped.timing = SGKaraokeTimingNone; wrapped.start = wrapped.end = 0;
        for (SGKaraokeWord *word in wrapped.words) word.start = word.end = 0;
        SGKaraokeKeepLines(SGHarnessPlayingTrack, @[wrapped]);
        page.frame = CGRectMake(0, 0, 140, 700);
        SGRSetLyricsTextOrder(order);
        ((void (*)(id, SEL))objc_msgSend)(page, NSSelectorFromString(@"tick"));
        [page layoutSubviews];
        BOOL originalFirst = [order[0] integerValue] == 0;
        NSArray *lead = originalFirst ? originals : readings, *under = originalFirst ? readings : originals;
        BOOL ready = extrasWait(^BOOL {
            UILabel *first = extrasLabel(page, lead[0]), *second = extrasLabel(page, under[0]);
            return first && second && [first convertPoint:CGPointZero toView:page].y < [second convertPoint:CGPointZero toView:page].y;
        });
        BOOL aligned = ready;
        NSMutableSet *rows = [NSMutableSet set];
        for (NSUInteger i = 0; ready && i < lead.count; i++) {
            UILabel *top = extrasLabel(page, lead[i]), *bottom = extrasLabel(page, under[i]);
            if (!top || !bottom) { aligned = NO; break; }
            CGFloat topY = [top convertPoint:CGPointZero toView:page].y;
            CGFloat bottomY = [bottom convertPoint:CGPointZero toView:page].y;
            [rows addObject:@(topY)];
            aligned &= bottomY > topY;
            for (NSUInteger j = i + 1; j < lead.count; j++) {
                UILabel *next = extrasLabel(page, lead[j]);
                if (!next) { aligned = NO; break; }
                CGFloat nextY = [next convertPoint:CGPointZero toView:page].y;
                if (nextY > topY) { aligned &= bottomY < nextY; break; }
            }
        }
        check(aligned && rows.count > 1, originalFirst ?
            @"wrapped untimed readings stay with their source row" : @"wrapped untimed originals stay with their leading reading row");
    }
    page.frame = CGRectMake(0, 0, 500, 700);
    [defaults setBool:YES forKey:SGKeyLyricsFurigana];
    NSMutableArray *many = [NSMutableArray array];
    for (NSUInteger i = 0; i < 80; i++) {
        SGKaraokeLine *entry = sungLine(100 + i * 2000,
            i == 79 ? @"君 の 名前" : [NSString stringWithFormat:@"君の名前%lu", (unsigned long)i]);
        [many addObject:entry];
    }
    SGHarnessPlayingTrack = @"extras-scroll";
    SGKaraokeKeepLines(SGHarnessPlayingTrack, many);
    ((void (*)(id, SEL))objc_msgSend)(page, NSSelectorFromString(@"tick"));
    [page layoutSubviews];
    check(extrasWait(^BOOL { return extrasLabel(page, @"なまえ") != nil; }),
          @"long song prepares ruby before viewport construction");
    check([page valueForKey:@"shown"][@79] == nil, @"last pronunciation row is not materialized before scrolling");
    NSMutableArray *equivalent = [NSMutableArray array];
    for (SGKaraokeLine *entry in many) [equivalent addObject:sungLine(entry.start, SGKaraokeLineText(entry))];
    SGKaraokeKeepLines(SGHarnessPlayingTrack, equivalent);
    ((void (*)(id, SEL))objc_msgSend)(page, NSSelectorFromString(@"tick"));
    UIScrollView *scroll = [page valueForKey:@"scroll"];
    [scroll.delegate scrollViewWillBeginDragging:scroll];
    for (NSUInteger i = 1; i <= 5; i++) {
        scroll.contentOffset = CGPointMake(0,
            MAX(0, scroll.contentSize.height + scroll.adjustedContentInset.bottom - scroll.bounds.size.height) * i / 5.0);
        ((void (*)(id, SEL))objc_msgSend)(page, NSSelectorFromString(@"showLinesInSight"));
    }
    check(extrasWait(^BOOL {
        ((void (*)(id, SEL))objc_msgSend)(page, NSSelectorFromString(@"showLinesInSight"));
        UIView *last = [page valueForKey:@"shown"][@79];
        return extrasLabel(last, @"kimi") && extrasLabel(last, @"なまえ");
    }), @"newly materialized rows retain pronunciation and furigana after an equivalent replacement");
    check(!atomic_load(&extrasRubyOnMain), @"rapid furigana-enabled scrolling never performs cold ruby work on main");
    [player removeFromSuperview]; [page removeFromSuperview];
    method_setImplementation(class_getInstanceMethod(SGLyricsRuby.class, @selector(init)), extrasOriginalRubyInit);
    for (NSString *key in keys) {
        if (saved[key] == NSNull.null) [defaults removeObjectForKey:key];
        else [defaults setObject:saved[key] forKey:key];
    }
}
