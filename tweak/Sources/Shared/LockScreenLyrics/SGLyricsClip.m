// SGLyricsClip.h says what this draws. The words are laid out once per clip and only the backdrop moves,
// so an animated clip costs a scaled image draw and an encode a frame.
#import <Accelerate/Accelerate.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreText/CoreText.h>
#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h>   // Vinyl's serif design, which Core Text does not name
#else
#import <AppKit/AppKit.h>
#endif
#import "SGLyricsClip.h"
#import "Shared/LyricsBackground/LyricsBackground.h"

// Change this token whenever the drawn picture changes: the system caches artwork across app builds.
static NSString *const kRenderVersion = @"r2";

// IMG_1800 shows the whole 3:4 frame across the screen, not a centre crop. Its text centre places
// the frame's top about 10% down a 1179x2556 screen. Map screen-safe heights into that frame once;
// all six layouts use its full width. The clock is at 11%, the media controls start at 68%.
static const CGFloat kFrameScreenTop = 0.10, kFrameScreenHeight = (4.0 / 3) * 1179 / 2556;
static const CGFloat kSafeScreenTop = 0.17, kSafeScreenBottom = 0.65, kTextScreenCentre = 0.4;
#define kTop ((kSafeScreenTop - kFrameScreenTop) / kFrameScreenHeight)
#define kLowest ((kSafeScreenBottom - kFrameScreenTop) / kFrameScreenHeight)
#define kCentreY ((kTextScreenCentre - kFrameScreenTop) / kFrameScreenHeight)
static const CGFloat kMargin = 0.08, kColumn = 0.84;
// Poster sets the line kPosterScale of the size in a heavy weight (UIFontWeightHeavy's trait), alone; its
// translation keeps the size it has under the other layouts.
static const CGFloat kPosterScale = 1.6, kPosterWeight = 0.56;
// The words' size as a share of the width, made smaller down to kSmallest of it while they run taller
// than kTallest of the height.
static const CGFloat kFont = 0.047;
static const CGFloat kSmallest = 0.6;
static const CGFloat kTallest = 0.4;
// The lines either side of the line (the next, and over moving artwork the one sung last) in the regular weight
// at this share of its size, kNextAlpha white, kNextGap of the line's size from it.
static const CGFloat kNextScale = 0.6, kNextAlpha = 0.5, kNextGap = 0.5;
// A translation sits close under its line, in the regular weight at this share of the line's size and this white.
static const CGFloat kTranslationScale = 0.62, kTranslationAlpha = 0.8, kTranslationGap = 0.15;
// OverArtwork: a continuous side-anchored Gaussian, without a rectangular core or cutoff.
// Reaches are in frame widths; the vertical reach grows with the text block.
static const CGFloat kArtworkScrimAlpha = 0.94, kArtworkSideReach = 1.8, kArtworkVerticalReach = 0.6;
static const CGFloat kArtworkShadowAlpha = 0.45;
// Dimmed whole (SGLyricsClipDimmedArtwork): the cover blurred by the shared renderer at kDimBlur (at width 640, about
// the spread the tent of kSoftWidth gives a video's frames), then darkened evenly, by at least kDimLeast so a dark
// cover reads as dimmed too, and by as much more as the brightest pixel of the blurred picture needs for a dimmed line
// (kNextAlpha white over it) to keep kDimContrast and the line kLineContrast: 3:1 with a tenth to spare for the
// encoder and the breath's resampling, and 4.5:1. A white cover comes to about a third of white: grey, not black.
static const CGFloat kDimBlur = 20, kDimLeast = 0.3, kDimContrast = 3.3, kLineContrast = 4.5;
// A still is one frame held this long; an animated clip breathes once over kLoopSeconds, which is all it
// plays before the lock screen loops it.
static const int32_t kStillSeconds = 2;
static const int32_t kLoopSeconds = 4;
static const int32_t kFPS = 15;   // the breath is slow; at 24 a line took about 4 s to write on the CPU
static const CGFloat kBreath = 0.06;   // how much bigger the cover grows at the top of a breath
// Over moving artwork, judged on bright, busy and dark clips in harness/lyrics-clip: the picture is dimmed by
// kMotionDim, and by kBandDim where the words sit, fading between the two over kBandReach of the height above
// and below the middle, so white in it stays under 0.4 of the words' white there; behind the words it is
// blurred, a tent kSoftWidth of the width across (127 pixels at most), so no pattern in it crosses the letters,
// the dimmed ones included; the words carry a tight dark shadow kShadowBlur of the font size wide, and the dimmed lines are
// kMotionNextAlpha white. Over a bright picture the band is darker, held for the clip: enough that the brightest
// tenth behind the words, on the brightest of kBandSamples frames spread across the stretch the clip shows, comes
// to kBandLight of white, up to kBandDarkest.
static const CGFloat kMotionDim = 0.25, kBandDim = 0.6, kBandReach = 0.3, kSoftWidth = 0.16;
static const CGFloat kBandLight = 0.22, kBandDarkest = 0.8;
static const int kBandSamples = 4;
static const CGFloat kShadowAlpha = 0.9, kShadowBlur = 0.15, kMotionNextAlpha = 0.55;
// A faster video keeps only this many frames a second: each costs a draw on the CPU.
static const double kMotionFPS = 30;

CGSize SGLyricsClipSize(CGFloat pixels) {
    // Three 16-pixel blocks across and four down preserve both the ratio and encoder alignment.
    CGFloat blocks = MAX(floor(pixels / (3 * 16)), 1);
    return CGSizeMake(blocks * 3 * 16, blocks * 4 * 16);
}

static CGContextRef newContext(CGSize size, void *data, size_t bytesPerRow) {
    CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGContextRef context = CGBitmapContextCreate(data, (size_t)size.width, (size_t)size.height, 8, bytesPerRow, space,
                                                 kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
    CGColorSpaceRelease(space);
    return context;
}

CGImageRef SGLyricsClipBackdrop(CGImageRef cover, CGSize size) {
    return SGLyricsBackgroundCreate(cover, size, SGLyricsBackgroundDefault(SGLyricsBackgroundLockScreen));
}

// The colours a darkening is judged on: each channel cut into kLightSteps steps of kLightStep levels, and the steps
// of the picture's pixels marked, red, then green, then blue. A step is judged on its worst level in each channel,
// so a judgement on these is never kinder than one on the pixels.
enum { kLightStep = 4, kLightSteps = 256 / kLightStep, kLightCells = kLightSteps * kLightSteps * kLightSteps };
typedef struct {
    uint64_t seen[kLightCells / 64];
} Lights;

static void markLight(Lights *lights, int red, int green, int blue) {
    size_t cell = ((size_t)(red / kLightStep) * kLightSteps + green / kLightStep) * kLightSteps + blue / kLightStep;
    lights->seen[cell / 64] |= 1ull << (cell % 64);
}

// The pixels of a BGRA picture into `lights`.
static void addLights(Lights *lights, const uint8_t *base, size_t width, size_t height, size_t bytesPerRow) {
    for (size_t y = 0; y < height; y++) {
        const uint8_t *pixel = base + y * bytesPerRow;
        for (size_t x = 0; x < width; x++, pixel += 4) markLight(lights, pixel[2], pixel[1], pixel[0]);
    }
}

// An sRGB value, 0 to 1, as linear light.
static double linearOf(double value) {
    return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4);
}

// Whether every colour of `lights` is readable over once `keep` of it is kept, each level then taken one higher for
// the rounding of the darkening: the line keeping kLineContrast, and a dimmed line, kNextAlpha white blended over
// it, kDimContrast. With L a colour's WCAG luminance and D the blend's, those are 1.05 / (L + 0.05) >= kLineContrast
// and D - kDimContrast * L >= 0.05 * (kDimContrast - 1); L and D are each a weighted sum of one function per
// channel, so both tests are too, and a step's worst colour is found channel by channel: its top level for the
// line, its least margin of the blend's light over kDimContrast times its own for the dimmed line. With none, the
// picture is judged as white.
static BOOL readableAt(const Lights *lights, double keep) {
    double light[kLightSteps], margin[kLightSteps], a = kNextAlpha;
    for (int step = 0; step < kLightSteps; step++) {
        margin[step] = INFINITY;
        for (int level = step * kLightStep; level < (step + 1) * kLightStep; level++) {
            double value = MIN(level * keep + 1, 255) / 255;
            light[step] = linearOf(value);
            margin[step] = MIN(margin[step], linearOf(a + (1 - a) * value) - kDimContrast * light[step]);
        }
    }
    double mostLight = 1.05 / kLineContrast - 0.05, leastMargin = 0.05 * (kDimContrast - 1);
    BOOL any = NO;
    for (size_t word = 0; word < kLightCells / 64; word++) {
        for (uint64_t bits = lights->seen[word]; bits; bits &= bits - 1) {
            size_t cell = word * 64 + (size_t)__builtin_ctzll(bits);
            size_t red = cell / (kLightSteps * kLightSteps), green = cell / kLightSteps % kLightSteps, blue = cell % kLightSteps;
            if (0.2126 * light[red] + 0.7152 * light[green] + 0.0722 * light[blue] > mostLight) return NO;
            if (0.2126 * margin[red] + 0.7152 * margin[green] + 0.0722 * margin[blue] < leastMargin) return NO;
            any = YES;
        }
    }
    if (any) return YES;
    Lights white = {0};
    markLight(&white, 255, 255, 255);
    return readableAt(&white, keep);
}

// How much of the picture an even darkening keeps, of 256: the most that leaves all of `lights` readable, and no more
// than kDimLeast leaves. Black always is.
static uint16_t keepFor(const Lights *lights) {
    uint16_t low = 0, high = (uint16_t)floor(256 * (1 - kDimLeast));
    if (readableAt(lights, high / 256.0)) return high;
    while (high - low > 1) {
        uint16_t middle = (low + high) / 2;
        if (readableAt(lights, middle / 256.0)) low = middle;
        else high = middle;
    }
    return low;
}

