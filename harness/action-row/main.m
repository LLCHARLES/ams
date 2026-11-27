// The redesign's action row (Kit/SGRHeaderInfo.m, Kit/SGRActionRow.m) on Spotify's play, shuffle and add-to buttons
// mocked under their own class names (../download-mock.h), checked in the simulator against Spotify's own words for
// Play and Pause, read from the SPTStrings.bundle build.sh copies out of a clean Spotify IPA. Each check logs
// "[harness] PASS ..." or exits through HARNESS_FAIL; with HARNESS_SHOTS naming a folder, each state is drawn there.
//
// - the first placement inside a running animation joins none of it (the row cannot slide in from the corner), and the
//   row moves with the header it is in, in the same pass;
// - Play keeps one width as Spotify's button turns from Play to Pause (its isPlaying ivar and its label both change), the
//   words the label carries being the harness's own for each language (fixtureWord), not the lookup's;
// - a row too narrow for the capsule with the usual gap puts a round Play in the capsule's place: swept a point at a
//   time, the capsule shows both words whole down to where its buttons reach the page's sides, round from there on;
// - add-to saved is a fixed 22pt accent disc with a dark check, drawn again in a new accent while it stays saved;
// - the artist page's hold reads playing from the ivar, not the label.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "../harness-fail.h"
#import "../download-mock.h"
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRHeaderInfo.h"
#import "Redesigned/Kit/SGRActionRow.h"
#import "Redesigned/Kit/SGRTokens.h"
#import "Redesigned/Artist/ArtistShuffleHold.h"

// Spotify's PlayButtonView, its Swift stored property isPlaying an ivar of the same name to the runtime.
@interface _TtC28EncoreConsumerMobile_BaseKit14PlayButtonView : UIView {
@public
    BOOL isPlaying;
}
@end
@implementation _TtC28EncoreConsumerMobile_BaseKit14PlayButtonView @end
typedef _TtC28EncoreConsumerMobile_BaseKit14PlayButtonView MockPlayButton;

// Encore's control inside it, which registers no action.
@interface MockCondensedButton : UIControl @end
@implementation MockCondensedButton @end

// stubs.m: the accent SGRAccent() resolves to, nil for Spotify's green.
extern UIColor *harnessAccent;

static const char *sg_shots;
static NSString *sg_language;

static void shoot(UIWindow *window, NSString *name) {
    if (!sg_shots) return;
    UIImage *image = [[[UIGraphicsImageRenderer alloc] initWithBounds:window.bounds] imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [window drawViewHierarchyInRect:window.bounds afterScreenUpdates:YES];
    }];
    NSString *file = [NSString stringWithFormat:@"%@-%@.png", sg_language, name];
    NSString *path = [@(sg_shots) stringByAppendingPathComponent:file];
    if (![UIImagePNGRepresentation(image) writeToFile:path atomically:YES]) HARNESS_FAIL(@"could not write %@", path);
}

static UIImage *glyphImage(NSString *symbol) {
    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:20 weight:UIImageSymbolWeightBold];
    return [[UIImage systemImageNamed:symbol withConfiguration:config] imageWithTintColor:UIColor.blackColor
                                                                            renderingMode:UIImageRenderingModeAlwaysOriginal];
}

static MockCondensedButton *sg_condensed;
static UIImageView *sg_playGlyph;

static MockPlayButton *mockPlayButton(UIView *host, NSString *label) {
    MockPlayButton *play = [[MockPlayButton alloc] initWithFrame:CGRectMake(0, 0, 48, 48)];
    play.accessibilityIdentifier = @"header-play-button";
    [host addSubview:play];
    sg_condensed = [[MockCondensedButton alloc] initWithFrame:play.bounds];
    sg_condensed.accessibilityLabel = label;
    [play addSubview:sg_condensed];
    sg_playGlyph = [[UIImageView alloc] initWithFrame:sg_condensed.bounds];
    sg_playGlyph.contentMode = UIViewContentModeCenter;
    sg_playGlyph.image = glyphImage(@"play.fill");
    [sg_condensed addSubview:sg_playGlyph];
    return play;
}

