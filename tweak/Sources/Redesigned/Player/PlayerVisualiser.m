// Player redesign: the Visualizer background, a calm spectrum of what is playing behind the player, in the
// cover's colors, over the Fluid field held still (PlayerField.x keeps the field Fluid for this choice, as for
// Animated, so the ⋯ menu moves between the three without a restart).
//
// The sound is Spotify's output as it plays, read on the render thread through the audio effects' notify
// (SGAudioSetOutputReader, Shared/AudioEffects/AudioEffects.h) into SGRSpectrum.m's bands. Here, on the main
// thread, a display link reads the bands, brings them to a share of the song's own loudness (the loudest band of
// the last few seconds at the top, so a quiet track moves as much as a loud one), eases each band up quickly
// and down slowly, and draws two soft hills across the foot of the screen, mirrored about its middle, the kick
// in the middle and the treble at either edge: a slow one behind, a quicker one in front. Each is a gradient of
// the cover's colors (SGRPalette's flow colors, brought to one luminance) masked by a shape layer, so the render
// server does the drawing and the app only hands it two paths a frame. They are light added to the field
// (plusL), never paint over it, so a dark cover's hills are a silver mist and a bright field's are brighter
// still, and the whole fades to clear toward the tallest crest, so a peak thins to light instead of ending in an
// edge. The front hill brightens on the kick and dims over a third of a second: the beat, where the heights are
// the spectrum.
//
// It moves only while it is in a window, Spotify is in front, the player is not opening or closing, Low Power
// Mode is off and the song plays; a pause lets the hills settle and the link stops, and nothing is read from
// the sound while it is stopped. The link asks for the rate the view draws at (-drawRate): 60 frames a second
// (Bars and Halo 120 on a ProMotion screen), 30 while the lyrics, which have a link of their own, are open and
// the hills are blurred behind them, and with Reduce Motion 15, with every band easing over seconds. Its range
// reaches up to the screen's rate, so the system may run it faster for another request, and the ticks between
// draws are then skipped. While the player opens or closes the link is down, and comes back only once the
// animation is over.
//
// ponytail: the hills follow what the output is handed, which a Bluetooth headset plays a fifth of a second or
// so later. Music Haptics schedules for the output latency; do the same here if the beat looks early on AirPods.
//
// The fifth style, Lyrics, draws the same hills at a reduced height under the line being sung, large and
// centered, white at a third of its strength: the lyrics set in the player's background. The line is the one
// SGKaraokeLeadLine names for the playing track's kept lines (Shared/Lyrics/Lyrics.h), so only synced lyrics
// show; a track without them, a break or the moments before the first line are just the quieter hills. The
// text changes only when the line index does, crossfading and rising in with two labels made once, and its
// own alpha and scale breathe with the level the bands are already at. While the player's own lyrics are
// open the text is put away (the field blurs then), leaving the hills. The settings card's preview has no
// track to read, so it falls back to LyricsLook's sample lines; it uses this view's frame clock, never one
// of its own.
//
// Poster and Cut, the sixth and seventh, read the same line by the same rules and draw the same quieter hills, and
// hand the line to a stage of their own over them (PlayerLyricStages.m): the line set word by word as a type
// poster over a halftone print of the cover, or one word at a time over the cover, cut to the singing. Where
// Lyrics shows no words, they show nothing over the hills either. Their words move as soon as a word's start
// passes, so the link reads their line on every tick, not only on the ticks the hills draw. In the player, while a
// stage shows a line, the cover fades away the way a clip takes it (SGRPlayerLyricStageTakesCover, PlayerMotion.x)
// and the type sets in the band the cover sat in, kTitleClearance over the title block (the player's own sung line
// where it has room, else the title), measured from the player on each layout and each new line. The cover comes
// back as the stage shows no line, and when the view leaves the field.
//
// Threading: main thread only, but for the reader, which runs on the render thread.
// Hills retains the drawing below. Bars, Nebula, Halo and Lyrics share its envelopes and lifecycle, using
// only finite layer paths/transforms driven here. Silence stops drawing; a low-frequency timer watches for sound.
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Redesigned/Lyrics/LyricsLook.h"
#import "Shared/AudioEffects/AudioEffects.h"
#import "Shared/Lyrics/Lyrics.h"
#import "Shared/Player/PlayerEvents.h"
#import "Shared/Player/PlayerState.h"
#import "Shared/Player/SpeedPitch.h"
#import "Player.h"
#import "PlayerLyricLine.h"
#import "PlayerLyricStages.h"
#import "SGRSpectrum.h"

NSNotificationName const SGRVisualiserStyleDidChangeNotification = @"spotifyglass.visualizer.styleDidChange";

NSArray<NSString *> *SGRVisualiserStyleNames(void) { return @[SGL(@"settings.visualizer.style.choice.hills", @"Hills"), SGL(@"settings.visualizer.style.choice.bars", @"Bars"), SGL(@"settings.visualizer.style.choice.nebula", @"Nebula"), SGL(@"settings.visualizer.style.choice.halo", @"Halo"), SGL(@"settings.visualizer.style.choice.lyrics", @"Lyrics"), SGL(@"settings.visualizer.style.choice.poster", @"Poster"), SGL(@"settings.visualizer.style.choice.cut", @"Cut")]; }
NSArray<NSString *> *SGRVisualiserStyleIDs(void) { return @[@"builtin:hills", @"builtin:bars", @"builtin:nebula", @"builtin:halo", @"builtin:lyrics", SGRVisualiserPosterID, SGRVisualiserCutID]; }

NSString *SGRVisualiserStyle(void) {
    id value = [NSUserDefaults.standardUserDefaults objectForKey:SGRKeyVisualiserStyle];
    return [value isKindOfClass:NSString.class] && [SGRVisualiserStyleIDs() containsObject:value] ? value : @"builtin:hills";
}

void SGRSetVisualiserStyle(NSString *identifier) {
    if (![identifier isKindOfClass:NSString.class] || ![SGRVisualiserStyleIDs() containsObject:identifier]) return;
    NSString *value = [identifier copy];
    void (^apply)(void) = ^{
        [NSUserDefaults.standardUserDefaults setObject:value forKey:SGRKeyVisualiserStyle];
        // Only views already observing this notification change; the background choice is untouched.
        [NSNotificationCenter.defaultCenter postNotificationName:SGRVisualiserStyleDidChangeNotification object:nil];
    };
    if (NSThread.isMainThread) apply();
    else dispatch_async(dispatch_get_main_queue(), apply);
}

// The style by hand: remembered as the one shuffle returns to when it is switched off.
void SGRPickVisualiserStyle(NSString *identifier) {
    if (![identifier isKindOfClass:NSString.class] || ![SGRVisualiserStyleIDs() containsObject:identifier]) return;
    [NSUserDefaults.standardUserDefaults setObject:[identifier copy] forKey:SGRKeyVisualiserShuffleHome];
    SGRSetVisualiserStyle(identifier);
}

void SGRVisualiserShuffleChanged(void) {
    if (SGHidden(SGRKeyVisualiserShuffle)) {
        [NSUserDefaults.standardUserDefaults setObject:SGRVisualiserStyle() forKey:SGRKeyVisualiserShuffleHome];
        return;
    }
    id home = [NSUserDefaults.standardUserDefaults objectForKey:SGRKeyVisualiserShuffleHome];
    if ([home isKindOfClass:NSString.class]) SGRSetVisualiserStyle(home);
}

BOOL SGRVisualiserStandsDownFor(NSProcessInfoThermalState state) {
    return state >= NSProcessInfoThermalStateSerious && !SGHidden(SGRKeyVisualiserIgnoreHeat);
}

typedef NS_ENUM(NSUInteger, SGRVisualiserStyleKind) { SGRHills, SGRBars, SGRNebula, SGRHalo, SGRLyricsStyle, SGRPosterStyle, SGRCutStyle };

// The styles that read the sung line and draw the quieter hills under it.
static BOOL readsLyrics(SGRVisualiserStyleKind style) {
    return style == SGRLyricsStyle || style == SGRPosterStyle || style == SGRCutStyle;
}

