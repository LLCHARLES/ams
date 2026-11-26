#import <Security/Security.h>
#import "Core/SGKeychain.h"
#import <stdatomic.h>
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Settings/SGPageStyle.h"
#import "Shared/Lyrics/Lyrics.h"
#import "Shared/LyricsSources/LyricsSources.h"
#import "Shared/LocalFiles/LocalFiles.h"
#import "Headers/SPTPlayer.h"
#import "AIServicesInternal.h"
#import "CredentialSettings.h"

// Pin the default; a saved model remains the user's choice.
static NSString *const kModel = @"gemini-4-hydrogen";
// Stable Keychain service for existing keys, including deletion.
static NSString *const kService = @"Vitrine.Gemini", *const kAccount = @"api-key";

NSString *SGGeminiModel(void) {
    id stored = [NSUserDefaults.standardUserDefaults objectForKey:SGKeyLyricsGeminiModel];
    return SGLyricsAICleanModel(stored) ?: kModel;
}

// The model goes into the path, so anything but unreserved ASCII is percent-encoded and a typed name
// cannot reach another part of the address.
static NSURL *geminiEndpoint(void) {
    NSCharacterSet *unreserved = [NSCharacterSet characterSetWithCharactersInString:
        @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"];
    NSString *model = [SGGeminiModel() stringByAddingPercentEncodingWithAllowedCharacters:unreserved];
    return model ? [NSURL URLWithString:[NSString stringWithFormat:@"https://generativelanguage.googleapis.com/v1beta/models/%@:generateContent", model]] : nil;
}

static const NSInteger kDefaultAITimeout = 120;

static NSTimeInterval aiTimeout(void) {
    NSInteger seconds = [NSUserDefaults.standardUserDefaults integerForKey:SGKeyAITimeout];
    return seconds > 0 ? seconds : kDefaultAITimeout;
}

static NSString *geminiThinkingLevel(void) {
    // Only the menu's levels: Gemini rejects unsupported thinking levels.
    NSString *level = [NSUserDefaults.standardUserDefaults stringForKey:SGKeyAIThinking];
    return [@[@"medium", @"high"] containsObject:level] ? level : @"low";
}

static NSMutableDictionary *geminiGenerationConfig(SGLyricsReplyFormat format) {
    NSMutableDictionary *config = [@{@"thinkingConfig": @{@"thinkingLevel": geminiThinkingLevel()}} mutableCopy];
    if (format != SGLyricsReplyIndexed) {
        config[@"responseMimeType"] = @"application/json";
        config[@"responseSchema"] = @{@"type": @"ARRAY", @"items": @{@"type": @"STRING"}};
    }
    if (format == SGLyricsReplyProse) config[@"maxOutputTokens"] = @(SGLyricsAIProseOutputTokens(SGLyricsAIGemini));
    return config;
}

static NSDictionary *geminiBody(NSString *system, NSString *prompt, SGLyricsReplyFormat format) {
    // Lyrics are often explicit: lower every filter that can be lowered.
    NSMutableArray *safety = [NSMutableArray array];
    for (NSString *category in @[@"HARM_CATEGORY_HARASSMENT", @"HARM_CATEGORY_HATE_SPEECH",
                                 @"HARM_CATEGORY_SEXUALLY_EXPLICIT", @"HARM_CATEGORY_DANGEROUS_CONTENT"])
        [safety addObject:@{@"category": category, @"threshold": @"BLOCK_NONE"}];
    return @{@"systemInstruction": @{@"parts": @[@{@"text": system}]},
             @"contents": @[@{@"parts": @[@{@"text": prompt}]}],
             @"safetySettings": safety, @"generationConfig": geminiGenerationConfig(format)};
}

static NSMutableURLRequest *geminiRequest(NSString *key, NSDictionary *body) {
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:geminiEndpoint()];
    request.HTTPMethod = @"POST";
    request.timeoutInterval = aiTimeout();
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request setValue:key forHTTPHeaderField:@"x-goog-api-key"];
    request.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];
    return request;
}