// As Spotify turns its button: the flag, the label, then the glyph, which is what the capsule hears.
static void setPlaying(MockPlayButton *play, BOOL playing, NSString *label) {
    play->isPlaying = playing;
    sg_condensed.accessibilityLabel = label;
    sg_playGlyph.image = glyphImage(playing ? @"pause.fill" : @"play.fill");
}

static SGRPlayCapsule *capsuleIn(SGRHeaderInfo *info) {
    for (UIView *v in info.subviews) if ([v isKindOfClass:SGRPlayCapsule.class]) return (SGRPlayCapsule *)v;
    return nil;
}

static NSArray<SGRMirrorButton *> *mirrorsIn(SGRHeaderInfo *info) {
    NSMutableArray *found = [NSMutableArray array];
    for (UIView *v in info.subviews) if ([v isKindOfClass:SGRMirrorButton.class]) [found addObject:v];
    return [found sortedArrayUsingComparator:^NSComparisonResult(UIView *a, UIView *b) {
        return [@(a.frame.origin.x) compare:@(b.frame.origin.x)];
    }];
}

// The animations that move or size `layer` or a sublayer (UIKit's "position" and "bounds..." keys); glass runs
// animations of its own on its filters, which place nothing.
static NSUInteger animationsUnder(CALayer *layer, NSMutableArray<NSString *> *seen) {
    NSUInteger count = 0;
    for (NSString *key in layer.animationKeys) {
        if (![key hasPrefix:@"position"] && ![key hasPrefix:@"bounds"]) continue;
        count++;
        if (seen.count < 6) [seen addObject:[NSString stringWithFormat:@"%@ on %@", key, (id)layer.delegate ?: layer]];
    }
    for (CALayer *sub in layer.sublayers) count += animationsUnder(sub, seen);
    return count;
}

// Spotify's words for Play and Pause in each language the harness runs in, as SPTStrings.bundle has them in 9.1.90 and
// 9.2.0 (encore:sEncoreAccessibilityPlay and ...Pause): what the mocked button's label carries, set apart from the lookup
// the capsule sizes itself by.
static NSString *fixtureWord(BOOL pause) {
    NSDictionary<NSString *, NSArray<NSString *> *> *words = @{
        @"en": @[@"Play", @"Pause"], @"ko": @[@"재생하기", @"일시 정지하기"], @"ru": @[@"Слушать", @"Пауза"],
    };
    NSArray<NSString *> *pair = words[sg_language];
    if (!pair) HARNESS_FAIL(@"no Play and Pause words for the language %@", sg_language);
    return pair[pause];
}

@interface ActionRowApp : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

static SGRHeaderInfo *sg_info;
static UIView *sg_header, *sg_shuffleHost, *sg_addHost;
static MockPlayButton *sg_play;
static UIButton *sg_shuffle, *sg_add;

static void feed(void) {
    [sg_info showShuffle:sg_shuffle play:sg_play trailing:sg_add trailingFallback:[UIImage systemImageNamed:@"plus"] playColor:nil];
    [sg_header layoutIfNeeded];
}

static void checkFirstPlacement(UIWindow *window) {
    // A page opening inside an animation: the info made, put in the header and placed, the whole laid out, all in the
    // animation's block.
    CGRect target = sg_header.bounds;
    [UIView animateWithDuration:2 animations:^{
        sg_info = [[SGRHeaderInfo alloc] initWithFrame:CGRectZero];
        [sg_header addSubview:sg_info];
        [sg_info showTitle:@"Album" creator:@"Artist" length:@"2026" about:nil];
        feed();
        sg_info.frame = target;
        [sg_header layoutIfNeeded];
    }];
    NSMutableArray<NSString *> *seen = [NSMutableArray array];
    NSUInteger moving = animationsUnder(sg_info.layer, seen);
    if (moving) HARNESS_FAIL(@"first placement: %lu moves animated on the row and what is in it, wanted none (it slides in from the corner): %@",
                             (unsigned long)moving, [seen componentsJoinedByString:@"; "]);
    SGRPlayCapsule *capsule = capsuleIn(sg_info);
    if (!CGRectEqualToRect(sg_info.frame, target) || capsule.bounds.size.width < 48)
        HARNESS_FAIL(@"first placement: the row at %@ with Play %@, wanted %@", NSStringFromCGRect(sg_info.frame), NSStringFromCGRect(capsule.frame), NSStringFromCGRect(target));
    NSLog(@"[harness] PASS first placement inside an animation: no animation on the row, Play at %@", NSStringFromCGRect(capsule.frame));

    // The header moves while the page opens: the row is in it, so it is where the header puts it in the same pass.
    CGRect before = [capsule convertRect:capsule.bounds toView:sg_header];
    sg_header.frame = CGRectOffset(sg_header.frame, 0, 40);
    CGRect after = [capsule convertRect:capsule.bounds toView:sg_header];
    CGRect inWindow = [capsule convertRect:capsule.bounds toView:nil];
    if (!CGRectEqualToRect(before, after) || CGRectGetMinY(inWindow) != CGRectGetMinY([sg_header convertRect:after toView:nil]))
        HARNESS_FAIL(@"anchor: Play at %@ in the header before the move, %@ after", NSStringFromCGRect(before), NSStringFromCGRect(after));
    sg_header.frame = CGRectOffset(sg_header.frame, 0, -40);
    NSLog(@"[harness] PASS the row moves with its header in the same pass");
}

