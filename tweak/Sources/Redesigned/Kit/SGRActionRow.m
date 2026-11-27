// The action row's controls: the Play capsule and the button that stands in for one of Spotify's.
//
// Both are drawn from what Spotify's own button shows, and neither keeps state of its own. The glyph is
// looked for past what is hidden behind it -- a play button's glow ring is a hidden view holding an image
// of its own, and taken for the glyph it put a soft green ring in the capsule (device, 2026-09-17) -- and
// it is watched afterward, because Spotify swaps play for pause without laying the header out again.
#import "Core/SGCore.h"
#import "SGRActionRow.h"
#import "SGRGlass.h"
#import "SGRRestyle.h"
#import "SGRTokens.h"
#import "SGRAccent.h"
#import "SGRDownload.h"
#import "SGRHeaderInfo.h"
#import "Redesigned/Player/Player.h"
#import "Shared/AlbumQueue/AlbumQueue.h"

// The capsule: the glyph is Spotify's own 48pt canvas with the triangle small in the middle of it, so the
// lead is short and the gap to the word comes out of the canvas itself.
static const CGFloat kGlyphSide = 44, kCapsuleLead = 4, kCapsuleTrail = 20;
// The mirrored glyph, the size Spotify draws one inside a 48pt round button.
static const CGFloat kMirrorGlyph = 24;

static char kCapsuleGlassKey, kMirrorGlassKey;

// The glyph Spotify's button draws: an image view of the button's own size that nothing hidden is in the
// way of. `side` is the size to match, 0 for any image view that is showing.
static UIImageView *glyphIn(UIView *button, CGFloat side) {
    __block UIImageView *glyph = nil;
    SGForEachView(button, ^(UIView *v) {
        if (glyph || ![v isKindOfClass:UIImageView.class] || !((UIImageView *)v).image) return;
        if (side > 0 && (fabs(v.bounds.size.width - side) > 2 || fabs(v.bounds.size.height - side) > 2)) return;
        for (UIView *up = v; up && up != button; up = up.superview) {
            if (up.hidden || up.alpha <= 0.01) return;
        }
        glyph = (UIImageView *)v;
    });
    return glyph;
}

static NSString *wordIn(UIView *button) {
    __block NSString *word = nil;
    SGForEachView(button, ^(UIView *v) {
        if (!word && v.accessibilityLabel.length) word = v.accessibilityLabel;
    });
    return word;
}

static id stringsAsset(NSBundle *bundle, NSString *asset) {
    NSData *data = bundle ? [[NSDataAsset alloc] initWithName:asset bundle:bundle].data : nil;
    return data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
}

NSDictionary<NSString *, NSSet<NSString *> *> *SGRSpotifyControlWords(void) {
    static NSDictionary *words;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSURL *url = [NSBundle.mainBundle URLForResource:@"SPTStrings" withExtension:@"bundle"];
        NSBundle *bundle = url ? [NSBundle bundleWithURL:url] : nil;
        NSArray *keys = stringsAsset(bundle, @"_i18n.KEYS");
        NSDictionary *files = stringsAsset(bundle, @"_i18n.INDEX");
        NSMutableDictionary *found = [NSMutableDictionary dictionary];
        for (NSString *language in [NSBundle.mainBundle.preferredLocalizations arrayByAddingObject:@"en"]) {
            NSString *file = [files isKindOfClass:NSDictionary.class] ? files[language] : nil;
            NSArray *values = stringsAsset(bundle, [@"_i18n." stringByAppendingString:file ?: language]);
            if (![keys isKindOfClass:NSArray.class] || ![values isKindOfClass:NSArray.class]) continue;
            for (NSString *key in @[@"ShuffleButtonOff", @"ShuffleButtonOn", @"ShuffleButtonOnSmartShuffle",
                                    @"AccessibilityPlay", @"AccessibilityPause", @"AccessibilityShufflePlay"]) {
                NSUInteger i = [keys indexOfObject:[@"encore:sEncore" stringByAppendingString:key]];
                if (i >= values.count || ![values[i] isKindOfClass:NSString.class] || ![values[i] length]) continue;
                if (!found[key]) found[key] = [NSMutableSet set];
                [found[key] addObject:values[i]];
            }
        }
        words = found;
    });
    return words;
}

BOOL SGRPlayButtonPlaying(UIView *button, BOOL *playing) {
    static Class playButton;
    static ptrdiff_t offset = -1;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        playButton = NSClassFromString(@"_TtC28EncoreConsumerMobile_BaseKit14PlayButtonView");
        Ivar ivar = playButton ? class_getInstanceVariable(playButton, "isPlaying") : NULL;
        if (ivar) offset = ivar_getOffset(ivar);
        SGLog(@"redesign kit: PlayButtonView isPlaying %@", ivar ? [NSString stringWithFormat:@"at %td", offset] : @"missing");
    });
    if (offset < 0 || ![button isKindOfClass:playButton]) return NO;
    if (playing) *playing = *((const uint8_t *)(__bridge const void *)button + offset) != 0;
    return YES;
}

// The capsule's word, made again only when the text size changes: the header feeds the capsule on every step of its collapse.
static UIFont *capsuleFont(void) {
    static UIFont *font;
    static UIContentSizeCategory madeFor;
    UIContentSizeCategory category = UIApplication.sharedApplication.preferredContentSizeCategory;
    if (!font || ![category isEqualToString:madeFor]) {
        font = SGCategoryCappedFont(UIFontTextStyleSubheadline, UIFontWeightSemibold, UIContentSizeCategoryLarge);
        madeFor = category;
    }
    return font;
}

