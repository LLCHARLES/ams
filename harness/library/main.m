// A mock of Spotify's Your Library page under its own class names and accessibility identifiers, built from
// trees/clean/library/03.txt (recorded 2026-09-16), so Redesigned/Library/LibraryHeader.x can be laid out and
// looked at on the Mac. It plays issue #21: the header's model arriving after the page has laid out, the buttons
// it shows placed by Spotify's stack on a pass of its own. `first` on the launch line stops there, `back` then
// gives the page the pass it gets on the way back from a playlist, `steady` builds the header with the model
// already in it. `nocreate` leaves Create out of the model, `norecents` Recents (the account the tree is of).
//
// `wrapped` puts the header in a plain UIStackView the way 9.2.0 does, the header's height Auto Layout's.
//
// `check` runs assertions instead and exits nonzero on the first failure (harness-fail.h): without `compact` the
// header is restyled (large title, avatar at the trailing edge), in either shape of the tree; with `compact`
// (spotifyglass.redesign.library.hideChips on) the chips fold away and come back, and the header's menu sorts,
// switches the view and clears a filter through the mock's own controls; `late`, `nosort` and `noclear` play a list
// loading after the page, a list without its sort row and a filter with no clear chip the menu knows; `safearea` the
// top safe area changing under the folded chips, and `bottomfirst` each page pass setting the list's bottom inset on a
// set of its own before the whole inset, the top carried in it as it stands. `look compact`
// opens the menu with a finger for a screenshot. `settings` checks the Library page of Mod Settings and its preview.
#import <UIKit/UIKit.h>
#import <os/log.h>
#import <objc/runtime.h>
#import "../harness-fail.h"
#import "Core/SGCore.h"
#import "Library.h"

void SGRRunKitChecks(void);
void SGHarnessTap(UIWindow *window, CGPoint point);

#define HLog(fmt, ...) os_log(OS_LOG_DEFAULT, "[harness] %{public}s", [NSString stringWithFormat:(fmt), ##__VA_ARGS__].UTF8String)

static const CGFloat kHeaderHeight = 159.33;
// Spotify's header: the control row on the safe area and the chips under it, 159.33pt under the 62pt of an iPhone 17
// Pro; the list is inset by all of it.
static const CGFloat kRowHeight = 48, kChipsHeight = 49.33;
static CGFloat spotifyHeaderHeight(UIView *view) {
    return (view.window ? view.safeAreaInsets.top : 62) + kRowHeight + kChipsHeight;
}

#pragma mark - Spotify's classes, by name

@interface _TtCO22Reprise_LiquidGlassKit11LiquidGlass12GradientView : UIView @end
@implementation _TtCO22Reprise_LiquidGlassKit11LiquidGlass12GradientView @end

@interface _TtC29ListeningActivity_ElementsKit21AdaptiveFaceContainer : UIView @end
@implementation _TtC29ListeningActivity_ElementsKit21AdaptiveFaceContainer @end

@interface _TtC21YourLibrary_CommonKit35YourLibraryHeaderContentFiltersView : UIView @end
@implementation _TtC21YourLibrary_CommonKit35YourLibraryHeaderContentFiltersView @end

@interface _TtC28YourLibrary_YourLibraryXImpl22YourLibraryContentView : UIView @end
@implementation _TtC28YourLibrary_YourLibraryXImpl22YourLibraryContentView @end

@interface _TtC22YourLibrary_FolderImpl10FolderView : UIView @end
@implementation _TtC22YourLibrary_FolderImpl10FolderView @end

@interface _TtC21YourLibrary_CommonKit25YourLibraryCollectionView : UICollectionView @end
@implementation _TtC21YourLibrary_CommonKit25YourLibraryCollectionView @end

// Encore's button: a 48pt box with its 24pt glyph in the middle.
@interface MockEncoreButton : UIControl @end
@implementation MockEncoreButton @end

// LegacyUI_ECMCoreKit.AutoLayoutStackView: the arranged views in a plain container view, chained by constraints
// the stack rebuilds when one of them shows or hides. The real one watches its views' hidden and folds the
// changes into one update (its ivars: observationsDictionary, needsCoalescedLayoutUpdate); the mock folds them
// into the next turn of the main queue, so a page laying out in the turn the header's model lands in still
// sees each button where it stood before. A hidden view leaves the chain and sits at the container's origin,
// where 03.txt has the hidden Recents.
@interface _TtC19LegacyUI_ECMCoreKit19AutoLayoutStackView : UIView
@property (nonatomic, readonly) UIView *containerView;
@property (nonatomic, copy) NSArray<UIView *> *arrangedSubviews;
@end

@implementation _TtC19LegacyUI_ECMCoreKit19AutoLayoutStackView {
    NSArray<NSLayoutConstraint *> *_layoutConstraints;
    BOOL _needsCoalescedLayoutUpdate;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    _containerView = [[UIView alloc] initWithFrame:self.bounds];
    _containerView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self addSubview:_containerView];
    return self;
}

- (void)setArrangedSubviews:(NSArray<UIView *> *)views {
    _arrangedSubviews = [views copy];
    for (UIView *view in views) {
        view.translatesAutoresizingMaskIntoConstraints = NO;
        [_containerView addSubview:view];
        [view addObserver:self forKeyPath:@"hidden" options:0 context:NULL];
    }
    [self rebuild];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if (_needsCoalescedLayoutUpdate) return;
    _needsCoalescedLayoutUpdate = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        self->_needsCoalescedLayoutUpdate = NO;
        [self rebuild];
        HLog(@"stack rebuilt its constraints");
    });
}

- (void)rebuild {
    if (_layoutConstraints) [NSLayoutConstraint deactivateConstraints:_layoutConstraints];
    NSMutableArray<NSLayoutConstraint *> *constraints = [NSMutableArray array];
    UIView *previous = nil;
    for (UIView *view in _arrangedSubviews) {
        if (view.hidden) {
            [constraints addObject:[view.leadingAnchor constraintEqualToAnchor:_containerView.leadingAnchor]];
            [constraints addObject:[view.topAnchor constraintEqualToAnchor:_containerView.topAnchor]];
            continue;
        }
        [constraints addObject:[view.centerYAnchor constraintEqualToAnchor:_containerView.centerYAnchor]];
        [constraints addObject:[view.leadingAnchor constraintEqualToAnchor:previous ? previous.trailingAnchor : _containerView.leadingAnchor]];
        previous = view;
    }
    if (previous) [constraints addObject:[previous.trailingAnchor constraintEqualToAnchor:_containerView.trailingAnchor]];
    _layoutConstraints = constraints;
    [NSLayoutConstraint activateConstraints:constraints];
}

- (void)dealloc {
    for (UIView *view in _arrangedSubviews) [view removeObserver:self forKeyPath:@"hidden"];
}
@end

// The header lays its own children out by frame: the scrim over all of it, the control row off the safe area,
// the chips under the row. `chained` (9.2.0's, in its stack) has Auto Layout place the row and the chips and give
// the header its height instead: row.top on the safe area, chips.top on the row's bottom, chips.bottom == the
// header's (the constraints read off 9.2.0's header in the simulator).
@interface _TtC28YourLibrary_YourLibraryXImpl21YourLibraryHeaderView : UIView
@property (nonatomic, strong) UIView *gradient, *row, *filters;
@property (nonatomic) BOOL chained;
@end

