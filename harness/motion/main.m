// Runs the steps of moving artwork that need no phone (Shared/AnimatedArtwork/SGMotionClip.m) on the Mac:
// the cut's size, a tall clip cut to 3:4 and read back (its size, its frames, and that it was cut about its
// middle rather than squeezed), a clip stored on its side, Spotify's Canvas service's request and reply,
// and when a Canvas that turned up late is asked for. Exits 1 on any failure.
#import <AVFoundation/AVFoundation.h>
#import "Shared/AdBlock/Protobuf.h"
#import "Shared/AnimatedArtwork/SGMotionClip.h"

static int failures;

// First demand withholds readiness until the producer registers its callback. Only the production translation unit
// uses these selectors; the underlying AVFoundation writer is unmodified.
static BOOL registeredDemand;
static BOOL stall, refuseAppend;
// Only the terminal fault is synthetic. Forward setup to the real writer so
// the failure occurs with its session open and its partial on disk.
@interface StalledWriter : NSObject
@property (nonatomic, strong) AVAssetWriter *writer;
@property AVAssetWriterStatus status;
@end
@implementation StalledWriter
- (id)forwardingTargetForSelector:(SEL)selector { return _writer; }
@end
static StalledWriter *stalledWriter;
@implementation AVAssetWriter (ShapeFixture)
+ (id)fixtureWriterWithURL:(NSURL *)url fileType:(AVFileType)type error:(NSError **)error {
    AVAssetWriter *writer = [self assetWriterWithURL:url fileType:type error:error];
    if (!stalledWriter) return writer;
    stalledWriter.writer = writer;
    stalledWriter.status = AVAssetWriterStatusWriting;
    return stalledWriter;
}
@end
static NSUInteger stalledReads;
@implementation AVAssetWriterInput (ShapeFixture)
- (BOOL)isFixtureReady {
    if (stall && !registeredDemand) {
        fputs("FAIL: producer polled the blocked writer before the readiness callback\n", stderr);
        exit(1);
    }
    return self.readyForMoreMediaData;
}
- (void)fixtureRequestOnQueue:(dispatch_queue_t)queue usingBlock:(dispatch_block_t)feed {
    if (stalledWriter) {
        dispatch_async(queue, ^{
            [stalledWriter.writer cancelWriting];
            stalledWriter.status = AVAssetWriterStatusFailed;
        });
        return; // no readiness callback, even after failure
    }
    dispatch_async(queue, ^{
        if (stall) registeredDemand = YES;
        [self requestMediaDataWhenReadyOnQueue:queue usingBlock:feed];
    });
}
- (BOOL)fixtureAppend:(CMSampleBufferRef)sample {
    return !refuseAppend && [self appendSampleBuffer:sample];
}
@end

static void check(BOOL ok, NSString *what) {
    printf("  %s %s\n", ok ? "ok  " : "FAIL", what.UTF8String);
    if (!ok) failures++;
}

