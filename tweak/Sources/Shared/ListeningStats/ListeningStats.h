// Listening stats (Mod Settings > Listening stats), under either look: plays counted on the phone as they
// happen, Spotify's own data export merged in, and for a calendar week, month or year stepped through (or
// all time) the listening time, a chart by day or month, hourly totals and the top tracks, artists and
// albums, under a card of the current and best local calendar streaks. Retrine JSON can round-trip history;
// Spotify JSON/ZIP and selected folders of JSON can be imported without an account.
//
//     SGPlayLog.m            the log, the export's parsers and the adding up; the Mac harness runs it
//     SGTopCharts.m          the chart a Top heading opens: ranks, moves, New, runs, discoveries (Mac harness too)
//     SGRecap.m              a year's recap and when it is announced (Mac harness too)
//     ListeningStats.x       the player watched, a play written down once it counts
//     ListeningStatsPage.m   the page, and the export picked and imported
//     TopChartPage.m         the chart's page
//     RecapStory.m           the Recap years, the story of cards and its share, the announcement prompt
//
// The append-only TSV stays in Application Support, out of the settings backup. Only an explicit
// Export history action gives a Retrine JSON copy to the system document exporter.
// Threading: main thread only.
#import <UIKit/UIKit.h>

@class SGPlayLog;

// Plays are written down unless this is switched off; it applies at once.
#define SGKeyListeningStats @"spotifyglass.stats.record"

SGPlayLog *SGListeningLog(void);
NSString *SGListeningStatsSummary(void);
UIViewController *SGListeningStatsPage(void);
