// `search` (README): Search, the last of five tabs, on the minimized bar's trailing circle beside the now playing card,
// as the Music app keeps it (issue #34). TabBar.x knows Search by the page Spotify's list of tabs names for it
// (SGRNavbarStockURIs), which Navbar.x reads off Spotify and the harness hands it here as 9.2.0 (`spotify:search`) or,
// with `find`, 9.1.78 to 9.1.90 (`spotify:find`) name it. Every frame of each move is sampled: one Search glyph on
// screen throughout, moving no more than a spring does, the circle coming out of Search's place in the row, and no
// glass partly faded. `splitcreate` makes Create a split tab, `nosearch` hides Search, and `own` hides it and adds a tab
// of the mod's own named Search after it: the minimized bar as it was, the last split tab or nothing on the trailing
// circle. `labels` shows the tabs' names; `middle` puts Search third, so it travels the row's width to the circle.
// `leaves` takes Search out of Spotify's row and back while the bar is minimized. `capture` holds one expand for
// capture.sh to record.
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import "../harness-fail.h"
#import "Core/SGViewTree.h"
#import "Redesigned/Navbar/Navbar.h"

extern CGRect SGRNowPlayingCardFrameIn(UIView *host, CGFloat *radius);
extern void SGHarnessTap(UIWindow *window, CGPoint point);

// The Music app's minimized bar as the redesign draws it on an iPhone 17 Pro: a 62 pt circle 21 pt in from each side,
// each on a bar 104 pt wide (a split tab's), and the card 8 pt from each circle; without a trailing circle the card
// ends 21 pt in from the side.
static const CGFloat kCirclePt = 62, kSideInsetPt = 21, kCircleBarPt = 104, kCardGapPt = 8;
// A critically damped spring moving the platter's 298 pt peaks at some 50 pt a frame (README, `motion`).
static const CGFloat kLargestStepPt = 50;
// How far from Search's glyph the trailing circle may be the first frame it is shown: it carries the glyph out of the
// row, whose steps the spring bounds.
static const CGFloat kComesOutWithinPt = 8;
// A glyph showing more than this share of itself (area left by the views that clip it, times its opacity) is drawn,
// and the one Search glyph of a frame shows at least kShownFraction of itself.
static const CGFloat kDrawnFraction = 0.02, kShownFraction = 0.9;

static __weak UIView *sgStock;

static void after(double seconds, dispatch_block_t block) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(seconds * NSEC_PER_SEC)), dispatch_get_main_queue(), block);
}

static NSArray<NSString *> *launchWords(void) {
    return NSProcessInfo.processInfo.arguments;
}

static BOOL said(NSString *word) {
    return [launchWords() containsObject:word];
}

// A failed check ends the run, or with `keepgoing` is printed and its case left for the next one, the run ending with
// the failures counted: each case's own failure shows on a tree built from before the change (README, SRC=).
static NSUInteger sgFailures;
#define CASE_FAIL(...) do { \
    if (!said(@"keepgoing")) HARNESS_FAIL(__VA_ARGS__); \
    printf("FAIL %s\n", [NSString stringWithFormat:__VA_ARGS__].UTF8String); \
    fflush(stdout); \
    sgFailures++; \
    return; \
} while (0)
// The same in a check that answers whether it passed.
#define CASE_FAIL_NO(...) do { \
    if (!said(@"keepgoing")) HARNESS_FAIL(__VA_ARGS__); \
    printf("FAIL %s\n", [NSString stringWithFormat:__VA_ARGS__].UTF8String); \
    fflush(stdout); \
    sgFailures++; \
    return NO; \
} while (0)

#pragma mark - the glass bars

static NSArray<UITabBar *> *allBars(void) {
    NSMutableArray<UITabBar *> *bars = [NSMutableArray array];
    SGForEachView(sgStock, ^(UIView *v) {
        if ([v isKindOfClass:UITabBar.class]) [bars addObject:(UITabBar *)v];
    });
    return bars;
}

static CGRect inWindow(UIView *v) {
    return [v convertRect:v.bounds toView:nil];
}

// The bars on screen, left to right.
static NSArray<UITabBar *> *shownBars(void) {
    NSMutableArray<UITabBar *> *bars = [NSMutableArray array];
    for (UITabBar *bar in allBars()) if (!bar.hidden && bar.window) [bars addObject:bar];
    return [bars sortedArrayUsingComparator:^NSComparisonResult(UITabBar *a, UITabBar *b) {
        return [@(CGRectGetMinX(inWindow(a))) compare:@(CGRectGetMinX(inWindow(b)))];
    }];
}

static UIView *platterOf(UIView *bar) {
    __block UIView *found = nil;
    SGForEachView(bar, ^(UIView *v) {
        if (!found && [NSStringFromClass(v.class) hasSuffix:@"PlatterView"]) found = v;
    });
    return found;
}

// UIKit draws every tab twice, the second copy lit under the selection's bubble.
static BOOL isLitCopy(UIView *view, UIView *bar) {
    for (UIView *up = view.superview; up && up != bar; up = up.superview) {
        if ([NSStringFromClass(up.class) containsString:@"SelectedContent"]) return YES;
    }
    return NO;
}

static UIImageView *glyphIn(UIView *button) {
    __block UIImageView *glyph = nil;
    SGForEachView(button, ^(UIView *v) {
        if (!glyph && [v isKindOfClass:UIImageView.class] && !v.hidden && ((UIImageView *)v).image) glyph = (UIImageView *)v;
    });
    return glyph;
}

static BOOL isButton(UIView *v) {
    return [v isKindOfClass:UIControl.class] && glyphIn(v);
}

// The item a plain tab button draws: UIKit keeps the buttons in the items' order.
static UITabBarItem *itemOf(UITabBar *bar, UIView *button) {
    NSMutableArray<UIView *> *buttons = [NSMutableArray array];
    for (UIView *sibling in button.superview.subviews) if (isButton(sibling)) [buttons addObject:sibling];
    return buttons.count == bar.items.count ? bar.items[[buttons indexOfObject:button]] : nil;
}

