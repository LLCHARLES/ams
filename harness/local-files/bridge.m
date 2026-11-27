// Production resolver + Logos artwork bridge + field identity gate. Only Spotify/OS boundaries,
// palette rendering and unused animation layers are doubles.
#import <MediaPlayer/MediaPlayer.h>
#import <objc/runtime.h>
#import "Core/SGCore.h"
#import "Shared/LocalFiles/LocalFiles.h"
#import "Shared/Player/PlayerEvents.h"
#import "Redesigned/Kit/SGRBridges.h"
#import "Redesigned/Kit/SGRField.h"
#import "Redesigned/Kit/SGRPalette.h"
#import "Redesigned/Kit/SGRTokens.h"
#import "Redesigned/Kit/SGRFlow.h"
#import "Redesigned/Kit/SGRFluid.h"
#import "Shared/Player/NowPlayingExtras.h"

NSNotificationName const SGNowPlayingInfoDidChangeNotification = @"spotifyglass.nowPlayingInfoDidChange";

#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAILED line %d: %s\n", __LINE__, #c); exit(1); } } while (0)

@interface BridgeTrack : NSObject
@property(nonatomic, strong) NSURL *URI;
@property(nonatomic, copy) NSDictionary *metadata;
@property(nonatomic, copy) NSString *trackTitle, *artistName;
@end
@implementation BridgeTrack @end
@interface BridgeState : NSObject
@property(nonatomic, strong) BridgeTrack *track;
@end
@implementation BridgeState @end
@interface BridgeNowPlaying : NSObject
@property(nonatomic, copy) NSDictionary *nowPlayingInfo;
@end
@implementation BridgeNowPlaying @end
// The production Logos hook drives the bridge through the normal bar layout entry point.
@interface _TtC18NowPlaying_BarImpl27NowPlayingBarViewController : UIViewController
@end
@implementation _TtC18NowPlaying_BarImpl27NowPlayingBarViewController
- (void)viewDidLayoutSubviews {}
@end

static BridgeState *state;
static NSMutableArray<id<SGPlayerStateObserver>> *observers;
NSString *SGURIString(id uri) { return [uri isKindOfClass:NSURL.class] ? [uri absoluteString] : uri; }
SPTPlayerState *SGPlayerState(void) { return (SPTPlayerState *)state; }
void SGAddPlayerStateObserver(id<SGPlayerStateObserver> observer) {
    if (!observers) observers = [NSMutableArray array];
    [observers addObject:observer];
}
BOOL SGRedesignedUI(void) { return YES; }
void SGRequireClasses(NSArray<NSString *> *names) {
    for (NSString *name in names) CHECK(NSClassFromString(name));
}
UIView *SGRFindByIdentifier(UIView *root, NSString *identifier, const void *key) { return nil; }
NSString *const SGPlayerTransitionNotification = @"bridge.transition";
NSString *const SGPlayerTransitionEndedNotification = @"bridge.transitionEnded";
CFTimeInterval SGPlayerTransitionEnds(void) { return 0; }
const NSTimeInterval SGRCrossfade = 0;
UIColor *SGRNeutralField(void) { return UIColor.blackColor; }
BOOL SGRReduceMotion(void) { return YES; }
void SGRAnimate(SGRMotion motion, void (^animations)(void), void (^completion)(BOOL)) {
    animations();
    if (completion) completion(YES);
}
UIColor *SGRFieldColorFor(UIColor *color) { return color; }
@implementation SGRFlowLayer
- (void)setColors:(NSArray<UIColor *> *)colors animated:(BOOL)animated {}
- (UIColor *)baseColor { return nil; }
@end
@implementation SGRFluidLayer
- (void)setArtwork:(UIImage *)image animated:(BOOL)animated {}
@end

