// Public renderer contracts and review frames. REVIEW_ONLY renders a saved source snapshot, without checks.
#import <AVFoundation/AVFoundation.h>
#import <ImageIO/ImageIO.h>
#import <CoreText/CoreText.h>
#import <objc/runtime.h>
#import "Shared/LockScreenLyrics/SGLyricsClip.h"
#import "Shared/LyricsBackground/LyricsBackground.h"
#import "fixtures.h"

static int failures;
static BOOL renderingOnly;
static NSUInteger backgrounds;
// Only instrument the synchronous injected call, not other renderer work.
static _Thread_local NSUInteger refusedAllocationIndex;
static _Thread_local BOOL watchingOverlay;
static _Thread_local NSInteger liveBuffers;
static _Thread_local CGImageRef liveWords;
void *SGLyricsHarnessMalloc(size_t size) {
    if (refusedAllocationIndex && !--refusedAllocationIndex) return NULL;
    void *buffer = malloc(size);
    if (watchingOverlay && buffer) liveBuffers++;
    return buffer;
}
void SGLyricsHarnessFree(void *buffer) {
    if (watchingOverlay && buffer) liveBuffers--;
    free(buffer);
}
CGImageRef SGLyricsHarnessCrop(CGImageRef image, CGRect rect) {
    CGImageRef crop = CGImageCreateWithImageInRect(image, rect);
    if (watchingOverlay) liveWords = crop;
    return crop;
}
void SGLyricsHarnessRelease(CGImageRef image) {
    if (watchingOverlay && image == liveWords) liveWords = NULL;
    CGImageRelease(image);
}
CGImageRef SGLyricsHarnessBackground(CGImageRef cover, CGSize size, SGLyricsBackgroundStyle style) {
    backgrounds++;
    return SGLyricsBackgroundCreate(cover, size, style);
}
static NSUInteger refusedContextIndex;
CGContextRef SGLyricsHarnessCreateContext(void *data, size_t width, size_t height, size_t bits, size_t stride,
                                         CGColorSpaceRef space, uint32_t info) {
    if (refusedContextIndex && !--refusedContextIndex) return NULL;
    return CGBitmapContextCreate(data, width, height, bits, stride, space, info);
}
static CGFloat drawnColumnWidth, longestDrawnLine;
static CFIndex drawnLineCount, drawnTextLength;
static NSUInteger truncations;
CTLineRef SGLyricsHarnessTruncatedLine(CTLineRef line, double width, CTLineTruncationType type, CTLineRef token) {
    CTLineRef result = CTLineCreateTruncatedLine(line, width, type, token);
    if (result && type == kCTLineTruncationEnd && token) truncations++;
    return result;
}
// Interpose only the framework draw boundary in the harness. Measure the actual shaped CTLines
// delivered by production, then call Core Text unchanged; no copy of the layout algorithm.
void SGLyricsHarnessDrawFrame(CTFrameRef frame, CGContextRef context) {
    if (!context) { fputs("FAIL: text drawn into a NULL context\n", stderr); exit(1); }
    drawnColumnWidth = CGRectGetWidth(CGPathGetBoundingBox(CTFrameGetPath(frame)));
    CFArrayRef lines = CTFrameGetLines(frame);
    drawnLineCount = CFArrayGetCount(lines);
    drawnTextLength = CTFrameGetVisibleStringRange(frame).length;
    longestDrawnLine = 0;
    for (CFIndex i = 0; i < drawnLineCount; i++) {
        CTLineRef line = CFArrayGetValueAtIndex(lines, i);
        CGFloat width = CTLineGetTypographicBounds(line, NULL, NULL, NULL) - CTLineGetTrailingWhitespaceWidth(line);
        longestDrawnLine = MAX(longestDrawnLine, width);
    }
    CTFrameDraw(frame, context);
}
static void check(BOOL ok, NSString *message) {
    if (renderingOnly) return;
    printf("%s %s\n", ok ? "ok" : "FAIL", message.UTF8String);
    if (!ok) failures++;
}
static CGContextRef context(CGSize size) {
    CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGContextRef c = CGBitmapContextCreate(NULL, size.width, size.height, 8, 0, space,
                                          (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(space);
    return c;
}
static NSData *pixels(CGImageRef image) {
    CGSize size = CGSizeMake(CGImageGetWidth(image), CGImageGetHeight(image));
    CGContextRef c = context(size);
    CGContextDrawImage(c, (CGRect){CGPointZero, size}, image);
    NSData *data = [NSData dataWithBytes:CGBitmapContextGetData(c) length:CGBitmapContextGetBytesPerRow(c) * size.height];
    CGContextRelease(c);
    return data;
}
static CGImageRef solid(CGFloat value) {
    CGContextRef c = context(CGSizeMake(640, 640));
    CGContextSetRGBFillColor(c, value, value, value, 1);
    CGContextFillRect(c, CGRectMake(0, 0, 640, 640));
    CGImageRef image = CGBitmapContextCreateImage(c);
    CGContextRelease(c);
    return image;
}
static CGImageRef render(CGImageRef backdrop, CGImageRef cover, NSString *previous, NSString *line,
                         NSString *translation, CGSize size, SGLyricsClipLayout layout) {
    drawnColumnWidth = longestDrawnLine = 0;
    drawnLineCount = drawnTextLength = 0;
#ifdef SG_BASELINE
    return SGLyricsClipFrameWithLayout(backdrop, line, translation, nil, size, layout);
#else
    return SGLyricsClipFrameWithLayout(backdrop, cover, previous, line, translation, nil, size, layout);
#endif
}
static void save(CGImageRef image, NSString *dir, NSString *name, BOOL phone) {
    CGImageRef output = CGImageRetain(image);
    if (phone) {
        // IMG_1800's uncropped presentation: the full frame at screen width, starting 10% down.
        // Neutral space outside the frame is not simulated system chrome.
        CGFloat displayedHeight = 1179.0 * CGImageGetHeight(image) / CGImageGetWidth(image);
        CGContextRef c = context(CGSizeMake(1179, 2556));
        CGContextSetRGBFillColor(c, .08, .08, .08, 1);
        CGContextFillRect(c, CGRectMake(0, 0, 1179, 2556));
        CGContextDrawImage(c, CGRectMake(0, 2556 * .90 - displayedHeight, 1179, displayedHeight), image);
        CGImageRelease(output);
        output = CGBitmapContextCreateImage(c);
        CGContextRelease(c);
    }
    NSURL *url = [NSURL fileURLWithPath:[dir stringByAppendingPathComponent:name]];
    CGImageDestinationRef dest = CGImageDestinationCreateWithURL((__bridge CFURLRef)url, CFSTR("public.png"), 1, NULL);
    CGImageDestinationAddImage(dest, output, NULL);
    if (!CGImageDestinationFinalize(dest)) { fprintf(stderr, "could not save %s\n", name.UTF8String); failures++; }
    CFRelease(dest);
    CGImageRelease(output);
}
static CGRect bounds(CGImageRef image) {
    size_t w = CGImageGetWidth(image), h = CGImageGetHeight(image);
    NSData *data = pixels(image);
    const uint8_t *p = data.bytes;
    NSInteger left = w, right = -1, top = h, bottom = -1;
    for (NSInteger y = 0; y < h; y++) for (NSInteger x = 0; x < w; x++) {
        if (p[(y * w + x) * 4] < 100) continue;
        left = MIN(left, x); right = MAX(right, x); top = MIN(top, y); bottom = MAX(bottom, y);
    }
    return CGRectMake(left, top, right - left + 1, bottom - top + 1);
}
#ifndef SG_BASELINE
// Count the sampler's real seeks while the preview and encoder use the same file.
static NSUInteger bandSeeks;
static CGImageRef (*originalSeek)(id, SEL, CMTime, CMTime *, NSError **);
static CGImageRef countSeek(id generator, SEL cmd, CMTime time, CMTime *actual, NSError **error) {
    bandSeeks++;
    return originalSeek(generator, cmd, time, actual, error);
}

// JPEG in QuickTime preserves the odd raster height, including its last decoded row.
static BOOL writeOddMotion(NSURL *url) {
    const size_t w = 144, h = 257;
    AVAssetWriter *writer = [AVAssetWriter assetWriterWithURL:url fileType:AVFileTypeQuickTimeMovie error:nil];
    AVAssetWriterInput *input = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo
        outputSettings:@{AVVideoCodecKey:AVVideoCodecTypeJPEG, AVVideoWidthKey:@(w), AVVideoHeightKey:@(h)}];
    AVAssetWriterInputPixelBufferAdaptor *adaptor = [AVAssetWriterInputPixelBufferAdaptor
        assetWriterInputPixelBufferAdaptorWithAssetWriterInput:input sourcePixelBufferAttributes:nil];
    if (![writer canAddInput:input]) return NO;
    [writer addInput:input];
    if (![writer startWriting]) return NO;
    [writer startSessionAtSourceTime:kCMTimeZero];
    CVPixelBufferRef frame = NULL;
    if (CVPixelBufferCreate(NULL, w, h, kCVPixelFormatType_32BGRA, NULL, &frame) != kCVReturnSuccess) {
        [writer cancelWriting];
        return NO;
    }
    if (CVPixelBufferLockBaseAddress(frame, 0) != kCVReturnSuccess) {
        CVPixelBufferRelease(frame);
        [writer cancelWriting];
        return NO;
    }
    for (size_t y = 0; y < h; y++) {
        uint32_t *row = (uint32_t *)((uint8_t *)CVPixelBufferGetBaseAddress(frame) + y * CVPixelBufferGetBytesPerRow(frame));
        for (size_t x = 0; x < w; x++) row[x] = (x / 3) % 2 ? 0xffffffff : 0xff000000;
    }
    CVPixelBufferUnlockBaseAddress(frame, 0);
    BOOL appended = [adaptor appendPixelBuffer:frame withPresentationTime:kCMTimeZero];
    CVPixelBufferRelease(frame);
    if (!appended) { [writer cancelWriting]; return NO; }
    [input markAsFinished];
    [writer endSessionAtSourceTime:CMTimeMake(1, 1)];
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    [writer finishWritingWithCompletionHandler:^{ dispatch_semaphore_signal(done); }];
    return dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC)) == 0
        && writer.status == AVAssetWriterStatusCompleted;
}

