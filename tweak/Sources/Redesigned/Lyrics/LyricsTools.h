// The redesign's lyrics tools, opened from the lyrics' corner menu (SGRKaraokeView.m):
//
//     Sync           a sheet moving the playing song's lines earlier or later, and those of every song on the
//                    headphones or speaker it plays through, on top of the Lyrics page's Delay (Shared/Lyrics)
//     Search LRCLIB  a sheet searching LRCLIB by title and artist and pinning the lyrics picked to the song, or
//                    taking the pin off so the sources choose again (Shared/LyricsSources)
//     Keep screen on the screen does not lock while lyrics are shown and the song plays
//
// The sheets apply at once. Main thread only.
#import <UIKit/UIKit.h>

void SGRShowLyricsSync(NSString *trackID);
void SGRShowLyricsSearch(NSString *trackID);
// What the menu's Sync item says under its name: the offsets in effect for the song, nil for none.
NSString *SGRLyricsSyncSummary(NSString *trackID);
// Search Lyrics for the player's ⋯ menu (Redesigned/Player/PlayerMenu.m), so a song the sources found nothing
// for, which has no lyrics view and so no corner menu, can still be given some; nil without a track.
UIAction *SGRLyricsSearchAction(NSString *trackID);

// On until switched off.
#define SGRKeyLyricsKeepAwake @"spotifyglass.redesign.lyrics.keepAwake"
#define SGRKeyLyricsFullRate @"spotifyglass.redesign.lyrics.fullRate"
BOOL SGRLyricsKeepAwakeOn(void);
// A lyrics view holding the screen awake, or letting it go; the idle timer is off while any view holds it.
void SGRLyricsHoldAwake(id holder, BOOL hold);
@class SGModRow;
SGModRow *SGRLyricsKeepAwakeRow(void);
SGModRow *SGRLyricsFullRateRow(void);
