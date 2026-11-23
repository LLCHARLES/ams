// Redesigned opts in to Spotify's video chip; Native keeps it unless explicitly hidden.
//
// The switch is the chip Spotify puts over the track's title for a song with a music video, Switch to
// video and, once switched, Switch to audio. Its accessibility identifier is nowplaying-npv-musicvideos-switch:
// the chips are FloatingElementsUnit's (Redesigned/Player/PlayerLyrics.x), a unit of Spotify's player
// that both looks keep. Remove the chip on every layout pass where it is found: Spotify can restore
// its alpha with its own fades or re-add it later. Detaching it also removes its touches and VoiceOver
// presence, without setting hidden on Spotify's stacks (AGENTS.md).
#import "Core/SGCore.h"
#import "PlayerSettings.h"
#import "Settings/SGModPage.h"

SGModRow *SGNativeVideoSwitchRow(void) {
    SGModRow *video = SGHideRow(SGL(@"settings.player.hide_video_switch.title", @"Switch to video"), SGL(@"settings.player.hide_video_switch.subtitle", @"The chip over the title of a song with a music video"), SGKeyHideVideoSwitch);
    video.readSwitch = ^BOOL { return SGVideoSwitchHiddenForLook(NO); };
    return video;
}

static UIView *switchIn(UIView *root, int depth) {
    if ([root.accessibilityIdentifier isEqualToString:SGVideoSwitchIdentifier]) return root;
    if (depth > 10) return nil;
    for (UIView *child in root.subviews) {
        UIView *found = switchIn(child, depth + 1);
        if (found) return found;
    }
    return nil;
}

%hook _TtC20NowPlaying_ModesImpl20FloatingElementsUnit
- (void)viewDidLayoutSubviews {
    %orig;
    // Read on each pass so the switch applies without a relaunch; off, Spotify's chip is left alone.
    if (!SGVideoSwitchHidden()) return;
    UIView *videoSwitch = switchIn(((UIViewController *)self).viewIfLoaded, 0);
    if (!videoSwitch) return;
    static BOOL logged;
    if (!logged) {
        logged = YES;
        SGLog(@"player: Switch to video hidden, %@ %@", NSStringFromClass(videoSwitch.class), NSStringFromCGRect(videoSwitch.frame));
    }
    [videoSwitch removeFromSuperview];
}
%end

%ctor {
    %init;
    SGRequireClasses(@[@"_TtC20NowPlaying_ModesImpl20FloatingElementsUnit"]);
}
