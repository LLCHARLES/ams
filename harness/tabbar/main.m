// Tab bar harness: TabBar.x and NowPlayingBar.x run for real on a mock of the bottom of Spotify's main
// screen, laid out with the constraints 9.1.78 makes (see the README for the addresses), under Spotify's
// class names, with Spotify's message bar (Offline, Private Session) able to come in under the tab bar.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "../harness-fail.h"
#import "Core/SGViewTree.h"
#import "Core/SGPrefs.h"
#import "Redesigned/Navbar/Navbar.h"
#import "Shared/Navigation/TabIcons.h"

#pragma mark - Spotify's classes, by the names the hooks look for

@interface _TtC23NavigationUI_TabBarImpl10TabBarView : UIView
@end
@implementation _TtC23NavigationUI_TabBarImpl10TabBarView
@end

@interface _TtC23NavigationUI_TabBarImpl17TabBarCompactView : UIView
@end
@implementation _TtC23NavigationUI_TabBarImpl17TabBarCompactView
@end

@interface _TtC23NavigationUI_TabBarImpl21TabBarItemElementView : UIView
@end
@implementation _TtC23NavigationUI_TabBarImpl21TabBarItemElementView
@end

@interface _TtC25CreateMenu_TabBarItemImpl24CreateMenuTabBarItemView : UIView
@end
@implementation _TtC25CreateMenu_TabBarItemImpl24CreateMenuTabBarItemView
@end

@interface _TtC44LimitedExperienceIndicator_MessageBarRuntime29LimitedExperienceIndicatorBar : UIView
@end
@implementation _TtC44LimitedExperienceIndicator_MessageBarRuntime29LimitedExperienceIndicatorBar
@end

@interface _TtC22NowPlaying_BarPageImplP33_CCC0D2EEA6D4725EECD8965E8C38C86D20TouchPassthroughView : UIView
@end
@implementation _TtC22NowPlaying_BarPageImplP33_CCC0D2EEA6D4725EECD8965E8C38C86D20TouchPassthroughView
@end

// A Jam (`jam`): Spotify's strip, a SwiftUI hosting view of Jam_AttachmentsImpl.JamHatElement 44pt high,
// over the card, both in a view that is painted too, and the bar 44pt taller.
@interface _TtGC7SwiftUI14_UIHostingViewV19Jam_AttachmentsImpl13JamHatElement_ : UIView
@end
@implementation _TtGC7SwiftUI14_UIHostingViewV19Jam_AttachmentsImpl13JamHatElement_
@end

// A tab of the mod's own (Navbar.x), for `symbols`.
@interface SGRTabItemView : UIControl
@end
@implementation SGRTabItemView
@end
NSString *const SGHarnessOwnTabTitle = @"Liked Songs";
// An outline symbol, so its selected variant (heart.fill) can be told from it; with `hold`, house, the symbol Apple
// symbols gives Home, so two tabs wear one symbol.
NSString *SGHarnessOwnTabSymbol(void) {
    return [NSProcessInfo.processInfo.arguments containsObject:@"hold"] ? @"house" : @"heart";
}

static BOOL sgJam, sgColorful, sgGlyphs, sgSwiftIcons, sgSearch;
static __weak UIView *sgJamStrip;

// `glyphs`: the tabs' icons are Encore's glyph view, SPTEncoreIconView, made at launch (main) on SGHarnessGlyphView with
// its `icon` ivar as the Spotify version keeps it, drawing a ring for an outline icon and a solid shape for a filled
// one. As in 9.1.78 the ivar is an object: an icon whose view's isActive changes only its colors, Spotify giving the
// selected tab's view the icon's filled variant (-active) in place of the outline one, as the mock tab does on a tap
// (`tapped:`). With `swift` after `glyphs`, as in 9.1.90, the ivar is a reference Objective-C cannot read (no type) to
// an icon carrying both glyphs, which the view keeps selected or not, its isActive picking the filled one. There is
// no SPTEncoreIcon class, so the Tab bar page's icons (TabIcons.m) stay symbols.
@interface SGHarnessEncoreIcon : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic) BOOL square, solid;
@property (nonatomic, strong) SGHarnessEncoreIcon *filled;   // nil on a filled icon
@end
@implementation SGHarnessEncoreIcon
+ (instancetype)outlineNamed:(NSString *)name square:(BOOL)square {
    SGHarnessEncoreIcon *outline = [self new], *filled = [self new];
    outline.name = name;
    filled.name = [name stringByAppendingString:@"-active"];
    outline.square = filled.square = square;
    filled.solid = YES;
    outline.filled = filled;
    return outline;
}
// A filled icon answers with itself.
- (id)active { return self.filled ?: self; }
@end

@interface SGHarnessGlyphView : UIView
@property (nonatomic, strong) SGHarnessEncoreIcon *outline;   // the outline icon the tab was made with
@property (nonatomic, strong) SGHarnessEncoreIcon *held;      // what the `icon` ivar refers to, kept alive here
@property (nonatomic, strong) UIColor *foregroundColor, *activeForegroundColor;
@property (nonatomic) BOOL isActive;
@end
@implementation SGHarnessGlyphView {
    CAShapeLayer *_shape;
}
- (instancetype)initWithIcon:(id)anIcon {
    if (!(self = [super initWithFrame:CGRectZero])) return nil;
    _shape = [CAShapeLayer layer];
    [self.layer addSublayer:_shape];
    [self show:anIcon];
    return self;
}
// Spotify handing the same view another icon. TabBar.x reads the ivar by its name, as it reads Encore's.
- (void)show:(SGHarnessEncoreIcon *)anIcon {
    self.held = anIcon;
    Ivar ivar = class_getInstanceVariable(self.class, "icon");
    *(void **)((uint8_t *)(__bridge void *)self + ivar_getOffset(ivar)) = (__bridge void *)anIcon;
    [self setNeedsLayout];
}
- (void)setIsActive:(BOOL)isActive {
    _isActive = isActive;
    [self setNeedsLayout];
}
- (void)layoutSubviews {
    [super layoutSubviews];
    SGHarnessEncoreIcon *shown = sgSwiftIcons && self.isActive ? self.held.active : self.held;
    UIColor *color = (self.isActive ? self.activeForegroundColor : nil) ?: self.foregroundColor ?: UIColor.whiteColor;
    CGRect box = CGRectInset(self.bounds, 3, 3);
    _shape.frame = self.bounds;
    _shape.path = (shown.square ? [UIBezierPath bezierPathWithRect:box] : [UIBezierPath bezierPathWithOvalInRect:box]).CGPath;
    _shape.fillColor = shown.solid ? color.CGColor : nil;
    _shape.strokeColor = color.CGColor;
    _shape.lineWidth = shown.solid ? 0 : 2;
}
@end

// Spotify's own fade under its bar (9.1.90), which the redesign keeps clear whatever its own fade does (`fade`).
@interface _TtC23NavigationUI_TabBarImpl18TabBarGradientView : UIView
@end
@implementation _TtC23NavigationUI_TabBarImpl18TabBarGradientView
@end

@interface _TtC18NowPlaying_BarImpl27NowPlayingBarViewController : UIViewController
@end
@implementation _TtC18NowPlaying_BarImpl27NowPlayingBarViewController
- (void)loadView {
    self.view = [UIView new];
    UIColor *album = [UIColor colorWithRed:0x18 / 255.0 green:0x14 / 255.0 blue:0x1C / 255.0 alpha:1];
    UIView *host = self.view;
    if (sgJam) {
        host = [[UIView alloc] initWithFrame:self.view.bounds];
        host.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        host.backgroundColor = album;
        [self.view addSubview:host];
    }
    // The card, 386x56 at {8,0} with the album color, the artwork, two lines and the progress line
    // (trees/clean/home/01.txt, SPTNowPlayingBar).
    UIView *card = [UIView new];
    card.accessibilityIdentifier = @"SPTNowPlayingBar";
    card.backgroundColor = album;
    card.layer.cornerRadius = 8;
    card.clipsToBounds = YES;
    card.translatesAutoresizingMaskIntoConstraints = NO;
    [host addSubview:card];
    [NSLayoutConstraint activateConstraints:@[
        [card.leadingAnchor constraintEqualToAnchor:host.leadingAnchor],
        [card.trailingAnchor constraintEqualToAnchor:host.trailingAnchor],
        [card.bottomAnchor constraintEqualToAnchor:host.bottomAnchor],
        sgJam ? [card.heightAnchor constraintEqualToConstant:56] : [card.topAnchor constraintEqualToAnchor:host.topAnchor],
    ]];
    if (sgJam) {
        UIView *strip = [_TtGC7SwiftUI14_UIHostingViewV19Jam_AttachmentsImpl13JamHatElement_ new];
        strip.backgroundColor = [UIColor colorWithRed:0.1 green:0.45 blue:0.3 alpha:1];
        strip.translatesAutoresizingMaskIntoConstraints = NO;
        [host addSubview:strip];
        UILabel *label = [UILabel new];
        label.text = @"Jam by Alex";
        label.font = [UIFont boldSystemFontOfSize:13];
        label.textColor = UIColor.whiteColor;
        label.frame = CGRectMake(16, 12, 200, 20);
        [strip addSubview:label];
        UIButton *more = [UIButton systemButtonWithImage:[UIImage systemImageNamed:@"ellipsis"] target:nil action:nil];
        more.tintColor = UIColor.whiteColor;
        more.translatesAutoresizingMaskIntoConstraints = NO;
        [strip addSubview:more];
        [NSLayoutConstraint activateConstraints:@[
            [strip.leadingAnchor constraintEqualToAnchor:host.leadingAnchor],
            [strip.trailingAnchor constraintEqualToAnchor:host.trailingAnchor],
            [strip.bottomAnchor constraintEqualToAnchor:card.topAnchor],
            [strip.heightAnchor constraintEqualToConstant:44],
            [more.trailingAnchor constraintEqualToAnchor:strip.trailingAnchor constant:-8],
            [more.centerYAnchor constraintEqualToAnchor:strip.centerYAnchor],
        ]];
        sgJamStrip = strip;
    }
    UIView *art = [[UIView alloc] initWithFrame:CGRectMake(8, 8, 40, 40)];
    art.layer.cornerRadius = 4;
    art.clipsToBounds = YES;
    UIImageView *image = [[UIImageView alloc] initWithFrame:art.bounds];
    image.backgroundColor = [UIColor colorWithRed:0.85 green:0.35 blue:0.55 alpha:1];
    [art addSubview:image];
    [card addSubview:art];
    UILabel *title = [UILabel new], *artist = [UILabel new];
    title.text = @"Stay High";
    title.font = [UIFont boldSystemFontOfSize:13];
    title.textColor = UIColor.whiteColor;
    artist.text = @"Juice WRLD";
    artist.font = [UIFont systemFontOfSize:13];
    artist.textColor = [UIColor colorWithWhite:0.7 alpha:1];
    UIStackView *lines = [[UIStackView alloc] initWithArrangedSubviews:@[title, artist]];
    lines.axis = UILayoutConstraintAxisVertical;
    lines.frame = CGRectMake(56, 8, 200, 40);
    [card addSubview:lines];
    UIButton *play = [UIButton systemButtonWithImage:[UIImage systemImageNamed:@"play.fill"] target:nil action:nil];
    play.tintColor = UIColor.whiteColor;
    play.frame = CGRectMake(330, 12, 32, 32);
    play.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [card addSubview:play];
    UIView *progress = [[UIView alloc] initWithFrame:CGRectMake(8, 54, 370, 2)];
    progress.backgroundColor = UIColor.whiteColor;
    [card addSubview:progress];
}
@end

@interface _TtC18NowPlaying_BarImpl36NowPlayingBarContainerViewController : UIViewController
@end
@implementation _TtC18NowPlaying_BarImpl36NowPlayingBarContainerViewController
- (void)viewDidLoad {
    [super viewDidLoad];
    UIViewController *bar = [_TtC18NowPlaying_BarImpl27NowPlayingBarViewController new];
    [self addChildViewController:bar];
    bar.view.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:bar.view];
    [NSLayoutConstraint activateConstraints:@[
        [bar.view.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:8],
        [bar.view.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-8],
        [bar.view.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [bar.view.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];
    [bar didMoveToParentViewController:self];
}
@end

// A page on the tab's stack: a list, inset the way Spotify's pages are, by the safe area it inherits.
@interface SGHarnessPage : UITableViewController
@end
@implementation SGHarnessPage
- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.backgroundColor = UIColor.blackColor;
    self.tableView.rowHeight = 48;
    [self.tableView registerClass:UITableViewCell.class forCellReuseIdentifier:@"row"];
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return 30; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"row" forIndexPath:path];
    cell.backgroundColor = path.row == 29 ? [UIColor colorWithRed:0.1 green:0.3 blue:0.6 alpha:1] : UIColor.blackColor;
    // `fade`: rows in color, so the fade under the bars shows on them.
    if (sgColorful) cell.backgroundColor = [UIColor colorWithHue:fmod(path.row * 0.11, 1) saturation:0.6 brightness:0.75 alpha:1];
    cell.textLabel.textColor = UIColor.whiteColor;
    cell.textLabel.text = path.row == 29 ? @"Last row of the list" : [NSString stringWithFormat:@"Row %ld", (long)path.row + 1];
    return cell;
}
@end

