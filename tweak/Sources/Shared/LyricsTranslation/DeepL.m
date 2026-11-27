#import <Security/Security.h>
#import "Core/SGKeychain.h"
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Settings/SGPageStyle.h"
#import "Shared/Lyrics/Lyrics.h"
#import "AIServicesInternal.h"
#import "CredentialSettings.h"

// Stable Keychain service for existing keys, including deletion.
static NSString *const kService = @"Vitrine.DeepL", *const kAccount = @"api-key";
static NSMutableDictionary *sg_done;

#pragma mark - replies and batches

NSString *SGDeepLTargetLanguage(NSString *tag) {
    if (![tag isKindOfClass:NSString.class] || !tag.length || tag.length > 64) return nil;
    NSString *upper = [[tag stringByReplacingOccurrencesOfString:@"_" withString:@"-"] uppercaseString];
    NSArray *parts = [upper componentsSeparatedByString:@"-"];
    for (NSString *part in parts) {
        if (!part.length || [part rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"] invertedSet]].location != NSNotFound) return nil;
    }
    NSString *base = parts.firstObject;
    if ([base isEqualToString:@"ZH"]) {
        if ([parts containsObject:@"HANT"]) return @"ZH-HANT";
        if ([parts containsObject:@"HANS"]) return @"ZH-HANS";
    }
    if ([base isEqualToString:@"EN"]) return [parts containsObject:@"GB"] ? @"EN-GB" : @"EN-US";
    if ([base isEqualToString:@"PT"]) return parts.count > 1 && [parts[1] isEqualToString:@"PT"] ? @"PT-PT" : @"PT-BR";
    // DeepL's text languages, from its supported-languages table. Unknown tags stay off the wire.
    static NSSet *supported;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        supported = [NSSet setWithArray:[@"ACE AF SQ AR AN HY AS AY AZ BA EU BE BN BHO BS BR BG MY YUE CA CEB ZH HR CS DA PRS NL EO ET FI FR GL KA DE EL GN GU HT HA HE HI HU IS IG ID GA IT JA JV PAM KK GOM KO KMR CKB KY LA LV LN LT LMO LB MK MAI MG MS ML MT MI MR MN NE NB OC OM PAG PS FA PL PA QU RO RU SA SR ST SCN SK SL ES SU SW SV TL TG TA TT TE TH TS TN TR TK UK UR UZ VI CY WO XH YI ZU" componentsSeparatedByString:@" "]];
    });
    return [supported containsObject:base] ? base : nil;
}

NSArray<NSArray<NSNumber *> *> *SGLyricsTranslationBatches(NSArray<NSString *> *texts, NSUInteger maxLines, NSUInteger maxCharacters) {
    if (![texts isKindOfClass:NSArray.class] || texts.count > 2000 || !maxLines || !maxCharacters || maxCharacters > 128000) return nil;
    NSMutableArray *batches = [NSMutableArray array], *batch = [NSMutableArray array];
    NSUInteger length = 0, total = 0;
    for (NSUInteger i = 0; i < texts.count; i++) {
        id text = texts[i];
        if (![text isKindOfClass:NSString.class] || [text length] > maxCharacters) return nil;
        total += [text length];
        if (total > 128000) return nil;
        if (![[text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] length]) continue;
        NSUInteger added = [text length] + (batch.count ? 1 : 0);
        if (batch.count && (batch.count == maxLines || added > maxCharacters - length)) {
            [batches addObject:[batch copy]];
            [batch removeAllObjects];
            length = 0;
        }
        length += [text length] + (batch.count ? 1 : 0);
        [batch addObject:@(i)];
    }
    if (batch.count) [batches addObject:[batch copy]];
    return [batches copy];
}

