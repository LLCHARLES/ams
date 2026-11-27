// The lock screen's full-screen artwork as the lyrics, a clip per line (SGLyricsClip.h draws it). A timer
// works out the line being sung and hands the lock screen a new artwork under a new ID each time it
// changes. It wakes for the next time the line can change, and again for whatever else changes the
// artwork: a player state, the lines kept, the moving artwork handed over or failing, the phone's heat,
// the style. Nothing is drawn until the lock screen asks for that artwork's video, so lines sung with the
// screen off cost nothing. It rides on Spotify's now playing info as an extra (NowPlayingExtras.h), like
// the moving artwork it takes the place of.
//
// Moving artwork with lyrics draws the lines over the track's moving artwork instead, which
// LockScreenMotion.x finds and hands over (SGLyricsArtworkSetMotion): each line's clip is the stretch of it
// the song is at while the line shows, taken round its length, with the line sung last dimmed above. Until the
// clip comes, and for a track that has none, the lines are drawn as Lyrics draws them; the clip coming
// changes every ID, so the line showing is offered again over it.
#import <MediaPlayer/MediaPlayer.h>
#import <stdatomic.h>
#import <CommonCrypto/CommonDigest.h>
#import <objc/runtime.h>
#import "Core/SGCore.h"
#import "Core/SGFileHash.h"
#import "Core/SGDataRoot.h"
#import "LockScreenLyrics.h"
#import "SGLyricsClip.h"
#import "Shared/AnimatedArtwork/AnimatedArtwork.h"
#import "Shared/Lyrics/Lyrics.h"
#import "Shared/LyricsTranslation/LyricsTranslation.h"
#import "Shared/Player/NowPlayingExtras.h"
#import "Shared/Player/PlayerState.h"
#import "Shared/Player/SpeedPitch.h"
#import "Shared/Player/SGLastTrack.h"
#import "Shared/LyricsBackground/LyricsBackground.h"

extern NSNotificationName const SGKaraokeLookupReadyNotification;
// A line's clip over moving artwork lasts from the line's start to the next one's, a second longer for the
// lock screen showing it late, and between these: the cost of a clip is its length.
static const double kShortest = 2, kLongest = 8;

// What a line's artwork shows, kept by its request blocks.
@interface SGLockLine : NSObject
@property (nonatomic, copy) NSString *previous, *line, *translation, *next;   // nil for none
@property (nonatomic) UIImage *cover;
@property (nonatomic) SGLyricsClipStyle style;
@property (nonatomic) SGLyricsClipLayout layout;
@property (nonatomic) BOOL dimmed;           // Over the artwork dimmed whole (SGKeyLockScreenDimArtwork)
@property (nonatomic) NSURL *motion;        // the moving artwork under the words, nil for the blurred cover
@property (nonatomic) double from, seconds;   // where in the song the clip starts and how long it is
@property (nonatomic) SGLyricsBackgroundStyle background;
@property (nonatomic) CGSize size;
@property (nonatomic) NSUInteger generation;
@property (nonatomic) NSUInteger prefetchGeneration; // zero for system requests
@property (nonatomic) BOOL stillPending;  // under sg_lock; only one ordinary-artwork miss per snapshot
@end

@implementation SGLockLine
@end

static dispatch_source_t sg_timer;
static CFAbsoluteTime sg_due;
// Lyrics are picked and the player is not paused: only then does the timer run.
static BOOL sg_running;
static void tick(void);

// Looks again on main, while the timer runs, for something other than the clock that changes the artwork.
static void tickSoon(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (sg_running) tick();
    });
}
static NSString *sg_motionURI;   // the track the moving artwork is for, and its file (SGLyricsArtworkSetMotion)
static NSURL *sg_motion;
// Paths of moving artwork that would not draw (turned, its frames another size than it states, cut short, or
// gone from the store), so each line goes straight to the cover; a file handed over again is tried again. Read
// on main and both queues, so only under its own lock.
static const NSUInteger kFailedMotionEntries = 32;
static NSMutableOrderedSet<NSString *> *sg_failedMotion;

static BOOL motionFailed(NSURL *file) {
    @synchronized (sg_failedMotion) {
        return [sg_failedMotion containsObject:file.path];
    }
}

static void markMotionFailed(NSURL *file, NSString *artworkID) {
    @synchronized (sg_failedMotion) {
        if ([sg_failedMotion containsObject:file.path]) return;
        if (sg_failedMotion.count >= kFailedMotionEntries) [sg_failedMotion removeObjectAtIndex:0];
        [sg_failedMotion addObject:file.path];
    }
    SGLog(@"lock lyrics: %@ would not draw for %@, the lines go over the cover for it", file.lastPathComponent, artworkID);
    tickSoon();
}
static NSString *sg_track;     // the track the clips are for
static NSArray<SGKaraokeLine *> *sg_lines;
static NSString *sg_lyricsKey;
static NSString *sg_readingKey;
static NSString *sg_readingTag;
static UIImage *sg_cover;      // the cover named by this track's metadata, never a system placeholder
static NSURL *sg_coverURL;     // attempted once per track/source, including a failed load
static NSString *sg_coverKey;  // content identity, including no-cover, in both disk and preview keys
static NSUInteger sg_coverGeneration, sg_renderGeneration, sg_settingsRevision;
static NSUInteger sg_prefetchGeneration = 1; // under sg_lock
static BOOL sg_settingsPending;
static NSString *sg_shownID;   // the artwork handed over last, nil for none; read on sg_queue too
static NSString *sg_aheadID;   // the next line's artwork being drawn ahead, nil for none; under sg_lock
static BOOL sg_aheadCostly;    // its clip has many frames (drawAhead); under sg_lock
static MPMediaItemArtwork *sg_stillArtwork; // main thread: one ordinary artwork for sg_shownID, including ready-frame resends
static UIImage *sg_stillPreview; // last ready lyric frame in this generation, under sg_lock
static NSObject *sg_lock;
static dispatch_queue_t sg_queue;   // writes the clips, one at a time
// Under sg_lock: demand and cache maintenance stay FIFO, ahead of the replaceable next-line job.
static NSMutableArray<void (^)(void)> *sg_clipRequests;
static void (^sg_prefetch)(void);
static BOOL sg_clipWorker;
// Draws the previews, apart from the clips: one waiting behind a clip that takes seconds left the lock screen blank.
static dispatch_queue_t sg_previewQueue;

