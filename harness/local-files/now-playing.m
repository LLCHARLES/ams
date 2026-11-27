// Real LocalFileInfo observer: worker-only decoding, stale-track rejection, retained system artwork.
#import <UIKit/UIKit.h>
#import <MediaPlayer/MediaPlayer.h>
#import <ImageIO/ImageIO.h>
#import "Shared/Player/PlayerState.h"
#import "Shared/Player/NowPlayingExtras.h"
#import "Headers/SPTLocalAVAssetImageLoaderRequest.h"
#import "load.h"
#include <dlfcn.h>
#include <stdatomic.h>

#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAILED now-playing line %d: %s\n", __LINE__, #c); exit(1); } } while (0)
static id<SGPlayerStateObserver> observer;
static SPTPlayerState *current;
static NSMutableDictionary *extras;
static atomic_bool stallNextRead;
static dispatch_semaphore_t readEntered, releaseRead;
CGImageSourceRef CGImageSourceCreateWithURL(CFURLRef url, CFDictionaryRef options) {
    CHECK(!NSThread.isMainThread);
    static CGImageSourceRef (*readSource)(CFURLRef, CFDictionaryRef);
    static dispatch_once_t once;
    dispatch_once(&once, ^{ readSource = dlsym(RTLD_NEXT, "CGImageSourceCreateWithURL"); CHECK(readSource); });
    if (atomic_exchange(&stallNextRead, false)) {
        dispatch_semaphore_signal(readEntered);
        CHECK(!dispatch_semaphore_wait(releaseRead, dispatch_time(DISPATCH_TIME_NOW, 120 * NSEC_PER_SEC)));
    }
    return readSource(url, options);
}
void SGAddPlayerStateObserver(id<SGPlayerStateObserver> value) { observer = value; }
SPTPlayerState *SGPlayerState(void) { return current; }
NSString *SGURIString(id uri) { return [uri isKindOfClass:NSString.class] ? uri : [uri absoluteString]; }
void SGRequireClasses(NSArray<NSString *> *names) { for (NSString *name in names) CHECK(NSClassFromString(name)); }
void SGNowPlayingSetExtras(NSString *owner, NSDictionary *value, NSString *title) {
    CHECK(NSThread.isMainThread);
    if (value.count) extras[owner] = @{@"value": value, @"title": title ?: @""};
    else [extras removeObjectForKey:owner];
}
@implementation SPTPlayerTrack @end
@implementation SPTLocalAVAssetImageLoaderRequest
- (void)loadLocalFileImage {}
- (void)dispatchSuccess:(NSData *)data {}
@end
@interface CoverTrack : NSObject
@property(nonatomic, copy) NSString *URI;
@end
@implementation CoverTrack @end
@interface CoverState : NSObject
@property(nonatomic, strong) CoverTrack *track;
@end
@implementation CoverState @end
static void report(NSString *uri) {
    CoverState *state = [CoverState new];
    state.track = [CoverTrack new]; state.track.URI = uri;
    current = (SPTPlayerState *)state;
    [observer playerStateDidChange:current];
}
int main(void) { @autoreleasepool {
    extras = [NSMutableDictionary dictionary];
    NSString *uri = @"spotify:local:Artist:Album:Original:60";
    NSString *barrier = @"spotify:local:Fixture:Album:Barrier:60";
    UIImage *image = [[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(8, 8)]
        imageWithActions:^(UIGraphicsImageRendererContext *context) {
            [UIColor.redColor setFill]; UIRectFill(CGRectMake(0, 0, 8, 8));
        }];
    SGLocalFileSaveEdit(uri, @{@"title": @"Edited"}, image, YES);
    readEntered = dispatch_semaphore_create(0);
    releaseRead = dispatch_semaphore_create(0);
    atomic_store(&stallNextRead, true);
    report(uri);
    CHECK(!dispatch_semaphore_wait(readEntered, dispatch_time(DISPATCH_TIME_NOW, 60 * NSEC_PER_SEC)));
    report(@"spotify:track:next");
    dispatch_semaphore_signal(releaseRead);
    // A later read's completion follows every previously submitted cover read.
    loadCoverAndWait(barrier);
    CHECK(extras.count == 0);
    report(uri);
    loadCoverAndWait(barrier);
    CHECK([extras[@"localFiles"][@"title"] isEqual:@"Edited"]);
    CHECK([extras[@"localFiles.tags"][@"title"] isEqual:@"Original"]);
    MPMediaItemArtwork *artwork = extras[@"localFiles"][@"value"][MPMediaItemPropertyArtwork];
    CHECK([artwork imageWithSize:CGSizeMake(8, 8)].CGImage != NULL);
    report(nil);
    CHECK(extras.count == 0);
    SGLocalFileSaveEdit(uri, @{}, nil, NO);
    puts("now-playing: off-main cover loading, stale-track rejection, and synchronous retained artwork passed");
    return 0;
} }
