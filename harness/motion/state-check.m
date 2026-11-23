// Production follower/catalog with deterministic player and HTTP boundaries. No Spotify or network.
#import <UIKit/UIKit.h>
#import "Shared/AnimatedArtwork/AnimatedArtwork.h"
#import "Shared/Player/PlayerState.h"
#import "Shared/AnimatedArtwork/SGMotionTicket.h"
#import "Shared/SpotifyMetadata/SGSpotifyMetadata.h"
#import "Shared/Haptics/Haptics.h"
#import <objc/runtime.h>
#import "player-state.inc"

#define CHECK(value) do { if (!(value)) { fprintf(stderr, "FAIL %d: %s\n", __LINE__, #value); exit(1); } } while (0)

@interface SPTPlayerTrack ()
@property (nonatomic, readwrite) id URI;
@property (nonatomic, readwrite) NSString *artistName;
@property (nonatomic, readwrite) NSString *trackTitle;
@property (nonatomic, readwrite) NSDictionary *metadata;
@end
@implementation SPTPlayerTrack
@dynamic artistURI, provider;
@end
@interface SPTPlayerState ()
@property (nonatomic, readwrite) SPTPlayerTrack *track;
@property (nonatomic, readwrite) NSArray *future;
@property (nonatomic, readwrite) id contextURI;
@property (nonatomic, readwrite) SPTPlayerOptions *options;
@property (nonatomic, readwrite) BOOL isPaused, isPlaying, isLoading;
@end
@implementation SPTPlayerState
@dynamic sleepTimer, position, positionAsOfTimestamp;
@dynamic timestamp, playbackSpeed, duration, reverse;
@end

static SPTPlayerState *state;
static __weak id<SGPlayerStateObserver> observer;
static NSURL *walkCanvas;
static NSArray *walkEvidence;
static NSURL *store;
static NSString *edition = @"first";
static NSDictionary *editorialVideos;
static NSArray *coverResults;
static NSDictionary *barcodeReply;
static NSString *spotifyUPC;
static NSString *expectedTrack;
static NSDictionary *songsReply;
static NSUInteger recordingReads;
static NSInteger recordingStatus = 200;
static BOOL hapticsRequest;
static NSUInteger metadataGets, barcodeGets;
static BOOL appleOn = YES;
static BOOL holdMetadata;
static dispatch_block_t sendMetadata;
BOOL SGMotionAppleMusicOn(void) { return appleOn; }
dispatch_block_t SGSpotifyMetadataRequestAllowConstrained(NSString *path, NSData *body, BOOL allow, SGSpotifyMetadataReply done) {
    if ([path isEqual:SGSpotifyExtendedMetadataPath]) {
        NSArray *entity = SGPBParse(SGPBFirst(SGPBParse(body), 2).payload);
        NSString *uri = SGPBText(SGPBFirst(entity, 1));
        CHECK([uri isEqual:expectedTrack] && allow == hapticsRequest && NSThread.isMainThread);
        recordingReads++;
        NSData *external = SGPBSerialize(@[SGPBString(1, @"isrc"), SGPBString(2, @"GBN9Y2200015")]);
        NSData *track = SGPBSerialize(songsReply ? @[SGPBBytes(10, external)] : @[SGPBString(2, @"Song")]);
        NSData *any = SGPBSerialize(@[SGPBString(1, @"type.googleapis.com/spotify.metadata.Track"), SGPBBytes(2, track)]);
        NSData *entry = SGPBSerialize(@[SGPBBytes(1, SGPBSerialize(@[SGPBVarint(1, 200)])), SGPBString(2, uri), SGPBBytes(3, any)]);
        done(SGPBSerialize(@[SGPBBytes(2, SGPBSerialize(@[SGPBBytes(3, entry)]))]), recordingStatus, nil);
        return ^{};
    }
    CHECK([path hasPrefix:@"/metadata/4/album/"] && !body && !allow && appleOn);
    metadataGets++;
    NSArray *ids = spotifyUPC ? @[@{@"type": @"upc", @"id": spotifyUPC}] : @[];
    NSData *json = [NSJSONSerialization dataWithJSONObject:@{@"external_id":ids,
        @"disc": @[@{@"track": @[@{@"gid": @"00000000000000000000000000000001"}]}]} options:0 error:nil];
    dispatch_block_t send = ^{ dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{ done(json, 200, nil); }); };
    if (holdMetadata) sendMetadata = send;
    else send();
    return ^{};
}
static NSMutableArray *coverSearches;
static NSUInteger masterHits, mediaHits;
static NSUInteger sentinelReads;
extern NSString *fixtureSimplifiedTitle(NSString *);
NSString *SGLyricsSimplifiedTitle(NSString *title) {
    if ([title isEqual:@"catalog sentinel"]) sentinelReads++;
    return fixtureSimplifiedTitle(title);
}
static NSData *redLogo, *blueLogo;
static BOOL blue;

