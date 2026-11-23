#import <Foundation/Foundation.h>
#import "Shared/SponsorBlock/SponsorBlock.h"
#import "App/About/SGDiagnosticRedaction.h"
#import <math.h>

static NSString *const kEpisode = @"0123456789ABCDEFGHIJKL";
static NSString *const kURI = @"spotify:episode:0123456789ABCDEFGHIJKL";
static NSData *fixture;
#define CHECK(test, message) do { if (!(test)) { NSLog(@"FAIL: %s", message); return NO; } } while (0)

// Only the external fetch, seek and notice boundaries are doubled; parser and session are production.
@interface SBProbe : NSObject
@property (nonatomic, strong) SGSponsorBlockSession *session;
@property (nonatomic, strong) NSMutableArray<NSNumber *> *seeks;
@property (nonatomic, strong) NSMutableArray<NSString *> *requests;
@property (nonatomic, copy) dispatch_block_t undo;
@property (nonatomic, copy) dispatch_block_t ask;
@property (nonatomic) double time, deadline;
// The player's state can land before the observer gets another report.
@property (nonatomic) double liveBase, liveStamp;
@property (nonatomic) BOOL holdSeek;
@property (nonatomic, copy) dispatch_block_t wake;
@property (nonatomic, strong) NSUserDefaults *stats;
@property (nonatomic, copy) NSString *suite;
@property (nonatomic, copy) SGSponsorBlockReply pendingReply;
@property (nonatomic) BOOL deferReply;
- (instancetype)initWithStatus:(NSInteger)status categories:(NSSet *)categories body:(NSData *)body;
- (void)at:(double)position;
@end
@implementation SBProbe
- (instancetype)initWithStatus:(NSInteger)status categories:(NSSet *)categories body:(NSData *)body {
    NSMutableDictionary *rules = [NSMutableDictionary dictionary];
    for (NSString *category in categories) rules[category] = @(SGBlockAuto);
    return [self initWithStatus:status rules:rules minimum:1 respect:NO body:body];
}
- (instancetype)initWithStatus:(NSInteger)status rules:(NSDictionary *)rules minimum:(double)minimum
                       respect:(BOOL)respect body:(NSData *)body {
    if ((self = [super init])) {
        _suite = NSUUID.UUID.UUIDString;
        _stats = [[NSUserDefaults alloc] initWithSuiteName:_suite];
        _seeks = [NSMutableArray array]; _requests = [NSMutableArray array];
        __weak SBProbe *weak = self;
        _session = [[SGSponsorBlockSession alloc] initWithBehaviors:rules minimum:minimum respectManual:respect
            fetch:^(NSString *episode, NSSet *selected, SGSponsorBlockReply reply) {
                SBProbe *probe = weak;
                [probe.requests addObject:episode];
                if (probe.deferReply) probe.pendingReply = reply;
                else reply(SGSponsorBlockParse(body, status, episode));
            } seek:^(double seconds) {
                [weak.seeks addObject:@(seconds)];
                if (!weak.holdSeek) [weak liveAt:seconds];
            }
            record:^dispatch_block_t(double seconds) { return SGSponsorBlockRecordSkip(weak.stats, seconds); }
            notice:^(BOOL ask, SGSponsorBlockAction action) {
                if (ask) weak.ask = action; else weak.undo = action;
            }];
        _session.now = ^{ return weak.time; };
        _session.readLive = ^BOOL(NSString *episode, SGSponsorBlockReading *sample) {
            if (![episode isEqual:kEpisode]) return NO;
            double rate = weak.session.playbackRate;
            *sample = (SGSponsorBlockReading){weak.liveBase + (weak.time - weak.liveStamp) * rate, weak.liveStamp, rate, YES};
            return YES;
        };
        _session.schedule = ^dispatch_block_t(double delay, dispatch_block_t fire) {
            weak.deadline = weak.time + delay;
            weak.wake = fire;
            return ^{ weak.wake = nil; };
        };
    }
    return self;
}
- (void)dealloc { [_stats removePersistentDomainForName:_suite]; }
- (void)liveAt:(double)position {
    self.time = nextafter(self.time, INFINITY);
    self.liveStamp = self.time;
    self.liveBase = position;
}
- (void)at:(double)position {
    [self liveAt:position];
    self.session.reportTimestamp = self.liveStamp;
    [self.session observeURI:kURI position:position duration:120 playing:YES enabled:YES];
}
@end