NSArray<NSString *> *SGDeepLTranslationsIn(id root, NSUInteger count) {
    if (![root isKindOfClass:NSDictionary.class] || count > 50) return nil;
    id translations = root[@"translations"];
    if (![translations isKindOfClass:NSArray.class] || [translations count] != count) return nil;
    NSMutableArray *out = [NSMutableArray array];
    NSUInteger size = 0;
    for (id entry in translations) {
        id text = [entry isKindOfClass:NSDictionary.class] ? entry[@"text"] : nil;
        if (![text isKindOfClass:NSString.class] || [text length] > 64000) return nil;
        size += [text length];
        if (size > 128000) return nil;
        [out addObject:text];
    }
    return [out copy];
}

#pragma mark - bounded requests

// Both providers stop receiving at 512 KiB (`limit`; a model list allows more), including a reply whose length
// was not announced. A fresh ephemeral session keeps lyrics out of the disk cache, and redirects cannot carry a
// key to another host.
@interface SGLyricsTranslationRequest : NSObject <NSURLSessionDataDelegate>
@property (nonatomic, strong) NSMutableData *data;
@property (nonatomic) NSInteger status;
@property (nonatomic) NSUInteger limit;
@property (nonatomic, copy) void (^finished)(NSData *, NSInteger, NSError *);
@end

@implementation SGLyricsTranslationRequest
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveResponse:(NSURLResponse *)response
 completionHandler:(void (^)(NSURLSessionResponseDisposition))completion {
    self.status = [response isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)response).statusCode : 0;
    completion(response.expectedContentLength > (long long)self.limit ? NSURLSessionResponseCancel : NSURLSessionResponseAllow);
}
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveData:(NSData *)data {
    if (data.length > self.limit - self.data.length) { [task cancel]; return; }
    [self.data appendData:data];
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task willPerformHTTPRedirection:(NSHTTPURLResponse *)response
       newRequest:(NSURLRequest *)request completionHandler:(void (^)(NSURLRequest *))completion {
    completion(nil);
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    void (^finished)(NSData *, NSInteger, NSError *) = self.finished;
    self.finished = nil;
    [session finishTasksAndInvalidate];
    finished(error ? nil : [self.data copy], self.status, error);
}
@end

NSURLSessionDataTask *SGLyricsTranslationSendOnce(NSURLRequest *request, void (^finished)(NSData *, NSInteger, NSError *)) {
    return SGLyricsTranslationSendOnceUpTo(request, 512 * 1024, finished);
}

NSURLSessionDataTask *SGLyricsTranslationSendOnceUpTo(NSURLRequest *request, NSUInteger limit, void (^finished)(NSData *, NSInteger, NSError *)) {
    SGLyricsTranslationRequest *receiver = [SGLyricsTranslationRequest new];
    receiver.data = [NSMutableData data]; receiver.finished = finished; receiver.limit = limit;
    NSURLSessionConfiguration *config = NSURLSessionConfiguration.ephemeralSessionConfiguration;
    config.URLCache = nil; config.HTTPCookieStorage = nil; config.URLCredentialStorage = nil;
    config.HTTPShouldSetCookies = NO; config.timeoutIntervalForResource = 20;
    NSMutableURLRequest *bounded = [request mutableCopy];
    bounded.timeoutInterval = 20; bounded.HTTPShouldHandleCookies = NO;
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config delegate:receiver delegateQueue:NSOperationQueue.mainQueue];
    NSURLSessionDataTask *task = [session dataTaskWithRequest:bounded];
    [task resume];
    return task;
}

static void sendRequest(NSURLRequest *request, BOOL retryServer, BOOL (^allowed)(void), NSUInteger attempt,
                        void (^finished)(NSData *, NSInteger, NSError *)) {
    if (allowed && !allowed()) {
        finished(nil, 0, [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCancelled userInfo:nil]);
        return;
    }
    SGLyricsTranslationRequest *receiver = [SGLyricsTranslationRequest new];
    receiver.data = [NSMutableData data];
    receiver.limit = 512 * 1024;
    receiver.finished = ^(NSData *data, NSInteger status, NSError *error) {
        if (!error && attempt < 3 && (status == 429 || (retryServer && status >= 500 && status <= 599))) {
            double delay = (double)(1 << attempt) * (0.75 + arc4random_uniform(500) / 1000.0);
            SGLog(@"translation: %ld, asking again in %.1f s", (long)status, delay);
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                sendRequest(request, retryServer, allowed, attempt + 1, finished);
            });
            return;
        }
        finished(data, status, error);
    };
    NSURLSessionConfiguration *config = NSURLSessionConfiguration.ephemeralSessionConfiguration;
    config.URLCache = nil;
    config.HTTPShouldSetCookies = NO;
    // A Gemini job's chosen timeout (30–300 s) bounds the whole job; every other caller asks for 60 s or less.
    config.timeoutIntervalForResource = MAX(60, request.timeoutInterval);
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config delegate:receiver delegateQueue:NSOperationQueue.mainQueue];
    [[session dataTaskWithRequest:request] resume];
}

