#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static char kReachKey;
static NSString *const SGRKeyPlayerVolume = @"harness.volume";
static BOOL SGEnabled(NSString *key) { return YES; }
static void SGRPlayerPaintCover(UIView *stack) {}
static BOOL SGRPlayerTwoColumns(void) { return NO; }
#define SGLog(...) ((void)0)
void SGRPlayerLowerRow(UIView *row);

// Only drawing is absent: production creates and places this row against the actual button geometry.
@interface SGRVolumeRow : UIView
@end
@implementation SGRVolumeRow
@end
static UIView *SGRFindByIdentifier(UIView *view, NSString *identifier, const void *key) {
    if ([view.accessibilityIdentifier isEqual:identifier]) return view;
    for (UIView *child in view.subviews) {
        UIView *found = SGRFindByIdentifier(child, identifier, key);
        if (found) return found;
    }
    return nil;
}
static BOOL SGRPlayerLyricsFadeView(UIView *view, BOOL fits) {
    if (!fits) view.alpha = 0;
    return !fits;
}

// The layout needs window geometry, not an application or a visible desktop window.
@interface HarnessFooter : UIView
@property BOOL layoutRunning;
@end
@implementation HarnessFooter
- (UIWindow *)window { return self.layoutRunning ? (UIWindow *)self : nil; }
@end
@interface PlaybackControlsElementsUnit : UIViewController
@end
@implementation PlaybackControlsElementsUnit
@end

#include "volume-margins-production.inc"
#include "volume-placement-production.inc"
#include "volume-layout-production.inc"

static BOOL checkPhone(CGSize size, CGFloat stackTop, BOOL expectsVolume) {
        UIView *host = [[UIView alloc] initWithFrame:(CGRect){CGPointZero, size}];
        UIStackView *stack = [[UIStackView alloc] initWithFrame:CGRectMake(0, stackTop, size.width, 240)];
        [host addSubview:stack];
        UIView *duration = [[UIView alloc] initWithFrame:CGRectMake(0, 67, size.width, 41)];
        UIControl *time = [[UIControl alloc] initWithFrame:CGRectMake(24, 26, size.width - 48, 15)];
        [duration addSubview:time];
        [stack addSubview:duration];
        PlaybackControlsElementsUnit *controls = [PlaybackControlsElementsUnit new];
        controls.view.frame = CGRectMake(0, 108, size.width, 88);
        UIControl *play = [[UIControl alloc] initWithFrame:CGRectMake((size.width - 64) / 2, 16, 64, 64)];
        play.accessibilityIdentifier = @"SPTNowPlayingPlayButton";
        [controls.view addSubview:play];
        [stack addSubview:controls.view];
        HarnessFooter *footer = [[HarnessFooter alloc] initWithFrame:CGRectMake(0, 196, size.width, 44)];
        [stack addSubview:footer];
        footer.layoutRunning = YES;
        SGRPlayerLowerRow(footer);
        footer.layoutRunning = NO;
        UIView *hit = [stack hitTest:CGPointMake(size.width / 2, 104) withEvent:nil];
        if (hit != time) {
            NSLog(@"FAIL volume layout covers time row: hit %@ instead of its control", NSStringFromClass(hit.class));
            return NO;
        }
        UIView *volume = nil;
        for (UIView *view in stack.subviews) if ([view isKindOfClass:SGRVolumeRow.class]) volume = view;
        if (!volume || (volume.alpha > 0.01) != expectsVolume) {
            NSLog(@"FAIL %@ volume should be %@", NSStringFromCGSize(size), expectsVolume ? @"shown" : @"omitted");
            return NO;
        }
        if (volume.alpha > 0.01 && (CGRectIntersectsRect(volume.frame, duration.frame) ||
            CGRectIntersectsRect(volume.frame, controls.view.frame) || CGRectIntersectsRect(volume.frame, footer.frame))) {
            NSLog(@"FAIL %@ volume overlaps another row", NSStringFromCGSize(size));
            return NO;
        }
        CGPoint playPoint = [play convertPoint:CGPointMake(32, 32) toView:stack];
        if ([stack hitTest:playPoint withEvent:nil] != play) {
            NSLog(@"FAIL %@ volume blocks playback controls", NSStringFromCGSize(size));
            return NO;
        }
        NSLog(@"PASS %@ real placement: volume %@, time and controls touchable", NSStringFromCGSize(size),
              expectsVolume ? @"shown without overlap" : @"omitted");
        if (expectsVolume) {
            // Spotify grows a bottom-pinned stack upwards to allocate a
            // floating unit. Footer and play keep their size and screen Y;
            // volume is *not* an arranged view.
            CGFloat before = CGRectGetMidY([host convertRect:volume.bounds fromView:volume]);
            [host layoutIfNeeded];
            stack.frame = CGRectMake(0, stackTop-32, size.width, 272);
            for (UIView *view in @[duration, controls.view, footer])
                view.center = CGPointMake(view.center.x, view.center.y+32);
            [host layoutIfNeeded];
            CGFloat after = CGRectGetMidY([host convertRect:volume.bounds fromView:volume]);
            if (fabs(after-before) > .01) {
                NSLog(@"FAIL stack grew above the controls: volume moved %.0f pt", after-before);
                return NO;
            }
        }
        return YES;
}

