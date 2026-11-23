// Checks what is new in the lyrics sources and their words without the phone or the network: lines in
// Thai and the scripts like it split at the dictionary's words (KaraokeTiming.m), KuGou's KRC unpacked
// and read (KuGou.m, through NetEase.m's parser), and the QQ Music and KuGou asks matching a track
// against made-up search replies, plus Bugs, Genie, LyricsPlus and Deezer parser and request checks.
// The requests are answered here, by host. Any file named on the
// command line is a real KuGou download or QQ lyrics reply, saved as JSON, and only its line count is
// printed. Exits non-zero on the first wrong answer.
#import <UIKit/UIKit.h>
#import <zlib.h>
#import "Shared/LyricsSources/LyricsSources.h"
#import "Core/SGPrefs.h"
#import <Security/Security.h>

// Real provider behavior, with no access to the user's Keychain.
static NSString *sg_testARL;
static NSUInteger sg_arlReads;
static OSStatus sg_arlReadStatus;
static OSStatus readTestARL(CFDictionaryRef query, CFTypeRef *data) {
    sg_arlReads++;
    if (sg_arlReadStatus != errSecSuccess) return sg_arlReadStatus;
    if (!sg_testARL) return errSecItemNotFound;
    *data = CFBridgingRetain([sg_testARL dataUsingEncoding:NSUTF8StringEncoding]);
    return errSecSuccess;
}
static OSStatus deleteTestARL(CFDictionaryRef query) { sg_testARL = nil; return errSecSuccess; }
#define SecItemCopyMatching readTestARL
#define SecItemDelete deleteTestARL
#import "Shared/LyricsSources/Deezer.m"
#undef SecItemDelete
#undef SecItemCopyMatching

#define CHECK(cond) do { if (!(cond)) { fprintf(stderr, "FAILED line %d: %s\n", __LINE__, #cond); exit(1); } } while (0)

// What the sources reach outside themselves for: the requests, answered by sg_answer.
@implementation SGLyricsResult
@end
@implementation SGLyricsQuery
@end
void SGLyricsPageLines(NSArray<SGKaraokeLine *> *lines, NSArray<NSNumber *> **starts, NSArray<NSString *> **texts) {
    NSMutableArray *at = [NSMutableArray array], *said = [NSMutableArray array];
    for (SGKaraokeLine *line in lines) {
        [at addObject:@(line.start)];
        [said addObject:SGKaraokeLineText(line)];
    }
    *starts = at;
    *texts = said;
}
static NSError *sg_replyFailure;
void SGLyricsNoteReply(NSURLResponse *response, NSError *error) { if (error) sg_replyFailure = error; }
NSURL *SGLyricsURL(NSString *base, NSDictionary<NSString *, NSString *> *query) {
    NSURLComponents *url = [NSURLComponents componentsWithString:base];
    NSMutableArray<NSURLQueryItem *> *items = [NSMutableArray array];
    [query enumerateKeysAndObjectsUsingBlock:^(NSString *name, NSString *value, BOOL *stop) {
        [items addObject:[NSURLQueryItem queryItemWithName:name value:value]];
    }];
    url.queryItems = items;
    return url.URL;
}
// Musixmatch.m asks these of a local file, which no check here plays.
BOOL SGLocalFileIs(NSString *uri) { return NO; }
NSDictionary<NSString *, id> *SGLocalFileInfo(NSString *uri) { return nil; }
static id (^sg_answer)(NSURL *url, id body);
void SGLyricsGetJSON(NSURL *url, NSDictionary *headers, void (^done)(id root)) {
    CHECK(![url.host isEqualToString:@"lrclib.net"]); // LRCLIB must use the bounded transport.
    done(sg_answer(url, nil));
}
void SGLyricsPostJSON(NSURL *url, NSDictionary *headers, id body, void (^done)(id root)) { done(sg_answer(url, body)); }
void SGLyricsPostJSONTransform(NSURL *url, NSDictionary *headers, id body, id (^transform)(id), void (^done)(id)) {
    id root = sg_answer(url, body);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        CHECK(!NSThread.isMainThread);
        id result = transform ? transform(root) : root;
        dispatch_async(dispatch_get_main_queue(), ^{ done(result); });
    });
}
void SGLyricsGetJSONTransform(NSURL *url, NSDictionary *headers, id (^transform)(id), void (^done)(id)) {
    SGLyricsPostJSONTransform(url, headers, nil, transform, done);
}
void SGLyricsGetJSONTransformIn(SGLyricsRequestContext *context, NSURL *url, NSDictionary *headers, id (^transform)(id), void (^done)(id)) {
    SGLyricsGetJSONTransform(url, headers, transform, done);
}
void SGLyricsPostJSONTransformIn(SGLyricsRequestContext *context, NSURL *url, NSDictionary *headers, id body, id (^transform)(id), void (^done)(id)) {
    SGLyricsPostJSONTransform(url, headers, body, transform, done);
}

// The settings row is linked but never opened. Credentials and network answers are made up here.
NSString *SGL(NSString *key, NSString *english) { return english; }
SGModRow *SGStatActionRow(NSString *title, NSString *subtitle, NSString *(^value)(void), void (^action)(void)) { return nil; }
UIViewController *SGTopController(void) { return nil; }
NSArray *SGLyricsOrder(void) { return @[]; }
void SGLyricsSetOrder(NSArray *keys) {}
void SGDeezerAskWith(NSString *arl, SGLyricsQuery *query, void (^done)(SGLyricsResult *));
static id (^sg_sourceAnswer)(NSURL *, NSDictionary *, NSData *, NSInteger *);
static NSUInteger sg_sourceRequests;
void SGLyricsSourceRequest(NSURL *url, NSDictionary *headers, NSData *body, void (^done)(NSData *, NSInteger)) {
    CHECK(NSThread.isMainThread);
    sg_sourceRequests++;
    NSInteger status = 200;
    id answer;
    if ([url.host isEqualToString:@"lrclib.net"]) {
        CHECK([headers[@"User-Agent"] hasPrefix:@"Retrine "] && !body);
        answer = sg_answer(url, nil);
    } else answer = sg_sourceAnswer(url, headers, body, &status);
    NSData *data = [answer isKindOfClass:NSString.class] ? [answer dataUsingEncoding:NSUTF8StringEncoding] :
        answer ? [NSJSONSerialization dataWithJSONObject:answer options:NSJSONWritingFragmentsAllowed error:nil] : nil;
    done(data, status);
}
void SGLyricsSourceRequestIn(SGLyricsRequestContext *context, NSURL *url, NSDictionary *headers, NSData *body, void (^done)(NSData *, NSInteger)) {
    SGLyricsSourceRequest(url, headers, body, ^(NSData *data, NSInteger status) {
        [context noteFailure:status == 429 || status >= 500];
        done(data, status);
    });
}

// Service main-queue completions until the callback stops the run loop. The deadline only reports
// a missing callback; neither a sleep nor a fixed delay decides when a reply is ready.
static id awaitReply(void (^ask)(void (^done)(id)), BOOL *answeredAtOnce) {
    __block id answer;
    __block BOOL answered = NO, waiting = NO;
    ask(^(id value) {
        CHECK(NSThread.isMainThread && !answered);
        answer = value;
        answered = YES;
        if (waiting) CFRunLoopStop(CFRunLoopGetMain());
    });
    if (answeredAtOnce) *answeredAtOnce = answered;
    waiting = YES;
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5];
    while (!answered && deadline.timeIntervalSinceNow > 0)
        [NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:deadline];
    waiting = NO;
    CHECK(answered);
    return answer;
}

static NSArray<NSDictionary *> *searchAnswer(NSString *title, NSString *artist, NSInteger seconds) {
    return awaitReply(^(void (^done)(id)) { SGLrcLibSearch(title, artist, seconds, done); }, nil);
}

static void checkReadingAndSearch(void) {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    id prior = [defaults objectForKey:SGKeyLyricsJapaneseKana];
    SGSetEnabled(SGKeyLyricsJapaneseKana, NO);
    CHECK([SGLyricsRomanised(@"君の名前を呼んでいた", NO) isEqualToString:@"kimi no namae wo yon de i ta"]);
    NSString *romaji = SGLyricsRomanised(@"君の名前を呼ぶ", YES);
    SGSetEnabled(SGKeyLyricsJapaneseKana, YES);
    NSString *hiragana = SGLyricsRomanised(@"君の名前を呼ぶ", YES);
    printf("Japanese reading: %s -> %s\n", romaji.UTF8String, hiragana.UTF8String);
    CHECK([hiragana isEqualToString:@"きみのなまえをよぶ"]);
    CHECK(!SGLyricsRomanised(@"きみのなまえをよぶ、カナを！", YES));
    CHECK([SGLyricsRomanised(@"東京 Café を 名前!", YES) isEqualToString:@"とうきょう Café を なまえ!"]);
    SGSetEnabled(SGKeyLyricsJapaneseKana, NO);
    CHECK([SGLyricsRomanised(@"君の名前を呼ぶ", YES) isEqualToString:romaji]);
    if (prior) [defaults setObject:prior forKey:SGKeyLyricsJapaneseKana];
    else [defaults removeObjectForKey:SGKeyLyricsJapaneseKana];
    SGPrefsChanged();

    NSDictionary *plain = @{@"id": @1, @"duration": @200, @"plainLyrics": @"a line"};
    NSDictionary *near = @{@"id": @2, @"trackName": @"Song", @"artistName": @"Singer", @"albumName": NSNull.null,
                           @"duration": @200.2, @"syncedLyrics": @"[00:01.00]a line", @"instrumental": NSNull.null};
    NSDictionary *far = @{@"id": @3, @"duration": @180, @"syncedLyrics": @"[00:02.00]another line"};
    __block id reply = @[plain, far, near, NSNull.null, @{@"id": @YES}, @{@"id": @"4"}];
    sg_answer = ^id(NSURL *url, id body) {
        CHECK([url.host isEqualToString:@"lrclib.net"] && [url.path isEqualToString:@"/api/search"]);
        return reply;
    };
    NSArray<NSDictionary *> *found = searchAnswer(@"Song", @"Singer", 200);
    CHECK(found.count == 3 && [found[0][@"id"] isEqual:@2] && [found[1][@"id"] isEqual:@3] && [found[2][@"id"] isEqual:@1]);
    CHECK([found[0][@"title"] isEqual:@"Song"] && [found[0][@"artist"] isEqual:@"Singer"] && [found[0][@"album"] isEqual:@""]);
    CHECK([found[0][@"synced"] boolValue] && ![found[0][@"instrumental"] boolValue] && [found[0][@"seconds"] isEqual:@200.2]);
    CHECK([found[0][@"record"] isEqual:near]);
    // A length the server spells as null is no length to go on: the record is kept with 0 seconds, not
    // messaged with integerValue/doubleValue, which NSNull does not answer.
    NSDictionary *unsized = @{@"id": @20, @"trackName": @"Song", @"artistName": @"Singer", @"duration": NSNull.null,
                              @"syncedLyrics": @"[00:01.00]a line"};
    id sizedReply = reply;
    reply = @[unsized, near];
    found = searchAnswer(@"Song", @"Singer", 200);
    CHECK(found.count == 2 && [found[1][@"id"] isEqual:@20] && [found[1][@"seconds"] isEqual:@0]);
    CHECK(SGLrcLibRecordResult(unsized).karaokeLines.count == 1);
    reply = sizedReply;
    CHECK([SGLrcLibRecordResult(near).provider isEqual:@"LRCLIB"] && SGLrcLibRecordResult(plain).karaokeLines.count == 1);
    CHECK(!SGLrcLibRecordResult(@{@"plainLyrics": @"  ", @"instrumental": NSNull.null}));
    CHECK(SGLrcLibRecordResult(@{@"instrumental": @YES}).instrumental);
    found = searchAnswer(@"Song", @"Singer", 0);
    CHECK([found[0][@"id"] isEqual:@3] && [found[1][@"id"] isEqual:@2]);
    NSMutableArray *many = [NSMutableArray array];
    for (NSUInteger i = 1; i <= 25; i++) [many addObject:@{@"id": @(i), @"duration": @(i), @"syncedLyrics": @"[00:01]line"}];
    reply = many;
    found = searchAnswer(@"Song", @"", 25);
    CHECK(found.count == 20 && [found[0][@"id"] isEqual:@25] && [found.lastObject[@"id"] isEqual:@6]);
    // Only the first 100 wire records count, even when they are malformed.
    NSMutableArray *over100 = [NSMutableArray array];
    for (NSUInteger i = 0; i < 100; i++) [over100 addObject:NSNull.null];
    [over100 addObject:near]; reply = over100;
    found = searchAnswer(@"Song", @"Singer", 200);
    CHECK(!found.count);
    NSString *tooManyBytes = [@"é" stringByPaddingToLength:131073 withString:@"é" startingAtIndex:0];
    NSString *atByteLimit = [@"a" stringByPaddingToLength:256 * 1024 withString:@"a" startingAtIndex:0];
    NSMutableArray *rows = [NSMutableArray array];
    for (NSUInteger i = 0; i < 4000; i++) [rows addObject:@"[00:01]line"];
    NSString *atLineLimit = [rows componentsJoinedByString:@"\r\n"];
    NSString *tooManyLines = [atLineLimit stringByAppendingString:@"\r\n[00:02]extra"];
    CHECK(SGLrcLibRecordResult(@{@"plainLyrics": atByteLimit, @"instrumental": @YES}).instrumental);
    CHECK(SGLrcLibRecordResult(@{@"syncedLyrics": atLineLimit}).karaokeLines.count == 4000);
    for (NSString *field in @[@"plainLyrics", @"syncedLyrics"]) {
        for (NSString *oversize in @[tooManyBytes, [atByteLimit stringByAppendingString:@"a"], tooManyLines]) {
            NSDictionary *bad = @{@"id": @99, field: oversize, @"instrumental": @YES};
            CHECK(!SGLrcLibRecordResult(bad));
            reply = @[bad, near];
            found = searchAnswer(@"Song", @"Singer", 200);
            CHECK(found.count == 1 && [found[0][@"id"] isEqual:@2]);
            sg_answer = ^id(NSURL *url, id body) { CHECK([url.path isEqualToString:@"/api/get/99"]); return bad; };
            SGLyricsResult *oversizedPin = awaitReply(^(void (^done)(id)) { SGLrcLibGetID(@99, done); }, nil);
            CHECK(!oversizedPin);
            sg_answer = ^id(NSURL *url, id body) { return reply; };
        }
    }
    reply = nil;
    found = searchAnswer(@"Song", @"Singer", 200);
    CHECK(found && !found.count);
    found = searchAnswer(@"", @"", 200);
    CHECK(found && !found.count);
    found = awaitReply(^(void (^done)(id)) {
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            SGLrcLibSearch(@"Song", @"Singer", 200, done);
        });
    }, nil);
    CHECK(found && !found.count);
    sg_answer = ^id(NSURL *url, id body) { CHECK([url.path isEqualToString:@"/api/get/2"]); return near; };
    SGLyricsResult *got = awaitReply(^(void (^done)(id)) { SGLrcLibGetID(@2, done); }, nil);
    CHECK(got.karaokeLines.count == 1 && [got.provider isEqualToString:@"LRCLIB"]);
    printf("LRCLIB: bounded transport, 100-record input/20-result output, 256 KiB/4000-line caps, ranking and pinned lookup passed\n");
}

