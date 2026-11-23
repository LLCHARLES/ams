// The artist's cut-out round Play (Kit/SGRActionRow.h, SGRPlayCapsule's cutOut; Kit/SGRHeaderInfo.m, which turns it on
// for round Play only) and the Artists page's preview of it (Artist/ArtistSettings.m), drawn by real UIKit in a Mac
// Catalyst window over a striped background and read back pixel by pixel. cutout-check.sh launches it three times:
//
//     off      no setting: round Play and the album's capsule paint their glyph as before, with no mask
//     on       -spotifyglass.redesign.artist.cutOutPlay YES (and roundPlay YES for the preview): round Play is cut out
//              of white, the album's capsule is not; plus every case of the capsule itself
//     accent   ... and -spotifyglass.redesign.accentPlay YES: cut out of the accent, which follows a change of it
//
// A cut is read against two drawings of the same place: the background alone, and the button painted (cut-out off,
// its glyph in a color of the check's own). Where the glyph was painted the cut must show the background, stripe for
// stripe, and where the fill was it must show the fill. `baseline` only writes the PNGs of the drawings the cut-out
// must leave alone, for a comparison against another build. With CUTOUT_PNG set, every drawing checked is written
// there. Exits nonzero on the first failure (../harness-fail.h).
#import <UIKit/UIKit.h>
#import "../harness-fail.h"
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Redesigned/Kit/SGRActionRow.h"
#import "Redesigned/Kit/SGRHeaderInfo.h"
#import "Redesigned/Kit/SGRPagePreview.h"
#import "Redesigned/Kit/SGRTokens.h"
#import "Redesigned/Artist/Artist.h"

#pragma mark - what the check does not compile

// The accent hook (SGRAccent.x): the check's own accent, which it changes.
static UIColor *sgh_accent;
UIColor *SGRAccentColor(void) { return sgh_accent; }
BOOL SGMotionAppleMusicOn(void) { return YES; }
// Shared/AlbumQueue: the album's ⋯ records its album; no menu here.
void SGAlbumQueueMarkSource(UIView *view) {}
// Shared/Player/SGLastTrack.m, which brings the player: the card's placeholder art, a square of the color.
UIImage *SGPlaceholderArtwork(UIColor *tint) {
    return [[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(64, 64)] imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [tint setFill];
        UIRectFill(CGRectMake(0, 0, 64, 64));
    }];
}

#pragma mark - pixels

static const CGFloat kScale = 2;

@interface Shot : NSObject
@property (nonatomic, strong) NSMutableData *data;
@property (nonatomic) size_t width, height;
@end
@implementation Shot
- (const uint8_t *)at:(size_t)x y:(size_t)y {
    return (const uint8_t *)self.data.bytes + (y * self.width + x) * 4;
}
@end

static NSString *sgh_mode;

