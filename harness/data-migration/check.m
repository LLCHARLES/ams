#import "Core/SGDataRoot.h"
#import "Core/TranslationStore/SGTranslationFiles.h"
#import "Shared/AudioEffects/AudioEffects.h"
#import "Shared/AudioEffects/AudioEffectsPresets.h"
#import "Shared/ListeningStats/SGPlayLog.h"
#import "Shared/LocalFiles/LyricRetirement.h"
#import "App/About/ReportFolder.h"
#import <sys/stat.h>
#import <unistd.h>

#define CHECK(...) do { if (!(__VA_ARGS__)) { NSLog(@"FAIL %s:%d: %s", __FILE__, __LINE__, #__VA_ARGS__); exit(1); } } while (0)
void SGDSPApply(NSString *effect) {} // codec without an audio engine
static NSFileManager *fm(void) { return NSFileManager.defaultManager; }
static NSURL *child(NSURL *url, NSString *path) { return [url URLByAppendingPathComponent:path]; }
static NSURL *base(NSSearchPathDirectory dir) {
    NSURL *url = [fm() URLsForDirectory:dir inDomains:NSUserDomainMask].firstObject;
    NSString *home = @(getenv("CFFIXED_USER_HOME")).stringByResolvingSymlinksInPath;
    CHECK([url.path.stringByResolvingSymlinksInPath hasPrefix:[home stringByAppendingString:@"/"]]);
    return url;
}
static BOOL exists(NSURL *url) { return [fm() fileExistsAtPath:url.path]; }
static void mkdirs(NSURL *url) { CHECK([fm() createDirectoryAtURL:url withIntermediateDirectories:YES attributes:nil error:nil]); }
static NSData *bytes(NSString *s) { return [s dataUsingEncoding:NSUTF8StringEncoding]; }
static void put(NSURL *url, NSString *s) {
    mkdirs(url.URLByDeletingLastPathComponent);
    CHECK([bytes(s) writeToURL:url options:NSDataWritingWithoutOverwriting error:nil]);
}
static void expect(NSURL *url, NSString *s) {
    if (![[NSData dataWithContentsOfURL:url] isEqual:bytes(s)]) { NSLog(@"FAIL bytes at %@", url.path); exit(1); }
}
static NSURL *active(NSSearchPathDirectory dir, NSString *name) {
    NSURL *root = SGDataRoot(dir);
    CHECK([root.path isEqual:child(base(dir), name).path]);
    return root;
}
static BOOL race;
int SGFixtureRename(const char *old, const char *new, unsigned flags) {
    if (race) {
        race = NO;
        put(child([NSURL fileURLWithPath:@(new)], @"winner"), @"competing writer");
    }
    return renamex_np(old, new, flags);
}

// These fixtures are from the old writers, not the new writers with the format field edited.
static void exports(void) {
    SGHistoryImport *history = SGReadHistoryURLs(@[[NSURL fileURLWithPath:@"fixtures/Vitrine-listening-history.json"]]);
    SGPlay *p = history.plays.firstObject;
    CHECK(history.plays.count == 1 && p.exactImport && p.ms == 1234 && p.end == 1700000000 &&
          [p.uri isEqual:@"spotify:track:one"] && [p.title isEqual:@"Old song"] && [p.artist isEqual:@"Artist"] && [p.album isEqual:@"Album"]);
    NSData *output = SGHistoryJSON(history.plays, nil);
    CHECK([[NSJSONSerialization JSONObjectWithData:output options:0 error:nil][@"format"] isEqual:@"retrine.listening-history"]);
    CHECK(SGPlaysFromExport(output).firstObject.exactImport);
    NSString *name = nil, *filename = nil;
    NSDictionary *values = SGDSPReadPresetFile([NSData dataWithContentsOfFile:@"fixtures/Late night.vitrine-preset.json"], nil, &name, nil);
    CHECK([name isEqual:@"Late night"] && [values isEqual:@{SGKeyDSPBass:@YES, SGKeyDSPBassGain:@9}]);
    SGDSPSaveUserPresetValues(name, values);
    output = SGDSPPresetFileData(name, &filename);
    CHECK([filename isEqual:@"Late night.retrine-preset.json"] &&
          [[NSJSONSerialization JSONObjectWithData:output options:0 error:nil][@"format"] isEqual:@"retrine.audio-preset"]);
    CHECK([SGDSPReadPresetFile(output, nil, nil, nil) isEqual:values]);
}

