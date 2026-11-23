// Request fields and base64/WSY schema from EeveeSpotifyReincarnated (GPL-3),
// PetitLyricsRepository.swift at 0d9feaa. Unlike its synchronous adapter, this keeps
// candidate matching and word clocks and uses Retrine's bounded asynchronous transport.
#import "Core/SGCore.h"
#import "LyricsSources.h"

@interface SGPetitXML : NSObject <NSXMLParserDelegate>
@property (nonatomic) NSMutableArray<NSMutableDictionary *> *stack;
@property (nonatomic) NSDictionary *root;
@property (nonatomic) NSUInteger nodes;
@end
@implementation SGPetitXML
- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)name namespaceURI:(NSString *)uri qualifiedName:(NSString *)qualified attributes:(NSDictionary *)attributes {
    if (++self.nodes > 20000 || self.stack.count >= 8) { [parser abortParsing]; return; }
    NSMutableDictionary *node = [@{@"name": name, @"text": [NSMutableString string], @"children": [NSMutableArray array]} mutableCopy];
    if (self.stack.count) [self.stack.lastObject[@"children"] addObject:node];
    else self.root = node;
    [self.stack addObject:node];
}
- (void)parser:(NSXMLParser *)parser foundCharacters:(NSString *)text {
    [self.stack.lastObject[@"text"] appendString:text];
}
- (void)parser:(NSXMLParser *)parser foundCDATA:(NSData *)data {
    NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (!text) [parser abortParsing];
    else [self.stack.lastObject[@"text"] appendString:text];
}
- (void)parser:(NSXMLParser *)parser didEndElement:(NSString *)name namespaceURI:(NSString *)uri qualifiedName:(NSString *)qualified {
    [self.stack removeLastObject];
}
@end

static NSDictionary *xml(NSData *data) {
    if (!data.length || data.length > 2 * 1024 * 1024) return nil;
    // No DTDs: disabling external resolution alone still permits internal entity expansion.
    NSString *source = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (!source || [source rangeOfString:@"<!DOCTYPE" options:NSCaseInsensitiveSearch].location != NSNotFound) return nil;
    SGPetitXML *reader = [SGPetitXML new];
    reader.stack = [NSMutableArray array];
    NSXMLParser *parser = [[NSXMLParser alloc] initWithData:data];
    parser.shouldResolveExternalEntities = NO;
    parser.delegate = reader;
    return [parser parse] ? reader.root : nil;
}
static NSArray *children(NSDictionary *node, NSString *name) {
    NSMutableArray *found = [NSMutableArray array];
    for (NSDictionary *child in node[@"children"])
        if ([child[@"name"] isEqual:name]) [found addObject:child];
    return found;
}
static NSString *field(NSDictionary *node, NSString *name) {
    return [children(node, name) firstObject][@"text"];
}
static NSArray *songs(NSData *data) {
    NSDictionary *root = xml(data);
    if (![root[@"name"] isEqual:@"response"]) return nil;
    NSString *status = field(root, @"status");
    if (status && ![status isEqual:@"00000000"]) return nil;
    NSDictionary *list = [children(root, @"songs") firstObject];
    if (!list) return nil;
    NSArray *items = children(list, @"song");
    return items.count <= 100 ? items : nil;
}

