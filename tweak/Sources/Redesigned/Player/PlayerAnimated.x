// Player redesign: Animated artwork, the track's Canvas or its album's Apple Music cover looping muted over
// Fluid artwork and under the rest of the player, found the way the lock screen finds its clip but in an
// order of its own. Fluid artwork shows until the clip can be drawn and for a track without one.
#import <AVFoundation/AVFoundation.h>
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Shared/LockScreenArtwork/LockScreenArtwork.h"
#import "Shared/LockScreenArtwork/SGArtworkFile.h"
#import "Shared/LockScreenArtwork/SGCanvas.h"
#import "Player.h"

static const NSTimeInterval kFadeIn = 0.6, kFadeOut = 0.45, kDimChange = 0.3;
// The dim holds the brighter part of a clip (the 75th percentile of a few frames' linear luminance) under
// this, where white text keeps 4.5:1 (7:1 with Increase Contrast), as Fluid artwork holds its own; never
// less than the least, and more under the lyrics. Over it, the shade Fluid artwork has under the controls.
static const float kCeiling = 0.18f, kCeilingContrast = 0.09f, kUnknownLight = 0.35f;
// The full-screen ground scrim carries most of the legibility darkening, so the clip's own dim stays
// light — just enough to keep a very bright clip from blowing out the status bar, never so much that
// the bottom of the video reads darker than the ground below it (which was the seam).
static const float kDimLeast = 0.0f, kDimLyrics = 0.10f, kDimMost = 0.12f;
static const NSTimeInterval kReadyWithin = 5;
// Where the clip begins fading to nothing, as a fraction of the artwork band's
// height — BitChord keeps its motion cover visible to ~0.72 then dissolves it,
// so the bottom ~22% of the band melts into the Fluid artwork instead of ending
// on a hard line.
static const float kDissolveStart = 0.78f;
// Colour stops in the dissolve ramp. As many as BitChord's BottomFadeScrim: a
// two-stop gradient interpolates linearly in the shader, which bands across a
// near-flat alpha on an 8-bit display; sampling the curve hands it short spans.
static const NSInteger kMaskStops = 12;
// A clip taller than this (its height over its width) is a Canvas: it is drawn to the full player height
// and cut at its sides. At or below it — a 1:1 or 3:4 cover — the clip keeps its own aspect and is centred
// in the player height, so it is shown whole and resizeAspectFill crops nothing. (The Taurus placement.)
static const CGFloat kFillAspect = 1.5f;

static char kReadyContext, kViewKey;

#define say(format, ...) SGLog(@"redesign player: animated: " format, ##__VA_ARGS__)

#pragma mark - a clip

// The brighter part of the clip, read once off the main thread from three small frames; `done` on the main
// queue, with kUnknownLight when none could be read.
static void readLight(NSURL *file, void (^done)(float light)) {
    AVAssetImageGenerator *generator = [AVAssetImageGenerator assetImageGeneratorWithAsset:[AVURLAsset URLAssetWithURL:file options:nil]];
    generator.appliesPreferredTrackTransform = YES;
    generator.maximumSize = CGSizeMake(48, 48);
    NSMutableData *lights = [NSMutableData data];
    __block NSUInteger pending = 3;
    for (NSNumber *second in @[@0, @1, @2]) {
        [generator generateCGImageAsynchronouslyForTime:CMTimeMakeWithSeconds(second.doubleValue, 600) completionHandler:^(CGImageRef frame, CMTime actual, NSError *error) {
            (void)generator;
            enum { kSide = 16 };
            uint8_t px[kSide * kSide * 4] = {0};
            CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
            CGContextRef context = frame ? CGBitmapContextCreate(px, kSide, kSide, 8, kSide * 4, space, (CGBitmapInfo)kCGImageAlphaNoneSkipLast) : NULL;
            CGColorSpaceRelease(space);
            if (context) CGContextDrawImage(context, CGRectMake(0, 0, kSide, kSide), frame);
            CGContextRelease(context);
            float read[kSide * kSide];
            for (int i = 0; context && i < kSide * kSide; i++) {
                float c[3];
                for (int k = 0; k < 3; k++) c[k] = powf(px[i * 4 + k] / 255.0f, 2.2f);
                read[i] = 0.2126f * c[0] + 0.7152f * c[1] + 0.0722f * c[2];
            }
            @synchronized (lights) {
                if (context) [lights appendBytes:read length:sizeof read];
                if (--pending) return;
            }
            NSUInteger count = lights.length / sizeof(float);
            float *values = lights.mutableBytes;
            float light = kUnknownLight;
            if (count) {
                qsort_b(values, count, sizeof(float), ^int(const void *a, const void *b) {
                    float x = *(const float *)a, y = *(const float *)b;
                    return x < y ? -1 : x > y;
                });
                light = values[count * 3 / 4];
            }
            dispatch_async(dispatch_get_main_queue(), ^{ done(light); });
        }];
    }
}