// The two bands under 80 Hz stay out of the picture: sub-bass is quieter than the kick above it in most mixes,
// so drawn at the middle it cut a notch into the crest right under the play button.
enum { kBands = SGRSpectrumBands, kFirst = 2, kShown = kBands - kFirst, kPoints = 2 * kShown - 1 };
// The kick: the four bands from kFirst, 80 to 205 Hz; beside it the next six, 205 to 840 Hz.
enum { kKickBands = 4, kBesideBands = 6 };
// The loudness a band is drawn against: the loudest band of late at the top, kRange dB under it at the floor,
// the top falling kPeakFall dB a second after a loud passage and never under kPeakFloor, so silence stays flat.
// 30 dB rather than more: a modern mix keeps every band within 40 of the loudest, which drew one flat plateau.
static const float kRange = 30, kPeakFall = 4, kPeakFloor = -60;
// A rise toward the treble, in dB a band (three bands an octave), since music has less there: a tuning knob.
static const float kTilt = 0.6f;
// How quickly a band eases toward its level, up and down, in seconds; the hill behind is slower. With Reduce
// Motion both ease over kStillEase.
static const double kFrontUp = 0.12, kFrontDown = 0.5, kBackUp = 0.3, kBackDown = 0.9, kStillEase = 3;
// The beat: the kick's bands within kPulseRange dB of the peak light the front hill up, at once,
// and it dims again over kPulseDown; the hill never goes under kPulseFloor of its brightness.
static const float kPulseRange = 10, kPulseFloor = 0.5f;
static const double kPulseUp = 0.03, kPulseDown = 0.3;
// The luminance the hills add to the field. Under the footer's icons, where both hills lie on the field, white
// measured 7:1 on Currents in the simulator (6:1 at the very foot); 0.08 took them to 5.3:1 and 4.8:1.
static const CGFloat kGlow = 0.075;
// The glow's least saturation, for any flow color that has a hue at all (over kGrayBelow): the flow colors keep
// a dark cover's faint tint, which lifted to kGlow alone reads as silver.
static const CGFloat kGlowSaturation = 0.6, kGrayBelow = 0.08;
// No new bands for this long reads as silence (a pause, a stall, a tap that never ran).
static const double kStale = 0.3;
// The hills' height at their tallest and at rest, as shares of the screen's height; the one behind is taller.
static const CGFloat kFrontHeight = 0.2, kBackHeight = 0.26, kRestHeight = 0.008;
// The crest fade: the hills are opaque from kFadeFoot of the screen's height over the foot and clear from
// kFadeTop up, so the front hill at its tallest and the back one's crests dissolve into the field.
static const CGFloat kFadeFoot = 0.04, kFadeTop = 0.2;
// Below this every band has settled (under 2 pt at the top of the front hill), and a paused song's link can stop.
static const float kSettled = 0.02f;
// Each band shares this much with either neighbor, three times over, so one loud band is a hill and not a spike.
static const float kSpread = 0.25f;
static const NSTimeInterval kTransitionSlack = 0.05;
// Lyrics: the sung line, large and bold, three lines at the most, centered on the visible player, white at
// kLyricAlpha so it is read as the background rather than as text to read. It rises in and crossfades at each
// new line over SGRMotionFade's time, and its own alpha swells a fifth and its scale a few percent with the
// level the hills are drawn at. Under it the hills are drawn at kLyricHills of their height.
static const CGFloat kLyricSize = 44, kLyricMargin = 26, kLyricAlpha = 0.35f, kLyricRise = 14;
static const CGFloat kLyricHills = 0.5, kLyricAnchor = 0.44;
// Poster's and Cut's type in the player keeps this many points over the title block.
static const CGFloat kTitleClearance = 12;
// A line whose singing ended this long ago, with the next this far off, is an instrumental break: the words
// go and only the hills show, as the lock screen keeps the cover.
static const NSInteger kLyricBreakMs = 4000;
// The line index of a view whose labels no longer show what it last read: the next read reconciles them, even
// when it names no line (-1), which an ordinary index would take for "already shown".
static const NSInteger kLineUnread = NSIntegerMin;
// The hills' draw rate in frames a second behind the player's own lyrics and with Reduce Motion.
static const float kBehindLyricsRate = 30, kStillRate = 15;

static NSUInteger sg_readers;

// The reader on while any eligible view follows a playing stream, including silence awaiting new sound.
static void needReader(BOOL need) {
    if (need) {
        if (sg_readers++ == 0) {
            SGRSpectrumPrepare();
            SGAudioSetOutputReader(SGRSpectrumFeed);
        }
    } else if (sg_readers && --sg_readers == 0) {
        SGAudioSetOutputReader(NULL);
    }
}

static NSDictionary *noActions(void) {
    static NSDictionary *none;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSNull *off = NSNull.null;
        none = @{@"bounds": off, @"position": off, @"frame": off, @"path": off, @"colors": off};
    });
    return none;
}

@interface SGRVisualiserView : UIView <SGPlayerStateObserver>
// Where the hills stand, in points from the top: the screen's foot in the player. 0 is the bounds' foot.
@property (nonatomic) CGFloat baseline;
// The height the hills are a share of; 0 is the bounds' height.
@property (nonatomic) CGFloat screenHeight;
@property (nonatomic, readonly) BOOL blurred;
// The settings card's preview: nothing plays there, so the Lyrics style reads LyricsLook's sample lines on a
// clock of its own instead of the player's.
@property (nonatomic) BOOL sample;
// The player's own view, on its field: its Poster or Cut takes the cover's place while it shows a line. Set NO as
// it leaves, which gives the cover back.
@property (nonatomic) BOOL ownsCover;
- (void)setBlurred:(BOOL)blurred animated:(BOOL)animated;
- (void)appear:(BOOL)animated;
- (void)disappear:(void (^)(void))done;
- (void)stopPreview;
@end

@implementation SGRVisualiserView {
    UIView *_content;   // the hills, faded in and out as one
    CAGradientLayer *_backFill, *_frontFill;
    CAShapeLayer *_backShape, *_frontShape;
    CAGradientLayer *_crestFade;   // the content's mask: clear at the tallest crest, opaque over the foot
    UIVisualEffectView *_lyricsBlur;
    CADisplayLink *_link;
    NSTimer *_wakeTimer; // no display link while silent; only checks for newly published sound
    BOOL _reading, _idle, _inactive, _previewStopped;
    float _front[kBands], _back[kBands], _peak, _pulse;
    uint64_t _generation;
    CFTimeInterval _fresh, _last;
    NSUInteger _palette;
    SGRVisualiserStyleKind _style;
    CALayer *_styleLayer, *_record;
    CAGradientLayer *_styleFill, *_reflection;
    CAShapeLayer *_styleShape, *_reflectionShape, *_waveShape;
    NSArray<CAGradientLayer *> *_clouds;
    NSArray<UIColor *> *_colors;
    float _wave[SGRSpectrumWaveformSamples];
    double _phase;
    NSString *_trackURI;
    // Lyrics: the sung line in two labels, the one rising in and the one it replaces; the lines read from the
    // playing track (or the sample, in the settings card) and the line shown, so nothing is set while it stays.
    UIView *_words;      // the words' host, over the hills and away from their crest mask
    UIView *_lyricBox;   // the words' alpha and scale breathe with the bands; the labels crossfade inside it
    NSArray<UILabel *> *_lyricLabels;
    UILabel *_lyricFront;
    NSArray<SGKaraokeLine *> *_lines;
    BOOL _linesTimed;
    NSString *_linesTrack;
    NSInteger _lineIndex;
    BOOL _asked;   // the playing track was asked for lyrics once
    CFTimeInterval _sampleEpoch, _delayAt;
    NSInteger _delayMs;
    SGRLyricStage *_stage;   // Poster's or Cut's, in the words' host; nil for the other styles
}

// As PlayerMotion.x: what fades is the effect view's effect, never its alpha or an ancestor's.
static UIBlurEffect *blurEffect(void) {
    return [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialDark];
}

static CAGradientLayer *fill(CAShapeLayer *shape) {
    CAGradientLayer *layer = [CAGradientLayer layer];
    layer.actions = noActions();
    layer.startPoint = CGPointMake(0, 0.5);
    layer.endPoint = CGPointMake(1, 0.5);
    layer.compositingFilter = @"plusL";
    shape.actions = noActions();
    layer.mask = shape;
    return layer;
}

static CGFloat toLinear(CGFloat c) { return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4); }
static CGFloat toEncoded(CGFloat c) { return c <= 0.0031308 ? c * 12.92 : 1.055 * pow(c, 1 / 2.4) - 0.055; }

