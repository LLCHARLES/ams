// Animated album covers, artist logos and songs by ISRC from Apple Music's catalog. The catalog takes the developer
// token Apple Music's web player carries, so the token is read out of the web player's script and
// kept until it is about to expire. Answers are kept for the launch, and an album's for a week on disk.
#import "Core/SGCore.h"
#import "Core/SGDataRoot.h"
#import "AnimatedArtwork.h"
#import "SGMotionTicket.h"
#import "SGMotionCatalog.h"
#import "Shared/Lyrics/Lyrics.h"
#import "Shared/SpotifyMetadata/SGSpotifyAlbumIdentity.h"
#import "Shared/SpotifyMetadata/SGSpotifyMetadata.h"
#import "Shared/Haptics/Haptics.h"

static NSString *const kTokenKey = @"spotifyglass.motion.token";
static NSString *const kBrowse = @"https://music.apple.com/us/browse";
static NSString *const kSearch = @"https://amp-api.music.apple.com/v1/catalog/us/search";
static NSString *const kSafari = @"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.5 Safari/605.1.15";
// A token this close to its expiry is read again rather than used.
static const NSTimeInterval kTokenMargin = 3600;

// Main queue only. NSNull is kept for an album or artist that has nothing.
static NSMutableDictionary<NSString *, id> *sg_kept;
static NSMutableArray<NSString *> *sg_keptOrder;
static NSUInteger sg_logoBytes;
static const NSUInteger kKeptEntries = 200, kLogoBytes = 16 * 1024 * 1024, kAlbumAnswers = 200;
static NSMutableDictionary<NSString *, NSMutableArray *> *sg_waiting;
static NSMutableArray<void (^)(NSString *)> *sg_tokenWaiting;
static NSMutableSet<NSString *> *sg_catalogDiagnostics;

// Only metadata decisions call this, never a layout or playback tick.
static void catalogDiagnostic(NSString *identity, NSString *event, NSString *detail) {
    if (SGLogFirst(&sg_catalogDiagnostics, [NSString stringWithFormat:@"%@\n%@", identity, event]))
        SGLog(@"catalog %@: %@", identity, detail);
}

// An album's answer, its clip's address or that it has none, kept on disk so that an album opened before starts at
// once after a relaunch, without the token and the search. Older answers are asked again.
static const NSTimeInterval kAlbumAnswerLife = 7 * 24 * 3600;

static NSURL *albumAnswersFile(void) {
#ifdef SG_MOTION_TEST_STORE
    extern NSURL *SGMotionTestAlbumAnswersFile(void);
    return SGMotionTestAlbumAnswersFile();
#else
    return [SGDataRoot(NSCachesDirectory) URLByAppendingPathComponent:@"Motion/album answers.plist"];
#endif
}

// Key to {url: the address, "" for none; at: when it was asked}.
static NSMutableDictionary<NSString *, NSDictionary *> *sg_albumAnswers;
// Bumped by each clear (main). A lookup that began in an earlier generation is delivered to its own callers but kept nowhere.
static NSUInteger sg_generation;
// Set by a clear that ran before the first lookup: the file on disk is gone, so the launch must not read it.
static BOOL sg_answersCleared;

// Every read and write of the answers file runs here, in order.
static dispatch_queue_t albumQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        queue = dispatch_queue_create("spotifyglass.motion.albumAnswers", DISPATCH_QUEUE_SERIAL);
    });
    return queue;
}

static NSUInteger logoBytes(id value) {
    if (![value isKindOfClass:UIImage.class]) return 0;
    CGImageRef image = [value CGImage];
    return image ? CGImageGetBytesPerRow(image) * CGImageGetHeight(image) : 0;
}

static void keepValue(NSString *key, id value) {
    id previous = sg_kept[key];
    sg_logoBytes -= logoBytes(previous);
    [sg_kept removeObjectForKey:key];
    [sg_keptOrder removeObject:key];
    NSUInteger bytes = logoBytes(value);
    if (bytes > kLogoBytes) return; // still delivered to the caller, never retained by the catalog
    while (sg_keptOrder.count && (sg_kept.count >= kKeptEntries || bytes > kLogoBytes - sg_logoBytes)) {
        NSString *oldest = sg_keptOrder.firstObject;
        sg_logoBytes -= logoBytes(sg_kept[oldest]);
        [sg_kept removeObjectForKey:oldest];
        [sg_keptOrder removeObjectAtIndex:0];
    }
    sg_kept[key] = value ?: NSNull.null;
    sg_logoBytes += bytes;
    [sg_keptOrder addObject:key];
}

static void pruneAlbumAnswers(void) {
    NSDate *now = NSDate.date;
    for (NSString *key in sg_albumAnswers.allKeys) {
        if ([now timeIntervalSinceDate:sg_albumAnswers[key][@"at"]] > kAlbumAnswerLife)
            [sg_albumAnswers removeObjectForKey:key];
    }
    if (sg_albumAnswers.count <= kAlbumAnswers) return;
    NSArray *oldest = [sg_albumAnswers.allKeys sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        return [sg_albumAnswers[a][@"at"] compare:sg_albumAnswers[b][@"at"]];
    }];
    NSUInteger excess = oldest.count - kAlbumAnswers;
    for (NSUInteger i = 0; i < excess; i++) [sg_albumAnswers removeObjectForKey:oldest[i]];
}

static void keepAlbumAnswer(NSString *key, id value) {
    sg_albumAnswers[key] = [value isKindOfClass:NSArray.class]
        ? @{@"records": value, @"at": NSDate.date}
        : [value isKindOfClass:NSURL.class] ? @{@"url": [value absoluteString], @"at": NSDate.date}
        : @{@"url": @"", @"identified": @([value isEqual:@NO]), @"at": NSDate.date};
    pruneAlbumAnswers();
    // Catalog answers arrive on main. Keep its dictionary there, but serialize
    // immutable snapshots off main in order so an older write cannot win.
    NSDictionary *answers = [sg_albumAnswers copy];
    NSURL *file = albumAnswersFile();
    dispatch_async(albumQueue(), ^{
        [NSFileManager.defaultManager createDirectoryAtURL:file.URLByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
        [answers writeToURL:file atomically:YES];
    });
}

static void setUp(void) {
    if (sg_kept) return;
    NSURL *file = albumAnswersFile();
    if (!file) return;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        sg_kept = [NSMutableDictionary dictionary];
        sg_keptOrder = [NSMutableArray array];
        sg_albumAnswers = [NSMutableDictionary dictionary];
        NSDictionary *stored = sg_answersCleared ? nil : [NSDictionary dictionaryWithContentsOfURL:file];
        for (NSString *key in stored) {
            NSDictionary *answer = stored[key];
            NSDate *at = [answer isKindOfClass:NSDictionary.class] ? answer[@"at"] : nil;
            if (![at isKindOfClass:NSDate.class] || -at.timeIntervalSinceNow > kAlbumAnswerLife) continue;
            if (![answer[@"url"] isKindOfClass:NSString.class] && ![answer[@"records"] isKindOfClass:NSArray.class]) continue;
            // Older empty answers didn't distinguish a still release from no matching release.
            if ([answer[@"url"] isEqual:@""] && !answer[@"identified"]) continue;
            sg_albumAnswers[key] = answer;
        }
        pruneAlbumAnswers();
        for (NSString *key in sg_albumAnswers) {
            NSString *url = sg_albumAnswers[key][@"url"];
            keepValue(key, sg_albumAnswers[key][@"records"] ?: (url.length ? [NSURL URLWithString:url] :
                [sg_albumAnswers[key][@"identified"] boolValue] ? (id)@NO : nil));
        }
        sg_waiting = [NSMutableDictionary dictionary];
        sg_tokenWaiting = [NSMutableArray array];
    });
}

static id dig(id value, NSString *path) {
    for (NSString *key in [path componentsSeparatedByString:@"/"]) {
        if (![value isKindOfClass:NSDictionary.class]) return nil;
        value = value[key];
    }
    return value;
}

static NSString *textOf(NSData *data) {
    return data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
}

#pragma mark - names

