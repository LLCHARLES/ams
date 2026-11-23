#import "Core/TranslationStore/SGTranslationFiles.h"
#import "Core/TranslationStore/SGTranslationTransfer.h"
#import "Shared/LyricsTranslation/TranslationLibrary.h"
#import <fcntl.h>
#import <unistd.h>
#import <errno.h>
#import <limits.h>
#import <stdlib.h>

static NSString *flushFailureDirectory, *flushFailureTarget;
static NSDictionary *flushFailureContents;
static NSUInteger largestAliasLookup;
BOOL SGLyricsTestProtectedDataAvailable(void) { return NSThread.isMainThread; }
void SGLyricsTestAliasLookupSize(NSUInteger count) { largestAliasLookup = MAX(largestAliasLookup, count); }
int SGLyricsTestFsync(int fd) {
    char path[PATH_MAX], actual[PATH_MAX], expected[PATH_MAX];
    if (flushFailureDirectory) {
        CHECK(fcntl(fd, F_GETPATH, path) == 0);
        CHECK(realpath(path, actual) != NULL);
        CHECK(realpath(flushFailureDirectory.fileSystemRepresentation, expected) != NULL);
    }
    if (flushFailureDirectory && strcmp(actual, expected) == 0 &&
        (!flushFailureTarget || [NSFileManager.defaultManager fileExistsAtPath:flushFailureTarget])) {
        NSData *data = flushFailureContents ? [NSData dataWithContentsOfFile:flushFailureTarget] : nil;
        id value = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        if (!flushFailureContents || [value isEqual:flushFailureContents]) {
            fprintf(stderr, "Injected directory fsync EIO: %s\n", actual);
            errno = EIO; return -1;
        }
    }
    return fsync(fd);
}

static NSURL *storageFixture(void) {
    NSURL *root = [[NSURL fileURLWithPath:NSTemporaryDirectory()] URLByAppendingPathComponent:NSUUID.UUID.UUIDString];
    CHECK([NSFileManager.defaultManager createDirectoryAtURL:root withIntermediateDirectories:YES attributes:nil error:nil]);
    return root;
}
static SGTranslationFiles *fixtureStore(NSURL *root) {
    return [[SGTranslationFiles alloc] initWithRoot:[root URLByAppendingPathComponent:@"Support"] legacy:[root URLByAppendingPathComponent:@"Legacy"]];
}
static void fixtureJSON(NSURL *file, id value) {
    CHECK([NSFileManager.defaultManager createDirectoryAtURL:file.URLByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil]);
    CHECK([[NSJSONSerialization dataWithJSONObject:value options:0 error:nil] writeToURL:file atomically:YES]);
}
static void clearFixture(NSURL *root) { CHECK([NSFileManager.defaultManager removeItemAtURL:root error:nil]); }
static NSUInteger fixtureCount(SGTranslationFiles *store) { return [[store summary:nil][@"count"] unsignedIntegerValue]; }
static NSArray *fixtureRecords(SGTranslationFiles *store) {
    NSMutableArray *records = [NSMutableArray array];
    CHECK([store enumerateRecords:^BOOL(NSDictionary *descriptor, NSError **error) {
        NSDictionary *record = [store record:descriptor error:error];
        if (!record) return NO;
        [records addObject:record]; return YES;
    } includeRecovery:YES error:nil]);
    return records;
}

static void checkStorageLifecycle(void) {
    NSURL *root = storageFixture();
    SGTranslationFiles *store = fixtureStore(root);
    CHECK([store prepare:nil]);
    // A directory in place of state.json is an I/O failure, not an absent file.
    NSURL *state = [store.root URLByAppendingPathComponent:@"TranslationState/state.json"];
    CHECK([NSFileManager.defaultManager createDirectoryAtURL:state withIntermediateDirectories:NO attributes:nil error:nil]);
    CHECK(![store removeRecords:@[] all:YES error:NULL]);
    BOOL unchanged = [[store importAuthority:nil] isEqual:@0];
    BOOL refused = ![fixtureStore(root) prepare:NULL];
    fprintf(stderr, "Failed deletion retained authority: %d; NULL-error read refused: %d\n", unchanged, refused);
    CHECK(unchanged && refused);
    CHECK([NSFileManager.defaultManager removeItemAtURL:store.root error:nil]);
    NSError *error = nil;
    BOOL saved = [store save:@{@"line":@"durable after recreation"} space:@"Translations" key:@"recreated.json"
        replace:YES preserveMissing:YES grandfather:NO allowed:nil error:&error];
    NSDictionary *reopened = [fixtureStore(root) read:@"Translations" key:@"recreated.json" error:nil];
    clearFixture(root);
    CHECK(saved && !error && [reopened[@"line"] isEqual:@"durable after recreation"]);
}