// The capsule's word, when it shows one: the whole of `word`, not cut short.
static void checkWordShown(SGRPlayCapsule *capsule, NSString *word, NSString *shot) {
    UILabel *title = nil;
    for (UIView *v in capsule.subviews) if ([v isKindOfClass:UILabel.class]) title = (UILabel *)v;
    CGFloat needed = ceil([title sizeThatFits:CGSizeMake(CGFLOAT_MAX, CGFLOAT_MAX)].width);
    if (!title || title.hidden || ![title.text isEqualToString:word] || title.bounds.size.width < needed ||
        CGRectGetMinX(title.frame) < 0 || CGRectGetMaxX(title.frame) > capsule.bounds.size.width)
        HARNESS_FAIL(@"%@: the capsule %@ shows \"%@\" in %@ (hidden %d), wanted all of \"%@\" (%.0fpt) inside it", shot,
                     NSStringFromCGRect(capsule.frame), title.text, NSStringFromCGRect(title.frame), title.hidden, word, needed);
}

static void checkPlayPause(UIWindow *window, NSString *shot) {
    SGRPlayCapsule *capsule = capsuleIn(sg_info);
    NSString *playWord = fixtureWord(NO), *pauseWord = fixtureWord(YES);
    setPlaying(sg_play, NO, playWord);
    feed();
    BOOL playing = YES;
    if (!SGRPlayButtonPlaying(sg_play, &playing) || playing) HARNESS_FAIL(@"play state: paused button read as %d", playing);
    CGRect paused = capsule.frame;
    BOOL round = capsule.round;
    if (!round) checkWordShown(capsule, playWord, shot);
    if (shot) shoot(window, [shot stringByAppendingString:@"-paused"]);
    setPlaying(sg_play, YES, pauseWord);
    // Nothing is laid out by Spotify's turn; the capsule hears the glyph, and the header's next pass is the page's.
    feed();
    if (!round) checkWordShown(capsule, pauseWord, shot);
    if (!SGRPlayButtonPlaying(sg_play, &playing) || !playing) HARNESS_FAIL(@"play state: playing button read as %d", playing);
    if (!CGRectEqualToRect(capsule.frame, paused) || capsule.round != round || ![capsule.accessibilityLabel isEqualToString:pauseWord])
        HARNESS_FAIL(@"%@: Play %@ round %d paused (\"%@\"), %@ round %d playing (\"%@\"): wanted one frame", shot,
                     NSStringFromCGRect(paused), round, playWord, NSStringFromCGRect(capsule.frame), capsule.round, capsule.accessibilityLabel);
    if (shot) shoot(window, [shot stringByAppendingString:@"-playing"]);
    setPlaying(sg_play, NO, playWord);
    feed();
    if (shot) NSLog(@"[harness] PASS %@: Play %@ (round %d) for both \"%@\" and \"%@\"", shot, NSStringFromCGRect(paused), round, playWord, pauseWord);
}