static BOOL advanceAllowed = YES;
BOOL SGOptionalWorkMayRun(BOOL expensive) { return advanceAllowed; }
static NSMutableArray<NSString *> *requested;
static NSMutableDictionary<NSString *, SGMotionTicket *> *tickets;
NSArray *SGMotionSourceOrder(void) { return @[@"canvas", @"applemusic"]; }
CGFloat SGMotionPixels(void) { return 720; }
NSURL *SGMotionCanvasIn(NSDictionary *metadata) {
    NSString *address = metadata[@"canvas.url"];
    return address ? [NSURL URLWithString:address] : nil;
}
SGMotionTicket *SGMotionRequestAlbumSongClip(NSString *uri, NSURL *canvas, NSString *artist, NSString *album, NSString *song, NSString *albumURI,
                     CGFloat pixels, void (^done)(NSURL *, NSString *)) {
    walkCanvas = canvas;
    walkEvidence = @[artist ?: @"", album ?: @"", song ?: @"", albumURI ?: @""];
    SGMotionTicket *ticket = [SGMotionTicket new];
    [requested addObject:uri];
    tickets[uri] = ticket;
    done(canvas, canvas ? @"canvas" : nil);
    return ticket;
}
void SGMotionFile(NSURL *remote, void (^done)(NSURL *)) { done(remote); }
SGMotionTicket *SGMotionRequestFile(NSURL *remote, void (^done)(NSURL *)) {
    SGMotionTicket *ticket = [SGMotionTicket new];
    dispatch_async(dispatch_get_main_queue(), ^{ if (!ticket.cancelled) done(remote); });
    return ticket;
}
void SGMotionStoreBytes(void (^done)(uint64_t bytes)) { done(0); }
void SGMotionStoreClear(void (^done)(BOOL complete)) { done(YES); }
BOOL SGFlag(NSString *key, BOOL fallback) { return fallback; }
NSURL *SGMotionTestAlbumAnswersFile(void) { return store; }

static void waitFor(BOOL (^ready)(void)) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:10];
    while (!ready() && deadline.timeIntervalSinceNow > 0)
        [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.001]];
    CHECK(ready());
}

@interface CatalogProtocol : NSURLProtocol
@end
@implementation CatalogProtocol
+ (BOOL)canInitWithRequest:(NSURLRequest *)request { return YES; }
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request { return request; }
- (void)startLoading {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSURL *url = self.request.URL;
        NSData *data;
        if ([url.host isEqual:@"amp-api.music.apple.com"]) {
            NSURLComponents *parts = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
            NSMutableDictionary *query = [NSMutableDictionary dictionary];
            for (NSURLQueryItem *item in parts.queryItems) query[item.name] = item.value;
            if ([url.path isEqual:@"/v1/catalog/us/songs"]) {
                CHECK([query[@"filter[isrc]"] isEqual:@"GBN9Y2200015"] && [query[@"include"] isEqual:@"albums"] &&
                      [query[@"extend[albums]"] isEqual:@"editorialVideo"] && !self.request.allowsConstrainedNetworkAccess);
                data = [NSJSONSerialization dataWithJSONObject:songsReply options:0 error:nil];
            } else if ([url.path isEqual:@"/v1/catalog/us/albums"]) {
                CHECK([query[@"filter[upc]"] isEqual:spotifyUPC] && [query[@"extend"] isEqual:@"editorialVideo"]);
                CHECK(!self.request.allowsConstrainedNetworkAccess);
                barcodeGets++;
                data = [NSJSONSerialization dataWithJSONObject:barcodeReply options:0 error:nil];
            } else {
            BOOL artist = [query[@"types"] isEqual:@"artists"];
            NSString *term = query[@"term"];
            NSArray *records = coverResults;
            if (records) {
                [coverSearches addObject:term];
                if (![query[@"include[albums]"] isEqual:@"tracks"]) { // the normal search has no track relationship
                    NSMutableArray *bare = [NSMutableArray array];
                    for (NSDictionary *record in records) [bare addObject:@{@"attributes": record[@"attributes"]}];
                    records = bare;
                }
            } else {
                NSDictionary *attributes = artist
                    ? @{@"name": term, @"editorialArtwork": @{@"musicContentColorLogoTrimmed":
                        @{@"url": @"https://fixture.invalid/logo.png", @"width": @1024, @"height": @1024}}}
                    : @{@"name": [term substringFromIndex:@"Artist ".length], @"artistName": @"Artist",
                        @"editorialVideo": editorialVideos ?: @{@"motionTallVideo3x4": @{@"video":
                            [NSString stringWithFormat:@"https://fixture.invalid/%@/%@/master.m3u8", edition,
                                [[term substringFromIndex:@"Artist ".length] stringByReplacingOccurrencesOfString:@" " withString:@"-"]]}}};
                records = @[@{@"attributes": attributes}];
            }
            data = [NSJSONSerialization dataWithJSONObject:
                @{@"results": @{artist ? @"artists" : @"albums": @{@"data": records}}} options:0 error:nil];
            }
        } else if ([url.path hasSuffix:@"master.m3u8"]) {
            masterHits++;
            data = [@"#EXTM3U\n#EXT-X-STREAM-INF:RESOLUTION=720x960\nmedia.m3u8" dataUsingEncoding:NSUTF8StringEncoding];
        } else if ([url.path hasSuffix:@"media.m3u8"]) {
            mediaHits++;
            data = [@"#EXTM3U\nclip.mp4" dataUsingEncoding:NSUTF8StringEncoding];
        } else {
            CHECK([url.path isEqual:@"/logo.png"]);
            data = blue ? blueLogo : redLogo;
        }
        NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:url statusCode:200 HTTPVersion:@"HTTP/1.1" headerFields:nil];
        [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
        [self.client URLProtocol:self didLoadData:data];
        [self.client URLProtocolDidFinishLoading:self];
    });
}
- (void)stopLoading {}
@end

static NSURL *album(NSString *name) {
    __block BOOL finished = NO;
    __block NSURL *value;
    SGMotionAlbumCover(@"Artist", name, 720, ^(NSURL *file) { value = file; finished = YES; });
    waitFor(^BOOL { return finished; });
    return value;
}
static UIImage *logo(NSString *artist) {
    __block BOOL finished = NO;
    __block UIImage *value;
    SGMotionArtistLogo(artist, 1024, ^(UIImage *image) { value = image; finished = YES; });
    waitFor(^BOOL { return finished; });
    return value;
}