static Shot *shoot(UIView *view, NSString *name) {
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat preferredFormat];
    format.scale = kScale;
    format.opaque = YES;
    UIImage *image = [[[UIGraphicsImageRenderer alloc] initWithBounds:view.bounds format:format] imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [view drawViewHierarchyInRect:view.bounds afterScreenUpdates:YES];
    }];
    NSString *dir = NSProcessInfo.processInfo.environment[@"CUTOUT_PNG"];
    if (dir.length && name) {
        NSString *path = [dir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@-%@.png", name, sgh_mode]];
        if (![UIImagePNGRepresentation(image) writeToFile:path atomically:YES]) HARNESS_FAIL(@"could not write %@", path);
    }
    Shot *shot = [Shot new];
    CGImageRef cg = image.CGImage;
    shot.width = CGImageGetWidth(cg);
    shot.height = CGImageGetHeight(cg);
    shot.data = [NSMutableData dataWithLength:shot.width * shot.height * 4];
    CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGContextRef context = CGBitmapContextCreate(shot.data.mutableBytes, shot.width, shot.height, 8, shot.width * 4, space,
                                                 kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGContextDrawImage(context, CGRectMake(0, 0, shot.width, shot.height), cg);
    CGContextRelease(context);
    CGColorSpaceRelease(space);
    return shot;
}

typedef struct { CGFloat r, g, b; } RGB;

static RGB rgbOf(UIColor *color) {
    CGFloat r, g, b, a;
    if (![color getRed:&r green:&g blue:&b alpha:&a]) HARNESS_FAIL(@"no RGB in %@", color);
    return (RGB){r * 255, g * 255, b * 255};
}

static RGB rgbAt(const uint8_t *p) {
    return (RGB){p[0], p[1], p[2]};
}

static BOOL near(RGB a, RGB b, CGFloat tolerance) {
    return fabs(a.r - b.r) <= tolerance && fabs(a.g - b.g) <= tolerance && fabs(a.b - b.b) <= tolerance;
}

static RGB over(RGB top, CGFloat alpha, RGB under) {
    return (RGB){top.r * alpha + under.r * (1 - alpha), top.g * alpha + under.g * (1 - alpha), top.b * alpha + under.b * (1 - alpha)};
}

static BOOL sameShot(Shot *a, Shot *b, CGFloat tolerance) {
    if (a.width != b.width || a.height != b.height) return NO;
    for (size_t y = 0; y < a.height; y++) for (size_t x = 0; x < a.width; x++) {
        if (!near(rgbAt([a at:x y:y]), rgbAt([b at:x y:y]), tolerance)) return NO;
    }
    return YES;
}

#pragma mark - Spotify's play button

// Spotify's play button as the capsule reads it: a control named by its word, holding its glyph in an image view its
// own size (as ../artist/main.m builds it), which counts what fires it.
@interface MockPlayButton : UIControl
@property (nonatomic) NSUInteger fired;
@property (nonatomic, strong) UIImageView *disc;
@end

@implementation MockPlayButton
- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.accessibilityLabel = @"Play";
    _disc = [[UIImageView alloc] initWithFrame:self.bounds];
    _disc.contentMode = UIViewContentModeCenter;
    [self addSubview:_disc];
    [self addTarget:self action:@selector(fire) forControlEvents:UIControlEventTouchUpInside];
    return self;
}
- (void)fire {
    self.fired++;
}
@end

static UIWindow *sgh_window;

// Off screen in the window, as Spotify's concealed button is under the redesign's.
static MockPlayButton *spotifyPlay(UIImage *glyph) {
    UIView *source = [[UIView alloc] initWithFrame:CGRectMake(-200, 0, 48, 48)];
    MockPlayButton *button = [[MockPlayButton alloc] initWithFrame:source.bounds];
    button.disc.image = glyph;
    [source addSubview:button];
    [sgh_window addSubview:source];
    return button;
}

// The play symbol a size Spotify's triangle is, drawn at its own size (UIViewContentModeCenter in the capsule).
static UIImage *playSymbol(void) {
    return [UIImage systemImageNamed:@"play.fill" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:24]];
}

// Pause as Spotify draws it: the bars small in the middle of a 48pt canvas, which the capsule fits to its glyph's
// frame (UIViewContentModeScaleAspectFit).
static UIImage *pauseCanvas(void) {
    return [[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(48, 48)] imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [UIColor.blackColor setFill];
        UIRectFill(CGRectMake(14, 12, 7, 24));
        UIRectFill(CGRectMake(27, 12, 7, 24));
    }];
}

#pragma mark - the stage

// Stripes 3pt wide in four colors, slanted, so what shows through a hole is the background's own pixels and differs
// from place to place.
static UIView *stage(CGRect frame) {
    UIView *stage = [[UIView alloc] initWithFrame:frame];
    UIImage *stripes = [[[UIGraphicsImageRenderer alloc] initWithSize:frame.size] imageWithActions:^(UIGraphicsImageRendererContext *context) {
        NSArray<UIColor *> *colors = @[[UIColor colorWithRed:0.9 green:0.2 blue:0.1 alpha:1], [UIColor colorWithRed:0.1 green:0.3 blue:0.9 alpha:1],
                                       [UIColor colorWithRed:0.95 green:0.85 blue:0.1 alpha:1], [UIColor colorWithRed:0.05 green:0.05 blue:0.05 alpha:1]];
        CGFloat span = frame.size.width + frame.size.height;
        for (NSInteger i = 0; i * 3 < span; i++) {
            [colors[i % colors.count] setFill];
            UIBezierPath *band = [UIBezierPath bezierPath];
            [band moveToPoint:CGPointMake(i * 3, 0)];
            [band addLineToPoint:CGPointMake(i * 3 + 3, 0)];
            [band addLineToPoint:CGPointMake(i * 3 + 3 - frame.size.height, frame.size.height)];
            [band addLineToPoint:CGPointMake(i * 3 - frame.size.height, frame.size.height)];
            [band fill];
        }
    }];
    UIImageView *background = [[UIImageView alloc] initWithImage:stripes];
    background.frame = stage.bounds;
    [stage addSubview:background];
    [sgh_window addSubview:stage];
    return stage;
}

