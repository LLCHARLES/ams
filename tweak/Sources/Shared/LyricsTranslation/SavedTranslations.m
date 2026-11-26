// The filenames remain compatible with the legacy cache; only the durable root changes.
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Settings/SGPageStyle.h"
#import "Shared/Lyrics/Lyrics.h"
#import "AIServicesInternal.h"
#import "Core/SGFileHash.h"
#import "Core/SGDataRoot.h"
#import "Core/TranslationStore/SGTranslationFiles.h"
#import "Core/TranslationStore/SGTranslationTransfer.h"
#import "TranslationLibrary.h"

// Store-queue ordering stops at delivery to main. A mutation requested meanwhile
// also retires read results waiting to be applied to the live lyric objects.
@interface SGTranslationReadVersion : NSObject
@property (nonatomic) NSUInteger mutation, readers;
@end
@implementation SGTranslationReadVersion
@end
// Guarded by the class lock. Keep versions only while reads are outstanding, not
// for every song visited this launch. Delete-all also invalidates reads of absent files.
static NSMutableDictionary<NSURL *, SGTranslationReadVersion *> *sg_readVersions;
static NSUInteger sg_deleteEpoch;

static void translationMutated(NSURL *file) {
    @synchronized (SGTranslationReadVersion.class) {
        SGTranslationReadVersion *version = sg_readVersions[file];
        version.mutation++;
    }
}

NSNotificationName const SGLyricsTranslationSavedNotification = @"spotifyglass.lyricsTranslationSaved";
NSNotificationName const SGLyricsSavedSummaryDidChangeNotification = @"spotifyglass.lyricsSavedSummaryDidChange";

// Only main reads/publishes these; directory enumeration stays on writes().
static NSString *sg_savedSummary;
static NSUInteger sg_savedCount;
static NSString *sg_storageWarning;
static NSError *sg_storageError;
static NSError *sg_migrationError;
static SGTranslationFiles *sg_store;
static NSUInteger sg_writeEpoch;
// Only enqueued saves need cancellation authority. Dropping the entry invalidates
// all those saves; a subsequent save gets a distinct object even for the same file.
static NSMutableDictionary<NSURL *, SGTranslationReadVersion *> *sg_authorities;
static NSMutableDictionary<NSArray *, NSNumber *> *sg_translationJobs;
static BOOL sg_readFailed;
static void refreshSummary(void); // called on writes(); coalesces queued mutations

static NSURL *cacheRoot(void) {
#ifdef SG_LYRICS_TEST_STORE
    extern NSURL *SGLyricsTestCacheRoot(void);
    return SGLyricsTestCacheRoot();
#else
    return SGDataRoot(NSApplicationSupportDirectory);
#endif
}
static NSURL *legacyRoot(void) {
#ifdef SG_LYRICS_TEST_STORE
    return [cacheRoot() URLByAppendingPathComponent:@"Legacy"];
#else
    return SGDataRoot(NSCachesDirectory);
#endif
}
static SGTranslationFiles *store(void) {
    if (!SGTranslationStorageUnlocked()) return [[SGTranslationFiles alloc] initWithRoot:nil legacy:nil];
#ifdef SG_LYRICS_TEST_STORE
    (void)cacheRoot();
#endif
    if (!sg_store) {
        NSURL *root = cacheRoot(), *legacy = legacyRoot();
#ifdef SG_LYRICS_TEST_STORE
        sg_store = [[SGTranslationFiles alloc] initWithRoot:root legacy:legacy];
#else
        sg_store = [[SGTranslationFiles alloc] initWithRoot:root renamedCache:legacy];
#endif
    }
    return sg_store;
}
static BOOL prepareStore(void) {
    NSError *error = nil;
    BOOL ready = [store() prepare:&error];
    sg_storageError = error;
    return ready;
}
static BOOL migrateStore(void) {
    NSError *error = nil;
    BOOL migrated = [store() migrate:&error];
    sg_migrationError = error;
    return migrated;
}
static NSDictionary *sg_importPreview;
static BOOL sg_stagingReclaimed;
static BOOL sg_maintenanceStarted, sg_maintained;
// Abandoned import stages are reclaimed once per launch, at the first pass that opens the store; a preview
// staged in this launch is live, so a retry waits until none is held.
static void maintainStore(void) {
    sg_maintenanceStarted = YES;
    NSError *error = nil;
    if ([store() prepare:&error] && (sg_stagingReclaimed || sg_importPreview ||
        (sg_stagingReclaimed = [SGTranslationTransfer reclaimStaging:store() error:&error])))
        migrateStore();
    sg_storageError = error;
    sg_maintained = !sg_storageError && !sg_migrationError;
    refreshSummary();
}
// In-memory read/write authority and unsaved records need stable identities even before unlock.
// Only the store turns a namespace/key into a filesystem path.
static NSURL *recordFolder(NSString *space) {
    return [[NSURL URLWithString:@"record:/"] URLByAppendingPathComponent:space isDirectory:YES];
}
static dispatch_queue_t storeQueue(void) {
    extern NSNotificationName const SGTranslationStorageAvailable;
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        queue = dispatch_queue_create("retrine.translations", DISPATCH_QUEUE_SERIAL);
        // Subscribe before the first prepare; Core sends this only after the latch is visible.
        [NSNotificationCenter.defaultCenter addObserverForName:SGTranslationStorageAvailable object:nil queue:nil
            usingBlock:^(NSNotification *note) {
                dispatch_async(queue, ^{ if (!sg_maintained || [note.object boolValue]) maintainStore(); });
            }];
    });
    return queue;
}

