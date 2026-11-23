// QQ Music, for the Mandarin, Cantonese and other Asian songs the rest have no timed lyrics for.
// QRC supplies real word clocks; when it cannot be read, the existing plain LRC request remains.
// Searched by title and artist, and a recording is only taken when its title
// is the track's, one of its singers is the track's artist and its length is about the track's, so a
// cover or a namesake by someone else is passed over.
#import "Core/SGCore.h"
#import "LyricsSources.h"
#import <zlib.h>

static NSString *const kAPI = @"https://u.y.qq.com/cgi-bin/musicu.fcg";
static const NSInteger kLengthSlack = 6;
static NSString *const kLyricRequest = @"music.musichallSong.PlayLyricInfo.GetPlayLyricInfo";

NSString *SGLyricsLeadArtist(NSString *artist) {
    NSRange featuring = [artist rangeOfString:@" feat" options:NSCaseInsensitiveSearch];
    return featuring.location == NSNotFound ? artist : [artist substringToIndex:featuring.location];
}

static id dig(id root, NSArray<NSString *> *path) {
    for (NSString *key in path) root = [root isKindOfClass:NSDictionary.class] ? root[key] : nil;
    return root;
}

static void ask(SGLyricsRequestContext *context, NSString *name, NSDictionary *request, id (^transform)(id), void (^done)(id reply)) {
    NSDictionary *body = @{@"comm": @{@"ct": @"19", @"cv": @"1859", @"uin": @"0"}, name: request};
    NSDictionary *headers = @{@"Referer": @"https://y.qq.com/", @"User-Agent": SGLyricsBrowserAgent, @"Accept": @"application/json"};
    SGLyricsPostJSONTransformIn(context, [NSURL URLWithString:kAPI], headers, body, ^id(id root) {
        id data = dig(root, @[name, @"data"]);
        id code = dig(root, @[@"code"]), subcode = dig(root, @[name, @"code"]);
        if (root && (!data || ([code isKindOfClass:NSNumber.class] && [code integerValue] != 0) ||
            ([subcode isKindOfClass:NSNumber.class] && [subcode integerValue] != 0))) [context noteFailure:YES];
        return transform(data);
    }, done);
}

// The first recording on the page that is the track: QQ ranks its own catalog well, so the first
// that fits is taken rather than the closest in length.
static NSNumber *songFor(id data, NSString *title, NSString *artist, NSInteger seconds) {
    id list = dig(data, @[@"body", @"song", @"list"]);
    for (NSDictionary *song in [list isKindOfClass:NSArray.class] ? list : @[]) {
        if (![song isKindOfClass:NSDictionary.class]) continue;
        id name = [song[@"title"] isKindOfClass:NSString.class] ? song[@"title"] : song[@"songname"];
        if (![SGLyricsMatchKey(name) isEqualToString:title]) continue;
        id interval = song[@"interval"];
        NSInteger length = [interval isKindOfClass:NSNumber.class] ? [interval integerValue] : 0;
        if (seconds > 0 && length > 0 && labs(length - seconds) > kLengthSlack) continue;
        BOOL sung = NO;
        id singers = song[@"singer"];
        for (NSDictionary *singer in [singers isKindOfClass:NSArray.class] ? singers : @[]) {
            sung = sung || ([singer isKindOfClass:NSDictionary.class] && SGLyricsSameArtist(singer[@"name"], artist));
        }
        if (sung && [song[@"id"] isKindOfClass:NSNumber.class]) return song[@"id"];
    }
    return nil;
}

// QRC's LyricContent is an XML attribute, including literal newlines. Preserve those before XML
// attribute normalization, and let the XML reader decode entities without resolving external ones.
@interface SGQQContentReader : NSObject <NSXMLParserDelegate>
@property (nonatomic, copy) NSString *content;
@end
@implementation SGQQContentReader
- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)element namespaceURI:(NSString *)uri
 qualifiedName:(NSString *)qualified attributes:(NSDictionary<NSString *, NSString *> *)attributes {
    self.content = attributes[@"text"];
}
@end

static const NSUInteger kQRCMaxBytes = 1 << 20;

