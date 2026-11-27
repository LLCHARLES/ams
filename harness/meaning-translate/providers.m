// No provider adapter or AI request/parser is replaced. URLSession gets an offline URLProtocol.
#import <UIKit/UIKit.h>
#import <Security/Security.h>
#import <objc/runtime.h>
#import "Shared/LyricsTranslation/AIServicesInternal.h"
#import "Shared/Lyrics/Lyrics.h"
#import "Shared/LyricsSources/LyricsSources.h"
#import "Settings/SGModPage.h"
#import "../harness-fail.h"

static NSUInteger checks, requests, failAt, metadataFailAt, maxUnits, activeRequests;
static NSString *provider, *stopReason;
static BOOL refusal, omitStop, localAvailable, languagesInstalled, preparedLanguages;
static NSMutableArray<NSString *> *sent;
static __weak UIView *presentingView;
#define CHECK(c, ...) do { checks++; if (!(c)) HARNESS_FAIL(__VA_ARGS__); } while (0)

NSString *SGL(NSString *key, NSString *english) { return english; }
void SGLogLong(NSString *tag, NSString *text) {}
NSInteger SGInt(NSString *key, NSInteger fallback) { return fallback; }
BOOL SGFlag(NSString *key, BOOL fallback) {
    if ([key isEqual:SGKeyLyricsBingTranslate]) return [provider isEqual:@"bing"];
    if ([key isEqual:SGKeyLyricsGoogleTranslate]) return [provider isEqual:@"google"];
    return fallback;
}
NSString *SGLyricsTranslationLanguage(void) { return @"fr"; }
UIViewController *SGTopController(void) { return nil; }
NSDictionary *SGLocalFileInfo(NSString *track) { return nil; }
id SGKaraokeTrackFor(NSString *track) { return nil; }
void SGLyricsTitleSettingsChanged(void) {}
void SGLyricsTranslationServiceSettingsChanged(void) {}
void SGLyricsSaveTranslation(NSString *track, NSString *language, NSArray *lines) { HARNESS_FAIL(@"prose saved lyric data"); }
void SGLyricsSaveAI(NSString *kind, NSString *track, NSString *variant, NSDictionary *values) { HARNESS_FAIL(@"prose saved AI lyric data"); }
void SGLyricsLoadSavedAI(NSString *kind, NSString *track, NSString *variant, void (^done)(NSDictionary *, NSError *)) { HARNESS_FAIL(@"prose read AI lyric data"); }

OSStatus ProseTestKey(CFDictionaryRef query, CFTypeRef *result) {
    NSDictionary *q = (__bridge NSDictionary *)query;
    NSString *service = q[(__bridge id)kSecAttrService];
    NSDictionary *services = @{@"deepl": @"Vitrine.DeepL", @"gemini": @"Vitrine.Gemini",
                               @"claude": @"Vitrine.Claude", @"openai": @"Vitrine.OpenAI"};
    if (![service isEqual:services[provider]] ||
        ([provider isEqual:@"openai"] && ![q[(__bridge id)kSecAttrAccount] isEqual:@"https://api.openai.com:443"])) return errSecItemNotFound;
    if (result) *result = CFBridgingRetain([@"fixture-key" dataUsingEncoding:NSUTF8StringEncoding]);
    return errSecSuccess;
}
OSStatus ProseTestKeyAdd(CFDictionaryRef q, CFTypeRef *result) { HARNESS_FAIL(@"unexpected key write"); }
OSStatus ProseTestKeyUpdate(CFDictionaryRef q, CFDictionaryRef a) {
    if (((__bridge NSDictionary *)a)[(__bridge id)kSecAttrAccount]) return errSecItemNotFound;
    HARNESS_FAIL(@"unexpected key update");
}
OSStatus ProseTestKeyDelete(CFDictionaryRef q) { return errSecSuccess; }

@implementation SGModRow
@end
SGModRow *SGStatActionRow(NSString *t, NSString *s, NSString *(^v)(void), void (^a)(void)) { return nil; }
SGModRow *SGMenuRow(NSString *t, NSArray *c, NSString *(^v)(void), void (^a)(NSInteger)) { return nil; }
SGModRow *SGSwitchRow(NSString *t, NSString *s, NSString *key) { return nil; }
SGModRow *SGOptionRow(NSString *t, NSString *s, NSString *key) { return nil; }

