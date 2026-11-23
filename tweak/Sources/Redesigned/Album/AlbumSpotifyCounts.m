#import "AlbumSpotifyCounts.h"
#import "Core/SGDataRoot.h"

static const NSUInteger kMaxTracksPerAlbum = 500, kMaxCachedAlbums = 64, kMaxCacheBytes = 2 * 1024 * 1024;
static const NSUInteger kMaxPendingAlbums = 16, kMaxAlbumWaiters = 16;
static const NSTimeInterval kCountLifetimeSeconds = 24 * 60 * 60, kUnavailableLifetimeSeconds = 5 * 60;
// Extended-metadata play count: the request asks for kind 185; the response carries it in payload field 3
// (a varint, or a message with varint field 1).
static const uint64_t kPlayCountExtension = 185;

NSString *SGRAlbumTrackURIFromMenuIdentifier(NSString *identifier) {
    NSString *prefix = @"Components.UI.ContextMenuButton-";
    if (![identifier hasPrefix:prefix]) return nil;
    NSString *uri = [@"spotify:track:" stringByAppendingString:[identifier substringFromIndex:prefix.length]];
    return SGSpotifyValidURI(uri, @"track") ? uri : nil;
}

@implementation SGRAlbumTrackIndex {
    NSDictionary *_byURI, *_byTitle;
}
+ (instancetype)fromMetadata:(NSData *)json {
    if (!json.length || json.length > kMaxCacheBytes) return nil;
    id album = [NSJSONSerialization JSONObjectWithData:json options:0 error:nil];
    if (![album isKindOfClass:NSDictionary.class] || ![album[@"disc"] isKindOfClass:NSArray.class]) return nil;
    NSMutableOrderedSet *tracks = [NSMutableOrderedSet orderedSet];
    NSMutableDictionary *uris = [NSMutableDictionary dictionary], *names = [NSMutableDictionary dictionary];
    BOOL allTitlesKnown = YES;
    for (id disc in album[@"disc"]) {
        if (![disc isKindOfClass:NSDictionary.class] || ![disc[@"track"] isKindOfClass:NSArray.class]) return nil;
        NSUInteger position = 0;
        for (id track in disc[@"track"]) {
            if (![track isKindOfClass:NSDictionary.class]) return nil;
            NSString *uri = track[@"uri"], *gidURI = SGSpotifyTrackURIFromGID(track[@"gid"]);
            if (!SGSpotifyValidURI(uri, @"track")) uri = gidURI;
            if (!uri || (gidURI && ![uri isEqual:gidURI])) return nil;
            [tracks addObject:uri];
            NSNumber *number = @(++position);
            uris[uri] = uris[uri] ? @0 : number;
            NSString *name = track[@"name"];
            if ([name isKindOfClass:NSString.class] && name.length) names[name] = names[name] ? @0 : number;
            else allTitlesKnown = NO;
            if (tracks.count > kMaxTracksPerAlbum) return nil;
        }
    }
    if (!tracks.count) return nil;
    SGRAlbumTrackIndex *index = [self new];
    index->_tracks = tracks.array;
    index->_byURI = uris;
    index->_byTitle = allTitlesKnown ? names : nil;
    return index;
}
- (NSNumber *)numberForURI:(NSString *)uri title:(NSString *)title {
    NSNumber *number = uri ? _byURI[uri] : title ? _byTitle[title] : nil;
    return number.unsignedIntegerValue ? number : nil;
}
@end

NSArray<NSString *> *SGRAlbumMetadataTracks(NSData *json) {
    return [SGRAlbumTrackIndex fromMetadata:json].tracks;
}

// Preflight without allocating a field object for each attacker-controlled tag. The common parser
// remains the codec authority; this scanner only bounds its allocation and skips wire payloads.
static BOOL skipVarint(const uint8_t *bytes, NSUInteger length, NSUInteger *at, uint64_t *value) {
    *value = 0;
    for (NSUInteger shift = 0; shift < 64 && *at < length; shift += 7) {
        uint8_t byte = bytes[(*at)++];
        if (shift == 63 && (byte & 0xfe)) return NO;
        *value |= (uint64_t)(byte & 127) << shift;
        if (!(byte & 128)) return YES;
    }
    return NO;
}

