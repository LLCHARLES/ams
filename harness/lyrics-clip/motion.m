// `lyrics-clip motion [video ...]`: the words over moving artwork (SGLyricsClipWriteOverMotion). Makes two
// stand-in videos, a bright busy one (a waving pink and white flag with white stars, 720 x 1280, 30 fps, the
// shape of a Canvas) and a dark one (dim drifting blobs and specks, 904 x 1206, 24 fps, the shape of an Apple
// Music cover at SGMotionPixels), takes any videos given too, and for each writes lines over it and checks
// the file: length, 3:4 size, H.264, frame count, words in the middle and none under the clock or the
// controls, the picture moving, the preview matching the first frame. It times each clip against the video
// cut alone (SGMotionClipShape) and the Animated lyrics clip, and prints the contrast of the words with the
// brightest of the picture behind them. Over the stand-ins it does so in every layout, and over a video dark at
// its start and bright later it checks the band is judged across the clip's stretch. Exits 1 on any failure.
#import <AVFoundation/AVFoundation.h>
#import <ImageIO/ImageIO.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <mach/mach.h>
#import "Shared/AnimatedArtwork/SGMotionClip.h"
#import "Shared/LockScreenLyrics/SGLyricsClip.h"

static int failures;

static void check(BOOL ok, NSString *what) {
    printf("  %s %s\n", ok ? "ok  " : "FAIL", what.UTF8String);
    if (!ok) failures++;
}

static double footprintMB(BOOL peak) {
    task_vm_info_data_t info;
    mach_msg_type_number_t count = TASK_VM_INFO_COUNT;
    if (task_info(mach_task_self(), TASK_VM_INFO, (task_info_t)&info, &count) != KERN_SUCCESS) return -1;
    return (peak ? info.ledger_phys_footprint_peak : info.phys_footprint) / 1048576.0;
}

static CGContextRef newContext(size_t width, size_t height, void *data, size_t bytesPerRow) {
    CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGContextRef context = CGBitmapContextCreate(data, width, height, 8, bytesPerRow, space,
                                                 kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
    CGColorSpaceRelease(space);
    return context;
}

static void star(CGContextRef c, CGFloat x, CGFloat y, CGFloat r) {
    for (int i = 0; i < 10; i++) {
        CGFloat a = M_PI_2 + i * M_PI / 5, l = i % 2 ? r * 0.4 : r;
        if (i) CGContextAddLineToPoint(c, x + l * cos(a), y + l * sin(a));
        else CGContextMoveToPoint(c, x + l * cos(a), y + l * sin(a));
    }
    CGContextClosePath(c);
    CGContextFillPath(c);
}

// A frame of the bright stand-in at `t` seconds: pink and white stripes waving across, a navy field of
// white stars at the top left, a white figure in the middle, the way a flag cover is busy and light.
static void drawFlag(CGContextRef c, size_t w, size_t h, double t) {
    CGContextSetRGBFillColor(c, 1, 1, 1, 1);
    CGContextFillRect(c, CGRectMake(0, 0, w, h));
    CGFloat stripe = h / 13.0;
    CGContextSetRGBFillColor(c, 0.88, 0.22, 0.58, 1);
    for (int i = 0; i < 14; i += 2) {
        CGContextMoveToPoint(c, 0, i * stripe);
        for (int x = 0; x <= (int)w; x += 8) {
            CGFloat y = i * stripe + stripe * 0.35 * sin(x / (CGFloat)w * 2 * M_PI + t * 2.2);
            CGContextAddLineToPoint(c, x, y);
        }
        for (int x = (int)w; x >= 0; x -= 8) {
            CGFloat y = (i + 1) * stripe + stripe * 0.35 * sin(x / (CGFloat)w * 2 * M_PI + t * 2.2);
            CGContextAddLineToPoint(c, x, y);
        }
        CGContextClosePath(c);
        CGContextFillPath(c);
    }
    CGFloat sway = 12 * sin(t * 2.2);
    CGRect field = CGRectMake(-20, h * 0.42 + sway, w * 0.62, h * 0.6);
    CGContextSetRGBFillColor(c, 0.06, 0.07, 0.16, 1);
    CGContextFillRect(c, field);
    CGContextSetRGBFillColor(c, 1, 1, 1, 1);
    for (int row = 0; row < 9; row++) {
        for (int col = 0; col < 5; col++) {
            star(c, 30 + col * w * 0.12 + (row % 2) * w * 0.06, h * 0.45 + sway + row * h * 0.062, w * 0.035);
        }
    }
    CGContextSetRGBFillColor(c, 0.97, 0.97, 0.97, 1);
    CGContextFillEllipseInRect(c, CGRectMake(w * 0.38, h * 0.18, w * 0.24, h * 0.22));
}

// A frame of the dark stand-in: a near-black field, slow dim colored blobs, and small bright specks.
static void drawDark(CGContextRef c, size_t w, size_t h, double t) {
    CGContextSetRGBFillColor(c, 0.03, 0.03, 0.06, 1);
    CGContextFillRect(c, CGRectMake(0, 0, w, h));
    CGFloat colors[][3] = {{0.35, 0.1, 0.45}, {0.1, 0.2, 0.45}, {0.45, 0.15, 0.1}};
    for (int i = 0; i < 3; i++) {
        CGFloat x = w * (0.3 + 0.25 * i + 0.1 * sin(t * 0.8 + i)), y = h * (0.3 + 0.2 * i + 0.08 * cos(t * 0.8 + i * 2));
        CGContextSetRGBFillColor(c, colors[i][0], colors[i][1], colors[i][2], 0.6);
        CGContextFillEllipseInRect(c, CGRectMake(x - w * 0.3, y - w * 0.3, w * 0.6, w * 0.6));
    }
    CGContextSetRGBFillColor(c, 1, 1, 1, 0.9);
    for (int i = 0; i < 60; i++) {
        CGFloat x = fmod(i * 97.3 + t * 20, w), y = fmod(i * 211.7, h), r = 1.5 + (i % 3);
        CGContextFillEllipseInRect(c, CGRectMake(x, y, r * 2, r * 2));
    }
}

// A frame of a video dark at its start and bright later: two seconds of a flat mid grey (0.4 of white) with a
// dimmer disc drifting across, then the flag.
static void drawDusk(CGContextRef c, size_t w, size_t h, double t) {
    if (t >= 2) {
        drawFlag(c, w, h, t);
        return;
    }
    CGContextSetRGBFillColor(c, 0.4, 0.4, 0.4, 1);
    CGContextFillRect(c, CGRectMake(0, 0, w, h));
    CGContextSetRGBFillColor(c, 0.3, 0.3, 0.32, 1);
    CGContextFillEllipseInRect(c, CGRectMake(w * (0.1 + 0.3 * t), h * 0.2, w * 0.3, w * 0.3));
}

// Flat white, and flat grey at a quarter of white: nothing to blur, so a dimming that is even leaves them even.
static void drawWhite(CGContextRef c, size_t w, size_t h, double t) {
    CGContextSetRGBFillColor(c, 1, 1, 1, 1);
    CGContextFillRect(c, CGRectMake(0, 0, w, h));
}

static void drawGrey(CGContextRef c, size_t w, size_t h, double t) {
    CGContextSetRGBFillColor(c, 0.25, 0.25, 0.25, 1);
    CGContextFillRect(c, CGRectMake(0, 0, w, h));
}

static BOOL makeVideo(NSURL *url, size_t w, size_t h, int fps, int seconds, void (*draw)(CGContextRef, size_t, size_t, double)) {
    [NSFileManager.defaultManager removeItemAtURL:url error:nil];
    AVAssetWriter *writer = [AVAssetWriter assetWriterWithURL:url fileType:AVFileTypeMPEG4 error:nil];
    AVAssetWriterInput *input = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:@{
        AVVideoCodecKey: AVVideoCodecTypeH264, AVVideoWidthKey: @(w), AVVideoHeightKey: @(h),
        AVVideoCompressionPropertiesKey: @{AVVideoAverageBitRateKey: @(w * h * 3), AVVideoMaxKeyFrameIntervalKey: @(fps * 2)},
    }];
    AVAssetWriterInputPixelBufferAdaptor *adaptor = [AVAssetWriterInputPixelBufferAdaptor assetWriterInputPixelBufferAdaptorWithAssetWriterInput:input
        sourcePixelBufferAttributes:@{(id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA),
                                      (id)kCVPixelBufferWidthKey: @(w), (id)kCVPixelBufferHeightKey: @(h)}];
    [writer addInput:input];
    [writer startWriting];
    [writer startSessionAtSourceTime:kCMTimeZero];
    for (int i = 0; i < fps * seconds; i++) {
        while (!input.readyForMoreMediaData) [NSThread sleepForTimeInterval:0.002];
        CVPixelBufferRef buffer = NULL;
        CVPixelBufferPoolCreatePixelBuffer(NULL, adaptor.pixelBufferPool, &buffer);
        CVPixelBufferLockBaseAddress(buffer, 0);
        CGContextRef context = newContext(w, h, CVPixelBufferGetBaseAddress(buffer), CVPixelBufferGetBytesPerRow(buffer));
        draw(context, w, h, (double)i / fps);
        CGContextRelease(context);
        CVPixelBufferUnlockBaseAddress(buffer, 0);
        [adaptor appendPixelBuffer:buffer withPresentationTime:CMTimeMake(i, fps)];
        CVPixelBufferRelease(buffer);
    }
    [input markAsFinished];
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    [writer finishWritingWithCompletionHandler:^{ dispatch_semaphore_signal(done); }];
    dispatch_semaphore_wait(done, DISPATCH_TIME_FOREVER);
    return writer.status == AVAssetWriterStatusCompleted;
}