static dispatch_queue_t writes(void) {
    dispatch_queue_t queue = storeQueue();
    static dispatch_once_t once;
    dispatch_once(&once, ^{ dispatch_async(queue, ^{ if (!sg_maintenanceStarted) maintainStore(); }); });
    return queue;
}

// Already on the serial queue. Preserve legacy merge order for this key, then
// queue the library-wide work behind the current read, not in front of it.
static NSError *prepareColdRead(NSURL *file) {
    if (sg_maintenanceStarted || !file) return nil;
    NSError *error = nil;
    [store() migrateSpace:file.URLByDeletingLastPathComponent.lastPathComponent key:file.lastPathComponent error:&error];
    sg_migrationError = error;
    (void)writes();
    return error;
}

static NSURL *fileFor(NSString *track, NSString *language) {
    if (![track isKindOfClass:NSString.class] || !track.length || track.length > 4096 ||
        ![language isKindOfClass:NSString.class] || !SGGoogleTargetLanguage(language)) return nil;
    NSCharacterSet *unsafe = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-"].invertedSet;
    NSString *tag = [[language componentsSeparatedByCharactersInSet:unsafe] componentsJoinedByString:@"_"];
    NSString *name = [NSString stringWithFormat:@"%@.%@.json", track, tag];
    // Keep every previously valid filename, including long local URIs. Only a filename exceeding
    // the filesystem's 255-byte limit or containing a path separator needs a bounded hash.
    if ([name lengthOfBytesUsingEncoding:NSUTF8StringEncoding] > 255 || [track containsString:@"/"] ||
        [track containsString:@"\\"] || [track isEqual:@"."] || [track isEqual:@".."]) {
        NSData *identity = [track dataUsingEncoding:NSUTF8StringEncoding];
        track = [@"local-hash-" stringByAppendingString:SGDataSHA256(identity)];
    }
    return [recordFolder(@"Translations") URLByAppendingPathComponent:[NSString stringWithFormat:@"%@.%@.json", track, tag]];
}

// Never silently evict a failed save. It remains visible, retryable and exportable this launch.
static NSMutableDictionary<NSURL *, NSDictionary *> *sg_unsavedTranslations;
static NSMutableDictionary<NSString *, NSDictionary *> *sg_memoryRecovery;
static void rememberUnsaved(NSURL *file, NSDictionary *answer) {
    if (!sg_unsavedTranslations) sg_unsavedTranslations = [NSMutableDictionary dictionary];
    [sg_unsavedTranslations removeObjectForKey:file];
    if (!answer) return;
    sg_unsavedTranslations[file] = [answer copy];
}
static SGTranslationReadVersion *beginWrite(NSURL *file) {
    @synchronized (SGTranslationReadVersion.class) {
        if (!sg_authorities) sg_authorities = [NSMutableDictionary dictionary];
        SGTranslationReadVersion *authority = sg_authorities[file];
        if (!authority) sg_authorities[file] = authority = [SGTranslationReadVersion new];
        authority.readers++;
        return authority;
    }
}
static void invalidateWrites(NSURL *file) {
    @synchronized (SGTranslationReadVersion.class) { [sg_authorities removeObjectForKey:file]; }
}
static BOOL writeAllowed(NSURL *file, SGTranslationReadVersion *authority) {
    @synchronized (SGTranslationReadVersion.class) { return sg_authorities[file] == authority; }
}
static BOOL finishWrite(NSURL *file, SGTranslationReadVersion *authority) {
    @synchronized (SGTranslationReadVersion.class) {
        BOOL current = sg_authorities[file] == authority;
        if (--authority.readers == 0 && current) [sg_authorities removeObjectForKey:file];
        return current;
    }
}
static void retireAll(void) {
    @synchronized (SGTranslationReadVersion.class) { sg_deleteEpoch++; sg_writeEpoch++; [sg_authorities removeAllObjects]; }
    [sg_translationJobs removeAllObjects];
    SGLyricsAIForgotten();
}