static NSString *plain(NSString *name) {
    NSString *key = [name stringByFoldingWithOptions:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch | NSWidthInsensitiveSearch
                                              locale:nil].lowercaseString;
    // Punctuation goes without leaving a gap, so "n’" and "n'" both become "n".
    key = [key stringByReplacingOccurrencesOfString:@"[^\\p{L}\\p{N}\\s]" withString:@"" options:NSRegularExpressionSearch range:NSMakeRange(0, key.length)];
    key = [key stringByReplacingOccurrencesOfString:@"\\s+" withString:@" " options:NSRegularExpressionSearch range:NSMakeRange(0, key.length)];
    return [key stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
}

NSString *SGMotionNameKey(NSString *name) {
    if (![name isKindOfClass:NSString.class]) return @"";
    // Apple Music adds " - Single" and " - EP" to names Spotify gives bare.
    NSRange dash = [name rangeOfString:@" - "];
    if (dash.location != NSNotFound) name = [name substringToIndex:dash.location];
    NSString *edition = @"\\([^)]*\\)|\\[[^\\]]*\\]";
    NSString *bare = plain([name stringByReplacingOccurrencesOfString:edition withString:@" " options:NSRegularExpressionSearch
                                                                range:NSMakeRange(0, name.length)]);
    // A name that is all brackets keeps them, so it still has a key.
    return bare.length ? bare : plain(name);
}

// The name as it is searched for: without what Spotify adds for an edition ("(Deluxe)", "[Remastered]",
// " - 2011 Remaster"), so edition lookups share candidate records. Selection still checks the full title.
NSString *SGMotionSearchName(NSString *name) {
    if (![name isKindOfClass:NSString.class]) return @"";
    NSString *bare = name;
    NSRange dash = [bare rangeOfString:@" - "];
    if (dash.location != NSNotFound) bare = [bare substringToIndex:dash.location];
    bare = [bare stringByReplacingOccurrencesOfString:@"\\([^)]*\\)|\\[[^\\]]*\\]" withString:@" " options:NSRegularExpressionSearch
                                               range:NSMakeRange(0, bare.length)];
    bare = [bare stringByReplacingOccurrencesOfString:@"\\s+" withString:@" " options:NSRegularExpressionSearch range:NSMakeRange(0, bare.length)];
    bare = [bare stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    return bare.length ? bare : name;
}

// Text, never a web view or HTML attributed-string importer. Strip markup before
// decoding entities, so an escaped "<..." remains literal text. Block boundaries
// survive, including notes with several paragraphs.
NSString *SGMotionEditorialText(id html) {
    if (![html isKindOfClass:NSString.class] || [html length] > 65536) return nil;
    NSString *text = html;
    for (NSArray *replacement in @[
        @[@"(?is)<(script|style)\\b[^>]*>.*?</\\1\\s*>", @""],
        @[@"(?is)<!--.*?-->", @""],
        @[@"(?i)</?(p|div|br|li|h[1-6])\\b[^>]*>", @"\n"],
        @[@"(?s)<[^>]*>", @""],
    ]) {
        text = [text stringByReplacingOccurrencesOfString:replacement[0] withString:replacement[1]
                                                 options:NSRegularExpressionSearch range:NSMakeRange(0, text.length)];
    }
    NSDictionary *entities = @{@"amp": @"&", @"lt": @"<", @"gt": @">", @"quot": @"\"", @"apos": @"'",
        @"nbsp": @" ", @"ndash": @"–", @"mdash": @"—", @"hellip": @"…", @"lsquo": @"‘", @"rsquo": @"’",
        @"ldquo": @"“", @"rdquo": @"”"};
    NSMutableString *decoded = [text mutableCopy];
    NSRegularExpression *entity = [NSRegularExpression regularExpressionWithPattern:@"&(#x[0-9a-fA-F]+|#[0-9]+|[A-Za-z]+);"
                                                                           options:0 error:nil];
    for (NSTextCheckingResult *match in [[entity matchesInString:text options:0 range:NSMakeRange(0, text.length)] reverseObjectEnumerator]) {
        NSString *name = [text substringWithRange:[match rangeAtIndex:1]];
        NSString *value = entities[name];
        if ([name hasPrefix:@"#"]) {
            BOOL hex = [name hasPrefix:@"#x"];
            unsigned long code = strtoul([[name substringFromIndex:hex ? 2 : 1] UTF8String], NULL, hex ? 16 : 10);
            if (code > 0 && code <= 0x10ffff && !(code >= 0xd800 && code <= 0xdfff)) {
                UTF32Char scalar = (UTF32Char)code;
                value = [[NSString alloc] initWithBytes:&scalar length:sizeof(scalar) encoding:NSUTF32LittleEndianStringEncoding];
            }
        }
        if (value) [decoded replaceCharactersInRange:match.range withString:value];
    }
    NSMutableArray *paragraphs = [NSMutableArray array];
    for (NSString *line in [decoded componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
        NSString *clean = [line stringByReplacingOccurrencesOfString:@"\\s+" withString:@" " options:NSRegularExpressionSearch range:NSMakeRange(0, line.length)];
        clean = [clean stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if (clean.length) [paragraphs addObject:clean];
    }
    return paragraphs.count ? [paragraphs componentsJoinedByString:@"\n\n"] : nil;
}

static NSNumber *albumExplicit(id rating) {
    if ([rating isEqual:@"explicit"]) return @YES;
    if (!rating || rating == NSNull.null || [rating isEqual:@"clean"]) return @NO;
    return nil;
}

NSDictionary *SGMotionAlbumNotesIn(NSArray *records, NSString *artist, NSString *album, NSDictionary *edition) {
    NSString *artistKey = plain(artist), *editionKey = plain(album);
    NSString *identity = [NSString stringWithFormat:@"notes %@ by %@", album, artist];
    NSString *missing = !artistKey.length || !editionKey.length ? @"missing identity" : nil;
    for (NSString *key in @[@"trackCount", @"releaseYear"])
        if (![edition[key] isKindOfClass:NSNumber.class] || [edition[key] integerValue] <= 0)
            missing = [@"missing Spotify " stringByAppendingString:key];
    if (![edition[@"explicit"] isKindOfClass:NSNumber.class]) missing = @"unknown Spotify rating";
    if (missing) {
        catalogDiagnostic(identity, missing, [@"refuse: " stringByAppendingString:missing]);
        return nil;
    }
    catalogDiagnostic(identity, records.count ? @"records-present" : @"records-absent",
        [NSString stringWithFormat:@"records=%lu (%@)", (unsigned long)records.count, records ? @"catalog answered" : @"unavailable/error"]);
    NSDictionary *match = nil;
    NSString *reason = @"no exact artist/title edition";
    for (id record in records) {
        id attributes = dig(record, @"attributes");
        id name = dig(attributes, @"name"), creator = dig(attributes, @"artistName");
        if (![name isKindOfClass:NSString.class] || ![creator isKindOfClass:NSString.class]) continue;
        // Do not use SGMotionNameKey here: it deliberately discards edition qualifiers.
        if (![plain(name) isEqual:editionKey] || ![plain(creator) isEqual:artistKey]) continue;
        id count = dig(attributes, @"trackCount"), date = dig(attributes, @"releaseDate"), rating = dig(attributes, @"contentRating");
        catalogDiagnostic(identity, [NSString stringWithFormat:@"record-%@", dig(record, @"id")],
            [NSString stringWithFormat:@"Apple id=%@ trackCount=%@ releaseDate=%@ contentRating=%@ editorialNotes.short=%d standard=%d",
                dig(record, @"id"), count, date, rating ?: @"absent (clean)",
                dig(attributes, @"editorialNotes/short") != nil, dig(attributes, @"editorialNotes/standard") != nil]);
        NSNumber *explicit = albumExplicit(rating), *year = nil;
        if ([date isKindOfClass:NSString.class] && [date rangeOfString:@"^[0-9]{4}(-[0-9]{2}(-[0-9]{2})?)?$"
            options:NSRegularExpressionSearch].location != NSNotFound) year = @([[date substringToIndex:4] integerValue]);
        if (![count isKindOfClass:NSNumber.class] || ![edition[@"trackCount"] isEqualToNumber:count] ||
            !year || ![edition[@"releaseYear"] isEqualToNumber:year]) {
            reason = @"trackCount/releaseYear missing or mismatch";
            continue;
        }
        if (!explicit || ![edition[@"explicit"] isEqualToNumber:explicit]) {
            reason = @"contentRating missing/unsupported or mismatch";
            continue;
        }
        if (match) {
            catalogDiagnostic(identity, @"ambiguous", @"refuse: multiple edition matches");
            return nil;
        }
        match = attributes;
    }
    NSString *shortText = SGMotionEditorialText(dig(match, @"editorialNotes/short"));
    NSString *standard = SGMotionEditorialText(dig(match, @"editorialNotes/standard"));
    BOOL accepted = shortText.length && standard.length;
    if (match && !accepted) reason = @"short/standard editorial text missing or empty after cleanup";
    catalogDiagnostic(identity, accepted ? @"accepted" : reason,
        accepted ? @"accept: exact edition and editorial text" : [@"refuse: " stringByAppendingString:reason]);
    return accepted ? @{@"short": shortText, @"standard": standard} : nil;
}

static NSString *artistFold(NSString *text) {
    if (![text isKindOfClass:NSString.class]) return @"";
    NSString *folded = [text stringByFoldingWithOptions:NSCaseInsensitiveSearch | NSWidthInsensitiveSearch locale:nil].lowercaseString;
    return [folded stringByReplacingOccurrencesOfString:@"\\p{Cf}" withString:@"" options:NSRegularExpressionSearch range:NSMakeRange(0, folded.length)];
}

static NSString *artistNameKey(NSString *name) { return plain(artistFold(name)); }

static NSString *artistReleaseKey(NSString *title) {
    NSString *key = artistFold(title);
    // Bare "with" is part of a title ("Stay with Me"), never proof of a credit.
    NSString *suffix = @"(?:\\s+-\\s+(?:single|ep)|\\s*\\(deluxe(?: edition)?\\)|\\s*\\((?:with|feat\\.|ft\\.)\\s+[^()]+\\)|\\s*\\[(?:with|feat\\.|ft\\.)\\s+[^\\[\\]]+\\]|\\s+(?:feat\\.|ft\\.)\\s+.+)\\s*$";
    while (YES) {
        NSRange range = [key rangeOfString:suffix options:NSRegularExpressionSearch];
        if (range.location == NSNotFound) break;
        key = [key substringToIndex:range.location];
    }
    return plain(key);
}

NSDictionary *SGMotionArtistMatch(NSArray *records, NSString *artist, NSArray<NSString *> *titles) {
    NSMutableSet *evidence = [NSMutableSet set];
    for (NSString *title in titles) {
        NSString *key = artistReleaseKey(title);
        if (key.length) [evidence addObject:key];
    }
    if (evidence.count < 2) return nil;
    NSDictionary *match = nil;
    for (id record in records) {
        id name = dig(record, @"attributes/name");
        if (![name isKindOfClass:NSString.class] || ![artistNameKey(name) isEqual:artistNameKey(artist)]) continue;
        id albums = dig(record, @"relationships/albums/data");
        if (![albums isKindOfClass:NSArray.class]) continue;
        NSMutableSet *overlap = [NSMutableSet set];
        for (id album in albums) {
            NSString *key = artistReleaseKey(dig(album, @"attributes/name"));
            if ([evidence containsObject:key]) [overlap addObject:key];
        }
        NSMutableArray *sample = [NSMutableArray array];
        for (id album in albums) {
            id title = dig(album, @"attributes/name");
            if ([title isKindOfClass:NSString.class] && sample.count < 4) [sample addObject:title];
        }
        SGLog(@"catalog artist %@: candidate id=%@ name=%@ releases=%lu overlap=%lu first=%@",
            artist, dig(record, @"id"), name, (unsigned long)[albums count], (unsigned long)overlap.count,
            [sample componentsJoinedByString:@" | "]);
        if (overlap.count < 2) continue;
        if (match) return nil;
        match = record;
    }
    return match;
}

#pragma mark - playlists

static NSArray<NSString *> *linesOf(NSString *playlist) {
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    for (NSString *line in [playlist componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
        NSString *trimmed = [line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if (trimmed.length) [lines addObject:trimmed];
    }
    return lines;
}

static NSString *firstGroup(NSString *pattern, NSString *text) {
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil];
    NSTextCheckingResult *match = [regex firstMatchInString:text options:0 range:NSMakeRange(0, text.length)];
    return match ? [text substringWithRange:[match rangeAtIndex:1]] : nil;
}

NSString *SGMotionStreamIn(NSString *master, CGFloat pixels) {
    if (![master isKindOfClass:NSString.class]) return nil;
    NSArray<NSString *> *lines = linesOf(master);
    NSString *best = nil;
    NSInteger bestWidth = 0;
    BOOL bestHEVC = NO;
    for (NSUInteger i = 0; i + 1 < lines.count; i++) {
        if (![lines[i] hasPrefix:@"#EXT-X-STREAM-INF:"] || [lines[i + 1] hasPrefix:@"#"]) continue;
        NSInteger width = [firstGroup(@"RESOLUTION=(\\d+)x\\d+", lines[i]) integerValue];
        if (width <= 0) continue;
        NSString *codecs = firstGroup(@"CODECS=\"([^\"]*)\"", lines[i]);
        BOOL hevc = [codecs hasPrefix:@"hvc1"] || [codecs hasPrefix:@"hev1"];
        BOOL wide = width >= pixels, bestWide = bestWidth >= pixels;
        BOOL better = !best || (wide != bestWide ? wide
                              : width != bestWidth ? (wide ? width < bestWidth : width > bestWidth)
                              : hevc && !bestHEVC);
        if (!better) continue;
        best = lines[i + 1];
        bestWidth = width;
        bestHEVC = hevc;
    }
    return best;
}

NSString *SGMotionWholeFileIn(NSString *media) {
    if (![media isKindOfClass:NSString.class]) return nil;
    NSMutableSet<NSString *> *uris = [NSMutableSet set];
    for (NSString *line in linesOf(media)) {
        NSString *uri = [line hasPrefix:@"#"] ? firstGroup(@"URI=\"([^\"]*)\"", line) : line;
        if (uri) [uris addObject:uri];
    }
    return uris.count == 1 ? uris.anyObject : nil;
}

#pragma mark - requests

static NSMutableURLRequest *requestFor(NSURL *url) {
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.allowsConstrainedNetworkAccess = SGFlag(SGKeyMotionLowData, NO);
    if ([url.host isEqualToString:@"music.apple.com"]) [request setValue:kSafari forHTTPHeaderField:@"User-Agent"];
    return request;
}

// `parse` runs off the main queue on a 200 answer. `done` gets what it made and the status, 0 for no
// answer at all, on the main queue.
static void fetch(NSURLRequest *request, id (^parse)(NSData *data), void (^done)(id result, NSInteger status)) {
    if (!request.URL) {
        dispatch_async(dispatch_get_main_queue(), ^{ done(nil, 0); });
        return;
    }
    [[NSURLSession.sharedSession dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSInteger status = !error && [response isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)response).statusCode : 0;
        id result = status == 200 && data ? parse(data) : nil;
        if (status != 200) SGLog(@"motion: %@%@ failed (%ld, %@)", request.URL.host, request.URL.path, (long)status, error.localizedDescription);
        dispatch_async(dispatch_get_main_queue(), ^{ done(result, status); });
    }] resume];
}

#pragma mark - token

static NSDictionary *claimsOf(NSString *jwt) {
    NSArray<NSString *> *parts = [jwt isKindOfClass:NSString.class] ? [jwt componentsSeparatedByString:@"."] : nil;
    if (parts.count != 3) return nil;
    NSMutableString *payload = [[[parts[1] stringByReplacingOccurrencesOfString:@"-" withString:@"+"]
                                 stringByReplacingOccurrencesOfString:@"_" withString:@"/"] mutableCopy];
    while (payload.length % 4) [payload appendString:@"="];
    NSData *data = [[NSData alloc] initWithBase64EncodedString:payload options:0];
    id claims = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    return [claims isKindOfClass:NSDictionary.class] ? claims : nil;
}

static BOOL usable(NSString *jwt) {
    id expiry = claimsOf(jwt)[@"exp"];
    return [expiry isKindOfClass:NSNumber.class] && [expiry doubleValue] - NSDate.date.timeIntervalSince1970 > kTokenMargin;
}

// The script holds several JWTs; the web player's own is the one the catalog takes.
static NSString *tokenIn(NSData *script) {
    NSString *text = textOf(script);
    if (!text) return nil;
    NSRegularExpression *jwt = [NSRegularExpression regularExpressionWithPattern:@"eyJ[A-Za-z0-9_-]+\\.eyJ[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+" options:0 error:nil];
    for (NSTextCheckingResult *match in [jwt matchesInString:text options:0 range:NSMakeRange(0, text.length)]) {
        NSString *candidate = [text substringWithRange:match.range];
        if ([claimsOf(candidate)[@"iss"] isEqual:@"AMPWebPlay"]) return candidate;
    }
    return nil;
}

// The script's name carries a hash that changes with every web player release, so the page names it.
static void readToken(void (^done)(NSString *token)) {
    NSURL *browse = [NSURL URLWithString:kBrowse];
    fetch(requestFor(browse), ^id(NSData *data) {
        NSString *html = textOf(data);
        if (!html) return nil;
        NSRange path = [html rangeOfString:@"/assets/index[^\"'\\s>]*\\.js" options:NSRegularExpressionSearch];
        return path.location == NSNotFound ? nil : [NSURL URLWithString:[html substringWithRange:path] relativeToURL:browse].absoluteURL;
    }, ^(NSURL *script, NSInteger status) {
        if (!script) {
            SGLog(@"motion: no web player script on the browse page (%ld)", (long)status);
            done(nil);
            return;
        }
        fetch(requestFor(script), ^id(NSData *data) { return tokenIn(data); }, ^(NSString *token, NSInteger scriptStatus) {
            SGLog(@"motion: token %@ in %@", token ? @"found" : @"not found", script.lastPathComponent);
            done(token);
        });
    });
}

static void withToken(void (^use)(NSString *token)) {
    NSString *stored = [NSUserDefaults.standardUserDefaults stringForKey:kTokenKey];
    if (usable(stored)) {
        use(stored);
        return;
    }
    [sg_tokenWaiting addObject:[use copy]];
    if (sg_tokenWaiting.count > 1) return;
    readToken(^(NSString *token) {
        if (token) [NSUserDefaults.standardUserDefaults setObject:token forKey:kTokenKey];
        NSArray<void (^)(NSString *)> *waiting = [sg_tokenWaiting copy];
        [sg_tokenWaiting removeAllObjects];
        for (void (^waiter)(NSString *) in waiting) waiter(token);
    });
}

// Another request may have read a new token since this one was sent; that one stays.
static void forgetToken(NSString *token) {
    if ([[NSUserDefaults.standardUserDefaults stringForKey:kTokenKey] isEqualToString:token])
        [NSUserDefaults.standardUserDefaults removeObjectForKey:kTokenKey];
}

#pragma mark - catalog

// After a 403 or a 429 the catalog is left alone this long: each lookup meanwhile finds nothing at once and is
// not kept, so it is asked again once the pause is over. Without it every skip sent a search to a catalog that
// had said to stop.
static const NSTimeInterval kCatalogPause = 600;
static NSDate *sg_catalogPausedUntil;

static NSString *escaped(NSString *value) {
    NSCharacterSet *unreserved = [NSCharacterSet characterSetWithCharactersInString:
        @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"];
    return [value stringByAddingPercentEncodingWithAllowedCharacters:unreserved] ?: @"";
}

// Keep the catalog envelope so relationship consumers can follow `next`.
// Status is HTTP or zero on transport/unavailability failure. A refused token is read again once.
static void askCatalogJSON(NSString *address, BOOL renew, void (^done)(NSDictionary *json, NSInteger status)) {
    if (sg_catalogPausedUntil.timeIntervalSinceNow > 0) {
        dispatch_async(dispatch_get_main_queue(), ^{ done(nil, 0); });
        return;
    }
    withToken(^(NSString *token) {
        if (!token) {
            done(nil, 0);
            return;
        }
        NSMutableURLRequest *request = requestFor([NSURL URLWithString:address]);
        [request setValue:[@"Bearer " stringByAppendingString:token] forHTTPHeaderField:@"Authorization"];
        // The catalog refuses the web player's token without the web player's origin.
        [request setValue:@"https://music.apple.com" forHTTPHeaderField:@"Origin"];
        fetch(request, ^id(NSData *data) {
            id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            return [json isKindOfClass:NSDictionary.class] ? json : nil;
        }, ^(NSDictionary *found, NSInteger status) {
            if (status == 401 && renew) {
                SGLog(@"motion: token refused, reading it again");
                forgetToken(token);
                askCatalogJSON(address, NO, done);
                return;
            }
            if (status == 403 || status == 429) {
                sg_catalogPausedUntil = [NSDate dateWithTimeIntervalSinceNow:kCatalogPause];
                SGLog(@"motion: the catalog answered %ld, not asked for %.0f minutes", (long)status, kCatalogPause / 60);
            }
            done(found, status);
        });
    });
}

static void askCatalog(NSString *address, NSString *path, BOOL renew, void (^done)(NSArray *, BOOL)) {
    askCatalogJSON(address, renew, ^(NSDictionary *json, NSInteger status) {
        BOOL answered = status == 200;
        id found = dig(json, path);
        done(answered ? ([found isKindOfClass:NSArray.class] ? found : @[]) : nil, answered);
    });
}

// `found` is the search's results of that type.
static void search(NSString *type, NSString *term, NSString *extend, BOOL renew, void (^done)(NSArray *found, BOOL answered)) {
    NSString *address = [NSString stringWithFormat:@"%@?term=%@&types=%@&limit=10&extend=%@", kSearch, escaped(term), type, extend];
    askCatalog(address, [NSString stringWithFormat:@"results/%@/data", type], renew, done);
}

// Runs `look` once per key and launch. `look` calls `answer` exactly once; `keep` is NO for a failure
// worth asking again.
static void lookUp(NSString *key, void (^done)(id value), void (^look)(void (^answer)(id value, BOOL keep))) {
    setUp();
    if (!sg_kept) { done(nil); return; }
    id kept = sg_kept[key];
    if (kept) {
        done(kept == NSNull.null ? nil : kept);
        return;
    }
    NSMutableArray *waiting = sg_waiting[key];
    if (waiting) {
        [waiting addObject:[done copy]];
        return;
    }
    NSMutableArray *callers = [NSMutableArray arrayWithObject:[done copy]];
    sg_waiting[key] = callers;
    NSUInteger generation = sg_generation;
    look(^(id value, BOOL keep) {
        // After a clear this answer is old: it keeps nothing and its callers are not in sg_waiting any more.
        if (generation == sg_generation) {
            if (keep) keepValue(key, value);
            if (keep && (([key hasPrefix:@"album\n"] && (!value || [value isEqual:@NO] || [value isKindOfClass:NSURL.class]))
                      || ([key hasPrefix:@"album-records\n"] && [value isKindOfClass:NSArray.class]))) keepAlbumAnswer(key, value);
            [sg_waiting removeObjectForKey:key];
        }
        for (void (^caller)(id) in [callers copy]) caller(value);
    });
}

#pragma mark - album covers

// Both consumers join this lookup, even when notes are requested before motion
// or motion is disabled. The complete search result preserves edition ambiguity.
static NSString *albumRecordsKey(NSString *artist, NSString *album) {
    return [NSString stringWithFormat:@"album-records\n%@\n%@", SGMotionNameKey(artist), SGMotionNameKey(album)];
}

static void albumRecords(NSString *artist, NSString *album, void (^done)(NSArray *records)) {
    NSString *key = albumRecordsKey(artist, album);
    setUp();
    catalogDiagnostic([NSString stringWithFormat:@"notes %@ by %@", album, artist], @"lookup",
        [NSString stringWithFormat:@"shared record lookup=%@", sg_kept[key] ? @"cached" : sg_waiting[key] ? @"in flight" : @"absent; search"]);
    lookUp(key, done, ^(void (^answer)(id, BOOL)) {
        search(@"albums", [NSString stringWithFormat:@"%@ %@", artist, SGMotionSearchName(album)],
               @"editorialVideo,editorialNotes", YES, ^(NSArray *found, BOOL answered) { answer(found, answered); });
    });
}

void SGMotionAlbumNotes(NSString *artist, NSString *album, NSDictionary *edition, void (^done)(NSDictionary *notes)) {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ SGMotionAlbumNotes(artist, album, edition, done); });
        return;
    }
    if (!SGMotionNameKey(artist).length || !SGMotionNameKey(album).length) { done(nil); return; }
    albumRecords(artist, album, ^(NSArray *records) { done(SGMotionAlbumNotesIn(records, artist, album, edition)); });
}

static NSString *videoOf(NSDictionary *editorialVideo) {
    NSArray<NSString *> *names = @[@"motionTallVideo3x4", @"motionDetailTall", @"motionSquareVideo1x1", @"motionDetailSquare"];
    for (NSString *name in names) {
        id video = dig(editorialVideo, [name stringByAppendingString:@"/video"]);
        if ([video isKindOfClass:NSString.class] && [video length]) return video;
    }
    return nil;
}

// The master playlist names a stream per size and codec; the chosen stream's playlist names one file.
static void wholeFileOf(NSURL *master, CGFloat pixels, void (^answer)(id file, BOOL keep)) {
    fetch(requestFor(master), ^id(NSData *data) {
        NSString *uri = SGMotionStreamIn(textOf(data), pixels);
        return uri ? [NSURL URLWithString:uri relativeToURL:master].absoluteURL : nil;
    }, ^(NSURL *stream, NSInteger status) {
        if (!stream) {
            answer(nil, status == 200);
            return;
        }
        fetch(requestFor(stream), ^id(NSData *data) {
            NSString *uri = SGMotionWholeFileIn(textOf(data));
            return uri ? [NSURL URLWithString:uri relativeToURL:stream].absoluteURL : nil;
        }, ^(NSURL *file, NSInteger streamStatus) {
            answer(file, streamStatus == 200);
        });
    });
}

void SGMotionAlbumCover(NSString *artist, NSString *album, CGFloat pixels, void (^done)(NSURL *file)) {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ SGMotionAlbumCover(artist, album, pixels, done); });
        return;
    }
    SGMotionRequestAlbumCover(artist, album, pixels, done);
}

