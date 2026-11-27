#import "SGRHeaderClip.h"
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>

@interface SGRHeaderSubscribers : NSObject
@property (nonatomic, strong) NSHashTable<SGRHeaderPage *> *pages;
@property (nonatomic) BOOL leaving, disappeared, scheduled;
@end
@implementation SGRHeaderSubscribers
@end

static char kSubscribers;
@implementation SGRHeaderPage {
    __weak UIViewController *_owner;
    SGRHeaderSubscribers *_subscribers;
    dispatch_block_t _refresh;
    BOOL _visible;
}
- (instancetype)initWithRefresh:(dispatch_block_t)refresh {
    if ((self = [super init])) _refresh = [refresh copy];
    return self;
}
- (void)bindHeader:(UIView *)header {
    UIResponder *r = header.nextResponder;
    while (r && ![r isKindOfClass:UIViewController.class]) r = r.nextResponder;
    UIViewController *owner = (UIViewController *)r;
    if (!owner && _subscribers.leaving) return;
    if (_owner == owner) return;
    [_subscribers.pages removeObject:self];
    _owner = owner;
    _visible = NO;
    _subscribers = objc_getAssociatedObject(owner, &kSubscribers);
    if (!owner) return;
    if (!_subscribers) {
        _subscribers = [SGRHeaderSubscribers new];
        _subscribers.pages = [NSHashTable weakObjectsHashTable];
        objc_setAssociatedObject(owner, &kSubscribers, _subscribers, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    [_subscribers.pages addObject:self];
}
- (BOOL)visibleInViewport:(BOOL)inViewport {
    if (_subscribers.disappeared) return _visible = NO;
    // During a pop the outgoing owner can lose its coordinator (and even
    // its window) before UIKit finishes the interaction. Preserve the last
    // settled visibility, including NO, until didAppear or didDisappear.
    if (_subscribers.leaving) return _visible;
    return _visible = inViewport;
}
- (void)refresh { _refresh(); }
@end

void SGRHeaderPageWillDisappear(UIViewController *owner) {
    SGRHeaderSubscribers *subscribers = objc_getAssociatedObject(owner, &kSubscribers);
    subscribers.leaving = YES;
}

void SGRHeaderPageDidAppear(UIViewController *owner, BOOL appeared) {
    SGRHeaderSubscribers *subscribers = objc_getAssociatedObject(owner, &kSubscribers);
    if (!subscribers) return;
    subscribers.leaving = NO;
    subscribers.disappeared = !appeared;
    if (subscribers.scheduled) return;
    subscribers.scheduled = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        subscribers.scheduled = NO;
        for (SGRHeaderPage *page in subscribers.pages.allObjects) [page refresh];
    });
}

static char kReplica, kFrame;

@implementation SGRHeaderClip {
    void (^_appearance)(BOOL, BOOL);
    AVQueuePlayer *_player;
    AVPlayerLooper *_looper;
    AVPlayerItem *_replica;
    AVPlayerItemVideoOutput *_output;
    AVPlayerLayer *_video;
    CMTime _savedTime;
    NSUInteger _generation;
    BOOL _mayPlay;
}

- (instancetype)initWithFile:(NSURL *)file appearance:(void (^)(BOOL, BOOL))appearance {
    if (!(self = [super init])) return nil;
    _file = file;
    _appearance = [appearance copy];
    _savedTime = kCMTimeInvalid;
    _layer = [CALayer layer];
    _layer.contentsGravity = kCAGravityResizeAspectFill;
    _layer.masksToBounds = YES;
    _layer.opacity = 0;
    return self;
}

- (void)setFrame:(CGRect)frame {
    _layer.frame = frame;
    _video.frame = _layer.bounds;
}