// `color` in its own hue at the relative luminance `luminance`, with its saturation lifted to kGlowSaturation
// so a dark red cover's glow is warm and not silver; black, near-black and gray come out gray.
static UIColor *lit(UIColor *color, CGFloat luminance) {
    CGFloat h = 0, s = 0, v = 0, r = 0, g = 0, b = 0, a = 1;
    [color getHue:&h saturation:&s brightness:&v alpha:&a];
    if (s > kGrayBelow) color = [UIColor colorWithHue:h saturation:MAX(s, kGlowSaturation) brightness:v alpha:1];
    [color getRed:&r green:&g blue:&b alpha:&a];
    CGFloat lr = toLinear(r), lg = toLinear(g), lb = toLinear(b);
    CGFloat have = 0.2126 * lr + 0.7152 * lg + 0.0722 * lb;
    if (have < 0.001) return [UIColor colorWithWhite:toEncoded(luminance) alpha:1];
    CGFloat k = luminance / have;
    return [UIColor colorWithRed:toEncoded(MIN(1, lr * k)) green:toEncoded(MIN(1, lg * k)) blue:toEncoded(MIN(1, lb * k)) alpha:1];
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.userInteractionEnabled = NO;
    self.accessibilityElementsHidden = YES;
    _peak = kPeakFloor;
    _content = [[UIView alloc] initWithFrame:frame];
    _content.userInteractionEnabled = NO;
    _content.accessibilityElementsHidden = YES;
    _crestFade = [CAGradientLayer layer];
    _crestFade.actions = noActions();
    _crestFade.colors = @[(id)UIColor.clearColor.CGColor, (id)UIColor.whiteColor.CGColor];
    _content.layer.mask = _crestFade;
    _backShape = [CAShapeLayer layer];
    _backFill = fill(_backShape);
    _backFill.opacity = 0.55f;
    [_content.layer addSublayer:_backFill];
    _frontShape = [CAShapeLayer layer];
    _frontFill = fill(_frontShape);
    [_content.layer addSublayer:_frontFill];
    [self addSubview:_content];
    // The Lyrics style's words, over the hills and under the blur, so opening the player's own lyrics blurs
    // them away: a box whose alpha and scale follow the bands, holding two labels made once, so a line change
    // only hands them text and fades one over the other.
    _words = [[UIView alloc] initWithFrame:CGRectZero];
    _words.userInteractionEnabled = NO;
    _words.accessibilityElementsHidden = YES;
    [self addSubview:_words];
    _lyricBox = [[UIView alloc] initWithFrame:CGRectZero];
    _lyricBox.userInteractionEnabled = NO;
    _lyricBox.accessibilityElementsHidden = YES;
    [_words addSubview:_lyricBox];
    _lyricsBlur = [[UIVisualEffectView alloc] initWithEffect:nil];
    _lyricsBlur.userInteractionEnabled = NO;
    _lyricsBlur.accessibilityElementsHidden = YES;
    _lyricsBlur.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    [self addSubview:_lyricsBlur];
    NSMutableArray *lyricLabels = [NSMutableArray array];
    for (int i = 0; i < 2; i++) {
        UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
        label.font = [UIFont systemFontOfSize:kLyricSize weight:UIFontWeightBold];
        label.textColor = [UIColor colorWithWhite:1 alpha:kLyricAlpha];
        label.textAlignment = NSTextAlignmentCenter;
        label.numberOfLines = 3;
        label.lineBreakMode = NSLineBreakByWordWrapping;
        label.alpha = 0;
        label.userInteractionEnabled = NO;
        label.accessibilityElementsHidden = YES;
        [_lyricBox addSubview:label];
        [lyricLabels addObject:label];
    }
    _lyricLabels = lyricLabels;
    _lyricFront = lyricLabels.firstObject;
    _lineIndex = -1;
    _words.hidden = YES;
    [self applyColors:@[UIColor.darkGrayColor, UIColor.darkGrayColor, UIColor.darkGrayColor, UIColor.darkGrayColor, UIColor.darkGrayColor]];

    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    for (NSNotificationName name in @[NSProcessInfoPowerStateDidChangeNotification, NSProcessInfoThermalStateDidChangeNotification,
                                      UIAccessibilityReduceMotionStatusDidChangeNotification]) {
        [center addObserver:self selector:@selector(updateMotionSoon) name:name object:nil];
    }
    [center addObserver:self selector:@selector(resignActive) name:UIApplicationWillResignActiveNotification object:nil];
    [center addObserver:self selector:@selector(tellCover) name:UIApplicationDidEnterBackgroundNotification object:nil];
    [center addObserver:self selector:@selector(becomeActive) name:UIApplicationDidBecomeActiveNotification object:nil];
    [center addObserver:self selector:@selector(artworkChanged) name:SGRNowPlayingArtworkDidChangeNotification object:nil];
    [center addObserver:self selector:@selector(styleChanged) name:SGRVisualiserStyleDidChangeNotification object:nil];
    [center addObserver:self selector:@selector(lyricsKept:) name:SGKaraokeLinesKeptNotification object:nil];
    SGRObservePlayerTransition(self, ^(id owner) { [owner updateMotion]; });
    SGAddPlayerStateObserver(self);
    [self styleChanged];
    [self artworkChanged];
    [self draw];
    return self;
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
    [_link invalidate];
    [_wakeTimer invalidate];
    if (_reading) needReader(NO);
}

- (void)stopPreview {
    _previewStopped = YES;
    _palette++; // invalidate a palette already being computed off the main thread
    [NSNotificationCenter.defaultCenter removeObserver:self];
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    [self setReading:NO];
    [self setMoving:NO];
    [_wakeTimer invalidate];
    _wakeTimer = nil;
    [self removeFromSuperview];
}

#pragma mark - color

// Bottom left, the whole cover and bottom right in front, the top two behind, so the hills read as the cover's
// lower half under its upper.
- (void)applyColors:(NSArray<UIColor *> *)colors {
    if (colors.count < 5) return;
    _colors = colors;
    _frontFill.colors = @[(id)lit(colors[2], kGlow).CGColor, (id)lit(colors[4], kGlow).CGColor, (id)lit(colors[3], kGlow).CGColor];
    _backFill.colors = @[(id)lit(colors[0], kGlow).CGColor, (id)lit(colors[1], kGlow).CGColor];
    _styleFill.colors = _frontFill.colors;
    _reflection.colors = _frontFill.colors;
    _waveShape.strokeColor = lit(colors[4], kGlow).CGColor;
    for (NSUInteger i = 0; i < _clouds.count; i++) {
        UIColor *color = lit(colors[i], kGlow * 0.65);
        _clouds[i].colors = @[(id)color.CGColor, (id)[color colorWithAlphaComponent:0].CGColor];
    }
    [_stage setColours:colors];
}

- (void)artworkChanged {
    if (_previewStopped) return;
    NSUInteger generation = ++_palette; // nil/new-track artwork invalidates an outstanding palette too
    NSString *uri = nil, *identity = nil;
    UIImage *image = SGRNowPlayingArtwork(&uri, &identity);
    NSString *current = SGURIString(SGPlayerState().track.URI);
    // The bridge intentionally keeps the previous track's cover while the next arrives. Halo, Poster and Cut must not.
    UIImage *recordImage = current.length && [current isEqualToString:uri] ? image : nil;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _record.contents = (id)recordImage.CGImage;
    [CATransaction commit];
    [_stage setCover:recordImage identity:recordImage ? identity : nil];
    // Hills draws the cover's palette; the lyric styles draw the same hills, so they read the cover too.
    if (_style != SGRHills && !readsLyrics(_style)) image = recordImage;
    if (!image) return;
    SGRPaletteRequest request = {.flow = YES};
    __weak SGRVisualiserView *weakSelf = self;
    [SGRPalette paletteForImage:image request:request completion:^(SGRPalette *palette) {
        SGRVisualiserView *view = weakSelf;
        if (!view || !palette.flowColors || generation != view->_palette) return;
        if (!view.window) {
            [view applyColors:palette.flowColors];
            return;
        }
        // The colors cross over as the field's do.
        [CATransaction begin];
        [CATransaction setAnimationDuration:SGRCrossfade];
        [CATransaction setAnimationTimingFunction:[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut]];
        for (CAGradientLayer *layer in @[view->_frontFill, view->_backFill]) {
            CABasicAnimation *fade = [CABasicAnimation animationWithKeyPath:@"colors"];
            fade.fromValue = (layer.presentationLayer ?: layer).colors;
            [layer addAnimation:fade forKey:@"colors"];
        }
        [view applyColors:palette.flowColors];
        [CATransaction commit];
    }];
}

