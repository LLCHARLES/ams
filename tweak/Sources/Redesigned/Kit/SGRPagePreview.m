// The live preview card of the redesign's page settings (SGRPagePreview.h).
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Settings/SGPageStyle.h"
#import "Shared/Player/SGLastTrack.h"
#import "SGRTokens.h"
#import "SGRPalette.h"
#import "SGRPagePreview.h"

// The card sits at the inset of the page's rows, rounded as the Player and Lyrics pages' cards are, and frames the
// mock page in a bezel of the card's color, so the mock's black reads as a screen on the settings page's black.
static const CGFloat kCardRadius = 26, kBezel = 6;
// The mock page's height at the default text size: room for a page's header and three or four sections under it.
static const CGFloat kPageHeight = 360;
// Between two parts shown; and the fade over the page's foot, where the page runs on past the card.
static const CGFloat kPartGap = 10, kFadeHeight = 40;
// A part scrolled into sight comes to rest this far down the page, as a share of its height.
static const CGFloat kRevealAt = 0.25;
// How far down the page the top tint reaches before it has faded into the field.
static const CGFloat kTintHeight = 180;
// The largest the mock's text grows, half again its size: past it the card would outgrow an iPhone's screen.
// The page's note under the card and VoiceOver's reading of it carry the larger sizes.
static const CGFloat kTextScaleCap = 1.5;
// The tab bar: a capsule over the page's foot, its glyphs, and the inset of the lit tab's selection in it.
static const CGFloat kTabBarHeight = 36, kTabBarInset = 10, kTabGlyph = 17, kTabSelectionInset = 3;
// Over a tab bar the page's content ends this far above it, faded out over the short fade above that, with the
// field between: nothing in sight runs into the bar.
static const CGFloat kTabBarClearance = 8, kTabBarFade = 12;
// The avatar's glyph, as a share of its circle.
static const CGFloat kAvatarGlyphShare = 0.55;
// Between the card and the note under it, as on the Lyrics page.
static const CGFloat kNoteGap = 14;
// The size symbols are drawn at before they are fitted to their frames: no frame in a mock is larger, so none is
// enlarged and blurred.
static const CGFloat kSymbolPoints = 28;

const CGFloat SGRPagePreviewMargin = 12;

// Spotify's category card colors: every mock's covers and cards are drawn in them.
static const NSInteger kPalette[] = {0xE13300, 0x1E3264, 0x8D67AB, 0xE8115B, 0x148A08, 0xBC5900, 0x477D95, 0x503750};
static const NSUInteger kPaletteCount = sizeof(kPalette) / sizeof(kPalette[0]);

#pragma mark - what a mock is drawn with

@interface SGRPreviewBarView : UIView
@end

@implementation SGRPreviewBarView
- (void)layoutSubviews {
    [super layoutSubviews];
    self.layer.cornerRadius = MIN(self.bounds.size.width, self.bounds.size.height) / 2;
}
@end

@interface SGRPreviewGradientView : UIView
@end

@implementation SGRPreviewGradientView
+ (Class)layerClass {
    return CAGradientLayer.class;
}
@end

static void setGradient(UIView *view, NSArray<UIColor *> *colors) {
    NSMutableArray *cgColors = [NSMutableArray arrayWithCapacity:colors.count];
    for (UIColor *color in colors) [cgColors addObject:(id)color.CGColor];
    ((CAGradientLayer *)view.layer).colors = cgColors;
}

UIColor *SGRPreviewColor(NSUInteger index) {
    return SGColorRGB(kPalette[index % kPaletteCount]);
}

UIImage *SGRPreviewArt(NSUInteger index) {
    // Drawn once a color and kept: a page's mock shows the same few again and again.
    static NSMutableDictionary<NSNumber *, UIImage *> *art;
    if (!art) art = [NSMutableDictionary dictionary];
    NSNumber *key = @(index % kPaletteCount);
    UIImage *image = art[key];
    if (!image) {
        image = SGPlaceholderArtwork(SGRPreviewColor(key.unsignedIntegerValue));
        art[key] = image;
    }
    return image;
}

UIImageView *SGRPreviewCover(NSUInteger index) {
    UIImageView *view = [[UIImageView alloc] initWithImage:SGRPreviewArt(index)];
    view.contentMode = UIViewContentModeScaleAspectFill;
    view.clipsToBounds = YES;
    view.layer.cornerCurve = kCACornerCurveContinuous;
    return view;
}

UIView *SGRPreviewBar(UIColor *color) {
    UIView *bar = [SGRPreviewBarView new];
    bar.backgroundColor = color;
    return bar;
}

UIView *SGRPreviewGlass(void) {
    UIView *glass = [UIView new];
    glass.backgroundColor = SGRSolidGlassFill();
    glass.clipsToBounds = YES;
    glass.layer.cornerCurve = kCACornerCurveContinuous;
    return glass;
}

UIImageView *SGRPreviewSymbol(NSString *name, UIColor *tint) {
    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:kSymbolPoints weight:UIImageSymbolWeightSemibold];
    UIImageView *view = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:name withConfiguration:config]];
    view.contentMode = UIViewContentModeScaleAspectFit;
    view.tintColor = tint;
    return view;
}

UIImageView *SGRPreviewAddSymbol(UIView *view, NSString *name, UIColor *tint) {
    UIImageView *glyph = SGRPreviewSymbol(name, tint);
    [view addSubview:glyph];
    return glyph;
}

void SGRPreviewCenter(UIView *view, CGRect bounds, CGFloat side) {
    view.frame = CGRectMake(CGRectGetMidX(bounds) - side / 2, CGRectGetMidY(bounds) - side / 2, side, side);
}

// A glass circle with the person glyph in its middle, laid out whenever its frame changes.
@interface SGRPreviewAvatarView : UIView
@end

@implementation SGRPreviewAvatarView {
    UIImageView *_glyph;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.backgroundColor = SGRSolidGlassFill();
    _glyph = SGRPreviewSymbol(@"person.fill", SGRSecondary());
    [self addSubview:_glyph];
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat side = self.bounds.size.width;
    self.layer.cornerRadius = side / 2;
    CGFloat glyph = side * kAvatarGlyphShare;
    _glyph.frame = CGRectMake((side - glyph) / 2, (side - glyph) / 2, glyph, glyph);
}

@end

UIView *SGRPreviewAvatar(void) {
    return [SGRPreviewAvatarView new];
}

