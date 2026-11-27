// The automix scenario (automix-check.sh): AutoMix's transitions in the redesigned player (Redesigned/Player/PlayerMix.x)
// and the AutoMix page's preview (Shared/AutoMix/AutoMixPreview.m), against the scenario's own facts and Spotify
// settings (stubs-automix.m) and a player whose clock advances only at a scripted position change.
//
//     progress  the bands on the mock of Spotify's slider: known, unknown and inverted windows, none, a seek inside
//               the song, the next song's incoming window after a blend, gone once passed, none after a skip; each
//               band flat at the track's thickness in a faint white, rounded only at the bar's own end; and the
//               phone's three sliders (one shown, two hidden) laid out again and again around a change of facts with
//               no layout loop, no band moved after it went in, no band on a hidden slider, and two shown at once
//               each with its own
//     queue     Playing Next's line over its first row for each kind and its accessibility, its quiet look, a change
//               of facts that reloads no row, another pair, no facts, the option off, and a row's tap still skipping
//     preview   the page's card off (with its gray divider), beat-matched (corners rounded) and crossfade at 1, 5 and
//               12 s, changed outside the page and in Spotify's page while it shows, the rows around it and no
//               setting written by it
//     artwork   the stage over the cover: its start, its edgeless cross-dissolve, its end with the window, every stop
//               and hold-back (the player hidden, faded or off screen, and facts that change under it among them), the
//               cover never left hidden, and no stage kept once the player is gone
//
// Steps wait for a frame or an explicit precondition. The log ends with automix checks n of m right -- PASS or
// FAIL, and the app exits with it.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import "Shared/AutoMix/AutoMix.h"
#import "Shared/AutoMix/AutoMixPreview.h"
#import "Shared/Player/PlayerState.h"
#import "Shared/Lyrics/Lyrics.h"
#import "Redesigned/Player/Player.h"
#import "Redesigned/Player/PlayerQueue.h"
#import "Redesigned/Kit/SGRBridges.h"
#import "Core/SGPrefs.h"
#import "../harness-fail.h"

void SGRHarnessReport(SPTPlayerState *state);
void SGRHarnessSetTransitionEnds(CFTimeInterval ends);
void SGRHarnessServe(NSString *imageURI, UIImage *image);
void SGRHarnessSetTransition(SGTransitionFacts *facts);
void SGRHarnessSetSpotifySettings(SGTransitionSettings settings);
NSUInteger SGRHarnessSettingWrites(void);
NSUInteger SGRHarnessPlayerCommands(void);
extern NSString *const SGPlayerTransitionNotification;

@interface SGTransitionFacts (SGRHarness)
+ (instancetype)sgr_harnessFrom:(NSString *)fromURI to:(NSString *)toURI kind:(SGTransitionKind)kind known:(BOOL)known
                       outStart:(double)outStart outEnd:(double)outEnd inStart:(double)inStart inEnd:(double)inEnd;
@end

#pragma mark - a player on the clock

static CFTimeInterval sg_playbackTime = 1000;
static CFTimeInterval sg_arrivalTime;
CFTimeInterval SGHarnessMediaTime(void) { return sg_arrivalTime ?: CACurrentMediaTime(); }
static CFTimeInterval playbackTime(void) {
    return sg_playbackTime;
}

@interface SGRHarnessLiveState : SPTPlayerState
@property (nonatomic) CFTimeInterval sgr_at;
@end
@implementation SGRHarnessLiveState
- (double)position {
    return self.isPaused ? self.positionAsOfTimestamp : self.positionAsOfTimestamp + (playbackTime() - self.sgr_at) * self.playbackSpeed;
}
@end

static NSString *const kDJ = @"spotify:playlist:37i9dQZF1EYkqdzj48dyYq", *const kPlaylist = @"spotify:playlist:harness";

static NSString *picture(NSString *digits) {
    return [@"spotify:image:ab67616d0000b273" stringByAppendingString:[[digits stringByPaddingToLength:24 withString:@"0" startingAtIndex:0] substringToIndex:24]];
}

static UIImage *solid(UIColor *color) {
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat preferredFormat];
    format.scale = 1;
    return [[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(300, 300) format:format] imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        [color setFill];
        UIRectFill(CGRectMake(0, 0, 300, 300));
    }];
}

static SPTPlayerTrack *song(NSString *uri, NSString *title, NSString *image) {
    SPTPlayerTrack *track = [SPTPlayerTrack new];
    [track setValue:uri forKey:@"URI"];
    [track setValue:title forKey:@"trackTitle"];
    [track setValue:@"Retrine harness" forKey:@"artistName"];
    NSMutableDictionary *metadata = [@{@"title": title} mutableCopy];
    if (image) metadata[@"image_xlarge_url"] = image;
    [track setValue:metadata forKey:@"metadata"];
    return track;
}

// Where the song last reported stands now, by the same clock the live state runs on.
static double sg_reportedAt;
static CFTimeInterval sg_reportedWhen;
static double playing(void) {
    return sg_reportedAt + playbackTime() - sg_reportedWhen;
}

static void report(SPTPlayerTrack *track, double position, double duration, NSArray *future, BOOL paused, NSString *context) {
    SGRHarnessLiveState *state = [SGRHarnessLiveState new];
    state.sgr_at = playbackTime();
    [state setValue:track forKey:@"track"];
    [state setValue:@(position) forKey:@"positionAsOfTimestamp"];
    [state setValue:[NSDate dateWithTimeIntervalSinceReferenceDate:state.sgr_at] forKey:@"timestamp"];
    [state setValue:@1 forKey:@"playbackSpeed"];
    [state setValue:@(paused) forKey:@"isPaused"];
    [state setValue:@YES forKey:@"isPlaying"];
    [state setValue:@(duration) forKey:@"duration"];
    [state setValue:future ?: @[] forKey:@"future"];
    [state setValue:context forKey:@"contextURI"];
    sg_reportedAt = position;
    sg_reportedWhen = state.sgr_at;
    SGRHarnessReport(state);
}

static SGTransitionFacts *facts(NSString *from, NSString *to, SGTransitionKind kind, BOOL known, double outStart, double outEnd, double inStart, double inEnd) {
    return [SGTransitionFacts sgr_harnessFrom:from to:to kind:kind known:known outStart:outStart outEnd:outEnd inStart:inStart inEnd:inEnd];
}

static void setOption(NSString *key, BOOL on) {
    [NSUserDefaults.standardUserDefaults setBool:on forKey:key];
    [NSNotificationCenter.defaultCenter postNotificationName:SGAutoMixPlayerOptionsDidChangeNotification object:nil];
}

#pragma mark - checks and steps

static NSUInteger sg_right, sg_checks;

static void check(NSString *area, NSString *name, BOOL ok, NSString *detail) {
    sg_checks++;
    if (ok) sg_right++;
    NSLog(@"[harness] automix %@ %@: %@ -- %@", area, name, detail, ok ? @"ok" : @"WRONG");
}

static NSMutableArray<NSArray *> *sg_steps;

@interface SGRHarnessFrameStep : NSObject
@property (nonatomic, copy) dispatch_block_t action;
@property (nonatomic) NSUInteger frames;
@property (nonatomic, copy) BOOL (^ready)(void);
@property (nonatomic, copy) NSString *precondition;
@property (nonatomic) CFTimeInterval deadline;
@end
@implementation SGRHarnessFrameStep
- (void)frame:(CADisplayLink *)link {
    // The second callback follows a complete frame regardless of display-link callback order.
    if (++self.frames < 2) return;
    if (self.ready && !self.ready()) {
        if (CACurrentMediaTime() >= self.deadline) {
            [link invalidate];
            HARNESS_FAIL(@"automix precondition timed out: %@", self.precondition);
        }
        return;
    }
    [link invalidate];
    self.action();
}
@end

static void stepOnFrame(dispatch_block_t block) {
    [sg_steps addObject:@[[block copy]]];
}

static void stepUntil(NSString *precondition, BOOL (^ready)(void), dispatch_block_t block) {
    [sg_steps addObject:@[[block copy], [ready copy], precondition]];
}

