// Mod Settings > Listening stats (Shared/ListeningStats) in the simulator: the page on the real Settings/ framework,
// the recorder of ListeningStats.x fed player states by hand, and an export picked through the page's own picker
// delegate. The launch line plays actions, one every 0.7 s from 1 s in; screenshot after.
//
//     THEOS=$HOME/theos ./build-sim.sh && xcrun simctl install <udid> build/sim/ListeningStatsHarness.app
//     xcrun simctl launch <udid> com.retrine.listeningstatsharness [action...]
//
// Actions: erase (the log emptied), seed (a week, a month and a year of plays merged in), record (a track played
// 31 s, one played 5 s, one paused after 10 s for 10 s and played 25 s more, then playback stopped: takes 82 s, so put it
// last), pick (an extended export and a zip of a basic one handed to the picker's delegate as if picked),
// select=<section>.<row> (a tap on a row of the page on top), kind=<0 week|1 month|2 year>, back, forward (the period
// card's controls), pop, bottom, dump (the rows each section shows).
// showcase (four weeks of a chart and 40 days of last year merged in), chart=<0 songs|1 artists|2 albums> (that Top
// heading tapped; checks the chart page opens and ranks), story (Recap opened, last year's story played: checks it
// opens, moves on by VoiceOver's swipe and by itself after 6 s, and closes; takes 11 s), storyopen (only opens it).
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "../../harness-fail.h"
#import "../../harness-wait.h"
#import "../../timer-lifecycle.h"
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Shared/Player/PlayerState.h"
#import "Shared/ListeningStats/ListeningStats.h"
#import "Shared/ListeningStats/SGPlayLog.h"

extern id<SGPlayerStateObserver> SGHarnessObserver;

static void findViews(UIView *root, Class kind, NSMutableArray *found) {
    if ([root isKindOfClass:kind]) [found addObject:root];
    for (UIView *sub in root.subviews) findViews(sub, kind, found);
}

static SGPlay *play(int64_t end, int64_t ms, NSString *title, NSString *artist, NSString *album) {
    SGPlay *p = [SGPlay new];
    p.end = end; p.ms = ms; p.title = title; p.artist = artist; p.album = album; p.uri = @"";
    return p;
}

static SPTPlayerState *state(NSString *uri, NSString *title, NSString *artist, double duration, BOOL playing) {
    SPTPlayerTrack *track = [SPTPlayerTrack new];
    [track setValue:uri forKey:@"URI"];
    [track setValue:title forKey:@"trackTitle"];
    [track setValue:artist forKey:@"artistName"];
    [track setValue:@{@"artist_name": artist ?: @"", @"album_title": @"Harness Album"} forKey:@"metadata"];
    SPTPlayerState *s = [SPTPlayerState new];
    [s setValue:track forKey:@"track"];
    [s setValue:@(playing) forKey:@"isPlaying"];
    [s setValue:@(!playing) forKey:@"isPaused"];
    [s setValue:@(duration) forKey:@"duration"];
    return s;
}

// The simulator's picker is a remote service that may never appear, so the page's picker is kept rather than
// presented, and pick hands its delegate the files.
static UIDocumentPickerViewController *SGHarnessPicker;

@implementation UIViewController (Harness)
- (void)harness_present:(UIViewController *)page animated:(BOOL)animated completion:(void (^)(void))completion {
    if ([page isKindOfClass:UIDocumentPickerViewController.class]) SGHarnessPicker = (UIDocumentPickerViewController *)page;
    else [self harness_present:page animated:animated completion:completion];
}
@end

@interface AppDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@property (nonatomic, strong) UINavigationController *nav;
@end

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    NSArray<NSString *> *args = NSProcessInfo.processInfo.arguments;
    method_exchangeImplementations(class_getInstanceMethod(UIViewController.class, @selector(presentViewController:animated:completion:)),
                                   class_getInstanceMethod(UIViewController.class, @selector(harness_present:animated:completion:)));
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    NSArray<NSString *> *actions = [args subarrayWithRange:NSMakeRange(1, args.count - 1)];
    // erase and seed go before the page is built, so it opens on them.
    for (NSString *action in actions) if ([@[@"erase", @"seed", @"showcase"] containsObject:action]) [self run:action];
    self.nav = [[UINavigationController alloc] initWithRootViewController:SGListeningStatsPage()];
    self.window.rootViewController = self.nav;
    [self.window makeKeyAndVisible];
    __block NSUInteger i = 0;
    for (NSString *action in actions) {
        if ([@[@"erase", @"seed", @"showcase"] containsObject:action]) continue;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((1 + 0.7 * i++) * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            NSLog(@"[harness] %@", action);
            [self run:action];
        });
    }
    return YES;
}

