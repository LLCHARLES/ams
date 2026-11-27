// The redesign's Artists page: Apple Music's logo in place of the name on an artist's page, its animated artwork and
// photo, and what the redesign takes off the page. It leads with a preview of an artist's page
// (Kit/SGRPagePreview.h) that follows them.
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Shared/AnimatedArtwork/AnimatedArtwork.h"
#import "Redesigned/Kit/SGRTokens.h"
#import "Redesigned/Kit/SGRPagePreview.h"
#import "Redesigned/Kit/SGRActionRow.h"
#import "Redesigned/Kit/SGRHeaderInfo.h"
#import "Artist.h"

// The mock artist's photo, Spotify's and Apple Music's, and the popular tracks under the header.
static const NSUInteger kPhoto = 6, kApplePhoto = 2, kPopularTracks = 3, kAboutLines = 3;
// The Music, Video and Merch strip: a capsule each, the first lit.
static const NSUInteger kTabs = 3;
static const CGFloat kTab = 24, kTabWidth = 64, kTabGap = 8, kTabBar = 6, kTabBarShare = 0.6;
// The Artist pick and the Release countdown: a card with a cover or a glyph at its leading end and two lines.
static const CGFloat kCardRow = 48, kCardRadius = 10, kCardPad = 8, kCardGlyph = 18, kCardLine = 7, kCardLineGap = 6;
static const CGFloat kCardTitleShare = 0.5, kCardDetailShare = 0.32;   // of the room for text

// A card of the Music list: `leading` (a cover, or a glyph on glass) and a title over a line of detail.
static UIView *addCardRow(SGRPagePreview *card, UIView *leading) {
    UIView *body = [UIView new];
    body.clipsToBounds = YES;
    body.layer.cornerCurve = kCACornerCurveContinuous;
    UIView *title = SGRPreviewBar(SGRPrimary()), *detail = SGRPreviewBar(SGRSecondary());
    for (UIView *view in @[leading, title, detail]) [body addSubview:view];
    __weak SGRPagePreview *weakCard = card;
    UIView *part = [card addPartWithLayout:^CGFloat(UIView *view, CGFloat width, CGFloat unit) {
        // On the field of the photo shown.
        body.backgroundColor = SGRElevated(weakCard.fieldColor);
        CGFloat height = kCardRow * unit, pad = kCardPad * unit, side = height - 2 * pad, line = kCardLine * unit;
        body.frame = CGRectMake(SGRPagePreviewMargin, 0, width - 2 * SGRPagePreviewMargin, height);
        body.layer.cornerRadius = kCardRadius * unit;
        leading.frame = CGRectMake(pad, pad, side, side);
        leading.layer.cornerRadius = kCardRadius / 2 * unit;
        if (leading.subviews.count) SGRPreviewCenter(leading.subviews[0], leading.bounds, kCardGlyph * unit);
        CGFloat x = CGRectGetMaxX(leading.frame) + pad, room = body.bounds.size.width - x - pad, middle = height / 2;
        title.frame = CGRectMake(x, middle - line - kCardLineGap * unit / 2, room * kCardTitleShare, line);
        detail.frame = CGRectMake(x, middle + kCardLineGap * unit / 2, room * kCardDetailShare, line);
        return height;
    }];
    [part addSubview:body];
    return part;
}

// The cut-out round Play over the card's white Play: a circle the row's height in the fill, with the card's play glyph
// cut out of it the way the page's is (SGRCutOutMask), so the field shows through. The white under it is put back as it
// goes.
@interface SGRArtistPreviewCutOut : UIView
@property (nonatomic, weak) UIImageView *glyph;
@property (nonatomic, strong) UIColor *covered;
@end

@implementation SGRArtistPreviewCutOut {
    CALayer *_cut;
    CGSize _cutFor;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGSize size = self.bounds.size;
    if (_cut && CGSizeEqualToSize(size, _cutFor)) return;
    _cutFor = size;
    UIImage *mask = SGRCutOutMask(self, CGRectMake((size.width - size.height) / 2, 0, size.height, size.height), self.glyph, nil);
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    if (!_cut) _cut = [CALayer layer];
    _cut.frame = self.bounds;
    _cut.contents = (__bridge id)mask.CGImage;
    _cut.contentsScale = mask.scale;
    self.layer.mask = _cut;
    [CATransaction commit];
}
@end