static CGImageRef createDimmedArtwork(CGImageRef cover, CGSize size) {
    SGLyricsBackgroundStyle style = {SGLyricsBackgroundBlur, 0, kDimBlur, 0};
    CGImageRef blurred = SGLyricsBackgroundCreate(cover, size, style);
    if (!blurred) return NULL;
    CGContextRef context = newContext(size, NULL, 0);
    if (!context) {
        CGImageRelease(blurred);
        return NULL;
    }
    CGContextDrawImage(context, (CGRect){CGPointZero, size}, blurred);
    CGImageRelease(blurred);
    Lights lights = {0};
    addLights(&lights, CGBitmapContextGetData(context), (size_t)size.width, (size_t)size.height, CGBitmapContextGetBytesPerRow(context));
    CGContextSetRGBFillColor(context, 0, 0, 0, MIN(.85, 1 - keepFor(&lights) / 256.0));
    CGContextFillRect(context, (CGRect){CGPointZero, size});
    CGImageRef dimmed = CGBitmapContextCreateImage(context);
    CGContextRelease(context);
    return dimmed;
}

CGImageRef SGLyricsClipDimmedArtwork(CGImageRef cover, CGSize size) {
    // This renderer has a single, fixed style. Preserve the exact draw size, including fractions.
    static NSCache<NSArray *, NSArray *> *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        cache = [NSCache new];
        cache.countLimit = 8;
        cache.totalCostLimit = 32 * 1024 * 1024;
    });
    NSArray *key = @[[NSValue valueWithPointer:cover], @(size.width), @(size.height)];
    @synchronized (cache) {
        NSArray *hit = [cache objectForKey:key];
        if (hit) return CGImageRetain((__bridge CGImageRef)hit[0]);
        CGImageRef image = createDimmedArtwork(cover, size);
        if (image) {
            // Retain the cover with the result: its address cannot be recycled under a live key.
            [cache setObject:@[(__bridge id)image, (__bridge id)cover ?: NSNull.null] forKey:key
                        cost:CGImageGetBytesPerRow(image) * CGImageGetHeight(image)];
        }
        return image;
    }
}

static BOOL isHangul(unichar c) {
    return (c >= 0xAC00 && c <= 0xD7A3) || (c >= 0x1100 && c <= 0x11FF) || (c >= 0x3130 && c <= 0x318F);
}

// Core Text breaks Korean inside a word, whatever language the text is tagged with; Korean breaks between words. A
// word joiner between two Hangul letters keeps each word whole, so its lines break at the spaces. A word wider than
// the column is still broken, as Core Text breaks any word that does not fit.
static NSString *keptWhole(NSString *text) {
    if (![text containsString:@" "]) return text;
    NSMutableString *kept = [NSMutableString stringWithCapacity:text.length + text.length / 2];
    for (NSUInteger i = 0; i < text.length; i++) {
        unichar c = [text characterAtIndex:i];
        if (i && isHangul(c) && isHangul([text characterAtIndex:i - 1])) [kept appendString:@"\u2060"];
        [kept appendFormat:@"%C", c];
    }
    return kept;
}

// The system font at `size` in kPosterWeight; Korean and Japanese fall back to their fonts' nearest weight.
static CTFontRef newHeavyFont(CGFloat size) CF_RETURNS_RETAINED {
    CTFontRef system = CTFontCreateUIFontForLanguage(kCTFontUIFontSystem, size, NULL);
    CTFontDescriptorRef descriptor = CTFontCopyFontDescriptor(system);
    NSDictionary *heavy = @{(id)kCTFontTraitsAttribute: @{(id)kCTFontWeightTrait: @(kPosterWeight)}};
    CTFontDescriptorRef weighted = CTFontDescriptorCreateCopyWithAttributes(descriptor, (__bridge CFDictionaryRef)heavy);
    CTFontRef font = CTFontCreateWithFontDescriptor(weighted, size, NULL);
    CFRelease(weighted);
    CFRelease(descriptor);
    CFRelease(system);
    return font;
}

// The line sung last (dimmed, smaller), the line, its translation, and the next line (dimmed, smaller), each its
// own paragraph. The translation goes only with the line it belongs to. In the Poster layout the line is larger and
// heavy, and a next line (which then shows alone) has its font.
static NSAttributedString *wordsAt(NSString *previous, NSString *line, NSString *translation, NSString *next,
                                   CGFloat fontSize, CGFloat dimAlpha, SGLyricsClipLayout layout) {
    if (!line.length) translation = nil;
    BOOL poster = layout == SGLyricsClipPoster, centred = layout == SGLyricsClipCentered;
    CGFloat lineSize = poster ? fontSize * kPosterScale : fontSize;
    CTFontRef font = poster ? newHeavyFont(lineSize) : CTFontCreateUIFontForLanguage(kCTFontUIFontEmphasizedSystem, fontSize, NULL);
    CTFontRef small = CTFontCreateUIFontForLanguage(kCTFontUIFontSystem, fontSize * kTranslationScale, NULL);
    CTFontRef aside = poster ? (CTFontRef)CFRetain(font) : CTFontCreateUIFontForLanguage(kCTFontUIFontSystem, fontSize * kNextScale, NULL);
    CGFloat spacing = fontSize * kNextGap, gap = lineSize * kTranslationGap, tall = round(fontSize * kTranslationScale * 1.3);
    CTTextAlignment centre = kCTTextAlignmentCenter;
    CTParagraphStyleSetting settings[] = {
        {kCTParagraphStyleSpecifierParagraphSpacingBefore, sizeof(spacing), &spacing},
        {kCTParagraphStyleSpecifierAlignment, sizeof(centre), &centre},
    };
    // A fallback font for its script (Korean's, Japanese's) sets the lines further apart than the line's own: held
    // to the line's spacing.
    CTParagraphStyleSetting under[] = {
        {kCTParagraphStyleSpecifierParagraphSpacingBefore, sizeof(gap), &gap},
        {kCTParagraphStyleSpecifierMaximumLineHeight, sizeof(tall), &tall},
        {kCTParagraphStyleSpecifierMinimumLineHeight, sizeof(tall), &tall},
        {kCTParagraphStyleSpecifierAlignment, sizeof(centre), &centre},
    };
    // The alignment, last, is set only when centred; the others keep the natural one.
    CTParagraphStyleRef paragraph = CTParagraphStyleCreate(settings, centred ? 2 : 1), close = CTParagraphStyleCreate(under, centred ? 4 : 3);
    translation = keptWhole(translation);
    CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGFloat white[] = {1, 1, 1, 1}, dim[] = {1, 1, 1, dimAlpha}, soft[] = {1, 1, 1, kTranslationAlpha};
    CGColorRef lit = CGColorCreate(space, white), unlit = CGColorCreate(space, dim), told = CGColorCreate(space, soft);
    NSMutableAttributedString *words = [NSMutableAttributedString new];
    NSString *texts[] = {previous, line, translation, next};
    for (int i = 0; i < 4; i++) {
        if (!texts[i].length) continue;
        BOOL isTranslation = i == 2;
        NSMutableDictionary *attributes = [@{
            (id)kCTFontAttributeName: (__bridge id)(i == 1 ? font : isTranslation ? small : aside),
            (id)kCTParagraphStyleAttributeName: (__bridge id)(isTranslation ? close : paragraph),
            (id)kCTForegroundColorAttributeName: (__bridge id)(i == 1 ? lit : isTranslation ? told : unlit),
        } mutableCopy];
        NSString *text = words.length ? [@"\n" stringByAppendingString:texts[i]] : texts[i];
        [words appendAttributedString:[[NSAttributedString alloc] initWithString:text attributes:attributes]];
    }
    CFRelease(font);
    CFRelease(small);
    CFRelease(aside);
    CFRelease(paragraph);
    CFRelease(close);
    CGColorRelease(lit);
    CGColorRelease(unlit);
    CGColorRelease(told);
    CGColorSpaceRelease(space);
    return words;
}

// The lines of `frame`, which holds as many whole lines of `words` as fit `box`, the last set again from where it
// starts to the end of the words and cut to the box's width with an ellipsis, placed `flush` of the way across.
static void drawCut(CTFrameRef frame, NSAttributedString *words, CGContextRef context, CGRect box, CGFloat flush) {
    CFArrayRef lines = CTFrameGetLines(frame);
    CFIndex count = CFArrayGetCount(lines);
    if (!count) return;
    CGPoint origins[count];
    CTFrameGetLineOrigins(frame, CFRangeMake(0, 0), origins);
    for (CFIndex i = 0; i < count; i++) {
        CTLineRef line = CFArrayGetValueAtIndex(lines, i), cut = NULL;
        CGFloat x = origins[i].x;
        if (i == count - 1) {
            NSUInteger start = (NSUInteger)CTLineGetStringRange(line).location;
            NSAttributedString *rest = [words attributedSubstringFromRange:NSMakeRange(start, words.length - start)];
            NSAttributedString *mark = [[NSAttributedString alloc] initWithString:@"\u2026" attributes:[words attributesAtIndex:start effectiveRange:NULL]];
            CTLineRef whole = CTLineCreateWithAttributedString((__bridge CFAttributedStringRef)rest);
            CTLineRef ellipsis = CTLineCreateWithAttributedString((__bridge CFAttributedStringRef)mark);
            cut = CTLineCreateTruncatedLine(whole, box.size.width, kCTLineTruncationEnd, ellipsis);
            CFRelease(whole);
            CFRelease(ellipsis);
            if (cut) x = CTLineGetPenOffsetForFlush(cut, flush, box.size.width);
        }
        CGContextSetTextPosition(context, box.origin.x + x, box.origin.y + origins[i].y);
        CTLineDraw(cut ?: line, context);
        if (cut) CFRelease(cut);
    }
}