// A mirror looks as enabled as the button it stands in for, and says so to accessibility: dimmed, with the
// not-enabled trait. It is never disabled as a control, because Spotify enables and disables a button with no
// pass here and a mirror that cannot be tapped could never hear that the source is back. Every tap reads the
// source (feedFrom:) before it fires, which is what clears the dim.
static const CGFloat kDisabledAlpha = 0.4;
// What a mirror draws is this opaque: dimmed while it says it is not enabled.
static CGFloat enabledAlpha(UIControl *mirror) {
    return mirror.accessibilityTraits & UIAccessibilityTraitNotEnabled ? kDisabledAlpha : 1;
}
// `drawn` nil: the caller dims what it draws itself, from enabledAlpha.
static void takeEnabled(UIControl *mirror, UIView *source, NSArray<UIView *> *drawn) {
    BOOL enabled = SGRSourceEnabled(source);
    if (!(mirror.accessibilityTraits & UIAccessibilityTraitNotEnabled) == enabled) return;
    mirror.accessibilityTraits = enabled ? UIAccessibilityTraitButton : UIAccessibilityTraitButton | UIAccessibilityTraitNotEnabled;
    for (UIView *view in drawn) view.alpha = enabledAlpha(mirror);
}

#pragma mark - the Play capsule

@implementation SGRPlayCapsule {
    UIImageView *_glyph;
    UILabel *_title;
    __weak UIImageView *_watchedGlyph;
    UIImage *_takenGlyph;
    // The cut-out's mask (cutOut), and what it was last drawn from: a pass that changes none of these draws nothing.
    CALayer *_cutMask;
    CGSize _cutSize;
    CGFloat _cutScale;
    UIImage *_cutGlyph;
    CGRect _cutGlyphFrame;
    UIViewContentMode _cutGlyphMode;
    NSString *_cutWord;
    UIFont *_cutFont;
    CGRect _cutWordFrame;
    // Every word shown for the source, and the width they and Spotify's Play and Pause ask for in `_fitFont` (0 until
    // measured): sgr_width.
    NSMutableSet<NSString *> *_words;
    UIFont *_fitFont;
    CGFloat _fitWidth;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    _glyph = [UIImageView new];
    _glyph.contentMode = UIViewContentModeScaleAspectFit;
    _glyph.userInteractionEnabled = NO;
    [self addSubview:_glyph];

    _title = [UILabel new];
    _title.userInteractionEnabled = NO;
    [self addSubview:_title];

    self.isAccessibilityElement = YES;
    self.accessibilityTraits = UIAccessibilityTraitButton;
    [self addTarget:self action:@selector(sgr_down) forControlEvents:UIControlEventTouchDown];
    [self addTarget:self action:@selector(sgr_up) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
    [self addTarget:self action:@selector(sgr_tap) forControlEvents:UIControlEventTouchUpInside];
    return self;
}

// The width the word showing asks for.
- (CGFloat)sgr_wordWidth {
    [_title sizeToFit];
    return kCapsuleLead + kGlyphSide + ceil(_title.bounds.size.width) + kCapsuleTrail;
}

// Measured once per set of words and font: the header asks on every step of its collapse.
- (CGFloat)sgr_width {
    UIFont *font = _title.font ?: capsuleFont();
    if (_fitWidth > 0 && [font isEqual:_fitFont]) return _fitWidth;
    NSDictionary<NSString *, NSSet<NSString *> *> *spotify = SGRSpotifyControlWords();
    NSMutableSet<NSString *> *words = [NSMutableSet setWithSet:_words ?: [NSSet set]];
    for (NSString *key in @[@"AccessibilityPlay", @"AccessibilityPause"]) {
        if (spotify[key]) [words unionSet:spotify[key]];
    }
    CGFloat widest = 0;
    for (NSString *word in words) widest = MAX(widest, ceil([word sizeWithAttributes:@{NSFontAttributeName: font}].width));
    _fitFont = font;
    _fitWidth = kCapsuleLead + kGlyphSide + widest + kCapsuleTrail;
    return _fitWidth;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect bounds = self.bounds;
    if (self.fillColor) {
        if (![self.backgroundColor isEqual:self.fillColor]) self.backgroundColor = self.fillColor;
        self.layer.cornerRadius = bounds.size.height / 2;
        self.layer.cornerCurve = kCACornerCurveContinuous;
    } else {
        SGRGlassCapsuleInside(self, &kCapsuleGlassKey, bounds.size, YES);
    }
    // Given more room than the word asks for, the glyph and the word stay together in the middle; round, the glyph
    // is alone there.
    CGFloat lead = self.round ? round((bounds.size.width - kGlyphSide) / 2)
                              : kCapsuleLead + MAX(0, round((bounds.size.width - [self sgr_wordWidth]) / 2));
    _glyph.frame = CGRectMake(lead, round((bounds.size.height - kGlyphSide) / 2), kGlyphSide, kGlyphSide);
    // Spotify's glyph comes on a 48pt canvas and is scaled down into the frame; one drawn tight is shown at
    // its own size instead of blown up to fill it.
    CGSize image = _glyph.image.size;
    UIViewContentMode mode = image.width <= kGlyphSide && image.height <= kGlyphSide ? UIViewContentModeCenter : UIViewContentModeScaleAspectFit;
    if (_glyph.contentMode != mode) _glyph.contentMode = mode;
    if (_title.hidden != self.round) _title.hidden = self.round;
    if (!self.round) {
        [_title sizeToFit];
        CGSize text = _title.bounds.size;
        _title.frame = CGRectMake(CGRectGetMaxX(_glyph.frame), round((bounds.size.height - text.height) / 2),
                                  MAX(0, bounds.size.width - kCapsuleTrail - CGRectGetMaxX(_glyph.frame)), text.height);
    }
    [self sgr_cut];
}

- (void)setFillColor:(UIColor *)fillColor {
    if (fillColor == _fillColor || [fillColor isEqual:_fillColor]) return;
    _fillColor = [fillColor copy];
    [self setNeedsLayout];
}

- (void)setCutOut:(BOOL)cutOut {
    if (_cutOut == cutOut) return;
    _cutOut = cutOut;
    [self setNeedsLayout];
}

// Into a window of another scale (the first one, from none): the mask is drawn again at it.
- (void)traitCollectionDidChange:(UITraitCollection *)previous {
    [super traitCollectionDidChange:previous];
    if (_cutMask && previous.displayScale != self.traitCollection.displayScale) [self setNeedsLayout];
}

// The mask that cuts the glyph and the word out of the fill, drawn again only when something it is drawn from changed
// (the fill's color is not one: the mask is alpha alone); with cutOut off or no fill, the mask goes and they are painted.
- (void)sgr_cut {
    if (!self.cutOut || !self.fillColor) {
        if (!_cutMask) return;
        if (self.layer.mask == _cutMask) self.layer.mask = nil;
        _cutMask = nil;
        [self sgr_paintDrawn];
        return;
    }
    CGSize size = self.bounds.size;
    CGFloat scale = self.traitCollection.displayScale;
    NSString *word = _title.hidden ? nil : _title.text;
    BOOL wordSame = word ? [word isEqualToString:_cutWord] && [_title.font isEqual:_cutFont] && CGRectEqualToRect(_title.frame, _cutWordFrame)
                         : !_cutWord;
    if (_cutMask && wordSame && CGSizeEqualToSize(size, _cutSize) && scale == _cutScale && _glyph.image == _cutGlyph
        && CGRectEqualToRect(_glyph.frame, _cutGlyphFrame) && _glyph.contentMode == _cutGlyphMode) return;
    _cutSize = size;
    _cutScale = scale;
    _cutGlyph = _glyph.image;
    _cutGlyphFrame = _glyph.frame;
    _cutGlyphMode = _glyph.contentMode;
    _cutWord = word;
    _cutFont = _title.font;
    _cutWordFrame = _title.frame;
    UIImage *mask = SGRCutOutMask(self, self.bounds, _glyph, _title);
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    if (!_cutMask) _cutMask = [CALayer layer];
    _cutMask.frame = self.bounds;
    _cutMask.contents = (__bridge id)mask.CGImage;
    _cutMask.contentsScale = mask.scale;
    if (self.layer.mask != _cutMask) self.layer.mask = _cutMask;
    [CATransaction commit];
    [self sgr_paintDrawn];
}

// The glyph and the word painted, as enabled as the source; cut out, they paint nothing and the cut fill takes the dim.
- (void)sgr_paintDrawn {
    CGFloat alpha = enabledAlpha(self), painted = _cutMask ? 0 : alpha;
    if (_glyph.alpha != painted) _glyph.alpha = painted;
    if (_title.alpha != painted) _title.alpha = painted;
    if (!_cutMask || _cutMask.opacity == alpha) return;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _cutMask.opacity = alpha;
    [CATransaction commit];
}

- (void)feedFrom:(UIView *)source {
    if (!source) return;
    if (source != _source) {
        _words = [NSMutableSet set];
        _fitWidth = 0;
    }
    _source = source;
    takeEnabled(self, source, nil);
    [self sgr_paintDrawn];

    NSString *word = wordIn(source);
    // The disc is as tall as the button, not always as wide: Liked Songs' is 80x48 with the 48pt disc at
    // x=16 (trees/continuous/1.txt, 2026-09-18), and matched by width the capsule drew no glyph at all.
    CGSize size = source.bounds.size;
    UIImageView *glyph = glyphIn(source, MIN(size.width, size.height));

    UIFont *font = capsuleFont();
    if (![_title.font isEqual:font]) {
        _title.font = font;
        // The word cut out at its new size.
        if (self.cutOut) [self setNeedsLayout];
    }
    UIColor *content = self.contentColor ?: SGRAccent();
    if (![_title.textColor isEqual:content]) _title.textColor = content;
    if (word && ![_title.text isEqualToString:word]) {
        _title.text = word;
        self.accessibilityLabel = word;
        [self setNeedsLayout];
    }
    // The header sizes the capsule to every word it can show ("Play", "Pause", "Shuffle Play" with shuffle on): one it
    // has not seen yet may widen it.
    if (word && ![_words containsObject:word]) {
        [_words addObject:word];
        _fitWidth = 0;
        [self.superview setNeedsLayout];
    }
    if (![_glyph.tintColor isEqual:content]) _glyph.tintColor = content;

    if (glyph.image && _takenGlyph != glyph.image) {
        _takenGlyph = glyph.image;
        _glyph.image = [glyph.image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        // Play turned pause: the cut follows, its content mode with it.
        if (self.cutOut) [self setNeedsLayout];
        static dispatch_once_t once;
        dispatch_once(&once, ^{
            SGLog(@"redesign kit: play glyph %@ from %@, word \"%@\"", NSStringFromCGSize(glyph.image.size),
                  NSStringFromClass(glyph.class), word);
        });
    }
    // Play becomes pause without the header laying out again. Watched per glyph view rather than once for
    // good, so a glyph Spotify hands to another button reports to the button it is in now.
    if (glyph && glyph != _watchedGlyph) {
        _watchedGlyph = glyph;
        __weak SGRPlayCapsule *weakSelf = self;
        __weak UIView *weakSource = source;
        SGRObserveImage(glyph, ^(UIImageView *view) {
            if (weakSelf && weakSource) [weakSelf feedFrom:weakSource];
        });
    }
}

- (void)sgr_down {
    SGRAnimate(SGRMotionPress, ^{ self.transform = CGAffineTransformMakeScale(0.94, 0.94); }, nil);
}

- (void)sgr_up {
    SGRAnimate(SGRMotionPress, ^{ self.transform = CGAffineTransformIdentity; }, nil);
}

- (void)sgr_tap {
    [self feedFrom:self.source];
    SGRActivate(self.source);
}

@end

#pragma mark - a button standing in for Spotify's

// Whether a button that marks "on" with a small dot under its glyph (Encore's shuffle, a 4pt round view it
// hides while off) is on. `found` says whether the button has such a dot at all.
static BOOL indicatorOn(UIView *button, BOOL *found) {
    __block UIView *dot = nil;
    SGForEachView(button, ^(UIView *v) {
        if (dot || v == button || [v isKindOfClass:UIImageView.class] || [v isKindOfClass:UILabel.class]) return;
        CGSize size = v.bounds.size;
        if (size.width < 2 || size.width > 8 || size.height < 2 || size.height > 8) return;
        CGColorRef paint = v.layer.backgroundColor;
        if (paint && CGColorGetAlpha(paint) > 0.5) dot = v;
    });
    if (found) *found = dot != nil;
    for (UIView *up = dot; up && up != button; up = up.superview) {
        if (up.hidden || up.alpha <= 0.01) return NO;
    }
    return dot != nil;
}

@interface SGRMirrorButton ()
// For the pinned pair (SGRPinnedDownload): one glass capsule under download and ⋯. Positive, the button's
// glass runs that much further toward the trailing side, under the button beside it (download carries the
// capsule, being under ⋯ so that ⋯'s glyph is above the glass, not taken into it); negative, the button draws no
// glass of its own (⋯, its half drawn by download's). 0, the default, is the button's own circle. While it is
// not 0 a press scales only the glyph, so the capsule both share stays still.
@property (nonatomic) CGFloat sgr_glassReach;
// The reach runs to the left instead: on a page laid out right to left, where ⋯ is pinned in the left corner and
// download on its right (SGRPinnedDownload). Set by whoever places the pair, from the page's own direction.
@property (nonatomic) BOOL sgr_glassReachesLeft;
// The page whose pinned ⋯ this is (SGRPinnedMore), nil on every other button: its tap claims that page for the sheet
// coming up, wherever the button is drawn (SGRHeaderInfo takes it beside the cover). Weak, as the page holds the button.
@property (nonatomic, weak) UIView *sgr_pinnedPage;
@end

static void claimPinnedMore(SGRMirrorButton *button);

@implementation SGRMirrorButton {
    UIImageView *_glyph;
    __weak UIImageView *_watchedGlyph;
    // Spotify's own image, as it was taken: what the copy is compared against, since a copy re-rendered as
    // a template is no longer the same object.
    UIImage *_takenGlyph;
    // Standing in for Spotify's download button: its state drawn, and read again while on screen.
    SGRDownloadGlyph *_download;
    NSTimer *_downloadTimer;
    NSTimeInterval _downloadInterval;
    BOOL _downloadInactive;
    BOOL _downloadWatching;
    BOOL _downloadPaused;
    NSHashTable *_downloadScrolls;
    // A two-state glyph drawn for Spotify (add-to, readState): 1 on, 0 off, -1 none drawn.
    NSInteger _stateShown;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    _glyph = [UIImageView new];
    _glyph.contentMode = UIViewContentModeScaleAspectFit;
    _glyph.userInteractionEnabled = NO;
    [self addSubview:_glyph];
    _stateShown = -1;

    self.isAccessibilityElement = YES;
    self.accessibilityTraits = UIAccessibilityTraitButton;
    [self addTarget:self action:@selector(sgr_down) forControlEvents:UIControlEventTouchDown];
    [self addTarget:self action:@selector(sgr_up) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
    [self addTarget:self action:@selector(sgr_tap) forControlEvents:UIControlEventTouchUpInside];
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    for (NSNotificationName name in @[UIApplicationWillResignActiveNotification, UIApplicationDidEnterBackgroundNotification])
        [center addObserver:self selector:@selector(sgr_downloadResigned) name:name object:nil];
    [center addObserver:self selector:@selector(sgr_downloadBecameActive) name:UIApplicationDidBecomeActiveNotification object:nil];
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect bounds = self.bounds;
    // Until its state is known the button draws nothing: a guess would flash the wrong glyph first.
    if (_downloadPaused) [self sgr_updateDownloadTimer];
    if (self.readState && _stateShown < 0) {
        ((UIView *)objc_getAssociatedObject(self, &kMirrorGlassKey)).hidden = YES;
        return;
    }
    CGFloat reach = self.sgr_glassReach;
    if (reach < 0) {
        ((UIView *)objc_getAssociatedObject(self, &kMirrorGlassKey)).hidden = YES;
    } else {
        CGFloat side = SGRGlassCircleSize;
        UIView *glass = SGRGlassCapsuleInside(self, &kMirrorGlassKey, CGSizeMake(side + reach, side), NO);
        CGFloat shift = self.sgr_glassReachesLeft ? -reach / 2 : reach / 2;
        CGPoint middle = CGPointMake(CGRectGetMidX(bounds) + shift, CGRectGetMidY(bounds));
        if (!CGPointEqualToPoint(glass.center, middle)) glass.center = middle;
    }
    // By bounds and center, not frame: a press scales the glyph itself while the button is paired.
    CGRect glyph = CGRectMake(0, 0, kMirrorGlyph, kMirrorGlyph);
    CGPoint center = CGPointMake(round((bounds.size.width - kMirrorGlyph) / 2) + kMirrorGlyph / 2,
                                 round((bounds.size.height - kMirrorGlyph) / 2) + kMirrorGlyph / 2);
    for (UIView *view in @[_glyph, _download ?: _glyph]) {
        view.bounds = glyph;
        view.center = center;
    }
}

- (void)setSgr_glassReach:(CGFloat)reach {
    if (_sgr_glassReach == reach) return;
    _sgr_glassReach = reach;
    self.transform = CGAffineTransformIdentity;
    _glyph.transform = CGAffineTransformIdentity;
    _download.transform = CGAffineTransformIdentity;
    [self setNeedsLayout];
}

- (void)setSgr_glassReachesLeft:(BOOL)left {
    if (_sgr_glassReachesLeft == left) return;
    _sgr_glassReachesLeft = left;
    [self setNeedsLayout];
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    // Read again on the way in -- the state may have moved on while the page was away -- and not at all
    // while out of the window.
    if (!_downloadPaused && [self sgr_downloadVisible] && self.source && (_download || _stateShown >= 0 || self.readState))
        [self feedFrom:self.source];
    [self sgr_updateDownloadTimer];
}

- (void)dealloc {
    for (UIView *scroll in _downloadScrolls)
        [scroll removeObserver:self forKeyPath:@"contentOffset" context:&_downloadScrolls];
    [_downloadTimer invalidate];
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

// Shows Spotify's download state; YES when `source` is a download button.
- (BOOL)sgr_feedDownloadFrom:(UIView *)source {
    SGRDownloadState state;
    CGFloat progress;
    if (!SGRReadDownload(source, &state, &progress)) {
        if (_download && !_download.hidden) {
            _download.hidden = YES;
            _glyph.hidden = NO;
            [self sgr_followDownload:0];
        }
        return NO;
    }
    if (!_download) {
        _download = [[SGRDownloadGlyph alloc] initWithFrame:CGRectZero];
        _download.bounds = _glyph.bounds;
        _download.center = _glyph.center;
        _download.alpha = _glyph.alpha;
        [self addSubview:_download];
    }
    _download.hidden = NO;
    _glyph.hidden = YES;
    [_download showState:state progress:progress animated:YES];

    NSString *word = source.accessibilityLabel ?: wordIn(source);
    if (word && ![self.accessibilityLabel isEqualToString:word]) self.accessibilityLabel = word;
    NSString *value = state == SGRDownloadDownloading && progress >= 0
        ? [NSNumberFormatter localizedStringFromNumber:@(progress) numberStyle:NSNumberFormatterPercentStyle] : nil;
    if (![self.accessibilityValue ?: @"" isEqualToString:value ?: @""]) self.accessibilityValue = value;

    // Spotify lays nothing out that the page hears as a download moves on, so the state is read again:
    // twice a second while one runs, for the ring, and now and then otherwise, for one started or removed
    // from elsewhere (the ⋯ sheet). Only while the button is on screen.
    BOOL running = state == SGRDownloadWaiting || state == SGRDownloadDownloading;
    [self sgr_followDownload:running ? 0.5 : 2];
    return YES;
}

// The add-to button's saved state, as downloaded is drawn (SGRDownload.m): a fixed 22pt disc in the accent color with a
// dark check, in the middle of the glyph's canvas. Drawn into a bitmap, which the glyph's tint leaves alone; drawn again
// only when the accent resolves to another color (the accent is a live token, one color object for every color it takes).
static const CGFloat kSavedDisc = 22, kSavedCheck = 11;
static UIImage *savedDisc(void) {
    static UIImage *disc;
    static CGFloat drawnIn[4];
    UIColor *accent = [SGRAccent() resolvedColorWithTraitCollection:UITraitCollection.currentTraitCollection];
    CGFloat rgba[4];
    [accent getRed:&rgba[0] green:&rgba[1] blue:&rgba[2] alpha:&rgba[3]];
    if (disc && !memcmp(rgba, drawnIn, sizeof rgba)) return disc;
    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:kSavedCheck weight:UIImageSymbolWeightBold];
    UIImage *check = [[UIImage systemImageNamed:@"checkmark" withConfiguration:config] imageWithTintColor:UIColor.blackColor
                                                                                             renderingMode:UIImageRenderingModeAlwaysOriginal];
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(kMirrorGlyph, kMirrorGlyph)];
    disc = [[renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        CGFloat inset = (kMirrorGlyph - kSavedDisc) / 2;
        [accent setFill];
        [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(inset, inset, kSavedDisc, kSavedDisc)] fill];
        CGSize size = check.size;
        [check drawAtPoint:CGPointMake((kMirrorGlyph - size.width) / 2, (kMirrorGlyph - size.height) / 2)];
    }] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
    memcpy(drawnIn, rgba, sizeof rgba);
    return disc;
}

// Draws `offImage`, or `onImage` (a symbol in the accent color), switching between them in place: a symbol turns into a
// symbol, anything else crossfades. A bitmap drawn in the accent (savedDisc) is put in again when it is another one, as the
// accent changes with the state unchanged: the tint does not reach it.
- (void)sgr_showOn:(BOOL)on off:(UIImage *)offImage on:(UIImage *)onImage source:(UIView *)source {
    UIImage *shown = on ? onImage : offImage;
    if (_stateShown == on && !shown.isSymbolImage && _glyph.image != shown) _glyph.image = shown;
    if (_stateShown != on) {
        UIImage *image = shown;
        BOOL animated = _stateShown >= 0 && self.window && !SGRReduceMotion();
        BOOL first = _stateShown < 0;
        _stateShown = on;
        _takenGlyph = nil;
        _glyph.hidden = NO;
        if (animated && image.isSymbolImage && _glyph.image.isSymbolImage) {
            if (@available(iOS 17.0, *)) [_glyph setSymbolImage:image withContentTransition:[NSSymbolReplaceContentTransition replaceDownUpTransition]];
            else _glyph.image = image;
        } else if (animated) {
            [UIView transitionWithView:_glyph duration:SGRCrossfade options:UIViewAnimationOptionTransitionCrossDissolve
                            animations:^{ self->_glyph.image = image; } completion:nil];
        } else {
            _glyph.image = image;
        }
        // On is saved or followed, in the accent color, as downloaded is.
        _glyph.tintColor = on ? SGRAccent() : SGRPrimary();
        if (first) [self setNeedsLayout];
    }
    NSString *word = source.accessibilityLabel ?: wordIn(source);
    if (word && ![self.accessibilityLabel isEqualToString:word]) self.accessibilityLabel = word;
    // Nothing is laid out when it changes from elsewhere (the ⋯ sheet), so it is read again as download is.
    [self sgr_followDownload:2];
}

// Shows whether Spotify's add-to button has its album or playlist saved; YES when `source` is one.
- (BOOL)sgr_feedAddToFrom:(UIView *)source {
    BOOL added;
    if (!SGRReadAddTo(source, &added)) {
        _stateShown = -1;
        return NO;
    }
    [self sgr_showOn:added off:[UIImage systemImageNamed:@"plus"] on:savedDisc() source:source];
    return YES;
}

// Reads the state again every `interval` seconds; 0 stops.
- (void)sgr_followDownload:(NSTimeInterval)interval {
    _downloadInterval = interval;
    BOOL watch = interval > 0;
    if (watch != _downloadWatching) {
        _downloadWatching = watch;
        if (watch)
            [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(sgr_updateDownloadTimer)
                name:SGRPlayerVisibilityDidChangeNotification object:nil];
        else
            [NSNotificationCenter.defaultCenter removeObserver:self name:SGRPlayerVisibilityDidChangeNotification object:nil];
        __weak SGRMirrorButton *weakSelf = self;
        SGRObserveVisibility(self, watch ? ^{ [weakSelf sgr_updateDownloadTimer]; } : nil);
    }
    [self sgr_updateDownloadTimer];
}

- (BOOL)sgr_downloadVisible {
    if (!self.window || _downloadInactive || UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return NO;
    for (UIView *view = self; view; view = view.superview)
        if (view.hidden || view.alpha <= 0.01) return NO;
    return SGRViewInViewport(self, SGRSettledPlayerRect(self.window));
}

- (void)observeValueForKeyPath:(NSString *)path ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if (context == &_downloadScrolls) [self sgr_updateDownloadTimer];
    else [super observeValueForKeyPath:path ofObject:object change:change context:context];
}

- (void)sgr_downloadResigned {
    // WillResignActive can arrive before applicationState changes.
    _downloadInactive = YES;
    [self sgr_updateDownloadTimer];
}

- (void)sgr_downloadBecameActive {
    _downloadInactive = NO;
    [self sgr_updateDownloadTimer];
}

- (void)sgr_updateDownloadTimer {
    NSTimeInterval interval = _downloadInterval;
    BOOL run = interval > 0 && self.source && [self sgr_downloadVisible];
    // Watch for a scroll back into view only when clipped out, never during ordinary visible polling.
    if (!run && interval > 0 && self.window && CGRectIsEmpty(SGRVisibleRectInWindow(self))) {
        if (!_downloadScrolls) _downloadScrolls = [NSHashTable weakObjectsHashTable];
        SGRBindViewportScrolls(self, _downloadScrolls, self, &_downloadScrolls);
    } else if (_downloadScrolls) {
        for (UIView *scroll in _downloadScrolls)
            [scroll removeObserver:self forKeyPath:@"contentOffset" context:&_downloadScrolls];
        _downloadScrolls = nil;
    }
    if (!run) {
        _downloadPaused = interval > 0;
        [_downloadTimer invalidate];
        _downloadTimer = nil;
        return;
    }
    if (_downloadPaused) {
        _downloadPaused = NO;
        [self feedFrom:self.source];
        // The refreshed state may select a different polling interval.
        interval = _downloadInterval;
        if (!interval) return;
    }
    if (_downloadTimer.valid && fabs(_downloadTimer.timeInterval - interval) < 0.01) return;
    [_downloadTimer invalidate];
    __weak SGRMirrorButton *weakSelf = self;
    _downloadTimer = [NSTimer scheduledTimerWithTimeInterval:interval repeats:YES block:^(NSTimer *timer) {
        SGRMirrorButton *button = weakSelf;
        if (!button) {
            [timer invalidate];
            return;
        }
        if (![button sgr_downloadVisible] || !button.source) {
            [button sgr_updateDownloadTimer];
            return;
        }
        [button feedFrom:button.source];
    }];
    _downloadTimer.tolerance = interval * 0.2;
}

// The glyph is taken as Spotify drew it, color and all: the shuffle button turns its own glyph the accent
// color while shuffle is on, and a copy rendered as a template would lose that.
- (void)feedFrom:(UIView *)source {
    if (!source) return;
    _source = source;
    takeEnabled(self, source, @[_glyph, _download ?: _glyph]);

    if (self.readState) {
        BOOL on = NO;
        if (self.readState(&on)) [self sgr_showOn:on off:[UIImage systemImageNamed:self.stateOffSymbol]
                                                  on:[UIImage systemImageNamed:self.stateOnSymbol] source:source];
        else [self sgr_followDownload:2];
        BOOL known = _stateShown >= 0;
        if (_glyph.hidden == known) _glyph.hidden = !known;
        if (self.userInteractionEnabled != known) {
            self.userInteractionEnabled = known;
            self.isAccessibilityElement = known;
        }
        return;
    }

    if ([self sgr_feedDownloadFrom:source]) return;
    if ([self sgr_feedAddToFrom:source]) return;

    UIImageView *glyph = glyphIn(source, 0);
    NSString *word = source.accessibilityLabel ?: wordIn(source);
    if (word && ![self.accessibilityLabel isEqualToString:word]) self.accessibilityLabel = word;
    // A button that says "on" with its dot is drawn in our colors, on and off. One expected to have a dot
    // and found without keeps Spotify's colors, which are then all that tells on from off.
    BOOL hasDot = NO;
    BOOL on = self.onGlyphColor && indicatorOn(source, &hasDot);
    UIColor *ownColor = !self.onGlyphColor ? self.glyphColor
                      : hasDot ? (on ? self.onGlyphColor : self.glyphColor ?: SGRPrimary()) : nil;
    if (glyph.image && (_takenGlyph != glyph.image || (ownColor != nil) != (_glyph.image.renderingMode == UIImageRenderingModeAlwaysTemplate))) {
        _takenGlyph = glyph.image;
        _glyph.image = ownColor ? [glyph.image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate] : glyph.image;
    }
    if (!glyph && self.fallbackGlyph && _glyph.image != self.fallbackGlyph) {
        _takenGlyph = nil;
        _glyph.image = self.fallbackGlyph;
    }
    UIColor *tint = ownColor ?: (glyph ? glyph.tintColor : SGRPrimary());
    if (tint && ![_glyph.tintColor isEqual:tint]) {
        // Turning on or off is a moment of its own: the color fades across rather than jumping.
        BOOL fade = self.window && _glyph.tintColor && hasDot;
        if (fade) {
            [UIView transitionWithView:_glyph duration:0.2 options:UIViewAnimationOptionTransitionCrossDissolve
                            animations:^{ self->_glyph.tintColor = tint; } completion:nil];
        } else {
            _glyph.tintColor = tint;
        }
    }

    // As the capsule does: watched per glyph view, so a reused one reports where it is now.
    if (glyph && glyph != _watchedGlyph) {
        _watchedGlyph = glyph;
        __weak SGRMirrorButton *weakSelf = self;
        __weak UIView *weakSource = source;
        SGRObserveImage(glyph, ^(UIImageView *view) {
            if (weakSelf && weakSource) [weakSelf feedFrom:weakSource];
        });
    }
}

- (void)sgr_pressed:(BOOL)pressed {
    CGAffineTransform scale = pressed ? CGAffineTransformMakeScale(0.92, 0.92) : CGAffineTransformIdentity;
    BOOL paired = self.sgr_glassReach != 0;
    SGRAnimate(SGRMotionPress, ^{
        if (!paired) {
            self.transform = scale;
            return;
        }
        self->_glyph.transform = scale;
        self->_download.transform = scale;
    }, nil);
}

- (void)sgr_down {
    [self sgr_pressed:YES];
}

- (void)sgr_up {
    [self sgr_pressed:NO];
}

- (void)sgr_tap {
    [self feedFrom:self.source];
    if (!SGRSourceEnabled(self.source)) return;
    if ([self.source.accessibilityIdentifier hasPrefix:SGAlbumQueueButtonPrefix]) SGAlbumQueueMarkSource(self.source);
    if (self.sgr_pinnedPage) claimPinnedMore(self);
    SGRActivate(self.source);
    // The word is watched where Spotify writes it, but a button that rebuilds its content on the state it
    // just took writes the new word into a label the watch has never seen. So a tap, and only a tap, asks
    // the button again a moment later, which also moves the watch onto whatever label it ended up with. The
    // same goes for shuffle's dot and a download's state, which change with no image or word to watch.
    __weak SGRMirrorButton *weakSelf = self;
    for (NSNumber *delay in @[@0.3, @1.0]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            SGRMirrorButton *button = weakSelf;
            if (button.source) [button feedFrom:button.source];
        });
    }
}