// LRCLIB decodes and builds every result off main and answers back on it, so this runs the main queue
// until the answer comes. answeredAtOnce says whether it came before the ask returned.
static SGLyricsResult *lrclibAnswer(SGLyricsQuery *query, BOOL *answeredAtOnce) {
    return awaitReply(^(void (^done)(id)) { SGLrcLibAsk(query, done); }, answeredAtOnce);
}

static SGLyricsResult *sourceAnswer(SGLyricsAsk ask, SGLyricsQuery *query) {
    return awaitReply(^(void (^done)(id)) { ask(query, done); }, nil);
}

static NSString *qqPayload(NSString *text, BOOL zipped) {
    NSData *data = [text dataUsingEncoding:NSUTF8StringEncoding];
    if (zipped) {
        uLongf size = compressBound(data.length);
        NSMutableData *compressed = [NSMutableData dataWithLength:size];
        CHECK(compress(compressed.mutableBytes, &size, data.bytes, data.length) == Z_OK);
        compressed.length = size;
        data = compressed;
    }
    return [data base64EncodedStringWithOptions:0];
}

static void checkQQWordsAndArtists(void) {
    // Invented text, unequal absolute millisecond clocks, and a gap that must not be interpolated.
    NSString *qrc = @"<QrcInfos><LyricInfo><Lyric_1 LyricContent=\"[ar:Fixture]\n"
        "[1234,2000]Sun(1234,111)rise (1345,222)&amp; (1700,50)go(2000,333)\n"
        "[5000,700]你(5000,123)好(5500,200)\"/></LyricInfo></QrcInfos>";
    for (NSNumber *zipped in @[@NO, @YES]) {
        SGLyricsResult *result = SGQQMusicResult(qqPayload(qrc, zipped.boolValue));
        CHECK(result.wordTimed && result.synced && result.karaokeLines.count == 2);
        SGKaraokeLine *line = result.karaokeLines[0];
        CHECK(line.start == 1234 && line.end == 3234 && line.timing == SGKaraokeTimingWords);
        CHECK(line.words.count == 3 && [SGKaraokeLineText(line) isEqual:@"Sunrise & go"]);
        CHECK(line.words[0].start == 1234 && line.words[0].end == 1567);
        CHECK(line.words[1].start == 1700 && line.words[1].end == 1750);
        CHECK(line.words[2].start == 2000 && line.words[2].end == 2333);
        line = result.karaokeLines[1];
        CHECK([SGKaraokeLineText(line) isEqual:@"你好"] && line.words.count == 2 && line.words[1].joined);
        CHECK(line.words[0].start == 5000 && line.words[0].end == 5123);
        CHECK(line.words[1].start == 5500 && line.words[1].end == 5700);
    }
    for (NSString *bad in @[@"", @"not base64!", @"eJw=", @"////"]) CHECK(!SGQQMusicResult(bad));
    CHECK(!SGQQMusicResult(@42));
    for (NSString *bad in @[
        @"<q LyricContent=\"[100,20]word(100,999999999999999999999999999999999999)\"/>",
        @"<q LyricContent=\"[100,20]word(-1,20)\"/>",
        @"<q LyricContent=\"[100,20]word(100,20)tail\"/>",
        @"<q LyricContent=\"[100,20]a(110,5)b(105,5)\"/>",
        @"<q LyricContent=\"[86400000,1]a(86400000,1)\"/>",
        @"<q LyricContent=\"[100,20]a(100,20)\n[120,20]broken\"/>",
        @"<q LyricContent=\"[100,20]&unknown;(100,20)\"/>",
        @"<q LyricContent=\"[100,20]a(100,20)"
    ]) CHECK(!SGQQMusicResult(qqPayload(bad, YES)));
    NSString *large = [@"x" stringByPaddingToLength:(1 << 20) + 1 withString:@"x" startingAtIndex:0];
    CHECK(!SGQQMusicResult(qqPayload(large, YES)));
    CHECK(!SGQQMusicResult(qqPayload(large, NO)));
    NSString *envelope = @"<q LyricContent=\"[by:]\n[100,20]a(100,20)\"/>";
    NSString *padding = [@"x" stringByPaddingToLength:(1 << 20) - envelope.length withString:@"x" startingAtIndex:0];
    NSString *atLimit = [envelope stringByReplacingOccurrencesOfString:@"[by:]" withString:
        [NSString stringWithFormat:@"[by:%@]", padding]];
    CHECK(SGQQMusicResult(qqPayload(atLimit, YES)).karaokeLines[0].words[0].end == 120);
    CHECK(!SGQQMusicResult(qqPayload([atLimit stringByAppendingString:@" "], YES)));
    SGLyricsResult *lrc = SGQQMusicResult(qqPayload(@"[00:01.234]plain\n[00:03.456]next", NO));
    CHECK(lrc.synced && !lrc.wordTimed && lrc.karaokeLines[0].start == 1234 && lrc.karaokeLines[1].start == 3456);
    CHECK(lrc.karaokeLines[0].timing != SGKaraokeTimingWords);
    CHECK(!SGLyricsSameArtist(@"MIURA", @"IU") && !SGLyricsSameArtist(@"IU", @"MIURA"));
    CHECK(SGLyricsSameArtist(@"IU", @"IU"));
    CHECK(SGLyricsSameArtist(@"IU (아이유)", @"IU")); // explicit prefix alias
    CHECK(SGLyricsSameArtist(@"아이유 (IU)", @"IU")); // explicit suffix alias
    CHECK(SGLyricsSameArtist(@"Other & IU & Guest", @"IU")); // middle credit
    CHECK(SGLyricsSameArtist(@"Other & IU (아이유) & Guest", @"IU")); // alias within a middle credit
    CHECK(SGLyricsSameArtist(@"방탄소년단 (BTS)", @"BTS"));
    CHECK(!SGLyricsSameArtist(@"xIUx", @"IU"));

    SGLyricsQuery *query = [SGLyricsQuery new];
    query.title = @"Fixture";
    query.artist = @"IU";
    query.seconds = 200;
    __block NSUInteger lyricRequests = 0;
    __block BOOL fallback = NO;
    __block NSString *fallbackPayload = @"invalid";
    sg_answer = ^id(NSURL *url, NSDictionary *body) {
        CHECK(NSThread.isMainThread);
        if (body[@"req"]) return @{@"req": @{@"data": @{@"body": @{@"song": @{@"list": @[
            @{@"id": @1, @"title": @"Fixture", @"interval": @200, @"singer": @[@{@"name": @"MIURA"}]},
            @{@"id": @2, @"title": @"Fixture", @"interval": @200, @"singer": @[@{@"name": @"IU"}]}
        ]}}}}};
        NSDictionary *params = body[@"music.musichallSong.PlayLyricInfo.GetPlayLyricInfo"][@"param"];
        CHECK([params[@"songID"] isEqual:@2] && [params[@"crypt"] isEqual:@0]);
        lyricRequests++;
        NSString *payload = fallback ? ([params[@"qrc"] boolValue] ? fallbackPayload :
            qqPayload(@"[00:01.234]fallback", NO)) : qqPayload(qrc, YES);
        return @{@"music.musichallSong.PlayLyricInfo.GetPlayLyricInfo": @{@"data": @{@"lyric": payload}}};
    };
    CHECK(sourceAnswer(SGQQMusicAsk, query).wordTimed && lyricRequests == 1);
    fallback = YES;
    lyricRequests = 0;
    SGLyricsResult *answer = sourceAnswer(SGQQMusicAsk, query);
    CHECK(answer.synced && !answer.wordTimed && lyricRequests == 2);
    CHECK(answer.karaokeLines[0].start == 1234 && [SGKaraokeLineText(answer.karaokeLines[0]) isEqual:@"fallback"]);
    // A bad clock beside a good one must reject the QRC, not become part of a genuinely timed word.
    for (NSString *row in @[
        @"[100,40]bad(-1,10)good(100,20)",
        @"[100,40]good(100,20)bad(120,-10)",
        @"[100,40]good(100,10)bad(+110,10)good(120,20)",
        @"[100,40]bad(100.5,10)good(120,20)",
        @"[100,40]bad(100,NaN)good(120,20)",
        @"[100,40]bad(,10)good(120,20)",
        @"[100,40]bad(100,10,0)good(120,20)"
    ]) {
        fallbackPayload = qqPayload([NSString stringWithFormat:@"<q LyricContent=\"%@\"/>", row], YES);
        SGLyricsResult *mixed = sourceAnswer(SGQQMusicAsk, query);
        CHECK(mixed.synced && !mixed.wordTimed);
        CHECK(mixed.karaokeLines[0].start == 1234 && [SGKaraokeLineText(mixed.karaokeLines[0]) isEqual:@"fallback"]);
    }
    sg_answer = ^id(NSURL *url, id body) {
        if ([url.host isEqual:@"krcs.kugou.com"]) return @{@"candidates": @[
            @{@"id": @"wrong", @"accesskey": @"k", @"song": @"Fixture", @"singer": @"MIURA", @"duration": @200000},
            @{@"id": @"right", @"accesskey": @"k", @"song": @"Fixture", @"singer": @"IU", @"duration": @200000}
        ]};
        CHECK([url.query containsString:@"id=right"]);
        return @{@"status": @404};
    };
    CHECK(!sourceAnswer(SGKuGouAsk, query));
}

static NSString *param(NSURL *url, NSString *name) {
    for (NSURLQueryItem *item in [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO].queryItems) {
        if ([item.name isEqualToString:name]) return item.value;
    }
    return nil;
}