// NavigationUI_TabBarImpl.TabBarContainerImpl in a compact width, as its viewDidLoad (0x1008409a8) and
// its size class pass (0x106fabb7c) lay it out: a guide from 49 pt above the safe area's bottom to the
// view's bottom, a stack as tall as the guide on the view's bottom, the tab bar as tall as the stack.
// The page gets 49 pt more safe area on top of what the container has (0x10707bde4).
@interface _TtC23NavigationUI_TabBarImpl19TabBarContainerImpl : UIViewController
@property (nonatomic, strong) UILayoutGuide *compactGuide;
@property (nonatomic, strong) UIView *bar;
@end
@implementation _TtC23NavigationUI_TabBarImpl19TabBarContainerImpl
- (UILayoutGuide *)compactTabBarHeightLayoutGuide { return self.compactGuide; }
- (UIView *)tabBarView { return self.bar; }
- (void)setSelectedViewController:(UIViewController *)controller {}

// A tap on a mock item does what Spotify's does to the bar: its label goes white and the others gray.
+ (void)tapped:(UITapGestureRecognizer *)tap {
    for (UIView *item in tap.view.superview.subviews) {
        for (UIView *sub in item.subviews) {
            if ([sub isKindOfClass:UILabel.class]) ((UILabel *)sub).textColor = item == tap.view ? UIColor.whiteColor : [UIColor colorWithWhite:0xB3 / 255.0 alpha:1];
            if (![sub isKindOfClass:SGHarnessGlyphView.class]) continue;
            SGHarnessGlyphView *glyph = (SGHarnessGlyphView *)sub;
            if (!sgSwiftIcons) [glyph show:item == tap.view ? glyph.outline.active : glyph.outline];
            glyph.isActive = item == tap.view;
        }
    }
    for (UIView *v = tap.view; v; v = v.superview) [v setNeedsLayout];
    // `search`: Spotify tells its container of the tab picked, which brings the minimized bar back (TabBar.x's hook).
    if (!sgSearch) return;
    for (UIResponder *r = tap.view; r; r = r.nextResponder) {
        if ([r isKindOfClass:self]) [(_TtC23NavigationUI_TabBarImpl19TabBarContainerImpl *)r setSelectedViewController:nil];
    }
}

static UIView *tab(Class cls, NSString *title, UIView *icon, BOOL active) {
    UIView *item = [cls new];
    [item addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:_TtC23NavigationUI_TabBarImpl19TabBarContainerImpl.class action:@selector(tapped:)]];
    icon.frame = CGRectMake(0, 5.67, 24, 24);
    icon.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
    UILabel *label = [UILabel new];
    label.text = title;
    label.font = [UIFont systemFontOfSize:10];
    label.textColor = active ? UIColor.whiteColor : [UIColor colorWithWhite:0xB3 / 255.0 alpha:1];
    label.textAlignment = NSTextAlignmentCenter;
    label.frame = CGRectMake(0, 35, 100, 14);
    label.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [item addSubview:icon];
    [item addSubview:label];
    return item;
}

static UIView *item(Class cls, NSString *title, NSString *symbol, BOOL active) {
    UIView *icon;
    if (sgGlyphs) {
        SGHarnessEncoreIcon *outline = [SGHarnessEncoreIcon outlineNamed:symbol square:NO];
        SGHarnessGlyphView *glyph = [[NSClassFromString(@"SPTEncoreIconView") alloc] initWithIcon:active && !sgSwiftIcons ? outline.active : outline];
        glyph.outline = outline;
        glyph.isActive = active;
        icon = glyph;
    } else {
        UIImageView *image = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:symbol]];
        image.tintColor = UIColor.whiteColor;
        image.contentMode = UIViewContentModeScaleAspectFit;
        icon = image;
    }
    return tab(cls, title, icon, active);
}

- (void)viewDidLoad {
    [super viewDidLoad];
    UIView *view = self.view;
    self.compactGuide = [UILayoutGuide new];
    [view addLayoutGuide:self.compactGuide];

    SGHarnessPage *page = [SGHarnessPage new];
    [self addChildViewController:page];
    page.view.translatesAutoresizingMaskIntoConstraints = NO;
    [view addSubview:page.view];
    [page didMoveToParentViewController:self];
    page.additionalSafeAreaInsets = UIEdgeInsetsMake(0, 0, 49, 0);

    // `fade`: Spotify's own fade over the page's foot, drawn black here so it would show if it came back.
    if (sgColorful) {
        UIView *spotifyFade = [_TtC23NavigationUI_TabBarImpl18TabBarGradientView new];
        spotifyFade.translatesAutoresizingMaskIntoConstraints = NO;
        spotifyFade.backgroundColor = UIColor.blackColor;
        spotifyFade.userInteractionEnabled = NO;
        [view addSubview:spotifyFade];
        [NSLayoutConstraint activateConstraints:@[
            [spotifyFade.leadingAnchor constraintEqualToAnchor:view.leadingAnchor],
            [spotifyFade.trailingAnchor constraintEqualToAnchor:view.trailingAnchor],
            [spotifyFade.bottomAnchor constraintEqualToAnchor:view.bottomAnchor],
            [spotifyFade.heightAnchor constraintEqualToConstant:219],
        ]];
    }

    UIView *stack = [UIView new];
    stack.accessibilityIdentifier = @"TabBarContainer.stackView";
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [view addSubview:stack];
    self.bar = [_TtC23NavigationUI_TabBarImpl10TabBarView new];
    self.bar.accessibilityIdentifier = @"elements-tabs-view-identifier";
    self.bar.translatesAutoresizingMaskIntoConstraints = NO;
    [stack addSubview:self.bar];
    UIView *compact = [_TtC23NavigationUI_TabBarImpl17TabBarCompactView new];
    compact.translatesAutoresizingMaskIntoConstraints = NO;
    [self.bar addSubview:compact];
    // `five` adds a fifth tab, `long` gives two tabs long names, as tabs of the user's own can have.
    NSArray<NSString *> *args = NSProcessInfo.processInfo.arguments;
    BOOL longNames = [args containsObject:@"long"];
    BOOL regular = [args containsObject:@"regular"];
    NSMutableArray<UIView *> *tabs = [NSMutableArray arrayWithArray:@[
        item(_TtC23NavigationUI_TabBarImpl21TabBarItemElementView.class, @"Home", @"house.fill", YES),
        item(_TtC23NavigationUI_TabBarImpl21TabBarItemElementView.class, @"Search", @"magnifyingglass", NO),
        item(_TtC23NavigationUI_TabBarImpl21TabBarItemElementView.class, longNames ? @"Your Library and Downloads" : @"Your Library", @"books.vertical", NO),
        item(_TtC25CreateMenu_TabBarItemImpl24CreateMenuTabBarItemView.class, @"Create", @"plus", NO),
    ]];
    if ([args containsObject:@"five"]) {
        [tabs addObject:item(_TtC23NavigationUI_TabBarImpl21TabBarItemElementView.class, longNames ? @"Discover Weekly" : @"Liked Songs", @"heart", NO)];
    }
    // `search` (search.m): Search the last of five tabs, as issue #34 keeps it, or with `middle` the third; with
    // `nosearch` hidden, with `own` hidden and a tab of the mod's own of the same name after it.
    if (sgSearch) {
        UIView *search = tabs[1];
        [tabs removeObjectAtIndex:1];
        [tabs addObject:item(_TtC23NavigationUI_TabBarImpl21TabBarItemElementView.class, @"Liked Songs", @"heart", NO)];
        [tabs insertObject:search atIndex:[args containsObject:@"middle"] ? 2 : tabs.count];
        search.hidden = [args containsObject:@"nosearch"] || [args containsObject:@"own"];
        if ([args containsObject:@"own"]) {
            [tabs addObject:tab(SGRTabItemView.class, @"Search", SGTabIconView(@"magnifyingglass", YES, [UIColor colorWithWhite:0xB3 / 255.0 alpha:1]), NO)];
        }
    }
    // `symbols`: a tab of the mod's own after Spotify's, under the class name Navbar.x gives one, with the SF Symbol
    // picked for it drawn as Navbar.x draws it (SGTabIconView).
    if (args.count > 1 && [args[1] isEqualToString:@"symbols"]) {
        [tabs addObject:tab(SGRTabItemView.class, SGHarnessOwnTabTitle, SGTabIconView(SGHarnessOwnTabSymbol(), YES, [UIColor colorWithWhite:0xB3 / 255.0 alpha:1]), NO)];
    }
    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:tabs];
    row.distribution = UIStackViewDistributionFillEqually;
    row.accessibilityIdentifier = @"tabs-container-view-identifier";
    row.translatesAutoresizingMaskIntoConstraints = NO;
    [compact addSubview:row];

    [NSLayoutConstraint activateConstraints:@[
        [page.view.leadingAnchor constraintEqualToAnchor:view.leadingAnchor],
        [page.view.trailingAnchor constraintEqualToAnchor:view.trailingAnchor],
        [page.view.topAnchor constraintEqualToAnchor:view.topAnchor],
        [page.view.bottomAnchor constraintEqualToAnchor:view.bottomAnchor],
        [self.compactGuide.topAnchor constraintEqualToAnchor:view.safeAreaLayoutGuide.bottomAnchor constant:-49],
        [self.compactGuide.bottomAnchor constraintEqualToAnchor:view.bottomAnchor],
        // `regular`: Spotify's regular width bar, 8 pt in and 648 of the container's 1016 pt, leaving the rest to the
        // now playing capsule (9.2.0, iPad Pro 13-inch), and 16 pt above the container's foot (iPad Pro 11-inch).
        [stack.leadingAnchor constraintEqualToAnchor:view.leadingAnchor constant:regular ? 8 : 0],
        regular ? [stack.widthAnchor constraintEqualToAnchor:view.widthAnchor multiplier:648.0 / 1016]
                : [stack.trailingAnchor constraintEqualToAnchor:view.trailingAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:view.bottomAnchor constant:regular ? -16 : 0],
        [stack.heightAnchor constraintEqualToAnchor:self.compactGuide.heightAnchor],
        [self.bar.leadingAnchor constraintEqualToAnchor:stack.leadingAnchor],
        [self.bar.trailingAnchor constraintEqualToAnchor:stack.trailingAnchor],
        [self.bar.bottomAnchor constraintEqualToAnchor:stack.bottomAnchor],
        [self.bar.heightAnchor constraintEqualToAnchor:stack.heightAnchor],
        [compact.leadingAnchor constraintEqualToAnchor:self.bar.leadingAnchor],
        [compact.trailingAnchor constraintEqualToAnchor:self.bar.trailingAnchor],
        [compact.topAnchor constraintEqualToAnchor:self.bar.topAnchor],
        [compact.bottomAnchor constraintEqualToAnchor:self.bar.bottomAnchor],
        [row.leadingAnchor constraintEqualToAnchor:compact.leadingAnchor],
        [row.trailingAnchor constraintEqualToAnchor:compact.trailingAnchor],
        [row.topAnchor constraintEqualToAnchor:compact.topAnchor],
        [row.heightAnchor constraintEqualToConstant:49],
    ]];
}
@end

#pragma mark - the chrome

// ClientChrome_ChromeContainerKit.ClientChromeViewController in a compact width: the primary content
// (the tab bar container) above the bottom attachment, which is Spotify's message bar, and the
// floating chrome (the now playing bar's page) standing on MainUIContainer's bottom anchor, the top of
// the tab bar container's compact height guide (0x100ae0178).
@interface SGHarnessChrome : UIViewController
@property (nonatomic, strong) _TtC23NavigationUI_TabBarImpl19TabBarContainerImpl *tabs;
@property (nonatomic, strong) UIView *banner;
@property (nonatomic, strong) NSLayoutConstraint *bannerHeight;
@property (nonatomic, strong) UIView *npb;
@property (nonatomic, strong) NSLayoutConstraint *npbHeight;
@end

@implementation SGHarnessChrome