void SGLyricsTranslationSendRequest(NSURLRequest *request, BOOL retryServer, BOOL (^allowed)(void),
                                   void (^finished)(NSData *, NSInteger, NSError *)) {
    sendRequest(request, retryServer, allowed, 0, finished);
}

#pragma mark - the key

static NSDictionary *keyQuery(void) {
    return @{(__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
             (__bridge id)kSecAttrService: kService, (__bridge id)kSecAttrAccount: kAccount};
}
// Bumped before every save, Remove and Clear of the key, also when the Keychain refuses; a job holds the one its
// key was read under, and drops its next batch, its retry and its kept answer once it is no longer current.
// Main queue only: sendRequest's retry timer and its completions run there.
static NSUInteger sg_credentialGeneration;
static NSNumber *sg_keyAvailable;
static NSString *storedKey(void) {
    NSMutableDictionary *query = [keyQuery() mutableCopy];
    query[(__bridge id)kSecReturnData] = @YES;
    query[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitOne;
    CFTypeRef data = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &data);
    id value = CFBridgingRelease(data);
    sg_keyAvailable = (status == errSecSuccess || status == errSecItemNotFound) ? @NO : nil;
    if (status != errSecSuccess || ![value isKindOfClass:NSData.class] || [value length] > 1024) return nil;
    NSString *key = [[NSString alloc] initWithData:value encoding:NSUTF8StringEncoding];
    BOOL valid = key.length && [key rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location == NSNotFound;
    sg_keyAvailable = @(valid);
    return valid ? key : nil;
}
// NO when the Keychain refused: a removed key is still stored then, and the caller says so.
static BOOL storeKey(NSString *key) {
    sg_credentialGeneration++;
    sg_keyAvailable = nil;
    [sg_done removeAllObjects];
    OSStatus status = SGStoreDeviceKey(keyQuery(), key);
    if (status != errSecSuccess) SGLog(@"deepl: the key could not be kept (%d)", (int)status);
    return status == errSecSuccess;
}
BOOL SGDeepLKeySet(void) { return sg_keyAvailable ? sg_keyAvailable.boolValue : storedKey() != nil; }
// Clear Keychain: the service's own items go, every account in it; answers kept for the launch go too.
BOOL SGDeepLForgetKey(void) {
    sg_credentialGeneration++;
    sg_keyAvailable = nil;
    [sg_done removeAllObjects];
    OSStatus status = SecItemDelete((__bridge CFDictionaryRef)@{(__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
                                                                (__bridge id)kSecAttrService: kService});
    if (status != errSecSuccess && status != errSecItemNotFound) SGLog(@"deepl: the keys could not be cleared (%d)", (int)status);
    return status == errSecSuccess || status == errSecItemNotFound;
}

#pragma mark - asking

static NSString *unreadable(void) {
    return SGL(@"settings.translation.deepl.error.unreadable", @"DeepL's answer could not be read. Try again.");
}

@interface SGDeepLTranslation : NSObject
@property (nonatomic, copy) NSString *key, *target;
@property (nonatomic, copy) NSArray<NSString *> *texts;
@property (nonatomic, copy) NSArray<NSArray<NSNumber *> *> *batches;
@property (nonatomic, strong) NSMutableArray<NSString *> *out;
@property (nonatomic) NSUInteger next, size, generation;
@property (nonatomic, copy) void (^done)(NSArray<NSString *> *, NSString *);
- (void)advance;
@end

@implementation SGDeepLTranslation
- (void)advance {
    if (self.next == self.batches.count) { self.done([self.out copy], nil); return; }
    NSArray<NSNumber *> *indices = self.batches[self.next++];
    NSMutableArray *texts = [NSMutableArray array];
    for (NSNumber *index in indices) [texts addObject:self.texts[index.unsignedIntegerValue]];
    NSString *endpoint = [self.key hasSuffix:@":fx"] ? @"https://api-free.deepl.com/v2/translate" : @"https://api.deepl.com/v2/translate";
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:endpoint]];
    request.HTTPMethod = @"POST";
    request.timeoutInterval = 60;
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request setValue:[@"DeepL-Auth-Key " stringByAppendingString:self.key] forHTTPHeaderField:@"Authorization"];
    request.HTTPBody = [NSJSONSerialization dataWithJSONObject:@{@"text": texts, @"target_lang": self.target} options:0 error:nil];
    if (!request.HTTPBody || request.HTTPBody.length > 128 * 1024) { self.done(nil, unreadable()); return; }
    SGLyricsTranslationSendRequest(request, NO, ^BOOL { return self.generation == sg_credentialGeneration; }, ^(NSData *data, NSInteger status, NSError *error) {
        if (self.generation != sg_credentialGeneration) { self.done(nil, SGLyricsKeyChangedProblem()); return; }
        NSString *problem = nil;
        NSArray *translated = nil;
        if (error) problem = SGL(@"settings.translation.deepl.error.unreachable", @"DeepL could not be reached.");
        else if (status == 403 || status == 401) problem = SGL(@"settings.translation.deepl.error.keyinvalid", @"DeepL turned the key down. Check it in Lyrics › Translation & AI.");
        else if (status == 456) problem = SGL(@"settings.translation.deepl.error.quota", @"This DeepL key's translation quota is used up.");
        else if (status == 429) problem = SGL(@"settings.translation.deepl.error.busy", @"DeepL is busy right now. Try again in a minute.");
        else if (status != 200) problem = [NSString stringWithFormat:SGL(@"settings.translation.deepl.error.status", @"DeepL did not translate the song (%ld)."), (long)status];
        else {
            id root = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
            translated = SGDeepLTranslationsIn(root, indices.count);
            if (!translated) problem = unreadable();
        }
        SGLog(@"deepl: %lu lines, status %ld, %@", (unsigned long)indices.count, (long)status, translated ? @"translated" : @"failed");
        if (problem) { self.done(nil, problem); return; }
        for (NSUInteger i = 0; i < indices.count; i++) {
            self.size += [translated[i] length];
            if (self.size > 256000) { self.done(nil, unreadable()); return; }
            self.out[indices[i].unsignedIntegerValue] = translated[i];
        }
        [self advance];
    });
}
@end

