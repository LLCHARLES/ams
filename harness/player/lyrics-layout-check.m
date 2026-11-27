// The player's lyric viewport must not follow the artwork pager between tracks.
// lyrics-layout-check.sh includes the production measurement section unchanged.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "Redesigned/Kit/SGRRestyle.h"
#import "../harness-fail.h"

static UIViewController *sg_info, *sg_duration, *sg_floating, *sg_header;
static UIView *sg_titleElement;
static char kColumnKey;
static CGRect artworkArea, artworkCover;
static const CGFloat SGRSideMargin = 24, SGRGrid = 8;
static CGRect SGFrameIn(UIView *view, UIView *host) { return [view convertRect:view.bounds toView:host]; }
static CGRect SGRPlayerArtworkAreaIn(UIView *host) { return artworkArea; }
static CGRect SGRPlayerCoverFrameIn(UIView *host) { return artworkCover; }
static BOOL wideIn(UIView *host) { return NO; }
static CGRect wideColumn(UIView *host) { return CGRectZero; }
static BOOL sg_alone, sg_queuePage, sg_open, sg_wide;
static BOOL keepsTitle(void) { return NO; }
UIView *SGRFindByIdentifier(UIView *root, NSString *identifier, const void *key) { return nil; }
static NSHashTable<UIView *> *sg_faded;
static NSArray<UIView *> *fadingViews(void) { return @[]; }
// The live header rows' bottom in the player (PlayerArtwork.x); none by default.
static CGFloat sg_liveRowBottom = -CGFLOAT_MAX;
static CGFloat SGRPlayerLiveRowBottomIn(UIView *view) { return sg_liveRowBottom; }

// A player on an iPhone's screen, its own window while it is measured: the thumbnail is placed from the grabber there.
static BOOL sg_measuring;
@interface HarnessShownPlayer : UIView
@end
@implementation HarnessShownPlayer
- (UIWindow *)window { return sg_measuring ? (UIWindow *)self : [super window]; }
- (UITraitCollection *)traitCollection {
    return sg_measuring ? [UITraitCollection traitCollectionWithUserInterfaceIdiom:UIUserInterfaceIdiomPhone] : [super traitCollection];
}
@end

#include "lyrics-layout-production.inc"

// Issue #71: the AI DJ's header keeps its buttons on screen over the lyrics. With its live row reaching under where the
// grabber puts the thumbnail, the thumbnail stands 8 pt under the row and the title beside it clears the row too; with
// no live row (the ordinary header put away) the thumbnail stays 33 pt down (7 + 4 + 22 under the safe area's top).
static void checkLiveHeader(void) {
    UIView *player = [[HarnessShownPlayer alloc] initWithFrame:CGRectMake(0, 0, 390, 844)];
    [player addSubview:sg_info.view];
    [player addSubview:sg_duration.view];
    artworkArea = CGRectMake(0, 106, 390, 444);
    artworkCover = CGRectMake(24, 150, 342, 342);
    sg_measuring = YES;
    SGRLyricsLayout put = layoutIn(player, NO);
    sg_liveRowBottom = 98;
    SGRLyricsLayout dj = layoutIn(player, NO);
    sg_measuring = NO;
    sg_liveRowBottom = -CGFLOAT_MAX;
    if (!put.ok || CGRectGetMinY(put.thumb) != 33)
        HARNESS_FAIL(@"no live header row: thumbnail %@, expected its top at 33", NSStringFromCGRect(put.thumb));
    CGFloat titleTop = CGRectGetMinY(sg_info.view.frame) + dj.lift;
    if (!dj.ok || CGRectGetMinY(dj.thumb) != 106 || titleTop < 98 || CGRectGetMinY(dj.stage) < CGRectGetMaxY(dj.thumb))
        HARNESS_FAIL(@"live header row to 98: thumbnail %@ (expected its top at 106), title top %.1f, lines from %.1f",
                     NSStringFromCGRect(dj.thumb), titleTop, CGRectGetMinY(dj.stage));
    NSLog(@"PASS thumbnail at 33 under the put-away header, at 106 under a live row to 98 with the title from %.1f", titleTop);
}

