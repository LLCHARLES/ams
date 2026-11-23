// Player redesign: Animated artwork, the track's Canvas or Apple Music's animated cover behind the player,
// the way the Music app draws it. The clip runs edge to edge from the top, sharp to near its foot, where
// it dissolves into the colors of its last rows, a few of them from side to side, drawn on down to the bottom of
// the field, so it ends in its own colors rather than on the Fluid field. A blur comes in from the seam (from above the controls for a
// Canvas as tall as the screen) and lies under the controls; behind the lyrics the whole clip is blurred.
// The player's square cover goes while a clip plays, so a track without one keeps its cover over Fluid
// (PlayerField.x keeps the field Fluid for this choice). The player's ⋯ menu switches between Animated
// and Fluid at once (Shared/Player/SpeedPitch.h).
//
// The clip is a subview of the field, not of the background plane: the plane's layout brings the field to
// the front on every pass, and a sibling would end up under it. Each of the field's layout passes attaches
// it (SGRPlayerMotionFieldLaidOut), including a field Spotify built again.
// Only the visible, active player requests clips; its current and ahead tickets are released when it leaves.
//
// The clip holds still when the moving field does (SGRField.m): out of a window, with the app not in front,
// while the player opens or closes, and while the song is paused. Under Reduce Motion, Low Power Mode or
// serious heat the clip goes away: the cover stays over Fluid until the clip can be looked up again.
// While a clip is showing, the Fluid field under it is held still too, and once the clip has faded in it is
// hidden (the field's covered): the field's color is what shows above the clip on the pull that dismisses.
//
// The clip is dimmed by how bright it is (SGRPlayerClipDim): three of its frames are measured as it comes in,
// so a white Canvas is drawn darker than a black one and the white text over it keeps its contrast. The dim
// lies only where text does, a band at the top and from above the title down, as the Music app's does:
// over the whole clip it took up to four fifths of its light (issue #101). The band is whole over the status bar,
// and over the header too while it shows something to read (where it plays from, Spotify's arrow, the AI DJ's
// buttons); a header with only the grabber leaves the clip's top to fade in right under the status bar (issue #39).
// Below the title a second black, on top of the dim, deepens toward the bottom of the screen as the Music app's
// player does, so the text there is never on anything lighter than the dim alone. Behind the lyrics it covers the clip.
//
// A track that changes while the player cannot be seen (out of a window, or with the app not in front, which a
// locked phone's player is while it stays in its window) takes the last clip away at once, without a fade, so
// the last track's clip does not greet the player as it opens.
//
// The clip and the cover cross over: the clip fades in from its first frame (the poster, under the video
// until the video has decoded one) as the cover fades out, and fades out as the cover comes back. A clip
// that has drawn no frame of its own after kGiveUp seconds on screen is given up, and the cover comes back.
// On a skip the last clip stays a moment (kHandOver), so a clip already in the store (the next track's is
// fetched ahead, SGMotionFollower) crosses over it with no cover between.
//
// A clip that has drawn a frame and then has its item or its looper fail is played again from the same local
// file, the poster and the foot staying as they are, so an AVFoundation failure does not leave it frozen until
// the track changes. At most kRebuildsMost rebuilds per clip (see SGRPlayerMotionRecovery): a file that will not
// play is then given up as one that never drew, and the cover or the Fluid field comes back. Only the item's and
// the looper's own failure is watched: a clip that plays but stands still, or one that never failed, is what
// the opening count is for, and there is no timer polling its clock.
//
// Spotify's music video (Switch to video) draws in one of three of its units, each told by its video surface
// as the video comes and goes: while one shows it, the clip goes and the cover comes back, as for Fluid.
//
// A square clip (Apple Music's square animated covers, no taller than kSquareAspect) plays in the cover itself
// instead, as the Music app plays one: a subview of the cover on screen, so it takes the cover's corners, its
// paused shrink, its swipe and its hiding for the open's flown cover and the lyrics' thumbnail. The field stays
// as it is under the player, and the cover is not hidden, so the rest of the player reads it as an ordinary
// cover (SGRPlayerMotionShowing stays NO). It fades in over the cover's picture, which is its own first frame.
//
// With the full-screen cover on (SGRKeyPlayerAnimatedStill, off until switched on), a track whose walk found no clip
// shows its cover the way a clip is shown, as a still: the same view (its foot, the blur under the controls, the dim
// and the lyrics' blur), at least kStillLeastAspect tall, so a square cover fills the top of the screen cut at its
// sides, with a scrim of its own under the status bar and the header's controls (kStillScrimTop). The cover is the Kit's for the playing track (SGRNowPlayingArtwork), nothing fetched for it, and only one at
// least kStillLeastPixels wide: a smaller one (the now playing bar's) leaves the ordinary cover until a larger one is
// published, which then comes in. It is held off where a clip would be (not Animated, Spotify's video, Reduce Motion,
// Low Power Mode or serious heat), a clip found later replaces it, and a skip lets it go as it does a clip.
//
// With the Visualizer without a clip on (SGRKeyPlayerAnimatedVisualiser, off until switched on, and off while the
// full-screen cover is on), the same walk's finding no clip puts the Visualizer on the field in the cover's place
// (SGRPlayerVisualiserFallbackWanted, taken up by PlayerVisualiser.m). Nothing shows while the lookup is out, and a
// clip found later or a skip takes it down.
#import <AVFoundation/AVFoundation.h>
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Redesigned/Kit/SGRMotionBudget.h"
#import "Shared/AnimatedArtwork/AnimatedArtwork.h"
#import "Shared/Player/PlayerState.h"
#import "Shared/Player/SGLastTrack.h"
#import "Shared/Player/SpeedPitch.h"
#import "Player.h"
#import "PlayerLyricLine.h"

// Where the clip starts dissolving into its foot, as a share of its height.
static const CGFloat kFootFrom = 0.9;
// The share of the poster's height, at its bottom, whose colors the foot is.
static const CGFloat kFootRows = 0.03;
// The foot's colors from side to side: that many means of the last rows, each over its share of the width, laid
// between by a gradient. A few, so the foot keeps the clip's left and right without columns: a row's own pixels
// stretched on down read as vertical streaks (issue #40).
static const size_t kFootSamples = 4;
// A clip this much taller than wide is a Canvas (9:16), drawn to the window's full height and centered, cut at its
// sides. Apple Music's tall cover (3:4) keeps its own height from the top, whole, as the Music app draws it
// (issues #40 and #57: drawn to the window's height it lost two fifths of its width).
static const CGFloat kCanvasAspect = 1.5;
// A clip no taller than this is square and plays inside the cover; anything taller plays behind the player.
static const CGFloat kSquareAspect = 1.05;
// The blur starts at the seam, or this share of the screen down where that is higher, so it is under the
// controls whatever the clip's shape; it is whole kBlurRamp points below its start.
static const CGFloat kBlurByControls = 0.6, kBlurRamp = 96;
// Seconds a clip may be on screen in front without drawing a frame before it is given up.
static const NSTimeInterval kGiveUp = 5;
// Seconds the last track's clip stays on a skip for the next one's to come in over it.
static const NSTimeInterval kHandOver = 0.4;
// The cover as a still: drawn at least this much taller than wide, and only from a picture this many pixels wide.
static const CGFloat kStillLeastAspect = 4.0 / 3, kStillLeastPixels = 300;
// A still's scrim over the status bar and the header's controls, which a cover's own bright text sits right behind
// (a clip keeps its look without it): this black at the top, gone this many points under the safe area's top, past
// the bottom of the controls. Increase Contrast deepens it by as much as it deepens the dim over a white picture.
static const CGFloat kStillScrimTop = 0.45, kStillScrimBelowSafeTop = 76;
// The dim's floor and ceiling, and what the lyrics add to it.
static const CGFloat kDimLeast = 0.10, kDimMost = 0.80, kDimLyrics = 0.15;
// The dim's band at the top: whole over the status bar, and down to this share of the screen while the header
// shows something to read, so its text gets all of it, then gone over kDimFade points.
static const CGFloat kDimTop = 0.14, kDimFade = 48;
// The black over the dim at the bottom of the screen, from none where the dim is whole above the title: the Music
// app's player darkens toward its foot (issue #39).
static const CGFloat kDeepenBottom = 0.35;
// The frames measured for the dim besides the poster, in seconds into the clip (one past its end is skipped).
static const double kMeasuredAt[] = {1, 2};
// Behind the lyrics the clip itself is blurred, a plain Gaussian blur with no material's gray tint over it
// (issue #101), so it keeps its colors as the Fluid field does; the dim keeps the text's contrast.
static NSString *const kLyricsBlurPath = @"filters.gaussianBlur.inputRadius";
static const CGFloat kLyricsBlurRadius = 30;

