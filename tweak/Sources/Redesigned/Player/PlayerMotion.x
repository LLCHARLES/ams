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
// A cover shorter than the screen (the tall 3:4 one) keeps its own pixels down to near its bottom edge and dissolves
// only over the last of it, as the Music app's does: measured on its player, the cover's dark middle is still dark
// at the cover's bottom edge and only fades into its surroundings below it. Dissolving over the last tenth, into
// the foot's colors, washed the cover out above its own edge (a fog) where the Music app's stays sharp.
static const CGFloat kTallFootFrom = 0.965;
// The share of the poster's (and the playing clip's) height, at its bottom, whose colors the foot is, each column's
// own. The Music app carries what runs down a column of the cover's lower part on to the screen's foot: a lightning
// bolt down the left of a black cover ending a little above the cover's edge kept the left of its foot blue, where the
// last 3% of rows read black there and the foot went a flat gray. The lower quarter holds such a bolt in any frame.
static const CGFloat kFootRows = 0.25;
// Rows read across that band of each clip frame (liveRow).
static const size_t kFootRowSamples = 16;
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
// The dim's band at the top: over the status bar, and down to this share of the screen while the header shows
// something to read, so its text gets it, then gone over kDimFade points (eased as the next constants say).
static const CGFloat kDimTop = 0.14, kDimFade = 108;
// The Music app's top is not a band with an edge: it is darkest at the very top (kDimTopShare of the dim) and
// lightens all the way down. The dim is this share of itself where the band ends (over the status bar), whole only at the top edge, and from there
// it fades out over kDimFade points along a curve (kDimCurve: 1 is a line, more lingers dark near the top and
// clears sooner). Measured on the Music app's player over a white cover (3x, 874 pt): the top is gone 167 pt down,
// and the lower half is untouched down to 23% of the screen, then darkens along x^1.75 (x the share of the way from
// there to the bottom) to the bottom's end, with no knee at the title. The dim and the black over it (kDeepenBottom)
// each follow that curve (kDimEase) from kBottomStart of the screen to its foot, so together they come to the
// measured 0.63 over a white cover.
static const CGFloat kDimTopShare = 0.9, kDimBandShare = 0.49, kDimCurve = 1.5, kDimEase = 1.75, kBottomStart = 0.23;
// How many steps the top's fade is drawn in, and the curve down the lower half.
enum { kDimSteps = 4, kRampSteps = 8 };
// The black over the dim at the bottom of the screen, from none where the lower half starts to darken: the Music
// app's player darkens toward its foot (issue #39).
static const CGFloat kDeepenBottom = 0.40;
// Under a cover shorter than the screen the veil carries the foot, and the Music app's colors there hold nearly their
// brightness to the bottom: over a pink animated cover (3x, 874 pt) they lost an eighth from the times to the foot,
// where the deepening above took two fifths. There the deepening is this much (the lyrics and Increase Contrast keep
// kDeepenBottom).
static const CGFloat kDeepenVeiled = 0.12;
// The Music app's player gets dark only a little at a time, down the whole lower half of the screen, and ends in the
// cover's own color rather than a gray one. The dim over the clip is eased to this share of what the rule
// (SGRPlayerClipDim) asks for, and it grows down the whole lower half (kBottomStart), not over kBlurRamp. Increase
// Contrast and the lyrics keep the full dim, so their contrast is not given up.
static const CGFloat kDimSoften = 0.7;
// A clip that is black or nearly so ends in a gray, not in black: the Music app's player, over a black cover, rises
// from the cover's own black at 27% of the screen to a gray of 17 of 255 at its foot, along x^1.5 (x the share of the
// way from there to the bottom; measured at 3x, 874 pt). It is white over the clip, kLiftFoot of it at the foot, and
// only as far as the clip is black: whole up to kLiftDark of linear luminance (the clip's bright end, as the dim
// reads it, so a black cover with a white sleeve's lettering is still one) and gone from kLiftNone up. A colored
// cover (measured over a dark blue and a dark pink one, bright end 0.15 to 0.25) ends in its own color on the Music
// app's player; the gray lift turned it gray and lighter. Not behind the lyrics.
static const CGFloat kLiftFrom = 0.27, kLiftEase = 1.5, kLiftFoot = 0.066, kLiftDark = 0.04, kLiftNone = 0.12;
// What the Music app's player draws below a cover that is shorter than the screen (its tall 3:4 cover): not the
// poster's last rows stretched down, which stand as a vertical streak, but the cover's foot blurred more the further
// down it goes, and darker. Measured on the Music app's player over an animated cover (3x, 874 pt) and fitted: the
// foot's colors smoothed along the width by a Gaussian of kVeilNear of the width, and from kVeilCrossFrom to
// kVeilCrossTo points below the cover's bottom taken over by the same smoothed by kVeilWide and pulled kVeilMean of
// the way to the foot's mean color, then brought row by row to the luma kVeilFootLuma says.
// It is a small picture (kVeilColumns by kVeilRows) the layer stretches smoothly, drawn once for a cover and a
// layout. It comes in over the clip's last tenth, as the clip dissolves into it.
// Fitted again against the Music app's center-to-side brightness below a dark blue cover (rms error 0.07 against
// 0.65 before): the edge's colors keep their own columns (kVeilNear) and are taken over from the cover's bottom
// edge (kVeilCrossFrom 0) down to kVeilCrossTo. The mean the far color is pulled to weighs each column by its
// brightness plus kVeilMeanFloor, so a dark middle does not pull a bright cover's sides down to it.
// The Music app keeps each column's own color down to the foot: over a black cover with a blue lightning bolt down its
// left side (3x, 874 pt) the left columns stayed blue (106 of 255) to the bottom while the right ones stayed black, where
// a far color pulled 0.67 of the way to the foot's mean cut the bolt off under the title (47). Fitted on that frame: a
// wide smoothing of 0.25 of the width, and 0.2 of the way to the mean (rms 0.020, against 0.030 before).
static const CGFloat kVeilNear = 0.03, kVeilWide = 0.25, kVeilMean = 0.2, kVeilMeanFloor = 0.5;
// Against the Music app's player over a pink animated cover, its colors had come to the mean 76 pt below the cover's
// bottom, where the cover's own dark and light columns still ran on down here: taken over by kVeilCrossTo 70, not 120.
static const CGFloat kVeilCrossFrom = 0, kVeilCrossTo = 70;
// How light the veil ends. Measured on the Music app's player over three animated covers (3x, 874 pt: a light blue and
// pink collage, a dark pink photo, a dark blue one), the foot ends at one luma, 44 to 50 of 255, in each cover's own
// hue, however light or dark the cover's foot was, and gets there in a straight line from the cover's bottom edge (the
// collage's sides: 117, 101, 80, 59 and 47 at 1, 76, 163, 250 and 316 pt below it). A fixed black over the dim and the
// deepening ended a dark cover a third too light and a light one too dark, and darkened late, so the controls stood on
// the cover's colors and the foot came in under them. So each row of the veil takes the luma that straight line puts
// there as it will be seen, the dim and the deepening over it included (veilShade), from what shows at the cover's
// edge to the foot's luma (kVeilFootShare) at the bottom of the screen, scaled by at most kVeilGainLeast to kVeilGainMost of its own.
// The line ends at the bottom of the screen (the ramp's end), not the view's: the view runs the field's bleed (600 pt)
// past it, and a line to there stood a third of the way at the screen's foot, a light cover's foot left gray at 125
// of 255 where the Music app's is 72. A light foot ends lighter than a dark one: kVeilFootShare of what shows at the
// cover's edge (the Music app's 72 under a beige wall at 184, 47 under a collage at 125), never under kVeilFootLuma
// (a dark pink and a dark blue cover end at 50 and 46), joined by a soft maximum of power kVeilFootSoft.
// A foot darker than that floor is not lifted to it: under the black and blue cover the Music app's foot ends about
// kVeilDarkLift of what shows at the cover's edge, so the floor is never more than that.
static const CGFloat kVeilFootLuma = 0.184, kVeilFootShare = 0.38, kVeilFootSoft = 4, kVeilGainLeast = 0.35, kVeilGainMost = 1.8;
static const CGFloat kVeilDarkLift = 1.3;
enum { kVeilColumns = 32, kVeilRows = 48, kVeilSamples = 16 };
// The foot follows the playing clip, not its poster: this often the clip's current frame is read for the colors of its
// last rows (AVPlayerItemVideoOutput), and the colors on screen close this share of the way to them each time, so they
// glide with the clip, as the Music app's lower part moves with its cover.
static const NSTimeInterval kLiveEvery = 1.0 / 15;
static const float kLiveFollow = 0.35f;
// The material blur under the controls tints the bottom of the player gray, which the Music app's player does not
// have: its colors run on to the bottom untouched. NO leaves the blur's view in place with no effect on it.
static const BOOL kSeamBlur = NO;
// Under a cover shorter than the screen the Music app does not cut from the sharp cover to its colors at one line: the
// cover goes soft from well above its bottom edge (over the title), more the further down, and goes on below its edge
// as itself blurred and mirrored. Replicate the blurred surface rather than attaching another video layer per mirror.
static const CGFloat kSoftFrom = 0.81, kSoftWhole = 1, kSoftRadius = 50, kSoftScale = 0.25;
// Where the blurs come in is not a straight line on the Music app's player but a curve that dips in the middle: over A Sky
// Full of Stars' animated cover its blur starts about 5% of the screen higher at the sides than in the middle, under the
// title. Each copy's mask is a circle's edge through its start in the middle and kBlurArc higher at the screen's sides
// (a radial gradient whose center lies above), not a horizontal band; below where it is whole it is whole all across.
static const CGFloat kBlurArc = 44;
// Below such a cover, as on the Music app's player, the playing clip itself is drawn mirrored at the cover's bottom edge
// and stretched kMirrorStretch times down, live, so a flash in the clip's foot runs on down to the bottom of the screen,
// under a blur of radius kSoftRadius. The mirror is whole from the cover's edge to the bottom and stands over the
// still veil, which shows only until the clip draws.
static const CGFloat kMirrorStretch = 2;
// Over it a color adjustment chosen to match the Music app's: a gradient whose alpha takes each color toward kAdjustKeep
// of itself plus kAdjustLift of white,
// from none at kAdjustFrom of the screen to whole at its foot, along x^kAdjustEase (x the share of the way from there
// to the foot). Measured on the Music app's player over Wish You Were Here's animated cover, whose white margins show
// the adjustment alone (3x, 874 pt): white starts to darken at a quarter of the screen and goes on smoothly, 0.82 of
// itself at the title, 0.39 at the foot, which that curve meets within a hundredth all the way down. Started at
// the bottom 0.5675 of the screen and 0.2 into it, and drawn along a line, it left the screen white down to below the title, which vanished in it. Its saturation (2.4 in the same
// matrix) is left out, so the mirror keeps the clip's own colors.
static const CGFloat kAdjustKeep = 0.3, kAdjustLift = 0.0651, kAdjustFrom = 0.25, kAdjustEase = 1.52;
enum { kAdjustSteps = 10 };
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
enum { kStripWide = 16 };
// The poster's last rows (kFootRows), drawn kStripWide pixels wide and one tall: RGBX bytes.
static void lastRows(CGImageRef poster, uint8_t pixels[kStripWide * 4]) {
    size_t height = CGImageGetHeight(poster), rows = MAX(1, (size_t)(height * kFootRows));
    CGImageRef strip = CGImageCreateWithImageInRect(poster, CGRectMake(0, height - rows, CGImageGetWidth(poster), rows));
    CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGContextRef context = CGBitmapContextCreate(pixels, kStripWide, 1, 8, kStripWide * 4, space, (CGBitmapInfo)kCGImageAlphaNoneSkipLast);
    CGColorSpaceRelease(space);
    CGContextSetInterpolationQuality(context, kCGInterpolationHigh);
    CGContextDrawImage(context, CGRectMake(0, 0, kStripWide, 1), strip);
    CGContextRelease(context);
    CGImageRelease(strip);
}

