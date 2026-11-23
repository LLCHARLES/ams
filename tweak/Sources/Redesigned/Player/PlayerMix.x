// PlayerMix.h says what this is for.
//
// The facts are read again on their notification and on every player report (reconcile). The last facts with known
// times are kept: when their next song starts playing as their song reaches its window (a skip there is no blend),
// that blend's incoming window is the new song's until playback passes it.
//
// The bands: views of the mod's at the back of Spotify's slider, behind its track and knob, each a flat segment of
// the track's own thickness in a faint white, so they lighten the unplayed bar and never show over the played part.
// Only an end that is the bar's own end is rounded, as the bar's cap is. A time of the song sits where the knob's
// center is at that time, the bar's own ends standing for the start and the end. Spotify keeps three such sliders in
// the tree at once (the full player's, the now playing bar's and the sticky header's, the last two hidden while the
// player shows), so each slider has its own pair, put into it once and never moved, and a hidden slider does nothing.
// A pair is placed again only when the facts, the options, the song's length, its slider's bounds or its track
// (thicker while scrubbed) changed, and placing it sets frames only, which lays out nothing again.
//
// The stage (SGRMixStage): when the playing song reaches its outgoing window, a view of the mod's takes the cover's
// place (SGRPlayerStageCover): a still of the cover as it is (the clip's frame, if one plays in it) gives way to the
// next song's cover, fetched from its metadata ahead of the window and prepared on a serial queue. The display link
// moves it at the screen's rate from the playing song's clock, or the next song's once it is the one playing, and it
// is done exactly as the outgoing window ends. Anything that holds it back (the player not seen among them) or stops
// it, facts that no longer name its blend included, hands the cover back at once.
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Shared/AutoMix/AutoMixPreview.h"
#import "Shared/LocalFiles/LocalFiles.h"
#import "Player.h"
#import "PlayerMix.h"

// UID is an NSString on SPTPlayerTrack (Spotify 9.1.90); older builds without it keep nil (SGTransitionFacts.m).
@interface SPTPlayerTrack (SGRMixIdentity)
@property (nonatomic, readonly) NSString *UID;
@end

static BOOL sg_progressOn, sg_queueOn, sg_artworkOn;

static void readOptions(void) {
    sg_progressOn = SGFlag(SGKeyAutoMixShowProgress, NO);
    sg_queueOn = SGFlag(SGKeyAutoMixShowQueue, NO);
    sg_artworkOn = SGFlag(SGKeyAutoMixArtwork, NO);
}

BOOL SGRMixShowsQueue(void) {
    return sg_queueOn;
}

static NSString *uidOf(SPTPlayerTrack *track) {
    id value = [track respondsToSelector:@selector(UID)] ? track.UID : nil;
    return [value isKindOfClass:NSString.class] && [value length] ? value : nil;
}

BOOL SGRMixTrackIs(SPTPlayerTrack *track, NSString *uri, NSString *uid) {
    static Class trackClass;
    if (!trackClass) trackClass = NSClassFromString(@"SPTPlayerTrack");
    if (!uri || ![track isKindOfClass:trackClass] || ![SGURIString(track.URI) isEqualToString:uri]) return NO;
    NSString *own = uidOf(track);
    return !own || !uid || [own isEqualToString:uid];
}

// Where playback is in the song now, read as the lyrics read it (Shared/Lyrics/KaraokeSource.x).
static double positionOf(SPTPlayerState *state) {
    return state.isPaused ? state.positionAsOfTimestamp : state.position;
}

#pragma mark - the facts

// A next song that starts this far before its blend's outgoing window was skipped to, not blended into.
static const NSTimeInterval kArrivalSlack = 1;

static SGTransitionFacts *sg_facts;     // as last read
static SGTransitionFacts *sg_arrived;   // a blend with known times whose next song is playing, until it passes its window
static SPTPlayerState *sg_fromReport;   // the last report of sg_facts' song, for where it stood when the next one came
static NSUInteger sg_generation;        // advances with every change the bands draw from
static NSHashTable<UISlider *> *sg_sliders;  // every progress slider laid out, weakly

@class SGRMixStage;
static SGRMixStage *sg_mixStage;
static void stageFollows(void);

// Where the song of the last report stood at `state`'s time.
static double fromPositionAt(SPTPlayerState *state) {
    SPTPlayerState *last = sg_fromReport;
    double elapsed = last.isPaused ? 0 : [state.timestamp timeIntervalSinceDate:last.timestamp] * last.playbackSpeed;
    return last.positionAsOfTimestamp + elapsed;
}