#pragma mark - local styles

- (void)styleChanged {
    SGRVisualiserStyleKind next = (SGRVisualiserStyleKind)[SGRVisualiserStyleIDs() indexOfObject:SGRVisualiserStyle()];
    self.accessibilityValue = SGRVisualiserStyleNames()[next];
    // The lyric styles draw the hills themselves, so they own them as Hills does.
    BOOL hills = next == SGRHills || readsLyrics(next);
    if (_style == next && (hills || _styleLayer)) return;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _style = next;
    // Dispose the entire old style, including its artwork; Hills owns only its original two fills.
    [_styleLayer removeFromSuperlayer];
    _styleLayer = nil; _record = nil; _styleFill = nil; _reflection = nil;
    _styleShape = nil; _reflectionShape = nil; _waveShape = nil; _clouds = nil;
    _phase = 0;
    memset(_wave, 0, sizeof _wave);
    _backFill.hidden = _frontFill.hidden = !hills;
    _content.layer.mask = hills ? _crestFade : nil;
    // The words belong to the lyric styles alone; nothing is read or shown for another style. Lyrics' labels are
    // its own, and Poster and Cut each draw on a stage of their own.
    _words.hidden = !readsLyrics(next);
    if (next != SGRLyricsStyle) {
        for (UILabel *label in _lyricLabels) label.alpha = 0;
        _lineIndex = -1;
    }
    [_stage removeFromSuperview];
    _stage = [SGRLyricStage stageForStyle:SGRVisualiserStyleIDs()[next]];
    if (_stage) [_words addSubview:_stage];
    [self layOutStage];
    [self tellCover];
    if (!readsLyrics(next)) {
        _lines = nil; _linesTimed = NO; _linesTrack = nil; _asked = NO;
    } else {
        [self takeUpTrack];
        [self readLine];
    }
    if (!hills) {
        _styleLayer = [CALayer layer];
        _styleLayer.actions = noActions();
        _styleLayer.masksToBounds = YES;
        [_content.layer addSublayer:_styleLayer];
        if (next == SGRNebula) {
            NSMutableArray *clouds = [NSMutableArray array];
            for (int i = 0; i < 3; i++) {
                CAGradientLayer *cloud = [CAGradientLayer layer];
                cloud.actions = noActions();
                cloud.type = kCAGradientLayerRadial;
                cloud.startPoint = CGPointMake(0.5, 0.5);
                cloud.endPoint = CGPointMake(1, 1);
                cloud.compositingFilter = @"plusL";
                [_styleLayer addSublayer:cloud];
                [clouds addObject:cloud];
            }
            _clouds = clouds;
        } else {
            if (next == SGRHalo) {
                _record = [CALayer layer];
                _record.actions = noActions();
                _record.contentsGravity = kCAGravityResizeAspectFill;
                _record.masksToBounds = YES;
                _record.opacity = 0.13; // dim even an all-white cover behind player text
                [_styleLayer addSublayer:_record];
            }
            _styleShape = [CAShapeLayer layer];
            _styleFill = fill(_styleShape);
            _styleFill.opacity = 0.65;
            [_styleLayer addSublayer:_styleFill];
            if (next == SGRBars) {
                _reflectionShape = [CAShapeLayer layer];
                _reflection = fill(_reflectionShape);
                _reflection.opacity = 0.20;
                [_styleLayer addSublayer:_reflection];
                _waveShape = [CAShapeLayer layer];
                _waveShape.actions = noActions();
                _waveShape.fillColor = nil;
                _waveShape.lineWidth = 1.5;
                _waveShape.compositingFilter = @"plusL";
                [_styleLayer addSublayer:_waveShape];
            }
        }
    }
    if (_colors) [self applyColors:_colors];
    [self artworkChanged];
    [self draw];
    [CATransaction commit];
    [self updateMotion];
}

- (void)setSample:(BOOL)sample {
    if (_sample == sample) return;
    _sample = sample;
    // The card's lines are the sample's, never the playing song's.
    _lines = nil;
    _linesTimed = NO;
    _linesTrack = nil;
    _asked = NO;
    _lineIndex = -1;
    _sampleEpoch = 0;
    for (UILabel *label in _lyricLabels) label.alpha = 0;
    _lyricFront = _lyricLabels.firstObject;
    [self readLine];
    [self updateMotion];
}

#pragma mark - the words

// The lines the style reads: the playing track's kept ones, or LyricsLook's sample lines in the settings card,
// which has no track. The track is taken up on a state change, so a frame only looks the kept lines up by a
// string it already holds; a track with none is asked for lyrics once, and the answer comes as
// SGKaraokeLinesKeptNotification.
- (NSArray<SGKaraokeLine *> *)lyricLines {
    // A view made while a track plays has had no state change yet to take it up; a track change does.
    if (!_sample && !_linesTrack) [self takeUpTrack];
    if (!_lines && (_sample || (_linesTrack && !_asked))) {
        _asked = YES;
        _lines = _sample ? SGRLyricsSampleLines() : SGKaraokeLinesForTrack(_linesTrack);
        // Classify only when taking a new array, never on the frame clock.
        _linesTimed = _lines && SGKaraokeLinesTiming(_lines) != SGKaraokeTimingNone;
        if (!_sample && !_lines) SGKaraokeRequestLyrics(_linesTrack);
    }
    return _lines;
}

// The track the words are for; a new one drops the old lines and the old words with them.
- (void)takeUpTrack {
    NSString *track = SGKaraokePlayingTrack();
    if (_linesTrack == track || [_linesTrack isEqualToString:track]) return;
    _linesTrack = [track copy];
    _lines = nil;
    _linesTimed = NO;
    _asked = NO;
    _lineIndex = -1;
    for (UILabel *label in _lyricLabels) {
        label.text = nil;
        label.alpha = 0;
    }
    _lyricFront = _lyricLabels.firstObject;
}

- (NSInteger)lyricPositionMs {
    if (_sample) {
        if (!_sampleEpoch) _sampleEpoch = CACurrentMediaTime();
        return (NSInteger)fmod((CACurrentMediaTime() - _sampleEpoch) * 1000, SGRLyricsSampleLength());
    }
    NSInteger ms = SGKaraokePositionMs();
    if (ms < 0) return ms;
    // The delay takes a lock and reads the offsets; once a second is enough for a change of it to land, and it
    // keeps a lock off every frame. The frame itself only needs a line to move when the clock passes it.
    CFTimeInterval now = CACurrentMediaTime();
    if (!_delayAt || now - _delayAt > 1) {
        _delayAt = now;
        _delayMs = SGKaraokeDelayMs();
    }
    return ms - _delayMs;
}

// The line the clock names, or -1 for the hills alone: no synced lyrics, before the first, in a break, or while
// the player's own lyrics are open. No text is built here.
- (NSInteger)lineAt:(NSInteger)ms lines:(NSArray<SGKaraokeLine *> *)lines {
    if (!lines.count || ms < 0 || self.blurred) return -1;
    if (!_linesTimed) return -1;
    NSInteger index = SGKaraokeLeadLine(lines, ms);
    if (index < 0) return -1;
    SGKaraokeLine *line = lines[(NSUInteger)index];
    BOOL nextFarOff = index + 1 >= (NSInteger)lines.count || lines[(NSUInteger)index + 1].start - ms > kLyricBreakMs;
    if (ms > SGKaraokeSungEnd(line) + kLyricBreakMs && nextFarOff) return -1;
    return index;
}

