// The album track rows' ⋯ in the page's colour (Redesigned/Album/AlbumRows.x), on the mocked page: `more` on the launch
// line, best with `-coverFixture colourful -spotifyglass.redesign.album.motion NO` for a page with a hue. Once the
// page's field has its colour, rows of the list get a ⋯ glyph each: white dots baked into the picture, Spotify's
// template symbol, none that then lands late, baked dots replaced by a baked square, none at all, baked dots under a
// mask someone else put there, and baked dots and the template symbol on rows then reused for another element. Their pixels, drawn as the screen
// draws them, are measured in OKLab worked out here against the spec: lightness 0.80 (0.88 with Increase Contrast),
// the page's hue, its chroma held to 0.08 -- and white where the glyph is to be left alone. The ⋯'s action fires once
// and what VoiceOver reads of it is what it was. "[harness] SHOT album-more" holds the page 1.5 s for a screenshot.
// Logs "[harness] PASS album more ..." and exits 0, or a FAIL line and exits 1.
#import <objc/runtime.h>
#import "pixel-check.h"

// The baked glyph's 24pt picture: three dots 6pt across on its middle line, at these x, or one 8pt square in the middle.
static const CGFloat kMoreDots[] = {5, 12, 19};
static const CGFloat kMoreDot = 6, kMoreSquare = 8, kMoreSide = 24;

static UIImage *moreBaked(BOOL square) {
    UIImage *image = [[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(kMoreSide, kMoreSide)] imageWithActions:^(UIGraphicsImageRendererContext *c) {
        [UIColor.whiteColor setFill];
        if (square) {
            UIRectFill(CGRectMake((kMoreSide - kMoreSquare) / 2, (kMoreSide - kMoreSquare) / 2, kMoreSquare, kMoreSquare));
            return;
        }
        for (int i = 0; i < 3; i++) {
            [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(kMoreDots[i] - kMoreDot / 2, (kMoreSide - kMoreDot) / 2, kMoreDot, kMoreDot)] fill];
        }
    }];
    return [image imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
}

static UIControl *moreButton(UIView *cell) {
    return (UIControl *)checkFind(cell, ^BOOL(UIView *v) { return [v.accessibilityIdentifier hasPrefix:@"Components.UI.ContextMenuButton"]; });
}

static UIImageView *moreGlyph(UIView *cell) {
    return (UIImageView *)checkFind(moreButton(cell), ^BOOL(UIView *v) { return [v isKindOfClass:UIImageView.class]; });
}

static void morePass(UIView *cell) {
    [cell setNeedsLayout];
    [cell layoutIfNeeded];
}

static CheckPixel moreGlyphPixel(UIView *cell, CGPoint inGlyph) {
    UIImageView *glyph = moreGlyph(cell);
    return checkPixel(checkRender(cell), [glyph convertPoint:inGlyph toView:cell]);
}

// The page's colour as the spec makes the ⋯'s of it.
typedef struct { CGFloat L, chroma; CheckLab page; } MoreTarget;

// The glyph's pixels at `points` are the ⋯'s colour: lightness and chroma near the target's, on the page's hue. A
// template glyph under Increase Contrast is drawn lighter still: UIKit raises a tint itself for it (its tintColor reads
// back lighter than it was set), so `raised` lets the lightness go up to 0.06 over the target.
static void moreExpectTint(NSString *what, UIView *cell, NSArray<NSValue *> *points, MoreTarget target, BOOL raised) {
    UIImage *drawn = checkRender(cell);
    UIImageView *glyph = moreGlyph(cell);
    for (NSValue *point in points) {
        CheckPixel pixel = checkPixel(drawn, [glyph convertPoint:point.CGPointValue toView:cell]);
        CheckLab lab = checkLab(pixel.r, pixel.g, pixel.b);
        CGFloat chroma = checkChroma(lab), hue = checkHueGap(lab, target.page);
        // Chroma at most the cap (less where sRGB holds less at that lightness), and still the page's colour, not gray.
        BOOL lightness = raised ? lab.L > target.L - 0.02 && lab.L < target.L + 0.06 : fabs(lab.L - target.L) <= 0.02;
        if (pixel.a < 0.9 || !lightness || chroma > target.chroma + 0.01 || chroma < target.chroma / 2 || hue > 12)
            HARNESS_FAIL(@"%@ ⋯: at %@ L %.3f C %.3f hue %.1f° off the page's (alpha %.2f), expected L %.2f, C up to %.3f (glyph tint %@)", what,
                         NSStringFromCGPoint(point.CGPointValue), lab.L, chroma, hue, pixel.a, target.L, target.chroma, glyph.tintColor);
    }
    NSLog(@"[harness] %@ ⋯: in the page's colour at %lu points", what, (unsigned long)points.count);
}

