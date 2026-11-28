#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "Core/SGCore.h"
#import "Shared/Player/PlayerState.h"
#import "Shared/Player/SleepTimer.h"
#import "Redesigned/Player/PlayerMix.h"
#import "Redesigned/Player/PlayerQueue.h"
#import "Redesigned/Player/Player.h"
#import "Redesigned/Kit/SGRKit.h"
#import "../harness-fail.h"

@implementation SPTPlayerTrack
@end
@implementation SPTPlayerState
@end
@implementation SGRGlyphView
- (instancetype)initWithSymbol:(NSString *)symbol pointSize:(CGFloat)size weight:(UIImageSymbolWeight)weight {
    return [super initWithFrame:CGRectZero];
}
- (void)setSymbol:(NSString *)symbol animated:(BOOL)animated {}
@end
@interface QueueTrack : SPTPlayerTrack
@property NSString *UID;
@end
@implementation QueueTrack
@end
@interface QueueState : SPTPlayerState
@property NSString *queueRevision;
@property NSString *playbackId;
@end
@implementation QueueState
@end
@interface SPTCommandOptions : NSObject
@property (nonatomic) BOOL overrideRestrictions;
@end
@implementation SPTCommandOptions
@end
@interface QueueSnapshot : NSObject <NSCopying>
@property SPTPlayerTrack *track;
@property NSArray *prevTracks;
@property NSArray *nextTracks;
@end
@implementation QueueSnapshot
- (id)copyWithZone:(NSZone *)zone {
    QueueSnapshot *copy = [QueueSnapshot new];
    copy.track = self.track;
    copy.prevTracks = self.prevTracks;
    copy.nextTracks = self.nextTracks;
    return copy;
}
@end
@interface QueuePlayer : NSObject
@property QueueSnapshot *currentQueue;
@property BOOL withoutQueueAPI;
@property NSArray<SPTPlayerTrack *> *sentNextTracks;
@property BOOL sentOverrideRestrictions;
@property NSUInteger moves;
@property NSUInteger fetches;
@property (copy) NSString *fetchedRevision;
@property BOOL delayFetch;
@property (copy) void (^reply)(id);
@end
@implementation QueuePlayer
- (BOOL)respondsToSelector:(SEL)selector {
    if (selector == @selector(fetchQueue:on:) && self.withoutQueueAPI) return NO;
    return [super respondsToSelector:selector];
}
- (void)fetchQueue:(void (^)(id))callback on:(dispatch_queue_t)queue {
    self.fetches++;
    self.fetchedRevision = ((QueueState *)SGPlayerState()).queueRevision;
    if (self.delayFetch) self.reply = callback;
    else callback(self.currentQueue);
}
- (id)setQueue:(QueueSnapshot *)queue options:(SPTCommandOptions *)options {
    self.sentNextTracks = queue.nextTracks;
    self.moves++;
    self.sentOverrideRestrictions = options.overrideRestrictions;
    return nil;
}
- (id)skipToNextTrackWithOptions:(id)options track:(SPTPlayerTrack *)track {
    self.currentQueue.track = track; return nil;
}
- (id)skipToPreviousTrackWithOptions:(id)options track:(SPTPlayerTrack *)track {
    self.currentQueue.track = track; return nil;
}
@end

static QueueState *state;
static QueuePlayer *player;
static NSHashTable *observers;
static UITableViewController *screen;
static UIWindow *window;
static int checked;
SPTPlayerState *SGPlayerState(void) { return state; }
id SGPlayerInstance(void) { return player; }
id SGPlayer(void) { return player; }
id SGPlayerAdvanceRepeat(id<SPTPlayer> player, SPTPlayerOptions *options) { return nil; }
void SGAddPlayerStateObserver(id<SGPlayerStateObserver> observer) {
    if (!observers) observers = [NSHashTable weakObjectsHashTable];
    [observers addObject:observer];
}
NSString *SGURIString(id uri) { return [uri isKindOfClass:NSURL.class] ? [uri absoluteString] : uri; }
NSArray *SGPlayerUpcomingTracks(SPTPlayerState *value, NSUInteger limit) { return value.future ?: @[]; }
NSString *SGL(NSString *key, NSString *english) { return english; }
static BOOL stubAutoMixFlag;
static NSNumber *historyPreference;
static BOOL stubAutoMixApplied;
static NSInteger stubAutoMixApplies;
static BOOL stubTransitionKnown;
static SGTransitionSettings stubTransitionSettings;
BOOL SGRedesignedUI(void) { return YES; }
BOOL SGFlag(NSString *key, BOOL fallback) {
    if ([key isEqualToString:@"spotifyglass.automix"]) return stubAutoMixFlag;
    if ([key isEqualToString:SGRKeyPlayerQueueHistory] && historyPreference) return historyPreference.boolValue;
    return fallback;
}
NSInteger SGInt(NSString *key, NSInteger fallback) { return fallback; }
void SGSetEnabled(NSString *key, BOOL on) {
    if ([key isEqualToString:@"spotifyglass.automix"]) stubAutoMixFlag = on;
}
void SGPresentDark(UIViewController *controller) { controller.overrideUserInterfaceStyle = UIUserInterfaceStyleDark; }
UIViewController *SGTopController(void) { return window.rootViewController; }
UIColor *SGRPrimary(void) { return UIColor.whiteColor; }
UIColor *SGRSecondary(void) { return UIColor.grayColor; }
const CGFloat SGRGrid = 8;
const NSTimeInterval SGRCrossfade = 0;
BOOL SGRIncreaseContrast(void) { return NO; }
BOOL SGRReduceMotion(void) { return NO; }
void SGRAnimate(SGRMotion motion, void (^animations)(void), void (^completion)(BOOL finished)) {
    if (animations) animations();
    if (completion) completion(YES);
}
UIFont *SGCategoryCappedFont(UIFontTextStyle style, UIFontWeight weight, UIContentSizeCategory largest) {
    return [UIFont preferredFontForTextStyle:style];
}
SGTransitionFacts *SGAutoMixCurrentTransition(void) { return nil; }
BOOL SGAutoMixAccountAllows(void) { return YES; }
void SGAutoMixApply(BOOL on) {
    stubAutoMixApplied = on;
    stubAutoMixApplies++;
    if (on && stubTransitionKnown) stubTransitionSettings = (SGTransitionSettings){YES, YES, 5000};
    else if (!on && stubTransitionKnown) stubTransitionSettings = (SGTransitionSettings){NO, NO, 0};
}
SGSleepTimerMode SGSleepTimerCurrentMode(void) { return SGSleepTimerOff; }
NSDate *SGSleepTimerEnd(void) { return nil; }
void SGSetSleepTimer(SGSleepTimerMode mode, NSTimeInterval seconds) {}
BOOL SGRMixShowsQueue(void) { return NO; }
BOOL SGRMixTrackIs(SPTPlayerTrack *track, NSString *uri, NSString *uid) { return NO; }
BOOL SGTransitionSettingsRead(SGTransitionSettings *settings) {
    if (!stubTransitionKnown) return NO;
    if (settings) *settings = stubTransitionSettings;
    return YES;
}
const CGFloat SGRRadiusThumb = 6;
// The cover each song's metadata names, landing a turn of the run loop later as a fetched one does; "Current" names none.
// While covers are held none lands, as a slow download's; each fetch's progress is kept by the song's title.
static UIImage *fetchedCover;
static BOOL coversHeld;
static BOOL offline;
static NSMutableDictionary<NSString *, NSProgress *> *coverFetches;
static NSCountedSet<NSString *> *coverAsks;
NSProgress *SGRPlayerTrackCover(SPTPlayerTrack *track, BOOL small, void (^done)(UIImage *image)) {
    if ([track.trackTitle isEqual:@"Current"]) { done(nil); return nil; }
    NSProgress *progress = [NSProgress discreteProgressWithTotalUnitCount:1];
    if (!coverFetches) coverFetches = [NSMutableDictionary dictionary];
    if (!coverAsks) coverAsks = [NSCountedSet set];
    coverFetches[track.trackTitle] = progress;
    [coverAsks addObject:track.trackTitle];
    // On the run loop rather than the main queue, so a check waiting in the run loop (spin) sees it land.
    if (!coversHeld) CFRunLoopPerformBlock(CFRunLoopGetMain(), kCFRunLoopCommonModes, ^{ if (!progress.cancelled) done(offline ? nil : fetchedCover); });
    return progress;
}
NSNotificationName const SGAutoMixTransitionDidChangeNotification = @"queue-test.mix";
NSNotificationName const SGAutoMixPlayerOptionsDidChangeNotification = @"queue-test.options";
NSNotificationName const SGTransitionSettingsDidChangeNotification = @"queue-test.transition-settings";

