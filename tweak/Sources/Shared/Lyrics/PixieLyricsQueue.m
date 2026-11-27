#import "PixieLyricsQueue.h"
#import "LyricsStore.h"
#import "Shared/LyricsSources/LyricsSources.h"
#import "Shared/LocalFiles/LocalLyrics.h"
#import "Core/SGDataRoot.h"
#import "Core/SGOptionalWork.h"
#import "Core/SGPrefs.h"
#import <dlfcn.h>

NSNotificationName const SGPixieLyricsProgress = @"spotifyglass.lyrics.pixie.progress";
static const NSTimeInterval day = 86400;
static void (*observe)(BOOL);
static dispatch_block_t (*scan)(void (^)(NSArray *, NSString *));
static dispatch_block_t (*metadata)(NSString *, void (^)(NSDictionary *));

BOOL SGPixieLyricsAvailable(void) {
    if (!observe) observe = dlsym(RTLD_DEFAULT,"SAPNativeDownloadCompletionSetActive");
    if (!scan) scan = dlsym(RTLD_DEFAULT,"SAPFetchDownloadedTrackURIs");
    if (!metadata) metadata = dlsym(RTLD_DEFAULT,"SAPFetchDownloadedTrackMetadata");
    return observe && scan && metadata;
}

static NSString *trackID(id uri) {
    if (![uri isKindOfClass:NSString.class] || ![uri hasPrefix:@"spotify:track:"]) return nil;
    NSString *key = [uri substringFromIndex:14];
    return SGLyricsIsSpotifyTrackID(key) ? key : nil;
}
static BOOL enabled(void) {
    return SGFlag(SGKeyPixieLyrics,NO) && SGFlag(SGKeyLyricsOffline,YES) && SGLyricsEnabled();
}

// Main-queue state. Persist only immutable values: the utility writer owns its snapshot.
// Presence is rebuilt from the actual payload directory, membership from a verified scan.
// A persisted member is never permission to request that song after a relaunch.
static NSMutableSet<NSString *> *members, *verified, *suppressed, *present, *capacity;
static NSMutableDictionary<NSString *,NSDictionary *> *marks;
static NSMutableDictionary<NSString *,NSNumber *> *providerUntil;
static NSMutableOrderedSet<NSString *> *pending;
static NSMutableSet<NSString *> *sleeping;
static NSTimeInterval earliestRetry = DBL_MAX;
static NSMutableDictionary<NSString *,NSNumber *> *scanEvents;
static BOOL loaded, loading, active, storageFailed, scanFailed, dirty;
static BOOL takingDeletionSnapshot, rescanAfterDelete;
static NSArray *options;
static NSString *working;
static SGLyricsLease *lease;
static SGLyricsRequestContext *request;
static dispatch_block_t cancelMetadata, cancelScan, wake;
static NSUInteger scanEpoch, jobEpoch;
static NSTimeInterval wakeAt;
static unsigned long long writableBytes = ULLONG_MAX;
static NSMutableArray<dispatch_block_t> *afterLoad;