// Reads the line for the clock and, only when the line index changed, hands the new text to the label that is
// not in front and fades it over the old one, rising in. Nothing is allocated from frame to frame: the line's
// text is built only when the index moves.
// Poster and Cut hand the line and the clock to their stage, which compares them with what it shows.
- (void)readLine {
    if (!readsLyrics(_style)) return;
    NSArray<SGKaraokeLine *> *lines = [self lyricLines];
    NSInteger ms = [self lyricPositionMs];
    NSInteger index = [self lineAt:ms lines:lines];
    if (_stage) {
        // A new line measures the player again, whose own line may have come or gone with it.
        if (index != _lineIndex) {
            _lineIndex = index;
            [self layOutStage];
        }
        [_stage showLine:index of:lines at:ms];
        [self tellCover];
        return;
    }
    if (index == _lineIndex) return;
    _lineIndex = index;
    NSString *text = nil;
    if (index >= 0) {
        text = [SGKaraokeLineText(lines[(NSUInteger)index]) stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (!text.length) text = nil;
    }
    UILabel *old = _lyricFront;
    UILabel *next = _lyricLabels.firstObject == old ? _lyricLabels.lastObject : _lyricLabels.firstObject;
    BOOL still = SGRReduceMotion();
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    next.text = text;
    next.transform = still || !text ? CGAffineTransformIdentity : CGAffineTransformMakeTranslation(0, kLyricRise);
    [self layoutLyrics];
    [CATransaction commit];
    if (!text) {
        SGRAnimate(SGRMotionFade, ^{ old.alpha = 0; next.alpha = 0; }, nil);
        _lyricFront = next;
        return;
    }
    next.alpha = 0;
    SGRAnimate(SGRMotionFade, ^{
        old.alpha = 0;
        next.alpha = 1;
        next.transform = CGAffineTransformIdentity;
    }, nil);
    _lyricFront = next;
}

// The words' box, centered over the player's visible field, three lines tall at the most.
- (void)layoutLyrics {
    CGRect bounds = self.bounds;
    CGFloat width = MAX(0, bounds.size.width - 2 * kLyricMargin);
    CGFloat tallest = ceil(kLyricSize * 1.25 * 3);
    CGFloat height = kLyricSize * 1.25;
    for (UILabel *label in _lyricLabels) {
        if (!label.text.length) continue;
        height = MAX(height, MIN(tallest, ceil([label sizeThatFits:CGSizeMake(width, CGFLOAT_MAX)].height)));
    }
    CGFloat baseline = _baseline > 0 ? _baseline : bounds.size.height;
    CGSize size = CGSizeMake(width, height);
    _lyricBox.bounds = CGRectMake(0, 0, size.width, size.height);
    _lyricBox.center = CGPointMake(CGRectGetMidX(bounds), baseline * kLyricAnchor);
    for (UILabel *label in _lyricLabels) {
        label.bounds = CGRectMake(0, 0, size.width, size.height);
        label.center = CGPointMake(size.width / 2, size.height / 2);
    }
}

// Poster's or Cut's stage over the whole view, its type within the margins Lyrics keeps. In the player it sets in
// the band the cover sits in, which the cover gives up while a line shows, down to kTitleClearance over the title
// block: the player's own sung line where that has room (and the type's whole line then goes, which would repeat
// it), else the title. In the settings card, which has no player, it sets above the baseline, centered on the line
// Lyrics centers its words on.
- (void)layOutStage {
    if (!_stage) return;
    CGRect bounds = self.bounds;
    _stage.frame = bounds;
    CGFloat width = MAX(0, bounds.size.width - 2 * kLyricMargin);
    CGRect area = _sample ? CGRectNull : SGRPlayerArtworkAreaIn(self);
    if (CGRectIsNull(area)) {
        CGFloat baseline = _baseline > 0 ? _baseline : bounds.size.height;
        [_stage setField:CGRectMake(kLyricMargin, 0, width, baseline) centre:baseline * kLyricAnchor lineElsewhere:NO];
        return;
    }
    CGRect line = SGRPlayerLyricLineIn(self);
    CGFloat title = CGRectIsNull(line) ? CGRectGetMaxY(area) : MIN(CGRectGetMaxY(area), CGRectGetMinY(line));
    CGRect field = CGRectMake(kLyricMargin, CGRectGetMinY(area), width, title - kTitleClearance - CGRectGetMinY(area));
    [_stage setField:field centre:CGRectGetMidY(field) lineElsewhere:!CGRectIsNull(line)];
}

// The player's view tells PlayerMotion.x whether its stage's line takes the cover's place: only while it is in a
// window with Spotify in front, so a closed player or one in the background gives the cover back. Inactive is
// still foreground: the stage remains visible there, even while its motion is held, and still owns its space.
- (void)tellCover {
    if (!_ownsCover) return;
    BOOL front = self.window && UIApplication.sharedApplication.applicationState != UIApplicationStateBackground;
    SGRPlayerLyricStageTakesCover(front && _stage.showing);
}

- (void)setOwnsCover:(BOOL)ownsCover {
    _ownsCover = ownsCover;
    if (ownsCover) [self tellCover];
    else SGRPlayerLyricStageTakesCover(NO);
}

- (void)lyricsKept:(NSNotification *)note {
    if (_sample || ![note.object isEqual:SGKaraokePlayingTrack()]) return;
    _lines = nil;
    _linesTimed = NO;
    _asked = NO;
    _lineIndex = kLineUnread;
    [self readLine];
}

#pragma mark - showing

- (void)setBaseline:(CGFloat)baseline {
    if (baseline == _baseline) return;
    _baseline = baseline;
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect bounds = self.bounds;
    _content.frame = bounds;
    _words.frame = bounds;
    _lyricsBlur.frame = bounds;
    _backFill.frame = bounds;
    _frontFill.frame = bounds;
    _backShape.frame = bounds;
    _frontShape.frame = bounds;
    _crestFade.frame = bounds;
    if (_style == SGRLyricsStyle) [self layoutLyrics];
    [self layOutStage];
    [self draw];
}

- (void)appear:(BOOL)animated {
    _content.alpha = _words.alpha = 0;
    if (animated) SGRAnimate(SGRMotionFade, ^{
        self->_content.alpha = 1;
        self->_words.alpha = 1;
    }, nil);
    else _content.alpha = _words.alpha = 1;
}

- (void)disappear:(void (^)(void))done {
    SGRAnimate(SGRMotionFade, ^{
        self->_content.alpha = 0;
        self->_words.alpha = 0;
        self->_lyricsBlur.effect = nil;
    }, ^(BOOL finished) { done(); });
}

- (BOOL)blurred {
    return _lyricsBlur.effect != nil;
}

- (void)setBlurred:(BOOL)blurred animated:(BOOL)animated {
    void (^apply)(void) = ^{ self->_lyricsBlur.effect = blurred ? blurEffect() : nil; };
    if (animated) SGRAnimate(SGRMotionFade, apply, nil);
    else apply();
    // The words go while the player's own lyrics are open, and come back when they close.
    [self readLine];
    [self updateMotion];
}

#pragma mark - moving

- (void)playerStateDidChange:(SPTPlayerState *)state {
    if (_previewStopped) return;
    NSString *uri = SGURIString(state.track.URI);
    if (![_trackURI isEqualToString:uri]) {
        _trackURI = [uri copy];
        [self artworkChanged];
    }
    if (!state.isPaused) _idle = NO;
    // A pause leaves the link down, so the new track's line (or the same one, a pause into the song) is read here.
    [self takeUpTrack];
    [self readLine];
    [self updateMotion];
}

// With the link down (a pause, a scrub while paused) a position report is the only clock there is.
- (void)playerStateDidReport:(SPTPlayerState *)state {
    // Off the screen nothing is read: the Player page's preview is kept between taps and held by nothing once
    // the page is gone, and a report there would only advance its sample's lines and measure its labels.
    if (!self.window || self.hidden) return;
    if (readsLyrics(_style) && (!_link || _sample)) [self readLine];
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    // Back on a window, the line the reports read while it was off is read once more.
    if (self.window && readsLyrics(_style)) [self readLine];
    // Off a window the cover is given back; back on one the line just read takes it again.
    [self tellCover];
    [self updateMotion];
}

- (void)setHidden:(BOOL)hidden {
    if (self.hidden == hidden) return;
    [super setHidden:hidden];
    // Shown again, the line the reports skipped while it was hidden is read once more.
    if (!hidden && self.window && readsLyrics(_style)) [self readLine];
    [self updateMotion];
}

// The power state is reported off the main thread.
- (void)updateMotionSoon {
    dispatch_async(dispatch_get_main_queue(), ^{ [self updateMotion]; });
}

- (void)resignActive {
    // WillResignActive can arrive before UIApplication's state changes.
    _inactive = YES;
    [self updateMotion];
}

- (void)becomeActive {
    _inactive = NO;
    // The stage's line read again, which takes the cover again while one shows.
    if (_stage) [self readLine];
    [self updateMotion];
}

- (BOOL)settled {
    for (int band = 0; band < kBands; band++) if (_front[band] > kSettled || _back[band] > kSettled) return NO;
    if (_style != SGRHills && _pulse > kSettled) return NO;
    if (_style == SGRBars) {
        for (int i = 0; i < SGRSpectrumWaveformSamples; i++) if (fabsf(_wave[i]) > kSettled) return NO;
    }
    return YES;
}

// Moving while it may and there is something to show: the song playing, or the hills still settling after it
// stopped. While the player animates, it comes back once the animation is expected to be over.
- (void)updateMotion {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(updateMotion) object:nil];
    if (_previewStopped) return;
    BOOL front = !_inactive && UIApplication.sharedApplication.applicationState == UIApplicationStateActive;
    BOOL may = self.window && !self.hidden && front && !NSProcessInfo.processInfo.lowPowerModeEnabled
        && !SGRVisualiserStandsDownFor(NSProcessInfo.processInfo.thermalState);
    NSTimeInterval wait = SGPlayerTransitionEnds() - CACurrentMediaTime();
    if (may && (wait > 0 || SGRPlayerIsTransitioning())) {
        may = NO;
        // Without an expected end, the transition's ended notification brings it back.
        if (wait > 0) [self performSelector:@selector(updateMotion) withObject:nil afterDelay:wait + kTransitionSlack inModes:@[NSRunLoopCommonModes]];
    }
    SPTPlayerState *state = SGPlayerState();
    BOOL playing = state && !state.isPaused;
    // The settings card's sample has no track to play: its clock steps the lines for as long as it is on screen.
    BOOL sampleTicking = _sample && readsLyrics(_style);
    // The lyric styles keep their clock while the song plays even through a quiet passage, since the next line
    // must come in then; the other styles may stop once the hills have settled.
    BOOL moving = sampleTicking || (readsLyrics(_style) && playing) || (playing && !_idle) || !self.settled;
    // The card's preview reads the same sound as the player's, so its hills move there too.
    [self setReading:may && playing];
    [self setMoving:may && moving];
    BOOL waiting = may && playing && _idle && !moving;
    if (waiting && !_wakeTimer) {
        __weak SGRVisualiserView *weakSelf = self;
        _wakeTimer = [NSTimer timerWithTimeInterval:0.25 repeats:YES block:^(NSTimer *timer) {
            SGRVisualiserView *view = weakSelf;
            if (!view) { [timer invalidate]; return; }
            // Recheck eligibility before touching the analysis (power/thermal notifications can be queued).
            [view updateMotion];
            if (!view->_reading) return;
            float levels[kBands];
            uint64_t generation = SGRSpectrumRead(levels);
            if (generation == view->_generation) return;
            view->_generation = generation;
            for (int i = 0; i < kBands; i++) {
                if (levels[i] > SGRSpectrumFloor + 1) {
                    view->_fresh = CACurrentMediaTime();
                    view->_idle = NO;
                    [view updateMotion];
                    break;
                }
            }
        }];
        _wakeTimer.tolerance = 0.05;
        [NSRunLoop.mainRunLoop addTimer:_wakeTimer forMode:NSRunLoopCommonModes];
    } else if (!waiting) {
        [_wakeTimer invalidate];
        _wakeTimer = nil;
    }
}

