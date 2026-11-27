#import "LyricsStore.h"
#import "Lyrics.h"
#import "Shared/LyricsSources/LyricsSources.h"
#import "Core/SGLog.h"
#import "Core/SGFileHash.h"
#import "Core/SGDataRoot.h"
#import <math.h>

// A corrupt/cyclic record cannot exhaust the stack. Real lyrics have at most a few
// levels (lead, backing, pronunciation).
static const NSUInteger kStoreDepth = 32;
// Optional provider metadata is independently bounded: damage must not hide the lyrics.
static const NSUInteger kOptionalTextBytes = 64 * 1024;
static const NSUInteger kCreditLinkCount = 32;

static NSString *optionalText(id value) {
    if (![value isKindOfClass:NSString.class] || ![value length]
        || [value length] > kOptionalTextBytes) return nil;
    NSUInteger bytes = [value lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
    return bytes && bytes <= kOptionalTextBytes ? value : nil;
}

static NSURL *creditURL(id value) {
    NSString *text = optionalText(value);
    NSURL *url = text ? [NSURL URLWithString:text] : nil;
    NSString *scheme = url.scheme.lowercaseString;
    return url.host.length && [scheme isEqual:@"https"] ? url : nil;
}

static NSArray *encodeLinks(NSArray<SGLyricsLink *> *links) {
    if (![links isKindOfClass:NSArray.class] || !links.count || links.count > kCreditLinkCount) return nil;
    NSMutableArray *encoded = [NSMutableArray array];
    NSUInteger bytes = 0;
    for (SGLyricsLink *link in links) {
        if (![link isKindOfClass:SGLyricsLink.class] || ![link.url isKindOfClass:NSURL.class]) return nil;
        NSString *title = optionalText(link.title), *url = link.url.absoluteString;
        if (!title || !creditURL(url)) return nil;
        bytes += [title lengthOfBytesUsingEncoding:NSUTF8StringEncoding] + [url lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
        if (bytes > kOptionalTextBytes) return nil;
        [encoded addObject:@{@"title": title, @"url": url}];
    }
    return encoded;
}

static NSArray<SGLyricsLink *> *decodeLinks(id records) {
    if (![records isKindOfClass:NSArray.class] || ![records count] || [records count] > kCreditLinkCount) return nil;
    NSMutableArray *links = [NSMutableArray array];
    NSUInteger bytes = 0;
    for (id item in records) {
        if (![item isKindOfClass:NSDictionary.class]) return nil;
        NSString *title = optionalText(item[@"title"]);
        NSURL *url = creditURL(item[@"url"]);
        if (!title || !url) return nil;
        bytes += [title lengthOfBytesUsingEncoding:NSUTF8StringEncoding] + [item[@"url"] lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
        if (bytes > kOptionalTextBytes) return nil;
        SGLyricsLink *link = [SGLyricsLink new];
        link.title = title; link.url = url;
        [links addObject:link];
    }
    return links;
}

static NSDictionary *encodeLine(SGKaraokeLine *line, NSUInteger depth) {
    if (![line isKindOfClass:SGKaraokeLine.class] || line.fileOwned || depth > kStoreDepth) return nil;
    NSMutableArray *words = [NSMutableArray array];
    for (SGKaraokeWord *word in line.words) {
        if (![word isKindOfClass:SGKaraokeWord.class] || ![word.text isKindOfClass:NSString.class]) return nil;
        [words addObject:@{@"text": word.text, @"start": @(word.start), @"end": @(word.end), @"joined": @(word.joined)}];
    }
    NSMutableDictionary *record = [@{@"words": words, @"start": @(line.start), @"end": @(line.end),
        @"align": @(line.align), @"timing": @(line.timing), @"pronunciationMade": @(line.pronunciationMade)} mutableCopy];
    if (line.voice) record[@"voice"] = line.voice;
    if (line.note) record[@"note"] = line.note;
    NSString *translation = line.translationMade ? nil : optionalText(line.translation);
    if (translation) record[@"translation"] = translation;
    NSString *language = translation ? optionalText(line.translationLanguage) : nil;
    if (language) record[@"translationLanguage"] = language;
    if (line.backing) {
        NSDictionary *backing = encodeLine(line.backing, depth + 1);
        if (!backing) return nil;
        record[@"backing"] = backing;
    }
    if (line.pronunciation && !line.pronunciationMade) {
        NSDictionary *pronunciation = encodeLine(line.pronunciation, depth + 1);
        if (!pronunciation) return nil;
        record[@"pronunciation"] = pronunciation;
    }
    return record;
}

NSDictionary *SGLyricsStoreEncode(NSArray<SGKaraokeLine *> *lines, NSString *credit) {
    if (![lines isKindOfClass:NSArray.class] || !lines.count || (credit && ![credit isKindOfClass:NSString.class])) return nil;
    NSMutableArray *encoded = [NSMutableArray arrayWithCapacity:lines.count];
    for (SGKaraokeLine *line in lines) {
        NSDictionary *record = encodeLine(line, 0);
        if (!record) return nil;
        [encoded addObject:record];
    }
    NSMutableDictionary *record = [@{@"v": @1, @"lines": encoded} mutableCopy];
    if (credit) record[@"credit"] = credit;
    return record;
}

static BOOL integer(id value, NSInteger minimum, NSInteger maximum) {
    if (![value isKindOfClass:NSNumber.class]) return NO;
    double number = [value doubleValue];
    return isfinite(number) && floor(number) == number
        && [value compare:@(minimum)] != NSOrderedAscending && [value compare:@(maximum)] != NSOrderedDescending;
}

static SGKaraokeLine *decodeLine(id record, NSUInteger depth) {
    if (![record isKindOfClass:NSDictionary.class] || depth > kStoreDepth) return nil;
    if (![record[@"words"] isKindOfClass:NSArray.class]
        || !integer(record[@"start"], NSIntegerMin, NSIntegerMax) || !integer(record[@"end"], NSIntegerMin, NSIntegerMax)
        || !integer(record[@"align"], SGKaraokeAlignLeading, SGKaraokeAlignTrailing)
        || !integer(record[@"timing"], SGKaraokeTimingWords, SGKaraokeTimingNone)
        || !integer(record[@"pronunciationMade"], 0, 1)) return nil;
    for (NSString *key in @[@"voice", @"note"]) {
        if (record[key] && ![record[key] isKindOfClass:NSString.class]) return nil;
    }
    NSMutableArray *words = [NSMutableArray array];
    for (id item in record[@"words"]) {
        if (![item isKindOfClass:NSDictionary.class] || ![item[@"text"] isKindOfClass:NSString.class]
            || !integer(item[@"start"], NSIntegerMin, NSIntegerMax) || !integer(item[@"end"], NSIntegerMin, NSIntegerMax)
            || !integer(item[@"joined"], 0, 1)) return nil;
        SGKaraokeWord *word = [SGKaraokeWord new];
        word.text = item[@"text"]; word.start = [item[@"start"] integerValue]; word.end = [item[@"end"] integerValue];
        word.joined = [item[@"joined"] boolValue];
        [words addObject:word];
    }
    SGKaraokeLine *line = [SGKaraokeLine new];
    line.words = words; line.start = [record[@"start"] integerValue]; line.end = [record[@"end"] integerValue];
    line.align = [record[@"align"] unsignedIntegerValue]; line.timing = [record[@"timing"] unsignedIntegerValue];
    line.voice = record[@"voice"]; line.note = record[@"note"];
    line.translation = optionalText(record[@"translation"]);
    line.translationLanguage = line.translation ? optionalText(record[@"translationLanguage"]) : nil;
    line.pronunciationMade = [record[@"pronunciationMade"] boolValue];
    if (record[@"backing"]) {
        line.backing = decodeLine(record[@"backing"], depth + 1);
        if (!line.backing) return nil;
    }
    if (record[@"pronunciation"]) {
        if (line.pronunciationMade) return nil;
        line.pronunciation = decodeLine(record[@"pronunciation"], depth + 1);
        if (!line.pronunciation) return nil;
    }
    return line;
}

NSArray<SGKaraokeLine *> *SGLyricsStoreDecode(id record, NSString **credit) {
    if (credit) *credit = nil;
    if (![record isKindOfClass:NSDictionary.class] || !integer(record[@"v"], 1, 1)
        || ![record[@"lines"] isKindOfClass:NSArray.class] || ![record[@"lines"] count]
        || (record[@"credit"] && ![record[@"credit"] isKindOfClass:NSString.class])) return nil;
    NSMutableArray *lines = [NSMutableArray array];
    for (id item in record[@"lines"]) {
        SGKaraokeLine *line = decodeLine(item, 0);
        if (!line) return nil;
        [lines addObject:line];
    }
    if (credit) *credit = record[@"credit"];
    return lines;
}

static dispatch_queue_t storeQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        queue = dispatch_queue_create("app.retrine.lyrics-store", dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_UTILITY, 0));
    });
    return queue;
}

