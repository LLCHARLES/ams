#import <UIKit/UIKit.h>
#import "Core/SGCore.h"
#import "Shared/Player/PlayerState.h"
#import "Redesigned/Player/PlayerMix.h"
#import "Redesigned/Kit/SGRKit.h"
#import "../harness-fail.h"

@implementation SPTPlayerTrack
@end
@implementation SPTPlayerState
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
@interface QueueSnapshot : NSObject
@property SPTPlayerTrack *track;
@property NSArray *prevTracks;
@property NSArray *nextTracks;
@end
@implementation QueueSnapshot
@end
@interface QueuePlayer : NSObject
@property QueueSnapshot *currentQueue;
@property BOOL withoutQueueAPI;
@end
@implementation QueuePlayer
- (BOOL)respondsToSelector:(SEL)selector {
    if (selector == @selector(fetchQueue:on:) && self.withoutQueueAPI) return NO;
    return [super respondsToSelector:selector];
}
- (void)fetchQueue:(void (^)(id))callback on:(dispatch_queue_t)queue { callback(self.currentQueue); }
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
void SGAddPlayerStateObserver(id<SGPlayerStateObserver> observer) {
    if (!observers) observers = [NSHashTable weakObjectsHashTable];
    [observers addObject:observer];
}
NSString *SGURIString(id uri) { return [uri isKindOfClass:NSURL.class] ? [uri absoluteString] : uri; }
NSArray *SGPlayerUpcomingTracks(SPTPlayerState *value, NSUInteger limit) { return value.future ?: @[]; }
NSString *SGL(NSString *key, NSString *english) { return english; }
void SGPresentDark(UIViewController *controller) { controller.overrideUserInterfaceStyle = UIUserInterfaceStyleDark; }
UIViewController *SGTopController(void) { return window.rootViewController; }
UIColor *SGRPrimary(void) { return UIColor.whiteColor; }
UIColor *SGRSecondary(void) { return UIColor.grayColor; }
const CGFloat SGRGrid = 8;
UIFont *SGCategoryCappedFont(UIFontTextStyle style, UIFontWeight weight, UIContentSizeCategory largest) {
    return [UIFont preferredFontForTextStyle:style];
}
SGTransitionFacts *SGAutoMixCurrentTransition(void) { return nil; }
BOOL SGRMixShowsQueue(void) { return NO; }
BOOL SGRMixTrackIs(SPTPlayerTrack *track, NSString *uri, NSString *uid) { return NO; }
BOOL SGTransitionSettingsRead(SGTransitionSettings *settings) { return NO; }
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
static void spin(NSTimeInterval seconds) {
    [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:seconds]];
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
    check([titles(0) isEqual:@[@"Earlier", @"Recent"]] && [titles(1) isEqual:@[@"Current"]] &&
          [titles(2) isEqual:@[@"First occurrence", @"Second occurrence"]], @"Spotify History appears chronologically above current and Up Next");
    UITableView *table = screen.tableView;
    [table layoutIfNeeded];
    spin(0.3);
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
    spin(0.3);
    check(keptCover.cancelled, @"Playing Next leaving the screen cancels the covers still coming");
    // Back with the same cells: first the cancelled request is retried offline, then the failed request online.
    coversHeld = NO;
    offline = YES;
    NSUInteger cancelledAsks = [coverAsks countForObject:@"Kept"];
    [screen.navigationController popViewControllerAnimated:NO];
    spin(0.3);
    check(shown(row(2, 0)) && shown(row(2, 0)) != fetchedCover && [coverAsks countForObject:@"Kept"] == cancelledAsks + 1,
          @"back on screen offline, the cancelled cover is requested again but stays a placeholder");
    [screen.navigationController pushViewController:[UIViewController new] animated:NO];
    spin(0.3);
    offline = NO;
    NSUInteger keptAsks = [coverAsks countForObject:@"Kept"];
    [screen.navigationController popViewControllerAnimated:NO];
    spin(0.3);
    check(shown(row(2, 0)) == fetchedCover && [coverAsks countForObject:@"Kept"] == keptAsks + 1,
          [NSString stringWithFormat:@"Playing Next shown again retries the failed cover once and shows it (%lu asks)",
                                     (unsigned long)([coverAsks countForObject:@"Kept"] - keptAsks)]);
    NSUInteger asksShown = coverAsks.count, totalAsks = 0;
    for (NSString *title in coverAsks) totalAsks += [coverAsks countForObject:title];
    [screen.navigationController pushViewController:[UIViewController new] animated:NO];
    [screen.navigationController popViewControllerAnimated:NO];
    spin(0.3);
    NSUInteger totalAfter = 0;
    for (NSString *title in coverAsks) totalAfter += [coverAsks countForObject:title];
    check(coverAsks.count == asksShown && totalAfter == totalAsks, @"shown again with every cover in, no cover is asked for again");
    QueueTrack *late = song(@"late", @"Late");
    [late setValue:@"spotify:track:late" forKey:@"URI"];
    offline = YES;
    player.currentQueue.nextTracks = @[late];
    report(@"107");
    spin(0.3);
    NSIndexPath *path = row(2, 0);
    UITableViewCell *prepared = [table cellForRowAtIndexPath:path];
    check(prepared && shown(path) != fetchedCover && [coverAsks countForObject:@"Late"] > 0,
          @"the prepared row has a failed cover");
    offline = NO;
    // UIKit can redisplay this cell without asking the data source to configure it again.
    if ([table.delegate respondsToSelector:@selector(tableView:willDisplayCell:forRowAtIndexPath:)])
        [table.delegate tableView:table willDisplayCell:prepared forRowAtIndexPath:path];
    spin(0.3);
    check(shown(path) == fetchedCover, @"redisplay of the prepared row retries and shows its failed cover");
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
    dispatch_async(dispatch_get_main_queue(), ^{ run(); });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 15 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        HARNESS_FAIL(@"queue checks did not finish");
    });
    return YES;
}
@end
int main(int argc, char **argv) {
    @autoreleasepool { return UIApplicationMain(argc, argv, nil, NSStringFromClass(QueueApp.class)); }
}
