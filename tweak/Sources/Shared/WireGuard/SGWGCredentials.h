#import <Foundation/Foundation.h>
#import <Security/Security.h>

#define SGWGDefaultsKey @"spotifyglass.wireguard"
#define SGWGKeychainService @"Vitrine.WireGuard"

// Also available in builds without the engine, after installing over one that had it.
static inline BOOL SGWGForgetAllCredentials(void) {
    NSDictionary *query = @{(__bridge id)kSecClass:(__bridge id)kSecClassGenericPassword,
                            (__bridge id)kSecAttrService:SGWGKeychainService};
    OSStatus status = SecItemDelete((__bridge CFDictionaryRef)query);
    if (status != errSecSuccess && status != errSecItemNotFound) return NO;
    [NSUserDefaults.standardUserDefaults removeObjectForKey:SGWGDefaultsKey];
    return YES;
}
