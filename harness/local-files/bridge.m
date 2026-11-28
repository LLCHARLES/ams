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
static NSUInteger barReads;
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
UIView *SGRFindByIdentifier(UIView *root, NSString *identifier, const void *key) {
    if ([identifier isEqual:@"SPTNowPlayingBar"] && [root.accessibilityIdentifier isEqual:@"bridge.bar.root"]) barReads++;
    if ([root.accessibilityIdentifier isEqualToString:identifier]) return root;
    for (UIView *child in root.subviews) {
        UIView *match = SGRFindByIdentifier(child, identifier, key);
        if (match) return match;
    }
    return nil;
}
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

static void reportTrack(void) {
    for (id<SGPlayerStateObserver> observer in observers.copy) [observer playerStateDidChange:SGPlayerState()];
}

static void checkArtworkResume(UIImage *red, UIImage *blue) {
    NSString *directory = SGLocalFileCoversDirectory();
    CHECK([NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil]);
    NSString *pathA = [directory stringByAppendingPathComponent:@"resume-a.png"];
    NSString *pathB = [directory stringByAppendingPathComponent:@"resume-b.png"];
    CHECK([UIImagePNGRepresentation(blue) writeToFile:pathA atomically:YES]);
    CHECK([UIImagePNGRepresentation(red) writeToFile:pathB atomically:YES]);
    BridgeTrack *a = [BridgeTrack new], *b = [BridgeTrack new];
    a.URI = [NSURL URLWithString:@"spotify:local:Artist:Album:A:60"];
    b.URI = [NSURL URLWithString:@"spotify:local:Artist:Album:B:60"];
    a.metadata = @{@"image_url": SGLocalFileCoverURL(pathA)};
    b.metadata = @{@"image_url": SGLocalFileCoverURL(pathB)};

    dispatch_semaphore_t firstRead = dispatch_semaphore_create(0);
    dispatch_semaphore_t releaseRead = dispatch_semaphore_create(0);
    dispatch_semaphore_t released = dispatch_semaphore_create(0);
    __block NSUInteger reads = 0;
    NSObject *lock = [NSObject new];
    Method method = class_getClassMethod(UIImage.class, @selector(imageWithContentsOfFile:));
    IMP original = method_getImplementation(method);
    IMP replacement = imp_implementationWithBlock(^UIImage *(id owner, NSString *path) {
        BOOL first = NO;
        if ([path isEqual:pathA] || [path isEqual:pathB]) {
            @synchronized (lock) { first = ++reads == 1; }
        }
        if (first) {
            dispatch_semaphore_signal(firstRead);
            CHECK(dispatch_semaphore_wait(releaseRead, dispatch_time(DISPATCH_TIME_NOW, 15 * NSEC_PER_SEC)) == 0);
            dispatch_semaphore_signal(released);
            return red;
        }
        return ((UIImage *(*)(id, SEL, NSString *))original)(owner, @selector(imageWithContentsOfFile:), path);
    });
    method_setImplementation(method, replacement);

    UIImage *previous = SGRNowPlayingArtwork(NULL, NULL);
    state.track = a;
    reportTrack();
    CHECK(dispatch_semaphore_wait(firstRead, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)) == 0);
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    [center postNotificationName:UIApplicationWillResignActiveNotification object:nil];
    state.track = b;
    reportTrack();
    state.track = a;
    reportTrack();
    [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
    @synchronized (lock) { CHECK(reads == 1); }
    CHECK(SGRNowPlayingArtwork(NULL, NULL) == previous);

    [center postNotificationName:UIApplicationDidBecomeActiveNotification object:nil];
    NSString *uri = nil;
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5];
    while (deadline.timeIntervalSinceNow > 0) {
        SGRNowPlayingArtwork(&uri, NULL);
        if ([uri isEqual:a.URI.absoluteString]) break;
        [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.005]];
    }
    UIImage *current = SGRNowPlayingArtwork(&uri, NULL);
    CHECK([uri isEqual:a.URI.absoluteString] && current != previous && current != red);
    @synchronized (lock) { CHECK(reads == 2); }
    dispatch_semaphore_signal(releaseRead);
    CHECK(dispatch_semaphore_wait(released, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)) == 0);
    [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
    CHECK(SGRNowPlayingArtwork(NULL, NULL) == current);
    method_setImplementation(method, original);
    imp_removeBlock(replacement);
    [NSFileManager.defaultManager removeItemAtPath:pathA error:nil];
    [NSFileManager.defaultManager removeItemAtPath:pathB error:nil];
    puts("PASS: inactive A -> B -> A defers cover reads, resumes once and rejects the old A");
}