- (void)viewDidLoad {
    [super viewDidLoad];
    UIView *view = self.view;
    view.backgroundColor = UIColor.blackColor;
    // `regular`: a regular width, as on an iPad; `rtl`: right to left.
    NSArray<NSString *> *args = NSProcessInfo.processInfo.arguments;
    if ([args containsObject:@"regular"]) self.traitOverrides.horizontalSizeClass = UIUserInterfaceSizeClassRegular;
    if ([args containsObject:@"rtl"]) self.traitOverrides.layoutDirection = UITraitEnvironmentLayoutDirectionRightToLeft;

    self.tabs = [_TtC23NavigationUI_TabBarImpl19TabBarContainerImpl new];
    [self addChildViewController:self.tabs];
    UIView *primary = self.tabs.view;
    primary.translatesAutoresizingMaskIntoConstraints = NO;
    [view addSubview:primary];
    [self.tabs didMoveToParentViewController:self];

    // LimitedExperienceIndicatorBar: its height is its message plus the safe area it pads its label by
    // (barHeightConstraint, backgroundContainerBottomPaddingConstraint, lastSafeAreaBottomInset).
    self.banner = [_TtC44LimitedExperienceIndicator_MessageBarRuntime29LimitedExperienceIndicatorBar new];
    self.banner.accessibilityIdentifier = @"LimitedExperienceIndicatorBar";
    self.banner.backgroundColor = UIColor.blackColor;
    self.banner.clipsToBounds = YES;
    self.banner.translatesAutoresizingMaskIntoConstraints = NO;
    [view addSubview:self.banner];
    UILabel *message = [UILabel new];
    message.text = @"Private Session";
    message.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    message.textColor = UIColor.whiteColor;
    message.translatesAutoresizingMaskIntoConstraints = NO;
    [self.banner addSubview:message];
    self.bannerHeight = [self.banner.heightAnchor constraintEqualToConstant:0];

    UIView *npb = [_TtC22NowPlaying_BarPageImplP33_CCC0D2EEA6D4725EECD8965E8C38C86D20TouchPassthroughView new];
    npb.translatesAutoresizingMaskIntoConstraints = NO;
    [view addSubview:npb];
    self.npb = npb;
    UIViewController *content = [_TtC18NowPlaying_BarImpl36NowPlayingBarContainerViewController new];
    [self addChildViewController:content];
    content.view.translatesAutoresizingMaskIntoConstraints = NO;
    [npb addSubview:content.view];
    [content didMoveToParentViewController:self];

    [NSLayoutConstraint activateConstraints:@[
        [primary.leadingAnchor constraintEqualToAnchor:view.leadingAnchor],
        [primary.trailingAnchor constraintEqualToAnchor:view.trailingAnchor],
        [primary.topAnchor constraintEqualToAnchor:view.topAnchor],
        [primary.bottomAnchor constraintEqualToAnchor:self.banner.topAnchor],
        [self.banner.leadingAnchor constraintEqualToAnchor:view.leadingAnchor],
        [self.banner.trailingAnchor constraintEqualToAnchor:view.trailingAnchor],
        [self.banner.bottomAnchor constraintEqualToAnchor:view.bottomAnchor],
        self.bannerHeight,
        [message.centerXAnchor constraintEqualToAnchor:self.banner.centerXAnchor],
        [message.bottomAnchor constraintEqualToAnchor:self.banner.safeAreaLayoutGuide.bottomAnchor constant:-4],
        [npb.leadingAnchor constraintEqualToAnchor:view.leadingAnchor],
        [npb.trailingAnchor constraintEqualToAnchor:view.trailingAnchor],
        [npb.bottomAnchor constraintEqualToAnchor:self.tabs.compactTabBarHeightLayoutGuide.topAnchor],
        self.npbHeight = [npb.heightAnchor constraintEqualToConstant:sgJam ? 108 : 64],
        // CompactNowPlayingViewController: the content 8 pt above its own bottom (0x105345190).
        [content.view.leadingAnchor constraintEqualToAnchor:npb.leadingAnchor],
        [content.view.trailingAnchor constraintEqualToAnchor:npb.trailingAnchor],
        [content.view.topAnchor constraintEqualToAnchor:npb.topAnchor],
        [content.view.bottomAnchor constraintEqualToAnchor:npb.bottomAnchor constant:-8],
    ]];

    // The now playing bar's share of the pages' inset, which Spotify adds on its own path; here a
    // stand-in on the page, so the list's end shows where Spotify thinks the bars begin.
    UIViewController *page = self.tabs.childViewControllers.firstObject;
    UIEdgeInsets inset = page.additionalSafeAreaInsets;
    inset.bottom += 64;
    page.additionalSafeAreaInsets = inset;
}

- (CGFloat)bannerTarget {
    return 22 + self.view.safeAreaInsets.bottom;
}

- (void)setBanner:(BOOL)shown animated:(BOOL)animated {
    self.bannerHeight.constant = shown ? [self bannerTarget] : 0;
    if (!animated) {
        [self.view layoutIfNeeded];
        return;
    }
    [UIView animateWithDuration:0.35 animations:^{ [self.view layoutIfNeeded]; }];
}

@end

#pragma mark - what the harness measures

extern CGRect SGRNowPlayingCardFrameIn(UIView *host, CGFloat *radius);
extern void SGRSetTabBarMinimized(BOOL minimized, BOOL animated);
extern BOOL SGRTabBarMinimized(void);
extern CGRect SGRTabBarInlineSlot(UIView *host, CGFloat height);
// touch.m: a finger's touches, through UIKit's own recognizers.
extern void SGHarnessTap(UIWindow *window, CGPoint point);
extern void SGHarnessDrag(UIWindow *window, CGPoint from, CGPoint to, NSTimeInterval seconds);

static UIView *platterIn(UIView *root) {
    // UIKit._UITabBarItemPlatterView on iOS 27; BarTransition.x looks for the same suffix.
    if ([NSStringFromClass(root.class) hasSuffix:@"PlatterView"]) return root;
    for (UIView *sub in root.subviews) {
        UIView *found = platterIn(sub);
        if (found) return found;
    }
    return nil;
}

static UITabBar *systemBarIn(UIView *root) {
    if ([root isKindOfClass:UITabBar.class]) return (UITabBar *)root;
    for (UIView *sub in root.subviews) {
        UITabBar *found = systemBarIn(sub);
        if (found) return found;
    }
    return nil;
}

static NSArray<UITabBar *> *systemBarsIn(UIView *root) {
    NSMutableArray<UITabBar *> *bars = [NSMutableArray array];
    if ([root isKindOfClass:UITabBar.class]) [bars addObject:(UITabBar *)root];
    else for (UIView *sub in root.subviews) [bars addObjectsFromArray:systemBarsIn(sub)];
    return bars;
}

extern __weak UIView *sgHarnessLitTab;

// The item of the stock row named `title`.
static UIView *stockItem(SGHarnessChrome *chrome, NSString *title) {
    for (UIView *item in SGRowIn(chrome.tabs.bar).arrangedSubviews) {
        for (UIView *sub in item.subviews) {
            if ([sub isKindOfClass:UILabel.class] && [((UILabel *)sub).text isEqualToString:title]) return item;
        }
    }
    return nil;
}

// A tab picked on whichever system bar shows it, the calls a finger ends in.
static void pick(SGHarnessChrome *chrome, NSString *title) {
    for (UITabBar *bar in systemBarsIn(chrome.tabs.bar)) {
        for (UITabBarItem *item in bar.items) {
            if (![item.title isEqualToString:title]) continue;
            bar.selectedItem = item;
            [bar.delegate tabBar:bar didSelectItem:item];
        }
    }
}

static void reportSelection(SGHarnessChrome *chrome, NSString *moment) {
    NSMutableString *out = [NSMutableString stringWithFormat:@"[harness] %@ selection", moment];
    for (UITabBar *bar in systemBarsIn(chrome.tabs.bar)) {
        [out appendFormat:@" | bar%@ %@: %@", bar.hidden ? @" (hidden)" : @"", [bar.items valueForKey:@"title"], bar.selectedItem.title ?: @"none"];
    }
    NSLog(@"%@", [out stringByReplacingOccurrencesOfString:@"\n" withString:@" "]);
}

static void report(SGHarnessChrome *chrome, NSString *moment) {
    UIWindow *window = chrome.view.window;
    UIView *stock = chrome.tabs.bar;
    UITabBar *system = systemBarIn(stock);
    UIView *platter = platterIn(system);
    CGRect stockFrame = [stock convertRect:stock.bounds toView:window];
    CGRect systemFrame = system ? [system convertRect:system.bounds toView:window] : CGRectNull;
    CGRect platterFrame = platter ? [platter convertRect:platter.bounds toView:window] : CGRectNull;
    CGRect card = SGRNowPlayingCardFrameIn(window, NULL);
    CGRect banner = [chrome.banner convertRect:chrome.banner.bounds toView:window];
    UITableView *list = (UITableView *)chrome.tabs.childViewControllers.firstObject.view;
    CGFloat listEnd = CGRectGetMaxY([list convertRect:list.bounds toView:window]) - list.adjustedContentInset.bottom;
    NSLog(@"[harness] %@ screen %.0fx%.0f safe-bottom %.0f | banner %@ | stock bar %@ | system bar %@ | platter %@ | card %@ | "
          @"gap card-to-platter %.1f | container extra inset %.0f | list ends at %.0f (card top %.0f)",
          moment, window.bounds.size.width, window.bounds.size.height, window.safeAreaInsets.bottom,
          NSStringFromCGRect(banner), NSStringFromCGRect(stockFrame), NSStringFromCGRect(systemFrame), NSStringFromCGRect(platterFrame),
          NSStringFromCGRect(card), CGRectGetMinY(platterFrame) - CGRectGetMaxY(card), chrome.tabs.additionalSafeAreaInsets.bottom,
          listEnd, CGRectGetMinY(card));
    // The glass panes of the now playing bar, the card's and in a Jam the strip's, and the strip itself.
    UIView *container = chrome.npb.subviews.firstObject;
    for (UIView *sub in container.subviews) {
        if (![sub isKindOfClass:UIVisualEffectView.class]) continue;
        NSLog(@"[harness] %@ bar pane %@ %@", moment, NSStringFromCGRect([sub convertRect:sub.bounds toView:window]),
              ((UIVisualEffectView *)sub).effect ? @"shown" : @"no effect");
    }
    UIView *strip = sgJamStrip;
    if (strip.window) NSLog(@"[harness] %@ strip %@", moment, NSStringFromCGRect([strip convertRect:strip.bounds toView:window]));
    // Every glass platter on the bar: with `split`, the main bar's and the split bar's.
    NSMutableString *platters = [NSMutableString stringWithFormat:@"[harness] %@ platters", moment];
    NSMutableArray<UIView *> *found = [NSMutableArray array];
    NSMutableArray<UIView *> *walk = [NSMutableArray arrayWithObject:stock];
    while (walk.count) {
        UIView *v = walk.firstObject;
        [walk removeObjectAtIndex:0];
        if ([NSStringFromClass(v.class) hasSuffix:@"PlatterView"]) [found addObject:v];
        else [walk addObjectsFromArray:v.subviews];
    }
    for (UIView *v in found) [platters appendFormat:@" %@ %@", NSStringFromClass(v.class), NSStringFromCGRect([v convertRect:v.bounds toView:window])];
    NSLog(@"%@", platters);
    // What a finger at the card's middle lands on, and the fade under the bars.
    if (!CGRectIsNull(card)) {
        UIView *hit = [window hitTest:CGPointMake(CGRectGetMidX(card), CGRectGetMidY(card)) withEvent:nil];
        NSLog(@"[harness] %@ touch at the card's middle lands on %@, in the now playing bar: %d", moment, NSStringFromClass(hit.class), [hit isDescendantOfView:chrome.npb]);
    }
    for (UIView *v in stock.subviews) {
        if ([NSStringFromClass(v.class) isEqualToString:@"SGRBarFade"]) NSLog(@"[harness] %@ fade %@", moment, NSStringFromCGRect([v convertRect:v.bounds toView:window]));
    }
}

#pragma mark - the fade under the bars

static NSArray<UIView *> *viewsNamed(UIView *root, NSString *name) {
    NSMutableArray<UIView *> *found = [NSMutableArray array];
    SGForEachView(root, ^(UIView *v) {
        if ([NSStringFromClass(v.class) isEqualToString:name]) [found addObject:v];
    });
    return found;
}

// What the Tab bar page does when its switch flips (NavbarSettings.m): the setting stored, the bar laid out again.
static void setFade(SGHarnessChrome *chrome, BOOL on) {
    SGSetEnabled(SGRKeyNavbarFade, on);
    [chrome.tabs.bar setNeedsLayout];
    [chrome.tabs.bar layoutIfNeeded];
}

