// Checks LocalAudioImport.m as the tweak compiles it: a taken name gets a number and is never overwritten,
// a copy leaves the original, only what Retrine imported is listed, and a delete touches only a listed file.
// Runs in a folder and a defaults suite of its own under the home it is given.
#import "Shared/LocalFiles/LocalAudioImport.h"
#import "../harness-fail.h"

static NSFileManager *files;

static void put(NSURL *url, NSString *text) {
    HARNESS_CHECK([text writeToURL:url atomically:YES encoding:NSUTF8StringEncoding error:nil]);
}

static NSString *text(NSURL *url) {
    return [NSString stringWithContentsOfURL:url encoding:NSUTF8StringEncoding error:nil];
}

static NSURL *makeDirectory(NSURL *parent, NSString *name) {
    NSURL *url = [parent URLByAppendingPathComponent:name isDirectory:YES];
    HARNESS_CHECK([files createDirectoryAtURL:url withIntermediateDirectories:YES attributes:nil error:nil]);
    return url;
}

#define EXPECT_EQ(actual, expected) do { id a = (actual), e = (expected); \
    if (!(a == e || [a isEqual:e])) HARNESS_FAIL(@"%s = %@, expected %@", #actual, a, e); } while (0)

int main(int argc, char **argv) {
    @autoreleasepool {
        files = NSFileManager.defaultManager;
        NSURL *root = [NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[1]] isDirectory:YES];
        [files removeItemAtURL:root error:nil];
        NSURL *documents = makeDirectory(root, @"Documents");
        NSURL *picked = makeDirectory(root, @"picked");
        NSURL *other = makeDirectory(root, @"other");
        NSString *suite = @"retrine.local-audio-check";
        [NSUserDefaults.standardUserDefaults removePersistentDomainForName:suite];
        NSUserDefaults *store = [[NSUserDefaults alloc] initWithSuiteName:suite];

        // Name numbering.
        EXPECT_EQ(SGLocalAudioNumberedName(@"a.mp3", 1), @"a.mp3");
        EXPECT_EQ(SGLocalAudioNumberedName(@"a.mp3", 2), @"a 2.mp3");
        EXPECT_EQ(SGLocalAudioNumberedName(@"a.mp3", 10), @"a 10.mp3");
        EXPECT_EQ(SGLocalAudioNumberedName(@"a", 3), @"a 3");
        EXPECT_EQ(SGLocalAudioNumberedName(@"x.tar.gz", 2), @"x.tar 2.gz");

        // A file the user put there is never overwritten: the import takes the next number.
        put([documents URLByAppendingPathComponent:@"song.mp3"], @"USER");
        put([documents URLByAppendingPathComponent:@"keep.mp3"], @"USER KEEP");
        put([picked URLByAppendingPathComponent:@"song.mp3"], @"NEW ONE");
        put([picked URLByAppendingPathComponent:@"fresh.m4a"], @"FRESH");
        NSArray<NSString *> *failed = nil;
        NSArray<NSString *> *imported = SGLocalAudioImport(@[[picked URLByAppendingPathComponent:@"song.mp3"]], documents, store, &failed);
        EXPECT_EQ(imported, (@[@"song 2.mp3"]));
        EXPECT_EQ(failed, @[]);
        EXPECT_EQ(text([documents URLByAppendingPathComponent:@"song.mp3"]), @"USER");
        EXPECT_EQ(text([documents URLByAppendingPathComponent:@"song 2.mp3"]), @"NEW ONE");
        // Copy, never move.
        EXPECT_EQ(text([picked URLByAppendingPathComponent:@"song.mp3"]), @"NEW ONE");

        // The same file again, and two of one name in one pick, each get the next free number.
        put([other URLByAppendingPathComponent:@"song.mp3"], @"OTHER");
        imported = SGLocalAudioImport(@[[picked URLByAppendingPathComponent:@"song.mp3"], [other URLByAppendingPathComponent:@"song.mp3"],
                                        [picked URLByAppendingPathComponent:@"fresh.m4a"]], documents, store, &failed);
        EXPECT_EQ(imported, (@[@"song 3.mp3", @"song 4.mp3", @"fresh.m4a"]));
        EXPECT_EQ(text([documents URLByAppendingPathComponent:@"song 3.mp3"]), @"NEW ONE");
        EXPECT_EQ(text([documents URLByAppendingPathComponent:@"song 4.mp3"]), @"OTHER");
        EXPECT_EQ(text([documents URLByAppendingPathComponent:@"song.mp3"]), @"USER");

        // A file that cannot be copied is named, and the rest of the pick still comes in.
        imported = SGLocalAudioImport(@[[picked URLByAppendingPathComponent:@"missing.mp3"], [other URLByAppendingPathComponent:@"song.mp3"]],
                                      documents, store, &failed);
        EXPECT_EQ(failed, (@[@"missing.mp3"]));
        EXPECT_EQ(imported, (@[@"song 5.mp3"]));
        HARNESS_CHECK(![files fileExistsAtPath:[documents URLByAppendingPathComponent:@"missing.mp3"].path]);

        // Only what was imported is listed, never the user's own files.
        NSArray<NSString *> *expected = @[@"song 2.mp3", @"song 3.mp3", @"song 4.mp3", @"fresh.m4a", @"song 5.mp3"];
        EXPECT_EQ(SGLocalAudioImportedNames(documents, store), expected);

        // A file the user removed leaves the list, in the defaults too.
        HARNESS_CHECK([files removeItemAtURL:[documents URLByAppendingPathComponent:@"song 3.mp3"] error:nil]);
        expected = @[@"song 2.mp3", @"song 4.mp3", @"fresh.m4a", @"song 5.mp3"];
        EXPECT_EQ(SGLocalAudioImportedNames(documents, store), expected);
        EXPECT_EQ([[store arrayForKey:SGKeyLocalAudioImported] valueForKey:@"name"], expected);
        // A folder or a link under a listed name is not the imported file.
        HARNESS_CHECK([files removeItemAtURL:[documents URLByAppendingPathComponent:@"song 5.mp3"] error:nil]);
        makeDirectory(documents, @"song 5.mp3");
        HARNESS_CHECK([files removeItemAtURL:[documents URLByAppendingPathComponent:@"fresh.m4a"] error:nil]);
        HARNESS_CHECK([files createSymbolicLinkAtURL:[documents URLByAppendingPathComponent:@"fresh.m4a"] withDestinationURL:[documents URLByAppendingPathComponent:@"keep.mp3"] error:nil]);
        expected = @[@"song 2.mp3", @"song 4.mp3"];
        EXPECT_EQ(SGLocalAudioImportedNames(documents, store), expected);

        // Delete: only a listed file, and the user's own files stay.
        HARNESS_CHECK(!SGLocalAudioDelete(@"song.mp3", documents, store));
        HARNESS_CHECK(!SGLocalAudioDelete(@"keep.mp3", documents, store));
        HARNESS_CHECK(!SGLocalAudioDelete(@"../picked/song.mp3", documents, store));
        EXPECT_EQ(text([documents URLByAppendingPathComponent:@"song.mp3"]), @"USER");
        EXPECT_EQ(text([documents URLByAppendingPathComponent:@"keep.mp3"]), @"USER KEEP");
        EXPECT_EQ(text([picked URLByAppendingPathComponent:@"song.mp3"]), @"NEW ONE");
        HARNESS_CHECK(SGLocalAudioDelete(@"song 2.mp3", documents, store));
        HARNESS_CHECK(![files fileExistsAtPath:[documents URLByAppendingPathComponent:@"song 2.mp3"].path]);
        EXPECT_EQ(SGLocalAudioImportedNames(documents, store), (@[@"song 4.mp3"]));
        EXPECT_EQ(text([documents URLByAppendingPathComponent:@"song 4.mp3"]), @"OTHER");
        // Deleting it twice finds it unlisted.
        HARNESS_CHECK(!SGLocalAudioDelete(@"song 2.mp3", documents, store));

        // A file already gone: nothing to delete, and the entry goes.
        HARNESS_CHECK([files removeItemAtURL:[documents URLByAppendingPathComponent:@"song 4.mp3"] error:nil]);
        HARNESS_CHECK(SGLocalAudioDelete(@"song 4.mp3", documents, store));
        EXPECT_EQ([store arrayForKey:SGKeyLocalAudioImported] ?: @[], (@[]));

        // The name taken by another thing after the import. Each import is listed, then the file at its name is
        // swapped; the swapped thing must never be listed, deleted or changed.
        NSURL *swapSource = [picked URLByAppendingPathComponent:@"swap.mp3"];
        put(swapSource, @"IMPORTED");
        for (NSString *kind in @[@"regular file", @"regular file during the confirmation", @"folder with contents", @"folder during the confirmation", @"link"]) {
            BOOL during = [kind containsString:@"during"];
            NSString *name = SGLocalAudioNumberedName(@"swap.mp3", 1);
            [files removeItemAtURL:[documents URLByAppendingPathComponent:name] error:nil];
            imported = SGLocalAudioImport(@[swapSource], documents, store, &failed);
            EXPECT_EQ(imported, (@[name]));
            if (during) EXPECT_EQ(SGLocalAudioImportedNames(documents, store), (@[name]));   // listed, the page is showing it
            NSURL *url = [documents URLByAppendingPathComponent:name];
            HARNESS_CHECK([files removeItemAtURL:url error:nil]);
            if ([kind hasPrefix:@"regular"]) {
                put(url, @"USER REPLACEMENT");
            } else if ([kind hasPrefix:@"folder"]) {
                makeDirectory(documents, name);
                put([url URLByAppendingPathComponent:@"inside.mp3"], @"INSIDE");
            } else {
                HARNESS_CHECK([files createSymbolicLinkAtURL:url withDestinationURL:[documents URLByAppendingPathComponent:@"keep.mp3"] error:nil]);
            }
            if (!during) EXPECT_EQ(SGLocalAudioImportedNames(documents, store), (@[]));
            HARNESS_CHECK(!SGLocalAudioDelete(name, documents, store));
            EXPECT_EQ([store arrayForKey:SGKeyLocalAudioImported] ?: @[], (@[]));
            if ([kind hasPrefix:@"regular"]) EXPECT_EQ(text(url), @"USER REPLACEMENT");
            if ([kind hasPrefix:@"folder"]) EXPECT_EQ(text([url URLByAppendingPathComponent:@"inside.mp3"]), @"INSIDE");
            if ([kind isEqualToString:@"link"]) HARNESS_CHECK([files destinationOfSymbolicLinkAtPath:url.path error:nil] != nil);
            EXPECT_EQ(text([documents URLByAppendingPathComponent:@"keep.mp3"]), @"USER KEEP");
            [files removeItemAtURL:url error:nil];
        }
        // The import itself, unchanged, still deletes.
        imported = SGLocalAudioImport(@[swapSource], documents, store, &failed);
        HARNESS_CHECK(SGLocalAudioDelete(imported.firstObject, documents, store));
        HARNESS_CHECK(![files fileExistsAtPath:[documents URLByAppendingPathComponent:imported.firstObject].path]);

        [store removePersistentDomainForName:suite];
        [files removeItemAtURL:root error:nil];
        printf("local audio import: ok\n");
    }
    return 0;
}
