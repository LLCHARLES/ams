// Vitrine Addon in SpringBoard, the lock screen's Canvas below iOS 26: SpringBoard's share of it. The lock screen's
// player and its large cover are drawn by MediaRemoteUI, which only shows in SpringBoard's lock screen as a scene of its
// own (the cover sheet has neither, MediaRemoteUI has both), so the clip is put in the
// large cover's place there (MediaRemoteUICanvas.x). Here:
//
//   the clip    Spotify's for the song (kSGRelayLockClip), read through the data container of the now playing app and
//               copied to the jailbreak's shared caches (SGLockSharedClipPath), where MediaRemoteUI, sandboxed, can read
//               it; MediaRemoteUI is told by kSGRelayLockClipShared. kSGRelayLockClipNone comes from Spotify to both.
//   the widgets the row under the clock (CSProminentEmptyElementView) hidden while
//               MediaRemoteUI shows the clip (kSGRelayLockShowing), and given back as it stops.
//
// Nothing is walked or hooked on the lock screen's layout: the widgets' row is looked for only as it is to be hidden.
//
// Threading: the notifications and MediaRemote's answers come on the main queue.
#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import <stdatomic.h>
#import <sys/stat.h>
#import <fcntl.h>
#import <unistd.h>
#import <notify.h>
#import "../../tweak/Sources/Shared/Haptics/SGHapticRelay.h"

@interface CSCoverSheetViewController : UIViewController
@end

@interface LSApplicationProxy : NSObject
+ (instancetype)applicationProxyForIdentifier:(NSString *)identifier;
@property (nonatomic, readonly) NSURL *dataContainerURL;
@end

typedef void (*SGMRGetApp)(dispatch_queue_t queue, void (^handler)(CFStringRef bundle));

static const NSTimeInterval kFade = 0.35;

static SGMRGetApp sg_getApp;
static __weak UIView *sg_sheet;   // the cover sheet's view
static NSHashTable<UIView *> *sg_hidden;

// The widgets' row under the clock, wherever the cover sheet keeps it.
static void collectRows(UIView *root, NSMutableArray<UIView *> *rows, int depth) {
    if (depth > 30) return;
    for (UIView *sub in root.subviews) {
        if ([NSStringFromClass(sub.class) isEqualToString:@"CSProminentEmptyElementView"]) {
            [rows addObject:sub];
            continue;
        }
        collectRows(sub, rows, depth + 1);
    }
}

static void hideWidgets(BOOL away) {
    if (!sg_hidden) sg_hidden = [NSHashTable weakObjectsHashTable];
    NSArray<UIView *> *views = sg_hidden.allObjects;
    if (away) {
        NSMutableArray<UIView *> *rows = [NSMutableArray array];
        if (sg_sheet) collectRows(sg_sheet, rows, 0);
        for (UIView *row in rows) [sg_hidden addObject:row];
        views = rows;
    } else {
        [sg_hidden removeAllObjects];
    }
    for (UIView *view in views) {
        [UIView animateWithDuration:kFade delay:0 options:UIViewAnimationOptionBeginFromCurrentState
                         animations:^{ view.alpha = away ? 0 : 1; } completion:nil];
    }
}

// The largest file taken from Spotify: a Canvas is a few MB, an animated cover a little more.
static const off_t kMostBytes = 50 * 1024 * 1024;

// Copies the regular file at `source` to `target`, opened once without following a link (O_NOFOLLOW) and checked on that
// descriptor (fstat), so what is checked is what is copied, and never more than kMostBytes of it. NO for a link, a
// directory, an empty or a larger file, or a failed write.
static BOOL copyRegularFile(NSURL *source, NSURL *target) {
    int in = open(source.fileSystemRepresentation, O_RDONLY | O_NOFOLLOW | O_CLOEXEC);
    if (in < 0) return NO;
    struct stat info;
    if (fstat(in, &info) != 0 || !S_ISREG(info.st_mode) || info.st_size <= 0 || info.st_size > kMostBytes) {
        close(in);
        return NO;
    }
    int out = open(target.fileSystemRepresentation, O_WRONLY | O_CREAT | O_TRUNC | O_NOFOLLOW | O_CLOEXEC, 0644);
    if (out < 0) {
        close(in);
        return NO;
    }
    static char buffer[256 * 1024];
    off_t copied = 0;
    BOOL done = YES;
    for (;;) {
        ssize_t got = read(in, buffer, sizeof buffer);
        if (got == 0) break;
        if (got < 0 || copied + got > kMostBytes) {
            done = NO;
            break;
        }
        for (ssize_t written = 0; written < got;) {
            ssize_t wrote = write(out, buffer + written, (size_t)(got - written));
            if (wrote <= 0) {
                done = NO;
                break;
            }
            written += wrote;
        }
        if (!done) break;
        copied += got;
    }
    close(in);
    if (close(out) != 0) done = NO;
    return done && copied > 0;
}