SGMotionTicket *SGMotionRequestAlbumCover(NSString *artist, NSString *album, CGFloat pixels, void (^done)(NSURL *file)) {
    return SGMotionRequestSongCover(artist, album, nil, nil, nil, pixels, done);
}

// Keep edition words, punctuation-only names and word boundaries; search keys discard all three.
static NSString *coverKey(id name) {
    if (![name isKindOfClass:NSString.class]) return @"";
    NSString *text = [name lowercaseString];
    return [[text stringByReplacingOccurrencesOfString:@"\\s+" withString:@" " options:NSRegularExpressionSearch
        range:NSMakeRange(0, text.length)] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
}

// A release's name as both catalogs agree on it: Apple Music names an EP "X - EP" and a single "X - Single"
// where Spotify names either "X". These are the only release-type words Apple adds to a name.
static NSString *releaseKey(id name) {
    NSString *key = coverKey(name);
    for (NSString *suffix in @[@" - ep", @" - single"])
        if ([key hasSuffix:suffix]) return [key substringToIndex:key.length - suffix.length];
    return key;
}

// A name's words in order, every run of punctuation one gap: Spotify's "Moana (Original Motion Picture
// Soundtrack/Deluxe Edition)" and Apple Music's "Moana (Original Motion Picture Soundtrack) [Deluxe Edition]" are the
// same words, set apart by a slash on one side and brackets on the other.
static NSString *wordsKey(NSString *name) {
    if (![name isKindOfClass:NSString.class]) return @"";
    NSString *key = [name stringByFoldingWithOptions:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch | NSWidthInsensitiveSearch
                                              locale:nil].lowercaseString;
    // An apostrophe joins its word ("n'" and "n’" both "n"), every other mark parts words.
    key = [key stringByReplacingOccurrencesOfString:@"['’]" withString:@"" options:NSRegularExpressionSearch range:NSMakeRange(0, key.length)];
    key = [key stringByReplacingOccurrencesOfString:@"[^\\p{L}\\p{N}]+" withString:@" " options:NSRegularExpressionSearch range:NSMakeRange(0, key.length)];
    return [key stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
}

// `album` is Spotify's whole name: one that already reads "X - Single" stays apart from Apple's album "X". The same
// words with other punctuation are the same release; a " - Single" or " - EP" still has to be there to count.
static BOOL sameRelease(id record, NSString *album) {
    NSString *name = coverKey(dig(record, @"attributes/name"));
    if ([name isEqual:album] || [releaseKey(name) isEqual:album]) return YES;
    NSString *words = wordsKey(album);
    return words.length && ([wordsKey(name) isEqual:words] || [wordsKey(releaseKey(name)) isEqual:words]);
}

// An Apple single that Spotify names without " - Single". It is taken only when no album or EP of that name
// qualifies: a same-named single beside an album is that album's lead single, not the album.
static BOOL namedSingle(id record) {
    return [dig(record, @"attributes/isSingle") isEqual:@YES] && [coverKey(dig(record, @"attributes/name")) hasSuffix:@" - single"];
}

static NSString *joinedCredit(NSString *key) {
    return [key stringByReplacingOccurrencesOfString:@" & " withString:@", "];
}

// Only the feature explicitly named in the song title can be added to or omitted from the credit.
static NSArray<NSString *> *featureAlternates(NSString *credit, NSString *song) {
    if (![song hasSuffix:@")"]) return @[];
    NSRange mark = [song rangeOfString:@"(feat. " options:NSBackwardsSearch];
    if (mark.location == NSNotFound || NSMaxRange(mark) >= song.length - 1) return @[];
    NSString *guest = [song substringWithRange:NSMakeRange(NSMaxRange(mark), song.length - 1 - NSMaxRange(mark))];
    NSString *tail = [@", " stringByAppendingString:guest];
    NSString *with = [credit stringByAppendingString:tail];
    return [credit hasSuffix:tail] ? @[with, [credit substringToIndex:credit.length - tail.length]] : @[with];
}

static BOOL containsSong(id record, NSString *song, NSString *artist) {
    id tracks = dig(record, @"relationships/tracks/data");
    if (![tracks isKindOfClass:NSArray.class]) return NO;
    NSString *title = SGLyricsSimplifiedTitle(song);
    for (id track in tracks) {
        NSString *appleTitle = coverKey(dig(track, @"attributes/name"));
        if (!title.length || ![SGLyricsSimplifiedTitle(appleTitle) isEqual:title]) continue;
        NSString *a = joinedCredit(artist), *b = joinedCredit(coverKey(dig(track, @"attributes/artistName")));
        if (b.length && ([a isEqual:b] || [featureAlternates(a, song) containsObject:b] ||
                         [featureAlternates(b, appleTitle) containsObject:a])) return YES;
    }
    return NO;
}

// `withSingles` is the last resort, once neither the album nor the song found a release in a final result.
static NSString *coverVideo(NSArray *records, NSString *album, NSString *artist, NSString *song, BOOL withSingles, NSUInteger *matches) {
    NSString *video = nil, *singleVideo = nil;
    NSUInteger singles = 0;
    *matches = 0;
    for (id record in records) {
        if (!sameRelease(record, album)) continue;
        id single = dig(record, @"attributes/isSingle");
        BOOL same = song.length ? containsSong(record, song, artist)
                                : [coverKey(dig(record, @"attributes/artistName")) isEqual:artist];
        if (![album hasSuffix:@" - single"] && ([single isEqual:@YES] || (song.length && ![single isEqual:@NO]))) {
            if (withSingles && same && namedSingle(record)) { singles++; singleVideo = videoOf(dig(record, @"attributes/editorialVideo")); }
            continue;
        }
        if (!same) continue;
        // Neither a shared recording nor a shared name makes one moving release the right one.
        if (++*matches > 1) return nil;
        video = video ?: videoOf(dig(record, @"attributes/editorialVideo"));
    }
    // Only a moving single counts: a still one could be a lead single that hides the album's identifier lookup.
    if (!*matches && singles == 1 && singleVideo) { *matches = 1; return singleVideo; }
    return video;
}

// Search by release rather than performer: a contributor's name can push the entire
// soundtrack out of Apple's ten album hits. Share the track list across all its songs.
static const NSUInteger kCoverSearchLimit = 10;
static void songCoverRecords(NSString *term, void (^done)(NSArray *records)) {
    lookUp([@"cover-tracks\n" stringByAppendingString:coverKey(term)], done, ^(void (^answer)(id, BOOL)) {
        NSString *url = [NSString stringWithFormat:@"%@?term=%@&types=albums&limit=%lu&extend=editorialVideo"
            "&include%%5Balbums%%5D=tracks&fields%%5Bsongs%%5D=name,artistName&fields%%5Balbums%%5D=name,artistName,isSingle,editorialVideo,releaseDate", kSearch, escaped(term), (unsigned long)kCoverSearchLimit];
        askCatalog(url, @"results/albums/data", YES, ^(NSArray *records, BOOL answered) { answer(records, answered); });
    });
}

static void masterFile(NSString *video, CGFloat pixels, void (^done)(NSURL *)) {
    lookUp([NSString stringWithFormat:@"master\n%@\n%g", video, pixels], done,
           ^(void (^resolve)(id, BOOL)) { wholeFileOf([NSURL URLWithString:video], pixels, resolve); });
}

// Keep the original digits for Apple's filter (a real leading zero can be significant there).
// Only equality between the two services ignores padding.
static NSString *barcodeKey(id digits) {
    if (![digits isKindOfClass:NSString.class]) return nil;
    NSUInteger start = NSNotFound;
    for (NSUInteger i = 0; i < [digits length]; i++) {
        unichar c = [digits characterAtIndex:i];
        if (c < '0' || c > '9') return nil;
        if (start == NSNotFound && c != '0') start = i;
    }
    return start == NSNotFound ? nil : [digits substringFromIndex:start];
}

static NSString *albumUPC(id json) {
    id ids = dig(json, @"external_id");
    if ([ids isKindOfClass:NSArray.class]) for (id entry in ids) {
        if ([dig(entry, @"type") isEqual:@"upc"] && barcodeKey(dig(entry, @"id"))) return entry[@"id"];
    }
    return nil;
}

static NSString *firstTrackURI(id album) {
    id discs = dig(album, @"disc");
    if (![discs isKindOfClass:NSArray.class]) return nil;
    for (id disc in discs) {
        id tracks = dig(disc, @"track");
        if ([tracks isKindOfClass:NSArray.class] && [tracks count])
            return SGSpotifyTrackURIFromGID(dig([tracks firstObject], @"gid"));
    }
    return nil;
}

typedef void (^CoverAnswer)(id result, BOOL keep);

@interface SGMotionSelection : NSObject
@property(nonatomic, copy) NSString *video;
@property(nonatomic) BOOL uniqueRelease;
@end
@implementation SGMotionSelection
@end

// A complete, nonempty set of identifier matches can agree on the picture without proving the release.
static void selectIdentifierCover(NSArray *records, CoverAnswer answer) {
    NSMutableDictionary<NSString *, NSString *> *byID = [NSMutableDictionary dictionary];
    for (NSDictionary *record in records) {
        NSString *identifier = record[@"id"];
        if (!byID[identifier].length) byID[identifier] = videoOf(dig(record, @"attributes/editorialVideo")) ?: @"";
    }
    BOOL unique = byID.count == 1;
    NSSet<NSString *> *videos = [NSSet setWithArray:byID.allValues];
    NSString *video = videos.anyObject;
    if (videos.count != 1 || !video.length) { answer(unique ? @NO : @(SGMotionIdentifierAmbiguous), YES); return; }
    SGMotionSelection *selection = [SGMotionSelection new];
    selection.video = video;
    selection.uniqueRelease = unique;
    answer(selection, NO); // Only a verified, downloaded clip is kept for the release.
}

static void recordingCover(NSString *track, NSString *album, NSUInteger generation, CoverAnswer answer) {
    if (!SGSpotifyValidURI(track, @"track")) {
        SGLog(@"motion: ISRC not read for %@: no track URI", album);
        answer(nil, NO);
        return;
    }
    SGSpotifyISRCAllowConstrained(track, 1, SGFlag(SGKeyMotionLowData, NO), ^(NSString *isrc, BOOL answered) {
        if (generation != sg_generation || !SGMotionAppleMusicOn()) { answer(nil, NO); return; }
        if (!isrc.length) {
            SGLog(@"motion: no ISRC for %@ (%@)", track, answered ? @"none found" : @"metadata unavailable");
            answer(nil, answered);
            return;
        }
        NSString *url = [NSString stringWithFormat:@"https://amp-api.music.apple.com/v1/catalog/us/songs?filter%%5Bisrc%%5D=%@&include=albums&extend%%5Balbums%%5D=editorialVideo", escaped(isrc)];
        askCatalogJSON(url, YES, ^(NSDictionary *json, NSInteger status) {
            if (generation != sg_generation || !SGMotionAppleMusicOn()) { answer(nil, NO); return; }
            NSString *wanted = SGMotionNameKey(album);
            NSMutableArray *albums = [NSMutableArray array], *singles = [NSMutableArray array];
            NSArray *songs = json[@"data"];
            BOOL complete = status == 200 && [songs isKindOfClass:NSArray.class] && !json[@"next"];
            if (complete) for (id song in songs) {
                if (![dig(song, @"attributes/isrc") isEqual:isrc]) continue;
                id related = dig(song, @"relationships/albums/data");
                if (![related isKindOfClass:NSArray.class] || dig(song, @"relationships/albums/next")) { complete = NO; break; }
                for (id record in related) {
                    NSString *name = dig(record, @"attributes/name");
                    // The edition-stripped key would join "Rich Man - Single" to "Rich Man - The 6th Mini Album":
                    // a single needs the whole name.
                    BOOL single = namedSingle(record) && [releaseKey(name) isEqual:releaseKey(album)];
                    if (!single && ![dig(record, @"attributes/isSingle") isEqual:@NO]) continue;
                    NSString *key = SGMotionNameKey(name);
                    if (!single && (wanted.length && key.length ? ![key isEqual:wanted] : ![coverKey(name) isEqual:coverKey(album)])) continue;
                    NSString *identifier = dig(record, @"id");
                    if (![identifier isKindOfClass:NSString.class] || !identifier.length) { complete = NO; break; }
                    [(single ? singles : albums) addObject:record];
                }
            }
            if (!albums.count) albums = singles;
            SGLog(@"motion: %@ ISRC %@: %lu matching records (%@)", track, isrc, (unsigned long)albums.count,
                  complete ? @"complete" : @"incomplete catalog reply");
            if (!complete || !albums.count) { answer(nil, complete); return; }
            selectIdentifierCover(albums, answer);
        });
    });
}

// Spotify's release year of each album looked up this launch, by its URI (0: the metadata had none), for the title
// search that follows a still edition (inYear).
static NSString *yearKey(NSString *uri) { return [@"album-year\n" stringByAppendingString:uri]; }

static NSNumber *yearIn(id json) {
    id year = dig(json, @"date/year");
    return [year isKindOfClass:NSNumber.class] && [year integerValue] > 0 ? year : nil;
}

static void keepAlbumYear(NSString *uri, NSNumber *year) {
    keepValue(yearKey(uri), year ?: @0);
}

// The album's release year from Spotify's metadata (the one the barcode was read from, else asked for); nil when it
// has none or cannot be read. Main queue.
static void albumYear(NSString *uri, void (^done)(NSNumber *year)) {
    NSUInteger generation = sg_generation;
    NSNumber *known = sg_kept[yearKey(uri)];
    if (known) { done(known.integerValue ? known : nil); return; }
    NSString *path = SGSpotifyAlbumMetadataPath(uri);
    if (!path) { done(nil); return; }
    SGSpotifyMetadataRequestAllowConstrained(path, nil, SGFlag(SGKeyMotionLowData, NO), ^(NSData *data, NSInteger status, NSError *error) {
        id json = status == 200 && !error && data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        NSNumber *year = yearIn(json);
        dispatch_async(dispatch_get_main_queue(), ^{
            if (generation != sg_generation) { done(nil); return; }
            if ([json isKindOfClass:NSDictionary.class]) keepAlbumYear(uri, year);
            done(year);
        });
    });
}

// Apple's releases within kYearSlack of `year`, nil `year` keeping them all. A release with no date is left out: the
// title search after a still edition takes a release by its year or not at all. Two catalogs' dates for one release can
// fall either side of a new year, never ten years apart (the 2016 and 2026 "Moana (Original Motion Picture
// Soundtrack)").
static const NSInteger kYearSlack = 1;
static NSArray *inYear(NSArray *records, NSNumber *year) {
    if (!year || ![records isKindOfClass:NSArray.class]) return records;
    NSMutableArray *kept = [NSMutableArray array];
    for (id record in records) {
        id date = dig(record, @"attributes/releaseDate");
        if (![date isKindOfClass:NSString.class] || [date length] < 4) continue;
        if (labs([[date substringToIndex:4] integerValue] - year.integerValue) <= kYearSlack) [kept addObject:record];
    }
    return kept;
}

static NSString *identifierKey(NSString *uri) { return [@"album\nverified4\n" stringByAppendingString:uri]; }

static NSURL *verifiedClip(NSString *uri) {
    if (!SGSpotifyValidURI(uri, @"album")) return nil;
    NSString *key = identifierKey(uri);
    id kept = sg_kept[key];
    if ([kept isKindOfClass:NSURL.class]) return kept;
    NSString *url = sg_albumAnswers[key][@"url"];
    return url.length ? [NSURL URLWithString:url] : nil;
}

static void identifierCover(NSString *uri, NSString *album, NSString *track, CGFloat pixels, void (^done)(NSURL *, SGMotionIdentifierOutcome)) {
    NSString *path = SGSpotifyAlbumMetadataPath(uri);
    if (!path || !SGMotionAppleMusicOn()) { done(nil, SGMotionIdentifierUnavailable); return; }
    setUp();
    NSUInteger generation = sg_generation;
    // The album lookup is shared even when the player and page will ask about different recordings.
    // A string means no UPC match; it carries the first track for a page without a playing track.
    void (^deliver)(id, BOOL) = ^(id result, BOOL miss) {
        if (generation != sg_generation) done(nil, SGMotionIdentifierUnavailable);
        else if ([result isKindOfClass:SGMotionSelection.class]) {
            SGMotionSelection *selection = result;
            masterFile(selection.video, pixels, ^(NSURL *file) {
                if (generation != sg_generation || !file) done(nil, SGMotionIdentifierUnavailable);
                else done(file, selection.uniqueRelease ? SGMotionIdentifierClip : SGMotionIdentifierAmbiguous);
            });
        }
        else if ([result isEqual:@NO]) done(nil, SGMotionIdentifierStill);
        else if ([result isEqual:@(SGMotionIdentifierAmbiguous)]) done(nil, SGMotionIdentifierAmbiguous);
        else done(nil, miss ? SGMotionIdentifierMiss : SGMotionIdentifierUnavailable);
    };
    lookUp([@"release-upc\n" stringByAppendingString:uri], ^(id result) {
        if (generation != sg_generation || ![result isKindOfClass:NSString.class]) { deliver(result, NO); return; }
        NSString *recording = track ?: result;
        NSString *key = [NSString stringWithFormat:@"album\nrecording\n%@\n%@\n%@", uri, recording, coverKey(album)];
        lookUp(key, ^(id record) { deliver(record, sg_kept[key] == NSNull.null); }, ^(CoverAnswer resolve) {
            recordingCover(recording, album, generation, resolve);
        });
    }, ^(CoverAnswer answer) {
        SGSpotifyMetadataRequestAllowConstrained(path, nil, SGFlag(SGKeyMotionLowData, NO), ^(NSData *data, NSInteger status, NSError *error) {
            id json = status == 200 && !error && data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
            NSString *upc = albumUPC(json);
            NSString *firstTrack = firstTrackURI(json) ?: @"";
            SGLog(@"motion: Spotify album %@ UPC: %@", uri, upc ?: @"none found");
            NSNumber *year = yearIn(json);
            dispatch_async(dispatch_get_main_queue(), ^{
                if (generation != sg_generation || !SGMotionAppleMusicOn()) { answer(nil, NO); return; }
                if (![json isKindOfClass:NSDictionary.class]) { answer(nil, NO); return; }
                keepAlbumYear(uri, year);
                if (!upc) { answer(firstTrack, YES); return; }
                NSString *address = [NSString stringWithFormat:@"https://amp-api.music.apple.com/v1/catalog/us/albums?filter%%5Bupc%%5D=%@&extend=editorialVideo", upc];
                askCatalogJSON(address, YES, ^(NSDictionary *reply, NSInteger status) {
                    if (generation != sg_generation || !SGMotionAppleMusicOn()) { answer(nil, NO); return; }
                    NSArray *records = reply[@"data"];
                    if (status != 200 || ![records isKindOfClass:NSArray.class] || reply[@"next"]) { answer(nil, NO); return; }
                    NSString *wanted = barcodeKey(upc);
                    NSMutableArray *matches = [NSMutableArray array];
                    for (id record in records) {
                        if (![barcodeKey(dig(record, @"attributes/upc")) isEqual:wanted]) continue;
                        NSString *candidate = dig(record, @"id");
                        if (![candidate isKindOfClass:NSString.class] || !candidate.length) { answer(nil, NO); return; }
                        [matches addObject:record];
                    }
                    if (matches.count) selectIdentifierCover(matches, answer);
                    else answer(firstTrack, YES);
                });
            });
        });
    });
}

static void keepDownloadedRelease(NSString *uri, NSURL *remote) {
    NSString *key = identifierKey(uri);
    if (![sg_kept[key] isEqual:remote]) {
        keepValue(key, remote);
        keepAlbumAnswer(key, remote);
    }
}

typedef NSString *(^SGRowVideo)(NSString *, NSString *);

// Main queue. A different track can prove the release while either the search or the
// file request is outstanding. Only identifier proof may write the album-wide answer.
static void deliverCoverFile(NSString *uri, NSUInteger generation, SGMotionTicket *ticket, NSURL *address,
                             SGMotionIdentifierOutcome outcome, void (^done)(NSURL *, SGMotionIdentifierOutcome)) {
    if (ticket.cancelled) return;
    if (generation != sg_generation) { done(nil, SGMotionIdentifierUnavailable); return; }
    BOOL proof = outcome == SGMotionIdentifierClip;
    NSURL *preferred = proof ? nil : verifiedClip(uri);
    NSURL *requested = preferred ?: address;
    ticket.child = SGMotionRequestFile(requested, ^(NSURL *file) {
        ticket.child = nil;
        if (ticket.cancelled) return;
        if (generation != sg_generation) { done(nil, SGMotionIdentifierUnavailable); return; }
        NSURL *now = proof ? nil : verifiedClip(uri);
        if (now && ![now isEqual:requested]) {
            deliverCoverFile(uri, generation, ticket, now, SGMotionIdentifierKnownTitle, done);
            return;
        }
        if (proof && file) keepDownloadedRelease(uri, address);
        done(file, (proof || preferred || now) ? (file ? SGMotionIdentifierClip : SGMotionIdentifierUnavailable) : outcome);
    });
}

// Distinct releases stay ambiguous even when only one moves. Duplicate songs on the
// same release (including its music videos) are one piece of evidence, not two.
static id mergeRecord(id a, id b) {
    if (!a || !b || [a isEqual:b]) return a ?: b;
    return NSNull.null;
}

// A full page may have left out the album beside its single, so only a complete result may fall back to one.
static SGRowVideo rowVideoIndex(NSArray *records, NSString *artist, NSString *album, NSString **exactVideo, BOOL *identified) {
    *identified = NO;
    NSMutableArray *candidates = [NSMutableArray array], *videos = [NSMutableArray array];
    BOOL single = [album hasSuffix:@" - single"], complete = records.count < kCoverSearchLimit;
    NSString *singleVideo = nil;
    NSUInteger singles = 0;
    NSUInteger exactReleases = 0;
    for (id record in records) {
        if (!sameRelease(record, album)) continue;
        id isSingle = dig(record, @"attributes/isSingle");
        if (!single && [isSingle isEqual:@YES]) {
            if (complete && namedSingle(record) && [coverKey(dig(record, @"attributes/artistName")) isEqual:artist]) {
                singles++;
                singleVideo = videoOf(dig(record, @"attributes/editorialVideo"));
            }
            continue;
        }
        NSString *video = videoOf(dig(record, @"attributes/editorialVideo"));
        if ([coverKey(dig(record, @"attributes/artistName")) isEqual:artist]) {
            *identified = YES;
            *exactVideo = ++exactReleases == 1 ? video : nil;
        }
        if (!single && ![isSingle isEqual:@NO]) continue;
        [candidates addObject:record];
        [videos addObject:video ?: (id)NSNull.null];
    }
    if (!*identified && !candidates.count && singles == 1 && singleVideo) {
        *identified = YES;
        *exactVideo = singleVideo;
    }
    if (*identified || !candidates.count) return nil;
    NSMutableDictionary *exact = [NSMutableDictionary dictionary], *featured = [NSMutableDictionary dictionary];
    for (NSUInteger i = 0; i < candidates.count; i++) {
        NSNumber *release = @(i);
        id tracks = dig(candidates[i], @"relationships/tracks/data");
        if (![tracks isKindOfClass:NSArray.class]) continue;
        for (id track in tracks) {
            NSString *full = coverKey(dig(track, @"attributes/name")), *title = SGLyricsSimplifiedTitle(full);
            NSString *credit = joinedCredit(coverKey(dig(track, @"attributes/artistName")));
            if (!title.length || !credit.length) continue;
            NSArray *key = @[title, credit];
            exact[key] = mergeRecord(exact[key], release);
            for (NSString *other in featureAlternates(credit, full)) {
                key = @[title, other];
                featured[key] = mergeRecord(featured[key], release);
            }
        }
    }
    if (!exact.count) return nil;
    return ^NSString *(NSString *rowArtist, NSString *rowSong) {
        NSString *song = coverKey(rowSong), *title = SGLyricsSimplifiedTitle(song), *credit = joinedCredit(coverKey(rowArtist));
        if (!title.length || !credit.length) return nil;
        NSArray *key = @[title, credit];
        id record = mergeRecord(exact[key], featured[key]);
        for (NSString *other in featureAlternates(credit, song))
            record = mergeRecord(record, exact[@[title, other]]);
        id video = [record isKindOfClass:NSNumber.class] ? videos[[record unsignedIntegerValue]] : nil;
        return video == NSNull.null ? nil : video;
    };
}

void SGMotionAlbumRowMatcher(NSString *albumArtist, NSString *album, NSString *uri, CGFloat pixels, void (^ready)(SGMotionRowMatch), void (^found)(NSURL *)) {
    NSUInteger generation = sg_generation;
    void (^deliver)(NSURL *) = ^(NSURL *remote) {
        deliverCoverFile(uri, generation, nil, remote, SGMotionIdentifierKnownTitle, ^(NSURL *file, SGMotionIdentifierOutcome outcome) {
            if (file) found(file);
        });
    };
    if (verifiedClip(uri)) { ready(nil); deliver(nil); return; }
    NSString *albumKey = coverKey(album);
    songCoverRecords(album, ^(NSArray *records) {
        if (!records || generation != sg_generation) { ready(nil); return; }
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            NSString *exact = nil;
            BOOL identified;
            SGRowVideo lookup = rowVideoIndex(records, coverKey(albumArtist), albumKey, &exact, &identified);
            dispatch_async(dispatch_get_main_queue(), ^{
                if (generation != sg_generation) { ready(nil); return; }
                if (verifiedClip(uri)) { ready(nil); deliver(nil); return; }
                void (^fetchVideo)(NSString *) = ^(NSString *video) {
                    masterFile(video, pixels, ^(NSURL *remote) {
                        deliver(remote);
                    });
                };
                if (!lookup) {
                    ready(nil);
                    if (exact) fetchVideo(exact);
                    else if (!identified) found(nil);
                    return;
                }
                ready(^BOOL(NSString *artist, NSString *song) {
                    if (generation != sg_generation) return NO;
                    if (verifiedClip(uri)) { deliver(nil); return YES; }
                    NSString *video = lookup(artist, song);
                    if (!video) return NO;
                    fetchVideo(video);
                    return YES;
                });
            });
        });
    });
}