static NSArray<NSString *> *namesOf(UITabBar *bar) {
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (UITabBarItem *item in bar.items) [names addObject:item.accessibilityLabel ?: @"?"];
    return names;
}

// The plain buttons of a tab named `name`, on any bar, hidden or not.
static NSArray<UIView *> *buttonsNamed(NSString *name) {
    NSMutableArray<UIView *> *found = [NSMutableArray array];
    for (UITabBar *bar in allBars()) {
        SGForEachView(bar, ^(UIView *v) {
            if (isButton(v) && !isLitCopy(v, bar) && [itemOf(bar, v).accessibilityLabel isEqualToString:name]) [found addObject:v];
        });
    }
    return found;
}

// What the screen shows of a view: its opacity with every view above it, and its frame in `top`.
static CGFloat shownOpacity(UIView *view) {
    CGFloat opacity = 1;
    for (UIView *up = view; up; up = up.superview) {
        if (up.hidden) return 0;
        opacity *= (up.layer.presentationLayer ?: up.layer).opacity;
    }
    return opacity;
}

// CGRectNull for a view made since the screen last drew, whose presentation layer is not in the drawn tree yet.
static CGRect shownFrame(UIView *view, UIView *top) {
    CALayer *layer = view.layer.presentationLayer, *topLayer = top.layer.presentationLayer ?: top.layer;
    if (!layer || (view.superview && !layer.superlayer)) return CGRectNull;
    return [layer convertRect:layer.bounds toLayer:topLayer];
}

static UIView *barHost(void);

// The glass of the bars drawn over `view`: the platters, in the window, of every bar standing after the one it is in (or
// after the picture it is) among the bars' host's views. A glyph under another bar's glass shows only blurred through it.
static NSArray<NSValue *> *glassOver(UIView *view) {
    UIView *host = barHost(), *own = view;
    while (own && own.superview != host) own = own.superview;
    NSMutableArray<NSValue *> *glass = [NSMutableArray array];
    if (!own) return glass;
    NSArray<UIView *> *views = host.subviews;
    for (NSUInteger i = [views indexOfObject:own] + 1; i < views.count; i++) {
        if (![views[i] isKindOfClass:UITabBar.class]) continue;
        SGForEachView(views[i], ^(UIView *v) {
            if (![NSStringFromClass(v.class) hasSuffix:@"PlatterView"] || shownOpacity(v) <= kDrawnFraction) return;
            CGRect frame = shownFrame(v, view.window);
            if (!CGRectIsNull(frame)) [glass addObject:[NSValue valueWithCGRect:frame]];
        });
    }
    return glass;
}

// UIKit's glass platters are capsules: a circle on a minimized bar, a row with round ends expanded.
static BOOL inCapsule(CGPoint point, CGRect capsule) {
    CGFloat radius = MIN(capsule.size.width, capsule.size.height) / 2;
    CGFloat x = MIN(MAX(point.x, CGRectGetMinX(capsule) + radius), CGRectGetMaxX(capsule) - radius);
    CGFloat y = MIN(MAX(point.y, CGRectGetMinY(capsule) + radius), CGRectGetMaxY(capsule) - radius);
    return hypot(point.x - x, point.y - y) <= radius;
}

// How finely shownFraction samples a view's frame, points along each side.
static const NSUInteger kShownSamples = 20;

// How much of a view the screen shows clearly: the share of its shown frame left inside every view above it that clips
// (its bounds, or its layer's mask) and under no other bar's glass (glassOver), times its opacity through the chain.
// NAN for a view the screen has not drawn yet that it is to draw: its opacity is the one set, not the one the views above
// it were last drawn with.
static CGFloat shownFraction(UIView *view) {
    UIWindow *window = view.window;
    if (!window) return 0;
    CGFloat opacitySet = 1;
    for (UIView *up = view; up; up = up.superview) opacitySet *= up.hidden ? 0 : up.alpha;
    if (opacitySet <= 0) return 0;
    CGRect whole = shownFrame(view, window);
    if (CGRectIsNull(whole)) return NAN;
    CGFloat opacity = shownOpacity(view);
    if (opacity <= 0) return 0;
    if (whole.size.width * whole.size.height <= 0) return 0;
    CALayer *windowLayer = window.layer.presentationLayer ?: window.layer;
    CGRect seen = whole;
    for (UIView *up = view.superview; up && up != window; up = up.superview) {
        CALayer *layer = up.layer.presentationLayer ?: up.layer;
        if (up.layer.masksToBounds) {
            CGRect bounds = shownFrame(up, window);
            if (CGRectIsNull(bounds)) return NAN;
            seen = CGRectIntersection(seen, bounds);
        }
        CALayer *mask = up.layer.mask.presentationLayer ?: up.layer.mask;
        if (mask) seen = CGRectIntersection(seen, [layer convertRect:mask.frame toLayer:windowLayer]);
        if (CGRectIsNull(seen)) return 0;
    }
    NSArray<NSValue *> *glass = glassOver(view);
    NSUInteger clear = 0;
    for (NSUInteger i = 0; i < kShownSamples; i++) {
        for (NSUInteger j = 0; j < kShownSamples; j++) {
            CGPoint point = CGPointMake(CGRectGetMinX(whole) + (i + 0.5) * whole.size.width / kShownSamples,
                                        CGRectGetMinY(whole) + (j + 0.5) * whole.size.height / kShownSamples);
            if (!CGRectContainsPoint(seen, point)) continue;
            BOOL covered = NO;
            for (NSValue *over in glass) covered |= inCapsule(point, over.CGRectValue);
            clear += !covered;
        }
    }
    return (CGFloat)clear / (kShownSamples * kShownSamples) * opacity;
}

static UIView *barHost(void) {
    for (UIView *v in sgStock.subviews) if ([NSStringFromClass(v.class) isEqualToString:@"SGRTabBarHost"]) return v;
    return nil;
}

// The main bar on screen: the one holding Home, the row's first tab.
static UITabBar *rowBar(void) {
    for (UITabBar *bar in shownBars()) if ([namesOf(bar) containsObject:@"Home"]) return bar;
    return nil;
}