UIView *SGRPreviewGradient(NSArray<UIColor *> *colors, CGPoint start, CGPoint end) {
    UIView *view = [SGRPreviewGradientView new];
    CAGradientLayer *layer = (CAGradientLayer *)view.layer;
    layer.startPoint = start;
    layer.endPoint = end;
    setGradient(view, colors);
    view.userInteractionEnabled = NO;
    return view;
}

UILabel *SGRPreviewLabel(NSString *text, UIColor *color) {
    UILabel *label = [UILabel new];
    label.text = text;
    label.textColor = color;
    label.lineBreakMode = NSLineBreakByTruncatingTail;
    return label;
}

UIFont *SGRPreviewFont(CGFloat size, UIFontWeight weight, CGFloat unit) {
    return [UIFont systemFontOfSize:size * unit weight:weight];
}

// In the language the names are in (SGL's), not the region's.
NSString *SGRPreviewList(NSArray<NSString *> *names) {
    static NSListFormatter *formatter;
    if (!formatter) {
        formatter = [NSListFormatter new];
        formatter.locale = [NSLocale localeWithLocaleIdentifier:SGLanguage()];
    }
    return [formatter stringFromItems:names];
}

#pragma mark - the card

@interface SGRPreviewPart : UIView
@property (nonatomic, copy) CGFloat (^stack)(UIView *part, CGFloat width, CGFloat unit);
@property (nonatomic, copy) CGRect (^over)(UIView *overlay, CGSize page, CGFloat unit);
@property (nonatomic) BOOL shown;
@property (nonatomic) BOOL mirrored;   // its views stand where mirrorSubviews put them
@end

@implementation SGRPreviewPart
@end

// A row whose views keep their order right to left, as the real header's controls do (SGRHeaderInfo.m): it is
// mirrored as a whole, and what it holds is left where it was laid out.
@interface SGRPreviewFixedRow : UIView
@end

@implementation SGRPreviewFixedRow
@end

static BOOL rightToLeft(UIView *view) {
    return view.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;
}

// Every view under `root` moved to the other side of the view it sits in, by its center, so a turned one keeps its
// turn; done twice, the views are back where they were. A label's and an image view's insides are UIKit's, and a
// fixed row's are left as they are.
static void mirrorSubviews(UIView *root) {
    CGFloat axis = 2 * CGRectGetMidX(root.bounds);
    for (UIView *view in root.subviews) {
        view.center = CGPointMake(axis - view.center.x, view.center.y);
        if ([view isKindOfClass:UILabel.class] || [view isKindOfClass:UIImageView.class] || [view isKindOfClass:SGRPreviewFixedRow.class]) continue;
        mirrorSubviews(view);
    }
}

@interface SGRPagePreview ()
// The page tells the card as it scrolls: a change noted while out of sight is drawn once it is back in sight.
- (void)drawIfStaleInSight;
@end

@implementation SGRPagePreview {
    UIView *_page;
    UIView *_stack;   // the parts, its bounds' origin where the page is scrolled to
    UIView *_tint, *_fade;
    NSMutableArray<SGRPreviewPart *> *_parts, *_overlays;
    __weak UIView *_revealed;
    __weak UIView *_tabBar;
    id _drawn;
    BOOL _hasDrawn;
    BOOL _stale;   // the settings changed while the card was out of sight, and are not drawn yet
    id<NSObject> _observer;
}

- (instancetype)initWithLabel:(NSString *)label {
    if (!(self = [super initWithFrame:CGRectZero])) return nil;
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    self.backgroundColor = SGCardBackground();
    self.layer.cornerRadius = kCardRadius;
    self.layer.cornerCurve = kCACornerCurveContinuous;
    self.clipsToBounds = YES;
    self.userInteractionEnabled = NO;
    self.isAccessibilityElement = YES;
    self.accessibilityTraits = UIAccessibilityTraitImage;
    self.accessibilityLabel = label;
    _page = [UIView new];
    _page.layer.cornerRadius = kCardRadius - kBezel;
    _page.layer.cornerCurve = kCACornerCurveContinuous;
    _page.clipsToBounds = YES;
    [self addSubview:_page];
    _stack = [UIView new];
    [_page addSubview:_stack];
    _tint = SGRPreviewGradient(@[], CGPointMake(0.5, 0), CGPointMake(0.5, 1));
    _tint.alpha = 0;
    [_stack addSubview:_tint];
    _fade = SGRPreviewGradient(@[], CGPointMake(0.5, 0), CGPointMake(0.5, 1));
    [_page addSubview:_fade];
    _parts = [NSMutableArray array];
    _overlays = [NSMutableArray array];
    self.fieldColor = UIColor.blackColor;
    return self;
}

- (void)dealloc {
    if (_observer) [NSNotificationCenter.defaultCenter removeObserver:_observer];
}

// At once, inside a change's animation too: the gradients that end in the field (the foot's fade, a header's
// dissolve) take their colors at once, and the page under them goes with them.
- (void)setFieldColor:(UIColor *)color {
    _fieldColor = color;
    [UIView performWithoutAnimation:^{ self->_page.backgroundColor = color; }];
    setGradient(_fade, @[[color colorWithAlphaComponent:0], color]);
}

// The colors change at once and the wash fades in or out with the layout; a tint taken away keeps its colors to fade with.
- (void)setTopTint:(UIColor *)tint {
    _topTint = tint;
    if (tint) setGradient(_tint, @[tint, [tint colorWithAlphaComponent:0]]);
}

- (CGFloat)unit {
    CGFloat scale = [UIFontMetrics.defaultMetrics scaledValueForValue:1 compatibleWithTraitCollection:self.traitCollection];
    return MIN(scale, kTextScaleCap);
}

- (CGFloat)preferredHeight {
    return round(kPageHeight * self.unit) + 2 * kBezel;
}

- (UIView *)addPartWithLayout:(CGFloat (^)(UIView *part, CGFloat width, CGFloat unit))layout {
    SGRPreviewPart *part = [SGRPreviewPart new];
    part.stack = layout;
    part.shown = YES;
    [_stack addSubview:part];
    [_parts addObject:part];
    return part;
}

- (UIView *)addOverlayWithLayout:(CGRect (^)(UIView *overlay, CGSize page, CGFloat unit))layout {
    SGRPreviewPart *overlay = [SGRPreviewPart new];
    overlay.over = layout;
    overlay.shown = YES;
    [_page addSubview:overlay];
    [_overlays addObject:overlay];
    return overlay;
}