- (void)setReading:(BOOL)reading {
    if (reading == _reading) return;
    _reading = reading;
    if (reading) {
        float unused[kBands];
        _generation = SGRSpectrumRead(unused);
        _fresh = 0;
        _idle = NO;
        _last = 0;
    }
    needReader(reading);
}

- (void)setMoving:(BOOL)moving {
    if (moving) {
        if (!_link) {
            _link = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick:)];
            [_link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
            _last = 0;
        }
        // The link asks for the rate the view draws at, so a calmer one lets a ProMotion screen come down. Its
        // maximum stays the screen's: the player's transitions and the lyrics' own link may run the screen faster,
        // and tick: skips the extra ticks.
        float rate = [self drawRate];
        _link.preferredFrameRateRange = CAFrameRateRangeMake(rate, (float)self.window.screen.maximumFramesPerSecond, rate);
    } else if (_link) {
        [_link invalidate];
        _link = nil;
        _last = 0;
    }
}

// How many times a second the hills draw: calmer behind the lyrics, whose own link runs at the display's rate,
// and calmest with Reduce Motion. Bars and Halo may use ProMotion, a target ceiling rather than a measured
// throughput claim.
- (float)drawRate {
    if (SGRReduceMotion()) return kStillRate;
    if (_lyricsBlur.effect) return kBehindLyricsRate;
    return (_style == SGRBars || _style == SGRHalo) && self.window.screen.maximumFramesPerSecond >= 120 ? 120 : 60;
}

static float ease(float value, float target, double dt, double up, double down) {
    double tau = target > value ? up : down;
    return value + (target - value) * (float)(1 - exp(-dt / tau));
}

- (void)tick:(CADisplayLink *)link {
    // Notifications normally stop us first; this also covers a power/thermal change queued behind this tick.
    if (!self.window || self.hidden || _inactive || UIApplication.sharedApplication.applicationState != UIApplicationStateActive
        || NSProcessInfo.processInfo.lowPowerModeEnabled || SGRVisualiserStandsDownFor(NSProcessInfo.processInfo.thermalState)
        || SGRPlayerIsTransitioning() || SGPlayerTransitionEnds() > CACurrentMediaTime()) {
        [self updateMotion];
        return;
    }
    // Poster's and Cut's words change as a word's start passes, whatever rate the hills draw at.
    if (_stage) [self readLine];
    CFTimeInterval now = link.timestamp;
    // The link may tick faster than the draw rate when another request runs the screen faster; a tick less than a
    // frame short of the wanted interval is skipped, and the next one that draws takes the time since the last draw.
    if (_last && now - _last < 1 / [self drawRate] - link.duration / 2) return;
    double dt = _last ? MIN(now - _last, 0.1) : link.duration;
    _last = now;
    float levels[kBands];
    uint64_t generation = SGRSpectrumRead(levels);
    if (generation != _generation) {
        _generation = generation;
        _fresh = now;
    }
    BOOL silent = !_reading || now - _fresh > kStale;
    float loudest = kPeakFloor;
    BOOL hasSignal = NO;
    for (int band = 0; band < kBands; band++) {
        if (levels[band] > SGRSpectrumFloor + 1) hasSignal = YES;
        levels[band] += kTilt * band;
        loudest = fmaxf(loudest, levels[band]);
    }
    silent = silent || !hasSignal;
    if (!silent) _peak = fmaxf(fmaxf(loudest, _peak - kPeakFall * (float)dt), kPeakFloor);
    BOOL still = SGRReduceMotion();
    float targets[kBands], kick = kPeakFloor;
    for (int band = 0; band < kBands; band++) targets[band] = silent ? 0 : fminf(1, fmaxf(0, (levels[band] - (_peak - kRange)) / kRange));
    for (int band = kFirst; band < kFirst + kKickBands; band++) kick = fmaxf(kick, levels[band]);
    // The middle is a mound and never a valley: between kicks the kick's bands stand as tall as the bands beside
    // them (kBesideBands up), so the centre sinks only with the hills on either side and never under them.
    float beside = 0;
    for (int band = kFirst + kKickBands; band < kFirst + kKickBands + kBesideBands; band++) beside = fmaxf(beside, targets[band]);
    for (int band = kFirst; band < kFirst + kKickBands; band++) targets[band] = fmaxf(targets[band], beside);
    for (int pass = 0; pass < 3; pass++) {
        float before = targets[0];
        for (int band = 0; band < kBands; band++) {
            float here = targets[band], next = targets[MIN(band + 1, kBands - 1)];
            targets[band] = kSpread * before + (1 - 2 * kSpread) * here + kSpread * next;
            before = here;
        }
    }
    for (int band = 0; band < kBands; band++) {
        float target = targets[band];
        _front[band] = ease(_front[band], target, dt, still ? kStillEase : kFrontUp, still ? kStillEase : kFrontDown);
        _back[band] = ease(_back[band], target, dt, still ? kStillEase : kBackUp, still ? kStillEase : kBackDown);
    }
    float beat = silent ? 0 : fminf(1, fmaxf(0, (kick - (_peak - kPulseRange)) / kPulseRange));
    _pulse = ease(_pulse, beat, dt, still ? kStillEase : kPulseUp, still ? kStillEase : kPulseDown);
    if (_style == SGRLyricsStyle) [self readLine];
    if (_style == SGRBars) {
        float samples[SGRSpectrumWaveformSamples];
        uint64_t waveGeneration = silent ? 0 : SGRSpectrumReadWaveform(samples);
        for (int i = 0; i < SGRSpectrumWaveformSamples; i++) {
            _wave[i] = ease(_wave[i], waveGeneration ? samples[i] : 0, dt,
                            still ? kStillEase : 0.04, still ? kStillEase : 0.12);
        }
    }
    // Spatial motion slows with the audible envelope and has no independent CAAnimation clock.
    if (!still && (_style == SGRNebula || _style == SGRHalo)) {
        float energy = 0;
        for (int i = 0; i < kBands; i++) energy = fmaxf(energy, _front[i]);
        _phase = fmod(_phase + dt * (0.08 * energy + 0.07 * _pulse), 2 * M_PI);
    }
    [self draw];
    BOOL idle = silent && self.settled;
    if (idle && !_idle) {
        // The last step down to rest, too small to see, so a settled hill is drawn exactly at rest.
        memset(_front, 0, sizeof _front);
        memset(_back, 0, sizeof _back);
        memset(_wave, 0, sizeof _wave);
        _pulse = 0;
        [self draw];
    }
    if (idle != _idle) {
        _idle = idle;
        [self updateMotion];
    }
}

