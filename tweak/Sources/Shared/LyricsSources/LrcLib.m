// LRCLIB, the floor of the order. It is an open library with no key and no catalog to license, so
// it holds what the rest cannot: the tracks Apple's word by word program never reached, and the
// ones Musixmatch may show nobody. It mostly times lines and not words, which is the whole point of
// putting it last — the estimate inside a line is still a sweep, where Spotify's own lyrics only
// scroll. A record someone has timed by the word carries a Lyricsfile too (Lyricsfile.m), read first.
//
// Its /api/get wants the length to agree almost exactly and answers 404 otherwise, so a miss falls
// back to /api/search, which answers with whole recordings to pick the closest of. LRCLIB asks that
// clients say who they are, and the mod does.
#import "Core/SGCore.h"
#import "LyricsSources.h"

static NSString *const kGet = @"https://lrclib.net/api/get";
static NSString *const kSearch = @"https://lrclib.net/api/search";
// Line timing is only worth taking from a recording of about the same length as the one playing.
static const NSInteger kLengthSlack = 4;
static const NSUInteger kMostTimedRows = 4000;

static NSDictionary<NSString *, NSString *> *headers(void) {
    return @{@"User-Agent": @"Retrine " @SG_VERSION};
}

// Bound transport before JSON allocation, and each sheet before ranking or LRC conversion.
static void getJSON(SGLyricsRequestContext *context, NSURL *url, id (^transform)(id), void (^done)(id)) {
    SGLyricsSourceRequestIn(context, url, headers(), nil, ^(NSData *data, NSInteger status) {
        SGLyricsTransform(^id {
            id reply = status == 200 && data.length ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
            if (status == 200 && !reply) [context noteFailure:YES];
            return transform(reply);
        }, done);
    });
}

static BOOL boundedSheet(id text) {
    if (![text isKindOfClass:NSString.class]) return YES;
    if ([text length] > 256 * 1024 || [text lengthOfBytesUsingEncoding:NSUTF8StringEncoding] > 256 * 1024) return NO;
    __block NSUInteger lines = 0;
    [text enumerateSubstringsInRange:NSMakeRange(0, [text length])
                            options:NSStringEnumerationByLines | NSStringEnumerationSubstringNotRequired
                         usingBlock:^(NSString *line, NSRange range, NSRange enclosing, BOOL *stop) {
        if (++lines > 4000) *stop = YES;
    }];
    return lines <= 4000;
}

static BOOL boundedRecord(id record) {
    return [record isKindOfClass:NSDictionary.class] &&
        boundedSheet(record[@"syncedLyrics"]) && boundedSheet(record[@"plainLyrics"]);
}

// A record's length in seconds, or 0 for none: the bounds above say nothing about it, and a record
// whose duration is null spells that length as NSNull.
static NSInteger secondsIn(id record) {
    double seconds;
    return [record isKindOfClass:NSDictionary.class] && SGLyricsNumber(record[@"duration"], &seconds)
        ? (NSInteger)seconds : 0;
}

