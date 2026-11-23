#import <Foundation/Foundation.h>
#import "Shared/Lyrics/Lyrics.h"
#import "Shared/Lyrics/LyricsStore.h"
#import "Shared/LyricsSources/LyricsSources.h"
#import "credit-registry.inc"
#import "../sha256-fixture.h"
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAILED line %d: %s\n", __LINE__, #c); exit(1); } } while (0)

static NSString *sg_translationLanguage;
NSString *SGLyricsTranslationLanguage(void) { return sg_translationLanguage; }

static SGKaraokeLine *line(NSString *text, NSInteger start) {
    SGKaraokeWord *a = [SGKaraokeWord new], *b = [SGKaraokeWord new];
    a.text = text; a.start = start; a.end = start + 300;
    b.text = @"!"; b.start = start + 300; b.end = start + 500; b.joined = YES;
    SGKaraokeLine *l = [SGKaraokeLine new];
    l.words = @[a, b]; l.start = start; l.end = start + 500;
    l.voice = @"v2"; l.align = SGKaraokeAlignTrailing; l.timing = SGKaraokeTimingWords;
    return l;
}

static void pump(BOOL (^ready)(void)) {
    NSDate *until = [NSDate dateWithTimeIntervalSinceNow:5];
    while (!ready() && until.timeIntervalSinceNow > 0)
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.002]];
    CHECK(ready());
}

static unsigned long long size(void) {
    __block BOOL done = NO; __block unsigned long long bytes;
    SGLyricsStoreSize(^(unsigned long long n) { CHECK(NSThread.isMainThread); bytes = n; done = YES; });
    pump(^BOOL { return done; });
    return bytes;
}

static NSArray<SGKaraokeLine *> *load(NSString *track, NSString **credit) {
    __block BOOL done = NO; __block NSArray<SGKaraokeLine *> *result; __block NSString *provider;
    SGLyricsStoreLoad(track, ^(NSArray *lines, NSString *name, SGLyricsResult *metadata) {
        if (lines.count && metadata) SGLyricsNoteCredit(metadata);
        CHECK(NSThread.isMainThread); result = lines; provider = name; done = YES;
    });
    pump(^BOOL { return done; });
    if (credit) *credit = provider;
    return result;
}

static NSArray<NSURL *> *files(NSURL *dir) {
    return [NSFileManager.defaultManager contentsOfDirectoryAtURL:dir includingPropertiesForKeys:nil options:0 error:nil] ?: @[];
}

// Every fixture is a unique directory; it is the only tree this test deletes.
static NSURL *temp(void) {
    NSString *pattern = [NSTemporaryDirectory() stringByAppendingPathComponent:@"retrine-lyrics-XXXXXX"];
    char *path = strdup(pattern.fileSystemRepresentation);
    CHECK(mkdtemp(path));
    NSURL *url = [NSURL fileURLWithPath:[NSFileManager.defaultManager stringWithFileSystemRepresentation:path length:strlen(path)] isDirectory:YES];
    free(path);
    return url;
}

static void ageAll(NSURL *dir, NSTimeInterval time) {
    for (NSURL *url in files(dir)) CHECK([NSFileManager.defaultManager setAttributes:@{NSFileModificationDate: [NSDate dateWithTimeIntervalSince1970:time]}
        ofItemAtPath:url.path error:nil]);
}