static const NSUInteger kMaxEnvelopeFields = 16, kMaxReplyDepth = 5;
static NSArray *limitedMessage(NSData *data, NSUInteger depth, NSUInteger fieldsLimit) {
    if (!data || depth > kMaxReplyDepth) return nil;
    const uint8_t *bytes = data.bytes;
    NSUInteger at = 0, fields = 0;
    while (at < data.length) {
        if (++fields > fieldsLimit) return nil;
        uint64_t tag, size;
        if (!skipVarint(bytes, data.length, &at, &tag) || !(tag >> 3)) return nil;
        switch (tag & 7) {
            case 0:
                if (!skipVarint(bytes, data.length, &at, &size)) return nil;
                continue;
            case 1: size = 8; break;
            case 5: size = 4; break;
            case 2:
                if (!skipVarint(bytes, data.length, &at, &size)) return nil;
                break;
            default: return nil;
        }
        if (size > data.length - at) return nil;
        at += (NSUInteger)size;
    }
    return SGPBParse(data);
}

static NSArray *message(NSArray *fields, uint32_t number, NSUInteger depth) {
    SGPBField *field = SGPBFirst(fields, number);
    return field.wire == 2 ? limitedMessage(field.payload, depth, kMaxEnvelopeFields) : nil;
}

NSDictionary<NSString *, NSNumber *> *SGRAlbumCountsInReply(NSData *data, NSArray<NSString *> *tracks) {
    if (!data.length || data.length > SGSpotifyMetadataMaxResponseBytes || tracks.count > kMaxTracksPerAlbum) return nil;
    NSArray *root = limitedMessage(data, 0, kMaxEnvelopeFields);
    if (!root) return nil;
    NSSet *wanted = [NSSet setWithArray:tracks];
    NSMutableDictionary *counts = [NSMutableDictionary dictionary];
    NSUInteger entries = 0;
    BOOL countExtension = NO;
    for (SGPBField *arrayField in root) {
        if (arrayField.number != 2) continue;
        if (arrayField.wire != 2) return nil;
        NSArray *array = limitedMessage(arrayField.payload, 1, kMaxTracksPerAlbum + kMaxEnvelopeFields);
        if (!array) return nil;
        for (SGPBField *field in array) {
            // Two requested extensions, at most one entry of each for every album track.
            if (field.number == 3 && ++entries > 2 * kMaxTracksPerAlbum) return nil;
        }
        SGPBField *kind = SGPBFirst(array, 2);
        if (!kind || kind.wire != 0 || kind.varint != kPlayCountExtension) continue;
        countExtension = YES;
        if (SGPBFirst(array, 1) && !message(array, 1, 2)) return nil;
        SGPBField *providerStatus = SGPBFirst(message(array, 1, 2), 1);
        if (providerStatus && (providerStatus.wire != 0 || providerStatus.varint != 200)) return nil;
        for (SGPBField *entryField in array) {
            if (entryField.number != 3) continue;
            if (entryField.wire != 2) return nil;
            NSArray *entry = limitedMessage(entryField.payload, 2, kMaxEnvelopeFields);
            if (!entry) return nil;
            NSString *uri = SGPBText(SGPBFirst(entry, 2));
            if (![wanted containsObject:uri ?: @""]) continue;
            SGPBField *status = SGPBFirst(message(entry, 1, 3), 1);
            if (!status || status.wire != 0 || status.varint != 200) return nil;
            NSArray *any = message(entry, 3, 3);
            if (!any) return nil;
            SGPBField *value = SGPBFirst(any, 2);
            if (!value || value.wire != 2) continue;
            NSArray *payload = limitedMessage(value.payload, 4, kMaxEnvelopeFields);
            if (!payload) return nil;
            SGPBField *count = SGPBFirst(payload, 3);
            if (count && count.wire == 2) {
                NSArray *wrapped = limitedMessage(count.payload, 5, kMaxEnvelopeFields);
                if (!wrapped) return nil;
                count = SGPBFirst(wrapped, 1);
            }
            // This schema has exactly one optional scalar wrapper: never descend into another.
            if (count && count.wire != 0) return nil;
            NSNumber *number = count && count.wire == 0 && count.varint <= LLONG_MAX ? @(count.varint) : nil;
            if (number) {
                if (counts[uri] && ![counts[uri] isEqual:number]) return nil;
                counts[uri] = number;
            }
#if DEBUG || SG_DRIVER
            NSLog(@"[spotifyglass] album counts: %@ kind=185 type=%@ field=%@ decoded=%@",
                  uri, SGPBText(SGPBFirst(any, 1)), SGPBFirst(payload, 3).wire == 2 ? @"3.1" : @"3", number ?: @"unavailable");
#endif
        }
    }
    return countExtension ? counts : nil;
}

