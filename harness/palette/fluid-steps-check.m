// The field's 200/600 pt bleed while the player's plane grows 4 pt per layout.
#import "Redesigned/Kit/SGRFluid.h"
#import "Redesigned/Kit/SGRFluidGPU.h"
#import "Shared/Player/SGMusicSpectrum.h"
#import "../harness-fail.h"

UIColor *SGRAccentColor(void) { return UIColor.greenColor; }
BOOL SGRPlayerIsTransitioning(void) { return NO; }
void SGRObservePlayerTransition(id owner, void (^changed)(id)) {}
void SGRBackdropInkFollow(CFTimeInterval duration) {}
void SGMusicSpectrumAddReader(void) { HARNESS_FAIL(@"layout started audio analysis"); }
void SGMusicSpectrumRemoveReader(void) {}
uint64_t SGMusicSpectrumReadings(void) { return 0; }
BOOL SGMusicSpectrumReading(uint64_t index, float levels[3]) { return NO; }

static BOOL active = YES;
BOOL SGRArtworkAppIsActive(void) { return active; }

static NSMutableArray<dispatch_block_t> *preparations;
static UIImage *scheduledCover;
void SGRProbeScheduleFluid(UIImage *image, dispatch_block_t prepare) {
    scheduledCover = image;
    [preparations addObject:prepare];
}

static void drainMain(void) {
    __block BOOL drained = NO;
    dispatch_async(dispatch_get_main_queue(), ^{ drained = YES; });
    while (!drained) [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
}

static void activate(void) {
    active = YES;
    [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationDidBecomeActiveNotification object:nil];
    drainMain();
}

static void checkPreparation(SGRFluidLayer *layer) {
    preparations = [NSMutableArray array];
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(8, 8)];
    UIImage *(^cover)(UIColor *) = ^UIImage *(UIColor *color) {
        return [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
            [color setFill];
            UIRectFill(CGRectMake(0, 0, 8, 8));
        }];
    };
    UIImage *red = cover(UIColor.redColor), *blue = cover(UIColor.blueColor), *green = cover(UIColor.greenColor);
    [layer setArtwork:red animated:NO];
    HARNESS_CHECK(!layer.moving && preparations.count == 1 && scheduledCover == red);
    dispatch_block_t late = preparations.firstObject;
    [preparations removeAllObjects];
    active = NO;
    [layer setArtwork:blue animated:YES];
    [layer setArtwork:green animated:YES];
    [NSNotificationCenter.defaultCenter postNotificationName:SGRFluidSettingsDidChangeNotification object:nil];
    HARNESS_CHECK(!preparations.count);
    activate();
    HARNESS_CHECK(layer.hidden && preparations.count == 1 && scheduledCover == green);
    activate();
    layer.hidden = NO;
    HARNESS_CHECK(preparations.count == 1);
    preparations.firstObject();
    drainMain();
    HARNESS_CHECK(!layer.hidden);
    id current = [layer valueForKey:@"cover"];
    HARNESS_CHECK(current != nil);
    late();
    drainMain();
    HARNESS_CHECK([layer valueForKey:@"cover"] == current);
    [preparations removeAllObjects];

    layer.hidden = YES;
    [layer setArtwork:green animated:YES];
    [layer setArtwork:red animated:YES];
    [layer setArtwork:blue animated:YES];
    [NSNotificationCenter.defaultCenter postNotificationName:UIAccessibilityDarkerSystemColorsStatusDidChangeNotification object:nil];
    activate();
    HARNESS_CHECK(!preparations.count);
    active = NO;
    layer.hidden = NO;
    HARNESS_CHECK(layer.hidden && !preparations.count);
    activate();
    HARNESS_CHECK(layer.hidden && preparations.count == 1 && scheduledCover == blue);
    preparations.firstObject();
    drainMain();
    HARNESS_CHECK(!layer.hidden && [layer valueForKey:@"cover"] != current);
    [preparations removeAllObjects];
    layer.hidden = YES;
    [NSNotificationCenter.defaultCenter postNotificationName:SGRFluidSettingsDidChangeNotification object:nil];
    HARNESS_CHECK(!preparations.count);
    layer.hidden = NO;
    HARNESS_CHECK(layer.hidden && preparations.count == 1 && scheduledCover == blue);
    preparations.firstObject();
    drainMain();
    HARNESS_CHECK(!layer.hidden);
    puts("PASS: inactive and hidden changes coalesce, late preparation is discarded, visible paused artwork prepares");
}

int main(void) {
    @autoreleasepool {
        SGRSetFluidRenderer(SGRFluidRendererSmooth);
        SGRFluidLayer *field = [SGRFluidLayer layer];
        SGRFluidGPULayer *gpu = (id)field.sublayers.firstObject;
        HARNESS_CHECK([gpu isKindOfClass:SGRFluidGPULayer.class]);
        HARNESS_CHECK(gpu.maximumDrawableCount == 2);
        CGRect visible = CGRectMake(0, 200, 390, 844);
        NSUInteger sizes = 0;
        CGSize last = CGSizeZero;
        for (CGFloat plane = 874; plane <= 2144; plane += 4) {
            field.frame = CGRectMake(0, -200, 390, plane + 800);
            field.visibleRect = visible;
            [field layoutIfNeeded];
            if (!CGSizeEqualToSize(gpu.drawableSize, last)) sizes++;
            last = gpu.drawableSize;
            HARNESS_CHECK(CGRectContainsRect(gpu.frame, field.bounds));
            HARNESS_CHECK(CGRectEqualToRect([gpu convertRect:gpu.visibleRect toLayer:field], visible));
        }
        HARNESS_CHECK(sizes > 0 && sizes <= 6);
        printf("PASS: %lu drawable sizes over 318 layouts\n", (unsigned long)sizes);
        checkPreparation(field);
        SGRSetFluidRenderer(SGRFluidRendererLight);
        HARNESS_CHECK(gpu.superlayer == nil);
    }
    return 0;
}
