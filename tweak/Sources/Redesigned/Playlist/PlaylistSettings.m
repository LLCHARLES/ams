// The redesign's Playlists page: the cover full screen from the header's picture (PlaylistHeader.x), the curation
// pills closed up (PlaylistRows.x) and Sort and Mix on the ⋯ sheet (PlaylistMenu.x), each on until switched off and
// read at launch. It leads with a preview of a playlist's page (Kit/SGRPagePreview.h) that follows the three.
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Redesigned/Kit/SGRTokens.h"
#import "Redesigned/Kit/SGRPagePreview.h"
#import "Redesigned/Kit/SGRHeaderInfo.h"
#import "Playlist.h"
#import "Redesigned/Album/SGRCoverBeside.h"

// The mock playlist's cover, whose color the page's field takes, and its tracks.
static const NSUInteger kCover = 2, kTracks = 5;
// The curation pills: a glyph and a word each.
static const CGFloat kPill = 24, kPillPad = 9, kPillGlyph = 11, kPillWord = 18, kPillWordHeight = 6, kPillTextGap = 6, kPillGap = 6;

// A playlist as the redesign lays it out, from the top: the cover with its header and controls (a badge on the
// cover while a tap opens it full screen), the pills, the tracks, and over them the back button, the pinned ⋯ and
// its menu, Sort and Mix at its top while they are on it.
static SGRPagePreview *playlistPreview(NSString *coverName, NSString *pillsName, NSString *sortMixName) {
    SGRPagePreview *card = [[SGRPagePreview alloc] initWithLabel:SGL(@"settings.playlist.preview.a11y", @"Preview of a playlist")];
    SGRPreviewHeader *header = SGRPreviewAddHeader(card, kCover, @"arrow.up.left.and.arrow.down.right", @"plus");

    // Add, Sort, Edit and Mix over the first track.
    NSArray<NSString *> *pillGlyphs = @[@"plus", @"arrow.up.arrow.down", @"pencil", @"wand.and.stars"];
    NSMutableArray<UIView *> *pillViews = [NSMutableArray array];
    UIView *pills = [card addPartWithLayout:^CGFloat(UIView *part, CGFloat width, CGFloat unit) {
        CGFloat x = SGRPagePreviewMargin, height = kPill * unit;
        for (UIView *pill in pillViews) {
            CGFloat pad = kPillPad * unit, glyph = kPillGlyph * unit, word = kPillWord * unit;
            pill.frame = CGRectMake(x, 0, pad + glyph + kPillTextGap * unit + word + pad, height);
            pill.layer.cornerRadius = height / 2;
            pill.subviews[0].frame = CGRectMake(pad, (height - glyph) / 2, glyph, glyph);
            pill.subviews[1].frame = CGRectMake(pad + glyph + kPillTextGap * unit, (height - kPillWordHeight * unit) / 2, word, kPillWordHeight * unit);
            x = CGRectGetMaxX(pill.frame) + kPillGap * unit;
        }
        return height;
    }];
    for (NSString *symbol in pillGlyphs) {
        UIView *pill = SGRPreviewGlass();
        SGRPreviewAddSymbol(pill, symbol, SGRPrimary());
        [pill addSubview:SGRPreviewBar(SGRSecondary())];
        [pills addSubview:pill];
        [pillViews addObject:pill];
    }
    pills.accessibilityLabel = pillsName;

    SGRPreviewAddTracks(card, kTracks, YES, kCover + 1);
    SGRPreviewAddTopBar(card);
    SGRPreviewMenu *menu = SGRPreviewAddMenu(card, @[@"arrow.up.arrow.down", @"wand.and.stars", @"plus.circle", @"square.and.arrow.up"],
                                             @[SGL(@"settings.playlist.preview.sort", @"Sort"), SGL(@"settings.playlist.preview.mix", @"Mix")]);

    card.state = ^id<NSObject> {
        return @[@(SGEnabled(SGRKeyPlaylistCoverViewer)), @(SGEnabled(SGRKeyPlaylistHideCuration)), @(SGEnabled(SGRKeyPlaylistMenuSortMix)),
                 @(SGRPageFullCover(SGRKeyPlaylistFullCover)), @(SGEnabled(SGRKeyPlaylistCreatorLine)),
                 @(SGEnabled(SGRKeyPlaylistCreatorPicture)), @(SGEnabled(SGRKeyPlaylistDescription))];
    };
    card.apply = ^(SGRPagePreview *preview, NSArray<NSNumber *> *state) {
        BOOL viewer = state[0].boolValue, hidePills = state[1].boolValue, sortMix = state[2].boolValue;
        if (header.fullCover != state[3].boolValue) [preview revealPart:header.part];
        header.fullCover = state[3].boolValue;
        [header setCreatorLine:state[4].boolValue picture:state[5].boolValue description:state[6].boolValue];
        if (header.badge.alpha != viewer) [preview revealPart:header.part];
        header.badge.alpha = viewer;
        header.part.accessibilityLabel = viewer ? coverName : nil;
        [preview setPart:pills shown:!hidePills];
        [menu setRow:0 shown:sortMix];
        [menu setRow:1 shown:sortMix];
        menu.overlay.accessibilityLabel = sortMix ? sortMixName : nil;
    };
    return card;
}

