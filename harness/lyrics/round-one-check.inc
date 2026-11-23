// Real view and scheduler; only provider boundaries and the recognizer's scheduling are instrumented.
#import <NaturalLanguage/NaturalLanguage.h>
#import "Shared/Lyrics/LyricsLanguage.h"
#import "Shared/LyricsSources/LyricsSources.h"
#import "Redesigned/Lyrics/LyricCardPicker.h"
extern void (^SGHarnessDeepL)(NSArray<SGKaraokeLine *> *, SGHarnessDone);
extern void (^SGHarnessOnDevice)(NSArray<NSString *> *, SGHarnessDone);
extern void (^SGHarnessLyricCardPresented)(NSArray<SGRLyricCardLine *> *, NSUInteger);

static atomic_bool languageOnMain, languageHoldNext, languageHeld, languageHoldTimeout;
static atomic_uint languageCalls;
static dispatch_semaphore_t languageRelease;
static IMP originalProcessString;
static void languageProcessString(id self, SEL selector, NSString *text) {
    atomic_fetch_add(&languageCalls, 1);
    if (NSThread.isMainThread) atomic_store(&languageOnMain, true);
    if (!NSThread.isMainThread && atomic_exchange(&languageHoldNext, false)) {
        atomic_store(&languageHeld, true);
        if (dispatch_semaphore_wait(languageRelease, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)))
            atomic_store(&languageHoldTimeout, true);
    }
    ((void (*)(id, SEL, id))originalProcessString)(self, selector, text);
}

static void unresolvedChecks(void) {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    [defaults removeObjectForKey:@"translateTo"];
    [defaults setBool:YES forKey:SGRKeyLyricsAutoTranslation];
    [defaults setBool:YES forKey:SGKeyLyricsGoogleTranslate];
    [defaults setBool:YES forKey:SGKeyLyricsBingTranslate];
    [defaults setBool:YES forKey:SGKeyLyricsTranslateOnDevice];
    [defaults setBool:YES forKey:@"onDevice"];
    [defaults setBool:YES forKey:@"deepl"];
    [defaults setBool:YES forKey:@"openai"];
    for (NSNumber *provider in @[@(SGRAutoTranslatorGoogle), @(SGRAutoTranslatorBing),
            @(SGRAutoTranslatorDeepL), @(SGRAutoTranslatorOnDevice)]) {
        SGRSetAutoTranslationOrder(@[@(SGRAutoTranslatorOpenAI), provider]);
        NSString *track = [NSString stringWithFormat:@"unresolved-%@", provider];
        SGKaraokeLine *source = sungLine(0, @"source"); source.translation = @"kept";
        NSArray *lines = @[source, sungLine(1000, @"alpha"), sungLine(2000, @"♪"),
                          sungLine(3000, @"beta"), sungLine(4000, @"gamma")];
        __block NSArray *sentTexts = nil;
        __block BOOL contextual = NO, finished = NO;
        SGHarnessOpenAI = ^(NSArray *sent, SGHarnessDone done) {
            contextual = [markAll(sent, @"") isEqual:@[@"source", @"alpha", @"♪", @"beta", @"gamma"]];
            done(@[@"discard", @"first", @"", @"", @""], nil);
        };
        void (^answer)(NSArray *, SGHarnessDone) = ^(NSArray *sent, SGHarnessDone done) {
            sentTexts = markAll(sent, @"");
            done(@[@"second", @"third"], nil);
        };
        SGHarnessGoogle = answer; SGHarnessBing = answer; SGHarnessDeepL = answer;
        SGHarnessOnDevice = ^(NSArray *sent, SGHarnessDone done) {
            sentTexts = sent; done(@[@"second", @"third"], nil);
        };
        NSUInteger revision = SGRAutoTranslationClaim(track, @"en");
        SGRTranslateLyrics(lines, track, @"en", revision,
            ^(NSArray *sent, NSString *song, NSString *target, SGRAutoTranslated progress, SGRAutoTranslated done) {
                SGRAutoTranslateInOrder(sent, song, target, revision, ^BOOL { return YES; }, progress, done);
            }, nil, ^(NSArray *answer, NSString *error) { finished = YES; });
        check(extrasWait(^BOOL { return finished; }) && contextual &&
              [sentTexts isEqual:@[@"beta", @"gamma"]] &&
              [translations(lines) isEqual:@"kept | first* | - | second* | third*"],
              [NSString stringWithFormat:@"provider %@ receives only unresolved lines, maps gaps, and preserves full AI context", provider]);
    }
    SGHarnessGoogle = nil; SGHarnessBing = nil; SGHarnessDeepL = nil; SGHarnessOnDevice = nil; SGHarnessOpenAI = nil;
    [defaults setBool:NO forKey:@"onDevice"]; [defaults setBool:NO forKey:@"deepl"]; [defaults setBool:NO forKey:@"openai"];
    [defaults setBool:NO forKey:SGRKeyLyricsAutoTranslation]; SGRAutoTranslationSettingsChanged();
}

