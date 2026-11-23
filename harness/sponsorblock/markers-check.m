// See markers-check.h.
#import "markers-check.h"
#import "Shared/SponsorBlock/SponsorBlock.h"

// Spotify's episode bar, a sibling under the slider's own drawing that shows the episode's chapters.
@interface _TtCO17NowPlaying_ECMKit11ProgressBar9AudioView : UIView @end
@implementation _TtCO17NowPlaying_ECMKit11ProgressBar9AudioView @end

#pragma mark - the engine, as the playback hooks drive it

static NSString *const kEpisodeA = @"4rOoJ6Egrf8K2IrywzwOMk", *const kEpisodeB = @"0EpisodeB0123456789xyz";
static NSString *const kSong = @"spotify:track:4uLU6hMCjMI75M1A2tKUQC";

static NSString *episodeURI(NSString *episode) {
    return [@"spotify:episode:" stringByAppendingString:episode];
}

// What the server answers for each episode: [start, end, category]. A's filler is Off in the rules below and its
// interaction reminder is under the one-second minimum, so neither is shown.
static NSDictionary<NSString *, NSArray *> *served(void) {
    return @{kEpisodeA: @[@[@0, @12, @"intro"], @[@60, @150, @"sponsor"], @[@300, @345, @"selfpromo"],
                          @[@400, @460, @"filler"], @[@500, @500.5, @"interaction"], @[@540, @600, @"outro"]],
             kEpisodeB: @[@[@600, @900, @"exclusive_access"]]};
}

static SGSponsorBlockSession *sg_session;

BOOL SBMarksOffRun(void) {
    return [NSProcessInfo.processInfo.arguments containsObject:@"sponsorblock-off"] ||
        [NSProcessInfo.processInfo.environment[@"HARNESS_SCENARIO"] isEqualToString:@"sponsorblock-off"];
}

BOOL SGSponsorBlockMarkersEnabled(void) { return !SBMarksOffRun(); }
NSArray<SGSponsorBlockSegment *> *SGSponsorBlockVisibleSegments(void) { return sg_session.visibleSegments ?: @[]; }
double SGSponsorBlockEpisodeDuration(void) { return sg_session.episodeDuration; }

static void play(NSString *uri, double duration) {
    if (!sg_session) {
        NSDictionary *behaviors = @{@"sponsor": @(SGBlockAuto), @"selfpromo": @(SGBlockAsk), @"interaction": @(SGBlockAuto),
            @"intro": @(SGBlockShowOnly), @"outro": @(SGBlockAuto), @"preview": @(SGBlockOff), @"hook": @(SGBlockOff),
            @"filler": @(SGBlockOff), @"exclusive_access": @(SGBlockShowOnly)};
        sg_session = [[SGSponsorBlockSession alloc] initWithBehaviors:behaviors minimum:1 respectManual:NO
            fetch:^(NSString *episode, NSSet *categories, SGSponsorBlockReply reply) {
                NSMutableArray *rows = [NSMutableArray array];
                for (NSArray *row in served()[episode])
                    [rows addObject:@{@"segment": @[row[0], row[1]], @"category": row[2], @"actionType": @"skip",
                                      @"UUID": [NSString stringWithFormat:@"%@-%lu", episode, (unsigned long)rows.count]}];
                NSData *body = [NSJSONSerialization dataWithJSONObject:@[@{@"videoID": episode, @"segments": rows}] options:0 error:nil];
                reply(SGSponsorBlockParse(body, 200, episode));
            }
            seek:^(double seconds) {}
            record:^dispatch_block_t(double seconds) { return ^{}; }
            notice:^(BOOL ask, SGSponsorBlockAction action) {}];
    }
    [sg_session observeURI:uri position:0 duration:duration playing:NO enabled:YES];
}

#pragma mark - the drawn window

typedef struct { double r, g, b; } SBRGB;

static SBRGB rgb(unsigned hex) {
    return (SBRGB){((hex >> 16) & 0xFF) / 255.0, ((hex >> 8) & 0xFF) / 255.0, (hex & 0xFF) / 255.0};
}

// SponsorBlock's standard colors for the categories shown here.
static SBRGB categoryColor(NSString *category) {
    return rgb([@{@"intro": @0x00FFFF, @"sponsor": @0x00D400, @"selfpromo": @0xFFFF00, @"outro": @0x0202ED,
                  @"exclusive_access": @0x008A5C}[category] unsignedIntValue]);
}

