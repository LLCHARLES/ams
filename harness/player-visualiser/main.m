// Asserts the Visualizer view offline (Redesigned/Player/PlayerVisualiser.m, PlayerLyricStages.m) under stubs for
// what it reads:
//   - the Lyrics style clears the words when its source changes to lyrics that are not synced (a kept-lines
//     notification for the playing track), instead of leaving the old source's line on screen;
//   - the display link asks for the rate the view draws at, up to the screen's: 60 (Bars 120 on a 120 Hz screen,
//     60 on a 60 Hz one), 30 with the player's lyrics open over the hills, 15 with Reduce Motion; and the hills draw
//     60, 30 and 15 times a second in those three cases from a 120 Hz link's ticks;
//   - the five first style ids, their order and names stay, Poster and Cut follow them, and an unknown or absent
//     stored style reads as Hills;
//   - Poster and Cut's parameters read their defaults when missing or malformed, clamp numbers, parse only
//     "#RRGGBB", and storing a default removes it without leaving an empty dictionary;
//   - Poster paints the words whose start has passed in the type color and the rest at the Words ahead opacity,
//     Cut shows the word whose start passed last, both switching exactly at a word's start;
//   - with lyrics nothing times, in a break, or under the player's lyrics, neither shows anything over the hills;
//   - the halftone is made off the calling turn, once per artwork: the same print through frames, words and a
//     second view, a new one for a new cover, the plain cover with Halftone off; a print that cannot be made is
//     final for its artwork and never asked again from its own answer; an older print ending after a newer one
//     reaches its own callers but does not replace the kept newer one;
//   - Reduce Motion: Poster's new line neither rises nor scales, Cut's word does not jump (nor at Motion 0);
//   - the cover is taken only by the player's own view and only while its stage shows a line: a break, lyrics
//     nothing times, the player's lyrics, another style and the view leaving the field give it back, and so do
//     leaving the window or the app leaving the front, until it comes back;
//   - in the player the type's field is the cover's band down to 12 points over the title block (the player's own
//     sung line where it has room, else the title), and Cut's whole line goes while the player shows that line,
//     else sits directly under the word inside the field, a short field's word sized to leave it room.
// With SHOTS set to a folder, writes poster.png and cut.png of both styles there. Exits 1 on any failure.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "Redesigned/Kit/SGRKit.h"
#import "Redesigned/Lyrics/LyricsLook.h"
#import "Shared/AudioEffects/AudioEffects.h"
#import "Shared/Lyrics/Lyrics.h"
#import "Shared/Player/PlayerEvents.h"
#import "Shared/Player/PlayerState.h"
#import "Shared/Player/SpeedPitch.h"
#import "Settings/SGModPage.h"
#import "Player.h"
#import "../harness-wait.h"

#pragma mark - the stubs

static NSString *gTrack = @"track-a";
static NSArray<SGKaraokeLine *> *gLines;
static NSInteger gPositionMs;
static BOOL gReduceMotion;
// The now playing artwork and its identity, nil for none; the palette's flow colors, nil for no answer.
static UIImage *gArtwork;
static NSString *gArtworkID;
static NSArray<UIColor *> *gFlow;
// Run as each animation starts, before its block: what the view set up to animate from.
static void (^gBeforeAnimate)(void);

NSNotificationName const SGKaraokeLinesKeptNotification = @"harness.linesKept";
NSNotificationName const SGRNowPlayingArtworkDidChangeNotification = @"harness.artwork";
const NSTimeInterval SGRCrossfade = 0.35;

NSString *SGL(NSString *key, NSString *english) { return english; }
BOOL SGRReduceMotion(void) { return gReduceMotion; }
void SGRAnimate(SGRMotion motion, void (^animations)(void), void (^completion)(BOOL finished)) {
    if (gBeforeAnimate) gBeforeAnimate();
    animations();
    if (completion) completion(YES);
}
UIColor *SGColorRGB(NSInteger rgb) {
    return [UIColor colorWithRed:((rgb >> 16) & 0xFF) / 255.0 green:((rgb >> 8) & 0xFF) / 255.0 blue:(rgb & 0xFF) / 255.0 alpha:1];
}
NSString *SGKaraokePlayingTrack(void) { return gTrack; }
NSArray<SGKaraokeLine *> *SGKaraokeLinesForTrack(NSString *trackID) { return [trackID isEqual:gTrack] ? gLines : nil; }
void SGKaraokeRequestLyrics(NSString *trackID) {}
NSInteger SGKaraokePositionMs(void) { return gPositionMs; }
NSInteger SGKaraokeDelayMs(void) { return 0; }
NSArray<SGKaraokeLine *> *SGRLyricsSampleLines(void) { return nil; }
NSInteger SGRLyricsSampleLength(void) { return 1; }
void SGAudioSetOutputReader(SGAudioOutputReader reader) {}
void SGAddPlayerStateObserver(id<SGPlayerStateObserver> observer) {}
// The playing track's URI, whatever is asked: the artwork below is always the playing track's own.
NSString *SGURIString(id uri) { return gTrack; }
CFTimeInterval SGPlayerTransitionEnds(void) { return 0; }
BOOL SGRPlayerIsTransitioning(void) { return NO; }
void SGRObservePlayerTransition(id owner, void (^changed)(id owner)) {}
UIImage *SGRNowPlayingArtwork(NSString **trackURI, NSString **identity) {
    if (trackURI) *trackURI = gArtwork ? gTrack : nil;
    if (identity) *identity = gArtwork ? gArtworkID : nil;
    return gArtwork;
}
BOOL SGPlayerMenuOffersAnimatedArtwork(void) { return NO; }
void SGPlayerMenuSetAnimatedArtwork(BOOL on) {}
SGRPlayerBackgroundKind SGRPlayerBackground(void) { return SGRPlayerBackgroundVisualiser; }
NSUInteger SGRSetPlayerBackground(SGRPlayerBackgroundKind kind) { return 0; }
SGRArtworkField *SGRPlayerField(void) { return nil; }
void SGRPlayerHoldField(void) {}
BOOL SGRPlayerLyricsOpen(void) { return NO; }
BOOL SGRPlayerPageOpen(void) { return NO; }
BOOL SGRPlayerMotionShowing(void) { return NO; }
// PlayerMotion.x's no-clip fallback and the shuffle and heat switches (Core/SGPrefs.m): all off, as unset.
BOOL SGHidden(NSString *key) { return NO; }
BOOL SGRPlayerAnimatedVisualiserOn(void) { return NO; }
void SGRPlayerReconcileFallbackSwitches(void) {}
BOOL SGRPlayerVisualiserFallbackWanted(void) { return NO; }
// The player around the view (PlayerArtwork.x, PlayerLyricLine.x, PlayerMotion.x), in the view's coordinates: the
// cover's band and the player's own line over the title, CGRectNull for none; whether the cover is taken.
static CGRect gArea, gPlayerLine;
static BOOL gCoverTaken;
CGRect SGRPlayerArtworkAreaIn(UIView *host) { return gArea; }
CGRect SGRPlayerLyricLineIn(UIView *view) { return gPlayerLine; }
void SGRPlayerLyricStageTakesCover(BOOL takes) { gCoverTaken = takes; }

