#import "LyricsPiPBackground.h"
#import "LyricsPiPFrame.h"
#import "Shared/LyricsBackground/LyricsBackground.h"
#import "Shared/Player/SGLastTrack.h"
#import "Shared/Player/PlayerState.h"

@implementation SGLyricsPiPBackground {
    NSOperationQueue *_queue;
    NSArray *_source, *_look;
    CGSize _size;
    SGLyricsBackgroundStyle _style;
    NSArray *_identity;
    NSUInteger _sourceGeneration, _renderGeneration;
}

- (instancetype)init {
    if (!(self = [super init])) return nil;
    _queue = [NSOperationQueue new];
    _queue.maxConcurrentOperationCount = 1;
    _queue.qualityOfService = NSQualityOfServiceUserInitiated;
    return self;
}

static NSArray *sourceFor(NSString *track, SGShownTrack *shown) {
    // Never use SGLastTrack's persisted last-song fallback, even while the player is loading.
    NSString *url = shown.current && [shown.uri isEqual:track] ? shown.artworkURL.absoluteString : nil;
    return @[track ?: @"", url ?: @""];
}

static BOOL currentSource(NSString *track, NSArray *source) {
    // Artwork eligibility is not playback identity: ads deliberately have no SGShownTrack.
    NSString *current = SGURIString(SGPlayerState().track.URI);
    return (track.length ? [current isEqual:track] : !current.length)
        && [source isEqual:sourceFor(track, SGShownTrackNow())];
}

- (void)refreshForTrack:(NSString *)track {
    CGSize size = SGLyricsPiPReadStyle().raster;
    SGLyricsBackgroundStyle style = SGLyricsPiPReadBackground();
    [self refreshForTrack:track size:size background:style identity:@[SGLyricsBackgroundIdentity(style), [NSValue valueWithCGSize:size]]];
}

- (void)refreshForTrack:(NSString *)track size:(CGSize)size background:(SGLyricsBackgroundStyle)style identity:(NSArray *)identity {
    _size = size;
    _style = style;
    _identity = identity;
    SGShownTrack *shown = SGShownTrackNow();
    NSArray *source = sourceFor(track, shown);
    if (![_source isEqual:source]) {
        _source = source;
        _cover = nil;
        _look = nil;
        _image = nil;
        NSUInteger generation = ++_sourceGeneration;
        if ([source[1] length]) {
            __weak SGLyricsPiPBackground *weakSelf = self;
            // This existing API reads local/Spotify metadata URLs and decodes off main. A failed load
            // gets one retry, for a source that is still current; no further attempt follows a second
            // failure (the solid shared fallback stays until the source changes).
            SGShownTrackArtworkBounded(shown, ^BOOL {
                SGLyricsPiPBackground *self = weakSelf;
                return self && generation == self->_sourceGeneration && currentSource(track, source);
            }, ^(UIImage *cover) {
                SGLyricsPiPBackground *self = weakSelf;
                if (!self || generation != self->_sourceGeneration) return;
                if (!currentSource(track, source)) {
                    self->_source = nil;
                    self->_look = nil;
                    return; // wait for an external state/metadata refresh, not a retry loop
                }
                if (!cover.CGImage) return; // keep the shared fallback; no per-tick failed-image retry
                self->_cover = cover;
                self->_look = nil;
                [self refreshForTrack:track size:self->_size background:self->_style identity:self->_identity];
            });
        }
    }
    if ([_look isEqual:identity]) return; // a new source or late cover already cleared _look
    _look = identity;
    _image = nil;
    NSUInteger generation = ++_renderGeneration;
    [_queue cancelAllOperations];
    UIImage *cover = _cover;
    __weak SGLyricsPiPBackground *weakSelf = self;
    NSBlockOperation *operation = [NSBlockOperation new];
    __weak NSBlockOperation *weakOperation = operation;
    [operation addExecutionBlock:^{
        @autoreleasepool {
            if (weakOperation.cancelled) return;
            CGImageRef rendered = SGLyricsBackgroundCreate(cover.CGImage, size, style);
            UIImage *image = rendered ? [UIImage imageWithCGImage:rendered] : nil;
            if (rendered) CGImageRelease(rendered);
            if (weakOperation.cancelled) return;
            dispatch_async(dispatch_get_main_queue(), ^{
                SGLyricsPiPBackground *self = weakSelf;
                if (!self || generation != self->_renderGeneration) return;
                if (!currentSource(track, source)) {
                    self->_look = nil; // a later correctly ordered refresh must be able to render
                    return;
                }
                self->_image = image;
                self->_revision++;
                if (self.changed) self.changed();
            });
        }
    }];
    [_queue addOperation:operation];
}

- (void)invalidate {
    ++_sourceGeneration;
    ++_renderGeneration;
    [_queue cancelAllOperations];
    _source = nil;
    _look = nil;
    _cover = nil;
    _image = nil;
}

- (void)dealloc { [_queue cancelAllOperations]; }
@end