static void check(BOOL condition, NSString *message) {
    checked++;
    printf("%s %s\n", condition ? "PASS" : "FAIL", message.UTF8String);
    fflush(stdout);
    if (!condition) HARNESS_FAIL(@"%@", message);
}
static QueueTrack *song(NSString *uid, NSString *title) {
    QueueTrack *track = [QueueTrack new];
    track.UID = uid;
    [track setValue:@"spotify:track:duplicate" forKey:@"URI"];
    [track setValue:title forKey:@"trackTitle"];
    [track setValue:@"context" forKey:@"provider"];
    return track;
}
static NSIndexPath *row(NSInteger section, NSInteger index) {
    return [NSIndexPath indexPathForRow:index inSection:section];
}
static NSArray *titles(NSInteger section) {
    NSMutableArray *values = [NSMutableArray new];
    for (NSInteger i = 0; i < [screen tableView:screen.tableView numberOfRowsInSection:section]; i++) {
        UITableViewCell *cell = [screen tableView:screen.tableView cellForRowAtIndexPath:row(section, i)];
        [values addObject:((UIListContentConfiguration *)cell.contentConfiguration).text];
    }
    return values;
}
static UILabel *labelIn(UIView *view, NSString *text) {
    if ([view isKindOfClass:UILabel.class] && [((UILabel *)view).text isEqual:text]) return (UILabel *)view;
    for (UIView *child in view.subviews) {
        UILabel *found = labelIn(child, text);
        if (found) return found;
    }
    return nil;
}
static void until(NSString *what, BOOL (^ready)(void)) {
    NSTimeInterval deadline = NSProcessInfo.processInfo.systemUptime + 45;
    while (!ready()) {
        if (NSProcessInfo.processInfo.systemUptime >= deadline) HARNESS_FAIL(@"queue: waiting for %@", what);
        [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
    }
}
static NSUInteger visibleHeadings(UIView *view, NSString *text) {
    if (view.hidden || view.alpha <= 0 || !view.window) return 0;
    NSUInteger count = [view isKindOfClass:UILabel.class] &&
        [((UILabel *)view).text isEqual:text] && !CGRectIsEmpty(view.bounds) ? 1 : 0;
    for (UIView *child in view.subviews) count += visibleHeadings(child, text);
    return count;
}
static void report(NSString *revision) {
    state.queueRevision = revision;
    for (id<SGPlayerStateObserver> observer in observers.allObjects) [observer playerStateDidReport:state];
}

static UIView *findReorderControl(UIView *view) {
    if ([NSStringFromClass(view.class) containsString:@"Reorder"]) return view;
    for (UIView *sub in view.subviews) {
        UIView *found = findReorderControl(sub);
        if (found) return found;
    }
    return nil;
}

@interface SGRPlayerQueueController : UITableViewController
- (instancetype)initMusicStyle;
- (BOOL)tableView:(UITableView *)table canMoveRowAtIndexPath:(NSIndexPath *)path;
- (void)tableView:(UITableView *)table willBeginReorderingRowAtIndexPath:(NSIndexPath *)path;
- (void)tableView:(UITableView *)table moveRowAtIndexPath:(NSIndexPath *)from toIndexPath:(NSIndexPath *)to;
- (void)tableView:(UITableView *)table didEndReorderingRowAtIndexPath:(NSIndexPath *)path;
- (void)tableView:(UITableView *)table didCancelReorderingRowAtIndexPath:(NSIndexPath *)path;
- (SPTPlayerTrack *)trackAt:(NSIndexPath *)path;
- (CGFloat)restOffset;
- (void)playerStateDidReport:(SPTPlayerState *)state;
@end

// Hand the data source a known, previously clipped cell on its next dequeue.
@interface ReuseTable : UITableView
@property UITableViewCell *reused;
@end
@implementation ReuseTable
- (UITableViewCell *)dequeueReusableCellWithIdentifier:(NSString *)identifier { return self.reused; }
@end
@interface MusicQueueCheck : SGRPlayerQueueController
@end
@implementation MusicQueueCheck {
    NSUInteger _passes;
}
- (void)viewDidLayoutSubviews {
    // Bound a non-converging UIKit layout (nested or successive passes) without crashing the harness.
    if (++_passes > 32) HARNESS_FAIL(@"offscreen empty queue layout did not settle");
    [super viewDidLayoutSubviews];
}
@end

// UIKit has no touch stream in the harness. Supply the recognizer's motion and hit-test the mounted
// queue at the resulting coordinates, leaving gestureRecognizerShouldBegin: to the production table.
@interface QueuePan : UIPanGestureRecognizer
@property CGPoint start;
@end
@implementation QueuePan
- (CGPoint)locationInView:(UIView *)view { return CGPointMake(_start.x - 60, _start.y + 24); }
- (CGPoint)translationInView:(UIView *)view { return CGPointMake(-60, 24); }
@end
@interface SGRQueueTableView : UITableView
@end
@interface PanTable : SGRQueueTableView
@property QueuePan *testPan;
@property (weak) UITableView *mounted;
@end
@implementation PanTable
- (UIPanGestureRecognizer *)panGestureRecognizer { return _testPan ?: super.panGestureRecognizer; }
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event { return [_mounted hitTest:point withEvent:event]; }
@end

static BOOL panCanBeginOn(UITableView *table, UIView *target) {
    CGPoint center = CGPointMake(CGRectGetMidX(target.bounds), CGRectGetMidY(target.bounds));
    CGPoint start = [target convertPoint:center toView:table];
    if (!target.window || ![[table hitTest:start withEvent:nil] isDescendantOfView:target])
        HARNESS_FAIL(@"pan target is not hittable: %@", target);
    PanTable *probe = [PanTable new];
    probe.mounted = table;
    probe.testPan = [QueuePan new];
    probe.testPan.start = start;
    return [probe gestureRecognizerShouldBegin:probe.panGestureRecognizer];
}

static void dropRow(SGRPlayerQueueController *list, NSIndexPath *from, NSIndexPath *to) {
    [list tableView:list.tableView willBeginReorderingRowAtIndexPath:from];
    [list tableView:list.tableView moveRowAtIndexPath:from toIndexPath:to];
    [list tableView:list.tableView didEndReorderingRowAtIndexPath:to];
    until(@"drop finished", ^BOOL { return ![[list valueForKey:@"reordering"] boolValue]; });
}

static void checkFetchRecovery(SGRPlayerQueueController *list, NSIndexPath *from, NSIndexPath *to) {
    SPTPlayerTrack *original = [list trackAt:from];
    NSUInteger moves = player.moves;
    NSInteger history = [list tableView:list.tableView numberOfRowsInSection:0];
    player.delayFetch = YES;
    dropRow(list, from, to);
    until(@"rejected move's fetch", ^BOOL { return player.reply != nil; });
    player.reply(nil);
    player.reply = nil;
    check(player.moves == moves + 1 && [list trackAt:from] == original &&
          [list tableView:list.tableView numberOfRowsInSection:0] == history &&
          ![list tableView:list.tableView canMoveRowAtIndexPath:from],
          @"a nil response immediately restores the player's row order and matching History");

    player.delayFetch = NO;
    [list playerStateDidReport:state];
    dropRow(list, from, to);
    check(player.moves == moves + 1 && [list trackAt:from] == original,
          @"a failed read restores the display without releasing the submitted revision for another move");
    state.queueRevision = @"303-retry";
    [list playerStateDidReport:state];
    dropRow(list, from, to);
    player.delayFetch = YES;
    until(@"post-drop fetch to withhold", ^BOOL { return player.reply != nil; });
    void (^expired)(id) = player.reply;
    player.reply = nil;
    QueueSnapshot *late = [player.currentQueue copy];
    late.nextTracks = @[];
    state.queueRevision = @"304";
    [list playerStateDidReport:state];
    until(@"new fetch after missing response expires", ^BOOL { return player.reply != nil; });
    expired(late);
    check(player.moves == moves + 2 && [list trackAt:from] == original &&
          ![list tableView:list.tableView canMoveRowAtIndexPath:from],
          @"a lost reply expires, rolls back the move and cannot replace the in-flight retry with stale rows");
    player.delayFetch = NO;
    player.reply(player.currentQueue);
    player.reply = nil;
    dropRow(list, from, to);
    check(player.moves == moves + 3 && [list trackAt:to] == original,
          @"editing works again after the retry supplies a fresh snapshot");
    player.delayFetch = YES;
    until(@"read on unchanged revision", ^BOOL { return player.reply != nil; });
    player.reply = nil; // The read expires with both the revision and the queue still unchanged.
    until(@"retry on unchanged revision", ^BOOL { return player.reply != nil; });
    player.delayFetch = NO;
    player.reply(player.currentQueue);
    player.reply = nil;
    dropRow(list, from, to);
    check(player.moves == moves + 3 && [list trackAt:from] == original &&
          ![list tableView:list.tableView canMoveRowAtIndexPath:from],
          @"the pre-move queue after a timeout cannot authorize another submission on the same revision");
    player.currentQueue.nextTracks = player.sentNextTracks;
    [state setValue:player.sentNextTracks forKey:@"future"];
    QueueTrack *current = (QueueTrack *)state.track;
    current.UID = nil;
    report(@"305");
    dropRow(list, to, from);
    check(player.moves == moves + 4 && [list trackAt:from] == original,
          @"the acknowledged revision permits the next move after timeout recovery");
    player.delayFetch = YES;
    current.UID = @"resolved-current-uid";
    [list playerStateDidReport:state];
    check(player.reply != nil, @"a newly available current track UID refreshes the queue display");
    player.delayFetch = NO;
    player.reply(player.currentQueue);
    player.reply = nil;
    dropRow(list, to, from);
    check(player.moves == moves + 4,
          @"a late current track UID cannot authorize a second move on the same playback ID and revision");
    state.playbackId = @"new playback";
    [list playerStateDidReport:state];
    dropRow(list, to, from);
    check(player.moves == moves + 5 && [list trackAt:from] == original,
          @"a new playback session can edit its own queue with the same revision number");
    player.currentQueue.nextTracks = player.sentNextTracks;
    [state setValue:player.sentNextTracks forKey:@"future"];
    report(@"306");
}

static void checkQueueDrag(SGRPlayerQueueController *list, UIViewController *page, UIScrollView *outer, NSArray *past) {
    UITableView *table = list.tableView;
    until(@"previous drop finished", ^BOOL { return ![[list valueForKey:@"reordering"] boolValue]; });
    outer.frame = CGRectMake(0, 0, 320, 460);
    page.view.frame = outer.bounds;
    [page.view layoutIfNeeded];
    NSMutableArray *next = [NSMutableArray array];
    for (NSInteger i = 0; i < 28; i++) {
        NSString *title = [NSString stringWithFormat:@"Upcoming %ld", (long)i];
        [next addObject:song(title, title)];
    }
    [state setValue:player.currentQueue.track forKey:@"track"];
    [state setValue:next forKey:@"future"];
    player.currentQueue.nextTracks = next;
    player.currentQueue.prevTracks = past;
    report(@"300");
    NSInteger section = table.numberOfSections - 1;
    CGFloat rest = [list restOffset], shift = 320;
    table.contentOffset = CGPointMake(0, rest + shift);
    [table layoutIfNeeded];
    NSIndexPath *from = row(section, 6), *to = row(section, 7);
    UITableViewCell *lifted = [table cellForRowAtIndexPath:from];
    check(lifted && !table.dragInteractionEnabled && table.estimatedRowHeight == 0 && table.estimatedSectionHeaderHeight == 0,
          @"narrow queue uses measured heights and native editing grips");
    check(!panCanBeginOn(table, findReorderControl(lifted)), @"the table pan yields a drag that began on the mounted grip");
    check(panCanBeginOn(table, [page valueForKey:@"mix"]), @"the table pan accepts a drag that began on a queue toggle");
    check(panCanBeginOn(table, lifted.contentView), @"the table pan accepts a drag that began on an ordinary row");

    // Both cells have the same local frame. Only the one under the pin in TABLE coordinates should be clipped.
    UIView *wrapper = [[UIView alloc] initWithFrame:CGRectMake(0, table.contentOffset.y + 200, 100, 100)];
    UITableViewCell *probe = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"track"];
    probe.frame = CGRectMake(0, 0, 100, 56);
    [table addSubview:wrapper];
    [wrapper addSubview:probe];
    [list tableView:table willDisplayCell:probe forRowAtIndexPath:from];
    check(!probe.layer.mask, @"a row in a translated container stays visible below the pins");
    wrapper.frame = CGRectOffset(wrapper.frame, 0, -200);
    [list tableView:table willDisplayCell:probe forRowAtIndexPath:from];
    CALayer *cut = probe.layer.mask;
    ReuseTable *reuse = [ReuseTable new];
    reuse.reused = probe;
    [list tableView:reuse cellForRowAtIndexPath:to];
    check(cut && !probe.layer.mask, @"reconfiguring a reused row clears the queue's clipping mask");
    CALayer *other = [CAGradientLayer layer];
    probe.layer.mask = other;
    [list tableView:reuse cellForRowAtIndexPath:to];
    [list tableView:table willDisplayCell:probe forRowAtIndexPath:from];
    check(probe.layer.mask == other, @"reuse and pinning preserve another component's mask");
    [wrapper removeFromSuperview];

    NSUInteger before = player.moves;
    lifted.layer.mask = cut;
    [list tableView:table willBeginReorderingRowAtIndexPath:from];
    table.contentOffset = CGPointMake(0, CGRectGetMinY([table rectForRowAtIndexPath:from]) - 1);
    [list tableView:table willDisplayCell:lifted forRowAtIndexPath:from];
    check(lifted.backgroundView && !lifted.layer.mask, @"a lifted row loses its clipping mask and stays unmasked");
    table.contentOffset = CGPointMake(0, rest + shift);
    [list tableView:table moveRowAtIndexPath:from toIndexPath:to];
    [list tableView:table didEndReorderingRowAtIndexPath:to];
    until(@"optimistic drop finished", ^BOOL { return ![[list valueForKey:@"reordering"] boolValue]; });
    check(player.moves == before + 1 && [list trackAt:to] == next[6] && [list trackAt:from] == next[7] &&
          fabs(table.contentOffset.y - rest - shift) < 1 && [list tableView:table numberOfRowsInSection:0] == 10,
          @"the scrolled queue keeps its dropped order, viewport and History before Spotify acknowledges the move");

    player.delayFetch = YES;
    until(@"post-drop fetch before acknowledgement", ^BOOL { return player.reply != nil; });
    player.reply(player.currentQueue);
    player.reply = nil;
    dropRow(list, from, to);
    check(player.moves == before + 1 && [list trackAt:to] == next[6],
          @"an old queue fetched before the new revision cannot undo the move or authorize a second submission");
    state.queueRevision = @"301";
    [list playerStateDidReport:state];
    [list tableView:table willBeginReorderingRowAtIndexPath:from];
    [list tableView:table moveRowAtIndexPath:from toIndexPath:to];
    [list tableView:table didCancelReorderingRowAtIndexPath:from];
    until(@"unconfirmed second lift cancelled", ^BOOL { return ![[list valueForKey:@"reordering"] boolValue]; });
    check(player.reply && player.moves == before + 1 && [list trackAt:to] == next[6] &&
          [list tableView:table numberOfRowsInSection:0] == 10 && [list tableView:table canMoveRowAtIndexPath:from],
          @"a report with empty reverse keeps History and grips while a second drag cannot submit the old revision");
    player.currentQueue.nextTracks = player.sentNextTracks;
    player.currentQueue.prevTracks = [past subarrayWithRange:NSMakeRange(0, 4)];
    player.delayFetch = NO;
    player.reply(player.currentQueue);
    player.reply = nil;
    check([list restOffset] < rest && fabs(table.contentOffset.y - [list restOffset] - shift) < 1 &&
          [list trackAt:to] == next[6], @"a shorter fetched History keeps the same upcoming songs under the viewport");
    [list tableView:table willBeginReorderingRowAtIndexPath:from];
    [list tableView:table moveRowAtIndexPath:from toIndexPath:to];
    [list tableView:table didEndReorderingRowAtIndexPath:to];
    until(@"confirmed second lift finished", ^BOOL { return ![[list valueForKey:@"reordering"] boolValue]; });
    check(player.moves == before + 2 && [player.sentNextTracks isEqual:next], @"a fresh snapshot accepts the next edit");
    player.currentQueue.nextTracks = player.sentNextTracks;
    report(@"302");

    historyPreference = @NO;
    report(@"302");
    check(table.numberOfSections == 2 && screen.tableView.numberOfSections == 2 &&
          [[screen tableView:screen.tableView titleForHeaderInSection:0] isEqual:@"Now Playing"],
          @"turning off History removes its section from the Music and sheet lists on the same revision");
    historyPreference = @YES;
    report(@"302");
    check(table.numberOfSections == 3 && screen.tableView.numberOfSections == 3 &&
          [list tableView:table numberOfRowsInSection:0] == 4 && titles(0).count == 4,
          @"turning History on restores the cached tracks to both lists");

    [list tableView:table willBeginReorderingRowAtIndexPath:from];
    NSArray *replacement = next.reverseObjectEnumerator.allObjects;
    [state setValue:replacement forKey:@"future"];
    player.currentQueue.nextTracks = replacement;
    report(@"303");
    [list tableView:table moveRowAtIndexPath:from toIndexPath:to];
    [list tableView:table didEndReorderingRowAtIndexPath:to];
    until(@"interrupted drop finished", ^BOOL { return ![[list valueForKey:@"reordering"] boolValue]; });
    check(player.moves == before + 2 && [list trackAt:from] == replacement[6],
          @"an authoritative queue received during a lift wins without submitting the interrupted move");
    checkFetchRecovery(list, from, to);

    UIView *host = outer.superview;
    UIPanGestureRecognizer *active = [UIPanGestureRecognizer new], *disabled = [UIPanGestureRecognizer new];
    [host addGestureRecognizer:active];
    [host addGestureRecognizer:disabled];
    disabled.enabled = NO;
    [table layoutIfNeeded];
    lifted = [table cellForRowAtIndexPath:from];
    [list tableView:table willBeginReorderingRowAtIndexPath:from];
    check(lifted.backgroundView && !active.enabled && !outer.panGestureRecognizer.enabled,
          @"a lift pauses pans on both scrolling and ordinary ancestor views");
    [list viewWillDisappear:NO];
    check(![[list valueForKey:@"reordering"] boolValue] && active.enabled && !disabled.enabled && !lifted.backgroundView,
          @"a disappearing controller releases its lift and ancestor pans before detachment");
    [list tableView:table willBeginReorderingRowAtIndexPath:from];
    lifted = [table cellForRowAtIndexPath:from];
    check(lifted.backgroundView && !active.enabled, @"a second lift starts cleanly before window detachment");
    [page.view removeFromSuperview];
    [list tableView:table didCancelReorderingRowAtIndexPath:from];
    [list viewWillDisappear:NO];
    check(![[list valueForKey:@"reordering"] boolValue] && ![list valueForKey:@"dragSnapshot"] &&
          !lifted.backgroundView && active.enabled && outer.panGestureRecognizer.enabled && !disabled.enabled,
          @"detaching mid-drag clears the lift and restores only originally active pans across repeated cleanup");
    [host removeGestureRecognizer:active];
    [host removeGestureRecognizer:disabled];
}

