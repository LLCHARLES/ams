// The lock screen's artwork moves: the track's Canvas, else Apple Music's animated album cover, and with
// Every song chosen, failing both, the selected fallback background (SGFluidClip.h). iOS 26 takes a
// local video through MPMediaItemAnimatedArtwork under one of two now playing keys, 1:1 or 3:4, of those
// the system lists. It rides on Spotify's now playing info as an extra (Shared/Player/NowPlayingExtras.h).
//
// The system turns down a clip of another shape than its key's, and a preview still of another shape with
// it, so a clip that does not fit (a Canvas is mostly 9:16) is cut to the key's shape about its middle, and
// the still is filled to the size the system asks for. The cut, like the cover's clip, is made only when the
// lock screen asks for the video, and kept: the cut by the clip and shape, the cover's clip by the picture
// the track names, so an album's songs share one.
//
// The choice is read on every track, and a change applies at once: Off takes the clip away, Moving artwork
// and Every song look the playing track up. Lyrics is LyricsArtwork.x's, which reads it the same way, so the
// lock screen widget's star (LockScreenStar.x) can swap the two without a restart. Moving artwork with
// lyrics looks the track up too and hands its clip to LyricsArtwork.x, which draws the lines over it.
#import <MediaPlayer/MediaPlayer.h>
#import <stdatomic.h>
#import "Core/SGCore.h"
#import <CommonCrypto/CommonDigest.h>
#import "AnimatedArtwork.h"
#import "SGLockArtworkStart.h"
#import "SGFluidClip.h"
#import "SGMotionClip.h"
#import "Shared/LockScreenLyrics/LockScreenLyrics.h"
#import "Shared/LockScreenLyrics/SGLyricsClip.h"
#import "Shared/Player/NowPlayingExtras.h"
#import "Shared/Player/PlayerState.h"
#import "Shared/Player/SGLastTrack.h"
#import "Shared/LyricsBackground/LyricsBackground.h"

// How far a clip's width over height may be from its key's and still be taken as it is.
static const CGFloat kSameShape = 0.02;

static NSString *sg_title;
static NSString *sg_trackURI;
static NSArray *sg_coverSource;
static NSUInteger sg_coverRequest;
static MPMediaItemArtwork *sg_nativeArtwork;
static BOOL sg_authoritativeCover;
static NSUInteger sg_coverRevision;
static NSString *sg_coverPublishedID;
static NSString *sg_picture;   // the picture the track names, for the cover's clip
static NSUInteger sg_walk;   // presentation generation: track, choice and plain/lyrics ownership
static _Atomic(SGLockArtwork) sg_choice; // applied on main, sampled by defaults posters
static dispatch_queue_t sg_queue;   // cuts clips and makes the cover's, one at a time
static SGMotionFollower *sg_follower;
// A source is fetched once. Only its presentation waits for MediaPlayer's capabilities/cover.
static NSURL *sg_pendingFile;
static NSString *sg_pendingPicture;
static UIImage *sg_poster;
static BOOL sg_loadingPoster;
static NSString *sg_fallbackPicture;
static UIImage *sg_fallbackCover;
static BOOL sg_loadingCover, sg_settingsPending;
static NSProgress *sg_presentation;
static SGLyricsBackgroundStyle sg_background;

static void cancelPresentation(void) {
    [sg_presentation cancel];
    sg_presentation = [NSProgress progressWithTotalUnitCount:1];
    sg_walk++;
    sg_pendingFile = nil;
    sg_pendingPicture = nil;
    sg_poster = nil;
    sg_loadingPoster = NO;
    sg_loadingCover = NO;
    sg_coverPublishedID = nil;
}

API_AVAILABLE(ios(26.0))
static void retryPresentation(void);

// Moving artwork with lyrics walks the sources too, and hands the clip to LyricsArtwork.x.
static BOOL motionOn(SGLockArtwork choice) {
    return choice == SGLockArtworkMotion || choice == SGLockArtworkEverySong || choice == SGLockArtworkMotionLyrics;
}