static NSArray<SGKaraokeWord *> *piecesOf(NSString *text) {
    return SGKaraokeStaticLines(@[text]).firstObject.words;
}

// The words of an unspaced token come back flush, so the line reads as it was written.
static void checkSplit(NSString *text, BOOL split) {
    NSArray<SGKaraokeWord *> *words = piecesOf(text);
    printf("%lu pieces: %s\n", (unsigned long)words.count, [[words valueForKey:@"text"] componentsJoinedByString:@"|"].UTF8String);
    CHECK([SGKaraokeLineText(SGKaraokeStaticLines(@[text]).firstObject) isEqualToString:text]);
    CHECK(!split || words.count > 1);
}

// KRC as KuGou packs it: "krc1", then the zlib of the text XORed with the key, all in base64.
static NSString *packed(NSString *krc, NSString *magic) {
    NSData *text = [krc dataUsingEncoding:NSUTF8StringEncoding];
    uLongf length = compressBound(text.length);
    NSMutableData *zipped = [NSMutableData dataWithLength:length];
    compress(zipped.mutableBytes, &length, text.bytes, text.length);
    zipped.length = length;
    static const uint8_t key[16] = {64, 71, 97, 119, 94, 50, 116, 71, 81, 54, 49, 45, 206, 210, 110, 105};
    uint8_t *bytes = zipped.mutableBytes;
    for (NSUInteger i = 0; i < zipped.length; i++) bytes[i] ^= key[i % 16];
    NSMutableData *all = [[magic dataUsingEncoding:NSASCIIStringEncoding] mutableCopy];
    [all appendData:zipped];
    return [all base64EncodedStringWithOptions:0];
}

static NSString *const kKRC = @"﻿[id:$00000000]\r\n[ar:Someone]\r\n"
    "[1000,2000]<0,500,0>Hel<500,300,0>lo <800,700,0>world\r\n"
    "[4000,1500]<0,400,0>你<400,400,0>好<800,0,0>啊\r\n"
    "[7000,100]<0,300,0>late\r\n";

// Every line's words read back as its text, the spaces aside, and start in order inside it.
static void checkWordLines(NSArray<SGKaraokeLine *> *lines) {
    for (SGKaraokeLine *line in lines) {
        CHECK(line.timing != SGKaraokeTimingWords || line.words.count);
        for (NSUInteger i = 0; i < line.words.count; i++) {
            CHECK(line.words[i].start >= line.start && line.words[i].end > line.words[i].start && line.words[i].end <= line.end);
            CHECK(!i || line.words[i].start >= line.words[i - 1].start);
        }
    }
}

static void checkLive(NSString *path) {
    NSDictionary *root = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:path] options:0 error:nil];
    if (root[@"lyricsfile"]) {
        // An LRCLIB record: one that times words reads as word timed lines with the text it had.
        NSArray<SGKaraokeLine *> *lines = SGLyricsfileLines(root[@"lyricsfile"]);
        NSUInteger words = 0, timed = 0;
        NSInteger startSum = 0;
        for (SGKaraokeLine *line in lines) {
            words += line.words.count;
            timed += line.timing == SGKaraokeTimingWords;
            startSum += line.start;
        }
        printf("%s: Lyricsfile, %lu lines (%lu word timed), %lu words, starts sum %ld\n", path.lastPathComponent.UTF8String,
               (unsigned long)lines.count, (unsigned long)timed, (unsigned long)words, (long)startSum);
        CHECK(!!lines == [root[@"hasWordSync"] boolValue]);
        checkWordLines(lines);
        return;
    }
    if (root[@"content"]) {
        NSArray<SGKaraokeLine *> *lines = SGKuGouLines(root[@"content"]);
        printf("%s: KRC, %lu word timed lines; first \"%s\" at %ld\n", path.lastPathComponent.UTF8String, (unsigned long)lines.count,
               SGKaraokeLineText(lines.firstObject).UTF8String, (long)lines.firstObject.start);
        CHECK(lines.count);
        return;
    }
    id lyric = root[@"music.musichallSong.PlayLyricInfo.GetPlayLyricInfo"][@"data"][@"lyric"];
    SGLyricsResult *result = SGQQMusicResult(lyric);
    printf("%s: QQ %s, %lu timed lines\n", path.lastPathComponent.UTF8String, result.wordTimed ? "QRC" : "LRC",
           (unsigned long)result.karaokeLines.count);
    CHECK(result.synced && result.karaokeLines.count);
}

static id deezerBody(NSDictionary *lyrics) { return @{@"data": @{@"track": @{@"lyrics": lyrics}}}; }

static void checkMalformedPayloads(void) {
    for (NSNumber *qq in @[@YES, @NO]) for (id payload in @[@"!invalid-base64!", @""]) {
        SGLyricsQuery *query = [SGLyricsQuery new];
        query.title = @"Fixture"; query.artist = @"Singer"; query.seconds = 200;
        query.requestContext = [SGLyricsRequestContext new];
        sg_answer = ^id(NSURL *url, NSDictionary *body) {
            if (qq.boolValue) {
                if (body[@"req"]) return @{@"req": @{@"data": @{@"body": @{@"song": @{@"list": @[
                    @{@"id": @1, @"title": @"Fixture", @"interval": @200, @"singer": @[@{@"name": @"Singer"}]}]}}}}};
                return @{@"music.musichallSong.PlayLyricInfo.GetPlayLyricInfo": @{@"data": @{@"lyric": payload}}};
            }
            if ([url.host isEqual:@"krcs.kugou.com"]) return @{@"status": @200, @"candidates": @[
                @{@"id": @"1", @"accesskey": @"k", @"song": @"Fixture", @"singer": @"Singer", @"duration": @200000}]};
            return @{@"status": @200, @"content": payload};
        };
        CHECK(!sourceAnswer(qq.boolValue ? SGQQMusicAsk : SGKuGouAsk, query));
        CHECK(query.requestContext.failed == ([payload length] != 0));
    }
    puts("decoder rejection: malformed QRC/KRC fails; empty content remains a miss");
}

