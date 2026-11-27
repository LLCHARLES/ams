// Genie's search is HTML. Each candidate is read inside its own table row so a title can never pick
// up the next row's artist or id. Its lyrics callback wraps a dictionary keyed by milliseconds.
#import "Core/SGCore.h"
#import "LyricsSources.h"

static NSRegularExpression *expression(NSString *pattern) {
    // The same fixed patterns are used for every row, anchor and entity on the search page.
    static NSCache<NSString *, NSRegularExpression *> *kept;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ kept = [NSCache new]; kept.countLimit = 16; });
    NSRegularExpression *regex = [kept objectForKey:pattern];
    if (!regex) {
        regex = [NSRegularExpression regularExpressionWithPattern:pattern options:NSRegularExpressionCaseInsensitive | NSRegularExpressionDotMatchesLineSeparators error:nil];
        if (regex) [kept setObject:regex forKey:pattern];
    }
    return regex;
}
static NSArray<NSTextCheckingResult *> *matches(NSString *pattern, NSString *text) {
    NSRegularExpression *regex = expression(pattern);
    return [regex matchesInString:text options:0 range:NSMakeRange(0, text.length)];
}
static NSString *capture(NSString *pattern, NSString *text) {
    NSTextCheckingResult *match = matches(pattern, text).firstObject;
    return match && [match rangeAtIndex:1].location != NSNotFound ? [text substringWithRange:[match rangeAtIndex:1]] : nil;
}

