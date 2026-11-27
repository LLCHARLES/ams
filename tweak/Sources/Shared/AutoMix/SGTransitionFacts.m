#import "AutoMix.h"
#import "SGTransitionFactsInternal.h"
#import "Shared/Player/PlayerState.h"
#import <math.h>

// UID is an NSString on SPTPlayerTrack (Spotify 9.1.90); older builds without it keep nil.
@interface SPTPlayerTrack (SGTransitionIdentity)
@property (nonatomic, readonly) NSString *UID;
@end

NSNotificationName const SGAutoMixTransitionDidChangeNotification = @"SGAutoMixTransitionDidChangeNotification";

@interface SGTransitionFacts ()
- (instancetype)initWithIdentity:(NSArray *)identity kind:(SGTransitionKind)kind
                     timesKnown:(BOOL)known outStart:(double)outStart outEnd:(double)outEnd
                        inStart:(double)inStart inEnd:(double)inEnd;
@end

@implementation SGTransitionFacts
- (instancetype)initWithIdentity:(NSArray *)identity kind:(SGTransitionKind)kind
                     timesKnown:(BOOL)known outStart:(double)outStart outEnd:(double)outEnd
                        inStart:(double)inStart inEnd:(double)inEnd {
    if ((self = [super init])) {
        _fromURI = [identity[0] copy];
        _fromUID = identity[1] == NSNull.null ? nil : [identity[1] copy];
        _toURI = [identity[2] copy];
        _toUID = identity[3] == NSNull.null ? nil : [identity[3] copy];
        _kind = kind;
        _timesKnown = known;
        _outStart = outStart;
        _outEnd = outEnd;
        _inStart = inStart;
        _inEnd = inEnd;
    }
    return self;
}
@end

static SGTransitionFacts *sg_transition;
static NSDictionary *sg_from, *sg_to;
static NSArray *sg_identity;
static SGTransitionSettings sg_settings;

SGTransitionFacts *SGAutoMixCurrentTransition(void) {
    return sg_transition;
}

static BOOL same(id a, id b) {
    return a == b || [a isEqual:b];
}

// Spotify metadata is decimal text, durations/cue-point positions in milliseconds, tempo in BPM.
// Reject partial numbers and nonfinite values rather than turning unknown metadata into a zero.
static BOOL number(id value, double *result) {
    if (![value isKindOfClass:NSString.class] && ![value isKindOfClass:NSNumber.class]) return NO;
    NSScanner *scanner = [NSScanner scannerWithString:[value description]];
    scanner.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    double n;
    if (![scanner scanDouble:&n] || !scanner.isAtEnd || !isfinite(n) || n < 0) return NO;
    *result = n;
    return YES;
}

static BOOL automixKey(NSString *key) {
    return [key hasPrefix:@"automix."];
}

static BOOL hasAutomixMetadata(NSDictionary *metadata) {
    for (NSString *key in metadata) if (automixKey(key)) return YES;
    return NO;
}

static NSDictionary *metadata(SPTPlayerTrack *track, NSDictionary *previous) {
    NSDictionary *raw = track.metadata;
    if (![raw isKindOfClass:NSDictionary.class]) return @{};
    // Position, image metadata and collection updates do not change the upcoming transition.
    if (previous) {
        NSUInteger matched = 0;
        BOOL changed = NO;
        for (id key in raw) {
            if (![key isKindOfClass:NSString.class] || (![key isEqual:@"duration"] && !automixKey(key))) continue;
            if (!same(previous[key], raw[key])) { changed = YES; break; }
            matched++;
        }
        if (!changed && matched == previous.count) return previous;
    }
    NSMutableDictionary *selected = [NSMutableDictionary dictionary];
    for (id key in raw) {
        if ([key isKindOfClass:NSString.class] && ([key isEqual:@"duration"] || automixKey(key)))
            selected[key] = raw[key];
    }
    return selected;
}

static NSString *uid(SPTPlayerTrack *track) {
    id value = [track respondsToSelector:@selector(UID)] ? track.UID : nil;
    return [value isKindOfClass:NSString.class] && [value length] ? value : nil;
}