// The words alone on a clear image the size of the clip, nil when there are none. Over moving artwork they
// carry a shadow, the dimmed lines are less dim, and the image is only the words' box, which `drawn` gets
// the place of in the clip. With `scrim` (Over the artwork on its cover kept sharp) the image carries the
// gradient behind them.
// YES with no image is an intentional rest; NO means rendering failed.
static BOOL newWords(NSString *previous, NSString *line, NSString *translation, NSString *next, CGSize size,
                     SGLyricsClipLayout layout, BOOL scrim, CGRect *drawn, CGImageRef *result) {
    *result = NULL;
    // Over the artwork keeps the line sung last above the line instead of the next, which shows only at a rest.
    if (layout == SGLyricsClipOverArtwork && line.length) next = nil;
    if (!previous.length && !line.length && !next.length) return YES;
    CGContextRef context = newContext(size, NULL, 0);
    if (!context) return NO;
    if (!line.length) translation = nil;
    if (layout == SGLyricsClipPoster) {
        // The line alone; at a rest the next one takes its place.
        previous = nil;
        if (line.length) next = nil;
    }
    CGFloat screen = size.width, width = round(screen * kColumn);
    CGFloat fontSize = size.width * kFont, lineSize = layout == SGLyricsClipPoster ? fontSize * kPosterScale : fontSize;
    CTFramesetterRef setter = NULL;
    NSAttributedString *words = nil;
    CGFloat height = 0, top = 0;
    // A long line is set smaller until the lines fit; past the smallest size they run taller, down to kLowest. Past
    // that the line sung last goes, then the next (unless it is all there is), then the translation, each time set
    // again from the full size.
    for (int step = 0; step < 4; step++) {
        if (step == 1) {
            if (!previous.length) continue;
            previous = nil;
        } else if (step == 2) {
            if (!line.length || !next.length) continue;
            next = nil;
        } else if (step == 3) {
            if (!translation.length) continue;
            translation = nil;
        }
        CGSize fits = CGSizeZero;
        for (CGFloat scale = 1; scale >= kSmallest - 0.01; scale -= 0.1) {
            if (setter) CFRelease(setter);
            words = wordsAt(previous, line, translation, next, fontSize * scale, drawn ? kMotionNextAlpha : kNextAlpha, layout);
            setter = CTFramesetterCreateWithAttributedString((__bridge CFAttributedStringRef)words);
            fits = CTFramesetterSuggestFrameSizeWithConstraints(setter, CFRangeMake(0, 0), NULL, CGSizeMake(width, CGFLOAT_MAX), NULL);
            if (fits.height <= size.height * kTallest) break;
        }
        height = ceil(fits.height) + 1;
        top = MAX(size.height * kCentreY - height / 2, size.height * kTop);
        if (top + height <= size.height * kLowest) break;
    }
    // Still too tall, the line alone keeps the whole lines that fit from kTop to kLowest, the last ending in an ellipsis.
    BOOL overflows = top + height > size.height * kLowest;
    if (overflows) {
        top = size.height * kTop;
        height = floor(size.height * (kLowest - kTop));
    }
    // Core Graphics counts up from the bottom.
    CGRect box = CGRectMake(round((size.width - screen) / 2 + screen * kMargin), round(size.height - top - height), width, height);
    CGPathRef path = CGPathCreateWithRect(box, NULL);
    CTFrameRef frame = CTFramesetterCreateFrame(setter, CFRangeMake(0, 0), path, NULL);
    if (scrim) {
        CGFloat reachX = size.width * kArtworkSideReach, reachY = height / 2 + size.width * kArtworkVerticalReach;
        uint8_t *pixels = CGBitmapContextGetData(context);
        size_t stride = CGBitmapContextGetBytesPerRow(context);
        for (size_t y = 0; y < (size_t)size.height; y++) {
            CGFloat dy = (y - (top + height / 2)) / reachY;
            for (size_t x = 0; x < (size_t)size.width; x++) {
                CGFloat dx = (x - box.origin.x) / reachX;
                CGFloat fade = exp(-(dx * dx + dy * dy));
                pixels[y * stride + x * 4 + 3] = (uint8_t)round(255 * kArtworkScrimAlpha * fade);
            }
        }
    }
    if (drawn || layout == SGLyricsClipOverArtwork) {
        CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
        CGFloat shade[] = {0, 0, 0, layout == SGLyricsClipOverArtwork ? kArtworkShadowAlpha : kShadowAlpha};
        CGColorRef color = CGColorCreate(space, shade);
        CGContextSetShadowWithColor(context, CGSizeZero, lineSize * kShadowBlur, color);
        CGColorRelease(color);
        CGColorSpaceRelease(space);
    }
    if (overflows) drawCut(frame, words, context, box, layout == SGLyricsClipCentered ? 0.5 : 0);
    else CTFrameDraw(frame, context);
    CGImageRef image = CGBitmapContextCreateImage(context);
    CGContextRelease(context);
    if (image && drawn) {
        // Out to the shadow's reach, inside the clip; an image is cut from the top, Core Graphics counts from the bottom.
        *drawn = CGRectIntersection(CGRectIntegral(CGRectInset(box, -lineSize, -lineSize)), (CGRect){CGPointZero, size});
        CGImageRef cut = CGImageCreateWithImageInRect(image, CGRectMake(drawn->origin.x, size.height - CGRectGetMaxY(*drawn),
                                                                        drawn->size.width, drawn->size.height));
        CGImageRelease(image);
        image = cut;
    }
    CFRelease(frame);
    CGPathRelease(path);
    CFRelease(setter);
    *result = image;
    return image != NULL;
}

// Messages and Vinyl paint the whole clip. Their sizes are shares of the card, the strip of the clip the lock screen
// shows: its full width W and its height H. All they draw stays between kTop and
// kLowest of the height, where the other layouts keep their words, clear of the clock and the media controls.
// Messages on black, of W: the bubbles kMessagesSide in from each side, the stack ending at kLowest. A bubble is at
// most kBubbleWidth of the stack's width, its corners kBubbleRadius round, its words kBubbleFont tall and
// kBubbleLineHeight of that apart, at most kMineLines lines of the line and kTheirsLines of the line sung last,
// kBubblePadX by kBubblePadY in, kBubbleGap from the next bubble. The typing bubble is a pill, its three dots in
// kSecondary kDot of the font size across and kDotGap of it apart.
static const uint32_t kMessagesBackground = 0x000000, kTheirs = 0x262629, kMine = 0x0A84FF, kSecondary = 0x8E8E93;
static const CGFloat kMessagesSide = 0.05;
static const CGFloat kBubbleWidth = 0.74, kBubbleRadius = 0.045, kBubbleFont = 0.05, kBubbleLineHeight = 1.3;
static const CFIndex kMineLines = 4, kTheirsLines = 2;
static const CGFloat kBubblePadX = 0.03, kBubblePadY = 0.02, kBubbleGap = 0.015, kDot = 0.3, kDotGap = 0.22;
// Vinyl on kVinylBackground, of W: a kDisc record kRecordMost across, less down to kRecordLeast when the words need
// the room, in a glow of kGlowAlpha white kGlow wide; its rim kRimAlpha white, grooves kGroove apart at kGrooveAlpha
// white from kGroovesFrom of the label out to kGroovesTo of the record, and a sheen of two wedges at kSheenAlpha
// white; the cover as its label, a circle kLabel of the record across (kLabelPlain without one), round a spindle hole
// kSpindle of it across. The words kRecordGap under it, centred in the shared kColumn: the line in italic
// serif kVinylFont tall, kVinylLineHeight of that apart (kVinylCJKLineHeight with Chinese, Japanese or Korean in it);
// the next line kVinylNextGap under it in the system font kVinylNextFont tall, kVinylNextLineHeight of that apart,
// kVinylNextAlpha white. The record and the words are centred together between kTop and kLowest, the glow inside.
static const uint32_t kVinylBackground = 0x0E0E0E, kDisc = 0x050505, kLabelPlain = 0x2A2A2C;
static const CGFloat kRecordMost = 0.6, kRecordLeast = 0.45, kRecordGap = 0.04, kLabel = 0.38, kSpindle = 0.028;
static const CGFloat kGlow = 0.04, kGlowAlpha = 0.12;
static const CGFloat kRimAlpha = 0.25, kGroove = 0.005, kGrooveAlpha = 0.05, kGroovesFrom = 1.15, kGroovesTo = 0.96, kSheenAlpha = 0.09;
static const CGFloat kVinylFont = 0.08, kVinylLineHeight = 1.2, kVinylCJKLineHeight = 1.35;
static const CGFloat kVinylNextFont = 0.046, kVinylNextLineHeight = 1.25, kVinylNextAlpha = 0.55, kVinylNextGap = 0.02;

static CGColorRef newColor(uint32_t rgb, CGFloat alpha) CF_RETURNS_RETAINED {
    CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGFloat parts[] = {(rgb >> 16 & 0xFF) / 255.0, (rgb >> 8 & 0xFF) / 255.0, (rgb & 0xFF) / 255.0, alpha};
    CGColorRef color = CGColorCreate(space, parts);
    CGColorSpaceRelease(space);
    return color;
}

static void setFill(CGContextRef context, uint32_t rgb, CGFloat alpha) {
    CGColorRef color = newColor(rgb, alpha);
    CGContextSetFillColorWithColor(context, color);
    CGColorRelease(color);
}

// `text` in `font`, white at `alpha`, its lines `lineHeight` apart, `before` under what comes before it.
static NSAttributedString *styled(NSString *text, CTFontRef font, CGFloat alpha, CGFloat lineHeight, CGFloat before,
                                  CTTextAlignment alignment) {
    CTParagraphStyleSetting settings[] = {
        {kCTParagraphStyleSpecifierMinimumLineHeight, sizeof(lineHeight), &lineHeight},
        {kCTParagraphStyleSpecifierMaximumLineHeight, sizeof(lineHeight), &lineHeight},
        {kCTParagraphStyleSpecifierParagraphSpacingBefore, sizeof(before), &before},
        {kCTParagraphStyleSpecifierAlignment, sizeof(alignment), &alignment},
    };
    CTParagraphStyleRef paragraph = CTParagraphStyleCreate(settings, sizeof(settings) / sizeof(settings[0]));
    CGColorRef color = newColor(0xFFFFFF, alpha);
    NSAttributedString *words = [[NSAttributedString alloc] initWithString:keptWhole(text) attributes:@{
        (id)kCTFontAttributeName: (__bridge id)font,
        (id)kCTParagraphStyleAttributeName: (__bridge id)paragraph,
        (id)kCTForegroundColorAttributeName: (__bridge id)color,
    }];
    CFRelease(paragraph);
    CGColorRelease(color);
    return words;
}

