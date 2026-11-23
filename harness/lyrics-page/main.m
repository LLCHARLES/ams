// The lyrics page harness: the redesign's Lyrics page as App/Pages.m opens it, its preview playing the sample
// song in the real lyrics view, the presets under it and the sliders' sheet, with one stand-in section under them.
//
// Launch arguments (NSUserDefaults' argument domain):
//   -preset N   stores preset N before the page opens (0 Apple Music, 1 Large, 2 Compact, 3 Calm, 4 Vivid)
//   -sheet S    opens the sliders' sheet S seconds in, as a tap on its button would
//   -check 1    asserts the page's behavior (see runChecks), prints PASS and FAIL lines and quits with the
//               number of failures
//   -pushCheck 1 pushes the page as Mod Settings does, for Apple Music, Vivid and a look of the sliders', and checks
//               the presets arrive where they rest (see runPushCase), the same way
//   -textCheck 1 asserts the Text sizes page and each text's look (see runTextChecks) the same way
//   -textPage N opens the Text sizes page, then text N's own page (0 lyrics, 1 pronunciation, 2 translation),
//               for a screenshot; -textLook 1 stores 130%, regular and 140% for it first
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import "Settings/SGModPage.h"
#import "Settings/SGPage.h"
#import "Redesigned/Lyrics/LyricsLook.h"
#import "Redesigned/Lyrics/LyricsText.h"
#import "Redesigned/Lyrics/SGRKaraokeView.h"

static int sg_failures;

static void expect(BOOL ok, NSString *what) {
    printf("%s %s\n", ok ? "PASS" : "FAIL", what.UTF8String);
    fflush(stdout);
    if (!ok) sg_failures++;
}

static void after(double seconds, dispatch_block_t block) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(seconds * NSEC_PER_SEC)), dispatch_get_main_queue(), block);
}

static void collect(UIView *root, Class cls, NSMutableArray *into) {
    if ([root isKindOfClass:cls]) [into addObject:root];
    for (UIView *view in root.subviews) collect(view, cls, into);
}

static NSArray *find(UIView *root, Class cls) {
    NSMutableArray *found = [NSMutableArray array];
    collect(root, cls, found);
    return found;
}

// The preset buttons, in order.
static NSArray<UIButton *> *chipsOf(UIViewController *page) {
    return [page valueForKey:@"chips"];
}

static BOOL lit(UIButton *chip) {
    return (chip.accessibilityTraits & UIAccessibilityTraitSelected) != 0;
}