static SBProbe *probe(NSInteger status) {
    return [[SBProbe alloc] initWithStatus:status categories:[NSSet setWithObject:@"sponsor"] body:fixture];
}

static SBProbe *probeWithRanges(NSArray<NSArray<NSNumber *> *> *ranges) {
    NSMutableArray *segments = [NSMutableArray array];
    for (NSArray *range in ranges) {
        [segments addObject:@{@"segment": range, @"category": @"sponsor", @"actionType": @"skip",
                              @"UUID": [NSString stringWithFormat:@"segment-%lu", (unsigned long)segments.count]}];
    }
    NSData *body = [NSJSONSerialization dataWithJSONObject:@[@{@"videoID": kEpisode, @"segments": segments}]
        options:0 error:nil];
    return [[SBProbe alloc] initWithStatus:200 categories:[NSSet setWithObject:@"sponsor"] body:body];
}

static BOOL overlappingStaleReport(void) {
    SBProbe *p = probeWithRanges(@[@[@10, @30], @[@15, @20]]);
    [p at:16];
    dispatch_block_t undo = p.undo;
    [p at:16];
    CHECK([p.seeks isEqual:@[@30.05]] && p.undo == undo,
          "nested overlap plus stale report must not rewind playback or replace Undo");
    return YES;
}

static BOOL pendingSkipTarget(void) {
    SBProbe *p = probeWithRanges(@[@[@1, @8], @[@10, @30], @[@50, @60]]);
    [p at:16];
    // Replay the older sample, not a newly timestamped manual scrub.
    [p.session observeURI:kURI position:4 duration:120 playing:YES enabled:YES];
    CHECK([p.seeks isEqual:@[@30.05]], "pending forward seek ignores stale positions in an older unhandled range");
    [p at:30.05];
    [p at:50];
    CHECK(([p.seeks isEqual:@[@30.05, @60.05]]), "settled skip permits a later forward skip");
    return YES;
}

static BOOL mergedChain(void) {
    SBProbe *p = probeWithRanges(@[@[@10, @30], @[@28, @40]]);
    [p at:16];
    CHECK([p.seeks isEqual:@[@40.05]], "overlapping chain skips once to its furthest end plus existing seek padding");
    return YES;
}

static BOOL adjacentChain(void) {
    SBProbe *p = probeWithRanges(@[@[@10, @30], @[@28, @40], @[@40, @45]]);
    [p at:16];
    CHECK([p.seeks isEqual:@[@45.05]], "adjacent selected segment extends the full transitive range");
    return YES;
}

static BOOL mergedUndo(void) {
    SBProbe *p = probeWithRanges(@[@[@10, @30], @[@28, @40]]);
    [p at:16];
    [p at:40.05];
    p.undo();
    [p at:9.75]; [p at:16]; [p at:29]; [p at:35]; [p at:40.05];
    CHECK(([p.seeks isEqual:@[@40.05, @9.75]]), "Undo of a settled merged skip plays through both segments");
    return YES;
}

static BOOL laterSegmentAfterUndo(void) {
    SBProbe *p = probeWithRanges(@[@[@10, @30], @[@28, @40], @[@50, @60]]);
    [p at:16];
    p.undo();
    [p at:16]; [p at:35]; [p at:40.05]; [p at:50];
    CHECK(([p.seeks isEqual:@[@40.05, @9.75, @60.05]]),
          "Undo supersedes pending seek but does not suppress a non-overlapping later segment");
    return YES;
}