// The size `words` take wrapped at `width`, in whole pixels.
static CGSize sizeOf(NSAttributedString *words, CGFloat width) {
    CTFramesetterRef setter = CTFramesetterCreateWithAttributedString((__bridge CFAttributedStringRef)words);
    CGSize fits = CTFramesetterSuggestFrameSizeWithConstraints(setter, CFRangeMake(0, 0), NULL, CGSizeMake(width, CGFLOAT_MAX), NULL);
    CFRelease(setter);
    return CGSizeMake(ceil(fits.width), ceil(fits.height));
}

// `words` in `box` (Core Graphics counts up from the bottom), from its top; words running past it end in an ellipsis
// after the whole lines that fit, placed `flush` of the way across.
static void drawIn(CGContextRef context, NSAttributedString *words, CGRect box, CGFloat flush) {
    CTFramesetterRef setter = CTFramesetterCreateWithAttributedString((__bridge CFAttributedStringRef)words);
    CGPathRef path = CGPathCreateWithRect(box, NULL);
    CTFrameRef frame = CTFramesetterCreateFrame(setter, CFRangeMake(0, 0), path, NULL);
    if (CTFrameGetVisibleStringRange(frame).length < (CFIndex)words.length) drawCut(frame, words, context, box, flush);
    else CTFrameDraw(frame, context);
    CFRelease(frame);
    CGPathRelease(path);
    CFRelease(setter);
}

// Whether `text` is written right to left, by the language it reads as.
static BOOL rightToLeft(NSString *text) {
    if (!text.length) return NO;
    NSString *language = CFBridgingRelease(CFStringTokenizerCopyBestStringLanguage((__bridge CFStringRef)text, CFRangeMake(0, (CFIndex)text.length)));
    return language && [NSLocale characterDirectionForLanguage:language] == NSLocaleLanguageDirectionRightToLeft;
}

// Messages: from the top, the line sung last (theirs, on the left), the line (mine, on the right) and while a next
// line is coming the typing dots (theirs), never its words; sides swapped for words written right to left. The stack
// ends at kLowest and grows up; held to their lines the bubbles stay far below kTop at any size.
static void drawMessages(CGContextRef context, NSString *previous, NSString *line, NSString *next, CGSize size) {
    CGFloat W = size.width, H = size.height, stack = W * (1 - 2 * kMessagesSide);
    CGFloat left = (size.width - W) / 2 + W * kMessagesSide;
    CGFloat padX = W * kBubblePadX, padY = W * kBubblePadY, gap = W * kBubbleGap, inside = stack * kBubbleWidth - 2 * padX;
    setFill(context, kMessagesBackground, 1);
    CGContextFillRect(context, (CGRect){CGPointZero, size});
    BOOL flipped = rightToLeft(line.length ? line : previous.length ? previous : next);
    // 0 the line sung last, 1 the line, 2 the typing dots (no words). As Left does, the words are set smaller until
    // each bubble holds them in its lines; past the smallest size they end in an ellipsis after those.
    BOOL shown[3] = {previous.length > 0, line.length > 0, next.length > 0};
    NSString *texts[2] = {previous, line};
    const CFIndex most[2] = {kTheirsLines, kMineLines};
    NSAttributedString *words[2] = {nil, nil};
    CGSize content[3] = {CGSizeZero, CGSizeZero, CGSizeZero};
    CGFloat fontSize = 0, lineHeight = 0;
    for (CGFloat scale = 1; scale >= kSmallest - 0.01; scale -= 0.1) {
        fontSize = W * kBubbleFont * scale;
        lineHeight = fontSize * kBubbleLineHeight;
        CTFontRef font = CTFontCreateUIFontForLanguage(kCTFontUIFontSystem, fontSize, NULL);
        BOOL held = YES;
        for (int i = 0; i < 2; i++) {
            if (!shown[i]) continue;
            words[i] = styled(texts[i], font, 1, lineHeight, 0, kCTTextAlignmentNatural);
            CGSize wrapped = sizeOf(words[i], inside);
            CGFloat lines = ceil(most[i] * lineHeight);
            held = held && wrapped.height <= lines;
            content[i] = CGSizeMake(MIN(wrapped.width + 1, inside), MIN(wrapped.height, lines));
        }
        CFRelease(font);
        if (held) break;
    }
    content[2] = CGSizeMake(fontSize * (3 * kDot + 2 * kDotGap), ceil(lineHeight));
    CGSize bubbles[3];
    CGFloat tall = 0;
    for (int i = 0, count = 0; i < 3; i++) {
        if (!shown[i]) continue;
        bubbles[i] = CGSizeMake(ceil(content[i].width + 2 * padX), ceil(content[i].height + 2 * padY));
        tall += bubbles[i].height + (count++ ? gap : 0);
    }
    CGFloat y = H * kLowest - tall;   // from the top
    for (int i = 0; i < 3; i++) {
        if (!shown[i]) continue;
        BOOL onLeft = (i != 1) != flipped;
        CGRect box = CGRectMake(round(onLeft ? left : left + stack - bubbles[i].width), round(H - y - bubbles[i].height),
                                bubbles[i].width, bubbles[i].height);
        CGFloat radius = MIN(MIN(i == 2 ? box.size.height / 2 : W * kBubbleRadius, box.size.height / 2), box.size.width / 2);
        CGPathRef path = CGPathCreateWithRoundedRect(box, radius, radius, NULL);
        setFill(context, i == 1 ? kMine : kTheirs, 1);
        CGContextAddPath(context, path);
        CGContextFillPath(context);
        CGPathRelease(path);
        CGRect inner = CGRectInset(box, padX, padY);
        if (i < 2) {
            drawIn(context, words[i], inner, flipped ? 1 : 0);
        } else {
            CGFloat dot = fontSize * kDot, step = dot + fontSize * kDotGap;
            setFill(context, kSecondary, 1);
            for (int d = 0; d < 3; d++)
                CGContextFillEllipseInRect(context, CGRectMake(inner.origin.x + d * step, CGRectGetMidY(inner) - dot / 2, dot, dot));
        }
        y += bubbles[i].height + gap;
    }
}

// New York italic, the system's serif design; Georgia Italic where there is none.
static CTFontRef newSerifItalic(CGFloat size) CF_RETURNS_RETAINED {
#if TARGET_OS_IPHONE
    UIFontDescriptor *serif = [[UIFont systemFontOfSize:size].fontDescriptor fontDescriptorWithDesign:UIFontDescriptorSystemDesignSerif];
    serif = [serif fontDescriptorWithSymbolicTraits:UIFontDescriptorTraitItalic];
    id font = serif ? [UIFont fontWithDescriptor:serif size:size] : nil;
#else
    NSFontDescriptor *serif = [[NSFont systemFontOfSize:size].fontDescriptor fontDescriptorWithDesign:NSFontDescriptorSystemDesignSerif];
    serif = [serif fontDescriptorWithSymbolicTraits:NSFontDescriptorTraitItalic];
    id font = serif ? [NSFont fontWithDescriptor:serif size:size] : nil;
#endif
    return font ? (CTFontRef)CFBridgingRetain(font) : CTFontCreateWithName(CFSTR("Georgia-Italic"), size, NULL);
}

// Whether `text` has Chinese, Japanese or Korean letters in it.
static BOOL hasCJK(NSString *text) {
    for (NSUInteger i = 0; i < text.length; i++) {
        unichar c = [text characterAtIndex:i];
        if (isHangul(c) || (c >= 0x3040 && c <= 0x30FF) || (c >= 0x3400 && c <= 0x4DBF) || (c >= 0x4E00 && c <= 0x9FFF)) return YES;
    }
    return NO;
}

// Vinyl's words at `scale` of their size: the line, and the next one under it.
static NSAttributedString *vinylWords(NSString *line, NSString *next, CGFloat W, CGFloat scale) {
    NSMutableAttributedString *words = [NSMutableAttributedString new];
    if (line.length) {
        CGFloat size = W * kVinylFont * scale, lineHeight = size * (hasCJK(line) ? kVinylCJKLineHeight : kVinylLineHeight);
        CTFontRef font = newSerifItalic(size);
        [words appendAttributedString:styled(line, font, 1, lineHeight, 0, kCTTextAlignmentCenter)];
        CFRelease(font);
    }
    if (next.length) {
        CGFloat size = W * kVinylNextFont * scale;
        CTFontRef font = CTFontCreateUIFontForLanguage(kCTFontUIFontSystem, size, NULL);
        NSString *text = words.length ? [@"\n" stringByAppendingString:next] : next;
        [words appendAttributedString:styled(text, font, kVinylNextAlpha, size * kVinylNextLineHeight, words.length ? W * kVinylNextGap : 0,
                                             kCTTextAlignmentCenter)];
        CFRelease(font);
    }
    return words;
}

