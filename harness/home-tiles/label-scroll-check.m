#import "Redesigned/Home/Home.h"
#import "Redesigned/Navbar/Navbar.h"
#import "Redesigned/Kit/SGRKit.h"
#import "../harness-fail.h"

static NSUInteger labels;
static BOOL minimized;
BOOL SGRedesignedUI(void) { return YES; }
BOOL SGRHomeLook(void) { return YES; }
BOOL SGRHomeShortcutGlass(void) { return YES; }
void SGRequireClasses(NSArray *names) {}
CFTimeInterval SGRHomeProbeBegin(void) { return 0; }
void SGRHomeProbeEnd(SGRHomeProbe probe, CFTimeInterval began) { if (probe == SGRHomeProbeLabels) labels++; }
const CGFloat SGRRadiusCover = 8, SGRRadiusCard = 16, SGRHomeTileRadius = 8;
UIView *SGRFindByIdentifier(UIView *root, NSString *identifier, const void *key) { return nil; }
void SGRSuppress(UIView *view) {}
BOOL SGRHomeStyleLargeCard(UIView *card) { return NO; }
void SGRHomeStyleTile(UIView *tile) {}
void SGRHomeUnstyleTile(UIView *tile) {}
NSString *const SGPlayerTransitionNotification = @"transition";
BOOL SGEnabled(NSString *key) { return YES; }
BOOL SGRTabBarMinimized(void) { return minimized; }
void SGRSetTabBarMinimized(BOOL on, BOOL animated) { minimized = on; }

@interface _TtC19LegacyUI_ECMCoreKit31InteractableLayoutBackingButton : UIButton
@property NSUInteger marks;
@end
@implementation _TtC19LegacyUI_ECMCoreKit31InteractableLayoutBackingButton
- (void)setNeedsLayout { _marks++; [super setNeedsLayout]; }
@end
@interface _TtC23NavigationUI_TabBarImpl19TabBarContainerImpl : UIViewController @end
@implementation _TtC23NavigationUI_TabBarImpl19TabBarContainerImpl @end
@interface PlayerScroll : UIScrollView
@property NSUInteger reads;
@end
@implementation PlayerScroll
- (BOOL)isTracking { _reads++; return YES; }
@end

int main(int argc, char **argv) {
    @autoreleasepool {
        if (!strcmp(argv[1], "labels")) {
            UIView *branch = [UIView new];
            UILabel *label = [UILabel new];
            label.accessibilityIdentifier = @"Encore.Label-internal";
            [branch addSubview:label];
            labels = 0;
            for (int i = 0; i < 40; i++) label.text = @"player";
            HARNESS_CHECK(!labels);
            _TtC19LegacyUI_ECMCoreKit31InteractableLayoutBackingButton *card = [_TtC19LegacyUI_ECMCoreKit31InteractableLayoutBackingButton new];
            card.accessibilityIdentifier = @"Components.UI.HomeCard";
            [card addSubview:branch];
            card.marks = 0;
            label.attributedText = [[NSAttributedString alloc] initWithString:@"on Home"];
            HARNESS_CHECK(labels && card.marks);
            [branch removeFromSuperview];
            labels = 0;
            label.text = @"player";
            HARNESS_CHECK(!labels);
        } else {
            UIViewController *page = [_TtC23NavigationUI_TabBarImpl19TabBarContainerImpl new];
            PlayerScroll *scroll = [[PlayerScroll alloc] initWithFrame:CGRectMake(0, 0, 100, 100)];
            scroll.contentSize = CGSizeMake(100, 1000);
            scroll.reads = 0;
            for (int i = 0; i < 40; i++) scroll.contentOffset = CGPointMake(0, i);
            HARNESS_CHECK(!scroll.reads && !minimized);
            [page.view addSubview:scroll];
            scroll.contentOffset = CGPointMake(0, 50);
            scroll.contentOffset = CGPointMake(0, 100);
            HARNESS_CHECK(minimized);
            scroll.contentOffset = CGPointZero;
            HARNESS_CHECK(!minimized);
        }
        printf("%s: unchanged outsiders skipped, inside path active\n", argv[1]);
    }
}