static NSURL *ledgerURL(void) {
    NSURL *dir = [SGDataRoot(NSApplicationSupportDirectory) URLByAppendingPathComponent:@"PixieLyrics" isDirectory:YES];
    return [dir URLByAppendingPathComponent:@"queue.plist"];
}
static dispatch_queue_t io(void) {
    static dispatch_queue_t q; static dispatch_once_t once;
    dispatch_once(&once, ^{ q = dispatch_queue_create("app.retrine.pixie-lyrics",dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL,QOS_CLASS_UTILITY,0)); });
    return q;
}
static void notify(void) {
    static BOOL scheduled;
    if (scheduled) return;
    scheduled = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        scheduled = NO;
        [NSNotificationCenter.defaultCenter postNotificationName:SGPixieLyricsProgress object:nil];
    });
}
static void persist(void) {
    notify();
    if (dirty || !loaded || storageFailed) return;
    dirty = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        dirty = NO;
        NSDictionary *state = @{@"version":@1, @"members":members.allObjects, @"suppressed":suppressed.allObjects,
            @"marks":marks.copy, @"providerUntil":providerUntil.copy, @"options":options ?: @[],
            @"writableBytes":@(writableBytes), @"capacity":capacity.allObjects};
        dispatch_async(io(), ^{
            NSURL *url = ledgerURL(), *dir = url.URLByDeletingLastPathComponent;
            NSError *error = nil;
            if (!url || ![NSFileManager.defaultManager createDirectoryAtURL:dir withIntermediateDirectories:YES attributes:nil error:&error] ||
                ![dir setResourceValue:@YES forKey:NSURLIsExcludedFromBackupKey error:&error] || ![state writeToURL:url error:&error]) {
                dispatch_async(dispatch_get_main_queue(), ^{ storageFailed = YES; SGPixieLyricsSettingsChanged(); notify(); });
            }
        });
    });
}
static NSMutableSet *idSet(id list) {
    NSMutableSet *set = NSMutableSet.set;
    if ([list isKindOfClass:NSArray.class]) for (id item in list) if (SGLyricsIsSpotifyTrackID(item)) [set addObject:item];
    return set;
}
static BOOL validState(NSDictionary *s) {
    if (![s[@"version"] isEqual:@1] || ![s[@"members"] isKindOfClass:NSArray.class] ||
        ![s[@"suppressed"] isKindOfClass:NSArray.class] || ![s[@"marks"] isKindOfClass:NSDictionary.class] ||
        ![s[@"providerUntil"] isKindOfClass:NSDictionary.class] || ![s[@"options"] isKindOfClass:NSArray.class]) return NO;
    for (id track in s[@"marks"]) {
        NSDictionary *row = s[@"marks"][track];
        if (!SGLyricsIsSpotifyTrackID(track) || ![row isKindOfClass:NSDictionary.class]) return NO;
        for (id key in row) if (![row[key] isKindOfClass:NSNumber.class]) return NO;
    }
    for (id key in s[@"providerUntil"]) if (![s[@"providerUntil"][key] isKindOfClass:NSNumber.class]) return NO;
    return YES;
}
static void load(void (^then)(void)) {
    if (loaded) { then(); return; }
    if (!afterLoad) afterLoad = NSMutableArray.array;
    [afterLoad addObject:[then copy]];
    if (loading) return;
    loading = YES;
    dispatch_async(io(), ^{
        NSURL *url = ledgerURL();
        NSError *error = nil;
        NSDictionary *state = url ? [NSDictionary dictionaryWithContentsOfURL:url error:&error] : nil;
        BOOL missing = [error.domain isEqual:NSCocoaErrorDomain] && error.code == NSFileReadNoSuchFileError;
        BOOL bad = !url || (!state && !missing) || (state && !validState(state));
        NSDictionary *s = bad ? nil : state;
        NSMutableSet *restoredMembers = idSet(s[@"members"]), *restoredSuppressed = idSet(s[@"suppressed"]);
        NSMutableSet *restoredCapacity = idSet(s[@"capacity"]);
        NSMutableDictionary *restoredMarks = [s[@"marks"] mutableCopy] ?: NSMutableDictionary.dictionary;
        NSMutableDictionary *restoredDeadlines = [s[@"providerUntil"] mutableCopy] ?: NSMutableDictionary.dictionary;
        NSArray *restoredOptions = s[@"options"];
        unsigned long long restoredBytes = [s[@"writableBytes"] isKindOfClass:NSNumber.class] ? [s[@"writableBytes"] unsignedLongLongValue] : ULLONG_MAX;
        dispatch_async(dispatch_get_main_queue(), ^{
            storageFailed = bad;
            members = restoredMembers; suppressed = restoredSuppressed; capacity = restoredCapacity;
            marks = restoredMarks; providerUntil = restoredDeadlines; options = restoredOptions;
            verified = NSMutableSet.set; present = NSMutableSet.set;
            writableBytes = restoredBytes;
            pending = NSMutableOrderedSet.orderedSet;
            sleeping = NSMutableSet.set;
            loaded = YES; loading = NO;
            NSArray *waiting = afterLoad.copy; afterLoad = nil;
            for (dispatch_block_t block in waiting) block();
        });
    });
}