@end

#pragma mark - the page's pinned ⋯

// A mirror of the back button, which UIKit draws as a 44pt glass circle at the top of the safe area, 16pt
// in from the leading edge (trees/continuous/1.txt:2554: the navigation bar's own glass at {16, 0} 44x44,
// the bar itself at the safe area's top). ⋯ takes the same size and the same insets on the other side, so
// the two read as one row on every page (issue #57).
static const CGFloat kCornerSide = 16;

// The page whose pinned ⋯ was last tapped, and when: what tells the sheet that opens a moment later which
// page's menu it is. The same trick Shared/Player/SpeedPitchMenu.x plays on the player's more button, but
// from this side of it, since this button is the redesign's own and knows its own page.
//
// Claimed by the tap itself (-sgr_tap), just before it fires Spotify's ⋯, so a sheet Spotify puts up from that
// call finds the claim; a press let go off the button, which fires nothing, claims nothing either.
static __weak UIView *sg_morePage;
static __weak SGRMirrorButton *sg_moreButton;
static NSTimeInterval sg_moreTappedAt;

static void claimPinnedMore(SGRMirrorButton *button) {
    sg_morePage = button.sgr_pinnedPage;
    sg_moreButton = button;
    sg_moreTappedAt = CACurrentMediaTime();
}