// The card's white Play: the middle of the header's three controls, in the order Kit/SGRPagePreview.h gives them.
static UIView *previewPlay(UIView *header) {
    __block UIView *controls = nil;
    SGForEachView(header, ^(UIView *view) {
        if (!controls && [view.accessibilityIdentifier isEqualToString:@"retrine.preview.header.controls"]) controls = view;
    });
    return controls.subviews.count == 3 ? controls.subviews[1] : nil;
}

static SGRArtistPreviewCutOut *cutIn(UIView *play) {
    for (UIView *view in play.subviews) if ([view isKindOfClass:SGRArtistPreviewCutOut.class]) return (SGRArtistPreviewCutOut *)view;
    return nil;
}

// The card's Play cut out in `fill`, or nil for its own white Play.
static void showCutOut(UIView *play, UIColor *fill) {
    SGRArtistPreviewCutOut *cut = cutIn(play);
    UIImageView *glyph = nil;
    for (UIView *view in play.subviews) if ([view isKindOfClass:UIImageView.class]) glyph = (UIImageView *)view;
    if (!fill) {
        if (!cut) return;
        play.backgroundColor = cut.covered;
        [cut removeFromSuperview];
        glyph.alpha = 1;
        return;
    }
    if (!cut) {
        cut = [[SGRArtistPreviewCutOut alloc] initWithFrame:play.bounds];
        cut.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        cut.glyph = glyph;
        cut.covered = play.backgroundColor;
        [play insertSubview:cut atIndex:0];
        play.backgroundColor = UIColor.clearColor;
        glyph.alpha = 0;
    }
    cut.backgroundColor = fill;
}