- (void)setPart:(UIView *)part shown:(BOOL)shown {
    ((SGRPreviewPart *)part).shown = shown;
}

- (void)revealPart:(UIView *)part {
    _revealed = part;
}

// The bar of the redesign's tabs, the one the page belongs to lit: its glyph in the accent color over a selection,
// so a dark accent stays in sight on the glass.
- (void)addTabBarShowing:(SGRPreviewTab)tab {
    NSArray<NSString *> *glyphs = @[@"house.fill", @"magnifyingglass", @"books.vertical.fill"];
    UIView *selection = SGRPreviewGlass();
    NSMutableArray<UIImageView *> *tabs = [NSMutableArray array];
    for (NSString *glyph in glyphs) [tabs addObject:SGRPreviewSymbol(glyph, SGRPrimary())];
    UIView *bar = [self addOverlayWithLayout:^CGRect(UIView *overlay, CGSize page, CGFloat unit) {
        CGFloat height = kTabBarHeight * unit, width = page.width - 2 * kTabBarInset;
        overlay.layer.cornerRadius = height / 2;
        CGFloat slot = width / tabs.count, glyph = kTabGlyph * unit;
        [tabs enumerateObjectsUsingBlock:^(UIImageView *view, NSUInteger i, BOOL *stop) {
            view.frame = CGRectMake(slot * i + (slot - glyph) / 2, (height - glyph) / 2, glyph, glyph);
            view.tintColor = i == tab ? SGRAccent() : SGRPrimary();
        }];
        selection.frame = CGRectInset(CGRectMake(slot * tab, 0, slot, height), kTabSelectionInset, kTabSelectionInset);
        selection.layer.cornerRadius = selection.frame.size.height / 2;
        return CGRectMake(kTabBarInset, page.height - kTabBarInset - height, width, height);
    }];
    // Opaque: a plain view cannot blur what passes under it as the glass does, and the page would show through.
    bar.backgroundColor = SGRElevated(SGRNeutralField());
    bar.clipsToBounds = YES;
    bar.layer.cornerCurve = kCACornerCurveContinuous;
    [bar addSubview:selection];
    for (UIImageView *view in tabs) [bar addSubview:view];
    _tabBar = bar;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    _page.frame = CGRectInset(self.bounds, kBezel, kBezel);
    if (!_hasDrawn) [self draw:self.state() animated:NO fromTop:YES];
    else [self layoutPageRevealing:nil];
}

// A part or an overlay as its layout left it, mirrored right to left.
static void orient(SGRPreviewPart *part, BOOL rtl) {
    if (rtl) mirrorSubviews(part);
    part.mirrored = rtl;
}

// The overlays; the parts top down, a hidden one faded where it is with the next taking its place; the page scrolled
// to `focus` when that is out of sight, and kept within its length, its content ending at the foot (over a tab bar,
// its clearance); then what VoiceOver reads: the names of the parts and overlays shown. Each lays out from the left,
// from where its last layout left its views (put back first if they were mirrored), and right to left it is mirrored.
- (void)layoutPageRevealing:(SGRPreviewPart *)focus {
    CGSize size = _page.bounds.size;
    if (size.width <= 0) return;
    CGFloat unit = self.unit, y = 0, end = 0;
    BOOL rtl = rightToLeft(self);
    NSMutableArray<NSString *> *names = [NSMutableArray array], *overlayNames = [NSMutableArray array];
    for (SGRPreviewPart *overlay in _overlays) {
        if (overlay.mirrored) mirrorSubviews(overlay);
        CGRect frame = overlay.over(overlay, size, unit);
        if (rtl) frame.origin.x = size.width - CGRectGetMaxX(frame);
        overlay.frame = frame;
        orient(overlay, rtl);
        overlay.alpha = overlay.shown ? 1 : 0;
        if (overlay.shown && overlay.accessibilityLabel.length) [overlayNames addObject:overlay.accessibilityLabel];
    }
    CGFloat foot = _tabBar ? CGRectGetMinY(_tabBar.frame) - kTabBarClearance * unit : size.height;
    CGFloat fade = (_tabBar ? kTabBarFade : kFadeHeight) * unit;
    for (SGRPreviewPart *part in _parts) {
        if (part.mirrored) mirrorSubviews(part);
        CGFloat height = part.stack(part, size.width, unit);
        part.frame = CGRectMake(0, y, size.width, height);
        orient(part, rtl);
        part.alpha = part.shown ? 1 : 0;
        if (!part.shown) continue;
        end = y + height;
        y = end + kPartGap * unit;
        if (part.accessibilityLabel.length) [names addObject:part.accessibilityLabel];
    }
    _tint.frame = CGRectMake(0, 0, size.width, kTintHeight * unit);
    _tint.alpha = _topTint != nil;
    CGFloat offset = _stack.bounds.origin.y;
    if (focus) {
        CGFloat top = CGRectGetMinY(focus.frame), bottom = focus.shown ? CGRectGetMaxY(focus.frame) : top;
        if (top < offset || bottom > offset + foot - fade) offset = top - size.height * kRevealAt;
    }
    offset = MIN(MAX(0, offset), MAX(0, end + fade - foot));
    _stack.bounds = CGRectMake(0, offset, size.width, size.height);
    _stack.center = CGPointMake(size.width / 2, size.height / 2);
    // The fade, then the field down to the page's bottom.
    CGFloat fadeTop = foot - fade, fadeHeight = size.height - fadeTop;
    _fade.frame = CGRectMake(0, fadeTop, size.width, fadeHeight);
    ((CAGradientLayer *)_fade.layer).locations = @[@0, @(fade / fadeHeight)];
    [names addObjectsFromArray:overlayNames];
    self.accessibilityValue = SGRPreviewList(names);
}

// From the top of the page, or following the change: the topmost part that came or went, or that `apply` revealed.
- (void)draw:(id)state animated:(BOOL)animated fromTop:(BOOL)fromTop {
    _drawn = state;
    _hasDrawn = YES;
    NSMutableArray<NSNumber *> *before = [NSMutableArray arrayWithCapacity:_parts.count];
    for (SGRPreviewPart *part in _parts) [before addObject:@(part.shown)];
    void (^change)(void) = ^{
        self->_revealed = nil;
        self.apply(self, state);
        SGRPreviewPart *focus = nil;
        for (NSUInteger i = 0; i < self->_parts.count && !focus && !fromTop; i++) {
            SGRPreviewPart *part = self->_parts[i];
            if (part.shown != before[i].boolValue || part == self->_revealed) focus = part;
        }
        if (fromTop) self->_stack.bounds = (CGRect){CGPointZero, self->_stack.bounds.size};
        [self layoutPageRevealing:focus];
    };
    if (animated) SGRAnimate(SGRMotionLayout, change, nil);
    else [UIView performWithoutAnimation:change];
}