// Cache values: URL for a clip, @NO for an identified release without video, nil for no match.
// `year`, when given, holds the title search to Apple's releases of that year (inYear) and keeps its answers apart.
static NSString *releaseTitleKey(NSString *artistKey, NSString *albumKey) {
    NSString *base = [NSString stringWithFormat:@"album\n5\n%@\n%@", artistKey, albumKey];
    NSString *legacy = [NSString stringWithFormat:@"album\n4\n%@\n%@", artistKey, albumKey];
    return !sg_kept[base] && sg_kept[legacy] && sg_kept[legacy] != NSNull.null ? legacy : base;
}

static SGMotionTicket *requestCover(NSString *artist, NSString *album, NSString *song, NSString *albumURI, NSString *trackURI, BOOL titleOnly, NSNumber *year, CGFloat pixels, void (^done)(NSURL *, BOOL identified)) {
    SGMotionTicket *ticket = [SGMotionTicket new];
    NSString *artistKey = coverKey(artist), *albumKey = coverKey(album), *songKey = coverKey(song);
    // A legacy URL (or miss) was decided with editions collapsed and no track evidence; a "2" miss could
    // be an EP that Apple Music names with " - EP", a "3" miss a single it names with " - Single".
    // "4" and "song7" misses were decided before a name matched by its words alone (sameRelease): asked again.
    setUp();
    NSString *base = releaseTitleKey(artistKey, albumKey);
    BOOL needsSong = songKey.length && (!sg_kept[base] || sg_kept[base] == NSNull.null);
    // Older song-level misses could also mean the track identified a release without video, so only the clips
    // kept under the older key are still read.
    NSString *key = base;
    if (needsSong) {
        NSString *song = [NSString stringWithFormat:@"%@\n%@\n%@", artistKey, albumKey, songKey];
        key = [@"album\nsong8\n" stringByAppendingString:song];
        if (!sg_kept[key] || sg_kept[key] == NSNull.null) {
            for (NSString *prefix in @[@"album\nsong7\n", @"album\nsong4\n"]) {
                NSString *older = [prefix stringByAppendingString:song];
                if ([sg_kept[older] isKindOfClass:NSURL.class]) { key = older; break; }
            }
        }
    }
    NSUInteger generation = sg_generation;
    // The remote file is what is kept: the store may drop its local copy later in the launch.
    void (^deliver)(id, BOOL) = ^(id remote, BOOL verified) {
        NSURL *address = [remote isKindOfClass:NSURL.class] ? remote : nil;
        SGMotionIdentifierOutcome result = verified ? SGMotionIdentifierClip : remote ? SGMotionIdentifierKnownTitle : SGMotionIdentifierMiss;
        deliverCoverFile(albumURI, generation, ticket, address, result, ^(NSURL *file, SGMotionIdentifierOutcome outcome) {
            done(file, outcome == SGMotionIdentifierKnownTitle || outcome == SGMotionIdentifierClip);
        });
    };
    NSURL *verified = verifiedClip(albumURI);
    if (verified) {
        deliver(verified, NO);
        return ticket;
    }
    if (!artistKey.length || !albumKey.length) {
        deliver(nil, NO);
        return ticket;
    }
    if (!year && sg_kept[key] && sg_kept[key] != NSNull.null) {
        deliver(sg_kept[key], NO);
        return ticket;
    }
    void (^byTitle)(NSNumber *) = ^(NSNumber *wantYear) {
        if (verifiedClip(albumURI)) { deliver(nil, NO); return; }
        // A year-held search is its own answer, never one kept from a search of every year, nor kept for one.
        NSString *k = wantYear ? [key stringByAppendingFormat:@"\nyear\n%@", wantYear] : key;
        NSString *b = wantYear ? [base stringByAppendingFormat:@"\nyear\n%@", wantYear] : base;
        id kept = sg_kept[k];
        if (kept) { deliver(kept == NSNull.null ? nil : kept, NO); return; }
        // A header (or its notes) may already have fetched the title's records. They are a title's evidence, so they
        // answer only where a title search would: after the identifiers, never in their place.
        NSArray *knownRecords = wantYear ? nil : sg_kept[albumRecordsKey(artist, album)];
        if ([knownRecords isKindOfClass:NSArray.class]) {
            NSUInteger matches;
            NSString *video = coverVideo(knownRecords, albumKey, artistKey, nil, NO, &matches);
            if (matches == 1) {
                if (video) masterFile(video, pixels, ^(NSURL *remote) { deliver(remote, NO); });
                else deliver(@NO, NO);
                return;
            }
        }
        // Raw records and playlists still coalesce. Selection belongs to this URI:
        // its verified clip must neither satisfy nor suppress another edition's search.
        void (^search)(void) = ^{
            void (^resolveVideo)(NSString *, BOOL, BOOL, BOOL) = ^(NSString *video, BOOL answered, BOOL albumMatch, BOOL songMatch) {
                void (^finish)(NSURL *) = ^(NSURL *file) {
                    id result = file ?: (albumMatch || songMatch ? (id)@NO : nil);
                    // Don't publish a losing title answer (and don't put the winner in a
                    // title key shared with other Spotify releases).
                    if (answered && (!video || file) && generation == sg_generation && !verifiedClip(albumURI)) {
                        NSString *cacheKey = needsSong && albumMatch ? b : k;
                        keepValue(cacheKey, result);
                        keepAlbumAnswer(cacheKey, result);
                    }
                    deliver(result, NO);
                };
                if (video && generation == sg_generation) masterFile(video, pixels, finish);
                else finish(nil);
            };
            BOOL (^select)(NSArray *, BOOL) = ^BOOL(NSArray *found, BOOL final) {
                if (verifiedClip(albumURI)) { deliver(nil, NO); return YES; }
                NSArray *records = inYear(found, wantYear);
                NSUInteger albums, songs = 0;
                NSString *video = coverVideo(records, albumKey, artistKey, nil, NO, &albums);
                if (!albums && needsSong) video = coverVideo(records, albumKey, artistKey, songKey, NO, &songs);
                if (!albums && !songs && final) {
                    video = coverVideo(records, albumKey, artistKey, nil, YES, &albums);
                    if (!albums && needsSong) video = coverVideo(records, albumKey, artistKey, songKey, YES, &songs);
                }
                if (!albums && !songs && !final) return NO;
                resolveVideo(video, records != nil, albums != 0, songs == 1);
                return YES;
            };
            if (needsSong) songCoverRecords(album, ^(NSArray *found) {
                if (!select(found, found.count != kCoverSearchLimit || generation != sg_generation)) {
                    // Title-only ranking can omit an ordinary album that the qualified search finds.
                    NSString *term = [NSString stringWithFormat:@"%@ %@", artist, SGMotionSearchName(album)];
                    songCoverRecords(term, ^(NSArray *narrow) { select(narrow, YES); });
                }
            });
            else albumRecords(artist, album, ^(NSArray *found) { select(found, YES); });
        };
        search();
    };
    // The album's identifiers first: they name the very release, where a title can name another of the same name (the
    // 2016 "Moana (Original Motion Picture Soundtrack)" and the 2026 film's). A clip they find is the answer. A still
    // edition they name is not the last word: a reissue's barcode and remastered recordings can point at an edition of
    // Apple's that does not move while the one that does carries other codes (Lynyrd Skynyrd's "Pronounced' Leh-'Nerd
    // 'Skin-'Nerd"), so the title is asked then too, with the same artist (or the song's credit) as it always needs; a
    // title that finds nothing leaves the identifiers' still.
    if (titleOnly || !SGSpotifyValidURI(albumURI, @"album") || !SGMotionAppleMusicOn()) byTitle(year);
    else {
        identifierCover(albumURI, album, trackURI, pixels, ^(NSURL *remote, SGMotionIdentifierOutcome outcome) {
            if (ticket.cancelled) return;
            if (generation != sg_generation) { deliver(nil, NO); return; }
            if (outcome != SGMotionIdentifierClip && verifiedClip(albumURI)) { deliver(nil, NO); return; }
            if (outcome == SGMotionIdentifierMiss) { byTitle(nil); return; }
            if (outcome != SGMotionIdentifierStill) { deliver(remote, outcome == SGMotionIdentifierClip); return; }
            // A still edition: the title only within the album's year, and not at all without one (inYear).
            albumYear(albumURI, ^(NSNumber *released) {
                if (ticket.cancelled) return;
                if (released && generation == sg_generation) byTitle(released);
                else deliver(@NO, NO);
            });
        });
    }
    return ticket;
}