// The key a clip shown at `shown` goes under, and the shape it is cut to (width over height): 1:1 for a
// square clip, else 3:4, each where the system lists it, else the other. nil while it lists neither, before
// MediaPlayer has started: a later now-playing update retries the pending presentation.
API_AVAILABLE(ios(26.0))
static NSString *keyFor(CGSize shown, CGFloat *ratio) {
    NSArray<NSString *> *keys = MPNowPlayingInfoCenter.supportedAnimatedArtworkKeys;
    BOOL square = shown.height > 0 && fabs(shown.width / shown.height - 1) <= kSameShape;
    BOOL tall = [keys containsObject:MPNowPlayingInfoProperty3x4AnimatedArtwork];
    if ([keys containsObject:MPNowPlayingInfoProperty1x1AnimatedArtwork] && (square || !tall)) {
        *ratio = 1;
        return MPNowPlayingInfoProperty1x1AnimatedArtwork;
    }
    *ratio = 0.75;
    return tall ? MPNowPlayingInfoProperty3x4AnimatedArtwork : nil;
}

// `image` filled into `size` about its middle, at scale 1 and opaque, as the preview the system asked for.
static UIImage *filled(UIImage *image, CGSize size) {
    size = CGSizeMake(round(size.width), round(size.height));
    if (!image || size.width < 1 || size.height < 1 || image.size.width <= 0 || image.size.height <= 0) return image;
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat preferredFormat];
    format.scale = 1;
    format.opaque = YES;
    CGFloat scale = MAX(size.width / image.size.width, size.height / image.size.height);
    CGSize drawn = CGSizeMake(image.size.width * scale, image.size.height * scale);
    return [[[UIGraphicsImageRenderer alloc] initWithSize:size format:format] imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [image drawInRect:CGRectMake((size.width - drawn.width) / 2, (size.height - drawn.height) / 2, drawn.width, drawn.height)];
    }];
}

API_AVAILABLE(ios(26.0))
static void show(NSURL *file) {
    cancelPresentation();
    sg_pendingFile = file;
    retryPresentation();
}

API_AVAILABLE(ios(26.0))
static void offerVideo(void) {
    NSURL *file = sg_pendingFile;
    NSUInteger walk = sg_walk;
    NSString *title = sg_title;
    if (!sg_poster) {
        if (sg_loadingPoster) return;
        sg_loadingPoster = YES;
        SGMotionPoster(file, ^(UIImage *poster) {
            if (walk != sg_walk) return;
            sg_loadingPoster = NO;
            // A bad file is not retried on every info update.
            if (!poster || poster.size.height <= 0) {
                sg_pendingFile = nil;
                return;
            }
            sg_poster = poster;
            retryPresentation();
        });
        return;
    }
    UIImage *poster = sg_poster;
        CGFloat ratio;
        NSString *key = keyFor(poster.size, &ratio);
        if (!key) return;
        BOOL fits = fabs(poster.size.width / poster.size.height - ratio) <= kSameShape;
        NSURL *shaped = fits ? file : SGMotionMadeFile([NSString stringWithFormat:@"cut\n%@\n%g", file.lastPathComponent, ratio]);
        MPMediaItemAnimatedArtwork *artwork = [[MPMediaItemAnimatedArtwork alloc] initWithArtworkID:shaped.lastPathComponent
            previewImageRequestHandler:^(CGSize wanted, void (^completion)(UIImage *)) { completion(filled(poster, wanted)); }
            videoAssetFileURLRequestHandler:^(CGSize wanted, void (^completion)(NSURL *)) {
                if (fits) {
                    completion(file);
                    return;
                }
                SGMotionMakeFile(shaped, ^BOOL { return SGMotionClipShape(file, ratio, shaped); },
                                ^(BOOL ok) { completion(ok ? shaped : nil); });
            }];
        SGNowPlayingSetExtras(@"motion", @{key: artwork}, title);
        sg_pendingFile = nil;
        sg_poster = nil;
        SGLog(@"lock motion: %@, %.0fx%.0f, as %@%@", file.lastPathComponent, poster.size.width, poster.size.height,
              ratio == 1 ? @"1:1" : @"3:4", fits ? @"" : @", cut to fit");
}