static NSURL *folder(void) {
    return [SGDataRoot(NSCachesDirectory) URLByAppendingPathComponent:@"Lyrics" isDirectory:YES];
}

static BOOL currentLineLocked(SGLockLine *line) {
    return line.generation == sg_renderGeneration
        && (!line.prefetchGeneration || line.prefetchGeneration == sg_prefetchGeneration);
}

static BOOL currentLine(SGLockLine *line) {
    @synchronized (sg_lock) { return currentLineLocked(line); }
}

static void invalidateRenders(void) {
    @synchronized (sg_lock) { sg_renderGeneration++; sg_prefetch = nil; sg_stillPreview = nil; }
}

static BOOL stillShown(NSString *artworkID) {
    @synchronized (sg_lock) {
        return [artworkID isEqualToString:sg_shownID];
    }
}

static void setShown(NSString *artworkID) {
    @synchronized (sg_lock) {
        if (![artworkID isEqual:sg_shownID]) sg_stillArtwork = nil;
        sg_shownID = artworkID;
        sg_aheadID = nil;
        sg_prefetch = nil;
    }
}

// A clip is still worth its encoding while its line shows, or is the one drawn ahead of it.
static BOOL stillWanted(NSString *artworkID) {
    @synchronized (sg_lock) {
        return [artworkID isEqualToString:sg_shownID] || [artworkID isEqualToString:sg_aheadID];
    }
}

static void drainClip(void) {
    void (^next)(void);
    @synchronized (sg_lock) {
        next = sg_clipRequests.firstObject;
        if (next) [sg_clipRequests removeObjectAtIndex:0];
        else { next = sg_prefetch; sg_prefetch = nil; }
        if (!next) { sg_clipWorker = NO; return; }
    }
    next();
    dispatch_async(sg_queue, ^{ drainClip(); });
}

static void enqueueClip(void (^job)(void), BOOL prefetch) {
    @synchronized (sg_lock) {
        if (prefetch) sg_prefetch = job;
        else [sg_clipRequests addObject:job];
        if (sg_clipWorker) return;
        sg_clipWorker = YES;
    }
    dispatch_async(sg_queue, ^{ drainClip(); });
}

// The lock screen's last asks, as absolute times: lines are drawn ahead only while it is showing them, previews and
// clips each by their own asks, as it asks for clips far less often.
static _Atomic(CFAbsoluteTime) sg_askedAt, sg_previewAskedAt;
// Previews drawn ahead, by artwork ID.
static NSCache<NSString *, UIImage *> *sg_previews;
// Keep the composed still with its animated offer. MediaPlayer falls back to the ordinary artwork
// while changing clips; leaving Spotify's cover there makes every lyric change flash that cover.
static char sg_stillKey, sg_nativeKey;

// One unwrap rule for both app-side cover readers and setter/resend round trips. NSNull records that
// Spotify supplied no native artwork; the composed lyric image must never become a source cover.
static MPMediaItemArtwork *nativeArtwork(MPMediaItemArtwork *artwork) {
    id original = objc_getAssociatedObject(artwork, &sg_nativeKey);
    return original ? (original == NSNull.null ? nil : original) : artwork;
}

static NSURL *clipFile(NSString *artworkID) {
    // Local-track identities contain full metadata; only their digest belongs in a filename.
    NSData *data = [artworkID dataUsingEncoding:NSUTF8StringEncoding];
    NSString *name = SGDataSHA256(data);
    return [folder() URLByAppendingPathComponent:[name stringByAppendingPathExtension:@"mp4"]];
}

// What a line's words go over when not over moving artwork: the selected background, none for a scene, which paints
// the whole picture, and Over the artwork's cover dimmed whole, or none for it kept sharp.
static CGImageRef newBackdrop(SGLockLine *line, CGSize size) CF_RETURNS_RETAINED {
    if (SGLyricsClipIsScene(line.layout)) return NULL;
    if (line.layout == SGLyricsClipOverArtwork) return line.dimmed ? SGLyricsClipDimmedArtwork(line.cover.CGImage, size) : NULL;
    return SGLyricsBackgroundCreate(line.cover.CGImage, size, line.background);
}

// Only on sg_previewQueue, including misses from the synchronous ordinary-artwork handler.
// Moving artwork that will not read uses the selected fallback background.
static UIImage *previewFor(NSString *artworkID, SGLockLine *line, CGSize size) {
    if (!currentLine(line)) return nil;
    UIImage *preview = [sg_previews objectForKey:artworkID];
    BOOL miss = !preview;
    if (!preview) {
        BOOL tryMotion = line.motion && !motionFailed(line.motion);
        CGImageRef frame = tryMotion ? SGLyricsClipMotionFrame(line.motion, line.previous, line.line, line.translation, line.next, line.from,
                                                               line.seconds, line.layout) : NULL;
        if (!frame) {
            if (!currentLine(line)) return nil;
            if (tryMotion) markMotionFailed(line.motion, artworkID);
            CGImageRef backdrop = newBackdrop(line, size);
            frame =SGLyricsClipFrameWithLayout(backdrop, line.cover.CGImage, line.previous, line.line, line.translation, line.next, size,
                                                line.layout);
            CGImageRelease(backdrop);
        }
        if (frame) preview = [UIImage imageWithCGImage:frame];
        CGImageRelease(frame);
    }
    @synchronized (sg_lock) {
        if (!currentLineLocked(line)) return nil;
        if (miss && preview) {
            CGImageRef image = preview.CGImage;
            [sg_previews setObject:preview forKey:artworkID cost:CGImageGetBytesPerRow(image) * CGImageGetHeight(image)];
        }
        // Even a late outgoing frame is a usable synchronous fallback when this generation has none yet.
        if (preview && (!sg_stillPreview || [artworkID isEqual:sg_shownID])) sg_stillPreview = preview;
    }
    return preview;
}

