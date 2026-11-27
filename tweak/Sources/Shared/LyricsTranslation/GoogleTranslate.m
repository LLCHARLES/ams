#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Shared/Lyrics/Lyrics.h"
#import "AIServicesInternal.h"

static NSMutableDictionary *sg_done;

NSString *SGGoogleTargetLanguage(NSString *tag) {
    if (![tag isKindOfClass:NSString.class] || !tag.length || tag.length > 64) return nil;
    NSString *clean = [tag stringByReplacingOccurrencesOfString:@"_" withString:@"-"];
    NSArray *parts = [clean.lowercaseString componentsSeparatedByString:@"-"];
    for (NSString *part in parts) {
        if (!part.length || [part rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyz0123456789"] invertedSet]].location != NSNotFound) return nil;
    }
    NSString *base = parts.firstObject;
    if ([base isEqualToString:@"zh"]) {
        if ([parts containsObject:@"hans"]) return @"zh-CN";
        if ([parts containsObject:@"hant"]) return @"zh-TW";
    }
    if ([base isEqualToString:@"he"]) return @"iw";
    if ([base isEqualToString:@"nb"]) return @"no";
    return clean;
}

BOOL SGGoogleKeepsLine(NSString *text) {
    if (![text isKindOfClass:NSString.class]) return NO;
    NSString *trimmed = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!trimmed.length) return NO;
    if ([trimmed stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"♪ \t"]].length == 0) return YES;
    if (trimmed.length < 3 || ![trimmed hasPrefix:@"["] || ![trimmed hasSuffix:@"]"]) return NO;
    NSString *inside = [trimmed substringWithRange:NSMakeRange(1, trimmed.length - 2)];
    return [inside rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"[]\r\n"]].location == NSNotFound;
}

NSArray<NSString *> *SGLyricsWebTexts(NSArray<SGKaraokeLine *> *lines, NSUInteger maxCharacters,
                                    NSMutableArray **send, NSMutableArray **out, BOOL *tooLong) {
    *tooLong = NO;
    if (![lines isKindOfClass:NSArray.class] || lines.count > 2000) return nil;
    NSMutableArray *texts = [NSMutableArray array];
    *send = [NSMutableArray array]; *out = [NSMutableArray array];
    NSUInteger total = 0;
    for (id line in lines) {
        if (![line isKindOfClass:SGKaraokeLine.class]) return nil;
        NSString *text = SGKaraokeLineText(line) ?: @"";
        total += text.length;
        if (text.length > maxCharacters || total > 128000) { *tooLong = YES; return nil; }
        BOOL keep = SGGoogleKeepsLine(text);
        [texts addObject:text]; [*send addObject:keep ? @"" : text]; [*out addObject:keep ? text : @""];
    }
    return texts;
}

NSString *SGGoogleTranslationTextIn(id root) {
    if (![root isKindOfClass:NSArray.class] || ![root count]) return nil;
    id segments = root[0];
    if (![segments isKindOfClass:NSArray.class] || ![segments count] || [segments count] > 4096) return nil;
    NSMutableString *text = [NSMutableString string];
    for (id segment in segments) {
        if (![segment isKindOfClass:NSArray.class] || ![segment count]) return nil;
        id translated = segment[0];
        if (![translated isKindOfClass:NSString.class] || [translated length] > 128000 - text.length) return nil;
        [text appendString:translated];
    }
    return [text copy];
}