// These are confined to storeQueue, including directory discovery.
static NSURL *sg_storeDirectory;
NSNotificationName const SGLyricsStoreChanged = @"spotifyglass.lyrics.storeChanged";
static void changed(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [NSNotificationCenter.defaultCenter postNotificationName:SGLyricsStoreChanged object:nil];
    });
}
static NSUInteger sg_countCap = 1000;
static unsigned long long sg_byteCap = 30 * 1024 * 1024;
static NSTimeInterval sg_lastPrune;
static const NSTimeInterval sg_pruneInterval = 60;

static NSURL *directory(void) {
    if (!sg_storeDirectory) {
        sg_storeDirectory = [SGDataRoot(NSApplicationSupportDirectory) URLByAppendingPathComponent:@"Lyrics" isDirectory:YES];
    }
    return sg_storeDirectory;
}

static NSURL *fileFor(NSString *track) {
    NSData *bytes = [track dataUsingEncoding:NSUTF8StringEncoding];
    NSString *key = SGDataSHA256(bytes);
    return [directory() URLByAppendingPathComponent:[key stringByAppendingPathExtension:@"plist"]];
}

static NSMutableArray<NSDictionary *> *inventory(unsigned long long *total) {
    NSMutableArray *files = [NSMutableArray array];
    *total = 0;
    NSError *error = nil;
    NSArray *urls = [NSFileManager.defaultManager contentsOfDirectoryAtURL:directory()
        includingPropertiesForKeys:@[NSURLFileSizeKey, NSURLContentModificationDateKey, NSURLIsRegularFileKey] options:0 error:&error];
    if (!urls && !([error.domain isEqual:NSCocoaErrorDomain] &&
        (error.code == NSFileReadNoSuchFileError || error.code == NSFileNoSuchFileError))) return nil;
    for (NSURL *url in urls) {
        NSDictionary *values = [url resourceValuesForKeys:@[NSURLFileSizeKey, NSURLContentModificationDateKey, NSURLIsRegularFileKey] error:nil];
        if (![url.pathExtension isEqualToString:@"plist"] || ![values[NSURLIsRegularFileKey] boolValue]) continue;
        NSNumber *size = values[NSURLFileSizeKey] ?: @0;
        *total += size.unsignedLongLongValue;
        [files addObject:@{@"url": url, @"size": size, @"date": values[NSURLContentModificationDateKey] ?: NSDate.distantPast}];
    }
    return files;
}

