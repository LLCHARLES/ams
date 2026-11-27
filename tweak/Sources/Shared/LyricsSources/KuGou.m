// KuGou, word timing for the Mandarin, Cantonese and other Asian songs the rest only time by the line
// or not at all. Its KRC is NetEase's yrc in all but brackets and clock (SGLyricsPieceLines), packed:
// base64 of "krc1", then the zlib of the text XORed with a key KuGou's clients all carry. Searched by
// artist, title and length; the user uploads are left out, and a recording is only taken when its
// title, singer and length agree with the track's.
#import <zlib.h>
#import "Core/SGCore.h"
#import "LyricsSources.h"

static NSString *const kSearch = @"https://krcs.kugou.com/search";
static NSString *const kDownload = @"https://lyrics.kugou.com/download";
static const NSInteger kLengthSlackMs = 8000;
static const NSUInteger kTriedSongs = 3;
// Lyrics take a few kilobytes; anything that unpacks past this is not lyrics, and is refused.
static const NSUInteger kMostBytes = 1 << 20;
static const uint8_t kKey[16] = {64, 71, 97, 119, 94, 50, 116, 71, 81, 54, 49, 45, 206, 210, 110, 105};

NSArray<SGKaraokeLine *> *SGKuGouLines(NSString *content) {
    if (![content isKindOfClass:NSString.class] || content.length > 4 * ((kMostBytes + 2) / 3)) return nil;
    NSData *packed = [[NSData alloc] initWithBase64EncodedString:content options:NSDataBase64DecodingIgnoreUnknownCharacters];
    if (packed.length <= 4 || packed.length > kMostBytes || memcmp(packed.bytes, "krc1", 4) != 0) return nil;
    NSMutableData *zipped = [[packed subdataWithRange:NSMakeRange(4, packed.length - 4)] mutableCopy];
    uint8_t *bytes = zipped.mutableBytes;
    for (NSUInteger i = 0; i < zipped.length; i++) bytes[i] ^= kKey[i % sizeof kKey];
    NSMutableData *text = [NSMutableData dataWithLength:kMostBytes];
    uLongf length = kMostBytes;
    if (uncompress(text.mutableBytes, &length, bytes, zipped.length) != Z_OK) return nil;
    text.length = length;
    NSString *krc = [[NSString alloc] initWithData:text encoding:NSUTF8StringEncoding];
    return krc ? SGLyricsPieceLines(krc, YES) : nil;
}

// KuGou writes its ids as strings and its lengths as numbers, but either may come as the other.
static NSString *stringIn(id value) {
    return [value isKindOfClass:NSString.class] ? value : [value isKindOfClass:NSNumber.class] ? [value stringValue] : nil;
}

static double msIn(NSDictionary *candidate) {
    if (!candidate[@"duration"]) return 0;   // unknown, not a malformed supplied duration
    double duration;
    return SGLyricsNumber(candidate[@"duration"], &duration) ? duration : -1;
}

static NSDictionary<NSString *, NSString *> *headers(void) {
    return @{@"User-Agent": SGLyricsBrowserAgent};
}

static void tryLyrics(SGLyricsRequestContext *context, NSArray *candidates, NSUInteger index, void (^done)(NSArray<SGKaraokeLine *> *)) {
    if (index >= candidates.count || index >= kTriedSongs) {
        done(nil);
        return;
    }
    NSDictionary *candidate = candidates[index];
    NSURL *url = SGLyricsURL(kDownload, @{@"ver": @"1", @"client": @"pc", @"id": stringIn(candidate[@"id"]),
                                          @"accesskey": stringIn(candidate[@"accesskey"]), @"fmt": @"krc", @"charset": @"utf8"});
    SGLyricsGetJSONTransformIn(context, url, headers(), ^id(id root) {
        id status = [root isKindOfClass:NSDictionary.class] ? root[@"status"] : nil;
        if (root && ![status isEqual:@200] && ![status isEqual:@404]) [context noteFailure:YES];
        if (![status isEqual:@200]) return nil;
        id payload = root[@"content"];
        NSArray *lines = SGKuGouLines(payload);
        if (payload && payload != NSNull.null && ![payload isEqual:@""] && !lines) [context noteFailure:YES];
        return lines;
    }, ^(NSArray<SGKaraokeLine *> *lines) {
        if (lines) {
            SGLog(@"kugou: %lu word timed lines", (unsigned long)lines.count);
            done(lines);
        } else {
            tryLyrics(context, candidates, index + 1, done);
        }
    });
}

