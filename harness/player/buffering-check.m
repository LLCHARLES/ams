#import <UIKit/UIKit.h>
#import "../harness-fail.h"

@interface _TtCO17NowPlaying_ECMKit11ProgressBar6Slider : UISlider @end
@implementation _TtCO17NowPlaying_ECMKit11ProgressBar6Slider @end
@interface _TtCO17NowPlaying_ECMKit11ProgressBar9AudioView : UIView @end
@implementation _TtCO17NowPlaying_ECMKit11ProgressBar9AudioView @end
__attribute__((objc_runtime_name("NowPlaying_ECMKit.SliderBufferingAnimationView")))
@interface TestBand : UIView @end
@implementation TestBand @end

int main(void) {
    @autoreleasepool {
        UISlider *slider = [[_TtCO17NowPlaying_ECMKit11ProgressBar6Slider alloc]
                            initWithFrame:CGRectMake(0, 0, 358, 17)];
        UIView *band = [TestBand new];
        band.hidden = YES;
        [slider addSubview:band];
        CGRect request = CGRectMake(88, 2, 270, 7);
        band.frame = request;
        HARNESS_CHECK(CGRectEqualToRect(band.frame, request) && !band.clipsToBounds);

        UIView *audio = [[_TtCO17NowPlaying_ECMKit11ProgressBar9AudioView alloc]
                         initWithFrame:CGRectMake(2, 4.67, 354, 7)];
        audio.layer.cornerRadius = 3.5;
        [slider insertSubview:audio atIndex:0];
        slider.semanticContentAttribute = UISemanticContentAttributeForceLeftToRight;
        band.frame = request;
        HARNESS_CHECK(CGRectEqualToRect(band.frame, CGRectMake(88, audio.frame.origin.y, 268, 7)));
        HARNESS_CHECK(band.clipsToBounds && band.layer.cornerRadius == 3.5);
        HARNESS_CHECK(band.layer.maskedCorners == (kCALayerMaxXMinYCorner | kCALayerMaxXMaxYCorner));

        slider.semanticContentAttribute = UISemanticContentAttributeForceRightToLeft;
        band.frame = CGRectMake(0, 2, 270, 5);
        HARNESS_CHECK(CGRectEqualToRect(band.frame, CGRectMake(2, audio.frame.origin.y, 268, 7)));
        HARNESS_CHECK(band.layer.maskedCorners == (kCALayerMinXMinYCorner | kCALayerMinXMaxYCorner));
        HARNESS_CHECK(band.hidden);
        puts("Podcast buffering band: passed");
    }
    return 0;
}
