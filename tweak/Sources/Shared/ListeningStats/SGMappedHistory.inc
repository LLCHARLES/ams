// Only the sparse index and decoded pages are dirty memory.
enum { SGHistoryPageRows = 128 };

static NSRange nextRow(NSData *data, NSUInteger *cursor) {
    NSUInteger start = *cursor;
    const char *bytes = data.bytes;
    const char *lf = memchr(bytes + start, '\n', data.length - start);
    NSUInteger end = lf ? (NSUInteger)(lf - bytes) : data.length;
    *cursor = end + (lf != NULL);
    return NSMakeRange(start, end - start);
}

static NSString *rowText(NSData *data, NSRange range) {
    return [[NSString alloc] initWithBytes:(const char *)data.bytes + range.location
                                    length:range.length encoding:NSUTF8StringEncoding];
}

static NSArray<NSString *> *rowFields(NSData *data, NSRange range) {
    NSMutableArray *fields = [NSMutableArray arrayWithCapacity:7];
    const char *bytes = data.bytes;
    NSUInteger start = range.location, end = NSMaxRange(range);
    for (;;) {
        const char *tab = memchr(bytes + start, '\t', end - start);
        NSUInteger stop = tab ? (NSUInteger)(tab - bytes) : end;
        NSString *field = rowText(data, NSMakeRange(start, stop - start));
        if (!field) return nil;
        [fields addObject:field];
        if (!tab) return fields;
        start = stop + 1;
    }
}

@interface SGMappedHistory : NSArray<SGPlay *>
- (instancetype)initWithData:(NSData *)data;
- (void)findRecordIDs:(NSSet *)wanted into:(NSMutableSet *)found;
- (void)dropPages;
@end

@implementation SGMappedHistory {
    NSData *_data;
    NSMutableData *_pages;
    NSCache *_decoded;
    NSUInteger _count;
}
- (instancetype)initWithData:(NSData *)data {
    if ((self = [super init])) {
        _data = data;
        _pages = [NSMutableData data];
        _decoded = [NSCache new];
        _decoded.countLimit = 8;
        NSUInteger cursor = 0;
        while (cursor < data.length) @autoreleasepool {
            NSRange row = nextRow(data, &cursor);
            NSArray *f = rowFields(data, row);
            if (!f) return nil; // Invalid UTF-8 rejects the whole file.
            if (f.count < 6) continue;
            if (_count++ % SGHistoryPageRows == 0) [_pages appendBytes:&row.location length:sizeof(NSUInteger)];
        }
    }
    return self;
}
- (NSUInteger)count { return _count; }
- (id)copyWithZone:(NSZone *)zone { return self; }
- (void)dropPages { [_decoded removeAllObjects]; }
- (SGPlay *)objectAtIndex:(NSUInteger)index {
    if (index >= _count) [NSException raise:NSRangeException format:@"Invalid history index %lu", (unsigned long)index];
    NSUInteger page = index / SGHistoryPageRows;
    NSArray *decoded = [_decoded objectForKey:@(page)];
    if (!decoded) {
        @autoreleasepool {
            NSUInteger cursor = ((const NSUInteger *)_pages.bytes)[page];
            NSMutableArray *rows = [NSMutableArray arrayWithCapacity:SGHistoryPageRows];
            while (cursor < _data.length && rows.count < SGHistoryPageRows) @autoreleasepool {
                NSArray *f = rowFields(_data, nextRow(_data, &cursor));
                if (f.count < 6) continue;
                SGPlay *p = [SGPlay new];
                p.end = [f[0] longLongValue]; p.ms = [f[1] longLongValue];
                p.uri = f[2]; p.title = f[3]; p.artist = f[4]; p.album = f[5];
                [rows addObject:p];
            }
            decoded = rows;
            [_decoded setObject:decoded forKey:@(page)];
        }
    }
    return decoded[index % SGHistoryPageRows];
}
- (void)findRecordIDs:(NSSet *)wanted into:(NSMutableSet *)found {
    NSUInteger cursor = 0;
    while (cursor < _data.length && found.count < wanted.count) @autoreleasepool {
        NSArray *f = rowFields(_data, nextRow(_data, &cursor));
        if (f.count == 7 && [wanted containsObject:f[6]]) [found addObject:f[6]];
    }
}
@end

@interface SGHistorySuffix : NSArray<SGPlay *>
- (instancetype)initWithSnapshot:(NSArray *)snapshot start:(NSUInteger)start;
@end
@implementation SGHistorySuffix {
    NSArray *_snapshot;
    NSUInteger _start;
}
- (instancetype)initWithSnapshot:(NSArray *)snapshot start:(NSUInteger)start {
    if ((self = [super init])) { _snapshot = snapshot; _start = start; }
    return self;
}
- (NSUInteger)count { return _snapshot.count - _start; }
- (id)copyWithZone:(NSZone *)zone { return self; }
- (SGPlay *)objectAtIndex:(NSUInteger)i {
    if (i >= self.count) [NSException raise:NSRangeException format:@"Invalid suffix index %lu", (unsigned long)i];
    return _snapshot[_start + i];
}
@end

// Recording adds a short tail of journal acknowledgements to the immutable file
// snapshot. Taking a snapshot must not materialize or copy its mapped prefix.
@interface SGJournalSnapshot : NSArray<SGPlay *>
- (instancetype)initWithBase:(NSArray *)base tail:(NSArray *)tail;
@end
@implementation SGJournalSnapshot {
    NSArray *_base, *_tail;
}
- (instancetype)initWithBase:(NSArray *)base tail:(NSArray *)tail {
    if ((self = [super init])) { _base = base; _tail = [tail copy]; }
    return self;
}
- (NSUInteger)count { return _base.count + _tail.count; }
- (id)copyWithZone:(NSZone *)zone { return self; }
- (SGPlay *)objectAtIndex:(NSUInteger)i {
    return i < _base.count ? _base[i] : _tail[i - _base.count];
}
@end