static void checkOddMotion(NSString *dir) {
    NSURL *url = [NSURL fileURLWithPath:[dir stringByAppendingPathComponent:@"odd-source.mov"]];
    BOOL written = writeOddMotion(url);
    check(written, @"odd-height stripe video written");
    if (!written) return;
    AVAssetTrack *track = [[AVURLAsset URLAssetWithURL:url options:nil] tracksWithMediaType:AVMediaTypeVideo].firstObject;
    check(track.naturalSize.height == 257, @"odd-height source retains all 257 rows");
    for (NSNumber *layout in @[@(SGLyricsClipLeft), @(SGLyricsClipOverArtwork)]) {
        CGImageRef preview = SGLyricsClipMotionFrame(url, nil, nil, nil, nil, 0, 1, layout.integerValue);
        check(preview && CGImageGetHeight(preview) == 192, @"odd-height source renders the full 3:4 crop");
        if (!preview) continue;
        NSData *data = pixels(preview);
        size_t w = CGImageGetWidth(preview), h = CGImageGetHeight(preview);
        const uint8_t *lastRow = (const uint8_t *)data.bytes + (h - 1) * w * 4;
        int low = 255, high = 0;
        for (size_t x = 16; x < w - 16; x++) {
            low = MIN(low, lastRow[x * 4]);
            high = MAX(high, lastRow[x * 4]);
        }
        if (layout.integerValue == SGLyricsClipLeft) check(high - low > 90, @"last row contains sharp source stripes");
        else check(high - low < 10, @"whole-artwork blur reaches the last row of an odd-height video");
        CGImageRelease(preview);
    }
}