// The page's side and the gap beside Play (SGRHeaderInfo.m's layout rules).
static const CGFloat kPageSide = 20, kRowGap = 16, kRowHeight = 48;

// The row laid out `width` wide; the leading button's distance from the page's side.
static CGFloat layoutAt(UIWindow *window, CGFloat width, NSString *shot) {
    sg_header.frame = CGRectMake((window.bounds.size.width - width) / 2, 120, width, 300);
    sg_info.frame = sg_header.bounds;
    feed();
    SGRPlayCapsule *capsule = capsuleIn(sg_info);
    NSArray<SGRMirrorButton *> *mirrors = mirrorsIn(sg_info);
    CGRect play = capsule.frame;
    // Both shapes: the buttons the usual gap either side of Play, in the middle, and inside the page's sides; round,
    // Play is a circle the row's height.
    if (mirrors.count != 2 || CGRectGetMinX(play) - CGRectGetMaxX(mirrors[0].frame) != kRowGap ||
        CGRectGetMinX(mirrors[1].frame) - CGRectGetMaxX(play) != kRowGap || fabs(CGRectGetMidX(play) - width / 2) > 1 ||
        (capsule.round && !CGSizeEqualToSize(play.size, CGSizeMake(kRowHeight, kRowHeight))) ||
        (!capsule.round && (CGRectGetMinX(mirrors[0].frame) < kPageSide - 1 || CGRectGetMaxX(mirrors[1].frame) > width - kPageSide + 1)))
        HARNESS_FAIL(@"%@ at %.0f: Play %@ round %d, buttons %@ %@", shot ?: @"sweep", width, NSStringFromCGRect(play), capsule.round,
                     NSStringFromCGRect(mirrors.firstObject.frame), NSStringFromCGRect(mirrors.lastObject.frame));
    return CGRectGetMinX(mirrors[0].frame) - kPageSide;
}

static void checkWidth(UIWindow *window, CGFloat width, NSString *shot) {
    layoutAt(window, width, shot);
    SGRPlayCapsule *capsule = capsuleIn(sg_info);
    NSLog(@"[harness] PASS %@ at %.0fpt: Play %@, %@", shot, width, NSStringFromCGRect(capsule.frame), capsule.round ? @"round" : @"capsule");
    checkPlayPause(window, shot);
}

// From the window's width down, a point at a time: a capsule with both words whole while one fits between the buttons at
// the page's sides, then round from the first width it would not, and round on down. At the last capsule the buttons are
// at the sides: the capsule went round no sooner than it had to. Each width also turns Play to Pause in place.
static void checkFitBoundary(UIWindow *window) {
    CGFloat lastCapsule = 0, firstRound = 0, slack = 0;
    for (CGFloat width = window.bounds.size.width; width >= 260; width--) {
        CGFloat side = layoutAt(window, width, nil);
        checkPlayPause(window, nil);
        BOOL round = capsuleIn(sg_info).round;
        if (round && !firstRound) firstRound = width;
        if (!round && firstRound) HARNESS_FAIL(@"fit: a capsule again at %.0f, below the round Play from %.0f", width, firstRound);
        if (!round) {
            lastCapsule = width;
            slack = side;
        }
    }
    if (!firstRound || !lastCapsule || slack > 1)
        HARNESS_FAIL(@"fit: last capsule at %.0f with its buttons %.1fpt in from the sides, round from %.0f", lastCapsule, slack, firstRound);
    NSLog(@"[harness] PASS fit: \"%@\" and \"%@\" whole in a capsule down to %.0fpt (buttons %.1fpt in from the sides), round from %.0fpt",
          fixtureWord(NO), fixtureWord(YES), lastCapsule, slack, firstRound);
}

// The saved disc as drawn into the add button's glyph, read back: whether it is clear in the corner and just outside the
// disc's edge, the color just inside that edge (copied out of the bitmap), and how many dark pixels the check has.
typedef struct {
    BOOL clear, edgeClear;
    uint8_t edge[4];
    NSUInteger dark;
} SavedDisc;