// The stage without `button`.
static Shot *backgroundOf(UIView *stage, UIView *button, NSString *name) {
    button.hidden = YES;
    Shot *shot = shoot(stage, name);
    button.hidden = NO;
    return shot;
}

static UIColor *magenta(void) {
    return [UIColor colorWithRed:1 green:0 blue:1 alpha:1];
}

// The cut of `button` (in `stage`), against `background` and `painted`, the button drawn with its glyph and word in
// `ink` over `paint` (cut-out off). Where `ink` was, the background's pixels; where `paint` was, inside the shape,
// `fill` at `alpha` over the background; outside the shape, the background.
static void expectCut(NSString *name, UIView *stage, UIView *button, Shot *background, Shot *painted, RGB ink, RGB paint,
                      UIColor *fill, CGFloat alpha) {
    Shot *cut = shoot(stage, name);
    CGRect frame = [button convertRect:button.bounds toView:stage];
    CGFloat radius = MIN(frame.size.width, frame.size.height) / 2;
    UIBezierPath *inside = [UIBezierPath bezierPathWithRoundedRect:CGRectInset(frame, 1.5, 1.5) cornerRadius:radius - 1.5];
    UIBezierPath *edge = [UIBezierPath bezierPathWithRoundedRect:CGRectInset(frame, -1.5, -1.5) cornerRadius:radius + 1.5];
    RGB filled = rgbOf(fill);
    NSUInteger glyph = 0, hole = 0, ring = 0, ringRight = 0, outside = 0, outsideRight = 0;
    NSMutableSet<NSNumber *> *showing = [NSMutableSet set];
    for (size_t y = 0; y < cut.height; y++) for (size_t x = 0; x < cut.width; x++) {
        CGPoint point = CGPointMake((x + 0.5) / kScale, (y + 0.5) / kScale);
        RGB was = rgbAt([painted at:x y:y]), now = rgbAt([cut at:x y:y]), under = rgbAt([background at:x y:y]);
        if (![edge containsPoint:point]) {
            outside++;
            if (near(now, under, 3)) outsideRight++;
        } else if (near(was, ink, 8)) {
            glyph++;
            if (near(now, under, 12)) {
                hole++;
                [showing addObject:@(((int)under.r / 32) << 10 | ((int)under.g / 32) << 5 | (int)under.b / 32)];
            }
        } else if (near(was, paint, 3) && [inside containsPoint:point]) {
            ring++;
            if (near(now, over(filled, alpha, under), 6)) ringRight++;
        }
    }
    if (glyph < 40 || hole < glyph * 0.97)
        HARNESS_FAIL(@"%@: %lu of %lu glyph pixels show the background", name, (unsigned long)hole, (unsigned long)glyph);
    if (showing.count < 2) HARNESS_FAIL(@"%@: the hole shows one color, not the stripes behind it", name);
    if (ring < 500 || ringRight < ring * 0.98)
        HARNESS_FAIL(@"%@: %lu of %lu fill pixels are %@ at %.1f", name, (unsigned long)ringRight, (unsigned long)ring, fill, alpha);
    if (outsideRight < outside * 0.999) HARNESS_FAIL(@"%@: the button drew outside its shape", name);
    NSLog(@"[harness] PASS %@: %lu glyph pixels show the stripes behind, %lu fill pixels %@", name, (unsigned long)glyph,
          (unsigned long)ring, alpha < 1 ? @"dimmed" : @"filled");
}

static UIImageView *glyphOf(SGRPlayCapsule *play) {
    return [play valueForKey:@"_glyph"];
}

static UILabel *wordOf(SGRPlayCapsule *play) {
    return [play valueForKey:@"_title"];
}

// The capsule painted, its glyph in `ink`: cut-out off, drawn, and on again.
static Shot *paintedOf(UIView *stage, SGRPlayCapsule *play, NSString *name) {
    play.cutOut = NO;
    [stage layoutIfNeeded];
    if (play.layer.mask || glyphOf(play).alpha != 1) HARNESS_FAIL(@"%@: off, the cut stayed (mask %@, glyph alpha %.2f)", name, play.layer.mask, glyphOf(play).alpha);
    Shot *shot = shoot(stage, name);
    play.cutOut = YES;
    [stage layoutIfNeeded];
    if (!play.layer.mask || glyphOf(play).alpha != 0) HARNESS_FAIL(@"%@: on again, no cut", name);
    return shot;
}

