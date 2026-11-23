// The now playing bar's rows of the redesign, the Mini player section of the Player page
// (Redesigned/Player/PlayerSettings.m puts them there).
#import "Settings/SGSourcesPage.h"
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Redesigned/Navbar/Navbar.h"
#import "NowPlayingBar.h"

NSArray<SGModRow *> *SGRNowPlayingBarRows(void) {
    // The tab bar reads the switch as each scroll goes; a bar minimized when it goes off grows back at once.
    SGModRow *minimize = SGSwitchRow(SGL(@"ui.apple.music.style.58eee0", @"Apple Music style"), SGL(@"settings.nowplayingbar.minimize.subtitle", @"Between two tabs as a page scrolls down"), SGRKeyNavbarMinimize);
    minimize.changed = ^(BOOL on) {
        if (!on) SGRSetTabBarMinimized(NO, NO);
        SGRRefreshTabBar();
    };
    SGModRow *inlineConnect = SGOptionRow(SGL(@"ui.device.button.70d9a4", @"Device button"), SGL(@"settings.nowplayingbar.device_button.subtitle", @"Kept on the bar between the tabs"), SGRKeyBarInlineConnect);
    inlineConnect.waitsOn = SGRKeyNavbarMinimize;
    return @[
        minimize,
        inlineConnect,
        SGHideRow(SGL(@"settings.nowplayingbar.hide_connect.title", @"Hide the device button"), SGL(@"settings.nowplayingbar.hide_device_button.subtitle", @"On the full now playing bar"), SGRHideBarConnect),
        // Spotify's own flag for the bar's save button, forced off: Spotify leaves the button out.
        SGKillRow(SGL(@"settings.nowplayingbar.hide_like.title", @"Hide the like button"), @"ios-feature-nowplayingbar.add_button"),
    ];
}

// Native redesign's mini player (Redesigned/Navbar/SystemTabs.x): Apple Music style (UIKit's tab bar minimizes as a page
// scrolls), the swipe and the Skip button, and the AirPlay button beside play, each on a key of its own. The glass bar's
// rows are left out: that bar is not up then.
UIViewController *SGRMiniPlayerSettingsPage(void) {
    SGModRow *minimize = SGSwitchRow(SGL(@"ui.apple.music.style.58eee0", @"Apple Music style"), SGL(@"ui.the.tab.bar.shrinks.cdd004", @"The tab bar shrinks as a page scrolls down"), SGRKeyNavbarMinimize);
    SGModRow *swipe = SGSwitchRow(SGL(@"ui.swipe.to.skip.3cb185", @"Swipe to skip"), SGL(@"ui.sideways.on.the.mini.b8b9b4", @"Sideways on the mini player"), SGRKeyMiniPlayerSwipe);
    // The buttons beside the title, dragged into their order, the ones below the line off (Settings/SGSourcesPage.h; its
    // owner, 2026-11-06). Play stays on.
    SGModRow *buttons = SGPageRow(SGL(@"settings.player.buttons.header", @"Buttons"), ^UIViewController *{
        NSArray<SGSource *> *all = @[
            [SGSource sourceWithKey:SGRMiniButtonAirPlay name:@"AirPlay" detail:@"The output's device"],
            [SGSource sourceWithKey:SGRMiniButtonStar name:@"Star" detail:@"Add to Liked Songs"],
            [SGSource sourceWithKey:SGRMiniButtonPlay name:@"Play" detail:@"Always shown"],
            [SGSource sourceWithKey:SGRMiniButtonNext name:@"Skip" detail:@"The next song"],
        ];
        return SGSourcesPageMake(@"Buttons", @"Left to right on the mini player, beside the title. Drag to reorder; the ones "
                                             @"below the line are off. AirPlay and Star step aside while the title would be "
                                             @"left too short; in the tab bar's row only play shows.",
                                 all, ^NSArray<NSString *> * { return SGRMiniPlayerButtons(); },
                                 ^(NSArray<NSString *> *keys) { SGRSetMiniPlayerButtons(keys); });
    });
    buttons.value = ^NSString * { return [NSString stringWithFormat:@"%lu", (unsigned long)SGRMiniPlayerButtons().count]; };
    return [[SGModPage alloc] initWithTitle:SGL(@"settings.player.mini_player.header", @"Mini player") intro:nil sections:@[
        SGNotedSection(nil, @[minimize, swipe, buttons],
                       @"Apple Music style moves the mini player into the tab bar's row as you scroll down. Swipe to skip pages to the "
                       @"next or previous song; on the player, a sideways swipe on the title does the same."),
    ] footer:nil];
}