static void checkFonts(CGImageRef blank, CGSize size) {
    SGLyricsClipFont imported = {SGLyricsClipFontFamily, @"Georgia", @"first-import"};
    NSString *originalLook = SGLyricsClipLookWithFont(nil, SGLyricsClipStill, SGLyricsClipLeft, NO, SGLyricsClipTextMedium, imported);
    imported.importRevision = @"replacement";
    check(![originalLook isEqual:SGLyricsClipLookWithFont(nil, SGLyricsClipStill, SGLyricsClipLeft, NO, SGLyricsClipTextMedium, imported)],
          @"reimporting the same family changes the artwork ID");
    NSString *line = @"Evening 11시 夜";
    SGLyricsClipFont faces[] = {{SGLyricsClipFontRounded, nil}, {SGLyricsClipFontSerif, nil},
        {SGLyricsClipFontMono, nil}, {SGLyricsClipFontFamily, @"Georgia"}, {SGLyricsClipFontFamily, @"Menlo"}};
    for (SGLyricsClipLayout layout = SGLyricsClipLeft; layout <= SGLyricsClipOverArtwork; layout++) {
        CGImageRef system = SGLyricsClipFrameWithLayout(blank, NULL, nil, line, @"번역", @"Next", size, layout);
        check(system != NULL, @"system font reference rendered");
        NSData *reference = system ? pixels(system) : nil;
        CGImageRelease(system);
        if (layout == SGLyricsClipLeft) {
            SGLyricsClipFont missing = {SGLyricsClipFontFamily, @"Retrine Missing Font Fixture"};
            CGImageRef fallback = SGLyricsClipFrameWithFont(blank, NULL, nil, line, @"번역", @"Next", size, layout, SGLyricsClipTextMedium, missing);
            check(fallback && [reference isEqual:pixels(fallback)], @"an unavailable family uses the original system faces");
            CGImageRelease(fallback);
        }
        NSMutableSet *looks = [NSMutableSet setWithObject:SGLyricsClipLook(nil, SGLyricsClipStill, layout, NO)];
        for (size_t i = 0; i < sizeof(faces) / sizeof(faces[0]); i++) {
            SGLyricsClipFont face = faces[i];
            CGImageRef styled = SGLyricsClipFrameWithFont(blank, NULL, nil, line, @"번역", @"Next", size, layout, SGLyricsClipTextMedium, face);
            check(styled && ![reference isEqual:pixels(styled)], [NSString stringWithFormat:@"font %zu changes the pixels of layout %ld", i, (long)layout]);
            CGImageRelease(styled);
            [looks addObject:SGLyricsClipLookWithFont(nil, SGLyricsClipStill, layout, NO, SGLyricsClipTextMedium, face)];
        }
        check(looks.count == 6, @"system, three designs and two named families get distinct artwork IDs");
    }
}