// Plan against the projected size, excluding the destination from the victims.
// Nothing is evicted unless the staged playback write actually publishes.
static NSArray *evictionOrder(NSArray<NSDictionary *> *files, unsigned long long bytes, BOOL *prunePlayback) {
    NSArray *oldest = [files sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [a[@"date"] compare:b[@"date"]];
    }];
    NSMutableArray *automatic = NSMutableArray.array, *foreground = NSMutableArray.array;
    for (NSDictionary *file in oldest) {
        if ([[NSDictionary dictionaryWithContentsOfURL:file[@"url"] error:nil][@"automatic"] boolValue]) {
            [automatic addObject:file]; bytes -= [file[@"size"] unsignedLongLongValue];
        } else [foreground addObject:file];
    }
    *prunePlayback = foreground.count + 1 > sg_countCap || bytes > sg_byteCap;
    if (!*prunePlayback) return automatic;
    if (sg_lastPrune && NSProcessInfo.processInfo.systemUptime - sg_lastPrune < sg_pruneInterval) return nil;
    return [automatic arrayByAddingObjectsFromArray:foreground];
}

// Only needed when optional metadata pushes a record over the whole-store byte cap.
// Remove the largest optional field first, retaining the old-format payload and other fields.
static void translationFields(NSMutableDictionary *line, NSMutableArray *fields) {
    if (line[@"translation"]) [fields addObject:@{@"parent": line, @"key": @"translation",
        @"bytes": @([line[@"translation"] lengthOfBytesUsingEncoding:NSUTF8StringEncoding]
            + [line[@"translationLanguage"] lengthOfBytesUsingEncoding:NSUTF8StringEncoding])}];
    if (line[@"backing"]) translationFields(line[@"backing"], fields);
    if (line[@"pronunciation"]) translationFields(line[@"pronunciation"], fields);
}

