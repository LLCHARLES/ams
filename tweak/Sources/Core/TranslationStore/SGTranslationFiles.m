#import "SGTranslationFiles.h"
#import "Core/SGFileHash.h"
#import <TargetConditionals.h>
NSNotificationName const SGTranslationStorageAvailable = @"retrine.translationStorageAvailable";
#if (TARGET_OS_IOS && !TARGET_OS_MACCATALYST) || defined(SG_LYRICS_TEST_STORE)
#import <UIKit/UIKit.h>
#import <stdatomic.h>

// Files use CompleteUntilFirstUserAuthentication, so availability latches at first unlock.
static atomic_bool unlocked;
static void storageAvailable(BOOL recovery) {
    BOOL alreadyUnlocked = atomic_exchange(&unlocked, true);
    [NSNotificationCenter.defaultCenter postNotificationName:SGTranslationStorageAvailable object:@(alreadyUnlocked && recovery)];
}
static BOOL availableNow(void) {
#ifdef SG_LYRICS_TEST_STORE
    extern BOOL SGLyricsTestProtectedDataAvailable(void);
    return SGLyricsTestProtectedDataAvailable();
#else
    return UIApplication.sharedApplication.protectedDataAvailable;
#endif
}
__attribute__((constructor)) static void observeUnlock(void) {
    void (^setup)(void) = ^{
        [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationProtectedDataDidBecomeAvailable
            object:nil queue:nil usingBlock:^(NSNotification *note) { storageAvailable(YES); }];
        [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidFinishLaunchingNotification
            object:nil queue:nil usingBlock:^(NSNotification *note) {
                if (availableNow()) storageAvailable(NO);
            }];
        if (availableNow()) storageAvailable(NO);
    };
    // Injected at launch this runs on main, so the first prepare: already sees it. Loaded by a dlopen elsewhere,
    // waiting for main from inside an image initializer could wait on main's own dyld lock.
    if (NSThread.isMainThread) setup();
    else dispatch_async(dispatch_get_main_queue(), setup);
}
#endif
#import <fcntl.h>
BOOL SGTranslationStorageUnlocked(void) {
#if (TARGET_OS_IOS && !TARGET_OS_MACCATALYST) || defined(SG_LYRICS_TEST_STORE)
    return atomic_load(&unlocked);
#else
    return YES;
#endif
}
#import <unistd.h>
#import <sys/stat.h>
#import <errno.h>
#import <dirent.h>

NSUInteger const SGTranslationRecordBytes = 9 * 1024 * 1024;
NSUInteger const SGTranslationTransferBytes = 256 * 1024 * 1024;
NSUInteger const SGTranslationTransferEntries = 10000;
static unsigned long long const kReserveBytes = 64ULL * 1024 * 1024;

NSError *SGTranslationStorageError(NSString *message) {
    return [NSError errorWithDomain:@"Retrine.TranslationStorage" code:1 userInfo:@{NSLocalizedDescriptionKey:message}];
}
static BOOL fail(NSError **error, NSString *message) {
    if (error) *error = SGTranslationStorageError(message);
    return NO;
}
static BOOL posixFailure(NSError **error) {
    if (error) *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];
    return NO;
}
static BOOL flushURL(NSURL *url, NSError **error) {
    int fd = open(url.fileSystemRepresentation, O_RDONLY | O_NOFOLLOW);
    if (fd < 0) return posixFailure(error);
#ifdef SG_LYRICS_TEST_STORE
    extern int SGLyricsTestFsync(int);
    BOOL ok = SGLyricsTestFsync(fd) == 0;
#else
    BOOL ok = fsync(fd) == 0;
#endif
    if (!ok) posixFailure(error);
    if (close(fd) != 0 && ok) ok = posixFailure(error);
    return ok;
}

