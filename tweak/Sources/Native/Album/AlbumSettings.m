#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Album.h"

UIViewController *SGAlbumSettingsPage(void) {
    NSArray<SGModSection *> *sections = @[
        SGSection(SGL(@"settings.album.header", @"Header"), @[
            SGOptionRow(SGL(@"settings.album.artwork_background.title", @"Artwork background"), nil, SGKeyAlbumBackdrop),
        ]),
        SGSection(SGL(@"settings.album.hide_in_header.header", @"Hide in the header"), @[
            SGHideRow(SGL(@"settings.album.hide.explore.title", @"Explore (video deck)"), nil, SGHideAlbumExplore),
            SGHideRow(SGL(@"settings.album.hide.add_to_library.title", @"Add to library"), nil, SGHideAlbumAddTo),
            SGHideRow(SGL(@"settings.pixie.menu.download", @"Download"), nil, SGHideAlbumDownload),
            SGHideRow(SGL(@"settings.album.hide.more.title", @"More options"), nil, SGHideAlbumMore),
        ]),
        SGNotedSection(SGL(@"settings.album.native.hide_on_page.header", @"Hide on the page"), @[
            SGHideRow(SGL(@"settings.album.hide.more_by_artist.title", @"More by the artist"), nil, SGHideAlbumMoreBy),
            SGHideRow(SGL(@"settings.album.hide.related_videos.title", @"Related music videos"), nil, SGHideAlbumVideos),
            SGHideRow(SGL(@"settings.tabbar.tab.concerts", @"Concerts"), nil, SGHideAlbumConcerts),
            SGHideRow(SGL(@"settings.album.hide.merch.title", @"Merch"), nil, SGHideAlbumMerch),
            SGHideRow(SGL(@"settings.album.hide.you_might_like.title", @"You might also like"), nil, SGHideAlbumYouMightLike),
        ], @"Works only with Spotify in English."),
    ];
    return [[SGModPage alloc] initWithTitle:SGL(@"settings.album.native.title", @"Album") intro:nil sections:sections footer:nil];
}