@implementation _TtC28YourLibrary_YourLibraryXImpl21YourLibraryHeaderView
- (void)chain {
    self.chained = YES;
    self.row.translatesAutoresizingMaskIntoConstraints = NO;
    self.filters.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [self.row.topAnchor constraintEqualToAnchor:self.safeAreaLayoutGuide.topAnchor],
        [self.row.heightAnchor constraintEqualToConstant:48],
        [self.row.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [self.row.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [self.filters.topAnchor constraintEqualToAnchor:self.row.bottomAnchor],
        [self.filters.heightAnchor constraintEqualToConstant:49.33],
        [self.filters.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [self.filters.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [self.filters.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
    ]];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.bounds.size.width;
    CGFloat top = self.window ? self.safeAreaInsets.top : 62;
    self.gradient.frame = CGRectMake(0, 0, width, spotifyHeaderHeight(self));
    if (self.chained) return;
    self.row.frame = CGRectMake(0, top, width, kRowHeight);
    self.filters.frame = CGRectMake(0, top + kRowHeight, width, kChipsHeight);
}
@end

// The page: its content the size of it, the header over it at its full height and the list inset by that height,
// all three stated again on every pass the way Spotify's does.
@interface _TtC28YourLibrary_YourLibraryXImpl15YourLibraryView : UIView
// `wrapper`: 9.2.0's plain UIStackView holding the header in its place (design/spotify-920/920-library-tree.txt:488),
// pinned at its top and sides only, so as tall as the header it arranges.
@property (nonatomic, strong) UIView *content, *header, *wrapper;
@property (nonatomic, strong) UICollectionView *list;
// `bottomfirst`: each pass sets the list's bottom inset on a set of its own first, the top carried in it as the list
// has it, then the whole inset.
@property (nonatomic) BOOL bottomFirst;
@end

@implementation _TtC28YourLibrary_YourLibraryXImpl15YourLibraryView {
    BOOL _rested;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    self.content.frame = self.bounds;
    self.list.frame = self.content.bounds;
    if (!self.wrapper) self.header.frame = CGRectMake(0, 0, self.bounds.size.width, spotifyHeaderHeight(self));
    if (self.bottomFirst) {
        UIEdgeInsets carried = self.list.contentInset;
        carried.bottom = self.safeAreaInsets.bottom;
        self.list.contentInset = carried;
    }
    UIEdgeInsets inset = self.list.contentInset;
    inset.top = spotifyHeaderHeight(self);
    self.list.contentInset = inset;
    // The list opens at its top, under the header.
    if (!_rested) {
        _rested = YES;
        self.list.contentOffset = CGPointMake(0, -self.list.contentInset.top);
    }
}
@end

#pragma mark - building the page

static UIView *box(UIView *parent, Class cls, CGRect frame, NSString *identifier) {
    UIView *view = [[cls alloc] initWithFrame:frame];
    view.accessibilityIdentifier = identifier;
    if (parent) [parent addSubview:view];
    return view;
}

static void pinSize(UIView *view, CGFloat width, CGFloat height) {
    [view.widthAnchor constraintEqualToConstant:width].active = YES;
    [view.heightAnchor constraintEqualToConstant:height].active = YES;
}

static UIView *button(NSString *identifier, NSString *symbol) {
    UIView *control = box(nil, MockEncoreButton.class, CGRectMake(0, 0, 48, 48), identifier);
    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:20 weight:UIImageSymbolWeightRegular];
    UIImageView *glyph = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:symbol withConfiguration:config]];
    glyph.frame = CGRectMake(12, 12, 24, 24);
    glyph.contentMode = UIViewContentModeCenter;
    glyph.tintColor = UIColor.whiteColor;
    [control addSubview:glyph];
    pinSize(control, 48, 48);
    return control;
}

static UIImage *avatar(void) {
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(64, 64)];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        [[UIColor colorWithRed:0.55 green:0.85 blue:0.55 alpha:1] setFill];
        UIRectFill(CGRectMake(0, 0, 64, 64));
        [[UIColor colorWithRed:0.25 green:0.22 blue:0.2 alpha:1] setFill];
        [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(18, 10, 28, 32)] fill];
        [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(6, 40, 52, 40)] fill];
    }];
}

static UIView *face(void) {
    UIView *container = box(nil, _TtC29ListeningActivity_ElementsKit21AdaptiveFaceContainer.class, CGRectMake(0, 0, 48, 48), nil);
    UIView *drawer = box(container, MockEncoreButton.class, CGRectMake(0, 0, 48, 48), @"Components.UI.SideDrawerButton");
    UIImageView *image = [[UIImageView alloc] initWithImage:avatar()];
    image.frame = CGRectMake(8, 8, 32, 32);
    image.layer.cornerRadius = 16;
    image.clipsToBounds = YES;
    [drawer addSubview:image];
    pinSize(container, 48, 48);
    return container;
}

static UIView *spotifyTitle(void) {
    UIView *encore = box(nil, UIView.class, CGRectZero, @"YourLibraryHeader.title");
    UILabel *label = [UILabel new];
    label.text = @"Your Library";
    label.font = [UIFont boldSystemFontOfSize:21];
    label.textColor = UIColor.whiteColor;
    label.accessibilityIdentifier = @"YourLibraryHeader.title-internal";
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [encore addSubview:label];
    [NSLayoutConstraint activateConstraints:@[
        [label.leadingAnchor constraintEqualToAnchor:encore.leadingAnchor],
        [label.trailingAnchor constraintEqualToAnchor:encore.trailingAnchor],
        [label.topAnchor constraintEqualToAnchor:encore.topAnchor],
        [label.bottomAnchor constraintEqualToAnchor:encore.bottomAnchor],
    ]];
    return encore;
}

#pragma mark - the chips

// The chips: a collection view, Layout.CollectionView, in YourLibraryHeaderContentFiltersView (the identifier and
// the clear chip's class name as Spotify 9.1.x has them). With a filter on, a clear chip comes first, then the
// chosen chip drawn as chosen; selecting the clear chip clears the filter, through the collection's delegate.
@interface SGRHarnessChipCell : UICollectionViewCell
@property (nonatomic, strong) UILabel *label;
@property (nonatomic, strong) UIImageView *glyph;
@end

@implementation SGRHarnessChipCell
- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.contentView.layer.cornerRadius = 16;
    self.contentView.clipsToBounds = YES;
    _label = [[UILabel alloc] initWithFrame:self.contentView.bounds];
    _label.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _label.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    _label.textColor = UIColor.whiteColor;
    _label.textAlignment = NSTextAlignmentCenter;
    [self.contentView addSubview:_label];
    _glyph = [[UIImageView alloc] initWithFrame:CGRectInset(self.contentView.bounds, 9, 9)];
    _glyph.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _glyph.contentMode = UIViewContentModeScaleAspectFit;
    _glyph.tintColor = UIColor.whiteColor;
    [self.contentView addSubview:_glyph];
    return self;
}
@end

// Spotify's clear chip, by the part of its class name the menu knows it by.
@interface SGRHarnessClearChipCell : SGRHarnessChipCell @end
@implementation SGRHarnessClearChipCell @end
// `noclear`: the same chip under a class name the menu does not know.
@interface SGRHarnessResetCell : SGRHarnessChipCell @end
@implementation SGRHarnessResetCell @end

static NSString *const kClearLabel = @"Clear all filters";

@interface SGRHarnessChips : NSObject <UICollectionViewDataSource, UICollectionViewDelegateFlowLayout>
@property (nonatomic, copy) NSString *filter;
@property (nonatomic) BOOL unknownClear;
@property (nonatomic) NSUInteger clears;
@end

@implementation SGRHarnessChips

- (NSArray<NSString *> *)items {
    return self.filter ? @[@"", self.filter] : @[@"Playlists", @"Podcasts", @"Albums", @"Artists"];
}

- (NSInteger)collectionView:(UICollectionView *)view numberOfItemsInSection:(NSInteger)section {
    return (NSInteger)self.items.count;
}

