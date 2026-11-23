#import <UIKit/UIKit.h>
#import "../harness-fail.h"

@interface MockDefaultToolbarElement : UIView @end
@implementation MockDefaultToolbarElement @end

__attribute__((objc_runtime_name("_TtC35ListUXPlatform_FreeTierPlaylistImpl32FTPTouchCancellingCollectionView")))
@interface TestList : UICollectionView
@property(nonatomic, weak) UIView *toolbar;
@end
@implementation TestList
- (void)setContentOffset:(CGPoint)offset {
    [super setContentOffset:offset];
    // Spotify positions the sibling before returning to the hook.
    self.toolbar.frame = CGRectMake(0, MAX(60, 100 - offset.y), 320, 32);
}
@end

static void check(Class rowClass) {
    UIView *page = [UIView new];
    TestList *list = [[TestList alloc] initWithFrame:CGRectMake(0, 0, 320, 400)
                                collectionViewLayout:[UICollectionViewFlowLayout new]];
    UIView *row = [rowClass new];
    [page addSubview:list];
    [page addSubview:row];
    list.toolbar = row;
    list.contentSize = CGSizeMake(320, 800);
    BOOL isChip = rowClass == MockDefaultToolbarElement.class;
    if (!isChip) row.alpha = 0.75;
    const struct { CGFloat offset, alpha; } steps[] = {
        {0, 1}, {20, 1}, {40, 1}, {52, 0.5}, {64, 0}, {80, 0},
        {52, 0.5}, {41, 23./24}, {40, 1}, {39, 1}, {0, 1}
    };
    for (size_t i = 0; i < sizeof steps / sizeof steps[0]; i++) {
        list.contentOffset = CGPointMake(0, steps[i].offset);
        CGFloat alpha = isChip ? steps[i].alpha : 0.75;
        BOOL touches = !isChip || steps[i].alpha == 1;
        if (fabs(row.alpha - alpha) > 0.002 || row.userInteractionEnabled != touches)
            HARNESS_FAIL(@"%@ at %.0f: alpha %.3f (wanted %.3f), touches %d (wanted %d)",
                         rowClass, steps[i].offset, row.alpha, alpha, row.userInteractionEnabled, touches);
        HARNESS_CHECK(list.contentOffset.y == steps[i].offset && list.alpha == 1 && list.userInteractionEnabled);
    }
}

int main(void) {
    @autoreleasepool {
        check(MockDefaultToolbarElement.class);
        check(UIView.class);
        puts("Playlist chip row: passed");
    }
}
