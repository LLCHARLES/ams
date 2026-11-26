#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Shared/Lyrics/Lyrics.h"
#import "Shared/LyricsSources/LyricsSources.h"
#import "AIServicesInternal.h"

static NSMutableDictionary *sg_done;
// Accessed only on main, like the jobs and their result memo.
static NSDictionary *sg_configuration;
static NSTimeInterval sg_expires;
static NSUInteger sg_sequence;
static NSString *const sg_agent = @"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/150.0.0.0 Safari/537.36";

NSString *SGBingTargetLanguage(NSString *tag) {
    if (!SGGoogleTargetLanguage(tag)) return nil;
    NSArray *parts = [[[tag stringByReplacingOccurrencesOfString:@"_" withString:@"-"] lowercaseString] componentsSeparatedByString:@"-"];
    NSString *base = parts.firstObject;
    if ([base isEqualToString:@"zh"]) {
        if ([parts containsObject:@"hans"]) return @"zh-Hans";
        if ([parts containsObject:@"hant"]) return @"zh-Hant";
        if ([parts containsObject:@"cn"]) return @"zh-Hans";
        if ([parts containsObject:@"tw"]) return @"zh-Hant";
    }
    if ([base isEqualToString:@"pt"] && parts.count > 1 && [parts[1] isEqualToString:@"pt"]) return @"pt-PT";
    return base;
}