// Issue #71: the queue page's list carries the thumbnail and the title up with it. Under a live header row to 98 (the
// thumbnail resting at 106) they are gone by the time they reach the row rather than drawn over it; with the header put
// away they still fade over 40 pt, half seen 20 pt up.
static void checkQueueRide(void) {
    UIView *player = [[HarnessShownPlayer alloc] initWithFrame:CGRectMake(0, 0, 390, 844)];
    [player addSubview:sg_info.view];
    [player addSubview:sg_duration.view];
    artworkArea = CGRectMake(0, 106, 390, 444);
    artworkCover = CGRectMake(24, 150, 342, 342);
    sg_open = YES;
    sg_queuePage = YES;
    sg_measuring = YES;
    SGRLyricsLayout put = layoutIn(player, NO);
    sg_liveRowBottom = 98;
    SGRLyricsLayout dj = layoutIn(player, NO);
    sg_measuring = NO;
    sg_liveRowBottom = -CGFLOAT_MAX;
    if (!put.ok || !dj.ok) HARNESS_FAIL(@"queue page has no layout: put away %d, live row %d", put.ok, dj.ok);
    sg_pageShift = 0;
    if (pageRideAlpha(dj) != 1) HARNESS_FAIL(@"queue at rest under a live row: alpha %.2f, expected 1", pageRideAlpha(dj));
    sg_pageShift = 20;
    if (fabs(pageRideAlpha(put) - 0.5) > 0.001)
        HARNESS_FAIL(@"put-away header, list 20 pt up: alpha %.2f, expected 0.50", pageRideAlpha(put));
    CGFloat titleRest = CGRectGetMinY(sg_info.view.frame) + dj.lift;
    for (CGFloat shift = 0.5; shift <= 104; shift += 0.5) {
        sg_pageShift = shift;
        CGFloat top = MIN(CGRectGetMinY(dj.thumb), titleRest) - shift;
        if (top < 98 && pageRideAlpha(dj) > 0)
            HARNESS_FAIL(@"live row to 98, list %.1f pt up: thumbnail and title from %.1f drawn at alpha %.2f", shift, top,
                         pageRideAlpha(dj));
    }
    sg_pageShift = 0;
    sg_open = NO;
    sg_queuePage = NO;
    NSLog(@"PASS the scrolled queue fades the thumbnail and title out before a live row's bottom, over 40 pt without one");
}

int main(void) {
    @autoreleasepool {
        UIView *host = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 393, 852)];
        sg_info = [UIViewController new];
        sg_info.view = [[UIView alloc] initWithFrame:CGRectMake(0, 550, 393, 64)];
        sg_duration = [UIViewController new];
        sg_duration.view = [[UIView alloc] initWithFrame:CGRectMake(0, 614, 393, 40)];
        sg_titleElement = [[UIView alloc] initWithFrame:CGRectMake(24, 0, 260, 64)];
        [host addSubview:sg_info.view];
        [host addSubview:sg_duration.view];
        [sg_info.view addSubview:sg_titleElement];
        // Both sides of a native cover-page transition, plus the settled page.
        for (NSNumber *x in @[@0, @32, @(-62), @393, @(-393)]) {
            artworkArea = CGRectMake(x.doubleValue, 106, 393, 444);
            artworkCover = CGRectMake(x.doubleValue + 24, 150, 345, 345);
            SGRLyricsLayout layout = layoutIn(host, NO);
            // Lyrics start at the bottom of the collapsed cover (114 + 72),
            // and end 8 pt above the duration unit when there is no slider.
            CGRect expected = CGRectMake(0, 186, 393, 420);
            if (!layout.ok || !CGRectEqualToRect(layout.stage, expected)) {
                HARNESS_FAIL(@"artwork x=%@: lyric viewport %@, expected %@", x,
                             NSStringFromCGRect(layout.stage), NSStringFromCGRect(expected));
            }
        }
        NSLog(@"PASS lyric viewport stays at {0,186,393,420} throughout cover paging");
        // A newly laid-out row was not in the original fade set; it must stay hidden and wake only if it fits.
        UIView *volume = [UIView new];
        sg_alone = YES;
        SGRPlayerLyricsFadeView(volume, YES);
        if (volume.alpha != 0) HARNESS_FAIL(@"new volume row covers lyrics");
        sg_alone = NO;
        fadeControls(NO);
        if (volume.alpha != 1) HARNESS_FAIL(@"fitting volume row did not wake");
        sg_alone = YES;
        SGRPlayerLyricsFadeView(volume, YES);
        SGRPlayerLyricsFadeView(volume, NO);
        sg_alone = NO;
        fadeControls(NO);
        if (volume.alpha != 0) HARNESS_FAIL(@"volume without room woke over controls");
        NSLog(@"PASS volume created while lyrics are alone stays hidden and wakes only with room");
        checkLiveHeader();
        checkQueueRide();
    }
    return 0;
}