static NSArray *footColors(CGImageRef poster) {
    enum { kWide = kStripWide };
    uint8_t pixels[kWide * 4] = {0};
    lastRows(poster, pixels);
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

// The foot's colors as kVeilSamples floats per channel, left to right (0 to 1).
static NSData *veilRow(CGImageRef poster) {
    uint8_t pixels[kStripWide * 4] = {0};
    lastRows(poster, pixels);
    float colors[kVeilSamples * 3];
    for (int i = 0; i < kVeilSamples; i++) {
        for (int c = 0; c < 3; c++) colors[i * 3 + c] = pixels[i * 4 + c] / 255.0f;
    }
    return [NSData dataWithBytes:colors length:sizeof colors];
}

// The foot gradient's colors from the row of kVeilSamples: the mean of each group, as footColors takes them.
static NSArray *footColorsOf(NSData *rowData) {
    const float *row = rowData.bytes;
    const size_t per = kVeilSamples / kFootSamples;
    NSMutableArray *colors = [NSMutableArray arrayWithCapacity:kFootSamples];
    for (size_t s = 0; s < kFootSamples; s++) {
        CGFloat sum[3] = {0};
        for (size_t i = s * per; i < (s + 1) * per; i++) {
            for (int c = 0; c < 3; c++) sum[c] += row[i * 3 + c];
        }
        [colors addObject:(__bridge id)[UIColor colorWithRed:sum[0] / per green:sum[1] / per blue:sum[2] / per alpha:1].CGColor];
    }
    return colors;
}

// The colors of a clip frame's last rows (kFootRows of its height), kVeilSamples across, as floats; NO for a frame that
// is not BGRA or cannot be read.
static BOOL liveRow(CVPixelBufferRef buffer, float out[kVeilSamples * 3]) {
    if (CVPixelBufferGetPixelFormatType(buffer) != kCVPixelFormatType_32BGRA) return NO;
    if (CVPixelBufferLockBaseAddress(buffer, kCVPixelBufferLock_ReadOnly) != kCVReturnSuccess) return NO;
    const uint8_t *base = CVPixelBufferGetBaseAddress(buffer);
    size_t width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer), stride = CVPixelBufferGetBytesPerRow(buffer);
    BOOL ok = base && width >= kVeilSamples && height > 0;
    if (ok) {
        size_t rows = MAX(1, (size_t)(height * kFootRows)), first = height - rows;
        size_t stepY = MAX(1, rows / kFootRowSamples), stepX = MAX(1, width / (kVeilSamples * 8));
        for (size_t j = 0; j < kVeilSamples; j++) {
            size_t from = j * width / kVeilSamples, to = (j + 1) * width / kVeilSamples;
            double sum[3] = {0};
            size_t count = 0;
            for (size_t y = first; y < height; y += stepY) {
                const uint8_t *line = base + y * stride;
                for (size_t x = from; x < to; x += stepX) {
                    const uint8_t *pixel = line + x * 4;
                    sum[0] += pixel[2];
                    sum[1] += pixel[1];
                    sum[2] += pixel[0];
                    count++;
                }
            }
            for (int c = 0; c < 3; c++) out[j * 3 + c] = count ? (float)(sum[c] / (count * 255.0)) : 0;
        }
    }
    CVPixelBufferUnlockBaseAddress(buffer, kCVPixelBufferLock_ReadOnly);
    return ok;
}

