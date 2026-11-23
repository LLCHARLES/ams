// Isolate the slider and its immediate composition on transparent pixels. In the second
// variant UIKit fits the minimum image to the played segment and dims the native control.
{
    UIView *parent = slider.superview;
    CGRect frame = slider.frame;
    UIView *host = [[UIView alloc] initWithFrame:frame];
    [parent addSubview:host];
    [host addSubview:slider];
    slider.frame = host.bounds;
    float initial = slider.value;
    [slider layoutSubviews];
    sliderIdentifierReads = 0;
    for (NSUInteger i = 0; i < 24; i++) [slider layoutSubviews];
    HARNESS_CHECK(!sliderIdentifierReads);
    [slider setValue:.25f animated:NO];
    [slider setValue:.250001f animated:NO];
    HARNESS_CHECK(slider.value == .25f);
    [slider setValue:.75f animated:YES];
    [slider setValue:.250001f animated:NO];
    HARNESS_CHECK(slider.value == .250001f);
    void (^settle)(NSTimeInterval) = ^(NSTimeInterval seconds) {
        [CATransaction flush];
        [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:seconds]];
    };
    // Like PlayerMix's outgoing marker, at the back of the slider, visible through the unplayed rail.
    UIView *band = [UIView new];
    band.backgroundColor = UIColor.redColor;
    [slider insertSubview:band atIndex:0];
    BOOL (^bandVisible)(void) = ^BOOL {
        CGRect track = [slider trackRectForBounds:slider.bounds];
        band.frame = CGRectMake(CGRectGetMaxX(track)-16, track.origin.y, 8, track.size.height);
        uint8_t rgba[4] = {};
        CGColorSpaceRef rgb = CGColorSpaceCreateDeviceRGB();
        CGContextRef ctx = CGBitmapContextCreate(rgba,1,1,8,4,rgb,kCGBitmapByteOrder32Big|(CGBitmapInfo)kCGImageAlphaPremultipliedLast);
        CGContextTranslateCTM(ctx,-CGRectGetMidX(band.frame),-CGRectGetMinY(track)-1);
        [host.layer renderInContext:ctx];
        CGContextRelease(ctx); CGColorSpaceRelease(rgb);
        return rgba[0] > 160 && rgba[1] >= 48 && rgba[1] < 70;
    };
    BOOL originalMotion = UIAccessibilityIsReduceMotionEnabled();
    void (*motion)(BOOL) = (void (*)(BOOL))dlsym(RTLD_DEFAULT,"_AXSSetReduceMotionEnabled");
    HARNESS_CHECK(motion != NULL);
    for (NSUInteger variant = 0; variant < 3; variant++) {
        motion(variant == 1);
        settle(.05);
        HARNESS_CHECK(UIAccessibilityIsReduceMotionEnabled() == (variant == 1));
        BOOL segment = variant != 0, rtl = variant == 2;
        slider.semanticContentAttribute = rtl ? UISemanticContentAttributeForceRightToLeft : UISemanticContentAttributeForceLeftToRight;
        for (NSUInteger state = 0; state <= UIControlStateHighlighted; state++) {
            CGFloat h = state ? 12 : 7;
            UIImage *disc = [[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(h,h)]
                imageWithActions:^(UIGraphicsImageRendererContext *c) {
                    [UIColor.whiteColor setFill];
                    [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(0,0,h,h)] fill];
                }];
            [slider setMinimumTrackImage:disc forState:state];
            [slider setMaximumTrackImage:disc forState:state];
        }
        slider.highlighted = YES;
        slider.alpha = segment ? 0.6 : 1;
        [slider beginTrackingWithTouch:[UITouch new] withEvent:nil];
        settle(.04);
        CALayer *visible = host.layer.sublayers.lastObject;
        // Inspect the visible composition, not animations still running on the obscured native track.
        __block BOOL moving = NO, fading = NO;
        void (^inspect)(CALayer *) = ^(CALayer *layer) {
            for (NSString *key in layer.animationKeys) {
                CAAnimation *a = [layer animationForKey:key];
                if ([a isKindOfClass:CATransition.class] && [((CATransition *)a).type isEqual:kCATransitionFade]) fading = YES;
                if ([a isKindOfClass:CAPropertyAnimation.class] && [((CAPropertyAnimation *)a).keyPath isEqual:@"opacity"]) fading = YES;
            }
            CGFloat height = layer.presentationLayer.bounds.size.height;
            if (height > 7 && height < 12) moving = YES;
        };
        inspect(visible);
        for (CALayer *child in visible.sublayers) inspect(child);
        [self expect:variant == 1 ? fading && !moving : moving step:@"visible scrub transition"
              detail:[NSString stringWithFormat:@"reduce %d, growth %d, fade %d",variant == 1,moving,fading]];
        settle(.55);
        slider.value = .5;
        [slider layoutIfNeeded];
        if (variant == 0) [self expect:bandVisible() step:@"marker behind held rail" detail:@"red under translucent track"];
        band.hidden = YES;
        for (NSNumber *position in @[@0.02,@0.5,@0.98]) {
            slider.value = position.floatValue;
            [slider setNeedsLayout];
            [slider layoutIfNeeded];
            CGRect rect = [slider trackRectForBounds:slider.bounds];
            size_t w = lround(rect.size.width), h = 12;
            CGFloat cut = w * (rtl ? 1-position.doubleValue : position.doubleValue);
            if (segment) {
                SGForEachView(slider, ^(UIView *v) {
                    if ([v isKindOfClass:UIImageView.class] && v.bounds.size.width > 12)
                        v.frame = v.superview.bounds;
                });
            }
            NSMutableData *pixels = [NSMutableData dataWithLength:w*h*4];
            CGColorSpaceRef rgb = CGColorSpaceCreateDeviceRGB();
            CGContextRef ctx = CGBitmapContextCreate(pixels.mutableBytes,w,h,8,w*4,rgb,
                kCGBitmapByteOrder32Big | (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
            CGColorSpaceRelease(rgb);
            CGContextTranslateCTM(ctx,-rect.origin.x,-rect.origin.y);
            [host.layer renderInContext:ctx];
            CGContextRelease(ctx);
            const uint8_t *p = pixels.bytes;
            BOOL caps = p[3] < 8 && p[4*(w-1)+3] < 8 && p[4*((h-1)*w)+3] < 8 && p[4*(h*w-1)+3] < 8;
            BOOL split = YES, white = YES;
            for (NSUInteger y = 1; y < h-1; y++) {
                for (NSUInteger x = 4; x < w-4; x++) {
                    // These rows are inside the circular caps here; skip the antialiased split pixel.
                    if (fabs(x+0.5-cut) < 1) continue;
                    BOOL played = (x+0.5 < cut) != rtl;
                    const uint8_t *pixel = p+4*(y*w+x);
                    if (played) white &= pixel[0]>=253 && pixel[1]>=253 && pixel[2]>=253 && pixel[3]>=253;
                    else split &= abs(pixel[3]-51)<=2;
                }
            }
            [self expect:caps && split && white && rect.size.height == 12 step:@"held capsule"
                  detail:[NSString stringWithFormat:@"variant %lu, value %@: corners %d, rail/split %d, lit fill %d",
                          (unsigned long)variant,position,caps,split,white]];
        }
        slider.highlighted = NO;
        if (variant == 0) [slider endTrackingWithTouch:[UITouch new] withEvent:nil];
        else if (variant == 1) [slider cancelTrackingWithEvent:nil];
        else { [slider removeFromSuperview]; HARNESS_CHECK(host.layer.sublayers.count == 0); [host addSubview:slider]; }
        slider.alpha = 1;
        if (variant < 2) {
            settle(.04);
            moving = fading = NO;
            inspect(visible);
            for (CALayer *child in visible.sublayers) inspect(child);
            [self expect:variant == 1 ? fading && !moving : moving step:@"visible release transition"
                  detail:[NSString stringWithFormat:@"shrink %d, fade %d",moving,fading]];
        }
        settle(.55);
        HARNESS_CHECK(host.layer.sublayers.count == 1 && [slider trackRectForBounds:slider.bounds].size.height == 7);
        band.hidden = NO;
        slider.value = .5;
        [slider layoutIfNeeded];
        if (variant == 0) [self expect:bandVisible() step:@"marker behind released rail" detail:@"same interval, resting height"];
    }
    motion(originalMotion);
    [band removeFromSuperview];
    slider.semanticContentAttribute = UISemanticContentAttributeUnspecified;
    slider.value = initial;
    [slider setMinimumTrackImage:nil forState:UIControlStateHighlighted];
    [slider setMaximumTrackImage:nil forState:UIControlStateHighlighted];
    [parent addSubview:slider];
    slider.frame = frame;
    [host removeFromSuperview];
}