// A stand-in Canvas, `size` as stored, of `count` frames at 30 fps, in three bands from the top as shown:
// red to a quarter, green to three quarters, blue below. `turn` stands it up when it is stored on its side.
static BOOL writeBands(NSURL *file, CGSize size, int count, CGAffineTransform turn, BOOL sideways) {
    [NSFileManager.defaultManager removeItemAtURL:file error:nil];
    AVAssetWriter *writer = [AVAssetWriter assetWriterWithURL:file fileType:AVFileTypeMPEG4 error:nil];
    AVAssetWriterInput *input = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:@{
        AVVideoCodecKey: AVVideoCodecTypeH264, AVVideoWidthKey: @(size.width), AVVideoHeightKey: @(size.height),
    }];
    input.transform = turn;
    AVAssetWriterInputPixelBufferAdaptor *adaptor = [AVAssetWriterInputPixelBufferAdaptor assetWriterInputPixelBufferAdaptorWithAssetWriterInput:input
        sourcePixelBufferAttributes:@{(id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA),
                                      (id)kCVPixelBufferWidthKey: @(size.width), (id)kCVPixelBufferHeightKey: @(size.height)}];
    [writer addInput:input];
    [writer startWriting];
    [writer startSessionAtSourceTime:kCMTimeZero];
    for (int i = 0; i < count; i++) {
        while (!input.readyForMoreMediaData) [NSThread sleepForTimeInterval:0.002];
        CVPixelBufferRef buffer = NULL;
        CVPixelBufferPoolCreatePixelBuffer(NULL, adaptor.pixelBufferPool, &buffer);
        CVPixelBufferLockBaseAddress(buffer, 0);
        uint8_t *base = CVPixelBufferGetBaseAddress(buffer);
        size_t row = CVPixelBufferGetBytesPerRow(buffer);
        for (size_t y = 0; y < size.height; y++) {
            for (size_t x = 0; x < size.width; x++) {
                // Along the shown picture's height: the stored rows, or, on its side, the stored columns.
                double along = sideways ? (double)x / size.width : (double)y / size.height;
                uint8_t *pixel = base + y * row + x * 4;   // BGRA
                pixel[0] = along >= 0.75 ? 255 : 0;
                pixel[1] = along >= 0.25 && along < 0.75 ? 255 : 0;
                pixel[2] = along < 0.25 ? 255 : 0;
                pixel[3] = 255;
            }
        }
        CVPixelBufferUnlockBaseAddress(buffer, 0);
        [adaptor appendPixelBuffer:buffer withPresentationTime:CMTimeMake(i, 30)];
        CVPixelBufferRelease(buffer);
    }
    [input markAsFinished];
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    [writer finishWritingWithCompletionHandler:^{ dispatch_semaphore_signal(done); }];
    dispatch_semaphore_wait(done, DISPATCH_TIME_FOREVER);
    return writer.status == AVAssetWriterStatusCompleted;
}

static AVAssetTrack *videoOf(NSURL *file) {
    __block AVAssetTrack *track = nil;
    dispatch_semaphore_t loaded = dispatch_semaphore_create(0);
    [[AVURLAsset assetWithURL:file] loadTracksWithMediaType:AVMediaTypeVideo completionHandler:^(NSArray *tracks, NSError *error) {
        track = tracks.firstObject;
        dispatch_semaphore_signal(loaded);
    }];
    dispatch_semaphore_wait(loaded, DISPATCH_TIME_FOREVER);
    return track;
}

static int framesIn(NSURL *file) {
    AVAssetTrack *track = videoOf(file);
    AVAssetReader *reader = [AVAssetReader assetReaderWithAsset:track.asset error:nil];
    AVAssetReaderTrackOutput *output = [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:track outputSettings:nil];
    [reader addOutput:output];
    [reader startReading];
    int count = 0;
    CMSampleBufferRef sample;
    while ((sample = [output copyNextSampleBuffer])) {
        if (CMSampleBufferGetNumSamples(sample)) count++;
        CFRelease(sample);
    }
    return count;
}