// The device can remain foreground-inactive while the stage is visible. A nil shared application in the
// command-line harness otherwise reads as Active and cannot exercise that boundary.
@interface HarnessApplication : NSObject
@property (nonatomic) UIApplicationState applicationState;
@end
@implementation HarnessApplication
@end

// A song that is playing, so the Lyrics style keeps its clock.
@implementation SPTPlayerState
- (BOOL)isPaused { return NO; }
@end
SPTPlayerState *SGPlayerState(void) {
    static SPTPlayerState *playing;
    if (!playing) playing = [SPTPlayerState new];
    return playing;
}

@implementation SGRPalette
+ (void)paletteForImage:(UIImage *)image request:(SGRPaletteRequest)request completion:(void (^)(SGRPalette *palette))completion {
    if (!gFlow) return;
    SGRPalette *palette = [SGRPalette new];
    [palette setValue:gFlow forKey:@"flowColors"];
    completion(palette);
}
+ (void)tintForImage:(UIImage *)image surface:(UIColor *)surface strong:(BOOL)strong completion:(void (^)(UIColor *tint))completion {}
@end

#pragma mark - the harness

@protocol Probe <NSObject>
- (void)lyricsKept:(NSNotification *)note;
- (void)tick:(id)link;
- (void)setMoving:(BOOL)moving;
- (void)setBlurred:(BOOL)blurred animated:(BOOL)animated;
- (void)readLine;
- (void)showCover;
@end

// A window on a 120 Hz screen: a command line Mac Catalyst process has no scene to make a UIWindow in.
@interface FakeScreen : NSObject
@property (nonatomic) NSInteger maximumFramesPerSecond;
@end
@implementation FakeScreen
@end
@interface FakeWindow : NSObject
@property (nonatomic, strong) FakeScreen *screen;
@end
@implementation FakeWindow
@end

// The window the view reports while set; UIKit's own hierarchy code never sees it, as it would take it for a
// UIWindow, so it is set only around the calls that read the screen's rate.
static FakeWindow *gWindow;

static UIView *visualiser(void) {
    static Class made;
    if (!made) {
        made = objc_allocateClassPair(NSClassFromString(@"SGRVisualiserView"), "HarnessVisualiser", 0);
        class_addMethod(made, @selector(window), imp_implementationWithBlock(^id(id self) { return gWindow; }), "@@:");
        objc_registerClassPair(made);
    }
    return [[made alloc] initWithFrame:CGRectMake(0, 0, 390, 844)];
}

// What -tick: reads of a display link.
@interface FakeLink : NSObject
@property (nonatomic) CFTimeInterval timestamp, duration;
@end
@implementation FakeLink
@end

static SGKaraokeLine *line(NSString *text, NSInteger start, NSInteger end, SGKaraokeTiming timing) {
    SGKaraokeWord *word = [SGKaraokeWord new];
    word.text = text;
    word.start = start;
    word.end = end;
    SGKaraokeLine *one = [SGKaraokeLine new];
    one.words = @[ word ];
    one.start = start;
    one.end = end;
    one.timing = timing;
    return one;
}

// A line of timed words: @[text, start ms] each, the line ending at `end`.
static SGKaraokeLine *wordsLine(NSArray<NSArray *> *timed, NSInteger end) {
    NSMutableArray<SGKaraokeWord *> *words = [NSMutableArray array];
    for (NSUInteger i = 0; i < timed.count; i++) {
        SGKaraokeWord *word = [SGKaraokeWord new];
        word.text = timed[i][0];
        word.start = [timed[i][1] integerValue];
        word.end = i + 1 < timed.count ? [timed[i + 1][1] integerValue] : end;
        [words addObject:word];
    }
    SGKaraokeLine *one = [SGKaraokeLine new];
    one.words = words;
    one.start = words.firstObject.start;
    one.end = end;
    one.timing = SGKaraokeTimingWords;
    return one;
}