#pragma mark - the key

static NSDictionary *keyQuery(void) {
    return @{(__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
             (__bridge id)kSecAttrService: kService, (__bridge id)kSecAttrAccount: kAccount};
}

static _Atomic NSUInteger sg_credentialGeneration[3];   // by SGLyricsAI; read off the main queue by retries
NSUInteger SGLyricsCredentialGeneration(SGLyricsAI service) { return atomic_load(&sg_credentialGeneration[service]); }
void SGLyricsCredentialChanged(SGLyricsAI service) { atomic_fetch_add(&sg_credentialGeneration[service], 1); }
NSString *SGLyricsKeyChangedProblem(void) {
    return SGL(@"settings.translation.error.keychanged", @"The API key changed while this was translating. Try again.");
}

static NSMutableDictionary<NSString *, NSDictionary *> *sg_done;   // per launch, by track and language; source texts must still match
static NSNumber *sg_keyAvailable;
static NSString *storedKey(void) {
    NSMutableDictionary *query = [keyQuery() mutableCopy];
    query[(__bridge id)kSecReturnData] = @YES;
    query[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitOne;
    CFTypeRef data = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &data);
    sg_keyAvailable = status == errSecItemNotFound ? @NO : nil;
    if (status != errSecSuccess || !data) return nil;
    NSString *key = [[NSString alloc] initWithData:(__bridge_transfer NSData *)data encoding:NSUTF8StringEncoding];
    sg_keyAvailable = @(key.length > 0);
    return key.length ? key : nil;
}

// NO when the Keychain refused: a removed key is still stored then, and the caller says so.
static BOOL storeKey(NSString *key) {
    SGLyricsCredentialChanged(SGLyricsAIGemini);
    sg_keyAvailable = nil;
    [sg_done removeAllObjects];
    OSStatus status = SGStoreDeviceKey(keyQuery(), key);
    if (status != errSecSuccess) SGLog(@"gemini: the key could not be kept (%d)", (int)status);
    return status == errSecSuccess;
}

static void alertKeychain(NSString *title, NSString *message) {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:SGL(@"common.ok", @"OK") style:UIAlertActionStyleCancel handler:nil]];
    SGPresentDark(alert);
    [SGTopController() presentViewController:alert animated:YES completion:nil];
}
void SGLyricsAlertKeyNotRemoved(void) {
    alertKeychain(SGL(@"settings.translation.key.remove_failed.title", @"Key not removed"),
                  SGL(@"settings.translation.key.remove_failed.message", @"The Keychain could not remove this key, so it is still stored on this iPhone. Please try again."));
}
void SGLyricsAlertKeyNotSaved(void) {
    alertKeychain(SGL(@"settings.translation.key.save_failed.title", @"Key not saved"),
                  SGL(@"settings.translation.key.save_failed.message", @"The Keychain could not save this key. Please try again."));
}

BOOL SGGeminiKeySet(void) {
    return sg_keyAvailable ? sg_keyAvailable.boolValue : storedKey() != nil;
}

#pragma mark - asking

NSString *SGLyricsSongName(NSString *trackID) {
    NSDictionary *local = trackID ? SGLocalFileInfo(trackID) : nil;
    SPTPlayerTrack *track = trackID && !local ? SGKaraokeTrackFor(trackID) : nil;
    NSString *title = local ? local[@"title"] : track.trackTitle, *artist = local ? local[@"artist"] : track.artistName;
    if (![title isKindOfClass:NSString.class] || !title.length) return nil;
    return [artist isKindOfClass:NSString.class] && artist.length ? [NSString stringWithFormat:@"\u201C%@\u201D by %@", title, artist]
                                                                     : [NSString stringWithFormat:@"\u201C%@\u201D", title];
}

NSString *SGLyricsGeminiLanguage(void) {
    return SGLyricsTranslationLanguage() ?: NSLocale.preferredLanguages.firstObject ?: @"en";
}