// A clip that has drawn a frame and then has its item or its looper fail is played again from the same local
// file, at most this many times: a file AVFoundation will not play stops here and the poster or the Fluid
// field comes back, instead of a rebuild for every failure.
static const NSUInteger kRebuildsMost = 3;

typedef NS_ENUM(NSInteger, SGRPlayerMotionRecoveryStep) {
    SGRPlayerMotionRecoveryNothing,   // nothing to do: the clip may not play, never drew, or the failure was answered
    SGRPlayerMotionRecoveryRebuild,   // another player and looper, over the same file
    SGRPlayerMotionRecoveryGiveUp,   // out of rebuilds
};

// One clip's rebuilds: at most kRebuildsMost, over the same local file. A clip is a view of its own, made for
// one track's file, so a replaced track starts with its own count.
typedef struct {
    NSUInteger rebuilds;   // spent on this clip so far
    BOOL drew;   // this clip has drawn a frame of its own, now or before an item swap or a rebuild
    BOOL over;   // given up, or leaving: nothing more is rebuilt
} SGRPlayerMotionRecovery;

static void SGRPlayerMotionRecoveryBegin(SGRPlayerMotionRecovery *recovery) {
    *recovery = (SGRPlayerMotionRecovery){0};
}

// The clip drew a frame, on the player it has now or on one it had before: kept for the life of the clip. The
// layer's readiness goes back to NO for every item the looper swaps in, so readiness NO says nothing about a
// clip that has played: only YES latches, and a later item failing before its own first frame is still the
// failure of a clip that has drawn.
static void SGRPlayerMotionRecoverySaw(SGRPlayerMotionRecovery *recovery, BOOL readyNow) {
    if (readyNow) recovery->drew = YES;
}

// The clip leaves, or another track's replaces it: a pass already on its way does nothing.
static void SGRPlayerMotionRecoveryCancel(SGRPlayerMotionRecovery *recovery) {
    recovery->over = YES;
}

// Another track began while this clip plays (`same` NO: the clip is the last track's). It stays kHandOver for
// the next one's to cross over it, but it is not played again from behind it, so a failure during the handover
// is only the outgoing clip's, and the visual handover is untouched.
static void SGRPlayerMotionRecoveryTrack(SGRPlayerMotionRecovery *recovery, BOOL same) {
    if (!same) SGRPlayerMotionRecoveryCancel(recovery);
}

// A failure answered with the clip as it is: rebuilt while it has drawn a frame (`drew`: one that never did is
// the opening count's, kGiveUp, and a rebuild would only start that count over) and may play (in a window, the
// app in front, the song not paused), given up once the rebuilds are spent, and nothing where it may not play.
static SGRPlayerMotionRecoveryStep SGRPlayerMotionRecoveryRuns(SGRPlayerMotionRecovery *recovery, BOOL mayPlay) {
    if (recovery->over || !recovery->drew || !mayPlay) return SGRPlayerMotionRecoveryNothing;
    if (recovery->rebuilds >= kRebuildsMost) {
        recovery->over = YES;
        return SGRPlayerMotionRecoveryGiveUp;
    }
    recovery->rebuilds++;
    return SGRPlayerMotionRecoveryRebuild;
}

// What the clip's own observations tell it apart by: the player's item, that item failing, the looper failing,
// and the layer drawing its first frame. A value someone else observes on the same object has another context,
// so it is not taken for one of these.
static char SGRPlayerMotionPlayerContext, SGRPlayerMotionItemContext, SGRPlayerMotionLooperContext, SGRPlayerMotionDrewContext;

@interface CAFilter : NSObject
+ (instancetype)filterWithType:(NSString *)type;
@end

CGFloat SGRPlayerClipDim(CGFloat luminance, BOOL contrast, BOOL lyrics) {
    // White is 1, so (1 + 0.05) / (L + 0.05) >= ratio puts the clip's luminance at `most` or under.
    CGFloat ratio = contrast ? 7 : 4.5, most = 1.05 / ratio - 0.05;
    // A black layer scales the clip's encoded values, which Core Animation blends, so its linear luminance
    // goes down by about the 2.2nd power of what the layer leaves.
    CGFloat dim = luminance > most ? 1 - pow(most / luminance, 1 / 2.2) : 0;
    dim = MIN(MAX(dim, kDimLeast), kDimMost);
    return lyrics ? dim + kDimLyrics : dim;
}

// Each pixel's linear luminance, of the image drawn 16 points square, onto `into` as floats.
static void addLuminances(CGImageRef image, NSMutableData *into) {
    if (!image) return;
    enum { kSide = 16 };
    uint8_t pixels[kSide * kSide * 4];
    CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGContextRef context = CGBitmapContextCreate(pixels, kSide, kSide, 8, kSide * 4, space, (CGBitmapInfo)kCGImageAlphaNoneSkipLast);
    CGColorSpaceRelease(space);
    if (!context) return;
    CGContextDrawImage(context, CGRectMake(0, 0, kSide, kSide), image);
    CGContextRelease(context);
    for (int i = 0; i < kSide * kSide; i++) {
        float linear[3];
        for (int c = 0; c < 3; c++) {
            float v = pixels[i * 4 + c] / 255.0f;
            linear[c] = v <= 0.04045f ? v / 12.92f : powf((v + 0.055f) / 1.055f, 2.4f);
        }
        float luminance = 0.2126f * linear[0] + 0.7152f * linear[1] + 0.0722f * linear[2];
        [into appendBytes:&luminance length:sizeof luminance];
    }
}

// The 75th percentile of the luminances: the bright end the text has to stand out against, past a few
// highlights.
static CGFloat brightEnd(NSData *luminances) {
    NSUInteger count = luminances.length / sizeof(float);
    if (!count) return 0;
    NSMutableData *sorted = [luminances mutableCopy];
    qsort_b(sorted.mutableBytes, count, sizeof(float), ^int(const void *a, const void *b) {
        float x = *(const float *)a, y = *(const float *)b;
        return x < y ? -1 : x > y;
    });
    return ((const float *)sorted.bytes)[(count - 1) * 3 / 4];
}

CGFloat SGRPlayerImageBrightEnd(CGImageRef image) {
    NSMutableData *luminances = [NSMutableData data];
    addLuminances(image, luminances);
    return brightEnd(luminances);
}

// The foot's colors from left to right (kFootSamples), each the mean of its share of the poster's last rows
// (kFootRows), drawn 16 pixels wide.
static NSArray *footColors(CGImageRef poster) {
    enum { kWide = 16 };
    size_t height = CGImageGetHeight(poster), rows = MAX(1, (size_t)(height * kFootRows));
    CGImageRef strip = CGImageCreateWithImageInRect(poster, CGRectMake(0, height - rows, CGImageGetWidth(poster), rows));
    uint8_t pixels[kWide * 4] = {0};
    CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGContextRef context = CGBitmapContextCreate(pixels, kWide, 1, 8, kWide * 4, space, (CGBitmapInfo)kCGImageAlphaNoneSkipLast);
    CGColorSpaceRelease(space);
    CGContextSetInterpolationQuality(context, kCGInterpolationHigh);
    CGContextDrawImage(context, CGRectMake(0, 0, kWide, 1), strip);
    CGContextRelease(context);
    CGImageRelease(strip);
    const size_t per = kWide / kFootSamples;
    NSMutableArray *colors = [NSMutableArray arrayWithCapacity:kFootSamples];
    for (size_t s = 0; s < kFootSamples; s++) {
        CGFloat sum[3] = {0};
        for (size_t i = s * per; i < (s + 1) * per; i++) {
            for (int c = 0; c < 3; c++) sum[c] += pixels[i * 4 + c];
        }
        [colors addObject:(__bridge id)[UIColor colorWithRed:sum[0] / (per * 255.0) green:sum[1] / (per * 255.0)
                                                       blue:sum[2] / (per * 255.0) alpha:1].CGColor];
    }
    return colors;
}