// Runs the job for texts already checked. `memo` is the song and language a kept answer belongs to; prose that is
// not a song's lyrics passes nil, and nothing is kept for it.
static void startDeepL(NSString *key, NSString *target, NSArray<NSString *> *texts,
                       NSArray<NSArray<NSNumber *> *> *batches, NSString *memo,
                       void (^done)(NSArray<NSString *> *, NSString *)) {
    NSMutableArray *out = [NSMutableArray array];
    for (NSUInteger i = 0; i < texts.count; i++) [out addObject:@""];
    SGDeepLTranslation *job = [SGDeepLTranslation new];
    job.generation = sg_credentialGeneration;   // the key was read in this ask, on main
    job.key = key; job.target = target; job.texts = texts; job.out = out; job.batches = batches;
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

void SGLyricsTranslateWithDeepL(NSString *trackID, NSArray<SGKaraokeLine *> *lines, NSString *languageTag,
                               void (^done)(NSArray<NSString *> *, NSString *)) {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *key = storedKey(), *target = SGDeepLTargetLanguage(languageTag);
        if (!key) { done(nil, SGL(@"settings.translation.deepl.error.nokey", @"Add a DeepL API key in Lyrics › Translation & AI first.")); return; }
        if (!target) { done(nil, SGL(@"settings.translation.deepl.error.language", @"DeepL does not support this translation language.")); return; }
        if (![lines isKindOfClass:NSArray.class] || lines.count > 2000) { done(nil, unreadable()); return; }
        NSMutableArray *texts = [NSMutableArray array];
        for (id line in lines) {
            if (![line isKindOfClass:SGKaraokeLine.class]) { done(nil, unreadable()); return; }
            [texts addObject:SGKaraokeLineText(line) ?: @""];
        }
        NSArray *batches = SGLyricsTranslationBatches(texts, 50, 16000);
        if (!batches) { done(nil, SGL(@"settings.translation.deepl.error.toolong", @"The song is too long to send to DeepL.")); return; }
        NSString *memo = trackID ? [NSString stringWithFormat:@"%@|%@", trackID, languageTag] : nil;
        NSDictionary *cached = memo ? sg_done[memo] : nil;
        if ([cached[@"texts"] isEqual:texts]) { done(cached[@"translations"], nil); return; }
        startDeepL(key, target, texts, batches, memo, done);
    });
}