// The gap between the outlines of two glass capsules lying along x, negative where they overlap.
static CGFloat capsuleGap(CGRect a, CGRect b) {
    CGFloat ra = MIN(a.size.width, a.size.height) / 2, rb = MIN(b.size.width, b.size.height) / 2;
    CGFloat across = MAX(0, MAX((CGRectGetMinX(a) + ra) - (CGRectGetMaxX(b) - rb), (CGRectGetMinX(b) + rb) - (CGRectGetMaxX(a) - ra)));
    return hypot(across, CGRectGetMidY(a) - CGRectGetMidY(b)) - ra - rb;
}

// How far off touching two capsules read off the screen's layers may be when they are taken to touch: the pixels they
// are rounded to, and the tenth of a millisecond TabBar.x times the circle's glass in, with the row growing some 4 pt
// in it.
static const CGFloat kOverlapSlackPt = 1;

static CGColorRef resolvedTint(UIView *view) {
    return [view.tintColor resolvedColorWithTraitCollection:view.traitCollection].CGColor;
}

// Whether `glyph` is drawn as the row draws Search: its image and color, those of the lit copy when Search is selected.
static BOOL looksLikeRowSearch(UIImageView *glyph) {
    UITabBar *row = rowBar();
    __block UIImageView *shown = nil;
    SGForEachView(row, ^(UIView *v) {
        if (!isButton(v) || isLitCopy(v, row) || ![itemOf(row, v).accessibilityLabel isEqualToString:@"Search"]) return;
        shown = glyphIn(v);
        if (!((UIControl *)v).selected) return;
        SGForEachView(row, ^(UIView *lit) {
            if (isButton(lit) && isLitCopy(lit, row) && ((UIControl *)lit).selected) shown = glyphIn(lit);
        });
    });
    return shown && glyph.image == shown.image && CGColorEqualToColor(resolvedTint(glyph), resolvedTint(shown));
}

#pragma mark - every frame of a move

@interface SGHarnessSearchSampler : NSObject
@property (nonatomic, copy) NSString *moment;
@property (nonatomic, strong) CADisplayLink *link;
@property (nonatomic, copy) NSArray<NSValue *> *searchFrames;   // Search's buttons as the move began, in the bars' host
@property (nonatomic) NSUInteger frames, fewest, most, faintFrames, fadedGlass, glassOnRow, goneEarly, unlikeRow;
@property (nonatomic) NSUInteger shownBarCount;   // the bars whose glass the last frame drew
// Whether an expand in the move starts from rest, so the circle's glass is to stay until the row reaches it: TabBar.x
// times it by the expand's own spring, which an expand turning a minimize back shares with what is left of the minimize's.
@property (nonatomic) BOOL expandsFromRest;
@property (nonatomic) CGFloat largestStep, comesOutAt, deepestOnRow;
@property (nonatomic) CGFloat circleCenterErrorY;
@property (nonatomic) CGPoint lastGlyph;          // Search's glyph center the last frame it was known, in the window
@property (nonatomic) NSTimeInterval lastTick;     // and when
@end

@implementation SGHarnessSearchSampler

- (void)begin:(NSString *)moment {
    self.moment = moment;
    UIView *host = barHost();
    NSMutableArray<NSValue *> *frames = [NSMutableArray array];
    self.lastGlyph = CGPointMake(NAN, NAN);
    for (UIView *button in buttonsNamed(@"Search")) {
        if (shownOpacity(button) <= 0.01) continue;
        [frames addObject:[NSValue valueWithCGRect:shownFrame(button, host)]];
        CGRect glyph = shownFrame(glyphIn(button), sgStock.window);
        if (!CGRectIsNull(glyph)) self.lastGlyph = CGPointMake(CGRectGetMidX(glyph), CGRectGetMidY(glyph));
    }
    self.searchFrames = frames;
    self.frames = 0;
    self.fewest = NSUIntegerMax;
    self.most = 0;
    self.faintFrames = 0;
    self.fadedGlass = 0;
    self.glassOnRow = 0;
    self.goneEarly = 0;
    self.expandsFromRest = YES;
    self.deepestOnRow = 0;
    self.circleCenterErrorY = 0;
    self.unlikeRow = 0;
    self.largestStep = 0;
    self.comesOutAt = NAN;
    self.lastTick = CACurrentMediaTime();
    self.shownBarCount = 0;
    for (UITabBar *bar in shownBars()) self.shownBarCount += shownOpacity(platterOf(bar)) > kDrawnFraction;
    self.link = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick)];
    self.link.preferredFrameRateRange = CAFrameRateRangeMake(60, 60, 60);
    [self.link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
}

