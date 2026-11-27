#import <Foundation/Foundation.h>
#import "Redesigned/Album/AlbumSpotifyCounts.h"
#import "Core/SGPrefs.h"

BOOL SGRPageFullCover(NSString *key);
static NSString *const album = @"spotify:album:0000000000000000000001";
static NSString *const one = @"spotify:track:0000000000000000000001";
static NSString *const two = @"spotify:track:0000000000000000000002";
static NSString *const missing = @"spotify:track:0000000000000000000003";
static NSString *const albumKey = @"spotifyglass.redesign.album.fullCover";
static NSString *const playlistKey = @"spotifyglass.redesign.playlist.fullCover";
static NSString *const legacyKey = @"spotifyglass.redesign.fullBleedCovers";
static NSString *const migratedKey = @"spotifyglass.redesign.fullBleedCovers.migrated";
static NSUInteger checks;

static void check(BOOL ok, NSString *why) {
    if (!ok) { fprintf(stderr, "FAIL %s\n", why.UTF8String); exit(1); }
    checks++;
}
static void waitFor(BOOL (^finished)(void)) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:45];
    while (!finished() && deadline.timeIntervalSinceNow > 0)
        [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.001]];
    check(finished(), @"asynchronous result completed");
}
static NSData *json(id value) {
    return [NSJSONSerialization dataWithJSONObject:value options:0 error:nil];
}
static NSData *metadata(void) {
    return json(@{@"disc": @[
        @{@"track": @[@{@"uri": one}, @{@"gid": @"00000000000000000000000000000002"}]},
        @{@"track": @[@{@"uri": one}, @{@"uri": missing}]}]});
}
static SGPBField *entry(NSString *uri, NSData *payload, NSUInteger status) {
    NSData *any = SGPBSerialize(@[SGPBString(1, @"fixture.PlayCount"), SGPBBytes(2, payload)]);
    return SGPBBytes(3, SGPBSerialize(@[SGPBBytes(1, SGPBSerialize(@[SGPBVarint(1, status)])),
        SGPBString(2, uri), SGPBBytes(3, any)]));
}
static NSData *replyWith(NSArray *entries, NSUInteger kind) {
    return SGPBSerialize(@[SGPBBytes(2, SGPBSerialize([@[SGPBVarint(2, kind)] arrayByAddingObjectsFromArray:entries]))]);
}
static NSData *reply(void) {
    // Independent literal wire bytes: field 3 = 12,345; field 3 -> field 1 = 300.
    const uint8_t scalar[] = {0x18, 0xb9, 0x60}, wrapped[] = {0x1a, 0x03, 0x08, 0xac, 0x02};
    return replyWith(@[entry(one, [NSData dataWithBytes:scalar length:sizeof(scalar)], 200),
                       entry(two, [NSData dataWithBytes:wrapped length:sizeof(wrapped)], 200)], 185);
}
// The live transport must not run in a fixture-only check.
dispatch_block_t SGSpotifyMetadataRequest(NSString *path, NSData *body, SGSpotifyMetadataReply done) {
    check(NO, @"no live transport");
    return ^{};
}
static NSDictionary *load(SGRAlbumCountsStore *store, NSString *uri) {
    __block BOOL ready = NO;
    __block NSDictionary *result;
    [store loadAlbum:uri completion:^(NSDictionary *counts) {
        check(NSThread.isMainThread, @"results delivered on main");
        result = counts;
        ready = YES;
    }];
    waitFor(^BOOL{ return ready; });
    return result;
}
static void coverChecks(void) {
    NSUserDefaults *prefs = NSUserDefaults.standardUserDefaults;
    for (NSString *key in @[albumKey, playlistKey, legacyKey, migratedKey, SGKeyStock]) [prefs removeObjectForKey:key];
    SGPrefsChanged();
    check(!SGRPageFullCover(albumKey) && SGRPageFullCover(playlistKey), @"fresh install: album card, playlist full screen");
    for (NSNumber *old in @[@NO, @YES]) {
        [prefs removeObjectForKey:migratedKey];
        [prefs removeObjectForKey:albumKey]; [prefs removeObjectForKey:playlistKey];
        [prefs setObject:old forKey:legacyKey]; SGPrefsChanged();
        check(SGRPageFullCover(albumKey) == old.boolValue && SGRPageFullCover(playlistKey) == old.boolValue,
              @"both choices inherit the legacy layout");
        check([[prefs objectForKey:legacyKey] isEqual:old] && [prefs boolForKey:migratedKey],
              @"rollback data retained with a separate migration marker");
        SGSetEnabled(albumKey, !old.boolValue);
        check(SGRPageFullCover(albumKey) != old.boolValue && SGRPageFullCover(playlistKey) == old.boolValue,
              @"later edits do not replay migration");
    }
    [prefs removeObjectForKey:migratedKey];
    [prefs setObject:@NO forKey:legacyKey]; SGSetEnabled(albumKey, YES); [prefs removeObjectForKey:playlistKey];
    check(SGRPageFullCover(albumKey) && !SGRPageFullCover(playlistKey), @"migration preserves an already-chosen page");
    for (int a = 0; a < 2; a++) for (int p = 0; p < 2; p++) {
        SGSetInt(albumKey, a); SGSetInt(playlistKey, p);
        check(SGRPageFullCover(albumKey) == a && SGRPageFullCover(playlistKey) == p, @"four independent cover combinations");
    }
    [prefs removeObjectForKey:playlistKey];
    [prefs setObject:@NO forKey:legacyKey];
    SGPrefsChanged();
    check(SGRPageFullCover(playlistKey), @"retained rollback data is inert even when a destination is absent");
    for (NSString *key in @[albumKey, playlistKey, legacyKey, migratedKey]) [prefs removeObjectForKey:key];
    SGSetEnabled(SGKeyStock, YES);
    check(!SGRPageFullCover(albumKey) && !SGRPageFullCover(playlistKey), @"reset preserves stock fallback");
    [prefs removeObjectForKey:SGKeyStock]; SGPrefsChanged();
}
int main(void) {
    @autoreleasepool {
        coverChecks();
        check([SGSpotifyAlbumMetadataPath(album) isEqual:@"/metadata/4/album/00000000000000000000000000000001?market=from_token"], @"album base62 converted to 128-bit GID");
        check(!SGSpotifyAlbumMetadataPath(@"spotify:album:ZZZZZZZZZZZZZZZZZZZZZZ"), @"overflowing identity rejected");
        check(!SGSpotifyAlbumMetadataPath(one), @"a track cannot stand in for an album");
        check([SGRAlbumMetadataTracks(metadata()) isEqual:@[one, two, missing]], @"multi-disc and repeated tracks normalize by URI/GID");
        SGRAlbumTrackIndex *index = [SGRAlbumTrackIndex fromMetadata:json(@{@"disc": @[
            @{@"track": @[@{@"uri": one, @"name": @"Shared", @"available": @NO},
                         @{@"uri": two, @"name": @"Unique"}]},
            @{@"track": @[@{@"uri": missing, @"name": @"Shared"}]}]})];
        check([[index numberForURI:one title:nil] isEqual:@1] && [[index numberForURI:two title:nil] isEqual:@2] &&
              [[index numberForURI:missing title:nil] isEqual:@1], @"greyed rows count; disc position restarts");
        check([[index numberForURI:nil title:@"Unique"] isEqual:@2] && ![index numberForURI:nil title:@"Shared"] &&
              ![index numberForURI:@"spotify:track:0000000000000000000004" title:@"Unique"],
              @"only a missing URI and a unique title can use title fallback");
        check(![[SGRAlbumTrackIndex fromMetadata:metadata()] numberForURI:one title:nil],
              @"ambiguous URI never picks a disc");
        check(!SGRAlbumMetadataTracks(json(@{@"disc": @[@{@"track": @[@{@"uri": one, @"gid": @"00000000000000000000000000000002"}]}]})),
              @"conflicting identities rejected");
        check(!SGRAlbumMetadataTracks(json(@{@"disc": @"wrong"})), @"malformed album response rejected");
        NSMutableArray *tooMany = [NSMutableArray array];
        for (NSUInteger i = 0; i < 501; i++) [tooMany addObject:@{@"uri": [NSString stringWithFormat:@"spotify:track:%022lu", (unsigned long)i]}];
        check(!SGRAlbumMetadataTracks(json(@{@"disc": @[@{@"track": tooMany}]})), @"album request budget refuses more than 500 tracks");
        NSDictionary *counts = SGRAlbumCountsInReply(reply(), @[one, two, missing]);
        check([counts isEqual:@{one: @12345, two: @300}], @"count kind 185 field 3 and wrapped 3.1 decode without inventing missing counts");
        check(!SGRAlbumCountsInReply(nil, @[one]), @"absent reply is unavailable");
        const uint8_t zero[] = {0x18, 0}, malformed[] = {0x1a, 0x80};
        check([SGRAlbumCountsInReply(replyWith(@[entry(one, [NSData dataWithBytes:zero length:2], 200)], 185), @[one])[one] isEqual:@0],
              @"explicit zero is distinct from unavailable");
        check(!SGRAlbumCountsInReply(replyWith(@[entry(one, [NSData dataWithBytes:malformed length:2], 200)], 185), @[one]),
              @"malformed nested response is rejected");
        const uint8_t overflow[] = {0x18, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x02};
        check(!SGRAlbumCountsInReply(replyWith(@[entry(one, [NSData dataWithBytes:overflow length:sizeof(overflow)], 200)], 185), @[one]),
              @"overflowing count varint is unavailable, not zero");
        NSData *tooDeep = SGPBSerialize(@[SGPBBytes(3, SGPBSerialize(@[SGPBBytes(1, SGPBSerialize(@[SGPBVarint(1, 7)]))]))]);
        check(!SGRAlbumCountsInReply(replyWith(@[entry(one, tooDeep, 200)], 185), @[one]), @"count nesting cannot exceed the scalar wrapper");
        NSMutableArray *manyEntries = [NSMutableArray array];
        for (NSUInteger i = 0; i < 500; i++) [manyEntries addObject:entry(one, [NSData dataWithBytes:zero length:2], 200)];
        NSData *oneArray = SGPBFirst(SGPBParse(replyWith(manyEntries, 185)), 2).payload;
        NSData *overBudget = SGPBSerialize(@[SGPBBytes(2, oneArray), SGPBBytes(2, oneArray),
            SGPBBytes(2, SGPBFirst(SGPBParse(replyWith(@[entry(one, [NSData dataWithBytes:zero length:2], 200)], 185)), 2).payload)]);
        check(!SGRAlbumCountsInReply(overBudget, @[one]), @"more than 1000 reply entries rejected, including duplicate identities");
        check(SGRAlbumCountsInReply(replyWith(@[entry(one, [NSData dataWithBytes:zero length:2], 404)], 185), @[one]).count == 0,
              @"failed entity remains unavailable");
        check(SGRAlbumCountsInReply(replyWith(@[entry(one, [NSData dataWithBytes:zero length:2], 200)], 10), @[one]).count == 0,
              @"TRACK_V4 is not a count");
        check([SGRAlbumTrackURIFromMenuIdentifier(@"Components.UI.ContextMenuButton-0000000000000000000001") isEqual:one],
              @"track menu identity, not title, supplies URI");
        check(!SGRAlbumTrackURIFromMenuIdentifier(@"Components.UI.ContextMenuButton-A song title"), @"titles are not identities");

        NSString *fixtureRoot = getenv("ALBUM_COUNTS_FIXTURE_ROOT") ? @(getenv("ALBUM_COUNTS_FIXTURE_ROOT")) : NSTemporaryDirectory();
        NSURL *dir = [NSURL fileURLWithPath:[fixtureRoot stringByAppendingPathComponent:NSUUID.UUID.UUIDString]];
        NSURL *cache = [dir URLByAppendingPathComponent:@"counts.plist"];
        __block NSUInteger requests = 0;
        SGRAlbumCountsTransport transport = ^(NSString *path, NSData *body, SGSpotifyMetadataReply done) {
            dispatch_async(dispatch_get_main_queue(), ^{
                requests++;
                if (body) {
                    NSArray *entities = SGPBParse(body);
                    check(entities.count == 3, @"batched request deduplicates repeated tracks");
                    for (SGPBField *entity in entities) {
                        NSArray *fields = SGPBParse(entity.payload);
                        check(fields.count == 3, @"each entity requests exactly two extensions");
                        check(SGPBFirst(SGPBParse(((SGPBField *)fields[1]).payload), 1).varint == 10 &&
                              SGPBFirst(SGPBParse(((SGPBField *)fields[2]).payload), 1).varint == 185, @"metadata and play-count extension kinds");
                    }
                }
                done(body ? reply() : metadata(), 200, nil);
            });
        };
        SGRAlbumCountsStore *store = [[SGRAlbumCountsStore alloc] initWithCacheURL:cache transport:transport];
        check([load(store, album)[one] isEqual:@12345] && requests == 2, @"one GET and one POST per album");
        check([load(store, album)[one] isEqual:@12345] && requests == 2, @"cache avoids another request");
        for (NSUInteger i = 2; i <= 65; i++) load(store, [NSString stringWithFormat:@"spotify:album:%022lu", (unsigned long)i]);
        NSDictionary *disk = [NSDictionary dictionaryWithContentsOfURL:cache];
        check(disk.count == 64 && !disk[album], @"disk cache evicts oldest album at 64 entries");
        check([NSData dataWithContentsOfURL:cache].length <= 2 * 1024 * 1024, @"disk cache bounded to 2 MiB");
        store = [[SGRAlbumCountsStore alloc] initWithCacheURL:cache transport:transport];
        NSUInteger before = requests;
        load(store, @"spotify:album:0000000000000000000065");
        check(requests == before, @"cache survives provider recreation");
        load(store, album);
        check(requests == before + 2, @"evicted album fetches exactly one new batch");

        __block NSUInteger failedRequests = 0;
        SGRAlbumCountsStore *failed = [[SGRAlbumCountsStore alloc] initWithCacheURL:[dir URLByAppendingPathComponent:@"failed.plist"]
            transport:^(NSString *path, NSData *body, SGSpotifyMetadataReply done) {
                failedRequests++;
                done(nil, 503, nil);
            }];
        check(!load(failed, album)[one] && !load(failed, album)[one] && failedRequests == 1, @"failed request is unavailable and not repeatedly fetched");
        for (NSNumber *providerFailure in @[@NO, @YES]) {
            NSURL *failureCache = [dir URLByAppendingPathComponent:providerFailure.boolValue ? @"provider.plist" : @"entity.plist"];
            NSData *failureReply = providerFailure.boolValue
                ? SGPBSerialize(@[SGPBBytes(2, SGPBSerialize(@[SGPBVarint(2, 185),
                    SGPBBytes(1, SGPBSerialize(@[SGPBVarint(1, 503)]))]))])
                : replyWith(@[entry(one, [NSData data], 503)], 185);
            SGRAlbumCountsStore *unavailable = [[SGRAlbumCountsStore alloc] initWithCacheURL:failureCache
                transport:^(NSString *path, NSData *body, SGSpotifyMetadataReply done) { done(body ? failureReply : metadata(), 200, nil); }];
            check(!load(unavailable, album), @"HTTP 200 with failed extension status is a failure");
            NSDictionary *record = [NSDictionary dictionaryWithContentsOfURL:failureCache][album];
            check([record[@"expires"] timeIntervalSinceDate:record[@"saved"]] == 300, @"failed extension uses five-minute cooldown");
        }

        NSMutableArray<SGSpotifyMetadataReply> *held = [NSMutableArray array];
        SGRAlbumCountsStore *late = [[SGRAlbumCountsStore alloc] initWithCacheURL:[dir URLByAppendingPathComponent:@"late.plist"]
            transport:^(NSString *path, NSData *body, SGSpotifyMetadataReply done) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (body) done(reply(), 200, nil);
                    else [held addObject:[done copy]];
                });
            }];
        SGRAlbumCountPage *page = [[SGRAlbumCountPage alloc] initWithStore:late];
        [page followAlbum:album changed:^{}];
        [page followAlbum:@"spotify:album:0000000000000000000002" changed:^{}];
        waitFor(^BOOL{ return held.count == 2; });
        held[1](metadata(), 200, nil);
        waitFor(^BOOL{ return page.counts != nil; });
        held[0](nil, 503, nil);
        // A completion behind the first request's finish establishes that its late callback has run.
        load(late, album);
        check([page.albumURI isEqual:@"spotify:album:0000000000000000000002"] && [page.counts[one] isEqual:@12345],
              @"late old album reply cannot clear or replace a new page's counts");
        [page followAlbum:nil changed:^{}];
        check(page.counts == nil, @"page without an identity drops previous counts");
        NSError *error;
        check([NSFileManager.defaultManager removeItemAtURL:dir error:&error], @"fixture cache removed");
        printf("album counts: %lu checks passed\n", (unsigned long)checks);
    }
    return 0;
}