@interface SGRPlayerClip : NSObject
@property (nonatomic, readonly) NSURL *file;
@property (nonatomic, readonly) AVPlayerLayer *layer;
@property (nonatomic, readonly) float light;   // negative until read
@property (nonatomic, readonly) CGFloat aspect;   // height over width; 0 until read
// Once, on the main queue, when its first frame can be drawn, and its light and aspect have been read.
@property (nonatomic, copy) void (^ready)(SGRPlayerClip *clip);
// On the main queue when the aspect becomes known, so the view can lay the clip out at its true shape.
@property (nonatomic, copy) void (^aspectReady)(void);
- (instancetype)initWithFile:(NSURL *)file;
- (void)setPlaying:(BOOL)playing;
- (void)stop;
@end

@implementation SGRPlayerClip {
    AVQueuePlayer *_player;
    AVPlayerLooper *_looper;
    BOOL _observing;
    CGFloat _aspect;
}

// The album hero's player: muted, never on AirPlay, letting the screen lock.
- (instancetype)initWithFile:(NSURL *)file {
    if (!(self = [super init])) return nil;
    _file = file;
    AVQueuePlayer *player = [AVQueuePlayer new];
    player.muted = YES;
    player.allowsExternalPlayback = NO;
    player.preventsDisplaySleepDuringVideoPlayback = NO;
    _looper = [AVPlayerLooper playerLooperWithPlayer:player templateItem:[AVPlayerItem playerItemWithURL:file]];
    _player = player;
    _layer = [AVPlayerLayer playerLayerWithPlayer:player];
    _layer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    NSNull *off = NSNull.null;
    _layer.actions = @{@"bounds": off, @"position": off, @"frame": off, @"opacity": off};
    [_layer addObserver:self forKeyPath:@"readyForDisplay" options:NSKeyValueObservingOptionInitial context:&kReadyContext];
    _observing = YES;
    _light = -1;
    _aspect = 0;
    __weak SGRPlayerClip *weakSelf = self;
    readLight(file, ^(float light) {
        SGRPlayerClip *clip = weakSelf;
        if (!clip) return;
        clip->_light = light;
        [clip checkReady];
    });
    [self readAspect:file];
    return self;
}

// The clip's height over its width, read off its video track (preferred transform applied, so a rotated
// clip reports the way it is drawn). Falls back to 1 (square) so a clip always has a shape to be laid out
// at. The result is delivered on the main queue.
- (void)readAspect:(NSURL *)file {
    __weak SGRPlayerClip *weakSelf = self;
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:file options:nil];
    [asset loadValuesAsynchronouslyForKeys:@[@"tracks"] completionHandler:^{
        CGFloat aspect = 1;
        NSError *error = nil;
        if ([asset statusOfValueForKey:@"tracks" error:&error] == AVKeyValueStatusLoaded) {
            AVAssetTrack *track = [[asset tracksWithMediaType:AVMediaTypeVideo] firstObject];
            CGSize size = track ? CGSizeApplyAffineTransform(track.naturalSize, track.preferredTransform) : CGSizeZero;
            if (size.width > 0 && size.height > 0) aspect = fabs(size.height) / fabs(size.width);
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            SGRPlayerClip *clip = weakSelf;
            if (!clip) return;
            clip->_aspect = aspect;
            if (clip->_aspectReady) clip->_aspectReady();
            [clip checkReady];
        });
    }];
}

- (void)checkReady {
    void (^ready)(SGRPlayerClip *) = _ready;
    if (!ready || _light < 0 || _aspect <= 0 || !_layer.readyForDisplay) return;
    _ready = nil;
    ready(self);
}

- (void)dealloc {
    [self stop];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if (context != &kReadyContext) {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
        return;
    }
    __weak SGRPlayerClip *weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf checkReady]; });
}

- (void)setPlaying:(BOOL)playing {
    if (playing && _player.rate == 0) [_player play];
    else if (!playing && _player.rate != 0) [_player pause];
}

- (void)stop {
    if (_observing) [_layer removeObserver:self forKeyPath:@"readyForDisplay" context:&kReadyContext];
    _observing = NO;
    _ready = nil;
    _aspectReady = nil;
    [_player pause];
    [_looper disableLooping];
    [_layer removeFromSuperlayer];
}

@end

#pragma mark - the view

// The clip over the field, with the dim and the shade that keep the player's text readable on it. The
// view fades as a whole between the field and a clip; one clip replacing another fades in over it.
@interface SGRPlayerAnimatedView ()
@property (nonatomic, readonly) SGRPlayerClip *clip;   // shown or coming in
@property (nonatomic, readonly) BOOL covers;           // a clip lies opaque over the whole field
@property (nonatomic, readonly) BOOL shown;            // on screen or fading in
@property (nonatomic, readonly) CFTimeInterval fadeEnds;
@property (nonatomic, copy) void (^coversChanged)(BOOL covers);
@property (nonatomic, copy) void (^shownChanged)(BOOL shown, NSTimeInterval duration);
@property (nonatomic, copy) void (^windowChanged)(void);
@property (nonatomic, copy) void (^neverReady)(SGRPlayerClip *clip);
- (void)showClip:(SGRPlayerClip *)clip;
- (void)clear:(BOOL)animated;
- (void)setPlaying:(BOOL)playing;
- (void)setLyricsUp:(BOOL)up animated:(BOOL)animated;
@end

