#import <AVFoundation/AVFoundation.h>
#import "Core/SGCore.h"
#import "Shared/AnimatedArtwork/AnimatedArtwork.h"
#import "Shared/AnimatedArtwork/SGMotionCatalog.h"
#import "Shared/AnimatedArtwork/SGMotionClip.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Redesigned/Kit/SGRMotionBudget.h"
#import "Redesigned/Player/Player.h"
#import "ArtistArtwork.h"

NSArray<NSString *> *SGRArtistReleaseTitles(UIView *root) {
    static NSRegularExpression *year;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        year = [NSRegularExpression regularExpressionWithPattern:@"(?<![0-9])[0-9]{4}(?![0-9])" options:0 error:nil];
    });
    NSMutableSet *titles = [NSMutableSet set];
    SGForEachView(root, ^(UIView *row) {
        if (![row.accessibilityIdentifier isEqual:@"Components.UI.RetrievalRowElementUI_Loaded"]) return;
        if (SGRFindByIdentifier(row, @"Components.UI.AddToButton", NULL) ||
            SGRFindByIdentifier(row, @"Components.UI.HiddenUndoButton", NULL)) return;
        NSString *subtitle = SGRFirstLabelText(SGRFindByIdentifier(row, @"RetrievalRowElementUI.Subtitle.Label", NULL));
        if (!subtitle || ![year firstMatchInString:subtitle options:0 range:NSMakeRange(0, subtitle.length)]) return;
        UIView *titleView = SGRFindByIdentifier(row, @"EncoreConsumerMobile.View.Granular.Title", NULL);
        if (!titleView) {
            __block UIView *found = nil;
            SGForEachView(row, ^(UIView *view) {
                if (!found && [NSStringFromClass(view.class) containsString:@"TitleView"]) found = view;
            });
            titleView = found;
        }
        NSString *title = SGRFirstLabelText(titleView);
        if (title.length) [titles addObject:title];
    });
    return titles.allObjects;
}

@implementation SGRArtistArtworkRequest {
    NSString *_identity;
    NSMutableSet<NSString *> *_evidence;
    BOOL _attempted, _finished, _deliveryPending;
    UIImage *_photo;
    NSURL *_file;
    NSUInteger _generation;
    NSUInteger _attemptedEvidenceCount;
    NSMutableSet<NSString *> *_diagnostics;
}
- (BOOL)needsReleaseEvidenceForIdentity:(NSString *)identity {
    return identity.length && (![_identity isEqual:identity] || !_finished);
}
- (void)applyPendingResultForIdentity:(NSString *)identity apply:(void (^)(UIImage *, NSURL *))apply {
    if (!_deliveryPending || ![_identity isEqual:identity]) return;
    _deliveryPending = NO;
    apply(_photo, _file);
}
- (void)updateIdentity:(NSString *)identity name:(NSString *)name titles:(NSArray<NSString *> *)titles
                 photo:(BOOL)photo motion:(BOOL)motion currentIdentity:(NSString *(^)(void))currentIdentity
                 apply:(void (^)(UIImage *, NSURL *))apply {
    if (![_identity isEqual:identity]) {
        _identity = [identity copy];
        _evidence = [NSMutableSet set];
        _attempted = _finished = _deliveryPending = NO;
        _photo = nil;
        _file = nil;
        _generation++;
        _attemptedEvidenceCount = 0;
        _diagnostics = nil;
    }
    [self applyPendingResultForIdentity:identity apply:apply];
    [_evidence addObjectsFromArray:titles];
    // Metadata may be re-matched when evidence grows. Once assets were attempted
    // (including failures), scrolling cannot retry them.
    if (_attempted) return;
    NSArray *sorted = [_evidence.allObjects sortedArrayUsingSelector:@selector(compare:)];
    NSString *evidenceStage = [NSString stringWithFormat:@"releases-%lu", (unsigned long)sorted.count];
    if (SGLogFirst(&_diagnostics, evidenceStage))
        SGLog(@"artist artwork: %@: release titles=%lu first=%@; %@", name, (unsigned long)sorted.count,
            [[sorted subarrayWithRange:NSMakeRange(0, MIN((NSUInteger)4, sorted.count))] componentsJoinedByString:@" | "],
            sorted.count >= 2 ? @"evidence ready" : @"wait: need two verified releases");
    NSUInteger generation = _generation;
    if (!identity.length || !name.length || sorted.count < 2 || sorted.count <= _attemptedEvidenceCount || (!photo && !motion)) return;
    _attempted = YES;
    _attemptedEvidenceCount = sorted.count;
    __weak SGRArtistArtworkRequest *weakSelf = self;
    SGMotionArtistArtwork(name, sorted, SGMotionPixels(), photo, motion, ^(UIImage *image, NSURL *file, SGMotionArtistArtworkOutcome outcome) {
        SGRArtistArtworkRequest *owner = weakSelf;
        if (!owner || owner->_finished || owner->_generation != generation) return;
        NSString *liveIdentity = currentIdentity();
        if (liveIdentity.length && ![liveIdentity isEqual:identity]) return;
        if (outcome == SGMotionArtistArtworkNeedsEvidence) {
            owner->_attempted = NO;
            SGLog(@"artist artwork: %@: wait: more release evidence; metadata cached, no asset attempt", name);
            // Rows may have arrived while metadata was in flight. The count guard
            // ensures unchanged evidence does not schedule another match.
            if (liveIdentity.length)
                [owner updateIdentity:identity name:name titles:@[] photo:photo motion:motion currentIdentity:currentIdentity apply:apply];
            return;
        }
        owner->_finished = YES;
        owner->_photo = image;
        owner->_file = file;
        owner->_deliveryPending = outcome == SGMotionArtistArtworkFinished || image || file;
        if (outcome == SGMotionArtistArtworkMetadataFailed) {
            SGLog(@"artist artwork: %@: metadata failed; retry on next page open", name);
        } else {
            SGLog(@"artist artwork: %@: page result photo=%@ motion=%@ (attempt latched)", name,
                image ? @"ready" : @"none", file ? @"ready" : @"none");
        }
        if (liveIdentity.length) [owner applyPendingResultForIdentity:liveIdentity apply:apply];
        else SGLog(@"artist artwork: %@: result retained until identity returns", name);
    });
}
@end

