// The charts behind Listening stats' Top songs, Top artists and Top albums headings, and the rankings the year's
// recap (SGRecap.h) is made of. Pure and Foundation-only, like the adding up in SGPlayLog.h: safe on any thread,
// each call copies the calendar it is given. The Mac harness (harness/listening-stats) runs it.
//
// A play belongs to a period by its `end`, [start, next start), as everywhere in Listening stats. Only music
// counts (SGPlayIsMusic). Entries are ranked as every top list is (SGTopOrder), then by detail, so entries that
// tie on name too keep one order.
#import "SGPlayLog.h"

typedef NS_ENUM(NSInteger, SGChartKind) { SGChartKindSongs, SGChartKindArtists, SGChartKindAlbums };

// How many entries a chart shows, and the comparison period's top that an entry must have been in not to be New.
enum { SGChartLength = 50 };
// A run counts the consecutive periods an entry spent in this top, and is shown from SGChartRunShown periods on.
enum { SGChartRunTop = 5, SGChartRunShown = 2 };

// Songs and local files, which is all the recorder writes down, and imported rows that carry no URI (a basic
// Spotify export has none and leaves podcasts out); not an episode, a show or an audiobook a Retrine backup holds.
BOOL SGPlayIsMusic(SGPlay *play);
// An entry's identity. A song is SGTrackKey. A play has no artist or album URI, so an artist is its name and an
// album its name with its artist, trimmed and compared without case or diacritics. Nil for a play without that
// kind of entry (an album for a play with no album name).
NSString *SGChartKey(SGPlay *play, SGChartKind kind);

@interface SGChartEntry : SGStatEntry
@property (nonatomic, copy) NSString *key;
@property (nonatomic) NSUInteger rank;           // from 1
@property (nonatomic) NSUInteger previousRank;   // in the comparison period's top SGChartLength; 0 when New
@property (nonatomic) NSUInteger run;            // periods in a row in the top SGChartRunTop, this one last; 0 outside it
@end

@interface SGChart : NSObject
@property (nonatomic, copy) NSArray<SGChartEntry *> *entries;   // the top SGChartLength
@property (nonatomic) NSUInteger played;       // different entries played in the period
@property (nonatomic) NSUInteger discovered;   // of those, the ones never played before the period's start
@property (nonatomic) NSUInteger plays;        // the music plays the chart counts
@end

// The chart of `kind` for the period holding `date`, compared with the period of the same kind just before it.
// Nil when the period cannot be represented.
SGChart *SGChartBuild(NSArray<SGPlay *> *plays, SGChartKind kind, SGStatsPeriod period, NSDate *date, NSCalendar *calendar);

// The music plays of one kind of entry that ended before `end`, sorted by end, so many periods of one log are
// ranked without reading the whole log again. Built once per chart or recap, off main.
@interface SGChartLog : NSObject
- (instancetype)initWithPlays:(NSArray<SGPlay *> *)plays kind:(SGChartKind)kind before:(int64_t)end;
// Each entry played in [start, end), keyed by SGChartKey, with its plays and listening time; ranks are not set.
- (NSDictionary<NSString *, SGChartEntry *> *)entriesFrom:(int64_t)start to:(int64_t)end;
// The keys of every entry played before `start`.
- (NSSet<NSString *> *)keysBefore:(int64_t)start;
// The plays that ended in [start, end), in order.
- (NSArray<SGPlay *> *)playsFrom:(int64_t)start to:(int64_t)end;
@end
// `entries` in chart order, at most `top`, each given its rank.
NSArray<SGChartEntry *> *SGChartRank(NSDictionary<NSString *, SGChartEntry *> *entries, NSUInteger top);