static SavedDisc readSavedDisc(SGRMirrorButton *add) {
    UIImageView *glyph = nil;
    for (UIView *v in add.subviews) if ([v isKindOfClass:UIImageView.class] && !v.hidden) glyph = (UIImageView *)v;
    UIImage *image = glyph.image;
    if (!image || image.isSymbolImage || !CGSizeEqualToSize(image.size, CGSizeMake(24, 24)) || !CGSizeEqualToSize(glyph.bounds.size, CGSizeMake(24, 24)))
        HARNESS_FAIL(@"saved: the add button shows %@ (symbol %d) in %@, wanted the 24pt canvas with the 22pt disc", image, image.isSymbolImage, NSStringFromCGRect(glyph.frame));
    CGFloat scale = image.scale;
    size_t w = (size_t)(24 * scale), h = w;
    uint8_t *pixels = calloc(w * h * 4, 1);
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(pixels, w, h, 8, w * 4, space, (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
    CGContextDrawImage(context, CGRectMake(0, 0, w, h), image.CGImage);
    uint8_t *(^at)(CGFloat, CGFloat) = ^uint8_t *(CGFloat x, CGFloat y) { return pixels + ((size_t)(y * scale) * w + (size_t)(x * scale)) * 4; };
    SavedDisc disc = {.clear = at(0.5, 0.5)[3] == 0};
    memcpy(disc.edge, at(2, 12), sizeof disc.edge);
    for (CGFloat y = 7; y < 17; y += 0.5) for (CGFloat x = 7; x < 17; x += 0.5) { uint8_t *p = at(x, y); if (p[3] == 255 && p[0] < 40 && p[1] < 40 && p[2] < 40) disc.dark++; }
    // Outside the disc: 0.5pt in from x = 1, the disc's edge, is still inside it; 0.5pt out of it is clear.
    disc.edgeClear = at(0.4, 12)[3] < 128 && at(1.6, 12)[3] > 128;
    CGContextRelease(context);
    CGColorSpaceRelease(space);
    free(pixels);
    return disc;
}

// A 22pt disc in `rgb` (0xRRGGBB) with a dark check.
static void checkSavedDisc(SGRMirrorButton *add, NSInteger rgb, NSString *shot) {
    SavedDisc disc = readSavedDisc(add);
    int want[] = {(int)(rgb >> 16) & 255, (int)(rgb >> 8) & 255, (int)rgb & 255};
    BOOL color = disc.edge[3] == 255;
    for (int i = 0; i < 3; i++) color = color && abs(disc.edge[i] - want[i]) <= 2;
    if (!disc.clear || !color || !disc.dark || !disc.edgeClear)
        HARNESS_FAIL(@"%@: corner clear %d, the edge %d %d %d, wanted %06lX, dark check pixels %lu, disc edge at 1pt %d", shot,
                     disc.clear, disc.edge[0], disc.edge[1], disc.edge[2], (long)rgb, (unsigned long)disc.dark, disc.edgeClear);
    NSLog(@"[harness] PASS %@: a 22pt %06lX disc with a dark check (%lu dark pixels)", shot, (long)rgb, (unsigned long)disc.dark);
}

// Saved in Spotify's green, then in another accent picked while it stays saved: the disc is drawn again in it.
static void checkSaved(UIWindow *window) {
    SGRMirrorButton *add = mirrorsIn(sg_info).lastObject;
    harnessAccent = nil;
    setAddTo(1);
    feed();
    checkSavedDisc(add, 0x1ED760, @"saved");
    shoot(window, @"saved");
    harnessAccent = [UIColor colorWithRed:0xE9 / 255.0 green:0x1E / 255.0 blue:0x63 / 255.0 alpha:1];
    feed();
    checkSavedDisc(add, 0xE91E63, @"saved-accent");
    shoot(window, @"saved-accent");
    harnessAccent = nil;
    setAddTo(0);
    feed();
}

// The artist page's hold reads whether Spotify is playing: from the button's own state, whatever its label says.
static void checkHold(UIWindow *window) {
    SGRPlayCapsule *capsule = capsuleIn(sg_info);
    SGRArtistHold *hold = [SGRArtistHold new];
    [capsule addGestureRecognizer:hold];
    hold.header = sg_header;
    hold.play = sg_play;
    hold.shuffle = sg_shuffle;
    hold.artist = @"Artist";
    sg_shuffle.accessibilityValue = [SGRSpotifyControlWords()[@"ShuffleButtonOff"] anyObject];
    sg_play->isPlaying = YES;
    // A label in no language Spotify's strings carry, as one the app shows in a language it was not read in.
    sg_condensed.accessibilityLabel = @"—";
    sg_play.accessibilityLabel = @"—";
    BOOL on = YES, playing = NO;
    if (![hold readShuffleOn:&on playing:&playing] || on || !playing)
        HARNESS_FAIL(@"hold: read shuffle on %d playing %d, wanted off and playing from the button's state", on, playing);
    sg_play->isPlaying = NO;
    if (![hold readShuffleOn:&on playing:&playing] || playing) HARNESS_FAIL(@"hold: paused button read as playing");
    // Another view than Spotify's play button has no such state.
    UIView *other = [UIView new];
    BOOL unknown = NO;
    if (SGRPlayButtonPlaying(other, &unknown)) HARNESS_FAIL(@"play state: a plain view was read as a play button");
    [capsule removeGestureRecognizer:hold];
    sg_play.accessibilityLabel = nil;
    NSLog(@"[harness] PASS the artist hold reads playing from isPlaying, not the label");
}

@implementation ActionRowApp
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController = [UIViewController new];
    self.window.backgroundColor = UIColor.blackColor;
    self.window.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    sg_shots = getenv("HARNESS_SHOTS");
    if (sg_shots && !*sg_shots) sg_shots = NULL;
    sg_language = NSBundle.mainBundle.preferredLocalizations.firstObject;
    __block id key = [NSNotificationCenter.defaultCenter addObserverForName:UIWindowDidBecomeKeyNotification
        object:self.window queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
        [NSNotificationCenter.defaultCenter removeObserver:key];
        [self run];
    }];
    return YES;
}

