#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static char kReachKey;
static NSString *const SGRKeyPlayerVolume = @"harness.volume";
// The Volume switch, on unless HARNESS_VOLUME=0; production reads it once per launch.
static BOOL SGEnabled(NSString *key) {
    const char *volume = getenv("HARNESS_VOLUME");
    return ![key isEqual:SGRKeyPlayerVolume] || !(volume && strcmp(volume, "0") == 0);
}
// The cover's lift (PlayerArtwork.x) over a column with Spotify's lyric preview shown or not.
static NSHashTable<UIView *> *sg_tilts;
static BOOL sg_previewShown;
static NSArray<CALayer *> *SGRPlayerPreviewLayers(UIView *column, BOOL *showing) {
    *showing = sg_previewShown;
    return @[];
}
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
#include "volume-cover-production.inc"
#include "volume-layout-production.inc"

#pragma mark - the cover over the rhythm (issue #71)

// A 390x844 iPhone's screen (47 pt safe area on top, 34 under), never in a hierarchy: the cover's cell and the footer
// row take it for their window while the production code reads them.
static UITraitCollection *phoneTraits(void) {
    return [UITraitCollection traitCollectionWithTraits:^(id<UIMutableTraits> traits) {
        traits.userInterfaceIdiom = UIUserInterfaceIdiomPhone;
        traits.displayScale = 3;
    }];
}
@interface HarnessWindow : UIView
@end
@implementation HarnessWindow
- (UIEdgeInsets)safeAreaInsets { return UIEdgeInsetsMake(47, 0, 34, 0); }
- (UITraitCollection *)traitCollection { return phoneTraits(); }
@end
static UIView *sg_screen;
static BOOL sg_onScreen;
@interface HarnessScreen : UIView
@end
@implementation HarnessScreen
- (UIWindow *)window { return sg_onScreen ? (UIWindow *)sg_screen : [super window]; }
- (UITraitCollection *)traitCollection { return sg_onScreen ? phoneTraits() : [super traitCollection]; }
@end

typedef struct { CGFloat cover, title, underRow, withPreview; } CoverPlace;

static UIView *arrangedRow(UIStackView *stack, UIView *row, CGFloat height) {
    row.translatesAutoresizingMaskIntoConstraints = NO;
    [row.heightAnchor constraintEqualToConstant:height].active = YES;
    [stack addArrangedSubview:row];
    return row;
}