// NSJSONSerialization accepts duplicate object keys. Inspect the grammar before allowing it
// to discard one; escaped spellings of the same key must also collide.
@interface SGTranslationJSONCursor : NSObject
@property NSString *text;
@property NSUInteger index;
@property NSUInteger values;
- (BOOL)value:(NSUInteger)depth;
@end
@implementation SGTranslationJSONCursor
- (void)space {
    while (_index < _text.length && [[NSCharacterSet whitespaceAndNewlineCharacterSet] characterIsMember:[_text characterAtIndex:_index]]) _index++;
}
- (unichar)peek { [self space]; return _index < _text.length ? [_text characterAtIndex:_index] : 0; }
- (BOOL)hexQuad:(unichar *)unit {
    if (_text.length - _index < 4) return NO;
    unsigned value = 0;
    for (unsigned i = 0; i < 4; i++) {
        unichar c = [_text characterAtIndex:_index++];
        if (c >= '0' && c <= '9') value = value * 16 + c - '0';
        else if ((c | 32) >= 'a' && (c | 32) <= 'f') value = value * 16 + (c | 32) - 'a' + 10;
        else return NO;
    }
    *unit = (unichar)value;
    return YES;
}
- (NSString *)stringKey:(BOOL)key {
    [self space];
    if ([self peek] != '"') return nil;
    NSUInteger start = _index++;
    BOOL needsDecode = NO;
    while (_index < _text.length) {
        unichar c = [_text characterAtIndex:_index++];
        if (c == '"') {
            // Foundation validates the whole document once. Only keys need their decoded spelling here.
            if (!key) return @"";
            if (!needsDecode) return [_text substringWithRange:NSMakeRange(start + 1, _index - start - 2)];
            NSString *token = [_text substringWithRange:NSMakeRange(start, _index - start)];
            NSData *data = [[NSString stringWithFormat:@"[%@]", token] dataUsingEncoding:NSUTF8StringEncoding];
            NSArray *value = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            return value.firstObject;
        }
        if (c < 0x20) return nil;
        if (c != '\\') continue;
        needsDecode = YES;
        if (_index == _text.length) return nil;
        c = [_text characterAtIndex:_index++];
        if (c == 'u') {
            unichar unit;
            if (![self hexQuad:&unit] || CFStringIsSurrogateLowCharacter(unit)) return nil;
            if (CFStringIsSurrogateHighCharacter(unit) &&
                (_text.length - _index < 6 || [_text characterAtIndex:_index++] != '\\' ||
                 [_text characterAtIndex:_index++] != 'u' || ![self hexQuad:&unit] || !CFStringIsSurrogateLowCharacter(unit))) return nil;
        } else if (c != '"' && c != '\\' && c != '/' && c != 'b' && c != 'f' && c != 'n' && c != 'r' && c != 't') return nil;
    }
    return nil;
}
- (BOOL)value:(NSUInteger)depth {
    // Allow a full transfer manifest or pending stage (up to 10,000 descriptors).
    if (depth > 16 || ++_values > 32 * SGTranslationTransferEntries) return NO;
    unichar c = [self peek];
    if (c == '"') return [self stringKey:NO] != nil;
    if (c == '{' || c == '[') {
        _index++;
        unichar end = c == '{' ? '}' : ']';
        NSMutableSet *keys = [NSMutableSet set];
        if ([self peek] == end) { _index++; return YES; }
        for (;;) { @autoreleasepool {
            if (c == '{') {
                NSString *key = [self stringKey:YES];
                if (!key || [keys containsObject:key] || [self peek] != ':') return NO;
                [keys addObject:key]; _index++;
            }
            if (![self value:depth + 1]) return NO;
            unichar next = [self peek]; _index++;
            if (next == end) return YES;
            if (next != ',') return NO;
        }}
    }
    NSUInteger start = _index;
    while (_index < _text.length) {
        c = [_text characterAtIndex:_index];
        if (c == ',' || c == ']' || c == '}' || [[NSCharacterSet whitespaceAndNewlineCharacterSet] characterIsMember:c]) break;
        _index++;
    }
    return _index > start;
}
@end