// An artist as the redesign lays it out, from the top: the photo (Apple Music's while asked for, a badge on it while
// its animated artwork is) with the name, or the logo, the listeners and the controls, Play cut out while round Play
// is (Kit/SGRHeaderInfo.h); the Music, Video and Merch strip, the Release countdown and the Artist pick while they are
// kept; the popular tracks; the videos while kept; the discography; About while kept; over them the back button and
// the ⋯.
static SGRPagePreview *artistPreview(NSDictionary<NSString *, NSString *> *names) {
    SGRPagePreview *card = [[SGRPagePreview alloc] initWithLabel:SGL(@"settings.artist.preview.a11y", @"Preview of an artist")];
    SGRPreviewHeader *header = SGRPreviewAddHeader(card, kPhoto, @"livephoto", @"person.badge.plus");

    NSMutableArray<UIView *> *tabViews = [NSMutableArray array];
    for (NSUInteger i = 0; i < kTabs; i++) {
        UIView *tab = i == 0 ? SGRPreviewBar(SGRPrimary()) : SGRPreviewGlass();
        [tab addSubview:SGRPreviewBar(i == 0 ? UIColor.blackColor : SGRSecondary())];
        [tabViews addObject:tab];
    }
    UIView *tabs = [card addPartWithLayout:^CGFloat(UIView *view, CGFloat width, CGFloat unit) {
        CGFloat height = kTab * unit, tabWidth = kTabWidth * unit, bar = kTabBar * unit;
        [tabViews enumerateObjectsUsingBlock:^(UIView *tab, NSUInteger i, BOOL *stop) {
            tab.frame = CGRectMake(SGRPagePreviewMargin + i * (tabWidth + kTabGap * unit), 0, tabWidth, height);
            tab.layer.cornerRadius = height / 2;
            tab.subviews[0].frame = CGRectMake(tabWidth * (1 - kTabBarShare) / 2, (height - bar) / 2, tabWidth * kTabBarShare, bar);
        }];
        return height;
    }];
    for (UIView *tab in tabViews) [tabs addSubview:tab];
    tabs.accessibilityLabel = names[SGRKeyArtistHideTabs];

    UIView *calendar = SGRPreviewGlass();
    SGRPreviewAddSymbol(calendar, @"calendar", SGRPrimary());
    UIView *countdown = addCardRow(card, calendar);
    countdown.accessibilityLabel = names[SGRKeyArtistHideCountdown];
    UIView *pick = addCardRow(card, SGRPreviewCover(kPhoto + 1));
    pick.accessibilityLabel = names[SGRKeyArtistHidePick];
    SGRPreviewAddTracks(card, kPopularTracks, YES, kPhoto + 2);
    UIView *videos = SGRPreviewAddShelf(card, names[SGRKeyArtistHideVideos], kPhoto + 3, SGRPreviewTilesWide);
    videos.accessibilityLabel = names[SGRKeyArtistHideVideos];
    SGRPreviewAddShelf(card, nil, kPhoto + 4, SGRPreviewTilesSquare);
    UIView *about = SGRPreviewAddParagraph(card, kAboutLines);
    about.accessibilityLabel = names[SGRKeyArtistHideAbout];
    SGRPreviewAddTopBar(card);

    card.state = ^id<NSObject> {
        NSMutableDictionary *state = [NSMutableDictionary dictionary];
        state[SGRKeyArtistLogo] = @(SGEnabled(SGRKeyArtistLogo));
        // As ArtistHeader.x asks: the switch, and Apple Music among the animated artwork's sources.
        state[SGRKeyArtistMotion] = @(SGEnabled(SGRKeyArtistMotion) && SGMotionAppleMusicOn());
        state[SGRKeyArtistApplePhoto] = @(SGHidden(SGRKeyArtistApplePhoto));
        state[SGRKeyArtistHideVideos] = @(SGEnabled(SGRKeyArtistHideVideos));
        state[SGRKeyArtistHideTabs] = @(SGEnabled(SGRKeyArtistHideTabs));
        state[SGRKeyArtistHidePick] = @(SGHidden(SGRKeyArtistHidePick));
        state[SGRKeyArtistHideCountdown] = @(SGHidden(SGRKeyArtistHideCountdown));
        state[SGRKeyArtistHideAbout] = @(SGHidden(SGRKeyArtistHideAbout));
        // As SGRHeaderInfo.m asks: cut out only round.
        state[SGRKeyArtistCutOutPlay] = @(SGFlag(SGRKeyArtistRoundPlay, NO) && SGFlag(SGRKeyArtistCutOutPlay, NO));
        state[SGRKeyAccentPlay] = @(SGFlag(SGRKeyAccentPlay, NO));
        return state;
    };
    card.apply = ^(SGRPagePreview *preview, NSDictionary *state) {
        BOOL (^on)(NSString *) = ^BOOL(NSString *key) { return [state[key] boolValue]; };
        BOOL logo = on(SGRKeyArtistLogo), motion = on(SGRKeyArtistMotion), applePhoto = on(SGRKeyArtistApplePhoto);
        // The photo shown, and the page's field and the header's dissolve in its color, as ArtistHeader.x takes it.
        NSUInteger photo = applePhoto ? kApplePhoto : kPhoto;
        UIView *play = previewPlay(header.part);
        UIColor *fill = !on(SGRKeyArtistCutOutPlay) ? nil : on(SGRKeyAccentPlay) ? SGRAccent() : UIColor.whiteColor;
        BOOL cutShown = cutIn(play) != nil;
        if (header.showsLogo != logo || header.badge.alpha != motion || header.cover != photo || cutShown != (fill != nil)) {
            [preview revealPart:header.part];
        }
        header.showsLogo = logo;
        header.badge.alpha = motion;
        header.cover = photo;
        showCutOut(play, fill);
        NSMutableArray<NSString *> *headerNames = [NSMutableArray array];
        for (NSString *key in @[SGRKeyArtistLogo, SGRKeyArtistMotion, SGRKeyArtistApplePhoto, SGRKeyArtistCutOutPlay]) if (on(key)) [headerNames addObject:names[key]];
        header.part.accessibilityLabel = SGRPreviewList(headerNames);
        [preview setPart:tabs shown:!on(SGRKeyArtistHideTabs)];
        [preview setPart:countdown shown:!on(SGRKeyArtistHideCountdown)];
        [preview setPart:pick shown:!on(SGRKeyArtistHidePick)];
        [preview setPart:videos shown:!on(SGRKeyArtistHideVideos)];
        [preview setPart:about shown:!on(SGRKeyArtistHideAbout)];
    };
    return card;
}