- (BOOL)isClear:(NSIndexPath *)path {
    return self.filter && path.item == 0;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)view cellForItemAtIndexPath:(NSIndexPath *)path {
    BOOL clear = [self isClear:path];
    SGRHarnessChipCell *cell = [view dequeueReusableCellWithReuseIdentifier:clear ? (self.unknownClear ? @"reset" : @"clear") : @"chip" forIndexPath:path];
    NSString *name = self.items[(NSUInteger)path.item];
    BOOL chosen = !clear && [name isEqualToString:self.filter];
    cell.label.text = clear ? nil : name;
    cell.label.accessibilityTraits = UIAccessibilityTraitButton | (chosen ? UIAccessibilityTraitSelected : 0);
    cell.glyph.image = clear ? [UIImage systemImageNamed:@"xmark"] : nil;
    cell.glyph.accessibilityLabel = clear ? kClearLabel : nil;
    cell.contentView.backgroundColor = chosen ? [UIColor colorWithRed:0.12 green:0.84 blue:0.38 alpha:1] : [UIColor colorWithWhite:0.18 alpha:1];
    cell.label.textColor = chosen ? UIColor.blackColor : UIColor.whiteColor;
    return cell;
}

- (CGSize)collectionView:(UICollectionView *)view layout:(UICollectionViewLayout *)layout sizeForItemAtIndexPath:(NSIndexPath *)path {
    if ([self isClear:path]) return CGSizeMake(32, 32);
    NSString *name = self.items[(NSUInteger)path.item];
    return CGSizeMake(ceil([name sizeWithAttributes:@{NSFontAttributeName: [UIFont systemFontOfSize:13 weight:UIFontWeightMedium]}].width) + 32, 32);
}

- (void)collectionView:(UICollectionView *)view didSelectItemAtIndexPath:(NSIndexPath *)path {
    if ([self isClear:path]) {
        self.filter = nil;
        self.clears++;
    } else {
        self.filter = self.items[(NSUInteger)path.item];
    }
    HLog(@"chips: filter %@", self.filter ?: @"none");
    [view reloadData];
    [view layoutIfNeeded];
}

@end

static UICollectionView *chips(UIView *filters, SGRHarnessChips *model) {
    UICollectionViewFlowLayout *layout = [UICollectionViewFlowLayout new];
    layout.scrollDirection = UICollectionViewScrollDirectionHorizontal;
    layout.minimumInteritemSpacing = 8;
    layout.sectionInset = UIEdgeInsetsMake(0, 16, 0, 16);
    UICollectionView *view = [[UICollectionView alloc] initWithFrame:filters.bounds collectionViewLayout:layout];
    view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    view.accessibilityIdentifier = @"Layout.CollectionView";
    view.backgroundColor = UIColor.clearColor;
    view.showsHorizontalScrollIndicator = NO;
    [view registerClass:SGRHarnessChipCell.class forCellWithReuseIdentifier:@"chip"];
    [view registerClass:SGRHarnessClearChipCell.class forCellWithReuseIdentifier:@"clear"];
    [view registerClass:SGRHarnessResetCell.class forCellWithReuseIdentifier:@"reset"];
    view.dataSource = model;
    view.delegate = model;
    [filters addSubview:view];
    return view;
}

#pragma mark - the list

// The list: its sort row first (YourLibraryContent.sort, YourLibraryContent.gridToggle), then the items as grid
// cards (Components.UI.CardLibrary) or list rows. The sort button cycles the order, as Spotify's sheet would, and
// the toggle switches the view; each counts its taps. `late` loads the list after the page first laid out,
// `nosort` has it without the sort row.
// Encore's controls: a glyph and, for the sort button, the order in a label beside it.
@interface SGRHarnessSortCell : UICollectionViewCell
@property (nonatomic, strong) UIControl *sort, *toggle;
@property (nonatomic, strong) UILabel *order;
@property (nonatomic, strong) UIImageView *toggleGlyph;
@end

@implementation SGRHarnessSortCell
- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    _sort = [[MockEncoreButton alloc] initWithFrame:CGRectMake(0, 0, 180, frame.size.height)];
    _sort.accessibilityIdentifier = @"YourLibraryContent.sort";
    UIImageView *arrows = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"arrow.up.arrow.down"]];
    arrows.tintColor = UIColor.whiteColor;
    arrows.frame = CGRectMake(0, 10, 20, 20);
    arrows.contentMode = UIViewContentModeScaleAspectFit;
    [_sort addSubview:arrows];
    _order = [[UILabel alloc] initWithFrame:CGRectMake(28, 0, 150, frame.size.height)];
    _order.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    _order.textColor = UIColor.whiteColor;
    [_sort addSubview:_order];
    [self.contentView addSubview:_sort];
    _toggle = [[MockEncoreButton alloc] initWithFrame:CGRectMake(frame.size.width - 40, 0, 40, frame.size.height)];
    _toggle.accessibilityIdentifier = @"YourLibraryContent.gridToggle";
    _toggle.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    _toggleGlyph = [[UIImageView alloc] initWithFrame:CGRectMake(10, 10, 20, 20)];
    _toggleGlyph.tintColor = UIColor.whiteColor;
    _toggleGlyph.contentMode = UIViewContentModeScaleAspectFit;
    [_toggle addSubview:_toggleGlyph];
    [self.contentView addSubview:_toggle];
    return self;
}
@end

@interface SGRHarnessCard : UICollectionViewCell
@property (nonatomic, strong) UIView *cover;
@property (nonatomic, strong) UILabel *title;
@end

@implementation SGRHarnessCard
- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    CGFloat side = frame.size.width;
    _cover = [[UIView alloc] initWithFrame:CGRectMake(0, 0, side, side)];
    _cover.layer.cornerRadius = 6;
    [self.contentView addSubview:_cover];
    _title = [[UILabel alloc] initWithFrame:CGRectMake(0, side + 6, side, 18)];
    _title.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    _title.textColor = UIColor.whiteColor;
    [self.contentView addSubview:_title];
    return self;
}
@end

@interface SGRHarnessRow : UICollectionViewCell
@property (nonatomic, strong) UIView *cover;
@property (nonatomic, strong) UILabel *title;
@end

@implementation SGRHarnessRow
- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    _cover = [[UIView alloc] initWithFrame:CGRectMake(0, 4, 56, 56)];
    _cover.layer.cornerRadius = 4;
    [self.contentView addSubview:_cover];
    _title = [[UILabel alloc] initWithFrame:CGRectMake(68, 22, 240, 20)];
    _title.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    _title.textColor = UIColor.whiteColor;
    [self.contentView addSubview:_title];
    return self;
}
@end

static NSArray<NSString *> *itemNames(void) {
    return @[@"Great songs", @"70s Hits", @"80s Hits", @"Early 2000's", @"Lofi Girl", @"hololive",
             @"Skepta", @"Real Music", @"Aitch", @"New Episodes", @"Tame Impala", @"Chill Mix"];
}

@interface SGRHarnessList : NSObject <UICollectionViewDataSource, UICollectionViewDelegateFlowLayout>
@property (nonatomic) BOOL loaded, grid, sortRow;
@property (nonatomic) NSUInteger sortTaps, toggleTaps;
@property (nonatomic, copy) NSString *order;
@property (nonatomic, weak) UICollectionView *view;
@end

@implementation SGRHarnessList

- (instancetype)init {
    if (!(self = [super init])) return nil;
    _grid = YES;
    _sortRow = YES;
    _order = @"Recents";
    return self;
}

- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView *)view {
    return 2;
}