UIView *SGRPinnedMoreRecentPage(void) {
    if (!sg_morePage || CACurrentMediaTime() - sg_moreTappedAt > SGRPinnedMoreWindow) return nil;
    return sg_morePage;
}

SGRMirrorButton *SGRPinnedMoreRecentButton(void) {
    if (!sg_moreButton || CACurrentMediaTime() - sg_moreTappedAt > SGRPinnedMoreWindow) return nil;
    return sg_moreButton;
}

void SGRPinnedMoreTaken(void) {
    sg_moreButton = nil;
}

// Over the page's list and its header both, and put back on top whenever Spotify adds to the page.
static void keepOnTop(UIView *page, UIView *button) {
    if (button.superview != page) [page addSubview:button];
    else if (page.subviews.lastObject != button) [page bringSubviewToFront:button];
}

// Level with the back button, at the top of the navigation bar shown over the page, kCornerSide in from the trailing
// edge of the page. Not the window's safe area: on an iPhone the bar starts there (62), but on an iPad Spotify sets
// its pages in a card inset from the window (40) with the bar 10 down inside it, and ⋯ sat 18pt above the back
// button (issue #41). Without a bar shown, the window's safe area. Never the page's own safe area: a page under a
// navigation bar counts the bar into its inset, so the playlist's read 116 where the window's reads 62 and the
// button sat a bar's height below the back button. The inset from the side is taken from
// the page's own bounds and not converted from the window: the swipe back slides the page across the
// window, and a frame converted from the window's x would hold the button still while the page left under
// it, over the screen below, until the page was gone and took it along.
// `along` moves the button that much further in from the trailing edge, for a second button beside ⋯.
//
// Right to left (Arabic, Hebrew) the page mirrors, the back button to the right with it, so ⋯ takes the left corner,
// kCornerSide in from the page's left edge, and download sits on its right. Read from the page's own direction,
// which follows the app's language and any semantic content attribute put on the page or above it.
static BOOL laidOutRightToLeft(UIView *page) {
    return page.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;
}