static BOOL validCounts(id counts) {
    if (![counts isKindOfClass:NSDictionary.class] || [counts count] > kMaxTracksPerAlbum) return NO;
    for (id uri in counts) {
        id number = counts[uri];
        if (!SGSpotifyValidURI(uri, @"track") || ![number isKindOfClass:NSNumber.class] ||
            CFGetTypeID((__bridge CFTypeRef)number) == CFBooleanGetTypeID() ||
            [number doubleValue] < 0 || [number unsignedLongLongValue] > (unsigned long long)LLONG_MAX ||
            floor([number doubleValue]) != [number doubleValue]) return NO;
    }
    return YES;
}

@implementation SGRAlbumCountsStore {
    NSURL *_url;
    SGRAlbumCountsTransport _transport;
    dispatch_queue_t _queue;
    NSMutableDictionary *_records, *_pending, *_pendingIndexes;
}
- (instancetype)initWithCacheURL:(NSURL *)url transport:(SGRAlbumCountsTransport)transport {
    if (!(self = [super init])) return nil;
    _url = url;
    _transport = [transport copy];
    _queue = dispatch_queue_create("retrine.album-counts", dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_UTILITY, 0));
    _pending = [NSMutableDictionary dictionary];
    _pendingIndexes = [NSMutableDictionary dictionary];
    return self;
}
- (void)readCache {
    if (_records) return;
    _records = [NSMutableDictionary dictionary];
    NSNumber *size;
    [_url getResourceValue:&size forKey:NSURLFileSizeKey error:nil];
    if (!size || size.unsignedLongLongValue > kMaxCacheBytes) return;
    NSData *data = [NSData dataWithContentsOfURL:_url];
    id records = data ? [NSPropertyListSerialization propertyListWithData:data options:0 format:nil error:nil] : nil;
    if (![records isKindOfClass:NSDictionary.class] || [records count] > kMaxCachedAlbums) return;
    for (NSString *uri in records) {
        id record = records[uri];
        if (!SGSpotifyAlbumMetadataPath(uri) || ![record isKindOfClass:NSDictionary.class] ||
            ![record[@"expires"] isKindOfClass:NSDate.class] || ![record[@"saved"] isKindOfClass:NSDate.class] ||
            !validCounts(record[@"counts"])) continue;
        if ([record[@"expires"] timeIntervalSinceNow] > 0) _records[uri] = record;
    }
}
- (void)finishAlbum:(NSString *)uri counts:(NSDictionary *)counts {
    NSDate *now = NSDate.date;
    _records[uri] = @{@"counts": counts ?: @{}, @"saved": now,
        @"expires": [now dateByAddingTimeInterval:counts ? kCountLifetimeSeconds : kUnavailableLifetimeSeconds]};
    NSArray *oldest = [_records keysSortedByValueUsingComparator:^NSComparisonResult(id a, id b) {
        return [a[@"saved"] compare:b[@"saved"]];
    }];
    NSData *data;
    NSUInteger index = 0;
    do {
        if (_records.count <= kMaxCachedAlbums)
            data = [NSPropertyListSerialization dataWithPropertyList:_records format:NSPropertyListBinaryFormat_v1_0 options:0 error:nil];
        if (data && data.length <= kMaxCacheBytes) break;
        [_records removeObjectForKey:oldest[index++]];
    } while (_records.count);
    NSError *error;
    BOOL directory = [NSFileManager.defaultManager createDirectoryAtURL:_url.URLByDeletingLastPathComponent
                                          withIntermediateDirectories:YES attributes:nil error:&error];
    if (!directory || ![data writeToURL:_url options:NSDataWritingAtomic error:&error])
        NSLog(@"[spotifyglass] album counts: cache write failed: %@", error.localizedDescription);
    NSArray *waiters = [_pending[uri] copy];
    [_pending removeObjectForKey:uri];
    dispatch_async(dispatch_get_main_queue(), ^{
        for (SGRAlbumCountsReply done in waiters) done(counts);
    });
}
- (void)loadTrackIndex:(NSString *)uri completion:(void (^)(SGRAlbumTrackIndex *))done {
    NSString *path = SGSpotifyAlbumMetadataPath(uri);
    if (!path) { done(nil); return; }
    dispatch_async(_queue, ^{
        NSMutableArray *waiters = self->_pendingIndexes[uri];
        if (waiters) {
            if (waiters.count < kMaxAlbumWaiters) [waiters addObject:[done copy]];
            else dispatch_async(dispatch_get_main_queue(), ^{ done(nil); });
            return;
        }
        if (self->_pendingIndexes.count >= kMaxPendingAlbums) {
            dispatch_async(dispatch_get_main_queue(), ^{ done(nil); });
            return;
        }
        self->_pendingIndexes[uri] = [NSMutableArray arrayWithObject:[done copy]];
        self->_transport(path, nil, ^(NSData *json, NSInteger status, NSError *error) {
            dispatch_async(self->_queue, ^{
                SGRAlbumTrackIndex *index = status == 200 && !error ? [SGRAlbumTrackIndex fromMetadata:json] : nil;
                NSArray *callbacks = self->_pendingIndexes[uri];
                [self->_pendingIndexes removeObjectForKey:uri];
                dispatch_async(dispatch_get_main_queue(), ^{
                    for (void (^callback)(SGRAlbumTrackIndex *) in callbacks) callback(index);
                });
            });
        });
    });
}
- (void)loadAlbum:(NSString *)uri completion:(SGRAlbumCountsReply)done {
    NSString *path = SGSpotifyAlbumMetadataPath(uri);
    if (!path) { done(nil); return; }
    dispatch_async(_queue, ^{
        [self readCache];
        NSDictionary *record = self->_records[uri];
        if ([record[@"expires"] timeIntervalSinceNow] > 0) {
            dispatch_async(dispatch_get_main_queue(), ^{ done(record[@"counts"]); });
            return;
        }
        NSMutableArray *waiters = self->_pending[uri];
        if (waiters) {
            if (waiters.count < kMaxAlbumWaiters) [waiters addObject:[done copy]];
            else dispatch_async(dispatch_get_main_queue(), ^{ done(nil); });
            return;
        }
        if (self->_pending.count >= kMaxPendingAlbums) {
            dispatch_async(dispatch_get_main_queue(), ^{ done(nil); });
            return;
        }
        self->_pending[uri] = [NSMutableArray arrayWithObject:[done copy]];
        [self loadTrackIndex:uri completion:^(SGRAlbumTrackIndex *index) {
            dispatch_async(self->_queue, ^{
                NSArray *tracks = index.tracks;
                if (!tracks) { [self finishAlbum:uri counts:nil]; return; }
                // TRACK_V4 alongside count metadata is the established request shape; titles are never read.
                NSData *body = SGSpotifyExtensionRequest(tracks, @[@10, @(kPlayCountExtension)]);
                self->_transport(SGSpotifyExtendedMetadataPath, body, ^(NSData *reply, NSInteger result, NSError *failure) {
                    dispatch_async(self->_queue, ^{
                        NSDictionary *counts = result == 200 && !failure ? SGRAlbumCountsInReply(reply, tracks) : nil;
                        [self finishAlbum:uri counts:counts];
                    });
                });
            });
        }];
    });
}
@end