SGMotionTicket *SGMotionRequestSongCover(NSString *artist, NSString *album, NSString *song, NSString *albumURI, NSString *trackURI, CGFloat pixels, void (^done)(NSURL *)) {
    return requestCover(artist, album, song, albumURI, trackURI, NO, nil, pixels, ^(NSURL *file, BOOL identified) { done(file); });
}

void SGMotionPageAlbumCover(NSString *artist, NSString *album, NSString *uri, CGFloat pixels, void (^done)(NSURL *, BOOL identified)) {
    requestCover(artist, album, nil, uri, nil, YES, nil, pixels, done);
}

void SGMotionPageStillEditionCover(NSString *albumURI, NSString *artist, NSString *album, CGFloat pixels, void (^done)(NSURL *)) {
    NSUInteger generation = sg_generation;
    if (verifiedClip(albumURI)) { SGMotionPageAlbumCover(artist, album, albumURI, pixels, ^(NSURL *file, BOOL identified) { done(file); }); return; }
    albumYear(albumURI, ^(NSNumber *year) {
        if (generation != sg_generation || (!year && !verifiedClip(albumURI))) { done(nil); return; }
        requestCover(artist, album, nil, albumURI, nil, YES, year, pixels, ^(NSURL *file, BOOL identified) { done(file); });
    });
}

