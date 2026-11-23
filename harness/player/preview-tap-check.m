#import <UIKit/UIKit.h>
#import "../harness-fail.h"
#import "Redesigned/Player/Player.h"
#import "Shared/Lyrics/Lyrics.h"
#import "Redesigned/Kit/SGRBridges.h"
#import "Shared/Player/PlayerState.h"

extern void SGHarnessTap(UIWindow *, CGPoint);
extern void SGRHarnessSetTrack(NSString *, NSString *, BOOL);

// Unlike the static cover used for screenshots, this cell must be selectable by UIKit.
@interface PreviewTapPager : NSObject <UICollectionViewDataSource, UICollectionViewDelegate>
@property(nonatomic) NSUInteger selections;
@end

@implementation PreviewTapPager
- (NSInteger)collectionView:(UICollectionView *)view numberOfItemsInSection:(NSInteger)section { return 1; }
- (UICollectionViewCell *)collectionView:(UICollectionView *)view cellForItemAtIndexPath:(NSIndexPath *)path {
    return [view dequeueReusableCellWithReuseIdentifier:@"cover" forIndexPath:path];
}
- (void)collectionView:(UICollectionView *)view didSelectItemAtIndexPath:(NSIndexPath *)path {
    self.selections++;
    [view deselectItemAtIndexPath:path animated:NO];
}
@end

static PreviewTapPager *pager;
UICollectionViewCell *SGHarnessSelectableCover(UICollectionView *covers, Class cellClass) {
    pager = [PreviewTapPager new];
    covers.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    ((UICollectionViewFlowLayout *)covers.collectionViewLayout).itemSize = covers.bounds.size;
    [covers registerClass:cellClass forCellWithReuseIdentifier:@"cover"];
    covers.dataSource = pager;
    covers.delegate = pager;
    [covers layoutIfNeeded];
    UICollectionViewCell *cell = [covers cellForItemAtIndexPath:[NSIndexPath indexPathForItem:0 inSection:0]];
    HARNESS_CHECK(cell);
    cell.accessibilityIdentifier = @"nowplaying-contentlayer-cell-0";
    return cell;
}

static void tapPreview(UIView *preview, dispatch_block_t settled) {
    UIWindow *window = preview.window;
    CGPoint point = [preview convertPoint:CGPointMake(CGRectGetMidX(preview.bounds), CGRectGetMidY(preview.bounds)) toView:window];
    UIView *hit = [window hitTest:point withEvent:nil];
    if (![hit isDescendantOfView:preview]) HARNESS_FAIL(@"preview touch would hit %@ instead", hit);
    SGHarnessTap(window, point);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / 2), dispatch_get_main_queue(), settled);
}

static void pendingCase(UIView *preview, UIViewController *player, NSUInteger step) {
    SGKaraokeKeepLines(SGKaraokePlayingTrack(), nil);
    HARNESS_CHECK(!SGRPlayerLyricsAvailable());
    tapPreview(preview, ^{
        HARNESS_CHECK(!SGRPlayerLyricsOpen() && pager.selections == 1);
        dispatch_block_t deliver = ^{
            SGKaraokeKeepLines(SGKaraokePlayingTrack(), @[]);
            [NSNotificationCenter.defaultCenter postNotificationName:SGKaraokeLinesKeptNotification object:SGKaraokePlayingTrack()];
            if (step == 3 && getenv("HARNESS_NO_ARTWORK")) {
                HARNESS_CHECK(!SGRNowPlayingArtwork(NULL, NULL) && !SGRPlayerLyricsOpen() && pager.selections == 1);
                SGRSetNowPlayingArtwork([UIImage systemImageNamed:@"music.note"], SGURIString(SGPlayerState().track.URI), SGRArtworkQualityHigh);
            }
            HARNESS_CHECK(SGRPlayerLyricsOpen() == (step == 3) && pager.selections == 1);
            if (step == 3) {
                NSLog(@"[harness] preview-pending checks: 4 of 4 right -- PASS");
                exit(0);
            }
            pendingCase(preview, player, step + 1);
        };
        if (step == 0) {
            // A touch outside the covers, without consuming it or asking the player to do anything.
            UIButton *button = [[UIButton alloc] initWithFrame:CGRectMake(20,100,50,50)];
            [player.view.window addSubview:button];
            [button addAction:[UIAction actionWithHandler:^(UIAction *action) {
                [(UIView *)action.sender removeFromSuperview];
                deliver();
            }] forControlEvents:UIControlEventTouchUpInside];
            SGHarnessTap(button.window, button.center);
        } else {
            if (step == 1) {
                SGRHarnessSetTrack(@"spotify:track:other", nil, NO);
                SGRHarnessSetTrack(@"spotify:track:harnessA", nil, NO);
            } else if (step == 2) {
                [player viewWillDisappear:NO];
                [player viewDidDisappear:NO];
                [player viewWillAppear:NO];
                [player viewDidLayoutSubviews];
            }
            deliver();
        }
    });
}

void SGHarnessCheckPreviewTap(UIView *preview, UIViewController *player, dispatch_block_t givePreviewBack) {
    HARNESS_CHECK(preview.layer.mask && !SGRPlayerLyricsOpen());
    tapPreview(preview, ^{
        if (SGRPlayerLyricsOpen() || pager.selections != 1)
            HARNESS_FAIL(@"masked preview: lyrics open=%d, selections=%lu (wanted NO, 1)", SGRPlayerLyricsOpen(), (unsigned long)pager.selections);
        givePreviewBack();
        HARNESS_CHECK(!preview.layer.mask && SGRPlayerLyricsAvailable());
        if ([NSProcessInfo.processInfo.environment[@"HARNESS_SCENARIO"] isEqual:@"preview-pending"]) {
            pendingCase(preview, player, 0);
            return;
        }
        tapPreview(preview, ^{
            if (!SGRPlayerLyricsOpen() || pager.selections != 1)
                HARNESS_FAIL(@"visible preview: lyrics open=%d, new selections=%lu (wanted YES, 0)", SGRPlayerLyricsOpen(), (unsigned long)(pager.selections - 1));
            NSLog(@"[harness] preview-tap checks: 2 of 2 right -- PASS");
            exit(0);
        });
    });
}