NSArray<NSString *> *SGGoogleTranslationLinesIn(id root, NSUInteger count) {
    if (!count || count > 2000) return nil;
    NSString *text = SGGoogleTranslationTextIn(root);
    if (!text) return nil;
    // CRLF is one boundary, just as LF is. Do not trim: a missing or extra line needs another request.
    text = [[text stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"] stringByReplacingOccurrencesOfString:@"\r" withString:@"\n"];
    NSArray *lines = [text componentsSeparatedByString:@"\n"];
    return lines.count == count ? lines : nil;
}

NSData *SGGoogleTranslationForm(NSString *text, NSString *languageTag) {
    NSString *target = SGGoogleTargetLanguage(languageTag);
    if (!target || ![text isKindOfClass:NSString.class] || text.length > 3500) return nil;
    // Only unreserved bytes stay literal, so &, +, =, line breaks and non-Latin scripts cannot become fields.
    NSCharacterSet *safe = [NSCharacterSet characterSetWithCharactersInString:@"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"];
    NSString *encoded = [text stringByAddingPercentEncodingWithAllowedCharacters:safe];
    NSString *language = [target stringByAddingPercentEncodingWithAllowedCharacters:safe];
    if (!encoded || !language) return nil;
    return [[NSString stringWithFormat:@"client=gtx&sl=auto&tl=%@&dt=t&q=%@", language, encoded] dataUsingEncoding:NSUTF8StringEncoding];
}

static NSString *unreadable(void) {
    return SGL(@"settings.translation.google.error.unreadable", @"Google Translate's answer could not be read. Try again.");
}
static NSString *disabled(void) {
    return SGL(@"settings.translation.google.error.disabled", @"Turn on Google Translate in Lyrics › Translation & AI first.");
}

@interface SGGoogleTranslation : NSObject
@property (nonatomic, copy) NSString *target;
@property (nonatomic, copy) NSArray<NSString *> *texts;
@property (nonatomic, strong) NSMutableArray<NSArray<NSNumber *> *> *batches;
@property (nonatomic, strong) NSMutableArray<NSString *> *out;
@property (nonatomic) NSUInteger next, size;
@property (nonatomic, copy) void (^done)(NSArray<NSString *> *, NSString *);
- (void)advance;
@end

@implementation SGGoogleTranslation
- (void)advance {
    if (!SGFlag(SGKeyLyricsGoogleTranslate, NO)) { self.done(nil, disabled()); return; }
    if (self.next == self.batches.count) { self.done([self.out copy], nil); return; }
    NSArray<NSNumber *> *indices = self.batches[self.next++];
    NSMutableArray *texts = [NSMutableArray array];
    BOOL hasNewline = NO;
    for (NSNumber *index in indices) {
        NSString *text = self.texts[index.unsignedIntegerValue];
        [texts addObject:text];
        if ([text rangeOfCharacterFromSet:NSCharacterSet.newlineCharacterSet].location != NSNotFound) hasNewline = YES;
    }
    // A source line containing its own newline cannot be recovered by counting the joined boundaries.
    if (hasNewline && indices.count > 1) { [self splitBatch:indices]; return; }
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"https://translate.googleapis.com/translate_a/single"]];
    request.HTTPMethod = @"POST";
    request.timeoutInterval = 60;
    [request setValue:@"application/x-www-form-urlencoded; charset=UTF-8" forHTTPHeaderField:@"Content-Type"];
    request.HTTPBody = SGGoogleTranslationForm([texts componentsJoinedByString:@"\n"], self.target);
    if (!request.HTTPBody) { self.done(nil, unreadable()); return; }
    SGLyricsTranslationSendRequest(request, YES, ^BOOL { return SGFlag(SGKeyLyricsGoogleTranslate, NO); }, ^(NSData *data, NSInteger status, NSError *error) {
        if (!SGFlag(SGKeyLyricsGoogleTranslate, NO)) { self.done(nil, disabled()); return; }
        NSString *problem = nil;
        if (error) problem = SGL(@"settings.translation.google.error.unreachable", @"Google Translate could not be reached.");
        else if (status == 429 || (status >= 500 && status <= 599)) problem = SGL(@"settings.translation.google.error.busy", @"Google Translate is busy right now. Try again in a minute.");
        else if (status != 200) problem = [NSString stringWithFormat:SGL(@"settings.translation.google.error.status", @"Google Translate did not translate the song (%ld)."), (long)status];
        SGLog(@"google translate: %lu lines, status %ld", (unsigned long)indices.count, (long)status);
        if (problem) { self.done(nil, problem); return; }
        id root = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        NSString *text = SGGoogleTranslationTextIn(root);
        if (!text) { self.done(nil, unreadable()); return; }
        NSArray *translated = indices.count == 1 ? @[text] : SGGoogleTranslationLinesIn(root, indices.count);
        if (!translated) { [self splitBatch:indices]; return; }
        for (NSUInteger i = 0; i < indices.count; i++) {
            self.size += [translated[i] length];
            if (self.size > 256000) { self.done(nil, unreadable()); return; }
            self.out[indices[i].unsignedIntegerValue] = translated[i];
        }
        [self advance];
    });
}
- (void)splitBatch:(NSArray<NSNumber *> *)indices {
    // Replace only this batch, preserving every later index. A single-line reply needs no splitting.
    NSMutableArray *singles = [NSMutableArray array];
    for (NSNumber *index in indices) [singles addObject:@[index]];
    [self.batches insertObjects:singles atIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(self.next, singles.count)]];
    [self advance];
}
@end