@interface SGRPlayerMotionView : UIView <SGPlayerStateObserver>
@property (nonatomic) CGFloat screenHeight;
// Plays inside the cover, filling it: no foot, dim or blur. Set before -playFile:poster:.
@property (nonatomic) BOOL inCover;
// Runs when the clip is given up: it drew nothing kGiveUp seconds after it was first on screen in front, or
// its item or the looper failed kRebuildsMost times. The owner takes the clip away, so the poster or Fluid
// shows instead; `why` says which, for the log.
@property (nonatomic, copy) void (^gaveUp)(NSString *why);
- (void)playFile:(NSURL *)file poster:(UIImage *)poster;
// The cover alone, with no video: drawn and dimmed as a poster is, at least kStillLeastAspect tall. Called again, it
// draws the new picture in place.
- (void)showStill:(UIImage *)cover;
- (void)appear:(BOOL)animated then:(void (^)(void))done;
- (void)setBlurred:(BOOL)blurred animated:(BOOL)animated;
// The clip is leaving the player (another track's replaces it, or the background changed): it plays nothing
// more, and no failure of it is played again.
- (void)stop;
// Another track began while this clip stood for the last one: it stays kHandOver for the next clip to cross
// over it, but its recovery stops now, so a failure during the handover is not played again behind the next.
- (void)handover;
@end

@implementation SGRPlayerMotionView {
    AVQueuePlayer *_player;
    AVPlayerLooper *_looper;
    NSURL *_file;   // the clip's local file, played again from the start after a failure
    SGRPlayerMotionRecovery _recovery;
    UIView *_picture;   // the clip over its foot, faded in as one
    CALayer *_still;    // the poster, with the video drawn over it
    AVPlayerLayer *_clip;
    CAGradientLayer *_clipMask, *_seamMask;
    CAGradientLayer *_foot;   // the colors of the poster's last rows, from side to side, from the seam down
    CAGradientLayer *_dim;   // black over the clip's top and from above the title down, as dark as the clip is bright
    CAGradientLayer *_deepen;   // more black over the dim, from where it is whole down to the bottom of the screen
    CAGradientLayer *_scrim;   // a still's only: black from the top fading out under the header's controls
    NSMutableData *_luminances;   // of the frames measured so far
    BOOL _lyricsUp;
    NSUInteger _blurTurn;   // counts the lyrics' turns, so a fade cut short leaves the filter to the turn after it
    UIVisualEffectView *_seamBlur;
    CGFloat _aspect;
    BOOL _timing;   // the give-up's count is running
    BOOL _checking;   // a failure's pass is on its way, so the item and the looper are read once for it
    BOOL _drawWatched;   // the layer's readiness is observed, so it comes off once
    AVPlayerItem *_watchedItem;   // the item the player has, watched for failing
}

// What fades is the effect views' effect, never their alpha or an ancestor's: UIKit draws a blur under a
// fading alpha or a mask wrongly or not at all.
// The dim's stops: black at the top and from above the title down, clear between; black all over behind the
// lyrics, which run down the whole screen.
static NSArray *dimColors(BOOL whole) {
    id black = (__bridge id)UIColor.blackColor.CGColor, between = whole ? black : (__bridge id)UIColor.clearColor.CGColor;
    return @[black, black, between, between, black];
}

static UIBlurEffect *blurEffect(void) {
    return [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialDark];
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.userInteractionEnabled = NO;
    self.accessibilityElementsHidden = YES;
    _picture = [[UIView alloc] initWithFrame:frame];
    [self addSubview:_picture];
    _foot = [CAGradientLayer layer];
    _foot.startPoint = CGPointMake(0, 0.5);
    _foot.endPoint = CGPointMake(1, 0.5);
    NSMutableArray *footAt = [NSMutableArray arrayWithCapacity:kFootSamples];
    for (size_t s = 0; s < kFootSamples; s++) [footAt addObject:@((s + 0.5) / kFootSamples)];
    _foot.locations = footAt;
    [_picture.layer addSublayer:_foot];
    // An AVPlayerLayer draws nothing until its first frame is decoded, so the poster, the clip's first
    // frame and where the looper starts, is the contents of the layer the video draws in: there is a
    // picture from the first frame, and the video covers it exactly.
    _still = [CALayer layer];
    _still.contentsGravity = kCAGravityResizeAspectFill;
    _still.masksToBounds = YES;
    _clip = [AVPlayerLayer layer];
    _clip.videoGravity = AVLayerVideoGravityResizeAspectFill;
    [_still addSublayer:_clip];
    _clipMask = [CAGradientLayer layer];
    _clipMask.colors = @[(id)UIColor.blackColor.CGColor, (id)UIColor.blackColor.CGColor, (id)UIColor.clearColor.CGColor];
    _clipMask.locations = @[@0, @(kFootFrom), @1];
    _still.mask = _clipMask;
    [_picture.layer addSublayer:_still];
    _dim = [CAGradientLayer layer];
    _dim.colors = dimColors(NO);
    _dim.opacity = kDimLeast;
    [_picture.layer addSublayer:_dim];
    _deepen = [CAGradientLayer layer];
    _deepen.colors = @[(id)UIColor.clearColor.CGColor, (id)UIColor.blackColor.CGColor];
    _deepen.opacity = kDeepenBottom;
    [_picture.layer addSublayer:_deepen];
    _scrim = [CAGradientLayer layer];
    _scrim.colors = @[(id)UIColor.blackColor.CGColor, (id)UIColor.clearColor.CGColor];
    _scrim.hidden = YES;
    [_picture.layer addSublayer:_scrim];

    _seamBlur = [[UIVisualEffectView alloc] initWithEffect:nil];
    _seamBlur.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    UIView *mask = [UIView new];
    _seamMask = [CAGradientLayer layer];
    _seamMask.colors = @[(id)UIColor.clearColor.CGColor, (id)UIColor.blackColor.CGColor];
    [mask.layer addSublayer:_seamMask];
    _seamBlur.maskView = mask;
    [self addSubview:_seamBlur];

    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    for (NSNotificationName name in @[UIApplicationDidBecomeActiveNotification, UIApplicationWillResignActiveNotification,
                                      NSProcessInfoPowerStateDidChangeNotification, NSProcessInfoThermalStateDidChangeNotification,
                                      UIAccessibilityReduceMotionStatusDidChangeNotification]) {
        [center addObserver:self selector:@selector(updateMotionSoon) name:name object:nil];
    }
    [center addObserver:self selector:@selector(updateDim) name:UIAccessibilityDarkerSystemColorsStatusDidChangeNotification object:nil];
    [center addObserver:self selector:@selector(updateDim) name:UIAccessibilityReduceTransparencyStatusDidChangeNotification object:nil];
    SGRObservePlayerTransition(self, ^(id owner) { [owner updateMotion]; });
    SGAddPlayerStateObserver(self);
    return self;
}

- (void)playerStateDidChange:(SPTPlayerState *)state {
    [self updateMotion];
}