- (UITableView *)table {
    return ((UITableViewController *)self.nav.topViewController).tableView;
}

// Each step of the script after the one before, in seconds from now.
- (void)after:(double)seconds do:(void (^)(void))block {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(seconds * NSEC_PER_SEC)), dispatch_get_main_queue(), block);
}

- (void)record {
    id<SGPlayerStateObserver> o = SGHarnessObserver;
    NSUInteger before = SGListeningLog().plays.count;
    [o playerStateDidChange:state(@"spotify:track:long", @"Played Long", @"Recorder", 200, YES)];
    [self after:31 do:^{ [o playerStateDidChange:state(@"spotify:track:skip", @"Skipped", @"Recorder", 200, YES)]; }];
    [self after:36 do:^{ [o playerStateDidChange:state(@"spotify:track:paused", @"Paused Between", @"Recorder", 200, YES)]; }];
    [self after:46 do:^{ [o playerStateDidChange:state(@"spotify:track:paused", @"Paused Between", @"Recorder", 200, NO)]; }];
    [self after:56 do:^{ [o playerStateDidChange:state(@"spotify:track:paused", @"Paused Between", @"Recorder", 200, YES)]; }];
    [self after:81 do:^{ [o playerStateDidChange:state(nil, nil, nil, 0, NO)]; }];
    [self after:82 do:^{
        NSArray<SGPlay *> *plays = SGListeningLog().plays;
        NSLog(@"[harness] record: %lu new plays (expected 2: Played Long about 31 s, Paused Between about 35 s; timers run late by up to a few percent)", (unsigned long)(plays.count - before));
        for (SGPlay *p in [plays subarrayWithRange:NSMakeRange(before, plays.count - before)]) {
            NSLog(@"[harness] recorded %@ / %@ / %@ / %@, %lld ms", p.uri, p.title, p.artist, p.album, p.ms);
        }
        [self.table reloadData];
    }];
}

