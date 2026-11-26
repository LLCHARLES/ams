// A mock of Spotify's full screen player under its own class names and accessibility identifiers, built
// from trees/clean/player/01.txt, so Redesigned/Player's lyrics state can be laid out, animated and
// looked at on the Mac. Tapping the lyrics glyph in the footer works exactly as it does on the phone;
// the harness also toggles it once by itself so a screenshot catches each state.
//
// HARNESS_SCENARIO (simctl launch passes it as SIMCTL_CHILD_HARNESS_SCENARIO) picks what it does:
//     lyrics   (default) the lyrics opened at 2 s, closed at 6, opened again at 10
//     look     one track playing, a second one from another album at 8 s, nothing opened
//     scroll   the list moved up and down in code; the log says whether it stayed at its top, then a scrub of
//              the progress bar begun and ended in code; the log says whether it held the list's pan
//     cover    the lyric preview given room under a smaller cover, as Spotify lays a track with lyrics out;
//              the log says whether the cover took that room back, PASS or FAIL
//     immersive the lyrics left alone: what fades, where the lines go, the tap that brings the controls
//              back, a scroll and the thumbnail; the log says PASS or FAIL
//     artwork  issue #58: tracks change while the covers on screen and the picture server lag behind,
//              checked by color at the end of each step; the log says PASS or FAIL
//     landscape the landscape lyrics at 3 s, a line's meanings over them, a pause and a resume; each
//              step logs whether the controls are up and what a touch on the lines lands on
//     motion   Animated artwork: a clip (HARNESS_CANVAS_FILE, an mp4) that comes in before the player has
//              laid out, then the field, the lyrics, a field built again, the menu's switch and the player
//              closed, each step checked; the log ends with motion checks n of m right -- PASS or FAIL
//     still    Animated's full-screen cover for a track with no clip: off first, then on, the 300 px rule, a late
//              cover, two quick skips, a late clip, black, the photo, the Visualizer and Low Power Mode; the log ends
//              with still checks n of m right -- PASS or FAIL
//     catalog  Apple Music's catalog behind a stub: the search term without the edition, the album of the same
//              name first, and the pause after a 429; the log says PASS or FAIL
//     settings the redesign's Player page (PlayerSettings.m) over the player with the clip of `motion`: Song
//              without a clip read from its two switches and each choice leaving the other off, the card pinned
//              and shrinking as the rows scroll, its demo, the card refreshed for another track with late clips
//              dropped, paused while covered and stopped once closed, the Buttons chips, the card and the chips
//              whole at narrow widths and the largest text, and no command sent to the player; the log ends
//              with settings checks n of m right -- PASS or FAIL, and the app exits with it
//     preview  the Player page's card picking Animated while the player has no clip (the background Still at
//              launch): the card looks the track's clip up itself, shows Fluid until it comes in 2 s late, then
//              the clip; the clip is in the store for the player, and asked for only while the page shows;
//              the log ends with preview checks n of m right -- PASS or FAIL
//     visualiser the Visualizer background (PlayerVisualiser.m) fed a song of the harness's own (stubs.m):
//              the hills moving, blurred behind the lyrics, settling and stopping on a pause, back on play,
//              and the ⋯ menu's switch to Fluid and back; the log ends with visualizer checks n of m right
//              -- PASS or FAIL
//     autoviz  Animated with "Visualizer when there's no clip": nothing while a lookup is out, the Visualizer
//              once it found no clip, down for a track change, a late clip, Low Power Mode, the full-screen cover
//              switch (each switches the other off), Fluid and black, and off again; needs HARNESS_CANVAS_FILE (an
//              mp4 taller than wide) for the late clip; the log ends with autoviz checks n of m right -- PASS or FAIL
//     shuffle  Shuffle styles: one pick per new track while the Visualizer is on screen (as the background, then as
//              the stand-in for a missing clip), none while hidden or for the same track, the user's own style back
//              when it is switched off; the log ends with shuffle checks n of m right -- PASS or FAIL
//     heat     Ignore heat warnings: the stand-down for each thermal state with and without it, the hills stopping and
//              moving on the switch, Low Power Mode still stopping them, and the stand-in for a missing clip; the log
//              ends with heat checks n of m right -- PASS or FAIL
//     options  the Player page's Header glass and Music app icons switched off and on with the player open, in it and
//              the AI DJ's, then Fluid's Grain at 0, 100 and 200% on Smooth and on Light; the log ends with options
//              checks n of m right -- PASS or FAIL
//     renderer the switch from Smooth to Light, read 0.2 to 4 s after it, five times; renderer checks n of m right
//     automix  AutoMix's transitions in the progress bar, the queue and the cover, and the AutoMix page's preview
//              (automix-scenario.m); automix checks n of m right -- PASS or FAIL, and the app exits with it
// HARNESS_VOLUME=0 leaves out the volume row the phone has (trees/clean/player/01.txt has none).
#import <AVFoundation/AVFoundation.h>
#import <CoreImage/CoreImage.h>
#import <OSLog/OSLog.h>
#import <MediaPlayer/MediaPlayer.h>
#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import "Redesigned/Kit/SGRTokens.h"
#import "../harness-fail.h"
#import "recognizer-reuse-check.h"
#import "../sponsorblock/markers-check.h"
#import <objc/runtime.h>
#import <Metal/Metal.h>
#import "Redesigned/Kit/SGRFluidGPU.h"
#import <objc/message.h>
#import <stdlib.h>
#import "Shared/Lyrics/Lyrics.h"
#import "Shared/Sing/Sing.h"
#import "Redesigned/Player/Player.h"
#import "Redesigned/Player/PlayerLyricLine.h"
#import "Redesigned/Player/PlayerLyricFit.h"
#import "Redesigned/Player/PlayerConnectVolume.h"
#import "Redesigned/Kit/SGRGlyph.h"
#import "Shared/AnimatedArtwork/AnimatedArtwork.h"
#import "Redesigned/Kit/SGRBridges.h"
#import "Redesigned/Kit/SGRField.h"
#import "Redesigned/Kit/SGRPalette.h"
#import "Redesigned/Lyrics/MeaningSheet.h"
#import "Redesigned/Lyrics/SGRKaraokeView.h"
#import "Core/SGPrefs.h"
#import "Core/SGViewTree.h"
#import "Redesigned/Kit/SGRFluid.h"
#import "Settings/SGModPage.h"
#import "Redesigned/Lyrics/LyricsLook.h"
#import "Redesigned/Lyrics/LyricsText.h"
#import "Shared/Player/PlayerSettings.h"
#import "Shared/Player/PlayerState.h"
#import "Shared/Player/AudioQuality.h"
#import "Shared/Player/SGLastTrack.h"
#import "Redesigned/Kit/SGRRefinements.h"
#import "Redesigned/Kit/SGRRestyle.h"

@interface SGRPlayerMotionView : UIView
- (void)playFile:(NSURL *)file poster:(UIImage *)poster;
@end

// Spotify's report of the file it plays (SPTPlayerState's playbackQuality), as the timerow scenario gives it.
@interface SGRHarnessQuality : NSObject
@property (nonatomic) long long bitrateLevel, strategy;
@end
@implementation SGRHarnessQuality
@end

// Inspect the first display frame for which the real close animation has returned the covers.
@interface SGRHarnessFrameCheck : NSObject
@property(nonatomic, copy) BOOL (^check)(void);
@end
@implementation SGRHarnessFrameCheck
- (void)frame:(CADisplayLink *)link { if (self.check()) [link invalidate]; }
@end

void SGRHarnessPlayFrom(NSInteger ms);
void SGRHarnessSetTrack(NSString *uri, NSString *imageURI, BOOL paused);
// stubs.m: every clip lookup answers this many seconds late (0, the default, at once).
void SGRHarnessSetLookupDelay(NSTimeInterval seconds);
void SGRHarnessHoldLookups(NSString *uri);
BOOL SGRHarnessLookupReady(NSString *uri);
void SGRHarnessDeliverLookups(NSString *uri);
void SGRHarnessClearTrack(void);
// ../tabbar/touch.m: a finger's touches, through UIKit's own recognizers.
extern void SGHarnessHold(UIWindow *window, CGPoint point, NSTimeInterval seconds);
extern void SGHarnessTap(UIWindow *window, CGPoint point);
extern UICollectionViewCell *SGHarnessSelectableCover(UICollectionView *covers, Class cellClass);
extern void SGHarnessCheckPreviewTap(UIView *preview, UIViewController *player, dispatch_block_t givePreviewBack);
#import "Redesigned/Player/PlayerQueue.h"
extern void SGHarnessDrag(UIWindow *window, CGPoint from, CGPoint to, NSTimeInterval seconds);
// stubs.m: the commands sent to the player.
NSUInteger SGRHarnessPlayerCommands(void);
// stubs.m: the last spotify: URI the mod asked Spotify's link dispatcher to open.
extern NSURL *SGRHarnessLastOpened;
// Low Power Mode as the process reports it, once reportPower has made it report this.
static BOOL sg_lowPower;
static void reportPower(void);
static void setThermal(NSProcessInfoThermalState state);

static NSString *scenario(void) {
    const char *value = getenv("HARNESS_SCENARIO");
    return value ? @(value) : @"lyrics";
}

#pragma mark - the picture server

// i.scdn.co as the harness wants it: each picture by the last 24 digits of its id, served after a delay
// of its own, or failed as if the phone were offline.
@interface SGRHarnessPicture : NSObject
@property (nonatomic, strong) UIImage *image;
@property (nonatomic) NSTimeInterval delay;
@property (nonatomic) BOOL fails;
@property (atomic) BOOL held, finished;
@property (nonatomic, strong) NSMutableArray<dispatch_block_t> *deliveries;
@end
@implementation SGRHarnessPicture
@end

static NSMutableDictionary<NSString *, SGRHarnessPicture *> *sg_pictures;
static NSUInteger sg_served;
// How many times the clip itself was served.
static NSUInteger sg_canvasServed;
// The catalog scenario's Apple Music: the addresses asked, in order, what it answers, and the clips' playlists
// asked for after it.
static NSMutableArray<NSURL *> *sg_catalogAsked, *sg_canvasAsked;
static NSInteger sg_catalogStatus = 200;
static NSData *sg_catalogBody;

static SGRHarnessPicture *serve(NSString *imageURI, UIImage *image, NSTimeInterval delay, BOOL fails) {
    if (!sg_pictures) sg_pictures = [NSMutableDictionary dictionary];
    SGRHarnessPicture *picture = [SGRHarnessPicture new];
    picture.image = image;
    picture.delay = delay;
    picture.fails = fails;
    picture.deliveries = [NSMutableArray array];
    sg_pictures[[imageURI substringFromIndex:imageURI.length - 24]] = picture;
    return picture;
}

static void deliverPicture(SGRHarnessPicture *picture) {
    NSArray<dispatch_block_t> *deliveries;
    @synchronized (picture) {
        picture.held = NO;
        deliveries = [picture.deliveries copy];
        [picture.deliveries removeAllObjects];
    }
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        for (dispatch_block_t delivery in deliveries) delivery();
    });
}
static BOOL pictureReady(SGRHarnessPicture *picture) {
    @synchronized (picture) { return picture.deliveries.count > 0; }
}

// For the automix scenario (automix-scenario.m).
void SGRHarnessServe(NSString *imageURI, UIImage *image) { serve(imageURI, image, 0, NO); }
void SGRHarnessRunAutoMix(UIWindow *window, UIViewController *durationUnit, UIView *tilt);
void SGRHarnessRunShare(UIWindow *window, BOOL systemOnly);

@interface SGRHarnessPictureServer : NSURLProtocol
@end

@implementation SGRHarnessPictureServer {
    BOOL _stopped;
}

+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    if ([request.URL.host isEqualToString:@"amp-api.music.apple.com"]) return sg_catalogAsked != nil;
    return [request.URL.host isEqualToString:@"i.scdn.co"] || [request.URL.host isEqualToString:@"canvas.harness"];
}

+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request {
    return request;
}

- (void)startLoading {
    if ([self.request.URL.host isEqualToString:@"amp-api.music.apple.com"]) {
        @synchronized (sg_catalogAsked) { [sg_catalogAsked addObject:self.request.URL]; }
        NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:self.request.URL statusCode:sg_catalogStatus HTTPVersion:@"HTTP/1.1"
                                                                headerFields:@{@"Content-Type": @"application/json"}];
        [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
        [self.client URLProtocol:self didLoadData:sg_catalogBody ?: [NSData data]];
        [self.client URLProtocolDidFinishLoading:self];
        return;
    }
    if (sg_canvasAsked && [self.request.URL.path hasSuffix:@".m3u8"]) {
        @synchronized (sg_canvasAsked) { [sg_canvasAsked addObject:self.request.URL]; }
        [self answer:nil];
        return;
    }
    // The motion scenario's clip, at once, or HARNESS_CANVAS_DELAY seconds late.
    if ([self.request.URL.host isEqualToString:@"canvas.harness"]) {
        const char *file = getenv("HARNESS_CANVAS_FILE"), *delay = getenv("HARNESS_CANVAS_DELAY");
        if ([self.request.URL.path hasPrefix:@"/square-"]) file = getenv("HARNESS_SQUARE_FILE");
        NSData *data = file ? [NSData dataWithContentsOfFile:@(file)] : nil;
        // HARNESS_CANVAS_FAILS=n: the first n requests for it fail on the way, as a download iOS canceled.
        static int failing = -1;
        if (failing < 0) failing = getenv("HARNESS_CANVAS_FAILS") ? atoi(getenv("HARNESS_CANVAS_FAILS")) : 0;
        if (failing > 0) {
            failing--;
            data = nil;
            NSLog(@"[harness] canvas server: this request fails");
        }
        NSThread *thread = NSThread.currentThread;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((delay ? atof(delay) : 0) * NSEC_PER_SEC)), dispatch_get_global_queue(0, 0), ^{
            sg_canvasServed++;
            [self performSelector:@selector(answer:) onThread:thread withObject:data waitUntilDone:NO];
        });
        return;
    }
    NSString *name = self.request.URL.lastPathComponent;
    SGRHarnessPicture *picture = name.length >= 24 ? sg_pictures[[name substringFromIndex:name.length - 24]] : nil;
    NSThread *thread = NSThread.currentThread;
    NSLog(@"[harness] picture server: %@ asked for, %@", name, picture ? (picture.fails ? @"will fail" : [NSString stringWithFormat:@"answers in %.1f s", picture.delay]) : @"unknown");
    NSData *data = picture.fails ? nil : UIImagePNGRepresentation(picture.image);
    dispatch_block_t delivery = ^{
        [self performSelector:@selector(answer:) onThread:thread withObject:data waitUntilDone:YES];
        picture.finished = YES;
    };
    @synchronized (picture) {
        if (picture.held) {
            [picture.deliveries addObject:delivery];
            return;
        }
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(picture.delay * NSEC_PER_SEC)),
                        dispatch_get_global_queue(0, 0), delivery);
}

- (void)answer:(NSData *)data {
    if (_stopped) return;
    if (!data) {
        [self.client URLProtocol:self didFailWithError:[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorNotConnectedToInternet userInfo:nil]];
        return;
    }
    sg_served++;
    NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:self.request.URL statusCode:200 HTTPVersion:@"HTTP/1.1"
                                                            headerFields:@{@"Content-Type": @"image/png"}];
    [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    [self.client URLProtocol:self didLoadData:data];
    [self.client URLProtocolDidFinishLoading:self];
}

- (void)stopLoading {
    _stopped = YES;
}

@end

// Every session the mod makes is handed the server first.
@implementation NSURLSessionConfiguration (SGRHarness)
+ (NSURLSessionConfiguration *)sgr_harnessDefault {
    NSURLSessionConfiguration *configuration = [self sgr_harnessDefault];
    configuration.protocolClasses = [@[SGRHarnessPictureServer.class] arrayByAddingObjectsFromArray:configuration.protocolClasses ?: @[]];
    return configuration;
}
@end

#pragma mark - pictures

static UIImage *solid(UIColor *color) {
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat preferredFormat];
    format.scale = 1;
    return [[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(300, 300) format:format] imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        [color setFill];
        UIRectFill(CGRectMake(0, 0, 300, 300));
    }];
}

// The color a picture is, by the pixel in its middle, named the way the checks name them.
static NSString *colorName(UIImage *image) {
    if (!image.CGImage) return @"none";
    uint8_t px[4] = {0};
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(px, 1, 1, 8, 4, space, (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(space);
    CGFloat w = CGImageGetWidth(image.CGImage), h = CGImageGetHeight(image.CGImage);
    CGContextDrawImage(context, CGRectMake(-w / 2, -h / 2, w, h), image.CGImage);
    CGContextRelease(context);
    int r = px[0] > 128, g = px[1] > 128, b = px[2] > 128;
    NSArray *names = @[@"black", @"blue", @"green", @"cyan", @"red", @"magenta", @"yellow", @"white"];
    return names[r << 2 | g << 1 | b];
}

// Sample the actual composed table, not a one-pixel render target that UIKit can cull or a half-pixel image.
static NSString *pixelAtPoint(UIView *view, CGPoint point) {
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat];
    format.scale = 1;
    UIImage *snapshot = [[[UIGraphicsImageRenderer alloc] initWithSize:view.bounds.size format:format] imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        [view drawViewHierarchyInRect:(CGRect){CGPointZero, view.bounds.size} afterScreenUpdates:YES];
    }];
    CGImageRef pixel = CGImageCreateWithImageInRect(snapshot.CGImage, CGRectMake(point.x - view.bounds.origin.x, point.y - view.bounds.origin.y, 1, 1));
    // Exact bytes matter: a darkened magenta row (38,0,38) is still visible, not an opaque black shield.
    uint8_t rgba[4] = {0};
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef bitmap = CGBitmapContextCreate(rgba, 1, 1, 8, 4, space, kCGImageAlphaPremultipliedLast);
    CGContextDrawImage(bitmap, CGRectMake(0, 0, 1, 1), pixel);
    CGContextRelease(bitmap);
    CGColorSpaceRelease(space);
    CGImageRelease(pixel);
    return [NSString stringWithFormat:@"%u,%u,%u,%u", rgba[0], rgba[1], rgba[2], rgba[3]];
}

#pragma mark - Spotify's classes, by name

#include <stdatomic.h>
static atomic_uint openingLayoutPasses;
static dispatch_semaphore_t openingFinished;

@interface SGROpeningHost : UIView @end
@implementation SGROpeningHost
- (void)layoutSubviews {
    atomic_fetch_add(&openingLayoutPasses, 1);
    [super layoutSubviews];
}
@end

// Drive either outcome of the same interactive transition at its completion boundary.
@interface HarnessDismissal : NSObject
@property (copy) void (^finish)(id<UIViewControllerTransitionCoordinatorContext>);
@property (getter=isCancelled) BOOL cancelled;
@end
@implementation HarnessDismissal
- (BOOL)isInteractive { return YES; }
- (BOOL)initiallyInteractive { return YES; }
- (BOOL)animateAlongsideTransition:(id)animation completion:(void (^)(id<UIViewControllerTransitionCoordinatorContext>))completion {
    self.finish = completion;
    return YES;
}
@end
@interface _TtC19NowPlaying_ViewImpl24NowPlayingViewController : UIViewController
@property HarnessDismissal *dismissal;
@end
@implementation _TtC19NowPlaying_ViewImpl24NowPlayingViewController
- (id<UIViewControllerTransitionCoordinator>)transitionCoordinator {
    return (id)self.dismissal ?: super.transitionCoordinator;
}
@end

@interface _TtC20NowPlaying_ModesImpl23InformationElementsUnit : UIViewController @end
@implementation _TtC20NowPlaying_ModesImpl23InformationElementsUnit @end

@interface _TtC20NowPlaying_ModesImpl19DurationElementUnit : UIViewController @end
@implementation _TtC20NowPlaying_ModesImpl19DurationElementUnit @end

@interface _TtC20NowPlaying_ModesImpl20FloatingElementsUnit : UIViewController @end
@implementation _TtC20NowPlaying_ModesImpl20FloatingElementsUnit @end

@interface _TtC20NowPlaying_ModesImpl28PlaybackControlsElementsUnit : UIViewController @end
@implementation _TtC20NowPlaying_ModesImpl28PlaybackControlsElementsUnit @end

// The header scenarios' root, whose status bar the grabber's edge checks hide: an iPad's window has a top inset only
// while its status bar shows.
@interface SGRHarnessStatusRoot : UIViewController
@property (nonatomic) BOOL bare;
@end
@implementation SGRHarnessStatusRoot
- (BOOL)prefersStatusBarHidden { return self.bare; }
@end

// The header unit's layouts, counted so the header scenario can tell the grabber kept up without one.
static NSUInteger sg_headerLayouts;
@interface _TtC20NowPlaying_ModesImpl18HeaderElementsUnit : UIViewController @end
@implementation _TtC20NowPlaying_ModesImpl18HeaderElementsUnit
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    sg_headerLayouts++;
}
@end

// The header unit for a while whose layouts reach none of the redesign's hooks (header-inset): UIKit may lay the row
// out as the window's inset changes, and the grabber has to follow without it.
@interface SGRHarnessStillHeaderUnit : _TtC20NowPlaying_ModesImpl18HeaderElementsUnit @end
@implementation SGRHarnessStillHeaderUnit
- (void)viewDidLayoutSubviews {
    sg_headerLayouts++;
}
@end

@interface _TtC20NowPlaying_ModesImpl18FooterElementsUnit : UIViewController @end
@implementation _TtC20NowPlaying_ModesImpl18FooterElementsUnit @end

@interface _TtC21NowPlaying_ScrollImpl23NPVScrollViewController : UIViewController <UIScrollViewDelegate> @end
@implementation _TtC21NowPlaying_ScrollImpl23NPVScrollViewController
- (void)scrollViewDidScroll:(UIScrollView *)list {}
@end

@interface _TtC35NowPlaying_ContentLayerPlatformImpl24AccessibleCollectionView : UICollectionView @end
static BOOL testCoverDrag;
@implementation _TtC35NowPlaying_ContentLayerPlatformImpl24AccessibleCollectionView
- (BOOL)isDragging { return testCoverDrag || [super isDragging]; }
@end

@interface _TtC28NowPlaying_ContentLayersImpl16CoverArtCellImpl : UICollectionViewCell @end
@implementation _TtC28NowPlaying_ContentLayersImpl16CoverArtCellImpl @end

@interface _TtC21NowPlaying_ScrollImpl27NPVBackgroundViewController : UIViewController @end
@implementation _TtC21NowPlaying_ScrollImpl27NPVBackgroundViewController @end

// One of the units Spotify shows its music video in (Switch to video); PlayerMotion.x hooks its video surface.
@interface _TtC22NowPlaying_ElementsKit14VideoElementUI : NSObject @end
@implementation _TtC22NowPlaying_ElementsKit14VideoElementUI
- (void)videoSurfaceDidAttachVideo:(id)surface {}
- (void)videoSurfaceDidDetachVideo:(id)surface {}
@end

@interface _TtC18NowPlaying_BarImpl27NowPlayingBarViewController : UIViewController @end
@implementation _TtC18NowPlaying_BarImpl27NowPlayingBarViewController @end

@interface _TtC22NowPlaying_ElementsKitP33_1D6A1393FEB35D7207F503DA17E7748E14ImageViewProxy : UIView @end
@implementation _TtC22NowPlaying_ElementsKitP33_1D6A1393FEB35D7207F503DA17E7748E14ImageViewProxy @end
@interface _TtCE15Encore_MediaKitO16EncoreFoundation6Encore9ImageView : UIView @end
@implementation _TtCE15Encore_MediaKitO16EncoreFoundation6Encore9ImageView @end
@interface _TtC35CreativeWorkCommons_CoverArtTiltKit16CoverArtTiltView : UIView
- (void)handleTap;
@end
@implementation _TtC35CreativeWorkCommons_CoverArtTiltKit16CoverArtTiltView
- (void)handleTap {}
@end

@interface _TtC22Lyrics_NPVContainerKit19LyricsContainerView : UIView @end
@implementation _TtC22Lyrics_NPVContainerKit19LyricsContainerView @end

// The progress bar's slider (01.txt:224), tracking without a touch so the harness can scrub it in code.
@interface _TtCO17NowPlaying_ECMKit11ProgressBar6Slider : UISlider @end
@implementation _TtCO17NowPlaying_ECMKit11ProgressBar6Slider
static NSUInteger sliderIdentifierReads;
- (NSString *)accessibilityIdentifier { sliderIdentifierReads++; return super.accessibilityIdentifier; }
- (BOOL)beginTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event { return YES; }
- (void)endTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {}
- (void)cancelTrackingWithEvent:(UIEvent *)event {}
@end

// The play button's view, which PlayerControls.x hooks for its tap.
@interface _TtC28EncoreConsumerMobile_BaseKit14PlayButtonView : UIView @end
@implementation _TtC28EncoreConsumerMobile_BaseKit14PlayButtonView
- (void)uiButtonTapped {}
@end

@interface MockEncoreButton : UIControl @end
@implementation MockEncoreButton @end

// Spotify's Encore label, which holds each time's UILabel, under its class name.
@interface SPTEncoreLabel : UIView @end
@implementation SPTEncoreLabel @end

// Spotify's Element holder, one button alone in it (9.2.0's player tree), under its class name.
@interface _TtGC13Element_UIKit11ElementViewT_P_P__ : UIView @end
@implementation _TtGC13Element_UIKit11ElementViewT_P_P__ @end

// Spotify's glyph view (Headers/SPTEncoreIconView.h), the queue's in the footer: it draws its glyph in the foreground
// color, or the active one while the queue is on.
@interface SPTEncoreIconView : UIView
@property (nonatomic, strong) UIColor *foregroundColor, *activeForegroundColor;
@property (nonatomic) BOOL isActive;
@property (nonatomic, strong) id icon;   // the SPTEncoreIcon it was made with, nil for the queue's in the tree
@end
@implementation SPTEncoreIconView {
    UIImageView *_drawn;
}
- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    _drawn = [[UIImageView alloc] initWithFrame:self.bounds];
    _drawn.image = [UIImage systemImageNamed:@"list.bullet"];
    _drawn.contentMode = UIViewContentModeScaleAspectFit;
    _drawn.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self addSubview:_drawn];
    _foregroundColor = UIColor.whiteColor;
    _activeForegroundColor = UIColor.greenColor;
    [self paint];
    return self;
}
- (instancetype)initWithIcon:(id)icon {
    if (!(self = [self initWithFrame:CGRectZero])) return nil;
    _icon = icon;
    _drawn.image = [UIImage systemImageNamed:[icon symbol]];
    return self;
}
- (void)setForegroundColor:(UIColor *)color { _foregroundColor = color; [self paint]; }
- (void)setActiveForegroundColor:(UIColor *)color { _activeForegroundColor = color; [self paint]; }
- (void)setIsActive:(BOOL)active { _isActive = active; [self paint]; }
- (void)paint { _drawn.tintColor = _isActive ? _activeForegroundColor : _foregroundColor; }
@end

// Spotify's glyph catalog (+[SPTEncoreIcon lyrics] and the like): each glyph drawn here by an SF Symbol of its own, unlike
// the Music app's the redesign draws, so a screenshot tells the two apart.
@interface SPTEncoreIcon : NSObject
@property (nonatomic, copy) NSString *name, *symbol;
@end
@implementation SPTEncoreIcon
+ (instancetype)named:(NSString *)name symbol:(NSString *)symbol {
    SPTEncoreIcon *icon = [self new];
    icon.name = name;
    icon.symbol = symbol;
    return icon;
}
+ (instancetype)microphone { return [self named:@"microphone" symbol:@"mic"]; }
+ (instancetype)queue { return [self named:@"queue" symbol:@"text.line.first.and.arrowtriangle.forward"]; }
@end

// The AI DJ's header and footer units (SGRDJClass's mangled Endless_DJMusicImpl names), built by the options scenario.
@interface _TtC19Endless_DJMusicImpl35DJMHeaderElementsUnitViewController : UIViewController @end
@implementation _TtC19Endless_DJMusicImpl35DJMHeaderElementsUnitViewController @end
@interface _TtC19Endless_DJMusicImpl27DJMFooterUnitViewController : UIViewController @end
@implementation _TtC19Endless_DJMusicImpl27DJMFooterUnitViewController @end

#pragma mark - building the tree

static UIView *box(UIView *parent, Class cls, CGRect frame, NSString *identifier) {
    UIView *view = [[cls alloc] initWithFrame:frame];
    view.accessibilityIdentifier = identifier;
    [parent addSubview:view];
    return view;
}

static UILabel *marquee(UIView *parent, CGRect frame, NSString *text, CGFloat size, UIColor *color, NSString *identifier) {
    UIView *clip = box(parent, UIView.class, frame, identifier);
    clip.clipsToBounds = YES;
    UILabel *inner = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 900, frame.size.height)];
    inner.text = text;
    inner.font = [UIFont systemFontOfSize:size weight:UIFontWeightBold];
    inner.textColor = color;
    [inner sizeToFit];
    [clip addSubview:inner];
    return inner;
}

static UIView *glyphButton(UIView *parent, CGRect frame, NSString *symbol, NSString *identifier) {
    UIView *button = box(parent, MockEncoreButton.class, frame, identifier);
    UIImageView *glyph = [[UIImageView alloc] initWithFrame:CGRectInset(button.bounds, 10, 10)];
    glyph.image = [UIImage systemImageNamed:symbol];
    glyph.contentMode = UIViewContentModeScaleAspectFit;
    glyph.tintColor = UIColor.whiteColor;
    [button addSubview:glyph];
    return button;
}

static UIImage *artwork(void) {
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(354, 354)];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
        CGFloat components[] = {0.11, 0.06, 0.35, 1, 0.83, 0.15, 0.62, 1};
        CGGradientRef gradient = CGGradientCreateWithColorComponents(space, components, NULL, 2);
        CGContextDrawLinearGradient(ctx.CGContext, gradient, CGPointZero, CGPointMake(354, 354), 0);
        CGGradientRelease(gradient);
        CGColorSpaceRelease(space);
        [[UIColor colorWithWhite:1 alpha:0.9] set];
        [@"LOOSE\nCANON" drawAtPoint:CGPointMake(28, 28) withAttributes:@{
            NSFontAttributeName: [UIFont systemFontOfSize:44 weight:UIFontWeightHeavy],
            NSForegroundColorAttributeName: [UIColor colorWithRed:1 green:0.92 blue:0.2 alpha:1],
        }];
    }];
}

// A second album, busier: a warm sky over teal water with a sun in it, for the track change.
static UIImage *secondArtwork(void) {
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(354, 354)];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        CGContextRef c = ctx.CGContext;
        CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
        CGFloat sky[] = {0.98, 0.55, 0.20, 1, 0.85, 0.22, 0.30, 1};
        CGGradientRef gradient = CGGradientCreateWithColorComponents(space, sky, NULL, 2);
        CGContextDrawLinearGradient(c, gradient, CGPointZero, CGPointMake(0, 200), 0);
        CGGradientRelease(gradient);
        CGFloat sea[] = {0.05, 0.45, 0.50, 1, 0.02, 0.12, 0.22, 1};
        gradient = CGGradientCreateWithColorComponents(space, sea, NULL, 2);
        CGContextSaveGState(c);
        CGContextClipToRect(c, CGRectMake(0, 200, 354, 154));
        CGContextDrawLinearGradient(c, gradient, CGPointMake(0, 200), CGPointMake(0, 354), 0);
        CGContextRestoreGState(c);
        CGGradientRelease(gradient);
        CGColorSpaceRelease(space);
        [[UIColor colorWithRed:1 green:0.9 blue:0.55 alpha:1] setFill];
        CGContextFillEllipseInRect(c, CGRectMake(210, 110, 90, 90));
        [@"LOW\nTIDE" drawAtPoint:CGPointMake(26, 230) withAttributes:@{
            NSFontAttributeName: [UIFont systemFontOfSize:40 weight:UIFontWeightHeavy],
            NSForegroundColorAttributeName: [UIColor colorWithWhite:1 alpha:0.9],
        }];
    }];
}

// A song with words timed inside each line, the shape SGRKaraokeView draws.
static void loadLyrics(void) {
    NSArray<NSString *> *texts = @[
        @"Who got the 808 under the 809",
        @"Making everybody jump?",
        @"Easy, I'm motivated",
        @"I got the feeling this is overrated",
        @"Give me the respect or give me nothing",
        @"Running up the hill with a heavy load",
        @"Tell them that the kid never folded",
        @"Every single verse was a promise kept",
        @"Nobody was there when it started",
        @"Now everybody wanna say they knew",
    ];
    NSMutableArray<SGKaraokeLine *> *lines = [NSMutableArray array];
    if ([scenario() hasPrefix:@"lyric-line"]) texts = @[@"한순간이였지"];
    if ([scenario() isEqual:@"lyric-line-ownership"])
        texts = @[@"Short", @"A longer phrase that cannot possibly fit onto one row of the available width"];
    if ([scenario() hasPrefix:@"lyric-line-chip"]) texts = @[@"Now I don't want you calling me baby now"];
    if ([scenario() isEqual:@"lyric-line-chip-live"]) texts = [texts arrayByAddingObject:@"Second verse"];
    BOOL longFirst = [scenario() isEqual:@"lyric-line-long"];
    if (longFirst) texts = @[@"First we find the words and then we sing the words together before another phrase begins and carries on until the final note"];
    NSInteger at = 0;
    for (NSString *text in texts) {
        NSArray<NSString *> *words = [text componentsSeparatedByString:@" "];
        NSMutableArray<SGKaraokeWord *> *built = [NSMutableArray array];
        NSInteger cursor = at;
        for (NSString *word in words) {
            SGKaraokeWord *w = [SGKaraokeWord new];
            w.text = word;
            w.start = cursor;
            cursor += 260 + word.length * 40;
            // Each line's last word is held, as sung lines often end, so the held-word glow shows.
            if (word == words.lastObject) cursor += 1600;
            if (longFirst) cursor = w.start + 1000;
            else if ([scenario() hasPrefix:@"lyric-line"]) cursor = at + 60000;
            w.end = cursor;
            [built addObject:w];
        }
        SGKaraokeLine *line = [SGKaraokeLine new];
        if ([scenario() hasPrefix:@"lyric-line"]) line.translation = @"One moment";
        line.words = built;
        line.start = at;
        line.end = cursor;
        [lines addObject:line];
        at = cursor + 400;
    }
    SGKaraokeKeepLines(@"harness", lines);
}

#pragma mark - the harness

// PlayerArtwork.x's hold on the cover, whose badge the badge scenario shows and hides by hand.
@interface NSObject (SGRHarnessHold)
- (void)showBadge:(BOOL)shown on:(UIView *)cover;
@end

// PlayerLyrics.x's tap that brings the controls back and the thumbnail's, fired by hand.
@interface NSObject (SGRHarnessLyrics)
- (void)sgr_woke;
- (void)sgr_thumbTapped;
@end

@interface SGRHarnessDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@interface NSObject (SGRAdaptiveBuild)
- (BOOL)buildPlayer;
@end
@interface SGRHarnessAdaptiveRoot : UIViewController
@property (nonatomic) BOOL built;
@end
@implementation SGRHarnessAdaptiveRoot
- (void)buildWhenVisible {
    if (self.built) return;
    self.built = YES;
    [(id)UIApplication.sharedApplication.delegate buildPlayer];
}
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (getenv("HARNESS_LANDSCAPE")) {
        if (self.view.bounds.size.width > self.view.bounds.size.height) {
            [self buildWhenVisible];
            return;
        }
        [self.view.window.windowScene requestGeometryUpdateWithPreferences:
            [[UIWindowSceneGeometryPreferencesIOS alloc] initWithInterfaceOrientations:UIInterfaceOrientationMaskLandscapeLeft]
            errorHandler:^(NSError *error) { HARNESS_FAIL(@"adaptive rotation: %@", error); }];
    } else {
        [self buildWhenVisible];
    }
}
- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
    [coordinator animateAlongsideTransition:nil completion:^(id<UIViewControllerTransitionCoordinatorContext> context) {
        if (getenv("HARNESS_LANDSCAPE") && self.view.bounds.size.width > self.view.bounds.size.height) [self buildWhenVisible];
    }];
}
@end

@implementation SGRHarnessDelegate {
    NSArray<UIViewController *> *_units;
    UIImageView *_cover, *_barCover;
    UIViewController *_bar;
    UICollectionView *_covers;
    UIScrollView *_list;
    UIView *_plane, *_host;
    CGRect _openingSingleFrame;
    UIViewController *_background;
    UIView *_tilt;
    NSUInteger _failures, _checks;
    float _dimAlone;   // the motion scenario's dim before the lyrics
    // The options scenario's views: the footer's Connect glyph and queue icon, the AI DJ's header and footer, the
    // glyph Spotify drew for Connect.
    UIImageView *_connectImage, *_djConnectImage;
    SPTEncoreIconView *_queueIcon;
    UIView *_djHeader, *_djFooter, *_djButton, *_djConnect, *_djShare;
    UIImage *_spotifyConnect, *_djSpotifyConnect;
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    if (getenv("HARNESS_OPENING")) {
        openingFinished = dispatch_semaphore_create(0);
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            if (dispatch_semaphore_wait(openingFinished, dispatch_time(DISPATCH_TIME_NOW, 15 * NSEC_PER_SEC))) {
                HARNESS_FAIL(@"opening failed to settle/respond: %u host layout passes", atomic_load(&openingLayoutPasses));
            }
        });
    }
    loadLyrics();
    if (getenv("HARNESS_NO_LYRICS")) SGKaraokeKeepLines(SGKaraokePlayingTrack(), nil);
    SGRHarnessPlayFrom(2400);
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    UIViewController *root = [scenario() isEqualToString:@"adaptive"] ? [SGRHarnessAdaptiveRoot new]
                           : [scenario() hasPrefix:@"header"] ? [SGRHarnessStatusRoot new] : [UIViewController new];
    root.view.backgroundColor = [UIColor colorWithRed:0.09 green:0.07 blue:0.17 alpha:1];
    self.window.rootViewController = root;
    if ([scenario() isEqualToString:@"adaptive"]) {
        [self.window makeKeyAndVisible];
        return YES;
    }
    return [self buildPlayer];
}

- (BOOL)buildPlayer {
    if ([scenario() hasPrefix:@"settings-pending-"]) {
        BOOL redesign = [scenario() hasSuffix:@"redesigned"];
        HARNESS_CHECK(SGRedesignedUI() != redesign);
        SGSetEnabled(SGKeyRedesign,redesign); // Later: the stored page changes, the running hooks do not.
        HARNESS_CHECK(SGRedesignedUIStored() == redesign);
        if (redesign) {
            UIView *preview = [SGRPlayerSettingsPage(@[SGRPlayerButtonsSection()]) valueForKey:@"preview"];
            UITableViewCell *cell = [[NSClassFromString(@"SGRPlayerButtonsCell") alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
            UIButton *video = [[cell valueForKey:@"chips"] lastObject];
            [preview performSelector:@selector(reloadLook)];
            HARNESS_CHECK(video && !video.selected && [[preview valueForKey:@"_chip"] isHidden]);
            [video sendActionsForControlEvents:UIControlEventTouchUpInside];
            [cell performSelector:@selector(readKeys)]; [preview performSelector:@selector(reloadLook)];
            HARNESS_CHECK(video.selected && ![[preview valueForKey:@"_chip"] isHidden]);
        } else {
            SGModPage *page = [[SGModPage alloc] initWithTitle:@"Player" intro:nil sections:@[SGSection(nil,@[SGNativeVideoSwitchRow()])] footer:nil];
            self.window.rootViewController = page;
            [self.window makeKeyAndVisible];
            dispatch_async(dispatch_get_main_queue(), ^{
                [page.tableView layoutIfNeeded];
                UITableViewCell *cell = [page.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];
                UISwitch *toggle = (UISwitch *)cell.accessoryView;
                HARNESS_CHECK(toggle);
                HARNESS_CHECK(!toggle.isOn);
                toggle.on = YES; [toggle sendActionsForControlEvents:UIControlEventValueChanged];
                HARNESS_CHECK(SGNativeVideoSwitchRow().readSwitch());
                NSLog(@"[harness] %@ passed",scenario()); exit(0);
            });
            return YES;
        }
        HARNESS_CHECK([[NSUserDefaults.standardUserDefaults objectForKey:SGKeyHideVideoSwitch] isEqual:@(!redesign)]);
        NSLog(@"[harness] %@ passed",scenario()); exit(0);
    }
    if ([scenario() hasPrefix:@"video-"]) {
        BOOL native = [scenario() isEqual:@"video-native"], reopened = [scenario() isEqual:@"video-relaunch"];
        UIViewController *unit = [_TtC20NowPlaying_ModesImpl20FloatingElementsUnit new];
        UIView *button = box(unit.view,UIButton.class,CGRectMake(0,0,128,32),SGVideoSwitchIdentifier);
        [unit viewDidLayoutSubviews];
        HARNESS_CHECK(!!button.superview == (native || reopened));
        if (!native && !reopened) {
            SGSetEnabled(SGKeyStock,YES); [unit.view addSubview:button]; [unit viewDidLayoutSubviews];
            HARNESS_CHECK(button.superview);
            [NSUserDefaults.standardUserDefaults removeObjectForKey:SGKeyStock]; SGPrefsChanged();
            SGSetEnabled(SGKeyHideVideoSwitch,NO); [unit viewDidLayoutSubviews]; HARNESS_CHECK(button.superview);
        }
        NSLog(@"[harness] %@ passed",scenario()); exit(0);
    }
    UIViewController *root = self.window.rootViewController;
    CGFloat W = root.view.bounds.size.width, H = root.view.bounds.size.height;
    BOOL stripPreview = [scenario() isEqual:@"cover-strip-preview"];
    BOOL emptyLine = [scenario() isEqual:@"lyric-line-empty-strip"];
    BOOL stripCheck = stripPreview || emptyLine || [scenario() isEqual:@"cover-empty-strip"];
    BOOL ownerChip = stripCheck || [scenario() isEqual:@"lyric-line-owner"] || [scenario() isEqual:@"lyric-line-owner-clip"];
    if (ownerChip || [scenario() isEqual:@"lyric-line-compact"]) { W = 393; H = 852; }
    if ([scenario() isEqualToString:@"adaptive"]) {
        if (getenv("HARNESS_COMPACT")) {
            W = 500;
            self.window.traitOverrides.horizontalSizeClass = UIUserInterfaceSizeClassCompact;
        }
        if (getenv("HARNESS_RTL")) root.view.semanticContentAttribute = UISemanticContentAttributeForceRightToLeft;
    }
    // The player's own numbers are the tree's 402x874; the simulator's screen is whatever it is, so the
    // rows are placed as shares of it, the way Spotify's layout puts them.
    CGFloat headerTop = 62, headerHeight = 48;
    CGFloat bandTop = headerTop + headerHeight;
    const char *volumeEnv = getenv("HARNESS_VOLUME");
    BOOL hasVolume = !(volumeEnv && volumeEnv[0] == '0');
    CGFloat bottomHeight = 236 + (hasVolume ? 44 : 0);   // the tree's rows plus a volume row, as the phone has it
    CGFloat bottomTop = H - bottomHeight - 61.33;
    if (ownerChip) bottomTop = 482;
    CGFloat bandHeight = bottomTop - bandTop;
    CGFloat coverSide = MIN(354, W - 48);

    // NPVScrollViewController: the list the player is the header of.
    UIView *page = box(root.view, UIView.class, root.view.bounds, nil);
    UIScrollView *list = [[UIScrollView alloc] initWithFrame:page.bounds];
    if ([scenario() isEqualToString:@"adaptive"]) list.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    list.accessibilityIdentifier = @"scrolling_npv_collection_view_accessibility_identifier";
    list.contentSize = CGSizeMake(W, H + 326);       // the player and a card's worth of cards under it
    [page addSubview:list];
    UIViewController *scrollUnit = [_TtC21NowPlaying_ScrollImpl23NPVScrollViewController new];
    scrollUnit.view = page;
    list.delegate = (id<UIScrollViewDelegate>)scrollUnit;
    _list = list;

    // NPVBackgroundViewController's plane, the field's home (trees/clean/player/01.txt:449), under the player.
    UIView *plane = box(list, UIView.class, CGRectMake(0, 0, W, H), nil);
    plane.backgroundColor = [UIColor colorWithRed:0.3 green:0.1 blue:0.3 alpha:1];
    UIViewController *background = [_TtC21NowPlaying_ScrollImpl27NPVBackgroundViewController new];
    background.view = plane;

    UIView *host = box(list, getenv("HARNESS_OPENING") ? SGROpeningHost.class : UIView.class,
                      CGRectMake(0, 0, W, H), @"SPTNowPlayingView");
    if (getenv("HARNESS_RTL")) host.semanticContentAttribute = UISemanticContentAttributeForceRightToLeft;

    // the content layers: the sideways list of covers
    UIView *layers = box(host, UIView.class, host.bounds, nil);
    UICollectionViewFlowLayout *flow = [UICollectionViewFlowLayout new];
    UICollectionView *covers = [[_TtC35NowPlaying_ContentLayerPlatformImpl24AccessibleCollectionView alloc]
                                initWithFrame:layers.bounds collectionViewLayout:flow];
    covers.accessibilityIdentifier = @"nowplaying-contentlayer-collectionview";
    covers.backgroundColor = UIColor.clearColor;
    [layers addSubview:covers];
    // The replacement can discover a pager Spotify has already faded out; compact must repair it.
    if ([scenario() isEqualToString:@"adaptive"] && !getenv("HARNESS_OPENING") && SGRPlayerIPadRegular(host))
        covers.alpha = 0;
    BOOL previewTap = [scenario() isEqual:@"preview-tap"] || [scenario() isEqual:@"preview-pending"];
    Class cellClass = _TtC28NowPlaying_ContentLayersImpl16CoverArtCellImpl.class;
    UIView *cell = previewTap ? SGHarnessSelectableCover(covers, cellClass)
                              : box(covers, cellClass, covers.bounds, @"nowplaying-contentlayer-cell-0");
    UIView *band = box(((UICollectionViewCell *)cell).contentView, UIView.class, CGRectMake(0, bandTop, W, bandHeight), nil);
    UIView *inner = box(band, UIView.class, CGRectMake(24, 8, W - 48, bandHeight - 16), nil);
    UIView *tilt = box(inner, _TtC35CreativeWorkCommons_CoverArtTiltKit16CoverArtTiltView.class,
                       CGRectMake(0, round((inner.bounds.size.height - coverSide) / 2), coverSide, coverSide), nil);
    tilt.accessibilityLabel = @"Inspect cover art";
    _tilt = tilt;
    // The Encore.ImageView holding the picture (01.txt:40), which PlayerField.x reads the cover from.
    UIView *coverElement = box(tilt, UIView.class, tilt.bounds, @"Encore.ImageView");
    coverElement.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    UIImage *picture = getenv("HARNESS_NO_ARTWORK") ? nil : artwork();
    UIImageView *cover = [[UIImageView alloc] initWithFrame:coverElement.bounds];
    cover.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    cover.image = picture;
    _cover = cover;
    cover.contentMode = UIViewContentModeScaleAspectFill;
    if (stripCheck || [@[@"lyric-line-compact", @"lyric-line-ownership", @"artwork-unowned"] containsObject:scenario()]) {
        UIView *proxy = box(coverElement, NSClassFromString(@"_TtC22NowPlaying_ElementsKitP33_1D6A1393FEB35D7207F503DA17E7748E14ImageViewProxy"), coverElement.bounds, nil);
        UIView *image = box(proxy, NSClassFromString(@"_TtCE15Encore_MediaKitO16EncoreFoundation6Encore9ImageView"), proxy.bounds, @"Encore.ImageView");
        [image addSubview:cover];
        cover.autoresizingMask = UIViewAutoresizingNone;
    } else [coverElement addSubview:cover];
    UIView *previewShell = box(inner, _TtC22Lyrics_NPVContainerKit19LyricsContainerView.class, CGRectMake(0, inner.bounds.size.height, coverSide, 0), nil);
    if (previewTap) {
        previewShell.frame = CGRectMake(0, inner.bounds.size.height - 80, coverSide, 32);
        ((UILabel *)box(previewShell, UILabel.class, previewShell.bounds, nil)).text = @"One lyric line";
    }
    if ([scenario() isEqualToString:@"lyric-line"]) {
        // Spotify keeps a populated, invisible wrapper beside the ordinary cover on tracks without a preview.
        previewShell.frame = CGRectMake(0, inner.bounds.size.height, coverSide, 100);
        previewShell.alpha = 0;
        UILabel *placeholder = (UILabel *)box(previewShell, UILabel.class, previewShell.bounds, @"Encore.Label-internal");
        placeholder.font = [UIFont systemFontOfSize:17];
    }

    // the header row; for the cover scenario alone in the stack of its own size Spotify 9.2.0 holds it in, which took
    // the touches the row let go over the lifted cover's top (issue #27)
    CGRect headerFrame = CGRectMake(0, headerTop, W, headerHeight);
    UIView *headerHolder = [scenario() isEqualToString:@"cover"] ? box(host, UIStackView.class, headerFrame, nil) : host;
    UIView *header = box(headerHolder, UIStackView.class, headerHolder == host ? headerFrame : headerHolder.bounds, nil);
    UIControl *arrow = (UIControl *)glyphButton(header, CGRectMake(12, 0, 48, 48), @"chevron.down", @"now-playing-minimize-button");
    // Spotify's arrow closes the player on a tap; header-noroute's has nothing to close by.
    if (![scenario() isEqualToString:@"header-noroute"])
        [arrow addAction:[UIAction actionWithHandler:^(UIAction *action) { NSLog(@"[harness] the down arrow's action ran"); }]
        forControlEvents:UIControlEventTouchUpInside];
    glyphButton(header, CGRectMake(W - 60, 0, 48, 48), @"ellipsis", @"Context menu");
    UIView *context = box(header, UIView.class, CGRectMake(72, 0, W - 144, 48), @"now-playing-navigation-unit-title-label");
    context.isAccessibilityElement = YES;
    context.accessibilityLabel = @"TECHNO BUNKER";
    UILabel *contextLabel = [[UILabel alloc] initWithFrame:context.bounds];
    contextLabel.text = @"TECHNO BUNKER";
    [context addSubview:contextLabel];
    // Spotify 9.2.0's row holds its buttons and where it plays from in a stack of their own, whose elements take a touch
    // landing between what they draw (the 9.2.0 phone tree: a tap at y 100 landed on that stack): under them here.
    if (headerHolder != host) {
        UIView *elements = box(header, UIStackView.class, CGRectMake(12, 0, W - 24, headerHeight), nil);
        [header sendSubviewToBack:elements];
        box(elements, UIView.class, CGRectMake(60, 0, W - 144, headerHeight), nil);
    }

    // the bottom stack: information, duration, controls, volume, footer
    UIView *bottom = box(host, UIStackView.class, CGRectMake(0, bottomTop, W, bottomHeight), @"npv.bottomStackView");
    // Spotify 9.2.0's plain view over the strip under the bottom stack, after it in the player, which takes a touch there
    // (the phone's tree: UIView {{0, 785}, {390, 59}} after npv.bottomStackView). The footer scenario's.
    if ([scenario() isEqualToString:@"look"])
        box(host, UIView.class, CGRectMake(0, CGRectGetMaxY(bottom.frame), W, H - CGRectGetMaxY(bottom.frame)), nil);

    UIView *floatingView = box(bottom, UIView.class, CGRectMake(0, 0, W, 32), nil);
    UIView *parent = floatingView;
    if (ownerChip) {
        UIView *scroll = box(parent, UIScrollView.class, parent.bounds, nil);
        UIView *stack = box(scroll, UIStackView.class, CGRectMake(24,0,128.67,32), nil);
        parent = box(stack, UIView.class, stack.bounds, nil);
        UIView *hidden = box(stack, UIView.class, CGRectMake(0,0,52,32), nil);
        hidden.hidden = YES;
        UIView *other = box(hidden, MockEncoreButton.class, hidden.bounds, @"hidden-button");
        other.hidden = YES; other.backgroundColor = UIColor.blackColor;
        [stack sendSubviewToBack:parent];
    }
    UIView *chip = box(parent, ownerChip ? UIButton.class : UIView.class, ownerChip ? parent.bounds : CGRectMake(24,0,148,32), nil);
    chip.backgroundColor = [UIColor colorWithWhite:1 alpha:0.16];
    chip.layer.cornerRadius = 16;
    UILabel *chipLabel = [[UILabel alloc] initWithFrame:chip.bounds];
    if ([scenario() hasPrefix:@"lyric-line"] || previewTap) chip.hidden = YES;
    if ([scenario() isEqual:@"lyric-line-chip"]) {
        chip.accessibilityIdentifier = @"nowplaying-npv-musicvideos-switch";
        chipLabel.frame = CGRectInset(chip.bounds, 8, 8);
    }
    if ([scenario() isEqual:@"lyric-line-chip-live"]) {
        chip.hidden = NO;
        chip.alpha = 0;
    }
    chipLabel.text = @"  \u25B6  Switch to video";
    chipLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    chipLabel.textColor = UIColor.whiteColor;
    if (ownerChip) {
        chip.accessibilityIdentifier = SGVideoSwitchIdentifier;
        chip.backgroundColor = UIColor.clearColor;
        UIView *shell = box(chip,UIView.class,chip.bounds,nil);
        CALayer *pill = [CALayer layer]; pill.frame = CGRectInset(shell.bounds,0,4);
        pill.backgroundColor = UIColor.darkGrayColor.CGColor; pill.cornerRadius = 12; [shell.layer addSublayer:pill];
        UIView *items = box(shell,UIStackView.class,CGRectInset(shell.bounds,13,8),nil);
        UIView *itemsRow = box(items,UIStackView.class,items.bounds,nil);
        UIView *label = box(itemsRow,UIView.class,CGRectMake(24,.67,78.67,15),@"label");
        chipLabel.frame = label.bounds; [label addSubview:chipLabel];
        box(itemsRow,SPTEncoreIconView.class,CGRectMake(0,0,16,16),@"icon");
    } else [chip addSubview:chipLabel];

    UIView *infoView = box(bottom, UIView.class, CGRectMake(0, 0, W, 64), nil);
    UIView *infoRow = box(infoView, UIStackView.class, CGRectMake(12, 8, W - 24, 48), nil);
    UIView *infoInner = box(infoRow, UIStackView.class, infoRow.bounds, nil);
    box(infoInner, UIView.class, CGRectMake(0, 24, 0, 0), nil);          // Spotify's own mini cover, unused
    box(infoInner, UIView.class, CGRectMake(0, 24, 12, 0), nil);         // the spacer after it
    CGFloat titleWidth = infoInner.bounds.size.width - 12 - 60;
    UIView *titleElement = box(infoInner, UIView.class, CGRectMake(12, 2.33, titleWidth, 43.33), nil);
    UIView *titleContainer = box(titleElement, UIView.class, titleElement.bounds, nil);
    marquee(titleContainer, CGRectMake(0, 0, titleWidth, 25.33), @"We Are The People - southstar Remix (Extended)", 21,
            UIColor.whiteColor, @"now-playing-title-label");
    marquee(titleContainer, CGRectMake(0, 25.33, titleWidth, 18), @"Canon", 13,
            [UIColor colorWithWhite:1 alpha:0.7], @"now-playing-subtitle-label");
    glyphButton(infoInner, CGRectMake(infoInner.bounds.size.width - 48, 0, 48, 48), @"star", @"Components.UI.AddToButton");

    UIView *durationView = box(bottom, UIView.class, CGRectMake(0, 64, W, 40), nil);
    UIView *track = box(durationView, UIView.class, CGRectMake(24, 8, W - 48, 6), nil);
    track.backgroundColor = [UIColor colorWithWhite:1 alpha:0.3];
    track.layer.cornerRadius = 3;
    UIView *played = box(track, UIView.class, CGRectMake(0, 0, (W - 48) * 0.22, 6), nil);
    played.backgroundColor = [UIColor colorWithWhite:1 alpha:0.85];
    played.layer.cornerRadius = 3;

    UIView *controls = box(bottom, UIView.class, CGRectMake(0, 104, W, 88), nil);
    glyphButton(controls, CGRectMake(W / 2 - 130, 20, 48, 48), @"backward.fill", nil);
    glyphButton(controls, CGRectMake(W / 2 - 24, 14, 48, 60), @"pause.fill", nil);
    glyphButton(controls, CGRectMake(W / 2 + 82, 20, 48, 48), @"forward.fill", nil);

    if (hasVolume) {
        UIView *volume = box(bottom, UIView.class, CGRectMake(0, 192, W, 44), nil);
        UIView *volumeTrack = box(volume, UIView.class, CGRectMake(44, 19, W - 88, 6), nil);
        volumeTrack.backgroundColor = [UIColor colorWithWhite:1 alpha:0.3];
        volumeTrack.layer.cornerRadius = 3;
    }

    UIView *footerView = box(bottom, UIView.class, CGRectMake(0, hasVolume ? 236 : 192, W, 44), nil);
    UIView *footerRow = box(footerView, UIStackView.class, CGRectMake(12, 0, W - 24, 44), nil);
    UIView *connect = box(footerRow, UIView.class, CGRectMake(0, 4, 153.67, 36), nil);
    UIView *connectHolder = box(connect, UIView.class, connect.bounds, @"Components.ConnectButtonOutputSwitcher");
    UIImageView *connectGlyph = [[UIImageView alloc] initWithFrame:CGRectMake(0, 8, 19, 19)];
    connectGlyph.image = [UIImage systemImageNamed:@"airpods.pro"];
    connectGlyph.tintColor = UIColor.whiteColor;
    [connectHolder addSubview:connectGlyph];
    _connectImage = connectGlyph;
    _spotifyConnect = connectGlyph.image;
    glyphButton(footerRow, CGRectMake(279, 0, 44, 44), @"square.and.arrow.up", @"ShareButtonNowPlayingView");
    // The queue control holds Spotify's 18x18 glyph view (out/rep/ptree.txt:1228-1279).
    UIView *queueButton = box(footerRow, MockEncoreButton.class, CGRectMake(323, 6, 47, 32), @"QueueButtonNowPlaying");
    _queueIcon = (SPTEncoreIconView *)box(queueButton, SPTEncoreIconView.class, CGRectMake(14.5, 7, 18, 18), @"Encore.IconView");
    if ([scenario() isEqualToString:@"adaptive"]) {
        for (UIView *row in bottom.subviews) row.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        for (UIView *view in @[infoRow, infoInner, titleElement, titleContainer, durationView.subviews.firstObject, footerRow])
            view.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        for (UIView *view in controls.subviews)
            view.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
        infoInner.subviews.lastObject.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
        for (UIView *view in titleContainer.subviews) view.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        if (hasVolume) bottom.subviews[4].subviews.firstObject.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    }

    // The options scenario's AI DJ: its header unit's two buttons over the status bar, and its footer (DJMFooterUnitView:
    // share, the DJ button and Connect, not in a stack) over the player's own header row. On the phone the DJ's footer is
    // under its controls, where the lyrics never reach; here the ordinary player's rows hold that place, and the header
    // row is the one place the open lyrics leave alone (their thumbnail takes the title row's place under it).
    UIViewController *djHeaderUnit = nil, *djFooterUnit = nil;
    if ([scenario() isEqualToString:@"options"]) {
        _djHeader = box(host, UIView.class, CGRectMake(0, 8, W, headerHeight), nil);
        glyphButton(_djHeader, CGRectMake(W / 2 - 104, 0, 48, 48), @"chevron.down", @"now-playing-minimize-button");
        glyphButton(_djHeader, CGRectMake(W / 2 + 56, 0, 48, 48), @"ellipsis", @"Context menu");
        _djFooter = box(host, UIView.class, CGRectMake(0, headerTop, W, 44), nil);
        UIView *djConnectHolder = box(_djFooter, UIView.class, CGRectMake(16, 4, 153, 36), nil);
        UIView *djConnect = box(djConnectHolder, UIView.class, djConnectHolder.bounds, @"Components.ConnectButtonOutputSwitcher");
        _djConnect = djConnect;
        _djConnectImage = [[UIImageView alloc] initWithFrame:CGRectMake(0, 8, 19, 19)];
        _djConnectImage.image = [UIImage systemImageNamed:@"hifispeaker"];
        _djConnectImage.tintColor = UIColor.whiteColor;
        _djSpotifyConnect = _djConnectImage.image;
        [djConnect addSubview:_djConnectImage];
        UILabel *device = [[UILabel alloc] initWithFrame:CGRectMake(26, 8, 120, 19)];
        device.text = @"Living Room";
        device.textColor = UIColor.whiteColor;
        [djConnect addSubview:device];
        // Connect under the DJ button and the share button's holder over it, right where the footer puts the DJ button:
        // the order in which a holder given its touches back would take the DJ button's.
        UIView *djHolder = box(_djFooter, UIView.class, CGRectMake(W - 120, -2, 48, 48), nil);
        UIView *dj = box(djHolder, MockEncoreButton.class, djHolder.bounds, @"Components.UI.NeffleButtonNowPlayingContainerView");
        dj.backgroundColor = UIColor.systemBlueColor;
        dj.layer.cornerRadius = 24;
        dj.isAccessibilityElement = YES;
        dj.accessibilityLabel = @"DJ";
        _djButton = dj;
        UIView *shareHolder = box(_djFooter, UIView.class, CGRectMake(round(W * 0.8) - 22, 0, 44, 44), nil);
        _djShare = glyphButton(shareHolder, shareHolder.bounds, @"square.and.arrow.up", @"ShareButtonNowPlayingView");
        box(_djFooter, UIView.class, CGRectMake(W / 2, 0, 1, 44), nil);   // the empty view
        djHeaderUnit = [_TtC19Endless_DJMusicImpl35DJMHeaderElementsUnitViewController new];
        djHeaderUnit.view = _djHeader;
        djFooterUnit = [_TtC19Endless_DJMusicImpl27DJMFooterUnitViewController new];
        djFooterUnit.view = _djFooter;
    }

    // The now playing bar, off screen: the Kit reads its 40pt cover (SPTNowPlayingBar > Encore.ImageView >
    // UIImageView, trees/clean/artist/01.txt).
    UIView *barView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, W, 64)];
    UIView *barCard = box(barView, UIView.class, CGRectMake(8, 8, W - 16, 48), @"SPTNowPlayingBar");
    UIView *barHolder = box(barCard, UIView.class, CGRectMake(8, 4, 40, 40), @"Encore.ImageView");
    UIImageView *barCover = [[UIImageView alloc] initWithFrame:barHolder.bounds];
    barCover.image = picture;
    [barHolder addSubview:barCover];
    _barCover = barCover;
    _bar = [_TtC18NowPlaying_BarImpl27NowPlayingBarViewController new];
    _bar.view = barView;

    [self.window makeKeyAndVisible];

    UIViewController *info = [_TtC20NowPlaying_ModesImpl23InformationElementsUnit new];
    info.view = infoView;
    UIViewController *duration = [_TtC20NowPlaying_ModesImpl19DurationElementUnit new];
    duration.view = durationView;
    UIViewController *floating = [_TtC20NowPlaying_ModesImpl20FloatingElementsUnit new];
    floating.view = floatingView;
    UIViewController *footer = [_TtC20NowPlaying_ModesImpl18FooterElementsUnit new];
    footer.view = footerView;
    UIViewController *playback = [_TtC20NowPlaying_ModesImpl28PlaybackControlsElementsUnit new];
    playback.view = controls;
    UIViewController *headerUnit = [_TtC20NowPlaying_ModesImpl18HeaderElementsUnit new];
    headerUnit.view = header;
    _TtC19NowPlaying_ViewImpl24NowPlayingViewController *player = [_TtC19NowPlaying_ViewImpl24NowPlayingViewController new];
    player.view = host;
    _units = @[headerUnit, info, duration, floating, playback, footer, scrollUnit, background, player];
    _covers = covers;
    _plane = plane;
    _host = host;
    _background = background;
    if (getenv("HARNESS_OPENING")) {
        host.frame = CGRectMake(0, 0, W, 64);
        bottom.frame = CGRectMake(0, 64 - bottomHeight - 61.33, W, bottomHeight);
    }
    // The player has not been opened yet: its background plane is laid out only when it is.
    if ([scenario() isEqual:@"motion"] || [scenario() isEqual:@"motion-mirror"]) {
        [plane removeFromSuperview];
        _units = @[headerUnit, info, duration, floating, playback, footer, scrollUnit, player];
    }
    if (djHeaderUnit) _units = [_units arrayByAddingObjectsFromArray:@[djHeaderUnit, djFooterUnit]];
    [self start];
    CGRect noUnitStack = bottom.frame, nativeTilt = tilt.frame;
    void (^unitSpace)(BOOL) = ^(BOOL visible) {
        CGFloat delta = visible ? 40 : 0;
        CGFloat shift = delta - (bottom.frame.size.height - noUnitStack.size.height);
        bottom.frame = CGRectMake(noUnitStack.origin.x,noUnitStack.origin.y-delta,W,noUnitStack.size.height+delta);
        floatingView.frame = CGRectMake(0,0,W,visible ? 32 : 0);
        for (UIView *v in bottom.subviews) if (v != floatingView) v.center = CGPointMake(v.center.x,v.center.y+shift);
    };
    unitSpace(!ownerChip);
    if (emptyLine) SGKaraokeKeepLines(SGKaraokePlayingTrack(), nil);
    [self layOut];
    if ([scenario() isEqual:@"cancel-dismissal"]) {
        after(1, ^{
            SGRPlayerToggleLyrics();
            after(1, ^{
                UIView *lyrics = firstOfClass(host, @"SGRKaraokeView");
                UIScrollView *scroll = (id)firstOfClass(lyrics, @"UIScrollView");
                HARNESS_CHECK(lyrics.window && scroll && SGRPlayerLyricsOpen());
                [scroll.delegate scrollViewWillBeginDragging:scroll];
                scroll.contentOffset = CGPointMake(0, 67);
                void (^dismiss)(BOOL) = ^(BOOL cancel) {
                    HarnessDismissal *transition = [HarnessDismissal new];
                    transition.cancelled = cancel;
                    player.dismissal = transition;
                    [player viewWillDisappear:YES];
                    HARNESS_CHECK(covers.alpha == 1);
                    if (cancel) [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationWillResignActiveNotification object:nil];
                    if (transition.finish) transition.finish((id)transition);
                    player.dismissal = nil;
                    [player viewWillAppear:YES];
                    [self layOut];
                    if (cancel)
                        HARNESS_CHECK(SGRPlayerLyricsOpen() && lyrics.window && covers.alpha == 0 && scroll.contentOffset.y == 67);
                    else HARNESS_CHECK(!SGRPlayerLyricsOpen() && covers.alpha == 1);
                };
                dismiss(YES);
                [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationDidBecomeActiveNotification object:nil];
                HarnessDismissal *held = [HarnessDismissal new];
                runScript(@[@[^BOOL { return scroll.contentOffset.y == 0; }, ^{
                    dismiss(NO);
                    SGRPlayerToggleLyrics();
                    held.cancelled = YES;
                    player.dismissal = held;
                    [player viewWillDisappear:YES];
                    SGKaraokeKeepLines(SGKaraokePlayingTrack(), nil);
                    SGRHarnessSetTrack(@"spotify:track:instrumental", nil, NO);
                    SGRSetNowPlayingArtwork(artwork(), @"spotify:track:instrumental", SGRArtworkQualityHigh);
                }], @[^BOOL { return SGRPlayerLyricsNone(); }, ^{
                    HARNESS_CHECK(held.finish && SGRNowPlayingArtwork(NULL,NULL));
                    held.finish((id)held);
                    player.dismissal = nil;
                    [player viewWillAppear:YES];
                    [self layOut];
                    HARNESS_CHECK(!SGRPlayerLyricsOpen() && !lyrics.window && covers.alpha == 1);
                    NSLog(@"[harness] cancel-dismissal passed"); exit(0);
                }]], 0);
            });
        });
        return YES;
    }
    if ([scenario() isEqual:@"late-wide"]) {
        after(1, ^{
            HARNESS_CHECK(!SGRNowPlayingArtwork(NULL,NULL) && SGRPlayerIPadRegular(host) && !SGRPlayerTwoColumns());
            [host layoutIfNeeded];
            SGRSetNowPlayingArtwork(artwork(), SGURIString(SGPlayerState().track.URI), SGRArtworkQualityHigh);
            HARNESS_CHECK(SGRNowPlayingArtwork(NULL,NULL));
            [host layoutIfNeeded]; // Consume only an invalidation caused by artwork arrival.
            HARNESS_CHECK(SGRPlayerTwoColumns());
            [self expectFooterRowWithQueueStandIn:YES];
            HARNESS_CHECK(!self->_failures);
            NSLog(@"[harness] late-wide passed"); exit(0);
        });
        return YES;
    }
    if (previewTap) {
        dispatch_async(dispatch_get_main_queue(), ^{
            SGHarnessCheckPreviewTap(previewShell, player, ^{
                SGKaraokeKeepLines(@"harness", @[]);
                [floating viewDidLayoutSubviews];
            });
        });
        return YES;
    }
    __block CGRect beforeSwitch = CGRectNull;
    if (ownerChip) after(2, ^{
        beforeSwitch = SGRPlayerCoverFrameIn(host);
        unitSpace(YES);
        tilt.frame = CGRectMake(13,CGRectGetMinY(nativeTilt),319,319);
        chip.hidden = NO; [self layOut];
        if (!stripCheck) return;
        [tilt layoutIfNeeded];
        CGRect small = SGRPlayerCoverFrameIn(host);
        HARNESS_CHECK(SGRPlayerLyricLineOn() == emptyLine && chip.superview && beforeSwitch.size.width == 345 && small.size.width == 319);
        NSArray *(^rows)(void) = ^{
            NSMutableArray *frames = [NSMutableArray array];
            for (UIView *v in @[bottom, floatingView, titleElement, track, controls, footerView])
                [frames addObject:[NSValue valueWithCGRect:[host convertRect:v.bounds fromView:v]]];
            return frames;
        };
        NSArray *baseline = rows();
        UIVisualEffectView *material = (id)box(parent, UIVisualEffectView.class, CGRectMake(0,0,96,32), nil);
        material.effect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleDark];
        material.alpha = 0;
        SGSetEnabled(SGKeyHideVideoSwitch, YES);
        [floating viewDidLayoutSubviews];
        dispatch_async(dispatch_get_main_queue(), ^{
            [tilt layoutIfNeeded];
            CGRect full = SGRPlayerCoverFrameIn(host);
            HARNESS_CHECK(!chip.superview && floatingView.bounds.size.height == 32 && tilt.bounds.size.width == 319);
            HARNESS_CHECK(full.size.width == 345 && full.origin.x == 24 && fabs(full.origin.y-small.origin.y) < .01 &&
                          [baseline isEqual:rows()]);
            cover.frame = CGRectMake(0,0,319,319);
            HARNESS_CHECK(cover.bounds.size.width == 345);
            if (stripPreview) {
                // Spotify's other reason for narrowing the square: its own
                // preview, in this page's column, 8 pt below a 273 pt tilt.
                tilt.frame = CGRectMake(36,0,273,273);
                previewShell.frame = CGRectMake(0,281,345,64);
                [tilt layoutIfNeeded];
                CGRect art = SGRPlayerCoverFrameIn(host);
                HARNESS_CHECK(art.size.width == 273 && CGRectGetMaxY(art) <= CGRectGetMinY([host convertRect:previewShell.bounds fromView:previewShell]));
                previewShell.hidden = YES;
                dispatch_async(dispatch_get_main_queue(), ^{
                    [tilt layoutIfNeeded];
                    HARNESS_CHECK(SGRPlayerCoverFrameIn(host).size.width == 345);
                    previewShell.hidden = NO;
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [tilt layoutIfNeeded]; HARNESS_CHECK(SGRPlayerCoverFrameIn(host).size.width == 273);
                        NSLog(@"[harness] cover-strip-preview passed"); exit(0);
                    });
                });
                return;
            }
            // No player or floating-unit layout between changes. The cover
            // consumes an invalidation; the test never dirties it itself.
            material.alpha = 1;
            dispatch_async(dispatch_get_main_queue(), ^{
                [tilt layoutIfNeeded];
                HARNESS_CHECK(CGRectEqualToRect(SGRPlayerCoverFrameIn(host),small) && [baseline isEqual:rows()]);
                [material removeFromSuperview];
                dispatch_async(dispatch_get_main_queue(), ^{
                    [tilt layoutIfNeeded]; HARNESS_CHECK(CGRectEqualToRect(SGRPlayerCoverFrameIn(host),full));
                    [parent addSubview:material];
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [tilt layoutIfNeeded]; HARNESS_CHECK(CGRectEqualToRect(SGRPlayerCoverFrameIn(host),small));
                        NSLog(@"[harness] %@ passed", scenario()); exit(0);
                    });
                });
            });
        });
    });
    // Spotify lays its units out again as a track's elements arrive, which is what the redesign's
    // transforms and narrowed labels have to survive. The options scenario leaves layout to UIKit, so a switch
    // on the Player page is seen to reach the open player by itself; the header scenarios too, so the grabber is
    // seen to need no layout of the header.
    if (![scenario() isEqualToString:@"options"] && ![scenario() isEqualToString:@"renderer"] && ![scenario() hasPrefix:@"header"]
        && !stripCheck && ![scenario() isEqual:@"lyric-line-chip-live"] && !getenv("HARNESS_OPENING")) {
        [NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(NSTimer *t) { [self layOut]; }];
    }

    NSLog(@"[harness] lyrics available: %d", SGRPlayerLyricsAvailable());
    // With the lines up, the row that rose into them must still be Spotify's to touch, and the lines
    // themselves must take the tap that seeks.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIView *star = nil;
        for (UIView *v in infoInner.subviews) if ([v.accessibilityIdentifier isEqualToString:@"Components.UI.AddToButton"]) star = v;
        CGPoint onStar = [self.window convertPoint:CGPointMake(CGRectGetMidX(star.bounds), CGRectGetMidY(star.bounds)) fromView:star];
        CGPoint onTitle = [self.window convertPoint:CGPointMake(40, 12) fromView:titleElement];
        CGPoint onLines = CGPointMake(W / 2, H * 0.45);
        NSLog(@"[harness] hit on the star: %@", NSStringFromClass([self.window hitTest:onStar withEvent:nil].class));
        NSLog(@"[harness] hit on the title: %@", NSStringFromClass([self.window hitTest:onTitle withEvent:nil].class));
        NSLog(@"[harness] hit on the lines: %@", NSStringFromClass([self.window hitTest:onLines withEvent:nil].class));
    });
    if ([scenario() isEqual:@"artwork-unowned"]) after(2, ^{
        cover.frame = CGRectMake(0,0,264,264);
        HARNESS_CHECK(CGRectGetWidth(cover.frame) == 264);
        NSLog(@"[harness] line off passed"); exit(0);
    });
    else if (getenv("HARNESS_OPENING")) [self runOpeningChecks];
    else if ([scenario() isEqualToString:@"adaptive"]) [self runAdaptiveChecks];
    else if ([scenario() isEqualToString:@"artwork"]) [self runArtworkChecks];
    else if ([scenario() isEqualToString:@"look"]) [self runLook];
    else if ([scenario() isEqualToString:@"scroll"]) [self runScrollChecks];
    else if ([scenario() isEqualToString:@"controls"]) [self runControlsChecks];
    else if ([scenario() isEqualToString:@"landscape-owner"]) [self runLandscapeOwner];
    else if ([scenario() isEqualToString:@"landscape"]) [self runLandscape];
    else if ([scenario() isEqual:@"motion"] || [scenario() isEqual:@"motion-mirror"]) [self runMotionChecks];
    else if ([scenario() hasPrefix:@"lyric-line"]) after(4, ^{
        UIView *line = firstOfClass(host, @"SGRLyricLineView");
        UILabel *words = (UILabel *)line.subviews.firstObject;
        UIView *title = SGRFindByIdentifier(host, @"now-playing-title-label", NULL);
        CGRect text = [host convertRect:words.bounds fromView:words];
        CGRect row = [host convertRect:title.bounds fromView:title];
        BOOL handover = [scenario() isEqualToString:@"lyric-line-switch"];
        BOOL clip = handover || [scenario() isEqualToString:@"lyric-line-clip"] || [scenario() isEqual:@"lyric-line-chip-clip"];
        NSLog(@"[harness] lyric-line font %.1f frame %@ title %@ room %@ clip %d", words.font.pointSize,
              NSStringFromCGRect(text), NSStringFromCGRect(row), [line valueForKey:@"room"], SGRPlayerMotionShowing());
        // Leave the settled frame on screen for simctl io screenshot.
        after(2, ^{
            CGFloat native = 19.1;
            if ([scenario() isEqual:@"lyric-line-long"]) {
                // The first clock tick enters with a known slot but no view frame yet.
                UIView *opening = [[line.class alloc] initWithFrame:CGRectZero];
                [opening setValue:[line valueForKey:@"slot"] forKey:@"slot"];
                [opening setValue:[line valueForKey:@"room"] forKey:@"room"];
                [host addSubview:opening];
                UILabel *first = (UILabel *)opening.subviews.firstObject;
                HARNESS_CHECK(opening.userInteractionEnabled && first.text.length && first.text.length < opening.accessibilityLabel.length);
                [opening removeFromSuperview];
                HARNESS_CHECK(line.userInteractionEnabled && words.text.length && words.text.length < line.accessibilityLabel.length);
                HARNESS_CHECK(fabs(words.font.pointSize - native) < .05 &&
                    [words textRectForBounds:words.bounds limitedToNumberOfLines:2].size.height > words.font.lineHeight * 1.5);
                NSArray<SGRLyricPortion *> *parts = [line valueForKey:@"portions"];
                HARNESS_CHECK(parts.count >= 2);
                SGRLyricPortion *penultimate = parts[parts.count - 2], *last = parts.lastObject;
                SGRHarnessPlayFrom(last.start);
                [line performSelector:@selector(tick)];
                HARNESS_CHECK([words.text isEqual:last.text]);
                // Jump back before the last boundary; cross it exactly when the label gets the preceding words.
                extern NSInteger (^SGRHarnessPositionDuringPlacement)(void);
                __block BOOL crossed = NO;
                SGRHarnessPositionDuringPlacement = ^NSInteger{
                    if ([words.text isEqual:penultimate.text]) crossed = YES;
                    return crossed ? last.start : last.start - 1;
                };
                [line performSelector:@selector(tick)];
                HARNESS_CHECK([words.text isEqual:penultimate.text]);
                NSTimer *next = [line valueForKey:@"timer"];
                HARNESS_CHECK(next.valid);
                [next fire];
                HARNESS_CHECK([words.text isEqual:last.text] && ![[line valueForKey:@"timer"] isValid]);
                SGRHarnessPositionDuringPlacement = nil;
                NSLog(@"[harness] lyric-line passed (first long lyric, final portion crossed during placement)");
                exit(0);
            }
            if ([scenario() isEqual:@"lyric-line-vo"]) {
                HARNESS_CHECK([line accessibilityActivate]);
                after(.5, ^{
                    HARNESS_CHECK(SGRPlayerLyricsOpen());
                    NSLog(@"[harness] lyric-line passed (VoiceOver)");
                    exit(0);
                });
                return;
            }
            HARNESS_CHECK(fabs(words.font.pointSize - native) < 0.05 &&
                          (words.font.fontDescriptor.symbolicTraits & UIFontDescriptorTraitBold));
            CGRect (^slotFor)(CGFloat, CGFloat, BOOL) = ^CGRect(CGFloat end, CGFloat points, BOOL translation) {
                CGFloat rowHeight = ceil([UIFont boldSystemFontOfSize:points].lineHeight);
                CGFloat reserve = translation ? ceil([UIFont systemFontOfSize:round(.8 * points)].lineHeight) : 0;
                return CGRectMake(row.origin.x, end - 8 - 2 * rowHeight - reserve, host.bounds.size.width - 2 * row.origin.x, 2 * rowHeight + reserve);
            };
            CGRect preview = slotFor(CGRectGetMinY(row), native, NO);
            if (ownerChip) {
                BOOL field = [scenario() hasSuffix:@"-clip"];
                HARNESS_CHECK(field == SGRPlayerMotionShowing());
                OSLogStore *store = [OSLogStore storeWithScope:OSLogStoreCurrentProcessIdentifier error:nil];
                NSPredicate *p = [NSPredicate predicateWithFormat:@"composedMessage BEGINSWITH '[spotifyglass] lyrics unit:'"];
                NSMutableString *snapshot = [NSMutableString string];
                NSUInteger parts = 0;
                for (OSLogEntry *e in [store entriesEnumeratorWithOptions:0 position:nil predicate:p error:nil]) {
                    NSString *msg = e.composedMessage;
                    if ([msg containsString:@"lyrics unit: 1 "]) { [snapshot setString:@""]; parts = 0; }
                    [snapshot appendString:[msg substringFromIndex:@"[spotifyglass] lyrics unit: 1 ".length]];
                    parts++;
                }
                HARNESS_CHECK(parts <= 4 && [snapshot containsString:@"top=442"] && [snapshot containsString:@"titleTop="] &&
                    [snapshot containsString:@"stack={{0, 442}"] && [snapshot containsString:field ? @"normalSide=0" : @"normalSide=345"] &&
                    [snapshot containsString:@"MockEncoreButton"] && ![snapshot containsString:@"[capped]"]);
                __block BOOL anchored = YES, hiddenFits = YES;
                CGFloat (^noLineTop)(void) = ^{
                    NSArray *kept = SGKaraokeLinesForTrack(SGKaraokePlayingTrack());
                    SGKaraokeKeepLines(@"harness",nil); [floating viewDidLayoutSubviews];
                    CGRect unreserved = SGRPlayerCoverFrameIn(host);
                    HARNESS_CHECK(unreserved.size.width == 319);
                    SGKaraokeKeepLines(@"harness",kept); [floating viewDidLayoutSubviews];
                    return CGRectGetMinY(unreserved);
                };
                CGFloat playbackTop = noLineTop();
                for (NSNumber *pair in field ? @[@NO] : @[@YES,@NO]) {
                    SGRSetLyricsTextShown(SGRLyricsTextTranslation,pair.boolValue);
                    [floating viewDidLayoutSubviews];
                    CGRect art = SGRPlayerCoverFrameIn(host);
                    NSLog(@"[harness] owner %@ pair=%@ art=%@ line=%@", scenario(),pair,NSStringFromCGRect(art),NSStringFromCGRect(line.frame));
                    HARNESS_CHECK(line.userInteractionEnabled && fabs(CGRectGetMaxY(line.frame)-434)<.01);
                    if (!field) HARNESS_CHECK(art.size.width < 319 && art.size.width >= 230 &&
                        fabs(CGRectGetMaxY(art)+8-CGRectGetMinY(line.frame))<.01);
                    if (!field) anchored &= fabs(art.origin.y-playbackTop)<.01;
                }
                if (!field) {
                    UIView *live = box(host,UIView.class,CGRectMake(0,playbackTop,W,12),nil);
                    SGRPlayerCoverUnderRow(live,YES,host);
                    [tilt layoutIfNeeded];
                    CGFloat liveTop = noLineTop();
                    anchored &= liveTop > playbackTop && fabs(SGRPlayerCoverFrameIn(host).origin.y-liveTop)<.01;
                    SGRPlayerCoverUnderRow(live,NO,host); [live removeFromSuperview]; [tilt layoutIfNeeded];
                }
                floatingView.alpha = 0; [floating viewDidLayoutSubviews];
                HARNESS_CHECK(CGRectEqualToRect(line.frame,preview));
                // VideoSwitch.x removes only the identified button, not its wrapper, unit or native tilt.
                SGSetEnabled(SGKeyHideVideoSwitch, YES); [floating viewDidLayoutSubviews];
                HARNESS_CHECK(!chip.superview); floatingView.alpha = 1;
                for (NSNumber *pair in @[@YES,@NO]) {
                    SGRSetLyricsTextShown(SGRLyricsTextTranslation,pair.boolValue); [floating viewDidLayoutSubviews];
                    CGRect art = SGRPlayerCoverFrameIn(host);
                    NSLog(@"[harness] removed pair=%@ art=%@ line=%@",pair,NSStringFromCGRect(art),NSStringFromCGRect(line.frame));
                    hiddenFits &= line.userInteractionEnabled && CGRectEqualToRect(line.frame,slotFor(row.origin.y,native,pair.boolValue));
                    if (!field) hiddenFits &= fabs(art.origin.y-playbackTop)<.01 && fabs(CGRectGetMaxY(art)+8-line.frame.origin.y)<.01;
                }
                tilt.frame = nativeTilt; [tilt setNeedsLayout]; [tilt layoutIfNeeded]; unitSpace(NO); [self layOut];
                NSLog(@"[harness] collapsed art=%@ line=%@",NSStringFromCGRect(SGRPlayerCoverFrameIn(host)),NSStringFromCGRect(line.frame));
                HARNESS_CHECK(CGRectEqualToRect(line.frame,preview));
                if (!field) HARNESS_CHECK(CGRectEqualToRect(SGRPlayerCoverFrameIn(host),beforeSwitch));
                NSLog(@"[harness] anchored=%d retained-strip=%d",anchored,hiddenFits);
                HARNESS_CHECK(anchored && hiddenFits);
                NSLog(@"[harness] owner chip passed"); exit(0);
            }
            if ([scenario() isEqual:@"lyric-line-ownership"]) {
                __block NSInteger failures = 0;
                void (^check)(BOOL, NSString *) = ^(BOOL ok, NSString *what) {
                    NSLog(@"[harness] %@: %@", what, ok ? @"PASS" : @"FAIL");
                    if (!ok) failures++;
                };
                CGRect originalFloating = floatingView.frame;
                CGFloat artEnd = CGRectGetMaxY(SGRPlayerCoverFrameIn(host));
                CGRect target = CGRectMake(0, artEnd - 12, W, 32);
                floatingView.frame = [bottom convertRect:target fromView:host];
                chip.hidden = NO; [floating viewDidLayoutSubviews];
                check(fabs(CGRectGetMaxY(line.frame) - (target.origin.y - 8)) < .01, @"pill above reserved foot");
                chip.accessibilityIdentifier = SGVideoSwitchIdentifier;
                chip.backgroundColor = UIColor.clearColor;
                chipLabel.layer.mask = [CALayer layer]; [floating viewDidLayoutSubviews];
                check(fabs(CGRectGetMaxY(line.frame) - (target.origin.y-8)) < .01, @"identified wrapper owns its outer frame");
                chip.accessibilityIdentifier = nil; [floating viewDidLayoutSubviews];
                check(CGRectEqualToRect(line.frame, preview), @"anonymous wrapper with masked child");
                chipLabel.hidden = YES; chip.accessibilityIdentifier = nil; chip.layer.cornerRadius = 0;
                UIImageView *img = [[UIImageView alloc] initWithImage:picture]; img.frame = CGRectInset(chip.bounds,4,4);
                [chip addSubview:img]; [floating viewDidLayoutSubviews];
                check(fabs(CGRectGetMaxY(line.frame) - (target.origin.y+4-8)) < .01, @"generic painted image");
                chip.hidden = YES; floatingView.frame = originalFloating;
                CGRect originalColumn = inner.frame;
                inner.frame = CGRectInset(originalColumn,32,0); [floating viewDidLayoutSubviews];
                check(![[line valueForKey:@"normalSide"] doubleValue], @"narrow artwork column");
                CGPoint homeBottom = bottom.center;
                previewShell.frame = CGRectMake(0,0,coverSide,64);
                CGFloat coverBottom = CGRectGetMaxY(SGRPlayerCoverFrameIn(host));
                bottom.center = CGPointMake(homeBottom.x, homeBottom.y + coverBottom + 46 -
                                           CGRectGetMinY([host convertRect:title.bounds fromView:title]));
                [floating viewDidLayoutSubviews];
                BOOL steady = YES;
                for (NSNumber *position in @[@1000,@62000,@1000]) {
                    SGRHarnessPlayFrom(position.integerValue); [line performSelector:@selector(tick)];
                    steady &= previewShell.layer.mask != nil && line.userInteractionEnabled &&
                              words.numberOfLines == 1 && words.text.length > 0;
                    if (position.integerValue == 62000) steady &= words.text.length < line.accessibilityLabel.length;
                }
                check(steady, @"one-row fallback keeps preview masked across lyrics");
                bottom.center = homeBottom;
                inner.frame = originalColumn;
                CGPoint originalBottom = bottom.center;
                previewShell.frame = CGRectMake(0,0,coverSide,64);
                bottom.center = CGPointMake(originalBottom.x, originalBottom.y-270);
                [floating viewDidLayoutSubviews];
                check(!previewShell.layer.mask && !line.userInteractionEnabled, @"no-fit preview returned");
                bottom.center = originalBottom; [floating viewDidLayoutSubviews];
                UIView *second = box(inner,tilt.class,CGRectMake(W,0,264,264),nil);
                UIView *secondBox = box(second,UIView.class,second.bounds,nil);
                UIView *proxy = box(secondBox,cover.superview.superview.class,secondBox.bounds,nil);
                UIView *holder = box(proxy,cover.superview.class,proxy.bounds,@"Encore.ImageView");
                UIImageView *bitmap = [UIImageView new]; [holder addSubview:bitmap];
                [second layoutSubviews]; bitmap.frame = CGRectMake(0,0,264,264);
                bitmap.frame = CGRectInset(bitmap.frame, 8, 8);
                check(bitmap.frame.size.width == 248, @"prefetched bitmap write accepted");
                UIView *nextColumn = box(band,UIView.class,CGRectOffset(inner.frame,W,0),nil);
                [nextColumn addSubview:second]; second.center = tilt.center;
                box(nextColumn,previewShell.class,previewShell.frame,nil);
                bottom.center = CGPointMake(originalBottom.x, originalBottom.y-45);
                [floating viewDidLayoutSubviews];
                CGRect outgoing = coverElement.frame, incoming = secondBox.frame;
                testCoverDrag = YES;
                BOOL unchanged = YES;
                for (NSNumber *delta in @[@-3,@3,@-2,@2]) {
                    covers.contentOffset = CGPointMake(W/2 + delta.doubleValue,0);
                    [line performSelector:@selector(tick)];
                    unchanged &= CGRectEqualToRect(coverElement.frame,outgoing) && CGRectEqualToRect(secondBox.frame,incoming);
                }
                check(unchanged, @"midpoint drag keeps both cover frames");
                testCoverDrag = NO; covers.contentOffset = CGPointMake(W,0);
                [line performSelector:@selector(tick)];
                check(secondBox.bounds.size.width > 264 && coverElement.bounds.size.width == tilt.bounds.size.width,
                      @"settling the pager transfers the reservation");
                covers.contentOffset = CGPointZero;
                [inner addSubview:second]; bottom.center = originalBottom;
                second.center = tilt.center; tilt.hidden = YES;
                [line performSelector:@selector(tick)];
                check(secondBox.bounds.size.width > 264 && coverElement.bounds.size.width == tilt.bounds.size.width,
                      @"clock transfers cover reservation");
                cover.frame = CGRectMake(0,0,264,264);
                check(cover.frame.size.width == 264, @"outgoing bitmap write accepted");
                HARNESS_CHECK(!failures); exit(0);
            }
            if ([scenario() isEqual:@"lyric-line-compact"]) {
                NSArray<SGKaraokeLine *> *kept = SGKaraokeLinesForTrack(SGKaraokePlayingTrack());
                void (^checkPicture)(void) = ^{
                    for (UIView *v = cover; v != coverElement; v = v.superview) {
                        HARNESS_CHECK(v && CGRectEqualToRect(v.frame, v.superview.bounds));
                    }
                };
                for (NSNumber *show in @[@NO,@YES]) {
                    SGRSetLyricsTextShown(SGRLyricsTextTranslation, show.boolValue);
                    [floating viewDidLayoutSubviews];
                    CGRect slot = slotFor(row.origin.y, native, show.boolValue);
                    CGRect art = SGRPlayerCoverFrameIn(host);
                    // A late cell pass can put the bitmap back at the native preview size
                    // without changing either the proxy or the Encore holder's bounds.
                    cover.frame = CGRectMake(0, 0, 264, 264);
                    checkPicture(); // No later parent layout is promised.
                    [tilt layoutSubviews];
                    checkPicture();
                    HARNESS_CHECK(CGRectEqualToRect(line.frame, slot));
                    HARNESS_CHECK(fabs(art.size.width - MIN(345, slot.origin.y - 8 - art.origin.y)) < .5);
                    NSString *old = [kept.firstObject translation];
                    [kept.firstObject setTranslation:nil];
                    [NSNotificationCenter.defaultCenter postNotificationName:SGKaraokeLinesKeptNotification object:nil];
                    HARNESS_CHECK(CGRectEqualToRect(art, SGRPlayerCoverFrameIn(host)) && CGRectEqualToRect(slot, line.frame));
                    [kept.firstObject setTranslation:old];
                    NSLog(@"[harness] compact translation %@ slot %@ art %@",show,NSStringFromCGRect(slot),NSStringFromCGRect(art));
                }
                SGRSetLyricsTextShown(SGRLyricsTextTranslation, NO);
                CGPoint saved = bottom.center;
                // Shorten the space between artwork and title without moving the live header.
                CGFloat floor = 230, naturalTop = CGRectGetMinY(SGRPlayerCoverFrameIn(host));
                SGRSetLyricsTextShown(SGRLyricsTextTranslation, YES);
                bottom.center = CGPointMake(saved.x, saved.y + 450 - row.origin.y);
                for (NSNumber *small in @[@NO, @YES, @NO]) {
                    SGRSetPlayerLineSmall(small.boolValue);
                    HARNESS_CHECK(line.frame.size.height == (small.boolValue ? 59 : 64));
                    HARNESS_CHECK(fabs(SGRPlayerCoverFrameIn(host).size.width -
                                       (450 - naturalTop - 16 - (small.boolValue ? 59 : 64))) < .5);
                }
                for (NSNumber *rows in @[@2,@1,@0]) {
                    CGFloat titleY = naturalTop + 16 + floor + rows.intValue * 23 + 1;
                    bottom.center = CGPointMake(saved.x,saved.y + titleY-row.origin.y);
                    [floating viewDidLayoutSubviews]; [line layoutIfNeeded];
                    HARNESS_CHECK(line.userInteractionEnabled == (rows.intValue != 0));
                    checkPicture();
                    if (rows.intValue) HARNESS_CHECK(line.frame.size.height == rows.intValue * 23 && !line.accessibilityValue);
                }
                bottom.center = saved;
                SGRSetLyricsTextShown(SGRLyricsTextTranslation, NO);
                SGKaraokeKeepLines(@"harness",nil); [floating viewDidLayoutSubviews];
                HARNESS_CHECK(!line.userInteractionEnabled && SGRPlayerCoverFrameIn(host).size.width == tilt.bounds.size.width);
                checkPicture();
                SGKaraokeKeepLines(@"harness",kept); [floating viewDidLayoutSubviews];
                HARNESS_CHECK(line.userInteractionEnabled && CGRectEqualToRect(line.frame,preview));
                checkPicture();
                SGRSetPlayerLineSmall(YES);
                chip.hidden = NO; [floating viewDidLayoutSubviews]; checkPicture();
                chip.hidden = YES; [floating viewDidLayoutSubviews]; checkPicture();
                SGRPlayerToggleLyrics(); SGRPlayerToggleLyrics();
                [floating viewDidLayoutSubviews]; checkPicture();
                NSLog(@"[harness] lyric-line passed (compact)");
                exit(0);
            }
            BOOL dismissRecord = [scenario() isEqual:@"lyric-line-chip-dismiss"];
            if (dismissRecord || [scenario() isEqual:@"lyric-line-chip-record"]) {
                NSArray *(^records)(void) = ^{
                    OSLogStore *store = [OSLogStore storeWithScope:OSLogStoreCurrentProcessIdentifier error:nil];
                    NSMutableArray *messages = [NSMutableArray array];
                    NSPredicate *p = [NSPredicate predicateWithFormat:@"composedMessage BEGINSWITH '[spotifyglass] lyrics unit:'"];
                    for (OSLogEntry *e in [store entriesEnumeratorWithOptions:0 position:nil predicate:p error:nil])
                        [messages addObject:e.composedMessage];
                    return messages.copy;
                };
                if (dismissRecord) {
                    floatingView.center = CGPointMake(floatingView.center.x + 37, floatingView.center.y);
                    NSString *finalFrame = NSStringFromCGRect([host convertRect:floatingView.bounds fromView:floatingView]);
                    [floating viewDidLayoutSubviews];
                    [host removeFromSuperview];
                    HARNESS_CHECK(!host.window && [[records() componentsJoinedByString:@"\n"] containsString:finalFrame]);
                    NSLog(@"[harness] pending record survived dismissal"); exit(0);
                }
                CGRect plain = line.frame;
                CALayer *ink = [CALayer layer]; ink.frame = chip.frame; ink.backgroundColor = UIColor.blackColor.CGColor;
                [floatingView.layer addSublayer:ink];
                after(1.4, ^{
                    BOOL raised = fabs(CGRectGetMaxY(line.frame) - ([host convertRect:ink.frame fromView:floatingView].origin.y - 8)) < .01;
                    // Same winner and top, different backing structure, without a view layout.
                    CAGradientLayer *extra = [CAGradientLayer layer]; extra.frame = ink.frame;
                    [floatingView.layer addSublayer:extra];
                    [line performSelector:@selector(tick)];
                    [extra removeFromSuperlayer]; // No layout can observe this transient backing layer.
                    after(1.4, ^{
                        NSArray *before = records();
                        BOOL tick = raised && [[before componentsJoinedByString:@"\n"] containsString:@"CAGradientLayer"];
                        for (int i = 0; i < 100; i++) {
                            floatingView.center = CGPointMake(floatingView.center.x + .25, floatingView.center.y);
                            [floating viewDidLayoutSubviews];
                        }
                        after(1.4, ^{
                            NSArray *moved = records();
                            NSString *finalFrame = NSStringFromCGRect([host convertRect:floatingView.bounds fromView:floatingView]);
                            BOOL bounded = moved.count - before.count <= 2 && [moved.lastObject containsString:finalFrame];
                            [ink removeFromSuperlayer];
                            chip.hidden = NO; chip.accessibilityIdentifier = SGVideoSwitchIdentifier;
                            CAShapeLayer *mask = [CAShapeLayer layer]; mask.frame = chip.bounds;
                            CGRect outside = CGRectMake(240,2,16,12);
                            mask.path = [UIBezierPath bezierPathWithRect:outside].CGPath; chip.layer.mask = mask;
                            [floating viewDidLayoutSubviews];
                            after(1.4, ^{
                                BOOL masked = CGRectEqualToRect(line.frame,plain) && [records().lastObject containsString:
                                    NSStringFromCGRect([host convertRect:outside fromView:chip])];
                                NSLog(@"[harness] record: tick=%d coalesced=%d mask=%d",tick,bounded,masked);
                                HARNESS_CHECK(tick && bounded && masked); exit(0);
                            });
                        });
                    });
                });
                return;
            }
            if ([scenario() isEqual:@"lyric-line-chip-live"]) {
                HARNESS_CHECK(CGRectEqualToRect(text, preview));
                SGRHarnessSetTrack(@"spotify:track:harness", nil, YES);
                HARNESS_CHECK(![[line valueForKey:@"timer"] isValid]);
                SGRHarnessPlayFrom(61000);
                SPTPlayerState *paused = SGPlayerState();
                [paused setValue:@61 forKey:@"positionAsOfTimestamp"];
                [(id<SGPlayerStateObserver>)line playerStateDidReport:paused];
                HARNESS_CHECK([words.text isEqual:@"Second verse"]);
                chip.alpha = 1;
                after(1, ^{
                    CGRect pill = [host convertRect:chip.bounds fromView:chip];
                    CGRect moved = [host convertRect:words.bounds fromView:words];
                    HARNESS_CHECK(line.userInteractionEnabled && CGRectEqualToRect(moved, slotFor(pill.origin.y,native,NO)));
                    chip.center = CGPointMake(chip.center.x, chip.center.y + 6);
                    after(1, ^{
                        HARNESS_CHECK(CGRectEqualToRect([host convertRect:words.bounds fromView:words], CGRectOffset(moved, 0, 6)));
                        chip.hidden = YES;
                        after(1, ^{
                            HARNESS_CHECK(CGRectEqualToRect([host convertRect:words.bounds fromView:words], preview));
                            SGRHarnessPlayFrom(1000);
                            SGRHarnessSetTrack(@"spotify:track:harness", nil, NO);
                            HARNESS_CHECK([[line valueForKey:@"timer"] isValid]);
                            if (getenv("HARNESS_QUEUE_SHEET")) {
                                SGRPlayerShowQueue(host);
                                runScript(@[
                                    @[^BOOL { return root.presentedViewController && !root.presentedViewController.transitionCoordinator; }, ^{
                                        root.presentedViewController.sheetPresentationController.selectedDetentIdentifier = UISheetPresentationControllerDetentIdentifierLarge;
                                    }],
                                    @[^BOOL {
                                        UIView *sheet = root.presentedViewController.view;
                                        return CGRectContainsRect([sheet convertRect:sheet.bounds toView:host], [line convertRect:line.bounds toView:host]);
                                    }, ^{
                                        HARNESS_CHECK(![[line valueForKey:@"timer"] isValid]);
                                        SGRHarnessPlayFrom(61000);
                                        [root dismissViewControllerAnimated:NO completion:^{
                                            HARNESS_CHECK(line.userInteractionEnabled && [words.text isEqual:@"Second verse"]);
                                            SGRHarnessFrameCheck *first = [SGRHarnessFrameCheck new];
                                            __block BOOL sought = NO;
                                            first.check = ^BOOL{
                                                BOOL dissolving = NO;
                                                for (NSString *key in words.layer.animationKeys)
                                                    if ([[words.layer animationForKey:key] isKindOfClass:CATransition.class]) dissolving = YES;
                                                if (sought) {
                                                    HARNESS_CHECK(dissolving && ![words.text isEqual:@"Second verse"]);
                                                    NSLog(@"[harness] queue-sheet passed"); exit(0);
                                                }
                                                HARNESS_CHECK(words.layer.presentationLayer && [words.text isEqual:@"Second verse"]);
                                                if (dissolving) HARNESS_FAIL(@"first uncovered lyric frame still dissolving from the previous words");
                                                sought = YES;
                                                SGRHarnessPlayFrom(1000);
                                                [(id<SGPlayerStateObserver>)line playerStateDidChange:SGPlayerState()];
                                                return NO;
                                            };
                                            CADisplayLink *frame = [CADisplayLink displayLinkWithTarget:first selector:@selector(frame:)];
                                            [frame addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
                                        }];
                                    }]
                                ], 0);
                                return;
                            }
                            SGRPlayerToggleLyrics();
                            after(1, ^{
                                HARNESS_CHECK(SGRPlayerLyricsOpen() && ![[line valueForKey:@"timer"] isValid]);
                                SGRHarnessPlayFrom(61000);
                                __block BOOL sawReturn = NO;
                                SGRHarnessFrameCheck *first = [SGRHarnessFrameCheck new];
                                first.check = ^BOOL{
                                    if (SGRPlayerLyricsOpen() || covers.alpha <= .01) return NO;
                                    HARNESS_CHECK(line.userInteractionEnabled && [words.text isEqual:@"Second verse"]);
                                    sawReturn = YES;
                                    return YES;
                                };
                                CADisplayLink *frame = [CADisplayLink displayLinkWithTarget:first selector:@selector(frame:)];
                                [frame addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
                                SGRPlayerToggleLyrics();
                                after(1, ^{
                                    HARNESS_CHECK(sawReturn);
                                    SGKaraokeKeepLines(@"harness", nil);
                                    [NSNotificationCenter.defaultCenter postNotificationName:SGKaraokeLinesKeptNotification object:@"harness"];
                                    HARNESS_CHECK(!line.userInteractionEnabled && ![[line valueForKey:@"timer"] isValid]);
                                    NSLog(@"[harness] lyric-line passed (idle clock, seek, live chip, lyrics handover)");
                                    exit(0);
                                });
                            });
                        });
                    });
                });
                return;
            }
            if ([scenario() hasPrefix:@"lyric-line-chip"]) {
                HARNESS_CHECK(CGRectEqualToRect(text, preview) && clip == SGRPlayerMotionShowing());
                CGRect pill = [host convertRect:chip.bounds fromView:chip];
                HARNESS_CHECK(pill.size.height == 32);
                void (^layout)(void) = ^{ [floating viewDidLayoutSubviews]; [line layoutIfNeeded]; };
                CGPoint original = band.center;
                band.center = CGPointMake(original.x, original.y - 80);
                // Model the public tree of a compositor-hosted material: neither the backing
                // layer nor the hosted label exposes the pixels as a UIKit image or text.
                UIView *material = box(floatingView,UIView.class,chip.frame,SGVideoSwitchIdentifier);
                material.layer.cornerRadius = 16;
                CALayer *backdrop = [CALayer layer]; backdrop.frame = material.bounds;
                [material.layer addSublayer:backdrop];
                UIView *hostedLabel = box(material,UIView.class,CGRectInset(material.bounds,8,4),nil);
                hostedLabel.accessibilityLabel = @"Private hosted words";
                layout();
                HARNESS_CHECK(fabs(CGRectGetMaxY(line.frame) - (pill.origin.y - 8)) < .01);
                [material removeFromSuperview]; layout();
                if (!clip) {
                    chip.hidden = NO;
                    CGRect home = chip.frame;
                    CALayer *emptyMask = [CALayer layer];
                    emptyMask.frame = chip.bounds;
                    chip.layer.mask = emptyMask;
                    layout();
                    HARNESS_CHECK(CGRectEqualToRect([host convertRect:words.bounds fromView:words], text));
                    chip.layer.mask = nil;
                    chip.layer.opacity = 0;
                    layout();
                    HARNESS_CHECK(CGRectEqualToRect([host convertRect:words.bounds fromView:words], text));
                    chip.layer.opacity = 1;
                    chip.transform = CGAffineTransformMakeScale(0, 1);
                    layout();
                    HARNESS_CHECK(CGRectEqualToRect([host convertRect:words.bounds fromView:words], text));
                    chip.transform = CGAffineTransformIdentity;
                    chip.frame = CGRectOffset(home, 0, -100);
                    layout();
                    HARNESS_CHECK(CGRectEqualToRect([host convertRect:words.bounds fromView:words], text));
                    chip.frame = (CGRect){home.origin, CGSizeZero};
                    layout();
                    HARNESS_CHECK(CGRectEqualToRect([host convertRect:words.bounds fromView:words], text));
                    chip.frame = home;
                    chip.hidden = YES;
                }
                for (NSNumber *large in @[@NO, @YES]) {
                    SGRSetPlayerLineSmall(!large.boolValue);
                    for (NSNumber *pair in @[@NO, @YES]) {
                        SGRSetLyricsTextShown(SGRLyricsTextTranslation, pair.boolValue);
                        chip.hidden = YES;
                        layout();
                        CGRect before = [host convertRect:words.bounds fromView:words];
                        HARNESS_CHECK(CGRectEqualToRect(line.frame, slotFor(row.origin.y, words.font.pointSize, pair.boolValue)));
                        chip.hidden = NO;
                        layout();
                        UILabel *translation = (UILabel *)line.subviews[1];
                        CGRect ink = [host convertRect:[words textRectForBounds:words.bounds limitedToNumberOfLines:2] fromView:words];
                        // textRectForBounds supplies the measured size, not UILabel's vertical centering.
                        ink.origin.y = CGRectGetMidY([host convertRect:words.bounds fromView:words]) - ink.size.height / 2;
                        CGRect block = pair.boolValue ? CGRectUnion(ink, [host convertRect:translation.bounds fromView:translation]) : ink;
                        HARNESS_CHECK(line.userInteractionEnabled && (line.accessibilityValue != nil) == pair.boolValue);
                        HARNESS_CHECK((ink.size.height > words.font.lineHeight * 1.5) == large.boolValue);
                        HARNESS_CHECK(CGRectEqualToRect(line.frame, slotFor(pill.origin.y,words.font.pointSize,pair.boolValue)));
                        HARNESS_CHECK(CGRectGetMaxY(block) <= CGRectGetMinY(pill) - 7.5);
                        CGRect moved = [host convertRect:words.bounds fromView:words];
                        HARNESS_CHECK(moved.origin.x == before.origin.x && moved.size.width == before.size.width);
                        HARNESS_CHECK(CGRectGetMaxY(line.frame) <= CGRectGetMinY(pill));
                        if (clip) HARNESS_CHECK(CGRectGetMinY(SGRPlayerVisibleClipLineIn(host)) <= CGRectGetMinY(ink));
                        NSLog(@"[harness] chip %@ large %@ pair %@ slot %@ -> %@ block %@ chip %@", scenario(), large, pair,
                              NSStringFromCGRect(before), NSStringFromCGRect(moved), NSStringFromCGRect(block), NSStringFromCGRect(pill));
                        chip.hidden = YES;
                        layout();
                        HARNESS_CHECK(CGRectEqualToRect([host convertRect:words.bounds fromView:words], before));
                    }
                }
                SGRSetLyricsTextShown(SGRLyricsTextTranslation, NO);
                SGRSetPlayerLineSmall(NO);
                NSLog(@"[harness] lyric-line passed (chip)");
                exit(0);
            }
            HARNESS_CHECK(line.userInteractionEnabled && [words.text isEqual:@"한순간이였지"] && clip == SGRPlayerMotionShowing());
            HARNESS_CHECK(CGRectEqualToRect(text, preview) && words.textAlignment == NSTextAlignmentLeft);
            CGPoint savedTitle = title.center;
            CGRect savedArt = SGRPlayerCoverFrameIn(host);
            title.center = CGPointMake(savedTitle.x + 8, savedTitle.y);
            [floating viewDidLayoutSubviews]; [line layoutIfNeeded];
            CGRect shifted = [host convertRect:words.bounds fromView:words];
            HARNESS_CHECK(shifted.origin.x == row.origin.x + 8 && shifted.size.width == text.size.width - 16);
            HARNESS_CHECK(CGRectEqualToRect(savedArt, SGRPlayerCoverFrameIn(host)));
            title.center = savedTitle; [floating viewDidLayoutSubviews];
            HARNESS_CHECK(CGColorEqualToColor(words.textColor.CGColor, UIColor.whiteColor.CGColor));
            if (handover) {
                SGRSetPlayerBackground(SGRPlayerBackgroundFluid);
                SGRPlayerBackgroundDidChange();
                [host layoutIfNeeded];
                HARNESS_CHECK(!SGRPlayerMotionShowing() && line.userInteractionEnabled);
                HARNESS_CHECK(CGRectEqualToRect(text, [host convertRect:words.bounds fromView:words]));
                SGRSetPlayerBackground(SGRPlayerBackgroundAnimated);
                SGRPlayerBackgroundDidChange();
                after(2, ^{
                    HARNESS_CHECK(SGRPlayerMotionShowing() && line.userInteractionEnabled);
                    HARNESS_CHECK(CGRectEqualToRect(text, [host convertRect:words.bounds fromView:words]));
                    NSLog(@"[harness] lyric-line passed");
                    exit(0);
                });
                return;
            }
            void (^checkSize)(NSInteger, CGFloat) = ^(NSInteger choice, CGFloat points) {
                SGRSetPlayerLineSmall(choice == 1);
                [host layoutIfNeeded];
                HARNESS_CHECK(fabs(words.font.pointSize - points) < 0.05);
                HARNESS_CHECK([words.text isEqual:@"한순간이였지"]);
                CGRect label = [host convertRect:words.bounds fromView:words];
                HARNESS_CHECK(CGRectEqualToRect(label, slotFor(row.origin.y,points,NO)));
            };
            checkSize(1, 17);
            checkSize(0, native);
            SGRSetLyricsTextShown(SGRLyricsTextTranslation, YES);
            UILabel *translation = (UILabel *)line.subviews[1];
            for (NSNumber *choice in @[@0, @1, @0]) {
                SGRSetPlayerLineSmall(choice.boolValue);
                [host layoutIfNeeded];
                CGFloat expected = choice.integerValue ? 14 : 15;
                NSLog(@"[harness] translation %.0f pt expected %.0f, frame %@", translation.font.pointSize,
                      expected, NSStringFromCGRect(translation.frame));
                HARNESS_CHECK(translation.font.pointSize == expected);
                HARNESS_CHECK(line.userInteractionEnabled && line.accessibilityValue != nil);
                HARNESS_CHECK([translation.text isEqual:@"One moment"] && translation.alpha == 1);
                HARNESS_CHECK([host convertRect:translation.bounds fromView:translation].origin.x == row.origin.x);
                HARNESS_CHECK(CGColorGetAlpha(translation.textColor.CGColor) == CGColorGetAlpha(SGRSecondary().CGColor));
                HARNESS_CHECK(CGRectEqualToRect(line.frame, slotFor(row.origin.y,words.font.pointSize,YES)));
                HARNESS_CHECK(CGRectGetMinY(translation.frame) >= CGRectGetMidY(words.frame) + words.font.lineHeight / 2 - 0.5);
                HARNESS_CHECK(translation.frame.size.height == ceil(translation.font.lineHeight));
                if (clip) HARNESS_CHECK(translation.frame.size.width == ceil(translation.intrinsicContentSize.width));
            }
            SGRSetLyricsTextShown(SGRLyricsTextTranslation, NO);
            NSLog(@"[harness] lyric-line passed");
            exit(0);
        });
    });
    else if ([scenario() isEqualToString:@"still"]) [self runStillChecks];
    else if ([scenario() isEqualToString:@"catalog"]) [self runCatalogChecks];
    else if ([scenario() isEqualToString:@"badge"]) [self runBadgeChecks];
    else if ([scenario() isEqualToString:@"cover"]) [self runCoverChecks];
    else if ([scenario() isEqualToString:@"immersive"]) [self runImmersiveChecks];
    else if ([scenario() isEqualToString:@"settings"]) [self runSettingsChecks];
    else if ([scenario() hasPrefix:@"share"]) SGRHarnessRunShare(self.window, [scenario() isEqualToString:@"share-system"]);
    else if ([scenario() isEqualToString:@"preview"]) [self runPreviewChecks];
    else if ([scenario() isEqualToString:@"seek"]) [self runSeekChecks];
    else if ([scenario() isEqualToString:@"timerow"]) [self performSelector:@selector(runTimeRowChecks) withObject:nil afterDelay:1];
    else if ([scenario() hasPrefix:@"sponsorblock"]) [self performSelector:@selector(runSponsorBlockChecks) withObject:nil afterDelay:1];
    else if ([scenario() isEqualToString:@"volumebar"]) [self performSelector:@selector(runVolumeBarChecks) withObject:nil afterDelay:1];
    else if ([scenario() isEqualToString:@"visualiser"]) [self runVisualiserChecks];
    else if ([scenario() isEqualToString:@"autoviz"]) [self runAutoVisualiserChecks];
    else if ([scenario() isEqualToString:@"shuffle"]) [self runShuffleChecks];
    else if ([scenario() isEqualToString:@"heat"]) [self runHeatChecks];
    else if ([scenario() hasPrefix:@"header"])
        [self performSelector:@selector(runHeaderChecks) withObject:nil afterDelay:1];
    else if ([scenario() isEqualToString:@"options"]) [self runOptionsChecks];
    else if ([scenario() isEqualToString:@"renderer"]) [self runRendererChecks];
    else if ([scenario() isEqualToString:@"automix"]) SGRHarnessRunAutoMix(self.window, _units[2], _tilt);
    else if ([scenario() isEqualToString:@"background"]) {
        extern void SGRHarnessRunBackground(UIWindow *, UIViewController *, UIView *);
        dispatch_async(dispatch_get_main_queue(), ^{ SGRHarnessRunBackground(self.window, _background, _tilt); });
    }
    // Opened, closed and opened again, so a screenshot can be taken of each state and of the move itself.
    else if (!stripCheck) for (NSNumber *at in @[@2, @6, @10]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(at.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            NSLog(@"[harness] %@ the lyrics", SGRPlayerLyricsOpen() ? @"closing" : @"opening");
            SGRPlayerToggleLyrics();
        });
    }
    return YES;
}

- (void)layOut {
    for (UIViewController *unit in _units) [unit viewDidLayoutSubviews];
}

static void runScript(NSArray<NSArray *> *script, NSUInteger index);
static UIView *firstOfClass(UIView *root, NSString *name);
static UISlider *spotifyBar(UIView *unit, NSArray<UILabel *> **labels);
#include "adaptive-check.inc"

#pragma mark - tracks

static NSString *imageURI(NSString *digits) {
    // 16 digits of size, then the picture's own 24 (padded here from a short name).
    NSString *hash = [[digits stringByPaddingToLength:24 withString:@"0" startingAtIndex:0] substringToIndex:24];
    return [@"spotify:image:ab67616d0000b273" stringByAppendingString:hash];
}

static UIViewController *unitOf(UIView *view) {
    UIResponder *next = view.nextResponder;
    return [next isKindOfClass:UIViewController.class] ? (UIViewController *)next : nil;
}

static UIView *firstOfClass(UIView *root, NSString *name);

// The alpha of a gradient's stop `index`.
static CGFloat stopAlpha(CAGradientLayer *gradient, NSUInteger index) {
    return CGColorGetAlpha((__bridge CGColorRef)gradient.colors[index]);
}

// Steps of @[delay, block], each run its delay after the one before it ran. Blocks all scheduled from one moment drift
// with dispatch_after's leeway, which grows with the delay, and two can fire together with no layout pass between.
static void runScript(NSArray<NSArray *> *script, NSUInteger index) {
    if (index >= script.count) return;
    if (![script[index][0] isKindOfClass:NSNumber.class]) {
        BOOL (^ready)(void) = script[index][0];
        NSTimeInterval deadline = NSProcessInfo.processInfo.systemUptime + 10;
        [NSTimer scheduledTimerWithTimeInterval:0.01 repeats:YES block:^(NSTimer *timer) {
            if (ready()) {
                [timer invalidate];
                ((dispatch_block_t)script[index][1])();
                runScript(script, index + 1);
            } else if (NSProcessInfo.processInfo.systemUptime >= deadline) {
                fprintf(stderr, "FAIL player scenario condition timed out at step %lu\n", (unsigned long)index);
                exit(1);
            }
        }];
        return;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)([script[index][0] doubleValue] * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        ((dispatch_block_t)script[index][1])();
        runScript(script, index + 1);
    });
}

static void after(NSTimeInterval seconds, dispatch_block_t block) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(seconds * NSEC_PER_SEC)), dispatch_get_main_queue(), block);
}

// What Spotify's screens do when a track changes: the list of covers moves to the new cell and lays out,
// still showing whatever picture that cell had, and the bar's cover stays what it was, until the
// pictures load and are set on the image views -- which lays nothing out.
- (void)playTrack:(NSString *)uri image:(NSString *)image {
    NSLog(@"[harness] track %@ (picture %@)", uri, [image substringFromIndex:image.length - 24]);
    SGRHarnessSetTrack(uri, image, NO);
    [_covers setNeedsLayout];
    [_covers layoutIfNeeded];
}

- (void)showOnScreen:(UIImage *)picture {
    _cover.image = picture;
    _barCover.image = picture;
}

- (void)start {
    if (getenv("HARNESS_NO_ARTWORK")) {
        [self showOnScreen:nil];
        [self playTrack:@"spotify:track:harnessA" image:nil];
        [_bar viewDidLayoutSubviews];
        return;
    }
    BOOL checks = [scenario() isEqualToString:@"artwork"];
    UIImage *first = checks ? solid(UIColor.redColor) : _cover.image;
    [self showOnScreen:first];
    serve(imageURI(@"aaaa"), first, 0.2, NO);
    // card: nothing plays; the Player page's card shows the last track played, or none.
    if ([scenario() isEqualToString:@"card"]) {
        after(1, ^{
            UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:SGRPlayerSettingsPage(@[])];
            nav.modalPresentationStyle = UIModalPresentationFullScreen;
            [self.window.rootViewController presentViewController:nav animated:NO completion:nil];
            after(2, ^{
                UIView *card = firstOfClass(((UITableViewController *)nav.topViewController).tableView, @"SGRPlayerPreview");
                UIImageView *cover = [card valueForKey:@"_cover"];
                NSLog(@"[harness] card: \"%@\", \"%@\", cover %.0fx%.0f", [[card valueForKey:@"_title"] text], [[card valueForKey:@"_artist"] text],
                      cover.image.size.width, cover.image.size.height);
            });
        });
        return;
    }
    [self playTrack:@"spotify:track:harnessA" image:imageURI(@"aaaa")];
    // The bar lays out once as the app comes up.
    [_bar viewDidLayoutSubviews];
}

#pragma mark - landscape

static UIViewController *landscapeScreen(void) {
    for (UIWindow *window in UIApplication.sharedApplication.connectedScenes.anyObject ? ((UIWindowScene *)UIApplication.sharedApplication.connectedScenes.anyObject).windows : @[]) {
        if (!window.hidden && [NSStringFromClass(window.rootViewController.class) isEqualToString:@"SGRLandscapeLyricsController"]) return window.rootViewController;
    }
    return nil;
}

// What a touch on the lines lands on, and whether the controls are up.
static void logLandscape(NSString *step, NSString *want) {
    UIViewController *screen = landscapeScreen();
    UIView *view = screen.view, *shield = [screen valueForKey:@"shield"];
    CGPoint onLine = CGPointMake(view.bounds.size.width * 0.7, view.bounds.size.height * 0.5);
    UIView *hit = [view hitTest:onLine withEvent:nil];
    CGFloat controls = [[screen valueForKey:@"controls"] alpha];
    NSString *got = hit == shield ? @"shield" : @"lines";
    NSLog(@"[harness] landscape %@: controls %.0f, a touch on the lines lands on %@ (%@) -- want %@: %@", step, controls,
          got, NSStringFromClass(hit.class), want, [got isEqualToString:want] ? @"ok" : @"WRONG");
}

// The landscape lyrics as a turned phone shows them: a line's meanings over them as a card on the bottom
// edge, the controls staying up behind the sheet and fading once it is gone, the shield taking the touch
// that brings them back, and a pause and a resume from elsewhere starting the clock again.
// Count deliveries to the actual pages. Advance each sample by frames of the page that
// should be running, so a stalled run loop or two stopped links cannot give a false pass.
- (void)runLandscapeOwner {
    __block UIView *portrait, *landscape;
    __block NSUInteger p = 0, l = 0, startP, startL, covered;
    __block NSUInteger pIn = 0, lIn = 0, pOut = 0, lOut = 0;
    __block BOOL returning = NO;
    Method tick = class_getInstanceMethod(NSClassFromString(@"SGRKaraokeView"), @selector(tick));
    void (*draw)(id, SEL) = (void *)method_getImplementation(tick);
    method_setImplementation(tick, imp_implementationWithBlock(^(UIView *page) {
        if (page == portrait) p++;
        if (page == landscape) l++;
        float opacity = landscape.window.layer.presentationLayer.opacity;
        if (opacity > 0 && opacity < 1) {
            if (returning) { pOut += page == portrait; lOut += page == landscape; }
            else { pIn += page == portrait; lIn += page == landscape; }
        }
        draw(page, @selector(tick));
    }));
    runScript(@[
        @[^BOOL { return SGRPlayerLyricsAvailable() && self.window.isKeyWindow; }, ^{
            SGRPlayerToggleLyrics();
            portrait = firstOfClass(self.window, @"SGRKaraokeView");
        }],
        @[^BOOL { return p >= 10; }, ^{
            SGRPlayerShowLandscape(YES);
            landscape = firstOfClass(landscapeScreen().view, @"SGRKaraokeView");
        }],
        @[^BOOL { return l >= 10 && landscape.window.alpha == 1 && landscape.window.layer.presentationLayer.opacity == 1; },
            ^{ startL = l; }],
        @[^BOOL { return l >= startL + 10; }, ^{ startP = p; startL = l; }],
        @[^BOOL { return l >= startL + 15; }, ^{
            covered = p - startP;
            returning = YES;
            SGRPlayerShowLandscape(NO);
        }],
        @[^BOOL { return self.window.isKeyWindow; }, ^{ startP = p; startL = l; }],
        @[^BOOL { return p >= startP + 15; }, ^{
            NSUInteger retired = l - startL;
            NSLog(@"[harness] covered portrait %lu, retired landscape %lu ticks", covered, retired);
            NSLog(@"[harness] mid-fade portrait/landscape: in %lu/%lu out %lu/%lu", pIn, lIn, pOut, lOut);
            NSUInteger right = (covered == 0) + (retired == 0) + (pIn && lIn) + (pOut && lOut);
            NSLog(@"[harness] landscape-owner checks: %lu of 4 right -- %@", right, right == 4 ? @"PASS" : @"FAIL");
            exit(right == 4 ? 0 : 1);
        }],
    ], 0);
}

- (void)runLandscape {
    // With portrait lyrics closed this is the bare landscape player, which never hides controls.
    after(2, ^{ SGRPlayerToggleLyrics(); });
    after(3, ^{ SGRPlayerShowLandscape(YES); });
    // The window comes up clear and fades in with the turn; it and what it presents are dark; the
    // controls say what they do and are 44pt.
    after(3.05, ^{
        UIWindow *window = landscapeScreen().view.window;
        NSLog(@"[harness] landscape window as it comes up: alpha %.2f -- want under 1: %@", window.alpha, window.alpha < 1 ? @"ok" : @"WRONG");
    });
    after(3.9, ^{
        UIViewController *screen = landscapeScreen();
        UIWindow *window = screen.view.window;
        NSLog(@"[harness] landscape window: alpha %.2f, %@ -- want 1, dark: %@", window.alpha,
              window.overrideUserInterfaceStyle == UIUserInterfaceStyleDark ? @"dark" : @"not dark",
              window.alpha == 1 && window.overrideUserInterfaceStyle == UIUserInterfaceStyleDark ? @"ok" : @"WRONG");
        NSMutableArray<UIButton *> *buttons = [[[screen valueForKey:@"controls"] arrangedSubviews] mutableCopy];
        [buttons addObject:[screen valueForKey:@"_close"]];
        for (UIButton *button in buttons) {
            BOOL ok = button.accessibilityLabel.length && button.bounds.size.width >= 44 && button.bounds.size.height >= 44;
            NSLog(@"[harness] landscape button \"%@\" %@ -- want a label, 44pt: %@", button.accessibilityLabel,
                  NSStringFromCGSize(button.bounds.size), ok ? @"ok" : @"WRONG");
        }
        UILabel *title = [screen valueForKey:@"_title"], *artist = [screen valueForKey:@"_artist"];
        NSLog(@"[harness] landscape text: title %.0fpt in %@, artist %.0fpt in %@, close %@", title.font.pointSize,
              NSStringFromCGRect(title.frame), artist.font.pointSize, NSStringFromCGRect(artist.frame),
              NSStringFromCGRect([[screen valueForKey:@"_close"] frame]));
    });
    after(4, ^{
        SGLyricsMeaning *meaning = [SGLyricsMeaning new];
        meaning.author = SGLyricsMeaningByArtist;
        meaning.body = @"A line of the harness's song, explained at the length Genius explains one, so the card has a body to show and to wrap.";
        meaning.url = @"https://genius.com";
        SGRShowMeanings(@"Harness line", @[meaning]);
    });
    after(6, ^{
        UIViewController *sheet = landscapeScreen().presentedViewController;
        UIView *window = sheet.view.window;
        NSLog(@"[harness] landscape meanings: %@ %@ in a window %@, height class %ld, edge attached %d",
              NSStringFromClass(sheet.class), NSStringFromCGRect([sheet.view convertRect:sheet.view.bounds toView:window]),
              NSStringFromCGSize(window.bounds.size), (long)sheet.traitCollection.verticalSizeClass,
              sheet.sheetPresentationController.prefersEdgeAttachedInCompactHeight);
    });
    after(8.5, ^{ logLandscape(@"with the sheet up past the rest", @"lines"); });
    after(9, ^{ [landscapeScreen() dismissViewControllerAnimated:YES completion:nil]; });
    after(14, ^{ logLandscape(@"rested after the sheet went", @"shield"); });
    after(14.5, ^{ SGRHarnessSetTrack(@"spotify:track:harnessA", imageURI(@"aaaa"), YES); });
    after(15, ^{ logLandscape(@"paused", @"lines"); });
    after(15.5, ^{ SGRHarnessSetTrack(@"spotify:track:harnessA", imageURI(@"aaaa"), NO); });
    after(17, ^{ logLandscape(@"just resumed", @"lines"); });
    after(21, ^{ logLandscape(@"rested after the resume", @"shield"); });
    // VoiceOver's escape turns the screen back, and the player is key once it has faded.
    after(22, ^{
        NSLog(@"[harness] landscape escape answered %d", [landscapeScreen() accessibilityPerformEscape]);
        runScript(@[@[^BOOL { return !landscapeScreen() && self.window.isKeyWindow; }, ^{
            NSLog(@"[harness] landscape after the escape: gone 1, the player key 1 -- ok");
        }]], 0);
    });
}

#pragma mark - badge

// The hold's 2x badge: the Kit's glass capsule first in it with its effect on, the label over it, the
// glyph an attachment; a hold again while it fades out keeps it; let go, it goes.
- (void)runBadgeChecks {
    __block NSObject *hold = nil;
    for (UIGestureRecognizer *recognizer in _tilt.gestureRecognizers) {
        if ([NSStringFromClass(recognizer.class) isEqualToString:@"SGRCoverHold"]) hold = recognizer;
    }
    __block NSUInteger right = 0, checks = 0;
    void (^check)(NSString *, BOOL) = ^(NSString *step, BOOL ok) {
        checks++;
        if (ok) right++;
        NSLog(@"[harness] badge %@: %@", step, ok ? @"ok" : @"WRONG");
    };
    UIView *tilt = _tilt;
    UIView *(^badge)(void) = ^UIView *{ return [hold valueForKey:@"badge"]; };
    after(2, ^{ [hold showBadge:YES on:tilt]; });
    after(2.8, ^{
        UIView *shape = badge().subviews.firstObject;
        UILabel *label = [hold valueForKey:@"badgeLabel"];
        __block BOOL glyph = NO;
        [label.attributedText enumerateAttribute:NSAttachmentAttributeName inRange:NSMakeRange(0, label.attributedText.length) options:0
                                      usingBlock:^(id value, NSRange range, BOOL *stop) { if (value) glyph = YES; }];
        check(@"up", badge().superview == tilt && [shape isKindOfClass:UIVisualEffectView.class]
              && ((UIVisualEffectView *)shape).effect && label.superview == badge() && label.alpha == 1
              && CGAffineTransformIsIdentity(badge().transform) && glyph);
        NSLog(@"[harness] badge %@ with %@ (%@), label %@ fits %d", NSStringFromCGRect(badge().frame), NSStringFromClass(shape.class),
              NSStringFromClass([(UIVisualEffectView *)shape effect].class), label.attributedText.string,
              label.intrinsicContentSize.width <= badge().bounds.size.width);
        [hold showBadge:NO on:tilt];
    });
    after(2.85, ^{ [hold showBadge:YES on:tilt]; });
    after(3.5, ^{
        check(@"held again while it faded", badge().superview == tilt && [(UIVisualEffectView *)badge().subviews.firstObject effect]);
        [hold showBadge:NO on:tilt];
    });
    after(4, ^{
        check(@"let go", !badge().superview);
        NSLog(@"[harness] badge checks: %lu of %lu right -- %@", (unsigned long)right, (unsigned long)checks, right == checks ? @"PASS" : @"FAIL");
    });
}

- (void)check:(NSString *)step want:(NSString *)want {
    NSString *uri = nil;
    UIImage *artwork = SGRNowPlayingArtwork(&uri, NULL);
    UIImage *drawn = [SGRPlayerField() valueForKey:@"image"];
    NSString *kit = colorName(artwork), *field = colorName(drawn);
    BOOL ok = [kit isEqualToString:want] && [field isEqualToString:want];
    _checks++;
    if (!ok) _failures++;
    NSLog(@"[harness] check %@: want %@, the Kit has %@ (for %@), the field draws %@ -- %@", step, want, kit, uri, field, ok ? @"ok" : @"WRONG");
}

// Issue #58: after a switch to another album the field kept the last one's picture until the next track.
- (void)runArtworkChecks {
    UIImage *green = solid(UIColor.greenColor), *blue = solid(UIColor.blueColor), *yellow = solid(UIColor.yellowColor),
            *magenta = solid(UIColor.magentaColor);
    after(1.5, ^{ [self check:@"1 first track" want:@"red"]; });

    // Another album: the screens go on showing the last picture for 3.5 s, well past the Kit's last look
    // at them, and the picture server answers in 1 s.
    after(2, ^{
        serve(imageURI(@"bbbb"), green, 1.0, NO);
        [self playTrack:@"spotify:track:harnessB" image:imageURI(@"bbbb")];
    });
    after(5.5, ^{ [self showOnScreen:green]; });
    after(7, ^{ [self check:@"2 album switch, the screens late" want:@"green"]; });

    // Two tracks in quick succession, the first one's picture answering last.
    after(7.5, ^{
        serve(imageURI(@"cccc"), blue, 2.0, NO);
        [self playTrack:@"spotify:track:harnessC" image:imageURI(@"cccc")];
    });
    after(7.7, ^{ [self showOnScreen:blue]; });
    after(7.8, ^{
        serve(imageURI(@"dddd"), yellow, 0.3, NO);
        [self playTrack:@"spotify:track:harnessD" image:imageURI(@"dddd")];
    });
    after(8.1, ^{ [self showOnScreen:yellow]; });
    after(11, ^{ [self check:@"3 skip twice, the older answer last" want:@"yellow"]; });

    // Offline: the server fails, and the screens show the new picture 0.8 s after the change.
    after(11.5, ^{
        serve(imageURI(@"eeee"), magenta, 0.1, YES);
        [self playTrack:@"spotify:track:harnessE" image:imageURI(@"eeee")];
    });
    after(12.3, ^{ [self showOnScreen:magenta]; });
    after(14.5, ^{ [self check:@"4 offline, the screens only" want:@"magenta"]; });

    after(15, ^{
        NSLog(@"[harness] artwork checks: %lu of %lu right -- %@", (unsigned long)(self->_checks - self->_failures), (unsigned long)self->_checks,
              self->_failures ? @"FAIL" : @"PASS");
    });
}

// Up must be taken back to the top, down (the dismissal's pull) left where it went.
#pragma mark - Animated artwork

BOOL SGPlayerMenuAnimatedArtwork(void);
void SGPlayerMenuSetAnimatedArtwork(BOOL on);

static UIView *motionView(void) {
    for (UIView *view in SGRPlayerField().subviews) {
        if ([NSStringFromClass(view.class) isEqualToString:@"SGRPlayerMotionView"]) return view;
    }
    return nil;
}

- (void)expect:(BOOL)ok step:(NSString *)step detail:(NSString *)detail {
    _checks++;
    if (!ok) _failures++;
    NSLog(@"[harness] %@ check %@: %@ -- %@", scenario(), step, detail, ok ? @"ok" : @"WRONG");
}

// The field covered by the clip, and its Fluid copies hidden for it.
static BOOL fieldCovered(void) {
    SGRArtworkField *field = SGRPlayerField();
    CALayer *fluid = [field valueForKey:@"_fluidLayer"];
    return field.covered && fluid && fluid.hidden;
}

// Green above the last 3% of rows, a red left half and a blue right half within them: the foot must keep the
// clip's left and right, red at its left edge and blue at its right, opaque, never green, and blend between
// them across the middle rather than meet in a hard edge as stretched pixel columns would.
static BOOL motionFootAcross(NSURL *file, NSString **detail) {
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat];
    format.scale = 1;
    format.preferredRange = UIGraphicsImageRendererFormatRangeStandard;
    UIImage *poster = [[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(32, 100) format:format]
        imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
            [UIColor.greenColor setFill];
            UIRectFill(CGRectMake(0, 0, 32, 100));
            [UIColor.redColor setFill];
            UIRectFill(CGRectMake(0, 97, 16, 3));
            [UIColor.blueColor setFill];
            UIRectFill(CGRectMake(16, 97, 16, 3));
        }];
    SGRPlayerMotionView *probe = [[SGRPlayerMotionView alloc] initWithFrame:CGRectMake(0, 0, 32, 120)];
    [probe playFile:file poster:poster];
    [probe layoutIfNeeded];
    CALayer *foot = [probe valueForKey:@"_foot"];
    uint8_t pixels[16 * 4] = {0};
    CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGContextRef context = CGBitmapContextCreate(pixels, 16, 1, 8, sizeof pixels, space,
                                                kCGBitmapByteOrder32Big | kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(space);
    CGContextScaleCTM(context, 16 / foot.bounds.size.width, 1 / foot.bounds.size.height);
    [foot renderInContext:context];
    CGContextRelease(context);
    NSMutableArray *row = [NSMutableArray array];
    BOOL ok = YES;
    for (NSUInteger x = 0; x < 16; x++) {
        uint8_t *pixel = pixels + x * 4, *before = x ? pixel - 4 : pixel;
        [row addObject:[NSString stringWithFormat:@"%u,%u,%u", pixel[0], pixel[1], pixel[2]]];
        // Opaque, nothing of the green above (Core Animation's software render of a gradient puts a little green
        // into pure red and blue: 38 and 50 on the iOS 26.5 simulator), red only ever giving way to blue from left
        // to right, give or take the render's rounding of a level.
        ok = ok && pixel[3] == 255 && pixel[1] < 64 && pixel[0] <= before[0] + 1 && pixel[2] + 1 >= before[2];
    }
    uint8_t *left = pixels, *right = pixels + 15 * 4, *middle = pixels + 7 * 4, *past = pixels + 8 * 4;
    ok = ok && left[0] >= 240 && left[2] <= 10 && right[0] <= 10 && right[2] >= 240
         && middle[0] > 40 && middle[2] > 40 && past[0] > 40 && past[2] > 40;
    *detail = [NSString stringWithFormat:@"RGB left to right %@; expected red at the left, blue at the right, both mixed in the middle",
               [row componentsJoinedByString:@" "]];
    return ok;
}

// The probe's whole picture, a gray poster with no video drawn, read down its middle: from where the dim is whole
// (its last stop) to the bottom it gets darker, ending clearly darker than where it started, and nowhere lighter
// than it is there, which is the dim alone.
static BOOL motionDeepensDown(NSURL *file, NSString **detail) {
    enum { kTall = 900 };
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat];
    format.scale = 1;
    format.preferredRange = UIGraphicsImageRendererFormatRangeStandard;
    UIImage *poster = [[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(32, 100) format:format]
        imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
            [[UIColor colorWithWhite:0.5 alpha:1] setFill];
            UIRectFill(CGRectMake(0, 0, 32, 100));
        }];
    SGRPlayerMotionView *probe = [[SGRPlayerMotionView alloc] initWithFrame:CGRectMake(0, 0, 32, kTall)];
    [probe playFile:file poster:poster];
    [probe layoutIfNeeded];
    CAGradientLayer *dim = [probe valueForKey:@"_dim"];
    // Where the lower half starts to darken (stop 6): the picture is as light as it gets there and darkens to the foot.
    NSUInteger whole = (NSUInteger)ceil([dim.locations[6] doubleValue] * kTall);
    uint8_t pixels[kTall * 4] = {0};
    CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGContextRef context = CGBitmapContextCreate(pixels, 1, kTall, 8, 4, space, kCGBitmapByteOrder32Big | kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(space);
    // UIKit's way up: row 0 of the bitmap is the top of the picture.
    CGContextTranslateCTM(context, 0, kTall);
    CGContextScaleCTM(context, 1.0 / 32, -1);
    [((UIView *)[probe valueForKey:@"_picture"]).layer renderInContext:context];
    CGContextRelease(context);
    uint8_t start = pixels[whole * 4], end = pixels[(kTall - 1) * 4];
    BOOL ok = whole > 0 && whole < kTall - 1 && end + 8 < start;
    for (NSUInteger y = whole + 1; y < kTall; y++) ok = ok && pixels[y * 4] <= pixels[(y - 1) * 4] + 1 && pixels[y * 4] <= start;
    *detail = [NSString stringWithFormat:@"gray %u where the dim is whole (row %lu of %d), %u at the bottom", start, (unsigned long)whole, kTall, end];
    return ok;
}

- (void)runMotionChecks {
    BOOL mirrorOnly = [scenario() isEqual:@"motion-mirror"];
    // The clip comes in before the player has laid out, as for the track restored at launch.
    if (!mirrorOnly) after(3, ^{
        [self expect:SGRPlayerMotionShowing() && !SGRPlayerField() step:@"before the player opened"
              detail:[NSString stringWithFormat:@"clip %@, field %@", SGRPlayerMotionShowing() ? @"in" : @"missing", SGRPlayerField() ? @"made" : @"not made"]];
    });
    after(4, ^{
        [self->_list insertSubview:self->_plane atIndex:0];
        self->_units = [self->_units arrayByAddingObject:self->_background];
        [self layOut];
    });
    after(5, ^{
        UIView *motion = motionView();
        CALayer *foot = [motion valueForKey:@"_foot"], *clip = [motion valueForKey:@"_clip"];
        if (mirrorOnly) {
            CAReplicatorLayer *soft = [motion valueForKey:@"_soft"];
            AVPlayerLayer *video = [motion valueForKey:@"_softClip"];
            if (soft.hidden || soft.instanceCount < 2 || !video.readyForDisplay || !video.player)
                HARNESS_FAIL(@"3:4 mirror fixture needs a visible, playing replica");
            CGRect source = [video convertRect:video.bounds toLayer:soft];
            CGFloat anchorY = soft.anchorPoint.y * CGRectGetHeight(soft.bounds);
            CGRect mirrored = CGRectOffset(CGRectApplyAffineTransform(CGRectOffset(source, 0, -anchorY),
                CATransform3DGetAffineTransform(soft.instanceTransform)), 0, anchorY);
            CALayer *window = self.window.layer;
            mirrored = [soft convertRect:mirrored toLayer:window];
            CGFloat edge = CGRectGetMaxY([clip convertRect:clip.bounds toLayer:window]), bottom = CGRectGetMaxY(window.bounds);
            if (fabs(source.size.height * 3 / 4 - source.size.width) > 1 || edge >= bottom ||
                fabs(CGRectGetMinY(mirrored) - edge) > 1 || CGRectGetMaxY(mirrored) < bottom)
                HARNESS_FAIL(@"mirror %@ does not span %.0f to %.0f", NSStringFromCGRect(mirrored), edge, bottom);
            NSLog(@"[harness] mirror %@ spans %.0f to %.0f", NSStringFromCGRect(mirrored), edge, bottom);
            if (!getenv("HARNESS_MOTION_SCREENSHOT")) exit(0);
            [video.player pause];
            [video.player seekToTime:CMTimeMake(736, 1000) toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero];
            return;
        }
        UIVisualEffectView *seam = [motion valueForKey:@"_seamBlur"];
        // The lyrics' blur is a filter on the clip, there only while the lyrics are up.
        BOOL lyricsBlurred = ((UIView *)[motion valueForKey:@"_picture"]).layer.filters.count > 0;
        [self expect:motion != nil && self->_covers.layer.mask != nil step:@"the player opened"
              detail:[NSString stringWithFormat:@"clip %@ the field, cover %@", motion ? @"on" : @"not on", self->_covers.layer.mask ? @"hidden" : @"shown"]];
        CGFloat seamAt = round(clip.frame.size.height * 0.9);
        NSArray *footColors = [foot isKindOfClass:CAGradientLayer.class] ? ((CAGradientLayer *)foot).colors : nil;
        BOOL footOpaque = footColors.count > 0;
        for (id color in footColors) footOpaque = footOpaque && CGColorGetAlpha((__bridge CGColorRef)color) == 1;
        BOOL footDown = foot && fabs(foot.frame.origin.y - seamAt) < 1 && CGRectGetMaxY(foot.frame) >= self.window.bounds.size.height
            && footOpaque;
        [self expect:footDown step:@"the foot"
              detail:[NSString stringWithFormat:@"clip %@, foot %@, %lu colors across, %@",
                      NSStringFromCGRect(clip.frame), NSStringFromCGRect(foot.frame), (unsigned long)footColors.count,
                      footOpaque ? @"all opaque" : @"not all opaque"]];
        NSString *footDetail = @"clip URL unavailable", *deepDetail = @"clip URL unavailable";
        NSURL *file = ((AVURLAsset *)((AVPlayer *)[motion valueForKey:@"_player"]).currentItem.asset).URL;
        BOOL across = file && motionFootAcross(file, &footDetail);
        [self expect:across step:@"the foot's colors across" detail:footDetail];
        BOOL deepens = file && motionDeepensDown(file, &deepDetail);
        [self expect:deepens step:@"darker toward the bottom" detail:deepDetail];
        // The poster under the video, so the clip has a picture before its first frame is decoded; and the
        // Fluid field under it held still and, the clip being opaque, hidden.
        CALayer *still = clip.superlayer;
        [self expect:still.contents && CGRectEqualToRect(still.bounds, clip.frame) && still.mask && SGRPlayerField().motionHeld
                     && fieldCovered()
                step:@"the poster and the held field"
              detail:[NSString stringWithFormat:@"poster %@ at %@, video %@, fade %@, field %@, %@", still.contents ? @"in" : @"missing",
                      NSStringFromCGRect(still.frame), NSStringFromCGRect(clip.frame), still.mask ? @"on the poster" : @"missing",
                      SGRPlayerField().motionHeld ? @"held" : @"moving", fieldCovered() ? @"its Fluid copies hidden" : @"its Fluid copies drawn"]];
        [self expect:!seam.effect && !lyricsBlurred step:@"no gray blur under the controls"
              detail:[NSString stringWithFormat:@"seam blur %@, from %@ of the height, lyrics blur %@", seam.effect ? @"on" : @"off",
                      [[seam.maskView.layer.sublayers.firstObject valueForKey:@"locations"] componentsJoinedByString:@" to "], lyricsBlurred ? @"on" : @"off"]];
        // Dimmed by its brightness: HARNESS_DIM is what the clip in HARNESS_CANVAS_FILE should get (0.54 for white,
        // 0.10 for black), which the clip's own dim eases to 0.7 of (kDimSoften in PlayerMotion.x); the rule itself is checked at its ends.
        CAGradientLayer *dim = [motion valueForKey:@"_dim"];
        // Whole at the very top and fading out from there with no edge, clear until the ramp, then growing to whole at the
        // foot of the screen (issue #101): stop 0 the top, 1 the end of the status bar's band (part of the dim), 5 the end of the
        // fade, 6 the start of the lower half's curve and 14 the whole dim at the foot.
        BOOL banded = dim && dim.colors.count == 15 && stopAlpha(dim, 0) > 0.8 && stopAlpha(dim, 1) > 0 && stopAlpha(dim, 1) < stopAlpha(dim, 0)
                      && stopAlpha(dim, 5) == 0 && stopAlpha(dim, 6) == 0 && stopAlpha(dim, 14) == 1;
        const char *expected = getenv("HARNESS_DIM");
        BOOL rule = fabs(SGRPlayerClipDim(1, NO, NO) - 0.54) < 0.01 && fabs(SGRPlayerClipDim(1, YES, NO) - 0.65) < 0.01
                    && SGRPlayerClipDim(0, NO, NO) == 0.10 && fabs(SGRPlayerClipDim(0, NO, YES) - 0.25) < 1e-6
                    && fabs(SGRPlayerClipDim(0.5, NO, NO) - 0.37) < 0.01;
        self->_dimAlone = dim.opacity;
        [self expect:rule && banded && dim && dim.superlayer == clip.superlayer.superlayer && (!expected || fabs(dim.opacity - atof(expected) * 0.7) < 0.02)
                step:@"the dim" detail:[NSString stringWithFormat:@"rule %@, dim %.2f %@%@", rule ? @"right" : @"wrong", dim.opacity,
                                        banded ? [NSString stringWithFormat:@"fading from the top to %@ and whole at %@", dim.locations[1], dim.locations[14]] : @"not banded",
                                        expected ? [NSString stringWithFormat:@", %s expected", expected] : @""]];
        // The band at the top: whole over the status bar only while the header shows nothing but the grabber, and over
        // the header's row too while it shows where it plays from. The stored switch is put back as it was.
        NSUserDefaults *store = NSUserDefaults.standardUserDefaults;
        id stored = [store objectForKey:SGRKeyPlayerHideContext];
        UIView *row = ((UIViewController *)self->_units.firstObject).view;
        CGFloat total = motion.bounds.size.height, safeTop = self.window.safeAreaInsets.top;
        CGFloat (^bandEnd)(BOOL) = ^CGFloat(BOOL hide) {
            SGSetEnabled(SGRKeyPlayerHideContext, hide);
            [self layOut];
            [motion layoutIfNeeded];
            return [((CAGradientLayer *)[motion valueForKey:@"_dim"]).locations[1] doubleValue] * total;
        };
        CGFloat bare = bandEnd(YES), shown = bandEnd(NO), rowBottom = CGRectGetMaxY([motion convertRect:row.bounds fromView:row]);
        if (stored) [store setObject:stored forKey:SGRKeyPlayerHideContext];
        else [store removeObjectForKey:SGRKeyPlayerHideContext];
        SGPrefsChanged();
        [self layOut];
        [motion layoutIfNeeded];
        [self expect:safeTop > 0 && fabs(bare - safeTop) < 1 && shown >= rowBottom step:@"the band at the top"
              detail:[NSString stringWithFormat:@"the band's end at %.0f with only the grabber (status bar to %.0f), to %.0f with where it plays from (its row to %.0f)",
                      bare, safeTop, shown, rowBottom]];
        NSLog(@"[harness] motion: screenshot the clip now");
        // Held here for a screenshot of the clip as it opened, the context as stored.
        if (getenv("HARNESS_MOTION_SCREENSHOT")) return;
        reportPower();
        setThermal(NSProcessInfoThermalStateSerious);
    });
    if (mirrorOnly || getenv("HARNESS_MOTION_SCREENSHOT")) return;
    after(6, ^{
        [self expect:!SGRPlayerMotionShowing() && !motionView() && !self->_covers.layer.mask
              step:@"serious heat" detail:@"the clip should be cleared for the cover"];
        setThermal(NSProcessInfoThermalStateNominal);
    });
    after(7, ^{
        [self expect:SGRPlayerMotionShowing() && motionView() && self->_covers.layer.mask
              step:@"cooled to nominal" detail:@"the clip should be looked up again"];
        SGRPlayerToggleLyrics();
    });
    after(8.5, ^{
        BOOL lyricsBlurred = ((UIView *)[motionView() valueForKey:@"_picture"]).layer.filters.count > 0;
        UIView *thumb = nil;
        for (UIView *view in self->_host.subviews) {
            if ([NSStringFromClass(view.class) isEqualToString:@"SGRPlayerLyricsOverlay"]) thumb = [view valueForKey:@"thumb"];
        }
        BOOL away = thumb && !CGAffineTransformIsIdentity(thumb.transform) && thumb.alpha > 0.99;
        CAGradientLayer *shade = [motionView() valueForKey:@"_dim"];
        float dim = shade.opacity;
        // The lyrics run down the whole screen, so the dim covers all of it.
        BOOL whole = shade && stopAlpha(shade, 2) == 1;
        [self expect:whole && dim > self->_dimAlone + 0.14f step:@"the dim under the lyrics"
              detail:[NSString stringWithFormat:@"%.2f, %.2f without them", dim, self->_dimAlone]];
        [self expect:SGRPlayerLyricsOpen() && lyricsBlurred && away step:@"the lyrics"
              detail:[NSString stringWithFormat:@"lyrics %@, clip blurred %@, thumbnail %@ at alpha %.2f", SGRPlayerLyricsOpen() ? @"up" : @"down",
                      lyricsBlurred ? @"yes" : @"no", thumb && !CGAffineTransformIsIdentity(thumb.transform) ? @"in its corner" : @"at the cover", thumb.alpha]];
        NSLog(@"[harness] motion: screenshot the lyrics now");
    });
    after(10, ^{ SGRPlayerToggleLyrics(); });
    // Spotify builds the player's background again: the clip goes onto the new field.
    after(11.5, ^{
        UIView *old = SGRPlayerField();
        UIView *plane = [[UIView alloc] initWithFrame:self->_plane.frame];
        UIViewController *background = [_TtC21NowPlaying_ScrollImpl27NPVBackgroundViewController new];
        background.view = plane;
        [self->_plane removeFromSuperview];
        [self->_list insertSubview:plane atIndex:0];
        self->_plane = plane;
        NSMutableArray *units = [self->_units mutableCopy];
        [units replaceObjectAtIndex:[units indexOfObject:self->_background] withObject:background];
        self->_units = units;
        self->_background = background;
        [self layOut];
        [self expect:SGRPlayerField() != old && motionView() != nil && fieldCovered() step:@"a field built again"
              detail:[NSString stringWithFormat:@"%@, its Fluid copies %@", motionView() ? @"the clip moved onto it" : @"the clip left behind",
                      fieldCovered() ? @"hidden" : @"drawn"]];
    });
    // Switched off, the clip and the cover cross over: the clip's fade out and the cover's fade in start
    // together, over the same time.
    after(12.5, ^{
        SGPlayerMenuSetAnimatedArtwork(NO);
        UIView *fading = motionView();
        CALayer *picture = ((UIView *)[fading valueForKey:@"_picture"]).layer, *mask = self->_covers.layer.mask;
        CAAnimation *out = [picture animationForKey:@"opacity"], *in = [mask animationForKey:@"opacity"];
        [self expect:!SGRPlayerMotionShowing() && fading && out && in && fabs(out.duration - in.duration) < 0.01 && picture.opacity == 0
                     && mask.opacity == 1 && !SGRPlayerField().motionHeld && !fieldCovered()
                step:@"switched off, crossing over"
              detail:[NSString stringWithFormat:@"clip %@ to %.0f over %.2f s, cover to %.0f over %.2f s, field %@, its Fluid copies %@", fading ? @"fading" : @"gone",
                      picture.opacity, out.duration, mask.opacity, in.duration, SGRPlayerField().motionHeld ? @"held" : @"moving",
                      fieldCovered() ? @"hidden" : @"drawn"]];
    });
    after(13.2, ^{
        [self expect:!SGRPlayerMotionShowing() && !motionView() && !self->_covers.layer.mask && !SGPlayerMenuAnimatedArtwork()
                step:@"switched off from the menu" detail:[NSString stringWithFormat:@"clip %@, cover %@", motionView() ? @"still there" : @"gone",
                                                                 self->_covers.layer.mask ? @"hidden" : @"back"]];
        SGPlayerMenuSetAnimatedArtwork(YES);
    });
    after(14.7, ^{
        // Faded in on screen this time, so the field is covered once the fade has finished.
        [self expect:motionView() && self->_covers.layer.mask && fieldCovered() step:@"switched on again"
              detail:[NSString stringWithFormat:@"clip %@, cover %@, its Fluid copies %@", motionView() ? @"back" : @"missing",
                      self->_covers.layer.mask ? @"hidden" : @"shown", fieldCovered() ? @"hidden" : @"drawn"]];
        // The player closed: the cover list cannot be found, and switching off must still bring its cover back.
        [self->_host removeFromSuperview];
        SGPlayerMenuSetAnimatedArtwork(NO);
        [self expect:!self->_covers.layer.mask step:@"switched off with the player closed" detail:self->_covers.layer.mask ? @"cover still hidden" : @"cover back"];
        [self->_list addSubview:self->_host];
    });
    after(15.7, ^{ SGPlayerMenuSetAnimatedArtwork(YES); });
    // The song paused and played again: the clip holds its frame, then moves on.
    after(17.2, ^{
        AVPlayer *player = [motionView() valueForKey:@"_player"];
        AVPlayerLayer *clip = [motionView() valueForKey:@"_clip"];
        [self expect:player.rate > 0 && clip.readyForDisplay step:@"playing" detail:[NSString stringWithFormat:@"clip at rate %.1f, %@", player.rate,
              clip.readyForDisplay ? @"drawn" : @"not drawn"]];
        SGRHarnessSetTrack(@"spotify:track:harnessA", imageURI(@"aaaa"), YES);
        AVPlayer *paused = [motionView() valueForKey:@"_player"];
        [self expect:motionView() && paused.rate == 0 step:@"paused" detail:[NSString stringWithFormat:@"clip %@ at rate %.1f",
              motionView() ? @"there" : @"gone", paused.rate]];
        SGRHarnessSetTrack(@"spotify:track:harnessA", imageURI(@"aaaa"), NO);
        [self expect:paused.rate > 0 step:@"played again" detail:[NSString stringWithFormat:@"rate %.1f", paused.rate]];
    });
    // Spotify's music video comes and goes: the clip goes for it, and comes back after.
    __block id video = nil;
    after(17.5, ^{
        video = [NSClassFromString(@"_TtC22NowPlaying_ElementsKit14VideoElementUI") new];
        [video videoSurfaceDidAttachVideo:nil];
    });
    after(18.5, ^{
        [self expect:!SGRPlayerMotionShowing() step:@"Spotify's video showing" detail:SGRPlayerMotionShowing() ? @"the clip stayed" : @"the clip went"];
        [video videoSurfaceDidDetachVideo:nil];
    });
    after(19.5, ^{
        [self expect:SGRPlayerMotionShowing() && self->_covers.layer.mask step:@"Spotify's video gone"
              detail:SGRPlayerMotionShowing() ? @"the clip back" : @"no clip"];
        // A track whose first state names no Canvas, as on a skip before Spotify's extended metadata.
        unsetenv("HARNESS_CANVAS");
        SGRHarnessSetTrack(@"spotify:track:harnessB", imageURI(@"bbbb"), NO);
    });
    after(20.5, ^{
        [self expect:!SGRPlayerMotionShowing() step:@"a track with no Canvas yet" detail:SGRPlayerMotionShowing() ? @"a clip left" : @"no clip"];
        setenv("HARNESS_CANVAS", "https://canvas.harness/clip.mp4", 1);
        SGRHarnessSetTrack(@"spotify:track:harnessB", imageURI(@"bbbb"), NO);
    });
    // A skip to a track whose clip is in the store: the clip stays for the next one to cross over it.
    __block UIView *before = nil;
    after(21.5, ^{
        [self expect:SGRPlayerMotionShowing() step:@"its Canvas came late" detail:SGRPlayerMotionShowing() ? @"the clip in" : @"no clip"];
        before = motionView();
        SGRHarnessSetTrack(@"spotify:track:harnessC", imageURI(@"cccc"), NO);
    });
    after(21.6, ^{
        [self expect:SGRPlayerMotionShowing() && self->_covers.layer.mask step:@"skipped, the clip kept a moment"
              detail:SGRPlayerMotionShowing() ? @"a clip in" : @"the cover back"];
    });
    after(22.3, ^{
        CALayer *mask = self->_covers.layer.mask;
        [self expect:SGRPlayerMotionShowing() && motionView() != before && mask && mask.opacity == 0 step:@"the next clip over the last"
              detail:[NSString stringWithFormat:@"%@, cover %@", motionView() != before ? @"a new clip" : @"the same clip", mask && mask.opacity == 0 ? @"still hidden" : @"back"]];
    });
    // Low Power Mode (Reduce Motion takes the same path): the clip goes for Fluid and the cover, and comes back
    // once it is off. The simulator has no Low Power Mode, so the process says it is on.
    after(22.5, ^{
        sg_lowPower = YES;
        [NSNotificationCenter.defaultCenter postNotificationName:NSProcessInfoPowerStateDidChangeNotification object:nil];
    });
    after(23.5, ^{
        [self expect:!SGRPlayerMotionShowing() && !motionView() && !self->_covers.layer.mask step:@"Low Power Mode"
              detail:[NSString stringWithFormat:@"clip %@, cover %@", motionView() ? @"still there" : @"gone", self->_covers.layer.mask ? @"hidden" : @"back"]];
        sg_lowPower = NO;
        [NSNotificationCenter.defaultCenter postNotificationName:NSProcessInfoPowerStateDidChangeNotification object:nil];
    });
    // A track change with the app in the background: the last clip goes at once, with no fade to come back to.
    __block UIApplicationState state = UIApplicationStateActive;
    after(24.5, ^{
        [self expect:SGRPlayerMotionShowing() && self->_covers.layer.mask
              step:@"Low Power Mode off" detail:SGRPlayerMotionShowing() ? @"the clip back" : @"no clip"];
        Method method = class_getInstanceMethod(UIApplication.class, @selector(applicationState));
        method_setImplementation(method, imp_implementationWithBlock(^UIApplicationState(id app) { return state; }));
        state = UIApplicationStateBackground;
        unsetenv("HARNESS_CANVAS");
        SGRHarnessSetTrack(@"spotify:track:harnessD", imageURI(@"dddd"), NO);
    });
    after(24.6, ^{
        CALayer *mask = self->_covers.layer.mask;
        [self expect:!SGRPlayerMotionShowing() && !motionView() && !mask step:@"a track change in the background"
              detail:[NSString stringWithFormat:@"clip %@, cover %@", motionView() ? @"still there" : @"gone at once",
                      mask ? [NSString stringWithFormat:@"hidden, at %.2f", mask.opacity] : @"back at once"]];
        state = UIApplicationStateActive;
    });
    after(25, ^{
        NSLog(@"[harness] motion checks: %lu of %lu right -- %@", (unsigned long)(self->_checks - self->_failures), (unsigned long)self->_checks,
              self->_failures ? @"FAIL" : @"PASS");
        exit(self->_failures ? 1 : 0);
    });
}

#pragma mark - the cover's still

// A picture of one color, `pixels` wide and tall at scale 1, so its pixel width is exactly that.
static UIImage *solidPixels(UIColor *color, CGFloat pixels) {
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat preferredFormat];
    format.scale = 1;
    return [[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(pixels, pixels) format:format] imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        [color setFill];
        UIRectFill(CGRectMake(0, 0, pixels, pixels));
    }];
}

// The still behind the player: the full-screen view with no video, or nil while a clip or nothing is there.
static UIView *stillView(void) {
    UIView *view = motionView();
    return view && ![view valueForKey:@"_player"] && SGRPlayerMotionShowing() ? view : nil;
}

static CGImageRef stillPicture(void) {
    return (__bridge CGImageRef)((CALayer *)[stillView() valueForKey:@"_still"]).contents;
}

// The scrim any motion view draws over the status bar and the header's controls: its top opacity and height, or
// nil where none shows.
static NSString *scrimShown(void) {
    for (UIView *view in SGRPlayerField().subviews) {
        if (![NSStringFromClass(view.class) isEqualToString:@"SGRPlayerMotionView"]) continue;
        [view layoutIfNeeded];
        CALayer *scrim = [view valueForKey:@"_scrim"];
        if (!scrim.hidden && scrim.opacity > 0) return [NSString stringWithFormat:@"%.2f to %.0f pt", scrim.opacity, scrim.frame.size.height];
    }
    return nil;
}

static NSString *stillName(void) {
    CGImageRef picture = stillPicture();
    return picture ? [NSString stringWithFormat:@"%@ %zu px", colorName([UIImage imageWithCGImage:picture]), CGImageGetWidth(picture)] : @"no still";
}

// Animated with the full-screen cover switch: off first (the ordinary cover, as before), then on for a track with no
// clip, and every rule the still follows. HARNESS_CANVAS_FILE is the clip a later Canvas brings.
- (void)runStillChecks {
    NSUserDefaults *store = NSUserDefaults.standardUserDefaults;
    void (^setStill)(BOOL) = ^(BOOL on) {
        [store setBool:on forKey:SGRKeyPlayerAnimatedStill];
        SGRPlayerStillChanged();
    };
    void (^background)(SGRPlayerBackgroundKind) = ^(SGRPlayerBackgroundKind kind) {
        SGRSetPlayerBackground(kind);
        SGRPlayerBackgroundDidChange();
        [self layOut];
    };
    BOOL (^ordinary)(void) = ^BOOL { return !SGRPlayerMotionShowing() && !self->_covers.layer.mask; };
    __block UIView *first = nil;
    __block BOOL lowPower = NO;
    UIImage *green = solidPixels(UIColor.greenColor, 600), *blue = solidPixels(UIColor.blueColor, 600),
            *yellow = solidPixels(UIColor.yellowColor, 299), *thumb = solidPixels(UIColor.magentaColor, 120),
            *magenta = solidPixels(UIColor.magentaColor, 300), *cyan = solidPixels(UIColor.cyanColor, 600);
    runScript(@[
        @[@3, ^{
            [self expect:ordinary() && !SGRPlayerStillOn() && !scrimShown() step:@"switched off, a track with no clip"
                  detail:[NSString stringWithFormat:@"%@, scrim %@", ordinary() ? @"the ordinary cover over Fluid" : @"something over the cover",
                          scrimShown() ?: @"none"]];
            NSLog(@"[harness] still: screenshot the ordinary cover now");
        }],
        @[@2, ^{
            setStill(YES);
            UIView *still = stillView();
            [still layoutIfNeeded];
            CALayer *picture = [still valueForKey:@"_still"];
            BOOL own = stillPicture() && stillPicture() == SGRNowPlayingArtwork(NULL, NULL).CGImage;
            CGFloat width = picture.bounds.size.width, tall = picture.bounds.size.height;
            [self expect:still && own && self->_covers.layer.mask && fabs(tall - round(width * 4 / 3)) < 1 && [still valueForKey:@"_dim"]
                    step:@"switched on: the cover as the still"
                  detail:[NSString stringWithFormat:@"%@, the Kit's cover %@, cover %@, picture %.0fx%.0f", stillName(), own ? @"yes" : @"no",
                          self->_covers.layer.mask ? @"hidden" : @"shown", width, tall]];
            CGPoint middle = [self.window convertPoint:CGPointMake(CGRectGetMidX(self->_tilt.bounds), CGRectGetMidY(self->_tilt.bounds)) fromView:self->_tilt];
            UIView *hit = [self.window hitTest:middle withEvent:nil];
            [self expect:[hit isDescendantOfView:self->_tilt] step:@"a tap on the hidden cover"
                  detail:[NSString stringWithFormat:@"lands on %@", NSStringFromClass(hit.class)]];
            // 45% black at the top, gone 76 pt under the safe area's top (the design review's numbers).
            NSString *want = [NSString stringWithFormat:@"0.45 to %.0f pt", self.window.safeAreaInsets.top + 76];
            [self expect:[scrimShown() isEqualToString:want] step:@"the still's scrim"
                  detail:[NSString stringWithFormat:@"%@, want %@", scrimShown() ?: @"none", want]];
            first = still;
        }],
        @[@2, ^{
            UIVisualEffectView *seam = [stillView() valueForKey:@"_seamBlur"];
            [self expect:stillView() && fieldCovered() && !seam.effect step:@"faded in" detail:[NSString stringWithFormat:@"field %@, seam blur %@",
                  fieldCovered() ? @"covered" : @"drawn", seam.effect ? @"on" : @"off"]];
            NSLog(@"[harness] still: screenshot the still now");
        }],
        // Time for the screenshot before the lyrics open.
        @[@4, ^{ SGRPlayerToggleLyrics(); }],
        @[@1.5, ^{
            BOOL blurred = ((UIView *)[stillView() valueForKey:@"_picture"]).layer.filters.count > 0;
            [self expect:SGRPlayerLyricsOpen() && blurred step:@"behind the lyrics" detail:blurred ? @"the still blurred" : @"the still sharp"];
            SGRPlayerToggleLyrics();
        }],
        @[@1.5, ^{
            // The same track and cover told again: the still is kept, not made again.
            SGRHarnessSetTrack(@"spotify:track:harnessA", imageURI(@"aaaa"), NO);
            SGRPlayerStillChanged();
            // A still made again would leave the first fading out beside a new one.
            NSUInteger views = [SGRPlayerField().subviews indexesOfObjectsPassingTest:^BOOL(UIView *view, NSUInteger i, BOOL *stop) {
                return [NSStringFromClass(view.class) isEqualToString:@"SGRPlayerMotionView"];
            }].count;
            [self expect:stillView() == first && views == 1 step:@"the same cover again"
                  detail:[NSString stringWithFormat:@"%@, %lu views", stillView() == first ? @"the same still" : @"another still", (unsigned long)views]];
            // Two skips in a row, each cover answering late, the first one's last.
            serve(imageURI(@"bbbb"), green, 1.0, NO);
            serve(imageURI(@"cccc"), blue, 1.5, NO);
            [self playTrack:@"spotify:track:harnessB" image:imageURI(@"bbbb")];
        }],
        @[@0.1, ^{ [self playTrack:@"spotify:track:harnessC" image:imageURI(@"cccc")]; }],
        @[@0.8, ^{
            [self expect:ordinary() step:@"skipped twice, the cover not in" detail:stillPicture() ? stillName() : @"the ordinary cover"];
        }],
        @[@1.6, ^{
            [self expect:[stillName() isEqualToString:@"blue 600 px"] step:@"the last track's cover in" detail:stillName()];
            serve(imageURI(@"dddd"), yellow, 0.2, NO);
            [self playTrack:@"spotify:track:harnessD" image:imageURI(@"dddd")];
            [self showOnScreen:yellow];
        }],
        @[@1.5, ^{
            [self expect:ordinary() && [colorName(SGRNowPlayingArtwork(NULL, NULL)) isEqualToString:@"yellow"] step:@"a cover 299 px wide"
                  detail:ordinary() ? @"the ordinary cover" : stillName()];
            // The screens' small cover first, the 300 px one late.
            serve(imageURI(@"eeee"), magenta, 2.0, NO);
            [self playTrack:@"spotify:track:harnessE" image:imageURI(@"eeee")];
            [self showOnScreen:thumb];
        }],
        @[@1, ^{
            UIImage *kit = SGRNowPlayingArtwork(NULL, NULL);
            [self expect:ordinary() && kit.size.width * kit.scale == 120 step:@"the 120 px thumbnail only"
                  detail:[NSString stringWithFormat:@"%@, the Kit's cover %.0f px", ordinary() ? @"the ordinary cover" : stillName(), kit.size.width * kit.scale]];
        }],
        @[@2, ^{
            [self expect:[stillName() isEqualToString:@"magenta 300 px"] step:@"the 300 px cover came late" detail:stillName()];
            // Its Canvas turns up: the clip replaces the still.
            setenv("HARNESS_CANVAS", [NSString stringWithFormat:@"https://canvas.harness/still-%d.mp4", getpid()].UTF8String, 1);
            SGRHarnessSetTrack(@"spotify:track:harnessE", imageURI(@"eeee"), NO);
        }],
        @[@2.5, ^{
            UIView *motion = motionView();
            BOOL clip = SGRPlayerMotionShowing() && motion && [motion valueForKey:@"_player"] && !stillView();
            [self expect:clip step:@"a clip came late" detail:clip ? @"the clip over the still's place" : stillName()];
            [self expect:clip && !scrimShown() step:@"no scrim over the clip" detail:scrimShown() ?: @"none"];
            unsetenv("HARNESS_CANVAS");
            serve(imageURI(@"ffff"), cyan, 0.2, NO);
            [self playTrack:@"spotify:track:harnessF" image:imageURI(@"ffff")];
        }],
        @[@1.5, ^{
            [self expect:[stillName() isEqualToString:@"cyan 600 px"] step:@"the next track without a clip" detail:stillName()];
            background(SGRPlayerBackgroundBlack);
        }],
        @[@1.5, ^{
            [self expect:!SGRPlayerMotionShowing() && SGRPlayerBackdropShowing() step:@"black wins"
                  detail:[NSString stringWithFormat:@"%@, black %@", stillName(), SGRPlayerBackdropShowing() ? @"over the field" : @"missing"]];
            background(SGRPlayerBackgroundPhoto);
        }],
        @[@1.5, ^{
            [self expect:!SGRPlayerMotionShowing() && SGRPlayerBackdropShowing() step:@"the photo wins" detail:stillName()];
            background(SGRPlayerBackgroundAnimated);
        }],
        @[@1.5, ^{
            [self expect:[stillName() isEqualToString:@"cyan 600 px"] step:@"Animated again" detail:stillName()];
            SGRPlayerMenuSetBackground(SGRPlayerBackgroundVisualiser);
        }],
        @[@1.5, ^{
            [self expect:!SGRPlayerMotionShowing() && SGRPlayerVisualiserShowing() step:@"the Visualizer, no still" detail:stillName()];
            SGRPlayerMenuSetBackground(SGRPlayerBackgroundAnimated);
        }],
        @[@1.5, ^{
            [self expect:[stillName() isEqualToString:@"cyan 600 px"] step:@"back from the Visualizer" detail:stillName()];
            // Low Power Mode, which the process is made to report (Reduce Motion takes the same path, motionAllowed).
            Class info = object_getClass(NSProcessInfo.processInfo);
            for (NSString *name in @[@"isLowPowerModeEnabled", @"lowPowerModeEnabled"]) {
                Method method = class_getInstanceMethod(info, NSSelectorFromString(name));
                if (method) method_setImplementation(method, imp_implementationWithBlock(^BOOL(id process) { return lowPower; }));
            }
            lowPower = YES;
            [NSNotificationCenter.defaultCenter postNotificationName:NSProcessInfoPowerStateDidChangeNotification object:nil];
        }],
        @[@1.5, ^{
            [self expect:ordinary() step:@"Low Power Mode keeps the cover" detail:ordinary() ? @"the ordinary cover" : stillName()];
            // The Kit telling of a cover meanwhile does not bring the still back either.
            [NSNotificationCenter.defaultCenter postNotificationName:SGRNowPlayingArtworkDidChangeNotification object:nil];
            [self expect:ordinary() step:@"a cover in under Low Power Mode" detail:ordinary() ? @"the ordinary cover" : stillName()];
            lowPower = NO;
            [NSNotificationCenter.defaultCenter postNotificationName:NSProcessInfoPowerStateDidChangeNotification object:nil];
        }],
        @[@1.5, ^{
            [self expect:[stillName() hasPrefix:@"cyan"] step:@"Low Power Mode off" detail:stillName()];
            setStill(NO);
        }],
        @[@1.5, ^{
            // Faded out with the still.
            [self expect:ordinary() && !scrimShown() step:@"switched off again"
                  detail:[NSString stringWithFormat:@"%@, scrim %@", ordinary() ? @"the ordinary cover" : stillName(), scrimShown() ?: @"none"]];
            NSLog(@"[harness] still checks: %lu of %lu right -- %@", (unsigned long)(self->_checks - self->_failures), (unsigned long)self->_checks,
                  self->_failures ? @"FAIL" : @"PASS");
            exit(self->_failures ? 1 : 0);
        }],
    ], 0);
}

#pragma mark - Apple Music's catalog

static NSData *catalogAlbums(NSArray<NSArray<NSString *> *> *albums) {
    NSMutableArray *data = [NSMutableArray array];
    for (NSArray<NSString *> *album in albums) {
        [data addObject:@{@"attributes": @{@"name": album[0], @"artistName": album[1],
                                           @"editorialVideo": @{@"motionTallVideo3x4": @{@"video": album[2]}}}}];
    }
    return [NSJSONSerialization dataWithJSONObject:@{@"results": @{@"albums": @{@"data": data}}} options:0 error:nil];
}

static NSString *termOf(NSURL *url) {
    for (NSURLQueryItem *item in [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO].queryItems) {
        if ([item.name isEqualToString:@"term"]) return item.value;
    }
    return nil;
}

// The album search's term without the edition, the album of the same name before another edition, and the pause
// after a 429: nothing asked of the catalog for the next album, which finds nothing at once.
- (void)runCatalogChecks {
    sg_catalogAsked = [NSMutableArray array];
    sg_canvasAsked = [NSMutableArray array];
    // A web player token that has not run out, so no browse page is read.
    NSString *(^part)(NSString *) = ^NSString *(NSString *json) {
        NSString *base = [[json dataUsingEncoding:NSUTF8StringEncoding] base64EncodedStringWithOptions:0];
        return [[[base stringByReplacingOccurrencesOfString:@"+" withString:@"-"] stringByReplacingOccurrencesOfString:@"/" withString:@"_"]
                stringByReplacingOccurrencesOfString:@"=" withString:@""];
    };
    NSString *token = [NSString stringWithFormat:@"%@.%@.c2ln", part(@"{\"alg\":\"none\"}"), part(@"{\"iss\":\"AMPWebPlay\",\"exp\":4102444800}")];
    [NSUserDefaults.standardUserDefaults setObject:token forKey:@"spotifyglass.motion.token"];

    NSDictionary<NSString *, NSString *> *names = @{
        @"Abbey Road (Remastered)": @"Abbey Road", @"Rumours - 2004 Remaster": @"Rumours", @"[Deluxe]": @"[Deluxe]",
        @"Thriller 25 [Super Deluxe Edition] (Remastered)": @"Thriller 25", @"Midnights": @"Midnights",
    };
    __block BOOL namesRight = YES;
    [names enumerateKeysAndObjectsUsingBlock:^(NSString *name, NSString *searched, BOOL *stop) {
        if (![SGMotionSearchName(name) isEqualToString:searched]) {
            namesRight = NO;
            NSLog(@"[harness] catalog: %@ searched as \"%@\", not \"%@\"", name, SGMotionSearchName(name), searched);
        }
    }];
    [self expect:namesRight step:@"search names" detail:namesRight ? @"editions taken off" : @"see above"];

    sg_catalogBody = catalogAlbums(@[@[@"Midnights", @"Taylor Swift", @"https://canvas.harness/standard.m3u8"],
                                     @[@"Midnights (3am Edition)", @"Taylor Swift", @"https://canvas.harness/3am.m3u8"]]);
    after(1, ^{ SGMotionAlbumCover(@"Taylor Swift", @"Midnights (3am Edition)", 600, ^(NSURL *file) {}); });
    after(2.5, ^{
        NSString *term = termOf(sg_catalogAsked.firstObject), *master = sg_canvasAsked.firstObject.lastPathComponent;
        [self expect:sg_catalogAsked.count == 1 && [term isEqualToString:@"Taylor Swift Midnights"] step:@"the term"
              detail:[NSString stringWithFormat:@"%lu asked, \"%@\"", (unsigned long)sg_catalogAsked.count, term]];
        [self expect:[master isEqualToString:@"3am.m3u8"] step:@"the album of the same name first" detail:master ?: @"none asked"];
        sg_catalogStatus = 429;
        SGMotionAlbumCover(@"Artist X", @"Album One", 600, ^(NSURL *file) {});
    });
    __block BOOL answered = NO;
    after(4, ^{
        [self expect:sg_catalogAsked.count == 2 step:@"a 429" detail:[NSString stringWithFormat:@"%lu asked", (unsigned long)sg_catalogAsked.count]];
        sg_catalogStatus = 200;
        SGMotionAlbumCover(@"Artist X", @"Album Two", 600, ^(NSURL *file) { answered = !file; });
    });
    after(5, ^{
        [self expect:sg_catalogAsked.count == 2 && answered step:@"paused after it"
              detail:[NSString stringWithFormat:@"%lu asked, the next album %@", (unsigned long)sg_catalogAsked.count, answered ? @"found nothing at once" : @"waits"]];
        NSLog(@"[harness] catalog checks: %lu of %lu right -- %@", (unsigned long)(self->_checks - self->_failures), (unsigned long)self->_checks,
              self->_failures ? @"FAIL" : @"PASS");
    });
}

static UIView *firstOfClass(UIView *root, NSString *name) {
    if ([NSStringFromClass(root.class) isEqualToString:name]) return root;
    for (UIView *sub in root.subviews) {
        UIView *found = firstOfClass(sub, name);
        if (found) return found;
    }
    return nil;
}

// What the Player page's card (PlayerSettings.m, SGRPlayerPreview) draws that is cut off or in another part's room at its
// size: nil when the header, the cover and the words, the progress, the times and the transport row each sit whole in
// their own band, inside the card.
static NSString *cardClipping(UIView *card) {
    [card layoutIfNeeded];
    CGRect bounds = CGRectInset(card.bounds, -0.5, -0.5);
    NSMutableArray<NSString *> *wrong = [NSMutableArray array];
    NSMutableDictionary<NSString *, NSValue *> *frames = [NSMutableDictionary dictionary];
    for (NSString *name in @[@"_cover", @"_chip", @"_title", @"_artist", @"_more", @"_star", @"_progress", @"_elapsed", @"_remaining",
                             @"_shuffle", @"_previous", @"_play", @"_next", @"_repeat", @"_demoButton"]) {
        UIView *view = [card valueForKey:name];
        if (view.hidden || view.alpha < 0.01) continue;
        CGRect frame = [view.superview convertRect:view.frame toView:card];
        frames[name] = [NSValue valueWithCGRect:frame];
        if (!CGRectContainsRect(bounds, frame) || frame.size.width < 1 || frame.size.height < 1)
            [wrong addObject:[NSString stringWithFormat:@"%@ %@ not whole in the card", name, NSStringFromCGRect(frame)]];
    }
    CGRect (^at)(NSString *) = ^CGRect(NSString *name) { return frames[name] ? frames[name].CGRectValue : CGRectNull; };
    CGRect words = CGRectUnion(at(@"_chip"), CGRectUnion(at(@"_title"), at(@"_artist")));
    CGRect upper = CGRectUnion(words, at(@"_cover"));
    CGRect transport = CGRectNull;
    for (NSString *name in @[@"_shuffle", @"_previous", @"_play", @"_next", @"_repeat"]) transport = CGRectUnion(transport, at(name));
    // The header's band is the album's name's, laid out whether or not it is shown.
    UIView *context = [card valueForKey:@"_context"];
    if (CGRectGetMinY(upper) < CGRectGetMaxY([context.superview convertRect:context.frame toView:card]) - 0.5) [wrong addObject:@"the cover or the words under the header"];
    if (CGRectGetMaxY(upper) > CGRectGetMinY(at(@"_progress")) + 0.5) [wrong addObject:@"the cover or the words over the progress"];
    if (CGRectGetMaxY(CGRectUnion(at(@"_elapsed"), at(@"_remaining"))) > CGRectGetMinY(transport) + 0.5) [wrong addObject:@"the times over the transport row"];
    if (CGRectGetMaxX(words) > CGRectGetMinX(at(@"_more")) + 0.5) [wrong addObject:@"the words under the ⋯"];
    // Star add button on: the player's star stands before the ⋯, and the words end before it.
    if (frames[@"_star"] && CGRectGetMaxX(words) > CGRectGetMinX(at(@"_star")) + 0.5) [wrong addObject:@"the words under the star"];
    if (frames[@"_star"] && CGRectGetMaxX(at(@"_star")) > CGRectGetMinX(at(@"_more")) + 0.5) [wrong addObject:@"the star under the ⋯"];
    if (CGRectIntersectsRect(CGRectInset(at(@"_cover"), 0.5, 0.5), words)) [wrong addObject:@"the cover over the words"];
    NSArray<NSString *> *row = @[@"_shuffle", @"_previous", @"_play", @"_next", @"_repeat"];
    for (NSUInteger i = 0; i + 1 < row.count; i++) {
        if (frames[row[i]] && frames[row[i + 1]] && CGRectIntersectsRect(at(row[i]), at(row[i + 1]))) [wrong addObject:[NSString stringWithFormat:@"%@ over %@", row[i], row[i + 1]]];
    }
    UILabel *chipLabel = [card valueForKey:@"_chipLabel"];
    if (frames[@"_chip"] && chipLabel.intrinsicContentSize.width > chipLabel.bounds.size.width + 0.5) [wrong addObject:@"Switch to video cut short"];
    return wrong.count ? [wrong componentsJoinedByString:@"; "] : nil;
}

// The track the player has and whether it is paused: what the card must never change.
static NSString *playerNow(void) {
    SPTPlayerState *state = SGPlayerState();
    return [NSString stringWithFormat:@"%@ %@", SGURIString(state.track.URI), state.isPaused ? @"paused" : @"playing"];
}

// The mod's stored settings, to tell which ones a step changed.
static NSDictionary<NSString *, id> *storedSettings(void) {
    NSMutableDictionary<NSString *, id> *settings = [NSMutableDictionary dictionary];
    [NSUserDefaults.standardUserDefaults.dictionaryRepresentation enumerateKeysAndObjectsUsingBlock:^(NSString *key, id value, BOOL *stop) {
        if ([key hasPrefix:@"spotifyglass."] && ![key isEqualToString:@"spotifyglass.lastTrack"] && ![key isEqualToString:@"spotifyglass.settings.seenNew"]) settings[key] = value;
    }];
    return settings;
}

static NSArray<NSString *> *changedSettings(NSDictionary *before, NSDictionary *after) {
    NSMutableSet<NSString *> *keys = [NSMutableSet setWithArray:before.allKeys];
    [keys addObjectsFromArray:after.allKeys];
    NSMutableArray<NSString *> *changed = [NSMutableArray array];
    for (NSString *key in keys) if (![before[key] isEqual:after[key]]) [changed addObject:key];
    return [changed sortedArrayUsingSelector:@selector(compare:)];
}

// Moments both Song without a clip switches were stored on, counted as each write lands.
static NSUInteger sg_bothOn;

// Performance/lifetime probes at UIKit's layout/geometry and the palette service boundaries.
static BOOL sg_watchPreviewWork, sg_watchPreviewPalette, sg_insidePreviewArtwork;
static __weak UIView *sg_watchedPreview;
static NSHashTable<UIView *> *sg_watchedBackgrounds;
static NSHashTable<UIView *> *sg_watchedTextSizeViews;
static NSUInteger sg_previewLayouts, sg_backgroundResizes, sg_previewMeasurements, sg_previewPaletteRequests;

static void installSettingsWorkProbes(void) {
    Class preview = NSClassFromString(@"SGRPlayerPreview");
    Method layout = class_getInstanceMethod(preview, @selector(layoutSubviews));
    IMP oldLayout = method_getImplementation(layout);
    method_setImplementation(layout, imp_implementationWithBlock(^(UIView *view) {
        if (sg_watchPreviewWork && view == sg_watchedPreview) sg_previewLayouts++;
        ((void (*)(id, SEL))oldLayout)(view, @selector(layoutSubviews));
    }));
    for (NSString *name in @[@"setFrame:", @"setBounds:"]) {
        SEL selector = NSSelectorFromString(name);
        Method method = class_getInstanceMethod(UIView.class, selector);
        IMP original = method_getImplementation(method);
        method_setImplementation(method, imp_implementationWithBlock(^(UIView *view, CGRect rect) {
            CGSize before = view.bounds.size;
            ((void (*)(id, SEL, CGRect))original)(view, selector, rect);
            if (sg_watchPreviewWork && [sg_watchedBackgrounds containsObject:view] && !CGSizeEqualToSize(before, view.bounds.size))
                sg_backgroundResizes++;
        }));
    }
    for (Class type in @[UIButton.class, UILabel.class]) {
        SEL selector = @selector(sizeThatFits:);
        Method method = class_getInstanceMethod(type, selector);
        IMP original = method_getImplementation(method);
        IMP probe = imp_implementationWithBlock(^CGSize(UIView *view, CGSize size) {
            if (sg_watchPreviewWork && [sg_watchedTextSizeViews containsObject:view]) sg_previewMeasurements++;
            return ((CGSize (*)(id, SEL, CGSize))original)(view, selector, size);
        });
        if (!class_addMethod(type, selector, probe, method_getTypeEncoding(method))) method_setImplementation(method, probe);
    }
    Method artwork = class_getInstanceMethod(NSClassFromString(@"SGRVisualiserView"), @selector(artworkChanged));
    IMP oldArtwork = method_getImplementation(artwork);
    method_setImplementation(artwork, imp_implementationWithBlock(^(UIView *view) {
        BOOL previous = sg_insidePreviewArtwork;
        sg_insidePreviewArtwork = [[view valueForKey:@"sample"] boolValue];
        ((void (*)(id, SEL))oldArtwork)(view, @selector(artworkChanged));
        sg_insidePreviewArtwork = previous;
    }));
    SEL selector = @selector(paletteForImage:request:completion:);
    Method palette = class_getClassMethod(SGRPalette.class, selector);
    IMP oldPalette = method_getImplementation(palette);
    method_setImplementation(palette, imp_implementationWithBlock(^(id owner, UIImage *image, SGRPaletteRequest request, void (^done)(SGRPalette *)) {
        if (sg_watchPreviewPalette && sg_insidePreviewArtwork) sg_previewPaletteRequests++;
        ((void (*)(id, SEL, UIImage *, SGRPaletteRequest, void (^)(SGRPalette *)))oldPalette)(owner, selector, image, request, done);
    }));
}

// The redesign's Player page over the player, with the clip of `motion` in. Song without a clip: what it reads from
// the two switches, and each choice leaving the other off at every write; the pinned card, its demo, and that neither
// sends the player anything; the card refreshed for another track with late answers dropped, paused while the page
// is covered, stopped once it is closed; the Buttons chips; and the card and the chips laid out whole at narrow widths
// and the largest text.
- (void)runSettingsChecks {
    installSettingsWorkProbes();
    UIViewController *headerUnit = _units.firstObject;
    static char contextKey, closeKey, moreKey;
    UIView *context = SGRFindByIdentifier(headerUnit.view, @"now-playing-navigation-unit-title-label", &contextKey);
    UIView *close = SGRFindByIdentifier(headerUnit.view, @"now-playing-minimize-button", &closeKey);
    UIView *more = SGRFindByIdentifier(headerUnit.view, @"Context menu", &moreKey);
    CGRect closeFrame = close.frame, moreFrame = more.frame, contextFrame = context.frame;
    // Nothing stored hides it, as the Music app's header has no context line.
    BOOL defaultConcealed = context.alpha == 0 && !context.isAccessibilityElement && context.accessibilityElementsHidden;
    SGModRow *contextRow = nil;
    for (SGModSection *section in ((SGModPage *)SGRPlayerSettingsPage(@[])).sections)
        for (SGModRow *row in section.rows)
            if ([row.title isEqualToString:@"Hide where it plays from"]) contextRow = row;
    SGSetEnabled(SGRKeyPlayerHideContext, YES);
    if (contextRow.changed) contextRow.changed(YES);
    [headerUnit.view layoutIfNeeded];
    BOOL concealed = context.alpha == 0 && !context.isAccessibilityElement && context.accessibilityElementsHidden
        && !context.hidden && CGRectEqualToRect(context.frame, contextFrame);
    SGSetEnabled(SGRKeyPlayerHideContext, NO);
    if (contextRow.changed) contextRow.changed(NO);
    [headerUnit.view layoutIfNeeded];
    [self expect:contextRow && defaultConcealed && concealed && context.alpha == 1
                 && context.isAccessibilityElement && !context.accessibilityElementsHidden
                 && CGRectEqualToRect(close.frame, closeFrame) && CGRectEqualToRect(more.frame, moreFrame)
            step:@"context hidden by default; its switch hides and restores text and VoiceOver live, keeping header slots"
          detail:NSStringFromCGRect(context.frame)];
    // Nothing stored again, so the next run on this install finds the default too.
    [NSUserDefaults.standardUserDefaults removeObjectForKey:SGRKeyPlayerHideContext];
    SGPrefsChanged();
    __block UINavigationController *nav;
    __block __weak UIView *closedCard;
    __block __weak UIView *closedDecoder;
    __block __weak UIView *closedVisualiser;
    __block NSUInteger latePreviewCallbacks = 0;
    SGModPage *(^page)(void) = ^{ return (SGModPage *)nav.viewControllers.firstObject; };
    UITableView *(^table)(void) = ^{ return page().tableView; };
    UIView *(^card)(void) = ^{ return firstOfClass(table(), @"SGRPlayerPreview"); };
    UISegmentedControl *(^segments)(void) = ^{ return (UISegmentedControl *)firstOfClass(table().tableHeaderView, @"UISegmentedControl"); };
    void (^pick)(NSUInteger) = ^(NSUInteger index) {
        segments().selectedSegmentIndex = (NSInteger)index;
        [segments() sendActionsForControlEvents:UIControlEventValueChanged];
    };
    SGModRow *(^rowTitled)(NSString *) = ^SGModRow *(NSString *title) {
        for (SGModSection *section in page().sections) for (SGModRow *row in section.rows) if ([row.title isEqualToString:title]) return row;
        return nil;
    };
    NSIndexPath *(^pathOf)(SGModRow *) = ^NSIndexPath *(SGModRow *row) {
        NSArray<NSArray *> *shown = [page() valueForKey:@"_shown"];
        for (NSUInteger s = 0; s < shown.count; s++) {
            NSUInteger r = [shown[s] indexOfObjectIdenticalTo:row];
            if (r != NSNotFound) return [NSIndexPath indexPathForRow:(NSInteger)r inSection:(NSInteger)s];
        }
        return nil;
    };
    UITableViewCell *(^cellOf)(SGModRow *) = ^UITableViewCell *(SGModRow *row) {
        NSIndexPath *path = pathOf(row);
        if (!path) return nil;
        [table() scrollToRowAtIndexPath:path atScrollPosition:UITableViewScrollPositionBottom animated:NO];
        [table() layoutIfNeeded];
        return [table() cellForRowAtIndexPath:path];
    };
    SGModRow *(^noClip)(void) = ^{ return rowTitled(@"Song without a clip"); };
    // A choice of Song without a clip as its menu makes it: the row's block, then the page read again.
    void (^choose)(NSInteger) = ^(NSInteger index) {
        noClip().chosen(index);
        [table() reloadData];
    };
    void (^checkScrollWork)(void) = ^{
        sg_watchedPreview = card();
        sg_watchedBackgrounds = [NSHashTable weakObjectsHashTable];
        sg_watchedTextSizeViews = [NSHashTable weakObjectsHashTable];
        [sg_watchedTextSizeViews addObject:[card() valueForKey:@"_demoButton"]];
        [sg_watchedTextSizeViews addObject:[card() valueForKey:@"_chipLabel"]];
        for (NSString *type in @[@"SGRArtworkField", @"SGRPlayerMotionView", @"SGRVisualiserView"]) {
            UIView *view = firstOfClass(card(), type);
            if (view) [sg_watchedBackgrounds addObject:view];
        }
        [table() setContentOffset:CGPointMake(0, -table().adjustedContentInset.top) animated:NO];
        [page().view layoutIfNeeded];
        [card() layoutIfNeeded];
        sg_previewLayouts = sg_backgroundResizes = sg_previewMeasurements = 0;
        sg_watchPreviewWork = YES;
        for (NSInteger y = 0; y <= 280; y += 20) {
            [table() setContentOffset:CGPointMake(0, y - table().adjustedContentInset.top) animated:NO];
            [page().view setNeedsLayout];
            [page().view layoutIfNeeded];
            [card() layoutIfNeeded];
        }
        sg_watchPreviewWork = NO;
        [self expect:card().bounds.size.height == 236 && sg_backgroundResizes == 0 && sg_previewMeasurements == 0
                step:@"collapsing does no background resize or text measurement"
              detail:[NSString stringWithFormat:@"%lu resizes, %lu measurements", (unsigned long)sg_backgroundResizes, (unsigned long)sg_previewMeasurements]];
        sg_previewLayouts = sg_backgroundResizes = sg_previewMeasurements = 0;
        sg_watchPreviewWork = YES;
        for (NSInteger y = 300; y <= 600; y += 20) {
            [table() setContentOffset:CGPointMake(0, y - table().adjustedContentInset.top) animated:NO];
            [page().view setNeedsLayout];
            [page().view layoutIfNeeded];
            [card() layoutIfNeeded];
        }
        sg_watchPreviewWork = NO;
        [self expect:sg_previewLayouts == 0 && sg_backgroundResizes == 0 && sg_previewMeasurements == 0
                step:@"compact scrolling does no preview layout or background resize"
              detail:[NSString stringWithFormat:@"%lu layouts, %lu resizes, %lu measurements", (unsigned long)sg_previewLayouts,
                      (unsigned long)sg_backgroundResizes, (unsigned long)sg_previewMeasurements]];
        sg_watchedPreview = nil;
        sg_watchedBackgrounds = nil;
        sg_watchedTextSizeViews = nil;
    };
    SGModRow *(^buttonsRow)(void) = ^{ return rowTitled(@"Buttons"); };
    NSArray<UIButton *> *(^chips)(void) = ^NSArray<UIButton *> *{
        NSMutableArray<UIButton *> *found = [NSMutableArray array];
        for (UIView *view in cellOf(buttonsRow()).contentView.subviews) if ([view isKindOfClass:UIButton.class]) [found addObject:(UIButton *)view];
        return found;
    };
    UIView *(^motionOn)(void) = ^{ return firstOfClass(card(), @"SGRPlayerMotionView"); };
    UIView *(^hillsOn)(void) = ^{ return firstOfClass(card(), @"SGRVisualiserView"); };
    BOOL (^stillShown)(void) = ^BOOL { return ![[card() valueForKey:@"_still"] isHidden] && [[card() valueForKey:@"_cover"] alpha] < 0.01; };
    BOOL (^demo)(void) = ^BOOL { return [[card() valueForKey:@"demo"] boolValue]; };
    NSString *(^cardState)(void) = ^{
        SGRArtworkField *field = (SGRArtworkField *)firstOfClass(card(), @"SGRArtworkField");
        return [NSString stringWithFormat:@"card %@, demo %d, clip %@, hills %@, full-screen cover %@, field held %d; player %@, %lu commands; \"%@\"",
                NSStringFromCGRect(card().frame), demo(), motionOn() ? @"on" : @"off", hillsOn() ? @"on" : @"off", stillShown() ? @"on" : @"off",
                field.motionHeld, playerNow(), (unsigned long)SGRHarnessPlayerCommands(), [[card() valueForKey:@"_canvas"] accessibilityValue]];
    };
    BOOL (^stored)(NSString *) = ^BOOL(NSString *key) { return [NSUserDefaults.standardUserDefaults boolForKey:key]; };
    NSString *(^switches)(void) = ^{
        return [NSString stringWithFormat:@"full-screen cover %@, Visualizer %@", [NSUserDefaults.standardUserDefaults objectForKey:SGRKeyPlayerAnimatedStill] ?: @"unset",
                [NSUserDefaults.standardUserDefaults objectForKey:SGRKeyPlayerAnimatedVisualiser] ?: @"unset"];
    };
    void (^reread)(void) = ^{
        [page() viewWillAppear:NO];
        [table() layoutIfNeeded];
    };
    __block BOOL settingsPresented = NO;
    void (^open)(void) = ^{
        settingsPresented = NO;
        nav = [[UINavigationController alloc] initWithRootViewController:SGRPlayerSettingsPage(@[SGRPlayerButtonsSection()])];
        // Keep the real player in its window: its intentional old-clip handover must not reach the preview.
        nav.modalPresentationStyle = UIModalPresentationOverFullScreen;
        [self.window.rootViewController presentViewController:nav animated:NO completion:^{
            [nav.view layoutIfNeeded];
            NSIndexPath *linePath = pathOf(rowTitled(@"Lyrics Line"));
            SGModRow *size = rowTitled(@"Size");
            HARNESS_CHECK(size && linePath && [pathOf(size) isEqual:[NSIndexPath indexPathForRow:linePath.row + 1 inSection:linePath.section]]);
            HARNESS_CHECK(([size.menu isEqual:@[@"19 pt", @"17 pt"]]));
            size.chosen(size.menu.count - 1);
            HARNESS_CHECK(SGRPlayerLineSmall() && [size.value() isEqual:@"17 pt"]);
            size.chosen(0);
            HARNESS_CHECK([size.value() isEqual:@"19 pt"]);
            if (getenv("HARNESS_SIZE_SCREENSHOT")) {
                cellOf(size);
                NSLog(@"[harness] size-settings ready");
                after(3, ^{ exit(0); });
                return;
            }
            settingsPresented = YES;
        }];
    };
    // The card's height in the window, and its top against the navigation bar's foot.
    NSString *(^pinned)(void) = ^{
        CGRect frame = [card() convertRect:card().bounds toView:self.window];
        return [NSString stringWithFormat:@"card %@ in the window, bar's foot %.0f, offset %.0f", NSStringFromCGRect(frame),
                CGRectGetMaxY([nav.navigationBar convertRect:nav.navigationBar.bounds toView:self.window]), table().contentOffset.y];
    };
    CGFloat (^cardTop)(void) = ^CGFloat { return CGRectGetMinY([card() convertRect:card().bounds toView:self.window]); };
    CGFloat (^barFoot)(void) = ^CGFloat { return CGRectGetMaxY([nav.navigationBar convertRect:nav.navigationBar.bounds toView:self.window]); };
    __block NSString *playerBefore;
    __block NSDictionary *settingsBefore;
    __block NSURL *fileC;
    __block SGRHarnessPicture *lateImageB, *lateImageD, *lateImageE;
    __block BOOL settingsDismissed = NO;

    [NSNotificationCenter.defaultCenter addObserverForName:NSUserDefaultsDidChangeNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
        if (stored(SGRKeyPlayerAnimatedStill) && stored(SGRKeyPlayerAnimatedVisualiser)) sg_bothOn++;
    }];

    NSMutableArray<NSArray *> *script = [NSMutableArray array];
    void (^step)(NSTimeInterval, dispatch_block_t) = ^(NSTimeInterval delay, dispatch_block_t block) { [script addObject:@[@(delay), block]]; };

    void (^when)(BOOL (^)(void), dispatch_block_t) = ^(BOOL (^ready)(void), dispatch_block_t block) {
        [script addObject:@[[ready copy], [block copy]]];
    };
    when(^BOOL { return SGRPlayerMotionShowing(); }, ^{ open(); });
    when(^BOOL { return settingsPresented && motionOn() != nil && card().window != nil; }, ^{
        playerBefore = playerNow();
        CGFloat height = card().frame.size.height;
        BOOL inTable = card().window && card().superview.superview == table() && fabs(cardTop() - barFoot() - 8) < 1;
        BOOL under = CGRectGetMinY([segments() convertRect:segments().bounds toView:self.window]) > CGRectGetMaxY([card() convertRect:card().bounds toView:self.window]);
        [self expect:inTable && under && fabs(height - 480) < 1 && segments().numberOfSegments == 5 step:@"the card pinned over the rows, expanded, the backgrounds under it"
              detail:[NSString stringWithFormat:@"%@, height %.0f, segments %@", pinned(), height, NSStringFromCGRect(segments().frame)]];
        [self expect:motionOn() && !demo() && [[[card() valueForKey:@"_canvas"] accessibilityValue] isEqualToString:@"Animated background"]
                step:@"Animated: the player's clip on the card" detail:cardState()];
        [self expect:[[[card() valueForKey:@"_title"] text] isEqualToString:@"Loose Canon"]
                     && [[[card() valueForKey:@"_artist"] text] isEqualToString:@"Retrine harness"]
                     && [[[card() valueForKey:@"_elapsed"] text] isEqualToString:@"1:15"]
                     && [[[card() valueForKey:@"_remaining"] text] isEqualToString:@"-2:45"]
                step:@"the actual current song, artist, elapsed and remaining time" detail:cardState()];
        NSString *clipping = cardClipping(card());
        [self expect:!clipping step:@"the expanded card whole" detail:clipping ?: @"every part in its band"];
        UIButton *toggle = [card() valueForKey:@"_demoButton"];
        [self expect:!toggle.hidden && (toggle.accessibilityTraits & UIAccessibilityTraitButton) && [toggle.accessibilityLabel isEqualToString:@"Preview without a clip"]
                     && [[card() valueForKey:@"_canvas"] isAccessibilityElement] && [[[card() valueForKey:@"_canvas"] accessibilityLabel] isEqualToString:@"Player preview"]
                step:@"VoiceOver: the card one element, the demo a button" detail:[NSString stringWithFormat:@"button \"%@\" traits %llu", toggle.accessibilityLabel, toggle.accessibilityTraits]];
        [self expect:[noClip().value() isEqualToString:@"Cover art"] && noClip().menu.count == 3 && pathOf(noClip()) && !rowTitled(@"Full-screen cover without a clip") && !rowTitled(@"Visualizer when there's no clip")
                step:@"one Song without a clip choice, Cover art with both switches unset" detail:[NSString stringWithFormat:@"reads %@ of %@; %@", noClip().value(), noClip().menu, switches()]];
    });
    // Covered by another page, the card does nothing; the background's switches changed meanwhile, as elsewhere.
    step(0, ^{
        closedDecoder = motionOn();
        [nav pushViewController:[UIViewController new] animated:NO];
        [NSUserDefaults.standardUserDefaults setBool:YES forKey:SGRKeyPlayerAnimatedStill];
    });
    when(^BOOL { return nav.topViewController != page() && !nav.transitionCoordinator; }, ^{
        [self expect:![[card() valueForKey:@"_active"] boolValue] && !motionOn() && !hillsOn() step:@"covered: no clip or hills on the card" detail:cardState()];
        [self expect:!closedDecoder step:@"covered: the preview decoder is released" detail:closedDecoder ? @"still retained" : @"released"];
        [nav popViewControllerAnimated:NO];
    });
    when(^BOOL { return nav.topViewController == page() && !nav.transitionCoordinator && motionOn() != nil; }, ^{
        UIButton *menu = (UIButton *)cellOf(noClip()).accessoryView;
        [self expect:[noClip().value() isEqualToString:@"Full-screen cover"] && [menu.accessibilityValue isEqualToString:@"Full-screen cover"] && motionOn()
                step:@"back on the page: Full-screen cover from the switch stored meanwhile, the clip back" detail:[NSString stringWithFormat:@"row \"%@\", menu \"%@\"; %@", noClip().value(), menu.accessibilityValue, cardState()]];
        // Both on, as an older build could leave them: shown as the full-screen cover, and left stored as they are.
        [NSUserDefaults.standardUserDefaults setBool:YES forKey:SGRKeyPlayerAnimatedVisualiser];
        reread();
        [self expect:[noClip().value() isEqualToString:@"Full-screen cover"] && stored(SGRKeyPlayerAnimatedStill) && stored(SGRKeyPlayerAnimatedVisualiser)
                step:@"both stored on: Full-screen cover, nothing rewritten" detail:switches()];
        [NSUserDefaults.standardUserDefaults setBool:NO forKey:SGRKeyPlayerAnimatedStill];
        reread();
        [self expect:[noClip().value() isEqualToString:@"Visualizer"] step:@"the Visualizer's switch alone: Visualizer" detail:switches()];
        [NSUserDefaults.standardUserDefaults removeObjectForKey:SGRKeyPlayerAnimatedVisualiser];
        [NSUserDefaults.standardUserDefaults removeObjectForKey:SGRKeyPlayerAnimatedStill];
        reread();
        sg_bothOn = 0;
    });
    // Each choice through the menu's own block: the other switch off at every write, and the card shows it.
    step(0.5, ^{
        choose(1);
        [self expect:stored(SGRKeyPlayerAnimatedStill) && !stored(SGRKeyPlayerAnimatedVisualiser) && demo() && stillShown() && !motionOn() && !hillsOn()
                     && [playerNow() isEqualToString:playerBefore] && SGRHarnessPlayerCommands() == 0
                step:@"Full-screen cover chosen: its switch alone on, the card shows it" detail:[NSString stringWithFormat:@"%@; %@", switches(), cardState()]];
    });
    step(0, ^{
        choose(2);
        [self expect:!stored(SGRKeyPlayerAnimatedStill) && stored(SGRKeyPlayerAnimatedVisualiser) && demo() && hillsOn() && !stillShown() && !motionOn()
                step:@"Visualizer chosen: its switch alone on, the hills on the card" detail:[NSString stringWithFormat:@"%@; %@", switches(), cardState()]];
    });
    step(0, ^{
        choose(1);
        BOOL fullScreen = stored(SGRKeyPlayerAnimatedStill) && !stored(SGRKeyPlayerAnimatedVisualiser);
        choose(0);
        [self expect:fullScreen && !stored(SGRKeyPlayerAnimatedStill) && !stored(SGRKeyPlayerAnimatedVisualiser) && demo() && !hillsOn() && !stillShown() && !motionOn()
                step:@"Visualizer to Full-screen cover to Cover art: one switch on at most, then none" detail:[NSString stringWithFormat:@"%@; %@", switches(), cardState()]];
        SGModRow *hold = rowTitled(@"Keep background still");
        SGRArtworkField *field = (SGRArtworkField *)firstOfClass(card(), @"SGRArtworkField");
        BOOL offered = pathOf(hold) && !hold.defaultOn && !field.motionHeld;
        SGSetEnabled(SGRKeyPlayerHoldNoClip, YES);
        if (hold.changed) hold.changed(YES);
        BOOL held = field.motionHeld;
        SGSetEnabled(SGRKeyPlayerHoldNoClip, NO);
        if (hold.changed) hold.changed(NO);
        BOOL resumed = !field.motionHeld;
        choose(2);
        [self expect:offered && held && resumed && !pathOf(hold)
                step:@"Cover art can hold and release Fluid live; Visualizer has no still switch" detail:cardState()];
        [self expect:sg_bothOn == 0 step:@"the two switches never stored on together" detail:[NSString stringWithFormat:@"%lu writes left both on", (unsigned long)sg_bothOn]];
    });
    // A tap on the card shows the song as it is again; its button shows it without a clip.
    step(0.5, ^{
        CGRect frame = [card() convertRect:card().bounds toView:self.window];
        SGHarnessTap(self.window, CGPointMake(CGRectGetMidX(frame), CGRectGetMidY(frame)));
    });
    when(^BOOL { return !demo() && motionOn() != nil; }, ^{
        [self expect:!demo() && motionOn() && !hillsOn() && [playerNow() isEqualToString:playerBefore] && SGRHarnessPlayerCommands() == 0
                step:@"a tap on the card: the clip again, the player untouched" detail:cardState()];
    });
    step(0, ^{
        UIView *toggle = [card() valueForKey:@"_demoButton"];
        CGRect frame = [toggle convertRect:toggle.bounds toView:self.window];
        SGHarnessTap(self.window, CGPointMake(CGRectGetMidX(frame), CGRectGetMidY(frame)));
    });
    when(^BOOL { return demo() && hillsOn() != nil; }, ^{
        UIButton *toggle = [card() valueForKey:@"_demoButton"];
        [self expect:demo() && hillsOn() && !motionOn() && (toggle.accessibilityTraits & UIAccessibilityTraitSelected)
                     && [[[card() valueForKey:@"_canvas"] accessibilityValue] isEqualToString:@"Animated background, without a clip: Visualizer"]
                     && [playerNow() isEqualToString:playerBefore] && SGRHarnessPlayerCommands() == 0
                step:@"the Without a clip button: the Visualizer, said as such, the player untouched" detail:cardState()];
        sg_lowPower = YES;
        reportPower();
        [NSNotificationCenter.defaultCenter postNotificationName:NSProcessInfoPowerStateDidChangeNotification object:nil];
    });
    step(0.8, ^{
        SGRArtworkField *field = (SGRArtworkField *)firstOfClass(card(), @"SGRArtworkField");
        [self expect:demo() && !hillsOn() && !stillShown() && !motionOn() && field.motionHeld step:@"Low Power Mode: the cover art held still, as the player shows" detail:cardState()];
        sg_lowPower = NO;
        [NSNotificationCenter.defaultCenter postNotificationName:NSProcessInfoPowerStateDidChangeNotification object:nil];
    });
    step(0.8, ^{
        BOOL back = demo() && hillsOn();
        choose(0);   // The upcoming track transitions exercise the Cover art fallback.
        pick(SGRPlayerBackgroundFluid);
        BOOL ended = !demo() && !hillsOn() && !motionOn();
        pick(SGRPlayerBackgroundAnimated);
        [self expect:back && ended && !demo() && [playerNow() isEqualToString:playerBefore] && SGRHarnessPlayerCommands() == 0
                step:@"Fluid ends the demo, and Animated again does not bring it back" detail:cardState()];
    });
    // Scrolled: compact, still under the bar, whole; the rows go under it.
    step(1, ^{
        // Half of the way the card shrinks: 122 pt of the 244 between 480 and 236.
        [table() setContentOffset:CGPointMake(0, 122 - table().adjustedContentInset.top) animated:NO];
        [table() layoutIfNeeded];
        NSString *halfway = cardClipping(card());
        CGFloat half = card().frame.size.height;
        [table() setContentOffset:CGPointMake(0, 600 - table().adjustedContentInset.top) animated:NO];
        [table() layoutIfNeeded];
        NSString *clipping = cardClipping(card());
        CGFloat height = card().frame.size.height;
        [self expect:card().window && fabs(half - 358) < 1 && !halfway && fabs(height - 236) < 1 && fabs(cardTop() - barFoot() - 8) < 1 && !clipping
                step:@"scrolled: the card shrinking whole, then compact under the bar" detail:[NSString stringWithFormat:@"halfway %.0f (%@); %@, height %.0f; %@", half,
                                                       halfway ?: @"whole", pinned(), height, clipping ?: @"every part in its band"]];
        CGPoint savedOffset = table().contentOffset;
        SGModRow *row = rowTitled(@"Header glass");
        UITableViewCell *cell = cellOf(row);
        CGRect rowFrame = [table() rectForRowAtIndexPath:pathOf(row)];
        // A visible-color marker on an actual row, scrolled under the status/navigation region.
        UIView *marker = [[UIView alloc] initWithFrame:CGRectMake(20, 0, 80, cell.contentView.bounds.size.height)];
        marker.backgroundColor = UIColor.magentaColor;
        [cell.contentView addSubview:marker];
        CGFloat belowPreview = CGRectGetMaxY([card() convertRect:card().bounds toView:table()]) - table().bounds.origin.y + 40;
        [table() setContentOffset:CGPointMake(0, CGRectGetMidY(rowFrame) - belowPreview) animated:NO];
        [table() layoutIfNeeded];
        CGPoint exposedPoint = [marker convertPoint:CGPointMake(40, marker.bounds.size.height / 2) toView:table()];
        NSString *exposed = pixelAtPoint(table(), exposedPoint);
        [table() setContentOffset:CGPointMake(0, CGRectGetMidY(rowFrame) - 50) animated:NO];
        [table() layoutIfNeeded];
        CGPoint point = [marker convertPoint:CGPointMake(40, marker.bounds.size.height / 2) toView:table()];
        UIView *hit = [table() hitTest:point withEvent:nil];
        CGFloat screenY = point.y - table().bounds.origin.y;
        NSString *color = pixelAtPoint(table(), point);
        [self expect:cell.window && screenY > 0 && screenY < 116 && [exposed isEqualToString:@"255,0,255,255"]
                     && [color isEqualToString:@"0,0,0,255"] && ![hit isDescendantOfView:cell]
                step:@"scrolled rows above the preview bottom are neither visible nor hit-testable"
              detail:[NSString stringWithFormat:@"row y %.0f, exposed %@, covered %@, hit %@", screenY, exposed, color, NSStringFromClass(hit.class)]];
        [marker removeFromSuperview];
        [table() setContentOffset:savedOffset animated:NO];
        [table() layoutIfNeeded];
    });
    // The Buttons chips: each one its key alone, the card at once, kept when the page opens again.
    step(0, ^{
        NSArray<UIButton *> *found = chips();
        BOOL whole = found.count == 3;
        for (UIButton *chip in found) {
            BOOL expected = chip != found.lastObject;
            whole = whole && chip.selected == expected && chip.frame.size.height >= 44 && (chip.accessibilityTraits & UIAccessibilityTraitButton)
                    && !!(chip.accessibilityTraits & UIAccessibilityTraitSelected) == expected;
        }
        NSArray *labels = [found valueForKey:@"accessibilityLabel"];
        [self expect:whole && [labels isEqualToArray:@[@"Shuffle", @"Repeat", @"Video"]] && !rowTitled(@"Switch to video") && !rowTitled(@"Shuffle")
                && [[card() valueForKey:@"_chip"] isHidden] step:@"Shuffle and Repeat selected, Video off in the card and preview" detail:[NSString stringWithFormat:@"%@ %@", labels, [found valueForKey:@"frame"]]];
    });
    step(0, ^{
        NSArray<NSString *> *keys = @[SGRKeyPlayerHideShuffle, SGRKeyPlayerHideRepeat, SGKeyHideVideoSwitch];
        BOOL alone = YES;
        NSMutableArray<NSString *> *seen = [NSMutableArray array];
        for (NSUInteger i = 0; i < 3; i++) {
            settingsBefore = storedSettings();
            [chips()[i] sendActionsForControlEvents:UIControlEventTouchUpInside];
            NSArray<NSString *> *changed = changedSettings(settingsBefore, storedSettings());
            alone = alone && [changed isEqualToArray:@[keys[i]]] && [NSUserDefaults.standardUserDefaults objectForKey:keys[i]] && stored(keys[i]) == (i != 2);
            [seen addObject:[changed componentsJoinedByString:@","]];
        }
        // Each chip's name whole once it is drawn unselected, its glyph changed.
        for (UIButton *chip in chips()) {
            [chip layoutIfNeeded];
            if (chip.titleLabel.intrinsicContentSize.width > chip.titleLabel.bounds.size.width + 0.5 || chip.frame.size.height < 44) alone = NO;
            [seen addObject:[NSString stringWithFormat:@"%@ %@", chip.accessibilityLabel, NSStringFromCGRect(chip.frame)]];
        }
        UIView *preview = card();
        [preview layoutIfNeeded];
        CGFloat play = [[preview valueForKey:@"_play"] center].x, previous = [[preview valueForKey:@"_previous"] center].x;
        CGFloat slot = ([preview bounds].size.width - 2 * 16) / 5;
        BOOL drawn = [[preview valueForKey:@"_shuffle"] alpha] == 0 && [[preview valueForKey:@"_repeat"] alpha] == 0 && ![[preview valueForKey:@"_chip"] isHidden]
                     && play - previous > slot + 1;
        [self expect:alone && drawn step:@"each chip its key alone, video shown, previous and next spread"
              detail:[NSString stringWithFormat:@"changed %@; previous %.0f pt from play, a slot %.0f", seen, play - previous, slot]];
    });
    step(0, ^{
        settingsPresented = NO;
        [self.window.rootViewController dismissViewControllerAnimated:NO completion:open];
    });
    when(^BOOL { return settingsPresented && card().window != nil; }, ^{
        NSArray<UIButton *> *found = chips();
        BOOL kept = found.count == 3;
        for (UIButton *chip in found) kept = kept && chip.selected == (chip == found.lastObject) && !!(chip.accessibilityTraits & UIAccessibilityTraitSelected) == chip.selected;
        [self expect:kept && [[card() valueForKey:@"_shuffle"] alpha] == 0 step:@"opened again: the three chips as left" detail:[[found valueForKey:@"selected"] description]];
        for (UIButton *chip in found) [chip sendActionsForControlEvents:UIControlEventTouchUpInside];
        [self expect:!stored(SGRKeyPlayerHideShuffle) && !stored(SGRKeyPlayerHideRepeat) && SGVideoSwitchHidden()
                step:@"Shuffle and Repeat shown again, Video hidden" detail:[[chips() valueForKey:@"selected"] description]];
        [table() setContentOffset:CGPointMake(0, -table().adjustedContentInset.top) animated:NO];
        [table() layoutIfNeeded];
    });
    // Deliver B only after C owns the card, then deliver C. No scheduler race decides their order.
    step(1, ^{
        SGSetEnabled(SGRKeyPlayerHoldNoClip, YES);
        SGRHarnessHoldLookups(@"spotify:track:harnessB");
        setenv("HARNESS_CANVAS", [NSString stringWithFormat:@"https://canvas.harness/b-%d.mp4", getpid()].UTF8String, 1);
        lateImageB = serve(imageURI(@"bbbb"), solid(UIColor.blueColor), 0, NO);
        lateImageB.held = YES;
        [self playTrack:@"spotify:track:harnessB" image:imageURI(@"bbbb")];
        // The player keeps A's clip only for its handover (kHandOver, PlayerMotion.x), timed from this track change, so
        // the card is looked at in the main queue turn after its own re-read (queued by the change, PlayerSettings.m),
        // ahead of the handover's end; B's held lookup is a download and may come after the handover is over.
        dispatch_async(dispatch_get_main_queue(), ^{
            [self expect:!motionOn() && SGRPlayerMotionShowing() && [[card() valueForKey:@"_track"] isEqualToString:@"spotify:track:harnessB"]
                    step:@"handover: no old preview clip while the real player keeps its clip" detail:cardState()];
        });
    });
    when(^BOOL { return SGRHarnessLookupReady(@"spotify:track:harnessB") && pictureReady(lateImageB); }, ^{
        SGRArtworkField *previewField = [card() valueForKey:@"_field"];
        [self expect:previewField && !previewField.motionHeld step:@"pending preview lookup leaves Fluid moving" detail:cardState()];
        SGRHarnessHoldLookups(@"spotify:track:harnessC");
        setenv("HARNESS_CANVAS", [NSString stringWithFormat:@"https://canvas.harness/square-%d.mp4", getpid()].UTF8String, 1);
        serve(imageURI(@"cccc"), solid(UIColor.greenColor), 0.2, NO);
        [self playTrack:@"spotify:track:harnessC" image:imageURI(@"cccc")];
    });
    when(^BOOL { return SGRHarnessLookupReady(@"spotify:track:harnessC"); }, ^{
        SGRHarnessDeliverLookups(@"spotify:track:harnessB");
        [self expect:!motionOn() && [[card() valueForKey:@"_track"] isEqualToString:@"spotify:track:harnessC"] step:@"the track before's clip, come after the next track, not shown" detail:cardState()];
        SGMotionFile([NSURL URLWithString:@(getenv("HARNESS_CANVAS"))], ^(NSURL *file) { fileC = file; });
        SGRHarnessDeliverLookups(@"spotify:track:harnessC");
    });
    when(^BOOL { return motionOn() != nil && fileC != nil &&
        [colorName([(UIImageView *)[card() valueForKey:@"_cover"] image]) isEqualToString:@"green"]; }, ^{
        deliverPicture(lateImageB);
    });
    when(^BOOL { return lateImageB.finished; }, ^{
        NSURL *playing = [motionOn() valueForKey:@"_file"];
        [self expect:playing && fileC && [playing isEqual:fileC] step:@"the track's own clip on the card once it is in"
              detail:[NSString stringWithFormat:@"card plays %@, the track's is %@", playing.lastPathComponent, fileC.lastPathComponent]];
        NSString *color = colorName([(UIImageView *)[card() valueForKey:@"_cover"] image]);
        [self expect:[color isEqualToString:@"green"] step:@"the current song's cover, not the preceding song's late blue image" detail:color];
    });
    when(^BOOL {
        UIView *clip = firstOfClass(SGRPlayerShowingCover(), @"SGRPlayerMotionView");
        return [(AVPlayer *)[clip valueForKey:@"player"] rate] > 0;
    }, ^{
        [self expect:SGRPlayerField() && !SGRPlayerField().motionHeld step:@"square clip in the cover leaves Fluid moving" detail:cardState()];
        unsetenv("HARNESS_CANVAS");
        SGRHarnessHoldLookups(@"spotify:track:noClip");
        [self playTrack:@"spotify:track:noClip" image:imageURI(@"cccc")];
    });
    when(^BOOL { return SGRHarnessLookupReady(@"spotify:track:noClip"); }, ^{
        SGRHarnessDeliverLookups(@"spotify:track:noClip");
    });
    when(^BOOL { return SGRPlayerField().motionHeld && [(SGRArtworkField *)[card() valueForKey:@"_field"] motionHeld]; }, ^{
        [self expect:!SGRPlayerMotionShowing() && !SGRPlayerVisualiserShowing() && !SGPlayerState().isPaused
                step:@"confirmed miss holds the playing field and preview" detail:cardState()];
        SGRHarnessHoldLookups(@"spotify:track:pending");
        setenv("HARNESS_CANVAS", [NSString stringWithFormat:@"https://canvas.harness/pending-%d.mp4", getpid()].UTF8String, 1);
        [self playTrack:@"spotify:track:pending" image:imageURI(@"cccc")];
    });
    when(^BOOL { return SGRHarnessLookupReady(@"spotify:track:pending"); }, ^{
        [self expect:!SGRPlayerField().motionHeld step:@"next track releases the hold before its clip answer" detail:cardState()];
        SGRHarnessDeliverLookups(@"spotify:track:pending");
        SGSetEnabled(SGRKeyPlayerHoldNoClip, NO);
    });
    step(0.5, ^{
        checkScrollWork();
        pick(SGRPlayerBackgroundVisualiser);
    });
    step(0.8, ^{
        checkScrollWork();
        pick(SGRPlayerBackgroundAnimated);
        choose(2); // the preview's hills only; the real player still has its clip
    });
    step(0.8, ^{
        closedVisualiser = hillsOn();
        [self expect:closedVisualiser != nil step:@"the visualizer preview is present before dismissal" detail:cardState()];
        settingsDismissed = NO;
        [self.window.rootViewController dismissViewControllerAnimated:NO completion:^{
            nav = nil;
            settingsDismissed = YES;
        }];
    });
    when(^BOOL { return settingsDismissed; }, ^{
        sg_previewPaletteRequests = 0;
        sg_watchPreviewPalette = YES;
        [NSNotificationCenter.defaultCenter postNotificationName:SGRNowPlayingArtworkDidChangeNotification object:nil];
        sg_watchPreviewPalette = NO;
        [self expect:!closedVisualiser && sg_previewPaletteRequests == 0
                step:@"dismissed visualizer is deallocated and artwork requests no preview palette"
              detail:[NSString stringWithFormat:@"view %@, %lu requests", closedVisualiser ? @"retained" : @"released", (unsigned long)sg_previewPaletteRequests]];
        open();
    });
    // The card and the chips at an iPhone SE's width and this one's, at the default text size and the largest.
    when(^BOOL { return settingsPresented && card().window != nil; }, ^{
        NSMutableArray<NSString *> *wrong = [NSMutableArray array];
        for (NSNumber *width in @[@288, @370]) {
            for (UIContentSizeCategory category in @[UIContentSizeCategoryLarge, UIContentSizeCategoryAccessibilityExtraExtraExtraLarge]) {
                // With Star add button off and on: the card draws the star the player shows (issue #44).
                for (NSNumber *star in @[@NO, @YES]) {
                [NSUserDefaults.standardUserDefaults setBool:star.boolValue forKey:@"spotifyglass.redesign.player.starAdd"];
                UIView *probe = [[NSClassFromString(@"SGRPlayerPreview") alloc] initWithFrame:CGRectMake(-2000, 0, width.doubleValue, 236)];
                [self.window addSubview:probe];
                probe.traitOverrides.preferredContentSizeCategory = category;
                [probe updateTraitsIfNeeded];
                UIView *starGlyph = [probe valueForKey:@"_star"];
                if (starGlyph.hidden == star.boolValue) [wrong addObject:[NSString stringWithFormat:@"card %@ %@ star %@ while the setting is %@", width, category, starGlyph.hidden ? @"hidden" : @"shown", star.boolValue ? @"on" : @"off"]];
                CGFloat least = [[probe valueForKey:@"minimumHeight"] doubleValue], compact = MAX(least, 236);
                // Include shorter screens' expanded heights as well as the full 480 pt preview.
                NSMutableArray<NSNumber *> *sizes = [NSMutableArray arrayWithObject:@(least)];
                for (NSNumber *expanded in @[@320, @400, @480])
                    for (NSUInteger step = 0; step <= 10; step++)
                        [sizes addObject:@(round(compact + (expanded.doubleValue - compact) * step / 10.0))];
                for (NSNumber *height in sizes) {
                    probe.frame = CGRectMake(-2000, 0, width.doubleValue, height.doubleValue);
                    NSString *clipping = cardClipping(probe);
                    if (clipping) [wrong addObject:[NSString stringWithFormat:@"card %@x%@ at %@ star %@: %@", width, height, category, star, clipping]];
                }
                if (least > 236) [wrong addObject:[NSString stringWithFormat:@"card %@ %@ needs %.0f compact", width, category, least]];
                [probe removeFromSuperview];
                }
                [NSUserDefaults.standardUserDefaults removeObjectForKey:@"spotifyglass.redesign.player.starAdd"];

                UITableViewCell *cell = [[NSClassFromString(@"SGRPlayerButtonsCell") alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
                cell.frame = CGRectMake(-2000, 0, width.doubleValue, 44);
                [self.window addSubview:cell];
                cell.traitOverrides.preferredContentSizeCategory = category;
                [cell updateTraitsIfNeeded];
                [cell performSelector:@selector(readKeys)];
                CGFloat height = [cell systemLayoutSizeFittingSize:CGSizeMake(width.doubleValue, 0) withHorizontalFittingPriority:UILayoutPriorityRequired
                                                verticalFittingPriority:UILayoutPriorityFittingSizeLevel].height;
                cell.frame = CGRectMake(-2000, 0, width.doubleValue, height);
                [cell layoutIfNeeded];
                CGRect inside = CGRectInset(cell.contentView.bounds, -0.5, -0.5);
                NSMutableArray<NSValue *> *placed = [NSMutableArray array];
                for (UIView *view in cell.contentView.subviews) {
                    if (![view isKindOfClass:UIButton.class]) continue;
                    UIButton *chip = (UIButton *)view;
                    BOOL whole = chip.titleLabel.intrinsicContentSize.width <= chip.titleLabel.bounds.size.width + 0.5;
                    if (!CGRectContainsRect(inside, chip.frame) || chip.frame.size.height < 44 || !whole)
                        [wrong addObject:[NSString stringWithFormat:@"chip %@ %@ at %@ %@ in %@", chip.accessibilityLabel, NSStringFromCGRect(chip.frame), width, category, NSStringFromCGRect(inside)]];
                    for (NSValue *other in placed) if (CGRectIntersectsRect(other.CGRectValue, chip.frame)) [wrong addObject:[NSString stringWithFormat:@"chip %@ over another", chip.accessibilityLabel]];
                    [placed addObject:[NSValue valueWithCGRect:chip.frame]];
                }
                [cell removeFromSuperview];
            }
        }
        [self expect:wrong.count == 0 step:@"the card at every height and the chips whole, 288 and 370 pt wide, default and largest text"
              detail:wrong.count ? [wrong componentsJoinedByString:@" | "] : @"all whole"];
    });
    // No playback: the actual last song, including its asynchronous image, still belongs in the preview.
    step(0.5, ^{
        pick(SGRPlayerBackgroundStill);
        lateImageD = serve(imageURI(@"dddd"), solid(UIColor.magentaColor), 0, NO);
        lateImageD.held = YES;
        NSString *url = [@"https://i.scdn.co/image/" stringByAppendingString:[imageURI(@"dddd") substringFromIndex:14]];
        [NSUserDefaults.standardUserDefaults setObject:@{@"uri": @"spotify:track:lastD", @"title": @"Last song D", @"artwork": url}
                                               forKey:SGKeyLastTrack];
        SGRHarnessClearTrack();
    });
    when(^BOOL { return pictureReady(lateImageD); }, ^{
        [self expect:![colorName([(UIImageView *)[card() valueForKey:@"_cover"] image]) isEqualToString:@"magenta"]
                step:@"last-song cover waits for the held image reply" detail:@"request pending, main run loop responsive"];
        deliverPicture(lateImageD);
    });
    when(^BOOL { return [colorName([(UIImageView *)[card() valueForKey:@"_cover"] image]) isEqualToString:@"magenta"]; }, ^{
        NSString *color = colorName([(UIImageView *)[card() valueForKey:@"_cover"] image]);
        [self expect:[color isEqualToString:@"magenta"] && [[[card() valueForKey:@"_title"] text] isEqualToString:@"Last song D"]
                step:@"no playback: the last song's title and delayed cover" detail:color];
        lateImageE = serve(imageURI(@"eeee"), solid(UIColor.blueColor), 0, NO);
        lateImageE.held = YES;
        NSString *url = [@"https://i.scdn.co/image/" stringByAppendingString:[imageURI(@"eeee") substringFromIndex:14]];
        [NSUserDefaults.standardUserDefaults setObject:@{@"uri": @"spotify:track:lastE", @"title": @"Last song E", @"artwork": url}
                                               forKey:SGKeyLastTrack];
        SGRHarnessClearTrack();
    });
    when(^BOOL { return pictureReady(lateImageE); }, ^{
        NSString *url = [@"https://i.scdn.co/image/" stringByAppendingString:[imageURI(@"dddd") substringFromIndex:14]];
        [NSUserDefaults.standardUserDefaults setObject:@{@"uri": @"spotify:track:lastF", @"title": @"Last song F", @"artwork": url}
                                               forKey:SGKeyLastTrack];
        SGRHarnessClearTrack();
        deliverPicture(lateImageE);
    });
    when(^BOOL { return lateImageE.finished; }, ^{
        NSString *color = colorName([(UIImageView *)[card() valueForKey:@"_cover"] image]);
        [self expect:[color isEqualToString:@"magenta"] && [[[card() valueForKey:@"_title"] text] isEqualToString:@"Last song F"]
                step:@"a late last-song image cannot replace the song now shown" detail:color];
        // A last-song lookup belongs only to the preview, not the real player.
        SGRHarnessHoldLookups(@"spotify:track:lastG");
        NSString *canvas = [NSString stringWithFormat:@"https://canvas.harness/closed-%d.mp4", getpid()];
        [NSUserDefaults.standardUserDefaults setObject:@{@"uri": @"spotify:track:lastG", @"title": @"Last song G", @"canvas": canvas}
                                               forKey:SGKeyLastTrack];
        SGRHarnessClearTrack();
        pick(SGRPlayerBackgroundAnimated);
        SGRPlayerMotionPreview(^(BOOL found){ latePreviewCallbacks++; });
    });
    // Closed: the card does nothing more, whatever the player does.
    when(^BOOL { return SGRHarnessLookupReady(@"spotify:track:lastG"); }, ^{
        closedCard = card();
        settingsDismissed = NO;
        [self.window.rootViewController dismissViewControllerAnimated:NO completion:^{ settingsDismissed = YES; }];
        nav = nil;
    });
    when(^BOOL { return settingsDismissed; }, ^{
        SGRHarnessDeliverLookups(@"spotify:track:lastG");
        UIView *left = closedCard;
        BOOL stopped = !left || (![[left valueForKey:@"_active"] boolValue] && !firstOfClass(left, @"SGRPlayerMotionView") && !firstOfClass(left, @"SGRVisualiserView")
                                 && ![[left valueForKey:@"_track"] isEqualToString:@"spotify:track:harnessD"]);
        [self expect:stopped step:@"closed: the card stopped, not following the player"
              detail:left ? [NSString stringWithFormat:@"card kept, active %@, track %@", [left valueForKey:@"_active"], [left valueForKey:@"_track"]] : @"card gone"];
        [self expect:latePreviewCallbacks == 0 && SGRPlayerMotionPreview(nil) == nil
                step:@"dismissal cancels the pending preview result" detail:[NSString stringWithFormat:@"%lu late callbacks", (unsigned long)latePreviewCallbacks]];
        [self expect:SGRHarnessPlayerCommands() == 0 step:@"no command sent to the player" detail:[NSString stringWithFormat:@"%lu commands", (unsigned long)SGRHarnessPlayerCommands()]];
        NSLog(@"[harness] settings checks: %lu of %lu right -- %@", (unsigned long)(self->_checks - self->_failures), (unsigned long)self->_checks,
              self->_failures ? @"FAIL" : @"PASS");
        exit(self->_failures ? 1 : 0);
    });
    runScript(script, 0);
}

// The Player page opened with the player showing no clip, Animated picked on it: the card looks the clip up.
- (void)runPreviewChecks {
    __block UINavigationController *nav;
    UIView *(^showcase)(void) = ^{
        return firstOfClass(((UITableViewController *)nav.topViewController).tableView, @"SGRPlayerPreview");
    };
    void (^pick)(NSUInteger) = ^(NSUInteger index) {
        UISegmentedControl *segments = (UISegmentedControl *)firstOfClass(((UITableViewController *)nav.topViewController).tableView.tableHeaderView, @"UISegmentedControl");
        segments.selectedSegmentIndex = (NSInteger)index;
        [segments sendActionsForControlEvents:UIControlEventValueChanged];
    };
    NSString *(^card)(void) = ^{
        UIView *view = showcase();
        SGRArtworkField *field = (SGRArtworkField *)firstOfClass(view, @"SGRArtworkField");
        UIView *motion = firstOfClass(view, @"SGRPlayerMotionView");
        CALayer *still = [motion valueForKey:@"_still"];
        return [NSString stringWithFormat:@"card: clip %@ (poster %@), field fluid %d held %d; the player's clip %@; the clip served %lu times",
                motion ? @"in" : @"out", still.contents ? @"drawn" : @"none", field.fluid, field.motionHeld, SGRPlayerMotionShowing() ? @"in" : @"none",
                (unsigned long)sg_canvasServed];
    };
    BOOL (^clipIn)(void) = ^{ return (BOOL)(firstOfClass(showcase(), @"SGRPlayerMotionView") != nil); };
    after(1, ^{
        [self expect:sg_canvasServed == 0 && !SGRPlayerMotionShowing() step:@"before the page, nothing asked for"
              detail:[NSString stringWithFormat:@"the clip served %lu times, the player's clip %@", (unsigned long)sg_canvasServed, SGRPlayerMotionShowing() ? @"in" : @"none"]];
        nav = [[UINavigationController alloc] initWithRootViewController:SGRPlayerSettingsPage(@[])];
        nav.modalPresentationStyle = UIModalPresentationFullScreen;
        [self.window.rootViewController presentViewController:nav animated:NO completion:nil];
    });
    after(2, ^{
        [self expect:!clipIn() && sg_canvasServed == 0 step:@"Still on the page, nothing asked for" detail:card()];
        pick(3);
    });
    after(2.5, ^{
        SGRArtworkField *field = (SGRArtworkField *)firstOfClass(showcase(), @"SGRArtworkField");
        [self expect:!clipIn() && field.fluid step:@"Animated picked, Fluid while the clip comes" detail:card()];
    });
    after(6, ^{
        SGRArtworkField *field = (SGRArtworkField *)firstOfClass(showcase(), @"SGRArtworkField");
        CALayer *still = [firstOfClass(showcase(), @"SGRPlayerMotionView") valueForKey:@"_still"];
        [self expect:clipIn() && still.contents && field.motionHeld && sg_canvasServed == 1 && !SGRPlayerMotionShowing()
                step:@"the clip in the card, the player left alone" detail:card()];
        NSLog(@"[harness] preview: screenshot the card now");
        // The player's walk asks the store the same way: it finds the file without asking the server again.
        SGMotionFile([NSURL URLWithString:@(getenv("HARNESS_CANVAS"))], ^(NSURL *file) {
            [self expect:file && sg_canvasServed == 1 step:@"the clip in the store for the player"
                  detail:[NSString stringWithFormat:@"%@, served %lu times", file.lastPathComponent ?: @"no file", (unsigned long)sg_canvasServed]];
        });
    });
    after(8, ^{ pick(2); });
    after(8.5, ^{
        [self expect:!clipIn() step:@"Fluid picked, the clip out" detail:card()];
        pick(3);
        [self expect:clipIn() && sg_canvasServed == 1 step:@"Animated again, the clip at once" detail:card()];
    });
    after(9.5, ^{
        NSLog(@"[harness] preview checks: %lu of %lu right -- %@", (unsigned long)(self->_checks - self->_failures), (unsigned long)self->_checks,
              self->_failures ? @"FAIL" : @"PASS");
    });
}

- (NSArray<UILabel *> *)labelsIn:(UIView *)view {
    NSMutableArray<UILabel *> *labels = [NSMutableArray array];
    for (UIView *sub in view.subviews) {
        if ([sub isKindOfClass:UILabel.class]) [labels addObject:(UILabel *)sub];
        [labels addObjectsFromArray:[self labelsIn:sub]];
    }
    return labels;
}

#pragma mark - the Visualizer

BOOL SGRHarnessReading(void);

static UIView *visualiserView(void) {
    for (UIView *view in SGRPlayerField().subviews) {
        if ([NSStringFromClass(view.class) isEqualToString:@"SGRVisualiserView"]) return view;
    }
    return nil;
}

// The tallest a hill stands over the screen's foot, in points, from its path's bounding box.
static CGFloat hillHeight(UIView *view, NSString *ivar) {
    CAShapeLayer *shape = [view valueForKey:ivar];
    if (!shape.path) return 0;
    return view.bounds.size.height > 0 ? [[view valueForKey:@"baseline"] doubleValue] - CGPathGetPathBoundingBox(shape.path).origin.y : 0;
}

- (void)runVisualiserChecks {
    after(3, ^{
        UIView *hills = visualiserView();
        CADisplayLink *link = [hills valueForKey:@"_link"];
        CGFloat front = hillHeight(hills, @"_frontShape"), back = hillHeight(hills, @"_backShape");
        [self expect:hills && SGRPlayerVisualiserShowing() && SGRPlayerField().fluid && SGRPlayerField().motionHeld && link && SGRHarnessReading() && front > 40
                step:@"playing"
              detail:[NSString stringWithFormat:@"hills %@, field fluid %d held %d, link %@ at up to %.0f fps, reader %@, front %.0f pt, back %.0f pt",
                      hills ? @"on the field" : @"missing", SGRPlayerField().fluid, SGRPlayerField().motionHeld, link ? @"running" : @"stopped",
                      link.preferredFrameRateRange.maximum, SGRHarnessReading() ? @"on" : @"off", front, back]];
        NSLog(@"[harness] visualizer: screenshot the hills now");
    });
    after(4, ^{ SGRPlayerToggleLyrics(); });
    after(5.5, ^{
        UIView *hills = visualiserView();
        UIVisualEffectView *blur = [hills valueForKey:@"_lyricsBlur"];
        CADisplayLink *link = [hills valueForKey:@"_link"];
        [self expect:SGRPlayerLyricsOpen() && blur.effect && link.preferredFrameRateRange.maximum == UIScreen.mainScreen.maximumFramesPerSecond step:@"behind the lyrics"
              detail:[NSString stringWithFormat:@"lyrics %@, blur %@, link at up to %.0f fps", SGRPlayerLyricsOpen() ? @"up" : @"down",
                      blur.effect ? @"on" : @"off", link.preferredFrameRateRange.maximum]];
        NSLog(@"[harness] visualizer: screenshot the lyrics now");
    });
    after(6.5, ^{ SGRPlayerToggleLyrics(); });
    after(7.5, ^{ SGRHarnessSetTrack(@"spotify:track:harnessA", imageURI(@"aaaa"), YES); });
    after(8, ^{
        CADisplayLink *link = [visualiserView() valueForKey:@"_link"];
        [self expect:link && !SGRHarnessReading() step:@"paused, settling"
              detail:[NSString stringWithFormat:@"link %@, reader %@", link ? @"still running" : @"stopped", SGRHarnessReading() ? @"on" : @"off"]];
    });
    after(12, ^{
        UIView *hills = visualiserView();
        CADisplayLink *link = [hills valueForKey:@"_link"];
        CGFloat front = hillHeight(hills, @"_frontShape");
        [self expect:!link && !SGRHarnessReading() && front < 15 step:@"paused, settled"
              detail:[NSString stringWithFormat:@"link %@, reader %@, front %.0f pt", link ? @"running" : @"stopped", SGRHarnessReading() ? @"on" : @"off", front]];
        NSLog(@"[harness] visualizer: screenshot the paused hills now");
        SGRHarnessSetTrack(@"spotify:track:harnessA", imageURI(@"aaaa"), NO);
    });
    after(13.5, ^{
        UIView *hills = visualiserView();
        [self expect:[hills valueForKey:@"_link"] && SGRHarnessReading() && hillHeight(hills, @"_frontShape") > 40 step:@"playing again"
              detail:[NSString stringWithFormat:@"front %.0f pt", hillHeight(hills, @"_frontShape")]];
        SGRPlayerMenuSetBackground(SGRPlayerBackgroundFluid);
    });
    after(14.2, ^{
        [self expect:!visualiserView() && !SGRPlayerVisualiserShowing() && !SGRPlayerField().motionHeld && !SGRHarnessReading()
                step:@"switched to Fluid from the menu"
              detail:[NSString stringWithFormat:@"hills %@, field %@, reader %@", visualiserView() ? @"still there" : @"gone",
                      SGRPlayerField().motionHeld ? @"held" : @"moving", SGRHarnessReading() ? @"on" : @"off"]];
        SGRPlayerMenuSetBackground(SGRPlayerBackgroundVisualiser);
    });
    after(15.5, ^{
        UIView *hills = visualiserView();
        [self expect:hills && SGRPlayerField().motionHeld && SGRHarnessReading() && hillHeight(hills, @"_frontShape") > 40 step:@"back from the menu"
              detail:[NSString stringWithFormat:@"hills %@, field %@, front %.0f pt", hills ? @"on the field" : @"missing",
                      SGRPlayerField().motionHeld ? @"held" : @"moving", hillHeight(hills, @"_frontShape")]];
        NSLog(@"[harness] visualizer checks: %lu of %lu right -- %@", (unsigned long)(self->_checks - self->_failures), (unsigned long)self->_checks,
              self->_failures ? @"FAIL" : @"PASS");
    });
}

#pragma mark - the Visualizer without a clip, shuffled styles, heat

// What NSProcessInfo reports as the thermal state and Low Power Mode, which the simulator has neither of.
static NSInteger sg_thermal;
static BOOL sg_lowPower;

static void reportPower(void) {
    Class info = object_getClass(NSProcessInfo.processInfo);
    for (NSString *name in @[@"isLowPowerModeEnabled", @"lowPowerModeEnabled"]) {
        Method method = class_getInstanceMethod(info, NSSelectorFromString(name));
        if (method) method_setImplementation(method, imp_implementationWithBlock(^BOOL(id process) { return sg_lowPower; }));
    }
    Method thermal = class_getInstanceMethod(info, @selector(thermalState));
    method_setImplementation(thermal, imp_implementationWithBlock(^NSInteger(id process) { return sg_thermal; }));
}

static void setThermal(NSProcessInfoThermalState state) {
    sg_thermal = state;
    [NSNotificationCenter.defaultCenter postNotificationName:NSProcessInfoThermalStateDidChangeNotification object:nil];
}

static NSString *finishChecks(NSUInteger checks, NSUInteger failures, NSString *name) {
    return [NSString stringWithFormat:@"%@ checks: %lu of %lu right -- %@", name, (unsigned long)(checks - failures), (unsigned long)checks, failures ? @"FAIL" : @"PASS"];
}

// Animated with "Visualizer when there's no clip" (SGRKeyPlayerAnimatedVisualiser). Every track's lookup takes 1.5 s
// (stubs.m), so the player can be looked at while it is out.
- (void)runAutoVisualiserChecks {
    NSUserDefaults *store = NSUserDefaults.standardUserDefaults;
    void (^setFallback)(BOOL) = ^(BOOL on) {
        [store setBool:on forKey:SGRKeyPlayerAnimatedVisualiser];
        SGRPlayerAnimatedVisualiserChanged();
    };
    void (^setStill)(BOOL) = ^(BOOL on) {
        [store setBool:on forKey:SGRKeyPlayerAnimatedStill];
        SGRPlayerStillChanged();
    };
    void (^background)(SGRPlayerBackgroundKind) = ^(SGRPlayerBackgroundKind kind) {
        SGRSetPlayerBackground(kind);
        SGRPlayerBackgroundDidChange();
        [self layOut];
    };
    // The ordinary cover: no clip, no still, no hills (faded out and gone), the reader off.
    BOOL (^ordinary)(void) = ^BOOL { return !SGRPlayerMotionShowing() && !self->_covers.layer.mask && !visualiserView() && !SGRHarnessReading(); };
    // The hills as the background, over the ordinary cover and the field held still, the reader on.
    BOOL (^hills)(void) = ^BOOL {
        return visualiserView() && SGRPlayerVisualiserShowing() && !SGRPlayerMotionShowing() && !self->_covers.layer.mask
            && SGRPlayerField().motionHeld && SGRHarnessReading();
    };
    NSString *(^state)(void) = ^NSString *{
        return [NSString stringWithFormat:@"hills %@, clip or still %@, cover %@, reader %@", visualiserView() ? @"on" : @"off",
                SGRPlayerMotionShowing() ? @"on" : @"off", self->_covers.layer.mask ? @"hidden" : @"shown", SGRHarnessReading() ? @"on" : @"off"];
    };
    serve(imageURI(@"bbbb"), solidPixels(UIColor.greenColor, 600), 0.1, NO);
    serve(imageURI(@"cccc"), solidPixels(UIColor.blueColor, 600), 0.1, NO);
    runScript(@[
        @[@0.6, ^{
            [self expect:ordinary() && !SGRPlayerAnimatedVisualiserOn() step:@"switch off, lookup out" detail:state()];
            setFallback(YES);
            [self expect:ordinary() && !SGRPlayerVisualiserShowing() step:@"switched on while the lookup is out: no flash" detail:state()];
        }],
        @[@2.5, ^{
            [self expect:hills() step:@"the lookup found no clip: the Visualizer" detail:state()];
            NSLog(@"[harness] autoviz: screenshot the Visualizer now");
            [self playTrack:@"spotify:track:harnessB" image:imageURI(@"bbbb")];
        }],
        @[@0.9, ^{ [self expect:ordinary() step:@"a track change takes it down until the lookup ends" detail:state()]; }],
        @[@2, ^{
            [self expect:hills() step:@"the new track's lookup found no clip" detail:state()];
            // Its Canvas turns up late.
            setenv("HARNESS_CANVAS", [NSString stringWithFormat:@"https://canvas.harness/auto-%d.mp4", getpid()].UTF8String, 1);
            SGRHarnessSetTrack(@"spotify:track:harnessB", imageURI(@"bbbb"), NO);
        }],
        @[@0.9, ^{ [self expect:ordinary() step:@"a clip on its way: the lookup is out again" detail:state()]; }],
        @[@2.2, ^{
            [self expect:SGRPlayerMotionShowing() && !visualiserView() && !SGRHarnessReading() step:@"a late clip takes the Visualizer down" detail:state()];
            unsetenv("HARNESS_CANVAS");
            [self playTrack:@"spotify:track:harnessC" image:imageURI(@"cccc")];
        }],
        @[@3.2, ^{
            [self expect:hills() step:@"a track without a clip after a clip" detail:state()];
            reportPower();
            // Low Power Mode, with no notification and no new walk (as Reduce Motion is switched): the Visualizer is asked again.
            sg_lowPower = YES;
            SGRPlayerVisualiserUpdate();
        }],
        @[@1, ^{
            [self expect:ordinary() step:@"no clip wanted any more (Low Power Mode, no new walk): the Visualizer goes" detail:state()];
            sg_lowPower = NO;
            SGRPlayerVisualiserUpdate();
        }],
        @[@1, ^{
            [self expect:hills() step:@"a clip wanted again: the Visualizer is back" detail:state()];
            sg_lowPower = YES;
            [NSNotificationCenter.defaultCenter postNotificationName:NSProcessInfoPowerStateDidChangeNotification object:nil];
        }],
        // Reduce Motion takes the same path as Low Power Mode (motionAllowed); the process can be made to report the latter.
        @[@1.8, ^{
            [self expect:ordinary() step:@"Low Power Mode: the ordinary cover, not the still" detail:state()];
            [NSNotificationCenter.defaultCenter postNotificationName:SGRNowPlayingArtworkDidChangeNotification object:nil];
            [self expect:ordinary() step:@"a cover in under Low Power Mode" detail:state()];
            sg_lowPower = NO;
            [NSNotificationCenter.defaultCenter postNotificationName:NSProcessInfoPowerStateDidChangeNotification object:nil];
        }],
        @[@0.5, ^{ [self expect:ordinary() step:@"Low Power Mode off, lookup out" detail:state()]; }],
        @[@2.5, ^{
            [self expect:hills() step:@"Low Power Mode off, lookup ended" detail:state()];
            setStill(YES);
        }],
        @[@0.9, ^{
            [self expect:!SGRPlayerAnimatedVisualiserOn() && SGRPlayerStillOn() && SGRPlayerMotionShowing() && !visualiserView() && !SGRHarnessReading()
                    step:@"the still switched on: the Visualizer switch off, the still in"
                  detail:[NSString stringWithFormat:@"switch %d, still %d, %@", SGRPlayerAnimatedVisualiserOn(), SGRPlayerStillOn(), state()]];
            setFallback(YES);
        }],
        @[@0.9, ^{
            [self expect:SGRPlayerAnimatedVisualiserOn() && !SGRPlayerStillOn() && hills()
                    step:@"the Visualizer switched on: the still switch off, the hills in"
                  detail:[NSString stringWithFormat:@"switch %d, still %d, %@", SGRPlayerAnimatedVisualiserOn(), SGRPlayerStillOn(), state()]];
            setFallback(NO);
        }],
        @[@0.9, ^{
            [self expect:ordinary() && !SGRPlayerStillOn() step:@"both off" detail:state()];
            setFallback(YES);
            background(SGRPlayerBackgroundFluid);
        }],
        @[@1, ^{ [self expect:ordinary() && !SGRPlayerVisualiserShowing() step:@"Fluid chosen: no Visualizer" detail:state()]; background(SGRPlayerBackgroundBlack); }],
        @[@1.5, ^{
            [self expect:!visualiserView() && !SGRPlayerVisualiserShowing() && !SGRHarnessReading() step:@"black chosen: no Visualizer" detail:state()];
            background(SGRPlayerBackgroundAnimated);
        }],
        @[@3, ^{ [self expect:hills() step:@"Animated again" detail:state()]; setFallback(NO); }],
        @[@0.9, ^{
            [self expect:ordinary() step:@"switched off again: today's behavior" detail:state()];
            // Both saved on (an older build): the track has no clip, and the cover is the one wanted.
            [store setBool:YES forKey:SGRKeyPlayerAnimatedStill];
            [store setBool:YES forKey:SGRKeyPlayerAnimatedVisualiser];
            [self expect:!SGRPlayerVisualiserFallbackWanted() step:@"both saved on: the Visualizer is not wanted" detail:state()];
            SGRPlayerVisualiserUpdate();
            [self expect:SGRPlayerStillOn() && !SGRPlayerAnimatedVisualiserOn() && ![store boolForKey:SGRKeyPlayerAnimatedVisualiser]
                    step:@"both saved on: the cover stays, the Visualizer switch is off"
                  detail:[NSString stringWithFormat:@"still %d, switch %d", SGRPlayerStillOn(), [store boolForKey:SGRKeyPlayerAnimatedVisualiser]]];
        }],
        @[@0.9, ^{
            [self expect:!visualiserView() && !SGRPlayerVisualiserShowing() step:@"both saved on: no Visualizer after the cover" detail:state()];
            // The row's order: the switch written, then the callback.
            SGSetEnabled(SGRKeyPlayerAnimatedVisualiser, YES);
            SGRPlayerAnimatedVisualiserChanged();
        }],
        @[@0.9, ^{
            [self expect:SGRPlayerAnimatedVisualiserOn() && !SGRPlayerStillOn() && hills() step:@"the row switching the Visualizer on with the cover on: the Visualizer wins"
                  detail:state()];
            setFallback(NO);
            NSLog(@"[harness] %@", finishChecks(self->_checks, self->_failures, @"autoviz"));
            exit(self->_failures ? 1 : 0);
        }],
    ], 0);
}

// Shuffle styles, with the Visualizer as the background first, then standing in for a missing clip.
- (void)runShuffleChecks {
    NSUserDefaults *store = NSUserDefaults.standardUserDefaults;
    __block NSUInteger changes = 0, picksBefore = 0;
    [NSNotificationCenter.defaultCenter addObserverForName:SGRVisualiserStyleDidChangeNotification object:nil queue:nil
                                                usingBlock:^(NSNotification *note) { changes++; }];
    NSSet<NSString *> *all = [NSSet setWithArray:@[@"builtin:hills", @"builtin:bars", @"builtin:nebula", @"builtin:halo",
                                                    @"builtin:lyrics", @"builtin:poster", @"builtin:cut"]];
    void (^background)(SGRPlayerBackgroundKind) = ^(SGRPlayerBackgroundKind kind) {
        SGRSetPlayerBackground(kind);
        SGRPlayerBackgroundDidChange();
        [self layOut];
    };
    runScript(@[
        @[@3, ^{
            [self expect:changes == 0 && [SGRVisualiserStyle() isEqualToString:@"builtin:hills"] step:@"off: no pick" detail:SGRVisualiserStyle()];
            SGRHarnessSetTrack(@"spotify:track:shuffleOff", imageURI(@"aaaa"), NO);
            [self expect:changes == 0 && [SGRVisualiserStyle() isEqualToString:@"builtin:hills"] step:@"off: a track change picks nothing" detail:SGRVisualiserStyle()];
            [store setBool:YES forKey:SGRKeyVisualiserShuffle];
            SGRVisualiserShuffleChanged();
            [self expect:changes == 0 && [[store stringForKey:SGRKeyVisualiserShuffleHome] isEqualToString:@"builtin:hills"]
                    step:@"switched on: the user's style remembered, nothing picked"
                  detail:[NSString stringWithFormat:@"home %@, %lu changes", [store stringForKey:SGRKeyVisualiserShuffleHome], (unsigned long)changes]];
            SGRHarnessSetTrack(@"spotify:track:shuffleA", imageURI(@"aaaa"), NO);
            [self expect:changes == 1 && ![SGRVisualiserStyle() isEqualToString:@"builtin:hills"] && [all containsObject:SGRVisualiserStyle()]
                    step:@"a track change on screen: one pick, not the current style"
                  detail:[NSString stringWithFormat:@"%lu changes, style %@", (unsigned long)changes, SGRVisualiserStyle()]];
            // The same song seen again: a pause and a play, then the same song reported once more.
            SGRHarnessSetTrack(@"spotify:track:shuffleA", imageURI(@"aaaa"), YES);
            SGRHarnessSetTrack(@"spotify:track:shuffleA", imageURI(@"aaaa"), NO);
            [self expect:changes == 1 step:@"the same track (pause, play): no pick" detail:[NSString stringWithFormat:@"%lu changes", (unsigned long)changes]];
        }],
        @[@0.5, ^{
            BOOL moved = YES;
            NSMutableSet *seen = [NSMutableSet set];
            // Exercise the whole pool without requiring an even distribution or a particular order.
            for (int i = 0; i < 256; i++) {
                NSString *before = SGRVisualiserStyle();
                NSUInteger count = changes;
                SGRHarnessSetTrack([NSString stringWithFormat:@"spotify:track:shuffleMany%d", i], imageURI(@"aaaa"), NO);
                moved = moved && changes == count + 1 && ![SGRVisualiserStyle() isEqualToString:before];
                [seen addObject:SGRVisualiserStyle()];
            }
            [self expect:moved && [seen isEqualToSet:all] step:@"each track gets one pick, never the current style, all seven styles turn up"
                  detail:[NSString stringWithFormat:@"%@, styles seen: %@", moved ? @"each moved" : @"a pick missed or repeated", seen]];
            // Hidden: another background.
            background(SGRPlayerBackgroundFluid);
        }],
        @[@1, ^{
            NSUInteger count = changes;
            for (int i = 0; i < 5; i++) SGRHarnessSetTrack([NSString stringWithFormat:@"spotify:track:shuffleHidden%d", i], imageURI(@"aaaa"), NO);
            [self expect:changes == count step:@"hidden: track changes pick nothing" detail:[NSString stringWithFormat:@"%lu picks", (unsigned long)(changes - count)]];
            background(SGRPlayerBackgroundVisualiser);
        }],
        @[@1.2, ^{
            NSUInteger count = changes;
            [self expect:visualiserView() step:@"the Visualizer back" detail:@""];
            SGRHarnessSetTrack(@"spotify:track:shuffleHidden4", imageURI(@"aaaa"), NO);
            [self expect:changes == count step:@"back on screen, the same track: no pick" detail:[NSString stringWithFormat:@"%lu picks", (unsigned long)(changes - count)]];
            SGRHarnessSetTrack(@"spotify:track:shuffleNext", imageURI(@"aaaa"), NO);
            [self expect:changes == count + 1 step:@"the next track: a pick" detail:[NSString stringWithFormat:@"%lu picks", (unsigned long)(changes - count)]];
            // A style by hand becomes the one shuffle goes back to.
            SGRPickVisualiserStyle(@"builtin:bars");
            [self expect:[[store stringForKey:SGRKeyVisualiserShuffleHome] isEqualToString:@"builtin:bars"] step:@"a style by hand is remembered"
                  detail:[store stringForKey:SGRKeyVisualiserShuffleHome]];
            SGRHarnessSetTrack(@"spotify:track:shuffleAfterHand", imageURI(@"aaaa"), NO);
            [store setBool:NO forKey:SGRKeyVisualiserShuffle];
            SGRVisualiserShuffleChanged();
            [self expect:[SGRVisualiserStyle() isEqualToString:@"builtin:bars"] step:@"switched off: the user's own style is back" detail:SGRVisualiserStyle()];
            count = changes;
            SGRHarnessSetTrack(@"spotify:track:shuffleOffAgain", imageURI(@"aaaa"), NO);
            [self expect:changes == count step:@"off again: no pick" detail:SGRVisualiserStyle()];
            // The Visualizer for a missing clip: shuffle picks once the hills come in, not while the lookup is out.
            [store setBool:YES forKey:SGRKeyVisualiserShuffle];
            SGRVisualiserShuffleChanged();
            [store setBool:YES forKey:SGRKeyPlayerAnimatedVisualiser];
            SGRHarnessSetLookupDelay(1);
            background(SGRPlayerBackgroundAnimated);
        }],
        @[@2.5, ^{
            [self expect:visualiserView() && SGRPlayerVisualiserShowing() step:@"Animated: the Visualizer for the current track's missing clip" detail:@""];
            picksBefore = changes;
            SGRHarnessSetTrack(@"spotify:track:shuffleFallback", imageURI(@"aaaa"), NO);
        }],
        @[@2, ^{
            [self expect:changes == picksBefore + 1 && visualiserView() && SGRPlayerVisualiserShowing() step:@"Animated: the next track's Visualizer, one pick"
                  detail:[NSString stringWithFormat:@"%lu picks", (unsigned long)(changes - picksBefore)]];
        }],
        @[@0.1, ^{
            NSUInteger count = changes;
            SGRHarnessSetTrack(@"spotify:track:shuffleFallback", imageURI(@"aaaa"), YES);
            SGRHarnessSetTrack(@"spotify:track:shuffleFallback", imageURI(@"aaaa"), NO);
            [self expect:changes == count step:@"Animated: the same track again, no pick" detail:@""];
            // A song that changes while the iPhone is hot is not picked for when it cools.
            reportPower();
            setThermal(NSProcessInfoThermalStateSerious);
            SGRPlayerVisualiserUpdate();
        }],
        @[@0.4, ^{
            picksBefore = changes;
            SGRHarnessSetTrack(@"spotify:track:shuffleHot", imageURI(@"aaaa"), NO);
        }],
        @[@2.5, ^{
            [self expect:!visualiserView() && changes == picksBefore step:@"hot: lookup held, no Visualizer, no pick"
                  detail:[NSString stringWithFormat:@"%lu picks", (unsigned long)(changes - picksBefore)]];
            setThermal(NSProcessInfoThermalStateNominal);
            SGRPlayerVisualiserUpdate();
        }],
        @[^BOOL { return SGRPlayerVisualiserShowing() && visualiserView(); }, ^{
            [self expect:visualiserView() && changes == picksBefore step:@"cooled: the Visualizer is back for the track that changed while hot, no pick"
                  detail:[NSString stringWithFormat:@"%lu picks", (unsigned long)(changes - picksBefore)]];
            // Hot during the lookup of a track that changed while the hills could be seen.
            SGRHarnessSetTrack(@"spotify:track:shuffleDuringFirst", imageURI(@"aaaa"), NO);
        }],
        @[@0.3, ^{
            // The hills are down for the first song's lookup, so the second is waited on.
            SGRHarnessSetTrack(@"spotify:track:shuffleDuring", imageURI(@"aaaa"), NO);
            picksBefore = changes;
        }],
        @[@0.3, ^{
            setThermal(NSProcessInfoThermalStateSerious);
            SGRPlayerVisualiserUpdate();
        }],
        @[@2.5, ^{
            [self expect:!visualiserView() && changes == picksBefore step:@"hot during the lookup: no Visualizer, no pick"
                  detail:[NSString stringWithFormat:@"%lu picks", (unsigned long)(changes - picksBefore)]];
            setThermal(NSProcessInfoThermalStateNominal);
            SGRPlayerVisualiserUpdate();
        }],
        @[^BOOL { return SGRPlayerVisualiserShowing() && visualiserView(); }, ^{
            [self expect:visualiserView() && changes == picksBefore step:@"cooled: the Visualizer is back for the track that was waited on while hot, no pick"
                  detail:[NSString stringWithFormat:@"%lu picks", (unsigned long)(changes - picksBefore)]];
            SGRHarnessSetTrack(@"spotify:track:shuffleCool", imageURI(@"aaaa"), NO);
        }],
        @[@2.5, ^{
            [self expect:visualiserView() && changes == picksBefore + 1 step:@"cooled: the next track while shown, one pick"
                  detail:[NSString stringWithFormat:@"%lu picks", (unsigned long)(changes - picksBefore)]];
            NSLog(@"[harness] %@", finishChecks(self->_checks, self->_failures, @"shuffle"));
            exit(self->_failures ? 1 : 0);
        }],
    ], 0);
}

// Ignore heat warnings.
- (void)runHeatChecks {
    NSUserDefaults *store = NSUserDefaults.standardUserDefaults;
    __block BOOL standInLeaving = NO;
    reportPower();
    void (^background)(SGRPlayerBackgroundKind) = ^(SGRPlayerBackgroundKind kind) {
        SGRSetPlayerBackground(kind);
        SGRPlayerBackgroundDidChange();
        [self layOut];
    };
    CADisplayLink * (^link)(void) = ^CADisplayLink *{ return [visualiserView() valueForKey:@"_link"]; };
    runScript(@[
        @[@3, ^{
            NSString *off = @"", *on = @"";
            BOOL right = YES;
            for (NSInteger level = NSProcessInfoThermalStateNominal; level <= NSProcessInfoThermalStateCritical; level++) {
                BOOL want = level >= NSProcessInfoThermalStateSerious;
                right = right && SGRVisualiserStandsDownFor(level) == want;
                off = [off stringByAppendingString:SGRVisualiserStandsDownFor(level) ? @"Y" : @"n"];
            }
            [self expect:right step:@"ignore off: serious and critical stand down, nominal and fair do not" detail:off];
            [store setBool:YES forKey:SGRKeyVisualiserIgnoreHeat];
            right = YES;
            for (NSInteger level = NSProcessInfoThermalStateNominal; level <= NSProcessInfoThermalStateCritical; level++) {
                right = right && !SGRVisualiserStandsDownFor(level);
                on = [on stringByAppendingString:SGRVisualiserStandsDownFor(level) ? @"Y" : @"n"];
            }
            [self expect:right step:@"ignore on: nothing stands down" detail:on];
            [store setBool:NO forKey:SGRKeyVisualiserIgnoreHeat];
            [self expect:link() && SGRHarnessReading() step:@"playing, cool" detail:@""];
            setThermal(NSProcessInfoThermalStateSerious);
        }],
        @[@0.6, ^{
            [self expect:visualiserView() && !link() && !SGRHarnessReading() step:@"hot: the hills stand down (still on the field)" detail:@""];
            [store setBool:YES forKey:SGRKeyVisualiserIgnoreHeat];
            SGRVisualiserIgnoreHeatChanged();
        }],
        @[@0.3, ^{
            [self expect:link() && SGRHarnessReading() step:@"hot, ignore switched on: moving at once" detail:@""];
            sg_lowPower = YES;
            [NSNotificationCenter.defaultCenter postNotificationName:NSProcessInfoPowerStateDidChangeNotification object:nil];
        }],
        @[@0.6, ^{
            [self expect:!link() && !SGRHarnessReading() step:@"hot, ignoring: Low Power Mode still stands it down" detail:@""];
            sg_lowPower = NO;
            [NSNotificationCenter.defaultCenter postNotificationName:NSProcessInfoPowerStateDidChangeNotification object:nil];
        }],
        @[@0.6, ^{
            [self expect:link() && SGRHarnessReading() step:@"Low Power Mode off, still hot and ignoring" detail:@""];
            [store setBool:NO forKey:SGRKeyVisualiserIgnoreHeat];
            SGRVisualiserIgnoreHeatChanged();
        }],
        @[@0.3, ^{
            [self expect:!link() && !SGRHarnessReading() step:@"ignore switched off while hot: stands down at once" detail:@""];
            setThermal(NSProcessInfoThermalStateNominal);
        }],
        @[@0.6, ^{
            [self expect:link() && SGRHarnessReading() step:@"cooled: moving again" detail:@""];
            // The Visualizer for a missing clip, which a hot iPhone gives back to the cover.
            [store setBool:YES forKey:SGRKeyPlayerAnimatedVisualiser];
            background(SGRPlayerBackgroundAnimated);
        }],
        @[@1.5, ^{
            [self expect:visualiserView() && SGRPlayerVisualiserShowing() step:@"Animated, no clip: the Visualizer" detail:@""];
            setThermal(NSProcessInfoThermalStateCritical);
        }],
        @[@1, ^{
            [self expect:!visualiserView() && !SGRPlayerVisualiserShowing() && !SGRPlayerMotionShowing() && !SGRHarnessReading()
                    step:@"hot: the ordinary cover" detail:@""];
            [store setBool:YES forKey:SGRKeyVisualiserIgnoreHeat];
            SGRVisualiserIgnoreHeatChanged();
        }],
        @[@0.3, ^{
            [self expect:visualiserView() && SGRPlayerVisualiserShowing() && SGRHarnessReading() step:@"hot, ignoring: the Visualizer stays" detail:@""];
            sg_lowPower = YES;
            [NSNotificationCenter.defaultCenter postNotificationName:NSProcessInfoPowerStateDidChangeNotification object:nil];
            // Sample the fade after the notification's main-queue callbacks, before a later layout can repair it.
            dispatch_async(dispatch_get_main_queue(), ^{
                UIView *content = [visualiserView() valueForKey:@"_content"];
                standInLeaving = content.alpha == 0;
            });
        }],
        @[@0.6, ^{
            [self expect:standInLeaving && !visualiserView() && !SGRHarnessReading() step:@"hot, ignoring: Low Power removes the stand-in without layout" detail:@""];
            sg_lowPower = NO;
            [NSNotificationCenter.defaultCenter postNotificationName:NSProcessInfoPowerStateDidChangeNotification object:nil];
        }],
        @[^BOOL { return visualiserView() && SGRHarnessReading(); }, ^{
            [self->_background viewWillDisappear:NO];
            [self->_background viewDidDisappear:NO];
        }],
        @[^BOOL { return !visualiserView(); }, ^{
            [self->_background viewWillAppear:NO];
            [self->_background viewDidAppear:NO];
        }],
        @[@0.3, ^{
            [self expect:visualiserView() && SGRHarnessReading() step:@"hot, ignoring: reopening the same track restores the stand-in without cooling" detail:@""];
            NSLog(@"[harness] %@", finishChecks(self->_checks, self->_failures, @"heat"));
            exit(self->_failures ? 1 : 0);
        }],
    ], 0);
}

- (void)runControlsChecks {
    static char ordinaryKey, djKey;
    UIView *owner = [UIView new];
    SGRGlyphView *glyph = SGRPlayerGlyphFor(owner, &ordinaryKey, @"backward.fill", 32);
    [self expect:glyph == SGRPlayerGlyphFor(owner, &ordinaryKey, @"pause.fill", 44)
            step:@"controls reuse the owner's glyph" detail:@"later symbol and size do not replace it"];
    [self expect:[glyph.symbol isEqualToString:@"backward.fill"]
            step:@"reuse preserves the original symbol" detail:glyph.symbol];
    [self expect:[glyph.preferredSymbolConfiguration isEqual:
                  [UIImageSymbolConfiguration configurationWithPointSize:32 weight:UIImageSymbolWeightRegular]]
            step:@"reuse preserves the original point size" detail:@"32pt regular, not the requested 44pt"];
    UIView *djGlyph = (UIView *)SGRPlayerGlyphFor(owner, &djKey, @"forward.fill", 32);
    [self expect:djGlyph != glyph step:@"controls keep association keys separate" detail:@"ordinary and DJ keys"];
    UIView *host = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 100, 60)];
    SGRPlayerPlaceGlyph(glyph, host, 0);
    [self expect:CGPointEqualToPoint(glyph.center, CGPointMake(50, 30))
            step:@"ordinary glyph is centered" detail:NSStringFromCGPoint(glyph.center)];
    SGRPlayerPlaceGlyph(djGlyph, host, 4);
    [self expect:CGPointEqualToPoint(djGlyph.center, CGPointMake(50, 34))
            step:@"DJ glyph retains its vertical offset" detail:NSStringFromCGPoint(djGlyph.center)];
    host.frame = CGRectMake(0, 0, 200, 100);
    [self expect:CGPointEqualToPoint(glyph.center, CGPointMake(100, 50))
            step:@"centered glyph follows host resizing" detail:NSStringFromCGPoint(glyph.center)];
    [host addSubview:[UIView new]];
    SGRPlayerPlaceGlyph(djGlyph, host, 4);
    [self expect:host.subviews.lastObject == djGlyph step:@"glyph returns above new content" detail:@"same host"];
    UIView *nextHost = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 80, 40)];
    SGRPlayerPlaceGlyph(djGlyph, nextHost, 4);
    [self expect:djGlyph.superview == nextHost && CGPointEqualToPoint(djGlyph.center, CGPointMake(40, 24))
            step:@"glyph moves to a new host" detail:NSStringFromCGPoint(djGlyph.center)];
    [self runSpreadChecks];
    [NSUserDefaults.standardUserDefaults removeObjectForKey:SGRKeyPlayerHideShuffle];
    [NSUserDefaults.standardUserDefaults removeObjectForKey:SGRKeyPlayerHideRepeat];
    NSLog(@"[harness] controls checks: %lu of %lu right -- %@", (unsigned long)(_checks - _failures),
          (unsigned long)_checks, _failures ? @"FAIL" : @"PASS");
    exit(_failures ? 1 : 0);
}

// One of the controls row's five holders (trees/clean/player/01.txt, .mixdog's phone tree): an arranged view `side`
// square holding a plain view that holds the button.
static UIView *controlSlot(UIStackView *row, CGFloat side, Class cls, NSString *identifier) {
    UIView *slot = [[UIView alloc] initWithFrame:CGRectMake(0, 0, side, side)];
    [slot.widthAnchor constraintEqualToConstant:side].active = YES;
    [slot.heightAnchor constraintEqualToConstant:side].active = YES;
    UIView *inner = box(slot, UIView.class, slot.bounds, nil);
    UIView *button = box(inner, cls, inner.bounds, identifier);
    box(button, UIView.class, button.bounds, nil);   // the content view the skip glyphs go in
    [row addArrangedSubview:slot];
    return slot;
}

// Shuffle and repeat both hidden (switched on for this scenario at launch): previous and next spread a third of the
// room between the Music app's 32 pt margins of the 390 pt unit ((390 - 64) / 3 pt) either side of play, and stay spread while Spotify takes repeat out, lays the controls out and
// puts a new repeat in, or swaps repeat's end for a bare placeholder and then a new holder. The emptied ends take no
// touches meanwhile, so a touch on next where it overlaps repeat's end is next's. A landscape row and a row whose ends
// hold other controls (a podcast's) get Spotify's places and the ends' touches back.
- (void)runSpreadChecks {
    UIView *host = box(self.window.rootViewController.view, UIView.class, CGRectMake(0, 200, 390, 96), nil);
    UIStackView *row = [[UIStackView alloc] initWithFrame:CGRectMake(12, 16, 366, 64)];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.alignment = UIStackViewAlignmentCenter;
    row.distribution = UIStackViewDistributionEqualSpacing;
    [host addSubview:row];
    UIView *shuffleEnd = controlSlot(row, 48, MockEncoreButton.class, @"Components.UI.ShuffleButton");
    UIView *previous = controlSlot(row, 56, MockEncoreButton.class, @"SPTNowPlayingPreviousTrackButton");
    UIView *play = controlSlot(row, 64, _TtC28EncoreConsumerMobile_BaseKit14PlayButtonView.class, @"SPTNowPlayingPlayButton");
    UIView *next = controlSlot(row, 56, MockEncoreButton.class, @"SPTNowPlayingNextTrackButton");
    __block UIView *repeatEnd = controlSlot(row, 48, MockEncoreButton.class, @"Nowplaying-RepeatButton");
    UIView *nextButton = next.subviews.firstObject.subviews.firstObject;
    UIViewController *unit = [_TtC20NowPlaying_ModesImpl28PlaybackControlsElementsUnit new];
    unit.view = host;
    // A pass of the unit as Spotify gives it, the row laid out by its constraints first.
    void (^pass)(void) = ^{
        [row setNeedsLayout];
        [row layoutIfNeeded];
        [unit viewDidLayoutSubviews];
    };
    // Where previous and next are drawn from play's middle, and whether a touch over the part of next that lies over
    // repeat's end (8 pt in from next's outer edge) reaches next.
    NSString *(^state)(BOOL *, BOOL) = ^NSString *(BOOL *right, BOOL spread) {
        CGFloat playX = play.center.x;
        CGFloat previousAt = previous.center.x + previous.transform.tx - playX, nextAt = next.center.x + next.transform.tx - playX;
        CGFloat side = nextAt < 0 ? -1 : 1;
        CGPoint outer = [self.window convertPoint:CGPointMake(next.center.x + next.transform.tx + side * 20, next.center.y) fromView:row];
        UIView *hit = [self.window hitTest:outer withEvent:nil];
        BOOL onNext = [hit isDescendantOfView:nextButton];
        BOOL quiet = !shuffleEnd.userInteractionEnabled && !repeatEnd.userInteractionEnabled;
        const CGFloat reach = (390 - 2 * 32) / 3.0;
        BOOL placed = spread ? fabs(fabs(previousAt) - reach) < 0.5 && fabs(fabs(nextAt) - reach) < 0.5 && previousAt * nextAt < 0
                             : CGAffineTransformIsIdentity(previous.transform) && CGAffineTransformIsIdentity(next.transform);
        *right = placed && (spread ? quiet && onNext : shuffleEnd.userInteractionEnabled && repeatEnd.userInteractionEnabled);
        return [NSString stringWithFormat:@"previous %+.1f, next %+.1f pt from play; ends %@; a touch on next over repeat's end lands on %@",
                previousAt, nextAt, quiet ? @"take no touches" : @"take touches", onNext ? @"next" : NSStringFromClass(hit.class)];
    };
    BOOL right = NO;
    NSString *seen;

    pass();
    seen = state(&right, YES);
    [self expect:right step:@"both hidden: previous and next spread" detail:seen];

    UIView *repeatHolder = repeatEnd.subviews.firstObject;
    [repeatHolder.subviews.firstObject removeFromSuperview];
    pass();
    seen = state(&right, YES);
    [self expect:right step:@"repeat taken out and the controls laid out: still spread" detail:seen];

    UIView *replacement = box(repeatHolder, MockEncoreButton.class, repeatHolder.bounds, @"Nowplaying-RepeatButton");
    [host layoutIfNeeded];
    seen = state(&right, YES);
    [self expect:right && replacement.alpha == 0 && !replacement.userInteractionEnabled step:@"a new repeat put in: hidden, still spread"
          detail:[seen stringByAppendingFormat:@"; the new repeat at alpha %.0f", replacement.alpha]];

    // Repeat's end swapped for a bare placeholder, as Spotify leaves where it has no repeat, then for a new holder.
    [row removeArrangedSubview:repeatEnd];
    [repeatEnd removeFromSuperview];
    UIView *placeholder = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 48, 48)];
    [placeholder.widthAnchor constraintEqualToConstant:48].active = YES;
    [placeholder.heightAnchor constraintEqualToConstant:48].active = YES;
    [row addArrangedSubview:placeholder];
    repeatEnd = placeholder;
    pass();
    seen = state(&right, YES);
    [self expect:right step:@"repeat's end a bare placeholder: still spread" detail:seen];
    [row removeArrangedSubview:placeholder];
    [placeholder removeFromSuperview];
    repeatEnd = controlSlot(row, 48, MockEncoreButton.class, @"Nowplaying-RepeatButton");
    pass();
    seen = state(&right, YES);
    [self expect:right step:@"a new holder with a new repeat: spread" detail:seen];

    row.semanticContentAttribute = UISemanticContentAttributeForceRightToLeft;
    pass();
    seen = state(&right, YES);
    [self expect:right && next.center.x < play.center.x step:@"right to left: next spread to the left" detail:seen];
    row.semanticContentAttribute = UISemanticContentAttributeUnspecified;

    host.traitOverrides.verticalSizeClass = UIUserInterfaceSizeClassCompact;
    [host updateTraitsIfNeeded];
    pass();
    seen = state(&right, NO);
    [self expect:right step:@"landscape: Spotify's places, the ends' touches back" detail:seen];
    [host.traitOverrides removeTrait:UITraitVerticalSizeClass.class];
    [host updateTraitsIfNeeded];
    pass();
    seen = state(&right, YES);
    [self expect:right step:@"portrait again: spread" detail:seen];

    // A podcast's row in the same holders: other controls at the ends.
    for (UIView *end in @[shuffleEnd, repeatEnd]) {
        UIView *inner = end.subviews.firstObject;
        [inner.subviews.firstObject removeFromSuperview];
        box(inner, MockEncoreButton.class, inner.bounds, end == shuffleEnd ? @"podcast-speed-button" : @"podcast-sleep-timer-button");
    }
    pass();
    seen = state(&right, NO);
    [self expect:right step:@"a podcast's row in the same holders: Spotify's places, the ends' touches back" detail:seen];
    [host removeFromSuperview];
}

- (void)runScrollChecks {
    after(2, ^{
        UIScrollView *list = self->_list;
        CGFloat top = -list.adjustedContentInset.top;
        list.contentOffset = CGPointMake(0, top + 120);
        BOOL up = list.contentOffset.y == top;
        list.contentOffset = CGPointMake(0, top - 80);
        BOOL down = list.contentOffset.y == top - 80;
        [list setContentOffset:CGPointMake(0, top + 300) animated:NO];
        BOOL again = list.contentOffset.y == top;
        list.contentOffset = CGPointMake(0, top);
        NSLog(@"[harness] scroll checks: up %@, down %@, again %@ -- %@", up ? @"held" : @"moved", down ? @"kept" : @"lost",
              again ? @"held" : @"moved", up && down && again ? @"PASS" : @"FAIL");
        if (!(up && down && again)) exit(1);
    });
    // Issue #172: the list's pan is off while the progress bar is scrubbed, back once the scrub ends however
    // it ends, and a pan that was off already stays off.
    after(3, ^{
        UIView *duration = self->_units[1].view;
        UISlider *slider = [[_TtCO17NowPlaying_ECMKit11ProgressBar6Slider alloc] initWithFrame:CGRectMake(24, 0, duration.bounds.size.width - 48, 20)];
        slider.hidden = YES;
        [duration addSubview:slider];
        UIPanGestureRecognizer *pan = self->_list.panGestureRecognizer;
        UITouch *none = nil;   // the mock tracks without one
        NSMutableArray<NSString *> *wrong = [NSMutableArray array];
        void (^expect)(NSString *, BOOL) = ^(NSString *step, BOOL ok) { if (!ok) [wrong addObject:step]; };
        [slider beginTrackingWithTouch:none withEvent:nil];
        expect(@"held while scrubbing", !pan.enabled);
        [slider endTrackingWithTouch:none withEvent:nil];
        expect(@"back at the end", pan.enabled);
        [slider beginTrackingWithTouch:none withEvent:nil];
        [slider cancelTrackingWithEvent:nil];
        expect(@"back at a cancel", pan.enabled);
        [slider beginTrackingWithTouch:none withEvent:nil];
        [slider removeFromSuperview];
        expect(@"back when the slider left the window", pan.enabled);
        [duration addSubview:slider];
        pan.enabled = NO;
        [slider beginTrackingWithTouch:none withEvent:nil];
        [slider endTrackingWithTouch:none withEvent:nil];
        expect(@"off already, left off", !pan.enabled);
        pan.enabled = YES;
        [slider removeFromSuperview];
        NSLog(@"[harness] scrub checks: %@ -- %@", wrong.count ? [wrong componentsJoinedByString:@", "] : @"all right",
              wrong.count ? @"FAIL" : @"PASS");
        exit(wrong.count ? 1 : 0);
    });
}

#pragma mark - the cover's room

// Spotify keeps room for the lyric preview under the cover of a track with lyrics, and the redesign keeps Spotify's
// sizes (as Spotify's Lyrics setting has them). Here the cover is untouched first (a track without lyrics), then given
// Spotify's layout for one with lyrics; either way its top is the Music app's (issue #27).
- (void)runCoverChecks {
    __block NSUInteger right = 0, checks = 0;
    void (^check)(NSString *, BOOL, NSString *) = ^(NSString *step, BOOL ok, NSString *detail) {
        checks++;
        if (ok) right++;
        NSLog(@"[harness] cover %@: %@ -- %@", step, detail, ok ? @"ok" : @"WRONG");
    };
    UIView *tilt = _tilt, *room = tilt.superview;
    UIView *preview = nil;
    for (UIView *view in room.subviews) {
        if ([view isKindOfClass:_TtC22Lyrics_NPVContainerKit19LyricsContainerView.class]) preview = view;
    }
    CGFloat side = MIN(room.bounds.size.width, room.bounds.size.height);
    CGRect square = CGRectMake(round((room.bounds.size.width - side) / 2), round((room.bounds.size.height - side) / 2), side, side);
    // Issue #27: drawn as the Music app's on a 402 pt iPhone, 24 pt in from the sides and 33 pt under the safe area.
    UIWindow *window = self.window;
    CGRect (^musicCover)(void) = ^CGRect {
        return CGRectMake(24, window.safeAreaInsets.top + 33, window.bounds.size.width - 48, window.bounds.size.width - 48);
    };
    after(1.5, ^{
        check(@"without lyrics", CGRectEqualToRect(tilt.frame, square), NSStringFromCGRect(tilt.frame));
        CGRect drawn = SGRPlayerCoverFrameIn(window);
        check(@"drawn where the Music app's is", CGRectEqualToRect(CGRectIntegral(drawn), musicCover()),
              [NSString stringWithFormat:@"%@, want %@", NSStringFromCGRect(drawn), NSStringFromCGRect(musicCover())]);
        // Its top, above the views holding the tilt view, still takes the cover's touches, in the 15 pt the header row
        // and the stack holding it lie over as Spotify's do on the phone (62 to 110); under it, they are gone.
        CGPoint top = CGPointMake(CGRectGetMidX(musicCover()), CGRectGetMinY(musicCover()) + 5);
        CGPoint under = CGPointMake(CGRectGetMidX(musicCover()), CGRectGetMaxY([window convertRect:tilt.bounds fromView:tilt]) - 4);
        UIView *topHit = [window hitTest:top withEvent:nil], *underHit = [window hitTest:under withEvent:nil];
        check(@"the cover's touches where it is drawn", topHit == tilt && underHit != tilt && ![underHit isDescendantOfView:tilt],
              [NSString stringWithFormat:@"its top hits %@, under it %@", NSStringFromClass(topHit.class), NSStringFromClass(underHit.class)]);
        // VoiceOver's cover, the tilt view, focuses and activates where the cover is drawn.
        CGRect focus = tilt.accessibilityFrame, screen = UIAccessibilityConvertFrameToScreenCoordinates(drawn, window);
        CGPoint activation = tilt.accessibilityActivationPoint;
        check(@"VoiceOver's frame and activation point on the drawn cover",
              CGRectEqualToRect(CGRectIntegral(focus), CGRectIntegral(screen)) && fabs(activation.x - CGRectGetMidX(screen)) <= 0.5
                  && fabs(activation.y - CGRectGetMidY(screen)) <= 0.5,
              [NSString stringWithFormat:@"frame %@ at %@, want %@", NSStringFromCGRect(focus), NSStringFromCGPoint(activation), NSStringFromCGRect(screen)]);
        NSLog(@"[harness] cover: screenshot without lyrics now");
        // A page laid out before its artwork band reaches its final origin. Only
        // the ancestor moves back; resizing/re-laying the tilt would mask the bug.
        UIView *band = room.superview;
        CGPoint rest = band.center;
        band.center = CGPointMake(rest.x, rest.y + 135);
        [tilt setNeedsLayout];
        [window layoutIfNeeded];
        band.center = rest;
        [window layoutIfNeeded];
        CGRect returned = SGRPlayerCoverFrameIn(window);
        check(@"same-sized page after its band moves back", CGRectEqualToRect(CGRectIntegral(returned), musicCover()),
              NSStringFromCGRect(returned));
    });
    // Where it plays from shown (Hide where it plays from switched off on the Player page, the switch's own path): the
    // row takes its touches again and the cover stays under it; switched on again, the cover is back at the Music app's
    // top, all without a relaunch.
    UIView *header = _units.firstObject.view;
    SGModRow *contextRow = nil;
    for (SGModSection *section in ((SGModPage *)SGRPlayerSettingsPage(@[])).sections)
        for (SGModRow *row in section.rows)
            if ([row.title isEqualToString:@"Hide where it plays from"]) contextRow = row;
    void (^hideContext)(BOOL) = ^(BOOL on) {
        SGSetEnabled(SGRKeyPlayerHideContext, on);
        contextRow.changed(on);
    };
    // The row's band over the cover, left of the grabber, and just under the row.
    NSString *(^band)(CGPoint *, CGPoint *) = ^NSString *(CGPoint *inRow, CGPoint *underRow) {
        CGRect row = [header convertRect:header.bounds toView:nil];
        *inRow = CGPointMake(CGRectGetMinX(musicCover()) + 60, CGRectGetMaxY(row) - 4);
        *underRow = CGPointMake(inRow->x, CGRectGetMaxY(row) + 4);
        UIView *rowHit = [window hitTest:*inRow withEvent:nil], *underHit = [window hitTest:*underRow withEvent:nil];
        return [NSString stringWithFormat:@"cover %@ under the row to %.0f; at %.0f %@, at %.0f %@", NSStringFromCGRect(SGRPlayerCoverFrameIn(window)),
                CGRectGetMaxY(row), inRow->y, [rowHit isDescendantOfView:header] ? @"the row" : NSStringFromClass(rowHit.class),
                underRow->y, underHit == tilt ? @"the cover" : NSStringFromClass(underHit.class)];
    };
    after(1.6, ^{ hideContext(NO); });
    after(1.8, ^{
        CGPoint inRow, underRow;
        NSString *seen = band(&inRow, &underRow);
        CGRect drawn = SGRPlayerCoverFrameIn(window), row = [header convertRect:header.bounds toView:nil];
        check(@"where it plays from shown, the cover under its row, the row's touches its own",
              contextRow && fabs(CGRectGetMinY(drawn) - CGRectGetMaxY(row)) <= 0.5 && CGRectGetWidth(drawn) == CGRectGetWidth(musicCover())
                  && [[window hitTest:inRow withEvent:nil] isDescendantOfView:header] && [window hitTest:underRow withEvent:nil] == tilt,
              seen);
        // Spotify moving the row's stack with no layout of the row (9.2.0 does it by the stack's top constraint,
        // PlayerHeader.x): the cover's top follows the row's bottom, never under Spotify's own place for it.
        UIView *holder = header.superview;
        CGRect rest = holder.frame;
        CGFloat own = CGRectGetMinY([window convertRect:tilt.bounds fromView:tilt]);
        NSMutableArray<NSString *> *moves = [NSMutableArray array];
        BOOL follows = YES;
        for (NSNumber *by in @[@8, @48, @0]) {
            holder.frame = CGRectOffset(rest, 0, by.doubleValue);
            [window layoutIfNeeded];
            CGFloat bottom = CGRectGetMaxY([header convertRect:header.bounds toView:nil]);
            CGFloat want = MIN(own, MAX(CGRectGetMinY(musicCover()), bottom)), top = CGRectGetMinY(SGRPlayerCoverFrameIn(window));
            follows = follows && fabs(top - want) <= 0.5;
            [moves addObject:[NSString stringWithFormat:@"row to %.0f: top %.1f, want %.1f", bottom, top, want]];
        }
        holder.frame = rest;
        check(@"the row moved by Spotify, the cover under where it is now", follows, [moves componentsJoinedByString:@"; "]);
        // The live row moved out of the player, still in the window, low on it, with no layout of the header reaching the
        // redesign: the cover no longer stays under it.
        UIViewController *unit = self->_units.firstObject;
        Class unitClass = object_setClass(unit, SGRHarnessStillHeaderUnit.class);
        CGRect place = header.frame;
        [window.rootViewController.view addSubview:header];
        header.frame = CGRectOffset(place, 0, 200);
        [window layoutIfNeeded];
        CGRect away = SGRPlayerCoverFrameIn(window);
        object_setClass(unit, unitClass);
        [holder addSubview:header];
        header.frame = place;
        [header setNeedsLayout];
        [window layoutIfNeeded];
        CGRect home = SGRPlayerCoverFrameIn(window);
        check(@"the live row moved out of the player, the cover no longer under it",
              CGRectEqualToRect(CGRectIntegral(away), musicCover()) && fabs(CGRectGetMinY(home) - CGRectGetMaxY([header convertRect:header.bounds toView:nil])) <= 0.5,
              [NSString stringWithFormat:@"out of it %@, back in its stack %@", NSStringFromCGRect(away), NSStringFromCGRect(home)]);
        hideContext(YES);
    });
    after(1.95, ^{
        CGPoint inRow, underRow;
        NSString *seen = band(&inRow, &underRow);
        check(@"hidden again, the cover back at the Music app's top through the row's band",
              CGRectEqualToRect(CGRectIntegral(SGRPlayerCoverFrameIn(window)), musicCover()) && [window hitTest:inRow withEvent:nil] == tilt, seen);
        [NSUserDefaults.standardUserDefaults removeObjectForKey:SGRKeyPlayerHideContext];
        SGPrefsChanged();
    });
    after(2, ^{
        // What Spotify does for a track with lyrics: the preview under the cover, the cover shrunk above it.
        CGFloat small = side - 72;
        tilt.frame = CGRectMake(round((room.bounds.size.width - small) / 2), 0, small, small);
        preview.frame = CGRectMake(0, small + 8, room.bounds.size.width, 64);
        [preview invalidateIntrinsicContentSize];
        [self->_covers setNeedsLayout];
        [self->_covers layoutIfNeeded];
    });
    after(2.5, ^{
        CGFloat small = side - 72;
        check(@"with lyrics, Spotify's preview and cover", preview.frame.size.height == 64 && tilt.frame.size.width == small,
              [NSString stringWithFormat:@"preview %@, cover %@", NSStringFromCGRect(preview.frame), NSStringFromCGRect(tilt.frame)]);
        CGRect drawn = SGRPlayerCoverFrameIn(window);
        CGRect want = CGRectMake(CGRectGetMinX([window convertRect:tilt.bounds fromView:tilt]), window.safeAreaInsets.top + 33, small, small);
        check(@"the Kit sees it at the Music app's top", CGRectEqualToRect(CGRectIntegral(drawn), want),
              [NSString stringWithFormat:@"%@, want %@, the picture %@", NSStringFromCGRect(drawn), NSStringFromCGRect(want),
               NSStringFromCGSize(self->_cover.bounds.size)]);
        NSLog(@"[harness] cover: screenshot with lyrics now");
    });
    // The cover's top under the put-away row: a touch there goes through the row and the stack holding it alone as they
    // are at the touch, and nothing of Spotify's is switched off for it. Wherever the row goes, nothing it leaves takes
    // or loses touches: the stack it left, emptied, is Spotify's as it was; another ordinary header put in its stack,
    // put away too, lets the strip through, beside the old one and after it; that one released and the AI DJ's header
    // put in the same stack, its button and row take their touches; the row put back, the strip is the cover again.
    // A control Spotify still shows in the put-away row (an iPad side panel's button to widen the player, in the row's
    // stack of elements; here over the cover's top) takes its touches, a touch landing inside it too; the row's empty
    // band over the cover still goes on to the cover, and beside or over the cover stays the row's, as Spotify's is.
    after(2.55, ^{
        UIView *elements = nil;
        for (UIView *view in header.subviews) if ([view isKindOfClass:UIStackView.class]) elements = view;
        CGRect drawn = SGRPlayerCoverFrameIn(window);
        CGFloat toggleX = [elements convertPoint:CGPointMake(CGRectGetMinX(drawn) + 20, 0) fromView:window].x;
        UIView *toggle = glyphButton(elements, CGRectMake(toggleX, 0, 48, 48), @"sidebar.leading", @"now-playing-toggle-button");
        UIView *glyph = toggle.subviews.firstObject;
        glyph.userInteractionEnabled = YES;
        [window layoutIfNeeded];
        CGFloat toggleMidX = CGRectGetMidX([window convertRect:toggle.bounds fromView:toggle]);
        UIView *glyphHit = [window hitTest:CGPointMake(toggleMidX, CGRectGetMinY(drawn) + 2) withEvent:nil];
        UIView *toggleHit = [window hitTest:CGPointMake(toggleMidX, CGRectGetMinY(drawn) + 12) withEvent:nil];
        UIView *bandHit = [window hitTest:CGPointMake(CGRectGetMidX(drawn), CGRectGetMinY(drawn) + 5) withEvent:nil];
        UIView *besideHit = [window hitTest:CGPointMake(CGRectGetMaxX(drawn) + 8, CGRectGetMinY(drawn) + 5) withEvent:nil];
        UIView *overHit = [window hitTest:CGPointMake(CGRectGetMinX(drawn) + 76, CGRectGetMinY(drawn) - 8) withEvent:nil];
        BOOL besideRow = [besideHit isDescendantOfView:header], overRow = [overHit isDescendantOfView:header];
        [toggle removeFromSuperview];
        check(@"a control shown in the put-away row its own, the row's band the cover's only on the cover",
              elements && glyphHit == glyph && toggleHit == toggle && bandHit == tilt && besideRow && overRow,
              [NSString stringWithFormat:@"over the cover the control's glyph hits %@, the control %@; the band on the cover %@, beside it the row's %d, over it the row's %d",
               NSStringFromClass(glyphHit.class), NSStringFromClass(toggleHit.class), NSStringFromClass(bandHit.class), besideRow, overRow]);
    });
    __block UIView *holder = nil;
    __block CGPoint strip = CGPointZero;
    __block __weak UIView *weakIncoming = nil;
    __block __weak UIViewController *weakIncomingUnit = nil;
    UIView *(^stripHit)(void) = ^UIView * {
        [window layoutIfNeeded];
        return [window hitTest:strip withEvent:nil];
    };
    after(2.6, ^{
        holder = header.superview;
        CGRect drawn = SGRPlayerCoverFrameIn(window);
        strip = CGPointMake(CGRectGetMidX(drawn), CGRectGetMinY(drawn) + 5);
        BOOL before = stripHit() == tilt;
        UIStackView *other = [[UIStackView alloc] initWithFrame:holder.frame];
        [self->_host addSubview:other];
        [other addSubview:header];
        BOOL moved = stripHit() == holder;
        [window.rootViewController.view addSubview:header];
        BOOL outside = stripHit() == other;
        [other removeFromSuperview];
        [holder addSubview:header];
        BOOL back = stripHit() == tilt;
        check(@"the row moved and back, the stacks it left Spotify's as they were", before && moved && outside && back,
              [NSString stringWithFormat:@"through it %d, the stack it left in the player takes the strip %d, out of the player %d, back %d",
               before, moved, outside, back]);

        UIView *(^ordinaryHeader)(UIViewController *) = ^UIView *(UIViewController *unit) {
            UIView *row = [[UIStackView alloc] initWithFrame:holder.bounds];
            UIControl *arrow = (UIControl *)glyphButton(row, CGRectMake(12, 0, 48, 48), @"chevron.down", @"now-playing-minimize-button");
            [arrow addAction:[UIAction actionWithHandler:^(UIAction *action) {}] forControlEvents:UIControlEventTouchUpInside];
            glyphButton(row, CGRectMake(holder.bounds.size.width - 60, 0, 48, 48), @"ellipsis", @"Context menu");
            unit.view = row;
            return row;
        };
        BOOL beside, replaced;
        @autoreleasepool {
            UIViewController *unit = [_TtC20NowPlaying_ModesImpl18HeaderElementsUnit new];
            UIView *incoming = ordinaryHeader(unit);
            [holder addSubview:incoming];
            beside = stripHit() == tilt;
            [header removeFromSuperview];
            replaced = stripHit() == tilt;
            [incoming removeFromSuperview];
            weakIncoming = incoming;
            weakIncomingUnit = unit;
        }
        check(@"an ordinary header in the stack after another, the strip still the cover's", beside && replaced,
              [NSString stringWithFormat:@"beside the old one %d, after it %d", beside, replaced]);
        // The second one gone from the stack and released by the run loop's next turns (UIKit lets a unit laid out in a
        // window go only then), the AI DJ's header goes in.
        after(0.3, ^{
            BOOL released = !weakIncoming && !weakIncomingUnit;
            UIViewController *djUnit = [_TtC19Endless_DJMusicImpl35DJMHeaderElementsUnitViewController new];
            UIView *dj = [[UIView alloc] initWithFrame:holder.bounds];
            UIView *button = glyphButton(dj, CGRectMake(12, 0, 48, 48), @"chevron.down", @"now-playing-minimize-button");
            glyphButton(dj, CGRectMake(holder.bounds.size.width - 60, 0, 48, 48), @"ellipsis", @"Context menu");
            djUnit.view = dj;
            [holder addSubview:dj];
            UIView *rowHit = stripHit();
            UIView *buttonHit = [window hitTest:[window convertPoint:button.center fromView:dj] withEvent:nil];
            [dj removeFromSuperview];
            [holder addSubview:header];
            BOOL again = stripHit() == tilt;
            BOOL untouched = holder.userInteractionEnabled && header.userInteractionEnabled;
            check(@"the old header released, the AI DJ's in its stack live, the row back through it",
                  released && rowHit == dj && buttonHit == button && again && untouched,
                  [NSString stringWithFormat:@"released %d, the DJ's row takes %@, its button %@; the row back %d, nothing switched off %d",
                   released, NSStringFromClass(rowHit.class), NSStringFromClass(buttonHit.class), again, untouched]);
            NSLog(@"[harness] cover checks: %lu of %lu right -- %@", (unsigned long)right, (unsigned long)checks, right == checks ? @"PASS" : @"FAIL");
            exit(right == checks ? 0 : 1);
        });
    });
}

#pragma mark - the lines on their own

static UIView *lyricsOverlay(UIView *host) {
    for (UIView *view in host.subviews) {
        if ([NSStringFromClass(view.class) isEqualToString:@"SGRPlayerLyricsOverlay"]) return view;
    }
    return nil;
}

// Whether the lines' own tap, the one that seeks, is on.
static BOOL linesSeek(SGRKaraokeView *lyrics) {
    BOOL on = NO;
    for (UIGestureRecognizer *recognizer in lyrics.gestureRecognizers) {
        if ([recognizer isKindOfClass:UITapGestureRecognizer.class]) on = on || recognizer.enabled;
    }
    return on;
}

// Exercise Keep the title on the first open, then the unset (Everything) choice on the second.
- (void)runImmersiveChecks {
    __block NSUInteger right = 0, checks = 0;
    void (^check)(NSString *, BOOL, NSString *) = ^(NSString *step, BOOL ok, NSString *detail) {
        checks++;
        if (ok) right++;
        NSLog(@"[harness] immersive %@: %@ -- %@", step, detail, ok ? @"ok" : @"WRONG");
    };
    UIView *host = _host;
    UIView *(^unitView)(Class) = ^UIView *(Class type) {
        for (UIViewController *unit in self->_units) if ([unit isKindOfClass:type]) return unit.view;
        HARNESS_FAIL(@"immersive: missing %@", NSStringFromClass(type));
    };
    UIView *info = unitView(_TtC20NowPlaying_ModesImpl23InformationElementsUnit.class);
    UIView *floating = unitView(_TtC20NowPlaying_ModesImpl20FloatingElementsUnit.class);
    UIView *duration = unitView(_TtC20NowPlaying_ModesImpl19DurationElementUnit.class);
    UIView *playback = unitView(_TtC20NowPlaying_ModesImpl28PlaybackControlsElementsUnit.class);
    UIView *footer = unitView(_TtC20NowPlaying_ModesImpl18FooterElementsUnit.class);
    UIGestureRecognizer *wake = nil;
    for (UIGestureRecognizer *recognizer in host.gestureRecognizers) {
        if ([NSStringFromClass(recognizer.class) isEqualToString:@"SGRPlayerWake"]) wake = recognizer;
    }
    __block CGRect withControls = CGRectNull;
    UIView *(^stage)(void) = ^UIView *{ return [lyricsOverlay(host) valueForKey:@"stage"]; };
    SGRKaraokeView *(^lines)(void) = ^SGRKaraokeView *{ return [lyricsOverlay(host) valueForKey:@"lyrics"]; };
    // Everything in the bottom stack but the title row and the chips: the volume row too, where there is one.
    NSMutableArray<UIView *> *lower = [NSMutableArray array];
    for (UIView *view in info.superview.subviews) {
        if (view != info && view != floating) [lower addObject:view];
    }
    BOOL (^lowerHidden)(void) = ^BOOL { for (UIView *v in lower) if (v.alpha != 0) return NO; return lower.count >= 3; };
    BOOL (^lowerShown)(void) = ^BOOL { for (UIView *v in lower) if (v.alpha != 1) return NO; return lower.count >= 3; };

    NSUserDefaults *prefs = NSUserDefaults.standardUserDefaults;
    id previousHide = [prefs objectForKey:SGRKeyLyricsAutoHide], previousMic = [prefs objectForKey:SGKeySingButton];
    after(1.5, ^{
        SGSetEnabled(SGKeySingButton, YES);
        SGSetInt(SGRKeyLyricsAutoHide, SGRLyricsHideControls);
        SGRPlayerToggleLyrics();
    });
    after(3, ^{
        withControls = [host convertRect:stage().bounds fromView:stage()];
        check(@"open, with the controls", SGRPlayerLyricsOpen() && lowerShown() && !wake.enabled && linesSeek(lines()),
              [NSString stringWithFormat:@"lines %@, wake %d, lines seek %d", NSStringFromCGRect(withControls), wake.enabled, linesSeek(lines())]);
    });
    // kRest is 4 s from the open.
    after(7, ^{
        UIView *thumb = [lyricsOverlay(host) valueForKey:@"thumb"];
        check(@"only the controls under the lines fade", lowerHidden() && info.alpha == 1 && thumb.alpha == 1,
              [NSString stringWithFormat:@"%lu views under the title row %@, progress %.0f, buttons %.0f, footer %.0f, title row %.0f, thumbnail %.0f",
               (unsigned long)lower.count, lowerHidden() ? @"faded" : @"not all faded", duration.alpha, playback.alpha, footer.alpha, info.alpha, thumb.alpha]);
        CGRect alone = [host convertRect:stage().bounds fromView:stage()];
        CGRect safe = UIEdgeInsetsInsetRect(host.bounds, host.safeAreaInsets);
        check(@"the lines grow down only", CGRectGetMinY(alone) == CGRectGetMinY(withControls) && CGRectGetMaxY(alone) > CGRectGetMaxY(withControls)
              && CGRectGetMaxY(alone) <= CGRectGetMaxY(safe),
              [NSString stringWithFormat:@"%@ from %@, safe area to %.0f", NSStringFromCGRect(alone), NSStringFromCGRect(withControls), CGRectGetMaxY(safe)]);
        // Where the buttons were, the lines now take the touch: a drag scrolls them.
        CGPoint onButtons = [host convertPoint:CGPointMake(CGRectGetMidX(playback.bounds), CGRectGetMidY(playback.bounds)) fromView:playback];
        UIView *hit = [host hitTest:onButtons withEvent:nil];
        check(@"a touch on the lines lands on them", [hit isDescendantOfView:lines()],
              [NSString stringWithFormat:@"%@", NSStringFromClass(hit.class)]);
        CGPoint onThumb = [host convertPoint:CGPointMake(CGRectGetMidX(thumb.bounds), CGRectGetMidY(thumb.bounds)) fromView:thumb];
        UIView *thumbHit = [host hitTest:onThumb withEvent:nil];
        check(@"the thumbnail takes its touch", [thumbHit isDescendantOfView:thumb], NSStringFromClass(thumbHit.class));
        check(@"a tap wakes, the lines do not seek", wake.enabled && !linesSeek(lines()),
              [NSString stringWithFormat:@"wake %d, lines seek %d", wake.enabled, linesSeek(lines())]);
        NSLog(@"[harness] immersive: screenshot alone now");
    });
    after(8, ^{
        [wake sgr_woke];
        // Off still for the rest of this turn of the run loop, which the tap that woke is part of.
        check(@"the waking tap does not seek", lowerShown() && !linesSeek(lines()),
              [NSString stringWithFormat:@"controls %.0f, lines seek %d", duration.alpha, linesSeek(lines())]);
    });
    after(8.5, ^{
        check(@"woken", lowerShown() && !wake.enabled && linesSeek(lines()),
              [NSString stringWithFormat:@"controls %.0f, wake %d, lines seek %d", duration.alpha, wake.enabled, linesSeek(lines())]);
        // A scroll through the lines leaves them alone at once.
        lines().browsingBegan();
        check(@"a scroll hides the controls", lowerHidden() && wake.enabled, [NSString stringWithFormat:@"controls %.0f", duration.alpha]);
    });
    after(9, ^{ [wake sgr_woke]; });
    after(9.5, ^{
        UIView *thumb = [lyricsOverlay(host) valueForKey:@"thumb"];
        CGPoint center = [thumb convertPoint:CGPointMake(CGRectGetMidX(thumb.bounds), CGRectGetMidY(thumb.bounds)) toView:host];
        BOOL reachable = [[host hitTest:center withEvent:nil] isDescendantOfView:thumb];
        [lyricsOverlay(host) sgr_thumbTapped];
        check(@"the woken thumbnail closes the lyrics", reachable && !SGRPlayerLyricsOpen() && lowerShown() && !wake.enabled,
              [NSString stringWithFormat:@"lyrics %@, controls %.0f", SGRPlayerLyricsOpen() ? @"up" : @"down", duration.alpha]);
    });
    // A sheet over the player keeps the controls up past the rest, and the clock runs again behind it, so
    // they fade within a rest of the sheet going.
    after(11.5, ^{
        [prefs removeObjectForKey:SGRKeyLyricsAutoHide];
        SGPrefsChanged();
        SGRPlayerToggleLyrics();
    });
    __block UIViewController *sheet = nil;
    after(12, ^{
        sheet = [UIViewController new];
        sheet.view.backgroundColor = UIColor.darkGrayColor;
        [self.window.rootViewController presentViewController:sheet animated:NO completion:nil];
    });
    after(17, ^{
        check(@"a sheet keeps the controls up", SGRPlayerLyricsOpen() && lowerShown(), [NSString stringWithFormat:@"controls %.0f", duration.alpha]);
        [sheet dismissViewControllerAnimated:NO completion:nil];
    });
    after(22, ^{
        check(@"they fade once the sheet has gone", lowerHidden(), [NSString stringWithFormat:@"controls %.0f", duration.alpha]);
        UIView *thumb = [lyricsOverlay(host) valueForKey:@"thumb"];
        check(@"by default the title and thumbnail fade too", thumb && thumb.alpha == 0 && info.alpha == 0,
              [NSString stringWithFormat:@"title row %.0f, thumbnail %.0f", info.alpha, thumb.alpha]);
        CGRect alone = [host convertRect:stage().bounds fromView:stage()];
        CGRect safe = UIEdgeInsetsInsetRect(host.bounds, host.safeAreaInsets);
        check(@"by default the lines grow up and down", CGRectGetMinY(alone) < CGRectGetMinY(withControls)
              && CGRectGetMaxY(alone) > CGRectGetMaxY(withControls) && CGRectContainsRect(safe, alone),
              [NSString stringWithFormat:@"%@ from %@, safe area %@", NSStringFromCGRect(alone), NSStringFromCGRect(withControls), NSStringFromCGRect(safe)]);
        // Sing's mic stays with the lines on their own, and takes its own touch.
        UIView *mic = nil;
        for (UIView *view in lines().subviews) {
            if ([NSStringFromClass(view.class) isEqualToString:@"SGRSingButton"]) mic = view;
        }
        CGPoint onMic = [host convertPoint:CGPointMake(CGRectGetMidX(mic.bounds), CGRectGetMidY(mic.bounds)) fromView:mic];
        UIView *hit = [host hitTest:onMic withEvent:nil];
        CGRect drawn = [host convertRect:mic.bounds fromView:mic];
        check(@"the mic stays and takes its touch", mic && ![[mic valueForKey:@"tucked"] boolValue] && mic.userInteractionEnabled && [hit isDescendantOfView:mic]
              && CGRectGetMaxY(drawn) > CGRectGetMaxY(withControls),
              [NSString stringWithFormat:@"mic %@ at %@, hit %@", mic ? @"there" : @"missing", NSStringFromCGRect(drawn), NSStringFromClass(hit.class)]);
        NSLog(@"[harness] immersive: screenshot the mic alone now");
    });
    after(28, ^{ [wake sgr_woke]; });
    // A finger held on the player (Sing's slider) holds the clock, and lifting it starts the clock over.
    __block UIGestureRecognizer *watcher = nil;
    after(28.5, ^{
        for (UIGestureRecognizer *recognizer in host.gestureRecognizers) {
            if ([NSStringFromClass(recognizer.class) isEqualToString:@"SGRPlayerTouchWatcher"]) watcher = recognizer;
        }
        [watcher touchesBegan:[NSSet set] withEvent:[UIEvent new]];
    });
    after(34, ^{
        check(@"a finger held keeps the controls up", watcher && lowerShown(), [NSString stringWithFormat:@"controls %.0f", duration.alpha]);
        [watcher reset];
    });
    after(39, ^{
        check(@"lifted, the clock runs out", lowerHidden(), [NSString stringWithFormat:@"controls %.0f", duration.alpha]);
    });
    after(40, ^{
        [prefs setObject:previousHide forKey:SGRKeyLyricsAutoHide];
        [prefs setObject:previousMic forKey:SGKeySingButton];
        SGPrefsChanged();
        NSLog(@"[harness] immersive checks: %lu of %lu right -- %@", (unsigned long)right, (unsigned long)checks, right == checks ? @"PASS" : @"FAIL");
        if (right != checks) exit(1);
    });
}

#pragma mark - the time row and the audio quality badge

// Where UIKit puts `label`'s first baseline, in `view`: a probe held to it by Auto Layout, under every transform above.
static CGFloat uikitBaseline(UILabel *label, UIView *view) {
    UIView *probe = [UIView new];
    probe.translatesAutoresizingMaskIntoConstraints = NO;
    [label.superview addSubview:probe];
    [NSLayoutConstraint activateConstraints:@[
        [probe.topAnchor constraintEqualToAnchor:label.firstBaselineAnchor], [probe.leadingAnchor constraintEqualToAnchor:label.leadingAnchor],
        [probe.widthAnchor constraintEqualToConstant:1], [probe.heightAnchor constraintEqualToConstant:1],
    ]];
    [label.superview layoutIfNeeded];
    CGFloat y = [probe.superview convertPoint:probe.frame.origin toView:view].y;
    [probe removeFromSuperview];
    return y;
}

// The opacity of an image's middle pixel.
static CGFloat middleAlpha(UIImage *image) {
    if (!image) return -1;
    uint8_t pixel[4] = {0};
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(pixel, 1, 1, 8, 4, space, kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(space);
    UIGraphicsPushContext(context);
    [image drawAtPoint:CGPointMake(-floor(image.size.width / 2), -floor(image.size.height / 2))];
    UIGraphicsPopContext();
    CGContextRelease(context);
    return pixel[3] / 255.0;
}

// The opacity, 0 to 255, of the pixels at `points` (in pixels, 3 per point) of `view`'s own drawing, nothing behind it.
static NSArray<NSNumber *> *drawnAlphas(UIView *view, NSArray<NSValue *> *points) {
    [view setNeedsDisplay];
    [view.layer displayIfNeeded];
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat];
    format.scale = 3;
    format.opaque = NO;
    UIImage *image = [[[UIGraphicsImageRenderer alloc] initWithSize:view.bounds.size format:format]
        imageWithActions:^(UIGraphicsImageRendererContext *context) { [view.layer renderInContext:context.CGContext]; }];
    CGImageRef cg = image.CGImage;
    size_t width = CGImageGetWidth(cg), height = CGImageGetHeight(cg);
    uint8_t *pixels = calloc(width * height, 4);
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(pixels, width, height, 8, width * 4, space, kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(space);
    CGContextDrawImage(context, CGRectMake(0, 0, width, height), cg);
    CGContextRelease(context);
    NSMutableArray<NSNumber *> *alphas = [NSMutableArray array];
    for (NSValue *value in points) {
        CGPoint p = value.CGPointValue;
        [alphas addObject:@(pixels[((size_t)p.y * width + (size_t)p.x) * 4 + 3])];
    }
    free(pixels);
    return alphas;
}

// A track image as Spotify's bar has it: a 7x7 rounded square in one color, resizable in the middle.
static UIImage *spotifyTrack(UIColor *color) {
    UIImage *image = [[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(7, 7)] imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [color setFill];
        [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, 7, 7) cornerRadius:3.5] fill];
    }];
    return [image resizableImageWithCapInsets:UIEdgeInsetsMake(0, 3, 0, 3)];
}

// Spotify's progress bar element as trees/clean (player-off-full-tree.txt:1902-1916) has it: the slider 17pt tall at
// y 10, its tracks 7pt images, and under it the two times, Encore labels 15.33pt tall drawing 11pt digits through a
// UILabel with Encore's line height. Returns the slider; the times' labels come back in `labels`.
static UISlider *spotifyBar(UIView *unit, NSArray<UILabel *> **labels) {
    CGFloat W = unit.bounds.size.width;
    UISlider *slider = [[_TtCO17NowPlaying_ECMKit11ProgressBar6Slider alloc] initWithFrame:CGRectMake(22, 10, W - 44, 17)];
    slider.accessibilityIdentifier = @"SPTNowPlayingSliderV2";
    slider.value = 0.3;
    [slider setMinimumTrackImage:spotifyTrack(UIColor.whiteColor) forState:UIControlStateNormal];
    [slider setMaximumTrackImage:spotifyTrack([UIColor colorWithWhite:1 alpha:0.3]) forState:UIControlStateNormal];
    [slider setThumbImage:[UIImage new] forState:UIControlStateNormal];
    [unit addSubview:slider];
    NSMutableArray<UILabel *> *made = [NSMutableArray array];
    for (NSArray *time in @[@[@"now-playing-time-take-label", @"0:25", @24], @[@"now-playing-time-remaning-label", @"-2:47", @(W - 24 - 28)]]) {
        UIView *outer = [[SPTEncoreLabel alloc] initWithFrame:CGRectMake([time[2] doubleValue], 26, 28, 15.33)];
        outer.accessibilityIdentifier = time[0];
        UILabel *label = [[UILabel alloc] initWithFrame:outer.bounds];
        label.accessibilityIdentifier = [time[0] stringByAppendingString:@"-internal"];
        NSMutableParagraphStyle *line = [NSMutableParagraphStyle new];
        line.minimumLineHeight = line.maximumLineHeight = 15.33;
        label.attributedText = [[NSAttributedString alloc] initWithString:time[1] attributes:@{
            NSFontAttributeName: [UIFont monospacedDigitSystemFontOfSize:11 weight:UIFontWeightRegular],
            NSForegroundColorAttributeName: [UIColor colorWithWhite:1 alpha:0.7], NSParagraphStyleAttributeName: line}];
        [outer addSubview:label];
        [unit addSubview:outer];
        [made addObject:label];
    }
    *labels = made;
    return slider;
}

// The redesign's time row and its audio quality badge (PlayerControls.x, Shared/Player/AudioQuality.x) on a mock of
// Spotify's bar, with Spotify reporting High (bitrateLevel 3): the Music app's measures (its player, 2026-11 screenshot:
// the digits 14pt under the bar, the badge 9.5pt under it with its text on the times' baseline), the redesign's words
// and details, the bar translucent and lit whole while a finger scrubs; then the native look's badge, as it was.
// SponsorBlock's marks on the redesign's bar (harness/sponsorblock/markers-check.m): Spotify's bar in the duration unit,
// drawn translucent by the unit's layout, scrubbed in code with animations off so the drawn window is the end state.
- (void)runSponsorBlockChecks {
    UIViewController *durationUnit = nil;
    for (UIViewController *candidate in _units) {
        if ([candidate isKindOfClass:_TtC20NowPlaying_ModesImpl19DurationElementUnit.class]) durationUnit = candidate;
    }
    HARNESS_CHECK(durationUnit != nil);
    UIView *unit = durationUnit.view;
    unit.subviews.firstObject.hidden = YES; // the launch's drawn stand-in for the bar
    NSArray<UILabel *> *labels;
    UISlider *slider = spotifyBar(unit, &labels);
    [durationUnit viewDidLayoutSubviews];
    [unit layoutIfNeeded];
    NSString *shots = NSProcessInfo.processInfo.environment[@"HARNESS_SHOTS"] ?: NSTemporaryDirectory();
    NSUInteger wrong = SBMarksRun(slider, @"redesign", ^(BOOL dragging) {
        [UIView setAnimationsEnabled:NO];
        UITouch *none = nil;
        if (dragging) [slider beginTrackingWithTouch:none withEvent:nil];
        else [slider endTrackingWithTouch:none withEvent:nil];
        [UIView setAnimationsEnabled:YES];
    }, shots);
    exit(wrong ? 1 : 0);
}

- (void)runTimeRowChecks {
    UIViewController *durationUnit = _units[2];
    UIView *unit = durationUnit.view;
    unit.frame = CGRectMake(unit.frame.origin.x, unit.frame.origin.y, unit.bounds.size.width, 41.33);
    NSArray<UILabel *> *labels;
    UISlider *slider = spotifyBar(unit, &labels);
    [NSUserDefaults.standardUserDefaults setBool:YES forKey:SGKeyPlayerAudioQuality];
    SGAudioQualitySettingChanged();
    SPTPlayerState *state = SGPlayerState();
    SGRHarnessQuality *quality = [SGRHarnessQuality new];
    quality.bitrateLevel = 3;
    quality.strategy = 1;
    [state setValue:quality forKey:@"playbackQuality"];
    extern void SGRHarnessReport(SPTPlayerState *state);
    SGRHarnessReport(state);
    [durationUnit viewDidLayoutSubviews];
    [unit layoutIfNeeded];

    __block UIView *badge = SGAudioQualityShownBadge(unit);
    UILabel *elapsed = labels.firstObject;
    UIFont *digits = [elapsed.attributedText attribute:NSFontAttributeName atIndex:0 effectiveRange:NULL];
    CGFloat track = CGRectGetMaxY([unit convertRect:[slider trackRectForBounds:slider.bounds] fromView:slider]);
    CGFloat baseline = uikitBaseline(elapsed, unit);
    CGFloat (^badgeBaseline)(void) = ^CGFloat {
        UIFont *font = [badge valueForKey:@"font"];
        return CGRectGetMinY(badge.frame) + badge.bounds.size.height / 2 - font.lineHeight / 2 + font.ascender;
    };
    [self expect:badge != nil step:@"the badge shows" detail:badge ? NSStringFromCGRect(badge.frame) : @"none"];
    [self expect:baseline - digits.capHeight - track >= 12 step:@"the times clear of the bar as the Music app's"
          detail:[NSString stringWithFormat:@"digits %.1f pt under the bar (want 12 or more)", baseline - digits.capHeight - track]];
    [self expect:fabs(badgeBaseline() - baseline) <= 0.5 step:@"the badge's text on the times' baseline"
          detail:[NSString stringWithFormat:@"badge %.2f, elapsed %.2f", badgeBaseline(), baseline]];
    [self expect:CGRectGetMinY(badge.frame) - track >= 8 step:@"the badge clear of the bar"
          detail:[NSString stringWithFormat:@"%.1f pt under it (want 8 or more)", CGRectGetMinY(badge.frame) - track]];
    [self expect:[badge.accessibilityLabel isEqualToString:@"Audio quality, High Quality"] step:@"the badge's words" detail:badge.accessibilityLabel];
    // Issue #27, the Music app's (iOS 26, 3x): 55 px tall, corners of a 14 px circle (the pixel 4 px in from a corner
    // inside, as a capsule's is not), a fill of 17 of 255 at the pixel 4 px from the top. Increase Contrast fills more.
    NSArray<NSValue *> *probes = @[[NSValue valueWithCGPoint:CGPointMake(4, 4)], [NSValue valueWithCGPoint:CGPointMake(30, 4)]];
    NSArray<NSNumber *> *lit = drawnAlphas(badge, probes);
    [self expect:fabs(badge.bounds.size.height - 55 / 3.0) < 0.2 && lit[0].intValue > 8 && abs(lit[1].intValue - 17) <= 2
            step:@"the badge's shape and fill as the Music app's"
          detail:[NSString stringWithFormat:@"%.2f pt tall (want 18.33), corner pixel %@ (want over 8), fill %@ (want 17)",
                  badge.bounds.size.height, lit[0], lit[1]]];
    badge.traitOverrides.accessibilityContrast = UIAccessibilityContrastHigh;
    [badge updateTraitsIfNeeded];
    NSArray<NSNumber *> *contrast = drawnAlphas(badge, probes);
    [badge.traitOverrides removeTrait:UITraitAccessibilityContrast.class];
    [badge updateTraitsIfNeeded];
    [self expect:contrast[1].intValue > lit[1].intValue + 17 step:@"Increase Contrast more opaque"
          detail:[NSString stringWithFormat:@"fill %@, %@ without it", contrast[1], lit[1]]];
    CGFloat fill =middleAlpha([slider minimumTrackImageForState:UIControlStateNormal]), rest = middleAlpha([slider maximumTrackImageForState:UIControlStateNormal]);
    [self expect:fill > 0.5 && fill < 0.7 && rest > 0.15 && rest < 0.25 step:@"the bar translucent"
          detail:[NSString stringWithFormat:@"fill %.2f (want 0.5 to 0.7), track %.2f (want 0.15 to 0.25)", fill, rest]];

    if (getenv("HARNESS_LANDSCAPE")) {
        UIWindowScene *scene = unit.window.windowScene;
        HARNESS_CHECK(scene && UIInterfaceOrientationIsPortrait(scene.interfaceOrientation) && badge);
        // The fixture uses measured frames instead of Spotify's constraints. Pin the controls to
        // the bottom so this same row stays on screen while UIKit resizes the player.
        UIView *bottom = SGRFindByIdentifier(_host, @"npv.bottomStackView", NULL);
        bottom.autoresizingMask |= UIViewAutoresizingFlexibleTopMargin;
        for (UIView *v = _host; v && v != self.window.rootViewController.view; v = v.superview)
            v.autoresizingMask |= UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth;
        [scene requestGeometryUpdateWithPreferences:[[UIWindowSceneGeometryPreferencesIOS alloc]
            initWithInterfaceOrientations:UIInterfaceOrientationMaskLandscapeRight]
            errorHandler:^(NSError *error) { HARNESS_FAIL(@"timerow rotation: %@", error); }];
        runScript(@[
            @[^BOOL {
                return UIInterfaceOrientationIsLandscape(scene.interfaceOrientation) &&
                    self.window.bounds.size.width > self.window.bounds.size.height && !self.window.rootViewController.transitionCoordinator;
            }, ^{
                [durationUnit viewDidLayoutSubviews];
                [unit layoutIfNeeded];
                if (unit.traitCollection.userInterfaceIdiom == UIUserInterfaceIdiomPhone) {
                    HARNESS_CHECK(!SGAudioQualityShownBadge(unit));
                    NSLog(@"[harness] PASS phone landscape badge hidden");
                    exit(self->_failures ? 1 : 0);
                }
                HARNESS_CHECK(unit.traitCollection.userInterfaceIdiom == UIUserInterfaceIdiomPad);
                badge = SGAudioQualityShownBadge(unit);
                HARNESS_CHECK(badge != nil);
                CGRect frame = [badge convertRect:badge.bounds toView:self.window];
                HARNESS_CHECK(CGRectContainsRect(self.window.bounds, frame));
                HARNESS_CHECK(fabs(badgeBaseline() - uikitBaseline(elapsed, unit)) <= 0.5);
                HARNESS_CHECK(CGRectGetMaxX(elapsed.superview.frame) < CGRectGetMinX(badge.frame) &&
                              CGRectGetMaxX(badge.frame) < CGRectGetMinX(labels.lastObject.superview.frame));
                HARNESS_CHECK(!SGRSeekTapLands(unit, slider, badge.center));
                HARNESS_CHECK([badge accessibilityActivate]);
                NSLog(@"[harness] landscape %@, badge %@", NSStringFromCGRect(self.window.bounds), NSStringFromCGRect(frame));
            }],
            @[^BOOL { return [self.window.rootViewController.presentedViewController isKindOfClass:NSClassFromString(@"SGAudioQualityPanel")]; }, ^{
                [self.window.rootViewController dismissViewControllerAnimated:NO completion:nil];
                SGAudioQualityPlaceBadge(unit);
                HARNESS_CHECK(!SGAudioQualityShownBadge(unit));
                labels.lastObject.superview.center = elapsed.superview.center;
                [durationUnit viewDidLayoutSubviews];
                HARNESS_CHECK(!SGAudioQualityShownBadge(unit));
                NSLog(@"[harness] PASS landscape timerow: details opened; native and crowded rows hidden");
                exit(self->_failures ? 1 : 0);
            }],
        ], 0);
        return;
    }

    // A finger scrubbing: the fill lit whole and the times a step lower; the badge stays where it is.
#include "scrub-capsule.inc"
    CGFloat badgeAt = CGRectGetMinY(badge.frame);
    [slider beginTrackingWithTouch:[UITouch new] withEvent:nil];
    after(0.6, ^{
        [durationUnit viewDidLayoutSubviews];
        CGFloat lower = uikitBaseline(elapsed, unit) - baseline;
        [self expect:lower > 1 && CGRectGetMinY(badge.frame) == badgeAt step:@"times while scrubbing"
              detail:[NSString stringWithFormat:@"times %.1f pt lower, badge moved %.1f pt", lower, CGRectGetMinY(badge.frame) - badgeAt]];
        [slider endTrackingWithTouch:[UITouch new] withEvent:nil];
    });
    after(1.4, ^{
        CGFloat back = middleAlpha([slider minimumTrackImageForState:UIControlStateNormal]);
        [self expect:back > 0.5 && back < 0.7 && fabs(uikitBaseline(elapsed, unit) - baseline) < 0.01 step:@"the scrub over"
              detail:[NSString stringWithFormat:@"fill %.2f, times %.2f pt off their place", back, uikitBaseline(elapsed, unit) - baseline]];
        [badge accessibilityActivate];
    });
    // The details: the glyph over the tier, its rate, a sentence and the footnote.
    after(2.4, ^{
        UIViewController *panel = self.window.rootViewController.presentedViewController;
        NSMutableArray<NSString *> *seen = [NSMutableArray array];
        UIView *stack = panel.viewIfLoaded;
        for (UIView *row in [stack isKindOfClass:UIStackView.class] ? ((UIStackView *)stack).arrangedSubviews : @[]) {
            [seen addObject:[row isKindOfClass:UILabel.class] ? ((UILabel *)row).text : [row isKindOfClass:UIImageView.class] ? @"(glyph)" : NSStringFromClass(row.class)];
        }
        NSArray<NSString *> *want = @[@"(glyph)", @"High Quality", @"About 160 kbps", @"A higher bitrate that brings out more of the detail.", @"Playing now · Spotify High"];
        [self expect:[seen isEqualToArray:want] step:@"the details" detail:[seen componentsJoinedByString:@" | "]];
        [panel dismissViewControllerAnimated:NO completion:nil];

        // A larger text size (9.2.0 at Accessibility Medium: 21pt digits in 25pt labels): Spotify gives the times
        // their new font and size and does not lay the unit out again; the badge follows onto the new baseline.
        for (UILabel *label in labels) {
            UIView *outer = label.superview;
            outer.bounds = CGRectMake(0, 0, outer.bounds.size.width, 25);
            label.frame = outer.bounds;
            NSMutableParagraphStyle *line = [NSMutableParagraphStyle new];
            line.minimumLineHeight = line.maximumLineHeight = 25;
            NSMutableAttributedString *text = [label.attributedText mutableCopy];
            [text addAttributes:@{NSFontAttributeName: [UIFont monospacedDigitSystemFontOfSize:21 weight:UIFontWeightRegular], NSParagraphStyleAttributeName: line}
                          range:NSMakeRange(0, text.length)];
            label.attributedText = text;
            [outer layoutIfNeeded];
        }
        CGFloat larger = uikitBaseline(elapsed, unit);
        // The labels grow about their middles, so the digits' baseline comes down about 2.5pt.
        [self expect:fabs(badgeBaseline() - larger) <= 0.5 && larger - baseline > 1 step:@"the badge on the times' baseline after a change of text size"
              detail:[NSString stringWithFormat:@"badge %.2f, elapsed %.2f (was %.2f)", badgeBaseline(), larger, baseline]];

        // The native look's badge, on a unit of its own: Spotify's word, centered on the times' middle, nothing lowered.
        UIView *native = [[UIView alloc] initWithFrame:CGRectMake(0, 0, unit.bounds.size.width, 41.33)];
        [unit.superview addSubview:native];
        NSArray<UILabel *> *nativeLabels;
        spotifyBar(native, &nativeLabels);
        SGAudioQualityPlaceBadge(native);
        UIView *nativeBadge = SGAudioQualityShownBadge(native);
        UIView *time = nativeLabels.firstObject.superview;
        [self expect:[nativeBadge.accessibilityLabel isEqualToString:@"Audio quality, High"] && CGAffineTransformIsIdentity(time.transform)
                     && fabs(CGRectGetMidY(nativeBadge.frame) - CGRectGetMidY(time.frame)) <= 0.5
                step:@"the native look's badge as it was" detail:[NSString stringWithFormat:@"%@, %@, times at %@", nativeBadge.accessibilityLabel,
                                                                  NSStringFromCGRect(nativeBadge.frame), NSStringFromCGRect(time.frame)]];
        [native removeFromSuperview];
        [NSUserDefaults.standardUserDefaults removeObjectForKey:SGKeyPlayerAudioQuality];
        NSLog(@"[harness] timerow checks: %lu of %lu right -- %@", (unsigned long)(self->_checks - self->_failures), (unsigned long)self->_checks,
              self->_failures ? @"FAIL" : @"PASS");
        exit(self->_failures ? 1 : 0);
    });
}

#pragma mark - the volume bar

// How many pixel rows of each column of `view`, drawn at 2x, are more opaque than `alpha`.
static NSArray<NSNumber *> *columnHeights(UIView *view, CGFloat alpha) {
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat preferredFormat];
    format.scale = 2;
    format.opaque = NO;
    UIImage *image = [[[UIGraphicsImageRenderer alloc] initWithSize:view.bounds.size format:format] imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [view drawViewHierarchyInRect:view.bounds afterScreenUpdates:YES];
    }];
    size_t width = CGImageGetWidth(image.CGImage), height = CGImageGetHeight(image.CGImage);
    uint8_t *pixels = calloc(width * height * 4, 1);
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(pixels, width, height, 8, width * 4, space, kCGImageAlphaPremultipliedLast);
    CGContextDrawImage(context, CGRectMake(0, 0, width, height), image.CGImage);
    NSMutableArray<NSNumber *> *columns = [NSMutableArray arrayWithCapacity:width];
    for (size_t x = 0; x < width; x++) {
        NSUInteger rows = 0;
        for (size_t y = 0; y < height; y++) rows += pixels[(y * width + x) * 4 + 3] > alpha * 255;
        [columns addObject:@(rows)];
    }
    CGContextRelease(context);
    CGColorSpaceRelease(space);
    free(pixels);
    return columns;
}

// The first and last columns with any rows.
static NSRange drawnColumns(NSArray<NSNumber *> *columns) {
    NSUInteger first = NSNotFound, last = 0;
    for (NSUInteger x = 0; x < columns.count; x++) {
        if (!columns[x].unsignedIntegerValue) continue;
        if (first == NSNotFound) first = x;
        last = x;
    }
    return first == NSNotFound ? NSMakeRange(NSNotFound, 0) : NSMakeRange(first, last - first + 1);
}

// The volume row (PlayerVolume.m) beside the progress bar as the redesign draws it (a mock of Spotify's, as timerow's),
// the Music app's two bars alike: the same track, 7pt as Spotify's images, the same colors, the fill's end square at
// the value inside round track ends, also right to left, and a drag thickening it to 12pt (7 x 1.75) with the fill
// lit, as a scrub does the progress bar, and back after; a drag from the track's far end moving the volume by the
// finger's distance, also right to left, a tap there moving nothing, and a drag of the fill's end moving it once.
// The Connect slider is the one the simulator draws (it does
// not draw MPVolumeView's), so MPVolumeView is checked for the same images and empty thumb.
- (void)runVolumeBarChecks {
    UIViewController *durationUnit = _units[2];
    UIView *unit = durationUnit.view;
    NSArray<UILabel *> *labels;
    UISlider *bar = spotifyBar(unit, &labels);
    [durationUnit viewDidLayoutSubviews];
    [unit layoutIfNeeded];
    [bar layoutIfNeeded];

    extern BOOL SGRHarnessConnectVolume;
    SGRHarnessConnectVolume = YES;
    UIView *row = [NSClassFromString(@"SGRVolumeRow") new];
    UIView *host = self.window.rootViewController.view;
    row.frame = CGRectMake(16, CGRectGetMaxY(host.bounds) - 160, host.bounds.size.width - 32, 34);
    [host addSubview:row];
    [row layoutIfNeeded];
    UISlider *remote = [row valueForKey:@"remote"];
    MPVolumeView *volume = [row valueForKey:@"volume"];
    [remote layoutIfNeeded];

    CGFloat barTrack = [bar trackRectForBounds:bar.bounds].size.height, volumeTrack = [remote trackRectForBounds:remote.bounds].size.height;
    [self expect:!remote.hidden && remote.value == 0.5f step:@"the Connect slider shows at half" detail:[NSString stringWithFormat:@"hidden %d, value %.2f", remote.hidden, remote.value]];
    [self expect:barTrack == 7 && volumeTrack == 7 step:@"the track as the progress bar's, 7pt"
          detail:[NSString stringWithFormat:@"volume %.1f pt, progress bar %.1f pt", volumeTrack, barTrack]];
    CGFloat fill = middleAlpha([remote minimumTrackImageForState:UIControlStateNormal]), rest = middleAlpha([remote maximumTrackImageForState:UIControlStateNormal]);
    CGFloat barFill = middleAlpha([bar minimumTrackImageForState:UIControlStateNormal]), barRest = middleAlpha([bar maximumTrackImageForState:UIControlStateNormal]);
    [self expect:fill == barFill && rest == barRest && fill > 0.5 && fill < 0.7 step:@"the colors as the progress bar's"
          detail:[NSString stringWithFormat:@"volume fill %.2f track %.2f, progress bar fill %.2f track %.2f", fill, rest, barFill, barRest]];
    UIImage *volumeFill = [volume minimumVolumeSliderImageForState:UIControlStateNormal], *volumeRest = [volume maximumVolumeSliderImageForState:UIControlStateNormal];
    UIImage *thumb = [volume volumeThumbImageForState:UIControlStateNormal];
    [self expect:volumeFill.size.height == 7 && volumeRest.size.height == 7 && middleAlpha(volumeFill) == barFill && middleAlpha(volumeRest) == barRest
                 && UIEdgeInsetsEqualToEdgeInsets(volumeFill.capInsets, [remote minimumTrackImageForState:UIControlStateNormal].capInsets)
                 && thumb && CGSizeEqualToSize(thumb.size, CGSizeZero)
            step:@"MPVolumeView given the same tracks and an empty thumb"
          detail:[NSString stringWithFormat:@"fill %@ caps %@, track %@, thumb %@", volumeFill ? NSStringFromCGSize(volumeFill.size) : @"none",
                  NSStringFromUIEdgeInsets(volumeFill.capInsets), volumeRest ? NSStringFromCGSize(volumeRest.size) : @"none",
                  thumb ? NSStringFromCGSize(thumb.size) : @"none"]];

    // The fill's end (its last three columns) as tall as its middle, 14 rows at 2x; the track's outermost columns well
    // shorter than its middle. `rtl` puts the fill's end at its left.
    void (^shape)(NSString *, BOOL) = ^(NSString *name, BOOL rtl) {
        NSArray<NSNumber *> *lit = columnHeights(remote, 0.45), *all = columnHeights(remote, 0.04);
        NSRange fillColumns = drawnColumns(lit), trackColumns = drawnColumns(all);
        if (fillColumns.location == NSNotFound || trackColumns.location == NSNotFound) {
            [self expect:NO step:name detail:@"nothing drawn"];
            return;
        }
        NSUInteger middle = lit[NSMaxRange(fillColumns) - fillColumns.length / 2 - 1].unsignedIntegerValue;
        NSUInteger end = rtl ? fillColumns.location : NSMaxRange(fillColumns) - 1;
        NSUInteger shortest = NSUIntegerMax;
        for (NSInteger step = 0; step < 3; step++) shortest = MIN(shortest, lit[rtl ? end + step : end - step].unsignedIntegerValue);
        NSUInteger trackMiddle = all[NSMaxRange(trackColumns) - trackColumns.length / 2 - 1].unsignedIntegerValue;
        NSUInteger left = all[trackColumns.location].unsignedIntegerValue, right = all[NSMaxRange(trackColumns) - 1].unsignedIntegerValue;
        [self expect:middle == 14 && shortest == middle && trackMiddle == 14 && left + 4 <= trackMiddle && right + 4 <= trackMiddle step:name
              detail:[NSString stringWithFormat:@"fill middle %lu rows, its end's shortest of 3 columns %lu (want both 14); track middle %lu, ends %lu and %lu (want 4 or more under it)",
                      (unsigned long)middle, (unsigned long)shortest, (unsigned long)trackMiddle, (unsigned long)left, (unsigned long)right]];
    };
    shape(@"the fill's end square, the track's ends round", NO);
    remote.semanticContentAttribute = UISemanticContentAttributeForceRightToLeft;
    [remote setNeedsLayout];
    [remote layoutIfNeeded];
    shape(@"right to left too", YES);
    remote.semanticContentAttribute = UISemanticContentAttributeUnspecified;
    [remote setNeedsLayout];
    [remote layoutIfNeeded];

    // A finger held on the fill's end (the empty thumb), as a finger scrubs the progress bar.
    [bar beginTrackingWithTouch:[UITouch new] withEvent:nil];
    [bar setNeedsLayout];
    [bar layoutIfNeeded];
    CGFloat barScrub = [bar trackRectForBounds:bar.bounds].size.height;
    [bar endTrackingWithTouch:[UITouch new] withEvent:nil];
    CGRect thumbRect = [remote thumbRectForBounds:remote.bounds trackRect:[remote trackRectForBounds:remote.bounds] value:remote.value];
    SGHarnessHold(self.window, [remote convertPoint:CGPointMake(CGRectGetMidX(thumbRect), CGRectGetMidY(remote.bounds)) toView:self.window], 0.8);
    after(0.5, ^{
        CGFloat grown = [remote trackRectForBounds:remote.bounds].size.height;
        CGFloat litFill = middleAlpha([remote minimumTrackImageForState:UIControlStateNormal]);
        [self expect:remote.tracking && grown == 12 && barScrub == 12 && litFill > 0.95 step:@"a drag thickens it and lights the fill as a scrub does"
              detail:[NSString stringWithFormat:@"tracking %d, volume %.1f pt, progress bar scrubbing %.1f pt (want 12), fill %.2f", remote.tracking, grown, barScrub, litFill]];
    });
    after(1.6, ^{
        CGFloat back = [remote trackRectForBounds:remote.bounds].size.height;
        CGFloat backFill = middleAlpha([remote minimumTrackImageForState:UIControlStateNormal]);
        // The finger lifted where it went down: the value where it was, to the hold's fraction of a point.
        [self expect:back == 7 && backFill == barFill && fabs(remote.value - 0.5) < 0.005 step:@"the drag over"
              detail:[NSString stringWithFormat:@"%.1f pt, fill %.2f, value %.2f", back, backFill, remote.value]];
    });

    // Drags that start away from the fill's end move the volume by the finger's distance over the track, never to the
    // finger; a tap there moves nothing. `edge` is a point 4pt inside the track's left or right end.
    extern double SGRHarnessConnectLevel;
    CGRect track = [remote trackRectForBounds:remote.bounds];
    CGFloat quarter = track.size.width / 4;
    CGPoint (^edge)(BOOL) = ^CGPoint(BOOL right) {
        return [remote convertPoint:CGPointMake(right ? CGRectGetMaxX(track) - 4 : CGRectGetMinX(track) + 4, CGRectGetMidY(remote.bounds)) toView:self.window];
    };
    CGPoint (^by)(CGPoint, CGFloat) = ^CGPoint(CGPoint point, CGFloat dx) { return CGPointMake(point.x + dx, point.y); };
    __block float tapped = 0;
    after(1.8, ^{
        SGHarnessDrag(self.window, edge(YES), by(edge(YES), -quarter), 0.4);
    });
    after(2.0, ^{
        CGFloat grown = [remote trackRectForBounds:remote.bounds].size.height;
        [self expect:grown == 12 && middleAlpha([remote minimumTrackImageForState:UIControlStateNormal]) > 0.95 step:@"a drag from the far end thickens it too"
              detail:[NSString stringWithFormat:@"%.1f pt (want 12)", grown]];
    });
    after(2.6, ^{
        [self expect:fabs(remote.value - 0.25) < 0.02 && fabs(SGRHarnessConnectLevel - remote.value) < 0.001
                     && [remote trackRectForBounds:remote.bounds].size.height == 7
                step:@"a drag from the far end a quarter left moves half to a quarter, the device too"
              detail:[NSString stringWithFormat:@"value %.3f (want 0.25), device %.3f, track %.1f pt", remote.value, SGRHarnessConnectLevel,
                      [remote trackRectForBounds:remote.bounds].size.height]];
        // From a quarter whatever the drag before did, so this one is judged alone.
        remote.value = 0.25;
        SGRHarnessConnectLevel = 0.25;
        remote.semanticContentAttribute = UISemanticContentAttributeForceRightToLeft;
        [remote setNeedsLayout];
        [remote layoutIfNeeded];
        SGHarnessDrag(self.window, edge(NO), by(edge(NO), -quarter), 0.4);
    });
    after(3.4, ^{
        [self expect:fabs(remote.value - 0.5) < 0.02 step:@"right to left, a drag a quarter left from the far end turns it up a quarter"
              detail:[NSString stringWithFormat:@"value %.3f (want 0.5)", remote.value]];
        remote.semanticContentAttribute = UISemanticContentAttributeUnspecified;
        [remote setNeedsLayout];
        [remote layoutIfNeeded];
        tapped = remote.value;
        SGHarnessTap(self.window, edge(YES));
    });
    after(4.0, ^{
        [self expect:remote.value == tapped && SGRHarnessConnectLevel == tapped step:@"a tap at the far end moves nothing"
              detail:[NSString stringWithFormat:@"value %.4f, device %.4f (want %.4f)", remote.value, SGRHarnessConnectLevel, tapped]];
        CGRect thumb = [remote thumbRectForBounds:remote.bounds trackRect:[remote trackRectForBounds:remote.bounds] value:remote.value];
        CGPoint end = [remote convertPoint:CGPointMake(CGRectGetMidX(thumb), CGRectGetMidY(remote.bounds)) toView:self.window];
        SGHarnessDrag(self.window, end, by(end, quarter * 0.8), 0.4);
    });
    after(4.8, ^{
        [self expect:fabs(remote.value - (tapped + 0.2)) < 0.02 step:@"a drag of the fill's end a fifth right moves it once, with the finger"
              detail:[NSString stringWithFormat:@"value %.3f (want %.3f)", remote.value, tapped + 0.2]];
        [self volumeChangesDuringDrags:row remote:remote volume:volume];
    });
}

// Changes from elsewhere during a drag of the row, each timed from its drag's start (after()'s leeway grows with the
// delay, so the steps are not timed from the scenario's start). A drag goes a quarter of the track left in 0.6 s, and
// the change comes 0.3 s in.
- (void)volumeChangesDuringDrags:(UIView *)row remote:(UISlider *)remote volume:(MPVolumeView *)volume {
    extern BOOL SGRHarnessConnectVolume;
    extern double SGRHarnessConnectLevel;
    // MPVolumeView's slider, which the simulator does not make: a stand-in in its place, showing the system volume.
    UISlider *local = [[UISlider alloc] initWithFrame:volume.bounds];
    [local setThumbImage:[UIImage new] forState:UIControlStateNormal];
    [volume addSubview:local];
    CGPoint (^far)(UISlider *) = ^CGPoint(UISlider *slider) {
        CGRect track = [slider trackRectForBounds:slider.bounds];
        return [slider convertPoint:CGPointMake(CGRectGetMaxX(track) - 4, CGRectGetMidY(slider.bounds)) toView:self.window];
    };
    void (^drag)(UISlider *) = ^(UISlider *slider) {
        CGPoint from = far(slider);
        SGHarnessDrag(self.window, from, CGPointMake(from.x - [slider trackRectForBounds:slider.bounds].size.width / 4, from.y), 0.6);
    };
    void (^connect)(BOOL, double) = ^(BOOL on, double level) {
        SGRHarnessConnectVolume = on;
        SGRHarnessConnectLevel = level;
        [NSNotificationCenter.defaultCenter postNotificationName:SGRConnectVolumeChangedNotification object:nil];
        [row layoutIfNeeded];
    };
    __block float before = 0;
    // The Connect device reports late the level the drag began at, one of the drag's own: not a change, the drag ends a
    // quarter down.
    connect(YES, 0.5);
    drag(remote);
    after(0.3, ^{
        before = remote.value;
        connect(YES, 0.5);
    });
    after(1.1, ^{
        [self expect:before < 0.49f && fabs(remote.value - 0.25) < 0.02 step:@"a late report of the drag's own level is not a change"
              detail:[NSString stringWithFormat:@"%.3f when it came, %.3f after the drag (want 0.25)", before, remote.value]];
        [self volumeChangeDuringDrag:remote local:local drag:drag connect:connect];
    });
}

- (void)volumeChangeDuringDrag:(UISlider *)remote local:(UISlider *)local drag:(void (^)(UISlider *))drag connect:(void (^)(BOOL, double))connect {
    extern double SGRHarnessConnectLevel;
    __block float before = 0;
    // The Connect device reports 0.9 (another app turned it up): the drag goes on from 0.9 by the rest of the finger's
    // way, a quarter less what it had gone.
    connect(YES, 0.5);
    drag(remote);
    after(0.3, ^{
        before = remote.value;
        connect(YES, 0.9);
    });
    after(1.1, ^{
        float want = 0.9f - 0.25f - (before - 0.5f);
        [self expect:before < 0.49f && fabs(remote.value - want) < 0.02 && fabs(SGRHarnessConnectLevel - remote.value) < 0.001
                step:@"a Connect level reported during a drag stays, the drag going on from it"
              detail:[NSString stringWithFormat:@"%.3f before the report, %.3f after the drag (want %.3f), device %.3f", before, remote.value, want, SGRHarnessConnectLevel]];
        // The hardware buttons turn this iPhone up to 0.9, which MPVolumeView shows on its slider.
        connect(NO, 0);
        local.value = 0.5;
        drag(local);
        after(0.3, ^{
            before = local.value;
            local.value = 0.9;
        });
        after(1.1, ^{
            float want = 0.9f - 0.25f - (before - 0.5f);
            [self expect:remote.hidden && before < 0.49f && fabs(local.value - want) < 0.02
                    step:@"a hardware button's level during a drag of this iPhone's slider stays, the drag going on from it"
                  detail:[NSString stringWithFormat:@"%.3f before the press, %.3f after the drag (want %.3f)", before, local.value, want]];
            // Quiet here, loud on the Connect device, which shows; halfway through a drag of its slider the device goes.
            local.value = 0.1;
            connect(YES, 0.8);
            drag(remote);
            after(0.3, ^{
                before = remote.value;
                connect(NO, 0);
            });
            after(1.1, ^{
                CGFloat look = [remote trackRectForBounds:remote.bounds].size.height;
                [self expect:remote.hidden && before < 0.79f && local.value == 0.1f && look == 7
                        step:@"the Connect device gone during a drag: this iPhone's volume untouched, the drag over"
                      detail:[NSString stringWithFormat:@"Connect %.3f when it went, this iPhone %.3f (want 0.100), Connect slider's track %.1f pt (want 7)",
                              before, local.value, look]];
                [self finishVolumeBar];
            });
        });
    });
}

- (void)finishVolumeBar {
    NSLog(@"[harness] volumebar checks: %lu of %lu right -- %@", (unsigned long)(_checks - _failures), (unsigned long)_checks, _failures ? @"FAIL" : @"PASS");
    exit(_failures ? 1 : 0);
}

#pragma mark - tap to seek

// The tap around the progress bar (PlayerControls.x): where it lands, what it maps to, and how it seeks. The
// slider is the mock's, given Spotify's identifier, with the two times beside it. A tap is the recognizer's
// action with its starting point set, since the harness cannot make a touch.
- (void)runSeekChecks {
    UIView *otherTilt = [[_tilt.class alloc] initWithFrame:_tilt.frame];
    [otherTilt addSubview:[[UIView alloc] initWithFrame:otherTilt.bounds]];
    [_tilt.superview addSubview:otherTilt];
    checkRecognizerReuse(_tilt, otherTilt, @"SGRCoverHold", ^{ [self->_tilt layoutSubviews]; }, ^{ [otherTilt layoutSubviews]; });
    [otherTilt removeFromSuperview];
    __block NSUInteger right = 0, checks = 0;
    void (^check)(NSString *, BOOL, NSString *) = ^(NSString *step, BOOL ok, NSString *detail) {
        checks++;
        if (ok) right++;
        NSLog(@"[harness] seek %@: %@ -- %@", step, detail, ok ? @"ok" : @"WRONG");
    };
    UIViewController *durationUnit = nil;
    for (UIViewController *candidate in _units) {
        if ([candidate isKindOfClass:_TtC20NowPlaying_ModesImpl19DurationElementUnit.class]) {
            durationUnit = candidate;
            break;
        }
    }
    HARNESS_CHECK(durationUnit != nil);
    UIView *unit = durationUnit.view;
    CGFloat W = unit.bounds.size.width;
    UISlider *slider = [[_TtCO17NowPlaying_ECMKit11ProgressBar6Slider alloc] initWithFrame:CGRectMake(24, 2, W - 48, 14)];
    slider.accessibilityIdentifier = @"SPTNowPlayingSliderV2";
    slider.value = 0.22;
    [unit addSubview:slider];
    UILabel *taken = [[UILabel alloc] initWithFrame:CGRectMake(24, 20, 44, 16)];
    taken.accessibilityIdentifier = @"now-playing-time-take-label";
    UILabel *remaining = [[UILabel alloc] initWithFrame:CGRectMake(W - 24 - 44, 20, 44, 16)];
    remaining.accessibilityIdentifier = @"now-playing-time-remaning-label";
    [unit addSubview:taken];
    [unit addSubview:remaining];
    [durationUnit viewDidLayoutSubviews];
    [SGPlayerState() setValue:@200 forKey:@"duration"];
    UIViewController *otherUnit = [durationUnit.class new];
    UISlider *otherSlider = [[UISlider alloc] initWithFrame:slider.frame];
    otherSlider.accessibilityIdentifier = slider.accessibilityIdentifier;
    [otherUnit.view addSubview:otherSlider];
    checkRecognizerReuse(unit, otherUnit.view, @"SGRSeekTap", ^{ [durationUnit viewDidLayoutSubviews]; },
                        ^{ [otherUnit viewDidLayoutSubviews]; });
    HARNESS_CHECK([onlyRecognizer(otherUnit.view, NSClassFromString(@"SGRSeekTap")) valueForKey:@"slider"] == otherSlider);

    UIGestureRecognizer *tap = nil;
    for (UIGestureRecognizer *recognizer in unit.gestureRecognizers) {
        if ([NSStringFromClass(recognizer.class) isEqualToString:@"SGRSeekTap"]) tap = recognizer;
    }
    CGRect bar = slider.frame;
    CGRect thumb = [unit convertRect:[slider thumbRectForBounds:slider.bounds trackRect:[slider trackRectForBounds:slider.bounds] value:slider.value] fromView:slider];
    check(@"on the duration unit", tap != nil, tap ? @"a recognizer there" : @"none");
    check(@"under the bar", SGRSeekTapLands(unit, slider, CGPointMake(W / 2, CGRectGetMaxY(bar) + 12)), @"12pt below the bar");
    check(@"past the ends", SGRSeekTapLands(unit, slider, CGPointMake(CGRectGetMinX(bar) - 10, 8)) && SGRSeekTapLands(unit, slider, CGPointMake(CGRectGetMaxX(bar) + 10, 8))
          && !SGRSeekTapLands(unit, slider, CGPointMake(CGRectGetMinX(bar) - 20, 8)), @"10pt past either end, not 20");
    check(@"not on the thumb", !SGRSeekTapLands(unit, slider, CGPointMake(CGRectGetMidX(thumb), CGRectGetMidY(thumb))), NSStringFromCGRect(thumb));
    check(@"not on the times", !SGRSeekTapLands(unit, slider, taken.center) && !SGRSeekTapLands(unit, slider, remaining.center), @"either time");
    CGFloat end = SGRSeekShareAt(slider, CGPointMake(slider.bounds.size.width - 1, 7)), start = SGRSeekShareAt(slider, CGPointMake(1, 7));
    CGFloat middle = SGRSeekShareAt(slider, CGPointMake(slider.bounds.size.width / 2, 7));
    check(@"the ends are the song's", end == 1 && start == 0 && fabs(middle - 0.5) < 0.001,
          [NSString stringWithFormat:@"start %.3f, middle %.3f, end %.3f", start, middle, end]);

    // A tap at three quarters of the thumb's travel, played to the slider as a drag.
    NSMutableArray<NSNumber *> *events = [NSMutableArray array];
    __block BOOL answers = NO;
    __block float delivered = NAN;
    for (NSNumber *event in @[@(UIControlEventTouchDown), @(UIControlEventValueChanged), @(UIControlEventTouchUpInside)]) {
        [slider addAction:[UIAction actionWithHandler:^(UIAction *action) {
            [events addObject:event];
            if (event.unsignedIntegerValue == UIControlEventValueChanged) delivered = slider.value;
            if (answers && event.unsignedIntegerValue == UIControlEventTouchUpInside) {
                SGKaraokeSeek((NSInteger)(slider.value * 200000));
                // Arrival is a fresh player report, not merely the karaoke clock moving.
                SPTPlayerState *state = SGPlayerState();
                [state setValue:@(slider.value * 200) forKey:@"positionAsOfTimestamp"];
                [state setValue:NSDate.date forKey:@"timestamp"];
                extern void SGRHarnessReport(SPTPlayerState *state);
                SGRHarnessReport(state);
            }
        }] forControlEvents:event.unsignedIntegerValue];
    }
    CGFloat from = CGRectGetMidX([slider thumbRectForBounds:slider.bounds trackRect:[slider trackRectForBounds:slider.bounds] value:0]);
    CGFloat to = CGRectGetMidX([slider thumbRectForBounds:slider.bounds trackRect:[slider trackRectForBounds:slider.bounds] value:1]);
    void (^tapAt)(CGFloat) = ^(CGFloat share) {
        CGPoint point = [unit convertPoint:CGPointMake(from + share * (to - from), 7) fromView:slider];
        [tap setValue:[NSValue valueWithCGPoint:point] forKey:@"start"];
        ((void (*)(id, SEL))objc_msgSend)(tap, NSSelectorFromString(@"sgr_seek"));
    };
    // A distinct playback value in the same device pixel as the tap.
    [slider setValue:nextafterf(0.75f, 1) animated:NO];
    tapAt(0.75);
    check(@"same-pixel seek delivers the tapped value", delivered == 0.75f,
          [NSString stringWithFormat:@"value-changed received %.9g", delivered]);
    NSArray *drag = @[@(UIControlEventTouchDown), @(UIControlEventValueChanged), @(UIControlEventTouchUpInside)];
    check(@"played as a drag", [events isEqualToArray:drag] && fabs(slider.value - 0.75) < 0.001 && slider.isTracking,
          [NSString stringWithFormat:@"%lu events, value %.3f, tracking %d", (unsigned long)events.count, slider.value, slider.isTracking]);
    // Nothing seeked for it: after a second the tap seeks directly, and the slider lets go.
    after(1.3, ^{
        NSInteger at = SGKaraokePositionMs();
        check(@"a drag that did not seek is seeked", labs(at - 150000) < 1000 && !slider.isTracking,
              [NSString stringWithFormat:@"at %ld ms, tracking %d", (long)at, slider.isTracking]);
        // Spotify seeking for the drag: the slider lets go as the position arrives.
        answers = YES;
        tapAt(0.3);
        NSInteger now = SGKaraokePositionMs();
        check(@"the slider lets go once the position is there", labs(now - 60000) < 1000 && !slider.isTracking,
              [NSString stringWithFormat:@"at %ld ms, tracking %d", (long)now, slider.isTracking]);
    });
    after(2.6, ^{
        NSLog(@"[harness] seek checks: %lu of %lu right -- %@", (unsigned long)right, (unsigned long)checks, right == checks ? @"PASS" : @"FAIL");
        exit(right == checks ? 0 : 1);
    });
}

// The header as the Music app's (PlayerHeader.x): Spotify's down arrow and ⋯ put away (not drawn, not touched, not
// read by VoiceOver) and the ⋯ handed to the menu, which puts its own beside the title; and only the grabber, the
// Music app's 60 x 4 pill 7pt under the safe area's top, a button VoiceOver reads with the arrow's words, whose
// activation, escape and a finger's tap anywhere in its 44pt touch area each close the player by the arrow's action.
// header-noroute: the arrow has no action to close by, so it stays drawn, touched and read, and the grabber is only drawn.
// The grabber stands in the player apart from the row: kept one row height lower by Spotify, the row leaves the pill
// where it is, in the middle of the touch area, and a finger on the pill still closes; and it fades with the row
// while the lyrics are alone and comes back with it.

// The grabber standing for a header row (PlayerHeader.x's SGRPlayerGrabber, in the row's player; inside the row itself
// in sources from before it moved out, which SRC can build).
static UIControl *grabberIn(UIView *header) {
    __block UIControl *found = nil;
    SGForEachView(header.window, ^(UIView *view) {
        if (![NSStringFromClass(view.class) isEqualToString:@"SGRPlayerGrabber"]) return;
        BOOL stands = [view respondsToSelector:NSSelectorFromString(@"row")] ? [view valueForKey:@"row"] == header : view.superview == header;
        if (stands) found = (UIControl *)view;
    });
    return found;
}

- (void)runHeaderChecks {
    BOOL routed = ![scenario() isEqualToString:@"header-noroute"];
    UIViewController *headerUnit = _units.firstObject;
    UIView *header = headerUnit.view;
    UIControl *arrow = nil, *more = nil;
    for (UIView *view in header.subviews) {
        if (![view isKindOfClass:MockEncoreButton.class]) continue;
        if ([view.accessibilityIdentifier isEqualToString:@"Context menu"]) more = (UIControl *)view;
        else arrow = (UIControl *)view;
    }
    arrow.accessibilityLabel = @"Minimize";
    // The ⋯ alone in Spotify's ElementView, as 9.2.0's tree has it.
    UIView *holder = [[_TtGC13Element_UIKit11ElementViewT_P_P__ alloc] initWithFrame:more.frame];
    [header addSubview:holder];
    more.frame = holder.bounds;
    [holder addSubview:more];
    // The row starts at the screen's safe area's top, as on the phone (trees/clean/player/01.txt; the old grabber sat
    // 9pt over it). The mock's player is in a scroll view, which takes the safe area from it; Spotify's is not.
    CGFloat safeTop = self.window.safeAreaInsets.top;
    header.frame = CGRectMake(header.frame.origin.x, safeTop, header.bounds.size.width, header.bounds.size.height);
    // The row in a branch of the player, as 9.2.0 has it (a UIStackView the player places by its top constraint),
    // which is what Spotify moves.
    UIView *branch = [[UIView alloc] initWithFrame:header.frame];
    [_host insertSubview:branch aboveSubview:header];
    header.frame = branch.bounds;
    [branch addSubview:header];
    __block NSUInteger closes = 0;
    if (routed) [arrow addAction:[UIAction actionWithHandler:^(UIAction *action) { closes++; }] forControlEvents:UIControlEventTouchUpInside];
    // The header laid out while the player slides up (9.2.0: its last layout before it is up), and not again.
    CGRect up = _host.frame;
    _host.frame = CGRectOffset(up, 0, 500);
    [_host layoutIfNeeded];
    [headerUnit viewDidLayoutSubviews];
    _host.frame = up;
    // Spotify then moves the row one row height lower and back, with no layout of the header (9.2.0 simulator: by the
    // row's top constraint, which carried the pill to 114pt, where the phone had it); the display pass after each
    // move lays out the rest.
    CGRect row = branch.frame;
    UIView *movedPill = grabberIn(header).subviews.firstObject;
    branch.frame = CGRectOffset(row, 0, row.size.height);
    [self.window layoutIfNeeded];
    CGRect movedDrawn = [movedPill convertRect:movedPill.bounds toView:_host];
    [self expect:movedPill && fabs(CGRectGetMinY(movedDrawn) - (safeTop + 7)) <= 0.5 step:@"the grabber stays when Spotify moves the row"
          detail:[NSString stringWithFormat:@"%@ in the player with the row at %.0f, safe top %.0f", NSStringFromCGRect(movedDrawn), CGRectGetMinY(branch.frame), safeTop]];
    branch.frame = row;
    [self.window layoutIfNeeded];
    // Spotify gives the ⋯ its alpha back as playback starts, with no layout of the header.
    more.alpha = 1;
    for (UIControl *button in @[arrow ?: (id)NSNull.null, more ?: (id)NSNull.null]) {
        if (![button isKindOfClass:UIControl.class]) {
            [self expect:NO step:@"Spotify's header buttons" detail:@"not in the mock"];
            continue;
        }
        CGFloat drawn = 1;
        for (UIView *view = button; view && view != header; view = view.superview) drawn *= view.alpha;
        CGPoint middle = [button convertPoint:CGPointMake(CGRectGetMidX(button.bounds), CGRectGetMidY(button.bounds)) toView:nil];
        UIView *hit = [self.window hitTest:middle withEvent:nil];
        BOOL kept = button == arrow && !routed;
        BOOL right = kept ? drawn == 1 && !button.accessibilityElementsHidden && [hit isDescendantOfView:button]
                          : drawn == 0 && button.accessibilityElementsHidden && !button.isAccessibilityElement && hit != button;
        [self expect:right step:[NSString stringWithFormat:@"%@ %@", button.accessibilityIdentifier, kept ? @"kept, with no action to close by" : @"put away"]
              detail:[NSString stringWithFormat:@"drawn at alpha %.2f, hidden from VoiceOver %d, a touch at its middle reaches %@", drawn,
                      button.accessibilityElementsHidden, NSStringFromClass(hit.class)]];
    }
    extern __weak UIView *SGRHarnessWatchedMore;
    [self expect:more && SGRHarnessWatchedMore == more step:@"the ⋯ handed to the menu" detail:NSStringFromClass(SGRHarnessWatchedMore.class)];
    UIControl *grabber = grabberIn(header);
    UIView *pill = grabber.subviews.firstObject;
    CGRect drawn = [pill convertRect:pill.bounds toView:_host];
    [self expect:grabber && CGSizeEqualToSize(pill.bounds.size, CGSizeMake(60, 4)) && fabs(CGRectGetMinY(drawn) - (safeTop + 7)) <= 0.5
                 && fabs(CGRectGetMidX(drawn) - CGRectGetMidX(_host.bounds)) <= 0.5
            step:@"the Music app's grabber" detail:[NSString stringWithFormat:@"%@ in the player, safe top %.0f", NSStringFromCGRect(drawn), safeTop]];
    BOOL activated = [grabber accessibilityActivate];
    BOOL escaped = [grabber accessibilityPerformEscape];
    if (!routed) {
        [self expect:!grabber.isAccessibilityElement && !grabber.userInteractionEnabled && !activated && !escaped && closes == 0
                step:@"the grabber only drawn" detail:[NSString stringWithFormat:@"read %d, touched %d, activate %d, escape %d",
                     grabber.isAccessibilityElement, grabber.userInteractionEnabled, activated, escaped]];
        NSLog(@"[harness] header checks: %lu of %lu right -- %@", (unsigned long)(_checks - _failures), (unsigned long)_checks, _failures ? @"FAIL" : @"PASS");
        exit(_failures ? 1 : 0);
    }
    [self expect:grabber.isAccessibilityElement && (grabber.accessibilityTraits & UIAccessibilityTraitButton) && [grabber.accessibilityLabel isEqualToString:@"Minimize"]
            step:@"the grabber a button for VoiceOver" detail:[NSString stringWithFormat:@"\"%@\"", grabber.accessibilityLabel]];
    [self expect:activated && escaped && closes == 2 step:@"VoiceOver closes the player by the grabber"
          detail:[NSString stringWithFormat:@"activate %d, escape %d, the arrow's action ran %lu times", activated, escaped, (unsigned long)closes]];
    // The whole touch area takes touches: at least 44 x 44, each corner (1pt in) and its middle reaching the grabber.
    CGRect area = [grabber convertRect:grabber.bounds toView:nil];
    CGRect inner = CGRectInset(area, 1, 1);
    NSMutableArray<NSString *> *missed = [NSMutableArray array];
    for (NSValue *point in @[@(CGPointMake(CGRectGetMinX(inner), CGRectGetMinY(inner))), @(CGPointMake(CGRectGetMaxX(inner), CGRectGetMinY(inner))),
                             @(CGPointMake(CGRectGetMinX(inner), CGRectGetMaxY(inner))), @(CGPointMake(CGRectGetMaxX(inner), CGRectGetMaxY(inner))),
                             @(CGPointMake(CGRectGetMidX(inner), CGRectGetMidY(inner)))]) {
        if ([self.window hitTest:point.CGPointValue withEvent:nil] != grabber) [missed addObject:NSStringFromCGPoint(point.CGPointValue)];
    }
    [self expect:area.size.width >= 44 && area.size.height >= 44 && !missed.count step:@"the grabber's whole 44pt touch area takes touches"
          detail:[NSString stringWithFormat:@"%@ in the window, missed at %@", NSStringFromCGRect(area), missed.count ? [missed componentsJoinedByString:@" "] : @"none"]];
    if ([scenario() isEqualToString:@"header-inset"]) {
        [self runGrabberInsetChecks:grabber unit:headerUnit closes:^NSUInteger { return closes; }];
        return;
    }
    // A finger at the touch area's top edge, which lies over the pill.
    CGPoint finger = CGPointMake(CGRectGetMidX(inner), CGRectGetMinY(inner));
    SGHarnessTap(self.window, finger);
    // Where the pill is drawn in the window, and whether a touch at its middle reaches the grabber.
    CGPoint (^onPill)(void) = ^CGPoint {
        CGRect shown = [pill convertRect:pill.bounds toView:nil];
        return CGPointMake(CGRectGetMidX(shown), CGRectGetMidY(shown));
    };
    BOOL (^pillTakesTouch)(void) = ^BOOL { return [self.window hitTest:onPill() withEvent:nil] == grabber; };
    __block id hideBefore = nil;
    after(0.6, ^{
        [self expect:closes == 3 step:@"a finger on the grabber closes the player"
              detail:[NSString stringWithFormat:@"at %@, the arrow's action ran %lu times", NSStringFromCGPoint(finger), (unsigned long)closes]];
        // Spotify keeps the row one row height lower.
        branch.frame = CGRectOffset(row, 0, row.size.height);
        [self.window layoutIfNeeded];
        CGRect drawnPill = [pill convertRect:pill.bounds toView:nil], touch = [grabber convertRect:grabber.bounds toView:nil];
        CGFloat expectedCenter = MAX(CGRectGetMidY(drawnPill), CGRectGetMinY([self->_host convertRect:self->_host.bounds toView:nil]) + touch.size.height / 2);
        [self expect:CGRectContainsRect(touch, drawnPill) && fabs(CGRectGetMidY(touch) - expectedCenter) <= 0.5 && touch.size.height >= 44 && pillTakesTouch()
                step:@"the pill over the moved row in the middle of its touch area"
              detail:[NSString stringWithFormat:@"pill %@, touch area %@, the row at %.0f", NSStringFromCGRect(drawnPill), NSStringFromCGRect(touch), CGRectGetMinY(branch.frame)]];
        CGPoint there = onPill();
        SGHarnessTap(self.window, there);
        after(0.6, ^{
            [self expect:closes == 4 step:@"a finger on the pill over the moved row closes the player"
                  detail:[NSString stringWithFormat:@"at %@, the arrow's action ran %lu times", NSStringFromCGPoint(there), (unsigned long)closes]];
            branch.frame = row;
            [self.window layoutIfNeeded];
            // The lyrics alone fade everything with the row, and a tap brings it back. The choice goes back as it was
            // before the app exits, so later scenarios on this simulator read their own.
            hideBefore = [NSUserDefaults.standardUserDefaults objectForKey:SGRKeyLyricsAutoHide];
            SGSetInt(SGRKeyLyricsAutoHide, SGRLyricsHideAll);
            SGRPlayerToggleLyrics();
        });
        UIGestureRecognizer *wake = nil;
        for (UIGestureRecognizer *recognizer in self->_host.gestureRecognizers) {
            if ([NSStringFromClass(recognizer.class) isEqualToString:@"SGRPlayerWake"]) wake = recognizer;
        }
        // The pill's alpha as the window draws it.
        CGFloat (^shown)(void) = ^CGFloat {
            CGFloat alpha = 1;
            for (UIView *view = pill; view; view = view.superview) alpha *= view.hidden ? 0 : view.alpha;
            return alpha;
        };
        NSString *(^look)(void) = ^NSString * {
            return [NSString stringWithFormat:@"lyrics %@, row alpha %.2f, the pill drawn at alpha %.2f, a touch on the pill %@", SGRPlayerLyricsOpen() ? @"up" : @"down",
                    header.alpha, shown(), pillTakesTouch() ? @"reaches it" : @"does not"];
        };
        after(2.5, ^{
            [self expect:SGRPlayerLyricsOpen() && header.alpha == 1 && shown() == 1 && pillTakesTouch()
                    step:@"the lyrics up, the grabber with the row" detail:look()];
        });
        // kRest is 4 s from the open.
        after(7.5, ^{
            [self expect:SGRPlayerLyricsOpen() && header.alpha == 0 && shown() == 0 && !pillTakesTouch()
                    step:@"the lyrics alone, the grabber faded with the row" detail:look()];
            // Back in the same turn as the row, inside its animation, with no layout of the header.
            [wake sgr_woke];
            [self expect:header.alpha == 1 && shown() == 1 && pillTakesTouch() step:@"woken, the grabber back with the row" detail:look()];
        });
        after(8.5, ^{ SGRPlayerToggleLyrics(); });
        after(9.5, ^{
            [self expect:!SGRPlayerLyricsOpen() && header.alpha == 1 && shown() == 1 && pillTakesTouch()
                    step:@"the lyrics closed, the grabber with the row" detail:look()];
            if (hideBefore) [NSUserDefaults.standardUserDefaults setObject:hideBefore forKey:SGRKeyLyricsAutoHide];
            else [NSUserDefaults.standardUserDefaults removeObjectForKey:SGRKeyLyricsAutoHide];
            SGPrefsChanged();
            [self runGrabberLeaveChecks:grabber header:header branch:branch closes:^NSUInteger { return closes; }];
        });
    });
}

// A retained row leaving its player (PlayerHeader.x): out of the window and back, then moved within the window, the
// old player routing nothing at once and losing the grabber with no layout of the header.
- (void)runGrabberLeaveChecks:(UIControl *)grabber header:(UIView *)header branch:(UIView *)branch closes:(NSUInteger (^)(void))closes {
    UIView *pill = grabber.subviews.firstObject, *host = _host;
    UIWindow *window = self.window;
    CGFloat safeTop = window.safeAreaInsets.top;
    NSUInteger before = closes();
    CGFloat (^pillTop)(void) = ^CGFloat { return CGRectGetMinY([pill convertRect:pill.bounds toView:host]); };
    NSUInteger slot = [host.subviews indexOfObject:branch];
    [branch removeFromSuperview];
    [self expect:!grabber.superview && ![grabber accessibilityActivate] && closes() == before
            step:@"a retained row out of the window leaves no close button" detail:NSStringFromClass(grabber.superview.class) ?: @"detached"];
    [host insertSubview:branch atIndex:slot];
    after(0.3, ^{
        [self expect:grabber.superview == host && grabberIn(header) == grabber && !grabber.hidden && fabs(pillTop() - (safeTop + 7)) <= 0.5
                step:@"the row back in its player has the grabber again"
              detail:[NSString stringWithFormat:@"in %@, hidden %d, pill at %.1f", NSStringFromClass(grabber.superview.class), grabber.hidden, pillTop()]];
        // Moved straight into another view of the same window: no window change for the row.
        NSUInteger moved = sg_headerLayouts;
        [window addSubview:branch];
        [self expect:![grabber pointInside:CGPointMake(CGRectGetMidX(grabber.bounds), CGRectGetMidY(grabber.bounds)) withEvent:nil]
                     && ![grabber accessibilityActivate] && closes() == before
                step:@"moved within the window, the old player routes nothing" detail:@"before any layout"];
        after(0.3, ^{
            [self expect:!grabber.superview && sg_headerLayouts == moved
                    step:@"moved within the window, the grabber leaves the player with no layout of the header"
                  detail:[NSString stringWithFormat:@"in %@, header laid out %lu times", NSStringFromClass(grabber.superview.class) ?: @"nothing",
                          (unsigned long)(sg_headerLayouts - moved)]];
            NSLog(@"[harness] header checks: %lu of %lu right -- %@", (unsigned long)(self->_checks - self->_failures), (unsigned long)self->_checks,
                  self->_failures ? @"FAIL" : @"PASS");
            exit(self->_failures ? 1 : 0);
        });
    });
}

// header-inset, on an iPad, whose window has a top inset only while its status bar shows: the inset going to none and
// back with no layout of the header reaching the redesign (SGRHarnessStillHeaderUnit).
// With no inset, the pill is 7pt under the player's top and the whole 44pt touch area, the pill in it, is in the
// player, takes touches and closes it; with the inset back, the pill is back under it.
- (void)runGrabberInsetChecks:(UIControl *)grabber unit:(UIViewController *)unit closes:(NSUInteger (^)(void))closes {
    UIView *pill = grabber.subviews.firstObject, *host = _host;
    UIWindow *window = self.window;
    CGFloat safeTop = window.safeAreaInsets.top;
    NSUInteger before = closes(), layouts = sg_headerLayouts;
    CGFloat (^pillTop)(void) = ^CGFloat { return CGRectGetMinY([pill convertRect:pill.bounds toView:host]); };
    Class unitClass = object_setClass(unit, SGRHarnessStillHeaderUnit.class);
    SGRHarnessStatusRoot *root = (SGRHarnessStatusRoot *)window.rootViewController;
    root.bare = YES;
    [root setNeedsStatusBarAppearanceUpdate];
    [window layoutIfNeeded];
    after(0.3, ^{
        CGRect area = [grabber convertRect:grabber.bounds toView:nil], shown = [pill convertRect:pill.bounds toView:nil];
        CGRect inner = CGRectInset(area, 1, 1);
        NSMutableArray<NSString *> *missed = [NSMutableArray array];
        for (NSValue *point in @[@(CGPointMake(CGRectGetMinX(inner), CGRectGetMinY(inner))), @(CGPointMake(CGRectGetMaxX(inner), CGRectGetMinY(inner))),
                                 @(CGPointMake(CGRectGetMinX(inner), CGRectGetMaxY(inner))), @(CGPointMake(CGRectGetMaxX(inner), CGRectGetMaxY(inner)))]) {
            if ([window hitTest:point.CGPointValue withEvent:nil] != grabber) [missed addObject:NSStringFromCGPoint(point.CGPointValue)];
        }
        [self expect:safeTop > 0 && window.safeAreaInsets.top == 0 && fabs(pillTop() - 7) <= 0.5 && area.size.height >= 44 && CGRectContainsRect(area, shown)
                     && !missed.count
                step:@"no top inset: the pill 7pt under the player's top, all 44pt of its touch area reached"
              detail:[NSString stringWithFormat:@"inset %.0f from %.0f, pill at %.1f in the player, touch area %@ and pill %@ in the window, missed at %@, "
                      "the header laid out %lu times with no hook", window.safeAreaInsets.top, safeTop, pillTop(), NSStringFromCGRect(area), NSStringFromCGRect(shown),
                      missed.count ? [missed componentsJoinedByString:@" "] : @"none", (unsigned long)(sg_headerLayouts - layouts)]];
        CGPoint finger = CGPointMake(CGRectGetMidX(inner), CGRectGetMinY(inner));
        SGHarnessTap(window, finger);
        after(0.6, ^{
            [self expect:closes() == before + 1 step:@"no top inset: a finger at the touch area's top closes the player"
                  detail:[NSString stringWithFormat:@"at %@, the arrow's action ran %lu times", NSStringFromCGPoint(finger), (unsigned long)closes()]];
            root.bare = NO;
            [root setNeedsStatusBarAppearanceUpdate];
            [window layoutIfNeeded];
            after(0.3, ^{
                [self expect:window.safeAreaInsets.top == safeTop && fabs(pillTop() - (safeTop + 7)) <= 0.5
                        step:@"the inset back, the pill back under it"
                      detail:[NSString stringWithFormat:@"inset %.0f, pill at %.1f", window.safeAreaInsets.top, pillTop()]];
                object_setClass(unit, unitClass);
                NSLog(@"[harness] header checks: %lu of %lu right -- %@", (unsigned long)(self->_checks - self->_failures), (unsigned long)self->_checks,
                      self->_failures ? @"FAIL" : @"PASS");
                exit(self->_failures ? 1 : 0);
            });
        });
    });
}

#pragma mark - the Player page's look switches and Grain

// The Kit's glass circle in a header button (SGRGlassInside): the 44pt view in it that is not the button's glyph.
static UIView *circleIn(UIView *button) {
    for (UIView *sub in button.subviews) {
        if (![sub isKindOfClass:UIImageView.class] && CGSizeEqualToSize(sub.bounds.size, CGSizeMake(44, 44))) return sub;
    }
    return nil;
}

// The Music app's glyph a stand-in draws over a glyph view of Spotify's, or nil.
static UIView *standInIn(UIView *drawn) {
    for (UIView *sub in drawn.subviews) {
        if ([NSStringFromClass(sub.class) isEqualToString:@"SGRGlyphView"]) return sub;
    }
    return nil;
}


static NSUInteger metalLayersIn(CALayer *layer) {
    NSUInteger count = [layer isKindOfClass:CAMetalLayer.class];
    for (CALayer *sublayer in layer.sublayers) count += metalLayersIn(sublayer);
    return count;
}

static __weak CAMetalLayer *captureLayer;
static char failUpright;
BOOL SGRProbeFailUprightCover(UIImage *cover) { return objc_getAssociatedObject(cover, &failUpright) != nil; }
extern NSUInteger SGRHarnessSpectrumReaders(void);
static int presentedPixel[3];
static NSUInteger capturedWidth;

// Sample the first drawable queued for presentation on its own command buffer. Neither a later
// Smooth frame nor the Light copies can satisfy this check.
static void captureNextFrame(CAMetalLayer *layer) {
    memset(presentedPixel, 0, sizeof(presentedPixel));
    layer.framebufferOnly = NO;
    captureLayer = layer;
}

void SGRProbeFluidFrame(CAMetalLayer *layer, id<CAMetalDrawable> drawable, id<MTLCommandBuffer> command) {
    if (layer != captureLayer) return;
    captureLayer = nil;
    capturedWidth = drawable.texture.width;
    id<MTLBuffer> pixel = [layer.device newBufferWithLength:256 options:MTLResourceStorageModeShared];
    id<MTLBlitCommandEncoder> blit = [command blitCommandEncoder];
    CGRect visible = CGRectIntersection([(SGRFluidGPULayer *)layer visibleRect], layer.bounds);
    [blit copyFromTexture:drawable.texture sourceSlice:0 sourceLevel:0
             sourceOrigin:MTLOriginMake(CGRectGetMidX(visible), CGRectGetMidY(visible), 0)
               sourceSize:MTLSizeMake(1,1,1) toBuffer:pixel destinationOffset:0 destinationBytesPerRow:256 destinationBytesPerImage:256];
    [blit endEncoding];
    [command addCompletedHandler:^(id<MTLCommandBuffer> finished) {
        if (finished.status != MTLCommandBufferStatusCompleted) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            const uint8_t *bgra = pixel.contents;
            for (int i = 0; i < 3; i++) presentedPixel[i] = bgra[2-i];
        });
    }];
}

static CALayer *fluidLayerIn(CALayer *layer) {
    if ([NSStringFromClass(layer.class) isEqualToString:@"SGRFluidLayer"]) return layer;
    for (CALayer *sublayer in layer.sublayers) {
        CALayer *found = fluidLayerIn(sublayer);
        if (found) return found;
    }
    return nil;
}

// The field's top band, above the header row, drawn at one pixel a point (the Smooth renderer's own), as RGBA bytes.
static NSData *fieldBand(UIView *field) {
    CGSize size = CGSizeMake(round(field.bounds.size.width), 56);
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat preferredFormat];
    format.scale = 1;
    format.opaque = YES;
    UIImage *image = [[[UIGraphicsImageRenderer alloc] initWithSize:size format:format] imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [field drawViewHierarchyInRect:field.bounds afterScreenUpdates:YES];
    }];
    size_t width = (size_t)size.width, height = (size_t)size.height;
    NSMutableData *pixels = [NSMutableData dataWithLength:width * height * 4];
    CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGContextRef bitmap = CGBitmapContextCreate(pixels.mutableBytes, width, height, 8, width * 4, space, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(space);
    CGContextDrawImage(bitmap, CGRectMake(0, 0, width, height), image.CGImage);
    CGContextRelease(bitmap);
    return pixels;
}

// The grain in a band: how far each pixel's green is from its right-hand neighbor's, in eight-bit steps, on average. The
// blurred cover barely changes from one pixel to the next, so what is left is the noise.
static double grainIn(NSData *pixels, CGFloat width) {
    const uint8_t *p = pixels.bytes;
    size_t w = (size_t)width, rows = pixels.length / 4 / w;
    double total = 0;
    size_t count = 0;
    for (size_t y = 0; y < rows; y++) {
        for (size_t x = 0; x + 1 < w; x++) {
            total += abs((int)p[(y * w + x) * 4 + 1] - (int)p[(y * w + x + 1) * 4 + 1]);
            count++;
        }
    }
    return count ? total / count : 0;
}

// How far apart two bands are: the mean difference of their color channels, in eight-bit steps.
static double bandDiff(NSData *a, NSData *b) {
    if (a.length != b.length || !a.length) return INFINITY;
    const uint8_t *p = a.bytes, *q = b.bytes;
    double total = 0;
    for (NSUInteger i = 0; i < a.length; i++) {
        if (i % 4 != 3) total += abs((int)p[i] - (int)q[i]);
    }
    return total / (a.length / 4 * 3);
}

// The switch from Smooth to Light with the song paused, five times: the field read about 0.2, 0.5, 1 and 2 s after it (each
// read's own time logged), each compared with the band it settles on, read about 4 s after. Only Kit API the committed
// renderer has too, so the same scenario runs against HEAD's SGRFluid.m and SGRFluidGPU.m.
- (void)runRendererChecks {
    static const NSUInteger kCycles = 5;
    NSArray<NSNumber *> *offsets = @[@0.2, @0.5, @1, @2];
    NSMutableArray<NSArray *> *script = [NSMutableArray array];
    void (^step)(NSTimeInterval, dispatch_block_t) = ^(NSTimeInterval delay, dispatch_block_t block) { [script addObject:@[@(delay), block]]; };
    NSString *(^state)(void) = ^NSString *{
        UIView *field = (UIView *)SGRPlayerField();
        CALayer *fluid = fluidLayerIn(field.layer);
        return [NSString stringWithFormat:@"Smooth %@, %lu Metal layers", [[fluid valueForKey:@"_gpuShown"] boolValue] ? @"showing" : @"not showing",
                (unsigned long)metalLayersIn(field.layer)];
    };
    step(2, ^{ SGRHarnessSetTrack(@"spotify:track:harnessA", imageURI(@"aaaa"), YES); });
    for (NSUInteger cycle = 0; cycle < kCycles; cycle++) {
        __block CFTimeInterval switchedAt = 0;
        NSMutableDictionary<NSNumber *, NSData *> *early = [NSMutableDictionary dictionary];
        NSMutableDictionary<NSNumber *, NSString *> *states = [NSMutableDictionary dictionary];
        step(1, ^{ SGRSetFluidRenderer(SGRFluidRendererSmooth); });
        step(3, ^{
            NSLog(@"[harness] renderer cycle %lu before the switch: %@", (unsigned long)cycle + 1, state());
            switchedAt = CACurrentMediaTime();
            SGRSetFluidRenderer(SGRFluidRendererLight);
        });
        __block double previous = 0;
        for (NSNumber *offset in offsets) {
            step(offset.doubleValue - previous, ^{
                early[offset] = fieldBand((UIView *)SGRPlayerField());
                states[offset] = [NSString stringWithFormat:@"read at +%.2f s, %@", CACurrentMediaTime() - switchedAt, state()];
            });
            previous = offset.doubleValue;
        }
        step(2, ^{
            NSData *settled = fieldBand((UIView *)SGRPlayerField());
            NSMutableArray<NSString *> *seen = [NSMutableArray array];
            for (NSNumber *offset in offsets) [seen addObject:[NSString stringWithFormat:@"%.3f steps off (%@)", bandDiff(early[offset], settled), states[offset]]];
            [self expect:[early[@1] isEqualToData:settled] step:[NSString stringWithFormat:@"cycle %lu, Light a second after the switch as it settles", (unsigned long)cycle + 1]
                  detail:[NSString stringWithFormat:@"settled at +%.2f s; %@", CACurrentMediaTime() - switchedAt, [seen componentsJoinedByString:@"; "]]];
        });
    }
    // The production field maps its visible rect by window height, even for a narrow probe.
    SGRArtworkField *probe = [[SGRArtworkField alloc] initWithFrame:CGRectMake(0, 0, 80, self.window.bounds.size.height)];
    probe.motionHeld = YES;
    __block SGRFluidGPULayer *gpu;
    Method appState = class_getInstanceMethod(UIApplication.class, @selector(applicationState));
    __block IMP originalState, simulatedState;
    __block UIApplicationState lifecycleState;
    __block UIView *card;
    step(0, ^{
        SGRSetFluidRenderer(SGRFluidRendererSmooth);
        probe.fluid = YES;
        [probe layoutIfNeeded];
        gpu = (SGRFluidGPULayer *)fluidLayerIn(probe.layer).sublayers.firstObject;
        [probe setArtwork:solid(UIColor.redColor) identity:@"detached" animated:YES];
    });
    step(1, ^{
        [self expect:[gpu valueForKey:@"toPicture"] != nil && ![gpu valueForKey:@"to"] && ![gpu valueForKey:@"link"]
                step:@"detached artwork prepared without a Metal texture or ticker" detail:state()];
        captureNextFrame(gpu);
        [self.window addSubview:probe];
    });
    step(1, ^{
        [self expect:presentedPixel[0] > presentedPixel[2] step:@"first Smooth frame on attachment is red" detail:state()];
        probe.motionHeld = NO;
        captureNextFrame(gpu);
    });
    step(1, ^{
        [self expect:captureLayer == nil && [gpu valueForKey:@"link"] != nil step:@"playing submits moving frames" detail:state()];
        probe.motionHeld = YES;
    });
    step(1.5, ^{
        [self expect:![gpu valueForKey:@"link"] step:@"motion hold stops its ticker after settlement" detail:state()];
        captureNextFrame(gpu);
    });
    step(0.3, ^{
        [self expect:captureLayer == gpu step:@"settled field does not submit another frame" detail:state()];
        captureNextFrame(gpu);
        [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationWillResignActiveNotification object:nil];
        lifecycleState = UIApplicationStateInactive;
        simulatedState = imp_implementationWithBlock(^UIApplicationState(id app) { return lifecycleState; });
        originalState = method_setImplementation(appState, simulatedState);
        [probe setArtwork:solid(UIColor.blueColor) identity:@"inactive" animated:YES];
    });
    step(1, ^{
        [self expect:!gpu.superlayer.hidden && !gpu.hidden && captureLayer == gpu && ![gpu valueForKey:@"to"] && ![gpu valueForKey:@"link"]
                step:@"inactive field keeps its frame without a submission or ticker" detail:state()];
        lifecycleState = UIApplicationStateBackground;
        [probe setArtwork:solid(UIColor.blueColor) identity:@"background" animated:YES];
        [self expect:captureLayer == gpu && ![gpu valueForKey:@"to"] && ![gpu valueForKey:@"link"]
                step:@"background artwork submits no frame or ticker" detail:state()];
        method_setImplementation(appState, originalState);
        imp_removeBlock(simulatedState);
        [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationDidBecomeActiveNotification object:nil];
    });
    step(1, ^{
        [self expect:presentedPixel[2] > presentedPixel[0] && ![gpu valueForKey:@"link"]
                step:@"reactivation draws the current blue still without starting motion" detail:state()];
        // Interrupt the blue-to-green run-in before its first tick. No track change follows.
        [gpu setCover:solid(UIColor.greenColor).CGImage animated:YES];
        [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationWillResignActiveNotification object:nil];
        captureNextFrame(gpu);
        [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationDidBecomeActiveNotification object:nil];
    });
    step(1, ^{
        [self expect:presentedPixel[1] > MAX(presentedPixel[0], presentedPixel[2])
                step:@"first Smooth frame after interrupted fade is current green"
              detail:[NSString stringWithFormat:@"first drawable RGB %d,%d,%d", presentedPixel[0], presentedPixel[1], presentedPixel[2]]];
        probe.covered = YES;
        [probe setArtwork:solid(UIColor.redColor) identity:@"replacement" animated:YES];
    });
    step(1, ^{
        // Hold Metal submissions through the screenshot so a later drawable cannot satisfy it.
        [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationWillResignActiveNotification object:nil];
        probe.covered = NO;
        NSData *surface = fieldBand(probe);
        const uint8_t *pixel = (const uint8_t *)surface.bytes + 4 * (40 + 28 * 80);
        [self expect:pixel[0] > pixel[1] && pixel[0] > pixel[2]
                step:@"visible uncover is the replacement red before a new drawable"
                detail:[NSString stringWithFormat:@"surface RGB %u,%u,%u", pixel[0], pixel[1], pixel[2]]];
        captureNextFrame(gpu);
        [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationDidBecomeActiveNotification object:nil];
    });
    step(1, ^{
        [self expect:presentedPixel[0] > MAX(presentedPixel[1], presentedPixel[2]) && [[gpu.superlayer valueForKey:@"canvas"] isHidden]
                step:@"presented replacement takes over without stale pixels" detail:state()];
        // Hold the presenter (not the field) so blue finishes preparing while visible
        // but cannot have presented when we cover and uncover it.
        [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationWillResignActiveNotification object:nil];
        [probe setArtwork:solid(UIColor.blueColor) identity:@"replace-before-cover" animated:YES];
    });
    step(1, ^{
        probe.covered = YES;
        probe.covered = NO;
        NSData *surface = fieldBand(probe);
        const uint8_t *pixel = (const uint8_t *)surface.bytes + 4 * (40 + 28 * 80);
        [self expect:pixel[2] > MAX(pixel[0], pixel[1]) step:@"replace then cover: blue fallback before first present"
              detail:[NSString stringWithFormat:@"surface RGB %u,%u,%u", pixel[0], pixel[1], pixel[2]]];
        captureNextFrame(gpu);
        [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationDidBecomeActiveNotification object:nil];
    });
    __block NSUInteger otherReaders;
    step(1, ^{
        [self expect:presentedPixel[2] > MAX(presentedPixel[0], presentedPixel[1]) && [[gpu.superlayer valueForKey:@"canvas"] isHidden]
                step:@"replace then cover: presented blue takes over" detail:state()];
        otherReaders = SGRHarnessSpectrumReaders();
        probe.motionHeld = NO;
    });
    step(1, ^{
        [self expect:SGRHarnessSpectrumReaders() == otherReaders + 1 step:@"moving probe requests spectrum" detail:state()];
        UIImage *red = solid(UIColor.redColor);
        objc_setAssociatedObject(red, &failUpright, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [probe setArtwork:red identity:@"failed-upright" animated:NO];
    });
    step(1, ^{
        NSData *surface = fieldBand(probe);
        const uint8_t *pixel = (const uint8_t *)surface.bytes + 4 * (40 + 28 * 80);
        [self expect:pixel[0] > MAX(pixel[1], pixel[2]) && SGRHarnessSpectrumReaders() == otherReaders
                step:@"failed upright shows the red fallback without spectrum demand" detail:state()];
        captureNextFrame(gpu);
    });
    step(0.3, ^{
        [self expect:captureLayer == gpu step:@"failed upright does not submit the previous cover underneath" detail:state()];
        probe.motionHeld = YES;
        captureNextFrame(gpu);
        [probe setArtwork:solid(UIColor.greenColor) identity:@"recovered-upright" animated:NO];
    });
    step(1, ^{
        [self expect:presentedPixel[1] > MAX(presentedPixel[0], presentedPixel[2]) && [[gpu.superlayer valueForKey:@"canvas"] isHidden]
                step:@"successful cover after failed upright takes over from Light" detail:state()];
        // Resize during this probe's acquisition, then suppress ticks. Only an immediate
        // handoff from the old acquisition can submit a drawable of the new size.
        IMP original = class_getMethodImplementation(CAMetalLayer.class, @selector(nextDrawable));
        __block BOOL resize = YES;
        SGRFluidGPULayer *target = gpu;
        IMP intercept = imp_implementationWithBlock(^id(CAMetalLayer *layer) {
            if (layer == target && resize) {
                resize = NO;
                dispatch_block_t duringAcquire = ^{
                    CGFloat before = gpu.drawableSize.width;
                    gpu.bounds = CGRectMake(0, 0, 112, 256);
                    [[gpu valueForKey:@"link"] setPaused:YES];
                    [self expect:gpu.drawableSize.width == before step:@"resize deferred during acquisition" detail:state()];
                };
                HARNESS_CHECK(!NSThread.isMainThread);
                dispatch_sync(dispatch_get_main_queue(), duringAcquire);
            }
            return ((id (*)(id, SEL))original)(layer, @selector(nextDrawable));
        });
        class_addMethod(SGRFluidGPULayer.class, @selector(nextDrawable), intercept,
                        method_getTypeEncoding(class_getInstanceMethod(CAMetalLayer.class, @selector(nextDrawable))));
        captureNextFrame(gpu);
        gpu.warp += .01;
    });
    step(1, ^{
        [self expect:capturedWidth == 112 && captureLayer == nil
                step:@"resized frame submitted without another tick" detail:state()];
        [probe removeFromSuperview];
        SGSetInt(SGRKeyPlayerArtworkBackground, SGRPlayerBackgroundFluid);
        SGRSetPlayerBackground(SGRPlayerBackgroundPhoto);
        card = [[NSClassFromString(@"SGRPlayerPreview") alloc] initWithFrame:CGRectMake(0, 0, 300, 300)];
        [self.window addSubview:card];
        [card setValue:@YES forKey:@"active"];
        SGRArtworkField *field = [card valueForKey:@"field"];
        gpu = (SGRFluidGPULayer *)fluidLayerIn(field.layer).sublayers.firstObject;
        captureNextFrame(gpu);
        [field setArtwork:solid(UIColor.redColor) identity:@"covered" animated:YES];
    });
    step(1, ^{
        [self expect:gpu && captureLayer == gpu && [card valueForKey:@"backdrop"]
                step:@"photo-covered settings preview submits no Smooth frame" detail:state()];
        captureLayer = nil;
        [card setValue:@NO forKey:@"active"];
        [card removeFromSuperview];
    });
    step(0.5, ^{
        NSLog(@"[harness] renderer checks: %lu of %lu right -- %@", (unsigned long)(self->_checks - self->_failures), (unsigned long)self->_checks,
              self->_failures ? @"FAIL" : @"PASS");
        if (self->_failures) HARNESS_FAIL(@"%lu renderer checks failed", (unsigned long)self->_failures);
        exit(0);
    });
    runScript(script, 0);
}

// Header glass and Music app icons switched off and on again on the Player page while the player is open, in the ordinary
// player and the AI DJ's; then Grain at 0, 100 and 200% on the Smooth renderer, and on the Light one, which has none.
- (void)runOptionsChecks {
    __block UINavigationController *nav;
    SGModPage *(^page)(void) = ^{ return (SGModPage *)nav.topViewController; };
    UIView *header = _units.firstObject.view, *djHeader = _djHeader;
    NSMutableArray<UIView *> *buttons = [NSMutableArray array];
    for (UIView *row in @[header, djHeader]) {
        for (UIView *view in row.subviews) if ([view isKindOfClass:MockEncoreButton.class]) [buttons addObject:view];
    }
    UIImageView *connect = _connectImage, *djConnect = _djConnectImage;
    SPTEncoreIconView *queue = _queueIcon;
    UIImage *spotifyConnect = _spotifyConnect, *djSpotifyConnect = _djSpotifyConnect;

    void (^open)(void) = ^{
        nav = [[UINavigationController alloc] initWithRootViewController:SGRPlayerSettingsPage(@[])];
        // Over the player, which stays in the window and lays out as it would under Mod Settings.
        nav.modalPresentationStyle = UIModalPresentationOverFullScreen;
        [self.window.rootViewController presentViewController:nav animated:NO completion:nil];
    };
    void (^close)(void) = ^{ [self.window.rootViewController dismissViewControllerAnimated:NO completion:nil]; };
    SGModRow *(^rowTitled)(NSString *) = ^SGModRow *(NSString *title) {
        for (SGModSection *section in page().sections) for (SGModRow *row in section.rows) if ([row.title isEqualToString:title]) return row;
        return nil;
    };
    NSIndexPath *(^pathOf)(SGModRow *) = ^NSIndexPath *(SGModRow *row) {
        NSArray<NSArray *> *shown = [page() valueForKey:@"_shown"];
        for (NSUInteger s = 0; s < shown.count; s++) {
            NSUInteger r = [shown[s] indexOfObject:row];
            if (r != NSNotFound) return [NSIndexPath indexPathForRow:(NSInteger)r inSection:(NSInteger)s];
        }
        return nil;
    };
    // A row's switch flipped as a finger flips it: the page's own handler stores it and tells the player.
    BOOL (^flip)(NSString *, BOOL) = ^BOOL(NSString *title, BOOL on) {
        NSIndexPath *path = pathOf(rowTitled(title));
        if (!path) return NO;
        UITableView *table = page().tableView;
        [table scrollToRowAtIndexPath:path atScrollPosition:UITableViewScrollPositionMiddle animated:NO];
        [table layoutIfNeeded];
        UIView *accessory = [table cellForRowAtIndexPath:path].accessoryView;
        UIControl *toggle = [accessory respondsToSelector:@selector(isOn)] ? (UIControl *)accessory : nil;
        for (UIView *sub in accessory.subviews) if (!toggle && [sub respondsToSelector:@selector(isOn)]) toggle = (UIControl *)sub;
        if (!toggle) return NO;
        [(UISwitch *)toggle setOn:on];
        [toggle sendActionsForControlEvents:UIControlEventValueChanged];
        return YES;
    };
    // The AI DJ's two buttons on glass while the switch is on and as Spotify's without; the ordinary player's put away
    // either way, its header the grabber's alone.
    void (^expectGlass)(NSString *, BOOL) = ^(NSString *step, BOOL on) {
        NSMutableArray<NSString *> *seen = [NSMutableArray array];
        BOOL ok = buttons.count == 4;
        for (UIView *button in buttons) {
            UIView *circle = circleIn(button), *row = button.superview;
            BOOL dj = row == djHeader;
            CGPoint middle = CGPointMake(CGRectGetMidX(button.frame), CGRectGetMidY(button.frame));
            BOOL hits = [row hitTest:middle withEvent:nil] == button;
            BOOL shape = on && dj ? [circle isKindOfClass:UIVisualEffectView.class] && button.subviews.firstObject == circle : circle == nil;
            BOOL kept = grabberIn(row) != nil && button.accessibilityIdentifier.length
                && (dj ? hits && !button.accessibilityElementsHidden && button.userInteractionEnabled : !hits && button.alpha == 0 && button.accessibilityElementsHidden);
            ok = ok && shape && kept;
            [seen addObject:[NSString stringWithFormat:@"%@ %@: circle %@, touch %@, grabber %@", row == djHeader ? @"DJ" : @"player",
                             button.accessibilityIdentifier, circle ? NSStringFromClass(circle.class) : @"none", hits ? @"lands" : @"MISSES",
                             grabberIn(row) ? @"up" : @"gone"]];
        }
        [self expect:ok step:step detail:[seen componentsJoinedByString:@"; "]];
    };
    void (^expectIcons)(NSString *, BOOL, UIImage *) = ^(NSString *step, BOOL on, UIImage *spotify) {
        BOOL ordinary = on ? standInIn(connect) && connect.image != spotify : !standInIn(connect) && connect.image == spotify;
        BOOL dj = on ? standInIn(djConnect) && djConnect.image != djSpotifyConnect : !standInIn(djConnect) && djConnect.image == djSpotifyConnect;
        BOOL queued = on ? standInIn(queue) && [queue.foregroundColor isEqual:UIColor.clearColor]
                         : !standInIn(queue) && [queue.foregroundColor isEqual:UIColor.whiteColor] && [queue.activeForegroundColor isEqual:UIColor.greenColor];
        [self expect:ordinary && dj && queued step:step
              detail:[NSString stringWithFormat:@"Connect: stand-in %@, Spotify's glyph %@; DJ Connect: stand-in %@, Spotify's glyph %@; queue: stand-in %@, colors %@ / %@",
                      standInIn(connect) ? @"in" : @"out", connect.image == spotify ? @"shown" : @"cleared", standInIn(djConnect) ? @"in" : @"out",
                      djConnect.image == djSpotifyConnect ? @"shown" : @"cleared", standInIn(queue) ? @"in" : @"out", queue.foregroundColor, queue.activeForegroundColor]];
    };

    // Lyrics in both footers and the AI DJ's Queue: the Music app's symbol while the switch is on, Spotify's Encore glyph
    // (the mock's own symbol) in the symbol's color while it is off; the DJ button a waveform over its masked disc, or the disc.
    UIView *footerHost = _units[5].view, *djFooter = _djFooter, *djButton = _djButton, *djConnectView = _djConnect, *djShare = _djShare;
    SGRGlyphButton *(^titled)(UIView *, NSString *) = ^SGRGlyphButton *(UIView *host, NSString *title) {
        for (UIView *sub in host.subviews) if ([sub isKindOfClass:SGRGlyphButton.class] && [sub.accessibilityLabel isEqualToString:title]) return (SGRGlyphButton *)sub;
        return nil;
    };
    SPTEncoreIconView *(^encoreIn)(UIView *) = ^SPTEncoreIconView *(UIView *button) {
        for (UIView *sub in button.subviews) if ([sub isKindOfClass:SPTEncoreIconView.class]) return (SPTEncoreIconView *)sub;
        return nil;
    };
    SGRGlyphView *(^waveIn)(UIView *) = ^SGRGlyphView *(UIView *host) {
        for (UIView *sub in host.subviews) if ([sub isKindOfClass:SGRGlyphView.class] && [((SGRGlyphView *)sub).symbol isEqualToString:@"waveform"]) return (SGRGlyphView *)sub;
        return nil;
    };
    void (^expectGlyphs)(NSString *, BOOL) = ^(NSString *step, BOOL on) {
        NSMutableArray<NSString *> *seen = [NSMutableArray array];
        BOOL ok = YES;
        for (NSArray *drawn in @[@[footerHost, @"Lyrics", @"microphone"], @[djFooter, @"Lyrics", @"microphone"], @[djFooter, @"Queue", @"queue"]]) {
            SGRGlyphButton *button = titled(drawn[0], drawn[1]);
            SPTEncoreIconView *encore = encoreIn(button);
            BOOL right = button && (on ? !button.glyph.hidden && !encore
                                       : button.glyph.hidden && [[encore.icon name] isEqualToString:drawn[2]] && [encore.foregroundColor isEqual:button.glyph.tintColor]
                                         && !encore.userInteractionEnabled && encore.accessibilityElementsHidden);
            ok = ok && right;
            [seen addObject:[NSString stringWithFormat:@"%@ %@: %@", drawn[0] == djFooter ? @"DJ" : @"player", drawn[1],
                             !button ? @"NOT FOUND" : encore ? [NSString stringWithFormat:@"Encore %@", [encore.icon name]] : button.glyph.hidden ? @"nothing" : button.glyph.symbol]];
        }
        UIView *djHolder = djButton.superview;
        SGRGlyphView *wave = waveIn(djFooter);
        CGPoint drawnDJ = [djFooter convertPoint:CGPointMake(CGRectGetMidX(djButton.bounds), CGRectGetMidY(djButton.bounds)) fromView:djButton];
        BOOL disc = on ? wave && djHolder.layer.mask && !wave.userInteractionEnabled && hypot(wave.center.x - drawnDJ.x, wave.center.y - drawnDJ.y) < 1
                       : !wave && !djHolder.layer.mask;
        [seen addObject:[NSString stringWithFormat:@"DJ button: %@, %@", wave ? [NSString stringWithFormat:@"waveform %.0f pt from its middle",
                         hypot(wave.center.x - drawnDJ.x, wave.center.y - drawnDJ.y)] : @"no waveform", djHolder.layer.mask ? @"disc masked" : @"disc drawn"]];
        [self expect:ok && disc step:step detail:[seen componentsJoinedByString:@"; "]];
    };
    // Where a touch at the middle of what each of the AI DJ's four draws lands, with Spotify having given the share button and
    // its holder their alpha and touches back: Lyrics and Queue on the redesign's buttons, Connect and the DJ button on
    // Spotify's, and nothing of the share button drawn. VoiceOver still finds all four.
    void (^expectDJTouches)(NSString *) = ^(NSString *step) {
        UIView *shareHolder = djShare.superview;
        for (UIView *view in @[djShare, shareHolder]) {
            view.alpha = 1;
            view.userInteractionEnabled = YES;
        }
        UIWindow *window = djFooter.window;
        UIView *(^hitAt)(UIView *) = ^UIView *(UIView *view) {
            return [window hitTest:[window convertPoint:CGPointMake(CGRectGetMidX(view.bounds), CGRectGetMidY(view.bounds)) fromView:view] withEvent:nil];
        };
        SGRGlyphButton *lyrics = titled(djFooter, @"Lyrics"), *queueButton = titled(djFooter, @"Queue");
        UIView *onLyrics = hitAt(lyrics), *onQueue = hitAt(queueButton), *onConnect = hitAt(djConnect), *onDJ = hitAt(djButton);
        BOOL lands = lyrics && queueButton && [onLyrics isDescendantOfView:lyrics] && [onQueue isDescendantOfView:queueButton]
                  && [onConnect isDescendantOfView:djConnectView] && [onDJ isDescendantOfView:djButton];
        CALayer *mask = shareHolder.layer.mask;
        BOOL away = mask && !mask.contents && CGRectIsEmpty(mask.bounds) && djShare.layer.mask;
        BOOL heard = lyrics.isAccessibilityElement && queueButton.isAccessibilityElement && djButton.isAccessibilityElement && !djButton.accessibilityElementsHidden
                  && [lyrics.accessibilityLabel isEqualToString:@"Lyrics"] && [queueButton.accessibilityLabel isEqualToString:@"Queue"];
        NSString *(^name)(UIView *) = ^NSString *(UIView *view) { return view.accessibilityIdentifier ?: view.accessibilityLabel ?: NSStringFromClass(view.class); };
        [self expect:lands && away && heard step:step
              detail:[NSString stringWithFormat:@"Lyrics on %@, Queue on %@, Connect on %@, the DJ button on %@; share %@; VoiceOver %@", name(onLyrics),
                      name(onQueue), name(onConnect), name(onDJ), away ? @"masked away" : @"DRAWN", heard ? @"finds all four" : @"MISSES ONE"]];
    };
    // A finger on the AI DJ's Queue, then on its Lyrics twice: the queue is asked for, and the lyrics open and close.
    __block BOOL lyricsBefore = NO;
    // Whether the touch lands on the button: with the lyrics up nothing of theirs may be over it.
    BOOL (^tapDJ)(NSString *) = ^BOOL(NSString *title) {
        UIView *button = titled(djFooter, title);
        CGPoint point = [djFooter.window convertPoint:CGPointMake(CGRectGetMidX(button.bounds), CGRectGetMidY(button.bounds)) fromView:button];
        BOOL lands = button && [[djFooter.window hitTest:point withEvent:nil] isDescendantOfView:button];
        SGHarnessTap(djFooter.window, point);
        return lands;
    };
    __block BOOL lyricsReached = NO;

    // One step after another, each its delay after the one before it ran: every state a screenshot is asked for holds
    // two seconds or more, and a check reads a state the step before it set up once UIKit has laid it out.
    __block UIImage *device = nil;
    NSMutableArray<NSArray *> *script = [NSMutableArray array];
    void (^step)(NSTimeInterval, dispatch_block_t) = ^(NSTimeInterval delay, dispatch_block_t block) { [script addObject:@[@(delay), block]]; };
    step(2, ^{
        expectGlass(@"glass, as it stands", YES);
        expectIcons(@"Music app icons, as they stand", YES, spotifyConnect);
        expectGlyphs(@"the Music app's Lyrics, Queue and waveform, as they stand", YES);
        expectDJTouches(@"the AI DJ's four take their touches, the Music app's glyphs");
        NSLog(@"[harness] options: screenshot on now");
    });
    step(2.5, ^{
        SGRHarnessLastOpened = nil;
        tapDJ(@"Queue");
    });
    step(0.5, ^{
        [self expect:[SGRHarnessLastOpened.absoluteString isEqualToString:@"spotify:now-playing:queue"] step:@"the AI DJ's Queue tapped, the Music app's glyph"
              detail:SGRHarnessLastOpened.absoluteString ?: @"nothing opened"];
        open();
    });
    step(0.5, ^{
        BOOL flipped = flip(@"Header glass", NO) && flip(@"Music app icons", NO);
        [self expect:flipped && !SGEnabled(SGRKeyPlayerHeaderGlass) && !SGEnabled(SGRKeyPlayerMusicIcons) step:@"both switched off on the page"
              detail:[NSString stringWithFormat:@"switches %@", flipped ? @"flipped" : @"NOT FOUND"]];
    });
    step(0.5, ^{
        expectGlass(@"glass off, the page still up", NO);
        expectIcons(@"Music app icons off, the page still up", NO, spotifyConnect);
        expectGlyphs(@"Spotify's Lyrics and Queue glyphs and the DJ's disc, the page still up", NO);
        // Spotify draws another device's glyph while they are off: it stays Spotify's.
        device = [[UIImage systemImageNamed:@"hifispeaker.fill"] imageWithTintColor:UIColor.greenColor renderingMode:UIImageRenderingModeAlwaysOriginal];
        connect.image = device;
        close();
    });
    step(1, ^{
        expectIcons(@"a new device's glyph while off", NO, device);
        expectDJTouches(@"the AI DJ's four take their touches, Spotify's glyphs");
        NSLog(@"[harness] options: screenshot off now");
    });
    step(2.5, ^{
        SGRHarnessLastOpened = nil;
        tapDJ(@"Queue");
    });
    step(0.5, ^{
        [self expect:[SGRHarnessLastOpened.absoluteString isEqualToString:@"spotify:now-playing:queue"] step:@"the AI DJ's Queue tapped, Spotify's glyph"
              detail:SGRHarnessLastOpened.absoluteString ?: @"nothing opened"];
        lyricsBefore = SGRPlayerLyricsOpen();
        lyricsReached = tapDJ(@"Lyrics");
    });
    // The second tap comes while the lyrics are still moving in: the Lyrics button turns them back at once.
    step(0.5, ^{
        BOOL turned = SGRPlayerLyricsOpen() != lyricsBefore;
        BOOL reached = lyricsReached;
        lyricsReached = tapDJ(@"Lyrics");
        [self expect:reached && turned && titled(djFooter, @"Lyrics").enabled step:@"the AI DJ's Lyrics tapped, Spotify's glyph"
              detail:!reached ? @"the touch missed the button" : turned ? (lyricsBefore ? @"the lyrics closed" : @"the lyrics opened") : @"the lyrics did not turn"];
    });
    step(0.5, ^{
        [self expect:lyricsReached && SGRPlayerLyricsOpen() == lyricsBefore && encoreIn(titled(djFooter, @"Lyrics")) step:@"tapped again, back as they were"
              detail:!lyricsReached ? @"the touch missed the button, under the lyrics" : SGRPlayerLyricsOpen() ? @"open" : @"closed"];
        open();
    });
    step(0.5, ^{ flip(@"Header glass", YES); flip(@"Music app icons", YES); });
    step(0.5, ^{
        expectGlass(@"glass on again", YES);
        expectIcons(@"Music app icons on again", YES, device);
        expectGlyphs(@"the Music app's Lyrics, Queue and waveform on again", YES);
        NSLog(@"[harness] options: screenshot controls rows now");
    });
    step(2.5, ^{
        SGModRow *grain = rowTitled(@"Grain"), *style = rowTitled(@"Style");
        BOOL smooth = pathOf(grain) != nil;
        style.chosen(SGRFluidRendererLight);
        BOOL light = pathOf(grain) != nil;
        style.chosen(SGRFluidRendererSmooth);
        BOOL back = pathOf(grain) != nil;
        [self expect:grain && smooth && !light && back step:@"Grain shown only while Smooth draws"
              detail:[NSString stringWithFormat:@"Smooth %@, Light %@, Smooth again %@", smooth ? @"shown" : @"hidden", light ? @"shown" : @"hidden", back ? @"shown" : @"hidden"]];
    });
    step(1, ^{
        if (pathOf(rowTitled(@"Grain"))) [page().tableView scrollToRowAtIndexPath:pathOf(rowTitled(@"Grain")) atScrollPosition:UITableViewScrollPositionMiddle animated:NO];
        NSLog(@"[harness] options: screenshot grain row now");
    });
    step(2.5, ^{
        close();
        // Held still, so every band read is one frame.
        SGRHarnessSetTrack(@"spotify:track:harnessA", imageURI(@"aaaa"), YES);
    });

    // What Spotify sets while the Music app's glyphs show is what comes back when they go, nil and all: Connect cleared, and
    // handed an image with no bitmap; the queue's two colors reset to nil; and a value Spotify set while they were out is
    // not overwritten by one recorded the time before.
    void (^icons)(BOOL) = ^(BOOL on) {
        SGSetEnabled(SGRKeyPlayerMusicIcons, on);
        SGRPlayerLookChanged();
    };
    UIImage *unbacked = [UIImage imageWithCIImage:[[CIImage imageWithColor:[CIColor colorWithRed:0 green:1 blue:0]] imageByCroppingToRect:CGRectMake(0, 0, 19, 19)]];
    NSString *(^iconState)(void) = ^NSString *{
        return [NSString stringWithFormat:@"Connect: stand-in %@, image %@; queue: stand-in %@, colors %@ / %@", standInIn(connect) ? @"in" : @"out",
                connect.image == unbacked ? @"the one with no bitmap" : connect.image ? (connect.image.CGImage ? @"a bitmap" : @"another") : @"nil",
                standInIn(queue) ? @"in" : @"out", queue.foregroundColor ?: @"nil", queue.activeForegroundColor ?: @"nil"];
    };
    step(0.5, ^{
        connect.image = nil;
        queue.foregroundColor = nil;
        queue.activeForegroundColor = nil;
        icons(NO);
    });
    step(0.5, ^{
        [self expect:!standInIn(connect) && !connect.image && !standInIn(queue) && !queue.foregroundColor && !queue.activeForegroundColor
                step:@"Connect cleared and the queue's colors reset while the glyphs showed, given back as nil" detail:iconState()];
        queue.foregroundColor = UIColor.whiteColor;
        icons(YES);
    });
    step(0.5, ^{
        [self expect:standInIn(connect) && standInIn(queue) && [queue.foregroundColor isEqual:UIColor.clearColor] step:@"the glyphs back over a cleared Connect"
              detail:iconState()];
        connect.image = unbacked;
        icons(NO);
    });
    step(0.5, ^{
        [self expect:!standInIn(connect) && connect.image == unbacked && [queue.foregroundColor isEqual:UIColor.whiteColor] && !queue.activeForegroundColor
                step:@"an image with no bitmap given back as Spotify set it" detail:iconState()];
        connect.image = nil;
        queue.foregroundColor = nil;
        icons(YES);
    });
    step(0.5, ^{ icons(NO); });
    step(0.5, ^{
        [self expect:!connect.image && !queue.foregroundColor && !queue.activeForegroundColor
                step:@"what Spotify set while they were out, not the record before" detail:iconState()];
        icons(YES);
    });

    // Each Grain set as the slider sets it, then the field read a second later. Light at 100 is the read a second after the
    // switch from Smooth, compared with the two read after it (the switch on its own: the `renderer` scenario).
    NSMutableDictionary<NSString *, NSNumber *> *grains = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSData *> *bands = [NSMutableDictionary dictionary];
    __block CFTimeInterval setAt = 0;
    NSArray<NSArray *> *grainSteps = @[@[@"Smooth", @0], @[@"Smooth", @100], @[@"Smooth", @200], @[@"Light", @100], @[@"Light", @0], @[@"Light", @200]];
    [grainSteps enumerateObjectsUsingBlock:^(NSArray *values, NSUInteger i, BOOL *stop) {
        NSString *renderer = values[0], *name = [NSString stringWithFormat:@"%@ %@", values[0], values[1]];
        step(i ? 2 : 1, ^{
            setAt = CACurrentMediaTime();
            SGRSetFluidRenderer([renderer isEqualToString:@"Smooth"] ? SGRFluidRendererSmooth : SGRFluidRendererLight);
            SGRSetFluidValue(SGRFluidGrain, [values[1] integerValue]);
        });
        step(1, ^{
            UIView *field = (UIView *)SGRPlayerField();
            CALayer *fluid = fluidLayerIn(field.layer);
            BOOL gpu = [[fluid valueForKey:@"_gpuShown"] boolValue];
            NSData *band = fieldBand(field);
            bands[name] = band;
            grains[name] = @(grainIn(band, round(field.bounds.size.width)));
            NSLog(@"[harness] options: %@ grain %.2f s after it was set, the Smooth renderer %@ (%lu Metal layers in the field) -- %.3f steps; screenshot %@ now",
                  name, CACurrentMediaTime() - setAt, gpu ? @"showing" : @"not showing", (unsigned long)metalLayersIn(field.layer), grains[name].doubleValue, name);
            if ([renderer isEqualToString:@"Smooth"] != gpu) {
                [self expect:NO step:[name stringByAppendingString:@" drawn by its renderer"] detail:gpu ? @"Smooth showing" : @"Smooth not showing"];
            }
        });
    }];
    step(1, ^{
        double s0 = grains[@"Smooth 0"].doubleValue, s100 = grains[@"Smooth 100"].doubleValue, s200 = grains[@"Smooth 200"].doubleValue;
        [self expect:[bands[@"Smooth 0"] isEqualToData:bands[@"Smooth 100"]] && s100 + 0.5 < s200
                step:@"Smooth: no grain through the standard, visible grain at 200"
              detail:[NSString stringWithFormat:@"%.3f, %.3f, %.3f steps", s0, s100, s200]];
        [self expect:[bands[@"Light 0"] isEqualToData:bands[@"Light 200"]] step:@"Light: the same at 0 and 200"
              detail:[NSString stringWithFormat:@"%.3f and %.3f steps", grains[@"Light 0"].doubleValue, grains[@"Light 200"].doubleValue]];
        [self expect:[bands[@"Light 100"] isEqualToData:bands[@"Light 0"]] step:@"Light a second after the switch from Smooth, as it settles"
              detail:[NSString stringWithFormat:@"%.3f steps from the settled band", bandDiff(bands[@"Light 100"], bands[@"Light 0"])]];
        NSLog(@"[harness] options checks: %lu of %lu right -- %@", (unsigned long)(self->_checks - self->_failures), (unsigned long)self->_checks,
              self->_failures ? @"FAIL" : @"PASS");
        if (self->_failures) HARNESS_FAIL(@"%lu options checks failed", (unsigned long)self->_failures);
        exit(0);
    });
    runScript(script, 0);
}

// Issue #54: the footer row moved down past the bottom stack's bounds must still take its touches, at the bottom edge of
// each glyph Spotify draws as well as the middle.
- (void)expectFooterTouches:(NSString *)when {
    CGFloat bottom = 0;
    // The Music app's queue and AirPlay glyphs the footer draws over Spotify's (Music app icons, on by default).
    for (NSString *symbol in @[@"list.bullet", @"airplayaudio"]) {
        UIView *found = nil;
        NSMutableArray *queue = [NSMutableArray arrayWithObject:self.window];
        while (queue.count && !found) {
            UIView *v = queue.firstObject;
            [queue removeObjectAtIndex:0];
            if ([v isKindOfClass:SGRGlyphView.class] && [((SGRGlyphView *)v).symbol isEqualToString:symbol]) found = v;
            [queue addObjectsFromArray:v.subviews];
        }
        CGRect drawn = [found convertRect:found.bounds toView:self.window];
        bottom = CGRectGetMaxY(drawn);
        for (NSNumber *dy in @[@0, @8]) {
            CGPoint at = CGPointMake(CGRectGetMidX(drawn), CGRectGetMidY(drawn) + dy.doubleValue);
            UIView *hit = [self.window hitTest:at withEvent:nil];
            BOOL inRow = NO;
            for (UIView *v = hit; v; v = v.superview) inRow = inRow || [NSStringFromClass(unitOf(v).class) containsString:@"FooterElementsUnit"] || [v.accessibilityIdentifier isEqualToString:@"QueueButtonNowPlaying"];
            [self expect:found && inRow step:[NSString stringWithFormat:@"%@: a touch on %@ +%.0f pt", when, symbol, dy.doubleValue]
                  detail:[NSString stringWithFormat:@"at y %.0f lands on %@", at.y, NSStringFromClass(hit.class)]];
        }
    }
    NSLog(@"[harness] footer glyphs end at %.0f of %.0f", bottom, self.window.bounds.size.height);
}

static NSUInteger footerBandsIn(UIView *player) {
    NSUInteger bands = 0;
    for (UIView *view in player.subviews) bands += [view isKindOfClass:NSClassFromString(@"SGRFooterReach")];
    return bands;
}

- (void)expectFooterRowWithQueueStandIn:(BOOL)standIn {
    UIView *queue = SGRFindByIdentifier(_host, @"QueueButtonNowPlaying", NULL);
    UIViewController *unit = unitOf(queue.superview.superview);
    UIView *footer = unit.view;
    CGRect ordinary = footer.bounds;
    CGPoint center = queue.center;
    // Labs' Agent button adds space below the row, not inside it.
    for (NSNumber *extra in @[@44, @0]) {
        CGRect bounds = ordinary;
        bounds.size.height += extra.doubleValue;
        footer.bounds = bounds;
        queue.center = CGPointMake(center.x, center.y + (extra.doubleValue ? 0.25 : 0));
        [unit viewDidLayoutSubviews];
        UIView *lyrics = firstOfClass(footer, @"SGRGlyphButton");
        UIView *placedQueue = SGRFindByIdentifier(footer, @"retrine.player.queue", NULL);
        BOOL aligned = lyrics && lyrics != placedQueue && lyrics.center.y == 22;
        if (standIn) aligned = aligned && placedQueue && placedQueue.center.y == lyrics.center.y;
        [self expect:aligned step:extra.doubleValue ? @"Footer glyphs stay on the row above the prompt" : @"Footer glyphs stay centered without the prompt"
              detail:[NSString stringWithFormat:@"Lyrics y %.2f, queue stand-in %@, footer height %.1f", lyrics.center.y,
                      placedQueue ? @(placedQueue.center.y) : @"absent", bounds.size.height]];
    }
}

- (void)runLook {
    UIImage *second = secondArtwork();
    after(3, ^{
        [self expectFooterTouches:@"a track"];
        [self expectFooterRowWithQueueStandIn:NO];
    });
    after(8, ^{
        serve(imageURI(@"ffff"), second, 0.25, NO);
        [self playTrack:@"spotify:track:harnessF" image:imageURI(@"ffff")];
    });
    after(8.4, ^{ [self showOnScreen:second]; });

    // A podcast episode's player as Spotify 9.2.0 lays it out in the same player view: a footer unit of its own in a
    // bottom stack of its own, its row as low as the Music app's already, so not hanging out of the stack; on every
    // switch Spotify takes the other kind's views out of the player and puts this kind's back on top.
    UIView *host = _host;
    UIView *music = SGRFindByIdentifier(host, @"npv.bottomStackView", NULL);
    UIView *strip = host.subviews[[host.subviews indexOfObject:music] + 1];
    CGFloat W = host.bounds.size.width, H = host.bounds.size.height, footerHeight = 44, stackHeight = 144, stackBottom = 20;
    UIStackView *episode = [[UIStackView alloc] initWithFrame:CGRectMake(0, H - stackBottom - stackHeight, W, stackHeight)];
    UIView *episodeFooter = box(episode, UIView.class, CGRectMake(0, stackHeight - footerHeight, W, footerHeight), nil);
    box(episodeFooter, UIStackView.class, CGRectMake(12, 0, W - 24, footerHeight), nil);
    UIViewController *episodeUnit = [_TtC20NowPlaying_ModesImpl18FooterElementsUnit new];
    episodeUnit.view = episodeFooter;
    void (^toEpisode)(void) = ^{
        [music removeFromSuperview];
        [strip removeFromSuperview];
        [host addSubview:episode];
    };
    void (^toMusic)(void) = ^{
        [episode removeFromSuperview];
        [host addSubview:music];
        [host addSubview:strip];
    };
    void (^expectEpisode)(void) = ^{
        UIView *lyrics = firstOfClass(episodeFooter, @"SGRGlyphButton");
        UIView *hit = [self.window hitTest:[lyrics convertPoint:CGPointMake(CGRectGetMidX(lyrics.bounds), CGRectGetMidY(lyrics.bounds)) toView:self.window] withEvent:nil];
        [self expect:lyrics && [hit isDescendantOfView:lyrics] step:@"an episode: a touch on Lyrics" detail:NSStringFromClass(hit.class)];
        [self expect:footerBandsIn(host) == 0 step:@"an episode: no band, its row not under its stack"
              detail:[NSString stringWithFormat:@"%lu", (unsigned long)footerBandsIn(host)]];
    };
    void (^expectMusic)(NSString *) = ^(NSString *when) {
        [self expectFooterTouches:when];
        [self expect:footerBandsIn(host) == 1 step:[NSString stringWithFormat:@"%@: one band", when]
              detail:[NSString stringWithFormat:@"%lu", (unsigned long)footerBandsIn(host)]];
    };
    runScript(@[
        @[@10, ^{
            self->_units = [self->_units arrayByAddingObject:episodeUnit];
            toEpisode();
            [self layOut];
        }],
        @[@0.5, expectEpisode],
        @[@0.5, ^{ toMusic(); [self layOut]; }],
        @[@0.5, ^{ expectMusic(@"a track after an episode"); }],
        @[@0.5, ^{ toEpisode(); [self layOut]; }],
        @[@0.5, expectEpisode],
        @[@0.5, ^{ toMusic(); [self layOut]; }],
        @[@0.5, ^{ expectMusic(@"a track after the episode again"); }],
        // There and back with no layout of the episode's row between, as with the player closed.
        @[@0.5, ^{ toEpisode(); toMusic(); [self layOut]; }],
        @[@0.5, ^{
            expectMusic(@"a track after an episode never laid out");
            NSLog(@"[harness] look checks: %lu of %lu right -- %@", (unsigned long)(self->_checks - self->_failures), (unsigned long)self->_checks,
                  self->_failures ? @"FAIL" : @"PASS");
            exit(self->_failures ? 1 : 0);
        }],
    ], 0);
}

@end

// Before every %ctor, so the redesign's gate reads on, and every session gets the picture server.
__attribute__((constructor(101))) static void sgr_harnessDefaults(void) {
    if ([scenario() isEqual:@"preview-tap"] || [scenario() isEqual:@"preview-pending"]) {
        [NSUserDefaults.standardUserDefaults setBool:YES forKey:SGKeyHideFullScreenCover];
    }
    [NSUserDefaults.standardUserDefaults setBool:!([scenario() isEqual:@"video-native"] || [scenario() isEqual:@"settings-pending-redesigned"]) forKey:@"spotifyglass.redesign"];
    if ([scenario() hasPrefix:@"settings-pending-"]) {
        [NSUserDefaults.standardUserDefaults removeObjectForKey:SGKeyStock];
        [NSUserDefaults.standardUserDefaults removeObjectForKey:SGKeyHideVideoSwitch];
    }
    if ([scenario() hasPrefix:@"lyric-line"] || [scenario() isEqual:@"cover-empty-strip"] || [scenario() isEqual:@"cover-strip-preview"])
        [NSUserDefaults.standardUserDefaults setBool:NO forKey:SGKeyHideVideoSwitch];
    if ([scenario() hasPrefix:@"video-"] && ![scenario() isEqual:@"video-relaunch"])
        [NSUserDefaults.standardUserDefaults removeObjectForKey:SGKeyHideVideoSwitch];
    if ([scenario() isEqualToString:@"background"])
        [NSUserDefaults.standardUserDefaults setInteger:SGRPlayerBackgroundAnimated forKey:@"spotifyglass.redesign.player.background"];
    // Animated artwork, its clip served by the picture server to the shared session too.
    if ([scenario() isEqualToString:@"visualiser"]) [NSUserDefaults.standardUserDefaults setInteger:4 forKey:@"spotifyglass.redesign.player.background"];
    // Still at launch, so the player looks up no clip; an address of this run's own, so the store has none of it yet.
    if ([scenario() isEqualToString:@"preview"]) {
        [NSUserDefaults.standardUserDefaults setInteger:0 forKey:@"spotifyglass.redesign.player.background"];
        setenv("HARNESS_CANVAS", [NSString stringWithFormat:@"https://canvas.harness/preview-%d.mp4", getpid()].UTF8String, 1);
        setenv("HARNESS_CANVAS_DELAY", "2", 1);
        [NSURLProtocol registerClass:SGRHarnessPictureServer.class];
    }
    // card: HARNESS_BACKGROUND (an index, Fluid if unset), and with HARNESS_LAST=1 a last track played whose cover is
    // the picture server's first picture; without it, no track ever played.
    if ([scenario() isEqualToString:@"card"]) {
        NSUserDefaults *store = NSUserDefaults.standardUserDefaults;
        const char *background = getenv("HARNESS_BACKGROUND");
        [store setInteger:background ? atoi(background) : 2 forKey:@"spotifyglass.redesign.player.background"];
        if (getenv("HARNESS_LAST")) {
            [store setObject:@{@"uri": @"spotify:track:last", @"title": @"Holocene, the Long Version Recorded Live at the Old Church",
                               @"artist": @"Bon Iver", @"artwork": [@"https://i.scdn.co/image/" stringByAppendingString:[imageURI(@"aaaa") substringFromIndex:14]],
                               @"canvas": [NSString stringWithFormat:@"https://canvas.harness/last-%d.mp4", getpid()]}
                      forKey:@"spotifyglass.lastTrack"];
        } else {
            [store removeObjectForKey:@"spotifyglass.lastTrack"];
        }
        [NSURLProtocol registerClass:SGRHarnessPictureServer.class];
    }
    // options: Fluid drawn Smooth, the look switches and Grain at their standard (the app's defaults outlive a run).
    if ([scenario() isEqualToString:@"options"] || [scenario() isEqualToString:@"renderer"]) {
        NSUserDefaults *store = NSUserDefaults.standardUserDefaults;
        [store setInteger:SGRPlayerBackgroundFluid forKey:@"spotifyglass.redesign.player.background"];
        [store setInteger:SGRFluidRendererSmooth forKey:@"spotifyglass.redesign.fluid.renderer"];
        for (NSString *key in @[SGRKeyPlayerHeaderGlass, SGRKeyPlayerMusicIcons, @"spotifyglass.redesign.fluid.grain"]) [store removeObjectForKey:key];
    }
    // controls: shuffle and repeat both hidden, read at launch (runSpreadChecks), and taken off again before it exits.
    if ([scenario() isEqualToString:@"controls"]) {
        [NSUserDefaults.standardUserDefaults setBool:YES forKey:SGRKeyPlayerHideShuffle];
        [NSUserDefaults.standardUserDefaults setBool:YES forKey:SGRKeyPlayerHideRepeat];
    }
    // The shared session the catalog asks with.
    if ([scenario() isEqualToString:@"catalog"]) [NSURLProtocol registerClass:SGRHarnessPictureServer.class];
    // automix: Fluid behind the player, AutoMix and its three player options at their standard (all off) until the
    // scenario turns them on, so it starts from what a user who never opened the page has.
    if ([scenario() isEqualToString:@"automix"]) {
        NSUserDefaults *store = NSUserDefaults.standardUserDefaults;
        [store setInteger:SGRPlayerBackgroundFluid forKey:@"spotifyglass.redesign.player.background"];
        for (NSString *key in @[@"spotifyglass.automix", @"spotifyglass.automix.style", @"spotifyglass.automix.show-progress",
                                @"spotifyglass.automix.show-queue", @"spotifyglass.automix.artwork"]) [store removeObjectForKey:key];
        [NSURLProtocol registerClass:SGRHarnessPictureServer.class];
    }
    // still: Animated with the full-screen cover off, and no Canvas until the scenario names one.
    if ([scenario() isEqualToString:@"still"]) {
        [NSUserDefaults.standardUserDefaults setInteger:SGRPlayerBackgroundAnimated forKey:@"spotifyglass.redesign.player.background"];
        [NSUserDefaults.standardUserDefaults setInteger:SGRPlayerBackgroundAnimated forKey:SGRKeyPlayerArtworkBackground];
        [NSUserDefaults.standardUserDefaults removeObjectForKey:SGRKeyPlayerAnimatedStill];
        unsetenv("HARNESS_CANVAS");
        [NSURLProtocol registerClass:SGRHarnessPictureServer.class];
    }
    // autoviz: Animated with the Visualizer-without-a-clip switch off, no Canvas until the scenario names one, every
    // lookup 1.5 s late. shuffle and heat: the Visualizer as the background (shuffle moves to Animated at the end),
    // their switches off, the style at its default.
    if ([scenario() isEqualToString:@"autoviz"] || [scenario() isEqualToString:@"shuffle"] || [scenario() isEqualToString:@"heat"]) {
        NSUserDefaults *store = NSUserDefaults.standardUserDefaults;
        BOOL animated = [scenario() isEqualToString:@"autoviz"];
        SGRPlayerBackgroundKind kind = animated ? SGRPlayerBackgroundAnimated : SGRPlayerBackgroundVisualiser;
        [store setInteger:kind forKey:@"spotifyglass.redesign.player.background"];
        [store setInteger:kind forKey:SGRKeyPlayerArtworkBackground];
        for (NSString *key in @[SGRKeyPlayerAnimatedStill, SGRKeyPlayerAnimatedVisualiser, SGRKeyVisualiserShuffle, SGRKeyVisualiserShuffleHome,
                                SGRKeyVisualiserIgnoreHeat, SGRKeyVisualiserStyle]) [store removeObjectForKey:key];
        unsetenv("HARNESS_CANVAS");
        if (animated) SGRHarnessSetLookupDelay(1.5);
        [NSURLProtocol registerClass:SGRHarnessPictureServer.class];
    }
    // settings: Animated, Song without a clip, the Buttons chips and the look switches at their standard (the app's defaults
    // outlive a run).
    if ([scenario() isEqualToString:@"settings"]) {
        NSUserDefaults *store = NSUserDefaults.standardUserDefaults;
        [store setInteger:SGRPlayerBackgroundAnimated forKey:SGRKeyPlayerArtworkBackground];
        for (NSString *key in @[SGRKeyPlayerAnimatedStill, SGRKeyPlayerAnimatedVisualiser, SGRKeyPlayerHoldNoClip, SGRKeyPlayerHideShuffle, SGRKeyPlayerHideRepeat,
                                SGKeyHideVideoSwitch, SGRKeyPlayerHeaderGlass, SGRKeyPlayerStarAdd]) [store removeObjectForKey:key];
    }
    [NSUserDefaults.standardUserDefaults setBool:([scenario() hasPrefix:@"lyric-line"] || [scenario() isEqual:@"preview-tap"] || [scenario() isEqual:@"preview-pending"]) forKey:SGRKeyPlayerLyricLine];
    if ([scenario() hasPrefix:@"lyric-line"]) {
        [NSUserDefaults.standardUserDefaults removeObjectForKey:@"spotifyglass.redesign.lyricsTranslation"];
        SGRSetPlayerLineSmall(NO);
        [NSUserDefaults.standardUserDefaults setInteger:4 forKey:@"spotifyglass.redesign.lyricsSize.underCover"]; // retired choice is ignored
    }
    if ([scenario() isEqual:@"motion"] || [scenario() isEqual:@"motion-mirror"] || [scenario() isEqualToString:@"settings"] ||
        [scenario() isEqualToString:@"lyric-line-clip"] || [scenario() isEqual:@"lyric-line-chip-clip"] || [scenario() isEqual:@"lyric-line-owner-clip"] || [scenario() isEqualToString:@"lyric-line-switch"]) {
        [NSUserDefaults.standardUserDefaults setInteger:3 forKey:@"spotifyglass.redesign.player.background"];
        setenv("HARNESS_CANVAS", "https://canvas.harness/clip.mp4", 1);
        [NSURLProtocol registerClass:SGRHarnessPictureServer.class];
    }
    Method original = class_getClassMethod(NSURLSessionConfiguration.class, @selector(defaultSessionConfiguration));
    Method harness = class_getClassMethod(NSURLSessionConfiguration.class, @selector(sgr_harnessDefault));
    method_exchangeImplementations(original, harness);
}

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(SGRHarnessDelegate.class));
    }
}
