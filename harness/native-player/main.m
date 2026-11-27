// The native player's scrub and cover room on the simulator: Native/Player/PlayerScrub.x and
// PlayerDeclutter.x run over mocks under Spotify's class names, and each check logs ok or WRONG. The log
// ends with `native player checks: n of m right -- PASS` or `FAIL`.
//
//     scrub   a mock of the progress bar's slider tracked in code (issue #172): the player list's pan off
//             while it tracks, back at its end, at a cancel and when the slider leaves the window, a pan
//             that was off already left off, and a sideways list between them left alone
//     cover   Spotify's layout for a track with lyrics, a smaller cover over the preview (issue #77):
//             untouched with Lyrics preview shown, the cover a centered square of its room with it hidden,
//             and a small cover and a tilt view outside the cover cell untouched
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "Native/Player/NowPlaying.h"
#import "Core/SGBackdrop.h"
#import "Shared/Gestures/Gestures.h"
#import "../harness-fail.h"
#import "../sponsorblock/markers-check.h"

#pragma mark - Spotify's classes, mocked

// Hooked by PlayerDeclutter.x but not looked at here.
@interface _TtC12Element_List18CollectionViewCell : UICollectionViewCell @end
@implementation _TtC12Element_List18CollectionViewCell @end
@interface _TtC12Element_List21SupplementaryItemView : UICollectionReusableView @end
@implementation _TtC12Element_List21SupplementaryItemView
- (UICollectionViewLayoutAttributes *)preferredLayoutAttributesFittingAttributes:(UICollectionViewLayoutAttributes *)attributes {
    return attributes;
}
@end
@interface _TtC20NowPlaying_ModesImpl28PlaybackControlsElementsUnit : UIViewController @end
@implementation _TtC20NowPlaying_ModesImpl28PlaybackControlsElementsUnit @end
@interface _TtC20NowPlaying_ModesImpl18FooterElementsUnit : UIViewController @end
@implementation _TtC20NowPlaying_ModesImpl18FooterElementsUnit @end
@interface _TtC20NowPlaying_ModesImpl23InformationElementsUnit : UIViewController @end
@implementation _TtC20NowPlaying_ModesImpl23InformationElementsUnit @end

@interface _TtC28NowPlaying_ContentLayersImpl16CoverArtCellImpl : UIView @end
@implementation _TtC28NowPlaying_ContentLayersImpl16CoverArtCellImpl @end
@interface _TtC35CreativeWorkCommons_CoverArtTiltKit16CoverArtTiltView : UIView
@property (nonatomic) BOOL inspected;
- (void)handleTap;
@end
@implementation _TtC35CreativeWorkCommons_CoverArtTiltKit16CoverArtTiltView
- (void)handleTap { self.inspected = YES; }
@end
@interface _TtC35NowPlaying_ContentLayerPlatformImpl24AccessibleCollectionView : UIScrollView @end
@implementation _TtC35NowPlaying_ContentLayerPlatformImpl24AccessibleCollectionView @end
@interface _TtC21NowPlaying_ScrollImpl27NPVBackgroundViewController : UIViewController @end
@implementation _TtC21NowPlaying_ScrollImpl27NPVBackgroundViewController @end
@interface _TtC20NowPlaying_ModesImpl18HeaderElementsUnit : UIViewController @end
@implementation _TtC20NowPlaying_ModesImpl18HeaderElementsUnit @end
@interface _TtC20NowPlaying_ModesImpl19DurationElementUnit : UIViewController @end
@implementation _TtC20NowPlaying_ModesImpl19DurationElementUnit @end
@interface _TtC22Lyrics_NPVContainerKit19LyricsContainerView : UIView @end
@implementation _TtC22Lyrics_NPVContainerKit19LyricsContainerView
- (CGSize)intrinsicContentSize { return CGSizeMake(UIViewNoIntrinsicMetric, 64); }
- (CGSize)sizeThatFits:(CGSize)size { return CGSizeMake(size.width, 64); }
@end

// The progress bar's slider, tracking without a touch so it can be scrubbed in code.
@interface _TtCO17NowPlaying_ECMKit11ProgressBar6Slider : UISlider @end
@implementation _TtCO17NowPlaying_ECMKit11ProgressBar6Slider
- (BOOL)beginTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event { return YES; }
- (void)endTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {}
- (void)cancelTrackingWithEvent:(UIEvent *)event {}
@end

