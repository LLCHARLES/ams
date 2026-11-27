// The one thing the mod says for itself, unasked: a release newer than this build is out. Nobody
// opens Mod Settings to look, so the check runs on its own a few seconds after Spotify comes up and
// a release nobody has been told about brings a sheet -- once per release, and never over the
// welcome tour, the signing fix or anything else holding the screen, which it waits out. Tell me
// when one is out on the Updates page switches it off; the page and the row are still there.
#import "Core/SGCore.h"
#import "Settings/SGPageStyle.h"
#import "About.h"
#import "App/Onboarding/Onboarding.h"

static NSString *const kTold = @"spotifyglass.update.told";
static const NSTimeInterval kSettle = 6;   // after the app comes up, for its own screens to land
static const NSTimeInterval kRetry = 4;
static const NSInteger kTries = 15;        // a minute of waiting for the screen, then not this run

static BOOL sg_offered;   // once a run, whatever else happens

// Everything that has changed since this build, newest release first, which is what the sheet counts
// and reads the first lines of.
static NSArray<SGUpdateChange *> *changesSinceThisBuild(void) {
    NSMutableArray<SGUpdateChange *> *changes = [NSMutableArray array];
    for (SGUpdateRelease *release in SGUpdateReleases()) {
        if (!SGUpdateIsNewer(release.version)) break;
        [changes addObjectsFromArray:release.changes];
    }
    return changes;
}

// Three lines and a count: enough to know whether to care, with the whole changelog a tap away.
static NSString *noticeBody(NSString *version, BOOL beta) {
    NSArray<SGUpdateChange *> *changes = changesSinceThisBuild();
    NSMutableString *body = [NSMutableString stringWithFormat:SGL(@"settings.mod.update.notice.current_build", @"This build is %s."), SG_VERSION];
    if (beta) [body appendString:SGL(@"settings.mod.update.notice.beta_explanation", @" This one is a beta, a test build ahead of the next release.")];
    NSUInteger shown = MIN(changes.count, (NSUInteger)3);
    for (NSUInteger i = 0; i < shown; i++) [body appendFormat:@"\n\n• %@", changes[i].text];
    if (changes.count > shown) [body appendFormat:SGL(@"settings.mod.update.notice.more_changes", @"\n\nand %lu more in %@."), (unsigned long)(changes.count - shown), version];
    return body;
}

static void offerWhenClear(NSInteger tries) {
    if (sg_offered) return;
    NSString *version = SGUpdateVersion();
    if (!version || !SGEnabled(SGKeyUpdateNotice)) return;
    if ([[NSUserDefaults.standardUserDefaults stringForKey:kTold] isEqualToString:version]) return;
    UIViewController *top = SGTopController();
    // The tour, the signing sheet and Spotify's own alerts own the screen first; a sheet presented
    // from one of them lands nowhere, so this one waits its turn and gives up rather than nagging.
    if (!top || SGOnboardingShowing() || [top isKindOfClass:UIAlertController.class]) {
        if (tries <= 0) {
            SGLog(@"update notice: the screen stayed busy, %@ waits for Mod Settings", version);
            return;
        }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kRetry * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            offerWhenClear(tries - 1);
        });
        return;
    }

    sg_offered = YES;
    // Told before it is read, not after: a sheet dismissed by a tap outside it, or by Spotify going
    // away under it, is still a sheet this release has had.
    [NSUserDefaults.standardUserDefaults setObject:version forKey:kTold];
    SGUpdateRelease *release = SGUpdateNewestRelease();
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:SGL(@"settings.mod.update.notice.alert.title", @"%@ is out"), version]
                                                                  message:noticeBody(version, release.prerelease)
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [sheet addAction:[UIAlertAction actionWithTitle:SGL(@"settings.mod.update.notice.action.whats_new", @"What's new") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        // The sheet is still going as this runs, so the page waits for the screen it is pushed onto.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            SGShowPage(SGTopController(), SGUpdatePage());
        });
    }]];
    if (release.url.length)
        [sheet addAction:[UIAlertAction actionWithTitle:SGL(@"settings.mod.update.notice.action.get_it", @"Get it") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            SGOpenURL(release.url);
        }]];
    [sheet addAction:[UIAlertAction actionWithTitle:SGL(@"settings.mod.update.notice.action.not_now", @"Not now") style:UIAlertActionStyleCancel handler:nil]];
    SGPresentDark(sheet);
    [top presentViewController:sheet animated:YES completion:nil];
    SGLog(@"update notice: offered %@ over %@", version, NSStringFromClass(top.class));
}

void SGWatchForUpdates(void) {
    // Once per launch, a few seconds after Spotify first comes to the front.
    __block __weak id active;
    active = [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification
                                                    object:nil
                                                     queue:NSOperationQueue.mainQueue
                                                usingBlock:^(NSNotification *note) {
        [NSNotificationCenter.defaultCenter removeObserver:active];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kSettle * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (!SGEnabled(SGKeyUpdateNotice)) return;
            BOOL checking = SGCheckForUpdate(NO);
            if (SGUpdateVersion()) {   // the last check knows one already
                offerWhenClear(kTries);
            }
            // A cached release told on a previous launch does not consume this
            // launch's offer. The check may find one the user has not seen.
            if (checking && !sg_offered) {
                __block __weak id landed;
                landed = [NSNotificationCenter.defaultCenter addObserverForName:SGUpdateCheckedNotification
                                                                                    object:nil
                                                                                     queue:NSOperationQueue.mainQueue
                                                                                usingBlock:^(NSNotification *n) {
                    [NSNotificationCenter.defaultCenter removeObserver:landed];
                    offerWhenClear(kTries);
                }];
            }
        });
    }];
}