static NSDictionary *release(NSString *name, NSString *artist, BOOL single, NSArray *songs) {
    return @{@"attributes": @{@"name": name, @"artistName": artist, @"isSingle": @(single),
        @"editorialVideo": @{@"motionTallVideo3x4": @{@"video": @"https://fixture.invalid/f1/master.m3u8"}}},
        @"relationships": @{@"tracks": @{@"data": songs}}};
}

static NSDictionary *clipRelease(NSString *name, NSString *artist, BOOL single, NSArray *songs, NSString *folder) {
    NSString *video = [NSString stringWithFormat:@"https://fixture.invalid/%@/master.m3u8", folder];
    return @{@"attributes": @{@"name": name, @"artistName": artist, @"isSingle": @(single),
        @"editorialVideo": @{@"motionTallVideo3x4": @{@"video": video}}},
        @"relationships": @{@"tracks": @{@"data": songs}}};
}

static NSURL *songCover(NSString *artist, NSString *album, NSString *song) {
    __block BOOL finished = NO;
    __block NSURL *result;
    SGMotionRequestSongCover(artist, album, song, nil, nil, 720, ^(NSURL *file) { result = file; finished = YES; });
    waitFor(^BOOL { return finished; });
    return result;
}

static NSURL *coverWithURI(NSString *name, NSString *song, NSString *uri) {
    __block BOOL finished = NO;
    __block NSURL *result;
    SGMotionRequestSongCover(@"Pink Floyd", name, song, uri, @"spotify:track:0000000000000000000002", 720, ^(NSURL *file) {
        CHECK(NSThread.isMainThread);
        result = file;
        finished = YES;
    });
    waitFor(^BOOL { return finished; });
    return result;
}

