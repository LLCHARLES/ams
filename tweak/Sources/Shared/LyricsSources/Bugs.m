// Bugs' timed sheet separates lines with a fullwidth number sign. Its clock is in seconds, unlike
// the other Korean source's millisecond keys. Plain words are asked for only when that sheet fails.
#import "Core/SGCore.h"
#import "LyricsSources.h"

SGLyricsResult *SGBugsResult(id root, BOOL timed) {
    NSString *body = SGLyricsString(SGLyricsField(root, @"lyrics"), 262144);
    if (!timed) return SGLyricsPlainTextResult(body, @"Bugs");
    if (!body.length) return nil;
    NSArray *entries = [body componentsSeparatedByString:@"＃"];
    if (entries.count > 2000) return nil;
    NSMutableArray *rows = [NSMutableArray array];
    NSUInteger total = 0;
    NSInteger previous = -1;
    for (NSString *entry in entries) {
        if (!entry.length) continue;
        total++;
        NSRange bar = [entry rangeOfString:@"|"];
        double seconds;
        if (bar.location == NSNotFound || !SGLyricsNumber([entry substringToIndex:bar.location], &seconds) || seconds > 86400) continue;
        NSString *text = [entry substringFromIndex:bar.location + 1];
        if (text.length > 4096) continue;
        NSInteger at = llround(seconds * 1000);
        // A tiny rounding wobble can be sorted; a clock jumping back to another verse cannot.
        if (previous >= 0 && at < previous - 500) return nil;
        previous = at;
        [rows addObject:@{@"at": @(at), @"text": text}];
    }
    if (!rows.count || rows.count * 2 < total) return nil;
    [rows sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) { return [a[@"at"] compare:b[@"at"]]; }];
    return SGLyricsResultWithLines(SGKaraokeEstimatedLines([rows valueForKey:@"at"], [rows valueForKey:@"text"]), @"Bugs");
}

static double trackLength(id value) {
    NSString *text = SGLyricsString(value, 32);
    NSArray *parts = [text componentsSeparatedByString:@":"];
    double minutes, seconds;
    if (parts.count == 2 && SGLyricsNumber(parts[0], &minutes) && SGLyricsNumber(parts[1], &seconds) && seconds < 60) return minutes * 60 + seconds;
    return SGLyricsNumber(value, &seconds) ? seconds : 0;
}

static NSString *songFor(id root, SGLyricsQuery *query) {
    id list = SGLyricsField(root, @"list");
    if (![list isKindOfClass:NSArray.class] || [list count] > 100) return nil;
    for (id song in list) {
        NSString *title = SGLyricsString(SGLyricsField(song, @"track_title"), 1024);
        if (![SGLyricsMatchKey(title) isEqualToString:SGLyricsMatchKey(query.title)]) continue;
        double length = trackLength(SGLyricsField(song, @"len"));
        if (length > 0 && query.seconds > 0 && fabs(length - query.seconds) > 4) continue;
        id artists = SGLyricsField(song, @"artists");
        if (![artists isKindOfClass:NSArray.class] || [artists count] > 100) continue;
        for (id artist in artists) {
            if (SGLyricsSameArtist(SGLyricsString(SGLyricsField(artist, @"artist_nm"), 1024), query.artist)) {
                NSString *songID = SGLyricsDecimalID(SGLyricsField(song, @"track_id"));
                if (songID) return songID;
            }
        }
    }
    return nil;
}

static void lyrics(SGLyricsRequestContext *context, NSString *song, BOOL timed, void (^done)(SGLyricsResult *)) {
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"https://music.bugs.co.kr/player/lyrics/%@/%@", timed ? @"T" : @"N", song]];
    SGLyricsSourceRequestIn(context, url, nil, nil, ^(NSData *data, NSInteger status) {
        id root = status == 200 && data.length ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        if (status == 200 && !root) [context noteFailure:YES];
        SGLyricsResult *result = SGBugsResult(root, timed);
        if (!result && timed) { lyrics(context, song, NO, done); return; }
        SGLog(@"bugs: %lu lines", (unsigned long)result.karaokeLines.count);
        done(result);
    });
}

// Main queue only. All tracks share the search host’s refusal window.
static NSTimeInterval sg_searchRefusedUntil;

SGLyricsAsk SGBugsAsk = ^(SGLyricsQuery *query, void (^done)(SGLyricsResult *)) {
    if (!NSThread.isMainThread) { dispatch_async(dispatch_get_main_queue(), ^{ SGBugsAsk(query, done); }); return; }
    if (!SGLyricsMatchKey(query.title).length || !SGLyricsMatchKey(query.artist).length) { done(nil); return; }
    if (NSProcessInfo.processInfo.systemUptime < sg_searchRefusedUntil) {
        [query.requestContext noteFailure:YES];
        done(nil);
        return;
    }
    sg_searchRefusedUntil = 0;
    NSURL *url = SGLyricsURL(@"https://m.bugs.co.kr/api/getSearchList", @{@"type": @"track", @"query": [NSString stringWithFormat:@"%@ %@", query.title, SGLyricsLeadArtist(query.artist)], @"page": @"1", @"size": @"30"});
    SGLyricsSourceRequestIn(query.requestContext, url, nil, nil, ^(NSData *data, NSInteger status) {
        id root = status == 200 && data.length ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        if (status == 403) {
            sg_searchRefusedUntil = NSProcessInfo.processInfo.systemUptime + SGLyricsCredentialPauseSeconds;
            [query.requestContext noteFailure:YES];
        }
        id list = SGLyricsField(root, @"list");
        if (status == 200 && ![list isKindOfClass:NSArray.class]) [query.requestContext noteFailure:YES];
        if ([list isKindOfClass:NSArray.class] && ![list count])
            query.requestContext.emptyNameSearch = SGBugsAsk;
        NSString *song = songFor(root, query);
        if (!song) { done(nil); return; }
        lyrics(query.requestContext, song, YES, done);
    });
};