static void checkTranslationLanguage(void) {
    NSURL *dir = temp();
    SGLyricsStoreConfigureForTests(dir, 1000, 30 * 1024 * 1024);
    SGKaraokeLine *source = line(@"Bonjour", 1000);
    source.translation = @"Hello"; source.translationLanguage = @"en";
    source.backing = line(@"Salut", 1100); source.backing.translation = @"Hi"; source.backing.translationLanguage = @"en";
    source.pronunciation = line(@"Bon-zhoor", 1000); source.pronunciation.translation = @"Reading translation";
    source.pronunciation.translationLanguage = @"en";
    // Reuse an English provider answer after changing the preference: saving cannot relabel it.
    sg_translationLanguage = @"ko";
    SGLyricsStoreSave(@"language", @[source], @"Language provider");
    size();
    NSURL *file = files(dir).firstObject;
    NSDictionary *record = [NSPropertyListSerialization propertyListWithData:[NSData dataWithContentsOfURL:file]
        options:0 format:nil error:nil];
    CHECK([record[@"lines"][0][@"translationLanguage"] isEqual:@"en"]);
    SGKaraokeLine *reused = load(@"language", NULL).firstObject;
    CHECK(reused && !reused.translation && !reused.backing.translation && !reused.pronunciation.translation);
    sg_translationLanguage = @"en";
    SGKaraokeLine *matched = load(@"language", NULL).firstObject;
    CHECK([matched.translation isEqual:@"Hello"] && [matched.backing.translation isEqual:@"Hi"]);
    CHECK([matched.pronunciation.translation isEqual:@"Reading translation"]);
    CHECK([matched.translationLanguage isEqual:@"en"] && [matched.backing.translationLanguage isEqual:@"en"]);

    // The selection changes while the read is pending, before its main-queue delivery.
    __block BOOL delivered = NO;
    SGLyricsStoreLoad(@"language", ^(NSArray<SGKaraokeLine *> *lines, NSString *credit, SGLyricsResult *metadata) {
        SGKaraokeLine *changed = lines.firstObject;
        CHECK(!changed.translation && !changed.backing.translation && !changed.pronunciation.translation);
        CHECK([changed.words.firstObject.text isEqual:@"Bonjour"] && changed.start == 1000 && changed.end == 1500);
        CHECK([changed.pronunciation.words.firstObject.text isEqual:@"Bon-zhoor"]);
        CHECK([credit isEqual:@"Language provider"] && [metadata.provider isEqual:@"Language provider"]);
        delivered = YES;
    });
    sg_translationLanguage = @"ko";
    pump(^BOOL { return delivered; });

    // Each nested line is filtered by its own provenance, not the lead line's language.
    source.backing.translation = @"안녕"; source.backing.translationLanguage = @"ko";
    SGLyricsStoreSave(@"language", @[source], @"Language provider");
    SGKaraokeLine *mixed = load(@"language", NULL).firstObject;
    CHECK(!mixed.translation && [mixed.backing.translation isEqual:@"안녕"] && !mixed.pronunciation.translation);
    source.backing.translation = @"Hi"; source.backing.translationLanguage = @"en";

    // Missing tags are the previous format; malformed/oversized tags also lose only translations.
    sg_translationLanguage = @"en";
    NSString *oversized = [@"x" stringByPaddingToLength:65537 withString:@"x" startingAtIndex:0];
    for (id language in @[NSNull.null, @42, @[], oversized]) {
        NSData *data = [NSPropertyListSerialization dataWithPropertyList:record format:NSPropertyListBinaryFormat_v1_0 options:0 error:nil];
        NSMutableDictionary *unknown = [NSPropertyListSerialization propertyListWithData:data
            options:NSPropertyListMutableContainers format:nil error:nil];
        NSMutableDictionary *lead = unknown[@"lines"][0];
        for (NSMutableDictionary *item in @[lead, lead[@"backing"], lead[@"pronunciation"]]) {
            if (language == NSNull.null) [item removeObjectForKey:@"translationLanguage"];
            else item[@"translationLanguage"] = language;
        }
        // The obsolete root field was a save-time preference, not trustworthy provenance.
        unknown[@"translationLanguage"] = @"en";
        CHECK([[NSPropertyListSerialization dataWithPropertyList:unknown format:NSPropertyListBinaryFormat_v1_0 options:0 error:nil]
            writeToURL:file atomically:YES]);
        SGKaraokeLine *restored = load(@"language", NULL).firstObject;
        CHECK(restored && !restored.translation && !restored.backing.translation && !restored.pronunciation.translation);
        CHECK([restored.words.firstObject.text isEqual:@"Bonjour"] && restored.words.firstObject.start == 1000);
        sg_translationLanguage = nil;
        CHECK([load(@"language", NULL).firstObject.translation isEqual:@"Hello"]);
        sg_translationLanguage = @"en";
    }
    // Any/unknown provider answers stay untagged even when saved under a specific preference.
    source.translationLanguage = nil; source.backing.translationLanguage = nil; source.pronunciation.translationLanguage = nil;
    sg_translationLanguage = @"ko";
    SGLyricsStoreSave(@"language", @[source], @"Language provider");
    size();
    NSDictionary *untagged = [NSPropertyListSerialization propertyListWithData:[NSData dataWithContentsOfURL:file] options:0 format:nil error:nil];
    CHECK(!untagged[@"lines"][0][@"translationLanguage"]);
    sg_translationLanguage = nil;
    CHECK([load(@"language", NULL).firstObject.translation isEqual:@"Hello"]);
    sg_translationLanguage = @"ko";
    CHECK(!load(@"language", NULL).firstObject.translation);
    sg_translationLanguage = nil;
    __block BOOL cleared = NO;
    SGLyricsStoreDeleteAll(^(unsigned long long remaining) { CHECK(remaining == 0); cleared = YES; });
    pump(^BOOL { return cleared; });
    puts("translation language: cached provenance, per-line filtering, changed selection, legacy and Any records passed");
}