UIViewController *SGRPlaylistSettingsPage(void) {
    NSString *coverName = SGL(@"settings.playlist.open_cover_on_tap.title", @"Open cover on tap");
    NSString *pillsName = SGL(@"settings.playlist.hide.pills.title", @"Curation pills");
    NSString *sortMixName = SGL(@"settings.playlist.sort_mix.title", @"Sort and Mix");
    return SGRPagePreviewPage(SGL(@"settings.playlist.title", @"Playlists"), playlistPreview(coverName, pillsName, sortMixName), SGRestartNote, @[
        SGSection(SGL(@"settings.playlist.cover.header", @"Cover"), @[
            SGChoiceRow(SGL(@"settings.playlist.cover_layout", @"Cover layout"), nil, SGRKeyPlaylistFullCover,
                @[SGL(@"settings.cover_layout.card", @"Card"), SGL(@"settings.cover_layout.full_screen", @"Full screen")],
                SGRPageFullCover(SGRKeyPlaylistFullCover)),
            SGSwitchRow(coverName, SGL(@"settings.playlist.full_screen_cover.subtitle", @"Tap the picture at the top of a playlist to zoom in or share it"),
                        SGRKeyPlaylistCoverViewer),
        ]),
        SGSection(SGL(@"settings.playlist.header_details", @"Playlist details"), @[
            SGSwitchRow(SGL(@"settings.playlist.creator_line", @"Creator and length"), nil, SGRKeyPlaylistCreatorLine),
            SGSwitchRow(SGL(@"settings.playlist.creator_picture", @"Creator picture"), nil, SGRKeyPlaylistCreatorPicture),
            SGSwitchRow(SGL(@"settings.playlist.description", @"Description"), nil, SGRKeyPlaylistDescription),
        ]),
        SGSection(SGL(@"settings.playlist.hide_on_page.header", @"Hide on a playlist's page"), @[
            SGSwitchRow(pillsName, SGL(@"settings.playlist.hide.pills.subtitle", @"Add, Mix, Sort and the rest, over the first track"),
                        SGRKeyPlaylistHideCuration),
            SGOptionRow(SGL(@"settings.playlist.hide.recommendations.title", @"Recommended songs"),
                        SGL(@"settings.playlist.hide.recommendations.subtitle", @"Hide recommendations and Refresh below the tracks. Reopen the playlist to apply"),
                        SGRKeyPlaylistHideRecommendations),
        ]),
        SGNotedSection(SGL(@"settings.playlist.more_menu.header", @"More menu"), @[
            SGSwitchRow(sortMixName, SGL(@"settings.playlist.sort_mix.subtitle", @"At the top of a playlist's ⋯ menu"),
                        SGRKeyPlaylistMenuSortMix),
        ], SGL(@"settings.playlist.sort_mix.note", @"The two curation pills the ⋯ menu does not already offer, so they stay a tap away with the pills hidden.")),
    ]);
}