@implementation SGRPlayerAnimatedView {
    CALayer *_video;   // container for the clip and a light dim; masked to fade out at the bottom
    CAGradientLayer *_mask;   // eased, many-stop alpha mask that dissolves the clip's bottom edge
    CALayer *_clips;
    CALayer *_dim;
    CAGradientLayer *_ground;   // the full-screen legibility scrim over the Fluid artwork
    UIVisualEffectView *_blur;   // blurs the video's bottom edge so its colours bleed into the field
    NSMutableArray<SGRPlayerClip *> *_leaving;   // under the one coming in until it is in
    BOOL _playing, _lyricsUp;
    float _light;   // the shown clip's
    NSUInteger _generation;
}

// Blending black at `dim` over sRGB scales linear light by about (1 - dim)^2.2.
static float dimFor(float light, BOOL lyricsUp) {
    float ceiling = SGRIncreaseContrast() ? kCeilingContrast : kCeiling;
    float need = light > ceiling ? 1 - powf(ceiling / light, 1 / 2.2f) : 0;
    return MIN(kDimMost, MAX(kDimLeast, need) + (lyricsUp ? kDimLyrics : 0));
}

// Where the clip is drawn: full width, its own aspect, centred in the player height (the Taurus placement),
// so a 1:1 or 3:4 cover is shown whole — resizeAspectFill then fits it exactly and crops nothing. Only a
// clip taller than kFillAspect (a Canvas) is drawn to the full height, centred and cut at its sides.
static CGRect clipFrame(CGFloat width, CGFloat screen, CGFloat aspect) {
    if (aspect <= 0) aspect = 1;
    CGFloat height = round(width * aspect);
    if (aspect > kFillAspect) height = MAX(height, screen);
    if (height > screen) height = screen;
    CGFloat top = round((screen - height) / 2);
    return CGRectMake(0, top, width, height);
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.userInteractionEnabled = NO;
    self.accessibilityElementsHidden = YES;
    self.clipsToBounds = YES;
    self.layer.opacity = 0;
    // Below the video the Fluid artwork shows through, blurred and darkened, so the background keeps the
    // cover's colours the way the lyrics page's background does — not a flat black.
    self.backgroundColor = UIColor.clearColor;
    _leaving = [NSMutableArray array];
    NSNull *off = NSNull.null;
    NSDictionary *still = @{@"bounds": off, @"position": off, @"frame": off, @"opacity": off, @"sublayers": off};
    UIColor *black = UIColor.blackColor;
    // A light scrim over the whole field, behind the video, so the title and controls read against the
    // Fluid artwork's colours without a hard seam where the video ends — the scrim is continuous under
    // the opaque video and shows through only where the video dissolves, exactly as BitChord draws its
    // mesh backdrop's scrim across the whole player.
    _ground = [CAGradientLayer layer];
    _ground.actions = still;
    // Many-stop, ease-in ramp rather than two stops: the bottom of the artwork
    // dissolves into this scrim, so its darkening must read continuous there (no
    // flat-shaded band). BitChord does the same for its mesh backdrop's scrim.
    _ground.colors = @[
        (id)[black colorWithAlphaComponent:0.06].CGColor,
        (id)[black colorWithAlphaComponent:0.12].CGColor,
        (id)[black colorWithAlphaComponent:0.20].CGColor,
        (id)[black colorWithAlphaComponent:0.28].CGColor,
        (id)[black colorWithAlphaComponent:0.34].CGColor,
    ];
    _ground.locations = @[@0, @0.35, @0.65, @0.85, @1];
    [self.layer addSublayer:_ground];
    // The video band (clip + a light dim) lives in one container so a single gradient mask can dissolve
    // its bottom edge into the Fluid artwork behind it — the way BitChord, LyricsBlossom and Apple Music
    // fade a motion cover out rather than blurring it. The full-screen ground scrim below does the
    // legibility darkening uniformly, so there is no seam where the video ends.
    _video = [CALayer layer];
    _video.actions = still;
    [self.layer addSublayer:_video];
    _clips = [CALayer layer];
    _clips.actions = still;
    [_video addSublayer:_clips];
    _dim = [CALayer layer];
    _dim.actions = still;
    _dim.backgroundColor = black.CGColor;
    _light = kUnknownLight;
    _dim.opacity = dimFor(_light, NO);
    [_video addSublayer:_dim];
    // BitChord-style dissolve: a single eased, many-stop alpha mask on the video
    // container fades its bottom edge to nothing, so the clip melts into the Fluid
    // artwork below it instead of stopping on a line. The ease-in (1 - u^3) keeps
    // the clip fully shown until well into the dissolve band, then drops fast near
    // the very bottom, hiding where the layer ends; many stops stop it banding.
    _mask = [CAGradientLayer layer];
    _mask.actions = still;
    NSMutableArray *maskColors = [NSMutableArray arrayWithCapacity:kMaskStops + 2];
    NSMutableArray *maskLocations = [NSMutableArray arrayWithCapacity:kMaskStops + 2];
    [maskColors addObject:(id)UIColor.whiteColor.CGColor];
    [maskLocations addObject:@0];
    [maskColors addObject:(id)UIColor.whiteColor.CGColor];
    [maskLocations addObject:@(kDissolveStart)];
    for (NSInteger i = 1; i <= kMaskStops; i++) {
        CGFloat u = (CGFloat)i / kMaskStops;
        CGFloat alpha = 1 - powf(u, 3.0f);   // EaseInCubic from shown to clear
        [maskColors addObject:(id)[UIColor colorWithWhite:1 alpha:alpha].CGColor];
        [maskLocations addObject:@(kDissolveStart + u * (1 - kDissolveStart))];
    }
    _mask.colors = maskColors;
    _mask.locations = maskLocations;
    // A blur over the video's dissolve region samples the clip itself, so its colours bleed down into
    // the Fluid artwork rather than stopping on the alpha edge — the same trick LyricsBlossom and
    // Apple Music use to marry a motion cover to its colour field.
    _blur = [[UIVisualEffectView alloc] initWithEffect:nil];
    _blur.userInteractionEnabled = NO;
    _blur.hidden = YES;
    [self addSubview:_blur];
    return self;
}