- (NSInteger)collectionView:(UICollectionView *)view numberOfItemsInSection:(NSInteger)section {
    if (!self.loaded) return 0;
    return section == 0 ? (self.sortRow ? 1 : 0) : 24;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)view cellForItemAtIndexPath:(NSIndexPath *)path {
    if (path.section == 0) {
        SGRHarnessSortCell *cell = [view dequeueReusableCellWithReuseIdentifier:@"sort" forIndexPath:path];
        cell.order.text = self.order;
        [cell.sort removeTarget:nil action:NULL forControlEvents:UIControlEventAllEvents];
        [cell.sort addTarget:self action:@selector(sorted) forControlEvents:UIControlEventTouchUpInside];
        cell.toggleGlyph.image = [UIImage systemImageNamed:self.grid ? @"list.bullet" : @"square.grid.2x2"];
        cell.toggle.accessibilityLabel = self.grid ? @"Switch to list view" : @"Switch to grid view";
        [cell.toggle removeTarget:nil action:NULL forControlEvents:UIControlEventAllEvents];
        [cell.toggle addTarget:self action:@selector(toggled) forControlEvents:UIControlEventTouchUpInside];
        return cell;
    }
    NSString *name = itemNames()[(NSUInteger)path.item % itemNames().count];
    UIColor *color = [UIColor colorWithHue:fmod(path.item * 0.137, 1) saturation:0.55 brightness:0.6 alpha:1];
    if (self.grid) {
        SGRHarnessCard *card = [view dequeueReusableCellWithReuseIdentifier:@"card" forIndexPath:path];
        card.contentView.accessibilityIdentifier = @"Components.UI.CardLibrary";
        card.title.text = name;
        card.cover.backgroundColor = color;
        return card;
    }
    SGRHarnessRow *row = [view dequeueReusableCellWithReuseIdentifier:@"row" forIndexPath:path];
    row.title.text = name;
    row.cover.backgroundColor = color;
    return row;
}

- (CGSize)collectionView:(UICollectionView *)view layout:(UICollectionViewLayout *)layout sizeForItemAtIndexPath:(NSIndexPath *)path {
    CGFloat width = view.bounds.size.width - 32;
    if (path.section == 0) return CGSizeMake(width, 40);
    if (!self.grid) return CGSizeMake(width, 64);
    CGFloat side = floor((width - 2 * 14) / 3);
    return CGSizeMake(side, side + 44);
}

- (UIEdgeInsets)collectionView:(UICollectionView *)view layout:(UICollectionViewLayout *)layout insetForSectionAtIndex:(NSInteger)section {
    return section == 0 ? UIEdgeInsetsMake(0, 16, 8, 16) : UIEdgeInsetsMake(0, 16, 0, 16);
}

- (CGFloat)collectionView:(UICollectionView *)view layout:(UICollectionViewLayout *)layout minimumLineSpacingForSectionAtIndex:(NSInteger)section {
    return self.grid ? 12 : 4;
}

- (void)sorted {
    NSArray<NSString *> *orders = @[@"Recents", @"Recently added", @"Alphabetical", @"Creator"];
    self.sortTaps++;
    self.order = orders[([orders indexOfObject:self.order] + 1) % orders.count];
    HLog(@"list: sort sheet, now %@", self.order);
    [self.view reloadData];
}

- (void)toggled {
    self.toggleTaps++;
    self.grid = !self.grid;
    HLog(@"list: %@ view", self.grid ? @"grid" : @"list");
    [self.view reloadData];
}

@end

#pragma mark - checks

static void spin(NSTimeInterval seconds) {
    [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:seconds]];
}

static BOOL near(CGFloat a, CGFloat b) {
    return fabs(a - b) < 0.5;
}

// The menu as one line: its sections apart by " | ", each action's title, its subtitle in brackets, and * when it is
// checked.
static NSString *describeMenu(NSArray<UIMenuElement *> *elements) {
    NSMutableArray<NSString *> *sections = [NSMutableArray array];
    for (UIMenuElement *element in elements) {
        NSArray<UIMenuElement *> *children = [element isKindOfClass:UIMenu.class] ? ((UIMenu *)element).children : @[element];
        NSMutableArray<NSString *> *names = [NSMutableArray array];
        for (UIAction *action in children) {
            NSMutableString *name = [action.title mutableCopy];
            if (action.subtitle.length) [name appendFormat:@" (%@)", action.subtitle];
            if (action.state == UIMenuElementStateOn) [name appendString:@"*"];
            [names addObject:name];
        }
        [sections addObject:[names componentsJoinedByString:@", "]];
    }
    return [sections componentsJoinedByString:@" | "];
}

static UIButton *menuButtonIn(UIView *header) {
    for (UIView *sub in header.subviews) if ([sub isKindOfClass:UIButton.class]) return (UIButton *)sub;
    return nil;
}

// The one block ivar of `object`'s class, every ivar listed in the failure when there is not exactly one.
static id blockIn(id object) {
    id block = nil;
    NSMutableString *all = [NSMutableString string];
    unsigned count = 0;
    Ivar *ivars = class_copyIvarList([object class], &count);
    for (unsigned i = 0; i < count; i++) {
        [all appendFormat:@" %s:%s", ivar_getName(ivars[i]), ivar_getTypeEncoding(ivars[i])];
        if (strcmp(ivar_getTypeEncoding(ivars[i]), "@?") != 0) continue;
        if (block) HARNESS_FAIL(@"%@ has more than one block:%@", [object class], all);
        block = object_getIvar(object, ivars[i]);
    }
    free(ivars);
    if (!block) HARNESS_FAIL(@"%@ has no block:%@", [object class], all);
    return block;
}

// What the header's menu button shows as it opens: its one deferred element's provider run, as UIKit runs it.
// UIDeferredMenuElement keeps the provider private, as the block of the object in its _elementProvider.
static NSArray<UIMenuElement *> *menuElements(UIView *page) {
    UIButton *button = menuButtonIn([page valueForKey:@"header"]);
    UIMenuElement *deferred = button.menu.children.firstObject;
    if (button.menu.children.count != 1 || ![deferred isKindOfClass:UIDeferredMenuElement.class]) {
        HARNESS_FAIL(@"the header's menu button %@ has no deferred menu: %@", button, button.menu.children);
    }
    Ivar holder = class_getInstanceVariable(UIDeferredMenuElement.class, "_elementProvider");
    if (!holder) HARNESS_FAIL(@"UIDeferredMenuElement has no _elementProvider");
    id provider = blockIn(object_getIvar(deferred, holder));
    __block NSArray<UIMenuElement *> *elements = nil;
    ((void (^)(void (^)(NSArray<UIMenuElement *> *)))provider)(^(NSArray<UIMenuElement *> *children) { elements = children; });
    if (!elements) HARNESS_FAIL(@"the menu's provider did not complete");
    return elements;
}

static void expectMenu(UIView *page, NSString *expected, NSString *moment) {
    NSString *menu = describeMenu(menuElements(page));
    if (![menu isEqualToString:expected]) HARNESS_FAIL(@"%@: the menu reads \"%@\", expected \"%@\"", moment, menu, expected);
    printf("PASS %s: the menu reads \"%s\"\n", moment.UTF8String, expected.UTF8String);
}

// What a pick in the menu runs: UIKit calls the action's handler.
static void pick(UIView *page, NSString *title) {
    for (UIMenuElement *element in menuElements(page)) {
        NSArray<UIMenuElement *> *children = [element isKindOfClass:UIMenu.class] ? ((UIMenu *)element).children : @[element];
        for (UIAction *action in children) {
            if (![action.title isEqualToString:title]) continue;
            void (^handler)(UIAction *) = [action valueForKey:@"handler"];
            HARNESS_CHECK(handler != nil);
            handler(action);
            return;
        }
    }
    HARNESS_FAIL(@"no %@ in the menu", title);
}

static UILabel *titleIn(UIView *header) {
    for (UIView *sub in header.subviews) if ([sub isMemberOfClass:UILabel.class]) return (UILabel *)sub;
    return nil;
}