static void checkNewSources(void) {
    SGLyricsResult *result = SGBugsResult(@{@"lyrics": @"0.3005|Made up＃8.9|Another line＃"}, YES);
    CHECK(result.synced && result.karaokeLines.firstObject.start == 301 && result.karaokeLines[1].start == 8900);
    CHECK([result.provider isEqualToString:@"Bugs"]);
    CHECK(!SGBugsResult(@{@"lyrics": @"20|Later＃1|Earlier"}, YES));
    CHECK(!SGBugsResult(@{@"lyrics": @"bad＃nope＃1|Only one"}, YES));
    CHECK(!SGBugsResult(@{@"lyrics": @"nan|Bad＃inf|Bad＃-2|Bad"}, YES));
    CHECK(SGBugsResult(@{@"lyrics": @"bad＃1|Half"}, YES).synced);
    result = SGBugsResult(@{@"lyrics": @"Made up\r\nAnother line"}, NO);
    CHECK(!result.synced && result.texts.count == 2 && [result.starts isEqual:(@[@0, @0])]);

    result = SGGenieResult(@"null({\"8700\":\"Later\",\"0\":\"First\"});");
    CHECK(result.synced && result.karaokeLines[1].start == 8700 && [result.provider isEqualToString:@"Genie"]);
    CHECK(!SGGenieResult(@"null({\"oops\":\"No\"})"));
    CHECK(!SGGenieResult(@"null({\"0\":null})") && !SGGenieResult(@"null({\"1.2\":\"No\"})"));
    CHECK(!SGGenieResult(@"null({\"99999999999999999999\":\"No\"})"));
    CHECK(!SGGenieResult(@"null([1,2])") && !SGGenieResult(@"broken"));

    NSDictionary *plus = @{@"type": @"Syllable", @"metadata": @{@"source": @"Made-up catalog"}, @"lyrics": @[
        @{@"time": @1000, @"duration": @2000, @"text": @"Hello world", @"element": @{@"singer": @"v1"}, @"syllabus": @[
            @{@"time": @1000, @"duration": @200, @"text": @"Hel"},
            @{@"time": @1200, @"duration": @300, @"text": @"lo "},
            @{@"time": @1500, @"duration": @500, @"text": @"world"},
            @{@"time": @1700, @"duration": @200, @"text": @"oh", @"isBackground": @YES},
        ]} ]};
    result = SGLyricsPlusResult(plus);
    CHECK(result.wordTimed && result.karaokeLines.firstObject.timing == SGKaraokeTimingWords);
    CHECK([SGKaraokeLineText(result.karaokeLines.firstObject) isEqualToString:@"Hello world"]);
    CHECK(result.karaokeLines.firstObject.words[1].joined && !result.karaokeLines.firstObject.words[2].joined);
    CHECK(result.karaokeLines.firstObject.backing.start == 1700 && [result.provider isEqualToString:@"LyricsPlus · Made-up catalog"]);
    NSMutableDictionary *wordPlus = [plus mutableCopy];
    wordPlus[@"type"] = @"Word";
    CHECK(SGLyricsPlusResult(wordPlus).wordTimed);
    NSDictionary *linePlus = @{@"type": @"Line", @"metadata": @{@"source": @42}, @"lyrics": @[
        @{@"time": @5000, @"duration": @1000, @"text": @"Second"}, @{@"time": @1000, @"duration": @1000, @"text": @"First"}]};
    result = SGLyricsPlusResult(linePlus);
    CHECK(result.synced && !result.wordTimed && result.karaokeLines.firstObject.start == 1000 && [result.provider isEqualToString:@"LyricsPlus"]);
    CHECK(!SGLyricsPlusResult(@{@"type": @"Word", @"lyrics": @[@{@"time": @0, @"duration": @1, @"text": @"x", @"syllabus": @[@{@"text": @"x", @"time": @"nan", @"duration": @1}]}]}));
    CHECK(!SGLyricsPlusResult(@{@"type": @"Line", @"lyrics": @[@{@"time": @YES, @"duration": @1, @"text": @"x"}]}));

    NSDictionary *deezer = deezerBody(@{@"text": @"Fallback", @"synchronizedLines": @[@{@"milliseconds": @9999, @"line": @"Fallback line"}], @"synchronizedWordByWordLines": @[
        @{@"start": @1000, @"end": @2400, @"words": @[@{@"start": @1000, @"end": @1500, @"word": @"Made"}, @{@"start": @1600, @"end": @2300, @"word": @"up"}]}]});
    result = SGDeezerResult(deezer);
    CHECK(result.wordTimed && result.karaokeLines.firstObject.words[1].start == 1600 && [result.provider isEqualToString:@"Deezer"]);
    CHECK([SGKaraokeLineText(result.karaokeLines.firstObject) isEqualToString:@"Made up"]);
    result = SGDeezerResult(deezerBody(@{@"synchronizedWordByWordLines": @[@{@"start": @1, @"end": @0}], @"synchronizedLines": @[@{@"milliseconds": @8700, @"line": @"Later"}, @{@"milliseconds": @0, @"line": @"First"}]}));
    CHECK(result.synced && !result.wordTimed && result.karaokeLines[1].start == 8700);
    result = SGDeezerResult(deezerBody(@{@"text": @"Plain\r\nMade up", @"synchronizedLines": NSNull.null}));
    CHECK(!result.synced && result.texts.count == 2);
    for (id odd in @[NSNull.null, @42, @YES, @"error", @[], @{}]) {
        CHECK(!SGBugsResult(odd, YES) && !SGBugsResult(odd, NO));
        CHECK(!SGGenieResult(odd) && !SGLyricsPlusResult(odd) && !SGDeezerResult(odd));
        CHECK(!SGLyricsPlusResult(@{@"type": @"Word", @"lyrics": @[odd]}));
        CHECK(!SGDeezerResult(deezerBody(@{@"synchronizedWordByWordLines": @[odd], @"synchronizedLines": @[odd], @"text": NSNull.null})));
    }
    NSString *huge = [@"x" stringByPaddingToLength:262145 withString:@"x" startingAtIndex:0];
    CHECK(!SGBugsResult(@{@"lyrics": huge}, NO) && !SGGenieResult(huge));
    CHECK(!SGLyricsPlusResult(@{@"type": @"Line", @"lyrics": @[@{@"time": @0, @"duration": @1, @"text": huge}]}));

    SGLyricsQuery *query = [SGLyricsQuery new];
    query.title = @"Made up"; query.artist = @"Singer feat. Guest"; query.seconds = 200;
    __block NSUInteger calls = 0, plain = 0;
    __block SGLyricsResult *got;
    sg_sourceAnswer = ^id(NSURL *url, NSDictionary *headers, NSData *body, NSInteger *status) {
        if ([url.host isEqualToString:@"m.bugs.co.kr"]) return @{@"list": @[
            @{@"track_id": @1, @"track_title": @"Other", @"artists": @[@{@"artist_nm": @"Singer"}]},
            @{@"track_id": @2, @"track_title": @"Made up", @"artists": @[@{@"artist_nm": @"Other"}]},
            @{@"track_id": @3, @"track_title": @"Made up", @"len": @"03:25", @"artists": @[@{@"artist_nm": @"Singer"}]},
            @{@"track_id": @4, @"track_title": @"Made up", @"len": @"03:24", @"mvs": @[@{@"len": @"00:10"}], @"artists": @[@{@"artist_nm": @"Singer"}]}]};
        CHECK([url.path hasSuffix:@"/4"]);
        if ([url.path containsString:@"/T/"]) return @{@"lyrics": @"invalid"};
        plain++; return @{@"lyrics": @"Made up words"};
    };
    SGBugsAsk(query, ^(SGLyricsResult *r) { CHECK(NSThread.isMainThread); got = r; calls++; });
    CHECK(calls == 1 && plain == 1 && got && !got.synced);
    __block NSUInteger genieRequests = 0;
    sg_sourceAnswer = ^id(NSURL *url, NSDictionary *headers, NSData *body, NSInteger *status) {
        genieRequests++;
        if ([headers[@"User-Agent"] containsString:@"iPhone"]) { *status = 302; return nil; }
        CHECK([headers[@"User-Agent"] containsString:@"Macintosh"]);
        if ([url.host isEqualToString:@"www.genie.co.kr"]) return @"<tr class='list' songid='1'><a class='title ellipsis' title='Made up'>x</a></tr>"
            "<tr class='list' songid='2'><a class='title ellipsis' title='Other'>x</a><a class='artist ellipsis'>Singer</a></tr>"
            "<tr class='list' songid='3'><a class='title ellipsis' title='Made&#32;up'>x</a><a class='artist ellipsis'><span>Singer</span></a></tr>";
        CHECK([param(url, @"songid") isEqualToString:@"3"] && [headers[@"Referer"] isEqualToString:@"https://www.genie.co.kr/"]);
        return @"null({\"8700\":\"Made up\"})";
    };
    got = sourceAnswer(SGGenieAsk, query);
    CHECK(genieRequests == 2 && got.synced && got.karaokeLines.firstObject.start == 8700);
    __block NSUInteger plusRequests = 0;
    sg_sourceAnswer = ^id(NSURL *url, NSDictionary *headers, NSData *body, NSInteger *status) {
        CHECK([param(url, @"duration") isEqualToString:@"200.000"]);
        plusRequests++;
        if ([url.host isEqualToString:@"lyricsplus.prjktla.my.id"]) { *status = 503; return nil; }
        CHECK([url.host isEqualToString:@"lyricsplus.binimum.org"]); return plus;
    };
    got = sourceAnswer(SGLyricsPlusAsk, query);
    CHECK(plusRequests == 2 && got.wordTimed);
    plusRequests = 0;
    sg_sourceAnswer = ^id(NSURL *url, NSDictionary *headers, NSData *body, NSInteger *status) {
        plusRequests++; CHECK([url.host isEqualToString:@"lyricsplus.prjktla.my.id"]); return plus;
    };
    got = sourceAnswer(SGLyricsPlusAsk, query);
    CHECK(plusRequests == 1 && got.wordTimed);

    __block NSUInteger logins = 0, lyricsRequests = 0;
    __block BOOL refuse = YES;
    sg_sourceAnswer = ^id(NSURL *url, NSDictionary *headers, NSData *body, NSInteger *status) {
        if ([url.host isEqualToString:@"api.deezer.com"]) {
            CHECK(!headers[@"Cookie"] && !headers[@"Authorization"] && !body);
            return @{@"data": @[
                @{@"id": @1, @"title": @"Other", @"artist": @{@"name": @"Singer"}},
                @{@"id": @2, @"title": @"Made up", @"artist": @{@"name": @"Other"}},
                @{@"id": @3, @"title": @"Made up", @"duration": @205, @"artist": @{@"name": @"Singer"}},
                @{@"id": @4, @"title": @"Made up", @"duration": @204, @"artist": @{@"name": @"Singer"}}]};
        }
        if ([url.host isEqualToString:@"auth.deezer.com"]) {
            CHECK([headers[@"Cookie"] isEqualToString:@"arl=made-up-cookie"] && body && !body.length);
            logins++; return @{@"jwt": [NSString stringWithFormat:@"fake.token.%lu", (unsigned long)logins]};
        }
        CHECK([url.host isEqualToString:@"pipe.deezer.com"] && !headers[@"Cookie"] && headers[@"Authorization"]);
        NSDictionary *request = [NSJSONSerialization JSONObjectWithData:body options:0 error:nil];
        CHECK([request[@"variables"][@"trackId"] isEqualToString:@"4"]);
        lyricsRequests++;
        if (refuse) return @{@"errors": @[@{@"message": @"Jwt token is missing", @"type": @"JwtTokenMissingError",
            @"path": @[@"track"], @"extensions": @{@"type": @"JwtTokenMissingError"}}], @"data": @{@"track": NSNull.null}};
        return deezer;
    };
    calls = 0; NSUInteger requests = sg_sourceRequests;
    SGDeezerAskWith(nil, query, ^(SGLyricsResult *r) { got = r; calls++; });
    CHECK(calls == 1 && !got && sg_sourceRequests == requests);
    SGDeezerAskWith(@"bad;cookie", query, ^(SGLyricsResult *r) { CHECK(!r); });
    CHECK(sg_sourceRequests == requests);
    calls = 0;
    SGDeezerAskWith(@"made-up-cookie", query, ^(SGLyricsResult *r) { got = r; calls++; });
    CHECK(calls == 1 && !got && logins == 2 && lyricsRequests == 2);
    refuse = NO;
    query.requestContext = [SGLyricsRequestContext new];
    SGDeezerAskWith(@"made-up-cookie", query, ^(SGLyricsResult *r) { got = r; });
    CHECK(!got && query.requestContext.failed);
    SGDeezerForgetKey();
    SGDeezerAskWith(@"made-up-cookie", query, ^(SGLyricsResult *r) { got = r; });
    CHECK(got.wordTimed && logins == 3);
    SGDeezerAskWith(@"made-up-cookie", query, ^(SGLyricsResult *r) { got = r; });
    CHECK(got.wordTimed && logins == 3 && lyricsRequests == 4);

    id (^healthyDeezer)(NSURL *, NSDictionary *, NSData *, NSInteger *) = sg_sourceAnswer;
    sg_sourceAnswer = ^id(NSURL *url, NSDictionary *headers, NSData *body, NSInteger *status) {
        if ([url.host isEqual:@"pipe.deezer.com"]) return @{@"data": @{@"track": NSNull.null}};
        return healthyDeezer(url, headers, body, status);
    };
    query.requestContext = [SGLyricsRequestContext new];
    SGDeezerAskWith(@"made-up-cookie", query, ^(SGLyricsResult *r) { got = r; });
    CHECK(!got && query.requestContext.failed);
    sg_sourceAnswer = healthyDeezer;

    // An HTTP auth failure refreshes once and still answers the original ask only once.
    id (^previousAnswer)(NSURL *, NSDictionary *, NSData *, NSInteger *) = sg_sourceAnswer;
    __block BOOL expired = YES;
    sg_sourceAnswer = ^id(NSURL *url, NSDictionary *headers, NSData *body, NSInteger *status) {
        if (expired && [url.host isEqualToString:@"pipe.deezer.com"]) { expired = NO; *status = 401; return nil; }
        if ([url.host isEqualToString:@"api.deezer.com"]) CHECK([param(url, @"q") isEqualToString:@"track:\"Made up\" artist:\"Singer\""]);
        return previousAnswer(url, headers, body, status);
    };
    query.title = @"\"Made up\"";
    calls = 0;
    SGDeezerAskWith(@"made-up-cookie", query, ^(SGLyricsResult *r) { got = r; calls++; });
    CHECK(calls == 1 && got.wordTimed && logins == 4);

    // Every source also completes its early miss on main when called from a worker queue.
    __block NSUInteger finished = 0;
    SGLyricsQuery *empty = [SGLyricsQuery new];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
        void (^done)(SGLyricsResult *) = ^(SGLyricsResult *r) { CHECK(NSThread.isMainThread && !r); finished++; };
        SGBugsAsk(empty, done);
        SGGenieAsk(empty, done);
        SGLyricsPlusAsk(empty, done);
        SGDeezerAskWith(nil, empty, done);
    });
    NSDate *until = [NSDate dateWithTimeIntervalSinceNow:2];
    while (finished < 4 && until.timeIntervalSinceNow > 0) [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    CHECK(finished == 4);
    printf("Bugs, Genie, LyricsPlus, Deezer: parser, matching, fallback, auth and main-queue checks passed\n");
}

static void checkLanguagesAndTitles(void) {
    NSDictionary *titles = @{
        @"Song (feat. Singer)": @"Song", @"Song [Live]": @"Song", @"노래 【라이브】": @"노래",
        @"노래 （리마스터）": @"노래", @"Song - 2020 Remastered": @"Song", @"노래 - 리마스터": @"노래",
        @"노래 - 라이브": @"노래", @"Song (Live) [Deluxe] - Radio Edit": @"Song",
        @"Song - Acoustic ver.": @"Song", @"Song - with Singer": @"Song", @"Song - ft. Singer": @"Song",
        @"Song (Live (London))": @"Song", @"Love (Is All) Around": @"Love (Is All) Around",
        @"Love (Is All)": @"Love", @"(Live)": @"(Live)", @"Song - Forever": @"Song - Forever", @"  Song  ": @"  Song  ",
        @"Song - Lively": @"Song - Lively", @"Song (Live]": @"Song (Live]", @"": @""
    };
    for (NSString *title in titles) CHECK([SGLyricsSimplifiedTitle(title) isEqual:titles[title]]);
    CHECK(!SGLyricsSimplifiedTitle(nil));
    NSArray *rubyCases = @[
        @[@"東京の空", @[@[@"東京", @"とうきょう"], @[@"空", @"そら"]]],
        @[@"君の名前を呼ぶ", @[@[@"君", @"きみ"], @[@"名前", @"なまえ"], @[@"呼", @"よ"]]],
        @[@"食べる", @[@[@"食", @"た"]]], @[@"ひらがなだけ", @[]], @[@"Only Latin", @[]],
        @[@"🌙東京の空", @[@[@"東京", @"とうきょう"], @[@"空", @"そら"]]]
    ];
    for (NSArray *test in rubyCases) {
        NSString *text = test[0]; NSArray *expected = test[1];
        NSArray<SGLyricsRuby *> *runs = SGLyricsFurigana(text);
        CHECK(runs.count == expected.count);
        for (NSUInteger i = 0; i < runs.count; i++) {
            CHECK([[text substringWithRange:runs[i].range] isEqual:expected[i][0]]);
            CHECK([runs[i].reading isEqual:expected[i][1]]);
        }
        CHECK(SGLyricsFurigana(text) == runs);
    }
    dispatch_apply(100, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^(size_t i) {
        CHECK([SGLyricsFurigana(@"東京の空").firstObject.reading isEqual:@"とうきょう"]);
    });
    NSDictionary *songs = @{
        @"ja": @[@"明日の空を見上げて歩く", @"夜が明けるまで歌おう"],
        @"ko": @[@"오늘도 너의 마음을 바라보며 조용히 걸어간다", @"내일의 햇살이 우리에게 다시 찾아올 거야"],
        @"en": @[@"I walk beside the river while the morning light is shining", @"We will find our way together through the quiet streets tonight"],
        @"es": @[@"Quiero caminar contigo por las calles de nuestra ciudad", @"Esta noche las estrellas brillan sobre nuestros corazones"]
    };
    for (NSString *language in songs) {
        NSArray *lines = SGKaraokeStaticLines(songs[language]);
        CHECK([SGLyricsDetectedLanguage(lines) isEqual:language]);
        CHECK([SGLyricsDetectedLanguage(lines) isEqual:language]);
    }
    CHECK(!SGLyricsDetectedLanguage(SGKaraokeStaticLines(@[@"123", @"♪"])));
    CHECK(!SGLyricsDetectedLanguage(SGKaraokeStaticLines(@[@"a"])));
    NSMutableArray *mixed = [songs[@"es"] mutableCopy];
    for (NSUInteger i = 0; i < 20; i++) [mixed addObject:@"I love you"];
    CHECK([SGLyricsDetectedLanguage(SGKaraokeStaticLines(mixed)) isEqual:@"es"]);
    CHECK([SGLyricsDetectedLanguage(SGKaraokeStaticLines(@[@"The morning light", @"かな"])) isEqual:@"ja"]);
    SGKaraokeLine *line = SGKaraokeStaticLines(@[@"A line"]).firstObject;
    line.note = @"A reference to the first day of spring";
    SGKaraokeLine *copy = [line copy];
    CHECK([copy.note isEqual:line.note]); copy.note = @"Changed"; CHECK(![copy.note isEqual:line.note]);
    printf("language: ja/ko/en/es, repeated lines, kana override and uncertainty passed; titles: %lu cases; furigana: 6 cases, UTF-16 and concurrent cache passed; note copy passed\n", (unsigned long)titles.count);
}