- (void)dealloc {
    [_clip stop];
    for (SGRPlayerClip *clip in _leaving) [clip stop];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect bounds = self.bounds;
    CGFloat w = bounds.size.width, h = bounds.size.height;
    // The clip is laid out at its own aspect and centred in the player height, so a 1:1 or 3:4 cover shows
    // whole (resizeAspectFill then crops nothing); only a Canvas fills the height. Below the clip the Fluid
    // artwork (the field) carries on, following the cover's colours as it does everywhere else in the player.
    CGRect vf = clipFrame(w, h, _clip ? _clip.aspect : 0);
    _video.frame = vf;
    // Dissolve the clip's bottom edge into the Fluid artwork below (BitChord-style),
    // rather than leaving the hard rectangle the blur alone could not hide.
    _mask.frame = _video.bounds;
    _video.mask = _mask;
    _clips.frame = _video.bounds;
    _dim.frame = _video.bounds;
    _clip.layer.frame = _video.bounds;
    for (SGRPlayerClip *clip in _leaving) clip.layer.frame = _video.bounds;
    // The blur ramps in over the lower half of the cover and stays on down to the bottom of the screen.
    // It smears the clip's bottom edge into the Fluid artwork so the two meet on a colour field rather
    // than a line — no hard rectangle, and no cropping because the blur sits over the field, not over a
    // stretched copy of the clip. Its anchor follows the cover, so the marriage holds wherever the cover
    // now sits.
    _blur.frame = bounds;
    CAGradientLayer *blurMask = (CAGradientLayer *)_blur.layer.mask;
    if (![blurMask isKindOfClass:CAGradientLayer.class]) {
        blurMask = [CAGradientLayer layer];
        _blur.layer.mask = blurMask;
    }
    blurMask.colors = @[
        (id)UIColor.clearColor.CGColor,   // top half of the cover: sharp clip
        (id)UIColor.clearColor.CGColor,
        (id)UIColor.blackColor.CGColor,   // past the cover: fully blurred field
        (id)UIColor.blackColor.CGColor,
    ];
    CGFloat mid = CGRectGetMidY(vf);
    CGFloat pastBottom = MIN(h, CGRectGetMaxY(vf) + 0.1 * vf.size.height);
    blurMask.locations = @[@0, @(mid / h), @(pastBottom / h), @1];
    blurMask.frame = bounds;
    // Scrim over the whole field so the title and controls read against the Fluid artwork; the opaque
    // clip hides it up top, the blur reveals it below.
    _ground.frame = bounds;
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (_windowChanged) _windowChanged();
}

- (void)setCovers:(BOOL)covers {
    if (covers == _covers) return;
    _covers = covers;
    if (_coversChanged) _coversChanged(covers);
}

static float shownOpacity(CALayer *layer) {
    return ((CALayer *)layer.presentationLayer ?: layer).opacity;
}

// From wherever it is now, so a fade caught halfway turns back without a jump.
static void fade(CALayer *layer, float to, NSTimeInterval duration) {
    float from = shownOpacity(layer);
    layer.opacity = to;
    if (duration <= 0 || fabsf(from - to) < 0.001f) {
        [layer removeAnimationForKey:@"fade"];
        return;
    }
    CABasicAnimation *animation = [CABasicAnimation animationWithKeyPath:@"opacity"];
    animation.fromValue = @(from);
    animation.toValue = @(to);
    animation.duration = duration;
    animation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    [layer addAnimation:animation forKey:@"fade"];
}

// The view's own fade, which the covers keep in step with.
- (void)fadeTo:(BOOL)shown duration:(NSTimeInterval)duration {
    float to = shown ? 1 : 0;
    if (fabsf(shownOpacity(self.layer) - to) < 0.001f) duration = 0;
    fade(self.layer, to, duration);
    // UIVisualEffectView does not follow its superview's opacity; pull the effect and hide it when the
    // clip is gone so it cannot blur the cover underneath.
    if (!shown) {
        _blur.effect = nil;
        _blur.hidden = YES;
    } else {
        _blur.hidden = NO;
        // Hold off the blur until the clip has finished fading in. While the clip is still transparent
        // the blur would sample the black field behind it and paint a dark rectangle at the bottom.
        NSTimeInterval delay = duration;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (self->_shown) self->_blur.effect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleRegular];
        });
    }
    _fadeEnds = CACurrentMediaTime() + duration;
    if (shown == _shown) return;
    _shown = shown;
    if (_shownChanged) _shownChanged(shown, duration);
}

