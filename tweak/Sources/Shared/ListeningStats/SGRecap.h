// A year of listening as the recap story tells it (RecapStory.m): listening time and plays, the top artists, songs
// and albums, what was played for the first time, active days and the longest streak, and the hour and month with
// the most listening. Pure and Foundation-only like SGTopCharts.h, which ranks it: safe on any thread, and run by
// the Mac harness. A play belongs to a year, and a day, by its `end` in the calendar given; only music counts.
#import "SGTopCharts.h"

// The story's cards, in order. A card whose figures are missing is left out (SGRecap.cards).
typedef NS_ENUM(NSInteger, SGRecapCard) {
    SGRecapCardTotal, SGRecapCardArtists, SGRecapCardSongs, SGRecapCardAlbums, SGRecapCardDiscoveries, SGRecapCardDays, SGRecapCardPeak,
};
// A year has a recap from this many active days (days with a counted play) on; each top list shows this many.
enum { SGRecapActiveDaysNeeded = 30, SGRecapTopLength = 5 };

@interface SGRecapYear : NSObject
@property (nonatomic, strong) NSDateInterval *interval;
@property (nonatomic) NSUInteger activeDays;
@property (nonatomic, readonly) BOOL eligible;
@end
// Every year with music plays, the latest first, each with its active days.
NSArray<SGRecapYear *> *SGRecapYears(NSArray<SGPlay *> *plays, NSCalendar *calendar);

@interface SGRecap : NSObject
@property (nonatomic, strong) NSDateInterval *year;
@property (nonatomic) NSUInteger plays, activeDays;
@property (nonatomic) int64_t ms;
@property (nonatomic, readonly) BOOL eligible;
@property (nonatomic, copy) NSArray<SGChartEntry *> *artists, *songs, *albums;   // the top SGRecapTopLength of each
// Artists and songs first played this year (never before its first day), and the most played of those artists.
@property (nonatomic) NSUInteger newArtists, newSongs;
@property (nonatomic, strong) SGChartEntry *topNewArtist;
// The longest run of consecutive active days inside the year (SGStreaks), its first and last day.
@property (nonatomic) NSUInteger longestStreak;
@property (nonatomic, strong) NSDate *streakStart, *streakEnd;
// The local hour of day (0…23) and the month (its first instant) with the most listening time; the earliest wins a tie.
@property (nonatomic) NSInteger peakHour;
@property (nonatomic) int64_t peakHourMs, peakMonthMs;
@property (nonatomic, strong) NSDate *peakMonth;
@property (nonatomic, copy) NSArray<NSNumber *> *cards;   // SGRecapCard values, in order
@end
// The recap of the year holding `date`. `now` keeps a year still running from counting days to come. Nil when the
// year cannot be represented.
SGRecap *SGRecapBuild(NSArray<SGPlay *> *plays, NSDate *date, NSDate *now, NSCalendar *calendar);

// When the year just ended is announced: on the first SGRecapAnnouncementDays days of the next one.
typedef NS_ENUM(NSInteger, SGRecapAnnouncement) { SGRecapAnnounceOnLaunch, SGRecapAnnounceInSettings, SGRecapAnnounceOff };
enum { SGRecapAnnouncementDays = 14 };
#define SGKeyRecapAnnouncement @"spotifyglass.stats.recap.announce"
// The year number (SGRecapYearNumber) of the last year whose recap was announced; 0 for none.
#define SGKeyRecapAnnouncedYear @"spotifyglass.stats.recap.announced_year"
// A stored value outside the three reads as In Retrine Settings.
SGRecapAnnouncement SGRecapAnnouncementFrom(NSInteger stored);
// The year just ended while `now` is in the announcement days of the next one; nil otherwise.
NSDateInterval *SGRecapAnnouncedYear(NSDate *now, NSCalendar *calendar);
// A year's number in `calendar` (2025), read at its middle so the same year keeps its number in another time zone.
NSInteger SGRecapYearNumber(NSDateInterval *year, NSCalendar *calendar);
// The number as it goes into text: plain digits, without a locale's year format or grouping.
NSString *SGRecapYearTitle(NSDateInterval *year, NSCalendar *calendar);
// The year just ended while it is still to be announced at `now`: in its announcement days, `preference` not Off,
// and `announcedYear` (SGKeyRecapAnnouncedYear) earlier than it; nil otherwise.
NSDateInterval *SGRecapUnannouncedYear(NSDate *now, NSCalendar *calendar, SGRecapAnnouncement preference, NSInteger announcedYear);
// Whether the launch prompt for the recap of `year` may show at `now`: When Spotify opens is chosen and `year` is
// still the one to announce. Checked again just before the prompt shows.
BOOL SGRecapPromptDue(NSDateInterval *year, NSDate *now, NSCalendar *calendar, SGRecapAnnouncement preference, NSInteger announcedYear);
