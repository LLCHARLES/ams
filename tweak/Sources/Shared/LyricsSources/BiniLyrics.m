// BiniLyrics, the widest of the sources that serve Apple Music's own TTML: over a million recordings,
// word timed, and no key to ask for. Its API now redirects to lrc.red, which files each TTML under the
// recording's ISRC: with Spotify's ISRC for the track, that file is asked for first, the exact recording.
// Else, or when it has none, the search by title, artist and length, so it needs a source before it in
// the order — or the player — to have named the track. The search answers with metadata and a link; the
// TTML itself is a second request, to a plain file host.
#import "Core/SGCore.h"
#import "Shared/Haptics/Haptics.h"
#import "LyricsSources.h"
#import "LyricsHosts.h"

static NSString *const kAPI = @"https://lyrics-api.binimum.org/";
static NSString *const kByISRC = @"https://lrc.red/s/%@.ttml";
// A recording is only taken when its length is this close to the track's, so the words fall on the
// same beat. The search is by name, and a live or sped up cut of the same song is a different take.
static const NSInteger kLengthSlack = 4;

// The best of what the search found: word timing wins over line timing, then the closest length.
static NSDictionary *bestOf(id results, NSInteger seconds) {
    NSDictionary *best = nil;
    BOOL bestWordTimed = NO;
    NSInteger bestOff = NSIntegerMax;
    for (NSDictionary *found in [results isKindOfClass:NSArray.class] ? results : @[]) {
        if (![found isKindOfClass:NSDictionary.class] || ![found[@"lyricsUrl"] isKindOfClass:NSString.class]) continue;
        // A length of null, or one that is not a number, is none to go on.
        double duration;
        NSInteger length = SGLyricsNumber(found[@"duration"], &duration) ? (NSInteger)duration : 0;
        NSInteger off = seconds > 0 ? (length > 0 ? labs(length - seconds) : NSIntegerMax) : 0;
        if (length > 0 && off > kLengthSlack) continue;
        BOOL wordTimed = [found[@"timing_type"] isEqual:@"word"];
        if (best && !(wordTimed && !bestWordTimed) && (bestWordTimed != wordTimed || off >= bestOff)) continue;
        best = found;
        bestWordTimed = wordTimed;
        bestOff = off;
    }
    return best;
}

static void searchByName(SGLyricsQuery *query, void (^done)(SGLyricsResult *result)) {
    if (!query.title.length || !query.artist.length) {
        SGLog(@"binilyrics: no names to search");
        done(nil);
        return;
    }
    NSMutableDictionary<NSString *, NSString *> *search = [NSMutableDictionary dictionaryWithDictionary:@{
        @"track": query.title,
        @"artist": query.artist,
    }];
    if (query.seconds > 0) search[@"duration"] = @(query.seconds).stringValue;
    if (query.album.length) search[@"album"] = query.album;
    NSInteger seconds = query.seconds;
    SGLyricsGetJSONTransformIn(query.requestContext, SGLyricsURL(kAPI, search), nil, ^id(id root) {
        id results = [root isKindOfClass:NSDictionary.class] ? root[@"results"] : nil;
        if (root && ![results isKindOfClass:NSArray.class]) [query.requestContext noteFailure:YES];
        if ([results isKindOfClass:NSArray.class] && ![results count])
            query.requestContext.emptyNameSearch = ^(SGLyricsQuery *again, void (^answer)(SGLyricsResult *)) { searchByName(again, answer); };
        return bestOf(results, seconds);
    }, ^(NSDictionary *found) {
        if (!found) {
            SGLog(@"binilyrics: no recording within %lds", (long)kLengthSlack);
            done(nil);
            return;
        }
        BOOL wordTimed = [found[@"timing_type"] isEqual:@"word"];
        NSURL *fileURL = [NSURL URLWithString:found[@"lyricsUrl"]];
        if (!SGLyricsBiniFileURLAllowed(fileURL)) {
            [query.requestContext noteFailure:YES];
            done(nil);
            return;
        }
        SGLyricsGetTextTransformIn(query.requestContext, fileURL, ^id(NSString *ttml) {
            SGLyricsResult *result = SGTTMLResult(ttml, wordTimed);
            if (ttml && !result) [query.requestContext noteFailure:YES];
            return result;
        }, ^(SGLyricsResult *result) {
            if (!result) SGLog(@"binilyrics: nothing the page could show");
            else SGLog(@"binilyrics: %lu %@ lines",
                       (unsigned long)result.karaokeLines.count, result.wordTimed ? @"word timed" : @"line timed");
            done(result);
        });
    });
}

SGLyricsAsk SGBiniLyricsAsk = ^(SGLyricsQuery *query, void (^done)(SGLyricsResult *result)) {
    if (!NSThread.isMainThread) { dispatch_async(dispatch_get_main_queue(), ^{ SGBiniLyricsAsk(query, done); }); return; }
    // ISRC lookup and its search fallback must describe the same recording even if the walk learns
    // new metadata while either request is outstanding.
    SGLyricsQuery *captured = [SGLyricsQuery new];
    captured.trackID = query.trackID; captured.title = query.title; captured.artist = query.artist;
    captured.album = query.album; captured.seconds = query.seconds;
    captured.requestContext = query.requestContext;
    query = captured;
    // The playback ISRC service logs the URI on failure. Bulk already has validated names.
    if (query.trackID.length != 22 || query.requestContext.bulk) {
        searchByName(query, done);
        return;
    }
    // Asked once: the lyrics wait on it, and the search is there when Spotify does not answer.
    dispatch_block_t cancelMetadata = SGSpotifyISRCWithOutcome([@"spotify:track:" stringByAppendingString:query.trackID], 1, ^(NSString *isrc, BOOL failed) {
        if (query.requestContext.cancelled) return;
        [query.requestContext noteFailure:failed];
        if (!isrc) {
            searchByName(query, done);
            return;
        }
        SGLyricsGetTextTransformIn(query.requestContext, [NSURL URLWithString:[NSString stringWithFormat:kByISRC, isrc]], ^id(NSString *ttml) {
            SGLyricsResult *result = SGTTMLResult(ttml, [ttml containsString:@"timing=\"Word\""]);
            if (ttml && !result) [query.requestContext noteFailure:YES];
            return result;
        }, ^(SGLyricsResult *result) {
            if (!result) {
                SGLog(@"binilyrics: nothing filed under %@, searched by name", isrc);
                searchByName(query, done);
                return;
            }
            SGLog(@"binilyrics: %@ (%@) has %lu %@ lines", query.title ?: query.trackID, isrc,
                  (unsigned long)result.karaokeLines.count, result.wordTimed ? @"word timed" : @"line timed");
            done(result);
        });
    });
    [query.requestContext onCancel:cancelMetadata];
};