static void checkBarArtworkResume(void) {
    UIViewController *bar __attribute__((objc_precise_lifetime)) = [_TtC18NowPlaying_BarImpl27NowPlayingBarViewController new];
    UIView *card = [UIView new], *holder = [UIView new];
    card.accessibilityIdentifier = @"SPTNowPlayingBar";
    holder.accessibilityIdentifier = @"Encore.ImageView";
    UIImageView *imageView = [UIImageView new];
    bar.view.accessibilityIdentifier = @"bridge.bar.root";
    [bar.view addSubview:card];
    [card addSubview:holder];
    [holder addSubview:imageView];

    BridgeTrack *a = [BridgeTrack new], *b = [BridgeTrack new];
    a.URI = [NSURL URLWithString:@"spotify:track:barA"];
    b.URI = [NSURL URLWithString:@"spotify:track:barB"];
    a.metadata = b.metadata = @{};
    state.track = a;
    UIImage *previous = square(UIColor.yellowColor), *current = square(UIColor.greenColor);
    imageView.image = previous;
    [bar viewDidLayoutSubviews];
    CHECK(SGRNowPlayingArtwork(NULL, NULL) == previous);
    reportTrack();
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    [center postNotificationName:UIApplicationWillResignActiveNotification object:nil];
    state.track = b;
    reportTrack();
    barReads = 0;
    [center postNotificationName:UIApplicationDidBecomeActiveNotification object:nil];
    // Wait for the first read while the bar still shows A, then install B without a layout or report.
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5];
    while (barReads == 0 && deadline.timeIntervalSinceNow > 0)
        [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.005]];
    CHECK(barReads > 0 && SGRNowPlayingArtwork(NULL, NULL) == previous);
    imageView.image = current;
    deadline = [NSDate dateWithTimeIntervalSinceNow:5];
    while (SGRNowPlayingArtwork(NULL, NULL) != current && deadline.timeIntervalSinceNow > 0)
        [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.005]];
    NSString *uri = nil;
    CHECK(SGRNowPlayingArtwork(&uri, NULL) == current && [uri isEqual:b.URI.absoluteString]);

    // Schedule a fresh set for B before locking. When B is still current on activation, only the
    // four new reads should run. The URI and foreground checks alone would let the old set run too.
    state.track = a;
    reportTrack();
    state.track = b;
    reportTrack();
    [center postNotificationName:UIApplicationWillResignActiveNotification object:nil];
    barReads = 0;
    [center postNotificationName:UIApplicationDidBecomeActiveNotification object:nil];
    __block BOOL drained = NO;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        drained = YES;
    });
    deadline = [NSDate dateWithTimeIntervalSinceNow:10];
    while (!drained && deadline.timeIntervalSinceNow > 0)
        [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    CHECK(drained && barReads == 4 && SGRNowPlayingArtwork(&uri, NULL) == current && [uri isEqual:b.URI.absoluteString]);
    puts("PASS: retry reads late bar artwork without layout and only the current activation's four reads run");
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
    checkArtworkResume(red, blue);
    checkBarArtworkResume();
    [NSNotificationCenter.defaultCenter removeObserver:token];
    method_setImplementation(getter, original);
    imp_removeBlock(replacement);
    [NSFileManager.defaultManager removeItemAtPath:path error:nil];
    puts("PASS: production bridge/field: provisional red -> exact blue changes identity and field; late provisional replies rejected");
    return 0;
} }
