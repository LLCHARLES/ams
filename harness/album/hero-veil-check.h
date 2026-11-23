// The page headers' scroll veil (Redesigned/Kit/SGRHeroVeil.h) and top-bar clip, checked on a mocked page: shared by
// the album, playlist and artist harnesses. `veil` on the launch line, with -spotifyglass.redesign.hero.scrollVeil YES,
// checks the veil on; `veil-card`, with the page's full cover switched off as well, checks it on the square cover;
// `veil-off`, without it, checks that nothing of it is drawn.
//
// From `start` seconds the page is put at d = 0, 190 and 400 (and, with the veil on, at "mid": the title half under the
// top bar), each held 1.5 s after a "[harness] SHOT <page>-<mode>-<d>" line for the run script to take a screenshot on
// (veil-check.sh). Then the literal checks run, and the harness logs a
// PASS line and exits 0, or a FAIL line and exits 1 (../harness-fail.h).
#import <UIKit/UIKit.h>
#import "../harness-fail.h"

static UIView *veilFind(UIView *root, NSString *className) {
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:root];
    while (queue.count) {
        UIView *v = queue.firstObject;
        [queue removeObjectAtIndex:0];
        if ([NSStringFromClass(v.class) isEqualToString:className]) return v;
        [queue addObjectsFromArray:v.subviews];
    }
    return nil;
}

// What the hero draws: the blur's radius on its layer (0 with no filter on it), the dim's alpha (0 hidden or absent).
static CGFloat veilRadius(UIView *hero) {
    if (!hero.layer.filters.count) return 0;
    return [[hero.layer valueForKeyPath:@"filters.gaussianBlur.inputRadius"] doubleValue];
}

static CALayer *veilDim(UIView *hero) {
    for (CALayer *layer in hero.layer.sublayers) {
        if ([layer.name isEqualToString:@"SGRHeroVeil.dim"]) return layer;
    }
    return nil;
}

static CGFloat veilAlpha(UIView *hero) {
    CALayer *dim = veilDim(hero);
    return !dim || dim.hidden ? 0 : dim.opacity;
}

static BOOL veilNear(CGFloat a, CGFloat b) {
    return fabs(a - b) < 0.001;
}

// The run the launch line asks for: "veil", "veil-card" (the veil on and the page's covers square, its full cover
// switched off on the launch line too), "veil-off", or nil for none.
static NSString *veilMode(void) {
    NSArray<NSString *> *arguments = NSProcessInfo.processInfo.arguments;
    for (NSString *mode in @[@"veil", @"veil-card", @"veil-off"]) {
        if ([arguments containsObject:mode]) return mode;
    }
    return nil;
}

// The window's pinned top bar line, the top safe area and 44pt under it.
static CGFloat veilBarLine(UIView *view) {
    return view.window.safeAreaInsets.top + 44;
}

// The header's topmost label with text, its title.
static UILabel *veilTitle(UIView *info) {
    UILabel *top = nil;
    for (UIView *v in info.subviews) {
        if ([v isKindOfClass:UILabel.class] && !v.hidden && ((UILabel *)v).text.length && (!top || CGRectGetMinY(v.frame) < CGRectGetMinY(top.frame)))
            top = (UILabel *)v;
    }
    return top;
}

// The mask's alpha as drawn on row `row` of its own points, from its top.
static CGFloat veilMaskAlpha(CALayer *mask, NSInteger row) {
    size_t height = (size_t)ceil(mask.bounds.size.height);
    if ((size_t)row >= height) HARNESS_FAIL(@"the clip is %zu points tall, no row %ld", height, (long)row);
    NSMutableData *pixels = [NSMutableData dataWithLength:height];
    CGContextRef context = CGBitmapContextCreate(pixels.mutableBytes, 1, height, 8, 1, NULL, (CGBitmapInfo)kCGImageAlphaOnly);
    CGContextTranslateCTM(context, 0, height);
    CGContextScaleCTM(context, 1, -1);
    [mask renderInContext:context];
    CGContextRelease(context);
    return ((const uint8_t *)pixels.bytes)[row] / 255.0;
}