// [00:34.30] Look — the timestamp in minutes, seconds and hundredths, or thousandths where a line
// carries three digits (SGLyricsLRCStamp in LyricsSources.h). A line may be stamped more than once when
// it is sung more than once, and the tags LRC opens with ([ar:…], [length:…]) are not timestamps, so
// they fall out on their own.
static NSArray<SGKaraokeLine *> *linesFromLRC(NSString *lrc) {
    NSRegularExpression *stamp = SGLyricsLRCStamp();
    NSMutableArray<NSDictionary *> *stamped = [NSMutableArray array];
    for (NSString *row in [lrc componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
        NSArray<NSTextCheckingResult *> *found = [stamp matchesInString:row options:0 range:NSMakeRange(0, row.length)];
        // Only the stamps a line opens with are its own; one further in is part of the words.
        NSUInteger end = 0;
        NSMutableArray<NSNumber *> *at = [NSMutableArray array];
        for (NSTextCheckingResult *match in found) {
            if (match.range.location != end) break;
            end = NSMaxRange(match.range);
            if (stamped.count + at.count >= kMostTimedRows) return nil;
            [at addObject:@(SGLyricsLRCStampMs(row, match))];
        }
        if (!at.count) continue;
        NSString *text = [[row substringFromIndex:end] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        for (NSNumber *ms in at) [stamped addObject:@{@"ms": ms, @"text": text}];
    }
    if (!stamped.count) return nil;
    [stamped sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [a[@"ms"] compare:b[@"ms"]];
    }];
    // The empty rows stay in: they are the breaks, and each one is the end of the line before it.
    NSMutableArray<NSNumber *> *starts = [NSMutableArray array];
    NSMutableArray<NSString *> *texts = [NSMutableArray array];
    for (NSDictionary *row in stamped) {
        [starts addObject:row[@"ms"]];
        [texts addObject:row[@"text"]];
    }
    return SGKaraokeEstimatedLines(starts, texts);
}

// Without word sync a record's Lyricsfile only repeats its LRC's line times, so it is not read.
// Whether a record has words to read: it says it times them, and it is not an instrumental.
static BOOL timesWords(NSDictionary *record) {
    return [record isKindOfClass:NSDictionary.class] && [record[@"hasWordSync"] isEqual:@YES] &&
        !([record[@"instrumental"] isKindOfClass:NSNumber.class] && [record[@"instrumental"] boolValue]);
}

SGLyricsResult *SGLyricsLRCResult(NSString *lrc) {
    return SGLyricsResultWithLines([lrc isKindOfClass:NSString.class] ? linesFromLRC(lrc) : nil, nil);
}

SGLyricsResult *SGLyricsPlainResult(NSArray<NSString *> *rows) {
    NSMutableArray<NSNumber *> *starts = [NSMutableArray array];
    NSMutableArray<NSString *> *texts = [NSMutableArray array];
    for (NSString *row in rows) {
        [starts addObject:@0];
        [texts addObject:row.length ? row : @"♪"];
    }
    SGLyricsResult *result = [SGLyricsResult new];
    result.starts = starts;
    result.texts = texts;
    result.karaokeLines = SGKaraokeStaticLines(texts);
    return result;
}

// wordLines: the record's Lyricsfile as lines, nil when it has none that reads.
static SGLyricsResult *resultFrom(NSDictionary *record, NSArray<SGKaraokeLine *> *wordLines) {
    if (!boundedRecord(record)) return nil;
    SGLyricsResult *result;
    if ([record[@"instrumental"] isKindOfClass:NSNumber.class] && [record[@"instrumental"] boolValue]) {
        result = [SGLyricsResult new];
        result.instrumental = YES;
    } else {
        result = SGLyricsResultWithLines(wordLines, nil);
        if (!result) {
            result = SGLyricsLRCResult(record[@"syncedLyrics"]);
        }
        if (!result.karaokeLines.count) result = SGLyricsPlainTextResult(record[@"plainLyrics"], @"LRCLIB");
        if (!result.karaokeLines.count) return nil;
    }
    result.provider = @"LRCLIB";
    result.pageProvider = @"LRCLIB";
    return result;
}

SGLyricsResult *SGLrcLibRecordResult(NSDictionary *record) {
    return resultFrom(record, timesWords(record) ? SGLyricsfileLines(record[@"lyricsfile"]) : nil);
}

void SGLrcLibGetID(NSNumber *recordID, void (^done)(SGLyricsResult *result)) {
    SGLrcLibGetIDIn(nil, recordID, done);
}
void SGLrcLibGetIDIn(SGLyricsRequestContext *context, NSNumber *recordID, void (^done)(SGLyricsResult *result)) {
    NSString *identifier = SGLyricsDecimalID(recordID);
    if (!identifier.length) { done(nil); return; }
    NSURL *url = [NSURL URLWithString:[kGet stringByAppendingFormat:@"/%@", identifier]];
    getJSON(context, url, ^id(id record) { return SGLrcLibRecordResult(record); }, done);
}

// Search is for a person choosing a recording: keep different lengths, and show the closest first
// within each timing kind. A malformed record has nothing useful to choose and is left out.
static NSArray<NSDictionary *> *searchRecords(id reply, NSInteger seconds) {
    NSMutableArray<NSDictionary *> *records = [NSMutableArray array];
    NSUInteger read = 0;
    for (id raw in [reply isKindOfClass:NSArray.class] ? reply : @[]) {
        if (read++ >= 100) break;
        if (!boundedRecord(raw)) continue;
        id identifier = raw[@"id"];
        if (![identifier isKindOfClass:NSNumber.class] || !SGLyricsDecimalID(identifier).length || [identifier longLongValue] <= 0) continue;
        double duration = 0;
        if (!SGLyricsNumber(raw[@"duration"], &duration)) duration = 0;
        if (!isfinite(duration) || duration < 0 || duration > 86400) duration = 0;
        BOOL synced = [raw[@"syncedLyrics"] isKindOfClass:NSString.class] && [raw[@"syncedLyrics"] length];
        BOOL instrumental = [raw[@"instrumental"] isKindOfClass:NSNumber.class] && [raw[@"instrumental"] boolValue];
        [records addObject:@{@"id": identifier, @"title": SGLyricsString(raw[@"trackName"], 4096) ?: @"",
                             @"artist": SGLyricsString(raw[@"artistName"], 4096) ?: @"",
                             @"album": SGLyricsString(raw[@"albumName"], 4096) ?: @"", @"seconds": @(duration),
                             @"synced": @(synced), @"instrumental": @(instrumental), @"record": raw}];
    }
    [records sortWithOptions:NSSortStable usingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        if ([a[@"synced"] boolValue] != [b[@"synced"] boolValue]) return [a[@"synced"] boolValue] ? NSOrderedAscending : NSOrderedDescending;
        if (seconds <= 0) return NSOrderedSame;
        double off = fabs([a[@"seconds"] doubleValue] - seconds), wasOff = fabs([b[@"seconds"] doubleValue] - seconds);
        return off < wasOff ? NSOrderedAscending : off > wasOff ? NSOrderedDescending : NSOrderedSame;
    }];
    return records.count > 20 ? [records subarrayWithRange:NSMakeRange(0, 20)] : [records copy];
}