static void checkTextSizes(CGImageRef blank, CGSize size) {
    NSString *overflow = [@"" stringByPaddingToLength:4000 withString:@"夜空に光る星を数えながら" startingAtIndex:0];
    for (SGLyricsClipLayout layout = SGLyricsClipLeft; layout <= SGLyricsClipOverArtwork; layout++) {
        CGFloat previousWidth = 0;
        for (SGLyricsClipTextSize choice = SGLyricsClipTextSmall; choice <= SGLyricsClipTextLarge; choice++) {
            longestDrawnLine = 0;
            CGImageRef shortLine = SGLyricsClipFrameWithTextSize(blank, NULL, nil, @"Hold", nil, nil, size, layout, choice);
            check(shortLine && longestDrawnLine > previousWidth,
                  [NSString stringWithFormat:@"short line grows with text size (layout %ld, size %ld)", (long)layout, (long)choice]);
            previousWidth = longestDrawnLine;
            CGImageRelease(shortLine);

            truncations = 0;
            CGImageRef longLine = SGLyricsClipFrameWithTextSize(blank, NULL, @"Before", overflow, @"번역",
                                                                @"After", size, layout, choice);
            CGRect ink = longLine ? bounds(longLine) : CGRectZero;
            CGFloat screenPerPixel = 1179.0 / (2556 * size.width);
            check(truncations && ink.size.height > 0 && .10 + CGRectGetMinY(ink) * screenPerPixel >= .17
                  && .10 + CGRectGetMaxY(ink) * screenPerPixel <= .65,
                  [NSString stringWithFormat:@"overflow ends in an ellipsis inside the safe band (layout %ld, size %ld)",
                   (long)layout, (long)choice]);
            CGImageRelease(longLine);
        }
    }
    for (int moving = 0; moving <= 1; moving++) {
        NSURL *source = moving ? [NSURL fileURLWithPath:@"/motion.mp4"] : nil;
        NSMutableSet *looks = [NSMutableSet set];
        for (SGLyricsClipTextSize choice = SGLyricsClipTextSmall; choice <= SGLyricsClipTextLarge; choice++)
            [looks addObject:SGLyricsClipLookWithTextSize(source, SGLyricsClipStill, SGLyricsClipLeft, NO, choice)];
        NSString *medium = SGLyricsClipLookWithTextSize(source, SGLyricsClipStill, SGLyricsClipLeft, NO, SGLyricsClipTextMedium);
        check(looks.count == 3 && [SGLyricsClipLook(source, SGLyricsClipStill, SGLyricsClipLeft, NO) isEqual:medium] &&
              [SGLyricsClipLookWithTextSize(source, SGLyricsClipStill, SGLyricsClipLeft, NO, -1) isEqual:medium] &&
              [SGLyricsClipLookWithTextSize(source, SGLyricsClipStill, SGLyricsClipLeft, NO, 3) isEqual:medium],
              source ? @"motion IDs distinguish all sizes and default to Medium" : @"still IDs distinguish all sizes and default to Medium");
    }
}
#endif
static double linear(double v) { return v <= .04045 ? v / 12.92 : pow((v + .055) / 1.055, 2.4); }

