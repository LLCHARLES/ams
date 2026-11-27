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
        SGRSetFluidRenderer(SGRFluidRendererLight);
        HARNESS_CHECK(gpu.superlayer == nil);
    }
    return 0;
}
