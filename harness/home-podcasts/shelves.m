// The real Home section hooks over a self-sizing Spotify-shaped feed.
#import <UIKit/UIKit.h>
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Home.h"
#import "harness-fail.h"

BOOL SGRedesignedUI(void) { return YES; }
void SGRedesignForceFlags(NSString *owner, NSDictionary *flags) {}
CFTimeInterval SGRHomeProbeBegin(void) { return 0; }
void SGRHomeProbeEnd(SGRHomeProbe probe, CFTimeInterval began) {}
void SGRRollingDigitsMovedToWindow(UIView *view) {}
void SGRRollingDigitsTextChanged(UIView *view) {}
BOOL SGRRollingDigitsWatched(UIView *view) { return NO; }
UIColor *SGRAccentColor(void) { return UIColor.whiteColor; }
UIFont *SGMonospacedDigitsFont(UIFont *font) { return font; }

@interface ShelfNoIntrinsicContentSizeButton : UIView
@end
@implementation ShelfNoIntrinsicContentSizeButton
@end
@interface _TtC16Home_CarouselKit29TouchCancellingCollectionView : UICollectionView
@end
@implementation _TtC16Home_CarouselKit29TouchCancellingCollectionView
@end
@interface _TtC12Element_List18CollectionViewCell : UICollectionViewCell
@property UILabel *heading;
@end
@implementation _TtC12Element_List18CollectionViewCell
- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    Class contentClass = NSClassFromString(@"Harness_Home_EvoPageImpl13HomeStructure");
    if (!contentClass) {
        contentClass = objc_allocateClassPair(self.contentView.class, "Harness_Home_EvoPageImpl13HomeStructure", 0);
        objc_registerClassPair(contentClass);
    }
    object_setClass(self.contentView, contentClass);
    UIView *element = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 400, 200)];
    [self.contentView addSubview:element];
    UICollectionView *shelf = [[_TtC16Home_CarouselKit29TouchCancellingCollectionView alloc]
        initWithFrame:element.bounds collectionViewLayout:[UICollectionViewFlowLayout new]];
    [element addSubview:shelf];
    UIView *heading = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 400, 30)];
    heading.accessibilityIdentifier = @"Components.UI.SectionHeadingHome";
    [shelf addSubview:heading];
    UIView *button = [[ShelfNoIntrinsicContentSizeButton alloc] initWithFrame:heading.bounds];
    [heading addSubview:button];
    UILabel *title = [[UILabel alloc] initWithFrame:button.bounds];
    title.accessibilityIdentifier = @"Encore.Label-internal";
    title.text = @"Hidden shelf";
    [button addSubview:title];
    self.heading = title;
    return self;
}
- (UICollectionViewLayoutAttributes *)preferredLayoutAttributesFittingAttributes:(UICollectionViewLayoutAttributes *)attributes {
    UICollectionViewLayoutAttributes *result = [attributes copy];
    result.size = CGSizeMake(attributes.size.width, 200);
    return result;
}
@end

#include "HomeSections.gen.m"

@interface ShelfFeedFixture : NSObject
+ (NSObject *)renderer;
+ (BOOL)rejectsScalarRenderer;
+ (id)generation:(NSInteger)phase;
+ (void)publish:(id)generation renderer:(NSObject *)renderer;
@end

@interface NSObject (ShelfSnapshotBoundary)
- (id)impl;
- (id)snapshot;
- (id)state;
- (id)generationID;
- (id)dataSourceSnapshot;
- (id)currentTransaction;
- (id)finalSnapshot;
- (void)applyDifferencesFromSnapshot:(id)snapshot animatingDifferences:(BOOL)animated completion:(void (^)(void))completion;
@end

@interface ShelvesList : UICollectionView
@end
@implementation ShelvesList
- (UICollectionViewLayout *)collectionViewLayout {
    HARNESS_CHECK(NSThread.isMainThread);
    return [super collectionViewLayout];
}
@end

static void (^afterCommit)(void);
static void (*storeState)(id, SEL, id);
static void observeStoreState(id self, SEL command, id state) {
    storeState(self, command, state);
    NSLog(@"[harness] committed generation %@ input %@", [state generationID],
        [[(NSObject *)[[[self currentTransaction] finalSnapshot] impl] state] generationID]);
    if (afterCommit) {
        HARNESS_CHECK(NSThread.isMainThread);
        void (^publish)(void) = afterCommit;
        afterCommit = nil;
        publish();
    }
}