static SGLyricsResult *sheet(NSDictionary *song) {
    NSData *data = [[NSData alloc] initWithBase64EncodedString:field(song, @"lyricsData") ?: @"" options:0];
    NSString *text = data.length <= 262144 ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
    if (!text.length) return nil;
    NSString *type = field(song, @"lyricsType");
    if ([type isEqual:@"1"]) return SGLyricsPlainTextResult(text, @"PetitLyrics");
    if (![type isEqual:@"3"]) return nil;
    NSDictionary *root = xml(data);
    if (![root[@"name"] isEqual:@"wsy"]) return nil;
    NSArray *rows = children(root, @"line");
    if (rows.count > 4000) return nil;
    NSMutableArray *lines = [NSMutableArray array];
    for (NSDictionary *row in rows) {
        NSString *text = field(row, @"linestring");
        if (!text.length) continue;
        if (text.length > 4096) return nil;
        NSMutableArray<SGKaraokePiece *> *pieces = [NSMutableArray array];
        NSUInteger cursor = 0;
        NSInteger previous = -1;
        NSInteger lineEnd = 0;
        for (NSDictionary *word in children(row, @"word")) {
            double start, end;
            NSString *raw = field(word, @"wordstring");
            NSString *token = [raw stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
            if (!token.length || !SGLyricsNumber(field(word, @"starttime"), &start) ||
                !SGLyricsNumber(field(word, @"endtime"), &end) || end <= start || start < previous) return nil;
            NSRange at = [text rangeOfString:token options:0 range:NSMakeRange(cursor, text.length - cursor)];
            if (at.location == NSNotFound) return nil;
            NSString *gap = [text substringWithRange:NSMakeRange(cursor, at.location - cursor)];
            if ([gap stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet].length) return nil;
            SGKaraokePiece *piece = [SGKaraokePiece new];
            piece.text = token;
            piece.start = llround(start);
            piece.end = llround(end);
            lineEnd = MAX(lineEnd, piece.end);
            piece.spaceBefore = gap.length > 0;
            [pieces addObject:piece];
            cursor = NSMaxRange(at);
            previous = piece.start;
        }
        if (!pieces.count || [[text substringFromIndex:cursor] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet].length) return nil;
        SGKaraokeLine *line = SGKaraokePieceLine(pieces, [pieces.firstObject start], lineEnd);
        if (!line) return nil;
        [lines addObject:line];
    }
    return SGLyricsResultWithLines(lines, @"PetitLyrics");
}

static void request(SGLyricsRequestContext *context, NSDictionary *parameters, id (^transform)(NSArray *), void (^done)(id)) {
    NSMutableDictionary *form = [parameters mutableCopy];
    form[@"clientAppId"] = @"p1110417";
    form[@"terminalType"] = @"10";
    NSMutableArray *pairs = [NSMutableArray array];
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:@"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"];
    for (NSString *key in form) [pairs addObject:[NSString stringWithFormat:@"%@=%@", key,
        [form[key] stringByAddingPercentEncodingWithAllowedCharacters:allowed]]];
    NSData *body = [[pairs componentsJoinedByString:@"&"] dataUsingEncoding:NSUTF8StringEncoding];
    SGLyricsSourceRequestIn(context, [NSURL URLWithString:@"https://p1.petitlyrics.com/api/GetPetitLyricsData.php"],
        @{@"Content-Type": @"application/x-www-form-urlencoded"}, body, ^(NSData *data, NSInteger status) {
        SGLyricsTransform(^id {
            if (status != 200) return nil;
            NSArray *items = songs(data);
            if (!items) { [context noteFailure:YES]; return nil; }
            return transform(items);
        }, done);
    });
}

static void fetch(SGLyricsRequestContext *context, NSArray *candidates, NSUInteger index, void (^done)(SGLyricsResult *)) {
    if (index >= MIN(candidates.count, 3u)) { done(nil); return; }
    NSDictionary *song = candidates[index];
    NSString *identifier = field(song, @"lyricsId");
    // Type 2 is a binary MHDROBJT sheet, not LRC. Like Eevee, request its
    // plain representation rather than inventing clocks or treating binary as text.
    NSString *type = field(song, @"availableLyricsType");
    request(context, @{@"key_lyricsId": identifier, @"lyricsType": [type isEqual:@"2"] ? @"1" : type},
        ^id(NSArray *items) {
            for (NSDictionary *item in items) {
                if (![field(item, @"lyricsId") isEqual:identifier]) continue;
                SGLyricsResult *result = sheet(item);
                if (field(item, @"lyricsData").length && !result) [context noteFailure:YES];
                return result;
            }
            return nil;
        }, ^(SGLyricsResult *result) {
            if (result || context.failed) done(result);
            else fetch(context, candidates, index + 1, done);
        });
}

SGLyricsAsk SGPetitLyricsAsk = ^(SGLyricsQuery *query, void (^done)(SGLyricsResult *)) {
    if (!NSThread.isMainThread) { dispatch_async(dispatch_get_main_queue(), ^{ SGPetitLyricsAsk(query, done); }); return; }
    if (!query.title.length || !query.artist.length) { done(nil); return; }
    request(query.requestContext, @{@"key_title": query.title, @"key_artist": SGLyricsLeadArtist(query.artist), @"max_count": @"30"},
        ^id(NSArray *items) {
            if (!items.count) query.requestContext.emptyNameSearch = SGPetitLyricsAsk;
            NSMutableArray *matches = [NSMutableArray array];
            for (NSDictionary *song in items) {
                NSInteger rank = SGLyricsSongRank(query.title, query.artist, field(song, @"title"), @[field(song, @"artist") ?: @""]);
                double duration = 0;
                NSString *length = field(song, @"duration");
                if (length.length && !SGLyricsNumber(length, &duration)) continue;
                if (!rank || (duration > 0 && query.seconds > 0 && fabs(duration / 1000 - query.seconds) > 4)) continue;
                if (!SGLyricsDecimalID(field(song, @"lyricsId"))) continue;
                if (![@[@"1", @"2", @"3"] containsObject:field(song, @"availableLyricsType") ?: @""]) continue;
                [matches addObject:@{@"song": song, @"rank": @(rank),
                    @"distance": @(duration > 0 && query.seconds > 0 ? fabs(duration / 1000 - query.seconds) : DBL_MAX)}];
            }
            [matches sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
                NSComparisonResult rank = [b[@"rank"] compare:a[@"rank"]];
                return rank == NSOrderedSame ? [a[@"distance"] compare:b[@"distance"]] : rank;
            }];
            return [matches valueForKey:@"song"];
        }, ^(NSArray *candidates) { fetch(query.requestContext, candidates, 0, done); });
};