static void layOut(UIView *stage) {
    [stage setNeedsLayout];
    [stage layoutIfNeeded];
}

#pragma mark - the capsule

static void checkCapsule(void) {
    UIColor *white = UIColor.whiteColor, *orange = [UIColor colorWithRed:1 green:0.55 blue:0 alpha:1];
    RGB ink = rgbOf(magenta()), paper = rgbOf(white);
    UIView *round = stage(CGRectMake(20, 40, 240, 120));
    MockPlayButton *spotify = spotifyPlay(playSymbol());
    UIView *source = spotify.superview;
    SGRPlayCapsule *play = [[SGRPlayCapsule alloc] initWithFrame:CGRectMake(88, 28, 64, 64)];
    play.fillColor = white;
    play.contentColor = magenta();
    play.round = YES;
    [round addSubview:play];
    [play feedFrom:source];
    [round layoutIfNeeded];
    Shot *background = backgroundOf(round, play, @"capsule-background");
    Shot *painted = shoot(round, @"round-painted");
    if (play.layer.mask) HARNESS_FAIL(@"a mask with cut-out off");
    NSString *label = play.accessibilityLabel;
    UIAccessibilityTraits traits = play.accessibilityTraits;
    CGPoint activation = play.accessibilityActivationPoint;
    NSUInteger before = spotify.fired;
    BOOL activates = [play accessibilityActivate];
    NSUInteger activateFires = spotify.fired - before;

    // Play, cut out of white.
    play.cutOut = YES;
    [round layoutIfNeeded];
    if (!play.layer.mask || glyphOf(play).alpha != 0) HARNESS_FAIL(@"cut-out on: no mask, or the glyph still painted");
    expectCut(@"round Play cut out of white", round, play, background, painted, ink, paper, white, 1);

    // Nothing changed: the same mask, not drawn again.
    id contents = play.layer.mask.contents;
    layOut(play);
    [play feedFrom:source];
    layOut(round);
    if (play.layer.mask.contents != contents) HARNESS_FAIL(@"the mask was drawn again with nothing changed");
    NSLog(@"[harness] PASS a pass with nothing changed keeps the mask");

    // Another fill: the ring takes it, the mask (alpha alone) is kept.
    play.fillColor = orange;
    [round layoutIfNeeded];
    if (play.layer.mask.contents != contents) HARNESS_FAIL(@"a new fill drew the mask again");
    expectCut(@"round Play cut out of the accent", round, play, background, painted, ink, paper, orange, 1);
    play.fillColor = white;
    [round layoutIfNeeded];

    // Spotify turns Play into Pause with no pass of the header: the capsule hears the image and cuts the bars.
    spotify.disc.image = pauseCanvas();
    [round layoutIfNeeded];
    if (play.layer.mask.contents == contents) HARNESS_FAIL(@"Play turned Pause, the mask kept Play");
    if (glyphOf(play).contentMode != UIViewContentModeScaleAspectFit) HARNESS_FAIL(@"Pause's canvas is not fitted");
    expectCut(@"Pause cut out", round, play, background, paintedOf(round, play, @"pause-painted"), ink, paper, white, 1);

    // Back to Play, then off: the painted capsule exactly as before the cut.
    spotify.disc.image = playSymbol();
    [round layoutIfNeeded];
    play.cutOut = NO;
    [round layoutIfNeeded];
    if (play.layer.mask || glyphOf(play).alpha != 1) HARNESS_FAIL(@"off: the mask stayed or the glyph is not painted");
    if (!sameShot(painted, shoot(round, @"round-off-again"), 1)) HARNESS_FAIL(@"off again, the capsule does not draw as it did");
    NSLog(@"[harness] PASS turned off, the mask goes and the capsule draws as before");
    play.cutOut = YES;
    [round layoutIfNeeded];

    // Another size: drawn again for it.
    contents = play.layer.mask.contents;
    play.frame = CGRectMake(92, 32, 56, 56);
    [round layoutIfNeeded];
    if (play.layer.mask.contents == contents) HARNESS_FAIL(@"a new size kept the old mask");
    Shot *painted56 = paintedOf(round, play, @"round56-painted");
    expectCut(@"round Play at 56pt", round, play, background, painted56, ink, paper, white, 1);

    // Disabled: no tap reaches Spotify, and the cut fill dims as a painted glyph would; enabled again (a tap reads the
    // source first), both come back.
    NSUInteger fired = spotify.fired;
    spotify.enabled = NO;
    [play feedFrom:source];
    [round layoutIfNeeded];
    if (!(play.accessibilityTraits & UIAccessibilityTraitNotEnabled)) HARNESS_FAIL(@"disabled source, enabled trait");
    [play sendActionsForControlEvents:UIControlEventTouchUpInside];
    if (spotify.fired != fired) HARNESS_FAIL(@"a disabled source was fired");
    expectCut(@"disabled round Play", round, play, background, painted56, ink, paper, white, 0.4);
    spotify.enabled = YES;
    [play sendActionsForControlEvents:UIControlEventTouchUpInside];
    if (spotify.fired != fired + 1) HARNESS_FAIL(@"enabled again, the tap did not reach Spotify");
    expectCut(@"enabled again", round, play, background, painted56, ink, paper, white, 1);

    // VoiceOver: the same element, name, traits and activation point as painted, the point on the capsule, and the
    // tap there reaching Spotify; pressed, the capsule still shrinks.
    play.frame = CGRectMake(88, 28, 64, 64);
    play.cutOut = NO;
    [round layoutIfNeeded];
    label = play.accessibilityLabel;
    traits = play.accessibilityTraits;
    activation = play.accessibilityActivationPoint;
    play.cutOut = YES;
    [round layoutIfNeeded];
    if (!play.isAccessibilityElement || ![play.accessibilityLabel isEqualToString:label] || play.accessibilityTraits != traits
        || !CGPointEqualToPoint(play.accessibilityActivationPoint, activation))
        HARNESS_FAIL(@"VoiceOver reads %@ %llu at %@, not %@ %llu at %@", play.accessibilityLabel, play.accessibilityTraits,
                     NSStringFromCGPoint(play.accessibilityActivationPoint), label, traits, NSStringFromCGPoint(activation));
    // VoiceOver activates as it did the painted capsule, and where it then taps, the middle (the hole), the capsule
    // takes the touch and fires Spotify's Play.
    fired = spotify.fired;
    if ([play accessibilityActivate] != activates || spotify.fired - fired != activateFires)
        HARNESS_FAIL(@"VoiceOver's activation differs from the painted capsule's");
    CGPoint middle = CGPointMake(CGRectGetMidX(play.bounds), CGRectGetMidY(play.bounds));
    if ([sgh_window hitTest:[play convertPoint:middle toView:sgh_window] withEvent:nil] != play) HARNESS_FAIL(@"the hole does not take a touch");
    fired = spotify.fired;
    [play sendActionsForControlEvents:UIControlEventTouchUpInside];
    if (spotify.fired != fired + 1) HARNESS_FAIL(@"activated, Spotify's Play did not fire");
    [play sendActionsForControlEvents:UIControlEventTouchDown];
    if (CGAffineTransformIsIdentity(play.transform) || !play.layer.mask) HARNESS_FAIL(@"pressed, the cut capsule does not shrink");
    [play sendActionsForControlEvents:UIControlEventTouchCancel];
    if (!CGAffineTransformIsIdentity(play.transform)) HARNESS_FAIL(@"released, the capsule stays small");
    NSLog(@"[harness] PASS VoiceOver reads and activates \"%@\" as painted, and a press still shows", label);

    // The capsule with its word (the album's and the playlist's shape): the word is cut out too, and drawn again for a
    // new font.
    UIView *wide = stage(CGRectMake(20, 180, 240, 100));
    SGRPlayCapsule *word = [[SGRPlayCapsule alloc] initWithFrame:CGRectMake(40, 26, 160, 48)];
    word.fillColor = white;
    word.contentColor = magenta();
    [wide addSubview:word];
    [word feedFrom:source];
    [wide layoutIfNeeded];
    if (wordOf(word).hidden || ![wordOf(word).text isEqualToString:@"Play"]) HARNESS_FAIL(@"the capsule shows no word");
    Shot *wideBackground = backgroundOf(wide, word, @"word-background");
    word.cutOut = YES;
    [wide layoutIfNeeded];
    expectCut(@"capsule with its word cut out", wide, word, wideBackground, paintedOf(wide, word, @"word-painted"), ink, paper, white, 1);
    contents = word.layer.mask.contents;
    wordOf(word).font = [UIFont systemFontOfSize:22 weight:UIFontWeightHeavy];
    layOut(word);
    if (word.layer.mask.contents == contents) HARNESS_FAIL(@"a new font kept the old cut");
    expectCut(@"word in a new font", wide, word, wideBackground, paintedOf(wide, word, @"word-font-painted"), ink, paper, white, 1);

    // No glyph yet: the whole circle filled; the glyph once Spotify has one.
    UIView *empty = stage(CGRectMake(20, 300, 240, 120));
    MockPlayButton *late = spotifyPlay(nil);
    SGRPlayCapsule *missing = [[SGRPlayCapsule alloc] initWithFrame:CGRectMake(88, 28, 64, 64)];
    missing.fillColor = white;
    missing.contentColor = magenta();
    missing.round = YES;
    missing.cutOut = YES;
    [empty addSubview:missing];
    [missing feedFrom:late.superview];
    [empty layoutIfNeeded];
    if (!missing.layer.mask) HARNESS_FAIL(@"no glyph: no mask");
    Shot *emptyBackground = backgroundOf(empty, missing, nil);
    Shot *whole = shoot(empty, @"missing-glyph");
    UIBezierPath *circle = [UIBezierPath bezierPathWithOvalInRect:CGRectInset(missing.frame, 1.5, 1.5)];
    NSUInteger inside = 0, white_ = 0;
    for (size_t y = 0; y < whole.height; y++) for (size_t x = 0; x < whole.width; x++) {
        if (![circle containsPoint:CGPointMake((x + 0.5) / kScale, (y + 0.5) / kScale)]) continue;
        inside++;
        if (near(rgbAt([whole at:x y:y]), paper, 3)) white_++;
    }
    if (inside < 1000 || white_ != inside) HARNESS_FAIL(@"no glyph: %lu of %lu pixels of the circle white", (unsigned long)white_, (unsigned long)inside);
    late.disc.image = playSymbol();
    [missing feedFrom:late.superview];
    [empty layoutIfNeeded];
    expectCut(@"glyph arriving late", empty, missing, emptyBackground, paintedOf(empty, missing, nil), ink, paper, white, 1);

    for (UIView *view in @[round, wide, empty, source, late.superview]) [view removeFromSuperview];
}