static NSData *dataForRecord(NSMutableDictionary *record, NSError **error) {
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:record format:NSPropertyListBinaryFormat_v1_0 options:0 error:error];
    if (!data || data.length <= sg_byteCap) return data;
    NSMutableArray *fields = [NSMutableArray array];
    for (NSMutableDictionary *line in record[@"lines"]) translationFields(line, fields);
    if (record[@"creditLinks"]) {
        NSData *links = [NSPropertyListSerialization dataWithPropertyList:record[@"creditLinks"]
            format:NSPropertyListBinaryFormat_v1_0 options:0 error:nil];
        [fields addObject:@{@"parent": record, @"key": @"creditLinks", @"bytes": @(links.length)}];
    }
    if (record[@"creditRequired"]) [fields addObject:@{@"parent": record, @"key": @"creditRequired", @"bytes": @1}];
    [fields sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [b[@"bytes"] compare:a[@"bytes"]];
    }];
    for (NSDictionary *field in fields) {
        [field[@"parent"] removeObjectForKey:field[@"key"]];
        if ([field[@"key"] isEqual:@"translation"]) [field[@"parent"] removeObjectForKey:@"translationLanguage"];
        data = [NSPropertyListSerialization dataWithPropertyList:record format:NSPropertyListBinaryFormat_v1_0 options:0 error:error];
        if (!data || data.length <= sg_byteCap) break;
    }
    return data;
}

void SGLyricsStoreSave(NSString *track, NSArray<SGKaraokeLine *> *lines, NSString *credit) {
    SGLyricsStoreSaveWithLease(track, lines, credit, [SGLyricsLease new]);
}

static void save(NSString *track, NSArray<SGKaraokeLine *> *lines, NSString *credit, NSArray *creditLinks,
                 BOOL required, SGLyricsLease *lease, void (^done)(SGBulkWrite)) {
    // The keeper calls on main, where the provider credit registry lives. Snapshot before
    // generated translations/pronunciation can be attached; serialization and I/O stay off main.
    NSMutableDictionary *record = [SGLyricsStoreEncode(lines, credit) mutableCopy];
    if (!track.length || !record) { if (done) done(SGBulkFailed); return; }
    if (done) record[@"automatic"] = @YES;
    NSArray *links = encodeLinks(creditLinks);
    if (links) record[@"creditLinks"] = links;
    if (required) record[@"creditRequired"] = @YES;
    dispatch_async(storeQueue(), ^{
        __block SGBulkWrite outcome = SGBulkFailed;
        dispatch_block_t write = ^{
        if (!lease.isCurrent) return;
        NSError *error = nil;
        NSData *data = record ? dataForRecord(record, &error) : nil;
        if (!data) { SGLog(@"lyrics store: write failed (encode): %@", error); return; }
        // A single oversized track cannot be kept, even in an empty store.
        if (data.length > sg_byteCap || !sg_countCap) { outcome = SGBulkCapacity; return; }
        NSURL *url = fileFor(track);
        if (!url) return;
        unsigned long long bytes;
        NSMutableArray *files = inventory(&bytes);
        if (!files) return; // Cannot admit a write without knowing the remaining budget.
        for (NSUInteger i = 0; i < files.count; i++) {
            NSDictionary *file = files[i];
            // Enumeration can return relative file URLs; both names are in directory().
            if (![[file[@"url"] lastPathComponent] isEqual:url.lastPathComponent]) continue;
            if (done) { outcome = SGBulkAlreadyPresent; return; }
            bytes -= [file[@"size"] unsignedLongLongValue];
            [files removeObjectAtIndex:i];
            break;
        }
        bytes += data.length;
        BOOL overBudget = files.count + 1 > sg_countCap || bytes > sg_byteCap;
        BOOL prunePlayback = NO;
        NSArray *victims = nil;
        if (overBudget && (done || !(victims = evictionOrder(files, bytes, &prunePlayback)))) {
            outcome = SGBulkCapacity; return;
        }
        // Only this queue reads or writes the store. Stage the bytes first; the last
        // lease check orders publication against cancellation, without locking over I/O.
        NSURL *staged = [directory() URLByAppendingPathComponent:@".pending"];
        if (![NSFileManager.defaultManager createDirectoryAtURL:directory() withIntermediateDirectories:YES attributes:nil error:&error]
            || ![directory() setResourceValue:@YES forKey:NSURLIsExcludedFromBackupKey error:&error]
            || ![data writeToURL:staged options:0 error:&error]) {
            SGLog(@"lyrics store: write failed: %@", error);
            [NSFileManager.defaultManager removeItemAtURL:staged error:nil];
            return;
        }
        if (!lease.isCurrent) { [NSFileManager.defaultManager removeItemAtURL:staged error:nil]; return; }
        if (rename(staged.fileSystemRepresentation,url.fileSystemRepresentation) != 0) {
            SGLog(@"lyrics store: publish failed (errno %d)",errno);
            [NSFileManager.defaultManager removeItemAtURL:staged error:nil];
            return;
        }
        outcome = SGBulkWritten;
        if (victims) {
            NSUInteger count = files.count + 1, removed = 0;
            NSUInteger countLimit = prunePlayback ? sg_countCap * 9 / 10 : sg_countCap;
            unsigned long long byteLimit = prunePlayback ? sg_byteCap * 9 / 10 : sg_byteCap;
            if (prunePlayback) sg_lastPrune = NSProcessInfo.processInfo.systemUptime;
            for (NSDictionary *file in victims) {
                if (count <= countLimit && bytes <= byteLimit) break;
                if ([NSFileManager.defaultManager removeItemAtURL:file[@"url"] error:nil]) {
                    bytes -= [file[@"size"] unsignedLongLongValue]; count--; removed++;
                }
            }
            SGLog(@"lyrics store: pruned %lu files", (unsigned long)removed);
        }
        };
        write();
        if (outcome == SGBulkWritten) changed();
        if (done) dispatch_async(dispatch_get_main_queue(), ^{ done(outcome); });
    });
}