// An extended export and a zip holding a basic one with one play the extended has and one it has not.
- (void)pick {
    NSString *dir = NSTemporaryDirectory();
    int64_t now = time(NULL);
    NSDateFormatter *f = [NSDateFormatter new];
    f.timeZone = [NSTimeZone timeZoneWithAbbreviation:@"UTC"];
    f.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    f.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss'Z'";
    NSString *ts = [f stringFromDate:[NSDate dateWithTimeIntervalSince1970:now - 3600]];
    NSArray *extended = @[@{@"ts": ts, @"ms_played": @180000, @"master_metadata_track_name": @"Imported Song",
                            @"master_metadata_album_artist_name": @"Exporter", @"master_metadata_album_album_name": @"Export Album",
                            @"spotify_track_uri": @"spotify:track:imported"}];
    NSURL *json = [NSURL fileURLWithPath:[dir stringByAppendingPathComponent:@"Streaming_History_Audio_2026.json"]];
    [[NSJSONSerialization dataWithJSONObject:extended options:0 error:nil] writeToURL:json atomically:YES];
    // A stored zip of one file, written by hand: the simulator has no zip tool to run.
    f.dateFormat = @"yyyy-MM-dd HH:mm";
    NSArray *basic = @[@{@"endTime": [f stringFromDate:[NSDate dateWithTimeIntervalSince1970:now - 3600]], @"artistName": @"Exporter",
                         @"trackName": @"Imported Song", @"msPlayed": @180000},
                       @{@"endTime": [f stringFromDate:[NSDate dateWithTimeIntervalSince1970:now - 7200]], @"artistName": @"Exporter",
                         @"trackName": @"Only In Basic", @"msPlayed": @90000}];
    NSData *body = [NSJSONSerialization dataWithJSONObject:basic options:0 error:nil];
    NSData *name = [@"Spotify Account Data/StreamingHistory_music_0.json" dataUsingEncoding:NSUTF8StringEncoding];
    uint32_t crc = 0;   // not checked by the reader
    NSMutableData *zip = [NSMutableData data];
    void (^u16)(uint32_t) = ^(uint32_t v) { uint16_t x = (uint16_t)v; [zip appendBytes:&x length:2]; };
    void (^u32)(uint32_t) = ^(uint32_t v) { [zip appendBytes:&v length:4]; };
    u32(0x04034b50); u16(10); u16(0); u16(0); u16(0); u16(0); u32(crc); u32((uint32_t)body.length); u32((uint32_t)body.length);
    u16((uint32_t)name.length); u16(0); [zip appendData:name]; [zip appendData:body];
    uint32_t central = (uint32_t)zip.length;
    u32(0x02014b50); u16(20); u16(10); u16(0); u16(0); u16(0); u16(0); u32(crc); u32((uint32_t)body.length); u32((uint32_t)body.length);
    u16((uint32_t)name.length); u16(0); u16(0); u16(0); u16(0); u32(0); u32(0); [zip appendData:name];
    uint32_t centralSize = (uint32_t)zip.length - central;
    u32(0x06054b50); u16(0); u16(0); u16(1); u16(1); u32(centralSize); u32(central); u16(0);
    NSURL *zipURL = [NSURL fileURLWithPath:[dir stringByAppendingPathComponent:@"my_spotify_data.zip"]];
    [zip writeToURL:zipURL atomically:YES];

    // The import row presents the picker; it is handed the files the way the system would.
    UIDocumentPickerViewController *picker = SGHarnessPicker;
    NSLog(@"[harness] presented %@, multiple %d", NSStringFromClass(picker.class), picker.allowsMultipleSelection);
    [picker.delegate documentPicker:picker didPickDocumentsAtURLs:@[json, zipURL]];
    // The import row while the files are read, before the merge comes back, and the guard against a second pick.
    UITableView *table = self.table;
    NSIndexPath *importRow = [NSIndexPath indexPathForRow:0 inSection:8];   // Import history
    UITableViewCell *row = [table.dataSource tableView:table cellForRowAtIndexPath:importRow];
    SGHarnessPicker = nil;
    [table.delegate tableView:table didSelectRowAtIndexPath:importRow];
    NSLog(@"[harness] importing: the row reads \"%@\", a second tap %@", [(UILabel *)row.accessoryView text],
          SGHarnessPicker ? @"opens the picker again" : @"is ignored");
    [self after:1.5 do:^{
        UITableViewCell *after = [table.dataSource tableView:table cellForRowAtIndexPath:importRow];
        NSLog(@"[harness] imported: the row reads \"%@\"", [(UILabel *)after.accessoryView text]);
    }];
    [self after:2 do:^{
        UIAlertController *alert = (UIAlertController *)self.nav.presentedViewController;
        NSLog(@"[harness] import says \"%@\": %@", alert.title, alert.message);
    }];
}