- (void)showClip:(SGRPlayerClip *)clip {
    if (!clip || clip == _clip) return;
    NSUInteger generation = ++_generation;
    if (_clip) [_leaving addObject:_clip];
    _clip = clip;
    clip.layer.frame = clipFrame(self.bounds.size.width, self.bounds.size.height, clip.aspect);
    clip.layer.opacity = 0;
    [_clips addSublayer:clip.layer];
    [clip setPlaying:_playing];
    __weak SGRPlayerAnimatedView *weakSelf = self;
    clip.ready = ^(SGRPlayerClip *ready) { [weakSelf fadeIn:ready generation:generation]; };
    // The aspect may still be loading; lay the clip out again the moment it is known, before it fades in.
    clip.aspectReady = ^{ [weakSelf setNeedsLayout]; [weakSelf layoutIfNeeded]; };
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kReadyWithin * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        SGRPlayerAnimatedView *view = weakSelf;
        if (!view || view.clip != clip || clip.layer.readyForDisplay) return;
        if (view.neverReady) view.neverReady(clip);
    });
}

- (void)dropLeaving {
    for (SGRPlayerClip *clip in _leaving) [clip stop];
    [_leaving removeAllObjects];
}

- (void)fadeIn:(SGRPlayerClip *)clip generation:(NSUInteger)generation {
    if (clip != _clip || generation != _generation) return;
    __weak SGRPlayerAnimatedView *weakSelf = self;
    [CATransaction begin];
    [CATransaction setCompletionBlock:^{
        SGRPlayerAnimatedView *view = weakSelf;
        if (!view || generation != view->_generation) return;
        [view dropLeaving];
        [view setCovers:YES];
    }];
    _light = clip.light;
    fade(_dim, dimFor(_light, _lyricsUp), shownOpacity(self.layer) > 0.01f ? kFadeIn : 0);
    say(@"%@ fades in, its light %.2f dimmed by %.2f", clip.file.lastPathComponent, _light, dimFor(_light, _lyricsUp));
    // Over a clip still on screen the new one fades in on top of it; over the field the whole view does.
    if (_leaving.count && shownOpacity(self.layer) > 0.01f) {
        clip.layer.opacity = 0;
        fade(clip.layer, 1, kFadeIn);
    } else {
        clip.layer.opacity = 1;
        [self dropLeaving];
    }
    // While the lyrics are up the clip stays hidden behind them; it shows when they close.
    [self fadeTo:!_lyricsUp duration:kFadeIn];
    [CATransaction commit];
}

- (void)clear:(BOOL)animated {
    if (!_clip && !_leaving.count && shownOpacity(self.layer) < 0.001f) return;
    NSUInteger generation = ++_generation;
    [self setCovers:NO];
    if (_clip) [_leaving addObject:_clip];
    _clip.ready = nil;
    _clip = nil;
    __weak SGRPlayerAnimatedView *weakSelf = self;
    [CATransaction begin];
    [CATransaction setCompletionBlock:^{
        SGRPlayerAnimatedView *view = weakSelf;
        if (view && generation == view->_generation) [view dropLeaving];
    }];
    [self fadeTo:NO duration:animated && self.window ? kFadeOut : 0];
    [CATransaction commit];
}

- (void)setPlaying:(BOOL)playing {
    _playing = playing;
    [_clip setPlaying:playing];
    for (SGRPlayerClip *clip in _leaving) [clip setPlaying:playing];
}

- (void)setLyricsUp:(BOOL)up animated:(BOOL)animated {
    _lyricsUp = up;
    NSTimeInterval duration = animated && self.window ? kDimChange : 0;
    fade(_dim, dimFor(_light, up), duration);
    // On the lyrics page the clip steps aside so Fluid artwork is the only thing behind the words,
    // the same look as Fluid artwork mode.
    [self fadeTo:!up duration:duration];
}

@end

#pragma mark - finding the clip

// What a track's sources gave: the clip on disk, or none from any of them.
@interface SGRPlayerFound : NSObject
@property (nonatomic, strong) NSURL *file;
@property (nonatomic, copy) NSString *source, *note;
@property (nonatomic) BOOL hadCanvas;   // the track's metadata carried a Canvas when it was asked
@end

@implementation SGRPlayerFound
@end

static __weak SGRPlayerAnimatedView *sg_view;
static __weak SGRArtworkField *sg_field;
static NSString *sg_wanted;   // the playing track, once its clip is asked for
static NSString *sg_next;     // the track up next, once its clip is fetched ahead
static NSMutableDictionary<NSString *, SGRPlayerFound *> *sg_found;
static NSMutableSet<NSString *> *sg_looking;
static NSHashTable *sg_videos;   // Spotify's own video views with a video on them
static BOOL sg_lyricsUp;
// Read at launch and when the choice changes, not on each of the plane's layout passes.
static BOOL sg_picked;

static void update(void);


static NSString *nameOf(NSString *source) {
    if ([source isEqualToString:SGArtworkSourceSpotify]) return @"Spotify Canvas";
    if ([source isEqualToString:SGArtworkSourceApple]) return @"Apple Music";
    return source ?: @"no source";
}

