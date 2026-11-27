// Unison, the lyrics people write for Better Lyrics by hand. It is a small corpus next to the rest,
// but what is in it is Apple Music's own TTML at its best, so it earns being asked early: what it
// misses the next source answers, and what it has beats what that source would have given.
//
// Reads need no key. The write half of its API — submitting, voting, reporting — is signed, and the
// mod does none of it: it asks for lyrics and nothing else.
#import "Core/SGCore.h"
#import "LyricsSources.h"

static NSString *const kAPI = @"https://unison.boidu.dev/lyrics";
static const NSInteger kLengthSlack = 4;

SGLyricsAsk SGUnisonAsk = ^(SGLyricsQuery *query, void (^done)(SGLyricsResult *result)) {
    if (!query.title.length || !query.artist.length) {
        SGLog(@"unison: no names to search");
        done(nil);
        return;
    }
    // song and artist alone answer with the highest scored match; album and duration narrow it.
    NSMutableDictionary<NSString *, NSString *> *search = [NSMutableDictionary dictionaryWithDictionary:@{
        @"song": query.title,
        @"artist": query.artist,
    }];
    if (query.seconds > 0) search[@"duration"] = @(query.seconds).stringValue;
    if (query.album.length) search[@"album"] = query.album;
    SGLyricsGetJSONReplyIn(query.requestContext, SGLyricsURL(kAPI, search), nil, ^(id root, NSHTTPURLResponse *response) {
        id data = [root isKindOfClass:NSDictionary.class] ? root[@"data"] : nil;
        if (response.statusCode == 404 || (response.statusCode == 200 && data == NSNull.null))
            query.requestContext.emptyNameSearch = SGUnisonAsk;
        if (![data isKindOfClass:NSDictionary.class]) {
            if (response.statusCode == 200 && data != NSNull.null) [query.requestContext noteFailure:YES];
            SGLog(@"unison: no matching lyrics");
            done(nil);
            return;
        }
        // Unison also keeps LRC and plain text, which carry nothing the other sources do not.
        if (![data[@"format"] isEqual:@"ttml"]) {
            SGLog(@"unison: not TTML");
            done(nil);
            return;
        }
        // A length of null, or one that is not a number, is none to go on.
        double duration;
        NSInteger length = SGLyricsNumber(data[@"duration"], &duration) ? (NSInteger)duration : 0;
        if (query.seconds > 0 && length > 0 && labs(length - query.seconds) > kLengthSlack) {
            SGLog(@"unison: duration mismatch");
            done(nil);
            return;
        }
        SGLyricsResult *result = SGTTMLResult(data[@"lyrics"], [data[@"syncType"] isEqual:@"richsync"]);
        if (!result) {
            [query.requestContext noteFailure:YES];
            done(nil);
            return;
        }
        SGLog(@"unison: %lu %@ lines", (unsigned long)result.karaokeLines.count, result.wordTimed ? @"word timed" : @"line timed");
        done(result);
    });
};