void SGMotionPageIdentifierCover(NSString *albumURI, NSString *artist, NSString *album, CGFloat pixels, void (^done)(NSURL *, SGMotionIdentifierOutcome)) {
    NSUInteger generation = sg_generation;
    setUp();
    id known = sg_kept[releaseTitleKey(coverKey(artist), coverKey(album))];
    if (verifiedClip(albumURI) || (known && known != NSNull.null)) {
        deliverCoverFile(albumURI, generation, nil, [known isKindOfClass:NSURL.class] ? known : nil, SGMotionIdentifierKnownTitle, done);
        return;
    }
    identifierCover(albumURI, album, nil, pixels, ^(NSURL *remote, SGMotionIdentifierOutcome outcome) {
        deliverCoverFile(albumURI, generation, nil, remote, outcome, done);
    });
}

#pragma mark - artist logos

static void artistRecords(NSString *artist, void (^done)(NSArray *records)) {
    lookUp([@"artist-records\n" stringByAppendingString:artistNameKey(artist)], done, ^(void (^answer)(id, BOOL)) {
        search(@"artists", artist, @"editorialArtwork,editorialVideo", YES,
               ^(NSArray *found, BOOL answered) { answer(found, answered); });
    });
}

// The URL is a template ending in {w}x{h}bb.jpg; the same image comes as a PNG with its transparency.
static NSURL *logoURL(id logo, CGFloat pixels) {
    id url = dig(logo, @"url"), width = dig(logo, @"width"), height = dig(logo, @"height");
    if (![url isKindOfClass:NSString.class] || ![width isKindOfClass:NSNumber.class] || ![height isKindOfClass:NSNumber.class]) return nil;
    if ([width doubleValue] <= 0 || [height doubleValue] <= 0) return nil;
    long w = MAX(1, lround(pixels)), h = MAX(1, lround(pixels * [height doubleValue] / [width doubleValue]));
    NSString *filled = [[url stringByReplacingOccurrencesOfString:@"{w}" withString:@(w).stringValue]
                        stringByReplacingOccurrencesOfString:@"{h}" withString:@(h).stringValue];
    if ([filled hasSuffix:@".jpg"]) filled = [[filled substringToIndex:filled.length - 4] stringByAppendingString:@".png"];
    return [NSURL URLWithString:filled];
}