static void layOutSliders(void) {
    for (UISlider *slider in sg_sliders.allObjects) [slider setNeedsLayout];
}

static void bandsChanged(void) {
    sg_generation++;
    layOutSliders();
}

static void reconcile(void) {
    SPTPlayerState *state = SGPlayerState();
    SGTransitionFacts *now = SGAutoMixCurrentTransition();
    BOOL changed = NO;
    if (now != sg_facts) {
        SGTransitionFacts *before = sg_facts;
        if (before.timesKnown && before.inEnd > before.inStart && SGRMixTrackIs(state.track, before.toURI, before.toUID)
            && sg_fromReport && fromPositionAt(state) >= before.outStart - kArrivalSlack) {
            sg_arrived = before;
        }
        sg_facts = now;
        sg_fromReport = nil;
        changed = YES;
    }
    if (sg_facts && SGRMixTrackIs(state.track, sg_facts.fromURI, sg_facts.fromUID)) sg_fromReport = state;
    if (sg_arrived && (!SGRMixTrackIs(state.track, sg_arrived.toURI, sg_arrived.toUID) || positionOf(state) >= sg_arrived.inEnd)) {
        sg_arrived = nil;
        changed = YES;
    }
    if (changed) bandsChanged();
    stageFollows();
}

#pragma mark - the bands

static const CGFloat kBandWhiteAlpha = 0.2;

@interface SGRMixBand : UIView
@end
@implementation SGRMixBand
@end

static SGRMixBand *makeBand(void) {
    SGRMixBand *band = [SGRMixBand new];
    band.userInteractionEnabled = NO;
    band.isAccessibilityElement = NO;
    band.backgroundColor = [UIColor colorWithWhite:1 alpha:kBandWhiteAlpha];
    return band;
}

// One slider's pair, in it from when it is made, and what it was last placed by.
@interface SGRMixBands : NSObject
@property (nonatomic, readonly) SGRMixBand *outgoing, *incoming;
@property (nonatomic) BOOL placed;
@property (nonatomic) CGRect bounds, track;
@property (nonatomic) double duration;
@property (nonatomic) NSUInteger generation;
@end

@implementation SGRMixBands
- (instancetype)initIn:(UISlider *)slider {
    if (!(self = [super init])) return nil;
    _outgoing = makeBand();
    _incoming = makeBand();
    _outgoing.hidden = YES;
    _incoming.hidden = YES;
    [slider insertSubview:_outgoing atIndex:0];
    [slider insertSubview:_incoming atIndex:0];
    return self;
}

- (void)hide {
    _outgoing.hidden = YES;
    _incoming.hidden = YES;
    _placed = NO;
}
@end

static char kBandsKey;

static SGRMixBands *bandsOf(UISlider *slider) {
    return objc_getAssociatedObject(slider, &kBandsKey);
}

// Hidden itself or under a hidden view, as Spotify keeps the sliders not shown (alpha is not asked: a faded player
// comes back by its alpha without laying its slider out again).
static BOOL hiddenUp(UIView *view) {
    for (UIView *v = view; v; v = v.superview) {
        if (v.hidden) return YES;
    }
    return NO;
}

static CGFloat thumbCentre(UISlider *slider, CGRect bounds, CGRect track, float value) {
    return CGRectGetMidX([slider thumbRectForBounds:bounds trackRect:track value:value]);
}

// The x of `seconds` into a song `duration` long.
static CGFloat barX(UISlider *slider, CGRect bounds, CGRect track, double seconds, double duration) {
    double share = seconds / duration;
    if (share <= 0) return CGRectGetMinX(track);
    if (share >= 1) return CGRectGetMaxX(track);
    CGFloat start = thumbCentre(slider, bounds, track, slider.minimumValue), end = thumbCentre(slider, bounds, track, slider.maximumValue);
    return start + share * (end - start);
}

// The band over `from` to `to` seconds of the song, at the back of its slider; hidden for a window that is not one.
static void placeBand(SGRMixBand *band, UISlider *slider, CGRect bounds, CGRect track, double from, double to, double duration) {
    if (!(duration > 0 && to > from)) {
        band.hidden = YES;
        return;
    }
    CGFloat start = barX(slider, bounds, track, MAX(0, from), duration), end = barX(slider, bounds, track, MIN(duration, to), duration);
    band.frame = CGRectMake(start, CGRectGetMinY(track), end - start, track.size.height);
    CACornerMask caps = 0;
    if (from <= 0) caps |= kCALayerMinXMinYCorner | kCALayerMinXMaxYCorner;
    if (to >= duration) caps |= kCALayerMaxXMinYCorner | kCALayerMaxXMaxYCorner;
    band.layer.maskedCorners = caps;
    band.layer.cornerRadius = caps ? track.size.height / 2 : 0;
    band.hidden = NO;
}