void SGLrcLibSearch(NSString *title, NSString *artist, NSInteger seconds, void (^done)(NSArray<NSDictionary *> *records)) {
    void (^search)(void) = ^{
        if (!title.length && !artist.length) { done(@[]); return; }
        NSMutableDictionary *query = [NSMutableDictionary dictionary];
        if (title.length) query[@"track_name"] = title;
        if (artist.length) query[@"artist_name"] = artist;
        getJSON(nil, SGLyricsURL(kSearch, query), ^id(id reply) { return searchRecords(reply, seconds); }, done);
    };
    if (NSThread.isMainThread) search();
    else dispatch_async(dispatch_get_main_queue(), search);
}

// How good a recording is for the track: words timed beat lines timed, which beat untimed, then the
// closest length. With no length to go on, the fullest sheet wins — the search will happily rank a
// seventeen second stub of a song above the song, and a stub is the one thing a length would have
// caught.
static BOOL betterRecord(NSDictionary *record, NSDictionary *best, NSInteger seconds) {
    if (!best) return YES;
    BOOL worded = [record[@"hasWordSync"] isEqual:@YES], wasWorded = [best[@"hasWordSync"] isEqual:@YES];
    if (worded != wasWorded) return worded;
    BOOL synced = [record[@"syncedLyrics"] isKindOfClass:NSString.class] && [record[@"syncedLyrics"] length];
    BOOL wasSynced = [best[@"syncedLyrics"] isKindOfClass:NSString.class] && [best[@"syncedLyrics"] length];
    if (synced != wasSynced) return synced;
    if (seconds > 0) {
        NSInteger off = labs(secondsIn(record) - seconds);
        NSInteger wasOff = labs(secondsIn(best) - seconds);
        if (off != wasOff) return off < wasOff;
    }
    id text = synced ? record[@"syncedLyrics"] : record[@"plainLyrics"];
    id wasText = wasSynced ? best[@"syncedLyrics"] : best[@"plainLyrics"];
    NSUInteger len = [text isKindOfClass:NSString.class] ? [text length] : 0;
    NSUInteger wasLen = [wasText isKindOfClass:NSString.class] ? [wasText length] : 0;
    return len > wasLen;
}

// The search ranks by its own lights, and its first hit is often another song of the artist's or the
// song by someone else, so a record has to be the track (SongMatch.m) before its timing counts. The
// artists are written as one name, joined however the uploader's tags had them.
static NSArray<NSDictionary *> *matching(id found, NSString *title, NSString *artist, NSInteger seconds) {
    NSMutableArray<NSDictionary *> *records = [NSMutableArray array];
    NSUInteger read = 0;
    for (NSDictionary *record in [found isKindOfClass:NSArray.class] ? found : @[]) {
        if (read++ >= 100) break;
        if (!boundedRecord(record)) continue;
        NSInteger length = secondsIn(record);
        if (seconds > 0 && length > 0 && labs(length - seconds) > kLengthSlack) continue;
        NSString *artists = [record[@"artistName"] isKindOfClass:NSString.class] ? record[@"artistName"] : @"";
        if (!SGLyricsSongRank(title, artist, record[@"trackName"], @[artists])) continue;
        [records addObject:record];
    }
    return records;
}