static NSString *capture(NSString *html, NSString *pattern) {
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil];
    NSTextCheckingResult *match = [regex firstMatchInString:html options:0 range:NSMakeRange(0, html.length)];
    return match ? [html substringWithRange:[match rangeAtIndex:1]] : nil;
}
static BOOL number(id value) {
    return [value isKindOfClass:NSNumber.class] && CFGetTypeID((__bridge CFTypeRef)value) != CFBooleanGetTypeID();
}
NSDictionary *SGBingConfigurationIn(NSString *html) {
    if (![html isKindOfClass:NSString.class] || html.length > 2 * 1024 * 1024) return nil;
    NSString *ig = capture(html, @"IG:\\s*\"([^\"]+)\"");
    NSString *iid = capture(html, @"data-iid=\"([^\"]+)\"");
    NSString *raw = capture(html, @"params_AbusePreventionHelper\\s*=\\s*(\\[[^\\]]+\\])");
    if (!ig.length || ig.length > 1024 || !iid.length || iid.length > 1024 || !raw || raw.length > 8192) return nil;
    id tuple = [NSJSONSerialization JSONObjectWithData:[raw dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
    if (![tuple isKindOfClass:NSArray.class] || [tuple count] < 2 || [tuple count] > 3 || !number(tuple[0])) return nil;
    // Scan the decimal representation so fractions and values outside signed 64-bit cannot wrap.
    NSString *keyText = [tuple[0] stringValue];
    if ([keyText rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"0123456789"].invertedSet].location != NSNotFound) return nil;
    NSScanner *scanner = [NSScanner scannerWithString:keyText];
    long long key = 0;
    if (![scanner scanLongLong:&key] || !scanner.isAtEnd || key <= 0 || ![keyText isEqualToString:[@(key) stringValue]]) return nil;
    id token = tuple[1];
    if (![token isKindOfClass:NSString.class] || ![token length] || [token length] > 4096) return nil;
    double seconds = 600;
    if ([tuple count] == 3) {
        if (!number(tuple[2]) || !isfinite([tuple[2] doubleValue]) || [tuple[2] doubleValue] < 0) return nil;
        seconds = MAX(60, [tuple[2] doubleValue] / 1000.0);
    }
    return @{@"ig": ig, @"iid": iid, @"key": @(key), @"token": token, @"seconds": @(seconds)};
}

NSString *SGBingTranslationTextIn(id root) {
    if (![root isKindOfClass:NSArray.class] || ![root count]) return nil;
    id first = root[0];
    id translations = [first isKindOfClass:NSDictionary.class] ? first[@"translations"] : nil;
    if (![translations isKindOfClass:NSArray.class] || ![translations count]) return nil;
    id entry = translations[0];
    id text = [entry isKindOfClass:NSDictionary.class] ? entry[@"text"] : nil;
    if (![text isKindOfClass:NSString.class] || [text length] > 128000) return nil;
    text = [[text stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"] stringByReplacingOccurrencesOfString:@"\r" withString:@"\n"];
    NSMutableArray *lines = [NSMutableArray array];
    for (NSString *line in [text componentsSeparatedByString:@"\n"]) {
        NSUInteger end = line.length;
        while (end && [NSCharacterSet.whitespaceCharacterSet characterIsMember:[line characterAtIndex:end - 1]]) end--;
        [lines addObject:[line substringToIndex:end]];
    }
    return [lines componentsJoinedByString:@"\n"];
}
BOOL SGBingTokenRefused(id root) {
    return [root isKindOfClass:NSDictionary.class] && root[@"statusCode"] != nil;
}

static NSString *unreadable(void) {
    return SGL(@"settings.translation.bing.error.unreadable", @"Bing Translator's answer could not be read. Try again.");
}
static NSString *disabled(void) {
    return SGL(@"settings.translation.bing.error.disabled", @"Turn on Bing Translator in Lyrics › Translation & AI first.");
}
static NSString *problemFor(NSInteger status, BOOL failed) {
    if (failed) return SGL(@"settings.translation.bing.error.unreachable", @"Bing Translator could not be reached.");
    if (status == 429 || (status >= 500 && status <= 599)) return SGL(@"settings.translation.bing.error.busy", @"Bing Translator is busy right now. Try again in a minute.");
    if (status != 200) return [NSString stringWithFormat:SGL(@"settings.translation.bing.error.status", @"Bing Translator did not translate the song (%ld)."), (long)status];
    return nil;
}
static NSString *encode(NSString *text) {
    return [text stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet characterSetWithCharactersInString:@"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"]];
}

@interface SGBingTranslation : NSObject
@property (nonatomic, copy) NSString *target;
@property (nonatomic, copy) NSArray<NSString *> *texts;
@property (nonatomic, strong) NSMutableArray<NSArray<NSNumber *> *> *batches;
@property (nonatomic, strong) NSMutableArray<NSString *> *out;
@property (nonatomic) NSUInteger next, size;
@property (nonatomic, copy) void (^done)(NSArray<NSString *> *, NSString *);
- (void)advance;
@end

@implementation SGBingTranslation
- (void)finish:(NSArray *)translated error:(NSString *)problem {
    void (^done)(NSArray *, NSString *) = self.done;
    self.done = nil;
    if (done) done(translated, problem);
}
- (void)advance {
    if (!self.done) return;
    if (!SGFlag(SGKeyLyricsBingTranslate, NO)) { [self finish:nil error:disabled()]; return; }
    if (self.next == self.batches.count) { [self finish:[self.out copy] error:nil]; return; }
    NSArray<NSNumber *> *indices = self.batches[self.next++];
    for (NSNumber *index in indices) {
        if (indices.count > 1 && [self.texts[index.unsignedIntegerValue] rangeOfCharacterFromSet:NSCharacterSet.newlineCharacterSet].location != NSNotFound) {
            [self splitBatch:indices]; return;
        }
    }
    [self send:indices retried:NO];
}
- (void)send:(NSArray<NSNumber *> *)indices retried:(BOOL)retried {
    if (!self.done) return;
    if (!SGFlag(SGKeyLyricsBingTranslate, NO)) { [self finish:nil error:disabled()]; return; }
    if (!sg_configuration || NSProcessInfo.processInfo.systemUptime >= sg_expires) {
        SGLyricsSourceRequest([NSURL URLWithString:@"https://www.bing.com/translator"],
            @{@"User-Agent": sg_agent, @"Accept": @"text/html"}, nil, ^(NSData *data, NSInteger status) {
            if (!SGFlag(SGKeyLyricsBingTranslate, NO)) { [self finish:nil error:disabled()]; return; }
            NSString *problem = problemFor(status, !data);
            NSDictionary *configuration = !problem ? SGBingConfigurationIn([[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]) : nil;
            if (!configuration) { [self finish:nil error:problem ?: unreadable()]; return; }
            sg_configuration = configuration;
            sg_expires = NSProcessInfo.processInfo.systemUptime + [configuration[@"seconds"] doubleValue] - 30;
            [self send:indices retried:retried];
        });
        return;
    }
    NSDictionary *configuration = sg_configuration;
    NSMutableArray *texts = [NSMutableArray array];
    for (NSNumber *index in indices) [texts addObject:self.texts[index.unsignedIntegerValue]];
    NSString *url = [NSString stringWithFormat:@"https://www.bing.com/ttranslatev3?isVertical=1&&IG=%@&IID=%@&SFX=%lu&ref=TThis&edgepdftranslator=1",
        encode(configuration[@"ig"]), encode(configuration[@"iid"]), (unsigned long)++sg_sequence];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]];
    request.HTTPMethod = @"POST";
    request.timeoutInterval = 60;
    [request setValue:@"application/x-www-form-urlencoded;charset=UTF-8" forHTTPHeaderField:@"Content-Type"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    [request setValue:@"https://www.bing.com" forHTTPHeaderField:@"Origin"];
    [request setValue:@"https://www.bing.com/translator" forHTTPHeaderField:@"Referer"];
    [request setValue:sg_agent forHTTPHeaderField:@"User-Agent"];
    NSString *text = encode([texts componentsJoinedByString:@"\n"]), *token = encode(configuration[@"token"]), *target = encode(self.target);
    if (!text || !token || !target) { [self finish:nil error:unreadable()]; return; }
    request.HTTPBody = [[NSString stringWithFormat:@"fromLang=auto-detect&text=%@&token=%@&key=%@&to=%@&tryFetchingGenderDebiasedTranslations=false",
        text, token, configuration[@"key"], target] dataUsingEncoding:NSUTF8StringEncoding];
    if (!request.HTTPBody || request.HTTPBody.length > 128 * 1024) { [self finish:nil error:unreadable()]; return; }
    SGLyricsTranslationSendRequest(request, YES, ^BOOL { return SGFlag(SGKeyLyricsBingTranslate, NO); }, ^(NSData *data, NSInteger status, NSError *error) {
        if (!SGFlag(SGKeyLyricsBingTranslate, NO)) { [self finish:nil error:disabled()]; return; }
        NSString *problem = problemFor(status, error != nil);
        SGLog(@"bing translate: %lu lines, status %ld", (unsigned long)indices.count, (long)status);
        if (problem) { [self finish:nil error:problem]; return; }
        id root = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        if (SGBingTokenRefused(root)) {
            // A concurrent job may already have replaced the configuration this reply refused.
            if (sg_configuration == configuration) { sg_configuration = nil; sg_expires = 0; }
            if (!retried) { [self send:indices retried:YES]; return; }
            [self finish:nil error:SGL(@"settings.translation.bing.error.token", @"Bing Translator refused its web token. Try again in a minute.")]; return;
        }
        NSString *text = SGBingTranslationTextIn(root);
        if (!text) { [self finish:nil error:unreadable()]; return; }
        NSArray *translated = indices.count == 1 ? @[text] : [text componentsSeparatedByString:@"\n"];
        if (translated.count != indices.count) { [self splitBatch:indices]; return; }
        for (NSUInteger i = 0; i < indices.count; i++) {
            self.size += [translated[i] length];
            if (self.size > 256000) { [self finish:nil error:unreadable()]; return; }
            self.out[indices[i].unsignedIntegerValue] = translated[i];
        }
        [self advance];
    });
}
- (void)splitBatch:(NSArray<NSNumber *> *)indices {
    NSMutableArray *singles = [NSMutableArray array];
    for (NSNumber *index in indices) [singles addObject:@[index]];
    [self.batches insertObjects:singles atIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(self.next, singles.count)]];
    [self advance];
}
@end

// Runs the batches for texts already checked. `memo` is the song and language a kept answer belongs to; text that
// is not a song's lyrics passes nil, and nothing is kept for it.
static void startBing(NSString *target, NSArray<NSString *> *texts, NSMutableArray *out,
                      NSArray<NSArray<NSNumber *> *> *batches, NSString *memo, void (^done)(NSArray<NSString *> *, NSString *)) {
    SGBingTranslation *job = [SGBingTranslation new];
    job.target = target; job.texts = texts; job.out = out; job.batches = [batches mutableCopy];
    job.done = ^(NSArray *translated, NSString *problem) {
        if (translated && memo) {
            if (!sg_done) sg_done = [NSMutableDictionary dictionary];
            if (sg_done.count >= 32) [sg_done removeAllObjects];
            sg_done[memo] = @{@"texts": [texts copy], @"translations": translated};
        }
        done(translated, problem);
    };
    [job advance];
}

void SGLyricsTranslateWithBing(NSString *trackID, NSArray<SGKaraokeLine *> *lines, NSString *languageTag,
                              void (^done)(NSArray<NSString *> *, NSString *)) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!SGFlag(SGKeyLyricsBingTranslate, NO)) { done(nil, disabled()); return; }
        NSString *target = SGBingTargetLanguage(languageTag);
        if (!target) { done(nil, SGL(@"settings.translation.bing.error.language", @"Choose a valid language for Bing Translator.")); return; }
        NSMutableArray *send, *out;
        BOOL tooLong;
        NSArray *texts = SGLyricsWebTexts(lines, 2800, &send, &out, &tooLong);
        if (!texts) { done(nil, tooLong ? SGL(@"settings.translation.bing.error.toolong", @"The song is too long to send to Bing Translator.") : unreadable()); return; }
        NSArray *batches = SGLyricsTranslationBatches(send, 40, 2800);
        if (!batches) { done(nil, unreadable()); return; }
        NSString *memo = trackID ? [NSString stringWithFormat:@"%@|%@", trackID, languageTag] : nil;
        NSDictionary *cached = memo ? sg_done[memo] : nil;
        if ([cached[@"texts"] isEqual:texts]) { done(cached[@"translations"], nil); return; }
        startBing(target, texts, out, batches, memo, done);
    });
}