static const NSSearchPathDirectory dirs[] = {NSDocumentDirectory, NSApplicationSupportDirectory, NSCachesDirectory};
static void roots(NSString *test, BOOL first) {
    for (unsigned i = 0; i < 3; i++) {
        NSSearchPathDirectory dir = dirs[i];
        NSURL *parent = base(dir), *old = child(parent, @"Vitrine"), *new = child(parent, @"Retrine");
        if ([test isEqual:@"fresh"]) {
            CHECK(!exists(active(dir, @"Retrine")) && !exists(old));
        } else if ([test isEqual:@"both"]) {
            if (first) {
                put(child(old, @"same"), @"old"); put(child(new, @"same"), @"new");
                put(child(old, @"unique/item"), @"only old");
            }
            active(dir, @"Retrine");
            expect(child(old, @"same"), @"old"); expect(child(old, @"unique/item"), @"only old");
            CHECK(!exists(child(new, @"unique")));
            if (first) {
                expect(child(new, @"same"), @"new");
                CHECK([fm() removeItemAtURL:new error:nil]);
            } else CHECK(!exists(new)); // erased active tree is not recreated from a retired tree
        } else if ([test isEqual:@"recreated"]) {
            if (first) {
                put(child(old, @"mine"), @"original library");
                expect(child(active(dir, @"Retrine"), @"mine"), @"original library");
                put(child(old, @"later"), @"later Files save");
                CHECK([fm() removeItemAtURL:new error:nil]);
            } else {
                CHECK(!exists(active(dir, @"Retrine")));
                expect(child(old, @"later"), @"later Files save");
            }
        } else if ([test isEqual:@"denied"]) {
            put(child(old, @"mine"), @"not missing");
            CHECK(!chmod(parent.fileSystemRepresentation, 0000));
            NSURL *answer = SGDataRoot(dir);
            NSString *library = dir == NSDocumentDirectory ? SGDSPLibraryDirectory(SGDSPFileDDC) : nil;
            CHECK(!chmod(parent.fileSystemRepresentation, 0700));
            CHECK(!library && !answer && !exists(new)); expect(child(old, @"mine"), @"not missing");
        } else if ([test isEqual:@"invalid"]) {
            mkdirs(parent);
            if (i == 0) CHECK(!symlink("missing", old.fileSystemRepresentation));
            if (i == 1) put(new, @"not a directory");
            if (i == 2) { mkdirs(old); CHECK(!symlink("Vitrine", new.fileSystemRepresentation)); }
            CHECK(!SGDataRoot(dir));
        } else {
            BOOL pinned = [test isEqual:@"pinned"] && first;
            if (first) {
                put(child(old, @"nested/user.data"), @"untouched");
                CHECK([child(old, @"nested") setResourceValue:@YES forKey:NSURLIsExcludedFromBackupKey error:nil]);
                if (pinned) CHECK(!chflags(old.fileSystemRepresentation, UF_IMMUTABLE));
            }
            struct stat before, after;
            if (first) CHECK(!lstat(old.fileSystemRepresentation, &before));
            NSURL *root = SGDataRoot(dir);
            if (pinned) CHECK(!chflags(old.fileSystemRepresentation, 0));
            CHECK([root.path isEqual:(pinned ? old : new).path]);
            if (first) CHECK(!lstat(root.fileSystemRepresentation, &after) && before.st_ino == after.st_ino);
            if (pinned) {
                active(dir, @"Vitrine"); // rename would now succeed, but callers must keep the same root
                put(child(root, @"after-failure"), @"writer");
                CHECK(!exists(new));
            } else {
                CHECK(!exists(old));
                if ([test isEqual:@"pinned"]) expect(child(root, @"after-failure"), @"writer");
            }
            expect(child(root, @"nested/user.data"), @"untouched");
            NSNumber *excluded = nil;
            CHECK([child(root, @"nested") getResourceValue:&excluded forKey:NSURLIsExcludedFromBackupKey error:nil] && excluded.boolValue);
        }
    }
}

