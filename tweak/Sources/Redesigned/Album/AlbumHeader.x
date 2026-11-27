// Album redesign: the header the Music app gives an album (iOS 26.4), the same one the playlist redesign
// gives a playlist. The cover runs full bleed across the top of the page and dissolves into the page's
// color; the title, the artist and the kind and date are centered on the bottom of that dissolve; and under
// them one row -- shuffle, a white Play capsule, and add.
//
// Tree (trees/clean/album/01.txt:39-152). The header is one element of the page's scrolling stack,
// id=CreativeWorkPlatform.Components.UI.CreativeWorkHeader, a plain UIView whose height the element framework
// measures from what it holds, down a chain of four stack views:
//
//     UIView {0, 78}                     the top inset, the status bar and the navigation bar's room
//       UIStackView                      the two groups
//         UIView 402x321                 the top group: the cover square, a spacer, and the title block --
//                                        TitleRow, and ParentRow, the artist with a facepile
//         UIView {0, 329} 402x71         the bottom group: Components.UI.MetadataRow (the kind and the date,
//                                        cells of a collection view) and the action row
//
// What the header shows is the redesign's own (the Kit's SGRHeaderInfo), not Spotify's rearranged: moving
// Spotify's stacks meant answering every pass of theirs, and the element framework measured the title for
// its own font. So Spotify's whole column is concealed and the Kit's view is drawn over the header in its
// place, reading its text off Spotify's concealed labels -- so it is in the app's language and follows
// whatever Spotify shows -- and drawing and firing Spotify's own controls. The header keeps its height and its
// place in the stack; Spotify's fade of it as the page scrolls is held off, the info clipped under the bar instead.
//
// Play and shuffle are not in the header. The album page floats them over the page, pinned to the top
// trailing corner outside the scroll (01.txt:1431, :1436): they are concealed where they are, and the row
// draws them and fires them all the same.
#import <AVFoundation/AVFoundation.h>
#import <CoreImage/CoreImage.h>
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Redesigned/Kit/SGRMotionBudget.h"
#import "Redesigned/Kit/SGRHeaderClip.h"
#import "Redesigned/Player/Player.h"
#import "Redesigned/Kit/SGRCoverRead.h"
#import "Redesigned/Kit/SGRCoverViewer.h"
#import "Redesigned/Kit/SGRHeroVeil.h"
#import "Shared/AnimatedArtwork/AnimatedArtwork.h"
#import "Shared/AnimatedArtwork/SGMotionClip.h"
#import "Album.h"
#import "AlbumNotes.h"
#import "SGRCoverBeside.h"

@interface SGAlbumQueuePage : NSObject
+ (NSString *)albumURI:(id)controller;
@end

// A header whose text begins nearer the top than this is one mid load, not one to measure the hero from;
// and an artwork view narrower than this is a placeholder glyph rather than the cover.
static const CGFloat kMinHero = 120, kMinCover = 80;
// The square cover's corners with Full bleed covers off: Spotify's own (its ImageViewHolder, r=4), so the album's
// square is the playlist's, which is Spotify's square left in place.
static const CGFloat kSquareRadius = 4;
// The room between the pinned chrome's bottom and the top of a square drawn smaller to clear it, in points.
static const CGFloat kChromeGapPoints = 8;

// The picture-aware cover (SGRKeyAlbumAdaptiveCover, with the Full screen cover). The cover is read (Kit/SGRCoverRead.h)
// and stays sharp, itself, down to kSharpRise above the hero's bottom unless the read moves that; from there down a
// picture drawn off the main thread lies over it, blurred up to the read's radius over kBlurRamp on the quintic ramp
// and mixed in OKLab into the page's color, all of it by the hero's bottom. Under the cover its bottom edge is reflected, at
// least kFootMin past the hero's bottom, so the blur there takes in picture rather than an edge. The title's area,
// SGRHeaderInfoTitleRise up from the bottom, is kept to kTitleL of lightness (kTitleLContrast with Increase Contrast)
// over kTitleShare of it by the dissolve, drawn as a scrim fading in over kScrimLead above it. Under an animated cover
// the dissolve stays, beginning where the clip's first frame stops being sharp, between kStillFadeMin and
// kStillFadeMax of the hero's height.
// 80pt left a 19/255 row step at a scanned sleeve's pale border, only 16pt below the sharp end.
// Reach the same maximum in 40pt so that border is softened before it crosses the title.
static const CGFloat kSharpRise = 30, kBlurRamp = 40, kFootMin = 24, kScrimLead = 24;
static const CGFloat kTitleL = 0.58, kTitleLContrast = 0.50, kTitleShare = 0.9, kTitleBlendMargin = 0.005;
static const size_t kTitleStride = 2;   // pixels and rows of the title's area measured, in pixels
static const CGFloat kStillFadeMin = 0.4384, kStillFadeMax = 0.70;
// Only the transition band is capped at 2x; the sharp UIImageView above it keeps the display's native scale.
// At 3x a cold simulator render spent 342ms in CI blur alone. 2x bounds that pixel work to four ninths.
// Over the cover (0) and under an animated cover (0.5).
static const CGFloat kRenderMaxScale = 2, kRenderZ = 0.25;
// How long a render waits, once, for the page's color to arrive before it draws into the color there is.
static const NSTimeInterval kColorWait = 0.6;
// Rendered pictures kept, by bytes: three heroes across a 3x phone.
static const NSUInteger kRenderCacheBytes = 20 * 1024 * 1024;
static const NSUInteger kLoggedRenders = 6;

static BOOL adaptiveCoverOn(void) {
    static BOOL on;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ on = SGFlag(SGRKeyAlbumAdaptiveCover, NO); });
    return on;
}

static char kHeaderKey, kCoverKey, kTitleKey, kParentKey, kMetaKey, kAddKey, kDownloadKey, kPlayKey, kShuffleKey;
static char kHeroKey, kHeroHeightKey, kHeaderHeightKey, kInfoKey, kHeaderWatchedKey, kRetryKey;
static char kExploreKey, kRowWatchedKey, kMoreKey, kPinnedMoreKey, kPinnedDownloadKey;

#pragma mark - moving Spotify's views

// The outermost view that still wraps the control exactly: the element view Spotify's layout places, so
// concealing it leaves the control itself alone to be read and fired.
static UIView *wrapperFor(UIView *control, UIView *stop) {
    UIView *wrapper = control;
    for (UIView *v = control.superview; v && v != stop; v = v.superview) {
        if (fabs(v.bounds.size.width - control.bounds.size.width) > 4) break;
        if (fabs(v.bounds.size.height - control.bounds.size.height) > 4) break;
        wrapper = v;
    }
    return wrapper;
}

// One of the two controls Spotify floats over the page. They are direct children of the page and 48pt
// across, so only the small children are searched: the wash, the tab and the navigation bar are the width
// of the page, and walking into the tab would be walking the whole list on every pass that missed.
static UIView *floatingIn(UIView *page, NSString *identifier, const void *cacheKey) {
    for (UIView *sub in page.subviews) {
        if (sub.bounds.size.width > 120) continue;
        UIView *found = SGRFindByIdentifier(sub, identifier, cacheKey);
        if (found) return found;
    }
    return nil;
}

static void setFrame(UIView *view, CGRect frame) {
    if (view && !CGRectIsEmpty(frame) && !CGRectEqualToRect(view.frame, frame)) view.frame = frame;
}

// The stack Spotify arranges the header's buttons in: the first one above `button`.
static UIView *rowOf(UIView *button, UIView *header) {
    for (UIView *v = button.superview; v && v != header; v = v.superview) {
        if ([v isKindOfClass:UIStackView.class]) return v;
    }
    return nil;
}

// Installs `laidOut` on the view's own pass once, under `key`.
static void watch(UIView *view, const void *key, void (^laidOut)(UIView *view)) {
    if (!view || objc_getAssociatedObject(view, key)) return;
    objc_setAssociatedObject(view, key, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    SGRObserveLayout(view, laidOut);
}

#pragma mark - the picture-aware cover, drawn

// What a picture-aware cover is drawn from, every length in the hero's points.
typedef struct {
    CGSize size;            // the hero
    CGRect place;           // where the cover is laid out in it
    CGFloat scale;
    CGFloat sharpEnd;       // where it stops being sharp
    CGFloat blurRadius;     // the most the blur below that reaches
    CGFloat mixStart;       // where the mix into the page's color begins; it ends at the bottom
    SGRLab page;
    CGFloat titleL;         // the most the title's area may be
} SGRCoverDrawing;

// The drawn picture, where in the hero it goes from down to the bottom, and the scrim's alpha the title's area needs.
@interface SGRCoverRender : NSObject
@property (nonatomic) UIImage *image;
// A pointer in the cache key is only an index. Zeroing weak identity rejects recycled source addresses.
@property (nonatomic, weak) UIImage *source;
@property (nonatomic) CGFloat top;
@property (nonatomic) CGFloat scrimAlpha;
@property (nonatomic) CGFloat dissolveHeight;
@end

@implementation SGRCoverRender
@end

static dispatch_queue_t renderQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        queue = dispatch_queue_create("spotifyglass.redesign.album.cover", dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_UTILITY, 0));
    });
    return queue;
}

static NSCache<NSString *, SGRCoverRender *> *renderCache(void) {
    static NSCache *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        cache = [NSCache new];
        cache.totalCostLimit = kRenderCacheBytes;
    });
    return cache;
}

static CGColorSpaceRef renderSpace(void) {
    static CGColorSpaceRef space;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB); });
    return space;
}

// Render queue only.
static CIContext *renderContext(void) {
    static CIContext *context;
    if (!context) context = [CIContext contextWithOptions:@{kCIContextCacheIntermediates: @NO}];
    return context;
}