static void keep(NSArray<SGKaraokeLine *> *lines) {
    gLines = lines;
    [NSNotificationCenter.defaultCenter postNotificationName:SGKaraokeLinesKeptNotification object:gTrack];
}

static void readAt(UIView *view, NSInteger ms) {
    gPositionMs = ms;
    [(id<Probe>)view readLine];
}

static UIView *stageOf(UIView *view) {
    return [view valueForKey:@"_stage"];
}

// The alpha of the color `word` is painted in on Poster's front label, -1 when it is not there.
static CGFloat inkAlpha(UIView *view, NSString *word) {
    UILabel *front = [stageOf(view) valueForKey:@"_front"];
    NSAttributedString *text = front.attributedText;
    NSRange range = [text.string rangeOfString:word];
    if (range.location == NSNotFound) return -1;
    UIColor *color = [text attribute:NSForegroundColorAttributeName atIndex:range.location effectiveRange:NULL];
    return CGColorGetAlpha(color.CGColor);
}

static BOOL near(double a, double b) { return fabs(a - b) < 0.001; }

static id printOf(UIView *view) {
    return [[stageOf(view) valueForKey:@"_print"] contents];
}


static UIImage *coverArt(UIColor *top, UIColor *bottom, UIColor *disc) {
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat new];
    format.scale = 1;
    format.opaque = YES;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(600, 600) format:format];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        CGContextRef cg = context.CGContext;
        CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
        CGGradientRef gradient = CGGradientCreateWithColors(space, (__bridge CFArrayRef)@[(id)top.CGColor, (id)bottom.CGColor], NULL);
        CGContextDrawLinearGradient(cg, gradient, CGPointZero, CGPointMake(600, 600), 0);
        CGGradientRelease(gradient);
        CGColorSpaceRelease(space);
        [disc setFill];
        CGContextFillEllipseInRect(cg, CGRectMake(150, 90, 300, 300));
        [UIColor.whiteColor setFill];
        for (int i = 0; i < 4; i++) CGContextFillRect(cg, CGRectMake(0, 440 + i * 36, 600, 12 + 4 * i));
    }];
}

// A cover whose bitmap can be read only once gGate opens, so the print made from it ends when the harness says.
static dispatch_semaphore_t gGate;
static size_t gatedBytes(void *info, void *buffer, size_t count) {
    dispatch_semaphore_wait(gGate, DISPATCH_TIME_FOREVER);
    dispatch_semaphore_signal(gGate);
    memset(buffer, 0x90, count);
    return count;
}
static off_t gatedSkip(void *info, off_t count) { return count; }
static void gatedRewind(void *info) {}
static UIImage *gatedArt(void) {
    enum { kSide = 64 };
    CGDataProviderSequentialCallbacks callbacks = {0, gatedBytes, gatedSkip, gatedRewind, NULL};
    CGDataProviderRef provider = CGDataProviderCreateSequential(NULL, &callbacks);
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGImageRef image = CGImageCreate(kSide, kSide, 8, 32, kSide * 4, space, (CGBitmapInfo)kCGImageAlphaNoneSkipLast, provider, NULL, NO,
                                     kCGRenderingIntentDefault);
    UIImage *art = [UIImage imageWithCGImage:image];
    CGImageRelease(image);
    CGColorSpaceRelease(space);
    CGDataProviderRelease(provider);
    return art;
}

// Poster's showCover re-entered deeper than an answer given at once takes it (twice) fails the run, rather than
// recursing until the process crashes.
static const int kShowCoverDepth = 4;
static int gShowCoverDepth;
static void guardShowCover(void) {
    Method method = class_getInstanceMethod(NSClassFromString(@"SGRPosterStage"), @selector(showCover));
    HARNESS_CHECK(method != NULL);
    void (*original)(id, SEL) = (void (*)(id, SEL))method_getImplementation(method);
    method_setImplementation(method, imp_implementationWithBlock(^(id stage) {
        if (++gShowCoverDepth > kShowCoverDepth) HARNESS_FAIL(@"Poster's showCover re-entered %d deep", gShowCoverDepth);
        original(stage, @selector(showCover));
        gShowCoverDepth--;
    }));
}

// The view as the player would show it, on black, into SHOTS/<name>.png when SHOTS is set.
static void shoot(UIView *view, NSString *name) {
    NSString *folder = NSProcessInfo.processInfo.environment[@"SHOTS"];
    if (!folder.length) return;
    [view setNeedsLayout];
    [view layoutIfNeeded];
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat new];
    format.scale = 3;
    format.opaque = YES;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:view.bounds.size format:format];
    UIImage *image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [UIColor.blackColor setFill];
        UIRectFill(view.bounds);
        [view.layer renderInContext:context.CGContext];
    }];
    NSString *path = [folder stringByAppendingPathComponent:[name stringByAppendingPathExtension:@"png"]];
    HARNESS_CHECK([UIImagePNGRepresentation(image) writeToFile:path atomically:YES]);
}

// The most visible label's text, nil when none shows.
static NSString *shownWords(UIView *view) {
    for (UILabel *label in [view valueForKey:@"_lyricLabels"]) {
        if (label.alpha > 0) return label.text;
    }
    return nil;
}

