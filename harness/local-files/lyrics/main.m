// The native look's lyrics page for a local file (Native/LocalFiles/LocalLyricsPage.m) and the Imported
// LRC files page (Shared/LocalFiles/LocalLyricsPage.m), as the tweak compiles them, over a stand-in for
// Spotify's player that plays a local file with an LRC file linked to it. The clock is the harness's own
// and runs at four times the song's speed, so a few seconds cover the lines. Each step logs a SHOT for
// build.sh's screenshot and PASS or FAIL for what it checks.
#import <UIKit/UIKit.h>
#import "Shared/LocalFiles/LocalFiles.h"
#import "Shared/LocalFiles/LocalLyrics.h"
#import "Native/LocalFiles/LocalLyrics.h"
#import "Shared/Player/PlayerState.h"
#import "../../harness-fail.h"
#include <stdatomic.h>

#pragma mark - the player, standing in

__attribute__((objc_runtime_name("SPTPlayerTrack")))
@interface SGFakeTrack : NSObject
@property (nonatomic, copy) NSString *URI, *trackTitle, *artistName;
@property (nonatomic, copy) NSDictionary *metadata;
@end
@implementation SGFakeTrack
@end

__attribute__((objc_runtime_name("_TtC20NowPlaying_ModesImpl18FooterElementsUnit")))
@interface SGFakeFooter : UIViewController
@end
@implementation SGFakeFooter
- (void)viewDidLoad { [super viewDidLoad]; }
@end

@interface SGFakeState : NSObject
@property (nonatomic, strong) SGFakeTrack *track;
@property (nonatomic) BOOL isPaused;
@property (nonatomic) double positionAsOfTimestamp;
@end
@implementation SGFakeState
static CFTimeInterval sg_started;
- (BOOL)isPlaying { return !self.isPaused; }
- (BOOL)isLoading { return NO; }
- (double)playbackSpeed { return 4; }
- (double)position {
    return self.positionAsOfTimestamp + (CACurrentMediaTime() - sg_started) * 4;
}
@end

static SGFakeState *sg_state;
SPTPlayerState *SGPlayerState(void) { return (SPTPlayerState *)sg_state; }
NSString *SGURIString(id uri) { return [uri isKindOfClass:NSString.class] ? uri : nil; }
static NSHashTable<id<SGPlayerStateObserver>> *observers;
void SGAddPlayerStateObserver(id<SGPlayerStateObserver> observer) {
    if (!observers) observers = [NSHashTable weakObjectsHashTable];
    [observers addObject:observer];
}
static void report(void) {
    for (id<SGPlayerStateObserver> observer in observers.allObjects) {
        if ([observer respondsToSelector:@selector(playerStateDidReport:)]) [observer playerStateDidReport:SGPlayerState()];
        [observer playerStateDidChange:SGPlayerState()];
    }
}

// What LyricsSources.m and KaraokeSource.x give the tweak.
@implementation SGLyricsResult
@end
@implementation SGLyricsQuery
@end
NSArray<NSString *> *SGLyricsOrder(void) { return @[]; }
void SGLyricsSetOrder(NSArray<NSString *> *keys) {}
SGLyricsProvider *SGLyricsProviderFor(NSString *key) { return nil; }
void SGLyricsPageLines(NSArray<SGKaraokeLine *> *lines, NSArray<NSNumber *> **starts, NSArray<NSString *> **texts) {
    *starts = @[];
    *texts = @[];
}
SPTPlayerTrack *SGKaraokeTrackFor(NSString *trackID) { return nil; }
// SGTTML.m reads it for a translation in the language the Lyrics page asks for, which this page of lines does not show.
NSString *SGLyricsTranslationLanguage(void) { return nil; }
NSInteger SGKaraokeDelayMs(void) { return [NSUserDefaults.standardUserDefaults integerForKey:SGKeyLyricsDelay]; }
NSNotificationName const SGLyricsOffsetsDidChangeNotification = @"harness.offsets";
NSNotificationName const SGLyricsPinDidChangeNotification = @"harness.pin";
NSNotificationName const SGLyricsSourceChosenNotification = @"harness.choice";
static NSString *sg_pinKey;
NSString *SGKaraokePlayingTrack(void) {
    NSString *uri = sg_state.track.URI;
    return [uri hasPrefix:@"spotify:track:"] ? [uri substringFromIndex:@"spotify:track:".length] : SGLocalFileLyricsKey(uri);
}
NSNumber *SGLyricsPinnedID(NSString *trackID) { return [trackID isEqual:sg_pinKey] ? @42 : nil; }
NSString *SGLyricsChosenSource(NSString *trackID) { return nil; }