static CGContextRef newRenderBitmap(size_t width, size_t height) {
    return CGBitmapContextCreate(NULL, width, height, 8, width * 4, renderSpace(), (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
}

static CGRect aspectFill(CGSize image, CGRect into) {
    CGFloat scale = MAX(into.size.width / image.width, into.size.height / image.height);
    CGSize drawn = CGSizeMake(image.width * scale, image.height * scale);
    return CGRectMake(CGRectGetMidX(into) - drawn.width / 2, CGRectGetMidY(into) - drawn.height / 2, drawn.width, drawn.height);
}

// The cover as the hero lays it out, over the page's color, with its bottom edge reflected down to `height` points.
static CGContextRef newSharpCanvas(UIImage *cover, const SGRCoverDrawing *d, CGFloat height, size_t pixelsWide, size_t pixelsHigh) {
    CGContextRef context = newRenderBitmap(pixelsWide, pixelsHigh);
    if (!context) return NULL;
    CGContextTranslateCTM(context, 0, pixelsHigh);
    CGContextScaleCTM(context, d->scale, -d->scale);
    CGFloat r, g, b;
    SGRLabToRGB(d->page, &r, &g, &b);
    CGContextSetRGBFillColor(context, r, g, b, 1);
    CGContextFillRect(context, CGRectMake(0, 0, d->size.width, height));
    UIGraphicsPushContext(context);
    CGRect drawn = aspectFill(cover.size, d->place);
    CGContextSaveGState(context);
    CGContextClipToRect(context, d->place);
    [cover drawInRect:drawn];
    CGContextRestoreGState(context);
    CGFloat bottom = CGRectGetMaxY(d->place);
    if (bottom < height) {
        CGContextSaveGState(context);
        CGContextClipToRect(context, CGRectMake(0, bottom, d->size.width, height - bottom));
        CGContextTranslateCTM(context, 0, 2 * bottom);
        CGContextScaleCTM(context, 1, -1);
        CGContextClipToRect(context, d->place);
        [cover drawInRect:drawn];
        CGContextRestoreGState(context);
    }
    UIGraphicsPopContext();
    return context;
}

// Every kTitleStride-th pixel of every kTitleStride-th row of `context` from `from` up to `to`, as RGB.
static void appendSamples(NSMutableData *samples, CGContextRef context, size_t from, size_t to) {
    const uint8_t *pixels = CGBitmapContextGetData(context);
    size_t rowBytes = CGBitmapContextGetBytesPerRow(context), wide = CGBitmapContextGetWidth(context);
    for (size_t row = from; row < to; row += kTitleStride) {
        for (size_t x = 0; x < wide; x += kTitleStride) [samples appendBytes:pixels + row * rowBytes + x * 4 length:3];
    }
}

// The blur's radius, in points, at a row of the canvas: none above the sharp end, then up to the most over kBlurRamp.
static CGFloat blurAt(const SGRCoverDrawing *d, size_t row) {
    CGFloat y = (row + 0.5) / d->scale;
    return d->blurRadius * SGRHeroVeilRamp((y - d->sharpEnd) / kBlurRamp);
}

// Interpolate Gaussian-blurred pictures at neighbouring radii, never the sharp source (except below half a point).
// A fractional variable-blur mask retains sharp edges; an all-white mask pays for a variable blur without using
// its mask. Radius bands keep Gaussian work bounded.
static const CGFloat kFinestBlur = 0.5;
static CGFloat blurOctave(const SGRCoverDrawing *d, CGFloat radius) {
    CGFloat octave = d->blurRadius;
    while (octave / 2 >= radius && octave / 2 >= kFinestBlur) octave /= 2;
    return octave;
}

static CIImage *blurredCover(CIImage *source, CGFloat radiusPixels) {
    if (radiusPixels == 0) return source;
    return [source imageByApplyingGaussianBlurWithSigma:radiusPixels];
}

// The rows from `start` down mixed into the page's color, all of it by the last row.
static void mixRows(CGContextRef context, size_t start, size_t pixelsWide, size_t pixelsHigh, SGRLab page) {
    uint8_t *pixels = CGBitmapContextGetData(context);
    size_t rowBytes = CGBitmapContextGetBytesPerRow(context), span = pixelsHigh - start;
    for (size_t row = start; row < pixelsHigh; row++) {
        CGFloat weight = SGRHeroVeilRamp((CGFloat)(row + 1 - start) / span);
        if (weight <= 0) continue;
        uint8_t *pixel = pixels + row * rowBytes;
        for (size_t x = 0; x < pixelsWide; x++, pixel += 4) {
            SGRLab lab = SGRLabFromRGB8(pixel);
            lab = (SGRLab){lab.L + (page.L - lab.L) * weight, lab.a + (page.a - lab.a) * weight, lab.b + (page.b - lab.b) * weight};
            SGRLabToRGB8(lab, pixel);
        }
    }
}

// The alpha of the page's color over the title's area, as Core Animation blends it, that holds kTitleShare of its
// pixels to the cap: 0 when they already are.
static CGFloat scrimAlpha(NSData *samples, const SGRCoverDrawing *d) {
    const uint8_t *sample = samples.bytes;
    size_t count = samples.length / 3, allowed = (size_t)floor(count * (1 - kTitleShare));
    CGFloat r, g, b, cap = d->titleL - kTitleBlendMargin;
    SGRLabToRGB(d->page, &r, &g, &b);
    // How many are over the cap, by a margin for the 8-bit blend, with the page's color over them at `alpha`.
    size_t (^over)(CGFloat) = ^size_t(CGFloat alpha) {
        size_t lighter = 0;
        for (size_t i = 0; i < count; i++) {
            const uint8_t *s = sample + i * 3;
            lighter += SGRLabFromRGB(s[0] / 255.0 * (1 - alpha) + r * alpha, s[1] / 255.0 * (1 - alpha) + g * alpha,
                                     s[2] / 255.0 * (1 - alpha) + b * alpha).L > cap;
        }
        return lighter;
    };
    if (!count || over(0) <= allowed) return 0;
    CGFloat low = 0, high = 1;
    for (int i = 0; i < 10; i++) {
        CGFloat alpha = (low + high) / 2;
        if (over(alpha) > allowed) low = alpha;
        else high = alpha;
    }
    return ceil(high * 100) / 100;
}

// The picture-aware cover from the sharp end down to the hero's bottom, where it is drawn over the cover: blurred
// below the sharp end, mixed into the page's color from the mix's start to the bottom. Above it the cover itself
// shows, the very pixels the drawing starts from. Render queue.
static SGRCoverRender *renderCover(UIImage *cover, SGRCoverDrawing d) {
    CFTimeInterval began = CACurrentMediaTime();
    size_t wide = (size_t)lround(d.size.width * d.scale), high = (size_t)lround(d.size.height * d.scale);
    CGFloat canvasHeight = d.size.height + kFootMin;
    size_t canvasHigh = (size_t)lround(canvasHeight * d.scale);
    size_t sharpRows = (size_t)MIN(high - 1, MAX(0, lround(d.sharpEnd * d.scale))), rows = high - sharpRows;
    CGContextRef canvas = newSharpCanvas(cover, &d, canvasHeight, wide, canvasHigh);
    CGImageRef canvasImage = canvas ? CGBitmapContextCreateImage(canvas) : NULL;
    CGContextRef context = canvasImage ? newRenderBitmap(wide, rows) : NULL;
    if (!context) {
        CGImageRelease(canvasImage);
        CGContextRelease(canvas);
        return nil;
    }
    // The canvas's rows from the sharp end as they are, its row sharpRows on the drawing's first.
    CGContextDrawImage(context, CGRectMake(0, (CGFloat)rows + sharpRows - canvasHigh, wide, canvasHigh), canvasImage);
    CFTimeInterval canvasDone = CACurrentMediaTime();
    CIImage *source = d.blurRadius > 0 ? [[CIImage imageWithCGImage:canvasImage] imageByClampingToExtent] : nil;
    for (size_t row = sharpRows; source && row < high;) {
        CGFloat radius = blurAt(&d, row);
        if (radius <= 0) {
            row++;
            continue;
        }
        // The band of rows in this octave, the radius only growing down the canvas.
        CGFloat octave = blurOctave(&d, radius);
        size_t end = row + 1;
        while (end < high && blurOctave(&d, blurAt(&d, end)) == octave) end++;
        // Core Image counts up from the bottom of the canvas, the drawing from the bottom of the hero.
        CGRect band = CGRectMake(0, canvasHigh - end, wide, end - row);
        CGFloat lower = octave / 2 < kFinestBlur ? 0 : octave / 2;
        CGContextRef bands[2] = {newRenderBitmap(wide, end - row), newRenderBitmap(wide, end - row)};
        BOOL complete = bands[0] && bands[1];
        for (int i = 0; complete && i < 2; i++) {
            CIImage *blur = blurredCover(source, (i ? octave : lower) * d.scale);
            CGImageRef image = [renderContext() createCGImage:blur fromRect:band format:kCIFormatRGBA8 colorSpace:renderSpace()];
            complete = image != NULL;
            if (image) CGContextDrawImage(bands[i], CGRectMake(0, 0, wide, end - row), image);
            CGImageRelease(image);
        }
        if (complete) {
            uint8_t *target = CGBitmapContextGetData(context);
            const uint8_t *a = CGBitmapContextGetData(bands[0]), *b = CGBitmapContextGetData(bands[1]);
            for (size_t y = row; y < end; y++) {
                CGFloat t = (blurAt(&d, y) - lower) / (octave - lower);
                size_t offset = (y - row) * wide * 4, dest = (y - sharpRows) * wide * 4;
                for (size_t x = 0; x < wide * 4; x++)
                    target[dest + x] = (uint8_t)lround(a[offset + x] + (b[offset + x] - a[offset + x]) * t);
            }
        }
        CGContextRelease(bands[0]);
        CGContextRelease(bands[1]);
        if (!complete) {
            CGImageRelease(canvasImage);
            CGContextRelease(canvas);
            CGContextRelease(context);
            return nil;
        }
        row = end;
    }
    CGImageRelease(canvasImage);
    CFTimeInterval blurDone = CACurrentMediaTime();
    size_t mixRow = (size_t)MIN(high - 1, MAX(sharpRows, lround(d.mixStart * d.scale)));
    mixRows(context, mixRow - sharpRows, wide, rows, d.page);
    CFTimeInterval mixDone = CACurrentMediaTime();
    // The title's area as it shows: the cover above the drawing, the drawing below.
    size_t titleRow = (size_t)MIN(high - 1, MAX(0, lround((d.size.height - SGRHeaderInfoTitleRise) * d.scale)));
    NSMutableData *title = [NSMutableData data];
    if (titleRow < sharpRows) appendSamples(title, canvas, titleRow, sharpRows);
    appendSamples(title, context, titleRow > sharpRows ? titleRow - sharpRows : 0, rows);
    CGContextRelease(canvas);
    SGRCoverRender *render = [SGRCoverRender new];
    render.source = cover;
    render.scrimAlpha = scrimAlpha(title, &d);
    render.top = sharpRows / d.scale;
    render.dissolveHeight = d.size.height - d.mixStart;
    CGImageRef image = CGBitmapContextCreateImage(context);
    CGContextRelease(context);
    render.image = [UIImage imageWithCGImage:image scale:d.scale orientation:UIImageOrientationUp];
    CGImageRelease(image);
    static NSUInteger profiled;
    if (profiled++ < kLoggedRenders)
        SGLog(@"redesign album: cover stages canvas %.1f, blur %.1f, mix %.1f, title %.1f ms; main thread %d; sharp %.1f, mix %.1f pt",
              (canvasDone - began) * 1000, (blurDone - canvasDone) * 1000, (mixDone - blurDone) * 1000,
              (CACurrentMediaTime() - mixDone) * 1000, NSThread.isMainThread, d.sharpEnd, d.mixStart);
    return render;
}

#pragma mark - the cover, full bleed

// The picture and rendered transition share a rest-sized surface, zoomed by SGRStretchHero on a pull.
// Only that surface dissolves; the title contrast scrim and square's shadow stay outside its mask.
//
// A tap on the picture, above where the title starts, opens the cover full screen (Kit/SGRCoverViewer.h): the still
// cover, even while the animated one plays. The Kit's view over the header answers only its buttons and the
// artist line and Spotify's column takes no touches, so the picture is what a tap anywhere else lands on; a
// drag still scrolls the page, whose pan sees every touch under it.
@interface SGRAlbumHero : SGRStretchHero <UIGestureRecognizerDelegate>
@property (nonatomic, readonly) UIImageView *picture;
@property (nonatomic, copy) UIColor *fieldColor;
// Where Spotify lays its cover square out, in the hero's coordinates. With Full bleed covers off the picture is
// drawn there instead (smaller where the pinned chrome covers it, -sgr_card), on the field with neither gradient,
// until an animated cover fills the hero over it.
@property (nonatomic) CGRect square;
// The header's width when the square was taken.
@property (nonatomic) CGFloat squareWidth;
// The page's pinned ⋯ and download (the glass over the top trailing corner) in the hero's coordinates with the page at
// rest, CGRectNull while neither is pinned to the page. Where it covers the square, the square is drawn smaller under
// it (-sgr_card).
@property (nonatomic) CGRect chrome;
@property (nonatomic) CGRect besideFrame;
// The cover in Spotify's artwork view, and every cover it puts there afterward: the hero keeps itself
// right, rather than being handed a picture on each of the header's passes and staying empty between them.
- (void)followCover:(UIImageView *)source;
// The artwork view in Spotify's cover element followed, or, while none in it is at the lookup's size, waited for.
- (void)followCoverIn:(UIView *)element;
// Apple Music's animated cover over the picture, where the album has one. The same album again is a no-op.
- (void)playMotionForArtist:(NSString *)artist album:(NSString *)album;
// The square's shadow, copied off whichever layer under Spotify's concealed cover casts one (its ShadowContainer),
// so the album's square has the shadow the playlist's -- Spotify's own square -- does. Once found, a no-op.
- (void)takeShadowFrom:(UIView *)cover;
// The scroll veil over the picture (Kit/SGRHeroVeil.h); nil while it is off.
@property (nonatomic, readonly) SGRHeroVeil *veil;
@end

@implementation SGRAlbumHero {
    CAGradientLayer *_dissolve;
    CALayer *_shadow;   // under the square, which clips and so cannot cast its own
    __weak UIImageView *_cover;
    __weak UIView *_awaited;   // the cover element whose image views wait for the artwork (-followCoverIn:)
    UIView *_extension;   // iOS 26's UIBackgroundExtensionView around the picture, nil before it
    NSString *_motionAlbum;
    __weak UIView *_motionPage;
    NSString *_motionRelease;
    NSUInteger _motionGeneration;
    CALayer *_motion;
    SGRHeaderClip *_clip;
    SGRHeaderPage *_clipPage;
    NSHashTable *_motionScrolls;
    BOOL _resigning, _background;
    // The picture-aware cover, on with the Full screen cover only; none of the below is used otherwise.
    BOOL _adaptive;
    SGRCoverReading *_coverReading, *_stillReading;   // the cover's, and its animated cover's first frame's
    NSURL *_stillFile;                                // the animated cover _stillReading is (being) read from
    CALayer *_render;                                 // the drawn picture over the cover, nil until one is drawn
    CGFloat _renderTop;                               // where it begins, down to the hero's bottom
    CGFloat _renderDissolveHeight;
    NSString *_renderKey;                             // what _render shows or is being drawn with
    NSUInteger _renderGeneration;
    CGFloat _scrimAlpha;                              // the dissolve's over the title's area, with _render shown
    BOOL _colorWaitBegun, _colorWaitOver;
}

static char kScrollContext;

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    _chrome = CGRectNull;
    self.clipsToBounds = YES;
    self.accessibilityTraits = UIAccessibilityTraitButton | UIAccessibilityTraitImage;
    self.accessibilityLabel = SGL(@"settings.album.cover_viewer.cover", @"Album cover");
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(sgr_openCover)];
    tap.delegate = self;
    [self addGestureRecognizer:tap];

    _picture = [[UIImageView alloc] initWithFrame:self.bounds];
    _picture.contentMode = UIViewContentModeScaleAspectFill;
    _picture.clipsToBounds = YES;
    // The cover is square and the hero runs a little taller, so a fill cut its sides: a title set edge to
    // edge on the cover lost its ends. On iOS 26 the cover stays whole at the top and the system carries its
    // bottom edge down the rest, as the Music app's album page does; before, it fills as it always did.
    Class extension = NSClassFromString(@"UIBackgroundExtensionView");
    if (extension) {
        _extension = [[extension alloc] initWithFrame:self.bounds];
        [_extension setValue:@NO forKey:@"automaticallyPlacesContentView"];
        [_extension setValue:_picture forKey:@"contentView"];
        [self.content addSubview:_extension];
    } else {
        _picture.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self.content addSubview:_picture];
    }

    // At the bottom, under the picture's layer.
    _shadow = [CALayer layer];
    _shadow.hidden = YES;
    [self.layer insertSublayer:_shadow atIndex:0];

    _dissolve = [CAGradientLayer layer];
    _dissolve.zPosition = 2;
    _dissolve.hidden = YES;
    [self.layer addSublayer:_dissolve];
    _adaptive = adaptiveCoverOn() && SGRPageFullCover(SGRKeyAlbumFullCover);
    if (SGRHeroScrollVeilOn()) {
        _veil = [[SGRHeroVeil alloc] initWithHero:self];
        _veil.stretchesItself = YES;
        [self sgr_fitVeil];
    }
    self.fieldColor = SGRNeutralField();
    // The color is read off the main thread, so it can land after the last layout pass of the page.
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    [center addObserver:self selector:@selector(sgr_updateMotion) name:SGRPlayerVisibilityDidChangeNotification object:nil];
    [center addObserver:self selector:@selector(sgr_fieldColorDidChange) name:SGRFieldColorDidChangeNotification object:nil];
    __weak SGRAlbumHero *weakHero = self;
    _clipPage = [[SGRHeaderPage alloc] initWithRefresh:^{ [weakHero sgr_updateMotion]; }];
    [center addObserver:self selector:@selector(sgr_updateMotion) name:UIApplicationDidReceiveMemoryWarningNotification object:nil];
    for (NSNotificationName name in @[UIApplicationDidBecomeActiveNotification, UIApplicationWillResignActiveNotification,
                                      UIApplicationDidEnterBackgroundNotification])
        [center addObserver:self selector:@selector(sgr_appState:) name:name object:nil];
    for (NSNotificationName name in @[NSProcessInfoPowerStateDidChangeNotification, NSProcessInfoThermalStateDidChangeNotification,
                                      UIAccessibilityReduceMotionStatusDidChangeNotification,
                                      UIAccessibilityVideoAutoplayStatusDidChangeNotification]) {
        [center addObserver:self selector:@selector(sgr_updateMotionSoon) name:name object:nil];
    }
    return self;
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
    [self sgr_dropMotion];
}