void SGRPlayerMixSliderLaidOut(UISlider *slider) {
    [sg_sliders addObject:slider];
    SGRMixBands *bands = bandsOf(slider);
    if (!sg_progressOn || !slider.window || hiddenUp(slider)) {
        [bands hide];
        return;
    }
    SPTPlayerState *state = SGPlayerState();
    SGTransitionFacts *facts = sg_facts, *arrived = sg_arrived;
    BOOL outgoing = facts.timesKnown && SGRMixTrackIs(state.track, facts.fromURI, facts.fromUID);
    // A slider gets its pair once there is a window to show.
    if (!bands && !outgoing && !arrived) return;
    CGRect bounds = slider.bounds, track = [slider trackRectForBounds:bounds];
    double duration = state.duration;
    if (bands.placed && bands.generation == sg_generation && bands.duration == duration && CGRectEqualToRect(bands.bounds, bounds)
        && CGRectEqualToRect(bands.track, track)) return;
    if (!bands) {
        bands = [[SGRMixBands alloc] initIn:slider];
        objc_setAssociatedObject(slider, &kBandsKey, bands, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    bands.placed = YES;
    bands.generation = sg_generation;
    bands.duration = duration;
    bands.bounds = bounds;
    bands.track = track;
    placeBand(bands.outgoing, slider, bounds, track, outgoing ? facts.outStart : 0, outgoing ? facts.outEnd : 0, duration);
    placeBand(bands.incoming, slider, bounds, track, arrived.inStart, arrived.inEnd, duration);
}

#pragma mark - the stage's view

// The two covers' cross-dissolve: both whole, in the cover's place, the stage's rounded shape their only clip, so no
// edge of either crosses the other.
@interface SGRMixStageView : UIView
@end

@implementation SGRMixStageView {
    UIView *_outgoing;
    UIImageView *_incoming;
}

- (instancetype)initWithOutgoing:(UIView *)outgoing incoming:(UIImage *)incoming {
    if (!(self = [super initWithFrame:CGRectZero])) return nil;
    self.userInteractionEnabled = NO;
    self.accessibilityElementsHidden = YES;
    self.clipsToBounds = YES;
    self.layer.cornerRadius = SGRRadiusArtwork;
    self.layer.cornerCurve = kCACornerCurveContinuous;
    _outgoing = outgoing;
    _incoming = [[UIImageView alloc] initWithImage:incoming];
    _incoming.contentMode = UIViewContentModeScaleAspectFill;
    _incoming.clipsToBounds = YES;
    [self addSubview:_outgoing];
    [self addSubview:_incoming];
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    _outgoing.frame = self.bounds;
    _incoming.frame = self.bounds;
}

// `progress` 0 is the outgoing cover alone, 1 the incoming one.
- (void)show:(CGFloat)progress {
    CGFloat eased = progress * progress * (3 - 2 * progress);
    _outgoing.alpha = 1 - eased;
    _incoming.alpha = eased;
}

@end

#pragma mark - a track's cover

// The cover a track's metadata names, a local file's cover or Spotify's picture on i.scdn.co: the largest for the
// stage, the 300 px one a row's thumbnail needs (Playing Next) when `small`.
static NSURL *coverURL(SPTPlayerTrack *track, BOOL small) {
    NSDictionary *metadata = [track respondsToSelector:@selector(metadata)] ? track.metadata : nil;
    if (![metadata isKindOfClass:NSDictionary.class]) return nil;
    NSArray<NSString *> *fields = small ? @[@"image_url", @"image_large_url", @"image_xlarge_url"]
                                        : @[@"image_xlarge_url", @"image_large_url", @"image_url"];
    for (NSString *field in fields) {
        id value = metadata[field];
        if (![value isKindOfClass:NSString.class] || ![value length]) continue;
        NSString *local = SGLocalFileCoverInURL(value);
        if (local) return [NSURL fileURLWithPath:local];
        if ([value hasPrefix:@"https://"]) return [NSURL URLWithString:value];
        if ([value hasPrefix:@"spotify:image:"]) return [NSURL URLWithString:[@"https://i.scdn.co/image/" stringByAppendingString:[value substringFromIndex:14]]];
    }
    return nil;
}

static dispatch_queue_t coverQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ queue = dispatch_queue_create("spotifyglass.redesign.player.covers", DISPATCH_QUEUE_SERIAL); });
    return queue;
}