- (void)discardGraph {
    ++_generation;
    [_player removeObserver:self forKeyPath:@"currentItem" context:&kReplica];
    [_video removeObserver:self forKeyPath:@"readyForDisplay" context:&kFrame];
    [_player pause];
    [_looper disableLooping];
    _video.player = nil;
    [_video removeFromSuperlayer];
    [_replica removeOutput:_output];
    [_player removeAllItems];
    _video = nil;
    _output = nil;
    _replica = nil;
    _looper = nil;
    _player = nil;
}

- (void)invalidate {
    [self discardGraph];
    [_layer removeFromSuperlayer];
}
- (void)dealloc { [self invalidate]; }

// The video output supplies storage pixels. Map their top-left coordinates
// through the track matrix as AVPlayerLayer does, before aspect-fill crops.
static CGImageRef displayImage(CGImageRef raw, AVPlayerItem *item) CF_RETURNS_RETAINED {
    AVAssetTrack *track = [item.asset tracksWithMediaType:AVMediaTypeVideo].firstObject;
    CGAffineTransform t = track.preferredTransform;
    if (!track || CGAffineTransformIsIdentity(t)) return CGImageRetain(raw);
    CGRect src = CGRectMake(0, 0, CGImageGetWidth(raw), CGImageGetHeight(raw));
    CGRect dst = CGRectIntegral(CGRectApplyAffineTransform(src, t));
    CGContextRef ctx = CGBitmapContextCreate(NULL, dst.size.width, dst.size.height, 8, 0,
        CGImageGetColorSpace(raw), kCGBitmapByteOrder32Little | kCGImageAlphaNoneSkipFirst);
    if (!ctx) return NULL;
    CGContextTranslateCTM(ctx, -dst.origin.x, CGRectGetMaxY(dst));
    CGContextScaleCTM(ctx, 1, -1);
    CGContextConcatCTM(ctx, t);
    CGContextTranslateCTM(ctx, 0, src.size.height);
    CGContextScaleCTM(ctx, 1, -1);
    CGContextDrawImage(ctx, src, raw);
    CGImageRef oriented = CGBitmapContextCreateImage(ctx);
    CGContextRelease(ctx);
    return oriented;
}

// Copy the frame and its PTS together from the current loop replica. A lazy
// CIImage (or retaining the CVPixelBuffer) would keep decoder storage alive.
- (void)freeze {
    CMTime pts = kCMTimeInvalid;
    CVPixelBufferRef pixel = _replica == _player.currentItem ?
        [_output copyPixelBufferForItemTime:_replica.currentTime itemTimeForDisplay:&pts] : NULL;
    CGImageRef still = NULL;
    if (pixel && CMTIME_IS_NUMERIC(pts) && CVPixelBufferLockBaseAddress(pixel, kCVPixelBufferLock_ReadOnly) == kCVReturnSuccess) {
        size_t stride = CVPixelBufferGetBytesPerRow(pixel), height = CVPixelBufferGetHeight(pixel);
        NSData *bytes = [NSData dataWithBytes:CVPixelBufferGetBaseAddress(pixel) length:stride * height];
        CVPixelBufferUnlockBaseAddress(pixel, kCVPixelBufferLock_ReadOnly);
        CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)bytes);
        CGColorSpaceRef rgb = CGColorSpaceRetain(CVImageBufferGetColorSpace(pixel));
        if (!rgb) rgb = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
        CGImageRef raw = CGImageCreate(CVPixelBufferGetWidth(pixel), height, 8, 32, stride, rgb,
                              kCGBitmapByteOrder32Little | kCGImageAlphaNoneSkipFirst, provider, NULL, YES,
                              kCGRenderingIntentDefault);
        CGColorSpaceRelease(rgb);
        CGDataProviderRelease(provider);
        if (raw) { still = displayImage(raw, _replica); CGImageRelease(raw); }
    }
    if (pixel) CVPixelBufferRelease(pixel);
    _layer.contents = (__bridge id)still;
    _savedTime = still ? pts : kCMTimeInvalid;
    if (still) CGImageRelease(still);
    else {
        [_layer removeAnimationForKey:@"fade"];
        _layer.opacity = 0;
        _appearance(NO, NO);
    }
}