static void runChecks(UIViewController *page) {
    SGRKaraokeView *preview = [page valueForKey:@"preview"];
    NSArray<UIButton *> *chips = chipsOf(page);
    expect(chips.count == SGRLyricsLookPresetNames().count && lit(chips[0]), @"with nothing stored Apple Music is lit");
    expect([[preview valueForKey:@"fontSize"] doubleValue] == 34 && [[preview valueForKey:@"margin"] doubleValue] == 32,
           [NSString stringWithFormat:@"with nothing stored the lines are the Music app's 34 pt, 32 pt in from the sides (%@ pt, %@ pt)",
            [preview valueForKey:@"fontSize"], [preview valueForKey:@"margin"]]);
    expect([preview valueForKey:@"tops"] != nil && !preview.hidden, @"the preview plays its lines");
    UIView *header = ((UITableViewController *)page).tableView.tableHeaderView;
    expect(CGRectGetMaxY([chips[0] convertRect:chips[0].bounds toView:header]) < header.bounds.size.height,
           [NSString stringWithFormat:@"the header holds the preview and the presets (%.0f pt tall)", header.bounds.size.height]);

    [chips[1] sendActionsForControlEvents:UIControlEventPrimaryActionTriggered];
    expect(lit(chips[1]) && !lit(chips[0]) && [[preview valueForKey:@"fontSize"] doubleValue] == 36,
           @"a tap on Large lights it and sets the preview's lines at 36 pt");

    UIButton *adjust = [page valueForKey:@"adjust"];
    // The fifth preset, past the edge of the strip on a phone, is scrolled into sight when it is picked.
    [chips.lastObject sendActionsForControlEvents:UIControlEventPrimaryActionTriggered];
    [page.view layoutIfNeeded];
    UIScrollView *strip = [page valueForKey:@"strip"];
    after(0.6, ^{
        CGRect shown = [strip convertRect:chips.lastObject.bounds fromView:chips.lastObject];
        expect(CGRectContainsRect(strip.bounds, shown), @"a preset picked past the edge of the strip is scrolled into sight");
    });
    [adjust sendActionsForControlEvents:UIControlEventPrimaryActionTriggered];
    after(1.2, ^{
        UINavigationController *nav = (UINavigationController *)page.presentedViewController;
        UITableViewController *sheet = (UITableViewController *)nav.topViewController;
        expect([nav isKindOfClass:UINavigationController.class] && [NSStringFromClass(sheet.class) isEqualToString:@"SGRLyricsStyleSheet"],
               @"the sliders' button opens the sheet");
        NSArray<UISlider *> *sliders = find(sheet.tableView, UISlider.class);
        expect([sheet.tableView numberOfRowsInSection:1] == 2,
               @"only player and landscape/full-screen lyrics have a percentage size");
        expect(sliders.count == 5, [NSString stringWithFormat:@"the sheet has five sliders (%lu)", (unsigned long)sliders.count]);
        UISlider *spacing = nil;
        for (UISlider *slider in sliders) {
            if (slider.maximumValue == 40 && slider.minimumValue == 12) spacing = slider;
        }
        spacing.value = 34;
        [spacing sendActionsForControlEvents:UIControlEventValueChanged];
        expect([[preview valueForKey:@"lineGap"] doubleValue] == 34 && lit(adjust) && [adjust.accessibilityValue isEqualToString:@"Custom"],
               [NSString stringWithFormat:@"a slider moves the preview's lines apart (%@ pt) and the look reads Custom",
                [preview valueForKey:@"lineGap"]]);
        // A preset picked over the sheet is read back into its sliders.
        [chips[0] sendActionsForControlEvents:UIControlEventPrimaryActionTriggered];
        [sheet.tableView layoutIfNeeded];
        UISlider *again = nil;
        for (UISlider *slider in find(sheet.tableView, UISlider.class)) {
            if (slider.maximumValue == 40 && slider.minimumValue == 12) again = slider;
        }
        expect(again.value == 24 && lit(chips[0]), [NSString stringWithFormat:@"Apple Music picked over the sheet puts its slider back to 24 (%.0f)", again.value]);
        after(0.8, ^{
            printf("%d failed\n", sg_failures);
            fflush(stdout);
            exit(sg_failures);
        });
    });
}

#pragma mark - the page pushed

// Where the strip is drawn each frame: its presentation while UIKit animates it, else the model.
@interface SGStripSampler : NSObject
@property (nonatomic, weak) UIViewController *page;
@property (nonatomic, strong) NSMutableArray<NSNumber *> *offsets;
@end

@implementation SGStripSampler
- (void)tick:(CADisplayLink *)link {
    UIViewController *page = self.page;
    if (!page.isViewLoaded || !page.view.window) return;
    UIScrollView *strip = [page valueForKey:@"strip"];
    CALayer *shown = strip.layer.presentationLayer ?: strip.layer;
    [self.offsets addObject:@(shown.bounds.origin.x)];}
@end