static void checkVoiceScaling(void) {
    for (NSNumber *size in @[@10000, @20000]) {
        NSMutableArray<SGKaraokeLine *> *lines = [NSMutableArray array];
        for (NSUInteger i = 0; i < size.unsignedIntegerValue; i++) {
            SGKaraokeLine *line = [SGKaraokeLine new];
            line.voice = [NSString stringWithFormat:@"voice-%lu", (unsigned long)i];
            line.backing = [SGKaraokeLine new];
            [lines addObject:line];
        }
        SGKaraokeLine *duplicate = [SGKaraokeLine new]; duplicate.voice = @"voice-0";
        [lines insertObject:duplicate atIndex:1];
        [lines insertObject:[SGKaraokeLine new] atIndex:2];
        NSTimeInterval began = NSProcessInfo.processInfo.systemUptime;
        SGKaraokeAlignVoices(lines);
        NSTimeInterval elapsed = NSProcessInfo.processInfo.systemUptime - began;
        for (SGKaraokeLine *line in lines) {
            SGKaraokeAlign expected = [line.voice isEqual:@"voice-1"] ? SGKaraokeAlignTrailing : SGKaraokeAlignLeading;
            CHECK(line.align == expected);
            if (line.backing) CHECK(line.backing.align == expected);
        }
        printf("voice scaling: %lu distinct agents, %.6fs\n", (unsigned long)size.unsignedIntegerValue, elapsed);
    }
}

static void checkDeezerKeychain(void) {
    SGDeezerForgetKey();
    SGLyricsQuery *query = [SGLyricsQuery new]; // No names: no network request, regardless of credential.
    for (NSUInteger i = 0; i < 10; i++) SGDeezerAsk(query, ^(SGLyricsResult *result) { CHECK(!result); });
    CHECK(sg_arlReads == 1 && !SGDeezerARLSet());
    SGDeezerForgetKey();
    sg_testARL = @"harness_arl";
    for (NSUInteger i = 0; i < 10; i++) SGDeezerAsk(query, ^(SGLyricsResult *result) { CHECK(!result); });
    CHECK(sg_arlReads == 2 && SGDeezerARLSet());
    SGDeezerForgetKey();
    CHECK(!SGDeezerARLSet() && sg_arlReads == 3);
    SGDeezerForgetKey();
    sg_testARL = @"unlocked_arl";
    sg_arlReadStatus = errSecInteractionNotAllowed;
    sg_replyFailure = nil;
    query.title = @"Song"; query.artist = @"Singer";
    SGDeezerAsk(query, ^(SGLyricsResult *result) { CHECK(!result); });
    CHECK([sg_replyFailure.domain isEqual:NSOSStatusErrorDomain] && sg_replyFailure.code == errSecInteractionNotAllowed);
    id (^saved)(NSURL *, NSDictionary *, NSData *, NSInteger *) = sg_sourceAnswer;
    sg_sourceAnswer = ^id(NSURL *url, NSDictionary *headers, NSData *body, NSInteger *status) {
        if ([url.host isEqual:@"api.deezer.com"])
            return @{@"data": @[@{@"id": @7, @"title": @"Song", @"artist": @{@"name": @"Singer"}}]};
        if ([url.host isEqual:@"auth.deezer.com"]) {
            CHECK([headers[@"Cookie"] isEqual:@"arl=unlocked_arl"]);
            return @{@"jwt": @"harness.jwt.signature"};
        }
        return deezerBody(@{@"text": @"Recovered after unlock"});
    };
    sg_arlReadStatus = errSecSuccess;
    __block SGLyricsResult *answer;
    SGDeezerAsk(query, ^(SGLyricsResult *result) { answer = result; });
    CHECK([SGKaraokeLineText(answer.karaokeLines.firstObject) isEqual:@"Recovered after unlock"]);
    CHECK(SGDeezerARLSet() && sg_arlReads == 5);
    sg_sourceAnswer = saved;
    puts("Deezer credentials: present/absent reads cached until credential invalidation");
}

static void checkMalformedTiming(void) {
    // The unpacked 100k-piece sheet is below KuGou's 1 MiB input bound.
    for (NSNumber *size in @[@25000, @100000]) {
        NSUInteger count = size.unsignedIntegerValue;
        NSMutableString *krc = [NSMutableString stringWithString:@"[0,1]"];
        for (NSUInteger i = 0; i < count; i++) [krc appendString:@"<0,1,0>a"];
        NSString *content = packed(krc, @"krc1");
        NSTimeInterval began = NSProcessInfo.processInfo.systemUptime;
        NSArray<SGKaraokeLine *> *joined = SGKuGouLines(content);
        NSTimeInterval elapsed = NSProcessInfo.processInfo.systemUptime - began;
        CHECK(joined.count == 1 && joined[0].words.count == 1);
        CHECK([joined[0].words[0].text isEqual:[@"" stringByPaddingToLength:count withString:@"a" startingAtIndex:0]]);
        printf("KRC scaling: %lu pieces, %.3fs, %.3fus/piece\n", (unsigned long)count, elapsed, elapsed * 1e6 / count);
    }
    for (id rows in @[NSNull.null, @"not rows", @{}, @[]]) {
        NSData *json = [NSJSONSerialization dataWithJSONObject:@{@"lyrics": @{@"syncType": @"LINE_SYNCED", @"lines": rows}} options:0 error:nil];
        CHECK(!SGKaraokeLinesFromBody(json));
    }
    for (id time in @[NSNull.null, @[], @{}, @YES, @(-1), @1.5, @86400001, @"9223372036854775807", @"12oops", @""]) {
        NSData *json = [NSJSONSerialization dataWithJSONObject:@{@"lyrics": @{@"syncType": @"LINE_SYNCED", @"lines": @[@{@"words": @"Hi", @"startTimeMs": time}]}} options:0 error:nil];
        CHECK(!SGKaraokeLinesFromBody(json));
    }
    CHECK(!SGKaraokeLinesFromBody([@"{\"lyrics\":{\"syncType\":\"LINE_SYNCED\",\"lines\":[{\"words\":\"Hi\"}]}}" dataUsingEncoding:NSUTF8StringEncoding]));
    NSArray *plain = SGKaraokeLinesFromBody([@"{\"lyrics\":{\"syncType\":\"UNSYNCED\",\"lines\":[{\"words\":\"Hi\",\"startTimeMs\":null}]}}" dataUsingEncoding:NSUTF8StringEncoding]);
    CHECK([SGKaraokeLineText(plain.firstObject) isEqual:@"Hi"]);
    NSArray<SGKaraokeLine *> *timed = SGKaraokeLinesFromBody([@"{\"lyrics\":{\"syncType\":\"LINE_SYNCED\",\"lines\":[{\"words\":\"Hi\",\"startTimeMs\":\"1234\"}]}}" dataUsingEncoding:NSUTF8StringEncoding]);
    CHECK(timed.firstObject.start == 1234);

    // Unsorted and duplicate starts keep their original order. A break still limits the preceding line.
    timed = SGKaraokeEstimatedLines(@[@3000, @1000, @1000, @1500], @[@"Last", @"One", @"Two", @""]);
    CHECK([[timed valueForKey:@"start"] isEqual:(@[@3000, @1000, @1000])]);
    CHECK([[timed valueForKey:@"end"] isEqual:(@[@3650, @1500, @1500])]);
    NSMutableArray *starts = [NSMutableArray array], *texts = [NSMutableArray array];
    for (NSUInteger i = 0; i < 20000; i++) { [starts addObject:@0]; [texts addObject:@"Hi"]; }
    CHECK(SGKaraokeEstimatedLines(starts, texts).count == 20000);
    NSMutableString *repeated = [NSMutableString string];
    for (NSUInteger i = 0; i < 20000; i++) [repeated appendString:@"[00:00]"];
    [repeated appendString:@"Hi"];
    CHECK(!SGLyricsLRCResult(repeated));
    CHECK(SGLyricsLRCResult(@"[00:01][00:02]Hi").karaokeLines.count == 2);
    // The one stamp and its conversion to milliseconds the two LRC parsers share (LyricsSources.h): a
    // fraction of no digit, of one (tenths), of two (hundredths) and of three (thousandths).
    for (NSArray *each in @[@[@"[01:02]", @62000], @[@"[01:02.3]", @62300], @[@"[01:02.35]", @62350],
                            @[@"[101:02:345]", @6062345]]) {
        NSString *row = each[0];
        NSTextCheckingResult *match = [SGLyricsLRCStamp() firstMatchInString:row options:0 range:NSMakeRange(0, row.length)];
        CHECK(match && SGLyricsLRCStampMs(row, match) == [each[1] integerValue]);
    }
    CHECK(![SGLyricsLRCStamp() firstMatchInString:@"[ti:x]" options:0 range:NSMakeRange(0, 6)]);

    for (NSString *bad in @[
        @"[0,1000](9223372036854775807,1,0)Hi",
        @"[0,1000](0,9223372036854775807,0)Hi",
        @"[86400000,1](86400000,1,0)Hi",
        @"[1000,1000](999,1,0)Hi",
        @"[0,1000](100,1,0)Hi (50,1,0)there",
        @"[0,1000](0,-1,0)Hi",
        @"[0,1000](-1,1,0)Hi"]) CHECK(!SGLyricsPieceLines(bad, NO));
    CHECK(!SGLyricsPieceLines(@"[1000,1000]<86400000,1,0>Hi", YES));
    CHECK(!SGLyricsPieceLines(@"[0,1000]<9223372036854775807,1,0>Hi", YES));
    puts("timing: malformed JSON, expanded stamps, ordered estimation and bounded piece clocks passed");
}

static void checkTimingNames(void) {
    SGKaraokeLine *word = [SGKaraokeLine new], *line = [SGKaraokeLine new], *plain = [SGKaraokeLine new];
    word.timing = SGKaraokeTimingWords;
    line.timing = SGKaraokeTimingLine;
    plain.timing = SGKaraokeTimingNone;
    CHECK([SGKaraokeTimingName(@[plain, line, word]) isEqualToString:@"word timed"]);
    CHECK([SGKaraokeTimingName(@[plain, line]) isEqualToString:@"line timed"]);
    CHECK([SGKaraokeTimingName(@[plain]) isEqualToString:@"untimed"]);
    CHECK([SGKaraokeTimingName(@[]) isEqualToString:@"untimed"]);
    CHECK([SGKaraokeTimingName(nil) isEqualToString:@"untimed"]);
    puts("timing diagnostic: word, line, untimed, empty and nil names passed");
}

