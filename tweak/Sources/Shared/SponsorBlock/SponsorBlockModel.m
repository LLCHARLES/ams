// Adapted from EeveeSpotifyReincarnated (GPL-3), SponsorBlockAPI/Hash/Segment/Options/
// Skipper at 0d9feaa (SponsorBlock also touched in 51cb2dc). Reporting and voting are not ported.
#import "SponsorBlock.h"
#import "Core/SGLog.h"
#import <CommonCrypto/CommonDigest.h>
#import <math.h>

NSArray<NSString *> *SGSponsorBlockCategories(void) {
    return @[@"sponsor", @"selfpromo", @"interaction", @"intro", @"outro", @"preview",
             @"hook", @"filler", @"exclusive_access"];
}

BOOL SGSponsorBlockCategoryDefault(NSString *category) {
    return [@[@"sponsor", @"selfpromo", @"interaction"] containsObject:category];
}

NSString *SGSponsorBlockCategoryKey(NSString *category) {
    return [@"spotifyglass.sponsorblock.category." stringByAppendingString:category];
}

NSString *SGSponsorBlockEpisodeID(NSString *uri) {
    if (![uri isKindOfClass:NSString.class]) return nil;
    NSString *identifier;
    if ([uri hasPrefix:@"spotify:episode:"]) identifier = [uri substringFromIndex:@"spotify:episode:".length];
    else {
        NSURLComponents *url = [NSURLComponents componentsWithString:uri];
        NSArray *parts = url.path.pathComponents;
        if (![url.scheme isEqualToString:@"https"] || ![url.host isEqualToString:@"open.spotify.com"] ||
            parts.count != 3 || ![parts[1] isEqualToString:@"episode"]) return nil;
        identifier = parts[2];
    }
    NSCharacterSet *base62 = [NSCharacterSet characterSetWithCharactersInString:@"0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"];
    return identifier.length == 22 && [identifier rangeOfCharacterFromSet:base62.invertedSet].location == NSNotFound ? identifier : nil;
}

// Same six-second bound as Retrine's lyrics-source requests; this independent transport sends no
// Spotify headers, cookies or credentials, and refuses redirects.
static const NSTimeInterval kRequestTimeoutSeconds = 6;