// Under Moving artwork with lyrics: the clip found for the track, and whether LyricsArtwork.x asked for it
// plain (the track has no synced lines) and it shows so.
static NSURL *sg_lyricsFile;
static BOOL sg_plain, sg_plainShown;

void SGLockMotionShowPlain(BOOL plain) {
    if (@available(iOS 26.0, *)) {
        sg_plain = plain;
        BOOL want = plain && sg_choice == SGLockArtworkMotionLyrics && sg_lyricsFile;
        if (want == sg_plainShown) return;
        cancelPresentation();
        sg_plainShown = want;
        if (want) show(sg_lyricsFile);
        else SGNowPlayingSetExtras(@"motion", nil, nil);
        SGLog(@"lock motion: %@", want ? [NSString stringWithFormat:@"%@ shown plain, the track has no synced lines", sg_lyricsFile.lastPathComponent]
                                       : @"the plain clip taken off for the lyrics");
    }
}

// The picture the track names, so the songs of an album share a clip; the track itself when it names none.
static NSString *pictureOf(SPTPlayerTrack *track, NSDictionary *metadata) {
    for (NSString *field in @[@"image_xlarge_url", @"image_large_url", @"image_url"]) {
        id value = metadata[field];
        if ([value isKindOfClass:NSString.class] && [value length]) return value;
    }
    return SGURIString(track.URI);
}

// The cover's clip is 3:4 (SGLyricsClipSize), so it goes only where the system lists that key.
API_AVAILABLE(ios(26.0))
static void showCover(NSString *picture) {
    cancelPresentation();
    sg_fallbackPicture = picture;
    sg_pendingPicture = picture;
    retryPresentation();
}

static BOOL currentCoverRequest(NSUInteger request, SGShownTrack *track) {
    SGShownTrack *now = SGShownTrackNow();
    return request == sg_coverRequest && sg_fallbackPicture && SGLockScreenArtwork() == SGLockArtworkEverySong
        && now.current && [now.uri isEqual:sg_trackURI] && [now.uri isEqual:track.uri]
        && [now.artworkURL isEqual:track.artworkURL];
}

static void setFallbackCover(UIImage *cover) {
    if (sg_fallbackCover.CGImage != cover.CGImage) sg_coverRevision++;
    sg_fallbackCover = cover;
    sg_pendingPicture = sg_fallbackPicture;
}

// Native pixels are provisional, not proof of ownership. Keep observing new objects until
// the URI loader succeeds, including when a paused fallback has already been published.
static void refreshNativeCover(void) {
    if (sg_authoritativeCover || ![SGURIString(SGPlayerState().track.URI) isEqual:sg_trackURI]) return;
    NSDictionary *info = MPNowPlayingInfoCenter.defaultCenter.nowPlayingInfo;
    MPMediaItemArtwork *native = info[MPMediaItemPropertyArtwork];
    if (![info[MPMediaItemPropertyTitle] isEqual:sg_title] || ![native isKindOfClass:MPMediaItemArtwork.class]
        || native == sg_nativeArtwork) return;
    sg_nativeArtwork = native;
    CGSize size = SGLyricsClipSize(UIScreen.mainScreen.nativeBounds.size.width);
    UIImage *cover = [native imageWithSize:CGSizeMake(size.height, size.height)];
    if (cover.CGImage) setFallbackCover(cover);
}

