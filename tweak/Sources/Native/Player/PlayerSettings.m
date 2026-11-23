// The native player's settings: Spotify's own player screen and the parts of it to hide, and the queue
// and devices flags. The Player page that holds them is App/Pages.m's.
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "NowPlaying.h"

NSArray<SGModSection *> *SGNativePlayerScreenSections(void) {
    return @[
        SGSection(SGL(@"settings.player.player_screen.header", @"Player screen"), @[
            SGOptionRow(SGL(@"settings.album.artwork_background.title", @"Artwork background"), nil, SGKeyPlayerBackdrop),
            SGOptionRow(SGL(@"settings.player.glass_header_buttons.title", @"Glass header buttons"), nil, SGKeyPlayer),
            SGKillRow(SGL(@"settings.player.disable_canvas.title", @"Disable Canvas"), @"ios-feature-canvas.canvas_enabled"),
            SGFlagRow(SGL(@"settings.player.sheet_style.title", @"Sheet style player"), @"ios-feature-nowplaying.sheet_style_npv"),
            SGFlagRow(SGL(@"settings.player.redesigned_header.title", @"Redesigned header"), @"ios-feature-nowplaying.new_redesign_header_with_context_menu_enabled"),
            SGFlagRow(SGL(@"settings.player.new_slider.title", @"New progress slider"), @"ios-feature-encoreexperiments.new_npv_slider_enabled"),
            SGFlagRow(SGL(@"settings.player.expand_sticky_header.title", @"Expand the sticky header on tap"), @"ios-feature-nowplaying.expand_sticky_header_on_tap"),
        ]),
        SGSection(SGL(@"settings.player.hide_cards.header", @"Hide cards below the player"), @[
            SGHideRow(SGL(@"settings.lyrics.title", @"Lyrics"), nil, SGHideLyricsCard),
            SGHideRow(SGL(@"settings.player.hide.about_artist.title", @"About the artist"), nil, SGHideAboutArtist),
            SGHideRow(SGL(@"settings.player.hide.related_videos.title", @"Related videos"), nil, SGHideRelatedVideos),
            SGHideRow(SGL(@"settings.player.hide.song_dna.title", @"SongDNA"), nil, SGHideSongDNA),
            SGHideRow(SGL(@"settings.player.hide.live_events.title", @"Live events"), nil, SGHideLiveEvents),
            SGHideRow(SGL(@"settings.player.hide.explore_artist.title", @"Explore the artist"), nil, SGHideExploreArtist),
            SGHideRow(SGL(@"settings.player.hide.credits.title", @"Credits"), nil, SGHideCredits),
            SGHideRow(SGL(@"settings.album.hide.merch.title", @"Merch"), nil, SGHideMerch),
            SGHideRow(SGL(@"settings.player.hide.recommendations.title", @"Recommendations"), nil, SGHideRecommendations),
        ]),
        SGSection(SGL(@"settings.player.hide_on_player.header", @"Hide on the player"), @[
            SGHideRow(SGL(@"settings.player.hide.lyrics_preview.title", @"Lyrics preview"), nil, SGHideLyricsInline),
            SGHideRow(SGL(@"settings.localmusic.shuffle", @"Shuffle"), nil, SGHideShuffle),
            SGHideRow(SGL(@"settings.player.ipad.repeat", @"Repeat"), nil, SGHideRepeat),
            SGHideRow(SGL(@"settings.player.hide.add_to_playlist.title", @"Add to playlist"), nil, SGHideAddTo),
            SGHideRow(SGL(@"settings.tabbar.tab.queue", @"Queue"), nil, SGHideQueue),
            SGHideRow(SGL(@"settings.cover_viewer.share", @"Share"), nil, SGHideShare),
            SGHideRow(SGL(@"settings.player.hide.connect.title", @"Connect to a device"), nil, SGHideConnect),
        ]),
    ];
}

SGModRow *SGGlassLyricsRow(void) {
    return SGOptionRow(SGL(@"settings.player.glass_lyrics.title", @"Glass lyrics"), nil, SGKeyLyricsCard);
}

UIViewController *SGQueueSettingsPage(void) {
    return [[SGModPage alloc] initWithTitle:SGL(@"settings.player.queue_devices.title", @"Queue & devices") intro:SGRestartNote sections:@[
        SGSection(SGL(@"settings.player.bottom_sheets.header", @"Bottom sheets"), @[
            SGFlagRow(SGL(@"settings.player.queue_bottom_sheet.title", @"Queue as a bottom sheet"), @"ios-feature-nowplaying.bottom_sheet_queue_enabled"),
            SGFlagRow(SGL(@"settings.player.connect_bottom_sheet.title", @"Connect as a bottom sheet"), @"ios-feature-nowplaying-elements.enable_connect_bottom_sheet"),
            SGFlagRow(SGL(@"settings.player.connect_sheet_switcher.title", @"Connect sheet from the video switcher"), @"ios-playbackcontrol-audiovideoswitcher-impl.enable_connect_bottom_sheet"),
        ]),
        SGSection(SGL(@"settings.tabbar.tab.queue", @"Queue"), @[
            SGFlagRow(SGL(@"settings.player.queue_flip.title", @"Queue flip transition"), @"ios-feature-nowplaying.queue_flip_transition_enabled"),
            SGFlagRow(SGL(@"settings.player.play_next_menu.title", @"Play next in the context menu"), @"ios-feature-queue.is_play_next_context_menu_enabled"),
        ]),
    ] footer:nil];
}
