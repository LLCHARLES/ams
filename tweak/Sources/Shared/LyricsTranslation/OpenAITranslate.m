#import <Security/Security.h>
#import <arpa/inet.h>
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Settings/SGPageStyle.h"
#import "Shared/Lyrics/Lyrics.h"
#import "AIServicesInternal.h"

// Stable Keychain service for existing keys, including deletion.
static NSString *const kService = @"Vitrine.OpenAI", *const kLegacyAccount = @"api-key";
static NSString *const kBase = @"https://api.openai.com/v1", *const kModel = @"gpt-4o-mini";
static NSMutableDictionary *sg_done;

NSURL *SGOpenAICompletionURL(NSString *base) {
    if (![base isKindOfClass:NSString.class] || !base.length || base.length > 2048) return nil;
    if ([base rangeOfCharacterFromSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].location != NSNotFound) return nil;
    NSURLComponents *parts = [NSURLComponents componentsWithString:base];
    NSString *host = parts.host.lowercaseString, *scheme = parts.scheme.lowercaseString;
    if (!host.length || parts.user || parts.password || parts.query || parts.fragment) return nil;
    // Match a numeric Tailscale IPv4 address, never a hostname which merely starts with one.
    struct in_addr address;
    BOOL tailnet = inet_pton(AF_INET, host.UTF8String, &address) == 1 &&
        (ntohl(address.s_addr) & 0xffc00000U) == 0x64400000U;   // 100.64.0.0/10
    BOOL local = tailnet || [host isEqualToString:@"localhost"] || [host isEqualToString:@"127.0.0.1"] || (host.length > 6 && [host hasSuffix:@".local"]);
    if (![scheme isEqualToString:@"https"] && !([scheme isEqualToString:@"http"] && local)) return nil;
    if (parts.port && (parts.port.integerValue < 1 || parts.port.integerValue > 65535)) return nil;
    NSString *path = parts.percentEncodedPath;
    while ([path hasSuffix:@"/"]) path = [path substringToIndex:path.length - 1];
    parts.percentEncodedPath = [path stringByAppendingString:@"/chat/completions"];
    return parts.URL;
}

NSURL *SGOpenAIModelsURL(NSString *base) {
    NSURL *completion = SGOpenAICompletionURL(base);
    if (!completion) return nil;
    NSURLComponents *parts = [NSURLComponents componentsWithURL:completion resolvingAgainstBaseURL:NO];
    NSString *path = parts.percentEncodedPath;
    parts.percentEncodedPath = [[path substringToIndex:path.length - @"/chat/completions".length] stringByAppendingString:@"/models"];
    return parts.URL;
}

NSArray<NSString *> *SGOpenAITranslationsIn(id root, NSUInteger count) {
    return SGOpenAIReplyIn(root, count, SGLyricsReplyJSON);
}
NSArray<NSString *> *SGOpenAIReplyIn(id root, NSUInteger count, SGLyricsReplyFormat format) {
    if (![root isKindOfClass:NSDictionary.class] || count > 2000) return nil;
    id choices = root[@"choices"];
    id first = [choices isKindOfClass:NSArray.class] && [choices count] ? choices[0] : nil;
    id message = [first isKindOfClass:NSDictionary.class] ? first[@"message"] : nil;
    id content = [message isKindOfClass:NSDictionary.class] ? message[@"content"] : nil;
    if (format != SGLyricsReplyJSON) {
        if (![first isKindOfClass:NSDictionary.class] || ![message isKindOfClass:NSDictionary.class] ||
            root[@"error"] || ![first[@"finish_reason"] isEqual:@"stop"] ||
            (message[@"refusal"] && message[@"refusal"] != NSNull.null)) return nil;
        id tools = message[@"tool_calls"], function = message[@"function_call"];
        // Optional no-call values vary across compatible servers; only the list field admits [].
        if (tools && tools != NSNull.null && (![tools isKindOfClass:NSArray.class] || [tools count])) return nil;
        if (function && function != NSNull.null) return nil;
        return format == SGLyricsReplyIndexed ? SGLyricsIndexedRowsIn(content, count) : SGLyricsAIArrayIn(content, count);
    }
    return SGLyricsAIArrayIn(content, count);
}

