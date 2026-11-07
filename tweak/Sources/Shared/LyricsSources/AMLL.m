// AMLL (amll.dev): the community's Apple Music-style TTML, word-timed, from the library Apple's own
// timing is transcribed into.
//
// Two ways in. Spotify's own id is exact and needs no name, but most sheets in the library were keyed
// by the Chinese catalogues they were transcribed from and carry no Spotify id at all — of the
// popular tracks sampled, only one in three did — so a miss by id is followed by a search on the title
// and artist. A sheet found that way is taken only when the title reads the same and an artist
// overlaps, or it is another recording and nothing is taken: a miss stays a miss.
//
// The API answers {"status":200,"data":{"lyrics":"<ttml>…"}} for a sheet and 404 when the library has
// nothing; the TTML is the same shape BiniLyrics and Unison serve, so SGTTMLLines reads it.
// Registered under the "amll" key.
#import "Core/SGCore.h"
#import "LyricsSources.h"

static NSString *const kAMLLAPI = @"https://api.amll.dev/v1/lyrics";
static NSString *const kAMLLAgent = @"Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1";
// The library sits far away and a cold request is slow; the walk waits this long before it gives up
// and lets the next source answer.
static const NSTimeInterval kAMLLWait = 12;

static NSDictionary<NSString *, NSString *> *amllHeaders(void) {
    return @{@"Accept": @"application/json", @"User-Agent": kAMLLAgent};
}

// Asks the library for a sheet by one of its own keys: "spotifyId", or the "id" a search returned.
static void amllAsk(NSDictionary<NSString *, NSString *> *query, NSString *what,
                    void (^done)(NSString *ttml)) {
    NSURL *url = SGLyricsURL([kAMLLAPI stringByAppendingPathComponent:@"get"], query);
    SGLyricsGetJSONWithin(url, amllHeaders(), kAMLLWait, ^(id root, NSInteger status) {
        NSDictionary *data = [root isKindOfClass:NSDictionary.class] ? root[@"data"] : nil;
        NSString *ttml = [data isKindOfClass:NSDictionary.class] ? data[@"lyrics"] : nil;
        if (![ttml isKindOfClass:NSString.class] || !ttml.length) {
            SGLog(@"amll: no sheet for %@ (answered %ld)", what, (long)status);
            done(nil);
            return;
        }
        done(ttml);
    });
}

// The entry the library has for a named track: the title has to read the same and an artist to
// overlap, or it is another recording and nothing is taken.
static NSDictionary *amllEntry(NSArray *items, SGLyricsQuery *query) {
    NSString *title = SGLyricsMatchKey(query.title ?: @"");
    NSString *artist = SGLyricsMatchKey(SGLyricsLeadArtist(query.artist ?: @""));
    if (!title.length) return nil;
    for (NSDictionary *item in items) {
        if (![item isKindOfClass:NSDictionary.class] || !item[@"id"]) continue;
        NSArray *names = [item[@"musicNames"] isKindOfClass:NSArray.class] ? item[@"musicNames"] : nil;
        BOOL titled = NO;
        for (id name in names) {
            if ([name isKindOfClass:NSString.class] && [SGLyricsMatchKey(name) isEqualToString:title]) {
                titled = YES;
                break;
            }
        }
        if (!titled) continue;
        if (!artist.length) return item;
        NSArray *artists = [item[@"artistNames"] isKindOfClass:NSArray.class] ? item[@"artistNames"] : nil;
        for (id name in artists) {
            if (![name isKindOfClass:NSString.class]) continue;
            NSString *key = SGLyricsMatchKey(name);
            if (key.length && ([key containsString:artist] || [artist containsString:key])) return item;
        }
    }
    return nil;
}

static SGLyricsResult *amllResult(NSString *ttml, NSString *track) {
    NSArray<SGKaraokeLine *> *lines = SGTTMLLines(ttml);
    if (!lines.count) {
        SGLog(@"amll: %@ returned a sheet with no lines", track);
        return nil;
    }
    // AMLL is a word-timed library; a sheet that only times lines still reads line by line.
    BOOL words = NO;
    for (SGKaraokeLine *line in lines) {
        if (line.words.count > 1) {
            words = YES;
            break;
        }
    }
    SGLyricsResult *lyrics = [SGLyricsResult new];
    lyrics.synced = YES;
    lyrics.wordTimed = words;
    lyrics.karaokeLines = lines;
    NSArray<NSNumber *> *starts;
    NSArray<NSString *> *texts;
    SGLyricsPageLines(lines, &starts, &texts);
    lyrics.starts = starts;
    lyrics.texts = texts;
    SGLog(@"amll: %@ — %lu %@ line(s)", track, (unsigned long)lines.count, words ? @"word timed" : @"line timed");
    return lyrics;
}

SGLyricsAsk SGAMLLAsk = ^(SGLyricsQuery *query, void (^done)(SGLyricsResult *result)) {
    NSString *track = [query.trackID stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    if (!track.length) {
        SGLog(@"amll: no Spotify id to ask with");
        done(nil);
        return;
    }
    amllAsk(@{@"spotifyId": track}, [NSString stringWithFormat:@"Spotify id %@", track], ^(NSString *ttml) {
        if (ttml) {
            done(amllResult(ttml, track));
            return;
        }
        if (!query.title.length) {
            done(nil);
            return;
        }
        NSString *term = [[NSString stringWithFormat:@"%@ %@", query.title, SGLyricsLeadArtist(query.artist ?: @"")]
                          stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        SGLyricsGetJSONWithin(SGLyricsURL([kAMLLAPI stringByAppendingPathComponent:@"search"], @{@"q": term}),
                             amllHeaders(), kAMLLWait, ^(id found, NSInteger status) {
            NSDictionary *data = [found isKindOfClass:NSDictionary.class] ? found[@"data"] : nil;
            NSArray *items = [data isKindOfClass:NSDictionary.class] ? data[@"items"] : nil;
            NSDictionary *entry = [items isKindOfClass:NSArray.class] ? amllEntry(items, query) : nil;
            if (!entry) {
                SGLog(@"amll: nothing reads as \"%@\" (search answered %ld)", term, (long)status);
                done(nil);
                return;
            }
            SGLog(@"amll: %@ found by name as \"%@\"", track, [entry[@"musicNames"] firstObject]);
            amllAsk(@{@"id": [entry[@"id"] description]}, [NSString stringWithFormat:@"entry %@", entry[@"id"]], ^(NSString *sheet) {
                done(sheet ? amllResult(sheet, track) : nil);
            });
        });
    });
};