#pragma mark - the header

// What SGRHeaderInfo makes of the settings: round Play cut out with cut-out on, in the accent with accent Play on, and
// the album's capsule (not round) painted whatever they are.
static void checkHeader(BOOL baseline) {
    BOOL cut = SGFlag(SGRKeyArtistCutOutPlay, NO), accent = SGFlag(SGRKeyAccentPlay, NO);
    UIColor *page = [UIColor colorWithRed:0.1 green:0.6 blue:0.55 alpha:1];
    sgh_accent = [UIColor colorWithRed:1 green:0.55 blue:0 alpha:1];
    MockPlayButton *spotify = spotifyPlay(playSymbol());

    UIView *albumStage = stage(CGRectMake(20, 40, 390, 140));
    SGRHeaderInfo *album = [[SGRHeaderInfo alloc] initWithFrame:albumStage.bounds];
    [albumStage addSubview:album];
    [album showShuffle:nil play:spotify.superview trailing:nil trailingFallback:nil playColor:page];
    [album layoutIfNeeded];
    SGRPlayCapsule *capsule = [album valueForKey:@"play"];
    shoot(albumStage, @"album-capsule");

    UIView *roundStage = stage(CGRectMake(20, 200, 390, 140));
    SGRHeaderInfo *info = [[SGRHeaderInfo alloc] initWithFrame:roundStage.bounds];
    info.roundPlay = YES;
    [roundStage addSubview:info];
    [info showShuffle:nil play:spotify.superview trailing:nil trailingFallback:nil playColor:page];
    [info layoutIfNeeded];
    SGRPlayCapsule *play = [info valueForKey:@"play"];
    shoot(roundStage, @"round-play");
    if (baseline) {
        NSLog(@"[harness] PASS baseline drawn");
        return;
    }

    if (capsule.cutOut || capsule.layer.mask) HARNESS_FAIL(@"the album's capsule is cut out");
    if (![capsule.fillColor isEqual:UIColor.whiteColor] || wordOf(capsule).hidden || wordOf(capsule).alpha != 1 || glyphOf(capsule).alpha != 1
        || ![glyphOf(capsule).tintColor isEqual:page] || ![wordOf(capsule).textColor isEqual:page])
        HARNESS_FAIL(@"the album's capsule is not white with its glyph and word in the page's color");
    NSLog(@"[harness] PASS the album's capsule stays white, painted in the page's color");

    if (play.cutOut != cut) HARNESS_FAIL(@"round Play cut out %d with the setting %d", play.cutOut, cut);
    if (!cut) {
        if (play.layer.mask || ![play.fillColor isEqual:UIColor.whiteColor] || glyphOf(play).alpha != 1 || ![glyphOf(play).tintColor isEqual:page])
            HARNESS_FAIL(@"cut-out off: round Play is not white with its glyph in the page's color");
        NSLog(@"[harness] PASS cut-out off: round Play white, its glyph painted in the page's color");
    } else {
        UIColor *fill = accent ? sgh_accent : UIColor.whiteColor;
        if (![play.fillColor isEqual:fill]) HARNESS_FAIL(@"round Play's fill %@, not %@", play.fillColor, fill);
        Shot *background = backgroundOf(roundStage, play, nil);
        play.cutOut = NO;
        [info layoutIfNeeded];
        Shot *painted = shoot(roundStage, nil);
        play.cutOut = YES;
        [info layoutIfNeeded];
        RGB ink = rgbOf(page);
        expectCut(accent ? @"artist header: round Play cut out of the accent" : @"artist header: round Play cut out of white", roundStage, play,
                  background, painted, ink, rgbOf(fill), fill, 1);
        if (accent) {
            // The accent moves (Automatic, with the page): the next pass of the header takes it, the mask kept.
            id contents = play.layer.mask.contents;
            sgh_accent = [UIColor colorWithRed:0.55 green:0.2 blue:0.95 alpha:1];
            [info showShuffle:nil play:spotify.superview trailing:nil trailingFallback:nil playColor:page];
            [info layoutIfNeeded];
            if (![play.fillColor isEqual:sgh_accent] || play.layer.mask.contents != contents)
                HARNESS_FAIL(@"a new accent: fill %@, mask kept %d", play.fillColor, play.layer.mask.contents == contents);
            expectCut(@"artist header: round Play in the new accent", roundStage, play, background, painted, ink, rgbOf(fill), sgh_accent, 1);
        }
    }
    for (UIView *view in @[albumStage, roundStage, spotify.superview]) [view removeFromSuperview];
}