static void moreExpectWhite(NSString *what, UIView *cell, CGPoint point) {
    CheckPixel pixel = moreGlyphPixel(cell, point);
    CheckLab lab = checkLab(pixel.r, pixel.g, pixel.b);
    if (pixel.a < 0.9 || lab.L < 0.97 || checkChroma(lab) > 0.01)
        HARNESS_FAIL(@"%@ ⋯: at %@ L %.3f C %.3f alpha %.2f, expected Spotify's white", what, NSStringFromCGPoint(point), lab.L, checkChroma(lab), pixel.a);
    NSLog(@"[harness] %@ ⋯: left as Spotify drew it", what);
}

static void moreExpectClear(NSString *what, UIView *cell, CGPoint point) {
    CheckPixel pixel = moreGlyphPixel(cell, point);
    if (pixel.a > 0.2) HARNESS_FAIL(@"%@ ⋯: at %@ something is drawn (alpha %.2f)", what, NSStringFromCGPoint(point), pixel.a);
}

static NSArray<NSValue *> *moreDots(void) {
    return @[[NSValue valueWithCGPoint:CGPointMake(kMoreDots[0], 12)], [NSValue valueWithCGPoint:CGPointMake(kMoreDots[1], 12)],
             [NSValue valueWithCGPoint:CGPointMake(kMoreDots[2], 12)]];
}

// The target for the page's colour now: the ⋯ follows the page as its colour arrives.
static MoreTarget moreTarget(UIColor *colour) {
    CGFloat r, g, b, a;
    HARNESS_CHECK([colour getRed:&r green:&g blue:&b alpha:&a]);
    CheckLab lab = checkLab(r, g, b);
    MoreTarget target = {UIAccessibilityDarkerSystemColorsEnabled() ? 0.88 : 0.80, MIN(checkChroma(lab), 0.08), lab};
    if (target.chroma < 0.03) HARNESS_FAIL(@"the page's colour %@ has no hue to check (C %.3f)", colour, checkChroma(lab));
    return target;
}