static void savePNG(CGImageRef image, NSURL *url) {
    CGImageDestinationRef destination = CGImageDestinationCreateWithURL((__bridge CFURLRef)url, (__bridge CFStringRef)UTTypePNG.identifier, 1, NULL);
    CGImageDestinationAddImage(destination, image, NULL);
    CGImageDestinationFinalize(destination);
    CFRelease(destination);
}

static CGImageRef frameAt(NSURL *url, double seconds) CF_RETURNS_RETAINED {
    AVAssetImageGenerator *generator = [AVAssetImageGenerator assetImageGeneratorWithAsset:[AVURLAsset URLAssetWithURL:url options:nil]];
    generator.requestedTimeToleranceBefore = generator.requestedTimeToleranceAfter = kCMTimeZero;
    return [generator copyCGImageAtTime:CMTimeMakeWithSeconds(seconds, 600) actualTime:NULL error:nil];
}

// RGBA bytes of `image`, freed by the caller.
static uint8_t *pixelsOf(CGImageRef image, size_t *width, size_t *height) {
    *width = CGImageGetWidth(image);
    *height = CGImageGetHeight(image);
    CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    uint8_t *data = calloc(*width * *height, 4);
    CGContextRef context = CGBitmapContextCreate(data, *width, *height, 8, *width * 4, space, (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
    CGContextDrawImage(context, CGRectMake(0, 0, *width, *height), image);
    CGContextRelease(context);
    CGColorSpaceRelease(space);
    return data;
}

// Share of pixels lighter than `above` in every channel in rows `from` to `to` of the height, counted from the
// top. The picture is dimmed to 0.75 of white (kMotionDim), and to 0.4 under the words (kBandDim), so past 225
// only the words reach, and past 120 in the band only the words, dimmed ones too.
static double whiteIn(CGImageRef image, double from, double to, int above) {
    size_t w, h, lit = 0, all = 0;
    uint8_t *p = pixelsOf(image, &w, &h);
    for (size_t y = from * h; y < to * h; y++) {
        for (size_t x = 0; x < w; x++, all++) {
            uint8_t *q = p + (y * w + x) * 4;
            if (q[0] > above && q[1] > above && q[2] > above) lit++;
        }
    }
    free(p);
    return all ? (double)lit / all : 0;
}

static double linear(double c) {
    c /= 255;
    return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4);
}

// The relative luminance the brightest 5% of the picture reaches in rows `from` to `to`, and their mean.
static double brightIn(CGImageRef image, double from, double to, double *mean) {
    size_t w, h;
    uint8_t *p = pixelsOf(image, &w, &h);
    NSMutableArray<NSNumber *> *all = [NSMutableArray array];
    double sum = 0;
    for (size_t y = from * h; y < to * h; y += 2) {
        for (size_t x = 0; x < w; x += 2) {
            uint8_t *q = p + (y * w + x) * 4;
            double l = 0.2126 * linear(q[0]) + 0.7152 * linear(q[1]) + 0.0722 * linear(q[2]);
            [all addObject:@(l)];
            sum += l;
        }
    }
    free(p);
    [all sortUsingSelector:@selector(compare:)];
    *mean = sum / all.count;
    return all[(NSUInteger)(all.count * 0.95)].doubleValue;
}

// Mean absolute difference of two images of the same size, per channel, 0 to 255.
static double differ(CGImageRef a, CGImageRef b) {
    size_t w, h, w2, h2;
    uint8_t *p = pixelsOf(a, &w, &h), *q = pixelsOf(b, &w2, &h2);
    double sum = 0;
    if (w == w2 && h == h2) {
        for (size_t i = 0; i < w * h * 4; i++) if (i % 4 != 3) sum += abs(p[i] - q[i]);
    }
    free(p);
    free(q);
    return w == w2 && h == h2 ? sum / (w * h * 3) : 255;
}

// The mean of the color channels in rows `from` to `to` of the height, counted from the top, 0 to 255, as the
// image holds them: in its own color space, so a decoded frame (Core Media's Rec. 709) and a preview (sRGB) both
// give the values SGLyricsClip.m worked on.
static double meanIn(CGImageRef image, double from, double to) {
    size_t w = CGImageGetWidth(image), h = CGImageGetHeight(image);
    uint8_t *p = calloc(w * h, 4);
    CGContextRef context = CGBitmapContextCreate(p, w, h, 8, w * 4, CGImageGetColorSpace(image), (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
    CGContextDrawImage(context, CGRectMake(0, 0, w, h), image);
    CGContextRelease(context);
    double sum = 0;
    size_t count = 0;
    for (size_t y = from * h; y < to * h; y++) {
        for (size_t x = 0; x < w; x++, count += 3) sum += p[(y * w + x) * 4] + p[(y * w + x) * 4 + 1] + p[(y * w + x) * 4 + 2];
    }
    free(p);
    return count ? sum / count : 0;
}

typedef struct { double seconds; int frames; CGSize size; BOOL h264; } Read;

static Read readBack(NSURL *url) {
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:url options:@{AVURLAssetPreferPreciseDurationAndTimingKey: @YES}];
    AVAssetTrack *track = [asset tracksWithMediaType:AVMediaTypeVideo].firstObject;
    Read read = {CMTimeGetSeconds(asset.duration), 0, track.naturalSize, NO};
    if (!track) return read;
    read.h264 = CMFormatDescriptionGetMediaSubType((__bridge CMFormatDescriptionRef)track.formatDescriptions.firstObject) == kCMVideoCodecType_H264;
    AVAssetReader *reader = [AVAssetReader assetReaderWithAsset:asset error:nil];
    AVAssetReaderTrackOutput *output = [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:track outputSettings:nil];
    [reader addOutput:output];
    [reader startReading];
    CMSampleBufferRef sample;
    while ((sample = [output copyNextSampleBuffer])) {
        if (CMSampleBufferGetNumSamples(sample)) read.frames++;
        CFRelease(sample);
    }
    return read;
}

static double contrast(double lighter, double darker) {
    return (lighter + 0.05) / (darker + 0.05);
}

// The lines as spaces: the same layout, so the same softening and dimming, with no words on it.
static NSString *blanked(NSString *text) {
    return [@"" stringByPaddingToLength:text.length withString:@" " startingAtIndex:0];
}

static double lumaAt(const uint8_t *q) {
    return 0.2126 * q[0] + 0.7152 * q[1] + 0.0722 * q[2];
}

// Isolate dimmed letters from a bright background, rather than counting the background as white text.
static CGRect wordBounds(CGImageRef words, CGImageRef behind) {
    size_t w, h, w2, h2;
    // The encoder consumes the renderer's RGB sample values but tags the decoded raster Rec.709.
    // Interpret those values in the renderer's space before comparing; a second transfer conversion
    // turns bright background edges into false letters.
    CGImageRef samples = CGImageCreateCopyWithColorSpace(words, CGImageGetColorSpace(behind));
    uint8_t *p = pixelsOf(samples, &w, &h), *q = pixelsOf(behind, &w2, &h2);
    CGImageRelease(samples);
    CGRect bounds = CGRectNull;
    for (size_t y = 0; w == w2 && h == h2 && y < h; y++) {
        for (size_t x = 0; x < w; x++) {
            size_t offset = (y * w + x) * 4;
            if (lumaAt(p + offset) - lumaAt(q + offset) > 40)
                bounds = CGRectUnion(bounds, CGRectMake(x, y, 1, 1));
        }
    }
    free(p);
    free(q);
    return bounds;
}

// The picture behind a translation and the next line, across the visible frame. `words` is a
// frame with them and `behind` the same frame with them as spaces; rows where `words` is lighter are the lines',
// and the last two runs of them (the translation and the next line, or the line and its translation run
// together and the next) are looked at. Returns the picture's pattern there, the mean step between neighbouring
// pixels' luma, 0 to 255; `dimmed` gets the contrast a dimmed line (0.55 white, unshadowed) has on its brightest
// 5%, and `outside` the mean difference of the two frames away from the words, which is 0 when the layout and
// dimming match.
static double behindDimmed(CGImageRef words, CGImageRef behind, double *dimmed, double *outside) {
    size_t w, h, w2, h2;
    uint8_t *p = pixelsOf(words, &w, &h), *q = pixelsOf(behind, &w2, &h2);
    double pattern = -1;
    *dimmed = 0;
    *outside = 255;
    size_t left = 0, right = w - 1, runs[8][2], n = 0, unlit = 0;
    BOOL in = NO;
    for (size_t y = 0; w == w2 && h == h2 && y < h; y++) {
        BOOL lit = NO;
        for (size_t x = left; x < right && !lit; x++) lit = lumaAt(p + (y * w + x) * 4) - lumaAt(q + (y * w + x) * 4) > 40;
        if (n == 8) break;
        if (lit && !in) runs[n][0] = y, in = YES;
        if (lit) unlit = 0, runs[n][1] = y + 1;
        // A run ends after three rows without a lit pixel, so a gap inside a line does not split it.
        else if (in && ++unlit >= 3) n++, in = NO;
    }
    if (in) n++;
    if (n >= 3) {
        size_t from = runs[n - 2][0], to = runs[n - 1][1], count = 0, away = 0;
        double steps = 0, apart = 0;
        NSMutableArray<NSNumber *> *lights = [NSMutableArray array];
        for (size_t y = from; y < to; y++) {
            for (size_t x = left; x < right; x++, count++) {
                const uint8_t *r = q + (y * w + x) * 4;
                steps += fabs(lumaAt(r + 4) - lumaAt(r)) + fabs(lumaAt(r + w * 4) - lumaAt(r));
                [lights addObject:@(0.2126 * linear(r[0]) + 0.7152 * linear(r[1]) + 0.0722 * linear(r[2]))];
            }
        }
        // Away from the words: a font size (about 5% of the width) past the first and last runs.
        for (size_t y = 0; y < h; y++) {
            if (y + w / 20 >= runs[0][0] && y <= runs[n - 1][1] + w / 20) continue;
            for (size_t i = y * w * 4; i < (y + 1) * w * 4; i++, away++) apart += abs(p[i] - q[i]);
        }
        pattern = steps / count;
        [lights sortUsingSelector:@selector(compare:)];
        double top = lights[(NSUInteger)(lights.count * 0.95)].doubleValue;
        *dimmed = contrast(linear(255 * (0.55 + 0.45 * pow(top, 1 / 2.2))), top);
        *outside = away ? apart / away : 255;
    }
    free(p);
    free(q);
    return pattern;
}

int motionMain(NSURL *out, int argc, char **argv) {
    printf("footprint at start %.1f MB\n", footprintMB(NO));
    // `motion one video` and `motion cut video`: a single line's clip, or the video cut alone as LockScreenMotion.x
    // cuts it, in a fresh process, for the memory one takes.
    if (argc == 2 && (!strcmp(argv[0], "one") || !strcmp(argv[0], "cut"))) {
        NSURL *video = [NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[1]]];
        CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
        BOOL ok = !strcmp(argv[0], "one")
            ? SGLyricsClipWriteOverMotion([out URLByAppendingPathComponent:@"one.mp4"], video, @"(And I turn into a stalker)",
                                          @"I stare at the moon", nil, @"When nighttime comes", 1, 4.5, SGLyricsClipLeft, nil)
            : SGMotionClipShape(video, 0.75, [out URLByAppendingPathComponent:@"one-cut.mp4"]);
        printf("%s %s in %.0f ms; footprint now %.1f MB, peak %.1f MB\n", argv[0], ok ? "written" : "FAILED",
               (CFAbsoluteTimeGetCurrent() - start) * 1000, footprintMB(NO), footprintMB(YES));
        return ok ? 0 : 1;
    }
    NSMutableArray<NSURL *> *videos = [NSMutableArray array];
    NSURL *flag = [out URLByAppendingPathComponent:@"source-flag.mp4"], *dark = [out URLByAppendingPathComponent:@"source-dark.mp4"];
    check(makeVideo(flag, 720, 1280, 30, 6, drawFlag), @"made the bright stand-in, 720x1280, 30 fps, 6 s");

    // The end of the artwork ID (LyricsArtwork.x): a style change or another video gives another ID, so no clip is
    // kept past either; two store names that share their first four characters still differ.
    printf("artwork IDs\n");
    NSURL *a = [NSURL fileURLWithPath:@"/c/Motion/3f9a0c11d2e4b5a6978877665544332211009988.mp4"];
    NSURL *b = [NSURL fileURLWithPath:@"/c/Motion/3f9a77aa00bb11cc22dd33ee44ff556677889900.mp4"];
    SGLyricsClipLayout left = SGLyricsClipLeft, over = SGLyricsClipOverArtwork;
    check(![SGLyricsClipLook(nil, SGLyricsClipStill, left, NO) isEqual:@"0l0"] &&
          ![SGLyricsClipLook(a, SGLyricsClipStill, left, NO) isEqual:@"m3f9a0c11d2e4b5a6s0l0"],
          @"cover and motion offers cannot reuse pre-versioned system artwork");
    check(![SGLyricsClipLook(a, SGLyricsClipStill, left, NO) isEqual:SGLyricsClipLook(a, SGLyricsClipAnimated, left, NO)],
          [NSString stringWithFormat:@"the style is in it over moving artwork (%@, %@)", SGLyricsClipLook(a, SGLyricsClipStill, left, NO),
           SGLyricsClipLook(a, SGLyricsClipAnimated, left, NO)]);
    check(![SGLyricsClipLook(a, SGLyricsClipStill, left, NO) isEqual:SGLyricsClipLook(b, SGLyricsClipStill, left, NO)], @"another video gives another one");
    check([SGLyricsClipLook(a, SGLyricsClipStill, left, NO) isEqual:SGLyricsClipLook([a copy], SGLyricsClipStill, left, NO)],
          @"the same video, style and layout give the same one");
    check(![SGLyricsClipLook(nil, SGLyricsClipStill, left, NO) isEqual:SGLyricsClipLook(a, SGLyricsClipStill, left, NO)]
          && ![SGLyricsClipLook(nil, SGLyricsClipStill, left, NO) isEqual:SGLyricsClipLook(nil, SGLyricsClipAnimated, left, NO)], @"over the cover, the style alone");
    NSSet *looks = [NSSet setWithArray:@[SGLyricsClipLook(a, SGLyricsClipStill, left, NO), SGLyricsClipLook(a, SGLyricsClipStill, SGLyricsClipCentered, NO),
                                         SGLyricsClipLook(a, SGLyricsClipStill, SGLyricsClipPoster, NO), SGLyricsClipLook(nil, SGLyricsClipStill, left, NO),
                                         SGLyricsClipLook(nil, SGLyricsClipStill, SGLyricsClipCentered, NO), SGLyricsClipLook(nil, SGLyricsClipStill, SGLyricsClipPoster, NO)]];
    check(looks.count == 6, [NSString stringWithFormat:@"the layout is in it, over moving artwork and the cover (%@)",
                             [looks.allObjects componentsJoinedByString:@", "]]);
    check(![SGLyricsClipLook(nil, SGLyricsClipStill, over, YES) isEqual:SGLyricsClipLook(nil, SGLyricsClipStill, over, NO)]
          && ![SGLyricsClipLook(nil, SGLyricsClipAnimated, over, YES) isEqual:SGLyricsClipLook(nil, SGLyricsClipAnimated, over, NO)]
          && ![SGLyricsClipLook(a, SGLyricsClipStill, over, YES) isEqual:SGLyricsClipLook(a, SGLyricsClipStill, left, NO)],
          [NSString stringWithFormat:@"dimming the whole artwork is in it (%@, %@)", SGLyricsClipLook(nil, SGLyricsClipStill, over, YES),
           SGLyricsClipLook(nil, SGLyricsClipStill, over, NO)]);

    // A video gone from the store or cut short fails at once, with no preview, for LyricsArtwork.x to remember.
    printf("videos that will not read\n");
    NSURL *gone = [out URLByAppendingPathComponent:@"gone.mp4"], *cutShort = [out URLByAppendingPathComponent:@"cut-short.mp4"];
    [NSFileManager.defaultManager removeItemAtURL:gone error:nil];
    NSData *whole = [NSData dataWithContentsOfURL:flag];
    [[whole subdataWithRange:NSMakeRange(0, whole.length / 3)] writeToURL:cutShort atomically:YES];
    for (NSURL *bad in @[gone, cutShort]) {
        NSURL *clip = [out URLByAppendingPathComponent:[@"from-" stringByAppendingString:bad.lastPathComponent]];
        CFAbsoluteTime started = CFAbsoluteTimeGetCurrent();
        BOOL written = SGLyricsClipWriteOverMotion(clip, bad, nil, @"A line", nil, @"the next", 1, 3, left, nil);
        double ms = (CFAbsoluteTimeGetCurrent() - started) * 1000;
        CGImageRef preview = SGLyricsClipMotionFrame(bad, nil, @"A line", nil, @"the next", 1, 3, left);
        check(!written && !preview && ![NSFileManager.defaultManager fileExistsAtPath:clip.path],
              [NSString stringWithFormat:@"%@: not written (in %.0f ms) and no preview", bad.lastPathComponent, ms]);
        CGImageRelease(preview);
    }
    check(makeVideo(dark, 904, 1206, 24, 8, drawDark), @"made the dark stand-in, 904x1206, 24 fps, 8 s");
    [videos addObjectsFromArray:@[flag, dark]];
    for (int i = 0; i < argc; i++) [videos addObject:[NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[i]]]];

    // The lyrics clip as it is, Animated, for the Mac-to-phone ratio: the phone wrote 96 such frames in about 4 s.
    CGImageRef plain = SGLyricsClipBackdrop(NULL, SGLyricsClipSize(904));
    CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
    SGLyricsClipWrite([out URLByAppendingPathComponent:@"animated.mp4"], plain, @"Hold on", nil, @"we're almost there", SGLyricsClipSize(904), SGLyricsClipAnimated);
    double animatedMs = (CFAbsoluteTimeGetCurrent() - start) * 1000;
    CGImageRelease(plain);
    printf("the Animated lyrics clip, 60 frames: %.0f ms, %.1f ms a frame\n", animatedMs, animatedMs / 60);

    NSArray *cases = @[
        // name, previous, line, next, from, seconds[, the line's translation]
        @[@"line", @"(And I turn into a stalker)", @"I stare at the moon", @"When nighttime comes", @1.0, @3.5],
        @[@"translated", @"(And I turn into a stalker)", @"I stare at the moon", @"When nighttime comes", @1.0, @3.5, @"나는 달을 바라봐"],
        @[@"long", @"Hold on", @"And every word I never said keeps ringing out across the quiet of the night", @"until the morning finds us", @2.0, @5.0],
        @[@"wrap", @"", @"Round the end of the video", @"and on from its start", @-1.5, @3.0],
        @[@"whole", @"Before", @"A line longer than the video", @"", @3.0, @20.0],
        @[@"rest", @"", @"", @"The first line, coming up", @0.0, @4.0],
        @[@"bare", @"", @"", @"", @2.0, @2.0],
        // Too tall even at the smallest size: the lines either side and the translation go, the line ends in an ellipsis.
        @[@"overflow", @"Hold on", [@"" stringByPaddingToLength:900 withString:@"Every word I never said keeps ringing out across the quiet night, " startingAtIndex:0],
          @"until the morning finds us", @1.0, @3.0,
          [@"" stringByPaddingToLength:300 withString:@"and every promise I forgot comes back to find me here again, " startingAtIndex:0]],
        @[@"overflow-cjk", @"前の行", [@"" stringByPaddingToLength:420 withString:@"夜空に光る星を数えながら君の名前を何度も呼んだ、" startingAtIndex:0],
          @"君の名前を呼んだ", @1.0, @3.0,
          [@"" stringByPaddingToLength:200 withString:@"밤하늘에 빛나는 별을 세면서 너의 이름을 몇 번이고 불렀어, " startingAtIndex:0]],
    ];
    NSDictionary<NSNumber *, NSString *> *layoutNames = @{@(SGLyricsClipLeft): @"", @(SGLyricsClipCentered): @"-centered",
                                                          @(SGLyricsClipPoster): @"-poster", @(SGLyricsClipOverArtwork): @"-over"};
    for (NSURL *video in videos) {
        NSString *name = video.lastPathComponent.stringByDeletingPathExtension;
        AVURLAsset *asset = [AVURLAsset URLAssetWithURL:video options:@{AVURLAssetPreferPreciseDurationAndTimingKey: @YES}];
        AVAssetTrack *track = [asset tracksWithMediaType:AVMediaTypeVideo].firstObject;
        double length = CMTimeGetSeconds(asset.duration), fps = MIN(round(track.nominalFrameRate), 30);   // kept to 30 fps
        printf("\n%s: %.0fx%.0f, %.2f s at %.0f fps\n", name.UTF8String, track.naturalSize.width, track.naturalSize.height, length, fps);
        // drawOver refuses a decoded frame of another size than the track states, and the clip is then not written,
        // so LyricsArtwork.x draws the line over the cover. A video with non-square pixels does that: its natural size
        // is the shown one (960x1280 for 720x1280 at 4:3), its frames the stored one.
        BOOL matches;
        {
            AVAssetReader *reader = [AVAssetReader assetReaderWithAsset:asset error:nil];
            AVAssetReaderTrackOutput *output = [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:track
                outputSettings:@{(id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA)}];
            [reader addOutput:output];
            [reader startReading];
            CMSampleBufferRef sample = [output copyNextSampleBuffer];
            CVPixelBufferRef buffer = sample ? CMSampleBufferGetImageBuffer(sample) : NULL;
            size_t w = buffer ? CVPixelBufferGetWidth(buffer) : 0, h = buffer ? CVPixelBufferGetHeight(buffer) : 0;
            matches = w == (size_t)round(track.naturalSize.width) && h == (size_t)round(track.naturalSize.height);
            printf("  %s\n", [NSString stringWithFormat:@"%@ at its natural size (%.3fx%.3f, frames %zux%zu, %zu bytes a row)",
                   matches ? @"decodes" : @"does NOT decode", track.naturalSize.width, track.naturalSize.height, w, h,
                   buffer ? CVPixelBufferGetBytesPerRow(buffer) : 0].UTF8String);
            if (sample) CFRelease(sample);
            [reader cancelReading];
        }
        // The video cut alone, the decode and encode with nothing drawn, to tell the drawing's share.
        start = CFAbsoluteTimeGetCurrent();
        SGMotionClipShape(video, 0.75, [out URLByAppendingPathComponent:[name stringByAppendingString:@"-cut.mp4"]]);
        double cutMs = (CFAbsoluteTimeGetCurrent() - start) * 1000;
        printf("  the cut alone: %.0f ms for %.2f s, %.1f ms a frame\n", cutMs, length, cutMs / (length * fps));
        // Every case in Left; the others (Over the artwork dimmed whole), only over the stand-ins, without the looks
        // behind the words.
        NSArray<NSNumber *> *layouts = [video isEqual:flag] || [video isEqual:dark]
            ? @[@(SGLyricsClipLeft), @(SGLyricsClipCentered), @(SGLyricsClipPoster), @(SGLyricsClipOverArtwork)] : @[@(SGLyricsClipLeft)];
        for (NSNumber *layoutNumber in layouts)
        for (NSArray *c in cases) @autoreleasepool {
            SGLyricsClipLayout layout = layoutNumber.integerValue;
            double from = [c[4] doubleValue] < 0 ? length + [c[4] doubleValue] : [c[4] doubleValue], seconds = [c[5] doubleValue];
            double wanted = MIN(seconds, length);
            NSString *translation = c.count > 6 ? c[6] : nil;
            NSURL *url = [out URLByAppendingPathComponent:[NSString stringWithFormat:@"%@-%@%@.mp4", name, c[0], layoutNames[layoutNumber]]];
            start = CFAbsoluteTimeGetCurrent();
            BOOL written = SGLyricsClipWriteOverMotion(url, video, c[1], c[2], translation, c[3], from, seconds, layout, nil);
            if (!matches) {
                CGImageRef preview = SGLyricsClipMotionFrame(video, c[1], c[2], translation, c[3], from, seconds, layout);
                check(!written && !preview && ![NSFileManager.defaultManager fileExistsAtPath:url.path],
                      @"not written and no preview, so the line falls back to the cover rather than showing without its words");
                CGImageRelease(preview);
                continue;
            }
            double ms = (CFAbsoluteTimeGetCurrent() - start) * 1000;
            printf("  footprint after writing %.1f MB\n", footprintMB(NO));
            printf(" %s\n", url.lastPathComponent.UTF8String);
            check(written, [NSString stringWithFormat:@"written in %.0f ms, %.1f ms a frame, %.1f s of clip a second",
                            ms, ms / (wanted * fps), wanted / (ms / 1000)]);
            if (!written) continue;
            Read read = readBack(url);
            check(fabs(read.seconds - wanted) < 0.05, [NSString stringWithFormat:@"lasts %.3f s (want %.3f)", read.seconds, wanted]);
            check(read.size.width * 4 == read.size.height * 3
                  && fmod(read.size.width, 2) == 0 && fmod(read.size.height, 2) == 0
                  && read.size.width <= track.naturalSize.width && read.size.height <= track.naturalSize.height,
                  [NSString stringWithFormat:@"motion clip is exactly 3:4 with even sides inside the source (%.0fx%.0f)",
                   read.size.width, read.size.height]);
            check(read.h264, @"is H.264");
            check(abs(read.frames - (int)round(wanted * fps)) <= 1, [NSString stringWithFormat:@"holds %d frames (want %.0f)", read.frames, wanted * fps]);
            CGImageRef first = frameAt(url, 0), middle = frameAt(url, wanted / 2);
            if (!first || !middle) {
                check(NO, @"frames read back");
                continue;
            }
            savePNG(first, [url URLByAppendingPathExtension:@"png"]);
            BOOL words = [c[1] length] || [c[2] length] || [c[3] length];
            CGFloat safeTop = (.17 - .10) / (1179.0 / 2556 * 4 / 3), safeBottom = (.65 - .10) / (1179.0 / 2556 * 4 / 3);
            double band = whiteIn(first, safeTop, safeBottom, [c[2] length] || ![c[3] length] ? 225 : 120);
            if (words && ![c[0] isEqual:@"rest"])
                check(band > 0.003, [NSString stringWithFormat:@"words in the screen-safe band (%.2f%% white)", band * 100]);
            else if (!words) check(band < 0.0005, [NSString stringWithFormat:@"no words when there are none (%.3f%% white)", band * 100]);
            check(whiteIn(first, 0, safeTop, 225) < 0.0005 && whiteIn(first, safeBottom, 1, 225) < 0.0005, @"nothing white under the clock or the controls");
            double moved = differ(first, middle);
            check(moved > 2, [NSString stringWithFormat:@"the picture moves (%.1f of 255 between the start and the middle)", moved]);
            CGImageRef preview = SGLyricsClipMotionFrame(video, c[1], c[2], translation, c[3], from, seconds, layout);
            check(preview && CGImageGetWidth(preview) == read.size.width && CGImageGetHeight(preview) == read.size.height
                  && CGImageGetWidth(preview) * 4 == CGImageGetHeight(preview) * 3,
                  @"motion preview matches the exact 3:4 clip raster");
            double off = preview ? differ(preview, first) : 255;
            check(off < 10, [NSString stringWithFormat:@"the preview is the first frame (%.1f of 255 apart, the encode's loss)", off]);
            if ([c[0] isEqual:@"rest"]) {
                // A lone next line is 0.6-size, half-white text, not a minimum share of the whole safe area's pixels.
                // Check its screen placement instead; the old density threshold also counted bright flag pixels.
                CGImageRef behind = SGLyricsClipMotionFrame(video, nil, nil, nil, blanked(c[3]), from, seconds, layout);
                CGRect bounds = behind ? wordBounds(first, behind) : CGRectNull;
                CGFloat screenHeight = CGImageGetWidth(first) * 2556.0 / 1179;
                CGFloat top = .10 + CGRectGetMinY(bounds) / screenHeight;
                CGFloat bottom = .10 + CGRectGetMaxY(bounds) / screenHeight;
                check(!CGRectIsNull(bounds) && top >= .17 && bottom <= .65 && fabs((top + bottom) / 2 - .40) < .025,
                      @"the lone next line is centred 40% down the screen inside 17–65%");
                CGFloat width = CGImageGetWidth(first);
                check(!CGRectIsNull(bounds) && (layout == SGLyricsClipCentered
                      ? fabs(CGRectGetMidX(bounds) / width - .50) < .02
                      : fabs(CGRectGetMinX(bounds) / width - .08) < .015),
                      @"the lone next line uses the full frame's alignment, not a centre crop");
                CGImageRelease(behind);
            }
            if (preview && ([c[0] isEqual:@"line"] || translation))
                savePNG(preview, [out URLByAppendingPathComponent:[NSString stringWithFormat:@"%@-%@%@-preview.png", name, c[0], layoutNames[layoutNumber]]]);
            if (preview && translation && layout == SGLyricsClipLeft && ![c[0] hasPrefix:@"overflow"]) {
                // Behind the dimmed lines: on the bright flag, the narrower softening and fixed band before left the
                // stars' pattern at 1.31 and a dimmed line 3.4:1 on the brightest there.
                CGImageRef behind = SGLyricsClipMotionFrame(video, blanked(c[1]), blanked(c[2]), blanked(translation), blanked(c[3]), from,
                                                            seconds, layout);
                double dimmed, outside, pattern = behind ? behindDimmed(preview, behind, &dimmed, &outside) : -1;
                NSString *what = [NSString stringWithFormat:@"behind the translation and the next line: pattern %.2f of 255, a dimmed "
                                  "line on the brightest %.1f:1 (the blank frame %.2f apart away from the words)", pattern, dimmed, outside];
                if ([video isEqual:flag]) check(pattern >= 0 && pattern < 0.65 && dimmed > 4.2 && outside < 0.5, what);
                else printf("  %s\n", what.UTF8String);
                CGImageRelease(behind);
            }
            CGImageRelease(preview);
            if ([c[0] isEqual:@"bare"] && layout == SGLyricsClipLeft) {
                // The picture under the words, as dimmed: white on its brightest 5%, and the dimmed lines' 40% white over it.
                double mean, top = brightIn(first, 0.30, 0.50, &mean);
                double dimTop = linear(255 * (0.4 + 0.6 * pow(top, 1 / 2.2)));
                printf("  under the words: brightest 5%% at luminance %.3f, mean %.3f; white on it %.1f:1, white on the mean %.1f:1, "
                       "a dimmed line on the brightest %.1f:1\n", top, mean, contrast(1, top), contrast(1, mean), contrast(dimTop, top));
                CGImageRef source = frameAt(video, from);
                double sourceMean, sourceTop = brightIn(source, 0.30, 0.50, &sourceMean);
                printf("  the same rows undimmed: brightest 5%% at %.3f, white on it %.1f:1\n", sourceTop, contrast(1, sourceTop));
                CGImageRelease(source);
            }
            CGImageRelease(first);
            CGImageRelease(middle);
        }
    }

    // Over the artwork dimmed whole darkens the whole frame evenly, no band, by what the brightest of the picture needs:
    // over flat white to grey, between a quarter of white and the 82 of 255 under which a dimmed line keeps 3.3:1, and over
    // flat grey by at least 30%. The clip's first frame is the preview's.
    printf("\nover the artwork, dimmed whole, over flat videos\n");
    for (NSArray *flat in @[@[@"white", [NSValue valueWithPointer:drawWhite], @255], @[@"grey", [NSValue valueWithPointer:drawGrey], @64]]) {
        NSURL *source = [out URLByAppendingPathComponent:[NSString stringWithFormat:@"source-%@.mp4", flat[0]]];
        check(makeVideo(source, 720, 1280, 30, 3, (void (*)(CGContextRef, size_t, size_t, double))[flat[1] pointerValue]),
              [NSString stringWithFormat:@"made flat %@, 720x1280, 30 fps, 3 s", flat[0]]);
        NSString *p = blanked(@"(And I turn into a stalker)"), *l = blanked(@"I stare at the moon"), *t = blanked(@"나는 달을 바라봐");
        NSURL *url = [out URLByAppendingPathComponent:[NSString stringWithFormat:@"%@-blank-over.mp4", flat[0]]];
        BOOL written = SGLyricsClipWriteOverMotion(url, source, p, l, t, nil, 0, 2, SGLyricsClipOverArtwork, nil);
        CGImageRef preview = SGLyricsClipMotionFrame(source, p, l, t, nil, 0, 2, SGLyricsClipOverArtwork), first = frameAt(url, 0);
        if (!written || !preview || !first) {
            check(NO, [NSString stringWithFormat:@"%@: written and read back", flat[0]]);
        } else {
            size_t w, h;
            uint8_t *q = pixelsOf(preview, &w, &h);
            int most = 0, least = 255;
            for (size_t i = 0; i < w * h * 4; i++) if (i % 4 != 3) most = MAX(most, q[i]), least = MIN(least, q[i]);
            free(q);
            double behind = linear(most) + 0.05;
            double line = 1.05 / behind, dimmed = (linear(255 * (0.5 + 0.5 * most / 255.0)) + 0.05) / behind;
            int level = [flat[2] intValue];
            check(most - least <= 2, [NSString stringWithFormat:@"%@: the whole frame darkened evenly (%d to %d of 255)", flat[0], least, most]);
            if (level == 255)
                check(least >= 64 && most <= 82 && line >= 4.5 && dimmed >= 3.3,
                      [NSString stringWithFormat:@"white: to grey, %d of 255; the line %.2f:1, a dimmed line %.2f:1", most, line, dimmed]);
            else
                check(most <= round(level * 0.7) + 1, [NSString stringWithFormat:@"grey: darkened by at least 30%% (%d of %d)", most, level]);
            double apart = fabs(meanIn(first, 0, 1) - meanIn(preview, 0, 1));
            check(apart < 3, [NSString stringWithFormat:@"%@: the clip's first frame is the preview (%.1f of 255 apart)", flat[0], apart]);
        }
        CGImageRelease(preview);
        CGImageRelease(first);
    }

    // Over a video dark at its start and bright later, the band is as dark as the brightest of the clip's stretch
    // asks, from its first frame on, and the preview for that stretch agrees. Judged by the first frame alone, as
    // before, it kept kBandDim's 0.4 of the picture, which the stretch over the grey alone still gives.
    printf("\na video dark at its start and bright later\n");
    NSURL *dusk = [out URLByAppendingPathComponent:@"source-dusk.mp4"];
    check(makeVideo(dusk, 720, 960, 30, 6, drawDusk), @"made it, 720x960, 30 fps, 6 s: 2 s of mid grey, then the flag");
    {
        // The lines as spaces, so the rows looked at hold the picture alone.
        NSString *p = blanked(@"(And I turn into a stalker)"), *l = blanked(@"I stare at the moon"), *n = blanked(@"When nighttime comes");
        NSURL *url = [out URLByAppendingPathComponent:@"dusk-blank.mp4"];
        start = CFAbsoluteTimeGetCurrent();
        BOOL written = SGLyricsClipWriteOverMotion(url, dusk, p, l, nil, n, 0, 3.5, left, nil);
        double ms = (CFAbsoluteTimeGetCurrent() - start) * 1000;
        check(written, [NSString stringWithFormat:@"0 to 3.5 s written in %.0f ms, %.1f ms a frame", ms, ms / 105]);
        CGImageRef first = frameAt(url, 0), late = frameAt(url, 3), sourceFirst = frameAt(dusk, 0), sourceLate = frameAt(dusk, 3);
        CGImageRef preview = SGLyricsClipMotionFrame(dusk, p, l, nil, n, 0, 3.5, left);
        CGImageRef early = SGLyricsClipMotionFrame(dusk, p, l, nil, n, 0, 1.5, left);
        if (written && first && late && sourceFirst && sourceLate && preview && early) {
            double grey = meanIn(sourceFirst, 0.3, 0.5);
            double keptEarly = meanIn(early, 0.3, 0.5) / grey, keptFirst = meanIn(first, 0.3, 0.5) / grey;
            double keptPreview = meanIn(preview, 0.3, 0.5) / grey, keptLate = meanIn(late, 0.3, 0.5) / meanIn(sourceLate, 0.3, 0.5);
            check(fabs(keptEarly - 0.4) < 0.03,
                  [NSString stringWithFormat:@"over 0 to 1.5 s, the grey alone, the band keeps %.2f of the picture, as first-frame fitting did", keptEarly]);
            check(keptFirst < keptEarly * 0.8 && keptLate < keptEarly * 0.8,
                  [NSString stringWithFormat:@"over 0 to 3.5 s it is darker from the first frame on: keeps %.2f at 0 s and %.2f at 3 s, "
                   "against %.2f by the first frame", keptFirst, keptLate, keptEarly]);
            check(fabs(keptPreview - keptFirst) < 0.02,
                  [NSString stringWithFormat:@"the preview for the same stretch has the same band (keeps %.2f, the clip %.2f)", keptPreview, keptFirst]);
        } else {
            check(NO, @"frames read back");
        }
        CGImageRelease(first);
        CGImageRelease(late);
        CGImageRelease(sourceFirst);
        CGImageRelease(sourceLate);
        CGImageRelease(preview);
        CGImageRelease(early);
    }
    printf("\nfootprint now %.1f MB, peak %.1f MB\n", footprintMB(NO), footprintMB(YES));
    printf("%s, clips in %s\n", failures ? "FAILED" : "all passed", out.path.UTF8String);
    return failures ? 1 : 0;
}