// The redesign's folder: a FolderView with its header (back, title, ⋯, plus) and its chips.
@interface _TtC22YourLibrary_FolderImpl16FolderHeaderView : UIView @end
@implementation _TtC22YourLibrary_FolderImpl16FolderHeaderView @end

void SGRRunSettingsChecks(UIWindow *window);

@interface SGRHarnessDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@property (nonatomic, strong) _TtC28YourLibrary_YourLibraryXImpl15YourLibraryView *page;
@property (nonatomic, strong) NSDictionary<NSString *, UIView *> *controls;
@property (nonatomic, strong) SGRHarnessChips *chips;
@property (nonatomic, strong) UICollectionView *chipsView;
@property (nonatomic, strong) SGRHarnessList *items;
@end

@implementation SGRHarnessDelegate

- (UIView *)control:(NSString *)name {
    return self.controls[name];
}

// What the header's model says: which buttons it shows. Setting them is all Spotify's header does on a render;
// the stack places what changed on its own, later.
- (void)render:(NSArray<NSString *> *)shown {
    for (NSString *name in @[@"recents", @"search", @"plus"]) {
        BOOL hidden = ![shown containsObject:name];
        UIView *control = self.controls[name];
        if (control.hidden != hidden) control.hidden = hidden;
    }
    HLog(@"model: %@ shown", [shown componentsJoinedByString:@", "]);
}

- (void)report:(NSString *)moment {
    UIView *header = self.page.header;
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    for (NSString *name in @[@"recents", @"search", @"plus", @"face"]) {
        UIView *control = self.controls[name];
        if (control.hidden) {
            [parts addObject:[NSString stringWithFormat:@"%@ hidden", name]];
            continue;
        }
        CGRect frame = [control.superview convertRect:control.frame toView:header];
        [parts addObject:[NSString stringWithFormat:@"%@ %.0f-%.0f", name, CGRectGetMinX(frame), CGRectGetMaxX(frame)]];
    }
    UILabel *title = nil;
    for (UIView *sub in header.subviews) {
        if ([sub isMemberOfClass:UILabel.class]) title = (UILabel *)sub;
    }
    CGFloat textRight = title ? CGRectGetMinX(title.frame) + MIN(title.bounds.size.width, [title.text sizeWithAttributes:@{NSFontAttributeName: title.font}].width) : 0;
    UIView *filters = [header valueForKey:@"filters"];
    HLog(@"%@: %@; title text %.0f-%.0f, header %.0fpt, list inset %.0f, chips %@", moment,
         [parts componentsJoinedByString:@", "], CGRectGetMinX(title.frame), textRight,
         header.bounds.size.height, self.page.list.contentInset.top,
         !filters ? @"missing" : (filters.alpha < 0.5 ? @"HIDDEN" : [NSString stringWithFormat:@"%.0fpt at y=%.0f",
                                  filters.bounds.size.height, filters.frame.origin.y]));
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    NSArray<NSString *> *args = NSProcessInfo.processInfo.arguments;
    if ([args containsObject:@"kitCheck"]) {
        SGRRunKitChecks();
        exit(0);
    }
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.backgroundColor = UIColor.blackColor;
    if ([args containsObject:@"settings"]) {
        self.window.rootViewController = [UIViewController new];
        [self.window makeKeyAndVisible];
        // From a timer rather than a block on the main queue: the checks run the run loop, and main-queue blocks
        // (the preview's own redraws) cannot run while one is running.
        UIWindow *window = self.window;
        [NSTimer scheduledTimerWithTimeInterval:0 repeats:NO block:^(NSTimer *timer) { SGRRunSettingsChecks(window); }];
        return YES;
    }
    BOOL check = [args containsObject:@"check"];
    BOOL steady = check || [args containsObject:@"steady"];
    NSArray<NSString *> *model = @[@"recents", @"search", @"plus"];
    if ([args containsObject:@"nocreate"]) model = @[@"recents", @"search"];
    if ([args containsObject:@"norecents"]) model = @[@"search", @"plus"];

    UIViewController *root = [UIViewController new];

    _TtC28YourLibrary_YourLibraryXImpl15YourLibraryView *page = [[_TtC28YourLibrary_YourLibraryXImpl15YourLibraryView alloc] initWithFrame:self.window.bounds];
    page.backgroundColor = UIColor.blackColor;
    page.bottomFirst = [args containsObject:@"bottomfirst"];
    self.page = page;

    page.content = box(page, _TtC28YourLibrary_YourLibraryXImpl22YourLibraryContentView.class, page.bounds, nil);
    UICollectionViewFlowLayout *layout = [UICollectionViewFlowLayout new];
    layout.minimumInteritemSpacing = 14;
    self.items = [SGRHarnessList new];
    self.items.loaded = ![args containsObject:@"late"];
    self.items.sortRow = ![args containsObject:@"nosort"];
    _TtC21YourLibrary_CommonKit25YourLibraryCollectionView *list = [[_TtC21YourLibrary_CommonKit25YourLibraryCollectionView alloc] initWithFrame:page.bounds collectionViewLayout:layout];
    list.accessibilityIdentifier = @"YourLibraryContent.collectionView";
    list.backgroundColor = UIColor.blackColor;
    list.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    [list registerClass:SGRHarnessCard.class forCellWithReuseIdentifier:@"card"];
    [list registerClass:SGRHarnessRow.class forCellWithReuseIdentifier:@"row"];
    [list registerClass:SGRHarnessSortCell.class forCellWithReuseIdentifier:@"sort"];
    list.dataSource = self.items;
    list.delegate = self.items;
    self.items.view = list;
    [page.content addSubview:list];
    page.list = list;

    _TtC28YourLibrary_YourLibraryXImpl21YourLibraryHeaderView *header = (id)box(nil, _TtC28YourLibrary_YourLibraryXImpl21YourLibraryHeaderView.class, CGRectMake(0, 0, page.bounds.size.width, kHeaderHeight), nil);
    page.header = header;
    BOOL wrapped = [args containsObject:@"wrapped"];
    if (wrapped) {
        UIStackView *wrapper = [[UIStackView alloc] initWithFrame:header.frame];
        wrapper.axis = UILayoutConstraintAxisVertical;
        wrapper.translatesAutoresizingMaskIntoConstraints = NO;
        [page addSubview:wrapper];
        [wrapper addArrangedSubview:header];
        [NSLayoutConstraint activateConstraints:@[
            [wrapper.topAnchor constraintEqualToAnchor:page.topAnchor],
            [wrapper.leadingAnchor constraintEqualToAnchor:page.leadingAnchor],
            [wrapper.trailingAnchor constraintEqualToAnchor:page.trailingAnchor],
        ]];
        page.wrapper = wrapper;
    } else {
        [page addSubview:header];
    }
    header.gradient = box(header, _TtCO22Reprise_LiquidGlassKit11LiquidGlass12GradientView.class, header.bounds, @"LiquidGlass.GradientView");
    header.gradient.backgroundColor = [UIColor colorWithWhite:0 alpha:0.85];
    header.row = box(header, UIView.class, CGRectMake(0, 62, header.bounds.size.width, 48), nil);
    UIView *inner = box(header.row, UIView.class, header.row.bounds, nil);
    inner.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    _TtC19LegacyUI_ECMCoreKit19AutoLayoutStackView *stack = (id)box(inner, _TtC19LegacyUI_ECMCoreKit19AutoLayoutStackView.class, CGRectMake(8, 0, inner.bounds.size.width - 16, 48), nil);
    stack.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    header.filters = box(header, _TtC21YourLibrary_CommonKit35YourLibraryHeaderContentFiltersView.class, CGRectMake(0, 110, header.bounds.size.width, 49.33), nil);
    self.chips = [SGRHarnessChips new];
    self.chips.unknownClear = [args containsObject:@"noclear"];
    self.chipsView = chips(header.filters, self.chips);
    if (wrapped) [header chain];

    UIView *avatarBox = face();
    UIView *title = spotifyTitle();
    UIView *spacer = [UIView new];
    [spacer.heightAnchor constraintEqualToConstant:0].active = YES;
    [spacer setContentHuggingPriority:1 forAxis:UILayoutConstraintAxisHorizontal];
    [spacer setContentCompressionResistancePriority:1 forAxis:UILayoutConstraintAxisHorizontal];
    UIView *recents = button(@"YourLibraryHeader.recents", @"clock.arrow.circlepath");
    UIView *search = button(@"YourLibraryHeader.search", @"magnifyingglass");
    UIView *plus = button(@"YourLibraryHeader.plus", @"plus");
    self.controls = @{@"recents": recents, @"search": search, @"plus": plus, @"face": avatarBox, @"title": title};

    // Built with what the header knows before its model arrives -- Search alone -- unless `steady`.
    NSArray<NSString *> *initial = steady ? model : @[@"search"];
    for (NSString *name in @[@"recents", @"search", @"plus"]) self.controls[name].hidden = ![initial containsObject:name];
    stack.arrangedSubviews = @[avatarBox, title, spacer, recents, search, plus];

    root.view = page;
    self.window.rootViewController = root;
    [self.window makeKeyAndVisible];

    if (check) {
        [NSTimer scheduledTimerWithTimeInterval:0 repeats:NO block:^(NSTimer *timer) { [self runChecks]; }];
        return YES;
    }
    if ([args containsObject:@"look"]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [self openMenu]; });
        return YES;
    }

    if (!steady) {
        [self render:model];
        [page setNeedsLayout];
        [page layoutIfNeeded];
    }
    return YES;
}