#pragma mark - the run

static void say(NSString *what) {
    printf("[harness] %s\n", what.UTF8String);
    fflush(stdout);
}

static void check(BOOL ok, NSString *what) {
    say([NSString stringWithFormat:@"%@ %@", ok ? @"PASS" : @"FAIL", what]);
}

static void after(NSTimeInterval seconds, dispatch_block_t block) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(seconds * NSEC_PER_SEC)), dispatch_get_main_queue(), block);
}

static NSArray<UILabel *> *labelsIn(UIView *view) {
    NSMutableArray<UILabel *> *found = [NSMutableArray array];
    for (UIView *sub in view.subviews) {
        if ([sub isKindOfClass:UIStackView.class]) {
            for (UIView *line in ((UIStackView *)sub).arrangedSubviews) [found addObject:(UILabel *)line];
        }
        [found addObjectsFromArray:labelsIn(sub)];
    }
    return found;
}

static BOOL sg_race;
static atomic_uint sg_aRequests;
static dispatch_semaphore_t sg_releaseFirstA;
static __weak UIViewController *sg_racePage;

static void playRaceTrack(NSString *name) {
    SGFakeTrack *track = [SGFakeTrack new];
    track.URI = [@"spotify:local:Harness:Race:" stringByAppendingString:name];
    track.trackTitle = name;
    track.artistName = @"Harness";
    sg_state.track = track;
    report();
}

static SGLyricsResult *raceLyrics(NSString *text) {
    SGKaraokeWord *word = [SGKaraokeWord new];
    word.text = text;
    SGKaraokeLine *line = [SGKaraokeLine new];
    line.words = @[word];
    line.timing = SGKaraokeTimingNone;
    SGLyricsResult *result = [SGLyricsResult new];
    result.karaokeLines = @[line];
    return result;
}

// The first A lookup is held until the second A is displayed. Spotify's state and the viewer's real
// reports drive A -> B -> A; no private viewer method or state is changed by the test.
static SGLyricsResult *heldRaceAnswer(NSString *title) {
    if ([title isEqual:@"B"]) {
        dispatch_async(dispatch_get_main_queue(), ^{ playRaceTrack(@"A"); });
        return raceLyrics(@"Track B");
    }
    unsigned request = atomic_fetch_add(&sg_aRequests, 1);
    if (request == 0) {
        dispatch_async(dispatch_get_main_queue(), ^{ playRaceTrack(@"B"); });
        HARNESS_CHECK(dispatch_semaphore_wait(sg_releaseFirstA, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)) == 0);
        dispatch_async(dispatch_get_main_queue(), ^{
            after(0.5, ^{
                NSArray *texts = [labelsIn(sg_racePage.view) valueForKey:@"text"];
                HARNESS_CHECK([texts isEqual:@[@"Current A"]]);
                HARNESS_CHECK(![[sg_racePage valueForKey:@"timer"] isValid]);
                say(@"PASS A -> B -> A keeps only the current lyrics batch");
                exit(0);
            });
        });
        return raceLyrics(@"Stale A");
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        after(0.5, ^{
            HARNESS_CHECK([[labelsIn(sg_racePage.view) valueForKey:@"text"] isEqual:@[@"Current A"]]);
            dispatch_semaphore_signal(sg_releaseFirstA);
        });
    });
    return raceLyrics(@"Current A");
}

void SGHarnessPlaybackLyricsFetch(NSString *key, NSString *path, void (^done)(SGLyricsResult *)) {
    if (!sg_race) { SGPlaybackLyricsFetch(key,path,done); return; }
    NSString *title = sg_state.track.trackTitle;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        SGLyricsResult *result = heldRaceAnswer(title);
        dispatch_async(dispatch_get_main_queue(), ^{ done(result); });
    });
}

void SGLyricsFetch(NSString *key, void (^done)(SGLyricsResult *)) {
    HARNESS_CHECK([key isEqual:sg_pinKey]);
    done(raceLyrics(@"Provider choice"));
}