// Some part of the card is inside its window's bounds: scrolled away with the page's rows, it is not.
- (BOOL)inSight {
    UIWindow *window = self.window;
    return window && CGRectIntersectsRect([self convertRect:self.bounds toView:nil], window.bounds);
}

// A change in sight is read and drawn with the layout motion. Out of sight it is only noted, and drawn at once when
// the card comes back into sight; one that reaches a card already out of its window is dropped, as coming back into
// a window draws the card afresh.
- (void)settingsChanged {
    if (!self.window) return;
    if (![self inSight]) {
        _stale = YES;
        return;
    }
    id state = self.state();
    if (_hasDrawn && [state isEqual:_drawn]) return;
    [self draw:state animated:YES fromTop:NO];
}

- (void)drawIfStaleInSight {
    if (!_stale || !self.window || ![self inSight]) return;
    _stale = NO;
    id state = self.state();
    if (![state isEqual:_drawn]) [self draw:state animated:NO fromTop:NO];
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (!self.window) {
        if (_observer) [NSNotificationCenter.defaultCenter removeObserver:_observer];
        _observer = nil;
        return;
    }
    _stale = NO;
    if (!_observer) {
        __weak SGRPagePreview *weakSelf = self;
        // Posted on the writing thread, which a main-queue observer would leave waiting on main.
        _observer = [NSNotificationCenter.defaultCenter addObserverForName:NSUserDefaultsDidChangeNotification object:nil queue:nil
                                                                usingBlock:^(NSNotification *note) {
            dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf settingsChanged]; });
        }];
    }
    // Whatever changed while the card was away, the accent color among it, drawn at once.
    [self draw:self.state() animated:NO fromTop:YES];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previous {
    [super traitCollectionDidChange:previous];
    if (![previous.preferredContentSizeCategory isEqualToString:self.traitCollection.preferredContentSizeCategory]) [self setNeedsLayout];
}

@end

#pragma mark - the parts the pages share

// The title row: the large title, on Home's glass pill with its chevron while that look is on, the avatar, and a
// hairline under the row.
const CGFloat SGRPreviewTitleTop = 8, SGRPreviewTitleRowHeight = 34, SGRPreviewTitleFontSize = 22, SGRPreviewAvatarSide = 26;
static const CGFloat kPillPad = 10, kPillHeight = 32, kChevron = 10, kChevronGap = 5;

@interface SGRPreviewTitle ()
@property (nonatomic, weak) UIView *part;
@end

@implementation SGRPreviewTitle
@end

SGRPreviewTitle *SGRPreviewAddTitle(SGRPagePreview *card, NSString *text) {
    SGRPreviewTitle *title = [SGRPreviewTitle new];
    UILabel *label = SGRPreviewLabel(text, SGRPrimary());
    UIView *pill = SGRPreviewGlass(), *avatar = SGRPreviewAvatar(), *edge = [UIView new];
    UIImageView *chevron = SGRPreviewSymbol(@"chevron.down", SGRSecondary());
    edge.backgroundColor = SGRHairline();
    // The part keeps the title's settings; they keep the part weakly.
    UIView *part = [card addPartWithLayout:^CGFloat(UIView *view, CGFloat width, CGFloat unit) {
        SGRPreviewTitle *owner = title;
        BOOL inPill = owner.inPill;
        CGFloat top = SGRPreviewTitleTop * unit, row = SGRPreviewTitleRowHeight * unit, middle = top + row / 2, side = SGRPreviewAvatarSide * unit;
        avatar.frame = CGRectMake(width - SGRPagePreviewMargin - side, middle - side / 2, side, side);
        label.font = SGRPreviewFont(SGRPreviewTitleFontSize, UIFontWeightBold, unit);
        CGFloat pad = inPill ? kPillPad * unit : 0, chevronSide = kChevron * unit, gap = kChevronGap * unit;
        CGFloat room = CGRectGetMinX(avatar.frame) - SGRPagePreviewMargin - 2 * pad - chevronSide - 2 * gap;
        CGFloat textWidth = MIN(room, ceil([label sizeThatFits:CGSizeMake(CGFLOAT_MAX, row)].width));
        label.frame = CGRectMake(SGRPagePreviewMargin + pad, top, textWidth, row);
        chevron.frame = CGRectMake(CGRectGetMaxX(label.frame) + gap, middle - chevronSide / 2, chevronSide, chevronSide);
        chevron.alpha = inPill;
        CGFloat pillHeight = kPillHeight * unit;
        pill.frame = CGRectMake(SGRPagePreviewMargin, middle - pillHeight / 2, CGRectGetMaxX(chevron.frame) + pad - SGRPagePreviewMargin, pillHeight);
        pill.layer.cornerRadius = pillHeight / 2;
        pill.alpha = inPill;
        CGFloat hairline = 1 / UIScreen.mainScreen.scale;
        edge.frame = CGRectMake(0, top + row - hairline, width, hairline);
        edge.alpha = owner.hardEdge;
        return top + row;
    }];
    for (UIView *view in @[pill, label, chevron, avatar, edge]) [part addSubview:view];
    title.part = part;
    return title;
}

// The header: the artwork cut to its height and dissolving into the field from partway down, the title, detail and
// length bars centered under it, then shuffle, the white Play and the trailing control.
static const CGFloat kArtworkHeight = 150, kDissolveFrom = 0.45;
static const CGFloat kTitleBar = 11, kDetailBar = 7, kLengthBar = 6, kTextGap = 6, kControlsGap = 12;
static const CGFloat kTitleShare = 0.46, kDetailShare = 0.28, kLengthShare = 0.2;   // of the page's width, centered
static const CGFloat kControl = 30, kPlayWidth = 88, kControlSpacing = 12, kControlGlyph = 13;
static const CGFloat kBadge = 24, kBadgeGlyph = 11;
// The logo takes the title's width and this many times its bar's height, centered on it, and the detail under it
// moves down this much more, clear of the logo's foot.
static const CGFloat kLogoHeightInBars = 3, kLogoDetailGap = 4;