- (void)tick {
    UIWindow *window = sgStock.window;
    UIView *host = barHost();
    NSTimeInterval time = CACurrentMediaTime();
    self.frames++;

    // Search's glyphs on screen: its buttons on either bar, and the pictures of its buttons that went. Where its glyph
    // is: unknown the frame a button is made, before the screen has drawn it.
    // A glyph counts as drawn by the part of it the screen shows clearly (shownFraction); one not drawn yet counts in
    // full.
    NSUInteger count = 0;
    CGFloat clearest = 0;
    CGPoint glyph = CGPointMake(NAN, NAN);
    for (UIView *button in buttonsNamed(@"Search")) {
        UIImageView *image = glyphIn(button);
        CGFloat fraction = shownFraction(image);
        if (isnan(fraction)) fraction = 1;
        if (fraction <= kDrawnFraction) continue;
        count++;
        clearest = MAX(clearest, fraction);
        CGRect frame = shownFrame(image, window);
        glyph = CGRectIsNull(frame) ? CGPointMake(NAN, NAN) : CGPointMake(CGRectGetMidX(frame), CGRectGetMidY(frame));
    }
    for (UIView *picture in host.subviews) {
        if ([picture isKindOfClass:UITabBar.class]) continue;
        CGFloat fraction = shownFraction(picture);
        if (isnan(fraction)) fraction = 1;
        if (fraction <= kDrawnFraction) continue;
        // Search's glyph travelling on its own, back into the row: the only glyph drawn outside the bars, so it is
        // drawn as the row draws Search, lit when Search is the tab selected.
        if ([picture isKindOfClass:UIImageView.class]) {
            count++;
            clearest = MAX(clearest, fraction);
            CGRect frame = shownFrame(picture, window);
            glyph = CGRectIsNull(frame) ? CGPointMake(NAN, NAN) : CGPointMake(CGRectGetMidX(frame), CGRectGetMidY(frame));
            if (!looksLikeRowSearch((UIImageView *)picture)) self.unlikeRow++;
            continue;
        }
        for (NSValue *frame in self.searchFrames) {
            CGRect was = frame.CGRectValue;
            if (fabs(CGRectGetMidX(picture.frame) - CGRectGetMidX(was)) < 1 && fabs(CGRectGetMidY(picture.frame) - CGRectGetMidY(was)) < 1) {
                count++;
                clearest = MAX(clearest, fraction);
            }
        }
    }
    self.fewest = MIN(self.fewest, count);
    self.most = MAX(self.most, count);
    if (clearest < kShownFraction) self.faintFrames++;
    if (count != 1) {
        self.lastGlyph = CGPointMake(NAN, NAN);
    } else if (!isnan(glyph.x)) {
        // A frame the simulator skipped, or one whose glyph was unknown, counts as that many: the step is per 1/60 s.
        if (!isnan(self.lastGlyph.x)) {
            CGFloat elapsed = MAX(1, round((time - self.lastTick) * 60));
            CGFloat step = MAX(fabs(glyph.x - self.lastGlyph.x), fabs(glyph.y - self.lastGlyph.y)) / elapsed;
            self.largestStep = MAX(self.largestStep, step);
        }
        self.lastGlyph = glyph;
        self.lastTick = time;
    }

    // The glass: never partly faded. The trailing circle, the first frame it is drawn, centered on Search's glyph (the
    // circle is centered on its bar).
    NSArray<UITabBar *> *bars = shownBars();
    NSMutableArray<UITabBar *> *drawn = [NSMutableArray array];
    for (UITabBar *bar in bars) {
        CGFloat opacity = shownOpacity(platterOf(bar));
        if (opacity > 0.02 && opacity < 0.98) self.fadedGlass++;
        if (opacity > kDrawnFraction) [drawn addObject:bar];
    }
    // Expanding, no other glass ever over or under the growing row's, and from rest the circle's glass drawn as long as
    // the row's has not reached it.
    UITabBar *row = rowBar();
    CGRect rowGlass = row ? shownFrame(platterOf(row), window) : CGRectNull;
    if (!SGRTabBarMinimized() && !CGRectIsNull(rowGlass)) {
        for (UITabBar *bar in bars) {
            CGRect glass = bar == row ? CGRectNull : shownFrame(platterOf(bar), window);
            if (CGRectIsNull(glass)) continue;
            CGFloat gap = capsuleGap(rowGlass, glass);
            BOOL drawnGlass = shownOpacity(platterOf(bar)) > kDrawnFraction;
            if (drawnGlass) {
                self.circleCenterErrorY = MAX(self.circleCenterErrorY, fabs(CGRectGetMidY(glass) - CGRectGetMidY(rowGlass)));
            }
            if (drawnGlass && gap < -kOverlapSlackPt) {
                self.glassOnRow++;
                self.deepestOnRow = MAX(self.deepestOnRow, -gap);
            }
            if (!drawnGlass && gap > kOverlapSlackPt && self.expandsFromRest) self.goneEarly++;
        }
    }
    if (drawn.count == 2 && self.shownBarCount == 1) {
        CGRect circle = shownFrame(drawn[1], window);
        if (CGRectIsNull(circle) || count != 1 || isnan(glyph.x)) return;   // measured once the screen has drawn both
        self.comesOutAt = fabs(CGRectGetMidX(circle) - glyph.x);
    }
    self.shownBarCount = drawn.count;
}

// The move's frames: Search drawn once in every one, moving as a spring does, the glass never partly faded, and with
// `comesOut` the trailing circle first shown where Search's glyph was.
- (void)endExpectingCircleToComeOut:(BOOL)comesOut {
    [self.link invalidate];
    NSLog(@"[harness] %@: %lu frames, Search drawn %lu to %lu times, faint in %lu, unlike the row's in %lu, largest step %.1f pt, glass partly faded in %lu, "
          @"other glass on the expanding row in %lu (%.1f pt deep at most), the circle gone before the row reached it in %lu, circle first shown %.1f pt from Search",
          self.moment, (unsigned long)self.frames, (unsigned long)self.fewest, (unsigned long)self.most, (unsigned long)self.faintFrames,
          (unsigned long)self.unlikeRow, self.largestStep, (unsigned long)self.fadedGlass, (unsigned long)self.glassOnRow, self.deepestOnRow, (unsigned long)self.goneEarly, self.comesOutAt);
    if (self.frames < 10) CASE_FAIL(@"%@: only %lu frames sampled", self.moment, (unsigned long)self.frames);
    if (self.fewest != 1 || self.most != 1) CASE_FAIL(@"%@: Search drawn %lu to %lu times in a frame, not once", self.moment, (unsigned long)self.fewest, (unsigned long)self.most);
    if (self.faintFrames) CASE_FAIL(@"%@: Search's glyph mostly clipped, under another bar's glass or clear in %lu frames", self.moment, (unsigned long)self.faintFrames);
    if (self.largestStep > kLargestStepPt) CASE_FAIL(@"%@: Search's glyph jumped %.1f pt in a frame", self.moment, self.largestStep);
    if (self.unlikeRow) CASE_FAIL(@"%@: Search's travelling glyph unlike the row's in %lu frames", self.moment, (unsigned long)self.unlikeRow);
    if (self.fadedGlass) CASE_FAIL(@"%@: glass partly faded in %lu frames", self.moment, (unsigned long)self.fadedGlass);
    if (self.glassOnRow) CASE_FAIL(@"%@: another bar's glass on the expanding row's in %lu frames", self.moment, (unsigned long)self.glassOnRow);
    if (self.circleCenterErrorY > 0.5) CASE_FAIL(@"%@: returning circle off the row's vertical center by %.1f pt", self.moment, self.circleCenterErrorY);
    if (self.goneEarly) CASE_FAIL(@"%@: the circle's glass gone before the expanding row reached it in %lu frames", self.moment, (unsigned long)self.goneEarly);
    if (comesOut && !(self.comesOutAt <= kComesOutWithinPt)) CASE_FAIL(@"%@: the trailing circle was first shown %.1f pt from Search's glyph", self.moment, self.comesOutAt);
    printf("PASS %s: Search drawn once in each of %lu frames\n", self.moment.UTF8String, (unsigned long)self.frames);
    fflush(stdout);
}