static void runSteps(void) {
    if (!sg_steps.count) return;
    NSArray *next = sg_steps.firstObject;
    [sg_steps removeObjectAtIndex:0];
    SGRHarnessFrameStep *frame = [SGRHarnessFrameStep new];
    if (next.count == 3) {
        const NSTimeInterval preconditionDeadlineSeconds = 45;
        frame.ready = next[1];
        frame.precondition = next[2];
        frame.deadline = CACurrentMediaTime() + preconditionDeadlineSeconds;
    }
    frame.action = ^{
        ((dispatch_block_t)next[0])();
        runSteps();
    };
    CADisplayLink *link = [CADisplayLink displayLinkWithTarget:frame selector:@selector(frame:)];
    [link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
}

static NSArray<UIView *> *viewsOf(UIView *root, NSString *className) {
    NSMutableArray<UIView *> *found = [NSMutableArray array];
    if ([NSStringFromClass(root.class) isEqualToString:className]) [found addObject:root];
    for (UIView *sub in root.subviews) [found addObjectsFromArray:viewsOf(sub, className)];
    return found;
}

static NSArray<UILabel *> *labelsIn(UIView *root) {
    NSMutableArray<UILabel *> *found = [NSMutableArray array];
    for (UIView *sub in root.subviews) {
        if ([sub isKindOfClass:UILabel.class]) [found addObject:(UILabel *)sub];
        [found addObjectsFromArray:labelsIn(sub)];
    }
    return found;
}

static CAShapeLayer *layerNamed(CALayer *root, NSString *name) {
    if ([root.name isEqualToString:name] && [root isKindOfClass:CAShapeLayer.class]) return (CAShapeLayer *)root;
    for (CALayer *sub in root.sublayers) {
        CAShapeLayer *found = layerNamed(sub, name);
        if (found) return found;
    }
    return nil;
}

static void collectPoint(void *info, const CGPathElement *element) {
    NSMutableArray<NSValue *> *points = (__bridge NSMutableArray<NSValue *> *)info;
    if (element->type == kCGPathElementMoveToPoint || element->type == kCGPathElementAddLineToPoint) {
        [points addObject:[NSValue valueWithCGPoint:element->points[0]]];
    }
}

static NSArray<NSValue *> *pointsOf(CAShapeLayer *layer) {
    NSMutableArray<NSValue *> *points = [NSMutableArray array];
    if (layer.path) CGPathApply(layer.path, (__bridge void *)points, collectPoint);
    return points;
}

// Each element of a path as [kind, end] or, for a curve, ["curve", end, the corner it rounds (its control point)].
static void collectElement(void *info, const CGPathElement *element) {
    NSMutableArray<NSArray *> *elements = (__bridge NSMutableArray<NSArray *> *)info;
    NSValue *(^point)(int) = ^NSValue *(int i) { return [NSValue valueWithCGPoint:element->points[i]]; };
    switch (element->type) {
        case kCGPathElementMoveToPoint: [elements addObject:@[@"move", point(0)]]; break;
        case kCGPathElementAddLineToPoint: [elements addObject:@[@"line", point(0)]]; break;
        case kCGPathElementAddQuadCurveToPoint: [elements addObject:@[@"curve", point(1), point(0)]]; break;
        case kCGPathElementAddCurveToPoint: [elements addObject:@[@"curve", point(2), point(1)]]; break;
        case kCGPathElementCloseSubpath: break;
    }
}

static NSArray<NSArray *> *elementsOf(CAShapeLayer *layer) {
    NSMutableArray<NSArray *> *elements = [NSMutableArray array];
    if (layer.path) CGPathApply(layer.path, (__bridge void *)elements, collectElement);
    return elements;
}

// The incoming curve read from its path, in seconds of the plot (`seconds` turns an x into them). Its corners are
// where it turns: its start, each rounded corner's own corner, and the end of each straight segment not rounded
// into the next. From them: where it starts, where it first reaches the top, its steps straight up (each on a beat
// or not) and its sloped segments. Sharp counts the corners where a straight segment turns square into another.
typedef struct {
    double from, to;
    NSUInteger steps, slopes, sharp;
    BOOL onBeats;
} SGRRise;

static BOOL square(CGPoint a, CGPoint b, CGPoint c) {
    BOOL firstAcross = fabs(b.y - a.y) < 0.01 && fabs(b.x - a.x) >= 0.01, firstUp = fabs(b.x - a.x) < 0.01 && fabs(b.y - a.y) >= 0.01;
    BOOL thenAcross = fabs(c.y - b.y) < 0.01 && fabs(c.x - b.x) >= 0.01, thenUp = fabs(c.x - b.x) < 0.01 && fabs(c.y - b.y) >= 0.01;
    return (firstAcross && thenUp) || (firstUp && thenAcross);
}

static SGRRise riseOf(CAShapeLayer *layer, double (^seconds)(CGFloat)) {
    NSArray<NSArray *> *elements = elementsOf(layer);
    NSMutableArray<NSValue *> *corners = [NSMutableArray array];
    SGRRise rise = {0, -1, 0, 0, 0, YES};
    for (NSUInteger i = 0; i < elements.count; i++) {
        NSArray *element = elements[i], *next = i + 1 < elements.count ? elements[i + 1] : nil;
        if ([element[0] isEqualToString:@"curve"]) [corners addObject:element[2]];
        else if (![next[0] isEqualToString:@"curve"]) [corners addObject:element[1]];
        if ([element[0] isEqualToString:@"line"] && [next[0] isEqualToString:@"line"] && i > 0
            && square([elements[i - 1][1] CGPointValue], [element[1] CGPointValue], [next[1] CGPointValue])) rise.sharp++;
    }
    if (!corners.count) return rise;
    CGFloat top = CGFLOAT_MAX;
    for (NSValue *corner in corners) top = MIN(top, corner.CGPointValue.y);
    rise.from = seconds(corners.firstObject.CGPointValue.x);
    for (NSUInteger i = 0; i < corners.count; i++) {
        CGPoint corner = corners[i].CGPointValue;
        if (rise.to < 0 && corner.y <= top + 0.01) rise.to = seconds(corner.x);
        if (!i) continue;
        CGPoint before = corners[i - 1].CGPointValue;
        BOOL across = fabs(corner.y - before.y) < 0.01, up = fabs(corner.x - before.x) < 0.01 && !across;
        if (up) {
            rise.steps++;
            double at = seconds(corner.x);
            rise.onBeats = rise.onBeats && fabs(at * 2 - round(at * 2)) < 0.01;
        } else if (!across) {
            rise.slopes++;
        }
    }
    return rise;
}

// The red, green and blue at a point of the window as it is drawn.
static void colorAt(UIWindow *window, CGPoint point, CGFloat rgb[3]) {
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat];
    format.scale = 1;
    UIImage *shot = [[[UIGraphicsImageRenderer alloc] initWithSize:window.bounds.size format:format] imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        [window drawViewHierarchyInRect:window.bounds afterScreenUpdates:YES];
    }];
    CGImageRef pixel = CGImageCreateWithImageInRect(shot.CGImage, CGRectMake(point.x, point.y, 1, 1));
    uint8_t px[4] = {0};
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(px, 1, 1, 8, 4, space, (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
    CGContextDrawImage(context, CGRectMake(0, 0, 1, 1), pixel);
    CGContextRelease(context);
    CGColorSpaceRelease(space);
    CGImageRelease(pixel);
    for (int i = 0; i < 3; i++) rgb[i] = px[i] / 255.0;
}

#pragma mark - the app made to report inactive

static BOOL sg_inactive;

static void reportInactiveWhenAsked(void) {
    Method method = class_getInstanceMethod(UIApplication.class, @selector(applicationState));
    UIApplicationState (*original)(id, SEL) = (UIApplicationState (*)(id, SEL))method_getImplementation(method);
    method_setImplementation(method, imp_implementationWithBlock(^UIApplicationState(UIApplication *app) {
        return sg_inactive ? UIApplicationStateInactive : original(app, @selector(applicationState));
    }));
}

extern void SGRHarnessSetReduceMotion(BOOL reduced);

#pragma mark - layouts and band moves, counted

// The layout passes a check asks for, one per slider each, and what more the facts' change, a pair's one insertion
// and main.m's once-a-second layout of the units may add to them.
static const NSUInteger kLayoutPasses = 5, kLayoutSlack = 3;
// A slider laid out this often since its count began is in a loop: the count goes on, but the slider's hook is no
// longer called, so the loop ends and the check can say so instead of the run hanging.
static const NSUInteger kLayoutBreaker = 200;
static NSMapTable<UIView *, NSNumber *> *sg_layouts;  // each progress slider's layoutSubviews since the count began
static NSMapTable<UIView *, NSNumber *> *sg_moves;    // each band's moves to a superview over its life

static NSUInteger countOf(NSMapTable<UIView *, NSNumber *> *table, UIView *view) {
    return [table objectForKey:view].unsignedIntegerValue;
}

static void countLayoutsAndMoves(Class sliderClass) {
    sg_layouts = [NSMapTable weakToStrongObjectsMapTable];
    sg_moves = [NSMapTable weakToStrongObjectsMapTable];
    Method layout = class_getInstanceMethod(sliderClass, @selector(layoutSubviews));
    void (*hooked)(id, SEL) = (void (*)(id, SEL))method_getImplementation(layout);
    void (*plain)(id, SEL) = (void (*)(id, SEL))class_getMethodImplementation(UISlider.class, @selector(layoutSubviews));
    method_setImplementation(layout, imp_implementationWithBlock(^(UIView *me) {
        NSUInteger count = countOf(sg_layouts, me) + 1;
        [sg_layouts setObject:@(count) forKey:me];
        (count > kLayoutBreaker ? plain : hooked)(me, @selector(layoutSubviews));
    }));
    void (*moved)(id, SEL) = (void (*)(id, SEL))class_getMethodImplementation(UIView.class, @selector(didMoveToSuperview));
    class_addMethod(NSClassFromString(@"SGRMixBand"), @selector(didMoveToSuperview), imp_implementationWithBlock(^(UIView *me) {
        [sg_moves setObject:@(countOf(sg_moves, me) + 1) forKey:me];
        moved(me, @selector(didMoveToSuperview));
    }), "v@:");
}

#pragma mark - the scenario

void SGRHarnessRunAutoMix(UIWindow *window, UIViewController *durationUnit, UIView *tilt) {
    sg_steps = [NSMutableArray array];
    reportInactiveWhenAsked();
    Class sliderClass = NSClassFromString(@"_TtCO17NowPlaying_ECMKit11ProgressBar6Slider");
    countLayoutsAndMoves(sliderClass);
    NSString *const P = @"progress", *const Q = @"queue", *const D = @"preview", *const A = @"artwork";

    // The duration unit's slider, as the seek scenario makes it.
    UIView *unit = durationUnit.view;
    CGFloat W = unit.bounds.size.width;
    UISlider *slider = [[sliderClass alloc] initWithFrame:CGRectMake(24, 0, W - 48, 20)];
    slider.accessibilityIdentifier = @"SPTNowPlayingSliderV2";
    // The tree's drawn bar gives way to the slider, which Spotify moves as the song plays (here by hand).
    for (UIView *drawn in unit.subviews) drawn.hidden = YES;
    [unit addSubview:slider];
    [durationUnit viewDidLayoutSubviews];
    // The phone's other two (.mixdog/review-shots/phone-v100/trees/player-sliders-annotated.txt), of the same class and
    // identifier on the same player: the now playing bar's under its hidden bar, and the sticky header's under its
    // hidden stack at the top of the player.
    CGFloat screenWidth = window.bounds.size.width;
    UIView *barHost = [[UIView alloc] initWithFrame:CGRectMake(0, window.bounds.size.height - 147, screenWidth, 64)];
    barHost.hidden = YES;
    UISlider *barSlider = [[sliderClass alloc] initWithFrame:CGRectMake(6, 48, screenWidth - 12, 14)];
    barSlider.accessibilityIdentifier = @"SPTNowPlayingSliderV2";
    [barHost addSubview:barSlider];
    [window addSubview:barHost];
    UIView *stickyHost = [[UIView alloc] initWithFrame:CGRectMake(0, 47, screenWidth, 70)];
    stickyHost.hidden = YES;
    UISlider *stickySlider = [[sliderClass alloc] initWithFrame:CGRectMake(-2, 56, screenWidth + 4, 14)];
    stickySlider.accessibilityIdentifier = @"SPTNowPlayingSliderV2";
    [stickyHost addSubview:stickySlider];
    [window.rootViewController.view addSubview:stickyHost];
    NSArray<UISlider *> *sliders = @[slider, barSlider, stickySlider];

    SPTPlayerTrack *a = song(@"spotify:track:mixA", @"Loose Canon", picture(@"a1a1")), *b = song(@"spotify:track:mixB", @"Low Tide", picture(@"b2b2"));
    SPTPlayerTrack *c = song(@"spotify:track:mixC", @"Third Song", picture(@"c3c3")), *x = song(@"spotify:track:mixX", @"Someone Else", nil);
    SGRHarnessServe(picture(@"a1a1"), solid(UIColor.redColor));
    SGRHarnessServe(picture(@"b2b2"), solid(UIColor.greenColor));
    SGRHarnessServe(picture(@"c3c3"), solid(UIColor.blueColor));
    SGRHarnessSetSpotifySettings((SGTransitionSettings){NO, YES, 5000});

    NSArray<UIView *> *(^bands)(void) = ^NSArray<UIView *> *{
        NSMutableArray<UIView *> *shown = [NSMutableArray array];
        for (UIView *band in viewsOf(slider, @"SGRMixBand")) if (!band.hidden) [shown addObject:band];
        return shown;
    };
    void (^layOut)(void) = ^{
        [slider setNeedsLayout];
        [slider layoutIfNeeded];
    };
    CGFloat (^knobAt)(double) = ^CGFloat(double share) {
        CGRect bounds = slider.bounds;
        return CGRectGetMidX([slider thumbRectForBounds:bounds trackRect:[slider trackRectForBounds:bounds] value:(float)share]);
    };
    CGRect (^track)(void) = ^CGRect { return [slider trackRectForBounds:slider.bounds]; };
    NSString *(^frames)(void) = ^NSString *{
        NSMutableArray *list = [NSMutableArray array];
        for (UIView *band in bands()) [list addObject:NSStringFromCGRect(band.frame)];
        return list.count ? [list componentsJoinedByString:@", "] : @"none";
    };
    // The band's look: the track's own thickness, a faint white, and rounded only at the end `caps` names (0 none,
    // -1 the bar's start, 1 the bar's end), as round as the bar's cap.
    BOOL (^flat)(UIView *, NSInteger) = ^BOOL(UIView *band, NSInteger caps) {
        CGFloat white = 0, alpha = 0;
        [band.backgroundColor getWhite:&white alpha:&alpha];
        CACornerMask start = kCALayerMinXMinYCorner | kCALayerMinXMaxYCorner, end = kCALayerMaxXMinYCorner | kCALayerMaxXMaxYCorner;
        CACornerMask mask = caps < 0 ? start : caps > 0 ? end : 0;
        CGFloat radius = caps ? track().size.height / 2 : 0;
        BOOL rounded = caps ? band.layer.maskedCorners == mask && fabs(band.layer.cornerRadius - radius) < 0.01 : band.layer.cornerRadius == 0;
        return fabs(band.frame.size.height - track().size.height) < 0.01 && fabs(CGRectGetMinY(band.frame) - CGRectGetMinY(track())) < 0.01
            && white == 1 && alpha >= 0.18 && alpha <= 0.22 && rounded;
    };
    NSString *(^bandLook)(UIView *) = ^NSString *(UIView *band) {
        CGFloat white = 0, alpha = 0;
        [band.backgroundColor getWhite:&white alpha:&alpha];
        return [NSString stringWithFormat:@"height %.1f on a %.1f track, white %.2f alpha %.2f, corners %lu radius %.1f", band.frame.size.height,
                track().size.height, white, alpha, (unsigned long)band.layer.maskedCorners, band.layer.cornerRadius];
    };

    #pragma mark progress

    // The facts measured on the phone for a Crossfade of 5 s: [177.609, 182.609] -> [0, 5].
    SGTransitionFacts *measured = facts(@"spotify:track:mixA", @"spotify:track:mixB", SGTransitionKindCrossfade, YES, 177.609, 182.609, 0, 5);
    stepOnFrame(^{
        report(a, 60, 182.609, @[b, c], NO, kPlaylist);
        slider.value = 60 / 182.609;
        SGRHarnessSetTransition(measured);
        layOut();
        check(P, @"option off", bands().count == 0, [NSString stringWithFormat:@"the options at their standard: bands %@", frames()]);
        for (NSString *key in @[SGKeyAutoMixShowProgress, SGKeyAutoMixShowQueue, SGKeyAutoMixArtwork]) setOption(key, YES);
    });
    __block CGRect knownFrame;
    stepOnFrame(^{
        layOut();
        NSArray<UIView *> *shown = bands();
        UIView *band = shown.firstObject;
        CGFloat start = knobAt(177.609 / 182.609), end = CGRectGetMaxX(track());
        NSUInteger index = band ? [slider.subviews indexOfObject:band] : NSNotFound;
        BOOL behind = index != NSNotFound;
        for (NSUInteger i = 0; behind && i < index; i++) behind = [NSStringFromClass(slider.subviews[i].class) isEqualToString:@"SGRMixBand"];
        knownFrame = band.frame;
        check(P, @"a known window", shown.count == 1 && fabs(CGRectGetMinX(band.frame) - start) < 0.5 && fabs(CGRectGetMaxX(band.frame) - end) < 0.5
              && behind,
              [NSString stringWithFormat:@"%@, from the knob at 177.609 s (%.1f) to the bar's end (%.1f), behind every part of the slider %d", frames(), start, end, behind]);
        check(P, @"a flat, faint segment capped at the bar's end", band && flat(band, 1), bandLook(band));
    });
    stepOnFrame(^{
        report(a, 150, 182.609, @[b, c], NO, kPlaylist);
        slider.value = 150 / 182.609;
        layOut();
        check(P, @"a seek inside the song", bands().count == 1 && CGRectEqualToRect(bands().firstObject.frame, knownFrame),
              [NSString stringWithFormat:@"after a seek to 150 s: %@", frames()]);
        SGRHarnessSetTransition(facts(@"spotify:track:mixA", @"spotify:track:mixB", SGTransitionKindCrossfade, YES, 170, 175, 0, 5));
        layOut();
        check(P, @"a window short of the end is square at both ends", bands().count == 1 && flat(bands().firstObject, 0), bandLook(bands().firstObject));
        SGRHarnessSetTransition(facts(@"spotify:track:mixA", @"spotify:track:mixB", SGTransitionKindSpotifyAutomix, NO, 100, 110, 0, 5));
        layOut();
        check(P, @"unknown times draw nothing", bands().count == 0, [NSString stringWithFormat:@"Spotify AutoMix with timesKnown NO (times 100 to 110 left in): %@", frames()]);
        SGRHarnessSetTransition(facts(@"spotify:track:mixA", @"spotify:track:mixB", SGTransitionKindCrossfade, YES, 182, 177, 0, 5));
        layOut();
        check(P, @"an inverted window draws nothing", bands().count == 0, [NSString stringWithFormat:@"182 to 177 s: %@", frames()]);
        SGRHarnessSetTransition(nil);
        layOut();
        check(P, @"no facts draw nothing", bands().count == 0, frames());
    });
    stepOnFrame(^{
        // The blend: the song plays into its window, then the next one comes and the facts move on to it.
        report(a, 180, 182.609, @[b, c], NO, kPlaylist);
        SGRHarnessSetTransition(measured);
        report(b, 0.3, 200, @[c], NO, kPlaylist);
        SGRHarnessSetTransition(nil);
        layOut();
        UIView *band = bands().firstObject;
        CGFloat start = CGRectGetMinX(track()), end = knobAt(5.0 / 200);
        check(P, @"the next song's incoming window", bands().count == 1 && fabs(CGRectGetMinX(band.frame) - start) < 0.5 && fabs(CGRectGetMaxX(band.frame) - end) < 0.5
              && flat(band, -1), [NSString stringWithFormat:@"%@, from the bar's start (%.1f) to the knob at 5 s (%.1f); %@", frames(), start, end, bandLook(band)]);
        report(b, 7, 200, @[c], NO, kPlaylist);
        layOut();
        check(P, @"gone once playback passes it", bands().count == 0, [NSString stringWithFormat:@"at 7 s: %@", frames()]);
        // A skip to the next song in the middle of the first is no blend.
        report(a, 60, 182.609, @[b, c], NO, kPlaylist);
        SGRHarnessSetTransition(measured);
        report(b, 0.3, 200, @[c], NO, kPlaylist);
        SGRHarnessSetTransition(nil);
        layOut();
        check(P, @"a skip shows no incoming window", bands().count == 0, [NSString stringWithFormat:@"skipped at 60 s: %@", frames()]);
    });
    // The phone's hang: the three sliders, one shown, laid out again and again around a change of facts with known
    // times, then left to the run loop for half a second. Each slider is laid out only for the passes asked and what
    // the change adds, each band goes into its slider once and stays there, and only a shown slider has bands.
    NSArray<UIView *> *(^bandsIn)(UISlider *, BOOL) = ^NSArray<UIView *> *(UISlider *owner, BOOL shownOnly) {
        NSMutableArray<UIView *> *found = [NSMutableArray array];
        for (UIView *band in viewsOf(owner, @"SGRMixBand")) if (!shownOnly || !band.hidden) [found addObject:band];
        return found;
    };
    void (^passes)(void) = ^{
        for (NSUInteger i = 0; i < kLayoutPasses; i++) {
            for (UISlider *each in sliders) {
                [each setNeedsLayout];
                [each layoutIfNeeded];
            }
        }
    };
    BOOL (^settled)(void) = ^BOOL {
        for (UISlider *each in sliders) if (countOf(sg_layouts, each) > kLayoutPasses + kLayoutSlack) return NO;
        for (UIView *band in sg_moves.keyEnumerator) if (countOf(sg_moves, band) > 1) return NO;
        return YES;
    };
    NSString *(^layoutsSaid)(void) = ^NSString *{
        NSMutableArray<NSString *> *moves = [NSMutableArray array];
        for (UIView *band in sg_moves.keyEnumerator) [moves addObject:@(countOf(sg_moves, band)).stringValue];
        return [NSString stringWithFormat:@"layouts: player %lu, bar %lu, sticky %lu (at most %lu each); band moves %@ (at most 1 each)",
                (unsigned long)countOf(sg_layouts, slider), (unsigned long)countOf(sg_layouts, barSlider), (unsigned long)countOf(sg_layouts, stickySlider),
                (unsigned long)(kLayoutPasses + kLayoutSlack), [moves componentsJoinedByString:@" "]];
    };
    // A band of `owner`'s over the outgoing window of `measured`, placed by that slider's own bounds.
    BOOL (^ownWindow)(UISlider *) = ^BOOL(UISlider *owner) {
        NSArray<UIView *> *shown = bandsIn(owner, YES);
        CGRect bounds = owner.bounds, bar = [owner trackRectForBounds:bounds];
        CGFloat start = CGRectGetMidX([owner thumbRectForBounds:bounds trackRect:bar value:(float)(177.609 / 182.609)]);
        return shown.count == 1 && shown.firstObject.superview == owner && fabs(CGRectGetMinX(shown.firstObject.frame) - start) < 0.5
            && fabs(CGRectGetMaxX(shown.firstObject.frame) - CGRectGetMaxX(bar)) < 0.5;
    };
    stepOnFrame(^{
        [sg_layouts removeAllObjects];
        report(a, 60, 182.609, @[b, c], NO, kPlaylist);
        SGRHarnessSetTransition(measured);
        passes();
    });
    // Allow more unsolicited layout passes than the slack before judging a loop.
    for (NSUInteger i = 0; i <= kLayoutSlack; ++i) stepOnFrame(^{});
    stepOnFrame(^{
        check(P, @"three sliders, one shown: layout settles", settled(), layoutsSaid());
        check(P, @"hidden sliders do nothing", ownWindow(slider) && bandsIn(barSlider, NO).count == 0 && bandsIn(stickySlider, NO).count == 0,
              [NSString stringWithFormat:@"player %@; bands made in the bar's %lu, the sticky header's %lu", frames(),
               (unsigned long)bandsIn(barSlider, NO).count, (unsigned long)bandsIn(stickySlider, NO).count]);
    });
    // The sticky header shown while the player's slider stays in place: two sliders shown at once, each with its own.
    stepOnFrame(^{
        [sg_layouts removeAllObjects];
        stickyHost.hidden = NO;
        SGRHarnessSetTransition(facts(@"spotify:track:mixA", @"spotify:track:mixB", SGTransitionKindCrossfade, YES, 177.609, 182.609, 0, 5));
        passes();
    });
    for (NSUInteger i = 0; i <= kLayoutSlack; ++i) stepOnFrame(^{});
    stepOnFrame(^{
        check(P, @"two sliders shown: each its own bands, layout settles", settled() && ownWindow(slider) && ownWindow(stickySlider),
              [NSString stringWithFormat:@"%@; the player's %@, the sticky header's %@", layoutsSaid(), frames(),
               bandsIn(stickySlider, YES).count ? NSStringFromCGRect(bandsIn(stickySlider, YES).firstObject.frame) : @"none"]);
    });
    stepOnFrame(^{
        stickyHost.hidden = YES;
        [stickySlider setNeedsLayout];
        SGRHarnessSetTransition(nil);
    });

    #pragma mark queue

    __block UITableViewController *queue;
    UIView *(^blendLine)(void) = ^UIView *{
        UIView *header = [queue tableView:queue.tableView viewForHeaderInSection:2];
        UIView *line = viewsOf(header, @"SGRQueueBlendView").firstObject;
        return line.hidden ? nil : line;
    };
    NSString *(^blendText)(void) = ^NSString *{ return labelsIn(blendLine()).firstObject.text; };
    stepOnFrame(^{
        SGRHarnessSetSpotifySettings((SGTransitionSettings){NO, YES, 6000});
        report(a, 60, 182.609, @[b, c], NO, kPlaylist);
        SGRHarnessSetTransition(facts(@"spotify:track:mixA", @"spotify:track:mixB", SGTransitionKindCrossfade, YES, 176.609, 182.609, 0, 6));
        [SGPlayerState() setValue:@[x] forKey:@"reverse"];
        SGRPlayerShowQueue(tilt);
    });
    stepUntil(@"Up Next sheet presented", ^BOOL {
        UIViewController *sheet = window.rootViewController.presentedViewController;
        return sheet.view.window && !sheet.transitionCoordinator;
    }, ^{
        UINavigationController *sheet = (UINavigationController *)window.rootViewController.presentedViewController;
        queue = [sheet isKindOfClass:UINavigationController.class] ? (UITableViewController *)sheet.topViewController : nil;
        UIView *line = blendLine();
        UIView *upNextHeader = [queue tableView:queue.tableView viewForHeaderInSection:2];
        check(Q, @"transition belongs to Up Next after History and current",
              [queue.tableView numberOfRowsInSection:0] == 1 &&
              [line isDescendantOfView:upNextHeader] &&
              !queue.tableView.tableHeaderView &&
              CGRectGetMinY([upNextHeader convertRect:upNextHeader.bounds toView:queue.tableView]) >= CGRectGetMaxY([queue.tableView rectForSection:1]),
              @"History, Now Playing, then Up Next with its transition");
        BOOL glyph = NO;
        for (UIView *view in viewsOf(line, @"UIImageView")) glyph = glyph || ((UIImageView *)view).image.isSymbolImage;
        check(Q, @"Crossfade with its length", [blendText() isEqualToString:@"Crossfade, 6 s"] && [line.accessibilityLabel isEqualToString:@"Crossfade, 6 s"]
              && line.isAccessibilityElement && glyph,
              [NSString stringWithFormat:@"line \"%@\", read out \"%@\", glyph %d", blendText(), line.accessibilityLabel, glyph]);
        // A quiet note, not a control: the secondary label's white (65 %, 80 % with Increase Contrast) for both the
        // glyph and the text, at the footnote size in the regular weight.
        UILabel *text = labelsIn(line).firstObject;
        UIImageView *mark = (UIImageView *)viewsOf(line, @"UIImageView").firstObject;
        CGFloat textWhite = 0, textAlpha = 0, markWhite = 0, markAlpha = 0;
        BOOL grey = [text.textColor getWhite:&textWhite alpha:&textAlpha] && [mark.tintColor getWhite:&markWhite alpha:&markAlpha];
        double weight = [[text.font.fontDescriptor objectForKey:UIFontDescriptorTraitsAttribute][UIFontWeightTrait] doubleValue];
        CGFloat footnote = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote].pointSize;
        check(Q, @"a quiet line", grey && textWhite == 1 && markWhite == 1 && textAlpha == markAlpha && (fabs(textAlpha - 0.65) < 0.001 || fabs(textAlpha - 0.8) < 0.001)
              && text.font.pointSize == footnote && fabs(weight - UIFontWeightRegular) < 0.01,
              [NSString stringWithFormat:@"text %@, glyph %@, %.1f pt (footnote %.1f) weight %.2f", text.textColor, mark.tintColor, text.font.pointSize, footnote, weight]);
        check(Q, @"the rows are the songs", [queue.tableView numberOfRowsInSection:2] == 2,
              [NSString stringWithFormat:@"%ld rows under the line", (long)[queue.tableView numberOfRowsInSection:2]]);
    });
    stepOnFrame(^{
        SGRHarnessSetTransition(facts(@"spotify:track:mixA", @"spotify:track:mixB", SGTransitionKindSpotifyAutomix, NO, 0, 0, 0, 0));
        [queue.view layoutIfNeeded];
        check(Q, @"Spotify AutoMix updates Up Next annotation", [blendText() isEqualToString:@"Spotify AutoMix"] && [blendLine().accessibilityLabel isEqualToString:@"Spotify AutoMix"],
              [NSString stringWithFormat:@"line \"%@\"", blendText()]);
        SGRHarnessSetTransition(facts(@"spotify:track:mixA", @"spotify:track:mixC", SGTransitionKindCrossfade, YES, 176.609, 182.609, 0, 6));
        check(Q, @"facts for another pair", blendLine() == nil, [NSString stringWithFormat:@"facts into the second row: line %@", blendText() ?: @"none"]);
        SGRHarnessSetTransition(nil);
        check(Q, @"no facts", blendLine() == nil, [NSString stringWithFormat:@"line %@", blendText() ?: @"none"]);
        SGRHarnessSetTransition(facts(@"spotify:track:mixA", @"spotify:track:mixB", SGTransitionKindCrossfade, YES, 176.609, 182.609, 0, 6));
        setOption(SGKeyAutoMixShowQueue, NO);
        check(Q, @"option off", blendLine() == nil, [NSString stringWithFormat:@"line %@", blendText() ?: @"none"]);
        setOption(SGKeyAutoMixShowQueue, YES);
        check(Q, @"option on again", [blendText() isEqualToString:@"Crossfade, 6 s"], [NSString stringWithFormat:@"line \"%@\"", blendText()]);
        NSUInteger commands = SGRHarnessPlayerCommands();
        [queue tableView:queue.tableView didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:2]];
        check(Q, @"a row still skips to its song", SGRHarnessPlayerCommands() == commands + 1,
              [NSString stringWithFormat:@"%lu commands for the tap", (unsigned long)(SGRHarnessPlayerCommands() - commands)]);
        [window.rootViewController dismissViewControllerAnimated:NO completion:nil];
    });

    #pragma mark preview

    __block UITableViewController *page;
    __block UIView *preview;
    UIView *(^findPreview)(void) = ^UIView *{ return viewsOf(page.tableView, @"SGAutoMixPreview").firstObject; };
    NSString *(^said)(void) = ^NSString *{
        NSArray<UILabel *> *labels = labelsIn(preview);
        return [NSString stringWithFormat:@"\"%@\" / \"%@\", read out \"%@\"", labels.firstObject.text, labels.count > 1 ? labels[1].text : nil, preview.accessibilityLabel];
    };
    BOOL (^says)(NSString *, NSString *) = ^BOOL(NSString *title, NSString *subtitle) {
        NSArray<UILabel *> *labels = labelsIn(preview);
        return labels.count >= 2 && [labels[0].text isEqualToString:title] && [labels[1].text isEqualToString:subtitle]
            && [preview.accessibilityLabel isEqualToString:[NSString stringWithFormat:@"AutoMix, %@, %@", title, subtitle]];
    };
    // The plot's seconds at x, over the 16 s the card spans.
    double (^seconds)(CGFloat) = ^double(CGFloat x) {
        return x / layerNamed(preview.layer, @"incoming").superlayer.bounds.size.width * 16;
    };
    SGRRise (^rise)(void) = ^SGRRise { return riseOf(layerNamed(preview.layer, @"incoming"), seconds); };
    NSString *(^riseSaid)(SGRRise) = ^NSString *(SGRRise r) {
        return [NSString stringWithFormat:@"rises %.2f to %.2f s, %lu steps (on beats %d), %lu slopes, %lu sharp corners", r.from, r.to,
                (unsigned long)r.steps, r.onBeats, (unsigned long)r.slopes, (unsigned long)r.sharp];
    };
    // The divider in the middle: its x in seconds, and whether its line runs the plot's height in a neutral gray.
    NSString *(^dividerSaid)(void) = ^NSString *{
        CAShapeLayer *divider = layerNamed(preview.layer, @"divider");
        NSArray<NSValue *> *points = pointsOf(divider);
        const CGFloat *rgba = CGColorGetComponents(divider.strokeColor);
        return [NSString stringWithFormat:@"divider %@ in %@", points.count ? [NSString stringWithFormat:@"at %.2f s, %.0f to %.0f pt",
                seconds(points.firstObject.CGPointValue.x), points.firstObject.CGPointValue.y, points.lastObject.CGPointValue.y] : @"none",
                CGColorGetNumberOfComponents(divider.strokeColor) == 4 ? [NSString stringWithFormat:@"%.2f %.2f %.2f", rgba[0], rgba[1], rgba[2]] : @"?"];
    };
    BOOL (^greyDividerAt8)(void) = ^BOOL {
        CAShapeLayer *divider = layerNamed(preview.layer, @"divider");
        NSArray<NSValue *> *points = pointsOf(divider);
        if (points.count != 2 || CGColorGetNumberOfComponents(divider.strokeColor) != 4) return NO;
        const CGFloat *rgba = CGColorGetComponents(divider.strokeColor);
        CGFloat high = MAX(rgba[0], MAX(rgba[1], rgba[2])), low = MIN(rgba[0], MIN(rgba[1], rgba[2]));
        CGPoint a = points[0].CGPointValue, b = points[1].CGPointValue;
        return fabs(seconds(a.x) - 8) < 0.01 && fabs(seconds(b.x) - 8) < 0.01 && fabs(a.y - b.y) >= divider.superlayer.bounds.size.height - 0.01
            && high - low < 0.06;
    };
    NSArray<NSString *> *(^rowTitles)(NSInteger) = ^NSArray<NSString *> *(NSInteger section) {
        NSMutableArray<NSString *> *titles = [NSMutableArray array];
        UITableView *table = page.tableView;
        for (NSInteger row = 0; row < [table numberOfRowsInSection:section]; row++) {
            UITableViewCell *cell = [table cellForRowAtIndexPath:[NSIndexPath indexPathForRow:row inSection:section]];
            [titles addObject:labelsIn(cell).firstObject.text ?: @"?"];
        }
        return titles;
    };
    __block NSUInteger writes;
    stepUntil(@"queue sheet dismissed", ^BOOL { return !window.rootViewController.presentedViewController; }, ^{
        [window.rootViewController dismissViewControllerAnimated:NO completion:nil];
        UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:SGAutoMixSettingsPage()];
        navigation.modalPresentationStyle = UIModalPresentationFullScreen;
        navigation.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
        page = (UITableViewController *)navigation.topViewController;
        [window.rootViewController presentViewController:navigation animated:NO completion:nil];
    });
    stepUntil(@"preview card visible", ^BOOL { return findPreview().window != nil; }, ^{
        preview = findPreview();
        SGRRise r = rise();
        check(D, @"off", says(@"Every song plays to its end", @"AutoMix is off") && r.from == 8 && r.to == 8 && r.steps == 0,
              [NSString stringWithFormat:@"%@, the incoming curve %@", said(), riseSaid(r)]);
        check(D, @"off: a gray divider in the middle", greyDividerAt8(), dividerSaid());
        check(D, @"the rows around it, off", [rowTitles(0) isEqualToArray:@[@"AutoMix", @"Style", @"Blend length"]] && rowTitles(1).count == 0,
              [NSString stringWithFormat:@"%@ then %@", rowTitles(0), rowTitles(1)]);
        writes = SGRHarnessSettingWrites();
    });
    stepOnFrame(^{
        // The page's own switch, flipped.
        SGRHarnessSetSpotifySettings((SGTransitionSettings){YES, YES, 5000});
        UISwitch *toggle = (UISwitch *)viewsOf([page.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]], @"UISwitch").firstObject
            ?: (UISwitch *)viewsOf([page.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]], @"SGGlowSwitch").firstObject;
        toggle.on = YES;
        [toggle sendActionsForControlEvents:UIControlEventValueChanged];
        check(D, @"the switch still applies AutoMix", SGFlag(SGKeyAutoMix, NO) && SGRHarnessSettingWrites() == writes + 1,
              [NSString stringWithFormat:@"stored %d, %lu writes", SGFlag(SGKeyAutoMix, NO), (unsigned long)(SGRHarnessSettingWrites() - writes)]);
        writes = SGRHarnessSettingWrites();
    });
    stepUntil(@"beat-matched preview", ^BOOL { return says(@"Beat-matched mix", @"5 s blend, on the beat"); }, ^{
        SGRRise r = rise();
        check(D, @"beat-matched, on the beats", says(@"Beat-matched mix", @"5 s blend, on the beat") && fabs(r.from - 5.5) < 0.01 && fabs(r.to - 10.5) < 0.01
              && r.onBeats && r.steps == 10 && r.slopes == 0, [NSString stringWithFormat:@"%@, %@", said(), riseSaid(r)]);
        check(D, @"beat-matched: every corner rounded", r.sharp == 0 && pointsOf(layerNamed(preview.layer, @"divider")).count == 0,
              [NSString stringWithFormat:@"%@, %@", riseSaid(r), dividerSaid()]);
        check(D, @"the rows around it, on", [rowTitles(1) isEqualToArray:@[@"Transitions in the progress bar", @"Transitions in the queue", @"Artwork moves with the mix"]],
              [NSString stringWithFormat:@"%@ then %@", rowTitles(0), rowTitles(1)]);
    });
    for (NSNumber *length in @[@1, @12, @5]) {
        // Away to another page, the settings changed there as Spotify's Playback page would, and back.
        stepOnFrame(^{
            [page.navigationController pushViewController:[UIViewController new] animated:NO];
            SGRHarnessSetSpotifySettings((SGTransitionSettings){NO, YES, length.integerValue * 1000});
        });
        stepOnFrame(^{ [page.navigationController popViewControllerAnimated:NO]; });
        stepUntil(@"crossfade preview after returning", ^BOOL {
            return says([NSString stringWithFormat:@"%@ s crossfade", length], @"A plain fade, the same length both ways");
        }, ^{
            double half = length.doubleValue / 2;
            SGRRise r = rise();
            NSArray<NSValue *> *falling = pointsOf(layerNamed(preview.layer, @"outgoing"));
            double fallFrom = falling.count >= 2 ? seconds(falling[falling.count - 2].CGPointValue.x) : -1, fallTo = seconds(falling.lastObject.CGPointValue.x);
            NSString *title = [NSString stringWithFormat:@"%ld s crossfade", (long)length.integerValue];
            check(D, [NSString stringWithFormat:@"crossfade %@ s, changed in Spotify's settings", length],
                  says(title, @"A plain fade, the same length both ways") && fabs(r.from - (8 - half)) < 0.01 && fabs(r.to - (8 + half)) < 0.01
                  && r.slopes == 1 && r.steps == 0 && fabs(fallFrom - r.from) < 0.01 && fabs(fallTo - r.to) < 0.01,
                  [NSString stringWithFormat:@"%@, %@, falls %.2f to %.2f s", said(), riseSaid(r), fallFrom, fallTo]);
        });
    }
    // Spotify's Playback page while the page shows, with facts that do not change (Spotify's AutoMix, times unknown):
    // the settings' own change reaches the card.
    stepOnFrame(^{
        SGRHarnessSetTransition(facts(@"spotify:track:mixA", @"spotify:track:mixB", SGTransitionKindSpotifyAutomix, NO, 0, 0, 0, 0));
        SGRHarnessSetSpotifySettings((SGTransitionSettings){NO, YES, 9000});
    });
    stepUntil(@"blend length notification", ^BOOL { return says(@"9 s crossfade", @"A plain fade, the same length both ways"); }, ^{
        check(D, @"Blend length changed in Spotify's page while the page shows", says(@"9 s crossfade", @"A plain fade, the same length both ways"), said());
        SGRHarnessSetSpotifySettings((SGTransitionSettings){YES, YES, 5000});
    });
    stepUntil(@"beat-matched settings notification", ^BOOL { return says(@"Beat-matched mix", @"5 s blend, on the beat"); }, ^{
        check(D, @"changed while the page shows", says(@"Beat-matched mix", @"5 s blend, on the beat"), said());
        check(D, @"the card writes no setting", SGRHarnessSettingWrites() == writes,
              [NSString stringWithFormat:@"%lu writes while the card was read again", (unsigned long)(SGRHarnessSettingWrites() - writes)]);
        // The page's switch off again.
        UITableViewCell *first = [page.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];
        UISwitch *toggle = (UISwitch *)(viewsOf(first, @"UISwitch").firstObject ?: viewsOf(first, @"SGGlowSwitch").firstObject);
        toggle.on = NO;
        [toggle sendActionsForControlEvents:UIControlEventValueChanged];
    });
    stepUntil(@"preview switched off", ^BOOL { return says(@"Every song plays to its end", @"AutoMix is off"); }, ^{
        check(D, @"off again from the switch", says(@"Every song plays to its end", @"AutoMix is off") && rowTitles(1).count == 0,
              [NSString stringWithFormat:@"%@, the player's rows %@", said(), rowTitles(1)]);
    });
    stepOnFrame(^{
        [window.rootViewController dismissViewControllerAnimated:NO completion:nil];
        SGRHarnessSetTransition(nil);
    });

    #pragma mark artwork

    __block UIView *cover;
    __block __weak UIView *weakStage;
    __block BOOL wasOn;
    UIView *(^stage)(void) = ^UIView *{ return viewsOf(tilt, @"SGRMixStageView").firstObject; };
    BOOL (^coverBack)(void) = ^BOOL { return stage() == nil && cover.alpha == 1; };
    NSString *(^coverState)(void) = ^NSString *{
        UIView *on = stage();
        return [NSString stringWithFormat:@"stage %@, cover alpha %.2f", on ? [NSString stringWithFormat:@"on (outgoing %.2f, incoming %.2f)",
                on.subviews.firstObject.alpha, on.subviews.lastObject.alpha] : @"none", cover.alpha];
    };
    // A long blend, 14 to 20 s of A (20 s long) into the first 6 s of B, for the run from start to end; a short one, 14 to
    // 16 s of A (16 s long) into the first 2 s of B, for the stops and holds. Each new object is a new blend to plan.
    SGTransitionFacts *(^longBlend)(void) = ^SGTransitionFacts *{
        return facts(@"spotify:track:mixA", @"spotify:track:mixB", SGTransitionKindCrossfade, YES, 14, 20, 0, 6);
    };
    SGTransitionFacts *(^blend)(void) = ^SGTransitionFacts *{
        return facts(@"spotify:track:mixA", @"spotify:track:mixB", SGTransitionKindCrossfade, YES, 14, 16, 0, 2);
    };
    void (^playA)(double, double) = ^(double at, double length) { report(a, at, length, @[b, c], NO, kPlaylist); };
    stepUntil(@"player cover after preview dismissal", ^BOOL { return !window.rootViewController.presentedViewController && SGRPlayerShowingCover().window; }, ^{
        cover = SGRPlayerShowingCover();
        setOption(SGKeyAutoMixArtwork, NO);
        playA(14.2, 16);
        SGRHarnessSetTransition(blend());
    });
    stepOnFrame(^{
        check(A, @"held back: the option off", cover && coverBack(), coverState());
        playA(13, 20);
        SGRHarnessSetTransition(longBlend());
        setOption(SGKeyAutoMixArtwork, YES);
    });
    stepOnFrame(^{ sg_playbackTime += 14.6 - playing(); });
    stepUntil(@"stage at 14.6 s", ^BOOL { return stage() != nil; }, ^{
        UIView *on = stage();
        weakStage = on;
        CGFloat out = on.subviews.firstObject.alpha, in = on.subviews.lastObject.alpha;
        UIView *plate = viewsOf(tilt, @"SGRShadowPlate").firstObject;
        BOOL placed = fabs(CGRectGetMidX(on.frame) - CGRectGetMidX(cover.frame)) < 0.5 && fabs(on.frame.size.width - cover.frame.size.width) < 0.5;
        check(A, @"starts with the outgoing window", on && cover.alpha == 0 && plate.alpha == 1 && in > 0 && in < 0.5 && out > 0.5 && out < 1 && placed,
              [NSString stringWithFormat:@"at %.2f s: %@, its shadow %.2f, over the cover %d", playing(), coverState(), plate.alpha, placed]);
    });
    stepOnFrame(^{ sg_playbackTime += 16.7 - playing(); });
    stepOnFrame(^{
        // A cross-dissolve with no edge: both covers whole over the stage's full bounds, untransformed, their alphas
        // adding up to one, and the stage clipping them to the cover's rounded shape only.
        UIView *on = stage();
        UIView *out = on.subviews.firstObject, *in = on.subviews.lastObject;
        BOOL whole = on.subviews.count == 2;
        for (UIView *view in on.subviews) {
            whole = whole && CGRectEqualToRect(view.frame, on.bounds) && CGAffineTransformIsIdentity(view.transform);
        }
        BOOL clipped = on.clipsToBounds && on.layer.cornerRadius > 0 && on.layer.cornerRadius == cover.layer.cornerRadius;
        check(A, @"a cross-dissolve with no edge", on && whole && clipped && out.alpha > 0.2 && in.alpha > 0.2 && fabs(out.alpha + in.alpha - 1) < 0.001,
              [NSString stringWithFormat:@"at %.2f s: %@; covers %@ and %@ in %@, transforms identity %d %d, clipped %d at radius %.1f (the cover's %.1f)",
               playing(), coverState(), NSStringFromCGRect(out.frame), NSStringFromCGRect(in.frame), NSStringFromCGRect(on.bounds),
               CGAffineTransformIsIdentity(out.transform), CGAffineTransformIsIdentity(in.transform), on.clipsToBounds, on.layer.cornerRadius, cover.layer.cornerRadius]);
    });
    // B comes 0.15 s before its incoming window ends, which is when A's outgoing one does.
    stepOnFrame(^{
        sg_playbackTime += 19.85 - playing();
        report(b, 5.85, 200, @[c], NO, kPlaylist);
        SGRHarnessSetTransition(nil);
    });
    stepOnFrame(^{
        UIView *on = stage();
        check(A, @"still mixing as the window nears its end", on && on.subviews.lastObject.alpha > 0.9 && on.subviews.lastObject.alpha < 1,
              [NSString stringWithFormat:@"at %.2f s of B: %@", playing(), coverState()]);
        sg_playbackTime = sg_reportedWhen + (6.2 - sg_reportedAt);
    });
    stepOnFrame(^{
        check(A, @"done as the outgoing window ends", coverBack() && weakStage == nil,
              [NSString stringWithFormat:@"at %.2f s of B: %@, stage kept %d", playing(), coverState(), weakStage != nil]);
    });

    // Each stop: the stage up inside the window, then what stops it, then the cover looked at.
    // The stage waits for the incoming cover (PlayerMix.x's -start), fetched again after a track change, so the stop
    // waits for the stage itself rather than a fixed time.
    void (^stops)(NSString *, dispatch_block_t, dispatch_block_t) = ^(NSString *name, dispatch_block_t up, dispatch_block_t stop) {
        stepOnFrame(up);
        stepUntil([name stringByAppendingString:@": the stage up inside the window"], ^BOOL { return stage() != nil; }, ^{
            weakStage = stage();
            wasOn = weakStage != nil;
            stop();
        });
        stepUntil([name stringByAppendingString:@": cover restored and stage released"], ^BOOL { return coverBack() && weakStage == nil; }, ^{
            check(A, name, wasOn && coverBack() && weakStage == nil, [NSString stringWithFormat:@"up before %d, now %@", wasOn, coverState()]);
        });
    };
    stops(@"a seek back hands the cover back", ^{
        playA(14.2, 16);
        SGRHarnessSetTransition(blend());
    }, ^{ playA(9, 16); });
    // The player stops being seen while it stays in the window: a view over the cover hidden, faded out or moved off.
    UIView *(^host)(void) = ^UIView *{ return tilt.superview; };
    stops(@"a hidden player hands the cover back", ^{ playA(14.2, 16); }, ^{ host().hidden = YES; });
    stops(@"a faded player hands the cover back", ^{
        host().hidden = NO;
        playA(14.2, 16);
    }, ^{ host().alpha = 0; });
    stops(@"a player moved off screen hands the cover back", ^{
        host().alpha = 1;
        playA(14.2, 16);
    }, ^{ host().transform = CGAffineTransformMakeTranslation(2 * window.bounds.size.width, 0); });
    // The facts change under a running stage while its song still plays: the cover comes back in the same turn.
    __block BOOL handedBack;
    void (^factsChange)(NSString *, dispatch_block_t) = ^(NSString *name, dispatch_block_t change) {
        stepOnFrame(^{
            host().transform = CGAffineTransformIdentity;
            playA(14.2, 16);
            SGRHarnessSetTransition(blend());
        });
        stepUntil([name stringByAppendingString:@": the stage up inside the window"], ^BOOL { return stage() != nil; }, ^{
            weakStage = stage();
            wasOn = weakStage != nil;
            change();
            handedBack = stage() == nil && cover.alpha == 1;
        });
        stepUntil([name stringByAppendingString:@": detached stage released"], ^BOOL { return weakStage == nil; }, ^{
            check(A, name, wasOn && handedBack && weakStage == nil, [NSString stringWithFormat:@"up before %d, back in the same turn %d, now %@, old stage kept %d",
                                                                      wasOn, handedBack, coverState(), weakStage != nil]);
            playA(9, 16);
        });
    };
    factsChange(@"a new next song hands the cover back", ^{
        report(a, playing(), 16, @[c], NO, kPlaylist);
        SGRHarnessSetTransition(facts(@"spotify:track:mixA", @"spotify:track:mixC", SGTransitionKindCrossfade, YES, 14, 16, 0, 2));
    });
    factsChange(@"facts whose times are no longer known hand the cover back", ^{
        SGRHarnessSetTransition(facts(@"spotify:track:mixA", @"spotify:track:mixB", SGTransitionKindSpotifyAutomix, NO, 0, 0, 0, 0));
    });
    factsChange(@"facts gone hand the cover back", ^{ SGRHarnessSetTransition(nil); });
    stops(@"another song hands the cover back", ^{
        playA(14.2, 16);
        SGRHarnessSetTransition(blend());
    }, ^{
        report(x, 0, 200, @[], NO, kPlaylist);
        SGRHarnessSetTransition(nil);
    });
    stops(@"the player stopping hands the cover back", ^{
        playA(14.2, 16);
        SGRHarnessSetTransition(blend());
    }, ^{ report(a, 14.8, 16, @[b, c], YES, kPlaylist); });
    // The playback clock is held at 14.2 s from here until the stage is back: the stage fetches its incoming cover
    // again before it shows, and on a slow simulator the real clock left the window first (hosted CI: 15.63 s, no stage).
    stops(@"the player closing hands the cover back", ^{
        playA(14.2, 16);
    }, ^{
        SGRHarnessSetTransitionEnds(DBL_MAX);
        [NSNotificationCenter.defaultCenter postNotificationName:SGPlayerTransitionNotification object:nil];
    });
    stepOnFrame(^{
        check(A, @"held back while it closes", coverBack(), coverState());
        SGRHarnessSetTransitionEnds(0);
    });
    stepUntil(@"the stage back once the player is still, inside the window", ^BOOL { return stage() != nil; }, ^{
        check(A, @"back once the player is still, inside the window", stage() != nil, [NSString stringWithFormat:@"at %.2f s: %@", playing(), coverState()]);
        playA(9, 16);
    });
    // The next song does not come: the stage holds the incoming cover, then gives up 3 s after the window ended.
    stepOnFrame(^{
        playA(15.5, 16);
        SGRHarnessSetTransition(blend());
    });
    stepUntil(@"stage ready before the missing-next-song case", ^BOOL { return stage() != nil; }, ^{
        sg_arrivalTime = 1000;
        sg_playbackTime += 17 - playing();
    });
    // Start the grace period on the first frame past the window, then advance
    // only this clock; neither image loading nor frame delivery consumes it.
    stepUntil(@"incoming artwork fully shown at the end of the window", ^BOOL {
        return stage() && stage().subviews.lastObject.alpha == 1;
    }, ^{ sg_arrivalTime += 2.9; });
    stepOnFrame(^{
        UIView *on = stage();
        CGRect drawn = [cover convertRect:cover.bounds toView:nil];
        CGFloat rgb[3];
        colorAt(window, CGPointMake(CGRectGetMidX(drawn), CGRectGetMidY(drawn)), rgb);
        check(A, @"waits for the next song with its cover", on && on.subviews.lastObject.alpha == 1 && rgb[1] > 0.6 && rgb[0] < 0.4,
              [NSString stringWithFormat:@"2.9 s after the window: %@, the cover's middle %.2f %.2f %.2f", coverState(), rgb[0], rgb[1], rgb[2]]);
        sg_arrivalTime += 0.2;
    });
    stepOnFrame(^{
        check(A, @"gives up when the next song does not come in 3 s", coverBack(), [NSString stringWithFormat:@"3.1 s after the window: %@", coverState()]);
        playA(9, 16);
        sg_arrivalTime = 0;
    });

    // Arm one fresh blend and prove its incoming cover loaded before checking holds;
    // seeking back to 9 s stops the stage with done=NO while keeping _toImage loaded.
    stepOnFrame(^{
        playA(14.2, 16);
        SGRHarnessSetTransition(blend());
    });
    stepUntil(@"incoming artwork loaded before hold checks", ^BOOL {
        return stage() != nil && cover.alpha == 0;
    }, ^{ playA(9, 16); });
    stepUntil(@"stage cleared after seeking back before hold checks", ^BOOL {
        return coverBack();
    }, ^{});

    // Each hold: set, then the song inside its window, then nothing over the cover, then cleared before the window.
    NSArray *holds = @[
        @[@"held back: the lyrics up", ^{ if (!SGRPlayerLyricsOpen()) SGRPlayerToggleLyrics(); }, ^{ if (SGRPlayerLyricsOpen()) SGRPlayerToggleLyrics(); }],
        @[@"held back: the app not active", ^{ sg_inactive = YES; }, ^{ sg_inactive = NO; }],
        @[@"held back: the wide layout", ^{ window.traitOverrides.verticalSizeClass = UIUserInterfaceSizeClassCompact; },
          ^{ [window.traitOverrides removeTrait:UITraitVerticalSizeClass.class]; }],
        @[@"held back: the player not on screen", ^{ tilt.superview.hidden = YES; }, ^{ tilt.superview.hidden = NO; }],
        @[@"held back: Reduce Motion", ^{ SGRHarnessSetReduceMotion(YES); }, ^{ SGRHarnessSetReduceMotion(NO); }],
    ];
    for (NSArray *hold in holds) {
        stepOnFrame((dispatch_block_t)hold[1]);
        stepOnFrame(^{ playA(14.2, 16); });
        stepOnFrame(^{
            NSString *name = hold[0];
            BOOL set = YES;
            if ([name containsString:@"Reduce Motion"]) set = UIAccessibilityIsReduceMotionEnabled();
            if ([name containsString:@"wide"]) set = cover.traitCollection.verticalSizeClass == UIUserInterfaceSizeClassCompact;
            if ([name containsString:@"lyrics"]) set = SGRPlayerLyricsOpen();
            check(A, name, set && coverBack(), [NSString stringWithFormat:@"%@%@", set ? @"" : @"the hold did not take; ", coverState()]);
            playA(9, 16);
            ((dispatch_block_t)hold[2])();
        });
        stepUntil(@"previous playback hold cleared", ^BOOL {
            return !SGRPlayerLyricsOpen() && !SGRPlayerIsTransitioning() && cover.traitCollection.verticalSizeClass != UIUserInterfaceSizeClassCompact;
        }, ^{});
    }
    stepOnFrame(^{ report(a, 14.2, 16, @[b, c], NO, kDJ); });
    stepOnFrame(^{
        check(A, @"held back: the AI DJ", coverBack(), coverState());
        playA(9, 16);
        SGRHarnessSetTransition(facts(@"spotify:track:mixA", @"spotify:track:mixB", SGTransitionKindSpotifyAutomix, NO, 14, 16, 0, 2));
        playA(14.2, 16);
    });
    stepOnFrame(^{
        check(A, @"held back: unknown times", coverBack(), coverState());
        playA(9, 16);
    });
    // Up again with nothing holding it, then the player taken out of the window.
    stepOnFrame(^{
        // Artwork readiness is asynchronous; keep the fixture inside the outgoing window while waiting.
        playA(14.2, 16);
        SGRHarnessSetTransition(blend());
    });
    stepUntil(@"artwork stage up before removing the player", ^BOOL{
        return stage() != nil && cover.alpha == 0;
    }, ^{
        weakStage = stage();
        wasOn = weakStage != nil;
        [window.rootViewController.view.subviews.firstObject removeFromSuperview];
    });
    stepUntil(@"removed player's stage released", ^BOOL { return !weakStage && cover.alpha == 1; }, ^{
        check(A, @"no stage kept once the player is gone", wasOn && weakStage == nil && cover.alpha == 1,
              [NSString stringWithFormat:@"up before %d, stage kept %d, cover alpha %.2f", wasOn, weakStage != nil, cover.alpha]);
    });
    stepOnFrame(^{
        BOOL pass = sg_right == sg_checks;
        NSLog(@"[harness] automix checks: %lu of %lu right -- %@", (unsigned long)sg_right, (unsigned long)sg_checks, pass ? @"PASS" : @"FAIL");
        exit(pass ? 0 : 1);
    });
    runSteps();
}