static const NSNotificationName kQueueTestResign = @"queue.check.resign";
static const NSNotificationName kQueueTestActivate = @"queue.check.activate";

static void loadQueuePageWithTestLifecycle(UIViewController *page) {
    // Catalyst's scene machinery also consumes UIKit's real lifecycle notifications. Reposting activation
    // while it is already active raises an exception. Redirect only the list's registrations to test names.
    SEL selector = @selector(addObserver:selector:name:object:);
    Method method = class_getInstanceMethod(NSNotificationCenter.class, selector);
    IMP original = method_getImplementation(method);
    Class listClass = NSClassFromString(@"SGRPlayerQueueController");
    IMP replacement = imp_implementationWithBlock(^(NSNotificationCenter *center, id observer, SEL action, NSString *name, id object) {
        if ([observer isKindOfClass:listClass]) {
            if ([name isEqual:UIApplicationWillResignActiveNotification]) name = kQueueTestResign;
            if ([name isEqual:UIApplicationDidBecomeActiveNotification]) name = kQueueTestActivate;
        }
        ((void (*)(id, SEL, id, SEL, NSString *, id))original)(center, selector, observer, action, name, object);
    });
    method_setImplementation(method, replacement);
    [page loadViewIfNeeded];
    method_setImplementation(method, original);
    imp_removeBlock(replacement);
}