- (void)sgr_fieldColorDidChange {
    if (self.superview) self.fieldColor = SGRAlbumFieldColor(self);
}

// A square stays where the page puts it, as the playlist's does (Spotify places that one), with its picture alone
// blurred and dimmed; a picture across the hero, full screen or a clip over the square, is the hero's, moved and all.
- (void)sgr_fitVeil {
    BOOL square = !SGRPageFullCover(SGRKeyAlbumFullCover) && _motion.opacity != 1;
    CALayer *picture = (_extension ?: _picture).layer;
    NSArray<CALayer *> *art = _motion ? @[picture, _motion] : @[picture];
    if (_render) art = [art arrayByAddingObject:_render];
    _veil.art = square ? @[] : art;
    _veil.surface = square ? _picture : nil;
}

// Where the cover is laid out full screen: on iOS 26 the top square of the hero, the system carrying its bottom edge
// down the rest; before, filling the whole hero.
- (CGRect)sgr_fullPicture {
    CGRect bounds = self.restBounds;
    return _extension ? CGRectMake(0, 0, bounds.size.width, MIN(bounds.size.width, bounds.size.height)) : bounds;
}

- (CGRect)restBounds {
    return CGRectIsEmpty(_besideFrame) ? [super restBounds] : (CGRect){CGPointZero, _besideFrame.size};
}