// Invented metadata and lyrics in the endpoint's XML/base64 WSY format; no captured user data.
static NSString *petitSong(NSString *identifier, NSString *title, NSString *artist, NSString *duration, NSString *type, NSString *text) {
    NSString *encoded = [[text dataUsingEncoding:NSUTF8StringEncoding] base64EncodedStringWithOptions:0];
    return [NSString stringWithFormat:@"<song><lyricsId>%@</lyricsId><title>%@</title><artist>%@</artist><duration>%@</duration><availableLyricsType>%@</availableLyricsType><lyricsType>%@</lyricsType><lyricsData>%@</lyricsData></song>",
        identifier, title, artist, duration, type, type, encoded];
}
static void checkPetitLyrics(void) {
    SGLyricsQuery *query = [SGLyricsQuery new];
    query.title = @"Fixture + Song";
    query.artist = @"Fixture Artist";
    query.seconds = 180;
    query.requestContext = [SGLyricsRequestContext new];
    NSString *wsy = @"<wsy><line><linestring>空 &amp; 海</linestring>"
        "<word><wordstring>空</wordstring><starttime>1200</starttime><endtime>1500</endtime></word>"
        "<word><wordstring>&amp;</wordstring><starttime>1700</starttime><endtime>1900</endtime></word>"
        "<word><wordstring>海</wordstring><starttime>2200</starttime><endtime>2900</endtime></word></line></wsy>";
    NSString *(^wrap)(NSString *) = ^(NSString *body) {
        return [NSString stringWithFormat:@"<response><status>00000000</status><songs>%@</songs></response>", body];
    };
    NSString *search = wrap([@[
        petitSong(@"1", @"Wrong Song", query.artist, @"180000", @"3", @""),
        petitSong(@"2", query.title, @"Wrong Artist", @"180000", @"3", @""),
        petitSong(@"3", query.title, query.artist, @"200000", @"3", @""),
        petitSong(@"4", query.title, query.artist, @"183000", @"3", @""),
        petitSong(@"5", query.title, query.artist, @"180000", @"3", @"")
    ] componentsJoinedByString:@""]);
    sg_sourceAnswer = ^id(NSURL *url, NSDictionary *headers, NSData *body, NSInteger *status) {
        CHECK([url.host isEqual:@"p1.petitlyrics.com"]);
        CHECK([headers[@"Content-Type"] isEqual:@"application/x-www-form-urlencoded"]);
        NSString *form = [[NSString alloc] initWithData:body encoding:NSUTF8StringEncoding];
        CHECK([form containsString:@"clientAppId=p1110417"] && [form containsString:@"terminalType=10"]);
        if ([form containsString:@"key_title="]) {
            CHECK([form containsString:@"key_title=Fixture%20%2B%20Song"] && [form containsString:@"max_count=30"]);
            return search;
        }
        CHECK([form containsString:@"key_lyricsId=5"] && [form containsString:@"lyricsType=3"]);
        return wrap(petitSong(@"5", query.title, query.artist, @"180000", @"3", wsy));
    };
    SGLyricsResult *got = awaitReply(^(void (^done)(id)) { SGPetitLyricsAsk(query, done); }, nil);
    CHECK(got.synced && got.wordTimed && [got.provider isEqual:@"PetitLyrics"]);
    SGKaraokeLine *line = got.karaokeLines.firstObject;
    CHECK([SGKaraokeLineText(line) isEqual:@"空 & 海"]);
    CHECK(line.start == 1200 && line.end == 2900 && line.words.count == 3);
    CHECK(line.words[1].start == 1700 && line.words[1].end == 1900);

    NSString *overlap = @"<wsy><line><linestring>空海</linestring>"
        "<word><wordstring>空</wordstring><starttime>1000</starttime><endtime>5000</endtime></word>"
        "<word><wordstring>海</wordstring><starttime>2000</starttime><endtime>3000</endtime></word></line></wsy>";
    sg_sourceAnswer = ^id(NSURL *url, NSDictionary *headers, NSData *body, NSInteger *status) {
        return wrap(petitSong(@"5", query.title, query.artist, @"180000", @"3", overlap));
    };
    got = awaitReply(^(void (^done)(id)) { SGPetitLyricsAsk(query, done); }, nil);
    CHECK(got.wordTimed && got.karaokeLines.firstObject.end == 5000);

    // Eevee requests type 1 for type 2 availability. Live type 2 is MHDROBJT
    // binary, not the fabricated LRC formerly used here. Plain text is never timed.
    for (NSString *available in @[@"1", @"2"]) {
        sg_sourceAnswer = ^id(NSURL *url, NSDictionary *headers, NSData *body, NSInteger *status) {
            NSString *form = [[NSString alloc] initWithData:body encoding:NSUTF8StringEncoding];
            if ([form containsString:@"key_title="])
                return wrap(petitSong(@"5", query.title, query.artist, @"180000", available, @""));
            CHECK([form containsString:@"lyricsType=1"]);
            return wrap(petitSong(@"5", query.title, query.artist, @"180000", @"1", @"Invented line\nNext line"));
        };
        got = awaitReply(^(void (^done)(id)) { SGPetitLyricsAsk(query, done); }, nil);
        CHECK(got && !got.synced && !got.wordTimed);
        CHECK([got.texts isEqual:(@[@"Invented line", @"Next line"])]);
    }

    sg_sourceAnswer = ^id(NSURL *url, NSDictionary *headers, NSData *body, NSInteger *status) {
        return wrap(petitSong(@"1", @"Unrelated", query.artist, @"180000", @"3", wsy));
    };
    CHECK(!awaitReply(^(void (^done)(id)) { SGPetitLyricsAsk(query, done); }, nil));
    CHECK(!query.requestContext.emptyNameSearch);
    sg_sourceAnswer = ^id(NSURL *url, NSDictionary *headers, NSData *body, NSInteger *status) { return wrap(@""); };
    CHECK(!awaitReply(^(void (^done)(id)) { SGPetitLyricsAsk(query, done); }, nil));
    CHECK(query.requestContext.emptyNameSearch != nil);
    query.requestContext = [SGLyricsRequestContext new];
    sg_sourceAnswer = ^id(NSURL *url, NSDictionary *headers, NSData *body, NSInteger *status) {
        *status = 429; return @"<response><status>rate limited</status></response>";
    };
    CHECK(!awaitReply(^(void (^done)(id)) { SGPetitLyricsAsk(query, done); }, nil));
    CHECK(query.requestContext.failed && !query.requestContext.emptyNameSearch);
    query.requestContext = [SGLyricsRequestContext new];
    sg_sourceAnswer = ^id(NSURL *url, NSDictionary *headers, NSData *body, NSInteger *status) { return @"<response><songs>"; };
    CHECK(!awaitReply(^(void (^done)(id)) { SGPetitLyricsAsk(query, done); }, nil));
    CHECK(query.requestContext.failed);
    for (NSString *payload in @[@"", @"<wsy><broken>"]) {
        query.requestContext = [SGLyricsRequestContext new];
        sg_sourceAnswer = ^id(NSURL *url, NSDictionary *headers, NSData *body, NSInteger *status) {
            return wrap(petitSong(@"5", query.title, query.artist, @"180000", @"3", payload));
        };
        CHECK(!awaitReply(^(void (^done)(id)) { SGPetitLyricsAsk(query, done); }, nil));
        CHECK(query.requestContext.failed == (payload.length != 0));
    }
    puts("PetitLyrics: XML/base64, overlapping word timing, plain fallback, ranked matching, empty and failure checks passed");
}