#pragma mark - checks

static NSUInteger sg_right, sg_checks;

static void check(NSString *step, BOOL ok, NSString *detail) {
    sg_checks++;
    if (ok) sg_right++;
    NSLog(@"[harness] %@: %@ -- %@", step, detail ?: @"", ok ? @"ok" : @"WRONG");
}

static BOOL hiddenPreviewRun(void) {
    return [NSProcessInfo.processInfo.arguments containsObject:@"preview-hidden"];
}

@interface CardListSource : NSObject <UICollectionViewDataSource> @end
@implementation CardListSource
- (NSInteger)collectionView:(UICollectionView *)list numberOfItemsInSection:(NSInteger)section { return 7; }
- (UICollectionViewCell *)collectionView:(UICollectionView *)list cellForItemAtIndexPath:(NSIndexPath *)path {
    return [list dequeueReusableCellWithReuseIdentifier:@"card" forIndexPath:path];
}
- (UICollectionReusableView *)collectionView:(UICollectionView *)list viewForSupplementaryElementOfKind:(NSString *)kind atIndexPath:(NSIndexPath *)path {
    return [list dequeueReusableSupplementaryViewOfKind:kind withReuseIdentifier:@"section" forIndexPath:path];
}
@end

static void checkCardRange(UIWindow *window) {
    UICollectionViewFlowLayout *layout = [UICollectionViewFlowLayout new];
    layout.headerReferenceSize = CGSizeMake(320, 800);
    layout.sectionInset = UIEdgeInsetsMake(24, 0, 0, 0);
    layout.itemSize = CGSizeMake(320, 0);
    layout.minimumLineSpacing = 24;
    UICollectionView *list = [[UICollectionView alloc] initWithFrame:CGRectMake(0, 0, 320, 600) collectionViewLayout:layout];
    list.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    list.contentInset = UIEdgeInsetsMake(0, 0, 34, 0);
    list.accessibilityIdentifier = @"scrolling_npv_collection_view_accessibility_identifier";
    __attribute__((objc_precise_lifetime)) CardListSource *source = [CardListSource new];
    list.dataSource = source;
    [list registerClass:UICollectionViewCell.class forCellWithReuseIdentifier:@"card"];
    for (NSString *kind in @[UICollectionElementKindSectionHeader, UICollectionElementKindSectionFooter])
        [list registerClass:UICollectionReusableView.class forSupplementaryViewOfKind:kind withReuseIdentifier:@"section"];
    [window addSubview:list];
    [list layoutIfNeeded];
    CGFloat bottom = list.contentSize.height + list.adjustedContentInset.bottom;
    check(@"scroll ends at visible player", bottom == 800, @(bottom).stringValue);
    layout.footerReferenceSize = CGSizeMake(320, 32);
    [layout invalidateLayout];
    [list layoutIfNeeded];
    bottom = list.contentSize.height + list.adjustedContentInset.bottom;
    check(@"new footer after collapsed cards reachable", bottom == 1034, @(bottom).stringValue);
    [list removeFromSuperview];
}

static void checkCardHeader(void) {
    UIView *list = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:[UICollectionViewFlowLayout new]];
    list.accessibilityIdentifier = @"scrolling_npv_collection_view_accessibility_identifier";
    UICollectionReusableView *header = [_TtC12Element_List21SupplementaryItemView new];
    UICollectionViewLayoutAttributes *proposed = [UICollectionViewLayoutAttributes
        layoutAttributesForSupplementaryViewOfKind:UICollectionElementKindSectionHeader
        withIndexPath:[NSIndexPath indexPathForItem:0 inSection:0]];
    proposed.size = CGSizeMake(320, 84);
    header.alpha = 0.75;
    [list addSubview:header];
    [header layoutSubviews];
    check(@"all cards: teaser header", header.alpha == 0, nil);
    CGSize fitted = [header preferredLayoutAttributesFittingAttributes:proposed].size;
    check(@"teaser takes no scroll space", CGSizeEqualToSize(fitted, CGSizeMake(320, 0)), NSStringFromCGSize(fitted));
    [header addSubview:[UISlider new]];
    [header layoutSubviews];
    check(@"reused header now contains the slider", header.alpha == 0.75, nil);
    fitted = [header preferredLayoutAttributesFittingAttributes:proposed].size;
    check(@"reused slider header takes its normal space", CGSizeEqualToSize(fitted, CGSizeMake(320, 84)), NSStringFromCGSize(fitted));
}