static void paste(NSString *words, NSString *uri) {
    SGImportPastedLyrics(words,uri,^(NSString *name, NSError *error) {
        HARNESS_CHECK(name != nil);
    });
}
static void footerCheck(UIViewController *footer) {
    UIButton *button = nil;
    for (UIView *view in footer.view.subviews) if ([view isKindOfClass:UIButton.class]) button = (UIButton *)view;
    HARNESS_CHECK(button && button.hidden);
    SGFakeTrack *local = [SGFakeTrack new];
    local.URI = @"spotify:local:Singer:Album:Tagged:120"; local.trackTitle = @"Tagged"; local.artistName = @"Singer";
    local.metadata = @{@"local_file_path":[NSBundle.mainBundle pathForResource:@"tagged" ofType:@"flac"]};
    NSDictionary *tagPath = local.metadata;
    SGFakeTrack *song = [SGFakeTrack new];
    song.URI = @"spotify:track:7aQAZv5XfpQF63U7lgN6w5"; song.trackTitle = @"Tagged"; song.artistName = @"Singer";
    BOOL (^shows)(NSString *) = ^BOOL(NSString *line) {
        return [[labelsIn(footer.presentedViewController.view) valueForKey:@"text"] isEqual:@[line]];
    };
    // Check after UIKit and the worker's main-queue deliveries get their turns. A nested
    // run loop inside a main queue block cannot service another block on that queue.
    __block unsigned step = 0;
    CFRunLoopObserverRef observer = CFRunLoopObserverCreateWithHandler(NULL, kCFRunLoopBeforeWaiting, true, 0,
        ^(CFRunLoopObserverRef obs, CFRunLoopActivity activity) {
        switch (step) {
            case 0:
                if (button.hidden) return;
                step++; [button sendActionsForControlEvents:UIControlEventTouchUpInside]; break;
            case 1:
                if (!shows(@"Plain text")) return;
                step++;
                SGImportPastedLyrics(@"[ti:Tagged]\n[ar:Singer]\n[00:01]Matched by name", nil, ^(NSString *name,NSError *error) {
                    HARNESS_CHECK(name); step++;
                });
                break;
            case 2: return;
            case 3:
                if (!shows(@"Plain text")) return;
                step++; local.metadata = @{}; report(); break;
            case 4:
                if (!shows(@"Matched by name")) return;
                step++; local.metadata = tagPath; report(); break;
            case 5:
                if (!shows(@"Plain text")) return;
                step++; paste(@"Linked local", local.URI); break;
            case 6:
                if (!shows(@"Linked local")) return;
                step++; sg_state.track = song; report(); HARNESS_CHECK(button.hidden);
                paste(@"Listener's song", song.URI); break;
            case 7:
                if (button.hidden || !shows(@"Listener's song")) return;
                step++; sg_pinKey = @"7aQAZv5XfpQF63U7lgN6w5";
                [NSNotificationCenter.defaultCenter postNotificationName:SGLyricsPinDidChangeNotification object:sg_pinKey];
                break;
            case 8:
                if (!shows(@"Provider choice")) return;
                say(@"PASS Native footer and viewer: tag alone, link over tag over name, ordinary link, pin over import");
                exit(0);
        }
    });
    CFRunLoopAddObserver(CFRunLoopGetMain(),observer,kCFRunLoopCommonModes);
    CFRelease(observer);
    sg_state.track = local; report();
    after(10, ^{ HARNESS_FAIL(@"Native footer/viewer step %u", step); });
}

