// Switch to video hidden from the player, under either look (SGKeyHideVideoSwitch, off until switched on).
//
// The switch is the chip Spotify puts over the track's title for a song with a music video, Switch to
// video and, once switched, Switch to audio. Its accessibility identifier is nowplaying-npv-musicvideos-switch:
// in 9.1.78's strings it sits between NowPlaying_ElementsKit's AudioVideoSwitchButtonAdapter and the
// sNowPlayingMusicVideosSwitchToVideo and ...SwitchToAudio strings, and no recorded tree shows it yet. The
// chips are FloatingElementsUnit's (Redesigned/Player/PlayerLyrics.x), a unit of Spotify's player that both
// looks keep, so its pass looks for it there. It goes by alpha, not hidden, since it may sit in one of
// Spotify's stacks (AGENTS.md), and takes no touches and says nothing to VoiceOver.
//
// On 9.1.90 the chip is a NowPlaying_ElementsKit NowPlaying.Button.Primary with that identifier, the one view of an
// Element_UIKit ElementView of AudioVideoElementProps (the device's log, 2026-10-24). The pass hid it, but Spotify
// faded it back in after, so the button is hooked as well and kept at no alpha whatever Spotify sets while it carries
// the identifier, and its element view with it.
#import "Core/SGCore.h"
#import "PlayerSettings.h"

static NSString *const kSwitchIdentifier = @"nowplaying-npv-musicvideos-switch";

static UIView *switchIn(UIView *root, int depth) {
    if ([root.accessibilityIdentifier isEqualToString:kSwitchIdentifier]) return root;
    if (depth > 10) return nil;
    for (UIView *child in root.subviews) {
        UIView *found = switchIn(child, depth + 1);
        if (found) return found;
    }
    return nil;
}

static BOOL isSwitch(UIView *view) {
    return [view.accessibilityIdentifier isEqualToString:kSwitchIdentifier];
}

static void hideSwitch(UIView *videoSwitch) {
    if (videoSwitch.alpha != 0) videoSwitch.alpha = 0;
    if (videoSwitch.userInteractionEnabled) videoSwitch.userInteractionEnabled = NO;
    if (!videoSwitch.accessibilityElementsHidden) videoSwitch.accessibilityElementsHidden = YES;
    UIView *element = videoSwitch.superview;
    if ([NSStringFromClass(element.class) containsString:@"AudioVideoElementProps"]) {
        if (element.alpha != 0) element.alpha = 0;
        if (element.userInteractionEnabled) element.userInteractionEnabled = NO;
    }
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        SGLog(@"player: Switch to video hidden, %@ in %@", NSStringFromClass(videoSwitch.class), NSStringFromClass(element.class));
    });
}

%hook _TtCCO22NowPlaying_ElementsKit10NowPlaying6Button7Primary
- (void)didMoveToWindow {
    %orig;
    if (isSwitch((UIView *)self)) hideSwitch((UIView *)self);
}
- (void)layoutSubviews {
    %orig;
    if (isSwitch((UIView *)self)) hideSwitch((UIView *)self);
}
- (void)setAlpha:(CGFloat)alpha {
    %orig(isSwitch((UIView *)self) ? 0 : alpha);
}
%end

%hook _TtC20NowPlaying_ModesImpl20FloatingElementsUnit
- (void)viewDidLayoutSubviews {
    %orig;
    UIView *videoSwitch = switchIn(((UIViewController *)self).viewIfLoaded, 0);
    if (videoSwitch) hideSwitch(videoSwitch);
}
%end

%ctor {
    if (!SGHidden(SGKeyHideVideoSwitch)) return;
    %init;
    SGRequireClasses(@[@"_TtC20NowPlaying_ModesImpl20FloatingElementsUnit", @"_TtCCO22NowPlaying_ElementsKit10NowPlaying6Button7Primary"]);
}