// The chart's four weeks, ending a minute ago: moves up and down, New entries and runs in the top 5. Then 40 days
// of last year, for a recap with every card.
- (void)showcase {
    int64_t now = time(NULL), week = 7 * 86400;
    NSDictionary<NSString *, NSArray<NSString *> *> *songs = @{
        @"Kyoto": @[@"Phoebe Bridgers", @"Punisher"], @"Garden Song": @[@"Phoebe Bridgers", @"Punisher"],
        @"Nobody": @[@"Mitski", @"Be the Cowboy"], @"Be Sweet": @[@"Japanese Breakfast", @"Jubilee"],
        @"Paprika": @[@"Japanese Breakfast", @"Jubilee"], @"Sunblind": @[@"Fleet Foxes", @"Shore"],
        @"Simulation Swarm": @[@"Big Thief", @"Dragon New Mountain I Believe In You"], @"Change": @[@"Big Thief", @"Dragon New Mountain I Believe In You"],
        @"715 - CREEKS": @[@"Bon Iver", @"22, A Million"]};
    NSArray<NSDictionary<NSString *, NSNumber *> *> *weeks = @[
        @{@"Kyoto": @9, @"Be Sweet": @7, @"Nobody": @6, @"Paprika": @5, @"Garden Song": @4, @"Simulation Swarm": @3, @"Change": @2, @"715 - CREEKS": @1},
        @{@"Kyoto": @7, @"Nobody": @5, @"Garden Song": @4, @"Be Sweet": @3, @"Sunblind": @2, @"Simulation Swarm": @1},
        @{@"Kyoto": @6, @"Garden Song": @4, @"Nobody": @2},
        @{@"Kyoto": @5, @"Garden Song": @3}];
    NSMutableArray<SGPlay *> *plays = [NSMutableArray array];
    [weeks enumerateObjectsUsingBlock:^(NSDictionary<NSString *, NSNumber *> *counts, NSUInteger back, BOOL *stop) {
        __block int64_t end = now - 60 - (int64_t)back * week;
        [counts enumerateKeysAndObjectsUsingBlock:^(NSString *title, NSNumber *count, BOOL *inner) {
            for (int i = 0; i < count.intValue; i++) {
                [plays addObject:play(end, 200000 + (int64_t)title.length * 4000, title, songs[title][0], songs[title][1])];
                end -= 240;   // apart by more than the 90 s in which an import takes the same song for a duplicate
            }
        }];
    }];
    NSCalendar *calendar = NSCalendar.currentCalendar;
    NSDateInterval *lastYear = SGPeriodStep(SGStatsPeriodYear, NSDate.date, -1, calendar);
    // Paprika and Change are left for this week's discoveries.
    NSArray<NSString *> *titles = @[@"Kyoto", @"Nobody", @"Be Sweet", @"Garden Song", @"Sunblind", @"Simulation Swarm", @"715 - CREEKS"];
    for (NSInteger day = 0; day < 40; day++) {
        // Runs of days through the year, 9 in a row in March, in the evening mostly.
        NSInteger offset = day < 9 ? 60 + day : 60 + day * 7;
        NSDate *date = [calendar dateByAddingUnit:NSCalendarUnitDay value:offset toDate:lastYear.startDate options:0];
        for (NSInteger i = 0; i < 2 + day % 4; i++) {
            NSString *title = titles[(NSUInteger)((day + i * i) % (NSInteger)titles.count)];
            NSDate *end = [calendar dateBySettingHour:(i % 3 ? 22 : 8) minute:10 + i * 5 second:0 ofDate:date options:0];
            [plays addObject:play((int64_t)end.timeIntervalSince1970, 210000, title, songs[title][0], songs[title][1])];
        }
    }
    [SGListeningLog() merge:plays completion:^(NSUInteger added, NSError *error) {
        if (error) HARNESS_FAIL(@"showcase merge failed: %@", error);
        NSLog(@"[harness] showcase merged %lu", (unsigned long)added);
    }];
}

// The Top heading of `kind` tapped as a finger would; its chart is checked once loaded.
- (void)chart:(NSInteger)kind {
    UITableView *table = self.table;
    UIView *heading = [table.delegate tableView:table viewForHeaderInSection:2 + kind];
    if (![heading isKindOfClass:UIButton.class]) HARNESS_FAIL(@"the Top heading of section %ld is %@, not a button", (long)(2 + kind), heading.class);
    NSLog(@"[harness] heading \"%@\", hint \"%@\"", heading.accessibilityLabel, heading.accessibilityHint);
    [(UIButton *)heading sendActionsForControlEvents:UIControlEventTouchUpInside];
    NSString *expected = @[@"Top tracks", @"Top artists", @"Top albums"][(NSUInteger)kind];
    HarnessWhen(@"chart page finished navigation and ranked its entries", ^BOOL {
        if (![self.nav.topViewController.title isEqual:expected] || self.nav.transitionCoordinator ||
            self.table.numberOfSections <= 1 || ![self.table numberOfRowsInSection:1]) return NO;
        UITableViewCell *list = [self.table.dataSource tableView:self.table cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:1]];
        NSMutableArray *entries = [NSMutableArray array];
        findViews(list, NSClassFromString(@"SGChartEntryView"), entries);
        return entries.count != 0;
    }, ^{
        UIViewController *top = self.nav.topViewController;
        if (![top.title isEqualToString:expected]) HARNESS_FAIL(@"the heading opened \"%@\", not %@", top.title, expected);
        UITableView *chart = self.table;
        UITableViewCell *list = [chart.dataSource tableView:chart cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:1]];
        NSMutableArray<UIView *> *entries = [NSMutableArray array];
        findViews(list, NSClassFromString(@"SGChartEntryView"), entries);
        NSMutableArray<NSString *> *spoken = [NSMutableArray array];
        for (UIView *entry in entries) [spoken addObject:[NSString stringWithFormat:@"%@ = %@", entry.accessibilityLabel, entry.accessibilityValue]];
        NSInteger rows = (NSInteger)entries.count;
        if (!rows) HARNESS_FAIL(@"the chart ranks nothing");
        UITableViewCell *summary = [chart.dataSource tableView:chart cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];
        NSMutableArray<UILabel *> *labels = [NSMutableArray array];
        findViews(summary, UILabel.class, labels);
        NSLog(@"[harness] chart \"%@\": summary %@; %ld rows: %@", top.title, [[labels valueForKey:@"text"] componentsJoinedByString:@" | "], (long)rows,
              [spoken componentsJoinedByString:@"; "]);
        NSLog(@"[harness] PASS the heading opens its chart");
    });
}