// The fade there once, behind the glass, from SGRBarFadeAbovePt over the glass bar's top to the tab bar container's
// foot (with `regular` 16 pt under the bar's) and across its whole width (with `regular` wider than Spotify's bar),
// taking no touches; or no fade of the
// redesign's anywhere in the window. Either way Spotify's own stays clear, and a finger in the fade's band over the
// now playing card lands on the page.
static void expectFade(SGHarnessChrome *chrome, BOOL on, NSString *moment) {
    UIWindow *window = chrome.view.window;
    UIView *stock = chrome.tabs.bar;
    NSArray<UIView *> *fades = viewsNamed(window, @"SGRBarFade");
    UIView *host = viewsNamed(stock, @"SGRTabBarHost").firstObject;
    CGRect glass = [host convertRect:host.bounds toView:window];
    CGRect across = [chrome.tabs.view convertRect:chrome.tabs.view.bounds toView:window];
    if (on) {
        UIView *fade = fades.firstObject;
        CGRect frame = [fade convertRect:fade.bounds toView:window];
        if (fades.count != 1 || fade.superview != stock || stock.subviews.firstObject != fade || fade.userInteractionEnabled
            || fabs(CGRectGetMinY(frame) - (CGRectGetMinY(glass) - SGRBarFadeAbovePt)) > 0.5 || fabs(CGRectGetMaxY(frame) - MAX(CGRectGetMaxY(glass), CGRectGetMaxY(across))) > 0.5
            || fabs(CGRectGetMinX(frame) - CGRectGetMinX(across)) > 0.5 || fabs(CGRectGetMaxX(frame) - CGRectGetMaxX(across)) > 0.5) {
            HARNESS_FAIL(@"%@: %lu fades, the first %@ under %@ (first subview %d, touches %d), glass %@, container %@", moment,
                         (unsigned long)fades.count, NSStringFromCGRect(frame), NSStringFromClass(fade.superview.class),
                         stock.subviews.firstObject == fade, fade.userInteractionEnabled, NSStringFromCGRect(glass),
                         NSStringFromCGRect(across));
        }
    } else if (fades.count) {
        HARNESS_FAIL(@"%@: %lu fades left with the fade off", moment, (unsigned long)fades.count);
    }
    for (UIView *spotify in viewsNamed(window, @"_TtC23NavigationUI_TabBarImpl18TabBarGradientView")) {
        if (spotify.alpha > 0) HARNESS_FAIL(@"%@: Spotify's fade is back (alpha %.2f)", moment, spotify.alpha);
    }
    CGPoint above = CGPointMake(CGRectGetMidX(glass), CGRectGetMinY(glass) - SGRBarFadeAbovePt + 10);
    UIView *hit = [window hitTest:above withEvent:nil];
    UIView *list = chrome.tabs.childViewControllers.firstObject.view;
    if (!CGRectIsEmpty(glass) && !stock.hidden && !chrome.presentedViewController && ![hit isDescendantOfView:list]) {
        HARNESS_FAIL(@"%@: a finger at %@ lands on %@, not the page", moment, NSStringFromCGPoint(above), NSStringFromClass(hit.class));
    }
    printf("PASS %s: %s\n", moment.UTF8String, on ? "one fade behind the glass, no touches taken" : "no fade");
    fflush(stdout);
}