@interface SGRPalette ()
@property(nonatomic, readwrite) UIColor *fieldColor;
@end
@implementation SGRPalette
+ (void)paletteForImage:(UIImage *)image request:(SGRPaletteRequest)request completion:(void (^)(SGRPalette *))completion {
    uint8_t pixel[4] = {0};
    CGColorSpaceRef rgb = CGColorSpaceCreateDeviceRGB();
    CGContextRef bitmap = CGBitmapContextCreate(pixel, 1, 1, 8, 4, rgb,
        kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGContextDrawImage(bitmap, CGRectMake(0, 0, 1, 1), image.CGImage);
    CGContextRelease(bitmap);
    CGColorSpaceRelease(rgb);
    SGRPalette *palette = [SGRPalette new];
    palette.fieldColor = [UIColor colorWithRed:pixel[0] / 255.0 green:pixel[1] / 255.0 blue:pixel[2] / 255.0 alpha:1];
    completion(palette);
}
+ (void)tintForImage:(UIImage *)image surface:(UIColor *)surface strong:(BOOL)strong completion:(void (^)(UIColor *))completion {
    completion(surface);
}
@end

static UIImage *square(UIColor *color) {
    return [[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(4, 4)]
        imageWithActions:^(UIGraphicsImageRendererContext *context) {
            [color setFill]; UIRectFill(CGRectMake(0, 0, 4, 4));
        }];
}
static BOOL fieldIs(SGRArtworkField *field, CGFloat red, CGFloat blue) {
    CGFloat r, g, b, a;
    return [field.fieldColor getRed:&r green:&g blue:&b alpha:&a] &&
        r == red && g == 0 && b == blue && a == 1;
}

int main(void) { @autoreleasepool {
    __block NSString *phase = @"opening";
    __weak NSMutableDictionary *releasedOwner;
    @autoreleasepool {
        NSMutableDictionary *owner = [NSMutableDictionary dictionary];
        releasedOwner = owner;
        SGRObservePlayerTransition(owner, ^(NSMutableDictionary *observed) { observed[@"phase"] = phase; });
        [NSNotificationCenter.defaultCenter postNotificationName:SGPlayerTransitionNotification object:nil];
        CHECK([owner[@"phase"] isEqual:@"opening"]);
        phase = @"closed";
        [NSNotificationCenter.defaultCenter postNotificationName:SGPlayerTransitionEndedNotification object:nil];
        CHECK([owner[@"phase"] isEqual:@"closed"]);
    }
    CHECK(releasedOwner == nil);
    [NSNotificationCenter.defaultCenter postNotificationName:SGPlayerTransitionNotification object:nil];
    [NSNotificationCenter.defaultCenter postNotificationName:SGPlayerTransitionEndedNotification object:nil];
    puts("PASS: transition callback follows opening and closing without retaining its owner");
    [NSUserDefaults.standardUserDefaults removeObjectForKey:SGKeyLocalFileEdits];
    UIImage *red = square(UIColor.redColor), *blue = square(UIColor.blueColor);
    BridgeNowPlaying *center = [BridgeNowPlaying new];
    center.nowPlayingInfo = @{MPMediaItemPropertyTitle: @"Same title",
        MPMediaItemPropertyArtist: @"Same artist",
        MPMediaItemPropertyArtwork: [[MPMediaItemArtwork alloc] initWithBoundsSize:red.size
            requestHandler:^UIImage *(CGSize size) { return red; }]};
    Method getter = class_getClassMethod(MPNowPlayingInfoCenter.class, @selector(defaultCenter));
    IMP replacement = imp_implementationWithBlock(^id(id self) { return center; });
    IMP original = method_setImplementation(getter, replacement);
    SGRArtworkField *field = [[SGRArtworkField alloc] initWithFrame:CGRectMake(0, 0, 40, 40)];
    id token = [NSNotificationCenter.defaultCenter addObserverForName:SGRNowPlayingArtworkDidChangeNotification
        object:nil queue:nil usingBlock:^(NSNotification *note) {
            NSString *identity = nil;
            UIImage *image = SGRNowPlayingArtwork(NULL, &identity);
            [field setArtwork:image identity:identity animated:NO];
        }];
    state = [BridgeState new];
    state.track = [BridgeTrack new];
    state.track.URI = [NSURL URLWithString:@"spotify:local:Artist:Album:Same:60"];
    state.track.trackTitle = @"Same title";
    state.track.artistName = @"Same artist";
    state.track.metadata = @{};
    for (id<SGPlayerStateObserver> observer in observers.copy) [observer playerStateDidChange:SGPlayerState()];
    CHECK(fieldIs(field, 1, 0));
    NSString *provisionalIdentity;
    CHECK(SGRNowPlayingArtwork(NULL, &provisionalIdentity) == red);

    NSString *path = [NSProcessInfo.processInfo.environment[@"CFFIXED_USER_HOME"] stringByAppendingPathComponent:@"bridge-blue.png"];
    CHECK([UIImagePNGRepresentation(blue) writeToFile:path atomically:YES]);
    state.track.metadata = @{@"image_url": path};
    UIViewController *bar = [_TtC18NowPlaying_BarImpl27NowPlayingBarViewController new];
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:60];
    // Real layout callbacks ask the bridge again as the asynchronous metadata thumbnail arrives.
    while (!fieldIs(field, 0, 1) && deadline.timeIntervalSinceNow > 0) {
        [bar viewDidLayoutSubviews];
        [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.005]];
    }
    CHECK(fieldIs(field, 0, 1));
    NSString *exactIdentity;
    UIImage *exact = SGRNowPlayingArtwork(NULL, &exactIdentity);
    CHECK([exactIdentity hasSuffix:@"#exact"] && ![exactIdentity isEqual:provisionalIdentity]);
    // A late report missing its metadata falls back to the still-red system artwork. Neither that
    // resolver path nor a screen's late reply may downgrade the exact blue cover.
    state.track.metadata = @{};
    [bar viewDidLayoutSubviews];
    SGRSetNowPlayingArtwork(red, state.track.URI.absoluteString, SGRArtworkQualityLow);
    NSString *retainedIdentity;
    CHECK(SGRNowPlayingArtwork(NULL, &retainedIdentity) == exact);
    CHECK([retainedIdentity isEqual:exactIdentity] && fieldIs(field, 0, 1));
    [NSNotificationCenter.defaultCenter removeObserver:token];
    method_setImplementation(getter, original);
    imp_removeBlock(replacement);
    [NSFileManager.defaultManager removeItemAtPath:path error:nil];
    puts("PASS: production bridge/field: provisional red -> exact blue changes identity and field; late provisional replies rejected");
    return 0;
} }