- (void)dealloc {
    // A looper let go while it plays is what AVFoundation minds: the player stops, the looper stops watching it,
    // and the layer lets the player go before any of them can be freed playing.
    [self unwatch];
    [_player pause];
    [_looper disableLooping];
    _clip.player = nil;
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

// A clip that is leaving the player plays nothing more, and no failure of it is played again: the owner is
// taking it off, and a rebuild would only be taken off with it.
- (void)stop {
    SGRPlayerMotionRecoveryCancel(&_recovery);
}

- (void)handover {
    SGRPlayerMotionRecoveryTrack(&_recovery, NO);
}

- (void)setScreenHeight:(CGFloat)height {
    if (height == _screenHeight) return;
    _screenHeight = height;
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect bounds = self.bounds;
    if (_inCover) {
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        _picture.frame = bounds;
        _still.frame = bounds;
        _clip.frame = _still.bounds;
        [CATransaction commit];
        return;
    }
    CGFloat width = bounds.size.width, total = MAX(1, bounds.size.height);
    CGFloat screen = _screenHeight > 0 ? _screenHeight : total;
    CGFloat height = round(width * _aspect);
    if (_aspect > kCanvasAspect) height = MAX(height, screen);
    CGFloat seam = round(height * kFootFrom), blurFrom = MIN(seam, round(screen * kBlurByControls));
    _picture.frame = bounds;
    _seamBlur.frame = bounds;
    _seamBlur.maskView.frame = bounds;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _still.frame = CGRectMake(0, 0, width, height);
    _clip.frame = _still.bounds;
    _clipMask.frame = _still.bounds;
    _foot.frame = CGRectMake(0, seam, width, MAX(0, total - seam));
    _dim.frame = bounds;
    _deepen.frame = bounds;
    // The window's safe area: this view's own, on the field in the player's list, reads none.
    CGFloat safeTop = self.window.safeAreaInsets.top;
    _scrim.frame = CGRectMake(0, 0, width, safeTop + kStillScrimBelowSafeTop);
    NSNumber *(^at)(CGFloat) = ^NSNumber *(CGFloat y) { return @(MIN(1, y / total)); };
    // Whole again by where the seam's blur starts, so over the title and the controls below it.
    CGRect line = SGRPlayerVisibleClipLineIn(self);
    CGFloat dimFrom = CGRectIsNull(line) ? blurFrom : MIN(blurFrom, MAX(0, CGRectGetMinY(line)));
    // The band at the top reaches as far as there is something to read: the status bar, and the header while it
    // shows more than the grabber.
    CGFloat bandEnd = SGRPlayerHeaderShowsIn(self) ? screen * kDimTop : safeTop;
    CGFloat topEnd = MIN(bandEnd, dimFrom), rampFrom = MAX(topEnd, dimFrom - kBlurRamp);
    _dim.locations = @[@0, at(topEnd), at(MIN(topEnd + kDimFade, rampFrom)), at(rampFrom), at(dimFrom)];
    _deepen.locations = @[at(dimFrom), at(screen)];
    _seamMask.frame = bounds;
    _seamMask.locations = @[at(blurFrom), at(blurFrom + kBlurRamp)];
    [CATransaction commit];
}

// The picture under the video, or the whole of a still, and the share of the width the view draws it tall.
- (void)takePicture:(UIImage *)picture aspect:(CGFloat)aspect {
    _aspect = aspect;
    _foot.colors = footColors(picture.CGImage);
    _still.contents = (__bridge id)picture.CGImage;
    [self setNeedsLayout];
}

- (void)showStill:(UIImage *)cover {
    [self takePicture:cover aspect:MAX(cover.size.height / cover.size.width, kStillLeastAspect)];
    _scrim.hidden = NO;
    [self measurePoster:cover];
}

- (void)playFile:(NSURL *)file poster:(UIImage *)poster {
    [self takePicture:poster aspect:poster.size.height / poster.size.width];
    _file = file;
    SGRPlayerMotionRecoveryBegin(&_recovery);
    [self build];
    [self updateMotion];
    if (_inCover) {
        // The cover's own picture: nothing over it to keep readable, and nothing under it to fade into.
        _still.mask = nil;
        _foot.hidden = _dim.hidden = _deepen.hidden = _seamBlur.hidden = YES;
        return;
    }
    [self measure:file poster:poster];
}

// A player and a looper over the clip's own file. The looper hands the player its own copies of the item, so
// the item is watched where the player takes it: an item that fails says so, and so does a looper that cannot
// go on. What they watch goes before another is made, so an observer never outlives the object it was put on.
- (void)build {
    [self unwatch];
    [_player pause];
    [_looper disableLooping];
    _clip.player = nil;
    _player = [AVQueuePlayer new];
    _player.muted = YES;
    _player.preventsDisplaySleepDuringVideoPlayback = NO;
    [_player addObserver:self forKeyPath:@"currentItem" options:NSKeyValueObservingOptionInitial | NSKeyValueObservingOptionNew
                 context:&SGRPlayerMotionPlayerContext];
    _looper = [AVPlayerLooper playerLooperWithPlayer:_player templateItem:[AVPlayerItem playerItemWithURL:_file]];
    [_looper addObserver:self forKeyPath:@"status" options:0 context:&SGRPlayerMotionLooperContext];
    _clip.player = _player;
    // The layer's readiness belongs to the item it has now, and goes back to NO for every one the looper swaps
    // in: what is kept is that this clip drew a frame at all, not that this item has.
    [_clip addObserver:self forKeyPath:@"readyForDisplay" options:NSKeyValueObservingOptionInitial | NSKeyValueObservingOptionNew
               context:&SGRPlayerMotionDrewContext];
    _drawWatched = YES;
    // A looper made over a file it cannot read is failed before KVO reports anything; the item it hands the
    // player the same way, which `watchItem` reads where the player takes it.
    if (_looper.status == AVPlayerLooperStatusFailed) [self recover];
}

// Every observer this view added, taken off the object it was added to, and only those.
- (void)unwatch {
    if (_watchedItem) {
        [_watchedItem removeObserver:self forKeyPath:@"status" context:&SGRPlayerMotionItemContext];
        _watchedItem = nil;
    }
    if (_drawWatched) {
        [_clip removeObserver:self forKeyPath:@"readyForDisplay" context:&SGRPlayerMotionDrewContext];
        _drawWatched = NO;
    }
    if (_player) [_player removeObserver:self forKeyPath:@"currentItem" context:&SGRPlayerMotionPlayerContext];
    if (_looper) [_looper removeObserver:self forKeyPath:@"status" context:&SGRPlayerMotionLooperContext];
}

// The player changed item: watch the one it has now, and let go of the one it had.
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if (context != &SGRPlayerMotionPlayerContext && context != &SGRPlayerMotionItemContext
        && context != &SGRPlayerMotionLooperContext && context != &SGRPlayerMotionDrewContext) {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
        return;
    }
    // AVFoundation reports these on a queue of its own, and the item a player hands over is read where it is
    // watched: all of it on main, where the clip's own state lives.
    __weak SGRPlayerMotionView *weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf mediaChanged:object context:context]; });
}

// What changed, with the object it changed on: one of the player's, its item's, the looper's or the layer's.
// Whoever reports it must still be the one this view plays with, so a callback from a player that a rebuild
// replaced says nothing about the new one.
- (void)mediaChanged:(id)object context:(void *)context {
    if (context == &SGRPlayerMotionPlayerContext) {
        [self watchItem:_player.currentItem];
    } else if (context == &SGRPlayerMotionItemContext) {
        if (object == _watchedItem && _watchedItem.status == AVPlayerItemStatusFailed) [self recover];
    } else if (context == &SGRPlayerMotionDrewContext) {
        // One decoded frame, on this player or an earlier one, stays this clip's. Read from the layer rather than
        // the change, so a swap that has already taken readiness away since does not lose it.
        if (object == _clip) SGRPlayerMotionRecoverySaw(&_recovery, _clip.readyForDisplay);
    } else {
        if (object == _looper && _looper.status == AVPlayerLooperStatusFailed) [self recover];
    }
}

- (void)watchItem:(AVPlayerItem *)item {
    if (item == _watchedItem) return;
    if (_watchedItem) [_watchedItem removeObserver:self forKeyPath:@"status" context:&SGRPlayerMotionItemContext];
    _watchedItem = item;
    if (!item) return;
    [item addObserver:self forKeyPath:@"status" options:0 context:&SGRPlayerMotionItemContext];
    // A player can hand over an item that is failed already, which KVO does not report again.
    if (item.status == AVPlayerItemStatusFailed) [self recover];
}

// A failure of what the clip plays with, answered on the next pass, where the item and the looper are read
// again: a track replaced or a pause in between is seen there, so a clip that left, or one that may not play,
// is left alone. A clip that never drew a frame is the opening count's, kGiveUp, and a rebuild would only start
// that count over, so only one that has drawn is played again (`_recovery.drew`, kept across item swaps).
- (void)recover {
    // One answer at a time: the item and the looper both failing is one pass to read them.
    if (_checking || _recovery.over) return;
    _checking = YES;
    __weak SGRPlayerMotionView *weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf answerFailure]; });
}

// The pass that answers a failure: rebuild from the same file, give up when the rebuilds are spent (the owner
// then takes the clip away, so the poster or the Fluid field shows), or nothing where the clip may not play.
// The item and the looper are read here, so an answer is only for what is failed now, and a rebuild that has
// already made a healthy player is not rebuilt again.
- (void)answerFailure {
    _checking = NO;
    if (_recovery.over) return;
    if (_watchedItem.status != AVPlayerItemStatusFailed && _looper.status != AVPlayerLooperStatusFailed) return;
    // A frame that drew since the pass was queued is the clip's too, before the policy is asked.
    SGRPlayerMotionRecoverySaw(&_recovery, _clip.readyForDisplay);
    switch (SGRPlayerMotionRecoveryRuns(&_recovery, [self mayPlay])) {
        case SGRPlayerMotionRecoveryNothing:
            return;
        case SGRPlayerMotionRecoveryGiveUp:
            SGLog(@"redesign player: animated artwork %@ failed %lu times, given up", _file.lastPathComponent, (unsigned long)kRebuildsMost);
            if (self.gaveUp) self.gaveUp(@"its item or its looper kept failing");
            return;
        case SGRPlayerMotionRecoveryRebuild:
            SGLog(@"redesign player: animated artwork %@ failed, played again (%lu of %lu)", _file.lastPathComponent,
                  (unsigned long)_recovery.rebuilds, (unsigned long)kRebuildsMost);
            [self build];
            [self updateMotion];
            return;
    }
}