static SGCanvas *canvasOf(SPTPlayerTrack *track) {
    return SGCanvasFromMetadata([track respondsToSelector:@selector(metadata)] ? track.metadata : nil);
}

static SPTPlayerTrack *upNext(SPTPlayerState *state) {
    id future = [state respondsToSelector:@selector(future)] ? state.future : nil;
    id next = [future isKindOfClass:NSArray.class] ? [(NSArray *)future firstObject] : nil;
    return [next isKindOfClass:objc_getClass("SPTPlayerTrack")] ? next : nil;
}

// Why no clip may play at all right now, or nil.
static NSString *heldBack(void) {
    if (!sg_picked) return @"Fluid artwork is picked";
    if (NSProcessInfo.processInfo.lowPowerModeEnabled) return @"Low Power Mode";
    if (SGRReduceMotion()) return @"Reduce Motion";
    if (sg_videos.allObjects.count) return @"Spotify's own video is showing";
    return nil;
}

static BOOL stillWanted(NSString *uri) {
    return [uri isEqualToString:sg_wanted] || [uri isEqualToString:sg_next];
}

// A download joined from the lock screen fails when the lock screen cancels it, so a failure is asked once more.
static void fetch(SGCanvas *clip, BOOL again, void (^done)(NSURL *file, NSString *note)) {
    SGArtworkFetchAside(clip.identifier, clip.address, ^(NSURL *file, NSString *note) {
        void (^answer)(void) = ^{
            if (!file && !again) fetch(clip, YES, done);
            else done(file, note);
        };
        if (NSThread.isMainThread) answer();
        else dispatch_async(dispatch_get_main_queue(), answer);
    });
}

// The sources in order until one has a clip on disk. A clip already at hand answers before this returns.
static void walk(NSString *uri, SPTPlayerTrack *track, SGCanvas *canvas, NSArray<NSString *> *order, NSUInteger at,
                 void (^done)(NSURL *file, NSString *source, NSString *note)) {
    if (at >= order.count) {
        done(nil, nil, order.count ? [NSString stringWithFormat:@"none from %@", [order componentsJoinedByString:@", "]] : @"no source is on");
        return;
    }
    NSString *source = order[at];
    SGArtworkAsk(source, track, canvas, YES, ^(SGCanvas *clip, NSString *note) {
        if (!stillWanted(uri)) {
            done(nil, nil, @"moved on");
            return;
        }
        if (!clip.video) {
            say(@"%@ has no clip for %@ (%@)", nameOf(source), uri, clip ? @"a still canvas" : note);
            walk(uri, track, canvas, order, at + 1, done);
            return;
        }
        fetch(clip, NO, ^(NSURL *file, NSString *fetched) {
            if (file) {
                done(file, source, [NSString stringWithFormat:@"%@, %@", note, fetched]);
                return;
            }
            say(@"%@'s clip for %@ not fetched: %@", nameOf(source), uri, fetched);
            if (stillWanted(uri)) walk(uri, track, canvas, order, at + 1, done);
            else done(nil, nil, @"moved on");
        });
    });
}

static void arrived(NSString *uri);
static void prefetchNext(void);

static void find(NSString *uri, SPTPlayerTrack *track, SGCanvas *canvas) {
    if (!uri || sg_found[uri] || [sg_looking containsObject:uri]) return;
    [sg_looking addObject:uri];
    walk(uri, track, canvas, SGArtworkOrderFor(SGRKeyPlayerArtworkSources), 0, ^(NSURL *file, NSString *source, NSString *note) {
        [sg_looking removeObject:uri];
        if (!stillWanted(uri)) return;
        SGRPlayerFound *found = [SGRPlayerFound new];
        found.file = file;
        found.source = source;
        found.note = note;
        found.hadCanvas = canvas != nil;
        sg_found[uri] = found;
        if ([uri isEqualToString:sg_wanted]) arrived(uri);
        else say(@"up next, %@: %@", uri, file ? [NSString stringWithFormat:@"%@ ready (%@)", nameOf(source), note] : note);
    });
}

static void playOrHold(void);

static void arrived(NSString *uri) {
    SGRPlayerAnimatedView *view = sg_view;
    SGRPlayerFound *found = sg_found[uri];
    if (!view || !found || ![uri isEqualToString:sg_wanted]) return;
    if (!found.file) {
        if (view.clip) say(@"fades to Fluid artwork, no clip for %@", uri);
        [view clear:YES];
        say(@"no clip for %@: %@", uri, found.note);
    } else if ([view.clip.file isEqual:found.file]) {
        say(@"%@ goes on with the same clip", uri);
    } else {
        say(@"%@ for %@ (%@), %@", nameOf(found.source), uri, found.note, view.clip ? @"crosses over from the last clip" : @"fades in over Fluid artwork");
        [view showClip:[[SGRPlayerClip alloc] initWithFile:found.file]];
        playOrHold();
    }
    prefetchNext();
}

// Once the playing track's clip is settled: the next track's is fetched ahead, so a skip can go straight to it.
static void prefetchNext(void) {
    if (!sg_view.window || heldBack() || !sg_wanted || !sg_found[sg_wanted]) return;
    SPTPlayerTrack *next = upNext(SGPlayerState());
    NSString *uri = SGURIString(next.URI);
    if (!uri || [uri isEqualToString:sg_wanted] || sg_found[uri] || [sg_looking containsObject:uri]) return;
    sg_next = uri;
    say(@"fetching ahead for %@", uri);
    find(uri, next, canvasOf(next));
}

