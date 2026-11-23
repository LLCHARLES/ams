// Word timing from NetEase Cloud Music, for the tracks the other sources only line-time, e.g. most
// of Eminem. It has no text of its own to offer Spotify's page, only the time of every word, so it
// earns its place at the end of the order rather than the front. Searched by title, artist and
// length; NetEase censors swear words with asterisks.
#import "Core/SGCore.h"
#import "LyricsSources.h"
#import "LyricsHosts.h"

static const NSTimeInterval kTimeout = 3;
// A NetEase recording is only taken when its length is this close to the track's, so the words fall
// on the same beat.
static const NSInteger kLengthSlack = 3;
static const NSUInteger kTriedSongs = 3;

static void get(SGLyricsRequestContext *context, NSString *path, NSDictionary<NSString *, NSString *> *query, void (^done)(NSDictionary *root)) {
    NSURL *url = SGLyricsURL([@"https://music.163.com/api/" stringByAppendingString:path], query);
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:kTimeout];
    SGLyricsMarkRequest(request);
    [request setValue:@"https://music.163.com" forHTTPHeaderField:@"Referer"];
    NSURLSessionDataTask *task = [NSURLSession.sharedSession dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        SGLyricsNoteReply(response, error);
        [context noteResponse:response error:error];
        id root = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        [context noteFailure:![root isKindOfClass:NSDictionary.class]];
        id code = SGLyricsField(root, @"code");
        if (code && ![code isEqual:@200]) [context noteFailure:YES];
        if (error || !root) SGLog(@"netease: %@ failed: status %ld, error %@", path, (long)[(NSHTTPURLResponse *)response statusCode], error);
        dispatch_async(dispatch_get_main_queue(), ^{ done([root isKindOfClass:NSDictionary.class] ? root : nil); });
    }];
    [context trackTask:task];
    [task resume];
}

