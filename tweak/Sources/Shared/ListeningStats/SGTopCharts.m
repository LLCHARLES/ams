// SGTopCharts.h says what a chart is.
#import "SGTopCharts.h"
#include <stdlib.h>

@implementation SGChartEntry
@end
@implementation SGChart
@end

BOOL SGPlayIsMusic(SGPlay *play) {
    NSString *uri = play.uri;
    return !uri.length || [uri hasPrefix:@"spotify:track:"] || [uri hasPrefix:@"spotify:local:"];
}

// Names repeat over a log thousands of times, so each is folded once per log.
static NSString *folded(NSString *text, NSMutableDictionary<NSString *, NSString *> *memo) {
    NSString *known = memo[text];
    if (known) return known;
    NSString *trimmed = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *result = [trimmed stringByFoldingWithOptions:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch locale:nil];
    memo[text] = result;
    return result;
}

static NSString *chartKey(SGPlay *play, SGChartKind kind, NSMutableDictionary<NSString *, NSString *> *memo) {
    if (kind == SGChartKindSongs) return SGTrackKey(play);
    NSString *artist = folded(play.artist ?: @"", memo);
    if (kind == SGChartKindArtists) return artist.length ? artist : nil;
    NSString *album = folded(play.album ?: @"", memo);
    return album.length ? [NSString stringWithFormat:@"%@\x1f%@", album, artist] : nil;
}

NSString *SGChartKey(SGPlay *play, SGChartKind kind) {
    return chartKey(play, kind, [NSMutableDictionary dictionary]);
}

NSArray<SGChartEntry *> *SGChartRank(NSDictionary<NSString *, SGChartEntry *> *entries, NSUInteger top) {
    NSArray<SGChartEntry *> *sorted = [entries.allValues sortedArrayUsingComparator:^NSComparisonResult(SGChartEntry *a, SGChartEntry *b) {
        NSComparisonResult order = SGTopOrder(a, b);
        // Two albums of one name by different artists still come out in the same order every time.
        return order != NSOrderedSame ? order : [a.detail ?: @"" localizedCaseInsensitiveCompare:b.detail ?: @""];
    }];
    NSArray<SGChartEntry *> *ranked = [sorted subarrayWithRange:NSMakeRange(0, MIN(top, sorted.count))];
    [ranked enumerateObjectsUsingBlock:^(SGChartEntry *entry, NSUInteger i, BOOL *stop) { entry.rank = i + 1; }];
    return ranked;
}

typedef struct { int64_t end; NSUInteger index; } SGChartRow;

@implementation SGChartLog {
    NSArray<SGPlay *> *_plays;
    NSArray *_keys;   // by the plays' index; NSNull for a play this kind does not count
    SGChartKind _kind;
    SGChartRow *_rows;
    NSUInteger _count;
}

- (instancetype)initWithPlays:(NSArray<SGPlay *> *)plays kind:(SGChartKind)kind before:(int64_t)end {
    if (!(self = [super init])) return nil;
    _plays = [plays copy];
    _kind = kind;
    NSMutableDictionary<NSString *, NSString *> *memo = [NSMutableDictionary dictionary];
    NSMutableArray *keys = [NSMutableArray arrayWithCapacity:_plays.count];
    _rows = calloc(MAX((NSUInteger)1, _plays.count), sizeof(SGChartRow));
    if (!_rows) return nil;
    [_plays enumerateObjectsUsingBlock:^(SGPlay *play, NSUInteger i, BOOL *stop) {
        NSString *key = play.end < end && SGPlayIsMusic(play) ? chartKey(play, kind, memo) : nil;
        [keys addObject:key ?: (id)NSNull.null];
        if (key) self->_rows[self->_count++] = (SGChartRow){play.end, i};
    }];
    _keys = keys;
    // By end, then by the log's order, so equal ends keep the order they were written in.
    qsort_b(_rows, _count, sizeof(SGChartRow), ^int(const void *a, const void *b) {
        const SGChartRow *x = a, *y = b;
        if (x->end != y->end) return x->end < y->end ? -1 : 1;
        return x->index < y->index ? -1 : x->index > y->index;
    });
    return self;
}

- (void)dealloc {
    free(_rows);
}

// The first row ending at or after `time`.
- (NSUInteger)firstAt:(int64_t)time {
    NSUInteger lo = 0, hi = _count;
    while (lo < hi) {
        NSUInteger mid = lo + (hi - lo) / 2;
        if (_rows[mid].end < time) lo = mid + 1; else hi = mid;
    }
    return lo;
}