static CGFloat smoothStep(CGFloat from, CGFloat to, CGFloat at) {
    CGFloat u = MIN(1, MAX(0, (at - from) / (to - from)));
    return u * u * (3 - 2 * u);
}

// `row` smoothed along its width by a Gaussian of `sigma` (a share of the width), at column `u` (0 to 1), each end
// averaging only what is there.
static void smoothedAt(const float *row, CGFloat sigma, CGFloat u, CGFloat out[3]) {
    CGFloat sum[3] = {0}, weights = 0;
    for (int j = 0; j < kVeilSamples; j++) {
        CGFloat x = (j + 0.5) / kVeilSamples, w = exp(-0.5 * pow((u - x) / sigma, 2));
        weights += w;
        for (int c = 0; c < 3; c++) sum[c] += w * row[j * 3 + c];
    }
    for (int c = 0; c < 3; c++) out[c] = sum[c] / weights;
}

// The veil's picture for a view `width` wide and `total` tall whose cover ends at `bottom`, drawn from `seam` down: its
// rows run from the seam to the foot of the view. Premultiplied, so the top rows, where it comes in over the clip's
// dissolve, are clear. The caller releases it.
// What the dim and the deepening over the veil leave of it (veilShade), as SGRPlayerMotionView's layout and dim set them:
// their opacities, where their ramp down the lower half starts and ends, and whether the dim is whole at every stop
// (the lyrics).
typedef struct {
    CGFloat dim, deepen, rampFrom, rampTo;
    BOOL wholeDim;
} SGRVeilShade;

// The share of a row at `y` the dim and the deepening leave: each is black along kDimEase from rampFrom to rampTo.
static CGFloat veilShade(SGRVeilShade shade, CGFloat y) {
    CGFloat span = MAX(1, shade.rampTo - shade.rampFrom), r = pow(MIN(1, MAX(0, (y - shade.rampFrom) / span)), kDimEase);
    return (1 - shade.dim * (shade.wholeDim ? 1 : r)) * (1 - shade.deepen * r);
}