// On sg_queue. A clip drawn ahead is found on disk and handed over at once. Over moving artwork that will not
// read, it is drawn over the selected background. The encoders ask `live` each frame, so a line sung or
// skipped past while its clip is written stops there instead of encoding to the end for nobody.
static BOOL writeClip(NSString *artworkID, SGLockLine *line, CGSize size) {
    // Once no, no for the rest of this write: seeking back to the line before the writer returns must not make
    // a stopped clip look like moving artwork that would not draw. The encoder's queue asks only while this
    // queue waits for it (writeReady), so the two never ask at once.
    __block BOOL stopped = NO;
    BOOL (^live)(void) = ^BOOL {
        if (!stopped && !(currentLine(line) && stillWanted(artworkID))) stopped = YES;
        return !stopped;
    };
    if (!live()) return NO;
    NSURL *file = clipFile(artworkID);
    if (!file) return NO;
    if ([NSFileManager.defaultManager fileExistsAtPath:file.path]) return YES;
    CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
    BOOL tryMotion = line.motion && !motionFailed(line.motion);
    BOOL over = tryMotion && SGLyricsClipWriteOverMotion(file, line.motion, line.previous, line.line, line.translation, line.next, line.from,
                                                         line.seconds, line.layout, live);
    if (!live()) return NO;
    if (tryMotion && !over) markMotionFailed(line.motion, artworkID);
    BOOL ok = over;
    if (!ok) {
        CGImageRef backdrop = newBackdrop(line, size);
        ok =SGLyricsClipWriteWithLayout(file, backdrop, line.cover.CGImage, line.previous, line.line, line.translation, line.next,
                                         size, line.style, line.layout, live);
        CGImageRelease(backdrop);
    }
    // Stopped for a line gone by: not a failure to log.
    if (!live()) return NO;
    // The first few of a launch of each kind, and any that fails: one a line would fill the log.
    static NSUInteger told[2];
    if (!ok || told[over]++ < 5) {
        SGLog(@"lock lyrics: %@ %@ in %.0f ms%@", artworkID, ok ? @"written" : @"not written", (CFAbsoluteTimeGetCurrent() - start) * 1000,
              over ? [NSString stringWithFormat:@", up to %.1f s of %@ from %.1f s", line.seconds, line.motion.lastPathComponent, line.from] : @"");
    }
    return ok && live();
}

// The next line's preview and clip, drawn while this one shows: a line change then hands both over at once, where
// drawing them on request left the lock screen on the plain cover for half a second. A clip of many frames (over
// moving artwork, or the breathing style) waits for the lock screen's ask once the phone is warm: drawn ahead
// line after line, it kept the encoder busy for as long as the lock screen had asked within 15 seconds.
static void drawAhead(NSString *artworkID, SGLockLine *line) {
    if (NSProcessInfo.processInfo.lowPowerModeEnabled) return;
    CFAbsoluteTime time = CFAbsoluteTimeGetCurrent();
    CGSize size = line.size;
    BOOL costly = line.motion || line.style == SGLyricsClipAnimated;
    BOOL warm = NSProcessInfo.processInfo.thermalState >= NSProcessInfoThermalStateFair;
    @synchronized (sg_lock) {
        line.prefetchGeneration = sg_prefetchGeneration;
        sg_aheadID = artworkID;
        sg_aheadCostly = costly;
        if (time - sg_previewAskedAt <= 15) dispatch_async(sg_previewQueue, ^{ previewFor(artworkID, line, size); });
        if (time - sg_askedAt <= 15 && !(costly && warm)) enqueueClip(^{ writeClip(artworkID, line, size); }, YES);
    }
}

API_AVAILABLE(ios(26.0))
static MPMediaItemAnimatedArtwork *artworkFor(NSString *artworkID, SGLockLine *line) {
    CGSize size = line.size;
    NSString *title = SGPlayerState().track.trackTitle;
    MPMediaItemAnimatedArtwork *artwork = [[MPMediaItemAnimatedArtwork alloc] initWithArtworkID:artworkID
        previewImageRequestHandler:^(CGSize wanted, void (^completion)(UIImage *)) {
            if (!currentLine(line)) { completion(nil); return; }
            // Only an ask for the line showing says the lock screen is following the lines.
            if (stillShown(artworkID)) sg_previewAskedAt = CFAbsoluteTimeGetCurrent();
            // One drawn ahead is handed over at once, as Apple asks of a preview; only a miss waits for drawing.
            UIImage *ready = [sg_previews objectForKey:artworkID];
            if (ready) {
                completion(ready);
                return;
            }
            dispatch_async(sg_previewQueue, ^{
                completion(previewFor(artworkID, line, size));
                static NSUInteger told;
                if (told++ < 10) SGLog(@"lock lyrics: preview of %@ was not drawn ahead", artworkID);
            });
        }
        videoAssetFileURLRequestHandler:^(CGSize wanted, void (^completion)(NSURL *)) {
            // A late ask for a line already gone by must not keep the next lines drawn ahead.
            if (stillShown(artworkID)) sg_askedAt = CFAbsoluteTimeGetCurrent();
            enqueueClip(^{
                // A line already sung by the time its turn comes is not drawn.
                if (!stillShown(artworkID)) {
                    completion(nil);
                    return;
                }
                BOOL ok = writeClip(artworkID, line, size);
                completion(ok && stillShown(artworkID) ? clipFile(artworkID) : nil);
            }, NO);
        }];
    MPMediaItemArtwork *still = sg_stillArtwork;
    if (!still) still = [[MPMediaItemArtwork alloc] initWithBoundsSize:size requestHandler:^UIImage *(CGSize wanted) {
        UIImage *ready = [sg_previews objectForKey:artworkID], *previous;
        BOOL start = NO;
        @synchronized (sg_lock) {
            if (line.generation != sg_renderGeneration) return nil;
            if (ready) {
                if ([artworkID isEqual:sg_shownID]) sg_stillPreview = ready;
                return ready;
            }
            previous = sg_stillPreview;
            if (!line.stillPending) { line.stillPending = YES; start = YES; }
        }
        // Callers include main-thread cover readers. A miss never renders or waits on this thread;
        // keep the last lyric frame (or nothing on first demand), never Spotify's plain cover.
        if (start) dispatch_async(sg_previewQueue, ^{
            UIImage *image = previewFor(artworkID, line, size);
            @synchronized (sg_lock) { line.stillPending = NO; }
            if (!image) return;
            dispatch_async(dispatch_get_main_queue(), ^{
                if (!currentLine(line) || !stillShown(artworkID)) return;
                // Re-offer the ready preview without changing this ID's ordinary-artwork identity.
                SGNowPlayingSetExtras(@"lyrics", @{MPNowPlayingInfoProperty3x4AnimatedArtwork: artworkFor(artworkID, line)}, title);
            });
        });
        return previous;
    }];
    sg_stillArtwork = still;
    objc_setAssociatedObject(artwork, &sg_stillKey, still, OBJC_ASSOCIATION_RETAIN);
    return artwork;
}