#pragma mark - the checks

- (void)pass {
    [self.page setNeedsLayout];
    [self.page layoutIfNeeded];
    spin(0.2);
}

// The chips as Spotify draws them and the page under them as Spotify lays it out.
- (void)expectChipsShown:(NSString *)moment {
    UIView *header = self.page.header, *filters = [header valueForKey:@"filters"];
    UIScrollView *list = self.page.list;
    CGFloat spotify = spotifyHeaderHeight(self.page);
    if (filters.alpha < 1 || !filters.userInteractionEnabled || filters.accessibilityElementsHidden
        || !near(header.bounds.size.height, spotify) || !near(list.contentInset.top, spotify)) {
        HARNESS_FAIL(@"%@: chips alpha %.2f touches %d hidden from VoiceOver %d, header %.2f, list inset %.2f (expected %.2f)", moment, filters.alpha,
                     filters.userInteractionEnabled, filters.accessibilityElementsHidden, header.bounds.size.height, list.contentInset.top, spotify);
    }
    printf("PASS %s: the chips are Spotify's, the header %.2fpt and the list inset by it\n", moment.UTF8String, spotify);
}

// The chips gone and the page closed up by their band, worked out here from the mock's own frames.
- (void)expectChipsFolded:(NSString *)moment {
    UIView *header = self.page.header, *filters = [header valueForKey:@"filters"], *row = [header valueForKey:@"row"];
    UIScrollView *list = self.page.list;
    CGFloat rowBottom = CGRectGetMaxY(row.frame), band = CGRectGetMaxY(filters.frame) - rowBottom, spotify = spotifyHeaderHeight(self.page);
    if (filters.alpha > 0 || filters.userInteractionEnabled || !filters.accessibilityElementsHidden) {
        HARNESS_FAIL(@"%@: chips alpha %.2f touches %d hidden from VoiceOver %d", moment, filters.alpha, filters.userInteractionEnabled, filters.accessibilityElementsHidden);
    }
    if (!near(header.bounds.size.height, rowBottom) || !near(list.contentInset.top, spotify - band)) {
        HARNESS_FAIL(@"%@: header %.2f (row ends at %.2f), list inset %.2f (expected %.2f)", moment, header.bounds.size.height, rowBottom,
                     list.contentInset.top, spotify - band);
    }
    printf("PASS %s: the chips folded, the header %.2fpt and the list inset %.2f\n", moment.UTF8String, rowBottom, spotify - band);
}

// The header's row in reading order from its leading edge -- the title, the menu button, the controls shown, the
// avatar flush with the trailing edge's 8pt inset -- each starting where the one before it ends, mirrored right to
// left (`rtl`); the menu as tall as the controls; read out by VoiceOver.
- (void)expectMenuButton:(NSString *)moment {
    UIView *header = self.page.header;
    UIButton *menu = menuButtonIn(header);
    if (!menu) HARNESS_FAIL(@"%@: no menu button", moment);
    BOOL rtl = header.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;
    if (rtl != [NSProcessInfo.processInfo.arguments containsObject:@"rtl"]) HARNESS_FAIL(@"%@: the header reads %@", moment, rtl ? @"right to left" : @"left to right");
    NSMutableArray<NSValue *> *row = [NSMutableArray arrayWithObject:[NSValue valueWithCGRect:menu.frame]];
    NSMutableArray<NSString *> *names = [NSMutableArray arrayWithObject:@"menu"];
    for (NSString *name in @[@"recents", @"search", @"plus", @"face"]) {
        UIView *control = self.controls[name];
        if (control.hidden) continue;
        [row addObject:[NSValue valueWithCGRect:SGFrameIn(control, header)]];
        [names addObject:name];
    }
    NSMutableString *read = [NSMutableString string];
    for (NSUInteger i = 0; i < row.count; i++) [read appendFormat:@" %@ %.1f-%.1f", names[i], CGRectGetMinX(row[i].CGRectValue), CGRectGetMaxX(row[i].CGRectValue)];
    for (NSUInteger i = 1; i < row.count; i++) {
        CGRect before = row[i - 1].CGRectValue, next = row[i].CGRectValue;
        CGFloat gap = rtl ? CGRectGetMinX(before) - CGRectGetMaxX(next) : CGRectGetMinX(next) - CGRectGetMaxX(before);
        if (!near(gap, 0)) HARNESS_FAIL(@"%@: %@ does not follow %@ in reading order:%@", moment, names[i], names[i - 1], read);
    }
    CGRect last = row.lastObject.CGRectValue, first = row[1].CGRectValue;
    CGFloat inset = rtl ? CGRectGetMinX(last) : header.bounds.size.width - CGRectGetMaxX(last);
    if (!near(inset, 8)) HARNESS_FAIL(@"%@: the avatar %.1fpt from the trailing edge:%@", moment, inset, read);
    if (!near(menu.frame.size.height, first.size.height) || !near(CGRectGetMidY(menu.frame), CGRectGetMidY(first))) {
        HARNESS_FAIL(@"%@: menu %@, first control %@", moment, NSStringFromCGRect(menu.frame), NSStringFromCGRect(first));
    }
    UILabel *title = titleIn(header);
    BOOL clear = rtl ? CGRectGetMinX(title.frame) >= CGRectGetMaxX(menu.frame) - 0.5 : CGRectGetMaxX(title.frame) <= CGRectGetMinX(menu.frame) + 0.5;
    if (!clear || title.frame.size.width < 1) HARNESS_FAIL(@"%@: title %@, menu %@", moment, NSStringFromCGRect(title.frame), NSStringFromCGRect(menu.frame));
    printf("PASS %s: the row reads title,%s %s\n", moment.UTF8String, read.UTF8String, rtl ? "right to left" : "left to right");
    // A UIButton, which UIKit's accessibility reads as a button opening a menu.
    if (![menu.accessibilityLabel isEqualToString:@"Sort and view"] || !menu.accessibilityHint.length || menu.accessibilityElementsHidden || menu.hidden
        || !menu.showsLargeContentViewer || !menu.largeContentImage || ![menu.largeContentTitle isEqualToString:menu.accessibilityLabel]) {
        HARNESS_FAIL(@"%@: VoiceOver reads \"%@\" (%@), large content %d \"%@\"", moment, menu.accessibilityLabel, menu.accessibilityHint,
                     menu.showsLargeContentViewer, menu.largeContentTitle);
    }
    printf("PASS %s: the menu button %s before the first control, clear of the title, read \"%s\"\n", moment.UTF8String,
           NSStringFromCGRect(menu.frame).UTF8String, menu.accessibilityLabel.UTF8String);
}