- (void)syncPlayback {
    BOOL play = _mayPlay && _video && _video.opacity == 1;
    if (play && !_player.rate) [_player play];
    else if (!play && _player.rate) [_player pause];
}

- (void)revealWhenReady {
    if (!_video || !_video.readyForDisplay || _video.opacity == 1) return;
    BOOL entrance = !_layer.contents;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _video.opacity = _layer.opacity = 1;
    // Leave the saved image *under* the video. The compositor can take
    // another transaction to install the AV surface after readiness; never
    // trade away its backing image in the transaction that exposes it.
    _savedTime = kCMTimeInvalid;
    if (entrance) _appearance(YES, YES);
    [CATransaction commit];
    [self syncPlayback];
}

// A restored layer is *new and first attached after exact seek completion*.
// Its first ready notification therefore cannot describe a pre-seek frame.
- (void)attachVideo {
    _video = [AVPlayerLayer playerLayerWithPlayer:_player];
    _video.videoGravity = AVLayerVideoGravityResizeAspectFill;
    _video.frame = _layer.bounds;
    _video.opacity = 0;
    [_layer addSublayer:_video];
    [_video addObserver:self forKeyPath:@"readyForDisplay" options:NSKeyValueObservingOptionInitial context:&kFrame];
}

- (void)replicaChanged {
    AVPlayerItem *item = _player.currentItem;
    if (item == _replica) return;
    [_replica removeOutput:_output];
    ++_generation;
    _replica = item;
    _output = nil;
    if (!item) return;
    _output = [[AVPlayerItemVideoOutput alloc] initWithPixelBufferAttributes:@{
        (id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA)
    }];
    [item addOutput:_output];
    if (_video) return; // ordinary forward loop
    if (!CMTIME_IS_NUMERIC(_savedTime)) { [self attachVideo]; return; }
    NSUInteger generation = _generation;
    __weak SGRHeaderClip *weakSelf = self;
    [item seekToTime:_savedTime toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero completionHandler:^(BOOL finished) {
        dispatch_async(dispatch_get_main_queue(), ^{
            SGRHeaderClip *clip = weakSelf;
            if (!clip || clip->_generation != generation || clip->_player.currentItem != clip->_replica) return;
            if (finished) [clip attachVideo]; else [clip discardGraph];
        });
    }];
}

- (void)observeValueForKeyPath:(NSString *)key ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    __weak SGRHeaderClip *weakSelf = self;
    __weak id weakSource = object;
    dispatch_async(dispatch_get_main_queue(), ^{
        SGRHeaderClip *clip = weakSelf;
        id source = weakSource;
        if (!clip || !source) return;
        if (context == &kReplica && source == clip->_player) [clip replicaChanged];
        if (context == &kFrame && source == clip->_video) [clip revealWhenReady];
    });
}

- (void)updateVisible:(BOOL)visible active:(BOOL)active mayPlay:(BOOL)mayPlay {
    _mayPlay = mayPlay && visible && active;
    if (!visible) {
        if (!_player) return;
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        [_player pause];
        if (_video && _video.opacity == 1) [self freeze];
        [self discardGraph];
        [CATransaction commit];
        return;
    }
    // A hold needs a static frame, not a running clock. A saved frame
    // already provides it; otherwise prepare the first frame paused.
    if (!_player && active && (_mayPlay || !_layer.contents)) {
        _player = [AVQueuePlayer new];
        _player.muted = YES;
        _player.preventsDisplaySleepDuringVideoPlayback = NO;
        _player.automaticallyWaitsToMinimizeStalling = NO;
        _looper = [AVPlayerLooper playerLooperWithPlayer:_player templateItem:[AVPlayerItem playerItemWithURL:_file]];
        [_player addObserver:self forKeyPath:@"currentItem" options:NSKeyValueObservingOptionInitial context:&kReplica];
    }
    [self revealWhenReady];
    [self syncPlayback];
}
@end