// Vinyl: the record, and under it the line and the next one.
static void drawVinyl(CGContextRef context, CGImageRef cover, NSString *line, NSString *next, CGSize size) {
    CGFloat W = size.width, H = size.height, middle = size.width / 2;
    CGFloat glow = round(W * kGlow), gap = round(W * kRecordGap), width = round(W * kColumn);
    // The band less the glow's reach above and below, so what is centred in it is centred in the band.
    CGFloat room = floor(H * (kLowest - kTop)) - 2 * glow;
    setFill(context, kVinylBackground, 1);
    CGContextFillRect(context, (CGRect){CGPointZero, size});
    // The record as large as it may be with the words at their full size under it. In what is left the words, as
    // Left does, are set smaller until they fit; past the smallest size the next line goes, and last the line ends in
    // an ellipsis after the whole lines that fit.
    NSAttributedString *words = vinylWords(line, next, W, 1);
    CGFloat full = words.length ? sizeOf(words, width).height + 1 + gap : 0;
    CGFloat diameter = round(MIN(MAX(room - full, W * kRecordLeast), W * kRecordMost)), wordsRoom = room - diameter - gap, tall = 0;
    for (int step = 0; step < 2 && words.length; step++) {
        if (step == 1) {
            if (!line.length || !next.length) continue;
            next = nil;
        }
        for (CGFloat scale = 1; scale >= kSmallest - 0.01; scale -= 0.1) {
            words = vinylWords(line, next, W, scale);
            tall = sizeOf(words, width).height + 1;
            if (tall <= wordsRoom) break;
        }
        if (tall <= wordsRoom) break;
    }
    tall = MIN(tall, wordsRoom);
    CGFloat block = diameter + (words.length ? gap + tall : 0), top = round(H * kTop + glow + (room - block) / 2);   // from the top
    CGFloat radius = diameter / 2, label = diameter * kLabel / 2;
    CGRect disc = CGRectMake(round(middle - radius), H - top - diameter, diameter, diameter);
    CGPoint centre = CGPointMake(CGRectGetMidX(disc), CGRectGetMidY(disc));
    CGContextSaveGState(context);
    CGColorRef halo = newColor(0xFFFFFF, kGlowAlpha);
    CGContextSetShadowWithColor(context, CGSizeZero, glow, halo);
    CGColorRelease(halo);
    setFill(context, kDisc, 1);
    CGContextFillEllipseInRect(context, disc);
    CGContextRestoreGState(context);
    CGContextSaveGState(context);
    CGContextAddEllipseInRect(context, disc);
    CGContextClip(context);
    CGColorRef groove = newColor(0xFFFFFF, kGrooveAlpha), rim = newColor(0xFFFFFF, kRimAlpha);
    CGContextSetStrokeColorWithColor(context, groove);
    CGContextSetLineWidth(context, 1);
    for (CGFloat r = label * kGroovesFrom; r < radius * kGroovesTo; r += W * kGroove)
        CGContextStrokeEllipseInRect(context, CGRectMake(centre.x - r, centre.y - r, 2 * r, 2 * r));
    CGContextSetStrokeColorWithColor(context, rim);
    CGContextSetLineWidth(context, 2);
    CGContextStrokeEllipseInRect(context, CGRectInset(disc, 1, 1));
    CGColorRelease(groove);
    CGColorRelease(rim);
    // Two soft bands of light across it, corner to corner (a linear gradient: the conic one needs iOS 17).
    CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGFloat sheen[] = {1, 1, 1, 0,  1, 1, 1, kSheenAlpha,  1, 1, 1, 0,  1, 1, 1, kSheenAlpha,  1, 1, 1, 0};
    CGFloat stops[] = {0.15, 0.3, 0.5, 0.7, 0.85};
    CGGradientRef gradient = CGGradientCreateWithColorComponents(space, sheen, stops, sizeof(stops) / sizeof(stops[0]));
    CGContextDrawLinearGradient(context, gradient, CGPointMake(CGRectGetMinX(disc), CGRectGetMaxY(disc)),
                                CGPointMake(CGRectGetMaxX(disc), CGRectGetMinY(disc)), 0);
    CGGradientRelease(gradient);
    CGColorSpaceRelease(space);
    CGContextRestoreGState(context);
    // The label: the cover cropped to its circle, about the middle.
    CGRect labelBox = CGRectMake(centre.x - label, centre.y - label, 2 * label, 2 * label);
    CGContextSaveGState(context);
    CGContextAddEllipseInRect(context, labelBox);
    CGContextClip(context);
    if (cover) {
        CGFloat w = CGImageGetWidth(cover), h = CGImageGetHeight(cover), fill = 2 * label / MIN(w, h);
        CGContextSetInterpolationQuality(context, kCGInterpolationHigh);
        CGContextDrawImage(context, CGRectMake(centre.x - w * fill / 2, centre.y - h * fill / 2, w * fill, h * fill), cover);
    } else {
        setFill(context, kLabelPlain, 1);
        CGContextFillRect(context, labelBox);
    }
    CGContextRestoreGState(context);
    CGFloat hole = diameter * kSpindle / 2;
    setFill(context, kVinylBackground, 1);
    CGContextFillEllipseInRect(context, CGRectMake(centre.x - hole, centre.y - hole, 2 * hole, 2 * hole));
    if (words.length) drawIn(context, words, CGRectMake(round(middle - width / 2), H - top - block, width, tall), 0.5);
}

// A scene's whole picture, the size of the clip.
static CGImageRef newScene(CGImageRef cover, NSString *previous, NSString *line, NSString *next, CGSize size,
                           SGLyricsClipLayout layout) CF_RETURNS_RETAINED {
    CGContextRef context = newContext(size, NULL, 0);
    if (!context) return NULL;
    if (layout == SGLyricsClipMessages) drawMessages(context, previous, line, next, size);
    else drawVinyl(context, cover, line, next, size);
    CGImageRef image = CGBitmapContextCreateImage(context);
    CGContextRelease(context);
    return image;
}

// What goes over the backdrop: a scene's picture, or the words; Over the artwork's under their scrim when it has no
// backdrop, as the cover then shows sharp.
static BOOL newPicture(CGImageRef backdrop, CGImageRef cover, NSString *previous, NSString *line, NSString *translation,
                       NSString *next, CGSize size, SGLyricsClipLayout layout, CGImageRef *picture) {
    if (SGLyricsClipIsScene(layout)) {
        *picture = newScene(cover, previous, line, next, size, layout);
        return *picture != NULL;
    }
    BOOL over = layout == SGLyricsClipOverArtwork;
    return newWords(over ? previous : nil, line, translation, next, size, layout, over && !backdrop, NULL, picture);
}

static CGImageRef newBackdrop(CGImageRef backdrop, CGImageRef cover, CGSize size, SGLyricsClipLayout layout) CF_RETURNS_RETAINED {
    if (layout == SGLyricsClipOverArtwork && !backdrop)
        return SGLyricsBackgroundCreate(cover, size, (SGLyricsBackgroundStyle){SGLyricsBackgroundCover, 0, 0, 0});
    return CGImageRetain(backdrop);
}

// A frame `phase` of the way through the loop, 0 to 1, into `context`.
static void drawFrame(CGContextRef context, CGImageRef backdrop, CGImageRef words, CGSize size, double phase) {
    CGFloat grow = kBreath * (1 - cos(2 * M_PI * phase)) / 2;
    CGRect bounds = {CGPointZero, size};
    if (backdrop) CGContextDrawImage(context, CGRectInset(bounds, -size.width * grow / 2, -size.height * grow / 2), backdrop);
    if (words) CGContextDrawImage(context, bounds, words);
}

CGImageRef SGLyricsClipFrameWithLayout(CGImageRef backdrop, CGImageRef cover, NSString *previous, NSString *line,
                                       NSString *translation, NSString *next, CGSize size, SGLyricsClipLayout layout) {
    CGImageRef words;
    if (!newPicture(backdrop, cover, previous, line, translation, next, size, layout, &words)) return NULL;
    CGImageRef background = newBackdrop(backdrop, cover, size, layout);
    CGContextRef context = newContext(size, NULL, 0);
    CGImageRef frame = NULL;
    if (context) {
        drawFrame(context, background, words, size, 0);
        frame = CGBitmapContextCreateImage(context);
        CGContextRelease(context);
    }
    CGImageRelease(words);
    CGImageRelease(background);
    return frame;
}

@interface SGLyricsWriterStatus : NSObject
@property (nonatomic, copy) dispatch_block_t failed;
@end
@implementation SGLyricsWriterStatus
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    AVAssetWriterStatus status = [(AVAssetWriter *)object status];
    if (status == AVAssetWriterStatusFailed || status == AVAssetWriterStatusCancelled) self.failed();
}
@end

// The encoder pulls only when ready. The caller remains on its worker queue until completion.
static BOOL writeReady(AVAssetWriter *writer, AVAssetWriterInput *input, CMTime length,
                       BOOL (^current)(void), NSInteger (^frame)(void)) {
    dispatch_semaphore_t complete = dispatch_semaphore_create(0);
    dispatch_queue_t queue = dispatch_queue_create("spotifyglass.lyrics.encoder", DISPATCH_QUEUE_SERIAL);
    __block BOOL finished = NO;
    dispatch_block_t fail = ^{
        if (finished) return;
        finished = YES;
        [writer cancelWriting];
        dispatch_semaphore_signal(complete);
    };
    SGLyricsWriterStatus *status = [SGLyricsWriterStatus new];
    status.failed = ^{ dispatch_async(queue, fail); };
    [writer addObserver:status forKeyPath:@"status" options:NSKeyValueObservingOptionInitial | NSKeyValueObservingOptionNew context:NULL];
    [input requestMediaDataWhenReadyOnQueue:queue usingBlock:^{
        if (finished) return;
        while (input.readyForMoreMediaData) @autoreleasepool {
            NSInteger result = (!current || current()) && writer.status == AVAssetWriterStatusWriting ? frame() : -1;
            if (result > 0) continue;
            [input markAsFinished];
            if (result < 0) {
                fail();
            } else {
                finished = YES;
                [writer endSessionAtSourceTime:length];
                [writer finishWritingWithCompletionHandler:^{ dispatch_semaphore_signal(complete); }];
            }
            return;
        }
    }];
    dispatch_semaphore_wait(complete, DISPATCH_TIME_FOREVER);
    [writer removeObserver:status forKeyPath:@"status"];
    return writer.status == AVAssetWriterStatusCompleted && (!current || current());
}