// Recap opened from the page, then the first year with a recap.
- (void)openStory:(void (^)(UIViewController *story))then {
    [self.table.delegate tableView:self.table didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:5]];
    HarnessWhen(@"Recap year list", ^BOOL {
        return [self.nav.topViewController.title isEqual:@"Recap"] && !self.nav.transitionCoordinator && [self.table numberOfRowsInSection:0] > 0;
    }, ^{
        UITableView *years = self.table;
        if (![self.nav.topViewController.title isEqualToString:@"Recap"]) HARNESS_FAIL(@"the Recap row opened \"%@\"", self.nav.topViewController.title);
        for (NSInteger row = 0; row < [years numberOfRowsInSection:0]; row++) {
            NSIndexPath *path = [NSIndexPath indexPathForRow:row inSection:0];
            UITableViewCell *cell = [years.dataSource tableView:years cellForRowAtIndexPath:path];
            NSMutableArray<UILabel *> *labels = [NSMutableArray array];
            findViews(cell, UILabel.class, labels);
            // Beside the title, or under it at the accessibility text sizes.
            NSString *value = [cell.accessoryView isKindOfClass:UILabel.class] ? [(UILabel *)cell.accessoryView text]
                : [[(UIListContentConfiguration *)cell.contentConfiguration secondaryText] componentsSeparatedByString:@"\n"].lastObject;
            NSLog(@"[harness] recap year row: %@ = %@", [[labels valueForKey:@"text"] componentsJoinedByString:@" | "], value);
            if (![value isEqualToString:@"Play"]) continue;
            [years.delegate tableView:years didSelectRowAtIndexPath:path];
            HarnessWhen(@"story presented", ^BOOL {
                return self.nav.presentedViewController.viewIfLoaded.window && !self.nav.presentedViewController.transitionCoordinator;
            }, ^{
                UIViewController *story = self.nav.presentedViewController;
                if (![NSStringFromClass(story.class) isEqualToString:@"SGRecapStoryController"]) HARNESS_FAIL(@"the year opened %@", story.class);
                then(story);
            });
            return;
        }
        HARNESS_FAIL(@"no year has a recap");
    });
}

- (void)story {
    [self openStory:^(UIViewController *story) {
        NSUInteger count = [[story valueForKey:@"count"] unsignedIntegerValue];
        if ([[story valueForKey:@"index"] unsignedIntegerValue] != 0 || count < 3) HARNESS_FAIL(@"the story opened on card %@ of %lu", [story valueForKey:@"index"], (unsigned long)count);
        NSMutableArray<UIView *> *strips = [NSMutableArray array];
        findViews(story.view, NSClassFromString(@"SGStoryProgress"), strips);
        UIView *strip = strips.firstObject;
        [strip accessibilityIncrement];
        if ([[story valueForKey:@"index"] unsignedIntegerValue] != 1) HARNESS_FAIL(@"VoiceOver's swipe up did not move on");
        NSLog(@"[harness] story: %lu cards, now %@ (%@)", (unsigned long)count, strip.accessibilityValue, strip.accessibilityLabel);
        [self after:6.6 do:^{
            if ([[story valueForKey:@"index"] unsignedIntegerValue] != 2) HARNESS_FAIL(@"the story did not move on by itself after 6 s (card %@)", [story valueForKey:@"index"]);
            NSLog(@"[harness] story moved on by itself to %@", strip.accessibilityValue);
            NSMutableArray<UIButton *> *buttons = [NSMutableArray array];
            findViews(story.view, UIButton.class, buttons);
            for (UIButton *button in buttons) if ([button.accessibilityLabel isEqualToString:@"Close"]) [button sendActionsForControlEvents:UIControlEventTouchUpInside];
            HarnessWhen(@"story dismissed", ^BOOL { return !self.nav.presentedViewController; }, ^{
                if (self.nav.presentedViewController) HARNESS_FAIL(@"Close left %@ up", self.nav.presentedViewController.class);
                NSLog(@"[harness] PASS the story opens, moves on and closes");
            });
        }];
    }];
}