@end

#pragma mark - the bar at rest

// The tab named `name` picked on whichever bar shows it, the calls a finger ends in.
static void pick(NSString *name) {
    for (UITabBar *bar in shownBars()) {
        for (UITabBarItem *item in bar.items) {
            if (![item.accessibilityLabel isEqualToString:name]) continue;
            bar.selectedItem = item;
            [bar.delegate tabBar:bar didSelectItem:item];
            return;
        }
    }
    CASE_FAIL(@"no tab named %@ to pick", name);
}

static NSString *selectedName(void) {
    for (UITabBar *bar in shownBars()) if (bar.selectedItem) return bar.selectedItem.accessibilityLabel;
    return nil;
}

// At rest, whatever move came before: nothing drawn among the bars but the bars, every tab's glyph and every glass of
// the bars on screen drawn in full, and every bar on screen taking touches.
static BOOL isClean(NSString *moment) {
    for (UIView *view in barHost().subviews) {
        if (![view isKindOfClass:UITabBar.class]) CASE_FAIL_NO(@"%@: a %@ left among the bars at %@", moment, NSStringFromClass(view.class), NSStringFromCGRect(view.frame));
    }
    for (UITabBar *bar in shownBars()) {
        if (!bar.userInteractionEnabled) CASE_FAIL_NO(@"%@: the bar holding %@ takes no touches", moment, namesOf(bar));
        if (shownOpacity(platterOf(bar)) < 0.99) CASE_FAIL_NO(@"%@: the glass of the bar holding %@ at %.2f", moment, namesOf(bar), shownOpacity(platterOf(bar)));
        __block NSString *undrawn = nil;
        SGForEachView(bar, ^(UIView *v) {
            if (!undrawn && isButton(v) && !isLitCopy(v, bar) && shownOpacity(glyphIn(v)) < 0.99) undrawn = itemOf(bar, v).accessibilityLabel ?: @"?";
        });
        if (undrawn) CASE_FAIL_NO(@"%@: %@'s glyph not drawn", moment, undrawn);
    }
    return YES;
}

// Expanded: the row as the launch words make it, `selected` picked, Search's button drawn in it once and in full.
static void expectExpanded(NSString *moment, NSString *selected) {
    if (SGRTabBarMinimized()) CASE_FAIL(@"%@: still minimized", moment);
    if (!isClean(moment)) return;
    NSArray<UITabBar *> *bars = shownBars();
    NSMutableArray<NSArray<NSString *> *> *names = [NSMutableArray array];
    for (UITabBar *bar in bars) [names addObject:namesOf(bar)];
    NSArray *expected = said(@"splitcreate") ? @[@[@"Home", @"Your Library", @"Liked Songs", @"Search"], @[@"Create"]]
                      : said(@"nosearch")    ? @[@[@"Home", @"Your Library", @"Create", @"Liked Songs"]]
                      : said(@"middle")      ? @[@[@"Home", @"Your Library", @"Search", @"Create", @"Liked Songs"]]
                                             : @[@[@"Home", @"Your Library", @"Create", @"Liked Songs", @"Search"]];
    if (![names isEqualToArray:expected]) CASE_FAIL(@"%@: the bars hold %@", moment, names);
    if (![selectedName() isEqualToString:selected]) CASE_FAIL(@"%@: %@ selected, not %@", moment, selectedName(), selected);
    NSUInteger drawn = 0;
    for (UIView *button in buttonsNamed(@"Search")) drawn += shownOpacity(button) > 0.99;
    if (drawn != !said(@"nosearch")) CASE_FAIL(@"%@: Search drawn in full %lu times", moment, (unsigned long)drawn);
    printf("PASS %s: expanded, %s selected\n", moment.UTF8String, selected.UTF8String);
    fflush(stdout);
}

// Minimized, the card's slot: from 8 pt after the leading circle to 8 pt before the trailing one, or to 21 pt in from
// the side without a trailing circle, down in the row.
static void expectCardSlot(NSString *moment, BOOL trailing) {
    UIWindow *window = sgStock.window;
    CGFloat width = window.bounds.size.width;
    CGFloat left = kSideInsetPt + kCirclePt + kCardGapPt;
    CGFloat right = trailing ? width - kSideInsetPt - kCirclePt - kCardGapPt : width - kSideInsetPt;
    CGRect card = SGRNowPlayingCardFrameIn(window, NULL), host = inWindow(barHost());
    if (fabs(CGRectGetMinX(card) - left) > 0.5 || fabs(CGRectGetMaxX(card) - right) > 0.5 || CGRectGetMinY(card) < CGRectGetMinY(host)) {
        CASE_FAIL(@"%@: the card at %@, expected in the row from x %.1f to %.1f", moment, NSStringFromCGRect(card), left, right);
    }
    printf("PASS %s: the card in the row from x %.0f to %.0f\n", moment.UTF8String, left, right);
    fflush(stdout);
}

