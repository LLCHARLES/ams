#import "SGDriverAuth.h"
#import "Core/SGPrefs.h"

#if SG_DRIVER
#import "Core/SGKeychain.h"
enum { kDriverTokenRandomBytes = 16, kDriverTokenTextBytes = 2 * kDriverTokenRandomBytes };

NSString *SGDriverToken(void) {
    static NSString *token;
    @synchronized(NSUserDefaults.standardUserDefaults) {
        if (token) return token;
        NSDictionary *identity = @{(__bridge id)kSecClass:(__bridge id)kSecClassGenericPassword,
                                   (__bridge id)kSecAttrService:@"Vitrine.Driver",
                                   (__bridge id)kSecAttrAccount:@"token"};
        NSMutableDictionary *query = [identity mutableCopy];
        query[(__bridge id)kSecReturnData] = @YES;
        CFTypeRef result = NULL;
        OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
        NSData *data = CFBridgingRelease(result);
        NSUserDefaults *store = NSUserDefaults.standardUserDefaults;
        // The former wildcard importer could write the old marker. It is never evidence of migration.
        [store removeObjectForKey:SGKeyDriverTokenLegacyRotation];
        if (status == errSecSuccess) {
            token = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        } else if (status == errSecItemNotFound) {
            NSString *candidate = [store stringForKey:SGKeyDriverToken];
            id marker = [store objectForKey:SGKeyDriverTokenRotated];
            BOOL rotated = [marker isKindOfClass:NSNumber.class] && [marker boolValue];
            if (!rotated || [candidate lengthOfBytesUsingEncoding:NSUTF8StringEncoding] != kDriverTokenTextBytes) {
                uint8_t bytes[kDriverTokenRandomBytes];
                arc4random_buf(bytes, sizeof(bytes));
                NSMutableString *hex = [NSMutableString stringWithCapacity:kDriverTokenTextBytes];
                for (NSUInteger i = 0; i < sizeof(bytes); i++) [hex appendFormat:@"%02x", bytes[i]];
                candidate = hex;
            }
            if (SGStoreDeviceKey(identity, candidate) != errSecSuccess) return nil;
            token = [candidate copy];
        } else {
            return nil; // A locked Keychain is not an absent credential; retry on the next request.
        }
        if (token) {
            [store removeObjectForKey:SGKeyDriverToken];
            [store removeObjectForKey:SGKeyDriverTokenRotated];
        }
        return token;
    }
}

BOOL SGDriverRequestAuthorized(NSString *request, NSString *token) {
    NSRange end = [request rangeOfString:@"\r\n\r\n"];
    if (end.location == NSNotFound) return NO;
    NSArray<NSString *> *headers = [[request substringToIndex:end.location] componentsSeparatedByString:@"\r\n"];
    NSData *provided = nil;
    NSCharacterSet *spacing = [NSCharacterSet characterSetWithCharactersInString:@" \t"];
    for (NSUInteger i = 1; i < headers.count; i++) {
        NSString *line = headers[i];
        // Obsolete folded headers make the number of values ambiguous.
        if ([line hasPrefix:@" "] || [line hasPrefix:@"\t"]) return NO;
        NSRange colon = [line rangeOfString:@":"];
        if (colon.location == NSNotFound) return NO;
        NSString *name = [line substringToIndex:colon.location];
        if ([name caseInsensitiveCompare:@"X-Phone-Token"] != NSOrderedSame) continue;
        if (provided) return NO;
        NSString *value = [[line substringFromIndex:colon.location + 1] stringByTrimmingCharactersInSet:spacing];
        provided = [value dataUsingEncoding:NSUTF8StringEncoding];
    }
    NSData *expected = [token dataUsingEncoding:NSUTF8StringEncoding];
    uint8_t left[kDriverTokenTextBytes] = {0}, right[kDriverTokenTextBytes] = {0};
    [provided getBytes:left length:MIN(provided.length, sizeof(left))];
    [expected getBytes:right length:MIN(expected.length, sizeof(right))];
    // Keep the full length difference: narrowing to a byte would accept a matching prefix plus 256 bytes.
    volatile NSUInteger difference = (provided.length ^ kDriverTokenTextBytes) | (expected.length ^ kDriverTokenTextBytes);
    for (NSUInteger i = 0; i < kDriverTokenTextBytes; i++) difference |= left[i] ^ right[i];
    return difference == 0;
}
#endif
