#import "SGTranslationTransfer.h"
#import "SGTranslationFiles.h"
#import "Core/SGFileHash.h"
#import <zlib.h>
#import <fcntl.h>
#import <unistd.h>
#import <sys/stat.h>

static BOOL bad(NSError **error) {
    if (error) *error = SGTranslationStorageError(@"Invalid or unsupported translation archive.");
    return NO;
}
static void u16(NSMutableData *d, uint16_t n) { uint8_t b[] = {(uint8_t)n, (uint8_t)(n >> 8)}; [d appendBytes:b length:2]; }
static void u32(NSMutableData *d, uint32_t n) { u16(d, (uint16_t)n); u16(d, (uint16_t)(n >> 16)); }
static uint16_t r16(const uint8_t *b) { return b[0] | ((uint16_t)b[1] << 8); }
static uint32_t r32(const uint8_t *b) { return r16(b) | ((uint32_t)r16(b + 2) << 16); }
static BOOL fits(NSUInteger offset, NSUInteger length, NSUInteger total) { return offset <= total && length <= total - offset; }
static NSData *json(id value, NSError **error) { return [NSJSONSerialization dataWithJSONObject:value options:NSJSONWritingSortedKeys error:error]; }
static NSString *identity(NSDictionary *record) {
    return SGTranslationRecordIdentity(record);
}
static NSString *filenameIdentity(NSDictionary *record, BOOL caseSensitive) {
    NSString *key = [record[@"key"] precomposedStringWithCanonicalMapping];
    if (!caseSensitive) key = [key stringByFoldingWithOptions:NSCaseInsensitiveSearch locale:[NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"]];
    return [record[@"namespace"] stringByAppendingFormat:@"/%@", key];
}
static BOOL acceptsFilename(NSString *incoming, NSString *existing, NSError **error) {
    return !existing || [incoming compare:existing options:NSLiteralSearch] == NSOrderedSame || bad(error);
}
static NSMutableDictionary *destinationAliases(SGTranslationFiles *store, NSSet<NSString *> *targets, BOOL caseSensitive, NSError **error) {
    NSMutableDictionary *aliases = [NSMutableDictionary dictionary];
    BOOL ok = [store enumerateRecords:^BOOL(NSDictionary *existing, NSError **problem) {
        NSString *identity = filenameIdentity(existing, caseSensitive);
        if (![targets containsObject:identity]) return YES;
        if (!acceptsFilename(existing[@"key"], aliases[identity], problem)) return NO;
        aliases[identity] = existing[@"key"];
        return YES;
    } includeRecovery:NO error:error];
#ifdef SG_LYRICS_TEST_STORE
    extern void SGLyricsTestAliasLookupSize(NSUInteger);
    SGLyricsTestAliasLookupSize(aliases.count);
#endif
    return ok ? aliases : nil;
}
static BOOL output(NSOutputStream *stream, NSData *data, NSError **error) {
    NSUInteger written = 0;
    while (written < data.length) {
        NSInteger n = [stream write:(const uint8_t *)data.bytes + written maxLength:data.length - written];
        if (n <= 0) { if (error) *error = stream.streamError ?: SGTranslationStorageError(@"Could not write export."); return NO; }
        written += (NSUInteger)n;
    }
    return YES;
}
// The ZIP field codec derives from ciowfreshh SGTranslationArchive (d829851).
// Keep the v1 manifest discriminator: archives travel between old and new installs.
static BOOL writeZIP(NSArray *records, NSURL *url, SGTranslationFiles *store, NSError **error) {
    NSMutableArray *manifest = [NSMutableArray array];
    for (NSDictionary *record in records) [manifest addObject:@{@"name":record[@"name"], @"sha256":record[@"sha256"]}];
    NSDictionary *index = @{@"type":@"vitrine.saved-archive", @"version":@1, @"records":manifest};
    NSOutputStream *stream = [NSOutputStream outputStreamWithURL:url append:NO];
    [stream open];
    NSMutableData *central = [NSMutableData data];
    uint32_t offset = 0;
    BOOL ok = YES;
    NSError *entryFailure = nil;
    for (NSUInteger i = 0; i <= records.count; i++) { @autoreleasepool {
        NSData *data = i == records.count ? json(index, &entryFailure) :
            [NSData dataWithContentsOfURL:records[i][@"url"] options:0 error:&entryFailure];
        NSData *name = [(i == records.count ? @"manifest.json" : manifest[i][@"name"]) dataUsingEncoding:NSUTF8StringEncoding];
        if (!data || data.length > SGTranslationRecordBytes) { ok = bad(&entryFailure); break; }
        uint32_t crc = (uint32_t)crc32(0, data.bytes, (uInt)data.length), size = (uint32_t)data.length;
        NSMutableData *header = [NSMutableData data];
        u32(header, 0x04034b50); u16(header, 20); u16(header, 0); u16(header, 0); u16(header, 0); u16(header, 0);
        u32(header, crc); u32(header, size); u32(header, size); u16(header, (uint16_t)name.length); u16(header, 0); [header appendData:name];
        if (!output(stream, header, &entryFailure) || !output(stream, data, &entryFailure)) { ok = NO; break; }
        u32(central, 0x02014b50); u16(central, 20); u16(central, 20); u16(central, 0); u16(central, 0); u16(central, 0); u16(central, 0);
        u32(central, crc); u32(central, size); u32(central, size); u16(central, (uint16_t)name.length); u16(central, 0); u16(central, 0);
        u16(central, 0); u16(central, 0); u32(central, 0); u32(central, offset); [central appendData:name];
        offset += (uint32_t)(header.length + data.length);
    }}
    if (entryFailure && error) *error = entryFailure;
    NSMutableData *end = [NSMutableData data];
    u32(end, 0x06054b50); u16(end, 0); u16(end, 0); u16(end, (uint16_t)(records.count + 1)); u16(end, (uint16_t)(records.count + 1));
    u32(end, (uint32_t)central.length); u32(end, offset); u16(end, 0);
    if (ok) ok = output(stream, central, error) && output(stream, end, error);
    [stream close];
    if (ok) {
        ok = [NSFileManager.defaultManager setAttributes:@{NSFileProtectionKey:NSFileProtectionCompleteUntilFirstUserAuthentication} ofItemAtPath:url.path error:error];
        if (ok) ok = [url setResourceValue:@NO forKey:NSURLIsExcludedFromBackupKey error:error];
    }
    if (ok) {
        int fd = open(url.fileSystemRepresentation, O_RDONLY | O_NOFOLLOW);
        ok = fd >= 0;
        if (fd >= 0) { ok = fsync(fd) == 0; if (close(fd) != 0) ok = NO; }
        if (!ok && error) *error = SGTranslationStorageError(@"Could not flush export.");
    }
    return ok;
}

@implementation SGTranslationTransfer
+ (BOOL)discardStage:(NSDictionary *)stage store:(SGTranslationFiles *)store error:(NSError **)error {
    if (!stage) return YES;
    NSString *name = stage[@"directory"];
    if (![name isKindOfClass:NSString.class] || ![[NSUUID alloc] initWithUUIDString:name]) return bad(error);
    NSError *failure = nil;
    NSDictionary *pending = [self pendingStage:store error:&failure];
    if (failure) { if (error) *error = failure; return NO; }
    if ([pending[@"directory"] isEqual:name]) return bad(error);
    NSURL *directory = [[store.root URLByAppendingPathComponent:@"TranslationImports"] URLByAppendingPathComponent:name];
    struct stat st;
    if (lstat(directory.fileSystemRepresentation, &st) != 0) {
        if (errno == ENOENT) return YES;
        if (error) *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];
        return NO;
    }
    return [NSFileManager.defaultManager removeItemAtURL:directory error:error];
}
+ (BOOL)reclaimStaging:(SGTranslationFiles *)store error:(NSError **)error {
    __block NSError *failure = nil;
    NSDictionary *pending = [self pendingStage:store error:&failure];
    if (failure) { if (error) *error = failure; return NO; }
    NSURL *root = [store.root URLByAppendingPathComponent:@"TranslationImports"];
    struct stat st;
    if (lstat(root.fileSystemRepresentation, &st) != 0) {
        if (errno == ENOENT) return YES;
        if (error) *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];
        return NO;
    }
    if (!S_ISDIR(st.st_mode)) return bad(error);
    NSDirectoryEnumerator *entries = [NSFileManager.defaultManager enumeratorAtURL:root includingPropertiesForKeys:nil
        options:NSDirectoryEnumerationSkipsSubdirectoryDescendants errorHandler:^BOOL(NSURL *url, NSError *problem) { failure = problem; return NO; }];
    for (;;) { @autoreleasepool {
        NSURL *entry = [entries nextObject];
        if (!entry || failure) break;
        if ([entry.lastPathComponent isEqual:pending[@"directory"]]) continue;
        if (![self discardStage:@{@"directory":entry.lastPathComponent} store:store error:&failure]) break;
    }}
    if (failure && error) *error = failure;
    return !failure;
}
+ (NSDictionary *)pendingStage:(SGTranslationFiles *)store error:(NSError **)error {
    NSURL *url = [store.root URLByAppendingPathComponent:@"TranslationState/import.json"];
    struct stat st;
    if (lstat(url.fileSystemRepresentation, &st) != 0) {
        if (errno == ENOENT) return nil;
        if (error) *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];
        return nil;
    }
    if (!S_ISREG(st.st_mode) || st.st_size > SGTranslationRecordBytes) { bad(error); return nil; }
    NSData *data = [NSData dataWithContentsOfURL:url options:0 error:error];
    id stage = data ? SGTranslationReadJSON(data, error) : nil;
    if (![stage isKindOfClass:NSDictionary.class] || ![stage[@"version"] isEqual:@1] ||
        ![stage[@"directory"] isKindOfClass:NSString.class] || ![[NSUUID alloc] initWithUUIDString:stage[@"directory"]] ||
        ![stage[@"records"] isKindOfClass:NSArray.class] || [stage[@"records"] count] >= SGTranslationTransferEntries ||
        ![stage[@"completed"] isKindOfClass:NSNumber.class] || [stage[@"completed"] unsignedIntegerValue] > [stage[@"records"] count] ||
        ![stage[@"replace"] isKindOfClass:NSNumber.class] || ![stage[@"authority"] isKindOfClass:NSNumber.class]) { bad(error); return nil; }
    NSUInteger index = 0;
    for (id item in stage[@"records"]) {
        if (![item isKindOfClass:NSDictionary.class] ||
            ![item[@"file"] isEqual:[NSString stringWithFormat:@"%lu.json", (unsigned long)index++]] ||
            !SGTranslationRecordKeyValid(item[@"key"]) || ![@[@"Translations", @"AI"] containsObject:item[@"namespace"]] ||
            ![item[@"recovery"] isKindOfClass:NSNumber.class]) { bad(error); return nil; }
    }
    return [stage[@"completed"] unsignedIntegerValue] == [stage[@"records"] count] ? nil : stage;
}
+ (NSArray<NSURL *> *)exportRecords:(NSArray<NSDictionary *> *)selection sessionRecords:(NSDictionary<NSString *, NSDictionary *> *)sessionRecords
                             store:(SGTranslationFiles *)store error:(NSError **)error {
    BOOL sessionOnly = selection.count > 0;
    for (NSDictionary *record in selection) if (!sessionRecords[identity(record)]) sessionOnly = NO;
    NSURL *directory = [[NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES] URLByAppendingPathComponent:NSUUID.UUID.UUIDString isDirectory:YES];
    if (![NSFileManager.defaultManager createDirectoryAtURL:directory withIntermediateDirectories:NO attributes:@{NSFileProtectionKey:NSFileProtectionCompleteUntilFirstUserAuthentication} error:error]) return nil;
    NSURL *snapshot = [directory URLByAppendingPathComponent:@"snapshot"];
    if (![NSFileManager.defaultManager createDirectoryAtURL:snapshot withIntermediateDirectories:NO attributes:@{NSFileProtectionKey:NSFileProtectionCompleteUntilFirstUserAuthentication} error:error]) {
        NSError *cleanup = nil;
        [NSFileManager.defaultManager removeItemAtURL:directory error:&cleanup];
        if (cleanup && error) *error = cleanup;
        return nil;
    }
    NSMutableSet *selected = [NSMutableSet set];
    for (NSDictionary *record in selection) [selected addObject:identity(record)];
    BOOL (^selectedRecord)(NSDictionary *) = ^BOOL(NSDictionary *record) { return !selection || [selected containsObject:identity(record)]; };
    BOOL (^keep)(NSDictionary *, NSError **) = ^BOOL(NSDictionary *record, NSError **failure) {
        if (!SGTranslationEnvelopeValid(record)) return bad(failure);
        NSString *name = [SGDataSHA256([identity(record) dataUsingEncoding:NSUTF8StringEncoding]) stringByAppendingString:@".json"];
        return [store writeJSON:record to:[snapshot URLByAppendingPathComponent:name] grandfather:YES allowed:nil error:failure];
    };
    NSError *failure = nil;
    BOOL ok = sessionOnly || [store enumerateRecords:^BOOL(NSDictionary *descriptor, NSError **problem) {
        if (!selectedRecord(descriptor)) return YES;
        NSDictionary *record = [store record:descriptor error:problem];
        if (!record) {
            if (problem) *problem = SGTranslationStorageError([@"Could not export saved record: " stringByAppendingString:identity(descriptor)]);
            return NO;
        }
        if (sessionRecords[identity(record)]) {
            if (!selection && ![record[@"recovery"] boolValue])
                return keep(SGTranslationEnvelope(record[@"namespace"], record[@"key"], record[@"lines"], YES), problem);
            return YES;
        }
        return keep(record, problem);
    } includeRecovery:YES error:&failure];
    if (ok) for (NSDictionary *record in sessionRecords.allValues) {
        @autoreleasepool { if (selectedRecord(record)) ok = keep(record, &failure); }
        if (!ok) break;
    }
    // The executor keeps this disk snapshot consistent with saves/imports/deletes. Only
    // one record body and one bounded ZIP volume's directory are retained in memory.
    __block NSError *enumerationError = nil;
    NSDirectoryEnumerator *enumerator = ok ? [NSFileManager.defaultManager enumeratorAtURL:snapshot includingPropertiesForKeys:nil
        options:NSDirectoryEnumerationSkipsSubdirectoryDescendants errorHandler:^BOOL(NSURL *url, NSError *problem) {
            enumerationError = problem; return NO;
        }] : nil;
    NSMutableArray *files = [NSMutableArray array], *part = [NSMutableArray array];
    NSUInteger bytes = 0;
    for (;;) {
      @autoreleasepool {
        NSURL *file = [enumerator nextObject];
        if (!file) break;
        NSNumber *size = nil;
        ok = [file getResourceValue:&size forKey:NSURLFileSizeKey error:&failure] && size.unsignedLongLongValue <= SGTranslationRecordBytes;
        NSData *data = ok ? [NSData dataWithContentsOfURL:file options:0 error:&failure] : nil;
        if (!data) { ok = NO; break; }
        if (part.count && (part.count >= SGTranslationTransferEntries - 1 || bytes + data.length > SGTranslationTransferBytes - SGTranslationRecordBytes)) {
            NSURL *url = [directory URLByAppendingPathComponent:[NSString stringWithFormat:@"translations-%lu.zip", (unsigned long)files.count + 1]];
            if (!writeZIP(part, url, store, &failure)) { ok = NO; break; }
            [files addObject:url]; [part removeAllObjects]; bytes = 0;
        }
        [part addObject:@{@"url":file, @"name":file.lastPathComponent, @"sha256":SGDataSHA256(data)}];
        bytes += data.length;
      }
    }
    if (enumerationError) { failure = enumerationError; ok = NO; }
    if (ok && !part.count) ok = bad(&failure);
    if (ok) {
        BOOL single = !files.count && part.count == 1;
        NSURL *url = [directory URLByAppendingPathComponent:single ? @"translation.json" :
            [NSString stringWithFormat:@"translations-%lu.zip", (unsigned long)files.count + 1]];
        if (single) {
            NSData *data = [NSData dataWithContentsOfURL:part[0][@"url"] options:0 error:&failure];
            id record = data ? SGTranslationReadJSON(data, &failure) : nil;
            ok = record && [store writeJSON:record to:url grandfather:YES allowed:nil error:&failure];
        } else ok = writeZIP(part, url, store, &failure);
        if (ok) [files addObject:url];
    }
    NSError *cleanup = nil;
    if (![NSFileManager.defaultManager removeItemAtURL:ok ? snapshot : directory error:&cleanup]) { failure = cleanup; ok = NO; }
    if (!ok && error) *error = [NSError errorWithDomain:@"Retrine.TranslationStorage" code:1 userInfo:@{
        NSLocalizedDescriptionKey:selection ? (failure.localizedDescription ?: @"Could not write export.") :
            [NSString stringWithFormat:@"Full export could not read all records in %@: %@", store.root.path, failure.localizedDescription ?: @"Export failed."],
        NSUnderlyingErrorKey:failure ?: SGTranslationStorageError(@"Could not write export.")}];
    return ok ? files : nil;
}
static BOOL readAt(int fd, NSUInteger offset, void *bytes, NSUInteger length) {
    for (NSUInteger at = 0; at < length;) {
        ssize_t count = pread(fd, (uint8_t *)bytes + at, length - at, (off_t)(offset + at));
        if (count < 0 && errno == EINTR) continue;
        if (count <= 0) return NO;
        at += count;
    }
    return YES;
}