static Class mockClass(const char *name) {
    Class cls = objc_getClass(name);
    if (!cls) { cls = objc_allocateClassPair(UIView.class, name, 0); objc_registerClassPair(cls); }
    return cls;
}

// Spotify 9.2.2 renamed the credits card's module from Creator_ to CreatorElements_.
static void checkCreditsCard(void) {
    UICollectionViewCell *cell = [[_TtC12Element_List18CollectionViewCell alloc] initWithFrame:CGRectMake(0, 0, 358, 220)];
    UIView *page = [mockClass("_TtGC13Element_UIKit11ElementViewO20NowPlaying_ScrollAPI20NowPlayingScrollDataP_P__") new];
    [page addSubview:[mockClass("_TtGC13Element_UIKit11ElementViewV33CreatorElements_CreditsElementAPI19CreditsElementPropsP_P__") new]];
    [cell.contentView addSubview:page];
    UICollectionViewLayoutAttributes *proposed = [UICollectionViewLayoutAttributes
        layoutAttributesForCellWithIndexPath:[NSIndexPath indexPathForItem:0 inSection:0]];
    proposed.size = CGSizeMake(358, 220);
    CGSize fitted = [cell preferredLayoutAttributesFittingAttributes:proposed].size;
    check(@"9.2.2 credits card collapses", fitted.height == 0, NSStringFromCGSize(fitted));
}

static void runScrubChecks(UIWindow *window) {
    UIScrollView *list = [[UIScrollView alloc] initWithFrame:window.bounds];
    list.accessibilityIdentifier = @"scrolling_npv_collection_view_accessibility_identifier";
    list.contentSize = CGSizeMake(window.bounds.size.width, window.bounds.size.height * 3);
    [window addSubview:list];
    // A sideways list between the slider and the player's, which the scrub must not take for it.
    UIScrollView *sideways = [[UIScrollView alloc] initWithFrame:CGRectMake(0, 500, window.bounds.size.width, 60)];
    sideways.contentSize = CGSizeMake(window.bounds.size.width * 2, 60);
    [list addSubview:sideways];
    UISlider *slider = [[_TtCO17NowPlaying_ECMKit11ProgressBar6Slider alloc] initWithFrame:CGRectMake(24, 20, 300, 20)];
    [sideways addSubview:slider];
    UIPanGestureRecognizer *pan = list.panGestureRecognizer;
    UITouch *none = nil;

    [slider beginTrackingWithTouch:none withEvent:nil];
    check(@"scrub held while scrubbing", !pan.enabled && sideways.panGestureRecognizer.enabled,
          [NSString stringWithFormat:@"list pan %d, sideways pan %d", pan.enabled, sideways.panGestureRecognizer.enabled]);
    [slider endTrackingWithTouch:none withEvent:nil];
    check(@"scrub back at the end", pan.enabled, nil);
    [slider beginTrackingWithTouch:none withEvent:nil];
    [slider cancelTrackingWithEvent:nil];
    check(@"scrub back at a cancel", pan.enabled, nil);
    [slider beginTrackingWithTouch:none withEvent:nil];
    [slider removeFromSuperview];
    check(@"scrub back when the slider left the window", pan.enabled, nil);
    [sideways addSubview:slider];
    pan.enabled = NO;
    [slider beginTrackingWithTouch:none withEvent:nil];
    [slider endTrackingWithTouch:none withEvent:nil];
    check(@"scrub, a pan off already left off", !pan.enabled, nil);
    [list removeFromSuperview];
}