// The poster alone, so the clip comes in already dimmed; a measure of another clip still on its way is dropped.
- (void)measurePoster:(UIImage *)poster {
    _luminances = [NSMutableData data];
    addLuminances(poster.CGImage, _luminances);
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    [self updateDim];
    [CATransaction commit];
}

// The poster now, and two later frames as they are read.
- (void)measure:(NSURL *)file poster:(UIImage *)poster {
    [self measurePoster:poster];
    AVAssetImageGenerator *generator = [AVAssetImageGenerator assetImageGeneratorWithAsset:[AVURLAsset assetWithURL:file]];
    generator.appliesPreferredTrackTransform = YES;
    generator.maximumSize = CGSizeMake(64, 64);
    __weak SGRPlayerMotionView *weakSelf = self;
    NSMutableData *into = _luminances;
    for (size_t i = 0; i < sizeof kMeasuredAt / sizeof *kMeasuredAt; i++) {
        [generator generateCGImageAsynchronouslyForTime:CMTimeMakeWithSeconds(kMeasuredAt[i], 600)
                                      completionHandler:^(CGImageRef image, CMTime actual, NSError *error) {
            if (!image) return;
            NSMutableData *frame = [NSMutableData data];
            addLuminances(image, frame);
            dispatch_async(dispatch_get_main_queue(), ^{
                SGRPlayerMotionView *view = weakSelf;
                if (!view || view->_luminances != into) return;
                [into appendData:frame];
                [view updateDim];
            });
        }];
    }
}

- (void)updateDim {
    // Reduce Transparency puts the lyrics on black, as the material it replaced went opaque there.
    BOOL contrast = UIAccessibilityDarkerSystemColorsEnabled();
    CGFloat dim = _lyricsUp && SGRReduceTransparency() ? 1 : SGRPlayerClipDim(brightEnd(_luminances), contrast, _lyricsUp);
    _dim.opacity = (float)dim;
    _scrim.opacity = (float)(contrast ? kStillScrimTop * SGRPlayerClipDim(1, YES, NO) / SGRPlayerClipDim(1, NO, NO) : kStillScrimTop);
}

// `done` runs once the clip is opaque, unless something cut the fade in short.
- (void)appear:(BOOL)animated then:(void (^)(void))done {
    _picture.alpha = 0;
    void (^apply)(void) = ^{
        self->_picture.alpha = 1;
        if (!self->_inCover) self->_seamBlur.effect = blurEffect();
    };
    if (animated) {
        SGRAnimate(SGRMotionFade, apply, ^(BOOL finished) {
            if (finished) done();
        });
    } else {
        apply();
        done();
    }
}

// The clip and the seam's blur fade out; `done` runs once they have.
- (void)disappear:(void (^)(void))done {
    SGRAnimate(SGRMotionFade, ^{
        self->_picture.alpha = 0;
        self->_seamBlur.effect = nil;
    }, ^(BOOL finished) { done(); });
}

// The lyrics' blur, and their share of the dim, which a layer's own animation carries over the same fade. The
// filter is on the clip only while the lyrics are up, so a closed lyrics page costs no blur pass a frame.
- (void)setBlurred:(BOOL)blurred animated:(BOOL)animated {
    // Asked again on every footer layout pass: the same state again would restart the fade.
    if (blurred == _lyricsUp) return;
    _lyricsUp = blurred;
    NSUInteger turn = ++_blurTurn;
    CALayer *layer = _picture.layer;
    if (blurred && !layer.filters && !SGRReduceTransparency()) {
        CAFilter *blur = [NSClassFromString(@"CAFilter") filterWithType:@"gaussianBlur"];
        [blur setValue:@0 forKey:@"inputRadius"];
        // The clip's edges blur against themselves, not against the clear around it.
        [blur setValue:@YES forKey:@"inputNormalizeEdges"];
        if (blur) {
            layer.filters = @[blur];
            // The clip changes every video frame, so the blur runs every frame either way: rendered at one pixel a
            // point it blurs a ninth of a 3x screen's pixels, as cheap as the material's quarter-scale backdrop
            // was. Nothing sharp is left to lose.
            layer.rasterizationScale = 1;
            layer.shouldRasterize = YES;
        }
    }
    id shown = [layer.presentationLayer valueForKeyPath:kLyricsBlurPath];
    CGFloat from = [shown isKindOfClass:NSNumber.class] ? [shown doubleValue] : 0, to = blurred ? kLyricsBlurRadius : 0;
    [CATransaction begin];
    [CATransaction setDisableActions:!animated];
    [CATransaction setAnimationDuration:SGRCrossfade];
    _dim.colors = dimColors(blurred);
    [self updateDim];
    if (layer.filters) {
        __weak SGRPlayerMotionView *weakSelf = self;
        [CATransaction setCompletionBlock:^{
            SGRPlayerMotionView *view = weakSelf;
            if (!view || view->_blurTurn != turn || view->_lyricsUp) return;
            view->_picture.layer.filters = nil;
            view->_picture.layer.shouldRasterize = NO;
        }];
        [layer setValue:@(to) forKeyPath:kLyricsBlurPath];
        if (animated) {
            CABasicAnimation *ease = [CABasicAnimation animationWithKeyPath:kLyricsBlurPath];
            ease.fromValue = @(from);
            ease.toValue = @(to);
            ease.duration = SGRCrossfade;
            ease.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
            [layer addAnimation:ease forKey:@"lyricsBlur"];
        }
    }
    [CATransaction commit];
}

// The power state is reported off the main thread.
- (void)updateMotionSoon {
    dispatch_async(dispatch_get_main_queue(), ^{ [self updateMotion]; });
}

// Whether the clip plays: in a window with the app in front, the player not opening or closing, no stand-down
// and the song not paused. A locked phone keeps the player in its window, so being in front counts as much as
// being in one. A failure is rebuilt only while this holds, so a pause, a detachment or a stand-down cancels
// the recovery it would have had.
- (BOOL)mayPlay {
    BOOL front = UIApplication.sharedApplication.applicationState == UIApplicationStateActive;
    return self.window && front && !SGRPlayerIsTransitioning() && !SGRReduceMotion() && !SGRMotionHeldForPowerOrHeat()
        && !SGPlayerState().isPaused;
}

- (void)updateMotion {
    BOOL front = UIApplication.sharedApplication.applicationState == UIApplicationStateActive;
    BOOL may = [self mayPlay];
    if (may) [_player play];
    else [_player pause];
    // A clip that plays again is asked whether its item or looper failed while it could not: the failure is
    // answered here, on the pass that puts it back on screen, and never behind a paused song or off screen.
    // This reads a state, it does not poll a clock.
    if (may) {
        SGRPlayerMotionRecoverySaw(&_recovery, _clip.readyForDisplay);
        if (_watchedItem.status == AVPlayerItemStatusFailed || _looper.status == AVPlayerLooperStatusFailed) [self recover];
    }
    // A paused player still draws the clip's first frame, so the count runs whenever it is on screen in front.
    if (_player && self.window && front && !_timing && !_clip.readyForDisplay) {
        _timing = YES;
        __weak SGRPlayerMotionView *weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kGiveUp * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            SGRPlayerMotionView *view = weakSelf;
            if (!view) return;
            view->_timing = NO;
            // Taken off screen meanwhile, the count starts again when it is back.
            BOOL shown = view.window && UIApplication.sharedApplication.applicationState == UIApplicationStateActive;
            if (shown && !view->_clip.readyForDisplay && view.gaveUp)
                view.gaveUp([NSString stringWithFormat:@"drew nothing in %.0f s", kGiveUp]);
        });
    }
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    [self updateMotion];
    // The scrim ends under the window's safe area top, which it has only now.
    [self setNeedsLayout];
}

@end

static SGRPlayerMotionView *sg_motion;
static SGRPlayerMotionView *sg_coverClip;   // a square clip, in the cover rather than behind the player
static NSString *sg_track;   // the track playing
static NSString *sg_shown;   // the track sg_motion is the clip of
static NSUInteger sg_begun;   // counts the walks begun, so a poster read for an earlier one is dropped
static NSString *sg_noClip;   // the track whose walk found no clip, until another walk begins
static NSString *sg_stillOf;   // the identity of the cover sg_motion shows as a still; nil while it is a clip or none
// The clip sg_motion plays and its poster, for the Player page's showcase (SGRPlayerMotionPreview).
static NSURL *sg_motionFile;
static UIImage *sg_motionPoster;
// The clip is in and opaque, so the field under it is covered.
static BOOL sg_covering;
// The list the mask went on, so it comes off even while the player is closed and the list cannot be found,
// and the mask, told from any other.
static __weak CALayer *sg_maskedCovers, *sg_coverMask;