// The navigation bar shown over `page` in its window, or nil.
static UINavigationBar *shownBarOver(UIView *page) {
    for (UIResponder *r = page.nextResponder; r; r = r.nextResponder) {
        if (![r isKindOfClass:UIViewController.class]) continue;
        UINavigationController *navigation = ((UIViewController *)r).navigationController;
        UINavigationBar *bar = navigation.navigationBar;
        return !navigation.navigationBarHidden && page.window && bar.window == page.window ? bar : nil;
    }
    return nil;
}

static void placeInCorner(UIView *page, UIView *button, CGFloat along) {
    UIWindow *window = page.window;
    UIView *space = window ?: page;
    CGFloat side = SGRGlassCircleSize;
    CGFloat x = laidOutRightToLeft(page) ? kCornerSide + along : page.bounds.size.width - kCornerSide - side - along;
    UINavigationBar *bar = shownBarOver(page);
    CGFloat y = space.safeAreaInsets.top;
    if (bar) y = [page convertPoint:CGPointZero fromView:bar].y;
    else if (window) y = [page convertPoint:CGPointMake(0, y) fromView:nil].y;
    CGRect frame = CGRectMake(x, y, side, side);
    if (!CGRectIsEmpty(frame) && !CGRectEqualToRect(button.frame, frame)) button.frame = frame;
}