static NSArray *translate(NSArray *texts) {
    NSMutableArray *answer = [NSMutableArray array];
    for (NSString *text in texts) [answer addObject:[text stringByReplacingOccurrencesOfString:@"Cat" withString:@"Chat"]];
    return answer;
}

@implementation SGOnDeviceTranslation
+ (BOOL)translationAvailable { return localAvailable; }
+ (BOOL)appleIntelligenceAvailable:(NSString *)tag { return NO; }
+ (void)openTranslateSettings {}
+ (void)translate:(NSArray<NSString *> *)texts to:(NSString *)tag done:(void (^)(NSArray<NSString *> *, NSString *))done {
    [self translate:texts to:tag from:nil done:done];
}
+ (void)translate:(NSArray<NSString *> *)texts to:(NSString *)tag from:(UIView *)view done:(void (^)(NSArray<NSString *> *, NSString *))done {
    if (!languagesInstalled && view) { preparedLanguages = YES; presentingView = view; languagesInstalled = YES; }
    done(languagesInstalled ? translate(texts) : nil, languagesInstalled ? nil : @"retrine.translation.languagesMissing");
}
+ (void)translateWithAppleIntelligence:(NSArray<NSString *> *)texts to:(NSString *)tag song:(NSString *)song
                              progress:(void (^)(NSArray<NSString *> *))progress done:(void (^)(NSArray<NSString *> *, NSString *))done {
    HARNESS_FAIL(@"unexpected Apple Intelligence route");
}
@end

void SGLyricsSourceRequest(NSURL *url, NSDictionary *headers, NSData *body, void (^done)(NSData *, NSInteger)) {
    CHECK([url.absoluteString isEqual:@"https://www.bing.com/translator"], @"unexpected source request");
    NSString *html = @"<div data-iid=\"translator.1\"></div><script>IG: \"fixture\"; params_AbusePreventionHelper = [1234567890123,\"token\",3600000];</script>";
    dispatch_async(dispatch_get_main_queue(), ^{ done([html dataUsingEncoding:NSUTF8StringEncoding], 200); });
}