static void checkQueueVisibility(SGRPlayerQueueController *list, UIViewController *page, UIScrollView *outer) {
    screen.view.hidden = YES;
    NSArray *submitted = [list valueForKey:@"submittedKey"];
    check(submitted != nil, @"the visibility fixture has a submitted queue move");
    NSUInteger fetches = player.fetches;
    UITableView *table = list.tableView;
    table.hidden = YES;
    report(@"hidden-1");
    report(@"hidden-2");
    check(player.fetches == fetches && [[list valueForKey:@"submittedKey"] isEqual:submitted] &&
          [list valueForKey:@"snapshot"] == nil,
          @"hidden reports defer RPC and keep the submitted revision");
    report(submitted.lastObject);
    table.hidden = NO;
    check(player.fetches == ++fetches && [player.fetchedRevision isEqual:submitted.lastObject] &&
          [[list valueForKey:@"submittedKey"] isEqual:submitted] && [list valueForKey:@"snapshot"] == nil,
          @"unhiding fetches the current revision once without allowing a duplicate move");

    UIApplication *app = UIApplication.sharedApplication;
    Method method = class_getInstanceMethod(app.class, @selector(applicationState));
    __block UIApplicationState appState = UIApplicationStateInactive;
    IMP replacement = imp_implementationWithBlock(^UIApplicationState(id owner) { return appState; });
    IMP original = method_setImplementation(method, replacement);
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    [center postNotificationName:kQueueTestResign object:nil];
    report(@"inactive-1");
    report(@"inactive-2");
    check(player.fetches == fetches && [[list valueForKey:@"submittedKey"] isEqual:submitted],
          @"inactive reports defer RPC and keep the submitted revision");
    appState = UIApplicationStateActive;
    [center postNotificationName:kQueueTestActivate object:nil];
    check(player.fetches == ++fetches && [player.fetchedRevision isEqual:@"inactive-2"] &&
          [list valueForKey:@"snapshot"] != nil, @"activation fetches only the latest inactive revision");
    player.delayFetch = YES;
    report(@"in-flight");
    void (^firstReply)(id) = player.reply;
    player.reply = nil;
    check(firstReply && player.fetches == ++fetches, @"first same-revision RPC is in flight");
    appState = UIApplicationStateInactive;
    [center postNotificationName:kQueueTestResign object:nil];
    check(![[list valueForKey:@"fetching"] boolValue] && [list valueForKey:@"snapshot"] == nil,
          @"the registered resign observer invalidates the in-flight request");
    appState = UIApplicationStateActive;
    [center postNotificationName:kQueueTestActivate object:nil];
    void (^freshReply)(id) = player.reply;
    player.reply = nil;
    check(freshReply && player.fetches == ++fetches && [player.fetchedRevision isEqual:@"in-flight"],
          @"the registered activation observer refetches the same revision once");
    QueueSnapshot *stale = [player.currentQueue copy];
    stale.nextTracks = @[];
    firstReply(stale);
    check([[list valueForKey:@"fetching"] boolValue] && [list valueForKey:@"snapshot"] == nil,
          @"the old callback cannot consume the new request");
    freshReply(player.currentQueue);
    firstReply(stale);
    check([list valueForKey:@"snapshot"] == player.currentQueue && player.fetches == fetches,
          @"the late old callback leaves the fresh editable snapshot intact");
    player.delayFetch = NO;
    method_setImplementation(method, original);
    imp_removeBlock(replacement);

    UIControl *mix = [page valueForKey:@"mix"];
    check([[mix valueForKey:@"on"] boolValue], @"parent visibility fixture starts with AutoMix on");
    page.view.hidden = YES;
    check([list valueForKey:@"snapshot"] == nil, @"hiding the page immediately clears the list snapshot");
    QueueTrack *latest = song(@"page-latest", @"Latest while page hidden");
    NSArray *originalTracks = player.currentQueue.nextTracks;
    player.currentQueue.nextTracks = @[latest];
    stubTransitionSettings = (SGTransitionSettings){NO, NO, 0};
    report(@"page-hidden-1");
    report(@"page-hidden-2");
    check(player.fetches == fetches && [[mix valueForKey:@"on"] boolValue],
          @"reports while only the parent is hidden defer RPC and options");
    page.view.hidden = NO;
    NSInteger section = list.tableView.numberOfSections - 1;
    check(player.fetches == ++fetches && [player.fetchedRevision isEqual:@"page-hidden-2"] &&
          [list valueForKey:@"snapshot"] == player.currentQueue && [list trackAt:row(section, 0)] == latest &&
          ![[mix valueForKey:@"on"] boolValue],
          @"unhiding the parent restores latest rows, editable snapshot and options without another report");
    player.currentQueue.nextTracks = originalTracks;

    [page.view removeFromSuperview];
    report(@"detached-1");
    report(@"detached-2");
    check(player.fetches == fetches, @"detached reports do not fetch");
    [outer addSubview:page.view];
    check(player.fetches == ++fetches && [player.fetchedRevision isEqual:@"detached-2"],
          @"reattachment fetches only the latest detached revision");
    screen.view.hidden = NO;
}