// The token belongs to a song/language, not a view. All calls and callback checks are on main.
static NSUInteger sg_nextTranslationJob;
NSUInteger SGLyricsBeginTranslation(NSString *track, NSString *language) {
    NSURL *file = fileFor(track, language);
    if (!file) return 0;
    invalidateWrites(file);
    if (!sg_translationJobs) sg_translationJobs = [NSMutableDictionary dictionary];
    NSUInteger token = ++sg_nextTranslationJob;
    if (!token) token = ++sg_nextTranslationJob;
    sg_translationJobs[@[track, language]] = @(token);
    return token;
}
BOOL SGLyricsTranslationIsCurrent(NSString *track, NSString *language, NSUInteger token) {
    return token && track && language && [sg_translationJobs[@[track, language]] unsignedIntegerValue] == token;
}
void SGLyricsEndTranslation(NSString *track, NSString *language, NSUInteger token) {
    if (SGLyricsTranslationIsCurrent(track, language, token)) [sg_translationJobs removeObjectForKey:@[track, language]];
}
void SGLyricsDeleteTranslation(NSString *track, NSString *language) {
    SGLyricsDeleteTranslationWithCompletion(track, language, nil);
}
void SGLyricsDeleteTranslationWithCompletion(NSString *track, NSString *language, void (^done)(NSError *)) {
    NSURL *file = fileFor(track, language);
    if (!file) {
        if (done) dispatch_async(dispatch_get_main_queue(), ^{ done(SGTranslationStorageError(@"Invalid translation record.")); });
        return;
    }
    translationMutated(file);
    invalidateWrites(file);
    [sg_translationJobs removeObjectForKey:@[track, language]];
    dispatch_async(writes(), ^{
        NSError *error = nil;
        BOOL removed = [store() removeRecords:@[SGTranslationEnvelope(@"Translations", file.lastPathComponent, @{}, NO)] all:NO error:&error];
        rememberUnsaved(file, removed ? nil : @{});
        sg_storageError = error;
        refreshSummary();
        dispatch_async(dispatch_get_main_queue(), ^{ if (done) done(error); });
    });
}