// Spotify's bottom stack pinned 61 pt over the screen's bottom, laid out as the footer and the run loop's settling pass
// lay it out, and the cover where it is drawn over Spotify's tilt view (its top 140 pt down, under the Music app's).
static CoverPlace measureCover(void) {
    CGSize size = CGSizeMake(390, 844);
    sg_screen = [[HarnessWindow alloc] initWithFrame:(CGRect){CGPointZero, size}];
    UIView *player = [[UIView alloc] initWithFrame:(CGRect){CGPointZero, size}];
    UIView *cell = [[HarnessScreen alloc] initWithFrame:player.bounds];
    [player addSubview:cell];
    UIView *tilt = [[UIView alloc] initWithFrame:CGRectMake(24, 140, 342, 342)];
    [cell addSubview:tilt];
    UIStackView *stack = [UIStackView new];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [player addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:player.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:player.trailingAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:player.bottomAnchor constant:-61],
    ]];
    UIView *info = arrangedRow(stack, [UIView new], 64);
    UIView *artist = [[UIView alloc] initWithFrame:CGRectMake(12, 40, 200, 18)];
    artist.accessibilityIdentifier = @"now-playing-subtitle-label";
    [info addSubview:artist];
    UIView *duration = arrangedRow(stack, [UIView new], 40);
    UIView *slider = [[UIView alloc] initWithFrame:CGRectMake(24, 8, size.width - 48, 6)];
    slider.accessibilityIdentifier = @"SPTNowPlayingSliderV2";
    [duration addSubview:slider];
    PlaybackControlsElementsUnit *controls = [PlaybackControlsElementsUnit new];
    arrangedRow(stack, controls.view, 88);
    UIControl *play = [[UIControl alloc] initWithFrame:CGRectMake((size.width - 64) / 2, 12, 64, 64)];
    play.accessibilityIdentifier = @"SPTNowPlayingPlayButton";
    [controls.view addSubview:play];
    UIView *footer = arrangedRow(stack, [HarnessScreen new], 44);
    for (int pass = 0; pass < 3; pass++) {
        [player layoutIfNeeded];
        sg_onScreen = YES;
        SGRPlayerLowerRow(footer);
        sg_onScreen = NO;
    }
    [player layoutIfNeeded];
    CoverPlace place;
    place.title = CGRectGetMinY([stack convertRect:info.frame toView:player]);
    sg_onScreen = YES;
    place.cover = CGRectGetMinY(tilt.frame) - coverLift(tilt, cell);
    sg_previewShown = YES;
    place.withPreview = CGRectGetMinY(tilt.frame) - coverLift(tilt, cell);
    sg_previewShown = NO;
    // The AI DJ's header row, taking touches 50 to 98 pt down in the same player (SGRPlayerCoverUnderRow's record).
    UIView *row = [[UIView alloc] initWithFrame:CGRectMake(0, 50, size.width, 48)], *follower = [UIView new];
    [player addSubview:row];
    [player insertSubview:follower atIndex:0];
    if (!sg_liveRows) sg_liveRows = [NSHashTable weakObjectsHashTable];
    [sg_liveRows addObject:row];
    objc_setAssociatedObject(row, &kFollowerKey, follower, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    place.underRow = CGRectGetMinY(tilt.frame) - coverLift(tilt, cell);
    [sg_liveRows removeObject:row];
    sg_onScreen = NO;
    return place;
}

// With Volume on, the Music app's cover top (33 pt under the safe area) and under the DJ's row; with it off, the room
// the volume row leaves above the title splits evenly over and under the cover, except beside Spotify's lyric preview.
static int checkCover(int argc, char **argv) {
    CoverPlace now = measureCover();
    const CGFloat side = 342;
    if (argc < 5) {
        if (now.cover != 47 + 33 || now.withPreview != now.cover || now.underRow != 98) {
            NSLog(@"FAIL Volume on: cover top %.1f (want 80), beside the preview %.1f, under the DJ row %.1f (want 98)",
                  now.cover, now.withPreview, now.underRow);
            return 1;
        }
        NSLog(@"PASS Volume on: cover top 80, gap to the title %.1f, under the DJ row 98", now.title - now.cover - side);
        printf("%g %g %g\n", now.cover, now.title, now.underRow);
        return 0;
    }
    CoverPlace on = { atof(argv[2]), atof(argv[3]), atof(argv[4]), 0 };
    CGFloat titleMove = now.title - on.title, coverMove = now.cover - on.cover;
    CGFloat gapMove = (now.title - now.cover - side) - (on.title - on.cover - side);
    CGFloat rowMove = now.underRow - on.underRow;
    BOOL ok = titleMove >= 40 && coverMove > 0 && fabs(coverMove - gapMove) <= 1 && rowMove == coverMove
        && now.withPreview == on.cover;
    NSLog(@"%@ Volume off: title %.1f lower, cover %.1f lower, gap under it %.1f wider; under the DJ row %.1f lower; "
          @"beside the preview the cover at %.1f (Volume on %.1f)", ok ? @"PASS" : @"FAIL", titleMove, coverMove, gapMove,
          rowMove, now.withPreview, on.cover);
    return ok ? 0 : 1;
}

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

int main(int argc, char **argv) {
    @autoreleasepool {
      if (argc > 1 && strcmp(argv[1], "cover") == 0) return checkCover(argc, argv);
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
