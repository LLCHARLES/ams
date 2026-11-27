// Included by translation-check.m. Mutable models belong to main; menu actions belong to the song
// and language they were offered for. No provider or network is used.
#import <stdatomic.h>

extern NSString *SGHarnessPlayingTrack;
extern void (^SGHarnessAIRequested)(NSString *kind, NSString *track);
static atomic_bool reviewReadOffMain;

@interface SGRKaraokeView (PublicationHarness)
- (void)placeLinesAnimated:(BOOL)animated;
@end

@interface SGPublicationView : SGRKaraokeView
@property (nonatomic) BOOL published;
@property (nonatomic) BOOL firstFrameCorrect;
@end
@implementation SGPublicationView
- (NSInteger)positionMs { return 1500; }
- (void)startLink {}
- (void)placeLinesAnimated:(BOOL)animated {
    [super placeLinesAnimated:animated];
    if (self.published || ![[self valueForKey:@"tops"] count]) return;
    self.published = YES;
    NSDictionary *shown = [self valueForKey:@"shown"];
    UIView *current = shown[@1], *previous = shown[@0];
    self.firstFrameCorrect = (current.accessibilityTraits & UIAccessibilityTraitSelected) &&
                             !(previous.accessibilityTraits & UIAccessibilityTraitSelected);
}
@end

static void publicationCheck(void) {
    SGHarnessPlayingTrack = @"publication";
    SGKaraokeKeepLines(@"publication", @[sungLine(0, @"before"), sungLine(1000, @"current")]);
    SGPublicationView *view = [[SGPublicationView alloc] initWithFrame:CGRectMake(0, 0, 360, 600)];
    ((void (*)(id, SEL))objc_msgSend)(view, NSSelectorFromString(@"tick"));
    [view layoutSubviews];
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:60];
    while (!view.published && deadline.timeIntervalSinceNow > 0)
        [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    check(view.published && view.firstFrameCorrect, @"first published frame selects the current sung line without a display tick");
}

@interface SGReviewMutableLine : SGKaraokeLine
@end
@implementation SGReviewMutableLine
- (NSString *)translation {
    if (!NSThread.isMainThread) atomic_store(&reviewReadOffMain, true);
    return [super translation];
}
@end

static BOOL reviewShowsText(UIView *view, NSString *text) {
    if ([view isKindOfClass:UILabel.class] && [((UILabel *)view).text isEqualToString:text]) return YES;
    for (UIView *child in view.subviews) if (reviewShowsText(child, text)) return YES;
    return NO;
}

#include "round-two-check.inc"
#include "song-language-check.inc"
#include "extras-check.inc"

static void reviewChecks(UIWindow *window) {
    publicationCheck();
    NSUserDefaults *args = NSUserDefaults.standardUserDefaults;
    [args setBool:NO forKey:SGRKeyLyricsAutoTranslation];
    [args setBool:YES forKey:@"ai"];
    [args setBool:YES forKey:@"aiCheck"];
    [args setBool:YES forKey:SGKeyLyricsCulturalNotes];
    [args removeObjectForKey:@"translateTo"];
    SGRSetLyricsTextShown(SGRLyricsTextTranslation, NO);
    SGHarnessPlayingTrack = @"review-first";
    SGReviewMutableLine *line = [SGReviewMutableLine new];
    SGKaraokeLine *words = sungLine(0, @"primera linea");
    line.words = words.words;
    line.start = words.start;
    line.end = words.end;
    line.translation = @"First translation";
    SGKaraokeKeepLines(@"review-first", @[line]);

    UIViewController *root = [UIViewController new];
    window.rootViewController = root;
    [window makeKeyAndVisible];
    SGRKaraokeView *view = [[SGRKaraokeView alloc] initWithFrame:CGRectMake(0, 0, 360, 600)];
    [root.view addSubview:view];
    ((void (*)(id, SEL))objc_msgSend)(view, NSSelectorFromString(@"tick"));
    atomic_store(&reviewReadOffMain, false);
    [view layoutSubviews];
    // The first measurement cannot publish until this main-thread turn returns. Change the style
    // now, not on a timer that might race the result.
    SGRSetLyricsTextShown(SGRLyricsTextTranslation, YES);
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:60];
    while (!reviewShowsText(view, @"First translation") && deadline.timeIntervalSinceNow > 0)
        [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    check(reviewShowsText(view, @"First translation"), @"a translation enabled during first measurement is displayed");
    check(!atomic_load(&reviewReadOffMain), @"background layout never reads the live model's mutable translation");

    UIAction *oldPronunciation = (UIAction *)itemIn((UIMenu *)item(view, @"Write Pronunciation"), @"Gemini");
    UIAction *oldNotes = (UIAction *)itemIn((UIMenu *)item(view, @"Explain References"), @"Gemini");
    NSMutableArray<NSString *> *requests = [NSMutableArray array];
    SGHarnessAIRequested = ^(NSString *kind, NSString *track) {
        [requests addObject:[NSString stringWithFormat:@"%@|%@", kind, track]];
    };
    SGHarnessPlayingTrack = @"review-next";
    SGKaraokeKeepLines(@"review-next", @[sungLine(0, @"segunda linea")]);
    ((void (*)(id, SEL))objc_msgSend)(view, NSSelectorFromString(@"tick"));
    BOOL tappedBoth = tap(oldPronunciation) && tap(oldNotes);
    check(tappedBoth && requests.count == 0, @"old AI actions send no lyrics after a track change");

    [requests removeAllObjects];
    oldPronunciation = (UIAction *)itemIn((UIMenu *)item(view, @"Write Pronunciation"), @"Gemini");
    oldNotes = (UIAction *)itemIn((UIMenu *)item(view, @"Explain References"), @"Gemini");
    [args setObject:@"fr" forKey:@"translateTo"];
    tappedBoth = tap(oldPronunciation) && tap(oldNotes);
    check(tappedBoth && requests.count == 0, @"old AI actions send no lyrics after a target-language change");

    [requests removeAllObjects];
    ((void (*)(id, SEL))objc_msgSend)(view, NSSelectorFromString(@"offerExtras"));
    tap(itemIn((UIMenu *)item(view, @"Write Pronunciation"), @"Gemini"));
    tap(itemIn((UIMenu *)item(view, @"Explain References"), @"Gemini"));
    check([requests isEqualToArray:@[@"pronunciation|review-next", @"notes|review-next"]],
          @"current AI actions still send the selected song to both services");
    SGHarnessAIRequested = nil;
    [view removeFromSuperview];
    [args setBool:NO forKey:@"ai"];
    [args removeObjectForKey:@"translateTo"];
    roundTwoChecks(window);
    songLanguageChecks();
    extrasChecks(window);
}