#pragma mark - drawing

// A smooth line through the points (Catmull-Rom as cubic Béziers), closed down to the foot of the bounds.
static CGPathRef hillPath(const CGPoint *points, int count, CGFloat foot) {
    CGMutablePathRef path = CGPathCreateMutable();
    CGPathMoveToPoint(path, NULL, points[0].x, foot);
    CGPathAddLineToPoint(path, NULL, points[0].x, points[0].y);
    for (int i = 0; i < count - 1; i++) {
        CGPoint before = points[MAX(i - 1, 0)], from = points[i], to = points[i + 1], after = points[MIN(i + 2, count - 1)];
        CGPathAddCurveToPoint(path, NULL, from.x + (to.x - before.x) / 6, from.y + (to.y - before.y) / 6,
                              to.x - (after.x - from.x) / 6, to.y - (after.y - from.y) / 6, to.x, to.y);
    }
    CGPathAddLineToPoint(path, NULL, points[count - 1].x, foot);
    CGPathCloseSubpath(path);
    return path;
}

// The bass in the middle, each band out to either side, the treble at the edges; a band's height eased in so
// quiet bands lie low and only the strong ones stand up.
static void shape(CAShapeLayer *layer, const float *bands, CGFloat width, CGFloat baseline, CGFloat foot, CGFloat tallest, CGFloat rest) {
    CGPoint points[kPoints];
    for (int i = 0; i < kPoints; i++) {
        float value = bands[kFirst + abs(i - (kShown - 1))];
        CGFloat height = rest + (tallest - rest) * powf(value, 1.2f);
        points[i] = CGPointMake(width * i / (kPoints - 1), baseline - height);
    }
    CGPathRef path = hillPath(points, kPoints, foot);
    layer.path = path;
    CGPathRelease(path);
}

- (void)draw {
    CGRect bounds = self.bounds;
    if (bounds.size.width <= 0 || bounds.size.height <= 0) return;
    CGFloat baseline = _baseline > 0 ? _baseline : bounds.size.height;
    CGFloat screen = _screenHeight > 0 ? _screenHeight : bounds.size.height;
    CGFloat foot = MAX(baseline, bounds.size.height), rest = round(screen * kRestHeight);
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    // The lyric styles draw the hills too, at a share of their height and with the words over them.
    if (_style != SGRHills && !readsLyrics(_style)) {
        [self drawStyleWithBaseline:baseline screen:screen];
        [CATransaction commit];
        return;
    }
    BOOL calm = readsLyrics(_style);
    CGFloat share = calm ? kLyricHills : 1;
    shape(_backShape, _back, bounds.size.width, baseline, foot, screen * kBackHeight * share, rest * 1.5);
    shape(_frontShape, _front, bounds.size.width, baseline, foot, screen * kFrontHeight * share, rest);
    _frontFill.opacity = kPulseFloor + (1 - kPulseFloor) * _pulse;
    if (_style == SGRLyricsStyle) {
        // The words breathe with the kick: a little brighter and a little larger, never much either way.
        CGFloat pulse = SGRReduceMotion() ? 0 : _pulse;
        _lyricBox.alpha = 0.84f + 0.16f * pulse;
        _lyricBox.transform = CGAffineTransformMakeScale(1 + 0.03f * pulse, 1 + 0.03f * pulse);
    }
    _crestFade.startPoint = CGPointMake(0.5, (baseline - screen * kFadeTop) / bounds.size.height);
    _crestFade.endPoint = CGPointMake(0.5, (baseline - screen * kFadeFoot) / bounds.size.height);
    [CATransaction commit];
}

- (void)drawStyleWithBaseline:(CGFloat)baseline screen:(CGFloat)screen {
    CGRect bounds = self.bounds;
    CGFloat width = bounds.size.width, height = bounds.size.height;
    _styleLayer.frame = bounds;
    _styleFill.frame = _styleShape.frame = bounds;
    _reflection.frame = _reflectionShape.frame = bounds;
    _waveShape.frame = bounds;
    if (_style == SGRNebula) {
        for (NSUInteger i = 0; i < _clouds.count; i++) {
            CGFloat angle = _phase + i * 2 * M_PI / 3;
            CGFloat size = MIN(width, screen) * (1.1 + 0.10 * _back[kFirst + i]);
            CGFloat x = width * (0.5 + 0.22 * cos(angle));
            CGFloat y = MIN(height, baseline) * (0.58 + 0.12 * sin(angle));
            _clouds[i].frame = CGRectMake(x - size / 2, y - size / 2, size, size);
            _clouds[i].opacity = 0.25 + 0.25 * _back[kFirst + i] + 0.08 * _pulse;
        }
        return;
    }
    CGMutablePathRef path = CGPathCreateMutable();
    if (_style == SGRBars) {
        CGFloat floor = MIN(height, baseline) - MIN(screen * 0.13, height * 0.2);
        CGFloat step = width / kBands, barWidth = MAX(1, step * 0.55);
        CGMutablePathRef reflected = CGPathCreateMutable();
        for (int i = 0; i < kBands; i++) {
            CGFloat amplitude = MIN(screen * 0.20, height * 0.4) * _front[i];
            CGFloat x = step * (i + 0.5) - barWidth / 2;
            CGPathAddRect(path, NULL, CGRectMake(x, floor - amplitude, barWidth, MAX(1, amplitude)));
            CGPathAddRect(reflected, NULL, CGRectMake(x, floor + 2, barWidth, MAX(1, amplitude * 0.48)));
        }
        _reflectionShape.path = reflected;
        CGPathRelease(reflected);
        CGMutablePathRef waveform = CGPathCreateMutable();
        for (int i = 0; i < SGRSpectrumWaveformSamples; i++) {
            CGFloat x = width * i / (SGRSpectrumWaveformSamples - 1);
            CGFloat y = floor - _wave[i] * MIN(screen * 0.065, height * 0.16);
            if (!i) CGPathMoveToPoint(waveform, NULL, x, y);
            else CGPathAddLineToPoint(waveform, NULL, x, y);
        }
        _waveShape.path = waveform;
        CGPathRelease(waveform);
    } else if (_style == SGRHalo) {
        CGFloat radius = MIN(width * 0.31, MIN(screen, height) * 0.27);
        CGPoint center = CGPointMake(width / 2, MIN(baseline, height) * 0.52);
        // Bounds/position rather than frame: the record already has a rotation transform.
        _record.bounds = CGRectMake(0, 0, radius * 1.8, radius * 1.8);
        _record.position = center;
        _record.cornerRadius = radius * 0.9;
        _record.transform = CATransform3DMakeRotation(_phase, 0, 0, 1);
        for (int i = 0; i < kBands * 3; i++) {
            CGFloat angle = 2 * M_PI * i / (kBands * 3) - M_PI_2;
            CGFloat length = 1.5 + radius * 0.24 * _front[i % kBands];
            CGPoint inner = CGPointMake(center.x + cos(angle) * radius, center.y + sin(angle) * radius);
            CGPoint outer = CGPointMake(center.x + cos(angle) * (radius + length), center.y + sin(angle) * (radius + length));
            CGPathMoveToPoint(path, NULL, inner.x, inner.y);
            CGPathAddLineToPoint(path, NULL, outer.x, outer.y);
        }
        _styleShape.fillColor = nil;
        _styleShape.strokeColor = UIColor.whiteColor.CGColor;
        _styleShape.lineWidth = MAX(1, radius * 0.018);
        _styleShape.lineCap = kCALineCapRound;
    }
    _styleShape.path = path;
    CGPathRelease(path);
}

@end

#pragma mark - in the player