static BOOL parsing(void) {
    NSArray<SGSponsorBlockSegment *> *segments = SGSponsorBlockParse(fixture, 200, kEpisode);
    CHECK(segments.count == 4, "parser rejects malformed, non-skip and duplicate segments");
    CHECK(([[segments valueForKey:@"uuid"] isEqual:@[@"sponsor", @"intro", @"too-short", @"selfpromo"]]),
          "segments sorted by start, only full episode-ID matches");
    CHECK(segments[0].start == 10 && segments[0].end == 20, "API seconds survive parsing");
    CHECK(!SGSponsorBlockParse([@"{}" dataUsingEncoding:NSUTF8StringEncoding], 200, kEpisode),
          "malformed API envelope fails closed");
    return YES;
}

static BOOL categories(void) {
    SBProbe *p = probe(200);
    [p at:30];
    CHECK(!p.seeks.count, "unselected intro category does not skip");
    [p at:10];
    CHECK([p.seeks isEqual:@[@20.05]], "selected sponsor category skips");
    return YES;
}

static BOOL segmentStart(void) {
    SBProbe *p = probe(200);
    [p at:9.99];
    CHECK(!p.seeks.count, "does not skip before segment start");
    [p at:10];
    CHECK([p.seeks isEqual:@[@20.05]] && p.undo != nil, "segment start seeks and offers Undo");
    return YES;
}

static BOOL undoOnce(void) {
    SBProbe *p = probe(200);
    [p at:10];
    p.undo();
    [p at:10]; [p at:11];
    CHECK(([p.seeks isEqual:@[@20.05, @9.75]]), "Undo seeks back and never re-skips the segment");
    return YES;
}

static BOOL staleReports(void) {
    SBProbe *p = probe(200);
    [p at:10]; [p at:10]; [p at:11];
    [p.session observeURI:@"spotify:track:abcdefghijklmnopqrstuv" position:10 duration:120 playing:YES enabled:YES];
    [p at:10];
    CHECK([p.seeks isEqual:@[@20.05]], "stale reports and episode revisits cannot repeat a skip");
    CHECK([p.requests isEqual:@[kEpisode]], "episode revisit reuses session response");
    return YES;
}

static BOOL offAndMusic(void) {
    SBProbe *p = probe(200);
    [p.session observeURI:kURI position:10 duration:120 playing:YES enabled:NO];
    [p.session observeURI:@"spotify:track:0123456789ABCDEFGHIJKL" position:10 duration:120 playing:YES enabled:YES];
    [p.session observeURI:@"https://example.com/episode/0123456789ABCDEFGHIJKL" position:10 duration:120 playing:YES enabled:YES];
    CHECK(!p.requests.count && !p.seeks.count, "off and non-episodes send no requests and never seek");
    return YES;
}

static BOOL failure(void) {
    SBProbe *p = probe(503);
    [p at:10]; [p at:11];
    [p.session observeURI:nil position:0 duration:0 playing:NO enabled:YES];
    [p at:10];
    CHECK(!p.seeks.count && !p.undo, "API failure cannot skip or show a notice");
    CHECK([p.requests isEqual:@[kEpisode]], "failed request stays cached across revisits");
    return YES;
}

static BOOL emptyResponse(void) {
    SBProbe *p = probe(404);
    [p at:10]; [p at:11];
    CHECK(!p.seeks.count && [p.requests isEqual:@[kEpisode]], "404 is a cached empty response");
    return YES;
}

static BOOL staleReplyAndUndo(void) {
    SBProbe *p = probe(200);
    p.deferReply = YES;
    [p at:10];
    [p.session observeURI:@"spotify:track:abcdefghijklmnopqrstuv" position:10 duration:120 playing:YES enabled:YES];
    p.pendingReply(SGSponsorBlockParse(fixture, 200, kEpisode));
    CHECK(!p.seeks.count, "late episode response cannot seek music");
    p.deferReply = NO;
    [p at:10];
    dispatch_block_t oldUndo = p.undo;
    CHECK(oldUndo, "fresh episode reply provides Undo on return");
    p.deferReply = YES;
    [p.session observeURI:@"spotify:episode:abcdefghijklmnopqrstuv" position:10 duration:120 playing:YES enabled:YES];
    oldUndo();
    [p at:10];
    oldUndo();
    CHECK([p.seeks isEqual:@[@20.05]], "Undo cannot act on another episode or a later visit");
    return YES;
}