// The clip from the top of the field, as wide as it is, its foot down to the bottom of the field's bleed.
static void layOut(void) {
    SGRArtworkField *field = SGRPlayerField();
    if (!sg_motion || !field) return;
    if (sg_motion.superview != field) [field addSubview:sg_motion];
    CGSize size = field.bounds.size;
    CGFloat screen = field.window.bounds.size.height ?: size.height;
    CGRect frame = CGRectMake(0, 0, size.width, MAX(size.height, screen) + field.bleed.bottom);
    if (!CGRectEqualToRect(sg_motion.frame, frame)) sg_motion.frame = frame;
    sg_motion.screenHeight = screen;
    // A field Spotify built again is covered too.
    field.covered = sg_covering;
}

static void cover(BOOL covering) {
    sg_covering = covering;
    SGRPlayerField().covered = covering;
}

// The mask's opacity to `opacity`, from where it is drawn now, over the clip's own fade. The frame reaches a
// few covers past the list's bounds either way, which move as the list scrolls: it counts only during a fade,
// since at 0 the mask hides everything and at 1 it comes off.
static void fadeCoverMask(CALayer *covers, CALayer *mask, float opacity, BOOL animated, void (^done)(void)) {
    // A list out of a window, a closed player's, has nothing to fade.
    id list = covers.delegate;
    animated = animated && [list isKindOfClass:UIView.class] && ((UIView *)list).window;
    CGRect bounds = covers.bounds;
    float from = (mask.presentationLayer ?: mask).opacity;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    mask.frame = CGRectInset(bounds, -3 * bounds.size.width, -bounds.size.height);
    mask.opacity = opacity;
    if (animated) {
        CABasicAnimation *fade = [CABasicAnimation animationWithKeyPath:@"opacity"];
        fade.fromValue = @(from);
        fade.toValue = @(opacity);
        fade.duration = SGRCrossfade;
        fade.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
        [CATransaction setCompletionBlock:done];
        [mask addAnimation:fade forKey:@"opacity"];
    } else {
        [mask removeAnimationForKey:@"opacity"];
    }
    [CATransaction commit];
    if (!animated && done) done();
}

// A mask rather than alpha: the covers still take the swipe that changes track, and the lyrics, which fade
// the list by its alpha as they come and go, cannot bring the cover back. Asked again for where it is going,
// it does nothing, so the field's layout passes do not cut a fade short.
static void setCoverShown(BOOL shown, BOOL animated) {
    CALayer *covers = shown ? sg_maskedCovers : SGRPlayerCoverList().layer;
    if (!covers) return;
    CALayer *mask = covers.mask;
    BOOL ours = mask && mask == sg_coverMask;
    if (shown) {
        sg_maskedCovers = nil;
        if (!ours) return;
        // A newer fade ends this one early, and the mask stays for it.
        fadeCoverMask(covers, mask, 1, animated, ^{
            if (covers.mask == mask && sg_maskedCovers != covers) covers.mask = nil;
        });
        return;
    }
    if (covers == sg_maskedCovers || (mask && !ours)) return;
    if (!mask) {
        mask = [CALayer layer];
        mask.backgroundColor = UIColor.blackColor.CGColor;
        covers.mask = mask;
        sg_coverMask = mask;
    }
    sg_maskedCovers = covers;
    fadeCoverMask(covers, mask, 0, animated, nil);
}

// The Visualizer's Poster or Cut is showing a line, whose type then owns the cover's place (PlayerVisualiser.m).
static BOOL sg_stageTakesCover;

// The cover shows unless a clip behind the player or a lyric stage's line takes its place.
static BOOL coverWanted(void) {
    return sg_motion == nil && !sg_stageTakesCover;
}

BOOL SGRPlayerCoverHidden(void) {
    return !coverWanted();
}

void SGRPlayerLyricStageTakesCover(BOOL takes) {
    if (takes == sg_stageTakesCover) return;
    sg_stageTakesCover = takes;
    setCoverShown(coverWanted(), YES);
}

void SGRPlayerMotionFieldLaidOut(void) {
    layOut();
    setCoverShown(coverWanted(), NO);
}

static void attachCoverClip(void);

// A clip that came in while the player opened can find no cover to hide at the field's first pass, the covers
// laying out after it (issue #19: the cover over the clip after a relaunch), so each cover's layout asks too.
void SGRPlayerMotionCoverLaidOut(void) {
    setCoverShown(coverWanted(), NO);
    attachCoverClip();
}

// The square clip goes into the cover on screen when it has none to be in: Spotify is still laying out
// the covers, or built them again. A cover it is in that is still in a window keeps it, so a swipe
// that shows the next cover a moment does not carry the clip over to it.
static void attachCoverClip(void) {
    SGRPlayerMotionView *clip = sg_coverClip;
    if (!clip) return;
    UIView *holder = clip.superview;
    if (!holder.window) {
        UIView *cover = SGRPlayerShowingCover();
        if (!cover) return;
        [cover addSubview:clip];
        holder = cover;
    }
    if (!CGRectEqualToRect(clip.frame, holder.bounds)) clip.frame = holder.bounds;
}

BOOL SGRPlayerMotionShowing(void) {
    return sg_motion != nil;
}

void SGRPlayerMotionLineMoved(void) { [sg_motion setNeedsLayout]; }

void SGRPlayerMotionHeaderChanged(void) { [sg_motion setNeedsLayout]; }

// The card's one clip and the file it plays: a tap on another background choice takes the view off the card
// and the next tap puts it back, so the same file is not made a playing looper a second time.
static SGRPlayerMotionView *sg_previewView;
static NSURL *sg_previewViewFile;

static UIView *previewOf(NSURL *file, UIImage *poster) {
    // A view the card has just taken off is still the one for this file: it comes back as it is, so nothing it
    // was playing is let go while it plays. Out of whatever held it before, in case it is another card's.
    if (sg_previewView && [sg_previewViewFile isEqual:file]) {
        SGRPlayerMotionView *preview = sg_previewView;
        [preview removeFromSuperview];
        [preview appear:NO then:^{}];
        return preview;
    }
    [sg_previewView removeFromSuperview];
    SGRPlayerMotionView *preview = [[SGRPlayerMotionView alloc] initWithFrame:CGRectZero];
    [preview playFile:file poster:poster];
    [preview appear:NO then:^{}];
    sg_previewView = preview;
    sg_previewViewFile = file;
    return preview;
}

// The playing track's clip the Player page looked up itself while the player had none, and its poster; the
// file is nil while the walk is out or after it found nothing. The walk is the player's (SGMotionClipFor, at
// the size SGMotionFollower asks for), so its file lands in the store, where the player's own walk finds it.
// With no track playing, the track is the last one played (Shared/Player/SGLastTrack.h).
static NSString *sg_previewTrack;
static NSURL *sg_previewFile;
static UIImage *sg_previewPoster;
static void (^sg_previewArrived)(void);
static SGMotionTicket *sg_previewTicket;
static BOOL sg_previewLooking;
static NSUInteger sg_previewGeneration;

void SGRPlayerMotionPreviewStop(void) {
    sg_previewGeneration++;
    [sg_previewTicket cancel];
    sg_previewTicket = nil;
    sg_previewLooking = NO;
    sg_previewArrived = nil;
    sg_previewTrack = nil;
    sg_previewFile = nil;
    sg_previewPoster = nil;
    [sg_previewView stop];
    [sg_previewView removeFromSuperview];
    sg_previewView = nil;
    sg_previewViewFile = nil;
}