static void checkBarcode(void) {
    NSString *name = @"The Dark Side Of The Moon (50th Anniversary) [2023 Remaster]";
    NSString *song = @"Speak to Me - 2023 Remaster", *uri = @"spotify:album:0000000000000000000001";
    barcodeReply = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:@"fixtures/196589805232.json"] options:0 error:nil];
    coverResults = barcodeReply[@"data"];
    spotifyUPC = @"00196589805232";
    CHECK(!coverWithURI(name, song, nil)); // a cached title miss must not mask a later barcode
    CHECK(!metadataGets && !barcodeGets);
    holdMetadata = YES;
    SGMotionTicket *cancelled = SGMotionRequestSongCover(@"Pink Floyd", name, song, uri, @"spotify:track:0000000000000000000002", 720, ^(NSURL *file) { CHECK(NO); });
    waitFor(^BOOL { return sendMetadata != nil; });
    __block BOOL page = NO, pageAsked = NO;
    SGMotionPageAlbumCover(@"Pink Floyd", name, 720, ^(NSURL *file, BOOL identified) {
        CHECK(!file && !identified);
        SGMotionAlbumRowMatcher(@"Pink Floyd", name, 720, ^(SGMotionRowMatch rows) { CHECK(!rows); }, ^(NSURL *row) {
            CHECK(!row);
            SGMotionPageIdentifierCover(uri, name, 720, ^(NSURL *clip) {
                CHECK([clip.path isEqual:@"/1665303755/clip.mp4"]); page = YES;
            });
            pageAsked = YES;
        });
    });
    waitFor(^BOOL { return pageAsked; });
    [cancelled cancel];
    holdMetadata = NO;
    sendMetadata();
    sendMetadata = nil;
    waitFor(^BOOL { return page; });
    CHECK([coverWithURI(name, song, uri).path isEqual:@"/1665303755/clip.mp4"]);
    CHECK(metadataGets == 1 && barcodeGets == 1);
    CHECK(!coverWithURI(@"The Dark Side of the Moon", song, uri)); // the identified plain release is still
    CHECK(coverWithURI(coverResults[1][@"attributes"][@"name"], song, uri));
    CHECK(metadataGets == 1 && barcodeGets == 1);

    NSString *other = @"spotify:album:0000000000000000000002";
    expectedTrack = @"spotify:track:0000000000000000000002";
    spotifyUPC = @"093624912194"; // a different real barcode, with a significant leading zero
    CHECK(!coverWithURI(name, song, other)); // even the record with video has the wrong UPC
    CHECK(metadataGets == 2 && barcodeGets == 2);
    spotifyUPC = nil;
    other = @"spotify:album:0000000000000000000003";
    appleOn = NO;
    CHECK(!coverWithURI(name, song, other) && metadataGets == 2);
    appleOn = YES;
    CHECK(!coverWithURI(name, song, other) && metadataGets == 3 && barcodeGets == 2);
    CHECK(!coverWithURI(name, song, other) && metadataGets == 3);
    spotifyUPC = @"5054197493980"; // observed distributor UPC: neither returned album carries it
    NSDictionary *fixture = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:@"fixtures/GBN9Y2200015.json"] options:0 error:nil];
    songsReply = fixture;
    CHECK([coverWithURI(name, song, @"spotify:album:1ipVQZ4voJtfJxCNlR8lg4").path isEqual:@"/1665303755/clip.mp4"]);

    expectedTrack = @"spotify:track:0000000000000000000001"; // page uses the album's first GID, not the player
    __block BOOL firstTrack = NO;
    SGMotionPageIdentifierCover(@"spotify:album:0000000000000000000004", name, 720, ^(NSURL *file) {
        CHECK([file.path isEqual:@"/1665303755/clip.mp4"]); firstTrack = YES;
    });
    waitFor(^BOOL { return firstTrack; });

    expectedTrack = @"spotify:track:0000000000000000000002";
    NSDictionary *record = fixture[@"data"][0][@"relationships"][@"albums"][@"data"][0];
    NSMutableDictionary *second = [record mutableCopy];
    second[@"id"] = @"another-edition";
    NSDictionary *(^replyWithAlbums)(NSArray *) = ^NSDictionary *(NSArray *albums) {
        NSMutableDictionary *hit = [fixture[@"data"][0] mutableCopy];
        hit[@"relationships"] = @{@"albums": @{@"data": albums}};
        return @{@"data": @[hit]};
    };
    songsReply = replyWithAlbums(@[record, second]);
    CHECK(!coverWithURI(name, song, @"spotify:album:0000000000000000000005"));
    NSMutableDictionary *attributes = [second[@"attributes"] mutableCopy];
    attributes[@"isSingle"] = @YES;
    second[@"attributes"] = attributes;
    songsReply = replyWithAlbums(@[second]);
    CHECK(!coverWithURI(name, song, @"spotify:album:0000000000000000000006"));

    // Persisted song4 misses include still releases identified only by a track, not the header artist.
    spotifyUPC = @"196589805232";
    coverResults = @[@{@"attributes": @{@"name": @"Legacy still", @"artistName": @"Compilation", @"isSingle": @NO},
                       @"relationships": @{@"tracks": @{@"data": @[@{@"attributes": @{@"name": @"One", @"artistName": @"Pink Floyd"}}]}}}];
    NSUInteger before = metadataGets;
    BOOL legacyStill = !coverWithURI(@"Legacy still", @"One", @"spotify:album:0000000000000000000007") && metadataGets == before;
    // A clip kept under the older song key is still that track's clip: no search, no identifier lookup.
    NSUInteger searched = coverSearches.count;
    legacyStill = legacyStill && [coverWithURI(@"Legacy clip", @"One", @"spotify:album:0000000000000000000012").path isEqual:@"/legacy-clip.mp4"]
        && coverSearches.count == searched && metadataGets == before;

    coverResults = @[];
    spotifyUPC = nil;
    songsReply = fixture;
    BOOL withoutUPC = [coverWithURI(name, song, @"spotify:album:0000000000000000000008").path isEqual:@"/1665303755/clip.mp4"];

    spotifyUPC = @"5054197493980";
    recordingStatus = 401;
    hapticsRequest = YES;
    __block BOOL hapticsDone = NO;
    SGSpotifyISRCWithOutcome(expectedTrack, 1, ^(NSString *code, BOOL failed) {
        CHECK(!code && !failed); hapticsDone = YES;  // legacy caller's 401 classification
    });
    waitFor(^BOOL { return hapticsDone; });
    hapticsRequest = NO;
    NSString *retryURI = @"spotify:album:0000000000000000000009";
    CHECK(!coverWithURI(name, song, retryURI));
    recordingStatus = 200;
    BOOL retried = [coverWithURI(name, song, retryURI).path isEqual:@"/1665303755/clip.mp4"];

    NSMutableDictionary *punctuation = [record mutableCopy], *punctAttrs = [record[@"attributes"] mutableCopy];
    punctAttrs[@"name"] = @"=";
    punctuation[@"attributes"] = punctAttrs;
    songsReply = replyWithAlbums(@[punctuation]);
    BOOL different = !coverWithURI(@"+", song, @"spotify:album:0000000000000000000010");
    BOOL identical = [coverWithURI(@"=", song, @"spotify:album:0000000000000000000011").path isEqual:@"/1665303755/clip.mp4"];
    fprintf(stderr, "motion: legacy still %s; absent UPC %s; unanswered retry %s; punctuation %s\n",
            legacyStill ? "PASS" : "FAIL", withoutUPC ? "PASS" : "FAIL", retried ? "PASS" : "FAIL", different && identical ? "PASS" : "FAIL");
    CHECK(legacyStill && withoutUPC && retried && different && identical);

    // The recording's only release is Apple's "X - Single" for Spotify's single "X" (MEOVV's HANDS UP, issue #48);
    // "Rich Man - Single" is not "Rich Man - The 6th Mini Album" although their edition-stripped names agree.
    NSDictionary *(^named)(NSString *, BOOL) = ^NSDictionary *(NSString *title, BOOL isSingle) {
        NSMutableDictionary *copy = [record mutableCopy], *attrs = [record[@"attributes"] mutableCopy];
        attrs[@"name"] = title;
        attrs[@"isSingle"] = @(isSingle);
        copy[@"attributes"] = attrs;
        copy[@"id"] = title;
        return copy;
    };
    spotifyUPC = nil;
    songsReply = replyWithAlbums(@[named(@"HANDS UP - Single", YES)]);
    BOOL recordingSingle = [coverWithURI(@"HANDS UP", song, @"spotify:album:0000000000000000000013").path isEqual:@"/1665303755/clip.mp4"];
    songsReply = replyWithAlbums(@[named(@"Rich Man - Single", YES)]);
    BOOL leadSingleKept = !coverWithURI(@"Rich Man - The 6th Mini Album", song, @"spotify:album:0000000000000000000014");
    fprintf(stderr, "motion: recording single %s, lead single not the album %s\n", recordingSingle ? "PASS" : "FAIL", leadSingleKept ? "PASS" : "FAIL");
    CHECK(recordingSingle && leadSingleKept);
    songsReply = nil;
    expectedTrack = nil;
    coverResults = nil;
}

