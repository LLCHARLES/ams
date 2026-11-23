// LyricsPlus gathers several catalogs behind one query. Its line clock and syllable clocks are
// already milliseconds. Keep a source credit and the backing part instead of flattening the voices.
#import "Core/SGCore.h"
#import "LyricsSources.h"

static SGKaraokeLine *wordsIn(NSArray *pieces, BOOL background, NSString *plain) {
    NSMutableArray<SGKaraokeWord *> *words = [NSMutableArray array];
    BOOL separated = YES;
    NSUInteger cursor = 0;
    NSInteger previous = -1;
    for (id piece in pieces) {
        if (![piece isKindOfClass:NSDictionary.class]) return nil;
        id flag = piece[@"isBackground"];
        if (flag && ![flag isKindOfClass:NSNumber.class]) return nil;
        if ([flag boolValue] != background) continue;
        NSString *raw = SGLyricsString(piece[@"text"], 1024);
        NSString *text = [raw stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        double at, duration;
        if (!raw || !SGLyricsNumber(piece[@"time"], &at) || !SGLyricsNumber(piece[@"duration"], &duration) || at + duration > 86400000) return nil;
        if (!text.length) { separated = YES; continue; }
        if (at < previous) return nil;
        SGKaraokeWord *word = [SGKaraokeWord new];
        word.text = text;
        word.start = llround(at);
        word.end = MAX(word.start + 1, llround(at + duration));
        word.joined = words.count && !separated && ![NSCharacterSet.whitespaceAndNewlineCharacterSet characterIsMember:[raw characterAtIndex:0]];
        // Word syncs sometimes trim each word. The full line still tells us where spaces belong.
        NSRange found = plain.length && cursor <= plain.length ? [plain rangeOfString:text options:0 range:NSMakeRange(cursor, plain.length - cursor)] : NSMakeRange(NSNotFound, 0);
        if (found.location != NSNotFound) {
            NSString *gap = [plain substringWithRange:NSMakeRange(cursor, found.location - cursor)];
            if (words.count) word.joined = [gap rangeOfCharacterFromSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].location == NSNotFound;
            cursor = NSMaxRange(found);
        }
        [words addObject:word];
        separated = [NSCharacterSet.whitespaceAndNewlineCharacterSet characterIsMember:[raw characterAtIndex:raw.length - 1]];
        previous = word.start;
    }
    if (!words.count) return nil;
    SGKaraokeLine *line = [SGKaraokeLine new];
    line.words = words;
    line.start = words.firstObject.start;
    line.end = line.start + 1;
    for (SGKaraokeWord *word in words) line.end = MAX(line.end, word.end);
    line.timing = SGKaraokeTimingWords;
    return line;
}

SGLyricsResult *SGLyricsPlusResult(id root) {
    NSString *type = SGLyricsString(SGLyricsField(root, @"type"), 32);
    BOOL wordTimed = [type isEqualToString:@"Word"] || [type isEqualToString:@"Syllable"];
    if (!wordTimed && ![type isEqualToString:@"Line"]) return nil;
    id rows = SGLyricsField(root, @"lyrics");
    if (![rows isKindOfClass:NSArray.class] || [rows count] > 2000) return nil;
    NSMutableArray *lines = [NSMutableArray array], *starts = [NSMutableArray array], *texts = [NSMutableArray array];
    for (id row in rows) {
        double at, duration;
        NSString *text = SGLyricsString(SGLyricsField(row, @"text"), 4096);
        if (!text || !SGLyricsNumber(SGLyricsField(row, @"time"), &at) || !SGLyricsNumber(SGLyricsField(row, @"duration"), &duration) || at + duration > 86400000) return nil;
        if (!wordTimed) { [starts addObject:@(llround(at))]; [texts addObject:text]; continue; }
        id pieces = SGLyricsField(row, @"syllabus");
        if (![pieces isKindOfClass:NSArray.class] || [pieces count] > 1000) return nil;
        SGKaraokeLine *line = wordsIn(pieces, NO, text);
        SGKaraokeLine *backing = wordsIn(pieces, YES, nil);
        // A row sung only in the background still has words worth showing.
        if (!line) { line = backing; backing = nil; }
        if (!line) return nil;
        line.backing = backing;
        line.start = MIN(line.start, llround(at));
        line.end = MAX(line.end, llround(at + duration));
        id singer = SGLyricsField(SGLyricsField(row, @"element"), @"singer");
        line.voice = SGLyricsString(singer, 64) ?: SGLyricsDecimalID(singer);
        [lines addObject:line];
    }
    if (!wordTimed) {
        NSMutableArray *sorted = [NSMutableArray array];
        for (NSUInteger i = 0; i < starts.count; i++) [sorted addObject:@{@"at": starts[i], @"text": texts[i]}];
        [sorted sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) { return [a[@"at"] compare:b[@"at"]]; }];
        [lines addObjectsFromArray:SGKaraokeEstimatedLines([sorted valueForKey:@"at"], [sorted valueForKey:@"text"]) ?: @[]];
    }
    SGKaraokeAlignVoices(lines);
    NSString *source = SGLyricsString(SGLyricsField(SGLyricsField(root, @"metadata"), @"source"), 128);
    return SGLyricsResultWithLines(lines, source.length ? [@"LyricsPlus · " stringByAppendingString:source] : @"LyricsPlus");
}