static NSURLSession *coverSession(void) {
    static NSURLSession *session;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSURLSessionConfiguration *configuration = NSURLSessionConfiguration.defaultSessionConfiguration;
        configuration.requestCachePolicy = NSURLRequestReturnCacheDataElseLoad;
        configuration.timeoutIntervalForRequest = 20;
        session = [NSURLSession sessionWithConfiguration:configuration];
    });
    return session;
}

NSProgress *SGRPlayerTrackCover(SPTPlayerTrack *track, BOOL small, void (^done)(UIImage *image)) {
    NSURL *url = coverURL(track, small);
    if (!url) {
        SGLog(@"redesign player: no cover in %@'s metadata", SGURIString(track.URI));
        done(nil);
        return nil;
    }
    NSProgress *progress = [NSProgress discreteProgressWithTotalUnitCount:1];
    void (^decode)(NSData *) = ^(NSData *data) {
        if (progress.cancelled) return;
        UIImage *image = [[UIImage imageWithData:data] imageByPreparingForDisplay];
        if (!image) SGLog(@"redesign player: the cover %@ did not come", url.lastPathComponent);
        dispatch_async(dispatch_get_main_queue(), ^{
            if (progress.cancelled) return;
            progress.completedUnitCount = 1;
            done(image);
        });
    };
    if (url.isFileURL) {
        dispatch_async(coverQueue(), ^{ decode(progress.cancelled ? nil : [NSData dataWithContentsOfURL:url]); });
        return progress;
    }
    NSURLSessionDataTask *task = [coverSession() dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        dispatch_async(coverQueue(), ^{ decode(error ? nil : data); });
    }];
    __weak NSURLSessionDataTask *weakTask = task;
    progress.cancellationHandler = ^{ [weakTask cancel]; };
    [task resume];
    return progress;
}

#pragma mark - the stage

// The next song must be playing this long after the outgoing window ended, or the stage gives up.
static const NSTimeInterval kArrivalWait = 3;
// While something holds the stage back inside the window, it looks again this often.
static const NSTimeInterval kHeldRetry = 0.25;
// The AI DJ's playlist (Shared/AdBlock/DJ.x).
static NSString *const kDJContext = @"spotify:playlist:37i9dQZF1EYkqdzj48dyYq";

static BOOL wideLayout(UITraitCollection *traits) {
    return traits.verticalSizeClass == UIUserInterfaceSizeClassCompact || traits.horizontalSizeClass == UIUserInterfaceSizeClassRegular;
}

// Below this alpha UIKit treats a view as not there (it takes no touches).
static const CGFloat kUnseenAlpha = 0.01;

// Whether `view` can be seen: in a shown window, nothing from it up hidden or faded out, and some of it on screen.
static BOOL seen(UIView *view) {
    UIWindow *window = view.window;
    if (!window) return NO;
    for (UIView *v = view; v; v = v.superview) {
        if (v.hidden || v.alpha < kUnseenAlpha) return NO;
    }
    return CGRectIntersectsRect(window.bounds, [view convertRect:view.bounds toView:window]);
}

// What holds the stage back, cheap enough to ask on every frame: `view` is the stage or the cover.
static BOOL heldBack(UIView *view) {
    return !sg_artworkOn || !seen(view) || SGRReduceMotion() || SGRPlayerIsTransitioning() || SGRPlayerLyricsOpen()
        || SGRPlayerCoverHidden() || UIApplication.sharedApplication.applicationState != UIApplicationStateActive || wideLayout(view.traitCollection);
}

// What the player state holds it back by: a pause or a stop, or the AI DJ.
static BOOL stateHolds(SPTPlayerState *state) {
    return state.isPaused || !state.isPlaying || [SGURIString(state.contextURI) isEqualToString:kDJContext];
}

@interface SGRMixStage : NSObject
- (void)follow;
- (void)restart;
- (void)coverLaidOut;
@end

@implementation SGRMixStage {
    SGTransitionFacts *_plan;    // the blend staged or waited for, with known times
    BOOL _done;                  // it ran to its end or was given up
    SGTransitionFacts *_imagesOf;
    UIImage *_fromImage, *_toImage;
    SGRMixStageView *_view;
    CADisplayLink *_link;
    NSTimer *_arm;
    BOOL _inactive;
    BOOL _onNext;                // the next song is the one playing
    CGFloat _progress;
    CFTimeInterval _overdueSince;
}