// This hook runs inside NowPlayingExtras' hook (the tweak's sorted source order), so it sees the
// complete offer. Restore the native artwork before replacing it: getter/resend round trips and
// clearing lyrics must not feed a composed lyric frame back into the cover resolver.
%hook MPNowPlayingInfoCenter
- (NSDictionary *)nowPlayingInfo {
    NSDictionary *info = %orig;
    id shown = info[MPMediaItemPropertyArtwork];
    id native = nativeArtwork(shown);
    if (native == shown) return info;
    NSMutableDictionary *source = [info mutableCopy];
    if (native) source[MPMediaItemPropertyArtwork] = native;
    else [source removeObjectForKey:MPMediaItemPropertyArtwork];
    return source;
}
- (void)setNowPlayingInfo:(NSDictionary *)info {
    if (@available(iOS 26.0, *)) {
    id supplied = info[MPMediaItemPropertyArtwork], native = nativeArtwork(supplied);
    id animated = info[MPNowPlayingInfoProperty3x4AnimatedArtwork];
    MPMediaItemArtwork *still = objc_getAssociatedObject(animated, &sg_stillKey);
    if (!still && native == supplied) {
        %orig;
        return;
    }
    NSMutableDictionary *composed = [info mutableCopy];
    if (still) {
        // Artist-row ticks and Spotify/extras resends must not look like another still-artwork change.
        objc_setAssociatedObject(still, &sg_nativeKey, native ?: NSNull.null, OBJC_ASSOCIATION_RETAIN);
        composed[MPMediaItemPropertyArtwork] = still;
    } else if (native) {
        composed[MPMediaItemPropertyArtwork] = native;
    } else {
        [composed removeObjectForKey:MPMediaItemPropertyArtwork];
    }
    %orig(composed);
    return;
    }
    %orig;
}
%end

static void clear(void) {
    invalidateRenders();
    if (!sg_shownID) return;
    setShown(nil);
    SGNowPlayingSetExtras(@"lyrics", nil, nil);
}

// A line as the lyrics show it: the larger of its words and their pronunciation (SGLyricsShownLine).
static NSString *textAt(NSArray<SGKaraokeLine *> *lines, NSInteger index) {
    SGKaraokeLine *line = SGLyricsShownLine(sg_track, lines, index, NULL);
    return line ? SGKaraokeLineText(line) : nil;
}

// What the artwork shows under the line, nil when it is resting: its translation with the switch on, where it has
// one, else the other of its words and their pronunciation, nil for a line the lyrics show no pronunciation for.
static NSString *translationAt(NSArray<SGKaraokeLine *> *lines, NSInteger index, BOOL resting) {
    if (resting || index < 0 || index >= (NSInteger)lines.count) return nil;
    if (!textAt(lines, index).length) return nil;
    NSString *translation = SGFlag(SGKeyLockScreenTranslation, NO) ? SGLyricsShownTranslation(lines[index]) : nil;
    if (translation.length) return translation;
    SGKaraokeLine *under = nil;
    SGLyricsShownLine(sg_track, lines, index, &under);
    return under ? SGKaraokeLineText(under) : translation;
}

// The translation's part of an artwork ID: nothing without one, else t and a short hex of its hash, the same
// for a translation that has not changed, so a clip drawn ahead is found instead of drawn again.
static NSString *translationTag(NSString *translation) {
    if (!translation.length) return @"";
    uint32_t hash = 2166136261u;
    const char *bytes = translation.UTF8String;
    for (size_t i = 0; bytes[i]; i++) hash = (hash ^ (uint8_t)bytes[i]) * 16777619u;
    return [NSString stringWithFormat:@"t%08x", hash];
}

static NSString *coverKey(UIImage *cover) {
    NSData *data = UIImagePNGRepresentation(cover);
    unsigned char digest[CC_SHA1_DIGEST_LENGTH];
    CC_SHA1(data.bytes, (CC_LONG)data.length, digest);
    NSMutableString *key = [NSMutableString stringWithString:@"c"];
    for (NSUInteger i = 0; i < sizeof(digest); i++) [key appendFormat:@"%02x", digest[i]];
    return key;
}

// Source lines are immutable once built; generated translations have their own tag below.
// Include the timing that chooses a line and the motion interval, not just its array index.
static NSString *lyricsKey(NSArray<SGKaraokeLine *> *lines) {
    NSMutableArray *rows = [NSMutableArray arrayWithCapacity:lines.count];
    for (SGKaraokeLine *line in lines)
        [rows addObject:@[SGKaraokeLineText(line) ?: @"", @(line.start), @(line.end), @(SGKaraokeSungEnd(line))]];
    NSData *data = [NSJSONSerialization dataWithJSONObject:rows options:0 error:nil];
    return SGDataSHA256(data);
}

static NSString *readingKey(NSString *tag, NSString *track, NSArray<SGKaraokeLine *> *lines) {
    if (!tag.length) return tag;
    NSMutableArray *rows = [NSMutableArray array];
    for (NSInteger index = 0; index < (NSInteger)lines.count; index++) {
        SGKaraokeLine *under = nil;
        SGKaraokeLine *line = SGLyricsShownLine(track, lines, index, &under);
        [rows addObject:@[SGKaraokeLineText(line) ?: @"", SGKaraokeLineText(under) ?: @""]];
    }
    NSArray *identity = @[tag, SGLyricsTrackLanguage(track) ?: SGLyricsDetectedLanguage(lines) ?: @"", rows];
    return SGDataSHA256([NSJSONSerialization dataWithJSONObject:identity options:0 error:nil]);
}

