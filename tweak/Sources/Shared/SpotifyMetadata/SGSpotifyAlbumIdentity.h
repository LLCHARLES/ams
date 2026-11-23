#import <Foundation/Foundation.h>

static NSString *const SGSpotifyBase62 = @"0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ";

static inline NSString *SGSpotifyTrackURIFromGID(id hex) {
    if (![hex isKindOfClass:NSString.class] || [hex length] != 32 ||
        [hex rangeOfString:@"^[0-9A-Fa-f]{32}$" options:NSRegularExpressionSearch].location == NSNotFound) return nil;
    uint8_t bytes[16];
    for (NSUInteger i = 0; i < sizeof(bytes); i++) {
        unsigned int value = 0;
        [[NSScanner scannerWithString:[hex substringWithRange:NSMakeRange(i * 2, 2)]] scanHexInt:&value];
        bytes[i] = value;
    }
    unichar identifier[22];
    for (NSInteger digit = 21; digit >= 0; digit--) {
        NSUInteger remainder = 0;
        for (NSUInteger i = 0; i < sizeof(bytes); i++) {
            NSUInteger value = remainder * 256 + bytes[i];
            bytes[i] = value / 62;
            remainder = value % 62;
        }
        identifier[digit] = [SGSpotifyBase62 characterAtIndex:remainder];
    }
    return [@"spotify:track:" stringByAppendingString:[NSString stringWithCharacters:identifier length:22]];
}

static inline BOOL SGSpotifyValidURI(NSString *uri, NSString *kind) {
    if (![uri isKindOfClass:NSString.class]) return NO;
    NSString *prefix = [NSString stringWithFormat:@"spotify:%@:", kind];
    if (![uri hasPrefix:prefix] || uri.length != prefix.length + 22) return NO;
    for (NSUInteger i = prefix.length; i < uri.length; i++) {
        if ([SGSpotifyBase62 rangeOfString:[uri substringWithRange:NSMakeRange(i, 1)]].location == NSNotFound) return NO;
    }
    return YES;
}

static inline NSString *SGSpotifyAlbumMetadataPath(NSString *albumURI) {
    if (!SGSpotifyValidURI(albumURI, @"album")) return nil;
    NSString *identifier = [albumURI substringFromIndex:@"spotify:album:".length];
    uint8_t gid[16] = {0};
    for (NSUInteger i = 0; i < identifier.length; i++) {
        NSUInteger carry = [SGSpotifyBase62 rangeOfString:[identifier substringWithRange:NSMakeRange(i, 1)]].location;
        for (NSInteger j = sizeof(gid) - 1; j >= 0; j--) {
            carry += gid[j] * 62;
            gid[j] = carry & 255;
            carry >>= 8;
        }
        if (carry) return nil; // A 22-digit base62 value need not fit Spotify's 128-bit GID.
    }
    NSMutableString *hex = [NSMutableString string];
    for (NSUInteger i = 0; i < sizeof(gid); i++) [hex appendFormat:@"%02x", gid[i]];
    return [NSString stringWithFormat:@"/metadata/4/album/%@?market=from_token", hex];
}
