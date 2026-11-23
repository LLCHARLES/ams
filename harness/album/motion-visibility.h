#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>
#import "Redesigned/Kit/SGRField.h"
#import "Redesigned/Kit/SGRFluid.h"
#import "../harness-fail.h"

extern __weak UIView *harnessSettledPlayerField;
extern NSNotificationName const SGRPlayerVisibilityDidChangeNotification;
@interface UIView (HarnessMotionFile)
- (void)showFile:(NSURL *)file;
- (void)showMotion:(NSURL *)file;
@end

static NSProcessInfoThermalState reportedHeat;
static BOOL reportedLowPower;

static void checkMotionChanges(AVPlayer *player, SGRFluidLayer *layer, NSUInteger step, dispatch_block_t done) {
    static const struct {
        NSProcessInfoThermalState heat;
        BOOL lowPower, moving;
    } states[] = {
        {NSProcessInfoThermalStateFair, NO, YES}, {NSProcessInfoThermalStateSerious, NO, NO},
        {NSProcessInfoThermalStateNominal, NO, YES}, {NSProcessInfoThermalStateCritical, NO, NO},
        {NSProcessInfoThermalStateFair, NO, YES}, {NSProcessInfoThermalStateFair, YES, NO},
        {NSProcessInfoThermalStateFair, NO, YES},
    };
    if (step == sizeof(states) / sizeof(states[0])) { done(); return; }
    NSNotificationName name = reportedLowPower != states[step].lowPower
        ? NSProcessInfoPowerStateDidChangeNotification : NSProcessInfoThermalStateDidChangeNotification;
    reportedHeat = states[step].heat;
    reportedLowPower = states[step].lowPower;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        [NSNotificationCenter.defaultCenter postNotificationName:name object:NSProcessInfo.processInfo];
        // Enqueued after the observers' hops; no sleep or AVPlayer clock polling.
        dispatch_async(dispatch_get_main_queue(), ^{
            HARNESS_CHECK((player.rate > 0) == states[step].moving);
            HARNESS_CHECK(layer.moving == states[step].moving);
            checkMotionChanges(player, layer, step + 1, done);
        });
    });
}

// A local mp4 (motion-fixture.mp4 in the harness bundle).
static void motionVisibilityCheck(UIView *root, BOOL artist) {
    if (![NSProcessInfo.processInfo.arguments containsObject:@"motion-visibility"]) return;
    [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification object:nil
        queue:nil usingBlock:^(NSNotification *note) {
        UIScrollView *list = [[UIScrollView alloc] initWithFrame:CGRectMake(0, 0, 240, 150)];
        list.contentSize = CGSizeMake(240, 1000);
        [root addSubview:list];
        UIView *header = [[NSClassFromString(artist ? @"SGRArtistMotionView" : @"SGRAlbumHero") alloc]
            initWithFrame:CGRectMake(0, 0, 240, 100)];
        [list addSubview:header];
        NSURL *file = [NSBundle.mainBundle URLForResource:@"motion-fixture" withExtension:@"mp4"];
        HARNESS_CHECK(file && header.window);
        UIView *field = [[UIView alloc] initWithFrame:CGRectMake(240, 0, 80, 150)];
        [root addSubview:field];
        harnessSettledPlayerField = field;
        if (artist) [header showFile:file]; else [header showMotion:file];
        AVPlayer *player = [header valueForKey:@"player"];
        HARNESS_CHECK(player.rate > 0);
        field.frame = CGRectMake(0, 0, 239, 150);
        [NSNotificationCenter.defaultCenter postNotificationName:SGRPlayerVisibilityDidChangeNotification object:nil];
        HARNESS_CHECK(player.rate > 0); // One uncovered column, even though the field overlaps.
        field.frame = list.frame;
        [NSNotificationCenter.defaultCenter postNotificationName:SGRPlayerVisibilityDidChangeNotification object:nil];
        HARNESS_CHECK(player.rate == 0);
        harnessSettledPlayerField = nil;
        [NSNotificationCenter.defaultCenter postNotificationName:SGRPlayerVisibilityDidChangeNotification object:nil];
        HARNESS_CHECK(player.rate > 0);
        list.contentOffset = CGPointMake(0, 100);
        HARNESS_CHECK(player.rate == 0);
        list.contentOffset = CGPointMake(0, 99);
        HARNESS_CHECK(player.rate > 0);
        list.hidden = YES;
        HARNESS_CHECK(player.rate == 0);
        list.hidden = NO;
        HARNESS_CHECK(player.rate > 0);
        Class info = object_getClass(NSProcessInfo.processInfo);
        method_setImplementation(class_getInstanceMethod(info, @selector(thermalState)),
            imp_implementationWithBlock(^NSProcessInfoThermalState(id unused) { return reportedHeat; }));
        method_setImplementation(class_getInstanceMethod(info, @selector(isLowPowerModeEnabled)),
            imp_implementationWithBlock(^BOOL(id unused) { return reportedLowPower; }));
        SGRArtworkField *art = [[SGRArtworkField alloc] initWithFrame:field.frame];
        [root addSubview:art];
        art.fluid = YES;
        SGRFluidLayer *fluid = [art valueForKey:@"fluidLayer"];
        HARNESS_CHECK(fluid.moving);
        checkMotionChanges(player, fluid, 0, ^{
            [header removeFromSuperview];
            HARNESS_CHECK(player.rate == 0);
            NSLog(@"PASS %@ header playback: viewport, heat, cooling, Low Power Mode and field motion", header.class);
            exit(0);
        });
    }];
}