NSArray<NSString *> *SGLyricsAIArrayIn(id content, NSUInteger count) {
    if (count > 2000 || ![content isKindOfClass:NSString.class] || [content length] > 256000) return nil;
    NSString *text = [content stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if ([text hasPrefix:@"```"]) {
        NSRange newline = [text rangeOfString:@"\n"];
        if (newline.location == NSNotFound || ![text hasSuffix:@"```"]) return nil;
        NSString *fence = [[text substringToIndex:newline.location] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (![fence.lowercaseString isEqualToString:@"```json"] && ![fence isEqualToString:@"```"]) return nil;
        NSUInteger start = NSMaxRange(newline), end = text.length - 3;
        if (end < start) return nil;
        text = [text substringWithRange:NSMakeRange(start, end - start)];
    }
    NSData *data = [text dataUsingEncoding:NSUTF8StringEncoding];
    if (!data || data.length > 512 * 1024) return nil;
    id parsed = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if ([parsed isKindOfClass:NSDictionary.class]) {
        if ([parsed count] != 1) return nil;
        parsed = [[parsed allValues] firstObject];
    }
    if (![parsed isKindOfClass:NSArray.class] || [parsed count] != count) return nil;
    NSUInteger size = 0;
    for (id line in parsed) {
        if (![line isKindOfClass:NSString.class] || [line length] > 64000) return nil;
        size += [line length];
        if (size > 128000) return nil;
    }
    return parsed;
}

#pragma mark - the key and settings

NSString *SGOpenAIKeyHost(NSString *base) {
    NSURL *url = SGOpenAICompletionURL(base ?: kBase);
    if (!url) return nil;
    NSString *scheme = url.scheme.lowercaseString, *host = url.host.lowercaseString;
    if ([host containsString:@":"] && ![host hasPrefix:@"["]) host = [NSString stringWithFormat:@"[%@]", host];
    return [NSString stringWithFormat:@"%@://%@:%@", scheme, host, url.port ?: ([scheme isEqual:@"https"] ? @443 : @80)];
}
SGOpenAIKeyMigration SGOpenAIKeyMigrationDecision(NSString *base, BOOL legacyExists, BOOL hostKeyExists) {
    if (!legacyExists) return SGOpenAIKeyMigrationNone;
    if (![SGOpenAIKeyHost(base) isEqual:SGOpenAIKeyHost(kBase)]) return SGOpenAIKeyMigrationDeferred;
    return hostKeyExists ? SGOpenAIKeyMigrationDeleteLegacy : SGOpenAIKeyMigrationCopy;
}
static NSString *setting(NSString *key, NSString *fallback) {
    id value = [NSUserDefaults.standardUserDefaults objectForKey:key];
    return [value isKindOfClass:NSString.class] ? value : fallback;
}
static NSDictionary *keyQuery(NSString *account) {
    return @{(__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
             (__bridge id)kSecAttrService: kService, (__bridge id)kSecAttrAccount: account};
}
static NSString *cleanKey(NSString *text) {
    return SGLyricsCleanCredential(text, 4096);
}
static NSString *readKey(NSString *account, OSStatus *status) {
    NSMutableDictionary *query = [keyQuery(account) mutableCopy];
    query[(__bridge id)kSecReturnData] = @YES;
    query[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitOne;
    CFTypeRef data = NULL;
    *status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &data);
    id value = CFBridgingRelease(data);
    if (*status != errSecSuccess) return nil;
    NSString *key = [value isKindOfClass:NSData.class] && [value length] <= 4096
        ? cleanKey([[NSString alloc] initWithData:value encoding:NSUTF8StringEncoding]) : nil;
    if (!key.length) { *status = errSecDecode; return nil; }
    return key;
}
// Availability only; requests still obtain the secret from the exact origin's account.
static NSMutableDictionary<NSString *, NSNumber *> *sg_keyAvailable;
static BOOL storeKey(NSString *key, NSString *host) {
    if (!host.length) return NO;
    SGLyricsCredentialChanged(SGLyricsAIOpenAI);
    [sg_keyAvailable removeObjectForKey:host];
    [sg_done removeAllObjects];
    NSDictionary *query = keyQuery(host);
    OSStatus status;
    if (!key.length) {
        status = SecItemDelete((__bridge CFDictionaryRef)query);
        if (status == errSecItemNotFound) status = errSecSuccess;
    } else {
        NSDictionary *attributes = @{(__bridge id)kSecValueData: [key dataUsingEncoding:NSUTF8StringEncoding],
            (__bridge id)kSecAttrAccessible: (__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly};
        status = SecItemUpdate((__bridge CFDictionaryRef)query, (__bridge CFDictionaryRef)attributes);
        if (status == errSecItemNotFound) {
            NSMutableDictionary *item = [query mutableCopy];
            [item addEntriesFromDictionary:attributes];
            status = SecItemAdd((__bridge CFDictionaryRef)item, NULL);
        }
    }
    if (status != errSecSuccess) SGLog(@"openai translation: the key could not be kept (%d)", (int)status);
    return status == errSecSuccess;
}
// A bare hostname does not identify a custom service, even when it matches the active host.
// Only carry the OpenAI hostname forward when the official origin is actually selected.
static BOOL sg_hostsMigrated;
static BOOL migrateHosts(void) {
    @synchronized (kService) {
        if (sg_hostsMigrated) return YES;
        NSDictionary *query = @{(__bridge id)kSecClass:(__bridge id)kSecClassGenericPassword,
            (__bridge id)kSecAttrService:kService, (__bridge id)kSecReturnAttributes:@YES,
            (__bridge id)kSecMatchLimit:(__bridge id)kSecMatchLimitAll};
        CFTypeRef result = NULL;
        OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
        NSArray *items = CFBridgingRelease(result);
        if (status != errSecSuccess && status != errSecItemNotFound) return NO;
        NSString *base = setting(SGKeyLyricsOpenAIBaseURL, kBase);
        NSString *official = SGOpenAIKeyHost(kBase);
        BOOL usingOfficial = [official isEqual:SGOpenAIKeyHost(base)];
        for (NSDictionary *item in items) {
            NSString *account = item[(__bridge id)kSecAttrAccount];
            if (!account.length || [account containsString:@"/"] || [account isEqual:kLegacyAccount]) continue;
            BOOL eligible = usingOfficial && [account isEqual:SGOpenAICompletionURL(kBase).host];
            NSString *destination = eligible ? official : [@"unassigned/" stringByAppendingString:NSUUID.UUID.UUIDString];
            status = SecItemUpdate((__bridge CFDictionaryRef)keyQuery(account),
                (__bridge CFDictionaryRef)@{(__bridge id)kSecAttrAccount:destination});
            if (eligible && status == errSecDuplicateItem) status = SecItemDelete((__bridge CFDictionaryRef)keyQuery(account));
            if (status != errSecSuccess && status != errSecItemNotFound) return NO;
        }
        sg_hostsMigrated = YES;
        return YES;
    }
}

static BOOL migrateKey(void) {
    OSStatus legacyStatus, hostStatus;
    NSString *legacy = readKey(kLegacyAccount, &legacyStatus);
    if (legacyStatus != errSecItemNotFound && legacyStatus != errSecSuccess) return NO;
    if (!migrateHosts()) return NO;
    if (legacyStatus == errSecItemNotFound) return YES;
    NSString *host = SGOpenAIKeyHost(kBase);
    readKey(host, &hostStatus);
    if (hostStatus != errSecSuccess && hostStatus != errSecItemNotFound) return NO;
    switch (SGOpenAIKeyMigrationDecision(kBase, YES, hostStatus == errSecSuccess)) {
        case SGOpenAIKeyMigrationDeferred: return NO;
        case SGOpenAIKeyMigrationCopy: if (!storeKey(legacy, host)) return NO; break;
        case SGOpenAIKeyMigrationDeleteLegacy: break;
        case SGOpenAIKeyMigrationNone: return YES;
    }
    OSStatus status = SecItemDelete((__bridge CFDictionaryRef)keyQuery(kLegacyAccount));
    return status == errSecSuccess || status == errSecItemNotFound;
}

static NSString *storedKey(NSString *base) {
    NSString *host = SGOpenAIKeyHost(base);
    if (!host) return nil;
    [sg_keyAvailable removeObjectForKey:host];
    if (!migrateKey()) return nil;
    OSStatus status;
    NSString *key = readKey(host, &status);
    if (status == errSecSuccess || status == errSecItemNotFound) {
        if (!sg_keyAvailable) sg_keyAvailable = [NSMutableDictionary dictionary];
        sg_keyAvailable[host] = @(key != nil);
    }
    return key;
}
BOOL SGOpenAIKeySet(void) {
    NSString *base = setting(SGKeyLyricsOpenAIBaseURL, kBase), *host = SGOpenAIKeyHost(base);
    if (!host) return NO;
    NSNumber *available = sg_keyAvailable[host];
    return available ? available.boolValue : storedKey(base) != nil;
}
// Clear Keychain: every account under the service goes (the legacy key and each host-bound one), so no
// server's key outlives it; answers kept for the launch go too.
BOOL SGOpenAIForgetKeys(void) {
    @synchronized (kService) { sg_hostsMigrated = NO; }
    SGLyricsCredentialChanged(SGLyricsAIOpenAI);
    [sg_keyAvailable removeAllObjects];
    [sg_done removeAllObjects];
    OSStatus status = SecItemDelete((__bridge CFDictionaryRef)@{(__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
                                                                (__bridge id)kSecAttrService: kService});
    if (status != errSecSuccess && status != errSecItemNotFound) SGLog(@"openai translation: the keys could not be cleared (%d)", (int)status);
    return status == errSecSuccess || status == errSecItemNotFound;
}
NSString *SGOpenAIModel(void) {
    return SGLyricsAICleanModel([NSUserDefaults.standardUserDefaults objectForKey:SGKeyLyricsOpenAIModel]) ?: kModel;
}

#pragma mark - asking

static NSString *unreadable(void) {
    return SGL(@"settings.translation.openai.error.unreadable", @"The translation service's answer could not be read. Try again.");
}

void SGLyricsTranslateWithOpenAI(NSString *trackID, NSArray<SGKaraokeLine *> *lines, NSString *languageTag,
                                void (^done)(NSArray<NSString *> *, NSString *)) {
    SGLyricsTranslateWithOpenAIFormat(trackID, lines, languageTag, SGLyricsReplyIndexed, done);
}
void SGLyricsTranslateWithOpenAIFormat(NSString *trackID, NSArray<SGKaraokeLine *> *lines, NSString *languageTag,
                                      SGLyricsReplyFormat format, void (^done)(NSArray<NSString *> *, NSString *)) {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *base = setting(SGKeyLyricsOpenAIBaseURL, kBase);
        NSString *key = storedKey(base), *model = SGOpenAIModel();
        NSURL *endpoint = SGOpenAICompletionURL(base);
        if (!key) { done(nil, SGL(@"settings.translation.openai.error.nokey", @"Add an OpenAI-compatible API key in Lyrics › Translation & AI first.")); return; }
        if (!endpoint) { done(nil, SGL(@"settings.translation.openai.error.settings", @"Check the translation service's base URL and model in Lyrics › Translation & AI.")); return; }
        if (![languageTag isKindOfClass:NSString.class] || !languageTag.length || languageTag.length > 64 || ![lines isKindOfClass:NSArray.class] || lines.count > 2000) { done(nil, unreadable()); return; }
        NSMutableArray *texts = [NSMutableArray array];
        NSUInteger size = 0;
        BOOL hasText = NO;
        for (id line in lines) {
            if (![line isKindOfClass:SGKaraokeLine.class]) { done(nil, unreadable()); return; }
            NSString *text = SGKaraokeLineText(line) ?: @"";
            if (text.length > 64000) { done(nil, SGL(@"settings.translation.openai.error.toolong", @"The song is too long to send to the translation service.")); return; }
            size += text.length;
            if (size > 128000) { done(nil, SGL(@"settings.translation.openai.error.toolong", @"The song is too long to send to the translation service.")); return; }
            BOOL blank = ![text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length;
            [texts addObject:blank ? @"" : text];
            hasText |= !blank;
        }
        if (!hasText) { done([texts copy], nil); return; }
        if (!sg_done) sg_done = [NSMutableDictionary dictionary];
        NSString *instruction = SGLyricsTranslationInstructionForLanguage(format, languageTag);
        NSString *memo = [NSString stringWithFormat:@"%@|%@|%ld|%@", trackID, languageTag, (long)format, instruction];
        NSDictionary *cached = trackID ? sg_done[memo] : nil;
        if ([cached[@"texts"] isEqual:texts] && [cached[@"base"] isEqual:base] && [cached[@"model"] isEqual:model]) { done(cached[@"translations"], nil); return; }
        NSUInteger generation = SGLyricsCredentialGeneration(SGLyricsAIOpenAI);
        SGLyricsTranslateAIRows(texts, format, ^(NSArray *rows, void (^receive)(NSArray *, NSString *)) {
        if (generation != SGLyricsCredentialGeneration(SGLyricsAIOpenAI)) { receive(nil, SGLyricsKeyChangedProblem()); return; }
        NSString *prompt = SGLyricsTranslationPromptForFormat(rows, languageTag, format);
        if (!prompt) { receive(nil, unreadable()); return; }
        NSString *requestProblem = nil;
        NSURLRequest *request = SGOpenAIRequest(instruction, prompt, format, &requestProblem);
        if (!request || !request.HTTPBody || request.HTTPBody.length > 1024 * 1024) { receive(nil, requestProblem ?: unreadable()); return; }
        SGLyricsTranslationSendRequest(request, YES, ^BOOL { return generation == SGLyricsCredentialGeneration(SGLyricsAIOpenAI); }, ^(NSData *data, NSInteger status, NSError *error) {
            if (generation != SGLyricsCredentialGeneration(SGLyricsAIOpenAI)) { receive(nil, SGLyricsKeyChangedProblem()); return; }
            NSString *problem = nil;
            NSArray *translated = nil;
            if (error) problem = SGL(@"settings.translation.openai.error.unreachable", @"The translation service could not be reached.");
            else if (status == 401 || status == 403) problem = SGL(@"settings.translation.openai.error.keyinvalid", @"The translation service turned the key down. Check it in Lyrics › Translation & AI.");
            else if (status == 429 || (status >= 500 && status <= 599)) problem = SGL(@"settings.translation.openai.error.busy", @"The translation service is busy right now. Try again in a minute.");
            else if (status != 200) problem = [NSString stringWithFormat:SGL(@"settings.translation.openai.error.status", @"The service did not translate the song (%ld)."), (long)status];
            else {
                id root = data && data.length <= 512 * 1024 ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
                translated = SGOpenAIReplyIn(root, rows.count, format);
                if (!translated) problem = unreadable();
            }
            SGLog(@"openai translation: %lu lines, status %ld, %@", (unsigned long)rows.count, (long)status, translated ? @"parsed" : @"failed");
            receive(translated, problem);
        });
        }, ^(NSArray *translated, NSString *problem) {
            if (generation != SGLyricsCredentialGeneration(SGLyricsAIOpenAI)) { done(nil, SGLyricsKeyChangedProblem()); return; }
            if (translated && !problem) {
                if (trackID) {
                    if (sg_done.count >= 32) [sg_done removeAllObjects];
                    sg_done[memo] = @{@"texts": [texts copy], @"translations": translated, @"base": base, @"model": model};
                }
            }
            done(translated, problem);
        });
    });
}

#pragma mark - the row

static void textField(UITextField *field) {
    field.autocorrectionType = UITextAutocorrectionTypeNo;
    field.autocapitalizationType = UITextAutocapitalizationTypeNone;
}

// The address alone: the old one migrates its legacy key first, and the new host keeps a key of its own.
static void askForBase(void) {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:SGL(@"settings.translation.openai.base.title", @"Address")
        message:SGL(@"settings.translation.openai.base.message", @"Use HTTPS. Local and tailnet addresses also accept HTTP, which sends your API key and lyrics without TLS. Only save an HTTP address if you trust the network and server.")
        preferredStyle:UIAlertControllerStyleAlert];
    __weak UIAlertController *weakAlert = alert;
    UIAlertAction *save = [UIAlertAction actionWithTitle:SGL(@"common.save", @"Save") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *base = [weakAlert.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (!SGOpenAICompletionURL(base) || !migrateKey()) return;
        [NSUserDefaults.standardUserDefaults setObject:base forKey:SGKeyLyricsOpenAIBaseURL];
        [sg_done removeAllObjects];
        SGLyricsTranslationServiceSettingsChanged();
    }];
    __weak UIAlertAction *weakSave = save;
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        textField(field);
        field.placeholder = SGL(@"settings.translation.openaikey.baseurl", @"Base URL");
        field.text = setting(SGKeyLyricsOpenAIBaseURL, kBase);
        field.keyboardType = UIKeyboardTypeURL;
        [field addAction:[UIAction actionWithHandler:^(UIAction *action) {
            weakSave.enabled = SGOpenAICompletionURL([weakAlert.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]) != nil;
        }] forControlEvents:UIControlEventEditingChanged];
    }];
    save.enabled = SGOpenAICompletionURL(setting(SGKeyLyricsOpenAIBaseURL, kBase)) != nil;
    [alert addAction:save];
    [alert addAction:[UIAlertAction actionWithTitle:SGL(@"common.cancel", @"Cancel") style:UIAlertActionStyleCancel handler:nil]];
    SGPresentDark(alert);
    [SGTopController() presentViewController:alert animated:YES completion:nil];
}
SGModRow *SGOpenAIBaseURLRow(void) {
    return SGStatActionRow(SGL(@"settings.translation.openai.base.title", @"Address"), nil, ^NSString *{
        return SGOpenAIKeyHost(setting(SGKeyLyricsOpenAIBaseURL, kBase)) ?: SGL(@"settings.translation.openai.base.invalid", @"Check it");
    }, ^{ askForBase(); });
}

// The key for the stored address's host; an address that cannot take one is asked for first.
static void askForKey(void) {
    NSString *base = setting(SGKeyLyricsOpenAIBaseURL, kBase), *host = SGOpenAIKeyHost(base);
    if (!host) { askForBase(); return; }
    SGLyricsCredentialPrompt(SGL(@"settings.translation.ai.key.title", @"API key"),
        [NSString stringWithFormat:SGL(@"settings.translation.openaikey.alert.message", @"The song's lyrics go to %@, on your own API key. The key is kept for that host and stays on this iPhone."), host],
        SGL(@"settings.translation.openaikey.key", @"API key"),
        ^BOOL(NSString *text) { return cleanKey(text).length > 0; }, ^(NSString *text) {
        NSString *key = cleanKey(text);
        OSStatus read;
        if (!key.length || [readKey(host, &read) isEqualToString:key]) return;   // the same key again changes nothing, so no job is cut off
        if (migrateKey() && storeKey(key, host)) SGLyricsTranslationServiceSettingsChanged(); else SGLyricsAlertKeyNotSaved();
    }, ^BOOL { return SGOpenAIKeySet(); }, ^{ if (storeKey(nil, host)) SGLyricsTranslationServiceSettingsChanged(); else SGLyricsAlertKeyNotRemoved(); });
}
SGModRow *SGOpenAIKeyRow(void) {
    return SGStatActionRow(SGL(@"settings.translation.ai.key.title", @"API key"), nil,
        ^NSString *{ return SGOpenAIKeySet() ? SGL(@"settings.translation.openaikey.set", @"Set") : SGL(@"common.off", @"Off"); }, ^{ askForKey(); });
}

// Each preset changes the address and model; only a key saved for its host can be used.
NSArray<NSDictionary<NSString *, NSString *> *> *SGOpenAIPresets(void) {
    return @[
        @{@"name": @"OpenAI", @"base": @"https://api.openai.com/v1", @"model": @"gpt-4o-mini"},
        @{@"name": @"OpenRouter", @"base": @"https://openrouter.ai/api/v1", @"model": @"openai/gpt-4o-mini"},
        @{@"name": @"Groq", @"base": @"https://api.groq.com/openai/v1", @"model": @"llama-3.3-70b-versatile"},
        @{@"name": @"Perplexity", @"base": @"https://api.perplexity.ai", @"model": @"sonar"},
        @{@"name": @"Pollinations", @"base": @"https://gen.pollinations.ai", @"model": @"openai"}
    ];
}
NSString *SGOpenAIPresetName(void) {
    NSURL *url = SGOpenAICompletionURL(setting(SGKeyLyricsOpenAIBaseURL, kBase));
    for (NSDictionary *preset in SGOpenAIPresets()) {
        if ([url isEqual:SGOpenAICompletionURL(preset[@"base"])]) return preset[@"name"];
    }
    return nil;
}
SGModRow *SGOpenAIPresetRow(void) {
    NSMutableArray *names = [NSMutableArray array];
    for (NSDictionary *preset in SGOpenAIPresets()) [names addObject:preset[@"name"]];
    [names addObject:SGL(@"settings.translation.openai.preset.custom", @"Custom")];
    return SGMenuRow(SGL(@"settings.translation.openai.preset.title", @"Service"), names,
        ^NSString *{
            NSString *name = SGOpenAIPresetName() ?: SGL(@"settings.translation.openai.preset.custom", @"Custom");
            return SGOpenAIKeySet() ? name : [name stringByAppendingString:SGL(@"settings.translation.openai.preset.nokey", @" · no key")];
        }, ^(NSInteger index) {
            NSArray *presets = SGOpenAIPresets();
            if (index < 0 || (NSUInteger)index >= presets.count) return;
            NSDictionary *preset = presets[index];
            if (!migrateKey()) return;
            [NSUserDefaults.standardUserDefaults setObject:preset[@"base"] forKey:SGKeyLyricsOpenAIBaseURL];
            [NSUserDefaults.standardUserDefaults setObject:preset[@"model"] forKey:SGKeyLyricsOpenAIModel];
            SGLyricsTranslationServiceSettingsChanged();
            [sg_done removeAllObjects];
        });
}

NSURLRequest *SGOpenAIModelsRequest(NSString **problem) {
    NSString *base = setting(SGKeyLyricsOpenAIBaseURL, kBase), *key = storedKey(base);
    NSURL *endpoint = SGOpenAIModelsURL(base);
    if (!endpoint) { *problem = SGL(@"settings.translation.openai.error.settings", @"Check the translation service's base URL and model in Lyrics › Translation & AI."); return nil; }
    if (!key) { *problem = SGL(@"settings.translation.models.error.nokey", @"Save an API key first, and its models are listed here."); return nil; }
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:endpoint];
    [request setValue:[@"Bearer " stringByAppendingString:key] forHTTPHeaderField:@"Authorization"];
    return request;
}