static void checkSoundtrack(void) {
    // Trimmed US catalog 1810796698 (the final five entries are music videos),
    // and the different display credits from Spotify album 2HwRKkEp7jXbxXwcGyZYHK.
    NSArray *rows = @[
        @[@"Lose My Mind (feat. Doja Cat)", @"Don Toliver", @"Don Toliver, Doja Cat"],
        @[@"No Room For A Saint (feat. Nathan Nicholson)", @"Dom Dolla & Nathan Nicholson", @"Dom Dolla, Nathan Nicholson"],
        @[@"Drive", @"Ed Sheeran"], @[@"Just Keep Watching", @"Tate McRae"], @[@"Messy", @"ROSÉ"],
        @[@"Don't Let Me Drown", @"Burna Boy"], @[@"Underdog", @"Roddy Ricch"], @[@"Grandma Calls The Boy Bad News", @"RAYE"],
        @[@"Bad As I Used To Be", @"Chris Stapleton"], @[@"Baja California", @"Myke Towers"],
        @[@"OMG!", @"Tiësto & Sexyy Red", @"Tiësto, Sexyy Red"], @[@"All At Once", @"Madison Beer"], @[@"D.A.N.C.E", @"Peggy Gou"],
        @[@"DOUBLE C", @"PAWSA"], @[@"Attention", @"Mr Eazi"], @[@"Give Me Love", @"Darkoo"], @[@"Gasoline", @"Obongjayar"]
    ];
    NSMutableArray *tracks = [NSMutableArray array];
    for (NSArray *row in rows) [tracks addObject:@{@"attributes": @{@"name": row[0], @"artistName": row[1]}}];
    NSString *name = @"F1 The Album";
    coverResults = @[release(name, @"Various Artists", NO, tracks), release(@"F1 The Album (Cinematic Edition)", @"Hans Zimmer", NO, tracks)];
    CHECK(!songCover(name, name, nil)); // the old header strings alone don't identify a compilation
    CHECK(songCover(@"Various Artists", name, nil)); // opening the album fetched both playlists
    NSUInteger masters = masterHits, media = mediaHits;
    coverSearches = [NSMutableArray array];
    for (NSArray *row in rows) CHECK([songCover(row.lastObject, name, row[0]).path isEqual:@"/f1/clip.mp4"]);
    CHECK(masterHits == masters && mediaHits == media);
    CHECK([coverSearches isEqual:@[name]]); // no per-track search for the same soundtrack
    // A full first page would normally invite a narrower artist-qualified network search.
    // For album-page rows the same record set must be used even after a localized credit misses.
    NSString *page = @"Page soundtrack";
    NSArray *pageTracks = [tracks arrayByAddingObject:@{@"attributes": @{@"name": @"Catalog Sentinel", @"artistName": @"Singer"}}];
    NSMutableArray *full = [NSMutableArray arrayWithObject:release(page, @"Various Artists", NO, pageTracks)];
    while (full.count < 10) [full addObject:release(@"Other release", @"Another artist", NO, @[])];
    coverResults = full;
    [coverSearches removeAllObjects];
    __block BOOL rowDone = NO;
    SGMotionAlbumRowMatcher(@"Spotify soundtrack credit", page, 720, ^(SGMotionRowMatch match) {
        CHECK(sentinelReads == 1); // catalog normalization finished before the first cell
        CHECK(match && !match(@"현지화된 이름", @"Drive"));
        CHECK(match(@"Ed Sheeran", @"Drive"));
        CHECK(sentinelReads == 1);
    }, ^(NSURL *clip) { CHECK([clip.path isEqual:@"/f1/clip.mp4"]); rowDone = YES; });
    waitFor(^BOOL { return rowDone; });
    CHECK([coverSearches isEqual:@[page]]);
    CHECK(!songCover(@"Someone Else", name, @"Drive"));
    CHECK(!songCover(@"Ed Sheeran", name, @"Different Song"));
    coverResults = @[release(@"Starboy", @"The Weeknd", NO, @[@{@"attributes":
        @{@"name": @"Starboy (feat. Daft Punk)", @"artistName": @"The Weeknd"}}])];
    CHECK(songCover(@"The Weeknd, Daft Punk", @"Starboy", @"Starboy"));
    CHECK(songCover(@"The Weeknd", @"Starboy", @"A song missing from the returned track list"));
    coverResults = @[release(@"Soundtrack", @"Cast", NO, @[@{@"attributes":
        @{@"name": @"Theme (2017 Remaster)", @"artistName": @"Singer"}}])];
    CHECK(songCover(@"Singer", @"Soundtrack", @"Theme - 2021 Remaster"));
    // Apple Music names an EP "X - EP" where Spotify names it "X" (aespa's Rich Man, issue #43).
    NSString *ep = @"Rich Man - The 6th Mini Album";
    coverResults = @[release([ep stringByAppendingString:@" - EP"], @"aespa", NO,
        @[@{@"attributes": @{@"name": @"Rich Man", @"artistName": @"aespa"}}])];
    BOOL epCover = songCover(@"aespa", ep, nil) != nil;
    __block BOOL epRow = NO, epRowClip = NO;
    SGMotionAlbumRowMatcher(@"aespa", ep, 720, ^(SGMotionRowMatch match) { CHECK(!match); },
        ^(NSURL *clip) { epRowClip = clip != nil; epRow = YES; });
    waitFor(^BOOL { return epRow; });
    fprintf(stderr, "motion: EP suffix cover %s, rows %s\n", epCover ? "PASS" : "FAIL", epRowClip ? "PASS" : "FAIL");
    CHECK(epCover && epRowClip);
    // Apple Music names a single "X - Single" where Spotify names it "X" (MEOVV's HANDS UP, issue #48). Beside an
    // album of the same name it is the album's lead single, and a still one proves nothing.
    NSArray *handsUp = @[@{@"attributes": @{@"name": @"HANDS UP", @"artistName": @"MEOVV"}}];
    coverResults = @[clipRelease(@"HANDS UP - Single", @"MEOVV", YES, handsUp, @"single")];
    BOOL singleCover = [songCover(@"MEOVV", @"HANDS UP", nil).path isEqual:@"/single/clip.mp4"];
    BOOL singleSong = [songCover(@"MEOVV", @"HANDS UP", @"HANDS UP").path isEqual:@"/single/clip.mp4"];
    __block BOOL singleRow = NO, singleRowClip = NO;
    SGMotionAlbumRowMatcher(@"MEOVV", @"HANDS UP", 720, ^(SGMotionRowMatch match) { CHECK(!match); },
        ^(NSURL *clip) { singleRowClip = [clip.path isEqual:@"/single/clip.mp4"]; singleRow = YES; });
    waitFor(^BOOL { return singleRow; });
    coverResults = @[clipRelease(@"Whiplash - Single", @"aespa", YES, tracks, @"lead"), clipRelease(@"Whiplash", @"aespa", NO, tracks, @"album")];
    BOOL albumOverLead = [songCover(@"aespa", @"Whiplash", nil).path isEqual:@"/album/clip.mp4"];
    __block BOOL leadRow = NO, leadRowClip = NO;
    SGMotionAlbumRowMatcher(@"aespa", @"Whiplash", 720, ^(SGMotionRowMatch match) { CHECK(!match); },
        ^(NSURL *clip) { leadRowClip = [clip.path isEqual:@"/album/clip.mp4"]; leadRow = YES; });
    waitFor(^BOOL { return leadRow; });
    coverResults = @[@{@"attributes": @{@"name": @"Still Single - Single", @"artistName": @"Artist", @"isSingle": @YES}}];
    BOOL stillSingle = !songCover(@"Artist", @"Still Single", nil);
    // The singer's same-named single must not stand in for the soundtrack that holds the song.
    NSArray *theme = @[@{@"attributes": @{@"name": @"Theme Park", @"artistName": @"Singer"}}];
    coverResults = @[clipRelease(@"Theme Park - Single", @"Singer", YES, theme, @"lead-single"), clipRelease(@"Theme Park", @"Various Artists", NO, theme, @"ost")];
    stillSingle = stillSingle && [songCover(@"Singer", @"Theme Park", @"Theme Park").path isEqual:@"/ost/clip.mp4"];
    // Spotify's own "X - Single" keeps Apple's single apart from its album "X".
    coverResults = @[clipRelease(@"Spring - Single", @"Band", YES, @[], @"spring-single"), clipRelease(@"Spring", @"Band", NO, @[], @"spring-album")];
    stillSingle = stillSingle && [songCover(@"Band", @"Spring - Single", nil).path isEqual:@"/spring-single/clip.mp4"]
        && [songCover(@"Band", @"Spring", nil).path isEqual:@"/spring-album/clip.mp4"];
    fprintf(stderr, "motion: single suffix cover %s, song %s, rows %s; album over its lead single %s, rows %s; still single %s\n",
            singleCover ? "PASS" : "FAIL", singleSong ? "PASS" : "FAIL", singleRowClip ? "PASS" : "FAIL",
            albumOverLead ? "PASS" : "FAIL", leadRowClip ? "PASS" : "FAIL", stillSingle ? "PASS" : "FAIL");
    CHECK(singleCover && singleSong && singleRowClip && albumOverLead && leadRowClip && stillSingle);

    coverResults = @[release(@"Original (Deluxe)", @"Artist", NO, tracks)];
    CHECK(!album(@"Original"));
    CHECK(album(@"Original (Deluxe)")); // the bare miss must not mask the edition's hit
    coverResults = @[release(@"Only Remaster - 2011 Remaster", @"Various Artists", NO, tracks)];
    CHECK(!songCover(@"Ed Sheeran", @"Only Remaster", @"Drive"));
    coverResults = @[release(@"Single Trap", @"Ed Sheeran", YES, tracks)];
    CHECK(!songCover(@"Ed Sheeran", @"Single Trap", @"Drive"));
    coverResults = @[release(@"Ambiguous", @"Various Artists", NO, tracks), release(@"Ambiguous", @"Another Album Artist", NO, tracks)];
    CHECK(!songCover(@"Ed Sheeran", @"Ambiguous", @"Drive"));
    coverResults = @[release(@"Cast Recording", @"Stage Cast", NO, tracks)];
    CHECK(songCover(@"Ed Sheeran", @"Cast Recording", @"Drive"));
    CHECK(!songCover(@"Ed Sheeran & Band", @"Cast Recording", @"Drive"));
    NSString *hits = @"Greatest Hits";
    coverResults = @[@{@"attributes": @{@"name": hits, @"artistName": @"Artist", @"isSingle": @NO}},
                     release(hits, @"Other Band", NO, @[@{@"attributes": @{@"name": @"Theme", @"artistName": @"Artist"}}])];
    BOOL stayedStill = !songCover(@"Artist", hits, @"Theme");
    __block BOOL exactStill = NO;
    SGMotionPageAlbumCover(@"Artist", hits, 720, ^(NSURL *file, BOOL identified) { CHECK(!file && identified); exactStill = YES; });
    waitFor(^BOOL { return exactStill; });
    [coverSearches removeAllObjects];
    coverResults = @[];
    CHECK(!songCover(@"Solo", @"Absent", @"Theme"));
    coverResults = @[release(@"Different Title", @"Artist", NO, tracks)];
    CHECK(!songCover(@"Solo", @"Short result", @"Theme"));
    CHECK(stayedStill);
    CHECK(([coverSearches isEqual:@[@"Absent", @"Short result"]]));
    coverResults = nil;
}
static NSData *makeLogo(BOOL red) {
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat];
    format.scale = 1; format.opaque = YES;
    return [[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(1024, 1024) format:format]
        PNGDataWithActions:^(UIGraphicsImageRendererContext *context) {
            [(red ? UIColor.redColor : UIColor.blueColor) setFill];
            UIRectFill(CGRectMake(0, 0, 1024, 1024));
        }];
}
static BOOL isBlue(UIImage *image) {
    CHECK(image.CGImage);
    uint8_t pixel[4] = {0};
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(pixel, 1, 1, 8, 4, space, kCGImageAlphaPremultipliedLast);
    CGContextDrawImage(context, CGRectMake(0, 0, 1, 1), image.CGImage);
    CGContextRelease(context); CGColorSpaceRelease(space);
    return pixel[2] > 240 && pixel[0] < 10;
}

