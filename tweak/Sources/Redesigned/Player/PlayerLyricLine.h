// Player redesign: the line of the lyrics being sung, one line under the cover, while the lyrics are not open
// in the player (PlayerLyricLine.x). A tap on it opens them, as the footer's lyrics glyph does.
//
// While the lyrics' own menu shows translations (SGRKeyLyricsTranslation), the line's translation sits under it,
// smaller and dimmer, when the room holds both; else the line shows alone, as without one.
// With synced lyrics the line replaces Spotify's preview regardless of translation settings.
//
// Threading: main thread only.
#import <UIKit/UIKit.h>
#import "Shared/Lyrics/Lyrics.h"

// The translation shown under `line`: its own, trimmed, while translations are shown; nil with them off, without
// one, or for one that only repeats the line (SGLyricsShownTranslation).
static inline NSString *SGRPlayerLineTranslation(SGKaraokeLine *line, BOOL translationsShown) {
    if (!translationsShown || !line) return nil;
    NSString *translation = [SGLyricsShownTranslation(line) stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return translation.length ? translation : nil;
}

// Whether the line takes the place of Spotify's own lyric preview under the cover: while the line is on
// (`lineOn`), in a player taller than it is wide (`portrait`),
// with synced lines of its own for the playing track (`syncedLines`), the preview is hidden and the line, with its
// translation, is placed as if the preview were not there. Else the preview shows as Spotify has it and the line
// stands down while it does: a track the line has nothing to show for keeps Spotify's lyrics.
static inline BOOL SGRPlayerLineTakesPreview(BOOL lineOn, BOOL portrait, BOOL syncedLines) {
    return lineOn && portrait && syncedLines;
}

// Prefer both lyric rows to the translation; the cover floor is reserved by the caller.
static inline NSInteger SGRPlayerCompactRows(CGFloat available, CGFloat row, CGFloat *translation) {
    if (2 * row + *translation > available) *translation = 0;
    return available >= 2 * row ? 2 : available >= row ? 1 : 0;
}

// Geometry owned by the portrait cover layout; CGRectNull for unknown cover hierarchies.
CGRect SGRPlayerNormalCover(UIView *host, UIView *tilt, CGFloat maxSide);
void SGRPlayerReserveCover(UIView *tilt, CGFloat side);
// A retained, empty floating strip applies to the player's pages, not just
// whichever page is crossing the middle of the pager during a skip.
void SGRPlayerEmptyStripIn(UIView *host);
// All native preview layers beside this page's tilt, including an empty or
// transparent preview that can start showing without another tilt layout.
NSArray<CALayer *> *SGRPlayerPreviewLayers(UIView *column, BOOL *showing);

// The previews to give back: none while the line takes their place (`takes`); else every one it hid (`hidden`, a
// weak table), whether or not it is still under the covers (one a list keeps for reuse included), and the table is
// emptied with them.
static inline NSArray<UIView *> *SGRPlayerPreviewsToGiveBack(NSHashTable<UIView *> *hidden, BOOL takes) {
    if (takes) return @[];
    NSArray<UIView *> *all = hidden.allObjects;
    [hidden removeAllObjects];
    return all;
}

// Off until switched on, read at launch, as the Music app keeps the room under its cover empty; the Player page's
// Controls section has its row (PlayerSettings.m).
#define SGRKeyPlayerLyricLine @"spotifyglass.redesign.player.lyricLine"
BOOL SGRPlayerLyricLineOn(void);
BOOL SGRPlayerLineSmall(void);
void SGRSetPlayerLineSmall(BOOL small);
// The line's place over the title in `view`'s coordinates while it has room there (it then shows whatever synced
// line is sung, unless the lyrics are open); CGRectNull while it has none, is off or the player is not up.
CGRect SGRPlayerLyricLineIn(UIView *view);
// Main-thread hand-over with the field clip, including a late arrival between player layouts.
void SGRPlayerLyricClipChanged(void);
CGRect SGRPlayerVisibleClipLineIn(UIView *view);
void SGRPlayerMotionLineMoved(void);