NSURLRequest *SGOpenAIRequest(NSString *system, NSString *prompt, SGLyricsReplyFormat format, NSString **problem) {
    NSString *base = setting(SGKeyLyricsOpenAIBaseURL, kBase);
    NSString *key = storedKey(base), *model = SGOpenAIModel();
    NSURL *endpoint = SGOpenAICompletionURL(base);
    if (!key) { *problem = SGL(@"settings.translation.openai.error.nokey", @"Add an OpenAI-compatible API key in Lyrics › Translation & AI first."); return nil; }
    if (!endpoint) { *problem = SGL(@"settings.translation.openai.error.settings", @"Check the translation service's base URL and model in Lyrics › Translation & AI."); return nil; }
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:endpoint];
    request.HTTPMethod = @"POST";
    request.timeoutInterval = 60;
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request setValue:[@"Bearer " stringByAppendingString:key] forHTTPHeaderField:@"Authorization"];
    NSMutableDictionary *body = [@{@"model": model, @"messages": @[
        @{@"role": @"system", @"content": system}, @{@"role": @"user", @"content": prompt}]} mutableCopy];
    if (format == SGLyricsReplyProse) body[@"max_tokens"] = @(SGLyricsAIProseOutputTokens(SGLyricsAIOpenAI));
    request.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];
    return request;
}
