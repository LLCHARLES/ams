// Player redesign: the line under the cover (PlayerLyricLine.x) cut to the room it has, and the moment it can next
// change. Each portion holds up to two rows at full size, except a single overwide word shown on its own.
// A line timed by the word shows the portion holding the
// word being sung and moves on with the words; a line timed only by the line splits its own duration evenly across
// its portions. No portion is ever cut in the middle of a word.
//
// The portions are kept per line, width and font: the same line laid out again is measured once. A font is compared
// whole, so a change of the text size or of Bold Text measures again rather than reading the last font's portions.
//
// Threading: main thread only (the cache is unsynchronized).
#import <UIKit/UIKit.h>

@class SGKaraokeLine;

// The smallest share for a single overwide word or a one-row translation.
extern const CGFloat SGRLyricMinScale;   // 0.85
// The label's font for a portion shown at `scale` of the line's own font.
UIFont *SGRLyricFontAtScale(UIFont *font, CGFloat scale);

// One piece of a line as the label shows it: its text, the font it is drawn at, and when it is shown, in ms of the
// track (the Lyrics delay is not taken off).
@interface SGRLyricPortion : NSObject
@property (nonatomic, copy, readonly) NSString *text;
@property (nonatomic, readonly) CGFloat scale;
@property (nonatomic, readonly) NSInteger start, end;
@end

// The two-row portions of `line` for a label `width` wide with `font`. Empty for a line without words. `width` of 0 measures nothing
// yet and gives one portion at full size.
NSArray<SGRLyricPortion *> *SGRLyricPortions(SGKaraokeLine *line, CGFloat width, UIFont *font);
NSArray<SGRLyricPortion *> *SGRLyricPortionsInRows(SGKaraokeLine *line, CGFloat width, UIFont *font, NSInteger rows);
// The portion shown at `ms` of the track: the one holding the word being sung, or the share of the line's time that
// `ms` falls in. 0 for an empty or not yet begun line.
NSInteger SGRLyricPortionAt(NSArray<SGRLyricPortion *> *portions, NSInteger ms);

// How long until the line can next change, and how much the timer may drift.
typedef struct {
    NSTimeInterval wait;
    NSTimeInterval tolerance;
} SGRLyricWait;
extern const NSTimeInterval SGRLyricMinWait;       // 0.02
extern const NSTimeInterval SGRLyricMaxWait;       // 0.5
extern const NSTimeInterval SGRLyricMaxTolerance;  // 0.1

// The wait until the next transition of the line shown, whichever comes first: the next portion of the line being sung,
// the next line's start, or an end of any line still to come (a retained line's sung end can be the next thing to
// happen). `positionMs` is the player's position (SGKaraokePositionMs, before the Lyrics delay), `delayMs` the Lyrics
// delay the line is read at, and `rate` the speed the song's time runs at, 0 while the song is not moving. Only a
// transition still in the future is aimed at: one further off than SGRLyricMaxWait, and none at all, is the fallback
// of SGRLyricMaxWait with its tolerance, which no shorter wait takes, and nothing is ever aimed at SGRLyricMinWait
// again without a new transition.
SGRLyricWait SGRLyricLineWait(NSArray<SGKaraokeLine *> *ordered, NSInteger positionMs, NSInteger delayMs,
                              CGFloat width, UIFont *font, double rate);
SGRLyricWait SGRLyricLineWaitInRows(NSArray<SGKaraokeLine *> *ordered, NSInteger positionMs, NSInteger delayMs,
                                    CGFloat width, UIFont *font, double rate, NSInteger rows);

// How far a playing report may land from where the armed timer was heading before it is taken for a seek.
extern const NSInteger SGRLyricReportSlack;   // 500 ms

// Whether the player's report of `reportedMs` at `reportedRate` asks the timer to be aimed again, the timer having
// been armed at `armedMs` at `armedRate` `elapsed` seconds ago. A rate below 1 that is not the armed one is a pause or
// a resume, which re-aims whatever the position says: a resume is often reported at the very place the song stopped,
// where the paused timer is the wrong one. Paused, any move of the place is a seek, however small; playing, only one
// that is not where the armed timer was heading, by more than the slack, is.
BOOL SGRLyricRearmNeeded(NSInteger armedMs, double armedRate, NSInteger reportedMs, double reportedRate,
                         NSTimeInterval elapsed);