static NSArray *lookupOptions(void) {
    NSMutableArray *result = NSMutableArray.array;
    for (NSString *key in SGLyricsOrder()) [result addObject:@[key,@(SGLyricsSourceTypes(key))]];
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    for (NSString *key in @[SGKeyLyricsAskMode, SGKeyLyricsPreferWordTiming, SGKeyLyricsTranslationLanguage,
            @"spotifyglass.lyrics.pixie.spicyRevision", @"spotifyglass.lyrics.pixie.deezerRevision"])
        [result addObject:[d objectForKey:key] ?: @""];
    return result;
}
static void retireJob(void) {
    ++jobEpoch;
    if (working && [verified containsObject:working]) [pending addObject:working];
    working = nil; [lease invalidate]; lease = nil;
    [request cancelRequests]; request = nil;
    if (cancelMetadata) cancelMetadata();
    cancelMetadata = nil;
}
static void stopScan(void) {
    ++scanEpoch;
    if (cancelScan) cancelScan();
    cancelScan = nil; scanEvents = nil;
    takingDeletionSnapshot = rescanAfterDelete = NO;
}
static void pump(void);
static void schedule(NSTimeInterval delay) {
    if (!active) return;
    NSTimeInterval at = NSDate.date.timeIntervalSince1970 + delay;
    if (wake && wakeAt <= at) return;
    if (wake) dispatch_block_cancel(wake);
    wakeAt = at;
    wake = dispatch_block_create(0, ^{ wake = nil; pump(); });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(MIN(delay,day)*NSEC_PER_SEC)),dispatch_get_main_queue(),wake);
}
static void removeTracks(NSSet *ids) {
    if (!ids.count) return;
    if ([ids containsObject:working ?: @""]) retireJob();
    [verified minusSet:ids]; [members minusSet:ids]; [suppressed minusSet:ids];
    [present minusSet:ids]; [capacity minusSet:ids];
    [pending removeObjectsInArray:ids.allObjects]; [marks removeObjectsForKeys:ids.allObjects];
    SGLyricsStoreRemoveAutomatic(ids.allObjects);
}
static void budget(unsigned long long room) {
    if (room > writableBytes) {
        [pending addObjectsFromArray:verified.allObjects];
        [capacity removeAllObjects];
    }
    writableBytes = room;
}
static void refreshStore(void) {
    if (!active) return;
    static BOOL reading, again;
    if (reading) { again = YES; return; }
    reading = YES;
    NSSet *checked = verified.copy;
    NSUInteger epoch = scanEpoch;
    SGLyricsStoreInventory(checked.allObjects, ^(NSSet *files,unsigned long long room) {
        reading = NO;
        if (files && active && scanEpoch == epoch) {
            budget(room);
            NSMutableSet *lost = present.mutableCopy;
            [lost intersectSet:checked]; [lost minusSet:files];
            [pending addObjectsFromArray:lost.allObjects];
            [present minusSet:checked]; [present unionSet:files]; [present intersectSet:verified];
            if (!room && working) retireJob();
            persist(); schedule(0);
        }
        if (again) { again = NO; refreshStore(); }
    });
}
static void reconcile(BOOL deletionSnapshot) {
    if (!deletionSnapshot && takingDeletionSnapshot) { rescanAfterDelete = YES; return; }
    stopScan();
    takingDeletionSnapshot = deletionSnapshot;
    NSUInteger epoch = scanEpoch;
    scanEvents = NSMutableDictionary.dictionary;
    cancelScan = scan(^(NSArray *uris, NSString *error) {
        if (epoch != scanEpoch) return;
        cancelScan = nil;
        if (!uris || error) { stopScan(); scanFailed = YES; notify(); return; }
        dispatch_async(io(), ^{
        NSMutableSet *live = NSMutableSet.set;
        for (NSString *uri in uris) { NSString *t = trackID(uri); if (t) [live addObject:t]; }
        SGLyricsStoreInventory(live.allObjects, ^(NSSet *onDisk,unsigned long long room) {
            if (epoch != scanEpoch) return;
            // Events between the native read and the asynchronous file inventory win.
            for (NSString *t in scanEvents) {
                if ([scanEvents[t] boolValue]) [live addObject:t]; else [live removeObject:t];
            }
            if (deletionSnapshot) {
                for (NSString *t in live) if (![scanEvents[t] boolValue]) [suppressed addObject:t];
                takingDeletionSnapshot = NO;
                persist();
            }
            if (!onDisk) { stopScan(); scanFailed = YES; notify(); return; }
            budget(room);
            // State 3 is eligibility, not history: an omitted track may be waiting or expired.
            if (working && ![live containsObject:working]) retireJob();
            [members unionSet:live]; [verified setSet:live];
            NSMutableSet *recent = present.mutableCopy;
            [recent intersectSet:[NSSet setWithArray:scanEvents.allKeys]];
            [present setSet:onDisk]; [present unionSet:recent]; [present intersectSet:live];
            [pending addObjectsFromArray:live.allObjects];
            scanEvents = nil; scanFailed = NO; persist(); schedule(0);
            if (rescanAfterDelete && active) reconcile(NO);
        });
        });
    });
}
// Negative: definitive miss; positive: retry date; a separate Boolean records a consumed 429 retry.
static void mark(NSString *t, NSString *key, NSNumber *value) {
    NSMutableDictionary *m = [marks[t] mutableCopy] ?: NSMutableDictionary.dictionary;
    m[key] = value; marks[t] = m.copy;
}
static void finishJob(void) {
    // Reclassify this result in the same bounded pass as the remaining candidates.
    if (working) [pending addObject:working];
    working = nil; request = nil; cancelMetadata = nil; lease = nil; persist(); schedule(0.25);
}
static BOOL canWork(void) { return enabled() && !SGFlag(SGKeyPixieLyricsPaused,NO) && SGOptionalWorkMayRun(NO)
    && UIApplication.sharedApplication.applicationState == UIApplicationStateActive && !SGLyricsPlaybackRequestsActive(); }

