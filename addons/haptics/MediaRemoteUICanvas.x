// Vitrine Addon in MediaRemoteUI, the lock screen's Canvas below iOS 26: MediaRemoteUI draws the lock screen's player
// and, when its cover is tapped, the large cover over the lock screen, in a window of its own
// (MediaRemoteUI.SecureWindow, full screen) holding MediaRemoteUI.CoverSheetBackgroundView: an MTKView for the coloured
// field and the large MRUArtworkView, 352pt on a 414pt phone. The player's own small
// cover is in its other window, and the system takes it away as the large one opens.
//
// While the large cover is open, Spotify's switch is on (kSGRelayLockArtOn) and SpringBoard has shared the song's clip
// (kSGRelayLockClipShared, SGLockSharedClipPath), the large cover is hidden and the clip shown full screen in its place,
// over the field (LockClipView.h), and SpringBoard is told (kSGRelayLockShowing) to hide the widgets under the clock.
// A clip that comes later takes the cover's place as it comes; with none the system's cover stays as it is, and closed,
// everything of the system's comes back. The clip holds still while the song is paused.
//
// MediaRemoteUI gives the large cover its alpha back as it animates (the cover would stay over the clip
// until the screen had gone off and on a few times), so a hidden cover keeps alpha 0 whatever it is set to, and gets the
// last alpha MediaRemoteUI asked for back. A tap that closes the large cover (the field's own, heard alongside it) gives
// the cover back at once, for MediaRemoteUI to shrink it into the player as it does with no clip, and fades the clip out
// over it: hidden, the cover had nothing to shrink and the clip went at once.
//
// A song with no clip gets its still cover the same way, the screen's width across on the bands of its edges' colours,
// while Spotify is what plays: the cover from MediaRemote's now playing info, as the lock screen's own player has it.
// While the screen is dark the clip is not read or decoded (com.apple.springboard.hasBlankedScreen), and lit it starts
// over on a new display layer.
//
// A new song changes what is drawn only once it has something to draw: until its cover is in (the now playing info
// comes first with none, or with Spotify's gray placeholder picture, looksLoaded) or its clip is shared, the last song's clip or cover stays,
// rather than the system's gray placeholder showing for a moment. If neither is in after kWait, whatever the song has
// is drawn, the placeholder too.
//
// Only the large cover's view and the cover itself are hooked, as they lay out, come and go and take an alpha.
//
// Threading: main thread.
#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import <objc/runtime.h>
#import <notify.h>
#import "LockClipView.h"
#import "../../tweak/Sources/Shared/Haptics/SGHapticRelay.h"

typedef void (*SGMRIsPlaying)(dispatch_queue_t queue, void (^handler)(Boolean playing));
typedef void (*SGMRRegister)(dispatch_queue_t queue);
typedef void (*SGMRGetInfo)(dispatch_queue_t queue, void (^handler)(CFDictionaryRef info));
typedef void (*SGMRGetApp)(dispatch_queue_t queue, void (^handler)(CFStringRef bundle));

static const NSTimeInterval kFade = 0.35;
// How long a new song's cover is waited for before its placeholder is drawn.
static const NSTimeInterval kWait = 2;

static SGMRIsPlaying sg_isPlaying;
static SGMRGetInfo sg_getInfo;
static SGMRGetApp sg_getApp;
static BOOL sg_on, sg_playing = YES, sg_showing, sg_blank;
static UIImage *sg_cover;   // Spotify's song's still cover, nil for none or for another app
static NSData *sg_coverData;
static BOOL sg_coverLoaded;   // sg_cover is the song's own, not a placeholder
static NSString *sg_track;   // the song the now playing info is for
static NSURL *sg_clip;   // this process's own copy of the shared clip, nil for none
// What is drawn: the clip, cover and song above as they were when last taken, held while a new song's are on their way.
static UIImage *sg_shownCover;
static NSData *sg_shownCoverData;
static NSString *sg_shownTrack;
static NSURL *sg_shownClip;
static BOOL sg_waiting;
static NSUInteger sg_wait;   // the wait's number, so a late timeout of one that ended does nothing
static __weak UIView *sg_field;   // the large cover's CoverSheetBackgroundView, while it is open
static char kClipKey, kTapKey, kHiddenKey, kWantedKey, kClosedKey;
static BOOL sg_settingAlpha;   // the alpha set here, not MediaRemoteUI's to remember

@interface SGVFieldTap : NSObject <UIGestureRecognizerDelegate>
@end