- (void)storyBackground {
    Method factory = class_getClassMethod(CADisplayLink.class, @selector(displayLinkWithTarget:selector:));
    IMP original = method_getImplementation(factory);
    NSMutableArray<CADisplayLink *> *links = [NSMutableArray array];
    IMP capture = imp_implementationWithBlock(^CADisplayLink *(id cls, id target, SEL selector) {
        CADisplayLink *link = ((id (*)(id, SEL, id, SEL))original)(cls, @selector(displayLinkWithTarget:selector:), target, selector);
        [links addObject:link];
        return link;
    });
    method_setImplementation(factory, capture);
    [self openStory:^(UIViewController *story) {
        method_setImplementation(factory, original);
        imp_removeBlock(capture);
        HARNESS_CHECK(links.count == 1);
        CADisplayLink *link = links.firstObject;
        HARNESS_CHECK(!link.paused);
        SGHarnessBeginTimerCapture();
        NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
        [center postNotificationName:UIApplicationWillResignActiveNotification object:nil];
        HARNESS_CHECK(link.paused);
        sg_testAppState = UIApplicationStateBackground;
        [center postNotificationName:UIApplicationDidEnterBackgroundNotification object:nil];
        HARNESS_CHECK(link.paused);
        sg_testAppState = UIApplicationStateActive;
        [center postNotificationName:UIApplicationDidBecomeActiveNotification object:nil];
        HARNESS_CHECK(!link.paused);
        [story viewWillDisappear:NO];
        [center postNotificationName:UIApplicationDidBecomeActiveNotification object:nil];
        HARNESS_CHECK(link.paused);
        [story viewDidAppear:NO];
        HARNESS_CHECK(!link.paused);
        SGHarnessEndTimerCapture();
        puts("PASS recap display link pauses in background and resumes only when visible");
        exit(0);
    }];
}