static BOOL writeLayoutPartial(NSURL *partial, CGImageRef backdrop, CGImageRef cover, NSString *previous, NSString *line,
                                 NSString *translation, NSString *next, CGSize size, SGLyricsClipStyle style,
                                 SGLyricsClipLayout layout, BOOL (^current)(void)) {
    AVAssetWriter *writer = [AVAssetWriter assetWriterWithURL:partial fileType:AVFileTypeMPEG4 error:nil];
    if (!writer) return NO;
    // A scene has no backdrop to breathe: one frame, held as long as the loop.
    int32_t frames = style == SGLyricsClipAnimated && !SGLyricsClipIsScene(layout) ? kLoopSeconds * kFPS : 1;
    CMTime length = CMTimeMake(style == SGLyricsClipAnimated ? kLoopSeconds : kStillSeconds, 1);
    AVAssetWriterInput *input = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:@{
        AVVideoCodecKey: AVVideoCodecTypeH264,
        AVVideoWidthKey: @(size.width),
        AVVideoHeightKey: @(size.height),
        // The CPU backdrop is sRGB. Explicit input/output color tagging prevents the encoder from
        // treating its samples as already Rec.709, which brightened decoded covers versus previews.
        AVVideoColorPropertiesKey: @{
            AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
            AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
            AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
        },
        AVVideoCompressionPropertiesKey: @{AVVideoAverageBitRateKey: @(2000000), AVVideoMaxKeyFrameIntervalKey: @(kFPS)},
    }];
    AVAssetWriterInputPixelBufferAdaptor *adaptor = [AVAssetWriterInputPixelBufferAdaptor assetWriterInputPixelBufferAdaptorWithAssetWriterInput:input
        sourcePixelBufferAttributes:@{
            (id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA),
            (id)kCVPixelBufferWidthKey: @(size.width),
            (id)kCVPixelBufferHeightKey: @(size.height),
        }];
    if (![writer canAddInput:input]) return NO;
    [writer addInput:input];
    if (![writer startWriting]) return NO;
    [writer startSessionAtSourceTime:kCMTimeZero];
    CGImageRef words;
    if (!newPicture(backdrop, cover, previous, line, translation, next, size, layout, &words)) {
        [writer cancelWriting];
        return NO;
    }
    CGImageRef background = newBackdrop(backdrop, cover, size, layout);
    __block int32_t i = 0;
    BOOL ok = writeReady(writer, input, length, current, ^NSInteger {
        if (i == frames) return 0;
        CVPixelBufferRef buffer = NULL;
        BOOL allocated = adaptor.pixelBufferPool
            && CVPixelBufferPoolCreatePixelBuffer(NULL, adaptor.pixelBufferPool, &buffer) == kCVReturnSuccess;
        if (!allocated) return -1;
        CVPixelBufferLockBaseAddress(buffer, 0);
        CGContextRef context = newContext(size, CVPixelBufferGetBaseAddress(buffer), CVPixelBufferGetBytesPerRow(buffer));
        if (!context) {
            CVPixelBufferUnlockBaseAddress(buffer, 0);
            CVPixelBufferRelease(buffer);
            return -1;
        }
        drawFrame(context, background, words, size, (double)i / frames);
        CGContextRelease(context);
        CVPixelBufferUnlockBaseAddress(buffer, 0);
        CVBufferSetAttachment(buffer, kCVImageBufferColorPrimariesKey, kCVImageBufferColorPrimaries_ITU_R_709_2, kCVAttachmentMode_ShouldPropagate);
        CVBufferSetAttachment(buffer, kCVImageBufferTransferFunctionKey, kCVImageBufferTransferFunction_sRGB, kCVAttachmentMode_ShouldPropagate);
        CVBufferSetAttachment(buffer, kCVImageBufferYCbCrMatrixKey, kCVImageBufferYCbCrMatrix_ITU_R_709_2, kCVAttachmentMode_ShouldPropagate);
        BOOL appended = [adaptor appendPixelBuffer:buffer withPresentationTime:CMTimeMake(i++, kFPS)];
        CVPixelBufferRelease(buffer);
        return appended ? 1 : -1;
    });
    CGImageRelease(words);
    CGImageRelease(background);
    return ok;
}

static BOOL publishClip(NSURL *file, BOOL (^writePartial)(NSURL *)) {
    NSURL *partial = [file URLByAppendingPathExtension:@"partial"];
    NSFileManager *files = NSFileManager.defaultManager;
    [files removeItemAtURL:partial error:nil];
    // A destination that appeared while encoding may already be leased to MediaPlayer.
    if (writePartial(partial) && [files moveItemAtURL:partial toURL:file error:nil]) return YES;
    [files removeItemAtURL:partial error:nil];
    return NO;
}

BOOL SGLyricsClipWriteWithLayout(NSURL *file, CGImageRef backdrop, CGImageRef cover, NSString *previous, NSString *line,
                                 NSString *translation, NSString *next, CGSize size, SGLyricsClipStyle style,
                                 SGLyricsClipLayout layout, BOOL (^current)(void)) {
    return publishClip(file, ^BOOL(NSURL *partial) {
        return writeLayoutPartial(partial, backdrop, cover, previous, line, translation, next, size, style, layout, current);
    });
}

// Over moving artwork. The video is read as BGRA, the dimming and the words are drawn into each frame where
// it lies, at the video's own size, and the exact 3:4 middle is copied into the encoder's buffer pool,
// so the picture is never scaled on the CPU: a frame costs a fill, a gradient and one image draw.

typedef struct {
    CGSize stored, cut;   // the video's size, and the 3:4 middle of it the clip keeps
    double length;        // the video's, in seconds
} Motion;

// The video's track, nil when it has none or a transform turns it.
static AVAssetTrack *motionTrack(AVURLAsset *asset, Motion *motion) {
    __block AVAssetTrack *track = nil;
    dispatch_semaphore_t loaded = dispatch_semaphore_create(0);
    [asset loadTracksWithMediaType:AVMediaTypeVideo completionHandler:^(NSArray<AVAssetTrack *> *tracks, NSError *error) {
        track = tracks.firstObject;
        dispatch_semaphore_signal(loaded);
    }];
    dispatch_semaphore_wait(loaded, DISPATCH_TIME_FOREVER);
    // shortcut: a turned video (none seen among Canvases or Apple Music's covers) falls back to the blurred
    // cover; drawing the words turned with it is the step up if one turns up.
    if (!track || !CGAffineTransformIsIdentity(track.preferredTransform)) return nil;
    // Whole pixels: the decoded frames are, and drawOver checks each against this.
    CGSize stored = CGSizeMake(round(track.naturalSize.width), round(track.naturalSize.height));
    double length = CMTimeGetSeconds(track.timeRange.duration);
    if (stored.width < 16 || stored.height < 16 || !(length > 0)) return nil;
    // A 3:4 pair of even sides has a 6x8 unit; rounding its sides independently changes the ratio.
    CGFloat units = floor(MIN(stored.width / 6, stored.height / 8));
    *motion = (Motion){stored, CGSizeMake(units * 6, units * 8), length};
    return track;
}

// The cut's place in the stored frame, which Core Graphics counts from the bottom; it is the middle, so the
// same from the top.
static CGRect cutIn(Motion motion) {
    return CGRectMake(round((motion.stored.width - motion.cut.width) / 2), round((motion.stored.height - motion.cut.height) / 2),
                      motion.cut.width, motion.cut.height);
}

// What is drawn over every frame of a clip, made once for it.
typedef struct {
    CGImageRef words;     // the words' box, NULL for none
    CGRect drawn;         // where it goes in the cut
    uint16_t *keep;       // how much of the picture each row of the cut keeps, of 256, from the top: the dimming
    CGRect soft;          // the rows behind the words, across the cut, in the stored frame; dimmed whole, the cut
    uint8_t *blurred;     // those rows blurred, NULL with no words unless dimmed whole
    uint16_t *feather;    // how much of the blurred rows each row takes, of 256, fading in and out at the top and bottom
    BOOL whole;          // Over the artwork, dimmed whole: the cut blurred and darkened evenly, words or none
} Over;

// How dark row `y` of `height` (from the top) is made: `band` across the middle 40% of the band about the
// words, kMotionDim past it, straight between.
static CGFloat dimAt(size_t y, size_t height, CGFloat band) {
    CGFloat reach = height * kBandReach, t = (y - (height * kCentreY - reach)) / (2 * reach);
    if (t <= 0 || t >= 1) return kMotionDim;
    CGFloat edge = MIN(MIN(t, 1 - t) / 0.3, 1);
    return kMotionDim + (band - kMotionDim) * edge;
}

static void setKeep(Over *over, size_t rows, CGFloat band) {
    for (size_t y = 0; y < rows; y++) over->keep[y] = (uint16_t)round(256 * (1 - dimAt(y, rows, band)));
}

static void freeOver(Over over) {
    CGImageRelease(over.words);
    free(over.keep);
    free(over.blurred);
    free(over.feather);
}

static Over makeOver(Motion motion, NSString *previous, NSString *line, NSString *translation, NSString *next,
                     SGLyricsClipLayout layout) {
    Over over = {0};
    if (!newWords(previous, line, translation, next, motion.cut, layout, NO, &over.drawn, &over.words)) return over;
    size_t rows = (size_t)motion.cut.height;
    over.keep = malloc(rows * sizeof(uint16_t));
    if (!over.keep) goto failed;
    CGRect cut = cutIn(motion);
    if (layout == SGLyricsClipOverArtwork) {
        // Blurred whole, with no edge to fade; until fitBand judges the stretch, darkened as white needs.
        over.whole = YES;
        over.soft = cut;
        size_t width = (size_t)cut.size.width;
        over.blurred = malloc(width * rows * 4);
        if (!over.blurred) goto failed;
        over.feather = malloc(rows * sizeof(uint16_t));
        if (!over.feather) goto failed;
        Lights none = {0};
        uint16_t keep = keepFor(&none);
        for (size_t y = 0; y < rows; y++) over.feather[y] = 256, over.keep[y] = keep;
        return over;
    }
    setKeep(&over, rows, kBandDim);
    if (!over.words) return over;
    // A font size past the margin newWords leaves about the words, itself a font size, and faded in over both, so
    // every line is on picture blurred whole and the blur's edge is gentle and away from them.
    CGFloat reach = round(motion.cut.width * kFont);
    over.soft = CGRectIntersection(CGRectMake(cut.origin.x, cut.origin.y + over.drawn.origin.y - reach, cut.size.width,
                                              over.drawn.size.height + 2 * reach), cut);
    size_t width = (size_t)over.soft.size.width, height = (size_t)over.soft.size.height;
    size_t fade = MAX(MIN((size_t)(2 * reach), height / 2), 1);
    over.blurred = malloc(width * height * 4);
    if (!over.blurred) goto failed;
    over.feather = malloc(height * sizeof(uint16_t));
    if (!over.feather) goto failed;
    for (size_t y = 0; y < height; y++) over.feather[y] = (uint16_t)(256 * MIN(1.0, MIN(y, height - 1 - y) / (double)fade));
    return over;
failed:
    freeOver(over);
    return (Over){0};
}

// The first of the rows behind the words in a BGRA frame of the video, `base`, at their left edge.
static uint8_t *softRows(uint8_t *base, size_t bytesPerRow, Motion motion, const Over *over) {
    // An image counts its rows from the top, Core Graphics from the bottom.
    size_t top = (size_t)(motion.stored.height - CGRectGetMaxY(over->soft));
    return base + top * bytesPerRow + (size_t)over->soft.origin.x * 4;
}

