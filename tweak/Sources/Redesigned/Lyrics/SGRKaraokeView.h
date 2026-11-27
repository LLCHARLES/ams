// The redesign's Apple Music style lyrics view, always on, over Spotify's full screen lyrics page
// (KaraokePage.x) and in the redesigned player itself (Redesigned/Player/PlayerLyrics.x). A track
// without synced lyrics keeps Spotify's own lines, where there are any next to it. The lines and the
// clock are Shared/Lyrics/Lyrics.h's.
//
// A player view takes the whole of whatever it is put in and dims every other view in there while it
// has lines to show, so a host it shares with anything else needs a view of its own for it. Sample
// previews leave their siblings alone.
#import <UIKit/UIKit.h>
#import "Shared/Lyrics/Lyrics.h"
#import "LyricsLook.h"

@interface SGRKaraokeView : UIView
// The Lyrics page's preview: `lines` played on a clock of its own, round and round every `length` ms, in
// the look the page sets. It takes no touches and asks nothing of the player, the sources, Genius or Sing.
- (instancetype)initWithSampleLines:(NSArray<SGKaraokeLine *> *)lines length:(NSInteger)length;
// Workshop comparison cards only: nil follows the stored style, as every ordinary preview does.
// Ignored on a player view. Never changes the stored choice.
@property (nonatomic, copy) NSString *sampleStyleIdentifier;
// Hides Spotify's own lyrics next to this view while it has lyrics to show, and brings them back when not.
- (void)syncSiblings;
// A retained but covered player page keeps its viewport, not its rendering clocks.
@property (nonatomic) BOOL renderingSuspended;
// Called as a finger starts to scroll the lines, for a host that hides its controls then.
@property (nonatomic, copy) void (^browsingBegan)(void);
// Called as the finger lifts from a scroll of the lines, with the scroll's vertical velocity (positive toward the
// lines still to come), for a host that hides or brings back its controls by the flick, as the Music app does.
@property (nonatomic, copy) void (^browsingFlicked)(CGFloat velocity);
// Called once the lines go back to following the song after a scroll by hand, or after a tap on a line.
@property (nonatomic, copy) void (^browsingEnded)(void);
// The pronunciation and translation button goes with the host's controls when they are hidden, and Sing's
// mic with it unless keepsSing is set.
@property (nonatomic) BOOL extrasHidden;
// The mic stays when the extras go, for a host that lets it take its own touches while its controls are
// hidden (the player's lines on their own, Redesigned/Player/PlayerLyrics.x), so Sing is always in reach.
@property (nonatomic) BOOL keepsSing;
// Where the sung line rests, in points from the top; 0, the default, rests it at a share of the height. The
// player's lines on their own under its title set it to rest the line where the Music app's does.
@property (nonatomic) CGFloat anchorTop;
// The ascent of the lines' font, so a caller can rest the sung line's baseline rather than its top.
@property (nonatomic, readonly) CGFloat lineAscent;
@property (nonatomic, readonly) BOOL untimed;
// Whether a touch is on a line it would seek to when tapped (not a corner control, a bubble or the credit), for a
// host that lets a tap on the lines stay theirs while its controls are hidden.
- (BOOL)touchIsOnLine:(UITouch *)touch;
// The place it shows in: its words take the size chosen for that place (LyricsLook.h), and follow a change of it at
// once. SGRLyricsPlaceNone, the look's size, until set.
@property (nonatomic) SGRLyricsPlace sizePlace;
// The glass of its corner buttons (the translation menu, the mic) drawn again, for a host that has just faded it in by
// an alpha above it (the player's page opening, or coming back from its queue): UIKit can leave it undrawn after that.
- (void)refreshGlass;
@end

// What sharing a held line says: the line, then "— <title> · <artist>" on the next line, and the song's public
// link on the one after that only while the lyrics are the playing song's own and it is not a local file's.
// A missing title or artist drops it, and with no title the second line goes too. No timestamp.
NSString *SGRLyricsShareText(NSString *line, NSString *title, NSString *artist, NSString *trackID, BOOL playing);