static void checkStorageRetention(void) {
    NSURL *root = storageFixture();
    SGTranslationFiles *store = fixtureStore(root);
    for (NSUInteger i = 0; i < 205; i++) {
        NSString *key = [NSString stringWithFormat:@"song-%lu.ko.json", (unsigned long)i];
        CHECK([store save:@{@"line":@"kept"} space:@"Translations" key:key replace:YES preserveMissing:YES grandfather:NO allowed:nil error:nil]);
    }
    SGTranslationFiles *reopened = fixtureStore(root);
    CHECK([[reopened read:@"Translations" key:@"song-0.ko.json" error:nil][@"line"] isEqual:@"kept"]);
    CHECK(fixtureCount(reopened) == 205);
    clearFixture(root);
}
static void checkMigrationResume(void) {
    NSURL *root = storageFixture();
    NSURL *legacy = [root URLByAppendingPathComponent:@"Legacy/Translations/song.ko.json"];
    fixtureJSON(legacy, @{@"line":@"legacy", @"other":@"retained"});
    SGTranslationFiles *store = fixtureStore(root);
    CHECK([store prepare:nil]);
    // A crash after the active commit but before the receipt leaves this observable state.
    fixtureJSON([root URLByAppendingPathComponent:@"Support/Translations/song.ko.json"], @{@"line":@"legacy", @"other":@"retained"});
    store = fixtureStore(root);
    CHECK([store migrate:nil]);
    CHECK([store migrate:nil]);
    CHECK(fixtureCount(store) == 1);
    CHECK([NSFileManager.defaultManager fileExistsAtPath:legacy.path]);
    CHECK([[store read:@"Translations" key:@"song.ko.json" error:nil][@"other"] isEqual:@"retained"]);
    clearFixture(root);
}
static void checkMigrationConflict(void) {
    NSURL *root = storageFixture();
    SGTranslationFiles *store = fixtureStore(root);
    CHECK([store save:@{@"same":@"local"} space:@"Translations" key:@"song.ko.json" replace:YES preserveMissing:YES grandfather:NO allowed:nil error:nil]);
    fixtureJSON([root URLByAppendingPathComponent:@"Legacy/Translations/song.ko.json"], @{@"same":@"legacy", @"new":@"addition"});
    CHECK([store migrate:nil]);
    CHECK(([[store read:@"Translations" key:@"song.ko.json" error:nil] isEqual:@{@"same":@"local", @"new":@"addition"}]));
    NSArray *records = fixtureRecords(store);
    CHECK(records.count == 2);
    NSDictionary *recovery = [records filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *r, NSDictionary *bindings) { return [r[@"recovery"] boolValue]; }]].firstObject;
    CHECK([recovery[@"lines"][@"same"] isEqual:@"legacy"]);
    clearFixture(root);
}
static void checkDeletionSuppression(void) {
    NSURL *root = storageFixture();
    SGTranslationFiles *store = fixtureStore(root);
    NSURL *legacy = [root URLByAppendingPathComponent:@"Legacy/AI/hash.json"];
    fixtureJSON(legacy, @{@"":@""});
    CHECK([store migrate:nil]);
    CHECK([store removeRecords:@[] all:YES error:nil]);
    // Even a changed legacy digest after a downgrade cannot defeat the tombstone.
    fixtureJSON(legacy, @{@"new":@"changed"});
    store = fixtureStore(root);
    CHECK([store migrate:nil]);
    CHECK(![store read:@"AI" key:@"hash.json" error:nil]);
    CHECK(fixtureCount(store) == 0);
    clearFixture(root);
}
static void checkStoreAdmission(void) {
    NSURL *root = storageFixture();
    SGTranslationFiles *store = fixtureStore(root);
    CHECK([store save:@{@"a":@"old"} space:@"Translations" key:@"song.json" replace:YES preserveMissing:YES grandfather:NO allowed:nil error:nil]);
    store.ceiling = 1;
    CHECK([store save:@{@"a":@"old"} space:@"Translations" key:@"song.json" replace:YES preserveMissing:YES grandfather:NO allowed:nil error:nil]);
    NSError *error = nil;
    CHECK(![store save:@{@"a":@"new"} space:@"Translations" key:@"song.json" replace:YES preserveMissing:YES grandfather:NO allowed:nil error:&error] && error);
    CHECK([[store read:@"Translations" key:@"song.json" error:nil][@"a"] isEqual:@"old"]);
    fixtureJSON([root URLByAppendingPathComponent:@"Legacy/Translations/migrated.json"], @{@"a":@"grandfathered"});
    CHECK([store migrate:nil]);
    CHECK([[store read:@"Translations" key:@"migrated.json" error:nil][@"a"] isEqual:@"grandfathered"]);
    clearFixture(root);
}
static void checkTransferMerge(void) {
    NSURL *root = storageFixture(), *target = storageFixture();
    SGTranslationFiles *source = fixtureStore(root), *destination = fixtureStore(target);
    NSString *hash = @"23b47f75127d4a814a5787252c0c079843b2b656118ac0e818720e49980b303a9.json";
    NSString *local = @"local-hash-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.ko.json";
    CHECK(([source save:@{@"":@"", @"line":@"incoming"} space:@"AI" key:hash replace:YES preserveMissing:YES grandfather:NO allowed:nil error:nil]));
    CHECK([source save:@{@"line":@"local song"} space:@"Translations" key:local replace:YES preserveMissing:YES grandfather:NO allowed:nil error:nil]);
    CHECK(([destination save:@{@"line":@"existing", @"only-local":@"keep"} space:@"AI" key:hash replace:YES preserveMissing:YES grandfather:NO allowed:nil error:nil]));
    NSError *error = nil;
    NSArray *exports = [SGTranslationTransfer exportRecords:nil sessionRecords:@{} store:source error:&error];
    CHECK(exports.count == 1 && !error);
    NSDictionary *stage = [SGTranslationTransfer stageURL:exports.firstObject store:destination error:&error];
    CHECK(stage && !error);
    NSDictionary *result = [SGTranslationTransfer applyStage:stage replace:NO store:destination allowed:nil error:&error];
    CHECK([result[@"completed"] integerValue] == 2 && !error);
    CHECK(([[destination read:@"AI" key:hash error:nil] isEqual:@{@"line":@"existing", @"only-local":@"keep", @"":@""}]));
    CHECK([[destination read:@"Translations" key:local error:nil][@"line"] isEqual:@"local song"]);
    CHECK(fixtureCount(destination) == 3);
    stage = [SGTranslationTransfer stageURL:exports.firstObject store:destination error:&error];
    CHECK(stage);
    result = [SGTranslationTransfer applyStage:stage replace:YES store:destination allowed:nil error:&error];
    CHECK([result[@"completed"] integerValue] == 2 && !error);
    CHECK(([[destination read:@"AI" key:hash error:nil] isEqual:@{@"line":@"incoming", @"":@""}]));
    BOOL preserved = NO;
    for (NSDictionary *record in fixtureRecords(destination)) if ([record[@"recovery"] boolValue] && [record[@"lines"][@"only-local"] isEqual:@"keep"]) preserved = YES;
    CHECK(preserved);
    clearFixture([exports.firstObject URLByDeletingLastPathComponent]);
    clearFixture(root); clearFixture(target);
}
static void checkTransferRejection(void) {
    NSError *error = nil;
    CHECK(!SGTranslationReadJSON([@"{\"x\":1,\"\\u0078\":2}" dataUsingEncoding:NSUTF8StringEncoding], &error) && error);
    CHECK(!SGTranslationRecordKeyValid(@"../escape.json"));
    CHECK(!SGTranslationRecordKeyValid(@"a\\b.json"));
    CHECK(!SGTranslationEnvelopeValid(@{@"type":@"vitrine.saved-record", @"version":@YES, @"namespace":@"AI", @"key":@"a.json", @"lines":@{}, @"recovery":@NO}));
    NSURL *root = storageFixture(), *target = storageFixture();
    SGTranslationFiles *store = fixtureStore(root), *destination = fixtureStore(target);
    CHECK([store save:@{@"line":@"first"} space:@"Translations" key:@"first.json" replace:YES preserveMissing:YES grandfather:NO allowed:nil error:nil]);
    CHECK([store save:@{@"line":@"second"} space:@"Translations" key:@"second.json" replace:YES preserveMissing:YES grandfather:NO allowed:nil error:nil]);
    error = nil;
    NSArray *files = [SGTranslationTransfer exportRecords:nil sessionRecords:@{} store:store error:&error];
    CHECK(files && !error);
    NSMutableData *damaged = [[NSData dataWithContentsOfURL:files.firstObject] mutableCopy];
    // Corrupt the later manifest payload, leaving ZIP structure intact.
    NSData *needle = [@"vitrine.saved-archive" dataUsingEncoding:NSUTF8StringEncoding];
    NSRange range = [damaged rangeOfData:needle options:0 range:NSMakeRange(0, damaged.length)];
    CHECK(range.location != NSNotFound);
    ((uint8_t *)damaged.mutableBytes)[range.location] ^= 1;
    CHECK([damaged writeToURL:files.firstObject atomically:YES]);
    CHECK(![SGTranslationTransfer stageURL:files.firstObject store:destination error:&error] && error);
    CHECK(fixtureCount(destination) == 0);
    clearFixture([files.firstObject URLByDeletingLastPathComponent]);
    clearFixture(root); clearFixture(target);
}
static void checkImportResume(void) {
    NSURL *root = storageFixture(), *target = storageFixture();
    SGTranslationFiles *source = fixtureStore(root), *destination = fixtureStore(target);
    CHECK([source save:@{@"a":@"one"} space:@"AI" key:@"a.json" replace:YES preserveMissing:YES grandfather:NO allowed:nil error:nil]);
    CHECK([source save:@{@"b":@"two"} space:@"AI" key:@"b.json" replace:YES preserveMissing:YES grandfather:NO allowed:nil error:nil]);
    NSArray *files = [SGTranslationTransfer exportRecords:nil sessionRecords:@{} store:source error:nil];
    NSDictionary *stage = [SGTranslationTransfer stageURL:files.firstObject store:destination error:nil];
    CHECK(stage);
    NSError *error = nil;
    NSURL *receipt = [destination.root URLByAppendingPathComponent:@"TranslationState/import.json"];
    NSDictionary *partial = [SGTranslationTransfer applyStage:stage replace:NO store:destination allowed:^BOOL {
        NSData *data = [NSData dataWithContentsOfURL:receipt];
        NSDictionary *progress = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        return [progress[@"completed"] unsignedIntegerValue] < 1;
    } error:&error];
    CHECK(error && fixtureCount(destination) == 1);
    CHECK([partial[@"completed"] integerValue] == 1);
    destination = fixtureStore(target);
    error = nil;
    NSDictionary *pending = [SGTranslationTransfer pendingStage:destination error:&error];
    CHECK(pending && !error && [pending[@"completed"] integerValue] == 1);
    NSDictionary *done = [SGTranslationTransfer applyStage:pending replace:NO store:destination allowed:nil error:&error];
    CHECK(!error && [done[@"completed"] integerValue] == 2 && fixtureCount(destination) == 2);
    clearFixture([files.firstObject URLByDeletingLastPathComponent]);
    clearFixture(root); clearFixture(target);
}
static void checkDeletedImportAuthority(void) {
    NSURL *sourceRoot = storageFixture(), *targetRoot = storageFixture();
    SGTranslationFiles *source = fixtureStore(sourceRoot), *target = fixtureStore(targetRoot);
    CHECK([source save:@{@"a":@"first"} space:@"AI" key:@"a.json" replace:NO preserveMissing:YES grandfather:NO allowed:nil error:nil]);
    CHECK([source save:@{@"b":@"second"} space:@"AI" key:@"b.json" replace:NO preserveMissing:YES grandfather:NO allowed:nil error:nil]);
    NSArray *files = [SGTranslationTransfer exportRecords:nil sessionRecords:@{} store:source error:nil];
    NSDictionary *stage = [SGTranslationTransfer stageURL:files.firstObject store:target error:nil];
    CHECK(stage);
    NSURL *receipt = [target.root URLByAppendingPathComponent:@"TranslationState/import.json"];
    NSError *error = nil;
    [SGTranslationTransfer applyStage:stage replace:NO store:target allowed:^BOOL {
        NSData *data = [NSData dataWithContentsOfURL:receipt];
        NSDictionary *progress = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        return [progress[@"completed"] unsignedIntegerValue] < 1;
    } error:&error];
    CHECK(error);
    NSDictionary *deleted = stage[@"records"][1];
    CHECK([target removeRecords:@[deleted] all:NO error:nil]);
    target = fixtureStore(targetRoot); error = nil;
    NSDictionary *pending = [SGTranslationTransfer pendingStage:target error:&error];
    NSDictionary *done = [SGTranslationTransfer applyStage:pending replace:NO store:target allowed:^BOOL { return YES; } error:&error];
    CHECK(!error && [done[@"deleted"] integerValue] == 1);
    CHECK(![target read:deleted[@"namespace"] key:deleted[@"key"] error:nil] && fixtureCount(target) == 1);
    clearFixture([files.firstObject URLByDeletingLastPathComponent]);
    clearFixture(sourceRoot); clearFixture(targetRoot);
}
static void checkUncertainCommitRetry(void) {
    NSURL *root = storageFixture();
    SGTranslationFiles *store = fixtureStore(root);
    CHECK([store save:@{@"line":@"old"} space:@"Translations" key:@"song.json" replace:YES preserveMissing:YES grandfather:NO allowed:nil error:nil]);
    flushFailureDirectory = [store.root URLByAppendingPathComponent:@"Translations"].URLByResolvingSymlinksInPath.path;
    flushFailureTarget = [store.root URLByAppendingPathComponent:@"Translations/song.json"].path;
    flushFailureContents = @{@"line":@"new"};
    NSError *first = nil, *retry = nil;
    BOOL saved = [store save:@{@"line":@"new"} space:@"Translations" key:@"song.json" replace:YES preserveMissing:YES grandfather:NO allowed:nil error:&first];
    BOOL retried = [store save:@{@"line":@"new"} space:@"Translations" key:@"song.json" replace:YES preserveMissing:YES grandfather:NO allowed:nil error:&retry];
    flushFailureDirectory = flushFailureTarget = nil; flushFailureContents = nil;
    CHECK(!saved && first && !retried && retry);
    CHECK([store save:@{@"line":@"new"} space:@"Translations" key:@"song.json" replace:YES preserveMissing:YES grandfather:NO allowed:nil error:nil]);
    CHECK([[fixtureStore(root) read:@"Translations" key:@"song.json" error:nil][@"line"] isEqual:@"new"]);
    clearFixture(root);
}
static void checkDirectoryLinkDurability(void) {
    NSURL *root = storageFixture();
    SGTranslationFiles *store = fixtureStore(root);
    CHECK([store prepare:nil]);
    flushFailureDirectory = store.root.URLByResolvingSymlinksInPath.path;
    flushFailureTarget = [store.root URLByAppendingPathComponent:@"Translations"].path;
    NSError *error = nil;
    BOOL saved = [store save:@{@"line":@"new"} space:@"Translations" key:@"song.json" replace:YES preserveMissing:YES grandfather:NO allowed:nil error:&error];
    flushFailureDirectory = flushFailureTarget = nil;
    CHECK(!saved && error);
    CHECK(![NSFileManager.defaultManager fileExistsAtPath:[store.root URLByAppendingPathComponent:@"Translations/song.json"].path]);
    CHECK([store save:@{@"line":@"new"} space:@"Translations" key:@"song.json" replace:YES preserveMissing:YES grandfather:NO allowed:nil error:nil]);
    clearFixture(root);
}
static void checkImportTraversal(void) {
    NSURL *root = storageFixture();
    // Independent Python zipfile fixture: a valid envelope/manifest with a traversal entry.
    NSString *encoded = @"UEsDBBQAAAAAAHBybF3IMp1rhQAAAIUAAAAOAAAALi4vZXNjYXBlLmpzb257InR5cGUiOiJ2aXRyaW5lLnNhdmVkLXJlY29yZCIsInZlcnNpb24iOjEsIm5hbWVzcGFjZSI6IlRyYW5zbGF0aW9ucyIsImtleSI6ImEua28uanNvbiIsImxpbmVzIjp7ImxpbmUiOiJpbmNvbWluZyJ9LCJyZWNvdmVyeSI6ZmFsc2V9UEsDBBQAAAAAAHBybF1kuMakngAAAJ4AAAANAAAAbWFuaWZlc3QuanNvbnsidHlwZSI6InZpdHJpbmUuc2F2ZWQtYXJjaGl2ZSIsInZlcnNpb24iOjEsInJlY29yZHMiOlt7Im5hbWUiOiIuLi9lc2NhcGUuanNvbiIsInNoYTI1NiI6Ijc2OWE5MTQ5MDljMzAwMjEzZTU2ZWUxODZlZjlkYjQ3NWM1NzU0OWY1YTg0YTc2MTBkZjU5OTk1YmNmNTEzZjcifV19UEsBAhQDFAAAAAAAcHJsXcgynWuFAAAAhQAAAA4AAAAAAAAAAAAAAIABAAAAAC4uL2VzY2FwZS5qc29uUEsBAhQDFAAAAAAAcHJsXWS4xqSeAAAAngAAAA0AAAAAAAAAAAAAAIABsQAAAG1hbmlmZXN0Lmpzb25QSwUGAAAAAAIAAgB3AAAAegEAAAAA";
    NSURL *url = [root URLByAppendingPathComponent:@"traversal.zip"];
    CHECK([[[NSData alloc] initWithBase64EncodedString:encoded options:0] writeToURL:url atomically:YES]);
    SGTranslationFiles *store = fixtureStore(root);
    NSError *error = nil;
    CHECK(![SGTranslationTransfer stageURL:url store:store error:&error] && error);
    CHECK(fixtureCount(store) == 0);
    clearFixture(root);
}
static void checkImportDuplicateIdentity(void) {
    NSURL *root = storageFixture();
    // The distinct ZIP names and matching manifest both identify the same saved record.
    NSString *encoded = @"UEsDBBQAAAAAAHBybF3IMp1rhQAAAIUAAAAGAAAAYS5qc29ueyJ0eXBlIjoidml0cmluZS5zYXZlZC1yZWNvcmQiLCJ2ZXJzaW9uIjoxLCJuYW1lc3BhY2UiOiJUcmFuc2xhdGlvbnMiLCJrZXkiOiJhLmtvLmpzb24iLCJsaW5lcyI6eyJsaW5lIjoiaW5jb21pbmcifSwicmVjb3ZlcnkiOmZhbHNlfVBLAwQUAAAAAABwcmxdyDKda4UAAACFAAAABgAAAGIuanNvbnsidHlwZSI6InZpdHJpbmUuc2F2ZWQtcmVjb3JkIiwidmVyc2lvbiI6MSwibmFtZXNwYWNlIjoiVHJhbnNsYXRpb25zIiwia2V5IjoiYS5rby5qc29uIiwibGluZXMiOnsibGluZSI6ImluY29taW5nIn0sInJlY292ZXJ5IjpmYWxzZX1QSwMEFAAAAAAAcHJsXVBshCD0AAAA9AAAAA0AAABtYW5pZmVzdC5qc29ueyJ0eXBlIjoidml0cmluZS5zYXZlZC1hcmNoaXZlIiwidmVyc2lvbiI6MSwicmVjb3JkcyI6W3sibmFtZSI6ImEuanNvbiIsInNoYTI1NiI6Ijc2OWE5MTQ5MDljMzAwMjEzZTU2ZWUxODZlZjlkYjQ3NWM1NzU0OWY1YTg0YTc2MTBkZjU5OTk1YmNmNTEzZjcifSx7Im5hbWUiOiJiLmpzb24iLCJzaGEyNTYiOiI3NjlhOTE0OTA5YzMwMDIxM2U1NmVlMTg2ZWY5ZGI0NzVjNTc1NDlmNWE4NGE3NjEwZGY1OTk5NWJjZjUxM2Y3In1dfVBLAQIUAxQAAAAAAHBybF3IMp1rhQAAAIUAAAAGAAAAAAAAAAAAAACAAQAAAABhLmpzb25QSwECFAMUAAAAAABwcmxdyDKda4UAAACFAAAABgAAAAAAAAAAAAAAgAGpAAAAYi5qc29uUEsBAhQDFAAAAAAAcHJsXVBshCD0AAAA9AAAAA0AAAAAAAAAAAAAAIABUgEAAG1hbmlmZXN0Lmpzb25QSwUGAAAAAAMAAwCjAAAAcQIAAAAA";
    NSURL *url = [root URLByAppendingPathComponent:@"duplicate.zip"];
    CHECK([[[NSData alloc] initWithBase64EncodedString:encoded options:0] writeToURL:url atomically:YES]);
    SGTranslationFiles *store = fixtureStore(root);
    NSError *error = nil;
    CHECK(![SGTranslationTransfer stageURL:url store:store error:&error] && error);
    CHECK(fixtureCount(store) == 0);
    clearFixture(root);
}
static void checkImportFilesystemAliases(void) {
    NSURL *root = storageFixture();
    SGTranslationFiles *store = fixtureStore(root);
    CHECK([store prepare:nil]);
    NSNumber *caseSensitive = nil;
    CHECK([store.root getResourceValue:&caseSensitive forKey:NSURLVolumeSupportsCaseSensitiveNamesKey error:nil]);
    NSMutableArray *pairs = [NSMutableArray arrayWithObject:@[@"caf\u00e9.json", @"cafe\u0301.json"]];
    if (!caseSensitive.boolValue) [pairs addObject:@[@"Song.json", @"song.json"]];
    for (NSArray *pair in pairs) {
        NSDictionary *first = SGTranslationEnvelope(@"Translations", pair[0], @{@"line":@"local"}, NO);
        NSDictionary *second = SGTranslationEnvelope(@"Translations", pair[1], @{@"line":@"incoming"}, NO);
        NSArray *files = [SGTranslationTransfer exportRecords:@[first, second]
            sessionRecords:@{SGTranslationRecordIdentity(first):first, SGTranslationRecordIdentity(second):second}
            store:store error:nil];
        CHECK(files.count == 1);
        NSError *error = nil;
        CHECK(![SGTranslationTransfer stageURL:files[0] store:store error:&error] && error);
        CHECK(fixtureCount(store) == 0);
        clearFixture([files[0] URLByDeletingLastPathComponent]);
        CHECK([store save:first[@"lines"] space:@"Translations" key:pair[0] replace:NO preserveMissing:YES grandfather:NO allowed:nil error:nil]);
        NSURL *incoming = [root URLByAppendingPathComponent:@"incoming.json"];
        __block NSString *storedKey = nil;
        CHECK([store enumerateRecords:^BOOL(NSDictionary *record, NSError **problem) {
            CHECK(!storedKey);
            storedKey = record[@"key"];
            return YES;
        } includeRecovery:YES error:nil]);
        CHECK(storedKey);
        NSData *storedBytes = [storedKey dataUsingEncoding:NSUTF8StringEncoding];
        NSString *alias = [storedBytes isEqual:[pair[0] dataUsingEncoding:NSUTF8StringEncoding]] ? pair[1] : pair[0];
        CHECK(![storedBytes isEqual:[alias dataUsingEncoding:NSUTF8StringEncoding]]);
        fixtureJSON(incoming, SGTranslationEnvelope(@"Translations", alias, @{@"line":@"incoming"}, NO)); error = nil;
        CHECK(![SGTranslationTransfer stageURL:incoming store:store error:&error] && error);
        CHECK([[store read:@"Translations" key:storedKey error:nil][@"line"] isEqual:@"local"]);
        CHECK([store removeRecords:@[first] all:NO error:nil]);
    }
    clearFixture(root);
}
static void checkImportAliasAfterPreview(void) {
    NSURL *root = storageFixture();
    SGTranslationFiles *store = fixtureStore(root);
    NSURL *incoming = [root URLByAppendingPathComponent:@"incoming.json"];
    fixtureJSON(incoming, SGTranslationEnvelope(@"Translations", @"caf\u00e9.ko.json", @{@"line":@"incoming"}, NO));
    NSDictionary *stage = [SGTranslationTransfer stageURL:incoming store:store error:nil];
    CHECK(stage);
    CHECK([store save:@{@"line":@"local"} space:@"Translations" key:@"cafe\u0301.ko.json"
        replace:NO preserveMissing:YES grandfather:NO allowed:nil error:nil]);
    NSError *error = nil;
    NSDictionary *report = [SGTranslationTransfer applyStage:stage replace:NO store:store allowed:nil error:&error];
    CHECK(error && [report[@"completed"] integerValue] == 0);
    store = fixtureStore(root); error = nil;
    stage = [SGTranslationTransfer pendingStage:store error:&error];
    CHECK(stage && !error);
    report = [SGTranslationTransfer applyStage:stage replace:YES store:store allowed:nil error:&error];
    CHECK(error && [report[@"completed"] integerValue] == 0);
    CHECK([[store read:@"Translations" key:@"cafe\u0301.ko.json" error:nil][@"line"] isEqual:@"local"]);
    clearFixture(root);
}
static void checkRecoveryAliasRoundTrip(void) {
    NSURL *sourceRoot = storageFixture(), *targetRoot = storageFixture();
    SGTranslationFiles *source = fixtureStore(sourceRoot), *target = fixtureStore(targetRoot);
    CHECK([source save:@{@"line":@"previous"} space:@"Translations" key:@"caf\u00e9.json"
        replace:YES preserveMissing:YES grandfather:NO allowed:nil error:nil]);
    CHECK([source save:@{@"line":@"current"} space:@"Translations" key:@"caf\u00e9.json"
        replace:YES preserveMissing:YES grandfather:NO allowed:nil error:nil]);
    NSArray *files = [SGTranslationTransfer exportRecords:nil sessionRecords:@{} store:source error:nil];
    CHECK(files.count == 1);
    NSError *error = nil;
    NSDictionary *stage = [SGTranslationTransfer stageURL:files[0] store:target error:&error];
    CHECK(stage && !error);
    NSDictionary *report = [SGTranslationTransfer applyStage:stage replace:NO store:target allowed:nil error:&error];
    CHECK(!error && [report[@"completed"] integerValue] == 2);
    CHECK([[target read:@"Translations" key:@"cafe\u0301.json" error:nil][@"line"] isEqual:@"current"]);
    BOOL recovered = NO;
    for (NSDictionary *record in fixtureRecords(target)) if ([record[@"recovery"] boolValue])
        recovered = [record[@"lines"][@"line"] isEqual:@"previous"];
    CHECK(recovered);
    clearFixture([files[0] URLByDeletingLastPathComponent]);
    clearFixture(sourceRoot); clearFixture(targetRoot);
}
static void checkImportIgnoresRecoveryBodies(void) {
    NSURL *root = storageFixture();
    SGTranslationFiles *store = fixtureStore(root);
    CHECK([store prepare:nil]);
    NSURL *recovery = [store.root URLByAppendingPathComponent:
        @"TranslationRecovery/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.json"];
    fixtureJSON(recovery, @[@"not a recovery envelope"]);
    NSURL *url = [root URLByAppendingPathComponent:@"incoming.json"];
    fixtureJSON(url, SGTranslationEnvelope(@"Translations", @"independent.json", @{@"line":@"imported"}, NO));
    NSError *error = nil;
    NSDictionary *stage = [SGTranslationTransfer stageURL:url store:store error:&error];
    CHECK(stage && !error);
    NSDictionary *report = [SGTranslationTransfer applyStage:stage replace:NO store:store allowed:nil error:&error];
    CHECK(!error && [report[@"completed"] integerValue] == 1);
    CHECK([[store read:@"Translations" key:@"independent.json" error:nil][@"line"] isEqual:@"imported"]);
    CHECK([NSFileManager.defaultManager fileExistsAtPath:recovery.path]);
    clearFixture(root);
}
static void checkImportAliasLookupBound(void) {
    NSURL *root = storageFixture();
    SGTranslationFiles *store = fixtureStore(root);
    for (NSUInteger i = 0; i < 100; i++) {
        CHECK(([store save:@{@"local":@"kept"} space:@"Translations"
            key:[NSString stringWithFormat:@"record-%lu.json", (unsigned long)i]
            replace:NO preserveMissing:YES grandfather:NO allowed:nil error:nil]));
    }
    NSURL *url = [root URLByAppendingPathComponent:@"incoming.json"];
    fixtureJSON(url, SGTranslationEnvelope(@"Translations", @"record-0.json", @{@"incoming":@"added"}, NO));
    largestAliasLookup = 0;
    NSError *error = nil;
    NSDictionary *stage = [SGTranslationTransfer stageURL:url store:store error:&error];
    CHECK(stage && !error);
    NSURL *receipt = [store.root URLByAppendingPathComponent:@"TranslationState/import.json"];
    NSDictionary *report = [SGTranslationTransfer applyStage:stage replace:NO store:store allowed:^BOOL {
        return ![NSFileManager.defaultManager fileExistsAtPath:receipt.path];
    } error:&error];
    CHECK(error && [report[@"completed"] integerValue] == 0);
    store = fixtureStore(root); error = nil;
    stage = [SGTranslationTransfer pendingStage:store error:&error];
    CHECK(stage && !error);
    report = [SGTranslationTransfer applyStage:stage replace:NO store:store allowed:nil error:&error];
    CHECK(!error && [report[@"completed"] integerValue] == 1);
    CHECK(largestAliasLookup == 1);
    CHECK(([[store read:@"Translations" key:@"record-0.json" error:nil] isEqual:@{@"local":@"kept", @"incoming":@"added"}]));
    clearFixture(root);
    largestAliasLookup = 0;
}
static void checkImportStagingLifecycle(void) {
    NSURL *root = storageFixture();
    SGTranslationFiles *store = fixtureStore(root);
    NSURL *incoming = [root URLByAppendingPathComponent:@"incoming.json"];
    fixtureJSON(incoming, SGTranslationEnvelope(@"AI", @"opaque.json", @{@"line":@"kept"}, NO));
    NSDictionary *first = [SGTranslationTransfer stageURL:incoming store:store error:nil];
    CHECK(first);
    NSURL *staging = [store.root URLByAppendingPathComponent:@"TranslationImports"];
    NSDictionary *replacement = [SGTranslationTransfer stageURL:incoming store:store error:nil];
    CHECK(replacement);
    NSArray *remaining = [NSFileManager.defaultManager contentsOfDirectoryAtPath:staging.path error:nil];
    CHECK(remaining.count == 1 && [remaining[0] isEqual:replacement[@"directory"]]);
    CHECK([SGTranslationTransfer discardStage:replacement store:store error:nil]);
    CHECK([NSFileManager.defaultManager contentsOfDirectoryAtPath:staging.path error:nil].count == 0);
    CHECK([SGTranslationTransfer stageURL:incoming store:store error:nil]);
    CHECK([SGTranslationTransfer reclaimStaging:fixtureStore(root) error:nil]);
    CHECK([NSFileManager.defaultManager contentsOfDirectoryAtPath:staging.path error:nil].count == 0);
    clearFixture(root);
}
static void checkSessionExportUnavailableStore(void) {
    NSURL *root = storageFixture();
    SGTranslationFiles *store = fixtureStore(root);
    CHECK([@"unavailable" writeToURL:store.root atomically:YES encoding:NSUTF8StringEncoding error:nil]);
    NSDictionary *record = SGTranslationEnvelope(@"AI", @"opaque.json", @{@"line":@"session answer"}, NO);
    NSDictionary *session = @{SGTranslationRecordIdentity(record):record};
    NSError *error = nil;
    NSArray *files = [SGTranslationTransfer exportRecords:@[record] sessionRecords:session store:store error:&error];
    CHECK(files.count == 1 && !error);
    NSDictionary *exported = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfURL:files[0]] options:0 error:nil];
    CHECK([exported[@"lines"][@"line"] isEqual:@"session answer"]);
    clearFixture([files[0] URLByDeletingLastPathComponent]);
    CHECK(![SGTranslationTransfer exportRecords:nil sessionRecords:session store:store error:&error] && error);
    clearFixture(root);
}
static uint32_t fixtureWord(const uint8_t *bytes) {
    return bytes[0] | ((uint32_t)bytes[1] << 8) | ((uint32_t)bytes[2] << 16) | ((uint32_t)bytes[3] << 24);
}
static void fixturePutWord(uint8_t *bytes, uint32_t value) {
    for (NSUInteger i = 0; i < 4; i++) bytes[i] = (uint8_t)(value >> (i * 8));
}
static void checkImportExpansionBound(void) {
    NSURL *root = storageFixture();
    SGTranslationFiles *store = fixtureStore(root);
    for (NSUInteger i = 0; i < 31; i++) {
        NSString *key = [NSString stringWithFormat:@"entry-%lu.json", (unsigned long)i];
        CHECK([store save:@{@"line":@"small"} space:@"Translations" key:key replace:YES preserveMissing:YES grandfather:NO allowed:nil error:nil]);
    }
    NSArray *files = [SGTranslationTransfer exportRecords:nil sessionRecords:@{} store:store error:nil];
    CHECK(files.count == 1);
    NSMutableData *data = [[NSData dataWithContentsOfURL:files[0]] mutableCopy];
    uint8_t *bytes = data.mutableBytes;
    NSUInteger end = data.length - 22, central = fixtureWord(bytes + end + 16);
    CHECK(fixtureWord(bytes + end) == 0x06054b50 && (bytes[end + 10] | (bytes[end + 11] << 8)) == 32);
    for (NSUInteger i = 0; i < 32; i++) {
        CHECK(central + 46 <= data.length && fixtureWord(bytes + central) == 0x02014b50);
        NSUInteger local = fixtureWord(bytes + central + 42);
        CHECK(local + 30 <= data.length);
        // Individually permitted claims whose aggregate must be refused before inflation.
        fixturePutWord(bytes + central + 24, 9 * 1024 * 1024);
        fixturePutWord(bytes + local + 22, 9 * 1024 * 1024);
        central += 46 + (bytes[central + 28] | (bytes[central + 29] << 8));
    }
    CHECK([data writeToURL:files[0] atomically:YES]);
    NSError *error = nil;
    CHECK(![SGTranslationTransfer stageURL:files[0] store:store error:&error]);
    CHECK([error.localizedDescription isEqual:@"Expanded translation archive exceeds 256 MiB."]);
    CHECK(fixtureCount(store) == 31);
    clearFixture([files[0] URLByDeletingLastPathComponent]); clearFixture(root);
}
static void checkSaveCompletionFailure(void) {
    SGLyricsDeleteSavedTranslations();
    NSArray<SGKaraokeLine *> *lines = aiLines(@[@"line"]);
    lines[0].translationMade = YES; lines[0].translation = @"previous";
    __block BOOL completed = NO;
    SGLyricsSaveTranslationWithCompletion(@"completion-failure", @"ko", lines, ^(BOOL durable, NSError *error) {
        CHECK(durable && !error); completed = YES;
    });
    waitFor(^BOOL { return completed; });
    NSURL *blocked = [SGLyricsTestCacheRoot() URLByAppendingPathComponent:@"TranslationRecovery"];
    CHECK([@"not a directory" writeToURL:blocked atomically:YES encoding:NSUTF8StringEncoding error:nil]);
    lines[0].translation = @"visible but unsaved"; completed = NO;
    SGLyricsSaveTranslationWithCompletion(@"completion-failure", @"ko", lines, ^(BOOL durable, NSError *error) {
        CHECK(!durable && error); completed = YES;
    });
    waitFor(^BOOL { return completed; });
    NSURL *file = [SGLyricsTestCacheRoot() URLByAppendingPathComponent:@"Translations/completion-failure.ko.json"];
    NSDictionary *disk = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfURL:file] options:0 error:nil];
    CHECK([disk[@"line"] isEqual:@"previous"]);
    NSArray<SGKaraokeLine *> *visible = aiLines(@[@"line"]);
    SGLyricsSyncSavedTranslation(@"completion-failure", @"ko", visible);
    CHECK([visible[0].translation isEqual:@"visible but unsaved"]);
    SGLyricsDeleteSavedTranslations();
}
static void checkAIDeletionReadInvalidation(void) {
    SGLyricsDeleteSavedTranslations();
    SGLyricsSaveAI(@"notes", @"old-read", @"ko", @{@"line":@"old"});
    __block BOOL finished = NO;
    SGLyricsLoadSavedAI(@"notes", @"old-read", @"ko", ^(NSDictionary *answer, NSError *error) {
        CHECK(!answer && !error); finished = YES;
    });
    SGLyricsSavedAI(@"notes", @"barrier", @"ko");
    SGLyricsDeleteSavedTranslations();
    waitFor(^BOOL { return finished; });
}
static void checkAIUnrelatedSaveRead(void) {
    SGLyricsDeleteSavedTranslations();
    SGLyricsSaveAI(@"notes", @"reading-A", @"ko", @{@"line":@"answer A"});
    __block BOOL finished = NO;
    SGLyricsLoadSavedAI(@"notes", @"reading-A", @"ko", ^(NSDictionary *answer, NSError *error) {
        CHECK(!error && [answer[@"line"] isEqual:@"answer A"]); finished = YES;
    });
    SGLyricsSavedAI(@"notes", @"barrier", @"ko");
    SGLyricsSaveAI(@"notes", @"writing-B", @"ko", @{@"line":@"answer B"});
    waitFor(^BOOL { return finished; });
    SGLyricsDeleteSavedTranslations();
}
static void checkAIUnavailableStorage(void) {
    SGLyricsDeleteSavedTranslations();
    SGLyricsSaveAI(@"notes", @"unavailable-A", @"ko", @{@"line":@"saved note"});
    SGLyricsSavedAI(@"notes", @"barrier", @"ko");
    NSURL *fixture = storageFixture(), *backup = [fixture URLByAppendingPathComponent:@"AI"];
    NSURL *folder = [SGLyricsTestCacheRoot() URLByAppendingPathComponent:@"AI"];
    CHECK([NSFileManager.defaultManager moveItemAtURL:folder toURL:backup error:nil]);
    CHECK([@"unavailable" writeToURL:folder atomically:YES encoding:NSUTF8StringEncoding error:nil]);
    SGLyricsAIForgotten();
    CHECK(!SGLyricsAIValues(@"notes", @"unavailable-A", @"ko"));
    NSUInteger before = aiRequests;
    NSString *problem = nil;
    CHECK(!askAI(SGLyricsAIClaude, @"unavailable-A", @[@"line"], YES, &problem) && problem.length);
    CHECK(aiRequests == before);
    CHECK([NSFileManager.defaultManager removeItemAtURL:folder error:nil]);
    CHECK([NSFileManager.defaultManager moveItemAtURL:backup toURL:folder error:nil]);
    waitFor(^BOOL { return [SGLyricsAIValues(@"notes", @"unavailable-A", @"ko")[@"line"] isEqual:@"saved note"]; });
    problem = nil;
    CHECK(([askAI(SGLyricsAIClaude, @"unavailable-A", @[@"line"], YES, &problem) isEqual:@[@"saved note"]]));
    CHECK(!problem && aiRequests == before);
    clearFixture(fixture);
    SGLyricsDeleteSavedTranslations();
}
static void checkImportedReadInvalidation(void) {
    for (NSNumber *ai in @[@NO, @YES]) {
        SGLyricsDeleteSavedTranslations();
        NSArray<SGKaraokeLine *> *lines = aiLines(@[@"line"]), *visible = aiLines(@[@"line"]);
        lines[0].translationMade = YES; lines[0].translation = @"old";
        if (ai.boolValue) SGLyricsSaveAI(@"notes", @"import-read", @"ko", @{@"line":@"old"});
        else SGLyricsSaveTranslation(@"import-read", @"ko", lines);
        SGLyricsSavedAI(@"notes", @"barrier", @"ko");
        NSString *space = ai.boolValue ? @"AI" : @"Translations";
        NSURL *folder = [SGLyricsTestCacheRoot() URLByAppendingPathComponent:space];
        NSURL *active = [NSFileManager.defaultManager contentsOfDirectoryAtURL:folder includingPropertiesForKeys:nil options:0 error:nil].firstObject;
        CHECK(active);
        NSURL *fixture = storageFixture(), *url = [fixture URLByAppendingPathComponent:@"incoming.json"];
        fixtureJSON(url, SGTranslationEnvelope(space, active.lastPathComponent, @{@"line":@"imported"}, NO));
        __block BOOL previewed = NO, loaded = NO, imported = NO;
        SGSavedImport(url, YES, YES, ^(NSDictionary *report, NSError *error) { CHECK(report && !error); previewed = YES; });
        waitFor(^BOOL { return previewed; });
        if (ai.boolValue) SGLyricsLoadSavedAI(@"notes", @"import-read", @"ko", ^(NSDictionary *answer, NSError *error) {
            CHECK(!error && [answer[@"line"] isEqual:@"imported"]); loaded = YES;
        });
        else SGLyricsLoadTranslation(@"import-read", @"ko", visible, ^BOOL { return YES; }, ^{
            CHECK([visible[0].translation isEqual:@"imported"]); loaded = YES;
        });
        SGLyricsSavedAI(@"notes", @"barrier", @"ko");
        SGSavedImport(url, YES, NO, ^(NSDictionary *report, NSError *error) {
            CHECK(!error && [report[@"completed"] integerValue] == 1); imported = YES;
        });
        waitFor(^BOOL { return loaded && imported; });
        if (ai.boolValue) CHECK([SGLyricsSavedAI(@"notes", @"import-read", @"ko")[@"line"] isEqual:@"imported"]);
        clearFixture(fixture);
    }
    SGLyricsDeleteSavedTranslations();
}
static void checkAsyncTranslationDeletion(void) {
    SGLyricsDeleteSavedTranslations();
    NSArray<SGKaraokeLine *> *lines = aiLines(@[@"line"]);
    lines[0].translationMade = YES; lines[0].translation = @"saved";
    SGLyricsSaveTranslation(@"async-delete", @"ko", lines);
    SGLyricsSavedAI(@"notes", @"barrier", @"ko");
    NSUInteger token = SGLyricsBeginTranslation(@"async-delete", @"ko");
    storeEntered = dispatch_semaphore_create(0);
    storeRelease = dispatch_semaphore_create(0);
    holdStore = YES;
    __block BOOL heartbeat = NO, finished = NO;
    SGLyricsDeleteTranslationWithCompletion(@"async-delete", @"ko", ^(NSError *error) {
        CHECK(NSThread.isMainThread && heartbeat && !error); finished = YES;
    });
    CHECK(!SGLyricsTranslationIsCurrent(@"async-delete", @"ko", token));
    CHECK(dispatch_semaphore_wait(storeEntered, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC)) == 0);
    dispatch_async(dispatch_get_main_queue(), ^{ heartbeat = YES; dispatch_semaphore_signal(storeRelease); });
    waitFor(^BOOL { return finished; });
    SGLyricsSyncSavedTranslation(@"async-delete", @"ko", lines);
    CHECK(!lines[0].translation);
    SGLyricsDeleteSavedTranslations();
}
static void checkPreviewSurvivesUnlock(void) {
    SGLyricsDeleteSavedTranslations();
    NSURL *root = storageFixture(), *url = [root URLByAppendingPathComponent:@"incoming.json"];
    fixtureJSON(url, SGTranslationEnvelope(@"Translations", @"unlock-preview.ko.json", @{@"line":@"imported"}, NO));
    __block BOOL previewed = NO, imported = NO;
    SGSavedImport(url, NO, YES, ^(NSDictionary *report, NSError *error) { CHECK(report && !error); previewed = YES; });
    waitFor(^BOOL { return previewed; });
    [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationProtectedDataDidBecomeAvailable object:nil];
    SGSavedImport(url, NO, NO, ^(NSDictionary *report, NSError *error) {
        CHECK(!error && [report[@"completed"] integerValue] == 1); imported = YES;
    });
    waitFor(^BOOL { return imported; });
    NSArray<SGKaraokeLine *> *lines = aiLines(@[@"line"]);
    SGLyricsSyncSavedTranslation(@"unlock-preview", @"ko", lines);
    CHECK([lines[0].translation isEqual:@"imported"]);
    clearFixture(root);
    SGLyricsDeleteSavedTranslations();
}
// Runs in its own process before anything opens the store: a failed startup pass leaves abandoned
// import stages, and the next maintenance chance must still reclaim them.
static void checkStartupReclaimRetry(void) {
    NSURL *root = SGLyricsTestCacheRoot();
    CHECK([[NSData data] writeToURL:root options:0 error:nil]);
    __block BOOL listed = NO;
    SGSavedRecords(nil, ^(NSArray *records, NSString *next, NSDictionary *summary, NSString *warning) { CHECK(warning.length); listed = YES; });
    waitFor(^BOOL { return listed; });
    CHECK([NSFileManager.defaultManager removeItemAtURL:root error:nil]);
    NSURL *abandoned = [[root URLByAppendingPathComponent:@"TranslationImports"] URLByAppendingPathComponent:NSUUID.UUID.UUIDString];
    CHECK([NSFileManager.defaultManager createDirectoryAtURL:abandoned withIntermediateDirectories:YES attributes:nil error:nil]);
    [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationProtectedDataDidBecomeAvailable object:nil];
    listed = NO;
    SGSavedRecords(nil, ^(NSArray *records, NSString *next, NSDictionary *summary, NSString *warning) { CHECK(!warning); listed = YES; });
    waitFor(^BOOL { return listed; });
    CHECK(![NSFileManager.defaultManager fileExistsAtPath:abandoned.path]);
    clearFixture(root);
}
static void checkMigrationWarningPersists(void) {
    SGLyricsDeleteSavedTranslations();
    SGLyricsSavedAI(@"notes", @"barrier", @"ko");
    CHECK([NSFileManager.defaultManager removeItemAtURL:SGLyricsTestCacheRoot() error:nil]);
    NSURL *legacy = [SGLyricsTestCacheRoot() URLByAppendingPathComponent:@"Legacy/Translations/unresolved.ko.json"];
    fixtureJSON(legacy, @[@"invalid mapping"]);
    [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationProtectedDataDidBecomeAvailable object:nil];
    for (NSUInteger i = 0; i < 2; i++) {
        __block BOOL finished = NO;
        SGSavedRecords(nil, ^(NSArray *records, NSString *next, NSDictionary *summary, NSString *warning) {
            CHECK(summary && [summary[@"count"] integerValue] == 0 && warning.length);
            finished = YES;
        });
        waitFor(^BOOL { return finished; });
    }
    fixtureJSON(legacy, @{@"line":@"migrated"});
    __block BOOL retried = NO, inspected = NO;
    SGSavedRetry(^(NSError *error) { CHECK(!error); retried = YES; });
    waitFor(^BOOL { return retried; });
    SGSavedRecords(nil, ^(NSArray *records, NSString *next, NSDictionary *summary, NSString *warning) {
        CHECK(!warning && [summary[@"count"] integerValue] == 1); inspected = YES;
    });
    waitFor(^BOOL { return inspected; });
    NSArray<SGKaraokeLine *> *lines = aiLines(@[@"line"]);
    SGLyricsSyncSavedTranslation(@"unresolved", @"ko", lines);
    CHECK([lines[0].translation isEqual:@"migrated"]);
    SGLyricsDeleteSavedTranslations();
}
static void checkManagementPagination(void) {
    SGLyricsDeleteSavedTranslations();
    for (NSUInteger i = 0; i < 205; i++) SGLyricsSaveAI(@"notes", [NSString stringWithFormat:@"page-%lu", (unsigned long)i], @"ko", @{@"line":@"kept"});
    SGLyricsSavedAI(@"notes", @"barrier", @"ko");
    NSMutableSet *seen = [NSMutableSet set];
    NSString *cursor = nil;
    NSUInteger pages = 0;
    do {
        __block BOOL completed = NO;
        __block NSString *next = nil;
        SGSavedRecords(cursor, ^(NSArray *records, NSString *after, NSDictionary *summary, NSString *warning) {
            CHECK(!warning && [summary[@"count"] integerValue] == 205);
            CHECK(records.count == (pages < 2 ? 100 : 5));
            for (NSDictionary *record in records) {
                CHECK(![seen containsObject:record[@"key"]]);
                [seen addObject:record[@"key"]];
            }
            next = after; completed = YES;
        });
        waitFor(^BOOL { return completed; });
        cursor = next; pages++;
    } while (cursor);
    CHECK(pages == 3 && seen.count == 205);
    SGLyricsDeleteSavedTranslations();
}
static void checkDurableStorage(void) {
    // Startup maintenance can be the first reader, before main services queued work.
    NSURL *root = storageFixture();
    __block BOOL prepared;
    dispatch_group_t startup = dispatch_group_create();
    dispatch_group_async(startup, dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
        prepared = [fixtureStore(root) prepare:NULL];
    });
    dispatch_group_wait(startup, DISPATCH_TIME_FOREVER);
    clearFixture(root);
    CHECK(prepared);
    root = storageFixture();
    SGTranslationFiles *store = fixtureStore(root);
    CHECK([store prepare:nil]);
    flushFailureDirectory = [store.root URLByAppendingPathComponent:@"TranslationState"].path;
    flushFailureTarget = [store.root URLByAppendingPathComponent:@"TranslationState/state.json"].path;
    BOOL removed = [store removeRecords:@[] all:YES error:nil];
    flushFailureDirectory = flushFailureTarget = nil;
    NSNumber *version = [store importAuthority:nil];
    clearFixture(root);
    CHECK(!removed && [version isEqual:@1]);
    checkStorageLifecycle();
    checkStorageRetention();
    checkMigrationResume();
    checkMigrationConflict();
    checkDeletionSuppression();
    checkStoreAdmission();
    checkTransferMerge();
    checkTransferRejection();
    checkImportResume();
    checkDeletedImportAuthority();
    checkUncertainCommitRetry();
    checkDirectoryLinkDurability();
    checkImportTraversal();
    checkImportDuplicateIdentity();
    checkImportFilesystemAliases();
    checkImportAliasAfterPreview();
    checkRecoveryAliasRoundTrip();
    checkImportIgnoresRecoveryBodies();
    checkImportAliasLookupBound();
    checkImportStagingLifecycle();
    checkSessionExportUnavailableStore();
    checkImportExpansionBound();
    checkSaveCompletionFailure();
    checkAIDeletionReadInvalidation();
    checkAIUnrelatedSaveRead();
    checkAIUnavailableStorage();
    checkImportedReadInvalidation();
    checkAsyncTranslationDeletion();
    checkPreviewSurvivesUnlock();
    checkMigrationWarningPersists();
    checkManagementPagination();
    puts("Durable JSON storage: retention, migration, recovery, suppression, admission and transfers passed");
}
