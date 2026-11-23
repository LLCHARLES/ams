// DurationTrackerImpl publishes to Combine before it gets anywhere near the slider. Stop its clock,
// not just the final UIKit write. Spotify still owns the link, its target, and its requested pause.
#import "Player.h"
#import "Core/SGUIMode.h"
#import "Redesigned/Kit/SGRRestyle.h"
#import "Shared/Player/PlayerEvents.h"
#import "Shared/Player/PlayerState.h"
#import "Shared/Player/SpeedPitch.h"
#import <stdatomic.h>
#import <objc/message.h>
#import <objc/runtime.h>

@interface SGRProgressClock : NSObject {
@public
    __weak CADisplayLink *link;
    __weak id target;
    NSHashTable<UIView *> *outputs;
    atomic_bool requested, invalidated;
    BOOL refreshPending, firing, changed, discovering, resetOutputs, held, wrote;
}
@property (atomic) CAFrameRateRange requestedRange;
- (void)update;
@end

@interface SGRProgressRail : NSObject
@property CGFloat pixels;
@property BOOL tracking;
@end
@implementation SGRProgressRail
@end

static char kClock, kFireHook, kWriters, kRail;
static NSHashTable<SGRProgressClock *> *clocks;
static NSHashTable<SGRProgressClock *> *learning;
static BOOL anyLearning;
static double trackSeconds, playbackRate;
static const float slowHz = 10;
__thread __unsafe_unretained SGRProgressClock *SGRWritingProgress;
static BOOL controlsFaded, transitioning;
static void (*setPause)(CADisplayLink *, SEL, BOOL);
static BOOL (*getPause)(CADisplayLink *, SEL);
static void (*setRange)(CADisplayLink *, SEL, CAFrameRateRange);
static CAFrameRateRange (*getRange)(CADisplayLink *, SEL);
static __thread __unsafe_unretained CADisplayLink *settingFPS;

static void bindNext(SGRProgressClock *c, BOOL bind) {
    c->discovering = bind;
    if (bind && !c->requested && !c->held) [learning addObject:c];
    else [learning removeObject:c];
    anyLearning = learning.count != 0;
}

static CGFloat railPixels(UISlider *slider) {
    return [slider trackRectForBounds:slider.bounds].size.width * slider.window.screen.scale;
}

void SGRProgressRailChanged(UISlider *slider, BOOL tracking) {
    SGRProgressRail *rail = objc_getAssociatedObject(slider, &kRail);
    if (!rail) return;
    CGFloat pixels = railPixels(slider);
    if (pixels == rail.pixels && tracking == rail.tracking) return;
    rail.pixels = pixels;
    rail.tracking = tracking;
    for (SGRProgressClock *c in [objc_getAssociatedObject(slider, &kWriters) allObjects]) [c update];
}

void SGRProgressPlaybackChanged(double seconds, double rate) {
    if (trackSeconds == seconds && playbackRate == rate) return;
    trackSeconds = seconds;
    playbackRate = rate;
    SGRProgressVisibilityChanged();
}

// A newly mounted progress element may have been rebound to an existing tracker.
void SGRProgressOutputMounted(UIView *view) {
    if (!view.window) {
        // The rail no longer has a screen scale, even if a time label is still visible.
        for (SGRProgressClock *c in [objc_getAssociatedObject(view, &kWriters) allObjects]) [c update];
        return;
    }
    for (SGRProgressClock *c in clocks.allObjects) {
        if (c->invalidated) continue;
        c->resetOutputs = YES;
        bindNext(c, YES);
        [c update];
    }
}