static BOOL safetyBoundaries(void) {
    SBProbe *p = probe(200);
    [p at:19.75]; [p at:50];
    [p.session observeURI:kURI position:10 duration:120 playing:NO enabled:YES];
    [p.session observeURI:kURI position:10 duration:15 playing:YES enabled:YES];
    [p at:NAN];
    CHECK(!p.seeks.count, "end guard, short segment, pause, duration mismatch and invalid clock never skip");
    return YES;
}

static BOOL requestPrivacy(void) {
    CHECK([SGSponsorBlockEpisodeID(@"https://open.spotify.com/episode/0123456789ABCDEFGHIJKL?si=tracking") isEqual:kEpisode],
          "Spotify web episode URL maps to bare ID");
    NSURLRequest *request = SGSponsorBlockRequest(kEpisode, [NSSet setWithObject:@"sponsor"]);
    CHECK([request.URL.path isEqual:@"/api/skipSegments/83fc0"], "request sends five SHA-256 hex characters, not episode ID");
    NSURLComponents *url = [NSURLComponents componentsWithURL:request.URL resolvingAgainstBaseURL:NO];
    NSMutableDictionary *query = [NSMutableDictionary dictionary];
    for (NSURLQueryItem *item in url.queryItems) query[item.name] = item.value;
    CHECK(([query isEqual:@{@"service": @"Spotify", @"categories": @"[\"sponsor\"]"}]), "request contains only required mapping and categories");
    CHECK(!request.HTTPShouldHandleCookies && request.HTTPBody == nil &&
          [request.allHTTPHeaderFields isEqual:@{@"X-CLIENT-NAME": @"Retrine-SponsorBlock/1"}],
          "no account headers, cookies or request body");
    return YES;
}

static BOOL customServer(void) {
    NSString *key = @"spotifyglass.sponsorblock.serverURL";
    NSUserDefaults *store = NSUserDefaults.standardUserDefaults;
    id original = [store objectForKey:key];
    @try {
        for (NSString *value in @[@"https://example.org:444", @"http://example.org", @"https://", @"not a URL",
                                  @"https://person:secret@example.org", @"https://example.org?tracking=1"]) {
            [store setObject:value forKey:key];
            NSURL *url = SGSponsorBlockRequest(kEpisode, [NSSet setWithObject:@"sponsor"]).URL;
            NSString *address = [value isEqual:@"https://example.org:444"] ? @"example.org" : @"sponsor.ajay.app";
            CHECK([url.scheme isEqual:@"https"] && [url.host isEqual:address] &&
                  [url.path isEqual:@"/api/skipSegments/83fc0"], "use valid custom server; reject invalid stored server");
        }
    } @finally {
        if (original) [store setObject:original forKey:key]; else [store removeObjectForKey:key];
    }
    return YES;
}

static BOOL migration(void) {
    SBProbe *p = probe(200);
    NSUserDefaults *store = p.stats;
    for (NSString *category in SGSponsorBlockCategories()) {
        NSString *old = SGSponsorBlockCategoryKey(category), *key = SGSponsorBlockBehaviorKey(category);
        BOOL autoDefault = [@[@"sponsor", @"interaction", @"selfpromo"] containsObject:category];
        CHECK(SGSponsorBlockReadBehavior(store, category) == (autoDefault ? SGBlockAuto : SGBlockOff),
              "absent old and new keys keep the original defaults");
        CHECK(![store objectForKey:old] && ![store objectForKey:key], "reading defaults does not write migration keys");
        for (NSNumber *enabled in @[@YES, @NO]) {
            [store setObject:enabled forKey:old];
            CHECK(SGSponsorBlockReadBehavior(store, category) == (enabled.boolValue ? SGBlockAuto : SGBlockOff) &&
                  ![store objectForKey:key], "read-only migration from old switch");
            [store setInteger:SGBlockAsk forKey:key];
            CHECK(SGSponsorBlockReadBehavior(store, category) == SGBlockAsk && [[store objectForKey:old] isEqual:enabled],
                  "explicit behavior wins without changing old switch");
            [store setObject:@"1" forKey:key];
            CHECK(SGSponsorBlockReadBehavior(store, category) == SGBlockAsk && [[store objectForKey:key] isEqual:@"1"],
                  "imported string choice remains Ask without rewriting it");
            [store removeObjectForKey:key];
        }
    }
    return YES;
}