int main(void) {
    @autoreleasepool {
        checkTranslationLanguage();
        SGKaraokeLine *lead = line(@"Hello", 1000);
        lead.backing = line(@"Oh", 1100); lead.pronunciation = line(@"Hel-lo", 1000);
        lead.note = @"A reference"; lead.translation = @"안녕"; lead.translationMade = YES;
        lead.backing.translation = @"오";
        SGKaraokeLine *ai = line(@"World", 2000);
        ai.pronunciation = line(@"Generated", 2000); ai.pronunciationMade = YES;
        NSArray *original = @[lead, ai];
        NSDictionary *record = SGLyricsStoreEncode(original, @"Fixture provider");
        NSData *data = [NSPropertyListSerialization dataWithPropertyList:record format:NSPropertyListBinaryFormat_v1_0 options:0 error:nil];
        CHECK(data && !record[@"lines"][0][@"translation"] && !record[@"lines"][0][@"translationMade"]);
        CHECK([record[@"lines"][0][@"backing"][@"translation"] isEqual:@"오"] && !record[@"lines"][1][@"pronunciation"]);
        NSString *credit;
        NSArray<SGKaraokeLine *> *round = SGLyricsStoreDecode([NSPropertyListSerialization propertyListWithData:data options:0 format:nil error:nil], &credit);
        CHECK(round.count == 2 && [credit isEqual:@"Fixture provider"]);
        SGKaraokeLine *decoded = round[0];
        CHECK([decoded.words[0].text isEqual:@"Hello"] && decoded.words[0].start == 1000 && decoded.words[0].end == 1300);
        CHECK(decoded.words[1].joined && !decoded.words[0].joined && decoded.start == 1000 && decoded.end == 1500);
        CHECK([decoded.voice isEqual:@"v2"] && decoded.align == SGKaraokeAlignTrailing && decoded.timing == SGKaraokeTimingWords);
        CHECK([decoded.backing.words[0].text isEqual:@"Oh"] && [decoded.pronunciation.words[0].text isEqual:@"Hel-lo"]);
        CHECK([decoded.note isEqual:@"A reference"] && !decoded.translation && !decoded.translationMade);
        CHECK([decoded.backing.translation isEqual:@"오"] && !decoded.backing.translationMade);
        CHECK(!round[1].pronunciation && round[1].pronunciationMade);
        CHECK(SGLyricsStoreDecode(SGLyricsStoreEncode(@[line(@"No credit", 0)], nil), &credit) && !credit);
        NSMutableDictionary *bad = [record mutableCopy]; bad[@"v"] = @2;
        CHECK(!SGLyricsStoreDecode(bad, &credit) && !credit);
        for (id garbage in @[@"garbage", @1, NSNull.null, @[], @{}, @{@"v": @1, @"lines": @[@"bad"]},
                              @{@"v": @1, @"lines": @[], @"credit": @7}]) CHECK(!SGLyricsStoreDecode(garbage, NULL));
        // A literal v1 record predating provider metadata remains readable.
        NSDictionary *legacy = @{@"v": @1, @"credit": @"Old provider", @"lines": @[
            @{@"words": @[@{@"text": @"Old lyrics", @"start": @1000, @"end": @1500, @"joined": @NO}],
              @"start": @1000, @"end": @1500, @"align": @0, @"timing": @1, @"pronunciationMade": @NO}]};
        SGKaraokeLine *old = SGLyricsStoreDecode(legacy, &credit).firstObject;
        CHECK([old.words.firstObject.text isEqual:@"Old lyrics"] && !old.translation && [credit isEqual:@"Old provider"]);
        NSString *oversized = [@"界" stringByPaddingToLength:22000 withString:@"界" startingAtIndex:0];
        for (id value in @[@42, @[], @{}, NSNull.null, oversized]) {
            NSMutableDictionary *damaged = [legacy[@"lines"][0] mutableCopy]; damaged[@"translation"] = value;
            SGKaraokeLine *restored = SGLyricsStoreDecode(@{@"v": @1, @"lines": @[damaged]}, NULL).firstObject;
            CHECK([restored.words.firstObject.text isEqual:@"Old lyrics"] && !restored.translation);
        }
        for (NSString *key in @[@"words", @"start", @"end", @"align", @"timing", @"voice", @"note", @"backing", @"pronunciation", @"pronunciationMade"]) {
            NSMutableDictionary *badLine = [record[@"lines"][0] mutableCopy]; badLine[key] = NSNull.null;
            CHECK(!SGLyricsStoreDecode(@{@"v": @1, @"lines": @[badLine]}, NULL));
        }
        NSMutableDictionary *badWord = [record[@"lines"][0][@"words"][0] mutableCopy];
        badWord[@"joined"] = @2;
        NSMutableDictionary *badLine = [record[@"lines"][0] mutableCopy]; badLine[@"words"] = @[badWord];
        CHECK(!SGLyricsStoreDecode(@{@"v": @1, @"lines": @[badLine]}, NULL));
        badLine[@"words"] = record[@"lines"][0][@"words"]; badLine[@"timing"] = @99;
        CHECK(!SGLyricsStoreDecode(@{@"v": @1, @"lines": @[badLine]}, NULL));
        badLine[@"timing"] = @0; badLine[@"start"] = @(NAN);
        CHECK(!SGLyricsStoreDecode(@{@"v": @1, @"lines": @[badLine]}, NULL));

        NSMutableArray *typical = [NSMutableArray array];
        for (NSInteger i = 0; i < 40; i++) {
            SGKaraokeLine *l = line(@"We sing together in the evening", i * 4000);
            NSMutableArray *words = [NSMutableArray array];
            NSInteger j = 0;
            for (NSString *text in [@"We sing together in the evening" componentsSeparatedByString:@" "]) {
                SGKaraokeWord *w = [SGKaraokeWord new];
                w.text = text; w.start = l.start + j * 500; w.end = w.start + 500; j++; [words addObject:w];
            }
            l.words = words; l.end = l.start + 3000; [typical addObject:l];
        }
        NSData *typicalData = [NSPropertyListSerialization dataWithPropertyList:SGLyricsStoreEncode(typical, @"Fixture provider")
            format:NSPropertyListBinaryFormat_v1_0 options:0 error:nil];
        printf("Typical fixture: 40 lines / 240 timed words, %lu bytes (binary plist)\n", (unsigned long)typicalData.length);

        NSURL *dir = temp();
        SGLyricsStoreConfigureForTests(dir, 1000, 30 * 1024 * 1024);
        SGLyricsStoreSave(@"../../track", original, @"Fixture provider");
        CHECK(size() == data.length && files(dir).count == 1);
        NSURL *file = files(dir).firstObject;
        NSString *legacyName = [HarnessLegacySHA256([@"../../track" dataUsingEncoding:NSUTF8StringEncoding]) stringByAppendingPathExtension:@"plist"];
        CHECK([file.lastPathComponent isEqual:legacyName]);
        NSData *stored = [NSData dataWithContentsOfURL:file];
        CHECK(stored.length >= 8 && memcmp(stored.bytes, "bplist00", 8) == 0);
        NSNumber *excluded; CHECK([dir getResourceValue:&excluded forKey:NSURLIsExcludedFromBackupKey error:nil] && excluded.boolValue);
        ageAll(dir, 100);
        CHECK(load(@"../../track", &credit).count == 2 && [credit isEqual:@"Fixture provider"]);
        NSDictionary *attrs = [NSFileManager.defaultManager attributesOfItemAtPath:file.path error:nil];
        CHECK([attrs[NSFileModificationDate] timeIntervalSince1970] > 100);
        CHECK(!load(@"missing", NULL));
        CHECK([@"garbage" writeToURL:file atomically:YES encoding:NSUTF8StringEncoding error:nil]);
        CHECK(!load(@"../../track", NULL));
        SGLyricsStoreDelete(@"../../track"); CHECK(size() == 0);

        SGKaraokeLine *providerLine = line(@"Bonjour", 3000);
        providerLine.translation = @"Hello";
        providerLine.backing = line(@"Salut", 3100); providerLine.backing.translation = @"Hi";
        SGLyricsResult *provider = [SGLyricsResult new];
        provider.provider = @"Linked provider"; provider.creditRequired = YES;
        SGLyricsLink *link = [SGLyricsLink new];
        link.title = @"Uploader: Fixture"; link.url = [NSURL URLWithString:@"https://example.org/lyrics/fixture"];
        provider.creditLinks = @[link]; provider.karaokeLines = @[providerLine];
        SGLyricsNoteCredit(provider);
        SGLyricsStoreSave(@"provider", provider.karaokeLines, provider.provider);
        unsigned long long providerBytes = size();
        file = files(dir).firstObject;
        NSDictionary *providerRecord = [NSPropertyListSerialization propertyListWithData:[NSData dataWithContentsOfURL:file]
            options:0 format:nil error:nil];
        CHECK(providerBytes == [NSData dataWithContentsOfURL:file].length);
        CHECK([providerRecord[@"creditLinks"][0][@"url"] isEqual:@"https://example.org/lyrics/fixture"]);
        CHECK(providerBytes > [NSPropertyListSerialization dataWithPropertyList:SGLyricsStoreEncode(@[line(@"Bonjour", 3000)], provider.provider)
            format:NSPropertyListBinaryFormat_v1_0 options:0 error:nil].length);
        // Replace online metadata so only the persisted record can restore the original credit.
        SGLyricsResult *replacement = [SGLyricsResult new]; replacement.provider = provider.provider;
        SGLyricsLink *other = [SGLyricsLink new]; other.title = @"Other"; other.url = [NSURL URLWithString:@"https://example.org/other"];
        replacement.creditLinks = @[other]; SGLyricsNoteCredit(replacement);
        // An online/picked answer wins while a disk read is in flight. Rejecting that read
        // must not replace its live credit, even when stored links are malformed.
        for (id storedLinks in @[providerRecord[@"creditLinks"], @42]) {
            NSMutableDictionary *staleRecord = [providerRecord mutableCopy];
            staleRecord[@"creditLinks"] = storedLinks;
            CHECK([[NSPropertyListSerialization dataWithPropertyList:staleRecord format:NSPropertyListBinaryFormat_v1_0 options:0 error:nil]
                writeToURL:file atomically:YES]);
            __block BOOL rejected = NO;
            SGLyricsStoreLoad(@"provider", ^(NSArray *lines, NSString *name, SGLyricsResult *metadata) {
                CHECK(NSThread.isMainThread && lines.count == 1 && [name isEqual:@"Linked provider"]);
                CHECK([metadata.provider isEqual:@"Linked provider"] && metadata.creditRequired);
                rejected = YES; // The caller discards this result instead of registering its metadata.
            });
            SGLyricsNoteCredit(replacement);
            pump(^BOOL { return rejected; });
            CHECK([SGLyricsCreditLinks(@"Linked provider").firstObject.url.absoluteString isEqual:@"https://example.org/other"]);
            CHECK(!SGLyricsCreditRequired(@"Linked provider"));
        }
        CHECK([[NSPropertyListSerialization dataWithPropertyList:providerRecord format:NSPropertyListBinaryFormat_v1_0 options:0 error:nil]
            writeToURL:file atomically:YES]);
        NSArray<SGKaraokeLine *> *offline = load(@"provider", &credit);
        CHECK([offline.firstObject.translation isEqual:@"Hello"] && [offline.firstObject.backing.translation isEqual:@"Hi"]);
        CHECK(!offline.firstObject.translationMade && [credit isEqual:@"Linked provider"]);
        CHECK([SGLyricsCreditLinks(credit).firstObject.title isEqual:@"Uploader: Fixture"]);
        CHECK([SGLyricsCreditLinks(credit).firstObject.url.absoluteString isEqual:@"https://example.org/lyrics/fixture"]);
        CHECK(SGLyricsCreditRequired(credit));
        for (id value in @[@42, @{}, @[@{@"title": @"Bad", @"url": @"javascript:bad"}],
                           @[@{@"title": oversized, @"url": @"https://example.org"}]]) {
            NSMutableDictionary *damaged = [providerRecord mutableCopy];
            damaged[@"credit"] = @"Damaged provider"; damaged[@"creditLinks"] = value;
            NSData *damagedData = [NSPropertyListSerialization dataWithPropertyList:damaged
                format:NSPropertyListBinaryFormat_v1_0 options:0 error:nil];
            CHECK([damagedData writeToURL:file atomically:YES]);
            CHECK([load(@"provider", &credit).firstObject.translation isEqual:@"Hello"]);
            CHECK(!SGLyricsCreditLinks(credit).count && SGLyricsCreditRequired(credit));
        }
        NSMutableDictionary *badRequired = [providerRecord mutableCopy];
        badRequired[@"credit"] = @"Bad required"; badRequired[@"creditRequired"] = @"yes";
        CHECK([[NSPropertyListSerialization dataWithPropertyList:badRequired format:NSPropertyListBinaryFormat_v1_0 options:0 error:nil]
            writeToURL:file atomically:YES]);
        CHECK(load(@"provider", &credit).count == 1 && !SGLyricsCreditRequired(credit));
        CHECK([SGLyricsCreditLinks(credit).firstObject.title isEqual:@"Uploader: Fixture"]);
        CHECK([[NSPropertyListSerialization dataWithPropertyList:legacy format:NSPropertyListBinaryFormat_v1_0 options:0 error:nil]
            writeToURL:file atomically:YES]);
        CHECK([load(@"provider", &credit).firstObject.words.firstObject.text isEqual:@"Old lyrics"]);
        CHECK(!SGLyricsCreditLinks(credit).count && !SGLyricsCreditRequired(credit));
        SGLyricsStoreDelete(@"provider"); CHECK(size() == 0);

        // A field that would push a single track past the cap is dropped, not the track.
        NSArray *budgetLines = @[line(@"Budget", 0)];
        NSUInteger baseBytes = [NSPropertyListSerialization dataWithPropertyList:SGLyricsStoreEncode(budgetLines, nil)
            format:NSPropertyListBinaryFormat_v1_0 options:0 error:nil].length;
        ((SGKaraokeLine *)budgetLines.firstObject).translation = @"Provider translation exceeding the available bytes";
        ((SGKaraokeLine *)budgetLines.firstObject).translationLanguage = @"en";
        SGLyricsStoreConfigureForTests(dir, 1000, baseBytes);
        SGLyricsStoreSave(@"budget", budgetLines, nil); CHECK(size() == baseBytes);
        CHECK(load(@"budget", NULL).count == 1 && !load(@"budget", NULL).firstObject.translation);
        SGLyricsStoreDelete(@"budget"); CHECK(size() == 0);

        // Count cap: five writes cross four; oldest two go, leaving newest three (90%).
        NSArray *small = @[line(@"Same", 0)];
        SGLyricsStoreConfigureForTests(dir, 4, 1024 * 1024);
        for (NSUInteger i = 0; i < 5; i++) {
            SGLyricsStoreSave(@(i).stringValue, small, nil); size();
            if (i == 0) ageAll(dir, 100);
            if (i == 1) {
                for (NSURL *url in files(dir)) {
                    NSDictionary *a = [NSFileManager.defaultManager attributesOfItemAtPath:url.path error:nil];
                    if ([a[NSFileModificationDate] timeIntervalSince1970] > 100)
                        CHECK([NSFileManager.defaultManager setAttributes:@{NSFileModificationDate: [NSDate dateWithTimeIntervalSince1970:200]} ofItemAtPath:url.path error:nil]);
                }
            }
        }
        CHECK(files(dir).count == 3 && !load(@"0", NULL) && !load(@"1", NULL));
        CHECK(load(@"2", NULL) && load(@"3", NULL) && load(@"4", NULL));
        __block BOOL cleared = NO;
        SGLyricsStoreDeleteAll(^(unsigned long long remaining) { CHECK(remaining == 0); cleared = YES; });
        pump(^BOOL { return cleared; });
        CHECK(![NSFileManager.defaultManager fileExistsAtPath:dir.path]);

        // Byte cap alone: three equal records cross 2.5 records; newest two fit 90%.
        NSUInteger unit = [NSPropertyListSerialization dataWithPropertyList:SGLyricsStoreEncode(small, nil)
            format:NSPropertyListBinaryFormat_v1_0 options:0 error:nil].length;
        SGLyricsStoreConfigureForTests(dir, 100, unit * 5 / 2);
        SGLyricsStoreSave(@"old", small, nil); CHECK(size() == unit); ageAll(dir, 100);
        SGLyricsStoreSave(@"middle", small, nil); CHECK(size() == unit * 2);
        SGLyricsStoreSave(@"new", small, nil); CHECK(size() == unit * 2);
        CHECK(files(dir).count == 2 && !load(@"old", NULL) && load(@"middle", NULL) && load(@"new", NULL));
        CHECK(size() <= unit * 5 / 2 * 9 / 10);
        cleared = NO;
        SGLyricsStoreDeleteAll(^(unsigned long long remaining) { CHECK(!remaining); cleared = YES; });
        pump(^BOOL { return cleared; });
        puts("lyrics-store: all checks passed");
    }
    return 0;
}