static void closing(UIView *field);

@implementation SGVFieldTap
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)recognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other {
    return YES;
}
- (void)tapped:(UITapGestureRecognizer *)tap {
    closing(tap.view);
}
@end

// The large cover hidden or given back: alpha 0 held while hidden, the alpha MediaRemoteUI last asked for after.
static void hideArtwork(UIView *artwork, BOOL hidden, BOOL animated) {
    if (!artwork || !!objc_getAssociatedObject(artwork, &kHiddenKey) == hidden) return;
    NSNumber *wanted = objc_getAssociatedObject(artwork, &kWantedKey);
    objc_setAssociatedObject(artwork, &kHiddenKey, hidden ? @YES : nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    CGFloat alpha = hidden ? 0 : (wanted ? wanted.doubleValue : 1);
    sg_settingAlpha = YES;
    [UIView animateWithDuration:animated ? kFade : 0 delay:0 options:UIViewAnimationOptionBeginFromCurrentState
                     animations:^{ artwork.alpha = alpha; } completion:nil];
    sg_settingAlpha = NO;
}

// The large cover in the field: the field's MRUArtworkView.
static UIView *artworkIn(UIView *field) {
    Class artwork = NSClassFromString(@"MRUArtworkView");
    for (UIView *sub in field.subviews) if (artwork && [sub isKindOfClass:artwork]) return sub;
    return nil;
}

static void tellShowing(BOOL showing) {
    if (sg_showing == showing) return;
    sg_showing = showing;
    notify_post(showing ? kSGRelayLockShowing : kSGRelayLockNotShowing);
}

static void apply(void) {
    UIView *field = sg_field;
    // Out of a window, or in a hidden one, nothing of the clip is read or decoded (the clip view rests itself out of one).
    if (!field.window || field.window.hidden) {
        tellShowing(NO);
        [(SGVLockClip *)objc_getAssociatedObject(field, &kClipKey) setSuspended:YES];
        return;
    }
    UIView *artwork = artworkIn(field);
    // Closed by a tap, the field stays the system's until it is shown again.
    BOOL on = sg_on && (sg_shownClip || sg_shownCover) && artwork && !objc_getAssociatedObject(field, &kClosedKey);
    SGVLockClip *clip = objc_getAssociatedObject(field, &kClipKey);
    if (!clip && on) {
        clip = [[SGVLockClip alloc] initWithFrame:field.bounds];
        clip.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        clip.alpha = 0;
        objc_setAssociatedObject(field, &kClipKey, clip, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (clip) {
        // Over the field and the large cover, so a cover MediaRemoteUI shows for a moment stays under it.
        if (clip.superview != field || field.subviews.lastObject != clip) [field addSubview:clip];
        if (!CGRectEqualToRect(clip.frame, field.bounds)) clip.frame = field.bounds;
    }
    if (on && !objc_getAssociatedObject(field, &kTapKey)) {
        SGVFieldTap *handler = [SGVFieldTap new];
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:handler action:@selector(tapped:)];
        tap.delegate = handler;
        tap.cancelsTouchesInView = NO;
        tap.delaysTouchesEnded = NO;
        [field addGestureRecognizer:tap];
        objc_setAssociatedObject(field, &kTapKey, handler, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    tellShowing(on);
    hideArtwork(artwork, on, YES);
    BOOL shown = clip.alpha > 0.99;
    [UIView animateWithDuration:shown == on ? 0 : kFade delay:0 options:UIViewAnimationOptionBeginFromCurrentState animations:^{
        clip.alpha = on ? 1 : 0;
    } completion:^(BOOL finished) {
        if (!(sg_on && sg_shownClip && artworkIn(field)) || objc_getAssociatedObject(field, &kClosedKey)) [clip playClip:nil];
    }];
    if (on) {
        [clip setSuspended:sg_blank];
        [clip showCover:sg_shownCover];
        [clip playClip:sg_shownClip];
        [clip setPlaying:sg_playing];
    }
}

// The large cover closing on a tap: the cover back at once, for MediaRemoteUI to shrink it, the clip fading over it.
static void closing(UIView *field) {
    SGVLockClip *clip = objc_getAssociatedObject(field, &kClipKey);
    if (!clip || clip.alpha < 0.01) return;
    objc_setAssociatedObject(field, &kClosedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    hideArtwork(artworkIn(field), NO, NO);
    tellShowing(NO);
    [UIView animateWithDuration:0.25 delay:0 options:UIViewAnimationOptionBeginFromCurrentState
                     animations:^{ clip.alpha = 0; } completion:nil];
}

// A copy of the shared clip taken off disk once it is neither the newest nor the one drawn.
static void forget(NSURL *clip) {
    if (clip && ![clip isEqual:sg_clip] && ![clip isEqual:sg_shownClip]) [NSFileManager.defaultManager removeItemAtURL:clip error:nil];
}

// What came in drawn. Falling back, at the end of a wait, the new song's placeholder is taken too; otherwise a
// placeholder never takes the place of a cover already drawn.
static void take(BOOL fallback) {
    NSURL *old = sg_shownClip;
    sg_waiting = NO;
    sg_shownClip = sg_clip;
    sg_shownTrack = sg_track;
    if (sg_coverLoaded || fallback || !sg_shownCover) {
        sg_shownCover = sg_cover;
        sg_shownCoverData = sg_coverData;
    }
    forget(old);
    apply();
}

// Something of a new song's in: drawn at once outside a wait, and in one once it is the new song's clip or its own cover.
static void changed(void) {
    if (!sg_waiting) {
        take(NO);
        return;
    }
    BOOL newClip = sg_clip && ![sg_clip isEqual:sg_shownClip];
    BOOL newCover = sg_coverLoaded && ![sg_track isEqualToString:sg_shownTrack] && ![sg_coverData isEqualToData:sg_shownCoverData];
    if (newClip || newCover) take(NO);
}

// The wait's end, kWait from now. With the cover not read (the screen dark, readCover), the cover in hand is the last
// song's, so the wait goes on, and starts over as the screen lights and the cover is read.
static BOOL sg_coverStale;
static void armWait(void) {
    NSUInteger run = ++sg_wait;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kWait * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (sg_waiting && sg_wait == run && !sg_coverStale) take(YES);
    });
}

// A new song on its way: what is drawn stays until changed() finds its clip or cover, or kWait has gone.
static void hold(void) {
    if (!sg_waiting && (sg_shownClip || sg_shownCover)) {
        sg_waiting = YES;
        armWait();
    }
    changed();
}

// A clip shared while it could not be shown (the screen dark, no large cover, the Canvas off): read once it can be.
static BOOL sg_clipStale;
// Each read and each new song's none: a copy that ends after a newer one began is dropped.
static NSUInteger sg_clipRun;

// The shared clip copied into this process's own temporary folder under a new name, so the clip view takes a new file.
// Only while it can be shown, and off the main thread.
static void readShared(void) {
    NSURL *old = sg_clip;
    sg_clip = nil;
    forget(old);
    NSUInteger run = ++sg_clipRun;
    sg_clipStale = sg_blank || !sg_field || !sg_on;
    if (sg_clipStale) {
        changed();
        return;
    }
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ queue = dispatch_queue_create("com.vitrine.addon.clipcopy", DISPATCH_QUEUE_SERIAL); });
    NSURL *shared = [NSURL fileURLWithPath:SGLockSharedClipPath()];
    NSURL *copy = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"vitrine-lockclip-%u.mp4", arc4random()]]];
    dispatch_async(queue, ^{
        NSError *error = nil;
        BOOL copied = [NSFileManager.defaultManager copyItemAtURL:shared toURL:copy error:&error];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (run != sg_clipRun) {
                if (copied) [NSFileManager.defaultManager removeItemAtURL:copy error:nil];
                return;
            }
            if (copied) sg_clip = copy;
            else NSLog(@"[vitrine-addon] MediaRemoteUI cannot read the shared clip: %@", error.localizedDescription);
            changed();
        });
    });
}