@interface SGRPreviewHeader ()
@property (nonatomic, weak) UIView *part;
@property (nonatomic, weak) SGRPagePreview *card;
@property (nonatomic, strong) UIImageView *artwork;
@property (nonatomic, strong) UIView *title, *badge, *logo, *dissolve;
@property (nonatomic, strong) UIView *face, *about;
@property (nonatomic) BOOL hideDetails;
@end

@implementation SGRPreviewHeader

- (void)setCreatorLine:(BOOL)line picture:(BOOL)picture description:(BOOL)description {
    if (!_face) {
        _face = SGRPreviewSymbol(@"person.crop.circle.fill", SGRSecondary());
        _face.accessibilityIdentifier = @"retrine.preview.header.creatorPicture";
        _about = SGRPreviewBar(SGRTertiary());
        [self.part addSubview:_face];
        [self.part addSubview:_about];
    }
    _hideDetails = !line;
    _face.hidden = !line || !picture;
    _about.hidden = !description;
}

// The artwork, and the field it dissolves into with the page's, from the same cover.
- (void)setCover:(NSUInteger)cover {
    _cover = cover;
    UIColor *field = SGRFieldColorFor(SGRPreviewColor(cover));
    self.card.fieldColor = field;
    setGradient(self.dissolve, @[[field colorWithAlphaComponent:0], field]);
    self.artwork.image = SGRPreviewArt(cover);
}

- (void)setShowsLogo:(BOOL)showsLogo {
    _showsLogo = showsLogo;
    self.logo.alpha = showsLogo;
    self.title.alpha = !showsLogo;
}

@end

static UIView *centered(UIView *view, CGFloat width, CGFloat y, CGFloat share, CGFloat height) {
    view.frame = CGRectMake(width * (1 - share) / 2, y, width * share, height);
    return view;
}

SGRPreviewHeader *SGRPreviewAddHeader(SGRPagePreview *card, NSUInteger cover, NSString *badgeSymbol, NSString *trailingSymbol) {
    SGRPreviewHeader *header = [SGRPreviewHeader new];
    header.fullCover = YES;
    UIImageView *artwork = SGRPreviewCover(cover);
    artwork.accessibilityIdentifier = @"retrine.preview.header.artwork";
    UIView *dissolve = SGRPreviewGradient(@[], CGPointMake(0.5, 0), CGPointMake(0.5, 1));
    UIView *badge = SGRPreviewGlass();
    UIImageView *badgeGlyph = SGRPreviewAddSymbol(badge, badgeSymbol, SGRPrimary());
    badge.alpha = 0;
    UIView *title = SGRPreviewBar(SGRPrimary()), *detail = SGRPreviewBar(SGRSecondary()), *length = SGRPreviewBar(SGRTertiary());
    detail.accessibilityIdentifier = @"retrine.preview.header.detail";
    UIImageView *logo = SGRPreviewSymbol(@"signature", SGRPrimary());
    logo.alpha = 0;
    UIView *shuffle = SGRPreviewGlass(), *trailing = SGRPreviewGlass(), *play = SGRPreviewBar(UIColor.whiteColor);
    UIView *controls = [SGRPreviewFixedRow new];
    controls.accessibilityIdentifier = @"retrine.preview.header.controls";
    for (UIView *view in @[shuffle, play, trailing]) [controls addSubview:view];
    UIImageView *shuffleGlyph = SGRPreviewAddSymbol(shuffle, @"shuffle", SGRPrimary());
    UIImageView *trailingGlyph = SGRPreviewAddSymbol(trailing, trailingSymbol, SGRPrimary());
    UIImageView *playGlyph = SGRPreviewAddSymbol(play, @"play.fill", UIColor.blackColor);
    UIView *part = [card addPartWithLayout:^CGFloat(UIView *view, CGFloat width, CGFloat unit) {
        CGFloat artworkHeight = round(kArtworkHeight * unit);
        CGFloat coverSide = MIN(artworkHeight, width - 2 * SGRPagePreviewMargin);
        artwork.frame = header.fullCover ? CGRectMake(0, 0, width, artworkHeight)
            : CGRectMake((width - coverSide) / 2, 0, coverSide, coverSide);
        artwork.layer.cornerRadius = header.fullCover ? 0 : 8 * unit;
        dissolve.alpha = header.fullCover;
        dissolve.frame = CGRectMake(0, artworkHeight * kDissolveFrom, width, artworkHeight * (1 - kDissolveFrom) + 1);
        CGFloat badgeSide = kBadge * unit;
        badge.frame = CGRectMake(SGRPagePreviewMargin, artworkHeight * kDissolveFrom - badgeSide, badgeSide, badgeSide);
        badge.layer.cornerRadius = badgeSide / 2;
        SGRPreviewCenter(badgeGlyph, badge.bounds, kBadgeGlyph * unit);
        CGFloat y = CGRectGetMaxY(centered(title, width, artworkHeight, kTitleShare, kTitleBar * unit).frame) + kTextGap * unit;
        if (header.showsLogo) y += kLogoDetailGap * unit;
        CGFloat logoHeight = kTitleBar * kLogoHeightInBars * unit;
        centered(logo, width, CGRectGetMidY(title.frame) - logoHeight / 2, kTitleShare, logoHeight);
        detail.hidden = length.hidden = header.hideDetails;
        if (!header.hideDetails) {
            CGFloat face = header.face && !header.face.hidden ? kDetailBar * unit : 0;
            CGFloat lead = face ? face + kTextGap * unit : 0;
            centered(detail, width, y, kDetailShare, kDetailBar * unit);
            detail.frame = CGRectOffset(detail.frame, lead / 2, 0);
            header.face.frame = CGRectMake(CGRectGetMinX(detail.frame) - lead, y, face, face);
            y += (kDetailBar + kTextGap) * unit;
            y = CGRectGetMaxY(centered(length, width, y, kLengthShare, kLengthBar * unit).frame) + kControlsGap * unit;
        }
        CGFloat side = kControl * unit, playWidth = kPlayWidth * unit, spacing = kControlSpacing * unit;
        CGFloat x = (width - 2 * side - playWidth - 2 * spacing) / 2;
        controls.frame = CGRectMake(0, y, width, side);
        shuffle.frame = CGRectMake(x, 0, side, side);
        play.frame = CGRectMake(CGRectGetMaxX(shuffle.frame) + spacing, 0, playWidth, side);
        trailing.frame = CGRectMake(CGRectGetMaxX(play.frame) + spacing, 0, side, side);
        shuffle.layer.cornerRadius = trailing.layer.cornerRadius = side / 2;
        SGRPreviewCenter(shuffleGlyph, shuffle.bounds, kControlGlyph * unit);
        SGRPreviewCenter(playGlyph, play.bounds, kControlGlyph * unit);
        SGRPreviewCenter(trailingGlyph, trailing.bounds, kControlGlyph * unit);
        y += side;
        if (header.about && !header.about.hidden)
            y = CGRectGetMaxY(centered(header.about, width, y + kControlsGap * unit, kTitleShare, kDetailBar * unit).frame);
        return y;
    }];
    for (UIView *view in @[artwork, dissolve, badge, title, logo, detail, length, controls]) [part addSubview:view];
    header.part = part;
    header.card = card;
    header.artwork = artwork;
    header.title = title;
    header.badge = badge;
    header.logo = logo;
    header.dissolve = dissolve;
    header.cover = cover;
    return header;
}