static NSDictionary *bestOf(NSArray<NSDictionary *> *records, NSInteger seconds) {
    NSDictionary *best = nil;
    for (NSDictionary *record in records) {
        if (betterRecord(record, best, seconds)) best = record;
    }
    return best;
}

// The best of the records as a result, on the transport worker. A record's words count only once
// its Lyricsfile reads, so the best that says it times words is read first, and one whose file cannot be read is
// weighed again on its LRC alone, until the best is one with words read or one without.
static SGLyricsResult *resultFor(NSArray<NSDictionary *> *records, NSInteger seconds) {
    NSDictionary *best = bestOf(records, seconds);
    if (!timesWords(best)) return resultFrom(best, nil);
        NSMutableArray<NSDictionary *> *left = [records mutableCopy];
        NSDictionary *top = best;
        NSArray<SGKaraokeLine *> *worded = nil;
        while (timesWords(top)) {
            worded = SGLyricsfileLines(top[@"lyricsfile"]);
            if (worded) break;
            SGLog(@"lrclib: unreadable timed Lyricsfile");
            NSMutableDictionary *onLines = [top mutableCopy];
            [onLines removeObjectForKey:@"hasWordSync"];
            left[[left indexOfObjectIdenticalTo:top]] = onLines;
            top = bestOf(left, seconds);
        }
    return resultFrom(top, worded);
}

SGLyricsAsk SGLrcLibAsk = ^(SGLyricsQuery *query, void (^done)(SGLyricsResult *result)) {
    if (!NSThread.isMainThread) { dispatch_async(dispatch_get_main_queue(), ^{ SGLrcLibAsk(query, done); }); return; }
    if (!query.title.length || !query.artist.length) {
        SGLog(@"lrclib: no names to search");
        done(nil);
        return;
    }
    NSMutableDictionary<NSString *, NSString *> *search = [NSMutableDictionary dictionaryWithDictionary:@{
        @"track_name": query.title,
        @"artist_name": query.artist,
    }];
    if (query.album.length) search[@"album_name"] = query.album;
    NSString *title = query.title, *artist = query.artist;
    NSInteger seconds = query.seconds;

    void (^bySearch)(void) = ^{
        getJSON(query.requestContext, SGLyricsURL(kSearch, search), ^id(id found) {
            if (found && ![found isKindOfClass:NSArray.class]) [query.requestContext noteFailure:YES];
            if ([found isKindOfClass:NSArray.class] && ![found count])
                query.requestContext.emptyNameSearch = SGLrcLibAsk;
            return resultFor(matching(found, title, artist, seconds), seconds);
        }, ^(SGLyricsResult *result) {
                SGLog(@"lrclib: search gave %@",
                      !result ? @"nothing" : result.instrumental ? @"an instrumental"
                      : result.synced ? [NSString stringWithFormat:@"%lu %@ lines", (unsigned long)result.karaokeLines.count, result.wordTimed ? @"word timed" : @"timed"]
                      : [NSString stringWithFormat:@"%lu untimed lines", (unsigned long)result.texts.count]);
                done(result);
        });
    };

    // With no length to match on, the exact lookup would be a guess; the search ranks by itself.
    if (query.seconds <= 0) {
        bySearch();
        return;
    }
    NSMutableDictionary<NSString *, NSString *> *exact = [search mutableCopy];
    exact[@"duration"] = @(query.seconds).stringValue;
    getJSON(query.requestContext, SGLyricsURL(kGet, exact), ^id(id record) {
        return resultFor([record isKindOfClass:NSDictionary.class] ? @[record] : @[], seconds);
    }, ^(SGLyricsResult *result) {
            if (!result) {
                bySearch();
                return;
            }
            SGLog(@"lrclib: exact match, %@",
                  result.instrumental ? @"instrumental" : result.wordTimed ? @"word timed" : result.synced ? @"timed" : @"untimed");
            done(result);
    });
};