static void run(void) {
    fetchedCover = [[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(8, 8)] imageWithActions:^(UIGraphicsImageRendererContext *context) {}];
    player = [QueuePlayer new];
    player.currentQueue = [QueueSnapshot new];
    player.currentQueue.track = song(@"current", @"Current");
    [player.currentQueue.track setValue:@"spotify:track:current" forKey:@"URI"];
    player.currentQueue.prevTracks = @[song(@"old", @"Earlier"), song(@"recent", @"Recent")];
    player.currentQueue.nextTracks = @[song(@"one", @"First occurrence"), song(@"two", @"Second occurrence")];
    state = [QueueState new]; state.playbackId = @"playback"; state.queueRevision = @"100";
    [state setValue:player.currentQueue.track forKey:@"track"];
    screen = [NSClassFromString(@"SGRPlayerQueueController") new];
    window.rootViewController = [[UINavigationController alloc] initWithRootViewController:screen];
    [screen loadViewIfNeeded];
    until(@"attached queue receives its first snapshot", ^BOOL { return titles(2).count == 2; });
    check([titles(0) isEqual:@[@"Earlier", @"Recent"]] && [titles(1) isEqual:@[@"Current"]] &&
          [titles(2) isEqual:@[@"First occurrence", @"Second occurrence"]], @"Spotify History appears chronologically above current and Up Next");
    UITableView *table = screen.tableView;
    [table layoutIfNeeded];
    until(@"Up Next section mounted", ^BOOL { return [table headerViewForSection:2].window != nil; });
    check(visibleHeadings([table headerViewForSection:2], @"Up Next") == 1,
          @"Up Next has exactly one visible heading");
    UILabel *now = labelIn([table headerViewForSection:1], @"Now Playing"), *next = labelIn([table headerViewForSection:2], @"Up Next");
    CGFloat nowX = CGRectGetMinX([table convertRect:now.bounds fromView:now]), nextX = CGRectGetMinX([table convertRect:next.bounds fromView:next]);
    check(now && next && fabs(nowX - nextX) < 0.5,
          [NSString stringWithFormat:@"the Up Next heading starts where the system's Now Playing heading does (%.1f, %.1f)", nextX, nowX]);
    NSString *screenshot = NSProcessInfo.processInfo.environment[@"QUEUE_SCREENSHOT"];
    if (screenshot.length) {
        UIImage *image = [[[UIGraphicsImageRenderer alloc] initWithBounds:window.bounds]
            imageWithActions:^(UIGraphicsImageRendererContext *context) {
                [window drawViewHierarchyInRect:window.bounds afterScreenUpdates:YES];
            }];
        check([UIImagePNGRepresentation(image) writeToFile:screenshot atomically:YES], @"queue screenshot saved");
    }
    UIImage *(^shown)(NSIndexPath *) = ^UIImage *(NSIndexPath *path) {
        return ((UIListContentConfiguration *)[table cellForRowAtIndexPath:path].contentConfiguration).image;
    };
    until(@"first row's fetched cover", ^BOOL { return shown(row(2, 0)) == fetchedCover; });
    check(shown(row(2, 0)) == fetchedCover && shown(row(1, 0)) && shown(row(1, 0)) != fetchedCover,
          @"a row takes the cover its song's metadata names as it lands; a song without one keeps the placeholder");
    UITableViewCell *history = [screen tableView:screen.tableView cellForRowAtIndexPath:row(0, 1)];
    [screen tableView:screen.tableView didSelectRowAtIndexPath:row(0, 1)];
    check(history.selectionStyle == UITableViewCellSelectionStyleNone &&
          history.accessibilityTraits == UIAccessibilityTraitStaticText &&
          [player.currentQueue.track.trackTitle isEqual:@"Current"], @"History is readable without changing playback");
    NSMutableArray *past = [NSMutableArray new];
    for (NSInteger i = 1; i <= 12; i++) {
        NSString *title = [NSString stringWithFormat:@"%ld", (long)i];
        [past addObject:song(title, title)];
    }
    player.currentQueue.prevTracks = past;
    report(@"101");
    check([titles(0) isEqual:@[@"3", @"4", @"5", @"6", @"7", @"8", @"9", @"10", @"11", @"12"]], @"queue reports show only the ten most recent songs");
    player.currentQueue.prevTracks = nil;
    report(@"102");
    check(titles(0).count == 0 && [screen tableView:screen.tableView titleForHeaderInSection:0] == nil,
          @"empty Spotify History has no heading or rows");
    QueueTrack *episode = song(@"episode", @"Podcast"), *local = song(@"local", @"Local recording");
    [episode setValue:@"spotify:episode:episode" forKey:@"URI"];
    [local setValue:@"spotify:local:artist:album:title:123" forKey:@"URI"];
    player.currentQueue.nextTracks = @[episode, local];
    report(@"103");
    check([titles(2) isEqual:@[@"Podcast", @"Local recording"]], @"whole queue preserves episode and local Up Next eligibility");
    for (NSNumber *missingAPI in @[@NO, @YES]) {
        player.withoutQueueAPI = missingAPI.boolValue;
        [state setValue:@[episode] forKey:@"future"];
        report(missingAPI.boolValue ? @"104" : nil);
        [state setValue:@[local, episode] forKey:@"future"];
        report(missingAPI.boolValue ? @"104" : nil);
        check([titles(2) isEqual:@[@"Local recording", @"Podcast"]], @"compatibility reports refresh changed future with the same current track");
    }
    [screen tableView:screen.tableView didSelectRowAtIndexPath:row(2, 1)];
    check([((QueueTrack *)player.currentQueue.track).UID isEqual:@"episode"], @"Up Next retains its episode skip action");
    coversHeld = YES;
    player.withoutQueueAPI = NO;
    QueueTrack *kept = song(@"kept", @"Kept"), *dropped = song(@"dropped", @"Dropped");
    [kept setValue:@"spotify:track:kept" forKey:@"URI"];
    [dropped setValue:@"spotify:track:dropped" forKey:@"URI"];
    player.currentQueue.nextTracks = @[kept, dropped];
    [state setValue:@[kept, dropped] forKey:@"future"];
    report(@"105");
    titles(2);
    NSProgress *keptCover = coverFetches[@"Kept"], *droppedCover = coverFetches[@"Dropped"];
    player.currentQueue.nextTracks = @[kept];
    [state setValue:@[kept] forKey:@"future"];
    report(@"106");
    check(keptCover && droppedCover && droppedCover.cancelled && !keptCover.cancelled,
          @"a cover still coming for a song gone from the list is cancelled; a listed song's keeps coming");
    [screen.navigationController pushViewController:[UIViewController new] animated:NO];
    until(@"pending cover cancelled on departure", ^BOOL { return keptCover.cancelled; });
    check(keptCover.cancelled, @"Playing Next leaving the screen cancels the covers still coming");
    // Back with the same cells: first the cancelled request is retried offline, then the failed request online.
    coversHeld = NO;
    offline = YES;
    NSUInteger cancelledAsks = [coverAsks countForObject:@"Kept"];
    [screen.navigationController popViewControllerAnimated:NO];
    until(@"offline row displayed and cover requested", ^BOOL {
        return shown(row(2, 0)) && [coverAsks countForObject:@"Kept"] > cancelledAsks;
    });
    check(shown(row(2, 0)) && shown(row(2, 0)) != fetchedCover && [coverAsks countForObject:@"Kept"] == cancelledAsks + 1,
          @"back on screen offline, the cancelled cover is requested again but stays a placeholder");
    [screen.navigationController pushViewController:[UIViewController new] animated:NO];
    until(@"queue left the window", ^BOOL { return !screen.view.window; });
    offline = NO;
    NSUInteger keptAsks = [coverAsks countForObject:@"Kept"];
    [screen.navigationController popViewControllerAnimated:NO];
    until(@"retried cover displayed", ^BOOL { return shown(row(2, 0)) == fetchedCover; });
    check(shown(row(2, 0)) == fetchedCover && [coverAsks countForObject:@"Kept"] == keptAsks + 1,
          [NSString stringWithFormat:@"Playing Next shown again retries the failed cover once and shows it (%lu asks)",
                                     (unsigned long)([coverAsks countForObject:@"Kept"] - keptAsks)]);
    NSUInteger asksShown = coverAsks.count, totalAsks = 0;
    for (NSString *title in coverAsks) totalAsks += [coverAsks countForObject:title];
    [screen.navigationController pushViewController:[UIViewController new] animated:NO];
    [screen.navigationController popViewControllerAnimated:NO];
    until(@"queue redisplayed with cached cover", ^BOOL { return screen.view.window && shown(row(2, 0)) == fetchedCover; });
    NSUInteger totalAfter = 0;
    for (NSString *title in coverAsks) totalAfter += [coverAsks countForObject:title];
    check(coverAsks.count == asksShown && totalAfter == totalAsks, @"shown again with every cover in, no cover is asked for again");
    QueueTrack *late = song(@"late", @"Late");
    [late setValue:@"spotify:track:late" forKey:@"URI"];
    offline = YES;
    player.currentQueue.nextTracks = @[late];
    report(@"107");
    until(@"new row requested its cover", ^BOOL { return [coverAsks countForObject:@"Late"] > 0 && [table cellForRowAtIndexPath:row(2, 0)]; });
    // Deliver the fixture's offline completion before switching it online.
    __block BOOL drained = NO;
    CFRunLoopPerformBlock(CFRunLoopGetMain(), kCFRunLoopCommonModes, ^{ drained = YES; });
    until(@"offline reply delivered", ^BOOL { return drained; });
    NSIndexPath *path = row(2, 0);
    UITableViewCell *prepared = [table cellForRowAtIndexPath:path];
    check(prepared && shown(path) != fetchedCover && [coverAsks countForObject:@"Late"] > 0,
          @"the prepared row has a failed cover");
    offline = NO;
    // UIKit can redisplay this cell without asking the data source to configure it again.
    if ([table.delegate respondsToSelector:@selector(tableView:willDisplayCell:forRowAtIndexPath:)])
        [table.delegate tableView:table willDisplayCell:prepared forRowAtIndexPath:path];
    until(@"prepared row shows fetched cover", ^BOOL { return shown(path) == fetchedCover; });
    check(shown(path) == fetchedCover, @"redisplay of the prepared row retries and shows its failed cover");
    // The closed Music page lays out the local empty state without fetching a snapshot.
    MusicQueueCheck *music = [[MusicQueueCheck alloc] initMusicStyle];
    player.withoutQueueAPI = NO;
    player.currentQueue.nextTracks = @[];
    [state setValue:@[] forKey:@"future"];
    UITableView *closedTable = music.tableView;
    closedTable.frame = CGRectMake(0, 0, 402, 446);
    do {
        [closedTable layoutIfNeeded];
    } while (closedTable.layer.needsLayout);
    UIView *footer = closedTable.tableFooterView;
    check(!closedTable.window && CGRectGetMinY(footer.frame) > 0 &&
          labelIn(footer, @"No songs are in the queue."),
          @"the offscreen empty Music queue lays out its message below the sections and settles");

    // Issue #74: Music queue grip drags immediately even inside an outer scroll view, toggles still cancel into scroll,
    // reordering submits the moved track order, and the AutoMix toggle follows Spotify Playback settings.
    QueueTrack *moveA = song(@"moveA", @"Move First"), *moveB = song(@"moveB", @"Move Second");
    [moveA setValue:@"spotify:track:moveA" forKey:@"URI"];
    [moveB setValue:@"spotify:track:moveB" forKey:@"URI"];
    player.currentQueue.nextTracks = @[moveA, moveB];
    player.sentNextTracks = nil;
    player.sentOverrideRestrictions = NO;
    [state setValue:@[moveA, moveB] forKey:@"future"];
    state.queueRevision = @"200";
    stubAutoMixFlag = YES;
    stubTransitionKnown = YES;
    stubTransitionSettings = (SGTransitionSettings){YES, YES, 5000};
    stubAutoMixApplies = 0;
    UIViewController *musicPage = ((UIViewController *(*)(void))SGRPlayerQueuePage)();
    UIScrollView *outer = [[UIScrollView alloc] initWithFrame:window.bounds];
    outer.delaysContentTouches = YES;
    [window.rootViewController.view addSubview:outer];
    [window.rootViewController addChildViewController:musicPage];
    loadQueuePageWithTestLifecycle(musicPage);
    musicPage.view.frame = outer.bounds;
    [outer addSubview:musicPage.view];
    [musicPage didMoveToParentViewController:window.rootViewController];
    SGRPlayerQueuePageConfigure(musicPage, 90, nil);
    [musicPage.view layoutIfNeeded];
    SGRPlayerQueueController *musicList = (SGRPlayerQueueController *)musicPage.childViewControllers.firstObject;
    UITableView *musicTable = musicList.tableView;
    [musicTable layoutIfNeeded];
    NSInteger upcomingSection = [musicTable numberOfSections] - 1;
    UITableViewCell *firstCell = [musicTable cellForRowAtIndexPath:row(upcomingSection, 0)];
    [firstCell layoutIfNeeded];
    UIView *reorderGrip = findReorderControl(firstCell);
    UIControl *mixToggle = [musicPage valueForKey:@"mix"];
    UIButton *clearButton = [UIButton new];
    BOOL canMove = [musicList tableView:musicTable canMoveRowAtIndexPath:row(upcomingSection, 0)];
    check(canMove && reorderGrip != nil &&
          !musicTable.delaysContentTouches &&
          [musicTable touchesShouldCancelInContentView:mixToggle] &&
          [musicTable touchesShouldCancelInContentView:clearButton] &&
          ![musicTable touchesShouldCancelInContentView:reorderGrip],
          [NSString stringWithFormat:@"Music queue cell mounts a real reorder grip that starts dragging without touch delay while toggles still scroll (sec=%ld canMove=%d cell=%d grip=%@ delay=%d)",
           (long)upcomingSection, canMove, firstCell != nil, reorderGrip, musicTable.delaysContentTouches]);
    check(!outer.delaysContentTouches && outer.panGestureRecognizer.enabled,
          @"Music queue clears outer scroll view touch delay while mounted");
    [musicList tableView:musicTable willBeginReorderingRowAtIndexPath:row(upcomingSection, 0)];
    BOOL pausedDuringReorder = !outer.panGestureRecognizer.enabled;
    [musicList tableView:musicTable moveRowAtIndexPath:row(upcomingSection, 0) toIndexPath:row(upcomingSection, 1)];
    [musicList tableView:musicTable didEndReorderingRowAtIndexPath:row(upcomingSection, 1)];
    check(pausedDuringReorder && outer.panGestureRecognizer.enabled &&
          player.sentOverrideRestrictions && player.sentNextTracks.count == 2 &&
          player.sentNextTracks[0] == moveB && player.sentNextTracks[1] == moveA,
          @"Music queue pauses outer scroll pan during row reorder, submits moved track order, and restores pan on end");
    check([[mixToggle valueForKey:@"on"] boolValue],
          @"Music queue AutoMix toggle starts on when AutoMix and Spotify transitions are active");
    stubTransitionSettings = (SGTransitionSettings){NO, NO, 0};
    [NSNotificationCenter.defaultCenter postNotificationName:SGTransitionSettingsDidChangeNotification object:nil];
    check(![[mixToggle valueForKey:@"on"] boolValue],
          @"Music queue AutoMix toggle turns off when Spotify Playback disables both Automix and Crossfade");
    [mixToggle sendActionsForControlEvents:UIControlEventTouchUpInside];
    check(stubAutoMixApplies == 1 && stubAutoMixApplied && [[mixToggle valueForKey:@"on"] boolValue],
          @"tapping the AutoMix toggle after Spotify disabled transitions re-applies AutoMix");
    checkQueueVisibility(musicList, musicPage, outer);
    checkQueueDrag(musicList, musicPage, outer, past);
    [musicPage willMoveToParentViewController:nil];
    [musicPage.view removeFromSuperview];
    [musicPage removeFromParentViewController];
    [outer removeFromSuperview];
    check(outer.delaysContentTouches && outer.panGestureRecognizer.enabled,
          @"removing Music queue restores outer scroll view touch delay and pan");
    printf("queue checks: %d of %d right -- PASS\n", checked, checked);
    fflush(stdout);
    exit(0);
}
@interface QueueApp : UIResponder <UIApplicationDelegate>
@end
@implementation QueueApp
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    window.rootViewController = [UIViewController new];
    [window makeKeyAndVisible];
    [NSTimer scheduledTimerWithTimeInterval:0 repeats:NO block:^(NSTimer *timer) { run(); }];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 120 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        HARNESS_FAIL(@"queue checks did not finish");
    });
    return YES;
}
@end
int main(int argc, char **argv) {
    @autoreleasepool { return UIApplicationMain(argc, argv, nil, NSStringFromClass(QueueApp.class)); }
}