static void languageSnapshotChecks(UIWindow *window) {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    for (NSString *key in @[SGKeyLyricsRomanised, SGKeyLyricsFurigana, SGRKeyLyricsPronunciation,
                            SGRKeyLyricsTranslation, SGKeyLyricsCulturalNotes])
        [defaults setBool:NO forKey:key];
    [defaults removeObjectForKey:SGKeyLyricsLanguageRules];
    [defaults removeObjectForKey:SGKeyLyricsTrackLanguages];
    [defaults removeObjectForKey:@"translateTo"];
    Method process = class_getInstanceMethod(NLLanguageRecognizer.class, @selector(processString:));
    originalProcessString = method_setImplementation(process, (IMP)languageProcessString);
    atomic_store(&languageOnMain, false); atomic_store(&languageCalls, 0);
    languageRelease = dispatch_semaphore_create(0);
    atomic_store(&languageHoldNext, true); atomic_store(&languageHeld, false);
    atomic_store(&languageHoldTimeout, false);
    SGKaraokeLine *mutable = sungLine(0, @"This quiet morning I can hear the birds singing outside my window.");
    NSArray *snapshotLines = @[mutable];
    __block BOOL done = NO, foreign = YES;
    __block NSString *detected = nil;
    SGRAnalyzeLyricsLanguage(snapshotLines, @"en", ^(BOOL other, NSString *tag) {
        foreign = other; detected = tag; done = YES;
    });
    check(!done && extrasWait(^BOOL { return atomic_load(&languageHeld); }),
          @"cold language analysis yields main while inference runs on its worker");
    mutable.words.firstObject.text = @"こんにちは";
    dispatch_semaphore_signal(languageRelease);
    check(extrasWait(^BOOL { return done; }) && !foreign && [detected isEqual:@"en"],
          @"analysis reads immutable text, not words mutated after scheduling");
    __block BOOL changed = NO;
    SGRAnalyzeLyricsLanguage(snapshotLines, @"en", ^(BOOL other, NSString *tag) { changed = [tag isEqual:@"ja"]; });
    check(extrasWait(^BOOL { return changed; }), @"changed text in the same array does not reuse the old language");
    NSUInteger calls = atomic_load(&languageCalls);
    __block BOOL cached = NO;
    SGRAnalyzeLyricsLanguage(SGLyricsLanguageSnapshot(snapshotLines), @"en", ^(BOOL other, NSString *tag) { cached = [tag isEqual:@"ja"]; });
    check(cached && calls == atomic_load(&languageCalls), @"equivalent snapshots reuse analysis without recognizer work");
    __block BOOL targetDone = NO;
    SGRAnalyzeLyricsLanguage(@[sungLine(0, @"This quiet morning I can hear the birds singing outside my window.")], @"ko",
        ^(BOOL other, NSString *tag) { targetDone = other && [tag isEqual:@"en"]; });
    check(extrasWait(^BOOL { return targetDone; }), @"a different target gets its own foreign-language decision");

    UIViewController *root = [UIViewController new]; window.rootViewController = root; [window makeKeyAndVisible];
    SGHarnessPlayingTrack = @"language-cold-view";
    SGHarnessStartClock(0, 0, -1, 0);
    NSArray *lines = @[sungLine(0, @"I remember walking through the garden with you on a beautiful summer evening.")];
    SGKaraokeKeepLines(SGHarnessPlayingTrack, lines);
    atomic_store(&languageHoldNext, true); atomic_store(&languageHeld, false);
    SGRKaraokeView *view = [[SGRKaraokeView alloc] initWithFrame:CGRectMake(0, 0, 520, 300)];
    [root.view addSubview:view]; autoTick(view);
    check(extrasWait(^BOOL { return atomic_load(&languageHeld); }) && ![[view valueForKey:@"shown"] count],
          @"cold first presentation does not draw a provisional lyric style");
    SGKaraokeKeepLines(SGHarnessPlayingTrack,
        @[sungLine(0, @"I remember walking through the garden with you on a beautiful summer evening.")]);
    autoTick(view);
    dispatch_semaphore_signal(languageRelease);
    check(extrasWait(^BOOL { return [[view valueForKey:@"shown"] count] != 0; }),
          @"equivalent replacement during pending language analysis still presents lyrics");
    UIScrollView *scroll = [view valueForKey:@"scroll"];
    NSDictionary *shownLines = [[view valueForKey:@"shown"] copy];
    NSArray *tops = [view valueForKey:@"tops"];
    CGPoint offset = scroll.contentOffset;
    __block BOOL warm = NO;
    SGRAnalyzeLyricsLanguage(lines, @"en", ^(BOOL other, NSString *tag) { warm = !other && [tag isEqual:@"en"]; });
    autoTick(view);
    check(warm && [tops isEqual:[view valueForKey:@"tops"]] && [shownLines isEqual:[view valueForKey:@"shown"]] &&
          CGPointEqualToPoint(offset, scroll.contentOffset) && ![scroll.layer animationForKey:@"restyle"],
          @"common-case language publication keeps the first rendered rows, geometry and scroll position without a fade");
    SGRKaraokeView *cachedView = [[SGRKaraokeView alloc] initWithFrame:view.frame];
    [root.view addSubview:cachedView]; autoTick(cachedView);
    BOOL rendered = extrasWait(^BOOL { return [[cachedView valueForKey:@"shown"] count] != 0; });
    autoTick(cachedView); // Both rows must have consumed the same paused clock, not just finished layout.
    NSData *(^pixels)(UIView *) = ^NSData *(UIView *content) {
        UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:content.bounds.size];
        return UIImagePNGRepresentation([renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
            [content.layer renderInContext:context.CGContext];
        }]);
    };
    UIView *coldRow = shownLines[@0], *warmRow = [cachedView valueForKey:@"shown"][@0];
    check(rendered && coldRow && warmRow && CGRectEqualToRect(coldRow.frame, warmRow.frame) &&
          [pixels(coldRow) isEqual:pixels(warmRow)],
          @"common-case cold first row is pixel-identical to the immediately available cached-language presentation");
    [cachedView removeFromSuperview];

    // Hold old inference while a new song and target become current.
    SGHarnessPlayingTrack = @"language-stale-view";
    SGKaraokeKeepLines(SGHarnessPlayingTrack, @[sungLine(0, @"This is another English sentence about the distant mountains beyond the river.")]);
    atomic_store(&languageHoldNext, true); atomic_store(&languageHeld, false);
    autoTick(view);
    check(extrasWait(^BOOL { return atomic_load(&languageHeld); }), @"old view analysis is held before switching songs");
    SGHarnessPlayingTrack = @"language-current-view";
    SGKaraokeKeepLines(SGHarnessPlayingTrack, @[sungLine(0, @"こんにちは 世界の歌")]);
    [defaults setObject:@"ko" forKey:@"translateTo"];
    autoTick(view);
    dispatch_semaphore_signal(languageRelease);
    check(extrasWait(^BOOL { return [[view valueForKey:@"languageReady"] boolValue] &&
        [[view valueForKey:@"detectedLanguage"] isEqual:@"ja"]; }) &&
        [[view valueForKey:@"track"] isEqual:@"language-current-view"],
        @"late old-song/target inference cannot replace the current song's language");
    check(!atomic_load(&languageOnMain) && atomic_load(&languageCalls) > 0 && !atomic_load(&languageHoldTimeout),
          @"view load and styling never run language recognition on main, with extras disabled");
    method_setImplementation(process, originalProcessString);
    [view removeFromSuperview];
    [defaults removeObjectForKey:@"translateTo"];
}

