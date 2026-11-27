#import <Foundation/Foundation.h>
#import <Security/Security.h>

// Replace in place: failure to save a new key must not destroy the old one.
static inline OSStatus SGStoreDeviceKey(NSDictionary *identity, NSString *key) {
    NSMutableDictionary *query = [identity mutableCopy];
    query[(__bridge id)kSecAttrSynchronizable] = @NO;
    if (!key.length) {
        OSStatus status = SecItemDelete((__bridge CFDictionaryRef)query);
        return status == errSecItemNotFound ? errSecSuccess : status;
    }
    NSDictionary *attributes = @{(__bridge id)kSecValueData:[key dataUsingEncoding:NSUTF8StringEncoding],
        (__bridge id)kSecAttrAccessible:(__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly};
    OSStatus status = SecItemUpdate((__bridge CFDictionaryRef)query, (__bridge CFDictionaryRef)attributes);
    if (status != errSecItemNotFound) return status;
    [query addEntriesFromDictionary:attributes];
    return SecItemAdd((__bridge CFDictionaryRef)query, NULL);
}