// Why Gemini stopped short, as finishReason or promptFeedback.blockReason name it.
static NSString *blockedBecause(NSString *reason) {
    if ([reason isEqualToString:@"RECITATION"]) return SGL(@"settings.translation.error.recitation", @"Gemini stopped because its answer repeated published lyrics.");
    if ([@[@"SAFETY", @"PROHIBITED_CONTENT", @"BLOCKLIST", @"SPII"] containsObject:reason]) return SGL(@"settings.translation.error.safety", @"Gemini's filters blocked this song's lyrics.");
    if ([reason isEqualToString:@"MAX_TOKENS"]) return SGL(@"settings.translation.error.toolong", @"The song is too long for one answer from Gemini.");
    return [NSString stringWithFormat:SGL(@"settings.translation.error.stopped", @"Gemini stopped before translating the song (%@)."), reason];
}

NSArray<NSString *> *SGGeminiTranslationsIn(id root, NSInteger status, NSError *error, NSUInteger count, NSString **problem) {
    return SGGeminiReplyIn(root, status, error, count, SGLyricsReplyJSON, problem);
}
NSArray<NSString *> *SGGeminiReplyIn(id root, NSInteger status, NSError *error, NSUInteger count, SGLyricsReplyFormat format, NSString **problem) {
    NSString *__autoreleasing ignored;
    if (!problem) problem = &ignored;
    *problem = nil;
    NSDictionary *reply = [root isKindOfClass:NSDictionary.class] ? root : nil;
    id candidates = reply[@"candidates"];
    id first = [candidates isKindOfClass:NSArray.class] ? [candidates firstObject] : nil;
    id parts = [first isKindOfClass:NSDictionary.class] && [first[@"content"] isKindOfClass:NSDictionary.class] ? first[@"content"][@"parts"] : nil;
    NSMutableString *text = [NSMutableString string];
    BOOL valid = [parts isKindOfClass:NSArray.class] && [parts count] <= 2000;
    if (valid) for (id part in parts) {
        if (![part isKindOfClass:NSDictionary.class]) { valid = NO; break; }
        if ([part[@"thought"] isEqual:@YES]) continue;
        id piece = part[@"text"];
        if (![piece isKindOfClass:NSString.class] || [piece length] > 256000 - text.length) { valid = NO; break; }
        [text appendString:piece];
    }
    id feedback = reply[@"promptFeedback"];
    id blocked = [feedback isKindOfClass:NSDictionary.class] ? feedback[@"blockReason"] : nil;
    id finished = [first isKindOfClass:NSDictionary.class] ? first[@"finishReason"] : nil;
    id failed = [reply[@"error"] isKindOfClass:NSDictionary.class] ? reply[@"error"][@"message"] : nil;
    NSString *googleSays = [failed isKindOfClass:NSString.class] ? failed : nil;
    if (error) {
        *problem = [error.domain isEqualToString:NSURLErrorDomain] && error.code == NSURLErrorTimedOut
            ? SGL(@"settings.translation.error.timeout", @"Gemini timed out. Try a longer timeout or choose another model in Mod Settings > Lyrics > Translation & AI > Gemini.")
            : SGL(@"settings.translation.error.unreachable", @"Gemini could not be reached.");
    } else if (status == 401 || status == 403 || (status == 400 && [googleSays localizedCaseInsensitiveContainsString:@"API key"])) {
        *problem = SGL(@"settings.translation.error.keyinvalid", @"Gemini turned the key down. Check it in Lyrics › Translation & AI.");
    } else if (status == 400) {
        *problem = googleSays.length ? [NSString stringWithFormat:SGL(@"settings.translation.error.badrequestformat", @"Gemini did not take the request: %@"), googleSays]
                                     : SGL(@"settings.translation.error.badrequest", @"Gemini did not take the request (400).");
    } else if (status == 404) {
        *problem = SGL(@"settings.translation.error.modelunavailable", @"This Gemini model is unavailable. Choose another model in Mod Settings > Lyrics > Translation & AI > Gemini.");
    } else if (status == 429) {
        *problem = SGL(@"settings.translation.error.ratelimit", @"Gemini's limit for this key is reached for now.");
    } else if (status == 503 || status == 500) {
        *problem = SGL(@"settings.translation.error.busy", @"Gemini is busy right now. Try again in a minute.");
    } else if (status != 200) {
        *problem = [NSString stringWithFormat:SGL(@"settings.translation.error.status", @"Gemini did not translate the song (%ld)."), (long)status];
    } else if ([blocked isKindOfClass:NSString.class]) {
        *problem = blockedBecause(blocked);
    } else if ([finished isKindOfClass:NSString.class] && ![finished isEqualToString:@"STOP"]) {
        *problem = blockedBecause(finished);
    } else {
        NSArray *answer = nil;
        if (valid && !reply[@"error"] && !blocked &&
            (format == SGLyricsReplyProse ? [finished isEqual:@"STOP"] : (!finished || [finished isEqual:@"STOP"]))) {
            if (format == SGLyricsReplyIndexed) {
                if ([finished isEqual:@"STOP"]) answer = SGLyricsIndexedRowsIn(text, count);
            } else answer = SGLyricsAIArrayIn(text, count);
        }
        if (answer) return answer;
        if (format == SGLyricsReplyJSON && valid && !reply[@"error"]) {
            id parsed = [NSJSONSerialization JSONObjectWithData:[text dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
            if ([parsed isKindOfClass:NSArray.class] && [parsed count] != count) {
                *problem = [NSString stringWithFormat:SGL(@"settings.translation.error.linecount", @"Gemini answered %lu lines for the song's %lu. Try again."),
                    (unsigned long)[parsed count], (unsigned long)count];
                return nil;
            }
        }
        *problem = SGL(@"settings.translation.error.unreadable", @"Gemini's answer could not be read. Try again.");
    }
    return nil;
}

// Google's advice for a busy model or a full minute's quota (408, 429, 5xx): ask again after about 1, 2 and 4 s,
// spread a little so phones do not all come back at once. A key turned down or a request that timed out is not
// asked again.
// plain is the same request without the thinking level, sent once if Gemini turns that field down: a model behind
// gemini-flash-latest that does not know it still translates.
// allowed is asked before every send, the first, the one without thinking and each retry; a refusal ends the job as cancelled.
static void sendToGemini(NSURLRequest *request, NSURLRequest *plain, NSUInteger attempt, BOOL (^allowed)(void),
                         void (^finished)(NSData *data, NSInteger status, NSError *error)) {
    if (!allowed()) {
        finished(nil, 0, [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCancelled userInfo:nil]);
        return;
    }
    [SGBoundedRequestTask(request, 0, ^(NSData *data, NSURLResponse *response, NSError *error) {
        NSInteger status = [response isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)response).statusCode : 0;
        NSString *reply = status == 400 && data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
        if (plain && [reply localizedCaseInsensitiveContainsString:@"thinking"]) {
            SGLog(@"gemini: the thinking level was turned down, asking without it");
            sendToGemini(plain, nil, attempt, allowed, finished);
            return;
        }
        if (attempt < 3 && !error && (status == 408 || status == 429 || status >= 500)) {
            double delay = (double)(1 << attempt) * (0.75 + arc4random_uniform(500) / 1000.0);
            SGLog(@"gemini: %ld, asking again in %.1f s", (long)status, delay);
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
                sendToGemini(request, plain, attempt + 1, allowed, finished);
            });
            return;
        }
        finished(data, status, error);
    }) resume];
}