int main(int argc, char **argv) {
    @autoreleasepool {
        if (argc != 3) return 2;
        renderingOnly = getenv("REVIEW_ONLY") != NULL;
        if (renderingOnly) puts("Reference rendering only; no regression checks run.");
        NSString *dir = [NSString stringWithUTF8String:argv[1]];
        [NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
        CGSize size = SGLyricsClipSize(1179);
        NSString *previous = @"Once a cocoa butter dreamer";
        NSString *line = @"You made me your brown sugar believer, now I can fly";
        NSString *translation = @"네 브라운 슈가의 신봉자가 되었어, 이제 난 날 수 있어";
        CGImageRef black = solid(0), white = solid(1), cover = newCover();
        CGImageRef backdrop = SGLyricsClipBackdrop(cover, size);
        if (!renderingOnly) {
            backgrounds = 0;
            CGImageRef dim = SGLyricsClipDimmedArtwork(cover, size);
            check(dim && backgrounds == 1, @"dimmed artwork needs only one blur");
            CGImageRef again = SGLyricsClipDimmedArtwork(cover, size);
            check(again == dim && backgrounds == 1, @"another demand reuses the final dimmed pixels");
            CGImageRelease(again);
            CGImageRelease(dim);
            // An asymmetric dark cover needs only the minimum dim, independent of the contrast search.
            CGContextRef dark = context(size);
            CGContextDrawImage(dark, (CGRect){CGPointZero, size}, cover);
            CGContextSetRGBFillColor(dark, 0, 0, 0, .95);
            CGContextFillRect(dark, (CGRect){CGPointZero, size});
            CGImageRef source = CGBitmapContextCreateImage(dark);
            CGContextRelease(dark);
            CGImageRef reference = SGLyricsBackgroundCreate(source, size, (SGLyricsBackgroundStyle){SGLyricsBackgroundBlur, 77 / 256., 20, 0});
            dim = SGLyricsClipDimmedArtwork(source, size);
            NSData *expected = pixels(reference), *actual = pixels(dim);
            const uint8_t *a = actual.bytes, *b = expected.bytes;
            int difference = 0;
            for (NSUInteger i = 0; i < actual.length; i++) difference = MAX(difference, abs(a[i] - b[i]));
            check(difference <= 1, @"single-pass dim keeps reference pixels and orientation within rounding");
            CGImageRelease(reference); CGImageRelease(dim); CGImageRelease(source);
            refusedContextIndex = 1;
            check(!SGLyricsClipDimmedArtwork(cover, CGSizeMake(64, 64)), @"new raster with missing measurement context returns no dimmed image");
            for (NSUInteger index = 1; index <= 2; index++) {
                refusedContextIndex = index;
                CGImageRef frame = render(backdrop, cover, nil, @"Line", nil, size, SGLyricsClipCentered);
                check(!frame, index == 1 ? @"missing required words returns no preview" : @"missing final context returns no preview");
                CGImageRelease(frame);
            }
        }
        CGImageRef blank = SGLyricsBackgroundCreate(black, size, (SGLyricsBackgroundStyle){SGLyricsBackgroundCover, 0, 0, 0});
#ifndef SG_BASELINE
        if (!renderingOnly) {
            checkOddMotion([@(argv[2]) stringByDeletingLastPathComponent]);
            checkFonts(blank, size);
            checkTextSizes(blank, size);
        }
#endif
        for (SGLyricsClipLayout layout = SGLyricsClipLeft; layout <= SGLyricsClipPoster; layout++) {
            CGImageRef words = render(blank, black, previous, line, translation, size, layout);
            if (layout != SGLyricsClipPoster)
                check(drawnLineCount > 2 && drawnTextLength >= (CFIndex)(line.length + 1 + translation.length),
                      [NSString stringWithFormat:@"reported lyric and translation both fit with natural wrapping (%ld lines)", (long)drawnLineCount]);
            CGRect b = bounds(words);
            CGFloat screen = size.width, left = 0;
            CGFloat screenTop = .10 + b.origin.y / size.width * 1179 / 2556;
            CGFloat screenBottom = .10 + CGRectGetMaxY(b) / size.width * 1179 / 2556;
            check(screenTop >= .17 && screenBottom <= .65,
                  @"existing layout text stays between 17% and 65%");
            check(fabs((screenTop + screenBottom) / 2 - .40) < .025,
                  @"existing layout is centred 40% down the screen, not the frame");
            if (layout != SGLyricsClipCentered)
                check(fabs((b.origin.x - left) / screen - .08) < .015, @"existing layout keeps the 8% visible-screen margin");
            else
                check(fabs(CGRectGetMidX(b) - size.width / 2) < screen * .02, @"Centered stays centred");
            CGImageRelease(words);
        }
        // Messages is a bubble scene, not a page-wide text column.
        for (NSNumber *value in @[@(SGLyricsClipLeft), @(SGLyricsClipCentered), @(SGLyricsClipPoster),
                                  @(SGLyricsClipVinyl), @(SGLyricsClipOverArtwork)]) {
            CGImageRef wide = render(blank, black, nil,
                @"And every word I never said keeps ringing out across the quiet of the night until the morning finds us again.",
                nil, size, value.integerValue);
            check(fabs(drawnColumnWidth - size.width * .84) <= 1,
                  [NSString stringWithFormat:@"text column is 84%% of visible width (layout %@: %.3f)", value, drawnColumnWidth / size.width]);
            check(longestDrawnLine > size.width * .70 && longestDrawnLine <= size.width * .84 + 1,
                  [NSString stringWithFormat:@"laid-out sentence spans over 70%% of visible width (layout %@: %.3f)", value, longestDrawnLine / size.width]);
            CGImageRelease(wide);
        }
        CGImageRef defaultFrame = render(backdrop, cover, previous, line, translation, size, SGLyricsClipLeft);
        save(defaultFrame, dir, @"default-phone.png", YES);
        // Moving-artwork Left is the only old layout that shows the previous line and a local blur/dim band.
        NSURL *video = [NSURL fileURLWithPath:[dir stringByAppendingPathComponent:@"fixture.mp4"]];
#ifdef SG_BASELINE
        BOOL written = SGLyricsClipWriteWithLayout(video, backdrop, nil, nil, nil, size, SGLyricsClipStill, SGLyricsClipLeft);
#else
        BOOL written = SGLyricsClipWriteWithLayout(video, backdrop, cover, nil, nil, nil, nil, size, SGLyricsClipStill, SGLyricsClipLeft, nil);
#endif
        check(written, @"motion fixture written");
        CGImageRef motion = written ? SGLyricsClipMotionFrame(video, previous, line, translation, nil, 0, 2, SGLyricsClipLeft) : NULL;
        check(motion != NULL, @"reported previous/current/translation case renders");
        if (motion) {
            save(motion, dir, @"motion-left-phone.png", YES);
        }
#ifndef SG_BASELINE
        if (!renderingOnly && written) {
            NSURL *leased = [NSURL fileURLWithPath:@(argv[2])];
            Method seek = class_getInstanceMethod(AVAssetImageGenerator.class, @selector(copyCGImageAtTime:actualTime:error:));
            originalSeek = (void *)method_setImplementation(seek, (IMP)countSeek);
            CGFloat previousWidth = 0;
            for (SGLyricsClipTextSize choice = SGLyricsClipTextSmall; choice <= SGLyricsClipTextLarge; choice++) {
                longestDrawnLine = 0;
                CGImageRef preview = SGLyricsClipMotionFrameWithTextSize(video, nil, @"Hold", nil, nil, 0, 2,
                                                                         SGLyricsClipLeft, choice);
                NSUInteger afterPreview = bandSeeks;
                CGFloat previewWidth = longestDrawnLine;
                longestDrawnLine = 0;
                BOOL encoded = SGLyricsClipWriteOverMotionWithTextSize(leased, video, nil, @"Hold", nil, nil, 0, 2,
                                                                      SGLyricsClipLeft, choice, nil);
                check(preview && encoded && previewWidth > previousWidth && fabs(longestDrawnLine - previewWidth) < 1,
                      [NSString stringWithFormat:@"motion preview and clip share the selected text size (%ld)", (long)choice]);
                check(afterPreview && bandSeeks == afterPreview, @"video reuses the preview’s measured darkness without more seeks");
                CGImageRelease(preview);
                previousWidth = previewWidth;
                [NSFileManager.defaultManager removeItemAtURL:leased error:nil];
            }
            NSUInteger previousSeeks = bandSeeks;
            NSError *dateError = nil;
            check([NSFileManager.defaultManager setAttributes:@{NSFileModificationDate: [NSDate dateWithTimeIntervalSince1970:123456789]}
                                                 ofItemAtPath:video.path error:&dateError], @"fixture revision updated");
            CGImageRef revised = SGLyricsClipMotionFrameWithTextSize(video, nil, @"Hold", nil, nil, 0, 2, SGLyricsClipLeft, SGLyricsClipTextLarge);
            check(revised && bandSeeks > previousSeeks, @"changing the file revision measures the stretch again");
            CGImageRelease(revised);
            method_setImplementation(seek, (IMP)originalSeek);
            NSData *original = [@"leased clip" dataUsingEncoding:NSUTF8StringEncoding];
            check([original writeToURL:leased atomically:YES], @"existing clip seeded");
            BOOL replaced = SGLyricsClipWriteOverMotion(leased, video, nil, line, nil, nil, 0, 2, SGLyricsClipLeft, nil);
            check(!replaced && [[NSData dataWithContentsOfURL:leased] isEqual:original] &&
                  ![NSFileManager.defaultManager fileExistsAtPath:[leased URLByAppendingPathExtension:@"partial"].path],
                  @"motion publish collision preserves the leased file and discards the partial");
            [NSFileManager.defaultManager removeItemAtURL:leased error:nil];
            for (NSNumber *layout in @[@(SGLyricsClipLeft), @(SGLyricsClipOverArtwork)]) {
                for (NSUInteger index = 1; index <= 4; index++) {
                    refusedAllocationIndex = index;
                    watchingOverlay = YES;
                    CGImageRef preview = SGLyricsClipMotionFrame(video, nil, line, nil, nil, 0, 2, layout.integerValue);
                    watchingOverlay = NO;
                    check(!liveWords && liveBuffers == 0, @"failed preview releases the words image and overlay buffers");
                    check(!preview && !refusedAllocationIndex, @"missing overlay buffer yields no motion preview");
                    CGImageRelease(preview);
                    refusedAllocationIndex = index;
                    watchingOverlay = YES;
                    BOOL encoded = SGLyricsClipWriteOverMotion(leased, video, nil, line, nil, nil, 0, 2, layout.integerValue, nil);
                    watchingOverlay = NO;
                    check(!liveWords && liveBuffers == 0, @"failed encode releases the words image and overlay buffers");
                    check(!encoded && !refusedAllocationIndex && ![NSFileManager.defaultManager fileExistsAtPath:leased.path] &&
                          ![NSFileManager.defaultManager fileExistsAtPath:[leased URLByAppendingPathExtension:@"partial"].path],
                          @"missing overlay buffer yields no motion clip or partial");
                }
            }
        }
#endif
        [NSFileManager.defaultManager removeItemAtURL:video error:nil];
#ifndef SG_BASELINE
        check(SGLyricsClipOverArtwork == 5, @"new stored layout is appended at index 5");
        CGImageRef dark = render(NULL, black, previous, line, translation, size, SGLyricsClipOverArtwork);
        CGImageRef bright = render(NULL, white, previous, line, translation, size, SGLyricsClipOverArtwork);
        CGRect b = bounds(dark);
        check(.10 + b.origin.y / size.width * 1179 / 2556 >= .17
              && .10 + CGRectGetMaxY(b) / size.width * 1179 / 2556 <= .65,
              @"OverArtwork words stay in the safe region");
        NSData *darkBytes = pixels(dark), *brightBytes = pixels(bright);
        const uint8_t *d = darkBytes.bytes, *p = brightBytes.bytes;
        size_t w = size.width, h = size.height;
        int brightest = 0;
        for (size_t y = ceil(b.origin.y); y < floor(CGRectGetMaxY(b)); y++)
            for (size_t x = ceil(b.origin.x); x < floor(CGRectGetMaxX(b)); x++)
                if (d[(y * w + x) * 4] == 0) brightest = MAX(brightest, p[(y * w + x) * 4]);
        double background = brightest / 255.0;
        double contrast = (linear(.5 + .5 * background) + .05) / (linear(background) + .05);
        double currentContrast = 1.05 / (linear(background) + .05);
        if (!renderingOnly) printf("white-cover contrast: current %.2f:1, dim %.2f:1\n", currentContrast, contrast);
        check(currentContrast >= 4.5 && contrast >= 3, @"current 4.5:1 and dimmed 3:1 contrast on white");
        // The blank row just above the first glyph still crosses the gradient: no text or shadow contamination.
        size_t row = MAX((NSInteger)b.origin.y - 12, 0);
        int last = -1; BOOL rising = YES;
        for (int column = 1; column <= 4; column++) {
            int value = p[(row * w + MIN(w * column / 4, w - 1)) * 4];
            if (last >= 0 && value <= last) rising = NO;
            last = value;
        }
        check(rising, @"side gradient continuously fades across the frame with no flat plateau");
        int largestStep = 0;
        for (size_t y = 1; y < floor(b.origin.y); y++) {
            size_t current = (y * w + w / 2) * 4, previous = ((y - 1) * w + w / 2) * 4;
            if (d[current] || d[previous]) continue; // compare background, not antialiased letter edges
            largestStep = MAX(largestStep, abs(p[current] - p[previous]));
        }
        check(largestStep <= 4, @"scrim fades smoothly into the cover without a hard band");
        // Distinct input edges far from the words must remain sharp, not pass through default blur.
        CGImageRef pattern = render(NULL, cover, nil, nil, nil, size, SGLyricsClipOverArtwork);
        CGImageRef sharp = SGLyricsBackgroundCreate(cover, size, (SGLyricsBackgroundStyle){SGLyricsBackgroundCover, 0, 0, 0});
        check([pixels(pattern) isEqual:pixels(sharp)], @"cover is sharp aspect fill with no blur or global darkening");
        CGContextRef darkContext = context(CGSizeMake(640, 640));
        CGContextDrawImage(darkContext, CGRectMake(0, 0, 640, 640), cover);
        CGContextSetRGBFillColor(darkContext, 0, 0, 0, .88);
        CGContextFillRect(darkContext, CGRectMake(0, 0, 640, 640));
        CGImageRef darkCover = CGBitmapContextCreateImage(darkContext);
        CGContextRelease(darkContext);
        CGImageRef darkAfter = render(NULL, darkCover, previous, line, translation, size, SGLyricsClipOverArtwork);
        save(bright, dir, @"bright-after.png", YES);
        save(darkAfter, dir, @"dark-after.png", YES);
        CGImageRef patterned = render(NULL, cover, previous, line, translation, size, SGLyricsClipOverArtwork);
        save(patterned, dir, @"artwork-after.png", YES);
        for (SGLyricsClipStyle style = SGLyricsClipStill; style <= SGLyricsClipAnimated; style++) {
            check(SGLyricsClipWriteWithLayout(video, NULL, cover, previous, line, translation, nil, size, style, SGLyricsClipOverArtwork, nil),
                  @"OverArtwork encodes in both styles");
            AVURLAsset *asset = [AVURLAsset URLAssetWithURL:video options:nil];
            check(fabs(CMTimeGetSeconds(asset.duration) - (style == SGLyricsClipStill ? 2 : 4)) < .01,
                  @"OverArtwork has the existing style duration");
            AVAssetReader *reader = [AVAssetReader assetReaderWithAsset:asset error:nil];
            AVAssetReaderTrackOutput *out = [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:
                [asset tracksWithMediaType:AVMediaTypeVideo].firstObject outputSettings:nil];
            [reader addOutput:out]; [reader startReading];
            int count = 0; CMSampleBufferRef sample;
            while ((sample = [out copyNextSampleBuffer])) { if (CMSampleBufferGetNumSamples(sample)) count++; CFRelease(sample); }
            check(count == (style == SGLyricsClipStill ? 1 : 60),
                  [NSString stringWithFormat:@"OverArtwork retains still/animated frame counts (%d)", count]);
            [NSFileManager.defaultManager removeItemAtURL:video error:nil];
        }
        CGImageRelease(dark); CGImageRelease(bright); CGImageRelease(pattern); CGImageRelease(sharp);
        CGImageRelease(patterned);
        CGImageRelease(darkCover); CGImageRelease(darkAfter);
#endif
        CGImageRelease(motion); CGImageRelease(defaultFrame); CGImageRelease(backdrop);
        CGImageRelease(blank); CGImageRelease(black); CGImageRelease(white); CGImageRelease(cover);
        return failures ? 1 : 0;
    }
}
