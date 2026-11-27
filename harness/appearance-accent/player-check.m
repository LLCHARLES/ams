// Real UIKit rasterization, animation delegates and presentation layers. Only Spotify's data is doubled.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "Core/SGPrefs.h"
#import "Core/SGTopController.h"
#import "Redesigned/Kit/SGRAccent.h"
#import "Redesigned/Kit/SGRPalette.h"
#import "Redesigned/Kit/SGRBridges.h"
#import "Redesigned/Player/Player.h"
#import "../harness-fail.h"

NSNotificationName const SGRNowPlayingArtworkDidChangeNotification = @"harness.artwork";
NSNotificationName const SGRFieldColorDidChangeNotification = @"harness.field";
static UIViewController *front;
BOOL SGRedesignedUI(void) { return YES; }
UIWindow *SGAppWindow(void) { return front.view.window; }
UIViewController *SGTopControllerInWindow(UIWindow *window, NSMutableArray *path, NSMutableArray *presented) { return front; }
SPTPlayerState *SGPlayerState(void) { return nil; }
NSString *SGURIString(id uri) { return nil; }
void SGAddPlayerStateObserver(id<SGPlayerStateObserver> observer) {}
UIImage *SGRNowPlayingArtwork(NSString **track, NSString **identity) { return nil; }
@implementation SGRPalette
+ (void)paletteForImage:(UIImage *)image request:(SGRPaletteRequest)request completion:(void (^)(SGRPalette *))completion { HARNESS_FAIL(@"unexpected artwork"); }
+ (void)tintForImage:(UIImage *)image surface:(UIColor *)surface strong:(BOOL)strong completion:(void (^)(UIColor *))completion { HARNESS_FAIL(@"unexpected tint"); }
@end

static NSUInteger checks;
static void expect(BOOL ok, NSString *what) { checks++; if (!ok) HARNESS_FAIL(@"%@",what); }
static void expectRGB(NSInteger got, NSInteger wanted, NSString *what) {
    checks++; if (got!=wanted) HARNESS_FAIL(@"%@: got #%06lX, expected #%06lX",what,(long)got,(long)wanted);
}
static UIColor *color(NSInteger rgb) {
    CGFloat c[]={((rgb>>16)&255)/255.0,((rgb>>8)&255)/255.0,(rgb&255)/255.0,1};
    CGColorSpaceRef space=CGColorSpaceCreateDeviceRGB(); CGColorRef cg=CGColorCreate(space,c);
    UIColor *result=[UIColor colorWithCGColor:cg]; CGColorRelease(cg); CGColorSpaceRelease(space); return result;
}
static NSInteger rgb(UIColor *color) {
    CGFloat r,g,b,a; if (![color getRed:&r green:&g blue:&b alpha:&a]) HARNESS_FAIL(@"not RGB");
    return (lround(r*255)<<16)|(lround(g*255)<<8)|lround(b*255);
}
static UIGraphicsImageRenderer *renderer(void) {
    UIGraphicsImageRendererFormat *format=[UIGraphicsImageRendererFormat defaultFormat];
    format.scale=1; format.preferredRange=UIGraphicsImageRendererFormatRangeStandard;
    return [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(16,16) format:format];
}
static UIImage *rectangle(UIColor *ink) {
    return [renderer() imageWithActions:^(UIGraphicsImageRendererContext *context) { [ink setFill]; UIRectFill(CGRectMake(0,0,16,16)); }];
}
static UIImage *knownIcon(UIColor *ink) {
    return [rectangle(UIColor.whiteColor) imageWithTintColor:ink renderingMode:UIImageRenderingModeAlwaysOriginal];
}
static uint32_t pixel(UIImage *image, NSUInteger x) {
    UIImage *drawn=[renderer() imageWithActions:^(UIGraphicsImageRendererContext *context) { [image drawInRect:CGRectMake(0,0,16,16)]; }];
    uint8_t pixels[16*16*4]={0};
    CGColorSpaceRef space=CGColorSpaceCreateDeviceRGB();
    CGContextRef context=CGBitmapContextCreate(pixels,16,16,8,16*4,space,(CGBitmapInfo)kCGImageAlphaPremultipliedLast);
    CGContextDrawImage(context,CGRectMake(0,0,16,16),drawn.CGImage); CGContextRelease(context); CGColorSpaceRelease(space);
    uint8_t *p=pixels+(8*16+x)*4;
    return ((uint32_t)p[0]<<24)|((uint32_t)p[1]<<16)|((uint32_t)p[2]<<8)|p[3];
}
static NSInteger imageRGB(UIImage *image) { return pixel(image,4)>>8; }
static void checkAnimations(CAShapeLayer *shape, NSInteger initial, CFTimeInterval origin) {
    CAKeyframeAnimation *keys=(id)[shape animationForKey:@"lottie.fill"];
    CABasicAnimation *basic=(id)[shape animationForKey:@"lottie.stroke"];
    expect(keys && basic,@"running animations remain installed");
    expectRGB(rgb([UIColor colorWithCGColor:(__bridge CGColorRef)keys.values[0]]),initial,@"running keyframe retains its original color");
    expectRGB(rgb([UIColor colorWithCGColor:(__bridge CGColorRef)keys.values[1]]),0xC3B9B9,@"unowned keyframe stays unchanged");
    expectRGB(rgb([UIColor colorWithCGColor:(__bridge CGColorRef)basic.fromValue]),initial,@"running basic animation is not replaced");
    expect(keys.beginTime==origin && keys.duration==100 && keys.timeOffset==.25 && keys.speed==.75,@"running animation clock is unchanged");
}