NSURLRequest *SGSponsorBlockRequest(NSString *episodeID, NSSet<NSString *> *categories) {
    NSData *input = [episodeID dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(input.bytes, (CC_LONG)input.length, digest);
    NSString *prefix = [NSString stringWithFormat:@"%02x%02x%x", digest[0], digest[1], digest[2] >> 4];
    NSMutableArray *selected = [NSMutableArray array];
    for (NSString *category in SGSponsorBlockCategories())
        if ([categories containsObject:category]) [selected addObject:category];
    if (!selected.count) return nil;
    NSData *json = [NSJSONSerialization dataWithJSONObject:selected options:0 error:nil];
    NSURLComponents *url = [NSURLComponents componentsWithString:
        [NSString stringWithFormat:@"%@/api/skipSegments/%@", SGSponsorBlockServer(), prefix]];
    url.queryItems = @[[NSURLQueryItem queryItemWithName:@"service" value:@"Spotify"],
        [NSURLQueryItem queryItemWithName:@"categories" value:[[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding]]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url.URL
        cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:kRequestTimeoutSeconds];
    request.HTTPShouldHandleCookies = NO;
    [request setValue:@"Retrine-SponsorBlock/1" forHTTPHeaderField:@"X-CLIENT-NAME"];
    return request;
}

@interface SGSponsorBlockSegment ()
@property (nonatomic) double start, end;
@property (nonatomic, copy) NSString *category, *uuid;
@end
@implementation SGSponsorBlockSegment
@end

static BOOL secondsValue(id value) {
    return [value isKindOfClass:NSNumber.class] && CFGetTypeID((__bridge CFTypeRef)value) != CFBooleanGetTypeID() &&
        isfinite([value doubleValue]) && [value doubleValue] >= 0;
}

NSArray<SGSponsorBlockSegment *> *SGSponsorBlockParse(NSData *data, NSInteger status, NSString *episodeID) {
    const NSUInteger maximumSegments = 200, maximumUUIDLength = 128;
    if (status == 404) return @[];
    if (status < 200 || status >= 300 || !data.length) return nil;
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![json isKindOfClass:NSArray.class]) return nil;
    NSMutableArray *result = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    for (id entry in json) {
        if (result.count == maximumSegments) break;
        if (![entry isKindOfClass:NSDictionary.class] || ![entry[@"videoID"] isEqual:episodeID]) continue;
        id segments = entry[@"segments"];
        if (![segments isKindOfClass:NSArray.class]) return nil;
        for (id row in segments) {
            if (result.count == maximumSegments) break;
            if (![row isKindOfClass:NSDictionary.class]) continue;
            id pair = row[@"segment"], category = row[@"category"], uuid = row[@"UUID"];
            if (![pair isKindOfClass:NSArray.class] || [pair count] != 2 ||
                !secondsValue(pair[0]) || !secondsValue(pair[1]) ||
                ![category isKindOfClass:NSString.class] || ![SGSponsorBlockCategories() containsObject:category] ||
                ![uuid isKindOfClass:NSString.class] || ![uuid length] || [uuid length] > maximumUUIDLength ||
                ![row[@"actionType"] isEqual:@"skip"] || [seen containsObject:uuid]) continue;
            double start = [pair[0] doubleValue], end = [pair[1] doubleValue];
            if (end <= start) continue;
            SGSponsorBlockSegment *segment = [SGSponsorBlockSegment new];
            segment.start = start; segment.end = end; segment.category = category; segment.uuid = uuid;
            [result addObject:segment];
            [seen addObject:uuid];
        }
    }
    return [result sortedArrayUsingComparator:^NSComparisonResult(SGSponsorBlockSegment *a, SGSponsorBlockSegment *b) {
        return a.start < b.start ? NSOrderedAscending : a.start > b.start ? NSOrderedDescending : NSOrderedSame;
    }];
}

// Eevee's minimum duration, end guard, seek padding and Undo lead-in, in seconds.
static const double kEndGuardSeconds = 0.25;
static const double kSeekPaddingSeconds = 0.05, kUndoLeadSeconds = 0.25;
static const double kSeekDiscontinuitySeconds = 2; // same report tolerance as upstream
static const double kUndoSettlementSeconds = 2;
// Our seek's landing can show in Spotify's live state just after the wake that looks for it.
static const double kSeekConfirmRetrySeconds = 0.25, kSeekConfirmWindowSeconds = 2;
static const NSUInteger kRecentEpisodes = 4;
NSNotificationName const SGSponsorBlockSegmentsDidChangeNotification = @"SGSponsorBlockSegmentsDidChange";

@interface SGSkipRange : NSObject
@property (nonatomic) double start, end;
@property (nonatomic, strong) NSMutableSet<NSString *> *members;
@end
@implementation SGSkipRange
@end

@implementation SGSponsorBlockSession {
    NSSet<NSString *> *_categories;
    NSDictionary<NSString *, NSNumber *> *_behaviors;
    BOOL _respectManual, _playing;
    double _minimum, _lastPosition, _stamp, _previousRate, _manualEntry, _acceptedTimestamp;
    NSArray<SGSkipRange *> *_automatic, *_asks;
    SGSkipRange *_prompt;
    SGSponsorBlockFetch _fetch;
    void (^_seek)(double);
    SGSponsorBlockNotice _notice;
    SGSponsorBlockRecord _record;
    NSMutableDictionary<NSString *, NSArray<SGSponsorBlockSegment *> *> *_cache;
    NSMutableDictionary<NSString *, NSMutableSet<NSString *> *> *_handled;
    NSMutableArray<NSString *> *_recent;
    BOOL _fetching;
    NSString *_episode;
    NSUInteger _visit, _undoTicket, _promptTicket, _wakeTicket;
    dispatch_block_t _cancelWake;
    BOOL _enabled;
    double _seekTarget, _seekExpected, _seekStamp, _seekIssued;
    BOOL _forwardSeek;
}

- (instancetype)initWithBehaviors:(NSDictionary<NSString *, NSNumber *> *)behaviors
                           minimum:(double)minimum respectManual:(BOOL)respectManual
                             fetch:(SGSponsorBlockFetch)fetch seek:(void (^)(double))seek
                            record:(SGSponsorBlockRecord)record notice:(SGSponsorBlockNotice)notice {
    if ((self = [super init])) {
        _behaviors = [behaviors copy];
        NSMutableSet *categories = [NSMutableSet set];
        for (NSString *key in behaviors) if (behaviors[key].integerValue != SGBlockOff) [categories addObject:key];
        _categories = [categories copy]; _minimum = minimum; _respectManual = respectManual;
        _fetch = [fetch copy]; _seek = [seek copy]; _record = [record copy]; _notice = [notice copy];
        _cache = [NSMutableDictionary dictionary]; _handled = [NSMutableDictionary dictionary];
        _recent = [NSMutableArray array];
        _seekTarget = _seekIssued = _acceptedTimestamp = _reportTimestamp = _manualEntry = _lastPosition = NAN;
        _playbackRate = 1;
        _now = ^{ return NSDate.timeIntervalSinceReferenceDate; };
        _visibleSegments = @[];
    }
    return self;
}

// Rebuild only on identity, duration or fetch changes, not every position report.
- (void)publishDuration:(double)duration identityChanged:(BOOL)changed {
    NSMutableArray *visible = [NSMutableArray array], *automatic = [NSMutableArray array], *asks = [NSMutableArray array];
    for (SGSponsorBlockSegment *s in (_episode && _enabled ? _cache[_episode] : nil)) {
        if (![_categories containsObject:s.category] || s.end - s.start < _minimum || s.end > duration) continue;
        [visible addObject:s];
        NSInteger behavior = _behaviors[s.category].integerValue;
        if (behavior == SGBlockShowOnly) continue;
        NSMutableArray *ranges = behavior == SGBlockAuto ? automatic : asks;
        SGSkipRange *range = ranges.lastObject;
        if (!range || behavior == SGBlockAsk || s.start > range.end) {
            range = [SGSkipRange new]; range.start = s.start; range.members = [NSMutableSet set];
            [ranges addObject:range];
        }
        range.end = MAX(range.end, s.end);
        [range.members addObject:s.uuid];
    }
    if (!changed && _episodeDuration == duration && [_visibleSegments isEqual:visible]) return;
    _visibleSegments = [visible copy]; _episodeDuration = duration;
    _automatic = automatic; _asks = asks; _prompt = nil;
    [NSNotificationCenter.defaultCenter postNotificationName:SGSponsorBlockSegmentsDidChangeNotification object:self];
}

- (void)cancelWake {
    ++_wakeTicket;
    if (_cancelWake) { _cancelWake(); _cancelWake = nil; }
}

- (void)dealloc { if (_cancelWake) _cancelWake(); }

- (BOOL)acceptReading:(SGSponsorBlockReading)s report:(BOOL)report {
    if (!isfinite(s.position) || s.position < 0 || !isfinite(s.timestamp) ||
        s.timestamp < _acceptedTimestamp || s.timestamp <= _seekIssued) return NO;
    double now = _now();
    BOOL resume = !isfinite(_lastPosition) || (s.playing && !_playing);
    double expected = _lastPosition + (_playing ? (now - _stamp) * _previousRate : 0);
    BOOL jump = fabs(s.position - expected) > kSeekDiscontinuitySeconds;
    if (isfinite(_seekTarget)) {
        double landing = _seekExpected + (_playing ? (now - _seekStamp) * _previousRate : 0);
        BOOL near = fabs(s.position - landing) <= kSeekDiscontinuitySeconds ||
            (now - _seekIssued <= kUndoSettlementSeconds && fabs(s.position - _seekTarget) <= kSeekDiscontinuitySeconds);
        BOOL landed = near && (!_forwardSeek || s.position >= _seekTarget - kSeekPaddingSeconds);
        // A timer/tap cannot guess whether an inconsistent live pose is a scrub or a
        // seek still in flight. Only a newer player report can establish the new anchor.
        if (!landed && !report) return NO;
        jump = !landed; resume = NO;
        _seekTarget = NAN;
    }
    if (jump || resume) _manualEntry = jump ? s.position : nextafter(s.position, -INFINITY);
    _lastPosition = s.position; _acceptedTimestamp = s.timestamp; _stamp = now;
    _playing = s.playing && _episodeDuration > 0;
    _previousRate = isfinite(s.rate) && s.rate > 0 ? s.rate : 0;
    return YES;
}

- (BOOL)readCurrent {
    SGSponsorBlockReading reading;
    return _enabled && _episode && _readLive && _readLive(_episode, &reading) && [self acceptReading:reading report:NO];
}

- (void)armNext {
    [self cancelWake];
    if (!_schedule || !_enabled || !_playing || !(_previousRate > 0)) return;
    BOOL pending = isfinite(_seekTarget);
    double anchor = pending ? _seekTarget : _lastPosition;
    double next = INFINITY;
    NSSet *handled = _handled[_episode];
    for (NSArray *ranges in @[_automatic ?: @[], _asks ?: @[]]) {
        for (SGSkipRange *range in ranges) {
            if (handled && [range.members isSubsetOfSet:handled]) continue;
            // A seek may land in the middle of a range. Give Spotify one chance
            // to confirm it on main, even when no report accompanies the landing.
            if (pending && range.start <= anchor && anchor < range.end - kEndGuardSeconds) {
                next = anchor; break;
            }
            if (range.start <= anchor) continue;
            next = MIN(next, range.start);
            break;
        }
    }
    if (!isfinite(next)) return;
    // Use the clock anchor, not time spent in the notice/seek callbacks, to find the deadline.
    double delay = MAX(0, (next - anchor) / _previousRate - (_now() - (pending ? _seekIssued : _stamp)));
    [self scheduleWakeAfter:delay];
}

- (void)scheduleWakeAfter:(double)delay {
    NSUInteger ticket = _wakeTicket;
    __weak typeof(self) weakSelf = self;
    _cancelWake = _schedule(delay, ^{
        typeof(self) self = weakSelf;
        if (!self || self->_wakeTicket != ticket) return;
        [self wake];
    });
}

- (void)wake {
    [self cancelWake];
    if ([self readCurrent]) { [self reconcile:_lastPosition]; return; }
    if (_schedule && isfinite(_seekTarget) && _now() - _seekIssued <= kSeekConfirmWindowSeconds)
        [self scheduleWakeAfter:kSeekConfirmRetrySeconds];
}

- (void)seekTo:(double)target {
    [self cancelWake];
    _seekIssued = _seekStamp = _now();
    _forwardSeek = target > _lastPosition;
    _seekTarget = _seekExpected = target;
    _manualEntry = NAN;
    _seek(target);
}

- (void)skip:(SGSkipRange *)range at:(double)position {
    NSMutableSet *handled = _handled[_episode];
    if (!handled) _handled[_episode] = handled = [NSMutableSet set];
    [handled unionSet:range.members];
    _prompt = nil;
    NSUInteger ticket = ++_undoTicket;
    dispatch_block_t subtract = _record(range.end - position); // no seek padding in time saved
    [self seekTo:MIN(_episodeDuration, range.end + kSeekPaddingSeconds)];
    __weak typeof(self) weakSelf = self;
    _notice(NO, ^{
        typeof(self) self = weakSelf;
        if (!self || ticket != self->_undoTicket || ![self readCurrent]) return;
        self->_undoTicket++;
        self->_prompt = nil;
        subtract();
        [self seekTo:MAX(0, range.start - kUndoLeadSeconds)];
        [self armNext];
    });
}

- (BOOL)offerRange:(SGSkipRange *)range ask:(BOOL)ask position:(double)position {
    if (position < range.start || position >= range.end - kEndGuardSeconds ||
        [range.members isSubsetOfSet:_handled[_episode] ?: [NSSet set]]) return NO;
    if (!ask) { [self skip:range at:position]; return YES; }
    if (_prompt == range) return YES;
    _prompt = range;
    NSUInteger ticket = ++_promptTicket;
    __weak typeof(self) weakSelf = self;
    _notice(YES, ^{
        typeof(self) self = weakSelf;
        if (!self || self->_promptTicket != ticket || self->_prompt != range || ![self readCurrent] || !self->_playing ||
            self->_lastPosition < range.start || self->_lastPosition >= range.end - kEndGuardSeconds) return;
        [self skip:range at:self->_lastPosition];
        [self armNext];
    });
    return YES;
}

- (void)reconcile:(double)position {
    if (!_playing || !_enabled || !isfinite(position)) { _prompt = nil; return; }
    BOOL offered = NO;
    for (SGSkipRange *range in _automatic) {
        BOOL ask = _respectManual && _manualEntry >= range.start && _manualEntry < range.end;
        if ([self offerRange:range ask:ask position:position]) { offered = YES; break; }
    }
    if (!offered) for (SGSkipRange *range in _asks) {
        if ([self offerRange:range ask:YES position:position]) { offered = YES; break; }
    }
    if (!offered) _prompt = nil;
    [self armNext];
}

- (void)touchEpisode:(NSString *)episode {
    [_recent removeObject:episode];
    [_recent addObject:episode];
    if (_recent.count <= kRecentEpisodes) return;
    NSString *oldest = _recent.firstObject;
    [_cache removeObjectForKey:oldest];
    [_handled removeObjectForKey:oldest];
    [_recent removeObjectAtIndex:0];
}

- (void)observeURI:(NSString *)uri position:(double)position duration:(double)duration
          playing:(BOOL)playing enabled:(BOOL)enabled {
    [self cancelWake];
    NSString *episode = SGSponsorBlockEpisodeID(uri);
    BOOL changed = (![_episode isEqual:episode] && (_episode || episode)) || _enabled != enabled;
    if (changed) {
        _episode = episode;
        _visit++; _undoTicket++; _fetching = NO;
        _seekTarget = _seekIssued = _lastPosition = _manualEntry = _acceptedTimestamp = NAN;
        _playing = NO;
        if (episode && enabled) [self touchEpisode:episode];
    }
    _enabled = enabled;
    duration = enabled && episode && isfinite(duration) && duration > 0 ? duration : 0;
    if (changed || duration != _episodeDuration) [self publishDuration:duration identityChanged:changed];
    if (!enabled || !episode || !_categories.count) return;

    if (isfinite(_seekTarget)) {
        double now = _now();
        if (_playing) _seekExpected += (now - _seekStamp) * _previousRate;
        _seekStamp = now;
    }
    BOOL accepted = [self acceptReading:(SGSponsorBlockReading){position, _reportTimestamp, _playbackRate, playing} report:YES];
    if (!playing || !duration) { _playing = NO; _prompt = nil; }
    if (_cache[episode]) {
        // A queued report can reset the deadline, but cannot issue an action
        // against a different (or newer) live player state. One it rejects still
        // re-arms from the last accepted anchor, since this call cancelled the wake.
        if (playing && duration && (accepted || isfinite(_seekTarget)) &&
            (_automatic.count || _asks.count) && [self readCurrent]) [self reconcile:_lastPosition];
        else [self armNext];
        return;
    }
    if (_fetching) return;
    _fetching = YES;
    NSUInteger visit = _visit;
    __weak typeof(self) weakSelf = self;
    _fetch(episode, _categories, ^(NSArray<SGSponsorBlockSegment *> *segments) {
        typeof(self) self = weakSelf;
        if (!self || self->_visit != visit) return;
        self->_fetching = NO;
        self->_cache[episode] = segments ?: @[];
        if (!segments) SGLog(@"SponsorBlock: request failed; cached as empty for this episode");
        [self publishDuration:self->_episodeDuration identityChanged:NO];
        if (self->_playing && [self readCurrent]) [self reconcile:self->_lastPosition];
    });
}
@end
