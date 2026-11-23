// The redesign's Artists page: Apple Music's logo in place of the name on an artist's page, and what the redesign
// takes off the page.
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Artist.h"

UIViewController *SGRArtistSettingsPage(void) {
    return [[SGModPage alloc] initWithTitle:SGL(@"settings.artist.title", @"Artists") intro:SGRestartNote sections:@[
        SGNotedSection(SGL(@"settings.album.apple_music.header", @"Apple Music"), @[
            SGSwitchRow(SGL(@"settings.artist.logos.title", @"Artist logos"), SGL(@"settings.artist.logos.subtitle", @"In place of the name on an artist's page"), SGRKeyArtistLogo),
        ], @"Only the artist's name is sent to Apple Music."),
        SGSection(SGL(@"settings.artist.hide_on_page.header", @"Hide on an artist's page"), @[
            SGSwitchRow(SGL(@"settings.artist.hide.videos.title", @"Videos"), SGL(@"settings.artist.hide.videos.subtitle", @"In the Music list, and in the Video tab"), SGRKeyArtistHideVideos),
            SGSwitchRow(SGL(@"settings.artist.hide.tabs.title", @"Music, Video and Merch tabs"), SGL(@"settings.artist.hide.tabs.subtitle", @"Without them the Music list is the page"), SGRKeyArtistHideTabs),
            SGHideRow(SGL(@"settings.artist.hide.pick.title", @"Artist pick"), nil, SGRKeyArtistHidePick),
            SGHideRow(SGL(@"settings.artist.hide.countdown.title", @"Release countdown"), SGL(@"settings.artist.hide.countdown.subtitle", @"The pre-save of an upcoming release"), SGRKeyArtistHideCountdown),
            SGHideRow(SGL(@"settings.artist.hide.about.title", @"About"), nil, SGRKeyArtistHideAbout),
        ]),
    ] footer:nil];
}