static BOOL behaviorsAndMarkers(void) {
    NSDictionary *rules = @{@"intro": @(SGBlockShowOnly), @"sponsor": @(SGBlockAsk), @"selfpromo": @(SGBlockOff)};
    SBProbe *p = [[SBProbe alloc] initWithStatus:200 rules:rules minimum:2 respect:NO body:fixture];
    __block NSUInteger changes = 0;
    id observer = [NSNotificationCenter.defaultCenter addObserverForName:SGSponsorBlockSegmentsDidChangeNotification
        object:p.session queue:nil usingBlock:^(NSNotification *note) { changes++; }];
    @try {
        [p at:0]; NSUInteger before = changes;
        [p at:30]; [p at:60];
        CHECK(([[p.session.visibleSegments valueForKey:@"uuid"] isEqual:@[@"sponsor", @"intro"]] &&
               p.session.episodeDuration == 120 && changes == before && before > 0),
              "eligible Ask and Show-only markers; no notification for position alone");
        CHECK(!p.ask && !p.seeks.count, "Show only and Off never act");
        [p at:12]; dispatch_block_t expired = p.ask;
        CHECK(expired && !p.seeks.count, "Ask waits for Skip");
        [p at:25]; expired();
        CHECK(!p.seeks.count, "expired prompt cannot rewind");
        [p at:13]; p.ask();
        CHECK([p.seeks isEqual:@[@20.05]], "Skip button seeks on acceptance");
        CHECK([p.stats integerForKey:SGKeySponsorBlockCount] == 1 && [p.stats doubleForKey:SGKeySponsorBlockSaved] == 7,
              "record actual remaining seconds, without padding");
        p.undo(); p.undo();
        CHECK(([p.seeks isEqual:@[@20.05, @9.75]] && [p.stats integerForKey:SGKeySponsorBlockCount] == 0 &&
               [p.stats doubleForKey:SGKeySponsorBlockSaved] == 0), "Undo rolls back count and seconds exactly once");
        [p.session observeURI:@"spotify:track:other" position:0 duration:100 playing:YES enabled:YES];
        CHECK(!p.session.visibleSegments.count && !p.session.episodeDuration && changes > before, "music clears markers");
    } @finally { [NSNotificationCenter.defaultCenter removeObserver:observer]; }
    return YES;
}

static BOOL manualAndOwnSeeks(void) {
    NSDictionary *rules = @{@"sponsor": @(SGBlockAuto), @"intro": @(SGBlockAuto)};
    SBProbe *p = [[SBProbe alloc] initWithStatus:200 rules:rules minimum:1 respect:YES body:fixture];
    [p at:8]; [p at:14]; [p at:15];
    CHECK(p.ask && !p.seeks.count, "jump into Auto remains Ask on following reports");
    p.ask(); [p at:20.05]; p.undo(); [p at:9.75]; [p at:10];
    CHECK(([p.seeks isEqual:@[@20.05, @9.75]]), "own skip and undo preserve playthrough");
    SBProbe *resume = [[SBProbe alloc] initWithStatus:200 rules:rules minimum:1 respect:YES body:fixture];
    resume.deferReply = YES;
    [resume at:13]; resume.pendingReply(SGSponsorBlockParse(fixture, 200, kEpisode)); [resume at:13.5];
    CHECK(resume.ask && !resume.seeks.count, "resuming inside a segment before fetch prompts instead");
    SBProbe *shorts = [[SBProbe alloc] initWithStatus:200 rules:rules minimum:11 respect:NO body:fixture];
    [shorts at:10];
    CHECK(!shorts.session.visibleSegments.count && !shorts.seeks.count, "configured minimum excludes skips and markers");
    return YES;
}