static void finalLineChecks(UIWindow *window) {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    [defaults setBool:YES forKey:SGKeyLyricsCredit];
    [defaults setBool:YES forKey:SGKeyLyricsCulturalNotes];
    [defaults setBool:YES forKey:SGRKeyLyricsTranslation];
    [defaults setBool:YES forKey:SGRKeyLyricsPronunciation];
    SGHarnessPlayingTrack = @"tall-final-line";
    SGHarnessStartClock(0, 0, -1, 0);
    SGKaraokeLine *last = sungLine(30000, @"This final line is long enough to wrap across several rows in the landscape lyric viewport.");
    last.translation = @"A long saved translation that also wraps below the final line, with all of its words still reachable.";
    last.pronunciation = sungLine(30000, @"A pronunciation guide that occupies several rows below the original lyrics.");
    last.note = @"A cultural note follows the translation and must remain reachable along with the provider credit.";
    SGKaraokeKeepLines(SGHarnessPlayingTrack, @[sungLine(0, @"First line"), last]);
    UIViewController *root = [UIViewController new]; window.rootViewController = root; [window makeKeyAndVisible];
    SGRKaraokeView *view = [[SGRKaraokeView alloc] initWithFrame:CGRectMake(0, 0, 480, 200)];
    [root.view addSubview:view]; autoTick(view);
    check(extrasWait(^BOOL { return [[view valueForKey:@"tops"] count] == 2; }), @"tall final line is measured in a short landscape viewport");
    autoTick(view);
    UIScrollView *scroll = [view valueForKey:@"scroll"];
    UILabel *credit = [view valueForKey:@"credit"];
    CAGradientLayer *fade = [view valueForKey:@"fade"];
    CGFloat maximumOffset = scroll.contentSize.height - scroll.bounds.size.height + scroll.contentInset.bottom;
    CGFloat clearBottom = view.bounds.size.height * [fade.locations[2] doubleValue];
    check(credit.text.length && CGRectGetMaxY(credit.frame) - maximumOffset <= clearBottom + 0.01,
          @"the entire final line and credit can scroll above the bottom fade and controls");
    [view removeFromSuperview];
}