SGLyricsAsk SGKuGouAsk = ^(SGLyricsQuery *query, void (^done)(SGLyricsResult *result)) {
    if (!NSThread.isMainThread) { dispatch_async(dispatch_get_main_queue(), ^{ SGKuGouAsk(query, done); }); return; }
    NSString *title = SGLyricsMatchKey(query.title), *lead = SGLyricsLeadArtist(query.artist);
    if (!title.length || !SGLyricsMatchKey(lead).length) {
        done(nil);
        return;
    }
    NSInteger ms = SGLyricsSecondsToMs(@(query.seconds));
    if (ms < 0) { done(nil); return; }
    NSMutableDictionary<NSString *, NSString *> *search = [@{@"ver": @"1", @"man": @"yes", @"client": @"mobi", @"hash": @"",
        @"album_audio_id": @"", @"keyword": [NSString stringWithFormat:@"%@ - %@", lead, query.title]} mutableCopy];
    if (ms > 0) search[@"duration"] = @(ms).stringValue;
    SGLyricsGetJSONTransformIn(query.requestContext, SGLyricsURL(kSearch, search), headers(), ^id(id root) {
        id candidates = [root isKindOfClass:NSDictionary.class] ? root[@"candidates"] : nil;
        if (root && ![candidates isKindOfClass:NSArray.class] && ![SGLyricsField(root, @"status") isEqual:@404])
            [query.requestContext noteFailure:YES];
        if ([candidates isKindOfClass:NSArray.class] && ![candidates count])
            query.requestContext.emptyNameSearch = SGKuGouAsk;
        NSMutableArray<NSDictionary *> *fitting = [NSMutableArray array];
        for (NSDictionary *candidate in [candidates isKindOfClass:NSArray.class] ? candidates : @[]) {
            if (![candidate isKindOfClass:NSDictionary.class]) continue;
            if (!stringIn(candidate[@"id"]).length || !stringIn(candidate[@"accesskey"]).length) continue;
            if ([candidate[@"product_from"] isEqual:@"ugc"]) continue;
            if (![SGLyricsMatchKey(candidate[@"song"]) isEqualToString:title]) continue;
            if (!SGLyricsSameArtist(candidate[@"singer"], lead)) continue;
            double duration = msIn(candidate);
            if (duration < 0 || (ms > 0 && duration > 0 && fabs(duration - ms) > kLengthSlackMs)) continue;
            [fitting addObject:candidate];
        }
        [fitting sortWithOptions:NSSortStable usingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
            return [@(fabs(msIn(a) - ms)) compare:@(fabs(msIn(b) - ms))];
        }];
        return [fitting copy];
    }, ^(NSArray *fitting) {
        if (!fitting.count) SGLog(@"kugou: no matching recording");
        tryLyrics(query.requestContext, fitting, 0, ^(NSArray<SGKaraokeLine *> *lines) {
            if (!lines.count) {
                done(nil);
                return;
            }
            SGLyricsResult *result = [SGLyricsResult new];
            result.wordTimed = result.synced = YES;
            result.karaokeLines = lines;
            NSArray<NSNumber *> *starts;
            NSArray<NSString *> *texts;
            SGLyricsPageLines(lines, &starts, &texts);
            result.starts = starts;
            result.texts = texts;
            done(result);
        });
    });
};