// CoverArtCellImpl > a plain view (the room) > the tilt view and the preview under it, the tilt view
// holding the cover pinned to its size, as Spotify's ElementView is.
static UIView *coverCell(UIWindow *window, Class cellClass, CGRect roomFrame, UIView **tiltOut, UIView **previewOut) {
    UIView *cell = [[cellClass alloc] initWithFrame:window.bounds];
    [window addSubview:cell];
    UIView *room = [[UIView alloc] initWithFrame:roomFrame];
    [cell addSubview:room];
    CGFloat side = roomFrame.size.width;
    CGFloat small = round(side * 0.8);
    UIView *tilt = [[_TtC35CreativeWorkCommons_CoverArtTiltKit16CoverArtTiltView alloc]
                    initWithFrame:CGRectMake(round((side - small) / 2), 0, small, small)];
    UIView *cover = [[UIView alloc] initWithFrame:tilt.bounds];
    cover.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [tilt addSubview:cover];
    [room addSubview:tilt];
    UIView *preview = [[_TtC22Lyrics_NPVContainerKit19LyricsContainerView alloc] initWithFrame:CGRectMake(0, small + 8, side, 64)];
    [room addSubview:preview];
    *tiltOut = tilt;
    *previewOut = preview;
    return cell;
}

static void runCoverChecks(UIWindow *window) {
    Class cellClass = _TtC28NowPlaying_ContentLayersImpl16CoverArtCellImpl.class;
    CGRect roomFrame = CGRectMake(24, 120, 354, 430);
    CGRect square = CGRectMake(0, round((430 - 354) / 2.0), 354, 354);
    UIView *tilt, *preview;

    if (!hiddenPreviewRun()) {
        UIView *cell = coverCell(window, cellClass, roomFrame, &tilt, &preview);
        CGRect before = tilt.frame, previewBefore = preview.frame;
        [cell setNeedsLayout];
        [cell layoutIfNeeded];
        [tilt setNeedsLayout];
        [tilt layoutIfNeeded];
        check(@"cover, preview shown, untouched", CGRectEqualToRect(tilt.frame, before) && CGRectEqualToRect(preview.frame, previewBefore)
              && !preview.hidden, [NSString stringWithFormat:@"cover %@, preview %@", NSStringFromCGRect(tilt.frame), NSStringFromCGRect(preview.frame)]);
        [cell removeFromSuperview];
        return;
    }

    UIView *cell = coverCell(window, cellClass, roomFrame, &tilt, &preview);
    [cell setNeedsLayout];
    [cell layoutIfNeeded];
    check(@"cover, preview hidden takes no room", preview.hidden && CGSizeEqualToSize(preview.frame.size, CGSizeZero)
          && CGSizeEqualToSize(preview.intrinsicContentSize, CGSizeZero) && CGSizeEqualToSize([preview sizeThatFits:roomFrame.size], CGSizeZero),
          [NSString stringWithFormat:@"frame %@, intrinsic %@", NSStringFromCGRect(preview.frame), NSStringFromCGSize(preview.intrinsicContentSize)]);
    UIView *picture = tilt.subviews.firstObject;
    check(@"cover, preview hidden, fills its room", CGRectEqualToRect(tilt.frame, square) && CGSizeEqualToSize(picture.bounds.size, square.size),
          [NSString stringWithFormat:@"cover %@, picture %@", NSStringFromCGRect(tilt.frame), NSStringFromCGSize(picture.bounds.size)]);
    // Spotify sizing the tilt view again on a pass of its own, without the cell laying out.
    tilt.frame = CGRectMake(40, 0, 280, 280);
    [tilt setNeedsLayout];
    [tilt layoutIfNeeded];
    check(@"cover, a later pass of Spotify's", CGRectEqualToRect(tilt.frame, square), NSStringFromCGRect(tilt.frame));
    [cell removeFromSuperview];

    // The bar's 40pt cover, and a tilt view outside the player's cover cell (an album header), stay as they are.
    cell = coverCell(window, cellClass, CGRectMake(16, 16, 40, 52), &tilt, &preview);
    CGRect before = tilt.frame;
    [cell setNeedsLayout];
    [cell layoutIfNeeded];
    check(@"cover, a small one untouched", CGRectEqualToRect(tilt.frame, before), NSStringFromCGRect(tilt.frame));
    [cell removeFromSuperview];
    cell = coverCell(window, UIView.class, roomFrame, &tilt, &preview);
    before = tilt.frame;
    [tilt setNeedsLayout];
    [tilt layoutIfNeeded];
    check(@"cover, outside the cover cell untouched", CGRectEqualToRect(tilt.frame, before), NSStringFromCGRect(tilt.frame));
    [cell removeFromSuperview];
}

#pragma mark - app