// The track rows: a cover or the track's number, the title over the artist, a word before the ⋯, a hairline under
// every row but the last from the text's leading edge.
static const CGFloat kTrackRow = 38, kTrackArt = 28, kTrackArtRadius = 4, kTrackTextGap = 10, kTrackLineGap = 2;
static const CGFloat kTrackTitle = 8, kTrackArtist = 6, kTrackGlyph = 14, kTrackNumber = 12, kTrackWord = 10;
static const CGFloat kTrackTitleShare = 0.42, kTrackArtistShare = 0.26;   // of the room for the text
// The trailing word's white, a little under the numbers' full white, legible on a tinted field.
static const CGFloat kTrackWordAlpha = 0.85;

@interface SGRPreviewTracks ()
@property (nonatomic, weak) UIView *part;
@end

@implementation SGRPreviewTracks
@end

SGRPreviewTracks *SGRPreviewAddTracks(SGRPagePreview *card, NSUInteger count, BOOL artwork, NSUInteger firstCover) {
    SGRPreviewTracks *tracks = [SGRPreviewTracks new];
    tracks.showsArtists = YES;
    NSMutableArray<NSArray<UIView *> *> *rows = [NSMutableArray array];
    NSNumberFormatter *numbers = [NSNumberFormatter new];
    for (NSUInteger i = 0; i < count; i++) {
        UIView *lead;
        if (artwork) {
            lead = SGRPreviewCover(firstCover + i);
        } else {
            UILabel *number = SGRPreviewLabel([numbers stringFromNumber:@(i + 1)], SGRPrimary());
            number.textAlignment = NSTextAlignmentCenter;
            lead = number;
        }
        UILabel *word = SGRPreviewLabel(nil, [SGRPrimary() colorWithAlphaComponent:kTrackWordAlpha]);
        UIView *line = [UIView new];
        line.backgroundColor = SGRHairline();
        [rows addObject:@[lead, SGRPreviewBar(SGRPrimary()), SGRPreviewBar(SGRSecondary()), word, SGRPreviewSymbol(@"ellipsis", SGRTertiary()), line]];
    }
    UIView *part = [card addPartWithLayout:^CGFloat(UIView *view, CGFloat width, CGFloat unit) {
        SGRPreviewTracks *owner = tracks;
        CGFloat row = kTrackRow * unit, art = kTrackArt * unit, textX = SGRPagePreviewMargin + art + kTrackTextGap * unit;
        CGFloat glyph = kTrackGlyph * unit, hairline = 1 / UIScreen.mainScreen.scale, room = width - textX;
        [rows enumerateObjectsUsingBlock:^(NSArray<UIView *> *views, NSUInteger i, BOOL *stop) {
            CGFloat y = i * row, middle = y + row / 2;
            views[0].frame = CGRectMake(SGRPagePreviewMargin, middle - art / 2, art, art);
            views[0].layer.cornerRadius = kTrackArtRadius * unit;
            if ([views[0] isKindOfClass:UILabel.class]) ((UILabel *)views[0]).font = SGRPreviewFont(kTrackNumber, UIFontWeightRegular, unit);
            // The playing track's title is in the accent color, as Spotify's green is.
            views[1].backgroundColor = i == 0 ? SGRAccent() : SGRPrimary();
            CGFloat titleY = owner.showsArtists ? middle - (kTrackTitle + kTrackLineGap) * unit : middle - kTrackTitle * unit / 2;
            views[1].frame = CGRectMake(textX, titleY, room * kTrackTitleShare, kTrackTitle * unit);
            views[2].frame = CGRectMake(textX, middle + kTrackLineGap * unit, room * kTrackArtistShare, kTrackArtist * unit);
            views[2].alpha = owner.showsArtists;
            views[4].frame = CGRectMake(width - SGRPagePreviewMargin - glyph, middle - glyph / 2, glyph, glyph);
            UILabel *word = (UILabel *)views[3];
            word.text = i < owner.trailing.count ? owner.trailing[i] : word.text;
            word.font = SGRPreviewFont(kTrackWord, UIFontWeightRegular, unit);
            // Against the ⋯, on its right right to left too once the row is mirrored.
            word.textAlignment = rightToLeft(view) ? NSTextAlignmentLeft : NSTextAlignmentRight;
            CGFloat wordX = textX + room * kTrackTitleShare + kTrackTextGap * unit;
            word.frame = CGRectMake(wordX, y, CGRectGetMinX(views[4].frame) - kTrackTextGap * unit - wordX, row);
            word.alpha = owner.trailing != nil;
            views[5].frame = CGRectMake(textX, y + row - hairline, room, hairline);
            views[5].alpha = i + 1 < rows.count;
        }];
        return rows.count * row;
    }];
    for (NSArray<UIView *> *views in rows) for (UIView *view in views) [part addSubview:view];
    tracks.part = part;
    return tracks;
}

static const CGFloat kParagraphLine = 7, kParagraphLeading = 6, kParagraphLastShare = 0.55;

UIView *SGRPreviewAddParagraph(SGRPagePreview *card, NSUInteger count) {
    NSMutableArray<UIView *> *lines = [NSMutableArray array];
    for (NSUInteger i = 0; i < count; i++) [lines addObject:SGRPreviewBar(SGRSecondary())];
    UIView *part = [card addPartWithLayout:^CGFloat(UIView *view, CGFloat width, CGFloat unit) {
        CGFloat line = kParagraphLine * unit, step = line + kParagraphLeading * unit, room = width - 2 * SGRPagePreviewMargin;
        [lines enumerateObjectsUsingBlock:^(UIView *bar, NSUInteger i, BOOL *stop) {
            bar.frame = CGRectMake(SGRPagePreviewMargin, i * step, i + 1 < lines.count ? room : room * kParagraphLastShare, line);
        }];
        return lines.count * step - kParagraphLeading * unit;
    }];
    for (UIView *bar in lines) [part addSubview:bar];
    return part;
}

