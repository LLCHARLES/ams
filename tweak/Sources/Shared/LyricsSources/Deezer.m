// Deezer needs the user's own login cookie. Only the Keychain keeps it between launches; the short
// lived JWT stays in memory and is replaced once when a lyrics request says it has expired.
#import <Security/Security.h>
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Settings/SGPageStyle.h"
#import "LyricsSources.h"

static NSString *sg_jwt;
static NSUInteger sg_generation;
static NSString *sg_arl;
static BOOL sg_arlLoaded;
static NSTimeInterval sg_authRefusedUntil;

static NSDictionary *keyQuery(void) {
    // Both lookup and reset must use the original Keychain service to reach existing credentials.
    return @{(__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
             (__bridge id)kSecAttrService: @"Vitrine.Deezer", (__bridge id)kSecAttrAccount: @"arl"};
}

static NSString *storedARL(SGLyricsRequestContext *context) {
    if (sg_arlLoaded) return sg_arl;
    NSMutableDictionary *query = [keyQuery() mutableCopy];
    query[(__bridge id)kSecReturnData] = @YES;
    query[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitOne;
    CFTypeRef data = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &data);
    if (status != errSecSuccess && status != errSecItemNotFound) {
        [context noteFailure:YES];
        SGLyricsNoteReply(nil, [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil]);
        return nil;
    }
    sg_arlLoaded = YES;
    if (status == errSecItemNotFound || !data) return nil;
    id value = CFBridgingRelease(data);
    if ([value isKindOfClass:NSData.class] && [value length] <= 4096)
        sg_arl = [[NSString alloc] initWithData:value encoding:NSUTF8StringEncoding];
    if (!sg_arl) {
        sg_arlLoaded = NO;
        [context noteFailure:YES];
    }
    return sg_arl;
}

BOOL SGDeezerARLSet(void) { return storedARL(nil).length > 0; }

// Clear Keychain: the ARL goes and the JWT signed in with it is dropped, so no request uses either; the
// order is a setting, so it stays.
BOOL SGDeezerForgetKey(void) {
    OSStatus status = SecItemDelete((__bridge CFDictionaryRef)@{(__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
                                                                (__bridge id)kSecAttrService: @"Vitrine.Deezer"});
    sg_jwt = nil;
    sg_arl = nil;
    sg_arlLoaded = NO;
    sg_authRefusedUntil = 0;
    sg_generation++;
    if (status != errSecSuccess && status != errSecItemNotFound) SGLog(@"deezer: the ARL could not be cleared (%d)", (int)status);
    return status == errSecSuccess || status == errSecItemNotFound;
}

static BOOL safeARL(NSString *arl) {
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.~"];
    return arl.length > 0 && arl.length <= 4096 && [arl rangeOfCharacterFromSet:allowed.invertedSet].location == NSNotFound;
}

static BOOL storeARL(NSString *arl) {
    OSStatus status;
    if (!arl.length) {
        status = SecItemDelete((__bridge CFDictionaryRef)keyQuery());
        if (status == errSecItemNotFound) status = errSecSuccess;
    } else {
        NSDictionary *attributes = @{(__bridge id)kSecValueData: [arl dataUsingEncoding:NSUTF8StringEncoding],
            (__bridge id)kSecAttrAccessible: (__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly};
        status = SecItemUpdate((__bridge CFDictionaryRef)keyQuery(), (__bridge CFDictionaryRef)attributes);
        if (status == errSecItemNotFound) {
            NSMutableDictionary *item = [keyQuery() mutableCopy];
            [item addEntriesFromDictionary:attributes];
            status = SecItemAdd((__bridge CFDictionaryRef)item, NULL);
        }
    }
    if (status != errSecSuccess) { SGLog(@"deezer: Keychain write failed (%d)", (int)status); return NO; }
    sg_jwt = nil;
    sg_arl = nil;
    sg_arlLoaded = NO;
    sg_authRefusedUntil = 0;
    sg_generation++;
    NSMutableArray *order = [SGLyricsOrder() mutableCopy];
    [order removeObject:@"deezer"];
    if (arl.length) [order addObject:@"deezer"];
    SGLyricsSetOrder(order);
    return YES;
}

static NSArray<SGKaraokeLine *> *wordLines(id rows) {
    if (![rows isKindOfClass:NSArray.class] || [rows count] > 2000) return nil;
    NSMutableArray *lines = [NSMutableArray array];
    for (id row in rows) {
        double start, end;
        if (!SGLyricsNumber(SGLyricsField(row, @"start"), &start) || !SGLyricsNumber(SGLyricsField(row, @"end"), &end) || end < start) return nil;
        id pieces = SGLyricsField(row, @"words");
        if (![pieces isKindOfClass:NSArray.class] || [pieces count] > 1000) return nil;
        NSMutableArray<SGKaraokeWord *> *words = [NSMutableArray array];
        NSInteger previous = -1;
        for (id piece in pieces) {
            double at, until;
            NSString *text = [SGLyricsString(SGLyricsField(piece, @"word"), 1024) stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            if (!text || !SGLyricsNumber(SGLyricsField(piece, @"start"), &at) || !SGLyricsNumber(SGLyricsField(piece, @"end"), &until) || until < at || at < previous) return nil;
            if (!text.length) continue;
            SGKaraokeWord *word = [SGKaraokeWord new];
            word.text = text;
            word.start = llround(at);
            word.end = MAX(word.start + 1, llround(until));
            [words addObject:word];
            previous = word.start;
        }
        if (!words.count) continue;
        SGKaraokeLine *line = [SGKaraokeLine new];
        line.words = words;
        line.start = MIN(llround(start), words.firstObject.start);
        line.end = llround(end);
        for (SGKaraokeWord *word in words) line.end = MAX(line.end, word.end);
        line.timing = SGKaraokeTimingWords;
        [lines addObject:line];
    }
    return lines.count ? lines : nil;
}

SGLyricsResult *SGDeezerResult(id root) {
    id lyrics = SGLyricsField(SGLyricsField(SGLyricsField(root, @"data"), @"track"), @"lyrics");
    SGLyricsResult *words = SGLyricsResultWithLines(wordLines(SGLyricsField(lyrics, @"synchronizedWordByWordLines")), @"Deezer");
    if (words) return words;
    id rows = SGLyricsField(lyrics, @"synchronizedLines");
    if ([rows isKindOfClass:NSArray.class] && [rows count] <= 2000) {
        NSMutableArray *sorted = [NSMutableArray array];
        for (id row in rows) {
            double at;
            NSString *text = SGLyricsString(SGLyricsField(row, @"line"), 4096);
            if (text && SGLyricsNumber(SGLyricsField(row, @"milliseconds"), &at)) [sorted addObject:@{@"at": @(llround(at)), @"text": text}];
        }
        [sorted sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) { return [a[@"at"] compare:b[@"at"]]; }];
        SGLyricsResult *lines = SGLyricsResultWithLines(SGKaraokeEstimatedLines([sorted valueForKey:@"at"], [sorted valueForKey:@"text"]), @"Deezer");
        if (lines) return lines;
    }
    return SGLyricsPlainTextResult(SGLyricsField(lyrics, @"text"), @"Deezer");
}

static NSString *songFor(id root, SGLyricsQuery *query) {
    id list = SGLyricsField(root, @"data");
    if (![list isKindOfClass:NSArray.class] || [list count] > 100) return nil;
    for (id song in list) {
        NSString *title = SGLyricsString(SGLyricsField(song, @"title"), 1024);
        NSString *artist = SGLyricsString(SGLyricsField(SGLyricsField(song, @"artist"), @"name"), 1024);
        if (![SGLyricsMatchKey(title) isEqualToString:SGLyricsMatchKey(query.title)] || !SGLyricsSameArtist(artist, query.artist)) continue;
        double length;
        if (SGLyricsNumber(SGLyricsField(song, @"duration"), &length) && length > 0 && query.seconds > 0 && fabs(length - query.seconds) > 4) continue;
        NSString *songID = SGLyricsDecimalID(SGLyricsField(song, @"id"));
        if (songID) return songID;
    }
    return nil;
}

static id json(NSData *data) { return data.length ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil; }

static void token(SGLyricsRequestContext *context, NSString *arl, NSUInteger generation, void (^done)(NSString *)) {
    if (generation != sg_generation) { done(nil); return; }
    if (sg_jwt.length) { done(sg_jwt); return; }
    SGLyricsSourceRequestIn(context, [NSURL URLWithString:@"https://auth.deezer.com/login/arl?jo=p&rto=c&i=c"], @{@"Cookie": [@"arl=" stringByAppendingString:arl]}, NSData.data, ^(NSData *data, NSInteger status) {
        NSString *jwt = status == 200 ? SGLyricsString(SGLyricsField(json(data), @"jwt"), 16384) : nil;
        NSCharacterSet *safe = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_."];
        if (!jwt.length || [jwt rangeOfCharacterFromSet:safe.invertedSet].location != NSNotFound || generation != sg_generation) {
            [context noteFailure:YES];
            if (generation == sg_generation && (status == 400 || status == 401 || status == 403))
                sg_authRefusedUntil = NSProcessInfo.processInfo.systemUptime + SGLyricsCredentialPauseSeconds;
            done(nil);
            return;
        }
        sg_jwt = jwt;
        done(jwt);
    });
}

static BOOL authError(id root, NSInteger status) {
    if (status == 401 || status == 403) return YES;
    id errors = SGLyricsField(root, @"errors");
    if (![errors isKindOfClass:NSArray.class] || [errors count] > 100) return NO;
    for (id error in errors) {
        NSString *code = SGLyricsString(SGLyricsField(SGLyricsField(error, @"extensions"), @"code"), 128);
        NSString *message = SGLyricsString(SGLyricsField(error, @"message"), 1024).lowercaseString;
        NSString *type = SGLyricsString(SGLyricsField(error, @"type"), 128);
        if ([@[@"UNAUTHENTICATED", @"UNAUTHORIZED", @"FORBIDDEN", @"TOKEN_EXPIRED", @"INVALID_TOKEN"] containsObject:code ?: @""] ||
            [type isEqual:@"JwtTokenMissingError"] ||
            [message containsString:@"unauthenticated"] || [message containsString:@"unauthorized"] ||
            ([message containsString:@"token"] && ([message containsString:@"expired"] || [message containsString:@"invalid"]))) return YES;
    }
    return NO;
}

static void lyrics(SGLyricsRequestContext *context, NSString *song, NSString *arl, NSUInteger generation, BOOL retried, void (^done)(SGLyricsResult *)) {
    token(context, arl, generation, ^(NSString *jwt) {
        if (!jwt) { done(nil); return; }
        NSDictionary *body = @{@"operationName": @"GetLyrics", @"variables": @{@"trackId": song}, @"query": @"query GetLyrics($trackId: String!) { track(trackId: $trackId) { id lyrics { id text synchronizedLines { lrcTimestamp line milliseconds duration } synchronizedWordByWordLines { start end words { start end word } } } } }"};
        SGLyricsSourceRequestIn(context, [NSURL URLWithString:@"https://pipe.deezer.com/api"], @{@"Authorization": [@"Bearer " stringByAppendingString:jwt], @"Content-Type": @"application/json"}, [NSJSONSerialization dataWithJSONObject:body options:0 error:nil], ^(NSData *data, NSInteger status) {
            if (generation != sg_generation) { done(nil); return; }
            id root = json(data);
            if (authError(root, status)) {
                [context noteFailure:YES];
                if ([sg_jwt isEqualToString:jwt]) sg_jwt = nil;
                if (!retried) { lyrics(context, song, arl, generation, YES, done); return; }
                sg_authRefusedUntil = NSProcessInfo.processInfo.systemUptime + SGLyricsCredentialPauseSeconds;
                done(nil);
                return;
            }
            SGLyricsResult *result = status == 200 ? SGDeezerResult(root) : nil;
            id errors = SGLyricsField(root, @"errors");
            if (status == 200 && (![root isKindOfClass:NSDictionary.class] ||
                SGLyricsField(SGLyricsField(root, @"data"), @"track") == NSNull.null ||
                ([errors isKindOfClass:NSArray.class] && [errors count]))) [context noteFailure:YES];
            SGLog(@"deezer: %lu lines", (unsigned long)result.karaokeLines.count);
            done(result);
        });
    });
}

// The harness supplies a made-up cookie here; it never reads or writes the user's Keychain.
void SGDeezerAskWith(NSString *arl, SGLyricsQuery *query, void (^done)(SGLyricsResult *));
void SGDeezerAskWith(NSString *arl, SGLyricsQuery *query, void (^done)(SGLyricsResult *)) {
    if (!NSThread.isMainThread) { dispatch_async(dispatch_get_main_queue(), ^{ SGDeezerAskWith(arl, query, done); }); return; }
    if (!arl.length) { done(nil); return; }
    if (!safeARL(arl) || NSProcessInfo.processInfo.systemUptime < sg_authRefusedUntil) {
        [query.requestContext noteFailure:YES];
        done(nil);
        return;
    }
    if (!SGLyricsMatchKey(query.title).length || !SGLyricsMatchKey(query.artist).length) { done(nil); return; }
    NSUInteger generation = sg_generation;
    NSString *title = [query.title stringByReplacingOccurrencesOfString:@"\"" withString:@""];
    NSString *artist = [SGLyricsLeadArtist(query.artist) stringByReplacingOccurrencesOfString:@"\"" withString:@""];
    NSURL *url = SGLyricsURL(@"https://api.deezer.com/search", @{@"q": [NSString stringWithFormat:@"track:\"%@\" artist:\"%@\"", title, artist]});
    SGLyricsSourceRequestIn(query.requestContext, url, nil, nil, ^(NSData *data, NSInteger status) {
        id root = status == 200 ? json(data) : nil;
        id list = SGLyricsField(root, @"data");
        if (status == 200 && ![list isKindOfClass:NSArray.class]) [query.requestContext noteFailure:YES];
        if ([list isKindOfClass:NSArray.class] && ![list count])
            query.requestContext.emptyNameSearch = ^(SGLyricsQuery *again, void (^answer)(SGLyricsResult *)) { SGDeezerAskWith(arl, again, answer); };
        NSString *song = songFor(root, query);
        if (!song) { done(nil); return; }
        lyrics(query.requestContext, song, arl, generation, NO, done);
    });
}

SGLyricsAsk SGDeezerAsk = ^(SGLyricsQuery *query, void (^done)(SGLyricsResult *)) {
    if (!NSThread.isMainThread) { dispatch_async(dispatch_get_main_queue(), ^{ SGDeezerAsk(query, done); }); return; }
    SGDeezerAskWith(storedARL(query.requestContext), query, done);
};

static void askForARL(NSString *problem) {
    NSString *how = SGL(@"settings.lyricssources.deezer.alert.instructions", @"Paste your own Deezer login cookie (ARL). It stays on this iPhone in the Keychain and is sent only to Deezer to sign in.");
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:SGL(@"settings.lyricssources.deezer.row.title", @"Deezer ARL") message:problem ? [NSString stringWithFormat:@"%@\n\n%@", problem, how] : how preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.secureTextEntry = YES;
        field.placeholder = SGL(@"settings.lyricssources.deezer.field.placeholder", @"Your ARL cookie");
        field.keyboardType = UIKeyboardTypeASCIICapable;
        field.autocorrectionType = UITextAutocorrectionTypeNo;
        field.autocapitalizationType = UITextAutocapitalizationTypeNone;
        field.spellCheckingType = UITextSpellCheckingTypeNo;
    }];
    UIAlertAction *save = [UIAlertAction actionWithTitle:SGL(@"settings.lyricssources.deezer.action.save", @"Save") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *arl = [alert.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        alert.textFields.firstObject.text = @"";
        NSString *problem = !safeARL(arl) ? SGL(@"settings.lyricssources.deezer.alert.invalid", @"Paste only the ARL cookie value.") : !storeARL(arl) ? SGL(@"settings.lyricssources.deezer.alert.storage", @"The Keychain could not save this change. Please try again.") : nil;
        if (problem) dispatch_async(dispatch_get_main_queue(), ^{ askForARL(problem); });
    }];
    [alert addAction:save];
    if (SGDeezerARLSet()) [alert addAction:[UIAlertAction actionWithTitle:SGL(@"settings.lyricssources.deezer.action.remove", @"Remove") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        if (!storeARL(nil)) dispatch_async(dispatch_get_main_queue(), ^{ askForARL(SGL(@"settings.lyricssources.deezer.alert.storage", @"The Keychain could not save this change. Please try again.")); });
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:SGL(@"settings.lyricssources.deezer.action.cancel", @"Cancel") style:UIAlertActionStyleCancel handler:nil]];
    alert.preferredAction = save;
    [SGTopController() presentViewController:alert animated:YES completion:nil];
}

SGModRow *SGDeezerARLRow(void) {
    return SGStatActionRow(SGL(@"settings.lyricssources.deezer.row.title", @"Deezer ARL"), SGL(@"settings.lyricssources.deezer.row.subtitle", @"Lyrics with your own Deezer login cookie"),
        ^NSString *{ return SGDeezerARLSet() ? SGL(@"settings.lyricssources.deezer.status.set", @"Set") : SGL(@"settings.lyricssources.deezer.status.off", @"Off"); }, ^{ askForARL(nil); });
}