static BOOL currentCoverRequest(NSUInteger generation, NSString *trackID, SGShownTrack *track) {
    if (generation != sg_coverGeneration || ![trackID isEqual:SGKaraokePlayingTrack()]) return NO;
    SGShownTrack *now = SGShownTrackNow();
    return now.current && [now.uri isEqual:track.uri] && [now.artworkURL isEqual:track.artworkURL];
}

void SGLyricsArtworkSetMotion(NSString *uri, NSURL *file) {
    @synchronized (sg_failedMotion) {
        if (file) [sg_failedMotion removeObject:file.path];
    }
    sg_motionURI = uri;
    sg_motion = file;
    tickSoon();
}

// What the artwork for line `index` shows, `resting` once its break has come (index -1, before the first line,
// always rests). Over moving artwork, the stretch of song from when it shows until the next artwork does.
static SGLockLine *lineAt(NSArray<SGKaraokeLine *> *lines, NSInteger index, BOOL resting, NSURL *motion,
                          UIImage *cover, SGLyricsClipStyle style, SGLyricsClipLayout layout, BOOL dimmed,
                          SGLyricsBackgroundStyle background, CGSize size) {
    SGLockLine *shown = [SGLockLine new];
    // Resting, the line sung is let go and the one coming shows alone. The line sung last shows over moving artwork
    // and in Messages; the clip leaves it out elsewhere.
    shown.line = resting ? nil : textAt(lines, index);
    shown.translation = translationAt(lines, index, resting);
    shown.next = textAt(lines, index + 1);
    shown.previous = resting ? nil : textAt(lines, index - 1);
    shown.cover = cover;
    shown.style = style;
    shown.layout = layout;
    shown.dimmed = dimmed;
    shown.motion = motion;
    shown.background = background;
    shown.size = size;
    shown.generation = sg_renderGeneration;
    NSInteger start = index < 0 ? 0 : resting ? SGKaraokeSungEnd(lines[index]) + SGKaraokeBreakMs : lines[index].start;
    NSInteger end = index + 1 < (NSInteger)lines.count ? lines[index + 1].start
                  : index < 0 ? start : SGKaraokeSungEnd(lines[index]) + SGKaraokeBreakMs;
    shown.from = start / 1000.0;
    shown.seconds = MIN(MAX((end - start) / 1000.0 + 1, kShortest), kLongest);
    return shown;
}

