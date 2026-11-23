// Spotify's Browse page (the Search tab before anything is typed) mocked for Redesigned/Search/SearchSections.x: a
// self-sizing compositional list (id=BrowsePage.ContentScrollView) of Element_List.CollectionViewCell cells whose content
// view is the BrowseStructure's, as trees/clean/search/01.txt has them: the two watch feed carousels first, each its own
// section (224pt, 16pt and 24pt after them), then 21 category cards two to a row (108pt, 8pt apart) with 16pt under the
// last row. The list starts under Spotify's header by its content inset (120pt) and ends over the tab bar (100pt). The
// page's layout pass calls SGRSearchCloseGap as SearchPage.x's does.
//
// It checks, with both collapse switches on (their default): the carousels collapse and the first card rests at the top of
// the list's inset as if they had never been there; scrolled to the end, the last row stands 16pt over the end of the
// content and over the tab bar's inset, as Spotify's layout puts it, not 16pt plus the gap the cards moved up by; and once
// it is there nothing lays the list out again. "[harness] SHOT <file>" holds the top and the end for screenshots before the
// checks. Logs "[harness] PASS search" and exits 0, or a FAIL line and exits 1 (../harness-fail.h).
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "../harness-fail.h"
#import "Search.h"

static const CGFloat kCarousel = 224, kCard = 108, kCardSpacing = 8, kCardsBottom = 16, kInsetTop = 120, kInsetBottom = 100;
static const NSInteger kCards = 21;
// What the list leaves after each carousel section.
static const CGFloat kAfterCarousel[] = {16, 24};

@interface _TtC12Element_List18CollectionViewCell : UICollectionViewCell
- (void)showCard:(NSInteger)card;
@end

@implementation _TtC12Element_List18CollectionViewCell {
    UIView *_root, *_entry;
    UILabel *_name;
    NSLayoutConstraint *_height;
}

// Spotify's content view, ElementContentView over the BrowseStructure, as a subclass of the cell's own content view.
static Class browseContent(Class base) {
    static Class cls;
    if (!cls) {
        cls = objc_allocateClassPair(base, "_TtGC12Element_List18ElementContentViewV22Browse_BrowsePageImpl15BrowseStructure_", 0);
        objc_registerClassPair(cls);
    }
    return cls;
}

static void pin(UIView *view, UIView *into) {
    view.translatesAutoresizingMaskIntoConstraints = NO;
    [into addSubview:view];
    [NSLayoutConstraint activateConstraints:@[
        [view.topAnchor constraintEqualToAnchor:into.topAnchor], [view.bottomAnchor constraintEqualToAnchor:into.bottomAnchor],
        [view.leadingAnchor constraintEqualToAnchor:into.leadingAnchor], [view.trailingAnchor constraintEqualToAnchor:into.trailingAnchor],
    ]];
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    object_setClass(self.contentView, browseContent(object_getClass(self.contentView)));
    // ElementView<BrowseStructure>, then the cell's own root.
    UIView *element = [UIView new];
    pin(element, self.contentView);
    _root = [UIView new];
    pin(_root, element);
    _height = [_root.heightAnchor constraintEqualToConstant:kCard];
    _height.active = YES;
    _entry = [UIView new];
    pin(_entry, _root);
    _name = [UILabel new];
    _name.font = [UIFont boldSystemFontOfSize:17];
    _name.textColor = UIColor.whiteColor;
    _name.frame = CGRectMake(12, 12, 150, 22);
    [_root addSubview:_name];
    return self;
}

// A category card, or with a negative `card` a watch feed carousel.
- (void)showCard:(NSInteger)card {
    BOOL isCard = card >= 0;
    _root.accessibilityIdentifier = isCard ? @"Components.UI.CategoryCardBrowse" : nil;
    _entry.accessibilityIdentifier = isCard ? nil : @"WatchFeedCarouselEntryPointElement";
    _root.backgroundColor = isCard ? [UIColor colorWithHue:card / (CGFloat)kCards saturation:0.6 brightness:0.7 alpha:1] : UIColor.darkGrayColor;
    _root.layer.cornerRadius = 8;
    _name.text = isCard ? [NSString stringWithFormat:@"Category %ld", (long)card + 1] : @"Playlists you can watch";
    _height.constant = isCard ? kCard : kCarousel;
}
@end