// Metadata that lands after the lookup: a Canvas the sources were asked without is asked for again when
// Spotify comes before the source that answered.
static void canvasLanded(NSString *uri, SPTPlayerTrack *track, SGCanvas *canvas) {
    SGRPlayerFound *found = sg_found[uri];
    if (!canvas || !found || found.hadCanvas) return;
    NSArray<NSString *> *order = SGArtworkOrderFor(SGRKeyPlayerArtworkSources);
    NSUInteger spotifyAt = [order indexOfObject:SGArtworkSourceSpotify];
    if (spotifyAt == NSNotFound || (found.file && [order indexOfObject:found.source] < spotifyAt)) return;
    say(@"%@ names a Canvas it had not when asked, asked again", uri);
    [sg_found removeObjectForKey:uri];
    find(uri, track, canvas);
}

static void resolve(SPTPlayerState *state) {
    SPTPlayerTrack *track = state.track;
    NSString *uri = SGURIString(track.URI);
    if (!uri) return;
    SGCanvas *canvas = canvasOf(track);
    if ([uri isEqualToString:sg_wanted]) {
        canvasLanded(uri, track, canvas);
        prefetchNext();
        return;
    }
    sg_wanted = uri;
    for (NSString *kept in sg_found.allKeys) {
        if (![kept isEqualToString:uri] && ![kept isEqualToString:sg_next]) [sg_found removeObjectForKey:kept];
    }
    if ([sg_next isEqualToString:uri]) sg_next = nil;
    // Fetched ahead, the track may not have named its Canvas yet.
    canvasLanded(uri, track, canvas);
    BOOL ahead = sg_found[uri] != nil;
    // A walk that answers at once arrives by itself.
    find(uri, track, canvas);
    if (ahead) {
        arrived(uri);
    } else if (!sg_found[uri] && sg_view.clip) {
        say(@"fades to Fluid artwork while %@'s clip is found", uri);
        [sg_view clear:YES];
    }
}

#pragma mark - playing and holding

static void playOrHold(void) {
    SGRPlayerAnimatedView *view = sg_view;
    if (!view) return;
    UIApplicationState state = UIApplication.sharedApplication.applicationState;
    NSString *why = nil;
    if (!view.window) why = @"the player is not on screen";
    else if (state != UIApplicationStateActive) why = @"the app is not in front";
    else if (SGRPlayerIsTransitioning()) why = @"the player opens or closes";
    else if (SGPlayerState().isPaused) why = @"the song is paused";
    [view setPlaying:!why];
    static NSString *said;
    NSString *now = why ?: @"plays";
    if (!view.clip || [now isEqualToString:said]) return;
    said = now;
    say(@"%@", why ? [@"holds its frame, " stringByAppendingString:why] : @"plays");
}

static void update(void) {
    SGRPlayerAnimatedView *view = sg_view;
    if (!view) return;
    NSString *held = heldBack();
    if (held) {
        if (view.clip) say(@"fades to Fluid artwork: %@", held);
        [view clear:YES];
        sg_wanted = nil;
        sg_next = nil;
    } else if (view.window && UIApplication.sharedApplication.applicationState != UIApplicationStateBackground) {
        resolve(SGPlayerState());
    }
    playOrHold();
}

static void covered(BOOL covers) {
    SGRArtworkField *field = sg_field;
    // The video only covers the top of the screen; below it Fluid artwork is the background, so it keeps
    // drawing and the colours stay matched to the cover, like the lyrics page's background.
    field.covered = NO;
    say(@"Fluid artwork draws while the clip sits over the top of the screen");
}

// The cover goes as a clip fades in and comes back as it fades out, over the same time (PlayerArtwork.x).
static void shownChanged(BOOL shown, NSTimeInterval duration) {
    say(@"the cover %@ over %.2f s", shown ? @"goes as the clip fades in" : @"comes back as the clip fades out", duration);
    if (shown) SGRPlayerFitClipToCover();
    SGRPlayerCoversFollowClip(duration);
}

BOOL SGRPlayerAnimatedShowing(CGFloat *shown, NSTimeInterval *left) {
    SGRPlayerAnimatedView *view = sg_view;
    if (shown) *shown = view ? shownOpacity(view.layer) : 0;
    if (left) *left = view ? MAX(0, view.fadeEnds - CACurrentMediaTime()) : 0;
    return view.shown;
}