// Offers the artwork for where the song is, and says in how many seconds of the song's time to look again:
// negative for not until something else changes. Past a line's sung
// end by SGKaraokeBreakMs, with the next line at least that far off, the line rests: it is let go and only the
// next one shows, dimmed (as the artist row does in LockScreenLyrics.x).
static NSTimeInterval update(void) {
    if (@available(iOS 26.0, *)) {
        if (sg_settingsPending || !SGLockArtworkShowsLyrics(SGLockScreenArtwork())) return -1;
        SPTPlayerState *state = SGPlayerState();
        NSString *trackID = SGKaraokePlayingTrack();
        if (!trackID || !state) {
            clear();
            return -1;
        }
        if (![trackID isEqualToString:sg_track]) {
            sg_track = trackID;
            sg_lines = nil;
            sg_lyricsKey = nil;
            sg_cover = nil;
            sg_coverURL = nil;
            sg_coverKey = @"no-cover";
            sg_coverGeneration++;
            invalidateRenders();
            // The worker owns cleanup too: no new-track request may overtake it.
            enqueueClip(^{
                NSURL *dir = folder();
                if (!dir) return;
                [NSFileManager.defaultManager removeItemAtURL:dir error:nil];
                [NSFileManager.defaultManager createDirectoryAtURL:dir withIntermediateDirectories:YES attributes:nil error:nil];
            }, NO);
        }
        NSArray<SGKaraokeLine *> *lines = SGKaraokeLinesForTrack(trackID);
        if (sg_lines != lines) {
            sg_readingTag = nil;
            NSString *key = lyricsKey(lines);
            sg_lines = lines;
            if (![key isEqual:sg_lyricsKey]) {
                sg_lyricsKey = key;
                invalidateRenders();
            }
        }
        if (!lines) SGKaraokeRequestLyrics(trackID);
        // Plain text has no line being sung, nor has a song whose lines are not in yet: the lock screen keeps the cover,
        // or under Moving artwork with lyrics shows the moving artwork plain (LockScreenMotion.x, which has it).
        if (!lines.count || SGKaraokeLinesTiming(lines) == SGKaraokeTimingNone) {
            static NSString *told;
            if (lines && ![told isEqualToString:trackID]) {
                told = trackID;
                SGLog(@"lock lyrics: %@ has no synced lines, the lock screen keeps the cover or the moving artwork", trackID);
            }
            clear();
            SGLockMotionShowPlain(YES);
            return -1;
        }
        NSInteger position = SGKaraokePositionMs();
        if (position < 0) return -1;
        position -= SGKaraokeDelayMs();
        NSInteger index = SGKaraokeLeadLine(lines, position);
        BOOL translationOn = SGFlag(SGKeyLockScreenTranslation, NO);
        // Translations wanted here: the switch on and the lines on the lock screen at all. Asked once a track and
        // language, not every tick; the call syncs saved ones first and de-duplicates one already running.
        static NSString *translatedTrack, *translatedLanguage;
        static NSArray<SGKaraokeLine *> *translatedLines;
        if (!translationOn) {
            translatedTrack = nil;
        } else {
            NSString *language = SGLyricsGeminiLanguage();
            // A refined source hands over a new array for the same track: it needs the saved translations too.
            if (![translatedTrack isEqualToString:trackID] || ![translatedLanguage isEqualToString:language] || translatedLines != lines) {
                translatedTrack = trackID;
                translatedLanguage = language;
                translatedLines = lines;
                SGRAutoTranslateWithoutView(trackID, lines, ^BOOL {
                    return [trackID isEqualToString:SGKaraokePlayingTrack()] && SGFlag(SGKeyLockScreenTranslation, NO)
                        && lines == SGKaraokeLinesForTrack(trackID) && [language isEqual:SGLyricsGeminiLanguage()]
                        && SGLockArtworkShowsLyrics(SGLockScreenArtwork());
                }, ^{ sg_readingTag = nil; tick(); });
            }
        }
        NSInteger ms = SGKaraokeMsToChange(lines, position, -1);
        // A ms on, past the truncation of the position.
        NSTimeInterval wait = ms > 0 ? (ms + 1) / 1000.0 : -1;
        BOOL nextFarOff = index + 1 == (NSInteger)lines.count || lines[index + 1].start - position > SGKaraokeBreakMs;
        BOOL resting = index < 0 || (position > SGKaraokeSungEnd(lines[index]) + SGKaraokeBreakMs && nextFarOff);
        SGLyricsClipStyle style = (SGLyricsClipStyle)SGInt(SGKeyLockScreenLyricsStyle, SGLyricsClipStill);
        SGLyricsClipLayout layout = (SGLyricsClipLayout)SGInt(SGKeyLockScreenLyricsLayout, SGLyricsClipLeft);
        BOOL dimmed = layout == SGLyricsClipOverArtwork && SGFlag(SGKeyLockScreenDimArtwork, NO);
        SGLyricsBackgroundStyle background = SGLyricsBackgroundRead(@"spotifyglass.lockscreen.background");
        CGSize size = SGLyricsClipSize(UIScreen.mainScreen.nativeBounds.size.width);
        // A scene covers the whole picture, so it is drawn over the cover even under Moving artwork with lyrics; so is
        // Over the artwork, unless it is dimmed whole.
        NSURL *motion = SGLockScreenArtwork() == SGLockArtworkMotionLyrics && !SGLyricsClipIsScene(layout)
            && (layout != SGLyricsClipOverArtwork || dimmed) && [sg_motionURI isEqualToString:SGURIString(state.track.URI)] ? sg_motion : nil;
        if (motion && motionFailed(motion)) motion = nil;
        // A line over moving artwork decodes and encodes up to 240 frames, a breathing one 60, a still one a single
        // frame: a phone already hot, or saving power, gets the still over the cover, as Sing.x keeps its model below
        // Serious, and the chosen look back once it cools or Low Power Mode is off.
        if ((motion || style != SGLyricsClipStill) && (NSProcessInfo.processInfo.thermalState >= NSProcessInfoThermalStateSerious
                                                       || NSProcessInfo.processInfo.lowPowerModeEnabled)) {
            static CFAbsoluteTime told;
            if (CFAbsoluteTimeGetCurrent() - told > 60) SGLog(@"lock lyrics: the phone is hot or saving power, the lines go still over the cover");
            told = CFAbsoluteTimeGetCurrent();
            motion = nil;
            style = SGLyricsClipStill;
        }
        NSString *look = SGLyricsClipLook(motion, style, layout, dimmed);
        // A non-nil MPNowPlaying image is not evidence of a cover: it may be Spotify's
        // placeholder, or the previous same-title track's image. Load the current URI's
        // metadata through the shared loader instead. Until then the renderer gets nil.
        SGShownTrack *shown = SGShownTrackNow();
        NSURL *url = shown.current && [shown.uri isEqual:SGURIString(state.track.URI)] ? shown.artworkURL : nil;
        if ((url || sg_coverURL) && ![url isEqual:sg_coverURL]) {
            sg_coverURL = url;
            // A pending URL does not change a coverless frame. Keep its request blocks
            // valid until pixels change; otherwise the unchanged ID keeps a cancelled offer.
            if (sg_cover) invalidateRenders();
            sg_cover = nil;
            sg_coverKey = @"no-cover";
            NSUInteger generation = ++sg_coverGeneration;
            if (url) {
                // A failed authoritative load gets one retry while the track, source URL and artwork
                // choice are still current; a second failure keeps the dark fallback, never old art.
                SGShownTrackArtworkBounded(shown, ^BOOL {
                    return currentCoverRequest(generation, trackID, shown) && [url isEqual:sg_coverURL]
                        && SGLockArtworkShowsLyrics(SGLockScreenArtwork());
                }, ^(UIImage *cover) {
                    if (!cover || !currentCoverRequest(generation, trackID, shown)) return;
                    dispatch_async(sg_previewQueue, ^{
                        NSString *key = coverKey(cover);
                        dispatch_async(dispatch_get_main_queue(), ^{
                            if (!currentCoverRequest(generation, trackID, shown)) return;
                            sg_cover = cover;
                            sg_coverKey = key;
                            invalidateRenders();
                            tick();
                        });
                    });
                });
            }
        }
        NSString *backgroundID = [NSString stringWithFormat:@"%@-%gx%g", SGLyricsBackgroundIdentity(background), size.width, size.height];
        // The pronunciation's choice changes the words of every line drawn, the ones before and after included.
        NSString *tag = SGLyricsShownLineTag();
        if (![tag isEqual:sg_readingTag]) {
            sg_readingTag = tag;
            NSString *key = readingKey(tag, trackID, lines);
            if (![key isEqual:sg_readingKey]) invalidateRenders();
            sg_readingKey = key;
        }
        NSString *reading = sg_readingKey;
        NSString *artworkID = [NSString stringWithFormat:@"%@-%ld%@%@%@-%@-%@-%@-%@", trackID, (long)index, resting ? @"r" : @"",
                               translationTag(translationAt(lines, index, resting)), reading, sg_lyricsKey, sg_coverKey, backgroundID, look];
        if ([artworkID isEqualToString:sg_shownID]) return wait;
        if (![sg_shownID hasPrefix:trackID]) SGLog(@"lock lyrics: lines offered for %@", trackID);
        if (motion && ![sg_shownID hasSuffix:[@"-" stringByAppendingString:look]]) SGLog(@"lock lyrics: the lines of %@ over %@", trackID, motion.lastPathComponent);
        setShown(artworkID);
        SGLockMotionShowPlain(NO);
        SGNowPlayingSetExtras(@"lyrics", @{MPNowPlayingInfoProperty3x4AnimatedArtwork:
                                               artworkFor(artworkID, lineAt(lines, index, resting, motion, sg_cover, style, layout, dimmed, background, size))},
                              state.track.trackTitle);
        if (index + 1 < (NSInteger)lines.count) {
            NSString *ahead = [NSString stringWithFormat:@"%@-%ld%@%@-%@-%@-%@-%@", trackID, (long)index + 1,
                               translationTag(translationAt(lines, index + 1, NO)), reading, sg_lyricsKey, sg_coverKey, backgroundID, look];
            drawAhead(ahead, lineAt(lines, index + 1, NO, motion, sg_cover, style, layout, dimmed, background, size));
        }
        return wait;
    }
    return -1;
}