// Minimized: `leading` on the leading circle, which says it shows all tabs, and `trailing` (nil for none) on a trailing
// circle as a split tab's is, its touch landing on it, named for VoiceOver and the large content viewer, selected when
// `trailingSelected` (the leading one when not).
static void expectCircles(NSString *moment, NSString *leading, NSString *trailing, BOOL trailingSelected) {
    if (!SGRTabBarMinimized()) CASE_FAIL(@"%@: not minimized", moment);
    if (!isClean(moment)) return;
    UIWindow *window = sgStock.window;
    CGFloat width = window.bounds.size.width;
    NSArray<UITabBar *> *bars = shownBars();
    NSMutableArray *names = [NSMutableArray array];
    for (UITabBar *bar in bars) [names addObject:namesOf(bar)];
    NSArray *expected = trailing ? @[@[leading], @[trailing]] : @[@[leading]];
    if (![names isEqualToArray:expected]) CASE_FAIL(@"%@: the bars hold %@, not %@", moment, names, expected);

    UITabBar *lead = bars[0];
    CGRect leadCircle = inWindow(platterOf(lead));
    if (fabs(CGRectGetMinX(leadCircle) - kSideInsetPt) > 0.5 || fabs(leadCircle.size.width - kCirclePt) > 0.5) {
        CASE_FAIL(@"%@: the leading circle at %@", moment, NSStringFromCGRect(leadCircle));
    }
    if (![lead.items.firstObject.accessibilityHint isEqualToString:@"Shows all tabs"]) {
        CASE_FAIL(@"%@: the leading circle's hint is %@", moment, lead.items.firstObject.accessibilityHint);
    }
    if ((lead.selectedItem != nil) == trailingSelected) CASE_FAIL(@"%@: the leading circle selected %d", moment, lead.selectedItem != nil);

    if (trailing) {
        UITabBar *trail = bars[1];
        CGRect bar = inWindow(trail), circle = inWindow(platterOf(trail));
        if (fabs(CGRectGetMinX(bar) - (width - kCircleBarPt)) > 0.5 || fabs(bar.size.width - kCircleBarPt) > 0.5
            || fabs(CGRectGetMaxX(circle) - (width - kSideInsetPt)) > 0.5 || fabs(circle.size.width - kCirclePt) > 0.5) {
            CASE_FAIL(@"%@: the trailing circle %@ on a bar at %@", moment, NSStringFromCGRect(circle), NSStringFromCGRect(bar));
        }
        UITabBarItem *item = trail.items.firstObject;
        if ((trail.selectedItem == item) != trailingSelected) CASE_FAIL(@"%@: the trailing circle selected %d", moment, trail.selectedItem == item);
        if (item.accessibilityHint) CASE_FAIL(@"%@: the trailing circle's hint is %@", moment, item.accessibilityHint);
        // UIKit hands VoiceOver and the large content viewer the item's name and image only while they are on, so the
        // item is what is checked, as for every glass tab.
        if (![item.accessibilityLabel isEqualToString:trailing] || !item.largeContentSizeImage) {
            CASE_FAIL(@"%@: the trailing circle's item reads \"%@\", large content image %@", moment, item.accessibilityLabel, item.largeContentSizeImage);
        }
        UIView *hit = [window hitTest:CGPointMake(CGRectGetMidX(circle), CGRectGetMidY(circle)) withEvent:nil];
        if (![hit isDescendantOfView:trail]) CASE_FAIL(@"%@: a finger on the trailing circle lands on %@", moment, hit);
    }
    printf("PASS %s: %s and %s\n", moment.UTF8String, leading.UTF8String, (trailing ?: @"no trailing circle").UTF8String);
    fflush(stdout);
}

static void expectMinimized(NSString *moment, NSString *leading, NSString *trailing, BOOL trailingSelected) {
    expectCircles(moment, leading, trailing, trailingSelected);
    expectCardSlot([moment stringByAppendingString:@", the card's slot"], trailing != nil);
}

#pragma mark - the run

// `middle labels`: a finger on the row this far into an expand, on the circle carrying Search back across the row, picks
// the tab the expanded row picks for the same point: the circle is drawn there, the row's tab is what is under it.
static const double kTapIntoExpandS = 0.15;
// An expand turned back this far in has had the growing row reach the trailing circle.
static const double kLateTurnS = 0.25;
// Expand, minimize and expand again: the minimize and the second expand this far into the first expand, and the second
// expand looked at this long after the first one's spring has ended, well before its own ends.
static const double kTurnS = 0.08, kAgainS = 0.16, kPastFirstSpringS = 0.05;
static CGPoint sgTapMidExpand;
static NSString *sgPickedMidExpand;

static void tapOnCircleMidExpand(void) {
    UIWindow *window = sgStock.window;
    NSArray<UITabBar *> *bars = shownBars();
    if (bars.count != 2) CASE_FAIL(@"mid-expand: %lu bars, no circle beside the row", (unsigned long)bars.count);
    UITabBar *circle = bars[0].items.count == 1 ? bars[0] : bars[1];
    CGRect platter = shownFrame(platterOf(circle), window);
    if (CGRectIsNull(platter)) CASE_FAIL(@"mid-expand: the circle not drawn yet");
    // Inside the circle as drawn, off Search's glyph at its middle.
    sgTapMidExpand = CGPointMake(CGRectGetMinX(platter) + kCardGapPt, CGRectGetMidY(platter));
    printf("tapping (%.0f, %.0f) on the circle drawn at x %.0f to %.0f\n", sgTapMidExpand.x, sgTapMidExpand.y, CGRectGetMinX(platter), CGRectGetMaxX(platter));
    fflush(stdout);
    SGHarnessTap(window, sgTapMidExpand);
}

// How long the spring UIKit gave `view` last runs; NAN for none.
static CFTimeInterval springDuration(UIView *view) {
    CFTimeInterval duration = NAN;
    for (NSString *key in view.layer.animationKeys) {
        CAAnimation *animation = [view.layer animationForKey:key];
        if ([animation isKindOfClass:CASpringAnimation.class]) duration = animation.duration;
    }
    return duration;
}