- (NSDictionary<NSString *, SGChartEntry *> *)entriesFrom:(int64_t)start to:(int64_t)end {
    NSMutableDictionary<NSString *, SGChartEntry *> *entries = [NSMutableDictionary dictionary];
    for (NSUInteger i = [self firstAt:start]; i < _count && _rows[i].end < end; i++) {
        SGPlay *play = _plays[_rows[i].index];
        NSString *key = _keys[_rows[i].index];
        SGChartEntry *entry = entries[key];
        if (!entry) {
            entry = [SGChartEntry new];
            entry.key = key;
            entry.name = _kind == SGChartKindSongs ? play.title : _kind == SGChartKindArtists ? play.artist : play.album;
            entry.detail = _kind == SGChartKindArtists ? nil : play.artist;
            entries[key] = entry;
        }
        entry.plays++;
        entry.ms += play.ms;
    }
    return entries;
}

- (NSSet<NSString *> *)keysBefore:(int64_t)start {
    NSMutableSet<NSString *> *keys = [NSMutableSet set];
    for (NSUInteger i = 0, n = [self firstAt:start]; i < n; i++) [keys addObject:_keys[_rows[i].index]];
    return keys;
}

- (NSArray<SGPlay *> *)playsFrom:(int64_t)start to:(int64_t)end {
    NSMutableArray<SGPlay *> *plays = [NSMutableArray array];
    for (NSUInteger i = [self firstAt:start]; i < _count && _rows[i].end < end; i++) [plays addObject:_plays[_rows[i].index]];
    return plays;
}

@end

static int64_t unixSeconds(NSDate *date) {
    return (int64_t)floor(date.timeIntervalSince1970);
}

SGChart *SGChartBuild(NSArray<SGPlay *> *plays, SGChartKind kind, SGStatsPeriod period, NSDate *date, NSCalendar *calendar) {
    NSCalendar *cal = [calendar copy];
    NSDateInterval *shown = SGPeriodInterval(period, date, cal);
    if (!shown) return nil;
    int64_t start = unixSeconds(shown.startDate), end = unixSeconds(shown.endDate);
    SGChartLog *log = [[SGChartLog alloc] initWithPlays:plays kind:kind before:end];
    if (!log) return nil;
    NSDictionary<NSString *, SGChartEntry *> *played = [log entriesFrom:start to:end];
    SGChart *chart = [SGChart new];
    chart.played = played.count;
    NSSet<NSString *> *before = [log keysBefore:start];
    for (NSString *key in played) {
        if (![before containsObject:key]) chart.discovered++;
        chart.plays += played[key].plays;
    }
    NSArray<SGChartEntry *> *ranked = SGChartRank(played, SGChartLength);

    NSDateInterval *previous = SGPeriodStep(period, shown.startDate, -1, cal);
    NSMutableDictionary<NSString *, SGChartEntry *> *running = [NSMutableDictionary dictionary];
    for (SGChartEntry *entry in ranked) {
        if (entry.rank <= SGChartRunTop) {
            entry.run = 1;
            running[entry.key] = entry;
        }
    }
    if (previous) {
        NSDictionary<NSString *, SGChartEntry *> *last = [log entriesFrom:unixSeconds(previous.startDate) to:unixSeconds(previous.endDate)];
        NSMutableDictionary<NSString *, NSNumber *> *lastRanks = [NSMutableDictionary dictionary];
        for (SGChartEntry *entry in SGChartRank(last, SGChartLength)) lastRanks[entry.key] = @(entry.rank);
        for (SGChartEntry *entry in ranked) entry.previousRank = lastRanks[entry.key].unsignedIntegerValue;
    }
    // Back one whole period at a time while any of this period's top is still in that one's; a period with no
    // plays has no top, which ends every run.
    for (NSDateInterval *at = previous; at && running.count; at = SGPeriodStep(period, at.startDate, -1, cal)) {
        NSSet<NSString *> *top = [NSSet setWithArray:[SGChartRank([log entriesFrom:unixSeconds(at.startDate) to:unixSeconds(at.endDate)], SGChartRunTop) valueForKey:@"key"]];
        for (NSString *key in running.allKeys) {
            if ([top containsObject:key]) running[key].run++;
            else [running removeObjectForKey:key];
        }
    }
    chart.entries = ranked;
    return chart;
}