#pragma mark - the Artists page

static UIView *withIdentifier(UIView *view, NSString *identifier) {
    if ([view.accessibilityIdentifier isEqualToString:identifier]) return view;
    for (UIView *sub in view.subviews) {
        UIView *found = withIdentifier(sub, identifier);
        if (found) return found;
    }
    return nil;
}

static SGRPagePreview *cardIn(UIView *view) {
    if ([view isKindOfClass:SGRPagePreview.class]) return (SGRPagePreview *)view;
    for (UIView *sub in view.subviews) {
        SGRPagePreview *card = cardIn(sub);
        if (card) return card;
    }
    return nil;
}

static SGModRow *rowWithKey(SGModPage *page, NSString *key) {
    for (SGModSection *section in page.sections) for (SGModRow *row in section.rows) if ([row.key isEqualToString:key]) return row;
    return nil;
}

// The rows, and the card: its Play cut out of white or the accent while round Play and cut-out are on, the page's
// field showing through the triangle; its own white Play otherwise.
static void checkSettings(UINavigationController *nav) {
    BOOL shown = SGFlag(SGRKeyArtistRoundPlay, NO) && SGFlag(SGRKeyArtistCutOutPlay, NO);
    UIViewController *page = SGRArtistSettingsPage();
    nav.viewControllers = @[page];
    [nav.view layoutIfNeeded];
    [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.5]];

    SGModRow *round = rowWithKey((SGModPage *)page, SGRKeyArtistRoundPlay), *cut = rowWithKey((SGModPage *)page, SGRKeyArtistCutOutPlay);
    SGModRow *accent = rowWithKey((SGModPage *)page, SGRKeyAccentPlay);
    if (!round || !cut || !accent || ![cut.waitsOn isEqualToString:SGRKeyArtistRoundPlay] || !accent.visible
        || accent.visible() != SGFlag(SGRKeyArtistCutOutPlay, NO))
        HARNESS_FAIL(@"the Play rows: round %@, cut-out waits on %@, accent shown %d", round.key, cut.waitsOn, accent.visible ? accent.visible() : -1);
    if (![cut.title isEqualToString:@"Cut-out Play"] || ![accent.title isEqualToString:@"Accent Play button"])
        HARNESS_FAIL(@"the rows read \"%@\" and \"%@\"", cut.title, accent.title);

    SGRPagePreview *card = cardIn(page.view);
    UIView *controls = withIdentifier(card, @"retrine.preview.header.controls");
    if (!card || controls.subviews.count != 3) HARNESS_FAIL(@"no preview card or header controls");
    UIView *play = controls.subviews[1];
    UIImageView *glyph = nil;
    for (UIView *view in play.subviews) if ([view isKindOfClass:UIImageView.class]) glyph = (UIImageView *)view;
    Shot *drawn = shoot(card, @"settings-preview");
    if (!shown) {
        if (play.subviews.count != 1 || glyph.alpha != 1) HARNESS_FAIL(@"cut-out off, the card's Play is not its own white one");
        NSLog(@"[harness] PASS the Artists card keeps its white Play");
        return;
    }
    // The card as it would be without the cut: its white Play, the glyph black on it; and with no Play at all.
    UIView *cutView = play.subviews.firstObject;
    UIColor *fill = cutView.backgroundColor;
    UIColor *expected = SGFlag(SGRKeyAccentPlay, NO) ? SGRAccent() : UIColor.whiteColor;
    if (![fill isEqual:expected]) HARNESS_FAIL(@"the card's cut Play is %@, not %@", fill, expected);
    if (glyph.alpha != 0 || !cutView.layer.mask) HARNESS_FAIL(@"the card's Play is not cut");
    play.alpha = 0;
    Shot *field = shoot(card, nil);
    play.alpha = 1;
    cutView.hidden = YES;
    play.backgroundColor = UIColor.whiteColor;
    glyph.alpha = 1;
    Shot *painted = shoot(card, nil);
    cutView.hidden = NO;
    play.backgroundColor = UIColor.clearColor;
    glyph.alpha = 0;
    // The cut circle is the Play's height, in its middle.
    CGRect frame = [play convertRect:play.bounds toView:card];
    CGRect circle = CGRectMake(CGRectGetMidX(frame) - frame.size.height / 2, frame.origin.y, frame.size.height, frame.size.height);
    UIBezierPath *inside = [UIBezierPath bezierPathWithOvalInRect:CGRectInset(circle, 1, 1)];
    RGB ink = rgbOf(UIColor.blackColor), paper = rgbOf(UIColor.whiteColor), filled = rgbOf(fill);
    NSUInteger glyphPixels = 0, hole = 0, ring = 0, ringRight = 0;
    for (size_t y = 0; y < drawn.height; y++) for (size_t x = 0; x < drawn.width; x++) {
        CGPoint point = CGPointMake((x + 0.5) / kScale, (y + 0.5) / kScale);
        if (![inside containsPoint:point]) continue;
        RGB was = rgbAt([painted at:x y:y]), now = rgbAt([drawn at:x y:y]);
        if (near(was, ink, 8)) {
            glyphPixels++;
            if (near(now, rgbAt([field at:x y:y]), 12)) hole++;
        } else if (near(was, paper, 3)) {
            ring++;
            if (near(now, filled, 6)) ringRight++;
        }
    }
    if (glyphPixels < 20 || hole < glyphPixels * 0.95 || ring < 300 || ringRight < ring * 0.97)
        HARNESS_FAIL(@"the card's cut: %lu of %lu glyph pixels show the field, %lu of %lu fill pixels %@", (unsigned long)hole,
                     (unsigned long)glyphPixels, (unsigned long)ringRight, (unsigned long)ring, fill);
    NSLog(@"[harness] PASS the Artists card cuts its Play out of %@: %lu glyph pixels show the field", fill, (unsigned long)glyphPixels);
}

#pragma mark - the app

@interface CutOutScene : UIResponder <UIWindowSceneDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation CutOutScene
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    sgh_window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    sgh_window.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    UINavigationController *nav = [UINavigationController new];
    sgh_window.rootViewController = nav;
    [sgh_window makeKeyAndVisible];
    self.window = sgh_window;
    dispatch_async(dispatch_get_main_queue(), ^{
        BOOL baseline = [sgh_mode isEqualToString:@"baseline"];
        checkHeader(baseline);
        if (!baseline) {
            if ([sgh_mode isEqualToString:@"on"]) checkCapsule();
            checkSettings(nav);
        }
        NSLog(@"[harness] PASS cut-out Play, %@", sgh_mode);
        fflush(NULL);
        exit(0);
    });
}
@end

@interface CutOutApp : UIResponder <UIApplicationDelegate>
@end
@implementation CutOutApp
@end

int main(int argc, char **argv) {
    @autoreleasepool {
        sgh_mode = argc > 1 ? @(argv[1]) : @"off";
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 60 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ HARNESS_FAIL(@"timed out"); });
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(CutOutApp.class));
    }
}
