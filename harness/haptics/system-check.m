#import <MediaAccessibility/MediaAccessibility.h>
#import "../harness-fail.h"

static BOOL background;
static int reads, extras, status, covers;
static void (^report)(NSString *, BOOL);
@interface HarnessManager : NSObject
+ (instancetype)sharedManager;
@property(readonly) BOOL isActive;
- (id)addStatusObserver:(void (^)(NSString *,BOOL))observer;
- (void)checkHapticTrackAvailabilityForMediaMatchingCode:(NSString *)s completionHandler:(void (^)(BOOL))done;
@end
@implementation HarnessManager
+ (instancetype)sharedManager { static HarnessManager *m; if (!m) m=[HarnessManager new]; return m; }
- (BOOL)isActive { reads++; return YES; }
- (id)addStatusObserver:(void (^)(NSString *,BOOL))observer { report = observer; return [NSObject new]; }
- (void)checkHapticTrackAvailabilityForMediaMatchingCode:(NSString *)s completionHandler:(void (^)(BOOL))done {
    HARNESS_FAIL(@"unexpected recording lookup");
}
@end
#define MAMusicHapticsManager HarnessManager
#define MAMusicHapticsManagerActiveStatusDidChangeNotification @"test.active"
#include "SystemMusicHaptics.m"
static id<SGPlayerStateObserver> playerObserver;
static NSString *uri;
NSNotificationName const SGMusicHapticsSwitchesChangedNotification = @"test.switch";
void SGMigrateMusicHaptics(void) {}
BOOL SGMusicHapticsInBackground(void) { return background; }
BOOL SGMusicHapticsListedByInstall(void) { return YES; }
void SGMusicHapticsSetSystemCovers(BOOL covered) { covers++; }
void SGSetMusicHapticsStatus(NSString *s) { status++; }
void SGSetSystemMusicHapticsOn(BOOL on) {}
void SGAddPlayerStateObserver(id<SGPlayerStateObserver> observer) { playerObserver = observer; }
NSString *SGURIString(id track) { return uri; }
SPTPlayerState *SGPlayerState(void) { return nil; }
void SGNowPlayingSetExtras(NSString *owner, NSDictionary *values, NSString *title) { extras++; }
void SGMotionSongsWithISRC(NSString *isrc, void (^done)(NSArray *songs)) { HARNESS_FAIL(@"unexpected catalog lookup"); }
dispatch_block_t SGSpotifyMetadataRequestAllowConstrained(NSString *path, NSData *body, BOOL allowed, SGSpotifyMetadataReply done) {
    HARNESS_FAIL(@"unexpected metadata lookup");
}

static void flip(BOOL on) {
    background = on;
    [NSNotificationCenter.defaultCenter postNotificationName:SGMusicHapticsSwitchesChangedNotification object:nil];
}
int main(void) { @autoreleasepool {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (reads || playerObserver) HARNESS_FAIL(@"system haptics active at off launch");
        flip(YES);
        if (!reads || !report || !playerObserver) HARNESS_FAIL(@"live enable did not observe playback and system status");
        // This status delivery is already headed to main when the switch goes off.
        report(@"old", YES);
        flip(NO);
        reads = extras = status = covers = 0;
        report(@"new", YES);
        uri = @"spotify:episode:new";
        [playerObserver playerStateDidChange:nil];
        [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationDidBecomeActiveNotification object:nil];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (reads || extras || status || covers)
                HARNESS_FAIL(@"disabled callbacks: %d manager reads, %d extras, %d status, %d covers", reads, extras, status, covers);
            flip(YES);
            if (!reads || !extras || !status || !covers) HARNESS_FAIL(@"re-enable did not follow the current track");
            puts("PASS off launch, zero callback work after disable, current track followed on re-enable");
            exit(0);
        });
    });
    [[NSRunLoop mainRunLoop] run];
    return 1;
} }
