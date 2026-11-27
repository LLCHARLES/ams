#import "../../tweak/Sources/Shared/Lossless/SGLosslessStore.m"

#define CHECK(expr) do { if (!(expr)) { fprintf(stderr, "FAIL: %s\n", #expr); return 1; } } while (0)
int main(int argc, char **argv) {
    @autoreleasepool {
        NSString *directory = @(argv[1]);
        NSString *path = [directory stringByAppendingPathComponent:@"one.m4a"];
        NSString *replacement = [directory stringByAppendingPathComponent:@"two.m4a"];
        NSDate *mtime = [NSFileManager.defaultManager attributesOfItemAtPath:path error:nil].fileModificationDate;
        __weak NSDictionary *old;
        @autoreleasepool {
            NSDictionary *first = tags(path);
            CHECK([first[@"title"] isEqual:@"First"] && tags(path) == first);
            old = first;
        }
        CHECK(!rename(replacement.fileSystemRepresentation, path.fileSystemRepresentation));
        CHECK([NSFileManager.defaultManager setAttributes:@{NSFileModificationDate:mtime} ofItemAtPath:path error:nil]);
        CHECK([tags(path)[@"title"] isEqual:@"Second"] && !old);
        NSHashTable *live = [NSHashTable hashTableWithOptions:NSPointerFunctionsWeakMemory | NSPointerFunctionsObjectPointerPersonality];
        for (NSUInteger i = 0; i < 400; i++) @autoreleasepool {
            NSString *alias = [directory stringByAppendingPathComponent:[NSString stringWithFormat:@"%zu.m4a", i]];
            CHECK([NSFileManager.defaultManager linkItemAtPath:path toPath:alias error:nil]);
            [live addObject:tags(alias)];
        }
        CHECK(live.allObjects.count <= 256);
        puts("PASS tag replacement, generation retirement and bounded retention");
        return 0;
    }
}