// The list, counting its layout passes.
@interface SGRHarnessBrowseList : UICollectionView
@property (nonatomic) NSUInteger passes;
@end

@implementation SGRHarnessBrowseList
- (void)layoutSubviews {
    [super layoutSubviews];
    self.passes++;
}
@end

@interface SGRHarnessSearchPage : UIViewController <UICollectionViewDataSource>
@property (nonatomic, strong) SGRHarnessBrowseList *list;
@end

@implementation SGRHarnessSearchPage
- (void)loadView {
    UICollectionViewCompositionalLayout *layout = [[UICollectionViewCompositionalLayout alloc] initWithSectionProvider:
        ^NSCollectionLayoutSection *(NSInteger section, id<NSCollectionLayoutEnvironment> environment) {
        BOOL cards = section == 2;
        NSCollectionLayoutDimension *height = [NSCollectionLayoutDimension estimatedDimension:cards ? kCard : kCarousel];
        NSCollectionLayoutItem *item = [NSCollectionLayoutItem itemWithLayoutSize:
            [NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension fractionalWidthDimension:cards ? 0.5 : 1] heightDimension:height]];
        NSCollectionLayoutGroup *group = [NSCollectionLayoutGroup horizontalGroupWithLayoutSize:
            [NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension fractionalWidthDimension:1] heightDimension:height]
            repeatingSubitem:item count:cards ? 2 : 1];
        group.interItemSpacing = [NSCollectionLayoutSpacing fixedSpacing:kCardSpacing];
        NSCollectionLayoutSection *layoutSection = [NSCollectionLayoutSection sectionWithGroup:group];
        layoutSection.interGroupSpacing = kCardSpacing;
        layoutSection.contentInsets = cards ? NSDirectionalEdgeInsetsMake(0, 16, kCardsBottom, 16)
                                            : NSDirectionalEdgeInsetsMake(0, 0, kAfterCarousel[section], 0);
        return layoutSection;
    }];
    self.view = [[UIView alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.view.backgroundColor = UIColor.blackColor;
    self.list = [[SGRHarnessBrowseList alloc] initWithFrame:self.view.bounds collectionViewLayout:layout];
    self.list.accessibilityIdentifier = SGRSearchListIdentifier;
    self.list.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.list.backgroundColor = UIColor.blackColor;
    self.list.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    self.list.contentInset = UIEdgeInsetsMake(kInsetTop, 0, kInsetBottom, 0);
    self.list.contentOffset = CGPointMake(0, -kInsetTop);
    self.list.dataSource = self;
    [self.list registerClass:_TtC12Element_List18CollectionViewCell.class forCellWithReuseIdentifier:@"cell"];
    [self.view addSubview:self.list];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    SGRSearchCloseGap(self.list);
}

- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView *)list { return 3; }
- (NSInteger)collectionView:(UICollectionView *)list numberOfItemsInSection:(NSInteger)section { return section == 2 ? kCards : 1; }
- (UICollectionViewCell *)collectionView:(UICollectionView *)list cellForItemAtIndexPath:(NSIndexPath *)path {
    _TtC12Element_List18CollectionViewCell *cell = [list dequeueReusableCellWithReuseIdentifier:@"cell" forIndexPath:path];
    [cell showCard:path.section == 2 ? path.item : -1];
    return cell;
}
@end

static void spin(NSTimeInterval seconds) {
    [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:seconds]];
}