void SGMotionArtistLogo(NSString *artist, CGFloat pixels, void (^done)(UIImage *logo)) {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ SGMotionArtistLogo(artist, pixels, done); });
        return;
    }
    NSString *artistKey = SGMotionNameKey(artist);
    if (!artistKey.length) {
        done(nil);
        return;
    }
    lookUp([@"logo\n" stringByAppendingString:artistKey], ^(UIImage *logo) { done(logo); }, ^(void (^answer)(id, BOOL)) {
        artistRecords(artist, ^(NSArray *found) {
            if (!found) {
                answer(nil, NO);
                return;
            }
            NSURL *url = nil;
            for (id result in found) {
                id attributes = dig(result, @"attributes");
                if (![SGMotionNameKey(dig(attributes, @"name")) isEqualToString:artistKey]) continue;
                url = logoURL(dig(attributes, @"editorialArtwork/musicContentColorLogoTrimmed"), pixels);
                break;
            }
            SGLog(@"motion: %@ has %@", artist, url ? @"a logo" : @"no logo");
            if (!url) {
                answer(nil, YES);
                return;
            }
            fetch(requestFor(url), ^id(NSData *data) { return [UIImage imageWithData:data]; }, ^(UIImage *logo, NSInteger status) {
                answer(logo, status == 200);
            });
        });
    });
}

static const NSUInteger kArtistCandidateLimit = 3, kArtistAlbumPages = 3;

// Search relationships may only contain the first 25 releases. Follow the
// relationship endpoint's actual cursor, never infer completeness from count.
static void artistAlbumPage(NSString *identifier, NSURL *url, NSUInteger page,
                            NSMutableArray *albums, void (^done)(NSArray *, BOOL)) {
    SGLog(@"catalog artist id=%@: albums request page=%lu/%lu", identifier, (unsigned long)page, (unsigned long)kArtistAlbumPages);
    askCatalogJSON(url.absoluteString, YES, ^(NSDictionary *json, NSInteger status) {
        SGLog(@"catalog artist id=%@: albums page=%lu HTTP=%ld%@", identifier, (unsigned long)page, (long)status,
            status ? @"" : @" (network/unavailable)");
        if (status == 404 && page == 1) {
            SGLog(@"catalog artist id=%@: albums complete pages=1 releases=0 (HTTP 404)", identifier);
            done(@[], YES);
            return;
        }
        id data = json[@"data"], next = json[@"next"];
        if (status != 200 || ![data isKindOfClass:NSArray.class]) { done(nil, NO); return; }
        [albums addObjectsFromArray:data];
        if (![data count] || !next || next == NSNull.null || [next isEqual:@""]) {
            SGLog(@"catalog artist id=%@: albums complete pages=%lu releases=%lu", identifier, (unsigned long)page, (unsigned long)albums.count);
            done(albums, YES);
            return;
        }
        if (page == kArtistAlbumPages) {
            SGLog(@"catalog artist id=%@: refuse: album page budget exhausted", identifier);
            done(nil, YES);
            return;
        }
        NSURL *following = [next isKindOfClass:NSString.class] ? [NSURL URLWithString:next relativeToURL:url].absoluteURL : nil;
        if (![following.scheme isEqual:@"https"] || ![following.host isEqual:url.host] ||
            following.port || ![following.path isEqual:url.path] || following.user || following.password) {
            SGLog(@"catalog artist id=%@: refuse: invalid album cursor", identifier);
            done(nil, YES);
            return;
        }
        artistAlbumPage(identifier, following, page + 1, albums, done);
    });
}