// The header restyled: the scrim and Spotify's own small title gone, the large title with Spotify's text at the
// leading edge, and the controls after it with the avatar last, 8pt from the trailing edge.
- (void)expectRedesignedHeader:(NSString *)moment {
    UIView *header = self.page.header;
    UIView *scrim = [header valueForKey:@"gradient"], *spotify = self.controls[@"title"];
    if (scrim.alpha > 0.01 || spotify.alpha > 0.01) HARNESS_FAIL(@"%@: scrim alpha %.2f, Spotify's title alpha %.2f", moment, scrim.alpha, spotify.alpha);
    UILabel *title = titleIn(header);
    if (![title.text isEqualToString:@"Your Library"] || title.font.pointSize <= 21) {
        HARNESS_FAIL(@"%@: the large title \"%@\" at %.1fpt", moment, title.text, title.font.pointSize);
    }
    CGRect face = SGFrameIn(self.controls[@"face"], header);
    CGFloat inset = header.bounds.size.width - CGRectGetMaxX(face);
    if (!near(inset, 8)) HARNESS_FAIL(@"%@: the avatar %.1fpt from the trailing edge", moment, inset);
    for (NSString *name in @[@"recents", @"search", @"plus"]) {
        UIView *control = self.controls[name];
        if (control.hidden) continue;
        CGRect frame = SGFrameIn(control, header);
        if (CGRectGetMaxX(frame) > CGRectGetMinX(face) + 0.5 || CGRectGetMinX(frame) < CGRectGetMaxX(title.frame) - 0.5) {
            HARNESS_FAIL(@"%@: %@ %@ not between the title %@ and the avatar %@", moment, name, NSStringFromCGRect(frame),
                         NSStringFromCGRect(title.frame), NSStringFromCGRect(face));
        }
    }
    printf("PASS %s: the large title at %.0f, the avatar 8pt from the trailing edge\n", moment.UTF8String, CGRectGetMinX(title.frame));
}

- (void)runChecks {
    NSArray<NSString *> *args = NSProcessInfo.processInfo.arguments;
    spin(0.3);
    _TtC28YourLibrary_YourLibraryXImpl15YourLibraryView *page = self.page;
    if (![args containsObject:@"compact"]) {
        if (menuButtonIn(page.header)) HARNESS_FAIL(@"Compact library off, the header has a menu button");
        [self expectRedesignedHeader:page.wrapper ? @"off, the header in 9.2.0's stack" : @"off"];
        [self expectChipsShown:@"off"];
        printf("PASS all off\n");
        exit(0);
    }
    if ([args containsObject:@"nosort"]) {
        [self pass];
        [self expectChipsShown:@"no sort row"];
        expectMenu(page, @"", @"no sort row");
        printf("PASS all nosort\n");
        exit(0);
    }
    if ([args containsObject:@"late"]) {
        [self expectChipsShown:@"before the list loads"];
        expectMenu(page, @"", @"before the list loads");
        // Rows in, on the list's own pass only: no pass of the page's.
        self.items.loaded = YES;
        [self.page.list reloadData];
        [self.page.list layoutIfNeeded];
        spin(0.3);
    }
    [self expectChipsFolded:@"loaded"];
    [self expectMenuButton:@"loaded"];
    expectMenu(page, @"Sort (Recents) | List, Grid*", @"loaded");
    // Spotify states the list's inset again on every pass of its page.
    [self pass];
    [self expectChipsFolded:@"after another page pass"];

    if ([args containsObject:@"noclear"]) [self checkFilterWithoutClearChip];
    if ([args containsObject:@"safearea"]) [self checkSafeAreaChange];

    UICollectionView *list = page.list;
    CGFloat top = -list.adjustedContentInset.top;

    // Sorted on Spotify's own row, which the menu last read as Recents, then the row scrolled away before the menu
    // opens: it names no order rather than the one it read before.
    [[self sortCell].sort sendActionsForControlEvents:UIControlEventTouchUpInside];
    HARNESS_CHECK(self.items.sortTaps == 1);
    [list layoutIfNeeded];
    [list setContentOffset:CGPointMake(0, 900) animated:NO];
    [list layoutIfNeeded];
    if ([self sortCell]) HARNESS_FAIL(@"the sort row still on screen at 900");
    expectMenu(page, @"Sort | List, Grid*", @"sorted on Spotify's row, the row scrolled away");

    // Sort from the menu with the row away: the list scrolls to its top in sight and stays there, and the row's
    // control fires once it is on screen -- not at the pick, while the list is on its way.
    pick(page, @"Sort");
    HARNESS_CHECK(self.items.sortTaps == 1);
    spin(1.0);
    if (self.items.sortTaps != 2 || !near(list.contentOffset.y, top)) {
        HARNESS_FAIL(@"sorted from the menu with the row away: %lu sorts, the list at %.1f (expected 2 at %.1f)",
                     (unsigned long)self.items.sortTaps, list.contentOffset.y, top);
    }
    // Spotify reloads the list in the new order; the list is still at its top after that, the row on screen.
    spin(0.3);
    [list layoutIfNeeded];
    if (!near(list.contentOffset.y, top) || ![self sortCell]) HARNESS_FAIL(@"after the reload the list is at %.1f, the row %@", list.contentOffset.y, [self sortCell] ? @"on screen" : @"away");
    printf("PASS sorted from the menu with the row away: the list came to its top and stayed after the reload (%.1f)\n", list.contentOffset.y);
    expectMenu(page, @"Sort (Alphabetical) | List, Grid*", @"after the list came back");

    // The row on screen a little way down: fired in place, the list left where it is.
    [list setContentOffset:CGPointMake(0, top + 12) animated:NO];
    [list layoutIfNeeded];
    pick(page, @"Sort");
    if (self.items.sortTaps != 3 || !near(list.contentOffset.y, top + 12)) {
        HARNESS_FAIL(@"sorted in place: %lu sorts, the list at %.1f (expected 3 at %.1f)", (unsigned long)self.items.sortTaps, list.contentOffset.y, top + 12);
    }
    [list layoutIfNeeded];
    expectMenu(page, @"Sort (Creator) | List, Grid*", @"sorted in place");

    pick(page, @"List");
    HARNESS_CHECK(self.items.toggleTaps == 1 && !self.items.grid);
    [self pass];
    expectMenu(page, @"Sort (Creator) | List*, Grid", @"list view from the menu");
    pick(page, @"List");
    HARNESS_CHECK(self.items.toggleTaps == 1);
    printf("PASS picking the view already shown fires nothing\n");

    // A filter Spotify has on (one kept from before): the chips stay folded and the menu clears it.
    [list setContentOffset:CGPointMake(0, top) animated:NO];
    [self.chips collectionView:self.chipsView didSelectItemAtIndexPath:[NSIndexPath indexPathForItem:2 inSection:0]];
    [self pass];
    [self expectChipsFolded:@"a filter on"];
    expectMenu(page, @"Sort (Creator) | List*, Grid | Clear all filters", @"a filter on");
    pick(page, kClearLabel);
    HARNESS_CHECK(self.chips.clears == 1 && !self.chips.filter);
    [self pass];
    expectMenu(page, @"Sort (Creator) | List*, Grid", @"the filter cleared");

    // A control the menu fires gone, the list at its top: the chips come back for good.
    self.items.sortRow = NO;
    [list reloadData];
    [list layoutIfNeeded];
    pick(page, @"Sort");
    HARNESS_CHECK(self.items.sortTaps == 3);
    spin(0.1);
    [self.page layoutIfNeeded];
    [self expectChipsShown:@"the sort row gone when fired"];

    [self checkFolder];
    printf("PASS all compact\n");
    exit(0);
}