void SGDeepLTranslateTexts(NSArray<NSString *> *texts, NSString *languageTag, void (^done)(NSArray<NSString *> *, NSString *)) {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *key = storedKey(), *target = SGDeepLTargetLanguage(languageTag);
        if (!key) { done(nil, SGL(@"settings.translation.deepl.error.nokey", @"Add a DeepL API key in Lyrics › Translation & AI first.")); return; }
        if (!target) { done(nil, SGL(@"settings.translation.deepl.error.language", @"DeepL does not support this translation language.")); return; }
        const NSUInteger maxTextUTF16Units = 16000;
        SGLyricsTranslateSegments(texts, maxTextUTF16Units, SGProseSegmentUTF16, ^(NSArray *segments, void (^finish)(NSArray *, NSString *)) {
            NSArray *batches = SGLyricsTranslationBatches(segments, 50, maxTextUTF16Units);
            if (!batches) { finish(nil, SGLyricsProseTooLong()); return; }
            startDeepL(key, target, segments, batches, nil, finish);
        }, done);
    });
}

#pragma mark - the row

static NSString *cleanKey(NSString *text) {
    return SGLyricsCleanCredential(text, 1024);
}
static void askForKey(void) {
    SGLyricsCredentialPrompt(SGL(@"settings.translation.deeplkey.title", @"DeepL API key"),
        SGL(@"settings.translation.deeplkey.message", @"Translate with DeepL sends the song's lyrics to DeepL, on your own key from deepl.com/your-account/keys. The key stays on this iPhone."),
        SGL(@"settings.translation.deeplkey.placeholder", @"API key"),
        ^BOOL(NSString *text) { return cleanKey(text).length > 0; }, ^(NSString *text) {
        NSString *key = cleanKey(text);
        if (!key.length || [storedKey() isEqualToString:key]) return;   // the same key again changes nothing, so no job is cut off
        if (storeKey(key)) SGLyricsTranslationServiceSettingsChanged(); else SGLyricsAlertKeyNotSaved();
    }, ^BOOL { return SGDeepLKeySet(); }, ^{ if (storeKey(nil)) SGLyricsTranslationServiceSettingsChanged(); else SGLyricsAlertKeyNotRemoved(); });
}
SGModRow *SGDeepLKeyRow(void) {
    return SGStatActionRow(SGL(@"settings.translation.deeplkey.title", @"DeepL API key"),
        SGL(@"settings.translation.deeplkey.subtitle", @"Translate any song with your own DeepL key"),
        ^NSString *{ return SGDeepLKeySet() ? SGL(@"settings.translation.deeplkey.set", @"Set") : SGL(@"common.off", @"Off"); }, ^{ askForKey(); });
}
