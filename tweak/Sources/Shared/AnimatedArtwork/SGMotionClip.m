// SGMotionClip.h says what these are. The cut is the encoder's: the writer is given the cut's size and told
// to fill it keeping the picture's shape, so it drops what overhangs either side and scales nothing.
#import <AVFoundation/AVFoundation.h>
#import <unistd.h>
#import "Shared/AdBlock/Protobuf.h"
#import "SGMotionClip.h"

BOOL SGMotionHeaderMayPlay(BOOL visible, BOOL active, BOOL reduceMotion, BOOL lowPower, BOOL autoplay) {
    return visible && active && !reduceMotion && !lowPower && autoplay;
}

static NSString *const kCanvas = @"canvas";

CGSize SGMotionClipCut(CGSize shown, CGFloat ratio) {
    if (shown.width <= 0 || shown.height <= 0 || ratio <= 0) return CGSizeZero;
    CGSize cut = shown.width / shown.height > ratio ? CGSizeMake(shown.height * ratio, shown.height)
                                                    : CGSizeMake(shown.width, shown.width / ratio);
    // H.264 takes even sides; rounded down, so the cut stays inside the picture.
    return CGSizeMake(floor(cut.width / 2) * 2, floor(cut.height / 2) * 2);
}

// A failed writer need never become ready again. Deliver terminal status to the
// same serial queue as the sample pump so the synchronous caller is released once.
@interface SGShapeStatus : NSObject
@property (copy) dispatch_block_t failed;
@end
@implementation SGShapeStatus
- (void)observeValueForKeyPath:(NSString *)key ofObject:(AVAssetWriter *)writer
                        change:(NSDictionary *)change context:(void *)context {
    if (writer.status == AVAssetWriterStatusFailed || writer.status == AVAssetWriterStatusCancelled) self.failed();
}
@end