void SGLyricsStoreSaveWithLease(NSString *track, NSArray<SGKaraokeLine *> *lines, NSString *credit, SGLyricsLease *lease) {
    save(track, lines, credit, SGLyricsCreditLinks(credit), SGLyricsCreditRequired(credit), lease, nil);
}

void SGLyricsStoreAddAutomatic(NSString *track, SGLyricsResult *result, SGLyricsLease *lease, void (^done)(SGBulkWrite)) {
    save(track, result.karaokeLines, result.provider, result.creditLinks, result.creditRequired, lease, done);
}

static NSUInteger minimumAutomaticSheetBytes(void) {
    static NSUInteger bytes;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableDictionary *record = [SGLyricsStoreEncode(SGKaraokeStaticLines(@[@"a"]), @"a") mutableCopy];
        record[@"automatic"] = @YES;
        bytes = [NSPropertyListSerialization dataWithPropertyList:record format:NSPropertyListBinaryFormat_v1_0
                                                          options:0 error:nil].length;
    });
    return bytes;
}

void SGLyricsStoreInventory(NSArray<NSString *> *tracks, void (^done)(NSSet<NSString *> *,unsigned long long)) {
    dispatch_async(storeQueue(), ^{
        unsigned long long bytes;
        NSArray *files = inventory(&bytes);
        NSSet *names = [NSSet setWithArray:[files valueForKeyPath:@"url.lastPathComponent"] ?: @[]];
        NSMutableSet *found = [NSMutableSet set];
        for (NSString *track in tracks) if ([names containsObject:fileFor(track).lastPathComponent]) [found addObject:track];
        unsigned long long room = files.count < sg_countCap && bytes < sg_byteCap ? sg_byteCap - bytes : 0;
        if (room < minimumAutomaticSheetBytes()) room = 0;
        dispatch_async(dispatch_get_main_queue(), ^{ done(files ? found : nil,room); });
    });
}

void SGLyricsStoreRemoveAutomatic(NSArray<NSString *> *tracks) {
    dispatch_async(storeQueue(), ^{
        BOOL removed = NO;
        for (NSString *track in tracks) @autoreleasepool {
            NSURL *url = fileFor(track);
            // A later playback write owns its file even if a removal raced the ledger write.
            if ([[NSDictionary dictionaryWithContentsOfURL:url error:nil][@"automatic"] isEqual:@YES])
                removed |= [NSFileManager.defaultManager removeItemAtURL:url error:nil];
        }
        if (removed) changed();
    });
}