// Clear Keychain: the service's own items go, the account left out so every one in it does, and with them
// the answers kept for the launch, which were made with that key.
BOOL SGGeminiForgetKey(void) {
    SGLyricsCredentialChanged(SGLyricsAIGemini);
    sg_keyAvailable = nil;
    [sg_done removeAllObjects];
    OSStatus status = SecItemDelete((__bridge CFDictionaryRef)@{(__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
                                                                (__bridge id)kSecAttrService: kService});
    if (status != errSecSuccess && status != errSecItemNotFound) SGLog(@"gemini: the keys could not be cleared (%d)", (int)status);
    return status == errSecSuccess || status == errSecItemNotFound;
}

void SGLyricsTranslateWithGemini(NSString *trackID, NSArray<SGKaraokeLine *> *lines, NSString *languageTag,
                                 void (^done)(NSArray<NSString *> *translations, NSString *error)) {
    SGLyricsTranslateWithGeminiFormat(trackID, lines, languageTag, SGLyricsReplyIndexed, done);
}
void SGLyricsTranslateWithGeminiFormat(NSString *trackID, NSArray<SGKaraokeLine *> *lines, NSString *languageTag,
                                      SGLyricsReplyFormat format, void (^done)(NSArray<NSString *> *, NSString *)) {
    NSString *key = storedKey();
    if (!key) {
        done(nil, SGL(@"settings.translation.error.nokey", @"Add a Gemini API key in Lyrics › Translation & AI first."));
        return;
    }
    if (!sg_done) sg_done = [NSMutableDictionary dictionary];
    NSString *instruction = SGLyricsTranslationInstructionForLanguage(format, languageTag);
    NSString *memo = [NSString stringWithFormat:@"%@|%@|%ld|%@|%@", trackID, languageTag, (long)format, geminiThinkingLevel(), instruction];
    NSArray<NSString *> *texts = SGLyricsAITexts(lines);
    NSString *prompt = texts ? SGLyricsTranslationPromptForFormat(texts, languageTag, format) : nil;
    if (!prompt) { done(nil, SGL(@"settings.translation.error.unreadable", @"Gemini's answer could not be read. Try again.")); return; }
    NSString *model = SGGeminiModel();
    NSDictionary *cached = trackID ? sg_done[memo] : nil;
    if ([cached[@"texts"] isEqual:texts] && [cached[@"model"] isEqual:model]) {
        done(cached[@"answer"], nil);
        return;
    }
    if (![[texts componentsJoinedByString:@""] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length) { done(texts, nil); return; }
    NSUInteger generation = SGLyricsCredentialGeneration(SGLyricsAIGemini);
    SGLyricsTranslateAIRows(texts, format, ^(NSArray *rows, void (^receive)(NSArray *, NSString *)) {
    if (generation != SGLyricsCredentialGeneration(SGLyricsAIGemini)) { receive(nil, SGLyricsKeyChangedProblem()); return; }
    NSDictionary *body = geminiBody(instruction, SGLyricsTranslationPromptForFormat(rows, languageTag, format), format);
    NSMutableURLRequest *request = geminiRequest(key, body);
    if (!request.HTTPBody || request.HTTPBody.length > 1024 * 1024) { receive(nil, SGL(@"settings.translation.error.unreadable", @"Gemini's answer could not be read. Try again.")); return; }
    NSMutableURLRequest *plain = [request mutableCopy];
    NSMutableDictionary *plainBody = [body mutableCopy], *plainConfig = [body[@"generationConfig"] mutableCopy];
    [plainConfig removeObjectForKey:@"thinkingConfig"];
    plainBody[@"generationConfig"] = plainConfig;
    plain.HTTPBody = [NSJSONSerialization dataWithJSONObject:plainBody options:0 error:nil];
    sendToGemini(request, plain, 0, ^BOOL { return generation == SGLyricsCredentialGeneration(SGLyricsAIGemini); }, ^(NSData *data, NSInteger status, NSError *error) {
        id root = data && data.length <= 512 * 1024 ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        NSString *problem = nil;
        NSArray *translations = SGGeminiReplyIn(root, status, error, rows.count, format, &problem);
        if (!translations && !problem) problem = SGL(@"settings.translation.error.unreadable", @"Gemini's answer could not be read. Try again.");
        SGLog(@"gemini: %@ lines into %@: %@", @(rows.count), languageTag, translations ? @"parsed" : @"failed");
        dispatch_async(dispatch_get_main_queue(), ^{
            if (generation != SGLyricsCredentialGeneration(SGLyricsAIGemini)) { receive(nil, SGLyricsKeyChangedProblem()); return; }
            receive(translations, problem);
        });
    });
    }, ^(NSArray *translations, NSString *problem) {
            if (generation != SGLyricsCredentialGeneration(SGLyricsAIGemini)) { done(nil, SGLyricsKeyChangedProblem()); return; }
            if (translations && !problem && trackID) {
                if (sg_done.count >= 32) [sg_done removeAllObjects];
                sg_done[memo] = @{@"texts": texts, @"model": model, @"answer": translations};
            }
            done(translations, problem);
    });
}

#pragma mark - the row

static void askForKey(void) {
    // Says what leaves the phone, not only where the key stays: each song translated goes to Google whole.
    SGLyricsCredentialPrompt(SGL(@"settings.translation.geminikey.alert.title", @"Gemini API key"),
        SGL(@"settings.translation.geminikey.alert.message", @"Translate with Gemini sends the song's lyrics to Google, on your own key from Google AI Studio. The key stays on this iPhone."),
        SGL(@"settings.translation.geminikey.placeholder", @"API key"),
        ^BOOL(NSString *text) { return [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length > 0; }, ^(NSString *text) {
        // A key copied with the quotes around it, as from a code sample, is turned down by Google as it stands.
        NSMutableCharacterSet *around = [NSMutableCharacterSet whitespaceAndNewlineCharacterSet];
        [around addCharactersInString:@"\"'“”‘’"];
        NSString *key = [text stringByTrimmingCharactersInSet:around];
        if (!key.length || [storedKey() isEqualToString:key]) return;   // the same key again changes nothing, so no job is cut off
        if (storeKey(key)) SGLyricsTranslationServiceSettingsChanged(); else SGLyricsAlertKeyNotSaved();
    }, ^BOOL { return SGGeminiKeySet(); }, ^{ if (storeKey(nil)) SGLyricsTranslationServiceSettingsChanged(); else SGLyricsAlertKeyNotRemoved(); });
}

NSNotificationName const SGLyricsTranslationsDidChangeNotification = @"spotifyglass.lyricsTranslationsDidChange";

SGModRow *SGTranslateEverySongRow(void) {
    SGModRow *row = SGOptionRow(SGL(@"settings.translation.translateanysong.title", @"Translate any song"), SGL(@"settings.translation.translateanysong.subtitle", @"The lyrics' translate menu for songs that already read as your language"),
                                SGKeyLyricsTranslateEverySong);
    row.changed = ^(BOOL on) {
        [NSNotificationCenter.defaultCenter postNotificationName:SGLyricsTranslationsDidChangeNotification object:nil];
    };
    return row;
}

NSArray<SGModRow *> *SGOnDeviceTranslatorRows(void) {
    SGModRow *onDevice = SGSwitchRow(SGL(@"settings.translation.ondevice.title", @"Translate on iPhone"),
        SGL(@"settings.translation.ondevice.subtitle", @"Apple's Translate in the lyrics' translate menu and automatic translation"),
        SGKeyLyricsTranslateOnDevice);
    SGModRow *intelligence = SGSwitchRow(SGL(@"settings.translation.intelligence.title", @"Apple Intelligence"),
        SGL(@"settings.translation.intelligence.subtitle", @"Apple Intelligence in the lyrics' translate menu and automatic translation"),
        SGKeyLyricsAppleIntelligence);
    // SGSwitchRow is already on by default, as SGFlag(key, YES) reads an unset one.
    onDevice.changed = intelligence.changed = ^(BOOL on) { SGLyricsTranslationServiceSettingsChanged(); };
    return @[onDevice, intelligence];
}

SGModRow *SGGeminiKeyRow(void) {
    return SGStatActionRow(SGL(@"settings.translation.ai.key.title", @"API key"), nil,
                           ^NSString *{ return SGGeminiKeySet() ? SGL(@"settings.translation.geminikey.status.set", @"Set") : SGL(@"common.off", @"Off"); }, ^{ askForKey(); });
}

// Up to 1000 models a page; a reply with nextPageToken asks for the following one.
static NSURLRequest *geminiModelsRequest(NSString *pageToken, NSString **problem) {
    NSString *key = storedKey();
    if (!key) { *problem = SGL(@"settings.translation.models.error.nokey", @"Save an API key first, and its models are listed here."); return nil; }
    NSURLComponents *components = [NSURLComponents componentsWithString:@"https://generativelanguage.googleapis.com/v1beta/models"];
    NSMutableArray<NSURLQueryItem *> *items = [NSMutableArray arrayWithObject:[NSURLQueryItem queryItemWithName:@"pageSize" value:@"1000"]];
    if (pageToken.length) [items addObject:[NSURLQueryItem queryItemWithName:@"pageToken" value:pageToken]];
    components.queryItems = items;
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:components.URL];
    [request setValue:key forHTTPHeaderField:@"x-goog-api-key"];
    return request;
}
NSURLRequest *SGGeminiModelsRequest(NSString **problem) {
    return geminiModelsRequest(nil, problem);
}
NSURLRequest *SGGeminiModelsPageRequest(NSString *pageToken, NSString **problem) {
    return geminiModelsRequest(pageToken, problem);
}

// Other AI jobs use the same model and filters, with the bounded transport used by the other services.
NSURLRequest *SGGeminiAIRequest(NSString *system, NSString *prompt, NSString **problem) {
    return SGGeminiAIRequestWithFormat(system, prompt, SGLyricsReplyJSON, problem);
}
NSURLRequest *SGGeminiAIRequestWithFormat(NSString *system, NSString *prompt, SGLyricsReplyFormat format, NSString **problem) {
    NSString *key = storedKey();
    if (!key) { *problem = SGL(@"settings.translation.error.nokey", @"Add a Gemini API key in Lyrics › Translation & AI first."); return nil; }
    return geminiRequest(key, geminiBody(system, prompt, format));
}

NSArray<SGModRow *> *SGGeminiTuningRows(void) {
    // Low first: 3.8 Flash refuses minimal.
    NSArray<NSString *> *levels = @[@"low", @"medium", @"high"];
    NSArray<NSString *> *thinkingLevels = @[SGL(@"settings.translation.thinking.low", @"Low"), SGL(@"settings.translation.thinking.medium", @"Medium"), SGL(@"settings.translation.thinking.high", @"High")];
    SGModRow *thinking = SGMenuRow(SGL(@"settings.translation.thinking.title", @"Thinking"), thinkingLevels, ^NSString *{
        return thinkingLevels[[levels indexOfObject:geminiThinkingLevel()]];
    }, ^(NSInteger index) {
        if (index == 0) [NSUserDefaults.standardUserDefaults removeObjectForKey:SGKeyAIThinking];
        else [NSUserDefaults.standardUserDefaults setObject:levels[index] forKey:SGKeyAIThinking];
        SGLyricsTranslationServiceSettingsChanged();
    });
    NSArray<NSNumber *> *timeoutSeconds = @[@30, @60, @90, @(kDefaultAITimeout), @180, @240, @300];
    NSMutableArray<NSString *> *timeouts = [NSMutableArray array];
    for (NSNumber *seconds in timeoutSeconds) [timeouts addObject:[NSString stringWithFormat:SGL(@"settings.translation.timeout.seconds", @"%ld s"), seconds.longValue]];
    SGModRow *timeout = SGMenuRow(SGL(@"settings.translation.timeout.title", @"Timeout"), timeouts, ^NSString *{
        return [NSString stringWithFormat:SGL(@"settings.translation.timeout.seconds", @"%ld s"), (long)aiTimeout()];
    }, ^(NSInteger index) {
        NSInteger seconds = timeoutSeconds[index].integerValue;
        if (seconds == kDefaultAITimeout) [NSUserDefaults.standardUserDefaults removeObjectForKey:SGKeyAITimeout];
        else [NSUserDefaults.standardUserDefaults setInteger:seconds forKey:SGKeyAITimeout];
    });
    return @[thinking, timeout];
}