static BOOL resetStats(void) {
    SBProbe *p = probe(200);
    [p at:12]; SGSponsorBlockResetStats(p.stats);
    CHECK(![p.stats integerForKey:SGKeySponsorBlockCount] && ![p.stats doubleForKey:SGKeySponsorBlockSaved],
          "reset clears both persisted totals");
    SGSponsorBlockRecordSkip(p.stats, 4);
    p.undo();
    CHECK([p.stats integerForKey:SGKeySponsorBlockCount] == 1 && [p.stats doubleForKey:SGKeySponsorBlockSaved] == 4,
          "Undo from before reset cannot debit a new skip");
    return YES;
}

static BOOL sparsePlayback(void) {
    SBProbe *p = probe(200);
    p.session.playbackRate = 2;
    [p at:9];
    CHECK(!p.seeks.count && p.wake && fabs(p.deadline - .5) < 1e-6, "one wake at segment start at 2x");
    p.time = .5; p.wake();
    CHECK([p.seeks isEqual:@[@20.05]], "wake skips at the boundary without another player report");
    return YES;
}

static BOOL pauseCancelsWake(void) {
    SBProbe *p = probe(200);
    [p at:9];
    dispatch_block_t queued = p.wake;
    CHECK(queued, "playing ahead of a segment schedules its boundary");
    [p.session observeURI:kURI position:9 duration:120 playing:NO enabled:YES];
    p.time = 1; queued();
    CHECK(!p.wake && !p.seeks.count, "pause cancels even a queued boundary");
    return YES;
}

static BOOL delayedLanding(void) {
    SBProbe *p = [[SBProbe alloc] initWithStatus:200 rules:@{@"sponsor": @(SGBlockAuto), @"intro": @(SGBlockAuto)}
        minimum:1 respect:YES body:fixture];
    [p at:10];
    p.time = 12; [p at:32.05];
    CHECK(([p.seeks isEqual:@[@20.05, @40.05]] && !p.ask), "delayed own landing advances at playback rate, not a manual seek");
    return YES;
}

static BOOL promptPreservesUndo(void) {
    NSData *body = [NSJSONSerialization dataWithJSONObject:@[@{@"videoID":kEpisode, @"segments":@[
        @{@"segment":@[@10,@20], @"category":@"sponsor", @"UUID":@"a", @"actionType":@"skip"},
        @{@"segment":@[@18,@30], @"category":@"intro", @"UUID":@"b", @"actionType":@"skip"}]}] options:0 error:nil];
    SBProbe *p = [[SBProbe alloc] initWithStatus:200 rules:@{@"sponsor": @(SGBlockAuto), @"intro": @(SGBlockAsk)}
        minimum:1 respect:YES body:body];
    [p at:10]; dispatch_block_t undo = p.undo;
    [p at:20.05]; CHECK(undo && p.ask, "own skip lands inside Ask");
    undo(); p.ask();
    CHECK(([p.seeks isEqual:@[@20.05, @9.75]]), "offering Ask does not invalidate dispatched Undo; Undo invalidates that Skip");
    return YES;
}

static BOOL expiredUndoLanding(void) {
    NSData *body = [NSJSONSerialization dataWithJSONObject:@[@{@"videoID":kEpisode, @"segments":@[
        @{@"segment":@[@6,@9], @"category":@"sponsor", @"UUID":@"a", @"actionType":@"skip"},
        @{@"segment":@[@10,@20], @"category":@"sponsor", @"UUID":@"b", @"actionType":@"skip"}]}] options:0 error:nil];
    SBProbe *p = [[SBProbe alloc] initWithStatus:200 rules:@{@"sponsor": @(SGBlockAuto)} minimum:1 respect:YES body:body];
    [p at:10]; p.undo();
    p.time = 5; [p at:40]; // no report near the expected Undo landing
    [p at:8];
    CHECK((p.ask && [p.seeks isEqual:@[@20.05, @9.75]]), "a later manual seek near the expired Undo target must Ask");
    return YES;
}