static void forgetOutputs(SGRProgressClock *c) {
    for (UIView *v in c->outputs) {
        NSHashTable *writers = objc_getAssociatedObject(v, &kWriters);
        [writers removeObject:c];
        if (!writers.allObjects.count) {
            SGRObserveVisibility(v, nil);
            objc_setAssociatedObject(v, &kWriters, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    }
    [c->outputs removeAllObjects];
}

static BOOL visible(UIView *view, BOOL *sticky) {
    UIWindow *window = view.window;
    BOOL mini = NO, player = NO, hidden = NO;
    for (UIView *v = view; v; v = v.superview) {
        NSString *name = v.accessibilityIdentifier;
        if ([name isEqualToString:@"now-playing-sticky-header"]) {
            *sticky = YES;
            return YES;
        }
        mini |= [name isEqualToString:@"SPTNowPlayingBar"];
        player |= [name isEqualToString:@"SPTNowPlayingViewContainerViewController"];
        hidden |= v.hidden || v.alpha == 0;
    }
    if (!window) return NO;
    if (transitioning && (player || mini)) return YES;
    if (player) {
        // The animator can set its final model alpha before the first frame of a held close.
        // Only the completed portrait lyrics fade authorizes stopping these controls.
        return !controlsFaded || !SGRPlayerLyricsOpen() || CGRectIsNull(SGRSettledPlayerRect(window)) || SGRPlayerTwoColumns() ||
            window.bounds.size.width > window.bounds.size.height ||
            [window.windowScene.keyWindow.rootViewController isKindOfClass:NSClassFromString(@"SGRLandscapeLyricsController")] || !hidden;
    }
    if (!mini && hidden) return NO;
    CGRect cover = SGRSettledPlayerRect(window);
    if (CGRectIsNull(cover)) return YES;
    // The mini bar is often already hidden. Test actual coverage independently of model alpha.
    CGRect rect = mini && hidden ? CGRectIntersection(window.bounds, [view convertRect:view.bounds toView:window])
                                 : SGRVisibleRectInWindow(view);
    return CGRectIsEmpty(rect) || !CGRectContainsRect(cover, rect);
}

@implementation SGRProgressClock
- (void)update {
    if (firing) { changed = YES; return; }
    CADisplayLink *clock = link;
    if (!clock || invalidated) return;
    BOOL hold = NO;
    BOOL seen = NO, hasRail = NO, sticky = NO;
    BOOL slow = trackSeconds > 0 && isfinite(trackSeconds) && playbackRate > 0 && isfinite(playbackRate);
    for (UIView *v in outputs) {
        hold = YES;
        seen |= visible(v, &sticky);
        SGRProgressRail *rail = objc_getAssociatedObject(v, &kRail);
        if (!rail) continue;
        hasRail = YES;
        slow &= v.window && !rail.tracking && rail.pixels > 0 && isfinite(rail.pixels) &&
            rail.pixels * MAX(1., playbackRate) <= slowHz * trackSeconds;
    }
    hold &= !discovering && !seen;
    if (held != hold) {
        held = hold;
        bindNext(self, discovering);
    }
    if (hold) refreshPending = YES;
    BOOL pause = hold || requested;
    CAFrameRateRange range = self.requestedRange;
    if (!discovering && !sticky && !pause && hasRail && slow && (!range.preferred || range.preferred > slowHz) &&
        (!range.maximum || range.maximum > slowHz)) range = CAFrameRateRangeMake(slowHz, slowHz, slowHz);
    @synchronized (self) {
        if (invalidated) return;
        if (!CAFrameRateRangeIsEqualToRange(getRange(clock, @selector(preferredFrameRateRange)), range))
            setRange(clock, @selector(setPreferredFrameRateRange:), range);
    }
    if (getPause(clock, @selector(isPaused)) != pause) setPause(clock, @selector(setPaused:), pause);
    // Waiting for the next 20 Hz callback would expose up to 50 ms of stale UI. The callback
    // reads the current playback position, not an accumulated tick count.
    if (refreshPending && !pause && !discovering) {
        refreshPending = NO;
        ((void (*)(id, SEL, id))objc_msgSend)(target, @selector(displayLinkFired:), clock);
    }
}
@end

void SGRProgressVisibilityChanged(void) {
    for (SGRProgressClock *clock in clocks.allObjects) [clock update];
}

void SGRProgressControlsFaded(BOOL finished) {
    controlsFaded = finished;
    SGRProgressVisibilityChanged();
}

static void recordOutput(UIView *view) {
    SGRProgressClock *clock = SGRWritingProgress;
    clock->wrote = YES;
    if ([clock->outputs containsObject:view]) return;
    [clock->outputs addObject:view];
    clock->changed = YES;
    NSHashTable *writers = objc_getAssociatedObject(view, &kWriters);
    if (!writers) {
        writers = [NSHashTable weakObjectsHashTable];
        objc_setAssociatedObject(view, &kWriters, writers, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        SGRObserveVisibility(view, ^{
            for (SGRProgressClock *writer in writers.allObjects) [writer update];
        });
    }
    [writers addObject:clock];
}

void SGRProgressSliderWrote(UISlider *slider) {
    if (!objc_getAssociatedObject(slider, &kRail)) {
        SGRProgressRail *rail = [SGRProgressRail new];
        rail.pixels = railPixels(slider);
        rail.tracking = slider.isTracking;
        objc_setAssociatedObject(slider, &kRail, rail, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    recordOutput(slider);
}

static BOOL timeLabel(UIView *view) {
    NSString *name = view.accessibilityIdentifier;
    return [name isEqualToString:@"now-playing-time-take-label-internal"] ||
           [name isEqualToString:@"now-playing-time-remaning-label-internal"];
}

// A player bar also writes its times, not necessarily on the tick that wrote the slider.
// Do not mistake the temporary glyph labels of a rolling time for new tracker outputs.
static BOOL bindingComplete(SGRProgressClock *c) {
    BOOL take = NO, remaining = NO;
    for (UIView *view in c->outputs) {
        NSString *name = view.accessibilityIdentifier;
        take |= [name isEqualToString:@"now-playing-time-take-label-internal"];
        remaining |= [name isEqualToString:@"now-playing-time-remaning-label-internal"];
        if (!objc_getAssociatedObject(view, &kRail)) continue;
        for (UIView *v = view; v; v = v.superview) {
            if ([v.accessibilityIdentifier isEqualToString:@"SPTNowPlayingBar"] ||
                [v.accessibilityIdentifier isEqualToString:@"now-playing-sticky-header"]) return YES;
        }
    }
    return take && remaining;
}

static void replace(Class cls, SEL sel, id block) {
    Method m = class_getInstanceMethod(cls, sel);
    IMP hook = imp_implementationWithBlock(block);
    if (!class_addMethod(cls, sel, hook, method_getTypeEncoding(m))) method_setImplementation(m, hook);
}

static void hookFire(Class cls, SEL sel) {
    if (objc_getAssociatedObject(cls, &kFireHook)) return;
    void (*fire)(id, SEL, CADisplayLink *) = (void *)class_getMethodImplementation(cls, sel);
    replace(cls, sel, ^(id owner, CADisplayLink *link) {
        if (!anyLearning) { fire(owner, sel, link); return; }
        SGRProgressClock *clock = objc_getAssociatedObject(link, &kClock);
        if (!clock || !clock->discovering) { fire(owner, sel, link); return; }
        if (clock->resetOutputs) {
            forgetOutputs(clock);
            clock->resetOutputs = NO;
        }
        SGRProgressClock *outer = SGRWritingProgress;
        SGRWritingProgress = clock;
        clock->wrote = NO;
        clock->refreshPending = NO;
        clock->firing = YES;
        fire(owner, sel, link);
        clock->firing = NO;
        SGRWritingProgress = outer;
        if (!clock->resetOutputs && clock->wrote && bindingComplete(clock)) {
            bindNext(clock, NO);
            clock->changed = YES;
        }
        if (clock->changed) {
            clock->changed = NO;
            [clock update];
        }
    });
    objc_setAssociatedObject(cls, &kFireHook, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void hookClocks(Class cls) {
    clocks = [NSHashTable weakObjectsHashTable];
    learning = [NSHashTable weakObjectsHashTable];
    setPause = (void *)class_getMethodImplementation(cls, @selector(setPaused:));
    getPause = (void *)class_getMethodImplementation(cls, @selector(isPaused));
    setRange = (void *)class_getMethodImplementation(cls, @selector(setPreferredFrameRateRange:));
    getRange = (void *)class_getMethodImplementation(cls, @selector(preferredFrameRateRange));
    replace(cls, @selector(setPreferredFrameRateRange:), ^(CADisplayLink *l, CAFrameRateRange range) {
        if (l == settingFPS) { setRange(l, @selector(setPreferredFrameRateRange:), range); return; }
        SGRProgressClock *c = objc_getAssociatedObject(l, &kClock);
        if (!c) { setRange(l, @selector(setPreferredFrameRateRange:), range); return; }
        c.requestedRange = range;
        if (NSThread.isMainThread) [c update];
        else dispatch_async(dispatch_get_main_queue(), ^{ [c update]; });
    });
    replace(cls, @selector(preferredFrameRateRange), ^CAFrameRateRange(CADisplayLink *l) {
        if (l == settingFPS) return getRange(l, @selector(preferredFrameRateRange));
        SGRProgressClock *c = objc_getAssociatedObject(l, &kClock);
        return c && !c->invalidated ? c.requestedRange : getRange(l, @selector(preferredFrameRateRange));
    });
    // Spotify also sets the integer FPS immediately after creating a link. Let Core Animation
    // translate that request; the range at creation was still the system default.
    SEL fps = @selector(setPreferredFramesPerSecond:);
    void (*setFPS)(CADisplayLink *, SEL, NSInteger) = (void *)class_getMethodImplementation(cls, fps);
    replace(cls, fps, ^(CADisplayLink *l, NSInteger value) {
        SGRProgressClock *c = objc_getAssociatedObject(l, &kClock);
        if (!c) { setFPS(l, fps, value); return; }
        CADisplayLink *outer = settingFPS;
        settingFPS = l;
        setFPS(l, fps, value);
        c.requestedRange = getRange(l, @selector(preferredFrameRateRange));
        settingFPS = outer;
        if (NSThread.isMainThread) [c update];
        else dispatch_async(dispatch_get_main_queue(), ^{ [c update]; });
    });
    replace(cls, @selector(setPaused:), ^(CADisplayLink *l, BOOL pause) {
        SGRProgressClock *c = objc_getAssociatedObject(l, &kClock);
        if (!c) { setPause(l, @selector(setPaused:), pause); return; }
        c->requested = pause;
        dispatch_block_t apply = ^{
            if (c->invalidated) return;
            if (c->discovering) bindNext(c, YES);
            [c update];
        };
        if (NSThread.isMainThread) apply(); else dispatch_async(dispatch_get_main_queue(), apply);
    });
    replace(cls, @selector(isPaused), ^BOOL(CADisplayLink *l) {
        SGRProgressClock *c = objc_getAssociatedObject(l, &kClock);
        return c && !c->invalidated ? c->requested : getPause(l, @selector(isPaused));
    });
    void (*invalidate)(CADisplayLink *, SEL) = (void *)class_getMethodImplementation(cls, @selector(invalidate));
    replace(cls, @selector(invalidate), ^(CADisplayLink *l) {
        SGRProgressClock *c = objc_getAssociatedObject(l, &kClock);
        if (!c) { invalidate(l, @selector(invalidate)); return; }
        BOOL alreadyInvalid;
        @synchronized (c) {
            alreadyInvalid = c->invalidated;
            if (!alreadyInvalid) {
                CAFrameRateRange own = c.requestedRange;
                if (!CAFrameRateRangeIsEqualToRange(getRange(l, @selector(preferredFrameRateRange)), own))
                    setRange(l, @selector(setPreferredFrameRateRange:), own);
                c->invalidated = YES;
            }
        }
        invalidate(l, @selector(invalidate));
        if (alreadyInvalid) return;
        dispatch_block_t detach = ^{
            bindNext(c, NO);
            c->link = nil;
            [clocks removeObject:c];
            forgetOutputs(c);
            objc_setAssociatedObject(l, &kClock, nil, OBJC_ASSOCIATION_RETAIN);
        };
        if (NSThread.isMainThread) detach();
        else dispatch_async(dispatch_get_main_queue(), detach);
    });
    for (NSString *name in @[@"setText:", @"setAttributedText:"]) {
        SEL sel = NSSelectorFromString(name);
        void (*write)(UIView *, SEL, id) = (void *)class_getMethodImplementation(UILabel.class, sel);
        replace(UILabel.class, sel, ^(UIView *label, id text) {
            if (SGRWritingProgress && timeLabel(label)) recordOutput(label);
            write(label, sel, text);
        });
    }
    SEL move = @selector(didMoveToWindow);
    void (*moved)(id, SEL) = (void *)class_getMethodImplementation(UILabel.class, move);
    replace(UILabel.class, move, ^(UIView *label) {
        moved(label, move);
        if (timeLabel(label)) SGRProgressOutputMounted(label);
    });
    for (NSString *event in @[SGRPlayerVisibilityDidChangeNotification, UIApplicationDidBecomeActiveNotification,
                              UIWindowDidBecomeKeyNotification]) {
        [NSNotificationCenter.defaultCenter addObserverForName:event object:nil queue:nil usingBlock:^(NSNotification *note) {
            SGRProgressVisibilityChanged();
        }];
    }
}

static void installProgress(Class cls) {
    [NSNotificationCenter.defaultCenter addObserverForName:SGPlayerSpeedDidChangeNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
        SPTPlayerState *state = SGPlayerState();
        SGRProgressPlaybackChanged(state.duration, state.playbackSpeed);
    }];
    // The estimated animation duration can elapse while a finger holds the transition. Only
    // its coordinator's completion (including cancellation) means the field is settled again.
    for (NSString *event in @[SGPlayerTransitionNotification, SGPlayerTransitionEndedNotification]) {
        [NSNotificationCenter.defaultCenter addObserverForName:event object:nil queue:nil usingBlock:^(NSNotification *note) {
            transitioning = [note.name isEqual:SGPlayerTransitionNotification];
            SGRProgressVisibilityChanged();
        }];
    }
    SEL factory = @selector(displayLinkWithTarget:selector:);
    CADisplayLink *(*make)(Class, SEL, id, SEL) = (void *)class_getMethodImplementation(object_getClass(cls), factory);
    replace(object_getClass(cls), factory, ^CADisplayLink *(Class type, id target, SEL sel) {
        CADisplayLink *l = make(type, factory, target, sel);
        if (sel != @selector(displayLinkFired:) || !NSThread.isMainThread) return l;
        const char *name = class_getName(object_getClass(target));
        if (!strstr(name, "NowPlaying_ElementsImpl") || !strstr(name, "WeakWrapper")) return l;
        if (!clocks) hookClocks(cls);
        hookFire(object_getClass(target), sel);
        SGRProgressClock *c = [SGRProgressClock new];
        c->target = target;
        c->link = l;
        c->requested = getPause(l, @selector(isPaused));
        c.requestedRange = getRange(l, @selector(preferredFrameRateRange));
        bindNext(c, YES);
        c->outputs = [NSHashTable weakObjectsHashTable];
        objc_setAssociatedObject(l, &kClock, c, OBJC_ASSOCIATION_RETAIN);
        [clocks addObject:c];
        return l;
    });
}

__attribute__((constructor)) static void progressStart(void) {
    if (!SGRedesignedUI()) return;
    installProgress(CADisplayLink.class);
}