static SGKaraokeLine *filterTranslations(SGKaraokeLine *line, NSString *wanted) {
    if (!line) return nil;
    SGKaraokeLine *backing = filterTranslations(line.backing, wanted);
    SGKaraokeLine *pronunciation = filterTranslations(line.pronunciation, wanted);
    BOOL drop = !line.translationMade && (line.translation || line.translationLanguage)
        && (!line.translationLanguage.length || [line.translationLanguage caseInsensitiveCompare:wanted] != NSOrderedSame);
    if (!drop && backing == line.backing && pronunciation == line.pronunciation) return line;
    SGKaraokeLine *copy = [line copy];
    if (drop) {
        copy.translation = nil;
        copy.translationLanguage = nil;
    }
    copy.backing = backing;
    copy.pronunciation = pronunciation;
    return copy;
}

NSArray<SGKaraokeLine *> *SGLyricsProviderTranslationsForLanguage(NSArray<SGKaraokeLine *> *lines, NSString *language) {
    if (!language.length) return lines;
    NSMutableArray *filtered;
    for (NSUInteger i = 0; i < lines.count; i++) {
        SGKaraokeLine *line = filterTranslations(lines[i], language);
        if (line == lines[i]) continue;
        if (!filtered) filtered = [lines mutableCopy];
        filtered[i] = line;
    }
    return filtered ? [filtered copy] : lines;
}

void SGLyricsStoreLoad(NSString *track, void (^done)(NSArray<SGKaraokeLine *> *, NSString *, SGLyricsResult *)) {
    dispatch_async(storeQueue(), ^{
        NSURL *url = track.length ? fileFor(track) : nil;
        // Bound corrupt files before parsing them.
        NSNumber *size;
        [url getResourceValue:&size forKey:NSURLFileSizeKey error:nil];
        NSData *data = size.unsignedLongLongValue <= sg_byteCap && url ? [NSData dataWithContentsOfURL:url] : nil;
        id record = data ? [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:nil error:nil] : nil;
        NSString *credit;
        NSArray *lines = SGLyricsStoreDecode(record, &credit);
        SGLyricsResult *metadata;
        if (lines && credit.length) {
            metadata = [SGLyricsResult new];
            metadata.provider = credit;
            metadata.creditLinks = decodeLinks(record[@"creditLinks"]);
            metadata.creditRequired = integer(record[@"creditRequired"], 0, 1) && [record[@"creditRequired"] boolValue];
        }
        if (lines) [NSFileManager.defaultManager setAttributes:@{NSFileModificationDate: NSDate.date} ofItemAtPath:url.path error:nil];
        dispatch_async(dispatch_get_main_queue(), ^{
            // Check at delivery, not on the I/O queue: the selection may change during a read.
            done(SGLyricsProviderTranslationsForLanguage(lines, SGLyricsTranslationLanguage()), credit, metadata);
        });
    });
}

void SGLyricsStoreDelete(NSString *track) {
    if (!track.length) return;
    dispatch_async(storeQueue(), ^{
        if ([NSFileManager.defaultManager removeItemAtURL:fileFor(track) error:nil]) { changed(); SGLog(@"lyrics store: deleted track"); }
    });
}

void SGLyricsStoreSize(void (^done)(unsigned long long)) {
    dispatch_async(storeQueue(), ^{
        unsigned long long bytes; inventory(&bytes);
        dispatch_async(dispatch_get_main_queue(), ^{ done(bytes); });
    });
}

void SGLyricsStoreDeleteAll(void (^done)(unsigned long long)) {
    dispatch_async(storeQueue(), ^{
        NSError *error;
        BOOL deleted = [NSFileManager.defaultManager removeItemAtURL:directory() error:&error];
        SGLog(@"lyrics store: delete saved lyrics: %@", deleted ? @"done" : error.localizedDescription);
        sg_lastPrune = 0;
        changed();
        unsigned long long bytes; inventory(&bytes);
        dispatch_async(dispatch_get_main_queue(), ^{ if (done) done(bytes); });
    });
}

void SGLyricsStoreConfigureForTests(NSURL *url, NSUInteger countCap, unsigned long long byteCap) {
    dispatch_async(storeQueue(), ^{
        sg_storeDirectory = [url copy]; sg_countCap = countCap; sg_byteCap = byteCap;
        sg_lastPrune = 0;
    });
}