static UIImageView *backgroundImage(UIViewController *controller, UIWindow *window) {
    controller.view.frame = window.bounds;
    [window addSubview:controller.view];
    [controller viewDidLayoutSubviews];
    return SGBackdropImageView(controller.view.subviews.firstObject);
}

#import "../player/recognizer-reuse-check.h"

static void runArtworkChecks(UIWindow *window) {
    NSUserDefaults *store = NSUserDefaults.standardUserDefaults;
    [store setBool:YES forKey:SGKeyGestures];
    UIView *cell = [_TtC28NowPlaying_ContentLayersImpl16CoverArtCellImpl new];
    _TtC35CreativeWorkCommons_CoverArtTiltKit16CoverArtTiltView *player = [_TtC35CreativeWorkCommons_CoverArtTiltKit16CoverArtTiltView new];
    _TtC35CreativeWorkCommons_CoverArtTiltKit16CoverArtTiltView *album = [_TtC35CreativeWorkCommons_CoverArtTiltKit16CoverArtTiltView new];
    [cell addSubview:player];
    player.frame = CGRectMake(0, 0, 354, 354);
    [player layoutSubviews];
    UIView *other = [[player.class alloc] initWithFrame:player.frame];
    [cell addSubview:other];
    checkRecognizerReuse(player, other, @"SGCoverHold", ^{ [player layoutSubviews]; }, ^{ [other layoutSubviews]; });
    [other removeFromSuperview];
    extern id harnessPlaybackController(void);
    __attribute__((objc_precise_lifetime)) id controller = harnessPlaybackController();
    HARNESS_CHECK(controller != nil);
    [player handleTap]; // preference on, but no ancestor has installed the double tap
    HARNESS_CHECK(player.inspected);
    player.inspected = NO;
    UIView *host = [_TtC35NowPlaying_ContentLayerPlatformImpl24AccessibleCollectionView new];
    [host addSubview:cell];
    [host layoutSubviews];
    [player handleTap];
    [album handleTap];
    HARNESS_CHECK(!player.inspected);
    HARNESS_CHECK(album.inspected);
    [store setBool:NO forKey:SGKeyGestures];
    [player handleTap];
    HARNESS_CHECK(player.inspected);

    [store setBool:YES forKey:SGKeyPlayerBackdrop];
    [UIView setAnimationsEnabled:NO];
    UIViewController *plane = [_TtC21NowPlaying_ScrollImpl27NPVBackgroundViewController new];
    UIImageView *backdrop = backgroundImage(plane, window);
    HARNESS_CHECK(backdrop != nil);
    UIScrollView *list = [[_TtC35NowPlaying_ContentLayerPlatformImpl24AccessibleCollectionView alloc] initWithFrame:CGRectMake(0, 0, 354, 354)];
    [window addSubview:list];
    cell.frame = list.bounds;
    [list addSubview:cell];
    UIImageView *cover = [[UIImageView alloc] initWithFrame:cell.bounds];
    cover.image = [UIImage systemImageNamed:@"star.fill"];
    [cell addSubview:cover];
    UIView *placeholder = [[UIView alloc] initWithFrame:cell.bounds];
    UIImageView *glyph = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"music.note"]];
    glyph.frame = CGRectMake(145, 145, 64, 64);
    [placeholder addSubview:glyph];
    [cell addSubview:placeholder];
    placeholder.hidden = YES;
    [list layoutSubviews];
    UIImage *before = backdrop.image;
    HARNESS_CHECK(before != nil);

    cover.image = nil;
    [list layoutSubviews];
    HARNESS_CHECK(backdrop.image == before); // Unsized/loading artwork is not an explicit no-cover state.
    placeholder.hidden = NO;
    glyph.hidden = YES;
    [list layoutSubviews];
    HARNESS_CHECK(backdrop.image == before);
    glyph.hidden = NO;
    [list layoutSubviews];
    HARNESS_CHECK(backdrop.image == nil);
    UIViewController *reopened = [_TtC21NowPlaying_ScrollImpl27NPVBackgroundViewController new];
    UIImageView *reopenedBackdrop = backgroundImage(reopened, window);
    HARNESS_CHECK(reopenedBackdrop.image == nil); // The cached sample must be cleared too.

    cover.image = [UIImage systemImageNamed:@"heart.fill"];
    [list layoutSubviews];
    HARNESS_CHECK(reopenedBackdrop.image != nil); // Real artwork wins even if the glyph still exists.
    [list removeFromSuperview];
    [plane.view removeFromSuperview];
    [reopened.view removeFromSuperview];
    [UIView setAnimationsEnabled:YES];
    NSLog(@"[harness] PASS native cover tap routing, loading preservation and explicit missing artwork");
}

