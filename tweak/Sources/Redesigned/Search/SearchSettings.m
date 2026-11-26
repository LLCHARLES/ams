// The redesign's Search page: what the Browse page collapses (SearchSections.x) and the category cards' glass
// (SearchCards.x), each on until switched off and read at launch. It leads with a preview of the Browse page
// (Kit/SGRPagePreview.h) that follows the three.
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Redesigned/Kit/SGRTokens.h"
#import "Redesigned/Kit/SGRPagePreview.h"
#import "Search.h"

// The glass search field under the title.
static const CGFloat kField = 30, kFieldPad = 10, kFieldGlyph = 13, kFieldBar = 7, kFieldBarShare = 0.4;
// A promo: a banner in a cover's color with the cover at its trailing end.
static const NSUInteger kPromoCover = 3;
static const CGFloat kPromo = 52, kPromoRadius = 8, kPromoBar = 9, kPromoBarShare = 0.45, kPromoPad = 12;
// Browse all: two columns of cards, a heading bar over them. Each card is its color with a bar for its title at the
// top leading corner and its cover turned at the trailing edge, as Spotify draws it (SearchCards.x).
static const NSUInteger kCategoryRows = 3, kCategoryColumns = 2, kFirstCategory = 0;
static const CGFloat kCategory = 50, kCategoryGap = 8, kCategoryArt = 34, kCategoryTurn = 25 * M_PI / 180;
// How far in from the card's trailing and bottom edges the turned cover's middle sits, in the cover's sides.
static const CGSize kCategoryArtIn = {0.3, 0.25};
static const CGFloat kCategoryBar = 8, kCategoryBarShare = 0.45, kHeadingBar = 9, kHeadingBarShare = 0.3, kHeadingGap = 8;
// Spotify's own card: corner 4 and its title 8 in; on tinted glass: the card radius and the title 12 in, the color
// running to this much of its brightness at the far corner, a rim catching the light (SearchCards.x).
static const CGFloat kSpotifyRadius = 4, kSpotifyTitleInset = 8, kGlassRadius = 12, kGlassTitleInset = 12;
static const CGFloat kFarBrightness = 0.55, kRimAlpha = 0.3;

static UIColor *darker(UIColor *color) {
    CGFloat h = 0, s = 0, b = 0, a = 0;
    [color getHue:&h saturation:&s brightness:&b alpha:&a];
    return [UIColor colorWithHue:h saturation:s brightness:b * kFarBrightness alpha:a];
}