static BOOL readArchive(int fd, NSUInteger n, BOOL (^consume)(NSString *, NSData *), NSError **error) {
    // Our portable subset has no archive comments, extra fields, descriptors or prepended data.
    uint8_t footer[22];
    if (n < sizeof(footer) || !readAt(fd, n - sizeof(footer), footer, sizeof(footer)) || r32(footer) != 0x06054b50) return bad(error);
    NSUInteger end = n - sizeof(footer), start = r32(footer + 16), cursor = start;
    NSUInteger count = r16(footer + 10);
    if (!count || count > SGTranslationTransferEntries || r16(footer + 4) || r16(footer + 6) ||
        r16(footer + 8) != count || r16(footer + 20) || !fits(start, r32(footer + 12), end) || start + r32(footer + 12) != end) return bad(error);
    NSMutableArray *entries = [NSMutableArray array];
    NSMutableSet *names = [NSMutableSet set];
    NSUInteger expanded = 0;
    for (NSUInteger i = 0; i < count; i++) {
        uint8_t central[46], header[30], filename[255], localName[sizeof(filename)];
        if (!fits(cursor, sizeof(central), end) || !readAt(fd, cursor, central, sizeof(central)) || r32(central) != 0x02014b50) return bad(error);
        uint16_t flags = r16(central + 8), method = r16(central + 10), nameLength = r16(central + 28);
        uint32_t compressed = r32(central + 20), plain = r32(central + 24), local = r32(central + 42), crc = r32(central + 16);
        uint32_t mode = (r32(central + 38) >> 16) & 0170000;
        if (r16(central + 6) > 20 || (flags & ~0x800) || (method != 0 && method != 8) ||
            r16(central + 30) || r16(central + 32) || r16(central + 34) ||
            (mode && mode != 0100000) || (r32(central + 38) & 0x10) ||
            plain > SGTranslationRecordBytes || compressed > SGTranslationRecordBytes || nameLength > sizeof(filename) ||
            !fits(cursor, sizeof(central) + nameLength, end) || !readAt(fd, cursor + sizeof(central), filename, nameLength)) return bad(error);
        NSString *name = [[NSString alloc] initWithBytes:filename length:nameLength encoding:NSUTF8StringEncoding];
        if (!SGTranslationRecordKeyValid(name) || [name containsString:@":"] || [names containsObject:name]) return bad(error);
        [names addObject:name];
        if (plain > SGTranslationTransferBytes - expanded) {
            if (error) *error = SGTranslationStorageError(@"Expanded translation archive exceeds 256 MiB.");
            return NO;
        }
        expanded += plain;
        if (!fits(local, sizeof(header) + nameLength, start) || !readAt(fd, local, header, sizeof(header)) ||
            r32(header) != 0x04034b50 || r16(header + 4) > 20 || r16(header + 6) != flags ||
            r16(header + 8) != method || r32(header + 14) != crc || r32(header + 18) != compressed ||
            r32(header + 22) != plain || r16(header + 26) != nameLength || r16(header + 28) ||
            !readAt(fd, local + sizeof(header), localName, nameLength) || memcmp(localName, filename, nameLength)) return bad(error);
        NSUInteger body = local + sizeof(header) + nameLength;
        if (!fits(body, compressed, start)) return bad(error);
        [entries addObject:@{@"name":name, @"local":@(local), @"offset":@(body), @"compressed":@(compressed), @"plain":@(plain), @"method":@(method), @"crc":@(crc)}];
        cursor += sizeof(central) + nameLength;
    }
    if (cursor != end) return bad(error);
    NSArray *ordered = [entries sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *c) { return [a[@"local"] compare:c[@"local"]]; }];
    NSUInteger next = 0;
    for (NSDictionary *entry in ordered) {
        if ([entry[@"local"] unsignedIntegerValue] != next) return bad(error);
        next = [entry[@"offset"] unsignedIntegerValue] + [entry[@"compressed"] unsignedIntegerValue];
    }
    if (next != start) return bad(error);
    NSError *entryError = nil;
    for (NSDictionary *entry in entries) {
      BOOL accepted = NO;
      @autoreleasepool {
        NSUInteger plain = [entry[@"plain"] unsignedIntegerValue], compressed = [entry[@"compressed"] unsignedIntegerValue], offset = [entry[@"offset"] unsignedIntegerValue];
        NSMutableData *outputData = [NSMutableData dataWithLength:plain];
        BOOL ok = YES;
        if (![entry[@"method"] unsignedIntegerValue]) {
            ok = compressed == plain && readAt(fd, offset, outputData.mutableBytes, plain);
        } else {
            NSMutableData *input = [NSMutableData dataWithLength:compressed];
            z_stream stream = {0};
            stream.next_in = input.mutableBytes; stream.avail_in = (uInt)compressed;
            stream.next_out = outputData.mutableBytes; stream.avail_out = (uInt)plain;
            if (!readAt(fd, offset, stream.next_in, compressed) || inflateInit2(&stream, -MAX_WBITS) != Z_OK) ok = NO;
            else {
                int result = inflate(&stream, Z_FINISH);
                ok = result == Z_STREAM_END && stream.total_in == compressed && stream.total_out == plain;
                inflateEnd(&stream);
            }
        }
        if (!ok || (uint32_t)crc32(0, outputData.bytes, (uInt)plain) != [entry[@"crc"] unsignedIntValue]) bad(&entryError);
        else accepted = consume(entry[@"name"], outputData);
      }
      // Retain the failure across the per-entry pool before writing to the caller's
      // autoreleasing out parameter. Otherwise a corrupt later entry can dangle it.
      if (!accepted) { if (entryError && error) *error = entryError; return NO; }
    }
    return YES;
}
+ (BOOL)readURL:(NSURL *)url consume:(BOOL (^)(NSString *, NSData *))consume error:(NSError **)error {
    BOOL record = [url.pathExtension.lowercaseString isEqual:@"json"];
    NSUInteger limit = record ? SGTranslationRecordBytes : SGTranslationTransferBytes;
    if (!url.isFileURL) return bad(error);
    int fd = open(url.fileSystemRepresentation, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC);
    if (fd < 0) return bad(error);
    struct stat st;
    BOOL ok;
    if (fstat(fd, &st) != 0 || !S_ISREG(st.st_mode) || st.st_size <= 0 || (uint64_t)st.st_size > limit) {
        ok = bad(error);
    } else {
        NSUInteger size = (NSUInteger)st.st_size;
        if (record) {
            NSMutableData *data = [NSMutableData dataWithLength:size];
            ok = readAt(fd, 0, data.mutableBytes, size) ? consume(@"record.json", data) : bad(error);
        } else ok = readArchive(fd, size, consume, error);
        if (ok && (fstat(fd, &st) != 0 || st.st_size != (off_t)size)) ok = bad(error);
    }
    close(fd);
    return ok;
}
+ (NSDictionary *)stageURL:(NSURL *)url store:(SGTranslationFiles *)store error:(NSError **)error {
    if (![store prepare:error]) return nil;
    if (![self reclaimStaging:store error:error]) return nil;
    NSNumber *authority = [store importAuthority:error];
    if (!authority) return nil;
    NSError *pendingError = nil;
    if ([self pendingStage:store error:&pendingError]) {
        if (error) *error = SGTranslationStorageError(@"Resume the interrupted import before starting another.");
        return nil;
    }
    if (pendingError) { if (error) *error = pendingError; return nil; }
    NSURL *directory = [[store.root URLByAppendingPathComponent:@"TranslationImports"] URLByAppendingPathComponent:NSUUID.UUID.UUIDString];
    NSMutableArray *records = [NSMutableArray array];
    NSMutableSet *identities = [NSMutableSet set];
    NSMutableDictionary *digests = [NSMutableDictionary dictionary];
    NSMutableDictionary *aliases = [NSMutableDictionary dictionary];
    NSNumber *caseSensitive = nil;
    if (![store.root getResourceValue:&caseSensitive forKey:NSURLVolumeSupportsCaseSensitiveNamesKey error:error] || !caseSensitive) return nil;
    __block NSUInteger stagedBytes = 0;
    __block NSDictionary *manifest = nil;
    __block NSError *failure = nil;
    BOOL archive = ![url.pathExtension.lowercaseString isEqual:@"json"];
    BOOL ok = [self readURL:url consume:^BOOL(NSString *name, NSData *data) {
        id record = SGTranslationReadJSON(data, &failure);
        if ([name isEqual:@"manifest.json"] && archive) {
            if (![record isKindOfClass:NSDictionary.class] || record[@"records"] == nil) return bad(&failure);
            manifest = record; return YES;
        }
        if (!SGTranslationEnvelopeValid(record) || [identities containsObject:identity(record)]) return bad(&failure);
        if (![record[@"recovery"] boolValue]) {
            NSString *alias = filenameIdentity(record, caseSensitive.boolValue);
            if (!acceptsFilename(record[@"key"], aliases[alias], &failure)) return NO;
            aliases[alias] = record[@"key"];
        }
        [identities addObject:identity(record)];
        digests[name] = SGDataSHA256(data);
        NSString *staged = [NSString stringWithFormat:@"%lu.json", (unsigned long)records.count];
        NSData *canonical = json(record, &failure);
        if (!canonical || canonical.length > SGTranslationTransferBytes - stagedBytes) return bad(&failure);
        stagedBytes += canonical.length;
        if (![store writeJSON:record to:[directory URLByAppendingPathComponent:staged] grandfather:YES allowed:nil error:&failure]) return NO;
        NSMutableDictionary *item = [@{@"file":staged, @"namespace":record[@"namespace"], @"key":record[@"key"], @"recovery":record[@"recovery"]} mutableCopy];
        if ([record[@"recovery"] boolValue]) item[@"recoveryKey"] = SGTranslationRecoveryKey(record);
        [records addObject:item];
        return YES;
    } error:&failure];
    if (ok && archive) {
        ok = [manifest[@"type"] isEqual:@"vitrine.saved-archive"] && [manifest[@"version"] isKindOfClass:NSNumber.class] &&
            CFGetTypeID((__bridge CFTypeRef)manifest[@"version"]) != CFBooleanGetTypeID() && [manifest[@"version"] isEqual:@1] &&
            manifest.count == 3 && [manifest[@"records"] isKindOfClass:NSArray.class] && [manifest[@"records"] count] == records.count;
        NSMutableSet *seen = [NSMutableSet set];
        for (id entry in ok ? manifest[@"records"] : @[]) {
            if (![entry isKindOfClass:NSDictionary.class] || [entry count] != 2 || ![entry[@"name"] isKindOfClass:NSString.class] ||
                [seen containsObject:entry[@"name"]] || ![digests[entry[@"name"]] isEqual:entry[@"sha256"]]) { ok = NO; break; }
            [seen addObject:entry[@"name"]];
        }
    }
    if (ok) {
        NSDictionary *existing = destinationAliases(store, [NSSet setWithArray:aliases.allKeys], caseSensitive.boolValue, &failure);
        ok = existing != nil;
        for (NSString *alias in aliases) {
            if (!ok || !acceptsFilename(aliases[alias], existing[alias], &failure)) { ok = NO; break; }
        }
    }
    if (!ok || !records.count) {
        NSError *cleanup = nil;
        if ([NSFileManager.defaultManager fileExistsAtPath:directory.path] && ![NSFileManager.defaultManager removeItemAtURL:directory error:&cleanup] && !failure) failure = cleanup;
        if (error) *error = failure ?: SGTranslationStorageError(@"Invalid archive; no saved records were changed.");
        return nil;
    }
    NSUInteger added = 0, matching = 0, conflicts = 0;
    for (NSDictionary *item in records) { @autoreleasepool {
        NSDictionary *existing = [store read:item[@"namespace"] key:item[@"key"] error:&failure];
        if (failure) break;
        if (existing) matching++; else added++;
        NSData *data = [NSData dataWithContentsOfURL:[directory URLByAppendingPathComponent:item[@"file"]] options:0 error:&failure];
        NSDictionary *incoming = data ? SGTranslationReadJSON(data, &failure) : nil;
        if (!incoming) break;
        for (NSString *line in incoming[@"lines"]) if (existing[line] && ![existing[line] isEqual:incoming[@"lines"][line]]) { conflicts++; break; }
    }}
    if (failure) {
        NSError *cleanup = nil;
        [self discardStage:@{@"directory":directory.lastPathComponent} store:store error:&cleanup];
        if (error) *error = cleanup ?: failure;
        return nil;
    }
    return @{@"version":@1, @"authority":authority, @"directory":directory.lastPathComponent, @"records":records, @"completed":@0,
        @"added":@(added), @"matching":@(matching), @"conflicts":@(conflicts)};
}
+ (NSDictionary *)applyStage:(NSDictionary *)stage replace:(BOOL)replace store:(SGTranslationFiles *)store allowed:(BOOL (^)(void))allowed error:(NSError **)error {
    NSMutableDictionary *progress = [stage mutableCopy];
    progress[@"replace"] = @(replace);
    NSURL *receipt = [store.root URLByAppendingPathComponent:@"TranslationState/import.json"];
    if (![store writeJSON:progress to:receipt grandfather:YES allowed:allowed error:error]) return progress;
    NSURL *directory = [[store.root URLByAppendingPathComponent:@"TranslationImports"] URLByAppendingPathComponent:stage[@"directory"]];
    NSArray *items = stage[@"records"];
    NSError *failure = nil;
    NSNumber *caseSensitive = nil;
    if (![store.root getResourceValue:&caseSensitive forKey:NSURLVolumeSupportsCaseSensitiveNamesKey error:&failure] || !caseSensitive) {
        if (error) *error = failure ?: SGTranslationStorageError(@"Could not determine translation filesystem naming rules.");
        return progress;
    }
    NSMutableSet *targets = [NSMutableSet set];
    for (NSUInteger i = [stage[@"completed"] unsignedIntegerValue]; i < items.count; i++) {
        NSDictionary *item = items[i];
        if (![item[@"recovery"] boolValue]) [targets addObject:filenameIdentity(item, caseSensitive.boolValue)];
    }
    NSMutableDictionary *aliases = destinationAliases(store, targets, caseSensitive.boolValue, &failure);
    if (!aliases) { if (error) *error = failure; return progress; }
    for (NSUInteger i = [stage[@"completed"] unsignedIntegerValue]; i < items.count; i++) { @autoreleasepool {
        if (allowed && !allowed()) { failure = SGTranslationStorageError(@"Import interrupted; committed records were kept."); break; }
        NSDictionary *item = items[i];
        if (![store permitsImport:item authority:stage[@"authority"] error:&failure]) {
            if (failure) break;
            progress[@"deleted"] = @([progress[@"deleted"] unsignedIntegerValue] + 1);
            progress[@"completed"] = @(i + 1);
            if (![store writeJSON:progress to:receipt grandfather:YES allowed:allowed error:&failure]) break;
            continue;
        }
        NSData *data = [NSData dataWithContentsOfURL:[directory URLByAppendingPathComponent:item[@"file"]] options:0 error:&failure];
        NSDictionary *record = data ? SGTranslationReadJSON(data, &failure) : nil;
        if (!SGTranslationEnvelopeValid(record)) { bad(&failure); break; }
        NSString *alias = [record[@"recovery"] boolValue] ? nil : filenameIdentity(record, caseSensitive.boolValue);
        if (alias && !acceptsFilename(record[@"key"], aliases[alias], &failure)) break;
        BOOL ok = [record[@"recovery"] boolValue] ? [store installRecovery:record grandfather:NO error:&failure] :
            [store save:record[@"lines"] space:record[@"namespace"] key:record[@"key"] replace:replace preserveMissing:NO grandfather:NO allowed:allowed error:&failure];
        if (!ok) break;
        if (alias) {
            NSURL *destination = [[store.root URLByAppendingPathComponent:record[@"namespace"]] URLByAppendingPathComponent:record[@"key"]];
            NSString *actualName = nil;
            if (![destination getResourceValue:&actualName forKey:NSURLNameKey error:&failure] || !actualName) {
                if (!failure) bad(&failure);
                break;
            }
            aliases[alias] = actualName;
        }
        progress[@"completed"] = @(i + 1);
        if (![store writeJSON:progress to:receipt grandfather:YES allowed:allowed error:&failure]) break;
    }}
    if (failure && error) *error = failure;
    if ([progress[@"completed"] unsignedIntegerValue] == items.count && !failure) {
        if (![NSFileManager.defaultManager removeItemAtURL:directory error:error]) return progress;
    }
    return progress;
}
@end