UIView *SGRPlayerMotionPreview(void (^arrived)(void)) {
    SGShownTrack *shown = SGShownTrackNow();
    NSString *track = shown.uri;
    if (![track isEqualToString:sg_previewTrack]) {
        SGRPlayerMotionPreviewStop();
        sg_previewTrack = track;
    }
    if (!track) return nil;
    // The real player deliberately retains the previous clip during handover. The preview must not borrow it.
    if (sg_motionFile && [track isEqualToString:sg_shown]) return previewOf(sg_motionFile, sg_motionPoster);
    if (sg_previewFile) return previewOf(sg_previewFile, sg_previewPoster);
    if (!arrived) return nil;
    // The newest page's to be told; a walk already out for this track is waited on rather than asked again.
    sg_previewArrived = [arrived copy];
    if (sg_previewLooking) return nil;
    sg_previewLooking = YES;
    NSUInteger generation = sg_previewGeneration;
    SGLog(@"redesign player: the Player page looks up the clip of %@%@", track, shown.current ? @"" : @", the last played");
    sg_previewTicket = SGMotionRequestSongClip(track, shown.canvasURL, shown.artist, shown.album, shown.title, SGMotionPixels(),
                    ^(NSURL *file, NSString *source) {
        if (generation != sg_previewGeneration) return;
        // Nothing found is not kept: the page asks again the next time it shows Animated.
        if (!file) {
            sg_previewLooking = NO;
            sg_previewArrived = nil;
            return;
        }
        SGMotionPoster(file, ^(UIImage *poster) {
            if (generation != sg_previewGeneration) return;
            sg_previewLooking = NO;
            sg_previewTicket = nil;
            void (^done)(void) = sg_previewArrived;
            sg_previewArrived = nil;
            if (!poster || poster.size.width <= 0) {
                return;
            }
            sg_previewFile = file;
            sg_previewPoster = poster;
            SGLog(@"redesign player: the Player page's clip from %@, %@", source, file.lastPathComponent);
            if (done) done();
        });
    });
    return nil;
}

static SGMotionFollower *sg_follower;
static BOOL sg_inactive;

static BOOL consumerVisible(void) {
    return !sg_inactive && UIApplication.sharedApplication.applicationState == UIApplicationStateActive && SGRPlayerIsVisible();
}

// Spotify's units that are showing its music video, held weakly: one that goes without saying so lets go.
static NSHashTable *sg_videos;

static BOOL videoShowing(void) {
    return sg_videos.allObjects.count > 0;
}

// Reduce Motion asks for no looping clip; low power or serious heat spares the video decoding.
static BOOL motionAllowed(void) {
    return !SGRReduceMotion() && !SGRMotionHeldForPowerOrHeat();
}

// What a clip, or the cover's still, is shown under: Animated chosen, Spotify's video not showing, motion allowed.
// Read on every track, since the ⋯ menu switches the background.
static BOOL clipWanted(void) {
    return SGRPlayerBackground() == SGRPlayerBackgroundAnimated && !videoShowing() && motionAllowed();
}

// The clip can be seen: in a window, with the app in front.
static BOOL seen(UIView *view) {
    return view.window && UIApplication.sharedApplication.applicationState == UIApplicationStateActive;
}

// The clip fades out over the cover coming back where the player is seen, and goes at once where not.
static void clearForReplacement(BOOL animated, BOOL fieldClipFollows) {
    SGRPlayerMotionView *old = sg_motion, *inCover = sg_coverClip;
    sg_motion = nil;
    if (old && !fieldClipFollows) SGRPlayerLyricClipChanged();
    sg_coverClip = nil;
    sg_shown = nil;
    sg_stillOf = nil;
    sg_motionFile = nil;
    sg_motionPoster = nil;
    // Neither plays again, whatever its item reported a moment ago: the track is replaced or the clip given up.
    [old stop];
    [inCover stop];
    if (animated && seen(inCover)) [inCover disappear:^{ [inCover removeFromSuperview]; }];
    else [inCover removeFromSuperview];
    // Uncovered before the clip starts to fade, so the field is there under it.
    cover(NO);
    // The Fluid field under a clip holds still, as it does for a paused song (PlayerField.x): the clip covers it.
    SGRPlayerHoldField();
    animated = animated && seen(old);
    setCoverShown(coverWanted(), animated);
    if (animated) [old disappear:^{ [old removeFromSuperview]; }];
    else [old removeFromSuperview];
}

static void clear(BOOL animated) { clearForReplacement(animated, NO); }

static void showInCover(NSString *track, NSURL *file, UIImage *poster) {
    SGRPlayerMotionView *clip = [[SGRPlayerMotionView alloc] initWithFrame:CGRectZero];
    clip.inCover = YES;
    sg_coverClip = clip;
    sg_shown = track;
    __weak SGRPlayerMotionView *weakClip = clip;   // the clip holds the block
    clip.gaveUp = ^(NSString *why) {
        if (!weakClip || sg_coverClip != weakClip) return;
        SGLog(@"redesign player: animated artwork %@ given up: %@", file.lastPathComponent, why);
        clear(YES);
    };
    [clip playFile:file poster:poster];
    sg_motionFile = file;
    sg_motionPoster = poster;
    attachCoverClip();
    [clip appear:seen(clip) then:^{}];
    SGLog(@"redesign player: animated artwork %@ in the cover, %.0fx%.0f", file.lastPathComponent, poster.size.width, poster.size.height);
}

// sg_motion made for `track` behind the player, drawn by `draw`, laid on the field and faded in over the cover where
// it is seen. `name` is what the log calls it.
static void showBehind(NSString *track, NSString *name, void (^draw)(SGRPlayerMotionView *motion)) {
    sg_motion = [[SGRPlayerMotionView alloc] initWithFrame:CGRectZero];
    sg_shown = track;
    SGRPlayerMotionView *motion = sg_motion;
    __weak SGRPlayerMotionView *weakMotion = motion;   // the clip holds the block
    motion.gaveUp = ^(NSString *why) {
        if (!weakMotion || sg_motion != weakMotion) return;
        SGLog(@"redesign player: animated artwork %@ given up: %@", name, why);
        clear(YES);
    };
    draw(motion);
    SGRPlayerLyricClipChanged();
    layOut();
    SGRPlayerHoldField();
    [motion setBlurred:SGRPlayerLyricsOpen() animated:NO];
    BOOL animated = seen(motion);
    [motion appear:animated then:^{
        if (sg_motion == motion) cover(YES);
    }];
    setCoverShown(NO, animated);
}

static void show(NSString *track, NSURL *file) {
    if (!consumerVisible() || !file || ![track isEqualToString:sg_track]) return;
    NSUInteger begun = sg_begun;
    SGMotionPoster(file, ^(UIImage *poster) {
        // A walk begun while the poster was read (switched off, Spotify's video) has the say.
        if (!consumerVisible() || !poster || poster.size.width <= 0 || begun != sg_begun) return;
        BOOL square = poster.size.height / poster.size.width <= kSquareAspect;
        clearForReplacement(YES, !square);
        if (square) {
            showInCover(track, file, poster);
            return;
        }
        showBehind(track, file.lastPathComponent, ^(SGRPlayerMotionView *motion) { [motion playFile:file poster:poster]; });
        sg_motionFile = file;
        sg_motionPoster = poster;
        SGLog(@"redesign player: animated artwork %@, %.0fx%.0f", file.lastPathComponent, poster.size.width, poster.size.height);
    });
}

BOOL SGRPlayerStillOn(void) {
    return SGHidden(SGRKeyPlayerAnimatedStill);
}

// The playing track's cover as the still, where the track's walk found no clip, a clip would be shown, and the cover
// the Kit has is this track's own and at least kStillLeastPixels wide; YES while this track's still shows. The same
// picture again changes nothing, and another picture of the track is drawn in place.
static BOOL showStill(void) {
    if (!consumerVisible() || !SGRPlayerStillOn() || ![sg_noClip isEqualToString:sg_track] || !clipWanted()) return NO;
    NSString *uri = nil, *identity = nil;
    UIImage *picture = SGRNowPlayingArtwork(&uri, &identity);
    BOOL showing = sg_stillOf && [sg_shown isEqualToString:sg_track];
    if (![uri isEqualToString:sg_track] || !picture.CGImage || picture.size.width * picture.scale < kStillLeastPixels) return showing;
    if (showing) {
        if (![identity isEqualToString:sg_stillOf]) {
            [sg_motion showStill:picture];
            sg_stillOf = identity;
        }
        return YES;
    }
    clearForReplacement(YES, YES);
    showBehind(sg_track, @"the cover's still", ^(SGRPlayerMotionView *motion) { [motion showStill:picture]; });
    sg_stillOf = identity;
    SGLog(@"redesign player: no clip for %@, its cover as the still, %.0f px wide", sg_track, picture.size.width * picture.scale);
    return YES;
}

void SGRPlayerStillChanged(void) {
    if (SGRPlayerStillOn()) {
        if (SGRPlayerAnimatedVisualiserOn()) SGSetEnabled(SGRKeyPlayerAnimatedVisualiser, NO);
        showStill();
    } else if (sg_stillOf) clear(YES);
    SGRPlayerVisualiserUpdate();
}

BOOL SGRPlayerAnimatedVisualiserOn(void) {
    return SGHidden(SGRKeyPlayerAnimatedVisualiser);
}