static SGRVisualiserView *sg_view;

BOOL SGRPlayerVisualiserShowing(void) {
    return SGRPlayerBackground() == SGRPlayerBackgroundVisualiser
        || (SGRPlayerVisualiserFallbackWanted() && !SGRVisualiserStandsDownFor(NSProcessInfo.processInfo.thermalState));
}

#pragma mark - shuffle

// The hills are on screen: in a window, shown, Spotify in front.
static BOOL onScreen(void) {
    return SGRPlayerVisualiserShowing() && sg_view.window && !sg_view.hidden
        && UIApplication.sharedApplication.applicationState == UIApplicationStateActive;
}

// The hills as a missing clip's stand-in could be seen if the lookup finds none: the player is in a window, Spotify in
// front, neither heat nor Low Power Mode keeping them away.
static BOOL fallbackSeeable(void) {
    return SGRPlayerField().window && UIApplication.sharedApplication.applicationState == UIApplicationStateActive
        && !NSProcessInfo.processInfo.lowPowerModeEnabled && !SGRVisualiserStandsDownFor(NSProcessInfo.processInfo.thermalState);
}

// Picks a style for each new song while the hills are on screen, one pick a song. Held by sg_shuffle, since player
// state observers are held weakly.
@interface SGRVisualiserShuffle : NSObject <SGPlayerStateObserver>
// The hills came onto the field.
- (void)viewMade;
// The background is no longer Animated, so no lookup is waited on.
- (void)stopWaiting;
@end

static SGRVisualiserShuffle *sg_shuffle;

@implementation SGRVisualiserShuffle {
    NSString *_track;     // the song playing, so the same song told again is not a new one
    NSString *_awaiting;  // the song whose clip lookup is out: the hills pick for it if they come in as its fallback
}

- (instancetype)init {
    if (!(self = [super init])) return nil;
    _track = SGURIString(SGPlayerState().track.URI);
    SGAddPlayerStateObserver(self);
    // A song that changed while the hills could not be seen is not picked for when they come back: the wait ends as
    // the app leaves the front, and when heat or Low Power Mode keeps them away.
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    for (NSNotificationName name in @[UIApplicationWillResignActiveNotification, UIApplicationDidEnterBackgroundNotification]) {
        [center addObserver:self selector:@selector(stopWaiting) name:name object:nil];
    }
    for (NSNotificationName name in @[NSProcessInfoThermalStateDidChangeNotification, NSProcessInfoPowerStateDidChangeNotification]) {
        [center addObserver:self selector:@selector(powerChanged) name:name object:nil];
    }
    return self;
}

- (void)pick {
    NSMutableArray<NSString *> *others = [SGRVisualiserStyleIDs() mutableCopy];
    [others removeObject:SGRVisualiserStyle()];
    SGRSetVisualiserStyle(others[arc4random_uniform((uint32_t)others.count)]);
}

- (void)playerStateDidChange:(SPTPlayerState *)state {
    NSString *uri = SGURIString(state.track.URI);
    if (!uri.length || [uri isEqualToString:_track]) return;
    _track = [uri copy];
    _awaiting = nil;
    if (!SGHidden(SGRKeyVisualiserShuffle)) return;
    if (onScreen()) [self pick];
    // Animated with the Visualizer for a missing clip: it comes in once the lookup finds none, if it could be seen now.
    else if (SGRPlayerBackground() == SGRPlayerBackgroundAnimated && SGRPlayerAnimatedVisualiserOn() && fallbackSeeable()) _awaiting = _track;
}

// The power state is reported off the main thread.
- (void)powerChanged {
    dispatch_async(dispatch_get_main_queue(), ^{ if (!fallbackSeeable()) [self stopWaiting]; });
}

- (void)viewMade {
    NSString *waited = _awaiting;
    _awaiting = nil;
    if (waited && [waited isEqualToString:_track] && SGHidden(SGRKeyVisualiserShuffle) && onScreen()) [self pick];
}

- (void)stopWaiting {
    _awaiting = nil;
}

@end

// The card's own hills, kept between taps on the background choices: a view taken off the card and shown again
// is the same one, with its link and the palette read it started let alone, where a new one a tap raced the old
// one's teardown.
static SGRVisualiserView *sg_preview;

void SGRPlayerVisualiserPreviewStop(void) {
    [sg_preview stopPreview];
    sg_preview = nil;
}

UIView *SGRPlayerVisualiserPreview(void) {
    if (sg_preview) {
        // Out of whatever held it before, in case it is another card's.
        [sg_preview removeFromSuperview];
        sg_preview.sample = YES;
        [sg_preview appear:NO];
        return sg_preview;
    }
    SGRVisualiserView *view = [[SGRVisualiserView alloc] initWithFrame:CGRectZero];
    // No track plays in the card, so the Lyrics style reads LyricsLook's sample lines there.
    view.sample = YES;
    sg_preview = view;
    return view;
}

// The hills from the top of the field to the foot of its bleed, standing on the screen's foot.
static void layOut(SGRArtworkField *field) {
    if (sg_view.superview != field) [field addSubview:sg_view];
    else if (field.subviews.lastObject != sg_view) [field bringSubviewToFront:sg_view];
    CGSize size = field.bounds.size;
    CGFloat screen = field.window.bounds.size.height ?: size.height;
    CGRect frame = CGRectMake(0, 0, size.width, MAX(size.height, screen) + field.bleed.bottom);
    if (!CGRectEqualToRect(sg_view.frame, frame)) sg_view.frame = frame;
    sg_view.baseline = screen;
    sg_view.screenHeight = screen;
}

void SGRPlayerVisualiserUpdate(void) {
    SGRPlayerReconcileFallbackSwitches();
    SGRArtworkField *field = SGRPlayerField();
    if (!sg_shuffle) sg_shuffle = [SGRVisualiserShuffle new];
    if (SGRPlayerBackground() != SGRPlayerBackgroundAnimated) [sg_shuffle stopWaiting];
    // Not over an Animated artwork clip still playing: the Player page can change the choice under it, which the
    // player takes up when it next starts.
    BOOL wanted = SGRPlayerVisualiserShowing() && field && !SGRPlayerMotionShowing();
    if (!wanted) {
        SGRVisualiserView *old = sg_view;
        if (!old) return;
        sg_view = nil;
        old.ownsCover = NO;
        if (old.window) [old disappear:^{ [old removeFromSuperview]; }];
        else [old removeFromSuperview];
        // The hills were what held the field still (PlayerField.x).
        SGRPlayerHoldField();
        return;
    }
    BOOL made = !sg_view;
    if (made) sg_view = [[SGRVisualiserView alloc] initWithFrame:CGRectZero];
    layOut(field);
    // The player's title block may have moved without the hills' frame changing.
    [sg_view layOutStage];
    if (made) {
        sg_view.ownsCover = YES;
        [sg_view setBlurred:SGRPlayerPageOpen() animated:NO];
        [sg_view appear:field.window != nil];
        SGRPlayerHoldField();
        SGLog(@"redesign player: visualizer on the field");
        [sg_shuffle viewMade];
    } else {
        BOOL open = SGRPlayerPageOpen();
        if (open != sg_view.blurred) [sg_view setBlurred:open animated:sg_view.window != nil];
    }
}

void SGRVisualiserIgnoreHeatChanged(void) {
    SGRPlayerVisualiserUpdate();
    [sg_view updateMotion];
    [sg_preview updateMotion];
}

#pragma mark - the ⋯ menu's switch

void SGRPlayerMenuSetBackground(SGRPlayerBackgroundKind kind) {
    SGRPlayerBackgroundKind current = SGRPlayerBackground();
    if (!SGPlayerMenuOffersAnimatedArtwork() || kind < SGRPlayerBackgroundFluid || kind == current) return;
    // Animated's own switch lets the clip go or looks it up, and calls back here.
    if (kind == SGRPlayerBackgroundAnimated || current == SGRPlayerBackgroundAnimated) SGPlayerMenuSetAnimatedArtwork(kind == SGRPlayerBackgroundAnimated);
    if (kind != SGRPlayerBackgroundAnimated) SGRSetPlayerBackground(kind);
    // The log keeps the English names; SGRPlayerBackgroundNames is translated for the page.
    SGLog(@"redesign player: background switched to %@ from the menu", @[@"Still", @"Colors", @"Fluid", @"Animated", @"Visualizer"][(NSUInteger)kind]);
    SGRPlayerHoldField();
    SGRPlayerVisualiserUpdate();
}