static void stopTicking(void) {
    if (sg_timer) dispatch_source_cancel(sg_timer);
    sg_timer = nil;
}

// Main thread, as everything the timer touches is. Offers the artwork for now and, while sg_running, arms the
// timer for the next look; else stops it.
static void tick(void) {
    NSTimeInterval wait = update();
    if (!sg_running || wait < 0) {
        stopTicking();
        return;
    }
    if (!sg_timer) {
        // A strict GCD timer: the main run loop's timers are throttled while the screen is off, and the lines stood
        // still on a locked phone.
        sg_timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, DISPATCH_TIMER_STRICT, dispatch_get_main_queue());
        dispatch_source_set_event_handler(sg_timer, ^{
            static int late;
            CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
            if (now - sg_due > 2 && late++ < 5) SGLog(@"%s: ticked %.1f s late", __FILE_NAME__, now - sg_due);
            tick();
        });
        dispatch_resume(sg_timer);
    }
    double speed = SGPlayerState().playbackSpeed;
    NSTimeInterval seconds = wait / (speed > 0 ? speed : 1);
    sg_due = CFAbsoluteTimeGetCurrent() + seconds;
    dispatch_source_set_timer(sg_timer, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(seconds * NSEC_PER_SEC)), DISPATCH_TIME_FOREVER, 10 * NSEC_PER_MSEC);
}

@interface SGLyricsArtwork : NSObject <SGPlayerStateObserver>
@end

@implementation SGLyricsArtwork
// A paused player's line does not move, and the lock screen keeps the clip it was left on. Picked or not is read
// each time, so a change on the Lock screen page applies at once.
- (void)playerStateDidChange:(SPTPlayerState *)state {
    BOOL on = SGLockArtworkShowsLyrics(SGLockScreenArtwork());
    sg_running = on && !state.isPaused;
    if (on) tick();
    else {
        stopTicking();
        clear();
    }
}
// Even a small position-only seek can cross a deadline. Paused reports can carry late artwork.
- (void)playerStateDidReport:(SPTPlayerState *)state {
    if (!SGLockArtworkShowsLyrics(SGLockScreenArtwork())) return;
    sg_running = !state.isPaused;
    tick();
}
@end

#import "Shared/AnimatedArtwork/SGLockArtworkStart.h"

