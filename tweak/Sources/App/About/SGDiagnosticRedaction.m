#import "SGDiagnosticRedaction.h"
#import "Core/SGPrefs.h"
#import "Shared/SponsorBlock/SponsorBlock.h"

NSString *SGRedactDiagnostics(NSString *text, NSDictionary<NSString *, id> *preferences) {
    NSMutableSet<NSString *> *terms = [SGPrivatePreferenceKeys() mutableCopy];
    [terms addObject:SGKeySponsorBlockServer];
    [terms addObject:SGKeyLyricsOpenAIBaseURL];
    [terms addObject:@"spotifyglass.wireguard"];
    id proxy = preferences[@"spotifyglass.wireguard"];
    if ([proxy isKindOfClass:NSDictionary.class]) {
        for (NSString *field in @[@"host", @"username"]) {
            id value = proxy[field];
            if ([value isKindOfClass:NSString.class] && [value length]) [terms addObject:value];
        }
    }
    [preferences enumerateKeysAndObjectsUsingBlock:^(NSString *key, id value, BOOL *stop) {
        if ((SGPrivatePreferenceKey(key) || [key isEqual:SGKeySponsorBlockServer] || [key isEqual:SGKeyLyricsOpenAIBaseURL]) &&
            [value isKindOfClass:NSString.class] && [value length]) [terms addObject:value];
    }];
    // Old driver logs can contain a credential that has since been rotated and is no longer stored.
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    for (NSString *line in [text componentsSeparatedByString:@"\n"]) {
        BOOL oldCredential = ([line containsString:@"driver: tailnet listener on "] && [line containsString:@", token "])
            || [line rangeOfString:@"X-Phone-Token" options:NSCaseInsensitiveSearch].location != NSNotFound;
        [lines addObject:oldCredential ? @"[redacted]" : line];
    }
    NSMutableString *safe = [[lines componentsJoinedByString:@"\n"] mutableCopy];
    // Keychain values are deliberately not read for export. Also catch credentials no longer stored.
    static NSRegularExpression *credential;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        credential = [NSRegularExpression regularExpressionWithPattern:
            @"(?i:DeepL-Auth-Key)[\\t ]+[^\\r\\n]+|(?i:Bearer)[\\t ]+[!-~]+|sl_pk_[!-~]+|(?:sk-|AIza)[A-Za-z0-9_-]+"
            options:0 error:NULL];
    });
    [credential replaceMatchesInString:safe options:0 range:NSMakeRange(0, safe.length) withTemplate:@"[redacted]"];
    // Longest first, so a private name or shorter value inside another credential cannot mask that match.
    NSArray<NSString *> *ordered = [terms.allObjects sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        return a.length > b.length ? NSOrderedAscending : a.length < b.length ? NSOrderedDescending : NSOrderedSame;
    }];
    for (NSString *term in ordered)
        [safe replaceOccurrencesOfString:term withString:@"[redacted]" options:0 range:NSMakeRange(0, safe.length)];
    return safe;
}