@interface Home_EvoPageImplShelvesController : UIViewController
@property UICollectionView *list;
@property UICollectionViewDiffableDataSource *source;
@property NSObject *collectionViewRenderer;
@property dispatch_queue_t applyQueue;
@property NSUInteger phase;
@property NSObject *renderer;
@property id generation;
@property BOOL unavailableCase;
@end
@implementation Home_EvoPageImplShelvesController
@synthesize collectionViewRenderer = collectionViewRenderer;
- (void)viewDidLoad {
    [super viewDidLoad];
    [NSUserDefaults.standardUserDefaults setBool:YES forKey:SGRHomeShelfHideKey(@"Hidden shelf")];
    SGPrefsChanged();
    UICollectionViewCompositionalLayout *layout = [[UICollectionViewCompositionalLayout alloc]
        initWithSectionProvider:^NSCollectionLayoutSection *(NSInteger section, id<NSCollectionLayoutEnvironment> environment) {
            NSCollectionLayoutSize *size = [NSCollectionLayoutSize
                sizeWithWidthDimension:[NSCollectionLayoutDimension fractionalWidthDimension:1]
                heightDimension:[NSCollectionLayoutDimension estimatedDimension:200]];
            NSCollectionLayoutItem *item = [NSCollectionLayoutItem itemWithLayoutSize:size];
            NSCollectionLayoutSection *made = [NSCollectionLayoutSection sectionWithGroup:
                [NSCollectionLayoutGroup verticalGroupWithLayoutSize:size subitems:@[item]]];
            made.contentInsets = NSDirectionalEdgeInsetsMake(24, 0, 0, 0);
            return made;
        }];
    HARNESS_CHECK([ShelfFeedFixture rejectsScalarRenderer]);
    self.renderer = [ShelfFeedFixture renderer];
    self.collectionViewRenderer = self.renderer;
    self.unavailableCase = [NSProcessInfo.processInfo.environment[@"SG_SHELF_CASE"] isEqualToString:@"unavailable"];
    self.applyQueue = dispatch_queue_create("home-shelves-snapshots", DISPATCH_QUEUE_SERIAL);
    self.list = [[ShelvesList alloc] initWithFrame:CGRectMake(0, 0, 400, 800) collectionViewLayout:layout];
    self.list.delegate = (id<UICollectionViewDelegate>)self;
    [self.list registerClass:_TtC12Element_List18CollectionViewCell.class forCellWithReuseIdentifier:@"shelf"];
    __weak typeof(self) weakSelf = self;
    self.source = [[UICollectionViewDiffableDataSource alloc] initWithCollectionView:self.list
        cellProvider:^UICollectionViewCell *(UICollectionView *list, NSIndexPath *path, id identifier) {
            typeof(self) self = weakSelf;
            // Disabled previews must never ask DataElement for its unready data.
            HARNESS_CHECK(self.phase != 1);
            _TtC12Element_List18CollectionViewCell *cell = [list dequeueReusableCellWithReuseIdentifier:@"shelf" forIndexPath:path];
            cell.heading.text = self.unavailableCase || self.phase == 3 || (self.phase == 2 && [identifier integerValue] % 2)
                ? @"Visible shelf" : @"Hidden shelf";
            return cell;
        }];
    [self.view addSubview:self.list];
}
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self applyPhase];
}
- (void)applyPhase {
    self.generation = [ShelfFeedFixture generation:self.unavailableCase ? 0 : self.phase];
    if (self.unavailableCase) {
        [ShelfFeedFixture publish:self.generation renderer:self.renderer];
        self.collectionViewRenderer = self.phase == 0 ? nil : self.renderer;
        if (self.phase == 0) {
            afterCommit = ^{ self.collectionViewRenderer = self.renderer; };
        }
    } else if (self.phase == 2) {
        // The model trails the commit: at commit neither current nor previous is this generation.
        // Publishing later must not make an older generation's classifications hide the new cells.
        afterCommit = ^{ [ShelfFeedFixture publish:self.generation renderer:self.renderer]; };
    } else {
        [ShelfFeedFixture publish:self.generation renderer:self.renderer];
        if (self.phase == 1 && ![NSProcessInfo.processInfo.environment[@"SG_SHELF_CASE"] isEqualToString:@"trailing"]) {
            // The next model leads the pending UIKit commit, retaining the committed model as previous.
            [ShelfFeedFixture publish:[ShelfFeedFixture generation:3] renderer:self.renderer];
        }
    }
    NSDiffableDataSourceSnapshot *snapshot = [self.generation snapshot];
    NSLog(@"[harness] submitting phase %lu generation %@ snapshot %p", (unsigned long)self.phase,
        [[(NSObject *)[snapshot impl] state] generationID], [[(NSObject *)[snapshot impl] state] dataSourceSnapshot]);
    id sourceImpl = [self.source impl];
    id snapshotImpl = [snapshot impl];
    dispatch_async(self.applyQueue, ^{
        // Exercise the entry the tweak hooks directly: callers are allowed to submit off-main.
        [sourceImpl applyDifferencesFromSnapshot:snapshotImpl animatingDifferences:NO completion:^{
            HARNESS_CHECK(NSThread.isMainThread);
            [self settle:24];
        }];
    });
}
- (void)settle:(NSUInteger)passes {
    [self.list layoutIfNeeded];
    if (passes) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self settle:passes - 1]; });
        return;
    }
    HARNESS_CHECK(self.list.numberOfSections == 12);
    if (self.unavailableCase) {
        HARNESS_CHECK(self.list.collectionViewLayout.collectionViewContentSize.height == (self.phase == 0 ? 2688 : 0));
        if (self.phase == 0) {
            NSLog(@"[harness] PASS unavailable model is not retried during repeated layouts");
            self.phase++;
            [self applyPhase];
            return;
        }
        NSLog(@"[harness] PASS next snapshot retries previously unavailable extraction");
        [NSUserDefaults.standardUserDefaults removeObjectForKey:SGRHomeShelfHideKey(@"Hidden shelf")];
        exit(0);
    }
    if (self.phase == 2) {
        // Without a model for this commit, shelves in sight are classified by their measured cells: the
        // visible ones (odd identifiers, even sections after the reversal) keep their height and the hidden
        // ones between them close. Shelves below the 800pt viewport are never measured and keep their estimate.
        HARNESS_CHECK(self.list.collectionViewLayout.collectionViewContentSize.height > 0);
        for (NSInteger section = 0; section < 7; section++) {
            CGFloat height = [self.list.collectionViewLayout layoutAttributesForItemAtIndexPath:
                [NSIndexPath indexPathForItem:0 inSection:section]].frame.size.height;
            HARNESS_CHECK(section % 2 ? height == 0 : height == 200);
        }
        HARNESS_CHECK([self.list cellForItemAtIndexPath:[NSIndexPath indexPathForItem:0 inSection:0]] != nil);
        HARNESS_CHECK([self.list cellForItemAtIndexPath:[NSIndexPath indexPathForItem:0 inSection:1]] == nil);
        NSLog(@"[harness] PASS trailing model does not lend stale classifications to a same-identity reordered commit");
        self.phase++;
        [self applyPhase];
        return;
    }
    if (self.phase == 3) {
        HARNESS_CHECK(self.list.collectionViewLayout.collectionViewContentSize.height == 2688);
        NSLog(@"[harness] PASS next generation replaces unavailable and previous classifications");
        [NSUserDefaults.standardUserDefaults removeObjectForKey:SGRHomeShelfHideKey(@"Hidden shelf")];
        exit(0);
    }
    HARNESS_CHECK(self.list.collectionViewLayout.collectionViewContentSize.height == 0);
    HARNESS_CHECK(self.list.visibleCells.count == 0);
    NSLog(@"[harness] PASS %@", self.phase == 0 ? @"all hidden shelves preserve the snapshot and settle without visible cells"
                                               : @"committed hidden previews are not constructed");
    self.phase++;
    [self applyPhase];
}
@end

@interface ShelvesDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end
@implementation ShelvesDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController = [Home_EvoPageImplShelvesController new];
    [self.window makeKeyAndVisible];
    return YES;
}
@end
static void failed(NSException *exception) {
    NSLog(@"[harness] FAIL %@", exception);
    exit(1);
}
int main(int argc, char **argv) {
    @autoreleasepool {
        NSSetUncaughtExceptionHandler(failed);
        Method method = class_getInstanceMethod(NSClassFromString(@"__UIDiffableDataSource"), NSSelectorFromString(@"_storeState:"));
        HARNESS_CHECK(method != NULL);
        storeState = (void *)method_setImplementation(method, (IMP)observeStoreState);
        @try {
            return UIApplicationMain(argc, argv, nil, NSStringFromClass(ShelvesDelegate.class));
        } @catch (NSException *exception) {
            failed(exception);
            return 1;
        }
    }
}