static NSArray<SGKaraokeLine *> *qrcLines(NSString *text) {
    NSRange marker = [text rangeOfString:@"LyricContent=\""];
    if (marker.location == NSNotFound) return nil;
    NSUInteger from = NSMaxRange(marker);
    NSRange end = [text rangeOfString:@"\"" options:0 range:NSMakeRange(from, text.length - from)];
    if (end.location == NSNotFound) return nil;
    NSString *attribute = [text substringWithRange:NSMakeRange(from, end.location - from)];
    attribute = [[attribute stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"]
        stringByReplacingOccurrencesOfString:@"\n" withString:@"&#10;"];
    NSXMLParser *xml = [[NSXMLParser alloc] initWithData:
        [[NSString stringWithFormat:@"<q text=\"%@\"/>", attribute] dataUsingEncoding:NSUTF8StringEncoding]];
    SGQQContentReader *reader = [SGQQContentReader new];
    xml.delegate = reader;
    xml.shouldResolveExternalEntities = NO;
    if (![xml parse] || !reader.content.length) return nil;
    static NSRegularExpression *header, *clock, *tag;
    static NSCharacterSet *nonDigits;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        header = [NSRegularExpression regularExpressionWithPattern:@"^\\[(\\d+),(\\d+)\\]" options:0 error:nil];
        // Recognize clock tuples before validating their fields; skipping a malformed tuple would
        // silently turn it into the next timed word's text.
        clock = [NSRegularExpression regularExpressionWithPattern:@"\\(([^(),]*),([^()]*)\\)" options:0 error:nil];
        nonDigits = [NSCharacterSet characterSetWithCharactersInString:@"0123456789"].invertedSet;
        tag = [NSRegularExpression regularExpressionWithPattern:@"^\\[[A-Za-z]+:.*\\]$" options:0 error:nil];
    });
    NSMutableArray *lines = [NSMutableArray array];
    for (NSString *row in [reader.content componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
        if (!row.length || [tag firstMatchInString:row options:0 range:NSMakeRange(0, row.length)]) continue;
        NSTextCheckingResult *head = [header firstMatchInString:row options:0 range:NSMakeRange(0, row.length)];
        if (!head) return nil;
        double start, duration;
        if (!SGLyricsNumber([row substringWithRange:[head rangeAtIndex:1]], &start) ||
            !SGLyricsNumber([row substringWithRange:[head rangeAtIndex:2]], &duration) ||
            start + duration > SGKaraokeMaxTimeMs) return nil;
        NSUInteger cursor = NSMaxRange(head.range);
        NSArray *clocks = [clock matchesInString:row options:0 range:NSMakeRange(cursor, row.length - cursor)];
        NSMutableArray *pieces = [NSMutableArray array];
        double previous = start;
        for (NSTextCheckingResult *match in clocks) {
            NSString *raw = [row substringWithRange:NSMakeRange(cursor, match.range.location - cursor)];
            NSString *atText = [row substringWithRange:[match rangeAtIndex:1]];
            NSString *lengthText = [row substringWithRange:[match rangeAtIndex:2]];
            double at, length;
            if (!raw.length || [atText rangeOfCharacterFromSet:nonDigits].location != NSNotFound ||
                [lengthText rangeOfCharacterFromSet:nonDigits].location != NSNotFound ||
                !SGLyricsNumber(atText, &at) || !SGLyricsNumber(lengthText, &length) ||
                at < previous || at + length > SGKaraokeMaxTimeMs) return nil;
            SGKaraokePiece *piece = [SGKaraokePiece new];
            piece.text = [raw stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
            piece.spaceBefore = [NSCharacterSet.whitespaceCharacterSet characterIsMember:[raw characterAtIndex:0]];
            piece.spaceAfter = [NSCharacterSet.whitespaceCharacterSet characterIsMember:[raw characterAtIndex:raw.length - 1]];
            piece.start = (NSInteger)at;
            piece.end = (NSInteger)(at + length);
            [pieces addObject:piece];
            previous = at;
            cursor = NSMaxRange(match.range);
        }
        if (cursor != row.length || !pieces.count) return nil;
        SGKaraokeLine *line = SGKaraokePieceLine(pieces, (NSInteger)start, (NSInteger)(start + duration));
        if (!line) return nil;
        line.timing = SGKaraokeTimingWords;
        [lines addObject:line];
    }
    return lines.count ? lines : nil;
}

SGLyricsResult *SGQQMusicResult(id payload) {
    NSString *encoded = SGLyricsString(payload, ((kQRCMaxBytes + 2) / 3) * 4);
    NSData *bytes = encoded ? [[NSData alloc] initWithBase64EncodedString:encoded options:0] : nil;
    if (!bytes.length || bytes.length > kQRCMaxBytes) return nil;
    // Supported crypt=0 payloads are UTF-8 or zlib, not the encrypted QRC file format.
    const uint8_t *header = bytes.bytes;
    BOOL zipped = bytes.length >= 2 && (header[0] & 15) == Z_DEFLATED &&
        (header[0] >> 4) <= 7 && ((header[0] << 8) + header[1]) % 31 == 0;
    NSString *text;
    if (zipped) {
        NSMutableData *expanded = [NSMutableData dataWithLength:kQRCMaxBytes];
        uLongf length = kQRCMaxBytes;
        if (uncompress(expanded.mutableBytes, &length, bytes.bytes, bytes.length) != Z_OK) return nil;
        expanded.length = length;
        text = [[NSString alloc] initWithData:expanded encoding:NSUTF8StringEncoding];
    } else text = [[NSString alloc] initWithData:bytes encoding:NSUTF8StringEncoding];
    if (!text.length) return nil;
    NSArray *lines = qrcLines(text);
    return lines ? SGLyricsResultWithLines(lines, nil) : SGLyricsLRCResult(text);
}

static void lyricsFor(SGLyricsRequestContext *context, NSNumber *song, BOOL qrc, void (^done)(SGLyricsResult *)) {
    ask(context, kLyricRequest, @{@"module": @"music.musichallSong.PlayLyricInfo", @"method": @"GetPlayLyricInfo",
        @"param": @{@"crypt": @0, @"qrc": @(qrc), @"songID": song}},
        ^id(id data) {
            id payload = dig(data, @[@"lyric"]);
            SGLyricsResult *result = SGQQMusicResult(payload);
            if (payload && payload != NSNull.null && ![payload isEqual:@""] && !result) [context noteFailure:YES];
            return result;
        }, ^(SGLyricsResult *result) {
            if (!result && qrc) { lyricsFor(context, song, NO, done); return; }
            SGLog(@"qqmusic: song %@ gave %lu timed lines", song, (unsigned long)result.karaokeLines.count);
            done(result);
        });
}

SGLyricsAsk SGQQMusicAsk = ^(SGLyricsQuery *query, void (^done)(SGLyricsResult *result)) {
    if (!NSThread.isMainThread) { dispatch_async(dispatch_get_main_queue(), ^{ SGQQMusicAsk(query, done); }); return; }
    NSString *lead = SGLyricsLeadArtist(query.artist);
    if (!SGLyricsMatchKey(query.title).length || !SGLyricsMatchKey(lead).length) {
        done(nil);
        return;
    }
    NSString *title = SGLyricsMatchKey(query.title), *artist = [query.artist copy];
    NSInteger seconds = query.seconds;
    ask(query.requestContext, @"req", @{@"module": @"music.search.SearchCgiService", @"method": @"DoSearchForQQMusicDesktop", @"param": @{
        @"query": [NSString stringWithFormat:@"%@ %@", query.title, lead],
        @"search_type": @0, @"grp": @1, @"num_per_page": @8, @"page_num": @1,
    }}, ^id(id found) {
        id list = dig(found, @[@"body", @"song", @"list"]);
        if ([list isKindOfClass:NSArray.class] && ![list count])
            query.requestContext.emptyNameSearch = SGQQMusicAsk;
        return songFor(found, title, artist, seconds);
    }, ^(NSNumber *song) {
        if (!song) {
            SGLog(@"qqmusic: no recording of %@ by %@ near %lds", query.title, lead, (long)query.seconds);
            done(nil);
            return;
        }
        lyricsFor(query.requestContext, song, YES, done);
    });
};