// Runs the batches for texts already checked. `memo` is the song and language a kept answer belongs to; text that
// is not a song's lyrics passes nil, and nothing is kept for it.
static void startGoogle(NSString *target, NSArray<NSString *> *texts, NSMutableArray *out,
                        NSArray<NSArray<NSNumber *> *> *batches, NSString *memo, void (^done)(NSArray<NSString *> *, NSString *)) {
    SGGoogleTranslation *job = [SGGoogleTranslation new];
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

void SGLyricsTranslateWithGoogle(NSString *trackID, NSArray<SGKaraokeLine *> *lines, NSString *languageTag,
                                void (^done)(NSArray<NSString *> *, NSString *)) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!SGFlag(SGKeyLyricsGoogleTranslate, NO)) { done(nil, disabled()); return; }
        NSString *target = SGGoogleTargetLanguage(languageTag);
        if (!target) { done(nil, SGL(@"settings.translation.google.error.language", @"Choose a valid language for Google Translate.")); return; }
        NSMutableArray *send, *out;
        BOOL tooLong;
        NSArray *texts = SGLyricsWebTexts(lines, 3500, &send, &out, &tooLong);
        if (!texts) { done(nil, tooLong ? SGL(@"settings.translation.google.error.toolong", @"The song is too long to send to Google Translate.") : unreadable()); return; }
        NSArray *batches = SGLyricsTranslationBatches(send, 2000, 3500);
        if (!batches) { done(nil, unreadable()); return; }
        NSString *memo = trackID ? [NSString stringWithFormat:@"%@|%@", trackID, languageTag] : nil;
        NSDictionary *cached = memo ? sg_done[memo] : nil;
        if ([cached[@"texts"] isEqual:texts]) { done(cached[@"translations"], nil); return; }
        startGoogle(target, texts, out, batches, memo, done);
    });
}

// Text that is not a song's lyrics: the same endpoint and batching, with nothing kept for a later call.
void SGGoogleTranslateTexts(NSArray<NSString *> *texts, NSString *languageTag, void (^done)(NSArray<NSString *> *, NSString *)) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!SGFlag(SGKeyLyricsGoogleTranslate, NO)) { done(nil, disabled()); return; }
        NSString *target = SGGoogleTargetLanguage(languageTag);
        if (!target) { done(nil, SGL(@"settings.translation.google.error.language", @"Choose a valid language for Google Translate.")); return; }
        const NSUInteger maxTextUTF16Units = 3500;
        SGLyricsTranslateSegments(texts, maxTextUTF16Units, SGProseSegmentUTF16, ^(NSArray *segments, void (^finish)(NSArray *, NSString *)) {
            NSArray *batches = SGLyricsTranslationBatches(segments, 2000, maxTextUTF16Units);
            if (!batches) { finish(nil, unreadable()); return; }
            NSMutableArray *out = [NSMutableArray array];
            for (NSUInteger i = 0; i < segments.count; i++) [out addObject:@""];
            startGoogle(target, segments, out, batches, nil, finish);
        }, done);
    });
}

SGModRow *SGGoogleTranslateRow(void) {
    SGModRow *row = SGOptionRow(SGL(@"settings.translation.google.title", @"Google Translate"),
        SGL(@"settings.translation.google.subtitle", @"Sends the song's lyrics to Google Translate's public web endpoint"), SGKeyLyricsGoogleTranslate);
    row.changed = ^(BOOL on) {
        SGLyricsTranslationServiceSettingsChanged();
        dispatch_async(dispatch_get_main_queue(), ^{
            [NSNotificationCenter.defaultCenter postNotificationName:SGLyricsTranslationsDidChangeNotification object:nil];
        });
    };
    return row;
}