// Spotify's clip for the song into the shared caches, for MediaRemoteUI: copied beside it and moved over the last one,
// so a reader of the last one keeps its own file. Any process can post the notification that starts it, so it is taken
// from Spotify alone (MediaRemoteUI's still cover is Spotify's alone too), off SpringBoard's main thread, as the copy
// crosses volumes, and only a regular file of a sane size.
// Each new song's none: a copy that ends after it was posted is dropped, so a fast skip never shows the last song's
// clip on the new one.
static atomic_uint sg_shareRun;

static void shareClip(void) {
    if (!sg_getApp) return;
    unsigned run = atomic_load(&sg_shareRun);
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ queue = dispatch_queue_create("com.vitrine.addon.share", DISPATCH_QUEUE_SERIAL); });
    sg_getApp(queue, ^(CFStringRef bundle) {
        NSString *identifier = (__bridge NSString *)bundle;
        if (![identifier isEqualToString:@"com.spotify.client"]) return;
        NSURL *container = [[NSClassFromString(@"LSApplicationProxy") applicationProxyForIdentifier:identifier] dataContainerURL];
        NSURL *clip = [container URLByAppendingPathComponent:@"Library/Caches/" kSGLockClipName];
        if (!clip) return;
        NSFileManager *files = NSFileManager.defaultManager;
        NSURL *shared = [NSURL fileURLWithPath:SGLockSharedClipPath()];
        [files createDirectoryAtURL:shared.URLByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
        NSURL *staging = [shared URLByAppendingPathExtension:@"part"];
        [files removeItemAtURL:staging error:nil];
        if (!copyRegularFile(clip, staging)) {
            [files removeItemAtURL:staging error:nil];
            NSLog(@"[vitrine-addon] no clip to take from Spotify");
            return;
        }
        if (atomic_load(&sg_shareRun) != run) {
            [files removeItemAtURL:staging error:nil];
            return;
        }
        NSError *error = nil;
        [files removeItemAtURL:shared error:nil];
        if (![files moveItemAtURL:staging toURL:shared error:&error]) {
            NSLog(@"[vitrine-addon] the clip not shared: %@", error.localizedDescription);
            return;
        }
        if (atomic_load(&sg_shareRun) == run) notify_post(kSGRelayLockClipShared);
    });
}

%hook CSCoverSheetViewController
- (void)viewDidLoad {
    %orig;
    sg_sheet = ((UIViewController *)self).view;
}
%end

%ctor {
    if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"]) return;
    if (@available(iOS 26.0, *)) return;
    void *remote = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW);
    sg_getApp = remote ? (SGMRGetApp)dlsym(remote, "MRMediaRemoteGetNowPlayingApplicationDisplayID") : NULL;
    %init;
    int clipToken, noneToken, showingToken, hiddenToken;
    notify_register_dispatch(kSGRelayLockClip, &clipToken, dispatch_get_main_queue(), ^(int t) { shareClip(); });
    notify_register_dispatch(kSGRelayLockClipNone, &noneToken, dispatch_get_main_queue(), ^(int t) {
        atomic_fetch_add(&sg_shareRun, 1);
        [NSFileManager.defaultManager removeItemAtPath:SGLockSharedClipPath() error:nil];
    });
    notify_register_dispatch(kSGRelayLockShowing, &showingToken, dispatch_get_main_queue(), ^(int t) { hideWidgets(YES); });
    notify_register_dispatch(kSGRelayLockNotShowing, &hiddenToken, dispatch_get_main_queue(), ^(int t) { hideWidgets(NO); });
}