void SGMotionArtistArtwork(NSString *artist, NSArray<NSString *> *titles, CGFloat pixels,
                          BOOL photo, BOOL motion, void (^done)(UIImage *, NSURL *, SGMotionArtistArtworkOutcome)) {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ SGMotionArtistArtwork(artist, titles, pixels, photo, motion, done); });
        return;
    }
    if ((!photo && !motion) || titles.count < 2 || !artist.length) {
        done(nil, nil, titles.count < 2 ? SGMotionArtistArtworkNeedsEvidence : SGMotionArtistArtworkFinished); return;
    }
    // A request that began before a clear starts no further lookup or download after it, at any step below. It is
    // answered as a metadata failure, which nothing keeps, so a later request asks again.
    NSUInteger generation = sg_generation;
    artistRecords(artist, ^(NSArray *records) {
        if (generation != sg_generation) { done(nil, nil, SGMotionArtistArtworkMetadataFailed); return; }
        NSString *identity = [@"artist " stringByAppendingString:artist];
        catalogDiagnostic(identity, @"records", [NSString stringWithFormat:@"artist search records=%lu extend=editorialArtwork,editorialVideo", (unsigned long)records.count]);
        if (!records) {
            catalogDiagnostic(identity, @"selection", @"no Apple artist chosen: catalog unavailable/error");
            done(nil, nil, SGMotionArtistArtworkMetadataFailed); return;
        }
        NSMutableArray *namesakes = [NSMutableArray array];
        // A non-exact normalized name is not a namesake; its missing/failed
        // discography cannot veto the verified artist. Exact names still can.
        for (id record in records)
            if ([artistNameKey(dig(record, @"attributes/name")) isEqual:artistNameKey(artist)]) [namesakes addObject:record];
        if (namesakes.count > kArtistCandidateLimit) {
            catalogDiagnostic(identity, @"candidate-budget", @"refuse: namesake budget exceeded");
            done(nil, nil, SGMotionArtistArtworkMetadataFailed);
            return;
        }
        catalogDiagnostic(identity, @"request-budget", [NSString stringWithFormat:@"request budget search=1 albums<=%lu (%lu per namesake) resource<=1; cached results reused",
            (unsigned long)(kArtistCandidateLimit * kArtistAlbumPages), (unsigned long)kArtistAlbumPages]);
        NSMutableArray *candidates = [NSMutableArray array];
        dispatch_group_t group = dispatch_group_create();
        __block BOOL failed = NO;
        for (id record in namesakes) {
            id name = dig(record, @"attributes/name"), identifier = dig(record, @"id");
            catalogDiagnostic(identity, [NSString stringWithFormat:@"search-fields-%@", identifier],
                [NSString stringWithFormat:@"search candidate id=%@ name=%@ editorialArtwork=%d editorialVideo=%d motionArtistSquare1x1=%d",
                    identifier, name, dig(record, @"attributes/editorialArtwork") != nil,
                    dig(record, @"attributes/editorialVideo") != nil,
                    dig(record, @"attributes/editorialVideo/motionArtistSquare1x1/video") != nil]);
            if (![identifier isKindOfClass:NSString.class] || ![identifier length]) { failed = YES; continue; }
            dispatch_group_enter(group);
            lookUp([@"artist-albums\n" stringByAppendingString:identifier], ^(NSArray *albums) {
                if (!albums) failed = YES;
                else {
                    NSMutableDictionary *candidate = [record mutableCopy];
                    candidate[@"relationships"] = @{@"albums": @{@"data": albums}};
                    [candidates addObject:candidate];
                }
                dispatch_group_leave(group);
            }, ^(void (^answer)(id, BOOL)) {
                NSString *url = [NSString stringWithFormat:@"https://amp-api.music.apple.com/v1/catalog/us/artists/%@/albums?limit=100", escaped(identifier)];
                artistAlbumPage(identifier, [NSURL URLWithString:url], 1, [NSMutableArray array],
                    ^(NSArray *albums, BOOL answered) { answer(albums, answered); });
            });
        }
        dispatch_group_notify(group, dispatch_get_main_queue(), ^{
            if (generation != sg_generation) { done(nil, nil, SGMotionArtistArtworkMetadataFailed); return; }
            NSDictionary *match = SGMotionArtistMatch(candidates, artist, titles);
            if (failed) match = nil; // still log successful candidates' overlaps
            SGLog(@"catalog %@: %@", identity, match ?
                [NSString stringWithFormat:@"chosen Apple artist id=%@", dig(match, @"id")] :
                [NSString stringWithFormat:@"no Apple artist chosen: %@", failed ? @"release lookup failed/incomplete" : @"wait: no unique namesake with two release matches"]);
            if (!match) {
                done(nil, nil, failed ? SGMotionArtistArtworkMetadataFailed : SGMotionArtistArtworkNeedsEvidence);
                return;
            }
            void (^assetsForResource)(NSDictionary *) = ^(NSDictionary *resource) {
            if (generation != sg_generation) { done(nil, nil, SGMotionArtistArtworkMetadataFailed); return; }
            dispatch_group_t assets = dispatch_group_create();
            __block UIImage *image = nil;
            __block NSURL *file = nil;
            NSURL *imageURL = photo ? logoURL(dig(match, @"attributes/artwork"), pixels) : nil;
            if (imageURL) {
                dispatch_group_enter(assets);
                lookUp([@"artist-photo\n" stringByAppendingString:imageURL.absoluteString], ^(UIImage *value) {
                    image = value;
                    dispatch_group_leave(assets);
                }, ^(void (^answer)(id, BOOL)) {
                    fetch(requestFor(imageURL), ^id(NSData *data) { return [UIImage imageWithData:data]; },
                          ^(UIImage *value, NSInteger status) { answer(value, status == 200); });
                });
            }
            id video = dig(resource, @"attributes/editorialVideo/motionArtistSquare1x1/video");
            if (![video isKindOfClass:NSString.class]) video = dig(resource, @"attributes/editorialVideo/motionSquareVideo1x1/video");
            catalogDiagnostic(identity, @"fields", [NSString stringWithFormat:@"artwork=%d editorialArtwork=%d editorialVideo=%d motionArtistSquare1x1=%d squareVideo=%d",
                dig(match, @"attributes/artwork") != nil, dig(match, @"attributes/editorialArtwork") != nil,
                dig(resource, @"attributes/editorialVideo") != nil,
                dig(resource, @"attributes/editorialVideo/motionArtistSquare1x1/video") != nil,
                dig(resource, @"attributes/editorialVideo/motionSquareVideo1x1/video") != nil]);
            NSURL *master = motion && [video isKindOfClass:NSString.class] ? [NSURL URLWithString:video] : nil;
            if (master) {
                dispatch_group_enter(assets);
                NSString *key = [NSString stringWithFormat:@"artist-motion\n%@\n%.0f", master.absoluteString, pixels];
                lookUp(key, ^(NSURL *remote) {
                    if (generation != sg_generation) { dispatch_group_leave(assets); return; }   // asked before a clear
                    SGMotionFile(remote, ^(NSURL *local) { file = local; dispatch_group_leave(assets); });
                }, ^(void (^answer)(id, BOOL)) { wholeFileOf(master, pixels, answer); });
            }
            dispatch_group_notify(assets, dispatch_get_main_queue(), ^{
                catalogDiagnostic(identity, @"assets", [NSString stringWithFormat:@"assets photo=%@ motion=%@ LowDataDownloads=%@",
                    !photo ? @"off" : image ? @"ready" : imageURL ? @"failed" : @"absent",
                    !motion ? @"off" : file ? @"ready (download/cache)" : master ? @"failed (playlist/download)" : @"absent",
                    SGFlag(SGKeyMotionLowData, NO) ? @"allowed" : @"blocked on constrained networks"]);
                done(image, file, motion && !resource ? SGMotionArtistArtworkMetadataFailed : SGMotionArtistArtworkFinished);
            });
            };
            if (!motion) { assetsForResource(nil); return; }
            NSString *identifier = dig(match, @"id");
            lookUp([@"artist-resource\n" stringByAppendingString:identifier], assetsForResource, ^(void (^answer)(id, BOOL)) {
                SGLog(@"catalog artist %@: resource request id=%@ extend=editorialVideo", artist, identifier);
                NSString *url = [NSString stringWithFormat:@"https://amp-api.music.apple.com/v1/catalog/us/artists/%@?extend=editorialVideo", escaped(identifier)];
                askCatalog(url, @"data", YES, ^(NSArray *found, BOOL answered) {
                    NSDictionary *resource = nil;
                    for (id item in found) if ([dig(item, @"id") isEqual:identifier]) { resource = item; break; }
                    SGLog(@"catalog artist %@: resource id=%@ answered=%d editorialVideo=%d motionArtistSquare1x1=%d",
                        artist, identifier, answered, dig(resource, @"attributes/editorialVideo") != nil,
                        dig(resource, @"attributes/editorialVideo/motionArtistSquare1x1/video") != nil);
                    answer(resource, answered && resource != nil);
                });
            });
        });
    });
}

#pragma mark - recordings

// The catalog's songs with this ISRC, for iOS's Music Haptics: the recording itself, not a search by name.
void SGMotionSongsWithISRC(NSString *isrc, void (^done)(NSArray *songs)) {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ SGMotionSongsWithISRC(isrc, done); });
        return;
    }
    if (!isrc.length) {
        done(nil);
        return;
    }
    lookUp([@"isrc\n" stringByAppendingString:isrc], done, ^(void (^answer)(id, BOOL)) {
        // The phone's own country first, as Apple sells some recordings only there; then the US catalog.
        NSString *region = NSLocale.currentLocale.countryCode.lowercaseString;
        if (![region rangeOfString:@"^[a-z]{2}$" options:NSRegularExpressionSearch].length) region = @"us";
        // filter[isrc] and fields[songs], the brackets escaped: iOS before 17 makes no URL of them bare.
        NSString *(^addressIn)(NSString *) = ^NSString *(NSString *storefront) {
            return [NSString stringWithFormat:@"https://amp-api.music.apple.com/v1/catalog/%@/songs?filter%%5Bisrc%%5D=%@&fields%%5Bsongs%%5D=isrc,durationInMillis,hasHaptics",
                    storefront, escaped(isrc)];
        };
        askCatalog(addressIn(region), @"data", YES, ^(NSArray *found, BOOL answered) {
            if (found.count || [region isEqualToString:@"us"]) {
                answer(found, answered);
                return;
            }
            askCatalog(addressIn(@"us"), @"data", YES, ^(NSArray *inUS, BOOL answeredInUS) { answer(inUS, answeredInUS); });
        });
    });
}

#pragma mark - clearing

void SGMotionCacheBytes(void (^done)(uint64_t bytes)) {
    dispatch_group_t group = dispatch_group_create();
    __block uint64_t total = 0;   // main only
    dispatch_group_enter(group);
    SGMotionStoreBytes(^(uint64_t bytes) { total += bytes; dispatch_group_leave(group); });
    dispatch_group_enter(group);
    NSURL *answers = albumAnswersFile();
    dispatch_async(albumQueue(), ^{
        NSNumber *size = [NSFileManager.defaultManager attributesOfItemAtPath:answers.path error:nil][NSFileSize];
        dispatch_async(dispatch_get_main_queue(), ^{ total += size.unsignedLongLongValue; dispatch_group_leave(group); });
    });
    dispatch_group_notify(group, dispatch_get_main_queue(), ^{ done(total); });
}

void SGMotionCacheClear(void (^done)(BOOL complete)) {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ SGMotionCacheClear(done); });
        return;
    }
    if (!albumAnswersFile()) { done(NO); return; }
    sg_answersCleared = YES;   // a clear before the first lookup: the launch need not read what the clear removes
    setUp();
    sg_generation++;
    [sg_kept removeAllObjects];
    [sg_keptOrder removeAllObjects];
    sg_logoBytes = 0;
    [sg_albumAnswers removeAllObjects];
    [sg_waiting removeAllObjects];
    dispatch_group_t group = dispatch_group_create();
    __block BOOL complete = YES;   // main only
    dispatch_group_enter(group);
    SGMotionStoreClear(^(BOOL clipsGone) { if (!clipsGone) complete = NO; dispatch_group_leave(group); });
    dispatch_group_enter(group);
    NSURL *answers = albumAnswersFile();
    // Behind any write already queued, so an older write cannot bring the file back.
    dispatch_async(albumQueue(), ^{
        NSError *error = nil;
        BOOL gone = [NSFileManager.defaultManager removeItemAtURL:answers error:&error] || ![NSFileManager.defaultManager fileExistsAtPath:answers.path];
        if (!gone) SGLog(@"motion: cannot remove album answers: %@", error.localizedDescription);
        dispatch_async(dispatch_get_main_queue(), ^{ if (!gone) complete = NO; dispatch_group_leave(group); });
    });
    dispatch_group_notify(group, dispatch_get_main_queue(), ^{ done(complete); });
}