// The color at `y`, a share of the shown picture's height, in its middle column: 'r', 'g', 'b' or '?'.
static char colourAt(NSURL *file, double y) {
    AVAssetImageGenerator *generator = [AVAssetImageGenerator assetImageGeneratorWithAsset:[AVURLAsset assetWithURL:file]];
    generator.appliesPreferredTrackTransform = YES;
    generator.requestedTimeToleranceBefore = generator.requestedTimeToleranceAfter = kCMTimeZero;
    __block CGImageRef image = NULL;
    dispatch_semaphore_t made = dispatch_semaphore_create(0);
    [generator generateCGImageAsynchronouslyForTime:kCMTimeZero completionHandler:^(CGImageRef frame, CMTime actual, NSError *error) {
        image = frame ? CGImageRetain(frame) : NULL;
        dispatch_semaphore_signal(made);
    }];
    dispatch_semaphore_wait(made, DISPATCH_TIME_FOREVER);
    if (!image) return '?';
    size_t width = CGImageGetWidth(image), height = CGImageGetHeight(image);
    uint8_t pixel[4] = {0};
    CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGContextRef context = CGBitmapContextCreate(pixel, 1, 1, 8, 4, space, (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
    // The one pixel wanted lands on the 1x1 context: Core Graphics counts rows from the bottom.
    CGContextDrawImage(context, CGRectMake(-(double)(width / 2), -(double)height * (1 - y), width, height), image);
    CGContextRelease(context);
    CGColorSpaceRelease(space);
    CGImageRelease(image);
    if (pixel[0] > 160 && pixel[1] < 90 && pixel[2] < 90) return 'r';
    if (pixel[1] > 160 && pixel[0] < 90 && pixel[2] < 90) return 'g';
    if (pixel[2] > 160 && pixel[0] < 90 && pixel[1] < 90) return 'b';
    return '?';
}

static CGSize shownSize(AVAssetTrack *track) {
    CGRect shown = CGRectApplyAffineTransform((CGRect){CGPointZero, track.naturalSize}, track.preferredTransform);
    return CGSizeMake(fabs(shown.size.width), fabs(shown.size.height));
}

int main(int argc, const char **argv) {
    @autoreleasepool {
        printf("the cut\n");
        check(CGSizeEqualToSize(SGMotionClipCut(CGSizeMake(720, 1280), 0.75), CGSizeMake(720, 960)), @"a 9:16 Canvas to 3:4 keeps its width");
        check(CGSizeEqualToSize(SGMotionClipCut(CGSizeMake(1000, 1000), 0.75), CGSizeMake(750, 1000)), @"a square to 3:4 keeps its height");
        check(CGSizeEqualToSize(SGMotionClipCut(CGSizeMake(720, 1280), 1), CGSizeMake(720, 720)), @"a 9:16 Canvas to 1:1");
        CGSize odd = SGMotionClipCut(CGSizeMake(721, 1281), 0.75);
        check((int)odd.width % 2 == 0 && (int)odd.height % 2 == 0 && odd.width <= 721 && odd.height <= 1281, @"odd sides come out even, inside the picture");
        check(CGSizeEqualToSize(SGMotionClipCut(CGSizeZero, 0.75), CGSizeZero), @"no picture, no cut");

        NSString *here = [[NSString stringWithUTF8String:argv[0]] stringByDeletingLastPathComponent];
        NSURL *folder = [NSURL fileURLWithPath:[here stringByAppendingPathComponent:@"clips"] isDirectory:YES];
        [NSFileManager.defaultManager createDirectoryAtURL:folder withIntermediateDirectories:YES attributes:nil error:nil];
        NSURL *tall = [folder URLByAppendingPathComponent:@"canvas-9x16.mp4"], *cut = [folder URLByAppendingPathComponent:@"canvas-3x4.mp4"];
        printf("a 9:16 Canvas cut to 3:4\n");
        check(writeBands(tall, CGSizeMake(720, 1280), 60, CGAffineTransformIdentity, NO), @"the stand-in Canvas written");
        CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
        [NSFileManager.defaultManager removeItemAtURL:cut error:nil]; // This fixture owns its destination.
        stall = YES;
        BOOL shaped = SGMotionClipShape(tall, 0.75, cut);
        stall = NO;
        check(registeredDemand && !stalledReads, @"no producer wakes during sustained writer backpressure");
        printf("  (cut in %.0f ms)\n", (CFAbsoluteTimeGetCurrent() - start) * 1000);
        check(shaped, @"cut and written");
        NSData *original = [NSData dataWithContentsOfURL:cut];
        refuseAppend = YES;
        NSURL *failed = [folder URLByAppendingPathComponent:@"refused.mp4"];
        check(!SGMotionClipShape(tall, 1, failed) && ![NSFileManager.defaultManager fileExistsAtPath:failed.path] &&
              ![NSFileManager.defaultManager fileExistsAtPath:[failed URLByAppendingPathExtension:@"partial"].path],
              @"refused append cancels without publishing or leaving a partial");
        refuseAppend = NO;
        stalledWriter = [StalledWriter new];
        dispatch_semaphore_t returned = dispatch_semaphore_create(0);
        __block BOOL published;
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
            published = SGMotionClipShape(tall, 1, failed);
            dispatch_semaphore_signal(returned);
        });
        if (dispatch_semaphore_wait(returned, dispatch_time(DISPATCH_TIME_NOW, 45 * NSEC_PER_SEC))) {
            check(NO, @"writer failure without readiness hung");
            return 1;
        }
        check(stalledWriter.status == AVAssetWriterStatusFailed && !published && ![NSFileManager.defaultManager fileExistsAtPath:failed.path] &&
              ![NSFileManager.defaultManager fileExistsAtPath:[failed URLByAppendingPathExtension:@"partial"].path],
              @"terminal writer failure without another readiness callback returns and cleans up");
        stalledWriter = nil;
        check(!SGMotionClipShape(tall, 1, cut) && [[NSData dataWithContentsOfURL:cut] isEqual:original] &&
              ![NSFileManager.defaultManager fileExistsAtPath:[cut URLByAppendingPathExtension:@"partial"].path],
              @"a failed move keeps the existing clip and retires its local partial");
        AVAssetTrack *track = videoOf(cut);
        check(CGSizeEqualToSize(shownSize(track), CGSizeMake(720, 960)), [NSString stringWithFormat:@"720 x 960 (%@)", NSStringFromSize(shownSize(track))]);
        check(framesIn(cut) == 60 && framesIn(tall) == 60, [NSString stringWithFormat:@"every frame kept (%d of %d)", framesIn(cut), framesIn(tall)]);
        check(fabs(CMTimeGetSeconds(track.timeRange.duration) - 2) < 0.05, [NSString stringWithFormat:@"2 s long (%.3f)", CMTimeGetSeconds(track.timeRange.duration)]);
        // Cut about the middle, 160 rows off each end, the bands sit at 0-1/6, 1/6-5/6 and 5/6-1; squeezed
        // they would sit at 0-1/4, 1/4-3/4 and 3/4-1.
        NSString *seen = [NSString stringWithFormat:@"%c%c%c%c", colourAt(cut, 0.08), colourAt(cut, 0.21), colourAt(cut, 0.79), colourAt(cut, 0.92)];
        check([seen isEqualToString:@"rggb"], [NSString stringWithFormat:@"cut about its middle, not squeezed (%@ at 8, 21, 79, 92 %%; rggb wanted)", seen]);
        check(![NSFileManager.defaultManager fileExistsAtPath:[cut URLByAppendingPathExtension:@"partial"].path], @"no partial file left");
        check(!SGMotionClipShape([folder URLByAppendingPathComponent:@"missing.mp4"], 0.75, [folder URLByAppendingPathComponent:@"none.mp4"]),
              @"a file that is not there is not cut");

        printf("a Canvas stored on its side\n");
        NSURL *side = [folder URLByAppendingPathComponent:@"canvas-side.mp4"], *sideCut = [folder URLByAppendingPathComponent:@"canvas-side-3x4.mp4"];
        // Stored 1280 x 720 and turned a quarter: shown 720 x 1280.
        CGAffineTransform quarter = CGAffineTransformMake(0, 1, -1, 0, 720, 0);
        check(writeBands(side, CGSizeMake(1280, 720), 30, quarter, YES), @"written");
        check(CGSizeEqualToSize(shownSize(videoOf(side)), CGSizeMake(720, 1280)), @"shown 720 x 1280");
        [NSFileManager.defaultManager removeItemAtURL:sideCut error:nil];
        check(SGMotionClipShape(side, 0.75, sideCut), @"cut and written");
        AVAssetTrack *sideTrack = videoOf(sideCut);
        check(CGSizeEqualToSize(shownSize(sideTrack), CGSizeMake(720, 960)), [NSString stringWithFormat:@"shown 720 x 960 (%@, stored %@)",
              NSStringFromSize(shownSize(sideTrack)), NSStringFromSize(sideTrack.naturalSize)]);
        NSString *sideSeen = [NSString stringWithFormat:@"%c%c%c%c", colourAt(sideCut, 0.08), colourAt(sideCut, 0.21), colourAt(sideCut, 0.79), colourAt(sideCut, 0.92)];
        check([sideSeen isEqualToString:@"rggb"], [NSString stringWithFormat:@"stood up and cut about its middle (%@)", sideSeen]);

        printf("Spotify's Canvas service\n");
        NSData *ask = SGMotionCanvasAsk(@"spotify:track:x");
        const uint8_t wanted[] = {0x0a, 0x11, 0x0a, 0x0f, 's', 'p', 'o', 't', 'i', 'f', 'y', ':', 't', 'r', 'a', 'c', 'k', ':', 'x'};
        check([ask isEqualToData:[NSData dataWithBytes:wanted length:sizeof wanted]], [NSString stringWithFormat:@"the request: an entity naming the track (%@)", ask]);
        check(SGMotionCanvasAsk(nil) == nil, @"no track, no request");
        NSData *(^canvas)(NSString *, int) = ^NSData *(NSString *address, int type) {
            NSMutableArray *fields = [NSMutableArray arrayWithObjects:SGPBString(1, @"id"), SGPBString(2, address), SGPBString(3, @"file"), nil];
            if (type) [fields addObject:SGPBVarint(4, type)];
            return SGPBSerialize(@[SGPBBytes(1, SGPBSerialize(fields))]);
        };
        NSMutableData *both = [canvas(@"https://canvaz.scdn.co/still.jpg", 0) mutableCopy];
        [both appendData:canvas(@"https://canvaz.scdn.co/loop.mp4", 2)];
        check([SGMotionCanvasInReply(both) isEqualToString:@"https://canvaz.scdn.co/loop.mp4"], @"a still then a video: the video");
        check([SGMotionCanvasInReply(canvas(@"https://canvaz.scdn.co/v.mp4", 1)) isEqualToString:@"https://canvaz.scdn.co/v.mp4"], @"type 1 is a video");
        check([SGMotionCanvasInReply(canvas(@"https://canvaz.scdn.co/v.mp4", 3)) isEqualToString:@"https://canvaz.scdn.co/v.mp4"], @"type 3 is a video");
        check(SGMotionCanvasInReply(canvas(@"https://canvaz.scdn.co/a.gif", 4)) == nil, @"a GIF is no clip");
        check(SGMotionCanvasInReply(canvas(@"https://canvaz.scdn.co/still.jpg", 0)) == nil, @"a still alone is no clip");
        check(SGMotionCanvasInReply(canvas(@"", 2)) == nil, @"a video with no address is no clip");
        check(SGMotionCanvasInReply([NSData data]) == nil, @"an empty reply");
        check(SGMotionCanvasInReply([@"<html>not found" dataUsingEncoding:NSUTF8StringEncoding]) == nil, @"a page that is not a reply");
        check(SGMotionCanvasInReply(nil) == nil, @"no reply");

        printf("a Canvas that turns up late\n");
        NSArray *canvasFirst = @[@"canvas", @"applemusic"], *appleFirst = @[@"applemusic", @"canvas"];
        check(SGMotionCanvasOutranks(canvasFirst, nil), @"nothing showing: asked");
        check(SGMotionCanvasOutranks(canvasFirst, @"applemusic"), @"Apple Music's below Canvas showing: asked");
        check(!SGMotionCanvasOutranks(canvasFirst, @"canvas"), @"the Canvas already showing: not asked");
        check(!SGMotionCanvasOutranks(appleFirst, @"applemusic"), @"Apple Music's above Canvas showing: not asked");
        check(SGMotionCanvasOutranks(appleFirst, nil), @"Apple Music first with nothing: asked");
        check(!SGMotionCanvasOutranks(@[@"applemusic"], nil), @"Canvas switched off: not asked");
        check(!SGMotionCanvasOutranks(@[], nil), @"no sources: not asked");

        printf(failures ? "motion: %d FAILED\n" : "motion: all passed\n", failures);
        return failures ? 1 : 0;
    }
}