static BOOL privateServerDiagnostic(void) {
    NSDictionary *store = @{SGKeySponsorBlockServer: @"https://private.example/podcasts"};
    NSString *text = @"spotifyglass.sponsorblock.serverURL=https://private.example/podcasts\nkeep";
    CHECK([SGRedactDiagnostics(text, store) isEqual:@"[redacted]=[redacted]\nkeep"], "server key and value redacted from diagnostic text");
    return YES;
}

static BOOL responseCaps(void) {
    NSMutableArray *rows = [NSMutableArray array];
    for (NSUInteger i = 0; i < 240; ++i) {
        NSString *uuid = i ? @(i).stringValue : [@"x" stringByPaddingToLength:512 withString:@"x" startingAtIndex:0];
        [rows addObject:@{@"segment":@[@1,@2], @"category":@"sponsor", @"UUID":uuid, @"actionType":@"skip"}];
    }
    NSData *body = [NSJSONSerialization dataWithJSONObject:@[@{@"videoID":kEpisode, @"segments":rows}] options:0 error:nil];
    NSArray *parsed = SGSponsorBlockParse(body, 200, kEpisode);
    CHECK(parsed.count == 200 && ![[parsed valueForKey:@"uuid"] containsObject:rows[0][@"UUID"]],
          "responses bound retained segments and reject oversized UUIDs");
    return YES;
}

static BOOL boundedRevisits(void) {
    SBProbe *p = probe(200);
    [p at:10];
    for (NSUInteger i = 0; i < 8; ++i)
        [p.session observeURI:[NSString stringWithFormat:@"spotify:episode:%022lu", (unsigned long)i]
                     position:0 duration:120 playing:YES enabled:YES];
    [p at:10];
    CHECK((p.requests.count == 10 && [p.seeks isEqual:@[@20.05, @20.05]]), "evicted episode refetches without retaining old handled UUIDs");
    return YES;
}

static BOOL staleReplyDropped(void) {
    SBProbe *p = probe(200);
    p.deferReply = YES; [p at:10];
    SGSponsorBlockReply stale = p.pendingReply;
    [p.session observeURI:nil position:0 duration:0 playing:NO enabled:YES];
    [p at:10]; stale(SGSponsorBlockParse(fixture, 200, kEpisode)); [p at:10];
    CHECK(p.requests.count == 2 && !p.seeks.count && !p.session.visibleSegments.count,
          "previous visit's pending response cannot populate cache after revisiting");
    return YES;
}

static SBProbe *autoThenAsk(double askStart, double askEnd) {
    NSArray *segments = @[
        @{@"segment":@[@10,@20], @"category":@"sponsor", @"actionType":@"skip", @"UUID":@"auto"},
        @{@"segment":@[@(askStart),@(askEnd)], @"category":@"intro", @"actionType":@"skip", @"UUID":@"ask"}];
    NSData *body = [NSJSONSerialization dataWithJSONObject:@[@{@"videoID":kEpisode, @"segments":segments}] options:0 error:nil];
    return [[SBProbe alloc] initWithStatus:200 rules:@{@"sponsor":@(SGBlockAuto), @"intro":@(SGBlockAsk)}
        minimum:1 respect:YES body:body];
}

static BOOL scrubBeforeLanding(void) {
    SBProbe *p = probeWithRanges(@[@[@10,@20], @[@30,@40]]);
    p.holdSeek = YES;
    [p at:10]; p.time = .1; [p at:5];
    p.time = 10.1;
    if (p.wake && p.deadline <= p.time) p.wake();
    CHECK([p.seeks isEqual:@[@20.05]], "scrub to 5 must not skip 30-40 while the listener is near 15");
    CHECK(p.wake && fabs(p.deadline - 25.1) < 1e-6, "next start follows the reported scrub, not our requested target");
    return YES;
}