static void ask(SGLyricsQuery *query, NSDictionary *parameters, BOOL fallback, BOOL priorEmpty, void (^done)(SGLyricsResult *)) {
    NSString *base = fallback ? @"https://lyricsplus.binimum.org" : @"https://lyricsplus.prjktla.my.id";
    NSURL *url = SGLyricsURL([base stringByAppendingString:@"/v2/lyrics/get"], parameters);
    SGLyricsSourceRequestIn(query.requestContext, url, nil, nil, ^(NSData *data, NSInteger status) {
        __block BOOL empty = NO;
        SGLyricsTransform(^id {
            id root = data.length ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
            id rows = SGLyricsField(root, @"lyrics");
            id sources = SGLyricsField(SGLyricsField(root, @"processingTime"), @"sourcesStatus");
            BOOL upstreamFailed = NO;
            for (id source in [sources isKindOfClass:NSDictionary.class] ? [sources allValues] : @[]) {
                id outcome = SGLyricsField(source, @"status");
                if ([outcome isEqual:@"RTO"] || [outcome isEqual:@"BAD"]) upstreamFailed = YES;
            }
            [query.requestContext noteFailure:upstreamFailed ||
                ((status == 200 || status == 404) && ![root isKindOfClass:NSDictionary.class])];
            empty = !upstreamFailed && (status == 404 || ([rows isKindOfClass:NSArray.class] && ![rows count]));
            SGLyricsResult *result = status == 200 ? SGLyricsPlusResult(root) : nil;
            if (status == 200 && !empty && !result) [query.requestContext noteFailure:YES];
            return result;
        }, ^(SGLyricsResult *result) {
        if (!result && !fallback) { ask(query, parameters, YES, empty, done); return; }
        if (!result && empty && priorEmpty) query.requestContext.emptyNameSearch = SGLyricsPlusAsk;
        SGLog(@"lyricsplus: %lu lines", (unsigned long)result.karaokeLines.count);
        done(result);
        });
    });
}

SGLyricsAsk SGLyricsPlusAsk = ^(SGLyricsQuery *query, void (^done)(SGLyricsResult *)) {
    if (!NSThread.isMainThread) { dispatch_async(dispatch_get_main_queue(), ^{ SGLyricsPlusAsk(query, done); }); return; }
    if (!SGLyricsMatchKey(query.title).length || !SGLyricsMatchKey(query.artist).length) { done(nil); return; }
    NSDictionary *parameters = @{@"title": query.title, @"artist": SGLyricsLeadArtist(query.artist), @"album": query.album ?: @"", @"duration": [NSString stringWithFormat:@"%.3f", (double)MAX(0, query.seconds)]};
    ask(query, parameters, NO, YES, done);
};