// Text that is not a song's lyrics: the same web translation, with nothing kept for a later call.
void SGBingTranslateTexts(NSArray<NSString *> *texts, NSString *languageTag, void (^done)(NSArray<NSString *> *, NSString *)) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!SGFlag(SGKeyLyricsBingTranslate, NO)) { done(nil, disabled()); return; }
        NSString *target = SGBingTargetLanguage(languageTag);
        if (!target) { done(nil, SGL(@"settings.translation.bing.error.language", @"Choose a valid language for Bing Translator.")); return; }
        const NSUInteger maxTextUTF16Units = 2800;
        SGLyricsTranslateSegments(texts, maxTextUTF16Units, SGProseSegmentUTF16, ^(NSArray *segments, void (^finish)(NSArray *, NSString *)) {
            NSArray *batches = SGLyricsTranslationBatches(segments, 40, maxTextUTF16Units);
            if (!batches) { finish(nil, unreadable()); return; }
            NSMutableArray *out = [NSMutableArray array];
            for (NSUInteger i = 0; i < segments.count; i++) [out addObject:@""];
            startBing(target, segments, out, batches, nil, finish);
        }, done);
    });
}

SGModRow *SGBingTranslateRow(void) {
    SGModRow *row = SGOptionRow(SGL(@"settings.translation.bing.title", @"Bing Translator"),
        SGL(@"settings.translation.bing.subtitle", @"Sends the song's lyrics to Bing Translator's public web page"), SGKeyLyricsBingTranslate);
    row.changed = ^(BOOL on) {
        SGLyricsTranslationServiceSettingsChanged();
        dispatch_async(dispatch_get_main_queue(), ^{
            [NSNotificationCenter.defaultCenter postNotificationName:SGLyricsTranslationsDidChangeNotification object:nil];
        });
    };
    return row;
}
