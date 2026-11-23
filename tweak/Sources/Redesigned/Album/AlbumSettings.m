// The redesign's Albums page: Apple Music's animated covers on album pages, whether their downloads run in Low
// Data Mode, and what the redesign takes off the page.
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Shared/AnimatedArtwork/AnimatedArtwork.h"
#import "Album.h"

UIViewController *SGRAlbumSettingsPage(void) {
    return [[SGModPage alloc] initWithTitle:SGL(@"settings.album.title", @"Albums") intro:SGRestartNote sections:@[
        SGNotedSection(SGL(@"settings.album.apple_music.header", @"Apple Music"), @[
            SGSwitchRow(SGL(@"settings.album.animated_covers.title", @"Animated covers"), SGL(@"settings.album.animated_covers.subtitle", @"At the top of an album that has one, about 5 MB each"), SGRKeyAlbumMotion),
            SGOptionRow(SGL(@"settings.lockscreen.low_data.title", @"Download in Low Data Mode"), nil, SGKeyMotionLowData),
        ], @"Only the album's name is sent to Apple Music. A cover stays still in Low Power Mode."),
        SGSection(SGL(@"settings.album.hide_on_page.header", @"Hide on an album's page"), @[
            SGSwitchRow(SGL(@"settings.album.hide_track_artists.title", @"Repeated track artists"), SGL(@"settings.album.hide_track_artists.subtitle", @"The artist under a track when it is the album's own"), SGRKeyAlbumHideTrackArtists),
        ]),
        SGNotedSection(SGL(@"settings.album.hide_under_tracks.header", @"Hide under an album's tracks"), @[
            SGSwitchRow(SGL(@"settings.album.hide.more_by_artist.title", @"More by the artist"), nil, SGRKeyAlbumHideMoreBy),
            SGSwitchRow(SGL(@"settings.album.hide.related_videos.title", @"Related music videos"), nil, SGRKeyAlbumHideVideos),
            SGSwitchRow(SGL(@"settings.tabbar.tab.concerts", @"Concerts"), nil, SGRKeyAlbumHideConcerts),
            SGSwitchRow(SGL(@"settings.album.hide.merch.title", @"Merch"), nil, SGRKeyAlbumHideMerch),
            SGSwitchRow(SGL(@"settings.album.hide.you_might_like.title", @"You might also like"), nil, SGRKeyAlbumHideYouMightLike),
            SGSwitchRow(SGL(@"settings.search_tab.hide.other.title", @"Everything else"), SGL(@"settings.album.hide.everything_else.subtitle", @"Any other section Spotify sends"), SGRKeyAlbumHideOther),
        ], @"Sections are told apart by their English names. With Spotify in another language, Everything else "
           @"covers them all."),
    ] footer:nil];
}