static void askNext(NSString *t, NSUInteger epoch, SGLyricsQuery *query, BOOL namedResponse, NSArray *order,
                    NSUInteger index, SGLyricsResult *best) {
    if (epoch != jobEpoch) return;
    if (!canWork()) { retireJob(); schedule(3); return; }
    NSTimeInterval now = NSDate.date.timeIntervalSince1970;
    for (; index < order.count; index++) {
        NSString *key = order[index];
        if ([key isEqual:SGImportedLRCKey]) continue;
        NSTimeInterval date = [marks[t][key] doubleValue], gate = [providerUntil[key] doubleValue];
        if (date < 0 || date > now || gate > now) continue;
        if (SGLyricsProviderFor(key).needsName && !(query.title.length && query.artist.length)) {
            mark(t,key,namedResponse ? @(-1) : @(now + day)); continue;
        }
        NSUInteger next = index + 1;
        request = SGLyricsAskDownloaded(key,query,^(SGBulkReply reply, SGLyricsResult *result, NSTimeInterval retryAt) {
            // Even an in-memory provider answer is delivered on the next turn so cancellation is installed first.
            dispatch_async(dispatch_get_main_queue(), ^{
                if (epoch != jobEpoch) return;
                if (!enabled()) { SGPixieLyricsSettingsChanged(); return; }
                NSTimeInterval at = NSDate.date.timeIntervalSince1970;
                NSString *retryKey = [@"429:" stringByAppendingString:key];
                SGLyricsResult *winner = best;
                if (retryAt > at) providerUntil[key] = @(MAX(retryAt,[providerUntil[key] doubleValue]));
                if (reply == SGBulkFound) {
                    if (!winner || SGKaraokeLinesTiming(result.karaokeLines) < SGKaraokeLinesTiming(winner.karaokeLines)) winner = result;
                } else if (reply == SGBulkMiss || reply == SGBulkFiltered) mark(t,key,reply == SGBulkMiss ? @(-1) : @(-2));
                else if (reply == SGBulkCredentialRejected) providerUntil[key] = @(at + day);
                else if (reply == SGBulkRateLimited) {
                    providerUntil[key] = @(retryAt);
                    BOOL second = [marks[t][retryKey] boolValue];
                    mark(t,key,@(second ? MAX(at + day,retryAt) : retryAt));
                    mark(t,retryKey,@(!second));
                } else mark(t,key,@(at + day));
                BOOL preferWords = SGInt(SGKeyLyricsAskMode,1) != 0 || SGFlag(SGKeyLyricsPreferWordTiming,NO);
                BOOL enough = winner && (winner.wordTimed || (!preferWords && winner.synced) || [key isEqual:SGLyricsChosenSource(t)]);
                askNext(t,epoch,query,namedResponse,order,enough ? order.count : next,winner);
            });
        });
        return;
    }
    if (!best) { finishJob(); return; }
    SGLyricsStoreAddAutomatic(t,best,lease,^(SGBulkWrite outcome) {
        if (epoch != jobEpoch) return;
        if (outcome == SGBulkWritten || outcome == SGBulkAlreadyPresent) [present addObject:t];
        else if (outcome == SGBulkCapacity) [capacity addObject:t];
        else mark(t,@"write",@(NSDate.date.timeIntervalSince1970 + day));
        finishJob();
    });
}
// Earliest eligible provider for a track. Zero is immediately runnable. DBL_MAX means
// the user or a library change is required; don't fetch metadata just to discover that.
static NSTimeInterval dueFor(NSString *t, NSArray *order) {
    if (!writableBytes || [present containsObject:t] || [suppressed containsObject:t] || [capacity containsObject:t] ||
        SGLyricsPinnedID(t) || SGImportedLRCLinkedTo(t)) return DBL_MAX;
    NSTimeInterval first = DBL_MAX;
    for (NSString *key in order) {
        if ([key isEqual:SGImportedLRCKey]) continue;
        NSTimeInterval track = [marks[t][key] doubleValue];
        if (track < 0) continue;
        first = MIN(first,MAX(track,[providerUntil[key] doubleValue]));
    }
    return MAX(first,[marks[t][@"write"] doubleValue]);
}
static void pump(void) {
    if (!active || takingDeletionSnapshot || working || storageFailed || !enabled()) return;
    if (!canWork()) { if (!SGFlag(SGKeyPixieLyricsPaused,NO) && verified.count > present.count) schedule(5); return; }
    NSTimeInterval now = NSDate.date.timeIntervalSince1970;
    NSArray *keys = SGLyricsOrder();
    // Restore deferred jobs when their persisted deadlines expire, without a per-track timer.
    if (earliestRetry <= now) {
        [pending addObjectsFromArray:sleeping.allObjects];
        [sleeping removeAllObjects]; earliestRetry = DBL_MAX;
    }
    for (NSUInteger examined=0; pending.count && examined<32; ++examined) {
        NSString *t = pending.firstObject; [pending removeObjectAtIndex:0];
        if (![verified containsObject:t]) continue;
        NSTimeInterval due = dueFor(t,keys);
        if (due > now) {
            if (due < DBL_MAX) { earliestRetry = MIN(earliestRetry,due); [sleeping addObject:t]; }
            continue;
        }
        working = t; NSUInteger epoch = ++jobEpoch; lease = SGLyricsLease.new;
        SGLyricsStoreInventory(@[t],^(NSSet *files,unsigned long long room) {
            if (epoch != jobEpoch) return;
            if (!files) { mark(t,@"write",@(now+day)); finishJob(); return; }
            budget(room);
            if ([files containsObject:t]) { [present addObject:t]; finishJob(); return; }
            if (!room) { finishJob(); return; }
            NSMutableArray *order = SGLyricsOrder().mutableCopy;
            NSString *chosen = SGLyricsChosenSource(t);
            if (chosen && [order containsObject:chosen]) { [order removeObject:chosen]; [order insertObject:chosen atIndex:0]; }
            NSString *uri = [@"spotify:track:" stringByAppendingString:t];
            cancelMetadata = metadata(uri,^(NSDictionary *row) {
                if (epoch != jobEpoch) return;
                cancelMetadata = nil;
                if (!row) { mark(t,@"write",@(NSDate.date.timeIntervalSince1970+day)); finishJob(); return; }
                if ([row[@"removed"] boolValue]) { removeTracks([NSSet setWithObject:t]); persist(); schedule(0); return; }
                SGLyricsQuery *q = SGLyricsQuery.new; q.trackID = t;
                BOOL valid = [row[@"uri"] isEqual:uri] && ![row[@"unavailable"] boolValue];
                if (valid) { q.title = row[@"name"]; q.artist = row[@"artist_name"]; q.album = row[@"album_name"]; q.seconds = [row[@"duration_ms"] integerValue]/1000; }
                askNext(t,epoch,q,valid,order,0,nil);
            });
        });
        return;
    }
    if (pending.count) schedule(0);
    else if (earliestRetry != DBL_MAX) schedule(MAX(0,earliestRetry-now));
}

