#import "SGDiagnosticRedaction.h"
#import "Core/SGPrefs.h"
#import "Shared/SponsorBlock/SponsorBlock.h"

NSString *SGRedactDiagnostics(NSString *text, NSDictionary<NSString *, id> *preferences) {
    NSMutableSet<NSString *> *terms = [SGPrivatePreferenceKeys() mutableCopy];
    [terms addObject:SGKeySponsorBlockServer];
    [preferences enumerateKeysAndObjectsUsingBlock:^(NSString *key, id value, BOOL *stop) {
        if ((SGPrivatePreferenceKey(key) || [key isEqual:SGKeySponsorBlockServer]) &&
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
    // Longest first, so a private name or shorter value inside another credential cannot mask that match.
    NSArray<NSString *> *ordered = [terms.allObjects sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        return a.length > b.length ? NSOrderedAscending : a.length < b.length ? NSOrderedDescending : NSOrderedSame;
    }];
    for (NSString *term in ordered)
        [safe replaceOccurrencesOfString:term withString:@"[redacted]" options:0 range:NSMakeRange(0, safe.length)];
    return safe;
}