// Once the first of two expands has settled, the second one still under way: Search's glyph travelling over the bars
// and the trailing circle's glass drawn exactly while the growing row has not reached it.
static void expectSecondExpandUnderWay(void) {
    UIView *travelling = nil;
    for (UIView *view in barHost().subviews) if ([view isKindOfClass:UIImageView.class]) travelling = view;
    if (!travelling) CASE_FAIL(@"expand again inside an expand: no glyph travelling once the first expand settled");
    UIWindow *window = sgStock.window;
    UITabBar *row = rowBar();
    for (UITabBar *bar in allBars()) {
        if (bar == row || ![namesOf(bar) isEqualToArray:@[@"Search"]]) continue;
        CGRect rowGlass = shownFrame(platterOf(row), window), glass = shownFrame(platterOf(bar), window);
        CGFloat gap = capsuleGap(rowGlass, glass);
        BOOL drawn = shownOpacity(platterOf(bar)) > kDrawnFraction;
        if (drawn && gap < -kOverlapSlackPt) CASE_FAIL(@"expand again inside an expand: the circle's glass on the row's, %.1f pt deep", -gap);
        if (!drawn && gap > kOverlapSlackPt) CASE_FAIL(@"expand again inside an expand: the circle gone %.1f pt before the row reached it", gap);
    }
    printf("PASS expand again inside an expand: under way once the first expand settled\n");
    fflush(stdout);
}

static void runSteps(NSArray<NSArray *> *steps, NSUInteger index) {
    if (index >= steps.count) return;
    dispatch_block_t block = steps[index][1];
    after([steps[index][0] doubleValue], ^{
        block();
        runSteps(steps, index + 1);
    });
}

// Spotify's Search tab hidden or shown in its row, as Spotify's list of tabs changing does, and the bar's pass run.
static void setStockSearchHidden(BOOL hidden) {
    __block UIView *search = nil;
    SGForEachView(sgStock, ^(UIView *v) {
        if (search || ![v.superview.accessibilityIdentifier isEqualToString:@"tabs-container-view-identifier"]) return;
        __block BOOL named = NO;
        SGForEachView(v, ^(UIView *sub) {
            if ([sub isKindOfClass:UILabel.class] && [((UILabel *)sub).text isEqualToString:@"Search"]) named = YES;
        });
        if (named) search = v;
    });
    if (!search) CASE_FAIL(@"no Search tab in Spotify's row");
    search.hidden = hidden;
    [sgStock setNeedsLayout];
    [sgStock layoutIfNeeded];
}

static void finish(void) {
    if (sgFailures) {
        printf("FAIL %lu search checks\n", (unsigned long)sgFailures);
        fflush(stdout);
        exit(1);
    }
    printf("PASS all search\n");
    fflush(stdout);
    exit(0);
}

