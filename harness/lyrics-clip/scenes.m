// Messages and Vinyl (SGLyricsClipIsScene) through the tweak's own SGLyricsClip.m. Every fixture's preview frame is
// saved as <layout>-<fixture>.png and checked against the spec's numbers (notes/cleanroom-specs/chroma-plus/
// lockscreen-layouts.md, as revised by the review), written here independently of SGLyricsClip.m; each layout's clip
// is also written and read back. `build/lyrics-clip scenes` runs these alone.
#import <AVFoundation/AVFoundation.h>
#import <ImageIO/ImageIO.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import "Shared/LockScreenLyrics/SGLyricsClip.h"

static int failures;

static void check(BOOL ok, NSString *what) {
    printf("  %s %s\n", ok ? "ok  " : "FAIL", what.UTF8String);
    if (!ok) failures++;
}

// The whole 3:4 card is shown across the screen, its top 10% down. Independent screen-space expectations.
static const CGFloat kCardOfWidth = 1;
static const CGFloat kBandTop = (.17 - .10) / (1179.0 / 2556 * 4 / 3);
static const CGFloat kBandBottom = (.65 - .10) / (1179.0 / 2556 * 4 / 3);
static const uint32_t kBlack = 0x000000, kTheirs = 0x262629, kMine = 0x0A84FF, kVinylGround = 0x0E0E0E, kDisc = 0x050505;
// Messages, of W: bubbles 4.5% round, words 5% tall at 1.3 line height, set down to 0.6 of that, 2% padding above and
// below; at most 4 lines of the line, 2 of the line sung last.
static const CGFloat kRadius = 0.045, kFont = 0.05, kLineHeight = 1.3, kSmallest = 0.6, kPadY = 0.02;
static const int kMineLines = 4, kTheirsLines = 2;
// Vinyl, of W: the record 60% across, down to 45% for words that need the room, the label 19% of a 50% record, the
// words 4% under it, the line 8% tall at 1.2 line height (1.35 with CJK), the next line 55% white, the rim 25% white
// over the near-black disc.
static const CGFloat kRecordMost = 0.6, kRecordLeast = 0.45, kLabelOfRecord = 0.19 / 0.5, kWordsGap = 0.04, kLineFont = 0.08;
static const CGFloat kVinylLineHeight = 1.2, kCJKLineHeight = 1.35, kNextWhite = 0.55, kRimWhite = 0.25;

static void savePNG(CGImageRef image, NSURL *url) {
    CGImageDestinationRef destination = CGImageDestinationCreateWithURL((__bridge CFURLRef)url, (__bridge CFStringRef)UTTypePNG.identifier, 1, NULL);
    CGImageDestinationAddImage(destination, image, NULL);
    CGImageDestinationFinalize(destination);
    CFRelease(destination);
}