// Loading is independent of native rendering. Neither missing metadata nor a failure
// removes available pixels. Install source state before the possibly synchronous cache hit.
API_AVAILABLE(ios(26.0))
static void refreshCover(void) {
    SGShownTrack *track = SGShownTrackNow();
    NSURL *url = track.current && [track.uri isEqual:sg_trackURI] ? track.artworkURL : nil;
    NSArray *source = @[sg_trackURI ?: @"", url.absoluteString ?: @""];
    if ([sg_coverSource isEqual:source]) return;
    sg_coverSource = source;
    sg_authoritativeCover = NO;
    sg_nativeArtwork = nil;
    NSUInteger request = ++sg_coverRequest;
    if (!url) return;
    SGShownTrackArtworkBounded(track, ^BOOL {
        return currentCoverRequest(request, track);
    }, ^(UIImage *cover) {
        if (!currentCoverRequest(request, track)) return;
        if (cover) {
            sg_authoritativeCover = YES;
            setFallbackCover(cover);
        }
        retryPresentation();
    });
}

// Fingerprint canonical pixels, not a native wrapper or the track that supplied it.
// The worker retains only the last revision's digest, never an encoded full-size cover.
static NSString *coverSource(CGImageRef cover, NSUInteger revision) {
    if (!cover) return @"no-cover";
    static NSUInteger lastRevision;
    static NSString *digest;
    if (digest && lastRevision == revision) return digest;
    // Hash every pixel (including small edits a thumbnail could miss) in fixed-size tiles.
    enum { side = 128 };
    CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGContextRef ctx = CGBitmapContextCreate(NULL, side, side, 8, side * 4, space,
                                             kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(space);
    if (!ctx) return nil;
    size_t width = CGImageGetWidth(cover), height = CGImageGetHeight(cover);
    CC_SHA256_CTX hash;
    CC_SHA256_Init(&hash);
    CGContextSetBlendMode(ctx, kCGBlendModeCopy);
    for (size_t y = 0; y < height; y += side) {
        for (size_t x = 0; x < width; x += side) {
            size_t w = MIN(side, width - x), h = MIN(side, height - y);
            CGImageRef tile = CGImageCreateWithImageInRect(cover, CGRectMake(x, y, w, h));
            if (!tile) { CGContextRelease(ctx); return nil; }
            CGContextClearRect(ctx, CGRectMake(0, 0, side, side));
            CGContextDrawImage(ctx, CGRectMake(0, 0, w, h), tile);
            CGImageRelease(tile);
            CC_SHA256_Update(&hash, CGBitmapContextGetData(ctx), side * side * 4);
        }
    }
    CGContextRelease(ctx);
    unsigned char bytes[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256_Final(bytes, &hash);
    digest = [NSString stringWithFormat:@"%zux%zu:%@", width, height,
              [[NSData dataWithBytes:bytes length:sizeof bytes] base64EncodedStringWithOptions:0]];
    lastRevision = revision;
    return digest;
}

API_AVAILABLE(ios(26.0))
static void offerCover(void) {
    if (![MPNowPlayingInfoCenter.supportedAnimatedArtworkKeys containsObject:MPNowPlayingInfoProperty3x4AnimatedArtwork]) return;
    if (sg_loadingCover) return;
    CGSize size = SGLyricsClipSize(UIScreen.mainScreen.nativeBounds.size.width);
    UIImage *cover = sg_fallbackCover;
    sg_loadingCover = YES;
    NSUInteger walk = sg_walk;
    NSUInteger revision = sg_coverRevision;
    NSProgress *token = sg_presentation;
    NSString *publishedID = sg_coverPublishedID;
    SGLyricsBackgroundStyle background = sg_background;
    NSString *picture = sg_pendingPicture;
    NSString *title = sg_title;
    dispatch_async(sg_queue, ^{
        if (token.cancelled) return;
        NSString *source = coverSource(cover.CGImage, revision);
        NSURL *file = source ? SGMotionMadeFile([NSString stringWithFormat:@"background\n%@\n%@\n%gx%g\n%@",
                                      picture, SGLyricsBackgroundIdentity(background), size.width, size.height, source]) : nil;
        BOOL unchanged = [file.lastPathComponent isEqual:publishedID];
        CGImageRef rendered = !file || unchanged ? nil : SGLyricsBackgroundCreate(cover.CGImage, size, background);
        UIImage *backdrop = rendered ? [UIImage imageWithCGImage:rendered] : nil;
        CGImageRelease(rendered);
        dispatch_async(dispatch_get_main_queue(), ^{
            if (token.cancelled || walk != sg_walk || SGLockScreenArtwork() != sg_choice) return;
            sg_loadingCover = NO;
            if (revision != sg_coverRevision) {
                retryPresentation();
                return;
            }
            if (![MPNowPlayingInfoCenter.supportedAnimatedArtworkKeys containsObject:MPNowPlayingInfoProperty3x4AnimatedArtwork]) return;
            if (unchanged) {
                sg_pendingPicture = nil;
                return;
            }
            if (!backdrop) return;
            // Retire lazy work only for a different content identity, not for another
            // native wrapper of the same pixels. One worker coalesces intervening changes.
            [sg_presentation cancel];
            NSProgress *offered = [NSProgress progressWithTotalUnitCount:1];
            sg_presentation = offered;
            sg_coverPublishedID = file.lastPathComponent;
            sg_pendingPicture = nil;
            MPMediaItemAnimatedArtwork *artwork = [[MPMediaItemAnimatedArtwork alloc] initWithArtworkID:file.lastPathComponent
                previewImageRequestHandler:^(CGSize wanted, void (^completion)(UIImage *)) {
                    // Already rendered at the clip's exact 3:4 raster; never reshape it to an arbitrary request.
                    completion(offered.cancelled ? nil : backdrop);
                }
                videoAssetFileURLRequestHandler:^(CGSize wanted, void (^completion)(NSURL *)) {
                    SGMotionMakeFile(file, ^BOOL {
                        return !offered.cancelled && SGFluidClipWrite(file, backdrop.CGImage, size);
                    }, ^(BOOL ok) {
                        completion(ok && !offered.cancelled ? file : nil);
                    });
                }];
            SGNowPlayingSetExtras(@"motion", @{MPNowPlayingInfoProperty3x4AnimatedArtwork: artwork}, title);
        });
    });
}

API_AVAILABLE(ios(26.0))
static void retryPresentation(void) {
    // No polling and no decoding while unsupported. Repeated native updates only check capability.
    // A queued notification from before a setting change must not revive the old presentation.
    if (sg_settingsPending || SGLockScreenArtwork() != sg_choice) return;
    if (sg_fallbackPicture) {
        if (![SGURIString(SGPlayerState().track.URI) isEqual:sg_trackURI]) return;
        refreshCover();
        if ([MPNowPlayingInfoCenter.supportedAnimatedArtworkKeys containsObject:MPNowPlayingInfoProperty3x4AnimatedArtwork])
            refreshNativeCover();
    }
    if (sg_pendingPicture) offerCover();
    else if (sg_pendingFile) {
        CGFloat ratio;
        if (keyFor(sg_poster ? sg_poster.size : CGSizeZero, &ratio)) offerVideo();
    }
}

@interface SGLockMotionPresentation : NSObject <SGPlayerStateObserver>
@end
@implementation SGLockMotionPresentation
- (void)playerStateDidChange:(SPTPlayerState *)state {
    [self playerStateDidReport:state];
}
- (void)playerStateDidReport:(SPTPlayerState *)state {
    if (@available(iOS 26.0, *)) {
        // Cover metadata can arrive on a paused report without a now-playing setter.
        if (sg_fallbackPicture) retryPresentation();
    }
}
@end

static void startLockMotion(void) {
    if (@available(iOS 26.0, *)) {
        sg_choice = SGLockScreenArtwork();
        if (sg_choice != SGLockArtworkOff) sg_background = SGLyricsBackgroundRead(@"spotifyglass.lockscreen.background");
        sg_queue = dispatch_queue_create("spotifyglass.lockscreen.motion", DISPATCH_QUEUE_SERIAL);
        static SGLockMotionPresentation *presentationObserver;
        presentationObserver = [SGLockMotionPresentation new];
        SGAddPlayerStateObserver(presentationObserver);
        // Each walk takes the last one's clip off first, so the lock screen falls back to the still cover.
        sg_follower = [[SGMotionFollower alloc] initWithBegin:^BOOL(NSString *uri, SPTPlayerState *state) {
            cancelPresentation();
            SGNowPlayingSetExtras(@"motion", nil, nil);
            sg_lyricsFile = nil;
            sg_plainShown = NO;
            sg_fallbackPicture = nil;
            sg_fallbackCover = nil;
            sg_coverSource = nil;
            sg_coverRequest++;
            sg_nativeArtwork = nil;
            sg_authoritativeCover = NO;
            sg_settingsPending = NO;
            NSDictionary *metadata = [state.track.metadata isKindOfClass:NSDictionary.class] ? state.track.metadata : nil;
            sg_title = state.track.trackTitle;
            sg_trackURI = uri;
            sg_picture = pictureOf(state.track, metadata);
            sg_choice = SGLockScreenArtwork();
            return motionOn(sg_choice);
        } found:^(NSString *uri, NSURL *file) {
            // Under the lyrics instead, and never as this file's extra too: both would fill the same 3:4 key.
            if (sg_choice == SGLockArtworkMotionLyrics) {
                if (file) SGLyricsArtworkSetMotion(uri, file);
                // A track with no synced lines shows it plain, as Moving artwork would; LyricsArtwork.x says which.
                sg_lyricsFile = file;
                SGLockMotionShowPlain(sg_plain);
                SGLog(@"lock motion: %@ for the lyrics of %@", file ? file.lastPathComponent : @"no clip", uri);
            } else if (file) show(file);
            else if (sg_choice == SGLockArtworkEverySong) showCover(sg_picture);
        }];
        // Observer registration does not replay a track that was already playing.
        [sg_follower restart];
        [NSNotificationCenter.defaultCenter addObserverForName:SGNowPlayingInfoDidChangeNotification object:nil queue:nil
                                                    usingBlock:^(NSNotification *note) {
            retryPresentation();
        }];
        // Heard on the writing thread and handed to main without waiting: a main-queue observer makes every
        // background defaults write wait for main, which deadlocks launch while main waits on Spotify's CoreThread.
        [NSNotificationCenter.defaultCenter addObserverForName:NSUserDefaultsDidChangeNotification object:nil queue:nil
                                                    usingBlock:^(NSNotification *note) {
            SGPrefsChanged();
            if (SGLockScreenArtwork() == SGLockArtworkOff && atomic_load(&sg_choice) == SGLockArtworkOff) return;
            dispatch_async(dispatch_get_main_queue(), ^{
                SGLockArtwork choice = SGLockScreenArtwork();
                if (choice == SGLockArtworkOff && sg_choice == SGLockArtworkOff) return;
                SGLyricsBackgroundStyle background = SGLyricsBackgroundRead(@"spotifyglass.lockscreen.background");
                BOOL changed = ![SGLyricsBackgroundIdentity(background) isEqual:SGLyricsBackgroundIdentity(sg_background)];
                sg_background = background;
                if (choice == sg_choice) {
                    if (!changed || !sg_fallbackPicture) return;
                    cancelPresentation();
                    SGNowPlayingSetExtras(@"motion", nil, nil);
                    sg_pendingPicture = sg_fallbackPicture;
                    sg_settingsPending = YES;
                    NSUInteger walk = sg_walk;
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 120 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
                        if (walk != sg_walk) return;
                        sg_settingsPending = NO;
                        retryPresentation();
                    });
                    return;
                }
                SGLog(@"lock motion: the choice changed to %ld, the playing track looked up again", (long)choice);
                sg_choice = choice;
                [sg_follower restart];
            });
        }];
    }
}

%ctor {
    if (@available(iOS 26.0, *)) {
        SGLockArtworkStartWhen(^BOOL { return motionOn(SGLockScreenArtwork()); }, ^(BOOL replay) { startLockMotion(); });
    }
}
