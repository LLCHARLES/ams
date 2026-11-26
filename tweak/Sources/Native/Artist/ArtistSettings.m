#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Artist.h"

UIViewController *SGArtistSettingsPage(void) {
    NSArray<SGModSection *> *sections = @[
        SGSection(SGL(@"settings.artist.photo.header", @"Photo"), @[
            SGOptionRow(SGL(@"settings.artist.photo_fade.title", @"Fade into a blur"), nil, SGKeyArtistPhotoFade),
        ]),
        SGSection(SGL(@"settings.artist.hide_in_header.header", @"Hide in the header"), @[
            SGHideRow(SGL(@"settings.artist.hide.explore.title", @"Explore (video deck)"), nil, SGHideArtistExplore),
            SGHideRow(SGL(@"settings.artist.hide.follow.title", @"Follow"), nil, SGHideArtistFollow),
            SGHideRow(SGL(@"settings.artist.hide.more.title", @"More options"), nil, SGHideArtistMore),
            SGHideRow(SGL(@"settings.artist.hide.shuffle.title", @"Shuffle"), nil, SGHideArtistShuffle),
            SGHideRow(SGL(@"settings.artist.hide.verified_badge.title", @"Verified badge"), nil, SGHideArtistVerified),
            SGHideRow(SGL(@"settings.artist.hide.listeners.title", @"Monthly listeners"), nil, SGHideArtistListeners),
        ]),
        SGSection(SGL(@"settings.artist.tabs.header", @"Tabs"), @[
            SGHideRow(SGL(@"settings.artist.hide.tab_bar.title", @"Hide the tab bar"), nil, SGHideArtistTabBar),
        ]),
        SGNotedSection(SGL(@"settings.artist.native.hide_on_page.header", @"Hide on the page"), @[
            SGHideRow(SGL(@"settings.artist.hide.liked_songs.title", @"Songs you liked"), nil, SGHideArtistLikedSongs),
            SGHideRow(SGL(@"settings.artist.hide.popular.title", @"Popular"), nil, SGHideArtistPopular),
            SGHideRow(SGL(@"settings.artist.hide.pick.title", @"Artist pick"), nil, SGHideArtistPick),
            SGHideRow(SGL(@"settings.artist.hide.releases.title", @"Popular releases"), nil, SGHideArtistReleases),
            SGHideRow(SGL(@"settings.artist.hide.featuring.title", @"Featuring"), nil, SGHideArtistFeaturing),
            SGHideRow(SGL(@"settings.artist.native.hide.music_videos.title", @"Music videos"), nil, SGHideArtistVideos),
            SGHideRow(SGL(@"settings.artist.hide.about.title", @"About"), nil, SGHideArtistAbout),
            SGHideRow(SGL(@"settings.artist.hide.playlists.title", @"Artist playlists"), nil, SGHideArtistPlaylists),
            SGHideRow(SGL(@"settings.artist.hide.fans_like.title", @"Fans also like"), nil, SGHideArtistFansAlsoLike),
            SGHideRow(SGL(@"settings.artist.hide.appears_on.title", @"Appears on"), nil, SGHideArtistAppearsOn),
            SGHideRow(SGL(@"settings.artist.hide.discovered_on.title", @"Discovered on"), nil, SGHideArtistDiscoveredOn),
        ], SGL(@"settings.artist.hide_on_page.note", @"Works only with Spotify in English.")),
        SGSection(SGL(@"settings.artist.spotify_own.header", @"Spotify's own"), @[
            SGFlagRow(SGL(@"settings.artist.share_in_header.title", @"Share button in the header"), @"ios-creator-impl.share_in_action_row_enabled_artist"),
            SGFlagRow(SGL(@"settings.artist.more_in_nav.title", @"More options in the navigation bar"), @"ios-creator-impl.context_menu_in_navigation_bar_enabled_artist"),
            SGFlagRow(SGL(@"settings.artist.top_collaborators.title", @"Top collaborators"), @"ios-creator-impl.is_top_collaborators_enabled"),
            SGFlagRow(SGL(@"settings.artist.artist_facts.title", @"Artist facts"), @"ios-creator-impl.is_artist_facts_enabled"),
        ]),
    ];
    return [[SGModPage alloc] initWithTitle:SGL(@"settings.main.artists.title", @"Artists") intro:SGRestartNote sections:sections footer:nil];
}