// The top bar's two glass circles, and the menu hanging from the ⋯ under it, a share of the page wide.
static const CGFloat kTopButton = 26, kTopButtonInset = 8, kTopGlyph = 12;
static const CGFloat kMenuWidthShare = 0.42, kMenuGap = 6, kMenuRow = 22, kMenuPad = 4, kMenuGlyph = 11, kMenuRadius = 12;
static const CGFloat kMenuText = 11, kMenuBar = 6, kMenuBarShare = 0.4;

void SGRPreviewAddTopBar(SGRPagePreview *card) {
    UIView *back = SGRPreviewGlass(), *more = SGRPreviewGlass();
    UIImageView *backGlyph = SGRPreviewAddSymbol(back, @"chevron.left", SGRPrimary());
    // Pointing back, to the right right to left.
    backGlyph.image = backGlyph.image.imageFlippedForRightToLeftLayoutDirection;
    backGlyph.accessibilityIdentifier = @"retrine.preview.back";
    UIImageView *moreGlyph = SGRPreviewAddSymbol(more, @"ellipsis", SGRPrimary());
    UIView *overlay = [card addOverlayWithLayout:^CGRect(UIView *view, CGSize page, CGFloat unit) {
        CGFloat side = kTopButton * unit, inset = kTopButtonInset * unit;
        back.frame = CGRectMake(SGRPagePreviewMargin, inset, side, side);
        more.frame = CGRectMake(page.width - SGRPagePreviewMargin - side, inset, side, side);
        back.layer.cornerRadius = more.layer.cornerRadius = side / 2;
        SGRPreviewCenter(backGlyph, back.bounds, kTopGlyph * unit);
        SGRPreviewCenter(moreGlyph, more.bounds, kTopGlyph * unit);
        return (CGRect){CGPointZero, page};
    }];
    [overlay addSubview:back];
    [overlay addSubview:more];
}

@interface SGRPreviewMenu ()
@property (nonatomic, weak) UIView *overlay;
@property (nonatomic, strong) NSMutableArray<NSNumber *> *shown;
@property (nonatomic, strong) NSArray<NSArray<UIView *> *> *rows;
@end

@implementation SGRPreviewMenu
- (void)setRow:(NSUInteger)row shown:(BOOL)shown {
    self.shown[row] = @(shown);
}
- (void)setRow:(NSUInteger)row word:(NSString *)word {
    UIView *text = self.rows[row][1];
    if ([text isKindOfClass:UILabel.class]) ((UILabel *)text).text = word;
}
@end

SGRPreviewMenu *SGRPreviewAddMenu(SGRPagePreview *card, NSArray<NSString *> *symbols, NSArray *words) {
    SGRPreviewMenu *menu = [SGRPreviewMenu new];
    menu.shown = [NSMutableArray array];
    NSMutableArray<NSArray<UIView *> *> *rows = [NSMutableArray array];
    [symbols enumerateObjectsUsingBlock:^(NSString *symbol, NSUInteger i, BOOL *stop) {
        id word = i < words.count ? words[i] : nil;
        UIView *text = [word isKindOfClass:NSString.class] ? SGRPreviewLabel(word, SGRPrimary()) : SGRPreviewBar(SGRSecondary());
        [rows addObject:@[SGRPreviewSymbol(symbol, SGRPrimary()), text]];
        [menu.shown addObject:@YES];
    }];
    UIView *overlay = [card addOverlayWithLayout:^CGRect(UIView *view, CGSize page, CGFloat unit) {
        CGFloat width = round(page.width * kMenuWidthShare), row = kMenuRow * unit, pad = kMenuPad * unit, y = pad;
        CGFloat glyph = kMenuGlyph * unit, textX = 2 * pad + 2 * glyph;
        view.layer.cornerRadius = kMenuRadius * unit;
        for (NSUInteger i = 0; i < rows.count; i++) {
            BOOL shown = menu.shown[i].boolValue;
            UIView *symbol = rows[i][0], *text = rows[i][1];
            symbol.frame = CGRectMake(2 * pad, y + (row - glyph) / 2, glyph, glyph);
            if ([text isKindOfClass:UILabel.class]) {
                ((UILabel *)text).font = SGRPreviewFont(kMenuText, UIFontWeightRegular, unit);
                text.frame = CGRectMake(textX, y, width - textX - pad, row);
            } else {
                text.frame = CGRectMake(textX, y + (row - kMenuBar * unit) / 2, (width - textX) * kMenuBarShare, kMenuBar * unit);
            }
            symbol.alpha = text.alpha = shown;
            if (shown) y += row;
        }
        CGFloat top = (kTopButtonInset + kTopButton + kMenuGap) * unit;
        return CGRectMake(page.width - SGRPagePreviewMargin - width, top, width, y + pad);
    }];
    overlay.backgroundColor = SGRElevated(SGRNeutralField());
    overlay.clipsToBounds = YES;
    overlay.layer.cornerCurve = kCACornerCurveContinuous;
    for (NSArray<UIView *> *row in rows) for (UIView *view in row) [overlay addSubview:view];
    menu.overlay = overlay;
    menu.rows = rows;
    return menu;
}

// A shelf: the heading (13pt bold, or a bar) over a row of tiles running off the page's trailing edge.
static const NSUInteger kShelfTiles = 6;
static const CGFloat kHeadingFont = 13, kHeadingBar = 9, kHeadingBarShare = 0.35, kHeadingGap = 8, kTileGap = 8;
static const CGFloat kCaptionGap = 5, kCaption = 6, kCaptionShare = 0.8, kTileRadius = 6, kTilePlay = 12;
static const CGSize kTileSquare = {56, 56}, kTileWide = {100, 56}, kTileTall = {50, 80};