static void moreRun(UIView *root, NSArray<UICollectionViewCell *> *cells, UIColor *(^pageColour)(void)) {
    UIView *baked = cells[1], *symbol = cells[2], *late = cells[3], *replaced = cells[4], *none = cells[5], *foreign = cells[6], *reused = cells[7], *reusedSymbol = cells[8];
    __block CALayer *foreignMask;
    __block NSUInteger fired = 0;
    __block NSString *spoken;
    __block UIAccessibilityTraits traits;
    __block BOOL element;
    NSValue *middle = [NSValue valueWithCGPoint:CGPointMake(12, 12)];
    MoreTarget (^target)(void) = ^{ return moreTarget(pageColour()); };
    {
        MoreTarget now = target();
        NSLog(@"[harness] more: page L %.3f C %.3f, target L %.2f C %.3f%@", now.page.L, checkChroma(now.page), now.L, now.chroma,
              UIAccessibilityDarkerSystemColorsEnabled() ? @" (Increase Contrast)" : @"");

        UIControl *button = moreButton(baked);
        spoken = button.accessibilityLabel;
        traits = button.accessibilityTraits;
        element = button.isAccessibilityElement;
        [button addAction:[UIAction actionWithHandler:^(UIAction *action) { fired++; }] forControlEvents:UIControlEventTouchUpInside];
        // Spotify's symbol at its own aspect, as its row draws it; the mock's button would stretch it.
        for (UIView *cell in cells) moreGlyph(cell).contentMode = UIViewContentModeScaleAspectFit;
        moreGlyph(baked).image = moreBaked(NO);
        moreGlyph(late).image = nil;
        moreGlyph(replaced).image = moreBaked(NO);
        moreGlyph(none).image = nil;
        moreGlyph(foreign).image = moreBaked(NO);
        foreignMask = [CALayer layer];
        foreignMask.backgroundColor = UIColor.blackColor.CGColor;
        foreignMask.frame = moreGlyph(foreign).bounds;
        moreGlyph(foreign).layer.mask = foreignMask;
        moreGlyph(reused).image = moreBaked(NO);
        for (UIView *cell in cells) morePass(cell);

        checkSteps(@[^{
            HARNESS_AWAIT(moreGlyph(baked).layer.mask != nil);
            moreExpectTint(@"baked", baked, moreDots(), target(), NO);
            // Through the glyph's own picture: between two dots nothing.
            moreExpectClear(@"baked, between the dots", baked, CGPointMake((kMoreDots[0] + kMoreDots[1]) / 2, 12));
            moreExpectTint(@"template", symbol, @[middle], target(), UIAccessibilityDarkerSystemColorsEnabled());
            moreExpectTint(@"to be replaced", replaced, moreDots(), target(), NO);
            moreExpectTint(@"to be reused", reused, moreDots(), target(), NO);
            moreExpectTint(@"template, to be reused", reusedSymbol, @[middle], target(), UIAccessibilityDarkerSystemColorsEnabled());
            moreExpectClear(@"no picture", none, middle.CGPointValue);
            if (moreGlyph(foreign).layer.mask != foreignMask) HARNESS_FAIL(@"the glyph's own mask was replaced");
            moreExpectWhite(@"under a mask of its own", foreign, middle.CGPointValue);
            UIControl *again = moreButton(baked);
            if (![again.accessibilityLabel isEqualToString:spoken] || again.accessibilityTraits != traits || again.isAccessibilityElement != element)
                HARNESS_FAIL(@"⋯ reads \"%@\" (traits %llu, element %d), was \"%@\" (%llu, %d)", again.accessibilityLabel,
                             again.accessibilityTraits, again.isAccessibilityElement, spoken, traits, element);
            if (again.layer.shouldRasterize || moreGlyph(baked).layer.shouldRasterize) HARNESS_FAIL(@"⋯ was rasterized");
            [again sendActionsForControlEvents:UIControlEventTouchUpInside];
            if (fired != 1) HARNESS_FAIL(@"⋯'s action ran %lu times", (unsigned long)fired);
            // Lands with the row laid out and nothing laying it out again.
            moreGlyph(late).image = moreBaked(NO);
        }, ^{
            HARNESS_AWAIT(moreGlyph(late).layer.mask != nil);
            moreExpectTint(@"landed late", late, moreDots(), target(), NO);
            checkShot(@"album-more");
        }, ^{
            moreGlyph(replaced).image = moreBaked(YES);
        }, ^{
            moreExpectTint(@"replaced", replaced, @[middle], target(), NO);
            moreExpectClear(@"replaced, where the old dot was", replaced, CGPointMake(kMoreDots[0], 12));
            // Reused for something that is not an album's track row (a cell keeps its list, and its list its page): the
            // element it holds is some other one's now, the old row still in it.
            for (UICollectionViewCell *cell in @[reused, reusedSymbol]) {
                object_setClass(cell.contentView.subviews.firstObject, UIView.class);
                [cell prepareForReuse];
                morePass(cell);
            }
        }, ^{
            moreExpectWhite(@"reused as no album track row", reused, CGPointMake(kMoreDots[1], 12));
            moreExpectWhite(@"template, reused as no album track row", reusedSymbol, middle.CGPointValue);
            if (moreGlyph(reused).layer.mask) HARNESS_FAIL(@"the glyph reused as no album track row keeps a mask");
            NSString *pass = [NSString stringWithFormat:@"[harness] PASS album more: ⋯ at L %.2f C %.3f on the page's hue, baked, template, "
                              @"late, replaced; left alone without a picture, under its own mask and reused as no track row; action and VoiceOver kept",
                              target().L, target().chroma];
            NSLog(@"%@", pass);
            fprintf(stderr, "%s\n", pass.UTF8String);
            exit(0);
        }], 0);
    }
}