// `fade toggle`: the switch flipped live, over and over, minimized and with the bar hidden; nothing kept from a
// fade switched off. With `split` the bar has a split tab; with `regular` it is Spotify's regular width bar, which
// never minimizes, so the minimized steps are left out.
static void runFadeChecks(SGHarnessChrome *chrome) {
    expectFade(chrome, YES, @"on");
    __weak UIView *first = viewsNamed(chrome.tabs.bar, @"SGRBarFade").firstObject;
    @autoreleasepool { setFade(chrome, NO); }
    [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
    expectFade(chrome, NO, @"switched off");
    if (first) HARNESS_FAIL(@"the fade switched off is still alive");
    setFade(chrome, YES);
    expectFade(chrome, YES, @"switched on again");

    NSPointerArray *made = [NSPointerArray weakObjectsPointerArray];
    for (NSUInteger i = 0; i < 20; i++) {
        @autoreleasepool {
            [made addPointer:(__bridge void *)viewsNamed(chrome.tabs.bar, @"SGRBarFade").firstObject];
            setFade(chrome, NO);
            setFade(chrome, YES);
        }
    }
    [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
    expectFade(chrome, YES, @"after 20 turns");
    NSUInteger alive = 0;
    for (NSUInteger i = 0; i < made.count; i++) alive += [made pointerAtIndex:i] != NULL;
    if (alive) HARNESS_FAIL(@"%lu fades switched off are still alive", (unsigned long)alive);
    printf("PASS no fade kept after 20 turns\n");

    if (chrome.traitCollection.horizontalSizeClass == UIUserInterfaceSizeClassCompact) {
        SGRSetTabBarMinimized(YES, NO);
        [chrome.view layoutIfNeeded];
        if (!SGRTabBarMinimized()) HARNESS_FAIL(@"the bar did not minimize");
        expectFade(chrome, YES, @"minimized");
        setFade(chrome, NO);
        expectFade(chrome, NO, @"minimized, switched off");
        setFade(chrome, YES);
        expectFade(chrome, YES, @"minimized, switched on");
        SGRSetTabBarMinimized(NO, NO);
        [chrome.view layoutIfNeeded];
    }

    // A page that hides the bar: the switch still takes the fade away and brings it back.
    chrome.tabs.bar.hidden = YES;
    setFade(chrome, NO);
    expectFade(chrome, NO, @"bar hidden, switched off");
    setFade(chrome, YES);
    chrome.tabs.bar.hidden = NO;
    [chrome.tabs.bar layoutIfNeeded];
    expectFade(chrome, YES, @"bar shown again");
    printf("PASS all fade\n");
    fflush(stdout);
    exit(0);
}

// Every title the glass bars show, and whether UIKit cut it short: the width its text needs at the
// smallest size the label may shrink to, against the width it was given. With `strict` a cut title fails the run.
static void reportNames(SGHarnessChrome *chrome, NSString *moment) {
    NSMutableString *out = [NSMutableString stringWithFormat:@"[harness] %@ names", moment];
    NSUInteger cut = 0;
    for (UITabBar *bar in systemBarsIn(chrome.tabs.bar)) {
        if (bar.hidden) continue;
        [out appendFormat:@" | bar %.0f wide:", bar.bounds.size.width];
        NSMutableArray<UIView *> *walk = [NSMutableArray arrayWithObject:bar];
        while (walk.count) {
            UIView *v = walk.firstObject;
            [walk removeObjectAtIndex:0];
            [walk addObjectsFromArray:v.subviews];
            if (![v isKindOfClass:UILabel.class] || !v.window) continue;
            BOOL shown = YES;
            for (UIView *up = v; up && up != bar; up = up.superview) shown &= !up.hidden && up.alpha > 0.01;
            if (!shown) continue;
            UILabel *label = (UILabel *)v;
            if (!label.text.length) continue;
            CGFloat need = [label.text sizeWithAttributes:@{NSFontAttributeName: label.font}].width;
            CGFloat scale = label.adjustsFontSizeToFitWidth && label.minimumScaleFactor > 0 ? label.minimumScaleFactor : 1;
            BOOL isCut = need * scale > label.bounds.size.width + 1;
            cut += isCut;
            if ([NSProcessInfo.processInfo.arguments containsObject:@"tree"]) {
                NSMutableString *chain = [NSMutableString string];
                for (UIView *up = label; up && up != bar; up = up.superview) [chain appendFormat:@" < %@%@", NSStringFromClass(up.class), NSStringFromCGRect(up.frame)];
                NSLog(@"[harness] %@ label%@", moment, chain);
            }
            [out appendFormat:@" \"%@\" %.0f/%.0f@%.1fpt%@", label.text, label.bounds.size.width, ceil(need), label.font.pointSize, isCut ? @" CUT" : @""];
        }
    }
    [out appendFormat:@" | %lu cut", (unsigned long)cut];
    NSLog(@"%@", out);
    if (cut && [NSProcessInfo.processInfo.arguments containsObject:@"strict"]) HARNESS_FAIL(@"%@", out);
}

// Whether the bar and the card agree: minimized, the platter is the 62 pt circle 21 pt in and the card is in
// its row; expanded, the platter is the whole bar's and the card stands above it. With what the screen shows
// (the presentation layers) and how many animations are still on the bar, its items and the card.
static void check(SGHarnessChrome *chrome, NSString *moment) {
    UIWindow *window = chrome.view.window;
    UITabBar *bar = systemBarIn(chrome.tabs.bar);
    UIView *platter = platterIn(bar);
    CGRect circle = [platter convertRect:platter.bounds toView:window];
    CGRect card = SGRNowPlayingCardFrameIn(window, NULL);
    BOOL minimized = SGRTabBarMinimized();
    BOOL leads = fabs(circle.size.width - 62) < 1 && fabs(circle.origin.x - 21) < 1;
    BOOL docked = CGRectGetMinY(card) > CGRectGetMinY(circle) - 1;
    UIView *moved = chrome.npb.subviews.firstObject;
    CALayer *shown = platter.layer.presentationLayer, *shownCard = moved.layer.presentationLayer;
    CGRect shownCircle = shown ? [shown convertRect:shown.bounds toLayer:window.layer] : CGRectNull;
    __block NSUInteger running = 0;
    SGForEachView(bar, ^(UIView *v) { running += v.layer.animationKeys.count; });
    SGForEachView(moved, ^(UIView *v) { running += v.layer.animationKeys.count; });
    BOOL inStep = minimized == leads && minimized == docked;
    NSLog(@"[harness] %@ check: %@ | circle %@ (shown %@) | card %@ (shown moved %.0f) | %lu animations | %@", moment,
          minimized ? @"minimized" : @"expanded", NSStringFromCGRect(circle), NSStringFromCGRect(shownCircle), NSStringFromCGRect(card),
          shownCard ? shownCard.transform.m42 : 0, (unsigned long)running, inStep ? @"IN STEP" : @"OUT OF STEP");
}

#pragma mark - the card's edges and the tabs' glyphs

// The glass platters shown on the bars, left to right in the window.
static NSArray<NSValue *> *shownPlatters(SGHarnessChrome *chrome) {
    UIWindow *window = chrome.view.window;
    NSMutableArray<NSValue *> *frames = [NSMutableArray array];
    SGForEachView(chrome.tabs.bar, ^(UIView *v) {
        if (![NSStringFromClass(v.class) hasSuffix:@"PlatterView"] || !v.window) return;
        for (UIView *up = v; up; up = up.superview) if (up.hidden || up.alpha < 0.01) return;
        [frames addObject:[NSValue valueWithCGRect:[v convertRect:v.bounds toView:window]]];
    });
    return [frames sortedArrayUsingComparator:^NSComparisonResult(NSValue *a, NSValue *b) {
        return [@(a.CGRectValue.origin.x) compare:@(b.CGRectValue.origin.x)];
    }];
}

// `edges`: the card's sides where they should be. Above the bar the card runs from the leading platter's leading edge
// to the trailing platter's trailing edge as UIKit drew them expanded (read at the first check, at rest), minimized
// too (in a Jam); in a regular width or right to left it keeps the 8 pt Spotify's constraints give it. In the
// minimized row it stands 8 pt from the leading circle and from the trailing one, or ends 21 pt in where there is none.
static CGFloat sgRowLeft = NAN, sgRowRight = NAN;
static void expectEdges(SGHarnessChrome *chrome, NSString *moment) {
    UIWindow *window = chrome.view.window;
    NSArray<NSString *> *args = NSProcessInfo.processInfo.arguments;
    BOOL spotify = [args containsObject:@"regular"] || [args containsObject:@"rtl"];
    BOOL split = [args containsObject:@"split"] || [args containsObject:@"split2"];
    CGFloat width = window.bounds.size.width;
    NSArray<NSValue *> *platters = shownPlatters(chrome);
    CGRect card = SGRNowPlayingCardFrameIn(window, NULL);
    if (CGRectIsNull(card) || !platters.count) HARNESS_FAIL(@"%@: card %@, %lu platters", moment, NSStringFromCGRect(card), (unsigned long)platters.count);
    CGRect lead = platters.firstObject.CGRectValue, trail = platters.lastObject.CGRectValue;
    BOOL docked = CGRectGetMinY(card) > CGRectGetMinY(lead) - 1;
    BOOL inRow = SGRTabBarMinimized() && !spotify && !sgJamStrip.window;
    if (isnan(sgRowLeft)) {
        if (SGRTabBarMinimized()) HARNESS_FAIL(@"%@: the first check is to be made expanded", moment);
        sgRowLeft = CGRectGetMinX(lead);
        sgRowRight = CGRectGetMaxX(trail);
    }
    CGFloat left, right;
    if (spotify) {
        left = 8;
        right = width - 8;
    } else if (inRow) {
        left = CGRectGetMaxX(lead) + 8;
        right = split ? CGRectGetMinX(trail) - 8 : width - 21;
    } else {
        left = sgRowLeft;
        right = sgRowRight;
    }
    if (docked != inRow || fabs(CGRectGetMinX(card) - left) > 0.5 || fabs(CGRectGetMaxX(card) - right) > 0.5) {
        HARNESS_FAIL(@"%@: card %@ (docked %d), expected x %.1f to %.1f %@; platters %@", moment, NSStringFromCGRect(card), docked, left, right,
                     inRow ? @"in the row" : @"above the bar", platters);
    }
    NSLog(@"[harness] PASS %@ edges: card x %.1f to %.1f %@", moment, CGRectGetMinX(card), CGRectGetMaxX(card), inRow ? @"in the row" : @"above the bar");
}

// Whether a glyph is filled: the mock's filled icons are solid shapes, its outline ones rings empty in the middle.
static BOOL solidGlyph(UIImage *image) {
    CGImageRef cg = image.CGImage;
    if (!cg) return NO;
    CGFloat width = CGImageGetWidth(cg), height = CGImageGetHeight(cg);
    uint8_t alpha = 0;
    CGContextRef context = CGBitmapContextCreate(&alpha, 1, 1, 8, 1, NULL, (CGBitmapInfo)kCGImageAlphaOnly);
    CGContextDrawImage(context, CGRectMake(-floor(width / 2), -floor(height / 2), width, height), cg);
    CGContextRelease(context);
    return alpha > 128;
}

// `glyphs`: the main bar selects tab `selected`, whose filled glyph it shows, and every other tab shows its outline.
static void expectGlyphs(SGHarnessChrome *chrome, NSString *moment, NSUInteger selected) {
    UITabBar *bar = systemBarIn(chrome.tabs.bar);
    NSArray<UITabBarItem *> *items = bar.items;
    if (selected >= items.count || bar.selectedItem != items[selected]) {
        HARNESS_FAIL(@"%@: tab %lu of %lu not selected (selected %lu)", moment, (unsigned long)selected, (unsigned long)items.count,
                     (unsigned long)[items indexOfObject:bar.selectedItem]);
    }
    for (NSUInteger i = 0; i < items.count; i++) {
        if (!solidGlyph(items[i].selectedImage)) HARNESS_FAIL(@"%@: tab %lu's selected glyph is an outline", moment, (unsigned long)i);
        if (i != selected && solidGlyph(items[i].image)) HARNESS_FAIL(@"%@: tab %lu not selected shows a filled glyph", moment, (unsigned long)i);
    }
    NSLog(@"[harness] PASS %@ glyphs: tab %lu filled, %lu outlined", moment, (unsigned long)selected, (unsigned long)items.count - 1);
}

// A tab of the main bar picked, the calls a finger ends in.
static void pickTab(SGHarnessChrome *chrome, NSUInteger index) {
    UITabBar *bar = systemBarIn(chrome.tabs.bar);
    UITabBarItem *item = bar.items[index];
    bar.selectedItem = item;
    [bar.delegate tabBar:bar didSelectItem:item];
}

// The list from its top, `drag` points up (a scroll down) or down (a scroll back up), let go moving.
static void fling(SGHarnessChrome *chrome, CGFloat drag) {
    UIWindow *window = chrome.view.window;
    CGFloat from = drag > 0 ? 600 : 300;
    SGHarnessDrag(window, CGPointMake(200, from), CGPointMake(200, from - drag), 0.12);
}

// What the screen shows of a view: its presentation layer's frame in the window's.
static CGRect shownFrame(UIView *view, UIWindow *window) {
    if (!view.window) return CGRectNull;
    CALayer *layer = view.layer.presentationLayer ?: view.layer, *top = window.layer.presentationLayer ?: window.layer;
    return [layer convertRect:layer.bounds toLayer:top];
}

static UIView *firstOf(UIView *root, BOOL (^match)(UIView *)) {
    if (match(root)) return root;
    for (UIView *sub in root.subviews) {
        UIView *found = firstOf(sub, match);
        if (found) return found;
    }
    return nil;
}

// `motion`: the presentation frames of what moves, sampled every frame across a stretch: the main bar's platter, its
// leading glyph, the split bar's platter and the card's glass. Each stretch logs the largest change from one frame to
// the next (x, y, width or height), when it was, and how many times the view under watch was a new one. A spring
// moves these some 20 pt a frame at most; more is a reversal snapping to the old target, or a view made anew
// somewhere else.
static NSString *const kWatched[4] = {@"platter", @"glyph", @"split platter", @"card"};

@interface SGHarnessSampler : NSObject {
@public
    CGRect last[4];
    CGFloat worst[4];
    NSTimeInterval worstAt[4];
    NSUInteger replaced[4];
}
@property (nonatomic, weak) SGHarnessChrome *chrome;
@property (nonatomic, copy) NSString *moment;
@property (nonatomic, strong) CADisplayLink *link;
@property (nonatomic) NSTimeInterval start, lastTick;
@property (nonatomic) NSUInteger frames;
@property (nonatomic, strong) NSMutableArray *views;
@end

@implementation SGHarnessSampler

- (NSArray *)watched {
    NSArray<UITabBar *> *bars = systemBarsIn(self.chrome.tabs.bar);
    UITabBar *main = bars.firstObject, *apart = bars.count > 1 && !bars[1].hidden ? bars[1] : nil;
    UIWindow *window = self.chrome.view.window;
    __block UIView *glyph = nil;
    __block CGFloat leftmost = CGFLOAT_MAX;
    SGForEachView(main, ^(UIView *v) {
        if (![v isKindOfClass:UIImageView.class] || !((UIImageView *)v).image || v.bounds.size.width < 10 || v.bounds.size.width > 40) return;
        for (UIView *up = v; up && up != main; up = up.superview) if (up.hidden || up.alpha < 0.01) return;
        CGFloat x = CGRectGetMinX(shownFrame(v, window));
        if (x < leftmost) { leftmost = x; glyph = v; }
    });
    UIView *card = firstOf(self.chrome.npb.subviews.firstObject, ^BOOL(UIView *v) {
        return [v isKindOfClass:UIVisualEffectView.class] && ((UIVisualEffectView *)v).effect && v.bounds.size.height > 40;
    });
    return @[platterIn(main) ?: NSNull.null, glyph ?: NSNull.null, (apart ? platterIn(apart) : nil) ?: NSNull.null, card ?: NSNull.null];
}

- (void)begin:(NSString *)moment {
    self.moment = moment;
    for (int i = 0; i < 4; i++) { last[i] = CGRectNull; worst[i] = 0; replaced[i] = 0; }
    self.views = [NSMutableArray arrayWithArray:@[NSNull.null, NSNull.null, NSNull.null, NSNull.null]];
    self.frames = 0;
    self.lastTick = 0;
    self.start = CACurrentMediaTime();
    self.link = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick)];
    self.link.preferredFrameRateRange = CAFrameRateRangeMake(60, 60, 60);
    [self.link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
}

- (void)tick {
    NSArray *now = [self watched];
    UIWindow *window = self.chrome.view.window;
    self.frames++;
    // A frame the simulator skipped counts as that many: the step is per 1/60 s.
    NSTimeInterval time = CACurrentMediaTime();
    CGFloat elapsed = self.lastTick > 0 ? MAX(1, round((time - self.lastTick) * 60)) : 1;
    self.lastTick = time;
    NSMutableString *line = [NSMutableString stringWithFormat:@"[harness] %@ %.3f", self.moment, time - self.start];
    for (int i = 0; i < 4; i++) {
        UIView *v = now[i] == NSNull.null ? nil : now[i];
        CGRect frame = v ? shownFrame(v, window) : CGRectNull;
        if (v && self.views[i] != NSNull.null && self.views[i] != v) replaced[i]++;
        self.views[i] = v ?: NSNull.null;
        if (!CGRectIsNull(frame) && !CGRectIsNull(last[i])) {
            CGFloat step = MAX(MAX(fabs(frame.origin.x - last[i].origin.x), fabs(frame.origin.y - last[i].origin.y)),
                               MAX(fabs(frame.size.width - last[i].size.width), fabs(frame.size.height - last[i].size.height))) / elapsed;
            if (step > worst[i]) { worst[i] = step; worstAt[i] = time - self.start; }
        }
        last[i] = frame;
        if (!CGRectIsNull(frame)) [line appendFormat:@" | %@ x %.1f y %.1f w %.1f", kWatched[i], frame.origin.x, frame.origin.y, frame.size.width];
    }
    // `timeline` logs every sample.
    if ([NSProcessInfo.processInfo.arguments containsObject:@"timeline"]) NSLog(@"%@", line);
}

- (void)end {
    [self.link invalidate];
    NSMutableString *out = [NSMutableString stringWithFormat:@"[harness] %@ motion over %lu frames:", self.moment, (unsigned long)self.frames];
    for (int i = 0; i < 4; i++) {
        if (CGRectIsNull(last[i]) && !worst[i]) continue;
        [out appendFormat:@" | %@ largest step %.1f pt at %.2f s, made anew %lu times", kWatched[i], worst[i], worstAt[i], (unsigned long)replaced[i]];
    }
    NSLog(@"%@", out);
}
@end

#pragma mark - what an earlier state leaves

static void after(double seconds, dispatch_block_t block);

// `states`' verdict: PASS or FAIL and the line, then the end of the run; with `hold`, READY and four seconds first, for a
// screenshot of what the screen shows either way.
static void statesVerdict(BOOL passed, NSString *what) {
    printf("%s %s\n", passed ? "PASS" : "FAIL", what.UTF8String);
    if (passed) printf("PASS all states\n");
    fflush(stdout);
    if (![NSProcessInfo.processInfo.arguments containsObject:@"hold"]) exit(passed ? 0 : 1);
    printf("READY\n");
    fflush(stdout);
    after(4.0, ^{ exit(passed ? 0 : 1); });
}

// The bar whose items' tab is `title` (labels hidden or not, an item reads its tab's name to VoiceOver).
static UITabBar *barHolding(SGHarnessChrome *chrome, NSString *title) {
    for (UITabBar *bar in systemBarsIn(chrome.tabs.bar)) {
        if (bar.hidden) continue;
        for (UITabBarItem *item in bar.items) if ([item.accessibilityLabel isEqualToString:title]) return bar;
    }
    return nil;
}

// Spotify's label of the tab `title` painted white: the tab Spotify is on.
static BOOL stockLit(SGHarnessChrome *chrome, NSString *title) {
    for (UIView *sub in stockItem(chrome, title).subviews) {
        if (![sub isKindOfClass:UILabel.class]) continue;
        CGFloat white = 0, alpha = 0;
        return [((UILabel *)sub).textColor getWhite:&white alpha:&alpha] && white > 0.95;
    }
    return NO;
}

// `states` alone: the bar minimized in a compact width, then the window made regular (an iPad's narrow window widened)
// with no tab changed: the whole row is back, not the two circles. With `split`: Search, the only split tab, picked on
// its bar; Home chosen elsewhere (a link or the side drawer: Spotify repaints its labels and tells its container, with no
// tap on the glass bar); the bar minimized; a finger on Search's circle: Spotify's Search is tapped, not only the bar
// expanded.
static void runStates(SGHarnessChrome *chrome) {
    if (![NSProcessInfo.processInfo.arguments containsObject:@"split"]) {
        SGRSetTabBarMinimized(YES, NO);
        [chrome.view layoutIfNeeded];
        if (!SGRTabBarMinimized()) HARNESS_FAIL(@"the bar did not minimize in a compact width");
        chrome.traitOverrides.horizontalSizeClass = UIUserInterfaceSizeClassRegular;
        [chrome updateTraitsIfNeeded];
        // Spotify lays its bar out again for the new width.
        [chrome.tabs.bar setNeedsLayout];
        [chrome.view layoutIfNeeded];
        UITabBar *bar = systemBarIn(chrome.tabs.bar);
        NSUInteger tabs = SGRowIn(chrome.tabs.bar).arrangedSubviews.count;
        BOOL whole = !SGRTabBarMinimized() && bar.items.count == tabs;
        statesVerdict(whole, [NSString stringWithFormat:@"widened to a regular width: the bar %@, %lu of %lu tabs on it",
                              SGRTabBarMinimized() ? @"still minimized" : @"expanded", (unsigned long)bar.items.count, (unsigned long)tabs]);
        return;
    }
    UITabBar *apart = barHolding(chrome, @"Search");
    UITabBarItem *search = apart.items.firstObject;
    if (!search || apart.items.count != 1) HARNESS_FAIL(@"Search is not alone on a bar of its own: %@", apart.items);
    apart.selectedItem = search;
    [apart.delegate tabBar:apart didSelectItem:search];
    after(0.5, ^{
        if (!stockLit(chrome, @"Search")) HARNESS_FAIL(@"picking Search on its bar did not tap Spotify's Search");
        UIView *home = stockItem(chrome, @"Home");
        for (UIGestureRecognizer *r in home.gestureRecognizers) {
            if ([r isKindOfClass:UITapGestureRecognizer.class]) [_TtC23NavigationUI_TabBarImpl19TabBarContainerImpl tapped:(UITapGestureRecognizer *)r];
        }
        [chrome.tabs setSelectedViewController:nil];
    });
    after(1.0, ^{
        UITabBar *main = barHolding(chrome, @"Home");
        if (![main.selectedItem.accessibilityLabel isEqualToString:@"Home"] || apart.selectedItem) {
            HARNESS_FAIL(@"Home chosen elsewhere: the main bar selects %@, Search's bar %@", main.selectedItem.accessibilityLabel, apart.selectedItem.accessibilityLabel);
        }
        SGRSetTabBarMinimized(YES, NO);
        [chrome.view layoutIfNeeded];
        UIView *platter = platterIn(apart);
        UIWindow *window = chrome.view.window;
        CGRect circle = [platter convertRect:platter.bounds toView:window];
        if (!SGRTabBarMinimized() || apart.hidden || !platter) HARNESS_FAIL(@"the bar did not minimize to Search's circle");
        SGHarnessTap(window, CGPointMake(CGRectGetMidX(circle), CGRectGetMidY(circle)));
    });
    after(1.8, ^{
        BOOL tapped = stockLit(chrome, @"Search");
        statesVerdict(tapped, [NSString stringWithFormat:@"a finger on Search's circle after Home was chosen elsewhere: Spotify's Search %@, the bar %@",
                               tapped ? @"tapped" : @"not tapped", SGRTabBarMinimized() ? @"minimized" : @"expanded"]);
    });
}

#pragma mark - the listener's glass

// `glass`: the listener's glass (Redesigned/Kit/SGRGlass.h) on the platter of every bar shown and on the now playing
// card, expanded and then minimized, each held for a screenshot (a SHOT line, with AREA lines naming the glass in
// points); then real taps on Your Library's tab and on the card's play button, which must work whatever touch response
// says. Every glass's tint and touch response are read here, and the platters' material; the card's material shows
// only on the screen. What each glass should be is given as literals: -harness.wantMaterial (0 Regular, 1 Clear), -harness.wantTint
// (0 none, 1 white at 30%, 2 black at 45%) and -harness.wantInteractive. UIKit's own platter glass is Regular,
// untinted and interactive, so the defaults expect it as UIKit made it.
static void expectGlass(NSInteger style, UIColor *tintColor, BOOL isInteractive, NSString *what, NSString *moment) {
    NSUserDefaults *store = NSUserDefaults.standardUserDefaults;
    NSInteger material = [store integerForKey:@"harness.wantMaterial"], tint = [store integerForKey:@"harness.wantTint"];
    BOOL interactive = [store boolForKey:@"harness.wantInteractive"];
    CGFloat white = -1, alpha = 0;
    if (tintColor && ![tintColor getWhite:&white alpha:&alpha]) HARNESS_FAIL(@"%@: %@ tinted %@", moment, what, tintColor);
    BOOL tintRight = tint == 0 ? tintColor == nil
        : fabs(white - (tint == 1 ? 1 : 0)) < 0.01 && fabs(alpha - (tint == 1 ? 0.3 : 0.45)) < 0.01;
    if ((style != NSNotFound && style != material) || !tintRight || isInteractive != interactive) {
        HARNESS_FAIL(@"%@: %@ is style %ld, tint %@, interactive %d; want %ld, %ld, %d", moment, what, (long)style, tintColor,
                     isInteractive, (long)material, (long)tint, interactive);
    }
}

static void shotGlass(SGHarnessChrome *chrome, NSString *moment, NSString *shot) {
    UIWindow *window = chrome.view.window;
    NSUInteger platters = 0;
    for (UITabBar *bar in systemBarsIn(chrome.tabs.bar)) {
        UIView *platter = bar.hidden ? nil : platterIn(bar);
        if (!platter.window) continue;
        // A platter's glass is its own background, a _UIViewGlass; -_glassEffect reads its style back as Regular
        // whatever it is, so the material and the touch response are read from the glass itself.
        NSString *background = [[platter valueForKey:@"_background"] description];
        NSInteger style = [background containsString:@"Configuration(clear)"] ? 1 : [background containsString:@"Configuration(regular)"] ? 0 : -1;
        BOOL flexible = [background containsString:@"isFlexible: true"];
        expectGlass(style, [[platter valueForKey:@"_glassEffect"] valueForKey:@"tintColor"], flexible,
                    [NSString stringWithFormat:@"platter %lu (%@)", (unsigned long)platters, background], moment);
        CGRect frame = [platter convertRect:platter.bounds toView:window];
        printf("AREA platter%lu %.1f %.1f %.1f %.1f\n", (unsigned long)platters, frame.origin.x, frame.origin.y, frame.size.width, frame.size.height);
        platters++;
    }
    if (platters == 0) HARNESS_FAIL(@"%@: no platter shown", moment);
    CGRect card = SGRNowPlayingCardFrameIn(window, NULL);
    UIVisualEffectView *pane = nil;
    for (UIView *sub in chrome.npb.subviews.firstObject.subviews) {
        if ([sub isKindOfClass:UIVisualEffectView.class] && CGRectEqualToRect([sub convertRect:sub.bounds toView:window], card)) pane = (UIVisualEffectView *)sub;
    }
    if (!pane) HARNESS_FAIL(@"%@: no glass under the card at %@", moment, NSStringFromCGRect(card));
    if (![pane.effect isKindOfClass:NSClassFromString(@"UIGlassEffect")]) HARNESS_FAIL(@"%@: the card has %@, not glass", moment, pane.effect);
    // An effect view hands back its glass rebuilt without its style (Regular for a Clear one, iOS 26.5): the card's
    // material is judged from the screen (glass-check.py).
    expectGlass(NSNotFound, [pane.effect valueForKey:@"tintColor"],
                [[pane.effect valueForKey:@"interactive"] boolValue], @"the card's glass", moment);
    printf("AREA card %.1f %.1f %.1f %.1f\nSHOT %s\n", card.origin.x, card.origin.y, card.size.width, card.size.height, shot.UTF8String);
    fflush(stdout);
    NSLog(@"[harness] PASS %@: %lu platters and the card in the glass asked for", moment, (unsigned long)platters);
}

static void runGlass(SGHarnessChrome *chrome) {
    NSString *shot = [NSUserDefaults.standardUserDefaults stringForKey:@"harness.shot"] ?: @"glass";
    NSLog(@"[harness] glass with Reduce Transparency %@", UIAccessibilityIsReduceTransparencyEnabled() ? @"on" : @"off");
    shotGlass(chrome, @"expanded", [shot stringByAppendingString:@"-expanded"]);
    after(3.0, ^{
        SGRSetTabBarMinimized(YES, NO);
        [chrome.view layoutIfNeeded];
    });
    after(3.5, ^{
        if (!SGRTabBarMinimized()) HARNESS_FAIL(@"the bar did not minimize");
        shotGlass(chrome, @"minimized", [shot stringByAppendingString:@"-minimized"]);
    });
    after(6.5, ^{
        SGRSetTabBarMinimized(NO, NO);
        [chrome.view layoutIfNeeded];
    });
    __block NSUInteger plays = 0;
    after(7.0, ^{
        UIWindow *window = chrome.view.window;
        UITabBar *bar = barHolding(chrome, @"Your Library");
        NSUInteger index = [bar.items indexOfObjectPassingTest:^BOOL(UITabBarItem *item, NSUInteger i, BOOL *stop) {
            return [item.accessibilityLabel isEqualToString:@"Your Library"];
        }];
        // UIKit's tab buttons, left to right, in the platter's content (not the copy it lifts into the selection).
        NSMutableArray<UIView *> *buttons = [NSMutableArray array];
        SGForEachView(bar, ^(UIView *v) {
            NSString *holder = NSStringFromClass(v.superview.class);
            if ([v isKindOfClass:UIControl.class] && [holder hasSuffix:@"ContentView"] && ![holder hasSuffix:@"SelectedContentView"]) [buttons addObject:v];
        });
        [buttons sortUsingComparator:^NSComparisonResult(UIView *a, UIView *b) {
            return [@([a convertRect:a.bounds toView:window].origin.x) compare:@([b convertRect:b.bounds toView:window].origin.x)];
        }];
        UIView *tab = index < buttons.count && buttons.count == bar.items.count ? buttons[index] : nil;
        if (!tab || stockLit(chrome, @"Your Library")) HARNESS_FAIL(@"Your Library's tab %@ of %@, already on: %d", tab, buttons, stockLit(chrome, @"Your Library"));
        CGRect frame = [tab convertRect:tab.bounds toView:window];
        SGHarnessTap(window, CGPointMake(CGRectGetMidX(frame), CGRectGetMidY(frame)));
    });
    after(8.0, ^{
        if (!stockLit(chrome, @"Your Library")) HARNESS_FAIL(@"a finger on Your Library's tab did not tap Spotify's");
        UIWindow *window = chrome.view.window;
        // The mock's own play button sits past the card's trailing edge (the mock's page is wider than the card), so
        // one goes beside it where the card shows its play button, 16 pt in from the card's trailing edge.
        CGRect card = SGRNowPlayingCardFrameIn(window, NULL);
        UIButton *mock = (UIButton *)firstOf(chrome.npb, ^BOOL(UIView *v) {
            return [v isKindOfClass:UIButton.class] && [((UIButton *)v).currentImage isEqual:[UIImage systemImageNamed:@"play.fill"]];
        });
        if (!mock) HARNESS_FAIL(@"no play button in the now playing bar");
        UIButton *play = [UIButton systemButtonWithImage:[UIImage systemImageNamed:@"play.fill"] target:nil action:nil];
        play.frame = [mock.superview convertRect:CGRectMake(CGRectGetMaxX(card) - 48, CGRectGetMidY(card) - 16, 32, 32) fromView:window];
        [mock.superview addSubview:play];
        [play addAction:[UIAction actionWithHandler:^(UIAction *action) { plays++; }] forControlEvents:UIControlEventTouchUpInside];
        CGRect frame = [play convertRect:play.bounds toView:window];
        CGPoint middle = CGPointMake(CGRectGetMidX(frame), CGRectGetMidY(frame));
        UIView *hit = [window hitTest:middle withEvent:nil];
        if (hit != play) HARNESS_FAIL(@"a finger on the card's play button at %@ lands on %@", NSStringFromCGPoint(middle), hit);
        SGHarnessTap(window, middle);
    });
    after(9.0, ^{
        if (plays != 1) HARNESS_FAIL(@"a finger on the card's play button played %lu times", (unsigned long)plays);
        NSLog(@"[harness] PASS all glass: the tab and the card's play button took their taps");
        exit(0);
    });
}

#pragma mark - the app

// Before every %ctor, so the redesign's gate reads on; the fade under the bars on unless the launch line says `off`;
// Apple symbols stored off (the product's default is on; `symbols` switches it itself), and the tabs' names stored
// hidden (the product's default shows them), but shown from the bar's first pass with `names` and `symbols` (not `symbols hold`):
// the glyph checks below compare Spotify's own glyphs on a bar of icons alone.
__attribute__((constructor(101))) static void sgr_harnessDefaults(void) {
    NSUserDefaults *store = NSUserDefaults.standardUserDefaults;
    NSArray<NSString *> *args = NSProcessInfo.processInfo.arguments;
    [store setBool:YES forKey:@"spotifyglass.redesign"];
    if ([args containsObject:@"off"]) [store setBool:NO forKey:SGRKeyNavbarFade];
    else [store removeObjectForKey:SGRKeyNavbarFade];
    [store setBool:NO forKey:SGRKeyNavbarSymbols];
    BOOL names = (args.count > 1 && [args[1] isEqualToString:@"symbols"] && ![args containsObject:@"hold"])
              || (args.count > 1 && [args[1] isEqualToString:@"search"] && [args containsObject:@"labels"])
              || (args.count > 1 && [args[1] isEqualToString:@"names"]);
    [store setBool:!names forKey:SGRKeyNavbarHideLabels];
}

void SGHarnessRunNavbarPage(SGHarnessChrome *chrome, void (^barChecked)(BOOL on));
void SGHarnessRunSymbols(SGHarnessChrome *chrome);
void SGHarnessRunSearch(UIView *stockBar);

@interface SGHarnessApp : UIResponder <UIApplicationDelegate>
@end
@implementation SGHarnessApp
@end

@interface SGHarnessScene : UIResponder <UIWindowSceneDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation SGHarnessScene

static void after(double seconds, dispatch_block_t block) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(seconds * NSEC_PER_SEC)), dispatch_get_main_queue(), block);
}

- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    self.window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    self.window.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    SGHarnessChrome *chrome = [SGHarnessChrome new];
    self.window.rootViewController = chrome;
    [self.window makeKeyAndVisible];

    // What happens, from the launch argument: `none` no message bar, `shown` one sliding in at 1.5 s,
    // `away` one there from the start sliding away at 1.5 s, `cycle` in at 1.5 s and out at 4.5 s.
    NSArray<NSString *> *args = NSProcessInfo.processInfo.arguments;
    NSString *mode = args.count > 1 ? args[1] : @"none";
    BOOL reparentFling = [mode isEqualToString:@"reparent-fling"];
    if (reparentFling || [mode isEqualToString:@"reparent-drag"]) {
        UIView *wrapper = [[UIView alloc] initWithFrame:CGRectMake(0, 100, 380, 560)];
        UIScrollView *scroll = [[UIScrollView alloc] initWithFrame:wrapper.bounds];
        scroll.contentSize = CGSizeMake(380, 3000);
        [wrapper addSubview:scroll];
        [chrome.view addSubview:wrapper];
        if (reparentFling) {
            after(.7, ^{
                fling(chrome, 250);
                after(.22, ^{
                    HARNESS_CHECK(scroll.isDecelerating && !SGRTabBarMinimized());
                    [chrome.tabs.view addSubview:wrapper];
                    CGFloat start = scroll.contentOffset.y;
                    after(.6, ^{
                        CGFloat travel = scroll.contentOffset.y - start;
                        HARNESS_CHECK(travel > 24);
                        if (!SGRTabBarMinimized()) HARNESS_FAIL(@"bar still expanded after %.1f pt on tab", travel);
                        NSLog(@"[harness] PASS bar minimized after %.1f pt on tab during fling", travel);
                        exit(0);
                    });
                });
            });
            return;
        }
        after(.7, ^{
            scroll.contentOffset = CGPointMake(0, 1);
            [chrome.tabs.view addSubview:wrapper];
            fling(chrome, 250);
        });
        after(1.7, ^{
            HARNESS_CHECK(scroll.contentOffset.y > 24 && SGRTabBarMinimized());
            [scroll setContentOffset:CGPointZero animated:NO];
            SGRSetTabBarMinimized(NO, NO);
            [chrome.view addSubview:wrapper];
            fling(chrome, 250);
        });
        after(2.8, ^{
            HARNESS_CHECK(scroll.contentOffset.y > 24 && !SGRTabBarMinimized());
            NSLog(@"[harness] PASS wrapper moved onto tab and off tab before drags");
            exit(0);
        });
        return;
    }
    if ([mode isEqualToString:@"audit"]) {
        after(1, ^{
            UIStackView *row = SGRowIn(chrome.tabs.bar);
            NSArray<UIView *> *tabs = row.arrangedSubviews;
            for (NSUInteger i = 1; i < tabs.count; i++) tabs[i].hidden = YES;
            [chrome.tabs.bar setNeedsLayout];
            [chrome.view layoutIfNeeded];
            SGRSetTabBarMinimized(YES, NO);
            if (SGRTabBarMinimized() || !CGRectIsNull(SGRTabBarInlineSlot(chrome.view, 56))) {
                NSLog(@"[harness] FAIL one visible tab minimized");
                exit(1);
            }
            for (UIView *tab in tabs) tab.hidden = NO;
            [chrome.tabs.bar setNeedsLayout];
            [chrome.view layoutIfNeeded];
            SGRSetTabBarMinimized(YES, NO);
            if (!SGRTabBarMinimized()) {
                NSLog(@"[harness] FAIL multiple tabs did not minimize");
                exit(1);
            }
            for (NSUInteger i = 1; i < tabs.count; i++) tabs[i].hidden = YES;
            [chrome.tabs.bar setNeedsLayout];
            [chrome.view layoutIfNeeded];
            if (SGRTabBarMinimized() || !CGRectIsNull(SGRTabBarInlineSlot(chrome.view, 56))) {
                NSLog(@"[harness] FAIL removing tabs left an inline slot");
                exit(1);
            }
            UITabBar *bar = systemBarIn(chrome.tabs.bar);
            NSData *before = UIImagePNGRepresentation(bar.items.firstObject.image);
            UIView *source = tabs.firstObject;
            for (UIView *sub in source.subviews) if ([sub isKindOfClass:UIImageView.class]) [sub removeFromSuperview];
            UIImageView *replacement = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"circle.fill"]];
            replacement.tintColor = UIColor.whiteColor;
            replacement.frame = CGRectMake(0, 5.67, 24, 24);
            [source addSubview:replacement];
            [chrome.tabs.bar setNeedsLayout];
            [chrome.view layoutIfNeeded];
            UITabBarItem *updated = bar.items.firstObject;
            if (!updated.image || !updated.selectedImage
                || [before isEqual:UIImagePNGRepresentation(updated.image)]
                || [before isEqual:UIImagePNGRepresentation(updated.selectedImage)]) {
                NSLog(@"[harness] FAIL edited glyph stayed unchanged");
                exit(1);
            }
            NSLog(@"[harness] PASS single-tab minimization, composition change and icon replacement");
            exit(0);
        });
        return;
    }
    // `fade`: the page in color under the bars with the fade on (`off`: off from the launch), checked at 1.5 s and
    // then held for a screenshot (READY); `mini` minimizes the bar first. `fade toggle` runs runFadeChecks instead.
    if ([mode isEqualToString:@"fade"]) {
        if ([args containsObject:@"mini"]) after(1.0, ^{ SGRSetTabBarMinimized(YES, NO); });
        after(1.5, ^{
            if ([args containsObject:@"toggle"]) {
                runFadeChecks(chrome);
                return;
            }
            expectFade(chrome, ![args containsObject:@"off"], [[args subarrayWithRange:NSMakeRange(1, args.count - 1)] componentsJoinedByString:@" "]);
            printf("READY\n");
            fflush(stdout);
            after(4.0, ^{ exit(0); });
        });
        return;
    }
    // `navsettings`: the Tab bar page over the bar (navsettings.m).
    if ([mode isEqualToString:@"navsettings"]) {
        after(1.0, ^{ SGHarnessRunNavbarPage(chrome, ^(BOOL on) { expectFade(chrome, on, on ? @"the page's switch on" : @"the page's switch off"); }); });
        return;
    }
    // `symbols`: Apple symbols from the Tab bar page over the bar, a tab of the mod's own on it (navsettings.m).
    if ([mode isEqualToString:@"symbols"]) {
        after(1.0, ^{ SGHarnessRunSymbols(chrome); });
        return;
    }
    // `search`: Search on the minimized bar's trailing circle (search.m).
    if ([mode isEqualToString:@"search"]) {
        after(1.0, ^{ SGHarnessRunSearch(chrome.tabs.bar); });
        return;
    }
    // `glass`: the listener's glass on the bars and the card (runGlass).
    if ([mode isEqualToString:@"glass"]) {
        after(1.0, ^{ runGlass(chrome); });
        return;
    }
    // `states`: what an earlier state leaves on the bar (runStates).
    if ([mode isEqualToString:@"states"]) {
        after(1.0, ^{ runStates(chrome); });
        return;
    }
    // `jam`: in a Jam from the start, and out of it at 3.5 s.
    if ([mode isEqualToString:@"jam"]) {
        after(3.5, ^{
            [sgJamStrip removeFromSuperview];
            chrome.npbHeight.constant = 64;
            [chrome.view layoutIfNeeded];
        });
        after(4.5, ^{ report(chrome, @"left the jam"); });
    }
    if ([mode isEqualToString:@"away"]) [chrome setBanner:YES animated:NO];
    // `mini`: the bar minimized at 1 s and logged at 2.5 s, expanded again at 3.5 s and logged at 5 s.
    if ([mode isEqualToString:@"mini"]) {
        after(1.0, ^{ SGRSetTabBarMinimized(YES, YES); });
        after(3.5, ^{ SGRSetTabBarMinimized(NO, YES); });
        after(5.0, ^{ report(chrome, @"expanded again"); });
    }
    // `tap`: the bar minimized at 1 s, then what a finger on the leading circle lands on, and that tap played.
    if ([mode isEqualToString:@"tap"]) {
        after(1.0, ^{ SGRSetTabBarMinimized(YES, YES); });
        after(2.5, ^{
            report(chrome, @"minimized");
            UITabBar *bar = systemBarIn(chrome.tabs.bar);
            UIView *platter = platterIn(bar);
            UIWindow *window = chrome.view.window;
            CGRect circle = [platter convertRect:platter.bounds toView:window];
            UIView *hit = [window hitTest:CGPointMake(CGRectGetMidX(circle), CGRectGetMidY(circle)) withEvent:nil];
            NSLog(@"[harness] touch on the leading circle %@ lands on %@, on the glass bar: %d", NSStringFromCGRect(circle),
                  NSStringFromClass(hit.class), [hit isDescendantOfView:bar]);
            for (UIView *v = hit; v && v != window; v = v.superview) {
                for (UIGestureRecognizer *r in v.gestureRecognizers) NSLog(@"[harness]   recognizer %@ on %@", NSStringFromClass(r.class), NSStringFromClass(v.class));
                if ([v isKindOfClass:UIControl.class]) NSLog(@"[harness]   control %@", NSStringFromClass(v.class));
            }
            // With `split`, the trailing circle keeps its own touches too.
            for (UITabBar *other in systemBarsIn(chrome.tabs.bar)) {
                UIView *otherPlatter = other == bar || other.hidden ? nil : platterIn(other);
                if (!otherPlatter) continue;
                CGRect trailing = [otherPlatter convertRect:otherPlatter.bounds toView:window];
                UIView *otherHit = [window hitTest:CGPointMake(CGRectGetMidX(trailing), CGRectGetMidY(trailing)) withEvent:nil];
                NSLog(@"[harness] touch on the trailing circle %@ lands on %@, on its glass bar: %d", NSStringFromCGRect(trailing),
                      NSStringFromClass(otherHit.class), [otherHit isDescendantOfView:other]);
            }
            SGHarnessTap(window, CGPointMake(CGRectGetMidX(circle), CGRectGetMidY(circle)));
        });
        after(3.5, ^{ report(chrome, @"after the tap"); });
        after(3.6, ^{ reportSelection(chrome, @"after the tap"); });
        // It stays expanded until the list is scrolled down again.
        after(5.0, ^{ report(chrome, @"a while after the tap"); });
    }
    // `turns`: real flings on the list, from its top: one down that minimizes the bar, one back up that turns it
    // half way, then down again half way through that, and a finger stopping the list as the bar minimizes.
    // Every check at rest should be IN STEP with no animations left.
    if ([mode isEqualToString:@"turns"]) {
        UITableView *list = (UITableView *)chrome.tabs.childViewControllers.firstObject.view;
        after(0.7, ^{ [list setContentOffset:CGPointMake(0, -list.adjustedContentInset.top) animated:NO]; });
        after(1.0, ^{ fling(chrome, 250); });
        after(1.3, ^{ check(chrome, @"minimizing"); });
        after(2.4, ^{ check(chrome, @"minimized"); });
        // Room both ways again after the report at 2.5 takes the list to its end.
        after(2.7, ^{ [list setContentOffset:CGPointMake(0, 300) animated:NO]; });
        after(3.0, ^{ fling(chrome, -150); });
        after(3.25, ^{ fling(chrome, 250); });
        after(5.0, ^{ check(chrome, @"after turning back half way"); });
        after(5.5, ^{ fling(chrome, -150); });
        after(5.75, ^{ SGHarnessTap(chrome.view.window, CGPointMake(200, 400)); });
        after(7.0, ^{ check(chrome, @"after a finger stopped the list"); });
        after(7.5, ^{ fling(chrome, 250); });
        after(7.65, ^{ fling(chrome, -150); });
        after(7.8, ^{ fling(chrome, 250); });
        after(7.95, ^{ fling(chrome, -150); });
        after(9.5, ^{ check(chrome, @"after four quick turns"); });
    }
    // `motion`: a minimize and an expand, each turned back 0.15 s in, and four turns 0.1 s apart, sampled every
    // frame (SGHarnessSampler). No largest step should be much over a spring's, nothing should be made anew while it
    // moves, names should be whole mid-expand, and every check IN STEP.
    if ([mode isEqualToString:@"motion"]) {
        static SGHarnessSampler *sampler;
        sampler = [SGHarnessSampler new];
        sampler.chrome = chrome;
        // Each stretch lasts 1 s and the next starts 0.3 s after it; turns are timed from the stretch's start,
        // since dispatch_after may run a block up to a tenth of its delay late, which at 3 s swallowed a turn
        // 0.15 s after another. The first turn of each goes the other way from where the bar is.
        NSArray *stretches = @[
            @[@"minimize", @[@0]],
            @[@"expand", @[@0]],
            @[@"minimize turned back", @[@0, @0.15]],
            @[@"minimize again", @[@0]],
            @[@"expand turned back", @[@0, @0.15]],
            @[@"four quick turns", @[@0, @0.1, @0.2, @0.3]],
        ];
        static void (^run)(NSUInteger);
        run = ^(NSUInteger index) {
            if (index >= stretches.count) {
                reportNames(chrome, @"after the turns");
                return;
            }
            NSString *moment = stretches[index][0];
            NSArray<NSNumber *> *turns = stretches[index][1];
            BOOL first = !SGRTabBarMinimized();
            [sampler begin:moment];
            for (NSUInteger i = 0; i < turns.count; i++) {
                BOOL minimize = i % 2 == 0 ? first : !first;
                after(turns[i].doubleValue, ^{ SGRSetTabBarMinimized(minimize, YES); });
            }
            after(0.15, ^{
                if (!first) reportNames(chrome, [moment stringByAppendingString:@", 0.15 s in"]);
            });
            after(1.0, ^{
                [sampler end];
                check(chrome, moment);
                reportNames(chrome, [moment stringByAppendingString:@", at rest"]);
                after(0.3, ^{ run(index + 1); });
            });
        };
        after(1.0, ^{ run(0); });
    }
    // `nested`: the bar minimized from inside someone else's animation: a property animator scrubbed by hand and
    // left paused a third of the way, as a header that follows the scroll keeps one (at 1 s), and a plain
    // animation block (at 4 s, expanding). Each check at rest should be IN STEP with no animations left.
    if ([mode isEqualToString:@"nested"]) {
        static UIViewPropertyAnimator *scrub;
        after(1.0, ^{
            UIView *page = chrome.tabs.childViewControllers.firstObject.view;
            scrub = [[UIViewPropertyAnimator alloc] initWithDuration:1 curve:UIViewAnimationCurveLinear animations:^{
                page.alpha = 0.9;
                SGRSetTabBarMinimized(YES, YES);
            }];
            scrub.fractionComplete = 0.33;
        });
        after(2.4, ^{ check(chrome, @"minimized in a paused animator"); });
        after(4.0, ^{
            [UIView animateWithDuration:3 animations:^{ SGRSetTabBarMinimized(NO, YES); }];
        });
        after(4.4, ^{ check(chrome, @"expanding in a slow animation block"); });
        after(5.6, ^{ check(chrome, @"expanded in a slow animation block"); });
    }
    // `names`: the titles at rest, after a minimize and expand, after scrolls that turn the bar back before
    // it settles, and mid-expand; `split`, `five` and `long` change the bar. Every report should say 0 cut.
    if ([mode isEqualToString:@"names"]) {
        after(1.0, ^{ reportNames(chrome, @"at rest"); });
        after(1.2, ^{ SGRSetTabBarMinimized(YES, YES); });
        after(2.4, ^{
            SGRSetTabBarMinimized(NO, YES);
            reportNames(chrome, @"expanding");
        });
        after(2.55, ^{ reportNames(chrome, @"mid-expand"); });
        after(4.0, ^{ reportNames(chrome, @"expanded"); });
        after(4.2, ^{ SGRSetTabBarMinimized(YES, YES); });
        after(4.3, ^{ SGRSetTabBarMinimized(NO, YES); });
        after(4.4, ^{ SGRSetTabBarMinimized(YES, YES); });
        after(4.5, ^{ SGRSetTabBarMinimized(NO, YES); });
        after(6.0, ^{ reportNames(chrome, @"after quick turns"); });
        after(6.2, ^{ SGRSetTabBarMinimized(YES, NO); });
        after(6.4, ^{ SGRSetTabBarMinimized(NO, NO); });
        after(7.0, ^{ reportNames(chrome, @"after a cut"); });
        after(7.2, ^{
            [chrome.tabs.bar setNeedsLayout];
            [chrome.tabs.bar layoutIfNeeded];
        });
        after(7.5, ^{
            reportNames(chrome, @"after Spotify lays out");
            if ([NSProcessInfo.processInfo.arguments containsObject:@"strict"]) {
                printf("PASS all names\n");
                fflush(stdout);
                exit(0);
            }
        });
    }
    // `edges` (after `none`, `split`, `split2` or `jam`, with `regular` or `rtl` for Spotify's own edges): the card's
    // sides at rest, minimized and expanded with no animation, after a minimize turned back mid-spring, and minimized
    // and expanded on the spring. In `jam` the strip leaves at 3.5 s, so the spring's minimize docks the card.
    if ([args containsObject:@"edges"]) {
        after(1.5, ^{
            expectEdges(chrome, @"at rest");
            SGRSetTabBarMinimized(YES, NO);
            [chrome.view layoutIfNeeded];
            expectEdges(chrome, @"minimized, cut");
            SGRSetTabBarMinimized(NO, NO);
            [chrome.view layoutIfNeeded];
            expectEdges(chrome, @"expanded, cut");
            SGRSetTabBarMinimized(YES, YES);
        });
        after(1.65, ^{ SGRSetTabBarMinimized(NO, YES); });
        after(3.0, ^{
            expectEdges(chrome, @"after a minimize turned back");
            SGRSetTabBarMinimized(YES, YES);
        });
        after(4.4, ^{
            expectEdges(chrome, @"minimized on the spring");
            SGRSetTabBarMinimized(NO, YES);
        });
        after(5.8, ^{
            expectEdges(chrome, @"expanded on the spring");
            printf("PASS all edges\n");
            fflush(stdout);
            exit(0);
        });
    }
    // `glyphs`: Home selected at launch, its view holding its filled icon. Search picked, then Home again, the bar
    // minimized and expanded on the spring, and Home's view handed another icon: the selected tab shows the filled
    // glyph and every other one its outline throughout.
    if ([mode isEqualToString:@"glyphs"]) {
        static NSData *circle;
        after(1.0, ^{
            expectGlyphs(chrome, @"at launch", 0);
            pickTab(chrome, 1);
        });
        after(1.8, ^{
            expectGlyphs(chrome, @"after Search", 1);
            pickTab(chrome, 0);
        });
        after(2.6, ^{
            expectGlyphs(chrome, @"after Home", 0);
            SGRSetTabBarMinimized(YES, YES);
        });
        after(3.8, ^{
            UITabBar *bar = systemBarIn(chrome.tabs.bar);
            if (!SGRTabBarMinimized() || bar.items.count != 1) HARNESS_FAIL(@"the bar did not minimize to one circle");
            expectGlyphs(chrome, @"minimized", 0);
            SGRSetTabBarMinimized(NO, YES);
        });
        after(5.0, ^{
            expectGlyphs(chrome, @"expanded", 0);
            circle = UIImagePNGRepresentation(systemBarIn(chrome.tabs.bar).items.firstObject.image);
            // The same view, another icon: Home's selected, so its filled one.
            for (UIView *sub in stockItem(chrome, @"Home").subviews) {
                if (![sub isKindOfClass:SGHarnessGlyphView.class]) continue;
                SGHarnessGlyphView *glyph = (SGHarnessGlyphView *)sub;
                glyph.outline = [SGHarnessEncoreIcon outlineNamed:@"square" square:YES];
                [glyph show:sgSwiftIcons ? glyph.outline : glyph.outline.active];
            }
            [chrome.tabs.bar setNeedsLayout];
            [chrome.tabs.bar layoutIfNeeded];
        });
        after(5.5, ^{
            expectGlyphs(chrome, @"Home's icon replaced", 0);
            pickTab(chrome, 1);
        });
        after(6.3, ^{
            expectGlyphs(chrome, @"after Search, Home's icon replaced", 1);
            if ([circle isEqual:UIImagePNGRepresentation(systemBarIn(chrome.tabs.bar).items.firstObject.image)]) {
                HARNESS_FAIL(@"Home still shows the icon it had before its view was handed another");
            }
            printf("PASS all glyphs\n");
            fflush(stdout);
            exit(0);
        });
    }
    // `lit`: Library stands in for a tab of the mod's own whose page is up at 2 s, while Spotify still paints
    // Home white: the glass bar selects Library. Home picked at 3.5 s takes the light back.
    if ([mode isEqualToString:@"lit"]) {
        after(2.0, ^{
            sgHarnessLitTab = stockItem(chrome, @"Your Library");
            [chrome.tabs.bar setNeedsLayout];
            [chrome.tabs.bar layoutIfNeeded];
        });
        after(2.5, ^{ reportSelection(chrome, @"with Library lit"); });
        after(3.5, ^{ pick(chrome, @"Home"); });
        after(4.5, ^{ reportSelection(chrome, @"after Home"); });
    }
    // `pick`: Search picked at 2 s and Home at 4 s, which bar selects what logged after each.
    if ([mode isEqualToString:@"pick"]) {
        after(2.0, ^{ pick(chrome, @"Search"); });
        after(3.0, ^{ reportSelection(chrome, @"after Search"); });
        after(4.0, ^{ pick(chrome, @"Home"); });
        after(5.0, ^{ reportSelection(chrome, @"after Home"); });
    }
    after(0.5, ^{
        UITableView *list = (UITableView *)chrome.tabs.childViewControllers.firstObject.view;
        [list scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:29 inSection:0] atScrollPosition:UITableViewScrollPositionBottom animated:NO];
        report(chrome, @"start");
    });
    if ([mode isEqualToString:@"shown"] || [mode isEqualToString:@"cycle"]) after(1.5, ^{ [chrome setBanner:YES animated:YES]; });
    if ([mode isEqualToString:@"away"]) after(1.5, ^{ [chrome setBanner:NO animated:YES]; });
    if ([mode isEqualToString:@"cycle"]) after(4.5, ^{ [chrome setBanner:NO animated:YES]; });
    // Half way through the slide, what the screen shows (the presentation layers).
    if ([mode isEqualToString:@"shown"] || [mode isEqualToString:@"away"] || [mode isEqualToString:@"cycle"]) after(1.5 + 0.17, ^{
        CALayer *stock = chrome.tabs.bar.layer.presentationLayer, *npb = chrome.npb.layer.presentationLayer, *banner = chrome.banner.layer.presentationLayer;
        NSLog(@"[harness] mid-slide presented: banner top %.1f, tab bar top %.1f, now playing bar bottom %.1f",
              [banner convertPoint:CGPointZero toLayer:self.window.layer.presentationLayer].y,
              [stock convertPoint:CGPointZero toLayer:self.window.layer.presentationLayer].y,
              [npb convertPoint:CGPointMake(0, npb.bounds.size.height) toLayer:self.window.layer.presentationLayer].y);
    });
    after(2.5, ^{
        UITableView *list = (UITableView *)chrome.tabs.childViewControllers.firstObject.view;
        [list scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:29 inSection:0] atScrollPosition:UITableViewScrollPositionBottom animated:NO];
        report(chrome, mode);
        if ([args containsObject:@"verify"] && ([mode isEqualToString:@"split"] || [mode isEqualToString:@"split2"])) {
            NSMutableArray<UITabBar *> *bars = [NSMutableArray array];
            for (UITabBar *bar in systemBarsIn(chrome.tabs.bar)) if (!bar.hidden) [bars addObject:bar];
            [bars sortUsingComparator:^NSComparisonResult(UITabBar *a, UITabBar *b) {
                return [@(a.frame.origin.x) compare:@(b.frame.origin.x)];
            }];
            CGFloat apartWidth = [mode isEqualToString:@"split2"] ? 166 : 104;
            if (bars.count != 2 || bars[1].frame.size.width != apartWidth
                || CGRectGetMaxX(bars[0].frame) - CGRectGetMinX(bars[1].frame) != 30
                || CGRectGetMaxX(bars[1].frame) != chrome.tabs.bar.bounds.size.width) {
                NSLog(@"[harness] FAIL %@ expanded split frames: %@", mode, [bars valueForKey:@"frame"]);
                exit(1);
            }
            NSLog(@"[harness] PASS %@ expanded split geometry", mode);
            exit(0);
        }
    });
}

@end

int main(int argc, char *argv[]) {
    sgJam = argc > 1 && strcmp(argv[1], "jam") == 0;
    sgColorful = argc > 1 && (strcmp(argv[1], "fade") == 0 || strcmp(argv[1], "navsettings") == 0 || strcmp(argv[1], "glass") == 0);
    sgGlyphs = argc > 1 && (strcmp(argv[1], "glyphs") == 0 || strcmp(argv[1], "symbols") == 0);
    sgSwiftIcons = sgGlyphs && argc > 2 && strcmp(argv[2], "swift") == 0;
    sgSearch = argc > 1 && strcmp(argv[1], "search") == 0;
    Class glyphView = objc_allocateClassPair(SGHarnessGlyphView.class, "SPTEncoreIconView", 0);
    class_addIvar(glyphView, "icon", sizeof(void *), __builtin_ctz(sizeof(void *)), sgSwiftIcons ? "" : "@");
    objc_registerClassPair(glyphView);
    @autoreleasepool { return UIApplicationMain(argc, argv, nil, NSStringFromClass(SGHarnessApp.class)); }
}
