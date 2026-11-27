#import <Security/Security.h>
#import "Core/SGKeychain.h"
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Settings/SGPageStyle.h"
#import "Shared/Lyrics/Lyrics.h"
#import "AIServicesInternal.h"
#import "CredentialSettings.h"

// Stable Keychain service for existing keys, including deletion.
static NSString *const kService = @"Vitrine.Claude", *const kAccount = @"api-key";
static NSString *const kModel = @"claude-sonnet-5";
static NSMutableDictionary *sg_done;

static NSDictionary *keyQuery(void) {
    return @{(__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
             (__bridge id)kSecAttrService: kService, (__bridge id)kSecAttrAccount: kAccount};
}
static NSString *cleanKey(NSString *text) {
    return SGLyricsCleanCredential(text, 4096);
}
static NSNumber *sg_keyAvailable;
static NSString *storedKey(void) {
    NSMutableDictionary *query = [keyQuery() mutableCopy];
    query[(__bridge id)kSecReturnData] = @YES;
    query[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitOne;
    CFTypeRef data = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &data);
    id value = CFBridgingRelease(data);
    sg_keyAvailable = (status == errSecSuccess || status == errSecItemNotFound) ? @NO : nil;
    if (status != errSecSuccess || ![value isKindOfClass:NSData.class] || [value length] > 4096) return nil;
    NSString *key = cleanKey([[NSString alloc] initWithData:value encoding:NSUTF8StringEncoding]);
    sg_keyAvailable = @(key.length > 0);
    return key.length ? key : nil;
}
static BOOL storeKey(NSString *key) {
    SGLyricsCredentialChanged(SGLyricsAIClaude);
    sg_keyAvailable = nil;
    [sg_done removeAllObjects];
    OSStatus status = SGStoreDeviceKey(keyQuery(), key);
    if (status != errSecSuccess) SGLog(@"claude: the key could not be kept (%d)", (int)status);
    return status == errSecSuccess;
}
BOOL SGClaudeKeySet(void) { return sg_keyAvailable ? sg_keyAvailable.boolValue : storedKey() != nil; }
// Clear Keychain: the service's own items go, every account in it; answers kept for the launch go too.
BOOL SGClaudeForgetKey(void) {
    SGLyricsCredentialChanged(SGLyricsAIClaude);
    sg_keyAvailable = nil;
    [sg_done removeAllObjects];
    OSStatus status = SecItemDelete((__bridge CFDictionaryRef)@{(__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
                                                                (__bridge id)kSecAttrService: kService});
    if (status != errSecSuccess && status != errSecItemNotFound) SGLog(@"claude: the keys could not be cleared (%d)", (int)status);
    return status == errSecSuccess || status == errSecItemNotFound;
}
NSString *SGClaudeModel(void) {
    return SGLyricsAICleanModel([NSUserDefaults.standardUserDefaults objectForKey:SGKeyLyricsClaudeModel]) ?: kModel;
}

static NSString *unreadable(void) {
    return SGL(@"settings.translation.claude.error.unreadable", @"Claude's answer could not be read. Try again.");
}

NSArray<NSString *> *SGClaudeTranslationsIn(id root, NSInteger status, NSError *error, NSUInteger count, NSString **problem) {
    return SGClaudeReplyIn(root, status, error, count, SGLyricsReplyJSON, problem);
}
NSArray<NSString *> *SGClaudeReplyIn(id root, NSInteger status, NSError *error, NSUInteger count, SGLyricsReplyFormat format, NSString **problem) {
    if (problem) *problem = nil;
    NSString *failure = nil;
    NSDictionary *reply = [root isKindOfClass:NSDictionary.class] ? root : nil;
    id detail = [reply[@"error"] isKindOfClass:NSDictionary.class] ? reply[@"error"][@"message"] : nil;
    if (error) failure = SGL(@"settings.translation.claude.error.unreachable", @"Claude could not be reached.");
    else if (status == 401 || status == 403) failure = SGL(@"settings.translation.claude.error.keyinvalid", @"Claude turned the key down. Check it in Lyrics › Translation & AI.");
    else if (status == 429 || (status >= 500 && status <= 599)) failure = SGL(@"settings.translation.claude.error.busy", @"Claude is busy right now. Try again in a minute.");
    else if (status == 400 && [detail isKindOfClass:NSString.class] && [detail length]) {
        NSString *message = [detail length] > 1024 ? [detail substringToIndex:1024] : detail;
        failure = [NSString stringWithFormat:SGL(@"settings.translation.claude.error.badrequest", @"Claude did not take the request: %@"), message];
    } else if (status != 200) failure = [NSString stringWithFormat:SGL(@"settings.translation.claude.error.status", @"Claude did not complete the request (%ld)."), (long)status];
    NSArray *out = nil;
    if (!failure) {
        id content = reply[@"content"];
        NSMutableString *text = [NSMutableString string];
        BOOL valid = [content isKindOfClass:NSArray.class] && [content count] <= 2000 && !reply[@"error"];
        if (valid) for (id part in content) {
            if (![part isKindOfClass:NSDictionary.class]) { valid = NO; break; }
            if (![part[@"type"] isEqual:@"text"]) {
                if (format != SGLyricsReplyJSON && ![part[@"type"] isEqual:@"thinking"] && ![part[@"type"] isEqual:@"redacted_thinking"]) { valid = NO; break; }
                continue;
            }
            id piece = part[@"text"];
            if (![piece isKindOfClass:NSString.class] || [piece length] > 256000 - text.length) { valid = NO; break; }
            [text appendString:piece];
        }
        if (format == SGLyricsReplyIndexed) {
            if (valid && [reply[@"stop_reason"] isEqual:@"end_turn"]) out = SGLyricsIndexedRowsIn(text, count);
        } else if (format == SGLyricsReplyProse) {
            if (valid && [reply[@"stop_reason"] isEqual:@"end_turn"]) out = SGLyricsAIArrayIn(text, count);
        } else if (valid && ![reply[@"stop_reason"] isEqual:@"max_tokens"]) out = SGLyricsAIArrayIn(text, count);
        if (!out) failure = unreadable();
    }
    if (problem) *problem = failure;
    return out;
}

NSURLRequest *SGClaudeRequest(NSString *system, NSString *prompt, NSString **problem) {
    NSString *key = storedKey(), *model = SGClaudeModel();
    if (!key) { *problem = SGL(@"settings.translation.claude.error.nokey", @"Add a Claude API key in Lyrics › Translation & AI first."); return nil; }
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"https://api.anthropic.com/v1/messages"]];
    request.HTTPMethod = @"POST";
    request.timeoutInterval = 60;
    [request setValue:key forHTTPHeaderField:@"x-api-key"];
    [request setValue:@"2023-06-01" forHTTPHeaderField:@"anthropic-version"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    request.HTTPBody = [NSJSONSerialization dataWithJSONObject:@{@"model": model, @"max_tokens": @(SGClaudeMaxOutputTokens), @"system": system,
        @"messages": @[@{@"role": @"user", @"content": prompt}]} options:0 error:nil];
    return request;
}

void SGLyricsTranslateWithClaude(NSString *trackID, NSArray<SGKaraokeLine *> *lines, NSString *languageTag,
                                 void (^done)(NSArray<NSString *> *, NSString *)) {
    SGLyricsTranslateWithClaudeFormat(trackID, lines, languageTag, SGLyricsReplyIndexed, done);
}
void SGLyricsTranslateWithClaudeFormat(NSString *trackID, NSArray<SGKaraokeLine *> *lines, NSString *languageTag,
                                      SGLyricsReplyFormat format, void (^done)(NSArray<NSString *> *, NSString *)) {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSArray *texts = SGLyricsAITexts(lines);
        NSString *prompt = texts ? SGLyricsTranslationPromptForFormat(texts, languageTag, format) : nil;
        if (!prompt) { done(nil, unreadable()); return; }
        if (!SGClaudeKeySet()) { done(nil, SGL(@"settings.translation.claude.error.nokey", @"Add a Claude API key in Lyrics › Translation & AI first.")); return; }
        NSString *model = SGClaudeModel();
        NSString *instruction = SGLyricsTranslationInstructionForLanguage(format, languageTag);
        NSString *memo = [NSString stringWithFormat:@"%@|%@|%ld|%@", trackID, languageTag, (long)format, instruction];
        if (!sg_done) sg_done = [NSMutableDictionary dictionary];
        NSDictionary *cached = trackID ? sg_done[memo] : nil;
        if ([cached[@"texts"] isEqual:texts] && [cached[@"model"] isEqual:model]) { done(cached[@"answer"], nil); return; }
        if (![[texts componentsJoinedByString:@""] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length) { done(texts, nil); return; }
        NSUInteger generation = SGLyricsCredentialGeneration(SGLyricsAIClaude);
        SGLyricsTranslateAIRows(texts, format, ^(NSArray *rows, void (^receive)(NSArray *, NSString *)) {
            if (generation != SGLyricsCredentialGeneration(SGLyricsAIClaude)) { receive(nil, SGLyricsKeyChangedProblem()); return; }
            SGLyricsAIAskWithFormat(SGLyricsAIClaude, instruction,
                SGLyricsTranslationPromptForFormat(rows, languageTag, format), rows.count, format, receive);
        }, ^(NSArray *answer, NSString *problem) {
            if (generation != SGLyricsCredentialGeneration(SGLyricsAIClaude)) { done(nil, SGLyricsKeyChangedProblem()); return; }
            if (answer && !problem) {
                if (trackID) {
                    if (sg_done.count >= 32) [sg_done removeAllObjects];
                    sg_done[memo] = @{@"texts": texts, @"model": model, @"answer": answer};
                }
            }
            done(answer, problem);
        });
    });
}