// Whether `cover` is a song's own rather than a placeholder. Spotify's placeholder is a gray field with a gray picture
// glyph on it: gray all over, two or three flat shades, and an edge of the field's shade alone. A song's cover, in color
// or not, has many shades and an edge that varies. The flat gray of a placeholder with no glyph reads the same way.
// Read off a 32 pt copy, in sixteen shades of gray.
static BOOL looksLoaded(UIImage *cover) {
    CGImageRef image = cover.CGImage;
    if (!image) return NO;
    enum { side = 32, levels = 16 };
    uint8_t pixels[side * side * 4] = {0};
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(pixels, side, side, 8, side * 4, space, (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(space);
    if (!context) return YES;
    CGContextSetInterpolationQuality(context, kCGInterpolationLow);
    CGContextDrawImage(context, CGRectMake(0, 0, side, side), image);
    CGContextRelease(context);
    NSUInteger counts[levels] = {0}, edges = 0;
    double chroma = 0, edgeSum = 0, edgeSquares = 0;
    for (int y = 0; y < side; y++) {
        for (int x = 0; x < side; x++) {
            const uint8_t *p = pixels + (y * side + x) * 4;
            double luma = (0.299 * p[0] + 0.587 * p[1] + 0.114 * p[2]) / 255;
            chroma = MAX(chroma, (MAX(p[0], MAX(p[1], p[2])) - MIN(p[0], MIN(p[1], p[2]))) / 255.0);
            counts[MIN(levels - 1, (int)(luma * levels))]++;
            if (x == 0 || y == 0 || x == side - 1 || y == side - 1) {
                edgeSum += luma;
                edgeSquares += luma * luma;
                edges++;
            }
        }
    }
    double edgeMean = edgeSum / edges, edgeSpread = sqrt(MAX(0, edgeSquares / edges - edgeMean * edgeMean));
    NSUInteger shades = 0;
    for (int i = 0; i < levels; i++) if (counts[i] > side * side / 50) shades++;
    return !(chroma < 0.08 && shades <= 3 && edgeSpread < 0.03);
}

// The song, by its title and album: not its artist, which Vitrine's lock screen lyrics write each line into.
static NSString *trackOf(NSDictionary *info) {
    return [NSString stringWithFormat:@"%@\n%@", info[@"kMRMediaRemoteNowPlayingInfoTitle"] ?: @"", info[@"kMRMediaRemoteNowPlayingInfoAlbum"] ?: @""];
}

// Spotify's still cover from the now playing info, read again as the info changes; another app's is not taken. Two XPC
// calls and the artwork's bytes, and Vitrine's lock screen lyrics change the info with every line: none of it while the
// switch is off or the screen is dark, only a note to read it once either comes back.
static void readCover(void) {
    if (!sg_getInfo || !sg_getApp) return;
    if (!sg_on || sg_blank) {
        sg_coverStale = YES;
        return;
    }
    sg_coverStale = NO;
    sg_getApp(dispatch_get_main_queue(), ^(CFStringRef bundle) {
        if (![(__bridge NSString *)bundle isEqualToString:@"com.spotify.client"]) {
            BOOL had = sg_cover != nil || sg_shownCover != nil;
            sg_cover = nil;
            sg_coverData = nil;
            sg_coverLoaded = NO;
            sg_track = nil;
            if (had) take(YES);
            return;
        }
        sg_getInfo(dispatch_get_main_queue(), ^(CFDictionaryRef info) {
            NSDictionary *now = (__bridge NSDictionary *)info;
            NSString *track = trackOf(now);
            NSData *data = now[@"kMRMediaRemoteNowPlayingInfoArtworkData"];
            BOOL sameCover = data == sg_coverData || [data isEqualToData:sg_coverData];
            if (sameCover && [track isEqualToString:sg_track]) return;
            BOOL newTrack = sg_track && ![track isEqualToString:sg_track];
            sg_track = track;
            if (!sameCover) {
                sg_coverData = data;
                sg_cover = data ? [UIImage imageWithData:data] : nil;
                sg_coverLoaded = looksLoaded(sg_cover);
            }
            if (newTrack) hold();
            else changed();
        });
    });
}

static void readPlaying(void) {
    if (!sg_isPlaying) return;
    sg_isPlaying(dispatch_get_main_queue(), ^(Boolean playing) {
        sg_playing = playing;
        SGVLockClip *clip = sg_field ? objc_getAssociatedObject(sg_field, &kClipKey) : nil;
        [clip setPlaying:playing];
    });
}

%hook _TtC13MediaRemoteUI24CoverSheetBackgroundView
- (void)didMoveToWindow {
    %orig;
    UIView *field = (UIView *)self;
    if (field.window) {
        sg_field = field;
        objc_setAssociatedObject(field, &kClosedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (sg_clipStale) readShared();
    }
    apply();
}

- (void)layoutSubviews {
    %orig;
    UIView *field = (UIView *)self;
    sg_field = field;
    // A field closed by a tap and kept, hidden, for the next time: it is the clip's again as it is shown.
    UIWindow *window = field.window;
    if (field.hidden || field.alpha < 0.01 || !window || window.hidden || window.alpha < 0.01)
        objc_setAssociatedObject(field, &kClosedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (sg_on || sg_showing) apply();
}
%end

%group SGVArtwork
%hook MRUArtworkView
- (void)setAlpha:(CGFloat)alpha {
    if (!sg_settingAlpha) objc_setAssociatedObject(self, &kWantedKey, @(alpha), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    %orig(objc_getAssociatedObject(self, &kHiddenKey) ? 0 : alpha);
}
%end
%end

static void listen(const char *name, void (^handler)(void)) {
    int token;
    notify_register_dispatch(name, &token, dispatch_get_main_queue(), ^(int t) { handler(); });
}

%ctor {
    if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.MediaRemoteUI"]) return;
    if (@available(iOS 26.0, *)) return;
    if (!objc_getClass("_TtC13MediaRemoteUI24CoverSheetBackgroundView")) {
        NSLog(@"[vitrine-addon] MediaRemoteUI has no CoverSheetBackgroundView, the lock screen's Canvas is off");
        return;
    }
    void *remote = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW);
    sg_isPlaying = remote ? (SGMRIsPlaying)dlsym(remote, "MRMediaRemoteGetNowPlayingApplicationIsPlaying") : NULL;
    SGMRRegister registerFor = remote ? (SGMRRegister)dlsym(remote, "MRMediaRemoteRegisterForNowPlayingNotifications") : NULL;
    sg_getInfo = remote ? (SGMRGetInfo)dlsym(remote, "MRMediaRemoteGetNowPlayingInfo") : NULL;
    sg_getApp = remote ? (SGMRGetApp)dlsym(remote, "MRMediaRemoteGetNowPlayingApplicationDisplayID") : NULL;
    %init;
    if (objc_getClass("MRUArtworkView")) %init(SGVArtwork);
    if (registerFor) registerFor(dispatch_get_main_queue());
    [NSNotificationCenter.defaultCenter addObserverForName:@"kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification" object:nil queue:nil
                                                usingBlock:^(NSNotification *note) {
        dispatch_async(dispatch_get_main_queue(), ^{ readPlaying(); });
    }];
    for (NSString *name in @[@"kMRMediaRemoteNowPlayingInfoDidChangeNotification", @"kMRMediaRemoteNowPlayingApplicationDidChangeNotification"]) {
        [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:nil usingBlock:^(NSNotification *note) {
            dispatch_async(dispatch_get_main_queue(), ^{ readCover(); });
        }];
    }
    readPlaying();
    readCover();
    static int blankToken;
    notify_register_dispatch("com.apple.springboard.hasBlankedScreen", &blankToken, dispatch_get_main_queue(), ^(int t) {
        uint64_t state = 0;
        notify_get_state(t, &state);
        sg_blank = state != 0;
        SGVLockClip *clip = sg_field ? objc_getAssociatedObject(sg_field, &kClipKey) : nil;
        [clip setSuspended:sg_blank];
        if (!sg_blank && sg_coverStale) {
            readCover();
            if (sg_waiting) armWait();
        }
        if (!sg_blank && sg_clipStale) readShared();
    });
    // As it is now: nothing is posted until it changes.
    uint64_t blankState = 0;
    if (notify_get_state(blankToken, &blankState) == NOTIFY_STATUS_OK) sg_blank = blankState != 0;
    listen(kSGRelayLockArtOn, ^{
        sg_on = YES;
        if (sg_coverStale) readCover();
        if (sg_clipStale) readShared();
        apply();
    });
    listen(kSGRelayLockArtOff, ^{ sg_on = NO; apply(); });
    listen(kSGRelayLockClipShared, ^{ readShared(); });
    // Spotify says so as each song begins, before its clip is looked up, so what is drawn waits for the song's cover.
    listen(kSGRelayLockClipNone, ^{
        sg_clipRun++;
        sg_clipStale = NO;
        NSURL *old = sg_clip;
        sg_clip = nil;
        forget(old);
        hold();
    });
    // The switch and the clip as they are now: Spotify answers SpringBoard's pong to this ping with the switch, and a
    // clip already shared is in the shared caches.
    notify_post(kSGRelayPing);
    // A MediaRemoteUI that went away while showing the clip left SpringBoard's widgets hidden: it says it shows nothing.
    notify_post(kSGRelayLockNotShowing);
    if ([NSFileManager.defaultManager fileExistsAtPath:SGLockSharedClipPath()]) readShared();
    NSLog(@"[vitrine-addon] MediaRemoteUI ready for the lock screen's Canvas");
}