- (void)setBesideFrame:(CGRect)frame {
    if (CGRectEqualToRect(_besideFrame, frame)) return;
    _besideFrame = frame;
    [self sgr_place];
    [self setNeedsLayout];
}

- (void)sgr_place {
    if (CGRectIsEmpty(_besideFrame)) [super sgr_place];
    else if (!CGRectEqualToRect(self.frame, _besideFrame)) self.frame = _besideFrame;
}

// The part of the picture over no text: the title and the artist start SGRHeaderInfoTitleRise above its bottom.
- (CGRect)sgr_coverArea {
    if (!CGRectIsEmpty(_besideFrame)) return self.bounds;
    return CGRectMake(0, 0, self.bounds.size.width, MAX(0, self.bounds.size.height - SGRHeaderInfoTitleRise));
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gesture shouldReceiveTouch:(UITouch *)touch {
    return _picture.image && CGRectContainsPoint([self sgr_coverArea], [touch locationInView:self]);
}

- (void)sgr_openCover {
    SGRShowCover(_picture.image, SGL(@"settings.album.cover_viewer.cover", @"Album cover"));
}

- (BOOL)isAccessibilityElement {
    return _picture.image != nil;
}

- (CGRect)accessibilityFrame {
    return UIAccessibilityConvertFrameToScreenCoordinates([self sgr_coverArea], self);
}

- (BOOL)accessibilityActivate {
    [self sgr_openCover];
    return YES;
}

- (void)setFieldColor:(UIColor *)color {
    if (!color || [_fieldColor isEqual:color]) return;
    _fieldColor = [color copy];
    if (_adaptive) {
        [self sgr_fitDissolve];
        _veil.color = color;
        [self sgr_render];
        return;
    }
    _veil.color = color;
}

- (void)setSquare:(CGRect)square {
    if (CGRectEqualToRect(_square, square)) return;
    _square = square;
    [self setNeedsLayout];
}

- (void)setChrome:(CGRect)chrome {
    if (CGRectEqualToRect(_chrome, chrome)) return;
    _chrome = chrome;
    [self setNeedsLayout];
}

// The square as drawn, and everything that follows it (its shadow, the veil on its picture): Spotify's square, or, where
// the pinned chrome covers it, the square under the chrome on the same vertical axis, its bottom edge where Spotify's
// is and its top kChromeGapPoints under the chrome's bottom.
- (CGRect)sgr_card {
    if (CGRectIsEmpty(CGRectIntersection(_square, _chrome))) return _square;
    CGFloat top = CGRectGetMaxY(_chrome) + kChromeGapPoints, side = CGRectGetMaxY(_square) - top;
    return CGRectMake(CGRectGetMidX(_square) - side / 2, top, side, side);
}

- (void)layoutSubviews {
    BOOL beside = !CGRectIsEmpty(_besideFrame);
    BOOL bleeds = !beside && (SGRPageFullCover(SGRKeyAlbumFullCover) || _motion.opacity == 1);
    self.stretchesContent = bleeds;
    self.dissolves = bleeds;
    [super layoutSubviews];
    CGRect bounds = self.restBounds, card = [self sgr_card];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    [_veil artWillLayOut];
    if (beside || SGRPageFullCover(SGRKeyAlbumFullCover)) {
        if (beside) {
            self.content.transform = CGAffineTransformIdentity;
            self.content.frame = bounds;
        }
        if (_extension) _extension.frame = bounds;
        _picture.frame = [self sgr_fullPicture];
    } else {
        // Stays square under an animated cover too: the clip covers the whole hero, so nothing moves under its fade.
        UIView *holder = _extension ?: _picture;
        holder.frame = card;
        holder.layer.cornerRadius = kSquareRadius;
        holder.layer.cornerCurve = kCACornerCurveContinuous;
        holder.clipsToBounds = YES;
        if (_extension) _picture.frame = _extension.bounds;
        _shadow.hidden = bleeds;
    }
    self.scrim.hidden = !bleeds;
    // A path, so the shadow is drawn from it rather than from an offscreen pass over the layer every frame.
    if (!CGSizeEqualToSize(_shadow.bounds.size, card.size))
        _shadow.shadowPath = [UIBezierPath bezierPathWithRoundedRect:(CGRect){CGPointZero, card.size} cornerRadius:kSquareRadius].CGPath;
    _shadow.frame = CGRectOffset(card, 0, self.stretch);
    [_clip setFrame:bounds];
    [self sgr_updateMotion];
    if (_adaptive) {
        [self sgr_placeRender];
        [self sgr_fitDissolve];
    }
    if (beside) {
        self.content.layer.mask = nil;
        _shadow.hidden = YES;
        _render.hidden = YES;
    } else {
        _render.hidden = NO;
    }
    [self sgr_fitVeil];
    [_veil artDidLayOut];
    [CATransaction commit];
    // A new size draws the picture again; the same one is a no-op.
    if (_adaptive) [self sgr_render];
}

#pragma mark - the picture-aware cover

// The reading the page goes by: the animated cover's first frame's while the clip shows, else the cover's.
- (SGRCoverReading *)sgr_reading {
    return _motion.opacity == 1 && _stillReading ? _stillReading : _coverReading;
}

// The reading's color to the page's field (nil gives it back the cover's main color), which hands it back to the hero
// through -setFieldColor:, and the picture drawn for it.
- (void)sgr_showReading {
    SGRAlbumSetCoverColor(self, [self sgr_reading].pageColor);
    [self sgr_render];
    [self sgr_fitDissolve];
}

- (void)sgr_readCover:(UIImage *)image {
    _coverReading = nil;
    [self sgr_showReading];
    __weak SGRAlbumHero *weakSelf = self;
    SGRCoverRead(image, ^(SGRCoverReading *reading) {
        SGRAlbumHero *hero = weakSelf;
        // Read off a cover the hero no longer shows: another album's, or a copy of this one replaced since.
        if (!hero || hero->_picture.image != image) return;
        hero->_coverReading = reading;
        [hero sgr_showReading];
    });
}

// The animated cover's first frame, read for the page's color and the dissolve while the clip shows.
- (void)sgr_readStill:(NSURL *)file {
    _stillFile = file;
    _stillReading = nil;
    NSUInteger generation = _motionGeneration;
    __weak SGRAlbumHero *weakSelf = self;
    SGMotionPoster(file, ^(UIImage *poster) {
        SGRAlbumHero *hero = weakSelf;
        if (!hero || hero->_motionGeneration != generation || hero->_stillFile != file) return;
        SGRCoverRead(poster, ^(SGRCoverReading *reading) {
            SGRAlbumHero *again = weakSelf;
            // Album ownership also changes on A -> B -> A, even if the clip URL is the same object again.
            if (!again || again->_motionGeneration != generation || again->_stillFile != file) return;
            again->_stillReading = reading;
            [again sgr_showReading];
        });
    });
}

// By bounds and position, which a transform the veil gives it leaves alone.
- (void)sgr_placeRender {
    CGRect bounds = self.restBounds;
    CGFloat height = MAX(0, bounds.size.height - _renderTop);
    _render.bounds = CGRectMake(0, 0, bounds.size.width, height);
    _render.position = CGPointMake(CGRectGetMidX(bounds), _renderTop + height / 2);
}

// With a drawn picture shown, the dissolve is a scrim over the title's area where the picture is too light there,
// and nothing where it is not; under an animated cover, or before a picture is drawn, it is the dissolve as it always
// was, under a clip beginning where its first frame stops being sharp.
- (void)sgr_fitDissolve {
    if (!_adaptive) return;
    if (!CGRectIsEmpty(_besideFrame)) {
        _dissolve.hidden = YES;
        return;
    }
    CGRect bounds = self.restBounds;
    CGFloat width = bounds.size.width, height = bounds.size.height;
    UIColor *color = _fieldColor;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    if (_render && _motion.opacity != 1) {
        self.dissolveHeight = _renderDissolveHeight;
        CGFloat top = MAX(0, height - SGRHeaderInfoTitleRise - kScrimLead);
        _dissolve.frame = CGRectMake(0, top + self.stretch, width, height - top);
        _dissolve.colors = @[(id)[color colorWithAlphaComponent:0].CGColor, (id)[color colorWithAlphaComponent:_scrimAlpha].CGColor,
                             (id)[color colorWithAlphaComponent:_scrimAlpha].CGColor];
        _dissolve.locations = @[@0, @(MIN(1, kScrimLead / MAX(1, height - top))), @1];
        _dissolve.hidden = _scrimAlpha <= 0;
    } else {
        CGFloat start = round(height * (1 - SGRStretchHeroDissolve));
        if (_motion.opacity == 1 && _stillReading && height > 0) {
            CGFloat sharp = SGRCoverSharpnessFor(_stillReading, (height - kSharpRise) / height).sharpEnd;
            start = round(height * MIN(MAX(sharp, kStillFadeMin), kStillFadeMax));
        }
        self.dissolveHeight = height - start;
        _dissolve.hidden = YES;
    }
    [CATransaction commit];
}

- (void)sgr_dropRender {
    _renderKey = nil;
    _renderGeneration++;
    if (!_render) return;
    [_render removeFromSuperlayer];
    _render = nil;
    [self sgr_fitVeil];
    [self sgr_fitDissolve];
}

// Draws the picture off the main thread for the cover's reading, the hero's size and the page's color, unless that is
// what is shown or being drawn; nothing under an animated cover, which keeps what is there. A color the field has not
// shown yet is waited for once, kColorWait at most.
- (void)sgr_render {
    if (!_adaptive) return;
    SGRCoverReading *reading = _coverReading;
    UIImage *image = _picture.image;
    CGRect bounds = self.restBounds;
    if (!reading || !image || bounds.size.height < kMinHero || bounds.size.width < kMinCover) {
        [self sgr_dropRender];
        return;
    }
    if (_motion.opacity == 1) return;
    // The page's color as the field paints it (SGRArtworkField's fieldColor), which a low grey is not as read.
    UIColor *color = _fieldColor;
    if (!_colorWaitOver && ![color isEqual:SGRFieldShownColor(reading.pageColor)]) {
        if (_colorWaitBegun) return;
        _colorWaitBegun = YES;
        __weak SGRAlbumHero *weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kColorWait * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            SGRAlbumHero *hero = weakSelf;
            if (!hero) return;
            hero->_colorWaitOver = YES;
            [hero sgr_render];
        });
        return;
    }
    _colorWaitOver = YES;

    SGRCoverDrawing d = {.size = bounds.size, .place = [self sgr_fullPicture]};
    CGFloat screen = self.traitCollection.displayScale > 0 ? self.traitCollection.displayScale : UIScreen.mainScreen.scale;
    d.scale = MIN(screen, kRenderMaxScale);
    CGFloat placed = MAX(1, d.place.size.height);
    SGRCoverSharpness sharpness = SGRCoverSharpnessFor(reading, (bounds.size.height - kSharpRise - d.place.origin.y) / placed);
    d.sharpEnd = MIN(bounds.size.height, d.place.origin.y + sharpness.sharpEnd * placed);
    d.blurRadius = sharpness.blurRadius;
    d.mixStart = sharpness.mixLength > 0 ? MAX(d.sharpEnd, bounds.size.height - sharpness.mixLength) : d.sharpEnd;
    CGFloat r = 0, g = 0, b = 0, a = 1;
    [color getRed:&r green:&g blue:&b alpha:&a];
    d.page = SGRLabFromRGB(r, g, b);
    d.titleL = SGRIncreaseContrast() ? kTitleLContrast : kTitleL;
    NSString *key = [NSString stringWithFormat:@"%p %.0fx%.0f@%.0f %@ %@ %.2f %.4f %.4f %.4f %.2f %.2f %.2f %.2f", image,
                     image.size.width, image.size.height, image.scale, NSStringFromCGSize(d.size), NSStringFromCGRect(d.place),
                     d.scale, r, g, b, d.sharpEnd, d.blurRadius, d.mixStart, d.titleL];
    if ([key isEqualToString:_renderKey]) return;
    _renderKey = key;
    NSUInteger generation = ++_renderGeneration;
    SGRCoverRender *cached = [renderCache() objectForKey:key];
    if (cached && cached.source == image) {
        [self sgr_installRender:cached];
        return;
    }
    __weak SGRAlbumHero *weakSelf = self;
    CFTimeInterval started = CACurrentMediaTime();
    dispatch_async(renderQueue(), ^{
        CFTimeInterval renderingStarted = CACurrentMediaTime();
        SGRCoverRender *render;
        @autoreleasepool {
            render = renderCover(image, d);
        }
        CFTimeInterval took = CACurrentMediaTime() - renderingStarted;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!render) return;
            CGImageRef drawn = render.image.CGImage;
            [renderCache() setObject:render forKey:key cost:CGImageGetBytesPerRow(drawn) * CGImageGetHeight(drawn)];
            static NSUInteger logged;
            if (logged++ < kLoggedRenders)
                SGLog(@"redesign album: picture-aware cover %zux%zu px in %.0f ms (queue %.0f ms), sharp to %.0f of %.0fpt, blur %.0f, scrim %.2f",
                      CGImageGetWidth(drawn), CGImageGetHeight(drawn), took * 1000, (renderingStarted - started) * 1000,
                      d.sharpEnd, d.size.height, d.blurRadius, render.scrimAlpha);
            SGRAlbumHero *hero = weakSelf;
            // Drawn for what the hero no longer shows.
            if (!hero || generation != hero->_renderGeneration || hero->_picture.image != image) return;
            [hero sgr_installRender:render];
        });
    });
}

