#import <AVFoundation/AVFoundation.h>
#import "Core/SGCore.h"
#import "Shared/AnimatedArtwork/AnimatedArtwork.h"
#import "Shared/AnimatedArtwork/SGMotionCatalog.h"
#import "Shared/AnimatedArtwork/SGMotionClip.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Redesigned/Kit/SGRMotionBudget.h"
#import "Redesigned/Kit/SGRHeaderClip.h"
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

static char kScrollContext;
@implementation SGRArtistMotionView {
    SGRHeaderClip *_clip;
    SGRHeaderPage *_clipPage;
    NSHashTable *_motionScrolls;
    BOOL _resigning, _background;
}
- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.userInteractionEnabled = NO;
    self.accessibilityElementsHidden = YES;
    self.clipsToBounds = YES;
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(updatePlayback)
        name:SGRPlayerVisibilityDidChangeNotification object:nil];
    __weak SGRArtistMotionView *weakView = self;
    _clipPage = [[SGRHeaderPage alloc] initWithRefresh:^{ [weakView updatePlayback]; }];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(updatePlayback)
        name:UIApplicationDidReceiveMemoryWarningNotification object:nil];
    for (NSNotificationName name in @[UIApplicationDidBecomeActiveNotification, UIApplicationWillResignActiveNotification,
        UIApplicationDidEnterBackgroundNotification])
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(appState:) name:name object:nil];
    for (NSNotificationName name in @[NSProcessInfoPowerStateDidChangeNotification, NSProcessInfoThermalStateDidChangeNotification,
        UIAccessibilityReduceMotionStatusDidChangeNotification,
        UIAccessibilityVideoAutoplayStatusDidChangeNotification])
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(updateSoon) name:name object:nil];
    return self;
}
- (void)dealloc {
    [_clip invalidate];
    SGRBindViewportScrolls(nil, _motionScrolls, self, &kScrollContext);
    [NSNotificationCenter.defaultCenter removeObserver:self];
}
- (void)showFile:(NSURL *)file {
    if ([_clip.file isEqual:file]) { [self updatePlayback]; return; }
    [_clip invalidate];
    _clip = nil;
    if (!file) {
        SGRObserveVisibility(self, nil);
        SGRBindViewportScrolls(nil, _motionScrolls, self, &kScrollContext);
        _motionScrolls = nil;
        return;
    }
    __weak SGRArtistMotionView *weakSelf = self;
    _clip = [[SGRHeaderClip alloc] initWithFile:file appearance:^(BOOL shown, BOOL entrance) {
        SGRArtistMotionView *view = weakSelf;
        if (!entrance || !view.window || SGRReduceMotion()) return;
        CABasicAnimation *fade = [CABasicAnimation animationWithKeyPath:@"opacity"];
        fade.fromValue = @0;
        fade.toValue = @1;
        fade.duration = 0.2;
        [view->_clip.layer addAnimation:fade forKey:@"fade"];
    }];
    [_clip setFrame:self.bounds];
    [self.layer addSublayer:_clip.layer];
    if (!_motionScrolls) {
        _motionScrolls = [NSHashTable weakObjectsHashTable];
        SGRObserveVisibility(self, ^{ [weakSelf motionHierarchyChanged]; });
    }
    [self motionHierarchyChanged];
}
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if (context == &kScrollContext) { [self updatePlayback]; return; }
    [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}
- (void)appState:(NSNotification *)note {
    _resigning = ![note.name isEqual:UIApplicationDidBecomeActiveNotification];
    _background = [note.name isEqual:UIApplicationDidEnterBackgroundNotification];
    [self updatePlayback];
}
- (void)updateSoon {
    dispatch_async(dispatch_get_main_queue(), ^{ [self updatePlayback]; });
}
- (void)updatePlayback {
    [_clipPage bindHeader:self];
    if (!_clip) return;
    UIApplicationState state = UIApplication.sharedApplication.applicationState;
    BOOL front = !_resigning && state == UIApplicationStateActive;
    BOOL visible = !_background && state != UIApplicationStateBackground &&
                   [_clipPage visibleInViewport:SGRViewInViewport(self, SGRSettledPlayerRect(self.window))];
    BOOL may = SGMotionHeaderMayPlay(visible, front,
        SGRReduceMotion(), SGRMotionHeldForPowerOrHeat(), UIAccessibilityIsVideoAutoplayEnabled());
    [_clip updateVisible:visible active:front mayPlay:may];
}
- (void)motionHierarchyChanged {
    SGRBindViewportScrolls(self, _motionScrolls, self, &kScrollContext);
    [self updatePlayback];
}
- (void)layoutSubviews {
    [super layoutSubviews];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    [_clip setFrame:self.bounds];
    [CATransaction commit];
    [self updatePlayback];
}
@end