static BOOL writeShape(NSURL *file, CGFloat ratio, NSURL *partial) {
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:file options:nil];
    __block AVAssetTrack *track = nil;
    dispatch_semaphore_t loaded = dispatch_semaphore_create(0);
    [asset loadTracksWithMediaType:AVMediaTypeVideo completionHandler:^(NSArray<AVAssetTrack *> *tracks, NSError *error) {
        track = tracks.firstObject;
        dispatch_semaphore_signal(loaded);
    }];
    dispatch_semaphore_wait(loaded, DISPATCH_TIME_FOREVER);
    if (!track) return NO;
    // A quarter turn in the track's transform stands the stored picture on its side: the cut is made in the
    // stored picture, and the transform is carried over to stand it up the same way.
    CGAffineTransform turn = track.preferredTransform;
    BOOL sideways = fabs(turn.b) > 0.5;
    CGSize stored = track.naturalSize, shown = sideways ? CGSizeMake(stored.height, stored.width) : stored;
    CGSize cut = SGMotionClipCut(shown, ratio);
    if (cut.width < 2 || cut.height < 2) return NO;
    if (sideways) cut = CGSizeMake(cut.height, cut.width);

    AVAssetReader *reader = [AVAssetReader assetReaderWithAsset:asset error:nil];
    AVAssetReaderTrackOutput *frames = [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:track outputSettings:@{
        (id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange),
    }];
    if (!reader || ![reader canAddOutput:frames]) return NO;
    [reader addOutput:frames];

    // Written beside the file and moved over it once whole, as SGLyricsClip.m writes, so a clip cut off
    // halfway is never found.
    AVAssetWriter *writer = [AVAssetWriter assetWriterWithURL:partial fileType:AVFileTypeMPEG4 error:nil];
    AVAssetWriterInput *input = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:@{
        AVVideoCodecKey: AVVideoCodecTypeH264,
        AVVideoWidthKey: @(cut.width),
        AVVideoHeightKey: @(cut.height),
        AVVideoScalingModeKey: AVVideoScalingModeResizeAspectFill,
        // About 2 Mbit/s at a Canvas's 720 x 960, near what Spotify streams it at.
        AVVideoCompressionPropertiesKey: @{AVVideoAverageBitRateKey: @(cut.width * cut.height * 3)},
    }];
    input.transform = turn;
    if (!writer || ![writer canAddInput:input]) return NO;
    [writer addInput:input];
    if (![reader startReading] || ![writer startWriting]) {
        [reader cancelReading];
        return NO;
    }
    CMSampleBufferRef first = [frames copyNextSampleBuffer];
    if (!first) {
        [reader cancelReading];
        [writer cancelWriting];
        return NO;
    }
    [writer startSessionAtSourceTime:CMSampleBufferGetPresentationTimeStamp(first)];
    __block id pending = CFBridgingRelease(first);
    dispatch_queue_t queue = dispatch_queue_create("app.retrine.motion.shape", DISPATCH_QUEUE_SERIAL);
    dispatch_semaphore_t written = dispatch_semaphore_create(0);
    __block BOOL ending = NO;
    void (^end)(BOOL) = ^(BOOL success) {
        if (ending) return;
        ending = YES;
        if (success) {
            [input markAsFinished];
            [writer finishWritingWithCompletionHandler:^{ dispatch_semaphore_signal(written); }];
        } else {
            [reader cancelReading];
            if (writer.status == AVAssetWriterStatusWriting) [writer cancelWriting];
            dispatch_semaphore_signal(written);
        }
    };
    SGShapeStatus *observer = [SGShapeStatus new];
    observer.failed = ^{ dispatch_async(queue, ^{ end(NO); }); };
    [writer addObserver:observer forKeyPath:@"status" options:NSKeyValueObservingOptionInitial context:NULL];
    [input requestMediaDataWhenReadyOnQueue:queue usingBlock:^{
        while (!ending && input.readyForMoreMediaData) @autoreleasepool {
            id sample = pending ?: CFBridgingRelease([frames copyNextSampleBuffer]);
            pending = nil;
            if (!sample) end(reader.status == AVAssetReaderStatusCompleted);
            else if (![input appendSampleBuffer:(__bridge CMSampleBufferRef)sample]) end(NO);
        }
    }];
    dispatch_semaphore_wait(written, DISPATCH_TIME_FOREVER);
    [writer removeObserver:observer forKeyPath:@"status"];
    return writer.status == AVAssetWriterStatusCompleted;
}

BOOL SGMotionClipShape(NSURL *file, CGFloat ratio, NSURL *out) {
    NSURL *partial = [out URLByAppendingPathExtension:@"partial"];
    unlink(partial.fileSystemRepresentation);
    if (writeShape(file, ratio, partial) && [NSFileManager.defaultManager moveItemAtURL:partial toURL:out error:nil]) return YES;
    unlink(partial.fileSystemRepresentation);
    return NO;
}

NSData *SGMotionCanvasAsk(NSString *uri) {
    if (!uri.length) return nil;
    return SGPBSerialize(@[SGPBBytes(1, SGPBSerialize(@[SGPBString(1, uri)]))]);
}

NSString *SGMotionCanvasInReply(NSData *reply) {
    for (SGPBField *field in SGPBParse(reply)) {
        if (field.number != 1 || field.wire != 2) continue;
        NSArray<SGPBField *> *canvas = SGPBParse(field.payload);
        SGPBField *type = SGPBFirst(canvas, 4);
        NSString *address = SGPBText(SGPBFirst(canvas, 2));
        // 0, the type a message leaves out, is a still; 4 and on are a GIF and kinds not seen.
        if (type.wire == 0 && type.varint >= 1 && type.varint <= 3 && address.length) return address;
    }
    return nil;
}

BOOL SGMotionCanvasOutranks(NSArray<NSString *> *order, NSString *source) {
    NSUInteger canvas = [order indexOfObject:kCanvas];
    if (canvas == NSNotFound) return NO;
    if (!source) return YES;
    NSUInteger shown = [order indexOfObject:source];
    return shown != NSNotFound && shown > canvas;
}