static void update(void) {
    NSArray *selected = lookupOptions();
    if (![selected isEqual:options]) {
        retireJob(); [marks removeAllObjects]; [providerUntil removeAllObjects]; [pending addObjectsFromArray:verified.allObjects];
        options = selected; persist();
    }
    BOOL want = enabled() && !storageFailed;
    if (active != want) {
        active = want; observe(active); retireJob(); [verified removeAllObjects]; [pending removeAllObjects]; [present removeAllObjects];
        if (active) reconcile(NO); else if (!takingDeletionSnapshot) stopScan();
    } else if (SGFlag(SGKeyPixieLyricsPaused,NO)) retireJob();
    schedule(0); notify();
}
void SGPixieLyricsSettingsChanged(void) {
    if (!SGPixieLyricsAvailable() || (!loaded && !loading && !enabled())) return;
    load(^{ update(); });
}
void SGPixieLyricsDownloadMissing(void) {
    if (!active) return;
    retireJob(); [marks removeAllObjects]; [capacity removeAllObjects];
    if (!takingDeletionSnapshot) [suppressed removeAllObjects];
    // Keep server-provided deadlines even on an explicit retry.
    persist(); reconcile(NO);
}
void SGPixieLyricsDeleteSaved(void (^done)(unsigned long long)) {
    BOOL companion = SGPixieLyricsAvailable();
    load(^{
        retireJob(); stopScan(); [marks removeAllObjects]; [providerUntil removeAllObjects]; [pending removeAllObjects];
        [present removeAllObjects]; [capacity removeAllObjects]; [suppressed unionSet:members];
        storageFailed = NO;
        persist(); SGLyricsStoreDeleteAll(done); if (companion) reconcile(YES);
    });
}
NSDictionary *SGPixieLyricsCounts(void) {
    NSUInteger deferred = 0;
    for (NSString *t in verified) if (![present containsObject:t] &&
        (!writableBytes || marks[t].count || [suppressed containsObject:t] || [capacity containsObject:t])) deferred++;
    return @{@"saved":@(present.count),@"missing":@(verified.count - MIN(verified.count,present.count)),
        @"deferred":@(deferred),@"capacity":@(!writableBytes ? verified.count - MIN(verified.count,present.count) : capacity.count),@"failed":@(storageFailed || scanFailed)};
}