// How many of `ticks` ticks of a 120 Hz link the view draws on, counted by the clock it keeps for dt.
static NSUInteger drawsOf(UIView *view, NSUInteger ticks) {
    FakeLink *link = [FakeLink new];
    link.duration = 1.0 / 120;
    [view setValue:@0 forKey:@"_last"];
    NSUInteger draws = 0;
    CFTimeInterval before = 0;
    for (NSUInteger i = 0; i < ticks; i++) {
        link.timestamp = 100 + (double)i / 120;
        [(id<Probe>)view tick:link];
        CFTimeInterval after = [[view valueForKey:@"_last"] doubleValue];
        if (after != before) draws++;
        before = after;
    }
    return draws;
}

int main(void) {
    @autoreleasepool {
        HarnessApplication *application = [HarnessApplication new];
        method_setImplementation(class_getClassMethod(UIApplication.class, @selector(sharedApplication)),
            imp_implementationWithBlock(^id(id receiver) { return application; }));
        guardShowCover();
        gArea = gPlayerLine = CGRectNull;
        [NSUserDefaults.standardUserDefaults setObject:@"builtin:lyrics" forKey:SGRKeyVisualiserStyle];
        gLines = @[ line(@"hold me close", 0, 3000, SGKaraokeTimingLine) ];
        gPositionMs = 1000;

        FakeWindow *window = [FakeWindow new];
        window.screen = [FakeScreen new];
        window.screen.maximumFramesPerSecond = 120;
        UIView *view = visualiser();

        // The synced line is on screen; the playing track's lyrics are then replaced by ones nothing times.
        HARNESS_CHECK([shownWords(view) isEqualToString:@"hold me close"]);
        gLines = @[ line(@"plain words", 0, 0, SGKaraokeTimingNone) ];
        [NSNotificationCenter.defaultCenter postNotificationName:SGKaraokeLinesKeptNotification object:@"track-a"];
        HARNESS_CHECK(shownWords(view) == nil);
        // Back to synced lyrics: the line returns.
        gLines = @[ line(@"hold me close", 0, 3000, SGKaraokeTimingLine) ];
        [NSNotificationCenter.defaultCenter postNotificationName:SGKaraokeLinesKeptNotification object:@"track-a"];
        HARNESS_CHECK([shownWords(view) isEqualToString:@"hold me close"]);

        // The link asks for the rate the view draws at, its maximum the screen's.
        gWindow = window;
        HARNESS_CHECK(window.screen.maximumFramesPerSecond == 120);
        id<Probe> probe = (id<Probe>)view;
        [probe setMoving:YES];
        CADisplayLink *link = [view valueForKey:@"_link"];
        HARNESS_CHECK(link != nil);
        HARNESS_CHECK(CAFrameRateRangeIsEqualToRange(link.preferredFrameRateRange, CAFrameRateRangeMake(60, 120, 60)));
        [probe setBlurred:YES animated:NO];
        [probe setMoving:YES];
        HARNESS_CHECK(CAFrameRateRangeIsEqualToRange(link.preferredFrameRateRange, CAFrameRateRangeMake(30, 120, 30)));
        [probe setBlurred:NO animated:NO];
        gReduceMotion = YES;
        [probe setMoving:YES];
        HARNESS_CHECK(CAFrameRateRangeIsEqualToRange(link.preferredFrameRateRange, CAFrameRateRangeMake(15, 120, 15)));
        gReduceMotion = NO;
        SGRSetVisualiserStyle(@"builtin:bars");
        [probe setMoving:YES];
        HARNESS_CHECK(CAFrameRateRangeIsEqualToRange(link.preferredFrameRateRange, CAFrameRateRangeMake(120, 120, 120)));
        window.screen.maximumFramesPerSecond = 60;
        [probe setMoving:YES];
        HARNESS_CHECK(CAFrameRateRangeIsEqualToRange(link.preferredFrameRateRange, CAFrameRateRangeMake(60, 60, 60)));
        window.screen.maximumFramesPerSecond = 120;
        SGRSetVisualiserStyle(@"builtin:lyrics");

        // The hills draw 60 times a second normally, 30 behind the player's lyrics and 15 with Reduce Motion.
        HARNESS_CHECK(drawsOf(view, 120) == 60);
        [probe setBlurred:YES animated:NO];
        HARNESS_CHECK(drawsOf(view, 120) == 30);
        [probe setBlurred:NO animated:NO];
        gReduceMotion = YES;
        HARNESS_CHECK(drawsOf(view, 120) == 15);
        gReduceMotion = NO;
        // The link holds its target: down, the view goes.
        [probe setMoving:NO];
        gWindow = nil;
        view = nil;
        probe = nil;

        // The five first styles keep their ids, order and names; Poster and Cut follow; Hills stays the default.
        NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
        NSArray<NSString *> *ids = SGRVisualiserStyleIDs();
        HARNESS_CHECK([ids isEqualToArray:(@[@"builtin:hills", @"builtin:bars", @"builtin:nebula", @"builtin:halo", @"builtin:lyrics",
                                             @"builtin:poster", @"builtin:cut"])]);
        HARNESS_CHECK([SGRVisualiserStyleNames() isEqualToArray:(@[@"Hills", @"Bars", @"Nebula", @"Halo", @"Lyrics", @"Poster", @"Cut"])]);
        [defaults removeObjectForKey:SGRKeyVisualiserStyle];
        HARNESS_CHECK([SGRVisualiserStyle() isEqualToString:@"builtin:hills"]);
        [defaults setObject:@"builtin:posters" forKey:SGRKeyVisualiserStyle];
        HARNESS_CHECK([SGRVisualiserStyle() isEqualToString:@"builtin:hills"]);
        for (NSString *identifier in ids) {
            [defaults setObject:identifier forKey:SGRKeyVisualiserStyle];
            HARNESS_CHECK([SGRVisualiserStyle() isEqualToString:identifier]);
        }

        // The parameters: defaults when absent or malformed, numbers clamped, colors only as "#RRGGBB".
        NSString *poster = SGRVisualiserPosterID, *cut = SGRVisualiserCutID;
        [defaults removeObjectForKey:SGRKeyVisualiserParams];
        HARNESS_CHECK(SGRVisualiserParam(poster, @"halftone") == 1);
        HARNESS_CHECK(SGRVisualiserParam(poster, @"ink") == 0xF4EFE6);
        HARNESS_CHECK(near(SGRVisualiserParam(poster, @"backdrop"), 0.6));
        HARNESS_CHECK(near(SGRVisualiserParam(poster, @"ghost"), 0.35));
        HARNESS_CHECK(SGRVisualiserParam(cut, @"ink") == 0xFFFFFF);
        HARNESS_CHECK(near(SGRVisualiserParam(cut, @"shade"), 0.75));
        HARNESS_CHECK(near(SGRVisualiserParam(cut, @"motion"), 1));
        HARNESS_CHECK(SGRVisualiserParam(cut, @"subtitle") == 1);
        [defaults setObject:@"params" forKey:SGRKeyVisualiserParams];
        HARNESS_CHECK(near(SGRVisualiserParam(poster, @"backdrop"), 0.6));
        [defaults setObject:@{poster: @{@"halftone": @"no", @"ink": @"#GG0000", @"backdrop": @7, @"ghost": @(-1)}, cut: @"shade"}
                     forKey:SGRKeyVisualiserParams];
        HARNESS_CHECK(SGRVisualiserParam(poster, @"halftone") == 1);
        HARNESS_CHECK(SGRVisualiserParam(poster, @"ink") == 0xF4EFE6);
        HARNESS_CHECK(near(SGRVisualiserParam(poster, @"backdrop"), 1));
        HARNESS_CHECK(near(SGRVisualiserParam(poster, @"ghost"), 0));
        HARNESS_CHECK(near(SGRVisualiserParam(cut, @"shade"), 0.75));
        for (id ink in @[@"12ab34", @"#12ab3", @"#12ab345", @(0x12AB34)]) {
            [defaults setObject:@{cut: @{@"ink": ink, @"motion": @9}} forKey:SGRKeyVisualiserParams];
            HARNESS_CHECK(SGRVisualiserParam(cut, @"ink") == 0xFFFFFF);
            HARNESS_CHECK(near(SGRVisualiserParam(cut, @"motion"), 1.5));
        }
        [defaults setObject:@{cut: @{@"ink": @"#12ab34", @"subtitle": @NO}} forKey:SGRKeyVisualiserParams];
        HARNESS_CHECK(SGRVisualiserParam(cut, @"ink") == 0x12AB34);
        HARNESS_CHECK(SGRVisualiserParam(cut, @"subtitle") == 0);
        // Stored as one dictionary; a default stored is removed, and nothing empty is left behind.
        [defaults removeObjectForKey:SGRKeyVisualiserParams];
        SGRSetVisualiserParam(poster, @"ghost", 0.42);
        SGRSetVisualiserParam(poster, @"ink", 0x112233);
        SGRSetVisualiserParam(cut, @"subtitle", 0);
        HARNESS_CHECK([[defaults objectForKey:SGRKeyVisualiserParams] isEqual:(@{poster: @{@"ghost": @0.42, @"ink": @"#112233"}, cut: @{@"subtitle": @NO}})]);
        HARNESS_CHECK(near(SGRVisualiserParam(poster, @"ghost"), 0.42));
        SGRSetVisualiserParam(poster, @"ghost", 0.35);
        SGRSetVisualiserParam(cut, @"subtitle", 1);
        HARNESS_CHECK([[defaults objectForKey:SGRKeyVisualiserParams] isEqual:(@{poster: @{@"ink": @"#112233"}})]);
        SGRSetVisualiserParam(poster, @"ink", 0xF4EFE6);
        HARNESS_CHECK([defaults objectForKey:SGRKeyVisualiserParams] == nil);

        // Poster: a word takes the type color as its start passes; the words ahead stay at Words ahead's opacity.
        SGKaraokeLine *first = wordsLine(@[@[@"we", @1000], @[@"run", @1300], @[@"tonight", @1600], @[@"under", @2000],
                                           @[@"the", @2300], @[@"neon", @2500], @[@"light", @2700]], 3200);
        SGKaraokeLine *second = wordsLine(@[@[@"hold", @3400], @[@"on", @3800], @[@"forever", @4200]], 5200);
        SGKaraokeLine *third = wordsLine(@[@[@"again", @20000]], 21000);
        gLines = @[first, second, third];
        gArtwork = nil;
        [defaults setObject:poster forKey:SGRKeyVisualiserStyle];
        UIView *v = visualiser();
        probe = (id<Probe>)v;
        HARNESS_CHECK([v.accessibilityValue isEqualToString:@"Poster"]);
        readAt(v, 1299);
        HARNESS_CHECK(near(stageOf(v).alpha, 1));
        HARNESS_CHECK(near(inkAlpha(v, @"we"), 1));
        HARNESS_CHECK(near(inkAlpha(v, @"run"), 0.35));
        HARNESS_CHECK(near(inkAlpha(v, @"tonight"), 0.35));
        readAt(v, 1300);
        HARNESS_CHECK(near(inkAlpha(v, @"run"), 1));
        HARNESS_CHECK(near(inkAlpha(v, @"tonight"), 0.35));
        readAt(v, 2699);
        HARNESS_CHECK(near(inkAlpha(v, @"neon"), 1) && near(inkAlpha(v, @"light"), 0.35));
        readAt(v, 2700);
        HARNESS_CHECK(near(inkAlpha(v, @"light"), 1));
        // Words ahead at 0 hides them; the change applies to the line on screen.
        readAt(v, 1300);
        SGRSetVisualiserParam(poster, @"ghost", 0);
        HARNESS_CHECK(near(inkAlpha(v, @"tonight"), 0) && near(inkAlpha(v, @"run"), 1));
        SGRSetVisualiserParam(poster, @"ghost", 0.35);

        // The halftone: made off the calling turn, then the same print through frames and words, and for a
        // second view of the same artwork without waiting; a new artwork makes a new one.
        gArtwork = coverArt([UIColor colorWithRed:0.10 green:0.16 blue:0.45 alpha:1], [UIColor colorWithRed:0.85 green:0.20 blue:0.45 alpha:1],
                            [UIColor colorWithRed:1.00 green:0.62 blue:0.18 alpha:1]);
        gArtworkID = @"art-a";
        gFlow = @[[UIColor colorWithRed:0.16 green:0.20 blue:0.55 alpha:1], [UIColor colorWithRed:0.55 green:0.18 blue:0.42 alpha:1],
                  [UIColor colorWithRed:0.70 green:0.36 blue:0.10 alpha:1], [UIColor colorWithRed:0.62 green:0.14 blue:0.30 alpha:1],
                  [UIColor colorWithRed:0.40 green:0.18 blue:0.48 alpha:1]];
        [NSNotificationCenter.defaultCenter postNotificationName:SGRNowPlayingArtworkDidChangeNotification object:nil];
        HARNESS_CHECK(printOf(v) == nil);
        HARNESS_AWAIT(printOf(v) != nil);
        id print = printOf(v);
        HARNESS_CHECK(print != (id)gArtwork.CGImage);
        gWindow = window;
        FakeLink *frames = [FakeLink new];
        frames.duration = 1.0 / 120;
        for (int i = 0; i < 240; i++) {
            frames.timestamp = 200 + i / 120.0;
            gPositionMs = 1000 + i * 13;   // up to 4107: into the second line, before its last word
            [probe tick:frames];
        }
        gWindow = nil;
        HARNESS_CHECK(near(inkAlpha(v, @"hold"), 1) && near(inkAlpha(v, @"forever"), 0.35));
        HARNESS_CHECK(printOf(v) == print);
        UIView *again = visualiser();
        HARNESS_CHECK(printOf(again) == print);
        again = nil;
        // Halftone off shows the plain cover; on again, the kept print at once.
        SGRSetVisualiserParam(poster, @"halftone", 0);
        HARNESS_CHECK(printOf(v) == (id)gArtwork.CGImage);
        SGRSetVisualiserParam(poster, @"halftone", 1);
        HARNESS_CHECK(printOf(v) == print);
        readAt(v, 2000);
        shoot(v, @"poster");
        UIImage *artA = gArtwork;
        gArtwork = coverArt(UIColor.darkGrayColor, UIColor.blackColor, UIColor.whiteColor);
        gArtworkID = @"art-b";
        [NSNotificationCenter.defaultCenter postNotificationName:SGRNowPlayingArtworkDidChangeNotification object:nil];
        HARNESS_AWAIT(printOf(v) != nil && printOf(v) != print);
        HARNESS_CHECK(printOf(v) != print);

        // A print that cannot be made (a cover with no bitmap: the nil answer a failed allocation gives) is final for
        // that artwork: the plain cover's path, asked once, never asked again from its own answer (the showCover
        // guard), and a second view takes the nil answer at once without asking either.
        gArtwork = [UIImage new];
        gArtworkID = @"art-empty";
        [NSNotificationCenter.defaultCenter postNotificationName:SGRNowPlayingArtworkDidChangeNotification object:nil];
        HARNESS_AWAIT(printOf(v) == (id)gArtwork.CGImage);
        HARNESS_CHECK(printOf(v) == (id)gArtwork.CGImage);
        UIView *failed = visualiser();
        HARNESS_CHECK(printOf(failed) == (id)gArtwork.CGImage);
        failed = nil;
        SGRSetVisualiserParam(poster, @"halftone", 0);
        SGRSetVisualiserParam(poster, @"halftone", 1);

        // An older job ending after a newer one: its own callers get its print, and the newer print stays kept.
        gGate = dispatch_semaphore_create(0);
        gArtwork = gatedArt();
        gArtworkID = @"art-slow";
        [NSNotificationCenter.defaultCenter postNotificationName:SGRNowPlayingArtworkDidChangeNotification object:nil];
        gArtwork = coverArt(UIColor.greenColor, UIColor.blueColor, UIColor.yellowColor);
        gArtworkID = @"art-fast";
        UIView *newer = visualiser();
        HARNESS_AWAIT(printOf(newer) != nil);
        id fastPrint = printOf(newer);
        HARNESS_CHECK(printOf(v) == nil);
        dispatch_semaphore_signal(gGate);
        HARNESS_AWAIT(printOf(v) != nil);
        HARNESS_CHECK(printOf(v) != fastPrint);
        UIView *later = visualiser();
        HARNESS_CHECK(printOf(later) == fastPrint);
        newer = nil;
        later = nil;

        gArtwork = artA;
        gArtworkID = @"art-a";
        [NSNotificationCenter.defaultCenter postNotificationName:SGRNowPlayingArtworkDidChangeNotification object:nil];
        HARNESS_AWAIT(printOf(v) != nil);

        // Poster under Reduce Motion: the new line only fades in; otherwise it rises into place.
        __block BOOL moved = NO;
        gBeforeAnimate = ^{
            for (UILabel *label in [stageOf(v) valueForKey:@"_labels"]) {
                if (!CGAffineTransformIsIdentity(label.transform)) moved = YES;
            }
        };
        readAt(v, 1000);
        moved = NO;
        readAt(v, 3400);
        HARNESS_CHECK(moved);
        gReduceMotion = YES;
        moved = NO;
        readAt(v, 1000);
        HARNESS_CHECK(!moved);
        gReduceMotion = NO;
        gBeforeAnimate = nil;

        // Cut: the word whose start passed last, switching exactly at each start; the whole line under it.
        SGRSetVisualiserStyle(cut);
        HARNESS_CHECK([v.accessibilityValue isEqualToString:@"Cut"]);
        UILabel *(^shownWord)(void) = ^UILabel *{ return [stageOf(v) valueForKey:@"_wordLabel"]; };
        NSArray *boundaries = @[@[@1000, @"we"], @[@1299, @"we"], @[@1300, @"run"], @[@1599, @"run"], @[@1600, @"tonight"],
                                @[@3399, @"light"], @[@3400, @"hold"], @[@4199, @"on"], @[@4200, @"forever"]];
        for (NSArray *boundary in boundaries) {
            readAt(v, [boundary[0] integerValue]);
            HARNESS_CHECK([shownWord().text isEqualToString:boundary[1]]);
        }
        HARNESS_CHECK(near(stageOf(v).alpha, 1));
        UILabel *wholeLine = [stageOf(v) valueForKey:@"_lineLabel"];
        HARNESS_CHECK([wholeLine.text isEqualToString:@"hold on forever"] && !wholeLine.hidden);
        SGRSetVisualiserParam(cut, @"subtitle", 0);
        HARNESS_CHECK(wholeLine.hidden);
        SGRSetVisualiserParam(cut, @"subtitle", 1);
        // In a break nothing shows over the hills; the next line brings it back.
        readAt(v, 12000);
        HARNESS_CHECK(near(stageOf(v).alpha, 0));
        readAt(v, 20000);
        HARNESS_CHECK(near(stageOf(v).alpha, 1) && [shownWord().text isEqualToString:@"again"]);
        // Under the player's own lyrics nothing shows either.
        [probe setBlurred:YES animated:NO];
        HARNESS_CHECK(near(stageOf(v).alpha, 0));
        [probe setBlurred:NO animated:NO];
        HARNESS_CHECK(near(stageOf(v).alpha, 1));

        // Cut's jump: on a new word, none with Reduce Motion or at Motion 0.
        CALayer *(^cutLayer)(void) = ^CALayer *{ return [[stageOf(v) valueForKey:@"_cut"] layer]; };
        readAt(v, 1000);
        readAt(v, 1300);
        HARNESS_CHECK([cutLayer() animationForKey:@"cut"] != nil);
        gReduceMotion = YES;
        readAt(v, 1600);
        HARNESS_CHECK([cutLayer() animationForKey:@"cut"] == nil);
        gReduceMotion = NO;
        SGRSetVisualiserParam(cut, @"motion", 0);
        readAt(v, 2000);
        HARNESS_CHECK([cutLayer() animationForKey:@"cut"] == nil);
        SGRSetVisualiserParam(cut, @"motion", 1);
        readAt(v, 1600);
        shoot(v, @"cut");

        // Lyrics nothing times: both show what Lyrics shows then, the quiet hills alone.
        for (NSString *style in @[cut, poster]) {
            SGRSetVisualiserStyle(style);
            keep(@[first, second, third]);
            readAt(v, 1300);
            HARNESS_CHECK(near(stageOf(v).alpha, 1));
            SGKaraokeLine *plain = wordsLine(@[@[@"we", @0], @[@"run", @0]], 0);
            plain.timing = SGKaraokeTimingNone;
            keep(@[plain]);
            readAt(v, 1300);
            HARNESS_CHECK(near(stageOf(v).alpha, 0));
            HARNESS_CHECK(![[v valueForKey:@"_frontFill"] isHidden]);
        }

        // The cover: a view that is not the player's own (the settings card's) never takes it, the player's takes it
        // only while its stage shows a line, in a window with the app in front.
        gWindow = window;
        keep(@[first, second, third]);
        readAt(v, 1300);
        HARNESS_CHECK(near(stageOf(v).alpha, 1) && !gCoverTaken);
        [v setValue:@YES forKey:@"ownsCover"];
        HARNESS_CHECK(gCoverTaken);
        readAt(v, 12000);
        HARNESS_CHECK(!gCoverTaken);
        readAt(v, 20000);
        HARNESS_CHECK(gCoverTaken);
        [probe setBlurred:YES animated:NO];
        HARNESS_CHECK(!gCoverTaken);
        [probe setBlurred:NO animated:NO];
        HARNESS_CHECK(gCoverTaken);
        SGKaraokeLine *untimed = wordsLine(@[@[@"we", @0], @[@"run", @0]], 0);
        untimed.timing = SGKaraokeTimingNone;
        keep(@[untimed]);
        readAt(v, 1300);
        HARNESS_CHECK(!gCoverTaken);
        keep(@[first, second, third]);
        readAt(v, 1300);
        HARNESS_CHECK(gCoverTaken);
        SGRSetVisualiserStyle(@"builtin:lyrics");
        HARNESS_CHECK(!gCoverTaken);
        SGRSetVisualiserStyle(cut);
        readAt(v, 1300);
        HARNESS_CHECK(gCoverTaken);
        // Off its window (the player closed mid-line) the cover comes back, and a report read there does not take it
        // again; back on the window it is taken again. The same for the app leaving the front and coming back.
        gWindow = nil;
        [v didMoveToWindow];
        HARNESS_CHECK(!gCoverTaken);
        readAt(v, 1300);
        HARNESS_CHECK(!gCoverTaken);
        gWindow = window;
        [v didMoveToWindow];
        HARNESS_CHECK(gCoverTaken);
        [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationWillResignActiveNotification object:nil];
        application.applicationState = UIApplicationStateInactive;
        readAt(v, 1300);
        HARNESS_CHECK(gCoverTaken);
        application.applicationState = UIApplicationStateBackground;
        [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationDidEnterBackgroundNotification object:nil];
        HARNESS_CHECK(!gCoverTaken);
        readAt(v, 1300);
        HARNESS_CHECK(!gCoverTaken);
        application.applicationState = UIApplicationStateActive;
        [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationDidBecomeActiveNotification object:nil];
        HARNESS_CHECK(gCoverTaken);
        [v setValue:@NO forKey:@"ownsCover"];
        HARNESS_CHECK(!gCoverTaken);
        gWindow = nil;

        // The field in the player (390 by 844): the cover's band from 110 down to the title row at 576.5, the player's
        // own line at 474 to 518 over it.
        gArea = CGRectMake(0, 110, 390, 466.5);
        gPlayerLine = CGRectMake(24, 474, 342, 44);
        [v setNeedsLayout];
        [v layoutIfNeeded];
        readAt(v, 2000);
        CGRect (^fieldOf)(void) = ^CGRect { return [[stageOf(v) valueForKey:@"field"] CGRectValue]; };
        UILabel *bigWord = [stageOf(v) valueForKey:@"_wordLabel"];
        UILabel *caption = [stageOf(v) valueForKey:@"_lineLabel"];
        HARNESS_CHECK(near(CGRectGetMinY(fieldOf()), 110) && near(CGRectGetMaxY(fieldOf()), 462));
        HARNESS_CHECK([bigWord.text isEqualToString:@"under"]);
        HARNESS_CHECK(CGRectGetMinY(bigWord.frame) >= 110 && CGRectGetMaxY(bigWord.frame) <= 462);
        HARNESS_CHECK(caption.hidden);
        // Without the player's line: down to 12 points over the title, the whole line directly under the word.
        gPlayerLine = CGRectNull;
        [v setNeedsLayout];
        [v layoutIfNeeded];
        HARNESS_CHECK(near(CGRectGetMaxY(fieldOf()), 564.5));
        HARNESS_CHECK(!caption.hidden && [caption.text isEqualToString:@"we run tonight under the neon light"]);
        CGFloat under = CGRectGetMinY(caption.frame) - CGRectGetMaxY(bigWord.frame);
        HARNESS_CHECK(under >= 0 && under <= 8);
        HARNESS_CHECK(CGRectGetMaxY(caption.frame) <= 564.5);
        // The player's line coming back with a new line hides the whole line again.
        gPlayerLine = CGRectMake(24, 474, 342, 44);
        readAt(v, 3400);
        HARNESS_CHECK(caption.hidden && near(CGRectGetMaxY(fieldOf()), 462));
        // Poster sets in the same field.
        SGRSetVisualiserStyle(poster);
        readAt(v, 1300);
        UILabel *posterFront = [stageOf(v) valueForKey:@"_front"];
        HARNESS_CHECK(near(CGRectGetMaxY(fieldOf()), 462));
        HARNESS_CHECK(CGRectGetMinY(posterFront.frame) >= 110 && CGRectGetMaxY(posterFront.frame) <= 462);
        // A short field (60 to 208, as in landscape): Cut's short word and the whole line under it both stay inside.
        gArea = CGRectMake(0, 60, 390, 160);
        gPlayerLine = CGRectNull;
        [v setNeedsLayout];
        [v layoutIfNeeded];
        SGRSetVisualiserStyle(cut);
        readAt(v, 2300);
        bigWord = [stageOf(v) valueForKey:@"_wordLabel"];
        caption = [stageOf(v) valueForKey:@"_lineLabel"];
        HARNESS_CHECK([bigWord.text isEqualToString:@"the"] && near(CGRectGetMaxY(fieldOf()), 208));
        HARNESS_CHECK(!caption.hidden && CGRectGetMinY(caption.frame) >= CGRectGetMaxY(bigWord.frame));
        HARNESS_CHECK(CGRectGetMinY(bigWord.frame) >= 60 && CGRectGetMaxY(caption.frame) <= 208);
        gArea = gPlayerLine = CGRectNull;
        [defaults removeObjectForKey:SGRKeyVisualiserParams];
        [defaults removeObjectForKey:SGRKeyVisualiserStyle];

        printf("player visualiser: all checks passed\n");
        return 0;
    }
}