// Only text and attributes are needed. Decode the common named entities and numeric references,
// without asking a web view to render a page or load its links.
static NSString *unescape(NSString *text) {
    if (!text) return nil;
    NSMutableString *out = [text mutableCopy];
    NSArray *entities = matches(@"&#(x[0-9a-f]+|[0-9]+);", text);
    for (NSTextCheckingResult *match in entities.reverseObjectEnumerator) {
        NSString *digits = [text substringWithRange:[match rangeAtIndex:1]];
        unsigned long code = strtoul(([digits hasPrefix:@"x"] || [digits hasPrefix:@"X"] ? [digits substringFromIndex:1] : digits).UTF8String, NULL, [digits.lowercaseString hasPrefix:@"x"] ? 16 : 10);
        if (!code || code > 0x10FFFF || (code >= 0xD800 && code <= 0xDFFF)) continue;
        UTF32Char scalar = (UTF32Char)code;
        NSString *value = [[NSString alloc] initWithBytes:&scalar length:sizeof(scalar) encoding:NSUTF32LittleEndianStringEncoding];
        if (value) [out replaceCharactersInRange:match.range withString:value];
    }
    for (NSArray *pair in @[@[@"&quot;", @"\""], @[@"&apos;", @"'"], @[@"&lt;", @"<"], @[@"&gt;", @">"], @[@"&nbsp;", @" "], @[@"&amp;", @"&"]])
        [out replaceOccurrencesOfString:pair[0] withString:pair[1] options:0 range:NSMakeRange(0, out.length)];
    return [out stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

// Search for each delimiter once. In particular a missing closer ends the scan instead of
// restarting a body match at every subsequent opener.
static BOOL nextTag(NSString *text, NSString *start, NSString *finish, NSUInteger *cursor,
                    NSRange *opening, NSRange *body) {
    NSRange tail = NSMakeRange(*cursor, text.length - *cursor);
    NSRange name = [expression(start) rangeOfFirstMatchInString:text options:0 range:tail];
    if (name.location == NSNotFound) return NO;
    NSUInteger at = NSMaxRange(name);
    NSRange gt = [text rangeOfString:@">" options:NSLiteralSearch range:NSMakeRange(at, text.length - at)];
    if (gt.location == NSNotFound) return NO;
    at = NSMaxRange(gt);
    NSRange end = [expression(finish) rangeOfFirstMatchInString:text options:0 range:NSMakeRange(at, text.length - at)];
    if (end.location == NSNotFound) return NO;
    *opening = NSMakeRange(name.location, at - name.location);
    *body = NSMakeRange(at, end.location - at);
    *cursor = NSMaxRange(end);
    return YES;
}

static NSString *anchor(NSString *row, NSString *kind) {
    NSUInteger cursor = 0;
    NSRange opening, content;
    while (nextTag(row, @"<a\\b", @"</a\\s*>", &cursor, &opening, &content)) {
        NSString *tag = [row substringWithRange:NSMakeRange(opening.location, cursor - opening.location)];
        NSString *classes = capture(@"\\bclass\\s*=\\s*['\"]([^'\"]*)['\"]", tag);
        if (![[classes componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] containsObject:kind]) continue;
        NSString *title = capture(@"\\btitle\\s*=\\s*['\"]([^'\"]*)['\"]", tag);
        if ([kind isEqualToString:@"title"] && title.length) return unescape(title);
        NSString *body = [row substringWithRange:content];
        NSMutableString *text = [NSMutableString string];
        NSUInteger at = 0;
        while (at < body.length) {
            NSRange open = [body rangeOfString:@"<" options:NSLiteralSearch range:NSMakeRange(at, body.length - at)];
            if (open.location == NSNotFound) break;
            NSUInteger afterOpen = NSMaxRange(open);
            NSRange close = [body rangeOfString:@">" options:NSLiteralSearch range:NSMakeRange(afterOpen, body.length - afterOpen)];
            if (close.location == NSNotFound) break;
            [text appendString:[body substringWithRange:NSMakeRange(at, open.location - at)]];
            at = NSMaxRange(close);
        }
        [text appendString:[body substringFromIndex:at]];
        return unescape(text);
    }
    return nil;
}

static NSString *songFor(NSString *html, NSString *title, NSString *artist, BOOL *empty) {
    if (!html.length || html.length > 1024 * 1024) return nil;
    *empty = [html containsString:@"검색 결과가 없습니다"];
    NSUInteger count = 0, cursor = 0;
    NSRange head, content;
    while (nextTag(html, @"<tr\\b", @"</tr\\s*>", &cursor, &head, &content)) {
        if (++count > 300) { *empty = NO; break; }
        if (cursor - head.location > 32768) { *empty = NO; continue; }
        NSString *opening = [html substringWithRange:head];
        NSString *classes = capture(@"\\bclass\\s*=\\s*['\"]([^'\"]*)['\"]", opening);
        if (![[classes componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] containsObject:@"list"]) continue;
        *empty = NO;
        NSString *song = SGLyricsDecimalID(capture(@"\\bsongid\\s*=\\s*['\"]([0-9]+)['\"]", opening));
        NSString *row = [html substringWithRange:content];
        if (song && [SGLyricsMatchKey(anchor(row, @"title")) isEqualToString:SGLyricsMatchKey(title)] && SGLyricsSameArtist(anchor(row, @"artist"), artist)) return song;
    }
    return nil;
}

SGLyricsResult *SGGenieResult(NSString *jsonp) {
    if (!SGLyricsString(jsonp, 262144).length) return nil;
    NSRange open = [jsonp rangeOfString:@"("], close = [jsonp rangeOfString:@")" options:NSBackwardsSearch];
    if (open.location == NSNotFound || close.location == NSNotFound || close.location <= open.location) return nil;
    NSString *body = [jsonp substringWithRange:NSMakeRange(open.location + 1, close.location - open.location - 1)];
    id root = [NSJSONSerialization JSONObjectWithData:[body dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
    if (![root isKindOfClass:NSDictionary.class] || ![root count] || [root count] > 2000) return nil;
    NSMutableArray *rows = [NSMutableArray array];
    for (id key in root) {
        double at;
        NSString *text = SGLyricsString(root[key], 4096);
        if (!SGLyricsDecimalID(key) || !SGLyricsNumber(key, &at) || !text) return nil;
        [rows addObject:@{@"at": @(llround(at)), @"text": text}];
    }
    [rows sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) { return [a[@"at"] compare:b[@"at"]]; }];
    return SGLyricsResultWithLines(SGKaraokeEstimatedLines([rows valueForKey:@"at"], [rows valueForKey:@"text"]), @"Genie");
}

SGLyricsAsk SGGenieAsk = ^(SGLyricsQuery *query, void (^done)(SGLyricsResult *)) {
    if (!NSThread.isMainThread) { dispatch_async(dispatch_get_main_queue(), ^{ SGGenieAsk(query, done); }); return; }
    if (!SGLyricsMatchKey(query.title).length || !SGLyricsMatchKey(query.artist).length) { done(nil); return; }
    NSDictionary *headers = @{@"User-Agent": @"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15", @"Referer": @"https://www.genie.co.kr/"};
    NSURL *url = SGLyricsURL(@"https://www.genie.co.kr/search/searchMain", @{@"query": [NSString stringWithFormat:@"%@ %@", query.title, SGLyricsLeadArtist(query.artist)]});
    NSString *title = query.title, *artist = query.artist;
    SGLyricsSourceRequestIn(query.requestContext, url, headers, nil, ^(NSData *data, NSInteger status) {
        SGLyricsTransform(^id {
            NSString *html = status == 200 && data.length ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
            BOOL empty = NO;
            NSString *song = songFor(html, title, artist, &empty);
            if (empty) query.requestContext.emptyNameSearch = SGGenieAsk;
            return song;
        }, ^(NSString *song) {
        if (!song) { done(nil); return; }
        SGLyricsSourceRequestIn(query.requestContext, SGLyricsURL(@"https://dn.genie.co.kr/app/purchase/get_msl.asp", @{@"path": @"a", @"songid": song}), headers, nil, ^(NSData *answer, NSInteger code) {
            SGLyricsTransform(^id {
                NSString *text = code == 200 ? [[NSString alloc] initWithData:answer encoding:NSUTF8StringEncoding] : nil;
                SGLyricsResult *result = text.length ? SGGenieResult(text) : nil;
                if (code == 200 && answer.length && !result &&
                    ![[text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] isEqual:@"NOT FOUND LYRICS"])
                    [query.requestContext noteFailure:YES];
                return result;
            }, ^(SGLyricsResult *result) {
            SGLog(@"genie: %lu lines", (unsigned long)result.karaokeLines.count);
            done(result);
            });
        });
        });
    });
};