UIViewController *SGRArtistSettingsPage(void) {
    NSArray<SGModRow *> *appleMusic = @[
        SGSwitchRow(SGL(@"settings.artist.logos.title", @"Artist logos"), SGL(@"settings.artist.logos.subtitle", @"In place of the name on an artist's page"), SGRKeyArtistLogo),
        SGSwitchRow(SGL(@"settings.artist.motion.title", @"Animated artist artwork"), nil, SGRKeyArtistMotion),
        SGOptionRow(SGL(@"settings.artist.apple_photo.title", @"Apple Music artist photo"), nil, SGRKeyArtistApplePhoto),
    ];
    NSArray<SGModRow *> *hide = @[
        SGSwitchRow(SGL(@"settings.artist.hide.videos.title", @"Videos"), SGL(@"settings.artist.hide.videos.subtitle", @"In the Music list, and in the Video tab"), SGRKeyArtistHideVideos),
        SGSwitchRow(SGL(@"settings.artist.hide.tabs.title", @"Music, Video and Merch tabs"), SGL(@"settings.artist.hide.tabs.subtitle", @"Without them the Music list is the page"), SGRKeyArtistHideTabs),
        SGHideRow(SGL(@"settings.artist.hide.pick.title", @"Artist pick"), nil, SGRKeyArtistHidePick),
        SGHideRow(SGL(@"settings.artist.hide.countdown.title", @"Release countdown"), SGL(@"settings.artist.hide.countdown.subtitle", @"The pre-save of an upcoming release"), SGRKeyArtistHideCountdown),
        SGHideRow(SGL(@"settings.artist.hide.about.title", @"About"), nil, SGRKeyArtistHideAbout),
    ];
    // Round Play's only row; the cut-out waits on it.
    SGModRow *roundPlay = SGOptionRow(SGL(@"settings.appearance.round_artist_play.title", @"Round artist Play"),
        SGL(@"settings.appearance.round_artist_play.subtitle", @"On artist pages, Play is a round button with its symbol alone"),
        SGRKeyArtistRoundPlay);
    SGModRow *cutOut = SGOptionRow(SGL(@"settings.artist.cut_out_play.title", @"Cut-out Play"), nil, SGRKeyArtistCutOutPlay);
    cutOut.waitsOn = SGRKeyArtistRoundPlay;
    SGModRow *accentPlay = SGOptionRow(SGL(@"settings.artist.accent_play.title", @"Accent Play button"), nil, SGRKeyAccentPlay);
    accentPlay.waitsOn = SGRKeyArtistCutOutPlay;
    accentPlay.visible = ^BOOL { return SGFlag(SGRKeyArtistRoundPlay, NO) && SGFlag(SGRKeyArtistCutOutPlay, NO); };
    NSArray<SGModRow *> *play = @[roundPlay, cutOut, accentPlay];
    NSArray<SGModRow *> *header = @[
        SGOptionRow(SGL(@"settings.artist.adaptive_photo.title", @"Picture-aware photo"),
            SGL(@"settings.artist.adaptive_photo.subtitle", @"Picks the page colour from the photo, leaving faces out"), SGRKeyArtistAdaptivePhoto),
        SGOptionRow(SGL(@"settings.artist.listeners_in_about.title", @"Monthly listeners in About"),
            SGL(@"settings.artist.listeners_in_about.subtitle", @"Spotify’s About shows the count. Hide About to keep it under the artist’s name."), SGRKeyArtistListenersInAbout),
    ];
    // The card names what it shows by the rows' own titles, by their keys.
    NSMutableDictionary<NSString *, NSString *> *names = [NSMutableDictionary dictionary];
    for (NSArray<SGModRow *> *rows in @[appleMusic, play, hide]) for (SGModRow *row in rows) names[row.key] = row.title;

    return SGRPagePreviewPage(SGL(@"settings.artist.title", @"Artists"), artistPreview(names), SGRestartNote, @[
        SGNotedSection(SGL(@"settings.artist.apple_music.header", @"Apple Music"), appleMusic,
                       SGL(@"settings.artist.apple_music.note", @"Only the artist's name is sent to Apple Music.")),
        SGNotedSection(SGL(@"settings.artist.play.header", @"Play"), play,
                       SGL(@"settings.artist.cut_out_play.footer", @"The triangle is cut out of the button.")),
        SGSection(SGL(@"settings.artist.header.header", @"Header"), header),
        SGSection(SGL(@"settings.artist.hide_on_page.header", @"Hide on an artist's page"), hide),
    ]);
}