id SGTranslationReadJSON(NSData *data, NSError **error) {
    if (!data || data.length > SGTranslationRecordBytes) { fail(error, @"Invalid or oversized JSON."); return nil; }
    BOOL valid;
    @autoreleasepool {
        SGTranslationJSONCursor *cursor = [SGTranslationJSONCursor new];
        cursor.text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        valid = cursor.text && [cursor value:0] && ![cursor peek];
    }
    if (!valid) { fail(error, @"Invalid JSON or duplicate keys."); return nil; }
    return [NSJSONSerialization JSONObjectWithData:data options:0 error:error];
}
BOOL SGTranslationRecordKeyValid(NSString *key) {
    return [key isKindOfClass:NSString.class] && key.length && [key lengthOfBytesUsingEncoding:NSUTF8StringEncoding] <= 255 &&
        [key hasSuffix:@".json"] && ![key hasPrefix:@"."] && ![key containsString:@"/"] && ![key containsString:@"\\"] &&
        [key rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location == NSNotFound;
}
BOOL SGTranslationMapValid(id map, NSString *space) {
    if (![@[@"Translations", @"AI"] containsObject:space] || ![map isKindOfClass:NSDictionary.class] || [map count] > 2000) return NO;
    NSUInteger count = 0;
    for (id key in map) {
        id value = map[key];
        if (![key isKindOfClass:NSString.class] || ![value isKindOfClass:NSString.class] ||
            [key length] > 64000 || [value length] > 64000) return NO;
        count += [key length] + [value length];
    }
    if ([space isEqual:@"AI"] && count > 256000) return NO;
    NSData *data = [NSJSONSerialization dataWithJSONObject:map options:0 error:nil];
    return data && data.length <= ([space isEqual:@"AI"] ? 1024 * 1024 : 8 * 1024 * 1024);
}
NSDictionary *SGTranslationEnvelope(NSString *space, NSString *key, NSDictionary *lines, BOOL recovery) {
    // The v1 discriminator is part of the canonical bytes hashed into recovery filenames.
    return @{@"type":@"vitrine.saved-record", @"version":@1, @"namespace":space, @"key":key, @"lines":lines, @"recovery":@(recovery)};
}
BOOL SGTranslationEnvelopeValid(id record) {
    if (![record isKindOfClass:NSDictionary.class] || [record count] != 6 ||
        ![record[@"type"] isEqual:@"vitrine.saved-record"] ||
        ![record[@"version"] isKindOfClass:NSNumber.class] || CFGetTypeID((__bridge CFTypeRef)record[@"version"]) == CFBooleanGetTypeID() ||
        ![record[@"version"] isEqual:@1] || ![record[@"recovery"] isKindOfClass:NSNumber.class] ||
        CFGetTypeID((__bridge CFTypeRef)record[@"recovery"]) != CFBooleanGetTypeID()) return NO;
    return SGTranslationRecordKeyValid(record[@"key"]) && SGTranslationMapValid(record[@"lines"], record[@"namespace"]);
}
NSString *SGTranslationRecoveryKey(NSDictionary *record) {
    NSDictionary *canonical = SGTranslationEnvelope(record[@"namespace"], record[@"key"], record[@"lines"], YES);
    return [SGDataSHA256([NSJSONSerialization dataWithJSONObject:canonical options:NSJSONWritingSortedKeys error:nil]) stringByAppendingString:@".json"];
}
NSString *SGTranslationRecordIdentity(NSDictionary *record) {
    return [record[@"recovery"] boolValue] ? [@"recovery/" stringByAppendingString:record[@"recoveryKey"] ?: SGTranslationRecoveryKey(record)]
        : [record[@"namespace"] stringByAppendingFormat:@"/%@", record[@"key"]];
}
NSDictionary *SGTranslationRecordDescriptor(NSDictionary *record, unsigned long long bytes) {
    NSMutableDictionary *descriptor = [@{@"namespace":record[@"namespace"], @"key":record[@"key"],
        @"recovery":record[@"recovery"], @"bytes":@(bytes)} mutableCopy];
    if ([record[@"recovery"] boolValue]) descriptor[@"recoveryKey"] = record[@"recoveryKey"] ?: SGTranslationRecoveryKey(record);
    return descriptor;
}

@implementation SGTranslationFiles {
    NSURL *_legacyConflicts;
    NSMutableDictionary *_metadata;
    NSMutableArray *_unresolved;
    BOOL _ready;
    dev_t _rootDevice;
    ino_t _rootInode;
}
- (instancetype)initWithRoot:(NSURL *)root legacy:(NSURL *)legacy {
    if ((self = [super init])) { _root = root; _legacy = legacy; _ceiling = 512ULL * 1024 * 1024; _unresolved = [NSMutableArray array]; }
    return self;
}
- (NSArray *)unresolved { return [_unresolved copy]; }
- (instancetype)initWithRoot:(NSURL *)root renamedCache:(NSURL *)cache {
    // Include conflicts still residing in the pre-rename cache.
    if ((self = [self initWithRoot:root legacy:cache]) && [cache.lastPathComponent isEqual:@"Retrine"])
        _legacyConflicts = [cache.URLByDeletingLastPathComponent URLByAppendingPathComponent:@"Vitrine" isDirectory:YES];
    return self;
}
- (NSURL *)metadataURL { return [_root URLByAppendingPathComponent:@"TranslationState/state.json"]; }
- (BOOL)protect:(NSURL *)url error:(NSError **)error {
#if TARGET_OS_IOS && !TARGET_OS_MACCATALYST
    if (![NSFileManager.defaultManager setAttributes:@{NSFileProtectionKey:NSFileProtectionCompleteUntilFirstUserAuthentication} ofItemAtPath:url.path error:error]) return NO;
#endif
    return [url setResourceValue:@NO forKey:NSURLIsExcludedFromBackupKey error:error];
}
- (BOOL)directory:(NSURL *)url error:(NSError **)error {
    struct stat st;
    if (lstat(url.fileSystemRepresentation, &st) != 0) {
        if (errno != ENOENT) return posixFailure(error);
        NSURL *parent = url.URLByDeletingLastPathComponent;
        if (![self directory:parent error:error] ||
            ![NSFileManager.defaultManager createDirectoryAtURL:url withIntermediateDirectories:NO
                attributes:@{NSFileProtectionKey:NSFileProtectionCompleteUntilFirstUserAuthentication} error:error]) return NO;
    } else if (!S_ISDIR(st.st_mode)) return fail(error, @"Translation directory is not a directory.");
    // Existing directories may be left by an earlier mkdir whose parent flush failed.
    return [self protect:url error:error] && flushURL(url, error) && flushURL(url.URLByDeletingLastPathComponent, error);
}
- (BOOL)prepare:(NSError **)error {
    if (!SGTranslationStorageUnlocked()) return fail(error, @"Storage unavailable before unlock.");
    if (!_root || !_legacy) return fail(error, @"Translation storage is unavailable.");
    if (![self directory:_root error:error] || ![self directory:self.metadataURL.URLByDeletingLastPathComponent error:error]) return NO;
    struct stat root;
    if (lstat(_root.fileSystemRepresentation, &root) != 0) return posixFailure(error);
    if (!S_ISDIR(root.st_mode)) return fail(error, @"Translation directory is not a directory.");
    if (_ready && root.st_dev == _rootDevice && root.st_ino == _rootInode) return YES;
    _ready = NO;
    NSError *failure = nil;
    NSData *data = [self data:self.metadataURL missing:YES error:&failure];
    if (failure) { if (error) *error = failure; return NO; }
    id state = data ? SGTranslationReadJSON(data, error) : @{@"version":@1, @"receipts":@{}, @"suppressed":@{}, @"allSuppressed":@NO};
    if (![state isKindOfClass:NSDictionary.class] || ![state[@"version"] isEqual:@1] ||
        ![state[@"receipts"] isKindOfClass:NSDictionary.class] || ![state[@"suppressed"] isKindOfClass:NSDictionary.class] ||
        ![state[@"allSuppressed"] isKindOfClass:NSNumber.class]) return fail(error, @"Translation migration metadata is unreadable; nothing was reset.");
    _metadata = [state mutableCopy];
    _metadata[@"receipts"] = [state[@"receipts"] mutableCopy];
    _metadata[@"suppressed"] = [state[@"suppressed"] mutableCopy];
    if ((state[@"deletedAt"] && ![state[@"deletedAt"] isKindOfClass:NSDictionary.class]) ||
        (state[@"deleteVersion"] && ![state[@"deleteVersion"] isKindOfClass:NSNumber.class]) ||
        (state[@"allDeletedAt"] && ![state[@"allDeletedAt"] isKindOfClass:NSNumber.class]))
        return fail(error, @"Invalid deletion authority.");
    _metadata[@"deletedAt"] = [state[@"deletedAt"] mutableCopy] ?: [NSMutableDictionary dictionary];
    _rootDevice = root.st_dev;
    _rootInode = root.st_ino;
    _ready = YES;
    return YES;
}
- (NSNumber *)importAuthority:(NSError **)error {
    return [self prepare:error] ? _metadata[@"deleteVersion"] ?: @0 : nil;
}
- (BOOL)permitsImport:(NSDictionary *)record authority:(NSNumber *)authority error:(NSError **)error {
    if (![self prepare:error]) return NO;
    if (![authority isKindOfClass:NSNumber.class]) return fail(error, @"Import has no durable write authority.");
    unsigned long long removed = [_metadata[@"deletedAt"][SGTranslationRecordIdentity(record)] unsignedLongLongValue];
    removed = MAX(removed, [_metadata[@"allDeletedAt"] unsignedLongLongValue]);
    return removed <= authority.unsignedLongLongValue;
}
- (NSData *)data:(NSURL *)url missing:(BOOL)missing error:(NSError **)error {
    struct stat st;
    if (lstat(url.fileSystemRepresentation, &st) != 0) {
        if (missing && errno == ENOENT) return nil;
        posixFailure(error); return nil;
    }
    if (!S_ISREG(st.st_mode) || st.st_size < 0 || (unsigned long long)st.st_size > SGTranslationRecordBytes) { fail(error, @"Invalid or oversized translation file."); return nil; }
    return [NSData dataWithContentsOfURL:url options:0 error:error];
}
- (BOOL)visitDirectory:(NSURL *)directory visit:(BOOL (^)(NSURL *, NSError **))visit error:(NSError **)error {
    struct stat st;
    if (lstat(directory.fileSystemRepresentation, &st) != 0) {
        if (errno == ENOENT) return YES;
        return posixFailure(error);
    }
    if (!S_ISDIR(st.st_mode)) return fail(error, @"Translation directory is not a directory.");
    int fd = open(directory.fileSystemRepresentation, O_RDONLY | O_DIRECTORY | O_NOFOLLOW);
    if (fd < 0) return posixFailure(error);
    DIR *stream = fdopendir(fd);
    if (!stream) { int saved = errno; close(fd); errno = saved; return posixFailure(error); }
    NSError *failure = nil;
    BOOL ok = YES;
    for (;;) {
        errno = 0;
        struct dirent *entry = readdir(stream);
        if (!entry) { if (errno) ok = posixFailure(&failure); break; }
        if (!strcmp(entry->d_name, ".") || !strcmp(entry->d_name, "..")) continue;
        @autoreleasepool {
            NSString *name = [[NSString alloc] initWithUTF8String:entry->d_name];
            if (!name) ok = fail(&failure, @"Invalid translation filename.");
            else ok = visit([directory URLByAppendingPathComponent:name], &failure);
        }
        if (!ok) break;
    }
    if (closedir(stream) != 0 && ok) ok = posixFailure(&failure);
    if (failure && error) *error = failure;
    return ok;
}
- (unsigned long long)bytes:(NSError **)error {
    __block unsigned long long total = 0;
    for (NSString *name in @[@"Translations", @"AI", @"TranslationRecovery", @"TranslationState"]) {
        if (![self visitDirectory:[_root URLByAppendingPathComponent:name] visit:^BOOL(NSURL *url, NSError **failure) {
            struct stat st;
            if (lstat(url.fileSystemRepresentation, &st) != 0) return posixFailure(failure);
            if (!S_ISREG(st.st_mode)) return fail(failure, @"Unexpected item in translation storage.");
            total += (unsigned long long)st.st_size;
            return YES;
        } error:error]) return 0;
    }
    return total;
}
- (BOOL)writeJSON:(id)value to:(NSURL *)url grandfather:(BOOL)grandfather allowed:(BOOL (^)(void))allowed error:(NSError **)error {
    NSError *failure = nil;
    NSData *data;
    BOOL valid;
    @autoreleasepool {
        data = [NSJSONSerialization dataWithJSONObject:value options:NSJSONWritingSortedKeys error:&failure];
        valid = data && SGTranslationReadJSON(data, &failure) != nil;
    }
    if (!valid) { if (error) *error = failure; return NO; }
    NSUInteger oldLength;
    BOOL unchanged;
    @autoreleasepool {
        NSData *old = [self data:url missing:YES error:&failure];
        unchanged = [old isEqual:data];
        oldLength = old.length;
    }
    if (failure) { if (error) *error = failure; return NO; }
    if (unchanged) {
        if (allowed && !allowed()) return fail(error, @"Translation write was cancelled.");
        return [self protect:url error:error] && flushURL(url, error) && [self directory:url.URLByDeletingLastPathComponent error:error];
    }
    if (!grandfather && data.length > oldLength) {
        NSError *sizeError = nil;
        unsigned long long total = [self bytes:&sizeError];
        if (sizeError) { if (error) *error = sizeError; return NO; }
        if (total + data.length - oldLength > _ceiling)
            return fail(error, @"Storage ceiling reached; export or delete records before adding data.");
    }
    if (![self directory:url.URLByDeletingLastPathComponent error:error]) return NO;
    NSDictionary *disk = [NSFileManager.defaultManager attributesOfFileSystemForPath:url.URLByDeletingLastPathComponent.path error:error];
    if (!disk) return NO;
    if ([disk[NSFileSystemFreeSize] unsignedLongLongValue] < kReserveBytes + data.length)
        return fail(error, @"Insufficient free space to save translations safely.");
    NSURL *temporary = [url.URLByDeletingLastPathComponent URLByAppendingPathComponent:[@".pending-" stringByAppendingString:NSUUID.UUID.UUIDString]];
    BOOL ok = [data writeToURL:temporary options:NSDataWritingWithoutOverwriting | NSDataWritingFileProtectionCompleteUntilFirstUserAuthentication error:error];
    data = nil;
    if (ok) {
        @autoreleasepool {
            NSData *check = [self data:temporary missing:NO error:&failure];
            ok = check && [SGTranslationReadJSON(check, &failure) isEqual:value];
        }
        if (!ok && error) *error = failure;
        if (ok) ok = [self protect:temporary error:error];
    }
    if (ok) ok = flushURL(temporary, error);
    if (ok && allowed && !allowed()) ok = fail(error, @"Translation write was cancelled.");
    if (ok && rename(temporary.fileSystemRepresentation, url.fileSystemRepresentation) != 0) ok = posixFailure(error);
    if (ok && !flushURL(url.URLByDeletingLastPathComponent, error)) {
        // rename succeeded: the visible state may now differ from our last durable snapshot.
        if ([url isEqual:self.metadataURL]) _ready = NO;
        ok = NO;
    }
    if (!ok) {
        NSError *cleanup = nil;
        if ([NSFileManager.defaultManager fileExistsAtPath:temporary.path] && ![NSFileManager.defaultManager removeItemAtURL:temporary error:&cleanup] && error && !*error) *error = cleanup;
        if (error && !*error) *error = SGTranslationStorageError(@"Translation write verification failed.");
    }
    return ok;
}
- (NSDictionary *)read:(NSString *)space key:(NSString *)key error:(NSError **)error {
    if (![self prepare:error]) return nil;
    if (!SGTranslationRecordKeyValid(key) || ![@[@"Translations", @"AI"] containsObject:space]) { fail(error, @"Invalid translation identity."); return nil; }
    NSURL *url = [[_root URLByAppendingPathComponent:space] URLByAppendingPathComponent:key];
    NSData *data = [self data:url missing:YES error:error];
    if (!data) return nil;
    id value = SGTranslationReadJSON(data, error);
    if (!SGTranslationMapValid(value, space)) { fail(error, @"Invalid translation map."); return nil; }
    return value;
}
- (BOOL)installRecovery:(NSDictionary *)record grandfather:(BOOL)grandfather error:(NSError **)error {
    if (![self prepare:error] || !SGTranslationEnvelopeValid(record)) return fail(error, @"Invalid recovery record.");
    NSDictionary *copy = SGTranslationEnvelope(record[@"namespace"], record[@"key"], record[@"lines"], YES);
    NSURL *url = [[_root URLByAppendingPathComponent:@"TranslationRecovery"] URLByAppendingPathComponent:SGTranslationRecoveryKey(copy)];
    return [self writeJSON:copy to:url grandfather:grandfather allowed:nil error:error];
}
- (BOOL)save:(NSDictionary *)lines space:(NSString *)space key:(NSString *)key replace:(BOOL)replace
 preserveMissing:(BOOL)preserveMissing grandfather:(BOOL)grandfather allowed:(BOOL (^)(void))allowed error:(NSError **)error {
    if (![self prepare:error]) return NO;
    if (!SGTranslationMapValid(lines, space) || !SGTranslationRecordKeyValid(key)) return fail(error, @"Invalid translation record.");
    NSError *failure = nil;
    NSDictionary *previous = [self read:space key:key error:&failure];
    if (failure) { if (error) *error = failure; return NO; }
    if (allowed && !allowed()) return fail(error, @"Translation write was cancelled.");
    if ([previous isEqual:lines]) return [self writeJSON:previous to:[[_root URLByAppendingPathComponent:space] URLByAppendingPathComponent:key]
        grandfather:grandfather allowed:allowed error:error];
    NSMutableDictionary *merged = preserveMissing || !replace ? [previous mutableCopy] ?: [NSMutableDictionary dictionary] : [NSMutableDictionary dictionary];
    NSMutableDictionary *conflicts = [NSMutableDictionary dictionary];
    for (NSString *line in lines) {
        if (previous[line] && ![previous[line] isEqual:lines[line]]) conflicts[line] = replace ? previous[line] : lines[line];
        if (replace || !previous[line]) merged[line] = lines[line];
    }
    if (!SGTranslationMapValid(merged, space)) return fail(error, @"Merged translation exceeds the record limit.");
    NSDictionary *recover = replace && !preserveMissing ? previous : conflicts;
    if (recover.count && ![self installRecovery:SGTranslationEnvelope(space, key, recover, YES) grandfather:grandfather error:error]) return NO;
    NSURL *url = [[_root URLByAppendingPathComponent:space] URLByAppendingPathComponent:key];
    return [self writeJSON:merged to:url grandfather:grandfather allowed:allowed error:error];
}
- (BOOL)migrate:(NSError **)error {
    return [self migrateSpace:nil key:nil error:error];
}
- (BOOL)migrateSpace:(NSString *)onlySpace key:(NSString *)onlyKey error:(NSError **)error {
    if (![self prepare:error]) return NO;
    if (onlySpace && (![@[@"Translations", @"AI"] containsObject:onlySpace] || !SGTranslationRecordKeyValid(onlyKey)))
        return fail(error, @"Invalid translation identity.");
    [_unresolved removeAllObjects];
    if ([_metadata[@"allSuppressed"] boolValue]) return YES;
    for (NSURL *base in _legacyConflicts ? @[_legacy, _legacyConflicts] : @[_legacy]) {
      struct stat st;
      if (lstat(base.fileSystemRepresentation, &st)) { if (errno == ENOENT) continue; return posixFailure(error); }
      if (!S_ISDIR(st.st_mode)) return fail(error, @"Invalid legacy cache directory.");
      for (NSString *space in onlySpace ? @[onlySpace] : @[@"Translations", @"AI"]) {
        NSURL *directory = [base URLByAppendingPathComponent:space];
        BOOL (^visit)(NSURL *, NSError **) = ^BOOL(NSURL *file, NSError **listingError) {
            NSString *key = file.lastPathComponent, *identity = [space stringByAppendingFormat:@"/%@", key];
            NSString *receipt = [base isEqual:self->_legacy] ? identity : [@"leftover/" stringByAppendingString:identity];
            if ([self->_metadata[@"suppressed"][identity] boolValue]) return YES;
            NSError *problem = nil;
            NSData *data = [self data:file missing:NO error:&problem];
            NSString *digest = data ? SGDataSHA256(data) : nil;
            if (digest && [self->_metadata[@"receipts"][receipt] isEqual:digest]) return YES;
            id lines = data ? SGTranslationReadJSON(data, &problem) : nil;
            if (!problem && (!SGTranslationRecordKeyValid(key) || !SGTranslationMapValid(lines, space))) problem = SGTranslationStorageError(@"Invalid legacy translation.");
            if (!problem && ![self save:lines space:space key:key replace:NO preserveMissing:YES grandfather:YES allowed:nil error:&problem]) {}
            NSDictionary *readBack = !problem ? [self read:space key:key error:&problem] : nil;
            if (!problem && !readBack) problem = SGTranslationStorageError(@"Migration verification failed.");
            if (!problem) {
                for (NSString *line in lines) {
                    if (!readBack[line]) { problem = SGTranslationStorageError(@"Migration verification failed."); break; }
                }
            }
            if (!problem) {
                id old = self->_metadata[@"receipts"][receipt];
                self->_metadata[@"receipts"][receipt] = digest;
                if (![self writeJSON:self->_metadata to:self.metadataURL grandfather:YES allowed:nil error:&problem]) {
                    if (old) self->_metadata[@"receipts"][receipt] = old; else [self->_metadata[@"receipts"] removeObjectForKey:receipt];
                }
            }
            if (problem) [self->_unresolved addObject:@{@"namespace":space, @"key":key, @"url":file, @"error":problem.localizedDescription}];
            return YES;
        };
        if (!onlySpace) {
            if (![self visitDirectory:directory visit:visit error:error]) return NO;
        } else {
            if (lstat(directory.fileSystemRepresentation, &st)) { if (errno == ENOENT) continue; return posixFailure(error); }
            if (!S_ISDIR(st.st_mode)) return fail(error, @"Invalid legacy cache directory.");
            NSURL *file = [directory URLByAppendingPathComponent:onlyKey];
            if (lstat(file.fileSystemRepresentation, &st)) { if (errno == ENOENT) continue; return posixFailure(error); }
            // A lookup can match another Unicode spelling (or case). Feed
            // the same directory-entry name to visit as readdir would.
            NSString *storedName = nil;
            if (![file getResourceValue:&storedName forKey:NSURLNameKey error:error]) return NO;
            if (!storedName) return fail(error, @"Missing legacy translation filename.");
            if (!visit([directory URLByAppendingPathComponent:storedName], error)) return NO;
        }
      }
    }
    if (_unresolved.count) return fail(error, @"Legacy migration is incomplete. Original files remain available.");
    return YES;
}
- (BOOL)enumerateRecords:(BOOL (^)(NSDictionary *, NSError **))visit includeRecovery:(BOOL)includeRecovery error:(NSError **)error {
    if (![self prepare:error]) return NO;
    NSArray *spaces = includeRecovery ? @[@"Translations", @"AI", @"TranslationRecovery"] : @[@"Translations", @"AI"];
    for (NSString *space in spaces) {
        if (![self visitDirectory:[_root URLByAppendingPathComponent:space] visit:^BOOL(NSURL *url, NSError **failure) {
            if ([url.lastPathComponent hasPrefix:@".pending-"]) return YES;
            struct stat st;
            if (lstat(url.fileSystemRepresentation, &st) != 0) return posixFailure(failure);
            if (!S_ISREG(st.st_mode) || !SGTranslationRecordKeyValid(url.lastPathComponent)) return fail(failure, @"Invalid saved record.");
            NSDictionary *descriptor;
            if ([space isEqual:@"TranslationRecovery"]) {
                NSData *data = [self data:url missing:NO error:failure];
                NSDictionary *value = data ? SGTranslationReadJSON(data, failure) : nil;
                if (!SGTranslationEnvelopeValid(value) || ![SGTranslationRecoveryKey(value) isEqual:url.lastPathComponent]) return fail(failure, @"Invalid recovery record.");
                descriptor = SGTranslationRecordDescriptor(value, (unsigned long long)st.st_size);
            } else {
                descriptor = @{@"namespace":space, @"key":url.lastPathComponent, @"recovery":@NO, @"bytes":@((unsigned long long)st.st_size)};
            }
            return visit(descriptor, failure);
        } error:error]) return NO;
    }
    return YES;
}
- (NSDictionary *)record:(NSDictionary *)descriptor error:(NSError **)error {
    if (![self prepare:error]) return nil;
    if (![descriptor[@"recovery"] boolValue]) {
        NSDictionary *lines = [self read:descriptor[@"namespace"] key:descriptor[@"key"] error:error];
        return lines ? SGTranslationEnvelope(descriptor[@"namespace"], descriptor[@"key"], lines, NO) : nil;
    }
    NSString *name = descriptor[@"recoveryKey"] ?: SGTranslationRecoveryKey(descriptor);
    if (!SGTranslationRecordKeyValid(name)) { fail(error, @"Invalid recovery record."); return nil; }
    NSData *data = [self data:[[_root URLByAppendingPathComponent:@"TranslationRecovery"] URLByAppendingPathComponent:name] missing:NO error:error];
    NSDictionary *value = data ? SGTranslationReadJSON(data, error) : nil;
    if (!SGTranslationEnvelopeValid(value) || ![SGTranslationRecoveryKey(value) isEqual:name]) { fail(error, @"Invalid recovery record."); return nil; }
    return value;
}
- (NSDictionary *)summary:(NSError **)error {
    __block NSUInteger count = 0;
    if (![self enumerateRecords:^BOOL(NSDictionary *descriptor, NSError **failure) { count++; return YES; } includeRecovery:YES error:error]) return nil;
    NSError *failure = nil;
    unsigned long long bytes = [self bytes:&failure];
    if (failure) { if (error) *error = failure; return nil; }
    return @{@"count":@(count), @"bytes":@(bytes)};
}
- (BOOL)removeRecords:(NSArray<NSDictionary *> *)records all:(BOOL)all error:(NSError **)error {
    if (![self prepare:error]) return NO;
    NSMutableDictionary *state = [_metadata mutableCopy];
    NSNumber *version = @([state[@"deleteVersion"] unsignedLongLongValue] + 1);
    state[@"deleteVersion"] = version;
    // A global tombstone supersedes the individual ones. A receipt is never
    // consulted again once migration of that legacy identity is suppressed.
    BOOL noMigration = all || [state[@"allSuppressed"] boolValue];
    state[@"receipts"] = noMigration ? [NSMutableDictionary dictionary] : [_metadata[@"receipts"] mutableCopy];
    state[@"suppressed"] = noMigration ? [NSMutableDictionary dictionary] : [_metadata[@"suppressed"] mutableCopy];
    state[@"deletedAt"] = all ? [NSMutableDictionary dictionary] : [_metadata[@"deletedAt"] mutableCopy];
    if (all) {
        state[@"allSuppressed"] = @YES;
        state[@"allDeletedAt"] = version;
    } else for (NSDictionary *record in records) {
        state[@"deletedAt"][SGTranslationRecordIdentity(record)] = version;
        if (!noMigration && ![record[@"recovery"] boolValue]) {
            NSString *identity = [record[@"namespace"] stringByAppendingFormat:@"/%@", record[@"key"]];
            state[@"suppressed"][identity] = @YES;
            [state[@"receipts"] removeObjectForKey:identity];
            [state[@"receipts"] removeObjectForKey:[@"leftover/" stringByAppendingString:identity]];
        }
    }
    if (![self writeJSON:state to:self.metadataURL grandfather:YES allowed:nil error:error]) return NO;
    _metadata = state;
    NSMutableArray<NSURL *> *targets = [NSMutableArray array];
    if (all) {
        for (NSURL *base in @[_root, _legacy]) for (NSString *space in @[@"Translations", @"AI"])
            [targets addObject:[base URLByAppendingPathComponent:space]];
        [targets addObject:[_root URLByAppendingPathComponent:@"TranslationRecovery"]];
        [targets addObject:[_root URLByAppendingPathComponent:@"TranslationImports"]];
        [targets addObject:[_root URLByAppendingPathComponent:@"TranslationState/import.json"]];
    } else for (NSDictionary *record in records) {
        NSString *space = [record[@"recovery"] boolValue] ? @"TranslationRecovery" : record[@"namespace"];
        NSString *key = [record[@"recovery"] boolValue] ? record[@"recoveryKey"] ?: SGTranslationRecoveryKey(record) : record[@"key"];
        if (!SGTranslationRecordKeyValid(key)) return fail(error, @"Invalid deletion identity.");
        [targets addObject:[[_root URLByAppendingPathComponent:space] URLByAppendingPathComponent:key]];
        if (![record[@"recovery"] boolValue]) [targets addObject:[[_legacy URLByAppendingPathComponent:space] URLByAppendingPathComponent:key]];
    }
    for (NSURL *url in targets) {
        struct stat st;
        if (lstat(url.fileSystemRepresentation, &st) != 0) { if (errno == ENOENT) continue; return posixFailure(error); }
        if (![NSFileManager.defaultManager removeItemAtURL:url error:error]) return NO;
        int fd = open(url.URLByDeletingLastPathComponent.fileSystemRepresentation, O_RDONLY | O_NOFOLLOW);
        if (fd < 0) return posixFailure(error);
        BOOL ok = fsync(fd) == 0;
        if (!ok) posixFailure(error);
        if (close(fd) != 0 && ok) ok = posixFailure(error);
        if (!ok) return NO;
    }
    return YES;
}
@end