static SGTransitionFacts *derive(NSArray *identity, NSDictionary *from, NSDictionary *to, SGTransitionSettings settings) {
    BOOL automix = settings.automix;
    SGTransitionKind kind = SGTransitionKindNone;
    if (automix && (hasAutomixMetadata(from) || hasAutomixMetadata(to))) {
        // "default" with both cue points is the native beat-matched path observed on TECHNO BUNKER.
        // A different/partially arrived mode is not a proven Crossfade fallback.
        if (![from[@"automix.mode"] isEqual:@"default"] || ![to[@"automix.mode"] isEqual:@"default"]) return nil;
        double outCue, inCue, outTempo, inTempo;
        if (!number(from[@"automix.fade_out_cuepoint.position"], &outCue) || outCue <= 0 ||
            !number(to[@"automix.fade_in_cuepoint.position"], &inCue) ||
            !number(from[@"automix.fade_out_cuepoint.tempo"], &outTempo) || outTempo <= 0 ||
            !number(to[@"automix.fade_in_cuepoint.tempo"], &inTempo) || inTempo <= 0) return nil;
        kind = SGTransitionKindSpotifyAutomix;
        // Cue points are not fade boundaries. Spotify switches at about 156 s with an outgoing cue
        // of 159.403 s; neither the overlap length nor its incoming end is exposed in this state.
        // Keep all windows unknown rather than invent a beat count or use the crossfade length.
        return [[SGTransitionFacts alloc] initWithIdentity:identity kind:kind timesKnown:NO
                                                 outStart:0 outEnd:0 inStart:0 inEnd:0];
    }
    NSInteger milliseconds = settings.milliseconds;
    if (!settings.crossfade || milliseconds <= 0) return nil;
    kind = SGTransitionKindCrossfade;
    double outDurationMilliseconds, inDurationMilliseconds;
    BOOL known = number(from[@"duration"], &outDurationMilliseconds) && outDurationMilliseconds > 0 &&
                 number(to[@"duration"], &inDurationMilliseconds) && inDurationMilliseconds > 0;
    double outStart = 0, outEnd = 0, inEnd = 0;
    if (known) {
        double seconds = milliseconds / 1000.0;
        outEnd = outDurationMilliseconds / 1000.0;
        outStart = MAX(0, outEnd - seconds);
        inEnd = MIN(seconds, inDurationMilliseconds / 1000.0);
    }
    return [[SGTransitionFacts alloc] initWithIdentity:identity kind:kind timesKnown:known
                                             outStart:outStart outEnd:outEnd inStart:0 inEnd:inEnd];
}

static BOOL sameFacts(SGTransitionFacts *a, SGTransitionFacts *b) {
    if (a == b) return YES;
    return a && b && same(a.fromURI, b.fromURI) && same(a.fromUID, b.fromUID) &&
           same(a.toURI, b.toURI) && same(a.toUID, b.toUID) && a.kind == b.kind &&
           a.timesKnown == b.timesKnown && a.outStart == b.outStart && a.outEnd == b.outEnd &&
           a.inStart == b.inStart && a.inEnd == b.inEnd;
}

void SGAutoMixRefreshTransition(void) {
    SPTPlayerState *state = SGPlayerState();
    id first = [state.future isKindOfClass:NSArray.class] ? state.future.firstObject : nil;
    SPTPlayerTrack *next = [first isKindOfClass:NSClassFromString(@"SPTPlayerTrack")] ? first : nil;
    SPTPlayerTrack *track = [state.track isKindOfClass:NSClassFromString(@"SPTPlayerTrack")] ? state.track : nil;
    NSString *fromURI = SGURIString(track.URI), *toURI = SGURIString(next.URI);
    SGTransitionSettings settings = {0};
    BOOL settingsKnown = SGTransitionSettingsRead(&settings);
    SGTransitionFacts *facts = nil;
    if (settingsKnown && SGPlayerPlaybackIsLocal() && !state.options.repeatingTrack &&
        (settings.automix || (settings.crossfade && settings.milliseconds > 0)) &&
        fromURI.length && toURI.length && [SGURIString(state.contextURI) hasPrefix:@"spotify:playlist:"]) {
        id fromUID = uid(track) ?: NSNull.null, toUID = uid(next) ?: NSNull.null;
        NSDictionary *from = metadata(track, sg_from), *to = metadata(next, sg_to);
        BOOL samePair = same(sg_identity[0], fromURI) && same(sg_identity[1], fromUID) &&
            same(sg_identity[2], toURI) && same(sg_identity[3], toUID);
        if (samePair && from == sg_from && to == sg_to && settings.automix == sg_settings.automix &&
            settings.crossfade == sg_settings.crossfade && settings.milliseconds == sg_settings.milliseconds) return;
        if (!samePair) sg_identity = @[fromURI, fromUID, toURI, toUID];
        sg_from = from; sg_to = to; sg_settings = settings;
        facts = derive(sg_identity, from, to, settings);
    } else {
        sg_identity = nil; sg_from = nil; sg_to = nil;
    }
    if (sameFacts(sg_transition, facts)) return;
    sg_transition = facts;
    [NSNotificationCenter.defaultCenter postNotificationName:SGAutoMixTransitionDidChangeNotification object:nil];
}

@interface SGTransitionObserver : NSObject <SGPlayerStateObserver>
@end
@implementation SGTransitionObserver
- (void)playerStateDidReport:(SPTPlayerState *)state {
    SGAutoMixRefreshTransition();
}
- (void)playerStateDidChange:(SPTPlayerState *)state {}
@end

void SGAutoMixStartTransitionObserver(void) {
    static SGTransitionObserver *observer;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        observer = [SGTransitionObserver new];
        SGAddPlayerStateObserver(observer);
        [NSNotificationCenter.defaultCenter addObserverForName:SGPlayerPlaybackLocationDidChangeNotification
            object:nil queue:nil usingBlock:^(NSNotification *note) { SGAutoMixRefreshTransition(); }];
        SGAutoMixRefreshTransition();
    });
}
