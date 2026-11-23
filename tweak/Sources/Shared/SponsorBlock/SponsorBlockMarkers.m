// The visible SponsorBlock segments as colored marks on a progress slider's track, after upstream Vitrine's
// SGSponsorBlockOverlay (d48c5f3b). Each look's slider hooks call in (Native/Player/PlayerScrub.x,
// Redesigned/Player/PlayerControls.x); this file draws. One view per slider, behind the slider's own drawing so
// the thumb stays over it: just above Spotify's episode bar (ProgressBar.AudioView, the bar an episode shows,
// its chapters included) when the slider holds one, else at the back on the slider's track rect. It takes no
// touches and VoiceOver does not see it. The marks are placed again only when the segments or the episode's
// duration change (the engine's notification) or the slider's bounds, track, direction or episode bar do.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "SponsorBlock.h"

// Wide enough to read: a one-second segment of an hour's episode is a tenth of a point.
static const CGFloat kMinimumMarkWidthPoints = 2;

// SponsorBlock's standard category colors, upstream Vitrine's defaults (SGSponsorBlockSettings.m kCategories).
static UIColor *categoryColor(NSString *category) {
    static NSDictionary<NSString *, NSNumber *> *rgb;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        rgb = @{@"sponsor": @0x00D400, @"selfpromo": @0xFFFF00, @"interaction": @0xCC00FF, @"intro": @0x00FFFF,
                @"outro": @0x0202ED, @"preview": @0x008FD6, @"hook": @0x008F87, @"filler": @0x7300FF,
                @"exclusive_access": @0x008A5C};
    });
    NSUInteger value = rgb[category].unsignedIntegerValue;
    return [UIColor colorWithRed:((value >> 16) & 0xFF) / 255.0 green:((value >> 8) & 0xFF) / 255.0
                            blue:(value & 0xFF) / 255.0 alpha:1];
}

@interface SGSponsorBlockMarks : UIView
@end

@implementation SGSponsorBlockMarks {
@public
    NSUInteger _revision;
    CGRect _bounds, _track;
    BOOL _rtl;
    double _opacity;
    __weak UIView *_bar;
}
@end

static char kMarksKey;
static Class sg_barClass;
// Every slider shown since launch, weakly, with its look's opacity for the marks.
static NSMapTable<UISlider *, NSNumber *> *sg_sliders;
static NSArray<SGSponsorBlockSegment *> *sg_segments;
static double sg_duration;
static NSUInteger sg_revision;

static UIView *episodeBar(UISlider *slider) {
    for (UIView *view in slider.subviews) {
        if ([view isKindOfClass:sg_barClass] && !view.hidden) return view;
    }
    return nil;
}

static void removeMarks(UISlider *slider) {
    SGSponsorBlockMarks *marks = objc_getAssociatedObject(slider, &kMarksKey);
    [marks removeFromSuperview];
    objc_setAssociatedObject(slider, &kMarksKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void placeMarks(UISlider *slider, double opacity) {
    if (!sg_segments.count) {
        removeMarks(slider);
        return;
    }
    UIView *bar = episodeBar(slider);
    CGRect bounds = slider.bounds;
    CGRect track = bar ? bar.frame : [slider trackRectForBounds:bounds];
    BOOL rtl = slider.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;
    SGSponsorBlockMarks *marks = objc_getAssociatedObject(slider, &kMarksKey);
    if (marks && marks.superview == slider && marks->_revision == sg_revision && marks->_bar == bar && marks->_rtl == rtl &&
        marks->_opacity == opacity && CGRectEqualToRect(marks->_bounds, bounds) && CGRectEqualToRect(marks->_track, track)) return;
    // A track outside the slider (a bar thinner than its track images) has nowhere to show them.
    if (CGRectIsEmpty(track) || !CGRectContainsRect(bounds, track)) {
        removeMarks(slider);
        return;
    }
    if (!marks) {
        marks = [SGSponsorBlockMarks new];
        marks.userInteractionEnabled = NO;
        marks.accessibilityElementsHidden = YES;
        marks.clipsToBounds = YES;
        objc_setAssociatedObject(slider, &kMarksKey, marks, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (marks.superview != slider || marks->_bar != bar) {
        if (bar) [slider insertSubview:marks aboveSubview:bar];
        else [slider insertSubview:marks atIndex:0];
    }
    marks->_revision = sg_revision;
    marks->_bar = bar;
    marks->_rtl = rtl;
    marks->_opacity = opacity;
    marks->_bounds = bounds;
    marks->_track = track;
    marks.frame = track;
    marks.alpha = opacity;
    // The bar's own rounding, so a mark at either end keeps its shape.
    marks.layer.cornerRadius = bar ? bar.layer.cornerRadius : track.size.height / 2;
    marks.layer.cornerCurve = bar ? bar.layer.cornerCurve : kCACornerCurveCircular;

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    NSArray<CALayer *> *layers = marks.layer.sublayers ?: @[];
    CGFloat width = track.size.width, height = track.size.height;
    for (NSUInteger i = 0; i < sg_segments.count; i++) {
        SGSponsorBlockSegment *segment = sg_segments[i];
        CALayer *layer = i < layers.count ? layers[i] : [CALayer layer];
        if (!layer.superlayer) [marks.layer addSublayer:layer];
        CGFloat markWidth = MIN(width, MAX(kMinimumMarkWidthPoints, (segment.end - segment.start) / sg_duration * width));
        CGFloat x = MIN(width - markWidth, segment.start / sg_duration * width);
        layer.frame = CGRectMake(rtl ? width - x - markWidth : x, 0, markWidth, height);
        layer.backgroundColor = categoryColor(segment.category).CGColor;
    }
    for (NSUInteger i = sg_segments.count; i < layers.count; i++) [layers[i] removeFromSuperlayer];
    [CATransaction commit];
}

static void segmentsChanged(void) {
    sg_segments = SGSponsorBlockVisibleSegments();
    sg_duration = SGSponsorBlockEpisodeDuration();
    sg_revision++;
    for (UISlider *slider in sg_sliders.keyEnumerator.allObjects) placeMarks(slider, [sg_sliders objectForKey:slider].doubleValue);
}

void SGSponsorBlockMarksShown(UISlider *slider, double opacity) {
    if (!sg_sliders) {
        sg_sliders = [NSMapTable weakToStrongObjectsMapTable];
        sg_barClass = NSClassFromString(@"_TtCO17NowPlaying_ECMKit11ProgressBar9AudioView");
        [NSNotificationCenter.defaultCenter addObserverForName:SGSponsorBlockSegmentsDidChangeNotification object:nil queue:nil
                                                    usingBlock:^(NSNotification *note) { segmentsChanged(); }];
        segmentsChanged();
    }
    [sg_sliders setObject:@(opacity) forKey:slider];
    placeMarks(slider, opacity);
}

void SGSponsorBlockMarksLaidOut(UISlider *slider) {
    if (!sg_segments.count) return;
    NSNumber *opacity = [sg_sliders objectForKey:slider];
    if (opacity) placeMarks(slider, opacity.doubleValue);
}