SGRMirrorButton *SGRPinnedMore(UIView *page, const void *key, UIView *source) {
    if (!page) return nil;
    SGRMirrorButton *button = objc_getAssociatedObject(page, key);
    if (!button) {
        button = [[SGRMirrorButton alloc] initWithFrame:CGRectZero];
        button.fallbackGlyph = [UIImage systemImageNamed:@"ellipsis"];
        // ⋯ sits in an Encore Tertiary button in Spotify's own row, which draws it gray; in the corner of
        // the page it is the one control there and reads white, like the back button opposite it.
        button.glyphColor = SGRPrimary();
        button.sgr_pinnedPage = page;
        objc_setAssociatedObject(page, key, button, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    BOOL inlineHeader = [button.superview isKindOfClass:SGRHeaderInfo.class];
    if (!inlineHeader) keepOnTop(page, button);
    if (source) [button feedFrom:source];
    if (button.hidden != (source == nil)) button.hidden = source == nil;
    if (!inlineHeader) placeInCorner(page, button, 0);
    return button;
}

// Right under ⋯, which is the page's top subview once it has brought itself to the front, with nothing between
// the two: the capsule download carries is ⋯'s glass as well, ⋯ drawing none of its own, so anything laid between
// them would cover that half of the capsule and leave ⋯ its glyph alone. The field's veil was, for the hold of a
// page opening (up to SGRFieldHoldLimit); SGRField.m -holdPage: now lays it under every pinned button at the top of
// the page, so the pair is drawn whole over the veil from the first frame. Moved only when out of place, as ⋯ is: a
// move lays the page out again, and two buttons each taking the top would trade places on every pass.
static void keepUnderMore(UIView *page, UIView *button) {
    NSArray<UIView *> *subviews = page.subviews;
    UIView *top = subviews.lastObject;
    if (top == button || ![top isKindOfClass:SGRMirrorButton.class]) {
        keepOnTop(page, button);
        return;
    }
    if (subviews.count < 2 || subviews[subviews.count - 2] != button) [page insertSubview:button belowSubview:top];
}

SGRMirrorButton *SGRPinnedDownload(UIView *page, const void *key, UIView *source) {
    if (!page) return nil;
    SGRMirrorButton *button = objc_getAssociatedObject(page, key);
    if (!button) {
        button = [[SGRMirrorButton alloc] initWithFrame:CGRectZero];
        button.fallbackGlyph = [UIImage systemImageNamed:@"arrow.down"];
        button.accessibilityIdentifier = @"Retrine.Album.Download";
        objc_setAssociatedObject(page, key, button, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    BOOL inlineHeader = [button.superview isKindOfClass:SGRHeaderInfo.class];
    if (!inlineHeader) keepUnderMore(page, button);
    if (source) [button feedFrom:source];
    if (button.hidden != (source == nil)) button.hidden = source == nil;
    // Right beside ⋯, the two one capsule as the navigation bar groups its buttons: download carries the glass
    // for both, ⋯ none, and each keeps its own touch, press and glyph. Without download, ⋯ is its circle again.
    SGRMirrorButton *more = nil;
    for (UIView *view in (inlineHeader ? button.superview : page).subviews.reverseObjectEnumerator) {
        if ([view isKindOfClass:SGRMirrorButton.class] && ((SGRMirrorButton *)view).sgr_pinnedPage) {
            more = (SGRMirrorButton *)view;
            break;
        }
    }
    BOOL paired = more && !more.hidden && !button.hidden;
    button.sgr_glassReach = paired ? SGRGlassCircleSize : 0;
    button.sgr_glassReachesLeft = laidOutRightToLeft(page);
    more.sgr_glassReach = paired ? -1 : 0;
    if (!inlineHeader) placeInCorner(page, button, SGRGlassCircleSize);
    return button;
}