@interface Editor : NSObject <NSFilePresenter>
@property(nonatomic, copy) NSURL *presentedItemURL;
@property(nonatomic, strong) NSOperationQueue *presentedItemOperationQueue;
@property(atomic) BOOL deletionRequested;
@end
@implementation Editor
- (void)accommodatePresentedItemDeletionWithCompletionHandler:(void (^)(NSError *))done {
    self.deletionRequested = YES; done(nil);
}
@end

static void presenter(BOOL first) {
    NSURL *old = child(base(NSDocumentDirectory), @"Vitrine/Lyrics/song.lrc");
    if (first) {
        put(old, @"song");
        Editor *editor = [Editor new]; editor.presentedItemURL = old; editor.presentedItemOperationQueue = [NSOperationQueue new];
        [NSFileCoordinator addFilePresenter:editor];
        dispatch_semaphore_t held = dispatch_semaphore_create(0), release = dispatch_semaphore_create(0), finished = dispatch_semaphore_create(0);
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            [[[NSFileCoordinator alloc] initWithFilePresenter:editor] coordinateWritingItemAtURL:old options:0 error:nil byAccessor:^(NSURL *url) {
                NSFileHandle *handle = [NSFileHandle fileHandleForWritingToURL:url error:nil]; CHECK(handle);
                dispatch_semaphore_signal(held);
                CHECK(!dispatch_semaphore_wait(release, dispatch_time(DISPATCH_TIME_NOW, 5*NSEC_PER_SEC)));
                [handle seekToEndOfFile]; [handle writeData:bytes(@" edited")]; [handle closeFile];
                put(url, @"later save to previous path");
                dispatch_semaphore_signal(finished);
            }];
        });
        CHECK(!dispatch_semaphore_wait(held, dispatch_time(DISPATCH_TIME_NOW, 5*NSEC_PER_SEC)));
        CHECK(NSThread.isMainThread);
        active(NSDocumentDirectory, @"Retrine"); // must return before the editor relinquishes
        dispatch_semaphore_signal(release);
        CHECK(!dispatch_semaphore_wait(finished, dispatch_time(DISPATCH_TIME_NOW, 5*NSEC_PER_SEC)));
        [NSFileCoordinator removeFilePresenter:editor];
    }
    NSURL *lyrics = child(active(NSDocumentDirectory, @"Retrine"), @"Lyrics");
    expect(child(lyrics, @"song.lrc"), @"song edited"); expect(old, @"later save to previous path");
    if (first) {
        BOOL removed; NSDictionary *proof = nil;
        CHECK(SGRemoveRetiredLyric(lyrics, @"song.lrc", &removed) && !removed);
        NSURL *file = child(lyrics, @"own.lrc");
        CHECK(SGWriteImportedLyric(@"original", file, &proof, nil) && proof);
        CHECK([bytes(@"Files replacement") writeToURL:file atomically:YES]);
        Editor *editor = [Editor new]; editor.presentedItemURL = file; editor.presentedItemOperationQueue = [NSOperationQueue new];
        [NSFileCoordinator addFilePresenter:editor];
        CHECK(SGRemoveRetiredLyric(lyrics, proof, &removed) && !removed && !editor.deletionRequested);
        [NSFileCoordinator removeFilePresenter:editor];
        expect(file, @"Files replacement");
        CHECK(SGWriteImportedLyric(@"retired", child(lyrics, @"another.lrc"), &proof, nil));
        CHECK(SGRemoveRetiredLyric(lyrics, proof, &removed) && removed);
    }
}

