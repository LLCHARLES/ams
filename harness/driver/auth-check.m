#import "Diagnostics/SGDriverAuth.h"
#import "Core/SGPrefs.h"
#import "App/About/SGDiagnosticRedaction.h"
#import "../harness-fail.h"
#import <Security/Security.h>

// Substitute only the Security calls, so this host check never accesses a login Keychain.
static NSMutableDictionary *items;
static NSString *identity(CFDictionaryRef query) {
    NSDictionary *q = (__bridge NSDictionary *)query;
    HARNESS_CHECK([q[(__bridge id)kSecClass] isEqual:(__bridge id)kSecClassGenericPassword]);
    return [NSString stringWithFormat:@"%@/%@", q[(__bridge id)kSecAttrService], q[(__bridge id)kSecAttrAccount]];
}
OSStatus DriverTestCopy(CFDictionaryRef query, CFTypeRef *result) {
    NSData *data = items[identity(query)];
    if (!data) return errSecItemNotFound;
    *result = CFBridgingRetain(data);
    return errSecSuccess;
}
OSStatus DriverTestUpdate(CFDictionaryRef query, CFDictionaryRef attributes) {
    if (!items[identity(query)]) return errSecItemNotFound;
    items[identity(query)] = ((__bridge NSDictionary *)attributes)[(__bridge id)kSecValueData];
    return errSecSuccess;
}
OSStatus DriverTestAdd(CFDictionaryRef query, CFTypeRef *result) {
    items[identity(query)] = ((__bridge NSDictionary *)query)[(__bridge id)kSecValueData];
    return errSecSuccess;
}