static void shot(UIWindow *window, NSString *name) {
    [window layoutIfNeeded];
    UIImage *image = [[[UIGraphicsImageRenderer alloc] initWithSize:window.bounds.size] imageWithActions:^(UIGraphicsImageRendererContext *c) {
        HARNESS_CHECK([window drawViewHierarchyInRect:window.bounds afterScreenUpdates:YES]);
    }];
    NSString *file = [[NSHomeDirectory() stringByAppendingPathComponent:@"Documents"] stringByAppendingPathComponent:
                      [NSString stringWithFormat:@"search-%@.png", name]];
    HARNESS_CHECK([UIImagePNGRepresentation(image) writeToFile:file atomically:YES]);
    NSLog(@"[harness] SHOT %@", file);
}

// The cards on screen, in the page, by where they are drawn.
static NSArray<UIView *> *cardsShown(UICollectionView *list, UIView *page) {
    NSMutableArray<UIView *> *cards = [NSMutableArray array];
    for (UICollectionViewCell *cell in list.visibleCells) {
        if (cell.bounds.size.height >= 1 && !cell.contentView.hidden && [list indexPathForCell:cell].section == 2) [cards addObject:cell];
    }
    return [cards sortedArrayUsingComparator:^NSComparisonResult(UIView *a, UIView *b) {
        return [@(CGRectGetMinY(a.frame)) compare:@(CGRectGetMinY(b.frame))];
    }];
}

static void expectNear(NSString *what, CGFloat actual, CGFloat expected) {
    if (fabs(actual - expected) > 0.5) HARNESS_FAIL(@"%@: %.1f, expected %.1f", what, actual, expected);
    NSLog(@"[harness] %@: %.1f", what, actual);
}

static void check(UIWindow *window, SGRHarnessSearchPage *page) {
    SGRHarnessBrowseList *list = page.list;
    spin(1.5);
    [page.view layoutIfNeeded];
    shot(window, @"top");
    // At the top: the first row of cards right under Spotify's header, where the list's inset puts its content.
    UIView *first = cardsShown(list, page.view).firstObject;
    HARNESS_CHECK(first);
    expectNear(@"the first card's top on the page", [list convertRect:first.frame toView:page.view].origin.y, kInsetTop);

    // Scrolled as far as the list goes: the last row 16pt over the content's end, which sits on the tab bar's inset.
    CGFloat end = list.contentSize.height + list.adjustedContentInset.bottom - list.bounds.size.height;
    list.contentOffset = CGPointMake(0, end);
    [list layoutIfNeeded];
    spin(0.3);
    shot(window, @"end");
    UIView *last = cardsShown(list, page.view).lastObject;
    HARNESS_CHECK(last);
    CGFloat bottom = CGRectGetMaxY([list convertRect:last.frame toView:page.view]);
    expectNear(@"the space under the last row at the end", page.view.bounds.size.height - kInsetBottom - bottom, kCardsBottom);

    // Settled there: nothing lays the list out again.
    list.passes = 0;
    spin(0.5);
    if (list.passes) HARNESS_FAIL(@"the list laid out %lu times while nothing changed", (unsigned long)list.passes);

    // And back at the top, as it was.
    list.contentOffset = CGPointMake(0, -kInsetTop);
    [list layoutIfNeeded];
    spin(0.3);
    first = cardsShown(list, page.view).firstObject;
    expectNear(@"the first card's top on the page again", [list convertRect:first.frame toView:page.view].origin.y, kInsetTop);
    NSLog(@"[harness] PASS search: the cards close up under the header and the list ends %.0fpt under the last row", kCardsBottom);
    exit(0);
}

@interface SGRHarnessDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation SGRHarnessDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    SGRHarnessSearchPage *page = [SGRHarnessSearchPage new];
    self.window.rootViewController = page;
    [self.window makeKeyAndVisible];
    UIWindow *window = self.window;
    // From a timer: the checks run the run loop.
    [NSTimer scheduledTimerWithTimeInterval:0 repeats:NO block:^(NSTimer *timer) { check(window, page); }];
    return YES;
}
@end

// Before every %ctor, so the redesign's gate reads on.
__attribute__((constructor(101))) static void sgr_harnessDefaults(void) {
    [NSUserDefaults.standardUserDefaults setBool:YES forKey:@"spotifyglass.redesign"];
}

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(SGRHarnessDelegate.class));
    }
}