UIView *SGRPlayerAnimatedViewIn(UIView *plane, SGRArtworkField *field) {
    SGRPlayerAnimatedView *view = objc_getAssociatedObject(plane, &kViewKey);
    if (!sg_picked) {
        // Kept until it has faded out to the field.
        if (view && !view.clip && shownOpacity(view.layer) < 0.01f) {
            [view removeFromSuperview];
            objc_setAssociatedObject(plane, &kViewKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            field.covered = NO;
            return nil;
        }
        return view;
    }
    if (!view) {
        view = [[SGRPlayerAnimatedView alloc] initWithFrame:plane.bounds];
        objc_setAssociatedObject(plane, &kViewKey, view, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        view.coversChanged = ^(BOOL covers) { covered(covers); };
        view.shownChanged = ^(BOOL shown, NSTimeInterval duration) { shownChanged(shown, duration); };
        view.windowChanged = ^{ update(); };
        view.neverReady = ^(SGRPlayerClip *clip) {
            say(@"%@ could not be drawn, Fluid artwork stays", clip.file.lastPathComponent);
            SGRPlayerFound *found = sg_wanted ? sg_found[sg_wanted] : nil;
            if ([found.file isEqual:clip.file]) found.file = nil;
            [sg_view clear:YES];
        };
        [view setLyricsUp:sg_lyricsUp animated:NO];
        say(@"view made in the background plane");
    }
    sg_field = field;
    // The clip is a square over the cover; Fluid artwork always draws behind it.
    field.covered = NO;
    // Another player's plane: the covers follow its clip instead.
    if (sg_view != view) {
        sg_view = view;
        SGRPlayerCoversFollowClip(0);
    }
    return view;
}

void SGRPlayerAnimatedFollowLyrics(BOOL open, BOOL animated) {
    sg_lyricsUp = open;
    [sg_view setLyricsUp:open animated:animated];
}

#pragma mark - the player

@interface SGRPlayerAnimatedWatcher : NSObject <SGPlayerStateObserver>
@end

@implementation SGRPlayerAnimatedWatcher {
    NSString *_track;
}

- (void)playerStateDidChange:(SPTPlayerState *)state {
    NSString *uri = SGURIString(state.track.URI);
    SGRPlayerAnimatedView *view = sg_view;
    // Out of sight nothing is looked up, and the last track's clip must not greet the player as it opens.
    if (uri && ![uri isEqualToString:_track]) {
        _track = uri;
        if (!view.window || UIApplication.sharedApplication.applicationState == UIApplicationStateBackground) {
            [view clear:NO];
            sg_wanted = nil;
        }
    }
    update();
}

@end

static SGRPlayerAnimatedWatcher *sg_watcher;

// Switch to video puts a music video where the cover is, on one of these; the clip goes while it is on.
static void spotifyVideo(id owner, BOOL attached) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!sg_videos) sg_videos = [NSHashTable weakObjectsHashTable];
        BOOL was = sg_videos.allObjects.count > 0;
        if (attached) [sg_videos addObject:owner];
        else [sg_videos removeObject:owner];
        BOOL now = sg_videos.allObjects.count > 0;
        if (now == was) return;
        say(@"Spotify's own video %@ (%@)", now ? @"shows" : @"is gone", NSStringFromClass([owner class]));
        update();
    });
}

%hook _TtC28NowPlaying_ContentLayersImpl24HorizontalVideoViewModel
- (void)videoSurfaceDidAttachVideo:(id)surface {
    %orig;
    spotifyVideo(self, YES);
}
- (void)videoSurfaceDidDetachVideo:(id)surface {
    %orig;
    spotifyVideo(self, NO);
}
%end

%hook _TtC28NowPlaying_ContentLayersImpl31VerticalVideoCellImplementation
- (void)videoSurfaceDidAttachVideo:(id)surface {
    %orig;
    spotifyVideo(self, YES);
}
- (void)videoSurfaceDidDetachVideo:(id)surface {
    %orig;
    spotifyVideo(self, NO);
}
%end

%hook _TtC22NowPlaying_ElementsKit14VideoElementUI
- (void)videoSurfaceDidAttachVideo:(id)surface {
    %orig;
    spotifyVideo(self, YES);
}
- (void)videoSurfaceDidDetachVideo:(id)surface {
    %orig;
    spotifyVideo(self, NO);
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
    sg_found = [NSMutableDictionary dictionary];
    sg_looking = [NSMutableSet set];
    sg_watcher = [SGRPlayerAnimatedWatcher new];
    SGAddPlayerStateObserver(sg_watcher);
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    sg_picked = SGRPlayerBackgroundStyle() == SGRPlayerBackgroundAnimated;
    [center addObserverForName:SGRPlayerBackgroundDidChangeNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
        sg_picked = SGRPlayerBackgroundStyle() == SGRPlayerBackgroundAnimated;
        say(@"%@ picked", sg_picked ? @"Animated artwork" : @"Fluid artwork");
        update();
    }];
    // The main queue, since the power state is reported off it.
    for (NSNotificationName name in @[UIApplicationDidBecomeActiveNotification, UIApplicationWillResignActiveNotification,
                                      UIApplicationDidEnterBackgroundNotification, UIApplicationWillEnterForegroundNotification,
                                      NSProcessInfoPowerStateDidChangeNotification, UIAccessibilityReduceMotionStatusDidChangeNotification]) {
        [center addObserverForName:name object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) { update(); }];
    }
    SGRObservePlayerTransition(sg_watcher, ^(id owner) { playOrHold(); }, ^(id owner) { playOrHold(); });
    SGRequireClasses(@[
        @"_TtC28NowPlaying_ContentLayersImpl24HorizontalVideoViewModel",
        @"_TtC28NowPlaying_ContentLayersImpl31VerticalVideoCellImplementation",
        @"_TtC22NowPlaying_ElementsKit14VideoElementUI",
    ]);
}