// The list's sort row while it is on screen.
- (SGRHarnessSortCell *)sortCell {
    for (UICollectionViewCell *cell in self.page.list.visibleCells) {
        if ([cell isKindOfClass:SGRHarnessSortCell.class] && !cell.hidden) return (SGRHarnessSortCell *)cell;
    }
    return nil;
}

// `noclear`: a filter on that the menu has no clear chip for, chosen in the chips with no pass of the page's. The
// chips come back on their own pass alone, and fold again when it is cleared there; chosen with no pass at all, they
// are back by the time the menu opens.
- (void)checkFilterWithoutClearChip {
    _TtC28YourLibrary_YourLibraryXImpl15YourLibraryView *page = self.page;
    [self.chips collectionView:self.chipsView didSelectItemAtIndexPath:[NSIndexPath indexPathForItem:2 inSection:0]];
    spin(0.3);
    [self expectChipsShown:@"a filter on with no clear chip, on the chips' pass"];
    HARNESS_CHECK(near(page.list.contentOffset.y, -kHeaderHeight));

    [self.chips collectionView:self.chipsView didSelectItemAtIndexPath:[NSIndexPath indexPathForItem:0 inSection:0]];
    spin(0.3);
    [self expectChipsFolded:@"the filter cleared in the chips"];

    self.chips.filter = @"Albums";
    [self.chipsView reloadData];
    NSString *menu = describeMenu(menuElements(page));
    [self expectChipsShown:@"the menu opened over a filter with no clear chip"];
    if (![menu isEqualToString:@"Sort (Recents) | List, Grid*"]) HARNESS_FAIL(@"the menu over a filter with no clear chip reads \"%@\"", menu);
    printf("PASS all noclear\n");
    exit(0);
}

// `safearea`: the page's top safe area changing with the chips folded (a rotation or a window resize moves it the same
// way), Spotify's header and its inset for the list changing with it, one page pass each: the list rests the chips' band
// under Spotify's new inset, back again when the safe area is, and the chips coming back after such a change give the
// list Spotify's new inset.
- (void)checkSafeAreaChange {
    UIViewController *root = self.window.rootViewController;
    root.additionalSafeAreaInsets = UIEdgeInsetsMake(20, 0, 0, 0);
    [self pass];
    [self.window layoutIfNeeded];
    UIImage *image = [[[UIGraphicsImageRenderer alloc] initWithSize:self.window.bounds.size] imageWithActions:^(UIGraphicsImageRendererContext *c) {
        HARNESS_CHECK([self.window drawViewHierarchyInRect:self.window.bounds afterScreenUpdates:YES]);
    }];
    NSString *file = [[NSHomeDirectory() stringByAppendingPathComponent:@"Documents"] stringByAppendingPathComponent:
                      @"library-safearea.png"];
    HARNESS_CHECK([UIImagePNGRepresentation(image) writeToFile:file atomically:YES]);
    printf("SHOT %s\n", file.UTF8String);
    [self expectChipsFolded:@"the safe area 20pt taller"];
    root.additionalSafeAreaInsets = UIEdgeInsetsZero;
    [self pass];
    [self expectChipsFolded:@"the safe area back"];
    root.additionalSafeAreaInsets = UIEdgeInsetsMake(20, 0, 0, 0);
    [self pass];
    // The sort row gone when the menu fires it, the list at its top: the chips come back.
    UICollectionView *list = self.page.list;
    [list setContentOffset:CGPointMake(0, -list.adjustedContentInset.top) animated:NO];
    self.items.sortRow = NO;
    [list reloadData];
    [list layoutIfNeeded];
    pick(self.page, @"Sort");
    spin(1.0);
    [self.page layoutIfNeeded];
    UIView *filters = [self.page.header valueForKey:@"filters"];
    CGFloat spotify = spotifyHeaderHeight(self.page);
    if (filters.alpha < 1 || !near(list.contentInset.top, spotify))
        HARNESS_FAIL(@"the chips back at the taller safe area: chips alpha %.2f, list inset %.2f (expected Spotify's %.2f)", filters.alpha,
                     list.contentInset.top, spotify);
    printf("PASS the chips back at the taller safe area: the list inset by Spotify's %.2f\n", spotify);
    printf("PASS all safearea\n");
    exit(0);
}

// A folder keeps its chips and gets no menu, Compact library or not.
- (void)checkFolder {
    UIView *folder = [[_TtC22YourLibrary_FolderImpl10FolderView alloc] initWithFrame:self.window.bounds];
    UIView *header = box(folder, _TtC22YourLibrary_FolderImpl16FolderHeaderView.class, CGRectMake(0, 0, folder.bounds.size.width, 167), nil);
    UIView *back = button(@"YourLibraryFolderHeader.back", @"chevron.left");
    UIView *plus = button(@"YourLibraryFolderHeader.plus", @"plus");
    back.translatesAutoresizingMaskIntoConstraints = plus.translatesAutoresizingMaskIntoConstraints = YES;
    back.frame = CGRectMake(8, 62, 48, 48);
    plus.frame = CGRectMake(folder.bounds.size.width - 56, 62, 48, 48);
    [header addSubview:back];
    [header addSubview:plus];
    UIView *filters = box(header, _TtC21YourLibrary_CommonKit35YourLibraryHeaderContentFiltersView.class, CGRectMake(0, 118, folder.bounds.size.width, 49.33), nil);
    chips(filters, self.chips);
    [self.window addSubview:folder];
    [folder setNeedsLayout];
    [folder layoutIfNeeded];
    if (filters.alpha < 1 || !filters.userInteractionEnabled || menuButtonIn(header)) {
        HARNESS_FAIL(@"the folder's chips alpha %.2f touches %d, menu %@", filters.alpha, filters.userInteractionEnabled, menuButtonIn(header));
    }
    [folder removeFromSuperview];
    printf("PASS a folder keeps its chips and has no menu\n");
}

// `look`: the menu opened by a finger, for a screenshot of it.
- (void)openMenu {
    UIButton *menu = menuButtonIn(self.page.header);
    if (!menu) HARNESS_FAIL(@"no menu button to open");
    CGPoint middle = [menu convertPoint:CGPointMake(CGRectGetMidX(menu.bounds), CGRectGetMidY(menu.bounds)) toView:nil];
    SGHarnessTap(self.window, middle);
    printf("READY menu opened at %s\n", NSStringFromCGPoint(middle).UTF8String);
    fflush(stdout);
}

@end

// Before every %ctor, so the redesign's gate reads on, and Compact library as the launch line has it.
__attribute__((constructor(101))) static void sgr_harnessDefaults(void) {
    NSUserDefaults *store = NSUserDefaults.standardUserDefaults;
    [store setBool:YES forKey:@"spotifyglass.redesign"];
    if ([NSProcessInfo.processInfo.arguments containsObject:@"compact"]) [store setBool:YES forKey:SGRKeyLibraryHideChips];
    else [store removeObjectForKey:SGRKeyLibraryHideChips];
}

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(SGRHarnessDelegate.class));
    }
}