static void *kArtistReady = &kArtistReady;
static char kScrollContext;
@implementation SGRArtistMotionView {
    NSURL *_file; // retains the store's lease while the player uses it
    AVQueuePlayer *_player;
    NSHashTable *_motionScrolls;
    AVPlayerLooper *_looper;
    AVPlayerLayer *_video;
}
- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.userInteractionEnabled = NO;
    self.accessibilityElementsHidden = YES;
    self.clipsToBounds = YES;
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(updatePlayback)
        name:SGRPlayerVisibilityDidChangeNotification object:nil];
    for (NSNotificationName name in @[UIApplicationDidBecomeActiveNotification, UIApplicationWillResignActiveNotification,
        NSProcessInfoPowerStateDidChangeNotification, NSProcessInfoThermalStateDidChangeNotification,
        UIAccessibilityReduceMotionStatusDidChangeNotification,
        UIAccessibilityVideoAutoplayStatusDidChangeNotification])
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(updateSoon) name:name object:nil];
    return self;
}
- (void)dealloc {
    SGRBindViewportScrolls(nil, _motionScrolls, self, &kScrollContext);
    [NSNotificationCenter.defaultCenter removeObserver:self];
    [_video removeObserver:self forKeyPath:@"readyForDisplay" context:kArtistReady];
    [_player pause];
}
- (void)showFile:(NSURL *)file {
    if ([_file isEqual:file]) return;
    [_player pause];
    [_video removeObserver:self forKeyPath:@"readyForDisplay" context:kArtistReady];
    [_video removeFromSuperlayer];
    _video = nil;
    _looper = nil;
    _player = nil;
    _file = file;
    if (!file) {
        SGRObserveVisibility(self, nil);
        SGRBindViewportScrolls(nil, _motionScrolls, self, &kScrollContext);
        _motionScrolls = nil;
        return;
    }
    _player = [AVQueuePlayer new];
    _player.muted = YES;
    _player.preventsDisplaySleepDuringVideoPlayback = NO;
    _player.automaticallyWaitsToMinimizeStalling = NO;
    _looper = [AVPlayerLooper playerLooperWithPlayer:_player templateItem:[AVPlayerItem playerItemWithURL:file]];
    _video = [AVPlayerLayer playerLayerWithPlayer:_player];
    _video.videoGravity = AVLayerVideoGravityResizeAspectFill;
    _video.frame = self.bounds;
    _video.opacity = 0;
    [self.layer addSublayer:_video];
    [_video addObserver:self forKeyPath:@"readyForDisplay" options:NSKeyValueObservingOptionInitial context:kArtistReady];
    if (!_motionScrolls) {
        _motionScrolls = [NSHashTable weakObjectsHashTable];
        __weak SGRArtistMotionView *weakSelf = self;
        SGRObserveVisibility(self, ^{ [weakSelf motionHierarchyChanged]; });
    }
    [self motionHierarchyChanged];
}
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if (context == &kScrollContext) { [self updatePlayback]; return; }
    if (context != kArtistReady) {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
        return;
    }
    __weak SGRArtistMotionView *weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        SGRArtistMotionView *view = weakSelf;
        AVPlayerLayer *video = object;
        if (!view || view->_video != video || !video.readyForDisplay || video.opacity == 1) return;
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        video.opacity = 1;
        if (view.window && !SGRReduceMotion()) {
            CABasicAnimation *fade = [CABasicAnimation animationWithKeyPath:@"opacity"];
            fade.fromValue = @0;
            fade.toValue = @1;
            fade.duration = 0.2;
            [video addAnimation:fade forKey:@"fade"];
        }
        [CATransaction commit];
    });
}
- (void)updateSoon {
    dispatch_async(dispatch_get_main_queue(), ^{ [self updatePlayback]; });
}
- (void)updatePlayback {
    if (!_player) return;
    BOOL may = SGMotionHeaderMayPlay(SGRViewInViewport(self, SGRSettledPlayerRect(self.window)),
        UIApplication.sharedApplication.applicationState == UIApplicationStateActive,
        SGRReduceMotion(), SGRMotionHeldForPowerOrHeat(), UIAccessibilityIsVideoAutoplayEnabled());
    if (may != (_player.rate != 0)) {
        if (may) [_player play]; else [_player pause];
    }
}
- (void)motionHierarchyChanged {
    SGRBindViewportScrolls(self, _motionScrolls, self, &kScrollContext);
    [self updatePlayback];
}
- (void)layoutSubviews {
    [super layoutSubviews];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _video.frame = self.bounds;
    [CATransaction commit];
    [self updatePlayback];
}
@end