static SGStripSampler *sampling(UIViewController *page, CADisplayLink **link) {
    SGStripSampler *sampler = [SGStripSampler new];
    sampler.page = page;
    sampler.offsets = [NSMutableArray array];
    *link = [CADisplayLink displayLinkWithTarget:sampler selector:@selector(tick:)];
    [*link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    return sampler;
}

static NSString *offsetsText(NSArray<NSNumber *> *offsets) {
    NSMutableArray *seen = [NSMutableArray array];
    for (NSNumber *x in offsets) if (![seen.lastObject isEqual:x]) [seen addObject:x];
    return [seen componentsJoinedByString:@" "];
}

// Mod Settings pushes the page: the presets come in already where they rest -- the chosen one in sight, or the first at
// the card's inset for a look of the sliders' -- and do not move once it is on screen (issue #41). A preset picked after
// that still scrolls to it.
static void runPushCase(UINavigationController *nav, NSArray *cases, NSUInteger index) {
    if (index == cases.count) {
        [NSUserDefaults.standardUserDefaults removeObjectForKey:SGRKeyLyricsLook];
        printf("%d failed\n", sg_failures);
        fflush(stdout);
        exit(sg_failures);
    }
    NSInteger preset = [cases[index] integerValue];
    SGRLyricsLook look = SGRLyricsLookPreset(preset < 0 ? 0 : (NSUInteger)preset);
    if (preset < 0) look.size += 1;
    SGRSetLyricsLook(look, nil);
    NSString *name = preset < 0 ? @"the sliders' own look" : SGRLyricsLookPresetNames()[(NSUInteger)preset];
    if (preset < 0) expect(SGRLyricsLookPresetIndex(SGRLyricsLookNow()) < 0, @"the sliders' own look is no preset");
    UIViewController *page = SGRLyricsSettingsPage(@"Lyrics", SGRestartNote, @[]);
    CADisplayLink *link;
    SGStripSampler *sampler = sampling(page, &link);
    [nav pushViewController:page animated:YES];
    after(1.5, ^{
        [link invalidate];
        UIScrollView *strip = [page valueForKey:@"strip"];
        UIView *card = [page valueForKey:@"card"];
        NSArray<UIButton *> *chips = chipsOf(page);
        NSArray<NSNumber *> *offsets = sampler.offsets;
        CGFloat rest = strip.contentOffset.x;
        BOOL still = offsets.count > 0;
        for (NSNumber *x in offsets) still &= fabs(x.doubleValue - rest) < 0.5;
        expect(still, [NSString stringWithFormat:@"%@: the presets are where they rest from the first frame on screen (%@ over %lu frames)",
                       name, offsetsText(offsets), (unsigned long)offsets.count]);
        if (preset < 0) {
            expect(fabs(rest + CGRectGetMinX(card.frame)) < 0.5,
                   [NSString stringWithFormat:@"%@: the first preset starts at the card's inset (offset %.1f, card %.1f)", name, rest, CGRectGetMinX(card.frame)]);
        } else {
            UIButton *chosen = chips[(NSUInteger)preset];
            CGRect shown = [strip convertRect:chosen.bounds fromView:chosen];
            expect(CGRectContainsRect(strip.bounds, shown), [NSString stringWithFormat:@"%@: the chosen preset is in sight", name]);
        }
        // Picked from the other end, the strip scrolls there over several frames.
        UIButton *other = preset == (NSInteger)chips.count - 1 ? chips.firstObject : chips.lastObject;
        CADisplayLink *pickLink;
        SGStripSampler *picked = sampling(page, &pickLink);
        [other sendActionsForControlEvents:UIControlEventPrimaryActionTriggered];
        after(1.0, ^{
            [pickLink invalidate];
            NSMutableSet *distinct = [NSMutableSet setWithArray:picked.offsets];
            CGRect shown = [strip convertRect:other.bounds fromView:other];
            BOOL moves = fabs(strip.contentOffset.x - rest) >= 0.5;
            BOOL within = strip.contentOffset.x > -strip.adjustedContentInset.left - 0.5;
            expect(CGRectContainsRect(strip.bounds, shown) && within && (!moves || distinct.count > 2),
                   [NSString stringWithFormat:@"%@: a preset picked afterwards is scrolled into sight%@ (%@)", name,
                    moves ? @" smoothly" : @"", offsetsText(picked.offsets)]);
            [nav popToRootViewControllerAnimated:NO];
            after(0.3, ^{ runPushCase(nav, cases, index + 1); });
        });
    });
}

#pragma mark - the Text sizes page

// The view's private style, made as the view makes it: 30 pt and the stored order.
static id styleNow(BOOL pronunciation, BOOL romanised) {
    return ((id (*)(id, SEL, CGFloat, NSArray *, BOOL, BOOL, BOOL))objc_msgSend)([NSClassFromString(@"SGRKaraokeStyle") alloc],
        NSSelectorFromString(@"initWithSize:order:pronunciation:translation:romanised:"), 30, SGRLyricsTextOrder(), pronunciation, YES, romanised);
}

static UIFontWeight weightOf(UIFont *font) {
    return [[font.fontDescriptor objectForKey:UIFontDescriptorTraitsAttribute][UIFontWeightTrait] doubleValue];
}

static BOOL near(CGFloat a, CGFloat b) {
    return fabs(a - b) < 0.001;
}

// The view's _style ivar: "style" by key value coding answers a number of UIView's own instead.
static id styleOf(SGRKaraokeView *view) {
    return object_getIvar(view, class_getInstanceVariable(SGRKaraokeView.class, "_style"));
}

static void clearTextLooks(void) {
    NSUserDefaults *store = NSUserDefaults.standardUserDefaults;
    for (NSString *key in store.dictionaryRepresentation.allKeys)
        if ([key hasPrefix:SGRKeyLyricsTextLook]) [store removeObjectForKey:key];
    [store removeObjectForKey:SGRKeyLyricsTextOrder];
}

static NSString *fontText(UIFont *font) {
    return [NSString stringWithFormat:@"%.0f pt %.2f", font.pointSize, weightOf(font)];
}

static void runTextChecks(UINavigationController *nav) {
    clearTextLooks();
    // Nothing stored is the look there always was: 30, 20 and 16 pt, bold, bold and semibold, the usual brightness.
    id style = styleNow(YES, NO);
    UIFont *lyrics = [style valueForKey:@"lyrics"], *spoken = [style valueForKey:@"pronunciation"], *translation = [style valueForKey:@"translation"];
    // Generated readings now occupy Pronunciation, including when source pronunciation is switched off.
    UIFont *generated = [styleNow(NO, YES) valueForKey:@"pronunciation"];
    expect(lyrics.pointSize == 30 && spoken.pointSize == 20 && translation.pointSize == 16 && generated.pointSize == 20,
           [NSString stringWithFormat:@"unset sizes stay 30, 20, 16 and the generated pronunciation 20 (%@, %@, %@, %@)", fontText(lyrics), fontText(spoken), fontText(translation), fontText(generated)]);
    expect(near(weightOf(lyrics), weightOf([UIFont systemFontOfSize:30 weight:UIFontWeightBold]))
           && near(weightOf(spoken), weightOf([UIFont systemFontOfSize:20 weight:UIFontWeightBold]))
           && near(weightOf(translation), weightOf([UIFont systemFontOfSize:16 weight:UIFontWeightSemibold]))
           && near(weightOf(generated), weightOf([UIFont systemFontOfSize:20 weight:UIFontWeightBold])),
           @"unset weights stay bold, bold, semibold and the generated pronunciation bold");
    expect(near([[style valueForKey:@"translationDim"] doubleValue], 0.3) && near([[style valueForKey:@"translationLit"] doubleValue], 0.6)
           && near([[style valueForKey:@"spokenDim"] doubleValue], 0.3) && near([[style valueForKey:@"spokenLit"] doubleValue], 0.6)
           && near([[style valueForKey:@"spokenSung"] doubleValue], 1) && near([[style valueForKey:@"noteDim"] doubleValue], 0.22)
           && near([[style valueForKey:@"noteLit"] doubleValue], 0.6), @"unset brightness stays 0.3 waiting, 0.6 sung, the note 0.22");
    UIFont *note = ((id (*)(id, SEL, CGFloat))objc_msgSend)(style, NSSelectorFromString(@"noteAt:"), 14);
    UIFont *furigana = ((id (*)(id, SEL, CGFloat))objc_msgSend)(style, NSSelectorFromString(@"furiganaAt:"), 11);
    expect(note.pointSize == 14 && near(weightOf(note), weightOf([UIFont systemFontOfSize:14 weight:UIFontWeightMedium]))
           && furigana.pointSize == 11 && near(weightOf(furigana), weightOf([UIFont systemFontOfSize:11 weight:UIFontWeightSemibold])),
           [NSString stringWithFormat:@"unset note and furigana stay medium 14 and semibold 11 (%@, %@)", fontText(note), fontText(furigana)]);
    id backing = [style valueForKey:@"backing"];
    expect([[backing valueForKey:@"lyrics"] pointSize] == 19 && [[backing valueForKey:@"pronunciation"] pointSize] == 12,
           @"the backing row stays at 62% of its line");

    // The translation at 115%, regular and 140%; the lyrics' brightness is not one to store.
    __block NSUInteger posted = 0;
    id watcher = [NSNotificationCenter.defaultCenter addObserverForName:SGRLyricsTextDidChangeNotification object:nil queue:nil
                                                             usingBlock:^(NSNotification *n) { posted++; }];
    SGRSetLyricsTextLook(SGRLyricsTextTranslation, (SGRLyricsTextLook){115, 0, 140});
    SGRSetLyricsTextLook(SGRLyricsTextLyrics, (SGRLyricsTextLook){120, 1, 60});
    style = styleNow(YES, NO);
    translation = [style valueForKey:@"translation"];
    lyrics = [style valueForKey:@"lyrics"];
    expect(posted == 2, @"each change is posted, so every lyrics view sets its lines again");
    expect(translation.pointSize == 18 && near(weightOf(translation), weightOf([UIFont systemFontOfSize:18 weight:UIFontWeightRegular]))
           && near([[style valueForKey:@"translationDim"] doubleValue], 0.42) && near([[style valueForKey:@"translationLit"] doubleValue], 0.84)
           && near([[style valueForKey:@"noteDim"] doubleValue], 0.308),
           [NSString stringWithFormat:@"the translation at 115%%, regular, 140%% is 18 pt and 0.42 to 0.84, its note after it (%@)", fontText(translation)]);
    expect(lyrics.pointSize == 36 && near(weightOf(lyrics), weightOf([UIFont systemFontOfSize:36 weight:UIFontWeightSemibold]))
           && SGRLyricsTextLookOf(SGRLyricsTextLyrics).brightness == 100
           && ![NSUserDefaults.standardUserDefaults objectForKey:[SGRKeyLyricsTextLook stringByAppendingString:@".lyrics.brightness"]],
           [NSString stringWithFormat:@"the lyrics at 120%% semibold are 36 pt, their brightness kept at 100%% (%@)", fontText(lyrics)]);
    backing = [style valueForKey:@"backing"];
    expect([[backing valueForKey:@"lyrics"] pointSize] == 22 && near(weightOf([backing valueForKey:@"lyrics"]), weightOf([UIFont systemFontOfSize:22 weight:UIFontWeightSemibold])),
           @"the backing row follows the lyrics' size and weight");
    SGRSetLyricsTextLook(SGRLyricsTextPronunciation, (SGRLyricsTextLook){100, 2, 140});
    style = styleNow(YES, NO);
    expect(near([[style valueForKey:@"spokenSung"] doubleValue], 1) && near([[style valueForKey:@"spokenDim"] doubleValue], 0.42),
           @"a bright pronunciation never goes past white as it is sung");
    SGRSetLyricsTextLook(SGRLyricsTextPronunciation, (SGRLyricsTextLook){100, 2, 40});
    style = styleNow(YES, NO);
    expect(near([[style valueForKey:@"spokenSung"] doubleValue], 0.4) && near([[style valueForKey:@"spokenDim"] doubleValue], 0.12),
           @"a dim pronunciation is dimmer waiting and sung");
    // What a sung word shows is its lit copy over the waiting one still under it: composited, that is the brightness asked for.
    SGKaraokeWord *(^word)(NSString *, NSInteger, NSInteger) = ^SGKaraokeWord *(NSString *text, NSInteger start, NSInteger end) {
        SGKaraokeWord *made = [SGKaraokeWord new];
        made.text = text; made.start = start; made.end = end;
        return made;
    };
    SGKaraokeLine *line = [SGKaraokeLine new];
    line.words = @[word(@"별빛", 0, 400)];
    line.start = 0; line.end = 400; line.timing = SGKaraokeTimingWords;
    SGKaraokeLine *spokenLine = [SGKaraokeLine new];
    spokenLine.words = @[word(@"byeolbit", 0, 400)];
    spokenLine.start = 0; spokenLine.end = 400; spokenLine.timing = SGKaraokeTimingWords;
    line.pronunciation = spokenLine;
    for (NSNumber *bright in @[@40, @100, @140]) {
        SGRSetLyricsTextLook(SGRLyricsTextPronunciation, (SGRLyricsTextLook){100, 2, bright.integerValue});
        id lineStyle = styleNow(YES, NO);
        UIView *lineView = ((id (*)(id, SEL, id, CGFloat, id, id, BOOL, BOOL))objc_msgSend)([NSClassFromString(@"SGRKaraokeLineView") alloc],
            NSSelectorFromString(@"initWithLine:width:style:under:blurred:sweepsEstimates:"), line, 300, lineStyle, nil, NO, NO);
        NSArray<UIView *> *words = [lineView valueForKey:@"words"];
        CGFloat (^alphaOf)(UIView *) = ^CGFloat(UIView *view) {
            CGFloat white = 0, alpha = 0;
            [((UILabel *)view).textColor getWhite:&white alpha:&alpha];
            return alpha;
        };
        UIView *spokenWord = words.lastObject, *lyricWord = words.firstObject;
        CGFloat under = alphaOf(spokenWord.subviews.firstObject), over = alphaOf([spokenWord valueForKey:@"lit"]);
        CGFloat shown = over + under * (1 - over);
        CGFloat lyricShown = alphaOf([lyricWord valueForKey:@"lit"]) + alphaOf(lyricWord.subviews.firstObject) * (1 - alphaOf([lyricWord valueForKey:@"lit"]));
        CGFloat want = MIN(1, bright.doubleValue / 100);
        expect(near(shown, want) && near(under, MIN(1, 0.3 * bright.doubleValue / 100)) && near(lyricShown, 1),
               [NSString stringWithFormat:@"a sung pronunciation at %@%% shows %.3f over its waiting %.3f (wants %.3f), the lyrics 1 (%.3f)",
                bright, shown, under, want, lyricShown]);
    }

    // Stored values out of range, off their step or of the wrong kind are the usual ones; the usual ones are not stored.
    NSUserDefaults *store = NSUserDefaults.standardUserDefaults;
    [store setObject:@83 forKey:[SGRKeyLyricsTextLook stringByAppendingString:@".pronunciation.scale"]];
    [store setObject:@7 forKey:[SGRKeyLyricsTextLook stringByAppendingString:@".pronunciation.weight"]];
    [store setObject:@"bright" forKey:[SGRKeyLyricsTextLook stringByAppendingString:@".pronunciation.brightness"]];
    [store setObject:@150 forKey:[SGRKeyLyricsTextLook stringByAppendingString:@".translation.brightness"]];
    SGRLyricsTextLook bad = SGRLyricsTextLookOf(SGRLyricsTextPronunciation);
    expect(bad.scale == 100 && bad.weight == 2 && bad.brightness == 100 && SGRLyricsTextLookOf(SGRLyricsTextTranslation).brightness == 100,
           @"a stored value out of range, off its step or not a number reads as the usual one");
    SGRSetLyricsTextLook(SGRLyricsTextTranslation, SGRLyricsTextLookDefault(SGRLyricsTextTranslation));
    BOOL stored = NO;
    for (NSString *key in store.dictionaryRepresentation.allKeys) stored |= [key hasPrefix:[SGRKeyLyricsTextLook stringByAppendingString:@".translation"]];
    expect(!stored && SGRLyricsTextLookIsDefault(SGRLyricsTextTranslation), @"setting the usual look back stores nothing for it");
    [NSNotificationCenter.defaultCenter removeObserver:watcher];
    clearTextLooks();

    // The page: the order's rows open each text's own page under a preview showing the pronunciation and translation.
    UITableViewController *order = (UITableViewController *)SGRLyricsTextSizesRow().page();
    [nav pushViewController:order animated:NO];
    [order.view layoutIfNeeded];
    UITableView *table = order.tableView;
    UITableViewCell *first = [order tableView:table cellForRowAtIndexPath:[NSIndexPath indexPathForRow:2 inSection:0]];
    NSString *summary = ((UIListContentConfiguration *)first.contentConfiguration).secondaryText;
    expect([summary containsString:@"100%"] && [summary containsString:@"Semibold"] && [summary containsString:@"Brightness"],
           [NSString stringWithFormat:@"the translation's row reads its look (%@)", summary]);
    [order tableView:table didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:2 inSection:0]];
    after(1.0, ^{
        UITableViewController *page = (UITableViewController *)nav.topViewController;
        [page.view layoutIfNeeded];
        NSArray<UISlider *> *sliders = find(page.tableView, UISlider.class);
        BOOL opened = [NSStringFromClass(page.class) isEqualToString:@"SGRLyricsTextStylePage"];
        expect(opened && sliders.count == 2,
               [NSString stringWithFormat:@"a tap on Translation opens its page with Size and Brightness (%@, %lu sliders)",
                NSStringFromClass(page.class), (unsigned long)sliders.count]);
        if (!opened) {
            printf("%d failed\n", sg_failures);
            fflush(stdout);
            exit(sg_failures);
        }
        SGRKaraokeView *preview = [page valueForKey:@"preview"];
        id previewStyle = styleOf(preview);
        expect([previewStyle valueForKey:@"pronunciation"] && [previewStyle valueForKey:@"translation"],
               @"the preview shows the pronunciation and the translation whatever the menu has on");
        UISlider *size = nil, *brightness = nil;
        for (UISlider *slider in sliders) {
            if (slider.maximumValue == 130) size = slider;
            if (slider.maximumValue == 140) brightness = slider;
        }
        size.value = 120;
        [size sendActionsForControlEvents:UIControlEventValueChanged];
        brightness.value = 70;
        [brightness sendActionsForControlEvents:UIControlEventValueChanged];
        SGRLyricsTextLook look = SGRLyricsTextLookOf(SGRLyricsTextTranslation);
        expect(look.scale == 120 && look.brightness == 70, [NSString stringWithFormat:@"the sliders store 120%% and 70%% (%ld, %ld)", (long)look.scale, (long)look.brightness]);
        UIView *header = [page valueForKey:@"header"];
        // The page's view is the table, so the header's frame is in content coordinates: measured from what is visible.
        UITableView *pageTable = page.tableView;
        CGFloat onScreen = CGRectGetMinY(header.frame) - pageTable.contentOffset.y;
        expect(header.bounds.size.height > 0 && fabs(onScreen - pageTable.safeAreaInsets.top) < 0.5
               && pageTable.contentInset.top == header.bounds.size.height,
               [NSString stringWithFormat:@"the preview is pinned under the bar and the rows start below it (%.0f pt tall, top %.1f, safe %.1f, inset %.1f)",
                header.bounds.size.height, onScreen, pageTable.safeAreaInsets.top, pageTable.contentInset.top]);
        // Scrolled down, it stays where it was.
        [pageTable setContentOffset:CGPointMake(0, pageTable.contentOffset.y + 120) animated:NO];
        [pageTable layoutIfNeeded];
        CGFloat scrolled = CGRectGetMinY(header.frame) - pageTable.contentOffset.y;
        expect(fabs(scrolled - onScreen) < 0.5, [NSString stringWithFormat:@"scrolling leaves the preview where it was (%.1f)", scrolled]);
        after(1.0, ^{
            id restyled = styleOf([page valueForKey:@"preview"]);
            // The default Apple Music look is 34 pt: its third-place text is 18 pt, then 22 at 120%.
            expect([[restyled valueForKey:@"translation"] pointSize] == 22, @"the preview sets its translation at 120% once restyled");
            [nav popViewControllerAnimated:NO];
            [nav pushViewController:SGRLyricsTextLookPage(SGRLyricsTextLyrics) animated:NO];
            after(0.6, ^{
                UITableViewController *lyricsPage = (UITableViewController *)nav.topViewController;
                [lyricsPage.view layoutIfNeeded];
                expect(find(lyricsPage.tableView, UISlider.class).count == 1, @"the lyrics' page has a Size slider and no Brightness");
                clearTextLooks();
                printf("%d failed\n", sg_failures);
                fflush(stdout);
                exit(sg_failures);
            });
        });
    });
}