- (instancetype)init {
    if (!(self = [super init])) return nil;
    _inactive = UIApplication.sharedApplication.applicationState != UIApplicationStateActive;
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(resigned) name:UIApplicationWillResignActiveNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(activated) name:UIApplicationDidBecomeActiveNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(follow) name:SGRPlayerVisibilityDidChangeNotification object:nil];
    return self;
}

- (void)resigned {
    _inactive = YES;
    [self follow];
}

- (void)activated {
    _inactive = NO;
    [self follow];
}

- (void)coverLaidOut {
    if (!_arm && !_view) [self follow];
}

// A report, new facts or a cover that came in.
- (void)follow {
    if (_inactive || UIApplication.sharedApplication.applicationState != UIApplicationStateActive || !SGRPlayerIsVisible()) {
        [_arm invalidate];
        _arm = nil;
        if (_view) [self stop:@"the player is not visible or active" done:NO];
        return;
    }
    SPTPlayerState *state = SGPlayerState();
    if (_view) {
        // On the outgoing song the facts must still be the plan's; on the incoming one the plan is the blend that
        // brought it (sg_arrived), or the facts that still name it until they move on.
        if (SGRMixTrackIs(state.track, _plan.fromURI, _plan.fromUID)) {
            _onNext = NO;
            if (_plan != sg_facts) {
                [self stop:@"the facts changed" done:NO];
                return;
            }
        } else if (SGRMixTrackIs(state.track, _plan.toURI, _plan.toUID) && (_plan == sg_arrived || _plan == sg_facts)) {
            _onNext = YES;
        } else {
            [self stop:@"another song came" done:YES];
            return;
        }
        if (stateHolds(state)) [self stop:@"the player stopped" done:NO];
        return;
    }
    if (_plan != sg_facts) {
        // The next song came before the stage could run: it may still run over the incoming window.
        if (_plan == sg_arrived && [self start]) return;
        [self adopt:sg_facts];
    }
    [self arm];
}

// The option changed: the plan is made again from the facts.
- (void)restart {
    if (_view) [self stop:@"its option changed" done:NO];
    _plan = nil;
    _imagesOf = nil;
    [self follow];
}

- (void)adopt:(SGTransitionFacts *)facts {
    BOOL usable = sg_artworkOn && facts.timesKnown && facts.outEnd > facts.outStart && facts.inEnd > facts.inStart;
    _plan = usable ? facts : nil;
    _done = NO;
    if (_plan && _imagesOf != _plan) [self prepareImages];
}

- (void)prepareImages {
    SGTransitionFacts *plan = _plan;
    _imagesOf = plan;
    _fromImage = _toImage = nil;
    SPTPlayerState *state = SGPlayerState();
    SPTPlayerTrack *from = state.track, *next = SGPlayerUpcomingTracks(state, 1).firstObject;
    if (SGRMixTrackIs(from, plan.fromURI, plan.fromUID)) SGRPlayerTrackCover(from, NO, ^(UIImage *image) {
        if (self->_imagesOf == plan) self->_fromImage = image;
    });
    if (SGRMixTrackIs(next, plan.toURI, plan.toUID)) SGRPlayerTrackCover(next, NO, ^(UIImage *image) {
        if (self->_imagesOf != plan) return;
        self->_toImage = image;
        [self follow];
    });
}

// Waits for the window of the song playing, or looks again while something holds the stage back inside it.
- (void)arm {
    [_arm invalidate];
    _arm = nil;
    if (_inactive || UIApplication.sharedApplication.applicationState != UIApplicationStateActive || !SGRPlayerIsVisible()
        || !seen(SGRPlayerShowingCover()) || !_plan || _done || _view) return;
    SPTPlayerState *state = SGPlayerState();
    if (!SGRMixTrackIs(state.track, _plan.fromURI, _plan.fromUID) || stateHolds(state) || state.playbackSpeed <= 0) return;
    double position = positionOf(state);
    if (position >= _plan.outEnd) return;
    NSTimeInterval wait = kHeldRetry;
    if (position < _plan.outStart) wait = (_plan.outStart - position) / state.playbackSpeed;
    else if ([self start]) return;
    _arm = [NSTimer timerWithTimeInterval:wait target:self selector:@selector(armed) userInfo:nil repeats:NO];
    [NSRunLoop.mainRunLoop addTimer:_arm forMode:NSRunLoopCommonModes];
}

