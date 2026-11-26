// The player's settings that do not depend on the look: the lock screen widget's flags.
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "PlayerSettings.h"
#import "SleepTimer.h"
#import "Shared/AnimatedArtwork/AnimatedArtwork.h"
#import "Shared/LockScreenLyrics/LockScreenLyrics.h"
#import "Shared/Lyrics/Lyrics.h"

// The sleep timer's fade, under either look and on every iOS: the Live Activity's Timer tab, the Sleep Timer
// shortcut and its control fade by it, and so does Spotify's own timer (Shared/Player/SpotifySleepTimer.m).
SGModSection *SGPlaybackRulesSection(SGModRow *blockedArtists, SGModRow *blockedSongs) {
    NSArray<NSString *> *fades = SGSleepTimerFadeNames();
    SGModRow *fade = SGMenuRow(SGL(@"settings.playback.timer_fade", @"Sleep timer fade-out"), fades,
                              ^NSString *{ return fades[(NSUInteger)SGSleepTimerFadeChoice()]; },
                              ^(NSInteger index) { SGSetInt(SGKeySleepTimerFade, index); });
    fade.subtitle = SGL(@"settings.player.sleep_fade.subtitle", @"While Labs' Fade out is forced on, Spotify's own timer fades its own way.");
    SGSearchIdentified(fade, SGKeySleepTimerFade);
    return SGNotedSection(SGL(@"settings.playback.rules", @"Playback"), @[fade, blockedArtists, blockedSongs],
                          SGL(@"settings.liveactivity.sleeptimer.footer", @"How long the sound fades before a sleep timer pauses Spotify: the one set from the Timer tab, the Sleep Timer shortcut or Control Center, and Spotify's own from the player's ⋯ menu."));
}

// Widget first: the line in place of the artist (on the Lyrics page too, the same switch) and Like and dislike,
// the one lock screen control a song gets, which the Artwork section's star takes the place of
// (Shared/AnimatedArtwork/LockScreenStar.x locks the flag off). Spotify's flags for podcasts, audiobooks and its
// own lock screen artwork stay on the All flags page: the Artwork section is the mod's.
UIViewController *SGLockScreenWidgetPage(void) {
    SGModRow *likes = SGFlagRow(SGL(@"settings.player.like_dislike.title", @"Like and dislike buttons"), @"ios-feature-lockscreen.like_dislike_enabled");
    likes.subtitle = SGL(@"settings.player.like_dislike.subtitle", @"Off and locked while Switch with the star is on: the star takes their place");
    SGModRow *line = SGChoiceRow(SGL(@"settings.player.lyrics_line.title", @"Lyrics line"), SGL(@"settings.player.lyrics_line.subtitle", @"A line without a translation shows the original"),
                                 SGKeyLockScreenLyricsLine, @[SGL(@"settings.player.lyrics_line.choice.original", @"Original"), SGL(@"settings.player.lyrics_line.choice.translation", @"Translation")], SGLockScreenLyricsLineOriginal);
    line.visible = ^BOOL { return SGFlag(SGKeyLockScreenLyrics, NO); };
    return [[SGModPage alloc] initWithTitle:SGL(@"settings.player.lockscreen.title", @"Lock screen") intro:SGRestartNote sections:@[
        SGSection(SGL(@"settings.player.widget.header", @"Widget"), @[SGLockScreenLyricsRow(), line, likes]),
        SGSection(SGL(@"settings.player.artwork.header", @"Artwork"), SGLockScreenMotionRows()),
    ] footer:nil];
}