static void providerRevisionChecks(UIWindow *window) {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    [defaults setBool:NO forKey:SGRKeyLyricsAutoTranslation];
    [defaults setBool:NO forKey:SGRKeyLyricsPronunciation];
    [defaults setBool:NO forKey:SGKeyLyricsRomanised];
    [defaults setBool:NO forKey:SGKeyLyricsCulturalNotes];
    [defaults setBool:YES forKey:SGRKeyLyricsTranslation];
    [defaults setObject:@"en" forKey:@"translateTo"];
    [defaults removeObjectForKey:SGKeyLyricsLanguageRules];
    SGHarnessPlayingTrack = @"provider-translation-revisions";
    SGHarnessStartClock(500, 0, -1, 0);
    NSMutableArray<SGKaraokeLine *> *english = [NSMutableArray array];
    for (NSUInteger i = 0; i < 12; i++) {
        SGKaraokeLine *line = sungLine(i * 3000, i ? @"Encore une chanson" : @"Bonjour le monde");
        line.timing = SGKaraokeTimingWords;
        [english addObject:line];
    }
    english.firstObject.translation = @"English provider text";
    english.firstObject.translationLanguage = @"en";
    SGKaraokeKeepLines(SGHarnessPlayingTrack, english);
    UIViewController *root = [UIViewController new]; window.rootViewController = root; [window makeKeyAndVisible];
    SGRKaraokeView *view = [[SGRKaraokeView alloc] initWithFrame:CGRectMake(0, 0, 520, 300)];
    [root.view addSubview:view]; autoTick(view);
    UIView *(^firstRow)(void) = ^UIView * { return [view valueForKey:@"shown"][@0]; };
    check(extrasWait(^BOOL { return [firstRow().accessibilityValue isEqual:@"English provider text"]; }),
          @"loaded timed karaoke renders the English provider translation");
    autoTick(view);
    UIScrollView *scroll = [view valueForKey:@"scroll"];
    [scroll.delegate scrollViewWillBeginDragging:scroll];
    scroll.contentOffset = CGPointMake(0, 24);
    // A browsed page keeps its first wholly visible verse where it is drawn (showStyle:tops:), so a row
    // above it changing height moves the offset, not the verse.
    CGFloat (^anchorY)(void) = ^CGFloat {
        CGFloat best = CGFLOAT_MAX;
        for (UIView *row in [[view valueForKey:@"shown"] allValues]) {
            CGFloat y = CGRectGetMinY(row.frame) - CGRectGetMinY(scroll.bounds);
            if (y >= 0 && y < best && CGRectGetMaxY(row.frame) <= CGRectGetMaxY(scroll.bounds)) best = y;
        }
        return best;
    };
    CGFloat anchor = anchorY();
    BOOL (^anchored)(void) = ^BOOL { return anchor < CGFLOAT_MAX && fabs(anchorY() - anchor) < 1; };
    [defaults setObject:@"ko" forKey:@"translateTo"];

    NSMutableArray<SGKaraokeLine *> *cleared = [NSMutableArray array];
    for (SGKaraokeLine *line in english) {
        SGKaraokeLine *copy = [line copy]; copy.translation = nil; copy.translationLanguage = nil;
        [cleared addObject:copy];
    }
    SGKaraokeKeepLines(SGHarnessPlayingTrack, cleared);
    UIView *oldRow = firstRow();
    autoTick(view);
    check(firstRow() == oldRow && anchored(),
          @"provider removal keeps rendered rows and scroll while replacement layout runs");
    check(extrasWait(^BOOL { return firstRow() && !firstRow().accessibilityValue.length; }) &&
          anchored(),
          @"provider removal clears English from loaded timed karaoke without moving scroll");

    NSMutableArray<SGKaraokeLine *> *korean = [NSMutableArray array];
    for (SGKaraokeLine *line in cleared) [korean addObject:[line copy]];
    korean.firstObject.translation = @"안녕하세요";
    korean.firstObject.translationLanguage = @"ko";
    SGKaraokeKeepLines(SGHarnessPlayingTrack, korean);
    oldRow = firstRow();
    autoTick(view);
    check(firstRow() == oldRow && anchored(),
          @"Korean arrival keeps rendered rows and scroll while replacement layout runs");
    check(extrasWait(^BOOL { return [firstRow().accessibilityValue isEqual:@"안녕하세요"]; }) &&
          anchored(),
          @"Korean provider revision appears in loaded timed karaoke without moving scroll");

    // A replacement must also be adopted when the current snapshot already has a translation.
    NSMutableArray<SGKaraokeLine *> *replacement = [NSMutableArray array];
    for (SGKaraokeLine *line in korean) [replacement addObject:[line copy]];
    replacement.firstObject.translation = @"다른 번역";
    SGKaraokeKeepLines(SGHarnessPlayingTrack, replacement);
    autoTick(view);
    check(extrasWait(^BOOL { return [firstRow().accessibilityValue isEqual:@"다른 번역"]; }) &&
          anchored(),
          @"provider replacement updates existing translated karaoke without moving scroll");

    NSMutableArray<SGKaraokeLine *> *unchanged = [NSMutableArray array];
    for (SGKaraokeLine *line in replacement) [unchanged addObject:[line copy]];
    // Offscreen rows fill in over several frames. The already-visible first row must survive;
    // comparing the entire virtualized dictionary would mistake normal additions for a restyle.
    UIView *unchangedRow = firstRow();
    SGKaraokeKeepLines(SGHarnessPlayingTrack, unchanged);
    autoTick(view);
    pump(); // Let any incorrectly scheduled replacement layout reach the presented rows.
    check(firstRow() == unchangedRow && anchored(),
          @"unchanged provider translations preserve presented rows without another restyle");
    check([unchangedRow accessibilityActivate] && SGKaraokePositionMs() == SGKaraokeDelayMs(),
          @"preserved lyric row VoiceOver activation seeks after an equivalent replacement");
    __block BOOL cardPresented = NO;
    __block NSUInteger selectedCard = NSNotFound;
    __block NSString *selectedText = nil;
    SGHarnessLyricCardPresented = ^(NSArray<SGRLyricCardLine *> *cards, NSUInteger picked) {
        cardPresented = YES;
        selectedCard = picked;
        selectedText = picked < cards.count ? cards[picked].text : nil;
    };
    BOOL shared = NO;
    for (UIAccessibilityCustomAction *action in unchangedRow.accessibilityCustomActions) {
        if ([action.name isEqual:@"Share as card"]) shared = action.actionHandler(action);
    }
    check(shared && extrasWait(^BOOL { return cardPresented; }) && selectedCard == 0 &&
          [selectedText isEqual:@"Bonjour le monde"],
          @"preserved lyric row card action keeps the selected line after an equivalent replacement");
    SGHarnessLyricCardPresented = nil;
    NSMutableArray *renamedVoices = [NSMutableArray array];
    for (SGKaraokeLine *line in unchanged) {
        SGKaraokeLine *copy = [line copy];
        copy.voice = @"another provider's vocalist";
        [renamedVoices addObject:copy];
    }
    SGKaraokeKeepLines(SGHarnessPlayingTrack, renamedVoices);
    autoTick(view);
    pump();
    check(firstRow() == unchangedRow,
          @"different provider voice names with equal alignment preserve presented rows");
    Method creditMethod = class_getInstanceMethod(SGRKaraokeView.class, NSSelectorFromString(@"creditTo:"));
    IMP originalCredit = method_getImplementation(creditMethod);
    __block BOOL refreshedReconciledCredit = NO;
    IMP observedCredit = imp_implementationWithBlock(^(SGRKaraokeView *receiver, NSString *source) {
        if (receiver == view) refreshedReconciledCredit = YES;
        ((void (*)(id, SEL, id))originalCredit)(receiver, NSSelectorFromString(@"creditTo:"), source);
    });
    method_setImplementation(creditMethod, observedCredit);
    for (NSUInteger frame = 0; frame < 3; frame++) autoTick(view);
    method_setImplementation(creditMethod, originalCredit);
    imp_removeBlock(observedCredit);
    NSMutableArray<SGKaraokeLine *> *authoritative = [unchanged mutableCopy];
    SGKaraokeLine *different = [unchanged.firstObject copy];
    different.words = sungLine(different.start, @"Nouvelle source prioritaire").words;
    authoritative[0] = different;
    SGKaraokeKeepLines(SGHarnessPlayingTrack, authoritative);
    autoTick(view);
    check(extrasWait(^BOOL { return [firstRow().accessibilityLabel isEqual:@"Nouvelle source prioritaire"]; }),
          @"different authoritative words replace same-timing rows even with unchanged translations");
    check(!refreshedReconciledCredit && [firstRow().accessibilityLabel isEqual:@"Nouvelle source prioritaire"],
          @"settled equivalent snapshots do no repeated credit work while a later different snapshot is adopted");
    [view removeFromSuperview];
    [defaults removeObjectForKey:@"translateTo"];
}

static void roundOneChecks(UIWindow *window) {
    unresolvedChecks();
    languageSnapshotChecks(window);
    finalLineChecks(window);
    providerRevisionChecks(window);
}