static NSDictionary *readTranslation(NSURL *file) {
    sg_readFailed = NO;
    if (!file) return nil;
    NSDictionary *saved = sg_unsavedTranslations[file];
    if (saved) return saved;
    NSError *error = prepareColdRead(file);
    NSDictionary *value = error ? nil : [store() read:@"Translations" key:file.lastPathComponent error:&error];
    sg_storageError = error;
    sg_readFailed = error != nil;
    return value;
}
static void applyTranslation(NSDictionary *saved, NSArray<SGKaraokeLine *> *lines) {
    for (SGKaraokeLine *line in lines) {
        id translation = saved[SGKaraokeLineText(line) ?: @""];
        BOOL has = [translation isKindOfClass:NSString.class] &&
            [translation stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length;
        if (line.translationMade) {
            line.translation = has ? translation : nil;
            line.translationMade = has;
        } else if (!line.translation.length && has) {
            line.translation = translation;
            line.translationMade = YES;
        }
    }
}

void SGLyricsSyncSavedTranslation(NSString *track, NSString *language, NSArray<SGKaraokeLine *> *lines) {
    NSURL *file = fileFor(track, language);
    if (!file || !lines.count) return;
    __block NSDictionary *saved;
    __block BOOL failed;
    dispatch_sync(storeQueue(), ^{ saved = readTranslation(file); failed = sg_readFailed; });
    if (!failed) applyTranslation(saved, lines);
}

static void loadRecord(NSURL *file, NSDictionary *(^read)(NSError **), BOOL (^current)(void),
                       void (^done)(NSDictionary *, NSError *), BOOL mayReload) {
    SGTranslationReadVersion *version = nil;
    NSUInteger mutation, epoch;
    @synchronized (SGTranslationReadVersion.class) {
        if (file) {
            if (!sg_readVersions) sg_readVersions = [NSMutableDictionary dictionary];
            version = sg_readVersions[file];
            if (!version) sg_readVersions[file] = version = [SGTranslationReadVersion new];
            version.readers++;
        }
        mutation = version.mutation;
        epoch = sg_deleteEpoch;
    }
    dispatch_async(storeQueue(), ^{
        NSError *error = nil;
        NSDictionary *saved = read(&error);
        dispatch_async(dispatch_get_main_queue(), ^{
            BOOL changed;
            @synchronized (SGTranslationReadVersion.class) {
                changed = file && (mutation != version.mutation || epoch != sg_deleteEpoch);
                if (version && --version.readers == 0) [sg_readVersions removeObjectForKey:file];
            }
            if (!current()) return;
            if (changed) {
                if (mayReload) loadRecord(file, read, current, done, NO);
                // A second intervening mutation retires this attempt too; finish without
                // overwriting live lines. Its newer save/delete owns the current state.
                else done(nil, SGTranslationStorageError(@"Saved record changed while reading. Try again."));
                return;
            }
            done(saved, error);
        });
    });
}

void SGLyricsLoadTranslation(NSString *track, NSString *language, NSArray<SGKaraokeLine *> *lines,
                             BOOL (^current)(void), void (^done)(void)) {
    NSURL *file = fileFor(track, language);
    loadRecord(file, ^NSDictionary *(NSError **error) {
        NSDictionary *saved = readTranslation(file);
        if (sg_readFailed && error) *error = sg_storageError;
        return saved;
    }, current, ^(NSDictionary *saved, NSError *error) {
        if (file && !error) applyTranslation(saved, lines);
        done();
    }, YES);
}

static void saveMap(NSURL *file, NSDictionary *saved, SGLyricsSavedCompletion done) {
    if (!file || !SGTranslationMapValid(saved, file.URLByDeletingLastPathComponent.lastPathComponent)) {
        if (done) done(NO, SGTranslationStorageError(@"Invalid translation record."));
        return;
    }
    saved = [saved copy];
    translationMutated(file);
    SGTranslationReadVersion *authority = beginWrite(file);
    dispatch_async(writes(), ^{
        NSError *error = nil;
        NSString *space = file.URLByDeletingLastPathComponent.lastPathComponent;
        BOOL ready = prepareStore();
        if (!ready) error = sg_storageError;
        NSDictionary *previous = sg_unsavedTranslations[file];
        NSMutableDictionary *displaced = [NSMutableDictionary dictionary];
        for (NSString *key in saved) if (previous[key] && ![previous[key] isEqual:saved[key]]) displaced[key] = previous[key];
        if (displaced.count) {
            if (!sg_memoryRecovery) sg_memoryRecovery = [NSMutableDictionary dictionary];
            NSDictionary *record = SGTranslationEnvelope(space, file.lastPathComponent, displaced, YES);
            sg_memoryRecovery[SGTranslationRecoveryKey(record)] = record;
        }
        NSMutableDictionary *visible = [previous mutableCopy] ?: [NSMutableDictionary dictionary];
        [visible addEntriesFromDictionary:saved];
        if (ready) for (NSString *key in [sg_memoryRecovery.allKeys copy]) {
            if (![store() installRecovery:sg_memoryRecovery[key] grandfather:NO error:&error]) { ready = NO; break; }
            [sg_memoryRecovery removeObjectForKey:key];
        }
        BOOL written = ready && [store() save:visible space:space key:file.lastPathComponent replace:YES preserveMissing:YES grandfather:NO
            allowed:^BOOL { return writeAllowed(file, authority); } error:&error];
        BOOL current = finishWrite(file, authority);
        if (current) {
            if (!written) {
                NSError *readError = nil;
                NSDictionary *disk = [store() read:space key:file.lastPathComponent error:&readError];
                NSMutableDictionary *merged = [disk mutableCopy] ?: [NSMutableDictionary dictionary];
                [merged addEntriesFromDictionary:visible];
                rememberUnsaved(file, merged);
            } else rememberUnsaved(file, nil);
            sg_storageError = error;
        }
        refreshSummary();
        dispatch_async(dispatch_get_main_queue(), ^{
            if (done) done(written && current, error ?: (current ? nil : SGTranslationStorageError(@"Translation write was cancelled.")));
        });
    });
}
void SGLyricsSaveTranslationWithCompletion(NSString *track, NSString *language, NSArray<SGKaraokeLine *> *lines, SGLyricsSavedCompletion done) {
    NSURL *file = fileFor(track, language);
    NSMutableDictionary<NSString *, NSString *> *saved = [NSMutableDictionary dictionary];
    for (SGKaraokeLine *line in lines) {
        NSString *text = SGKaraokeLineText(line);
        if (text.length && line.translationMade &&
            [line.translation stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length) saved[text] = line.translation;
    }
    if (!saved.count) { if (done) done(NO, SGTranslationStorageError(@"No generated translations to save.")); return; }
    saveMap(file, saved, done);
    // Readers enqueue after this write, preserving read-after-write order without blocking main.
    if (file) [NSNotificationCenter.defaultCenter postNotificationName:SGLyricsTranslationSavedNotification object:track
                                                      userInfo:@{@"language": language}];
}
void SGLyricsSaveTranslation(NSString *track, NSString *language, NSArray<SGKaraokeLine *> *lines) {
    SGLyricsSaveTranslationWithCompletion(track, language, lines, nil);
}

static NSString *summary(NSDictionary *stats) {
    NSUInteger count = [stats[@"count"] unsignedIntegerValue];
    if (!count) return SGL(@"settings.translation.savedtranslations.value.none", @"None");
    return [NSString stringWithFormat:SGL(@"settings.translation.savedtranslations.value.format", @"%lu · %@"), (unsigned long)count,
            [NSByteCountFormatter stringFromByteCount:[stats[@"bytes"] longLongValue] countStyle:NSByteCountFormatterCountStyleFile]];
}

static void refreshSummary(void) {
    static BOOL queued;
    if (queued) return;
    queued = YES;
    dispatch_async(writes(), ^{
        queued = NO;
        NSError *error = nil;
        NSDictionary *stats = [store() summary:&error];
        unsigned long long bytes = [stats[@"bytes"] unsignedLongLongValue];
        NSString *warning = (error ?: sg_migrationError ?: sg_storageError).localizedDescription;
        if (sg_unsavedTranslations.count) warning = SGL(@"settings.translation.library.unsaved", @"Unsaved results — retry or export before closing Spotify.");
        else if (bytes >= store().ceiling) warning = SGL(@"settings.translation.library.full", @"Storage ceiling reached. Existing records are kept.");
        NSString *value = warning ? SGL(@"settings.translation.library.attention", @"Needs attention") : summary(stats);
        dispatch_async(dispatch_get_main_queue(), ^{
            sg_savedCount = [stats[@"count"] unsignedIntegerValue];
            sg_storageWarning = warning;
            if ([sg_savedSummary isEqualToString:value]) return;
            sg_savedSummary = value;
            // The live settings row reads this cache on its next value refresh.
            [NSNotificationCenter.defaultCenter postNotificationName:SGLyricsSavedSummaryDidChangeNotification object:nil];
        });
    });
}

SGModRow *SGSavedTranslationsRow(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{ dispatch_async(writes(), ^{ refreshSummary(); }); });
    SGModRow *row = SGPageRow(SGL(@"settings.translation.savedtranslations.title", @"Saved translations"),
                             ^UIViewController *{ return SGSavedTranslationsPage(); });
    row.subtitle = SGL(@"settings.translation.savedtranslations.aisubtitle", @"Saved translations, pronunciations and cultural notes");
    row.value = ^NSString *{ return sg_savedSummary; };
    row.searchIdentifier = @"page.savedtranslations";
    return row;
}

// Hash the tuple instead of cleaning characters: a slash in a track ID cannot escape the folder,
// and different punctuation in identifiers must not make two songs share a file.
static NSURL *aiFile(NSString *kind, NSString *track, NSString *variant) {
    if ((![kind isEqual:@"pronunciation"] && ![kind isEqual:@"notes"]) || ![track isKindOfClass:NSString.class] || !track.length || track.length > 1024 ||
        ![variant isKindOfClass:NSString.class] || !variant.length || variant.length > 64) return nil;
    // Notation zero follows the current translation language. Keep its letters separate when that
    // language changes, while callers continue to identify the notation by the number zero.
    NSArray *identity = [kind isEqual:@"pronunciation"] && [variant isEqual:@"0"]
        ? @[kind, track, variant, SGLyricsGeminiLanguage()] : @[kind, track, variant];
    NSData *tuple = [NSJSONSerialization dataWithJSONObject:identity options:0 error:nil];
    NSString *name = SGDataSHA256(tuple);
    return [recordFolder(@"AI") URLByAppendingPathComponent:[name stringByAppendingString:@".json"]];
}
static NSDictionary *readAI(NSURL *file, NSError **problem) {
    if (!file) { if (problem) *problem = SGTranslationStorageError(@"Invalid AI record identity."); return nil; }
    if (sg_unsavedTranslations[file]) return sg_unsavedTranslations[file];
    NSError *error = prepareColdRead(file);
    if (error) { if (problem) *problem = error; return nil; }
    if (!prepareStore()) { if (problem) *problem = sg_storageError; return nil; }
    NSDictionary *saved = [store() read:@"AI" key:file.lastPathComponent error:&error];
    if (error) { sg_storageError = error; if (problem) *problem = error; }
    return saved;
}
NSDictionary<NSString *, NSString *> *SGLyricsSavedAI(NSString *kind, NSString *track, NSString *variant) {
    NSURL *file = aiFile(kind, track, variant);
    __block NSDictionary *answer = nil;
    dispatch_sync(storeQueue(), ^{ answer = readAI(file, nil); });
    return answer;
}
void SGLyricsLoadSavedAI(NSString *kind, NSString *track, NSString *variant, void (^done)(NSDictionary *, NSError *)) {
    NSURL *file = aiFile(kind, track, variant);
    loadRecord(file, ^NSDictionary *(NSError **error) { return readAI(file, error); }, ^BOOL { return YES; }, done, YES);
}
void SGLyricsSaveAI(NSString *kind, NSString *track, NSString *variant, NSDictionary<NSString *, NSString *> *byLine) {
    SGLyricsSaveAIWithCompletion(kind, track, variant, byLine, nil);
}
void SGLyricsSaveAIWithCompletion(NSString *kind, NSString *track, NSString *variant, NSDictionary<NSString *, NSString *> *byLine, SGLyricsSavedCompletion done) {
    NSURL *file = aiFile(kind, track, variant);
    saveMap(file, byLine, done);
}

void SGLyricsDeleteSavedTranslations(void) {
    retireAll();
    dispatch_sync(writes(), ^{
        NSError *error = nil;
        if ([store() removeRecords:@[] all:YES error:&error]) {
            [sg_unsavedTranslations removeAllObjects]; [sg_memoryRecovery removeAllObjects];
            migrateStore();
        }
        sg_storageError = error;
        refreshSummary();
    });
    [NSNotificationCenter.defaultCenter postNotificationName:SGLyricsAIResultDidChangeNotification object:nil];
}

static void changed(void) {
    [NSNotificationCenter.defaultCenter postNotificationName:SGLyricsTranslationsDidChangeNotification object:nil];
    [NSNotificationCenter.defaultCenter postNotificationName:SGLyricsAIResultDidChangeNotification object:nil];
}
void SGSavedRecords(NSString *after, void (^done)(NSArray *, NSString *, NSDictionary *, NSString *)) {
    dispatch_async(writes(), ^{
        prepareStore();
        NSError *error = nil;
        static const NSUInteger pageSize = 100;
        NSMutableArray *records = [NSMutableArray arrayWithCapacity:pageSize + 1];
        void (^consider)(NSDictionary *) = ^(NSDictionary *descriptor) {
            NSString *key = SGTranslationRecordIdentity(descriptor);
            if (after && [key compare:after options:NSLiteralSearch] != NSOrderedDescending) return;
            NSUInteger index = [records indexOfObject:descriptor inSortedRange:NSMakeRange(0, records.count) options:NSBinarySearchingInsertionIndex
                usingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
                    return [SGTranslationRecordIdentity(a) compare:SGTranslationRecordIdentity(b) options:NSLiteralSearch];
                }];
            if (index < records.count && [SGTranslationRecordIdentity(records[index]) isEqual:key]) records[index] = descriptor;
            else if (index <= pageSize) [records insertObject:descriptor atIndex:index];
            if (records.count > pageSize + 1) [records removeLastObject];
        };
        BOOL ok = [store() enumerateRecords:^BOOL(NSDictionary *descriptor, NSError **failure) { consider(descriptor); return YES; } includeRecovery:YES error:&error];
        for (NSURL *file in sg_unsavedTranslations) {
            NSString *space = file.URLByDeletingLastPathComponent.lastPathComponent;
            @autoreleasepool {
                NSData *data = [NSJSONSerialization dataWithJSONObject:sg_unsavedTranslations[file] options:0 error:nil];
                consider(@{@"namespace":space, @"key":file.lastPathComponent, @"recovery":@NO, @"unsaved":@YES, @"bytes":@(data.length)});
            }
        }
        for (NSDictionary *record in sg_memoryRecovery.allValues) {
            @autoreleasepool {
                NSData *data = [NSJSONSerialization dataWithJSONObject:record options:0 error:nil];
                consider(SGTranslationRecordDescriptor(record, data.length));
            }
        }
        NSString *next = nil;
        if (records.count > pageSize) { [records removeLastObject]; next = SGTranslationRecordIdentity(records.lastObject); }
        NSDictionary *stats = ok ? [store() summary:&error] : nil;
        unsigned long long bytes = [stats[@"bytes"] unsignedLongLongValue];
        NSString *warning = (error ?: sg_migrationError ?: sg_storageError).localizedDescription;
        if (sg_unsavedTranslations.count) warning = SGL(@"settings.translation.library.unsaved", @"Unsaved results — retry or export before closing Spotify.");
        else if (bytes >= store().ceiling) warning = SGL(@"settings.translation.library.full", @"Storage ceiling reached. Existing records are kept.");
        dispatch_async(dispatch_get_main_queue(), ^{ done(records, next, stats, warning); });
        refreshSummary();
    });
}
void SGSavedRemove(NSArray *selection, BOOL all, void (^done)(NSError *)) {
    retireAll();
    dispatch_async(writes(), ^{
        NSError *error = nil;
        BOOL ok = [store() removeRecords:selection all:all error:&error];
        if (ok) {
            if (all) {
                [sg_unsavedTranslations removeAllObjects]; [sg_memoryRecovery removeAllObjects];
                migrateStore();
            }
            else for (NSDictionary *record in selection) {
                if ([record[@"recovery"] boolValue]) { [sg_memoryRecovery removeObjectForKey:record[@"recoveryKey"] ?: SGTranslationRecoveryKey(record)]; continue; }
                NSURL *file = [recordFolder(record[@"namespace"]) URLByAppendingPathComponent:record[@"key"]];
                [sg_unsavedTranslations removeObjectForKey:file];
            }
        }
        sg_storageError = error; refreshSummary();
        dispatch_async(dispatch_get_main_queue(), ^{ changed(); done(error); });
    });
}
void SGSavedRestore(NSDictionary *record, void (^done)(NSError *)) {
    retireAll();
    dispatch_async(writes(), ^{
        NSError *error = nil;
        NSDictionary *recovery = sg_memoryRecovery[record[@"recoveryKey"]] ?: [store() record:record error:&error];
        if (recovery) [store() save:recovery[@"lines"] space:recovery[@"namespace"] key:recovery[@"key"] replace:YES preserveMissing:NO grandfather:NO allowed:nil error:&error];
        sg_storageError = error; refreshSummary();
        dispatch_async(dispatch_get_main_queue(), ^{ changed(); done(error); });
    });
}
void SGSavedRetry(void (^done)(NSError *)) {
    retireAll();
    __block NSUInteger epoch;
    @synchronized (SGTranslationReadVersion.class) { epoch = sg_writeEpoch; }
    dispatch_async(writes(), ^{
        NSError *error = nil;
        for (NSString *key in [sg_memoryRecovery.allKeys copy]) {
            if (![store() installRecovery:sg_memoryRecovery[key] grandfather:NO error:&error]) break;
            [sg_memoryRecovery removeObjectForKey:key];
        }
        NSDictionary *pending = [SGTranslationTransfer pendingStage:store() error:&error];
        if (pending) [SGTranslationTransfer applyStage:pending replace:[pending[@"replace"] boolValue] store:store() allowed:^BOOL {
            @synchronized (SGTranslationReadVersion.class) { return epoch == sg_writeEpoch; }
        } error:&error];
        for (NSURL *file in [sg_unsavedTranslations.allKeys copy]) {
            if (error) break;
            if (![store() save:sg_unsavedTranslations[file] space:file.URLByDeletingLastPathComponent.lastPathComponent key:file.lastPathComponent
                replace:YES preserveMissing:YES grandfather:NO allowed:^BOOL { @synchronized (SGTranslationReadVersion.class) { return epoch == sg_writeEpoch; } } error:&error]) break;
            [sg_unsavedTranslations removeObjectForKey:file];
        }
        if (!error && !migrateStore()) error = sg_migrationError;
        sg_storageError = error; refreshSummary();
        dispatch_async(dispatch_get_main_queue(), ^{ changed(); done(error); });
    });
}