static void downloaded(NSString *uri) {
    NSString *t = trackID(uri);
    if (!active || !t) return;
    scanEvents[t] = @YES;
    [members addObject:t]; [verified addObject:t]; [pending addObject:t]; persist(); schedule(0);
}
__attribute__((constructor)) static void install(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSNotificationCenter *nc = NSNotificationCenter.defaultCenter;
        [nc addObserverForName:SGLyricsStoreChanged object:nil queue:nil usingBlock:^(NSNotification *n) { refreshStore(); }];
        [nc addObserverForName:@"SAPOfflineTrackDownloaded" object:nil queue:nil usingBlock:^(NSNotification *n) {
            dispatch_async(dispatch_get_main_queue(),^{ downloaded(n.object); });
        }];
        [nc addObserverForName:@"SAPOfflineTracksRemoved" object:nil queue:nil usingBlock:^(NSNotification *n) {
            dispatch_async(dispatch_get_main_queue(),^{
                load(^{
                NSMutableSet *ids = NSMutableSet.set;
                for (id uri in n.object) { NSString *t = trackID(uri); if (t) { [ids addObject:t]; scanEvents[t] = @NO; } }
                removeTracks(ids); persist(); schedule(0);
                });
            });
        }];
        [nc addObserverForName:NSUserDefaultsDidChangeNotification object:nil queue:nil usingBlock:^(NSNotification *n) {
            dispatch_async(dispatch_get_main_queue(), ^{ if (active || loaded) { SGPrefsChanged(); SGPixieLyricsSettingsChanged(); } });
        }];
        for (NSString *name in @[SGLyricsPinDidChangeNotification,SGLyricsSourceChosenNotification,SGLyricsDidReloadNotification]) {
            [nc addObserverForName:name object:nil queue:nil usingBlock:^(NSNotification *n) {
                if ([working isEqual:n.object]) { retireJob(); schedule(0); }
            }];
        }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC),dispatch_get_main_queue(), ^{ SGPixieLyricsSettingsChanged(); });
    });
}