// The rows behind the words in a BGRA frame of the video, `base`, blurred (Accelerate's tent blur) and faded in.
static void soften(uint8_t *base, size_t bytesPerRow, size_t frameHeight, Motion motion, const Over *over) {
    size_t top = (size_t)(motion.stored.height - CGRectGetMaxY(over->soft)), height = (size_t)over->soft.size.height;
    size_t width = (size_t)over->soft.size.width, rowBytes = width * 4;
    uint8_t *rows = softRows(base, bytesPerRow, motion, over);
    // Accelerate's tent takes about 0.5 ms here up to 127 pixels across and some 40 times that past it.
    uint32_t kernel = MIN((uint32_t)(width * kSoftWidth) | 1, 127);
    // Read from the picture above and below the rows as far as the blur reaches, where the frame has it, so
    // their top and bottom are blurred with what is there rather than their edge drawn out.
    size_t above = MIN(kernel / 2, top), below = MIN(kernel / 2, frameHeight - top - height);
    vImage_Buffer from = {rows - above * bytesPerRow, height + above + below, width, bytesPerRow};
    vImage_Buffer to = {over->blurred, height, width, rowBytes};
    if (vImageTentConvolve_ARGB8888(&from, &to, NULL, 0, above, kernel, kernel, NULL, kvImageEdgeExtend) != kvImageNoError) return;
    for (size_t y = 0; y < height; y++) {
        uint8_t *sharp = rows + y * bytesPerRow;
        const uint8_t *soft = over->blurred + y * rowBytes;
        uint16_t share = over->feather[y];
        if (share == 256) memcpy(sharp, soft, rowBytes);
        else if (share) for (size_t i = 0; i < rowBytes; i++) sharp[i] += (uint8_t)(((soft[i] - sharp[i]) * share) >> 8);
    }
}

// The luma (Rec. 709's weights on the stored values) the brightest tenth of the softened picture behind the
// words reaches in a BGRA frame of the video, `base`.
static int lightBehind(uint8_t *base, size_t bytesPerRow, Motion motion, const Over *over) {
    const uint8_t *rows = softRows(base, bytesPerRow, motion, over);
    size_t histogram[256] = {0}, count = 0, seen = 0;
    for (size_t y = 0; y < (size_t)over->soft.size.height; y++) {
        const uint8_t *pixel = rows + y * bytesPerRow + (size_t)over->drawn.origin.x * 4;
        for (size_t x = 0; x < (size_t)over->drawn.size.width; x++, pixel += 4, count++)
            histogram[(pixel[2] * 54 + pixel[1] * 183 + pixel[0] * 19) >> 8]++;
    }
    int light = 255;
    while (light > 0 && (seen += histogram[light]) < count / 10) light--;
    return light;
}

// The band's darkness for the clip's stretch of the video, `from` seconds (taken round its length) for `seconds`,
// set in `over`: by the brightest behind the words of kBandSamples frames spread from its first to its last,
// softened as drawOver softens them. The writer and the preview both call this for the same stretch, so they
// agree. The frames come from an image generator, one decode from a key frame each; one that does not read is
// skipped, and with none the band keeps kBandDim. Dimmed whole, the cut is darkened evenly instead, by what the
// brightest pixel of those frames, blurred, needs (keepFor), as a cover dimmed whole is; with none read, as white needs.
static void fitBand(AVURLAsset *asset, Motion motion, Over *over, double from, double seconds) {
    if (!over->blurred) return;
    Lights lights = {0};
    CGRect cut = cutIn(motion);
    AVAssetImageGenerator *generator = [AVAssetImageGenerator assetImageGeneratorWithAsset:asset];
    generator.requestedTimeToleranceBefore = generator.requestedTimeToleranceAfter = kCMTimeZero;
    size_t width = (size_t)motion.stored.width, height = (size_t)motion.stored.height, bytesPerRow = width * 4;
    uint8_t *frame = malloc(bytesPerRow * height);
    double at = fmod(MAX(from, 0), motion.length), span = MAX(seconds - 1 / kMotionFPS, 0);
    int light = 0;
    for (int i = 0; frame && i < kBandSamples; i++) {
        CMTime time = CMTimeMakeWithSeconds(fmod(at + span * i / (kBandSamples - 1), motion.length), 600);
        CGImageRef image = [generator copyCGImageAtTime:time actualTime:NULL error:nil];
        if (!image) continue;
        // In the image's own color space, so its values are the decoded ones the clip's frames have.
        CGColorSpaceRef space = CGImageGetColorSpace(image);
        CGContextRef context = space && CGColorSpaceGetModel(space) == kCGColorSpaceModelRGB
            ? CGBitmapContextCreate(frame, width, height, 8, bytesPerRow, space, kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little)
            : newContext(motion.stored, frame, bytesPerRow);
        if (!context) {
            CGImageRelease(image);
            continue;
        }
        CGContextSetBlendMode(context, kCGBlendModeCopy);
        CGContextDrawImage(context, (CGRect){CGPointZero, motion.stored}, image);
        CGContextRelease(context);
        CGImageRelease(image);
        soften(frame, bytesPerRow, height, motion, over);
        if (over->whole)
            addLights(&lights, frame + (size_t)cut.origin.y * bytesPerRow + (size_t)cut.origin.x * 4, (size_t)cut.size.width,
                      (size_t)cut.size.height, bytesPerRow);
        else light = MAX(light, lightBehind(frame, bytesPerRow, motion, over));
    }
    free(frame);
    if (over->whole) {
        uint16_t keep = keepFor(&lights);
        for (size_t y = 0; y < (size_t)motion.cut.height; y++) over->keep[y] = keep;
    } else if (light) {
        setKeep(over, (size_t)motion.cut.height, MIN(MAX(1 - kBandLight * 255 / light, kBandDim), kBandDarkest));
    }
}

// The softening, the dimming and the words, drawn into `buffer`, a BGRA frame of the video: the rows behind
// the words softened, every row of the cut darkened by its share in one pass, and one image the size of the
// words. All on the CPU. NO, with the frame left as it is, for a frame of another size or format than the
// track states, so the clip is not written without its words.
static BOOL drawOver(CVPixelBufferRef buffer, Motion motion, Over *over) {
    CVPixelBufferLockBaseAddress(buffer, 0);
    uint8_t *base = CVPixelBufferGetBaseAddress(buffer);
    size_t bytesPerRow = CVPixelBufferGetBytesPerRow(buffer);
    CGRect cut = cutIn(motion);
    // Every write below is placed by the track's natural size, which the file states: a decoded frame of another
    // size or format is left as it is rather than written past its end.
    size_t frameWidth = CVPixelBufferGetWidth(buffer), frameHeight = CVPixelBufferGetHeight(buffer);
    CGRect frame = CGRectMake(0, 0, frameWidth, frameHeight);
    if (!base || CVPixelBufferIsPlanar(buffer) || CVPixelBufferGetPixelFormatType(buffer) != kCVPixelFormatType_32BGRA
        || frameWidth != (size_t)motion.stored.width || frameHeight != (size_t)motion.stored.height || bytesPerRow < frameWidth * 4
        || !CGRectContainsRect(frame, cut) || (over->blurred && !CGRectContainsRect(frame, over->soft))) {
        CVPixelBufferUnlockBaseAddress(buffer, 0);
        return NO;
    }
    if (over->blurred) soften(base, bytesPerRow, frameHeight, motion, over);
    // Blue and red, then green, each scaled in its own lane of the pixel; alpha is left as it is.
    size_t top = (size_t)cut.origin.y, width = (size_t)cut.size.width;
    for (size_t y = 0; y < (size_t)cut.size.height; y++) {
        uint32_t *pixel = (uint32_t *)(base + (top + y) * bytesPerRow) + (size_t)cut.origin.x, keep = over->keep[y];
        for (size_t x = 0; x < width; x++) {
            uint32_t v = pixel[x];
            pixel[x] = (((v & 0x00FF00FFu) * keep >> 8) & 0x00FF00FFu) | (((v & 0x0000FF00u) * keep >> 8) & 0x0000FF00u) | (v & 0xFF000000u);
        }
    }
    if (over->words) {
        CGContextRef context = newContext(motion.stored, base, bytesPerRow);
        if (!context) {
            CVPixelBufferUnlockBaseAddress(buffer, 0);
            return NO;
        }
        CGContextDrawImage(context, CGRectOffset(over->drawn, cut.origin.x, cut.origin.y), over->words);
        CGContextRelease(context);
    }
    CVPixelBufferUnlockBaseAddress(buffer, 0);
    return YES;
}