// [43060,3600](43060,120,0)To (43180,330,0)seize (43510,420,0)everything …
// A line's start and length in ms, then each piece's start and length before its text. A piece not
// ending in a space runs on into the next one ("wanted" "…"), as in richsync. KuGou's KRC is written
// the same way, its pieces in <> and timed from the start of their line instead of the track's.
NSArray<SGKaraokeLine *> *SGLyricsPieceLines(NSString *body, BOOL krc) {
    static NSRegularExpression *header, *yrcPiece, *krcPiece;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        header = [NSRegularExpression regularExpressionWithPattern:@"^\\[(-?\\d+),(-?\\d+)\\]" options:0 error:nil];
        yrcPiece = [NSRegularExpression regularExpressionWithPattern:@"\\((-?\\d+),(-?\\d+),-?\\d+\\)" options:0 error:nil];
        krcPiece = [NSRegularExpression regularExpressionWithPattern:@"<(-?\\d+),(-?\\d+),-?\\d+>" options:0 error:nil];
    });
    NSRegularExpression *piece = krc ? krcPiece : yrcPiece;
    NSMutableArray<SGKaraokeLine *> *lines = [NSMutableArray array];
    for (NSString *row in [body componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
        NSTextCheckingResult *head = [header firstMatchInString:row options:0 range:NSMakeRange(0, row.length)];
        if (!head) continue;
        NSArray<NSTextCheckingResult *> *pieces = [piece matchesInString:row options:0 range:NSMakeRange(NSMaxRange(head.range), row.length - NSMaxRange(head.range))];
        double startMs, durationMs;
        if (!SGLyricsNumber([row substringWithRange:[head rangeAtIndex:1]], &startMs) ||
            !SGLyricsNumber([row substringWithRange:[head rangeAtIndex:2]], &durationMs) ||
            startMs + durationMs > SGKaraokeMaxTimeMs) return nil;
        NSInteger lineStart = (NSInteger)startMs, lineEnd = lineStart + (NSInteger)durationMs;
        NSInteger previous = lineStart;
        NSMutableArray<SGKaraokePiece *> *timed = [NSMutableArray array];
        for (NSUInteger i = 0; i < pieces.count; i++) {
            NSUInteger from = NSMaxRange(pieces[i].range), to = i + 1 < pieces.count ? pieces[i + 1].range.location : row.length;
            NSString *raw = [row substringWithRange:NSMakeRange(from, to - from)];
            SGKaraokePiece *piece = [SGKaraokePiece new];
            piece.text = [raw stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
            double atMs, lengthMs;
            if (!SGLyricsNumber([row substringWithRange:[pieces[i] rangeAtIndex:1]], &atMs) ||
                !SGLyricsNumber([row substringWithRange:[pieces[i] rangeAtIndex:2]], &lengthMs)) return nil;
            if (krc) atMs += lineStart;
            if (atMs < previous || atMs + MAX(lengthMs, 1) > SGKaraokeMaxTimeMs) return nil;
            piece.start = (NSInteger)atMs;
            // A piece of no length is still shown, for a moment.
            piece.end = piece.start + MAX((NSInteger)lengthMs, 1);
            previous = piece.start;
            // A space ends the word after the piece, even one in front of it.
            piece.spaceAfter = raw.length > piece.text.length;
            [timed addObject:piece];
        }
        SGKaraokeLine *line = SGKaraokePieceLine(timed, lineStart, lineEnd);
        if (line) [lines addObject:line];
    }
    return lines.count ? lines : nil;
}

static void tryLyrics(SGLyricsRequestContext *context, NSArray<NSString *> *songs, NSUInteger index, void (^done)(NSArray<SGKaraokeLine *> *)) {
    if (index >= songs.count) {
        done(nil);
        return;
    }
    get(context, @"song/lyric/v1", @{@"id": songs[index], @"lv": @"1", @"yv": @"1", @"tv": @"-1"}, ^(NSDictionary *root) {
        id yrc = [root[@"yrc"] isKindOfClass:NSDictionary.class] ? root[@"yrc"][@"lyric"] : nil;
        NSArray<SGKaraokeLine *> *lines = [yrc isKindOfClass:NSString.class] ? SGLyricsPieceLines(yrc, NO) : nil;
        if (yrc && yrc != NSNull.null && ![yrc isEqual:@""] && !lines) [context noteFailure:YES];
        if (lines) {
            SGLog(@"netease: song %@ has %lu word timed lines", songs[index], (unsigned long)lines.count);
            done(lines);
        } else {
            tryLyrics(context, songs, index + 1, done);
        }
    });
}

// A recording is only taken when its length is this close to the track's, so the words fall on the
// same beat as the recording Spotify is playing.
SGLyricsAsk SGNetEaseAsk = ^(SGLyricsQuery *query, void (^done)(SGLyricsResult *result)) {
    void (^answer)(NSArray<SGKaraokeLine *> *) = ^(NSArray<SGKaraokeLine *> *lines) {
        if (!lines.count) {
            done(nil);
            return;
        }
        SGLyricsResult *result = [SGLyricsResult new];
        result.wordTimed = result.synced = YES;
        result.karaokeLines = lines;
        done(result);
    };
    NSString *lead = [query.artist componentsSeparatedByString:@" feat"].firstObject.lowercaseString;
    NSString *title = query.title;
    NSInteger seconds = query.seconds;
    if (!title.length || !lead.length || seconds <= 0) {
        answer(nil);
        return;
    }
    get(query.requestContext, @"search/get", @{@"s": [NSString stringWithFormat:@"%@ %@", title, lead], @"type": @"1", @"limit": @"10"}, ^(NSDictionary *root) {
        id result = [root[@"result"] isKindOfClass:NSDictionary.class] ? root[@"result"] : nil;
        id songs = result[@"songs"];
        if (root && ![songs isKindOfClass:NSArray.class] && ![result[@"songCount"] isEqual:@0])
            [query.requestContext noteFailure:YES];
        if ([root[@"code"] isEqual:@200] && (([songs isKindOfClass:NSArray.class] && ![songs count])
            || (!songs && [result[@"songCount"] isEqual:@0])))
            query.requestContext.emptyNameSearch = SGNetEaseAsk;
        NSMutableArray<NSDictionary *> *fitting = [NSMutableArray array];
        for (NSDictionary *song in [songs isKindOfClass:NSArray.class] ? songs : @[]) {
            if (![song isKindOfClass:NSDictionary.class]) continue;
            if (![SGLyricsMatchKey(song[@"name"]) isEqualToString:SGLyricsMatchKey(title)]) continue;
            NSString *identifier = SGLyricsDecimalID(song[@"id"]);
            double duration;
            if (!identifier || !SGLyricsNumber(song[@"duration"], &duration)
                || labs((NSInteger)duration / 1000 - seconds) > kLengthSlack) continue;
            id artists = song[@"artists"];
            for (NSDictionary *credited in [artists isKindOfClass:NSArray.class] ? artists : @[]) {
                NSString *name = [credited isKindOfClass:NSDictionary.class] && [credited[@"name"] isKindOfClass:NSString.class] ? [credited[@"name"] lowercaseString] : nil;
                if (name.length && ([name containsString:lead] || [lead containsString:name])) {
                    [fitting addObject:@{@"id": identifier, @"duration": @((NSInteger)duration)}];
                    break;
                }
            }
        }
        [fitting sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
            return [@(labs([a[@"duration"] integerValue] / 1000 - seconds)) compare:@(labs([b[@"duration"] integerValue] / 1000 - seconds))];
        }];
        NSArray *ids = [[fitting valueForKey:@"id"] subarrayWithRange:NSMakeRange(0, MIN(fitting.count, kTriedSongs))];
        if (!ids.count) SGLog(@"netease: no recording of %@ by %@ within %lds of %lds", title, lead, (long)kLengthSlack, (long)seconds);
        tryLyrics(query.requestContext, ids, 0, answer);
    });
};