void SGSavedExport(NSArray *selection, void (^done)(NSArray<NSURL *> *, NSError *)) {
    dispatch_async(writes(), ^{
        NSError *error = nil;
        NSMutableDictionary *session = [NSMutableDictionary dictionary];
        for (NSDictionary *record in sg_memoryRecovery.allValues) session[SGTranslationRecordIdentity(record)] = record;
        for (NSURL *file in sg_unsavedTranslations) {
            NSString *space = file.URLByDeletingLastPathComponent.lastPathComponent;
            NSDictionary *record = SGTranslationEnvelope(space, file.lastPathComponent, sg_unsavedTranslations[file], NO);
            session[SGTranslationRecordIdentity(record)] = record;
        }
        NSArray *files = [SGTranslationTransfer exportRecords:selection sessionRecords:session store:store() error:&error];
        dispatch_async(dispatch_get_main_queue(), ^{ done(files, error); });
    });
}
static NSURL *sg_importURL;
void SGSavedDiscardPreview(void (^done)(NSError *)) {
    dispatch_async(writes(), ^{
        NSError *error = nil;
        if ([SGTranslationTransfer discardStage:sg_importPreview store:store() error:&error]) {
            sg_importPreview = nil; sg_importURL = nil;
        }
        dispatch_async(dispatch_get_main_queue(), ^{ if (done) done(error); });
    });
}
void SGSavedImport(NSURL *file, BOOL replace, BOOL preview, void (^done)(NSDictionary *, NSError *)) {
    if (!preview) retireAll();
    __block NSUInteger epoch;
    @synchronized (SGTranslationReadVersion.class) { epoch = sg_writeEpoch; }
    dispatch_async(writes(), ^{
        NSError *error = nil;
        NSDictionary *report = nil;
        if (preview) {
            if ([SGTranslationTransfer discardStage:sg_importPreview store:store() error:&error]) {
                sg_importPreview = [SGTranslationTransfer stageURL:file store:store() error:&error];
                sg_importURL = file;
                report = sg_importPreview;
            }
        } else if (sg_importPreview && [file isEqual:sg_importURL]) {
            for (NSString *key in [sg_memoryRecovery.allKeys copy]) {
                if (![store() installRecovery:sg_memoryRecovery[key] grandfather:NO error:&error]) break;
                [sg_memoryRecovery removeObjectForKey:key];
            }
            for (NSURL *pending in [sg_unsavedTranslations.allKeys copy]) {
                if (error || ![store() save:sg_unsavedTranslations[pending] space:pending.URLByDeletingLastPathComponent.lastPathComponent
                    key:pending.lastPathComponent replace:YES preserveMissing:YES grandfather:NO allowed:nil error:&error]) break;
                [sg_unsavedTranslations removeObjectForKey:pending];
            }
            report = !error ? [SGTranslationTransfer applyStage:sg_importPreview replace:replace store:store() allowed:^BOOL {
                @synchronized (SGTranslationReadVersion.class) { return epoch == sg_writeEpoch; }
            } error:&error] : sg_importPreview;
            sg_importPreview = nil; sg_importURL = nil;
            if (!error) for (NSDictionary *item in report[@"records"]) if (![item[@"recovery"] boolValue]) {
                NSURL *target = [recordFolder(item[@"namespace"]) URLByAppendingPathComponent:item[@"key"]];
                [sg_unsavedTranslations removeObjectForKey:target];
            }
        } else error = SGTranslationStorageError(@"Import preview is no longer available.");
        sg_storageError = error; refreshSummary();
        dispatch_async(dispatch_get_main_queue(), ^{ if (!preview) changed(); done(report, error); });
    });
}