// The image as sRGB RGBA bytes, rows from the top.
static NSData *rgba(CGImageRef image) {
    size_t width = CGImageGetWidth(image), height = CGImageGetHeight(image);
    NSMutableData *data = [NSMutableData dataWithLength:width * height * 4];
    CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGContextRef context = CGBitmapContextCreate(data.mutableBytes, width, height, 8, width * 4, space, (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
    CGContextDrawImage(context, CGRectMake(0, 0, width, height), image);
    CGContextRelease(context);
    CGColorSpaceRelease(space);
    return data;
}

static uint32_t rgbOf(const uint8_t *p) { return (uint32_t)p[0] << 16 | (uint32_t)p[1] << 8 | p[2]; }
static int brightOf(uint32_t rgb) { return MAX((int)(rgb >> 16 & 0xFF), MAX((int)(rgb >> 8 & 0xFF), (int)(rgb & 0xFF))); }

// The box, from the top left, of the pixels `pick` takes; CGRectNull for none.
static CGRect boundsOf(CGImageRef image, BOOL (^pick)(uint32_t rgb, size_t x, size_t y)) {
    size_t width = CGImageGetWidth(image), height = CGImageGetHeight(image);
    NSData *data = rgba(image);
    const uint8_t *bytes = data.bytes;
    size_t minX = width, maxX = 0, minY = height, maxY = 0;
    for (size_t y = 0; y < height; y++)
        for (size_t x = 0; x < width; x++) {
            if (!pick(rgbOf(bytes + (y * width + x) * 4), x, y)) continue;
            minX = MIN(minX, x), maxX = MAX(maxX, x), minY = MIN(minY, y), maxY = MAX(maxY, y);
        }
    return minX > maxX ? CGRectNull : CGRectMake(minX, minY, maxX - minX + 1, maxY - minY + 1);
}

// The runs of rows, from the top, in which `pick` takes a pixel, each as the box of the pixels it takes there.
static NSArray<NSValue *> *runsOf(CGImageRef image, BOOL (^pick)(uint32_t rgb, size_t x, size_t y)) {
    size_t width = CGImageGetWidth(image), height = CGImageGetHeight(image);
    NSData *data = rgba(image);
    const uint8_t *bytes = data.bytes;
    NSMutableArray *runs = [NSMutableArray array];
    size_t minX = width, maxX = 0, start = 0;
    BOOL open = NO;
    for (size_t y = 0; y <= height; y++) {
        BOOL any = NO;
        for (size_t x = 0; y < height && x < width; x++) {
            if (!pick(rgbOf(bytes + (y * width + x) * 4), x, y)) continue;
            any = YES;
            minX = MIN(minX, x), maxX = MAX(maxX, x);
        }
        if (any && !open) open = YES, start = y;
        if (!any && open) {
            [runs addObject:[NSValue valueWithRect:CGRectMake(minX, start, maxX - minX + 1, y - start)]];
            open = NO, minX = width, maxX = 0;
        }
    }
    return runs;
}

// How many pixels in rows `from` to `to` (shares of the height, from the top) are not `rgb`.
static size_t offColour(CGImageRef image, CGFloat from, CGFloat to, uint32_t rgb) {
    size_t width = CGImageGetWidth(image), height = CGImageGetHeight(image), off = 0;
    NSData *data = rgba(image);
    const uint8_t *bytes = data.bytes;
    // Classify by pixel centres. Mapping screen fractions gives non-integral frame boundaries;
    // floor/ceil of both ends used to count an inside edge row as outside too.
    for (size_t y = (size_t)ceil(from * height - .5); y < (size_t)ceil(to * height - .5) && y < height; y++)
        for (size_t x = 0; x < width; x++) off += rgbOf(bytes + (y * width + x) * 4) != rgb;
    return off;
}

static size_t countIn(CGImageRef image, CGRect box, uint32_t rgb) {
    size_t width = CGImageGetWidth(image), count = 0;
    NSData *data = rgba(image);
    const uint8_t *bytes = data.bytes;
    for (size_t y = (size_t)CGRectGetMinY(box); y < (size_t)CGRectGetMaxY(box); y++)
        for (size_t x = (size_t)CGRectGetMinX(box); x < (size_t)CGRectGetMaxX(box); x++) count += rgbOf(bytes + (y * width + x) * 4) == rgb;
    return count;
}

static CGRect colourBounds(CGImageRef image, uint32_t rgb) {
    return boundsOf(image, ^BOOL(uint32_t c, size_t x, size_t y) { return c == rgb; });
}

// The area of `box` a shape filled with `rgb` over black covers, from how bright each pixel is against it; words or
// dots inside it count as covered.
static double coverage(NSData *data, size_t width, CGRect box, uint32_t rgb) {
    const uint8_t *bytes = data.bytes;
    double area = 0, full = brightOf(rgb);
    for (size_t y = (size_t)CGRectGetMinY(box); y < (size_t)CGRectGetMaxY(box); y++)
        for (size_t x = (size_t)CGRectGetMinX(box); x < (size_t)CGRectGetMaxX(box); x++)
            area += MIN(brightOf(rgbOf(bytes + (y * width + x) * 4)) / full, 1.0);
    return area;
}

// The box of the pixels where `a` and `b` differ, and in `brightest` the highest channel among them in `a`.
static CGRect differ(CGImageRef a, CGImageRef b, int *brightest) {
    size_t width = CGImageGetWidth(a), height = CGImageGetHeight(a);
    NSData *da = rgba(a), *db = rgba(b);
    const uint8_t *pa = da.bytes, *pb = db.bytes;
    size_t minX = width, maxX = 0, minY = height, maxY = 0;
    int light = 0;
    for (size_t y = 0; y < height; y++)
        for (size_t x = 0; x < width; x++) {
            const uint8_t *p = pa + (y * width + x) * 4, *q = pb + (y * width + x) * 4;
            if (rgbOf(p) == rgbOf(q)) continue;
            minX = MIN(minX, x), maxX = MAX(maxX, x), minY = MIN(minY, y), maxY = MAX(maxY, y);
            light = MAX(light, brightOf(rgbOf(p)));
        }
    if (brightest) *brightest = light;
    return minX > maxX ? CGRectNull : CGRectMake(minX, minY, maxX - minX + 1, maxY - minY + 1);
}

static BOOL same(CGImageRef a, CGImageRef b) {
    return CGImageGetWidth(a) == CGImageGetWidth(b) && CGImageGetHeight(a) == CGImageGetHeight(b) && CGRectIsNull(differ(a, b, NULL));
}

static NSString *none(NSString *text) { return text.length ? text : nil; }

static CGSize size;

static CGImageRef frameOf(SGLyricsClipLayout layout, CGImageRef cover, NSString *previous, NSString *line, NSString *translation,
                          NSString *next) CF_RETURNS_RETAINED {
    CGImageRef frame = SGLyricsClipFrameWithLayout(NULL, cover, none(previous), none(line), none(translation), none(next), size, layout);
    check(frame && CGImageGetWidth(frame) == size.width && CGImageGetHeight(frame) == size.height
          && CGImageGetWidth(frame) * 4 == CGImageGetHeight(frame) * 3,
          @"scene preview matches the exact 3:4 clip raster");
    return frame;
}

// The clip written and read back: its length, size, codec and its one frame, held, clear under the band.
static void readBack(NSURL *url, SGLyricsClipStyle style, uint32_t ground) {
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:url options:@{AVURLAssetPreferPreciseDurationAndTimingKey: @YES}];
    AVAssetTrack *track = [asset tracksWithMediaType:AVMediaTypeVideo].firstObject;
    double seconds = CMTimeGetSeconds(asset.duration), wanted = style == SGLyricsClipAnimated ? 4 : 2;
    int samples = 0;
    if (track) {
        AVAssetReader *reader = [AVAssetReader assetReaderWithAsset:asset error:nil];
        AVAssetReaderTrackOutput *output = [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:track outputSettings:nil];
        [reader addOutput:output];
        [reader startReading];
        CMSampleBufferRef sample;
        while ((sample = [output copyNextSampleBuffer])) {
            if (CMSampleBufferGetNumSamples(sample)) samples++;
            CFRelease(sample);
        }
    }
    FourCharCode codec = track ? CMFormatDescriptionGetMediaSubType((__bridge CMFormatDescriptionRef)track.formatDescriptions.firstObject) : 0;
    check(track && fabs(seconds - wanted) < 0.05 && CGSizeEqualToSize(track.naturalSize, size)
          && track.naturalSize.width * 4 == track.naturalSize.height * 3 && codec == kCMVideoCodecType_H264 && samples == 1,
          [NSString stringWithFormat:@"the clip reads back: %.2f s (want %.0f), %.0fx%.0f, %d frames (want 1, held)", seconds, wanted,
           track.naturalSize.width, track.naturalSize.height, samples]);
    AVAssetImageGenerator *generator = [AVAssetImageGenerator assetImageGeneratorWithAsset:asset];
    generator.requestedTimeToleranceBefore = generator.requestedTimeToleranceAfter = kCMTimeZero;
    CGImageRef first = [generator copyCGImageAtTime:kCMTimeZero actualTime:NULL error:nil];
    if (!first) {
        check(NO, @"the clip's first frame reads back");
        return;
    }
    // The encoder's loss moves the field by a few levels.
    NSData *data = rgba(first);
    const uint8_t *bytes = data.bytes;
    size_t width = CGImageGetWidth(first), height = CGImageGetHeight(first), from = (size_t)ceil(kBandBottom * height);
    int light = 0;
    for (size_t y = from; y < height; y++)
        for (size_t x = 0; x < width; x++) light = MAX(light, brightOf(rgbOf(bytes + (y * width + x) * 4)));
    check(light <= brightOf(ground) + 10, [NSString stringWithFormat:@"the clip's first frame is clear under the band (brightest %d)", light]);
    CGImageRelease(first);
}

int scenesMain(NSURL *out, CGImageRef cover) {
    failures = 0;
    size = SGLyricsClipSize(1206);
    CGFloat W = size.width * kCardOfWidth, H = size.height, cardLeft = (size.width - W) / 2;
    NSString *translation = @"조금만 버텨, 거의 다 왔어";
    NSString *before = @"I left the light on in the hall", *line = @"Hold on, we're almost there", *next = @"until the morning finds us";
    NSString *otherNext = @"Something else entirely, and much longer than the line it replaces would ever be";
    NSString *longLatin = [@"" stringByPaddingToLength:600 withString:@"Every word I never said keeps ringing out across the quiet night, " startingAtIndex:0];
    NSArray *rtl = @[@"rtl", @"كنت أنتظرك طوال الليل", @"تمسّك، نحن على وشك الوصول", @"حتى يجدنا الصباح"];
    // name, the line sung last, the line, the next
    NSArray *fixtures = @[
        @[@"full", before, line, next],
        @[@"no-previous", @"", line, next],
        @[@"no-next", before, line, @""],
        @[@"long-latin", before, longLatin, next],
        @[@"long-cjk", before, [@"" stringByPaddingToLength:300 withString:@"夜空に光る星を数えながら君の名前を何度も呼んだ、" startingAtIndex:0], next],
        rtl,
        @[@"emoji", before, @"Dancing in the rain 💃🌧️ all night long 🎶✨", next],
        @[@"no-cover", before, line, next],
    ];
    SGLyricsClipLayout layouts[] = {SGLyricsClipMessages, SGLyricsClipVinyl};
    for (int l = 0; l < 2; l++) {
        SGLyricsClipLayout layout = layouts[l];
        NSString *name = layout == SGLyricsClipMessages ? @"messages" : @"vinyl";
        uint32_t ground = layout == SGLyricsClipMessages ? kBlack : kVinylGround;
        for (NSArray *f in fixtures) @autoreleasepool {
            BOOL coverless = [f[0] isEqual:@"no-cover"];
            if (coverless && layout == SGLyricsClipMessages) continue;   // Messages never draws the cover
            CGImageRef image = frameOf(layout, coverless ? NULL : cover, f[1], f[2], translation, f[3]);
            NSString *file = [NSString stringWithFormat:@"%@-%@.png", name, f[0]];
            savePNG(image, [out URLByAppendingPathComponent:file]);
            printf("%s\n", file.UTF8String);
            size_t high = offColour(image, 0, kBandTop, ground), low = offColour(image, kBandBottom, 1, ground);
            check(high == 0, [NSString stringWithFormat:@"nothing drawn above 17%% of the screen (the clock) (%zu pixels)", high]);
            check(low == 0, [NSString stringWithFormat:@"nothing drawn below 65%% of the screen (the controls) (%zu pixels)", low]);
            check(offColour(image, kBandTop, kBandBottom, ground) > 0, @"something drawn between them");
            if (layout == SGLyricsClipMessages)
                check(colourBounds(image, kMine).size.width > 0, @"the line in a #0A84FF bubble");
            CGImageRelease(image);
        }
        for (SGLyricsClipStyle style = SGLyricsClipStill; style <= SGLyricsClipAnimated; style++) {
            NSString *file = [NSString stringWithFormat:@"%@-full-%@.mp4", name, style == SGLyricsClipStill ? @"still" : @"animated"];
            NSURL *url = [out URLByAppendingPathComponent:file];
            printf("%s\n", file.UTF8String);
            BOOL written = SGLyricsClipWriteWithLayout(url, NULL, cover, before, line, translation, next, size, style, layout, nil);
            check(written, @"written");
            if (written) readBack(url, style, ground);
        }
    }

    printf("messages\n");
    {
        SGLyricsClipLayout m = SGLyricsClipMessages;
        CGFloat stackLeft = cardLeft + 0.05 * W, stackRight = cardLeft + 0.95 * W, widest = 0.74 * 0.9 * W;
        BOOL (^drawn)(uint32_t, size_t, size_t) = ^BOOL(uint32_t c, size_t x, size_t y) { return c != kBlack; };
        CGImageRef full = frameOf(m, cover, before, line, nil, next);
        CGImageRef other = frameOf(m, cover, before, line, nil, otherNext);
        check(same(full, other), @"the next line's words never show: another next line draws the same frame");
        CGImageRef rtlFull = frameOf(m, cover, rtl[1], rtl[2], nil, rtl[3]);
        CGImageRef rtlOther = frameOf(m, cover, rtl[1], rtl[2], nil, otherNext);
        check(same(rtlFull, rtlOther), @"the next line's words never show, right to left either");
        CGImageRef plain = frameOf(m, NULL, before, line, nil, next);
        CGImageRef told = frameOf(m, cover, before, line, translation, next);
        check(same(full, plain) && same(full, told), @"the cover and the translation are not drawn");
        CGRect mine = colourBounds(full, kMine), theirs = colourBounds(full, kTheirs);
        check(fabs(CGRectGetMaxX(mine) - stackRight) <= 1.5 && CGRectGetMinX(mine) > stackLeft + 0.1 * W
              && fabs(CGRectGetMinX(theirs) - stackLeft) <= 1.5 && CGRectGetMaxX(theirs) < stackRight - 0.1 * W
              && CGRectGetMaxY(theirs) > CGRectGetMaxY(mine) && CGRectGetMinY(theirs) < CGRectGetMinY(mine),
              [NSString stringWithFormat:@"the line sung last on the left above the line, on the right (blue %.0f to %.0f, grey %.0f to %.0f; "
               "stack %.0f to %.0f)", CGRectGetMinX(mine), CGRectGetMaxX(mine), CGRectGetMinX(theirs), CGRectGetMaxX(theirs), stackLeft, stackRight]);
        CGRect rtlMine = colourBounds(rtlFull, kMine), rtlTheirs = colourBounds(rtlFull, kTheirs);
        check(fabs(CGRectGetMinX(rtlMine) - stackLeft) <= 1.5 && fabs(CGRectGetMaxX(rtlTheirs) - stackRight) <= 1.5
              && CGRectGetMinX(rtlTheirs) > stackLeft + 0.1 * W,
              [NSString stringWithFormat:@"mirrored right to left (blue %.0f to %.0f, grey %.0f to %.0f)", CGRectGetMinX(rtlMine),
               CGRectGetMaxX(rtlMine), CGRectGetMinX(rtlTheirs), CGRectGetMaxX(rtlTheirs)]);
        CGImageRef lone = frameOf(m, cover, nil, line, nil, nil);
        CGImageRef typing = frameOf(m, cover, nil, line, nil, next);
        CGRect dots = colourBounds(typing, kTheirs), above = colourBounds(typing, kMine);
        size_t loneGrey = countIn(lone, (CGRect){CGPointZero, size}, kTheirs), typingGrey = countIn(typing, (CGRect){CGPointZero, size}, kTheirs);
        check(loneGrey == 0 && typingGrey > 0 && CGRectGetMinY(dots) > CGRectGetMaxY(above),
              [NSString stringWithFormat:@"no typing bubble without a next line, one under the line with it (%zu grey pixels; with one %zu)",
               loneGrey, typingGrey]);
        CGRect all = boundsOf(full, drawn);
        check(fabs(CGRectGetMaxY(all) - kBandBottom * H) <= 1.5,
              [NSString stringWithFormat:@"the bubbles end at 65%% of the screen (at %.0f, want %.0f)", CGRectGetMaxY(all), kBandBottom * H]);
        NSArray<NSValue *> *bubbles = runsOf(full, drawn);
        BOOL onlyBubbles = bubbles.count == 3;
        for (NSValue *b in bubbles) onlyBubbles = onlyBubbles && countIn(full, b.rectValue, kTheirs) + countIn(full, b.rectValue, kMine) > 0;
        check(onlyBubbles, [NSString stringWithFormat:@"nothing but the three bubbles drawn, no heading (%lu runs of rows)", (unsigned long)bubbles.count]);
        if (bubbles.count == 3) {
            NSData *pixels = rgba(full);
            CGFloat side = ceil(kRadius * W) + 2;
            uint32_t fills[3] = {kTheirs, kMine, kTheirs};
            NSMutableString *corners = [NSMutableString string];
            BOOL uniform = YES;
            for (int i = 0; i < 3; i++) {
                CGRect b = bubbles[i].rectValue;
                double c[4];
                for (int k = 0; k < 4; k++)
                    c[k] = coverage(pixels, (size_t)size.width, CGRectMake(k % 2 ? CGRectGetMaxX(b) - side : CGRectGetMinX(b),
                                                                           k / 2 ? CGRectGetMaxY(b) - side : CGRectGetMinY(b), side, side), fills[i]);
                double lo = MIN(MIN(c[0], c[1]), MIN(c[2], c[3])), hi = MAX(MAX(c[0], c[1]), MAX(c[2], c[3]));
                uniform = uniform && hi - lo <= 2;
                [corners appendFormat:@"%s%.0f to %.0f", i ? "; " : "", lo, hi];
            }
            check(uniform, [NSString stringWithFormat:@"every bubble's four corners round alike (covered of each corner: %@)", corners]);
            CGRect pill = bubbles[2].rectValue;
            double area = coverage(pixels, (size_t)size.width, pill, kTheirs);
            double want = pill.size.width * pill.size.height - (4 - M_PI) * pow(pill.size.height / 2, 2);
            check(fabs(area - want) <= 15, [NSString stringWithFormat:@"the typing bubble a pill (%.0f px covered, want %.0f)", area, want]);
        }
        CGFloat smallest = kFont * kSmallest * W * kLineHeight;
        CGFloat mineTall = ceil(ceil(kMineLines * smallest) + 2 * kPadY * W), theirsTall = ceil(ceil(kTheirsLines * smallest) + 2 * kPadY * W);
        CGImageRef longLine = frameOf(m, cover, before, longLatin, nil, next);
        NSArray<NSValue *> *longRuns = runsOf(longLine, drawn);
        CGFloat longMine = longRuns.count == 3 ? longRuns[1].rectValue.size.height : 0;
        check(fabs(longMine - mineTall) <= 2, [NSString stringWithFormat:@"a long line set at 0.6 of the size holds 4 lines (%.0f tall, want %.0f)",
                                               longMine, mineTall]);
        CGImageRef longBoth = frameOf(m, cover, longLatin, longLatin, nil, next);
        NSArray<NSValue *> *bothRuns = runsOf(longBoth, drawn);
        CGFloat longTheirs = bothRuns.count == 3 ? bothRuns[0].rectValue.size.height : 0;
        check(fabs(longTheirs - theirsTall) <= 2,
              [NSString stringWithFormat:@"a long line sung last holds 2 lines (%.0f tall, want %.0f)", longTheirs, theirsTall]);
        CGImageRef longAlone = frameOf(m, cover, nil, longLatin, nil, nil);
        CGRect longBlue = colourBounds(longAlone, kMine);
        check(CGRectGetWidth(longBlue) <= widest + 1.5 && CGRectGetWidth(longBlue) >= widest * 0.9,
              [NSString stringWithFormat:@"a bubble is at most 74%% of the stack wide (%.0f, want up to %.0f)", CGRectGetWidth(longBlue), widest]);
        CGImageRelease(full); CGImageRelease(other); CGImageRelease(rtlFull); CGImageRelease(rtlOther); CGImageRelease(plain);
        CGImageRelease(told); CGImageRelease(lone); CGImageRelease(typing); CGImageRelease(longLine); CGImageRelease(longBoth);
        CGImageRelease(longAlone);
    }

    printf("vinyl\n");
    {
        SGLyricsClipLayout v = SGLyricsClipVinyl;
        // The record is the first run of rows brighter than 0x28, its rim crossing every one of them (the glow about it
        // is fainter, the grooves and the sheen darker); the words are what is brighter than 0x60 under it.
        CGRect (^discOf)(CGImageRef) = ^CGRect(CGImageRef image) {
            NSArray<NSValue *> *runs = runsOf(image, ^BOOL(uint32_t c, size_t x, size_t y) { return brightOf(c) > 0x28; });
            return runs.count ? runs.firstObject.rectValue : CGRectNull;
        };
        NSArray<NSValue *> *(^inkOf)(CGImageRef) = ^NSArray<NSValue *> *(CGImageRef image) {
            CGFloat below = CGRectGetMaxY(discOf(image));
            return runsOf(image, ^BOOL(uint32_t c, size_t x, size_t y) { return y >= below && brightOf(c) > 0x60; });
        };
        CGImageRef full = frameOf(v, cover, before, line, translation, next);
        CGImageRef bare = frameOf(v, cover, nil, line, nil, next);
        check(same(full, bare), @"the line sung last and the translation are not drawn");
        CGRect disc = discOf(bare);
        check(fabs(CGRectGetWidth(disc) - kRecordMost * W) <= 5 && fabs(CGRectGetMidX(disc) - size.width / 2) <= 1.5,
              [NSString stringWithFormat:@"the record 60%% of the card across, centred, when the words fit (%@; want %.0f across)",
               NSStringFromRect(disc), kRecordMost * W]);
        CGImageRef longOne = frameOf(v, cover, nil, longLatin, nil, next);
        CGRect longDisc = discOf(longOne);
        check(fabs(CGRectGetWidth(longDisc) - kRecordLeast * W) <= 5,
              [NSString stringWithFormat:@"the record 45%% across under a long line (%.0f, want %.0f)", CGRectGetWidth(longDisc), kRecordLeast * W]);
        CGImageRef shortOne = frameOf(v, cover, nil, @"Hold on", nil, nil);
        CGRect shortDisc = discOf(shortOne);
        NSArray<NSValue *> *shortInk = inkOf(shortOne);
        CGFloat blockMid = shortInk.count ? (CGRectGetMinY(shortDisc) + CGRectGetMaxY(shortInk.lastObject.rectValue)) / 2 : 0;
        CGFloat bandMid = (kBandTop + kBandBottom) / 2 * H;
        check(fabs(blockMid - bandMid) <= 0.02 * W,
              [NSString stringWithFormat:@"the record and the words centred in the band together (middle at %.0f, want %.0f)", blockMid, bandMid]);
        CGPoint centre = CGPointMake(CGRectGetMidX(disc), CGRectGetMidY(disc));
        CGFloat label = kLabelOfRecord * CGRectGetWidth(disc);
        CGImageRef coverless = frameOf(v, NULL, nil, line, nil, next);
        NSData *bytes = rgba(coverless);
        uint32_t first = 0;
        BOOL flat = YES;
        for (int k = 0; k < 8; k++) {
            CGFloat angle = k * M_PI / 4, r = label * 0.25;
            size_t x = (size_t)round(centre.x + r * cos(angle)), y = (size_t)round(centre.y + r * sin(angle));
            uint32_t c = rgbOf((const uint8_t *)bytes.bytes + (y * (size_t)size.width + x) * 4);
            if (!k) first = c;
            flat = flat && c == first;
        }
        CGRect labelled = differ(bare, coverless, NULL);
        CGRect labelBox = CGRectMake(centre.x - label / 2 - 1.5, centre.y - label / 2 - 1.5, label + 3, label + 3);
        check(flat && brightOf(first) < 64 && !CGRectIsNull(labelled) && CGRectContainsRect(labelBox, labelled),
              [NSString stringWithFormat:@"the cover is the label, 38%% of the record, a plain dark one without (plain %06x; cover changes %@, label %@)",
               first, NSStringFromRect(labelled), NSStringFromRect(labelBox)]);
        BOOL glows = YES, rims = YES;
        NSMutableString *edges = [NSMutableString string];
        for (id object in @[(__bridge id)bare, (__bridge id)coverless]) {
            NSData *pixels = rgba((__bridge CGImageRef)object);
            const uint8_t *p = pixels.bytes;
            size_t row = (size_t)round(centre.y) * (size_t)size.width, left = (size_t)CGRectGetMinX(disc);
            int outside = brightOf(rgbOf(p + (row + left - 6) * 4)), rim = 0;
            for (size_t x = left; x < left + 4; x++) rim = MAX(rim, brightOf(rgbOf(p + (row + x) * 4)));
            glows = glows && outside >= brightOf(kVinylGround) + 3;
            rims = rims && rim >= round(kRimWhite * 255 + (1 - kRimWhite) * brightOf(kDisc)) - 4 && rim <= 0.35 * 255;
            [edges appendFormat:@"%s6 px out %d, rim %d", edges.length ? "; " : "", outside, rim];
        }
        check(glows, [NSString stringWithFormat:@"a glow about the record, with a cover and without (%@; ground %d)", edges, brightOf(kVinylGround)]);
        check(rims, [NSString stringWithFormat:@"the rim 25%% white (%@)", edges]);
        NSArray<NSValue *> *ink = inkOf(bare);
        CGRect words = ink.count ? ink.firstObject.rectValue : CGRectNull;
        for (NSValue *run in ink) words = CGRectUnion(words, run.rectValue);
        check(ink.count && CGRectGetMinY(words) >= CGRectGetMaxY(disc) + kWordsGap * W - 2 && CGRectGetMinY(words) <= CGRectGetMaxY(disc) + (kWordsGap + 0.03) * W
              && fabs(CGRectGetMidX(words) - size.width / 2) <= 0.03 * W,
              [NSString stringWithFormat:@"the words centred 4%% under the record (%@; record ends at %.0f)", NSStringFromRect(words), CGRectGetMaxY(disc)]);
        int brightest = 0;
        if (ink.count) {
            CGRect nextRun = ink.lastObject.rectValue;
            brightest = brightOf(kVinylGround);
            NSData *pixels = rgba(bare);
            const uint8_t *p = pixels.bytes;
            for (size_t y = (size_t)CGRectGetMinY(nextRun); y < (size_t)CGRectGetMaxY(nextRun); y++)
                for (size_t x = (size_t)CGRectGetMinX(nextRun); x < (size_t)CGRectGetMaxX(nextRun); x++)
                    brightest = MAX(brightest, brightOf(rgbOf(p + (y * (size_t)size.width + x) * 4)));
        }
        int want = (int)round(kNextWhite * 255 + (1 - kNextWhite) * brightOf(kVinylGround));
        check(ink.count >= 2 && brightest <= want + 2 && brightest >= want - 10,
              [NSString stringWithFormat:@"the next line beneath, 55%% white (brightest %d, want %d)", brightest, want]);
        NSString *texts[2] = {@"Hold on\nHold on", @"夜空\n夜空"};
        CGFloat heights[2] = {kVinylLineHeight, kCJKLineHeight};
        for (int k = 0; k < 2; k++) {
            CGImageRef twice = frameOf(v, cover, nil, texts[k], nil, nil);
            NSArray<NSValue *> *rows = inkOf(twice);
            CGFloat apart = rows.count == 2 ? CGRectGetMinY(rows[1].rectValue) - CGRectGetMinY(rows[0].rectValue) : 0;
            CGFloat wanted = heights[k] * kLineFont * W;
            check(fabs(apart - wanted) <= 1.5, [NSString stringWithFormat:@"the line's lines %.2f of its size apart%s (%.1f px, want %.1f)",
                                                heights[k], k ? " with CJK" : "", apart, wanted]);
            CGImageRelease(twice);
        }
        CGImageRelease(full); CGImageRelease(bare); CGImageRelease(longOne); CGImageRelease(shortOne); CGImageRelease(coverless);
    }
    printf("%s, scenes in %s\n", failures ? "scenes FAILED" : "scenes passed", out.path.UTF8String);
    return failures;
}