@interface SGHarnessDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation SGHarnessDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    NSString *uri = @"spotify:local:Retrine:Demos:A+Song+of+Our+Own:120";
    SGFakeTrack *track = [SGFakeTrack new];
    track.URI = uri;
    track.trackTitle = @"A Song of Our Own";
    track.artistName = @"Retrine";
    sg_state = [SGFakeState new];
    sg_state.track = track;

    NSString *documents = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    [NSFileManager.defaultManager removeItemAtPath:[documents stringByAppendingPathComponent:@"Retrine/Lyrics"] error:nil];
    [NSUserDefaults.standardUserDefaults removeObjectForKey:SGKeyImportedLRCLinks];
    NSMutableString *sheet = [NSMutableString string];
    for (NSInteger i = 0; i < 24; i++) {
        [sheet appendFormat:@"[00:%02ld.00]Line %ld of the song, long enough to wrap onto a second row here\n", (long)(i * 2), (long)i + 1];
    }
    NSURL *file = [[NSURL fileURLWithPath:NSTemporaryDirectory()] URLByAppendingPathComponent:@"Retrine - A Song of Our Own.lrc"];
    [sheet writeToURL:file atomically:YES encoding:NSUTF8StringEncoding error:nil];
    NSString *mode = NSProcessInfo.processInfo.arguments.count > 1 ? NSProcessInfo.processInfo.arguments[1] : @"page";
    if (![@[@"race", @"footer"] containsObject:mode]) SGImportLRC(file, uri, ^(NSString *name, NSError *error) {
        check(name != nil, @"imported and linked");
    });

    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    UIViewController *player = [mode isEqual:@"footer"] ? [SGFakeFooter new] : [UIViewController new];
    player.view.backgroundColor = UIColor.darkGrayColor;
    self.window.rootViewController = player;
    [self.window makeKeyAndVisible];

    if ([mode isEqual:@"footer"]) {
        after(1, ^{ footerCheck(player); });
        return YES;
    }
    if ([mode isEqualToString:@"race"]) {
        sg_race = YES;
        sg_releaseFirstA = dispatch_semaphore_create(0);
        playRaceTrack(@"A");
        after(1, ^{
            UIViewController *page = SGLocalLyricsPage();
            sg_racePage = page;
            [player presentViewController:page animated:NO completion:nil];
        });
        after(7, ^{ HARNESS_FAIL(@"lyrics race check did not finish"); });
        return YES;
    }
    if ([mode isEqualToString:@"settings"]) {
        after(1, ^{
            UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:SGImportedLRCPage()];
            nav.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
            [player presentViewController:nav animated:NO completion:nil];
            after(1.5, ^{
                say(@"SHOT settings");
                after(1, ^{ exit(0); });
            });
        });
        return YES;
    }

    after(1, ^{
        sg_started = CACurrentMediaTime();
        UIViewController *page = SGLocalLyricsPage();
        [player presentViewController:page animated:NO completion:nil];
        after(0.3, ^{ say(@"SHOT start"); });
        // 3 s at four times speed is 12 s of song: line 7 (from 12 s) is being sung.
        after(3, ^{
            NSArray<UILabel *> *lines = labelsIn(page.view);
            check(lines.count == 24, [NSString stringWithFormat:@"24 lines shown (%lu)", (unsigned long)lines.count]);
            UILabel *lit = nil;
            for (UILabel *line in lines) {
                if (line.alpha == 1) lit = line;
            }
            check([lit.text hasPrefix:@"Line 7 "], [NSString stringWithFormat:@"line 7 lit (%@)", lit.text]);
            say(@"SHOT playing");
            sg_state.isPaused = YES;
            sg_state.positionAsOfTimestamp = 17;
            report();
            HARNESS_CHECK(lines[8].alpha == 1 && ![[page valueForKey:@"timer"] isValid]);
            sg_state.positionAsOfTimestamp = 5;
            report();
            HARNESS_CHECK(lines[2].alpha == 1);
            [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationWillResignActiveNotification object:nil];
            sg_state.positionAsOfTimestamp = 1;
            [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationDidBecomeActiveNotification object:nil];
            HARNESS_CHECK(lines[0].alpha == 1);
            sg_state.isPaused = NO;
            sg_started = CACurrentMediaTime();
            report();
            HARNESS_CHECK([[page valueForKey:@"timer"] isValid]);
            after(4, ^{
                say(@"SHOT later");
                // Another track with nothing linked or matching.
                SGFakeTrack *other = [SGFakeTrack new];
                other.URI = @"spotify:local:Someone:Else:Untitled:90";
                other.trackTitle = @"Untitled";
                other.artistName = @"Someone";
                sg_state.track = other;
                report();
                after(1, ^{
                    check(labelsIn(page.view).count == 0, @"a track with no file shows no lines");
                    say(@"SHOT none");
                    [page dismissViewControllerAnimated:NO completion:nil];
                    after(0.5, ^{ exit(0); });
                });
            });
        });
    });
    return YES;
}

@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(SGHarnessDelegate.class));
    }
}