// Each frame of the video from `from` seconds (taken round its length) for `seconds`, round its end as often
// as needed, timed from 0, to `each`, which returns NO to stop. NO when a read failed.
@interface SGLyricsMotionFrames : NSObject {
    AVURLAsset *asset;
    AVAssetTrack *track;
    Motion motion;
    double at, done, due, seconds, take;
    AVAssetReader *reader;
    AVAssetReaderTrackOutput *output;
}
@property (nonatomic) BOOL failed;
- (instancetype)initWithAsset:(AVURLAsset *)value track:(AVAssetTrack *)video motion:(Motion)shape from:(double)from seconds:(double)duration;
- (CMSampleBufferRef)copyNextSample CF_RETURNS_RETAINED;
@end
@implementation SGLyricsMotionFrames
- (instancetype)initWithAsset:(AVURLAsset *)value track:(AVAssetTrack *)video motion:(Motion)shape from:(double)from seconds:(double)duration {
    if ((self = [super init])) {
        asset = value; track = video; motion = shape;
        at = fmod(MAX(from, 0), motion.length); seconds = duration;
    }
    return self;
}
- (CMSampleBufferRef)copyNextSample {
    const int32_t scale = 600;
    while (!_failed && seconds - done > 0.01) {
      if (!reader) {
        take = MIN(motion.length - at, seconds - done);
        reader = [AVAssetReader assetReaderWithAsset:asset error:nil];
        output = [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:track outputSettings:@{
            (id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA),
        }];
        // Copies, so drawing into one never touches a frame the decoder still refers to.
        output.alwaysCopiesSampleData = YES;
        if (!reader || ![reader canAddOutput:output]) { _failed = YES; return NULL; }
        [reader addOutput:output];
        reader.timeRange = CMTimeRangeMake(CMTimeMakeWithSeconds(at, scale), CMTimeMakeWithSeconds(take, scale));
        if (![reader startReading]) { _failed = YES; return NULL; }
      }
        CMSampleBufferRef sample;
        while ((sample = [output copyNextSampleBuffer])) {
            // The first frame may start before `at`; it shows from the start of this stretch.
            CMTime time = CMTimeMakeWithSeconds(done + MAX(CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sample)) - at, 0), scale);
            CMSampleBufferRef timed = NULL;
            CMSampleTimingInfo timing = {kCMTimeInvalid, time, kCMTimeInvalid};
            BOOL keep = CMTimeGetSeconds(time) >= due - 0.002 && CMTimeGetSeconds(time) < done + take
                && CMSampleBufferGetImageBuffer(sample)
                && CMSampleBufferCreateCopyWithNewTiming(NULL, sample, 1, &timing, &timed) == noErr;
            CFRelease(sample);
            if (!keep) continue;
            // A jump in the video (its loop) starts the schedule again rather than keeping a burst of frames.
            due = due + 1.0 / kMotionFPS < CMTimeGetSeconds(time) ? CMTimeGetSeconds(time) + 0.5 / kMotionFPS : due + 1.0 / kMotionFPS;
            return timed;
        }
        if (reader.status != AVAssetReaderStatusCompleted) { _failed = YES; return NULL; }
        reader = nil; output = nil;
        done += take;
        at = 0;
    }
    return NULL;
}
- (void)dealloc { [reader cancelReading]; }
@end

static BOOL eachFrame(AVURLAsset *asset, AVAssetTrack *track, Motion motion, double from, double seconds,
                      BOOL (^each)(CMSampleBufferRef sample)) {
    SGLyricsMotionFrames *frames = [[SGLyricsMotionFrames alloc] initWithAsset:asset track:track motion:motion from:from seconds:seconds];
    CMSampleBufferRef sample;
    while ((sample = [frames copyNextSample])) {
        BOOL more = each(sample);
        CFRelease(sample);
        if (!more) break;
    }
    return !frames.failed;
}

CGImageRef SGLyricsClipMotionFrame(NSURL *motionFile, NSString *previous, NSString *line, NSString *translation, NSString *next,
                                   double from, double seconds, SGLyricsClipLayout layout) {
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:motionFile options:nil];
    Motion motion;
    AVAssetTrack *track = motionTrack(asset, &motion);
    if (!track) return NULL;
    __block Over over = makeOver(motion, previous, line, translation, next, layout);
    // As the clip judges its band.
    if (!over.keep) return NULL;
    fitBand(asset, motion, &over, from, MIN(seconds, motion.length));
    __block CGImageRef frame = NULL;
    eachFrame(asset, track, motion, from, motion.length, ^BOOL(CMSampleBufferRef sample) {
        CVPixelBufferRef buffer = CMSampleBufferGetImageBuffer(sample);
        if (!drawOver(buffer, motion, &over)) return NO;
        CVPixelBufferLockBaseAddress(buffer, kCVPixelBufferLock_ReadOnly);
        CGContextRef context = newContext(motion.stored, CVPixelBufferGetBaseAddress(buffer), CVPixelBufferGetBytesPerRow(buffer));
        CGImageRef whole = context ? CGBitmapContextCreateImage(context) : NULL;
        if (context) CGContextRelease(context);
        CVPixelBufferUnlockBaseAddress(buffer, kCVPixelBufferLock_ReadOnly);
        if (!whole) return NO;
        frame = CGImageCreateWithImageInRect(whole, cutIn(motion));
        CGImageRelease(whole);
        return NO;
    });
    freeOver(over);
    return frame;
}

static BOOL writeMotionPartial(NSURL *partial, NSURL *motionFile, NSString *previous, NSString *line, NSString *translation,
                                 NSString *next, double from, double seconds, SGLyricsClipLayout layout, BOOL (^current)(void)) {
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:motionFile options:nil];
    Motion motion;
    AVAssetTrack *track = motionTrack(asset, &motion);
    if (!track) return NO;
    // No longer than the video, which is then written whole and loops as it was made to.
    seconds = MIN(seconds, motion.length);
    AVAssetWriter *writer = [AVAssetWriter assetWriterWithURL:partial fileType:AVFileTypeMPEG4 error:nil];
    AVAssetWriterInput *input = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:@{
        AVVideoCodecKey: AVVideoCodecTypeH264,
        AVVideoWidthKey: @(motion.cut.width),
        AVVideoHeightKey: @(motion.cut.height),
        // As SGMotionClip.m's cut: about 2 Mbit/s at a Canvas's 720 x 960.
        AVVideoCompressionPropertiesKey: @{AVVideoAverageBitRateKey: @(motion.cut.width * motion.cut.height * 3)},
    }];
    if (!writer || ![writer canAddInput:input]) return NO;
    [writer addInput:input];
    AVAssetWriterInputPixelBufferAdaptor *adaptor = [AVAssetWriterInputPixelBufferAdaptor
        assetWriterInputPixelBufferAdaptorWithAssetWriterInput:input sourcePixelBufferAttributes:@{
            (id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA),
            (id)kCVPixelBufferWidthKey: @(motion.cut.width),
            (id)kCVPixelBufferHeightKey: @(motion.cut.height),
            (id)kCVPixelBufferIOSurfacePropertiesKey: @{},
        }];
    if (![writer startWriting]) return NO;
    [writer startSessionAtSourceTime:kCMTimeZero];
    __block Over over = makeOver(motion, previous, line, translation, next, layout);
    if (!over.keep) {
        [writer cancelWriting];
        return NO;
    }
    fitBand(asset, motion, &over, from, seconds);
    __block BOOL any = NO;
    SGLyricsMotionFrames *frames = [[SGLyricsMotionFrames alloc] initWithAsset:asset track:track motion:motion from:from seconds:seconds];
    BOOL ok = writeReady(writer, input, CMTimeMakeWithSeconds(seconds, 600), current, ^NSInteger {
        CMSampleBufferRef sample = [frames copyNextSample];
        if (!sample) return frames.failed || !any ? -1 : 0;
        CVPixelBufferRef buffer = CMSampleBufferGetImageBuffer(sample);
        if (!drawOver(buffer, motion, &over)) {
            CFRelease(sample);
            return -1;
        }
        // Aspect-fill would scale the complete stored frame when both crop dimensions shrink,
        // shifting the already-drawn letters relative to the preview. Submit precisely its crop instead.
        CGRect cut = cutIn(motion);
        CVPixelBufferRef cropped = NULL;
        if (writer.status != AVAssetWriterStatusWriting || !adaptor.pixelBufferPool
            || CVPixelBufferPoolCreatePixelBuffer(NULL, adaptor.pixelBufferPool, &cropped) != kCVReturnSuccess) {
            CFRelease(sample);
            return -1;
        }
        // Pool storage is aligned and IOSurface-backed, unlike a borrowed, offset view of the decoder's bytes.
        CVPixelBufferLockBaseAddress(buffer, kCVPixelBufferLock_ReadOnly);
        CVPixelBufferLockBaseAddress(cropped, 0);
        size_t sourceStride = CVPixelBufferGetBytesPerRow(buffer), targetStride = CVPixelBufferGetBytesPerRow(cropped);
        const uint8_t *source = CVPixelBufferGetBaseAddress(buffer);
        source += (size_t)cut.origin.y * sourceStride + (size_t)cut.origin.x * 4;
        uint8_t *target = CVPixelBufferGetBaseAddress(cropped);
        for (size_t y = 0; y < (size_t)cut.size.height; y++)
            memcpy(target + y * targetStride, source + y * sourceStride, (size_t)cut.size.width * 4);
        CVPixelBufferUnlockBaseAddress(cropped, 0);
        CVPixelBufferUnlockBaseAddress(buffer, kCVPixelBufferLock_ReadOnly);
        CFStringRef const colorKeys[] = {kCVImageBufferColorPrimariesKey, kCVImageBufferTransferFunctionKey,
                                        kCVImageBufferYCbCrMatrixKey};
        for (NSUInteger i = 0; i < sizeof(colorKeys) / sizeof(colorKeys[0]); i++) {
            CVAttachmentMode mode;
            CFTypeRef value = CVBufferCopyAttachment(buffer, colorKeys[i], &mode);
            if (value) {
                CVBufferSetAttachment(cropped, colorKeys[i], value, mode);
                CFRelease(value);
            } else {
                CVBufferRemoveAttachment(cropped, colorKeys[i]);
            }
        }
        BOOL appended = writer.status == AVAssetWriterStatusWriting
            && [adaptor appendPixelBuffer:cropped withPresentationTime:CMSampleBufferGetPresentationTimeStamp(sample)];
        CVPixelBufferRelease(cropped);
        CFRelease(sample);
        any = YES;
        return appended ? 1 : -1;
    });
    freeOver(over);
    return ok;
}

BOOL SGLyricsClipWriteOverMotion(NSURL *file, NSURL *motionFile, NSString *previous, NSString *line, NSString *translation,
                                 NSString *next, double from, double seconds, SGLyricsClipLayout layout, BOOL (^current)(void)) {
    return publishClip(file, ^BOOL(NSURL *partial) {
        return writeMotionPartial(partial, motionFile, previous, line, translation, next, from, seconds, layout, current);
    });
}

NSString *SGLyricsClipLook(NSURL *motion, SGLyricsClipStyle style, SGLyricsClipLayout layout, BOOL dimmed) {
    NSString *dim = dimmed ? @"d" : @"";
    if (!motion) return [NSString stringWithFormat:@"%@-%ldl%ld%@", kRenderVersion, (long)style, (long)layout, dim];
    NSString *name = motion.lastPathComponent.stringByDeletingPathExtension;
    return [NSString stringWithFormat:@"%@-m%@s%ldl%ld%@", kRenderVersion, name.length > 16 ? [name substringToIndex:16] : name, (long)style,
            (long)layout, dim];
}