static UIImage *drawn(UIWindow *window) {
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat formatForTraitCollection:window.traitCollection];
    return [[[UIGraphicsImageRenderer alloc] initWithBounds:window.bounds format:format] imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [window drawViewHierarchyInRect:window.bounds afterScreenUpdates:YES];
    }];
}

// The color drawn at `point`, in the image's points.
static SBRGB pixel(UIImage *image, CGPoint point) {
    CGImageRef cg = image.CGImage;
    uint8_t rgba[4] = {0};
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(rgba, 1, 1, 8, 4, space, (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
    CGFloat x = floor(point.x * image.scale), y = floor(point.y * image.scale);
    CGFloat width = CGImageGetWidth(cg), height = CGImageGetHeight(cg);
    CGContextDrawImage(context, CGRectMake(-x, -(height - 1 - y), width, height), cg);
    CGContextRelease(context);
    CGColorSpaceRelease(space);
    return (SBRGB){rgba[0] / 255.0, rgba[1] / 255.0, rgba[2] / 255.0};
}

static double length(SBRGB c) { return sqrt(c.r * c.r + c.g * c.g + c.b * c.b); }
static SBRGB minus(SBRGB a, SBRGB b) { return (SBRGB){a.r - b.r, a.g - b.g, a.b - b.b}; }

// A mark shows where its color moved the bar's pixel toward the category's, by a step one can see; elsewhere the
// bar is as it was drawn with no marks.
static const double kSeenStep = 0.06, kUnmovedStep = 0.025, kTowardCosine = 0.6;
// How far inside or outside a mark's edge a probe sits, in points: clear of the edge's antialiasing.
static const CGFloat kProbeInset = 1.5;

#pragma mark - checks

static NSUInteger sg_wrong, sg_checks;

static void check(NSString *look, NSString *step, BOOL ok, NSString *detail) {
    sg_checks++;
    if (!ok) sg_wrong++;
    NSLog(@"[harness] sponsorblock %@: %@: %@ -- %@", look, step, detail ?: @"", ok ? @"ok" : @"WRONG");
}

typedef struct { double start, end; __unsafe_unretained NSString *category; } SBMark;

static NSString *describe(SBRGB c) { return [NSString stringWithFormat:@"(%.3f %.3f %.3f)", c.r, c.g, c.b]; }

// Checks `marks` of an episode `duration` long on the `track` (slider coordinates), in `marked` against `plain`.
static void expectMarks(NSString *look, NSString *step, UISlider *slider, CGRect track, BOOL rtl, const SBMark *marks, NSUInteger count,
                        double duration, UIImage *marked, UIImage *plain) {
    UIWindow *window = slider.window;
    CGFloat (^at)(double) = ^CGFloat(double seconds) {
        CGFloat share = seconds / duration * track.size.width;
        return rtl ? CGRectGetMaxX(track) - share : CGRectGetMinX(track) + share;
    };
    // Whether `x` is on or beside a mark other than mark `own`.
    BOOL (^nearOther)(CGFloat, NSUInteger) = ^BOOL(CGFloat x, NSUInteger own) {
        for (NSUInteger i = 0; i < count; i++) {
            CGFloat a = at(marks[i].start), b = at(marks[i].end);
            if (i != own && x >= MIN(a, b) - kProbeInset && x <= MAX(a, b) + kProbeInset) return YES;
        }
        return NO;
    };
    CGFloat mid = CGRectGetMidY(track);
    NSMutableArray<NSString *> *wrong = [NSMutableArray array];
    for (NSUInteger i = 0; i < count; i++) {
        CGFloat a = at(marks[i].start), b = at(marks[i].end), left = MIN(a, b), right = MAX(a, b);
        SBRGB toward = categoryColor(marks[i].category);
        for (NSNumber *x in @[@((left + right) / 2), @(left + kProbeInset), @(right - kProbeInset)]) {
            CGPoint point = [slider convertPoint:CGPointMake(x.doubleValue, mid) toView:window];
            SBRGB moved = minus(pixel(marked, point), pixel(plain, point)), target = minus(toward, pixel(plain, point));
            double cosine = (moved.r * target.r + moved.g * target.g + moved.b * target.b) / (length(moved) * length(target) ?: 1);
            if (length(moved) < kSeenStep || cosine < kTowardCosine)
                [wrong addObject:[NSString stringWithFormat:@"%@ at x %.1f moved %@ (cos %.2f)", marks[i].category, x.doubleValue, describe(moved), cosine]];
        }
        // Just past each edge along the track, where no other mark is, and just over and under the track.
        for (NSNumber *x in @[@(left - kProbeInset), @(right + kProbeInset)]) {
            if (x.doubleValue <= CGRectGetMinX(track) + kProbeInset || x.doubleValue >= CGRectGetMaxX(track) - kProbeInset ||
                nearOther(x.doubleValue, i)) continue;
            CGPoint point = [slider convertPoint:CGPointMake(x.doubleValue, mid) toView:window];
            SBRGB moved = minus(pixel(marked, point), pixel(plain, point));
            if (length(moved) > kUnmovedStep)
                [wrong addObject:[NSString stringWithFormat:@"past %@'s edge at x %.1f moved %@", marks[i].category, x.doubleValue, describe(moved)]];
        }
        for (NSNumber *y in @[@(CGRectGetMinY(track) - kProbeInset), @(CGRectGetMaxY(track) + kProbeInset)]) {
            CGPoint point = [slider convertPoint:CGPointMake((left + right) / 2, y.doubleValue) toView:window];
            SBRGB moved = minus(pixel(marked, point), pixel(plain, point));
            if (length(moved) > kUnmovedStep)
                [wrong addObject:[NSString stringWithFormat:@"off the track at y %.1f over %@ moved %@", y.doubleValue, marks[i].category, describe(moved)]];
        }
    }
    check(look, step, !wrong.count, wrong.count ? [wrong componentsJoinedByString:@"; "]
          : [NSString stringWithFormat:@"%lu marks on %@%@", (unsigned long)count, NSStringFromCGRect(track), rtl ? @", right to left" : @""]);
}

// A segment no longer shown: its middle drawn as with no marks.
static void expectUnmarked(NSString *look, NSString *step, UISlider *slider, CGRect track, double start, double end, double duration,
                           UIImage *marked, UIImage *plain) {
    CGFloat x = CGRectGetMinX(track) + (start + end) / 2 / duration * track.size.width;
    CGPoint point = [slider convertPoint:CGPointMake(x, CGRectGetMidY(track)) toView:slider.window];
    SBRGB moved = minus(pixel(marked, point), pixel(plain, point));
    check(look, step, length(moved) <= kUnmovedStep, [NSString stringWithFormat:@"x %.1f moved %@", x, describe(moved)]);
}

static void layOut(UISlider *slider) {
    [slider setNeedsLayout];
    [slider layoutIfNeeded];
}

static const SBMark kMarksA[] = {{0, 12, @"intro"}, {60, 150, @"sponsor"}, {300, 345, @"selfpromo"}, {540, 600, @"outro"}};
static const NSUInteger kMarksACount = sizeof(kMarksA) / sizeof(kMarksA[0]);
static const SBMark kMarksB[] = {{600, 900, @"exclusive_access"}};
static const double kDurationA = 600, kDurationB = 1200, kDurationBLonger = 1800;
// The bar's played share in the screenshots; the checks run with nothing played.
static const float kShotValue = 0.35;

static UIImage *sg_minimumTrack, *sg_maximumTrack;

// Spotify's episode bar as Spotify lays it out (buffering-check.m: 2 pt in, 4.67 pt down in a 17 pt slider, 7 pt tall):
// two chapters with a gap between them, each drawing its own played part, `played` of the episode from its start. As
// the bar draws the progress, the slider's own tracks are clear while it shows (AudioSegmentView carries its own
// progress and colors; that Spotify clears them is assumed, not seen).
static UIView *addEpisodeBar(UISlider *slider, double played, BOOL rtl) {
    sg_minimumTrack = [slider minimumTrackImageForState:UIControlStateNormal];
    sg_maximumTrack = [slider maximumTrackImageForState:UIControlStateNormal];
    UIImage *clear = [[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(7, 7)] imageWithActions:^(UIGraphicsImageRendererContext *context) {}];
    [slider setMinimumTrackImage:clear forState:UIControlStateNormal];
    [slider setMaximumTrackImage:clear forState:UIControlStateNormal];
    CGRect bounds = slider.bounds;
    UIView *bar = [[_TtCO17NowPlaying_ECMKit11ProgressBar9AudioView alloc] initWithFrame:CGRectMake(2, (bounds.size.height - 7) / 2 - 0.33, bounds.size.width - 4, 7)];
    bar.layer.cornerRadius = 3.5;
    bar.clipsToBounds = YES;
    CGFloat width = bar.bounds.size.width, split = round(width * 0.4), reach = played * width;
    CGRect playedPart = rtl ? CGRectMake(width - reach, 0, reach, 7) : CGRectMake(0, 0, reach, 7);
    for (NSValue *chapter in @[[NSValue valueWithCGRect:CGRectMake(0, 0, split - 1, 7)],
                               [NSValue valueWithCGRect:CGRectMake(split + 1, 0, width - split - 1, 7)]]) {
        CGRect frame = chapter.CGRectValue;
        if (rtl) frame.origin.x = width - CGRectGetMaxX(frame);
        UIView *view = [[UIView alloc] initWithFrame:frame];
        view.backgroundColor = [UIColor colorWithWhite:1 alpha:0.3];
        [bar addSubview:view];
        CGRect done = CGRectIntersection(frame, playedPart);
        if (CGRectIsEmpty(done)) continue;
        UIView *fill = [[UIView alloc] initWithFrame:done];
        fill.backgroundColor = UIColor.whiteColor;
        [bar addSubview:fill];
    }
    [slider insertSubview:bar atIndex:0];
    return bar;
}

static void removeEpisodeBar(UISlider *slider, UIView *bar) {
    [bar removeFromSuperview];
    [slider setMinimumTrackImage:sg_minimumTrack forState:UIControlStateNormal];
    [slider setMaximumTrackImage:sg_maximumTrack forState:UIControlStateNormal];
}

static NSUInteger finish(NSString *look) {
    NSLog(@"[harness] sponsorblock %@ checks: %lu of %lu right -- %@", look, (unsigned long)(sg_checks - sg_wrong),
          (unsigned long)sg_checks, sg_wrong ? @"FAIL" : @"PASS");
    return sg_wrong;
}

NSUInteger SBMarksRun(UISlider *slider, NSString *look, void (^scrub)(BOOL), NSString *shots) {
    sg_wrong = sg_checks = 0;
    float shownValue = slider.value;
    slider.value = slider.minimumValue;
    layOut(slider);
    NSArray<UIView *> *before = [slider.subviews copy];
    if (SBMarksOffRun()) {
        UIImage *plain = drawn(slider.window);
        play(episodeURI(kEpisodeA), kDurationA);
        layOut(slider);
        CGRect track = [slider trackRectForBounds:slider.bounds];
        check(look, @"switch off: no view added", [slider.subviews isEqualToArray:before], [NSString stringWithFormat:@"%lu views, were %lu",
              (unsigned long)slider.subviews.count, (unsigned long)before.count]);
        expectUnmarked(look, @"switch off: the sponsor segment not drawn", slider, track, 60, 150, kDurationA, drawn(slider.window), plain);
        return finish(look);
    }

    play(kSong, 200);
    layOut(slider);
    check(look, @"a song: no view added", [slider.subviews isEqualToArray:before], nil);

    // Spotify's episode bar, its chapters under the slider's drawing.
    UIView *bar = addEpisodeBar(slider, 0, NO);
    layOut(slider);
    UIImage *plain = drawn(slider.window);
    CGPoint probe = [slider convertPoint:CGPointMake(CGRectGetMinX(bar.frame) + 105.0 / kDurationA * bar.frame.size.width, CGRectGetMidY(bar.frame)) toView:slider.window];
    UIView *hitBefore = [slider.window hitTest:probe withEvent:nil];
    BOOL elementBefore = slider.isAccessibilityElement;
    NSInteger countBefore = slider.accessibilityElementCount;
    NSString *valueBefore = slider.accessibilityValue;
    play(episodeURI(kEpisodeA), kDurationA);
    UIImage *marked = drawn(slider.window);
    expectMarks(look, @"the episode's segments on its bar", slider, bar.frame, NO, kMarksA, kMarksACount, kDurationA, marked, plain);
    expectUnmarked(look, @"a category set to Off not drawn", slider, bar.frame, 400, 460, kDurationA, marked, plain);
    expectUnmarked(look, @"a segment under the minimum not drawn", slider, bar.frame, 500, 500.5, kDurationA, marked, plain);
    check(look, @"a touch on a mark reaches what it reached", [slider.window hitTest:probe withEvent:nil] == hitBefore,
          NSStringFromClass([slider.window hitTest:probe withEvent:nil].class));
    check(look, @"the slider's accessibility as it was", slider.isAccessibilityElement == elementBefore &&
          slider.accessibilityElementCount == countBefore && [slider.accessibilityValue ?: @"" isEqualToString:valueBefore ?: @""],
          [NSString stringWithFormat:@"element %d, count %ld, value %@", slider.isAccessibilityElement, (long)slider.accessibilityElementCount, slider.accessibilityValue]);

    // Another episode comes in by the engine's notification alone, with no layout pass of the slider's.
    play(episodeURI(kEpisodeB), kDurationB);
    UIImage *next = drawn(slider.window);
    expectMarks(look, @"the next episode's segments, on the notification", slider, bar.frame, NO, kMarksB, 1, kDurationB, next, plain);
    expectUnmarked(look, @"the previous episode's segments gone", slider, bar.frame, 60, 150, kDurationA, next, plain);
    play(episodeURI(kEpisodeB), kDurationBLonger);
    expectMarks(look, @"placed again when the duration changes", slider, bar.frame, NO, kMarksB, 1, kDurationBLonger, drawn(slider.window), plain);

    // Spotify lays the slider out narrower, its bar with it.
    play(episodeURI(kEpisodeA), kDurationA);
    CGRect frame = slider.frame;
    slider.frame = CGRectMake(frame.origin.x, frame.origin.y, frame.size.width - 60, frame.size.height);
    bar.frame = CGRectMake(bar.frame.origin.x, bar.frame.origin.y, bar.frame.size.width - 60, bar.frame.size.height);
    layOut(slider);
    marked = drawn(slider.window);
    play(kSong, 200);
    plain = drawn(slider.window);
    expectMarks(look, @"following a narrower bar", slider, bar.frame, NO, kMarksA, kMarksACount, kDurationA, marked, plain);
    slider.frame = frame;
    bar.frame = CGRectMake(bar.frame.origin.x, bar.frame.origin.y, bar.frame.size.width + 60, bar.frame.size.height);
    layOut(slider);

    // Right to left, the start of the episode at the bar's right end.
    slider.semanticContentAttribute = UISemanticContentAttributeForceRightToLeft;
    layOut(slider);
    plain = drawn(slider.window);
    play(episodeURI(kEpisodeA), kDurationA);
    layOut(slider);
    expectMarks(look, @"right to left", slider, bar.frame, YES, kMarksA, kMarksACount, kDurationA, drawn(slider.window), plain);
    slider.semanticContentAttribute = UISemanticContentAttributeUnspecified;

    // No episode bar: the slider's own track, inset as its track rect says.
    removeEpisodeBar(slider, bar);
    layOut(slider);
    marked = drawn(slider.window);
    play(kSong, 200);
    plain = drawn(slider.window);
    CGRect track = [slider trackRectForBounds:slider.bounds];
    expectMarks(look, @"on the slider's own track", slider, track, NO, kMarksA, kMarksACount, kDurationA, marked, plain);
    if (scrub) {
        play(episodeURI(kEpisodeA), kDurationA);
        scrub(YES);
        CGRect thick = [slider trackRectForBounds:slider.bounds];
        marked = drawn(slider.window);
        play(kSong, 200);
        plain = drawn(slider.window);
        check(look, @"a scrub thickens the track", thick.size.height > track.size.height, NSStringFromCGRect(thick));
        expectMarks(look, @"as thick as the scrubbed track", slider, thick, NO, kMarksA, kMarksACount, kDurationA, marked, plain);
        scrub(NO);
    }
    play(episodeURI(kEpisodeA), kDurationA);
    layOut(slider);
    play(kSong, 200);
    layOut(slider);
    check(look, @"a song after an episode: nothing left", [slider.subviews isEqualToArray:before], [NSString stringWithFormat:@"%lu views, were %lu",
          (unsigned long)slider.subviews.count, (unsigned long)before.count]);

    // The screenshots: the episode's bar a third played, left to right and right to left.
    slider.value = slider.minimumValue + kShotValue * (slider.maximumValue - slider.minimumValue);
    play(episodeURI(kEpisodeA), kDurationA);
    for (NSNumber *rtl in @[@NO, @YES]) {
        slider.semanticContentAttribute = rtl.boolValue ? UISemanticContentAttributeForceRightToLeft : UISemanticContentAttributeUnspecified;
        bar = addEpisodeBar(slider, kShotValue, rtl.boolValue);
        layOut(slider);
        NSString *path = [shots stringByAppendingPathComponent:[NSString stringWithFormat:@"%@-%@.png", look, rtl.boolValue ? @"rtl" : @"ltr"]];
        BOOL written = [UIImagePNGRepresentation(drawn(slider.window)) writeToFile:path atomically:YES];
        check(look, @"screenshot", written, path);
        removeEpisodeBar(slider, bar);
    }
    slider.semanticContentAttribute = UISemanticContentAttributeUnspecified;
    slider.value = shownValue;
    layOut(slider);
    return finish(look);
}