// The Browse page from the top: the title, the glass field, a promo and a video carousel while they are not
// collapsed, and the category cards, on tinted glass or Spotify's own; the tab bar over the foot.
static SGRPagePreview *searchPreview(NSString *videosName, NSString *otherName, NSString *cardsName, NSString *glassName) {
    SGRPagePreview *card = [[SGRPagePreview alloc] initWithLabel:SGL(@"settings.search_tab.preview.a11y", @"Preview of Search")];
    SGRPreviewAddTitle(card, SGL(@"settings.search_tab.title", @"Search"));

    UIView *field = SGRPreviewGlass();
    UIImageView *fieldGlyph = SGRPreviewAddSymbol(field, @"magnifyingglass", SGRSecondary());
    UIView *fieldBar = SGRPreviewBar(SGRTertiary());
    [field addSubview:fieldBar];
    UIView *fieldPart = [card addPartWithLayout:^CGFloat(UIView *part, CGFloat width, CGFloat unit) {
        CGFloat height = kField * unit, glyph = kFieldGlyph * unit, pad = kFieldPad * unit;
        field.frame = CGRectMake(SGRPagePreviewMargin, 0, width - 2 * SGRPagePreviewMargin, height);
        field.layer.cornerRadius = height / 2;
        fieldGlyph.frame = CGRectMake(pad, (height - glyph) / 2, glyph, glyph);
        fieldBar.frame = CGRectMake(2 * pad + glyph, (height - kFieldBar * unit) / 2, field.bounds.size.width * kFieldBarShare, kFieldBar * unit);
        return height;
    }];
    [fieldPart addSubview:field];

    UIView *banner = SGRPreviewGradient(@[SGRPreviewColor(kPromoCover), darker(SGRPreviewColor(kPromoCover))], CGPointZero, CGPointMake(1, 1));
    banner.clipsToBounds = YES;
    banner.layer.cornerCurve = kCACornerCurveContinuous;
    UIView *bannerBar = SGRPreviewBar(SGRPrimary());
    UIImageView *bannerArt = SGRPreviewCover(kPromoCover);
    [banner addSubview:bannerBar];
    [banner addSubview:bannerArt];
    UIView *promo = [card addPartWithLayout:^CGFloat(UIView *part, CGFloat width, CGFloat unit) {
        CGFloat height = kPromo * unit, pad = kPromoPad * unit;
        banner.frame = CGRectMake(SGRPagePreviewMargin, 0, width - 2 * SGRPagePreviewMargin, height);
        banner.layer.cornerRadius = kPromoRadius * unit;
        bannerArt.frame = CGRectMake(banner.bounds.size.width - height, 0, height, height);
        bannerBar.frame = CGRectMake(pad, (height - kPromoBar * unit) / 2, banner.bounds.size.width * kPromoBarShare, kPromoBar * unit);
        return height;
    }];
    [promo addSubview:banner];
    promo.accessibilityLabel = otherName;

    UIView *videos = SGRPreviewAddShelf(card, nil, kPromoCover + 1, SGRPreviewTilesTall);
    videos.accessibilityLabel = videosName;

    UIView *heading = SGRPreviewBar(SGRPrimary());
    NSMutableArray<NSArray<UIView *> *> *categories = [NSMutableArray array];
    for (NSUInteger i = 0; i < kCategoryRows * kCategoryColumns; i++) {
        UIColor *color = SGRPreviewColor(kFirstCategory + i);
        UIView *plate = [UIView new];
        plate.backgroundColor = color;
        plate.clipsToBounds = YES;
        plate.layer.cornerCurve = kCACornerCurveContinuous;
        UIView *glass = SGRPreviewGradient(@[color, darker(color)], CGPointZero, CGPointMake(1, 1));
        glass.layer.borderColor = [UIColor colorWithWhite:1 alpha:kRimAlpha].CGColor;
        glass.layer.borderWidth = 1 / UIScreen.mainScreen.scale;
        glass.layer.cornerCurve = kCACornerCurveContinuous;
        UIImageView *art = SGRPreviewCover(kFirstCategory + i);
        UIView *bar = SGRPreviewBar(SGRPrimary());
        for (UIView *view in @[glass, art, bar]) [plate addSubview:view];
        [categories addObject:@[plate, glass, art, bar]];
    }
    __block BOOL onGlass = YES;
    UIView *cards = [card addPartWithLayout:^CGFloat(UIView *part, CGFloat width, CGFloat unit) {
        CGFloat headingHeight = kHeadingBar * unit;
        heading.frame = CGRectMake(SGRPagePreviewMargin, 0, width * kHeadingBarShare, headingHeight);
        CGFloat gap = kCategoryGap * unit, top = headingHeight + kHeadingGap * unit, height = kCategory * unit;
        CGFloat cardWidth = (width - 2 * SGRPagePreviewMargin - (kCategoryColumns - 1) * gap) / kCategoryColumns;
        CGFloat radius = (onGlass ? kGlassRadius : kSpotifyRadius) * unit, inset = (onGlass ? kGlassTitleInset : kSpotifyTitleInset) * unit;
        CGFloat art = kCategoryArt * unit;
        [categories enumerateObjectsUsingBlock:^(NSArray<UIView *> *views, NSUInteger i, BOOL *stop) {
            NSUInteger row = i / kCategoryColumns, column = i % kCategoryColumns;
            views[0].frame = CGRectMake(SGRPagePreviewMargin + column * (cardWidth + gap), top + row * (height + gap), cardWidth, height);
            views[0].layer.cornerRadius = radius;
            views[1].frame = views[0].bounds;
            views[1].layer.cornerRadius = radius;
            views[1].alpha = onGlass;
            views[2].bounds = CGRectMake(0, 0, art, art);
            views[2].center = CGPointMake(cardWidth - art * kCategoryArtIn.width, height - art * kCategoryArtIn.height);
            views[2].transform = CGAffineTransformMakeRotation(kCategoryTurn);
            views[3].frame = CGRectMake(inset, inset, cardWidth * kCategoryBarShare, kCategoryBar * unit);
        }];
        return top + kCategoryRows * height + (kCategoryRows - 1) * gap;
    }];
    [cards addSubview:heading];
    for (NSArray<UIView *> *views in categories) [cards addSubview:views[0]];

    [card addTabBarShowing:SGRPreviewTabSearch];

    card.state = ^id<NSObject> {
        return @[@(SGEnabled(SGRKeySearchHideWatchFeeds)), @(SGEnabled(SGRKeySearchHideOther)), @(SGEnabled(SGRKeySearchGlassCards))];
    };
    card.apply = ^(SGRPagePreview *preview, NSArray<NSNumber *> *state) {
        [preview setPart:videos shown:!state[0].boolValue];
        [preview setPart:promo shown:!state[1].boolValue];
        if (onGlass != state[2].boolValue) [preview revealPart:cards];
        onGlass = state[2].boolValue;
        cards.accessibilityLabel = onGlass ? glassName : cardsName;
    };
    return card;
}

SGRPagePreview *SGRSearchPreview(void) {
    return searchPreview(SGL(@"settings.search_tab.hide.watch_feeds.title", @"Video carousels"),
                         SGL(@"settings.search_tab.hide.other.title", @"Everything else"),
                         SGL(@"settings.search_tab.cards.header", @"Category cards"),
                         SGL(@"settings.search_tab.glass_cards.title", @"Tinted glass"));
}

NSArray<SGModSection *> *SGRSearchSections(void) {
    NSString *videosName = SGL(@"settings.search_tab.hide.watch_feeds.title", @"Video carousels");
    NSString *otherName = SGL(@"settings.search_tab.hide.other.title", @"Everything else");
    NSString *cardsName = SGL(@"settings.search_tab.cards.header", @"Category cards");
    NSString *glassName = SGL(@"settings.search_tab.glass_cards.title", @"Tinted glass");
    return @[
        SGNotedSection(SGL(@"settings.search_tab.hide.header", @"Hide on Search"), @[
            SGSwitchRow(videosName, SGL(@"settings.search_tab.hide.watch_feeds.subtitle", @"Playlists you can watch, Explore episodes for you"),
                        SGRKeySearchHideWatchFeeds),
            SGSwitchRow(otherName, SGL(@"settings.search_tab.hide.other.subtitle", @"Promos and any other section Spotify sends"),
                        SGRKeySearchHideOther),
        ], SGL(@"settings.search_tab.hide.note", @"The category cards always stay.")),
        SGSection(cardsName, @[
            SGSwitchRow(glassName, SGL(@"settings.search_tab.glass_cards.subtitle", @"Each card as Liquid Glass in its own color. Off, the cards are Spotify's own."),
                        SGRKeySearchGlassCards),
        ]),
    ];
}
