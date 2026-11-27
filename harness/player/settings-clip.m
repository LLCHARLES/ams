// Host-only Canvas fixture for settings-check.sh: four seconds of solid #3060c0.
#import <AVFoundation/AVFoundation.h>

static void fail(NSString *reason) {
    fprintf(stderr, "settings clip: %s\n", reason.UTF8String);
    exit(1);
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc != 2 && argc != 3) fail(@"expected an output .mp4 path and optional square flag");
        const int width = 360, height = argc == 3 ? width : 640, framesPerSecond = 25, durationSeconds = 4;
        NSError *error = nil;
        AVAssetWriter *writer = [AVAssetWriter assetWriterWithURL:
            [NSURL fileURLWithPath:@(argv[1])] fileType:AVFileTypeMPEG4 error:&error];
        if (!writer) fail([NSString stringWithFormat:@"create writer: %@", error]);
        AVAssetWriterInput *input = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo
            outputSettings:@{AVVideoCodecKey: AVVideoCodecTypeH264,
                             AVVideoWidthKey: @(width), AVVideoHeightKey: @(height)}];
        AVAssetWriterInputPixelBufferAdaptor *adaptor =
            [AVAssetWriterInputPixelBufferAdaptor assetWriterInputPixelBufferAdaptorWithAssetWriterInput:input
                sourcePixelBufferAttributes:@{(id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA),
                                              (id)kCVPixelBufferWidthKey: @(width),
                                              (id)kCVPixelBufferHeightKey: @(height)}];
        if (![writer canAddInput:input]) fail(@"cannot add H.264 input");
        [writer addInput:input];
        if (![writer startWriting]) fail([NSString stringWithFormat:@"start writing: %@", writer.error]);
        [writer startSessionAtSourceTime:kCMTimeZero];
        CVPixelBufferRef buffer = NULL;
        CVReturn result = CVPixelBufferPoolCreatePixelBuffer(NULL, adaptor.pixelBufferPool, &buffer);
        if (result != kCVReturnSuccess) fail([NSString stringWithFormat:@"allocate pixels: %d", result]);
        result = CVPixelBufferLockBaseAddress(buffer, 0);
        if (result != kCVReturnSuccess) fail([NSString stringWithFormat:@"lock pixels: %d", result]);
        uint8_t *base = CVPixelBufferGetBaseAddress(buffer);
        size_t stride = CVPixelBufferGetBytesPerRow(buffer);
        for (int y = 0; y < height; y++) {
            for (int x = 0; x < width; x++) {
                uint8_t *pixel = base + y * stride + x * 4;
                pixel[0] = 0xc0; pixel[1] = 0x60; pixel[2] = 0x30; pixel[3] = 0xff;
            }
        }
        result = CVPixelBufferUnlockBaseAddress(buffer, 0);
        if (result != kCVReturnSuccess) fail([NSString stringWithFormat:@"unlock pixels: %d", result]);
        dispatch_semaphore_t done = dispatch_semaphore_create(0);
        __block int frame = 0;
        [input requestMediaDataWhenReadyOnQueue:dispatch_queue_create("settings-clip", DISPATCH_QUEUE_SERIAL)
            usingBlock:^{
                while (input.readyForMoreMediaData && frame < framesPerSecond * durationSeconds) {
                    if (![adaptor appendPixelBuffer:buffer withPresentationTime:CMTimeMake(frame, framesPerSecond)])
                        fail([NSString stringWithFormat:@"append frame %d: %@", frame, writer.error]);
                    frame++;
                }
                if (frame == framesPerSecond * durationSeconds) {
                    [input markAsFinished];
                    [writer endSessionAtSourceTime:CMTimeMake(durationSeconds, 1)];
                    [writer finishWritingWithCompletionHandler:^{ dispatch_semaphore_signal(done); }];
                }
            }];
        const int generationTimeoutSeconds = 30;
        if (dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, generationTimeoutSeconds * NSEC_PER_SEC)))
            fail([NSString stringWithFormat:@"generation timed out: %@", writer.error]);
        CVPixelBufferRelease(buffer);
        if (writer.status != AVAssetWriterStatusCompleted)
            fail([NSString stringWithFormat:@"finish writing: %@", writer.error]);
    }
    return 0;
}