- (void)run {
    UIWindow *window = self.window;
    if (!SGRSpotifyControlWords()[@"AccessibilityPause"].count) HARNESS_FAIL(@"Spotify's words: none read from SPTStrings.bundle");
    NSLog(@"[harness] language %@: Play %@, Pause %@", sg_language, SGRSpotifyControlWords()[@"AccessibilityPlay"], SGRSpotifyControlWords()[@"AccessibilityPause"]);
    sg_header = [[UIView alloc] initWithFrame:CGRectMake(0, 120, window.bounds.size.width, 300)];
    sg_header.backgroundColor = UIColor.blackColor;
    [window addSubview:sg_header];
    // Spotify's own buttons, in the header and concealed, as the pages leave them.
    UIView *sources = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 200, 48)];
    sources.hidden = YES;
    [sg_header addSubview:sources];
    sg_play = mockPlayButton(sources, fixtureWord(NO));
    sg_shuffleHost = [[UIView alloc] initWithFrame:CGRectMake(60, 0, 48, 48)];
    [sources addSubview:sg_shuffleHost];
    sg_shuffle = [[UIButton alloc] initWithFrame:sg_shuffleHost.bounds];
    sg_shuffle.accessibilityIdentifier = @"Components.UI.ShuffleButton";
    [sg_shuffleHost addSubview:sg_shuffle];
    mockShuffleGlyph(sg_shuffle);
    sg_addHost = [[UIView alloc] initWithFrame:CGRectMake(120, 0, 48, 48)];
    [sources addSubview:sg_addHost];
    sg_add = mockAddToButton(sg_addHost);

    checkFirstPlacement(window);
    // The settled pass after the animation, then the states, each drawn.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        shoot(window, @"first-placement");
        checkWidth(window, window.bounds.size.width, @"wide");
        // 316pt leaves Play 148pt: Korean's longer Pause does not fit, English's and Russian's do. 300pt fits none.
        checkWidth(window, 316, @"narrow");
        checkWidth(window, 300, @"narrower");
        checkWidth(window, window.bounds.size.width, @"wide-again");
        checkFitBoundary(window);
        checkWidth(window, window.bounds.size.width, @"wide-last");
        checkSaved(window);
        checkHold(window);
        printf("[harness] action-row %s: all checks passed\n", sg_language.UTF8String);
        fflush(stdout);
        exit(0);
    });
}
@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(ActionRowApp.class));
    }
}