static void translations(BOOL first) {
    NSURL *previous = child(base(NSCachesDirectory), @"Vitrine"), *current = child(base(NSCachesDirectory), @"Retrine");
    NSString *record = @"{\"key\":\"old.json\",\"lines\":{\"line\":\"kept\"},\"namespace\":\"AI\",\"recovery\":true,\"type\":\"vitrine.saved-record\",\"version\":1}";
    NSString *recovery = @"TranslationRecovery/aaf5b00e5b818fa6b81904edc4934ee22f8b16f4fd3970829e9ccaef23018b5b.json";
    if (first) {
        put(child(child(base(NSApplicationSupportDirectory), @"Vitrine"), recovery), record);
        put(child(previous, @"Translations/both.json"), @"{\"old\":\"leftover\"}");
        put(child(current, @"Translations/both.json"), @"{\"new\":\"current\"}");
    }
    NSURL *root = active(NSApplicationSupportDirectory, @"Retrine");
    SGTranslationFiles *store = [[SGTranslationFiles alloc] initWithRoot:root renamedCache:active(NSCachesDirectory, @"Retrine")];
    NSError *error = nil;
    CHECK([store migrate:&error]); expect(child(root, recovery), record);
    __block BOOL recovered = NO;
    CHECK([store enumerateRecords:^BOOL(NSDictionary *d, NSError **e) {
        if ([d[@"recovery"] boolValue]) recovered = [[store record:d error:e][@"lines"] isEqual:@{@"line":@"kept"}];
        return YES;
    } includeRecovery:YES error:&error] && recovered);
    NSDictionary *map = [store read:@"Translations" key:@"both.json" error:&error];
    CHECK(!error);
    if (first) {
        CHECK([map isEqual:@{@"old":@"leftover", @"new":@"current"}]);
        CHECK([store removeRecords:@[SGTranslationEnvelope(@"Translations", @"both.json", @{}, NO)] all:NO error:&error]);
    } else CHECK(!map);
    expect(child(previous, @"Translations/both.json"), @"{\"old\":\"leftover\"}");
}

int main(int argc, const char *argv[]) { @autoreleasepool {
    CHECK(argc == 3 && getenv("CFFIXED_USER_HOME"));
    NSString *test = @(argv[1]); BOOL first = !strcmp(argv[2], "first");
    if ([test isEqual:@"presenter"]) presenter(first);
    else if ([test isEqual:@"translations"]) translations(first);
    else if ([test isEqual:@"race"]) {
        NSURL *old = child(base(NSDocumentDirectory), @"Vitrine");
        put(child(old, @"mine"), @"original"); race = YES;
        expect(child(active(NSDocumentDirectory, @"Retrine"), @"winner"), @"competing writer"); expect(child(old, @"mine"), @"original");
        put(child(base(NSApplicationSupportDirectory), @"Vitrine/other"), @"independent");
        expect(child(active(NSApplicationSupportDirectory, @"Retrine"), @"other"), @"independent");
    } else {
        roots(test, first);
        if ([test isEqual:@"fresh"]) {
            exports();
            NSURL *reports = child(active(NSApplicationSupportDirectory, @"Retrine"), @"Reports");
            put(reports, @"blocked"); CHECK(!SGCreateReportFolder(reports)); CHECK([fm() removeItemAtURL:reports error:nil]);
            NSURL *folder = SGCreateReportFolder(reports); CHECK(folder); put(child(folder, @"report.json"), @"retry text");
        }
        if ([test isEqual:@"pinned"] && first) {
            NSURL *cache = active(NSCachesDirectory, @"Vitrine");
            put(child(cache, @"Translations/bad.json"), @"bad");
            SGTranslationFiles *store = [[SGTranslationFiles alloc] initWithRoot:active(NSApplicationSupportDirectory, @"Vitrine") renamedCache:cache];
            CHECK(![store migrate:nil] && store.unresolved.count == 1);
        }
    }
    printf("ok %s %s\n", argv[1], argv[2]); return 0;
} }