static void checkStorage(NSString *mode) {
    NSUserDefaults *store = NSUserDefaults.standardUserDefaults;
    id beforeToken = [store objectForKey:SGKeyDriverToken];
    id beforeMarker = [store objectForKey:SGKeyDriverTokenRotated];
    id beforeLegacy = [store objectForKey:@"spotifyglass.driver.token.rotated"];
    NSString *fixture = @"0123456789abcdef0123456789abcdef";
    NSString *item = @"Vitrine.Driver/token";
    NSString *existing = NSUUID.UUID.UUIDString.lowercaseString;
    existing = [existing stringByReplacingOccurrencesOfString:@"-" withString:@""];
    items = [NSMutableDictionary dictionary];
    if ([mode isEqual:@"existing"]) items[item] = [existing dataUsingEncoding:NSUTF8StringEncoding];
    if ([mode isEqual:@"fresh"]) [store removeObjectForKey:SGKeyDriverToken];
    else [store setObject:fixture forKey:SGKeyDriverToken];
    // An old wildcard backup can pre-seed this marker along with a known credential.
    [store setBool:YES forKey:@"spotifyglass.driver.token.rotated"];
    if ([mode isEqual:@"migrated"]) [store setBool:YES forKey:SGKeyDriverTokenRotated];
    else [store removeObjectForKey:SGKeyDriverTokenRotated];
    NSString *token = SGDriverToken();
    BOOL removed = [store objectForKey:SGKeyDriverToken] == nil;
    BOOL legacyRemoved = [store objectForKey:@"spotifyglass.driver.token.rotated"] == nil;
    // Restore the host harness's preferences before reporting any failure.
    if (beforeToken) [store setObject:beforeToken forKey:SGKeyDriverToken];
    else [store removeObjectForKey:SGKeyDriverToken];
    if (beforeMarker) [store setObject:beforeMarker forKey:SGKeyDriverTokenRotated];
    else [store removeObjectForKey:SGKeyDriverTokenRotated];
    if (beforeLegacy) [store setObject:beforeLegacy forKey:@"spotifyglass.driver.token.rotated"];
    else [store removeObjectForKey:@"spotifyglass.driver.token.rotated"];
    HARNESS_CHECK(legacyRemoved);
    HARNESS_CHECK(removed);
    HARNESS_CHECK(token.length == 32);
    HARNESS_CHECK([items[item] isEqual:[token dataUsingEncoding:NSUTF8StringEncoding]]);
    HARNESS_CHECK([SGDriverToken() isEqual:token]);
    if ([mode isEqual:@"migrated"]) HARNESS_CHECK([token isEqual:fixture]);
    else if ([mode isEqual:@"existing"]) HARNESS_CHECK([token isEqual:existing]);
    else {
        HARNESS_CHECK(![token isEqual:fixture]);
        NSCharacterSet *hex = [NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdef"];
        HARNESS_CHECK([token rangeOfCharacterFromSet:hex.invertedSet].location == NSNotFound);
    }
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        checkStorage(@(argv[1]));
        NSString *token = @"0123456789abcdef0123456789abcdef";
        HARNESS_CHECK(SGDriverRequestAuthorized(@"GET /state HTTP/1.1\r\nx-phone-token:\t0123456789abcdef0123456789abcdef \r\n\r\n", token));
        HARNESS_CHECK(!SGDriverRequestAuthorized(@"GET /state HTTP/1.1\r\nX-Phone-Token: 0123456789ABCDEF0123456789ABCDEF\r\n\r\n", token));
        HARNESS_CHECK(!SGDriverRequestAuthorized(@"GET /state HTTP/1.1\r\nX-Phone-Token: 0123456789abcdef0123456789abcdef\r\nx-phone-token: 0123456789abcdef0123456789abcdef\r\n\r\n", token));
        HARNESS_CHECK(!SGDriverRequestAuthorized(@"GET /state HTTP/1.1\r\nHost: phone\r\n\r\nX-Phone-Token: 0123456789abcdef0123456789abcdef\r\n", token));
        HARNESS_CHECK(!SGDriverRequestAuthorized(@"GET /state HTTP/1.1\r\nX-Phone-Token: short\r\n\r\n", token));
        HARNESS_CHECK(!SGDriverRequestAuthorized(@"GET /state HTTP/1.1\r\nX-Phone-Token: short\r\n\r\n", @"short"));
        NSString *longToken = [token stringByAppendingString:[@"" stringByPaddingToLength:256 withString:@"x" startingAtIndex:0]];
        NSString *longRequest = [NSString stringWithFormat:@"GET /state HTTP/1.1\r\nX-Phone-Token: %@\r\n\r\n", longToken];
        HARNESS_CHECK(!SGDriverRequestAuthorized(longRequest, token));
        HARNESS_CHECK(!SGDriverRequestAuthorized(longRequest, longToken));
        HARNESS_CHECK(!SGDriverRequestAuthorized(@"GET /state HTTP/1.1\r\nX-Phone-Token: 0123456789abcdef0123456789abcdef0\r\n\r\n", token));
        HARNESS_CHECK(!SGDriverRequestAuthorized(@"GET /state HTTP/1.1\r\nX-Phone-Token: 0123456789abcdef0123456789abcdee\r\n\r\n", token));
        HARNESS_CHECK(!SGDriverRequestAuthorized(@"GET /state HTTP/1.1\r\nX-Phone-Token: 0123456789abcdef0123456789abcdef\r\n extra\r\n\r\n", token));
        HARNESS_CHECK(!SGDriverRequestAuthorized(@"GET /state HTTP/1.1\r\nX-Phone-Token: 0123456789abcdef0123456789abcdef\r\n", token));
        NSDictionary *private = @{
            @"spotifyglass.driver.token": @"driver-fixture",
            @"spotifyglass.musixmatch.token": @"music-fixture",
            @"spotifyglass.motion.token": @"motion-fixture",
        };
        NSString *diagnostics = @"keep\nspotifyglass.driver.token=driver-fixture\nspotifyglass.musixmatch.token=music-fixture\nspotifyglass.motion.token=motion-fixture\nvitrine.private.driver.token.rotated\nspotifyglass.driver.token.rotated\n";
        HARNESS_CHECK([SGRedactDiagnostics(diagnostics, private) isEqualToString:@"keep\n[redacted]=[redacted]\n[redacted]=[redacted]\n[redacted]=[redacted]\n[redacted]\n[redacted]\n"]);
        HARNESS_CHECK([SGRedactDiagnostics(@"before\ndriver: tailnet listener on phone:8085, token old-fixture\nafter", @{}) isEqualToString:@"before\n[redacted]\nafter"]);
        HARNESS_CHECK([SGRedactDiagnostics(@"prefix secret\nline suffix", @{@"spotifyglass.motion.token": @"secret\nline"}) isEqualToString:@"prefix [redacted] suffix"]);
        HARNESS_CHECK([SGRedactDiagnostics(@"ordinary", @{@"spotifyglass.title": @"ordinary"}) isEqualToString:@"ordinary"]);
        HARNESS_CHECK([SGRedactDiagnostics(@"spotifyglass.lyrics.openai.baseURL=https://example.test/v1",
            @{@"spotifyglass.lyrics.openai.baseURL":@"https://example.test/v1"}) isEqual:@"[redacted]=[redacted]"]);
        HARNESS_CHECK([SGRedactDiagnostics(@"Bearer fixture.123 sl_pk_fixture sk-fixture AIzafixture", @{})
            isEqual:@"[redacted] [redacted] [redacted] [redacted]"]);
        NSString *providerLog = @"Authorization: DeepL-Auth-Key fixture:fx\nstandalone sl_pk_fake!./?=tail done\nBearer sl_pk_fake!tail";
        HARNESS_CHECK([SGRedactDiagnostics(providerLog, @{}) isEqual:@"Authorization: [redacted]\nstandalone [redacted] done\n[redacted]"]);
        HARNESS_CHECK([SGRedactDiagnostics(@"proxy proxy.example username example-user",
            @{@"spotifyglass.wireguard":@{@"host":@"proxy.example",@"username":@"example-user"}})
            isEqual:@"proxy [redacted] username [redacted]"]);
        puts("driver auth: PASS");
    }
    return 0;
}