- (void)sgr_installRender:(SGRCoverRender *)render {
    if (!_render) {
        _render = [CALayer layer];
        _render.name = @"SGRAlbumHero.render";
        _render.zPosition = kRenderZ;
        _render.contentsGravity = kCAGravityResize;
        [self.content.layer addSublayer:_render];
    }
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    if (self.window) {
        CATransition *fade = [CATransition animation];
        fade.type = kCATransitionFade;
        fade.duration = SGRCrossfade;
        [_render addAnimation:fade forKey:@"contents"];
        [_dissolve addAnimation:fade forKey:@"contents"];
    }
    _renderTop = render.top;
    _renderDissolveHeight = render.dissolveHeight;
    [self sgr_placeRender];
    _render.contents = (__bridge id)render.image.CGImage;
    _render.contentsScale = render.image.scale;
    _scrimAlpha = render.scrimAlpha;
    [self sgr_fitVeil];
    [self sgr_fitDissolve];
    [CATransaction commit];
}

- (void)playMotionForArtist:(NSString *)artist album:(NSString *)album {
    NSString *key = artist.length && album.length ? [NSString stringWithFormat:@"%@\n%@", artist, album] : nil;
    UIView *page = SGRAlbumPageOf(self);
    NSString *release = SGRFindByIdentifier(self.superview, @"Components.UI.ContextMenuButton-*", &kMoreKey).accessibilityIdentifier;
    SGRAlbumMotionHeader(page, self, key, release);
    BOOL changedRelease = release.length && _motionRelease.length && ![_motionRelease isEqual:release];
    if (_motionPage == page && !changedRelease && (_motionAlbum == key || [key isEqualToString:_motionAlbum])) {
        if (release) _motionRelease = [release copy];
        return;
    }
    SGRAlbumWaitForMotionRow(_motionPage, NO, nil);
    _motionPage = page;
    _motionRelease = [release copy];
    NSUInteger generation = ++_motionGeneration;
    _motionAlbum = [key copy];
    // Stop owning A immediately, not only when B supplies a replacement clip.
    [self sgr_dropMotion];
    if (!key || !SGEnabled(SGRKeyAlbumMotion) || !SGMotionAppleMusicOn()) return;
    // The player's size: at the screen's full width a square cover ran to the 1920 stream, tens of MB.
    CGFloat pixels = SGMotionPixels();
    __weak SGRAlbumHero *weakSelf = self;
    __weak UIView *weakPage = page;
    NSString *albumURI = nil;
    for (UIResponder *r = page.nextResponder; r && !albumURI; r = r.nextResponder)
        if ([r isKindOfClass:UIViewController.class]) albumURI = [NSClassFromString(@"SGAlbumQueuePage") albumURI:r];
    // Tall, as the Music app's album page: the hero runs past the title, taller than wide, and a square clip
    // filled into it lost its sides. An album with only a square clip gets that one.
    void (^byTitle)(void) = ^{
        SGMotionPageAlbumCover(artist, album, albumURI, pixels, ^(NSURL *file, BOOL identified) {
            SGRAlbumHero *hero = weakSelf;
            UIView *owner = weakPage;
            if (!hero || hero->_motionGeneration != generation || SGRAlbumPageOf(hero) != owner) return;
            if (file) { [hero showMotion:file]; return; }
            if (identified || !SGMotionAppleMusicOn()) return;
            // Only one row clip may take ownership of this hero.
            __block BOOL shown = NO;
            void (^show)(NSURL *) = ^(NSURL *clip) {
                SGRAlbumHero *target = weakSelf;
                if (shown || !clip || !target || target->_motionGeneration != generation || SGRAlbumPageOf(target) != weakPage) return;
                shown = YES;
                [target showMotion:clip];
            };
            if (!SGRAlbumMotionRowsAllowed(owner)) return;
            BOOL (^stillCurrent)(void) = ^BOOL {
                SGRAlbumHero *current = weakSelf;
                return current && current->_motionGeneration == generation && SGRAlbumPageOf(current) == weakPage &&
                       SGRAlbumMotionRowsAllowed(weakPage);
            };
            BOOL (^startRows)(NSString *, NSString *) = ^BOOL(NSString *credit, NSString *song) {
                if (!stillCurrent()) return YES;
                SGMotionAlbumRowMatcher(artist, album, albumURI, pixels, ^(SGMotionRowMatch match) {
                    if (!stillCurrent()) return;
                    // Read rows again from the settled list, not strings captured before the search.
                    SGRAlbumWaitForMotionRow(weakPage, YES, match);
                }, ^(NSURL *clip) {
                    if (clip && stillCurrent()) show(clip);
                });
                return YES;
            };
            if (albumURI) startRows(nil, nil);
            else SGRAlbumWaitForMotionRow(owner, NO, startRows);
        });
    };
    // The album's identifiers first: they name the very release, where its title can name another of the same name
    // (the 2016 "Moana (Original Motion Picture Soundtrack)" took the 2026 film's clip). A clip they find is the
    // answer; a still edition they name may not be the one of Apple's that moves (a reissue's barcode), so the title
    // is asked then too, among Apple's releases of the album's year only (SGMotionPageStillEditionCover). Only an album
    // they cannot name goes to the title of every year and the rows.
    if (!albumURI) { byTitle(); return; }
    SGMotionPageIdentifierCover(albumURI, artist, album, pixels, ^(NSURL *file, SGMotionIdentifierOutcome outcome) {
        SGRAlbumHero *hero = weakSelf;
        if (!hero || hero->_motionGeneration != generation || SGRAlbumPageOf(hero) != weakPage) return;
        if (file) { [hero showMotion:file]; return; }
        if (outcome == SGMotionIdentifierMiss) { byTitle(); return; }
        if (outcome != SGMotionIdentifierStill) return;
        SGMotionPageStillEditionCover(albumURI, artist, album, pixels, ^(NSURL *clip) {
            SGRAlbumHero *target = weakSelf;
            if (clip && target && target->_motionGeneration == generation && SGRAlbumPageOf(target) == weakPage) [target showMotion:clip];
        });
    });
}