- (void)armed {
    _arm = nil;
    [self arm];
}

- (BOOL)start {
    if (!_plan || _done || _view || !_toImage) return NO;
    SPTPlayerState *state = SGPlayerState();
    UIView *cover = SGRPlayerShowingCover();
    if (heldBack(cover) || stateHolds(state)) return NO;
    double position = positionOf(state);
    BOOL onFrom = SGRMixTrackIs(state.track, _plan.fromURI, _plan.fromUID);
    BOOL onNext = !onFrom && _plan == sg_arrived && SGRMixTrackIs(state.track, _plan.toURI, _plan.toUID);
    if (onFrom ? (position < _plan.outStart || position >= _plan.outEnd) : !(onNext && _fromImage && position < _plan.inEnd)) return NO;
    // A still of the cover as it shows now, while it still shows the playing song; the fetched one after.
    UIView *outgoing = onFrom ? [cover snapshotViewAfterScreenUpdates:NO] : [[UIImageView alloc] initWithImage:_fromImage];
    if (!outgoing) return NO;
    SGRMixStageView *view = [[SGRMixStageView alloc] initWithOutgoing:outgoing incoming:_toImage];
    if (!SGRPlayerStageCover(view)) return NO;
    [view layoutIfNeeded];
    _view = view;
    _onNext = onNext;
    _progress = 0;
    _overdueSince = 0;
    _link = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick)];
    [_link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    static NSUInteger logged;
    if (logged++ < 3) SGLog(@"redesign player: AutoMix's stage over the cover, %@ into %@ at %.2f s", _plan.fromURI, _plan.toURI, position);
    [self tick];
    return YES;
}

- (void)tick {
    SGRMixStageView *view = _view;
    if (heldBack(view)) {
        [self stop:@"held back" done:NO];
        return;
    }
    double position = positionOf(SGPlayerState());
    CGFloat progress;
    if (_onNext) {
        progress = MAX(_progress, (position - _plan.inStart) / (_plan.inEnd - _plan.inStart));
    } else {
        if (position < _plan.outStart) {
            [self stop:@"a seek back before the window" done:NO];
            return;
        }
        progress = (position - _plan.outStart) / (_plan.outEnd - _plan.outStart);
    }
    if (progress >= 1) {
        if (_onNext) {
            [self stop:@"done" done:YES];
            return;
        }
        CFTimeInterval now = CACurrentMediaTime();
        if (!_overdueSince) _overdueSince = now;
        if (now - _overdueSince > kArrivalWait) {
            [self stop:@"the next song did not come" done:YES];
            return;
        }
        progress = 1;
    }
    _progress = progress;
    [view show:progress];
}

// The cover back at once; then the stage waits for the window again unless it is `done` with this blend.
- (void)stop:(NSString *)why done:(BOOL)done {
    [_link invalidate];
    _link = nil;
    [_arm invalidate];
    _arm = nil;
    if (_view) SGRPlayerStageCover(nil);
    _view = nil;
    if (done) _done = YES;
    static NSUInteger logged;
    if (logged++ < 20) SGLog(@"redesign player: AutoMix's stage ends, %@", why);
    [self follow];
}

@end

static void stageFollows(void) {
    [sg_mixStage follow];
}

void SGRPlayerMixCoverLaidOut(void) {
    [sg_mixStage coverLaidOut];
}

#pragma mark - wiring

@interface SGRMixWatcher : NSObject <SGPlayerStateObserver>
@end

@implementation SGRMixWatcher
- (void)playerStateDidReport:(SPTPlayerState *)state {
    reconcile();
}
- (void)playerStateDidChange:(SPTPlayerState *)state {
    // A new song's length, which the bands are placed by.
    layOutSliders();
    reconcile();
}
@end

static SGRMixWatcher *sg_mixWatcher;

%ctor {
    if (!SGRedesignedUI()) return;
    readOptions();
    sg_sliders = [NSHashTable weakObjectsHashTable];
    sg_mixStage = [SGRMixStage new];
    sg_mixWatcher = [SGRMixWatcher new];
    SGAddPlayerStateObserver(sg_mixWatcher);
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    // Both are posted on the main thread.
    [center addObserverForName:SGAutoMixTransitionDidChangeNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
        reconcile();
    }];
    [center addObserverForName:SGAutoMixPlayerOptionsDidChangeNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
        readOptions();
        bandsChanged();
        [sg_mixStage restart];
    }];
}