void SGHarnessRunSearch(UIView *stockBar) {
    sgStock = stockBar;
    // What Navbar.x reads off Spotify's list of tabs: each tab's page by its name.
    BOOL find = said(@"find");
    SGRSetNavbarStockURIs(@{
        @"Home": @"spotify:home",
        @"Search": find ? @"spotify:find" : @"spotify:search",
        @"Your Library": @"spotify:collection",
        @"Create": find ? @"spotify:internal:playlist-creation-container" : @"spotify:create-menu",
    });
    [stockBar setNeedsLayout];
    [stockBar layoutIfNeeded];
    static SGHarnessSearchSampler *sampler;
    sampler = [SGHarnessSearchSampler new];
    const double settle = 0.9;

    // `capture` (capture.sh): the bar minimized at once and, after a pause, one expand, for a screen recording to show
    // frame by frame; `selected` with Search the tab selected. The recording's script ends the run.
    if (said(@"capture")) {
        if (said(@"selected")) pick(@"Search");
        runSteps(@[
            @[@(settle), ^{ SGRSetTabBarMinimized(YES, NO); }],
            @[@(settle), ^{
                printf("expanding\n");
                fflush(stdout);
                SGRSetTabBarMinimized(NO, YES);
            }],
        ], 0);
        return;
    }

    // The bar as it was: Create's split circle, or no trailing circle at all.
    if (said(@"splitcreate") || said(@"nosearch") || said(@"own")) {
        NSString *trailing = said(@"splitcreate") ? @"Create" : nil;
        NSString *other = said(@"nosearch") ? @"Your Library" : @"Search";
        runSteps(@[
            @[@0, ^{
                expectExpanded(@"at rest", @"Home");
                SGRSetTabBarMinimized(YES, YES);
            }],
            @[@(settle), ^{
                expectMinimized(@"minimized on Home", @"Home", trailing, NO);
                SGRSetTabBarMinimized(NO, NO);
                pick(other);
            }],
            @[@(settle), ^{
                expectExpanded([@"on " stringByAppendingString:other], other);
                SGRSetTabBarMinimized(YES, YES);
            }],
            // Another tab current: on the leading circle, as any current tab but the trailing one.
            @[@(settle), ^{
                expectMinimized([@"minimized on " stringByAppendingString:other], other, trailing, NO);
                finish();
            }],
        ], 0);
        return;
    }

    // `leaves`: Spotify's list of tabs loses Search while the bar is minimized, four tabs left, and gets it back: the
    // trailing circle goes and comes, and the card takes the slot each time.
    if (said(@"leaves")) {
        runSteps(@[
            @[@0, ^{
                expectExpanded(@"at rest", @"Home");
                SGRSetTabBarMinimized(YES, YES);
            }],
            @[@(settle), ^{
                expectMinimized(@"minimized on Home", @"Home", @"Search", NO);
                setStockSearchHidden(YES);
            }],
            @[@(settle), ^{
                expectMinimized(@"Search gone from the row", @"Home", nil, NO);
                setStockSearchHidden(NO);
            }],
            @[@(settle), ^{
                expectMinimized(@"Search back in the row", @"Home", @"Search", NO);
                SGRSetTabBarMinimized(NO, YES);
            }],
            @[@(settle), ^{
                expectExpanded(@"expanded", @"Home");
                finish();
            }],
        ], 0);
        return;
    }

    NSArray<NSArray *> *tapMidExpand = !(said(@"middle") && said(@"labels")) ? @[] : @[
        @[@(settle), ^{ pick(@"Home"); }],
        @[@(settle), ^{ SGRSetTabBarMinimized(YES, YES); }],
        @[@(settle), ^{
            expectMinimized(@"minimized for a tap mid-expand", @"Home", @"Search", NO);
            SGRSetTabBarMinimized(NO, YES);
            after(kTapIntoExpandS, ^{ tapOnCircleMidExpand(); });
        }],
        // The same point tapped on the expanded row, from Home again.
        @[@(settle), ^{
            if (SGRTabBarMinimized()) CASE_FAIL(@"after a tap mid-expand: still minimized");
            sgPickedMidExpand = selectedName();
            pick(@"Home");
            SGHarnessTap(sgStock.window, sgTapMidExpand);
        }],
        @[@(settle), ^{
            NSString *atRest = selectedName();
            if ([atRest isEqualToString:@"Home"]) CASE_FAIL(@"a tap at rest at %@ picked nothing", NSStringFromCGPoint(sgTapMidExpand));
            if (![sgPickedMidExpand isEqualToString:atRest]) {
                CASE_FAIL(@"a tap mid-expand at %@: %@ selected, the expanded row picks %@ there", NSStringFromCGPoint(sgTapMidExpand), sgPickedMidExpand, atRest);
            }
            printf("PASS a tap on the circle mid-expand: %s, as on the expanded row\n", atRest.UTF8String);
            fflush(stdout);
        }],
    ];
    runSteps([@[
        @[@0, ^{
            expectExpanded(@"at rest", @"Home");
            [sampler begin:@"minimize on Home"];
            SGRSetTabBarMinimized(YES, YES);
        }],
        @[@(settle), ^{
            [sampler endExpectingCircleToComeOut:YES];
            expectMinimized(@"minimized on Home", @"Home", @"Search", NO);
            [sampler begin:@"expand from Home"];
            SGRSetTabBarMinimized(NO, YES);
        }],
        @[@(settle), ^{
            [sampler endExpectingCircleToComeOut:NO];
            expectExpanded(@"expanded from Home", @"Home");
            [sampler begin:@"minimize turned back"];
            sampler.expandsFromRest = NO;
            SGRSetTabBarMinimized(YES, YES);
            after(0.12, ^{ SGRSetTabBarMinimized(NO, YES); });
        }],
        @[@(settle), ^{
            [sampler endExpectingCircleToComeOut:YES];
            expectExpanded(@"after a minimize turned back", @"Home");
            SGRSetTabBarMinimized(YES, YES);
        }],
        @[@(settle), ^{
            [sampler begin:@"expand turned back"];
            SGRSetTabBarMinimized(NO, YES);
            after(0.12, ^{ SGRSetTabBarMinimized(YES, YES); });
        }],
        // Turned back once the growing row has reached the circle, which is gone by then: it comes out of the row again.
        @[@(settle), ^{
            [sampler endExpectingCircleToComeOut:NO];
            expectMinimized(@"after an expand turned back", @"Home", @"Search", NO);
            [sampler begin:@"expand turned back late"];
            SGRSetTabBarMinimized(NO, YES);
            after(kLateTurnS, ^{
                NSUInteger glass = 0;
                for (UITabBar *bar in shownBars()) glass += shownOpacity(platterOf(bar)) > kDrawnFraction;
                SGRSetTabBarMinimized(YES, YES);
                if (glass != 1) CASE_FAIL(@"expand turned back late: the circle still drawn %.2f s in", kLateTurnS);
            });
        }],
        @[@(settle), ^{
            [sampler endExpectingCircleToComeOut:YES];
            expectMinimized(@"after an expand turned back late", @"Home", @"Search", NO);
            [sampler begin:@"expand again inside an expand"];
            sampler.expandsFromRest = NO;
            SGRSetTabBarMinimized(NO, YES);
            CFTimeInterval firstS = springDuration(rowBar());
            if (isnan(firstS)) CASE_FAIL(@"expand again inside an expand: no spring on the expanding bar");
            after(kTurnS, ^{ SGRSetTabBarMinimized(YES, YES); });
            after(kAgainS, ^{ SGRSetTabBarMinimized(NO, YES); });
            after(firstS + kPastFirstSpringS, ^{ expectSecondExpandUnderWay(); });
        }],
        @[@(settle + kAgainS), ^{
            [sampler endExpectingCircleToComeOut:NO];
            expectExpanded(@"after an expand again inside an expand", @"Home");
            pick(@"Search");
        }],
        @[@(settle), ^{
            expectExpanded(@"on Search", @"Search");
            [sampler begin:@"minimize on Search"];
            SGRSetTabBarMinimized(YES, YES);
        }],
        // Search current: the first tab on the leading circle, Search selected on the trailing one.
        @[@(settle), ^{
            [sampler endExpectingCircleToComeOut:YES];
            expectMinimized(@"minimized on Search", @"Home", @"Search", YES);
            [sampler begin:@"expand from Search"];
            SGRSetTabBarMinimized(NO, YES);
        }],
        @[@(settle), ^{
            [sampler endExpectingCircleToComeOut:NO];
            expectExpanded(@"expanded from Search", @"Search");
            pick(@"Home");
        }],
        @[@(settle), ^{ SGRSetTabBarMinimized(YES, YES); }],
        // A finger on the trailing circle opens Search, and Spotify's tab change brings the bar back.
        @[@(settle), ^{
            expectMinimized(@"minimized for the tap", @"Home", @"Search", NO);
            NSArray<UITabBar *> *bars = shownBars();
            if (bars.count < 2) CASE_FAIL(@"the tap: no trailing circle to tap");
            CGRect circle = inWindow(platterOf(bars[1]));
            [sampler begin:@"expand from a tap on the trailing circle"];
            SGHarnessTap(sgStock.window, CGPointMake(CGRectGetMidX(circle), CGRectGetMidY(circle)));
        }],
        @[@(1.2), ^{
            [sampler endExpectingCircleToComeOut:NO];
            expectExpanded(@"after a tap on the trailing circle", @"Search");
        }],
    ] arrayByAddingObjectsFromArray:[tapMidExpand arrayByAddingObject:@[@0, ^{ finish(); }]]], 0);
}