// Muted and looping, over the picture and under the two gradients. The picture stays under it until the
// first frame is decoded, and only then does the clip fade in: a fade started at once was spent on a layer
// with nothing in it, and the clip cut in after it.
- (void)showMotion:(NSURL *)file {
    [self sgr_dropMotion];
    __weak SGRAlbumHero *weakSelf = self;
    _clip = [[SGRHeaderClip alloc] initWithFile:file appearance:^(BOOL shown, BOOL entrance) {
        [weakSelf sgr_motionShown:shown entrance:entrance];
    }];
    _motion = _clip.layer;
    _motion.zPosition = 0.5;
    [_clip setFrame:self.restBounds];
    [self.content.layer addSublayer:_motion];
    [self sgr_fitVeil];
    _motionScrolls = [NSHashTable weakObjectsHashTable];
    SGRObserveVisibility(self, ^{ [weakSelf sgr_motionHierarchyChanged]; });
    [self sgr_motionHierarchyChanged];
    SGLog(@"redesign album: animated cover %@", file.lastPathComponent);
}

- (void)sgr_dropMotion {
    if (_motionScrolls) {
        SGRObserveVisibility(self, nil);
        SGRBindViewportScrolls(nil, _motionScrolls, self, &kScrollContext);
        _motionScrolls = nil;
    }
    [_clip invalidate];
    _clip = nil;
    _motion = nil;
    _stillFile = nil;
    _stillReading = nil;
    [self sgr_fitVeil];
    // The page goes back to the cover's reading. Not from -dealloc, out of the page by then.
    if (_adaptive && self.superview) {
        [self sgr_showReading];
    }
    // A square cover's gradients and shadow follow whether a clip covers it.
    if (!SGRPageFullCover(SGRKeyAlbumFullCover)) [self setNeedsLayout];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if (context == &kScrollContext) { [self sgr_updateMotion]; return; }
    [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}

// Once, when the clip has a frame to show: over 0.2 s on a curve most of the way there at once (the Kit's response,
// an entrance being quick), on screen; at once off it.
- (void)sgr_motionShown:(BOOL)shown entrance:(BOOL)entrance {
    if (shown && _adaptive && !_stillFile) [self sgr_readStill:_clip.file];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    [self sgr_fitVeil];
    // A square cover's hero gains the full-bleed surface only once the clip is ready.
    NSArray<CALayer *> *fading = SGRPageFullCover(SGRKeyAlbumFullCover) ? @[_motion] : @[_motion, self.scrim];
    if (shown) self.scrim.hidden = NO;
    [self setNeedsLayout];
    if (entrance && self.window && !SGRReduceMotion()) {
        CABasicAnimation *fade = [CABasicAnimation animationWithKeyPath:@"opacity"];
        fade.fromValue = @0;
        fade.toValue = @1;
        fade.duration = 0.2;
        fade.timingFunction = [CAMediaTimingFunction functionWithControlPoints:0.23 :1 :0.32 :1];
        for (CALayer *each in fading) [each addAnimation:fade forKey:@"fade"];
    }
    [CATransaction commit];
    // The clip's first frame now gives the page its color and the dissolve its start.
    if (_adaptive) [self sgr_showReading];
}

// The power state is reported off the main thread.
- (void)sgr_updateMotionSoon {
    dispatch_async(dispatch_get_main_queue(), ^{ [self sgr_updateMotion]; });
}

- (void)sgr_appState:(NSNotification *)note {
    _resigning = ![note.name isEqual:UIApplicationDidBecomeActiveNotification];
    _background = [note.name isEqual:UIApplicationDidEnterBackgroundNotification];
    [self sgr_updateMotion];
}

// The clip moves under the conditions the player's does (Player/PlayerMotion.x), and only with Auto-Play
// Video Previews on; otherwise it holds its frame. Off screen it stops: an album page left on the
// navigation stack would otherwise keep decoding.
- (void)sgr_updateMotion {
    [_clipPage bindHeader:self];
    if (!_clip) return;
    UIApplicationState state = UIApplication.sharedApplication.applicationState;
    BOOL front = !_resigning && state == UIApplicationStateActive;
    BOOL visible = !_background && state != UIApplicationStateBackground &&
                   [_clipPage visibleInViewport:SGRViewInViewport(self, SGRSettledPlayerRect(self.window))];
    BOOL may = SGMotionHeaderMayPlay(visible, front, SGRReduceMotion(),
                                   SGRMotionHeldForPowerOrHeat(), UIAccessibilityIsVideoAutoplayEnabled());
    [_clip updateVisible:visible active:front mayPlay:may];
}

- (void)sgr_motionHierarchyChanged {
    SGRBindViewportScrolls(self, _motionScrolls, self, &kScrollContext);
    [self sgr_updateMotion];
}

- (void)takeShadowFrom:(UIView *)cover {
    if (_shadow.shadowOpacity > 0) return;
    __block CALayer *found = nil;
    SGForEachView(cover, ^(UIView *v) {
        if (!found && v.layer.shadowOpacity > 0) found = v.layer;
    });
    if (!found) return;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _shadow.shadowColor = found.shadowColor;
    _shadow.shadowOpacity = found.shadowOpacity;
    _shadow.shadowRadius = found.shadowRadius;
    _shadow.shadowOffset = found.shadowOffset;
    [CATransaction commit];
    SGLog(@"redesign album: square shadow from %@, opacity %.2f radius %.1f offset %@", NSStringFromClass(found.delegate.class),
          found.shadowOpacity, found.shadowRadius, NSStringFromCGSize(found.shadowOffset));
    [self setNeedsLayout];
}

- (void)followCover:(UIImageView *)source {
    // Spotify's cover holds no artwork view of the lookup's size: the one followed is not its cover any more (a rebuilt
    // header's replacement can still be undersized here), and a picture landing in it later is not the album's.
    if (!source) {
        _cover = nil;
        return;
    }
    [self takeCover:source late:NO];
    if (_cover == source) return;
    _cover = source;
    __weak SGRAlbumHero *weakSelf = self;
    SGRObserveImage(source, ^(UIImageView *view) { [weakSelf takeCover:view late:YES]; });
}

// A rebuilt header's replacement artwork view can be under the lookup's size on the header's pass and get its size and
// its picture on passes of its own, which reach neither the header nor the page. Until one is followed, every image
// view in the element looks again when it gets a picture and, where its layout can be watched, when it is laid out at
// the lookup's size; the walk is made once per element waited on, and a pass under the size costs one comparison.
- (void)followCoverIn:(UIView *)element {
    UIImageView *artwork = SGRHeaderArtworkIn(element);
    [self followCover:artwork];
    if (artwork) {
        _awaited = nil;
        return;
    }
    if (!element || element == _awaited) return;
    _awaited = element;
    __weak SGRAlbumHero *weakSelf = self;
    __weak UIView *weakElement = element;
    void (^look)(UIView *) = ^(UIView *view) {
        SGRAlbumHero *hero = weakSelf;
        UIView *root = weakElement;
        if (!hero || !root || hero->_cover || view.bounds.size.width < kMinCover) return;
        [hero followCoverIn:root];
    };
    SGForEachView(element, ^(UIView *v) {
        if (![v isKindOfClass:UIImageView.class]) return;
        SGRObserveImage((UIImageView *)v, ^(UIImageView *view) { look(view); });
        SGRObserveLayout(v, look);
    });
}

// `late` is a cover that arrived after the header had laid out -- an album opened for the first time, whose
// artwork is still being fetched while the page is already on screen. The log line says once that the watch,
// and not one of the header's passes, is what filled the hero.
- (void)takeCover:(UIImageView *)source late:(BOOL)late {
    if (late && source != _cover) return;
    UIImage *image = source.image;
    if (!image || source.bounds.size.width < kMinCover || _picture.image == image) return;
    _picture.image = image;
    // The page's field takes its color from the same picture.
    SGRAlbumSetArtwork(self, image);
    if (_adaptive) [self sgr_readCover:image];
    static BOOL logged;
    if (late && !logged) {
        logged = YES;
        SGLog(@"redesign album: the cover landed after the header had laid out; the hero took it");
    }
}

@end

// The picture runs from the top of the header down past where its text begins, so the title and the artist
// sit on the bottom of its dissolve; below that the page's field is already drawing the very color the
// picture dissolves into, so there is no seam to see.
//
// `bottom` is taken from the header at rest, never from where it is mid scroll, and only ever grows: a header
// still loading is shorter than it will end up, and once the cover and the artist are in it settles and the
// picture does not change size again.
static void applyHero(UIView *header, UIView *cover, CGFloat bottom) {
    SGRAlbumHero *hero = objc_getAssociatedObject(header, &kHeroKey);
    if (!hero) {
        hero = [[SGRAlbumHero alloc] initWithFrame:CGRectZero];
        objc_setAssociatedObject(header, &kHeroKey, hero, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (hero.superview != header) [header insertSubview:hero atIndex:0];
    else if (header.subviews.firstObject != hero) [header sendSubviewToBack:hero];

    CGFloat height = [objc_getAssociatedObject(hero, &kHeroHeightKey) doubleValue];
    if (bottom > height + 0.5) {
        height = round(bottom);
        objc_setAssociatedObject(hero, &kHeroHeightKey, @(height), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        SGLog(@"redesign album: hero %.0fpt across the top of the header", height);
    }
    if (height < kMinHero) return;
    hero.restHeight = height;
    [hero sgr_place];
    hero.fieldColor = SGRAlbumFieldColor(header);
    // Spotify's square at full size, in the header's coordinates, which are the hero's: grow-only like the height,
    // so the square stays put while the header fades and collapses. Its bottom too, since the cover can reach its
    // full size before the header's top inset is in. A header of another width (an iPad window resized) has Spotify
    // lay its square out anew: the one kept is dropped and the square taken again from there. Spotify can centre it
    // in the new width a pass later, so one of the same size and height moved sideways is taken too: a scroll never
    // moves the square sideways.
    if (!SGRPageFullCover(SGRKeyAlbumFullCover)) {
        CGRect square = [cover convertRect:cover.bounds toView:header], kept = hero.square;
        CGFloat width = header.bounds.size.width;
        BOOL sideways = fabs(square.size.width - kept.size.width) <= 0.5 && fabs(square.size.height - kept.size.height) <= 0.5
            && fabs(CGRectGetMinY(square) - CGRectGetMinY(kept)) <= 0.5 && fabs(CGRectGetMinX(square) - CGRectGetMinX(kept)) > 0.5;
        if (square.size.width >= kMinCover && (fabs(width - hero.squareWidth) > 0.5 || sideways || square.size.width > kept.size.width + 0.5
                                               || CGRectGetMaxY(square) > CGRectGetMaxY(kept) + 0.5)) {
            hero.square = square;
            hero.squareWidth = width;
        }
        [hero takeShadowFrom:cover];
    }
    [hero followCoverIn:cover];
    SGRConcealView(cover);
}

#pragma mark - what the header shows

static NSString *trimmed(NSString *text) {
    NSString *clean = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return clean.length ? clean : nil;
}

// The first label under `root` with more than a letter in it: the facepile's initials are labels of their own.
static NSString *firstText(UIView *root) {
    __block NSString *found = nil;
    SGForEachView(root, ^(UIView *v) {
        if (found || ![v isKindOfClass:UILabel.class]) return;
        NSString *text = trimmed(((UILabel *)v).text);
        if (text.length > 1) found = text;
    });
    return found;
}

// The kind and the date ("Album • 31. 1. 2025", "Single • 2024") are cells of a collection view, a label each;
// read in the order they are drawn in.
static NSString *metadataText(UIView *metadata) {
    NSMutableArray<UILabel *> *labels = [NSMutableArray array];
    SGForEachView(metadata, ^(UIView *v) {
        if ([v isKindOfClass:UILabel.class] && trimmed(((UILabel *)v).text) && v.window) [labels addObject:(UILabel *)v];
    });
    [labels sortUsingComparator:^NSComparisonResult(UILabel *a, UILabel *b) {
        CGFloat ax = [a convertPoint:CGPointZero toView:metadata].x, bx = [b convertPoint:CGPointZero toView:metadata].x;
        return ax < bx ? NSOrderedAscending : (ax > bx ? NSOrderedDescending : NSOrderedSame);
    }];
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    for (UILabel *label in labels) [parts addObject:trimmed(label.text)];
    return parts.count ? [parts componentsJoinedByString:@" "] : nil;
}

static void applyHeader(UIView *header, UIView *page);

// The headers that have drawn an artist line, drawn again when Artist picture is flipped so the albums open follow it.
// The defaults post their change on the writing thread: taken to main, where the headers are.
static void followArtistPicture(UIView *header) {
    static NSHashTable<UIView *> *headers;
    static BOOL shown;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        headers = [NSHashTable weakObjectsHashTable];
        shown = SGEnabled(SGRKeyAlbumArtistPicture);
        [NSNotificationCenter.defaultCenter addObserverForName:NSUserDefaultsDidChangeNotification object:nil queue:nil
                                                    usingBlock:^(NSNotification *note) {
            dispatch_async(dispatch_get_main_queue(), ^{
                SGPrefsChanged();
                BOOL on = SGEnabled(SGRKeyAlbumArtistPicture);
                if (on == shown) return;
                shown = on;
                for (UIView *known in headers.allObjects) {
                    UIView *page = SGRAlbumPageOf(known);
                    if (page) applyHeader(known, page);
                }
            });
        }];
    });
    [headers addObject:header];
}

// The Kit's view over the whole header, its content on the header's bottom edge; Spotify's own column goes.
static SGRHeaderInfo *applyInfo(UIView *header, UIView *page, NSString **artist, NSString **album) {
    SGRHeaderInfo *info = objc_getAssociatedObject(header, &kInfoKey);
    if (!info) {
        info = [[SGRHeaderInfo alloc] initWithFrame:CGRectZero];
        objc_setAssociatedObject(header, &kInfoKey, info, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (info.superview != header) [header addSubview:info];
    else if (header.subviews.lastObject != info) [header bringSubviewToFront:info];
    SGRAlbumHero *hero = objc_getAssociatedObject(header, &kHeroKey);
    for (UIView *sub in header.subviews) {
        if (sub != info && sub != hero) SGRBlankView(sub);
    }
    if (!info.sgr_coverBeside) setFrame(info, header.bounds);

    UIView *title = SGRFindByIdentifier(header, @"CreativeWorkPlatform.Components.UI.TitleRow", &kTitleKey);
    // Spotify's header grows and shrinks as its Play turns to Pause (issue #25), its title row does not.
    if (title.window) {
        CGFloat top = [title convertRect:title.bounds toView:header].origin.y;
        if (fabs(top - info.pinnedTop) > 0.5) {
            info.pinnedTop = top;
            [info setNeedsLayout];
        }
    }
    UIView *parent = SGRFindByIdentifier(header, @"CreativeWorkPlatform.Components.UI.ParentRow", &kParentKey);
    UIView *metadata = SGRFindByIdentifier(header, @"Components.UI.MetadataRow", &kMetaKey);
    NSString *length = metadataText(metadata), *line = firstText(parent);
    *album = SGRFirstLabelText(title);
    *artist = line ?: trimmed(parent.accessibilityLabel);
    [info showTitle:*album creator:*artist length:length about:nil];
    // The line as it reads, without the accessibility label to fall back on: no line, no row loses its artist.
    SGRAlbumSetArtist(page, line);
    // And the title, for the rows to find their plays by.
    SGRAlbumSetTitle(page, SGRFirstLabelText(title));
    // The kind and the date are cells the metadata row's collection view makes on its own pass, after the
    // header's, and nothing lays the header out again when they arrive; the collection is Spotify's own Swift
    // class, which cannot be watched. So an empty row is read again a moment later, a few times at most.
    NSInteger tries = [objc_getAssociatedObject(header, &kRetryKey) integerValue];
    if (!length && metadata && tries < 6) {
        objc_setAssociatedObject(header, &kRetryKey, @(tries + 1), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        __weak UIView *weakHeader = header, *weakPage = page;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (weakHeader && weakPage) applyHeader(weakHeader, weakPage);
        });
    }

    // The artist under the title, opened from the line that names them. ParentRow is one control for the
    // whole line however many artists are on the album, so several of them open Spotify's own picker
    // (issue #56).
    [info showCreatorLink:parent];
    // And the artists' faces before the names, the ones Spotify draws at the start of the row (several for several
    // artists), while the Albums page's Artist picture is on.
    [info showCreatorFaces:SGEnabled(SGRKeyAlbumArtistPicture) ? SGRCreatorFaces(parent) : nil from:parent];
    followArtistPicture(header);

    // More, pinned over the page rather than left in the header, which is blanked and scrolls away.
    SGRPinnedMore(page, &kPinnedMoreKey, SGRFindByIdentifier(header, @"Components.UI.ContextMenuButton*", &kMoreKey));

    UIView *play = floatingIn(page, @"header-play-button", &kPlayKey);
    UIView *shuffle = floatingIn(page, @"Components.UI.ShuffleButton", &kShuffleKey);
    UIView *add = SGRFindByIdentifier(header, @"Components.UI.AddToButton", &kAddKey);
    UIView *download = SGRFindByIdentifier(header, @"DownloadButton.Granular*", &kDownloadKey);
    // Shuffle, Play and add, Play on the middle of the page; download beside the pinned ⋯.
    [info showShuffle:shuffle play:play trailing:add trailingFallback:[UIImage systemImageNamed:@"plus"]
            playColor:SGRAlbumFieldColor(header)];
    SGRPinnedDownload(page, &kPinnedDownloadKey, download);
    // Only what the two floating buttons draw goes: a concealed layer still sends the actions the row fires.
    if (play) SGRConcealView(wrapperFor(play, page));
    if (shuffle) SGRConcealView(wrapperFor(shuffle, page));

    // Add arrives after the header has laid out on an album opened for the first time (the next time its state
    // is cached and it is there from the start), in a row that lays nothing else out (Native/Album/Album.x): the
    // row drew download on Play's right, or nothing, until the page was opened again (issue #19). So the row's
    // own pass is watched, a plain UIStackView, as the artist page's is, found from whichever of Spotify's
    // buttons is in it already.
    UIView *inRow = add ?: download ?: SGRFindByIdentifier(header, @"Components.UI.WatchFeedEntityExplorerButton", &kExploreKey);
    __weak UIView *weakHeader = header, *weakPage = page;
    watch(rowOf(inRow, header), &kRowWatchedKey, ^(UIView *view) {
        if (weakHeader && weakPage) applyHeader(weakHeader, weakPage);
    });

    static BOOL logged;
    if (!logged && header.window && title) {
        logged = YES;
        SGLog(@"redesign album: own block \"%@\" by %@, \"%@\"; shuffle %@, play %@, %@", firstText(title),
              firstText(parent) ?: trimmed(parent.accessibilityLabel) ?: @"nobody", metadataText(metadata) ?: @"no metadata", shuffle ? @"found" : @"missing",
              play ? @"found" : @"missing", add ? @"add" : (download ? @"download" : @"nothing on the right"));
    }
    return info;
}

#pragma mark - the header's pass

// Drawn by nothing, whatever Spotify does to it: an empty mask. Spotify switches the navigation bar's
// gradient on and off with -setHidden:, which writes the layer's own hidden and so undoes concealment; and
// it fades both gradients by alpha. Neither touches a mask.
static void maskOut(UIView *view) {
    if (!view || view.layer.mask) return;
    view.layer.mask = [CALayer layer];
    view.accessibilityElementsHidden = YES;
}

// The color Spotify painted the wash in: the first opaque color of the gradient layer it draws with,
// whether that is the view's own layer or one under it. nil when it draws some other way, or has
// no color yet.
static UIColor *washColorOf(UIView *gradient) {
    NSMutableArray<CALayer *> *layers = [NSMutableArray arrayWithObject:gradient.layer];
    [layers addObjectsFromArray:gradient.layer.sublayers ?: @[]];
    for (CALayer *layer in layers) {
        if (![layer isKindOfClass:CAGradientLayer.class]) continue;
        for (id value in ((CAGradientLayer *)layer).colors) {
            CGColorRef cg = (__bridge CGColorRef)value;
            if (CFGetTypeID(cg) != CGColorGetTypeID() || CGColorGetAlpha(cg) < 0.5) continue;
            // The page's base surface is what a wash is before Spotify has a color for it, not a color.
            if (SGIsBaseSurface(cg)) return nil;
            return [UIColor colorWithCGColor:cg];
        }
    }
    return nil;
}

// Spotify's color wash behind the header goes, so the page's field shows through, and the color it was
// painted in goes to the field, to show until the cover's own main color has been read.
//
// The navigation bar's gradient goes too. Hidden at rest, it is shown as the page scrolls under the
// title, and over the field it was a flat dark band across the top (device, 2026-09-18). What keeps the
// title legible over the list is the soft top edge every redesigned page has (SGREdgeEffect.x), as it is
// on Home, Search and Library.
static void applyWash(UIView *page) {
    for (UIView *sub in page.subviews) {
        NSString *name = NSStringFromClass(sub.class);
        if (![name containsString:@"HeaderView"] && ![name containsString:@"HeaderNavigationBar"]) continue;
        BOOL wash = ![name containsString:@"NavigationBar"];
        for (UIView *v in sub.subviews) {
            if (![NSStringFromClass(v.class) containsString:@"GradientView"]) continue;
            if (wash) {
                UIColor *color = washColorOf(v);
                static BOOL logged;
                if (!logged) {
                    logged = YES;
                    SGLog(@"redesign album: Spotify's wash %@ on %@, color %@", NSStringFromClass(v.class),
                          NSStringFromClass(v.layer.class), color ?: @"not found");
                }
                SGRAlbumSetSpotifyColor(page, color);
            }
            maskOut(v);
        }
    }
}

// The ⋯ and download pinned to the page, in the header's coordinates with the page at rest: they stay where
// they are while the header scrolls under them, so the scroll is taken back out, read from the scroll owner the hero
// reads its pull from. CGRectNull while neither is shown on the page (Cover beside puts them in the header's info).
static CGRect pinnedChrome(UIView *header, UIView *page) {
    static const void *const keys[] = {&kPinnedMoreKey, &kPinnedDownloadKey};
    CGRect chrome = CGRectNull;
    for (size_t i = 0; i < sizeof keys / sizeof *keys; i++) {
        UIView *button = objc_getAssociatedObject(page, keys[i]);
        if (button.superview == page && !button.hidden) chrome = CGRectUnion(chrome, button.frame);
    }
    if (CGRectIsNull(chrome)) return chrome;
    UIScrollView *scroll = SGRStretchHeroScrollAbove(header);
    CGFloat scrolled = scroll ? scroll.contentOffset.y + scroll.adjustedContentInset.top : 0;
    return CGRectOffset([page convertRect:chrome toView:header], 0, -scrolled);
}

static void applyHeader(UIView *header, UIView *page) {
    if (!SGRFindByIdentifier(header, @"CreativeWorkPlatform.Components.UI.TitleRow", &kTitleKey)) return;
    SGRAlbumHoldPage(page);
    applyWash(page);
    NSString *artist, *album;
    SGRHeaderInfo *info = applyInfo(header, page, &artist, &album);

    // The picture reaches to where the content's top is at rest, plus the title and the artist. The header at
    // rest is the tallest it has been, so the picture does not change size as the header loads or scrolls.
    CGFloat rest = MAX([objc_getAssociatedObject(header, &kHeaderHeightKey) doubleValue], header.bounds.size.height);
    objc_setAssociatedObject(header, &kHeaderHeightKey, @(rest), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    UIView *cover = SGRFindByIdentifier(header, @"CreativeWorkPlatform.Components.UI.ArtWorkElement.WithCoverArt", &kCoverKey);
    __weak UIView *weakHeader = header, *weakPage = page;
    CGRect available = CGRectInset(header.bounds, 20, 0);
    CGFloat top = cover ? CGRectGetMinY([cover convertRect:cover.bounds toView:header]) : 0;
    available.origin.y = top;
    available.size.height -= top + SGRHeaderInfoBottom;
    CGRect beside = [info sgr_coverBesideIn:header available:cover ? available : CGRectZero fitHeight:NO
        direction:page.effectiveUserInterfaceLayoutDirection
        stackedParent:header stackedFrame:header.bounds
        more:objc_getAssociatedObject(page, &kPinnedMoreKey) download:objc_getAssociatedObject(page, &kPinnedDownloadKey)
        refresh:^{ if (weakHeader && weakPage) applyHeader(weakHeader, weakPage); }];
    SGRAlbumHero *existingHero = objc_getAssociatedObject(header, &kHeroKey);
    existingHero.besideFrame = beside;
    CGFloat bottom = rest - SGRHeaderInfoBottom - [info contentHeightForWidth:header.bounds.size.width] + SGRHeaderInfoTitleRise;
    // A pass without Spotify's cover element (the header rebuilding) leaves the hero following no artwork view: the
    // one it followed is retired with the element.
    if (cover) applyHero(header, cover, bottom);
    else [existingHero followCover:nil];
    SGRAlbumHero *hero = objc_getAssociatedObject(header, &kHeroKey);
    hero.besideFrame = beside;
    hero.chrome = pinnedChrome(header, page);
    header.accessibilityElements = info.sgr_coverBeside ? @[hero, info] : nil;
    // The header scrolls with the page's scroll view, the hero and the info with it. Spotify fades its header
    // element as the page scrolls; over the Music app's layout that left the title, the artist and the row faint
    // under the bar, so the element stays solid and the info is clipped under the bar instead.
    UIScrollView *scroll = SGRStretchHeroScrollAbove(header);
    SGRKeepOpaque(header.superview);
    [info clipUnderTopBarFollowing:scroll];
    SGRHeroVeil *veil = hero.veil;
    if (veil) {
        [veil followScroll:scroll];
        [veil update];
    }
    [hero playMotionForArtist:artist album:album];
    SGRAlbumNotesUpdate(header, page, artist, album);
}

static void applyPage(UIView *page) {
    UIView *header = SGRFindByIdentifier(page, @"CreativeWorkPlatform.Components.UI.CreativeWorkHeader", &kHeaderKey);
    if (!header) return;
    applyHeader(header, page);
    // The header lays itself out again whenever its cover, its artist or its buttons arrive, which the
    // page's own pass does not hear about. It is a plain UIView, so its pass can be watched.
    watch(header, &kHeaderWatchedKey, ^(UIView *view) {
        UIView *owner = SGRAlbumPageOf(view);
        if (owner) applyHeader(view, owner);
    });
}

%hook _TtC28CreativeWorkPlatform_PageKit24CreativeWorkTemplateView
- (void)layoutSubviews {
    %orig;
    applyPage((UIView *)self);
}
%end

// The play button arrives in the page after the row that replaces it has been laid out, so a page opening
// showed Spotify's green disc in the corner until something else laid the page out. Its own pass is where
// it goes, and the class is Spotify's own so nothing else pays for the check.
%hook _TtC28EncoreConsumerMobile_BaseKit14PlayButtonView
- (void)layoutSubviews {
    %orig;
    UIView *button = (UIView *)self;
    if (button.layer.hidden || ![button.accessibilityIdentifier isEqualToString:@"header-play-button"]) return;
    UIView *page = SGRAlbumPageOf(button);
    if (!page) return;
    SGRConcealView(wrapperFor(button, page));
    applyPage(page);
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
    SGRequireClasses(@[
        @"_TtC28CreativeWorkPlatform_PageKit24CreativeWorkTemplateView",
        @"_TtC28EncoreConsumerMobile_BaseKit14PlayButtonView",
    ]);
}