int main(int argc, char **argv) {
    @autoreleasepool {
        checkPetitLyrics();
        checkTimingNames();
        checkMalformedTiming();
        checkVoiceScaling();
        checkQQWordsAndArtists();
        // Thai, Lao, Khmer and Burmese, long lines with no space, and Thai among Latin and brackets.
        checkSplit(@"ฉันรักเธอมากกว่าสิ่งใดในโลกนี้และจะอยู่เคียงข้างเธอตลอดไป", YES);
        checkSplit(@"วันนี้อากาศดีมากเราไปเดินเล่นที่สวนสาธารณะด้วยกันไหมนะที่รัก", YES);
        checkSplit(@"Baby(ที่รัก)ฉันคิดถึงเธอทุกวันทุกคืนไม่เคยลืมเลย,ok?", YES);
        checkSplit(@"ฉันรักเธอ, เธอรักฉัน... (ด้วยหัวใจ)", YES);
        CHECK([piecesOf(@"(ด้วยหัวใจ)").firstObject.text isEqualToString:@"(ด้วย"]);   // what comes before the first word stays with it
        checkSplit(@"ຂ້ອຍຮັກເຈົ້າຫຼາຍທີ່ສຸດໃນໂລກນີ້ແລະຈະຢູ່ນຳເຈົ້າຕະຫຼອດໄປ", NO);
        checkSplit(@"ខ្ញុំស្រលាញ់អ្នកខ្លាំងណាស់ហើយនឹងនៅជាមួយអ្នកជារៀងរហូត", NO);
        checkSplit(@"ကျွန်တော်မင်းကိုအရမ်းချစ်တယ်ထာဝရမင်းနဲ့အတူရှိနေမယ်", NO);
        CHECK(piecesOf(@"๏๚").count == 1);   // Thai punctuation alone: no word, one piece
        CHECK(piecesOf(@"hello world").count == 2 && !piecesOf(@"hello world")[1].joined);
        CHECK(piecesOf(@"日本語の歌").count == 5 && piecesOf(@"日本語の歌")[4].joined);
        NSArray<SGKaraokeWord *> *thai = piecesOf(@"ฉันรักเธอมากกว่าสิ่งใดในโลกนี้");
        CHECK(!thai[0].joined && thai[1].joined);

        // The keys the two catalogs are matched by.
        CHECK([SGLyricsMatchKey(@"晴天（Live版）") isEqualToString:SGLyricsMatchKey(@"晴天 (Live版)")]);
        CHECK([SGLyricsMatchKey(@"Hello,　World!") isEqualToString:@"helloworld"]);
        CHECK([SGLyricsMatchKey(@"《稻香》") isEqualToString:@"稻香"]);
        CHECK([SGLyricsLeadArtist(@"周杰伦 feat. 费玉清") isEqualToString:@"周杰伦"]);
        CHECK(SGLyricsSameArtist(@"周杰伦、费玉清", @"周杰伦 Feat. Someone") && !SGLyricsSameArtist(@"林俊杰", @"周杰伦"));
        CHECK(!SGLyricsSameArtist(@"", @"周杰伦") && !SGLyricsSameArtist(nil, @"x"));

        // KRC: pieces timed from their line's start, a spaced word's pieces run together, a syllable each
        // in Chinese, a piece of no length shown for 1 ms, a line ending at its last word when that is later.
        NSArray<SGKaraokeLine *> *lines = SGKuGouLines(packed(kKRC, @"krc1"));
        CHECK(lines.count == 3);
        CHECK([SGKaraokeLineText(lines[0]) isEqualToString:@"Hello world"] && lines[0].words.count == 2);
        CHECK(lines[0].words[0].start == 1000 && lines[0].words[0].end == 1800 && lines[0].words[1].start == 1800);
        CHECK(lines[0].start == 1000 && lines[0].end == 3000 && lines[0].timing == SGKaraokeTimingWords);
        CHECK(lines[1].words.count == 3 && [SGKaraokeLineText(lines[1]) isEqualToString:@"你好啊"]);
        CHECK(lines[1].words[1].joined && lines[1].words[2].start == 4800 && lines[1].words[2].end == 4801);
        CHECK(lines[2].end == 7300);
        // NetEase's yrc, timed from the track's start: "wan" runs on into "ted ", and a piece after one
        // with no space after it runs on into it even when it opens with a space of its own.
        lines = SGLyricsPieceLines(@"[1000,3000](1000,200,0)wan(1200,300,0)ted (1500,0,0)to(1600,100,0) go\n"
            "[5000,1000](5000,100,0)你(5100,100,0)好", NO);
        CHECK(lines.count == 2 && [SGKaraokeLineText(lines[0]) isEqualToString:@"wanted togo"]);
        CHECK(lines[0].words[0].start == 1000 && lines[0].words[0].end == 1500 && !lines[0].words[0].joined);
        CHECK(lines[0].words[1].start == 1500 && lines[0].words[1].end == 1700 && !lines[0].words[1].joined);
        CHECK(lines[0].start == 1000 && lines[0].end == 4000);
        CHECK(lines[1].words.count == 2 && lines[1].words[1].joined && lines[1].words[1].start == 5100 && lines[1].end == 6000);
        CHECK(!SGLyricsPieceLines(@"[1000,3000]", NO) && !SGLyricsPieceLines(@"", NO));
        // A piece run on into a word that is sung longer leaves the word's end where it was.
        lines = SGLyricsPieceLines(@"[1000,500](1000,800,0)ab(1200,100,0)cd ", NO);
        CHECK(lines.count == 1 && lines[0].words.count == 1 && lines[0].words[0].end == 1800 && lines[0].end == 1800);

        // Musixmatch's richsync: an entry's offset is from its line's start, and only an entry of spaces
        // ends a word, so "Mil" "ion" is one word and "ab" " cd" another. A word is sung until the next
        // word starts, the last until a space after it or the line's end; a syllable of an unspaced
        // script is a word of its own, joined to the one before.
        SGLyricsResult *rich = SGMusixmatchRichsyncResult(@[
            @{@"ts": @10, @"te": @14, @"x": @"Milion +, go", @"l": @[@{@"c": @"Mil", @"o": @0}, @{@"c": @"ion", @"o": @0.3}, @{@"c": @" ", @"o": @0.6},
                @{@"c": @"+", @"o": @0.8}, @{@"c": @",", @"o": @0.9}, @{@"c": @" ", @"o": @1.0}, @{@"c": @"go", @"o": @1.5}]},
            @{@"ts": @20, @"te": @22, @"l": @[@{@"c": @"a", @"o": @0}, @{@"c": @" ", @"o": @0.5}]},
            @{@"ts": @30, @"te": @31, @"l": @[@{@"c": @"日", @"o": @0}, @{@"c": @"本", @"o": @0}]},
            @{@"ts": @40, @"te": @42, @"l": @[@{@"c": @"ab", @"o": @0}, @{@"c": @" cd", @"o": @0.5}, @{@"c": @5, @"o": @0.7}]},
            @{@"ts": @50, @"te": @51, @"l": @[@{@"c": @" ", @"o": @0}]},
        ]);
        NSArray<SGKaraokeLine *> *rl = rich.karaokeLines;
        CHECK(rich.wordTimed && rl.count == 4);
        CHECK([SGKaraokeLineText(rl[0]) isEqualToString:@"Milion +, go"] && rl[0].start == 10000 && rl[0].end == 14000);
        CHECK(rl[0].words[0].start == 10000 && rl[0].words[0].end == 10800 && rl[0].words[1].start == 10800 && rl[0].words[1].end == 11500);
        CHECK(rl[0].words[2].start == 11500 && rl[0].words[2].end == 14000 && !rl[0].words[1].joined && !rl[0].words[2].joined);
        CHECK(rl[1].words.count == 1 && rl[1].words[0].end == 20500 && rl[1].end == 22000);
        CHECK(rl[2].words.count == 2 && rl[2].words[0].end == 30000 && rl[2].words[1].joined && rl[2].words[1].end == 31000);
        CHECK([SGKaraokeLineText(rl[3]) isEqualToString:@"abcd"] && rl[3].words[0].start == 40000 && rl[3].words[0].end == 42000);
        CHECK(([rich.texts isEqualToArray:@[@"Milion +, go", @"♪", @"a", @"♪", @"日本", @"♪", @"abcd", @""]]));
        CHECK(!SGMusixmatchRichsyncResult(@[]) && !SGMusixmatchRichsyncResult(@"x"));
        // An entry run on into a word after the line's end is sung to its own end, not cut off before it.
        rl = SGMusixmatchRichsyncResult(@[@{@"ts": @60, @"te": @61, @"l": @[@{@"c": @"ab", @"o": @0}, @{@"c": @"cd", @"o": @2}]}]).karaokeLines;
        CHECK(rl.count == 1 && rl[0].words.count == 1 && rl[0].words[0].end == 62000 && rl[0].end == 62000);
        CHECK(!SGKuGouLines(packed(kKRC, @"krc2")) && !SGKuGouLines(@"bm90IGtyYw==") && !SGKuGouLines(nil));
        CHECK(!SGKuGouLines(packed(@"[ar:only tags]", @"krc1")));

        // KuGou: the user uploads, another title, another singer, a length 21 s off and a candidate with
        // no key are passed over; the rest are tried closest in length first, three at most.
        NSArray *candidates = @[
            @{@"id": @"a", @"accesskey": @"k", @"product_from": @"ugc", @"song": @"晴天", @"singer": @"周杰伦", @"duration": @269000},
            @{@"id": @"b", @"accesskey": @"k", @"song": @"晴天 (Live)", @"singer": @"周杰伦", @"duration": @269000},
            @{@"id": @"c", @"accesskey": @"k", @"song": @"晴天", @"singer": @"Other", @"duration": @269000},
            @{@"id": @"d", @"accesskey": @"k", @"song": @"晴天", @"singer": @"周杰伦", @"duration": @290000},
            @{@"id": @"e", @"accesskey": @"k", @"song": @"晴天", @"singer": @"周杰伦", @"duration": @265000},
            @{@"id": @7, @"accesskey": @"k", @"song": @"晴天", @"singer": @"周杰伦", @"duration": @269500},
            @{@"id": @"g", @"accesskey": @"k", @"song": @"晴天", @"singer": @"周杰伦", @"duration": @262000},
            @{@"id": @"h", @"song": @"晴天", @"singer": @"周杰伦", @"duration": @270000},
            @{@"id": @"i", @"accesskey": @"k", @"song": @" 晴天！", @"singer": @"周杰伦、费玉清", @"duration": @"268000"},
        ];
        NSMutableArray<NSString *> *tried = [NSMutableArray array];
        __block NSString *keyword, *duration, *good = @"e";
        sg_answer = ^id(NSURL *url, id body) {
            if ([url.host isEqualToString:@"krcs.kugou.com"]) {
                keyword = param(url, @"keyword");
                duration = param(url, @"duration");
                return @{@"status": @200, @"candidates": candidates};
            }
            NSString *song = param(url, @"id");
            [tried addObject:song];
            if ([song isEqualToString:good]) return @{@"status": @200, @"content": packed(kKRC, @"krc1")};
            return [song isEqualToString:@"7"] ? @{@"status": @200, @"content": @"garbage"} : @{@"status": @404};
        };
        SGLyricsQuery *query = [SGLyricsQuery new];
        query.title = @"晴天";
        query.artist = @"周杰伦 feat. Someone";
        query.seconds = 269;
        __block SGLyricsResult *got = nil;
        got = sourceAnswer(SGKuGouAsk, query);
        CHECK([keyword isEqualToString:@"周杰伦 - 晴天"] && [duration isEqualToString:@"269000"]);
        CHECK([tried isEqualToArray:(@[@"7", @"i", @"e"])]);
        CHECK(got.synced && got.wordTimed && got.karaokeLines.count == 3 && got.texts.count == 3);
        [tried removeAllObjects];
        good = @"g";   // fourth in line: never asked
        got = [SGLyricsResult new];
        got = sourceAnswer(SGKuGouAsk, query);
        CHECK([tried isEqualToArray:(@[@"7", @"i", @"e"])] && !got);
        query.artist = @"";
        got = [SGLyricsResult new];
        [tried removeAllObjects];
        got = sourceAnswer(SGKuGouAsk, query);
        CHECK(!got && !tried.count);

        // QQ Music: the first result with the title, a singer and the length is taken, and its LRC read.
        NSString *lrc = @"[ti:x]\n[ar:y]\n[00:01.00]第一行\n[00:03.50]第二行\n";
        __block NSDictionary *asked = nil;
        sg_answer = ^id(NSURL *url, NSDictionary *body) {
            if (body[@"req"]) return @{@"req": @{@"data": @{@"body": @{@"song": @{@"list": @[
                @{@"title": @"晴天", @"interval": @269, @"singer": @[@{@"name": @"Someone Else"}], @"id": @1},
                @{@"title": @"晴天", @"interval": @300, @"singer": @[@{@"name": @"周杰伦"}], @"id": @2},
                @{@"title": @"雨天", @"interval": @269, @"singer": @[@{@"name": @"周杰伦"}], @"id": @3},
                @{@"songname": @"晴天", @"interval": @270, @"singer": @[@{@"name": @"x"}, @{@"name": @"周杰伦"}], @"id": @97773},
            ]}}}}};
            asked = body[@"music.musichallSong.PlayLyricInfo.GetPlayLyricInfo"][@"param"];
            NSString *encoded = [[lrc dataUsingEncoding:NSUTF8StringEncoding] base64EncodedStringWithOptions:0];
            return @{@"music.musichallSong.PlayLyricInfo.GetPlayLyricInfo": @{@"data": @{@"lyric": encoded}}};
        };
        query.artist = @"周杰伦";
        got = nil;
        got = sourceAnswer(SGQQMusicAsk, query);
        CHECK([asked[@"songID"] isEqual:@97773] && [asked[@"qrc"] isEqual:@1] && [asked[@"crypt"] isEqual:@0]);
        CHECK(got.synced && !got.wordTimed && got.karaokeLines.count == 2 && got.karaokeLines[1].start == 3500);
        query.seconds = 200;   // no recording that long: nothing asked for lyrics
        asked = nil;
        got = [SGLyricsResult new];
        got = sourceAnswer(SGQQMusicAsk, query);
        CHECK(!got && !asked);

        checkMalformedPayloads();
        checkNewSources();
        checkDeezerKeychain();
        checkReadingAndSearch();
        checkLanguagesAndTitles();
        // Lyricsfile: the spec's own example, two words timed to the end of each.
        NSArray<SGKaraokeLine *> *lf = SGLyricsfileLines(@"version: '1.0'\n\nmetadata:\n  title: 'Example Song'\n  artist: 'Example Artist'\n"
            "  language: 'en'\n  instrumental: false\n\nlines:\n  - text: 'Hello world'\n    start_ms: 1200\n    end_ms: 2800\n    words:\n"
            "      - text: 'Hello '\n        start_ms: 1200\n        end_ms: 1900\n      - text: 'world'\n        start_ms: 1900\n        end_ms: 2800\n\n"
            "plain: |\n  Hello world\n");
        CHECK(lf.count == 1 && lf[0].words.count == 2 && [SGKaraokeLineText(lf[0]) isEqualToString:@"Hello world"]);
        CHECK(lf[0].start == 1200 && lf[0].end == 2800 && lf[0].timing == SGKaraokeTimingWords);
        CHECK(lf[0].words[0].end == 1900 && lf[0].words[1].start == 1900 && !lf[0].words[1].joined);

        // As LRCLIB writes it: keys in any order, words with no end of their own ending where the next
        // starts and the last one with its line; a segment with no space after it runs into the next
        // one, Japanese syllables stay apart and flush, and a line timed only as a whole is estimated.
        // The rows a sequence's items start on are at its key's indent, quoted the way YAML quotes.
        NSString *lrclib = @"version: \"1.0\"\nmetadata:\n  title: ကမ္ဘာ\n  artist: Someone # a comment\nlines:\n"
            "- text: \"Hold on \"\n  words:\n  - text: \"Hold \"\n    start_ms: 48712\n  - text: \"on \"\n    start_ms: 49109\n  start_ms: 48712\n  end_ms: 52187\n"
            "- text: wanted now\n  start_ms: 53000\n  words:\n    - text: wan\n      start_ms: 53000\n    - text: \"ted \"\n      start_ms: 53200\n      end_ms: 53500\n"
            "    - {text: now}\n";
        CHECK(!SGLyricsfileLines(lrclib));   // a flow mapping is refused, and the whole file with it
        lrclib = [lrclib stringByReplacingOccurrencesOfString:@"    - {text: now}\n" withString:@"    - text: now\n      start_ms: 54000\n"];
        lrclib = [lrclib stringByAppendingString:@"- text: '''Cause I''m-'\n  start_ms: 60000\n  end_ms: 62000\n- text: ''\n  start_ms: 62000\n"
            "- text: \"\\u65e5\\u672c語\"\n  start_ms: 63000\n  end_ms: 64000\n  words:\n  - text: 日本\n    start_ms: 63000\n  - text: 語\n    start_ms: 63500\n"
            "plain: |-\n  Hold on\n\n  wanted now\n"];
        lf = SGLyricsfileLines(lrclib);
        CHECK(lf.count == 4);
        checkWordLines(lf);
        CHECK([SGKaraokeLineText(lf[0]) isEqualToString:@"Hold on"] && lf[0].words[0].end == 49109 && lf[0].words[1].end == 52187);
        CHECK(lf[1].words.count == 2 && [lf[1].words[0].text isEqualToString:@"wanted"] && lf[1].words[0].end == 53500);
        CHECK([lf[1].words[1].text isEqualToString:@"now"] && !lf[1].words[1].joined && lf[1].end == 55000);   // no end anywhere: a second past its last word
        CHECK([SGKaraokeLineText(lf[2]) isEqualToString:@"'Cause I'm-"] && lf[2].timing == SGKaraokeTimingLine && lf[2].start == 60000);
        CHECK(lf[3].words.count == 2 && lf[3].words[1].joined && [SGKaraokeLineText(lf[3]) isEqualToString:@"日本語"]);

        // LRCLIB's Lyricsfile for a record timed by the line alone: nothing the LRC does not have.
        CHECK(!SGLyricsfileLines(@"version: '1.0'\nmetadata:\n  title: a\n  artist: b\nlines:\n- text: Biatch!\n  start_ms: 90\n  end_ms: 960\n"));
        // Refused whole: another version, a key twice, a tab for indent, a negative time, an end before its
        // start, a quote never closed, words not a list, an alias, a stray row, not YAML at all.
        NSString *wordFile = @"version: '1.0'\nlines:\n- text: a\n  start_ms: 10\n  words:\n  - text: a\n    start_ms: 10\n";
        CHECK(SGLyricsfileLines(wordFile).count == 1);
        for (NSArray<NSString *> *swap in @[@[@"'1.0'", @"'2.0'"], @[@"  start_ms: 10\n  words", @"  start_ms: 10\n  start_ms: 11\n  words"],
                                            @[@"  start_ms: 10\n  words", @"\tstart_ms: 10\n  words"], @[@"    start_ms: 10", @"    start_ms: -10"],
                                            @[@"    start_ms: 10", @"    start_ms: 10\n    end_ms: 5"], @[@"- text: a", @"- text: \"a"],
                                            @[@"  - text: a\n    start_ms: 10\n", @"  a\n"], @[@"- text: a", @"- text: *a"],
                                            @[@"lines:", @"  stray\nlines:"], @[@"    start_ms: 10", @"    start_ms: 9223372036854775807"],
                                            @[@"- text: a", @"- text: \"\\u1\U0001F600\""]]) {
            CHECK(!SGLyricsfileLines([wordFile stringByReplacingOccurrencesOfString:swap[0] withString:swap[1]]));
        }
        // An end written as YAML's null, on a line or a word, is no end: the line stops a second past its last word.
        for (NSString *null in @[@"null", @"~", @""]) {
            lf = SGLyricsfileLines([wordFile stringByReplacingOccurrencesOfString:@"    start_ms: 10\n"
                                        withString:[NSString stringWithFormat:@"    start_ms: 10\n    end_ms: %@\n  end_ms: %@\n", null, null]]);
            CHECK(lf.count == 1 && lf[0].words.count == 1 && lf[0].end == 1010);
        }
        // YAML's other escapes, a block whose header gives its indent, and lines listed out of time order.
        lf = SGLyricsfileLines([wordFile stringByAppendingString:@"- text: \"b\\Lc\\N\"\n  start_ms: 5\n  words:\n  - text: \"b\\Lc\"\n    start_ms: 5\nplain: |2\n     a\n    b\n"]);
        CHECK(lf.count == 2 && lf[0].start == 5 && [lf[0].words[0].text isEqualToString:@"b\u2028c"]);
        // A segment that runs into a word sung before it leaves the word's end where it was.
        lf = SGLyricsfileLines(@"version: '1.0'\nlines:\n- text: wanted\n  start_ms: 10\n  words:\n  - text: wan\n    start_ms: 50\n"
            "  - text: ted\n    start_ms: 20\n    end_ms: 30\n");
        CHECK(lf.count == 1 && lf[0].words.count == 1);
        checkWordLines(lf);
        // Nested far past the spec's four levels, or over 256 KB: refused, not followed. The same file
        // with its extra key nested ten deep still reads.
        NSString *(^nested)(NSUInteger) = ^NSString *(NSUInteger levels) {
            NSMutableString *doc = [NSMutableString stringWithString:wordFile];
            for (NSUInteger level = 0; level < levels; level++) {
                [doc appendFormat:@"%@k:\n", [@"" stringByPaddingToLength:level withString:@" " startingAtIndex:0]];
            }
            [doc appendFormat:@"%@x: 1\n", [@"" stringByPaddingToLength:levels withString:@" " startingAtIndex:0]];
            return doc;
        };
        CHECK(SGLyricsfileLines(nested(10)).count == 1);
        CHECK(!SGLyricsfileLines(nested(20)) && !SGLyricsfileLines(nested(1000)));
        CHECK(!SGLyricsfileLines([wordFile stringByAppendingFormat:@"plain: |\n  %@\n", [@"" stringByPaddingToLength:(1 << 18) withString:@"a" startingAtIndex:0]]));
        CHECK(!SGLyricsfileLines(@"[not, yaml") && !SGLyricsfileLines(@"") && !SGLyricsfileLines(nil) && !SGLyricsfileLines((NSString *)@3));

        // LRCLIB: a record with words timed answers with them; one whose Lyricsfile cannot be read, or
        // that says it has no word sync, answers with its LRC; the search picks the record with words over a closer one without.
        NSString *twoLines = @"[00:01.00]a\n[00:02.00]b\n";
        __block NSDictionary *record = @{@"id": @1, @"duration": @200, @"hasWordSync": @YES, @"syncedLyrics": twoLines, @"lyricsfile": wordFile};
        __block NSArray *found = nil;
        sg_answer = ^id(NSURL *url, id body) { return [url.path hasSuffix:@"/get"] ? record : found; };
        query.title = @"a";
        query.artist = @"b";
        query.seconds = 200;
        // JSON and all result construction run off main, with or without a Lyricsfile.
        BOOL atOnce = YES;
        got = lrclibAnswer(query, &atOnce);
        CHECK(got.wordTimed && got.synced && got.karaokeLines.count == 1 && got.texts.count && !atOnce);
        record = @{@"id": @1, @"duration": @200, @"hasWordSync": @YES, @"syncedLyrics": twoLines, @"lyricsfile": @"version: '9'"};
        got = lrclibAnswer(query, nil);
        CHECK(!got.wordTimed && got.synced && got.karaokeLines.count == 2);
        record = @{@"id": @1, @"duration": @200, @"hasWordSync": @NO, @"syncedLyrics": twoLines, @"lyricsfile": wordFile};
        got = lrclibAnswer(query, &atOnce);
        CHECK(!got.wordTimed && got.synced && got.karaokeLines.count == 2 && !atOnce);
        // An instrumental is answered as one, its Lyricsfile not read.
        record = @{@"id": @1, @"duration": @200, @"instrumental": @YES, @"hasWordSync": @YES, @"lyricsfile": wordFile};
        got = lrclibAnswer(query, &atOnce);
        CHECK(got.instrumental && !atOnce);
        record = nil;
        found = @[@{@"id": @2, @"trackName": @"a", @"artistName": @"b", @"duration": @200, @"syncedLyrics": twoLines},
                  @{@"id": @3, @"trackName": @"a", @"artistName": @"b", @"duration": @202, @"hasWordSync": @YES, @"syncedLyrics": twoLines, @"lyricsfile": wordFile}];
        got = lrclibAnswer(query, nil);
        CHECK(got.wordTimed && got.karaokeLines.count == 1);
        // Only a record that is the track can win, however it is timed: not another song of the artist's, nor
        // the song by someone whose name only begins with the artist's. A record that names the artist first of
        // several is theirs, and another version of the song ("a - Live") is still the song.
        NSDictionary *otherSong = @{@"id": @6, @"trackName": @"c", @"artistName": @"b", @"duration": @200, @"hasWordSync": @YES, @"syncedLyrics": twoLines, @"lyricsfile": wordFile};
        NSDictionary *otherArtist = @{@"id": @7, @"trackName": @"a", @"artistName": @"b key", @"duration": @200, @"hasWordSync": @YES, @"syncedLyrics": twoLines, @"lyricsfile": wordFile};
        found = @[otherSong, otherArtist, found[0]];
        got = lrclibAnswer(query, nil);
        CHECK(got.synced && !got.wordTimed && got.karaokeLines.count == 2);
        found = @[otherSong, otherArtist];
        CHECK(!lrclibAnswer(query, nil));
        found = @[@{@"id": @8, @"trackName": @"a - Live", @"artistName": @"b, x", @"duration": @200, @"hasWordSync": @YES, @"syncedLyrics": twoLines, @"lyricsfile": wordFile}];
        got = lrclibAnswer(query, nil);
        CHECK(got.wordTimed && got.karaokeLines.count == 1);
        // The artists joined by a word or by punctuation, in either order, as LRCLIB's records write them.
        for (NSString *joined in @[@"b and x", @"B And X", @"x; b", @"B/X/B/X", @"b x x", @"x • b", @"b vs. x"]) {
            found = @[@{@"id": @12, @"trackName": @"a", @"artistName": joined, @"duration": @200, @"syncedLyrics": twoLines}];
            got = lrclibAnswer(query, nil);
            CHECK(got.synced && got.karaokeLines.count == 2);
        }
        // A record's words count once its Lyricsfile reads: one whose file cannot be read is weighed on its LRC,
        // so the words of a record further off win, and with no file that reads the closer LRC does.
        NSDictionary *unreadable = @{@"id": @9, @"trackName": @"a", @"artistName": @"b", @"duration": @202, @"hasWordSync": @YES, @"syncedLyrics": twoLines, @"lyricsfile": @"version: '9'"};
        found = @[unreadable, @{@"id": @10, @"trackName": @"a", @"artistName": @"b", @"duration": @204, @"hasWordSync": @YES, @"syncedLyrics": twoLines, @"lyricsfile": wordFile}];
        got = lrclibAnswer(query, nil);
        CHECK(got.wordTimed && got.karaokeLines.count == 1);
        found = @[unreadable, @{@"id": @11, @"trackName": @"a", @"artistName": @"b", @"duration": @200, @"syncedLyrics": @"[00:01.00]a\n[00:02.00]b\n[00:03.00]c\n"}];
        got = lrclibAnswer(query, nil);
        CHECK(!got.wordTimed && got.synced && got.karaokeLines.count == 3);
        // A length spelled as null is unknown, not a crash: matching keeps such a record whole, and the
        // ranking weighs it as having no length to go on rather than messaging NSNull. Each record's words
        // say which one won.
        query.seconds = 200;
        NSDictionary *unsized = @{@"id": @13, @"trackName": @"a", @"artistName": @"b", @"duration": NSNull.null,
                                  @"syncedLyrics": @"[00:01.00]alone\n[00:02.00]alone b\n"};
        found = @[unsized];
        got = lrclibAnswer(query, nil);
        CHECK(got && got.synced && got.karaokeLines.count == 2);
        CHECK([SGKaraokeLineText(got.karaokeLines[0]) isEqualToString:@"alone"]);
        // Two with no length and one 4 s off the track, inside the slack: the one that says its length wins,
        // since the ones that do not are 200 s off.
        found = @[unsized, @{@"id": @14, @"trackName": @"a", @"artistName": @"b", @"duration": NSNull.null,
                             @"syncedLyrics": @"[00:01.00]unsized again\n[00:02.00]unsized again b\n", @"plainLyrics": @"x\ny"},
                  @{@"id": @15, @"trackName": @"a", @"artistName": @"b", @"duration": @204,
                    @"syncedLyrics": @"[00:01.00]sized\n[00:02.00]sized b\n"}];
        got = lrclibAnswer(query, nil);
        CHECK(got && got.synced && got.karaokeLines.count == 2);
        CHECK([SGKaraokeLineText(got.karaokeLines[0]) isEqualToString:@"sized"]);
        // Equal duration distances break ties by the fullest sheet.
        found = @[unsized, @{@"id": @14, @"trackName": @"a", @"artistName": @"b", @"duration": NSNull.null,
                             @"syncedLyrics": @"[00:01.00]unsized again\n[00:02.00]unsized again b\n", @"plainLyrics": @"x\ny"}];
        got = lrclibAnswer(query, nil);
        CHECK(got && got.synced);
        CHECK([SGKaraokeLineText(got.karaokeLines[0]) isEqualToString:@"unsized again"]);

        // With no length to go on, a record whose LRC is null against one whose LRC is empty: the plain text wins.
        query.seconds = 0;
        found = @[@{@"id": @4, @"trackName": @"a", @"artistName": @"b", @"syncedLyrics": NSNull.null, @"plainLyrics": @"x"},
                  @{@"id": @5, @"trackName": @"a", @"artistName": @"b", @"syncedLyrics": @"", @"plainLyrics": @"y\nz"}];
        got = lrclibAnswer(query, nil);
        CHECK(got && !got.synced);

        for (int i = 1; i < argc; i++) checkLive(@(argv[i]));
        printf("lyrics-sources: all checks passed\n");
    }
    return 0;
}