static NSDictionary *form(NSData *data) {
    NSURLComponents *parts = [NSURLComponents new];
    parts.percentEncodedQuery = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    NSMutableDictionary *values = [NSMutableDictionary dictionary];
    for (NSURLQueryItem *item in parts.queryItems) values[item.name] = item.value;
    return values;
}
static NSString *jsonText(id value) {
    return [[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:value options:0 error:nil] encoding:NSUTF8StringEncoding];
}
static NSData *requestBody(NSURLRequest *request) {
    if (request.HTTPBody) return request.HTTPBody;
    // URLSession hands a POST body to URLProtocol as a stream.
    NSInputStream *stream = request.HTTPBodyStream;
    CHECK(stream != nil, @"missing transport request body");
    NSMutableData *data = [NSMutableData data];
    [stream open];
    uint8_t bytes[4096];
    NSInteger length;
    while ((length = [stream read:bytes maxLength:sizeof(bytes)]) > 0) [data appendBytes:bytes length:(NSUInteger)length];
    CHECK(length == 0, @"request stream failed: %@", stream.streamError);
    [stream close];
    return data;
}
static id replyFor(NSURLRequest *request) {
    CHECK(NSThread.isMainThread, @"transport fixture not on main");
    requests++;
    NSArray *texts;
    NSDictionary *body = nil;
    NSData *data = requestBody(request);
    if ([@[@"bing", @"google"] containsObject:provider]) {
        NSDictionary *fields = form(data);
        NSString *text = fields[[provider isEqual:@"bing"] ? @"text" : @"q"];
        CHECK(text && text.length <= maxUnits, @"%@ exceeded its UTF-16 batch limit", provider);
        texts = [text componentsSeparatedByString:@"\n"];
    } else {
        body = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if ([provider isEqual:@"deepl"]) texts = body[@"text"];
        else {
            NSString *prompt = [provider isEqual:@"gemini"] ? body[@"contents"][0][@"parts"][0][@"text"] :
                [provider isEqual:@"claude"] ? body[@"messages"][0][@"content"] : body[@"messages"][1][@"content"];
            NSRange dataStart = [prompt rangeOfString:@"\n\n"];
            CHECK(dataStart.location != NSNotFound, @"missing prose JSON");
            texts = [NSJSONSerialization JSONObjectWithData:[[prompt substringFromIndex:NSMaxRange(dataStart)]
                     dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
            CHECK(texts.count == 1 && [NSJSONSerialization dataWithJSONObject:texts options:0 error:nil].length <= 2000,
                  @"%@ exceeded its per-segment AI input budget", provider);
            NSNumber *outputLimit = [provider isEqual:@"gemini"] ? body[@"generationConfig"][@"maxOutputTokens"] : body[@"max_tokens"];
            CHECK(outputLimit.integerValue == 8192, @"%@ did not set the bounded prose output budget", provider);
        }
    }
    CHECK([texts isKindOfClass:NSArray.class] && texts.count, @"no input texts in request");
    for (NSString *text in texts) {
        CHECK(!maxUnits || text.length <= maxUnits, @"%@ exceeded its item limit", provider);
        CHECK([text dataUsingEncoding:NSUTF8StringEncoding] != nil, @"segmentation broke Unicode");
        [sent addObject:text];
    }
    NSArray *answer = translate(texts);
    if (requests == failAt) {
        NSMutableArray *blank = [NSMutableArray array];
        for (NSUInteger i = 0; i < texts.count; i++) [blank addObject:@""];
        answer = blank;
    }
    if ([provider isEqual:@"bing"]) return @[@{@"translations": @[@{@"text": [answer componentsJoinedByString:@"\n"]}]}];
    if ([provider isEqual:@"google"]) return @[@[@[[answer componentsJoinedByString:@"\n"]]]];
    if ([provider isEqual:@"deepl"]) {
        NSMutableArray *rows = [NSMutableArray array];
        for (NSString *text in answer) [rows addObject:@{@"text": text}];
        return @{@"translations": rows};
    }
    NSString *json = jsonText(answer);
    NSString *reason = requests == metadataFailAt ? ([provider isEqual:@"openai"] ? @"length" :
        [provider isEqual:@"claude"] ? @"max_tokens" : @"MAX_TOKENS") : stopReason;
    if ([provider isEqual:@"openai"]) {
        NSMutableDictionary *message = [@{@"content": json} mutableCopy];
        if (refusal) message[@"refusal"] = @"refused";
        NSMutableDictionary *choice = [@{@"message": message} mutableCopy];
        if (!omitStop) choice[@"finish_reason"] = reason ?: @"stop";
        return @{@"choices": @[choice]};
    }
    if ([provider isEqual:@"claude"]) {
        NSMutableArray *content = [NSMutableArray arrayWithObject:@{@"type": @"text", @"text": json}];
        if (refusal) [content addObject:@{@"type": @"tool_use", @"id": @"fixture"}];
        NSMutableDictionary *reply = [@{@"content": content} mutableCopy];
        if (!omitStop) reply[@"stop_reason"] = reason ?: @"end_turn";
        return reply;
    }
    CHECK([provider isEqual:@"gemini"], @"unknown fixture provider");
    NSMutableDictionary *candidate = [@{@"content": @{@"parts": @[@{@"text": json}]}} mutableCopy];
    if (!omitStop) candidate[@"finishReason"] = reason ?: @"STOP";
    NSMutableDictionary *reply = [@{@"candidates": @[candidate]} mutableCopy];
    if (refusal) reply[@"promptFeedback"] = @{@"blockReason": @"SAFETY"};
    return reply;
}

@interface ProseProtocol : NSURLProtocol
@end
@implementation ProseProtocol
+ (BOOL)canInitWithRequest:(NSURLRequest *)request { return YES; }
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request { return request; }
- (void)startLoading {
    dispatch_async(dispatch_get_main_queue(), ^{
        CHECK(++activeRequests == 1, @"overlapping paid segment requests");
        NSData *data = [NSJSONSerialization dataWithJSONObject:replyFor(self.request) options:0 error:nil];
        NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:self.request.URL statusCode:200
            HTTPVersion:@"HTTP/1.1" headerFields:@{@"Content-Type": @"application/json"}];
        dispatch_async(dispatch_get_main_queue(), ^{
            activeRequests--;
            [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
            [self.client URLProtocol:self didLoadData:data];
            [self.client URLProtocolDidFinishLoading:self];
        });
    });
}
- (void)stopLoading {}
@end
@interface NSURLSessionConfiguration (ProseFixture)
+ (NSURLSessionConfiguration *)proseConfiguration;
@end
@implementation NSURLSessionConfiguration (ProseFixture)
+ (NSURLSessionConfiguration *)proseConfiguration {
    NSURLSessionConfiguration *config = [self proseConfiguration];
    config.protocolClasses = @[ProseProtocol.class];
    return config;
}
@end

static void selectProvider(NSString *name) {
    provider = name;
    SGGeminiForgetKey(); SGClaudeForgetKey(); SGOpenAIForgetKeys(); SGDeepLForgetKey();
    requests = failAt = metadataFailAt = activeRequests = 0;
    stopReason = nil; refusal = omitStop = localAvailable = languagesInstalled = preparedLanguages = NO;
    sent = [NSMutableArray array];
    maxUnits = [name isEqual:@"bing"] ? 2800 : [name isEqual:@"google"] ? 3500 : [name isEqual:@"deepl"] ? 16000 : 0;
}

static NSArray *ask(NSArray *texts, BOOL direct, NSString **error, UIView *view) {
    __block BOOL finished = NO;
    __block NSArray *result;
    __block NSString *problem;
    void (^done)(NSArray *, NSString *) = ^(NSArray *answer, NSString *failure) {
        CHECK(NSThread.isMainThread && !finished, @"completion must be once on main");
        result = answer; problem = failure; finished = YES;
    };
    if (direct && [provider isEqual:@"bing"]) SGBingTranslateTexts(texts, @"fr", done);
    else if (direct && [provider isEqual:@"google"]) SGGoogleTranslateTexts(texts, @"fr", done);
    else if (direct && [provider isEqual:@"deepl"]) SGDeepLTranslateTexts(texts, @"fr", done);
    else SGLyricsTranslateTexts(texts, @"fr", view, done);
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:60];
    while (!finished && deadline.timeIntervalSinceNow > 0) [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    CHECK(finished, @"%@ timed out", provider);
    if (error) *error = problem;
    return result;
}
static NSString *repeat(NSString *text, NSUInteger count) {
    return [@"" stringByPaddingToLength:text.length * count withString:text startingAtIndex:0];
}

static void checkWeb(void) {
    for (NSString *name in @[@"bing", @"google", @"deepl"]) {
        selectProvider(name);
        NSString *error;
        NSString *source = [NSString stringWithFormat:@"  %@\r\n\r\nCat rests.\n\nCat sings.  ", repeat(@"Cat sleeps. ", 1700)];
        NSString *expected = [NSString stringWithFormat:@"  %@\r\n\r\nChat rests.\n\nChat sings.  ", repeat(@"Chat sleeps. ", 1700)];
        NSArray *answer = ask(@[source, @"Cat"], YES, &error, nil);
        CHECK(!error && ([answer isEqual:@[expected, @"Chat"]]), @"%@ paragraph/sentence reassembly failed: %@", name, error);
        CHECK(sent.count > 3, @"%@ did not segment a long paragraph", name);
        // The end of a long sentence cannot cut an emoji's UTF-16 surrogate pair.
        NSString *unicode = [repeat(@"a", maxUnits - 1) stringByAppendingString:@"😀Cat"];
        answer = ask(@[unicode], YES, &error, nil);
        CHECK(!error && [answer.firstObject isEqual:[repeat(@"a", maxUnits - 1) stringByAppendingString:@"😀Chat"]],
              @"%@ long Unicode sentence was not reassembled", name);
        NSUInteger before = requests;
        answer = ask(@[repeat(@"x", 64001)], YES, &error, nil);
        CHECK(!answer && error.length && requests == before, @"%@ sent oversized prose", name);
        failAt = requests + 2;
        answer = ask(@[source, @"Cat"], YES, &error, nil);
        CHECK(!answer && error.length, @"%@ accepted an incomplete segment reply", name);
        failAt = 0;
        answer = ask(@[@"Cat"], YES, &error, nil);
        CHECK(!error && [answer.firstObject isEqual:@"Chat"], @"%@ could not retry", name);
    }
}

static void checkAI(void) {
    NSDictionary *reasons = @{@"openai": @[@"length", @"content_filter"],
        @"claude": @[@"max_tokens", @"refusal", @"tool_use", @"pause_turn"],
        @"gemini": @[@"MAX_TOKENS", @"SAFETY", @"RECITATION"]};
    for (NSString *name in @[@"openai", @"claude", @"gemini"]) {
        selectProvider(name);
        NSString *error;
        NSArray *answer = ask(@[@"Cat sleeps.", @"Cat"], NO, &error, nil);
        CHECK(!error && ([answer isEqual:@[@"Chat sleeps.", @"Chat"]]), @"%@ normal prose failed", name);
        for (NSString *reason in reasons[name]) {
            stopReason = reason;
            answer = ask(@[@"Cat sleeps.", @"Cat"], NO, &error, nil);
            CHECK(!answer && error.length, @"%@ accepted stop reason %@", name, reason);
        }
        stopReason = nil; omitStop = YES;
        CHECK(!ask(@[@"Cat"], NO, &error, nil) && error.length, @"%@ accepted missing completion metadata", name);
        omitStop = NO; refusal = YES;
        CHECK(!ask(@[@"Cat"], NO, &error, nil) && error.length, @"%@ accepted refusal metadata", name);
        refusal = NO;
        NSUInteger before = requests;
        CHECK(!ask(@[repeat(@"猫", 700)], NO, &error, nil) && error.length && requests == before,
              @"%@ paid for input beyond the output budget", name);
        CHECK([ask(@[@"Cat"], NO, &error, nil).firstObject isEqual:@"Chat"], @"%@ failure prevented retry", name);
        NSString *paragraph = repeat(@"Cat naps. ", 199), *translatedParagraph = repeat(@"Chat naps. ", 199);
        NSString *source = [[@[paragraph, paragraph, paragraph] componentsJoinedByString:@"\n\n"]
            stringByAppendingString:@"Cat rests in the shade.   "];
        NSString *expected = [[@[translatedParagraph, translatedParagraph, translatedParagraph] componentsJoinedByString:@"\n\n"]
            stringByAppendingString:@"Chat rests in the shade.   "];
        CHECK([source lengthOfBytesUsingEncoding:NSUTF8StringEncoding] == 6000, @"fixture must be 6,000 bytes");
        before = requests;
        answer = ask(@[source, @"Cat"], NO, &error, nil);
        CHECK(!error && ([answer isEqual:@[expected, @"Chat"]]) && requests > before + 1 && requests <= before + 16,
              @"%@ did not translate a 6,000-byte explanation in bounded segments: %@", name, error);
        before = requests; failAt = before + 2;
        CHECK(!ask(@[source, @"Cat"], NO, &error, nil) && error.length && requests == before + 2,
              @"%@ did not stop the whole explanation after one failing segment", name);
        failAt = 0; before = requests; metadataFailAt = before + 2;
        CHECK(!ask(@[source, @"Cat"], NO, &error, nil) && error.length && requests == before + 2,
              @"%@ accepted a cut answer in the middle of the explanation", name);
        metadataFailAt = 0; before = requests;
        NSMutableArray *paragraphs = [NSMutableArray array];
        for (NSUInteger i = 0; i < 17; i++) [paragraphs addObject:@"Cat sleeps."];
        CHECK(!ask(@[[paragraphs componentsJoinedByString:@"\n\n"]], NO, &error, nil) && error.length && requests == before,
              @"%@ exceeded the overall paid-call cap", name);
    }
}

static void checkOnDevice(void) {
    selectProvider(@"google");
    UIView *view = [UIView new];
    localAvailable = YES;
    NSString *error;
    NSArray *answer = ask(@[@"Cat"], NO, &error, view);
    CHECK([answer.firstObject isEqual:@"Chat"] && !error && preparedLanguages && presentingView == view && requests == 0,
          @"the manual on-device route did not prepare languages using the sheet view");
    // An unavailable Apple translator selects the configured online route, not a dead local route.
    localAvailable = NO;
    answer = ask(@[@"Cat"], NO, &error, view);
    CHECK([answer.firstObject isEqual:@"Chat"] && !error && requests == 1, @"online route not selected when Apple unavailable");
}

int main(void) {
    @autoreleasepool {
        method_exchangeImplementations(class_getClassMethod(NSURLSessionConfiguration.class, @selector(ephemeralSessionConfiguration)),
            class_getClassMethod(NSURLSessionConfiguration.class, @selector(proseConfiguration)));
        checkWeb(); checkAI(); checkOnDevice();
        printf("[harness] meaning providers: %lu checks passed\n", (unsigned long)checks);
    }
    return 0;
}