UIView *SGRPreviewAddShelf(SGRPagePreview *card, NSString *headingText, NSUInteger firstCover, SGRPreviewTiles tiles) {
    UIView *heading = headingText ? SGRPreviewLabel(headingText, SGRPrimary()) : SGRPreviewBar(SGRPrimary());
    BOOL captioned = tiles == SGRPreviewTilesSquare || tiles == SGRPreviewTilesRound;
    CGSize tileSize = tiles == SGRPreviewTilesWide ? kTileWide : tiles == SGRPreviewTilesTall ? kTileTall : kTileSquare;
    NSMutableArray<NSArray<UIView *> *> *items = [NSMutableArray array];
    for (NSUInteger i = 0; i < kShelfTiles; i++) {
        UIView *extra = captioned ? SGRPreviewBar(SGRSecondary()) : SGRPreviewSymbol(@"play.fill", SGRPrimary());
        [items addObject:@[SGRPreviewCover(firstCover + i), extra]];
    }
    UIView *part = [card addPartWithLayout:^CGFloat(UIView *view, CGFloat width, CGFloat unit) {
        CGFloat headingHeight;
        if ([heading isKindOfClass:UILabel.class]) {
            UILabel *label = (UILabel *)heading;
            label.font = SGRPreviewFont(kHeadingFont, UIFontWeightBold, unit);
            headingHeight = ceil(label.font.lineHeight);
            label.frame = CGRectMake(SGRPagePreviewMargin, 0, width - 2 * SGRPagePreviewMargin, headingHeight);
        } else {
            headingHeight = kHeadingBar * unit;
            heading.frame = CGRectMake(SGRPagePreviewMargin, 0, width * kHeadingBarShare, headingHeight);
        }
        CGFloat top = headingHeight + kHeadingGap * unit, w = tileSize.width * unit, h = tileSize.height * unit;
        [items enumerateObjectsUsingBlock:^(NSArray<UIView *> *item, NSUInteger i, BOOL *stop) {
            UIView *tile = item[0];
            tile.frame = CGRectMake(SGRPagePreviewMargin + i * (w + kTileGap * unit), top, w, h);
            tile.layer.cornerRadius = tiles == SGRPreviewTilesRound ? w / 2 : kTileRadius * unit;
            if (captioned) {
                CGFloat captionWidth = w * kCaptionShare;
                CGFloat x = tiles == SGRPreviewTilesRound ? CGRectGetMidX(tile.frame) - captionWidth / 2 : CGRectGetMinX(tile.frame);
                item[1].frame = CGRectMake(x, CGRectGetMaxY(tile.frame) + kCaptionGap * unit, captionWidth, kCaption * unit);
            } else {
                CGFloat glyph = kTilePlay * unit;
                item[1].frame = CGRectMake(CGRectGetMinX(tile.frame) + kCaptionGap * unit, CGRectGetMaxY(tile.frame) - kCaptionGap * unit - glyph, glyph, glyph);
            }
        }];
        return top + h + (captioned ? (kCaptionGap + kCaption) * unit : 0);
    }];
    [part addSubview:heading];
    for (NSArray<UIView *> *item in items) for (UIView *view in item) [part addSubview:view];
    return part;
}

#pragma mark - the page

@interface SGRPreviewPage : SGModPage
@property (nonatomic, copy) NSArray<SGRPagePreview *> *cards;
@property (nonatomic, strong) UISegmentedControl *picker;
- (instancetype)initWithTitle:(NSString *)title card:(SGRPagePreview *)card note:(NSString *)note sections:(NSArray<SGModSection *> *)sections;
@end

@implementation SGRPreviewPage {
    SGRPagePreview *_card;
    UIView *_header;
    UILabel *_note;
}

- (instancetype)initWithTitle:(NSString *)title card:(SGRPagePreview *)card note:(NSString *)note sections:(NSArray<SGModSection *> *)sections {
    if (!(self = [super initWithTitle:title intro:nil sections:sections footer:nil])) return nil;
    _card = card;
    _note = [UILabel new];
    _note.text = note;
    _note.textColor = SGGrey();
    _note.numberOfLines = 0;
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    _header = [UIView new];
    if (_picker) {
        [_header addSubview:_picker];
        [_picker addTarget:self action:@selector(pickCard) forControlEvents:UIControlEventValueChanged];
    }
    [_header addSubview:_card];
    [_header addSubview:_note];
    self.tableView.tableHeaderView = _header;
}

// The header keeps the height it is given, so it is measured here and handed back to the table only when that
// changes, as the Lyrics page does: the card at the table's inset, the note under it.
- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    UITableView *table = self.tableView;
    CGFloat width = table.bounds.size.width, inset = table.layoutMargins.left, inner = width - 2 * inset;
    if (inner <= 0) return;
    CGFloat top = 2 * SGRGrid;
    if (_picker) {
        _picker.frame = CGRectMake(inset, top, inner, _picker.intrinsicContentSize.height);
        top = CGRectGetMaxY(_picker.frame) + kNoteGap;
    }
    _card.frame = CGRectMake(inset, top, inner, _card.preferredHeight);
    _note.font = SGSubtitleFont();
    CGFloat noteHeight = _note.text.length ? ceil([_note sizeThatFits:CGSizeMake(inner, CGFLOAT_MAX)].height) : 0;
    _note.frame = CGRectMake(inset, CGRectGetMaxY(_card.frame) + kNoteGap, inner, noteHeight);
    CGSize size = CGSizeMake(width, CGRectGetMaxY(_note.frame));
    if (CGSizeEqualToSize(_header.bounds.size, size)) return;
    _header.frame = (CGRect){CGPointZero, size};
    table.tableHeaderView = _header;
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    [_card drawIfStaleInSight];
}

- (void)pickCard {
    [_card removeFromSuperview];
    _card = _cards[(NSUInteger)_picker.selectedSegmentIndex];
    [_header addSubview:_card];
    [self.view setNeedsLayout];
}

@end

UIViewController *SGRPagePreviewPage(NSString *title, SGRPagePreview *card, NSString *note, NSArray<SGModSection *> *sections) {
    return [[SGRPreviewPage alloc] initWithTitle:title card:card note:note sections:sections];
}

UIViewController *SGRPairedPreviewPage(NSString *title, SGRPagePreview *first, SGRPagePreview *second,
                                      NSArray<NSString *> *labels, NSString *note, NSArray<SGModSection *> *sections) {
    SGRPreviewPage *page = [[SGRPreviewPage alloc] initWithTitle:title card:first note:note sections:sections];
    page.cards = @[first, second];
    page.picker = [[UISegmentedControl alloc] initWithItems:labels];
    page.picker.selectedSegmentIndex = 0;
    return page;
}