// The still goes first, so the Visualizer finds the cover back and the field uncovered.
void SGRPlayerAnimatedVisualiserChanged(void) {
    if (SGRPlayerAnimatedVisualiserOn() && SGRPlayerStillOn()) {
        SGSetEnabled(SGRKeyPlayerAnimatedStill, NO);
        SGRPlayerStillChanged();
    }
    SGRPlayerVisualiserUpdate();
}

// Both switches saved on (an older build, or set from two places at once): the full-screen cover stays.
void SGRPlayerReconcileFallbackSwitches(void) {
    if (SGRPlayerStillOn() && SGRPlayerAnimatedVisualiserOn()) SGSetEnabled(SGRKeyPlayerAnimatedVisualiser, NO);
}

BOOL SGRPlayerVisualiserFallbackWanted(void) {
    return SGRPlayerAnimatedVisualiserOn() && !SGRPlayerStillOn() && sg_track && [sg_noClip isEqualToString:sg_track] && clipWanted();
}

void SGRPlayerMotionLyricsChanged(void) {
    [sg_motion setBlurred:SGRPlayerLyricsOpen() animated:sg_motion.window != nil];
    SGRPlayerBackdropLyricsChanged();
}

static void videoSurface(id unit, BOOL attached) {
    dispatch_async(dispatch_get_main_queue(), ^{
        BOOL was = videoShowing();
        if (attached) [sg_videos addObject:unit];
        else [sg_videos removeObject:unit];
        if (videoShowing() == was) return;
        SGLog(@"redesign player: Spotify's video %@", was ? @"gone, the clip looked up again" : @"showing, the clip away");
        [sg_follower restart];
    });
}

// A skip on screen leaves the last clip a moment for the next one's to cross over, and the same track
// walked again (its Canvas came late) keeps its clip until the new one does. Otherwise the clip goes: at
// once where it cannot be seen, with a fade for Spotify's video, under Reduce Motion, Low Power Mode or serious heat, and
// when the background is not Animated.
static BOOL beginTrack(NSString *track) {
    sg_track = track;
    sg_begun++;
    // Until this walk says there is no clip; a still showing for the same track stays as a clip would.
    sg_noClip = nil;
    // The Visualizer standing in for the last track's missing clip goes with the lookup this walk starts.
    SGRPlayerVisualiserUpdate();
    BOOL wanted = consumerVisible() && clipWanted();
    if (wanted && [track isEqualToString:sg_shown]) return YES;
    // The clip on screen is another track's: it waits kHandOver for the next one to cross over it, but its
    // recovery stops here, at once, so a failure during the handover is not played again behind the next track.
    [sg_motion handover];
    [sg_coverClip handover];
    if (!wanted || !seen(sg_motion ?: sg_coverClip)) {
        clear(YES);
        return wanted;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kHandOver * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if ([track isEqualToString:sg_track] && (sg_motion || sg_coverClip) && ![track isEqualToString:sg_shown]) clear(YES);
    });
    return YES;
}

void SGRPlayerBackgroundDidChange(void) {
    // A clip left playing under black or a photo would keep the cover masked until the next track.
    clear(YES);
    [sg_follower restart];
    SGRPlayerVisualiserUpdate();
}

#pragma mark - the ⋯ menu's switch (Shared/Player/SpeedPitch.h)

// Fluid, Animated and the Visualizer share the field, so the menu moves between them without a restart. The
// other backgrounds are a field of another kind, chosen on the Player page (PlayerSettings.m).
BOOL SGPlayerMenuOffersAnimatedArtwork(void) {
    SGRPlayerBackgroundKind kind = SGRPlayerBackground();
    return sg_follower && kind >= SGRPlayerBackgroundFluid && SGRPlayerBackgroundFromArtwork(kind);
}

BOOL SGPlayerMenuAnimatedArtwork(void) {
    return SGRPlayerBackground() == SGRPlayerBackgroundAnimated;
}

void SGPlayerMenuSetAnimatedArtwork(BOOL on) {
    if (!SGPlayerMenuOffersAnimatedArtwork() || on == SGPlayerMenuAnimatedArtwork()) return;
    SGRSetPlayerBackground(on ? SGRPlayerBackgroundAnimated : SGRPlayerBackgroundFluid);
    SGLog(@"redesign player: animated artwork switched %@ from the menu", on ? @"on" : @"off");
    // The playing track is let go, and looked up again when switched on.
    clear(YES);
    [sg_follower restart];
    // From the Visualizer, whose hills go.
    SGRPlayerVisualiserUpdate();
}

%group SGRVideoSurfaces
%hook _TtC28NowPlaying_ContentLayersImpl24HorizontalVideoViewModel
- (void)videoSurfaceDidAttachVideo:(id)surface {
    %orig;
    videoSurface(self, YES);
}
- (void)videoSurfaceDidDetachVideo:(id)surface {
    %orig;
    videoSurface(self, NO);
}
%end

%hook _TtC28NowPlaying_ContentLayersImpl31VerticalVideoCellImplementation
- (void)videoSurfaceDidAttachVideo:(id)surface {
    %orig;
    videoSurface(self, YES);
}
- (void)videoSurfaceDidDetachVideo:(id)surface {
    %orig;
    videoSurface(self, NO);
}
%end

%hook _TtC22NowPlaying_ElementsKit14VideoElementUI
- (void)videoSurfaceDidAttachVideo:(id)surface {
    %orig;
    videoSurface(self, YES);
}
- (void)videoSurfaceDidDetachVideo:(id)surface {
    %orig;
    videoSurface(self, NO);
}
%end
%end

%ctor {
    if (!SGRedesignedUI()) return;
    SGRPlayerReconcileFallbackSwitches();
    // The artwork's own choice under black or a photo, so going back to Animated finds the follower ready.
    SGRPlayerBackgroundKind background = SGRPlayerArtworkBackground();
    if (background < SGRPlayerBackgroundFluid) return;
    sg_videos = [NSHashTable weakObjectsHashTable];
    // Here rather than on the clip's view, which is gone while they hold it off: the track is walked again
    // as these conditions change. Power and thermal state can be reported off the main thread, which must not wait for main
    // (AGENTS.md), so the observer takes it where it is posted and hops.
    __block BOOL allowed = motionAllowed();
    for (NSNotificationName name in @[NSProcessInfoPowerStateDidChangeNotification, NSProcessInfoThermalStateDidChangeNotification,
                                      UIAccessibilityReduceMotionStatusDidChangeNotification]) {
        [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:nil usingBlock:^(NSNotification *note) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (motionAllowed() == allowed) return;
                allowed = !allowed;
                SGLog(@"redesign player: animated artwork %@", allowed ? @"allowed again, the clip looked up" : @"held off by Reduce Motion, Low Power Mode or serious heat, Fluid shows");
                [sg_follower restart];
            });
        }];
    }
    // The Visualizer standing in for a missing clip goes when the iPhone gets hot, and comes back when it cools.
    [NSNotificationCenter.defaultCenter addObserverForName:NSProcessInfoThermalStateDidChangeNotification object:nil queue:nil
                                                usingBlock:^(NSNotification *note) { dispatch_async(dispatch_get_main_queue(), ^{ SGRPlayerVisualiserUpdate(); }); }];
    sg_follower = [[SGMotionFollower alloc] initWithBegin:^BOOL(NSString *uri, SPTPlayerState *state) {
        return beginTrack(uri);
    } found:^(NSString *uri, NSURL *file) {
        if (!consumerVisible()) return;
        if (file) {
            show(uri, file);
            return;
        }
        sg_noClip = uri;
        if (!showStill()) clear(YES);
        SGRPlayerVisualiserUpdate();
    }];
    for (NSNotificationName name in @[UIApplicationWillResignActiveNotification, UIApplicationDidBecomeActiveNotification,
                                      SGRPlayerVisibilityDidChangeNotification]) {
        [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:nil usingBlock:^(NSNotification *note) {
            if ([note.name isEqualToString:UIApplicationWillResignActiveNotification]) sg_inactive = YES;
            else if ([note.name isEqualToString:UIApplicationDidBecomeActiveNotification]) sg_inactive = NO;
            // Invalidate posters as well as both tickets, including when no player state is available.
            sg_begun++;
            if (!consumerVisible()) clear(NO);
            [sg_follower restart];
        }];
    }
    // A larger cover, or the track's own after the last one's, can make the still: the Kit posts on main.
    [NSNotificationCenter.defaultCenter addObserverForName:SGRNowPlayingArtworkDidChangeNotification object:nil queue:nil
                                                usingBlock:^(NSNotification *note) { showStill(); }];
    %init(SGRVideoSurfaces);
}