// The d at which the bar line crosses the middle of the title, measured with the page put back at rest.
static CGFloat veilMidDistance(UIView *root, void (^place)(CGFloat d)) {
    place(0);
    UIView *info = veilFind(root, @"SGRHeaderInfo");
    UILabel *title = veilTitle(info);
    HARNESS_CHECK(title);
    CGFloat top = [title convertPoint:CGPointZero toView:nil].y;
    return round(top - veilBarLine(info) + title.bounds.size.height / 2);
}

// `place` puts the page at d points scrolled (negative: pulled down that far). The art is the hero's first subview,
// its picture. `surfaceOf` gives the view the blur and the dim are on, from the hero (nil: the hero itself); `zooms`
// is NO for a hero that stretches with a pull itself (the playlist's), `moves` NO for a picture placed by Spotify
// (the playlist's square), which is then checked unmoved.
static void veilRun(UIView *root, NSString *page, NSString *mode, BOOL zooms, BOOL moves, NSTimeInterval start,
                    UIView *(^surfaceOf)(UIView *hero), void (^positionPage)(CGFloat d)) {
    BOOL on = ![mode isEqualToString:@"veil-off"];
    NSString *heroClass = [NSString stringWithFormat:@"SGR%@%@Hero", [page substringToIndex:1].uppercaseString, [page substringFromIndex:1]];
    void (^place)(CGFloat) = ^(CGFloat d) {
        positionPage(d);
        [veilFind(root, heroClass) layoutIfNeeded];
    };
    UIView *(^surface)(UIView *) = ^UIView *(UIView *hero) { return surfaceOf ? surfaceOf(hero) : hero; };
    // d = 0, 190, 400, then on with the veil a d where the title is half under the bar line, measured at rest.
    NSUInteger count = on ? 4 : 3;
    for (NSUInteger i = 0; i < count; i++) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((start + 1.5 * i) * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            NSString *name;
            CGFloat d;
            if (i < 3) {
                d = (CGFloat[]){0, 190, 400}[i];
                name = [NSString stringWithFormat:@"%.0f", d];
            } else {
                d = veilMidDistance(root, place);
                name = @"mid";
            }
            place(d);
            UIView *hero = veilFind(root, heroClass);
            NSLog(@"[harness] %@ %@ d=%.0f: radius %.2f, dim %.3f", page, mode, d, veilRadius(surface(hero)), veilAlpha(surface(hero)));
            NSLog(@"[harness] SHOT %@-%@-%@", page, mode, name);
        });
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((start + 1.5 * count) * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIView *hero = veilFind(root, heroClass), *info = veilFind(root, @"SGRHeaderInfo");
        HARNESS_CHECK(hero && hero.window && info);
        UIView *drawnOn = surface(hero);
        HARNESS_CHECK(drawnOn && drawnOn.window);
        BOOL stretches = [hero respondsToSelector:NSSelectorFromString(@"restHeight")];
        UIView *content = stretches ? [hero valueForKey:@"content"] : hero;
        CALayer *art = content.subviews.firstObject.layer;
        HARNESS_CHECK(art);
        if (stretches) {
            place(0);
            CGRect restFrame = hero.frame;
            for (NSNumber *offset in @[@-40, @-100, @0, @-40, @0]) {
                CGFloat d = offset.doubleValue;
                place(d);
                if (!veilNear(hero.frame.origin.y, d) ||
                    !veilNear(CGRectGetMaxY(hero.frame), CGRectGetMaxY(restFrame)) ||
                    !veilNear(hero.frame.size.height, restFrame.size.height - d))
                    HARNESS_FAIL(@"pull/release geometry at %@: %@, rest %@", offset,
                                 NSStringFromCGRect(hero.frame), NSStringFromCGRect(restFrame));
                HARNESS_CHECK(hero.clipsToBounds);
            }
            NSLog(@"[harness] PASS %@ pull/release geometry: top anchored, bottom fixed, exact rest after repeated pulls", page);
        }
        if (!on) {
            // The album clips its text at the pinned bar independently of the artwork veil.
            BOOL album = [page isEqualToString:@"album"];
            UILabel *title = album ? veilTitle(info) : nil;
            if (album) HARNESS_CHECK(title);
            for (NSNumber *d in @[@0, @190, @400, @-40]) {
                place(d.doubleValue);
                HARNESS_CHECK(!hero.layer.filters.count && !veilDim(hero));
                HARNESS_CHECK(CGAffineTransformIsIdentity(art.affineTransform));
                if (album && [title convertPoint:CGPointZero toView:nil].y < veilBarLine(info)) {
                    CALayer *mask = info.layer.mask;
                    CGFloat line = [info convertPoint:CGPointMake(0, veilBarLine(info)) fromView:nil].y;
                    if (![mask isKindOfClass:CAGradientLayer.class] || !veilNear(CGRectGetMinY(mask.frame), line))
                        HARNESS_FAIL(@"at d=%@ expected the album header clip at %.2f, got %@", d, line, mask);
                } else {
                    HARNESS_CHECK(!info.layer.mask);
                }
            }
            place(0);
            if (album) HARNESS_CHECK(!info.layer.mask);
            NSLog(@"[harness] PASS %@ veil off: no blur, no dim, the picture unmoved and the header %@",
                  page, album ? @"clipped only under the bar" : @"unclipped");
            exit(0);
        }
        // The blur's radius and the dim's alpha at the spec's distances, on the surface.
        NSDictionary<NSNumber *, NSNumber *> *radii = @{@0: @0, @60: @0, @190: @12, @320: @24, @400: @24};
        for (NSNumber *d in @[@0, @60, @190, @320, @400]) {
            place(d.doubleValue);
            if (!veilNear(veilRadius(drawnOn), radii[d].doubleValue))
                HARNESS_FAIL(@"radius at d=%@ is %.3f, not %@", d, veilRadius(drawnOn), radii[d]);
        }
        NSDictionary<NSNumber *, NSNumber *> *alphas = @{@0: @0, @80: @0, @240: @0.225, @400: @0.45};
        for (NSNumber *d in @[@0, @80, @240, @400]) {
            place(d.doubleValue);
            if (!veilNear(veilAlpha(drawnOn), alphas[d].doubleValue))
                HARNESS_FAIL(@"dim at d=%@ is %.4f, not %@", d, veilAlpha(drawnOn), alphas[d]);
        }
        // Over exactly the surface; a square's page around it neither blurred nor dimmed.
        if (!CGRectEqualToRect(veilDim(drawnOn).frame, drawnOn.layer.bounds))
            HARNESS_FAIL(@"the dim covers %@, not the surface's %@", NSStringFromCGRect(veilDim(drawnOn).frame), NSStringFromCGRect(drawnOn.layer.bounds));
        if (drawnOn != hero) HARNESS_CHECK(!hero.layer.filters.count && !veilDim(hero));
        // The dim in the page's color, the one the hero dissolves into (the playlist's hero masks its dissolve instead).
        if ([hero respondsToSelector:@selector(fieldColor)]) {
            UIColor *page = [hero valueForKey:@"fieldColor"];
            HARNESS_CHECK(page && CGColorEqualToColor(veilDim(drawnOn).backgroundColor, page.CGColor));
        }
        // Scrolled 190 with the hero, the picture keeps back a quarter of it; a square stays where the page puts it.
        place(0);
        CGRect rest = art.frame;
        place(190);
        if (moves) {
            if (!veilNear(CGRectGetMinY(art.frame) - CGRectGetMinY(rest), 47.5))
                HARNESS_FAIL(@"picture at d=190 moved %.2f, not 47.5", CGRectGetMinY(art.frame) - CGRectGetMinY(rest));
        } else if (!CGAffineTransformIsIdentity(art.affineTransform) || !CGAffineTransformIsIdentity(drawnOn.layer.affineTransform)) {
            HARNESS_FAIL(@"at d=190 the square is moved");
        }
        // Pulled 40: the picture scaled (h + 40) / h about the hero's top and 20 up, so a full bleed one runs from
        // 20 over the hero's top to 20 under its bottom.
        place(-40);
        CGFloat height = hero.bounds.size.height, scale = (height + 40) / height;
        if (zooms && moves) {
            CGFloat top = CGRectGetMinY(rest) * scale - 20, bottom = CGRectGetMaxY(rest) * scale - 20;
            if (!veilNear(CGRectGetMinY(art.frame), top) || !veilNear(CGRectGetMaxY(art.frame), bottom))
                HARNESS_FAIL(@"pulled 40, the picture spans %.2f to %.2f, not %.2f to %.2f", CGRectGetMinY(art.frame), CGRectGetMaxY(art.frame), top, bottom);
        } else {
            HARNESS_CHECK(CGAffineTransformIsIdentity(art.affineTransform) && CGAffineTransformIsIdentity(drawnOn.layer.affineTransform));
        }
        HARNESS_CHECK(veilRadius(drawnOn) == 0 && veilAlpha(drawnOn) == 0);
        // The header's text clipped under the top bar, at the top safe area and 44pt under it, and only then: clear at
        // the line, half at 7pt under it, whole by 14pt under it (the rows' middles at 0.5, 7.5 and 13.5pt).
        place(0);
        HARNESS_CHECK(!info.layer.mask);
        place(400);
        CALayer *mask = info.layer.mask;
        CGFloat line = [info convertPoint:CGPointMake(0, veilBarLine(info)) fromView:nil].y;
        if (!mask || !veilNear(CGRectGetMinY(mask.frame), line))
            HARNESS_FAIL(@"at d=400 the header is clipped at %@, not at %.2f", mask ? @(CGRectGetMinY(mask.frame)) : @"nothing", line);
        CGFloat atLine = veilMaskAlpha(mask, 0), half = veilMaskAlpha(mask, 7), whole = veilMaskAlpha(mask, 13);
        if (atLine > 0.08 || fabs(half - 0.5) > 0.1 || whole < 0.93)
            HARNESS_FAIL(@"the clip's alpha is %.2f at the line, %.2f 7pt under, %.2f 13pt under; not clear, half, whole", atLine, half, whole);
        // Scrolled on at the same header size, the clip's top follows the line and nothing of it is built again: the
        // same mask with the same stop and color arrays and the same bounds. From the title
        // half under the line, so most of the header is still under it, down to d = 400.
        CGFloat mid = veilMidDistance(root, place);
        place(mid);
        CAGradientLayer *clip = (CAGradientLayer *)info.layer.mask;
        HARNESS_CHECK(clip == (CAGradientLayer *)mask && [clip isKindOfClass:CAGradientLayer.class]);
        NSArray *stops = clip.locations, *colors = clip.colors;
        CGRect bounds = clip.bounds;
        CGSize size = info.bounds.size;
        for (NSNumber *d in @[@(mid + 12), @(mid + 24), @(mid + 36), @400]) {
            place(d.doubleValue);
            if (!CGSizeEqualToSize(info.bounds.size, size))
                HARNESS_FAIL(@"at d=%@ the header is %@, not %@ as at d=%.0f", d, NSStringFromCGSize(info.bounds.size), NSStringFromCGSize(size), mid);
            CGFloat at = [info convertPoint:CGPointMake(0, veilBarLine(info)) fromView:nil].y;
            if (info.layer.mask != clip || !veilNear(CGRectGetMinY(clip.frame), at))
                HARNESS_FAIL(@"at d=%@ the header is not clipped by the same mask at %.2f", d, at);
            if (clip.locations != stops || clip.colors != colors || !CGRectEqualToRect(clip.bounds, bounds))
                HARNESS_FAIL(@"at d=%@ the clip was built again: stops %@, colors %@, bounds %@ (were %@)", d,
                             clip.locations == stops ? @"kept" : @"new", clip.colors == colors ? @"kept" : @"new",
                             NSStringFromCGRect(clip.bounds), NSStringFromCGRect(bounds));
        }
        place(0);
        HARNESS_CHECK(!info.layer.mask && veilRadius(drawnOn) == 0 && veilAlpha(drawnOn) == 0);
        NSLog(@"[harness] PASS %@ %@: radius 0/0/12/24/24 at d = 0/60/190/320/400, dim 0/0/0.225/0.45 at 0/80/240/400 on %@, "
              "picture %@, %@ pulled 40, header faded in under the top bar (alpha %.2f/%.2f/%.2f at 0/7/13pt) at d = 400, "
              "the same clip moved and not built again from d = %.0f by 12s and at 400, and not at rest", page, mode,
              drawnOn == hero ? @"the hero" : NSStringFromClass(drawnOn.class),
              moves ? @"moved 47.5 scrolled 190" : @"left in place", zooms && moves ? @"zoomed (h + 40) / h" : @"not zoomed",
              atLine, half, whole, mid);
        exit(0);
    });
}