@interface AnimationObserver : NSObject <CAAnimationDelegate>
@property (nonatomic,weak) CALayer *layer;
@property (nonatomic,strong) CADisplayLink *link;
@property (nonatomic,copy) void (^changeColors)(void);
@property (nonatomic,copy) void (^finished)(void);
@property (nonatomic) NSUInteger starts,stops,samples;
@property (nonatomic) CGFloat lastRed;
@end
@implementation AnimationObserver
- (void)animationDidStart:(CAAnimation *)animation {
    self.starts++;
    self.link=[CADisplayLink displayLinkWithTarget:self selector:@selector(sample)];
    [self.link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
}
- (void)sample {
    CALayer *presentation=self.layer.presentationLayer;
    if (!presentation.backgroundColor) return;
    CGFloat r,g,b,a; [[UIColor colorWithCGColor:presentation.backgroundColor] getRed:&r green:&g blue:&b alpha:&a];
    if (self.samples) expect(r<=self.lastRed,@"presentation continues fading toward black without a repaint jump");
    self.lastRed=r; self.samples++;
    if (self.changeColors) { void (^change)(void)=self.changeColors; self.changeColors=nil; change(); }
}
- (void)animationDidStop:(CAAnimation *)animation finished:(BOOL)finished {
    self.stops++;
    [self.link invalidate]; self.link=nil;
    expect(finished,@"repainting must not cancel the original animation delegate");
    expect(self.starts==1 && self.stops==1,@"original delegate starts and completes exactly once");
    expect(self.samples>=2,@"presentation continuity observed across real display frames");
    self.finished();
}
@end

// A fresh process launched with Spotify's own accent and Follow the cover on. Typed negative preferences must be in
// place before the tweak constructors (the Kit decides its hooks there), and +load runs before them.
static BOOL stockLaunch(void) { return [NSProcessInfo.processInfo.arguments containsObject:@"stock"]; }
@interface StockLaunchDefaults : NSObject @end
@implementation StockLaunchDefaults
+ (void)load {
    if (!stockLaunch()) return;
    [NSUserDefaults.standardUserDefaults setVolatileDomain:@{SGRKeyAccent:@(-1),SGRKeyAccentAuto:@NO,SGRKeyPlayerFollowsCover:@YES} forName:NSArgumentDomain];
    SGPrefsChanged();
}
@end

static void runStockChecks(void) {
    SGRAccentStart();
    expect(!SGRAccentSubstitutionEnabled() && SGRAccentColor()==nil,@"stock launch substitutes no accent");
    expect(SGRPlayerFollowsCover(),@"stock launch input: Follow the cover is on");
    UIColor *stockGreen=[UIColor colorWithRed:30/255.0 green:215/255.0 blue:96/255.0 alpha:1];
    // The same three kinds of control Spotify draws its lit player controls with, once in the player's stack and once outside it.
    Class lottieClass=objc_allocateClassPair(UIView.class,"Lottie.LottieAnimationView",0); objc_registerClassPair(lottieClass);
    NSMutableArray<NSDictionary *> *sets=[NSMutableArray array];
    UIStackView *stack=[[UIStackView alloc] initWithFrame:CGRectMake(0,0,300,200)]; [front.view addSubview:stack];
    UIView *outside=[[UIView alloc] initWithFrame:CGRectMake(0,200,300,200)]; [front.view addSubview:outside];
    for (UIView *host in @[stack,outside]) {
        UIImageView *icon=[[UIImageView alloc] initWithImage:knownIcon(stockGreen)];
        UIView *dot=[UIView new]; dot.backgroundColor=stockGreen;
        UIView *lottie=[[lottieClass alloc] initWithFrame:CGRectMake(0,0,50,50)];
        CAShapeLayer *shape=[CAShapeLayer layer]; [lottie.layer addSublayer:shape]; shape.fillColor=stockGreen.CGColor;
        for (UIView *view in @[icon,dot,lottie]) [host addSubview:view];
        [sets addObject:@{@"icon":icon,@"dot":dot,@"shape":shape}];
    }
    void (^expectAll)(NSDictionary *,NSInteger,NSString *)=^(NSDictionary *set,NSInteger wanted,NSString *where) {
        expectRGB(imageRGB([(UIImageView *)set[@"icon"] image]),wanted,[where stringByAppendingString:@" image"]);
        expectRGB(rgb([(UIView *)set[@"dot"] backgroundColor]),wanted,[where stringByAppendingString:@" background"]);
        expectRGB(rgb([UIColor colorWithCGColor:[(CAShapeLayer *)set[@"shape"] fillColor]]),wanted,[where stringByAppendingString:@" shape"]);
    };
    expectAll(sets[0],0x1ED760,@"stock launch: player control before a cover");
    SGRPlayerSetCoverAccent(color(0xFF00FF));
    SGRPlayerPaintCover(stack);
    expectAll(sets[0],0xFF26FF,@"stock launch with Follow the cover: player control follows the cover");
    expectAll(sets[1],0x1ED760,@"stock launch with Follow the cover: control outside the player stays Spotify green");
    SGRPlayerSetCoverAccent(UIColor.grayColor);
    expectAll(sets[0],0x1ED760,@"stock launch: a gray cover gives Spotify green back");
    printf("player accent stock launch with Follow: %lu checks passed\n",(unsigned long)checks);
    exit(0);
}

static void runChecks(void) {
    if (stockLaunch()) runStockChecks();
    BOOL automatic=SGFlag(SGRKeyAccentAuto,NO), follow=SGRPlayerFollowsCover();
    [NSUserDefaults.standardUserDefaults setVolatileDomain:@{SGRKeyAccentAuto:@(automatic),SGRKeyPlayerFollowsCover:@(follow),SGRKeyAccent:@0xFFFF00} forName:NSArgumentDomain];
    SGPrefsChanged(); SGRAccentStart(); SGRAccentPublishPageColor(front.view,color(0x402020));
    NSInteger first=automatic?0xC3B9B9:0xFFFF00;
    expectRGB(SGRAccentRGB(),first,@"resolved page accent");
    if (!automatic) expect(SGRPlayerAccentLike(color(0xFFFF00)),@"Picked preserves the footer's existing lit-control classification");
    UIStackView *stack=[[UIStackView alloc] initWithFrame:CGRectMake(0,0,300,200)]; [front.view addSubview:stack];
    UIImageView *owned=[[UIImageView alloc] initWithImage:knownIcon(SGRAccentColor())];
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    [stack addSubview:button];
    UIImageView *derived=[[UIImageView alloc] initWithImage:knownIcon([SGRAccentColor() colorWithAlphaComponent:.5])];
    UIImageView *unowned=[[UIImageView alloc] initWithImage:rectangle(color(first))];
    UIImageView *templateView=[[UIImageView alloc] initWithImage:[knownIcon(SGRAccentColor()) imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
    templateView.tintColor=UIColor.redColor;
    UIImage *mixed=[renderer() imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [SGRAccentColor() setFill]; UIRectFill(CGRectMake(0,0,8,16));
        CGContextSetRGBFillColor(context.CGContext,0,0,1,1);
        CGContextFillRect(context.CGContext,CGRectMake(8,0,8,16));
    }];
    UIImageView *partial=[[UIImageView alloc] initWithImage:mixed];
    for (UIView *view in @[owned,derived,unowned,partial,templateView]) [stack addSubview:view];
    Class lottieClass=objc_allocateClassPair(UIView.class,"Lottie.LottieAnimationView",0); objc_registerClassPair(lottieClass);
    UIView *lottie=[[lottieClass alloc] initWithFrame:CGRectMake(0,30,100,100)]; [stack addSubview:lottie];
    CAShapeLayer *shape=[CAShapeLayer layer]; shape.frame=lottie.bounds; [lottie.layer addSublayer:shape];
    shape.fillColor=SGRAccentColor().CGColor;
    CAKeyframeAnimation *keys=[CAKeyframeAnimation animationWithKeyPath:@"fillColor"];
    keys.values=@[(id)color(0x1ED760).CGColor,(id)color(0xC3B9B9).CGColor,(id)UIColor.blackColor.CGColor];
    keys.duration=100; keys.timeOffset=.25; keys.speed=.75; keys.repeatCount=HUGE_VALF;
    [shape addAnimation:keys forKey:@"lottie.fill"];
    CABasicAnimation *basic=[CABasicAnimation animationWithKeyPath:@"strokeColor"];
    basic.fromValue=(id)SGRAccentColor().CGColor; basic.toValue=(id)UIColor.blackColor.CGColor;
    basic.duration=100; basic.repeatCount=HUGE_VALF; [shape addAnimation:basic forKey:@"lottie.stroke"];
    __block CFTimeInterval origin=0;
    AnimationObserver *observer=[AnimationObserver new]; observer.layer=shape;
    CABasicAnimation *finite=[CABasicAnimation animationWithKeyPath:@"backgroundColor"];
    finite.fromValue=(id)SGRAccentColor().CGColor; finite.toValue=(id)UIColor.blackColor.CGColor;
    finite.duration=.5; finite.timingFunction=[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
    finite.delegate=observer;
    [shape addAnimation:finite forKey:@"delegate"];
    observer.changeColors=^{
        // Core Animation fills an implicit beginTime when it commits, not at addAnimation:.
        origin=[shape animationForKey:@"lottie.fill"].beginTime;
        SGRPlayerSetCoverAccent(color(0xFF00FF));
        SGRPlayerPaintCover(stack);
        SGRPlayerPaintCover(stack); // unchanged repaint must be idempotent, including delegates
        expectRGB(imageRGB(owned.image),follow?0xFF26FF:first,@"complete tint operation follows the cover");
        [button setImage:knownIcon(SGRAccentColor()) forState:UIControlStateSelected];
        button.selected = YES;
        [button layoutSubviews];
        expectRGB(imageRGB(button.imageView.image),follow?0xFF26FF:first,@"new selected-state image follows the cover on layout");
        expect((pixel(derived.image,4)&255)==128,@"derived alpha icon preserves one half opacity");
        expectRGB(imageRGB(unowned.image),first,@"unknown image is left alone");
        checkAnimations(shape,first,origin);
        SGRAccentPublishPageColor(front.view,color(0x00FFFF));
        NSInteger pageB=automatic?0x00FFFF:0xFFFF00;
        dispatch_async(dispatch_get_main_queue(), ^{
            expectRGB(imageRGB(owned.image),follow?0xFF26FF:pageB,@"owned image follows B or override");
            expect((pixel(derived.image,4)&255)==128,@"global refresh does not multiply derived alpha");
            expectRGB(imageRGB(derived.image),follow?0x801380:(automatic?0x008080:0x808000),
                      @"derived alpha icon follows its token, not only its opacity");
            expectRGB(pixel(partial.image,4)>>8,first,@"partially known renderer keeps its accent-colored half");
            expectRGB(pixel(partial.image,12)>>8,0x0000FF,@"CoreGraphics half of mixed renderer stays blue");
            expect(templateView.image.renderingMode==UIImageRenderingModeAlwaysTemplate && [templateView.tintColor isEqual:UIColor.redColor],
                   @"template image keeps its independent rendering intent and view tint");
            checkAnimations(shape,first,origin);
            CABasicAnimation *next=[CABasicAnimation animationWithKeyPath:@"strokeColor"];
            next.fromValue=(id)SGRAccentColor().CGColor; next.toValue=(id)UIColor.blackColor.CGColor; next.duration=100;
            [shape addAnimation:next forKey:@"natural.repaint"];
            CABasicAnimation *installed=(id)[shape animationForKey:@"natural.repaint"];
            expectRGB(rgb([UIColor colorWithCGColor:(__bridge CGColorRef)installed.fromValue]),follow?0xFF26FF:pageB,@"next natural animation gets current tint");
            [NSUserDefaults.standardUserDefaults setVolatileDomain:@{SGRKeyAccentAuto:@NO,SGRKeyPlayerFollowsCover:@(follow),SGRKeyAccent:@0x123456} forName:NSArgumentDomain];
            SGRAccentPreferencesChanged();
            dispatch_async(dispatch_get_main_queue(), ^{
                SGRPlayerSetCoverAccent(UIColor.grayColor);
                expectRGB(imageRGB(owned.image),0x123456,@"grey cover restores current global image tint");
                expect((pixel(derived.image,4)&255)==128,@"restoration preserves derived alpha");
                expectRGB(imageRGB(derived.image),0x091A2B,@"derived icon restores the current picked tint with half alpha");
                expectRGB(rgb([UIColor colorWithCGColor:shape.fillColor]),0x123456,@"grey cover restores current model color");
                checkAnimations(shape,first,origin);
            });
        });
    };
    observer.finished=^{
        [NSUserDefaults.standardUserDefaults setVolatileDomain:@{SGRKeyAccentAuto:@NO,SGRKeyPlayerFollowsCover:@(follow),SGRKeyAccent:@(-1)} forName:NSArgumentDomain];
        SGRAccentPreferencesChanged();
        UIColor *offGreen=[UIColor colorWithRed:30/255.0 green:215/255.0 blue:96/255.0 alpha:1];
        UIImageView *offIcon=[[UIImageView alloc] initWithImage:knownIcon(offGreen)];
        UIImageView *offAlpha=[[UIImageView alloc] initWithImage:knownIcon([offGreen colorWithAlphaComponent:.5])];
        expectRGB(imageRGB(offIcon.image),0x1ED760,@"icon created while stock renders stock green");
        expect((pixel(offAlpha.image,4)&255)==128,@"icon derived while stock preserves half opacity");
        [NSUserDefaults.standardUserDefaults setVolatileDomain:@{SGRKeyAccentAuto:@NO,SGRKeyPlayerFollowsCover:@(follow),SGRKeyAccent:@0xFF0000} forName:NSArgumentDomain];
        SGRAccentPreferencesChanged();
        expectRGB(imageRGB(offIcon.image),0xFF0000,@"icon created while stock follows the restored accent");
        expectRGB(imageRGB(offAlpha.image),0x800000,@"icon derived while stock follows the restored accent at half opacity");
        printf("player accent Automatic=%d Follow=%d: %lu checks passed\n",automatic,follow,(unsigned long)checks);
        exit(0);
    };
}
@interface PlayerScene : UIResponder <UIWindowSceneDelegate>
@property (nonatomic,strong) UIWindow *window;
@end
@implementation PlayerScene
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    self.window=[[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    front=[UIViewController new]; self.window.rootViewController=front; [self.window makeKeyAndVisible];
    dispatch_async(dispatch_get_main_queue(),^{ runChecks(); });
}
@end
@interface PlayerApp : UIResponder <UIApplicationDelegate> @end
@implementation PlayerApp @end
int main(int argc,char **argv) {
    @autoreleasepool {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,120*NSEC_PER_SEC),dispatch_get_main_queue(),^{ HARNESS_FAIL(@"player harness timed out"); });
        return UIApplicationMain(argc,argv,nil,NSStringFromClass(PlayerApp.class));
    }
}