int main(int argc, char **argv) {
    @autoreleasepool {
        __block BOOL visible = YES;
        __attribute__((objc_precise_lifetime)) SGMotionFollower *follower = [[SGMotionFollower alloc] initWithBegin:^BOOL(NSString *uri, SPTPlayerState *value) {
            return visible;
        } found:^(NSString *uri, NSURL *file) {}];
        observer = follower;
        requested = [NSMutableArray array];
        tickets = [NSMutableDictionary dictionary];
        state = [SPTPlayerState new];
        state.track = [SPTPlayerTrack new];
        state.track.URI = @"spotify:track:one";
        state.track.metadata = @{};
        publish(state);
        state.track.metadata = @{@"canvas.url": @"https://fixture.invalid/late.mp4"};
        CHECK([observer respondsToSelector:@selector(playerStateDidReport:)]);
        publish(state);
        CHECK([walkCanvas.absoluteString isEqual:@"https://fixture.invalid/late.mp4"]);
        [requested removeAllObjects];
        SPTPlayerTrack *a = [SPTPlayerTrack new]; a.URI = @"spotify:track:a";
        a.trackTitle = @"OMG!"; a.artistName = @"Tiësto";
        a.metadata = @{@"album_title": @"F1 The Album", @"album_uri": @"spotify:album:0000000000000000000001", @"artist_name": @"Tiësto", @"artist_name:1": @"Sexyy Red"};
        SPTPlayerTrack *b = [SPTPlayerTrack new]; b.URI = @"spotify:track:b";
        state.future = @[a]; publish(state);
        CHECK(([walkEvidence isEqual:@[@"Tiësto, Sexyy Red", @"F1 The Album", @"OMG!", @"spotify:album:0000000000000000000001"]]));
        CHECK(([requested isEqual:@[@"spotify:track:a"]]));
        SGMotionTicket *old = tickets[a.URI];
        state.future = @[b]; publish(state);
        CHECK(old.cancelled);
        CHECK(([requested isEqual:@[@"spotify:track:a", @"spotify:track:b"]]));
        publish(state);
        CHECK(requested.count == 2);
        state.future = @[]; publish(state);
        CHECK(tickets[b.URI].cancelled);
        state.future = (id)@[@"invalid"]; publish(state);
        CHECK(requested.count == 2);
        state.future = @[b]; advanceAllowed = NO; publish(state);
        CHECK(requested.count == 2);
        advanceAllowed = YES; state.isPaused = YES; publish(state);
        CHECK(requested.count == 3 && [requested.lastObject isEqual:b.URI]);
        old = tickets[b.URI];
        state.track = b; publish(state);
        CHECK(old.cancelled);
        CHECK(requested.count == 4); // only B's own fetch, not another B ahead
        advanceAllowed = NO;
        state.track = a; state.future = @[b]; publish(state);
        CHECK(requested.count == 5 && [requested.lastObject isEqual:a.URI]);
        advanceAllowed = YES;
        [follower restart];
        SGMotionTicket *current = tickets[a.URI], *ahead = tickets[b.URI];
        NSUInteger beforeSuspending = requested.count;
        visible = NO;
        [follower restart];
        CHECK(current.cancelled && ahead.cancelled);
        CHECK(requested.count == beforeSuspending);
        visible = YES;
        [follower restart];
        CHECK(requested.count == beforeSuspending + 2);

        NSURL *root = [[NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES]
            URLByAppendingPathComponent:NSUUID.UUID.UUIDString isDirectory:YES];
        CHECK([NSFileManager.defaultManager createDirectoryAtURL:root withIntermediateDirectories:YES attributes:nil error:nil]);
        store = argc == 3 ? [NSURL fileURLWithPath:@(argv[2])] : [root URLByAppendingPathComponent:@"answers.plist"];
        if (argc != 3) CHECK(([@{@"album\n4\nartist\nexpired": @{@"url": @"https://fixture.invalid/expired.mp4",
            @"at": [NSDate dateWithTimeIntervalSinceNow:-8 * 24 * 3600]},
            @"album\n1\nartist\noriginal": @{@"url": @"https://fixture.invalid/wrong-edition.mp4", @"at": NSDate.date},
            @"album\nsong4\npink floyd\nlegacy still\none": @{@"url": @"", @"identified": @NO, @"at": NSDate.date},
            @"album\nsong4\npink floyd\nlegacy clip\none": @{@"url": @"https://fixture.invalid/legacy-clip.mp4", @"at": NSDate.date},
            @"album\n4\nartist\nsaved": @{@"url": @"https://fixture.invalid/saved.mp4", @"at": NSDate.date}}
            writeToURL:store atomically:YES]));
        NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
        NSString *tokenKey = @"spotifyglass.motion.token";
        id prior = [defaults objectForKey:tokenKey];
        NSData *claims = [NSJSONSerialization dataWithJSONObject:@{@"exp": @4102444800} options:0 error:nil];
        [defaults setObject:[NSString stringWithFormat:@"e30.%@.test", [claims base64EncodedStringWithOptions:0]] forKey:tokenKey];
        CHECK([NSURLProtocol registerClass:CatalogProtocol.class]);
        if (argc == 3) {
            BOOL first = [@(argv[1]) isEqual:@"seed"];
            coverSearches = [NSMutableArray array];
            coverResults = first ? @[release(@"Ordinary", @"Solo", NO, @[@{@"attributes": @{@"name": @"One", @"artistName": @"Solo"}}])] : @[];
            CHECK(songCover(@"Solo", @"Ordinary", first ? @"One" : @"Two"));
            if (first) {
                CHECK(coverSearches.count == 1);
                waitFor(^BOOL { return [NSDictionary dictionaryWithContentsOfURL:store].count > 0; });
            }
            else CHECK(!coverSearches.count && !masterHits && !mediaHits);
            NSString *uri = @"spotify:album:0000000000000000000001";
            barcodeReply = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:@"fixtures/196589805232.json"] options:0 error:nil];
            coverResults = barcodeReply[@"data"];
            spotifyUPC = @"5054197493980";
            expectedTrack = first ? @"spotify:track:0000000000000000000002" : nil;
            songsReply = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:@"fixtures/GBN9Y2200015.json"] options:0 error:nil];
            CHECK([coverWithURI(@"The Dark Side Of The Moon (50th Anniversary) [2023 Remaster]", @"Speak to Me - 2023 Remaster", uri).path isEqual:@"/1665303755/clip.mp4"]);
            if (first) {
                CHECK(metadataGets == 1 && barcodeGets == 1 && recordingReads == 1);
                waitFor(^BOOL {
                    for (NSDictionary *entry in [NSDictionary dictionaryWithContentsOfURL:store].allValues)
                        if ([entry[@"url"] hasSuffix:@"/1665303755/clip.mp4"]) return YES;
                    return NO;
                });
            } else CHECK(!metadataGets && !barcodeGets && !coverSearches.count && !masterHits && !mediaHits);
            if (prior) [defaults setObject:prior forKey:tokenKey]; else [defaults removeObjectForKey:tokenKey];
            CHECK([NSFileManager.defaultManager removeItemAtURL:root error:nil]);
            return 0;
        }
        checkSoundtrack();
        checkBarcode();
        CHECK([album(@"Saved").absoluteString isEqual:@"https://fixture.invalid/saved.mp4"]);
        for (NSUInteger i = 0; i < 201; i++) {
            NSString *name = [NSString stringWithFormat:@"Album %lu", (unsigned long)i];
            CHECK(album(name) != nil);
        }
        waitFor(^BOOL {
            return [NSDictionary dictionaryWithContentsOfURL:store][@"album\n4\nartist\nalbum 200"] != nil;
        });
        NSDictionary *saved = [NSDictionary dictionaryWithContentsOfURL:store];
        CHECK(saved.count == 200 && !saved[@"album\n4\nartist\nexpired"] && !saved[@"album\n4\nartist\nalbum 0"]);
        edition = @"second";
        CHECK([album(@"Album 200").absoluteString isEqual:@"https://fixture.invalid/first/Album-200/clip.mp4"]);
        CHECK([album(@"Album 0").absoluteString isEqual:@"https://fixture.invalid/second/Album-0/clip.mp4"]);

        editorialVideos = @{
            @"motionTallVideo3x4": @{@"video": @"https://fixture.invalid/tall/master.m3u8"},
            @"motionDetailTall": @{@"video": @"https://fixture.invalid/detail-tall/master.m3u8"},
            @"motionSquareVideo1x1": @{@"video": @"https://fixture.invalid/square/master.m3u8"},
            @"motionDetailSquare": @{@"video": @"https://fixture.invalid/detail-square/master.m3u8"},
        };
        CHECK([album(@"All formats").absoluteString isEqual:@"https://fixture.invalid/tall/clip.mp4"]);
        editorialVideos = @{
            @"motionDetailTall": @{@"video": @"https://fixture.invalid/detail-tall/master.m3u8"},
            @"motionSquareVideo1x1": @{@"video": @"https://fixture.invalid/square/master.m3u8"},
            @"motionDetailSquare": @{@"video": @"https://fixture.invalid/detail-square/master.m3u8"},
        };
        CHECK([album(@"Detail tall").absoluteString isEqual:@"https://fixture.invalid/detail-tall/clip.mp4"]);
        editorialVideos = @{
            @"motionSquareVideo1x1": @{@"video": @"https://fixture.invalid/square/master.m3u8"},
            @"motionDetailSquare": @{@"video": @"https://fixture.invalid/detail-square/master.m3u8"},
        };
        CHECK([album(@"Square fallback").absoluteString isEqual:@"https://fixture.invalid/square/clip.mp4"]);
        editorialVideos = @{
            @"motionDetailSquare": @{@"video": @"https://fixture.invalid/detail-square/master.m3u8"},
        };
        CHECK([album(@"Detail square fallback").absoluteString isEqual:@"https://fixture.invalid/detail-square/clip.mp4"]);
        editorialVideos = nil;

        redLogo = makeLogo(YES); blueLogo = makeLogo(NO);
        for (NSUInteger i = 0; i < 5; i++)
            CHECK(!isBlue(logo([NSString stringWithFormat:@"Singer %lu", (unsigned long)i])));
        blue = YES;
        CHECK(!isBlue(logo(@"Singer 4")));
        CHECK(isBlue(logo(@"Singer 0"))); // five 4 MiB rasters cannot all remain inside 16 MiB
        [NSURLProtocol unregisterClass:CatalogProtocol.class];
        if (prior) [defaults setObject:prior forKey:tokenKey]; else [defaults removeObjectForKey:tokenKey];
        waitFor(^BOOL {
            return [[NSDictionary dictionaryWithContentsOfURL:store][@"album\n4\nartist\nalbum 0"][@"url"]
                isEqual:@"https://fixture.invalid/second/Album-0/clip.mp4"];
        });
        CHECK([NSFileManager.defaultManager removeItemAtURL:root error:nil]);
        puts("motion state: late Canvas, bounded catalog/album store and logo pixel budget passed");
        return 0;
    }
}