static void startLyricsArtwork(BOOL replay) {
    if (@available(iOS 26.0, *)) {
        sg_lock = [NSObject new];
        sg_queue = dispatch_queue_create("spotifyglass.lockscreen.lyrics", DISPATCH_QUEUE_SERIAL);
        sg_clipRequests = [NSMutableArray array];
        sg_previewQueue = dispatch_queue_create("spotifyglass.lockscreen.lyrics.preview", DISPATCH_QUEUE_SERIAL);
        sg_previews = [NSCache new];
        sg_failedMotion = [NSMutableOrderedSet orderedSet];
        sg_previews.countLimit = 4;
        sg_previews.totalCostLimit = 16 * 1024 * 1024;
        [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidReceiveMemoryWarningNotification object:nil queue:nil
            usingBlock:^(NSNotification *note) {
                // Keep the displayed still and outstanding system requests, not speculative lines.
                @synchronized (sg_lock) {
                    sg_prefetchGeneration++;
                    sg_askedAt = sg_previewAskedAt = 0;
                    sg_prefetch = nil;
                    [sg_previews removeAllObjects];
                }
            }];
        static SGLyricsArtwork *observer;
        observer = [SGLyricsArtwork new];
        SGAddPlayerStateObserver(observer);
        [NSNotificationCenter.defaultCenter addObserverForName:SGPlayerSpeedDidChangeNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
            [observer playerStateDidReport:SGPlayerState()];
        }];
        [NSNotificationCenter.defaultCenter addObserverForName:SGNowPlayingInfoDidChangeNotification object:nil queue:nil
                                                    usingBlock:^(NSNotification *note) {
            if (SGLockArtworkShowsLyrics(SGLockScreenArtwork())) tick();
        }];
        // Main owns the applied settings snapshot, like the artwork it describes.
        static _Atomic(SGLockArtwork) choice; // main is the sole writer
        static NSInteger style, layout, delay;
        static BOOL dim;
        choice = SGLockScreenArtwork();
        __block NSString *background = choice == SGLockArtworkOff ? nil : SGLyricsBackgroundIdentity(SGLyricsBackgroundRead(@"spotifyglass.lockscreen.background"));
        __block BOOL translation = SGFlag(SGKeyLockScreenTranslation, NO);
        __block NSString *reading = SGLyricsShownLineTag();
        // A translation saved while the player is paused has no tick to pick it up (Shared/LyricsTranslation).
        for (NSNotificationName name in @[SGLyricsTranslationSavedNotification, SGLyricsTranslationsDidChangeNotification]) {
        [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:nil
                                                    usingBlock:^(NSNotification *note) {
            dispatch_async(dispatch_get_main_queue(), ^{
                BOOL saved = [note.name isEqual:SGLyricsTranslationSavedNotification];
                NSString *track = saved ? note.object : SGKaraokePlayingTrack();
                if (![track isEqualToString:SGKaraokePlayingTrack()] || !SGLockArtworkShowsLyrics(SGLockScreenArtwork())
                    || (saved && ![note.userInfo[@"language"] isEqual:SGLyricsGeminiLanguage()])
                    || !SGFlag(SGKeyLockScreenTranslation, NO)) return;
                NSArray<SGKaraokeLine *> *lines = SGKaraokeLinesForTrack(track);
                NSString *language = SGLyricsGeminiLanguage();
                SGLyricsLoadTranslation(track, language, lines, ^BOOL {
                    return [track isEqual:SGKaraokePlayingTrack()] && [language isEqual:SGLyricsGeminiLanguage()]
                        && lines == SGKaraokeLinesForTrack(track) && SGLockArtworkShowsLyrics(SGLockScreenArtwork())
                        && SGFlag(SGKeyLockScreenTranslation, NO);
                }, ^{ sg_readingTag = nil; tick(); });
            });
        }];
        }
        style = SGInt(SGKeyLockScreenLyricsStyle, SGLyricsClipStill);
        layout = SGInt(SGKeyLockScreenLyricsLayout, SGLyricsClipLeft);
        // Dimming the whole artwork changes only Over the artwork's lines.
        dim = layout == SGLyricsClipOverArtwork && SGFlag(SGKeyLockScreenDimArtwork, NO);
        delay = SGKaraokeDelayMs();
        [NSNotificationCenter.defaultCenter addObserverForName:NSUserDefaultsDidChangeNotification object:nil queue:nil
                                                    usingBlock:^(NSNotification *note) {
            // The style, the layout and the lyrics' delay apply at once, and move the artwork or its next change.
            SGPrefsChanged();
            if (SGLockScreenArtwork() == SGLockArtworkOff && atomic_load(&choice) == SGLockArtworkOff) return;
            dispatch_async(dispatch_get_main_queue(), ^{
                SGLockArtwork picked = SGLockScreenArtwork();
                BOOL enabling = choice == SGLockArtworkOff;
                if (enabling && picked == SGLockArtworkOff) return;
                NSInteger nowStyle = SGInt(SGKeyLockScreenLyricsStyle, SGLyricsClipStill), nowDelay = SGKaraokeDelayMs();
                NSInteger nowLayout = SGInt(SGKeyLockScreenLyricsLayout, SGLyricsClipLeft);
                BOOL nowDim = nowLayout == SGLyricsClipOverArtwork && SGFlag(SGKeyLockScreenDimArtwork, NO);
                NSString *next = SGLyricsBackgroundIdentity(SGLyricsBackgroundRead(@"spotifyglass.lockscreen.background"));
                BOOL nowTranslation = SGFlag(SGKeyLockScreenTranslation, NO);
                NSString *nowReading = SGLyricsShownLineTag();
                BOOL changed = ![next isEqual:background] || nowStyle != style || nowLayout != layout || nowDim != dim;
                BOOL reread = ![nowReading isEqualToString:reading];
                if (picked == choice && !changed && nowDelay == delay && nowTranslation == translation && !reread) return;
                background = next;
                style = nowStyle;
                layout = nowLayout;
                dim = nowDim;
                delay = nowDelay;
                translation = nowTranslation;
                reading = nowReading;
                choice = picked;
                if (reread) invalidateRenders();
                if (!enabling && changed && SGLockArtworkShowsLyrics(picked)) {
                    clear();
                    sg_settingsPending = YES;
                    NSUInteger revision = ++sg_settingsRevision;
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 120 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
                        if (revision != sg_settingsRevision) return;
                        sg_settingsPending = NO;
                        [observer playerStateDidChange:SGPlayerState()];
                    });
                    return;
                }
                sg_settingsRevision++;
                sg_settingsPending = NO;
                SGLog(@"lock lyrics: %@", !SGLockArtworkShowsLyrics(picked) ? @"no longer picked" : picked == SGLockArtworkLyrics ? @"picked" : @"picked over the moving artwork");
                [observer playerStateDidChange:SGPlayerState()];
            });
        }];
        // The lyrics view applies saved AI readings in its own notification handler. Hash only
        // after all observers have returned, whichever one received the notification first.
        [NSNotificationCenter.defaultCenter addObserverForName:SGLyricsAIResultDidChangeNotification object:nil queue:nil
                                                    usingBlock:^(NSNotification *note) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (note.object && ![note.object isEqual:SGKaraokePlayingTrack()]) return;
                sg_readingTag = nil;
                if (SGLockArtworkShowsLyrics(SGLockScreenArtwork())) tick();
            });
        }];
        // Lines kept for the track, or better timed ones in their place, are posted on main.
        for (NSNotificationName name in @[SGKaraokeLookupReadyNotification, SGKaraokeLinesKeptNotification, SGLyricsReadingsDidChangeNotification,
                                          SGLyricsLanguageDidChangeNotification, SGLyricsOffsetsDidChangeNotification]) {
        [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:nil
                                                    usingBlock:^(NSNotification *note) {
            if (note.object && ![note.object isEqual:SGKaraokePlayingTrack()]) return;
            if (![note.name isEqual:SGLyricsOffsetsDidChangeNotification]) sg_readingTag = nil;
            if (SGLockArtworkShowsLyrics(SGLockScreenArtwork())) tick();
        }];
        }
        // A hot phone, or Low Power Mode, puts the lines still over the cover, and the chosen look comes back after,
        // paused too: the paused line's offer changes. A clip of many frames drawn ahead, queued or under way, is let
        // go from Fair up or in Low Power Mode, as drawAhead no longer starts one there; the line showing keeps its own.
        for (NSNotificationName name in @[NSProcessInfoThermalStateDidChangeNotification, NSProcessInfoPowerStateDidChangeNotification]) {
        [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:nil
                                                    usingBlock:^(NSNotification *note) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (!SGLockArtworkShowsLyrics(SGLockScreenArtwork())) return;
                NSProcessInfo *info = NSProcessInfo.processInfo;
                if (info.thermalState >= NSProcessInfoThermalStateFair || info.lowPowerModeEnabled) {
                    @synchronized (sg_lock) {
                        if (sg_aheadCostly) {
                            sg_prefetch = nil;
                            sg_aheadID = nil;
                        }
                    }
                }
                tick();
            });
        }];
        }
        if (replay) [observer playerStateDidChange:SGPlayerState()];
    }
}

%ctor {
    if (@available(iOS 26.0, *)) {
        // Keep these inside NowPlayingExtras' hooks even if lyrics are first selected mid-song.
        %init;
        SGLockArtworkStartWhen(^BOOL { return SGLockArtworkShowsLyrics(SGLockScreenArtwork()); },
                               ^(BOOL replay) { startLyricsArtwork(replay); });
    }
}
