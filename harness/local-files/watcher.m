// The native cover consumer (Native/LocalFiles/LocalCover.x, through Logos) over the production resolver
// (Shared/LocalFiles/LocalCover.m): two local tracks share a title and artist, the second shows the first's
// system artwork as its provisional cover, and its own artwork reaches the now playing info only after the
// watcher's last retry. With no layout and no playback change the displayed cover must still become it.
// Spotify's classes are doubles under the same runtime names; the player, the now playing center and the
// window are doubles too.
#import <UIKit/UIKit.h>
#import <MediaPlayer/MediaPlayer.h>
#import <objc/runtime.h>
#import "Headers/SPTPlayer.h"
#import "Shared/LocalFiles/LocalFiles.h"
#import "Shared/Player/NowPlayingExtras.h"
#import "Shared/Player/PlayerState.h"
#import "../harness-fail.h"
#import "../dispatch-clock.h"

NSNotificationName const SGNowPlayingInfoDidChangeNotification = @"spotifyglass.nowPlayingInfoDidChange";

__attribute__((objc_runtime_name("_TtC35NowPlaying_ContentLayerPlatformImpl24AccessibleCollectionView")))
@interface HarnessCoverList : UIScrollView
@end
// A window needs the app's scene, which a command-line check does not have. The watcher only asks whether the list
// is in one, and UIKit must not be told so, so the list says yes while the run loop is pumped and no otherwise.
static BOOL sg_listInWindow;
@implementation HarnessCoverList
- (UIWindow *)window { return sg_listInWindow ? (UIWindow *)(id)self : nil; }
@end

__attribute__((objc_runtime_name("_TtC28NowPlaying_ContentLayersImpl16CoverArtCellImpl")))
@interface HarnessCoverCell : UIView
@end
@implementation HarnessCoverCell
@end

__attribute__((objc_runtime_name("_TtC35CreativeWorkCommons_CoverArtTiltKit16CoverArtTiltView")))
@interface HarnessTiltView : UIView
@end
@implementation HarnessTiltView
@end

@interface HarnessTrack : NSObject
@property(nonatomic, strong) NSURL *URI;
@property(nonatomic, copy) NSDictionary *metadata;
@property(nonatomic, copy) NSString *trackTitle, *artistName;
@end
@implementation HarnessTrack @end
@interface HarnessState : NSObject
@property(nonatomic, strong) HarnessTrack *track;
@end
@implementation HarnessState @end
@interface HarnessCenter : NSObject
@property(nonatomic, copy) NSDictionary *nowPlayingInfo;
@end
@implementation HarnessCenter @end

static HarnessState *state;
static NSMutableArray<id<SGPlayerStateObserver>> *observers;
SPTPlayerState *SGPlayerState(void) { return (SPTPlayerState *)state; }
void SGAddPlayerStateObserver(id<SGPlayerStateObserver> value) { [observers addObject:value]; }
NSString *SGURIString(id uri) { return [uri isKindOfClass:NSURL.class] ? [uri absoluteString] : uri; }
BOOL SGNativeUI(void) { return YES; }
void SGRequireClasses(NSArray<NSString *> *names) { for (NSString *name in names) HARNESS_CHECK(NSClassFromString(name)); }
BOOL SGClassNamed(Class cls, NSString *marker) { return [NSStringFromClass(cls) containsString:marker]; }
void SGForEachView(UIView *view, void (^fn)(UIView *)) {
    fn(view);
    for (UIView *child in view.subviews) SGForEachView(child, fn);
}

static void play(HarnessTrack *track) {
    state = [HarnessState new];
    state.track = track;
    for (id<SGPlayerStateObserver> observer in [observers copy]) [observer playerStateDidChange:SGPlayerState()];
}
// Drive the watcher's two scheduled retries before announcing the real artwork.
#define dispatch_after HarnessAfter
#define dispatch_time HarnessTime
#import "LocalCover.m"
#undef dispatch_time
#undef dispatch_after
#import "../harness-wait.h"
static UIImage *solid(UIColor *color) {
    return [[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(4, 4)] imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [color setFill]; UIRectFill(CGRectMake(0, 0, 4, 4));
    }];
}
static MPMediaItemArtwork *artwork(UIImage *image) {
    return [[MPMediaItemArtwork alloc] initWithBoundsSize:image.size requestHandler:^UIImage *(CGSize size) { return image; }];
}
static HarnessTrack *track(NSUInteger number) {
    HarnessTrack *track = [HarnessTrack new];
    track.URI = [NSURL URLWithString:[NSString stringWithFormat:@"spotify:local:Fixture:Album:Track%lu:60", (unsigned long)number]];
    track.metadata = @{};
    track.trackTitle = @"Shared title";
    track.artistName = @"Shared artist";
    return track;
}

int main(void) { @autoreleasepool {
    observers = [NSMutableArray array];
    HarnessCenter *center = [HarnessCenter new];
    Method getter = class_getClassMethod(MPNowPlayingInfoCenter.class, @selector(defaultCenter));
    IMP replacement = imp_implementationWithBlock(^id(id self) { return center; });
    IMP original = method_setImplementation(getter, replacement);

    UIImage *first = solid(UIColor.redColor), *second = solid(UIColor.blueColor);
    HarnessTrack *one = track(1), *two = track(2);
    center.nowPlayingInfo = @{MPMediaItemPropertyTitle: one.trackTitle, MPMediaItemPropertyArtist: one.artistName,
                              MPMediaItemPropertyArtwork: artwork(first)};

    HarnessCoverList *list = [[HarnessCoverList alloc] initWithFrame:CGRectMake(0, 0, 390, 390)];
    HarnessCoverCell *cell = [[HarnessCoverCell alloc] initWithFrame:CGRectMake(0, 0, 390, 390)];
    UIImageView *cover = [[UIImageView alloc] initWithFrame:CGRectMake(18, 18, 354, 354)];
    [cell addSubview:cover];
    [list addSubview:cell];

    HarnessStartClock();
    play(one);
    [list layoutSubviews];   // the hooked layout the player does on its own
    HARNESS_CHECK(cover.image == first);

    // The second track agrees by title and artist, so it shows the first's artwork until its own arrives.
    play(two);
    sg_listInWindow = YES;
    HarnessAdvanceClock(1700 * NSEC_PER_MSEC);
    HarnessStopClock();
    HARNESS_CHECK(cover.image == first);

    // Its own artwork reaches the now playing info afterwards, as the system's post (NowPlayingExtras.x) says.
    center.nowPlayingInfo = @{MPMediaItemPropertyTitle: two.trackTitle, MPMediaItemPropertyArtist: two.artistName,
                              MPMediaItemPropertyArtwork: artwork(second)};
    dispatch_async(dispatch_get_main_queue(), ^{
        [NSNotificationCenter.defaultCenter postNotificationName:SGNowPlayingInfoDidChangeNotification object:nil];
    });
    HARNESS_AWAIT(cover.image == second);
    sg_listInWindow = NO;

    method_setImplementation(getter, original);
    imp_removeBlock(replacement);
    puts("PASS: the native cover updates to a second local track's own system artwork that arrives after the watcher's retries, with no layout or playback change");
    return 0;
} }