- (void)run:(NSString *)action {
    NSArray<NSString *> *parts = [action componentsSeparatedByString:@"="];
    NSString *verb = parts.firstObject, *value = parts.count > 1 ? parts[1] : @"";
    UITableView *table = self.table;
    if ([verb isEqualToString:@"erase"]) {
        [SGListeningLog() erase];
    } else if ([verb isEqualToString:@"seed"]) {
        int64_t now = time(NULL), day = 86400;
        NSMutableArray *plays = [NSMutableArray array];
        for (int i = 0; i < 12; i++) [plays addObject:play(now - day - i * 400, 210000, @"Midnight City", @"M83", @"Hurry Up, We're Dreaming")];
        for (int i = 0; i < 7; i++) [plays addObject:play(now - 2 * day - i * 400, 250000, @"Windowlicker", @"Aphex Twin", @"Windowlicker")];
        for (int i = 0; i < 5; i++) [plays addObject:play(now - 3 * day - i * 400, 300000, @"Teardrop", @"Massive Attack", @"Mezzanine")];
        for (int i = 0; i < 9; i++) [plays addObject:play(now - 20 * day - i * 400, 240000, @"Angel", @"Massive Attack", @"Mezzanine")];
        for (int i = 0; i < 30; i++) [plays addObject:play(now - 200 * day - i * 400, 200000, @"Xtal", @"Aphex Twin", @"Selected Ambient Works 85-92")];
        [plays addObject:play(now - 500 * day, 3600000, @"A Very Long Title That Will Not Fit On One Line Of The Row", @"Someone With A Long Name", @"")];
        [SGListeningLog() merge:plays completion:^(NSUInteger added, NSError *error) {
            if (error) { NSLog(@"[harness] seed failed: %@", error); exit(1); }
            NSLog(@"[harness] seeded %lu", (unsigned long)added);
        }];
    } else if ([verb isEqualToString:@"showcase"]) {
        [self showcase];
    } else if ([verb isEqualToString:@"chart"]) {
        [self chart:value.integerValue];
    } else if ([verb isEqualToString:@"story"]) {
        [self story];
    } else if ([verb isEqualToString:@"storybackground"]) {
        [self storyBackground];
    } else if ([verb isEqualToString:@"storyopen"]) {
        [self openStory:^(UIViewController *story) { NSLog(@"[harness] story open"); }];
    } else if ([verb isEqualToString:@"storyshare"]) {
        // Share tapped on the first card; the image handed to the share sheet is read back.
        [self openStory:^(UIViewController *story) {
            NSMutableArray<UIButton *> *buttons = [NSMutableArray array];
            findViews(story.view, UIButton.class, buttons);
            for (UIButton *button in buttons) if ([button.accessibilityLabel isEqualToString:@"Share card"]) [button sendActionsForControlEvents:UIControlEventTouchUpInside];
            [self after:2 do:^{
                NSString *tmp = NSTemporaryDirectory();
                for (NSString *path in [NSFileManager.defaultManager subpathsAtPath:tmp]) {
                    if (![path.lastPathComponent hasPrefix:@"Retrine-Recap-"]) continue;
                    UIImage *image = [UIImage imageWithContentsOfFile:[tmp stringByAppendingPathComponent:path]];
                    NSLog(@"[harness] shared %@: %.0f x %.0f px under %@", path.lastPathComponent, image.size.width * image.scale, image.size.height * image.scale,
                          story.presentedViewController.class);
                }
            }];
        }];
    } else if ([verb isEqualToString:@"record"]) {
        [self record];
    } else if ([verb isEqualToString:@"pick"]) {
        [self pick];
    } else if ([verb isEqualToString:@"select"]) {
        NSArray<NSString *> *at = [value componentsSeparatedByString:@"."];
        [table.delegate tableView:table didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:at[1].integerValue inSection:at[0].integerValue]];
    } else if ([verb isEqualToString:@"kind"] || [verb isEqualToString:@"back"] || [verb isEqualToString:@"forward"]) {
        // The period card's controls, tapped as a finger would.
        NSMutableArray<UIControl *> *controls = [NSMutableArray array];
        findViews(table, UIControl.class, controls);
        for (UIControl *control in controls) {
            if ([verb isEqualToString:@"kind"] && [control isKindOfClass:UISegmentedControl.class]) {
                ((UISegmentedControl *)control).selectedSegmentIndex = value.integerValue;
                [control sendActionsForControlEvents:UIControlEventValueChanged];
            } else if (![verb isEqualToString:@"kind"] && [control isKindOfClass:UIButton.class] && control.accessibilityLabel.length &&
                       [control.accessibilityLabel hasPrefix:[verb isEqualToString:@"back"] ? @"Previous" : @"Next"]) {
                NSLog(@"[harness] %@ enabled %d", control.accessibilityLabel, control.enabled);
                [control sendActionsForControlEvents:UIControlEventTouchUpInside];
            }
        }
    } else if ([verb isEqualToString:@"pop"]) {
        [self.nav popViewControllerAnimated:YES];
    } else if ([verb isEqualToString:@"bottom"]) {
        CGFloat max = MAX(-table.adjustedContentInset.top, table.contentSize.height - table.bounds.size.height + table.adjustedContentInset.bottom);
        [table setContentOffset:CGPointMake(0, max) animated:NO];
    } else if ([verb isEqualToString:@"dump"]) {
        for (NSInteger section = 0; section < table.numberOfSections; section++) {
            NSMutableArray<NSString *> *rows = [NSMutableArray array];
            for (NSInteger row = 0; row < [table numberOfRowsInSection:section]; row++) {
                UITableViewCell *cell = [table.dataSource tableView:table cellForRowAtIndexPath:[NSIndexPath indexPathForRow:row inSection:section]];
                NSMutableArray<UILabel *> *labels = [NSMutableArray array];
                findViews(cell, UILabel.class, labels);
                NSMutableArray<NSString *> *texts = [NSMutableArray array];
                for (UILabel *label in labels) if (label.text.length) [texts addObject:label.text];
                [rows addObject:[texts componentsJoinedByString:@" | "]];
            }
            NSLog(@"[harness] section %ld: %@", (long)section, [rows componentsJoinedByString:@", "]);
        }
    }
}

@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(AppDelegate.class));
    }
}