static BOOL liveLandingInsideAsk(void) {
    SBProbe *p = autoThenAsk(18, 25);
    p.holdSeek = YES;
    [p at:10];
    p.time = .03; [p liveAt:20.08]; // live player advanced; no landing report
    if (p.wake && p.deadline <= p.time) p.wake();
    CHECK(p.ask && [p.seeks isEqual:@[@20.05]], "landing inside Ask offers Skip without a landing report");
    p.ask();
    CHECK(([p.seeks isEqual:@[@20.05, @25.05]]), "Skip tap uses the confirmed live landing, not the old report");
    return YES;
}

static BOOL staleReportKeepsWake(void) {
    SBProbe *p = probeWithRanges(@[@[@30,@40]]);
    [p at:10];
    double old = p.liveStamp;
    p.time = 5; [p at:15];
    p.session.reportTimestamp = old; // an older report reaches main after the newer one
    [p.session observeURI:kURI position:10 duration:120 playing:YES enabled:YES];
    CHECK(p.wake && fabs(p.deadline - 20) < 1e-3, "a rejected stale report keeps the wake for the next start");
    return YES;
}

static BOOL landingVisibleAfterCheck(void) {
    SBProbe *p = autoThenAsk(18, 25);
    p.holdSeek = YES;
    [p at:10];
    p.time = .03;
    if (p.wake && p.deadline <= p.time) p.wake(); // Spotify still shows the pre-seek state
    p.time = .1; [p liveAt:20.12];               // the landing shows a moment later, with no report
    p.time = .3;
    if (p.wake && p.deadline <= p.time) p.wake();
    CHECK(p.ask && [p.seeks isEqual:@[@20.05]], "landing inside Ask offers Skip once Spotify shows it");
    return YES;
}

static BOOL promptRequiresFreshState(void) {
    SBProbe *p = autoThenAsk(30, 50);
    p.holdSeek = YES;
    [p at:10];
    p.time = 20.5; // even the pre-seek sample's running position now lies in Ask
    if (p.wake) p.wake();
    CHECK(!p.ask && !p.wake, "no post-seek timestamp: no speculative prompt or repeat wake");
    [p at:30.5]; // fresh report restores evaluation
    CHECK(p.ask, "fresh live position offers Ask");
    p.ask();
    CHECK(([p.seeks isEqual:@[@20.05, @50.05]]), "confirmed prompt's tap is accepted");
    return YES;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc != 2 || !(fixture = [NSData dataWithContentsOfFile:@(argv[1])])) {
            NSLog(@"FAIL: API fixture required"); return 1;
        }
        BOOL (*tests[])(void) = {parsing, categories, segmentStart, undoOnce, staleReports, offAndMusic,
                                failure, emptyResponse, staleReplyAndUndo, safetyBoundaries, requestPrivacy,
                                overlappingStaleReport, pendingSkipTarget, mergedChain, adjacentChain,
                                mergedUndo, laterSegmentAfterUndo, customServer, migration, behaviorsAndMarkers,
                                manualAndOwnSeeks, resetStats, sparsePlayback, pauseCancelsWake, delayedLanding,
                                promptPreservesUndo, responseCaps, boundedRevisits, staleReplyDropped, expiredUndoLanding,
                                privateServerDiagnostic, scrubBeforeLanding, liveLandingInsideAsk, promptRequiresFreshState,
                                staleReportKeepsWake, landingVisibleAfterCheck};
        NSUInteger failed = 0;
        for (NSUInteger i = 0; i < sizeof(tests) / sizeof(*tests); i++) if (!tests[i]()) failed++;
        NSLog(@"SponsorBlock: %lu checks, %lu failed", (unsigned long)(sizeof(tests) / sizeof(*tests)), (unsigned long)failed);
        return failed ? 1 : 0;
    }
}