@interface SGHarnessDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation SGHarnessDelegate
- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)options {
    NSUserDefaults *args = NSUserDefaults.standardUserDefaults;
    [args removeObjectForKey:SGRKeyLyricsLook];   // each launch starts from its own arguments
    if ([args objectForKey:@"preset"]) SGRSetLyricsLook(SGRLyricsLookPreset((NSUInteger)[args integerForKey:@"preset"]), nil);
    SGModSection *stand = SGSection(@"Sources", @[SGSwitchRow(@"Lyrics for every track", @"Even where Spotify has none", @"harness.everyTrack")]);
    BOOL push = [args boolForKey:@"pushCheck"];
    UIViewController *page = push ? [[UITableViewController alloc] initWithStyle:UITableViewStyleInsetGrouped]
                                  : SGRLyricsSettingsPage(@"Lyrics", SGRestartNote, @[stand]);
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:page];
    nav.navigationBar.prefersLargeTitles = NO;
    nav.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController = nav;
    [self.window makeKeyAndVisible];
    if ([args objectForKey:@"sheet"]) {
        after([args doubleForKey:@"sheet"], ^{
            [(UIButton *)[page valueForKey:@"adjust"] sendActionsForControlEvents:UIControlEventPrimaryActionTriggered];
        });
    }
    if (push) after(1.0, ^{ runPushCase(nav, @[@0, @4, @-1], 0); });
    if ([args boolForKey:@"check"]) after(2.5, ^{ runChecks(page); });   // the preview measures its lines off the main thread
    if ([args boolForKey:@"textCheck"]) after(1.5, ^{ runTextChecks(nav); });
    if ([args objectForKey:@"textPage"]) {
        SGRLyricsText text = (SGRLyricsText)[args integerForKey:@"textPage"];
        clearTextLooks();
        if ([args boolForKey:@"textLook"]) SGRSetLyricsTextLook(text, (SGRLyricsTextLook){130, 0, text == SGRLyricsTextLyrics ? 100 : 140});
        after(1.0, ^{
            [nav pushViewController:SGRLyricsTextSizesRow().page() animated:NO];
            [nav pushViewController:SGRLyricsTextLookPage(text) animated:NO];
        });
        // -landscape 1: turned on its side, and the safe area logged so a screenshot can be trusted.
        if ([args boolForKey:@"landscape"]) after(1.5, ^{
            // A window made before the scene connected keeps the portrait safe area when turned; one made in the
            // scene follows it.
            UIWindowScene *scene = self.window.windowScene;
            UIWindow *window = [[UIWindow alloc] initWithWindowScene:scene];
            window.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
            UIViewController *root = self.window.rootViewController;
            self.window.rootViewController = nil;
            self.window.hidden = YES;
            window.rootViewController = root;
            self.window = window;
            [window makeKeyAndVisible];
            UIWindowSceneGeometryPreferencesIOS *prefs = [[UIWindowSceneGeometryPreferencesIOS alloc]
                initWithInterfaceOrientations:UIInterfaceOrientationMaskLandscapeRight];
            [self.window.windowScene requestGeometryUpdateWithPreferences:prefs errorHandler:^(NSError *error) { NSLog(@"[harness] rotate %@", error); }];
            [nav.topViewController setNeedsUpdateOfSupportedInterfaceOrientations];
            after(2.0, ^{
                UITableView *table = ((UITableViewController *)nav.topViewController).tableView;
                printf("orientation %ld window %s safe %s header %.0f\n", (long)self.window.windowScene.interfaceOrientation,
                       NSStringFromCGSize(self.window.bounds.size).UTF8String, NSStringFromUIEdgeInsets(self.window.safeAreaInsets).UTF8String,
                       table.contentInset.top);
                fflush(stdout);
            });
        });
    }
    return YES;
}
@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(SGHarnessDelegate.class));
    }
}