SGRAlbumCountsStore *SGRAlbumSpotifyCountsStore(void) {
    static SGRAlbumCountsStore *store;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSURL *base = SGDataRoot(NSCachesDirectory);
        if (base) store = [[SGRAlbumCountsStore alloc] initWithCacheURL:[base URLByAppendingPathComponent:@"AlbumCounts.plist"]
            transport:^(NSString *path, NSData *body, SGSpotifyMetadataReply done) { SGSpotifyMetadataRequest(path, body, done); }];
    });
    return store;
}

@implementation SGRAlbumCountPage {
    SGRAlbumCountsStore *_store;
    NSUInteger _generation;
}
- (instancetype)initWithStore:(SGRAlbumCountsStore *)store {
    if (!(self = [super init])) return nil;
    _store = store;
    return self;
}
- (void)followAlbum:(NSString *)uri changed:(dispatch_block_t)changed {
    if ([_albumURI isEqual:uri] || (!_albumURI && !uri)) return;
    _albumURI = [uri copy];
    _counts = nil;
    NSUInteger generation = ++_generation;
    changed();
    if (!SGSpotifyAlbumMetadataPath(uri)) return;
    __weak SGRAlbumCountPage *weakSelf = self;
    [_store loadAlbum:uri completion:^(NSDictionary *counts) {
        SGRAlbumCountPage *page = weakSelf;
        if (!page || page->_generation != generation) return;
        page->_counts = [counts copy];
        changed();
    }];
}
@end