// A track image as Spotify's bar has it: a 7x7 rounded square in one color, resizable in the middle.
static UIImage *spotifyTrack(UIColor *color) {
    UIImage *image = [[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(7, 7)] imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [color setFill];
        [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, 7, 7) cornerRadius:3.5] fill];
    }];
    return [image resizableImageWithCapInsets:UIEdgeInsetsMake(0, 3, 0, 3)];
}

// SponsorBlock's marks on Spotify's own bar (harness/sponsorblock/markers-check.m): the slider 17 pt tall with
// Spotify's white tracks and empty thumb (player-off-full-tree.txt:1902-1916), on a player's color.
static void runSponsorBlockChecks(UIWindow *window) {
    UIView *player = [[UIView alloc] initWithFrame:window.bounds];
    player.backgroundColor = [UIColor colorWithRed:0.27 green:0.17 blue:0.2 alpha:1];
    [window addSubview:player];
    CGFloat width = window.bounds.size.width;
    UISlider *slider = [[_TtCO17NowPlaying_ECMKit11ProgressBar6Slider alloc] initWithFrame:CGRectMake(22, window.bounds.size.height * 0.62, width - 44, 17)];
    slider.accessibilityIdentifier = @"SPTNowPlayingSliderV2";
    [slider setMinimumTrackImage:spotifyTrack(UIColor.whiteColor) forState:UIControlStateNormal];
    [slider setMaximumTrackImage:spotifyTrack([UIColor colorWithWhite:1 alpha:0.3]) forState:UIControlStateNormal];
    [slider setThumbImage:[UIImage new] forState:UIControlStateNormal];
    [player addSubview:slider];
    NSString *shots = NSProcessInfo.processInfo.environment[@"HARNESS_SHOTS"] ?: NSTemporaryDirectory();
    exit(SBMarksRun(slider, @"native", nil, shots) ? 1 : 0);
}

@interface Delegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation Delegate
- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)options {
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController = [UIViewController new];
    self.window.backgroundColor = UIColor.blackColor;
    [self.window makeKeyAndVisible];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        NSArray<NSString *> *arguments = NSProcessInfo.processInfo.arguments;
        if ([arguments containsObject:@"sponsorblock"] || [arguments containsObject:@"sponsorblock-off"]) runSponsorBlockChecks(self.window);
        if ([NSProcessInfo.processInfo.arguments containsObject:@"audit"]) {
            runArtworkChecks(self.window);
            exit(0);
        }
        if (!hiddenPreviewRun()) runScrubChecks(self.window);
        if ([arguments containsObject:@"all-cards"]) {
            checkCardHeader();
            checkCreditsCard();
            checkCardRange(self.window);
        }
        runCoverChecks(self.window);
        NSLog(@"[harness] native player checks: %lu of %lu right -- %@", (unsigned long)sg_right, (unsigned long)sg_checks,
              sg_right == sg_checks ? @"PASS" : @"FAIL");
        exit(sg_right == sg_checks ? 0 : 1);
    });
    return YES;
}
@end

// Before every %ctor, so the native look's gate reads on.
__attribute__((constructor(101))) static void sg_harnessDefaults(void) {
    [NSUserDefaults.standardUserDefaults setBool:NO forKey:@"spotifyglass.redesign"];
    // PlayerDeclutter snapshots this switch in its constructor, just as a real launch does.
    [NSUserDefaults.standardUserDefaults setBool:hiddenPreviewRun() forKey:SGHideLyricsInline];
    for (NSString *key in @[SGHideLyricsCard, SGHideAboutArtist, SGHideRelatedVideos, SGHideSongDNA,
                            SGHideLiveEvents, SGHideExploreArtist, SGHideCredits, SGHideMerch, SGHideRecommendations]) {
        [NSUserDefaults.standardUserDefaults setBool:[NSProcessInfo.processInfo.arguments containsObject:@"all-cards"] forKey:key];
    }
}

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(Delegate.class));
    }
}
