#import "Shared/Lyrics/PixieLyricsQueue.h"
extern void fixtureCompanion(NSURL *);
extern void (^fixtureLibrary(void))(NSArray *,NSString *);
extern void (^fixtureTakeLibrary(void))(NSArray *,NSString *);
extern void fixtureAnswerLibrary(NSArray *,NSString *);
extern void fixtureStorage(NSURL *);
extern NSUInteger fixtureMetadataReads(void);
extern void fixturePins(dispatch_block_t);
extern void fixtureLedgerValidation(void (^)(NSString *));
static void knownFile(NSString *track,BOOL expected) {
    __block BOOL finished=NO;
    SGLyricsStoreLoad(track,^(NSArray *lines,NSString *credit,SGLyricsResult *metadata){CHECK((lines.count>0)==expected);finished=YES;});
    pumpUntil(^BOOL{return finished;});
}
static void checkColdQueue(NSString *mode) {
    NSString *a=@"aaaaaaaaaaaaaaaaaaaaaa",*b=@"bbbbbbbbbbbbbbbbbbbbbb";
    NSString *ua=[@"spotify:track:" stringByAppendingString:a],*ub=[@"spotify:track:" stringByAppendingString:b];
    NSURL *base=[NSURL fileURLWithPath:sg_testStore], *dir=[base URLByAppendingPathComponent:@"PixieLyrics"];
    NSURL *file=[dir URLByAppendingPathComponent:@"queue.plist"];
    CHECK([NSFileManager.defaultManager createDirectoryAtURL:dir withIntermediateDirectories:YES attributes:nil error:nil]);
    SGLyricsStoreConfigureForTests([base URLByAppendingPathComponent:@"Lyrics"],1000,30*1024*1024);
    fixtureStorage(base);
    if ([mode isEqual:@"reset"]) {
        CHECK([@"corrupt" writeToURL:file atomically:YES encoding:NSUTF8StringEncoding error:nil]);
        CHECK(!SGPixieLyricsAvailable());
        __block BOOL deleted=NO;SGPixieLyricsDeleteSaved(^(unsigned long long bytes){deleted=!bytes;});
        pumpUntil(^BOOL{return deleted && [[NSDictionary dictionaryWithContentsOfURL:file error:nil][@"version"] isEqual:@1];});
        return;
    }
    fixtureCompanion(base);
    if ([mode isEqual:@"enableDuringDelete"]) {
        __block BOOL cleared=NO;
        SGPixieLyricsDeleteSaved(^(unsigned long long bytes){CHECK(!bytes); cleared=YES;});
        pumpUntil(^BOOL{return fixtureLibrary()!=nil;});
        void (^atDelete)(NSArray *,NSString *)=fixtureTakeLibrary();
        SGLyricsSetOrder(@[@"musixmatch"]);SGSetEnabled(SGKeyLyricsOffline,YES);SGSetEnabled(SGKeyPixieLyrics,YES);SGPrefsChanged();
        SGLyricsProviderFor(@"musixmatch").ask=^(SGLyricsQuery *q,void (^answer)(SGLyricsResult *)){
            CHECK([q.trackID isEqual:b]); // a was downloaded before Delete but was not in the ledger
            answer(madeUpLyrics(@"Later download",SGKaraokeTimingWords));
        };
        SGPixieLyricsSettingsChanged(); SGPixieLyricsDownloadMissing();
        atDelete(@[ua],nil);
        pumpUntil(^BOOL{return fixtureLibrary()!=nil;}); fixtureAnswerLibrary(@[ua,ub],nil);
        pumpUntil(^BOOL{return cleared && [SGPixieLyricsCounts()[@"saved"] integerValue]==1 &&
            [SGPixieLyricsCounts()[@"deferred"] integerValue]==1;});
        knownFile(a,NO); knownFile(b,YES); return;
    }
    if ([mode isEqual:@"byteBudget"]) {
        SGLyricsResult *sheet=madeUpLyrics(@"Earlier playback",SGKaraokeTimingWords);
        SGLyricsStoreSave(a,sheet.karaokeLines,sheet.provider);
        __block unsigned long long used=0;
        SGLyricsStoreSize(^(unsigned long long bytes){used=bytes;});pumpUntil(^BOOL{return used!=0;});
        SGLyricsStoreConfigureForTests([base URLByAppendingPathComponent:@"Lyrics"],10,used+1);
        SGLyricsSetOrder(@[@"musixmatch"]);SGSetEnabled(SGKeyLyricsOffline,YES);SGSetEnabled(SGKeyPixieLyrics,YES);SGPrefsChanged();
        SGLyricsProviderFor(@"musixmatch").ask=^(SGLyricsQuery *q,void (^answer)(SGLyricsResult *)){answer(sheet);};
        SGPixieLyricsSettingsChanged();pumpUntil(^BOOL{return fixtureLibrary()!=nil;});fixtureAnswerLibrary(@[ua,ub],nil);
        pumpUntil(^BOOL{return [SGPixieLyricsCounts()[@"capacity"] integerValue]==1;});
        CHECK(fixtureMetadataReads()==0);return;
    }
    if ([mode isEqual:@"largeLedger"]) {
        NSMutableArray *ids=NSMutableArray.array;
        for (unsigned i=0;i<10000;i++) [ids addObject:[NSString stringWithFormat:@"%022u",i]];
        NSString *c=@"cccccccccccccccccccccc";
        CHECK(([@{@"version":@1,@"members":[ids arrayByAddingObject:a],@"suppressed":[ids arrayByAddingObject:b],
            @"capacity":[ids arrayByAddingObject:c],@"providerUntil":@{},@"marks":@{},@"options":@[]}
            writeToURL:file error:nil]));
        NSMutableSet *serviced=NSMutableSet.set;
        fixtureLedgerValidation(^(NSString *track){
            if (![track isEqual:a] && ![track isEqual:b] && ![track isEqual:c]) return;
            dispatch_semaphore_t signal=dispatch_semaphore_create(0);
            dispatch_async(dispatch_get_main_queue(),^{[serviced addObject:track];dispatch_semaphore_signal(signal);});
            CHECK(dispatch_semaphore_wait(signal,dispatch_time(DISPATCH_TIME_NOW,60*NSEC_PER_SEC))==0);
        });
        SGLyricsSetOrder(@[@"musixmatch"]);SGSetEnabled(SGKeyLyricsOffline,YES);SGSetEnabled(SGKeyPixieLyrics,YES);SGPrefsChanged();
        SGPixieLyricsSettingsChanged();pumpUntil(^BOOL{return fixtureLibrary()!=nil;});
        CHECK(([serviced isEqual:[NSSet setWithArray:@[a,b,c]]]));return;
    }
    if ([mode isEqual:@"responsive"]) {
        NSMutableArray *uris=NSMutableArray.array;
        for (NSUInteger i=0;i<1024;i++) [uris addObject:[NSString stringWithFormat:@"spotify:track:%022lu",(unsigned long)i]];
        __block NSUInteger checked=0,atMainEvent=0;
        fixturePins(^{ if (!checked++) dispatch_async(dispatch_get_main_queue(),^{atMainEvent=checked;}); });
        SGLyricsSetOrder(@[@"musixmatch"]);SGSetEnabled(SGKeyLyricsOffline,YES);SGSetEnabled(SGKeyPixieLyrics,YES);SGPrefsChanged();
        SGPixieLyricsSettingsChanged();pumpUntil(^BOOL{return fixtureLibrary()!=nil;});fixtureAnswerLibrary(uris,nil);
        pumpUntil(^BOOL{return atMainEvent!=0;});CHECK(atMainEvent<uris.count);return;
    }
    CHECK(([@{@"version":@1,@"members":@[a],@"suppressed":@[a],@"providerUntil":@{},@"marks":@{},@"options":@[]}
        writeToURL:file error:nil]));
    __block BOOL ready=NO;dispatch_async(dispatch_get_main_queue(),^{ready=YES;});pumpUntil(^BOOL{return ready;});
    BOOL removal=[mode isEqual:@"coldRemoval"];
    if (removal) {
        [NSNotificationCenter.defaultCenter postNotificationName:@"SAPOfflineTracksRemoved" object:@[ua]];
        pumpUntil(^BOOL{return [[NSDictionary dictionaryWithContentsOfURL:file error:nil][@"suppressed"] count]==0;});
    } else {
        __block BOOL cleared=NO;SGPixieLyricsDeleteSaved(^(unsigned long long bytes){cleared=!bytes;});
        pumpUntil(^BOOL{return fixtureLibrary()!=nil;});fixtureAnswerLibrary(@[ua],nil);
        pumpUntil(^BOOL{return cleared && [SGPixieLyricsCounts()[@"deferred"] integerValue]==1;});
    }
    SGLyricsSetOrder(@[@"musixmatch"]);SGSetEnabled(SGKeyLyricsOffline,YES);SGSetEnabled(SGKeyPixieLyrics,YES);SGPrefsChanged();
    __block NSString *asked;
    SGLyricsProviderFor(@"musixmatch").ask=^(SGLyricsQuery *q,void (^answer)(SGLyricsResult *)){asked=q.trackID;};
    SGPixieLyricsSettingsChanged();pumpUntil(^BOOL{return fixtureLibrary()!=nil;});fixtureAnswerLibrary(removal?@[ua]:@[ua,ub],nil);
    pumpUntil(^BOOL{return asked!=nil;});CHECK([asked isEqual:removal?a:b]);
}
static void checkPixieQueue(void) {
    NSString *a=@"aaaaaaaaaaaaaaaaaaaaaa", *b=@"bbbbbbbbbbbbbbbbbbbbbb", *c=@"cccccccccccccccccccccc";
    NSString *(^uri)(NSString *)=^(NSString *t){return [@"spotify:track:" stringByAppendingString:t];};
    CHECK(!SGPixieLyricsAvailable());
    SGPixieLyricsSettingsChanged(); CHECK(!fixtureLibrary());
    NSURL *base=[NSURL fileURLWithPath:sg_testStore];
    SGLyricsStoreConfigureForTests([base URLByAppendingPathComponent:@"Lyrics"],1000,30*1024*1024);
    fixtureCompanion(base); CHECK(SGPixieLyricsAvailable());
    SGLyricsSetOrder(@[@"musixmatch"]);
    SGSetEnabled(SGKeyLyricsOffline,YES);SGSetEnabled(SGKeyPixieLyrics,YES);SGPrefsChanged();
    __block void (^held)(SGLyricsResult *);
    SGLyricsProvider *provider=SGLyricsProviderFor(@"musixmatch");
    __block NSInteger misses=0,temporary=0;
    provider.ask=^(SGLyricsQuery *q,void (^reply)(SGLyricsResult *)) {
        CHECK([q.title isEqual:@"Named song"] && [q.artist isEqual:@"Artist"]);
        if ([q.trackID isEqual:b]) { misses++; q.requestContext.definiteMiss=YES;reply(nil); }
        else if ([q.trackID isEqual:c]) { temporary++; [q.requestContext noteFailure:YES];reply(nil); }
        else held=reply;
    };
    SGPixieLyricsSettingsChanged();pumpUntil(^BOOL{return fixtureLibrary()!=nil;});
    [NSNotificationCenter.defaultCenter postNotificationName:@"SAPOfflineTrackDownloaded" object:uri(a)];
    pumpUntil(^BOOL{return held!=nil;});
    fixtureAnswerLibrary(@[uri(b),uri(c)],nil); // older scan didn't include the completed song
    held(madeUpLyrics(@"Saved by Pixie",SGKaraokeTimingWords));held=nil;
    pumpUntil(^BOOL{return [SGPixieLyricsCounts()[@"saved"] integerValue]==1 && [SGPixieLyricsCounts()[@"deferred"] integerValue]==2;});
    CHECK(misses==1 && temporary==1 && !SGLyricsKeptAnswer(a));
    SGSetEnabled(SGKeyPixieLyrics,NO);SGPrefsChanged();SGPixieLyricsSettingsChanged();
    SGSetEnabled(SGKeyPixieLyrics,YES);SGPrefsChanged();SGPixieLyricsSettingsChanged();
    pumpUntil(^BOOL{return fixtureLibrary()!=nil;});fixtureAnswerLibrary(@[uri(a),uri(b),uri(c)],nil);
    pumpUntil(^BOOL{return [SGPixieLyricsCounts()[@"saved"] integerValue]==1;});CHECK(misses==1 && temporary==1);
    // A failed scan must not remove a saved track or manufacture a verified empty library.
    SGPixieLyricsDownloadMissing();fixtureAnswerLibrary(nil,@"unavailable");
    CHECK([SGPixieLyricsCounts()[@"failed"] boolValue] && [SGPixieLyricsCounts()[@"saved"] integerValue]==1);
    __block BOOL deleted=NO; SGPixieLyricsDeleteSaved(^(unsigned long long size){CHECK(!size);deleted=YES;});
    fixtureAnswerLibrary(@[uri(a),uri(b),uri(c)],nil);
    pumpUntil(^BOOL{return deleted && [SGPixieLyricsCounts()[@"deferred"] integerValue]==3;});
    CHECK(!held);
    [NSNotificationCenter.defaultCenter postNotificationName:@"SAPOfflineTracksRemoved" object:@[uri(a),uri(b)]];
    [NSNotificationCenter.defaultCenter postNotificationName:@"SAPOfflineTrackDownloaded" object:uri(a)];
    pumpUntil(^BOOL{return held!=nil;});
    void (^stale)(SGLyricsResult *)=held;held=nil;
    [NSNotificationCenter.defaultCenter postNotificationName:@"SAPOfflineTracksRemoved" object:@[uri(a)]];
    pumpUntil(^BOOL{return [SGPixieLyricsCounts()[@"missing"] integerValue]==1;});
    stale(madeUpLyrics(@"Removed",SGKaraokeTimingWords));
    [NSNotificationCenter.defaultCenter postNotificationName:@"SAPOfflineTrackDownloaded" object:uri(a)];
    pumpUntil(^BOOL{return held!=nil;});held(madeUpLyrics(@"Downloaded again",SGKaraokeTimingWords));held=nil;
    pumpUntil(^BOOL{return [SGPixieLyricsCounts()[@"saved"] integerValue]==1;});
    // State 3 can disappear temporarily. Neither its payload nor its miss history is deleted.
    SGPixieLyricsDownloadMissing();fixtureAnswerLibrary(@[],nil);
    pumpUntil(^BOOL{return [SGPixieLyricsCounts()[@"saved"] integerValue]==0;});knownFile(a,YES);
    SGLyricsStoreConfigureForTests([base URLByAppendingPathComponent:@"Lyrics"],1,30*1024*1024);
    NSUInteger reads=fixtureMetadataReads();
    SGPixieLyricsDownloadMissing();fixtureAnswerLibrary(@[uri(a),uri(b)],nil);
    NSURL *ledger=[base URLByAppendingPathComponent:@"PixieLyrics/queue.plist"];
    pumpUntil(^BOOL{return [SGPixieLyricsCounts()[@"capacity"] integerValue]==1 &&
        [[NSDictionary dictionaryWithContentsOfURL:ledger error:nil][@"writableBytes"] isEqual:@0];});
    CHECK(fixtureMetadataReads()==reads);
    SGSetEnabled(SGKeyPixieLyricsPaused,YES);SGPrefsChanged();SGPixieLyricsSettingsChanged();
    SGLyricsStoreDelete(a);
    pumpUntil(^BOOL{return ![SGPixieLyricsCounts()[@"saved"] integerValue] && ![SGPixieLyricsCounts()[@"capacity"] integerValue];});
    // A deferred request gets its retry even if the final pending entry is already on disk.
    SGLyricsStoreConfigureForTests([base URLByAppendingPathComponent:@"Lyrics"],10,30*1024*1024);
    SGLyricsResult *saved=madeUpLyrics(@"Earlier playback",SGKaraokeTimingWords);
    SGLyricsStoreSave(b,saved.karaokeLines,saved.provider);
    pumpUntil(^BOOL{return [SGPixieLyricsCounts()[@"saved"] integerValue]==1;});
    __block NSUInteger attempts=0;
    provider.ask=^(SGLyricsQuery *q,void (^reply)(SGLyricsResult *)){
        CHECK([q.trackID isEqual:a]);attempts++;
        if (attempts==1) {
            [NSNotificationCenter.defaultCenter postNotificationName:@"SAPOfflineTrackDownloaded" object:uri(b)];
            [q.requestContext noteResponse:[[NSHTTPURLResponse alloc]initWithURL:[NSURL URLWithString:@"https://fixture.invalid"] statusCode:429 HTTPVersion:nil headerFields:@{@"Retry-After":@"1"}] error:nil]; reply(nil);
        } else reply(saved);
    };
    SGSetEnabled(SGKeyPixieLyricsPaused,NO);SGPrefsChanged();SGPixieLyricsSettingsChanged();
    pumpUntil(^BOOL{return [SGPixieLyricsCounts()[@"saved"] integerValue]==2;});CHECK(attempts==2);
    puts("PASS: absent/late companion, cold metadata, verified scan vs. completion, misses/backoff, stale delivery, bulk removal, explicit delete and re-download");
}
