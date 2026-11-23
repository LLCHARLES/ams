#import "SponsorBlock.h"

NSString *SGSponsorBlockBehaviorKey(NSString *category) {
    return [@"spotifyglass.sponsorblock.behavior." stringByAppendingString:category];
}

SGSponsorBlockBehavior SGSponsorBlockReadBehavior(NSUserDefaults *store, NSString *category) {
    id value = [store objectForKey:SGSponsorBlockBehaviorKey(category)];
    if (value) {
        for (NSInteger i = SGBlockAuto; i <= SGBlockOff; i++)
            if ([value isEqual:@(i)] || [value isEqual:@(i).stringValue]) return i;
        return SGBlockOff;
    }
    id old = [store objectForKey:SGSponsorBlockCategoryKey(category)];
    BOOL on = old ? ([old respondsToSelector:@selector(boolValue)] && [old boolValue])
                  : SGSponsorBlockCategoryDefault(category);
    return on ? SGBlockAuto : SGBlockOff;
}

double SGSponsorBlockMinimum(void) {
    id value = [NSUserDefaults.standardUserDefaults objectForKey:SGKeySponsorBlockMinimum];
    if (![value isKindOfClass:NSNumber.class]) return 1;
    double seconds = [value doubleValue];
    return seconds >= 0 && seconds <= SGSponsorBlockMaxMinimum ? seconds : 1;
}

NSString *SGSponsorBlockValidServer(id value) {
    if (![value isKindOfClass:NSString.class] || ![value length] ||
        [value rangeOfCharacterFromSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].location != NSNotFound ||
        [value containsString:@"\\"]) return nil;
    NSURLComponents *url = [NSURLComponents componentsWithString:value];
    if (![url.scheme.lowercaseString isEqual:@"https"] || !url.host.length ||
        url.user || url.password || url.query || url.fragment || !url.URL ||
        (url.port && (url.port.integerValue < 1 || url.port.integerValue > 65535))) return nil;
    NSString *base = url.URL.absoluteString;
    while ([base hasSuffix:@"/"]) base = [base substringToIndex:base.length - 1];
    return base;
}

NSString *SGSponsorBlockServer(void) {
    return SGSponsorBlockValidServer([NSUserDefaults.standardUserDefaults objectForKey:SGKeySponsorBlockServer])
        ?: @"https://sponsor.ajay.app";
}

// Main only. An Undo may survive a reset, but cannot subtract from a later run of counters.
static NSUInteger statsGeneration;
dispatch_block_t SGSponsorBlockRecordSkip(NSUserDefaults *store, double seconds) {
    NSUInteger generation = statsGeneration;
    [store setInteger:[store integerForKey:SGKeySponsorBlockCount] + 1 forKey:SGKeySponsorBlockCount];
    [store setDouble:[store doubleForKey:SGKeySponsorBlockSaved] + seconds forKey:SGKeySponsorBlockSaved];
    return ^{
        if (generation != statsGeneration) return;
        [store setInteger:MAX(0, [store integerForKey:SGKeySponsorBlockCount] - 1) forKey:SGKeySponsorBlockCount];
        [store setDouble:MAX(0, [store doubleForKey:SGKeySponsorBlockSaved] - seconds) forKey:SGKeySponsorBlockSaved];
    };
}

void SGSponsorBlockResetStats(NSUserDefaults *store) {
    statsGeneration++;
    [store removeObjectForKey:SGKeySponsorBlockCount];
    [store removeObjectForKey:SGKeySponsorBlockSaved];
}