static void askForKey(void) {
    SGLyricsCredentialPrompt(SGL(@"settings.translation.claudekey.title", @"Claude API key"),
        SGL(@"settings.translation.claudekey.message", @"The song's lyrics go to Anthropic, on your own API key. The key stays on this iPhone."),
        SGL(@"settings.translation.openaikey.key", @"API key"),
        ^BOOL(NSString *text) { return cleanKey(text).length > 0; }, ^(NSString *text) {
        NSString *key = cleanKey(text);
        if (!key.length || [storedKey() isEqualToString:key]) return;   // the same key again changes nothing, so no job is cut off
        if (storeKey(key)) SGLyricsTranslationServiceSettingsChanged(); else SGLyricsAlertKeyNotSaved();
    }, ^BOOL { return SGClaudeKeySet(); }, ^{ if (storeKey(nil)) SGLyricsTranslationServiceSettingsChanged(); else SGLyricsAlertKeyNotRemoved(); });
}
SGModRow *SGClaudeKeyRow(void) {
    return SGStatActionRow(SGL(@"settings.translation.ai.key.title", @"API key"), nil,
        ^NSString *{ return SGClaudeKeySet() ? SGL(@"settings.translation.openaikey.set", @"Set") : SGL(@"common.off", @"Off"); }, ^{ askForKey(); });
}

// Anthropic lists up to 1000 models a page, newest first.
static NSURLRequest *claudeModelsRequest(NSString *afterID, NSString **problem) {
    NSString *key = storedKey();
    if (!key) { *problem = SGL(@"settings.translation.models.error.nokey", @"Save an API key first, and its models are listed here."); return nil; }
    NSURLComponents *components = [NSURLComponents componentsWithString:@"https://api.anthropic.com/v1/models"];
    NSMutableArray<NSURLQueryItem *> *items = [NSMutableArray arrayWithObject:[NSURLQueryItem queryItemWithName:@"limit" value:@"1000"]];
    if (afterID.length) [items addObject:[NSURLQueryItem queryItemWithName:@"after_id" value:afterID]];
    components.queryItems = items;
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:components.URL];
    [request setValue:key forHTTPHeaderField:@"x-api-key"];
    [request setValue:@"2023-06-01" forHTTPHeaderField:@"anthropic-version"];
    return request;
}
NSURLRequest *SGClaudeModelsRequest(NSString **problem) {
    return claudeModelsRequest(nil, problem);
}
NSURLRequest *SGClaudeModelsPageRequest(NSString *afterID, NSString **problem) {
    return claudeModelsRequest(afterID, problem);
}
