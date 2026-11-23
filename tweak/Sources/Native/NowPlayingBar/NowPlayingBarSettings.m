#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "NowPlayingBar.h"

UIViewController *SGNowPlayingBarSettingsPage(void) {
    return [[SGModPage alloc] initWithTitle:SGL(@"settings.nowplayingbar.title", @"Now playing bar") intro:SGRestartNote sections:@[
        SGSection(nil, @[
            SGHideRow(SGL(@"settings.nowplayingbar.hide_connect.title", @"Hide the device button"), nil, SGHideBarConnect),
        ]),
        SGSection(SGL(@"settings.nowplayingbar.spotify_flags.header", @"Spotify's flags"), @[
            SGFlagRow(SGL(@"settings.nowplayingbar.two_lines_info.title", @"Two lines of track info"), @"ios-feature-nowplayingbar.two_lines_information_unit"),
            SGFlagRow(SGL(@"settings.nowplayingbar.save_button.title", @"Save button"), @"ios-feature-nowplayingbar.add_button"),
            SGFlagRow(SGL(@"settings.nowplayingbar.queue_badge.title", @"Queue badge"), @"ios-feature-nowplayingbar.queue_badge"),
            SGFlagRow(SGL(@"settings.nowplayingbar.hold_drag_resize.title", @"Hold and drag to resize"), @"ios-feature-nowplayingbar.hold_and_drag_to_resize"),
            SGFlagRow(SGL(@"settings.nowplayingbar.video_miniplayer.title", @"Video in the mini player"), @"ios-feature-nowplaying.video_in_miniplayer"),
            SGFlagRow(SGL(@"settings.nowplayingbar.bar_to_cover_animation.title", @"Bar to cover art animation"), @"ios-feature-nowplaying.bartocoverart_animation_enabled"),
            SGFlagRow(SGL(@"settings.nowplayingbar.miniplayer_transition_animations.title", @"Mini player transition animations"), @"ios-feature-nowplaying.miniplayer_transition_animations"),
        ]),
    ] footer:nil];
}