static CGImageRef veilImage(NSData *rowData, CGFloat seam, CGFloat bottom, CGFloat total, SGRVeilShade shade) {
    const float *row = rowData.bytes;
    CGFloat mean[3] = {0}, weights = 0;
    for (int j = 0; j < kVeilSamples; j++) {
        CGFloat w = kVeilMeanFloor + 0.299 * row[j * 3] + 0.587 * row[j * 3 + 1] + 0.114 * row[j * 3 + 2];
        weights += w;
        for (int c = 0; c < 3; c++) mean[c] += w * row[j * 3 + c];
    }
    for (int c = 0; c < 3; c++) mean[c] /= weights;
    CGFloat edgeShade = veilShade(shade, bottom), run = MAX(1, MIN(total, shade.rampTo) - bottom);
    uint8_t *pixels = calloc(kVeilColumns * kVeilRows * 4, 1);
    // Each column's two colors, the near and the far, once for every row.
    CGFloat narrowAt[kVeilColumns][3], farAt[kVeilColumns][3];
    for (int k = 0; k < kVeilColumns; k++) {
        CGFloat u = (k + 0.5) / kVeilColumns, wide[3];
        smoothedAt(row, kVeilNear, u, narrowAt[k]);
        smoothedAt(row, kVeilWide, u, wide);
        for (int c = 0; c < 3; c++) farAt[k][c] = wide[c] * (1 - kVeilMean) + mean[c] * kVeilMean;
    }
    // Where the line ends: from the luma at the cover's edge as it is seen (kVeilFootShare).
    CGFloat edgeLuma = 0;
    for (int k = 0; k < kVeilColumns; k++) edgeLuma += 0.299 * narrowAt[k][0] + 0.587 * narrowAt[k][1] + 0.114 * narrowAt[k][2];
    edgeLuma = edgeLuma / kVeilColumns * edgeShade;
    CGFloat floorLuma = MIN(kVeilFootLuma, kVeilDarkLift * edgeLuma);
    CGFloat footLuma = pow(pow(kVeilFootShare * edgeLuma, kVeilFootSoft) + pow(floorLuma, kVeilFootSoft), 1 / kVeilFootSoft);
    for (int r = 0; r < kVeilRows; r++) {
        CGFloat y = seam + (r + 0.5) / kVeilRows * (total - seam), d = MAX(0, y - bottom);
        CGFloat across = smoothStep(kVeilCrossFrom, kVeilCrossTo, d);
        CGFloat enter = bottom > seam ? smoothStep(seam, bottom, y) : 1;
        // The row's colors, and their mean luma: one gain for the whole row keeps its columns' light and dark.
        CGFloat colors[kVeilColumns][3], luma = 0;
        for (int k = 0; k < kVeilColumns; k++) {
            for (int c = 0; c < 3; c++) colors[k][c] = narrowAt[k][c] * (1 - across) + farAt[k][c] * across;
            luma += 0.299 * colors[k][0] + 0.587 * colors[k][1] + 0.114 * colors[k][2];
        }
        luma = MAX(0.01, luma / kVeilColumns);
        // The straight line from what shows at the cover's edge to the foot's luma, as seen through the dim and the
        // deepening at this row.
        CGFloat along = MIN(1, d / run), seen = luma * edgeShade * (1 - along) + footLuma * along;
        CGFloat gain = MIN(kVeilGainMost, MAX(kVeilGainLeast, seen / (luma * MAX(0.05, veilShade(shade, y)))));
        for (int k = 0; k < kVeilColumns; k++) {
            uint8_t *pixel = pixels + (r * kVeilColumns + k) * 4;
            for (int c = 0; c < 3; c++) {
                CGFloat color = colors[k][c] * gain;
                pixel[c] = (uint8_t)lrint(MIN(1, MAX(0, color * enter)) * 255);
            }
            pixel[3] = (uint8_t)lrint(enter * 255);
        }
    }
    CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGContextRef context = CGBitmapContextCreate(pixels, kVeilColumns, kVeilRows, 8, kVeilColumns * 4, space,
                                                 kCGBitmapByteOrder32Big | kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(space);
    CGImageRef image = CGBitmapContextCreateImage(context);
    CGContextRelease(context);
    free(pixels);
    return image;
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
    CAReplicatorLayer *_soft;
    CAGradientLayer *_adjust, *_adjustLift;   // the Music app's color adjustment over the mirror (kAdjustKeep)
    CALayer *_softPicture;
    AVPlayerLayer *_softClip;
    CAGradientLayer *_foot;   // the colors of the poster's last rows, from side to side, from the seam down
    SGRVeilShade _veilShade;   // what the veil's picture was drawn for of the dim and the deepening over it
    CGFloat _rampFrom, _rampTo;   // the dim's and the deepening's ramp down the lower half, as last laid out
    CALayer *_veil;   // under a cover shorter than the screen: the foot blurred, more the further down, over _foot
    NSData *_veilRow;   // the foot's colors now (the poster's last rows at first, then the clip's), kVeilSamples (floats) left to right
    AVPlayerItemVideoOutput *_liveOutput;   // reads the playing clip's frames, on the item it is on
    AVPlayerItem *_liveItem;
    NSTimer *_liveTimer;
    CGRect _veilFor;   // the layout _veil's picture was drawn for (seam, cover's bottom, width, height of the view)
    CAGradientLayer *_dim;   // black over the clip's top and from above the title down, as dark as the clip is bright
    CAGradientLayer *_deepen;   // more black over the dim, from where it is whole down to the bottom of the screen
    CAGradientLayer *_lift;   // white over a dark clip's lower part, so a black one ends in the Music app's gray
    CAGradientLayer *_scrim;   // a still's only: black from the top fading out under the header's controls
    NSMutableData *_luminances;   // of the frames measured so far
    BOOL _lyricsUp;
    BOOL _dimTopOnly;   // the dim's colors are the band's only (dimColors)
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
// The dim's stops, top to bottom (15 of them; SGRPlayerMotionView's layout puts each at its place): the very top
// (whole), the end of the band over the status bar (kDimBandShare), kDimSteps down the fade to nothing, where the
// lower half starts (nothing), and kRampSteps down it to the whole dim at the foot of the screen. `whole` (the
// lyrics, which run down the whole screen) is black at every stop; `topOnly` (under the color adjustment,
// kAdjustKeep) keeps the band and leaves out the ramp.
static NSArray *dimColors(BOOL whole, BOOL topOnly) {
    NSMutableArray *colors = [NSMutableArray arrayWithCapacity:3 + kDimSteps + kRampSteps];
    void (^add)(CGFloat) = ^(CGFloat alpha) {
        [colors addObject:(__bridge id)[UIColor colorWithWhite:0 alpha:whole ? 1 : alpha].CGColor];
    };
    add(kDimTopShare);
    add(kDimBandShare);
    for (int i = 1; i <= kDimSteps; i++) add(kDimBandShare * pow(1 - (CGFloat)i / kDimSteps, kDimCurve));
    add(0);
    for (int j = 1; j <= kRampSteps; j++) add(topOnly ? 0 : pow((CGFloat)j / kRampSteps, kDimEase));
    return colors;
}

// The black over the dim: the same curve down the lower half, from nothing to whole (its opacity is kDeepenBottom).
static NSArray *deepenColors(void) {
    NSMutableArray *colors = [NSMutableArray arrayWithCapacity:1 + kRampSteps];
    [colors addObject:(__bridge id)UIColor.clearColor.CGColor];
    for (int j = 1; j <= kRampSteps; j++) [colors addObject:(__bridge id)[UIColor colorWithWhite:0 alpha:pow((CGFloat)j / kRampSteps, kDimEase)].CGColor];
    return colors;
}

// The adjustment's stops (kAdjustEase): nothing where it starts, then the curve to whole, `white` at `alpha` when whole.
static NSArray *adjustColors(CGFloat white, CGFloat alpha) {
    NSMutableArray *colors = [NSMutableArray arrayWithCapacity:1 + kAdjustSteps];
    for (int j = 0; j <= kAdjustSteps; j++)
        [colors addObject:(__bridge id)[UIColor colorWithWhite:white alpha:alpha * pow((CGFloat)j / kAdjustSteps, kAdjustEase)].CGColor];
    return colors;
}

// The white that lifts a dark clip's foot: nothing where it starts, then the curve to whole (its opacity is kLiftFoot).
static NSArray *liftColors(void) {
    NSMutableArray *colors = [NSMutableArray arrayWithCapacity:1 + kRampSteps];
    [colors addObject:(__bridge id)UIColor.clearColor.CGColor];
    for (int j = 1; j <= kRampSteps; j++) [colors addObject:(__bridge id)[UIColor colorWithWhite:1 alpha:pow((CGFloat)j / kRampSteps, kLiftEase)].CGColor];
    return colors;
}

static UIBlurEffect *blurEffect(void) {
    return [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialDark];
}

// `mask` comes in from `from` to `to` (points down a layer `width` by `total`) in the middle, kBlurArc higher at the sides.
static void arcRamp(CAGradientLayer *mask, CGFloat width, CGFloat total, CGFloat from, CGFloat to) {
    CGFloat half = width / 2, radius = (half * half + kBlurArc * kBlurArc) / (2 * kBlurArc), outer = radius + MAX(1, to - from);
    if (width <= 0 || total <= 0) return;
    mask.type = kCAGradientLayerRadial;
    mask.startPoint = CGPointMake(0.5, (from - radius) / total);
    mask.endPoint = CGPointMake(0.5 + outer / width, (from - radius + outer) / total);
    mask.locations = @[@(radius / outer), @1];
}

static CAReplicatorLayer *softCopy(void) {
    CAReplicatorLayer *copy = [CAReplicatorLayer layer];
    copy.anchorPoint = CGPointZero; // layoutSoftFor: reflects about the cover's edge in top-origin coordinates.
    copy.instanceCount = 2;
    copy.hidden = YES;
    CAFilter *blur = [NSClassFromString(@"CAFilter") filterWithType:@"gaussianBlur"];
    if (blur) {
        [blur setValue:@(kSoftRadius) forKey:@"inputRadius"];
        // The copy's edges blur against themselves, not against the clear around it.
        [blur setValue:@YES forKey:@"inputNormalizeEdges"];
        copy.filters = @[blur];
        copy.rasterizationScale = kSoftScale;
        copy.shouldRasterize = YES;
    }
    CAGradientLayer *mask = [CAGradientLayer layer];
    mask.colors = @[(id)UIColor.clearColor.CGColor, (id)UIColor.blackColor.CGColor];
    copy.mask = mask;
    return copy;
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
    _veil = [CALayer layer];
    _veil.magnificationFilter = kCAFilterLinear;
    _veil.hidden = YES;
    [_picture.layer addSublayer:_veil];
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
    _soft = softCopy();
    _softPicture = [CALayer layer];
    _softPicture.contentsGravity = kCAGravityResizeAspectFill;
    _softPicture.masksToBounds = YES;
    [_soft addSublayer:_softPicture];
    [_picture.layer addSublayer:_soft];
    _adjust = [CAGradientLayer layer];
    _adjust.colors = adjustColors(0, 1 - kAdjustKeep);
    _adjust.hidden = YES;
    [_picture.layer addSublayer:_adjust];
    _adjustLift = [CAGradientLayer layer];
    _adjustLift.colors = adjustColors(1, kAdjustLift);
    _adjustLift.compositingFilter = @"plusL";
    _adjustLift.hidden = YES;
    [_picture.layer addSublayer:_adjustLift];
    _dim = [CAGradientLayer layer];
    _dim.colors = dimColors(NO, NO);
    _dim.opacity = kDimLeast;
    [_picture.layer addSublayer:_dim];
    _deepen = [CAGradientLayer layer];
    _deepen.colors = deepenColors();
    _deepen.opacity = kDeepenBottom;
    [_picture.layer addSublayer:_deepen];
    _lift = [CAGradientLayer layer];
    _lift.colors = liftColors();
    _lift.opacity = 0;
    [_picture.layer addSublayer:_lift];
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
    [self dropLive];
    [_player pause];
    [_looper disableLooping];
    _clip.player = nil;
    _softClip.player = nil;
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
    BOOL tall = height < screen - 0.5;
    CGFloat from = tall ? kTallFootFrom : kFootFrom;
    CGFloat seam = round(height * from), blurFrom = MIN(seam, round(screen * kBlurByControls));
    _picture.frame = bounds;
    _seamBlur.frame = bounds;
    _seamBlur.maskView.frame = bounds;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _still.frame = CGRectMake(0, 0, width, height);
    _clip.frame = _still.bounds;
    _clipMask.frame = _still.bounds;
    _clipMask.locations = @[@0, @(from), @1];
    _foot.frame = CGRectMake(0, seam, width, MAX(0, total - seam));
    // A cover shorter than the screen gets the blurred foot below it, a Canvas (which fills the screen) none.
    BOOL shorter = _veilRow && height < screen - 0.5 && total > seam;
    _veil.hidden = !shorter;
    [self updateDeepen];
    [self layoutSoftFor:shorter width:width height:height total:total];
    if (shorter) {
        _veil.frame = _foot.frame;
        CGRect geometry = CGRectMake(seam, height, width, total);
        if (!CGRectEqualToRect(geometry, _veilFor)) {
            _veilFor = geometry;
            _veilShade.rampTo = -1;   // drawn again below, once the ramp is laid out
        }
    }
    _dim.frame = bounds;
    _deepen.frame = bounds;
    _lift.frame = bounds;
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
    CGFloat topEnd = MIN(bandEnd, dimFrom);
    CGFloat fadeEnd = topEnd + kDimFade, rampFrom = MAX(fadeEnd, screen * kBottomStart);
    NSMutableArray *stops = [NSMutableArray arrayWithObjects:@0, at(topEnd), nil];
    for (int i = 1; i <= kDimSteps; i++) [stops addObject:at(topEnd + (fadeEnd - topEnd) * i / kDimSteps)];
    [stops addObject:at(rampFrom)];
    for (int j = 1; j <= kRampSteps; j++) [stops addObject:at(rampFrom + (screen - rampFrom) * j / kRampSteps)];
    _dim.locations = stops;
    NSMutableArray *deepen = [NSMutableArray arrayWithObject:at(rampFrom)];
    for (int j = 1; j <= kRampSteps; j++) [deepen addObject:at(rampFrom + (screen - rampFrom) * j / kRampSteps)];
    _deepen.locations = deepen;
    _rampFrom = rampFrom;
    _rampTo = screen;
    [self redrawVeilIfShaded];
    CGFloat liftFrom = screen * kLiftFrom;
    NSMutableArray *lift = [NSMutableArray arrayWithObject:at(liftFrom)];
    for (int j = 1; j <= kRampSteps; j++) [lift addObject:at(liftFrom + (screen - liftFrom) * j / kRampSteps)];
    _lift.locations = lift;
    _seamMask.frame = bounds;
    _seamMask.locations = @[at(blurFrom), at(blurFrom + kBlurRamp)];
    [CATransaction commit];
}

// Lighter under the veil (kDeepenVeiled), except behind the lyrics and under Increase Contrast.
- (void)updateDeepen {
    BOOL veiled = !_veil.hidden && !_lyricsUp && !UIAccessibilityDarkerSystemColorsEnabled();
    float opacity = (float)([self adjusted] ? 0 : veiled ? kDeepenVeiled : kDeepenBottom);
    if (_deepen.opacity != opacity) _deepen.opacity = opacity;
}

// The blurred copies over a cover shorter than the screen (kSoftFrom), none over a Canvas or in the cover. Called
// inside the layout's transaction.
- (void)layoutSoftFor:(BOOL)shorter width:(CGFloat)width height:(CGFloat)height total:(CGFloat)total {
    BOOL shown = shorter && !_inCover && height > 0;
    _soft.hidden = !shown;
    if (shown && _player && !_softClip) {
        _softClip = [AVPlayerLayer layer];
        _softClip.videoGravity = AVLayerVideoGravityResizeAspectFill;
        [_softPicture addSublayer:_softClip];
    }
    if (_softClip.player != (shown ? _player : nil)) _softClip.player = shown ? _player : nil;
    [self updateDim];
    if (!shown) return;
    _soft.frame = CGRectMake(0, 0, width, total);
    _soft.mask.frame = _soft.bounds;
    _softPicture.frame = CGRectMake(0, 0, width, height);
    _softClip.frame = _softPicture.bounds;
    CATransform3D mirror = CATransform3DMakeTranslation(0, height * (1 + kMirrorStretch), 0);
    _soft.instanceTransform = CATransform3DScale(mirror, 1, -kMirrorStretch, 1);
    NSNumber *(^at)(CGFloat) = ^NSNumber *(CGFloat y) { return @(MIN(1, MAX(0, y / total))); };
    CGFloat screen = _screenHeight > 0 ? MIN(_screenHeight, total) : total, adjustFrom = screen * kAdjustFrom;
    arcRamp((CAGradientLayer *)_soft.mask, width, total, height * kSoftFrom, height * kSoftWhole);
    NSMutableArray *adjustAt = [NSMutableArray arrayWithCapacity:1 + kAdjustSteps];
    for (int j = 0; j <= kAdjustSteps; j++) [adjustAt addObject:at(adjustFrom + (screen - adjustFrom) * j / kAdjustSteps)];
    for (CAGradientLayer *layer in @[_adjust, _adjustLift]) {
        layer.frame = CGRectMake(0, 0, width, total);
        layer.locations = adjustAt;
    }
}

// The veil's picture again from the foot's colors now, for the layout it was last placed in.
- (void)redrawVeil {
    if (_veil.hidden || !_veilRow || CGRectIsEmpty(_veilFor)) return;
    _veilShade = [self veilShadeNow];
    CGImageRef image = veilImage(_veilRow, _veilFor.origin.x, _veilFor.origin.y, _veilFor.size.height, _veilShade);
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _veil.contents = (__bridge id)image;
    [CATransaction commit];
    CGImageRelease(image);
}

// The dim and the deepening over the veil now (kVeilFootLuma).
- (SGRVeilShade)veilShadeNow {
    if ([self adjusted]) return (SGRVeilShade){0, 0, _rampFrom, _rampTo, NO};   // the ramps stand aside there
    return (SGRVeilShade){_dim.opacity, _deepen.opacity, _rampFrom, _rampTo, _lyricsUp};
}

// Whether the Music app's color adjustment is over the lower half.
- (BOOL)adjusted {
    return !_adjust.hidden && !_lyricsUp;
}

// The veil's picture again when the dim or the deepening over it changed since it was drawn.
- (void)redrawVeilIfShaded {
    SGRVeilShade now = [self veilShadeNow], was = _veilShade;
    if (fabs(now.dim - was.dim) > 0.01 || fabs(now.deepen - was.deepen) > 0.01 || fabs(now.rampFrom - was.rampFrom) > 0.5
        || fabs(now.rampTo - was.rampTo) > 0.5 || now.wholeDim != was.wholeDim) [self redrawVeil];
}

// While the clip plays, the foot takes its colors from the clip's frames. The output is on the item the player has
// now (the looper swaps items, and an output belongs to one at a time).
- (void)startLive {
    if (_liveTimer) return;
    __weak SGRPlayerMotionView *weakSelf = self;
    _liveTimer = [NSTimer timerWithTimeInterval:kLiveEvery repeats:YES block:^(NSTimer *timer) { [weakSelf liveTick]; }];
    [NSRunLoop.mainRunLoop addTimer:_liveTimer forMode:NSRunLoopCommonModes];
}

- (void)stopLive {
    [_liveTimer invalidate];
    _liveTimer = nil;
}

// Also lets the item go of the output, for a player that is being replaced or a view that is going.
- (void)dropLive {
    [self stopLive];
    [_liveItem removeOutput:_liveOutput];
    _liveItem = nil;
}

- (void)liveTick {
    AVPlayerItem *item = _player.currentItem;
    if (_inCover || !item || !_veilRow || !self.window) return;
    if (!_liveOutput) {
        _liveOutput = [[AVPlayerItemVideoOutput alloc] initWithPixelBufferAttributes:@{(id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA)}];
    }
    if (item != _liveItem) {
        [_liveItem removeOutput:_liveOutput];
        _liveItem = nil;
        if (![item.outputs containsObject:_liveOutput]) [item addOutput:_liveOutput];
        _liveItem = item;
    }
    CMTime time = [_liveOutput itemTimeForHostTime:CACurrentMediaTime()];
    if (![_liveOutput hasNewPixelBufferForItemTime:time]) return;
    CVPixelBufferRef buffer = [_liveOutput copyPixelBufferForItemTime:time itemTimeForDisplay:NULL];
    if (!buffer) return;
    float now[kVeilSamples * 3], shown[kVeilSamples * 3];
    BOOL read = liveRow(buffer, now);
    CVPixelBufferRelease(buffer);
    if (!read || _veilRow.length != sizeof shown) return;
    memcpy(shown, _veilRow.bytes, sizeof shown);
    for (int i = 0; i < kVeilSamples * 3; i++) shown[i] += (now[i] - shown[i]) * kLiveFollow;
    _veilRow = [NSData dataWithBytes:shown length:sizeof shown];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _foot.colors = footColorsOf(_veilRow);
    [self redrawVeil];
    [CATransaction commit];
}

// The picture under the video, or the whole of a still, and the share of the width the view draws it tall.
- (void)takePicture:(UIImage *)picture aspect:(CGFloat)aspect {
    _aspect = aspect;
    _foot.colors = footColors(picture.CGImage);
    _veilRow = veilRow(picture.CGImage);
    _veilFor = CGRectZero;
    _still.contents = (__bridge id)picture.CGImage;
    _softPicture.contents = _still.contents;
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
        _foot.hidden = _dim.hidden = _deepen.hidden = _seamBlur.hidden = _soft.hidden = _adjust.hidden = _adjustLift.hidden = YES;
        return;
    }
    [self measure:file poster:poster];
}

// A player and a looper over the clip's own file. The looper hands the player its own copies of the item, so
// the item is watched where the player takes it: an item that fails says so, and so does a looper that cannot
// go on. What they watch goes before another is made, so an observer never outlives the object it was put on.
- (void)build {
    [self unwatch];
    [self dropLive];
    [_player pause];
    [_looper disableLooping];
    _clip.player = nil;
    _softClip.player = nil;
    _player = [AVQueuePlayer new];
    _player.muted = YES;
    _player.preventsDisplaySleepDuringVideoPlayback = NO;
    [_player addObserver:self forKeyPath:@"currentItem" options:NSKeyValueObservingOptionInitial | NSKeyValueObservingOptionNew
                 context:&SGRPlayerMotionPlayerContext];
    _looper = [AVPlayerLooper playerLooperWithPlayer:_player templateItem:[AVPlayerItem playerItemWithURL:_file]];
    [_looper addObserver:self forKeyPath:@"status" options:0 context:&SGRPlayerMotionLooperContext];
    _clip.player = _player;
    [self setNeedsLayout];
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
    _adjust.hidden = _adjustLift.hidden = _soft.hidden || _lyricsUp || contrast;
    CGFloat dim = _lyricsUp && SGRReduceTransparency() ? 1 : SGRPlayerClipDim(brightEnd(_luminances), contrast, _lyricsUp);
    // Eased toward the Music app's look, except where the text's contrast is a setting's (Increase Contrast) or the
    // lyrics' own.
    if (!_lyricsUp && !contrast) dim *= kDimSoften;
    _dim.opacity = (float)dim;
    // Behind the lyrics their own colors stand (setBlurred:animated:).
    if (!_lyricsUp) {
        BOOL topOnly = [self adjusted];
        if (topOnly != _dimTopOnly) {
            _dimTopOnly = topOnly;
            _dim.colors = dimColors(NO, topOnly);
        }
    }
    [self updateDeepen];
    // The gray a dark clip ends in: all of it for a black one, less up to kLiftNone, none behind the lyrics.
    CGFloat bright = brightEnd(_luminances), share = MIN(1, MAX(0, (kLiftNone - bright) / (kLiftNone - kLiftDark)));
    // Under the color adjustment its own lift (kAdjustLift) stands for this one.
    _lift.opacity = _lyricsUp || !_adjust.hidden ? 0 : (float)(kLiftFoot * share);
    [self redrawVeilIfShaded];
    _scrim.opacity = (float)(contrast ? kStillScrimTop * SGRPlayerClipDim(1, YES, NO) / SGRPlayerClipDim(1, NO, NO) : kStillScrimTop);
}

// `done` runs once the clip is opaque, unless something cut the fade in short.
- (void)appear:(BOOL)animated then:(void (^)(void))done {
    _picture.alpha = 0;
    void (^apply)(void) = ^{
        self->_picture.alpha = 1;
        if (!self->_inCover && kSeamBlur) self->_seamBlur.effect = blurEffect();
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
    // Behind the lyrics the whole clip is blurred and dimmed instead (the dim's lyrics share).
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
    _dim.colors = dimColors(blurred, NO);
    _dimTopOnly = NO;
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
    if (may && _player && !_inCover && SGRPlayerIsVisible()) [self startLive];
    else [self stopLive];
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

BOOL SGRPlayerTrackHasNoClip(void) {
    return [sg_noClip isEqualToString:SGURIString(SGPlayerState().track.URI)];
}
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
static void (^sg_previewArrived)(BOOL);
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

UIView *SGRPlayerMotionPreview(void (^arrived)(BOOL)) {
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
            void (^done)(BOOL) = sg_previewArrived;
            sg_previewArrived = nil;
            if (done) done(NO);
            return;
        }
        SGMotionPoster(file, ^(UIImage *poster) {
            if (generation != sg_previewGeneration) return;
            sg_previewLooking = NO;
            sg_previewTicket = nil;
            void (^done)(BOOL) = sg_previewArrived;
            sg_previewArrived = nil;
            if (!poster || poster.size.width <= 0) {
                return;
            }
            sg_previewFile = file;
            sg_previewPoster = poster;
            SGLog(@"redesign player: the Player page's clip from %@, %@", source, file.lastPathComponent);
            if (done) done(YES);
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
static BOOL animatedBackground(void) {
    return SGRPlayerBackground() == SGRPlayerBackgroundAnimated && !videoShowing();
}

static BOOL clipWanted(void) {
    return animatedBackground() && motionAllowed();
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
    [motion setBlurred:SGRPlayerPageOpen() animated:NO];
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
    // This stand-in has its own heat switch. It needs a confirmed miss, not a decoder.
    return SGRPlayerAnimatedVisualiserOn() && !SGRPlayerStillOn() && [sg_noClip isEqualToString:sg_track]
        && consumerVisible() && animatedBackground() && !SGRReduceMotion() && !NSProcessInfo.processInfo.lowPowerModeEnabled;
}

void SGRPlayerMotionLyricsChanged(void) {
    [sg_motion setBlurred:SGRPlayerPageOpen() animated:sg_motion.window != nil];
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
    BOOL wanted = consumerVisible() && clipWanted();
    // Restarting while hidden or hot does not start a lookup or invalidate this track's answer.
    if (sg_noClip && (wanted || ![sg_noClip isEqualToString:track])) {
        sg_noClip = nil;
        SGRPlayerHoldField();
    }
    // The Visualizer standing in for the last track's missing clip goes with the lookup this walk starts.
    SGRPlayerVisualiserUpdate();
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
                BOOL nowAllowed = motionAllowed();
                if (nowAllowed != allowed) {
                    allowed = nowAllowed;
                    SGLog(@"redesign player: animated artwork %@", allowed ? @"allowed again, the clip looked up" : @"held off by Reduce Motion, Low Power Mode or serious heat, Fluid shows");
                    [sg_follower restart];
                }
                // The stand-in can ignore heat, but not Low Power Mode or Reduce Motion.
                SGRPlayerVisualiserUpdate();
            });
        }];
    }
    sg_follower = [[SGMotionFollower alloc] initWithBegin:^BOOL(NSString *uri, SPTPlayerState *state) {
        return beginTrack(uri);
    } found:^(NSString *uri, NSURL *file) {
        if (!consumerVisible()) return;
        sg_noClip = file ? nil : uri;
        SGRPlayerHoldField();
        if (file) {
            show(uri, file);
            return;
        }
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
