#import "SGLocalize.h"

static NSString *const kBundleName = @"Retrine.bundle";

static NSArray<NSBundle *> *resourceBundles(void) {
    NSMutableArray<NSString *> *paths = [NSMutableArray array];
    NSString *inApp = [NSBundle.mainBundle pathForResource:kBundleName ofType:nil];
    if (inApp) [paths addObject:inApp];
    [paths addObject:[@"/var/jb/Library/Application Support" stringByAppendingPathComponent:kBundleName]];
    [paths addObject:[@"/Library/Application Support" stringByAppendingPathComponent:kBundleName]];
    NSMutableArray<NSBundle *> *bundles = [NSMutableArray array];
    for (NSString *path in paths) {
        NSBundle *bundle = [NSBundle bundleWithPath:path];
        if (bundle) [bundles addObject:bundle];
    }
    return bundles;
}

// Spotify's own language, which iOS picks from the languages Spotify has and the one set for it in Settings. An app
// with one localization (a harness) has no such choice, so the user's first language stands in for it.
static NSString *appLanguage(void) {
    NSBundle *main = NSBundle.mainBundle;
    if (main.localizations.count > 1) {
        NSString *language = main.preferredLocalizations.firstObject;
        if (language.length) return language;
    }
    return NSLocale.preferredLanguages.firstObject ?: @"en";
}

// The bundle's localization for that language: the identifier itself (zh-Hans), then language and script, then the
// language code alone (ko for ko-KR). Nothing matching means English.
static NSString *matchLanguage(NSString *wanted, NSArray<NSString *> *available) {
    NSString *normal = [wanted stringByReplacingOccurrencesOfString:@"_" withString:@"-"];
    if ([available containsObject:normal]) return normal;
    NSDictionary<NSString *, NSString *> *parts = [NSLocale componentsFromLocaleIdentifier:normal];
    NSString *code = parts[NSLocaleLanguageCode], *script = parts[NSLocaleScriptCode];
    if (code.length && script.length) {
        NSString *withScript = [NSString stringWithFormat:@"%@-%@", code, script];
        if ([available containsObject:withScript]) return withScript;
    }
    if (code.length && [available containsObject:code]) return code;
    return @"en";
}

// What each argument of a format string is read as, by its position: the length modifier and conversion ("@", "ld",
// "llu", ".1f" -> "f"), and "*" for a width or precision read from the arguments. A translation is used only when it
// reads the same arguments as the same types as the English, so it may reorder them with positions (%2$@) but never
// read one the English does not pass. Two reads of one position as different types give nil, which matches nothing.
// A % followed by anything else, a space included, is text ("100% of"). scripts/check-strings.py reads them the same way.
static NSDictionary<NSNumber *, NSString *> *specifiers(NSString *format) {
    NSMutableDictionary<NSNumber *, NSString *> *found = [NSMutableDictionary dictionary];
    NSInteger next = 1;
    NSUInteger length = format.length;
    BOOL (^read)(NSInteger, NSString *) = ^BOOL(NSInteger position, NSString *type) {
        NSString *before = found[@(position)];
        if (before && ![before isEqualToString:type]) return NO;
        found[@(position)] = type;
        return YES;
    };
    for (NSUInteger i = 0; i < length; i++) {
        if ([format characterAtIndex:i] != '%') continue;
        NSUInteger j = i + 1;
        if (j < length && [format characterAtIndex:j] == '%') { i = j; continue; }
        NSInteger position = 0;
        NSUInteger digits = j;
        while (digits < length && [format characterAtIndex:digits] >= '0' && [format characterAtIndex:digits] <= '9') {
            position = position * 10 + ([format characterAtIndex:digits] - '0');
            digits++;
        }
        if (digits > j && digits < length && [format characterAtIndex:digits] == '$') j = digits + 1;
        else position = 0;
        NSInteger stars = 0;
        while (j < length && [format characterAtIndex:j] < 128 && strchr("0123456789.-+#*", [format characterAtIndex:j])) {
            if ([format characterAtIndex:j] == '*') stars++;
            j++;
        }
        NSUInteger start = j;
        while (j < length && [format characterAtIndex:j] < 128 && strchr("hlqLzjt", [format characterAtIndex:j])) j++;
        if (j >= length) continue;
        unichar conversion = [format characterAtIndex:j];
        if (conversion >= 128 || !strchr("@dDiuUxXoOfFeEgGaAcCsSp", conversion)) continue;
        if (!position) {
            for (NSInteger s = 0; s < stars; s++) if (!read(next++, @"*")) return nil;
        } else if (stars) {
            return nil;   // a positional conversion with a * width: nothing here uses one, so it is never trusted
        }
        if (!read(position ?: next, [format substringWithRange:NSMakeRange(start, j + 1 - start)])) return nil;
        next = (position ?: next) + 1;
        i = j;
    }
    return found;
}

static NSString *sg_language = @"en";
static NSDictionary<NSString *, NSString *> *sg_table;

static void load(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSInteger choice = [NSUserDefaults.standardUserDefaults integerForKey:SGKeyLanguage];
        NSString *wanted = choice == 1 ? @"en" : choice == 2 ? @"ko" : appLanguage();
        // An explicit choice must not silently fall back to English just because one bundle lacks the
        // language (an old copy left inside the app shadows the deb's). Try every location and keep the
        // first one that actually resolves the wanted localization and yields a non-empty table.
        for (NSBundle *bundle in resourceBundles()) {
            NSString *language = matchLanguage(wanted, bundle.localizations);
            if ([language isEqualToString:@"en"]) continue;
            NSString *path = [bundle pathForResource:@"Localizable" ofType:@"strings" inDirectory:nil forLocalization:language];
            NSDictionary *table = path ? [NSDictionary dictionaryWithContentsOfFile:path] : nil;
            if (![table isKindOfClass:NSDictionary.class] || !table.count) continue;
            sg_table = table;
            sg_language = language;
            return;
        }
    });
}

NSString *SGL(NSString *key, NSString *english) {
    load();
    if (!sg_table || !key) return english;
    id text = sg_table[key];
    if (![text isKindOfClass:NSString.class] || ![text length]) return english;
    if ([english rangeOfString:@"%"].location != NSNotFound || [text rangeOfString:@"%"].location != NSNotFound) {
        NSDictionary *wanted = specifiers(english), *read = specifiers(text);
        if (!wanted || !read || ![wanted isEqualToDictionary:read]) return english;
    }
    return text;
}

NSString *SGLanguage(void) {
    load();
    return sg_language;
}