// A reused row already has its last frame when Spotify installs fresh side
// pins. Layout of the new 12 pt pins follows the unit's first measurement.
static BOOL checkReusedTitle(void) {
    UIView *host = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 402, 64)];
    UIView *row = [[UIView alloc] initWithFrame:CGRectMake(20, 0, 362, 64)];
    row.translatesAutoresizingMaskIntoConstraints = NO;
    [host addSubview:row];
    NSLayoutConstraint *leading = [row.leadingAnchor constraintEqualToAnchor:host.leadingAnchor constant:12];
    [NSLayoutConstraint activateConstraints:@[
        leading,
        [row.trailingAnchor constraintEqualToAnchor:host.trailingAnchor constant:-12],
        [row.topAnchor constraintEqualToAnchor:host.topAnchor],
        [row.bottomAnchor constraintEqualToAnchor:host.bottomAnchor],
    ]];
    SGRPlayerHoldMargin(row, 12);
    [host layoutIfNeeded];
    SGRPlayerHoldMargin(row, 12);
    [host layoutIfNeeded];
    BOOL ok = CGRectGetMinX(row.frame) + 12 == 32 && CGRectGetMaxX(row.frame) == 382;
    NSLog(@"%@ reused title starts at %.0f", ok ? @"PASS" : @"FAIL", CGRectGetMinX(row.frame)+12);
    if (!ok) return NO;
    // Issue #35: once inset, the row lays its title out 8 pt in for 12. That is the inset row's own layout, not
    // Spotify's offset, so the row stays where the first reading put it.
    SGRPlayerHoldMargin(row, 8);
    [host setNeedsLayout];
    [host layoutIfNeeded];
    ok = CGRectGetMinX(row.frame) == 20 && CGRectGetMaxX(row.frame) == 382;
    NSLog(@"%@ inset title row holds at %.0f", ok ? @"PASS" : @"FAIL", CGRectGetMinX(row.frame));
    if (!ok) return NO;
    // A row first read while it still held a video podcast's thumbnail (the title 60 pt in) is not inset, and is
    // read again without it: only a reading that inset the row is kept.
    UIView *late = [UIView new];
    late.translatesAutoresizingMaskIntoConstraints = NO;
    [host addSubview:late];
    [NSLayoutConstraint activateConstraints:@[
        [late.leadingAnchor constraintEqualToAnchor:host.leadingAnchor constant:12],
        [late.trailingAnchor constraintEqualToAnchor:host.trailingAnchor constant:-12],
        [late.topAnchor constraintEqualToAnchor:host.topAnchor],
        [late.bottomAnchor constraintEqualToAnchor:host.bottomAnchor],
    ]];
    [host layoutIfNeeded];
    SGRPlayerHoldMargin(late, 60);
    [host layoutIfNeeded];
    BOOL native = CGRectGetMinX(late.frame) == 12;
    SGRPlayerHoldMargin(late, 12);
    [host setNeedsLayout];
    [host layoutIfNeeded];
    ok = native && CGRectGetMinX(late.frame) == 20 && CGRectGetMaxX(late.frame) == 382;
    NSLog(@"%@ row read with a thumbnail, then without, starts at %.0f", ok ? @"PASS" : @"FAIL", CGRectGetMinX(late.frame));
    [late removeFromSuperview];
    if (!ok) return NO;
    // UIKit can normalize a direct leadingMargin constraint into one on
    // the unit's own guide. A sibling's margin is genuinely not that pin.
    UIView *rail = [[UIView alloc] initWithFrame:host.bounds];
    rail.layoutMargins = UIEdgeInsetsMake(0,12,0,12);
    [host addSubview:rail];
    leading.active = NO;
    [NSLayoutConstraint constraintWithItem:row attribute:NSLayoutAttributeLeading relatedBy:NSLayoutRelationEqual
                                   toItem:rail attribute:NSLayoutAttributeLeadingMargin multiplier:1 constant:0].active = YES;
    // Still at the adjusted x=20; the replacement pin's native x is 12.
    SGRPlayerHoldMargin(row, 12);
    [host layoutIfNeeded];
    ok = CGRectGetMinX(row.frame) + 12 == 32;
    NSLog(@"%@ title re-pinned to leadingMargin starts at %.0f", ok ? @"PASS" : @"FAIL", CGRectGetMinX(row.frame)+12);
    return ok;
}

int main(void) {
    @autoreleasepool {
      @try {
        if (!checkReusedTitle()) return 1;
        if (!checkPhone(CGSizeMake(402, 874), 572, YES)) return 1;
        // The SE has no bottom safe-area inset; the same Spotify units end at its 667 pt screen edge.
        if (!checkPhone(CGSizeMake(375, 667), 427, NO)) return 1;
      } @catch (NSException *exception) {
        NSLog(@"FAIL volume layout exception: %@", exception.reason);
        return 1;
      }
    }
    return 0;
}
